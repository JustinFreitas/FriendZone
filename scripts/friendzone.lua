-- 
-- Please see the license.txt file included with this distribution for 
-- attribution and copyright information.
--

FRIENDZONE_USE_COHORT_EFFECT = "FRIENDZONE_USE_COHORT_EFFECT";
local notifyAddHolderOwnershipOriginal;

-- Helper to safely get an actor from a node/string, preferring the modern getActor method.
local function getActorSafe(v)
    if ActorManager.getActor then
        return ActorManager.getActor(v)
    end
    return ActorManager.resolveActor(v)
end

-- Helper to safely get an actor's type and node, preferring the modern getTypeAndNode method.
local function getTypeAndNodeSafe(v)
    if ActorManager.getTypeAndNode then
        return ActorManager.getTypeAndNode(v)
    end
    return ActorManager.getActorTypeAndNode(v)
end

-- Helper to safely check for effects, preferring the 5E-specific EffectManager5E if available.
local function hasEffectSafe(rActor, sEffect)
    if EffectManager5E and EffectManager5E.hasEffect then
        return EffectManager5E.hasEffect(rActor, sEffect)
    end
    return EffectManager.hasEffect(rActor, sEffect)
end

function onInit()
	OptionsManager.registerOption2(FRIENDZONE_USE_COHORT_EFFECT, false, "option_header_friendzone", "option_label_friendzone_use_cohort_effect", "option_entry_cycler",
	{ labels = "option_val_off", values = "off", baselabel = "option_val_on", baseval = "on", default = "on" })

	if AssistantGMManager then
		notifyAddHolderOwnershipOriginal = AssistantGMManager.NotifyAddHolderOwnership;
		AssistantGMManager.NotifyAddHolderOwnership = notifyAddHolderOwnership;
	end
	if Session.IsHost then
		Comm.registerSlashHandler("subinit", CombatManagerFZ.processSubinitChatCommand);
		Comm.registerSlashHandler("fzsync", processSyncCommand);
		Comm.registerSlashHandler("fzfix", processFixCohortsCommand);
		DB.addHandler("charsheet.*.level", "onUpdate", onLevelChanged)
	end
end

function processSyncCommand(sCommand, sParams)
	if CombatManagerFZ and CombatManagerFZ.syncAllCohorts then
		CombatManagerFZ.syncAllCohorts(true);
	else
		ChatManager.SystemMessage("CombatManagerFZ.syncAllCohorts not found.");
	end
end

function processFixCohortsCommand(sCommand, sParams)
	local nFixed = 0;
	local nTotal = 0;

	for _,nodeChar in pairs(DB.getChildren("charsheet")) do
		local nodeCohorts = nodeChar.getChild("cohorts");
		if nodeCohorts then
			for _,nodeCohort in pairs(DB.getChildren(nodeCohorts)) do
				nTotal = nTotal + 1;
				local bChanged = false;
				
				-- 1. Ensure commandernodename is set
				local sCurrentCommander = DB.getValue(nodeCohort, "commandernodename", "");
				local sNewCommander = nodeChar.getNodeName();
				if sCurrentCommander ~= sNewCommander then
					DB.setValue(nodeCohort, "commandernodename", "string", sNewCommander);
					bChanged = true;
				end
				
				-- 2. Recalculate HP
				if HpManagerFZ then
					HpManagerFZ.updateNpcHitPoints(nodeCohort);
				end
				
				-- 3. Sync hptotal to hp
				local nHP = DB.getValue(nodeCohort, "hp", 0);
				local nHPTotal = DB.getValue(nodeCohort, "hptotal", 0);
				if nHPTotal ~= nHP then
					DB.setValue(nodeCohort, "hptotal", "number", nHP);
					-- We consider this a fix/update
					bChanged = true; 
				end
				
				if bChanged then
					nFixed = nFixed + 1;
				end
			end
		end
	end
	
	ChatManager.SystemMessage("FriendZone: Examined " .. nTotal .. " cohorts. Updated " .. nFixed .. ".");
end

function checkUseCohortEffectOption()
	return OptionsManager.getOption(FRIENDZONE_USE_COHORT_EFFECT) == "on";
end

function onLevelChanged(nodeLevel)
	local nodeChar = nodeLevel.getChild("..");
	for _,nodeCohort in pairs(DB.getChildren(nodeChar, "cohorts")) do
		levelUpCohort(nodeCohort);
	end
end

function addCohort(nodeChar, nodeNPC)
	if nodeChar == nodeNPC then return end  -- prevent 'source/target same node' DB error at copyNode()

	local nodeCohorts = nodeChar.createChild("cohorts");
	if not nodeCohorts then
		return;
	end

	local nodeNewCohort = nodeCohorts.createChild();
	if not nodeNewCohort then
		return;
	end

	DB.copyNode(nodeNPC, nodeNewCohort);
	
	-- Prefix name with Commander's name and ensure uniqueness
	local sCommanderName = DB.getValue(nodeChar, "name", "");
	local sNPCName = DB.getValue(nodeNPC, "name", "");
	local sBaseName = sNPCName;
	if sCommanderName ~= "" and sNPCName ~= "" then
		sBaseName = sCommanderName .. "'s " .. sNPCName;
	end

	local sFinalName = sBaseName;
	
	-- Check for exact match or existing numbered versions
	local nodeOriginal = nil;
	local bHasNumbered = false;
	local sSafeBaseName = sBaseName:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"); -- Escape magic chars

	for _, vChild in pairs(DB.getChildren(nodeCohorts)) do
		if vChild ~= nodeNewCohort then
			local sChildName = DB.getValue(vChild, "name", "");
			if sChildName == sBaseName then
				nodeOriginal = vChild;
			elseif sChildName:match("^" .. sSafeBaseName .. " %d+$") then
				bHasNumbered = true;
			end
		end
	end

	if nodeOriginal then
		-- Original exists. Rename to "... 1"
		local sOriginalRename = sBaseName .. " 1";
		
		-- Ensure "Name 1" isn't magically taken (e.g. user manually named one "Ghoul 1" but left "Ghoul")
		local bSafeToRename = true;
		for _, vChild in pairs(DB.getChildren(nodeCohorts)) do
			if vChild ~= nodeNewCohort and vChild ~= nodeOriginal then
				if DB.getValue(vChild, "name", "") == sOriginalRename then
					bSafeToRename = false;
					break;
				end
			end
		end
		
		if bSafeToRename then
			DB.setValue(nodeOriginal, "name", "string", sOriginalRename);
			bHasNumbered = true; -- Now we effectively have a numbered series
		end
	end

	-- If we have a series (or just started one), find the next available number
	if bHasNumbered or nodeOriginal then
		local nSuffix = 1;
		local bUnique = false;
		
		while not bUnique do
			bUnique = true;
			local sTestName = sBaseName .. " " .. nSuffix;
			
			for _, vChild in pairs(DB.getChildren(nodeCohorts)) do
				if vChild ~= nodeNewCohort then
					local sChildName = DB.getValue(vChild, "name", "");
					if sChildName == sTestName then
						bUnique = false; -- Name taken
						break;
					end
				end
			end
			
			if not bUnique then
				nSuffix = nSuffix + 1;
			else
				sFinalName = sTestName;
			end
		end
	else
		-- No original, no series. Just use the base name.
		sFinalName = sBaseName;
	end

	DB.setValue(nodeNewCohort, "name", "string", sFinalName);

	-- TODO: For this, we'll need to override import/export to add/strip the values for that char.
	DB.setValue(nodeNewCohort, "commandernodename", "string", nodeChar.getNodeName());
	if HpManagerFZ then
		HpManagerFZ.updateNpcHitPoints(nodeNewCohort);
	end
	DB.setValue(nodeNewCohort, "hptotal", "number", DB.getValue(nodeNewCohort, "hp", 0));
end

function addUnit(nodeChar, nodeUnit)
	local nodeUnits = nodeChar.createChild("units");
	if not nodeUnits then
		return;
	end

	local nodeNewUnit = nodeUnits.createChild();
	if not nodeNewUnit then
		return;
	end

	DB.copyNode(nodeUnit, nodeNewUnit);

	DB.setValue(nodeNewUnit, "commander", "string", DB.getValue(nodeChar, "name", ""));
end

function isCohort(vRecord)
	local rActor = getActorSafe(vRecord);
	
	if rActor and rActor.sCreatureNode and rActor.sCreatureNode:match("%.cohorts%.") then
		return true;
	end

	return false;
end

function notifyAddHolderOwnership(node, sUserName, bOwner, bForceAccessRemoval)
	local rActor = getActorSafe(node);
	if isCohort(rActor) then
		if bOwner then
			ChatManager.SystemMessage(Interface.getString("assistant_gm_cohort_ownership"));
		end
	elseif notifyAddHolderOwnershipOriginal then
		notifyAddHolderOwnershipOriginal(node, sUserName, bOwner, bForceAccessRemoval);
	end
end

function getCommanderNode(vCohort)
	local nodeCohort = ActorManager.getCreatureNode(vCohort);
	return DB.getChild(nodeCohort, "...");
end

function levelUpCohort(nodeCohort)
	if HpManager then
		HpManager.updateNpcHitDice(nodeCohort);
	end
	if HpManagerFZ then
		HpManagerFZ.updateNpcHitPoints(nodeCohort);
	end
end
