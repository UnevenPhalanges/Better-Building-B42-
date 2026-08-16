------------------------------------------------------------
-- CONSTRUCTION PLANNER KEYBINDS
------------------------------------------------------------

local function addConstructionPlannerKeybinds()

	if not keyBinding then
		return
	end

	--------------------------------------------------------
	-- PREVENT DUPLICATE REGISTRATION
	--------------------------------------------------------

	if ConstructionPlanner
	and ConstructionPlanner.keybindsRegistered then
		return
	end

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

	--------------------------------------------------------
	-- SECTION HEADER
	--------------------------------------------------------

	local bind =
		{}

	bind.value =
		"[Construction Planner]"

	table.insert(
		keyBinding,
		bind
	)

	--------------------------------------------------------
	-- TOGGLE PROJECT PANEL
	--------------------------------------------------------

	bind =
		{}

	bind.value =
		"Toggle Construction Planner"

	bind.key =
		Keyboard.KEY_LBRACKET

	table.insert(
		keyBinding,
		bind
	)

	ConstructionPlanner.keybindsRegistered =
		true

	cpDebug(
		"[ConstructionPlanner] Keybinds registered"
	)
end

addConstructionPlannerKeybinds()