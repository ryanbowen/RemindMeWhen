local _, ns = ...
local W, L = ns.Widgets, ns.L
local Options, Tree = ns.Options, ns.Tree

local ROW_H = 22
local INDENT = 14
local BUTTON_ROWS = 5

Options.treeRows = {}

local function nodeLabel(node)
	local name = node.name ~= "" and node.name or L["(unnamed)"]
	if Tree:IsGroup(node) then
		local count = #node.children > 0 and tostring(#node.children) or L["empty"]
		name = name .. " |cff888888(" .. count .. ")|r"
	end
	if node.enabled and not ns.Core:IsOwnEnabledHere(node) then
		local offHere = node.disabledFor and node.disabledFor[ns.Compat.CharKey()]
		return "|cff888888" .. name .. (offHere and L[" (off on this character)"] or L[" (not loaded)"]) .. "|r"
	end
	if not ns.Core:IsEnabledHere(node) then return "|cff888888" .. name .. "|r" end
	return name
end

-- Rows in display order, skipping the contents of collapsed groups.
function Options:VisibleNodes()
	local out = {}
	Tree:Walk(function(node, level)
		out[#out + 1] = { node = node, level = level }
		if Tree:IsGroup(node) and ns.db.collapsed[node.id] then return false end
	end)
	return out
end

-- Where dragID lands when dropped on targetID at fraction of the row's height (0 top, 1 bottom).
-- Returns parentID, index, zone, or nil when not allowed.
function Options:DropTarget(dragID, targetID, fraction)
	local node, target = Tree:Get(dragID), Tree:Get(targetID)
	if not (node and target) or dragID == targetID or Tree:IsAncestor(dragID, targetID) then return nil end
	local zone
	if Tree:IsGroup(target) then
		zone = fraction < 0.25 and "before" or fraction > 0.75 and "after" or "into"
	else
		zone = fraction < 0.5 and "before" or "after"
	end
	local parentID, index
	if zone == "into" then
		parentID = targetID
	else
		parentID = Tree:Parent(targetID)
		index = Tree:IndexOf(targetID) + (zone == "after" and 1 or 0)
	end
	if not Tree:CanPlace(node, parentID) then return nil, nil, zone end
	return parentID, index, zone
end

function Options:Drop(dragID, targetID, fraction)
	local parentID, index = self:DropTarget(dragID, targetID, fraction)
	if parentID == nil then return false end
	if parentID ~= Tree.ROOT then ns.db.collapsed[parentID] = nil end
	return ns.Core:MoveNode(dragID, parentID, index)
end

-- Selects the node, expands the groups above it and scrolls the list so it shows.
function Options:Reveal(id)
	local parentID = Tree:Parent(id)
	while parentID and parentID ~= Tree.ROOT do
		ns.db.collapsed[parentID] = nil
		parentID = Tree:Parent(parentID)
	end
	self:Select(id)
	local visible = self:VisibleNodes()
	for i, entry in ipairs(visible) do
		if entry.node.id == id then
			local scroll = self.listScroll
			local top, height = (i - 1) * ROW_H, scroll:GetHeight()
			local offset = scroll:GetVerticalScroll() or 0
			if top < offset then
				offset = top
			elseif top + ROW_H > offset + height then
				offset = top + ROW_H - height
			end
			scroll:SetVerticalScroll(math.max(0, math.min(offset, #visible * ROW_H - height)))
			return
		end
	end
end

function Options:ToggleCollapsed(id)
	ns.db.collapsed[id] = not ns.db.collapsed[id] or nil
	self:RefreshList()
end

function Options:NewReminder()
	self:ClearEditFocus()
	local r = { kind = "reminder", name = L["New reminder"], conditions = { { type = "combat", negate = true } } }
	local parentID, index = ns.Core:InsertTarget(self.selected, r)
	self:Select(ns.Core:AddReminder(r, parentID, index).id)
end

function Options:NewGroup(layout)
	self:ClearEditFocus()
	local parentID, index = ns.Core:InsertTarget(self.selected, { kind = "group", children = {} })
	self:Select(ns.Core:AddGroup(layout, parentID, index).id)
end

function Options:AddPreset(preset)
	local r = ns.Presets:Build(preset)
	local parentID, index = ns.Core:InsertTarget(self.selected, r)
	self:Select(ns.Core:AddReminder(r, parentID, index).id)
end

function Options:DuplicateSelected(id)
	local copy = ns.Core:DuplicateNode(id or self.selected)
	if copy then self:Select(copy.id) end
end

function Options:CreateList()
	local frame = self.frame
	local listHeight = self.HEIGHT - 40 - BUTTON_ROWS * 26 - 14
	local box = W.Panel(frame)
	box:SetPoint("TOPLEFT", 12, -40)
	box:SetSize(self.LIST_W, listHeight)
	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(self.LIST_W - 36, 10)
	scroll:SetScrollChild(child)
	self.listScroll, self.listChild = scroll, child

	self.dropLine = child:CreateTexture(nil, "OVERLAY")
	self.dropLine:SetHeight(2)
	self.dropLine:Hide()
	self.dropBox = child:CreateTexture(nil, "OVERLAY")
	self.dropBox:Hide()
	child:SetScript("OnUpdate", function() if self.dragID then self:UpdateDropIndicator() end end)

	local half = (self.LIST_W - 4) / 2
	local quarter = (half - 4) / 2
	local top = -40 - listHeight - 6

	local new = W.Button(frame, L["New reminder"], half, function() self:NewReminder() end)
	new:SetPoint("TOPLEFT", 12, top)

	local newGroup
	newGroup = W.Button(frame, L["New group..."], half, function()
		self:ClearEditFocus()
		W.OpenMenu(newGroup, {
			{ value = "dynamic", label = L["Dynamic group (row or grid)"] },
			{ value = "static", label = L["Static group (place freely)"] },
		}, nil, function(layout) self:NewGroup(layout) end)
	end)
	newGroup:SetPoint("LEFT", new, "RIGHT", 4, 0)
	W.Tooltip(newGroup, L["New group"], L["Dynamic groups arrange their contents in a row or grid. Static groups let you place each one yourself."])

	local copy = W.Button(frame, L["Duplicate"], half, function()
		self:ClearEditFocus()
		self:DuplicateSelected()
	end)
	copy:SetPoint("TOPLEFT", new, "BOTTOMLEFT", 0, -4)

	local delete = W.Button(frame, L["Delete"], half, function() self:ConfirmDelete(self.selected) end)
	delete:SetPoint("LEFT", copy, "RIGHT", 4, 0)

	local preset
	preset = W.Button(frame, L["Add preset..."], half, function()
		self:ClearEditFocus()
		local choices = {}
		for i, p in ipairs(ns.Presets.list) do choices[#choices + 1] = { value = i, label = p.name } end
		W.OpenMenu(preset, choices, nil, function(index) self:AddPreset(ns.Presets.list[index]) end)
	end)
	preset:SetPoint("TOPLEFT", copy, "BOTTOMLEFT", 0, -4)

	local up = W.Button(frame, L["Up"], quarter, function()
		self:ClearEditFocus()
		ns.Core:Nudge(self.selected, -1)
		self:Refresh()
	end)
	up:SetPoint("LEFT", preset, "RIGHT", 4, 0)

	local down = W.Button(frame, L["Down"], quarter, function()
		self:ClearEditFocus()
		ns.Core:Nudge(self.selected, 1)
		self:Refresh()
	end)
	down:SetPoint("LEFT", up, "RIGHT", 4, 0)

	local import = W.Button(frame, L["Import..."], half, function() self:ShowImport() end)
	import:SetPoint("TOPLEFT", preset, "BOTTOMLEFT", 0, -4)
	W.Tooltip(import, L["Import"], L["Paste a RemindMeWhen export string. It is added to the selected group, or next to the selected reminder."])

	local export
	export = W.Button(frame, L["Export..."], half, function()
		self:ClearEditFocus()
		W.OpenMenu(export, {
			{ value = "selected", label = L["Selected (with its contents)"], disabled = self.selected == nil },
			{ value = "all", label = L["Everything"] },
		}, nil, function(which)
			self:ShowExport(which == "all" and ns.db.root or { self.selected })
		end)
	end)
	export:SetPoint("LEFT", import, "RIGHT", 4, 0)
	W.Tooltip(export, L["Export"], L["Creates a text string that others can import."])

	local display = W.Button(frame, L["Display settings"], self.LIST_W, function() self:ShowPage("display") end)
	display:SetPoint("TOPLEFT", import, "BOTTOMLEFT", 0, -4)
end

function Options:TreeRow(i)
	local row = self.treeRows[i]
	if row then return row end
	row = CreateFrame("Button", nil, self.listChild)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	row:SetPoint("RIGHT", self.listChild, "RIGHT")
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:RegisterForDrag("LeftButton")
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(0.25, 0.45, 0.8, 0.35)
	row.bg:Hide()
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.expand = CreateFrame("Button", nil, row)
	row.expand:SetSize(14, 14)
	row.expand:SetScript("OnClick", function() self:ToggleCollapsed(row.nodeID) end)

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetSize(20, 20)
	row.check:SetPoint("LEFT", row.expand, "RIGHT", 0, 0)
	row.check:SetScript("OnClick", function(check)
		local node = Tree:Get(row.nodeID)
		if not node then return end
		node.enabled = check:GetChecked() and true or false
		if row.nodeID == self.selected then self:RefreshEditor() end
		self:Changed()
	end)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
	row.dot = row:CreateTexture(nil, "OVERLAY")
	row.dot:SetSize(8, 8)
	row.dot:SetPoint("RIGHT", -4, 0)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.text:SetPoint("RIGHT", row.dot, "LEFT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)

	row:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			self:OpenNodeMenu(row)
		else
			self:Select(row.nodeID)
		end
	end)
	row:SetScript("OnDoubleClick", function()
		if Tree:IsGroup(Tree:Get(row.nodeID)) then self:ToggleCollapsed(row.nodeID) end
	end)
	row:SetScript("OnDragStart", function() self:BeginDrag(row.nodeID) end)
	row:SetScript("OnDragStop", function() self:EndDrag() end)
	self.treeRows[i] = row
	return row
end

function Options:RefreshList()
	if not self.frame then return end
	local visible = self:VisibleNodes()
	for i, entry in ipairs(visible) do
		local row, node = self:TreeRow(i), entry.node
		row.nodeID = node.id
		row.expand:ClearAllPoints()
		row.expand:SetPoint("LEFT", entry.level * INDENT, 0)
		local group = Tree:IsGroup(node) and #node.children > 0
		row.expand:SetShown(group)
		if group then
			local state = ns.db.collapsed[node.id] and "Plus" or "Minus"
			row.expand:SetNormalTexture("Interface\\Buttons\\UI-" .. state .. "Button-Up")
			row.expand:SetPushedTexture("Interface\\Buttons\\UI-" .. state .. "Button-Down")
			row.expand:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
		end
		row.check:SetChecked(node.enabled)
		row.icon:SetTexture(ns.Display:GetIcon(node))
		row.text:SetText(nodeLabel(node))
		row.bg:SetShown(node.id == self.selected and self.page == "node")
		row:Show()
	end
	for i = #visible + 1, #self.treeRows do self.treeRows[i]:Hide() end
	self.listChild:SetHeight(math.max(10, #visible * ROW_H))
	self:RefreshStatus()
end

function Options:RefreshTreeStatus()
	for _, row in ipairs(self.treeRows) do
		local node = row:IsShown() and Tree:Get(row.nodeID)
		if node then Options.SetColor(row.dot, Options.StatusColor(node)) end
	end
end

local MOVE_PREFIX = "move:"

-- Move to choices: the top level and every group by depth, disabled where the node cannot go.
local function moveChoices(node)
	local current = Tree:Parent(node.id)
	local out = { { value = MOVE_PREFIX .. Tree.ROOT, label = L["Top level"], disabled = current == Tree.ROOT } }
	Tree:Walk(function(group, level)
		if not Tree:IsGroup(group) then return end
		out[#out + 1] = {
			value = MOVE_PREFIX .. group.id,
			label = string.rep("   ", level + 1) .. group.name,
			disabled = group.id == current or not Tree:CanPlace(node, group.id),
		}
	end)
	return out
end

function Options:MoveToGroup(id, parentID)
	if not ns.Core:MoveNode(id, parentID) then return end
	if parentID ~= Tree.ROOT then ns.db.collapsed[parentID] = nil end
	self.selected = id
	self:Refresh()
end

function Options:OpenNodeMenu(row)
	local node = Tree:Get(row.nodeID)
	if not node then return end
	self:ClearEditFocus()
	local choices = {
		{ value = "move", label = L["Move to"], children = moveChoices(node) },
		{ value = "duplicate", label = L["Duplicate"] },
		{ value = "export", label = L["Export"] },
		{ value = "test", label = L["Test"] },
	}
	if Tree:IsGroup(node) then
		local other = node.layout == "dynamic" and "static" or "dynamic"
		choices[#choices + 1] = {
			value = "layout",
			label = other == "static" and L["Change to static group"] or L["Change to dynamic group"],
		}
		choices[#choices + 1] = { value = "collapse", label = ns.db.collapsed[node.id] and L["Expand"] or L["Collapse"] }
	end
	choices[#choices + 1] = { value = "delete", label = L["Delete"] }
	W.OpenMenu(row, choices, nil, function(action)
		local target = tonumber(action:match("^" .. MOVE_PREFIX .. "(%d+)$"))
		if target then
			self:MoveToGroup(node.id, target)
		elseif action == "duplicate" then
			self:DuplicateSelected(node.id)
		elseif action == "export" then
			self:ShowExport({ node.id })
		elseif action == "test" then
			ns.Core:Test(node)
		elseif action == "layout" then
			ns.Core:SetLayout(node, node.layout == "dynamic" and "static" or "dynamic")
			self:Refresh()
		elseif action == "collapse" then
			self:ToggleCollapsed(node.id)
		elseif action == "delete" then
			self:ConfirmDelete(node.id)
		end
	end)
end

function Options:BeginDrag(id)
	self:ClearEditFocus()
	W.CloseMenu()
	self.dragID = id
end

-- The row under the cursor and how far down it the cursor is (0 top, 1 bottom).
function Options:HoveredRow()
	local _, y = GetCursorPosition()
	for _, row in ipairs(self.treeRows) do
		if row:IsShown() and row:IsMouseOver() then
			local top, bottom = row:GetTop(), row:GetBottom()
			local cursor = y / row:GetEffectiveScale()
			return row, math.max(0, math.min(1, (top - cursor) / math.max(1, top - bottom)))
		end
	end
	return nil
end

function Options:UpdateDropIndicator()
	local row, fraction = self:HoveredRow()
	self.dropLine:Hide()
	self.dropBox:Hide()
	if not row then return end
	local parentID, _, zone = self:DropTarget(self.dragID, row.nodeID, fraction)
	if not zone then return end
	local r, g, b = 0.2, 0.9, 0.3
	if parentID == nil then r, g, b = 0.9, 0.2, 0.2 end
	if zone == "into" then
		self.dropBox:ClearAllPoints()
		self.dropBox:SetAllPoints(row)
		self.dropBox:SetColorTexture(r, g, b, 0.25)
		self.dropBox:Show()
	else
		self.dropLine:ClearAllPoints()
		local point = zone == "before" and "TOP" or "BOTTOM"
		self.dropLine:SetPoint(point .. "LEFT", row, point .. "LEFT", 0, 0)
		self.dropLine:SetPoint(point .. "RIGHT", row, point .. "RIGHT", 0, 0)
		self.dropLine:SetColorTexture(r, g, b, 1)
		self.dropLine:Show()
	end
end

function Options:EndDrag()
	local id = self.dragID
	self.dragID = nil
	self.dropLine:Hide()
	self.dropBox:Hide()
	local row, fraction = self:HoveredRow()
	if id and row and self:Drop(id, row.nodeID, fraction) then
		self.selected = id
		self:Refresh()
	end
end
