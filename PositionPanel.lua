local _, ns = ...
local L, W = ns.L, ns.Widgets

-- What dragging snaps to and the grid size. It shows in move mode, and in edit mode once something is dragged.
-- Closing it ends move mode.
local PositionPanel = {}
ns.PositionPanel = PositionPanel

local WIDTH, HEIGHT = 280, 180
local DEFAULT_Y = -120

local function savePosition(frame)
	local left, bottom, width, height = frame:GetRect()
	local pLeft, pBottom, pWidth, pHeight = UIParent:GetRect()
	if not (left and pLeft) then return end
	ns.db.display.panel = {
		x = math.floor(left + width / 2 - (pLeft + pWidth / 2) + 0.5),
		y = math.floor(bottom + height - (pBottom + pHeight) + 0.5),
	}
end

local function place(frame)
	local saved = ns.db.display.panel
	frame:ClearAllPoints()
	frame:SetPoint("TOP", UIParent, "TOP", saved and saved.x or 0, saved and saved.y or DEFAULT_Y)
end

function PositionPanel:Create()
	if self.frame then return self.frame end
	local frame = W.Panel(UIParent, "RemindMeWhenPositions")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		savePosition(f)
	end)
	frame:SetScript("OnHide", function()
		if self.refreshing then return end
		self.requested = nil
		ns.Drag.HideGrid()
		ns.Display:StopMoving(true)
	end)
	tinsert(UISpecialFrames, "RemindMeWhenPositions")
	self.frame = frame

	local title = W.Label(frame, L["RemindMeWhen positions"], "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() frame:Hide() end)

	local function setSnap(key)
		return function(checked)
			ns.db.display.snap[key] = checked
			self:Refresh(true)
		end
	end
	self.checks = {}
	local rows = {
		{ "grid", L["Snap to grid"] },
		{ "edges", L["Snap to screen and anchor"] },
		{ "others", L["Snap to other reminders and groups"] },
	}
	for i, info in ipairs(rows) do
		local check = W.Check(frame, info[2], setSnap(info[1]))
		check:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 26)
		self.checks[info[1]] = check
	end

	self.sizeLabel = W.Label(frame, L["Size"], "GameFontNormalSmall")
	self.sizeLabel:SetPoint("LEFT", self.checks.grid.label, "RIGHT", 14, 0)
	self.sizeBox = W.EditBox(frame, 36, function(text)
		local Core = ns.Core
		local size = math.floor(tonumber(text) or ns.db.display.snap.gridSize)
		ns.db.display.snap.gridSize = math.max(Core.GRID_MIN, math.min(Core.GRID_MAX, size))
		self:Refresh(true)
	end)
	self.sizeBox:SetPoint("LEFT", self.sizeLabel, "RIGHT", 8, 0)
	W.Tooltip(self.sizeBox, L["Grid size"], string.format(L["Pixels between grid lines, from %d to %d."], ns.Core.GRID_MIN, ns.Core.GRID_MAX))

	local help = W.Label(frame, L["Hold Shift while dragging to place freely."], "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", 14, -114)
	local configure = W.Label(frame, L["Right-click a reminder or group to configure it."], "GameFontDisableSmall")
	configure:SetPoint("TOPLEFT", 14, -130)
	self.done = W.Button(frame, L["Done"], 90, function()
		if ns.Display.moving then ns.Display:StopMoving(true) else ns.Display:SetLocked(true) end
	end)
	self.done:SetPoint("BOTTOMRIGHT", -10, 10)
	place(frame)
	self.refreshing = true
	frame:Hide()
	self.refreshing = nil
	return frame
end

-- Shows it when something starts being dragged.
function PositionPanel:Request()
	self.requested = true
	self:Refresh(true)
end

-- Shows the panel (and the grid when grid snapping is on) in move mode, or in edit mode once something
-- has been dragged, and hides both otherwise.
function PositionPanel:Refresh(edit)
	if not edit then self.requested = nil end
	local show = edit and (ns.Display.moving or self.requested)
	local snap = ns.db.display.snap
	if show and snap.grid then ns.Drag.ShowGrid(snap.gridSize) else ns.Drag.HideGrid() end
	if not show then
		if self.frame and self.frame:IsShown() then
			self.refreshing = true
			self.frame:Hide()
			self.refreshing = nil
		end
		return
	end
	local frame = self:Create()
	for key, check in pairs(self.checks) do check:SetChecked(snap[key]) end
	self.sizeBox:SetValue(snap.gridSize)
	self.sizeBox:SetEnabled(snap.grid)
	self.done:SetText(ns.Display.moving and L["Done"] or L["Lock"])
	frame:Show()
end
