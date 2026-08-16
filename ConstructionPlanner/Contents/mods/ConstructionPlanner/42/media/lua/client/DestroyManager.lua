------------------------------------------------------------
-- Construction Planner - Destroy Manager
--
-- Bulk VANILLA sledgehammer destruction.
--
-- Mirrors the working Dismantle workflow:
--   * Area / Line selection
--   * temporary drag-ground highlight
--   * persistent selected-object highlight
--   * Confirm Destruction gate
--   * source priority:
--       Player Inventory
--       -> Supply Containers
--       -> Gather Area ground items
--   * continuous Speed-3 queue:
--       walk -> prepare -> ISDestroyStuffAction
--       -> addAfter continuation -> next walk
--
-- Destroy has exactly ONE tool requirement: Sledgehammer.
------------------------------------------------------------

require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISGrabItemAction"
require "TimedActions/ISDestroyStuffAction"
require "ISUI/ISWorldObjectContextMenu"

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

ConstructionPlanner.destroySelecting = false
ConstructionPlanner.destroyStartTile = nil
ConstructionPlanner.destroyCurrentTile = nil
ConstructionPlanner.destroyDragObjects = {}
ConstructionPlanner.destroySelectedObjects = {}
ConstructionPlanner.destroySelectedLookup = {}
ConstructionPlanner.destroyWasBuildButtonDown = false

ConstructionPlanner.destroyFetchingTool = false
ConstructionPlanner.destroyRunning = false
ConstructionPlanner.destroyReturningTool = false
ConstructionPlanner.destroyQueue = nil
ConstructionPlanner.destroyQueueIndex = 0
ConstructionPlanner.destroyBorrowedTool = nil

ConstructionPlanner.destroyToolStatus = {
	allAvailable = false,
	requirements = {}
}

------------------------------------------------------------
-- BASIC HELPERS
------------------------------------------------------------

local function getPlayer()
	return getSpecificPlayer(0)
end

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
-- SLEDGEHAMMER MATCHING
------------------------------------------------------------

local function isUsableSledgehammer(
	item
)
	if not item then
		return false
	end

	if item.isBroken
	and item:isBroken() then
		return false
	end

	local itemType =
		item.getType
		and tostring(
			item:getType()
		)
		or ""

	local fullType =
		item.getFullType
		and tostring(
			item:getFullType()
		)
		or ""

	itemType =
		string.lower(
			itemType
		)

	fullType =
		string.lower(
			fullType
		)

	--------------------------------------------------------
	-- Covers vanilla Sledgehammer and Sledgehammer2.
	--------------------------------------------------------

	return string.find(
		itemType,
		"sledgehammer",
		1,
		true
	) ~= nil
	or string.find(
		fullType,
		"sledgehammer",
		1,
		true
	) ~= nil
end

local function findSledgeInContainer(
	container,
	recurse
)
	if not container then
		return nil
	end

	if recurse
	and container.getFirstEvalRecurse then

		local item =
			container:getFirstEvalRecurse(
				isUsableSledgehammer
			)

		if item then
			return item
		end
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

		if isUsableSledgehammer(
			item
		) then

			return item
		end
	end

	return nil
end

------------------------------------------------------------
-- SOURCE PRIORITY
------------------------------------------------------------

local function findSledgeSource()
	local player =
		getPlayer()

	if not player then
		return nil
	end

	--------------------------------------------------------
	-- 1. PLAYER INVENTORY
	--------------------------------------------------------

	local item =
		findSledgeInContainer(
			player:getInventory(),
			true
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
				findSledgeInContainer(
					container,
					false
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
			and isUsableSledgehammer(
				entry.item
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

function ConstructionPlanner.refreshDestroyToolStatus()
	local source =
		findSledgeSource()

	local row = {
		label = "Sledgehammer",
		available =
			source ~= nil,
		source =
			source,
		sourceLabel =
			source
			and source.label
			or "Missing"
	}

	ConstructionPlanner.destroyToolStatus = {
		allAvailable =
			source ~= nil,
		requirements = {
			row
		}
	}

	return ConstructionPlanner.destroyToolStatus
end

function ConstructionPlanner.getDestroyToolStatus()
	return ConstructionPlanner.refreshDestroyToolStatus()
end

------------------------------------------------------------
-- DESTROY TARGET FILTER
--
-- Destroy deliberately excludes ground clutter / floor tiles.
-- Everything else is handed to vanilla ISDestroyStuffAction.
------------------------------------------------------------

local function isDestroyClutter(
	object
)
	if not object then
		return true
	end

	if instanceof(
		object,
		"IsoWorldInventoryObject"
	) then
		return true
	end

	if instanceof(
		object,
		"IsoTree"
	) then
		return true
	end

	local square =
		object.getSquare
		and object:getSquare()
		or nil

	if not square then
		return true
	end

	if square:getFloor()
	== object then
		return true
	end

	local sprite =
		object.getSprite
		and object:getSprite()
		or nil

	if not sprite then
		return true
	end

	local props =
		sprite:getProperties()

	if props then

		if props:has("vegetation")
		or props:has("Vegetation")
		or props:has("Bush")
		or props:has("Tree")
		or props:has("NaturalFloor") then

			return true
		end
	end

	local name =
		string.lower(
			tostring(
				sprite:getName()
				or ""
			)
		)

	if string.find(
		name,
		"vegetation_",
		1,
		true
	)
	or string.find(
		name,
		"blends_natural_",
		1,
		true
	)
	or string.find(
		name,
		"d_floorleaves_",
		1,
		true
	)
	or string.find(
		name,
		"d_trash_",
		1,
		true
	)
	or string.find(
		name,
		"trash_",
		1,
		true
	)
	or string.find(
		name,
		"debris_",
		1,
		true
	)
	or string.find(
		name,
		"grass_",
		1,
		true
	) then

		return true
	end

	return false
end

local function getDestroyTarget(
	object,
	square
)
	if not object
	or not square
	or isDestroyClutter(
		object
	) then

		return nil
	end

	return {
		object = object,
		square = square
	}
end

------------------------------------------------------------
-- SELECTION TILE SHAPE
------------------------------------------------------------

local function buildSelectionTiles(
	startTile,
	endTile
)
	local tiles = {}

	if not startTile
	or not endTile
	or startTile.z
		~= endTile.z then

		return tiles
	end

	local placementMode =
		ConstructionPlanner.getPlacementMode
		and ConstructionPlanner.getPlacementMode()
		or "area"

	--------------------------------------------------------
	-- LINE
	--------------------------------------------------------

	if placementMode == "line" then

		local x1 =
			startTile.x

		local y1 =
			startTile.y

		local x2 =
			endTile.x

		local y2 =
			endTile.y

		local dx =
			math.abs(
				x2 - x1
			)

		local dy =
			math.abs(
				y2 - y1
			)

		local sx =
			x1 < x2
			and 1
			or -1

		local sy =
			y1 < y2
			and 1
			or -1

		local err =
			dx - dy

		while true do

			table.insert(
				tiles,
				{
					x = x1,
					y = y1,
					z = startTile.z
				}
			)

			if x1 == x2
			and y1 == y2 then
				break
			end

			local e2 =
				2 * err

			if e2 > -dy then
				err =
					err - dy

				x1 =
					x1 + sx
			end

			if e2 < dx then
				err =
					err + dx

				y1 =
					y1 + sy
			end
		end

		return tiles
	end

	--------------------------------------------------------
	-- AREA
	--------------------------------------------------------

	for x = math.min(
		startTile.x,
		endTile.x
	),
	math.max(
		startTile.x,
		endTile.x
	) do

		for y = math.min(
			startTile.y,
			endTile.y
		),
		math.max(
			startTile.y,
			endTile.y
		) do

			table.insert(
				tiles,
				{
					x = x,
					y = y,
					z = startTile.z
				}
			)
		end
	end

	return tiles
end

------------------------------------------------------------
-- COLLECT DESTROY OBJECTS
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

	for i = 0,
		objects:size() - 1 do

		local object =
			objects:get(i)

		local target =
			getDestroyTarget(
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

				table.insert(
					results,
					target
				)
			end
		end
	end
end

local function refreshDestroyDrag(
	endTile
)
	local results = {}
	local lookup = {}

	local tiles =
		buildSelectionTiles(
			ConstructionPlanner.destroyStartTile,
			endTile
		)

	for _, tile in ipairs(
		tiles
	) do

		collectSquareObjects(
			tile,
			results,
			lookup
		)
	end

	ConstructionPlanner.destroyCurrentTile =
		endTile

	ConstructionPlanner.destroyDragObjects =
		results
end

local function rebuildSelectedList()
	local selected = {}

	for _, target in pairs(
		ConstructionPlanner.destroySelectedLookup
		or {}
	) do

		table.insert(
			selected,
			target
		)
	end

	ConstructionPlanner.destroySelectedObjects =
		selected
end

local function commitDestroyDrag()
	for _, target in ipairs(
		ConstructionPlanner.destroyDragObjects
		or {}
	) do

		local key =
			objectKey(
				target.object
			)

		if key then

			if ConstructionPlanner.destroySelectedLookup[
				key
			] then

				ConstructionPlanner.destroySelectedLookup[
					key
				] = nil

			else

				ConstructionPlanner.destroySelectedLookup[
					key
				] = target
			end
		end
	end

	ConstructionPlanner.destroyDragObjects =
		{}

	rebuildSelectedList()

	ConstructionPlanner.refreshDestroyToolStatus()
end

function ConstructionPlanner.clearDestroySelection()
	ConstructionPlanner.destroySelecting =
		false

	ConstructionPlanner.destroyStartTile =
		nil

	ConstructionPlanner.destroyCurrentTile =
		nil

	ConstructionPlanner.destroyDragObjects =
		{}

	ConstructionPlanner.destroySelectedObjects =
		{}

	ConstructionPlanner.destroySelectedLookup =
		{}
end

function ConstructionPlanner.getDestroySelectionCount()
	return #(
		ConstructionPlanner.destroySelectedObjects
		or {}
	)
end

------------------------------------------------------------
-- HIGHLIGHTING
------------------------------------------------------------

local function highlightDestroyTarget(
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

local function drawDestroyDragGround()
	if not ConstructionPlanner.destroySelecting
	or not ConstructionPlanner.destroyStartTile
	or not ConstructionPlanner.destroyCurrentTile then

		return
	end

	local tiles =
		buildSelectionTiles(
			ConstructionPlanner.destroyStartTile,
			ConstructionPlanner.destroyCurrentTile
		)

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

local function renderDestroySelection()
	if ConstructionPlanner.projectPanelPage
	~= "destroy" then

		return
	end

	--------------------------------------------------------
	-- Ground only remains while mouse is held.
	--------------------------------------------------------

	drawDestroyDragGround()

	for _, target in ipairs(
		ConstructionPlanner.destroySelectedObjects
		or {}
	) do

		highlightDestroyTarget(
			target,
			true
		)
	end

	for _, target in ipairs(
		ConstructionPlanner.destroyDragObjects
		or {}
	) do

		local key =
			objectKey(
				target.object
			)

		if not key
		or not ConstructionPlanner.destroySelectedLookup[
			key
		] then

			highlightDestroyTarget(
				target,
				false
			)
		end
	end
end

------------------------------------------------------------
-- SELECTION INPUT
------------------------------------------------------------

local function updateDestroySelection()
	if ConstructionPlanner.projectPanelPage
	~= "destroy" then

		ConstructionPlanner.destroyWasBuildButtonDown =
			false

		if not ConstructionPlanner.destroyRunning
		and not ConstructionPlanner.destroyFetchingTool then

			ConstructionPlanner.destroySelecting =
				false

			ConstructionPlanner.destroyDragObjects =
				{}
		end

		return
	end

	if ConstructionPlanner.destroyRunning
	or ConstructionPlanner.destroyFetchingTool then

		ConstructionPlanner.destroyWasBuildButtonDown =
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

	--------------------------------------------------------
	-- START
	--------------------------------------------------------

	if mouseDown
	and not ConstructionPlanner.destroyWasBuildButtonDown then

		local tile =
			getMouseWorldTile()

		if tile then

			ConstructionPlanner.destroySelecting =
				true

			ConstructionPlanner.destroyStartTile =
				tile

			ConstructionPlanner.destroyCurrentTile =
				tile

			refreshDestroyDrag(
				tile
			)
		end
	end

	--------------------------------------------------------
	-- DRAG
	--------------------------------------------------------

	if ConstructionPlanner.destroySelecting
	and mouseDown then

		local tile =
			getMouseWorldTile()

		if tile
		and ConstructionPlanner.destroyStartTile
		and tile.z
			== ConstructionPlanner.destroyStartTile.z then

			refreshDestroyDrag(
				tile
			)
		end
	end

	--------------------------------------------------------
	-- RELEASE
	--------------------------------------------------------

	if ConstructionPlanner.destroySelecting
	and ConstructionPlanner.destroyWasBuildButtonDown
	and not mouseDown then

		local endTile =
			ConstructionPlanner.destroyCurrentTile
			or getMouseWorldTile()

		if endTile then

			refreshDestroyDrag(
				endTile
			)

			commitDestroyDrag()
		end

		ConstructionPlanner.destroySelecting =
			false

		ConstructionPlanner.destroyStartTile =
			nil

		ConstructionPlanner.destroyCurrentTile =
			nil
	end

	ConstructionPlanner.destroyWasBuildButtonDown =
		mouseDown
end

------------------------------------------------------------
-- TOOL PICKUP
------------------------------------------------------------

local function queueSledgePickup(
	source
)
	local player =
		getPlayer()

	if not player
	or not source
	or not source.item then

		return false
	end

	--------------------------------------------------------
	-- ALREADY CARRIED
	--------------------------------------------------------

	if source.kind == "inventory" then
		return true
	end

	--------------------------------------------------------
	-- SUPPLY CONTAINER
	--------------------------------------------------------

	if source.kind == "supply" then

		if not source.container then
			return false
		end

		if not luautils.walkToContainer(
			source.container,
			player:getPlayerNum()
		) then

			return false
		end

		local action =
			ISInventoryTransferUtil.newInventoryTransferAction(
				player,
				source.item,
				source.container,
				player:getInventory()
			)

		if not action then
			return false
		end

		ISTimedActionQueue.add(
			action
		)

		ConstructionPlanner.destroyBorrowedTool = {
			item = source.item,
			sourceContainer = source.container
		}

		return true
	end

	--------------------------------------------------------
	-- GATHER AREA GROUND
	--------------------------------------------------------

	if source.kind == "gather" then

		if not source.worldObject
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

	return false
end

------------------------------------------------------------
-- EXACT SPEED-3 WALK FIX
--
-- This is the logic that fixed Dismantle:
-- CP-owned walk actions remain valid through Speed 3.
------------------------------------------------------------

local function markLatestDestroyWalk(
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

	for i = #queue.queue, 1, -1 do

		local action =
			queue.queue[i]

		if action
		and (
			action.Type == "ISWalkToTimedAction"
			or action.Type
				== "ISConstructionPlannerWalkToTimedAction"
		) then

			action.constructionPlannerWalk =
				true

			action.constructionPlannerDestroyWalk =
				true

			action.isValid = function(self)

				if self.character:getVehicle() then
					return false
				end

				return getGameSpeed() <= 3
			end

			return true
		end
	end

	return false
end

------------------------------------------------------------
-- REFRESH TARGET
------------------------------------------------------------

local function refreshDestroyTarget(
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

	return getDestroyTarget(
		oldTarget.object,
		square
	)
end

------------------------------------------------------------
-- FORWARD DECLARATION
------------------------------------------------------------

local finishDestroyRun

------------------------------------------------------------
-- PREPARE VANILLA DESTROY
------------------------------------------------------------

ISConstructionPlannerPrepareDestroy =
	ISBaseTimedAction:derive(
		"ISConstructionPlannerPrepareDestroy"
	)

function ISConstructionPlannerPrepareDestroy:isValid()
	return self.character ~= nil
		and ConstructionPlanner.destroyRunning
		and self.target ~= nil
end

function ISConstructionPlannerPrepareDestroy:update()
end

function ISConstructionPlannerPrepareDestroy:start()
end

function ISConstructionPlannerPrepareDestroy:stop()
	ISBaseTimedAction.stop(
		self
	)
end

function ISConstructionPlannerPrepareDestroy:perform()
	if not ConstructionPlanner.destroyRunning then

		ISBaseTimedAction.perform(
			self
		)

		return
	end

	local target =
		refreshDestroyTarget(
			self.target
		)

	if not target then

		ConstructionPlanner.destroyQueueIndex =
			ConstructionPlanner.destroyQueueIndex
			+ 1

		if ConstructionPlanner.destroyQueue
		and ConstructionPlanner.destroyQueueIndex
			<= #ConstructionPlanner.destroyQueue then

			ConstructionPlanner.queueCurrentDestroyTarget()

		else

			finishDestroyRun()
		end

		ISBaseTimedAction.perform(
			self
		)

		return
	end

	--------------------------------------------------------
	-- REAL VANILLA DESTROY ACTION.
	--------------------------------------------------------

	local action =
		ISDestroyStuffAction:new(
			self.character,
			target.object,
			nil
		)

	if not action then

		ConstructionPlanner.destroyQueueIndex =
			ConstructionPlanner.destroyQueueIndex
			+ 1

		if ConstructionPlanner.destroyQueue
		and ConstructionPlanner.destroyQueueIndex
			<= #ConstructionPlanner.destroyQueue then

			ConstructionPlanner.queueCurrentDestroyTarget()

		else

			finishDestroyRun()
		end

		ISBaseTimedAction.perform(
			self
		)

		return
	end

	action.constructionPlannerDestroy =
		true

	cpDebug(
		"[ConstructionPlanner] Vanilla Destroy "
		.. tostring(
			ConstructionPlanner.destroyQueueIndex
		)
		.. " / "
		.. tostring(
			#ConstructionPlanner.destroyQueue
		)
	)

	ISTimedActionQueue.add(
		action
	)

	ISBaseTimedAction.perform(
		self
	)
end

function ISConstructionPlannerPrepareDestroy:new(
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
-- QUEUE CURRENT DESTROY TARGET
------------------------------------------------------------

function ConstructionPlanner.queueCurrentDestroyTarget()
	if not ConstructionPlanner.destroyRunning then
		return false
	end

	local queue =
		ConstructionPlanner.destroyQueue

	local index =
		ConstructionPlanner.destroyQueueIndex

	if not queue
	or index < 1
	or index > #queue then
		return false
	end

	local target =
		refreshDestroyTarget(
			queue[index]
		)

	if not target then

		ConstructionPlanner.destroyQueueIndex =
			index + 1

		if ConstructionPlanner.destroyQueueIndex
		<= #queue then

			return ConstructionPlanner.queueCurrentDestroyTarget()
		end

		finishDestroyRun()

		return false
	end

	--------------------------------------------------------
	-- Same continuous queue structure as Dismantle.
	--
	-- IMPORTANT:
	-- luautils.walkAdj() can return true WITHOUT queuing a
	-- new ISWalkToTimedAction when the player is already in a
	-- valid adjacent position.
	--
	-- The old Destroy code treated "no new walk action" as a
	-- failure because markLatestDestroyWalk() returned false,
	-- which silently stopped the chain.
	--------------------------------------------------------

	local player =
		getPlayer()

	local timedQueue =
		ISTimedActionQueue.getTimedActionQueue(
			player
		)

	local beforeCount =
		timedQueue
		and timedQueue.queue
		and #timedQueue.queue
		or 0

	if not luautils.walkAdj(
		player,
		target.square,
		true
	) then

		ConstructionPlanner.destroyQueueIndex =
			index + 1

		if ConstructionPlanner.destroyQueueIndex
		<= #queue then

			return ConstructionPlanner.queueCurrentDestroyTarget()
		end

		finishDestroyRun()

		return false
	end

	local afterQueue =
		ISTimedActionQueue.getTimedActionQueue(
			player
		)

	local afterCount =
		afterQueue
		and afterQueue.queue
		and #afterQueue.queue
		or 0

	--------------------------------------------------------
	-- ONLY mark a walk if walkAdj actually queued one.
	-- If count did not increase, we're already adjacent and
	-- should go directly to PrepareDestroy.
	--------------------------------------------------------

	if afterCount > beforeCount then

		if not markLatestDestroyWalk(
			player
		) then

			cpDebug(
				"[ConstructionPlanner] WARNING: Destroy walk queued but could not be marked for Speed 3"
			)

			return false
		end

	else

		cpDebug(
			"[ConstructionPlanner] Destroy target already adjacent - no walk needed"
		)
	end

	ISTimedActionQueue.add(
		ISConstructionPlannerPrepareDestroy:new(
			getPlayer(),
			target
		)
	)

	cpDebug(
		"[ConstructionPlanner] Preparing Destroy "
		.. tostring(index)
		.. " / "
		.. tostring(#queue)
	)

	return true
end

------------------------------------------------------------
-- CONTINUATION
------------------------------------------------------------

ISConstructionPlannerContinueDestroy =
	ISBaseTimedAction:derive(
		"ISConstructionPlannerContinueDestroy"
	)

function ISConstructionPlannerContinueDestroy:isValid()
	return self.character ~= nil
end

function ISConstructionPlannerContinueDestroy:update()
end

function ISConstructionPlannerContinueDestroy:start()
end

function ISConstructionPlannerContinueDestroy:stop()
	ISBaseTimedAction.stop(
		self
	)
end

function ISConstructionPlannerContinueDestroy:perform()
	if not ConstructionPlanner.destroyRunning then

		ISBaseTimedAction.perform(
			self
		)

		return
	end

	cpDebug(
		"[ConstructionPlanner] Destroy completed "
		.. tostring(
			ConstructionPlanner.destroyQueueIndex
		)
		.. " / "
		.. tostring(
			ConstructionPlanner.destroyQueue
			and #ConstructionPlanner.destroyQueue
			or 0
		)
	)

	ConstructionPlanner.destroyQueueIndex =
		ConstructionPlanner.destroyQueueIndex
		+ 1

	if ConstructionPlanner.destroyQueue
	and ConstructionPlanner.destroyQueueIndex
		<= #ConstructionPlanner.destroyQueue then

		ConstructionPlanner.queueCurrentDestroyTarget()

	else

		finishDestroyRun()
	end

	ISBaseTimedAction.perform(
		self
	)
end

function ISConstructionPlannerContinueDestroy:new(
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
-- VANILLA DESTROY PERFORM HOOK
------------------------------------------------------------

local function ensureDestroyPerformHook()
	if ConstructionPlanner.destroyPerformHooked then
		return
	end

	if not ISDestroyStuffAction
	or not ISDestroyStuffAction.perform then
		return
	end

	ConstructionPlanner.originalDestroyStuffPerform =
		ISDestroyStuffAction.perform

	ISDestroyStuffAction.perform = function(self)

		if self
		and self.constructionPlannerDestroy
		and ConstructionPlanner.destroyRunning then

			ISTimedActionQueue.addAfter(
				self,
				ISConstructionPlannerContinueDestroy:new(
					self.character
				)
			)
		end

		return ConstructionPlanner.originalDestroyStuffPerform(
			self
		)
	end

	ConstructionPlanner.destroyPerformHooked =
		true

	cpDebug(
		"[ConstructionPlanner] Destroy perform hook installed"
	)
end

------------------------------------------------------------
-- RETURN BORROWED SUPPLY-CONTAINER SLEDGE
------------------------------------------------------------

ISConstructionPlannerFinishDestroyReturn =
	ISBaseTimedAction:derive(
		"ISConstructionPlannerFinishDestroyReturn"
	)

function ISConstructionPlannerFinishDestroyReturn:isValid()
	return self.character ~= nil
end

function ISConstructionPlannerFinishDestroyReturn:update()
end

function ISConstructionPlannerFinishDestroyReturn:start()
end

function ISConstructionPlannerFinishDestroyReturn:stop()
	ConstructionPlanner.destroyReturningTool =
		false

	ISBaseTimedAction.stop(
		self
	)
end

function ISConstructionPlannerFinishDestroyReturn:perform()
	ConstructionPlanner.destroyReturningTool =
		false

	ConstructionPlanner.destroyBorrowedTool =
		nil

	cpDebug(
		"[ConstructionPlanner] Borrowed sledgehammer returned"
	)

	ISBaseTimedAction.perform(
		self
	)
end

function ISConstructionPlannerFinishDestroyReturn:new(
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

local function queueBorrowedSledgeReturn()
	local borrowed =
		ConstructionPlanner.destroyBorrowedTool

	if not borrowed
	or not borrowed.item
	or not borrowed.sourceContainer then

		ConstructionPlanner.destroyBorrowedTool =
			nil

		return false
	end

	local player =
		getPlayer()

	if not player
	or borrowed.item:getContainer()
		~= player:getInventory() then

		ConstructionPlanner.destroyBorrowedTool =
			nil

		return false
	end

	if not luautils.walkToContainer(
		borrowed.sourceContainer,
		player:getPlayerNum()
	) then

		return false
	end

	local action =
		ISInventoryTransferUtil.newInventoryTransferAction(
			player,
			borrowed.item,
			player:getInventory(),
			borrowed.sourceContainer
		)

	if not action then
		return false
	end

	ISTimedActionQueue.add(
		action
	)

	ConstructionPlanner.destroyReturningTool =
		true

	ISTimedActionQueue.add(
		ISConstructionPlannerFinishDestroyReturn:new(
			player
		)
	)

	return true
end

------------------------------------------------------------
-- FINISH RUN
------------------------------------------------------------

finishDestroyRun = function()
	ConstructionPlanner.destroyRunning =
		false

	ConstructionPlanner.destroyFetchingTool =
		false

	ConstructionPlanner.destroyQueue =
		nil

	ConstructionPlanner.destroyQueueIndex =
		0

	cpDebug(
		"[ConstructionPlanner] Destroy queue complete"
	)

	queueBorrowedSledgeReturn()
end

ConstructionPlanner.finishDestroyRun =
	finishDestroyRun

------------------------------------------------------------
-- BEGIN AFTER TOOL PICKUP
------------------------------------------------------------

ISConstructionPlannerBeginDestroy =
	ISBaseTimedAction:derive(
		"ISConstructionPlannerBeginDestroy"
	)

function ISConstructionPlannerBeginDestroy:isValid()
	return self.character ~= nil
		and self.targets ~= nil
end

function ISConstructionPlannerBeginDestroy:update()
end

function ISConstructionPlannerBeginDestroy:start()
end

function ISConstructionPlannerBeginDestroy:stop()
	ConstructionPlanner.destroyFetchingTool =
		false

	ConstructionPlanner.destroyRunning =
		false

	ISBaseTimedAction.stop(
		self
	)
end

function ISConstructionPlannerBeginDestroy:perform()
	ConstructionPlanner.destroyFetchingTool =
		false

	local sledge =
		findSledgeInContainer(
			self.character:getInventory(),
			true
		)

	if not sledge then

		cpDebug(
			"[ConstructionPlanner] Destroy could not start - Sledgehammer missing after pickup"
		)

		ConstructionPlanner.destroyRunning =
			false

		ISBaseTimedAction.perform(
			self
		)

		return
	end

	--------------------------------------------------------
	-- Vanilla ISDestroyCursor equips its sledge before
	-- queuing ISDestroyStuffAction.
	--------------------------------------------------------

	ISWorldObjectContextMenu.equip(
		self.character,
		self.character:getPrimaryHandItem(),
		sledge,
		true,
		false
	)

	ConstructionPlanner.destroyQueue =
		self.targets

	ConstructionPlanner.destroyQueueIndex =
		1

	ConstructionPlanner.destroyRunning =
		true

	ConstructionPlanner.clearDestroySelection()

	--------------------------------------------------------
	-- Queue first target while sentinel is still current.
	-- If equip() added an equip action, the walk naturally
	-- sits behind it in the same queue.
	--------------------------------------------------------

	ConstructionPlanner.queueCurrentDestroyTarget()

	ISBaseTimedAction.perform(
		self
	)
end

function ISConstructionPlannerBeginDestroy:new(
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
-- CONFIRM
------------------------------------------------------------

function ConstructionPlanner.canConfirmDestruction()
	if ConstructionPlanner.destroyRunning
	or ConstructionPlanner.destroyFetchingTool then

		return false
	end

	if ConstructionPlanner.getDestroySelectionCount()
	<= 0 then

		return false
	end

	local status =
		ConstructionPlanner.refreshDestroyToolStatus()

	return status.allAvailable
end

function ConstructionPlanner.confirmDestruction()
	if not ConstructionPlanner.canConfirmDestruction() then
		return false
	end

	local source =
		findSledgeSource()

	if not source then
		return false
	end

	local targets = {}

	for _, target in ipairs(
		ConstructionPlanner.destroySelectedObjects
		or {}
	) do

		table.insert(
			targets,
			target
		)
	end

	if #targets == 0 then
		return false
	end

	ConstructionPlanner.destroyBorrowedTool =
		nil

	--------------------------------------------------------
	-- Tool pickup first if needed.
	--------------------------------------------------------

	if source.kind ~= "inventory" then

		ISTimedActionQueue.clear(
			getPlayer()
		)

		if not queueSledgePickup(
			source
		) then

			return false
		end
	end

	ConstructionPlanner.destroyFetchingTool =
		true

	ISTimedActionQueue.add(
		ISConstructionPlannerBeginDestroy:new(
			getPlayer(),
			targets
		)
	)

	if source.kind == "inventory" then

		cpDebug(
			"[ConstructionPlanner] Sledgehammer already carried"
		)

	else

		cpDebug(
			"[ConstructionPlanner] Fetching Sledgehammer from "
			.. tostring(source.label)
		)
	end

	return true
end

ConstructionPlanner.confirmDestroying =
	ConstructionPlanner.confirmDestruction

------------------------------------------------------------
-- TOOL STATUS REFRESH
------------------------------------------------------------

local function updateDestroyToolStatus()
	if ConstructionPlanner.projectPanelPage
	~= "destroy" then
		return
	end

	ConstructionPlanner.destroyToolRefreshCounter =
		(
			ConstructionPlanner.destroyToolRefreshCounter
			or 0
		)
		+ 1

	if ConstructionPlanner.destroyToolRefreshCounter
	< 30 then
		return
	end

	ConstructionPlanner.destroyToolRefreshCounter =
		0

	ConstructionPlanner.refreshDestroyToolStatus()
end

------------------------------------------------------------
-- EVENTS
------------------------------------------------------------

Events.OnTick.Add(
	ensureDestroyPerformHook
)

Events.OnTick.Add(
	updateDestroySelection
)

Events.OnTick.Add(
	updateDestroyToolStatus
)

Events.OnPostRender.Add(
	renderDestroySelection
)
