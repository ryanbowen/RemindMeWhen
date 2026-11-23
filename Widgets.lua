local _, ns = ...
local L = ns.L

local W = {}
ns.Widgets = W

W.BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local MENU_ROW_H = 18

function W.Panel(parent, name)
	local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
	frame:SetBackdrop(W.BACKDROP)
	frame:SetBackdropColor(0.05, 0.05, 0.06, 0.96)
	frame:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	return frame
end

function W.Label(parent, text, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	label:SetJustifyH("LEFT")
	label:SetText(text or "")
	return label
end

local function resolve(value)
	if type(value) == "function" then return value() end
	return value
end

function W.Tooltip(frame, title, body)
	frame:HookScript("OnEnter", function(self)
		local heading = resolve(title)
		if not heading then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(heading, 1, 0.82, 0)
		local text = resolve(body)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function W.Button(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 100, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

function W.Check(parent, text, onClick)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check.label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	check.label:SetPoint("LEFT", check, "RIGHT", 2, 1)
	check.label:SetText(text or "")
	check:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	return check
end

function W.EditBox(parent, width, onCommit)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box.rmw = true
	box.value = ""
	box.hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	box.hint:SetPoint("LEFT", 2, 0)
	function box:UpdateHint()
		self.hint:SetShown(self:GetText() == "" and not self:HasFocus())
	end
	function box:SetHint(text)
		self.hint:SetText(text or "")
		self:UpdateHint()
	end
	function box:SetValue(value)
		self.value = value == nil and "" or tostring(value)
		self:SetText(self.value)
		self:SetCursorPosition(0)
		self:UpdateHint()
	end
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(self.value or "")
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self.hint:Hide()
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		local text = self:GetText()
		if text ~= self.value then
			self.value = text
			onCommit(text, self)
		end
		self:UpdateHint()
	end)
	box:SetScript("OnTextChanged", function(self)
		if not self:HasFocus() then self:UpdateHint() end
	end)
	return box
end

local menu, submenu
local SEARCH_H = 26

local function newMenuFrame(name)
	local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetFrameLevel(20)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetBackdrop(W.BACKDROP)
	frame:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
	frame:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
	frame.buttons = {}
	frame:Hide()
	return frame
end

local function getMenu()
	if menu then return menu end
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(1)
	catcher:RegisterForClicks("AnyUp")
	catcher:Hide()
	menu = newMenuFrame("RemindMeWhenMenu")
	submenu = newMenuFrame("RemindMeWhenSubmenu")
	submenu:SetFrameLevel(30)
	menu.submenu = submenu
	catcher:SetScript("OnClick", function() menu:Hide() end)
	menu:SetScript("OnShow", function() catcher:Show() end)
	menu:SetScript("OnHide", function()
		catcher:Hide()
		submenu:Hide()
		if menu.search then menu.search:ClearFocus() end
	end)
	tinsert(UISpecialFrames, "RemindMeWhenMenu")
	return menu
end

function W.CloseMenu()
	if menu then menu:Hide() end
end

local function containsValue(choices, value)
	for _, choice in ipairs(choices) do
		if choice.value == value and not choice.children then return true end
		if choice.children and containsValue(choice.children, value) then return true end
	end
	return false
end

local function menuButton(frame, i)
	local button = frame.buttons[i]
	if button then return button end
	button = CreateFrame("Button", nil, frame)
	button:SetHeight(MENU_ROW_H)
	button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:SetPoint("LEFT", 18, 0)
	button.text:SetJustifyH("LEFT")
	button.check = button:CreateTexture(nil, "OVERLAY")
	button.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	button.check:SetSize(14, 14)
	button.check:SetPoint("LEFT", 2, 0)
	button.arrow = button:CreateTexture(nil, "OVERLAY")
	button.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	button.arrow:SetSize(12, 12)
	button.arrow:SetPoint("RIGHT", -2, 0)
	frame.buttons[i] = button
	return button
end

-- Fills a menu frame with rows below top. A choice with children opens them beside it on hover.
-- Returns the width the rows need.
local function fillMenu(frame, choices, selected, onSelect, top, minWidth)
	local width = minWidth
	for i, choice in ipairs(choices) do
		local button = menuButton(frame, i)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 6, -top - (i - 1) * MENU_ROW_H)
		button:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
		button.text:SetText(choice.label)
		width = math.max(width, button.text:GetStringWidth() + 36)
		local children = choice.children
		button.arrow:SetShown(children ~= nil)
		button.check:SetShown(selected ~= nil and (children and containsValue(children, selected) or choice.value == selected))
		button:SetEnabled(not choice.disabled)
		local shade = choice.disabled and 0.5 or 1
		button.text:SetTextColor(shade, children and 0.82 * shade or shade, children and 0 or shade)
		local function openChildren()
			submenu:SetSize(fillMenu(submenu, children, selected, onSelect, 6, 120) + 12, #children * MENU_ROW_H + 12)
			submenu:ClearAllPoints()
			submenu:SetPoint("TOPLEFT", button, "TOPRIGHT", 8, 6)
			submenu:Show()
			submenu:Raise()
		end
		button:SetScript("OnEnter", function()
			if children then openChildren() elseif frame == menu then submenu:Hide() end
		end)
		button:SetScript("OnClick", function()
			if children then
				openChildren()
				return
			end
			menu:Hide()
			onSelect(choice.value)
		end)
		button:Show()
	end
	for i = #choices + 1, #frame.buttons do frame.buttons[i]:Hide() end
	return width
end

local function matchingLeaves(choices, text, out)
	for _, choice in ipairs(choices) do
		if choice.children then
			matchingLeaves(choice.children, text, out)
		elseif not choice.disabled and choice.label:lower():find(text, 1, true) then
			out[#out + 1] = choice
		end
	end
	return out
end

local function searchBox(m)
	if m.search then return m.search end
	local box = CreateFrame("EditBox", nil, m, "InputBoxTemplate")
	box:SetHeight(20)
	box:SetPoint("TOPLEFT", 12, -6)
	box:SetPoint("RIGHT", m, "RIGHT", -10, 0)
	box:SetAutoFocus(false)
	box.hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	box.hint:SetPoint("LEFT", 2, 0)
	box.hint:SetText(L["Type to search"])
	box:SetScript("OnEscapePressed", function() m:Hide() end)
	box:SetScript("OnEnterPressed", function()
		if m.pickFirst then m.pickFirst() end
	end)
	box:SetScript("OnTextChanged", function(self)
		self.hint:SetShown(self:GetText() == "")
		if m.refill then m.refill() end
	end)
	m.search = box
	return box
end

-- options.search: a box at the top that filters every choice, including those in submenus.
function W.OpenMenu(owner, choices, selected, onSelect, options)
	local m = getMenu()
	submenu:Hide()
	local minWidth = math.max(owner:GetWidth(), 120)
	local box = options and options.search and searchBox(m)
	if m.search then m.search:SetShown(box ~= nil) end
	local top = box and SEARCH_H + 6 or 6
	m.refill = function()
		submenu:Hide()
		local text = box and box:GetText():lower() or ""
		local shown = choices
		m.pickFirst = nil
		if text ~= "" then
			shown = matchingLeaves(choices, text, {})
			if #shown == 0 then shown = { { label = L["No matches"], disabled = true } } end
			local first = shown[1]
			if not first.disabled then
				m.pickFirst = function()
					m:Hide()
					onSelect(first.value)
				end
			end
		end
		local width = fillMenu(m, shown, selected, onSelect, top, minWidth)
		m:SetSize(width + 12, #shown * MENU_ROW_H + top + 6)
	end
	if box then
		box:SetText("")
		box.hint:Show()
	end
	m.refill()
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	m:Show()
	m:Raise()
	if box then box:SetFocus() end
end

function W.Dropdown(parent, width, onChange)
	local dropdown = CreateFrame("Button", nil, parent, "BackdropTemplate")
	dropdown:SetSize(width, 22)
	dropdown:SetBackdrop(W.BACKDROP)
	dropdown:SetBackdropColor(0.1, 0.1, 0.12, 1)
	dropdown:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
	dropdown.text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dropdown.text:SetPoint("LEFT", 7, 0)
	dropdown.text:SetPoint("RIGHT", -18, 0)
	dropdown.text:SetJustifyH("LEFT")
	dropdown.text:SetWordWrap(false)
	dropdown.arrow = dropdown:CreateTexture(nil, "OVERLAY")
	dropdown.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	dropdown.arrow:SetSize(12, 12)
	dropdown.arrow:SetPoint("RIGHT", -5, -2)
	dropdown.choices = {}
	function dropdown:SetChoices(choices)
		self.choices = choices
		self:Refresh()
	end
	function dropdown:SetValue(value)
		self.value = value
		self:Refresh()
	end
	-- With searchable, the menu gets a box that filters every choice, including those in categories.
	function dropdown:SetSearchable(searchable)
		self.searchable = searchable
	end
	local function labelFor(choices, value)
		for _, choice in ipairs(choices) do
			if choice.children then
				local label = labelFor(choice.children, value)
				if label then return label end
			elseif choice.value == value then
				return choice.label
			end
		end
		return nil
	end
	-- showUnknown: a string value missing from the choices (e.g. another class's talent) is shown as is.
	function dropdown:Refresh()
		local label = labelFor(resolve(self.choices) or {}, self.value)
		if not label and self.showUnknown and type(self.value) == "string" then label = self.value end
		self.text:SetText(label or "")
	end
	dropdown:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.8, 0.7, 0.3, 1) end)
	dropdown:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.45, 1) end)
	dropdown:SetScript("OnClick", function(self)
		W.OpenMenu(self, resolve(self.choices) or {}, self.value, function(value)
			self.value = value
			self:Refresh()
			if onChange then onChange(value, self) end
		end, { search = self.searchable })
	end)
	return dropdown
end

-- Scrolling multi-line text box. onCommit (optional) runs when focus is lost with changed text.
function W.MultiLineBox(parent, width, height, onCommit)
	local panel = W.Panel(parent)
	panel:SetSize(width, height)
	local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -26, 6)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject("ChatFontNormal")
	edit:SetWidth(width - 36)
	edit:SetHeight(height - 12)
	edit.rmw = true
	scroll:SetScrollChild(edit)
	panel:EnableMouse(true)
	panel:SetScript("OnMouseDown", function() edit:SetFocus() end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnEditFocusLost", function(self)
		local text = self:GetText()
		if onCommit and text ~= panel.value then
			panel.value = text
			onCommit(text)
		end
	end)
	panel.edit, panel.value = edit, ""
	function panel:SetValue(text)
		self.value = text or ""
		edit:SetText(self.value)
		edit:SetCursorPosition(0)
	end
	function panel:GetValue()
		return edit:GetText()
	end
	return panel
end

-- A row of buttons acting as tabs, calling onSelect(key) when one is clicked.
function W.Tabs(parent, tabs, onSelect)
	local bar = { buttons = {} }
	local previous
	for _, tab in ipairs(tabs) do
		local button = W.Button(parent, tab.label, tab.width or 130, function() onSelect(tab.key) end)
		if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) end
		bar.buttons[tab.key] = button
		bar.first = bar.first or button
		previous = button
	end
	function bar:Select(key)
		for k, button in pairs(self.buttons) do
			if k == key then button:LockHighlight() else button:UnlockHighlight() end
		end
	end
	return bar
end

local sliderCount = 0
function W.Slider(parent, label, minValue, maxValue, step, width, format, onChange)
	sliderCount = sliderCount + 1
	local name = "RemindMeWhenSlider" .. sliderCount
	local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	slider:SetWidth(width)
	slider:SetMinMaxValues(minValue, maxValue)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	local low = slider.Low or _G[name .. "Low"]
	local high = slider.High or _G[name .. "High"]
	local text = slider.Text or _G[name .. "Text"]
	if low then low:SetText(format(minValue)) end
	if high then high:SetText(format(maxValue)) end
	local function display(value)
		if text then text:SetText(label .. ": " .. format(value)) end
	end
	function slider:SetRange(low2, high2)
		self.updating = true
		self:SetMinMaxValues(low2, high2)
		self.updating = false
		if low then low:SetText(format(low2)) end
		if high then high:SetText(format(high2)) end
	end
	function slider:SetSliderValue(value)
		self.updating = true
		self:SetValue(value)
		display(value)
		self.updating = false
	end
	slider:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value / step + 0.5) * step
		display(value)
		if not self.updating then onChange(value) end
	end)
	return slider
end
