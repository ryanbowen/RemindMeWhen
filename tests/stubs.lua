NS = {}
FRAMES = {}
NOW = 1000
WALL = 50000
SECRET = setmetatable({}, { __tostring = function() return "SECRET" end })

function issecretvalue(v) return v == SECRET end
function time() return WALL end

local function newObject(kind, name)
	local obj = { _kind = kind, _name = name, _shown = true, _scripts = {}, _width = 100, _text = "", _checked = false, _attr = {} }
	local mt = {}
	mt.__index = function(t, key)
		local methods = {
			CreateTexture = function() return newObject("Texture") end,
			CreateFontString = function() return newObject("FontString") end,
			CreateAnimationGroup = function() return newObject("AnimGroup") end,
			CreateAnimation = function() return newObject("Anim") end,
			SetScript = function(self, s, fn) self._scripts[s] = fn end,
			HookScript = function(self, s, fn)
				local old = self._scripts[s]
				if old then self._scripts[s] = function(...) old(...) fn(...) end else self._scripts[s] = fn end
			end,
			GetScript = function(self, s) return self._scripts[s] end,
			Show = function(self) self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end,
			Hide = function(self) self._shown = false; if self._scripts.OnHide then self._scripts.OnHide(self) end end,
			SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
			IsShown = function(self) return self._shown end,
			GetWidth = function(self) return self._width end,
			GetHeight = function(self) return self._height or 100 end,
			SetWidth = function(self, w) self._width = w end,
			SetHeight = function(self, h) self._height = h end,
			SetSize = function(self, w, h) self._width = w; self._height = h or self._height end,
			GetRect = function(self) if self._rect then return unpack(self._rect) end return 10, 20, 100, 40 end,
			GetEffectiveScale = function(self) return self._scale or 1 end,
			SetScale = function(self, s) self._scale = s end,
			SetPoint = function(self, ...) self._points = self._points or {}; self._points[#self._points + 1] = { ... } end,
			ClearAllPoints = function(self) self._points = {} end,
			SetAlpha = function(self, a) self._alpha = a end,
			IsMouseOver = function(self) return self._mouseOver or false end,
			GetTop = function(self) return self._top or 100 end,
			GetBottom = function(self) return self._bottom or 78 end,
			GetStringWidth = function(self) return #(self._text or "") * 7 end,
			SetText = function(self, v) self._text = v end,
			GetText = function(self) return self._text end,
			SetTexture = function(self, v) self._texture = v end,
			SetChecked = function(self, v) self._checked = v and true or false end,
			GetChecked = function(self) return self._checked end,
			SetAttribute = function(self, k, v) self._attr[k] = v end,
			GetAttribute = function(self, k) return self._attr[k] end,
			SetCooldown = function(self, start, duration) self._cd = { start, duration } end,
			SetValue = function(self, v) self._value = v end,
			GetValue = function(self) return self._value end,
			SetStatusBarTexture = function(self, v) self._barTexture = v end,
			SetStatusBarColor = function(self, r, g, b) self._barColor = { r, g, b } end,
			SetColorTexture = function(self, r, g, b, a) self._color = { r, g, b, a } end,
			HasFocus = function() return false end,
			SetEnabled = function(self, v) self._enabled = v and true or false end,
			GetPoint = function() return "CENTER", nil, "CENTER", 10.4, 20.6 end,
			IsPlaying = function(self) return self._playing end,
			Play = function(self) self._playing = true end,
			Stop = function(self) self._playing = false end,
			GetFont = function() return "Fonts\\FRIZQT__.TTF", 14, "" end,
			GetFrameLevel = function() return 1 end,
			RegisterEvent = function(self, e) self._events = self._events or {}; self._events[e] = true end,
			RegisterUnitEvent = function(self, e) self._events = self._events or {}; self._events[e] = true end,
		}
		local m = methods[key]
		if m then return m end
		if type(key) == "string" and key:match("^%u") then return function() return nil end end
		return nil
	end
	setmetatable(obj, mt)
	FRAMES[#FRAMES + 1] = obj
	if name then _G[name] = obj end
	return obj
end

function CreateFrame(kind, name, parent, template)
	local obj = newObject(kind, name)
	obj._template = template
	obj.Low, obj.High, obj.Text = newObject("FontString"), newObject("FontString"), newObject("FontString")
	return obj
end

UIParent = newObject("Frame", "UIParent")
GameTooltip = newObject("GameTooltip", "GameTooltip")
GameFontNormalLarge = newObject("Font")
CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) CHAT[#CHAT + 1] = msg end }
UISpecialFrames = {}
StaticPopupDialogs = {}
POPUPS = {}
function StaticPopup_Show(name, text)
	local dialog = { name = name, text = text }
	POPUPS[#POPUPS + 1] = dialog
	return dialog
end
CURSOR = { 0, 0 }
function GetCursorPosition() return CURSOR[1], CURSOR[2] end
SlashCmdList = {}
SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960 }
PLAYED = {}
function PlaySound(kit) PLAYED[#PLAYED + 1] = kit end
RaidWarningFrame = {}
ALERTS = {}
function RaidNotice_AddMessage(_, text) ALERTS[#ALERTS + 1] = text end
ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0, b = 0 } }
function tinsert(t, v) table.insert(t, v) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function() end }
function GetTime() return NOW end
function GetBuildInfo() return "1.60.1", "71037", "", 16001 end
STATE_DRIVERS = {}
function RegisterStateDriver(frame, attr, value) STATE_DRIVERS[#STATE_DRIVERS + 1] = { frame, attr, value } end
C_CVar = { GetCVar = function(name) if name == "ActionButtonUseKeyDown" then return "1" end end }

STATE = {
	combat = false, mounted = false, indoors = false, class = "HUNTER", level = 60,
	auras = {}, unitAuras = {}, aurasSecret = false, mounts = { { id = 1, usable = true, favorite = true } },
	weapons = { [16] = {}, [17] = {} }, items = { [16] = 1001, [17] = 1002, [0] = 2512 },
	ammo = 150, durability = { [1] = { 20, 100 }, [5] = { 90, 100 } }, freeSlots = { 2, 0, 0, 0, 0 },
	rested = 500, xpMax = 1000, targetClass = "elite", targetLevel = 62, target = false,
	happiness = 3, pet = false, petDead = false, petHealth = 100,
	bag = { [8928] = 5, [6265] = 2 }, group = {}, summoned = {},
}

function InCombatLockdown() return STATE.combat end
function UnitAffectingCombat() return STATE.combat end
function IsMounted() return STATE.mounted end
function IsIndoors() return STATE.indoors end
function IsOutdoors() return not STATE.indoors end
function UnitClass() return "Hunter", STATE.class end
function UnitLevel(unit) if unit == "target" then return STATE.targetLevel end return STATE.level end
function UnitName(unit)
	if unit == "player" then return "Tester" end
	if unit == "target" then return STATE.target and "Hogger" or nil end
	local member = STATE.group[unit]
	return member and member.name
end
function GetRealmName() return "Realm" end
function UnitIsDeadOrGhost() return false end
function UnitIsDead(unit) if unit == "pet" then return STATE.petDead end return false end
function UnitOnTaxi() return false end
function UnitExists(u)
	if u == "player" then return true end
	if u == "pet" then return STATE.pet end
	if u == "target" then return STATE.target end
	return STATE.group[u] ~= nil
end
function UnitIsUnit(a, b) return a == b end
function UnitIsConnected(u) return u == "player" or (STATE.group[u] and STATE.group[u].online ~= false) end
function UnitIsVisible() return true end
function UnitClassification() return STATE.targetClass end
function UnitCanAttack() return true end
function IsResting() return false end
function IsInInstance() return STATE.instance or false, STATE.instance and "party" or "none" end
function IsInGroup() return next(STATE.group) ~= nil end
function IsInRaid() return false end
function GetNumSubgroupMembers() local n = 0 for _ in pairs(STATE.group) do n = n + 1 end return n end
function GetNumGroupMembers() return GetNumSubgroupMembers() + 1 end
function IsPlayerMoving() return false end
function GetInventoryItemID(_, slot) return STATE.items[slot] end
function GetInventoryItemTexture() return 12345 end
function GetInventoryItemCount(_, slot) if slot == 0 then return STATE.ammo end return 1 end
function GetInventorySlotInfo(name) if name == "AmmoSlot" then return 0 end end
function GetInventoryItemDurability(slot) local d = STATE.durability[slot]; if d then return d[1], d[2] end end
function GetXPExhaustion() return STATE.rested end
function UnitXPMax() return STATE.xpMax end
function GetPetHappiness() if STATE.pet then return STATE.happiness end end
function CanMerchantRepair() return true end
function GetNumShapeshiftForms() return 0 end
function IsPlayerSpell(id) return id == 883 or id == 13165 or id == 982 end
function UnitHealth(unit)
	if unit == "pet" then return STATE.petHealth end
	if unit == "target" then return STATE.targetHealth end
	return 50
end
function UnitHealthMax() return 100 end
function UnitPower() return 10 end
function UnitPowerMax() return 100 end

C_Secrets = { ShouldAurasBeSecret = function() return STATE.aurasSecret end, ShouldSpellAuraBeSecret = function() return true end }
C_UnitAuras = {
	GetAuraDataByIndex = function(unit, i, filter)
		if STATE.aurasSecret then return SECRET end
		if filter ~= "HELPFUL" then return nil end
		if unit == "player" then return STATE.auras[i] end
		local list = STATE.unitAuras[unit]
		return list and list[i]
	end,
	GetPlayerAuraBySpellID = function() return SECRET end,
}
SPELL_NAMES = {
	[13159] = "Aspect of the Pack", [13165] = "Aspect of the Hawk", [14318] = "Aspect of the Hawk", [5118] = "Aspect of the Cheetah",
	[883] = "Call Pet", [982] = "Revive Pet", [6991] = "Feed Pet", [19705] = "Well Fed", [1243] = "Power Word: Fortitude",
	[21562] = "Prayer of Fortitude", [458] = "Brown Horse",
}
UNLOADED = { [99998] = "Late Spell" }
LOAD_REQUESTS = {}
C_Spell = {
	GetSpellInfo = function(spell)
		local byName = { ["aspect of the hawk"] = 13165 }
		for id, n in pairs(SPELL_NAMES) do byName[n:lower()] = byName[n:lower()] or id end
		local id = type(spell) == "number" and spell or byName[tostring(spell):lower()]
		if not id or not SPELL_NAMES[id] then return nil end
		return { name = SPELL_NAMES[id], spellID = id, iconID = 100 + id }
	end,
	DoesSpellExist = function(id) return SPELL_NAMES[id] ~= nil or UNLOADED[id] ~= nil end,
	RequestLoadSpellData = function(id) LOAD_REQUESTS[#LOAD_REQUESTS + 1] = id end,
}
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 3 } end,
	GetSpellBookItemInfo = function(i)
		local ids = { 13165, 13159, 883 }
		local id = ids[i]
		return { itemType = 1, spellID = id, name = SPELL_NAMES[id], iconID = 100 + id }
	end,
}
C_MountJournal = {
	GetMountIDs = function() local out = {} for _, m in ipairs(STATE.mounts) do out[#out + 1] = m.id end return out end,
	GetMountInfoByID = function(id)
		for _, m in ipairs(STATE.mounts) do
			if m.id == id then return "Brown Horse", 458, 132261, false, m.usable, 0, m.favorite, false, 1, false, true end
		end
	end,
	SummonByID = function(id) STATE.summoned[#STATE.summoned + 1] = id end,
}
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 }, WeaponSlot = { MainHand = 0, OffHand = 1 }, ItemEnchantType = { Temporary = 1, Imbue = 2, Permanent = 0 }, ItemClass = { Weapon = 2 } }
ITEM_NAMES = { [8928] = "Instant Poison VI", [8927] = "Instant Poison V", [6265] = "Soul Shard", [20844] = "Deadly Poison V",
	[18262] = "Elemental Sharpening Stone", [12404] = "Dense Sharpening Stone", [7964] = "Solid Sharpening Stone",
	[12643] = "Dense Weightstone" }
ITEM_MIN_LEVEL = { [8928] = 60, [8927] = 52, [18262] = 50, [12404] = 35, [7964] = 25, [12643] = 35 }
WEAPON_SUBCLASS = {}
C_Item = {
	GetWeaponEnchantInfo = function(slot)
		return STATE.weapons[slot == 0 and 16 or 17]
	end,
	GetItemInfoInstant = function(id)
		if type(id) == "string" then
			for itemID, n in pairs(ITEM_NAMES) do if n:lower() == id:lower() then return itemID, "Consumable", "", "", 1, 0, 0 end end
			return nil
		end
		if ITEM_NAMES[id] then return id, "Consumable", "", "", 1, 0, 0 end
		return id, "Weapon", "", "", 1, 2, WEAPON_SUBCLASS[id] or 15
	end,
	GetItemInfo = function(item)
		local id = item
		if type(item) == "string" then
			for itemID, n in pairs(ITEM_NAMES) do if n:lower() == item:lower() then id = itemID end end
		end
		local name = ITEM_NAMES[id]
		if not name then return nil end
		return name, "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[" .. name .. "]|h|r", 1, 1, ITEM_MIN_LEVEL[id] or 1, "", "", 20, "", 999
	end,
	DoesItemExistByID = function(id) return ITEM_NAMES[id] ~= nil or id == 77777 end,
	RequestLoadItemDataByID = function(id) LOAD_REQUESTS[#LOAD_REQUESTS + 1] = id end,
	GetItemIconByID = function() return 999 end,
	GetItemCount = function(item)
		if type(item) == "string" then
			for itemID, n in pairs(ITEM_NAMES) do if n:lower() == item:lower() then item = itemID end end
		end
		return STATE.bag[item] or 0
	end,
}
C_Container = {
	GetContainerNumFreeSlots = function(bag) return STATE.freeSlots[bag + 1] or 0, 0 end,
	GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
	GetContainerItemInfo = function(bag, slot)
		local ids = { 8928, 6265 }
		return { itemID = ids[slot], iconFileID = 500 + slot }
	end,
}
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }

function LoadAddonFile(source, name)
	local f = assert(loadstring(source, "@" .. name))
	f("RemindMeWhen", NS)
end

function Fire(event, ...)
	for _, f in ipairs(FRAMES) do
		local handler = f._scripts and f._scripts.OnEvent
		if handler and f._events and (f._events[event] or event == "ADDON_LOADED" or event == "PLAYER_LOGIN") then
			handler(f, event, ...)
		end
	end
end

STATE.talents = {
	{ name = "Assassination", icon = 201, list = { { "Malice", 301, 0, 5 }, { "Cold Blood", 302, 1, 1 } } },
	{ name = "Combat", icon = 202, list = { { "Precision", 303, 5, 5 } } },
	{ name = "Subtlety", icon = 203, list = { { "Preparation", 304, 0, 1 } } },
}
STATE.race, STATE.faction, STATE.money = "Human", "Alliance", 123456
STATE.totems, STATE.cast, STATE.channel, STATE.combo = {}, nil, nil, 0
STATE.equipped, STATE.cooldowns, STATE.reaction, STATE.targetPlayer = {}, {}, 2, false
STATE.leader, STATE.assist, STATE.pvp, STATE.afk, STATE.dnd = false, false, false, false, false
STATE.mapID, STATE.instanceName, STATE.instanceID = 1429, "Elwynn Forest", 0
STATE.targetHealth = 50

function GetNumTalentTabs() return #STATE.talents end
function GetTalentTabInfo(tab)
	local t = STATE.talents[tab]
	local points = 0
	for _, talent in ipairs(t.list) do points = points + talent[3] end
	return t.name, t.icon, points, "file"
end
function GetNumTalents(tab) return #STATE.talents[tab].list end
function GetTalentInfo(tab, i)
	local talent = STATE.talents[tab].list[i]
	return talent[1], talent[2], 1, 1, talent[3], talent[4]
end
function UnitRace() return "Race", STATE.race end
function UnitFactionGroup() return STATE.faction, STATE.faction end
function GetMoney() return STATE.money end
function GetTotemInfo(slot)
	local t = STATE.totems[slot]
	if not t then return false, "", 0, 0, nil end
	return true, t.name, t.start, t.duration, 400 + slot
end
function UnitCastingInfo() local c = STATE.cast if c then return c.name, "", 1, 0, c.ends * 1000, false, "castGUID", false, c.id end end
function UnitChannelInfo() local c = STATE.channel if c then return c.name, "", 1, 0, c.ends * 1000, false, false, c.id end end
function GetComboPoints() return STATE.combo end
function IsEquippedItem(item) return STATE.equipped[item] or false end
function GetItemCooldown(id) local c = STATE.cooldowns[id] if c then return c[1], c[2], c[3] or 1 end return 0, 0, 1 end
function UnitReaction() return STATE.reaction end
function UnitIsPlayer() return STATE.targetPlayer end
function UnitIsGroupLeader() return STATE.leader end
function UnitIsGroupAssistant() return STATE.assist end
function UnitIsPVP() return STATE.pvp end
function UnitIsAFK() return STATE.afk end
function UnitIsDND() return STATE.dnd end
function GetInstanceInfo() return STATE.instanceName, STATE.instance and "party" or "none", 1, "", 5, 0, false, STATE.instanceID end
C_Map = { GetBestMapForUnit = function() return STATE.mapID end }