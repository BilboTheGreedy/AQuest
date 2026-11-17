local _, ns = ...

local Log = { quests = {}, order = {}, npcs = {}, items = {}, count = 0, rev = 0 }
ns.Log = Log

local EMPTY = {}
local doneCache = {}
local seeded = false

local function seed()
	if not C_QuestLog or not C_QuestLog.GetAllCompletedQuestIDs then return end
	local ok, list = pcall(C_QuestLog.GetAllCompletedQuestIDs)
	if not ok or type(list) ~= "table" or ns.IsSecret(list) then return end
	for _, id in ipairs(list) do
		if type(id) == "number" then doneCache[id] = true end
	end
	seeded = #list > 0
end

function ns.Done(id)
	if doneCache[id] then return true end
	if seeded then return false end
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
				local complete, failed
				if C_QuestLog.IsComplete then complete = C_QuestLog.IsComplete(info.questID) end
				if C_QuestLog.IsFailed then failed = C_QuestLog.IsFailed(info.questID) end
				if ns.IsSecret(failed) then failed = nil end
				out[#out + 1] = { id = info.questID, title = info.title, level = info.level, index = i, complete = complete, failed = failed and true or false }
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

function ns.ObjectiveFor(entry, name, kind, n)
	local cand
	if kind and n then
		local seen = 0
		for _, o in ipairs(entry.objectives) do
			if o.type == kind then
				seen = seen + 1
				if seen == n then cand = o break end
			end
		end
	end
	if name and name ~= "" then
		local lname = name:lower()
		if cand and cand.text:lower():find(lname, 1, true) then return cand end
		local other
		for _, o in ipairs(entry.objectives) do
			if o.text:lower():find(lname, 1, true) then
				if not kind or o.type == kind then return o end
				other = other or o
			end
		end
		if other then return other end
	end
	return cand
end

function ns.CountType(entry, kind)
	local n = 0
	for _, o in ipairs(entry.objectives) do
		if o.type == kind then n = n + 1 end
	end
	return n
end

local function addItem(item, quest, text)
	local l = Log.items[item]
	if not l then
		l = {}
		Log.items[item] = l
	end
	l[#l + 1] = { quest = quest, text = text }
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

local last, lastSet
function Log.Scan(force)
	local ok, list = pcall(entries)
	if not ok then list = {} end
	Log.quests = {}
	Log.order = {}
	Log.npcs = {}
	Log.items = {}
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
				local slots = q.oc and #q.oc or 0
				for i, npc in ipairs(q.oc or EMPTY) do
					local n = ns.Npc(npc)
					local o = ns.ObjectiveFor(e, n and n.name, "monster", i)
					if not o or not o.done then addNpc(npc, e, o and o.text) end
				end
				local exact = q.ok and ns.CountType(e, "monster") == slots + #q.ok
				for i, group in ipairs(q.ok or EMPTY) do
					local o = exact and ns.ObjectiveFor(e, nil, "monster", slots + i) or nil
					if not o or not o.done then
						for _, npc in ipairs(group) do addNpc(npc, e, o and o.text) end
					end
				end
				for i, item in ipairs(q.oi or EMPTY) do
					local it = ns.Item(item)
					local o = ns.ObjectiveFor(e, it and it.name, "item", i)
					if not o or not o.done then
						local text = o and o.text or (it and it.name)
						addItem(item, e, text)
						for _, npc in ipairs(it and it.npcs or EMPTY) do addNpc(npc, e, text) end
					end
				end
			end
		end
	end
	Log.count = #Log.order
	local set = table.concat(Log.order, ",")
	if force or set ~= lastSet then
		lastSet = set
		Log.rev = Log.rev + 1
	end
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

local skills
local function skillRank(id)
	if not skills then
		skills = { known = false }
		if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
			local ok, n = pcall(C_SkillInfo.GetNumSkillLines)
			if ok and type(n) == "number" and n > 0 then
				skills.known = true
				for i = 1, n do
					local ok2, line = pcall(C_SkillInfo.GetSkillLineInfo, i)
					if ok2 and type(line) == "table" then
						if line.isHeader and line.isCollapsed then skills.known = false end
						if type(line.skillID) == "number" and type(line.rank) == "number" then skills[line.skillID] = line.rank end
					end
				end
			end
		elseif GetProfessions and GetProfessionInfo then
			local res = { pcall(GetProfessions) }
			if res[1] then
				skills.known = true
				for i = 2, 6 do
					if res[i] then
						local ok2, _, _, rank, _, _, _, line = pcall(GetProfessionInfo, res[i])
						if ok2 and type(line) == "number" and type(rank) == "number" then skills[line] = rank end
					end
				end
			end
		end
	end
	if skills[id] then return skills[id] end
	if skills.known then return false end
	return nil
end

local SEASONAL = { [-22] = true, [-364] = true, [-366] = true, [-369] = true, [-370] = true }

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
	if q.sk then
		local rank = skillRank(q.sk[1])
		if rank == false then return "Needs a profession" end
		if rank and rank < (q.sk[2] or 0) then return "Needs skill " .. q.sk[2] end
	end
	return nil
end

function ns.Shown(q)
	if q.h then return false end
	if q.rep and not ns.db.repeatable then return false end
	if not ns.db.trivial and ns.Trivial(q) then return false end
	if not ns.db.seasonal and q.z and SEASONAL[q.z] then return false end
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

local wantForce = false
local function rescan(force)
	if force then wantForce = true end
	ns.Debounce("log", 0.3, function()
		local f = wantForce
		wantForce = false
		Log.Scan(f)
	end)
end

ns:Listen("LOGIN", function()
	player()
	seed()
	Log.Scan(true)
end)

ns:On("PLAYER_ENTERING_WORLD", function()
	player()
	rescan()
end)
ns:On("QUEST_LOG_UPDATE", function() rescan() end)
ns:On("QUEST_ACCEPTED", function() rescan() end)
ns:On("QUEST_REMOVED", function() rescan() end)
ns:On("UNIT_QUEST_LOG_CHANGED", function(unit)
	if unit == nil or unit == "player" then rescan() end
end)
ns:On("QUEST_TURNED_IN", function(id)
	if type(id) == "number" then doneCache[id] = true end
	rescan(true)
	ns.Debounce("seed", 2, seed)
end)
ns:On("PLAYER_LEVEL_UP", function(level)
	if type(level) == "number" then ns.playerLevel = level end
	rescan(true)
end)
ns:On("SKILL_LINES_CHANGED", function()
	skills = nil
	ns.Debounce("skills", 2, function() rescan(true) end)
end)
ns:On("UPDATE_FACTION", function()
	ns.Debounce("rep", 10, function()
		if InCombatLockdown and InCombatLockdown() then return end
		rescan(true)
	end)
end)
