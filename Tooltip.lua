local _, ns = ...

local function npcFromGuid(guid)
	if type(guid) ~= "string" or ns.IsSecret(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

local function addLines(tooltip, npc)
	if not ns.db or not ns.db.tooltip or not npc then return end
	local list = ns.Log.npcs[npc]
	if not list then return end
	local seen = {}
	for _, entry in ipairs(list) do
		local e = entry.quest
		if not seen[e.id] then
			seen[e.id] = true
			local r, g, b = ns.QuestColor(e.id)
			tooltip:AddLine(e.title or ns.QuestTitle(e.id), r, g, b)
		end
		if entry.text then tooltip:AddLine("  " .. entry.text, 0.9, 0.9, 0.92) end
	end
	tooltip:Show()
end

local function fromData(tooltip, data)
	if tooltip ~= GameTooltip then return end
	local guid = data and data.guid
	if not guid and UnitGUID then
		local ok, g = pcall(UnitGUID, "mouseover")
		if ok then guid = g end
	end
	addLines(tooltip, npcFromGuid(guid))
end

ns:Listen("LOGIN", function()
	local hooked = false
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
		hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tooltip, data)
			pcall(fromData, tooltip, data)
		end)
	end
	if not hooked and GameTooltip and GameTooltip.HookScript then
		pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip)
			pcall(fromData, tooltip, nil)
		end)
	end
end)
