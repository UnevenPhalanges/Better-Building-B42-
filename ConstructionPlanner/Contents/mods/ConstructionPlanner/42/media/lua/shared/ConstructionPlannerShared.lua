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

ConstructionPlanner.plannerEnabled = false
ConstructionPlanner.currentCursor = nil
ConstructionPlanner.currentCursorName = nil

ConstructionPlanner.selecting = false
ConstructionPlanner.startTile = nil
ConstructionPlanner.endTile = nil

ConstructionPlanner.wasBuildButtonDown = false
ConstructionPlanner.noCursorTicks = 0

ConstructionPlanner.AUTO_EXIT_TICKS = 180

ConstructionPlanner.hoverTile = nil
ConstructionPlanner.selectedTiles = nil

ConstructionPlanner.buildQueue = nil
ConstructionPlanner.buildIndex = 0
ConstructionPlanner.building = false

ConstructionPlanner.buildLogicTemplate = nil

ConstructionPlanner.modDataTemplate = nil

ConstructionPlanner.nextBuildPending = false
ConstructionPlanner.nextBuildDelay = 0

------------------------------------------------------------
-- SHARED CONSTRUCTION PLANNER WALK
------------------------------------------------------------

local function ensureConstructionPlannerWalkClass()
	if ISConstructionPlannerWalkToTimedAction then
		return true
	end

	if not ISWalkToTimedAction
	or not ISWalkToTimedAction.derive then

		return false
	end

	ISConstructionPlannerWalkToTimedAction =
		ISWalkToTimedAction:derive(
			"ISConstructionPlannerWalkToTimedAction"
		)

	--------------------------------------------------------
	-- ALLOW CONSTRUCTION PLANNER WALKING AT SPEED 3
	--------------------------------------------------------

	function ISConstructionPlannerWalkToTimedAction:isValid()
		if self.character:getVehicle() then
			return false
		end

		return getGameSpeed() <= 3
	end

	--------------------------------------------------------
	-- CREATE
	--------------------------------------------------------

	function ISConstructionPlannerWalkToTimedAction:new(
		character,
		location,
		additionalTest,
		additionalContext
	)
		local o =
			ISWalkToTimedAction.new(
				self,
				character,
				location,
				additionalTest,
				additionalContext
			)

		o.constructionPlannerWalk =
			true

		return o
	end
	cpDebug(
		"[ConstructionPlanner] CP Speed-3 walk class installed"
	)

	return true
end

------------------------------------------------------------
-- CREATE ONE CP WALK ACTION
------------------------------------------------------------

function ConstructionPlanner.createWalkAction(
	player,
	square
)
	if not player
	or not square then

		return nil
	end

	if not ensureConstructionPlannerWalkClass() then

		cpDebug(
			"[ConstructionPlanner] Could not create CP walk - ISWalkToTimedAction unavailable"
		)

		return nil
	end

	local action =
		ISConstructionPlannerWalkToTimedAction:new(
			player,
			square
		)

	if not action then

		cpDebug(
			"[ConstructionPlanner] Could not create CP walk action"
		)

		return nil
	end

	return action
end

------------------------------------------------------------
-- CREATE + QUEUE ONE CP WALK
------------------------------------------------------------

function ConstructionPlanner.queueWalkAction(
	player,
	square
)
	local action =
		ConstructionPlanner.createWalkAction(
			player,
			square
		)

	if not action then
		return nil
	end

	ISTimedActionQueue.add(
		action
	)

	return action
end
