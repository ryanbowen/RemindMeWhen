local _, ns = ...

local Compat = {}
ns.Compat = Compat

local issecretvalue = _G.issecretvalue

-- Secret values may be stored but never compared, so every API result is checked first.
function Compat.IsSecret(...)
	if not issecretvalue then return false end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then return true end
	end
	return false
end

function Compat.Plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

function Compat.Flag(value)
	if Compat.IsSecret(value) then return nil end
	return value and true or false
end

function Compat.InCombat()
	if InCombatLockdown and InCombatLockdown() then return true end
	return UnitAffectingCombat and Compat.Plain(UnitAffectingCombat("player")) and true or false
end

function Compat.AurasSecret()
	if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
	local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
	if not ok or Compat.IsSecret(secret) then return true end
	return secret == true
end

function Compat.SpellAuraSecret(spellID)
	if not (C_Secrets and C_Secrets.ShouldSpellAuraBeSecret) then return true end
	local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, spellID)
	if not ok or Compat.IsSecret(secret) then return true end
	return secret == true
end

-- Returns name, spellID, icon for a spell ID or a spell name the player knows.
function Compat.GetSpellInfo(spell)
	if spell == nil or spell == "" then return nil end
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, spell)
		if not ok or Compat.IsSecret(info) or type(info) ~= "table" then return nil end
		if Compat.IsSecret(info.name, info.spellID, info.iconID) then return nil end
		return info.name, info.spellID, info.iconID
	end
	if GetSpellInfo then
		local ok, name, _, icon, _, _, _, id = pcall(GetSpellInfo, spell)
		if not ok or Compat.IsSecret(name, id, icon) then return nil end
		return name, id, icon
	end
	return nil
end

-- Returns itemID, classID, icon.
function Compat.GetItemInstant(item)
	if item == nil or item == "" then return nil end
	local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if not fn then return nil end
	local ok, id, _, _, _, icon, classID, subclassID = pcall(fn, item)
	if not ok or Compat.IsSecret(id, icon, classID, subclassID) then return nil end
	return id, classID, icon, subclassID
end

function Compat.GetItemIcon(itemID)
	if not itemID then return nil end
	local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
	if not fn then return nil end
	local ok, icon = pcall(fn, itemID)
	if not ok then return nil end
	return Compat.Plain(icon)
end

function Compat.GetItemCount(item)
	local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
	if not fn then return nil end
	local ok, count = pcall(fn, item, false, false)
	if not ok or Compat.IsSecret(count) then return nil end
	return tonumber(count) or 0
end

function Compat.Compare(a, op, b)
	if op == "<" then return a < b end
	if op == "<=" then return a <= b end
	if op == ">" then return a > b end
	if op == ">=" then return a >= b end
	return a == b
end

function Compat.SplitList(text)
	local out = {}
	if type(text) ~= "string" then text = text and tostring(text) or "" end
	for token in text:gmatch("[^,;]+") do
		token = token:match("^%s*(.-)%s*$")
		if token ~= "" then out[#out + 1] = token end
	end
	return out
end

function Compat.CopyTable(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = Compat.CopyTable(v) end
	return out
end

local charKey
function Compat.CharKey()
	if charKey then return charKey end
	local name = Compat.Plain(UnitName("player")) or "?"
	local realm = GetRealmName and Compat.Plain(GetRealmName()) or ""
	charKey = name .. "-" .. realm
	return charKey
end

-- Returns name, itemID, icon, or nil while the item is not cached.
function Compat.GetItemInfo(item)
	if item == nil or item == "" then return nil end
	local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not fn then return nil end
	local ok, name, link, _, _, minLevel, _, _, _, _, icon = pcall(fn, item)
	if not ok or Compat.IsSecret(name, link, icon) or not name then return nil end
	local id = type(item) == "number" and item or (link and tonumber(link:match("item:(%d+)")))
	return name, id, icon, tonumber(Compat.Plain(minLevel))
end

function Compat.FormatTime(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	if seconds >= 3600 then return string.format("%dh", math.floor(seconds / 3600 + 0.5)) end
	if seconds >= 60 then return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60) end
	return seconds .. "s"
end

local UNIT_SECONDS = { h = 3600, m = 60, s = 1 }

-- Seconds from "90", "90s", "20m", "1h30m" or "1:30" (minutes:seconds), or nil.
function Compat.ParseDuration(text)
	text = type(text) == "string" and text:lower():gsub("%s+", "") or ""
	if text == "" then return nil end
	if text:match("^%d+$") then return tonumber(text) end
	local minutes, seconds = text:match("^(%d+):(%d%d)$")
	if minutes then return tonumber(minutes) * 60 + tonumber(seconds) end
	local total, rest = 0, text
	while rest ~= "" do
		local number, unit, after = rest:match("^(%d+)([hms])(.*)$")
		if not number then return nil end
		total = total + tonumber(number) * UNIT_SECONDS[unit]
		rest = after
	end
	return total
end

-- Short form for durations typed by the user: 90 -> "1m30s", 600 -> "10m".
function Compat.FormatDuration(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	local h, m, s = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
	local out = (h > 0 and h .. "h" or "") .. (m > 0 and m .. "m" or "") .. (s > 0 and s .. "s" or "")
	return out ~= "" and out or "0s"
end

function Compat.MapID()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
	if not ok or Compat.IsSecret(id) then return nil end
	return tonumber(id)
end

-- Talent trees of your class: { name, icon, points } each. Newer clients return an ID first.
function Compat.TalentTabs()
	local out = {}
	if not (GetNumTalentTabs and GetTalentTabInfo) then return out end
	for tab = 1, GetNumTalentTabs() or 0 do
		local a, b, c, d, e = GetTalentTabInfo(tab)
		if type(a) == "number" and type(b) == "string" then
			out[tab] = { name = b, icon = d, points = tonumber(e) or 0 }
		else
			out[tab] = { name = a, icon = b, points = tonumber(c) or 0 }
		end
	end
	return out
end

-- Calls fn(tab, name, icon, rank, maxRank) for every talent of your class.
function Compat.ForEachTalent(fn)
	if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return end
	for tab = 1, GetNumTalentTabs() or 0 do
		for index = 1, GetNumTalents(tab) or 0 do
			local name, icon, _, _, rank, maxRank = GetTalentInfo(tab, index)
			if type(name) == "string" then fn(tab, name, icon, tonumber(rank) or 0, tonumber(maxRank) or 0) end
		end
	end
end

local function pack(...)
	return { n = select("#", ...), ... }
end

-- What you are casting ("cast") or channeling ("channel"): name, spell ID and end time in seconds.
function Compat.PlayerCast(kind)
	local fn = kind == "channel" and UnitChannelInfo or UnitCastingInfo
	if not fn then return nil end
	local values = pack(fn("player"))
	local name = values[1]
	if Compat.IsSecret(name) or type(name) ~= "string" then return nil end
	local spellID
	for i = 7, values.n do
		local value = values[i]
		if not Compat.IsSecret(value) and type(value) == "number" and value > 0 then spellID = value end
	end
	local endMS = tonumber(values[5])
	return name, spellID, endMS and endMS / 1000
end

function Compat.ComboPoints()
	if GetComboPoints then return Compat.Plain(GetComboPoints("player", "target")) end
	local comboType = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
	return Compat.Plain(UnitPower("player", comboType))
end