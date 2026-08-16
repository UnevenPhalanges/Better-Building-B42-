require "TimedActions/ISGrabItemAction"
ConstructionPlanner = ConstructionPlanner or {}


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
-- DISTRIBUTION DROP ACTION
------------------------------------------------------------

ISConstructionPlannerDropMaterial =
	ISBaseTimedAction:derive(
		"ISConstructionPlannerDropMaterial"
	)

function ISConstructionPlannerDropMaterial:isValid()

	local valid =
		self.character ~= nil
		and self.item ~= nil
		and self.targetSquare ~= nil

	if not valid then

		cpDebug(
			"[ConstructionPlanner] Virtual drop INVALID"
		)
	end

	return valid
end


function ISConstructionPlannerDropMaterial:update()
end


function ISConstructionPlannerDropMaterial:start()

	cpDebug(
		"[ConstructionPlanner] Virtual drop starting: "
		.. tostring(
			self.fullType
		)
	)
end


function ISConstructionPlannerDropMaterial:stop()

	cpDebug(
		"[ConstructionPlanner] Virtual drop STOPPED: "
		.. tostring(
			self.fullType
		)
	)

	ISBaseTimedAction.stop(
		self
	)
end

function ISConstructionPlannerDropMaterial:perform()

			local player =
				self.character

			if not player
			or not self.item
			or not self.targetSquare then

				ISBaseTimedAction.perform(
					self
				)

				return
			end

			local inventory =
				player:getInventory()

			if not inventory then

				ISBaseTimedAction.perform(
					self
				)

				return
			end

			--------------------------------------------------------
			-- RESTORE THIS EXACT VIRTUAL ITEM TO REAL INVENTORY
			--
			-- The old working distribution system always moved
			-- materials through the player's inventory immediately
			-- before placing them on the ground.
			--------------------------------------------------------

			if not inventory:contains(
				self.item
			) then

				inventory:AddItem(
					self.item
				)
			end

			--------------------------------------------------------
			-- VERIFY ITEM REALLY ENTERED INVENTORY
			--------------------------------------------------------

			if not inventory:contains(
				self.item
			) then

				cpDebug(
					"[ConstructionPlanner] Failed to restore virtual item to inventory: "
					.. tostring(
						self.fullType
					)
				)

				ISBaseTimedAction.perform(
					self
				)

				return
			end

			--------------------------------------------------------
			-- USE THE OLD WORKING INVENTORY -> WORLD TRANSITION
			--------------------------------------------------------

			inventory:Remove(
				self.item
			)

			local droppedItem =
				self.targetSquare:AddWorldInventoryItem(
					self.item,
					0.5,
					0.5,
					0
				)

			--------------------------------------------------------
			-- DROP FAILED
			--
			-- PUT THE EXACT ITEM BACK INTO INVENTORY.
			-- DO NOT REMOVE IT FROM VIRTUAL HAUL.
			--------------------------------------------------------

			if not droppedItem then

				inventory:AddItem(
					self.item
				)

				cpDebug(
					"[ConstructionPlanner] Failed to stage "
					.. tostring(
						self.fullType
					)
				)

				ISBaseTimedAction.perform(
					self
				)

				return
			end

			--------------------------------------------------------
			-- RECORD MATERIAL AS STAGED
			--------------------------------------------------------

			local record =
				self.distributionRecord

			local fullType =
				self.fullType

			if record
			and fullType then

				record.stagedMaterials =
					record.stagedMaterials
					or {}

				record.stagedMaterials[
					fullType
				] =
					(
						record.stagedMaterials[
							fullType
						]
						or 0
					)
					+ 1

				cpDebug(
					"[ConstructionPlanner] Staged "
					.. tostring(fullType)
					.. " "
					.. tostring(
						record.stagedMaterials[
							fullType
						]
					)
					.. "/"
					.. tostring(
						record.requiredMaterials[
							fullType
						]
					)
				)
			end

			--------------------------------------------------------
			-- NOW REMOVE THIS EXACT ITEM FROM VIRTUAL HAUL
			--------------------------------------------------------

			local haul =
				ConstructionPlanner.virtualHaul

			if haul
			and haul.items then

				for index, haulItem in ipairs(
					haul.items
				) do

					if haulItem == self.item then

						table.remove(
							haul.items,
							index
						)

						break
					end
				end

				----------------------------------------------------
				-- REMOVE ITS DELIVERY DESTINATION
				----------------------------------------------------

				if haul.itemDestinations then

					haul.itemDestinations[
						self.item
					] =
						nil
				end

				----------------------------------------------------
				-- WHOLE VIRTUAL HAUL DELIVERED
				----------------------------------------------------

				if #haul.items == 0 then

					ConstructionPlanner.virtualHaul =
						nil

					ConstructionPlanner.virtualDeliveryActive =
						false

					ConstructionPlanner.virtualDeliveryActions =
						nil

					ConstructionPlanner.virtualDeliveryObserved =
						false

					ConstructionPlanner.virtualDeliveryEmptySinceMs =
						nil

					cpDebug(
						"[ConstructionPlanner] Virtual haul delivered"
					)
				end
			end

			ISBaseTimedAction.perform(
				self
			)
		end

function ISConstructionPlannerDropMaterial:new(
	character,
	item,
	targetSquare,
	record,
	fullType
)
	local o = {}

	setmetatable(
		o,
		self
	)

	self.__index =
		self

	o.character =
		character

	o.item =
		item

	o.targetSquare =
		targetSquare

	o.distributionRecord =
		record

	o.fullType =
		fullType

	o.stopOnWalk =
		false

	o.stopOnRun =
		true

	o.maxTime =
		10

	if character:isTimedActionInstant() then

		o.maxTime =
			1
	end

	return o
end

function ISConstructionPlannerDropMaterial:new(
	character,
	item,
	targetSquare,
	record,
	fullType
)
	local o = {}

	setmetatable(
		o,
		self
	)

	self.__index =
		self

	o.character =
		character

	o.item =
		item

	o.targetSquare =
		targetSquare

	o.distributionRecord =
		record

	o.fullType =
		fullType

	o.stopOnWalk =
		false

	o.stopOnRun =
		false

	o.maxTime =
		10

	if character:isTimedActionInstant() then
		o.maxTime =
			1
	end

	return o
end

------------------------------------------------------------
-- MULTI-LEVEL PHASE HELPERS
------------------------------------------------------------

local function getActivePhaseIndex()
    local project = ConstructionPlanner.pendingProject
    return project and (project.cpActivePhaseIndex or 1) or 1
end

local function recordIsInActivePhase(record)
    if not record then
        return false
    end

    local project =
        ConstructionPlanner.pendingProject

    --------------------------------------------------------
    -- Before execution is locked, preserve legacy behavior.
    -- Once a multi-level execution is locked, an untagged record is
    -- a real metadata error and MUST NOT leak into the active phase.
    --------------------------------------------------------

    if record.cpPhaseIndex == nil then
        if project
        and project.cpPhasePlanLocked then
            cpDebug(
                "[ConstructionPlanner] WARNING: locked project has untagged distribution record at "
                .. tostring(record.x) .. ","
                .. tostring(record.y) .. ","
                .. tostring(record.z)
            )
            return false
        end

        return true
    end

    return record.cpPhaseIndex == getActivePhaseIndex()
end

local function getRecordStageCoordinates(record)
    if not record then
        return nil, nil, nil
    end

    return record.cpStageX or record.x,
           record.cpStageY or record.y,
           record.cpStageZ or record.z
end

------------------------------------------------------------
-- FIND FIRST INCOMPLETE DISTRIBUTION RECORD
------------------------------------------------------------

local function findNextIncompleteDistribution()
	local project =
		ConstructionPlanner.pendingProject

	if not project
	or not project.segments then
		return nil
	end

	for segmentIndex, segment in ipairs(
		project.segments
	) do

		if segment.distribution then

			for tileIndex, record in ipairs(
				segment.distribution
			) do

				if not record.distributionComplete
				and recordIsInActivePhase(record) then

					return {
						segmentIndex = segmentIndex,
						tileIndex = tileIndex,
						segment = segment,
						record = record
					}
				end
			end
		end
	end

	return nil
end

------------------------------------------------------------
-- COUNT MATERIAL IN PLAYER INVENTORY
------------------------------------------------------------

local function countMaterialInInventory(
	player,
	fullType
)
	if not player
	or not fullType then
		return 0
	end

	local inventory =
		player:getInventory()

	if not inventory then
		return 0
	end

	local items =
		inventory:getItems()

	if not items then
		return 0
	end

	local total = 0

	for i = 0, items:size() - 1 do
		local item =
			items:get(i)

		if item
		and item:getFullType() == fullType then

			total =
				total + 1
		end
	end

	return total
end

------------------------------------------------------------
-- GET MATCHING ITEMS FROM ONE CONTAINER
------------------------------------------------------------

local function getMaterialItems(
	container,
	fullType
)
	local found = {}

	if not container
	or not fullType
	or not container.getItems then

		return found
	end

	local items =
		container:getItems()

	if not items then
		return found
	end

	for i = 0, items:size() - 1 do
		local item =
			items:get(i)

		if item
		and item:getFullType() == fullType then

			table.insert(
				found,
				item
			)
		end
	end

	return found
end

------------------------------------------------------------
-- GET SUPPLY CONTAINER WORLD SQUARE
------------------------------------------------------------

local function getSupplyContainerSquare(container)
	if not container then
		return nil
	end

	if not container.getParent then
		return nil
	end

	local parent =
		container:getParent()

	if not parent then
		return nil
	end

	if not parent.getSquare then
		return nil
	end

	return parent:getSquare()
end

------------------------------------------------------------
-- GET / CREATE ONE PICKUP STOP
------------------------------------------------------------

local function getPickupStop(
	stops,
	container
)
	for _, stop in ipairs(stops) do
		if stop.container == container then
			return stop
		end
	end

	local stop = {
		container = container,
		square =
			getSupplyContainerSquare(
				container
			),

		items = {},
		materials = {}
	}

	table.insert(
		stops,
		stop
	)

	return stop
end

------------------------------------------------------------
-- GET / CREATE ONE GATHER-AREA PICKUP STOP
------------------------------------------------------------

local function getGatherPickupStop(
	stops,
	square
)
	for _, stop in ipairs(
		stops
	) do

		if stop.kind == "gather"
		and stop.square == square then
			return stop
		end
	end

	local stop = {
		kind = "gather",
		square = square,
		items = {},
		worldObjects = {},
		materials = {}
	}

	table.insert(
		stops,
		stop
	)

	return stop
end

------------------------------------------------------------
-- BUILD COMPLETE PICKUP PLAN FOR NEXT TILE
------------------------------------------------------------

			local function getMaxMaterialsPerHaul()
				local value =
					3

				if SandboxVars
				and SandboxVars.ConstructionPlanner then

					local savedValue =
						SandboxVars.ConstructionPlanner.MaterialsPerHaul

					if savedValue ~= nil then

						value =
							tonumber(
								savedValue
							)
							or 3
					end
				end

				if value < 1 then
					value =
						1
				end

				if value > 10 then
					value =
						10
				end

				return value
			end

------------------------------------------------------------
-- REFRESH PHYSICAL STAGED MATERIALS
--
-- A MATERIAL COUNTS AS STAGED ONLY WHEN IT IS PHYSICALLY
-- ON THE EXACT PREVIEW / DISTRIBUTION TILE.
--
-- STAGED ITEMS ARE ALSO RESERVED HERE SO GATHER AREA
-- SOURCING CAN NEVER TAKE THEM.
------------------------------------------------------------

local function refreshPhysicalStagedMaterials(
	project
)
	local reservedStagedItems =
		{}

	if not project
	or not project.segments then

		return reservedStagedItems
	end

	for _, segment in ipairs(
		project.segments
	) do

		if segment.distribution then

			for _, record in ipairs(
				segment.distribution
			) do

				if record
				and record.requiredMaterials then

					------------------------------------------------
					-- EXACT PREVIEW TILE ONLY.
					--
					-- DO NOT SEARCH ADJACENT TILES.
					------------------------------------------------

					local stageX, stageY, stageZ =
						getRecordStageCoordinates(
							record
						)

					local square =
						getCell():getGridSquare(
							stageX,
							stageY,
							stageZ
						)

					local worldObjects =
						square
						and square:getWorldObjects()
						or nil

					record.stagedMaterials =
						{}

					local distributionComplete =
						true

					for fullType, required in pairs(
						record.requiredMaterials
					) do

						local staged =
							0

						if worldObjects then

							for i = 0,
								worldObjects:size() - 1 do

								if staged >= required then
									break
								end

								local worldObject =
									worldObjects:get(i)

								local item =
									worldObject
									and worldObject:getItem()
									or nil

									if item
									and item:getFullType()
										== fullType
									and not reservedStagedItems[
										item
									] then

									------------------------------------------------
									-- THIS EXACT ITEM NOW BELONGS TO THIS PREVIEW.
									--
									-- GATHER AREA MUST NEVER TAKE IT.
									------------------------------------------------

									reservedStagedItems[
										item
									] =
										true

									staged =
										staged + 1
								end
							end
						end

						record.stagedMaterials[
							fullType
						] =
							staged

						if staged < required then

							distributionComplete =
								false
						end
					end

					record.distributionComplete =
						distributionComplete
				end
			end
		end
	end

	return reservedStagedItems
end

			local function buildPickupPlan()
				local player =
					getSpecificPlayer(0)

				if not player then
					return nil, "no player"
				end

				local project =
					ConstructionPlanner.pendingProject

				if not project
				or not project.segments then

					return nil, "no project"
				end

	--------------------------------------------------------
	-- REFRESH STAGING FROM THE ACTUAL WORLD.
	--
	-- THIS ALSO RETURNS THE EXACT GROUND ITEMS THAT
	-- GATHER AREA IS FORBIDDEN TO COLLECT.
	--------------------------------------------------------

	local reservedStagedItems =
		refreshPhysicalStagedMaterials(
			project
		)

				local supplyContainers =
					{}

				if ConstructionPlanner.getSupplyContainers then

					supplyContainers =
						ConstructionPlanner.getSupplyContainers()
						or {}
				end

				local maxHaulItems =
					getMaxMaterialsPerHaul()

				local allocatedItems =
					0

				local plan = {
					stops =
						{},

					deliveries =
						{},

					itemDestinations =
						{},

					maxHaulItems =
						maxHaulItems
				}

				--------------------------------------------------------
				-- TRACK PLAYER MATERIALS SO THE SAME CARRIED ITEM
				-- IS NOT COUNTED FOR MULTIPLE PREVIEW TILES.
				--------------------------------------------------------

				local carriedRemaining =
					{}

				--------------------------------------------------------
				-- TRACK EXACT SUPPLY ITEMS ALREADY RESERVED FOR
				-- THIS HAUL SO THEY CANNOT BE ALLOCATED TWICE.
				--------------------------------------------------------

				local reservedItems =
					{}

				--------------------------------------------------------
				-- WALK PROJECT IN NORMAL SEGMENT / TILE ORDER
				--------------------------------------------------------

				for segmentIndex, segment in ipairs(
					project.segments
				) do

					if allocatedItems >= maxHaulItems then
						break
					end

					if segment.distribution then

						for tileIndex, record in ipairs(
							segment.distribution
						) do

							if allocatedItems >= maxHaulItems then
								break
							end

							if not record.distributionComplete
							and recordIsInActivePhase(record)
							and record.requiredMaterials then

								local delivery = {
									segmentIndex =
										segmentIndex,

									tileIndex =
										tileIndex,

									segment =
										segment,

									record =
										record,

									materials =
										{}
								}

								------------------------------------------------
								-- MATERIALS FOR THIS PREVIEW TILE
								------------------------------------------------

								for fullType, required in pairs(
									record.requiredMaterials
								) do

									if allocatedItems >= maxHaulItems then
										break
									end

									local staged =
										0

									if record.stagedMaterials then

										staged =
											record.stagedMaterials[
												fullType
											]
											or 0
									end

									local missing =
										required
										- staged

									if missing > 0 then

										------------------------------------------------
										-- GET PLAYER MATERIAL COUNT ONCE PER TYPE
										------------------------------------------------

										if carriedRemaining[
											fullType
										] == nil then

											carriedRemaining[
												fullType
											] =
												countMaterialInInventory(
													player,
													fullType
												)
										end

										local haulSpace =
											maxHaulItems
											- allocatedItems

										------------------------------------------------
										-- ALLOCATE CARRIED MATERIALS FIRST
										------------------------------------------------

										local carriedForTile =
											math.min(
												carriedRemaining[
													fullType
												],
												missing,
												haulSpace
											)

										carriedRemaining[
											fullType
										] =
											carriedRemaining[
												fullType
											]
											- carriedForTile

										allocatedItems =
											allocatedItems
											+ carriedForTile

										local remaining =
											missing
											- carriedForTile

										local materialPlan = {
											fullType =
												fullType,

											required =
												required,

											staged =
												staged,

											missing =
												missing,

											carried =
												carriedForTile,

											toPickup =
												0
										}

										table.insert(
											delivery.materials,
											materialPlan
										)

										------------------------------------------------
										-- ALLOCATE SUPPLY ITEMS INTO REMAINING
										-- HAUL SPACE
										------------------------------------------------

										if remaining > 0
										and allocatedItems < maxHaulItems then

											for _, container in ipairs(
												supplyContainers
											) do

												if remaining <= 0
												or allocatedItems >= maxHaulItems then

													break
												end

												local availableItems =
													getMaterialItems(
														container,
														fullType
													)

												if #availableItems > 0 then

													local stop =
														nil

													for _, candidate in ipairs(
														plan.stops
													) do

														if candidate.container
														== container then

															stop =
																candidate

															break
														end
													end

													for _, item in ipairs(
														availableItems
													) do

														if remaining <= 0
														or allocatedItems >= maxHaulItems then

															break
														end

														if item
														and not reservedItems[
															item
														] then

															if not stop then

																stop =
																	getPickupStop(
																		plan.stops,
																		container
																	)

																if not stop.square then

																	return nil,
																		"supply container has no world square"
																end
															end

															reservedItems[
																item
															] =
																true

															plan.itemDestinations[
																item
															] =
																record

															table.insert(
																stop.items,
																item
															)

															stop.materials[
																fullType
															] =
																(
																	stop.materials[
																		fullType
																	]
																	or 0
																)
																+ 1

															materialPlan.toPickup =
																materialPlan.toPickup
																+ 1

															allocatedItems =
																allocatedItems
																+ 1

															remaining =
																remaining
																- 1
														end
													end
												end
											end
										end

										------------------------------------------------
										-- GATHER AREAS
										--
										-- SOURCE PRIORITY:
										-- PLAYER INVENTORY
										-- -> SUPPLY CONTAINERS
										-- -> LOOSE ITEMS IN GATHER AREAS
										------------------------------------------------

										if remaining > 0
										and allocatedItems < maxHaulItems
										and ConstructionPlanner.getGroundItemsInGatherAreas then

											local gatherItems =
												ConstructionPlanner.getGroundItemsInGatherAreas(
													fullType
												)
												or {}

											for _, entry in ipairs(
												gatherItems
											) do

												if remaining <= 0
												or allocatedItems >= maxHaulItems then
													break
												end

												local item =
													entry.item

												local worldObject =
													entry.worldObject

												local square =
													entry.square

												if item
												and worldObject
												and square
												and not reservedItems[
													item
												]
												and not reservedStagedItems[
													item
												] then

													local stop =
														getGatherPickupStop(
															plan.stops,
															square
														)

													reservedItems[
														item
													] =
														true

													plan.itemDestinations[
														item
													] =
														record

													table.insert(
														stop.items,
														item
													)

													stop.worldObjects[
														item
													] =
														worldObject

													stop.materials[
														fullType
													] =
														(
															stop.materials[
																fullType
															]
															or 0
														)
														+ 1

													materialPlan.toPickup =
														materialPlan.toPickup
														+ 1

													allocatedItems =
														allocatedItems
														+ 1

													remaining =
														remaining
														- 1
												end
											end
										end

										------------------------------------------------
										-- IF HAUL STILL HAS SPACE AND WE COULD NOT
										-- SATISFY THIS MATERIAL, THIS IS A REAL
										-- MATERIAL SHORTAGE, NOT A HAUL-LIMIT STOP.
										------------------------------------------------

										if remaining > 0
										and allocatedItems < maxHaulItems then

											return nil,
												"not enough "
												.. tostring(fullType)
												.. " for tile "
												.. tostring(
													tileIndex
												)
										end
									end
								end

								------------------------------------------------
								-- ONLY SAVE TILE IF THIS HAUL ACTUALLY
								-- ALLOCATED SOMETHING TO IT.
								------------------------------------------------

								local deliveryCount =
									0

								for _, material in ipairs(
									delivery.materials
								) do

									deliveryCount =
										deliveryCount
										+ material.carried
										+ material.toPickup
								end

								if deliveryCount > 0 then

									table.insert(
										plan.deliveries,
										delivery
									)
								end
							end
						end
					end
				end

				if allocatedItems == 0 then

					return nil,
						"no materials available for distribution"
				end

				cpDebug(
					"[ConstructionPlanner] Materials Per Haul setting = "
					.. tostring(
						maxHaulItems
					)
				)

				cpDebug(
					"[ConstructionPlanner] Haul allocated "
					.. tostring(
						allocatedItems
					)
					.. " / "
					.. tostring(
						maxHaulItems
					)
					.. " object(s)"
				)

				cpDebug(
					"[ConstructionPlanner] Delivery stops: "
					.. tostring(
						#plan.deliveries
					)
				)

				return plan, nil
			end

------------------------------------------------------------
-- QUEUE WALK TO ONE SUPPLY CONTAINER
------------------------------------------------------------

local function queueWalkToContainer(
	player,
	stop
)
	if not player
	or not stop
	or not stop.square then

		return false
	end

	--------------------------------------------------------
	-- FIND A FREE ADJACENT TILE
	--------------------------------------------------------

	local adjacent =
		AdjacentFreeTileFinder.Find(
			stop.square,
			player
		)

	if not adjacent then

		cpDebug(
			"[ConstructionPlanner] No accessible square beside supply container"
		)

		return false
	end

	--------------------------------------------------------
	-- QUEUE SHARED CONSTRUCTION PLANNER WALK
	--------------------------------------------------------

	local walkAction =
		ConstructionPlanner.queueWalkAction(
			player,
			adjacent
		)

	if not walkAction then

		cpDebug(
			"[ConstructionPlanner] Could not queue walk to supply container"
		)

		return false
	end

	return true
end

local function queueWalkToGatherStop(
	player,
	stop
)
	if not player
	or not stop
	or not stop.square then

		return false
	end

	local adjacent =
		AdjacentFreeTileFinder.Find(
			stop.square,
			player
		)

	if not adjacent then

		adjacent =
			stop.square
	end

	local walkAction =
		ConstructionPlanner.queueWalkAction(
			player,
			adjacent
		)

	if not walkAction then

		cpDebug(
			"[ConstructionPlanner] Could not queue walk to Gather Area stop"
		)

		return false
	end

	return true
end

------------------------------------------------------------
-- QUEUE ITEMS FROM ONE SUPPLY STOP
------------------------------------------------------------

local function getHeavyLoadLevel(
	player
)
	if not player then
		return 0
	end

	local moodles =
		player:getMoodles()

	if not moodles then
		return 0
	end

	return moodles:getMoodleLevel(
		MoodleType.HEAVY_LOAD
	)
end


local function hasCarriedProjectMaterials(
	player,
	plan
)
	if not player
	or not plan
	or not plan.deliveries then

		return false
	end

	for _, delivery in ipairs(
		plan.deliveries
	) do

		if delivery.materials then

			for _, material in ipairs(
				delivery.materials
			) do

				local items =
					getCarriedMaterialItems(
						player,
						material.fullType,
						1
					)

				if items
				and #items > 0 then

					return true
				end
			end
		end
	end

	return false
end


local function queueSinglePickupItem(
	player,
	stop,
	item
)
	if not player
	or not stop
	or not stop.container
	or not item then

		return false
	end

	local inventory =
		player:getInventory()

	if not inventory then
		return false
	end

	ISTimedActionQueue.add(
		ISInventoryTransferAction:new(
			player,
			item,
			stop.container,
			inventory
		)
	)

	return true
end

local function startCurrentLoadDelivery(
	player,
	plan
)
	if not player
	or not plan then

		return false
	end

	ConstructionPlanner.distributionPickupState =
		nil

	cpDebug(
		"[ConstructionPlanner] Current hauling load complete - delivering"
	)

	if not queueTileDelivery(
		player,
		plan
	) then

		cpDebug(
			"[ConstructionPlanner] Could not start partial-load delivery"
		)

		return false
	end

	return true
end


local function updateDistributionPickup()
	local state =
		ConstructionPlanner.distributionPickupState

	if not state then
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

	--------------------------------------------------------
	-- WAIT FOR CURRENT WALK / TRANSFER ACTION
	--------------------------------------------------------

	if actionQueue
	and actionQueue.queue
	and actionQueue.queue[1] then

		return
	end

	local plan =
		state.plan

	if not plan then

		ConstructionPlanner.distributionPickupState =
			nil

		return
	end

	--------------------------------------------------------
	-- JUST FINISHED A TRANSFER
	--
	-- CHECK HEAVY LOAD BEFORE TAKING ANYTHING ELSE.
	--------------------------------------------------------

	if state.phase == "waitTransfer" then

		local level =
			getHeavyLoadLevel(
				player
			)

		cpDebug(
			"[ConstructionPlanner] HeavyLoad after pickup: "
			.. tostring(level)
		)

		state.itemIndex =
			state.itemIndex + 1

		if level >= 2 then

			cpDebug(
				"[ConstructionPlanner] HeavyLoad 2+ reached - delivering current load"
			)

			startCurrentLoadDelivery(
				player,
				plan
			)

			return
		end

		state.phase =
			"pickup"
	end

	--------------------------------------------------------
	-- FINISHED WALKING TO CURRENT SUPPLY CONTAINER
	--------------------------------------------------------

	if state.phase == "waitWalk" then

		state.phase =
			"pickup"
	end

	--------------------------------------------------------
	-- PROCESS NEXT PICKUP
	--------------------------------------------------------

	if state.phase == "pickup" then

		local stop =
			plan.stops[
				state.stopIndex
			]

		----------------------------------------------------
		-- NO MORE SUPPLY STOPS
		----------------------------------------------------

		if not stop then

			startCurrentLoadDelivery(
				player,
				plan
			)

			return
		end

		local item =
			stop.items[
				state.itemIndex
			]

		----------------------------------------------------
		-- FINISHED THIS CONTAINER
		----------------------------------------------------

		if not item then

			state.stopIndex =
				state.stopIndex + 1

			state.itemIndex =
				1

			state.phase =
				"startStop"

			return
		end

		----------------------------------------------------
		-- PICK UP ONE ITEM
		----------------------------------------------------

		cpDebug(
			"[ConstructionPlanner] Picking up "
			.. tostring(item:getFullType())
		)

		if not queueSinglePickupItem(
			player,
			stop,
			item
		) then

			cpDebug(
				"[ConstructionPlanner] Could not queue material pickup"
			)

			ConstructionPlanner.distributionPickupState =
				nil

			return
		end

		state.phase =
			"waitTransfer"

		return
	end

	--------------------------------------------------------
	-- START NEXT SUPPLY STOP
	--------------------------------------------------------

	if state.phase == "startStop" then

		local stop =
			plan.stops[
				state.stopIndex
			]

		----------------------------------------------------
		-- ALL STOPS COMPLETED
		----------------------------------------------------

		if not stop then

			startCurrentLoadDelivery(
				player,
				plan
			)

			return
		end

		----------------------------------------------------
		-- IF PLAYER IS ALREADY HEAVY BEFORE TAKING ANOTHER
		-- ITEM, DELIVER WHAT THEY CURRENTLY HAVE.
		----------------------------------------------------

		local level =
			getHeavyLoadLevel(
				player
			)

		if level >= 2 then

			if hasCarriedProjectMaterials(
				player,
				plan
			) then

				cpDebug(
					"[ConstructionPlanner] Already HeavyLoad 2+ - delivering carried project materials"
				)

				startCurrentLoadDelivery(
					player,
					plan
				)

			else

				cpDebug(
					"[ConstructionPlanner] ================================="
				)

				cpDebug(
					"[ConstructionPlanner] Distribution paused"
				)

				cpDebug(
					"[ConstructionPlanner] Player is HeavyLoad 2+ before hauling"
				)

				cpDebug(
					"[ConstructionPlanner] Reduce carried weight and press Build Project again"
				)

				cpDebug(
					"[ConstructionPlanner] ================================="
				)

				ConstructionPlanner.distributionPickupState =
					nil
			end

			return
		end

		cpDebug(
			"[ConstructionPlanner] Walking to supply stop "
			.. tostring(state.stopIndex)
			.. " / "
			.. tostring(#plan.stops)
		)

		if not queueWalkToContainer(
			player,
			stop
		) then

			cpDebug(
				"[ConstructionPlanner] Could not walk to supply stop"
			)

			ConstructionPlanner.distributionPickupState =
				nil

			return
		end

		state.phase =
			"waitWalk"

		return
	end
end

------------------------------------------------------------
-- DEBUG PICKUP PLAN
------------------------------------------------------------

local function printPickupPlan(plan)
	cpDebug(
		"[ConstructionPlanner] ================================="
	)

	cpDebug(
		"[ConstructionPlanner] DISTRIBUTION PICKUP PLAN"
	)

	cpDebug(
		"[ConstructionPlanner] Haul limit: "
		.. tostring(
			plan.maxHaulItems
		)
	)

	cpDebug(
		"[ConstructionPlanner] Delivery tiles: "
		.. tostring(
			#plan.deliveries
		)
	)

	cpDebug(
		"[ConstructionPlanner] ---------------------------------"
	)

	--------------------------------------------------------
	-- PRINT EACH TILE INCLUDED IN THIS HAUL
	--------------------------------------------------------

	for deliveryIndex, delivery in ipairs(
		plan.deliveries
	) do

		cpDebug(
			"[ConstructionPlanner] Delivery "
			.. tostring(deliveryIndex)
		)

		cpDebug(
			"[ConstructionPlanner]     Segment: "
			.. tostring(
				delivery.segmentIndex
			)
		)

		cpDebug(
			"[ConstructionPlanner]     Tile: "
			.. tostring(
				delivery.tileIndex
			)
		)

		cpDebug(
			"[ConstructionPlanner]     Location: "
			.. tostring(
				delivery.record.x
			)
			.. ", "
			.. tostring(
				delivery.record.y
			)
			.. ", "
			.. tostring(
				delivery.record.z
			)
		)

		for _, material in ipairs(
			delivery.materials
		) do

			cpDebug(
				"[ConstructionPlanner]         "
				.. tostring(
					material.fullType
				)
			)

			cpDebug(
				"[ConstructionPlanner]             staged="
				.. tostring(
					material.staged
				)
				.. "/"
				.. tostring(
					material.required
				)
			)

			cpDebug(
				"[ConstructionPlanner]             already carried="
				.. tostring(
					material.carried
				)
			)

			cpDebug(
				"[ConstructionPlanner]             pickup="
				.. tostring(
					material.toPickup
				)
			)
		end
	end

	cpDebug(
		"[ConstructionPlanner] ---------------------------------"
	)

	--------------------------------------------------------
	-- PRINT SUPPLY CONTAINER STOPS
	--------------------------------------------------------

	cpDebug(
		"[ConstructionPlanner] Supply stops: "
		.. tostring(
			#plan.stops
		)
	)

	for stopIndex, stop in ipairs(
		plan.stops
	) do

		local stopName =
			"unknown"

		if stop.kind == "gather" then

			stopName =
				"Gather Area ground @ "
				.. tostring(
					stop.square:getX()
				)
				.. ","
				.. tostring(
					stop.square:getY()
				)
				.. ","
				.. tostring(
					stop.square:getZ()
				)

		elseif stop.container then

			stopName =
				tostring(
					stop.container:getType()
				)
		end

		cpDebug(
			"[ConstructionPlanner] Stop "
			.. tostring(stopIndex)
			.. ": "
			.. stopName
		)

		for fullType, amount in pairs(
			stop.materials
		) do

			cpDebug(
				"[ConstructionPlanner]     "
				.. tostring(fullType)
				.. " x"
				.. tostring(amount)
			)
		end
	end

	cpDebug(
		"[ConstructionPlanner] ================================="
	)
end

------------------------------------------------------------
-- GET MATERIAL ITEMS CURRENTLY CARRIED
------------------------------------------------------------

local function getCarriedMaterialItems(
	player,
	fullType,
	maxCount
)
	local found = {}

	if not player
	or not fullType then
		return found
	end

	local inventory =
		player:getInventory()

	if not inventory then
		return found
	end

	local items =
		inventory:getItems()

	if not items then
		return found
	end

	for i = 0, items:size() - 1 do

		if #found >= maxCount then
			break
		end

		local item =
			items:get(i)

		if item
		and item:getFullType()
			== fullType then

			table.insert(
				found,
				item
			)
		end
	end

	return found
end

------------------------------------------------------------
-- CHECK WHETHER TILE IS FULLY STAGED
------------------------------------------------------------

local function updateDistributionComplete(
	record
)
	if not record
	or not record.requiredMaterials then
		return false
	end

	for fullType, required in pairs(
		record.requiredMaterials
	) do

		local staged =
			record.stagedMaterials
			and record.stagedMaterials[
				fullType
			]
			or 0

		if staged < required then
			record.distributionComplete =
				false

			return false
		end
	end

	record.distributionComplete =
		true

	cpDebug(
		"[ConstructionPlanner] Tile distribution complete at "
		.. tostring(record.x)
		.. ", "
		.. tostring(record.y)
		.. ", "
		.. tostring(record.z)
	)

	return true
end

------------------------------------------------------------
-- QUEUE DELIVERY TO PLANNED TILE
------------------------------------------------------------

local function spillVirtualHaul(
	player,
	reason
)
	if not player then
		return false
	end

	local haul =
		ConstructionPlanner.virtualHaul

	if not haul
	or not haul.items
	or #haul.items == 0 then

		return false
	end

	local square =
		player:getSquare()

	if not square then

		cpDebug(
			"[ConstructionPlanner] Could not spill virtual haul - player square missing"
		)

		return false
	end

	cpDebug(
		"[ConstructionPlanner] ================================="
	)

	cpDebug(
		"[ConstructionPlanner] HAUL INTERRUPTED"
	)

	cpDebug(
		"[ConstructionPlanner] "
		.. tostring(
			reason
			or "delivery interrupted"
		)
	)

	cpDebug(
		"[ConstructionPlanner] Dropping "
		.. tostring(
			#haul.items
		)
		.. " carried item(s) at player"
	)

	for _, item in ipairs(
		haul.items
	) do

		if item then

			local dropped =
				square:AddWorldInventoryItem(
					item,
					0.5,
					0.5,
					0
				)

			if dropped then

				cpDebug(
					"[ConstructionPlanner] Spilled "
					.. tostring(
						item:getFullType()
					)
				)
			else

				cpDebug(
					"[ConstructionPlanner] WARNING: could not spill "
					.. tostring(
						item:getFullType()
					)
				)
			end
		end
	end

	ConstructionPlanner.virtualHaul =
		nil

	ConstructionPlanner.virtualDeliveryActive =
		false

	ConstructionPlanner.virtualDeliveryActions =
		nil

	ConstructionPlanner.virtualDeliveryObserved =
		false

	ConstructionPlanner.virtualDeliveryEmptySinceMs =
		nil

	ConstructionPlanner.pendingDeliveryPlan =
		nil

	ConstructionPlanner.pendingNextDistribution =
		false

	ConstructionPlanner.distributionPausedBySpill =
		true

	cpDebug(
		"[ConstructionPlanner] Distribution paused after interrupted haul"
	)

	cpDebug(
		"[ConstructionPlanner] ================================="
	)

	return true
end

local function queueTileDelivery(
	player,
	plan
)
	if not player
	or not plan
	or not plan.deliveries then

		return false
	end

	local haul =
		ConstructionPlanner.virtualHaul

	if not haul
	or not haul.items
	or #haul.items == 0 then

		cpDebug(
			"[ConstructionPlanner] Delivery failed: virtual haul empty"
		)

		return false
	end

	ConstructionPlanner.virtualDeliveryActive =
		true

	ConstructionPlanner.virtualDeliveryActions =
		{}

	ConstructionPlanner.virtualDeliveryObserved =
		false

	ConstructionPlanner.virtualDeliveryEmptySinceMs =
		nil

	--------------------------------------------------------
	-- QUEUE EACH PREVIEW TILE SERVED BY THIS HAUL
	--------------------------------------------------------

	for _, delivery in ipairs(
		plan.deliveries
	) do

		local record =
			delivery.record

		local stageX, stageY, stageZ =
			getRecordStageCoordinates(
				record
			)

		local targetSquare =
			getCell():getGridSquare(
				stageX,
				stageY,
				stageZ
			)

		if not targetSquare then

			cpDebug(
				"[ConstructionPlanner] Delivery failed: target square missing"
			)

			return false
		end

		----------------------------------------------------
		-- FIND OUT WHETHER THIS HAUL ACTUALLY CONTAINS
		-- ITEMS ASSIGNED TO THIS TILE.
		----------------------------------------------------

		local deliveryItems =
			{}

		for _, item in ipairs(
			haul.items
		) do

			if item
			and haul.itemDestinations
			and haul.itemDestinations[
				item
			] == record then

				table.insert(
					deliveryItems,
					item
				)
			end
		end

		if #deliveryItems > 0 then

			------------------------------------------------
			-- NORMAL DELIVERY:
			-- Prefer a free square adjacent to the staging tile.
			------------------------------------------------

			local adjacent =
				AdjacentFreeTileFinder.Find(
					targetSquare,
					player
				)

			------------------------------------------------
			-- MULTI-LEVEL / TIGHT-SPACE FALLBACK:
			--
			-- A FLOOR_BOOTSTRAP record stages its materials on
			-- the REAL lower-level square at the same X/Y.
			-- In some layouts AdjacentFreeTileFinder returns nil
			-- even though that lower square itself is perfectly
			-- walkable.
			--
			-- Only fall back to the staging square itself when it
			-- has an actual floor.  This prevents CP from walking
			-- onto / staging on a nonexistent future upper level.
			------------------------------------------------

			if not adjacent then

				local hasRealFloor =
					targetSquare.getFloor
					and targetSquare:getFloor() ~= nil

				cpDebug(
					"[ConstructionPlanner] No adjacent delivery square at "
					.. tostring(stageX)
					.. ","
					.. tostring(stageY)
					.. ","
					.. tostring(stageZ)
					.. " floor="
					.. tostring(hasRealFloor)
					.. " phase="
					.. tostring(record.cpPhaseKind)
				)

				if hasRealFloor then

					adjacent =
						targetSquare

					cpDebug(
						"[ConstructionPlanner] Delivery fallback: walking onto staging square"
					)

				else

					cpDebug(
						"[ConstructionPlanner] Delivery failed: no reachable staging square"
					)

					return false
				end
			end

			cpDebug(
				"[ConstructionPlanner] Queueing delivery to tile "
				.. tostring(
					delivery.tileIndex
				)
				.. " with "
				.. tostring(
					#deliveryItems
				)
				.. " item(s)"
			)

			------------------------------------------------
			-- USE SHARED SPEED-3-COMPATIBLE CP WALK
			------------------------------------------------

			local walkAction =
				ConstructionPlanner.queueWalkAction(
					player,
					adjacent
				)

			if not walkAction then

				cpDebug(
					"[ConstructionPlanner] Delivery failed: could not queue CP walk"
				)

				return false
			end

			table.insert(
				ConstructionPlanner.virtualDeliveryActions,
				walkAction
			)

			------------------------------------------------
			-- DROP EACH ITEM ASSIGNED TO THIS TILE
			------------------------------------------------

			for _, item in ipairs(
				deliveryItems
			) do

				local dropAction =
					ISConstructionPlannerDropMaterial:new(
						player,
						item,
						targetSquare,
						record,
						item:getFullType()
					)

				table.insert(
					ConstructionPlanner.virtualDeliveryActions,
					dropAction
				)

				ISTimedActionQueue.add(
					dropAction
				)
			end

			------------------------------------------------
			-- CHECK THIS TILE AFTER ITS PORTION OF THE
			-- CURRENT HAUL HAS BEEN DROPPED.
			------------------------------------------------

			ISTimedActionQueue.add(
				ISConstructionPlannerFinishDelivery:new(
					player,
					record
				)
			)
		end
	end

	return true
end

local function updateVirtualHaulInterruption()
	if not ConstructionPlanner.virtualDeliveryActive then
		return
	end

	local haul =
		ConstructionPlanner.virtualHaul

	--------------------------------------------------------
	-- NOTHING LEFT TO DELIVER
	--------------------------------------------------------

	if not haul
	or not haul.items
	or #haul.items == 0 then

		ConstructionPlanner.virtualDeliveryActive =
			false

		ConstructionPlanner.virtualDeliveryActions =
			nil

		ConstructionPlanner.virtualDeliveryObserved =
			false

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

	local queueHasAction =
		false

	if actionQueue
	and actionQueue.queue
	and actionQueue.queue[1] then

		queueHasAction =
			true
	end

	--------------------------------------------------------
	-- DELIVERY QUEUE HAS ACTUALLY STARTED
	--------------------------------------------------------

	if queueHasAction then

		ConstructionPlanner.virtualDeliveryObserved =
			true

		ConstructionPlanner.virtualDeliveryEmptySinceMs =
			nil

		return
	end

	--------------------------------------------------------
	-- DELIVERY WAS JUST CREATED
	--
	-- DON'T CALL AN EMPTY QUEUE AN INTERRUPTION UNTIL
	-- WE HAVE FIRST SEEN THE DELIVERY QUEUE RUNNING.
	--------------------------------------------------------

	if not ConstructionPlanner.virtualDeliveryObserved then
		return
	end

	--------------------------------------------------------
	-- IMPORTANT:
	--
	-- AT HIGH GAME SPEED THE VANILLA TIMED-ACTION QUEUE CAN
	-- APPEAR EMPTY BRIEFLY BETWEEN ACTION TRANSITIONS.
	--
	-- ONLY TREAT THIS AS A REAL INTERRUPTION IF THE QUEUE
	-- STAYS CONTINUOUSLY EMPTY FOR 500 REAL MILLISECONDS.
	--
	-- getTimestampMs() IS REAL-TIME BASED, SO THIS DOES NOT
	-- SHRINK WHEN THE PLAYER INCREASES GAME SPEED.
	--------------------------------------------------------

	local now =
		getTimestampMs()

	if not ConstructionPlanner.virtualDeliveryEmptySinceMs then

		ConstructionPlanner.virtualDeliveryEmptySinceMs =
			now

		return
	end

	if now
	- ConstructionPlanner.virtualDeliveryEmptySinceMs
	< 500 then

		return
	end

	ConstructionPlanner.virtualDeliveryEmptySinceMs =
		nil

	spillVirtualHaul(
		player,
		"delivery action queue was interrupted"
	)
end

------------------------------------------------------------
-- WAIT FOR PICKUPS TO FINISH, THEN START DELIVERY
------------------------------------------------------------

			local function absorbCarriedMaterialsIntoVirtualHaul(
				player,
				plan
			)
				if not player
				or not plan
				or not plan.deliveries then

					return
				end

				local inventory =
					player:getInventory()

				if not inventory then
					return
				end

				if not ConstructionPlanner.virtualHaul then

					ConstructionPlanner.virtualHaul = {
						items =
							{},

						itemDestinations =
							{}
					}
				end

				local haul =
					ConstructionPlanner.virtualHaul

				--------------------------------------------------------
				-- EACH DELIVERY ALREADY KNOWS EXACTLY HOW MANY
				-- PLAYER-CARRIED ITEMS WERE RESERVED FOR THAT TILE.
				--------------------------------------------------------

				for _, delivery in ipairs(
					plan.deliveries
				) do

					for _, material in ipairs(
						delivery.materials
					) do

						local carriedNeeded =
							material.carried
							or 0

						if carriedNeeded > 0 then

							local carriedItems =
								getCarriedMaterialItems(
									player,
									material.fullType,
									carriedNeeded
								)

							local added =
								0

							for _, item in ipairs(
								carriedItems
							) do

								if added >= carriedNeeded then
									break
								end

								if item
								and inventory:contains(
									item
								) then

									inventory:Remove(
										item
									)

									table.insert(
										haul.items,
										item
									)

									haul.itemDestinations[
										item
									] =
										delivery.record

									added =
										added + 1

									cpDebug(
										"[ConstructionPlanner] Added carried material to virtual haul: "
										.. tostring(
											item:getFullType()
										)
									)
								end
							end
						end
					end
				end
			end

			------------------------------------------------------------
			-- FINISH PICKUP ROUTE EXPLICITLY
			--
			-- DO NOT INFER PICKUP COMPLETION FROM AN EMPTY ACTION
			-- QUEUE.  AT HIGH GAME SPEED THE QUEUE CAN LOOK EMPTY
			-- BETWEEN VANILLA ACTION TRANSITIONS.
			--
			-- THIS FUNCTION IS CALLED ONLY BY A SENTINEL TIMED ACTION
			-- QUEUED AFTER EVERY PICKUP ACTION.
			------------------------------------------------------------

			local function finishPickupRoute(
				player,
				plan
			)
				if not player
				or not plan then

					return false
				end

				ConstructionPlanner.pendingDeliveryPlan =
					nil

				cpDebug(
					"[ConstructionPlanner] Pickup route sentinel reached - starting haul delivery"
				)

				--------------------------------------------------------
				-- ADD ANY MATERIALS THAT THIS HAUL RESERVED FROM
				-- THE PLAYER'S INVENTORY.
				--------------------------------------------------------

				absorbCarriedMaterialsIntoVirtualHaul(
					player,
					plan
				)

				local haul =
					ConstructionPlanner.virtualHaul

				if not haul
				or not haul.items
				or #haul.items == 0 then

					cpDebug(
						"[ConstructionPlanner] Virtual haul missing at pickup-route sentinel"
					)

					return false
				end

				cpDebug(
					"[ConstructionPlanner] Virtual haul ready with "
					.. tostring(
						#haul.items
					)
					.. " item(s)"
				)

				--------------------------------------------------------
				-- QUEUE ALL TILE DELIVERIES BELONGING TO THIS HAUL
				--------------------------------------------------------

				if not queueTileDelivery(
					player,
					plan
				) then

					cpDebug(
						"[ConstructionPlanner] Could not start haul delivery"
					)

					return false
				end

				cpDebug(
					"[ConstructionPlanner] Multi-tile haul delivery started"
				)

				return true
			end

			------------------------------------------------------------
			-- PICKUP ROUTE SENTINEL
			------------------------------------------------------------

			ISConstructionPlannerFinishPickupRoute =
				ISBaseTimedAction:derive(
					"ISConstructionPlannerFinishPickupRoute"
				)

			function ISConstructionPlannerFinishPickupRoute:isValid()
				return self.character ~= nil
					and self.plan ~= nil
			end

			function ISConstructionPlannerFinishPickupRoute:update()
			end

			function ISConstructionPlannerFinishPickupRoute:start()
			end

			function ISConstructionPlannerFinishPickupRoute:stop()

				ISBaseTimedAction.stop(
					self
				)
			end

			function ISConstructionPlannerFinishPickupRoute:perform()

				if self:isValid() then

					finishPickupRoute(
						self.character,
						self.plan
					)
				end

				ISBaseTimedAction.perform(
					self
				)
			end

			function ISConstructionPlannerFinishPickupRoute:new(
				character,
				plan
			)
				local o =
					{}

				setmetatable(
					o,
					self
				)

				self.__index =
					self

				o.character =
					character

				o.plan =
					plan

				o.stopOnWalk =
					false

				o.stopOnRun =
					false

				o.maxTime =
					1

				return o
			end

------------------------------------------------------------
-- START NEXT TILE AFTER PREVIOUS DELIVERY FULLY FINISHES
------------------------------------------------------------

local function updateDistributionContinuation()

	if not ConstructionPlanner.pendingNextDistribution then
		return
	end

	local player =
		getSpecificPlayer(0)

	if not player then
		return
	end

	--------------------------------------------------------
	-- WAIT UNTIL TIMED-ACTION QUEUE IS COMPLETELY IDLE
	--------------------------------------------------------

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
	-- QUEUE IS EMPTY -- START NEXT DISTRIBUTION TILE
	--------------------------------------------------------

	ConstructionPlanner.pendingNextDistribution =
		false

	cpDebug(
		"[ConstructionPlanner] Starting next distribution tile"
	)

	if ConstructionPlanner.startDistributionPickup then

		ConstructionPlanner.startDistributionPickup()

	else

		cpDebug(
			"[ConstructionPlanner] Could not continue distribution"
		)
	end
end

------------------------------------------------------------
-- DELIVERY FINISH ACTION
------------------------------------------------------------

ISConstructionPlannerFinishDelivery =
	ISBaseTimedAction:derive(
		"ISConstructionPlannerFinishDelivery"
	)

function ISConstructionPlannerFinishDelivery:isValid()
	return true
end

function ISConstructionPlannerFinishDelivery:update()
end

function ISConstructionPlannerFinishDelivery:start()
end

function ISConstructionPlannerFinishDelivery:stop()
	ISBaseTimedAction.stop(
		self
	)
end

function ISConstructionPlannerFinishDelivery:perform()

	local complete =
		updateDistributionComplete(
			self.record
		)

	--------------------------------------------------------
	-- FINISH THIS TIMED ACTION
	--------------------------------------------------------

	ISBaseTimedAction.perform(
		self
	)

	--------------------------------------------------------
	-- TILE DID NOT FULLY STAGE
	--------------------------------------------------------

	if not complete then

		cpDebug(
			"[ConstructionPlanner] Tile still missing staged materials"
		)

		cpDebug(
			"[ConstructionPlanner] Another hauling trip is required"
		)

		ConstructionPlanner.pendingNextDistribution =
			true

		return
	end

	--------------------------------------------------------
	-- CHECK FOR ANOTHER INCOMPLETE TILE
	--------------------------------------------------------

	local nextPlacement =
		findNextIncompleteDistribution()

	if not nextPlacement then

		--------------------------------------------------------
		-- DISTRIBUTION IS COMPLETELY FINISHED.
		--
		-- EARLIER DELIVERY-FINISH ACTIONS MAY HAVE REQUESTED
		-- ANOTHER DISTRIBUTION ROUTE.  CANCEL THAT REQUEST
		-- BEFORE HANDING CONTROL TO CONSTRUCTION.
		--------------------------------------------------------

		ConstructionPlanner.pendingNextDistribution =
			false

		cpDebug(
			"[ConstructionPlanner] ================================="
		)

		local activePhase =
			ConstructionPlanner.getActiveProjectPhase
			and ConstructionPlanner.getActiveProjectPhase()
			or nil

		cpDebug(
			"[ConstructionPlanner] ACTIVE PHASE MATERIALS STAGED"
			.. (
				activePhase
				and (
					" - "
					.. tostring(activePhase.kind)
					.. " Z"
					.. tostring(activePhase.targetZ)
				)
				or ""
			)
		)

		cpDebug(
			"[ConstructionPlanner] ================================="
		)

		--------------------------------------------------------
		-- HAND OFF TO PROJECT BUILDER ON AN IDLE TICK
		--
		-- We are still inside the final delivery timed action
		-- here.  Starting tools/build inline can race the queue
		-- teardown and strand the next phase.
		--------------------------------------------------------

		ConstructionPlanner.pendingPhaseBuildStart =
			true

		cpDebug(
			"[ConstructionPlanner] Active phase build pending idle queue"
		)

		return
	end
	
	--------------------------------------------------------
	-- DON'T START THE NEXT ROUTE INSIDE THIS ACTION.
	-- LET ONTICK START IT AFTER THE QUEUE IS ACTUALLY IDLE.
	--------------------------------------------------------

	ConstructionPlanner.pendingNextDistribution =
		true

	cpDebug(
		"[ConstructionPlanner] Tile complete - next distribution pending"
	)
end

function ISConstructionPlannerFinishDelivery:new(
	character,
	record
)
	local o = {}

	setmetatable(
		o,
		self
	)

	self.__index =
		self

	o.character =
		character

	o.record =
		record

	o.maxTime =
		1

	return o
end

------------------------------------------------------------
-- START COMPLETE PICKUP ROUTE FOR NEXT TILE
------------------------------------------------------------

			local function virtualizeTransferredItem(
				player,
				item,
				plan
			)
				if not player
				or not item
				or not plan then

					return
				end

				local inventory =
					player:getInventory()

				if not inventory then
					return
				end

				if not inventory:contains(
					item
				) then

					return
				end

				if not ConstructionPlanner.virtualHaul then

					ConstructionPlanner.virtualHaul = {
						items =
							{},

						itemDestinations =
							{}
					}
				end

				local haul =
					ConstructionPlanner.virtualHaul

				inventory:Remove(
					item
				)

				table.insert(
					haul.items,
					item
				)

				haul.itemDestinations[
					item
				] =
					plan.itemDestinations[
						item
					]

				cpDebug(
					"[ConstructionPlanner] Virtualized immediately: "
					.. tostring(
						item:getFullType()
					)
				)
			end

------------------------------------------------------------
-- GATHER PICKUP -> EXISTING VIRTUAL HAUL BRIDGE
------------------------------------------------------------

ISConstructionPlannerVirtualizeGather =
	ISBaseTimedAction:derive(
		"ISConstructionPlannerVirtualizeGather"
	)

function ISConstructionPlannerVirtualizeGather:isValid()
	if not self.character
	or not self.item
	or not self.plan then
		return false
	end

	local inventory =
		self.character:getInventory()

	return inventory
		and inventory:contains(
			self.item
		)
end

function ISConstructionPlannerVirtualizeGather:update()
end

function ISConstructionPlannerVirtualizeGather:start()
end

function ISConstructionPlannerVirtualizeGather:stop()
	ISBaseTimedAction.stop(
		self
	)
end

function ISConstructionPlannerVirtualizeGather:perform()
	if self:isValid() then
		virtualizeTransferredItem(
			self.character,
			self.item,
			self.plan
		)
	else
		cpDebug(
			"[ConstructionPlanner] Gather item was not in inventory when virtualization ran: "
			.. tostring(
				self.item
				and self.item:getFullType()
				or "nil"
			)
		)
	end

	ISBaseTimedAction.perform(
		self
	)
end

function ISConstructionPlannerVirtualizeGather:new(
	character,
	item,
	plan
)
	local o = {}

	setmetatable(
		o,
		self
	)

	self.__index =
		self

	o.character =
		character

	o.item =
		item

	o.plan =
		plan

	o.stopOnWalk =
		false

	o.stopOnRun =
		false

	o.maxTime =
		1

	return o
end


local function queuePickupFromStop(
	player,
	stop,
	plan
)
	if not player
	or not stop
	or not plan then
		return false
	end

	local inventory =
		player:getInventory()

	if not inventory then
		return false
	end

	--------------------------------------------------------
	-- GATHER AREA GROUND STOP
	--
	-- IMPORTANT:
	-- USE VANILLA B42 GROUND-PICKUP ACTION.
	-- WHEN THE ITEM REACHES PLAYER INVENTORY, THE SAME
	-- virtualizeTransferredItem() CALLBACK USED BY SUPPLY
	-- CONTAINERS IMMEDIATELY MOVES IT INTO virtualHaul.
	--------------------------------------------------------

	if stop.kind == "gather" then

		if not queueWalkToGatherStop(
			player,
			stop
		) then

			return false
		end

		for _, item in ipairs(
			stop.items
		) do

			if item then

				local worldObject =
					stop.worldObjects
					and stop.worldObjects[
						item
					]
					or nil

				if not worldObject then

					cpDebug(
						"[ConstructionPlanner] Gather stop lost world object for "
						.. tostring(
							item:getFullType()
						)
					)

					return false
				end

				local action =
					ISGrabItemAction:new(
						player,
						worldObject,
						10
					)

				if not action then
					cpDebug(
						"[ConstructionPlanner] Could not create vanilla Gather Area grab action for "
						.. tostring(
							item:getFullType()
						)
					)

					return false
				end

				ISTimedActionQueue.add(
					action
				)

				ISTimedActionQueue.add(
					ISConstructionPlannerVirtualizeGather:new(
						player,
						item,
						plan
					)
				)
			end
		end

		return true
	end

	--------------------------------------------------------
	-- NORMAL SUPPLY CONTAINER STOP
	--------------------------------------------------------

	if not stop.container then
		return false
	end

	if not queueWalkToContainer(
		player,
		stop
	) then

		return false
	end

	for _, item in ipairs(
		stop.items
	) do

		if item then

			local action =
				ISInventoryTransferAction:new(
					player,
					item,
					stop.container,
					inventory
				)

			action:setOnComplete(
				virtualizeTransferredItem,
				player,
				item,
				plan
			)

			ISTimedActionQueue.add(
				action
			)
		end
	end

	return true
end

local function startDistributionPickup()
	local player =
		getSpecificPlayer(0)

	if not player then
		return
	end

	--------------------------------------------------------
	-- FINALIZE + LOCK MULTI-LEVEL PHASES ON FIRST EXECUTION
	--
	-- Planning recalculations are allowed to rebuild the phase plan.
	-- The first Build Project execution rebuilds once using the COMPLETE
	-- project, then freezes phase numbering for all later handoffs.
	--------------------------------------------------------

	local project =
		ConstructionPlanner.pendingProject

	if project
	and not project.cpPhasePlanLocked then

		if ConstructionPlanner.buildLevelPhasePlan then
			ConstructionPlanner.buildLevelPhasePlan()
		end

		project.cpPhasePlanLocked =
			true

		project.cpActivePhaseIndex =
			1

		cpDebug(
			"[ConstructionPlanner] Multi-level phase plan locked for execution"
		)
	end

	--------------------------------------------------------
	-- ALREADY CARRYING A VIRTUAL LOAD
	--
	-- DO NOT START ANOTHER PICKUP WHILE THE CURRENT
	-- MULTI-TILE HAUL IS STILL ACTIVE.
	--------------------------------------------------------

	local haul =
		ConstructionPlanner.virtualHaul

	if haul
	and haul.items
	and #haul.items > 0 then

		cpDebug(
			"[ConstructionPlanner] Virtual haul already active"
		)

		return
	end

	--------------------------------------------------------
	-- BUILD NEXT MULTI-TILE HAUL PLAN
	--------------------------------------------------------

	local plan, errorMessage =
		buildPickupPlan()

	if not plan then

		--------------------------------------------------------
		-- NOTHING IS MISSING
		--
		-- THIS IS NOT AN ERROR.
		--
		-- IT MEANS EVERY MATERIAL REQUIRED BY THE REMAINING
		-- PROJECT IS ALREADY STAGED, SO SKIP DISTRIBUTION AND
		-- CONTINUE DIRECTLY TO TOOLS / CONSTRUCTION.
		--------------------------------------------------------

		if errorMessage
		== "no materials available for distribution" then

			cpDebug(
				"[ConstructionPlanner] All remaining project materials already staged"
			)

			----------------------------------------------------
			-- MATERIALS ARE ALREADY STAGED.  DEFER THE BUILD
			-- HANDOFF TO THE SAME IDLE-TICK CONTROLLER USED
			-- AFTER A NORMAL DELIVERY ROUTE.
			----------------------------------------------------

			ConstructionPlanner.pendingPhaseBuildStart =
				true

			cpDebug(
				"[ConstructionPlanner] Active phase build pending idle queue"
			)

			return
		end

		--------------------------------------------------------
		-- REAL DISTRIBUTION FAILURE
		--------------------------------------------------------

		cpDebug(
			"[ConstructionPlanner] ================================="
		)

		cpDebug(
			"[ConstructionPlanner] Distribution pickup could not start"
		)

		cpDebug(
			"[ConstructionPlanner] "
			.. tostring(
				errorMessage
			)
		)

		cpDebug(
			"[ConstructionPlanner] ================================="
		)

		return
	end

	printPickupPlan(
		plan
	)

	--------------------------------------------------------
	-- NO EXTERNAL PICKUP STOPS
	--
	-- THIS ENTIRE HAUL CAN BE FILLED FROM MATERIALS
	-- ALREADY IN THE PLAYER'S INVENTORY.
	--------------------------------------------------------

	if #plan.stops == 0 then

		cpDebug(
			"[ConstructionPlanner] No external material pickup required"
		)

		absorbCarriedMaterialsIntoVirtualHaul(
			player,
			plan
		)

		local carriedHaul =
			ConstructionPlanner.virtualHaul

		if not carriedHaul
		or not carriedHaul.items
		or #carriedHaul.items == 0 then

			cpDebug(
				"[ConstructionPlanner] Could not create virtual haul from carried materials"
			)

			return
		end

		cpDebug(
			"[ConstructionPlanner] Virtual haul ready with "
			.. tostring(
				#carriedHaul.items
			)
			.. " carried item(s)"
		)

		ISTimedActionQueue.clear(
			player
		)

		if not queueTileDelivery(
			player,
			plan
		) then

			cpDebug(
				"[ConstructionPlanner] Could not start carried-material delivery"
			)

			return
		end

		cpDebug(
			"[ConstructionPlanner] Carried-material haul delivery started"
		)

		return
	end

	--------------------------------------------------------
	-- CLEAR EXISTING ACTIONS
	--------------------------------------------------------

	ISTimedActionQueue.clear(
		player
	)

	--------------------------------------------------------
	-- QUEUE EVERY SUPPLY STOP REQUIRED BY THIS HAUL
	--------------------------------------------------------

	for stopIndex, stop in ipairs(
		plan.stops
	) do

		cpDebug(
			"[ConstructionPlanner] Queueing supply stop "
			.. tostring(
				stopIndex
			)
			.. " / "
			.. tostring(
				#plan.stops
			)
		)

		if not queuePickupFromStop(
			player,
			stop,
			plan
		) then

			cpDebug(
				"[ConstructionPlanner] Failed to queue supply stop "
				.. tostring(
					stopIndex
				)
			)

			ISTimedActionQueue.clear(
				player
			)

			return
		end
	end

	cpDebug(
		"[ConstructionPlanner] Complete haul pickup route queued"
	)

	--------------------------------------------------------
	-- EXPLICIT PICKUP-ROUTE COMPLETION SENTINEL
	--
	-- THIS ACTION CAN ONLY RUN AFTER EVERY WALK / GRAB /
	-- TRANSFER / VIRTUALIZATION ACTION ALREADY QUEUED.
	--------------------------------------------------------

	ConstructionPlanner.pendingDeliveryPlan =
		plan

	ISTimedActionQueue.add(
		ISConstructionPlannerFinishPickupRoute:new(
			player,
			plan
		)
	)

	cpDebug(
		"[ConstructionPlanner] Pickup-route completion sentinel queued"
	)
end

------------------------------------------------------------
-- MULTI-LEVEL PHASE IDLE HANDOFF
------------------------------------------------------------

local function updateProjectPhaseIdleHandoff()
	if not ConstructionPlanner.pendingPhaseDistributionStart
	and not ConstructionPlanner.pendingPhaseBuildStart then
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

	--------------------------------------------------------
	-- WAIT UNTIL THE PREVIOUS TIMED ACTION IS COMPLETELY
	-- GONE FROM THE LUA QUEUE BEFORE STARTING A NEW ENGINE.
	--------------------------------------------------------

	if actionQueue
	and actionQueue.queue
	and actionQueue.queue[1] then
		return
	end

	if ConstructionPlanner.pendingPhaseDistributionStart then

		ConstructionPlanner.pendingPhaseDistributionStart =
			false

		cpDebug(
			"[ConstructionPlanner] Idle queue reached - starting next phase distribution"
		)

		startDistributionPickup()
		return
	end

	if ConstructionPlanner.pendingPhaseBuildStart then

		ConstructionPlanner.pendingPhaseBuildStart =
			false

		cpDebug(
			"[ConstructionPlanner] Idle queue reached - starting active phase tools/build"
		)

		if not ConstructionPlanner.startToolAcquisition then
			cpDebug(
				"[ConstructionPlanner] Tool manager not available"
			)
			return
		end

		local toolsReady =
			ConstructionPlanner.startToolAcquisition()

		----------------------------------------------------
		-- FALSE MAY MEAN TOOLMANAGER QUEUED PICKUPS. ITS
		-- EXISTING CONTINUATION WILL START PROJECTBUILDER.
		----------------------------------------------------

		if toolsReady then
			if ConstructionPlanner.startPlannedProject then
				cpDebug(
					"[ConstructionPlanner] Starting construction phase"
				)
				ConstructionPlanner.startPlannedProject()
			else
				cpDebug(
					"[ConstructionPlanner] Project builder not available"
				)
			end
		end
	end
end

------------------------------------------------------------
-- PUBLIC DISTRIBUTION START
------------------------------------------------------------

ConstructionPlanner.startDistributionPickup =
	startDistributionPickup

Events.OnTick.Add(
	updateDistributionContinuation
)

Events.OnTick.Add(
	updateProjectPhaseIdleHandoff
)

Events.OnTick.Add(
	updateVirtualHaulInterruption
)