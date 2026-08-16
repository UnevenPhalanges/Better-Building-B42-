-- Release logging helper.
local function cpDebug(...)
	if ConstructionPlanner
	and ConstructionPlanner.DEBUG then
		print(...)
	end
end

ConstructionPlanner.mode = ConstructionPlanner.mode or "plan"

------------------------------------------------------------
-- PLAN HEIGHT OFFSET
--
-- +0 = current level. Positive values plan future levels
-- while the player remains on the current physical floor.
------------------------------------------------------------

ConstructionPlanner.planHeightOffset =
	ConstructionPlanner.planHeightOffset
	or 0

function ConstructionPlanner.getPlanHeightOffset()
	return ConstructionPlanner.planHeightOffset
		or 0
end

function ConstructionPlanner.setPlanHeightOffset(value)
	value = math.floor(tonumber(value) or 0)

	if value < 0 then
		value = 0
	elseif value > 7 then
		value = 7
	end

	ConstructionPlanner.planHeightOffset = value

	cpDebug(
		"[ConstructionPlanner] Plan height: +"
		.. tostring(value)
	)
end

function ConstructionPlanner.adjustPlanHeightOffset(delta)
	ConstructionPlanner.setPlanHeightOffset(
		ConstructionPlanner.getPlanHeightOffset()
		+ (delta or 0)
	)
end

function ConstructionPlanner.getPlanTargetZ(baseZ)
	local page =
		ConstructionPlanner.projectPanelPage
		or "plan"

	if page ~= "plan" then
		return baseZ
	end

	return baseZ
		+ ConstructionPlanner.getPlanHeightOffset()
end

------------------------------------------------------------
-- PLACEMENT SHAPE
--
-- AREA IS THE DEFAULT.
------------------------------------------------------------

ConstructionPlanner.placementMode =
	ConstructionPlanner.placementMode
	or "area"

function ConstructionPlanner.getPlacementMode()
	return ConstructionPlanner.placementMode
		or "area"
end

function ConstructionPlanner.setPlacementMode(
	mode
)
	if mode ~= "area"
	and mode ~= "line" then

		return
	end

	ConstructionPlanner.placementMode =
		mode
end

function ConstructionPlanner.togglePlacementMode()

	if ConstructionPlanner.getPlacementMode()
		== "area" then

		ConstructionPlanner.setPlacementMode(
			"line"
		)
	else

		ConstructionPlanner.setPlacementMode(
			"area"
		)
	end
end

function ConstructionPlanner.getMode()
	return ConstructionPlanner.mode or "plan"
end

function ConstructionPlanner.setMode(mode)
	if mode ~= "quick"
	and mode ~= "plan"
	and mode ~= "off" then
		return
	end

	ConstructionPlanner.mode = mode

		if ConstructionPlanner.applyMode then
		ConstructionPlanner.applyMode()
	end

	cpDebug(
		"[ConstructionPlanner] Mode: "
		.. string.upper(mode)
	)
end

function ConstructionPlanner.cycleMode()
	local mode = ConstructionPlanner.getMode()

	if mode == "quick" then
		ConstructionPlanner.setMode("plan")

	elseif mode == "plan" then
		ConstructionPlanner.setMode("off")

	else
		ConstructionPlanner.setMode("quick")
	end
end

local function generateStraightLine(startTile, endTile)
    local tiles = {}

    local differenceX = endTile.x - startTile.x
    local differenceY = endTile.y - startTile.y

    if math.abs(differenceX) >= math.abs(differenceY) then
        local stepX = differenceX >= 0 and 1 or -1

        for x = startTile.x, endTile.x, stepX do
            table.insert(tiles, {
                x = x,
                y = startTile.y,
                z = startTile.z
            })
        end
    else
        local stepY = differenceY >= 0 and 1 or -1

        for y = startTile.y, endTile.y, stepY do
            table.insert(tiles, {
                x = startTile.x,
                y = y,
                z = startTile.z
            })
        end
    end

    return tiles
end

------------------------------------------------------------
-- FILLED RECTANGLE
------------------------------------------------------------

local function generateArea(
	startTile,
	endTile
)
	local tiles =
		{}

	local minX =
		math.min(
			startTile.x,
			endTile.x
		)

	local maxX =
		math.max(
			startTile.x,
			endTile.x
		)

	local minY =
		math.min(
			startTile.y,
			endTile.y
		)

	local maxY =
		math.max(
			startTile.y,
			endTile.y
		)

	for y = minY, maxY do

		for x = minX, maxX do

			table.insert(
				tiles,
				{
					x =
						x,

					y =
						y,

					z =
						startTile.z
				}
			)
		end
	end

	return tiles
end

------------------------------------------------------------
-- SHARED SELECTION SHAPE
--
-- BUILD + REMOVE BOTH USE THIS.
-- FOR NOW DRAGBUILDER ONLY HAS LINE MODE.
------------------------------------------------------------

------------------------------------------------------------
-- SHARED SELECTION SHAPE
------------------------------------------------------------

local function getSelectionTiles(
	startTile,
	endTile
)
	if not startTile
	or not endTile then

		return {}
	end

	--------------------------------------------------------
	-- AREA MODE
	--------------------------------------------------------

	if ConstructionPlanner.getPlacementMode()
		== "area" then

		return generateArea(
			startTile,
			endTile
		)
	end

	--------------------------------------------------------
	-- LINE MODE
	--------------------------------------------------------

	return generateStraightLine(
		startTile,
		endTile
	)
end

ConstructionPlanner.getSelectionTiles =
	getSelectionTiles

ConstructionPlanner.getSelectionTiles =
	getSelectionTiles

local function copyTiles(sourceTiles)
	local copied = {}

	if not sourceTiles then
		return copied
	end

	for _, tile in ipairs(sourceTiles) do
		table.insert(copied, {
			x = tile.x,
			y = tile.y,
			z = tile.z
		})
	end

	return copied
end

local function tileKey(x, y, z)
	return tostring(x)
		.. ":"
		.. tostring(y)
		.. ":"
		.. tostring(z)
end

------------------------------------------------------------
-- MOUSE WORLD TILE
--
-- CURSOR-INDEPENDENT WORLD SELECTION.
-- SAME B42 METHOD ALREADY USED SUCCESSFULLY BY
-- GATHER AREA SELECTION.
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
	-- FIND THE FIRST VALID FLOOR UNDER THE MOUSE.
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

local sprite = nil

local function getFootprintTiles(cursor, anchorTile)
	local footprint = {}

	if not cursor or not anchorTile then
		return footprint
	end

	local face = nil

	if cursor.getFace then
		face = cursor:getFace()
	end

	--------------------------------------------------------
	-- FALLBACK 1x1
	--------------------------------------------------------

	if not face then
		table.insert(
			footprint,
			{
				x = anchorTile.x,
				y = anchorTile.y,
				z = anchorTile.z
			}
		)

		return footprint
	end

	--------------------------------------------------------
	-- VANILLA BUILD 42 FOOTPRINT
	--------------------------------------------------------

	for zz = 0, face:getzLayers() - 1 do
		for xx = 0, face:getWidth() - 1 do
			for yy = 0, face:getHeight() - 1 do

				local tileInfo =
					face:getTileInfo(
						xx,
						yy,
						zz
					)

				if tileInfo
				and (
					tileInfo:getSpriteName()
					or tileInfo:isBlocking()
				) then

					table.insert(
						footprint,
						{
							x = anchorTile.x + xx,
							y = anchorTile.y + yy,
							z = anchorTile.z + zz
						}
					)
				end
			end
		end
	end

	--------------------------------------------------------
	-- SAFETY FALLBACK
	--------------------------------------------------------

	if #footprint == 0 then
		table.insert(
			footprint,
			{
				x = anchorTile.x,
				y = anchorTile.y,
				z = anchorTile.z
			}
		)
	end

	return footprint
end

local function isWallLikePlacement(cursor, footprint)
	if not cursor
	or not footprint
	or #footprint ~= 1 then
		return false
	end

	if cursor.isWallLike then
		return true
	end

	local name =
		string.lower(
			tostring(cursor.name or "")
		)

	if string.find(name, "wall", 1, true) then
		return true
	end

	if string.find(name, "fence", 1, true) then
		return true
	end

	return false
end

local function getOccupancyType(
	cursor,
	footprint
)
	if not cursor then
		return "object"
	end

	--------------------------------------------------------
	-- WALL / FENCE EDGE
	--------------------------------------------------------

	if isWallLikePlacement(
		cursor,
		footprint
	) then

		if cursor.north == true then
			return "wallNorth"
		end

		return "wallWest"
	end

	--------------------------------------------------------
	-- FLOOR
	--------------------------------------------------------

	local name =
		string.lower(
			tostring(
				cursor.name or ""
			)
		)

	if string.find(
		name,
		"floor",
		1,
		true
	) then

		return "floor"
	end

	--------------------------------------------------------
	-- GENERAL OBJECT
	--------------------------------------------------------

	return "object"
end

local function occupancyConflicts(
	existing,
	newType
)
	if not existing
	or not newType then

		return false
	end

	return existing[
		newType
	] == true
end

local function reserveOccupancy(
	occupied,
	tile,
	occupancyType
)
	local key =
		tileKey(
			tile.x,
			tile.y,
			tile.z
		)

	occupied[key] =
		occupied[key] or {}

	occupied[key][occupancyType] = true
end

local function getExistingOccupiedTiles()
	local occupied =
		{}

	local project =
		ConstructionPlanner.pendingProject

	if not project
	or not project.segments then

		return occupied
	end

	for _, segment in ipairs(
		project.segments
	) do

		----------------------------------------------------
		-- SEGMENTS WITH SAVED OCCUPANCY
		----------------------------------------------------

		if segment.occupiedTiles then

			for _, tile in ipairs(
				segment.occupiedTiles
			) do

				local occupancyType =
					tile.occupancyType
					or segment.occupancyType
					or "object"

				reserveOccupancy(
					occupied,
					tile,
					occupancyType
				)
			end

		----------------------------------------------------
		-- FALLBACK FOR OLDER SEGMENTS
		----------------------------------------------------

		elseif segment.tiles
		and segment.buildCursor then

			local cursor =
				segment.buildCursor

			------------------------------------------------
			-- SAVE LIVE CURSOR DIRECTION
			------------------------------------------------

			local oldNorth =
				cursor.north

			------------------------------------------------
			-- TEMPORARILY RESTORE SAVED DIRECTION
			------------------------------------------------

			if segment.north ~= nil then

				cursor.north =
					segment.north
			end

			for _, anchorTile in ipairs(
				segment.tiles
			) do

				local footprint =
					getFootprintTiles(
						cursor,
						anchorTile
					)

				local occupancyType =
					segment.occupancyType
					or getOccupancyType(
						cursor,
						footprint
					)

				for _, tile in ipairs(
					footprint
				) do

					reserveOccupancy(
						occupied,
						tile,
						occupancyType
					)
				end
			end

			------------------------------------------------
			-- RESTORE LIVE CURSOR
			------------------------------------------------

			cursor.north =
				oldNorth
		end
	end

	return occupied
end

local function getRemoveMouseWorldTile()
	local tile =
		getMouseWorldTile()

	if not tile then
		return nil
	end

	return {
		x = tile.x,
		y = tile.y,
		z = ConstructionPlanner.getPlanTargetZ(
			tile.z
		)
	}
end


------------------------------------------------------------
-- REBUILD ONE SEGMENT'S OCCUPIED TILE CACHE
------------------------------------------------------------

local function rebuildSegmentOccupiedTiles(
	segment
)
	if not segment
	or not segment.buildCursor then
		return
	end

	segment.occupiedTiles =
		{}

	local sourceTiles =
		segment.tiles or {}

	--------------------------------------------------------
	-- IMPORTANT:
	-- USE THE SLOT SAVED WHEN THIS SEGMENT WAS CREATED.
	-- DO NOT RECALCULATE IT FROM THE LIVE CURSOR.
	--------------------------------------------------------

	local occupancyType =
		segment.occupancyType

	if not occupancyType then

		local oldNorth =
			segment.buildCursor.north

		if segment.north ~= nil then
			segment.buildCursor.north =
				segment.north
		end

		if sourceTiles[1] then

			local footprint =
				getFootprintTiles(
					segment.buildCursor,
					sourceTiles[1]
				)

			occupancyType =
				getOccupancyType(
					segment.buildCursor,
					footprint
				)
		else

			occupancyType =
				"object"
		end

		segment.buildCursor.north =
			oldNorth

		segment.occupancyType =
			occupancyType
	end

	for _, anchorTile in ipairs(
		sourceTiles
	) do

		local footprint =
			getFootprintTiles(
				segment.buildCursor,
				anchorTile
			)

		for _, tile in ipairs(
			footprint
		) do

			table.insert(
				segment.occupiedTiles,
				{
					x =
						tile.x,

					y =
						tile.y,

					z =
						tile.z,

					occupancyType =
						occupancyType
				}
			)
		end
	end
end

------------------------------------------------------------
-- DOES THIS OLD PLACEMENT OCCUPY ONE OF THE NEW BUILD'S
-- TILES IN THE SAME PLACEMENT SLOT?
------------------------------------------------------------

local function placementConflictsWithNew(
	segment,
	oldAnchor,
	newFootprint,
	newType
)
	if not segment
	or not segment.buildCursor
	or not oldAnchor
	or not newFootprint
	or not newType then

		return false
	end

	--------------------------------------------------------
	-- OLD PREVIEW USES ITS FROZEN OCCUPANCY SLOT.
	--
	-- NEVER RECALCULATE FROM segment.buildCursor HERE.
	-- THAT CURSOR IS MUTABLE AND MAY HAVE BEEN ROTATED
	-- DURING CONSTRUCTION.
	--------------------------------------------------------

	local oldType =
		segment.occupancyType

	if not oldType then

		local oldNorth =
			segment.buildCursor.north

		if segment.north ~= nil then
			segment.buildCursor.north =
				segment.north
		end

		local oldFootprint =
			getFootprintTiles(
				segment.buildCursor,
				oldAnchor
			)

		oldType =
			getOccupancyType(
				segment.buildCursor,
				oldFootprint
			)

		segment.buildCursor.north =
			oldNorth
	end

	--------------------------------------------------------
	-- DIFFERENT SLOTS CAN SHARE THE SAME TILE.
	--
	-- wallNorth + wallWest = allowed.
	-- floor + wall = allowed.
	--------------------------------------------------------

	if oldType ~= newType then
		return false
	end

	--------------------------------------------------------
	-- SAME SLOT: CHECK WHETHER THEIR FOOTPRINTS TOUCH.
	--------------------------------------------------------

	local oldFootprint =
		getFootprintTiles(
			segment.buildCursor,
			oldAnchor
		)

	for _, oldTile in ipairs(
		oldFootprint
	) do

		for _, newTile in ipairs(
			newFootprint
		) do

			if oldTile.x == newTile.x
			and oldTile.y == newTile.y
			and oldTile.z == newTile.z then

				return true
			end
		end
	end

	return false
end

------------------------------------------------------------
-- REMOVE OLD PREVIEWS THAT THE NEW PREVIEW REPLACES
------------------------------------------------------------

local function removeReplacedPreviews(
	tiles,
	cursor
)
	local project =
		ConstructionPlanner.pendingProject

	if not project
	or not project.segments
	or not tiles
	or not cursor then

		return
	end

	--------------------------------------------------------
	-- CHECK EACH NEW PLACEMENT
	--------------------------------------------------------

	for _, newAnchor in ipairs(
		tiles
	) do

		local newFootprint =
			getFootprintTiles(
				cursor,
				newAnchor
			)

		local newType =
			getOccupancyType(
				cursor,
				newFootprint
			)

		----------------------------------------------------
		-- SEARCH EXISTING PROJECT SEGMENTS
		----------------------------------------------------

		for segmentIndex =
			#project.segments,
			1,
			-1 do

			local segment =
				project.segments[
					segmentIndex
				]

			if segment
			and segment.tiles
			and segment.buildCursor then

				for tileIndex =
					#segment.tiles,
					1,
					-1 do

					local oldAnchor =
						segment.tiles[
							tileIndex
						]

					if placementConflictsWithNew(
						segment,
						oldAnchor,
						newFootprint,
						newType
					) then

						------------------------------------------------
						-- SAME SLOT ON SAME POSITION:
						-- NEW PREVIEW REPLACES OLD PREVIEW
						------------------------------------------------

						table.remove(
							segment.tiles,
							tileIndex
						)

						------------------------------------------------
						-- REMOVE FROM REMAINING TILES
						------------------------------------------------

						if segment.remainingTiles then

							for remainingIndex =
								#segment.remainingTiles,
								1,
								-1 do

								local remainingTile =
									segment.remainingTiles[
										remainingIndex
									]

								if remainingTile.x
									== oldAnchor.x
								and remainingTile.y
									== oldAnchor.y
								and remainingTile.z
									== oldAnchor.z then

									table.remove(
										segment.remainingTiles,
										remainingIndex
									)

									if segment.distribution
									and segment.distribution[
										remainingIndex
									] then

										table.remove(
											segment.distribution,
											remainingIndex
										)
									end

									break
								end
							end
						end
					end
				end

				------------------------------------------------
				-- REBUILD USING THE SEGMENT'S SAVED SLOT
				------------------------------------------------

				rebuildSegmentOccupiedTiles(
					segment
				)

				------------------------------------------------
				-- REMOVE EMPTY SEGMENT
				------------------------------------------------

				if #segment.tiles == 0 then

					table.remove(
						project.segments,
						segmentIndex
					)
				end
			end
		end
	end
end

local function filterOverlappingPlacements(tiles, cursor)
	local validTiles = {}
	local occupied = getExistingOccupiedTiles()

	for _, anchorTile in ipairs(tiles) do

		local footprint =
			getFootprintTiles(
				cursor,
				anchorTile
			)

		local occupancyType =
			getOccupancyType(
				cursor,
				footprint
			)

		local blocked = false

		----------------------------------------------------
		-- CHECK THIS BUILD'S COMPLETE FOOTPRINT
		----------------------------------------------------

		for _, tile in ipairs(footprint) do

			local existing =
				occupied[
					tileKey(
						tile.x,
						tile.y,
						tile.z
					)
				]

			if occupancyConflicts(
				existing,
				occupancyType
			) then

				blocked = true
				break
			end
		end

		----------------------------------------------------
		-- ACCEPT AND RESERVE IT
		----------------------------------------------------

		if not blocked then

			table.insert(
				validTiles,
				anchorTile
			)

			for _, tile in ipairs(footprint) do
				reserveOccupancy(
					occupied,
					tile,
					occupancyType
				)
			end
		end
	end

	return validTiles
end

------------------------------------------------------------
-- ELEVATED PREVIEW ATTACHMENT
--
-- Future-level previews may not begin as isolated floating
-- islands.  A new elevated placement must connect to at least
-- one of these:
--
--   * an existing planned preview directly below it
--   * a real walkable square beside it on the target Z
--   * an existing planned preview beside it on the target Z
--   * another accepted tile from THIS SAME drag
--
-- This keeps upper-level planning physically connected while
-- still allowing one drag to grow a floor outward.
------------------------------------------------------------

local function hasRealFloorAt(
	x,
	y,
	z
)
	if z < 0 then
		return false
	end

	local square =
		getCell():getGridSquare(
			x,
			y,
			z
		)

	return square ~= nil
		and square:TreatAsSolidFloor()
end

local function hasPlannedOccupancyAt(
	occupied,
	x,
	y,
	z
)
	if not occupied then
		return false
	end

	return occupied[
		tileKey(
			x,
			y,
			z
		)
	] ~= nil
end

local function elevatedTileIsAttached(
	tile,
	occupied,
	accepted
)
	if not tile then
		return false
	end

	--------------------------------------------------------
	-- PLANNED SUPPORT BELOW
	--
	-- IMPORTANT: a normal real floor on Z-1 does NOT count
	-- as attachment. Otherwise every Z+1 preview placed over
	-- ordinary ground would be accepted as "supported" even
	-- when completely detached from the planned structure.
	--
	-- A planned object directly below DOES count, which gives
	-- us a clean way for stairs / planned supporting structure
	-- to seed the next level.
	--------------------------------------------------------

	if hasPlannedOccupancyAt(
		occupied,
		tile.x,
		tile.y,
		tile.z - 1
	) then
		return true
	end

	--------------------------------------------------------
	-- SAME-LEVEL CARDINAL CONNECTION
	--------------------------------------------------------

	local neighbours = {
		{ x = tile.x - 1, y = tile.y },
		{ x = tile.x + 1, y = tile.y },
		{ x = tile.x, y = tile.y - 1 },
		{ x = tile.x, y = tile.y + 1 }
	}

	for _, neighbour in ipairs(
		neighbours
	) do

		if hasRealFloorAt(
			neighbour.x,
			neighbour.y,
			tile.z
		)
		or hasPlannedOccupancyAt(
			occupied,
			neighbour.x,
			neighbour.y,
			tile.z
		)
		or accepted[
			tileKey(
				neighbour.x,
				neighbour.y,
				tile.z
			)
		] then
			return true
		end
	end

	return false
end

------------------------------------------------------------
-- REMOVE WORLD-INVALID PLACEMENTS
--
-- A TILE THAT VANILLA WOULD NOT ALLOW THIS BUILD OBJECT
-- TO OCCUPY MUST NEVER BECOME A PROJECT PREVIEW.
------------------------------------------------------------

local function filterInvalidPlacements(
	tiles,
	cursor
)
	local validTiles =
		{}

	if not tiles
	or not cursor then

		return validTiles
	end

	local plannedOccupied =
		getExistingOccupiedTiles()

	local acceptedElevated =
		{}

	for _, tile in ipairs(
		tiles
	) do

		local square =
			getCell():getGridSquare(
				tile.x,
				tile.y,
				tile.z
			)

		local valid =
			false

		local player =
			getSpecificPlayer(0)

		local playerZ =
			player
			and math.floor(player:getZ())
			or tile.z

		local elevatedPlan =
			(ConstructionPlanner.projectPanelPage or "plan") == "plan"
			and tile.z > playerZ

		if elevatedPlan then
			----------------------------------------------------
			-- Future-level previews may exist before their own
			-- floor exists, but they must remain connected to
			-- real/planned structure.
			----------------------------------------------------

			valid =
				elevatedTileIsAttached(
					tile,
					plannedOccupied,
					acceptedElevated
				)

		elseif square
		and cursor.isValid then

			valid =
				cursor:isValid(
					square
				)
		end

		if valid then

			table.insert(
				validTiles,
				tile
			)

			if elevatedPlan then
				acceptedElevated[
					tileKey(
						tile.x,
						tile.y,
						tile.z
					)
				] = true
			end
		else

			cpDebug(
				"[ConstructionPlanner] Skipping invalid preview at "
				.. tostring(
					tile.x
				)
				.. ", "
				.. tostring(
					tile.y
				)
				.. ", "
				.. tostring(
					tile.z
				)
			)
		end
	end

	return validTiles
end

local function addProjectSegment(tiles)
	if not tiles
	or #tiles == 0 then
		return
	end

	local cursor =
		ConstructionPlanner.currentCursor

	if not cursor then
		return
	end

	--------------------------------------------------------
	-- REMOVE WORLD-INVALID PLACEMENTS
	--------------------------------------------------------

	local worldValidTiles =
		filterInvalidPlacements(
			tiles,
			cursor
		)

	if #worldValidTiles == 0 then

		cpDebug(
			"[ConstructionPlanner] No valid placements - all selected tiles are invalid"
		)

		return
	end

	--------------------------------------------------------
	-- SAME-SLOT PREVIEWS REPLACE OLD PREVIEWS
	--------------------------------------------------------

	removeReplacedPreviews(
		worldValidTiles,
		cursor
	)

	--------------------------------------------------------
	-- REMOVE REMAINING OCCUPANCY CONFLICTS
	--------------------------------------------------------

	local validTiles =
		filterOverlappingPlacements(
			worldValidTiles,
			cursor
		)

	if #validTiles == 0 then

		cpDebug(
			"[ConstructionPlanner] No valid placements - all previews overlap"
		)

		return
	end

	--------------------------------------------------------
	-- ONLY CREATE PROJECT AFTER SOMETHING SURVIVED
	--------------------------------------------------------

	if not ConstructionPlanner.pendingProject then

		ConstructionPlanner.pendingProject = {
			segments =
				{},

			status =
				"planning",

			requiredMaterials =
				{}
		}

		cpDebug(
			"[ConstructionPlanner] New pending project created"
		)
	end

	--------------------------------------------------------
	-- FREEZE THIS SEGMENT'S OCCUPANCY SLOT
	--
	-- WALL DIRECTION MUST NOT FOLLOW THE LIVE CURSOR
	-- AFTER THE PLAYER ROTATES IT AGAIN.
	--------------------------------------------------------

	local segmentOccupancyType =
		getOccupancyType(
			cursor,
			getFootprintTiles(
				cursor,
				validTiles[1]
			)
		)

	--------------------------------------------------------
	-- RECORD FULL OCCUPIED FOOTPRINT
	--------------------------------------------------------

	local occupiedTiles =
		{}

	for _, anchorTile in ipairs(
		validTiles
	) do

		local footprint =
			getFootprintTiles(
				cursor,
				anchorTile
			)

		for _, tile in ipairs(
			footprint
		) do

			table.insert(
				occupiedTiles,
				{
					x =
						tile.x,

					y =
						tile.y,

					z =
						tile.z,

					occupancyType =
						segmentOccupancyType
				}
			)
		end
	end

	--------------------------------------------------------
	-- CREATE SEGMENT
	--------------------------------------------------------

	local segment = {
		tiles =
			copyTiles(
				validTiles
			),

		remainingTiles =
			copyTiles(
				validTiles
			),

		occupiedTiles =
			occupiedTiles,

		occupancyType =
			segmentOccupancyType,

		north =
			cursor.north == true,

		buildCursor =
			cursor,

		buildableName =
			cursor
			and tostring(
				cursor.name
			)
			or "Unknown",

		nSprite =
			cursor
			and cursor.nSprite
			or nil
	}

	table.insert(
		ConstructionPlanner.pendingProject.segments,
		segment
	)

	cpDebug(
		"[ConstructionPlanner] Added project segment "
		.. tostring(
			#ConstructionPlanner.pendingProject.segments
		)
		.. " - "
		.. tostring(
			segment.buildableName
		)
		.. " - "
		.. tostring(
			#validTiles
		)
		.. " build(s)"
	)

	cpDebug(
		"[ConstructionPlanner] Occupied preview tiles: "
		.. tostring(
			#occupiedTiles
		)
	)
end

local function removeProjectPreviews(
	selectedTiles
)
	if not selectedTiles
	or #selectedTiles == 0 then

		return 0
	end

	local project =
		ConstructionPlanner.pendingProject

	if not project
	or not project.segments then

		cpDebug(
			"[ConstructionPlanner] No project previews to remove"
		)

		return 0
	end

	--------------------------------------------------------
	-- ONLY ALLOW PREVIEW EDITING WHILE PLANNING
	--------------------------------------------------------

	if project.status
	and project.status ~= "planning" then

		cpDebug(
			"[ConstructionPlanner] Preview removal unavailable while project is active"
		)

		return 0
	end

	--------------------------------------------------------
	-- BUILD LOOKUP OF SELECTED WORLD TILES
	--------------------------------------------------------

	local selectedLookup =
		{}

	for _, tile in ipairs(
		selectedTiles
	) do

		selectedLookup[
			tileKey(
				tile.x,
				tile.y,
				tile.z
			)
		] =
			true
	end

	local removedCount =
		0

	--------------------------------------------------------
	-- WORK BACKWARDS SO SEGMENTS CAN BE REMOVED SAFELY
	--------------------------------------------------------

	for segmentIndex =
		#project.segments,
		1,
		-1 do

		local segment =
			project.segments[
				segmentIndex
			]

		if segment
		and segment.tiles
		and segment.buildCursor then

			------------------------------------------------
			-- FIND PLACEMENTS TO REMOVE
			------------------------------------------------

			local removeAnchors =
				{}

			for tileIndex, anchorTile in ipairs(
				segment.tiles
			) do

				local footprint =
					getFootprintTiles(
						segment.buildCursor,
						anchorTile
					)

				local removePlacement =
					false

				for _, footprintTile in ipairs(
					footprint
				) do

					local key =
						tileKey(
							footprintTile.x,
							footprintTile.y,
							footprintTile.z
						)

					if selectedLookup[
						key
					] then

						removePlacement =
							true

						break
					end
				end

				if removePlacement then

					table.insert(
						removeAnchors,
						{
							index =
								tileIndex,

							x =
								anchorTile.x,

							y =
								anchorTile.y,

							z =
								anchorTile.z
						}
					)
				end
			end

			------------------------------------------------
			-- REMOVE MATCHING PLACEMENTS BACKWARDS
			------------------------------------------------

			for removeIndex =
				#removeAnchors,
				1,
				-1 do

				local removal =
					removeAnchors[
						removeIndex
					]

				------------------------------------------------
				-- ORIGINAL PLACEMENT LIST
				------------------------------------------------

				table.remove(
					segment.tiles,
					removal.index
				)

				------------------------------------------------
				-- REMAINING BUILD LIST
				------------------------------------------------

				if segment.remainingTiles then

					for remainingIndex =
						#segment.remainingTiles,
						1,
						-1 do

						local remainingTile =
							segment.remainingTiles[
								remainingIndex
							]

						if remainingTile.x
							== removal.x
						and remainingTile.y
							== removal.y
						and remainingTile.z
							== removal.z then

							table.remove(
								segment.remainingTiles,
								remainingIndex
							)

							------------------------------------------------
							-- DISTRIBUTION RECORD FOLLOWS REMAINING TILE
							------------------------------------------------

							if segment.distribution
							and segment.distribution[
								remainingIndex
							] then

								table.remove(
									segment.distribution,
									remainingIndex
								)
							end

							break
						end
					end
				end

				removedCount =
					removedCount + 1
			end

			------------------------------------------------
			-- REBUILD OCCUPANCY FOR WHAT REMAINS
			------------------------------------------------

			if #removeAnchors > 0 then

				segment.occupiedTiles =
					{}

				for _, anchorTile in ipairs(
					segment.tiles
				) do

					local footprint =
						getFootprintTiles(
							segment.buildCursor,
							anchorTile
						)

					------------------------------------------------
					-- IMPORTANT:
					-- USE THE FROZEN SEGMENT SLOT.
					-- DO NOT RECALCULATE FROM THE LIVE CURSOR.
					------------------------------------------------

					local occupancyType =
						segment.occupancyType

					if not occupancyType then

						local oldNorth =
							segment.buildCursor.north

						if segment.north ~= nil then

							segment.buildCursor.north =
								segment.north
						end

						occupancyType =
							getOccupancyType(
								segment.buildCursor,
								footprint
							)

						segment.buildCursor.north =
							oldNorth
					end

					for _, footprintTile in ipairs(
						footprint
					) do

						table.insert(
							segment.occupiedTiles,
							{
								x =
									footprintTile.x,

								y =
									footprintTile.y,

								z =
									footprintTile.z,

								occupancyType =
									occupancyType
							}
						)
					end
				end
			end

			------------------------------------------------
			-- EMPTY SEGMENT
			------------------------------------------------

			if #segment.tiles == 0 then

				table.remove(
					project.segments,
					segmentIndex
				)
			end
		end
	end

	--------------------------------------------------------
	-- WHOLE PROJECT WAS REMOVED
	--------------------------------------------------------

	if #project.segments == 0 then

		ConstructionPlanner.pendingProject =
			nil

		cpDebug(
			"[ConstructionPlanner] All project previews removed"
		)

	else

		if ConstructionPlanner.calculateProjectMaterials then

			ConstructionPlanner.calculateProjectMaterials()
		end

		cpDebug(
			"[ConstructionPlanner] Removed "
			.. tostring(
				removedCount
			)
			.. " preview placement(s)"
		)
	end

	return removedCount
end

------------------------------------------------------------
-- REMOVE SELECTION PREVIEW
------------------------------------------------------------

ConstructionPlanner.removeSelecting =
	false

ConstructionPlanner.removeSelectionReady =
	false

ConstructionPlanner.removeStartTile =
	nil

ConstructionPlanner.removeCurrentTile =
	nil

------------------------------------------------------------
-- COMMITTED REMOVE SELECTION
--
-- LOOKUP STORES THE ACTUAL TILE TABLE SO WE CAN REBUILD
-- THE TILE LIST WITHOUT HAVING TO PARSE THE TILE KEY.
------------------------------------------------------------

ConstructionPlanner.removeSelectedTileLookup =
	{}

ConstructionPlanner.removeSelectionTiles =
	{}

------------------------------------------------------------
-- CURRENT LIVE DRAG
------------------------------------------------------------

ConstructionPlanner.removeDragTiles =
	{}

------------------------------------------------------------
-- WHAT THE PLAYER CURRENTLY SEES.
--
-- WHILE DRAGGING THIS REPRESENTS THE RESULT THAT WOULD
-- EXIST IF THE PLAYER RELEASED THE MOUSE RIGHT NOW.
------------------------------------------------------------

ConstructionPlanner.removeDisplayTiles =
	{}

ConstructionPlanner.removeTargetedPreviewAnchors =
	{}


local function copyTile(
	tile
)
	if not tile then
		return nil
	end

	return {
		x = tile.x,
		y = tile.y,
		z = tile.z
	}
end


local function rebuildCommittedRemoveTiles()
	ConstructionPlanner.removeSelectionTiles =
		{}

	for _, tile in pairs(
		ConstructionPlanner.removeSelectedTileLookup
	) do

		table.insert(
			ConstructionPlanner.removeSelectionTiles,
			copyTile(
				tile
			)
		)
	end
end


local function clearRemoveSelection()
	ConstructionPlanner.removeSelecting =
		false

	ConstructionPlanner.removeSelectionReady =
		false

	ConstructionPlanner.removeStartTile =
		nil

	ConstructionPlanner.removeCurrentTile =
		nil

	ConstructionPlanner.removeSelectedTileLookup =
		{}

	ConstructionPlanner.removeSelectionTiles =
		{}

	ConstructionPlanner.removeDragTiles =
		{}

	ConstructionPlanner.removeDisplayTiles =
		{}

	ConstructionPlanner.removeTargetedPreviewAnchors =
		{}
end


ConstructionPlanner.clearRemoveSelection =
	clearRemoveSelection


------------------------------------------------------------
-- BUILD THE SELECTION THE PLAYER SHOULD CURRENTLY SEE.
--
-- START WITH THE COMMITTED SELECTION.
--
-- THEN TOGGLE EVERY TILE IN THE CURRENT DRAG:
--
-- NOT SELECTED = WOULD BECOME SELECTED
-- SELECTED     = WOULD BECOME DESELECTED
------------------------------------------------------------

local function rebuildRemoveDisplayTiles()
	local effectiveLookup =
		{}

	for key, tile in pairs(
		ConstructionPlanner.removeSelectedTileLookup
	) do

		effectiveLookup[
			key
		] =
			copyTile(
				tile
			)
	end

	for _, tile in ipairs(
		ConstructionPlanner.removeDragTiles
	) do

		local key =
			tileKey(
				tile.x,
				tile.y,
				tile.z
			)

		if effectiveLookup[
			key
		] then

			effectiveLookup[
				key
			] =
				nil

		else

			effectiveLookup[
				key
			] =
				copyTile(
					tile
				)
		end
	end

	ConstructionPlanner.removeDisplayTiles =
		{}

	for _, tile in pairs(
		effectiveLookup
	) do

		table.insert(
			ConstructionPlanner.removeDisplayTiles,
			copyTile(
				tile
			)
		)
	end
end


------------------------------------------------------------
-- FIND ALL SAVED PROJECT PREVIEWS THAT INTERSECT
-- THE CURRENT DISPLAY SELECTION.
------------------------------------------------------------

local function rebuildRemoveTargets()
	ConstructionPlanner.removeTargetedPreviewAnchors =
		{}

	local selectedTiles =
		ConstructionPlanner.removeDisplayTiles

	if not selectedTiles
	or #selectedTiles == 0 then
		return
	end

	local project =
		ConstructionPlanner.pendingProject

	if not project
	or not project.segments then
		return
	end

	local selectedLookup =
		{}

	for _, tile in ipairs(
		selectedTiles
	) do

		selectedLookup[
			tileKey(
				tile.x,
				tile.y,
				tile.z
			)
		] =
			true
	end

	for _, segment in ipairs(
		project.segments
	) do

		if segment
		and segment.buildCursor
		and segment.remainingTiles then

			for _, anchorTile in ipairs(
				segment.remainingTiles
			) do

				local footprint =
					getFootprintTiles(
						segment.buildCursor,
						anchorTile
					)

				local targeted =
					false

				for _, footprintTile in ipairs(
					footprint
				) do

					local key =
						tileKey(
							footprintTile.x,
							footprintTile.y,
							footprintTile.z
						)

					if selectedLookup[
						key
					] then

						targeted =
							true

						break
					end
				end

				if targeted then

					ConstructionPlanner.removeTargetedPreviewAnchors[
						tileKey(
							anchorTile.x,
							anchorTile.y,
							anchorTile.z
						)
					] =
						true
				end
			end
		end
	end
end


------------------------------------------------------------
-- UPDATE CURRENT LIVE DRAG
------------------------------------------------------------

local function refreshRemoveSelection(
	currentTile
)
	if not ConstructionPlanner.removeStartTile
	or not currentTile then

		return
	end

	if currentTile.z
	~= ConstructionPlanner.removeStartTile.z then

		return
	end

	ConstructionPlanner.removeCurrentTile = {
		x = currentTile.x,
		y = currentTile.y,
		z = currentTile.z
	}

	ConstructionPlanner.removeDragTiles =
		getSelectionTiles(
			ConstructionPlanner.removeStartTile,
			ConstructionPlanner.removeCurrentTile
		)

	rebuildRemoveDisplayTiles()

	rebuildRemoveTargets()
end


------------------------------------------------------------
-- COMMIT THE CURRENT DRAG INTO THE MULTI-SELECTION.
--
-- EVERY TILE IS TOGGLED.
------------------------------------------------------------

local function commitRemoveDrag()
	for _, tile in ipairs(
		ConstructionPlanner.removeDragTiles
	) do

		local key =
			tileKey(
				tile.x,
				tile.y,
				tile.z
			)

		if ConstructionPlanner.removeSelectedTileLookup[
			key
		] then

			ConstructionPlanner.removeSelectedTileLookup[
				key
			] =
				nil

		else

			ConstructionPlanner.removeSelectedTileLookup[
				key
			] =
				copyTile(
					tile
				)
		end
	end

	ConstructionPlanner.removeDragTiles =
		{}

	rebuildCommittedRemoveTiles()

	ConstructionPlanner.removeDisplayTiles =
		copyTiles(
			ConstructionPlanner.removeSelectionTiles
		)

	ConstructionPlanner.removeSelectionReady =
		#ConstructionPlanner.removeSelectionTiles > 0

	rebuildRemoveTargets()
end


function ConstructionPlanner.isPreviewTargetedForRemoval(
	x,
	y,
	z
)
	local lookup =
		ConstructionPlanner.removeTargetedPreviewAnchors

	if not lookup then
		return false
	end

	return lookup[
		tileKey(
			x,
			y,
			z
		)
	] == true
end


------------------------------------------------------------
-- CONFIRM ALL CURRENTLY COMMITTED REMOVE SELECTIONS
------------------------------------------------------------

function ConstructionPlanner.confirmRemoveSelection()
	if not ConstructionPlanner.previewRemovalMode then
		return 0
	end

	if not ConstructionPlanner.removeSelectionReady then

		cpDebug(
			"[ConstructionPlanner] No removal selection to confirm"
		)

		return 0
	end

	local selectedTiles =
		copyTiles(
			ConstructionPlanner.removeSelectionTiles
		)

	if #selectedTiles == 0 then

		clearRemoveSelection()

		return 0
	end

	local removed =
		removeProjectPreviews(
			selectedTiles
		)

	--------------------------------------------------------
	-- CLEAR THE CURRENT MULTI-SELECTION AFTER CONFIRMING.
	--------------------------------------------------------

	clearRemoveSelection()

	--------------------------------------------------------
	-- IF THE ENTIRE PROJECT WAS REMOVED,
	-- REMOVE MODE TURNS OFF.
	--------------------------------------------------------

	if not ConstructionPlanner.pendingProject then

		ConstructionPlanner.previewRemovalMode =
			false
	end

	cpDebug(
		"[ConstructionPlanner] Confirmed removal of "
		.. tostring(removed)
		.. " preview placement(s)"
	)

	return removed
end


------------------------------------------------------------
-- RENDER CURRENT REMOVE SELECTION
------------------------------------------------------------

local function renderRemoveSelection()
	if not ConstructionPlanner.previewRemovalMode then
		return
	end

	local tiles =
		ConstructionPlanner.removeDisplayTiles

	if not tiles
	or #tiles == 0 then
		return
	end

	for _, tile in ipairs(
		tiles
	) do

		local square =
			getCell():getGridSquare(
				tile.x,
				tile.y,
				tile.z
			)

		local floor =
			square
			and square:getFloor()
			or nil

		if floor then

			floor:setHighlightColor(
				0.95,
				0.15,
				0.15,
				0.48
			)

			floor:setHighlighted(
				true,
				true
			)
		end
	end
end

ConstructionPlanner.removeAllProjectPreviews =
	function()

		local project =
			ConstructionPlanner.pendingProject

		if not project
		or not project.segments then

			cpDebug(
				"[ConstructionPlanner] No project previews to remove"
			)

			return 0
		end

		------------------------------------------------
		-- ONLY ALLOW WHILE PROJECT IS STILL PLANNING
		------------------------------------------------

		if project.status
		and project.status ~= "planning" then

			cpDebug(
				"[ConstructionPlanner] Preview removal unavailable while project is active"
			)

			return 0
		end

		------------------------------------------------
		-- COLLECT EVERY PLANNED ANCHOR TILE
		------------------------------------------------

		local allTiles =
			{}

		for _, segment in ipairs(
			project.segments
		) do

			if segment
			and segment.tiles then

				for _, tile in ipairs(
					segment.tiles
				) do

					table.insert(
						allTiles,
						{
							x = tile.x,
							y = tile.y,
							z = tile.z
						}
					)
				end
			end
		end

		if #allTiles == 0 then
			return 0
		end

		------------------------------------------------
		-- USE THE EXISTING PREVIEW REMOVAL SYSTEM
		------------------------------------------------

		local removed =
			removeProjectPreviews(
				allTiles
			)

		clearRemoveSelection()

		ConstructionPlanner.previewRemovalMode =
			false

		cpDebug(
			"[ConstructionPlanner] Remove All Previews removed "
			.. tostring(removed)
			.. " placement(s)"
		)

		return removed
	end

local function printSelectedTiles()
	local startTile = ConstructionPlanner.startTile
	local endTile = ConstructionPlanner.endTile

	if not startTile or not endTile then
		return
	end

	local tiles =
		getSelectionTiles(
			startTile,
			endTile
		)

	cpDebug("[ConstructionPlanner] -------------------------")
	cpDebug(
		"[ConstructionPlanner] Selected "
		.. tostring(#tiles)
		.. " tiles"
	)

	for index, tile in ipairs(tiles) do
		cpDebug(
			"[ConstructionPlanner] "
			.. tostring(index)
			.. ": "
			.. tostring(tile.x)
			.. ", "
			.. tostring(tile.y)
			.. ", "
			.. tostring(tile.z)
		)
	end

	cpDebug("[ConstructionPlanner] -------------------------")

	--------------------------------------------------------
	-- HANDLE CURRENT DRAGBUILDER MODE
	--------------------------------------------------------

	local mode =
		ConstructionPlanner.getMode
		and ConstructionPlanner.getMode()
		or "plan"

	--------------------------------------------------------
	-- PLAN MODE
	--------------------------------------------------------

	if mode == "plan" then

		----------------------------------------------------
		-- GATHER AREA REMOVAL
		----------------------------------------------------

		if ConstructionPlanner.gatherRemovalMode
		and ConstructionPlanner.removeGatherAreasIntersectingTiles then

			ConstructionPlanner.removeGatherAreasIntersectingTiles(
				tiles
			)

			return
		end

		----------------------------------------------------
		-- NORMAL PREVIEW PLACEMENT
		----------------------------------------------------

		addProjectSegment(
			tiles
		)

		return
	end

--------------------------------------------------------
-- QUICK MODE
--------------------------------------------------------

	--------------------------------------------------------
	-- QUICK MODE
	--------------------------------------------------------

	if mode == "quick" then

		----------------------------------------------------
		-- QUICK MODE IS INDEPENDENT OF PLAN MODE.
		--
		-- The execution pipeline currently operates on
		-- pendingProject, so preserve any existing Plan project
		-- off to the side while the temporary Quick project runs.
		-- finalizeProject() restores it when Quick finishes.
		----------------------------------------------------

		if ConstructionPlanner.quickProjectActive then
			cpDebug(
				"[ConstructionPlanner] Quick Build failed - "
				.. "another Quick Build is already active"
			)
			return
		end

		local savedPlanProject =
			ConstructionPlanner.pendingProject

		ConstructionPlanner.savedPlanProjectDuringQuick =
			savedPlanProject

		ConstructionPlanner.pendingProject =
			nil

		----------------------------------------------------
		-- CREATE A TEMPORARY QUICK PROJECT USING THE SAME
		-- PROVEN DISTRIBUTION / CONSTRUCTION PIPELINE.
		----------------------------------------------------

		addProjectSegment(
			tiles
		)

		local project =
			ConstructionPlanner.pendingProject

		if project then
			project.cpQuickProject = true
			ConstructionPlanner.quickProjectActive = true
		end

		if not project
		or not project.segments
		or #project.segments == 0 then

			ConstructionPlanner.pendingProject =
				ConstructionPlanner.savedPlanProjectDuringQuick

			ConstructionPlanner.savedPlanProjectDuringQuick =
				nil

			ConstructionPlanner.quickProjectActive =
				false

			cpDebug(
				"[ConstructionPlanner] Quick Build failed - "
				.. "project was not created"
			)

			return
		end

		----------------------------------------------------
		-- CLEAR LEGACY QUICK-BUILD STATE.
		----------------------------------------------------

		ConstructionPlanner.building =
			false

		ConstructionPlanner.buildQueue =
			nil

		ConstructionPlanner.buildIndex =
			nil

		ConstructionPlanner.nextBuildPending =
			false

		ConstructionPlanner.nextBuildDelay =
			nil

		ConstructionPlanner.queueNSprite =
			nil

		----------------------------------------------------
		-- MOUSE RELEASE STARTS DISTRIBUTION IMMEDIATELY.
		----------------------------------------------------

		ConstructionPlanner.previewRemovalMode =
			false

		ConstructionPlanner.gatherRemovalMode =
			false

		if not ConstructionPlanner.startDistributionPickup then

			ConstructionPlanner.pendingProject =
				ConstructionPlanner.savedPlanProjectDuringQuick

			ConstructionPlanner.savedPlanProjectDuringQuick =
				nil

			ConstructionPlanner.quickProjectActive =
				false

			cpDebug(
				"[ConstructionPlanner] Quick Build failed - "
				.. "distribution manager not loaded"
			)

			return
		end

		ConstructionPlanner.pendingQuickDistribution =
			true

		ConstructionPlanner.pendingQuickDistributionWait =
			true

		cpDebug(
			"[ConstructionPlanner] Quick Build - "
			.. "project created, distribution pending"
		)

		return
	end

	--------------------------------------------------------
	-- OFF MODE
	--------------------------------------------------------

	cpDebug(
		"[ConstructionPlanner] DragBuilder is OFF"
	)
end

local function update()
	if not ConstructionPlanner.plannerEnabled then

		ConstructionPlanner.wasBuildButtonDown =
			false

		clearRemoveSelection()

		return
	end

	--------------------------------------------------------
	-- GATHER AREA SELECTION OWNS THE BUILD BUTTON.
	--------------------------------------------------------

	if ConstructionPlanner.gatherAreaArmed
	or ConstructionPlanner.gatherAreaSelecting then

		ConstructionPlanner.wasBuildButtonDown =
			false

		clearRemoveSelection()

		return
	end

	--------------------------------------------------------
	-- ONLY PLAN / QUICK OWN NORMAL BUILD PREVIEW INPUT.
	--
	-- EXTRA TOOL PAGES (DISMANTLE / DESTROY) HAVE THEIR
	-- OWN MOUSE-SELECTION MANAGERS AND MUST NEVER FALL
	-- THROUGH INTO PREVIEW PLACEMENT.
	--------------------------------------------------------

	local activePage =
		ConstructionPlanner.projectPanelPage
		or "plan"

	if activePage ~= "plan"
	and activePage ~= "quick" then

		ConstructionPlanner.wasBuildButtonDown =
			false

		if ConstructionPlanner.removeSelecting
		or ConstructionPlanner.removeSelectionReady then

			clearRemoveSelection()
		end

		return
	end

	local player =
		getSpecificPlayer(0)

	if not player then
		return
	end

	local mouseDown =
		player:isBuildButtonDown()

	--------------------------------------------------------
	-- REMOVE MODE
	--
	-- DOES NOT REQUIRE A BUILD CURSOR.
	--------------------------------------------------------

	if ConstructionPlanner.previewRemovalMode then

		----------------------------------------------------
		-- BEGIN ANOTHER REMOVE SELECTION.
		--
		-- IMPORTANT:
		-- DO NOT CLEAR PREVIOUS COMMITTED SELECTIONS.
		----------------------------------------------------

		if mouseDown
		and not ConstructionPlanner.wasBuildButtonDown then

			local tile =
				getRemoveMouseWorldTile()

			if tile then

				ConstructionPlanner.removeSelecting =
					true

				ConstructionPlanner.removeStartTile = {
					x = tile.x,
					y = tile.y,
					z = tile.z
				}

				ConstructionPlanner.removeCurrentTile = {
					x = tile.x,
					y = tile.y,
					z = tile.z
				}

				ConstructionPlanner.removeDragTiles =
					{}

				refreshRemoveSelection(
					tile
				)

				cpDebug(
					"[ConstructionPlanner] Remove start: "
					.. tostring(tile.x)
					.. ", "
					.. tostring(tile.y)
					.. ", "
					.. tostring(tile.z)
				)
			end
		end

		----------------------------------------------------
		-- LIVE DRAG
		----------------------------------------------------

		if ConstructionPlanner.removeSelecting
		and mouseDown then

			local tile =
				getRemoveMouseWorldTile()

			if tile then

				refreshRemoveSelection(
					tile
				)
			end
		end

		----------------------------------------------------
		-- RELEASE = TOGGLE THIS DRAG INTO THE
		-- EXISTING MULTI-SELECTION.
		----------------------------------------------------

		if ConstructionPlanner.removeSelecting
		and ConstructionPlanner.wasBuildButtonDown
		and not mouseDown then

			local endTile =
				ConstructionPlanner.removeCurrentTile
				or getRemoveMouseWorldTile()

			if endTile then

				refreshRemoveSelection(
					endTile
				)

				cpDebug(
					"[ConstructionPlanner] Remove end: "
					.. tostring(endTile.x)
					.. ", "
					.. tostring(endTile.y)
					.. ", "
					.. tostring(endTile.z)
				)

				commitRemoveDrag()

				if ConstructionPlanner.removeSelectionReady then

					cpDebug(
						"[ConstructionPlanner] Removal selection ready for confirmation"
					)

				else

					cpDebug(
						"[ConstructionPlanner] Removal selection cleared"
					)
				end

			else

				ConstructionPlanner.removeDragTiles =
					{}

				rebuildRemoveDisplayTiles()

				rebuildRemoveTargets()
			end

			ConstructionPlanner.removeSelecting =
				false

			ConstructionPlanner.removeStartTile =
				nil

			ConstructionPlanner.removeCurrentTile =
				nil
		end

		ConstructionPlanner.wasBuildButtonDown =
			mouseDown

		return
	end

	--------------------------------------------------------
	-- REMOVE MODE OFF = CLEAR ALL REMOVE SELECTION STATE.
	--------------------------------------------------------

	if ConstructionPlanner.removeSelecting
	or ConstructionPlanner.removeSelectionReady
	or (
		ConstructionPlanner.removeSelectionTiles
		and #ConstructionPlanner.removeSelectionTiles > 0
	)
	or (
		ConstructionPlanner.removeDragTiles
		and #ConstructionPlanner.removeDragTiles > 0
	) then

		clearRemoveSelection()
	end

	--------------------------------------------------------
	-- NORMAL PLAN / QUICK SELECTION
	--------------------------------------------------------

	local cursor =
		ConstructionPlanner.currentCursor

	if not cursor then

		ConstructionPlanner.wasBuildButtonDown =
			false

		return
	end

	--------------------------------------------------------
	-- MOUSE FIRST PRESSED
	--------------------------------------------------------

	if mouseDown
	and not ConstructionPlanner.wasBuildButtonDown then

		local square =
			cursor.square

		if square then

			ConstructionPlanner.selecting =
				true

			local baseZ =
				square:getZ()

			local targetZ =
				ConstructionPlanner.getPlanTargetZ
				and ConstructionPlanner.getPlanTargetZ(baseZ)
				or baseZ

			ConstructionPlanner.startTile = {
				x =
					square:getX(),

				y =
					square:getY(),

				z =
					targetZ
			}

			ConstructionPlanner.endTile =
				nil

			cpDebug(
				"[ConstructionPlanner] Start: "
				.. tostring(
					ConstructionPlanner.startTile.x
				)
				.. ", "
				.. tostring(
					ConstructionPlanner.startTile.y
				)
				.. ", "
				.. tostring(
					ConstructionPlanner.startTile.z
				)
			)
		end
	end

	--------------------------------------------------------
	-- MOUSE RELEASED
	--------------------------------------------------------

	if ConstructionPlanner.selecting
	and ConstructionPlanner.wasBuildButtonDown
	and not mouseDown then

		local tile =
			ConstructionPlanner.hoverTile

		if tile then

			ConstructionPlanner.endTile = {
				x =
					tile.x,

				y =
					tile.y,

				z =
					tile.z
			}

			cpDebug(
				"[ConstructionPlanner] End: "
				.. tostring(
					ConstructionPlanner.endTile.x
				)
				.. ", "
				.. tostring(
					ConstructionPlanner.endTile.y
				)
				.. ", "
				.. tostring(
					ConstructionPlanner.endTile.z
				)
			)

			printSelectedTiles()

		else

			cpDebug(
				"[ConstructionPlanner] No dragged end tile captured"
			)
		end

		ConstructionPlanner.selecting =
			false
	end

	ConstructionPlanner.wasBuildButtonDown =
		mouseDown
end

Events.OnTick.Add(
	update
)

Events.OnPostRender.Add(
	renderRemoveSelection
)
