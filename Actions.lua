local _, ns = ...
local Compat, Resolver, L = ns.Compat, ns.Resolver, ns.L

-- Click actions use secure buttons laid over the reminder icons. Secure frames cannot be
-- changed in combat, so the buttons hide in combat and are re-placed once it ends.
local Actions = { buttons = {} }
ns.Actions = Actions

Actions.KINDS = {
	{ value = "none", label = L["Nothing"] },
	{ value = "spell", label = L["Cast a spell"] },
	{ value = "item", label = L["Use an item"] },
	{ value = "weapon", label = L["Apply an item to a weapon"] },
	{ value = "mount", label = L["Summon a mount"] },
	{ value = "macro", label = L["Run macro text"] },
}
Actions.KIND_SET = {}
for _, kind in ipairs(Actions.KINDS) do Actions.KIND_SET[kind.value] = true end

function Actions:Normalize(r)
	local a = type(r.action) == "table" and r.action or {}
	r.action = a
	if not self.KIND_SET[a.kind] then a.kind = "none" end
	a.spell = type(a.spell) == "string" and a.spell or ""
	a.item = type(a.item) == "string" and a.item or ""
	a.macro = type(a.macro) == "string" and a.macro or ""
	a.slot = a.slot == 17 and 17 or 16
end

-- First spell of the list that you know, otherwise the first one that resolves.
local function pickSpell(text)
	local fallback
	for _, token in ipairs(Compat.SplitList(text)) do
		local result = ns.Spells:Resolve(token)
		if result.status == Resolver.OK then
			if result.known then return result end
			fallback = fallback or result
		end
	end
	return fallback
end

local function pickItem(a)
	return ns.Items:FirstOwned(a.item, a.kind == "weapon" and a.slot or nil)
end

local function itemName(id)
	return Compat.GetItemInfo(id) or ("item:" .. id)
end

-- Returns the macro text for the reminder's action, or nil when there is nothing to do.
function Actions:MacroFor(r)
	local a = r.action
	if not a or a.kind == "none" then return nil end
	if a.kind == "spell" then
		local spell = pickSpell(a.spell)
		return spell and ("/cast " .. spell.name)
	elseif a.kind == "item" then
		local id = pickItem(a)
		return id and ("/use item:" .. id)
	elseif a.kind == "weapon" then
		local id = pickItem(a)
		return id and ("/use item:" .. id .. "\n/use " .. a.slot)
	elseif a.kind == "mount" then
		local spell = a.spell ~= "" and pickSpell(a.spell)
		if spell then return "/cast " .. spell.name end
		return "/run RemindMeWhen_SummonMount()"
	elseif a.kind == "macro" then
		return a.macro ~= "" and a.macro or nil
	end
	return nil
end

function Actions:Describe(r)
	local a = r.action
	if not a or a.kind == "none" then return nil end
	if a.kind == "spell" then
		local spell = pickSpell(a.spell)
		return spell and string.format(L["cast %s"], spell.name)
	elseif a.kind == "item" then
		local id = pickItem(a)
		return id and string.format(L["use %s"], itemName(id))
	elseif a.kind == "weapon" then
		local id = pickItem(a)
		local slot = a.slot == 17 and L["off hand"] or L["main hand"]
		return id and string.format(L["apply %s to your %s"], itemName(id), slot)
	elseif a.kind == "mount" then
		local spell = a.spell ~= "" and pickSpell(a.spell)
		return spell and string.format(L["summon %s"], spell.name) or L["summon a random favorite mount"]
	elseif a.kind == "macro" then
		return a.macro ~= "" and L["run your macro"] or nil
	end
	return nil
end

function Actions:GetIcon(r)
	local a = r.action
	if not a then return nil end
	if a.kind == "spell" or (a.kind == "mount" and a.spell ~= "") then
		local spell = pickSpell(a.spell)
		return spell and spell.icon
	elseif a.kind == "item" or a.kind == "weapon" then
		local id = pickItem(a)
		return id and Compat.GetItemIcon(id)
	elseif a.kind == "mount" then
		return ns.Data.MOUNT_ICON
	end
	return nil
end

function RemindMeWhen_SummonMount()
	if not (C_MountJournal and C_MountJournal.SummonByID) then return end
	local favorites, usable = {}, {}
	for _, id in ipairs(ns.Conditions.CollectedMounts()) do
		local _, _, _, _, isUsable, _, isFavorite = C_MountJournal.GetMountInfoByID(id)
		if isUsable then
			usable[#usable + 1] = id
			if isFavorite then favorites[#favorites + 1] = id end
		end
	end
	local pool = #favorites > 0 and favorites or usable
	if #pool > 0 then C_MountJournal.SummonByID(pool[math.random(#pool)]) end
end

local function useKeyDownCVar()
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	return get and get("ActionButtonUseKeyDown") ~= nil
end

function Actions:Create()
	if self.root then return end
	local root = CreateFrame("Frame", "RemindMeWhenActions", UIParent, "SecureHandlerStateTemplate")
	root:SetAllPoints(UIParent)
	if RegisterStateDriver then RegisterStateDriver(root, "visibility", "[combat] hide; show") end
	self.root = root
end

function Actions:Button(i)
	local button = self.buttons[i]
	if button then return button end
	button = CreateFrame("Button", "RemindMeWhenActionButton" .. i, self.root, "SecureActionButtonTemplate")
	if useKeyDownCVar() then button:RegisterForClicks("AnyUp", "AnyDown") else button:RegisterForClicks("AnyUp") end
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(50)
	button:SetAttribute("type1", "macro")
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.12)
	button:HookScript("OnClick", function(frame, mouse, down)
		if mouse == "RightButton" and not down then ns.Display:OpenSnoozeMenu(frame, frame.reminder) end
	end)
	button:SetScript("OnEnter", function(frame)
		if frame.reminder then ns.Display:ShowTooltip(frame, frame.reminder) end
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.buttons[i] = button
	return button
end

-- Places a button over each visible reminder that has an action. Only runs out of combat.
function Actions:Refresh(items)
	self.items = items or self.items or {}
	if not self.root then return end
	if InCombatLockdown() then
		self.pending = true
		return
	end
	self.pending = nil
	local used = 0
	local uiScale = UIParent:GetEffectiveScale()
	for _, item in ipairs(self.items) do
		local r = item.reminder
		local macro = r and item:IsShown() and self:MacroFor(r)
		local left, bottom, width, height = item:GetRect()
		if macro and left then
			used = used + 1
			local button = self:Button(used)
			button.reminder = r
			if button.macro ~= macro then
				button:SetAttribute("macrotext1", macro)
				button.macro = macro
			end
			local scale = item:GetEffectiveScale() / uiScale
			button:ClearAllPoints()
			button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
			button:SetSize(width * scale, height * scale)
			button:Show()
		end
	end
	for i = used + 1, #self.buttons do
		local button = self.buttons[i]
		button.reminder = nil
		button:Hide()
	end
end

function Actions:OnCombatEnded()
	if self.pending then self:Refresh() end
end
