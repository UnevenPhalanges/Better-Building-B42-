------------------------------------------------------------
-- Construction Planner - Dismantle Manager
--
-- Bulk VANILLA Disassemble.
--
-- This file does NOT invent dismantle rules.
--
-- Standard objects:
--   ISMoveableSpriteProps.fromObject(object)
--   -> vanilla structural scrap checks
--   -> vanilla ISMoveableDefinitions scrap tool groups
--   -> vanilla ISMoveablesAction(..., "scrap", ...)
--
-- Special dismantlable IsoThumpables:
--   ISMoveableSpriteProps.fromObject(object)
--   returns vanilla ISThumpableSpriteProps
--   -> vanilla Saw + Screwdriver requirements
--   -> same vanilla ISMoveablesAction "scrap" execution
--
-- Construction Planner only adds:
--   * Area / Line bulk selection
--   * bright persistent selection highlight
--   * aggregate tool display
--   * tool sourcing:
--       player inventory
--       -> Supply Containers
--       -> Gather Area ground items
--   * Confirm Dismantling gate
--   * sequential execution of vanilla Disassemble actions
------------------------------------------------------------

require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISGrabItemAction"
require "Moveables/ISMoveablesAction"
require "Moveables/ISMoveableSpriteProps"
require "Moveables/ISMoveableDefinitions"

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

------------------------------------------------------------
-- STATE
------------------------------------------------------------

ConstructionPlanner.dismantleSelecting =
	false

ConstructionPlanner.dismantleStartTile =
	nil

ConstructionPlanner.dismantleCurrentTile =
	nil

ConstructionPlanner.dismantleDragObjects =
	{}

ConstructionPlanner.dismantleSelectedObjects =
	{}

ConstructionPlanner.dismantleSelectedLookup =
	{}

ConstructionPlanner.dismantleWasBuildButtonDown =
	false

ConstructionPlanner.dismantleRequiredTools =
	{}

ConstructionPlanner.dismantleToolStatus =
	{
		allAvailable = true,
		requirements = {}
	}

ConstructionPlanner.dismantleFetchingTools =
	false

ConstructionPlanner.dismantleRunning =
	false

ConstructionPlanner.dismantleQueue =
	nil

ConstructionPlanner.dismantleQueueIndex =
	0

ConstructionPlanner.dismantleWaitingForAction =
	false

ConstructionPlanner.dismantleBorrowedTools =
	{}

ConstructionPlanner.dismantleToolRefreshCounter =
	0


------------------------------------------------------------
-- BASIC HELPERS
------------------------------------------------------------

local function objectKey(
	object
)
	if not object then
		return nil
	end

	return tostring(
		object
	)
end


local function getPlayer()
	return getSpecificPlayer(0)
end


local function getMouseWorldTile()
	local player =
		getPlayer()

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
		math.floor(wx)

	wy =
		math.floor(wy)

	local square =
		getCell():getGridSquare(
			wx,
			wy,
			z
		)

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
			math.floor(wx)

		wy =
			math.floor(wy)

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
-- VANILLA SCRAP STRUCTURAL ELIGIBILITY
--
-- IMPORTANT:
-- vanilla canScrapObject() also checks whether the tools are
-- currently in the PLAYER inventory.
--
-- Construction Planner is allowed to source those same tools
-- from Supply Containers / Gather Areas, so selection must use
-- the exact VANILLA structural checks separately from the tool
-- availability check.
------------------------------------------------------------

local function standardMovePropsStructurallyScrappable(
	moveProps
)
	if not moveProps
	or not moveProps.canScrap
	or not moveProps.isFromObject
	or not moveProps.object
	or not moveProps.object:getSquare() then
		return false
	end

	local result =
		{}

	local canScrap =
		false

	if moveProps.isMultiSprite then

		local grid =
			moveProps:getSpriteGridInfo(
				moveProps.object:getSquare(),
				true
			)

		if not grid
		or #grid <= 0 then
			return false
		end

		canScrap =
			true

		for _, member in ipairs(
			grid
		) do

			if member.object then

				canScrap =
					moveProps:canScrapObjectInternal(
						result,
						member.object
					)

				if not canScrap then
					break
				end
			end
		end

	else

		canScrap =
			moveProps:canScrapObjectInternal(
				result,
				moveProps.object
			)
	end

	if not canScrap then
		return false
	end

	if moveProps.material then

		local defs =
			ISMoveableDefinitions:getInstance()

		if not defs.isScrapDefinitionValid(
			moveProps.material
		) then

			return false
		end
	end

	return true
end


local function isSpecialThumpableProps(
	moveProps
)
	--------------------------------------------------------
	-- Vanilla ISThumpableSpriteProps has scrapThumpable and
	-- is returned by ISMoveableSpriteProps.fromObject().
	--------------------------------------------------------

	return moveProps
		and moveProps.scrapThumpable
		and true
		or false
end


------------------------------------------------------------
-- VANILLA TOOL REQUIREMENT DESCRIPTORS
------------------------------------------------------------

local function copyTypes(
	source
)
	local out = {}

	for _, value in ipairs(
		source or {}
	) do

		table.insert(
			out,
			value
		)
	end

	return out
end


local function sortedTypesKey(
	types
)
	local copy =
		copyTypes(
			types
		)

	table.sort(
		copy
	)

	return table.concat(
		copy,
		"|"
	)
end


local function getDisplayNamesForTypes(
	moveProps,
	types,
	toolNames
)
	if moveProps
	and moveProps.getToolString
	and toolNames then

		local ok,
			names =
				pcall(
					function()
						return moveProps:getToolString(
							types,
							toolNames
						)
					end
				)

		if ok
		and names
		and #names > 0 then

			return table.concat(
				names,
				" / "
			)
		end
	end

	local simple = {}

	for _, fullType in ipairs(
		types or {}
	) do

		local name =
			string.match(
				tostring(fullType),
				"%.(.+)$"
			)
			or tostring(fullType)

		table.insert(
			simple,
			name
		)
	end

	return table.concat(
		simple,
		" / "
	)
end


local function makeTypeRequirement(
	moveProps,
	types,
	toolNames,
	groupNumber
)
	if not types
	or #types == 0 then
		return nil
	end

	local copied =
		copyTypes(
			types
		)

	return {
		kind = "types",

		key =
			"types:"
			.. sortedTypesKey(
				copied
			),

		label =
			getDisplayNamesForTypes(
				moveProps,
				copied,
				toolNames
			),

		types =
			copied,

		groupNumber =
			groupNumber
	}
end


local function makeTagRequirement(
	tag,
	label
)
	return {
		kind = "tag",

		key =
			"tag:"
			.. tostring(tag),

		label =
			label,

		tag =
			tag
	}
end


------------------------------------------------------------
-- VANILLA REQUIRED TOOLS FOR ONE TARGET
------------------------------------------------------------

local function getVanillaToolRequirements(
	moveProps
)
	local requirements =
		{}

	if not moveProps then
		return requirements
	end

	--------------------------------------------------------
	-- VANILLA SPECIAL THUMPABLE:
	-- ISThumpableSpriteProps:walkToAndEquip() requires
	-- one non-broken SAW and one non-broken SCREWDRIVER.
	--------------------------------------------------------

	if isSpecialThumpableProps(
		moveProps
	) then

		table.insert(
			requirements,
			makeTagRequirement(
				ItemTag.SAW,
				"Saw"
			)
		)

		table.insert(
			requirements,
			makeTagRequirement(
				ItemTag.SCREWDRIVER,
				"Screwdriver"
			)
		)

		return requirements
	end

	--------------------------------------------------------
	-- NORMAL VANILLA MOVEABLE SCRAP DEFINITION.
	--------------------------------------------------------

	if not moveProps.scrapUseTool then
		return requirements
	end

	local defs =
		ISMoveableDefinitions:getInstance()

	local scrapDef =
		defs.getScrapDefinition(
			moveProps.material
		)

	if not scrapDef then
		return requirements
	end

	local req1 =
		makeTypeRequirement(
			moveProps,
			scrapDef.tools,
			scrapDef.toolNames,
			1
		)

	if req1 then
		table.insert(
			requirements,
			req1
		)
	end

	local req2 =
		makeTypeRequirement(
			moveProps,
			scrapDef.tools2,
			scrapDef.toolNames,
			2
		)

	if req2 then
		table.insert(
			requirements,
			req2
		)
	end

	return requirements
end


------------------------------------------------------------
-- DISMANTLE-MODE EXCLUSIONS
--
-- These objects may have moveable/scrap metadata, but they are
-- environmental cleanup rather than furniture/construction.
-- Keep them out of Dismantle so a later Cleanup tool can own them.
------------------------------------------------------------

local function isEnvironmentalClutter(
	object,
	moveProps
)
	if not object then
		return true
	end

	--------------------------------------------------------
	-- Vanilla moveable vegetation category.
	--------------------------------------------------------

	if moveProps
	and moveProps.type
	and tostring(moveProps.type)
		== "Vegitation" then
		return true
	end

	local sprite =
		object.getSprite
		and object:getSprite()
		or nil

	local props =
		sprite
		and sprite:getProperties()
		or nil

	--------------------------------------------------------
	-- Common vegetation / natural-ground sprite flags.
	--------------------------------------------------------

	if props then
		if props:has("vegetation")
		or props:has("Vegetation")
		or props:has("Bush")
		or props:has("Tree")
		or props:has("NaturalFloor") then
			return true
		end
	end

	--------------------------------------------------------
	-- Conservative sprite-name filter for world clutter.
	-- This deliberately targets only obvious environmental
	-- categories, not furniture or player construction.
	--------------------------------------------------------

	local spriteName =
		sprite
		and sprite:getName()
		or ""

	local name =
		string.lower(
			tostring(spriteName)
		)

	if string.find(name, "vegetation_", 1, true)
	or string.find(name, "blends_natural_", 1, true)
	or string.find(name, "d_floorleaves_", 1, true)
	or string.find(name, "d_trash_", 1, true)
	or string.find(name, "trash_", 1, true)
	or string.find(name, "debris_", 1, true)
	or string.find(name, "grass_", 1, true) then
		return true
	end

	return false
end


------------------------------------------------------------
-- VANILLA TARGET DESCRIPTOR
------------------------------------------------------------

local function getDismantleTarget(
	object,
	square
)
	if not object
	or not square then
		return nil
	end

	local ok,
		moveProps =
			pcall(
				ISMoveableSpriteProps.fromObject,
				object
			)

	if not ok
	or not moveProps then
		return nil
	end

	if isEnvironmentalClutter(
		object,
		moveProps
	) then
		return nil
	end

	--------------------------------------------------------
	-- SPECIAL VANILLA DISMANTLABLE THUMPABLE
	--------------------------------------------------------

	if isSpecialThumpableProps(
		moveProps
	) then

		return {
			object = object,
			square = square,
			moveProps = moveProps,
			spriteName =
				moveProps.spriteName,
			requirements =
				getVanillaToolRequirements(
					moveProps
				)
		}
	end

	--------------------------------------------------------
	-- NORMAL VANILLA DISASSEMBLE TARGET
	--------------------------------------------------------

	if not standardMovePropsStructurallyScrappable(
		moveProps
	) then
		return nil
	end

	return {
		object = object,
		square = square,
		moveProps = moveProps,
		spriteName =
			moveProps.spriteName,
		requirements =
			getVanillaToolRequirements(
				moveProps
			)
	}
end


------------------------------------------------------------
-- COLLECT VANILLA DISASSEMBLE TARGETS FROM SQUARES
------------------------------------------------------------

local function collectSquareObjects(
	tile,
	results,
	lookup
)
	if not tile then
		return
	end

	local square =
		getCell():getGridSquare(
			tile.x,
			tile.y,
			tile.z
		)

	if not square then
		return
	end

	local objects =
		square:getObjects()

	if not objects then
		return
	end

	local floor =
		square:getFloor()

	for i = 0,
		objects:size() - 1 do

		local object =
			objects:get(i)

		if object
		and object ~= floor then

			local target =
				getDismantleTarget(
					object,
					square
				)

			if target then

				local key =
					objectKey(
						object
					)

				if key
				and not lookup[key] then

					lookup[key] =
						true

					target.x =
						tile.x

					target.y =
						tile.y

					target.z =
						tile.z

					table.insert(
						results,
						target
					)
				end
			end
		end
	end
end


local function collectObjectsFromTiles(
	tiles
)
	local results =
		{}

	local lookup =
		{}

	for _, tile in ipairs(
		tiles or {}
	) do

		collectSquareObjects(
			tile,
			results,
			lookup
		)
	end

	return results
end


------------------------------------------------------------
-- SELECTION
------------------------------------------------------------

local function refreshDismantleDrag(
	currentTile
)
	if not ConstructionPlanner.dismantleStartTile
	or not currentTile then
		return
	end

	if currentTile.z
	~= ConstructionPlanner.dismantleStartTile.z then
		return
	end

	ConstructionPlanner.dismantleCurrentTile = {
		x = currentTile.x,
		y = currentTile.y,
		z = currentTile.z
	}

	if not ConstructionPlanner.getSelectionTiles then
		return
	end

	local tiles =
		ConstructionPlanner.getSelectionTiles(
			ConstructionPlanner.dismantleStartTile,
			ConstructionPlanner.dismantleCurrentTile
		)

	ConstructionPlanner.dismantleDragObjects =
		collectObjectsFromTiles(
			tiles
		)
end


local function rebuildSelectedList()
	ConstructionPlanner.dismantleSelectedObjects =
		{}

	for _, target in pairs(
		ConstructionPlanner.dismantleSelectedLookup
	) do

		table.insert(
			ConstructionPlanner.dismantleSelectedObjects,
			target
		)
	end
end


------------------------------------------------------------
-- TOOL ITEM VALIDITY
------------------------------------------------------------

local function isUsableScrapItem(
	item
)
	if not item then
		return false
	end

	if item.isBroken
	and item:isBroken() then
		return false
	end

	if item.getFullType
	and item:getFullType()
		== "Base.BlowTorch" then

		if not item.getCurrentUsesFloat then
			return false
		end

		return item:getCurrentUsesFloat()
			>= 0.1
	end

	return true
end


local function itemMatchesRequirement(
	item,
	requirement
)
	if not item
	or not requirement
	or not isUsableScrapItem(
		item
	) then
		return false
	end

	if requirement.kind
	== "types" then

		local fullType =
			item.getFullType
			and item:getFullType()
			or nil

		if not fullType then
			return false
		end

		for _, acceptedType in ipairs(
			requirement.types
			or {}
		) do

			if fullType
			== acceptedType then
				return true
			end
		end

		return false
	end

	if requirement.kind
	== "tag" then

		if item.hasTag then

			local ok,
				has =
					pcall(
						function()
							return item:hasTag(
								requirement.tag
							)
						end
					)

			if ok
			and has then
				return true
			end
		end

		return false
	end

	return false
end


local function findItemInContainer(
	container,
	requirement
)
	if not container then
		return nil
	end

	local items =
		container:getItems()

	if not items then
		return nil
	end

	for i = 0,
		items:size() - 1 do

		local item =
			items:get(i)

		if itemMatchesRequirement(
			item,
			requirement
		) then

			return item
		end
	end

	return nil
end


------------------------------------------------------------
-- FIND A REQUIRED TOOL USING CP SOURCE PRIORITY
------------------------------------------------------------

local function findRequirementSource(
	requirement
)
	local player =
		getPlayer()

	if not player then
		return nil
	end

	--------------------------------------------------------
	-- 1. PLAYER INVENTORY
	--------------------------------------------------------

	local item =
		findItemInContainer(
			player:getInventory(),
			requirement
		)

	if item then

		return {
			kind = "inventory",
			item = item,
			label = "Carried"
		}
	end

	--------------------------------------------------------
	-- 2. SUPPLY CONTAINERS
	--------------------------------------------------------

	if ConstructionPlanner.getSupplyContainers then

		local containers =
			ConstructionPlanner.getSupplyContainers()

		for _, container in ipairs(
			containers or {}
		) do

			item =
				findItemInContainer(
					container,
					requirement
				)

			if item then

				return {
					kind = "supply",
					item = item,
					container = container,
					label = "Supply Container"
				}
			end
		end
	end

	--------------------------------------------------------
	-- 3. GATHER AREA GROUND ITEMS
	--------------------------------------------------------

	if ConstructionPlanner.getGroundItemsInGatherAreas then

		local entries =
			ConstructionPlanner.getGroundItemsInGatherAreas(
				nil,
				nil
			)

		for _, entry in ipairs(
			entries or {}
		) do

			if entry.item
			and itemMatchesRequirement(
				entry.item,
				requirement
			) then

				return {
					kind = "gather",
					item = entry.item,
					worldObject =
						entry.worldObject,
					square =
						entry.square,
					label = "Gather Area"
				}
			end
		end
	end

	return nil
end


------------------------------------------------------------
-- AGGREGATE VANILLA TOOL GROUPS
------------------------------------------------------------

local function rebuildRequiredTools()
	local requirements =
		{}

	local lookup =
		{}

	for _, target in ipairs(
		ConstructionPlanner.dismantleSelectedObjects
		or {}
	) do

		for _, requirement in ipairs(
			target.requirements
			or {}
		) do

			if requirement
			and requirement.key
			and not lookup[
				requirement.key
			] then

				lookup[
					requirement.key
				] =
					true

				table.insert(
					requirements,
					requirement
				)
			end
		end
	end

	ConstructionPlanner.dismantleRequiredTools =
		requirements
end


function ConstructionPlanner.refreshDismantleToolStatus()
	rebuildRequiredTools()

	local status = {
		allAvailable = true,
		requirements = {}
	}

	for _, requirement in ipairs(
		ConstructionPlanner.dismantleRequiredTools
		or {}
	) do

		local source =
			findRequirementSource(
				requirement
			)

		if not source then

			status.allAvailable =
				false
		end

		table.insert(
			status.requirements,
			{
				key =
					requirement.key,

				label =
					requirement.label,

				available =
					source ~= nil,

				source =
					source,

				sourceLabel =
					source
					and source.label
					or "Missing",

				requirement =
					requirement
			}
		)
	end

	ConstructionPlanner.dismantleToolStatus =
		status

	return status
end


function ConstructionPlanner.getDismantleToolStatus()
	return ConstructionPlanner.dismantleToolStatus
		or {
			allAvailable = true,
			requirements = {}
		}
end


function ConstructionPlanner.canConfirmDismantling()
	if ConstructionPlanner.dismantleRunning
	or ConstructionPlanner.dismantleFetchingTools then
		return false
	end

	if #(
		ConstructionPlanner.dismantleSelectedObjects
		or {}
	) == 0 then
		return false
	end

	local status =
		ConstructionPlanner.refreshDismantleToolStatus()

	return status
		and status.allAvailable
		or false
end


------------------------------------------------------------
-- COMMIT / CLEAR SELECTION
------------------------------------------------------------

local function commitDismantleDrag()
	for _, target in ipairs(
		ConstructionPlanner.dismantleDragObjects
		or {}
	) do

		local key =
			objectKey(
				target.object
			)

		if key then

			if ConstructionPlanner.dismantleSelectedLookup[
				key
			] then

				ConstructionPlanner.dismantleSelectedLookup[
					key
				] =
					nil

			else

				ConstructionPlanner.dismantleSelectedLookup[
					key
				] =
					target
			end
		end
	end

	ConstructionPlanner.dismantleDragObjects =
		{}

	rebuildSelectedList()

	ConstructionPlanner.refreshDismantleToolStatus()
end


function ConstructionPlanner.clearDismantleSelection()
	ConstructionPlanner.dismantleSelecting =
		false

	ConstructionPlanner.dismantleStartTile =
		nil

	ConstructionPlanner.dismantleCurrentTile =
		nil

	ConstructionPlanner.dismantleDragObjects =
		{}

	ConstructionPlanner.dismantleSelectedObjects =
		{}

	ConstructionPlanner.dismantleSelectedLookup =
		{}

	ConstructionPlanner.dismantleRequiredTools =
		{}

	ConstructionPlanner.dismantleToolStatus = {
		allAvailable = true,
		requirements = {}
	}
end


function ConstructionPlanner.getDismantleSelectionCount()
	return #(
		ConstructionPlanner.dismantleSelectedObjects
		or {}
	)
end


------------------------------------------------------------
-- BRIGHT SELECTION HIGHLIGHT
------------------------------------------------------------

local function highlightTarget(
	target,
	committed
)
	if not target
	or not target.object then
		return
	end

	local object =
		target.object

	if not object.setHighlightColor
	or not object.setHighlighted then
		return
	end

	--------------------------------------------------------
	-- Intentionally much brighter than vanilla.
	--------------------------------------------------------

	if committed then

		object:setHighlightColor(
			1.0,
			0.05,
			0.02,
			1.0
		)

	else

		object:setHighlightColor(
			1.0,
			0.82,
			0.02,
			1.0
		)
	end

	object:setHighlighted(
		true,
		true
	)
end


------------------------------------------------------------
-- DISMANTLE DRAG GROUND HIGHLIGHT
--
-- Same rectangle-floor highlight pattern used by Gather Area.
-- It highlights the entire dragged rectangle while the mouse
-- is held, not just squares containing dismantlable objects.
------------------------------------------------------------

local function drawDismantleDragGround()
	if not ConstructionPlanner.dismantleSelecting
	or not ConstructionPlanner.dismantleStartTile
	or not ConstructionPlanner.dismantleCurrentTile then
		return
	end

	local startTile =
		ConstructionPlanner.dismantleStartTile

	local endTile =
		ConstructionPlanner.dismantleCurrentTile

	if startTile.z ~= endTile.z then
		return
	end

	local x1 =
		math.min(
			startTile.x,
			endTile.x
		)

	local y1 =
		math.min(
			startTile.y,
			endTile.y
		)

	local x2 =
		math.max(
			startTile.x,
			endTile.x
		)

	local y2 =
		math.max(
			startTile.y,
			endTile.y
		)

	for x = x1, x2 do
		for y = y1, y2 do

			local square =
				getCell():getGridSquare(
					x,
					y,
					startTile.z
				)

			local floor =
				square
				and square:getFloor()
				or nil

			if floor then

				floor:setHighlightColor(
					1.0,
					0.82,
					0.02,
					0.42
				)

				floor:setHighlighted(
					true,
					true
				)
			end
		end
	end
end


local function renderDismantleSelection()
	if ConstructionPlanner.projectPanelPage
	~= "dismantle" then
		return
	end

	--------------------------------------------------------
	-- TEMPORARY DRAG RECTANGLE GROUND HIGHLIGHT
	--------------------------------------------------------

	drawDismantleDragGround()

	for _, target in ipairs(
		ConstructionPlanner.dismantleSelectedObjects
		or {}
	) do

		highlightTarget(
			target,
			true
		)
	end

	for _, target in ipairs(
		ConstructionPlanner.dismantleDragObjects
		or {}
	) do

		local key =
			objectKey(
				target.object
			)

		if not key
		or not ConstructionPlanner.dismantleSelectedLookup[
			key
		] then

			highlightTarget(
				target,
				false
			)
		end
	end
end


------------------------------------------------------------
-- MOUSE SELECTION UPDATE
------------------------------------------------------------

local function updateDismantleSelection()
	if ConstructionPlanner.projectPanelPage
	~= "dismantle" then

		ConstructionPlanner.dismantleWasBuildButtonDown =
			false

		if ConstructionPlanner.dismantleSelecting then

			ConstructionPlanner.dismantleSelecting =
				false

			ConstructionPlanner.dismantleDragObjects =
				{}
		end

		return
	end

	if ConstructionPlanner.dismantleRunning
	or ConstructionPlanner.dismantleFetchingTools then

		ConstructionPlanner.dismantleWasBuildButtonDown =
			false

		return
	end

	local player =
		getPlayer()

	if not player then
		return
	end

	local mouseDown =
		player:isBuildButtonDown()

	if mouseDown
	and not ConstructionPlanner.dismantleWasBuildButtonDown then

		local tile =
			getMouseWorldTile()

		if tile then

			ConstructionPlanner.dismantleSelecting =
				true

			ConstructionPlanner.dismantleStartTile = {
				x = tile.x,
				y = tile.y,
				z = tile.z
			}

			ConstructionPlanner.dismantleCurrentTile = {
				x = tile.x,
				y = tile.y,
				z = tile.z
			}

			refreshDismantleDrag(
				tile
			)
		end
	end

	if ConstructionPlanner.dismantleSelecting
	and mouseDown then

		local tile =
			getMouseWorldTile()

		if tile then

			refreshDismantleDrag(
				tile
			)
		end
	end

	if ConstructionPlanner.dismantleSelecting
	and ConstructionPlanner.dismantleWasBuildButtonDown
	and not mouseDown then

		local endTile =
			ConstructionPlanner.dismantleCurrentTile
			or getMouseWorldTile()

		if endTile then

			refreshDismantleDrag(
				endTile
			)

			commitDismantleDrag()
		end

		ConstructionPlanner.dismantleSelecting =
			false

		ConstructionPlanner.dismantleStartTile =
			nil

		ConstructionPlanner.dismantleCurrentTile =
			nil
	end

	ConstructionPlanner.dismantleWasBuildButtonDown =
		mouseDown
end


------------------------------------------------------------
-- TOOL PICKUP
------------------------------------------------------------

local function queueSupplyPickup(
	player,
	row
)
	local source =
		row.source

	if not source
	or not source.container
	or not source.item then
		return false
	end

	local container =
		source.container

	local item =
		source.item

	--------------------------------------------------------
	-- Use the same vanilla walk-to-container helper that CP's
	-- ToolManager already uses when available.
	--------------------------------------------------------

	if luautils
	and luautils.walkToContainer then

		if not luautils.walkToContainer(
			container,
			player:getPlayerNum()
		) then

			return false
		end

	else

		return false
	end

	local action =
		ISInventoryTransferUtil.newInventoryTransferAction(
			player,
			item,
			container,
			player:getInventory()
		)

	if not action then
		return false
	end

	ISTimedActionQueue.add(
		action
	)

	table.insert(
		ConstructionPlanner.dismantleBorrowedTools,
		{
			item = item,
			sourceContainer = container
		}
	)

	return true
end


local function queueGatherPickup(
	player,
	row
)
	local source =
		row.source

	if not source
	or not source.worldObject
	or not source.square then
		return false
	end

	if not luautils.walkAdj(
		player,
		source.square,
		false
	) then
		return false
	end

	local action =
		ISGrabItemAction:new(
			player,
			source.worldObject,
			10
		)

	if not action then
		return false
	end

	ISTimedActionQueue.add(
		action
	)

	return true
end


local function queueMissingToolPickups(
	status
)
	local player =
		getPlayer()

	if not player then
		return false,
			false
	end

	local queuedAny =
		false

	ConstructionPlanner.dismantleBorrowedTools =
		{}

	for _, row in ipairs(
		status.requirements
		or {}
	) do

		local source =
			row.source

		if not source then
			return false,
				queuedAny
		end

		if source.kind == "supply" then

			if not queueSupplyPickup(
				player,
				row
			) then

				return false,
					queuedAny
			end

			queuedAny =
				true

		elseif source.kind == "gather" then

			if not queueGatherPickup(
				player,
				row
			) then

				return false,
					queuedAny
			end

			queuedAny =
				true
		end
	end

	return true,
		queuedAny
end


------------------------------------------------------------
-- CONTINUOUS SPEED-3 DISMANTLE QUEUE
--
-- This mirrors the current working ProjectBuilder:
--
--   walk/equip (keepActions=true)
--       -> CP prepare action
--       -> vanilla ISMoveablesAction("scrap")
--       -> addAfter(CP continuation)
--       -> next walk/equip
--
-- Progression is NOT driven by OnTick queue polling.
------------------------------------------------------------

ConstructionPlanner.dismantleReturningTools =
	false

ConstructionPlanner.dismantleQueueDebugLast =
	nil


------------------------------------------------------------
-- REVALIDATE ONE TARGET
------------------------------------------------------------

local function refreshTarget(
	oldTarget
)
	if not oldTarget
	or not oldTarget.object then
		return nil
	end

	local square =
		oldTarget.object:getSquare()

	if not square then
		return nil
	end

	return getDismantleTarget(
		oldTarget.object,
		square
	)
end


------------------------------------------------------------
-- CP SPEED-3 WALK VALIDITY
--
-- Vanilla ISWalkToTimedAction can invalidate itself at higher
-- game speeds. Construction Planner's working build/distribution
-- walk class fixes that by allowing the walk while game speed
-- is <= 3.
--
-- Dismantle uses vanilla adjacency helpers because they know
-- which adjacent square is valid for doors/windows/multitiles.
-- After the helper queues its walk, we patch THAT exact walk
-- action with the same CP isValid rule instead of replacing
-- the adjacency/path-selection logic.
------------------------------------------------------------

local function markLatestDismantleWalk(
	player
)
	if not player then
		return false
	end

	local queue =
		ISTimedActionQueue.getTimedActionQueue(
			player
		)

	if not queue
	or not queue.queue then
		return false
	end

	--------------------------------------------------------
	-- Find the newest queued ISWalkToTimedAction.
	--------------------------------------------------------

	for i = #queue.queue, 1, -1 do

		local action =
			queue.queue[i]

		if action
		and (
			action.Type == "ISWalkToTimedAction"
			or action.Type == "ISConstructionPlannerWalkToTimedAction"
			or action.Type == "ISConstructionPlannerDismantleWalkToTimedAction"
		) then

			action.constructionPlannerWalk =
				true

			action.constructionPlannerDismantleWalk =
				true

			------------------------------------------------
			-- EXACT CP SPEED-3 WALK VALIDITY RULE.
			------------------------------------------------

			action.isValid = function(self)

				if self.character:getVehicle() then
					return false
				end

				return getGameSpeed() <= 3
			end

			cpDebug(
				"[ConstructionPlanner] Dismantle walk marked for Speed 3"
			)

			return true
		end
	end

	cpDebug(
		"[ConstructionPlanner] WARNING: could not find queued Dismantle walk to mark"
	)

	return false
end


------------------------------------------------------------
-- QUEUE-PRESERVING VANILLA DISASSEMBLE WALK / EQUIP
--
-- This copies the behavior of vanilla
-- ISMoveableSpriteProps:walkToAndEquip(..., "scrap", ...)
-- but deliberately uses keepActions=true.
--
-- That is the same queue-ownership rule used by the working
-- ProjectBuilder's walkAdj(..., true).
------------------------------------------------------------

local function queueVanillaScrapWalkAndEquip(
	player,
	target
)
	if not player
	or not target
	or not target.moveProps
	or not target.square then
		return false
	end

	local moveProps =
		target.moveProps

	local square =
		target.square

	local function finalizeWalk(
		walkQueued
	)
		if not walkQueued then
			return false
		end

		if not markLatestDismantleWalk(
			player
		) then
			return false
		end

		return true
	end

	--------------------------------------------------------
	-- IMPORTANT:
	-- DO NOT CALL ISWorldObjectContextMenu.equip() HERE.
	--
	-- In Build 42.20 the context-menu equip helper inserts
	-- its own timed-action behavior and is breaking the
	-- continuous CP queue before PrepareDismantle can run.
	--
	-- CP has already validated and fetched the exact vanilla
	-- scrap tools into the player's inventory. Here we only:
	--
	--   1. verify those tools are still present
	--   2. queue the vanilla-style walk with keepActions=true
	--
	-- The actual vanilla ISMoveablesAction("scrap") remains
	-- responsible for the Disassemble operation itself.
	--------------------------------------------------------

	--------------------------------------------------------
	-- SPECIAL THUMPABLE:
	-- vanilla requires Saw + Screwdriver.
	--------------------------------------------------------

	if moveProps.scrapThumpable then

		local saw =
			player:getInventory():getFirstTagEvalRecurse(
				ItemTag.SAW,
				predicateNotBroken
			)

		if not saw then
			return false
		end

		local screwdriver =
			player:getInventory():getFirstTagEvalRecurse(
				ItemTag.SCREWDRIVER,
				predicateNotBroken
			)

		if not screwdriver then
			return false
		end

		return finalizeWalk(
			luautils.walkAdj(
				player,
				square,
				true
			)
		)
	end

	--------------------------------------------------------
	-- NORMAL MOVEABLE:
	-- verify the same vanilla scrap-tool groups.
	--------------------------------------------------------

	local tool =
		moveProps:hasScrapTool(
			player,
			false
		)

	if tool == false
	or tool == nil then
		return false
	end

	local tool2 =
		moveProps:hasScrapTool(
			player,
			true
		)

	if tool2 == false
	or tool2 == nil then
		return false
	end

	--------------------------------------------------------
	-- QUEUE-PRESERVING VANILLA WALK
	--------------------------------------------------------

	local keepActions =
		true

	if moveProps.type == "Window"
	or moveProps.type == "WindowObject" then

		local dir =
			moveProps.facing

		if moveProps.type == "Window" then

			local isNorth =
				moveProps.facing
				and (
					moveProps.facing == "N"
					or moveProps.facing == "S"
				)
				or false

			dir =
				isNorth
				and "S"
				or "E"
		end

		local windowFrame =
			moveProps:getWallForFacing(
				square,
				dir,
				"WindowFrame"
			)

		return finalizeWalk(
			windowFrame
			and luautils.walkAdjWindowOrDoor(
				player,
				square,
				windowFrame,
				keepActions
			)
			or false
		)
	end

	if moveProps.object
	and (
		instanceof(
			moveProps.object,
			"IsoDoor"
		)
		or (
			instanceof(
				moveProps.object,
				"IsoThumpable"
			)
			and moveProps.object:isDoor()
		)
	) then

		return finalizeWalk(
			luautils.walkAdjWindowOrDoor(
				player,
				square,
				moveProps.object,
				keepActions
			)
		)
	end

	if moveProps.object
	and moveProps.object:getType()
		== IsoObjectType.wall then

		return finalizeWalk(
			luautils.walkAdjWindowOrDoor(
				player,
				square,
				moveProps.object,
				keepActions
			)
		)
	end

	local walked =
		moveProps:walkAdj(
			player,
			square,
			keepActions
		)

	return finalizeWalk(
		walked
	)
end


------------------------------------------------------------
-- PREPARE ACTION
--
-- Queued after walk/equip. While THIS action is still current,
-- it queues the real vanilla scrap action. Completing this
-- action immediately hands control to vanilla with no empty
-- queue transition.
------------------------------------------------------------

ISConstructionPlannerPrepareDismantle =
	ISBaseTimedAction:derive(
		"ISConstructionPlannerPrepareDismantle"
	)

function ISConstructionPlannerPrepareDismantle:isValid()
	return self.character ~= nil
		and ConstructionPlanner.dismantleRunning
		and self.target ~= nil
end

function ISConstructionPlannerPrepareDismantle:begin()
	cpDebug("[CP DISMANTLE DEBUG] PrepareDismantle:begin")
	ISBaseTimedAction.begin(self)
end

function ISConstructionPlannerPrepareDismantle:update()
end

function ISConstructionPlannerPrepareDismantle:start()
	cpDebug("[CP DISMANTLE DEBUG] PrepareDismantle:start")
end

function ISConstructionPlannerPrepareDismantle:stop()
	ISBaseTimedAction.stop(
		self
	)
end

function ISConstructionPlannerPrepareDismantle:perform()
	cpDebug("[CP DISMANTLE DEBUG] PrepareDismantle:perform")
	if not ConstructionPlanner.dismantleRunning then

		ISBaseTimedAction.perform(
			self
		)

		return
	end

	local target =
		refreshTarget(
			self.target
		)

	if not target then

		cpDebug(
			"[ConstructionPlanner] Dismantle target no longer valid - continuing"
		)

		ConstructionPlanner.dismantleQueueIndex =
			ConstructionPlanner.dismantleQueueIndex
			+ 1

		local queue =
			ConstructionPlanner.dismantleQueue

		if queue
		and ConstructionPlanner.dismantleQueueIndex
			<= #queue then

			ConstructionPlanner.queueCurrentDismantleTarget()
		else
			ConstructionPlanner.finishDismantleRun()
		end

		ISBaseTimedAction.perform(
			self
		)

		return
	end

	local direction =
		target.object.getDir
		and target.object:getDir()
		or IsoDirections.N

	local action =
		ISMoveablesAction:new(
			self.character,
			target.square,
			"scrap",
			target.spriteName,
			target.object,
			direction,
			nil,
			nil
		)

	if not action then

		cpDebug(
			"[ConstructionPlanner] Could not create vanilla Disassemble action"
		)

		ConstructionPlanner.dismantleQueueIndex =
			ConstructionPlanner.dismantleQueueIndex
			+ 1

		local queue =
			ConstructionPlanner.dismantleQueue

		if queue
		and ConstructionPlanner.dismantleQueueIndex
			<= #queue then

			ConstructionPlanner.queueCurrentDismantleTarget()
		else
			ConstructionPlanner.finishDismantleRun()
		end

		ISBaseTimedAction.perform(
			self
		)

		return
	end

	action.constructionPlannerDismantle =
		true

	action.constructionPlannerDismantleIndex =
		ConstructionPlanner.dismantleQueueIndex

	cpDebug(
		"[ConstructionPlanner] Vanilla Disassemble "
		.. tostring(
			ConstructionPlanner.dismantleQueueIndex
		)
		.. " / "
		.. tostring(
			#ConstructionPlanner.dismantleQueue
		)
	)

	--------------------------------------------------------
	-- Queue vanilla scrap WHILE prepare is still current.
	--------------------------------------------------------

	ISTimedActionQueue.add(
		action
	)

	ISBaseTimedAction.perform(
		self
	)
end

function ISConstructionPlannerPrepareDismantle:new(
	character,
	target
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

	o.target =
		target

	o.stopOnWalk =
		false

	o.stopOnRun =
		false

	o.maxTime =
		1

	return o
end


------------------------------------------------------------
-- QUEUE CURRENT TARGET
------------------------------------------------------------

function ConstructionPlanner.queueCurrentDismantleTarget()
	if not ConstructionPlanner.dismantleRunning then
		return false
	end

	local queue =
		ConstructionPlanner.dismantleQueue

	local index =
		ConstructionPlanner.dismantleQueueIndex

	if not queue
	or index < 1
	or index > #queue then

		return false
	end

	local target =
		refreshTarget(
			queue[index]
		)

	if not target then

		cpDebug(
			"[ConstructionPlanner] Dismantle target "
			.. tostring(index)
			.. " no longer valid - skipping"
		)

		ConstructionPlanner.dismantleQueueIndex =
			index + 1

		if ConstructionPlanner.dismantleQueueIndex
		<= #queue then

			return ConstructionPlanner.queueCurrentDismantleTarget()
		end

		ConstructionPlanner.finishDismantleRun()

		return false
	end

	--------------------------------------------------------
	-- QUEUE VANILLA-STYLE WALK + TOOL EQUIP, PRESERVING THE
	-- EXISTING CP ACTION QUEUE.
	--------------------------------------------------------

	if not queueVanillaScrapWalkAndEquip(
		getPlayer(),
		target
	) then

		cpDebug(
			"[ConstructionPlanner] Could not prepare Disassemble target "
			.. tostring(index)
			.. " - skipping"
		)

		ConstructionPlanner.dismantleQueueIndex =
			index + 1

		if ConstructionPlanner.dismantleQueueIndex
		<= #queue then

			return ConstructionPlanner.queueCurrentDismantleTarget()
		end

		ConstructionPlanner.finishDismantleRun()

		return false
	end

	--------------------------------------------------------
	-- PREPARE ACTION GOES DIRECTLY BEHIND WALK / EQUIP.
	--------------------------------------------------------

	ISTimedActionQueue.add(
		ISConstructionPlannerPrepareDismantle:new(
			getPlayer(),
			target
		)
	)

	cpDebug(
		"[ConstructionPlanner] Preparing Disassemble "
		.. tostring(index)
		.. " / "
		.. tostring(#queue)
	)

	return true
end


------------------------------------------------------------
-- CONTINUATION ACTION
--
-- Inserted directly after each successful vanilla scrap action
-- by the perform hook below. It queues the next target BEFORE
-- completing, exactly like ProjectBuilder.
------------------------------------------------------------

ISConstructionPlannerContinueDismantle =
	ISBaseTimedAction:derive(
		"ISConstructionPlannerContinueDismantle"
	)

function ISConstructionPlannerContinueDismantle:isValid()
	return self.character ~= nil
end

function ISConstructionPlannerContinueDismantle:update()
end

function ISConstructionPlannerContinueDismantle:start()
end

function ISConstructionPlannerContinueDismantle:stop()
	ISBaseTimedAction.stop(
		self
	)
end

function ISConstructionPlannerContinueDismantle:perform()
	if not ConstructionPlanner.dismantleRunning then

		ISBaseTimedAction.perform(
			self
		)

		return
	end

	cpDebug(
		"[ConstructionPlanner] Disassemble completed "
		.. tostring(
			ConstructionPlanner.dismantleQueueIndex
		)
		.. " / "
		.. tostring(
			ConstructionPlanner.dismantleQueue
			and #ConstructionPlanner.dismantleQueue
			or 0
		)
	)

	ConstructionPlanner.dismantleQueueIndex =
		ConstructionPlanner.dismantleQueueIndex
		+ 1

	local queue =
		ConstructionPlanner.dismantleQueue

	if queue
	and ConstructionPlanner.dismantleQueueIndex
		<= #queue then

		----------------------------------------------------
		-- Queue next walk/equip/prepare BEFORE this
		-- continuation action completes.
		----------------------------------------------------

		ConstructionPlanner.queueCurrentDismantleTarget()

	else

		ConstructionPlanner.finishDismantleRun()
	end

	ISBaseTimedAction.perform(
		self
	)
end

function ISConstructionPlannerContinueDismantle:new(
	character
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

	o.stopOnWalk =
		false

	o.stopOnRun =
		false

	o.maxTime =
		1

	return o
end


------------------------------------------------------------
-- VANILLA SCRAP PERFORM HOOK
--
-- This is the Dismantle equivalent of ProjectBuilder's
-- ISBuildAction.perform hook.
------------------------------------------------------------

local function ensureDismantlePerformHook()
	if ConstructionPlanner.dismantlePerformHooked then
		return
	end

	if not ISMoveablesAction
	or not ISMoveablesAction.perform then
		return
	end

	ConstructionPlanner.originalDismantleMoveablesPerform =
		ISMoveablesAction.perform

	ISMoveablesAction.perform = function(self)

		if self
		and self.constructionPlannerDismantle
		and ConstructionPlanner.dismantleRunning then

			------------------------------------------------
			-- Insert continuation immediately after THIS
			-- vanilla scrap action before vanilla removes it.
			------------------------------------------------

			ISTimedActionQueue.addAfter(
				self,
				ISConstructionPlannerContinueDismantle:new(
					self.character
				)
			)
		end

		return ConstructionPlanner.originalDismantleMoveablesPerform(
			self
		)
	end

	ConstructionPlanner.dismantlePerformHooked =
		true

	cpDebug(
		"[ConstructionPlanner] Dismantle perform hook installed"
	)
end


------------------------------------------------------------
-- BORROWED TOOL RETURN
------------------------------------------------------------

local function queueBorrowedToolReturns()
	local borrowed =
		ConstructionPlanner.dismantleBorrowedTools
		or {}

	if #borrowed == 0 then
		return false
	end

	local player =
		getPlayer()

	if not player then
		return false
	end

	local queued =
		false

	for _, entry in ipairs(
		borrowed
	) do

		if entry.item
		and entry.sourceContainer
		and entry.item:getContainer()
			== player:getInventory() then

			if luautils.walkToContainer(
				entry.sourceContainer,
				player:getPlayerNum()
			) then

				local action =
					ISInventoryTransferUtil.newInventoryTransferAction(
						player,
						entry.item,
						player:getInventory(),
						entry.sourceContainer
					)

				if action then

					ISTimedActionQueue.add(
						action
					)

					queued =
						true
				end
			end
		end
	end

	ConstructionPlanner.dismantleBorrowedTools =
		{}

	return queued
end


------------------------------------------------------------
-- FINISH RETURN SENTINEL
------------------------------------------------------------

ISConstructionPlannerFinishDismantleReturn =
	ISBaseTimedAction:derive(
		"ISConstructionPlannerFinishDismantleReturn"
	)

function ISConstructionPlannerFinishDismantleReturn:isValid()
	return self.character ~= nil
end

function ISConstructionPlannerFinishDismantleReturn:update()
end

function ISConstructionPlannerFinishDismantleReturn:start()
end

function ISConstructionPlannerFinishDismantleReturn:stop()
	ConstructionPlanner.dismantleReturningTools =
		false

	ISBaseTimedAction.stop(
		self
	)
end

function ISConstructionPlannerFinishDismantleReturn:perform()
	ConstructionPlanner.dismantleReturningTools =
		false

	cpDebug(
		"[ConstructionPlanner] Borrowed dismantle tools returned"
	)

	ISBaseTimedAction.perform(
		self
	)
end

function ISConstructionPlannerFinishDismantleReturn:new(
	character
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

	o.stopOnWalk =
		false

	o.stopOnRun =
		false

	o.maxTime =
		1

	return o
end


------------------------------------------------------------
-- FINISH RUN
------------------------------------------------------------

function ConstructionPlanner.finishDismantleRun()
	ConstructionPlanner.dismantleRunning =
		false

	ConstructionPlanner.dismantleFetchingTools =
		false

	ConstructionPlanner.dismantleQueue =
		nil

	ConstructionPlanner.dismantleQueueIndex =
		0

	cpDebug(
		"[ConstructionPlanner] Dismantle queue complete"
	)

	if queueBorrowedToolReturns() then

		ConstructionPlanner.dismantleReturningTools =
			true

		ISTimedActionQueue.add(
			ISConstructionPlannerFinishDismantleReturn:new(
				getPlayer()
			)
		)
	end
end


------------------------------------------------------------
-- BEGIN AFTER TOOL FETCH SENTINEL
------------------------------------------------------------

ISConstructionPlannerBeginDismantle =
	ISBaseTimedAction:derive(
		"ISConstructionPlannerBeginDismantle"
	)

function ISConstructionPlannerBeginDismantle:isValid()
	return self.character ~= nil
		and self.targets ~= nil
end

function ISConstructionPlannerBeginDismantle:update()
end

function ISConstructionPlannerBeginDismantle:start()
end

function ISConstructionPlannerBeginDismantle:stop()
	ConstructionPlanner.dismantleFetchingTools =
		false

	ConstructionPlanner.dismantleRunning =
		false

	ISBaseTimedAction.stop(
		self
	)
end

function ISConstructionPlannerBeginDismantle:perform()
	ConstructionPlanner.dismantleFetchingTools =
		false

	local targets =
		self.targets

	if not targets
	or #targets == 0 then

		ConstructionPlanner.dismantleRunning =
			false

		ISBaseTimedAction.perform(
			self
		)

		return
	end

	--------------------------------------------------------
	-- Recheck the sourced tools now that all pickup actions
	-- ahead of this sentinel have completed.
	--------------------------------------------------------

	for _, target in ipairs(
		targets
	) do

		local refreshed =
			refreshTarget(
				target
			)

		if refreshed then

			for _, requirement in ipairs(
				refreshed.requirements
				or {}
			) do

				if not findItemInContainer(
					self.character:getInventory(),
					requirement
				) then

					cpDebug(
						"[ConstructionPlanner] Required Disassemble tool was not acquired"
					)

					ConstructionPlanner.dismantleRunning =
						false

					ConstructionPlanner.dismantleQueue =
						nil

					ISBaseTimedAction.perform(
						self
					)

					return
				end
			end
		end
	end

	ConstructionPlanner.dismantleQueue =
		targets

	ConstructionPlanner.dismantleQueueIndex =
		1

	ConstructionPlanner.dismantleRunning =
		true

	ConstructionPlanner.clearDismantleSelection()

	--------------------------------------------------------
	-- Queue the first walk/equip/prepare pair WHILE this
	-- sentinel is still current.
	--------------------------------------------------------

	ConstructionPlanner.queueCurrentDismantleTarget()

	ISBaseTimedAction.perform(
		self
	)
end

function ISConstructionPlannerBeginDismantle:new(
	character,
	targets
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

	o.targets =
		targets

	o.stopOnWalk =
		false

	o.stopOnRun =
		false

	o.maxTime =
		1

	return o
end


------------------------------------------------------------
-- CONFIRM DISMANTLING
------------------------------------------------------------

function ConstructionPlanner.confirmDismantling()
	if not ConstructionPlanner.canConfirmDismantling() then
		return false
	end

	local copy =
		{}

	for _, target in ipairs(
		ConstructionPlanner.dismantleSelectedObjects
		or {}
	) do

		table.insert(
			copy,
			target
		)
	end

	local status =
		ConstructionPlanner.refreshDismantleToolStatus()

	if not status.allAvailable then
		return false
	end

	local ok,
		queuedAny =
			queueMissingToolPickups(
				status
			)

	if not ok then

		ConstructionPlanner.dismantleBorrowedTools =
			{}

		return false
	end

	if queuedAny then

		ConstructionPlanner.dismantleFetchingTools =
			true

		----------------------------------------------------
		-- Start sentinel sits behind all pickup actions.
		----------------------------------------------------

		ISTimedActionQueue.add(
			ISConstructionPlannerBeginDismantle:new(
				getPlayer(),
				copy
			)
		)

		cpDebug(
			"[ConstructionPlanner] Fetching vanilla Disassemble tools"
		)

		return true
	end

	--------------------------------------------------------
	-- No tool fetch needed. Use the same begin sentinel even
	-- now, so the first target also enters through the exact
	-- same continuous timed-action architecture.
	--------------------------------------------------------

	ConstructionPlanner.dismantleFetchingTools =
		true

	ISTimedActionQueue.add(
		ISConstructionPlannerBeginDismantle:new(
			getPlayer(),
			copy
		)
	)

	return true
end


------------------------------------------------------------
-- PERIODIC TOOL STATUS REFRESH
------------------------------------------------------------

local function updateToolStatus()
	if ConstructionPlanner.projectPanelPage
	~= "dismantle" then
		return
	end

	if #(
		ConstructionPlanner.dismantleSelectedObjects
		or {}
	) == 0 then
		return
	end

	ConstructionPlanner.dismantleToolRefreshCounter =
		(
			ConstructionPlanner.dismantleToolRefreshCounter
			or 0
		)
		+ 1

	if ConstructionPlanner.dismantleToolRefreshCounter
	< 30 then
		return
	end

	ConstructionPlanner.dismantleToolRefreshCounter =
		0

	ConstructionPlanner.refreshDismantleToolStatus()
end


------------------------------------------------------------
-- HOOK INSTALLER
------------------------------------------------------------

local function updateDismantleHook()
	ensureDismantlePerformHook()
end


------------------------------------------------------------
-- EVENTS
------------------------------------------------------------

Events.OnTick.Add(
	updateDismantleHook
)

Events.OnTick.Add(
	updateDismantleSelection
)

Events.OnTick.Add(
	updateToolStatus
)

Events.OnPostRender.Add(
	renderDismantleSelection
)
