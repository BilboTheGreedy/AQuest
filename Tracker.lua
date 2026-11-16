local _, ns = ...
local UI = ns.UI
local C = UI.colors

local Tracker = {}
ns.Tracker = Tracker

local frame
local lines = {}
local WIDTH = 250

local function line(i)
	local l = lines[i]
	if l then return l end
	l = CreateFrame("Button", nil, frame)
	l:SetHeight(15)
	l.text = UI.Text(l, "GameFontHighlightSmall")
	l.text:SetPoint("LEFT", 0, 0)
	l.text:SetPoint("RIGHT", 0, 0)
	l.dot = l:CreateTexture(nil, "ARTWORK")
	l.dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMaskSmall")
	l.dot:SetSize(8, 8)
	l.dot:SetPoint("LEFT", 0, 0)
	l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	l:RegisterForDrag("LeftButton")
	l:SetScript("OnDragStart", function() frame:StartDrag() end)
	l:SetScript("OnDragStop", function() frame:StopDrag() end)
	l:SetScript("OnClick", function(self, button)
		if not self.quest then
			ns.Journal.Show()
			return
		end
		if button == "RightButton" then
			local id = self.quest
			UI.Menu(self, {
				{ text = ns.QuestTitle(id), title = true },
				{ text = "Open in journal", func = function() ns.Journal.ShowQuest(id) end },
				{ text = "Show on map", func = function() Tracker.ShowOnMap(id) end },
				{ text = "Stop tracking", func = function() Tracker.SetTracked(id, false) end },
				{ text = "Options", title = true },
				UI.Check(ns.db.trackerDb, "locked", "Lock the tracker"),
				{ text = "Hide the tracker", func = function()
					ns.db.tracker = false
					ns:Fire("OPTIONS")
				end },
			})
		else
			ns.Journal.ShowQuest(self.quest)
		end
	end)
	lines[i] = l
	return l
end

local function watched(id)
	if C_QuestLog and C_QuestLog.GetQuestWatchType then
		local ok, kind = pcall(C_QuestLog.GetQuestWatchType, id)
		if ok and kind ~= nil then return true end
	end
	if IsQuestWatched and GetQuestLogIndexByID then
		local ok, index = pcall(GetQuestLogIndexByID, id)
		if ok and type(index) == "number" and index > 0 then
			local ok2, w = pcall(IsQuestWatched, index)
			if ok2 and w then return true end
		end
	end
	return false
end

function Tracker.Tracked(id)
	return ns.chardb.tracked[id] or watched(id)
end

function Tracker.SetTracked(id, on)
	ns.chardb.tracked[id] = on and true or nil
	if on then
		if C_QuestLog and C_QuestLog.AddQuestWatch then pcall(C_QuestLog.AddQuestWatch, id) end
	else
		if C_QuestLog and C_QuestLog.RemoveQuestWatch then pcall(C_QuestLog.RemoveQuestWatch, id) end
	end
	Tracker.Refresh()
	ns:Fire("TRACK_CHANGED")
end

function Tracker.ShowOnMap(id)
	local e = ns.Log.quests[id]
	local q = ns.Quest(id)
	if not q then return end
	local map
	if e and not e.complete then
		for _, npc in ipairs(q.oc or {}) do
			local n = ns.Npc(npc)
			if n then map = next(n.spawns) end
			if map then break end
		end
		if not map and q.oi then
			local it = ns.Item(q.oi[1])
			local n = it and it.npcs[1] and ns.Npc(it.npcs[1])
			if n then map = next(n.spawns) end
			if not map then
				local o = it and it.objects[1] and ns.Object(it.objects[1])
				if o then map = next(o.spawns) end
			end
		end
		if not map and q.oo then
			local o = ns.Object(q.oo[1])
			if o then map = next(o.spawns) end
		end
	end
	if not map then
		local _, m = ns.FinisherPlace(q)
		if e then map = m end
	end
	if not map then
		local _, m = ns.StarterPlace(q)
		map = m
	end
	ns.Pins.ShowOnMap(map)
end

local function build()
	frame = CreateFrame("Frame", "AQuestTracker", UIParent)
	frame:SetSize(WIDTH, 20)
	frame:SetFrameStrata("LOW")
	UI.Movable(frame, ns.db.trackerDb)
	frame.head = CreateFrame("Button", nil, frame)
	frame.head:SetPoint("TOPLEFT")
	frame.head:SetPoint("TOPRIGHT")
	frame.head:SetHeight(18)
	frame.head:RegisterForDrag("LeftButton")
	frame.head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame.head:SetScript("OnDragStart", function() frame:StartDrag() end)
	frame.head:SetScript("OnDragStop", function() frame:StopDrag() end)
	frame.head:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			UI.Menu(self, ns.Options())
		else
			ns.Journal.Toggle()
		end
	end)
	frame.title = UI.Text(frame.head, "GameFontNormalSmall", "LEFT", C.accent)
	frame.title:SetPoint("LEFT", 0, 0)
	frame.count = UI.Text(frame.head, "GameFontDisableSmall", "RIGHT", C.dim)
	frame.count:SetPoint("RIGHT", 0, 0)
	local rule = UI.Tex(frame, "ARTWORK", C.line)
	rule:SetPoint("TOPLEFT", 0, -18)
	rule:SetPoint("TOPRIGHT", 0, -18)
	rule:SetHeight(1)
end

function Tracker.Refresh()
	if not ns.db then return end
	if not ns.db.tracker then
		if frame then frame:Hide() end
		return
	end
	if not frame then build() end
	local n = 0
	local y = -22
	local tracked = 0
	for _, id in ipairs(ns.Log.order) do
		if Tracker.Tracked(id) then
			tracked = tracked + 1
			local e = ns.Log.quests[id]
			local q = e.data
			local level = q and ns.QuestLevel(q) or e.level or 0
			if type(level) ~= "number" then level = 0 end
			n = n + 1
			local l = line(n)
			l.quest = id
			l:ClearAllPoints()
			l:SetPoint("TOPLEFT", 0, y)
			l:SetPoint("RIGHT", 0, 0)
			local r, g, b = ns.QuestColor(id)
			l.dot:SetVertexColor(r, g, b)
			l.dot:Show()
			l.text:ClearAllPoints()
			l.text:SetPoint("LEFT", 13, 0)
			l.text:SetPoint("RIGHT", 0, 0)
			local dr, dg, db = ns.DifficultyColor(level)
			l.text:SetTextColor(dr, dg, db)
			l.text:SetText("[" .. level .. "] " .. (e.title or ns.QuestTitle(id)) .. (e.complete and "  (done)" or ""))
			l:Show()
			y = y - 15
			if not e.complete then
				for _, o in ipairs(e.objectives) do
					n = n + 1
					local ol = line(n)
					ol.quest = id
					ol:ClearAllPoints()
					ol:SetPoint("TOPLEFT", 0, y)
					ol:SetPoint("RIGHT", 0, 0)
					ol.dot:Hide()
					ol.text:ClearAllPoints()
					ol.text:SetPoint("LEFT", 13, 0)
					ol.text:SetPoint("RIGHT", 0, 0)
					if o.done then
						ol.text:SetTextColor(0.35, 0.8, 0.35)
					else
						ol.text:SetTextColor(C.text[1], C.text[2], C.text[3])
					end
					ol.text:SetText(o.text)
					ol:Show()
					y = y - 14
				end
			end
			y = y - 4
		end
	end
	if tracked == 0 and ns.Log.count > 0 then
		n = n + 1
		local l = line(n)
		l.quest = nil
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", 0, y)
		l:SetPoint("RIGHT", 0, 0)
		l.dot:Hide()
		l.text:ClearAllPoints()
		l.text:SetPoint("LEFT", 0, 0)
		l.text:SetPoint("RIGHT", 0, 0)
		l.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
		l.text:SetText("Nothing tracked. Click here to pick quests.")
		l:Show()
		y = y - 16
	end
	for i = n + 1, #lines do lines[i]:Hide() end
	frame.title:SetText("Quests")
	frame.count:SetText(tracked .. " / " .. ns.Log.count)
	frame:SetHeight(-y + 2)
	frame:SetShown(ns.Log.count > 0)
end

ns:Listen("LOG_CHANGED", function()
	for id in pairs(ns.chardb.tracked) do
		if not ns.Log.quests[id] then ns.chardb.tracked[id] = nil end
	end
	Tracker.Refresh()
end)
ns:On("QUEST_WATCH_LIST_CHANGED", function() ns.Debounce("watch", 0.2, Tracker.Refresh) end)
ns:On("QUEST_WATCH_UPDATE", function() ns.Debounce("watch", 0.2, Tracker.Refresh) end)
ns:Listen("OPTIONS", Tracker.Refresh)
ns:Listen("LAYOUT_RESET", function()
	if frame then frame:Restore() end
end)
