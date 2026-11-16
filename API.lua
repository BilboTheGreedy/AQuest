local _, ns = ...

AQuest = {}

function AQuest.IsQuestMob(npc)
	return ns.Log.npcs[npc] ~= nil
end

function AQuest.QuestsFor(npc)
	local out = {}
	for _, entry in ipairs(ns.Log.npcs[npc] or {}) do
		out[#out + 1] = { id = entry.quest.id, title = entry.quest.title, text = entry.text }
	end
	return out
end

function AQuest.InLog(id)
	return ns.Log.quests[id] ~= nil
end

function AQuest.Open(id)
	if id then
		ns.Journal.ShowQuest(id)
	else
		ns.Journal.Show()
	end
end

function AQuest.IsQuestUnit(unit)
	if not unit or not UnitGUID then return false end
	local ok, guid = pcall(UnitGUID, unit)
	if not ok or type(guid) ~= "string" or ns.IsSecret(guid) then return false end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return false end
	return ns.Log.npcs[tonumber(id) or 0] ~= nil
end
