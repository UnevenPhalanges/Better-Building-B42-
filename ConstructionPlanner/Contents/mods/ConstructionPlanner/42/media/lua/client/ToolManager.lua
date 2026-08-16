require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISGrabItemAction"
require "AdjacentFreeTileFinder"
ConstructionPlanner =
	ConstructionPlanner or {}


-- Release logging: disabled by default.
-- Set ConstructionPlanner.DEBUG = true to restore diagnostic output.
if ConstructionPlanner.DEBUG == nil then
	ConstructionPlanner.DEBUG = false
end

local function cpDebug(...)
	if ConstructionPlanner.DEBUG then
		print(...)
	end
end

------------------------------------------------------------
-- PLAYER HAS TOOL
------------------------------------------------------------

local function playerHasTool(
	player,
	fullType
)
	if not player
	or not fullType then
		return false
	end

	local inventory =
		player:getInventory()

	if not inventory then
		return false
	end

	local item =
		inventory:getItemFromType(
			fullType,
			true,
			true
		)

	if item then
		return true
	end

	return false
end

------------------------------------------------------------
-- FIND EXACT TOOL IN PLAYER INVENTORY
------------------------------------------------------------

local function findPlayerTool(
	player,
	fullType
)
	if not player
	or not fullType then
		return nil
	end

	local inventory =
		player:getInventory()

	if not inventory then
		return nil
	end

	return inventory:getItemFromType(
		fullType,
		true,
		true
	)
end


------------------------------------------------------------
-- FIND TOOL IN GATHER AREA GROUND ITEMS
------------------------------------------------------------

local function findToolInGatherAreas(
	fullType
)
	if not fullType
	or not ConstructionPlanner.getGroundItemsInGatherAreas then
		return nil, nil, nil
	end

	local entries =
		ConstructionPlanner.getGroundItemsInGatherAreas(
			nil,
			nil
		)

	for _, entry in ipairs(
		entries or {}
	) do

		if entry.item
		and entry.item:getFullType()
			== fullType then

			return entry.item,
				entry.worldObject,
				entry.square
		end
	end

	return nil, nil, nil
end


------------------------------------------------------------
-- PROJECT TOOL STATUS
--
-- SAME SOURCE PRIORITY / DISPLAY SHAPE AS DISMANTLE:
-- PLAYER -> SUPPLY CONTAINERS -> GATHER AREA.
------------------------------------------------------------

function ConstructionPlanner.getProjectToolStatus()
	local project =
		ConstructionPlanner.pendingProject

	local status = {
		allAvailable = true,
		requirements = {}
	}

	if not project
	or not project.requiredTools then
		return status
	end

	local player =
		getSpecificPlayer(0)

	for fullType, required in pairs(
		project.requiredTools
	) do

		if required then
			local source =
				nil

			local item =
				findPlayerTool(
					player,
					fullType
				)

			if item then

				source = {
					kind = "inventory",
					item = item,
					label = "Carried"
				}

			else

				local supplyItem =
					nil

				local supplyContainer =
					nil

				if ConstructionPlanner.getSupplyContainers then

					for _, container in ipairs(
						ConstructionPlanner.getSupplyContainers()
						or {}
					) do

						local items =
							container
							and container:getItems()
							or nil

						if items then
							for i = 0, items:size() - 1 do

								local candidate =
									items:get(i)

								if candidate
								and candidate:getFullType()
									== fullType then

									supplyItem =
										candidate

									supplyContainer =
										container

									break
								end
							end
						end

						if supplyItem then
							break
						end
					end
				end

				if supplyItem then

					source = {
						kind = "supply",
						item = supplyItem,
						container = supplyContainer,
						label = "Supply Container"
					}

				else

					local gatherItem,
						worldObject,
						square =
							findToolInGatherAreas(
								fullType
							)

					if gatherItem then

						source = {
							kind = "gather",
							item = gatherItem,
							worldObject = worldObject,
							square = square,
							label = "Gather Area"
						}
					end
				end
			end

			local available =
				source ~= nil

			if not available then
				status.allAvailable =
					false
			end

			local displayName =
				fullType

			local scriptItem =
				ScriptManager.instance
				and ScriptManager.instance:getItem(
					fullType
				)
				or nil

			if scriptItem
			and scriptItem.getDisplayName then
				displayName =
					scriptItem:getDisplayName()
			end

			table.insert(
				status.requirements,
				{
					fullType = fullType,
					label = displayName,
					available = available,
					source = source,
					sourceLabel =
						source
						and source.label
						or "Missing"
				}
			)
		end
	end

	table.sort(
		status.requirements,
		function(a, b)
			return tostring(a.label)
				< tostring(b.label)
		end
	)

	return status
end


------------------------------------------------------------
-- FIND TOOL IN EXISTING SUPPLY CONTAINERS
------------------------------------------------------------

local function findToolInSupplies(
	fullType
)
	if not ConstructionPlanner.getSupplyContainers then
		return nil, nil
	end

	local containers =
		ConstructionPlanner.getSupplyContainers()

	if not containers then
		return nil, nil
	end

	for _, container in ipairs(
		containers
	) do

		if container then

			local items =
				container:getItems()

			if items then

				for i = 0, items:size() - 1 do

					local item =
						items:get(i)

					if item
					and item:getFullType() == fullType then

						return item, container
					end
				end
			end
		end
	end

	return nil, nil
end

------------------------------------------------------------
-- BUILD LIST OF TOOLS WE ACTUALLY NEED TO BORROW
------------------------------------------------------------

local function buildToolPickupPlan()
	local project =
		ConstructionPlanner.pendingProject

	if not project then
		return nil, "project missing"
	end

	local requiredTools =
		project.requiredTools

	if not requiredTools then
		return {}
	end

	local player =
		getSpecificPlayer(0)

	if not player then
		return nil, "player missing"
	end

	local plan = {}

	for fullType, required in pairs(
		requiredTools
	) do

		if required
		and not playerHasTool(
			player,
			fullType
		) then

			------------------------------------------------
			-- SUPPLY CONTAINER FIRST
			------------------------------------------------

			local item,
				container =
					findToolInSupplies(
						fullType
					)

			if item
			and container then

				table.insert(
					plan,
					{
						kind = "supply",
						fullType = fullType,
						item = item,
						container = container
					}
				)

			else

				------------------------------------------------
				-- THEN GATHER AREA GROUND
				------------------------------------------------

				local gatherItem,
					worldObject,
					square =
						findToolInGatherAreas(
							fullType
						)

				if not gatherItem
				or not worldObject
				or not square then

					return nil,
						"missing required tool "
						.. tostring(fullType)
				end

				table.insert(
					plan,
					{
						kind = "gather",
						fullType = fullType,
						item = gatherItem,
						worldObject = worldObject,
						square = square
					}
				)
			end
		end
	end

	return plan
end


------------------------------------------------------------
-- QUEUE ONE TOOL PICKUP
------------------------------------------------------------

local function queueToolPickup(
	player,
	entry
)
	if not player
	or not entry
	or not entry.item then
		return false
	end

	--------------------------------------------------------
	-- SUPPLY CONTAINER TOOL
	--------------------------------------------------------

	if entry.kind == "supply" then

		if not entry.container then
			return false
		end

		local parent =
			entry.container:getParent()

		if not parent then
			cpDebug(
				"[ConstructionPlanner] Tool container has no parent"
			)
			return false
		end

		local square =
			parent:getSquare()

		if not square then
			cpDebug(
				"[ConstructionPlanner] Tool container has no world square"
			)
			return false
		end

		local adjacent =
			AdjacentFreeTileFinder.Find(
				square,
				player
			)

		if not adjacent then
			cpDebug(
				"[ConstructionPlanner] No accessible square beside tool container"
			)
			return false
		end

		local walkAction =
			ConstructionPlanner.queueWalkAction(
				player,
				adjacent
			)

		if not walkAction then
			cpDebug(
				"[ConstructionPlanner] Could not queue walk to tool container"
			)
			return false
		end

		local action =
			ISInventoryTransferUtil.newInventoryTransferAction(
				player,
				entry.item,
				entry.container,
				player:getInventory()
			)

		if not action then
			return false
		end

		ISTimedActionQueue.add(
			action
		)

		return true
	end

	--------------------------------------------------------
	-- GATHER AREA GROUND TOOL
	--------------------------------------------------------

	if entry.kind == "gather" then

		if not entry.worldObject
		or not entry.square then
			return false
		end

		local adjacent =
			AdjacentFreeTileFinder.Find(
				entry.square,
				player
			)

		if not adjacent then
			return false
		end

		local walkAction =
			ConstructionPlanner.queueWalkAction(
				player,
				adjacent
			)

		if not walkAction then
			return false
		end

		local action =
			ISGrabItemAction:new(
				player,
				entry.worldObject,
				10
			)

		if not action then
			return false
		end

		ISTimedActionQueue.add(
			action
		)

		return true
	end

	return false
end


------------------------------------------------------------
-- START TOOL ACQUISITION
------------------------------------------------------------

function ConstructionPlanner.startToolAcquisition()
	local player =
		getSpecificPlayer(0)

	if not player then
		return false
	end

	local plan, errorMessage =
		buildToolPickupPlan()

	if not plan then

		cpDebug(
			"[ConstructionPlanner] ================================="
		)

		cpDebug(
			"[ConstructionPlanner] Tool acquisition could not start"
		)

		cpDebug(
			"[ConstructionPlanner] "
			.. tostring(errorMessage)
		)

		cpDebug(
			"[ConstructionPlanner] ================================="
		)

		return false
	end

	--------------------------------------------------------
	-- NO TOOLS NEED PICKING UP
	--------------------------------------------------------

	if #plan == 0 then

		cpDebug(
			"[ConstructionPlanner] All required tools already carried"
		)

		return true
	end

	--------------------------------------------------------
	-- SAVE PLAN
	--------------------------------------------------------

	ConstructionPlanner.pendingToolPickupPlan =
		plan

	--------------------------------------------------------
	-- QUEUE TOOL PICKUPS
	--------------------------------------------------------

	ISTimedActionQueue.clear(
		player
	)

	for index, entry in ipairs(
		plan
	) do

		cpDebug(
			"[ConstructionPlanner] Retrieving tool "
			.. tostring(index)
			.. " / "
			.. tostring(#plan)
			.. ": "
			.. tostring(entry.fullType)
		)

		if not queueToolPickup(
			player,
			entry
		) then

			ConstructionPlanner.pendingToolPickupPlan =
				nil

			ISTimedActionQueue.clear(
				player
			)

			return false
		end
	end

	ConstructionPlanner.toolPickupPending =
		true

	cpDebug(
		"[ConstructionPlanner] Tool pickup route queued"
	)

	return false
end

------------------------------------------------------------
-- WAIT UNTIL TOOL PICKUP ROUTE FINISHES
------------------------------------------------------------

local function updateToolPickup()
	if not ConstructionPlanner.toolPickupPending then
		return
	end

	local player =
		getSpecificPlayer(0)

	if not player then
		return
	end

	local actionQueue =
		ISTimedActionQueue.getTimedActionQueue(
			player
		)

	if actionQueue
	and actionQueue.queue
	and actionQueue.queue[1] then

		return
	end

	--------------------------------------------------------
	-- PICKUPS FINISHED
	--------------------------------------------------------

	ConstructionPlanner.toolPickupPending =
		false

	local plan =
		ConstructionPlanner.pendingToolPickupPlan

	ConstructionPlanner.pendingToolPickupPlan =
		nil

	if not plan then
		return
	end

	local project =
		ConstructionPlanner.pendingProject

	if not project then
		return
	end

	project.borrowedTools =
		project.borrowedTools
		or {}

	--------------------------------------------------------
	-- VERIFY + REMEMBER BORROWED TOOLS
	--------------------------------------------------------

	for _, entry in ipairs(
		plan
	) do

		if not playerHasTool(
			player,
			entry.fullType
		) then

			cpDebug(
				"[ConstructionPlanner] Tool pickup failed: "
				.. tostring(entry.fullType)
			)

			return
		end

		if entry.kind == "supply"
		and entry.container then

			table.insert(
				project.borrowedTools,
				{
					item =
						entry.item,

					fullType =
						entry.fullType,

					sourceContainer =
						entry.container
				}
			)

			cpDebug(
				"[ConstructionPlanner] Borrowed "
				.. tostring(entry.fullType)
				.. " from Supply Container"
			)

		else

			cpDebug(
				"[ConstructionPlanner] Acquired "
				.. tostring(entry.fullType)
				.. " from Gather Area"
			)
		end
	end

	cpDebug(
		"[ConstructionPlanner] All required tools acquired"
	)

	--------------------------------------------------------
	-- CONTINUE INTO EXISTING BUILD PHASE
	--------------------------------------------------------

	if ConstructionPlanner.startPlannedProject then

		cpDebug(
			"[ConstructionPlanner] Starting construction phase"
		)

		cpDebug(
			"[ConstructionPlanner] ProjectBuilder handoff ready"
		)

		ConstructionPlanner.startPlannedProject()

	else

		cpDebug(
			"[ConstructionPlanner] Project builder unavailable"
		)
	end
end

------------------------------------------------------------
-- FINAL PROJECT CLEANUP
------------------------------------------------------------

function ConstructionPlanner.finalizeProject()

	cpDebug(
		"[ConstructionPlanner] ========================="
	)

	cpDebug(
		"[ConstructionPlanner] PROJECT COMPLETE"
	)

	cpDebug(
		"[ConstructionPlanner] ========================="
	)

	local completedProject =
		ConstructionPlanner.pendingProject

	local completedQuick =
		ConstructionPlanner.quickProjectActive == true
		or (
			completedProject
			and completedProject.cpQuickProject == true
		)

	if completedQuick then
		----------------------------------------------------
		-- QUICK COMPLETE: restore the Plan project exactly as
		-- it existed before Quick started.
		----------------------------------------------------

		ConstructionPlanner.pendingProject =
			ConstructionPlanner.savedPlanProjectDuringQuick

		ConstructionPlanner.savedPlanProjectDuringQuick =
			nil

		ConstructionPlanner.quickProjectActive =
			false

		ConstructionPlanner.pendingQuickDistribution =
			false

		ConstructionPlanner.pendingQuickDistributionWait =
			false

		cpDebug(
			"[ConstructionPlanner] QUICK PROJECT COMPLETE - "
			.. "Plan project restored"
		)
	else
		ConstructionPlanner.pendingProject =
			nil
	end

	if ConstructionPlanner.calculateProjectMaterials then
		ConstructionPlanner.calculateProjectMaterials()
	end
end

------------------------------------------------------------
-- QUEUE ONE TOOL RETURN
------------------------------------------------------------

local function queueToolReturn(
	player,
	entry
)
	if not player
	or not entry
	or not entry.item
	or not entry.sourceContainer then

		return false
	end

	--------------------------------------------------------
	-- MAKE SURE THE PLAYER STILL HAS THIS EXACT TOOL
	--------------------------------------------------------

	if entry.item:getContainer()
	~= player:getInventory() then

		cpDebug(
			"[ConstructionPlanner] Borrowed tool no longer carried: "
			.. tostring(entry.fullType)
		)

		return true
	end

	--------------------------------------------------------
	-- GET ORIGINAL SUPPLY CONTAINER WORLD SQUARE
	--------------------------------------------------------

	local parent =
		entry.sourceContainer:getParent()

	if not parent then

		cpDebug(
			"[ConstructionPlanner] Tool return container has no parent"
		)

		return false
	end

	local square =
		parent:getSquare()

	if not square then

		cpDebug(
			"[ConstructionPlanner] Tool return container has no world square"
		)

		return false
	end

	--------------------------------------------------------
	-- FIND A FREE ADJACENT TILE
	--------------------------------------------------------

	local adjacent =
		AdjacentFreeTileFinder.Find(
			square,
			player
		)

	if not adjacent then

		cpDebug(
			"[ConstructionPlanner] Could not find adjacent tile for tool return"
		)

		return false
	end

	--------------------------------------------------------
	-- WALK BACK USING SHARED CONSTRUCTION PLANNER WALK
	--------------------------------------------------------

	local walkAction =
		ConstructionPlanner.queueWalkAction(
			player,
			adjacent
		)

	if not walkAction then

		cpDebug(
			"[ConstructionPlanner] Could not walk to tool return container"
		)

		return false
	end

	--------------------------------------------------------
	-- RETURN EXACT BORROWED ITEM
	--------------------------------------------------------

	local action =
		ISInventoryTransferUtil.newInventoryTransferAction(
			player,
			entry.item,
			player:getInventory(),
			entry.sourceContainer
		)

	if not action then

		cpDebug(
			"[ConstructionPlanner] Could not create tool return action"
		)

		return false
	end

	ISTimedActionQueue.add(
		action
	)

	return true
end

------------------------------------------------------------
-- START TOOL RETURN
------------------------------------------------------------

function ConstructionPlanner.startToolReturn()
	local project =
		ConstructionPlanner.pendingProject

	if not project
	or not project.borrowedTools
	or #project.borrowedTools == 0 then

		return false
	end

	local player =
		getSpecificPlayer(0)

	if not player then
		return false
	end

	--------------------------------------------------------
	-- SAVE RETURN PLAN
	--------------------------------------------------------

	ConstructionPlanner.pendingToolReturnPlan =
		project.borrowedTools

	ConstructionPlanner.toolReturnPending =
		true

	--------------------------------------------------------
	-- QUEUE RETURNS
	--------------------------------------------------------

	for index, entry in ipairs(
		project.borrowedTools
	) do

		cpDebug(
			"[ConstructionPlanner] Returning tool "
			.. tostring(index)
			.. " / "
			.. tostring(
				#project.borrowedTools
			)
			.. ": "
			.. tostring(entry.fullType)
		)

		if not queueToolReturn(
			player,
			entry
		) then

			ConstructionPlanner.toolReturnPending =
				false

			ConstructionPlanner.pendingToolReturnPlan =
				nil

			return false
		end
	end

	cpDebug(
		"[ConstructionPlanner] Tool return route queued"
	)

	return true
end

------------------------------------------------------------
-- WAIT FOR TOOL RETURNS TO FINISH
------------------------------------------------------------

local function updateToolReturn()
	if not ConstructionPlanner.toolReturnPending then
		return
	end

	local player =
		getSpecificPlayer(0)

	if not player then
		return
	end

	local actionQueue =
		ISTimedActionQueue.getTimedActionQueue(
			player
		)

	if actionQueue
	and actionQueue.queue
	and actionQueue.queue[1] then

		return
	end

	--------------------------------------------------------
	-- RETURN ROUTE FINISHED
	--------------------------------------------------------

	ConstructionPlanner.toolReturnPending =
		false

	ConstructionPlanner.pendingToolReturnPlan =
		nil

	local project =
		ConstructionPlanner.pendingProject

	if project then

		project.borrowedTools =
			nil
	end

	cpDebug(
		"[ConstructionPlanner] All borrowed tools returned"
	)

	--------------------------------------------------------
	-- NOW FULLY FINISH PROJECT
	--------------------------------------------------------

	if ConstructionPlanner.finalizeProject then

		ConstructionPlanner.finalizeProject()
	end
end

Events.OnTick.Add(
	updateToolPickup
)

Events.OnTick.Add(
	updateToolReturn
)