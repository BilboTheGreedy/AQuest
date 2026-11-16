local _, ns = ...
local UI = ns.UI
local C = UI.colors

local Journal = {}
ns.Journal = Journal

local frame
local state = { zone = "log", query = "", stack = {}, hideDone = false }

local STATE_ICON = {
	log = "Interface\\GossipFrame\\IncompleteQuestIcon",
	ready = "Interface\\GossipFrame\\ActiveQuestIcon",
	available = "Interface\\GossipFrame\\AvailableQuestIcon",
	done = "Interface\\RaidFrame\\ReadyCheck-Ready",
}

function ns.CanWaypoint()
	return (AWay and AWay.Add) or (AMap and AMap.SetWaypoint) or false
end

function ns.Waypoint(map, x, y, title)
	if AWay and AWay.Add then return AWay.Add(map, x, y, title) and true or false end
	if AMap and AMap.SetWaypoint then return AMap.SetWaypoint(map, x, y, title) and true or false end
	return false
end

local function questState(q)
	local e = ns.Log.quests[q.id]
	if e then return e.complete and "ready" or "log", e.complete and "Ready to turn in" or "In your quest log" end
	if ns.Done(q.id) and not q.rep then return "done", "Completed" end
	local why = ns.Unavailable(q)
	if why then return "locked", why end
	return "available", "Available"
end

local function wrap(text, width)
	local out, cur = {}, ""
	for word in text:gmatch("%S+") do
		if #cur + #word + 1 > width and cur ~= "" then
			out[#out + 1] = cur
			cur = word
		else
			cur = cur == "" and word or (cur .. " " .. word)
		end
	end
	if cur ~= "" then out[#out + 1] = cur end
	return out
end

local function placeRow(label, name, map, x, y)
	local text = label .. ": " .. (name or "unknown")
	if map then
		text = text .. "  -  " .. ns.MapName(map)
		if x then text = text .. string.format(" (%.1f, %.1f)", x * 100, y * 100) end
	end
	return { kind = "place", text = text, map = map, x = x, y = y, name = name }
end

local function detailRows(id)
	local q = ns.Quest(id)
	local rows = {}
	if not q then
		rows[1] = { kind = "note", text = "No data for quest " .. id }
		return rows
	end
	local _, why = questState(q)
	rows[#rows + 1] = { kind = "quest", id = id, static = true }
	rows[#rows + 1] = { kind = "note", text = why, dim = true }
	if q.t then
		for _, l in ipairs(wrap(q.t, 92)) do rows[#rows + 1] = { kind = "note", text = l } end
	end
	local e = ns.Log.quests[id]
	if e and #e.objectives > 0 then
		rows[#rows + 1] = { kind = "header", text = "Progress" }
		for _, o in ipairs(e.objectives) do
			rows[#rows + 1] = { kind = "note", text = o.text, good = o.done }
		end
	end
	rows[#rows + 1] = { kind = "header", text = "Where" }
	rows[#rows + 1] = placeRow("Starts", ns.StarterPlace(q))
	rows[#rows + 1] = placeRow("Ends", ns.FinisherPlace(q))
	if q.z then rows[#rows + 1] = { kind = "note", text = "Category: " .. ns.ZoneName(q.z), dim = true } end
	local pre = {}
	for _, p in ipairs(q.ps or {}) do pre[#pre + 1] = p end
	for _, p in ipairs(q.pg or {}) do pre[#pre + 1] = math.abs(p) end
	if q.pq then pre[#pre + 1] = q.pq end
	if #pre > 0 then
		rows[#rows + 1] = { kind = "header", text = (q.ps and #q.ps > 1) and "Requires one of" or "Requires" }
		for _, p in ipairs(pre) do rows[#rows + 1] = { kind = "quest", id = p } end
	end
	if q.nx then
		rows[#rows + 1] = { kind = "header", text = "Leads to" }
		rows[#rows + 1] = { kind = "quest", id = q.nx }
	end
	if q.ex then
		rows[#rows + 1] = { kind = "header", text = "Cannot be combined with" }
		for _, p in ipairs(q.ex) do rows[#rows + 1] = { kind = "quest", id = p } end
	end
	rows[#rows + 1] = { kind = "header", text = "Actions" }
	rows[#rows + 1] = { kind = "action", text = "Show on the map", func = function() ns.Tracker.ShowOnMap(id) end }
	if e then
		local tracked = ns.Tracker.Tracked(id)
		rows[#rows + 1] = {
			kind = "action", text = tracked and "Stop tracking" or "Track this quest",
			func = function()
				ns.Tracker.SetTracked(id, not tracked)
				Journal.Refresh()
			end,
		}
	end
	return rows
end

local function zoneRows()
	local rows = {}
	if state.query ~= "" then
		for _, id in ipairs(ns.SearchQuests(state.query, 400)) do
			rows[#rows + 1] = { kind = "quest", id = id, zone = true }
		end
		if #rows == 0 then rows[1] = { kind = "note", text = "No quest matches that." } end
		return rows, "Search: " .. state.query
	end
	if state.zone == "log" then
		for _, id in ipairs(ns.Log.order) do rows[#rows + 1] = { kind = "quest", id = id, zone = true } end
		if #rows == 0 then rows[1] = { kind = "note", text = "Your quest log is empty." } end
		return rows, "Quest log"
	end
	local list = {}
	for _, id in ipairs(ns.Index("zonequests", state.zone)) do
		local q = ns.Quest(id)
		if q and not q.h and ns.ForPlayer(q) then
			local st = questState(q)
			if not (state.hideDone and st == "done") then list[#list + 1] = q end
		end
	end
	table.sort(list, function(a, b)
		local la, lb = ns.QuestLevel(a), ns.QuestLevel(b)
		if la ~= lb then return la < lb end
		if a.n ~= b.n then return a.n < b.n end
		return a.id < b.id
	end)
	for _, q in ipairs(list) do rows[#rows + 1] = { kind = "quest", id = q.id } end
	if #rows == 0 then rows[1] = { kind = "note", text = "Nothing here for your character." } end
	return rows, ns.ZoneName(state.zone)
end

local zoneList
local function zones()
	if zoneList then return zoneList end
	zoneList = {}
	for zone in pairs(ns.raw.zonequests) do
		zoneList[#zoneList + 1] = { zone = zone, name = ns.ZoneName(zone) }
	end
	table.sort(zoneList, function(a, b)
		local pa, pb = a.zone > 0, b.zone > 0
		if pa ~= pb then return pa end
		if a.name ~= b.name then return a.name < b.name end
		return a.zone < b.zone
	end)
	table.insert(zoneList, 1, { zone = "log", name = "Quest log" })
	return zoneList
end

local function currentZone()
	if not C_Map or not C_Map.GetBestMapForUnit then return nil end
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok or type(map) ~= "number" then return nil end
	for area, m in pairs(ns.raw.areamaps) do
		if m == map and ns.raw.zonequests[area] then return area end
	end
end

local function createZoneRow(list)
	local row = CreateFrame("Button", nil, list)
	row.sel = UI.Fill(row, C.select)
	row.hl = UI.Fill(row, C.hover, "HIGHLIGHT")
	row.text = UI.Text(row, "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 12, 0)
	row.text:SetPoint("RIGHT", -6, 0)
	row:SetScript("OnClick", function(self)
		if not self.data then return end
		state.zone = self.data.zone
		state.stack = {}
		if state.query ~= "" then
			state.query = ""
			frame.search.box:SetText("")
			frame.search.box:ClearFocus()
		end
		Journal.Refresh()
	end)
	return row
end

local function updateZoneRow(row, d)
	row.text:SetText(d.name)
	local on = state.query == "" and d.zone == state.zone
	row.sel:SetShown(on)
	local c = on and C.accent or ((d.zone == "log" or d.zone > 0) and C.text or C.dim)
	row.text:SetTextColor(c[1], c[2], c[3])
end

local function createRow(list)
	local row = CreateFrame("Button", nil, list)
	row.hl = UI.Fill(row, C.hover, "HIGHLIGHT")
	row.band = UI.Fill(row, { 1, 1, 1, 0.05 })
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 8, 0)
	row.right = UI.Text(row, "GameFontDisableSmall", "RIGHT", C.dim)
	row.right:SetPoint("RIGHT", -8, 0)
	row.text = UI.Text(row, "GameFontHighlight")
	row.text:SetPoint("LEFT", 30, 0)
	row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self, button)
		local d = self.data
		if not d then return end
		if d.kind == "quest" and not d.static then
			if IsShiftKeyDown and IsShiftKeyDown() and ns.Log.quests[d.id] then
				ns.Tracker.SetTracked(d.id, not ns.Tracker.Tracked(d.id))
			elseif button == "RightButton" then
				ns.Tracker.ShowOnMap(d.id)
			else
				Journal.ShowQuest(d.id)
			end
		elseif d.kind == "place" and d.map then
			if d.x and IsShiftKeyDown and IsShiftKeyDown() and ns.Waypoint(d.map, d.x, d.y, d.name) then
				return
			else
				ns.Pins.ShowOnMap(d.map)
			end
		elseif d.kind == "action" and d.func then
			d.func()
		end
	end)
	return row
end

local function updateRow(row, d)
	row.band:Hide()
	row.icon:Hide()
	row.right:SetText("")
	row.hl:SetShown(d.kind == "quest" and not d.static or d.kind == "action" or (d.kind == "place" and d.map ~= nil))
	if d.kind == "quest" then
		local q = ns.Quest(d.id)
		if not q then
			row.text:SetText("Quest " .. d.id)
			row.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
			return
		end
		local st, why = questState(q)
		local level = ns.QuestLevel(q)
		local r, g, b = ns.DifficultyColor(level)
		if st == "done" or st == "locked" then r, g, b = C.dim[1], C.dim[2], C.dim[3] end
		row.text:SetText("[" .. level .. "] " .. q.n .. (q.rep and "  (repeatable)" or ""))
		row.text:SetTextColor(r, g, b)
		local icon = STATE_ICON[st]
		if icon then
			row.icon:SetTexture(icon)
			row.icon:Show()
		end
		local right = why
		if ns.Log.quests[d.id] and ns.Tracker.Tracked(d.id) then right = "Tracked   " .. right end
		if d.zone and q.z then right = ns.ZoneName(q.z) .. "   " .. why end
		row.right:SetText(d.static and "" or right)
	elseif d.kind == "header" then
		row.band:Show()
		row.text:SetText(d.text)
		row.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
	elseif d.kind == "action" then
		row.text:SetText("> " .. d.text)
		row.text:SetTextColor(0.55, 0.8, 1)
	elseif d.kind == "place" then
		row.text:SetText(d.text)
		row.text:SetTextColor(C.text[1], C.text[2], C.text[3])
		if d.map then row.right:SetText(ns.CanWaypoint() and "click: map   shift-click: waypoint" or "click: map") end
	else
		row.text:SetText(d.text or "")
		if d.good then
			row.text:SetTextColor(0.35, 0.8, 0.35)
		elseif d.dim then
			row.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
		else
			row.text:SetTextColor(C.text[1], C.text[2], C.text[3])
		end
	end
end

local function build()
	frame = UI.Window("AQuestJournal", "AQuest", 800, 560, ns.db.journal)
	local bar = frame.bar

	local search = UI.EditBox(bar, "Search every quest", function(text)
		ns.Debounce("search", 0.2, function()
			local q = text:gsub("^%s+", ""):gsub("%s+$", "")
			if q == state.query then return end
			state.query = q
			state.stack = {}
			Journal.Refresh()
		end)
	end)
	search:SetPoint("LEFT", 110, 0)
	search:SetWidth(300)
	frame.search = search

	local options = UI.Button(bar, "Options", function(self) UI.Menu(self, ns.Options()) end)
	options:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
	local here = UI.Button(bar, "This zone", function()
		local zone = currentZone()
		if zone then
			state.zone = zone
			state.stack = {}
			Journal.Refresh()
		end
	end)
	here:SetPoint("RIGHT", options, "LEFT", -6, 0)
	local done = UI.Button(bar, "Hide completed", function()
		state.hideDone = not state.hideDone
		Journal.Refresh()
	end)
	done:SetPoint("RIGHT", here, "LEFT", -6, 0)
	frame.doneButton = done

	local body = frame.body
	local left = CreateFrame("Frame", nil, body)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(210)
	UI.Fill(left, C.panel)
	local zl = UI.List(left, 20, createZoneRow, updateZoneRow)
	zl:SetPoint("TOPLEFT", 0, -4)
	zl:SetPoint("BOTTOMRIGHT", 0, 4)
	frame.zoneList = zl

	local tools = CreateFrame("Frame", nil, body)
	tools:SetPoint("TOPLEFT", left, "TOPRIGHT")
	tools:SetPoint("TOPRIGHT")
	tools:SetHeight(32)
	UI.Fill(tools, { 0.075, 0.08, 0.1, 1 })
	local back = UI.Button(tools, "< Back", function()
		table.remove(state.stack)
		Journal.Refresh()
	end)
	back:SetPoint("LEFT", 8, 0)
	frame.back = back
	frame.viewTitle = UI.Text(tools, "GameFontNormal", "LEFT", C.text)
	frame.count = UI.Text(tools, "GameFontDisableSmall", "RIGHT", C.dim)
	frame.count:SetPoint("RIGHT", -10, 0)

	local ql = UI.List(body, 24, createRow, updateRow)
	ql:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, -34)
	ql:SetPoint("BOTTOMRIGHT", 0, 2)
	frame.questList = ql
end

function Journal.Refresh()
	if not frame or not frame:IsShown() then return end
	local top = state.stack[#state.stack]
	local rows, title
	if top then
		rows = detailRows(top)
		title = ns.QuestTitle(top)
	else
		rows, title = zoneRows()
	end
	frame.back:SetShown(top ~= nil)
	frame.viewTitle:ClearAllPoints()
	if top then
		frame.viewTitle:SetPoint("LEFT", frame.back, "RIGHT", 10, 0)
	else
		frame.viewTitle:SetPoint("LEFT", 10, 0)
	end
	frame.viewTitle:SetText(title or "")
	local n = 0
	for _, r in ipairs(rows) do
		if r.kind == "quest" then n = n + 1 end
	end
	frame.count:SetText(top and "" or (n .. (n == 1 and " quest" or " quests")))
	frame.doneButton:SetActive(state.hideDone)
	frame.zoneList:SetData(zones(), true)
	frame.questList:SetData(rows, frame.lastTop == top and frame.lastTitle == title)
	frame.lastTop, frame.lastTitle = top, title
end

function Journal.Show()
	if not frame then build() end
	frame:Show()
	Journal.Refresh()
end

function Journal.Hide()
	if frame then frame:Hide() end
end

function Journal.Toggle()
	if frame and frame:IsShown() then
		Journal.Hide()
	else
		Journal.Show()
	end
end

function Journal.ShowQuest(id)
	if not id then return end
	Journal.Show()
	if state.stack[#state.stack] ~= id then state.stack[#state.stack + 1] = id end
	Journal.Refresh()
end

function Journal.SetSearch(text)
	if not frame then return end
	frame.search.box:SetText(text or "")
end

ns:Listen("LOG_CHANGED", function() Journal.Refresh() end)
ns:Listen("TRACK_CHANGED", function() Journal.Refresh() end)
ns:Listen("LAYOUT_RESET", function()
	if frame then frame:Restore() end
end)
