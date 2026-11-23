local _, ns = ...
local W, Data, Compat, L = ns.Widgets, ns.Data, ns.Compat, ns.L
local Options = ns.Options

local TRIGGER_CHOICES = {
	{ value = "state", label = L["While its conditions are true"] },
	{ value = "event", label = L["When something happens (for a few seconds)"] },
}
local SLOT_CHOICES = { { value = 16, label = L["Main hand"] }, { value = 17, label = L["Off hand"] } }
local TABS = {
	reminder = {
		{ key = "conditions", label = L["Conditions"], width = 112 },
		{ key = "trigger", label = L["Trigger & timing"], width = 112 },
		{ key = "sound", label = L["Sound & alert"], width = 112 },
		{ key = "action", label = L["Click action"], width = 112 },
		{ key = "display", label = L["Display"], width = 112 },
		{ key = "load", label = L["Load"], width = 112 },
	},
	group = {
		{ key = "conditions", label = L["Conditions"], width = 112 },
		{ key = "layout", label = L["Layout"], width = 112 },
		{ key = "display", label = L["Display"], width = 112 },
		{ key = "load", label = L["Load"], width = 112 },
	},
}
local PANELS = { "conditions", "trigger", "sound", "action", "display", "layout", "load" }
local LAYOUT_CHOICES = {
	{ value = "dynamic", label = L["Dynamic (arranges what it holds)"] },
	{ value = "static", label = L["Static (free positions)"] },
}
local TEXT_HELP = L["Text shown next to the icon or on the bar. Leave empty to show no text (raid warning alerts then use the reminder name). Color codes like |cffff0000red|r work.\n\nPlaceholders:\n{left} - time left on the aura or weapon enchant\n{count} - the number from a count, percent or durability condition\n{missing} - group members missing a buff\n{target} - your target's name\n{name} - your character's name\n\nAdd a fallback for when there is no value: {left:missing} shows the time left, or \"missing\" when the aura or enchant is gone."]

local function fieldLabel(parent, text, x, y)
	local label = W.Label(parent, text, "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", x, y)
	return label
end

function Options:Edit(field, convert)
	return function(text)
		local r = self:Current()
		if not r then return end
		r[field] = convert and convert(text) or text
		self:Changed()
	end
end

function Options:CreateEditor()
	local panel = W.Panel(self.frame)
	panel:SetPoint("TOPLEFT", self.LIST_W + 20, -40)
	panel:SetPoint("BOTTOMRIGHT", -12, 12)
	self.editor = panel

	self.emptyLabel = W.Label(panel, L["No reminders yet. Click New reminder or Add preset."], "GameFontDisable")
	self.emptyLabel:SetPoint("CENTER")

	local content = CreateFrame("Frame", nil, panel)
	content:SetAllPoints()
	self.editorContent = content

	fieldLabel(content, L["Name"], 14, -18)
	self.nameBox = W.EditBox(content, 220, self:Edit("name"))
	self.nameBox:SetPoint("TOPLEFT", 74, -14)

	self.enabledCheck = W.Check(content, L["Enabled"], function(value)
		local r = self:Current()
		if not r then return end
		r.enabled = value
		self:Changed()
	end)
	self.enabledCheck:SetPoint("LEFT", self.nameBox, "RIGHT", 14, 0)

	self.charCheck = W.Check(content, L["On this character"], function(value)
		local r = self:Current()
		if not r then return end
		r.disabledFor = r.disabledFor or {}
		r.disabledFor[Compat.CharKey()] = (not value) or nil
		self:Changed()
	end)
	self.charCheck:SetPoint("LEFT", self.enabledCheck, "RIGHT", 70, 0)
	W.Tooltip(self.charCheck, L["On this character"], L["Uncheck to turn this off for the character you are playing, while keeping it on for your other characters."])

	local test = W.Button(content, L["Test"], 80, function() ns.Core:Test(self:Current()) end)
	test:SetPoint("TOPRIGHT", -14, -12)
	W.Tooltip(test, L["Test"], L["Shows this reminder (or every reminder in this group) for a few seconds, including sound and alert."])

	local export = W.Button(content, L["Export"], 80, function()
		if self:Current() then self:ShowExport({ self.selected }) end
	end)
	export:SetPoint("RIGHT", test, "LEFT", -6, 0)
	W.Tooltip(export, L["Export"], L["Creates a text string with this reminder or group (and everything in it) that others can import."])

	local reminderHeader = CreateFrame("Frame", nil, content)
	reminderHeader:SetPoint("TOPLEFT", 0, -40)
	reminderHeader:SetPoint("RIGHT")
	reminderHeader:SetHeight(60)
	self.reminderHeader = reminderHeader
	self:CreateReminderHeader(reminderHeader)

	local groupHeader = CreateFrame("Frame", nil, content)
	groupHeader:SetPoint("TOPLEFT", 0, -40)
	groupHeader:SetPoint("RIGHT")
	groupHeader:SetHeight(60)
	self.groupHeader = groupHeader
	fieldLabel(groupHeader, L["Type"], 14, -8)
	self.layoutDropdown = W.Dropdown(groupHeader, 280, function(value)
		local g = self:Current()
		if not g then return end
		ns.Core:SetLayout(g, value)
		self:RefreshEditor()
		self:Changed()
	end)
	self.layoutDropdown:SetChoices(LAYOUT_CHOICES)
	self.layoutDropdown:SetPoint("TOPLEFT", 74, -3)
	W.Tooltip(self.layoutDropdown, L["Type"], L["Dynamic groups arrange their contents in a row or grid. Static groups let you place each one yourself."])
	self.groupIconBox, self.groupIconPreview = self:IconField(groupHeader,
		L["Shown in the list and used by reminders in this group that have no icon. Leave empty for the default. Accepts a spell name or ID, item:ID, or a texture path such as Interface\\Icons\\INV_Misc_Bag_10."])
	self.groupSummary = W.Label(groupHeader, "", "GameFontDisableSmall")
	self.groupSummary:SetPoint("LEFT", self.groupIconPreview, "RIGHT", 14, 0)

	self.tabBars = {}
	for kind, tabs in pairs(TABS) do
		local bar = W.Tabs(content, tabs, function(key) self:ShowTab(key) end)
		bar.first:SetPoint("TOPLEFT", 14, -106)
		self.tabBars[kind] = bar
	end
	self.tabPanels = {}
	for _, key in ipairs(PANELS) do
		local tabPanel = CreateFrame("Frame", nil, content)
		tabPanel:SetPoint("TOPLEFT", 10, -134)
		tabPanel:SetPoint("BOTTOMRIGHT", -10, 10)
		tabPanel:Hide()
		self.tabPanels[key] = tabPanel
	end
	self:CreateConditionsTab(self.tabPanels.conditions)
	self:CreateTriggerTab(self.tabPanels.trigger)
	self:CreateSoundTab(self.tabPanels.sound)
	self:CreateActionTab(self.tabPanels.action)
	self:CreateDisplayTab(self.tabPanels.display)
	self:CreateLayoutTab(self.tabPanels.layout)
	self:CreateLoadTab(self.tabPanels.load)
end

function Options:CreateReminderHeader(content)
	fieldLabel(content, L["Text"], 14, -8)
	self.textBox = W.EditBox(content, 520, self:Edit("text"))
	self.textBox:SetPoint("TOPLEFT", 74, -4)
	self.textBox:SetHint(L["shown next to the icon (empty = no text). Placeholders: {left} {count} {missing} {target} {name}"])
	W.Tooltip(self.textBox, L["Text"], TEXT_HELP)

	self.iconBox, self.iconPreview = self:IconField(content,
		L["Leave empty to use the icon from the conditions, the click action or the group. Accepts a spell name or ID, item:ID, or a texture path such as Interface\\Icons\\Ability_Poisons."])
end

function Options:IconField(content, help)
	fieldLabel(content, L["Icon"], 14, -38)
	local box = W.EditBox(content, 170, self:Edit("icon"))
	box:SetPoint("TOPLEFT", 74, -34)
	box:SetHint(L["auto"])
	W.Tooltip(box, L["Icon"], help)
	local preview = content:CreateTexture(nil, "ARTWORK")
	preview:SetSize(20, 20)
	preview:SetPoint("LEFT", box, "RIGHT", 6, 0)
	preview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return box, preview
end

local function kindOf(node)
	return ns.Tree:IsGroup(node) and "group" or "reminder"
end

local function hasTab(kind, key)
	for _, tab in ipairs(TABS[kind]) do
		if tab.key == key then return true end
	end
	return false
end

function Options:ShowTab(key)
	self:ClearEditFocus()
	W.CloseMenu()
	local kind = kindOf(self:Current())
	if not hasTab(kind, key) then key = "conditions" end
	self.tabs[kind] = key
	for k, tabPanel in pairs(self.tabPanels) do tabPanel:SetShown(k == key) end
	for k, bar in pairs(self.tabBars) do
		for _, button in pairs(bar.buttons) do button:SetShown(k == kind) end
	end
	self.tabBars[kind]:Select(key)
end

function Options:CreateTriggerTab(p)
	fieldLabel(p, L["Show this reminder"], 4, -10)
	self.triggerDropdown = W.Dropdown(p, 320, function(value)
		local r = self:Current()
		if not r then return end
		r.trigger = value
		self:RefreshTrigger(r)
		self:Changed()
	end)
	self.triggerDropdown:SetChoices(TRIGGER_CHOICES)
	self.triggerDropdown:SetPoint("TOPLEFT", 130, -5)

	local state = CreateFrame("Frame", nil, p)
	state:SetPoint("TOPLEFT", 0, -40)
	state:SetPoint("BOTTOMRIGHT")
	self.stateOptions = state
	fieldLabel(state, L["Delay"], 4, -6)
	self.delayBox = W.EditBox(state, 40, self:Edit("delay", function(text) return math.max(0, tonumber(text) or 0) end))
	self.delayBox:SetPoint("TOPLEFT", 130, -2)
	W.Tooltip(self.delayBox, L["Delay (seconds)"], L["The conditions must stay true this long before the reminder shows. Avoids flicker, e.g. right after dismounting."])
	local seconds = W.Label(state, L["seconds the conditions must stay true before it shows"], "GameFontDisableSmall")
	seconds:SetPoint("LEFT", self.delayBox, "RIGHT", 6, 0)

	local event = CreateFrame("Frame", nil, p)
	event:SetPoint("TOPLEFT", 0, -40)
	event:SetPoint("BOTTOMRIGHT")
	self.eventOptions = event
	fieldLabel(event, L["When any of these happen:"], 4, -6)
	self.eventChecks = {}
	for i, trigger in ipairs(Data.triggers) do
		local check = W.Check(event, trigger.label, function(value)
			local r = self:Current()
			if not r then return end
			r.events[trigger.key] = value or nil
			self:Changed()
		end)
		local column, line = (i - 1) % 2, math.floor((i - 1) / 2)
		check:SetPoint("TOPLEFT", 10 + column * 240, -26 - line * 28)
		self.eventChecks[trigger.key] = check
	end
	local lines = math.ceil(#Data.triggers / 2)
	local y = -26 - lines * 28 - 12
	fieldLabel(event, L["Show for"], 4, y - 4)
	self.durationBox = W.EditBox(event, 40, self:Edit("duration", function(text) return math.max(1, tonumber(text) or 10) end))
	self.durationBox:SetPoint("TOPLEFT", 130, y)
	local durationHelp = W.Label(event, L["seconds"], "GameFontDisableSmall")
	durationHelp:SetPoint("LEFT", self.durationBox, "RIGHT", 6, 0)
	local help = W.Label(event,
		L["The conditions are still checked while the reminder is up, so you can combine an event with conditions (e.g. ready check and no food buff). Leave the condition list empty to always show it."],
		"GameFontDisableSmall")
	help:SetPoint("TOPLEFT", 4, y - 34)
	help:SetPoint("RIGHT", event, "RIGHT", -20, 0)
	help:SetWordWrap(true)
end

function Options:RefreshTrigger(r)
	self.triggerDropdown:SetValue(r.trigger)
	self.stateOptions:SetShown(r.trigger ~= "event")
	self.eventOptions:SetShown(r.trigger == "event")
	self.delayBox:SetValue(r.delay)
	self.durationBox:SetValue(r.duration)
	for key, check in pairs(self.eventChecks) do check:SetChecked(r.events[key] and true or false) end
end

-- A sound dropdown for field r[key] with a Play button beside it. Choosing a sound plays it once.
function Options:SoundPicker(p, key, y)
	local play
	local dropdown = W.Dropdown(p, 170, function(value)
		local r = self:Current()
		if not r then return end
		r[key] = value
		ns.Display.PlaySoundKey(value)
		play:SetEnabled(value ~= "NONE")
		self:Changed()
	end)
	dropdown:SetChoices(Data.SoundChoices)
	dropdown:SetPoint("TOPLEFT", 130, y)
	play = W.Button(p, L["Play"], 50, function()
		local r = self:Current()
		if r then ns.Display.PlaySoundKey(r[key]) end
	end)
	play:SetPoint("LEFT", dropdown, "RIGHT", 8, 0)
	W.Tooltip(play, L["Play"], L["Plays the chosen sound so you can hear it."])
	dropdown.play = play
	return dropdown
end

local function showSound(dropdown, value)
	dropdown:SetValue(value)
	dropdown.play:SetEnabled(value ~= "NONE")
end

function Options:CreateSoundTab(p)
	fieldLabel(p, L["Sound"], 4, -10)
	self.soundDropdown = self:SoundPicker(p, "sound", -5)

	fieldLabel(p, L["Repeat every"], 4, -42)
	self.repeatBox = W.EditBox(p, 40, self:Edit("repeatSound", function(text) return math.max(0, tonumber(text) or 0) end))
	self.repeatBox:SetPoint("TOPLEFT", 130, -38)
	local repeatHelp = W.Label(p, L["seconds while the reminder is shown (0 = play once)"], "GameFontDisableSmall")
	repeatHelp:SetPoint("LEFT", self.repeatBox, "RIGHT", 6, 0)

	self.alertCheck = W.Check(p, L["Center-screen alert when it appears"], function(value)
		local r = self:Current()
		if not r then return end
		r.alert = value
		self:Changed()
	end)
	self.alertCheck:SetPoint("TOPLEFT", 4, -70)

	local warnHeader = W.Label(p, L["Warnings before it runs out"], "GameFontNormal")
	warnHeader:SetPoint("TOPLEFT", 4, -112)
	fieldLabel(p, L["Warn at"], 4, -142)
	self.warnBox = W.EditBox(p, 160, function(text)
		local r = self:Current()
		if not r then return end
		local list = {}
		for _, part in ipairs(Compat.SplitList(text)) do list[#list + 1] = Compat.ParseDuration(part) end
		r.warnAt = ns.Core.NormalizeWarnings(list)
		self:RefreshSound(r)
		self:Changed()
	end)
	self.warnBox:SetPoint("TOPLEFT", 130, -138)
	self.warnBox:SetHint(L["e.g. 1m, 10s"])
	W.Tooltip(self.warnBox, L["Warn at"], L["Time left, separated by commas (90, 1m30s, 1:30 and 10s all work). While the reminder is shown, each time the time left of its aura, enchant or timer drops past one of these, it plays the warning sound, flashes and shows the center-screen alert if that is on. Up to 5."])
	local warnHelp = W.Label(p, L["time left on the aura, enchant or timer"], "GameFontDisableSmall")
	warnHelp:SetPoint("LEFT", self.warnBox, "RIGHT", 8, 0)

	fieldLabel(p, L["Warning sound"], 4, -174)
	self.warnSoundDropdown = self:SoundPicker(p, "warnSound", -169)
end

function Options:RefreshSound(r)
	showSound(self.soundDropdown, r.sound)
	self.repeatBox:SetValue(r.repeatSound)
	self.alertCheck:SetChecked(r.alert)
	local parts = {}
	for i, seconds in ipairs(r.warnAt) do parts[i] = Compat.FormatDuration(seconds) end
	self.warnBox:SetValue(table.concat(parts, ", "))
	showSound(self.warnSoundDropdown, r.warnSound)
end

function Options:CreateActionTab(p)
	fieldLabel(p, L["When clicked"], 4, -10)
	self.actionDropdown = W.Dropdown(p, 240, function(value)
		local r = self:Current()
		if not r then return end
		local previous = r.action.kind
		if (previous == "mount") ~= (value == "mount") and (previous == "spell" or previous == "mount") then r.action.spell = "" end
		r.action.kind = value
		if value == "macro" then r.macroDisabled = nil end
		self:RefreshAction(r)
		self:Changed()
	end)
	self.actionDropdown:SetChoices(ns.Actions.KINDS)
	self.actionDropdown:SetPoint("TOPLEFT", 130, -5)

	local function commit(key)
		return function(value)
			local r = self:Current()
			if not r then return end
			r.action[key] = value
			self:RefreshActionPreview(r)
			self:Changed()
		end
	end

	self.actionSpellLabel = fieldLabel(p, L["Spell"], 4, -44)
	self.actionSpell = self:ResolverField(p, 300, commit("spell"))
	self.actionSpell:SetPoint("TOPLEFT", 136, -40)

	self.actionItemLabel = fieldLabel(p, L["Items"], 4, -44)
	self.actionItem = self:ResolverField(p, 300, commit("item"))
	self.actionItem:SetResolver("Items")
	self.actionItem:SetPoint("TOPLEFT", 136, -40)
	W.Tooltip(self.actionItem.box, L["Items"],
		L["Item names or IDs, best first. The first one you have in your bags is used, skipping items above your level and stones that do not fit the weapon."])

	local fillChoices = {}
	for _, list in ipairs(Data.itemLists) do fillChoices[#fillChoices + 1] = { value = list, label = list.label } end
	self.actionFill = W.Button(p, L["Fill with..."], 100, function(button)
		W.OpenMenu(button, fillChoices, nil, function(list)
			local r = self:Current()
			if not r then return end
			r.action.item = ns.Items:Canonicalize(list.items)
			self.actionItem:SetValue(r.action.item)
			self:RefreshActionPreview(r)
			self:Changed()
		end)
	end)
	self.actionFill:SetPoint("TOPLEFT", 486, -39)
	W.Tooltip(self.actionFill, L["Fill with..."], L["Replace the item list with a ready-made list, best first."])

	self.actionSlotLabel = fieldLabel(p, L["Weapon"], 4, -76)
	self.actionSlot = W.Dropdown(p, 110, function(value)
		local r = self:Current()
		if not r then return end
		r.action.slot = value
		self:RefreshActionPreview(r)
		self:Changed()
	end)
	self.actionSlot:SetChoices(SLOT_CHOICES)
	self.actionSlot:SetPoint("TOPLEFT", 130, -71)

	self.actionMacroLabel = fieldLabel(p, L["Macro text"], 4, -44)
	self.actionMacro = W.MultiLineBox(p, 480, 100, function(text)
		local r = self:Current()
		if not r then return end
		r.action.macro = text
		self:RefreshActionPreview(r)
		self:Changed()
	end)
	self.actionMacro:SetPoint("TOPLEFT", 130, -40)

	self.actionWarning = W.Label(p,
		L["This reminder was imported with a macro, which was switched off for safety. Check the macro text, then choose Run macro text again."],
		"GameFontRedSmall")
	self.actionWarning:SetPoint("TOPLEFT", 4, -152)
	self.actionWarning:SetPoint("RIGHT", p, "RIGHT", -20, 0)
	self.actionWarning:SetWordWrap(true)

	self.actionPreview = W.Label(p, "", "GameFontHighlightSmall")
	self.actionPreview:SetPoint("TOPLEFT", 4, -184)
	self.actionPreview:SetPoint("RIGHT", p, "RIGHT", -20, 0)
	self.actionPreview:SetWordWrap(true)

	local help = W.Label(p,
		L["Left-click the reminder on screen to do this. Blizzard blocks click actions in combat, so they only work out of combat. Right-click still snoozes in combat."],
		"GameFontDisableSmall")
	help:SetPoint("BOTTOMLEFT", 4, 8)
	help:SetPoint("RIGHT", p, "RIGHT", -20, 0)
	help:SetWordWrap(true)
end

function Options:RefreshActionPreview(r)
	local macro = ns.Actions:MacroFor(r)
	if r.action.kind == "none" then
		self.actionPreview:SetText("")
	elseif macro then
		self.actionPreview:SetText(L["Clicking runs:"] .. "\n|cffaaaaaa" .. macro:gsub("|", "||") .. "|r")
	else
		self.actionPreview:SetText("|cffff6060" .. L["Nothing to do right now: check the entries above (for items, one of them must be in your bags)."] .. "|r")
	end
end

function Options:RefreshAction(r)
	local a = r.action
	local kind = a.kind
	self.actionDropdown:SetValue(kind)
	local spell = kind == "spell" or kind == "mount"
	local item = kind == "item" or kind == "weapon"
	self.actionSpellLabel:SetShown(spell)
	self.actionSpellLabel:SetText(kind == "mount" and L["Mount (empty = random)"] or L["Spell"])
	self.actionSpell:SetShown(spell)
	self.actionSpell.single = kind == "mount"
	self.actionSpell.extraOnly = kind == "mount"
	self.actionSpell.extraChoices = kind == "mount" and function(filter) return Options.FilterChoices(Options.MountChoices(), filter) end or nil
	if spell then self.actionSpell:SetValue(a.spell) end
	self.actionItemLabel:SetShown(item)
	self.actionItem:SetShown(item)
	if item then self.actionItem:SetValue(a.item) end
	self.actionFill:SetShown(kind == "weapon")
	self.actionSlotLabel:SetShown(kind == "weapon")
	self.actionSlot:SetShown(kind == "weapon")
	self.actionSlot:SetValue(a.slot)
	self.actionMacroLabel:SetShown(kind == "macro")
	self.actionMacro:SetShown(kind == "macro")
	self.actionMacro:SetValue(a.macro)
	self.actionWarning:SetShown(r.macroDisabled and kind == "none" or false)
	self:RefreshActionPreview(r)
end

function Options:RefreshEditor()
	local node = self:Current()
	self.emptyLabel:SetShown(node == nil)
	self.editorContent:SetShown(node ~= nil)
	if not node then return end
	local kind = kindOf(node)
	self.nameBox:SetValue(node.name)
	self.enabledCheck:SetChecked(node.enabled)
	self.charCheck:SetChecked(not (node.disabledFor and node.disabledFor[Compat.CharKey()]))
	self.reminderHeader:SetShown(kind == "reminder")
	self.groupHeader:SetShown(kind == "group")
	self:ShowTab(self.tabs[kind])
	self:RefreshConditions()
	self:RefreshDisplayTab(node)
	self:RefreshLoadTab(node)
	if kind == "group" then
		self.layoutDropdown:SetValue(node.layout)
		self.groupIconBox:SetValue(node.icon)
		self.groupSummary:SetText(string.format(L["Holds %d reminders (%d directly)."], #ns.Tree:Reminders(node.id), #node.children))
		self:RefreshLayoutTab(node)
		return
	end
	self.textBox:SetValue(node.text)
	self.iconBox:SetValue(node.icon)
	self:RefreshTrigger(node)
	self:RefreshSound(node)
	self:RefreshAction(node)
end
