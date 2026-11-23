local _, ns = ...
local L = ns.L

local Data = {}
ns.Data = Data

Data.MOUNT_ICON = "Interface\\Icons\\Ability_Mount_RidingHorse"
Data.POISON_ICON = "Interface\\Icons\\Ability_Poisons"
Data.PET_ICON = "Interface\\Icons\\Ability_Hunter_BeastCall"
Data.QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
Data.AMMO_ICON = "Interface\\Icons\\INV_Ammo_Arrow_02"
Data.REPAIR_ICON = "Interface\\Icons\\Trade_BlackSmithing"
Data.BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
Data.VENDOR_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
Data.MAIL_ICON = "Interface\\Icons\\INV_Letter_15"
Data.FOOD_ICON = "Interface\\Icons\\INV_Misc_Food_14"
Data.SHARD_ICON = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
Data.DYNAMIC_GROUP_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
Data.STATIC_GROUP_ICON = "Interface\\Icons\\INV_Misc_Map_01"

Data.BAR_TEXTURES = {
	{ key = "blizzard", label = L["Blizzard"], path = "Interface\\TargetingFrame\\UI-StatusBar" },
	{ key = "flat", label = L["Flat"], path = "Interface\\Buttons\\WHITE8X8" },
	{ key = "raid", label = L["Raid frame"], path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
	{ key = "skill", label = L["Skill bar"], path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}
Data.barTextureByKey = {}
for _, texture in ipairs(Data.BAR_TEXTURES) do Data.barTextureByKey[texture.key] = texture end

local function toSet(...)
	local set = {}
	for i = 1, select("#", ...) do
		for _, id in ipairs((select(i, ...))) do set[id] = true end
	end
	return set
end

-- SpellItemEnchantment IDs as of Forever 1.60.1 (enUS).
Data.poisonEnchants = toSet(
	{ 7, 8, 626, 627, 2630 }, -- Deadly
	{ 323, 324, 325, 623, 624, 625 }, -- Instant
	{ 22, 603 }, -- Crippling
	{ 23, 35, 643 }, -- Mind-numbing
	{ 703, 704, 705, 706 }, -- Wound
	{ 6912 }, -- Leeching
	{ 7254 }, -- Sebacious
	{ 7255 }, -- Numbing
	{ 7256 }, -- Atrophic
	{ 7542, 7651 } -- Occult
)

Data.imbueEnchants = toSet(
	{ 1, 6, 29, 503, 683, 1663, 1664, 7568 }, -- Rockbiter
	{ 3, 4, 5, 523, 1665, 1666, 7567 }, -- Flametongue
	{ 2, 12, 524, 1667, 1668, 7566 }, -- Frostbrand
	{ 283, 284, 525, 1669, 7569 }, -- Windfury
	{ 6910, 6985 } -- Earthliving
)

-- Casting one spell of a group removes the others, which keeps state correct while auras are secret.
local EXCLUSIVE_GROUPS = {
	hunterAspects = {
		13165, 14318, 14319, 14320, 14321, 14322, 25296, -- Hawk
		13163, -- Monkey
		5118, -- Cheetah
		13159, -- Pack
		13161, -- Beast
		20043, 20190, -- Wild
		34074, -- Viper
		61846, 61847, -- Dragonhawk
	},
}

Data.exclusiveGroupOf = {}
for group, ids in pairs(EXCLUSIVE_GROUPS) do
	for _, id in ipairs(ids) do Data.exclusiveGroupOf[id] = group end
end

-- Item lists for click actions, best first.
local ELEMENTAL = "Elemental Sharpening Stone (18262)"
local SHARPENING = "Dense Sharpening Stone (12404), Solid Sharpening Stone (7964), Heavy Sharpening Stone (2871), "
	.. "Coarse Sharpening Stone (2863), Rough Sharpening Stone (2862)"
local WEIGHT = "Dense Weightstone (12643), Solid Weightstone (7965), Heavy Weightstone (3241), "
	.. "Coarse Weightstone (3240), Rough Weightstone (3239)"

local function idSet(text)
	local set = {}
	for id in text:gmatch("%((%d+)%)") do set[tonumber(id)] = true end
	return set
end
Data.sharpOnly = idSet(SHARPENING)
Data.bluntOnly = idSet(WEIGHT)

Data.itemLists = {
	{ key = "instant", label = L["Instant Poison"], items = "Instant Poison VI (8928), Instant Poison V (8927), "
		.. "Instant Poison IV (8926), Instant Poison III (6950), Instant Poison II (6949), Instant Poison (6947)" },
	{ key = "deadly", label = L["Deadly Poison"], items = "Deadly Poison V (20844), Deadly Poison IV (8985), "
		.. "Deadly Poison III (8984), Deadly Poison II (2893), Deadly Poison (2892)" },
	{ key = "wound", label = L["Wound Poison"], items = "Wound Poison IV (10922), Wound Poison III (10921), "
		.. "Wound Poison II (10920), Wound Poison (10918)" },
	{ key = "crippling", label = L["Crippling Poison"], items = "Crippling Poison II (3776), Crippling Poison (3775)" },
	{ key = "mindNumbing", label = L["Mind-numbing Poison"], items = "Mind-numbing Poison III (9186), "
		.. "Mind-numbing Poison II (6951), Mind-numbing Poison (5237)" },
	{ key = "stones", label = L["Sharpening stone or weightstone, whichever fits the weapon"],
		items = ELEMENTAL .. ", " .. SHARPENING .. ", " .. WEIGHT },
	{ key = "sharpening", label = L["Sharpening stones"], items = ELEMENTAL .. ", " .. SHARPENING },
	{ key = "weight", label = L["Weightstones"], items = ELEMENTAL .. ", " .. WEIGHT },
	{ key = "wizardOil", label = L["Wizard oils"], items = "Brilliant Wizard Oil (20749), Wizard Oil (20750), "
		.. "Lesser Wizard Oil (20746), Minor Wizard Oil (20744)" },
	{ key = "manaOil", label = L["Mana oils"], items = "Brilliant Mana Oil (20748), Lesser Mana Oil (20747), Minor Mana Oil (20745)" },
}
Data.itemListByKey = {}
for _, list in ipairs(Data.itemLists) do Data.itemListByKey[list.key] = list end

-- Event triggers: each key fires on any of its game events (and when check passes).
Data.triggers = {
	{ key = "readyCheck", label = L["Ready check"], events = { "READY_CHECK" } },
	{ key = "enterInstance", label = L["Entering an instance"], events = { "PLAYER_ENTERING_WORLD" },
		check = function() return IsInInstance() and true or false end },
	{ key = "zoneChanged", label = L["Zone change"], events = { "ZONE_CHANGED_NEW_AREA" } },
	{ key = "combatStart", label = L["Combat starts"], events = { "PLAYER_REGEN_DISABLED" } },
	{ key = "combatEnd", label = L["Combat ends"], events = { "PLAYER_REGEN_ENABLED" } },
	{ key = "levelUp", label = L["Level up"], events = { "PLAYER_LEVEL_UP" } },
	{ key = "merchant", label = L["Vendor opened"], events = { "MERCHANT_SHOW" } },
	{ key = "mailbox", label = L["Mailbox opened"], events = { "MAIL_SHOW" } },
}
Data.triggersByEvent = {}
for _, trigger in ipairs(Data.triggers) do
	for _, event in ipairs(trigger.events) do
		local list = Data.triggersByEvent[event] or {}
		Data.triggersByEvent[event] = list
		list[#list + 1] = trigger
	end
end

local SOUNDS = {
	{ value = "NONE", label = L["None"] },
	{ value = "RAID_WARNING", label = L["Raid warning"] },
	{ value = "READY_CHECK", label = L["Ready check"] },
	{ value = "ALARM_CLOCK_WARNING_3", label = L["Alarm clock"] },
	{ value = "MAP_PING", label = L["Map ping"] },
	{ value = "TELL_MESSAGE", label = L["Whisper"] },
	{ value = "IG_QUEST_LIST_COMPLETE", label = L["Quest complete"] },
	{ value = "UI_BNET_TOAST", label = L["Toast"] },
}

function Data.SoundChoices()
	local out = {}
	for _, sound in ipairs(SOUNDS) do
		if sound.value == "NONE" or (SOUNDKIT and SOUNDKIT[sound.value]) then out[#out + 1] = sound end
	end
	return out
end
