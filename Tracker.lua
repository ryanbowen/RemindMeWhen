local _, ns = ...
local Compat, Data = ns.Compat, ns.Data

-- Aura and weapon enchant state. While the game keeps aura data secret (combat, encounters), the
-- last known state is kept and updated from your own casts and from aura events that are readable.
local Tracker = {
	entries = {},
	sets = {},
	auraScans = {},
	weaponScans = {},
	weaponCache = {},
	generation = 1,
}
ns.Tracker = Tracker

local HELPFUL, HARMFUL = "HELPFUL", "HARMFUL"
local MAIN_HAND, OFF_HAND = 16, 17

local function learned()
	return ns.db and ns.db.learned or {}
end

function Tracker:GetSpellSet(text)
	text = type(text) == "string" and text or tostring(text or "")
	local set = self.sets[text]
	if set then return set end
	set = { key = text, ids = {}, names = {}, idNames = {}, tokens = Compat.SplitList(text) }
	for _, token in ipairs(set.tokens) do
		local id, name = ns.Spells.ParseToken(token)
		if id then set.ids[id] = true else set.names[name:lower()] = true end
	end
	self.sets[text] = set
	return set
end

-- Typed names plus names resolved from IDs, so other ranks of the same spell match too.
local function hasName(set, lower)
	return set.names[lower] or set.idNames[lower]
end

local function eachName(set, fn)
	for name in pairs(set.names) do fn(name) end
	for name in pairs(set.idNames) do
		if not set.names[name] then fn(name) end
	end
end

function Tracker:Learn(name, spellID)
	if not (ns.db and type(name) == "string" and type(spellID) == "number") then return end
	name = name:lower()
	local map = ns.db.learned[name]
	if not map then
		map = {}
		ns.db.learned[name] = map
	end
	map[spellID] = true
end

-- Spell names can become secret in combat, so names and IDs are mapped while out of combat.
function Tracker:Resolve(set)
	if set.resolvedAt == self.generation or Compat.InCombat() then return end
	set.resolvedAt = self.generation
	for name in pairs(set.names) do
		local _, id = Compat.GetSpellInfo(name)
		if id then self:Learn(name, id) end
	end
	for id in pairs(set.ids) do
		local name = Compat.GetSpellInfo(id)
		if name then set.idNames[name:lower()] = true else ns.Spells:RequestLoad(id) end
	end
end

function Tracker:ResetResolved()
	self.generation = self.generation + 1
end

function Tracker:ForEachID(set, fn)
	for id in pairs(set.ids) do fn(id) end
	local map = learned()
	eachName(set, function(name)
		for id in pairs(map[name] or {}) do
			if not set.ids[id] then fn(id) end
		end
	end)
end

function Tracker:HasUnlearnedNames(set)
	local map = learned()
	for name in pairs(set.names) do
		if not (map[name] and next(map[name])) then return true end
	end
	return false
end

function Tracker:Matches(set, spellID, name)
	if type(spellID) == "number" then
		if set.ids[spellID] then return true end
		local map, hit = learned(), false
		eachName(set, function(n)
			local ids = map[n]
			if ids and ids[spellID] then hit = true end
		end)
		if hit then return true end
	end
	if type(name) == "string" and hasName(set, name:lower()) then return true end
	return false
end

function Tracker:InGroup(set, group)
	local hit = false
	self:ForEachID(set, function(id)
		if Data.exclusiveGroupOf[id] == group then hit = true end
	end)
	return hit
end

function Tracker:BeginPass()
	wipe(self.auraScans)
	wipe(self.weaponScans)
end

local function readAuraList(unit, filter)
	local list = {}
	local getData = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	for i = 1, 255 do
		local aura
		if getData then
			local ok, data = pcall(getData, unit, i, filter)
			if not ok or Compat.IsSecret(data) then return nil end
			aura = data
		elseif UnitAura then
			local ok, name, _, _, _, duration, expirationTime, _, _, _, spellId = pcall(UnitAura, unit, i, filter)
			if not ok then return nil end
			aura = name and { name = name, duration = duration, expirationTime = expirationTime, spellId = spellId } or nil
		else
			return nil
		end
		if not aura then return list end
		if Compat.IsSecret(aura.name, aura.spellId, aura.duration, aura.expirationTime, aura.auraInstanceID) then return nil end
		list[#list + 1] = aura
	end
	return list
end

-- Uncached read for the options UI, or nil while auras are secret.
function Tracker:ReadAuras(unit, filter)
	if Compat.AurasSecret() or not Compat.Plain(UnitExists(unit)) then return nil end
	return readAuraList(unit, filter)
end

-- Returns the aura list, or nil while it cannot be read.
function Tracker:ScanAuras(unit, filter)
	local key = unit .. "|" .. filter
	local scan = self.auraScans[key]
	if scan == nil then
		local exists = UnitExists(unit)
		if Compat.IsSecret(exists) then
			scan = false
		elseif not exists then
			scan = {}
		elseif Compat.AurasSecret() then
			scan = false
		else
			scan = readAuraList(unit, filter) or false
		end
		self.auraScans[key] = scan
	end
	return scan or nil
end

function Tracker:Entry(unit, filter, set)
	local key = unit .. "|" .. filter .. "|" .. set.key
	local entry = self.entries[key]
	if not entry then
		entry = { unit = unit, filter = filter, set = set }
		self.entries[key] = entry
	end
	return entry
end

local function store(entry, present, aura)
	entry.known, entry.present = true, present
	entry.expires, entry.instanceID = nil, nil
	if present and aura then
		local expires, duration = tonumber(aura.expirationTime), tonumber(aura.duration)
		if expires and expires > 0 then entry.expires = expires end
		if duration and duration > 0 then entry.duration = duration end
		entry.instanceID = aura.auraInstanceID
	end
end

-- Some spells stay readable even while auras in general are secret.
function Tracker:DirectLookup(unit, set)
	if not C_UnitAuras then return nil end
	local getter
	if unit == "player" and C_UnitAuras.GetPlayerAuraBySpellID then
		getter = function(id) return C_UnitAuras.GetPlayerAuraBySpellID(id) end
	elseif C_UnitAuras.GetUnitAuraBySpellID then
		getter = function(id) return C_UnitAuras.GetUnitAuraBySpellID(unit, id) end
	else
		return nil
	end
	if self:HasUnlearnedNames(set) then return nil end
	local ids, blocked = {}, false
	self:ForEachID(set, function(id)
		ids[#ids + 1] = id
		if Compat.SpellAuraSecret(id) then blocked = true end
	end)
	if blocked or #ids == 0 then return nil end
	for _, id in ipairs(ids) do
		local ok, aura = pcall(getter, id)
		if not ok or Compat.IsSecret(aura) then return nil end
		if aura then
			if type(aura) ~= "table" or Compat.IsSecret(aura.expirationTime, aura.duration, aura.auraInstanceID) then
				return true, nil
			end
			return true, aura
		end
	end
	return false
end

-- Returns present (true/false, nil = unknown), seconds left, expiration time and duration (nil = none).
function Tracker:FindAura(unit, filter, set)
	local entry = self:Entry(unit, filter, set)
	local now = GetTime()
	local auras = self:ScanAuras(unit, filter)
	if auras then
		local found
		for _, aura in ipairs(auras) do
			if self:Matches(set, aura.spellId, aura.name) then
				found = aura
				break
			end
		end
		if found and type(found.name) == "string" and hasName(set, found.name:lower()) then
			self:Learn(found.name, found.spellId)
		end
		store(entry, found ~= nil, found)
	else
		local present, aura = self:DirectLookup(unit, set)
		if present ~= nil then
			store(entry, present, aura)
		elseif entry.known and entry.present and entry.expires and entry.expires <= now then
			entry.present, entry.expires, entry.instanceID = false, nil, nil
		end
	end
	if not entry.known then return nil end
	if not (entry.present and entry.expires) then return entry.present end
	return true, entry.expires - now, entry.expires, entry.duration
end

-- Returns present for one unit using only readable data, or nil when unknown.
function Tracker:UnitHasAura(unit, filter, set)
	local auras = self:ScanAuras(unit, filter)
	if not auras then return nil end
	for _, aura in ipairs(auras) do
		if self:Matches(set, aura.spellId, aura.name) then return true end
	end
	return false
end

function Tracker:GroupUnits()
	local units = { "player" }
	if IsInRaid and Compat.Plain(IsInRaid()) then
		units = {}
		local count = Compat.Plain(GetNumGroupMembers and GetNumGroupMembers()) or 0
		for i = 1, count do units[#units + 1] = "raid" .. i end
	elseif IsInGroup and Compat.Plain(IsInGroup()) then
		local count = Compat.Plain(GetNumSubgroupMembers and GetNumSubgroupMembers()) or 4
		for i = 1, count do units[#units + 1] = "party" .. i end
	end
	return units
end

-- Vendor and mailbox windows have no query API, so their open state comes from events.
Tracker.windows = {}

function Tracker:SetWindow(key, open)
	self.windows[key] = open or nil
end

-- The boss fight in progress, from ENCOUNTER_START until ENCOUNTER_END or a loading screen.
function Tracker:SetEncounter(id, name)
	self.encounter = (id or name) and { id = id, name = name } or nil
end

-- A dead hunter pet leaves the pet unit, so the death is remembered until a live pet returns.
function Tracker:UpdatePet()
	local exists = Compat.Plain(UnitExists("pet"))
	if exists == nil then return end
	if exists then
		local dead = Compat.Plain(UnitIsDead("pet"))
		if dead ~= nil then self.petDead = dead or nil end
	end
end

function Tracker:OnPetGone()
	if self.petDead then return end
	local exists = Compat.Plain(UnitExists("pet"))
	if exists == false and self.petHealthZero then self.petDead = true end
	self.petHealthZero = nil
end

function Tracker:OnPetHealth()
	local health = Compat.Plain(UnitHealth("pet"))
	if health ~= nil then self.petHealthZero = health <= 0 or nil end
	self:UpdatePet()
end

function Tracker:OnPlayerCast(spellID)
	if Compat.IsSecret(spellID) or type(spellID) ~= "number" then return end
	if not Compat.InCombat() then
		local name = Compat.GetSpellInfo(spellID)
		if name then
			local lower = name:lower()
			for _, entry in pairs(self.entries) do
				if hasName(entry.set, lower) then self:Learn(lower, spellID) end
			end
		end
	end
	local group = Data.exclusiveGroupOf[spellID]
	local now = GetTime()
	for _, entry in pairs(self.entries) do
		if entry.unit == "player" and entry.filter == HELPFUL then
			if self:Matches(entry.set, spellID) then
				entry.known, entry.present, entry.instanceID = true, true, nil
				entry.expires = entry.duration and (now + entry.duration) or nil
			elseif group and self:InGroup(entry.set, group) then
				entry.known, entry.present, entry.expires, entry.instanceID = true, false, nil, nil
			end
		end
	end
end

function Tracker:OnUnitAura(unit, info)
	if not Compat.AurasSecret() or Compat.IsSecret(info) or type(info) ~= "table" then return end
	local removed = info.removedAuraInstanceIDs
	if not Compat.IsSecret(removed) and type(removed) == "table" then
		for _, instanceID in ipairs(removed) do
			if not Compat.IsSecret(instanceID) then
				for _, entry in pairs(self.entries) do
					if entry.unit == unit and entry.instanceID == instanceID then
						entry.present, entry.expires, entry.instanceID = false, nil, nil
					end
				end
			end
		end
	end
	local added = info.addedAuras
	if not Compat.IsSecret(added) and type(added) == "table" then
		for _, aura in ipairs(added) do
			if not Compat.IsSecret(aura) and type(aura) == "table"
				and not Compat.IsSecret(aura.spellId, aura.isHelpful, aura.expirationTime, aura.duration, aura.auraInstanceID) then
				local filter = aura.isHelpful == false and HARMFUL or HELPFUL
				for _, entry in pairs(self.entries) do
					if entry.unit == unit and entry.filter == filter and self:Matches(entry.set, aura.spellId) then
						store(entry, true, aura)
					end
				end
			end
		end
	end
end

function Tracker:ResetUnit(unit)
	for _, entry in pairs(self.entries) do
		if entry.unit == unit then entry.known, entry.present, entry.expires, entry.instanceID = false, nil, nil, nil end
	end
end

local function readWeapon(slot)
	local now = GetTime()
	if C_Item and C_Item.GetWeaponEnchantInfo and Enum and Enum.WeaponSlot and Enum.ItemEnchantType then
		local weaponSlot = slot == MAIN_HAND and Enum.WeaponSlot.MainHand or Enum.WeaponSlot.OffHand
		local ok, list = pcall(C_Item.GetWeaponEnchantInfo, weaponSlot)
		if not ok or Compat.IsSecret(list) then return nil end
		local out = {}
		if type(list) ~= "table" then return out end
		for _, info in pairs(list) do
			if Compat.IsSecret(info) or type(info) ~= "table" then return nil end
			if Compat.IsSecret(info.hasEnchant, info.enchantType, info.enchantID, info.timeLeft) then return nil end
			local kind = info.enchantType
			if info.hasEnchant and (kind == Enum.ItemEnchantType.Temporary or kind == Enum.ItemEnchantType.Imbue) then
				local left = tonumber(info.timeLeft) or 0
				out[#out + 1] = { id = tonumber(info.enchantID), expires = left > 0 and (now + left / 1000) or nil }
			end
		end
		return out
	end
	if GetWeaponEnchantInfo then
		local ok, hasMain, mainMs, _, mainID, hasOff, offMs, _, offID = pcall(GetWeaponEnchantInfo)
		if not ok or Compat.IsSecret(hasMain, mainMs, mainID, hasOff, offMs, offID) then return nil end
		local has, ms, id
		if slot == MAIN_HAND then has, ms, id = hasMain, mainMs, mainID else has, ms, id = hasOff, offMs, offID end
		if not has then return {} end
		ms = tonumber(ms) or 0
		return { { id = tonumber(id), expires = ms > 0 and (now + ms / 1000) or nil } }
	end
	return nil
end

-- Returns a list of { id, expires } for the slot, or nil when unknown.
function Tracker:GetWeaponEnchants(slot)
	local scan = self.weaponScans[slot]
	if scan == nil then
		scan = readWeapon(slot) or false
		self.weaponScans[slot] = scan
		if scan then self.weaponCache[slot] = scan end
	end
	if scan then return scan end
	local cached = self.weaponCache[slot]
	if not cached then return nil end
	local now, live = GetTime(), {}
	for _, enchant in ipairs(cached) do
		if not enchant.expires or enchant.expires > now then live[#live + 1] = enchant end
	end
	return live
end

function Tracker:InvalidateWeapon(slot)
	if slot == MAIN_HAND or slot == OFF_HAND then
		self.weaponCache[slot] = nil
		self.weaponScans[slot] = nil
	end
end
