local _, ns = ...

local Log = { quests = {}, order = {}, npcs = {}, count = 0 }
ns.Log = Log

local EMPTY = {}
local doneCache = {}

function ns.Done(id)
	if doneCache[id] then return true end
	local done
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
		done = ok and v
	elseif IsQuestFlaggedCompleted then
		done = IsQuestFlaggedCompleted(id)
	end
	if done and not ns.IsSecret(done) then
		doneCache[id] = true
		return true
	end
	return false
end

local function objectives(id, index)
	local out = {}
	local list
	if C_QuestLog and C_QuestLog.GetQuestObjectives then
		local ok, l = pcall(C_QuestLog.GetQuestObjectives, id)
		if ok then list = l end
	end
	if type(list) == "table" then
		for _, o in ipairs(list) do
			if type(o) == "table" and type(o.text) == "string" and not ns.IsSecret(o.text) then
				out[#out + 1] = {
					text = o.text, type = o.type, done = o.finished and true or false,
					have = o.numFulfilled, need = o.numRequired,
				}
			end
		end
	elseif GetNumQuestLeaderBoards and index then
		for i = 1, GetNumQuestLeaderBoards(index) or 0 do
			local text, kind, finished = GetQuestLogLeaderBoard(i, index)
			if text then out[#out + 1] = { text = text, type = kind, done = finished and true or false } end
		end
	end
	return out
end

local function entries()
	local out = {}
	local n = 0
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
		n = C_QuestLog.GetNumQuestLogEntries() or 0
	elseif GetNumQuestLogEntries then
		n = GetNumQuestLogEntries() or 0
	end
	for i = 1, n do
		if C_QuestLog and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID and not info.isHidden then
				local complete
				if C_QuestLog.IsComplete then complete = C_QuestLog.IsComplete(info.questID) end
				out[#out + 1] = { id = info.questID, title = info.title, level = info.level, index = i, complete = complete, failed = info.isFailed }
			end
		elseif GetQuestLogTitle then
			local title, level, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
			if title and not isHeader and questID and questID > 0 then
				out[#out + 1] = { id = questID, title = title, level = level, index = i, complete = isComplete == 1 or isComplete == true, failed = isComplete == -1 }
			end
		end
	end
	return out
end

local function addNpc(npc, quest, text)
	local l = Log.npcs[npc]
	if not l then
		l = {}
		Log.npcs[npc] = l
	end
	l[#l + 1] = { quest = quest, text = text }
end

function ns.ObjectiveFor(entry, name)
	if not name or name == "" then return nil end
	local lname = name:lower()
	for _, o in ipairs(entry.objectives) do
		if o.text:lower():find(lname, 1, true) then return o end
	end
	return nil
end

local function signature()
	local parts = {}
	for _, id in ipairs(Log.order) do
		local e = Log.quests[id]
		parts[#parts + 1] = id .. (e.complete and "c" or "")
		for _, o in ipairs(e.objectives) do parts[#parts + 1] = o.text .. (o.done and "d" or "") end
	end
	return table.concat(parts, "|")
end

local last
function Log.Scan(force)
	local ok, list = pcall(entries)
	if not ok then list = {} end
	Log.quests = {}
	Log.order = {}
	Log.npcs = {}
	for _, e in ipairs(list) do
		if not Log.quests[e.id] then
			e.objectives = objectives(e.id, e.index)
			if e.complete == nil or ns.IsSecret(e.complete) then
				local all = true
				for _, o in ipairs(e.objectives) do
					if not o.done then all = false break end
				end
				e.complete = all
			end
			e.data = ns.Quest(e.id)
			Log.quests[e.id] = e
			Log.order[#Log.order + 1] = e.id
			local q = e.data
			if q and not e.complete then
				for _, npc in ipairs(q.oc or EMPTY) do
					local n = ns.Npc(npc)
					local o = n and ns.ObjectiveFor(e, n.name)
					if not o or not o.done then addNpc(npc, e, o and o.text) end
				end
				for _, npc in ipairs(q.ok or EMPTY) do addNpc(npc, e) end
				for _, item in ipairs(q.oi or EMPTY) do
					local it = ns.Item(item)
					if it then
						local o = ns.ObjectiveFor(e, it.name)
						if not o or not o.done then
							for _, npc in ipairs(it.npcs) do addNpc(npc, e, o and o.text or it.name) end
						end
					end
				end
			end
		end
	end
	Log.count = #Log.order
	local sig = signature()
	if force or sig ~= last then
		last = sig
		ns:Fire("LOG_CHANGED")
	end
end

function Log.Has(id)
	return Log.quests[id] ~= nil
end

local function repOk(req, max)
	if not C_Reputation or not C_Reputation.GetFactionDataByID then return true end
	local ok, data = pcall(C_Reputation.GetFactionDataByID, req[1])
	if not ok or type(data) ~= "table" or type(data.currentStanding) ~= "number" then return true end
	if max then return data.currentStanding < req[2] end
	return data.currentStanding >= req[2]
end

function ns.Unavailable(q)
	local id = q.id
	if Log.quests[id] then return "In your quest log" end
	if ns.Done(id) and not q.rep then return "Completed" end
	if not ns.ForPlayer(q) then return "Not for your race or class" end
	local level = ns.playerLevel or 60
	if (q.m or 0) > level then return "Requires level " .. q.m end
	if q.x and level > q.x then return "Only up to level " .. q.x end
	if q.ps then
		local any = false
		for _, pre in ipairs(q.ps) do
			if ns.Done(pre) then any = true break end
		end
		if not any then return "Requires: " .. ns.QuestTitle(q.ps[1]) end
	end
	if q.pg then
		for _, pre in ipairs(q.pg) do
			if not ns.Done(math.abs(pre)) then return "Requires: " .. ns.QuestTitle(math.abs(pre)) end
		end
	end
	if q.ex then
		for _, other in ipairs(q.ex) do
			if ns.Done(other) or Log.quests[other] then return "Replaced by: " .. ns.QuestTitle(other) end
		end
	end
	if q.pq and not Log.quests[q.pq] then return "Needs active quest: " .. ns.QuestTitle(q.pq) end
	if q.nx and (ns.Done(q.nx) or Log.quests[q.nx]) then return "Already further in the chain" end
	if q.rr and not repOk(q.rr) then return "Needs more reputation" end
	if q.rx and not repOk(q.rx, true) then return "Reputation too high" end
	return nil
end

function ns.Shown(q)
	if q.h then return false end
	if q.rep and not ns.db.repeatable then return false end
	if not ns.db.trivial and ns.Trivial(q) then return false end
	return ns.Unavailable(q) == nil
end

local function player()
	ns.playerLevel = UnitLevel and UnitLevel("player") or 60
	if type(ns.playerLevel) ~= "number" or ns.playerLevel < 1 then ns.playerLevel = 60 end
	local _, _, race = UnitRace("player")
	ns.playerRace = race
	local _, _, class = UnitClass("player")
	ns.playerClassID = class
end

local function rescan()
	ns.Debounce("log", 0.3, function() Log.Scan() end)
end

ns:Listen("LOGIN", function()
	player()
	Log.Scan(true)
end)

ns:On("PLAYER_ENTERING_WORLD", function()
	player()
	rescan()
end)
ns:On("QUEST_LOG_UPDATE", rescan)
ns:On("QUEST_ACCEPTED", rescan)
ns:On("QUEST_REMOVED", rescan)
ns:On("UNIT_QUEST_LOG_CHANGED", rescan)
ns:On("QUEST_TURNED_IN", function(id)
	if type(id) == "number" then doneCache[id] = true end
	ns.Debounce("log", 0.3, function() Log.Scan(true) end)
end)
ns:On("PLAYER_LEVEL_UP", function(level)
	if type(level) == "number" then ns.playerLevel = level end
	ns.Debounce("log", 0.3, function() Log.Scan(true) end)
end)
