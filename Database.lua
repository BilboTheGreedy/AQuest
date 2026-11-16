local _, ns = ...

local quests, npcs, objects, items, spawnCache = {}, {}, {}, {}, {}
local EMPTY = {}

local function list(s)
	if not s or s == "" then return EMPTY end
	local out = {}
	for v in s:gmatch("%d+") do out[#out + 1] = tonumber(v) end
	return out
end

function ns.Spawns(s)
	if not s or s == "" then return EMPTY end
	local c = spawnCache[s]
	if c then return c end
	c = {}
	for part in s:gmatch("[^;]+") do
		local map, sep, coords = part:match("^(%d+)([:!])(.*)$")
		if map then
			map = tonumber(map)
			local pts = c[map]
			if not pts then
				pts = {}
				c[map] = pts
			end
			if sep == "!" then pts.inside = true end
			for x, y in coords:gmatch("(%d+),(%d+)") do
				pts[#pts + 1] = tonumber(x) / 1000
				pts[#pts + 1] = tonumber(y) / 1000
			end
		end
	end
	spawnCache[s] = c
	return c
end

function ns.Quest(id)
	local q = quests[id]
	if q ~= nil then return q or nil end
	local s = ns.raw.quests[id]
	if s then
		local fn = loadstring("return " .. s)
		q = fn and fn() or false
	else
		q = false
	end
	if q then q.id = id end
	quests[id] = q
	return q or nil
end

function ns.Npc(id)
	local n = npcs[id]
	if n ~= nil then return n or nil end
	local s = ns.raw.npcs[id]
	if s then
		local name, lo, hi, friendly, spawns = s:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
		n = { id = id, name = name, min = tonumber(lo) or 0, max = tonumber(hi) or 0, friendly = friendly, spawns = ns.Spawns(spawns) }
	else
		n = false
	end
	npcs[id] = n
	return n or nil
end

function ns.Object(id)
	local o = objects[id]
	if o ~= nil then return o or nil end
	local s = ns.raw.objects[id]
	if s then
		local name, spawns = s:match("^([^|]*)|(.*)$")
		o = { id = id, name = name, spawns = ns.Spawns(spawns) }
	else
		o = false
	end
	objects[id] = o
	return o or nil
end

function ns.Item(id)
	local it = items[id]
	if it ~= nil then return it or nil end
	local s = ns.raw.items[id]
	if s then
		local name, n, o, i, v = s:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
		it = { id = id, name = name, npcs = list(n), objects = list(o), items = list(i), vendors = list(v) }
	else
		it = false
	end
	items[id] = it
	return it or nil
end

local indexCache = { starts = {}, ends = {}, zonequests = {} }
function ns.Index(kind, key)
	local c = indexCache[kind]
	local l = c[key]
	if l then return l end
	l = list(ns.raw[kind][key])
	c[key] = l
	return l
end

function ns.ZoneName(zone)
	if not zone then return "Other" end
	if zone > 0 then
		local name
		if C_Map and C_Map.GetAreaInfo then name = C_Map.GetAreaInfo(zone) end
		return name or ("Zone " .. zone)
	end
	return ns.SORTS[zone] or "Other"
end

function ns.MapName(map)
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	return info and info.name or ("Map " .. map)
end

ns.SORTS = {
	[-1] = "Epic", [-22] = "Seasonal", [-24] = "Herbalism", [-25] = "Battlegrounds", [-61] = "Warlock",
	[-81] = "Warrior", [-82] = "Shaman", [-101] = "Fishing", [-121] = "Blacksmithing", [-141] = "Paladin",
	[-161] = "Mage", [-162] = "Rogue", [-181] = "Alchemy", [-182] = "Leatherworking", [-201] = "Engineering",
	[-261] = "Hunter", [-262] = "Priest", [-263] = "Druid", [-264] = "Tailoring", [-284] = "Special",
	[-304] = "Cooking", [-324] = "First Aid", [-364] = "Darkmoon Faire", [-365] = "Ahn'Qiraj War",
	[-366] = "Lunar Festival", [-367] = "Reputation", [-368] = "Invasion", [-369] = "Midsummer",
	[-370] = "Brewfest", [-284] = "Special",
}

local RACEBIT = { 1, 2, 4, 8, 16, 32, 64, 128 }
local CLASSBIT = { 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024 }

local function has(mask, b)
	return math.floor(mask / b) % 2 == 1
end

function ns.ForPlayer(q)
	if q.r then
		local b = RACEBIT[ns.playerRace or 0]
		if b and not has(q.r, b) then return false end
	end
	if q.c then
		local b = CLASSBIT[ns.playerClassID or 0]
		if b and not has(q.c, b) then return false end
	end
	return true
end

function ns.QuestTitle(id)
	local q = ns.Quest(id)
	if not q then return "Quest " .. id end
	return q.n
end

function ns.QuestLevel(q)
	local l = q.l or 0
	if l <= 0 then return ns.playerLevel or 60 end
	return l
end

function ns.DifficultyColor(level)
	local diff = level - (ns.playerLevel or 60)
	if diff >= 5 then return 1, 0.1, 0.1 end
	if diff >= 3 then return 1, 0.5, 0.25 end
	if diff >= -2 then return 1, 0.82, 0 end
	local green = GetQuestGreenRange and GetQuestGreenRange() or 8
	if type(green) ~= "number" then green = 8 end
	if -diff <= green then return 0.25, 0.75, 0.25 end
	return 0.6, 0.6, 0.6
end

function ns.Trivial(q)
	local level = q.l or 0
	if level <= 0 then return false end
	local green = GetQuestGreenRange and GetQuestGreenRange() or 8
	if type(green) ~= "number" then green = 8 end
	return (ns.playerLevel or 60) - level > green
end

local PALETTE = {
	{ 0.35, 0.75, 1 }, { 1, 0.45, 0.35 }, { 0.5, 1, 0.45 }, { 1, 0.6, 1 }, { 1, 0.75, 0.25 },
	{ 0.45, 1, 0.9 }, { 0.75, 0.6, 1 }, { 1, 1, 0.45 }, { 1, 0.5, 0.7 }, { 0.6, 0.85, 0.55 },
}

function ns.QuestColor(id)
	local c = PALETTE[id % #PALETTE + 1]
	return c[1], c[2], c[3]
end

local function someSpawn(spawns)
	for map, pts in pairs(spawns) do
		if pts[1] then return map, pts[1], pts[2] end
	end
end

function ns.StarterPlace(q)
	for _, id in ipairs(q.s1 or EMPTY) do
		local n = ns.Npc(id)
		if n then
			local map, x, y = someSpawn(n.spawns)
			return n.name, map, x, y
		end
	end
	for _, id in ipairs(q.s2 or EMPTY) do
		local o = ns.Object(id)
		if o then
			local map, x, y = someSpawn(o.spawns)
			return o.name, map, x, y
		end
	end
	for _, id in ipairs(q.s3 or EMPTY) do
		local it = ns.Item(id)
		if it then return it.name .. " (item)" end
	end
end

function ns.FinisherPlace(q)
	for _, id in ipairs(q.e1 or EMPTY) do
		local n = ns.Npc(id)
		if n then
			local map, x, y = someSpawn(n.spawns)
			return n.name, map, x, y
		end
	end
	for _, id in ipairs(q.e2 or EMPTY) do
		local o = ns.Object(id)
		if o then
			local map, x, y = someSpawn(o.spawns)
			return o.name, map, x, y
		end
	end
end

local names
function ns.SearchQuests(query, limit)
	local words = {}
	for w in query:lower():gmatch("%S+") do words[#words + 1] = w end
	local out = {}
	if #words == 0 then return out end
	if not names then
		names = {}
		for id, s in pairs(ns.raw.quests) do
			local n = s:match('n="(.-[^\\])"')
			if n then names[#names + 1] = { id, n:gsub('\\"', '"'):lower() } end
		end
		table.sort(names, function(a, b)
			if a[2] ~= b[2] then return a[2] < b[2] end
			return a[1] < b[1]
		end)
	end
	local num = tonumber(query)
	if num and ns.raw.quests[num] then out[#out + 1] = num end
	for _, e in ipairs(names) do
		local ok = true
		for i = 1, #words do
			if not e[2]:find(words[i], 1, true) then ok = false break end
		end
		if ok then
			out[#out + 1] = e[1]
			if #out >= (limit or 300) then break end
		end
	end
	return out
end
