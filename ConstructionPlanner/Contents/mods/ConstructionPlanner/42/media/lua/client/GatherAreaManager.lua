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

ConstructionPlanner.gatherAreas =
	ConstructionPlanner.gatherAreas
	or {}

if ConstructionPlanner.gatherAreaHighlight == nil then
	ConstructionPlanner.gatherAreaHighlight =
		true
end

ConstructionPlanner.gatherSupplyRescanPending =
	false

ConstructionPlanner.gatherAreaArmed =
	false

ConstructionPlanner.gatherAreaSelecting =
	false

ConstructionPlanner.gatherAreaStart =
	nil

ConstructionPlanner.gatherAreaCurrent =
	nil

ConstructionPlanner.gatherAreaWaitForRelease =
	false

ConstructionPlanner.gatherAreaWasMouseDown =
	false

ConstructionPlanner.gatherRemovalMode =
	ConstructionPlanner.gatherRemovalMode
	or false


------------------------------------------------------------
-- SAVE DATA
------------------------------------------------------------

local SAVE_KEY =
	"DragBuilderGatherAreas"


local function getSaveData()
	local data =
		ModData.getOrCreate(
			SAVE_KEY
		)

	if not data.areas then
		data.areas = {}
	end

	return data
end


local function saveGatherAreas()
	local data =
		getSaveData()

	data.areas = {}

	for _, area in ipairs(
		ConstructionPlanner.gatherAreas
	) do

		table.insert(
			data.areas,
			{
				x1 = area.x1,
				y1 = area.y1,
				x2 = area.x2,
				y2 = area.y2,
				z = area.z
			}
		)
	end

	data.highlight =
		ConstructionPlanner.gatherAreaHighlight
			~= false

	cpDebug(
		"[ConstructionPlanner] Saved "
		.. tostring(
			#ConstructionPlanner.gatherAreas
		)
		.. " Gather Area(s)"
	)
end


local function loadGatherAreas()
	local data =
		getSaveData()

	ConstructionPlanner.gatherAreas =
		{}

	for _, area in ipairs(
		data.areas or {}
	) do

		if area.x1
		and area.y1
		and area.x2
		and area.y2
		and area.z ~= nil then

			table.insert(
				ConstructionPlanner.gatherAreas,
				{
					x1 = math.min(
						area.x1,
						area.x2
					),

					y1 = math.min(
						area.y1,
						area.y2
					),

					x2 = math.max(
						area.x1,
						area.x2
					),

					y2 = math.max(
						area.y1,
						area.y2
					),

					z = area.z
				}
			)
		end
	end

	if data.highlight == nil then
		ConstructionPlanner.gatherAreaHighlight =
			true
	else
		ConstructionPlanner.gatherAreaHighlight =
			data.highlight == true
	end

cpDebug(
	"[ConstructionPlanner] Loaded "
	.. tostring(
		#ConstructionPlanner.gatherAreas
	)
	.. " Gather Area(s)"
)

--------------------------------------------------------
-- AFTER LOAD, RESCAN THESE AREAS FOR WORLD CONTAINERS
--------------------------------------------------------

ConstructionPlanner.gatherSupplyRescanPending =
	true

ConstructionPlanner.gatherSupplyRescanDelay =
	30
end


------------------------------------------------------------
-- MOUSE WORLD TILE
------------------------------------------------------------

local function getMouseWorldTile()
	local player =
		getSpecificPlayer(0)

	if not player then
		return nil
	end

	local mx =
		getMouseX()

	local my =
		getMouseY()

	local z =
		math.floor(
			player:getZ()
		)

	local wx, wy =
		ISCoordConversion.ToWorld(
			mx,
			my,
			z
		)

	wx =
		math.floor(
			wx
		)

	wy =
		math.floor(
			wy
		)

	local square =
		getCell():getGridSquare(
			wx,
			wy,
			z
		)

	--------------------------------------------------------
	-- MATCH VANILLA GRID-SQUARE SELECTION BEHAVIOR:
	-- IF THIS LEVEL HAS NO WALKABLE FLOOR UNDER THE MOUSE,
	-- SEARCH DOWNWARD UNTIL WE FIND ONE.
	--------------------------------------------------------

	while z >= 0
	and (
		not square
		or not square:TreatAsSolidFloor()
	) do

		z =
			z - 1

		if z < 0 then
			return nil
		end

		wx, wy =
			ISCoordConversion.ToWorld(
				mx,
				my,
				z
			)

		wx =
			math.floor(
				wx
			)

		wy =
			math.floor(
				wy
			)

		square =
			getCell():getGridSquare(
				wx,
				wy,
				z
			)
	end

	if not square then
		return nil
	end

	return {
		x = wx,
		y = wy,
		z = z
	}
end

------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------

function ConstructionPlanner.getGatherAreas()
	return ConstructionPlanner.gatherAreas
end


function ConstructionPlanner.getGatherAreaCount()
	return #ConstructionPlanner.gatherAreas
end


function ConstructionPlanner.startGatherAreaSelection()
	ConstructionPlanner.gatherAreaArmed =
		true

	ConstructionPlanner.gatherAreaSelecting =
		false

	ConstructionPlanner.gatherAreaStart =
		nil

	ConstructionPlanner.gatherAreaCurrent =
		nil

	--------------------------------------------------------
	-- The Set button itself is a left mouse click.
	-- Wait for that click to be released before watching
	-- for the world-selection click.
	--------------------------------------------------------

	ConstructionPlanner.gatherAreaWaitForRelease =
		true

	local player =
		getSpecificPlayer(0)

	ConstructionPlanner.gatherAreaWasMouseDown =
		player
		and player:isBuildButtonDown()
		or false

	cpDebug(
		"[ConstructionPlanner] Gather Area selection armed"
	)
end


function ConstructionPlanner.clearGatherAreas()
	ConstructionPlanner.gatherAreas =
		{}

	ConstructionPlanner.gatherAreaArmed =
		false

	ConstructionPlanner.gatherAreaSelecting =
		false

	ConstructionPlanner.gatherAreaStart =
		nil

	ConstructionPlanner.gatherAreaCurrent =
		nil

	saveGatherAreas()

	cpDebug(
		"[ConstructionPlanner] Removed all Gather Areas"
	)
end


function ConstructionPlanner.toggleGatherAreaHighlight()
	ConstructionPlanner.gatherAreaHighlight =
		not (
			ConstructionPlanner.gatherAreaHighlight
				~= false
		)

	saveGatherAreas()

	cpDebug(
		"[ConstructionPlanner] Gather Area highlight: "
		.. tostring(
			ConstructionPlanner.gatherAreaHighlight
		)
	)
end


function ConstructionPlanner.removeGatherAreasIntersectingTiles(
	selectedTiles
)
	if not selectedTiles
	or #selectedTiles == 0 then
		return 0
	end

	local removed = 0

	for areaIndex = #ConstructionPlanner.gatherAreas, 1, -1 do
		local area =
			ConstructionPlanner.gatherAreas[areaIndex]

		local intersects =
			false

		for _, tile in ipairs(selectedTiles) do
			if tile.z == area.z
			and tile.x >= area.x1
			and tile.x <= area.x2
			and tile.y >= area.y1
			and tile.y <= area.y2 then
				intersects = true
				break
			end
		end

		if intersects then
			table.remove(
				ConstructionPlanner.gatherAreas,
				areaIndex
			)

			removed =
				removed + 1
		end
	end

	if removed > 0 then
		saveGatherAreas()
	end

	cpDebug(
		"[ConstructionPlanner] Removed "
		.. tostring(removed)
		.. " Gather Area(s)"
	)

	return removed
end

------------------------------------------------------------
-- ADD CONTAINERS INSIDE GATHER AREA AS SUPPLY CONTAINERS
------------------------------------------------------------

local function addGatherAreaSupplyContainers(
	area
)
	if not area then
		return 0
	end

	if not ConstructionPlanner.addSupplyContainer then

		cpDebug(
			"[ConstructionPlanner] Supply container manager unavailable"
		)

		return 0
	end

	local added =
		0

	for x = area.x1, area.x2 do

		for y = area.y1, area.y2 do

			local square =
				getCell():getGridSquare(
					x,
					y,
					area.z
				)

			if square then

				cpDebug(
					"[ConstructionPlanner] Gather scan square "
					.. tostring(x)
					.. ","
					.. tostring(y)
					.. ","
					.. tostring(area.z)
				)

				local objects =
					square:getObjects()

				cpDebug(
					"[ConstructionPlanner] Gather scan objects="
					.. tostring(
						objects
						and objects:size()
						or 0
					)
				)

				if objects then

					for i = 0,
						objects:size() - 1 do

						local object =
							objects:get(i)

						if object
						and object.getContainer then
								cpDebug(
									"[ConstructionPlanner] Gather object "
									.. tostring(i)
									.. " has getContainer"
								)
							local container =
								object:getContainer()
									cpDebug(
										"[ConstructionPlanner] Gather object "
										.. tostring(i)
										.. " container="
										.. tostring(container)
									)
							if container then

								local alreadySupply =
									ConstructionPlanner.isSupplyContainer
									and ConstructionPlanner.isSupplyContainer(
										container
									)

								if not alreadySupply then

									ConstructionPlanner.addSupplyContainer(
										container
									)

									added =
										added + 1
								end
							end
						end
					end
				end
			end
		end
	end

	if added > 0 then

		cpDebug(
			"[ConstructionPlanner] Gather Area added "
			.. tostring(added)
			.. " supply container(s)"
		)
	end

	return added
end

------------------------------------------------------------
-- RESCAN LOADED GATHER AREAS FOR SUPPLY CONTAINERS
------------------------------------------------------------

local function updateGatherSupplyRescan()

	if not ConstructionPlanner.gatherSupplyRescanPending then
		return
	end

	--------------------------------------------------------
	-- WAIT A SHORT TIME AFTER GAME LOAD
	--------------------------------------------------------

	if ConstructionPlanner.gatherSupplyRescanDelay
	and ConstructionPlanner.gatherSupplyRescanDelay > 0 then

		ConstructionPlanner.gatherSupplyRescanDelay =
			ConstructionPlanner.gatherSupplyRescanDelay - 1

		return
	end

	--------------------------------------------------------
	-- SUPPLY SYSTEM MUST BE READY
	--------------------------------------------------------

	if not ConstructionPlanner.addSupplyContainer then
		return
	end

	ConstructionPlanner.gatherSupplyRescanPending =
		false

	ConstructionPlanner.gatherSupplyRescanDelay =
		nil

	--------------------------------------------------------
	-- RESCAN EVERY SAVED GATHER AREA
	--------------------------------------------------------

	for _, area in ipairs(
		ConstructionPlanner.gatherAreas
	) do

		addGatherAreaSupplyContainers(
			area
		)
	end
end

------------------------------------------------------------
-- REGISTER NEW CONTAINERS BUILT INSIDE GATHER AREAS
------------------------------------------------------------

function ConstructionPlanner.addSupplyContainersAtGatherTile(
	x,
	y,
	z
)
	--------------------------------------------------------
	-- TILE MUST BELONG TO AT LEAST ONE GATHER AREA
	--------------------------------------------------------

	local insideGatherArea =
		false

	for _, area in ipairs(
		ConstructionPlanner.gatherAreas
	) do

		if z == area.z
		and x >= area.x1
		and x <= area.x2
		and y >= area.y1
		and y <= area.y2 then

			insideGatherArea =
				true

			break
		end
	end

	if not insideGatherArea then
		return 0
	end

	if not ConstructionPlanner.addSupplyContainer then
		return 0
	end

	--------------------------------------------------------
	-- SCAN ONLY THE NEWLY BUILT SQUARE
	--------------------------------------------------------

	local square =
		getCell():getGridSquare(
			x,
			y,
			z
		)

	if not square then
		return 0
	end

	local objects =
		square:getObjects()

	if not objects then
		return 0
	end

	local added =
		0

	for i = 0, objects:size() - 1 do

		local object =
			objects:get(i)

		if object
		and object.getContainer then

			local container =
				object:getContainer()

			if container then

				local alreadySupply =
					ConstructionPlanner.isSupplyContainer
					and ConstructionPlanner.isSupplyContainer(
						container
					)

				if not alreadySupply then

					ConstructionPlanner.addSupplyContainer(
						container
					)

					added =
						added + 1
				end
			end
		end
	end

	if added > 0 then

		cpDebug(
			"[ConstructionPlanner] Built container inside Gather Area added to supplies"
		)
	end

	return added
end

------------------------------------------------------------
-- ADD RECTANGLE
------------------------------------------------------------

local function finishGatherArea(
	startTile,
	endTile
)
	if not startTile
	or not endTile then

		return false
	end

	if startTile.z ~= endTile.z then

		cpDebug(
			"[ConstructionPlanner] Gather Area cancelled - Z level changed"
		)

		return false
	end

	local area = {
		x1 =
			math.min(
				startTile.x,
				endTile.x
			),

		y1 =
			math.min(
				startTile.y,
				endTile.y
			),

		x2 =
			math.max(
				startTile.x,
				endTile.x
			),

		y2 =
			math.max(
				startTile.y,
				endTile.y
			),

		z =
			startTile.z
	}

	table.insert(
		ConstructionPlanner.gatherAreas,
		area
	)

	saveGatherAreas()

	--------------------------------------------------------
	-- EVERY STORAGE CONTAINER INSIDE THIS GATHER AREA
	-- AUTOMATICALLY BECOMES A NORMAL SUPPLY CONTAINER.
	--------------------------------------------------------

	addGatherAreaSupplyContainers(
		area
	)

	local width =
		area.x2
		- area.x1
		+ 1

	local height =
		area.y2
		- area.y1
		+ 1

	cpDebug(
		"[ConstructionPlanner] Added Gather Area "
		.. tostring(
			#ConstructionPlanner.gatherAreas
		)
		.. " - "
		.. tostring(width)
		.. "x"
		.. tostring(height)
		.. " at Z="
		.. tostring(area.z)
	)

	return true
end


------------------------------------------------------------
-- SELECTION UPDATE
------------------------------------------------------------

local function updateGatherAreaSelection()
	if not ConstructionPlanner.gatherAreaArmed
	and not ConstructionPlanner.gatherAreaSelecting then
		return
	end

	local player =
		getSpecificPlayer(0)

	if not player then
		return
	end

	--------------------------------------------------------
	-- USE THE SAME INPUT DRAGBUILDER ALREADY USES FOR
	-- WORLD BUILDING SELECTIONS.
	--------------------------------------------------------

	local mouseDown =
		player:isBuildButtonDown()

	--------------------------------------------------------
	-- THE SET BUTTON ITSELF WAS A UI CLICK.
	-- WAIT UNTIL THAT CLICK IS FULLY RELEASED.
	--------------------------------------------------------

	if ConstructionPlanner.gatherAreaWaitForRelease then

		if not mouseDown then
			ConstructionPlanner.gatherAreaWaitForRelease =
				false
		end

		ConstructionPlanner.gatherAreaWasMouseDown =
			mouseDown

		return
	end

	--------------------------------------------------------
	-- BEGIN RECTANGLE
	--------------------------------------------------------

	if ConstructionPlanner.gatherAreaArmed
	and mouseDown
	and not ConstructionPlanner.gatherAreaWasMouseDown then

		local tile =
			getMouseWorldTile()

		if tile then

			ConstructionPlanner.gatherAreaStart =
				tile

			ConstructionPlanner.gatherAreaCurrent =
				tile

			ConstructionPlanner.gatherAreaSelecting =
				true

			ConstructionPlanner.gatherAreaArmed =
				false

			cpDebug(
				"[ConstructionPlanner] Gather Area start: "
				.. tostring(tile.x)
				.. ", "
				.. tostring(tile.y)
				.. ", "
				.. tostring(tile.z)
			)

		else

			cpDebug(
				"[ConstructionPlanner] Gather Area waiting for valid world tile"
			)
		end
	end

	--------------------------------------------------------
	-- UPDATE RECTANGLE WHILE DRAGGING
	--------------------------------------------------------

	if ConstructionPlanner.gatherAreaSelecting
	and mouseDown then

		local tile =
			getMouseWorldTile()

		if tile
		and ConstructionPlanner.gatherAreaStart
		and tile.z
			== ConstructionPlanner.gatherAreaStart.z then

			ConstructionPlanner.gatherAreaCurrent =
				tile
		end
	end

	--------------------------------------------------------
	-- RELEASE = SAVE RECTANGLE
	--------------------------------------------------------

	if ConstructionPlanner.gatherAreaSelecting
	and ConstructionPlanner.gatherAreaWasMouseDown
	and not mouseDown then

		local endTile =
			ConstructionPlanner.gatherAreaCurrent
			or getMouseWorldTile()

		local saved =
			finishGatherArea(
				ConstructionPlanner.gatherAreaStart,
				endTile
			)

		if not saved then
			cpDebug(
				"[ConstructionPlanner] Gather Area was not saved"
			)
		end

		ConstructionPlanner.gatherAreaSelecting =
			false

		ConstructionPlanner.gatherAreaStart =
			nil

		ConstructionPlanner.gatherAreaCurrent =
			nil
	end

	ConstructionPlanner.gatherAreaWasMouseDown =
		mouseDown
end

------------------------------------------------------------
-- HIGHLIGHT RENDER
------------------------------------------------------------

local function drawArea(
	area,
	alpha
)
	if not area then
		return
	end

	for x = area.x1, area.x2 do
		for y = area.y1, area.y2 do

			local square =
				getCell():getGridSquare(
					x,
					y,
					area.z
				)

			local floor =
				square
				and square:getFloor()
				or nil

			if floor then
				------------------------------------------------
				-- RENDER-ONCE HIGHLIGHT
				--
				-- Reapplied every frame while visible, so it
				-- behaves like a persistent area highlight
				-- without permanently changing the floor.
				------------------------------------------------

				floor:setHighlightColor(
					0.35,
					0.90,
					0.35,
					alpha
				)

				floor:setHighlighted(
					true,
					true
				)
			end
		end
	end
end

local function renderGatherAreas()
	--------------------------------------------------------
	-- SAVED AREAS
	--------------------------------------------------------

	if ConstructionPlanner.gatherAreaHighlight
		~= false then

		for _, area in ipairs(
			ConstructionPlanner.gatherAreas
		) do

			drawArea(
				area,
				0.18
			)
		end
	end

	--------------------------------------------------------
	-- CURRENT AREA IS ALWAYS SHOWN WHILE SETTING
	--------------------------------------------------------

	if ConstructionPlanner.gatherAreaSelecting
	and ConstructionPlanner.gatherAreaStart
	and ConstructionPlanner.gatherAreaCurrent then

		local startTile =
			ConstructionPlanner.gatherAreaStart

		local endTile =
			ConstructionPlanner.gatherAreaCurrent

		drawArea(
			{
				x1 =
					math.min(
						startTile.x,
						endTile.x
					),

				y1 =
					math.min(
						startTile.y,
						endTile.y
					),

				x2 =
					math.max(
						startTile.x,
						endTile.x
					),

				y2 =
					math.max(
						startTile.y,
						endTile.y
					),

				z =
					startTile.z
			},
			0.42
		)
	end
end


------------------------------------------------------------
-- GROUND ITEM SCANNING API
------------------------------------------------------------

function ConstructionPlanner.getGroundItemsInGatherAreas(
	fullType,
	maxCount
)
	local found =
		{}

	local seen =
		{}

	for _, area in ipairs(
		ConstructionPlanner.gatherAreas
	) do

		for x = area.x1, area.x2 do
			for y = area.y1, area.y2 do

				local square =
					getCell():getGridSquare(
						x,
						y,
						area.z
					)

				local worldObjects =
					square
					and square:getWorldObjects()
					or nil

				if worldObjects then

					for i = 0,
						worldObjects:size() - 1 do

						local object =
							worldObjects:get(i)

						local item =
							object
							and object:getItem()
							or nil

						if item
						and not seen[item]
						and (
							not fullType
							or item:getFullType()
								== fullType
						) then

							seen[item] =
								true

							table.insert(
								found,
								{
									item = item,
									worldObject = object,
									square = square
								}
							)

							if maxCount
							and #found >= maxCount then

								return found
							end
						end
					end
				end
			end
		end
	end

	return found
end


------------------------------------------------------------
-- EVENTS
------------------------------------------------------------

Events.OnTick.Add(
	updateGatherAreaSelection
)

Events.OnTick.Add(
	updateGatherSupplyRescan
)

Events.OnPostRender.Add(
	renderGatherAreas
)

Events.OnGameStart.Add(
	loadGatherAreas
)
