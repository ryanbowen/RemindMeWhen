local _, ns = ...
local Compat, Data, Tracker, Conditions, L = ns.Compat, ns.Data, ns.Tracker, ns.Conditions, ns.L

local MAIN_HAND, OFF_HAND = 16, 17
local flag, SetVar = Compat.Flag, Conditions.SetVar
local BAG_COUNT = NUM_BAG_SLOTS or 4
local MAX_NAMES = 5

-- {count} and the value a progress bar fills toward come from the same condition.
local function setCount(vars, count, maximum)
	if vars and vars.count == nil and count ~= nil then
		vars.count, vars.max = count, maximum
	end
end

local function threshold(c)
	local value = tonumber(c.value)
	return value and value > 0 and value or nil
end

local SLOT_CHOICES = { { value = MAIN_HAND, label = L["Main hand"] }, { value = OFF_HAND, label = L["Off hand"] } }
local OP_CHOICES = {
	{ value = "<", label = "<" }, { value = "<=", label = "<=" }, { value = "=", label = "=" },
	{ value = ">=", label = ">=" }, { value = ">", label = ">" },
}
local UNIT_CHOICES = { { value = "player", label = L["Player"] }, { value = "pet", label = L["Pet"] }, { value = "target", label = L["Target"] } }
local FILTER_CHOICES = { { value = "HELPFUL", label = L["Buff"] }, { value = "HARMFUL", label = L["Debuff"] } }
local ENCHANT_CHOICES = {
	{ value = "any", label = L["Any"] },
	{ value = "poison", label = L["Rogue poison"] },
	{ value = "imbue", label = L["Shaman imbue"] },
	{ value = "ids", label = L["Enchant IDs"] },
}
local GROUP_CHOICES = { { value = "group", label = L["Any group"] }, { value = "party", label = L["Party"] }, { value = "raid", label = L["Raid"] } }
local INSTANCE_CHOICES = {
	{ value = "any", label = L["Any"] }, { value = "party", label = L["Dungeon"] },
	{ value = "raid", label = L["Raid"] }, { value = "pvp", label = L["PvP"] },
}
local TARGET_CHOICES = {
	{ value = "any", label = L["Any"] }, { value = "enemy", label = L["Attackable"] }, { value = "friend", label = L["Not attackable"] },
	{ value = "hostile", label = L["Hostile (red)"] }, { value = "neutral", label = L["Neutral (yellow)"] },
	{ value = "friendly", label = L["Friendly (green)"] }, { value = "player", label = L["A player"] }, { value = "npc", label = L["An NPC"] },
}
local REACTION_KINDS = { hostile = true, neutral = true, friendly = true }
local TARGET_CLASS_CHOICES = {
	{ value = "elite", label = L["Elite or boss"] }, { value = "rare", label = L["Rare"] },
	{ value = "boss", label = L["Boss"] }, { value = "normal", label = L["Normal"] },
}
local POWER_CHOICES = {
	{ value = "health", label = L["Health"] }, { value = "mana", label = L["Mana"] }, { value = "rage", label = L["Rage"] },
	{ value = "energy", label = L["Energy"] }, { value = "focus", label = L["Focus"] },
}
local HAPPINESS_CHOICES = { { value = 2, label = L["Content or unhappy"] }, { value = 1, label = L["Unhappy"] } }
local MERCHANT_CHOICES = { { value = "any", label = L["Any vendor"] }, { value = "repair", label = L["Can repair"] } }
local SCOPE_CHOICES = { { value = "all", label = L["Everyone"] }, { value = "others", label = L["Others only"] } }
local POWER_TYPES = { mana = 0, rage = 1, focus = 2, energy = 3 }
local DEFAULT_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local classChoices
local function getClassChoices()
	if classChoices then return classChoices end
	classChoices = {}
	for _, token in ipairs(CLASS_SORT_ORDER or DEFAULT_CLASSES) do
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] or token
		classChoices[#classChoices + 1] = { value = token, label = name }
	end
	return classChoices
end

local function define(key, def)
	Conditions:Define(key, def)
end

local function slotParam()
	return { key = "slot", kind = "choice", label = L["Weapon slot"], default = MAIN_HAND, width = 90, choices = SLOT_CHOICES }
end

local function spellsParam(width, help)
	return {
		key = "spells", kind = "text", resolver = "Spells", label = L["Spells"], hint = L["name or ID, ..."], default = "", width = width or 150,
		help = (help or L["Spell names or spell IDs, separated by commas."]) .. "\n\n"
			.. L["Entries are saved as Name (ID) when you leave the box. Hover the icon on the right to see what each one matched, or use + to pick a spell."],
	}
end

local function minLeftParam()
	return {
		key = "minLeft", kind = "number", label = L["Min. seconds left"], hint = L["secs"], default = 0, width = 40,
		help = L["Only counts while more than this many seconds remain, so the reminder can show before it runs out. 0 = any time left."],
	}
end

local function opParam(default)
	return { key = "op", kind = "choice", label = L["Comparison"], default = default or ">=", width = 50, choices = OP_CHOICES }
end

local function numberParam(key, label, default, width)
	return { key = key, kind = "number", label = label, default = default, width = width or 50 }
end

local function compare(value, c)
	return Compat.Compare(value, c.op, tonumber(c.value) or 0)
end

local function spellSet(text)
	local set = Tracker:GetSpellSet(text)
	Tracker:Resolve(set)
	return set
end

local function spellIcon(text)
	local first = Compat.SplitList(text)[1]
	if not first then return nil end
	return ns.Spells:Resolve(first).icon
end

local idSets = {}
local function idSet(text)
	local set = idSets[text]
	if set then return set end
	set = {}
	for _, token in ipairs(Compat.SplitList(text)) do
		local id = tonumber(token)
		if id then set[id] = true end
	end
	idSets[text] = set
	return set
end

local function knownSpellID(set)
	local found
	Tracker:ForEachID(set, function(id)
		if not found and ns.Spells.IsKnown(id) then found = id end
	end)
	return found
end

local function joinNames(names)
	if #names <= MAX_NAMES then return table.concat(names, ", ") end
	local shown = {}
	for i = 1, MAX_NAMES do shown[i] = names[i] end
	return table.concat(shown, ", ") .. string.format(" +%d", #names - MAX_NAMES)
end

local mountCache, mountCacheTime = nil, 0
local function collectedMounts()
	local now = GetTime()
	if mountCache and (#mountCache > 0 or now - mountCacheTime < 5) then return mountCache end
	mountCache, mountCacheTime = {}, now
	if not (C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID) then return mountCache end
	local ok, ids = pcall(C_MountJournal.GetMountIDs)
	if not ok or type(ids) ~= "table" then return mountCache end
	for _, id in ipairs(ids) do
		local _, _, _, _, _, _, _, _, _, hideOnChar, collected = C_MountJournal.GetMountInfoByID(id)
		if collected and not hideOnChar then mountCache[#mountCache + 1] = id end
	end
	return mountCache
end
Conditions.CollectedMounts = collectedMounts

function Conditions:InvalidateMounts()
	mountCache = nil
end

local function trackingActive(set)
	local M = C_Minimap
	if M and M.GetNumTrackingTypes and M.GetTrackingInfo then
		local okCount, count = pcall(M.GetNumTrackingTypes)
		count = okCount and tonumber(Compat.Plain(count)) or 0
		for i = 1, count do
			local ok, a, _, c = pcall(M.GetTrackingInfo, i)
			if ok then
				local name, active, spellID
				if type(a) == "table" then name, active, spellID = a.name, a.active, a.spellID else name, active = a, c end
				if not Compat.IsSecret(name, active, spellID) and Tracker:Matches(set, spellID, name) and active then
					return true
				end
			end
		end
		return false
	end
	if GetTrackingTexture then
		local texture = Compat.Plain(GetTrackingTexture())
		if not texture then return false end
		local hit = false
		Tracker:ForEachID(set, function(id)
			local _, _, icon = Compat.GetSpellInfo(id)
			if icon == texture then hit = true end
		end)
		return hit
	end
	return nil
end

local ammoSlotID
local function ammoSlot()
	if ammoSlotID then return ammoSlotID end
	ammoSlotID = 0
	if GetInventorySlotInfo then
		local ok, slot = pcall(GetInventorySlotInfo, "AmmoSlot")
		if ok and tonumber(slot) then ammoSlotID = tonumber(slot) end
	end
	return ammoSlotID
end

local function freeBagSlots()
	local fn = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	if not fn then return nil end
	local free = 0
	for bag = 0, BAG_COUNT do
		local ok, count, bagType = pcall(fn, bag)
		if not ok or Compat.IsSecret(count, bagType) then return nil end
		if bagType == nil or bagType == 0 then free = free + (tonumber(count) or 0) end
	end
	return free
end

local function memberAvailable(unit)
	local exists, connected, dead, visible = UnitExists(unit), UnitIsConnected(unit), UnitIsDeadOrGhost(unit), UnitIsVisible(unit)
	if Compat.IsSecret(exists, connected, dead, visible) then return false end
	return exists and connected and not dead and visible
end

define("combat", {
	label = L["In combat"],
	eval = function() return Compat.InCombat() end,
})

define("mounted", {
	label = L["Mounted"],
	icon = function() return Data.MOUNT_ICON end,
	eval = function() return flag(IsMounted()) end,
})

define("mountUsable", {
	label = L["A mount can be used here"],
	icon = function() return Data.MOUNT_ICON end,
	eval = function()
		if IsIndoors and Compat.Plain(IsIndoors()) then return false end
		if not (C_MountJournal and C_MountJournal.GetMountInfoByID) then return false end
		for _, id in ipairs(collectedMounts()) do
			local _, _, _, _, usable = C_MountJournal.GetMountInfoByID(id)
			if Compat.Plain(usable) then return true end
		end
		return false
	end,
})

define("moving", {
	label = L["Moving"],
	eval = function()
		if IsPlayerMoving then
			local moving = IsPlayerMoving()
			if not Compat.IsSecret(moving) then return moving and true or false end
		end
		local speed = GetUnitSpeed and GetUnitSpeed("player")
		if Compat.IsSecret(speed) then return nil end
		return (tonumber(speed) or 0) > 0
	end,
})

define("resting", {
	label = L["In a rested area (inn or city)"],
	eval = function() return flag(IsResting()) end,
})

define("restedXP", {
	measures = "value",
	label = L["Rested XP (percent of level)"],
	icon = function() return "Interface\\Icons\\Spell_Nature_Sleep" end,
	params = { opParam(">"), numberParam("value", L["Percent"], 0, 40) },
	eval = function(c, vars)
		local rested = GetXPExhaustion and Compat.Plain(GetXPExhaustion()) or 0
		local maximum = Compat.Plain(UnitXPMax("player"))
		if maximum == nil then return nil end
		if maximum <= 0 then return false end
		local percent = (tonumber(rested) or 0) / maximum * 100
		setCount(vars, math.floor(percent + 0.5), 100)
		return compare(percent, c)
	end,
})

define("indoors", {
	label = L["Indoors"],
	eval = function()
		if not IsIndoors then return false end
		return flag(IsIndoors())
	end,
})

define("swimming", {
	label = L["Swimming"],
	eval = function()
		if not IsSwimming then return false end
		return flag(IsSwimming())
	end,
})

define("stealthed", {
	label = L["Stealthed"],
	eval = function()
		if not IsStealthed then return false end
		return flag(IsStealthed())
	end,
})

define("dead", {
	label = L["Dead or ghost"],
	eval = function() return flag(UnitIsDeadOrGhost("player")) end,
})

define("taxi", {
	label = L["On a flight path"],
	eval = function() return flag(UnitOnTaxi("player")) end,
})

define("class", {
	label = L["Class is"],
	params = { { key = "class", kind = "choice", label = L["Class"], default = "WARRIOR", width = 110, choices = getClassChoices } },
	eval = function(c)
		local _, token = UnitClass("player")
		return token == c.class
	end,
})

define("level", {
	label = L["Character level"],
	params = { opParam(">="), numberParam("value", L["Level"], 60, 40) },
	eval = function(c)
		local level = Compat.Plain(UnitLevel("player"))
		if not level then return nil end
		return compare(level, c)
	end,
})

define("group", {
	label = L["In a party or raid"],
	params = { { key = "kind", kind = "choice", label = L["Group type"], default = "group", width = 100, choices = GROUP_CHOICES } },
	eval = function(c)
		local raid = IsInRaid and IsInRaid() or false
		local group = IsInGroup and IsInGroup() or raid
		if c.kind == "raid" then return raid end
		if c.kind == "party" then return group and not raid end
		return group
	end,
})

define("instance", {
	label = L["In an instance"],
	params = {
		{ key = "kind", kind = "choice", label = L["Instance type"], default = "any", width = 90, choices = INSTANCE_CHOICES },
		{
			key = "names", kind = "text", resolver = "Instances", label = L["Instances"], hint = L["any, or names and IDs"], default = "", width = 150,
			help = L["Optional. Instance names (or part of a name) or IDs, comma separated. Use + inside an instance to add it. Empty = any instance of the chosen type."],
		},
	},
	eval = function(c)
		local inInstance, kind = IsInInstance()
		if Compat.IsSecret(inInstance, kind) then return nil end
		if not inInstance then return false end
		if c.kind == "pvp" and not (kind == "pvp" or kind == "arena") then return false end
		if c.kind ~= "any" and c.kind ~= "pvp" and kind ~= c.kind then return false end
		if #Compat.SplitList(c.names) == 0 then return true end
		return ns.Instances.Matches(c.names)
	end,
})

define("zone", {
	label = L["Zone or subzone"],
	params = {
		{
			key = "zones", kind = "text", label = L["Zones"], hint = L["zone, subzone, ..."], default = "", width = 200,
			help = L["Matches when the zone or subzone name contains any of these words (comma separated). A number matches the current map ID (shown by /rmw debug)."],
		},
	},
	eval = function(c)
		local tokens = Compat.SplitList(c.zones)
		if #tokens == 0 then return false end
		local mapID = Compat.MapID()
		for _, token in ipairs(tokens) do
			if mapID and tonumber(token) == mapID then return true end
		end
		local texts = {
			GetRealZoneText and GetRealZoneText() or "",
			GetZoneText and GetZoneText() or "",
			GetSubZoneText and GetSubZoneText() or "",
			GetMinimapZoneText and GetMinimapZoneText() or "",
		}
		for i = 1, #texts do
			local text = Compat.Plain(texts[i])
			if type(text) == "string" and text ~= "" then
				text = text:lower()
				for _, token in ipairs(tokens) do
					if text:find(token:lower(), 1, true) then return true end
				end
			end
		end
		return false
	end,
})

define("target", {
	label = L["Have a target"],
	params = { { key = "kind", kind = "choice", label = L["Target type"], default = "any", width = 100, choices = TARGET_CHOICES } },
	eval = function(c)
		local exists = UnitExists("target")
		if Compat.IsSecret(exists) then return nil end
		if not exists then return false end
		if c.kind == "any" then return true end
		if REACTION_KINDS[c.kind] then
			local reaction = UnitReaction("player", "target")
			if Compat.IsSecret(reaction) then return nil end
			reaction = tonumber(reaction)
			if not reaction then return false end
			if c.kind == "hostile" then return reaction <= 3 end
			if c.kind == "neutral" then return reaction == 4 end
			return reaction >= 5
		end
		if c.kind == "player" or c.kind == "npc" then
			local isPlayer = UnitIsPlayer("target")
			if Compat.IsSecret(isPlayer) then return nil end
			return (isPlayer and true or false) == (c.kind == "player")
		end
		local canAttack = UnitCanAttack("player", "target")
		if Compat.IsSecret(canAttack) then return nil end
		if c.kind == "enemy" then return canAttack and true or false end
		return not canAttack
	end,
})

define("targetClass", {
	label = L["Target is elite, rare or boss"],
	params = { { key = "kind", kind = "choice", label = L["Target type"], default = "elite", width = 110, choices = TARGET_CLASS_CHOICES } },
	eval = function(c)
		local exists = UnitExists("target")
		if Compat.IsSecret(exists) then return nil end
		if not exists then return false end
		local class, level = UnitClassification("target"), UnitLevel("target")
		if Compat.IsSecret(class, level) then return nil end
		local boss = class == "worldboss" or level == -1
		if c.kind == "boss" then return boss end
		if c.kind == "elite" then return boss or class == "elite" or class == "rareelite" end
		if c.kind == "rare" then return class == "rare" or class == "rareelite" end
		return not boss and (class == "normal" or class == "trivial" or class == "minus")
	end,
})

define("pet", {
	label = L["Have an active pet"],
	icon = function() return Data.PET_ICON end,
	eval = function()
		local exists = UnitExists("pet")
		if Compat.IsSecret(exists) then return nil end
		if not exists then return false end
		local dead = UnitIsDeadOrGhost("pet")
		if Compat.IsSecret(dead) then return true end
		return not dead
	end,
})

define("petDead", {
	label = L["Pet is dead"],
	icon = function() return Data.PET_ICON end,
	params = {},
	eval = function()
		Tracker:UpdatePet()
		return Tracker.petDead and true or false
	end,
})

define("petHappiness", {
	label = L["Pet is not happy (hunter)"],
	icon = function() return Data.PET_ICON end,
	params = { { key = "level", kind = "choice", label = L["Mood"], default = 2, width = 130, choices = HAPPINESS_CHOICES } },
	eval = function(c)
		if not GetPetHappiness then return false end
		local happiness = Compat.Plain(GetPetHappiness())
		if not happiness then return false end
		return happiness <= (tonumber(c.level) or 2)
	end,
})

define("aura", {
	measures = "time",
	label = L["Has aura (buff or debuff)"],
	params = {
		{ key = "unit", kind = "choice", label = L["Unit"], default = "player", width = 70, choices = UNIT_CHOICES },
		{ key = "filter", kind = "choice", label = L["Aura type"], default = "HELPFUL", width = 70, choices = FILTER_CHOICES },
		spellsParam(150),
		minLeftParam(),
	},
	icon = function(c) return spellIcon(c.spells) end,
	eval = function(c, vars)
		local set = spellSet(c.spells)
		if #set.tokens == 0 then return false end
		local present, left, expires, duration = Tracker:FindAura(c.unit, c.filter, set)
		if present then
			SetVar(vars, "expires", expires)
			SetVar(vars, "duration", duration)
		end
		local minLeft = tonumber(c.minLeft) or 0
		if present and minLeft > 0 and left and left < minLeft then return false end
		return present
	end,
})

define("groupBuffMissing", {
	label = L["Group member is missing a buff"],
	params = {
		spellsParam(150, L["Buff names or IDs. A member counts as buffed when they have any of them. Members out of sight, offline or dead are skipped."]),
		{ key = "scope", kind = "choice", label = L["Who"], default = "all", width = 100, choices = SCOPE_CHOICES },
	},
	icon = function(c) return spellIcon(c.spells) end,
	eval = function(c, vars)
		local set = spellSet(c.spells)
		if #set.tokens == 0 then return false end
		local missing, unknown = {}, false
		for _, unit in ipairs(Tracker:GroupUnits()) do
			local isSelf = Compat.Plain(UnitIsUnit(unit, "player"))
			if not (c.scope == "others" and isSelf) and memberAvailable(unit) then
				local has = Tracker:UnitHasAura(unit, "HELPFUL", set)
				if has == nil then
					unknown = true
				elseif not has then
					missing[#missing + 1] = Compat.Plain(UnitName(unit)) or unit
				end
			end
		end
		if #missing > 0 then
			SetVar(vars, "missing", joinNames(missing))
			return true
		end
		if unknown then return nil end
		return false
	end,
})

define("form", {
	label = L["In shapeshift form or stance"],
	params = { spellsParam(150, L["Form or stance names or spell IDs. Leave empty to match any form."]) },
	icon = function(c) return spellIcon(c.spells) end,
	eval = function(c)
		local set = spellSet(c.spells)
		local count = GetNumShapeshiftForms and Compat.Plain(GetNumShapeshiftForms()) or 0
		for i = 1, count do
			local _, active, _, spellID = GetShapeshiftFormInfo(i)
			if Compat.IsSecret(active, spellID) then return nil end
			if active then
				if #set.tokens == 0 then return true end
				local name = not Compat.InCombat() and spellID and Compat.GetSpellInfo(spellID) or nil
				return Tracker:Matches(set, spellID, name)
			end
		end
		return false
	end,
})

define("weaponEquipped", {
	label = L["Weapon equipped"],
	params = { slotParam() },
	icon = function(c) return GetInventoryItemTexture("player", c.slot) end,
	eval = function(c)
		local itemID = GetInventoryItemID("player", c.slot)
		if Compat.IsSecret(itemID) then return nil end
		if not itemID then return false end
		local _, classID = Compat.GetItemInstant(itemID)
		if classID == nil then return true end
		return classID == (Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2)
	end,
})

define("weaponEnchant", {
	measures = "time",
	label = L["Weapon has temporary enchant"],
	params = {
		slotParam(),
		{ key = "kind", kind = "choice", label = L["Enchant type"], default = "any", width = 100, choices = ENCHANT_CHOICES },
		{
			key = "ids", kind = "text", label = L["Enchant IDs"], hint = L["enchant IDs"], default = "", width = 90,
			shownIf = function(c) return c.kind == "ids" end,
			help = L["Only used when the enchant type is 'Enchant IDs'. Type /rmw debug to list the enchant IDs on your weapons."],
		},
		minLeftParam(),
	},
	icon = function(c)
		if c.kind == "poison" then return Data.POISON_ICON end
		return GetInventoryItemTexture("player", c.slot)
	end,
	eval = function(c, vars)
		local enchants = Tracker:GetWeaponEnchants(c.slot)
		if not enchants then return nil end
		local minLeft, now = tonumber(c.minLeft) or 0, GetTime()
		local ids = c.kind == "ids" and idSet(c.ids) or nil
		for _, enchant in ipairs(enchants) do
			local id = enchant.id
			local match = c.kind == "any"
				or (c.kind == "poison" and id and Data.poisonEnchants[id])
				or (c.kind == "imbue" and id and Data.imbueEnchants[id])
				or (ids and id and ids[id])
			if match then
				SetVar(vars, "expires", enchant.expires)
				if minLeft <= 0 or not enchant.expires or enchant.expires - now >= minLeft then return true end
			end
		end
		return false
	end,
})

define("tracking", {
	label = L["Minimap tracking active"],
	params = { spellsParam(150, L["Tracking spell names or IDs, for example Find Herbs (2383) or Find Minerals (2580)."]) },
	icon = function(c) return spellIcon(c.spells) end,
	eval = function(c)
		local set = spellSet(c.spells)
		if #set.tokens == 0 then return false end
		return trackingActive(set)
	end,
})

define("spellKnown", {
	label = L["Knows spell"],
	params = { spellsParam(150, L["Spell names or IDs. True when you know any of them."]) },
	icon = function(c) return spellIcon(c.spells) end,
	eval = function(c)
		local set = spellSet(c.spells)
		if #set.tokens == 0 then return false end
		return knownSpellID(set) ~= nil
	end,
})

define("spellReady", {
	label = L["Spell is off cooldown"],
	params = { spellsParam(150, L["Spell name or ID. The global cooldown is ignored."]) },
	icon = function(c) return spellIcon(c.spells) end,
	eval = function(c)
		local set = spellSet(c.spells)
		local id = knownSpellID(set)
		if not id then return false end
		local start, duration
		if C_Spell and C_Spell.GetSpellCooldown then
			local ok, info = pcall(C_Spell.GetSpellCooldown, id)
			if not ok or Compat.IsSecret(info) then return nil end
			if type(info) ~= "table" then return true end
			start, duration = info.startTime, info.duration
		elseif GetSpellCooldown then
			local ok, s, d = pcall(GetSpellCooldown, id)
			if not ok then return nil end
			start, duration = s, d
		else
			return nil
		end
		if Compat.IsSecret(start, duration) then return nil end
		start, duration = tonumber(start) or 0, tonumber(duration) or 0
		if duration <= 1.5 then return true end
		return start + duration <= GetTime()
	end,
})

define("itemCount", {
	measures = "value",
	label = L["Item count in bags"],
	params = {
		{
			key = "item", kind = "text", resolver = "Items", label = L["Items"], hint = L["name or ID, ..."], default = "", width = 140,
			help = L["Item names or IDs, separated by commas. Their counts are added up, so all ranks of a poison or several reagents count together."],
		},
		opParam("<"),
		numberParam("value", L["Count"], 1, 50),
	},
	icon = function(c)
		local first = Compat.SplitList(c.item)[1]
		return first and ns.Items:Resolve(first).icon
	end,
	eval = function(c, vars)
		local tokens = Compat.SplitList(c.item)
		if #tokens == 0 then return false end
		local total = 0
		for _, token in ipairs(tokens) do
			local id, name = ns.Resolver.ParseToken(token)
			local count = Compat.GetItemCount(id or name)
			if count == nil then return nil end
			total = total + count
		end
		setCount(vars, total, threshold(c))
		return compare(total, c)
	end,
})

define("ammo", {
	measures = "value",
	label = L["Ammo count (hunter)"],
	params = { opParam("<"), numberParam("value", L["Count"], 200, 50) },
	icon = function() return GetInventoryItemTexture("player", ammoSlot()) or Data.AMMO_ICON end,
	eval = function(c, vars)
		local slot = ammoSlot()
		local itemID = GetInventoryItemID("player", slot)
		if Compat.IsSecret(itemID) then return nil end
		local count = 0
		if itemID then
			count = Compat.Plain(GetInventoryItemCount("player", slot))
			if count == nil then return nil end
		end
		setCount(vars, count, threshold(c))
		return compare(count, c)
	end,
})

define("durability", {
	measures = "value",
	label = L["Lowest equipment durability (percent)"],
	icon = function() return Data.REPAIR_ICON end,
	params = { opParam("<"), numberParam("value", L["Percent"], 30, 40) },
	eval = function(c, vars)
		if not GetInventoryItemDurability then return false end
		local lowest
		for slot = 1, 19 do
			local current, maximum = GetInventoryItemDurability(slot)
			if Compat.IsSecret(current, maximum) then return nil end
			if current and maximum and maximum > 0 then
				local percent = current / maximum * 100
				if not lowest or percent < lowest then lowest = percent end
			end
		end
		lowest = lowest or 100
		setCount(vars, math.floor(lowest + 0.5), 100)
		return compare(lowest, c)
	end,
})

define("bagSlots", {
	measures = "value",
	label = L["Free bag slots"],
	icon = function() return Data.BAG_ICON end,
	params = { opParam("<"), numberParam("value", L["Slots"], 3, 40) },
	eval = function(c, vars)
		local free = freeBagSlots()
		if free == nil then return nil end
		setCount(vars, free, threshold(c))
		return compare(free, c)
	end,
})

define("power", {
	measures = "value",
	label = L["Health or power percent"],
	params = {
		{ key = "kind", kind = "choice", label = L["Resource"], default = "health", width = 80, choices = POWER_CHOICES },
		opParam("<"),
		numberParam("value", L["Percent"], 50, 40),
	},
	eval = function(c, vars)
		local current, maximum
		if c.kind == "health" then
			current, maximum = UnitHealth("player"), UnitHealthMax("player")
		else
			local powerType = POWER_TYPES[c.kind] or 0
			current, maximum = UnitPower("player", powerType), UnitPowerMax("player", powerType)
		end
		if Compat.IsSecret(current, maximum) then return nil end
		current, maximum = tonumber(current) or 0, tonumber(maximum) or 0
		if maximum <= 0 then return false end
		local percent = current / maximum * 100
		setCount(vars, math.floor(percent + 0.5), 100)
		return compare(percent, c)
	end,
})

define("atMerchant", {
	label = L["At a vendor"],
	icon = function() return Data.VENDOR_ICON end,
	params = { { key = "kind", kind = "choice", label = L["Vendor"], default = "any", width = 100, choices = MERCHANT_CHOICES } },
	eval = function(c)
		if not Tracker.windows.merchant then return false end
		if c.kind == "repair" then return CanMerchantRepair and flag(CanMerchantRepair()) or false end
		return true
	end,
})

define("atMailbox", {
	label = L["At a mailbox"],
	icon = function() return Data.MAIL_ICON end,
	eval = function() return Tracker.windows.mail and true or false end,
})

local RACE_CHOICES = {
	{ value = "Human", label = L["Human"] }, { value = "Dwarf", label = L["Dwarf"] },
	{ value = "NightElf", label = L["Night Elf"] }, { value = "Gnome", label = L["Gnome"] },
	{ value = "Orc", label = L["Orc"] }, { value = "Scourge", label = L["Undead"] },
	{ value = "Tauren", label = L["Tauren"] }, { value = "Troll", label = L["Troll"] },
}
local FACTION_CHOICES = { { value = "Alliance", label = L["Alliance"] }, { value = "Horde", label = L["Horde"] } }
local TOTEM_CHOICES = {
	{ value = 0, label = L["Any element"] }, { value = 1, label = L["Fire"] }, { value = 2, label = L["Earth"] },
	{ value = 3, label = L["Water"] }, { value = 4, label = L["Air"] },
}
local LEADER_CHOICES = { { value = "leader", label = L["Leader"] }, { value = "assist", label = L["Leader or assistant"] } }
local CAST_CHOICES = { { value = "any", label = L["Casting or channeling"] }, { value = "cast", label = L["Casting"] }, { value = "channel", label = L["Channeling"] } }
local STATUS_CHOICES = { { value = "pvp", label = L["PvP flagged"] }, { value = "afk", label = L["AFK"] }, { value = "dnd", label = L["Do not disturb"] } }
local MAX_TOTEMS = MAX_TOTEMS or 4
local COPPER_PER_GOLD = 10000

local function textParam(key, label, hint, width, help)
	return { key = key, kind = "text", label = label, hint = hint, default = "", width = width, help = help }
end

-- Whether name contains any of the comma separated words, or id equals one of the numbers.
local function matchesList(text, name, id)
	for _, token in ipairs(Compat.SplitList(text)) do
		local number = tonumber(token)
		if number then
			if id and number == id then return true end
		elseif type(name) == "string" and name:lower():find(token:lower(), 1, true) then
			return true
		end
	end
	return false
end

local function talentChoices()
	local out = {}
	for tab, info in ipairs(Compat.TalentTabs()) do out[tab] = { label = info.name, children = {} } end
	Compat.ForEachTalent(function(tab, name)
		local tree = out[tab]
		if tree then tree.children[#tree.children + 1] = { value = name, label = name } end
	end)
	for i = #out, 1, -1 do
		if #out[i].children == 0 then table.remove(out, i) end
	end
	if #out == 0 then return { { label = L["No talents found"], disabled = true } } end
	return out
end

local function treeChoices()
	local out = {}
	for tab, info in ipairs(Compat.TalentTabs()) do out[#out + 1] = { value = tab, label = info.name } end
	if #out == 0 then
		for tab = 1, 3 do out[tab] = { value = tab, label = string.format(L["Tree %d"], tab) } end
	end
	return out
end

local function isEquipped(item)
	local fn = (C_Item and C_Item.IsEquippedItem) or IsEquippedItem
	if not fn then return nil end
	local ok, equipped = pcall(fn, item)
	if not ok or Compat.IsSecret(equipped) then return nil end
	return equipped and true or false
end

local function itemCooldown(id)
	local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	if not fn then return nil end
	local ok, start, duration, enabled = pcall(fn, id)
	if not ok or Compat.IsSecret(start, duration, enabled) then return nil end
	return tonumber(start) or 0, tonumber(duration) or 0, enabled
end

local function ownedItem(text)
	for _, token in ipairs(Compat.SplitList(text)) do
		local id, name = ns.Resolver.ParseToken(token)
		id = id or Compat.GetItemInstant(name)
		if id and ((Compat.GetItemCount(id) or 0) > 0 or isEquipped(id)) then return id end
	end
	return nil
end

local function firstItemIcon(text)
	local first = Compat.SplitList(text)[1]
	return first and ns.Items:Resolve(first).icon
end

define("talent", {
	label = L["Knows talent"],
	params = {
		{
			key = "talent", kind = "choice", label = L["Talent"], default = "", width = 190, choices = talentChoices,
			searchable = true, showUnknown = true,
			help = L["True with at least one point in this talent. Use IF NOT for talents you do not have. Talents are matched by name."],
		},
	},
	icon = function(c)
		local found
		Compat.ForEachTalent(function(_, name, icon) if name == c.talent then found = icon end end)
		return found
	end,
	eval = function(c)
		if c.talent == "" then return false end
		local known = false
		Compat.ForEachTalent(function(_, name, _, rank) if name == c.talent and rank > 0 then known = true end end)
		return known
	end,
})

define("spec", {
	label = L["Specialization (talent tree)"],
	params = {
		{
			key = "tree", kind = "choice", label = L["Talent tree"], default = 1, width = 130, choices = treeChoices,
			help = L["True when this tree has the most talent points. Trees tied for the most all count. With no points spent, none do."],
		},
	},
	icon = function(c)
		local tree = Compat.TalentTabs()[c.tree]
		return tree and tree.icon
	end,
	eval = function(c)
		local tabs = Compat.TalentTabs()
		local most = 0
		for _, info in ipairs(tabs) do most = math.max(most, info.points) end
		local tree = tabs[tonumber(c.tree) or 0]
		return most > 0 and tree ~= nil and tree.points == most
	end,
})

define("race", {
	label = L["Race is"],
	params = { { key = "race", kind = "choice", label = L["Race"], default = "Human", width = 110, choices = RACE_CHOICES } },
	eval = function(c)
		local _, token = UnitRace("player")
		if Compat.IsSecret(token) then return nil end
		return token == c.race
	end,
})

define("faction", {
	label = L["Faction is"],
	params = { { key = "faction", kind = "choice", label = L["Faction"], default = "Alliance", width = 90, choices = FACTION_CHOICES } },
	eval = function(c)
		local faction = UnitFactionGroup("player")
		if Compat.IsSecret(faction) then return nil end
		return faction == c.faction
	end,
})

define("itemEquipped", {
	label = L["Item equipped"],
	params = {
		{
			key = "item", kind = "text", resolver = "Items", label = L["Items"], hint = L["name or ID, ..."], default = "", width = 150,
			help = L["True when any of these items is equipped, e.g. a fishing pole or a trinket."],
		},
	},
	icon = function(c) return firstItemIcon(c.item) end,
	eval = function(c)
		local tokens = Compat.SplitList(c.item)
		if #tokens == 0 then return false end
		for _, token in ipairs(tokens) do
			local id, name = ns.Resolver.ParseToken(token)
			local equipped = isEquipped(id or name)
			if equipped == nil then return nil end
			if equipped then return true end
		end
		return false
	end,
})

define("itemReady", {
	measures = "time",
	label = L["Item is off cooldown"],
	params = {
		{
			key = "item", kind = "text", resolver = "Items", label = L["Item"], hint = L["name or ID"], default = "", width = 150,
			help = L["True when you have the item (in your bags or equipped) and it is off cooldown, e.g. Hearthstone or a trinket. With several items, the first one you have is used. {left} shows the cooldown left."],
		},
	},
	icon = function(c) return firstItemIcon(c.item) end,
	eval = function(c, vars)
		local id = ownedItem(c.item)
		if not id then return false end
		local start, duration, enabled = itemCooldown(id)
		if start == nil then return nil end
		if enabled == 0 or enabled == false then return false end
		if duration <= 1.5 or start + duration <= GetTime() then return true end
		SetVar(vars, "expires", start + duration)
		SetVar(vars, "duration", duration)
		return false
	end,
})

define("comboPoints", {
	measures = "value",
	label = L["Combo points"],
	params = { opParam(">="), numberParam("value", L["Points"], 5, 40) },
	eval = function(c, vars)
		local points = Compat.ComboPoints()
		if points == nil then return nil end
		setCount(vars, points, 5)
		return compare(points, c)
	end,
})

define("totem", {
	measures = "time",
	label = L["Totem active (shaman)"],
	params = {
		{ key = "element", kind = "choice", label = L["Element"], default = 0, width = 90, choices = TOTEM_CHOICES },
		textParam("names", L["Totems"], L["any, or names"], 130, L["Optional. Only these totems (any part of the name), comma separated."]),
	},
	eval = function(c, vars)
		if not GetTotemInfo then return false end
		local filter = #Compat.SplitList(c.names) > 0
		for slot = 1, MAX_TOTEMS do
			if c.element == 0 or c.element == slot then
				local have, name, start, duration = GetTotemInfo(slot)
				if Compat.IsSecret(have, name, start, duration) then return nil end
				if have and (not filter or matchesList(c.names, name)) then
					start, duration = tonumber(start) or 0, tonumber(duration) or 0
					if duration > 0 then
						SetVar(vars, "expires", start + duration)
						SetVar(vars, "duration", duration)
					end
					return true
				end
			end
		end
		return false
	end,
})

define("money", {
	measures = "value",
	label = L["Money (gold)"],
	icon = function() return "Interface\\Icons\\INV_Misc_Coin_01" end,
	params = { opParam("<"), numberParam("value", L["Gold"], 10, 50) },
	eval = function(c, vars)
		local copper = Compat.Plain(GetMoney())
		if copper == nil then return nil end
		local gold = copper / COPPER_PER_GOLD
		setCount(vars, math.floor(gold), threshold(c))
		return compare(gold, c)
	end,
})

define("targetHealth", {
	measures = "value",
	label = L["Target health percent"],
	params = { opParam("<"), numberParam("value", L["Percent"], 20, 40) },
	eval = function(c, vars)
		local exists = UnitExists("target")
		if Compat.IsSecret(exists) then return nil end
		if not exists then return false end
		local current, maximum = UnitHealth("target"), UnitHealthMax("target")
		if Compat.IsSecret(current, maximum) then return nil end
		current, maximum = tonumber(current) or 0, tonumber(maximum) or 0
		if maximum <= 0 then return false end
		local percent = current / maximum * 100
		setCount(vars, math.floor(percent + 0.5), 100)
		return compare(percent, c)
	end,
})

define("groupLeader", {
	label = L["You lead the group"],
	params = { { key = "kind", kind = "choice", label = L["Role"], default = "leader", width = 130, choices = LEADER_CHOICES } },
	eval = function(c)
		local inGroup = IsInGroup and IsInGroup() or (GetNumGroupMembers and (GetNumGroupMembers() or 0) > 0)
		if Compat.IsSecret(inGroup) then return nil end
		if not inGroup then return false end
		local leader = UnitIsGroupLeader and UnitIsGroupLeader("player")
		if Compat.IsSecret(leader) then return nil end
		if leader then return true end
		if c.kind ~= "assist" then return false end
		local assist = UnitIsGroupAssistant and UnitIsGroupAssistant("player")
		if Compat.IsSecret(assist) then return nil end
		return assist and true or false
	end,
})

define("groupSize", {
	measures = "value",
	label = L["Group size"],
	params = { opParam(">="), numberParam("value", L["Players"], 5, 40) },
	eval = function(c, vars)
		local members = GetNumGroupMembers and Compat.Plain(GetNumGroupMembers()) or 0
		if members == nil then return nil end
		local size = math.max(1, tonumber(members) or 0)
		setCount(vars, size, threshold(c))
		return compare(size, c)
	end,
})

define("casting", {
	measures = "time",
	label = L["Casting or channeling"],
	params = {
		{ key = "kind", kind = "choice", label = L["Cast type"], default = "any", width = 140, choices = CAST_CHOICES },
		spellsParam(140, L["Optional. Only these spells, or any spell when empty."]),
	},
	icon = function(c) return spellIcon(c.spells) end,
	eval = function(c, vars)
		local filter = #Compat.SplitList(c.spells) > 0 and spellSet(c.spells) or nil
		for _, kind in ipairs({ "cast", "channel" }) do
			if c.kind == "any" or c.kind == kind then
				local name, spellID, ends = Compat.PlayerCast(kind)
				if name and (not filter or Tracker:Matches(filter, spellID, name)) then
					SetVar(vars, "expires", ends)
					return true
				end
			end
		end
		return false
	end,
})

define("encounter", {
	label = L["Boss encounter in progress"],
	params = {
		textParam("names", L["Bosses"], L["any, or names and IDs"], 150,
			L["Optional. Boss or encounter names (any part) or encounter IDs, comma separated. Empty = any boss fight that the game reports as an encounter."]),
	},
	eval = function(c)
		local encounter = Tracker.encounter
		if not encounter then return false end
		if #Compat.SplitList(c.names) == 0 then return true end
		return matchesList(c.names, encounter.name, encounter.id)
	end,
})

define("status", {
	label = L["PvP flag, AFK or DND"],
	params = { { key = "kind", kind = "choice", label = L["Status"], default = "pvp", width = 120, choices = STATUS_CHOICES } },
	eval = function(c)
		local fn = c.kind == "afk" and UnitIsAFK or c.kind == "dnd" and UnitIsDND or UnitIsPVP
		if not fn then return false end
		return flag(fn("player"))
	end,
})

-- How the condition menu groups the types. Types missing here are listed under "Other".
Conditions.CATEGORIES = {
	{
		label = L["You"],
		types = { "combat", "mounted", "mountUsable", "moving", "swimming", "stealthed", "dead", "taxi", "power", "comboPoints", "form", "casting", "totem", "status" },
	},
	{ label = L["Character"], types = { "class", "race", "faction", "level", "restedXP", "spellKnown", "talent", "spec", "money" } },
	{ label = L["Location"], types = { "resting", "indoors", "instance", "zone", "encounter", "atMerchant", "atMailbox" } },
	{ label = L["Party and target"], types = { "group", "groupSize", "groupLeader", "groupBuffMissing", "target", "targetClass", "targetHealth" } },
	{ label = L["Pet"], types = { "pet", "petDead", "petHappiness" } },
	{ label = L["Auras and spells"], types = { "aura", "spellReady", "tracking" } },
	{ label = L["Gear and items"], types = { "weaponEquipped", "weaponEnchant", "itemEquipped", "itemReady", "itemCount", "ammo", "durability", "bagSlots" } },
}