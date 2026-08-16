-- Release logging helper.
local function cpDebug(...)
	if ConstructionPlanner
	and ConstructionPlanner.DEBUG then
		print(...)
	end
end

local function getBuildCursor()
	local player = getSpecificPlayer(0)

	if not player then
		return nil
	end

	local cursor = getCell():getDrag(player:getPlayerNum())

	if not cursor or cursor.Type ~= "ISBuildIsoEntity" then
		return nil
	end

	return cursor
end


local function stopBuildQueue(reason)
	if reason then
		cpDebug(
			"[ConstructionPlanner] Build queue stopped - "
			.. tostring(reason)
		)
	end

	ConstructionPlanner.buildQueue = nil
	ConstructionPlanner.buildIndex = 0
	ConstructionPlanner.building = false
	ConstructionPlanner.queueNSprite = nil
end


local function copySelectedTiles(tiles)
	local result = {}

	for i, tile in ipairs(tiles) do
		result[i] = {
			x = tile.x,
			y = tile.y,
			z = tile.z
		}
	end

	return result
end


local function ensureRotateMouseHook()
	if ConstructionPlanner.rotateMouseHooked then
		return true
	end

	if not ISBuildIsoEntity or not ISBuildIsoEntity.rotateMouse then
		return false
	end

	ConstructionPlanner.originalRotateMouse = ISBuildIsoEntity.rotateMouse

	ISBuildIsoEntity.rotateMouse = function(self, x, y)
		if ConstructionPlanner.plannerEnabled then
			local z = 0

			if ConstructionPlanner.startTile then
				z = ConstructionPlanner.startTile.z
			elseif self.square then
				local baseZ = self.square:getZ()

				z = ConstructionPlanner.getPlanTargetZ
					and ConstructionPlanner.getPlanTargetZ(baseZ)
					or baseZ
			end

			ConstructionPlanner.hoverTile = {
				x = x,
				y = y,
				z = z
			}

			-- Only suppress vanilla mouse rotation while
			-- an actual planner drag is happening.
			if ConstructionPlanner.selecting then
				return
			end
		end

		return ConstructionPlanner.originalRotateMouse(
			self,
			x,
			y
		)
	end

	ConstructionPlanner.rotateMouseHooked = true

	cpDebug("[ConstructionPlanner] rotateMouse hook installed")

	return true
end


local function ensureRenderHook()
	if ConstructionPlanner.renderHooked then
		return true
	end

	if not ISBuildIsoEntity
	or not ISBuildIsoEntity.render then

		return false
	end

	ConstructionPlanner.originalRender =
		ISBuildIsoEntity.render

	--------------------------------------------------------
	-- RENDER A PLANNED PREVIEW WITHOUT VANILLA'S INVALID
	-- RED TINT.  Elevated planning deliberately allows a
	-- future world state, so vanilla support validation is
	-- not meaningful for preview colour.
	--------------------------------------------------------

	ConstructionPlanner.renderPlannerPreview = function(
		cursor,
		x,
		y,
		z,
		renderSquare
	)
		if not cursor
		or not renderSquare then
			return
		end

		local oldBlockBuild =
			cursor.blockBuild

		local oldIsValid =
			cursor.isValid

		cursor.blockBuild =
			false

		cursor.isValid = function()
			return true
		end

		ConstructionPlanner.originalRender(
			cursor,
			x,
			y,
			z,
			renderSquare
		)

		cursor.blockBuild =
			oldBlockBuild

		cursor.isValid =
			oldIsValid
	end

	ISBuildIsoEntity.render = function(
		self,
		x,
		y,
		z,
		square
	)

		----------------------------------------------------
		-- CURRENT LIVE DRAG PREVIEW
		----------------------------------------------------

		if ConstructionPlanner.plannerEnabled
		and ConstructionPlanner.selecting
		and ConstructionPlanner.startTile
		and ConstructionPlanner.hoverTile
		and ConstructionPlanner.getSelectionTiles then

			local tiles =
				ConstructionPlanner.getSelectionTiles(
					ConstructionPlanner.startTile,
					ConstructionPlanner.hoverTile
				)

			for _, tile in ipairs(
				tiles
			) do

				local tileSquare =
					getCell():getGridSquare(
						tile.x,
						tile.y,
						tile.z
					)

				----------------------------------------------------
				-- Empty future Z-levels may not have a usable floor
				-- square yet. The renderer still gets the planned Z;
				-- use the live cursor square only as a render context
				-- fallback.
				----------------------------------------------------

				local renderSquare =
					tileSquare
					or self.square

				if renderSquare then

					ConstructionPlanner.renderPlannerPreview(
						self,
						tile.x,
						tile.y,
						tile.z,
						renderSquare
					)
				end
			end

			return
		end

		----------------------------------------------------
		-- ELEVATED SINGLE-TILE HOVER BEFORE DRAG STARTS
		----------------------------------------------------

		local page =
			ConstructionPlanner.projectPanelPage
			or "plan"

		local heightOffset =
			ConstructionPlanner.getPlanHeightOffset
			and ConstructionPlanner.getPlanHeightOffset()
			or 0

		if ConstructionPlanner.plannerEnabled
		and page == "plan"
		and heightOffset > 0
		and not ConstructionPlanner.selecting then

			local baseZ =
				square
				and square:getZ()
				or z

			local targetZ =
				ConstructionPlanner.getPlanTargetZ
				and ConstructionPlanner.getPlanTargetZ(baseZ)
				or baseZ

			local targetSquare =
				getCell():getGridSquare(
					x,
					y,
					targetZ
				)

			local renderSquare =
				targetSquare
				or square
				or self.square

			if renderSquare then
				ConstructionPlanner.renderPlannerPreview(
					self,
					x,
					y,
					targetZ,
					renderSquare
				)
			end

			return
		end

		----------------------------------------------------
		-- NORMAL CURRENT VANILLA CURSOR
		----------------------------------------------------

		return ConstructionPlanner.originalRender(
			self,
			x,
			y,
			z,
			square
		)
	end

	ConstructionPlanner.renderHooked =
		true

	cpDebug(
		"[ConstructionPlanner] render hook installed"
	)

	return true
end


local function ensureTryBuildHook()
	if ConstructionPlanner.tryBuildHooked then
		return true
	end

	if not ISBuildingObject or not ISBuildingObject.tryBuild then
		return false
	end

	ConstructionPlanner.originalTryBuild = ISBuildingObject.tryBuild

	ISBuildingObject.tryBuild = function(self, x, y, z)
		if ConstructionPlanner.plannerEnabled
		and self.Type == "ISBuildIsoEntity" then

			local tiles = ConstructionPlanner.selectedTiles

			if not tiles or #tiles == 0 then
				cpDebug("[ConstructionPlanner] No selected tiles to plan")
				return nil
			end

			------------------------------------------------
			-- FINALIZE THE PENDING PROJECT
			------------------------------------------------

			local project = ConstructionPlanner.pendingProject

			if not project then
				project = {
					tiles = copySelectedTiles(tiles),
					remainingTiles = copySelectedTiles(tiles),
					requiredMaterials = {}
				}

				ConstructionPlanner.pendingProject = project
			end

			project.tiles = copySelectedTiles(tiles)
			project.remainingTiles = copySelectedTiles(tiles)

			project.status = "waitingForSupplies"

			project.buildableName = tostring(self.name)
			project.nSprite = self.nSprite

			-- Save the cursor for the current prototype.
			-- Later we can replace this with enough recipe data
			-- to recreate the build independently.
			project.buildCursor = self

			------------------------------------------------
			-- MAKE SURE NO BUILD QUEUE STARTS
			------------------------------------------------

			ConstructionPlanner.buildQueue = nil
			ConstructionPlanner.buildIndex = nil
			ConstructionPlanner.building = false

			ConstructionPlanner.nextBuildPending = false
			ConstructionPlanner.nextBuildDelay = nil

			ConstructionPlanner.queueNSprite = nil

			------------------------------------------------
			-- KEEP THE GHOST PLAN VISIBLE
			------------------------------------------------

			ConstructionPlanner.selectedTiles =
				project.remainingTiles

			cpDebug(
				"[ConstructionPlanner] Build plan finalized: "
				.. tostring(#project.remainingTiles)
				.. " tile(s)"
			)

			cpDebug(
				"[ConstructionPlanner] Build plan waiting for supplies"
			)

			-- IMPORTANT:
			-- Do NOT call vanilla tryBuild here.
			-- Nothing gets physically built yet.
			return nil
		end

		return ConstructionPlanner.originalTryBuild(
			self,
			x,
			y,
			z
		)
	end

	ConstructionPlanner.tryBuildHooked = true

	cpDebug("[ConstructionPlanner] tryBuild hook installed")

	return true
end


local function ensureBuildPerformHook()
	if ConstructionPlanner.buildPerformHooked then
		return true
	end

	if not ISBuildAction or not ISBuildAction.perform then
		return false
	end

	ConstructionPlanner.originalBuildPerform = ISBuildAction.perform

	ISBuildAction.perform = function(self)
		ConstructionPlanner.originalBuildPerform(self)

		if not ConstructionPlanner.building then
			return
		end

		if not ConstructionPlanner.buildQueue then
			return
		end

		if not ConstructionPlanner.plannerEnabled then
			stopBuildQueue("Planner Mode is off")
			return
		end

		ConstructionPlanner.buildIndex =
			ConstructionPlanner.buildIndex + 1

		if ConstructionPlanner.buildIndex >
		#ConstructionPlanner.buildQueue then

			cpDebug("[ConstructionPlanner] Build queue complete")
			stopBuildQueue()

			return
		end

		-- Do NOT start the next build here.
		-- Give vanilla time to refresh BuildLogic and containers.
		ConstructionPlanner.nextBuildPending = true
		ConstructionPlanner.nextBuildDelay = 2

		cpDebug(
			"[ConstructionPlanner] Next queued build pending "
			.. tostring(ConstructionPlanner.buildIndex)
			.. " / "
			.. tostring(#ConstructionPlanner.buildQueue)
		)
	end

	ConstructionPlanner.buildPerformHooked = true

	cpDebug("[ConstructionPlanner] ISBuildAction.perform hook installed")

	return true
end

local function ensurePlanBuildMenuHook()
	if ConstructionPlanner.planBuildMenuHooked then
		return true
	end

	if not ISWidgetBuildControl
	or not ISWidgetBuildControl.prerender then
		return false
	end

	if not ISBuildPanel
	or not ISBuildPanel.createBuildIsoEntity then
		return false
	end

	--------------------------------------------------------
	-- SAVE VANILLA FUNCTIONS
	--------------------------------------------------------

	ConstructionPlanner.originalBuildControlPrerender =
		ISWidgetBuildControl.prerender

	ConstructionPlanner.originalCreateBuildIsoEntity =
		ISBuildPanel.createBuildIsoEntity

	--------------------------------------------------------
	-- GATE 1:
	-- KEEP BUILD BUTTON ENABLED IN PLAN MODE
	--------------------------------------------------------

ISWidgetBuildControl.prerender = function(
	self
)
	--------------------------------------------------------
	-- LET VANILLA DECIDE FIRST
	--------------------------------------------------------

	ConstructionPlanner.originalBuildControlPrerender(
		self
	)

	local mode =
		ConstructionPlanner.getMode
		and ConstructionPlanner.getMode()
		or "plan"

	if mode ~= "plan"
	and mode ~= "quick" then
		return
	end

	if not self.buttonCraft then
		return
	end

	local logic =
		self.logic

	if not logic then
		return
	end

	--------------------------------------------------------
	-- NEVER OVERRIDE AN ACTIVE CRAFT / BUILD ACTION
	--------------------------------------------------------

	if logic.isCraftActionInProgress
	and logic:isCraftActionInProgress() then

		self.buttonCraft.enable =
			false

		return
	end

	--------------------------------------------------------
	-- GET CURRENT RECIPE
	--------------------------------------------------------

	local recipe =
		nil

	if logic.getRecipe then
		recipe =
			logic:getRecipe()
	end

	if not recipe
	and self.craftRecipe then

		recipe =
			self.craftRecipe
	end

	--------------------------------------------------------
-- DIRECTLY CHECK THE RECIPE'S REQUIRED SKILLS
--------------------------------------------------------

if recipe
and recipe.getRequiredSkillCount
and recipe.getRequiredSkill then

	local player =
		getSpecificPlayer(0)

	if not player then
		return
	end

	local skillCount =
		recipe:getRequiredSkillCount()

	for i = 0, skillCount - 1 do

		local requirement =
			recipe:getRequiredSkill(i)

		if requirement then

			local perk =
				requirement:getPerk()

			local requiredLevel =
				requirement:getLevel()

			if perk
			and requiredLevel then

				local playerLevel =
					player:getPerkLevel(
						perk
					)

				if playerLevel < requiredLevel then

					------------------------------------------------
					-- PLAYER DOES NOT MEET THIS BUILD'S SKILL
					-- REQUIREMENT.
					--
					-- LEAVE VANILLA'S BUILD BUTTON DISABLED.
					------------------------------------------------

					return
				end
			end
		end
	end
end

	--------------------------------------------------------
	-- KEEP EXISTING BUILDLOGIC SKILL CHECK AS A SECONDARY
	-- SAFETY CHECK.
	--------------------------------------------------------

	if logic.characterHasRequiredSkills
	and not logic:characterHasRequiredSkills() then

		return
	end

	--------------------------------------------------------
	-- PRESERVE RECIPE KNOWLEDGE
	--------------------------------------------------------

	if logic.isRecipeKnown
	and not logic:isRecipeKnown() then

		return
	end

	--------------------------------------------------------
	-- PRESERVE LIGHT RESTRICTIONS
	--------------------------------------------------------

	if logic.isTooDarkToRead
	and logic:isTooDarkToRead() then

		return
	end

	--------------------------------------------------------
	-- PRESERVE WORKSTATION / RANGE REQUIREMENTS
	--------------------------------------------------------

	if logic.isInRangeOfWorkbench
	and not logic:isInRangeOfWorkbench() then

		return
	end

	--------------------------------------------------------
	-- PRESERVE PLAYER MOVEMENT RESTRICTION
	--------------------------------------------------------

	if logic.isPlayerMoving
	and logic:isPlayerMoving() then

		return
	end

	--------------------------------------------------------
	-- PLAYER PASSED ALL NON-MATERIAL REQUIREMENTS.
	--
	-- NOW AND ONLY NOW DO WE OVERRIDE VANILLA'S MISSING
	-- MATERIAL REQUIREMENT FOR PLAN / QUICK MODE.
	--------------------------------------------------------

	self.buttonCraft.enable =
		true
end

	--------------------------------------------------------
	-- GATE 2:
	-- DON'T BLOCK THE CREATED BUILD CURSOR IN PLAN MODE
	--------------------------------------------------------

	ISBuildPanel.createBuildIsoEntity = function(
		self,
		dontSetDrag
	)

		ConstructionPlanner.originalCreateBuildIsoEntity(
			self,
			dontSetDrag
		)

		local mode =
			ConstructionPlanner.getMode
			and ConstructionPlanner.getMode()
			or "plan"

		if mode ~= "plan"
			and mode ~= "quick" then
			return
		end

		local buildEntity =
			self.buildEntity

		if not buildEntity then
			return
		end

		if buildEntity.Type ~= "ISBuildIsoEntity" then
			return
		end

		----------------------------------------------------
		-- THIS ONLY ALLOWS THE PLANNING CURSOR.
		-- ACTUAL PROJECT BUILDS STILL USE REAL VANILLA
		-- MATERIAL VALIDATION AND CONSUMPTION.
		----------------------------------------------------

		buildEntity.blockBuild =
			false
	end

	ConstructionPlanner.planBuildMenuHooked =
		true

	cpDebug(
		"[ConstructionPlanner] PLAN build-menu hook installed"
	)

	return true
end

local function isPlayerActionQueueIdle()
	local player =
		getSpecificPlayer(0)

	if not player then
		return false
	end

	local actionQueue =
		ISTimedActionQueue.getTimedActionQueue(
			player
		)

	if actionQueue
	and actionQueue.queue
	and actionQueue.queue[1] then

		return false
	end

	return true
end

local stableIdleTicks = {}

local function isPlayerActionQueueStablyIdle(key)
	if not isPlayerActionQueueIdle() then
		stableIdleTicks[key] = 0
		return false
	end

	stableIdleTicks[key] = (stableIdleTicks[key] or 0) + 1

	if stableIdleTicks[key] < 2 then
		return false
	end

	stableIdleTicks[key] = 0
	return true
end

local function update()
	ensureRotateMouseHook()
	ensureRenderHook()
	ensureTryBuildHook()
	ensureBuildPerformHook()
	ensurePlanBuildMenuHook()

		if ConstructionPlanner.pendingQuickDistribution then

		local project =
			ConstructionPlanner.pendingProject

		----------------------------------------------------
		-- WAIT FOR THE QUICK PROJECT TO ACTUALLY EXIST.
		----------------------------------------------------

		if not project
		or not project.segments
		or #project.segments == 0 then

			return
		end

		----------------------------------------------------
		-- MAKE SURE MATERIAL DATA EXISTS.
		----------------------------------------------------

		if ConstructionPlanner.calculateProjectMaterials then

			ConstructionPlanner.calculateProjectMaterials()
		end

		----------------------------------------------------
		-- WAIT FOR THE PLAYER ACTION QUEUE TO BE IDLE.
		----------------------------------------------------

		if not isPlayerActionQueueStablyIdle("quickDistribution") then
			return
		end

		ConstructionPlanner.pendingQuickDistribution =
			false

		ConstructionPlanner.pendingQuickDistributionWait =
			false

		cpDebug(
			"[ConstructionPlanner] Quick Build - "
			.. "starting distribution"
		)

		if ConstructionPlanner.startDistributionPickup then

			ConstructionPlanner.startDistributionPickup()

		else

			cpDebug(
				"[ConstructionPlanner] Quick Build failed - "
				.. "distribution manager not loaded"
			)
		end

		return
	end

		if ConstructionPlanner.nextBuildPending then

		----------------------------------------------------
		-- WAIT FOR THE PREVIOUS VANILLA BUILD ACTION
		-- TO ACTUALLY FINISH.
		----------------------------------------------------

		if not isPlayerActionQueueStablyIdle("nextQueuedBuild") then
			return
		end

		local cursor =
			getBuildCursor()

		----------------------------------------------------
		-- VANILLA MAY STILL BE REFRESHING ITS BUILD CURSOR.
		-- JUST WAIT AND TRY AGAIN NEXT UPDATE.
		----------------------------------------------------

		if not cursor then
			return
		end

		ConstructionPlanner.currentCursor =
			cursor

		ConstructionPlanner.currentCursorName =
			tostring(
				cursor.name
			)

		if ConstructionPlanner.queueNSprite then

			cursor.nSprite =
				ConstructionPlanner.queueNSprite

			cursor.nSpriteCache =
				-1

			cursor:getSprite()
		end

		----------------------------------------------------
		-- SAME THING FOR BUILD AVAILABILITY.
		-- DON'T ABORT THE QUEUE JUST BECAUSE VANILLA
		-- ISN'T READY ON THIS PARTICULAR UPDATE.
		----------------------------------------------------

		if cursor.blockBuild then
			return
		end

		local tile =
			ConstructionPlanner.buildQueue[
				ConstructionPlanner.buildIndex
			]

		if not tile then

			stopBuildQueue(
				"queued build tile missing"
			)

			return
		end

		ConstructionPlanner.nextBuildPending =
			false

		ConstructionPlanner.nextBuildDelay =
			nil

		cpDebug(
			"[ConstructionPlanner] Starting queued build "
			.. tostring(
				ConstructionPlanner.buildIndex
			)
			.. " / "
			.. tostring(
				#ConstructionPlanner.buildQueue
			)
		)

		ConstructionPlanner.originalTryBuild(
			cursor,
			tile.x,
			tile.y,
			tile.z
		)

		return
	end

	if not ConstructionPlanner.plannerEnabled then
		ConstructionPlanner.currentCursor = nil
		ConstructionPlanner.currentCursorName = nil
		ConstructionPlanner.hoverTile = nil
		return
	end

	local cursor = getBuildCursor()

	if not cursor then
		ConstructionPlanner.currentCursor = nil
		ConstructionPlanner.currentCursorName = nil
		ConstructionPlanner.hoverTile = nil
		return
	end

	if ConstructionPlanner.previewRemovalMode then

		ConstructionPlanner.previewRemovalMode =
			false

		if ConstructionPlanner.clearRemoveSelection then

			ConstructionPlanner.clearRemoveSelection()
		end

		cpDebug(
			"[ConstructionPlanner] Remove mode disabled - build object selected"
		)
	end

	ConstructionPlanner.currentCursor = cursor

	local cursorName = tostring(cursor.name)

	if cursorName ~= ConstructionPlanner.currentCursorName then
		ConstructionPlanner.currentCursorName = cursorName

		cpDebug(
			"[ConstructionPlanner] Current buildable: "
			.. cursorName
		)
	end
end

Events.OnTick.Add(update)

local function renderPendingProject()
	local project =
		ConstructionPlanner.pendingProject

	if not project
	or not project.segments
	or #project.segments == 0 then

		return
	end

	for _, segment in ipairs(
		project.segments
	) do

		if segment.buildCursor
		and segment.remainingTiles then

			local cursor =
				segment.buildCursor

			------------------------------------------------
			-- SAVE LIVE CURSOR STATE
			------------------------------------------------

			local oldNSprite =
				cursor.nSprite

			local oldNorth =
				cursor.north

			local oldBlockBuild =
				cursor.blockBuild

			------------------------------------------------
			-- LOCK THIS SEGMENT TO SAVED WALL DIRECTION
			------------------------------------------------

			if segment.north ~= nil then

				cursor.north =
					segment.north
			end

			------------------------------------------------
			-- LOCK THIS SEGMENT TO SAVED SPRITE ROTATION
			------------------------------------------------

			if segment.nSprite ~= nil then

				cursor.nSprite =
					segment.nSprite

				cursor.nSpriteCache =
					-1

				if cursor.getSprite then

					cursor:getSprite()
				end
			end

			------------------------------------------------
			-- DRAW THIS SAVED SEGMENT
			--
			-- Normal saved previews stay valid-looking.
			-- If Remove mode is currently targeting this exact
			-- x/y/z preview, temporarily render it as blocked so
			-- vanilla gives it the bright red removal tint.
			--
			-- This works on future Z levels even when there is no
			-- real floor object there to highlight.
			------------------------------------------------

			for _, tile in ipairs(
				segment.remainingTiles
			) do

				local targetedForRemoval =
					ConstructionPlanner.previewRemovalMode
					and ConstructionPlanner.isPreviewTargetedForRemoval
					and ConstructionPlanner.isPreviewTargetedForRemoval(
						tile.x,
						tile.y,
						tile.z
					)
					or false

				cursor.blockBuild =
					targetedForRemoval == true

				local tileSquare =
					getCell():getGridSquare(
						tile.x,
						tile.y,
						tile.z
					)

				local renderSquare =
					tileSquare
					or getCell():getGridSquare(
						tile.x,
						tile.y,
						math.max(0, tile.z - 1)
					)

				if renderSquare then

					ConstructionPlanner.renderPlannerPreview(
						cursor,
						tile.x,
						tile.y,
						tile.z,
						renderSquare
					)
				end
			end

			------------------------------------------------
			-- RESTORE LIVE CURSOR STATE
			------------------------------------------------

			cursor.north =
				oldNorth

			cursor.nSprite =
				oldNSprite

			cursor.blockBuild =
				oldBlockBuild

			cursor.nSpriteCache =
				-1

			if cursor.getSprite then

				cursor:getSprite()
			end
		end
	end
end

Events.OnPostRender.Add(renderPendingProject)

cpDebug("[ConstructionPlanner] persistent project render installed")