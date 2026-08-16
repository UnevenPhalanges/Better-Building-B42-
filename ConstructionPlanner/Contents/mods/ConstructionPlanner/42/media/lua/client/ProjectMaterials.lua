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
-- COUNT MATERIALS FOR ONE SEGMENT
------------------------------------------------------------

local function getMaterialsForSegment(segment)
	local materials = {}
	local tools = {}

	if not segment then
		return materials, tools
	end

	local cursor =
		segment.buildCursor

	if not cursor then
		cpDebug(
			"[ConstructionPlanner] Material check: segment has no build cursor"
		)

		return materials, tools
	end

	local recipe =
		cursor.craftRecipe

	if not recipe then
		cpDebug(
			"[ConstructionPlanner] Material check: segment has no craftRecipe"
		)

		return materials, tools
	end

	--------------------------------------------------------
	-- HELPER: READ ONE INPUT'S POSSIBLE ITEM
	--------------------------------------------------------

	local function getInputItem(input)
		if not input then
			return nil
		end

		local possibleItems =
			input:getPossibleInputItems()

		if not possibleItems
		or possibleItems:size() == 0 then
			return nil
		end

		return possibleItems:get(0)
	end

	--------------------------------------------------------
	-- HELPER: ADD TOOL
	--------------------------------------------------------

	local function addToolInput(input)
		if not input then
			return
		end

		if input:isAutomationOnly() then
			return
		end

		local scriptItem =
			getInputItem(input)

		if not scriptItem then
			return
		end

		local fullType =
			scriptItem:getScriptObjectFullType()

		if not fullType
		and scriptItem.getFullName then

			fullType =
				scriptItem:getFullName()
		end

		if fullType then
			tools[fullType] = true

			cpDebug(
				"[ConstructionPlanner] Tool: "
				.. tostring(fullType)
			)
		end
	end

	--------------------------------------------------------
	-- EXPLICIT RECIPE TOOLS
	--------------------------------------------------------

	if recipe.getToolLeft then
		addToolInput(
			recipe:getToolLeft()
		)
	end

	if recipe.getToolRight then
		addToolInput(
			recipe:getToolRight()
		)
	end

	--------------------------------------------------------
	-- CONSUMABLE INPUTS
	--------------------------------------------------------

	local inputs =
		recipe:getInputs()

	if not inputs then
		return materials, tools
	end

	for inputIndex = 0, inputs:size() - 1 do
		local input =
			inputs:get(inputIndex)

		local skipInput = false

		if input:isAutomationOnly() then
			skipInput = true
		end

		if input:getCreateToItemScript() then
			skipInput = true
		end

		----------------------------------------------------
		-- KEPT INPUT = REUSABLE REQUIREMENT
		----------------------------------------------------

		if input:isKeep() then
			addToolInput(input)
			skipInput = true
		end

		----------------------------------------------------
		-- MATERIAL INPUT
		----------------------------------------------------

		if not skipInput
		and input:getResourceType() == ResourceType.Item then

			local scriptItem =
				getInputItem(input)

			if scriptItem then
				local fullType =
					scriptItem:getScriptObjectFullType()

				if not fullType
				and scriptItem.getFullName then

					fullType =
						scriptItem:getFullName()
				end

				if fullType then
					local amount =
						input:getAmount(
							fullType
						)

					if not amount
					or amount <= 0 then

						amount =
							input:getIntAmount()
					end

					if amount
					and amount > 0 then

						if not materials[fullType] then
							materials[fullType] = 0
						end

						materials[fullType] =
							materials[fullType]
							+ amount

						cpDebug(
							"[ConstructionPlanner] Input "
							.. tostring(inputIndex + 1)
							.. ": "
							.. tostring(fullType)
							.. " x"
							.. tostring(amount)
						)
					end
				end
			end
		end
	end

	return materials, tools
end

------------------------------------------------------------
-- PREPARE PER-TILE MATERIAL DISTRIBUTION
------------------------------------------------------------

local function prepareSegmentDistribution(
	segment
)
	if not segment then
		return
	end

	local tiles =
		segment.remainingTiles
		or segment.tiles

	if not tiles then

		segment.distribution =
			{}

		return
	end

	--------------------------------------------------------
	-- MATERIALS REQUIRED FOR ONE BUILD
	--------------------------------------------------------

	local perBuild =
		getMaterialsForSegment(
			segment
		)

	--------------------------------------------------------
	-- INDEX OLD RECORDS BY WORLD TILE
	--
	-- ONLY RECORDS WHOSE BUILD STILL EXISTS IN
	-- remainingTiles WILL BE COPIED INTO THE NEW ARRAY.
	--------------------------------------------------------

	local oldRecords =
		{}

	if segment.distribution then

		for _, record in ipairs(
			segment.distribution
		) do

			if record then

				local key =
					tostring(
						record.x
					)
					.. ":"
					.. tostring(
						record.y
					)
					.. ":"
					.. tostring(
						record.z
					)

				oldRecords[
					key
				] =
					record
			end
		end
	end

	--------------------------------------------------------
	-- REBUILD DISTRIBUTION FROM REMAINING BUILDS ONLY
	--------------------------------------------------------

	local newDistribution =
		{}

	for _, tile in ipairs(
		tiles
	) do

		local key =
			tostring(
				tile.x
			)
			.. ":"
			.. tostring(
				tile.y
			)
			.. ":"
			.. tostring(
				tile.z
			)

		local record =
			oldRecords[
				key
			]

		if not record then

			record = {
				x =
					tile.x,

				y =
					tile.y,

				z =
					tile.z,

				requiredMaterials =
					{},

				stagedMaterials =
					{},

				distributionComplete =
					false
			}
		else

			record.x =
				tile.x

			record.y =
				tile.y

			record.z =
				tile.z

			record.stagedMaterials =
				record.stagedMaterials
				or {}
		end

		----------------------------------------------------
		-- UPDATE REQUIRED MATERIALS
		----------------------------------------------------

		record.requiredMaterials =
			{}

		for fullType, amount in pairs(
			perBuild
		) do

			record.requiredMaterials[
				fullType
			] =
				amount

			if record.stagedMaterials[
				fullType
			] == nil then

				record.stagedMaterials[
					fullType
				] =
					0
			end
		end

		----------------------------------------------------
		-- CURRENT COMPLETION STATE
		----------------------------------------------------

		local complete =
			true

		for fullType, required in pairs(
			record.requiredMaterials
		) do

			local staged =
				record.stagedMaterials[
					fullType
				]
				or 0

			if staged < required then

				complete =
					false

				break
			end
		end

		record.distributionComplete =
			complete

		table.insert(
			newDistribution,
			record
		)
	end

	segment.distribution =
		newDistribution
end

------------------------------------------------------------
-- COUNT MATERIALS AVAILABLE TO VANILLA BUILDING
------------------------------------------------------------

local function getSupplyMaterialCount(fullType)
	if not ConstructionPlanner.getSupplyContainers then
		return 0
	end

	local supplyContainers =
		ConstructionPlanner.getSupplyContainers()

	if not supplyContainers then
		return 0
	end

	local total = 0

	for _, container in ipairs(supplyContainers) do
		if container
		and container.getItems then

			local items =
				container:getItems()

			if items then
				for i = 0, items:size() - 1 do
					local item =
						items:get(i)

					if item
					and item:getFullType() == fullType then

						total =
							total + 1
					end
				end
			end
		end
	end

	return total
end

local function getAvailableMaterialCount(
	fullType
)
	local player =
		getSpecificPlayer(0)

	if not player then
		return 0
	end

	local total =
		0

	--------------------------------------------------------
	-- PLAYER INVENTORY
	--------------------------------------------------------

	local inventory =
		player:getInventory()

	if inventory then

		local items =
			inventory:getItems()

		if items then

			for i = 0, items:size() - 1 do

				local item =
					items:get(i)

				if item
				and item:getFullType()
					== fullType then

					total =
						total + 1
				end
			end
		end
	end

	--------------------------------------------------------
	-- DESIGNATED SUPPLY CONTAINERS
	--------------------------------------------------------

	total =
		total
		+ getSupplyMaterialCount(
			fullType
		)

	--------------------------------------------------------
	-- GATHER AREA GROUND ITEMS
	--------------------------------------------------------

	if ConstructionPlanner.getGroundItemsInGatherAreas then

		local gatherItems =
			ConstructionPlanner.getGroundItemsInGatherAreas(
				fullType
			)

		if gatherItems then

			total =
				total
				+ #gatherItems
		end
	end

	return total
end

------------------------------------------------------------
-- CALCULATE AVAILABLE PROJECT MATERIALS
------------------------------------------------------------

local function calculateAvailableMaterials(
	requiredMaterials
)
	local available = {}

	local player =
		getSpecificPlayer(0)

	if not player then
		return available
	end

	local buildCheat =
		player:isBuildCheat()

	for fullType, required in pairs(
		requiredMaterials
	) do

		if buildCheat then
			available[fullType] =
				required

		else
			local found =
				getAvailableMaterialCount(
					fullType
				)

			available[fullType] =
				math.min(
					found,
					required
				)
		end
	end

	return available
end

function ConstructionPlanner.refreshAvailableMaterials()
	local project =
		ConstructionPlanner.pendingProject

	if not project
	or not project.requiredMaterials then
		return
	end

	project.availableMaterials =
		calculateAvailableMaterials(
			project.requiredMaterials
		)
end


------------------------------------------------------------
-- MULTI-LEVEL PROJECT PHASE PLAN (DIAGNOSTIC / FOUNDATION)
------------------------------------------------------------

local function cpLower(value)
    return string.lower(tostring(value or ""))
end

local function cpSegmentKind(segment)
    local name = cpLower(segment and segment.buildableName)
    local cursor = segment and segment.buildCursor or nil
    local sprite = cpLower(segment and segment.nSprite)

    -- Keep this deliberately conservative.  We log UNKNOWN so the
    -- first test tells us the exact vanilla names we need to support.
    if string.find(name, "stair", 1, true)
    or string.find(sprite, "stair", 1, true) then
        return "stairs"
    end

    if string.find(name, "floor", 1, true)
    or string.find(name, "wooden floor", 1, true)
    or string.find(sprite, "floor", 1, true) then
        return "floor"
    end

    -- Some build cursors expose a type/name separate from buildableName.
    if cursor then
        local cursorName = cpLower(cursor.name)
        local cursorType = cpLower(cursor.Type)
        if string.find(cursorName, "stair", 1, true)
        or string.find(cursorType, "stair", 1, true) then
            return "stairs"
        end
        if string.find(cursorName, "floor", 1, true)
        or string.find(cursorType, "floor", 1, true) then
            return "floor"
        end
    end

    return "rest"
end

function ConstructionPlanner.buildLevelPhasePlan()
    local project = ConstructionPlanner.pendingProject
    if not project or not project.segments then
        return nil
    end

    local minZ, maxZ = nil, nil
    local levels = {}

    for segmentIndex, segment in ipairs(project.segments) do
        local kind = cpSegmentKind(segment)
        segment.cpPhaseKind = kind

        local tiles = segment.remainingTiles or segment.tiles or {}
        for tileIndex, tile in ipairs(tiles) do
            local z = tonumber(tile.z) or 0
            minZ = minZ and math.min(minZ, z) or z
            maxZ = maxZ and math.max(maxZ, z) or z
            levels[z] = levels[z] or { floor = {}, stairs = {}, rest = {}, all = {} }

            local entry = {
                segmentIndex = segmentIndex,
                tileIndex = tileIndex,
                segment = segment,
                tile = tile,
                kind = kind
            }
            table.insert(levels[z].all, entry)
            table.insert(levels[z][kind], entry)
        end
    end

    if minZ == nil then
        return nil
    end

    local phases = {}

    local function addPhase(kind, targetZ, entries, stageZ, accessFromZ)
        if entries and #entries > 0 then
            local phaseIndex = #phases + 1
            local phase = {
                index = phaseIndex,
                kind = kind,
                targetZ = targetZ,
                stageZ = stageZ,
                accessFromZ = accessFromZ,
                entries = entries
            }
            table.insert(phases, phase)

            for _, entry in ipairs(entries) do
                entry.tile.cpPhaseIndex = phaseIndex
                entry.tile.cpPhaseKind = kind
                entry.tile.cpStageZ = stageZ
                entry.tile.cpBuildFromZ = accessFromZ or targetZ
            end
        end
    end

    --------------------------------------------------------
    -- LOWEST LEVEL NORMAL BUILD
    --
    -- STAIRS ARE HELD BACK. A stair anchored on Z is the
    -- transition/access construction for Z+1.
    --------------------------------------------------------

    local baseEntries = {}
    for _, entry in ipairs((levels[minZ] and levels[minZ].all) or {}) do
        if entry.kind ~= "stairs" then
            table.insert(baseEntries, entry)
        end
    end

    addPhase("NORMAL", minZ, baseEntries, minZ, minZ)

    --------------------------------------------------------
    -- EACH HIGHER LEVEL
    --
    -- 1) floor bootstrap: stage on/build from z-1
    -- 2) stair transition anchored on z-1
    -- 3) normal remaining construction on z
    --------------------------------------------------------

    for z = minZ + 1, maxZ do
        local level = levels[z] or { floor = {}, stairs = {}, rest = {}, all = {} }
        local below = levels[z - 1] or { stairs = {} }

        addPhase("FLOOR_BOOTSTRAP", z, level.floor, z - 1, z - 1)
        addPhase("ACCESS_STAIRS", z, below.stairs, z - 1, z - 1)

        local restEntries = {}
        for _, entry in ipairs(level.rest) do
            table.insert(restEntries, entry)
        end
        addPhase("LEVEL_REST", z, restEntries, z, z)
    end

    --------------------------------------------------------
    -- ANY STAIRS ON THE HIGHEST PLANNED LEVEL STILL NEED
    -- TO BE BUILT EVEN IF THERE IS NO HIGHER PLANNED WORK.
    --------------------------------------------------------

    local highest = levels[maxZ]
    if highest and #highest.stairs > 0 then
        addPhase("FINAL_STAIRS", maxZ, highest.stairs, maxZ, maxZ)
    end

    project.cpPhasePlan = phases
    project.cpMinZ = minZ
    project.cpMaxZ = maxZ

    if not project.cpActivePhaseIndex
    or project.cpActivePhaseIndex < 1
    or project.cpActivePhaseIndex > #phases then
        project.cpActivePhaseIndex = 1
    end

    --------------------------------------------------------
    -- COPY PHASE METADATA TO DISTRIBUTION RECORDS
    --------------------------------------------------------

    for _, segment in ipairs(project.segments) do
        if segment.distribution then
            local tiles = segment.remainingTiles or segment.tiles or {}
            for tileIndex, record in ipairs(segment.distribution) do
                local tile = tiles[tileIndex]
                if record and tile then
                    record.cpPhaseIndex = tile.cpPhaseIndex
                    record.cpPhaseKind = tile.cpPhaseKind
                    record.cpTargetZ = tile.z
                    record.cpStageX = tile.x
                    record.cpStageY = tile.y
                    record.cpStageZ = tile.cpStageZ or tile.z
                    record.cpBuildFromZ = tile.cpBuildFromZ or tile.z
                end
            end
        end
    end

    cpDebug("[ConstructionPlanner] =================================")
    cpDebug("[ConstructionPlanner] MULTI-LEVEL PHASE PLAN")
    cpDebug("[ConstructionPlanner] =================================")
    for index, phase in ipairs(phases) do
        cpDebug(
            "[ConstructionPlanner] Phase " .. tostring(index)
            .. " " .. tostring(phase.kind)
            .. " targetZ=" .. tostring(phase.targetZ)
            .. " stageZ=" .. tostring(phase.stageZ)
            .. " builds=" .. tostring(#phase.entries)
        )
        for _, entry in ipairs(phase.entries) do
            cpDebug(
                "[ConstructionPlanner]   "
                .. tostring(entry.segment.buildableName)
                .. " @ " .. tostring(entry.tile.x)
                .. "," .. tostring(entry.tile.y)
                .. "," .. tostring(entry.tile.z)
                .. " kind=" .. tostring(entry.kind)
            )
        end
    end
    cpDebug("[ConstructionPlanner] =================================")

    return phases
end

function ConstructionPlanner.refreshProjectPhaseMetadata()
    return ConstructionPlanner.buildLevelPhasePlan()
end

function ConstructionPlanner.getActiveProjectPhase()
    local project = ConstructionPlanner.pendingProject
    if not project or not project.cpPhasePlan then
        return nil
    end
    return project.cpPhasePlan[project.cpActivePhaseIndex or 1]
end

function ConstructionPlanner.advanceProjectPhase()
    local project = ConstructionPlanner.pendingProject
    if not project or not project.cpPhasePlan then
        return false
    end

    local nextIndex = (project.cpActivePhaseIndex or 1) + 1
    if nextIndex > #project.cpPhasePlan then
        return false
    end

    project.cpActivePhaseIndex = nextIndex
    local phase = project.cpPhasePlan[nextIndex]

    cpDebug(
        "[ConstructionPlanner] ADVANCING TO PHASE "
        .. tostring(nextIndex)
        .. " "
        .. tostring(phase and phase.kind)
    )

    return true
end

------------------------------------------------------------
-- CALCULATE ENTIRE PROJECT
------------------------------------------------------------

function ConstructionPlanner.calculateProjectMaterials()
	local project = ConstructionPlanner.pendingProject

	if not project
	or not project.segments
	or #project.segments == 0 then

		cpDebug("[ConstructionPlanner] No pending project to calculate")
		return nil
	end

	local totals = {}
	local requiredTools = {}

		project.availableMaterials =
		calculateAvailableMaterials(
			totals
		)
	
	cpDebug("[ConstructionPlanner] =========================")
	cpDebug("[ConstructionPlanner] Calculating project materials")
	cpDebug(
		"[ConstructionPlanner] Project segments: "
		.. tostring(#project.segments)
	)

	--------------------------------------------------------
	-- EACH SEGMENT
	--------------------------------------------------------

	for segmentIndex, segment in ipairs(project.segments) do

		--------------------------------------------------------
		-- PREPARE / UPDATE PER-TILE DISTRIBUTION RECORDS
		--------------------------------------------------------

		prepareSegmentDistribution(
			segment
		)

		local buildCount = 0

		if segment.remainingTiles then
			buildCount = #segment.remainingTiles
		elseif segment.tiles then
			buildCount = #segment.tiles
		end

		cpDebug(
			"[ConstructionPlanner] Segment "
			.. tostring(segmentIndex)
			.. ": "
			.. tostring(segment.buildableName)
			.. " x"
			.. tostring(buildCount)
		)

		local perBuild, segmentTools =
			getMaterialsForSegment(segment)

		for fullType, amountPerBuild in pairs(perBuild) do

			local segmentAmount =
				amountPerBuild * buildCount

			if not totals[fullType] then
				totals[fullType] = 0
			end

			totals[fullType] =
				totals[fullType] + segmentAmount

			cpDebug(
				"[ConstructionPlanner]     "
				.. tostring(fullType)
				.. " x"
				.. tostring(segmentAmount)
			)
		end

		for fullType, required in pairs(segmentTools) do
			if required then
				requiredTools[fullType] = true
			end
		end
	end

	--------------------------------------------------------
	-- MULTI-LEVEL PHASE PLAN LIFECYCLE
	--
	-- While the player is still planning, calculateProjectMaterials()
	-- runs after every newly-added preview segment.  The phase plan MUST
	-- therefore be rebuilt so newly-added Z levels/floors/stairs receive
	-- cpPhaseIndex / cpStageZ / cpBuildFromZ metadata.
	--
	-- DistributionManager sets cpPhasePlanLocked=true on the FIRST actual
	-- Build Project execution.  Once locked, phase numbers must remain
	-- stable while completed tiles disappear from remainingTiles.
	--------------------------------------------------------

	if ConstructionPlanner.buildLevelPhasePlan then
		if not project.cpPhasePlanLocked then
			ConstructionPlanner.buildLevelPhasePlan()
		elseif not project.cpPhasePlan then
			-- Safety recovery for an incomplete/legacy project state.
			ConstructionPlanner.buildLevelPhasePlan()
		end
	end

	-- Distribution arrays are rebuilt during material recalculation, so
	-- always re-copy the current/frozen tile metadata onto fresh records.
	for _, segment in ipairs(project.segments) do
		if segment.distribution then
			local tiles = segment.remainingTiles or segment.tiles or {}
			for tileIndex, record in ipairs(segment.distribution) do
				local tile = tiles[tileIndex]
				if record and tile then
					record.cpPhaseIndex = tile.cpPhaseIndex
					record.cpPhaseKind = tile.cpPhaseKind
					record.cpTargetZ = tile.z
					record.cpStageX = tile.x
					record.cpStageY = tile.y
					record.cpStageZ = tile.cpStageZ or tile.z
					record.cpBuildFromZ = tile.cpBuildFromZ or tile.z
				end
			end
		end
	end

	--------------------------------------------------------
	-- SAVE TOTALS TO PROJECT
	--------------------------------------------------------

	project.requiredMaterials = totals
	project.requiredTools = requiredTools

	project.availableMaterials =
		calculateAvailableMaterials(
			totals
		)

	cpDebug("[ConstructionPlanner] -------------------------")
	cpDebug("[ConstructionPlanner] TOTAL REQUIRED MATERIALS")

	local foundAny = false

	for fullType, amount in pairs(totals) do
		foundAny = true

		cpDebug(
			"[ConstructionPlanner] "
			.. tostring(fullType)
			.. " x"
			.. tostring(amount)
		)
	end

	if not foundAny then
		cpDebug("[ConstructionPlanner] No materials detected")
	end

	cpDebug("[ConstructionPlanner] -------------------------")
	cpDebug("[ConstructionPlanner] TOOLS REQUIRED")

	local foundTool = false

	for fullType, required in pairs(requiredTools) do
		if required then
			foundTool = true

			cpDebug(
				"[ConstructionPlanner] "
				.. tostring(fullType)
			)
		end
	end

	if not foundTool then
		cpDebug(
			"[ConstructionPlanner] No tools required"
		)
	end

	cpDebug("[ConstructionPlanner] =========================")

	return totals
end
