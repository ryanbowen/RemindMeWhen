local _, ns = ...
local Anchors, Layout, Tree = ns.Anchors, ns.Layout, ns.Tree

-- Dragging reminders and groups in edit mode. A dragged frame snaps to lines of its target, of
-- other reminders and groups and of a grid, as set in db.display.snap. Shift turns snapping off.
local Drag = {}
ns.Drag = Drag

local SNAP_DISTANCE = 8
local GRID_LINE_SPACING = 8

-- Frame that moves when this node's frame is dragged: anything a dynamic group lays out moves that
-- group (and the dynamic groups that lay it out in turn).
local function moverFor(id)
	local Display = ns.Display
	local parent = Tree:ParentNode(id)
	while parent and parent.layout == "dynamic" do
		id = parent.id
		parent = Tree:ParentNode(id)
	end
	if Tree:IsGroup(Tree:Get(id)) then return id, Display.groups[id] end
	return id, Display.items[id]
end

local function push(list, ...)
	for i = 1, select("#", ...) do list[#list + 1] = select(i, ...) end
end

-- Left, center and right (and bottom, center and top) of a rect, converted by k.
local function addRect(xs, ys, left, bottom, right, top, k)
	push(xs, left * k, (left + right) / 2 * k, right * k)
	push(ys, bottom * k, (bottom + top) / 2 * k, top * k)
end

local function addFrame(xs, ys, frame, scale)
	local left, bottom, width, height = frame:GetRect()
	if left then addRect(xs, ys, left, bottom, left + width, bottom + height, frame:GetEffectiveScale() / scale) end
end

-- The rect around the shown frames of a static group's contents other than id, plus its handle,
-- in units of the given scale.
local function staticEdges(xs, ys, parent, id, scale)
	local Display = ns.Display
	local handle = Display.groups[parent.id]
	local frames = { handle }
	for _, childID in ipairs(parent.children) do
		local child = Tree:Get(childID)
		local frame = child and childID ~= id and (Tree:IsGroup(child) and Display.groups[childID] or Display.items[childID])
		if frame and frame:IsShown() then frames[#frames + 1] = frame end
	end
	local left, bottom, right, top
	for _, frame in ipairs(frames) do
		local l, b, w, h = frame:GetRect()
		if l then
			local k = frame:GetEffectiveScale() / scale
			l, b, w, h = l * k, b * k, w * k, h * k
			left, bottom = math.min(left or l, l), math.min(bottom or b, b)
			right, top = math.max(right or l + w, l + w), math.max(top or b + h, b + h)
		end
	end
	if left then addRect(xs, ys, left, bottom, right, top, 1) end
end

-- Lines on each axis that a frame dragged for node id snaps to, in units of its scale.
function Drag.Lines(id, scale)
	local Display, snap = ns.Display, ns.db.display.snap
	local xs, ys = {}, {}
	local parent = Tree:ParentNode(id)
	if snap.edges then
		if parent then
			staticEdges(xs, ys, parent, id, scale)
		else
			addFrame(xs, ys, Display:AnchorTarget(Tree:Get(id)), scale)
		end
	end
	if snap.others then
		for _, pool in ipairs({ Display.items, Display.groups }) do
			for nodeID, frame in pairs(pool) do
				if frame:IsShown() and not (parent and nodeID == parent.id) and not Anchors.MovesWith(nodeID, id) then
					addFrame(xs, ys, frame, scale)
				end
			end
		end
	end
	return xs, ys
end

-- The grid's origin (the screen's center) and spacing in units of the given scale, or nil when off.
local function gridFor(scale)
	local snap = ns.db.display.snap
	if not snap.grid then return nil end
	local left, bottom, width, height = UIParent:GetRect()
	local k = UIParent:GetEffectiveScale() / scale
	return { x = (left + width / 2) * k, y = (bottom + height / 2) * k, step = snap.gridSize * k }
end

local function overlay(strata)
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata(strata)
	frame.lines = {}
	return frame
end

local function guideFrame()
	local guides = Drag.guides
	if guides then return guides end
	guides = overlay("TOOLTIP")
	guides.vertical = guides:CreateTexture(nil, "OVERLAY")
	guides.vertical:SetColorTexture(1, 0.82, 0, 0.9)
	guides.vertical:SetWidth(1)
	guides.horizontal = guides:CreateTexture(nil, "OVERLAY")
	guides.horizontal:SetColorTexture(1, 0.82, 0, 0.9)
	guides.horizontal:SetHeight(1)
	Drag.guides = guides
	return guides
end

-- Shows a guide line at each snapped coordinate (in units of the given scale), hiding the others.
local function showGuides(x, y, scale)
	local guides = guideFrame()
	local k = scale / UIParent:GetEffectiveScale()
	guides.vertical:SetShown(x ~= nil)
	guides.horizontal:SetShown(y ~= nil)
	if x then
		guides.vertical:ClearAllPoints()
		guides.vertical:SetPoint("TOP", UIParent, "TOPLEFT", x * k, 0)
		guides.vertical:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x * k, 0)
	end
	if y then
		guides.horizontal:ClearAllPoints()
		guides.horizontal:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, y * k)
		guides.horizontal:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, y * k)
	end
end

-- Draws the grid from the screen's center, skipping lines that would sit closer than
-- GRID_LINE_SPACING apart.
function Drag.ShowGrid(size)
	local grid = Drag.grid or overlay("BACKGROUND")
	Drag.grid = grid
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	if grid:IsShown() and grid.drawn == size and grid.width == width and grid.height == height then return end
	grid.drawn, grid.width, grid.height = size, width, height
	local spacing = size * math.max(1, math.ceil(GRID_LINE_SPACING / size))
	local count = 0
	local function line(vertical, offset)
		count = count + 1
		local texture = grid.lines[count] or grid:CreateTexture(nil, "ARTWORK")
		grid.lines[count] = texture
		texture:ClearAllPoints()
		texture:SetColorTexture(1, 1, 1, offset == 0 and 0.35 or 0.12)
		if vertical then
			texture:SetWidth(1)
			texture:SetPoint("TOP", grid, "TOP", offset, 0)
			texture:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
		else
			texture:SetHeight(1)
			texture:SetPoint("LEFT", grid, "LEFT", 0, offset)
			texture:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
		end
		texture:Show()
	end
	for _, vertical in ipairs({ true, false }) do
		local half = (vertical and UIParent:GetWidth() or UIParent:GetHeight()) / 2
		for i = 0, math.floor(half / spacing) do
			line(vertical, i * spacing)
			if i > 0 then line(vertical, -i * spacing) end
		end
	end
	for i = count + 1, #grid.lines do grid.lines[i]:Hide() end
	grid:Show()
end

function Drag.HideGrid()
	if Drag.grid then Drag.grid:Hide() end
end

-- Snaps one axis: to the nearest line in reach, otherwise to the grid. Returns the shift and the
-- line to show a guide on (nil for the grid).
local function snapAxis(edges, lines, threshold, origin, step)
	local shift, line = Layout.Snap(edges, lines, threshold)
	if line or not step then return shift, line end
	return (Layout.SnapGrid(edges, origin, step)), nil
end

-- Follows the cursor and snaps unless Shift is held.
function Drag:Update()
	local drag = ns.Display.dragging
	if not drag then return end
	local frame = drag.frame
	local scale = frame:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local left, bottom = cx / scale + drag.dx, cy / scale + drag.dy
	local guideX, guideY
	if not (IsShiftKeyDown and IsShiftKeyDown()) then
		local width, height = frame:GetWidth(), frame:GetHeight()
		local threshold = SNAP_DISTANCE * UIParent:GetEffectiveScale() / scale
		local grid = drag.grid or {}
		local shiftX, shiftY
		shiftX, guideX = snapAxis({ left, left + width / 2, left + width }, drag.xs, threshold, grid.x, grid.step)
		shiftY, guideY = snapAxis({ bottom, bottom + height / 2, bottom + height }, drag.ys, threshold, grid.y, grid.step)
		left, bottom = left + shiftX, bottom + shiftY
	end
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
	showGuides(guideX, guideY, scale)
end

local driver

local function startDrag(frame)
	local Display = ns.Display
	if not (frame.nodeID and Display:IsEditMode()) then return end
	local id, mover = moverFor(frame.nodeID)
	local node = Tree:Get(id)
	if not (mover and node) or Display.FollowsMouse(node) then return end
	local left, bottom = mover:GetRect()
	if not left then return end
	local scale = mover:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local xs, ys = Drag.Lines(id, scale)
	Display.dragging = {
		id = id, frame = mover, xs = xs, ys = ys, grid = gridFor(scale),
		dx = left - cx / scale, dy = bottom - cy / scale,
	}
	ns.PositionPanel:Request()
	driver = driver or CreateFrame("Frame")
	driver:SetScript("OnUpdate", function() Drag:Update() end)
end

local function stopDrag()
	local Display = ns.Display
	local drag = Display.dragging
	if not drag then return end
	Display.dragging = nil
	driver:SetScript("OnUpdate", nil)
	showGuides(nil, nil, 1)
	Display:SavePosition(drag.id, drag.frame)
end

function Drag.Attach(frame)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", startDrag)
	frame:SetScript("OnDragStop", stopDrag)
end
