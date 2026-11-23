local _, ns = ...
local Anchors, Compat, Conditions, Data, Layout, Tree, L =
	ns.Anchors, ns.Compat, ns.Conditions, ns.Data, ns.Layout, ns.Tree, ns.L

-- One frame per shown reminder (items) and per shown group (groups). Dynamic groups arrange their
-- contents with Layout, and everything else sits at its own x/y from its parent's center.
local Display = { items = {}, groups = {}, shown = {}, icons = {}, visible = {} }
ns.Display = Display

local EDIT_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Buttons\\WHITE8X8",
	edgeSize = 1,
}
local STATIC_HANDLE = 22
local PREVIEW_ALPHA = 0.45

local SNOOZE_CHOICES = {
	{ value = "clear", label = L["Until its conditions clear"] },
	{ value = 300, label = L["For 5 minutes"] },
	{ value = 900, label = L["For 15 minutes"] },
	{ value = 3600, label = L["For 1 hour"] },
	{ value = "zone", label = L["Until I change zones"] },
	{ value = "session", label = L["Until I reload or log out"] },
}

-- The reminder's text, or its name when the text is empty, for alerts and name sorting.
local function labelOf(r)
	if r.text and r.text ~= "" then return r.text end
	return r.name or ""
end

local function varsOf(r)
	local st = ns.Core.state[r.id]
	return st and st.vars or {}
end

-- Replaces {left} {count} {missing} {target} {name}. Values that are not known show as "?",
-- or as the fallback in {key:fallback}, e.g. {left:missing}.
function Display:FormatText(r, vars, text)
	vars = vars or varsOf(r)
	return ((text or r.text or ""):gsub("{(%a+)(:?)([^{}]*)}", function(key, colon, fallback)
		if colon == "" and fallback ~= "" then return nil end
		if colon == "" then fallback = "?" end
		local value
		if key == "left" then
			value = vars.expires and Compat.FormatTime(vars.expires - GetTime())
		elseif key == "count" or key == "missing" then
			value = vars[key]
		elseif key == "target" then
			value = Compat.Plain(UnitName("target"))
		elseif key == "name" then
			value = Compat.Plain(UnitName("player"))
		else
			return nil
		end
		return value ~= nil and tostring(value) or fallback
	end))
end

function Display:Create() end

-- Locking also ends move mode, and the editor's edit mode until the editor is opened again.
function Display:IsEditMode()
	local d = ns.db.display
	return self.moving or not d.locked or (d.editWhileOptions and ns.Options:IsOpen() and not self.editEnded) or false
end

function Display:SetLocked(locked)
	ns.db.display.locked = locked
	self.editEnded = locked or nil
	if locked then self.moving = nil end
	ns.Core:RequestUpdate()
end

-- Move mode hides the editor and lets everything be dragged until it ends. It is not saved.
function Display:StartMoving()
	local Options = ns.Options
	self.reopenEditor = Options:IsOpen()
	self.moving = true
	if self.reopenEditor then Options.frame:Hide() end
	ns.Core:RequestUpdate()
end

-- reopen: open the editor again when move mode started from it.
function Display:StopMoving(reopen)
	if not self.moving then return end
	self.moving = nil
	ns.PositionPanel.requested = nil
	if reopen and self.reopenEditor then ns.Options:Open() else ns.Core:RequestUpdate() end
end

-- Opens the editor with the node selected. Right-clicking something that can be moved does this.
function Display:Configure(id)
	if not Tree:Get(id) then return end
	ns.Options:Open()
	ns.Options:Reveal(id)
end

function Display:ApplySettings()
	ns.Core:RequestUpdate()
end

function Display:ShowTooltip(owner, r)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(r.name, 1, 0.82, 0)
	if self:IsEditMode() then
		local mover = Display.FollowsMouse(r) and L["Follows the mouse. Set its offset on the Display tab."]
			or Tree:IsPositioned(r) and L["Drag to move it."] or L["Drag to move its group."]
		GameTooltip:AddLine(mover, 1, 1, 1, true)
		GameTooltip:AddLine(L["Right-click to configure it."], 1, 1, 1, true)
		GameTooltip:Show()
		return
	end
	local action = ns.Actions:Describe(r)
	if action then
		local color = Compat.InCombat() and 0.5 or 1
		GameTooltip:AddLine(L["Left-click: "] .. action, color, color, color, true)
		if Compat.InCombat() then GameTooltip:AddLine(L["(click actions are not available in combat)"], 0.6, 0.6, 0.6, true) end
	end
	if ns.db.display.clickToDismiss then GameTooltip:AddLine(L["Right-click: snooze"], 1, 1, 1, true) end
	GameTooltip:Show()
end

function Display:OpenSnoozeMenu(owner, r)
	if not (r and ns.db.display.clickToDismiss) or self:IsEditMode() then return end
	ns.Widgets.OpenMenu(owner, SNOOZE_CHOICES, nil, function(how) ns.Core:Snooze(r, how) end)
end

local function followCursor(frame)
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

-- A point that follows the mouse for nodes anchored to it. It only moves while shown.
function Display:Cursor()
	local cursor = self.cursor
	if not cursor then
		cursor = CreateFrame("Frame", nil, UIParent)
		cursor:SetSize(1, 1)
		cursor:SetScript("OnUpdate", followCursor)
		self.cursor = cursor
	end
	if not cursor:IsShown() then followCursor(cursor) end
	cursor:Show()
	return cursor
end

-- Whether the top-level node holding node follows the mouse.
local function followsMouse(node)
	local root = Tree:Get(Anchors.Root(node.id))
	return root ~= nil and root.anchorTo == "MOUSE"
end
Display.FollowsMouse = followsMouse

-- The frame and point a positioned node's offset is measured from: the origin of its static group,
-- or for a top-level node the screen, a named frame, another reminder or group, or the mouse.
-- A target that is missing, hidden or not allowed falls back to the screen. During an update, ctx
-- tells which frames are drawn this pass.
function Display:AnchorTarget(node, ctx)
	local parent = Tree:ParentNode(node.id)
	if parent then return self.groups[parent.id] or UIParent, "CENTER" end
	if node.anchorTo == "MOUSE" then
		if ctx then ctx.followsMouse = true end
		return self:Cursor(), "CENTER"
	elseif node.anchorTo == "NODE" then
		local target = Anchors.Resolve(node)
		local frame = target and (Tree:IsGroup(target) and self.groups[target.id] or self.items[target.id])
		local drawn = frame and (ctx and ctx.used[frame] or not ctx and frame:IsShown())
		if drawn then return frame, node.relPoint end
	elseif node.anchorTo == "FRAME" then
		local named = node.anchorFrame ~= "" and _G[node.anchorFrame]
		if type(named) == "table" and named.GetRect and named.IsVisible and named:IsVisible()
			and not (named.IsForbidden and named:IsForbidden()) then
			return named, node.relPoint
		end
	end
	return UIParent, node.relPoint
end

-- Stores where a frame is as the offset of its anchor point from its target's point.
function Display:SavePosition(id, frame)
	local node = Tree:Get(id)
	if not node then return end
	local target, relPoint = self:AnchorTarget(node)
	local left, bottom, width, height = frame:GetRect()
	local tLeft, tBottom, tWidth, tHeight = target:GetRect()
	if not (left and tLeft) then return end
	local point = Tree:IsGroup(node) and frame.anchorPoint or node.point
	local ox, oy = Layout.PointOffset(point or "CENTER", width, height)
	local rx, ry = Layout.PointOffset(relPoint, tWidth, tHeight)
	local k = target:GetEffectiveScale() / frame:GetEffectiveScale()
	node.x = math.floor(left + width / 2 + ox - (tLeft + tWidth / 2 + rx) * k + 0.5)
	node.y = math.floor(bottom + height / 2 + oy - (tBottom + tHeight / 2 + ry) * k + 0.5)
	frame.placedAt = nil
	ns.Options:OnNodeMoved(id)
	ns.Core:RequestUpdate()
end

local function setEditLook(frame, editing, r, g, b)
	if editing then
		frame:SetBackdrop(EDIT_BACKDROP)
		frame:SetBackdropColor(r, g, b, 0.18)
		frame:SetBackdropBorderColor(r, g, b, 0.9)
	else
		frame:SetBackdrop(nil)
	end
end

local function pulseFor(texture, fromAlpha)
	local pulse = texture:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local alpha = pulse:CreateAnimation("Alpha")
	alpha:SetFromAlpha(fromAlpha)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.6)
	return pulse
end

local function barFill(fraction, reverse)
	fraction = math.max(0, math.min(1, fraction or 0))
	return reverse and 1 - fraction or fraction
end

-- Time bars drain every frame between evaluation passes.
local function drainBar(bar)
	if bar.expires then bar:SetValue(barFill((bar.expires - GetTime()) / bar.total, bar.reverse)) end
end

function Display:CreateItem()
	local item = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	item:SetFrameStrata("MEDIUM")
	item.border = item:CreateTexture(nil, "BACKGROUND")
	item.border:SetColorTexture(0, 0, 0, 0.85)
	item.icon = item:CreateTexture(nil, "ARTWORK")
	item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	item.border:SetPoint("TOPLEFT", item.icon, -1, 1)
	item.border:SetPoint("BOTTOMRIGHT", item.icon, 1, -1)
	item.cooldown = CreateFrame("Cooldown", nil, item, "CooldownFrameTemplate")
	item.cooldown:SetAllPoints(item.icon)
	if item.cooldown.SetHideCountdownNumbers then item.cooldown:SetHideCountdownNumbers(true) end
	if item.cooldown.SetReverse then item.cooldown:SetReverse(true) end
	item.timer = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	item.timer:SetPoint("BOTTOM", item.icon, "BOTTOM", 0, 2)
	item.iconGlow = item:CreateTexture(nil, "OVERLAY", nil, 7)
	item.iconGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	item.iconGlow:SetBlendMode("ADD")
	item.iconGlow:SetVertexColor(1, 0.85, 0.3, 1)
	item.iconGlow:SetPoint("CENTER", item.icon)
	item.iconGlow:Hide()
	item.iconPulse = pulseFor(item.iconGlow, 0.25)
	item.glow, item.pulse = item.iconGlow, item.iconPulse
	item.text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	item.text:SetShadowOffset(1, -1)

	item.bar = CreateFrame("StatusBar", nil, item)
	item.bar:SetMinMaxValues(0, 1)
	item.bar.background = item.bar:CreateTexture(nil, "BACKGROUND")
	item.bar.background:SetAllPoints()
	item.bar.text = item.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	item.bar.text:SetShadowOffset(1, -1)
	item.bar.text:SetJustifyH("LEFT")
	item.bar.text:SetWordWrap(false)
	item.bar.timer = item.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	item.bar.timer:SetShadowOffset(1, -1)
	item.bar.timer:SetPoint("RIGHT", -4, 0)
	item.bar.timer:SetJustifyH("RIGHT")
	item.barGlow = item.bar:CreateTexture(nil, "OVERLAY", nil, 7)
	item.barGlow:SetTexture("Interface\\Buttons\\WHITE8X8")
	item.barGlow:SetBlendMode("ADD")
	item.barGlow:SetVertexColor(1, 0.85, 0.3, 0.35)
	item.barGlow:SetAllPoints(item)
	item.barGlow:Hide()
	item.barPulse = pulseFor(item.barGlow, 0)
	item.bar:SetScript("OnUpdate", drainBar)
	item.bar:Hide()
	item:SetScript("OnMouseUp", function(frame, button)
		if button ~= "RightButton" or not frame.reminder then return end
		if Display:IsEditMode() then
			Display:Configure(frame.reminder.id)
		else
			Display:OpenSnoozeMenu(frame, frame.reminder)
		end
	end)
	item:SetScript("OnEnter", function(frame)
		if frame.reminder then Display:ShowTooltip(frame, frame.reminder) end
	end)
	item:SetScript("OnLeave", function() GameTooltip:Hide() end)
	ns.Drag.Attach(item)
	return item
end

function Display:CreateGroupFrame()
	local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetFrameStrata("MEDIUM")
	frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.label:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
	frame:SetScript("OnEnter", function(f)
		local node = Tree:Get(f.nodeID)
		if not node then return end
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:AddLine(node.name, 1, 0.82, 0)
		GameTooltip:AddLine(L["Drag to move this group."], 1, 1, 1, true)
		GameTooltip:AddLine(L["Right-click to configure it."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame:SetScript("OnMouseUp", function(f, button)
		if button == "RightButton" and Display:IsEditMode() then Display:Configure(f.nodeID) end
	end)
	ns.Drag.Attach(frame)
	return frame
end

function Display:InvalidateIcons()
	wipe(self.icons)
end

local function iconFromText(icon)
	local itemID = tonumber(icon:match("^item:(%d+)$") or "")
	if itemID then return Compat.GetItemIcon(itemID) end
	local number = tonumber(icon)
	if number then
		local _, _, spellIcon = Compat.GetSpellInfo(number)
		return spellIcon or Compat.GetItemIcon(number) or number
	end
	if icon:find("[\\/]") then return icon end
	local _, _, spellIcon = Compat.GetSpellInfo(icon)
	return spellIcon or ("Interface\\Icons\\" .. icon)
end

-- The custom icon of the nearest group above the node that has one.
local function groupIcon(id)
	local parentID = Tree:Parent(id)
	while parentID and parentID ~= Tree.ROOT do
		local group = Tree:Get(parentID)
		if group and (group.icon or "") ~= "" then return iconFromText(group.icon) end
		parentID = Tree:Parent(parentID)
	end
	return nil
end

function Display:ResolveIcon(r)
	local icon = r.icon or ""
	if icon ~= "" then return iconFromText(icon) end
	if Tree:IsGroup(r) then return nil end
	for _, c in ipairs(r.conditions) do
		local tex = Conditions:GetIcon(c)
		if tex then return tex end
	end
	return ns.Actions:GetIcon(r) or groupIcon(r.id)
end

-- Icons are resolved out of combat where possible because spell data can turn secret in combat.
function Display:GetIcon(r)
	local cached = self.icons[r.id]
	if cached == nil or (cached == false and not Compat.InCombat()) then
		cached = self:ResolveIcon(r) or false
		self.icons[r.id] = cached
	end
	if cached then return cached end
	if Tree:IsGroup(r) then
		return r.layout == "static" and Data.STATIC_GROUP_ICON or Data.DYNAMIC_GROUP_ICON
	end
	return Data.QUESTION_ICON
end

local function setFont(fontString, size)
	local font = GameFontNormalLarge:GetFont()
	fontString:SetFont(font, size, "OUTLINE")
end

local TEXT_ANCHORS = {
	RIGHT = { "LEFT", "RIGHT", Layout.TEXT_GAP, 0, "LEFT" },
	LEFT = { "RIGHT", "LEFT", -Layout.TEXT_GAP, 0, "RIGHT" },
	TOP = { "BOTTOM", "TOP", 0, Layout.TEXT_GAP_VERTICAL, "CENTER" },
	BOTTOM = { "TOP", "BOTTOM", 0, -Layout.TEXT_GAP_VERTICAL, "CENTER" },
	CENTER = { "CENTER", "CENTER", 0, 0, "CENTER" },
}

-- Picks the glow that belongs to the current style, stopping the other one.
local function useGlow(item, glow, pulse)
	if item.glow == glow then return end
	item.pulse:Stop()
	item.glow:Hide()
	item.glow, item.pulse = glow, pulse
end

-- Applies the reminder's visual settings and sizes the frame. Returns the box width and height.
function Display:LayoutItem(item, r)
	local V = function(key) return Tree:Visual(r, key) end
	local vars = varsOf(r)
	item.icon:SetTexture(self:GetIcon(r))
	if V("style") == "bar" then return self:LayoutBar(item, r, V, vars) end

	item.bar:Hide()
	item.bar.expires = nil
	useGlow(item, item.iconGlow, item.iconPulse)
	local size, fontSize, showText, textPos = V("iconSize"), V("fontSize"), V("showText"), V("textPos")
	item.icon:Show()
	item.icon:SetSize(size, size)
	item.border:ClearAllPoints()
	item.border:SetPoint("TOPLEFT", item.icon, -1, 1)
	item.border:SetPoint("BOTTOMRIGHT", item.icon, 1, -1)
	item.glow:SetSize(size * 1.9, size * 1.9)
	if item.fontSize ~= fontSize or item.iconSize ~= size then
		setFont(item.text, fontSize)
		setFont(item.timer, math.max(9, math.floor(size * 0.3)))
		item.fontSize, item.iconSize = fontSize, size
	end
	local color = V("textColor")
	item.text:SetTextColor(color[1], color[2], color[3])
	item.text:SetShown(showText)
	item.text:SetText(self:FormatText(r, vars))
	local anchor = TEXT_ANCHORS[textPos] or TEXT_ANCHORS.RIGHT
	item.text:ClearAllPoints()
	item.text:SetPoint(anchor[1], item.icon, anchor[2], anchor[3], anchor[4])
	item.text:SetJustifyH(anchor[5])

	local expires, duration = vars.expires, vars.duration
	item.timer:SetShown(V("timer"))
	item.timer:SetText(expires and Compat.FormatTime(expires - GetTime()) or "")
	if V("sweep") and expires and duration and duration > 0 then
		if item.cooldownStart ~= expires - duration then
			item.cooldownStart = expires - duration
			item.cooldown:SetCooldown(item.cooldownStart, duration)
		end
	elseif item.cooldownStart then
		item.cooldownStart = nil
		item.cooldown:SetCooldown(0, 0)
	end

	local textW = showText and item.text:GetStringWidth() or 0
	local w, h, ix, iy = Layout.Box(size, textW, fontSize, showText, textPos)
	item.icon:ClearAllPoints()
	item.icon:SetPoint("CENTER", item, "CENTER", ix, iy)
	item:SetSize(w, h)
	item.ix, item.iy = ix, iy
	return w, h
end

-- A bar: optional square icon on one side, the fill, the text on the left and the timer on the right.
-- Its position is the center of the whole bar.
function Display:LayoutBar(item, r, V, vars)
	local width, height, side = V("barWidth"), V("barHeight"), V("iconSide")
	local fontSize = V("fontSize")
	local bar = item.bar
	useGlow(item, item.barGlow, item.barPulse)
	item.text:Hide()
	item.timer:Hide()
	if item.cooldownStart then
		item.cooldownStart = nil
		item.cooldown:SetCooldown(0, 0)
	end
	item:SetSize(width, height)
	item.ix, item.iy = 0, 0
	item.border:ClearAllPoints()
	item.border:SetPoint("TOPLEFT", item, -1, 1)
	item.border:SetPoint("BOTTOMRIGHT", item, 1, -1)

	item.icon:ClearAllPoints()
	bar:ClearAllPoints()
	if side == "NONE" then
		item.icon:Hide()
		bar:SetPoint("TOPLEFT", item, "TOPLEFT")
		bar:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT")
	else
		item.icon:Show()
		item.icon:SetSize(height, height)
		item.icon:SetPoint(side, item, side, 0, 0)
		if side == "LEFT" then
			bar:SetPoint("TOPLEFT", item.icon, "TOPRIGHT", 1, 0)
			bar:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT")
		else
			bar:SetPoint("TOPLEFT", item, "TOPLEFT")
			bar:SetPoint("BOTTOMRIGHT", item.icon, "BOTTOMLEFT", -1, 0)
		end
	end

	local texture = Data.barTextureByKey[V("barTexture")] or Data.BAR_TEXTURES[1]
	bar:SetStatusBarTexture(texture.path)
	local fill, background = V("barColor"), V("barBackground")
	bar:SetStatusBarColor(fill[1], fill[2], fill[3], 1)
	bar.background:SetColorTexture(background[1], background[2], background[3], 0.8)

	if bar.fontSize ~= fontSize then
		setFont(bar.text, fontSize)
		setFont(bar.timer, fontSize)
		bar.fontSize = fontSize
	end
	local color = V("textColor")
	bar.text:SetTextColor(color[1], color[2], color[3])
	bar.timer:SetTextColor(color[1], color[2], color[3])
	local expires = vars.expires
	local showTimer = V("timer") and expires ~= nil
	bar.timer:SetShown(showTimer)
	bar.timer:SetText(showTimer and Compat.FormatTime(expires - GetTime()) or "")
	bar.text:SetShown(V("showText"))
	bar.text:SetText(self:FormatText(r, vars))
	bar.text:ClearAllPoints()
	bar.text:SetPoint("LEFT", bar, "LEFT", 4, 0)
	bar.text:SetPoint("RIGHT", bar, "RIGHT", showTimer and -(fontSize * 3) or -4, 0)

	local reverse = V("barReverse")
	local fraction, barExpires, total = ns.Progress.Compute(r, vars, ns.Core:State(r), GetTime())
	bar.expires, bar.total, bar.reverse = barExpires, total, reverse
	bar:SetValue(barFill(fraction, reverse))
	bar:Show()
	return width, height
end

-- Plays one of Data.SoundChoices by its SOUNDKIT key.
function Display.PlaySoundKey(key)
	local kit = key and key ~= "NONE" and SOUNDKIT and SOUNDKIT[key]
	if kit then pcall(PlaySound, kit, "Master") end
end

function Display:PlaySound(r)
	Display.PlaySoundKey(r.sound)
	local st = ns.Core.state[r.id]
	if st then st.lastSound = GetTime() end
end

local WARN_FLASH_SECONDS = 2

-- A shown reminder's time left crossed one of its warning points: sound, glow, and the
-- center-screen alert when the reminder uses one.
function Display:Warn(r)
	Display.PlaySoundKey(r.warnSound)
	local item = self.items[r.id]
	if item then
		item.flashUntil = GetTime() + WARN_FLASH_SECONDS
		item.glow:Show()
		item.pulse:Play()
	end
	if r.alert then self:Alert(self:FormatText(r, nil, labelOf(r))) end
end

function Display:Alert(text)
	if RaidNotice_AddMessage and RaidWarningFrame then
		local color = ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.1 }
		pcall(RaidNotice_AddMessage, RaidWarningFrame, text, color)
	elseif UIErrorsFrame then
		UIErrorsFrame:AddMessage(text, 1, 0.3, 0.1)
	end
end

function Display:Announce(r)
	self:PlaySound(r)
	if r.alert then self:Alert(self:FormatText(r, nil, labelOf(r))) end
end

local function attach(frame, parentFrame)
	if frame.parentFrame ~= parentFrame then
		frame:SetParent(parentFrame)
		frame.parentFrame = parentFrame
	end
end

-- Anchors point of frame to relPoint of target, unless it is being dragged.
local function place(frame, point, target, relPoint, x, y)
	if Display.dragging and Display.dragging.frame == frame then return end
	local key = point .. ":" .. relPoint .. ":" .. x .. ":" .. y
	if frame.placedAt == key and frame.placedIn == target then return end
	frame:ClearAllPoints()
	frame:SetPoint(point, target, relPoint, x, y)
	frame.placedAt, frame.placedIn = key, target
end

-- Whether a reminder or anything inside a group is showing this pass.
local function hasShown(node, ctx)
	if not Tree:IsGroup(node) then return ctx.show[node.id] ~= nil end
	for _, id in ipairs(node.children) do
		local child = Tree:Get(id)
		if child and hasShown(child, ctx) then return true end
	end
	return false
end

function Display:ShowItem(r, parentFrame, ctx)
	local item = self.items[r.id] or self:CreateItem()
	self.items[r.id] = item
	ctx.used[item] = true
	item.reminder, item.nodeID = r, r.id
	attach(item, parentFrame)
	local w, h = self:LayoutItem(item, r)
	local real = ctx.active[r.id]
	item:SetAlpha(real and 1 or PREVIEW_ALPHA)
	setEditLook(item, ctx.edit, 0.3, 0.8, 0.4)
	item:EnableMouse((ctx.edit or ns.db.display.clickToDismiss) and not followsMouse(r) or false)
	item:Show()
	local flashing = item.flashUntil and item.flashUntil > GetTime()
	if not flashing then item.flashUntil = nil end
	if real and (Tree:Visual(r, "glow") or flashing) then
		if not item.pulse:IsPlaying() then
			item.glow:Show()
			item.pulse:Play()
		end
	elseif item.pulse:IsPlaying() or item.glow:IsShown() then
		item.pulse:Stop()
		item.glow:Hide()
	end
	if real then
		ctx.shown[r.id] = true
		ctx.visible[#ctx.visible + 1] = item
		if not self.shown[r.id] then self:Announce(r) end
	end
	return item, w, h
end

-- Empty groups still show in edit mode so they can be found and dragged.
local function isDrawn(node, ctx)
	return hasShown(node, ctx) or (ctx.edit and Tree:IsGroup(node) and ctx.enabled[node.id] or false)
end

-- Soonest expiry among the shown reminders at or below node, for the time left sort.
local function earliestExpires(node, ctx)
	if not Tree:IsGroup(node) then return ctx.show[node.id] and varsOf(node).expires or nil end
	local soonest
	for _, id in ipairs(node.children) do
		local child = Tree:Get(id)
		local expires = child and earliestExpires(child, ctx)
		if expires and (not soonest or expires < soonest) then soonest = expires end
	end
	return soonest
end

-- Grows bounds ({ left, bottom, right, top }, or nil when empty) to hold a w x h box centered at x, y.
local function extend(bounds, x, y, w, h)
	local left, bottom, right, top = x - w / 2, y - h / 2, x + w / 2, y + h / 2
	if not bounds then return { left, bottom, right, top } end
	bounds[1], bounds[2] = math.min(bounds[1], left), math.min(bounds[2], bottom)
	bounds[3], bounds[4] = math.max(bounds[3], right), math.max(bounds[4], top)
	return bounds
end

function Display:ShowGroupFrame(g, parentFrame, ctx, scale)
	local frame = self.groups[g.id] or self:CreateGroupFrame()
	self.groups[g.id] = frame
	ctx.used[frame] = true
	frame.nodeID = g.id
	attach(frame, parentFrame)
	frame:SetScale(scale)
	frame.label:SetText(g.name)
	frame.label:SetShown(ctx.edit)
	setEditLook(frame, ctx.edit, 0.2, 0.55, 1)
	frame:EnableMouse(ctx.edit and not followsMouse(g))
	frame:Show()
	return frame
end

-- Shows a group and everything in it. Returns its frame, the size of the box it takes up, and the
-- frame point that marks its position with that point's offset from the box center.
function Display:RenderGroup(g, parentFrame, ctx, scale)
	local frame = self:ShowGroupFrame(g, parentFrame, ctx, scale)
	if g.layout == "dynamic" then
		local anchor, w, h = self:RenderDynamic(g, frame, ctx)
		local px, py = Layout.PointOffset(anchor, w, h)
		return frame, w, h, anchor, px, py
	end
	frame:SetSize(STATIC_HANDLE, STATIC_HANDLE)
	frame.anchorPoint = "CENTER"
	local bounds = self:RenderList(g.children, frame, ctx)
	if ctx.edit or not bounds then bounds = extend(bounds, 0, 0, STATIC_HANDLE, STATIC_HANDLE) end
	local left, bottom, right, top = unpack(bounds)
	return frame, right - left, top - bottom, "CENTER", -(left + right) / 2, -(bottom + top) / 2
end

function Display:RenderDynamic(g, frame, ctx)
	local entries = {}
	for i, id in ipairs(g.children) do
		local node = Tree:Get(id)
		if node and isDrawn(node, ctx) then
			entries[#entries + 1] = { node = node, order = i, name = labelOf(node), expires = earliestExpires(node, ctx) }
		end
	end
	Layout.Sort(entries, g.sort)
	local boxes = {}
	for i, entry in ipairs(entries) do
		local w, h
		if Tree:IsGroup(entry.node) then
			entry.frame, w, h, entry.point, entry.px, entry.py = self:RenderGroup(entry.node, frame, ctx, 1)
		else
			entry.frame, w, h = self:ShowItem(entry.node, frame, ctx)
			entry.frame:SetScale(1)
			entry.point, entry.px, entry.py = "CENTER", 0, 0
		end
		boxes[i] = { w = w, h = h }
	end
	local result = Layout.Dynamic(boxes, g)
	local minSize = Tree:Visual(g, "iconSize")
	local width, height = math.max(result.width, minSize), math.max(result.height, minSize)
	frame:SetSize(width, height)
	frame.anchorPoint = result.anchor
	for i, entry in ipairs(entries) do
		local c = result.centers[i]
		entry.frame:ClearAllPoints()
		entry.frame:SetPoint(entry.point, frame, result.anchor, c[1] + entry.px, c[2] + entry.py)
		entry.frame.placedAt = nil
	end
	return result.anchor, width, height
end

-- Shows nodes at their own positions in parentFrame. Returns the bounds of what was drawn, relative
-- to the parent's center in its units, or nil when nothing was. Top-level nodes are drawn after the
-- nodes they are anchored to.
function Display:RenderList(list, parentFrame, ctx)
	local bounds
	if parentFrame == UIParent then list = Anchors.Order(list) end
	for _, id in ipairs(list) do
		local node = Tree:Get(id)
		if node and isDrawn(node, ctx) then
			local s = node.scale
			local target, relPoint = self:AnchorTarget(node, ctx)
			if Tree:IsGroup(node) then
				local frame, w, h, point, px, py = self:RenderGroup(node, parentFrame, ctx, s)
				place(frame, point, target, relPoint, node.x, node.y)
				bounds = extend(bounds, (node.x - px) * s, (node.y - py) * s, w * s, h * s)
			else
				local item, w, h = self:ShowItem(node, parentFrame, ctx)
				item:SetScale(s)
				item.anchorPoint = node.point
				place(item, node.point, target, relPoint, node.x, node.y)
				local ox, oy = Layout.PointOffset(node.point, w, h)
				bounds = extend(bounds, (node.x - ox) * s, (node.y - oy) * s, w * s, h * s)
			end
		end
	end
	return bounds
end

-- active: set of reminder IDs whose conditions (or a test) say they should show.
function Display:Update(active)
	local edit = self:IsEditMode()
	local ctx = { active = active, edit = edit, used = {}, shown = {}, visible = {}, show = {}, enabled = {} }
	Tree:Walk(function(node)
		if not ns.Core:IsOwnEnabledHere(node) then return false end
		ctx.enabled[node.id] = true
		if not Tree:IsGroup(node) and (active[node.id] or edit) then ctx.show[node.id] = true end
	end)
	for id in pairs(active) do ctx.show[id] = true end
	self:RenderList(ns.db.root, UIParent, ctx)
	for _, pool in ipairs({ self.items, self.groups }) do
		for id, frame in pairs(pool) do
			if not ctx.used[frame] then
				frame:Hide()
				if frame.pulse then frame.pulse:Stop() end
				frame.reminder = nil
				if not Tree:Get(id) then pool[id] = nil end
			end
		end
	end
	if self.cursor and not ctx.followsMouse then self.cursor:Hide() end
	self.shown, self.visible = ctx.shown, ctx.visible
	ns.Actions:Refresh(edit and {} or ctx.visible)
	ns.PositionPanel:Refresh(edit)
end
