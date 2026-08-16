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
-- PROJECT BUILD STATE
------------------------------------------------------------

ConstructionPlanner.projectBuilding = false
ConstructionPlanner.projectSegmentIndex = 0
ConstructionPlanner.projectBuildQueue = nil
ConstructionPlanner.projectBuildIndex = 0
ConstructionPlanner.projectBuildCursor = nil
ConstructionPlanner.projectBuildSegment = nil
ConstructionPlanner.projectModDataTemplate = nil

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

local function copyTiles(sourceTiles)
	local copied = {}

	if not sourceTiles then
		return copied
	end

	for _, tile in ipairs(sourceTiles) do
		table.insert(
			copied,
			{
				x = tile.x,
				y = tile.y,
				z = tile.z,

				-- Preserve multi-level phase metadata when ProjectBuilder
				-- creates its private build queue.  Dropping these fields
				-- caused Z1/Z2 tiles to leak into the active Z0 phase.
				cpPhaseIndex = tile.cpPhaseIndex,
				cpPhaseKind = tile.cpPhaseKind,
				cpStageZ = tile.cpStageZ,
				cpBuildFromZ = tile.cpBuildFromZ
			}
		)
	end

	return copied
end

local function copyModData(source)
	local result = {}

	if not source then
		return result
	end

	for key, value in pairs(source) do
		result[key] = value
	end

	return result
end

local function recalculateMaterials()
	if ConstructionPlanner.calculateProjectMaterials then
		ConstructionPlanner.calculateProjectMaterials()
	end
end

------------------------------------------------------------
-- BUILD LOGIC
------------------------------------------------------------

local function refreshBuildLogic(
	cursor,
	tile
)
	if not cursor then
		cpDebug(
			"[ConstructionPlanner] refreshBuildLogic FAILED: no cursor"
		)

		return false
	end

	if not tile then
		cpDebug(
			"[ConstructionPlanner] refreshBuildLogic FAILED: no tile"
		)

		return false
	end

	local player =
		cursor.character

	if not player then
		cpDebug(
			"[ConstructionPlanner] refreshBuildLogic FAILED: no character"
		)

		return false
	end

	if not cursor.craftRecipe then
		cpDebug(
			"[ConstructionPlanner] refreshBuildLogic FAILED: no craftRecipe"
		)

		return false
	end

	if not ISInventoryPaneContextMenu
	or not ISInventoryPaneContextMenu.getContainers then

		cpDebug(
			"[ConstructionPlanner] refreshBuildLogic FAILED: getContainers unavailable"
		)

		return false
	end

	--------------------------------------------------------
	-- REFRESH VANILLA INVENTORY / FLOOR VIEW
	--------------------------------------------------------

	local playerNum =
		player:getPlayerNum()

	local playerInventory =
		getPlayerInventory(
			playerNum
		)

	if playerInventory
	and playerInventory.refreshBackpacks then

		playerInventory:refreshBackpacks()
	end

	local playerLoot =
		getPlayerLoot(
			playerNum
		)

	if playerLoot
	and playerLoot.refreshBackpacks then

		playerLoot:refreshBackpacks()

		cpDebug(
			"[ConstructionPlanner] Refreshed nearby floor materials"
		)
	end

	--------------------------------------------------------
	-- CURRENT VANILLA CONTAINERS
	--------------------------------------------------------

	local containers =
		ISInventoryPaneContextMenu.getContainers(
			player
		)

	if not containers then

		cpDebug(
			"[ConstructionPlanner] refreshBuildLogic FAILED: containers nil"
		)

		return false
	end

	--------------------------------------------------------
	-- CREATE COMPLETELY FRESH BUILD LOGIC
	--------------------------------------------------------

	local newLogic =
		BuildLogic.new(
			player,
			nil,
			nil
		)

	if not newLogic then

		cpDebug(
			"[ConstructionPlanner] refreshBuildLogic FAILED: BuildLogic.new returned nil"
		)

		return false
	end

	newLogic:setContainers(
		containers
	)

	newLogic:setRecipe(
		cursor.craftRecipe
	)

	--------------------------------------------------------
	-- MANUAL INPUT MODE
	--
	-- EVERY BUILD GETS NEW PHYSICAL ITEM REFERENCES.
	--------------------------------------------------------

	newLogic:setManualSelectInputs(
		true
	)

	newLogic:clearManualInputs()

	--------------------------------------------------------
	-- EXACT BUILD TILE
	--------------------------------------------------------

	local targetSquare =
		getCell():getGridSquare(
			tile.x,
			tile.y,
			tile.z
		)

	if not targetSquare then

		cpDebug(
			"[ConstructionPlanner] refreshBuildLogic FAILED: target square missing"
		)

		return false
	end

	--------------------------------------------------------
	-- MATERIAL SOURCE SQUARE
	--
	-- Normal builds consume staged materials from the build
	-- square itself.  FLOOR_BOOTSTRAP deliberately stages the
	-- Z+1 floor's materials on the real square one level below.
	--------------------------------------------------------

	local materialZ =
		tile.cpStageZ ~= nil
		and tile.cpStageZ
		or tile.z

	local materialSquare =
		getCell():getGridSquare(
			tile.x,
			tile.y,
			materialZ
		)

	if not materialSquare then
		cpDebug(
			"[ConstructionPlanner] refreshBuildLogic FAILED: material square missing at Z"
			.. tostring(materialZ)
		)
		return false
	end

	local worldObjects =
		materialSquare:getWorldObjects()

	if materialZ ~= tile.z then
		cpDebug(
			"[ConstructionPlanner] FLOOR_BOOTSTRAP inputs: build Z"
			.. tostring(tile.z)
			.. " using staged materials on Z"
			.. tostring(materialZ)
		)
	end

	local inventory =
		player:getInventory()

	if not inventory then

		cpDebug(
			"[ConstructionPlanner] refreshBuildLogic FAILED: inventory missing"
		)

		return false
	end

	local inventoryItems =
		inventory:getItems()

	local inputs =
		cursor.craftRecipe:getInputs()

	--------------------------------------------------------
	-- ASSIGN EVERY INPUT FRESH
	--------------------------------------------------------

	for inputIndex = 0, inputs:size() - 1 do

		local inputScript =
			inputs:get(
				inputIndex
			)

		if inputScript then

			local selectedItems =
				ArrayList.new()

			local possibleItems =
				inputScript:getPossibleInputItems()

			local required =
				1

			if inputScript:isItemCount() then

				required =
					inputScript:getIntAmount()

			else

				required =
					inputScript:getAmount()
			end

			local remaining =
				required

			------------------------------------------------
			-- KEEP INPUT
			--
			-- TOOLS COME FROM CURRENT PLAYER INVENTORY.
			------------------------------------------------

			if inputScript:isKeep() then

				for possibleIndex = 0,
					possibleItems:size() - 1 do

					if remaining <= 0 then
						break
					end

					local possibleItem =
						possibleItems:get(
							possibleIndex
						)

					if possibleItem then

						local fullType =
							possibleItem:getFullName()

						for itemIndex = 0,
							inventoryItems:size() - 1 do

							if remaining <= 0 then
								break
							end

							local item =
								inventoryItems:get(
									itemIndex
								)

							if item
							and item:getFullType()
								== fullType then

								selectedItems:add(
									item
								)

								remaining =
									remaining - 1
							end
						end
					end
				end

			else

				------------------------------------------------
				-- CONSUMED MATERIAL
				--
				-- ONLY THE MATERIALS STAGED ON THIS EXACT
				-- PROJECT TILE ARE ALLOWED.
				------------------------------------------------

				if worldObjects then

					for objectIndex = 0,
						worldObjects:size() - 1 do

						if remaining <= 0 then
							break
						end

						local worldObject =
							worldObjects:get(
								objectIndex
							)

						local item =
							worldObject
							and worldObject:getItem()
							or nil

						if item then

							local accepted =
								false

							for possibleIndex = 0,
								possibleItems:size() - 1 do

								local possibleItem =
									possibleItems:get(
										possibleIndex
									)

								if possibleItem
								and item:getFullType()
									== possibleItem:getFullName() then

									accepted =
										true

									break
								end
							end

							if accepted then

								selectedItems:add(
									item
								)

								remaining =
									remaining - 1
							end
						end
					end
				end
			end

			cpDebug(
				"[ConstructionPlanner] Fresh input "
				.. tostring(
					inputIndex + 1
				)
				.. " selected="
				.. tostring(
					selectedItems:size()
				)
				.. " required="
				.. tostring(
					required
				)
			)

			------------------------------------------------
			-- FAIL IF THIS TILE DOES NOT ACTUALLY HAVE
			-- EVERYTHING VANILLA NEEDS.
			------------------------------------------------

			if remaining > 0 then

				cpDebug(
					"[ConstructionPlanner] refreshBuildLogic FAILED: input "
					.. tostring(
						inputIndex + 1
					)
					.. " missing "
					.. tostring(
						remaining
					)
				)

				return false
			end

			------------------------------------------------
			-- GIVE VANILLA THESE EXACT ITEM OBJECTS
			------------------------------------------------

			if not newLogic:setManualInputsFor(
				inputScript,
				selectedItems
			) then

				cpDebug(
					"[ConstructionPlanner] refreshBuildLogic FAILED: setManualInputsFor input "
					.. tostring(
						inputIndex + 1
					)
				)

				return false
			end
		end
	end

	--------------------------------------------------------
	-- APPLY THE FRESH INPUT DATA
	--------------------------------------------------------

	if newLogic.updateManualInputAllowedItemTypes then

		newLogic:updateManualInputAllowedItemTypes()
	end

	local canPerform =
		newLogic:canPerformCurrentRecipe()

	--------------------------------------------------------
	-- INSTALL FRESH LOGIC
	--------------------------------------------------------

	cursor.containers =
		containers

	cursor.buildPanelLogic =
		newLogic

	cursor.blockBuild =
		false

	cpDebug(
		"[ConstructionPlanner] fresh canPerformCurrentRecipe="
		.. tostring(
			canPerform
		)
	)

	cpDebug(
		"[ConstructionPlanner] refreshBuildLogic SUCCESS"
	)

	return true
end


local function restoreModData(cursor)
	if not cursor then
		return
	end

	if not ConstructionPlanner.projectModDataTemplate then
		return
	end

	cursor.modData =
		copyModData(
			ConstructionPlanner.projectModDataTemplate
		)
end

------------------------------------------------------------
-- REMOVE COMPLETED PREVIEW
------------------------------------------------------------

local function removeCompletedTile(segment, completedTile)
	if not segment
	or not segment.remainingTiles
	or not completedTile then
		return
	end

	for index, tile in ipairs(segment.remainingTiles) do

		if tile.x == completedTile.x
		and tile.y == completedTile.y
		and tile.z == completedTile.z then

			table.remove(
				segment.remainingTiles,
				index
			)

			return
		end
	end
end

------------------------------------------------------------
-- STOP PROJECT BUILD
------------------------------------------------------------

local function stopProjectBuild(reason)
	ConstructionPlanner.projectBuilding =
		false

	ConstructionPlanner.projectBuildQueue =
		nil

	ConstructionPlanner.projectBuildIndex =
		0

	ConstructionPlanner.projectBuildCursor =
		nil

	ConstructionPlanner.projectBuildSegment =
		nil

	ConstructionPlanner.projectBuildWalkPending =
		false

	ConstructionPlanner.projectBuildWalkTile =
		nil

	ConstructionPlanner.projectBuildWalkObserved =
		false

	ConstructionPlanner.projectNextBuildPending =
		false

	ConstructionPlanner.projectNextBuildDelay =
		nil

	-- Very important:
	-- keep the pending project and remaining previews.
	if ConstructionPlanner.pendingProject then
		ConstructionPlanner.pendingProject.status =
			"planning"
	end

	if reason then
		cpDebug(
			"[ConstructionPlanner] Project build stopped - "
			.. tostring(reason)
		)
	end

	recalculateMaterials()
end

------------------------------------------------------------
-- COMPLETE PROJECT
------------------------------------------------------------

local function completeProject()
	cpDebug(
		"[ConstructionPlanner] ========================="
	)

	cpDebug(
		"[ConstructionPlanner] PROJECT BUILDING COMPLETE"
	)

	cpDebug(
		"[ConstructionPlanner] ========================="
	)

	--------------------------------------------------------
	-- STOP BUILD STATE
	--------------------------------------------------------

	ConstructionPlanner.projectBuilding =
		false

	ConstructionPlanner.projectBuildQueue =
		nil

	ConstructionPlanner.projectBuildIndex =
		0

	ConstructionPlanner.projectBuildCursor =
		nil

	ConstructionPlanner.projectBuildSegment =
		nil

	ConstructionPlanner.projectSegmentIndex =
		0

	--------------------------------------------------------
	-- RETURN BORROWED TOOLS BEFORE FINAL CLEANUP
	--------------------------------------------------------

	if ConstructionPlanner.startToolReturn then

		local returningTools =
			ConstructionPlanner.startToolReturn()

		if returningTools then

			cpDebug(
				"[ConstructionPlanner] Returning borrowed tools"
			)

			return
		end
	end

	--------------------------------------------------------
	-- NO TOOLS TO RETURN
	-- FINALIZE IMMEDIATELY
	--------------------------------------------------------

	if ConstructionPlanner.finalizeProject then

		ConstructionPlanner.finalizeProject()

	else

		ConstructionPlanner.pendingProject =
			nil

		recalculateMaterials()
	end
end

local function getSquareObjectCount(tile)
	if not tile then
		return 0
	end

	--------------------------------------------------------
	-- DO NOT CALL copyTileForWalk() HERE.
	--
	-- This helper appears earlier in the file than
	-- copyTileForWalk(), so the later local function is not
	-- yet in lexical scope here in Lua.
	--
	-- Compute the active walk/build-observation Z directly.
	--------------------------------------------------------

	local walkZ =
		tile.z

	local project =
		ConstructionPlanner.pendingProject

	local activePhase =
		project
		and project.cpPhasePlan
		and project.cpPhasePlan[
			project.cpActivePhaseIndex or 1
		]
		or nil

	if activePhase
	and activePhase.kind == "FLOOR_BOOTSTRAP" then

		walkZ =
			tile.z - 1
	end

	local square =
		getCell():getGridSquare(
			tile.x,
			tile.y,
			walkZ
		)

	if not square then
		return 0
	end

	local objects =
		square:getObjects()

	if not objects then
		return 0
	end

	local worldObjects =
		square:getWorldObjects()

	local count =
		objects:size()

	if worldObjects then
		count =
			count - worldObjects:size()
	end

	if count < 0 then
		count = 0
	end

	return count
end

local function getActiveProjectPhase()
    return ConstructionPlanner.getActiveProjectPhase
        and ConstructionPlanner.getActiveProjectPhase()
        or nil
end

local function tileIsInActivePhase(tile)
    if not tile then
        return false
    end

    local project = ConstructionPlanner.pendingProject
    local activeIndex = project and (project.cpActivePhaseIndex or 1) or 1

    --------------------------------------------------------
    -- No phase plan = legacy/single-level behavior.
    --------------------------------------------------------

    if not project or not project.cpPhasePlan then
        return true
    end

    --------------------------------------------------------
    -- With an active phase plan, missing metadata must be
    -- treated as NOT ACTIVE.  The old permissive fallback
    -- is what allowed copied Z1 tiles into the Z0 pass.
    --------------------------------------------------------

    if tile.cpPhaseIndex == nil then
        return false
    end

    return tile.cpPhaseIndex == activeIndex
end

local function copyTileForWalk(tile)
    if not tile then
        return nil
    end

    local phase = getActiveProjectPhase()
    local walkZ = tile.z

    if phase and phase.kind == "FLOOR_BOOTSTRAP" then
        walkZ = tile.z - 1
    end

    return {
        x = tile.x,
        y = tile.y,
        z = walkZ
    }
end

local function queueProjectWalkToTile(tile)
	local player =
		getSpecificPlayer(0)

	if not player
	or not tile then

		return false
	end

	-- FLOOR_BOOTSTRAP builds a floor at Z+1 while the character remains
	-- on the supporting level below.  Use the walk copy here, not the
	-- actual build target, so pathfinding never tries to reach empty air.
	local walkTile =
		copyTileForWalk(tile)

	if not walkTile then
		return false
	end

	local square =
		getCell():getGridSquare(
			walkTile.x,
			walkTile.y,
			walkTile.z
		)

	if not square then

		cpDebug(
			"[ConstructionPlanner] Project walk failed - target square missing"
		)

		return false
	end

	--------------------------------------------------------
	-- FIND A FREE TILE BESIDE THE BUILD LOCATION
	--------------------------------------------------------

	local adjacent =
		AdjacentFreeTileFinder.Find(
			square,
			player
		)

	if not adjacent then

		cpDebug(
			"[ConstructionPlanner] Project walk failed - no adjacent square"
		)

		return false
	end

	--------------------------------------------------------
	-- QUEUE THE SAME SHARED WALK USED BY DISTRIBUTION
	--------------------------------------------------------

	local walkAction =
		ConstructionPlanner.queueWalkAction(
			player,
			adjacent
		)

	if not walkAction then

		cpDebug(
			"[ConstructionPlanner] Project walk failed - could not queue CP walk"
		)

		return false
	end

	--------------------------------------------------------
	-- AFTER THE WALK QUEUE BECOMES EMPTY,
	-- updateProjectBuilder() WILL START THE BUILD.
	--------------------------------------------------------

	ConstructionPlanner.projectBuildWalkPending =
		true

	ConstructionPlanner.projectBuildWalkTile =
		tile

	cpDebug(
		"[ConstructionPlanner] Walking to project build "
		.. tostring(tile.x)
		.. ", "
		.. tostring(tile.y)
		.. ", "
		.. tostring(tile.z)
		.. (
			walkTile
			and walkTile.z ~= tile.z
			and (
				" from Z"
				.. tostring(walkTile.z)
			)
			or ""
		)
	)

	return true
end

------------------------------------------------------------
-- START ONE SEGMENT
------------------------------------------------------------

local function startProjectSegment(segmentIndex)
	local project =
		ConstructionPlanner.pendingProject

	if not project
	or not project.segments then

		stopProjectBuild(
			"project missing"
		)

		return false
	end

	--------------------------------------------------------
	-- FIND NEXT NON-EMPTY SEGMENT
	--------------------------------------------------------

	local segment =
		nil

	local foundIndex =
		nil

	for index = segmentIndex, #project.segments do

		local candidate =
			project.segments[
				index
			]

		if candidate
		and candidate.remainingTiles
		and #candidate.remainingTiles > 0 then

			local hasActiveTile =
				false

			for _, candidateTile in ipairs(
				candidate.remainingTiles
			) do

				if tileIsInActivePhase(
					candidateTile
				) then

					hasActiveTile =
						true

					break
				end
			end

			if hasActiveTile then
				segment =
					candidate

				foundIndex =
					index

				break
			end
		end
	end

	--------------------------------------------------------
	-- NOTHING LEFT
	--------------------------------------------------------

	if not segment then

		--------------------------------------------------------
		-- ACTIVE PHASE COMPLETE
		--------------------------------------------------------

		if ConstructionPlanner.advanceProjectPhase
		and ConstructionPlanner.advanceProjectPhase() then

			local nextPhase =
				getActiveProjectPhase()

			cpDebug(
				"[ConstructionPlanner] Build phase complete - returning to distribution"
			)

			if nextPhase then
				cpDebug(
					"[ConstructionPlanner] Next phase: "
					.. tostring(nextPhase.kind)
					.. " Z"
					.. tostring(nextPhase.targetZ)
				)
			end

			ConstructionPlanner.projectBuilding =
				false

			ConstructionPlanner.projectBuildQueue =
				nil

			ConstructionPlanner.projectBuildCursor =
				nil

			ConstructionPlanner.projectBuildSegment =
				nil

			ConstructionPlanner.projectSegmentIndex =
				0

			----------------------------------------------------
			-- DO NOT START DISTRIBUTION INSIDE THE BUILD
			-- COMPLETION PATH.  The final vanilla/project timed
			-- action is still unwinding here.  Starting the next
			-- engine inline can leave its first action orphaned.
			--
			-- DistributionManager will start it on the first
			-- genuinely idle tick.
			----------------------------------------------------

			ConstructionPlanner.pendingPhaseDistributionStart =
				true

			cpDebug(
				"[ConstructionPlanner] Next phase distribution pending idle queue"
			)

			return true
		end

		completeProject()

		return true
	end

	local cursor =
		segment.buildCursor

	if not cursor then

		stopProjectBuild(
			"saved build cursor missing"
		)

		return false
	end

	--------------------------------------------------------
	-- RESTORE SAVED WALL DIRECTION
	--------------------------------------------------------

	if segment.north ~= nil then

		cursor.north =
			segment.north
	end

	--------------------------------------------------------
	-- RESTORE SAVED SPRITE ROTATION
	--------------------------------------------------------

	if segment.nSprite ~= nil then

		cursor.nSprite =
			segment.nSprite

		cursor.nSpriteCache =
			-1

		if cursor.getSprite then

			cursor:getSprite()
		end
	end

	--------------------------------------------------------
	-- SAVE THIS SEGMENT'S BUILD STATE
	--------------------------------------------------------

	ConstructionPlanner.projectSegmentIndex =
		foundIndex

	ConstructionPlanner.projectBuildSegment =
		segment

	ConstructionPlanner.projectBuildCursor =
		cursor

	ConstructionPlanner.projectBuildQueue =
		{}

	for _, projectTile in ipairs(
		segment.remainingTiles
	) do

		if tileIsInActivePhase(
			projectTile
		) then

			table.insert(
				ConstructionPlanner.projectBuildQueue,
				{
					x = projectTile.x,
					y = projectTile.y,
					z = projectTile.z,
					cpPhaseIndex = projectTile.cpPhaseIndex,
					cpPhaseKind = projectTile.cpPhaseKind,
					cpStageZ = projectTile.cpStageZ,
					cpBuildFromZ = projectTile.cpBuildFromZ
				}
			)
		end
	end

	ConstructionPlanner.projectBuildIndex =
		1

	ConstructionPlanner.currentCursor =
		cursor

	ConstructionPlanner.currentCursorName =
		tostring(
			cursor.name
		)

	ConstructionPlanner.projectModDataTemplate =
		copyModData(
			cursor.modData
		)

	--------------------------------------------------------
	-- FIRST BUILD TILE
	--------------------------------------------------------

	local tile =
		ConstructionPlanner.projectBuildQueue[
			1
		]

	if not tile then

		stopProjectBuild(
			"first project tile missing"
		)

		return false
	end

	cpDebug(
		"[ConstructionPlanner] Starting project segment "
		.. tostring(
			foundIndex
		)
		.. " - "
		.. tostring(
			segment.buildableName
		)
		.. " - "
		.. tostring(
			#ConstructionPlanner.projectBuildQueue
		)
		.. " build(s)"
	)

	cpDebug(
		"[ConstructionPlanner] Project build 1 / "
		.. tostring(
			#ConstructionPlanner.projectBuildQueue
		)
	)

	--------------------------------------------------------
	-- WALK TO STAGED MATERIALS FIRST
	--------------------------------------------------------

	if not queueProjectWalkToTile(
		tile
	) then

		stopProjectBuild(
			"could not walk to first build"
		)

		return false
	end

	return true
end

------------------------------------------------------------
-- START WHOLE PROJECT
------------------------------------------------------------

function ConstructionPlanner.startPlannedProject()
	if ConstructionPlanner.projectBuilding then
		cpDebug(
			"[ConstructionPlanner] Project is already building"
		)

		return
	end

	if ConstructionPlanner.building then
		cpDebug(
			"[ConstructionPlanner] Quick Build is currently active"
		)

		return
	end

	local project =
		ConstructionPlanner.pendingProject

	if not project
	or not project.segments
	or #project.segments == 0 then

		cpDebug(
			"[ConstructionPlanner] No project to build"
		)

		return
	end

	if not ConstructionPlanner.originalTryBuild then
		cpDebug(
			"[ConstructionPlanner] tryBuild hook not ready"
		)

		return
	end

	cpDebug(
		"[ConstructionPlanner] ========================="
	)

	cpDebug(
		"[ConstructionPlanner] STARTING PROJECT"
	)

	cpDebug(
		"[ConstructionPlanner] ========================="
	)

	local activePhase =
		getActiveProjectPhase()

	if activePhase then
		cpDebug(
			"[ConstructionPlanner] Active build phase: "
			.. tostring(activePhase.kind)
			.. " Z"
			.. tostring(activePhase.targetZ)
		)
	end

	project.status =
		"building"

	ConstructionPlanner.projectBuilding =
		true

	ConstructionPlanner.projectSegmentIndex =
		1

	startProjectSegment(1)
end



------------------------------------------------------------
-- PROJECT BUILD PERFORM / LIFECYCLE HOOK
------------------------------------------------------------

------------------------------------------------------------
-- FLOOR BOOTSTRAP VALIDATION OVERRIDE
------------------------------------------------------------

local function ensureBootstrapFloorValidationOverride()
	if ConstructionPlanner.bootstrapFloorValidationHooked then
		return true
	end

	if not BuildRecipeCode
	or not BuildRecipeCode.floor
	or not BuildRecipeCode.floor.OnIsValid then
		cpDebug("[ConstructionPlanner] FLOOR_BOOTSTRAP validation hook unavailable")
		return false
	end

	ConstructionPlanner.originalFloorOnIsValid =
		BuildRecipeCode.floor.OnIsValid

	BuildRecipeCode.floor.OnIsValid = function(params)
		local target =
			ConstructionPlanner.bootstrapValidationTarget

		local square =
			params
			and params.square
			or nil

		local exactBootstrapTarget =
			target
			and square
			and square:getX() == target.x
			and square:getY() == target.y
			and square:getZ() == target.z

		if not exactBootstrapTarget then
			return ConstructionPlanner.originalFloorOnIsValid(params)
		end

		-- Preserve vanilla rejection when stairs already occupy/support below.
		if square:HasStairsBelow() then
			cpDebug("[ConstructionPlanner] FLOOR_BOOTSTRAP invalid: stairs below target")
			return false
		end

		local tileInfoSprite =
			params.tileInfo
			and params.tileInfo:getSpriteName()
			or nil

		local objects =
			square:getObjects()

		if objects then
			for i = 0, objects:size() - 1 do
				local item = objects:get(i)

				if item then
					local textureName = item:getTextureName()
					local spriteName = item:getSpriteName()

					if (
						textureName
						and luautils.stringStarts(textureName, "vegetation_farming")
					)
					or (
						spriteName
						and luautils.stringStarts(spriteName, "vegetation_farming")
					) then
						return false
					end

					if (
						textureName
						and textureName == tileInfoSprite
					)
					or (
						spriteName
						and spriteName == tileInfoSprite
					) then
						return false
					end
				end
			end
		end

		-- The ONE vanilla rule intentionally waived here is:
		-- if not square:connectedWithFloor() then return false end
		params.testCollisions = false

		cpDebug(
			"[ConstructionPlanner] FLOOR_BOOTSTRAP structural validation accepted at "
			.. tostring(square:getX()) .. ","
			.. tostring(square:getY()) .. ","
			.. tostring(square:getZ())
		)

		return true
	end

	ConstructionPlanner.bootstrapFloorValidationHooked = true

	cpDebug("[ConstructionPlanner] FLOOR_BOOTSTRAP floor validation hook installed")

	return true
end

local function getActualBuildTargetObjectCount(tile)
	if not tile then
		return 0
	end

	local square =
		getCell():getGridSquare(
			tile.x,
			tile.y,
			tile.z
		)

	if not square then
		return 0
	end

	local objects =
		square:getObjects()

	if not objects then
		return 0
	end

	local worldObjects =
		square:getWorldObjects()

	local count =
		objects:size()

	if worldObjects then
		count =
			count - worldObjects:size()
	end

	if count < 0 then
		count = 0
	end

	return count
end

local function ensureProjectPerformHook()
	if ConstructionPlanner.projectPerformHooked then
		return
	end

	-- Wait until CursorWatcher has installed its normal
	-- Quick Build perform hook first.
	if not ConstructionPlanner.buildPerformHooked then
		return
	end

	if not ISBuildAction
	or not ISBuildAction.perform then
		return
	end

	--------------------------------------------------------
	-- SAVE CURRENT PERFORM HANDLER
	--------------------------------------------------------

	ConstructionPlanner.originalProjectPerform =
		ISBuildAction.perform

	--------------------------------------------------------
	-- PROJECT BUILD PERFORM HOOK
	--------------------------------------------------------

	ISBuildAction.perform = function(self)

		----------------------------------------------------
		-- RUN EXISTING VANILLA / QUICK PERFORM HANDLER
		----------------------------------------------------

		ConstructionPlanner.originalProjectPerform(
			self
		)

		----------------------------------------------------
		-- IGNORE NORMAL AND QUICK BUILDS
		----------------------------------------------------

		if not ConstructionPlanner.projectBuilding then
			return
		end

		local queue =
			ConstructionPlanner.projectBuildQueue

		local segment =
			ConstructionPlanner.projectBuildSegment

		if not queue
		or not segment then

			stopProjectBuild(
				"project queue state missing"
			)

			return
		end

		----------------------------------------------------
		-- CURRENT PROJECT TILE
		----------------------------------------------------

		local completedTile =
			queue[
				ConstructionPlanner.projectBuildIndex
			]

		if not completedTile then

			stopProjectBuild(
				"completed tile missing"
			)

			return
		end

		----------------------------------------------------
		-- BUILD REALLY SUCCEEDED
		----------------------------------------------------

		local completedBootstrap =
			completedTile.cpPhaseKind == "FLOOR_BOOTSTRAP"
			or (
				completedTile.cpBuildFromZ ~= nil
				and completedTile.cpBuildFromZ ~= completedTile.z
			)

		if completedBootstrap then
			local beforeCount =
				ConstructionPlanner.projectBeforeActualTargetObjectCount
				or 0

			local afterCount =
				getActualBuildTargetObjectCount(
					completedTile
				)

			ConstructionPlanner.bootstrapValidationTarget = nil

			cpDebug(
				"[ConstructionPlanner] FLOOR_BOOTSTRAP target object count "
				.. tostring(beforeCount)
				.. " -> "
				.. tostring(afterCount)
			)

			if afterCount <= beforeCount then
				ConstructionPlanner.projectBeforeActualTargetObjectCount = nil

				stopProjectBuild(
					"FLOOR_BOOTSTRAP action finished but no upper-floor object was created"
				)

				return
			end

			cpDebug(
				"[ConstructionPlanner] FLOOR_BOOTSTRAP REAL BUILD CONFIRMED"
			)
		end

		ConstructionPlanner.projectBeforeActualTargetObjectCount = nil

		removeCompletedTile(
			segment,
			completedTile
		)

		----------------------------------------------------
		-- IF THIS NEW BUILD IS A CONTAINER INSIDE A
		-- GATHER AREA, AUTOMATICALLY MAKE IT A SUPPLY
		-- CONTAINER.
		----------------------------------------------------

		if ConstructionPlanner.addSupplyContainersAtGatherTile then

			ConstructionPlanner.addSupplyContainersAtGatherTile(
				completedTile.x,
				completedTile.y,
				completedTile.z
			)
		end

		cpDebug(
			"[ConstructionPlanner] Project build completed at "
			.. tostring(completedTile.x)
			.. ", "
			.. tostring(completedTile.y)
			.. ", "
			.. tostring(completedTile.z)
		)

		recalculateMaterials()

		ConstructionPlanner.projectBuildIndex =
			ConstructionPlanner.projectBuildIndex + 1

		----------------------------------------------------
		-- SEGMENT FINISHED
		----------------------------------------------------

		if ConstructionPlanner.projectBuildIndex
		> #queue then

			cpDebug(
				"[ConstructionPlanner] Project segment "
				.. tostring(
					ConstructionPlanner.projectSegmentIndex
				)
				.. " complete"
			)

			local nextSegment =
				ConstructionPlanner.projectSegmentIndex
				+ 1

			ConstructionPlanner.projectBuildQueue =
				nil

			ConstructionPlanner.projectBuildIndex =
				0

			ConstructionPlanner.projectBeforeObjectCount =
				nil

			------------------------------------------------
			-- START NEXT SEGMENT LATER
			------------------------------------------------

			ConstructionPlanner.projectNextSegment =
				nextSegment

			ConstructionPlanner.projectNextBuildPending =
				true

			ConstructionPlanner.projectNextBuildDelay =
				nil

			return
		end

		----------------------------------------------------
		-- DO NOT START NEXT BUILD INSIDE perform()
		----------------------------------------------------

		ConstructionPlanner.projectNextBuildPending =
			true

		ConstructionPlanner.projectNextBuildDelay =
			nil
	end

	ConstructionPlanner.projectPerformHooked =
		true

	cpDebug(
		"[ConstructionPlanner] Project perform hook installed"
	)
end

local projectStableIdleTicks = {}

local function isProjectActionQueueStablyIdle(
	player,
	key
)
	if not player then

		projectStableIdleTicks[key] =
			0

		return false
	end

	local actionQueue =
		ISTimedActionQueue.getTimedActionQueue(
			player
		)

	--------------------------------------------------------
	-- LUA TIMED-ACTION QUEUE
	--------------------------------------------------------

	if actionQueue
	and actionQueue.queue
	and actionQueue.queue[1] then

		projectStableIdleTicks[key] =
			0

		return false
	end

	--------------------------------------------------------
	-- VANILLA CHARACTER ACTIONS
	--
	-- THIS IS THE ACTUAL ACTION LIST USED BY VANILLA'S
	-- ISTimedActionQueue.isPlayerDoingAction().
	--------------------------------------------------------

	local characterActions =
		player:getCharacterActions()

	if characterActions
	and not characterActions:isEmpty() then

		projectStableIdleTicks[key] =
			0

		return false
	end

	--------------------------------------------------------
	-- BOTH SIDES ARE IDLE
	--------------------------------------------------------

	projectStableIdleTicks[key] =
		(projectStableIdleTicks[key] or 0)
		+ 1

	if projectStableIdleTicks[key] < 2 then
		return false
	end

	projectStableIdleTicks[key] =
		0

	return true
end

local function updateProjectBuilder()
	if not ConstructionPlanner.projectBuilding then
		return
	end

	--------------------------------------------------------
	-- PLAYER HAS BEEN SENT TO A BUILD TILE
	--------------------------------------------------------

	if ConstructionPlanner.projectBuildWalkPending then

		local player =
			getSpecificPlayer(0)

		if not player then
			return
		end

		local actionQueue =
			ISTimedActionQueue.getTimedActionQueue(
				player
			)

		local luaActive =
			actionQueue
			and actionQueue.queue
			and actionQueue.queue[1]
				~= nil

		local characterActions =
			player:getCharacterActions()

		local javaActive =
			characterActions
			and not characterActions:isEmpty()

		----------------------------------------------------
		-- FIRST OBSERVE THE WALK / VANILLA ACTION STATE
		----------------------------------------------------

		if not ConstructionPlanner.projectBuildWalkObserved then

			if luaActive
			or javaActive then

				ConstructionPlanner.projectBuildWalkObserved =
					true

				cpDebug(
					"[ConstructionPlanner] Project walk action observed"
				)

				return
			end

			------------------------------------------------
			-- walkAdj() MAY REQUIRE NO WALK AT ALL IF THE
			-- PLAYER IS ALREADY IN A VALID POSITION.
			--
			-- IN THAT CASE THERE IS NOTHING TO WAIT FOR,
			-- SO ALLOW THE NORMAL STABLE-IDLE CHECK BELOW.
			------------------------------------------------
		end

		----------------------------------------------------
		-- IF AN ACTION IS ACTIVE, THE WALK / POSITIONING
		-- PHASE IS DEFINITELY NOT FINISHED.
		----------------------------------------------------

		if luaActive
		or javaActive then
			return
		end

		----------------------------------------------------
		-- REQUIRE BOTH VANILLA ACTION REPRESENTATIONS TO
		-- REMAIN IDLE BEFORE MOVING INTO THE BUILD.
		----------------------------------------------------

		if not isProjectActionQueueStablyIdle(
			player,
			"projectWalk"
		) then
			return
		end

		----------------------------------------------------
		-- ARRIVED AT BUILD LOCATION
		----------------------------------------------------

		local tile =
			ConstructionPlanner.projectBuildWalkTile

		local cursor =
			ConstructionPlanner.projectBuildCursor

		local segment =
			ConstructionPlanner.projectBuildSegment

		if not tile
		or not cursor
		or not segment then

			stopProjectBuild(
				"project walk state missing"
			)

			return
		end

		ConstructionPlanner.projectBuildWalkPending =
			false

		ConstructionPlanner.projectBuildWalkTile =
			nil

		ConstructionPlanner.projectBuildWalkObserved =
			false

		cpDebug(
			"[ConstructionPlanner] Arrived at project build location"
		)

		----------------------------------------------------
		-- RESTORE SAVED BUILD MOD DATA
		----------------------------------------------------

		restoreModData(
			cursor
		)

		----------------------------------------------------
		-- BUILD FRESH LOGIC USING EXACT STAGED ITEMS
		----------------------------------------------------

		if not refreshBuildLogic(
			cursor,
			tile
		) then

			stopProjectBuild(
				"could not refresh build logic after walking"
			)

			return
		end

		----------------------------------------------------
		-- RESTORE SAVED WALL DIRECTION
		----------------------------------------------------

		if segment.north ~= nil then

			cursor.north =
				segment.north
		end

		----------------------------------------------------
		-- RESTORE SAVED SPRITE ROTATION
		----------------------------------------------------

		if segment.nSprite ~= nil then

			cursor.nSprite =
				segment.nSprite

			cursor.nSpriteCache =
				-1

			if cursor.getSprite then
				cursor:getSprite()
			end
		end

		----------------------------------------------------
		-- RECORD STATE BEFORE BUILD
		----------------------------------------------------

		ConstructionPlanner.projectBeforeObjectCount =
			getSquareObjectCount(
				tile
			)

		----------------------------------------------------
		-- START VANILLA BUILD
		----------------------------------------------------

		cpDebug(
			"[ConstructionPlanner] Attempting vanilla project build at "
			.. tostring(tile.x)
			.. ", "
			.. tostring(tile.y)
			.. ", "
			.. tostring(tile.z)
		)

		----------------------------------------------------
		-- VANILLA tryBuild() MAY CREATE ITS OWN
		-- ISWalkToTimedAction BEFORE THE REAL BUILD ACTION.
		--
		-- TEMPORARILY MARK THOSE WALKS AS PROJECT WALKS SO
		-- THEY REMAIN VALID AT SPEED 3.
		----------------------------------------------------

		local originalWalkNew =
			ISWalkToTimedAction
			and ISWalkToTimedAction.new
			or nil

		if originalWalkNew then

			ISWalkToTimedAction.new = function(
				self,
				character,
				location,
				additionalTest,
				additionalContext
			)
				local walk =
					originalWalkNew(
						self,
						character,
						location,
						additionalTest,
						additionalContext
					)

				if ConstructionPlanner.projectBuilding
				and walk then

					walk.constructionPlannerWalk =
						true

					walk.isValid = function(self)

						if self.character:getVehicle() then
							return false
						end

						return getGameSpeed() <= 3
					end
				end

				return walk
			end
		end

		----------------------------------------------------
		-- FLOOR_BOOTSTRAP PROOF:
		--
		-- We have ALREADY walked the character to the valid
		-- lower-level position above.  Vanilla tryBuild() must
		-- still receive the REAL target x/y/Z so ISBuildAction
		-- and createBuildAction build on the upper level.
		--
		-- The only vanilla step we suppress is cursor:walkTo()
		-- during this one tryBuild() call, because vanilla would
		-- otherwise try to path beside the nonexistent Z+1 floor.
		----------------------------------------------------

		local bootstrap =
			tile.cpPhaseKind == "FLOOR_BOOTSTRAP"
			or (
				tile.cpBuildFromZ ~= nil
				and tile.cpBuildFromZ ~= tile.z
			)

		local savedCursorWalkTo =
			bootstrap
			and cursor.walkTo
			or nil

		if bootstrap then
			if not ensureBootstrapFloorValidationOverride() then
				stopProjectBuild(
					"FLOOR_BOOTSTRAP validation override unavailable"
				)
				return
			end

			ConstructionPlanner.bootstrapValidationTarget = {
				x = tile.x,
				y = tile.y,
				z = tile.z
			}

			ConstructionPlanner.projectBeforeActualTargetObjectCount =
				getActualBuildTargetObjectCount(
					tile
				)

			------------------------------------------------
			-- VANILLA MATERIAL GATE
			--
			-- ISBuildIsoEntity:isValid(targetSquare) checks
			-- self:haveMaterial(targetSquare) BEFORE it calls
			-- the recipe OnIsValid callback.
			--
			-- Bootstrap materials intentionally live on the
			-- lower staging square, so vanilla sees no materials
			-- on Z+1 and rejects the build before our structural
			-- validation override can even run.
			--
			-- refreshBuildLogic() immediately above has already
			-- selected the real staged inputs from cpStageZ and
			-- verified canPerformCurrentRecipe=true.  Therefore,
			-- for ONLY the exact active bootstrap target, let
			-- vanilla's haveMaterial gate pass.
			------------------------------------------------

			------------------------------------------------
			-- BOOTSTRAP PER-SQUARE VALIDATION
			--
			-- Entity scripts cache their OnIsValid callback, so
			-- replacing BuildRecipeCode.floor.OnIsValid globally
			-- does NOT affect the callback used by this cursor.
			--
			-- Override the cursor's actual isValidPerSquare()
			-- seam for ONLY the exact bootstrap target.
			------------------------------------------------

			if not cursor.cpBootstrapOriginalIsValidPerSquare then
				cursor.cpBootstrapOriginalIsValidPerSquare =
					cursor.isValidPerSquare
			end

			cursor.isValidPerSquare = function(
				self,
				square,
				tileInfo,
				requiresFloor,
				extendsN,
				extendsW
			)
				local target =
					ConstructionPlanner.bootstrapValidationTarget

				local exactTarget =
					target
					and square
					and square:getX() == target.x
					and square:getY() == target.y
					and square:getZ() == target.z

				if not exactTarget then
					if self.cpBootstrapOriginalIsValidPerSquare then
						return self:cpBootstrapOriginalIsValidPerSquare(
							square,
							tileInfo,
							requiresFloor,
							extendsN,
							extendsW
						)
					end
					return false
				end

				------------------------------------------------
				-- FLOOR-SPECIFIC VANILLA SAFETY CHECKS
				------------------------------------------------

				if square:HasStairsBelow() then
					cpDebug(
						"[ConstructionPlanner] FLOOR_BOOTSTRAP invalid: stairs below target"
					)
					return false
				end

				local tileInfoSpriteName =
					tileInfo
					and tileInfo:getSpriteName()
					or nil

				local objects =
					square:getObjects()

				if objects then
					for i = 0, objects:size() - 1 do
						local item =
							objects:get(i)

						if item then
							local textureName =
								item:getTextureName()

							local spriteName =
								item:getSpriteName()

							if (
								textureName
								and luautils.stringStarts(
									textureName,
									"vegetation_farming"
								)
							)
							or (
								spriteName
								and luautils.stringStarts(
									spriteName,
									"vegetation_farming"
								)
							) then
								return false
							end

							if (
								textureName
								and textureName == tileInfoSpriteName
							)
							or (
								spriteName
								and spriteName == tileInfoSpriteName
							) then
								return false
							end
						end
					end
				end

				------------------------------------------------
				-- RELEVANT GENERIC VANILLA SAFETY CHECKS
				------------------------------------------------

				if square:has(IsoPropertyType.GARAGE_DOOR) then
					return false
				end

				if square:isVehicleIntersecting() then
					return false
				end

				if buildUtil
				and buildUtil.stairIsBlockingPlacement
				and buildUtil.stairIsBlockingPlacement(
					square,
					true
				) then
					return false
				end

				------------------------------------------------
				-- INTENTIONALLY OMITTED:
				--
				-- BuildRecipeCode.floor.OnIsValid:
				--   square:connectedWithFloor()
				--
				-- The project's preview/support rules already
				-- established this as a legitimate bootstrap floor.
				------------------------------------------------

				cpDebug(
					"[ConstructionPlanner] FLOOR_BOOTSTRAP per-square validation accepted at "
					.. tostring(square:getX())
					.. ","
					.. tostring(square:getY())
					.. ","
					.. tostring(square:getZ())
				)

				return true
			end

			if not cursor.cpBootstrapOriginalHaveMaterial then
				cursor.cpBootstrapOriginalHaveMaterial =
					cursor.haveMaterial
			end

			cursor.haveMaterial = function(self, square)
				local target =
					ConstructionPlanner.bootstrapValidationTarget

				if target
				and square
				and square:getX() == target.x
				and square:getY() == target.y
				and square:getZ() == target.z then

					cpDebug(
						"[ConstructionPlanner] FLOOR_BOOTSTRAP material gate accepted using staged lower-level inputs"
					)

					return true
				end

				if self.cpBootstrapOriginalHaveMaterial then
					return self:cpBootstrapOriginalHaveMaterial(
						square
					)
				end

				return false
			end

			cpDebug(
				"[ConstructionPlanner] FLOOR_BOOTSTRAP proof: player Z"
				.. tostring(player:getZ())
				.. " build target Z"
				.. tostring(tile.z)
				.. " - bypassing vanilla upper-level walk + connected-floor gate"
			)

			cursor.walkTo = function(self, x, y, z)
				cpDebug(
					"[ConstructionPlanner] FLOOR_BOOTSTRAP suppressed vanilla walkTo("
					.. tostring(x) .. ","
					.. tostring(y) .. ","
					.. tostring(z) .. ")"
				)
				return true
			end
		end

		local action =
			ConstructionPlanner.originalTryBuild(
				cursor,
				tile.x,
				tile.y,
				tile.z
			)

		if bootstrap then
			cursor.walkTo =
				savedCursorWalkTo
		end

		----------------------------------------------------
		-- RESTORE VANILLA WALK CONSTRUCTOR IMMEDIATELY.
		----------------------------------------------------

		if originalWalkNew then

			ISWalkToTimedAction.new =
				originalWalkNew
		end

		if not action then

			if bootstrap then
				ConstructionPlanner.bootstrapValidationTarget = nil
				ConstructionPlanner.projectBeforeActualTargetObjectCount = nil
			end

			stopProjectBuild(
				"project build could not start after walking"
			)

			return
		end

		----------------------------------------------------
		-- IMPORTANT:
		-- DO NOT ASSUME THE RETURN VALUE ALONE MEANS THE
		-- TIMED ACTION IS ACTIVE.
		----------------------------------------------------

		local postBuildQueue =
			ISTimedActionQueue.getTimedActionQueue(
				player
			)

		local buildLuaActive =
			postBuildQueue
			and postBuildQueue.queue
			and postBuildQueue.queue[1]
				~= nil

		local postBuildCharacterActions =
			player:getCharacterActions()

		local buildJavaActive =
			postBuildCharacterActions
			and not postBuildCharacterActions:isEmpty()

		if buildLuaActive
		or buildJavaActive then

			cpDebug(
				"[ConstructionPlanner] Vanilla project build action started"
			)

		else

			cpDebug(
				"[ConstructionPlanner] Vanilla project build returned without an active timed action"
			)
		end

		return
	end

	--------------------------------------------------------
	-- WAITING FOR NEXT BUILD?
	--------------------------------------------------------

	if not ConstructionPlanner.projectNextBuildPending then
		return
	end

	--------------------------------------------------------
	-- WAIT FOR PREVIOUS VANILLA BUILD TO FULLY FINISH
	--
	-- BOTH THE LUA QUEUE AND CHARACTER ACTION LIST MUST
	-- BE CLEAR.
	--------------------------------------------------------

	local player =
		getSpecificPlayer(0)

	if not isProjectActionQueueStablyIdle(
		player,
		"nextProjectBuild"
	) then
		return
	end

	ConstructionPlanner.projectNextBuildPending =
		false

	ConstructionPlanner.projectNextBuildDelay =
		nil

	--------------------------------------------------------
	-- NEXT SEGMENT
	--------------------------------------------------------

	if ConstructionPlanner.projectNextSegment then

		local nextSegment =
			ConstructionPlanner.projectNextSegment

		ConstructionPlanner.projectNextSegment =
			nil

		startProjectSegment(
			nextSegment
		)

		return
	end

	--------------------------------------------------------
	-- NEXT BUILD IN CURRENT SEGMENT
	--------------------------------------------------------

	local queue =
		ConstructionPlanner.projectBuildQueue

	local cursor =
		ConstructionPlanner.projectBuildCursor

	local segment =
		ConstructionPlanner.projectBuildSegment

	if not queue
	or not cursor
	or not segment then

		stopProjectBuild(
			"project queue state missing"
		)

		return
	end

	--------------------------------------------------------
	-- NEXT TILE
	--------------------------------------------------------

	local nextTile =
		queue[
			ConstructionPlanner.projectBuildIndex
		]

	if not nextTile then

		stopProjectBuild(
			"next project tile missing"
		)

		return
	end

	cpDebug(
		"[ConstructionPlanner] Project build "
		.. tostring(
			ConstructionPlanner.projectBuildIndex
		)
		.. " / "
		.. tostring(
			#queue
		)
	)

	--------------------------------------------------------
	-- WALK TO NEXT BUILD
	--------------------------------------------------------

	if not queueProjectWalkToTile(
		nextTile
	) then

		stopProjectBuild(
			"could not walk to next project build"
		)

		return
	end
end

------------------------------------------------------------
-- DETECT AN INTERRUPTED PROJECT BUILD
--
-- A MANUAL MOVEMENT / CANCEL / OTHER INTERRUPTION CAN
-- REMOVE THE VANILLA TIMED ACTION WITHOUT TELLING OUR
-- PROJECT STATE THAT CONSTRUCTION STOPPED.
--
-- IF THE PROJECT CLAIMS TO BE BUILDING BUT THERE IS:
--
--   - NO WALK PENDING
--   - NO NEXT BUILD PENDING
--   - NO NEXT SEGMENT HANDOFF
--   - NO LUA TIMED ACTION
--   - NO JAVA CHARACTER ACTION
--
-- FOR SEVERAL TICKS, TREAT THE PROJECT AS PAUSED.
--
-- stopProjectBuild() PRESERVES pendingProject AND
-- remainingTiles, SO CONSTRUCTION CAN LATER RESUME.
------------------------------------------------------------

local function detectInterruptedProjectBuild()

	if not ConstructionPlanner.projectBuilding then

		ConstructionPlanner.projectInterruptIdleTicks =
			0

		return
	end

	--------------------------------------------------------
	-- THESE ARE LEGITIMATE PROJECT TRANSITIONS
	--------------------------------------------------------

	if ConstructionPlanner.projectBuildWalkPending
	or ConstructionPlanner.projectNextBuildPending
	or ConstructionPlanner.projectNextSegment then

		ConstructionPlanner.projectInterruptIdleTicks =
			0

		return
	end

	local player =
		getSpecificPlayer(0)

	if not player then
		return
	end

	--------------------------------------------------------
	-- LUA TIMED-ACTION QUEUE
	--------------------------------------------------------

	local actionQueue =
		ISTimedActionQueue.getTimedActionQueue(
			player
		)

	local luaActive =
		actionQueue
		and actionQueue.queue
		and actionQueue.queue[1]
			~= nil

	--------------------------------------------------------
	-- JAVA CHARACTER ACTIONS
	--------------------------------------------------------

	local characterActions =
		player:getCharacterActions()

	local javaActive =
		characterActions
		and not characterActions:isEmpty()

	--------------------------------------------------------
	-- SOMETHING IS STILL ACTUALLY RUNNING
	--------------------------------------------------------

	if luaActive
	or javaActive then

		ConstructionPlanner.projectInterruptIdleTicks =
			0

		return
	end

	--------------------------------------------------------
	-- PROJECT CLAIMS TO BE BUILDING, BUT NOTHING EXISTS.
	--
	-- REQUIRE A FEW CONSECUTIVE TICKS SO WE DON'T MISTAKE
	-- A NORMAL VANILLA ACTION TRANSITION FOR INTERRUPTION.
	--------------------------------------------------------

	ConstructionPlanner.projectInterruptIdleTicks =
		(
			ConstructionPlanner.projectInterruptIdleTicks
			or 0
		)
		+ 1

	if ConstructionPlanner.projectInterruptIdleTicks
	< 10 then

		return
	end

	ConstructionPlanner.projectInterruptIdleTicks =
		0

	cpDebug(
		"[ConstructionPlanner] Project construction interrupted - project paused"
	)

	stopProjectBuild(
		"construction interrupted"
	)
end

------------------------------------------------------------
-- INSTALL AFTER CURSORWATCHER
------------------------------------------------------------

Events.OnTick.Add(
	ensureProjectPerformHook
)

Events.OnTick.Add(
	updateProjectBuilder
)

Events.OnTick.Add(
	detectInterruptedProjectBuild
)