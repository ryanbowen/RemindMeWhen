local _, ns = ...
local W, Conditions, L = ns.Widgets, ns.Conditions, ns.L
local Options = ns.Options

local ROW_H = 30
local PARAMS_X = 292
local INDENT = 16
-- Row width used until the scroll frame reports its size.
local CHILD_W = 730

local NEGATE_CHOICES = { { value = false, label = L["IF"] }, { value = true, label = L["IF NOT"] } }
local MATCH_CHOICES = { { value = "ALL", label = L["All conditions"] }, { value = "ANY", label = L["Any condition"] } }
local GROUP_MATCH_CHOICES = { { value = "ALL", label = L["All of these"] }, { value = "ANY", label = L["Any of these"] } }

Options.condRows = {}

local function newCondition()
	return Conditions:Normalize({ type = "combat", negate = false })
end

local function newGroup()
	return Conditions:SetType({ negate = false }, Conditions.GROUP)
end

function Options:CreateConditionsTab(p)
	local label = W.Label(p, L["Show when"], "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", 4, -10)
	self.condMatchLabel = label
	self.matchDropdown = W.Dropdown(p, 130, function(value)
		local r = self:Current()
		if not r then return end
		r.match = value
		self:Changed()
	end)
	self.matchDropdown:SetChoices(MATCH_CHOICES)
	self.matchDropdown:SetPoint("TOPLEFT", 80, -5)

	local addGroup = W.Button(p, L["Add group"], 100, function()
		local r = self:Current()
		if not r then return end
		self:ClearEditFocus()
		r.conditions[#r.conditions + 1] = newGroup()
		self:Changed(true)
	end)
	addGroup:SetPoint("TOPRIGHT", -4, -4)
	W.Tooltip(addGroup, L["Add group"], string.format(L["A group has its own All / Any setting, e.g. 'in combat AND (Pack OR Cheetah)'. Groups can be nested %d levels deep."], Conditions.MAX_DEPTH))

	local add = W.Button(p, L["Add condition"], 120, function()
		local r = self:Current()
		if not r then return end
		self:ClearEditFocus()
		r.conditions[#r.conditions + 1] = newCondition()
		self:Changed(true)
	end)
	add:SetPoint("RIGHT", addGroup, "LEFT", -6, 0)

	local help = W.Label(p, "", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", 4, -32)
	help:SetPoint("RIGHT", p, "RIGHT", -10, 0)
	help:SetWordWrap(true)
	self.condHelp = help

	local box = W.Panel(p)
	box:SetPoint("TOPLEFT", 0, -50)
	box:SetPoint("BOTTOMRIGHT")
	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(CHILD_W, 10)
	scroll:SetScrollChild(child)
	scroll:SetScript("OnSizeChanged", function(_, width)
		if width and width > 0 then child:SetWidth(width) end
	end)
	self.condChild = child
end

function Options:CondRow(i)
	local row = self.condRows[i]
	if row then return row end
	row = CreateFrame("Frame", nil, self.condChild)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	row:SetPoint("RIGHT", self.condChild, "RIGHT")

	row.guide = row:CreateTexture(nil, "BACKGROUND")
	row.guide:SetColorTexture(0.5, 0.5, 0.55, 0.5)
	row.guide:SetWidth(2)
	row.guide:SetPoint("TOP")
	row.guide:SetPoint("BOTTOM")

	row.dotFrame = CreateFrame("Frame", nil, row)
	row.dotFrame:SetSize(14, 14)
	row.dotFrame:EnableMouse(true)
	row.dot = row.dotFrame:CreateTexture(nil, "OVERLAY")
	row.dot:SetSize(8, 8)
	row.dot:SetPoint("CENTER")
	W.Tooltip(row.dotFrame, function()
		if row.result == true then return L["Currently true"] end
		if row.result == false then return L["Currently false"] end
		return L["Currently unknown"]
	end, function()
		local err = row.node and Conditions.errors[row.node]
		if err then return L["Error: "] .. err end
		if row.result == nil then return L["The game is hiding this information right now, so the last known state is used."] end
		return L["Includes the IF / IF NOT setting."]
	end)

	row.negate = W.Dropdown(row, 70, function(value)
		if not row.node then return end
		row.node.negate = value
		self:Changed()
	end)
	row.negate:SetChoices(NEGATE_CHOICES)

	row.type = W.Dropdown(row, 196, function(value)
		if not row.node then return end
		self:ClearEditFocus()
		Conditions:SetType(row.node, value)
		self:Changed(true)
	end)
	row.type:SetChoices(function() return Conditions:TypeMenu(row.level) end)
	row.type:SetSearchable(true)

	row.groupMatch = W.Dropdown(row, 110, function(value)
		if not row.node then return end
		row.node.match = value
		self:Changed()
	end)
	row.groupMatch:SetChoices(GROUP_MATCH_CHOICES)
	row.groupMatch:SetPoint("LEFT", row, "LEFT", PARAMS_X, 0)

	row.addChild = W.Button(row, L["+ Condition"], 96, function()
		if not row.node then return end
		self:ClearEditFocus()
		table.insert(row.node.conditions, newCondition())
		self:Changed(true)
	end)
	row.addChild:SetPoint("LEFT", row.groupMatch, "RIGHT", 6, 0)

	row.addGroup = W.Button(row, L["+ Group"], 76, function()
		if not row.node then return end
		self:ClearEditFocus()
		table.insert(row.node.conditions, newGroup())
		self:Changed(true)
	end)
	row.addGroup:SetPoint("LEFT", row.addChild, "RIGHT", 4, 0)

	row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
	row.remove:SetSize(24, 24)
	row.remove:SetPoint("RIGHT", -2, 0)
	row.remove:SetScript("OnClick", function()
		if not (row.list and row.list[row.index]) then return end
		self:ClearEditFocus()
		table.remove(row.list, row.index)
		self:Changed(true)
	end)
	W.Tooltip(row.remove, L["Remove"], function()
		return row.node and Conditions:IsGroup(row.node) and L["Removes the group and everything in it."] or nil
	end)

	row.field = self:ResolverField(row, 150, function(value)
		local param = row.field.param
		if not (row.node and param) then return end
		row.node[param.key] = value
		self:Changed()
	end)
	row.field.extraChoices = function(filter)
		local node = row.node
		if not node then return nil end
		if node.type == "aura" then return Options.FilterChoices(Options.AuraChoices(node.unit, node.filter), filter) end
		if node.type == "groupBuffMissing" then return Options.FilterChoices(Options.AuraChoices("player", "HELPFUL"), filter) end
		return nil
	end
	W.Tooltip(row.field.box, function() return row.field.param and row.field.param.label end,
		function() return row.field.param and row.field.param.help end)

	row.dropdowns, row.boxes = {}, {}
	self.condRows[i] = row
	return row
end

function Options:ParamDropdown(row, index)
	local dropdown = row.dropdowns[index]
	if dropdown then return dropdown end
	dropdown = W.Dropdown(row, 80, function(value, widget)
		if not (row.node and widget.param) then return end
		row.node[widget.param.key] = value
		self:LayoutParams(row, row.node)
		self:Changed()
	end)
	W.Tooltip(dropdown, function() return dropdown.param and dropdown.param.label end, function() return dropdown.param and dropdown.param.help end)
	row.dropdowns[index] = dropdown
	return dropdown
end

function Options:ParamBox(row, index)
	local box = row.boxes[index]
	if box then return box end
	box = W.EditBox(row, 80, function(text, widget)
		local param = widget.param
		if not (row.node and param) then return end
		if param.kind == "number" then
			row.node[param.key] = tonumber(text) or param.default or 0
			widget:SetValue(row.node[param.key])
		else
			row.node[param.key] = text
		end
		self:Changed()
	end)
	W.Tooltip(box, function() return box.param and box.param.label end, function() return box.param and box.param.help end)
	row.boxes[index] = box
	return box
end

local function visibleParams(def, c)
	local out = {}
	for _, param in ipairs(def and def.params or {}) do
		if not param.shownIf or param.shownIf(c) then out[#out + 1] = param end
	end
	return out
end

function Options:LayoutParams(row, c)
	for _, dropdown in ipairs(row.dropdowns) do dropdown:Hide() end
	for _, box in ipairs(row.boxes) do box:Hide() end
	row.field:SetShown(false)
	row.field.param = nil
	local isGroup = Conditions:IsGroup(c)
	row.groupMatch:SetShown(isGroup)
	row.addChild:SetShown(isGroup)
	row.addGroup:SetShown(isGroup and row.level + 1 < Conditions.MAX_DEPTH)
	if isGroup then
		row.groupMatch:SetValue(c.match)
		return
	end
	local def = Conditions.types[c.type]
	local x, dropdowns, boxes = PARAMS_X, 0, 0
	for _, param in ipairs(visibleParams(def, c)) do
		local width = param.width or 80
		if param.kind == "choice" then
			dropdowns = dropdowns + 1
			local widget = self:ParamDropdown(row, dropdowns)
			widget.param = param
			widget:SetWidth(width)
			widget:SetSearchable(param.searchable)
			widget.showUnknown = param.showUnknown
			widget:SetChoices(param.choices)
			widget:SetValue(c[param.key])
			widget:ClearAllPoints()
			widget:SetPoint("LEFT", row, "LEFT", x, 0)
			widget:Show()
			x = x + width + 4
		elseif param.resolver then
			local field = row.field
			field.param = param
			field:SetResolver(param.resolver)
			field.box:SetWidth(width)
			field.box:SetHint(param.hint or param.label)
			field:SetPoint("LEFT", row, "LEFT", x + 6, 0)
			field:SetShown(true)
			field:SetValue(c[param.key])
			x = x + width + 12 + field.extraWidth
		else
			boxes = boxes + 1
			local widget = self:ParamBox(row, boxes)
			widget.param = param
			widget:SetWidth(width)
			widget:SetHint(param.hint or param.label)
			widget:SetValue(c[param.key])
			widget:ClearAllPoints()
			widget:SetPoint("LEFT", row, "LEFT", x + 6, 0)
			widget:Show()
			x = x + width + 12
		end
	end
end

function Options:RefreshConditions()
	if not self.frame then return end
	local r = self:Current()
	local entries = {}
	if r then
		Conditions:Walk(r.conditions, function(c, list, index, level)
			entries[#entries + 1] = { node = c, list = list, index = index, level = level }
		end)
		self.matchDropdown:SetValue(r.match)
		local group = ns.Tree:IsGroup(r)
		self.condMatchLabel:SetText(group and L["Active when"] or L["Show when"])
		self.condHelp:SetText(group
			and L["Nothing in this group shows while it is inactive. With no conditions it is always active. Dots: green = true, red = false, yellow = hidden by the game right now."]
			or L["Dots: green = true, red = false, yellow = the game hides this right now (e.g. auras in combat) and the last known state is used."])
	end
	for i, entry in ipairs(entries) do
		local row = self:CondRow(i)
		row.node, row.list, row.index, row.level = entry.node, entry.list, entry.index, entry.level
		local indent = entry.level * INDENT
		row.guide:SetShown(entry.level > 0)
		row.guide:ClearAllPoints()
		row.guide:SetPoint("TOPLEFT", indent - 9, 0)
		row.guide:SetPoint("BOTTOMLEFT", indent - 9, 0)
		row.dotFrame:ClearAllPoints()
		row.dotFrame:SetPoint("LEFT", 2 + indent, 0)
		row.negate:ClearAllPoints()
		row.negate:SetPoint("LEFT", 18 + indent, 0)
		row.type:ClearAllPoints()
		row.type:SetPoint("LEFT", 92 + indent, 0)
		row.type:SetWidth(PARAMS_X - 96 - indent)
		row.negate:SetValue(entry.node.negate and true or false)
		row.type:SetValue(entry.node.type)
		if not Conditions:IsGroup(entry.node) and not Conditions.types[entry.node.type] then
			row.type.text:SetText(L["Unknown: "] .. tostring(entry.node.type))
		end
		self:LayoutParams(row, entry.node)
		row:Show()
	end
	for i = #entries + 1, #self.condRows do
		local row = self.condRows[i]
		row.node, row.list = nil, nil
		row:Hide()
	end
	self.condChild:SetHeight(math.max(10, #entries * ROW_H))
	self:RefreshStatus()
end

function Options:RefreshConditionStatus()
	for _, row in ipairs(self.condRows) do
		if row:IsShown() and row.node then
			local value = Conditions:Evaluate(row.node)
			row.result = value
			local color = value == true and Options.COLOR_TRUE or value == false and Options.COLOR_FALSE or Options.COLOR_UNKNOWN
			Options.SetColor(row.dot, color)
		end
	end
end
