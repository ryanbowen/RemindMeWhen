local _, ns = ...
local W, L = ns.Widgets, ns.L
local Options, Tree = ns.Options, ns.Tree

local ROW_H = 28
local CONTROL_X = 200

local TEXT_POS_CHOICES = {
	{ value = "RIGHT", label = L["Right of the icon"] },
	{ value = "LEFT", label = L["Left of the icon"] },
	{ value = "TOP", label = L["Above the icon"] },
	{ value = "BOTTOM", label = L["Below the icon"] },
	{ value = "CENTER", label = L["On the icon"] },
}
local GROW_CHOICES = {
	{ value = "DOWN", label = L["Down"] },
	{ value = "UP", label = L["Up"] },
	{ value = "RIGHT", label = L["Right"] },
	{ value = "LEFT", label = L["Left"] },
	{ value = "VCENTER", label = L["Centered, vertical"] },
	{ value = "HCENTER", label = L["Centered, horizontal"] },
}
local ALIGN_CHOICES = {
	{ value = "LEFT", label = L["Left"] },
	{ value = "CENTER", label = L["Center"] },
	{ value = "RIGHT", label = L["Right"] },
}
local SORT_CHOICES = {
	{ value = "order", label = L["List order"] },
	{ value = "timeLeft", label = L["Time left (soonest first)"] },
	{ value = "name", label = L["Name"] },
}
local STYLE_CHOICES = {
	{ value = "icon", label = L["Icon"] },
	{ value = "bar", label = L["Bar"] },
}
local ICON_SIDE_CHOICES = {
	{ value = "LEFT", label = L["Left"] },
	{ value = "RIGHT", label = L["Right"] },
	{ value = "NONE", label = L["No icon"] },
}
local PROGRESS_CHOICES = {
	{ value = "auto", label = L["Automatic"] },
	{ value = "time", label = L["Time left"] },
	{ value = "value", label = L["Count or percent"] },
	{ value = "full", label = L["Always full"] },
}
local BAR_TEXTURE_CHOICES = {}
for _, texture in ipairs(ns.Data.BAR_TEXTURES) do
	BAR_TEXTURE_CHOICES[#BAR_TEXTURE_CHOICES + 1] = { value = texture.key, label = texture.label }
end

-- style: only shown for that style. column 2 holds the bar settings.
local VISUAL_ROWS = {
	{ key = "style", label = L["Style"], kind = "choice", choices = STYLE_CHOICES },
	{ key = "iconSize", label = L["Icon size"], kind = "number", min = 12, max = 128, style = "icon" },
	{ key = "showText", label = L["Show text"], kind = "bool" },
	{ key = "fontSize", label = L["Text size"], kind = "number", min = 6, max = 48 },
	{ key = "textPos", label = L["Text position"], kind = "choice", choices = TEXT_POS_CHOICES, style = "icon" },
	{ key = "textColor", label = L["Text color"], kind = "color" },
	{ key = "glow", label = L["Glow"], kind = "bool" },
	{ key = "timer", label = L["Show time left"], kind = "bool" },
	{ key = "sweep", label = L["Cooldown sweep on the icon"], kind = "bool", style = "icon" },
	{ key = "barWidth", label = L["Bar width"], kind = "number", min = 20, max = 800, style = "bar", column = 2 },
	{ key = "barHeight", label = L["Bar height"], kind = "number", min = 6, max = 128, style = "bar", column = 2 },
	{ key = "barTexture", label = L["Bar texture"], kind = "choice", choices = BAR_TEXTURE_CHOICES, style = "bar", column = 2 },
	{ key = "barColor", label = L["Bar color"], kind = "color", style = "bar", column = 2 },
	{ key = "barBackground", label = L["Bar background"], kind = "color", style = "bar", column = 2 },
	{ key = "iconSide", label = L["Icon on the bar"], kind = "choice", choices = ICON_SIDE_CHOICES, style = "bar", column = 2 },
	{ key = "barReverse", label = L["Reverse fill"], kind = "bool", style = "bar", column = 2 },
}
Options.VISUAL_ROW_COUNT = 9
Options.VISUAL_COLUMN_W = 390

local function copyValue(value)
	if type(value) == "table" then return { value[1], value[2], value[3] } end
	return value
end

local function pickColor(color, onChange)
	local r, g, b = color[1], color[2], color[3]
	local function current()
		local nr, ng, nb = ColorPickerFrame:GetColorRGB()
		return { nr, ng, nb }
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b,
			swatchFunc = function() onChange(current()) end,
			cancelFunc = function() onChange({ r, g, b }) end,
		})
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.func = function() onChange(current()) end
		ColorPickerFrame.cancelFunc = function() onChange({ r, g, b }) end
		ColorPickerFrame:SetColorRGB(r, g, b)
		ColorPickerFrame:Hide()
		ColorPickerFrame:Show()
	end
end

local function fieldLabel(parent, text, x, y)
	local label = W.Label(parent, text, "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", x, y)
	return label
end

-- Rows for the visual settings of db.display.visual (with global) or of the selected node, where each
-- row has a checkbox to use the group's setting. Bar settings go in a second column, and rows for the
-- other style are hidden.
function Options:VisualControls(parent, x, y, global)
	local controls = { rows = {} }

	local function target()
		if global then return ns.db.display.visual end
		local node = self:Current()
		return node and node.visual
	end
	local function effective(key)
		if global then
			local value = ns.db.display.visual[key]
			if value == nil then value = Tree.VISUAL_DEFAULTS[key] end
			return value
		end
		return Tree:Visual(self:Current(), key)
	end
	local function set(key, value)
		local visual = target()
		if not visual then return end
		visual[key] = value
		self:Changed()
		controls:Refresh()
	end

	for _, info in ipairs(VISUAL_ROWS) do
		local key = info.key
		local row = { info = info, widgets = {} }
		if not global then
			row.inherit = W.Check(parent, "", function(value)
				local node = self:Current()
				if not node then return end
				if value then
					node.visual[key] = nil
				else
					node.visual[key] = copyValue(Tree:InheritedVisual(node, key))
				end
				self:Changed()
				controls:Refresh()
			end)
			W.Tooltip(row.inherit, L["Use group setting"], L["Checked: uses the setting of the group it is in (or Display settings at the top level). Uncheck to give it its own value."])
		end
		row.label = W.Label(parent, info.label, "GameFontNormalSmall")
		if info.kind == "number" then
			row.control = W.EditBox(parent, 50, function(text)
				local value = tonumber(text)
				if value then set(key, math.max(info.min, math.min(info.max, math.floor(value + 0.5)))) end
				controls:Refresh()
			end)
			row.dx, row.dy = CONTROL_X + 6, 4
		elseif info.kind == "bool" then
			row.control = W.Check(parent, "", function(value) set(key, value) end)
			row.dx, row.dy = CONTROL_X, 6
		elseif info.kind == "choice" then
			row.control = W.Dropdown(parent, 160, function(value) set(key, value) end)
			row.control:SetChoices(info.choices)
			row.dx, row.dy = CONTROL_X, 5
		else
			row.control = CreateFrame("Button", nil, parent, "BackdropTemplate")
			row.control:SetSize(40, 18)
			row.control:SetBackdrop(W.BACKDROP)
			row.control:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
			row.control:SetScript("OnClick", function()
				pickColor(effective(key), function(color) set(key, color) end)
			end)
			row.dx, row.dy = CONTROL_X + 2, 3
		end
		controls.rows[#controls.rows + 1] = row
	end

	local function place(row, rowX, rowY)
		local labelX = rowX
		if row.inherit then
			row.inherit:ClearAllPoints()
			row.inherit:SetPoint("TOPLEFT", rowX, rowY + 4)
			labelX = rowX + 26
		end
		row.label:ClearAllPoints()
		row.label:SetPoint("TOPLEFT", labelX, rowY)
		row.control:ClearAllPoints()
		row.control:SetPoint("TOPLEFT", rowX + row.dx, rowY + row.dy)
	end
	local function show(row, shown)
		if row.inherit then row.inherit:SetShown(shown) end
		row.label:SetShown(shown)
		row.control:SetShown(shown)
	end

	function controls:Refresh()
		local visual = target()
		if not visual then return end
		local style = effective("style")
		local counts = { 0, 0 }
		for _, row in ipairs(self.rows) do
			local key, kind = row.info.key, row.info.kind
			local shown = not row.info.style or row.info.style == style
			show(row, shown)
			if shown then
				local column = row.info.column or 1
				place(row, x + (column - 1) * Options.VISUAL_COLUMN_W, y - counts[column] * ROW_H)
				counts[column] = counts[column] + 1
			end
			local own = global or visual[key] ~= nil
			if row.inherit then row.inherit:SetChecked(not own) end
			local value = effective(key)
			if kind == "number" then
				row.control:SetValue(value)
			elseif kind == "bool" then
				row.control:SetChecked(value and true or false)
			elseif kind == "choice" then
				row.control:SetValue(value)
			else
				row.control:SetBackdropColor(value[1], value[2], value[3], 1)
			end
			row.control:SetAlpha(own and 1 or 0.5)
			row.label:SetAlpha(own and 1 or 0.6)
		end
		self.style, self.barRows = style, counts[2]
		if self.OnRefresh then self:OnRefresh() end
	end

	return controls
end

-- X / Y / scale boxes for a node that has its own screen position.
function Options:PositionControls(parent, x, y)
	local controls = {}
	local widgets = {}
	local function rounded(value) return math.floor(value + 0.5) end
	local function scaleText(value) return string.format("%.2f", value) end

	-- A slider plus an edit box for exact values, both writing node[key].
	local function field(key, label, sx, sy, minValue, maxValue, step, format)
		local entry = {}
		local function apply(value, refreshList)
			local node = self:Current()
			if not node then return end
			node[key] = math.max(minValue, math.min(maxValue, value))
			if refreshList then self:Changed() else ns.Core:RequestUpdate() end
			controls:Refresh()
		end
		entry.slider = W.Slider(parent, label, minValue, maxValue, step, 220, format, function(value) apply(value, false) end)
		entry.slider:SetPoint("TOPLEFT", sx, sy)
		entry.box = W.EditBox(parent, 56, function(text)
			local value = tonumber(text)
			if value then apply(value, true) else controls:Refresh() end
		end)
		entry.box:SetPoint("LEFT", entry.slider, "RIGHT", 14, 0)
		widgets[#widgets + 1] = entry.slider
		widgets[#widgets + 1] = entry.box
		return entry
	end

	controls.x = field("x", L["X"], x + 10, y - 34, -4000, 4000, 1, rounded)
	controls.y = field("y", L["Y"], x + 330, y - 34, -4000, 4000, 1, rounded)
	controls.scale = field("scale", L["Scale"], x + 10, y - 82, 0.3, 3, 0.05, scaleText)
	controls.help = W.Label(parent, "", "GameFontDisableSmall")
	controls.help:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
	controls.help:SetWordWrap(true)

	-- Sliders span the screen from the parent's middle, widened to include the current value.
	local function setRange(entry, half, value)
		local limit = math.max(half, math.ceil(math.abs(value)))
		entry.slider:SetRange(-limit, limit)
		entry.slider:SetSliderValue(value)
		entry.box:SetValue(math.floor(value * 10 + 0.5) / 10)
	end

	function controls:Refresh()
		local node = Options:Current()
		if not node then return end
		local positioned = Tree:IsPositioned(node)
		for _, widget in ipairs(widgets) do widget:SetShown(positioned) end
		self.help:ClearAllPoints()
		self.help:SetPoint("TOPLEFT", x, positioned and y - 116 or y - 20)
		self.help:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
		if positioned then
			local scale = node.scale > 0 and node.scale or 1
			setRange(self.x, math.ceil((UIParent:GetWidth() or 0) / 2 / scale), node.x)
			setRange(self.y, math.ceil((UIParent:GetHeight() or 0) / 2 / scale), node.y)
			self.scale.slider:SetSliderValue(node.scale)
			self.scale.box:SetValue(node.scale)
			local parentNode = Tree:ParentNode(node.id)
			self.help:SetText(parentNode
				and string.format(L["Offset from the middle of group \"%s\". You can also drag it on screen while the options are open."], parentNode.name)
				or L["Offset from the middle of the screen. You can also drag it on screen while the options are open."])
		else
			self.help:SetText(L["Its dynamic group sets its position. Reorder it in the list, or drag it on screen to move the whole group."])
		end
	end
	return controls
end

function Options:CreateDisplayTab(p)
	fieldLabel(p, L["Position"], 4, -10)
	self.nodePosition = self:PositionControls(p, 4, -10)
	local header = W.Label(p, L["Look"], "GameFontNormal")
	header:SetPoint("TOPLEFT", 4, -164)
	self.displayHelp = W.Label(p, "", "GameFontDisableSmall")
	self.displayHelp:SetPoint("LEFT", header, "RIGHT", 10, 0)
	self.nodeVisuals = self:VisualControls(p, 4, -190, false)
	self.barProgress = self:ProgressControls(p)
	self.nodeVisuals.OnRefresh = function(controls)
		local node = self:Current()
		local shown = controls.style == "bar" and node ~= nil and not Tree:IsGroup(node)
		self.barProgress:SetShown(shown)
		if shown then
			self.barProgress:ClearAllPoints()
			self.barProgress:SetPoint("TOPLEFT", 4 + Options.VISUAL_COLUMN_W, -190 - controls.barRows * ROW_H)
			self.barProgress:Refresh(node)
		end
	end
end

-- What a reminder's bar measures, shown under the bar settings.
function Options:ProgressControls(p)
	local frame = CreateFrame("Frame", nil, p)
	frame:SetSize(Options.VISUAL_COLUMN_W, ROW_H * 2)
	fieldLabel(frame, L["Bar shows"], 26, 0)
	frame.mode = W.Dropdown(frame, 160, function(value)
		local node = self:Current()
		if not node then return end
		node.progress = value
		self:Changed()
		frame:Refresh(node)
	end)
	frame.mode:SetChoices(PROGRESS_CHOICES)
	frame.mode:SetPoint("TOPLEFT", CONTROL_X, 5)
	W.Tooltip(frame.mode, L["Bar shows"], L["Automatic: time left for aura and weapon enchant conditions, the count or percent for item, ammo, bag, durability, health, power and rested conditions, otherwise a full bar. Empty when the aura or enchant is missing."])
	frame.maxLabel = fieldLabel(frame, L["Full at"], 26, -ROW_H)
	frame.max = W.EditBox(frame, 50, function(text)
		local node = self:Current()
		if not node then return end
		node.progressMax = math.max(0, tonumber(text) or 0)
		self:Changed()
		frame:Refresh(node)
	end)
	frame.max:SetPoint("TOPLEFT", CONTROL_X + 6, -ROW_H + 4)
	W.Tooltip(frame.max, L["Full at"], L["The value of a full bar: seconds for time, or the count. 0 uses the duration, the condition's amount or 100 for percents. For weapon enchants 0 uses the longest time left seen since it was applied."])
	frame.maxHelp = W.Label(frame, L["0 = automatic"], "GameFontDisableSmall")
	frame.maxHelp:SetPoint("LEFT", frame.max, "RIGHT", 10, 0)

	function frame:Refresh(node)
		local mode = node.progress or "auto"
		self.mode:SetValue(mode)
		local usesMax = mode ~= "full"
		self.max:SetValue(node.progressMax or 0)
		self.max:SetShown(usesMax)
		self.maxLabel:SetShown(usesMax)
		self.maxHelp:SetShown(usesMax)
	end
	return frame
end

function Options:RefreshDisplayTab(node)
	self.displayHelp:SetText(Tree:IsGroup(node)
		and L["Defaults for everything in this group."]
		or L["Checked boxes use the group's setting."])
	self.nodePosition:Refresh()
	self.nodeVisuals:Refresh()
end

function Options:RefreshPositions()
	if self.nodePosition then self.nodePosition:Refresh() end
	if self.groupPosition then self.groupPosition:Refresh() end
end

function Options:CreateLayoutTab(p)
	fieldLabel(p, L["Position"], 4, -10)
	self.groupPosition = self:PositionControls(p, 4, -10)

	local dynamic = CreateFrame("Frame", nil, p)
	dynamic:SetPoint("TOPLEFT", 0, -164)
	dynamic:SetPoint("BOTTOMRIGHT")
	self.dynamicOptions = dynamic

	local function setGroup(key, value)
		local g = self:Current()
		if not g then return end
		g[key] = value
		self:Changed()
		self:RefreshLayoutTab(g)
	end

	fieldLabel(dynamic, L["Grow"], 4, -10)
	self.growDropdown = W.Dropdown(dynamic, 180, function(value) setGroup("grow", value) end)
	self.growDropdown:SetChoices(GROW_CHOICES)
	self.growDropdown:SetPoint("TOPLEFT", 130, -5)
	W.Tooltip(self.growDropdown, L["Grow"], L["Direction new reminders are added in. Centered keeps the row or column centered on the group's position."])

	self.alignLabel = fieldLabel(dynamic, L["Align"], 4, -42)
	self.alignDropdown = W.Dropdown(dynamic, 180, function(value) setGroup("align", value) end)
	self.alignDropdown:SetChoices(ALIGN_CHOICES)
	self.alignDropdown:SetPoint("TOPLEFT", 130, -37)

	fieldLabel(dynamic, L["Spacing"], 4, -74)
	self.spacingBox = W.EditBox(dynamic, 50, function(text)
		setGroup("spacing", math.max(0, math.min(100, tonumber(text) or 6)))
	end)
	self.spacingBox:SetPoint("TOPLEFT", 136, -70)

	fieldLabel(dynamic, L["Sort"], 4, -106)
	self.sortDropdown = W.Dropdown(dynamic, 180, function(value) setGroup("sort", value) end)
	self.sortDropdown:SetChoices(SORT_CHOICES)
	self.sortDropdown:SetPoint("TOPLEFT", 130, -101)

	fieldLabel(dynamic, L["Per line"], 4, -138)
	self.wrapBox = W.EditBox(dynamic, 50, function(text)
		setGroup("wrap", math.max(0, math.min(50, math.floor(tonumber(text) or 0))))
	end)
	self.wrapBox:SetPoint("TOPLEFT", 136, -134)
	local wrapHelp = W.Label(dynamic, L["items before starting a new line (0 = one line)"], "GameFontDisableSmall")
	wrapHelp:SetPoint("LEFT", self.wrapBox, "RIGHT", 6, 0)

	self.staticHelp = W.Label(p,
		L["Each reminder and group in a static group keeps its own position relative to the group. Drag them on screen while the options are open, or set X and Y on their Display tab. Drag the group's handle to move everything at once."],
		"GameFontDisableSmall")
	self.staticHelp:SetPoint("TOPLEFT", 4, -164)
	self.staticHelp:SetPoint("RIGHT", p, "RIGHT", -20, 0)
	self.staticHelp:SetWordWrap(true)
end

function Options:RefreshLayoutTab(g)
	self.groupPosition:Refresh()
	local dynamic = g.layout == "dynamic"
	self.dynamicOptions:SetShown(dynamic)
	self.staticHelp:SetShown(not dynamic)
	if not dynamic then return end
	self.growDropdown:SetValue(g.grow)
	local vertical = g.grow == "DOWN" or g.grow == "UP" or g.grow == "VCENTER"
	self.alignLabel:SetShown(vertical)
	self.alignDropdown:SetShown(vertical)
	self.alignDropdown:SetValue(g.align)
	self.spacingBox:SetValue(g.spacing)
	self.sortDropdown:SetValue(g.sort)
	self.wrapBox:SetValue(g.wrap)
end
