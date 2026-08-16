require "GatherAreaManager"
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

ConstructionPlanner.previewRemovalMode =
	ConstructionPlanner.previewRemovalMode
	or false

ConstructionPlanner.projectPanelPage =
	ConstructionPlanner.projectPanelPage
	or "plan"

------------------------------------------------------------
-- PANEL CLASS
------------------------------------------------------------

DragBuilderProjectPanel = ISPanel:derive("DragBuilderProjectPanel")

function DragBuilderProjectPanel:new(x, y, width, height)
	local o = ISPanel.new(
		self,
		x,
		y,
		width,
		height
	)

	o.moveWithMouse = true

	o.fixedWidth = width
	o.minimumWidth = width
	o.minimumHeight = 300

	o.scrollOffset = 0
	o.contentHeight = 0

	o.resizing = false
	o.resizeStartMouseX = 0
	o.resizeStartMouseY = 0
	o.resizeStartWidth = width
	o.resizeStartHeight = height

	return o
end

function DragBuilderProjectPanel:initialise()
	ISPanel.initialise(self)
end

function DragBuilderProjectPanel:createChildren()
	ISPanel.createChildren(self)
end

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

local function hasTableEntries(t)
	if not t then
		return false
	end

	for _, _ in pairs(t) do
		return true
	end

	return false
end

local function isPointInsideRect(x, y, rect)
	return rect
		and x >= rect.x
		and x <= rect.x + rect.w
		and y >= rect.y
		and y <= rect.y + rect.h
end

local function panelMouseOverRect(panel, rect)
	if not panel or not rect then
		return false
	end

	return isPointInsideRect(
		panel:getMouseX(),
		panel:getMouseY(),
		rect
	)
end

local function getMaterialDisplayName(fullType)
	local displayName = tostring(fullType)

	if string.sub(displayName, 1, 5) == "Base." then
		displayName = string.sub(displayName, 6)
	end

	return displayName
end


local function drawWrappedText(panel, text, x, y, maxWidth, r, g, b, a, font)
	local words = {}
	for word in string.gmatch(tostring(text or ""), "%S+") do
		table.insert(words, word)
	end

	if #words == 0 then
		return y
	end

	local line = ""
	local lineHeight = 18
	local textManager = getTextManager()

	for _, word in ipairs(words) do
		local candidate = line == "" and word or (line .. " " .. word)
		local width = textManager:MeasureStringX(font, candidate)

		if line ~= "" and width > maxWidth then
			panel:drawText(line, x, y, r, g, b, a, font)
			y = y + lineHeight
			line = word
		else
			line = candidate
		end
	end

	if line ~= "" then
		panel:drawText(line, x, y, r, g, b, a, font)
		y = y + lineHeight
	end

	return y
end

function DragBuilderProjectPanel:getVisibleContentHeight()
	local titleHeight = 34
	local tabsHeight = 34
	local footerHeight = 0

	local page =
		ConstructionPlanner.projectPanelPage
		or "plan"

	if page == "plan" then
		footerHeight = 78
	elseif page == "gather" then
		footerHeight = 42
	end

	local visibleHeight =
		self.height
		- titleHeight
		- tabsHeight
		- footerHeight
		- 8

	if visibleHeight < 1 then
		visibleHeight = 1
	end

	return visibleHeight
end

function DragBuilderProjectPanel:getMaximumScroll()
	local visibleHeight = self:getVisibleContentHeight()

	local maxScroll =
		self.contentHeight - visibleHeight

	if maxScroll < 0 then
		maxScroll = 0
	end

	return maxScroll
end

function DragBuilderProjectPanel:clampScroll()
	local maxScroll =
		self:getMaximumScroll()

	if self.scrollOffset < 0 then
		self.scrollOffset = 0
	end

	if self.scrollOffset > maxScroll then
		self.scrollOffset = maxScroll
	end
end

------------------------------------------------------------
-- DRAW PANEL
------------------------------------------------------------

function DragBuilderProjectPanel:prerender()
	ISPanel.prerender(self)

	if ConstructionPlanner.refreshAvailableMaterials then
		ConstructionPlanner.refreshAvailableMaterials()
	end

	local titleHeight = 34
	local tabsHeight = 34
	local headerHeight = titleHeight + tabsHeight
	local planControlHeight = 36
	local buildFooterHeight = 42
	local page = ConstructionPlanner.projectPanelPage or "plan"

	--------------------------------------------------------
	-- CURRENT PROJECT / TILE COUNT
	--------------------------------------------------------

	local project =
		ConstructionPlanner.pendingProject

	local remainingTiles =
		0

	if project
	and project.segments then

		for _, segment in ipairs(
			project.segments
		) do

			if segment.remainingTiles then

				remainingTiles =
					remainingTiles
					+ #segment.remainingTiles
			end
		end
	end

	local planFooterHeight = 0

	if page == "plan" then
		planFooterHeight =
			planControlHeight
			+ buildFooterHeight
	elseif page == "gather"
	or page == "dismantle" then
		planFooterHeight =
			buildFooterHeight
	end

	local contentTop = headerHeight + 4
	local contentBottom = self.height - planFooterHeight - 4
	local visibleContentHeight = contentBottom - contentTop
	if visibleContentHeight < 1 then visibleContentHeight = 1 end

	-- Main background.
	self:drawRect(0, 0, self.width, self.height, 0.92, 0.06, 0.06, 0.06)
	self:drawRectBorder(0, 0, self.width, self.height, 1, 0.65, 0.65, 0.65)

	-- Title bar.
	self:drawRect(
		0,
		0,
		self.width,
		titleHeight,
		0.98,
		0,
		0,
		0
	)

	self:drawText(
		"Better Building",
		10,
		5,
		1,
		1,
		1,
		1,
		UIFont.Medium
	)

	--------------------------------------------------------
	-- CLOSE BUTTON
	--------------------------------------------------------

	local closeSize =
		22

	local closeX =
		self.width
		- closeSize
		- 6

	local closeY =
		6

	self.closeButtonX =
		closeX

	self.closeButtonY =
		closeY

	self.closeButtonSize =
		closeSize

	local closeRect = { x = closeX, y = closeY, w = closeSize, h = closeSize }
	local closeHover = panelMouseOverRect(self, closeRect)

	self:drawRect(
		closeX,
		closeY,
		closeSize,
		closeSize,
		closeHover and 0.62 or 0.38,
		closeHover and 0.34 or 0.22,
		closeHover and 0.34 or 0.22,
		closeHover and 0.34 or 0.22
	)

	self:drawRectBorder(
		closeX,
		closeY,
		closeSize,
		closeSize,
		1,
		0.5,
		0.5,
		0.5
	)

	self:drawTextCentre(
		"X",
		closeX + closeSize / 2,
		closeY + 1,
		1,
		0.25,
		0.25,
		1,
		UIFont.Small
	)

	--------------------------------------------------------
	-- TILE COUNT BADGE
	--------------------------------------------------------

	local tileBadgeW =
		88

	local tileBadgeH =
		22

	local tileBadgeX =
		closeX
		- tileBadgeW
		- 8

	local tileBadgeY =
		6

	self:drawRect(
		tileBadgeX,
		tileBadgeY,
		tileBadgeW,
		tileBadgeH,
		0.62,
		0.18,
		0.18,
		0.18
	)

	self:drawRectBorder(
		tileBadgeX,
		tileBadgeY,
		tileBadgeW,
		tileBadgeH,
		1,
		0.85,
		0.85,
		0.85
	)

	self:drawTextCentre(
		"Tiles: "
		.. tostring(
			remainingTiles
		),
		tileBadgeX + tileBadgeW / 2,
		tileBadgeY - 2,
		1,
		0.9,
		0.5,
		1,
		UIFont.Small
	)

	--------------------------------------------------------
	-- MODE / TOOL ROW
	--------------------------------------------------------

	local navY = titleHeight + 5
	local navH = 23
	local navMargin = 8
	local navGap = 8
	local selectorW = 150
	local placementW = 170
	local heightGap = 8
	local heightMinusW = 28
	local heightLabelW = 78
	local heightPlusW = 28

	local modeLabels = {
		gather = "Gather Area",
		plan = "Plan",
		quick = "Quick",
		destroy = "Destroy",
		dismantle = "Dismantle",
		off = "Off"
	}

	local modeLabel =
		modeLabels[page]
		or "Plan"

	self.modeSelectorButton = {
		x = navMargin,
		y = navY,
		w = selectorW,
		h = navH
	}

	local mouseX = self:getMouseX()
	local mouseY = self:getMouseY()

	local function isHovering(rect)
		return rect
			and mouseX >= rect.x
			and mouseX <= rect.x + rect.w
			and mouseY >= rect.y
			and mouseY <= rect.y + rect.h
	end

	local selectorHover =
		isHovering(self.modeSelectorButton)

	self:drawRect(
		self.modeSelectorButton.x,
		self.modeSelectorButton.y,
		self.modeSelectorButton.w,
		self.modeSelectorButton.h,
		selectorHover and 0.72 or 0.50,
		selectorHover and 0.28 or 0.20,
		selectorHover and 0.28 or 0.20,
		selectorHover and 0.28 or 0.20
	)

	self:drawRectBorder(
		self.modeSelectorButton.x,
		self.modeSelectorButton.y,
		self.modeSelectorButton.w,
		self.modeSelectorButton.h,
		1,
		selectorHover and 1.0 or 0.85,
		selectorHover and 1.0 or 0.85,
		selectorHover and 1.0 or 0.85
	)

	self:drawTextCentre(
		modeLabel .. " v",
		self.modeSelectorButton.x + self.modeSelectorButton.w / 2,
		self.modeSelectorButton.y - 3,
		1,
		1,
		1,
		1,
		UIFont.Small
	)

	local showPlacement =
		page == "plan"
		or page == "quick"
		or page == "destroy"
		or page == "dismantle"

	if showPlacement then
		local placementMode =
			ConstructionPlanner.getPlacementMode
			and ConstructionPlanner.getPlacementMode()
			or "area"

		local prefix =
			(page == "plan" or page == "quick")
			and "Placement: "
			or "Selection: "

		local placementLabel =
			prefix
			.. (placementMode == "area" and "Area" or "Line")

		self.placementButtonX =
			navMargin + selectorW + navGap

		self.placementButtonY =
			navY

		self.placementButtonWidth =
			placementW

		self.placementButtonHeight =
			navH

		local placementRect = {
			x = self.placementButtonX,
			y = self.placementButtonY,
			w = self.placementButtonWidth,
			h = self.placementButtonHeight
		}

		local placementHover =
			isHovering(placementRect)

		self:drawRect(
			placementRect.x,
			placementRect.y,
			placementRect.w,
			placementRect.h,
			placementHover and 0.72 or 0.50,
			placementHover and 0.28 or 0.20,
			placementHover and 0.28 or 0.20,
			placementHover and 0.28 or 0.20
		)

		self:drawRectBorder(
			placementRect.x,
			placementRect.y,
			placementRect.w,
			placementRect.h,
			1,
			placementHover and 1.0 or 0.85,
			placementHover and 1.0 or 0.85,
			placementHover and 1.0 or 0.85
		)

		self:drawTextCentre(
			placementLabel,
			placementRect.x + placementRect.w / 2,
			placementRect.y - 3,
			1,
			1,
			1,
			1,
			UIFont.Small
		)

		----------------------------------------------------
		-- PLAN HEIGHT CONTROL
		----------------------------------------------------

		if page == "plan" then

			local heightX =
				placementRect.x
				+ placementRect.w
				+ heightGap

			self.heightMinusButton = {
				x = heightX,
				y = navY,
				w = heightMinusW,
				h = navH
			}

			self.heightLabelButton = {
				x = heightX + heightMinusW,
				y = navY,
				w = heightLabelW,
				h = navH
			}

			self.heightPlusButton = {
				x = heightX + heightMinusW + heightLabelW,
				y = navY,
				w = heightPlusW,
				h = navH
			}

			local minusHover = isHovering(self.heightMinusButton)
			local plusHover = isHovering(self.heightPlusButton)

			for _, rect in ipairs({
				self.heightMinusButton,
				self.heightLabelButton,
				self.heightPlusButton
			}) do
				self:drawRect(
					rect.x, rect.y, rect.w, rect.h,
					0.50, 0.20, 0.20, 0.20
				)

				self:drawRectBorder(
					rect.x, rect.y, rect.w, rect.h,
					1, 0.85, 0.85, 0.85
				)
			end

			if minusHover then
				self:drawRect(
					self.heightMinusButton.x, self.heightMinusButton.y,
					self.heightMinusButton.w, self.heightMinusButton.h,
					0.72, 0.28, 0.28, 0.28
				)
			end

			if plusHover then
				self:drawRect(
					self.heightPlusButton.x, self.heightPlusButton.y,
					self.heightPlusButton.w, self.heightPlusButton.h,
					0.72, 0.28, 0.28, 0.28
				)
			end

			local heightOffset =
				ConstructionPlanner.getPlanHeightOffset
				and ConstructionPlanner.getPlanHeightOffset()
				or 0

			self:drawTextCentre(
				"-",
				self.heightMinusButton.x + self.heightMinusButton.w / 2,
				self.heightMinusButton.y - 3,
				1, 1, 1, 1, UIFont.Small
			)

			self:drawTextCentre(
				"Z +" .. tostring(heightOffset),
				self.heightLabelButton.x + self.heightLabelButton.w / 2,
				self.heightLabelButton.y - 3,
				1, 1, 1, 1, UIFont.Small
			)

			self:drawTextCentre(
				"+",
				self.heightPlusButton.x + self.heightPlusButton.w / 2,
				self.heightPlusButton.y - 3,
				1, 1, 1, 1, UIFont.Small
			)

		else

			self.heightMinusButton = nil
			self.heightLabelButton = nil
			self.heightPlusButton = nil
		end
	else
		self.placementButtonX = nil
		self.placementButtonY = nil
		self.placementButtonWidth = nil
		self.placementButtonHeight = nil
		self.heightMinusButton = nil
		self.heightLabelButton = nil
		self.heightPlusButton = nil
	end


	-- Middle content box.
	local contentX = 6
	local contentWidth = self.width - 12
	self:drawRect(contentX, contentTop, contentWidth, visibleContentHeight, 0.95, 0.12, 0.12, 0.12)
	self:drawRectBorder(contentX, contentTop, contentWidth, visibleContentHeight, 1, 0.48, 0.48, 0.48)

	self:setStencilRect(contentX + 1, contentTop + 1, contentWidth - 10, visibleContentHeight - 2)
	local textLeft = contentX + 12
	local y = contentTop + 10 - self.scrollOffset
	local contentStartY = y
	if page == "plan" then
		if not project then
			self:drawText("No active project", textLeft, y, 0.8, 0.8, 0.8, 1, UIFont.Small)
			y = y + 20
		else
			self:drawText("Materials Required", textLeft, y, 1, 0.9, 0.5, 1, UIFont.Small)
			y = y + 24
			local materials = project.requiredMaterials
			if not hasTableEntries(materials) then
				self:drawText("Not calculated yet", textLeft + 8, y, 0.8, 0.8, 0.8, 1, UIFont.Small)
				y = y + 18
			else
				for fullType, required in pairs(materials) do
					local displayName = getMaterialDisplayName(fullType)
					local available = 0
					if project.availableMaterials then available = project.availableMaterials[fullType] or 0 end
					self:drawText(displayName .. " " .. tostring(available) .. "/" .. tostring(required), textLeft + 8, y, 1, 1, 1, 1, UIFont.Small)
					y = y + 18
				end
			end
			y = y + 12
			self:drawText("Tools Required", textLeft, y, 1, 0.9, 0.5, 1, UIFont.Small)
			y = y + 24

			local toolStatus =
				ConstructionPlanner.getProjectToolStatus
				and ConstructionPlanner.getProjectToolStatus()
				or {
					allAvailable = true,
					requirements = {}
				}

			if not toolStatus.requirements
			or #toolStatus.requirements == 0 then

				self:drawText(
					"None",
					textLeft + 8,
					y,
					0.70,
					0.90,
					0.70,
					1,
					UIFont.Small
				)

				y = y + 18

			else

				for _, row in ipairs(
					toolStatus.requirements
				) do

					local prefix =
						row.available
						and "[OK] "
						or "[MISSING] "

					local sourceText =
						row.available
						and (
							" - "
							.. tostring(
								row.sourceLabel
								or "Available"
							)
						)
						or ""

					self:drawText(
						prefix
						.. tostring(
							row.label
							or "Tool"
						)
						.. sourceText,
						textLeft + 8,
						y,
						row.available and 0.55 or 1.0,
						row.available and 1.0 or 0.35,
						row.available and 0.55 or 0.35,
						1,
						UIFont.Small
					)

					y = y + 18
				end
			end
			y = y + 12
		end
	elseif page == "quick" then
		self:drawText("Quick building is active.", textLeft, y, 0.9, 0.9, 0.9, 1, UIFont.Small)
		y = y + 20
	elseif page == "gather" then
		self:drawText("Gather Areas", textLeft, y, 1, 0.9, 0.5, 1, UIFont.Small)
		y = y + 24

		self:drawText(
			"PLAN MODE REMAINS ACTIVE",
			textLeft,
			y,
			1,
			0.75,
			0.35,
			1,
			UIFont.Small
		)
		y = y + 22

		y = drawWrappedText(
			self,
			"Gather Area is a management page. Your planned project remains active and can still be removed or built from the controls below.",
			textLeft,
			y,
			contentWidth - 28,
			0.85,
			0.85,
			0.85,
			1,
			UIFont.Small
		)
		y = y + 10

		local gatherCount =
			ConstructionPlanner.getGatherAreaCount
			and ConstructionPlanner.getGatherAreaCount()
			or 0

		self:drawText(
			"Saved Areas: " .. tostring(gatherCount),
			textLeft,
			y,
			0.9,
			0.9,
			0.9,
			1,
			UIFont.Small
		)
		y = y + 22

		local gatherSelecting =
			ConstructionPlanner.gatherAreaArmed
			or ConstructionPlanner.gatherAreaSelecting

		local setText =
			gatherSelecting
			and "Setting Area..."
			or "Set"

		local highlightText =
			ConstructionPlanner.gatherAreaHighlight == false
			and "Highlight: OFF"
			or "Highlight: ON"

		local buttonGap = 8
		local buttonHeight = 26
		local availableWidth = contentWidth - 24
		local buttonWidth = (availableWidth - buttonGap * 2) / 3
		local buttonY = y

		self.gatherSetButton = {
			x = textLeft,
			y = buttonY,
			w = buttonWidth,
			h = buttonHeight
		}

		self.gatherRemoveAllButton = {
			x = textLeft + buttonWidth + buttonGap,
			y = buttonY,
			w = buttonWidth,
			h = buttonHeight
		}

		self.gatherHighlightButton = {
			x = textLeft + (buttonWidth + buttonGap) * 2,
			y = buttonY,
			w = buttonWidth,
			h = buttonHeight
		}

		local gatherButtons = {
			{ rect = self.gatherSetButton, text = setText },
			{ rect = self.gatherRemoveAllButton, text = "Remove All" },
			{ rect = self.gatherHighlightButton, text = highlightText }
		}

		for _, button in ipairs(gatherButtons) do
			local hover = panelMouseOverRect(self, button.rect)
			self:drawRect(
				button.rect.x,
				button.rect.y,
				button.rect.w,
				button.rect.h,
				hover and 0.70 or 0.50,
				hover and 0.28 or 0.20,
				hover and 0.28 or 0.20,
				hover and 0.28 or 0.20
			)

			self:drawRectBorder(
				button.rect.x,
				button.rect.y,
				button.rect.w,
				button.rect.h,
				1,
				0.85,
				0.85,
				0.85
			)

			self:drawTextCentre(
				button.text,
				button.rect.x + button.rect.w / 2,
				button.rect.y + 2,
				1,
				1,
				1,
				1,
				UIFont.Small
			)
		end

		y = y + buttonHeight + 14

		if gatherSelecting then
			y = drawWrappedText(
				self,
				"Drag a rectangle on the ground to add a Gather Area.",
				textLeft,
				y,
				contentWidth - 28,
				0.85,
				0.85,
				0.85,
				1,
				UIFont.Small
			)
		else
			y = drawWrappedText(
				self,
				"Loose ground materials inside saved Gather Areas can be used as material sources once Gather Area sourcing is connected to distribution.",
				textLeft,
				y,
				contentWidth - 28,
				0.85,
				0.85,
				0.85,
				1,
				UIFont.Small
			)
		end
	elseif page == "destroy" then

		self:drawText(
			"Destroy",
			textLeft,
			y,
			1,
			0.9,
			0.5,
			1,
			UIFont.Medium
		)

		y = y + 30

		local selectedCount =
			ConstructionPlanner.getDestroySelectionCount
			and ConstructionPlanner.getDestroySelectionCount()
			or 0

		self:drawText(
			"Selected Objects: "
			.. tostring(selectedCount),
			textLeft,
			y,
			1,
			1,
			1,
			1,
			UIFont.Small
		)

		y = y + 24

		y = drawWrappedText(
			self,
			"Drag over world objects to select them for vanilla Sledgehammer destruction. Missing Sledgehammer is fetched automatically from inventory, Supply Containers, then Gather Areas.",
			textLeft,
			y,
			contentWidth - 28,
			0.85,
			0.85,
			0.85,
			1,
			UIFont.Small
		)

		y = y + 12

		self:drawText(
			"Tools Required:",
			textLeft,
			y,
			1,
			0.9,
			0.5,
			1,
			UIFont.Small
		)

		y = y + 21

		local toolStatus =
			ConstructionPlanner.getDestroyToolStatus
			and ConstructionPlanner.getDestroyToolStatus()
			or {
				allAvailable = false,
				requirements = {
					{
						label = "Sledgehammer",
						available = false,
						sourceLabel = "Missing"
					}
				}
			}

		for _, row in ipairs(
			toolStatus.requirements
			or {}
		) do

			local prefix =
				row.available
				and "[OK] "
				or "[MISSING] "

			local sourceText =
				row.available
				and (
					" - "
					.. tostring(
						row.sourceLabel
						or "Available"
					)
				)
				or ""

			self:drawText(
				prefix
				.. tostring(
					row.label
					or "Sledgehammer"
				)
				.. sourceText,
				textLeft + 10,
				y,
				row.available and 0.55 or 1.0,
				row.available and 1.0 or 0.35,
				row.available and 0.55 or 0.35,
				1,
				UIFont.Small
			)

			y = y + 20
		end

		y = y + 8

		local clearW = 150
		local clearH = 26

		self.destroyClearButton = {
			x = textLeft,
			y = y,
			w = clearW,
			h = clearH
		}

		local clearHover =
			panelMouseOverRect(
				self,
				self.destroyClearButton
			)

		self:drawRect(
			self.destroyClearButton.x,
			self.destroyClearButton.y,
			self.destroyClearButton.w,
			self.destroyClearButton.h,
			clearHover and 0.68 or 0.48,
			clearHover and 0.28 or 0.20,
			clearHover and 0.28 or 0.20,
			clearHover and 0.28 or 0.20
		)

		self:drawRectBorder(
			self.destroyClearButton.x,
			self.destroyClearButton.y,
			self.destroyClearButton.w,
			self.destroyClearButton.h,
			1,
			0.85,
			0.85,
			0.85
		)

		self:drawTextCentre(
			"Clear Selection",
			self.destroyClearButton.x
				+ self.destroyClearButton.w / 2,
			self.destroyClearButton.y + 2,
			1,
			1,
			1,
			1,
			UIFont.Small
		)

		y = y + clearH + 10
	elseif page == "dismantle" then

		self:drawText(
			"Dismantle",
			textLeft,
			y,
			1,
			0.9,
			0.5,
			1,
			UIFont.Medium
		)

		y = y + 30

		local selectedCount =
			ConstructionPlanner.getDismantleSelectionCount
			and ConstructionPlanner.getDismantleSelectionCount()
			or 0

		self:drawText(
			"Selected Objects: "
			.. tostring(selectedCount),
			textLeft,
			y,
			1,
			1,
			1,
			1,
			UIFont.Small
		)

		y = y + 24

		y = drawWrappedText(
			self,
			"Only objects that vanilla can Disassemble are selectable. Missing tools are fetched automatically from inventory, Supply Containers, then Gather Areas.",
			textLeft,
			y,
			contentWidth - 28,
			0.85,
			0.85,
			0.85,
			1,
			UIFont.Small
		)

		y = y + 12

		----------------------------------------------------
		-- REQUIRED TOOLS
		----------------------------------------------------

		self:drawText(
			"Tools Required:",
			textLeft,
			y,
			1,
			0.9,
			0.5,
			1,
			UIFont.Small
		)

		y = y + 21

		local toolStatus =
			ConstructionPlanner.getDismantleToolStatus
			and ConstructionPlanner.getDismantleToolStatus()
			or {
				allAvailable = true,
				requirements = {}
			}

		if not toolStatus.requirements
		or #toolStatus.requirements == 0 then

			self:drawText(
				"None",
				textLeft + 10,
				y,
				0.70,
				0.90,
				0.70,
				1,
				UIFont.Small
			)

			y = y + 20

		else

			for _, row in ipairs(
				toolStatus.requirements
			) do

				local prefix =
					row.available
					and "[OK] "
					or "[MISSING] "

				local sourceText =
					row.available
					and (
						" - "
						.. tostring(
							row.sourceLabel
							or "Available"
						)
					)
					or ""

				self:drawText(
					prefix
					.. tostring(
						row.label
						or "Tool"
					)
					.. sourceText,
					textLeft + 10,
					y,
					row.available and 0.55 or 1.0,
					row.available and 1.0 or 0.35,
					row.available and 0.55 or 0.35,
					1,
					UIFont.Small
				)

				y = y + 20
			end
		end

		y = y + 8

		local clearW = 150
		local clearH = 26

		self.dismantleClearButton = {
			x = textLeft,
			y = y,
			w = clearW,
			h = clearH
		}

		local clearHover =
			panelMouseOverRect(
				self,
				self.dismantleClearButton
			)

		self:drawRect(
			self.dismantleClearButton.x,
			self.dismantleClearButton.y,
			self.dismantleClearButton.w,
			self.dismantleClearButton.h,
			clearHover and 0.68 or 0.48,
			clearHover and 0.28 or 0.20,
			clearHover and 0.28 or 0.20,
			clearHover and 0.28 or 0.20
		)

		self:drawRectBorder(
			self.dismantleClearButton.x,
			self.dismantleClearButton.y,
			self.dismantleClearButton.w,
			self.dismantleClearButton.h,
			1,
			0.85,
			0.85,
			0.85
		)

		self:drawTextCentre(
			"Clear Selection",
			self.dismantleClearButton.x
				+ self.dismantleClearButton.w / 2,
			self.dismantleClearButton.y + 2,
			1,
			1,
			1,
			1,
			UIFont.Small
		)

		y = y + clearH + 10
	elseif page == "off" then
		self:drawText("Better Building is disabled.", textLeft, y, 1, 0.9, 0.5, 1, UIFont.Small)
		y = y + 22
		self:drawText("Returned to vanilla building.", textLeft, y, 0.9, 0.9, 0.9, 1, UIFont.Small)
		y = y + 20
	end

	self.contentHeight = y - contentStartY + 12
	self:clearStencilRect()
	self:clampScroll()

	-- Scroll bar.
	local maxScroll = self:getMaximumScroll()
	if maxScroll > 0 then
		local trackY = contentTop + 3
		local trackHeight = visibleContentHeight - 6
		local visibleHeight = visibleContentHeight
		local thumbHeight = math.max(24, trackHeight * (visibleHeight / self.contentHeight))
		if thumbHeight > trackHeight then thumbHeight = trackHeight end
		local thumbY = trackY + (trackHeight - thumbHeight) * (self.scrollOffset / maxScroll)
		self:drawRect(self.width - 9, trackY, 3, trackHeight, 0.25, 0.3, 0.3, 0.3)
		self:drawRect(self.width - 9, thumbY, 3, thumbHeight, 0.8, 0.8, 0.8, 0.8)
	end

	-- Page-specific button state.
	if page ~= "gather" then
		self.gatherSetButton = nil
		self.gatherRemoveAllButton = nil
		self.gatherHighlightButton = nil
	end

	if page ~= "dismantle" then
		self.dismantleClearButton = nil
	end

	if page ~= "destroy" then
		self.destroyClearButton = nil
	end

		-- Plan/Gather footer controls.
	self.removeButtonX =
		nil

	self.removeAllPreviewsButtonX =
		nil

	self.confirmRemovalButtonX =
		nil

	self.buildButtonX =
		nil

	self.confirmDismantleButtonX =
		nil

	self.confirmDestroyButtonX =
		nil

	if page == "plan" then

		local controlY =
			self.height
			- planControlHeight
			- buildFooterHeight

		self:drawRect(
			0,
			controlY,
			self.width,
			planControlHeight,
			0.95,
			0.08,
			0.08,
			0.08
		)

		self:drawRectBorder(
			0,
			controlY,
			self.width,
			planControlHeight,
			1,
			0.35,
			0.35,
			0.35
		)

		local removeW =
			125

		local removeAllW =
			181

		local confirmW =
			145

		local buttonGap =
			8

		local removeH =
			24

		local removeY =
			controlY + 6

		local removeActive =
			false

		if page == "gather" then

			removeActive =
				ConstructionPlanner.gatherRemovalMode
				== true

		else

			removeActive =
				ConstructionPlanner.previewRemovalMode
				== true
		end

		local showRemoveAll =
			page == "plan"
			and removeActive

		local showConfirm =
			page == "plan"
			and removeActive
			and ConstructionPlanner.removeSelectionReady
				== true

		----------------------------------------------------
		-- WORK OUT TOTAL WIDTH SO BUTTON GROUP
		-- REMAINS CENTRED.
		----------------------------------------------------

		local totalWidth =
			removeW

		if showRemoveAll then

			totalWidth =
				totalWidth
				+ buttonGap
				+ removeAllW
		end

		if showConfirm then

			totalWidth =
				totalWidth
				+ buttonGap
				+ confirmW
		end

		local removeX =
			(self.width - totalWidth) / 2

		----------------------------------------------------
		-- REMOVE ON/OFF
		----------------------------------------------------

		self.removeButtonX =
			removeX

		self.removeButtonY =
			removeY

		self.removeButtonWidth =
			removeW

		self.removeButtonHeight =
			removeH

		local removeHover = panelMouseOverRect(self, { x = removeX, y = removeY, w = removeW, h = removeH })

		local removeText =
			removeActive
			and "Remove: ON"
			or "Remove: OFF"

		self:drawRect(
			removeX,
			removeY,
			removeW,
			removeH,
			removeHover and 0.68 or 0.48,
			removeHover and 0.28 or 0.20,
			removeHover and 0.28 or 0.20,
			removeHover and 0.28 or 0.20
		)

		self:drawRectBorder(
			removeX,
			removeY,
			removeW,
			removeH,
			1,
			0.85,
			0.85,
			0.85
		)

		self:drawTextCentre(
			removeText,
			removeX + removeW / 2,
			removeY + 1,
			1,
			1,
			1,
			1,
			UIFont.Small
		)

		local nextX =
			removeX
			+ removeW
			+ buttonGap

		----------------------------------------------------
		-- REMOVE ALL PREVIEWS
		----------------------------------------------------

		if showRemoveAll then

			self.removeAllPreviewsButtonX =
				nextX

			self.removeAllPreviewsButtonY =
				removeY

			self.removeAllPreviewsButtonWidth =
				removeAllW

			self.removeAllPreviewsButtonHeight =
				removeH

			local removeAllHover = panelMouseOverRect(self, { x = nextX, y = removeY, w = removeAllW, h = removeH })

			self:drawRect(
				nextX,
				removeY,
				removeAllW,
				removeH,
				removeAllHover and 0.68 or 0.48,
				removeAllHover and 0.28 or 0.20,
				removeAllHover and 0.28 or 0.20,
				removeAllHover and 0.28 or 0.20
			)

			self:drawRectBorder(
				nextX,
				removeY,
				removeAllW,
				removeH,
				1,
				0.85,
				0.85,
				0.85
			)

			self:drawTextCentre(
				"Remove All Previews",
				nextX + removeAllW / 2,
				removeY + 1,
				1,
				1,
				1,
				1,
				UIFont.Small
			)

			nextX =
				nextX
				+ removeAllW
				+ buttonGap
		end

		----------------------------------------------------
		-- CONFIRM REMOVAL
		----------------------------------------------------

		if showConfirm then

			self.confirmRemovalButtonX =
				nextX

			self.confirmRemovalButtonY =
				removeY

			self.confirmRemovalButtonWidth =
				confirmW

			self.confirmRemovalButtonHeight =
				removeH

			local confirmHover = panelMouseOverRect(self, { x = nextX, y = removeY, w = confirmW, h = removeH })

			self:drawRect(
				nextX,
				removeY,
				confirmW,
				removeH,
				confirmHover and 0.80 or 0.60,
				confirmHover and 0.42 or 0.32,
				confirmHover and 0.12 or 0.08,
				confirmHover and 0.12 or 0.08
			)

			self:drawRectBorder(
				nextX,
				removeY,
				confirmW,
				removeH,
				1,
				0.95,
				0.45,
				0.45
			)

			self:drawTextCentre(
				"Confirm Removal",
				nextX + confirmW / 2,
				removeY + 1,
				1,
				0.72,
				0.72,
				1,
				UIFont.Small
			)
		end

		----------------------------------------------------
		-- BUILD PROJECT
		----------------------------------------------------

		local buildFooterY =
			self.height
			- buildFooterHeight

		self:drawRect(
			0,
			buildFooterY,
			self.width,
			buildFooterHeight,
			0.98,
			0,
			0,
			0
		)

		local buildX =
			8

		local buildY =
			buildFooterY + 7

		local buildW =
			self.width - 16

		local buildH =
			28

		self.buildButtonX =
			buildX

		self.buildButtonY =
			buildY

		self.buildButtonWidth =
			buildW

		self.buildButtonHeight =
			buildH

		local buildHover = panelMouseOverRect(self, { x = buildX, y = buildY, w = buildW, h = buildH })

		self:drawRect(
			buildX,
			buildY,
			buildW,
			buildH,
			buildHover and 0.90 or 0.72,
			buildHover and 0.28 or 0.18,
			buildHover and 0.28 or 0.18,
			buildHover and 0.28 or 0.18
		)

		self:drawRectBorder(
			buildX,
			buildY,
			buildW,
			buildH,
			1,
			0.85,
			0.85,
			0.85
		)

		local buildText =
			ConstructionPlanner.projectBuilding
			and "Building..."
			or "Build Project"

		self:drawTextCentre(
			buildText,
			buildX + buildW / 2,
			buildY + 2,
			1,
			1,
			1,
			1,
			UIFont.Small
		)
	end

	--------------------------------------------------------
	-- DESTROY CONFIRM FOOTER
	--------------------------------------------------------

	if page == "destroy" then

		local footerY =
			self.height - buildFooterHeight

		self:drawRect(
			0,
			footerY,
			self.width,
			buildFooterHeight,
			0.98,
			0,
			0,
			0
		)

		local buttonX = 8
		local buttonY = footerY + 7
		local buttonW = self.width - 16
		local buttonH = 28

		self.confirmDestroyButtonX = buttonX
		self.confirmDestroyButtonY = buttonY
		self.confirmDestroyButtonWidth = buttonW
		self.confirmDestroyButtonHeight = buttonH

		local selectedCount =
			ConstructionPlanner.getDestroySelectionCount
			and ConstructionPlanner.getDestroySelectionCount()
			or 0

		local enabled =
			selectedCount > 0
			and ConstructionPlanner.canConfirmDestruction
			and ConstructionPlanner.canConfirmDestruction()

		local hover =
			enabled
			and panelMouseOverRect(
				self,
				{
					x = buttonX,
					y = buttonY,
					w = buttonW,
					h = buttonH
				}
			)

		self:drawRect(
			buttonX,
			buttonY,
			buttonW,
			buttonH,
			enabled
				and (hover and 0.90 or 0.72)
				or 0.42,
			enabled
				and (hover and 0.34 or 0.22)
				or 0.16,
			enabled
				and (hover and 0.18 or 0.12)
				or 0.16,
			enabled
				and (hover and 0.18 or 0.12)
				or 0.16
		)

		self:drawRectBorder(
			buttonX,
			buttonY,
			buttonW,
			buttonH,
			1,
			enabled and 0.95 or 0.45,
			enabled and 0.65 or 0.45,
			enabled and 0.45 or 0.45
		)

		local buttonText =
			ConstructionPlanner.destroyRunning
			and "Destroying..."
			or (
				ConstructionPlanner.destroyFetchingTool
				and "Fetching Sledgehammer..."
				or "Confirm Destruction"
			)

		self:drawTextCentre(
			buttonText,
			buttonX + buttonW / 2,
			buttonY + 2,
			enabled and 1 or 0.55,
			enabled and 0.85 or 0.55,
			enabled and 0.65 or 0.55,
			1,
			UIFont.Small
		)
	end


	--------------------------------------------------------
	-- DISMANTLE CONFIRM FOOTER
	--------------------------------------------------------

	if page == "dismantle" then

		local footerY =
			self.height - buildFooterHeight

		self:drawRect(
			0,
			footerY,
			self.width,
			buildFooterHeight,
			0.98,
			0,
			0,
			0
		)

		local buttonX = 8
		local buttonY = footerY + 7
		local buttonW = self.width - 16
		local buttonH = 28

		self.confirmDismantleButtonX = buttonX
		self.confirmDismantleButtonY = buttonY
		self.confirmDismantleButtonWidth = buttonW
		self.confirmDismantleButtonHeight = buttonH

		local selectedCount =
			ConstructionPlanner.getDismantleSelectionCount
			and ConstructionPlanner.getDismantleSelectionCount()
			or 0

		local enabled =
			ConstructionPlanner.canConfirmDismantling
			and ConstructionPlanner.canConfirmDismantling()
			or false

		local hover =
			enabled
			and panelMouseOverRect(
				self,
				{
					x = buttonX,
					y = buttonY,
					w = buttonW,
					h = buttonH
				}
			)

		self:drawRect(
			buttonX,
			buttonY,
			buttonW,
			buttonH,
			enabled
				and (hover and 0.90 or 0.72)
				or 0.42,
			enabled
				and (hover and 0.34 or 0.22)
				or 0.16,
			enabled
				and (hover and 0.18 or 0.12)
				or 0.16,
			enabled
				and (hover and 0.18 or 0.12)
				or 0.16
		)

		self:drawRectBorder(
			buttonX,
			buttonY,
			buttonW,
			buttonH,
			1,
			enabled and 0.95 or 0.45,
			enabled and 0.65 or 0.45,
			enabled and 0.45 or 0.45
		)

		local buttonText =
			ConstructionPlanner.dismantleRunning
			and "Dismantling..."
			or (
				ConstructionPlanner.dismantleFetchingTools
				and "Fetching Tools..."
				or (
					enabled
						and "Confirm Dismantling"
						or (
							selectedCount > 0
								and "Missing Required Tools"
								or "Confirm Dismantling"
						)
				)
			)

		self:drawTextCentre(
			buttonText,
			buttonX + buttonW / 2,
			buttonY + 2,
			enabled and 1 or 0.55,
			enabled and 0.85 or 0.55,
			enabled and 0.65 or 0.55,
			1,
			UIFont.Small
		)
	end

	--------------------------------------------------------
	-- GATHER BUILD PROJECT FOOTER
	--------------------------------------------------------

	if page == "gather" then

		local buildFooterY =
			self.height
			- buildFooterHeight

		self:drawRect(
			0,
			buildFooterY,
			self.width,
			buildFooterHeight,
			0.98,
			0,
			0,
			0
		)

		local buildX = 8
		local buildY = buildFooterY + 7
		local buildW = self.width - 16
		local buildH = 28

		self.buildButtonX = buildX
		self.buildButtonY = buildY
		self.buildButtonWidth = buildW
		self.buildButtonHeight = buildH

		local buildHover = panelMouseOverRect(self, { x = buildX, y = buildY, w = buildW, h = buildH })

		self:drawRect(
			buildX,
			buildY,
			buildW,
			buildH,
			buildHover and 0.90 or 0.72,
			buildHover and 0.28 or 0.18,
			buildHover and 0.28 or 0.18,
			buildHover and 0.28 or 0.18
		)

		self:drawRectBorder(
			buildX,
			buildY,
			buildW,
			buildH,
			1,
			0.85,
			0.85,
			0.85
		)

		local buildText =
			ConstructionPlanner.projectBuilding
			and "Building..."
			or "Build Project"

		self:drawTextCentre(
			buildText,
			buildX + buildW / 2,
			buildY + 2,
			1,
			1,
			1,
			1,
			UIFont.Small
		)
	end

	--------------------------------------------------------
	-- MODE / TOOL DROPDOWN OVERLAY
	-- DRAW LAST SO IT SITS ABOVE PANEL CONTENT
	--------------------------------------------------------

	--------------------------------------------------------
	-- MODE / TOOL DROPDOWN
	--------------------------------------------------------

	if self.modeDropdownOpen then
		local options = {
			{ key = "gather", label = "Gather Area" },
			{ key = "plan", label = "Plan" },
			{ key = "quick", label = "Quick" },
			{ key = "destroy", label = "Destroy" },
			{ key = "dismantle", label = "Dismantle" },
			{ key = "off", label = "Off" }
		}

		self.modeDropdownButtons = {}

		local rowH = 24

		for i, option in ipairs(options) do
			local rect = {
				x = navMargin,
				y = navY + navH + ((i - 1) * rowH),
				w = selectorW,
				h = rowH
			}

			self.modeDropdownButtons[option.key] =
				rect

			local hover =
				isHovering(rect)

			self:drawRect(
				rect.x,
				rect.y,
				rect.w,
				rect.h,
				hover and 1.0 or 0.98,
				hover and 0.22 or 0.10,
				hover and 0.22 or 0.10,
				hover and 0.22 or 0.10
			)

			self:drawRectBorder(
				rect.x,
				rect.y,
				rect.w,
				rect.h,
				1,
				hover and 1.0 or 0.75,
				hover and 1.0 or 0.75,
				hover and 1.0 or 0.75
			)

			self:drawTextCentre(
				option.label,
				rect.x + rect.w / 2,
				rect.y - 2,
				1,
				1,
				1,
				1,
				UIFont.Small
			)
		end
	else
		self.modeDropdownButtons = nil
	end


	-- Resize grip.
	for offset = 4, 14, 5 do
		self:drawRect(self.width - offset, self.height - 3, 2, 2, 1, 0.9, 0.9, 0.9)
	end
end

------------------------------------------------------------
-- MOUSE WHEEL
------------------------------------------------------------

function DragBuilderProjectPanel:onMouseWheel(del)
	self.scrollOffset =
		self.scrollOffset
		+ (del * 24)

	self:clampScroll()

	return true
end

------------------------------------------------------------
-- MOUSE DOWN
------------------------------------------------------------

function DragBuilderProjectPanel:onMouseDown(x, y)

	--------------------------------------------------------
	-- MODE / TOOL DROPDOWN
	--------------------------------------------------------

	if self.modeDropdownOpen
	and self.modeDropdownButtons then
		for key, rect in pairs(self.modeDropdownButtons) do
			if isPointInsideRect(x, y, rect) then
				self.modeDropdownOpen = false
				ConstructionPlanner.projectPanelPage = key
				self.scrollOffset = 0

				ConstructionPlanner.previewRemovalMode = false
				ConstructionPlanner.gatherRemovalMode = false

				if ConstructionPlanner.clearRemoveSelection then
					ConstructionPlanner.clearRemoveSelection()
				end

				if key ~= "dismantle"
				and ConstructionPlanner.clearDismantleSelection then
					ConstructionPlanner.clearDismantleSelection()
				end

				if key ~= "destroy"
				and ConstructionPlanner.clearDestroySelection then
					ConstructionPlanner.clearDestroySelection()
				end

				if ConstructionPlanner.setMode then
					if key == "quick" then

						ConstructionPlanner.setMode(
							"quick"
						)

					elseif key == "plan"
					or key == "gather" then

						ConstructionPlanner.setMode(
							"plan"
						)

					else

						------------------------------------------------
						-- DESTROY / DISMANTLE / OFF MUST COMPLETELY
						-- DISABLE THE PLAN / QUICK PREVIEW PIPELINE.
						------------------------------------------------

						ConstructionPlanner.setMode(
							"off"
						)
					end
				end

				return true
			end
		end

		self.modeDropdownOpen = false
	end

	if self.modeSelectorButton
	and isPointInsideRect(x, y, self.modeSelectorButton) then
		self.modeDropdownOpen =
			not self.modeDropdownOpen

		return true
	end

	--------------------------------------------------------
	-- PLAN HEIGHT
	--------------------------------------------------------

	if (ConstructionPlanner.projectPanelPage or "plan") == "plan" then

		if self.heightMinusButton
		and isPointInsideRect(x, y, self.heightMinusButton) then

			if ConstructionPlanner.adjustPlanHeightOffset then
				ConstructionPlanner.adjustPlanHeightOffset(-1)
			end

			return true
		end

		if self.heightPlusButton
		and isPointInsideRect(x, y, self.heightPlusButton) then

			if ConstructionPlanner.adjustPlanHeightOffset then
				ConstructionPlanner.adjustPlanHeightOffset(1)
			end

			return true
		end
	end

	--------------------------------------------------------
	-- PLACEMENT / SELECTION MODE
	--------------------------------------------------------

	if self.placementButtonX
	and self.placementButtonY
	and self.placementButtonWidth
	and self.placementButtonHeight
	and x >= self.placementButtonX
	and x <= self.placementButtonX
		+ self.placementButtonWidth
	and y >= self.placementButtonY
	and y <= self.placementButtonY
		+ self.placementButtonHeight then

		if ConstructionPlanner.togglePlacementMode then
			ConstructionPlanner.togglePlacementMode()
		end

		return true
	end

	--------------------------------------------------------
	-- DESTROY PAGE CONTROLS
	--------------------------------------------------------

	if (ConstructionPlanner.projectPanelPage or "plan")
	== "destroy" then

		if self.destroyClearButton
		and isPointInsideRect(
			x,
			y,
			self.destroyClearButton
		) then

			if ConstructionPlanner.clearDestroySelection then
				ConstructionPlanner.clearDestroySelection()
			end

			return true
		end

		if self.confirmDestroyButtonX
		and self.confirmDestroyButtonY
		and self.confirmDestroyButtonWidth
		and self.confirmDestroyButtonHeight
		and x >= self.confirmDestroyButtonX
		and x <= self.confirmDestroyButtonX
			+ self.confirmDestroyButtonWidth
		and y >= self.confirmDestroyButtonY
		and y <= self.confirmDestroyButtonY
			+ self.confirmDestroyButtonHeight then

			local selectedCount =
				ConstructionPlanner.getDestroySelectionCount
				and ConstructionPlanner.getDestroySelectionCount()
				or 0

			if selectedCount > 0
			and ConstructionPlanner.canConfirmDestruction
			and ConstructionPlanner.canConfirmDestruction()
			and ConstructionPlanner.confirmDestruction then

				ConstructionPlanner.confirmDestruction()
			end

			return true
		end
	end


	--------------------------------------------------------
	-- DISMANTLE PAGE CONTROLS
	--------------------------------------------------------

	if (ConstructionPlanner.projectPanelPage or "plan")
	== "dismantle" then

		if self.dismantleClearButton
		and isPointInsideRect(
			x,
			y,
			self.dismantleClearButton
		) then

			if ConstructionPlanner.clearDismantleSelection then
				ConstructionPlanner.clearDismantleSelection()
			end

			return true
		end

		if self.confirmDismantleButtonX
		and self.confirmDismantleButtonY
		and self.confirmDismantleButtonWidth
		and self.confirmDismantleButtonHeight
		and x >= self.confirmDismantleButtonX
		and x <= self.confirmDismantleButtonX
			+ self.confirmDismantleButtonWidth
		and y >= self.confirmDismantleButtonY
		and y <= self.confirmDismantleButtonY
			+ self.confirmDismantleButtonHeight then

			local selectedCount =
				ConstructionPlanner.getDismantleSelectionCount
				and ConstructionPlanner.getDismantleSelectionCount()
				or 0

			if selectedCount > 0
			and ConstructionPlanner.canConfirmDismantling
			and ConstructionPlanner.canConfirmDismantling()
			and ConstructionPlanner.confirmDismantling then

				ConstructionPlanner.confirmDismantling()
			end

			return true
		end
	end

	-- Gather Area controls.
	if (ConstructionPlanner.projectPanelPage or "plan") == "gather" then
		local function insideButton(rect)
			return rect
				and x >= rect.x
				and x <= rect.x + rect.w
				and y >= rect.y
				and y <= rect.y + rect.h
		end

		if insideButton(self.gatherSetButton) then
			if ConstructionPlanner.startGatherAreaSelection then
				ConstructionPlanner.startGatherAreaSelection()
			end
			return true
		end

		if insideButton(self.gatherRemoveAllButton) then
			if ConstructionPlanner.clearGatherAreas then
				ConstructionPlanner.clearGatherAreas()
			end
			return true
		end

		if insideButton(self.gatherHighlightButton) then
			if ConstructionPlanner.toggleGatherAreaHighlight then
				ConstructionPlanner.toggleGatherAreaHighlight()
			end
			return true
		end
	end

	-- Close button.
	if self.closeButtonX and self.closeButtonY and self.closeButtonSize
	and x >= self.closeButtonX and x <= self.closeButtonX + self.closeButtonSize
	and y >= self.closeButtonY and y <= self.closeButtonY + self.closeButtonSize then
		self:setVisible(false)
		ConstructionPlanner.projectPanelVisible = false
		return true
	end
	
	--------------------------------------------------------
	-- CONFIRM REMOVAL
	--------------------------------------------------------

	if self.confirmRemovalButtonX
	and self.confirmRemovalButtonY
	and self.confirmRemovalButtonWidth
	and self.confirmRemovalButtonHeight
	and x >= self.confirmRemovalButtonX
	and x <= self.confirmRemovalButtonX
		+ self.confirmRemovalButtonWidth
	and y >= self.confirmRemovalButtonY
	and y <= self.confirmRemovalButtonY
		+ self.confirmRemovalButtonHeight then

		if ConstructionPlanner.confirmRemoveSelection then

			ConstructionPlanner.confirmRemoveSelection()

		else

			cpDebug(
				"[ConstructionPlanner] Confirm Removal unavailable"
			)
		end

		return true
	end

	--------------------------------------------------------
	-- REMOVE ALL PROJECT PREVIEWS
	--------------------------------------------------------

	if self.removeAllPreviewsButtonX
	and self.removeAllPreviewsButtonY
	and self.removeAllPreviewsButtonWidth
	and self.removeAllPreviewsButtonHeight
	and x >= self.removeAllPreviewsButtonX
	and x <= self.removeAllPreviewsButtonX
		+ self.removeAllPreviewsButtonWidth
	and y >= self.removeAllPreviewsButtonY
	and y <= self.removeAllPreviewsButtonY
		+ self.removeAllPreviewsButtonHeight then

		if ConstructionPlanner.removeAllProjectPreviews then

			ConstructionPlanner.removeAllProjectPreviews()

		else

			cpDebug(
				"[ConstructionPlanner] Remove All Previews unavailable"
			)
		end

		return true
	end

	-- Context-aware Remove button.
	if self.removeButtonX and self.removeButtonY and self.removeButtonWidth and self.removeButtonHeight
	and x >= self.removeButtonX and x <= self.removeButtonX + self.removeButtonWidth
	and y >= self.removeButtonY and y <= self.removeButtonY + self.removeButtonHeight then
		local page = ConstructionPlanner.projectPanelPage or "plan"

		if page == "gather" then
			ConstructionPlanner.previewRemovalMode = false
			ConstructionPlanner.gatherRemovalMode =
				not (ConstructionPlanner.gatherRemovalMode == true)

			cpDebug(
				"[ConstructionPlanner] Gather Area removal mode: "
				.. tostring(ConstructionPlanner.gatherRemovalMode)
			)
			return true
		end

		ConstructionPlanner.gatherRemovalMode = false

		if ConstructionPlanner.previewRemovalMode then

			ConstructionPlanner.previewRemovalMode =
				false

			if ConstructionPlanner.clearRemoveSelection then

				ConstructionPlanner.clearRemoveSelection()
			end

			cpDebug(
				"[ConstructionPlanner] Preview removal mode: false"
			)

			return true
		end

		local project = ConstructionPlanner.pendingProject
		if not project then
			cpDebug("[ConstructionPlanner] No project previews to remove")
			return true
		end
		if project.status and project.status ~= "planning" then
			cpDebug("[ConstructionPlanner] Preview removal unavailable while project is active")
			return true
		end
		if ConstructionPlanner.clearRemoveSelection then

			ConstructionPlanner.clearRemoveSelection()
		end
		ConstructionPlanner.previewRemovalMode = true
		cpDebug("[ConstructionPlanner] Preview removal mode: true")
		return true
	end

	-- Existing Build Project behavior, Plan/Gather pages only.
	local activePage =
		ConstructionPlanner.projectPanelPage
		or "plan"

	if (activePage == "plan" or activePage == "gather")
	and ConstructionPlanner.pendingProject and self.buildButtonX and self.buildButtonY
	and x >= self.buildButtonX and x <= self.buildButtonX + self.buildButtonWidth
	and y >= self.buildButtonY and y <= self.buildButtonY + self.buildButtonHeight then
		ConstructionPlanner.previewRemovalMode = false
		ConstructionPlanner.gatherRemovalMode = false
		if ConstructionPlanner.startDistributionPickup then
			cpDebug("[ConstructionPlanner] Build Project pressed - starting distribution")
			ConstructionPlanner.startDistributionPickup()
		else
		end
		return true
	end

	-- Resize handle.
	local resizeSize = 18
	if x >= self.width - resizeSize and y >= self.height - resizeSize then
		self.resizing = true
		self.resizeStartMouseX = getMouseX()
		self.resizeStartMouseY = getMouseY()
		self.resizeStartWidth = self.width
		self.resizeStartHeight = self.height
		return true
	end

	return ISPanel.onMouseDown(self, x, y)
end

------------------------------------------------------------
-- MOUSE UP
------------------------------------------------------------

function DragBuilderProjectPanel:onMouseUp(x, y)
	self.resizing = false

	return ISPanel.onMouseUp(self, x, y)
end

function DragBuilderProjectPanel:onMouseUpOutside(x, y)
	self.resizing = false

	return ISPanel.onMouseUpOutside(self, x, y)
end

------------------------------------------------------------
-- RESIZE UPDATE
------------------------------------------------------------

function DragBuilderProjectPanel:update()
	ISPanel.update(self)

	if not self.resizing then
		return
	end

	local mouseX =
		getMouseX()

	local mouseY =
		getMouseY()

	local differenceY =
		mouseY
			- self.resizeStartMouseY

	local newHeight =
		self.resizeStartHeight
			+ differenceY

	if newHeight < self.minimumHeight then
		newHeight =
			self.minimumHeight
	end

	-- Width is intentionally locked. Only height is user-resizable.
	self:setWidth(self.fixedWidth or 529)
	self:setHeight(newHeight)

	self:clampScroll()
end

------------------------------------------------------------
-- CREATE PANEL
------------------------------------------------------------

local function createPanel()
	if ConstructionPlanner.projectPanel then
		return ConstructionPlanner.projectPanel
	end

	local panel =
		DragBuilderProjectPanel:new(
			50,
			150,
			529,
			600
		)

	panel:initialise()
	panel:addToUIManager()

	panel:setVisible(false)

	ConstructionPlanner.projectPanel =
		panel

	ConstructionPlanner.projectPanelVisible =
		false

	cpDebug(
		"[ConstructionPlanner] Project panel created"
	)

	return panel
end

------------------------------------------------------------
-- SHOW PANEL
------------------------------------------------------------

function ConstructionPlanner.showProjectPanel()
	local panel =
		createPanel()

	if ConstructionPlanner.calculateProjectMaterials then
		ConstructionPlanner.calculateProjectMaterials()
	end

	panel:setVisible(true)

	ConstructionPlanner.projectPanelVisible =
		true

	cpDebug(
		"[ConstructionPlanner] Project panel shown"
	)
end

------------------------------------------------------------
-- HIDE PANEL
------------------------------------------------------------

function ConstructionPlanner.hideProjectPanel()
	local panel =
		ConstructionPlanner.projectPanel

	if not panel then
		return
	end

	panel:setVisible(false)

	ConstructionPlanner.projectPanelVisible =
		false

	cpDebug(
		"[ConstructionPlanner] Project panel hidden"
	)
end

------------------------------------------------------------
-- TOGGLE PANEL
------------------------------------------------------------

local function togglePanel()
	if ConstructionPlanner.projectPanelVisible then

		ConstructionPlanner.hideProjectPanel()

	else

		ConstructionPlanner.showProjectPanel()
	end
end

local function onKeyPressed(
	key
)
	local configuredKey =
		getCore():getKey(
			"Toggle Construction Planner"
		)

	if key ~= configuredKey then
		return
	end

	togglePanel()
end

------------------------------------------------------------
-- AUTO RECALCULATE
------------------------------------------------------------

local lastSegmentCount = -1

local function updateProjectMaterials()
	local project =
		ConstructionPlanner.pendingProject

	if not project
	or not project.segments then

		lastSegmentCount = -1

		return
	end

	local count =
		#project.segments

	if count ~= lastSegmentCount then

		lastSegmentCount =
			count

		if ConstructionPlanner.calculateProjectMaterials then
			ConstructionPlanner.calculateProjectMaterials()
		end
	end
end

------------------------------------------------------------
-- SYNC DRAGBUILDER WITH VANILLA BUILD MENU HOTKEY
------------------------------------------------------------

local function onBuildingUIKeyPressed(
	key
)
	local openMode =
		SandboxVars
		and SandboxVars.ConstructionPlanner
		and SandboxVars.ConstructionPlanner.PanelOpenMode
		or 1

	--------------------------------------------------------
	-- HOTKEY ONLY MODE
	--------------------------------------------------------

	if openMode ~= 1 then
		return
	end

	--------------------------------------------------------
	-- FOLLOW WHATEVER KEY VANILLA CURRENTLY USES FOR
	-- "BUILDING UI".
	--------------------------------------------------------

	if not getCore():isKey(
		"Building UI",
		key
	) then

		return
	end

	--------------------------------------------------------
	-- FOR NOW:
	-- BUILD MENU HOTKEY ONLY ENSURES DRAGBUILDER IS OPEN.
	--
	-- WE ARE NOT TRYING TO MIRROR THE BUILD MENU'S CLOSE
	-- STATE UNTIL WE COME BACK TO THAT POLISH ISSUE.
	--------------------------------------------------------

	if not ConstructionPlanner.projectPanelVisible
	and ConstructionPlanner.showProjectPanel then

		ConstructionPlanner.showProjectPanel()
	end
end

------------------------------------------------------------
-- EVENTS
------------------------------------------------------------

Events.OnKeyPressed.Add(
	onKeyPressed
)

Events.OnKeyPressed.Add(
	onBuildingUIKeyPressed
)

Events.OnTick.Add(
	updateProjectMaterials
)