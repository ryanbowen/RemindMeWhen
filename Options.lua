local _, ns = ...
local W, Compat, Resolver, L = ns.Widgets, ns.Compat, ns.Resolver, ns.L

local Options = { page = "node", tabs = { reminder = "conditions", group = "conditions" }, fields = {} }
ns.Options = Options

local WIDTH, HEIGHT = 1080, 680
local LIST_W = 260
local PICK_LIMIT = 30
Options.WIDTH, Options.HEIGHT, Options.LIST_W = WIDTH, HEIGHT, LIST_W

Options.COLOR_TRUE = { 0.2, 0.9, 0.3 }
Options.COLOR_FALSE = { 0.85, 0.2, 0.2 }
Options.COLOR_UNKNOWN = { 0.95, 0.8, 0.2 }
Options.COLOR_OFF = { 0.35, 0.35, 0.35 }

function Options.SetColor(texture, color)
	texture:SetColorTexture(color[1], color[2], color[3], 1)
end

local STATUS_TEXTURES = {
	[Resolver.MISSING] = "Interface\\RaidFrame\\ReadyCheck-NotReady",
	[Resolver.UNVERIFIED] = "Interface\\RaidFrame\\ReadyCheck-Waiting",
	[Resolver.LOADING] = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

StaticPopupDialogs.REMINDMEWHEN_DELETE = {
	text = L["Delete \"%s\"?"],
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function(_, id) Options:DeleteNode(id) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs.REMINDMEWHEN_DELETE_GROUP = {
	text = L["Delete group \"%s\"?"],
	button1 = L["Delete everything"],
	button3 = L["Keep its contents"],
	button2 = CANCEL or "Cancel",
	OnAccept = function(_, id) Options:DeleteNode(id, false) end,
	OnAlt = function(_, id) Options:DeleteNode(id, true) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function Options:Current()
	return ns.db and ns.Tree:Get(self.selected)
end

function Options:IsOpen()
	return self.frame ~= nil and self.frame:IsShown()
end

function Options:ClearEditFocus()
	local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	if focus and focus.rmw then focus:ClearFocus() end
end

function Options:Toggle()
	if self.frame and self.frame:IsShown() then
		self.frame:Hide()
	else
		self:Open()
	end
end

function Options:Open()
	self:Create()
	local fit = math.min((UIParent:GetWidth() - 40) / WIDTH, (UIParent:GetHeight() - 40) / HEIGHT)
	self.frame:SetScale(math.max(0.6, math.min(1, fit)))
	self.frame:Show()
	ns.Display.editEnded = nil
	ns.Display.moving = nil
	ns.Core:RequestUpdate()
	self:Refresh()
end

function Options:Changed(rebuildConditions)
	ns.Display:InvalidateIcons()
	ns.Core:RequestUpdate()
	self:RefreshList()
	if rebuildConditions then self:RefreshConditions() end
end

function Options:Select(id)
	self:ClearEditFocus()
	if id ~= self.selected then ns.Versions:Update() end
	self.selected = id
	self.page = "node"
	self:Refresh()
end

function Options:ShowPage(page)
	self:ClearEditFocus()
	self.page = page
	self:Refresh()
end

-- Asks before deleting, and offers to keep the contents of a group.
function Options:ConfirmDelete(id)
	local node = ns.Tree:Get(id)
	if not node then return end
	self:ClearEditFocus()
	local popup = ns.Tree:IsGroup(node) and #node.children > 0 and "REMINDMEWHEN_DELETE_GROUP" or "REMINDMEWHEN_DELETE"
	local dialog = StaticPopup_Show(popup, node.name)
	if dialog then dialog.data = id end
end

function Options:DeleteNode(id, keepChildren)
	local index, list = ns.Tree:IndexOf(id)
	local parent = ns.Tree:Parent(id)
	ns.Core:DeleteNode(id, keepChildren)
	if self.selected == id then
		self.selected = list and (list[index] or list[index - 1]) or nil
		if not self.selected and parent ~= ns.Tree.ROOT then self.selected = parent end
	end
	self:Refresh()
end

function Options:OnNodeMoved(id)
	if self:IsOpen() and self.selected == id then self:RefreshPositions() end
end

function Options:Create()
	if self.frame then return end
	local frame = W.Panel(UIParent, "RemindMeWhenOptions")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetScript("OnHide", function()
		W.CloseMenu()
		ns.Versions:Update()
		ns.Core:RequestUpdate()
	end)
	frame:Hide()
	tinsert(UISpecialFrames, "RemindMeWhenOptions")

	local title = W.Label(frame, "RemindMeWhen", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	local subtitle = W.Label(frame, L["Show reminders when your conditions are met.  /rmw"], "GameFontDisableSmall")
	subtitle:SetPoint("LEFT", title, "RIGHT", 12, -1)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	self.moveButton = W.Button(frame, L["Move"], 80, function()
		self:ClearEditFocus()
		ns.Display:StartMoving()
	end)
	self.moveButton:SetPoint("RIGHT", close, "LEFT", -4, 0)
	W.Tooltip(self.moveButton, L["Move"], L["Hides this window and shows everything so you can drag it into place. Right-click a reminder or group to configure it. Click Done or press Escape when you are finished."])

	self.frame = frame
	self:CreateList()
	self:CreateEditor()
	self:CreateDisplayPage()
end

-- An edit box for a "Name (ID)" list with a status icon and a "+" picker.
function Options:ResolverField(parent, width, onCommit)
	local field = { resolverName = "Spells" }
	field.box = W.EditBox(parent, width, function(text) field:Commit(text) end)
	field.status = CreateFrame("Frame", nil, parent)
	field.status:SetSize(18, 18)
	field.status:EnableMouse(true)
	field.status:SetPoint("LEFT", field.box, "RIGHT", 4, 0)
	field.status.icon = field.status:CreateTexture(nil, "ARTWORK")
	field.status.icon:SetAllPoints()
	W.Tooltip(field.status, L["Check"], function()
		return table.concat(field:Resolver():Describe(field.results or {}), "\n")
	end)
	field.pick = CreateFrame("Button", nil, parent)
	field.pick:SetSize(18, 18)
	field.pick:SetPoint("LEFT", field.status, "RIGHT", 2, 0)
	field.pick:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
	field.pick:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
	field.pick:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
	field.pick:SetScript("OnClick", function() self:OpenPicker(field) end)
	W.Tooltip(field.pick, L["Pick from a list"], function()
		local source = field:Resolver().pickSource
			or (field.resolverName == "Items" and L["items in your bags"] or L["your spellbook"])
		return string.format(L["Lists %s. An unrecognized last entry filters the list and is replaced by your pick."], source)
	end)
	field.extraWidth = 42

	function field:Resolver() return ns[self.resolverName] end
	function field:SetResolver(name) self.resolverName = name end
	function field:SetValue(text)
		self.box:SetValue(text)
		self:UpdateStatus()
	end
	function field:Commit(text)
		local value = self:Resolver():Canonicalize(text)
		self.box:SetValue(value)
		self:UpdateStatus()
		onCommit(value, self)
	end
	function field:UpdateStatus()
		local results, worst = self:Resolver():Check(self.box.value)
		self.results = results
		if not worst then
			self.status:Hide()
			return
		end
		local texture = STATUS_TEXTURES[worst] or results[1].icon or "Interface\\RaidFrame\\ReadyCheck-Ready"
		self.status.icon:SetTexture(texture)
		self.status:SetShown(self.box:IsShown())
	end
	function field:SetShown(shown)
		self.box:SetShown(shown)
		self.pick:SetShown(shown)
		if shown then self:UpdateStatus() else self.status:Hide() end
	end
	function field:SetPoint(...)
		self.box:ClearAllPoints()
		self.box:SetPoint(...)
	end
	self.fields[#self.fields + 1] = field
	return field
end

function Options:OpenPicker(field)
	self:ClearEditFocus()
	local resolver = field:Resolver()
	local tokens = Compat.SplitList(field.box.value)
	local last = tokens[#tokens]
	local filter = last and resolver:Resolve(last).status ~= Resolver.OK and last:lower() or nil
	local choices, seen = {}, {}
	local function add(entry, note)
		if #choices >= PICK_LIMIT or seen[entry.id] then return end
		seen[entry.id] = true
		local icon = entry.icon and ("|T" .. entry.icon .. ":14:14|t ") or ""
		local suffix = note and ("  |cff888888" .. note .. "|r") or ""
		choices[#choices + 1] = { value = entry, label = icon .. resolver:Format(entry) .. suffix }
	end
	if field.extraChoices then
		for _, entry in ipairs(field.extraChoices(filter) or {}) do add(entry, entry.note) end
	end
	if not field.extraOnly then
		for _, entry in ipairs(resolver:Search(filter, PICK_LIMIT - #choices)) do add(entry) end
	end
	if #choices == 0 then
		local label = filter and string.format(L["Nothing matches \"%s\""], last) or L["Nothing found"]
		choices[1] = { label = label, disabled = true }
	end
	W.OpenMenu(field.pick, choices, nil, function(entry)
		if not entry then return end
		if filter then table.remove(tokens) end
		if field.single then wipe(tokens) end
		tokens[#tokens + 1] = resolver:Format(entry)
		field:Commit(table.concat(tokens, ", "))
	end)
end

-- Picker sources beyond the spellbook and bags.
function Options.AuraChoices(unit, filter)
	local out = {}
	for _, aura in ipairs(ns.Tracker:ReadAuras(unit, filter) or {}) do
		if type(aura.name) == "string" and type(aura.spellId) == "number" then
			out[#out + 1] = { name = aura.name, id = aura.spellId, icon = aura.icon, note = string.format(L["on %s now"], unit) }
		end
	end
	return out
end

function Options.MountChoices()
	local out = {}
	if not (C_MountJournal and C_MountJournal.GetMountInfoByID) then return out end
	for _, id in ipairs(ns.Conditions.CollectedMounts()) do
		local name, spellID, icon = C_MountJournal.GetMountInfoByID(id)
		if type(name) == "string" and type(spellID) == "number" then out[#out + 1] = { name = name, id = spellID, icon = icon } end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

function Options.FilterChoices(list, filter)
	if not filter then return list end
	local out = {}
	for _, entry in ipairs(list) do
		if entry.name:lower():find(filter, 1, true) then out[#out + 1] = entry end
	end
	return out
end

function Options:OnDataLoaded()
	if not (self.frame and self.frame:IsShown()) then return end
	for _, field in ipairs(self.fields) do
		if field.box:IsShown() then field:UpdateStatus() end
	end
end

function Options:RefreshStatus()
	if not self:IsOpen() then return end
	self:RefreshTreeStatus()
	if self.page ~= "node" then return end
	local node = self:Current()
	local preview = node and (ns.Tree:IsGroup(node) and self.groupIconPreview or self.iconPreview)
	if preview then preview:SetTexture(ns.Display:GetIcon(node)) end
	self:RefreshConditionStatus()
end

-- Status dot color for a node: green when showing (or active, for groups).
function Options.StatusColor(node)
	local st = ns.Core.state[node.id]
	if not (ns.Core:IsEnabledHere(node) and st) then return Options.COLOR_OFF end
	if st.active then return Options.COLOR_TRUE end
	if st.unknown then return Options.COLOR_UNKNOWN end
	return Options.COLOR_FALSE
end

function Options:OnEvaluated()
	if self.frame and self.frame:IsShown() then self:RefreshStatus() end
end

function Options:Refresh()
	if not self:IsOpen() then return end
	if not ns.Tree:Get(self.selected) then self.selected = ns.db.root[1] end
	self.editor:SetShown(self.page == "node")
	self.displayPage:SetShown(self.page == "display")
	self:RefreshList()
	if self.page == "node" then
		self:RefreshEditor()
	else
		self:RefreshDisplayPage()
	end
end

function Options:RegisterSettings()
	local panel = CreateFrame("Frame")
	panel.name = "RemindMeWhen"
	local title = W.Label(panel, "RemindMeWhen", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	local text = W.Label(panel, L["Reminders are edited in their own window. You can also type /rmw."], "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	local open = W.Button(panel, L["Open RemindMeWhen"], 180, function()
		if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
		self:Open()
	end)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, "RemindMeWhen")
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end
