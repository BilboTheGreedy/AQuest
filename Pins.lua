local _, ns = ...

local Pins = {}
ns.Pins = Pins

local EMPTY = {}
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMaskSmall"

local KINDS = {
	turnin = { order = 6, icon = "Interface\\GossipFrame\\ActiveQuestIcon", size = 18, label = "Turn in" },
	available = { order = 5, icon = "Interface\\GossipFrame\\AvailableQuestIcon", size = 18, label = "Available" },
	repeatable = { order = 4, icon = "Interface\\GossipFrame\\DailyQuestIcon", size = 16, label = "Repeatable" },
	turnin_wait = { order = 3, icon = "Interface\\GossipFrame\\IncompleteQuestIcon", size = 16, label = "Turn in later" },
	slay = { order = 2, dot = true, size = 11, glyph = "Interface\\CURSOR\\Attack", label = "Slay" },
	loot = { order = 2, dot = true, size = 11, glyph = "Interface\\CURSOR\\Pickup", label = "Loot" },
	object = { order = 2, dot = true, size = 11, glyph = "Interface\\CURSOR\\Interact", label = "Use" },
	event = { order = 2, dot = true, size = 11, glyph = "Interface\\CURSOR\\Crosshairs", label = "Go here" },
}

local function add(index, list, pts, kind, quest, title, text)
	if not pts then return end
	local k = KINDS[kind]
	for i = 1, #pts, 2 do
		local x, y = pts[i], pts[i + 1]
		local key = math.floor(x * 1000 + 0.5) * 10000 + math.floor(y * 1000 + 0.5)
		if k.dot then key = key + quest * 100000000 end
		local pin = index[key]
		if not pin then
			pin = { x = x, y = y, kind = kind, quest = quest, title = title, inside = pts.inside, lines = {}, seen = {} }
			index[key] = pin
			list[#list + 1] = pin
		elseif k.order > KINDS[pin.kind].order then
			pin.kind = kind
			pin.quest = quest
		end
		local lk = quest .. kind
		if not pin.seen[lk] then
			pin.seen[lk] = true
			pin.lines[#pin.lines + 1] = { quest = quest, text = text or k.label, kind = kind }
		end
	end
end

local function have(item)
	local count = C_Item and C_Item.GetItemCount or GetItemCount
	if not count then return false end
	local ok, n = pcall(count, item)
	return ok and type(n) == "number" and not ns.IsSecret(n) and n > 0
end

local function itemPins(index, list, map, id, it, text, depth)
	for i = 1, math.min(#it.npcs, 40) do
		local n = ns.Npc(it.npcs[i])
		if n then add(index, list, n.spawns[map], "loot", id, n.name, text) end
	end
	for i = 1, math.min(#it.objects, 20) do
		local ob = ns.Object(it.objects[i])
		if ob then add(index, list, ob.spawns[map], "object", id, ob.name, text) end
	end
	for i = 1, math.min(#it.vendors, 10) do
		local n = ns.Npc(it.vendors[i])
		if n then add(index, list, n.spawns[map], "loot", id, n.name, "Sold here: " .. it.name) end
	end
	if depth > 0 then
		for i = 1, math.min(#it.items, 5) do
			local inner = ns.Item(it.items[i])
			if inner then itemPins(index, list, map, id, inner, text, depth - 1) end
		end
	end
end

local function objectivePins(index, list, map, e)
	local q = e.data
	local id = e.id
	local before = #list
	local slots = q.oc and #q.oc or 0
	for i, npc in ipairs(q.oc or EMPTY) do
		local n = ns.Npc(npc)
		if n then
			local o = ns.ObjectiveFor(e, n.name, "monster", i)
			if not o or not o.done then add(index, list, n.spawns[map], "slay", id, n.name, o and o.text) end
		end
	end
	local exact = q.ok and ns.CountType(e, "monster") == slots + #q.ok
	for i, group in ipairs(q.ok or EMPTY) do
		local o = exact and ns.ObjectiveFor(e, nil, "monster", slots + i) or nil
		if not o or not o.done then
			for _, npc in ipairs(group) do
				local n = ns.Npc(npc)
				if n then add(index, list, n.spawns[map], "slay", id, n.name, o and o.text) end
			end
		end
	end
	for i, obj in ipairs(q.oo or EMPTY) do
		local o = ns.Object(obj)
		if o then
			local lo = ns.ObjectiveFor(e, o.name, "object", i)
			if not lo or not lo.done then add(index, list, o.spawns[map], "object", id, o.name, lo and lo.text) end
		end
	end
	for i, item in ipairs(q.oi or EMPTY) do
		local it = ns.Item(item)
		if it then
			local o = ns.ObjectiveFor(e, it.name, "item", i)
			if not o or not o.done then itemPins(index, list, map, id, it, o and o.text or it.name, 1) end
		end
	end
	for _, item in ipairs(q.rs or EMPTY) do
		local it = ns.Item(item)
		if it and not have(item) then itemPins(index, list, map, id, it, "Needed: " .. it.name, 0) end
	end
	if q.te then
		local ev = ns.CountType(e, "event") == 1 and ns.ObjectiveFor(e, nil, "event", 1) or nil
		if not ev or not ev.done then add(index, list, ns.Spawns(q.te)[map], "event", id, e.title or q.n, ev and ev.text) end
	end
	for _, s in ipairs(q.eo or EMPTY) do
		add(index, list, ns.Spawns(s)[map], "event", id, e.title or q.n)
	end
	local limit = before + 80
	for i = #list, limit + 1, -1 do list[i] = nil end
end

local function turninPins(index, list, map, e)
	local q = e.data
	local kind = e.complete and "turnin" or "turnin_wait"
	for _, npc in ipairs(q.e1 or EMPTY) do
		local n = ns.Npc(npc)
		if n then add(index, list, n.spawns[map], kind, e.id, n.name) end
	end
	for _, obj in ipairs(q.e2 or EMPTY) do
		local o = ns.Object(obj)
		if o then add(index, list, o.spawns[map], kind, e.id, o.name) end
	end
end

local STARTER_SOURCES = 10

local function starterPins(index, list, map, q)
	local id = q.id
	local kind = q.rep and "repeatable" or "available"
	for _, npc in ipairs(q.s1 or EMPTY) do
		local n = ns.Npc(npc)
		if n then add(index, list, n.spawns[map], kind, id, n.name) end
	end
	for _, obj in ipairs(q.s2 or EMPTY) do
		local o = ns.Object(obj)
		if o then add(index, list, o.spawns[map], kind, id, o.name) end
	end
	for _, item in ipairs(q.s3 or EMPTY) do
		local it = ns.Item(item)
		if it and #it.npcs + #it.objects <= STARTER_SOURCES and not have(item) then
			local text = "Drops: " .. it.name
			for _, npc in ipairs(it.npcs) do
				local n = ns.Npc(npc)
				if n then add(index, list, n.spawns[map], kind, id, n.name, text) end
			end
			for _, obj in ipairs(it.objects) do
				local o = ns.Object(obj)
				if o then add(index, list, o.spawns[map], kind, id, o.name, text) end
			end
		end
	end
end

local avail = {}

local function available(map)
	local c = avail[map]
	if c and c.rev == ns.Log.rev then return c end
	c = { rev = ns.Log.rev }
	for _, id in ipairs(ns.Index("starts", map)) do
		local q = ns.Quest(id)
		if q and ns.Shown(q) then c[#c + 1] = q end
	end
	avail[map] = c
	return c
end

function Pins.Build(map)
	local index, list = {}, {}
	local db = ns.db
	if db.turnins or db.objectives then
		for _, id in ipairs(ns.Log.order) do
			local e = ns.Log.quests[id]
			if e.data then
				if db.turnins then turninPins(index, list, map, e) end
				if db.objectives and not e.complete then objectivePins(index, list, map, e) end
			end
		end
	end
	if db.available then
		for _, q in ipairs(available(map)) do starterPins(index, list, map, q) end
	end
	table.sort(list, function(a, b)
		local oa, ob = KINDS[a.kind].order, KINDS[b.kind].order
		if oa ~= ob then return oa < ob end
		if a.y ~= b.y then return a.y < b.y end
		return a.x < b.x
	end)
	return list
end

function Pins.QuestPoints(id, map)
	local index, list = {}, {}
	if not map then return list end
	local e = ns.Log.quests[id]
	if e and e.data then
		if e.complete then
			turninPins(index, list, map, e)
		else
			objectivePins(index, list, map, e)
		end
	elseif not e then
		local q = ns.Quest(id)
		if q then starterPins(index, list, map, q) end
	end
	local out = {}
	for _, pin in ipairs(list) do
		if not pin.inside then out[#out + 1] = pin end
	end
	if #out == 0 then return list end
	return out
end

local function tooltip(self)
	local pin = self.pin
	if not pin then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(pin.title or "", 1, 1, 1)
	if pin.inside then GameTooltip:AddLine("Inside this dungeon", 0.58, 0.6, 0.65) end
	local shown = {}
	for _, line in ipairs(pin.lines) do
		local q = ns.Quest(line.quest)
		local e = ns.Log.quests[line.quest]
		local name = e and e.title or (q and q.n) or ("Quest " .. line.quest)
		local level = q and ns.QuestLevel(q) or (e and e.level) or 0
		local r, g, b = ns.DifficultyColor(level)
		GameTooltip:AddDoubleLine("[" .. level .. "] " .. name, KINDS[line.kind].label, r, g, b, 0.58, 0.6, 0.65)
		if line.text and line.text ~= KINDS[line.kind].label and not shown[line.quest .. line.text] then
			shown[line.quest .. line.text] = true
			local cr, cg, cb = ns.QuestColor(line.quest)
			GameTooltip:AddLine("  " .. line.text, cr, cg, cb)
		end
	end
	if self.map and ns.CanWaypoint and ns.CanWaypoint() then
		GameTooltip:AddLine("Click: journal   Shift-click: waypoint", 0.45, 0.47, 0.5)
	end
	GameTooltip:Show()
end

local waiting = {}

local function passThrough()
	if #waiting == 0 then return end
	if InCombatLockdown and InCombatLockdown() then return end
	for i = #waiting, 1, -1 do
		local f = waiting[i]
		if f.SetPassThroughButtons then pcall(f.SetPassThroughButtons, f, "RightButton", "MiddleButton") end
		waiting[i] = nil
	end
end

ns:On("PLAYER_REGEN_ENABLED", passThrough)

local function create(parent)
	local f = CreateFrame("Button", nil, parent)
	f:SetSize(16, 16)
	f.back = f:CreateTexture(nil, "BACKGROUND")
	f.back:SetTexture(CIRCLE)
	f.back:SetVertexColor(0, 0, 0, 0.9)
	f.back:SetPoint("TOPLEFT", -1.5, 1.5)
	f.back:SetPoint("BOTTOMRIGHT", 1.5, -1.5)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints(f)
	f.glyph = f:CreateTexture(nil, "OVERLAY")
	f.glyph:SetPoint("CENTER", 0, 0)
	f:SetScript("OnEnter", tooltip)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f:RegisterForClicks("LeftButtonUp")
	f:SetScript("OnClick", function(self)
		local pin = self.pin
		if not pin then return end
		if IsShiftKeyDown and IsShiftKeyDown() and self.map and ns.QuestWaypoint then
			ns.QuestWaypoint(self.map, pin.x, pin.y, pin.title)
		elseif ns.Journal then
			ns.Journal.ShowQuest(pin.quest)
		end
	end)
	waiting[#waiting + 1] = f
	passThrough()
	return f
end

local function style(f, pin, small)
	local k = KINDS[pin.kind]
	local size = k.size * (small and 0.8 or 1)
	f.pin = pin
	f:SetSize(size, size)
	if k.dot then
		local r, g, b = ns.QuestColor(pin.quest)
		f.tex:SetTexture(CIRCLE)
		f.tex:SetVertexColor(r, g, b, 1)
		f.back:Show()
		if small then
			f.glyph:Hide()
		else
			f.glyph:SetTexture(k.glyph)
			f.glyph:SetSize(size * 0.8, size * 0.8)
			f.glyph:Show()
		end
	else
		f.tex:SetTexture(k.icon)
		f.tex:SetVertexColor(1, 1, 1, 1)
		f.back:Hide()
		f.glyph:Hide()
	end
	f:SetFrameLevel((f.base or 2000) + k.order)
end

local world = { pool = {}, pins = {}, dirty = true }
local mini = { pool = {}, pins = {}, dirty = true }

local function canvas()
	if not WorldMapFrame then return nil end
	if WorldMapFrame.GetCanvas then return WorldMapFrame:GetCanvas() end
	return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function worldMap()
	if WorldMapFrame and WorldMapFrame.GetMapID then return WorldMapFrame:GetMapID() end
end

function Pins.RefreshWorld(force)
	local c = canvas()
	if not c or not WorldMapFrame:IsShown() then return end
	local map = worldMap()
	if type(map) ~= "number" then return end
	local scale = c:GetEffectiveScale()
	if not force and not world.dirty and map == world.map and scale == world.scale then return end
	if world.dirty or map ~= world.map then world.pins = Pins.Build(map) end
	world.map, world.scale, world.dirty = map, scale, false
	local w, h = c:GetWidth(), c:GetHeight()
	local pinScale = (UIParent:GetEffectiveScale() * (ns.db.pinSize or 1)) / (scale > 0 and scale or 1)
	for i, pin in ipairs(world.pins) do
		local f = world.pool[i]
		if not f then
			f = create(c)
			f.base = 2000
			world.pool[i] = f
		end
		f:SetScale(pinScale)
		f.map = map
		style(f, pin)
		f:ClearAllPoints()
		f:SetPoint("CENTER", c, "TOPLEFT", pin.x * w / pinScale, -pin.y * h / pinScale)
		f:Show()
	end
	for i = #world.pins + 1, #world.pool do world.pool[i]:Hide() end
end

local RADIUS = {
	[0] = { 150, 120, 90, 60, 40, 25 },
	[1] = { 233.33, 200, 166.67, 133.33, 100, 66.67 },
}

local function viewRadius()
	if C_Minimap and C_Minimap.GetViewRadius then
		local ok, r = pcall(C_Minimap.GetViewRadius)
		if ok and type(r) == "number" and r > 0 then return r end
	end
	local zoom = Minimap:GetZoom() or 0
	local outdoors = 1
	if IsIndoors and IsIndoors() then outdoors = 0 end
	return RADIUS[outdoors][zoom + 1] or 150
end

local function playerMap()
	if not C_Map or not C_Map.GetBestMapForUnit then return nil end
	local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
	if ok and type(map) == "number" then return map end
end

local rects = {}

local function worldRect(map)
	local r = rects[map]
	if r ~= nil then return r or nil end
	r = false
	if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
		local ok, c0, a = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 0))
		local ok2, _, b = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0.5, 0.5))
		if ok and ok2 and a and b then
			local n0, w0 = a.x, a.y
			local n1, w1 = b.x, b.y
			if a.GetXY then n0, w0 = a:GetXY() end
			if b.GetXY then n1, w1 = b:GetXY() end
			if type(n0) == "number" and type(w0) == "number" and type(n1) == "number" and type(w1) == "number" then
				r = { north = n0, west = w0, dn = (n1 - n0) * 2, dw = (w1 - w0) * 2, continent = c0 }
			end
		end
	end
	rects[map] = r
	return r or nil
end

function Pins.World(map, x, y)
	local r = worldRect(map)
	if not r then return nil end
	return r.north + r.dn * y, r.west + r.dw * x, r.continent
end

local function buildMini()
	mini.pins = {}
	mini.dirty = false
	local map = playerMap()
	mini.map = map
	if not map or not ns.db.minimap then return end
	local r = worldRect(map)
	if not r then return end
	for _, pin in ipairs(Pins.Build(map)) do
		if not pin.inside then
			mini.pins[#mini.pins + 1] = { pin = pin, north = r.north + r.dn * pin.y, west = r.west + r.dw * pin.x }
		end
	end
end

function Pins.RefreshMini()
	if mini.dirty or playerMap() ~= mini.map then buildMini() end
	local shown = 0
	if #mini.pins > 0 and UnitPosition and Minimap:IsShown() then
		local ok, north, west = pcall(UnitPosition, "player")
		if ok and not ns.IsSecret(north) and not ns.IsSecret(west) and type(north) == "number" and type(west) == "number" then
			local radius = viewRadius()
			local half = Minimap:GetWidth() / 2
			local sin, cos
			if GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing then
				local facing = GetPlayerFacing()
				if type(facing) == "number" and not ns.IsSecret(facing) then
					sin, cos = math.sin(facing), math.cos(facing)
				end
			end
			for _, m in ipairs(mini.pins) do
				local dx, dy = west - m.west, north - m.north
				if sin then
					dx, dy = dx * cos - dy * sin, dx * sin + dy * cos
				end
				local dist = math.sqrt(dx * dx + dy * dy) / radius
				if dist <= 0.95 then
					shown = shown + 1
					local f = mini.pool[shown]
					if not f then
						f = create(Minimap)
						f.base = (Minimap:GetFrameLevel() or 0) + 4
						mini.pool[shown] = f
					end
					if f.pin ~= m.pin then style(f, m.pin, true) end
					f.map = mini.map
					f:ClearAllPoints()
					f:SetPoint("CENTER", Minimap, "CENTER", dx / radius * half, -dy / radius * half)
					f:Show()
					if shown >= 80 then break end
				end
			end
		end
	end
	for i = shown + 1, #mini.pool do
		mini.pool[i]:Hide()
		mini.pool[i].pin = nil
	end
end

local function dirty()
	world.dirty = true
	mini.dirty = true
	Pins.RefreshWorld()
end

ns:Listen("LOG_CHANGED", dirty)
ns:Listen("OPTIONS", function()
	avail = {}
	dirty()
end)
ns:On("ZONE_CHANGED_NEW_AREA", function() mini.dirty = true end)

ns:Listen("LOGIN", function()
	if WorldMapFrame then
		local watcher = CreateFrame("Frame", nil, WorldMapFrame)
		local elapsed = 0
		watcher:SetScript("OnUpdate", function(_, dt)
			elapsed = elapsed + (dt or 0)
			if elapsed < 0.2 then return end
			elapsed = 0
			Pins.RefreshWorld()
		end)
		watcher:SetScript("OnShow", function() Pins.RefreshWorld(true) end)
		if hooksecurefunc and WorldMapFrame.OnMapChanged then
			pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", function() Pins.RefreshWorld() end)
		end
	end
	local ticker = CreateFrame("Frame")
	local elapsed = 0
	ticker:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 0.1 then return end
		elapsed = 0
		Pins.RefreshMini()
	end)
end)

function Pins.ShowOnMap(map)
	if not map then return end
	if C_Map and C_Map.OpenWorldMap then
		pcall(C_Map.OpenWorldMap, map)
	elseif WorldMapFrame then
		if ShowUIPanel then ShowUIPanel(WorldMapFrame) end
		if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(map) end
	end
end

function Pins.Nearest(id)
	local map = playerMap()
	local points = Pins.QuestPoints(id, map)
	if #points == 0 then
		map = ns.Tracker.QuestMap(id)
		points = Pins.QuestPoints(id, map)
		local first = points[1]
		if not first then return nil end
		return map, first.x, first.y, first.title
	end
	local px, py
	if C_Map and C_Map.GetPlayerMapPosition then
		local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
		if ok and pos and not ns.IsSecret(pos) then
			px, py = pos.x, pos.y
			if pos.GetXY then px, py = pos:GetXY() end
		end
	end
	if type(px) ~= "number" or type(py) ~= "number" or ns.IsSecret(px) or ns.IsSecret(py) then
		local first = points[1]
		return map, first.x, first.y, first.title
	end
	local r = worldRect(map)
	local sx, sy = r and math.abs(r.dw) or 1.5, r and math.abs(r.dn) or 1
	local best, bestDist
	for _, pin in ipairs(points) do
		local dx, dy = (pin.x - px) * sx, (pin.y - py) * sy
		local d = dx * dx + dy * dy
		if not bestDist or d < bestDist then best, bestDist = pin, d end
	end
	return map, best.x, best.y, best.title
end
