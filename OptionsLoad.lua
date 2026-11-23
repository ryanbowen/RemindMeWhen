local _, ns = ...
local W, Compat, Load, L = ns.Widgets, ns.Compat, ns.Load, ns.L
local Options = ns.Options

local function fieldLabel(parent, text, x, y)
	local label = W.Label(parent, text, "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", x, y)
	return label
end

-- Edits node.load through a working copy so empty rules collapse back to nil.
function Options:UpdateLoad(change)
	local node = self:Current()
	if not node then return end
	local load = node.load and Compat.CopyTable(node.load) or { classes = {}, minLevel = 0, maxLevel = 0, characters = "" }
	change(load)
	node.load = Load.Normalize(load)
	self:Changed()
	self:RefreshLoadTab(node)
end

function Options:CreateLoadTab(p)
	self.loadHelp = W.Label(p, "", "GameFontDisableSmall")
	self.loadHelp:SetPoint("TOPLEFT", 4, -10)
	self.loadHelp:SetPoint("RIGHT", p, "RIGHT", -20, 0)
	self.loadHelp:SetWordWrap(true)

	fieldLabel(p, L["Classes"], 4, -44)
	local classHelp = W.Label(p, L["none checked = every class"], "GameFontDisableSmall")
	classHelp:SetPoint("TOPLEFT", 130, -44)
	self.loadClassChecks = {}
	for i, token in ipairs(Load.CLASSES) do
		local check = W.Check(p, Load.ClassName(token), function(value)
			self:UpdateLoad(function(load) load.classes[token] = value or nil end)
		end)
		local column, line = (i - 1) % 3, math.floor((i - 1) / 3)
		check:SetPoint("TOPLEFT", 10 + column * 160, -64 - line * 26)
		self.loadClassChecks[token] = check
	end

	local levelY = -64 - 3 * 26 - 14
	fieldLabel(p, L["Level"], 4, levelY - 4)
	local function levelBox(key)
		return W.EditBox(p, 40, function(text)
			self:UpdateLoad(function(load) load[key] = tonumber(text) or 0 end)
		end)
	end
	self.loadMinLevel = levelBox("minLevel")
	self.loadMinLevel:SetPoint("TOPLEFT", 136, levelY)
	local to = W.Label(p, L["to"], "GameFontHighlightSmall")
	to:SetPoint("LEFT", self.loadMinLevel, "RIGHT", 8, 0)
	self.loadMaxLevel = levelBox("maxLevel")
	self.loadMaxLevel:SetPoint("LEFT", to, "RIGHT", 12, 0)
	local levelHelp = W.Label(p, L["0 = no limit"], "GameFontDisableSmall")
	levelHelp:SetPoint("LEFT", self.loadMaxLevel, "RIGHT", 10, 0)

	local charY = levelY - 34
	fieldLabel(p, L["Characters"], 4, charY - 4)
	self.loadCharacters = W.EditBox(p, 380, function(text)
		self:UpdateLoad(function(load) load.characters = text end)
	end)
	self.loadCharacters:SetPoint("TOPLEFT", 136, charY)
	self.loadCharacters:SetHint(L["Name or Name-Realm, separated by commas (empty = all)"])
	self.loadAddMe = W.Button(p, L["Add this character"], 140, function()
		self:ClearEditFocus()
		self:UpdateLoad(function(load)
			if load.characters ~= "" then load.characters = load.characters .. ", " end
			load.characters = load.characters .. Compat.CharKey()
		end)
	end)
	self.loadAddMe:SetPoint("LEFT", self.loadCharacters, "RIGHT", 8, 0)

	self.loadStatus = W.Label(p, "", "GameFontHighlight")
	self.loadStatus:SetPoint("TOPLEFT", 4, charY - 40)
end

function Options:RefreshLoadTab(node)
	local load = node.load
	local group = ns.Tree:IsGroup(node)
	self.loadHelp:SetText(group
		and L["Only load this group and everything in it for these characters."]
		or L["Only load this reminder for these characters."])
	for token, check in pairs(self.loadClassChecks) do
		check:SetChecked(load and load.classes[token] or false)
	end
	self.loadMinLevel:SetValue(load and load.minLevel or 0)
	self.loadMaxLevel:SetValue(load and load.maxLevel or 0)
	self.loadCharacters:SetValue(load and load.characters or "")
	local loaded, reason = Load.Check(load)
	local parent = ns.Tree:ParentNode(node.id)
	local parentLoaded = true
	while parent do
		if not Load.Matches(parent.load) then parentLoaded = false end
		parent = ns.Tree:ParentNode(parent.id)
	end
	if not loaded then
		self.loadStatus:SetText("|cffff6060" .. string.format(L["Not loaded on this character (%s)."], reason) .. "|r")
	elseif not parentLoaded then
		self.loadStatus:SetText("|cffff6060" .. L["Not loaded on this character: a group it is in has load rules that exclude it."] .. "|r")
	else
		self.loadStatus:SetText("|cff60ff60" .. L["Loaded on this character."] .. "|r")
	end
end
