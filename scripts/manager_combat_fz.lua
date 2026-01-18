-- 
-- Please see the license.txt file included with this distribution for 
-- attribution and copyright information.
--

local showTurnMessageOriginal;
local centerOnTokenOriginal;
local addUnitOriginal;
local onNPCPostAddOriginal;
local addNPCHelperOriginal;
local rollInitOriginal;
local rollInit2Original;
local rollEntryInitOriginal;
local resetInitOriginal;

function onInit()
    if not CombatManager then
        Debug.console("FZ ERROR: CombatManager not found. Aborting.");
        return;
    end

	showTurnMessageOriginal = CombatManager.showTurnMessage;
	CombatManager.showTurnMessage = showTurnMessage;

	centerOnTokenOriginal = CombatManager.centerOnToken;
	CombatManager.centerOnToken = centerOnToken;
	
	rollInitOriginal = CombatManager.rollInit;
	CombatManager.rollInit = rollInitFZ;
	
	if CombatManager2 then
		rollInit2Original = CombatManager2.rollInit;
		CombatManager2.rollInit = rollInit2FZ;
	end
	
	rollEntryInitOriginal = CombatManager.rollEntryInit;
	CombatManager.rollEntryInit = rollEntryInitFZ;

	resetInitOriginal = CombatManager.resetInit;
	CombatManager.resetInit = resetInitFZ;

	if CombatRecordManager then
		onNPCPostAddOriginal = CombatRecordManager.getRecordTypePostAddCallback("npc");
		CombatRecordManager.setRecordTypePostAddCallback("npc", onNPCPostAdd);
	else
		addNPCHelperOriginal = CombatManager.addNPCHelper;
		CombatManager.addNPCHelper = addNPCHelper;
	end

	onSortCompareOriginal = CombatManager.onSortCompare;
	CombatManager.onSortCompare = onSortCompareFZ;

	if CombatManagerKw then
		addUnitOriginal = CombatManagerKw.addUnit;
		CombatManagerKw.addUnit = addUnit;
	end
	
	DB.addHandler("combattracker.list.*.initresult", "onUpdate", onInitResultChanged);
	
end

function rollInitFZ(tCustom)
    if rollInitOriginal then rollInitOriginal(tCustom); end
    syncAllCohorts(true);
end

function resetInitFZ()
	if resetInitOriginal then resetInitOriginal(); end

	-- Gather all combatants
	local tCombatants = {};
	for _, node in pairs(DB.getChildren(CombatManager.CT_LIST)) do
		table.insert(tCombatants, node);
	end
	
	-- Sort alphabetically by name to define fallback order
	table.sort(tCombatants, function(a, b)
		return (DB.getValue(a, "name", ""):lower()) < (DB.getValue(b, "name", ""):lower());
	end);
	
	-- Assign tiny unique initiatives to commanders/solo PCs to force grouping
	-- Higher rank = higher initiative = top of list
	local nCount = #tCombatants;
	for i, node in ipairs(tCombatants) do
		local sCmdrPath = DB.getValue(node, "commandernodename", "");
		if sCmdrPath == "" then
			local nInit = (nCount - i + 1) * 0.0001; 
			DB.setValue(node, "initresult", "number", nInit);
		end
	end
	
	syncAllCohorts(false);
	
	-- Force a resort
	if CombatManager.sortCombatantList then
		CombatManager.sortCombatantList();
	end
end

function rollInit2FZ(tCustom)
    if rollInit2Original then rollInit2Original(tCustom); end
    syncAllCohorts(true);
end

function syncAllCohorts(bVerbose)
    -- Pass 1: Gather Commander Inits
    local tCommanderInits = {};
    for _,nodeCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
        local sClass, sRecord = DB.getValue(nodeCT, "link");
        if sRecord and type(sRecord) == "string" then
            sRecord = sRecord:match("^%s*(.-)%s*$");
            if sRecord ~= "" then
                tCommanderInits[sRecord] = DB.getValue(nodeCT, "initresult", 0);
            end
        end
    end
    
    -- Pass 2: Apply to Cohorts
    for _,nodeCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
        local sMyCommander = DB.getValue(nodeCT, "commandernodename", "");
        if sMyCommander ~= "" then
            sMyCommander = sMyCommander:match("^%s*(.-)%s*$");
            if tCommanderInits[sMyCommander] then
                DB.setValue(nodeCT, "initresult", "number", tCommanderInits[sMyCommander]);
            end
        end
    end
end

function rollEntryInitFZ(nodeEntry)
    if rollEntryInitOriginal then rollEntryInitOriginal(nodeEntry); end
    fixCohortInit(nodeEntry, true);
end

function hex_dump(str)
    if not str then return "nil" end;
    local len = string.len(str)
    local hex = ""
    for i = 1, len do
        local ord = string.byte(str, i)
        hex = hex .. string.format("%02X ", ord)
    end
    return hex
end

function fixCohortInit(nodeCohort, bVerbose)
	local sMyCommanderNodeName = DB.getValue(nodeCohort, "commandernodename", "");
	if sMyCommanderNodeName ~= "" then
		sMyCommanderNodeName = sMyCommanderNodeName:match("^%s*(.-)%s*$");
		
		for _,nodeCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
			local sClass, sRecord = DB.getValue(nodeCT, "link");
			if sRecord and type(sRecord) == "string" then 
				sRecord = sRecord:match("^%s*(.-)%s*$"); 
				
				if sRecord == sMyCommanderNodeName then
					local nCommanderInit = DB.getValue(nodeCT, "initresult", 0);
					DB.setValue(nodeCohort, "initresult", "number", nCommanderInit);
					return;
				end
			end
		end
	end
end

function onNPCPostAdd(tCustom)
	if onNPCPostAddOriginal then
		onNPCPostAddOriginal(tCustom);
	end

	processCohort(tCustom.nodeCT, tCustom.nodeRecord);
end

function addNPCHelper(nodeNPC, sName)
	local nodeEntry, nodeLastMatch = addNPCHelperOriginal(nodeNPC, sName);
	if nodeEntry then
		processCohort(nodeEntry, nodeNPC);
	end
	return nodeEntry, nodeLastMatch;
end

function processCohort(nodeCT, nodeRecord)
	if nodeRecord and nodeCT and FriendZone.isCohort(nodeRecord) then
		DB.setValue(nodeCT, "link", "windowreference", "npc", nodeRecord.getPath());
		
		local sCommanderNode = DB.getValue(nodeRecord, "commandernodename", "");
		DB.setValue(nodeCT, "commandernodename", "string", sCommanderNode);

		setCohortFaction(nodeCT);
		addCohortOfEffectIfEnabled(nodeCT);
		
		-- [NEW] Initial Sync: If commander is already in CT, snap to them.
		if sCommanderNode ~= "" then
			sCommanderNode = sCommanderNode:match("^%s*(.-)%s*$"); -- TRIM
			for _,nodeExistingCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
				local sClass, sRecord = DB.getValue(nodeExistingCT, "link");
				if sRecord then sRecord = sRecord:match("^%s*(.-)%s*$"); end -- TRIM
				
				if sRecord and sRecord == sCommanderNode then
					local nCommanderInit = DB.getValue(nodeExistingCT, "initresult", 0);
					DB.setValue(nodeCT, "initresult", "number", nCommanderInit);
					break;
				end
			end
		end
	end
end

function showTurnMessage(nodeEntry, bActivate, bSkipBell)
	showTurnMessageOriginal(nodeEntry, bActivate, bSkipBell);

	local sClass, sRecord = DB.getValue(nodeEntry, "link", "", "");
	local bHidden = CombatManager.isCTHidden(nodeEntry);
	if not bHidden and (sClass ~= "charsheet") then -- Allow non-character sheet turns as well for the sake of cohorts.
		if bActivate and not bSkipBell and OptionsManager.isOption("RING", "on") then
			if sRecord ~= "" then
				local nodeCohort = DB.findNode(sRecord);
				if nodeCohort then
					local sOwner = nodeCohort.getOwner();
					if sOwner then
						User.ringBell(sOwner);
					end
				end
			end
		end
	end
end

function centerOnToken(nodeEntry, bOpen)
	centerOnTokenOriginal(nodeEntry, bOpen);

	if not Session.IsHost and
	FriendZone.isCohort(nodeEntry) and
	DB.isOwner(ActorManager.getCreatureNode(nodeEntry)) then
		ImageManager.centerOnToken(CombatManager.getTokenFromCT(nodeEntry), bOpen);
	end
end

function setCohortFaction(nodeCohort)
	-- Check DB node, and if available, use it for friendfoe status (if PC, assume friend.  if NPC, get status).
	local nodeCommander = DB.findNode(DB.getValue(nodeCohort, "commandernodename", ""));
	local sFaction = "friend";
	if nodeCommander and not ActorManager.isPC(nodeCommander) then
		-- Use NPC friendfoe.
		sFaction = DB.getValue(nodeCommander, "friendfoe", sFaction);
	end

	DB.setValue(nodeCohort, "friendfoe", "string", sFaction);
end

function addCohortOfEffectIfEnabled(nodeCohort)
	if not nodeCohort or not FriendZone.checkUseCohortEffectOption() then return end

	-- TODO: If effect option set, mark CT entry with 'Cohort of [ACTOR_NAME]', visible to all but in GM control.
	local nodeCommander = DB.findNode(DB.getValue(nodeCohort, "commandernodename", ""));
	local sCommanderName = ActorManager.getDisplayName(nodeCommander);
	if sCommanderName ~= "" then
		local rEffect = {
			sName = "Cohort of " .. sCommanderName;
			nInit = 0,
			nDuration = 0,
			nGMOnly = ActorManager.getFaction(nodeCohort) ~= "friend" and 1 or 0
		};

		EffectManager.addEffect("", "", nodeCohort, rEffect, false);
	end
end

function addUnit(sClass, nodeUnit, sName)
	local nodeEntry = addUnitOriginal(sClass, nodeUnit, sName);
	if nodeEntry then
		local bIsCohort = FriendZone.isCohort(nodeUnit);
		if bIsCohort then
			DB.setValue(nodeEntry, "link", "windowreference", "reference_unit", nodeUnit.getPath());
			DB.setValue(nodeEntry, "friendfoe", "string", "friend");
		end
	end

	return nodeEntry;
end

function processSubinitChatCommand()
	local tChildren = DB.getChildren(CombatManager.CT_LIST);

	-- Strategy 1: Name Regex (Legacy/Fallback)
	for _,nodeCT in pairs(tChildren) do
		local sCharacterName = ActorManager.getDisplayName(nodeCT);
		local sMsgSafeName = sCharacterName:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1");
		local sRegex = "^" .. sMsgSafeName .. "'s?.*$";
		local nNodeCTInit = DB.getValue(nodeCT, "initresult", 0);

		for _,subNodeCT in pairs(tChildren) do
			if nodeCT ~= subNodeCT then
				local sSubName = ActorManager.getDisplayName(subNodeCT);
				if string.match(sSubName, sRegex) then
					DB.setValue(subNodeCT, "initresult", "number", nNodeCTInit);
				end
			end
		end
	end

	-- Strategy 2: DB Link (Authoritative)
	local tRecordInits = {};
	for _,nodeCT in pairs(tChildren) do
		local sClass, sRecord = DB.getValue(nodeCT, "link", "", "");
		if sRecord ~= "" then
			tRecordInits[sRecord] = DB.getValue(nodeCT, "initresult", 0);
		end
	end

	for _,nodeCT in pairs(tChildren) do
		local sCommanderNode = DB.getValue(nodeCT, "commandernodename", "");
		if sCommanderNode ~= "" and tRecordInits[sCommanderNode] then
			DB.setValue(nodeCT, "initresult", "number", tRecordInits[sCommanderNode]);
		end
	end

	ChatManager.SystemMessage("Sub-initiatives processed.");
end

local bUpdating = false;

function onInitResultChanged(nodeField)
	if bUpdating then return; end

	local nodeCommander = nodeField.getParent();
	local nNewInit = nodeField.getValue();
	
	-- Identify Commander Link
	local sClass, sRecord = DB.getValue(nodeCommander, "link");
	if sRecord then sRecord = sRecord:match("^%s*(.-)%s*$"); end -- TRIM
	
	-- Identify Commander Name (for regex)
	local sCharacterName = ActorManager.getDisplayName(nodeCommander);
	local sMsgSafeName = sCharacterName:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1");
	local sRegex = "^" .. sMsgSafeName .. "'s?.*$";
	
	-- Iterate all CT nodes to find cohorts
	local bFoundCohort = false;
	for _,nodeCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
		if nodeCT ~= nodeCommander then
			local bMatch = false;
			local sMatchType = "";
			
			-- Check Link (Authoritative)
			local sCohortCommander = DB.getValue(nodeCT, "commandernodename", "");
			if sCohortCommander then sCohortCommander = sCohortCommander:match("^%s*(.-)%s*$"); end -- TRIM
			
			if sCohortCommander and sCohortCommander ~= "" and sCohortCommander == sRecord then
				bMatch = true;
				sMatchType = "Link";
			end
			
			-- Check Regex (Fallback)
			if not bMatch then
				local sSubName = ActorManager.getDisplayName(nodeCT);
				if string.match(sSubName, sRegex) then
					bMatch = true;
					sMatchType = "Regex";
				end
			end
			
			if bMatch then
				bFoundCohort = true;
				local nOldInit = DB.getValue(nodeCT, "initresult", 0);
				if nOldInit ~= nNewInit then
					bUpdating = true;
					DB.setValue(nodeCT, "initresult", "number", nNewInit);
					bUpdating = false;
				end
			end
		end
	end
end

function onSortCompareFZ(node1, node2)
	local nInit1 = DB.getValue(node1, "initresult", 0);
	local nInit2 = DB.getValue(node2, "initresult", 0);
	
	if nInit1 == nInit2 then
		local sCmdr1 = DB.getValue(node1, "commandernodename", "");
		local sCmdr2 = DB.getValue(node2, "commandernodename", "");
		
		-- TRIM
		if sCmdr1 then sCmdr1 = sCmdr1:match("^%s*(.-)%s*$"); end
		if sCmdr2 then sCmdr2 = sCmdr2:match("^%s*(.-)%s*$"); end
		
		local sClass1, sRecord1 = DB.getValue(node1, "link");
		local sClass2, sRecord2 = DB.getValue(node2, "link");
		
		-- TRIM
		if sRecord1 then sRecord1 = sRecord1:match("^%s*(.-)%s*$"); end
		if sRecord2 then sRecord2 = sRecord2:match("^%s*(.-)%s*$"); end
		
		-- Node1 is Commander of Node2? (Check Node2's commander against Node1's link)
		if sCmdr2 and sCmdr2 ~= "" and sCmdr2 == sRecord1 then
			return false; -- Node1 (Commander) comes after (Cohort on top)
		end
		
		-- Node2 is Commander of Node1? (Check Node1's commander against Node2's link)
		if sCmdr1 and sCmdr1 ~= "" and sCmdr1 == sRecord2 then
			return true; -- Node2 (Commander) comes after (Cohort on top)
		end
	end
	
	if onSortCompareOriginal then
		return onSortCompareOriginal(node1, node2);
	end

	-- Fallback default sort if no original function (Init Desc > Name Asc)
	if nInit1 ~= nInit2 then
		return nInit1 > nInit2;
	end
	local sName1 = DB.getValue(node1, "name", "");
	local sName2 = DB.getValue(node2, "name", "");
	return sName1 < sName2;
end
