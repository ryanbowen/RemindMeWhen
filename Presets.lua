local _, ns = ...
local Data, L = ns.Data, ns.L

local Presets = {}
ns.Presets = Presets

local WELL_FED = "Well Fed (19705)"

-- Presets offered under "Add preset". Those marked default are added on first install.
Presets.list = {
	{
		default = true,
		name = L["Mount up"],
		text = L["Mount up!"],
		icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
		delay = 2,
		action = { kind = "mount" },
		conditions = {
			{ type = "combat", negate = true },
			{ type = "mountUsable" },
			{ type = "mounted", negate = true },
		},
	},
	{
		default = true,
		name = L["Rogue: main hand poison missing"],
		text = L["Main hand poison missing"],
		icon = "Interface\\Icons\\Ability_Poisons",
		action = { kind = "weapon", item = Data.itemListByKey.instant.items, slot = 16 },
		conditions = {
			{ type = "class", class = "ROGUE" },
			{ type = "weaponEquipped", slot = 16 },
			{ type = "weaponEnchant", negate = true, slot = 16, kind = "poison" },
		},
	},
	{
		default = true,
		name = L["Rogue: off hand poison missing"],
		text = L["Off hand poison missing"],
		icon = "Interface\\Icons\\Ability_Poisons",
		action = { kind = "weapon", item = Data.itemListByKey.deadly.items, slot = 17 },
		conditions = {
			{ type = "class", class = "ROGUE" },
			{ type = "weaponEquipped", slot = 17 },
			{ type = "weaponEnchant", negate = true, slot = 17, kind = "poison" },
		},
	},
	{
		default = true,
		name = L["Hunter: Aspect of the Pack in combat"],
		text = L["Aspect of the Pack is on!"],
		sound = "RAID_WARNING",
		alert = true,
		action = { kind = "spell", spell = "Aspect of the Hawk (13165)" },
		conditions = {
			{ type = "class", class = "HUNTER" },
			{ type = "combat" },
			{ type = "aura", unit = "player", filter = "HELPFUL", spells = "Aspect of the Pack (13159)" },
		},
	},
	{
		name = L["Hunter: Aspect of the Cheetah in combat"],
		text = L["Aspect of the Cheetah is on!"],
		sound = "RAID_WARNING",
		alert = true,
		action = { kind = "spell", spell = "Aspect of the Hawk (13165)" },
		conditions = {
			{ type = "class", class = "HUNTER" },
			{ type = "combat" },
			{ type = "aura", unit = "player", filter = "HELPFUL", spells = "Aspect of the Cheetah (5118)" },
		},
	},
	{
		name = L["Hunter: pet missing"],
		text = L["Call your pet"],
		delay = 3,
		action = { kind = "spell", spell = "Call Pet (883)" },
		conditions = {
			{ type = "class", class = "HUNTER" },
			{ type = "spellKnown", spells = "Call Pet (883)" },
			{ type = "pet", negate = true },
			{ type = "petDead", negate = true },
			{ type = "mounted", negate = true },
		},
	},
	{
		name = L["Hunter: pet dead"],
		text = L["Revive your pet"],
		action = { kind = "spell", spell = "Revive Pet (982)" },
		conditions = {
			{ type = "class", class = "HUNTER" },
			{ type = "petDead" },
			{ type = "mounted", negate = true },
		},
	},
	{
		name = L["Hunter: pet unhappy"],
		text = L["Feed your pet"],
		action = { kind = "spell", spell = "Feed Pet (6991)" },
		conditions = {
			{ type = "class", class = "HUNTER" },
			{ type = "pet" },
			{ type = "petHappiness", level = 2 },
			{ type = "combat", negate = true },
		},
	},
	{
		name = L["Hunter: low ammo"],
		text = L["Low ammo: {count}"],
		icon = Data.AMMO_ICON,
		conditions = {
			{ type = "class", class = "HUNTER" },
			{ type = "ammo", op = "<", value = 200 },
			{ type = "combat", negate = true },
		},
	},
	{
		name = L["Warlock: demon missing"],
		text = L["Summon your demon"],
		delay = 3,
		action = { kind = "spell", spell = "Summon Imp (688)" },
		conditions = {
			{ type = "class", class = "WARLOCK" },
			{ type = "spellKnown", spells = "Summon Imp (688)" },
			{ type = "pet", negate = true },
			{ type = "mounted", negate = true },
		},
	},
	{
		name = L["Warlock: low soul shards"],
		text = L["Soul shards: {count}"],
		icon = Data.SHARD_ICON,
		conditions = {
			{ type = "class", class = "WARLOCK" },
			{ type = "itemCount", item = "Soul Shard (6265)", op = "<", value = 3 },
			{ type = "combat", negate = true },
		},
	},
	{
		name = L["Shaman: weapon imbue missing"],
		text = L["Weapon imbue missing"],
		action = { kind = "spell", spell = "Rockbiter Weapon (8017)" },
		conditions = {
			{ type = "class", class = "SHAMAN" },
			{ type = "spellKnown", spells = "Rockbiter Weapon (8017)" },
			{ type = "weaponEquipped", slot = 16 },
			{ type = "weaponEnchant", negate = true, slot = 16, kind = "imbue" },
		},
	},
	{
		name = L["Priest: Fortitude missing in group"],
		text = L["Fortitude missing: {missing}"],
		action = { kind = "spell", spell = "Power Word: Fortitude (1243)" },
		conditions = {
			{ type = "class", class = "PRIEST" },
			{ type = "combat", negate = true },
			{ type = "groupBuffMissing", spells = "Power Word: Fortitude (1243), Prayer of Fortitude (21562)" },
		},
	},
	{
		name = L["Mage: Arcane Intellect missing in group"],
		text = L["Arcane Intellect missing: {missing}"],
		action = { kind = "spell", spell = "Arcane Intellect (1459)" },
		conditions = {
			{ type = "class", class = "MAGE" },
			{ type = "combat", negate = true },
			{ type = "groupBuffMissing", spells = "Arcane Intellect (1459), Arcane Brilliance (23028)" },
		},
	},
	{
		name = L["Druid: Mark of the Wild missing in group"],
		text = L["Mark of the Wild missing: {missing}"],
		action = { kind = "spell", spell = "Mark of the Wild (1126)" },
		conditions = {
			{ type = "class", class = "DRUID" },
			{ type = "combat", negate = true },
			{ type = "groupBuffMissing", spells = "Mark of the Wild (1126), Gift of the Wild (21849)" },
		},
	},
	{
		name = L["No food buff in an instance"],
		text = L["Eat something (no Well Fed buff)"],
		icon = Data.FOOD_ICON,
		conditions = {
			{ type = "instance", kind = "any" },
			{ type = "combat", negate = true },
			{ type = "aura", negate = true, unit = "player", filter = "HELPFUL", spells = WELL_FED },
		},
	},
	{
		name = L["Ready check: no food buff"],
		text = L["Ready check - you are not Well Fed"],
		icon = Data.FOOD_ICON,
		sound = "READY_CHECK",
		trigger = "event",
		events = { readyCheck = true },
		duration = 20,
		conditions = {
			{ type = "aura", negate = true, unit = "player", filter = "HELPFUL", spells = WELL_FED },
		},
	},
	{
		name = L["Repair at vendor"],
		text = L["Repair your gear ({count}%)"],
		icon = Data.REPAIR_ICON,
		conditions = {
			{ type = "atMerchant", kind = "repair" },
			{ type = "durability", op = "<", value = 90 },
		},
	},
	{
		name = L["Bags almost full"],
		text = L["Bags almost full: {count} free"],
		icon = Data.BAG_ICON,
		conditions = {
			{ type = "bagSlots", op = "<", value = 3 },
			{ type = "combat", negate = true },
		},
	},
	{
		name = L["Find Herbs tracking off"],
		text = L["Find Herbs is off"],
		action = { kind = "spell", spell = "Find Herbs (2383)" },
		conditions = {
			{ type = "spellKnown", spells = "Find Herbs (2383)" },
			{ type = "tracking", negate = true, spells = "Find Herbs (2383)" },
			{ type = "combat", negate = true },
		},
	},
	{
		name = L["Find Minerals tracking off"],
		text = L["Find Minerals is off"],
		action = { kind = "spell", spell = "Find Minerals (2580)" },
		conditions = {
			{ type = "spellKnown", spells = "Find Minerals (2580)" },
			{ type = "tracking", negate = true, spells = "Find Minerals (2580)" },
			{ type = "combat", negate = true },
		},
	},
}

-- Rewrites spell and item lists with names from the client's language where the data is available.
function Presets:Localize(r)
	ns.Conditions:Walk(r.conditions, function(c)
		if c.spells then c.spells = ns.Spells:Canonicalize(c.spells) end
		if c.item then c.item = ns.Items:Canonicalize(c.item) end
	end)
	local action = r.action
	if action then
		if action.spell then action.spell = ns.Spells:Canonicalize(action.spell) end
		if action.item then action.item = ns.Items:Canonicalize(action.item) end
	end
end

function Presets:Build(preset)
	local r = ns.Compat.CopyTable(preset)
	r.default = nil
	r.enabled = true
	self:Localize(r)
	return r
end
