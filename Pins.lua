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

local function objectivePins(index, list, map, e)
	local q = e.data
	local id = e.id
	local before = #list
	for _, npc in ipairs(q.oc or EMPTY) do
		local n = ns.Npc(npc)
		if n then
			local o = ns.ObjectiveFor(e, n.name)
			if not o or not o.done then add(index, list, n.spawns[map], "slay", id, n.name, o and o.text) end
		end
	end
	for _, npc in ipairs(q.ok or EMPTY) do
		local n = ns.Npc(npc)
		if n then add(index, list, n.spawns[map], "slay", id, n.name) end
	end
	for _, obj in ipairs(q.oo or EMPTY) do
		local o = ns.Object(obj)
		if o then
			local lo = ns.ObjectiveFor(e, o.name)
			if not lo or not lo.done then add(index, list, o.spawns[map], "object", id, o.name, lo and lo.text) end
		end
	end
	for _, item in ipairs(q.oi or EMPTY) do
		local it = ns.Item(item)
		if it then
			local o = ns.ObjectiveFor(e, it.name)
			if not o or not o.done then
				local text = o and o.text or it.name
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
			end
		end
	end
	if q.te then add(index, list, ns.Spawns(q.te)[map], "event", id, e.title or q.n) end
	for _, s in ipairs(q.eo or EMPTY) do
		add(index, list, ns.Spawns(s)[map], "event", id, e.title or q.n)
	end
	local limit = before + 80
	for i = #list, limit + 1, -1 do list[i] = nil end
end

function Pins.Build(map)
	local index, list = {}, {}
	local db = ns.db
	if db.turnins or db.objectives then
		for _, id in ipairs(ns.Log.order) do
			local e = ns.Log.quests[id]
			local q = e.data
			if q then
				if db.turnins then
					local kind = e.complete and "turnin" or "turnin_wait"
					for _, npc in ipairs(q.e1 or EMPTY) do
						local n = ns.Npc(npc)
						if n then add(index, list, n.spawns[map], kind, id, n.name) end
					end
					for _, obj in ipairs(q.e2 or EMPTY) do
						local o = ns.Object(obj)
						if o then add(index, list, o.spawns[map], kind, id, o.name) end
					end
				end
				if db.objectives and not e.complete then objectivePins(index, list, map, e) end
			end
		end
	end
	if db.available then
		for _, id in ipairs(ns.Index("starts", map)) do
			local q = ns.Quest(id)
			if q and ns.Shown(q) then
				local kind = q.rep and "repeatable" or "available"
				for _, npc in ipairs(q.s1 or EMPTY) do
					local n = ns.Npc(npc)
					if n then add(index, list, n.spawns[map], kind, id, n.name) end
				end
				for _, obj in ipairs(q.s2 or EMPTY) do
					local o = ns.Object(obj)
					if o then add(index, list, o.spawns[map], kind, id, o.name) end
				end
			end
		end
	end
	table.sort(list, function(a, b)
		local oa, ob = KINDS[a.kind].order, KINDS[b.kind].order
		if oa ~= ob then return oa < ob end
		if a.y ~= b.y then return a.y < b.y end
		return a.x < b.x
	end)
	return list
end

local function tooltip(self)
	local pin = self.pin
	if not pin then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(pin.title or "", 1, 1, 1)
	if pin.inside then GameTooltip:AddLine("Inside this dungeon", 0.58, 0.6, 0.65) end
	for _, line in ipairs(pin.lines) do
		local q = ns.Quest(line.quest)
		local e = ns.Log.quests[line.quest]
		local name = e and e.title or (q and q.n) or ("Quest " .. line.quest)
		local level = q and ns.QuestLevel(q) or (e and e.level) or 0
		local r, g, b = ns.DifficultyColor(level)
		GameTooltip:AddDoubleLine("[" .. level .. "] " .. name, KINDS[line.kind].label, r, g, b, 0.58, 0.6, 0.65)
		if line.text and line.text ~= KINDS[line.kind].label then
			local cr, cg, cb = ns.QuestColor(line.quest)
			GameTooltip:AddLine("  " .. line.text, cr, cg, cb)
		end
	end
	GameTooltip:Show()
end

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
		if self.pin and ns.Journal then ns.Journal.ShowQuest(self.pin.quest) end
	end)
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

local function buildMini()
	mini.pins = {}
	mini.dirty = false
	local map = playerMap()
	mini.map = map
	if not map or not ns.db.minimap or not C_Map.GetWorldPosFromMapPos or not CreateVector2D then return end
	for _, pin in ipairs(Pins.Build(map)) do
		if not pin.inside then
			local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(pin.x, pin.y))
			if ok and pos then
				local north, west = pos.x, pos.y
				if pos.GetXY then north, west = pos:GetXY() end
				if type(north) == "number" and type(west) == "number" then
					mini.pins[#mini.pins + 1] = { pin = pin, north = north, west = west }
				end
			end
		end
	end
end

function Pins.RefreshMini()
	if mini.dirty or playerMap() ~= mini.map then buildMini() end
	local shown = 0
	if #mini.pins > 0 and UnitPosition and Minimap:IsShown() then
		local ok, north, west = pcall(UnitPosition, "player")
		if ok and type(north) == "number" and type(west) == "number" and not ns.IsSecret(north) then
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
						f.base = Minimap:GetFrameLevel() + 4
						mini.pool[shown] = f
					end
					if f.pin ~= m.pin then style(f, m.pin, true) end
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
ns:Listen("OPTIONS", dirty)
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
