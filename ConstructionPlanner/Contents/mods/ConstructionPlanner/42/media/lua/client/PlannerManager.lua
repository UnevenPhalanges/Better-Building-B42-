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
-- RESET ACTIVE SELECTION ONLY
--
-- This does NOT delete pending projects or saved previews.
------------------------------------------------------------

local function resetSelection()
	ConstructionPlanner.selecting = false
	ConstructionPlanner.startTile = nil
	ConstructionPlanner.endTile = nil
	ConstructionPlanner.selectedTiles = nil
	ConstructionPlanner.wasBuildButtonDown = false
end

------------------------------------------------------------
-- DISABLE DRAGBUILDER
------------------------------------------------------------

local function disableDragBuilder()
	resetSelection()

	ConstructionPlanner.plannerEnabled = false

	ConstructionPlanner.currentCursor = nil
	ConstructionPlanner.currentCursorName = nil
	ConstructionPlanner.hoverTile = nil

	ConstructionPlanner.noCursorTicks = 0

	cpDebug(
		"[ConstructionPlanner] DragBuilder disabled"
	)
end

------------------------------------------------------------
-- ENABLE DRAGBUILDER
------------------------------------------------------------

local function enableDragBuilder(mode)
	ConstructionPlanner.plannerEnabled = true
	ConstructionPlanner.noCursorTicks = 0

	cpDebug(
		"[ConstructionPlanner] DragBuilder enabled - "
		.. string.upper(mode)
	)
end

------------------------------------------------------------
-- APPLY CURRENT MODE
------------------------------------------------------------

function ConstructionPlanner.applyMode()
	local mode =
		ConstructionPlanner.getMode
		and ConstructionPlanner.getMode()
		or "plan"

	if mode == "off" then
		disableDragBuilder()
		return
	end

	enableDragBuilder(mode)
end

------------------------------------------------------------
-- KEEP MODE STATE SYNCHRONIZED
------------------------------------------------------------

local lastMode = nil

local function update()
	local mode =
		ConstructionPlanner.getMode
		and ConstructionPlanner.getMode()
		or "plan"

	if mode ~= lastMode then
		lastMode = mode

		ConstructionPlanner.applyMode()
	end
end

Events.OnTick.Add(update)