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

ConstructionPlanner.supplyContainers =
	ConstructionPlanner.supplyContainers
	or {}

ConstructionPlanner.supplyRestorePending =
	ConstructionPlanner.supplyRestorePending
	or false


--------------------------------------------------------
-- SAVE DATA
--------------------------------------------------------

local SAVE_KEY =
	"ConstructionPlannerSupplyContainers"


local function getSaveData()
	local data =
		ModData.getOrCreate(
			SAVE_KEY
		)

	if not data.containers then
		data.containers = {}
	end

	return data
end


--------------------------------------------------------
-- HELPERS
--------------------------------------------------------

local function getContainerFromWorldObject(
	worldObject
)
	if not worldObject then
		return nil
	end

	if not worldObject.getContainer then
		return nil
	end

	return worldObject:getContainer()
end


local function getSelectedCount()
	local count = 0

	for _, _ in pairs(
		ConstructionPlanner.supplyContainers
	) do
		count = count + 1
	end

	return count
end


local function isSelected(container)
	if not container then
		return false
	end

	return ConstructionPlanner.supplyContainers[
		container
	] == true
end


--------------------------------------------------------
-- CONTAINER LOCATION
--------------------------------------------------------

local function getContainerWorldObject(
	container
)
	if not container then
		return nil
	end

	if not container.getParent then
		return nil
	end

	return container:getParent()
end


local function getContainerSquare(
	container
)
	local parent =
		getContainerWorldObject(
			container
		)

	if not parent then
		return nil
	end

	if not parent.getSquare then
		return nil
	end

	return parent:getSquare()
end


--------------------------------------------------------
-- CREATE SAVE ENTRY
--------------------------------------------------------

local function makeContainerSaveEntry(
	container
)
	if not container then
		return nil
	end

	local square =
		getContainerSquare(
			container
		)

	if not square then
		return nil
	end

	local parent =
		getContainerWorldObject(
			container
		)

	if not parent then
		return nil
	end

	local objectIndex = -1

	if parent.getObjectIndex then
		objectIndex =
			parent:getObjectIndex()
	end

	return {
		x = square:getX(),
		y = square:getY(),
		z = square:getZ(),

		objectIndex =
			objectIndex,

		containerType =
			tostring(
				container:getType()
			)
	}
end


--------------------------------------------------------
-- COMPARE SAVE ENTRIES
--------------------------------------------------------

local function sameSaveEntry(
	a,
	b
)
	if not a or not b then
		return false
	end

	return
		a.x == b.x
		and a.y == b.y
		and a.z == b.z
		and a.objectIndex == b.objectIndex
		and a.containerType == b.containerType
end


--------------------------------------------------------
-- SAVE CURRENT SUPPLY CONTAINERS
--------------------------------------------------------

saveSupplyContainers =
function()
	local data =
		getSaveData()

	data.containers = {}

	for container, selected in pairs(
		ConstructionPlanner.supplyContainers
	) do

		if selected then

			local entry =
				makeContainerSaveEntry(
					container
				)

			if entry then

				table.insert(
					data.containers,
					entry
				)
			end
		end
	end

	cpDebug(
		"[ConstructionPlanner] Saved "
		.. tostring(
			#data.containers
		)
		.. " supply container(s)"
	)
end


--------------------------------------------------------
-- FIND SAVED CONTAINER
--------------------------------------------------------

local function findSavedContainer(
	entry
)
	if not entry then
		return nil
	end

	local square =
		getCell():getGridSquare(
			entry.x,
			entry.y,
			entry.z
		)

	if not square then
		return nil
	end

	local objects =
		square:getObjects()

	if not objects then
		return nil
	end


	----------------------------------------------------
	-- TRY SAVED OBJECT INDEX FIRST
	----------------------------------------------------

	if entry.objectIndex
	and entry.objectIndex >= 0
	and entry.objectIndex < objects:size() then

		local object =
			objects:get(
				entry.objectIndex
			)

		if object
		and object.getContainer then

			local container =
				object:getContainer()

			if container
			and tostring(
				container:getType()
			) == entry.containerType then

				return container
			end
		end
	end


	----------------------------------------------------
	-- FALLBACK:
	-- SEARCH ALL OBJECTS ON THE SQUARE
	----------------------------------------------------

	for i = 0, objects:size() - 1 do

		local object =
			objects:get(i)

		if object
		and object.getContainer then

			local container =
				object:getContainer()

			if container
			and tostring(
				container:getType()
			) == entry.containerType then

				return container
			end
		end
	end

	return nil
end

--------------------------------------------------------
-- RETRY RESTORE AFTER WORLD LOAD
--------------------------------------------------------

local function updateSupplyRestore()
	if not ConstructionPlanner.supplyRestorePending then
		return
	end

	local data =
		getSaveData()

	if not data.containers then
		ConstructionPlanner.supplyRestorePending =
			false

		return
	end

	local missing = 0

	for _, entry in pairs(
		data.containers
	) do

		local container =
			findSavedContainer(
				entry
			)

		if container then

			if not ConstructionPlanner.supplyContainers[
				container
			] then

				ConstructionPlanner.supplyContainers[
					container
				] = true

				cpDebug(
					"[ConstructionPlanner] Late-restored supply container: "
					.. tostring(
						container:getType()
					)
				)
			end

		else

			missing =
				missing + 1
		end
	end

	if missing == 0 then

		ConstructionPlanner.supplyRestorePending =
			false

		cpDebug(
			"[ConstructionPlanner] All saved supply containers restored"
		)
	end
end


--------------------------------------------------------
-- CHECK WHETHER SAVE DATA ALREADY CONTAINS CONTAINER
--------------------------------------------------------

local function saveDataContainsContainer(
	container
)
	local entry =
		makeContainerSaveEntry(
			container
		)

	if not entry then
		return false
	end

	local data =
		getSaveData()

	for _, savedEntry in pairs(
		data.containers
	) do

		if sameSaveEntry(
			entry,
			savedEntry
		) then

			return true
		end
	end

	return false
end


--------------------------------------------------------
-- ADD SUPPLY CONTAINER
--------------------------------------------------------

local function addSupplyContainer(
	container
)
	if not container then
		return
	end

	if isSelected(container) then
		return
	end

	ConstructionPlanner.supplyContainers[
		container
	] = true

	ConstructionPlanner.supplyAppliedCursor =
		nil

	saveSupplyContainers()

	cpDebug(
		"[ConstructionPlanner] Added supply container: "
		.. tostring(
			container:getType()
		)
	)

	cpDebug(
		"[ConstructionPlanner] Supply containers selected: "
		.. tostring(
			getSelectedCount()
		)
	)
end

--------------------------------------------------------
-- EXPOSE ADD SUPPLY CONTAINER
--------------------------------------------------------

ConstructionPlanner.addSupplyContainer =
	addSupplyContainer

--------------------------------------------------------
-- REMOVE SUPPLY CONTAINER
--------------------------------------------------------

local function removeSupplyContainer(
	container
)
	if not container then
		return
	end

	if not isSelected(container) then
		return
	end

	ConstructionPlanner.supplyContainers[
		container
	] = nil

	ConstructionPlanner.supplyAppliedCursor =
		nil

	saveSupplyContainers()

	cpDebug(
		"[ConstructionPlanner] Removed supply container: "
		.. tostring(
			container:getType()
		)
	)

	cpDebug(
		"[ConstructionPlanner] Supply containers selected: "
		.. tostring(
			getSelectedCount()
		)
	)
end


--------------------------------------------------------
-- CLEAR SUPPLY CONTAINERS
--------------------------------------------------------

local function clearSupplyContainers()
	ConstructionPlanner.supplyContainers =
		{}

	ConstructionPlanner.supplyAppliedCursor =
		nil

	ConstructionPlanner.supplyRestorePending =
		false

	saveSupplyContainers()

	cpDebug(
		"[ConstructionPlanner] Cleared all supply containers"
	)

	cpDebug(
		"[ConstructionPlanner] Supply containers selected: 0"
	)
end


--------------------------------------------------------
-- CONTEXT MENU
--------------------------------------------------------

local function addContextMenu(
	playerNum,
	context,
	worldObjects
)
	if not worldObjects then
		return
	end

	local worldObject =
		worldObjects[1]

	if not worldObject then
		return
	end

	local container =
		getContainerFromWorldObject(
			worldObject
		)

	-- Only show DragBuilder on actual
	-- storage containers.
	if not container then
		return
	end

	local mainOption =
		context:addOption(
			"Better Building"
		)

	local subMenu =
		ISContextMenu:getNew(
			context
		)

	context:addSubMenu(
		mainOption,
		subMenu
	)


	if isSelected(container) then

		subMenu:addOption(
			"Remove from Supplies",
			container,
			removeSupplyContainer
		)

	else

		subMenu:addOption(
			"Add to Supplies",
			container,
			addSupplyContainer
		)
	end


	local count =
		getSelectedCount()

	if count > 0 then

		subMenu:addOption(
			"Clear All Supplies ("
				.. tostring(count)
				.. " selected)",

			nil,
			clearSupplyContainers
		)
	end
end


--------------------------------------------------------
-- BUILD CONTAINER LIST
--------------------------------------------------------

local function listHasContainer(
	containerList,
	target
)
	if not containerList
	or not target then

		return false
	end

	if containerList.size
	and containerList.get then

		for i = 0,
			containerList:size() - 1 do

			if containerList:get(i)
			== target then

				return true
			end
		end
	end

	return false
end


local function addContainerToList(
	containerList,
	container
)
	if not containerList
	or not container then

		return
	end

	if listHasContainer(
		containerList,
		container
	) then

		return
	end

	if containerList.add then
		containerList:add(
			container
		)
	end
end


--------------------------------------------------------
-- COMBINE VANILLA + SUPPLY CONTAINERS
--------------------------------------------------------

local function buildCombinedContainerList(
	playerObj
)
	local containers =
		ISInventoryPaneContextMenu.getContainers(
			playerObj
		)

	if not containers then
		return nil
	end

	local added = 0

	for container, selected in pairs(
		ConstructionPlanner.supplyContainers
	) do

		if selected then

			if not listHasContainer(
				containers,
				container
			) then

				addContainerToList(
					containers,
					container
				)

				added =
					added + 1
			end
		end
	end

	return containers, added
end


--------------------------------------------------------
-- EXPOSE SUPPLY CONTAINER HELPERS
--------------------------------------------------------

local saveSupplyContainers


local function isValidSupplyContainer(
	container
)
	if not container then
		return false
	end

	local parent =
		getContainerWorldObject(
			container
		)

	if not parent then
		return false
	end

	--------------------------------------------------------
	-- CONTAINER MUST STILL BELONG TO A WORLD OBJECT
	--------------------------------------------------------

	local square =
		getContainerSquare(
			container
		)

	if not square then
		return false
	end

	--------------------------------------------------------
	-- DESTROYED / PICKED-UP WORLD OBJECTS SHOULD NO
	-- LONGER HAVE A VALID OBJECT INDEX
	--------------------------------------------------------

	if parent.getObjectIndex then

		local objectIndex =
			parent:getObjectIndex()

		if objectIndex == nil
		or objectIndex < 0 then

			return false
		end
	end

	--------------------------------------------------------
	-- PARENT ITSELF MUST STILL BE ON A WORLD SQUARE
	--------------------------------------------------------

	if parent.getSquare then

		local parentSquare =
			parent:getSquare()

		if not parentSquare then
			return false
		end

		if parentSquare ~= square then
			return false
		end
	end

	return true
end


ConstructionPlanner.getSupplyContainerCount =
function()
	return getSelectedCount()
end


ConstructionPlanner.getSupplyContainers =
function()
	local containers = {}

	local invalid =
		{}

	for container, selected in pairs(
		ConstructionPlanner.supplyContainers
	) do

		if selected then

			if isValidSupplyContainer(
				container
			) then

				table.insert(
					containers,
					container
				)

			else

				table.insert(
					invalid,
					container
				)
			end
		end
	end

	--------------------------------------------------------
	-- REMOVE DESTROYED / PICKED-UP SUPPLY CONTAINERS
	--------------------------------------------------------

	if #invalid > 0 then

		for _, container in ipairs(
			invalid
		) do

			ConstructionPlanner.supplyContainers[
				container
			] = nil

			cpDebug(
				"[ConstructionPlanner] Removed invalid supply container"
			)
		end

		----------------------------------------------------
		-- SAVE THE CLEANED LIST IMMEDIATELY
		----------------------------------------------------

		if saveSupplyContainers then

			saveSupplyContainers()
		end
	end

	return containers
end


ConstructionPlanner.isSupplyContainer =
function(container)
	return isSelected(
		container
	)
end


--------------------------------------------------------
-- APPLY SUPPLIES TO CURRENT BUILD CURSOR
--------------------------------------------------------

local function updateBuildContainers()
	if not ConstructionPlanner.plannerEnabled then

		ConstructionPlanner.supplyAppliedCursor =
			nil

		return
	end

	if getSelectedCount() == 0 then

		ConstructionPlanner.supplyAppliedCursor =
			nil

		return
	end

	local cursor =
		ConstructionPlanner.currentCursor

	if not cursor then
		return
	end

	if not cursor.buildPanelLogic then
		return
	end

	local playerObj =
		cursor.character

	if not playerObj then

		playerObj =
			getSpecificPlayer(
				cursor.player or 0
			)
	end

	if not playerObj then
		return
	end

	local containers, added =
		buildCombinedContainerList(
			playerObj
		)

	if not containers then
		return
	end

	cursor.containers =
		containers

	if cursor.buildPanelLogic.setContainers then

		cursor.buildPanelLogic:setContainers(
			containers
		)
	end

	if ConstructionPlanner.supplyAppliedCursor
	~= cursor then

		ConstructionPlanner.supplyAppliedCursor =
			cursor

		cpDebug(
			"[ConstructionPlanner] Connected "
			.. tostring(
				getSelectedCount()
			)
			.. " supply container(s) to BuildLogic"
		)

		cpDebug(
			"[ConstructionPlanner] Newly added to vanilla container list: "
			.. tostring(added)
		)
	end
end


--------------------------------------------------------
-- GAME START
--------------------------------------------------------

local function loadSupplyContainers()
	local data =
		getSaveData()

	--------------------------------------------------------
	-- REBUILD RUNTIME LIST FROM SAVE DATA
	--------------------------------------------------------

	ConstructionPlanner.supplyContainers =
		{}

	local loaded =
		0

	local missing =
		0

	for _, entry in pairs(
		data.containers or {}
	) do

		local container =
			findSavedContainer(
				entry
			)

		if container
		and isValidSupplyContainer(
			container
		) then

			ConstructionPlanner.supplyContainers[
				container
			] = true

			loaded =
				loaded + 1

		else

			------------------------------------------------
			-- DO NOT DELETE IT FROM SAVE DATA.
			--
			-- THE SQUARE MAY SIMPLY NOT BE LOADED YET.
			------------------------------------------------

			missing =
				missing + 1
		end
	end

	ConstructionPlanner.supplyRestorePending =
		missing > 0

	cpDebug(
		"[ConstructionPlanner] Restored "
		.. tostring(loaded)
		.. " supply container(s)"
	)

	if missing > 0 then

		cpDebug(
			"[ConstructionPlanner] Waiting to restore "
			.. tostring(missing)
			.. " supply container(s)"
		)
	end
end


--------------------------------------------------------
-- EVENTS
--------------------------------------------------------

Events.OnFillWorldObjectContextMenu.Add(
	addContextMenu
)

Events.OnGameStart.Add(
	loadSupplyContainers
)

Events.OnTick.Add(
	updateSupplyRestore
)