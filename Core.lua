local ADDON, ns = ...

ns.raw = {}

local defaults = {
	available = true,
	trivial = false,
	repeatable = false,
	objectives = true,
	turnins = true,
	minimap = true,
	tooltip = true,
	tracker = true,
	pinSize = 1,
	trackerDb = { scale = 1, locked = false, default = { "RIGHT", "RIGHT", -60, 60 } },
	journal = { scale = 1 },
}

local charDefaults = {
	untracked = {},
}

ACore.New(ADDON, ns, { db = "AQuestDB", defaults = defaults, char = "AQuestCharDB", charDefaults = charDefaults })

ACore.Register({
	name = "AQuest",
	title = "AQuest",
	slash = "/aquest",
	desc = "quest map, tracker and journal",
	toggle = function() ns.Journal.Toggle() end,
})

function ns.Options()
	local db = ns.db
	local UI = ns.UI
	local function changed() ns:Fire("OPTIONS") end
	local entries = {
		{ text = "Map", title = true },
		UI.Check(db, "available", "Show available quests", changed),
		UI.Check(db, "trivial", "Include low level quests", changed),
		UI.Check(db, "repeatable", "Include repeatable quests", changed),
		UI.Check(db, "objectives", "Show objectives", changed),
		UI.Check(db, "turnins", "Show turn-ins", changed),
		UI.Check(db, "minimap", "Show on the minimap", changed),
		{ text = "Other", title = true },
		UI.Check(db, "tracker", "Quest tracker", changed),
		UI.Check(db.trackerDb, "locked", "Lock the tracker", changed),
		UI.Check(db, "tooltip", "Quest progress in tooltips", changed),
		{ text = "Pin size", title = true },
	}
	for _, s in ipairs({ 0.75, 1, 1.25, 1.5 }) do
		entries[#entries + 1] = {
			text = math.floor(s * 100 + 0.5) .. "%", checked = math.abs(db.pinSize - s) < 0.01,
			func = function()
				db.pinSize = s
				changed()
			end,
		}
	end
	return entries
end

SLASH_AQUEST1 = "/aquest"
SLASH_AQUEST2 = "/aq"
SlashCmdList["AQUEST"] = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd = msg:lower()
	if cmd == "" then
		ns.Journal.Toggle()
	elseif cmd == "tracker" then
		ns.db.tracker = not ns.db.tracker
		ns:Fire("OPTIONS")
	elseif cmd == "reset" then
		ns.db.trackerDb.pos = nil
		ns.db.journal.pos = nil
		ns:Fire("LAYOUT_RESET")
	else
		ns.Journal.Show()
		ns.Journal.SetSearch(msg)
	end
end

BINDING_HEADER_AQUEST = "AQuest"
BINDING_NAME_AQUEST_TOGGLE = "Toggle quest journal"
function AQuest_ToggleBinding()
	ns.Journal.Toggle()
end
