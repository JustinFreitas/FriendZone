-- 
-- Please see the license.txt file included with this distribution for 
-- attribution and copyright information.
--

local getNpcHitDiceOriginal;
local canHandleExtraHealthFieldsOriginal;

function onInit()
	if HpManager then
		getNpcHitDiceOriginal = HpManager.getNpcHitDice;
		HpManager.getNpcHitDice = getNpcHitDice;
	
		canHandleExtraHealthFieldsOriginal = HpManager.canHandleExtraHealthFields;
		HpManager.canHandleExtraHealthFields = canHandleExtraHealthFields;
	end
end

function getNpcHitDice(nodeNPC)
	local sHD = StringManager.trim(DB.getValue(nodeNPC, "hd", ""));
	if sHD == "(see notes)" and FriendZone.isCohort(nodeNPC) then
		local sText = DB.getValue(nodeNPC, "text", "");
		local aLines = StringManager.splitByPattern(sText, "<p>", true);
		for _,sLine in ipairs(aLines) do
			sLine = sLine:gsub("</?%w>", ""):lower();
			if StringManager.startsWith(sLine, "hit dice:") then
				local nodeCommander = FriendZone.getCommanderNode(nodeNPC);
				local nHDMult, nHDSides;
				if nodeCommander then
					local sClass = sLine:match("([%w]+)%'?s? level");
					if StringManager.contains(DataCommon.classes, sClass) then
						nHDMult = ActorManager5E.getClassLevel(nodeCommander, sClass);
					else
						nHDMult = DB.getValue(nodeCommander, "level", 0);
					end

					local sSides = sLine:match("d(%d+)");
					if sSides then
						nHDSides = tonumber(sSides)
					end
				end

				return nHDMult, nHDSides;
			end
		end
	else
		return getNpcHitDiceOriginal(nodeNPC);
	end
end

function updateNpcHitPoints(nodeNPC)
	local sHD = StringManager.trim(DB.getValue(nodeNPC, "hd", ""));
	if sHD == "(see notes)" and FriendZone.isCohort(nodeNPC) then
		local nodeCommander = FriendZone.getCommanderNode(nodeNPC);
		if nodeCommander then
			local sText = DB.getValue(nodeNPC, "text", "");
			local aLines = StringManager.splitByPattern(sText, "<p>", true);
			for _,sLine in ipairs(aLines) do
				sLine = sLine:gsub("</?%w>", ""):lower();
				if StringManager.startsWith(sLine, "hit points:") then
					local sClass = sLine:match("([%w]+)%'?s? level");
					local nLevels;
					if StringManager.contains(DataCommon.classes, sClass) then
						nLevels = ActorManager5E.getClassLevel(nodeCommander, sClass);
					else
						nLevels = DB.getValue(nodeCommander, "level", 0);
					end

					local sAbility;
					local sMod, sModOrAbility, sPerLevel = sLine:match("(%d?%d?) ?%+? ?t?h?e? %w*'?s? (%w*) m?o?d?i?f?i?e?r? ?%+? ?([%d%w]+) times the");

					local nMod = 0;
					if (sMod or "") ~= "" then
						nMod = tonumber(sMod);
						sAbility = sModOrAbility;
					elseif sModOrAbility then
						nMod = tonumber(sModOrAbility);
					end

					local nAbility = 0;
					if sAbility and StringManager.contains(DataCommon.abilities, sAbility) then
						nAbility = DB.getValue(nodeCommander, "abilities.".. sAbility .. ".bonus", 0);
					end

					if sPerLevel then
						local nPerLevel = CharManager.convertSingleNumberTextToNumber(sPerLevel);
						if (nPerLevel or 0) == 0 then
							nPerLevel = tonumber(sPerLevel);
						end
						local nHP = nMod + nAbility + (nPerLevel * nLevels);
						DB.setValue(nodeNPC, "hp", "number", nHP);
						break;
					end
				end
			end
		end
	end
end

function canHandleExtraHealthFields(nodeNPC)
	if not canHandleExtraHealthFieldsOriginal(nodeNPC) then
		return FriendZone.isCohort(nodeNPC);
	end
	return true;
end