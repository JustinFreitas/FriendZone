--
-- Please see the license.txt file included with this distribution for
-- attribution and copyright information.
--

FRIENDZONE_USE_OF_EFFECT = "FRIENDZONE_USE_OF_EFFECT";
local notifyAddHolderOwnershipOriginal;

function onInit()
	OptionsManager.registerOption2(FRIENDZONE_USE_OF_EFFECT, false, "option_header_friendzone", "option_label_friendzone_use_of_effect", "option_entry_cycler",
	{ labels = "option_val_off", values = "off", baselabel = "option_val_on", baseval = "on", default = "on" })

	if AssistantGMManager then
		notifyAddHolderOwnershipOriginal = AssistantGMManager.NotifyAddHolderOwnership;
		AssistantGMManager.NotifyAddHolderOwnership = notifyAddHolderOwnership;
	end
	if Session.IsHost then
		DB.addHandler("charsheet.*.level", "onUpdate", onLevelChanged)
	end
end

function checkUseOfEffectOption()
	return OptionsManager.getOption(FRIENDZONE_USE_OF_EFFECT) == "on";
end

function onClose()
	if Session.IsHost then
		DB.removeHandler("charsheet.*.level", "onUpdate", onLevelChanged)
	end
end


function onLevelChanged(nodeLevel)
	local nodeChar = nodeLevel.getChild("..");
	for _,nodeCohort in pairs(DB.getChildren(nodeChar, "cohorts")) do
		levelUpCohort(nodeCohort);
	end
end

function addCohort(nodeChar, nodeNPC)
	local nodeCohorts = nodeChar.createChild("cohorts");
	if not nodeCohorts then
		return;
	end

	local nodeNewCohort = nodeCohorts.createChild();
	if not nodeNewCohort then
		return;
	end

	DB.copyNode(nodeNPC, nodeNewCohort);
	DB.setValue(nodeNewCohort, "commandernodename", "string", nodeChar.getNodeName()); -- for effect option
	HpManagerFZ.updateNpcHitPoints(nodeNewCohort);
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
	DB.setValue(nodeNewUnit, "commandernodename", "string", nodeChar.getNodeName()); -- for effect option

	DB.setValue(nodeNewUnit, "commander", "string", DB.getValue(nodeChar, "name", ""));
end

function addVehicle(nodeChar, nodeVehicle)
	local nodeVehicles = nodeChar.createChild("vehicles");
	if not nodeVehicles then
		return;
	end

	local nodeNewVehicle = nodeVehicles.createChild();
	if not nodeNewVehicle then
		return;
	end

	DB.copyNode(nodeVehicle, nodeNewVehicle);
	DB.setValue(nodeNewVehicle, "commandernodename", "string", nodeChar.getNodeName()); -- for effect option
end

function isCohort(vRecord)
	local rActor = ActorManager.resolveActor(vRecord);
	if rActor and rActor.sCreatureNode
	and (rActor.sCreatureNode:match("%.cohorts%.") or rActor.sCreatureNode:match("%.vehicles%.")) then
		return true;
	end

	return false;
end

function notifyAddHolderOwnership(node, sUserName, bOwner, bForceAccessRemoval)
	local rActor = ActorManager.resolveActor(node);
	if isCohort(rActor) then
		if bOwner then
			ChatManager.SystemMessage(Interface.getString("assistant_gm_cohort_ownership"));
		end
	else
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
	HpManagerFZ.updateNpcHitPoints(nodeCohort);
end