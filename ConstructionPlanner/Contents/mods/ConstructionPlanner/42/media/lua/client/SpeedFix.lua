-- Release logging helper.
local function cpDebug(...)
	if ConstructionPlanner
	and ConstructionPlanner.DEBUG then
		print(...)
	end
end

------------------------------------------------------------
-- CONSTRUCTION PLANNER SPEED-3 CONTINUITY
------------------------------------------------------------

local CP_SPEED_CONTINUITY =
	{
		wantsSpeed3 =
			false,

		lastSpeed =
			nil,

		-- Keep CP considered "active" briefly across intentional
		-- empty-queue handoffs between distribution/build phases.
		graceTicks =
			0
	}

------------------------------------------------------------
-- IS CP CURRENTLY RUNNING?
------------------------------------------------------------

local function isConstructionPlannerActive()

	if not ConstructionPlanner then
		return false
	end

	if ConstructionPlanner.projectBuilding then
		return true
	end

	if ConstructionPlanner.projectBuildWalkPending then
		return true
	end

	if ConstructionPlanner.projectNextBuildPending then
		return true
	end

	if ConstructionPlanner.pendingDeliveryPlan then
		return true
	end

	if ConstructionPlanner.pendingNextDistribution then
		return true
	end

	if ConstructionPlanner.virtualDeliveryActive then
		return true
	end

	if ConstructionPlanner.virtualHaul
	and ConstructionPlanner.virtualHaul.items
	and #ConstructionPlanner.virtualHaul.items > 0 then

		return true
	end

	if ConstructionPlanner.toolAcquisitionActive then
		return true
	end

	if ConstructionPlanner.toolPickupActive then
		return true
	end

	if ConstructionPlanner.toolReturnActive then
		return true
	end

	--------------------------------------------------------
	-- MULTI-LEVEL PROJECT PHASE HANDOFFS
	--
	-- These are deliberate queue-idle transitions.  Without
	-- tracking them, SpeedFix can believe CP has stopped for
	-- a tick and clear wantsSpeed3 before the next phase starts.
	--------------------------------------------------------

	if ConstructionPlanner.pendingPhaseDistributionStart then
		return true
	end

	if ConstructionPlanner.pendingPhaseBuildStart then
		return true
	end

	--------------------------------------------------------
	-- DISMANTLE WORKFLOW
	--------------------------------------------------------

	if ConstructionPlanner.dismantleFetchingTools then
		return true
	end

	if ConstructionPlanner.dismantleRunning then
		return true
	end

	if ConstructionPlanner.dismantleReturningTools then
		return true
	end

	--------------------------------------------------------
	-- DESTROY WORKFLOW
	--------------------------------------------------------

	if ConstructionPlanner.destroyFetchingTool then
		return true
	end

	if ConstructionPlanner.destroyRunning then
		return true
	end

	if ConstructionPlanner.destroyReturningTool then
		return true
	end

	return false
end

------------------------------------------------------------
-- SPEED CONTINUITY
------------------------------------------------------------

local function updateConstructionPlannerSpeed()

	local rawActive =
		isConstructionPlannerActive()

	--------------------------------------------------------
	-- SHORT CONTINUITY GRACE
	--
	-- Vanilla often empties the action queue for a tick or two
	-- between CP actions.  Treat that as one continuous workflow
	-- instead of ending Speed-3 continuity immediately.
	--------------------------------------------------------

	if rawActive then
		CP_SPEED_CONTINUITY.graceTicks =
			12
	elseif CP_SPEED_CONTINUITY.graceTicks > 0 then
		CP_SPEED_CONTINUITY.graceTicks =
			CP_SPEED_CONTINUITY.graceTicks - 1
	end

	local active =
		rawActive
		or CP_SPEED_CONTINUITY.graceTicks > 0

	local speed =
		getGameSpeed()

	--------------------------------------------------------
	-- PROJECT IS REALLY NOT ACTIVE
	--------------------------------------------------------

	if not active then

		CP_SPEED_CONTINUITY.wantsSpeed3 =
			false

		CP_SPEED_CONTINUITY.lastSpeed =
			speed

		return
	end

	--------------------------------------------------------
	-- USER HAS ENTERED SPEED 3 DURING THIS CP WORKFLOW
	--------------------------------------------------------

	if speed == 3 then

		CP_SPEED_CONTINUITY.wantsSpeed3 =
			true

		CP_SPEED_CONTINUITY.lastSpeed =
			speed

		return
	end

	--------------------------------------------------------
	-- ENGINE DROPPED SPEED 3 -> SPEED 1
	--------------------------------------------------------

	if CP_SPEED_CONTINUITY.wantsSpeed3
	and CP_SPEED_CONTINUITY.lastSpeed == 3
	and speed == 1 then

		local player =
			getSpecificPlayer(0)

		----------------------------------------------------
		-- DO NOT FIGHT A REAL PLAYER INTERRUPTION
		----------------------------------------------------

		if player
		and not player:pressedMovement(false)
		and not player:pressedCancelAction() then

			if UIManager
			and UIManager.getSpeedControls
			and UIManager.getSpeedControls() then

				cpDebug(
					"[ConstructionPlanner] Restoring Speed 3 after CP action transition"
				)

				UIManager.getSpeedControls():SetCurrentGameSpeed(
					3
				)

				------------------------------------------------
				-- MATCH VANILLA SPEED-3 BEHAVIOR.
				--
				-- SetCurrentGameSpeed() restores the speed-control
				-- state, but the actual GameTime multiplier may
				-- still be 1 during the CP action transition.
				------------------------------------------------

				if getGameTime() then

					getGameTime():setMultiplier(
						20
					)
				end

				speed =
					3
			end
		end
	end

	CP_SPEED_CONTINUITY.lastSpeed =
		speed
end

Events.OnTick.Add(
	updateConstructionPlannerSpeed
)