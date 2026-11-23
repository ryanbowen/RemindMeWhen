local ns = NS
local function check(cond, msg) if not cond then error("FAILED: " .. msg, 2) end print("ok  " .. msg) end

local function shownNames()
	local out = {}
	for id in pairs(ns.Display.shown) do
		local node = ns.Tree:Get(id)
		if node then out[node.name] = true end
	end
	return out
end

local function step(seconds)
	NOW = NOW + (seconds or 0)
	ns.Core:Evaluate()
	return shownNames()
end

local function byName(name)
	local found
	ns.Tree:Walk(function(node) if node.name == name and not found then found = node end end)
	return found
end

local function preset(name, parentID)
	for _, p in ipairs(ns.Presets.list) do
		if p.name == name then return ns.Core:AddReminder(ns.Presets:Build(p), parentID) end
	end
	error("no preset " .. name)
end

local function disableAll()
	for _, r in ipairs(ns.Tree:Reminders()) do r.enabled = false end
end

local function deepCopy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = deepCopy(v) end
	return out
end

-- Fresh install
RemindMeWhenDB = nil
Fire("ADDON_LOADED", "RemindMeWhen")
Fire("PLAYER_LOGIN")
local main = ns.Tree:Get(ns.db.root[1])
check(#ns.db.root == 1 and main.kind == "group" and main.layout == "dynamic" and main.y == 160, "first run seeds a Main dynamic group")
check(#main.children == 4 and #ns.Tree:Reminders() == 4, "four default reminders seeded inside it")
check(ns.Tree:Parent(main.children[1]) == main.id, "parents derived from child lists")
check(#STATE_DRIVERS == 1 and STATE_DRIVERS[1][3] == "[combat] hide; show", "action overlay hides in combat via state driver")

local shown = step(0)
check(not shown["Mount up"], "mount reminder waits for its delay")
shown = step(3)
check(shown["Mount up"], "mount reminder shows when unmounted, out of combat, mount usable")
STATE.mounted = true
shown = step(0)
check(not shown["Mount up"], "mount reminder hides when mounted")
STATE.mounted = false
STATE.indoors = true
shown = step(5)
check(not shown["Mount up"], "mount reminder hidden indoors")
STATE.indoors = false

-- Hunter: Aspect of the Pack in combat, with auras secret in combat
STATE.auras = { { name = "Aspect of the Hawk", spellId = 13165, duration = 0, expirationTime = 0, auraInstanceID = 7 } }
shown = step(0)
check(not shown["Hunter: Aspect of the Pack in combat"], "pack reminder off out of combat")
STATE.auras = { { name = "Aspect of the Pack", spellId = 13159, duration = 0, expirationTime = 0, auraInstanceID = 8 } }
shown = step(0)
STATE.combat, STATE.aurasSecret = true, true
shown = step(0)
check(shown["Hunter: Aspect of the Pack in combat"], "pack reminder uses last known state while auras are secret")
check(#ALERTS > 0 and #PLAYED > 0, "alert and sound fired on appearance")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 13165)
shown = step(0)
check(not shown["Hunter: Aspect of the Pack in combat"], "casting another aspect in combat clears the reminder")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 13159)
shown = step(0)
check(shown["Hunter: Aspect of the Pack in combat"], "casting Pack in combat shows it again")
Fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { SECRET } })
shown = step(0)
check(shown["Hunter: Aspect of the Pack in combat"], "secret removal ids are ignored safely")
check(ns.Actions.pending, "action overlay refresh deferred in combat")
STATE.combat, STATE.aurasSecret = false, false
Fire("PLAYER_REGEN_ENABLED")
check(not ns.Actions.pending, "action overlay refreshed after combat")
STATE.auras = {}
shown = step(0)
check(not shown["Hunter: Aspect of the Pack in combat"], "out of combat, real data takes over")

-- Rogue poisons
STATE.class = "ROGUE"
STATE.weapons[16] = { { hasEnchant = true, enchantType = 2, enchantID = 7, timeLeft = 600000 } }
STATE.weapons[17] = { { hasEnchant = true, enchantType = 1, enchantID = 1643, timeLeft = 600000 } }
shown = step(0)
check(not shown["Rogue: main hand poison missing"], "main hand with deadly poison is fine")
check(shown["Rogue: off hand poison missing"], "off hand with only a sharpening stone needs poison")
STATE.items[17] = nil
shown = step(0)
check(not shown["Rogue: off hand poison missing"], "no off hand weapon, no reminder")
STATE.weapons[16] = {}
shown = step(0)
check(shown["Rogue: main hand poison missing"], "main hand poison missing shows")

-- Click actions
local mh = byName("Rogue: main hand poison missing")
check(ns.Actions:MacroFor(mh) == "/use item:8928\n/use 16", "poison action uses best poison in bags on main hand")
STATE.bag[8928] = nil
check(ns.Actions:MacroFor(mh) == "/use item:8928\n/use 16", "falls back to first listed poison when none in bags")
STATE.bag[8927] = 3
check(ns.Actions:MacroFor(mh) == "/use item:8927\n/use 16", "uses the next rank you actually have")
STATE.bag[8928] = 5
STATE.level = 55
check(ns.Actions:MacroFor(mh) == "/use item:8927\n/use 16", "skips a poison above your level")
STATE.level = 60

local stones = { kind = "weapon", item = ns.Items:Canonicalize(ns.Data.itemListByKey.stones.items), slot = 16 }
local stoneReminder = { action = stones }
check(stones.item:find("^Elemental Sharpening Stone %(18262%), Dense Sharpening Stone %(12404%)"), "stone list canonicalized")
STATE.bag[12404], STATE.bag[12643] = 2, 2
check(ns.Actions:MacroFor(stoneReminder) == "/use item:12404\n/use 16", "dagger gets a sharpening stone")
WEAPON_SUBCLASS[1001] = 4
check(ns.Actions:MacroFor(stoneReminder) == "/use item:12643\n/use 16", "mace gets a weightstone")
WEAPON_SUBCLASS[1001] = 13
check(ns.Actions:MacroFor(stoneReminder) == "/use item:12643\n/use 16", "fist weapon gets a weightstone")
STATE.bag[18262] = 1
WEAPON_SUBCLASS[1001] = 4
check(ns.Actions:MacroFor(stoneReminder) == "/use item:18262\n/use 16", "elemental stone preferred on any weapon")
STATE.level = 45
check(ns.Actions:MacroFor(stoneReminder) == "/use item:12643\n/use 16", "elemental stone skipped below level 50")
STATE.level = 60
stones.kind = "item"
check(ns.Actions:MacroFor(stoneReminder) == "/use item:18262", "use-item action ignores weapon fit")
WEAPON_SUBCLASS[1001] = nil
STATE.bag[18262], STATE.bag[12404], STATE.bag[12643] = nil, nil, nil
local button
for _, b in ipairs(ns.Actions.buttons) do if b.reminder == mh and b._shown then button = b end end
check(button and button._attr.macrotext1 == "/use item:8928\n/use 16" and button._attr.type1 == "macro", "secure button placed over the reminder with macro")
local mount = byName("Mount up")
check(ns.Actions:MacroFor(mount) == "/run RemindMeWhen_SummonMount()", "mount action summons random favorite")
RemindMeWhen_SummonMount()
check(STATE.summoned[1] == 1, "random favorite mount summoned")
local pack = byName("Hunter: Aspect of the Pack in combat")
check(ns.Actions:MacroFor(pack) == "/cast Aspect of the Hawk", "spell action casts by resolved name")
check(ns.Actions:Describe(mh):find("Instant Poison VI"), "action description names the item")
pack.action = { kind = "macro", macro = "/say hi" }
ns.Actions:Normalize(pack)
check(ns.Actions:MacroFor(pack) == "/say hi", "macro action")
pack.action.kind = "spell"

-- Snooze menu choices
ns.Core:Snooze(mh)
shown = step(0)
check(not shown["Rogue: main hand poison missing"], "snoozed until conditions clear")
STATE.weapons[16] = { { hasEnchant = true, enchantType = 2, enchantID = 7, timeLeft = 600000 } }
step(0)
STATE.weapons[16] = {}
shown = step(0)
check(shown["Rogue: main hand poison missing"], "clear-snooze ends once conditions cleared")
ns.Core:Snooze(mh, 300)
shown = step(0)
check(not shown["Rogue: main hand poison missing"] and ns.db.snoozes[mh.id] == WALL + 300, "timed snooze stored with wall clock")
WALL = WALL + 301
shown = step(0)
check(shown["Rogue: main hand poison missing"] and ns.db.snoozes[mh.id] == nil, "timed snooze expires")
ns.Core:Snooze(mh, "zone")
shown = step(0)
check(not shown["Rogue: main hand poison missing"], "zone snooze active")
Fire("ZONE_CHANGED_NEW_AREA")
shown = step(0)
check(shown["Rogue: main hand poison missing"], "zone snooze cleared on zone change")
ns.Core:Snooze(mh, "session")
ns.Core:Snooze(mh, 600)
shown = step(0)
check(not shown["Rogue: main hand poison missing"], "session snooze active")
ns.Core:ClearSnoozes()
shown = step(0)
check(shown["Rogue: main hand poison missing"], "clear snoozes shows everything again")

-- Repeating sound
mh.sound, mh.repeatSound = "RAID_WARNING", 5
local before = #PLAYED
step(2)
check(#PLAYED == before, "no repeat before interval")
step(4)
check(#PLAYED == before + 1, "sound repeats after interval")
mh.repeatSound = 0

-- Per-character switch
mh.disabledFor = { ["Tester-Realm"] = true }
shown = step(0)
check(not shown["Rogue: main hand poison missing"] and not ns.Core:IsEnabledHere(mh), "disabled on this character")
mh.disabledFor = nil
disableAll()

-- Nested condition groups
STATE.class = "HUNTER"
local grouped = ns.Core:AddReminder({
	name = "Grouped", conditions = {
		{ type = "combat" },
		{ type = "group", match = "ANY", conditions = {
			{ type = "aura", unit = "player", filter = "HELPFUL", spells = "Aspect of the Pack (13159)" },
			{ type = "aura", unit = "player", filter = "HELPFUL", spells = "Aspect of the Cheetah (5118)" },
		} },
	},
})
check(ns.Tree:Parent(grouped.id) == ns.Tree.ROOT and grouped.y == 120, "new reminder without a target goes to the top level")
STATE.combat = true
STATE.auras = { { name = "Aspect of the Cheetah", spellId = 5118, duration = 0, expirationTime = 0, auraInstanceID = 11 } }
shown = step(0)
check(shown["Grouped"], "combat AND (Pack OR Cheetah) true with Cheetah")
STATE.auras = {}
shown = step(0)
check(not shown["Grouped"], "group false when neither aura")
grouped.conditions[2].negate = true
shown = step(0)
check(shown["Grouped"], "negated group")
STATE.combat = false
check(#ns.Conditions:TypeChoices(2) == #ns.Conditions.order + 1 and #ns.Conditions:TypeChoices(3) == #ns.Conditions.order, "groups allowed only up to 3 levels")
grouped.enabled = false

-- "No enchant, or under 1 minute left in combat, or under 10 minutes left out of combat"
local refresh = ns.Core:AddReminder({
	name = "Refresh enchant", match = "ANY", conditions = {
		{ type = "group", match = "ALL", conditions = {
			{ type = "combat" },
			{ type = "weaponEnchant", negate = true, slot = 16, kind = "any", minLeft = 60 },
		} },
		{ type = "group", match = "ALL", conditions = {
			{ type = "combat", negate = true },
			{ type = "weaponEnchant", negate = true, slot = 16, kind = "any", minLeft = 600 },
		} },
	},
})
local function enchantLeft(seconds)
	STATE.weapons[16] = seconds and { { hasEnchant = true, enchantType = 2, enchantID = 7, timeLeft = seconds * 1000 } } or {}
	Fire("WEAPON_ENCHANT_CHANGED")
end
enchantLeft(nil)
check(step(0)["Refresh enchant"], "refresh: no enchant shows")
enchantLeft(1200)
check(not step(0)["Refresh enchant"], "refresh: 20 min left out of combat hides")
enchantLeft(300)
check(step(0)["Refresh enchant"], "refresh: 5 min left out of combat shows")
STATE.combat = true
check(not step(0)["Refresh enchant"], "refresh: 5 min left in combat hides")
enchantLeft(30)
check(step(0)["Refresh enchant"], "refresh: 30 s left in combat shows")
STATE.combat = false
enchantLeft(nil)
refresh.enabled = false

-- Placeholders and countdown
local timed = ns.Core:AddReminder({
	name = "Timed", text = "Hawk {left} for {name}, {count} {missing} {bogus}",
	conditions = { { type = "aura", unit = "player", filter = "HELPFUL", spells = "13165" } },
})
STATE.auras = { { name = "Aspect of the Hawk", spellId = 13165, duration = 120, expirationTime = NOW + 90, auraInstanceID = 12 } }
shown = step(0)
check(shown["Timed"], "timed aura reminder shows")
local text = ns.Display:FormatText(timed)
check(text == "Hawk 1:30 for Tester, ? ? {bogus}", "placeholders filled: " .. text)
check(ns.Display:FormatText({ text = "Poison {left:missing}, {count:} {left x}" }, { expires = NOW + 75 }) == "Poison 1:15,  {left x}", "fallback ignored when the value is known")
check(ns.Display:FormatText({ text = "Poison {left:missing}" }, {}) == "Poison missing", "fallback shown when the value is unknown")
do
	local quiet = ns.Core:AddReminder({ name = "Quiet one", text = "", alert = true, trigger = "event", events = {}, conditions = {} })
	ns.Core:Test()
	step(0)
	local qItem = ns.Display.items[quiet.id]
	check(qItem and qItem.text._text == "" and qItem._width == ns.Tree:Visual(quiet, "iconSize"), "empty text shows no text and no text space")
	local alertCount = #ALERTS
	ns.Display:Announce(quiet)
	check(#ALERTS == alertCount + 1 and ALERTS[#ALERTS] == "Quiet one", "alerts with empty text use the name")
	quiet.visual.style = "bar"
	step(0)
	check(qItem.bar.text._text == "", "empty text on a bar")
	ns.Core:DeleteNode(quiet.id)
	step(0)
end
local item = ns.Display.items[timed.id]
check(item and item.cooldown._cd and item.cooldown._cd[2] == 120 and item.timer._text == "1:30", "cooldown sweep and timer text")
timed.visual.sweep, timed.visual.timer = false, false
step(0)
check(item.cooldown._cd[2] == 0 and not item.timer._shown, "sweep and timer can be switched off per reminder")
timed.enabled = false

-- Counts, target, vendor, pet and group buff conditions
local C = ns.Conditions
local function eval(c) ns.Tracker:BeginPass(); return C:Evaluate(C:Normalize(c), {}) end
local vars = {}
check(C:Evaluate(C:Normalize({ type = "ammo", op = "<", value = 200 }), vars) == true and vars.count == 150, "ammo count with {count}")
vars = {}
check(C:Evaluate(C:Normalize({ type = "durability", op = "<", value = 30 }), vars) == true and vars.count == 20, "lowest durability")
check(eval({ type = "bagSlots", op = "<", value = 3 }) == true, "free bag slots")
check(eval({ type = "restedXP", op = ">", value = 40 }) == true, "rested XP percent")
STATE.target = true
check(eval({ type = "targetClass", kind = "elite" }) == true and eval({ type = "targetClass", kind = "boss" }) == false, "target classification")
STATE.targetLevel = -1
check(eval({ type = "targetClass", kind = "boss" }) == true, "level -1 target is a boss")
STATE.target = false
check(eval({ type = "atMerchant", kind = "repair" }) == false, "not at vendor")
Fire("MERCHANT_SHOW")
check(eval({ type = "atMerchant", kind = "repair" }) == true, "at repair vendor")
Fire("MERCHANT_CLOSED")
check(eval({ type = "atMerchant" }) == false, "vendor closed")
Fire("MAIL_SHOW")
check(eval({ type = "atMailbox" }) == true, "at mailbox")
Fire("MAIL_CLOSED")
STATE.pet, STATE.happiness = true, 2
check(eval({ type = "petHappiness", level = 2 }) == true and eval({ type = "petHappiness", level = 1 }) == false, "pet happiness levels")
STATE.petHealth = 0
STATE.petDead = true
Fire("UNIT_HEALTH", "pet")
STATE.pet = false
Fire("UNIT_PET", "player")
check(eval({ type = "petDead" }) == true, "dead pet remembered after the unit disappears")
STATE.pet, STATE.petDead, STATE.petHealth = true, false, 100
Fire("UNIT_PET", "player")
check(eval({ type = "petDead" }) == false, "live pet clears death")
STATE.pet = false

STATE.group = { party1 = { name = "Ann" }, party2 = { name = "Bob" } }
STATE.auras = { { name = "Power Word: Fortitude", spellId = 1243, duration = 0, expirationTime = 0, auraInstanceID = 20 } }
STATE.unitAuras = { party1 = { { name = "Prayer of Fortitude", spellId = 21562, duration = 0, expirationTime = 0, auraInstanceID = 21 } } }
vars = {}
ns.Tracker:BeginPass()
local fort = C:Normalize({ type = "groupBuffMissing", spells = "Power Word: Fortitude (1243), Prayer of Fortitude (21562)" })
check(C:Evaluate(fort, vars) == true and vars.missing == "Bob", "group buff missing lists Bob: " .. tostring(vars.missing))
STATE.unitAuras.party2 = { { name = "Power Word: Fortitude", spellId = 10938, duration = 0, expirationTime = 0, auraInstanceID = 22 } }
ns.Tracker:BeginPass()
check(C:Evaluate(fort, {}) == false, "other rank by name counts as buffed")
STATE.aurasSecret = true
ns.Tracker:BeginPass()
check(C:Evaluate(fort, {}) == nil, "unknown while auras are secret")
STATE.aurasSecret = false
STATE.group, STATE.unitAuras, STATE.auras = {}, {}, {}

check(eval({ type = "group", kind = "group" }) == false, "party/raid condition is not a nested group when solo")
STATE.group = { party1 = { name = "Ann" } }
check(eval({ type = "group", kind = "party" }) == true and eval({ type = "group", kind = "raid" }) == false, "party/raid condition in a party")
STATE.group = {}

-- Talents, specialization, character
check(eval({ type = "talent", talent = "Cold Blood" }) == true and eval({ type = "talent", talent = "Malice" }) == false
	and eval({ type = "talent" }) == false, "talent known needs a point in it")
local talentMenu = C.types.talent.params[1].choices()
check(#talentMenu == 3 and talentMenu[1].label == "Assassination" and talentMenu[1].children[2].value == "Cold Blood",
	"talent picker groups talents by tree")
check(eval({ type = "spec", tree = 2 }) == true and eval({ type = "spec", tree = 1 }) == false, "spec is the tree with the most points")
STATE.talents[1].list[1][3] = 4
check(eval({ type = "spec", tree = 1 }) == true and eval({ type = "spec", tree = 2 }) == true, "tied trees both count")
STATE.talents[1].list[1][3], STATE.talents[1].list[2][3], STATE.talents[2].list[1][3] = 0, 0, 0
check(eval({ type = "spec", tree = 1 }) == false and eval({ type = "spec", tree = 3 }) == false, "no points spent, no spec")
STATE.talents[1].list[2][3], STATE.talents[2].list[1][3] = 1, 5
check(eval({ type = "race", race = "Human" }) == true and eval({ type = "race", race = "Scourge" }) == false, "race")
check(eval({ type = "faction", faction = "Alliance" }) == true and eval({ type = "faction", faction = "Horde" }) == false, "faction")
vars = {}
check(C:Evaluate(C:Normalize({ type = "money", op = "<", value = 20 }), vars) == true and vars.count == 12, "money in gold")
check(eval({ type = "money", op = ">=", value = 12.3 }) == true, "money compares fractions of gold")

-- Gear and items
STATE.equipped[6265] = true
check(eval({ type = "itemEquipped", item = "Instant Poison VI, Soul Shard (6265)" }) == true
	and eval({ type = "itemEquipped", item = "8928" }) == false and eval({ type = "itemEquipped" }) == false, "item equipped")
STATE.equipped = {}
check(eval({ type = "itemReady", item = "Soul Shard (6265)" }) == true, "item off cooldown")
check(eval({ type = "itemReady", item = "Deadly Poison V (20844)" }) == false, "item you do not have is not ready")
STATE.cooldowns[6265] = { NOW - 10, 60 }
vars = {}
check(C:Evaluate(C:Normalize({ type = "itemReady", item = "Soul Shard (6265)" }), vars) == false and vars.expires == NOW + 50
	and vars.duration == 60, "item on cooldown sets {left}")
STATE.cooldowns[6265] = { NOW, 1 }
check(eval({ type = "itemReady", item = "Soul Shard (6265)" }) == true, "global cooldown does not count")
STATE.cooldowns[6265] = { 0, 0, 0 }
check(eval({ type = "itemReady", item = "Soul Shard (6265)" }) == false, "cooldown waiting to start is not ready")
STATE.cooldowns = {}
STATE.equipped[20844] = true
check(eval({ type = "itemReady", item = "Deadly Poison V (20844)" }) == true, "equipped-only item counts as owned")
STATE.equipped = {}

-- You
STATE.combo = 3
vars = {}
check(C:Evaluate(C:Normalize({ type = "comboPoints", op = ">=", value = 3 }), vars) == true and vars.count == 3 and vars.max == 5, "combo points")
check(eval({ type = "comboPoints", op = ">=", value = 5 }) == false, "not enough combo points")
STATE.totems[2] = { name = "Stoneskin Totem IV", start = NOW - 5, duration = 120 }
vars = {}
check(C:Evaluate(C:Normalize({ type = "totem" }), vars) == true and vars.expires == NOW + 115, "any totem active with {left}")
check(eval({ type = "totem", element = 1 }) == false and eval({ type = "totem", element = 2, names = "stoneskin" }) == true
	and eval({ type = "totem", names = "Searing" }) == false, "totem element and name filters")
STATE.totems = {}
STATE.cast = { name = "Frostbolt", id = 116, ends = NOW + 2 }
vars = {}
check(C:Evaluate(C:Normalize({ type = "casting" }), vars) == true and vars.expires == NOW + 2, "casting sets {left}")
check(eval({ type = "casting", kind = "channel" }) == false and eval({ type = "casting", spells = "Call Pet (883)" }) == false,
	"cast type and spell filters")
STATE.cast, STATE.channel = nil, { name = "Call Pet", id = 883, ends = NOW + 3 }
check(eval({ type = "casting", kind = "channel", spells = "Call Pet (883)" }) == true, "channeling a listed spell")
STATE.channel = nil
STATE.afk = true
check(eval({ type = "status", kind = "afk" }) == true and eval({ type = "status", kind = "pvp" }) == false, "AFK and PvP status")
STATE.afk = false

-- Target and group
STATE.target, STATE.reaction = true, 4
check(eval({ type = "target", kind = "neutral" }) == true and eval({ type = "target", kind = "hostile" }) == false, "target reaction")
STATE.targetPlayer = true
check(eval({ type = "target", kind = "player" }) == true and eval({ type = "target", kind = "npc" }) == false, "target is a player")
STATE.targetPlayer, STATE.targetHealth = false, 15
vars = {}
check(C:Evaluate(C:Normalize({ type = "targetHealth", op = "<", value = 20 }), vars) == true and vars.count == 15, "target health percent")
STATE.target = false
check(eval({ type = "targetHealth", op = "<", value = 20 }) == false, "no target, no health")
STATE.targetHealth = 50
check(eval({ type = "groupSize", op = "<=", value = 1 }) == true and eval({ type = "groupLeader" }) == false, "solo is a group of one, not a leader")
STATE.group, STATE.assist = { party1 = { name = "Ann" } }, true
check(eval({ type = "groupSize", op = ">=", value = 2 }) == true and eval({ type = "groupLeader", kind = "leader" }) == false
	and eval({ type = "groupLeader", kind = "assist" }) == true, "group size and assistant")
STATE.group, STATE.assist = {}, false

-- Location
check(eval({ type = "zone", zones = "1429" }) == true and eval({ type = "zone", zones = "1430" }) == false, "zone by map ID")
STATE.instance, STATE.instanceName, STATE.instanceID = true, "The Deadmines", 36
check(eval({ type = "instance", names = "deadmines" }) == true and eval({ type = "instance", names = "36" }) == true
	and eval({ type = "instance", names = "Stockade, 34" }) == false, "instance by name or ID")
STATE.instance, STATE.instanceName, STATE.instanceID = false, "Elwynn Forest", 0
check(eval({ type = "encounter" }) == false, "no boss fight")
Fire("ENCOUNTER_START", 1144, "Edwin VanCleef", 1, 5)
check(eval({ type = "encounter" }) == true and eval({ type = "encounter", names = "vancleef" }) == true
	and eval({ type = "encounter", names = "1144" }) == true and eval({ type = "encounter", names = "Ragnaros, 672" }) == false,
	"boss encounter by name or ID")
Fire("ENCOUNTER_END", 1144, "Edwin VanCleef", 1, 5, 1)
check(eval({ type = "encounter" }) == false, "encounter ends")
Fire("ENCOUNTER_START", 1144, "Edwin VanCleef", 1, 5)
Fire("PLAYER_ENTERING_WORLD")
check(eval({ type = "encounter" }) == false, "a loading screen ends the encounter")
for key in pairs(C.types) do
	local listed = false
	for _, category in ipairs(C.CATEGORIES) do
		for _, typeKey in ipairs(category.types) do listed = listed or typeKey == key end
	end
	check(listed or key == C.GROUP, "condition type is in a category: " .. key)
end
local legacy = C:Normalize({ type = "group", match = "ANY", conditions = { { type = "combat" } } })
check(legacy.type == C.GROUP and C:IsGroup(legacy), "legacy nested group migrated")
local legacyString = ns.Serialize.Encode({ version = 1, reminders = { { name = "Legacy", anchor = 2, flash = false, conditions = {
	{ type = "group", match = "ANY", conditions = { { type = "combat" } } }, { type = "group", kind = "raid" } } } } })
local legacyList = ns.Serialize.Import(legacyString)
check(legacyList and legacyList[1].conditions[1].type == C.GROUP and legacyList[1].conditions[2].type == "group"
	and legacyList[1].conditions[2].kind == "raid", "legacy export string imports groups and party conditions correctly")
check(legacyList[1].kind == "reminder" and legacyList[1].anchor == nil and legacyList[1].flash == false, "v1 strings import as plain reminders")

vars = {}
check(C:Evaluate(C:Normalize({ type = "itemCount", item = "Soul Shard (6265)", op = "<", value = 3 }), vars) == true and vars.count == 2, "item count sums with {count}")

-- Event triggers
local ready = preset("Ready check: no food buff")
shown = step(0)
check(not shown["Ready check: no food buff"], "event reminder hidden before its event")
Fire("READY_CHECK")
shown = step(0)
check(shown["Ready check: no food buff"], "ready check shows the reminder")
STATE.auras = { { name = "Well Fed", spellId = 19710, duration = 900, expirationTime = NOW + 900, auraInstanceID = 30 } }
shown = step(0)
check(not shown["Ready check: no food buff"], "conditions still apply (any Well Fed buff by name)")
STATE.auras = {}
shown = step(25)
check(not shown["Ready check: no food buff"], "event window ends after its duration")
local zone = ns.Core:AddReminder({ name = "Instance", trigger = "event", events = { enterInstance = true }, duration = 5, conditions = {} })
Fire("PLAYER_ENTERING_WORLD")
shown = step(0)
check(not shown["Instance"], "enterInstance ignores the open world")
STATE.instance = true
Fire("PLAYER_ENTERING_WORLD")
shown = step(0)
check(shown["Instance"], "enterInstance fires inside an instance, and empty conditions always show")
STATE.instance = false
ns.Core:Snooze(zone)
shown = step(0)
check(not shown["Instance"], "snoozing an event reminder hides it")
ready.enabled, zone.enabled = false, false

-- Layout geometry
local Layout = ns.Layout
local function near(a, b) return math.abs(a - b) < 0.01 end
local function centersAre(result, expected)
	for i, c in ipairs(expected) do
		if not (near(result.centers[i][1], c[1]) and near(result.centers[i][2], c[2])) then return false end
	end
	return true
end
local two = { { w = 40, h = 40 }, { w = 40, h = 40 } }
local res = Layout.Dynamic(two, { grow = "DOWN", spacing = 6 })
check(res.anchor == "TOP" and res.width == 40 and res.height == 86 and centersAre(res, { { 0, -20 }, { 0, -66 } }), "grow down from the top")
res = Layout.Dynamic(two, { grow = "UP", spacing = 6 })
check(res.anchor == "BOTTOM" and centersAre(res, { { 0, 20 }, { 0, 66 } }), "grow up from the bottom")
res = Layout.Dynamic(two, { grow = "RIGHT", spacing = 6 })
check(res.anchor == "LEFT" and centersAre(res, { { 20, 0 }, { 66, 0 } }), "grow right from the left")
res = Layout.Dynamic(two, { grow = "LEFT", spacing = 6 })
check(res.anchor == "RIGHT" and centersAre(res, { { -20, 0 }, { -66, 0 } }), "grow left from the right")
res = Layout.Dynamic(two, { grow = "HCENTER", spacing = 6 })
check(res.anchor == "CENTER" and centersAre(res, { { -23, 0 }, { 23, 0 } }), "centered row")
res = Layout.Dynamic({ { w = 40, h = 40 }, { w = 40, h = 40 }, { w = 40, h = 40 } }, { grow = "DOWN", spacing = 6, wrap = 2 })
check(res.anchor == "TOPLEFT" and res.width == 86 and centersAre(res, { { 20, -20 }, { 20, -66 }, { 66, -20 } }), "wrapped columns go right")
res = Layout.Dynamic({ { w = 40, h = 40 }, { w = 100, h = 40 } }, { grow = "DOWN", spacing = 0, align = "LEFT" })
check(res.anchor == "TOPLEFT" and centersAre(res, { { 20, -20 }, { 50, -60 } }), "left aligned column")
res = Layout.Dynamic({ { w = 40, h = 40 }, { w = 100, h = 40 } }, { grow = "DOWN", spacing = 0, align = "RIGHT" })
check(res.anchor == "TOPRIGHT" and centersAre(res, { { -20, -20 }, { -50, -60 } }), "right aligned column")
local w, h, ix, iy = Layout.Box(40, 50, 16, true, "RIGHT")
check(w == 98 and h == 40 and ix == -29 and iy == 0, "text right: icon left of the box center")
w, h, ix, iy = Layout.Box(40, 50, 16, true, "TOP")
check(w == 50 and h == 60 and ix == 0 and iy == -10, "text above: icon below the box center")
check(select(1, Layout.Box(40, 50, 16, false, "RIGHT")) == 40, "no text: box is the icon")
local sorted = Layout.Sort({ { order = 1, name = "b", expires = nil }, { order = 2, name = "a", expires = 50 }, { order = 3, name = "c", expires = 20 } }, "timeLeft")
check(sorted[1].order == 3 and sorted[2].order == 2 and sorted[3].order == 1, "sort by time left, unknown last")
sorted = Layout.Sort(sorted, "name")
check(sorted[1].name == "a" and sorted[3].name == "c", "sort by name")

-- Tree rules
local Tree, Core = ns.Tree, ns.Core
local static = Core:AddGroup("static", nil, nil, "Static")
local dyn = Core:AddGroup("dynamic", static.id, nil, "Inner dynamic")
check(Tree:Parent(dyn.id) == static.id and Tree:GroupDepth(dyn.id) == 2, "dynamic group inside a static group")
local inner = Core:AddGroup("static", dyn.id)
check(Tree:Parent(inner.id) == dyn.id and Tree:GroupDepth(inner.id) == 3, "a group can go in a dynamic group")
local s2 = Core:AddGroup("static", static.id, nil, "Level 2")
local s3 = Core:AddGroup("static", s2.id, nil, "Level 3")
check(not Tree:CanPlace({ kind = "group", children = {} }, s3.id), "a fourth group level is refused")
check(not Tree:CanPlace(static, s2.id), "a group cannot move into its own subtree")
check(not Core:MoveNode(inner.id, s3.id), "moving a group past the depth limit fails")
check(Core:MoveNode(inner.id, s2.id) and Tree:Parent(inner.id) == s2.id, "moving a group within the limit works")
Core:SetLayout(s2, "dynamic")
check(s2.layout == "dynamic", "a group holding groups can become dynamic")
Core:SetLayout(s2, "static")
check(not Core:MoveNode(s3.id, s2.id, 1) or Tree:ChildList(s2.id)[1] == s3.id, "reorder within a group")
local list = Tree:ChildList(s2.id)
local firstID = list[1]
check(Core:Nudge(firstID, 1) and Tree:ChildList(s2.id)[2] == firstID, "nudge moves among siblings")
check(not Core:Nudge(firstID, 1), "nudge stops at the end")

-- Group gating and inherited placeholders
local gate = Core:AddGroup("dynamic", nil, nil, "Combat only")
gate.conditions = { C:Normalize({ type = "combat" }) }
local gated = Core:AddReminder({ name = "Gated", text = "{left}", conditions = { { type = "aura", unit = "player", filter = "HELPFUL", spells = "13165" } } }, gate.id)
STATE.auras = { { name = "Aspect of the Hawk", spellId = 13165, duration = 60, expirationTime = NOW + 30, auraInstanceID = 50 } }
shown = step(0)
check(not shown["Gated"] and Core.state[gated.id].raw == true, "closed group hides its reminder but still evaluates it")
local gateFrame = ns.Display.groups[gate.id]
check(Core.state[gate.id].active == false and not (gateFrame and gateFrame._shown), "closed group with nothing showing is hidden")
STATE.combat, STATE.aurasSecret = true, true
shown = step(0)
check(shown["Gated"] and Core.state[gate.id].active, "in combat with secret auras the warmed-up state is used")
STATE.aurasSecret = false
gate.conditions = { C:Normalize({ type = "combat" }), C:Normalize({ type = "aura", unit = "player", filter = "HELPFUL", spells = "13165" }) }
gated.conditions = {}
gated.text = "Hawk {left}"
shown = step(0)
check(shown["Gated"] and ns.Display:FormatText(gated) == "Hawk 30s", "a reminder without conditions follows its group and uses its placeholders")
local loose = Core:AddReminder({ name = "Loose", conditions = {} })
check(not step(0)["Loose"], "a top-level state reminder without conditions never shows")
Core:DeleteNode(loose.id)
gate.enabled = false
shown = step(0)
check(not shown["Gated"] and not Core:IsEnabledHere(gated), "disabling a group disables what is inside")
gate.enabled = true
gate.disabledFor = { ["Tester-Realm"] = true }
check(not Core:IsEnabledHere(gated) and Core:IsOwnEnabledHere(gated), "per-character switch on a group")
gate.disabledFor = nil
STATE.combat = false
STATE.auras = {}

-- Dynamic group display
local dg = Core:AddGroup("dynamic", nil, nil, "Display test")
dg.x, dg.y, dg.spacing = 0, 0, 10
local d1 = Core:AddReminder({ name = "D1", text = "", conditions = { { type = "combat", negate = true } } }, dg.id)
local d2 = Core:AddReminder({ name = "D2", text = "", conditions = { { type = "combat", negate = true } } }, dg.id)
dg.visual.iconSize = 30
d2.visual.iconSize = 50
dg.visual.showText = false
shown = step(0)
check(shown["D1"] and shown["D2"], "reminders in a dynamic group show")
local i1, i2, gframe = ns.Display.items[d1.id], ns.Display.items[d2.id], ns.Display.groups[dg.id]
check(i1.icon._width == 30 and i2.icon._width == 50, "group visual inherited, reminder override wins")
local p1, p2 = i1._points[1], i2._points[1]
check(p1[2] == gframe and p1[3] == "TOP" and near(p1[5], -15) and near(p2[5], -30 - 10 - 25), "items stacked down from the group's top")
check(gframe._width == 50 and gframe._height == 90, "group frame sized to its contents")
check(gframe._points[1][1] == "TOP" and gframe._points[1][2] == UIParent, "group anchored at its grow point")
dg.sort = "name"
d1.name, d2.name = "Zed", "Abe"
step(0)
check(ns.Display.items[d2.id]._points[1][5] > ns.Display.items[d1.id]._points[1][5], "sorted by name")
d1.name, d2.name = "D1", "D2"
ns.db.display.visual.iconSize = 20
dg.visual.iconSize = nil
check(Tree:Visual(d1, "iconSize") == 20 and Tree:InheritedVisual(d2, "iconSize") == 20, "global visual default used when no group sets it")
ns.db.display.visual.iconSize = nil
check(Tree:Visual(d1, "iconSize") == 40, "built-in default last")

-- Groups inside a dynamic group
do
	local function always(name, parentID)
		return Core:AddReminder({ name = name, text = "", conditions = { { type = "combat", negate = true } } }, parentID)
	end
	local outer = Core:AddGroup("dynamic", nil, nil, "Outer")
	outer.x, outer.y, outer.spacing, outer.visual.iconSize, outer.visual.showText = 0, 0, 10, 30, false
	local o1 = always("B", outer.id)
	local innerDyn = Core:AddGroup("dynamic", outer.id, nil, "C")
	innerDyn.grow, innerDyn.spacing = "RIGHT", 0
	local n1, n2 = always("n1", innerDyn.id), always("n2", innerDyn.id)
	local innerStatic = Core:AddGroup("static", outer.id, nil, "A")
	innerStatic.scale = 2
	local s1 = always("s1", innerStatic.id)
	s1.x, s1.y = 40, 0
	shown = step(0)
	local D = ns.Display
	local oframe, dframe, sframe2 = D.groups[outer.id], D.groups[innerDyn.id], D.groups[innerStatic.id]
	check(shown["B"] and shown["n1"] and shown["n2"] and shown["s1"], "reminders in nested groups show")
	check(oframe._width == 60 and oframe._height == 110, "outer group sized to hold the child groups: " .. oframe._width .. "x" .. oframe._height)
	local dp, sp = dframe._points[1], sframe2._points[1]
	check(dp[1] == "LEFT" and dp[2] == oframe and dp[3] == "TOP" and near(dp[4], -30) and near(dp[5], -55),
		"a dynamic child group takes one slot, placed at its own anchor")
	check(D.items[n2.id]._points[1][2] == dframe and near(D.items[n2.id]._points[1][4], 45), "the child group arranges its own reminders")
	check(sp[1] == "CENTER" and sp[2] == oframe and near(sp[4], -40) and near(sp[5], -95) and sframe2._scale == 1,
		"a static child group is placed by the box of what it shows, at scale 1")
	check(D.items[s1.id]._points[1][2] == sframe2 and near(D.items[s1.id]._points[1][4], 40), "reminders keep their spot inside the static child")
	outer.sort = "name"
	step(0)
	check(near(sframe2._points[1][5], -15) and near(D.items[o1.id]._points[1][5], -55), "child groups sort by name with the reminders")
	outer.sort = "order"
	STATE.combat = true
	shown = step(0)
	check(not shown["B"] and not dframe._shown and not oframe._shown, "nothing showing hides the nested groups")
	STATE.combat = false
	n2.conditions = { { type = "combat" } }
	shown = step(0)
	check(shown["n1"] and not shown["n2"] and dframe._width == 30 and oframe._height == 110, "a child group shrinks to what it shows")
	n1.conditions = { { type = "combat" } }
	shown = step(0)
	check(not dframe._shown and oframe._height == 70, "a child group with nothing showing gives up its slot")
	n1.conditions, n2.conditions = { { type = "combat", negate = true } }, { { type = "combat", negate = true } }
	ns.db.display.locked = false
	step(0)
	check(oframe._width == 66 and oframe._height == 110, "in edit mode a static child also holds its handle: " .. oframe._width .. "x" .. oframe._height)
	local ni = D.items[n1.id]
	ni._scripts.OnDragStart(ni)
	check(D.dragging and D.dragging.id == outer.id and D.dragging.frame == oframe, "dragging inside nested dynamic groups moves the outermost one")
	ni._scripts.OnDragStop(ni)
	local si = D.items[s1.id]
	si._scripts.OnDragStart(si)
	check(D.dragging and D.dragging.id == s1.id, "a reminder in a static child still moves on its own")
	D.dragging = nil
	ns.db.display.locked = true
	Core:DeleteNode(outer.id)
	step(0)
end

-- Bars
do
local savedAuras = STATE.auras
dg.visual.style, dg.visual.barWidth, dg.visual.barHeight = "bar", 200, 20
d2.visual.iconSize = 50
step(0)
check(i1.bar._shown and not i1.text._shown and not i1.timer._shown and i1._width == 200 and i1._height == 20, "bar style and size inherited from the group")
check(gframe._width == 200 and gframe._height == 50, "dynamic group stacks bars: " .. gframe._width .. "x" .. gframe._height)
check(i1.icon._width == 20 and i1.icon._points[1][1] == "LEFT" and i1.bar._points[1][2] == i1.icon, "square icon on the left of the bar")
check(i1.bar._value == 1 and i1.glow == i1.barGlow and i1.bar._barTexture == ns.Data.barTextureByKey.blizzard.path, "nothing measured: full bar with the default texture")
d1.visual.iconSide, d1.visual.barTexture, d1.visual.barColor = "NONE", "flat", { 1, 0, 0 }
step(0)
check(not i1.icon._shown and i1.bar._points[1][2] == i1 and i1.bar._barTexture == ns.Data.barTextureByKey.flat.path and i1.bar._barColor[1] == 1, "bar without an icon, own texture and color")
d1.visual.iconSide, d1.visual.barTexture, d1.visual.barColor = "RIGHT", nil, nil
step(0)
check(i1.icon._shown and i1.icon._points[1][1] == "RIGHT" and i1.bar._points[2][2] == i1.icon, "icon on the right")
d1.visual.iconSide = nil
d2.visual.style = "icon"
step(0)
check(not i2.bar._shown and i2.icon._shown and i2.icon._width == 50 and i2.glow == i2.iconGlow and gframe._height == 20 + 10 + 50, "reminder can switch back to an icon")
d2.visual.style = nil
local imported = ns.Serialize.Import(ns.Serialize.Export({ dg.id }))
check(imported and imported[1].visual.style == "bar" and imported[1].visual.barWidth == 200, "bar settings exported with the group")
dg.visual.barWidth = 5000
Core:NormalizeNode(dg)
check(dg.visual.barWidth == 800, "bar width clamped")
dg.visual.style, dg.visual.barWidth, dg.visual.barHeight = nil, nil, nil
step(0)
check(not i1.bar._shown and i1.icon._shown and i1.icon._width == 40, "back to icons")
dg.visual.iconSize = 30
d2.visual.iconSize = 50

local hawkBar = Core:AddReminder({ name = "Hawk bar", text = "Hawk {left}", conditions = { { type = "aura", unit = "player", filter = "HELPFUL", spells = "13165" } } })
hawkBar.visual.style = "bar"
STATE.auras = { { name = "Aspect of the Hawk", spellId = 13165, duration = 120, expirationTime = NOW + 90, auraInstanceID = 31 } }
Fire("UNIT_AURA", "player")
step(0)
local hb = ns.Display.items[hawkBar.id]
check(near(hb.bar._value, 0.75) and hb.bar.text._text == "Hawk 1:30" and hb.bar.timer._text == "1:30", "aura bar: 90 of 120 s, text and timer inside")
NOW = NOW + 30
hb.bar._scripts.OnUpdate(hb.bar)
check(near(hb.bar._value, 0.5), "bar drains between passes")
hawkBar.visual.barReverse = true
step(0)
check(near(hb.bar._value, 0.5) and hb.bar.reverse, "reverse fill")
NOW = NOW + 30
hb.bar._scripts.OnUpdate(hb.bar)
check(near(hb.bar._value, 0.75), "reverse bar fills as time runs out")
hawkBar.visual.barReverse = nil
hawkBar.progressMax = 120
step(0)
check(near(hb.bar._value, 0.25), "full-at override")
hawkBar.progressMax = 0
hawkBar.progress = "full"
step(0)
check(hb.bar._value == 1 and hb.bar.expires == nil, "always full")
hawkBar.progress = "auto"
hawkBar.conditions[1].negate = true
STATE.auras = {}
step(0)
check(ns.Display.shown[hawkBar.id] and hb.bar._value == 0 and not hb.bar.timer._shown, "missing aura: empty bar")
hawkBar.progress = "full"
step(0)
check(hb.bar._value == 1, "missing aura with always full")
hawkBar.enabled = false
STATE.auras = savedAuras
Fire("UNIT_AURA", "player")

local poisonBar = Core:AddReminder({ name = "Poison bar", text = "Poison {left:missing}", conditions = {
	{ type = "weaponEnchant", negate = true, slot = 16, kind = "any", minLeft = 600 },
} })
poisonBar.visual.style = "bar"
enchantLeft(1800)
check(not step(0)["Poison bar"], "poison bar hidden while fresh")
enchantLeft(1200)
step(0)
enchantLeft(300)
step(0)
local pb = ns.Display.items[poisonBar.id]
check(pb and near(pb.bar._value, 300 / 1800) and pb.bar.text._text == "Poison 5:00", "enchant bar measured against the longest time left seen")
poisonBar.progressMax = 3600
step(0)
check(near(pb.bar._value, 300 / 3600), "enchant full-at override")
poisonBar.progressMax = 0
enchantLeft(nil)
step(0)
check(pb.bar._value == 0 and pb.bar.text._text == "Poison missing", "missing enchant: empty bar")
enchantLeft(1700)
step(0)
enchantLeft(500)
step(0)
check(near(pb.bar._value, 500 / 1700), "reference resets when the enchant is reapplied")
enchantLeft(nil)
poisonBar.enabled = false

local Compat = ns.Compat
check(Compat.ParseDuration("90") == 90 and Compat.ParseDuration("1m30s") == 90 and Compat.ParseDuration("1:30") == 90
	and Compat.ParseDuration("2H") == 7200 and Compat.ParseDuration("1 h 5 m") == 3900 and Compat.ParseDuration("abc") == nil
	and Compat.ParseDuration("5x") == nil and Compat.ParseDuration("") == nil, "durations parsed")
check(Compat.FormatDuration(90) == "1m30s" and Compat.FormatDuration(600) == "10m" and Compat.FormatDuration(3605) == "1h5s", "durations formatted")
check(table.concat(Core.NormalizeWarnings({ 10, "60", 10, 0, -5, 30.7, 1, 2, 3, 4 }), ",") == "60,30,10,2,1", "warnings sorted, deduplicated, capped at 5")
local warned = Core:AddReminder({ name = "Warned", text = "Hawk {left}", alert = true, warnAt = { 60, 10 }, conditions = {
	{ type = "aura", unit = "player", filter = "HELPFUL", spells = "13165" } } })
warned.visual.glow = false
check(warned.warnSound == "RAID_WARNING", "warning sound defaults to raid warning")
STATE.auras = { { name = "Aspect of the Hawk", spellId = 13165, duration = 120, expirationTime = NOW + 60.8, auraInstanceID = 12 } }
step(0)
local wItem = ns.Display.items[warned.id]
local played, alerts = #PLAYED, #ALERTS
step(0.5)
check(#PLAYED == played and not wItem.glow._shown, "no warning above the first point")
step(1)
check(#PLAYED == played + 1 and PLAYED[#PLAYED] == SOUNDKIT.RAID_WARNING and ALERTS[#ALERTS] == "Hawk 59s" and wItem.glow._shown, "warning at 60 s: sound, alert, flash")
step(0.5)
check(#PLAYED == played + 1, "each point warns once")
step(3)
check(not wItem.glow._shown, "flash ends")
warned.warnSound = "NONE"
warned.alert = false
step(46.5)
check(#PLAYED == played + 1 and wItem.glow._shown and #ALERTS == alerts + 1, "silent warning still flashes")
warned.conditions[1].negate = true
STATE.auras = {}
step(3)
warned.conditions[1].negate = false
STATE.auras = { { name = "Aspect of the Hawk", spellId = 13165, duration = 120, expirationTime = NOW + 5, auraInstanceID = 12 } }
warned.warnSound = "READY_CHECK"
step(0)
check(PLAYED[#PLAYED] ~= SOUNDKIT.READY_CHECK, "appearing below a point does not warn")
local copy = ns.Serialize.Import(ns.Serialize.Export({ warned.id }))[1]
check(copy.warnAt[1] == 60 and copy.warnAt[2] == 10 and copy.warnSound == "READY_CHECK", "warnings exported")
warned.enabled = false
STATE.auras = {}
step(0)

local ammoBar = Core:AddReminder({ name = "Ammo bar", conditions = { { type = "ammo", op = "<", value = 200 } } })
ammoBar.visual.style = "bar"
step(0)
local ab = ns.Display.items[ammoBar.id]
check(ab and near(ab.bar._value, 150 / 200), "count bar uses the condition's amount")
ammoBar.progressMax = 600
step(0)
check(near(ab.bar._value, 0.25), "count full-at override")
ammoBar.enabled = false
local function progressOf(vars, mode, maximum)
	return ns.Progress.Compute({ progress = mode or "auto", progressMax = maximum or 0, conditions = {} }, vars, {}, NOW)
end
check(near(progressOf({ count = 40, max = 100 }), 0.4) and progressOf({}, "value") == nil and progressOf({}, "time") == nil and progressOf({}) == 1, "percent, missing value and nothing measured")
end

-- Static positions and dragging
UIParent._rect = { 0, 0, 1000, 800 }
local sg = Core:AddGroup("static", nil, nil, "Free")
sg.x, sg.y = 100, 50
local free = Core:AddReminder({ name = "Free one", conditions = { { type = "combat", negate = true } } }, sg.id)
free.x, free.y = 30, -20
free.visual.showText = false
step(0)
local sframe, fitem = ns.Display.groups[sg.id], ns.Display.items[free.id]
check(sframe._points[1][2] == UIParent and sframe._points[1][4] == 100 and sframe._points[1][5] == 50, "static group placed at its offset")
check(fitem._points[1][2] == sframe and fitem._points[1][4] == 30 and fitem._points[1][5] == -20, "reminder placed relative to its static group")
check(Tree:IsPositioned(free) and not Tree:IsPositioned(d1), "positioned unless in a dynamic group")
ns.db.display.locked = false
step(0)
check(ns.Display:IsEditMode() and fitem._alpha == 1, "edit mode when unlocked")
sframe._rect = { 589, 439, 22, 22 }
fitem._rect = { 700, 500, 40, 40 }
fitem._scripts.OnDragStart(fitem)
check(ns.Display.dragging and ns.Display.dragging.frame == fitem, "dragging a free reminder moves it")
fitem._scripts.OnDragStop(fitem)
check(free.x == 120 and free.y == 70, "drag saves the offset from the group center: " .. free.x .. "," .. free.y)
i1._scripts.OnDragStart(i1)
check(ns.Display.dragging.frame == gframe and ns.Display.dragging.id == dg.id, "dragging a reminder in a dynamic group moves the group")
gframe._rect = { 450, 600, 40, 86 }
i1._scripts.OnDragStop(i1)
check(dg.x == -30 and dg.y == 286, "dynamic group position saved at its anchor: " .. dg.x .. "," .. dg.y)
sframe._rect = { 600, 600, 22, 22 }
sframe._scripts.OnDragStart(sframe)
sframe._scripts.OnDragStop(sframe)
check(sg.x == 111 and sg.y == 211, "static group position saved at its center")
gframe._scale = 2
gframe._rect = { 225, 300, 20, 43 }
gframe.anchorPoint = "TOP"
ns.Display:SavePosition(dg.id, gframe)
check(dg.x == 235 - 250 and dg.y == 343 + 0 - 200, "scaled group offsets use its own scale")
gframe._scale = 1
local disabledChild = Core:AddReminder({ name = "Off child", enabled = false, conditions = {} }, sg.id)
shown = step(0)
check(ns.Display.items[free.id]._shown and (ns.Display.items[disabledChild.id] == nil or not ns.Display.items[disabledChild.id]._shown), "edit mode previews enabled reminders only")
ns.db.display.locked = true
step(0)
check(not ns.Display:IsEditMode(), "locked again")

-- Remove and duplicate
local dup = Core:DuplicateNode(sg.id)
check(dup and dup.id ~= sg.id and #dup.children == 2 and dup.children[1] ~= sg.children[1] and dup.name == "Free (copy)", "duplicating a group copies its contents with new IDs")
check(Tree:IndexOf(dup.id) == Tree:IndexOf(sg.id) + 1, "duplicate placed right after the original")
local childIDs = { dup.children[1], dup.children[2] }
Core:DeleteNode(dup.id, true)
check(not Tree:Get(dup.id) and Tree:Parent(childIDs[1]) == Tree.ROOT and Tree:Get(childIDs[2]), "delete keeping contents moves them up")
Core:DeleteNode(childIDs[1])
Core:DeleteNode(childIDs[2])
local dup2 = Core:DuplicateNode(sg.id)
local dupChild = dup2.children[1]
Core:DeleteNode(dup2.id)
check(not Tree:Get(dup2.id) and not Tree:Get(dupChild), "delete everything removes the contents")

-- Import / export
local S = ns.Serialize
local sample = Core:AddReminder({
	name = "Pipes |cffff0000red|r", text = "line1\nline2 ~ tilde", icon = "", sound = "NONE",
	action = { kind = "macro", macro = "/run print(1)\n/cast Foo" },
	conditions = { { type = "group", match = "ANY", conditions = { { type = "aura", spells = "Aspect of the Pack (13159)" } } }, { type = "level", op = ">=", value = 10 } },
	disabledFor = { ["Tester-Realm"] = true },
})
sample.visual.textColor = { 1, 0, 0 }
sample.visual.textPos = "BOGUS"
local exported = S.Export({ sample.id })
check(exported:sub(1, 6) == "!RMW1!" and not exported:find("|", 1, true) and not exported:find("\n", 1, true), "export string has no pipes or newlines")
local imported, err = S.Import("  " .. exported .. "\n")
check(imported and #imported == 1, "import round trip: " .. tostring(err))
local one = imported[1]
check(one.name == sample.name and one.text == sample.text, "strings survive escaping")
check(one.conditions[1].type == ns.Conditions.GROUP and one.conditions[1].conditions[1].spells == "Aspect of the Pack (13159)", "nested conditions survive")
check(one.action.kind == "none" and one.macroDisabled and one.action.macro == sample.action.macro, "imported macro is switched off for review")
check(one.disabledFor == nil and one.id == nil, "per-character and id data not exported")
check(one.visual.textColor[1] == 1 and one.visual.textPos == nil, "visual overrides exported and sanitized")
check(S.Import("hello") == nil, "rejects non-export text")
check(S.Import("!RMW1!t" .. "s4:name") == nil, "rejects truncated strings")
check(S.Import("!RMW1!ts9:remindersts4:types7:unknownee" .. "e") == nil, "drops unknown condition types (no reminders left)")
local deep = "!RMW1!ts9:reminderstn1;t" .. "s10:conditionst" .. string.rep("n1;ts4:types5:groups10:conditionst", 6) .. string.rep("ee", 6) .. "eeee"
local deepList = S.Import(deep)
check(deepList and ns.Conditions:GroupDepth(deepList[1].conditions[1]) <= 3, "imported nesting capped at 3 levels")
sample.enabled = false

local tree = S.Import(S.Export({ static.id }))
local top = tree and tree[1]
check(top and top.kind == "group" and top.layout == "static" and #top.items == #static.children, "group export keeps its contents")
local innerDyn
for _, it in ipairs(top.items) do if it.name == "Inner dynamic" then innerDyn = it end end
check(innerDyn and innerDyn.layout == "dynamic" and innerDyn.items, "nested groups exported")
check(S.CountReminders(tree) == #Tree:Reminders(static.id), "reminder count matches the subtree")
local evil = S.Encode({ version = 2, nodes = {
	{ kind = "group", layout = "dynamic", name = "Bad", items = { { kind = "group", layout = "static", items = {} }, { kind = "reminder", name = "ok" } } },
	{ kind = "group", layout = "static", items = { { kind = "group", layout = "static", items = { { kind = "group", layout = "static", items = {
		{ kind = "group", layout = "static", items = {} } } } } } } },
} })
local cleaned = S.Import(evil)
check(cleaned and #cleaned[1].items == 2 and cleaned[1].items[1].kind == "group", "groups inside a dynamic group are kept on import")
check(Tree:GroupHeight(cleaned[2]) == 3, "imported group depth capped at 3")
local added = Core:AddSnapshot(top, nil)
check(added.id ~= static.id and #added.children == #static.children and Tree:Parent(added.children[1]) == added.id, "imported group restored with new IDs")
Core:DeleteNode(added.id)

-- Permanent IDs, revisions and updating on import
do
	local V, M = ns.Versions, ns.Merge
	local function place() return Tree.ROOT, nil end
	local function reimport(ids) return S.Import(S.Export(ids)) end
	local function uidsUnique()
		local seen, unique = {}, true
		Tree:Walk(function(n)
			if not V.IsUID(n.uid) or seen[n.uid] then unique = false end
			seen[n.uid] = true
		end)
		return unique
	end
	check(V.IsUID(static.uid) and static.revision >= 1 and uidsUnique(), "every node has a unique permanent ID and a revision")

	local pack = Core:AddGroup("dynamic", nil, nil, "Pack")
	local a = Core:AddReminder({ name = "Alpha", text = "a", conditions = { { type = "combat", negate = true } } }, pack.id)
	local b = Core:AddReminder({ name = "Beta", text = "b", conditions = {} }, pack.id)
	V:Update()
	local aRev, packRev = a.revision, pack.revision
	a.text = "a2"
	a.text = "a3"
	V:Update()
	check(a.revision == aRev + 1 and pack.revision == packRev + 1 and b.revision == 1, "an edit session counts once, for the reminder and its group")
	a.x, a.enabled, a.scale = 99, false, 2
	V:Update()
	a.x, a.enabled, a.scale = 0, true, 1
	V:Update()
	check(a.revision == aRev + 1, "position and enabled are not edits")

	local exported = reimport({ pack.id })
	check(exported[1].uid == pack.uid and exported[1].items[1].uid == a.uid and exported[1].revision == pack.revision, "exports carry permanent IDs and revisions")

	local c = Core:AddReminder({ name = "Mine only", conditions = {} }, pack.id)
	a.visual.iconSize = 50
	a.disabledFor = { ["Tester-Realm"] = true }
	local snoozeAt = time() + 600
	ns.db.snoozes[a.id] = snoozeAt
	local incoming = exported[1]
	incoming.revision = pack.revision + 2
	incoming.name = "Pack v2"
	incoming.items[1].text = "new text"
	incoming.items[1].conditions = {}
	incoming.items[1].x = 500
	incoming.items[1].visual = { style = "bar" }
	incoming.items[2] = { kind = "reminder", name = "Gamma", conditions = {} }
	local plan = M.Plan({ incoming })
	local entry = plan.entries[1]
	check(plan.matches == 2 and entry.existing == pack and entry.status == "newer" and entry.children[1].existing == a
		and entry.children[2].status == "new", "plan matches the group and its reminder by permanent ID")
	check(#plan.leftovers == 2 and plan.leftovers[1] == b and plan.leftovers[2] == c, "plan lists what the new version no longer has")
	local updated = M.Apply(plan, { keep = { look = true, position = true }, remove = { [b.id] = true }, place = place })
	check(updated[1] == pack and pack.name == "Pack v2" and pack.revision == incoming.revision and Tree:Parent(pack.id) == Tree.ROOT, "group updated in place")
	check(a.text == "new text" and #a.conditions == 0 and a.visual.iconSize == 50 and a.visual.style == nil and a.x == 0, "replaced parts follow the import, kept parts stay")
	check(a.disabledFor["Tester-Realm"] and a.enabled and ns.db.snoozes[a.id] == snoozeAt, "enabled, per-character switches and snoozes survive")
	local names = {}
	for i, id in ipairs(pack.children) do names[i] = Tree:Get(id).name end
	check(table.concat(names, ",") == "Alpha,Gamma,Mine only" and not Tree:Get(b.id), "new order, new reminder added, kept leftover at the end, removed one gone")
	V:Update()
	check(pack.revision == incoming.revision and uidsUnique(), "an update is not counted as an edit")

	local older = reimport({ pack.id })[1]
	older.revision = 1
	local olderPlan = M.Plan({ older })
	check(olderPlan.entries[1].status == "older" and olderPlan.notNewer >= 1, "older imports are flagged")

	local solo = Core:AddReminder({ name = "Solo", text = "old", conditions = {} })
	local legacy = M.Plan({ { kind = "reminder", name = "Solo", text = "fresh", conditions = {} } })
	check(legacy.entries[1].existing == solo and legacy.entries[1].status == "same", "without an ID, a unique name and type match")
	check(M.Plan({ { kind = "group", layout = "dynamic", name = "Solo", items = {} } }).matches == 0, "names only match the same type")
	local solo2 = Core:AddReminder({ name = "Solo", conditions = {} })
	check(M.Plan({ { kind = "reminder", name = "Solo", conditions = {} } }).matches == 0, "a name used twice matches nothing")
	Core:DeleteNode(solo.id)
	Core:DeleteNode(solo2.id)

	a.action = { kind = "macro", macro = "/dance" }
	local withMacro = reimport({ pack.id })
	a.action = { kind = "none" }
	local _, macros = M.Apply(M.Plan(withMacro), { place = place })
	check(macros == 1 and a.action.kind == "none" and a.macroDisabled, "an updated macro is switched off for review")

	local rootCount = #ns.db.root
	local copyTop = M.Apply(M.Plan(reimport({ pack.id })), { asCopy = true, place = place })[1]
	check(copyTop ~= pack and copyTop.uid ~= pack.uid and #ns.db.root == rootCount + 1 and #copyTop.children == #pack.children, "import as copy adds new nodes")
	local dupPack = Core:DuplicateNode(pack.id)
	check(dupPack.uid ~= pack.uid and Tree:Get(dupPack.children[1]).uid ~= a.uid and uidsUnique(), "duplicates get new permanent IDs")

	local foreign = reimport({ pack.id })[1]
	foreign.name = "Unrelated"
	foreign.uid = nil
	for _, item in ipairs(foreign.items) do item.name = item.name .. " x" end
	foreign.items[1].uid = c.uid
	local foreignPlan = M.Plan({ foreign })
	check(foreignPlan.matches == 0, "contents of an unmatched group are not matched")
	M.Apply(foreignPlan, { place = place })
	check(uidsUnique() and c.uid ~= nil, "an ID already in use is replaced on the new copy")

	for _, id in ipairs({ pack.id, copyTop.id, dupPack.id }) do Core:DeleteNode(id) end
	Tree:Walk(function(n) if n.name == "Unrelated" then Core:DeleteNode(n.id) return false end end)
end

-- Saved variables reload keeps the tree
local beforeRoot = #ns.db.root
local snapshotDB = deepCopy(ns.db)
RemindMeWhenDB = snapshotDB
ns.Core:InitDB()
check(#ns.db.root == beforeRoot and Tree:Parent(free.id) == sg.id and ns.db.nodes[free.id].x == 120, "reload keeps nodes, order and positions")
sg, free, main, dg = Tree:Get(sg.id), Tree:Get(free.id), Tree:Get(main.id), Tree:Get(dg.id)
d1, d2, static, dyn = Tree:Get(d1.id), Tree:Get(d2.id), Tree:Get(static.id), Tree:Get(dyn.id)

-- Spell resolution
local Sp = ns.Spells
check(Sp:Canonicalize("13159") == "Aspect of the Pack (13159)", "ID resolves to Name (ID)")
check(Sp:Canonicalize("Wrong Label (13159)") == "Aspect of the Pack (13159)", "ID wins over a wrong label")
local results, worst = Sp:Check("13159, 99999")
check(worst == "missing", "bad spell ID reported missing")
check(ns.Items:Canonicalize("instant poison vi") == "Instant Poison VI (8928)", "item name canonicalizes")
results, worst = ns.Items:Check("77777")
check(worst == "loading" and LOAD_REQUESTS[#LOAD_REQUESTS] == 77777, "uncached item requests data")
check(#ns.Items:Search("poison", 10) == 1, "item search lists bag items")

-- Options UI
local O = ns.Options
for _, p in ipairs(ns.Presets.list) do Core:AddReminder(ns.Presets:Build(p), main.id) end
step(0)
O:Open()
check(O:IsOpen() and ns.Display:IsEditMode(), "options window open turns on edit mode")
for _, entry in ipairs(O:VisibleNodes()) do O:Select(entry.node.id) end
for _, tab in ipairs({ "conditions", "trigger", "sound", "action", "display", "conditions" }) do O:ShowTab(tab) end
O:Select(sg.id)
for _, tab in ipairs({ "conditions", "layout", "display", "trigger" }) do O:ShowTab(tab) end
check(O.tabs.group == "conditions" and O.tabPanels.conditions._shown and not O.tabPanels.trigger._shown, "reminder-only tabs not offered for groups")
check(O.groupHeader._shown and not O.reminderHeader._shown and O.tabBars.group.buttons.layout._shown and not O.tabBars.reminder.buttons.action._shown, "group editor header and tabs")
O:ShowTab("layout")
check(O.staticHelp._shown and not O.dynamicOptions._shown, "static layout tab")
O:Select(dg.id)
O:ShowTab("layout")
check(O.dynamicOptions._shown and O.alignDropdown._shown, "dynamic layout options shown")
O.growDropdown._scripts.OnClick(O.growDropdown)
for _, b in ipairs(RemindMeWhenMenu.buttons) do
	if b._shown and b.text._text == "Right" then b._scripts.OnClick(b) break end
end
check(dg.grow == "RIGHT" and not O.alignDropdown._shown, "grow choice saved, and align only shows for columns")
O.spacingBox._text = "12"
O.spacingBox._scripts.OnEditFocusLost(O.spacingBox)
check(dg.spacing == 12, "spacing saved")
O:ShowPage("display")
O:RefreshDisplayPage()
O.displayChecks.editWhileOptions._checked = false
O.displayChecks.editWhileOptions._scripts.OnClick(O.displayChecks.editWhileOptions)
check(ns.db.display.editWhileOptions == false and not ns.Display:IsEditMode(), "edit while options can be switched off")
ns.db.display.editWhileOptions = true
local gsize
for _, row in ipairs(O.globalVisuals.rows) do if row.info.key == "iconSize" then gsize = row end end
gsize.control._text = "36"
gsize.control._scripts.OnEditFocusLost(gsize.control)
check(ns.db.display.visual.iconSize == 36 and Tree:Visual(free, "iconSize") == 36, "global default look edited")
ns.db.display.visual.iconSize = nil

-- Display tab overrides
O:Select(free.id)
O:ShowTab("display")
local sizeRow, glowRow
for _, row in ipairs(O.nodeVisuals.rows) do
	if row.info.key == "iconSize" then sizeRow = row end
	if row.info.key == "glow" then glowRow = row end
end
check(sizeRow.inherit._checked and sizeRow.control.value == "40", "inherited value shown with use-group checked")
sizeRow.control._text = "64"
sizeRow.control._scripts.OnEditFocusLost(sizeRow.control)
check(free.visual.iconSize == 64 and not sizeRow.inherit._checked, "editing a value makes it an override")
sizeRow.inherit._checked = true
sizeRow.inherit._scripts.OnClick(sizeRow.inherit)
check(free.visual.iconSize == nil, "use group setting removes the override")
sg.visual.glow = false
O:RefreshEditor()
glowRow.inherit._checked = false
glowRow.inherit._scripts.OnClick(glowRow.inherit)
check(free.visual.glow == false, "overriding copies an inherited false")
free.visual.glow = nil
sg.visual.glow = nil
local pos = O.nodePosition
check(pos.x.box._shown and pos.x.slider._shown and pos.x.box.value == "120", "position fields for a free reminder")
pos.y.box._text = "-40"
pos.y.box._scripts.OnEditFocusLost(pos.y.box)
check(free.y == -40 and pos.y.slider.Text._text == "Y: -40", "position edited from the box updates the slider")
pos.x.slider._scripts.OnValueChanged(pos.x.slider, 251.4)
check(free.x == 251 and pos.x.box.value == "251", "slider drag moves it and updates the box")
pos.scale.slider._scripts.OnValueChanged(pos.scale.slider, 1.52)
check(math.abs(free.scale - 1.5) < 0.001 and pos.scale.slider.Text._text == "Scale: 1.50", "scale slider snaps to its step")
free.scale = 1
pos.x.box._text = "900"
pos.x.box._scripts.OnEditFocusLost(pos.x.box)
check(free.x == 900 and tostring(pos.x.slider.High._text) == "900", "slider range widens to include a typed value")
free.x = 120
O:Select(d1.id)
O:ShowTab("display")
check(not pos.x.box._shown and not pos.x.slider._shown, "no position fields inside a dynamic group")

do
	local W = ns.Widgets
	local function rowOf(key)
		for _, row in ipairs(O.nodeVisuals.rows) do if row.info.key == key then return row end end
	end
	local function choose(dropdown, value)
		local open = W.OpenMenu
		W.OpenMenu = function(_, _, _, pick) pick(value) end
		dropdown._scripts.OnClick(dropdown)
		W.OpenMenu = open
	end
	O:Select(free.id)
	O:ShowTab("display")
	check(not rowOf("barWidth").control._shown and rowOf("iconSize").control._shown and not O.barProgress._shown, "icon style hides the bar settings")
	choose(rowOf("style").control, "bar")
	check(free.visual.style == "bar" and rowOf("barWidth").control._shown and not rowOf("iconSize").control._shown and not rowOf("sweep").label._shown, "choosing Bar swaps icon-only rows for bar rows")
	local widthPoint, timerPoint = rowOf("barWidth").label._points[1], rowOf("timer").label._points[1]
	check(widthPoint[2] == 4 + O.VISUAL_COLUMN_W + 26 and widthPoint[3] == -190 and timerPoint[2] == 30 and timerPoint[3] == -190 - 5 * 28, "bar settings in a second column, first column closes up")
	local progress = O.barProgress
	check(progress._shown and progress._points[1][2] == 4 + O.VISUAL_COLUMN_W and progress._points[1][3] == -190 - 7 * 28, "bar progress controls under the bar settings")
	choose(progress.mode, "value")
	progress.max._text = "250"
	progress.max._scripts.OnEditFocusLost(progress.max)
	check(free.progress == "value" and free.progressMax == 250 and progress.max._shown, "progress mode and full-at value saved")
	choose(progress.mode, "full")
	check(free.progress == "full" and not progress.max._shown, "always full hides the full-at box")
	free.visual.style, free.progress, free.progressMax = nil, "auto", 0
	sg.visual.style = "bar"
	O:Select(sg.id)
	O:ShowTab("display")
	check(rowOf("barWidth").control._shown and not O.barProgress._shown, "groups set bar defaults but have no progress controls")
	sg.visual.style = nil
	O:Select(free.id)
	O:ShowTab("display")
	check(not rowOf("barWidth").control._shown, "back to icon rows")
end

-- Load rules
do
	local Load = ns.Load
	check(Load.Normalize({ classes = {}, minLevel = 0, characters = " , " }) == nil, "empty load rules collapse to nil")
	local clean = Load.Normalize({ classes = { MAGE = true, BOGUS = true }, minLevel = 70, maxLevel = 10, characters = " Tester ,  Alt-Realm " })
	check(clean.classes.MAGE and not clean.classes.BOGUS and clean.minLevel == 10 and clean.maxLevel == 60 and clean.characters == "Tester, Alt-Realm", "load rules sanitized")
	dg.load = Load.Normalize({ classes = { MAGE = true } })
	check(not Core:IsEnabledHere(d1) and not step(0)["D1"], "wrong class unloads the group and its reminders")
	STATE.level = 30
	dg.load = Load.Normalize({ classes = { HUNTER = true }, minLevel = 40 })
	check(not Core:IsEnabledHere(d1), "level below the range")
	dg.load = Load.Normalize({ maxLevel = 29 })
	check(not Core:IsEnabledHere(d1), "level above the range")
	dg.load = Load.Normalize({ minLevel = 30, maxLevel = 30 })
	check(Core:IsEnabledHere(d1), "level inside the range")
	STATE.level = 60
	dg.load = Load.Normalize({ characters = "someone, tester" })
	check(Core:IsEnabledHere(d1) and step(0)["D1"], "character name matches without realm, any case")
	dg.load = Load.Normalize({ characters = "Tester-OtherRealm" })
	check(not Core:IsEnabledHere(d1), "realm must match when given")
	dg.load = nil
	d1.load = Load.Normalize({ classes = { HUNTER = true }, minLevel = 10, maxLevel = 60 })
	check(Core:IsEnabledHere(d1), "matching rules load")
	STATE.level = 5
	check(not Core:IsEnabledHere(d1), "level re-checked every pass")
	STATE.level = 60
	local copy = ns.Serialize.Import(ns.Serialize.Export({ d1.id }))[1]
	check(copy.load and copy.load.classes.HUNTER and copy.load.minLevel == 10, "load rules exported")

	O:Select(d1.id)
	O:ShowTab("load")
	check(O.tabPanels.load._shown and O.loadClassChecks.HUNTER._checked and O.loadMinLevel.value == "10", "load tab shows the rules")
	check(O.loadStatus._text:find("Loaded on this character", 1, true), "status: loaded")
	O.loadClassChecks.HUNTER._checked = false
	O.loadClassChecks.HUNTER._scripts.OnClick(O.loadClassChecks.HUNTER)
	O.loadMinLevel._text = "0"
	O.loadMinLevel._scripts.OnEditFocusLost(O.loadMinLevel)
	O.loadMaxLevel._text = ""
	O.loadMaxLevel._scripts.OnEditFocusLost(O.loadMaxLevel)
	check(d1.load == nil, "clearing every rule removes them")
	O.loadClassChecks.MAGE._checked = true
	O.loadClassChecks.MAGE._scripts.OnClick(O.loadClassChecks.MAGE)
	check(d1.load.classes.MAGE and O.loadStatus._text:find("class", 1, true), "status says why it is not loaded")
	d1.load = nil
	O.loadAddMe._scripts.OnClick(O.loadAddMe)
	check(d1.load.characters == "Tester-Realm" and O.loadCharacters.value == "Tester-Realm", "add this character")
	d1.load = nil
	dg.load = Load.Normalize({ classes = { MAGE = true } })
	O:RefreshEditor()
	check(O.loadStatus._text:find("a group it is in", 1, true), "status explains a group's rules")
	dg.load = nil
	O:Select(dg.id)
	O:ShowTab("load")
	check(O.loadHelp._text:find("this group", 1, true), "group load help")
end

-- Tree list
local rowsBefore = #O:VisibleNodes()
O:ToggleCollapsed(main.id)
check(#O:VisibleNodes() == rowsBefore - #main.children and ns.db.collapsed[main.id], "collapsing hides a group's contents")
O:ToggleCollapsed(main.id)
check(#O:VisibleNodes() == rowsBefore, "expanding shows them again")
local a, b = main.children[1], main.children[2]
check(O:DropTarget(a, b, 0.9) == main.id and select(2, O:DropTarget(a, b, 0.9)) == 3, "drop below a sibling")
check(O:Drop(a, b, 0.9) and main.children[1] == b and main.children[2] == a, "drag reorder within a group")
check(O:Drop(a, sg.id, 0.5) and Tree:Parent(a) == sg.id, "drop into a group")
check(Tree:ParentNode(d1.id).layout == "dynamic" and O:DropTarget(inner.id, d1.id, 0.2) == Tree:Parent(d1.id), "a group can be dropped into a dynamic group")
check(O:DropTarget(static.id, d1.id, 0.2) == nil, "a group too deep for the spot cannot be dropped there")
check(O:DropTarget(static.id, dyn.id, 0.5) == nil, "a group cannot be dropped into its own subtree")
check(O:Drop(a, sg.id, 0.1) and Tree:Parent(a) == Tree.ROOT and ns.db.root[Tree:IndexOf(sg.id) - 1] == a, "drop above a group puts it before")
O:RefreshList()
local row
for _, r in ipairs(O.treeRows) do if r._shown and r.nodeID == a then row = r end end
check(row and row.icon._texture and row.check._checked == Tree:Get(a).enabled and row.text._text:find("|cff888888", 1, true), "tree row shows icon, enabled check, greyed when off")
local target
for _, r in ipairs(O.treeRows) do if r._shown and r.nodeID == sg.id then target = r end end
row._scripts.OnDragStart(row)
target._mouseOver, target._top, target._bottom = true, 100, 78
CURSOR[2] = 89
O:UpdateDropIndicator()
check(O.dropBox._shown, "drop indicator over the middle of a group")
row._scripts.OnDragStop(row)
target._mouseOver = false
check(Tree:Parent(a) == sg.id and O.selected == a, "mouse drag drops into the group")
local function rowFor(id)
	for _, tr in ipairs(O.treeRows) do if tr._shown and tr.nodeID == id then return tr end end
end
row, target = rowFor(a), rowFor(sg.id)
row._scripts.OnClick(row, "RightButton")
local labels = {}
for _, mb in ipairs(RemindMeWhenMenu.buttons) do if mb._shown then labels[#labels + 1] = mb.text._text end end
check(table.concat(labels, ",") == "Move to,Duplicate,Export,Test,Delete", "reminder context menu")
target._scripts.OnClick(target, "RightButton")
labels = {}
for _, mb in ipairs(RemindMeWhenMenu.buttons) do if mb._shown then labels[#labels + 1] = mb.text._text end end
check(table.concat(labels, ",") == "Move to,Duplicate,Export,Test,Change to dynamic group,Collapse,Delete", "group context menu")
do
	local m, sub = RemindMeWhenMenu, RemindMeWhenSubmenu
	local function moveEntry(label)
		m.buttons[1]._scripts.OnEnter(m.buttons[1])
		for _, mb in ipairs(sub.buttons) do
			if mb._shown and mb.text._text:match("^%s*(.-)$") == label then return mb end
		end
	end
	local mainEntry = moveEntry("Main")
	check(sub._shown and sub.buttons[1].text._text == "Top level" and sub.buttons[1]._enabled == false,
		"Move to flyout lists Top level first, disabled where the group already is")
	check(mainEntry and mainEntry._enabled == true and moveEntry("Free")._enabled == false,
		"Move to: a dynamic group is allowed for a group, its own entry is not")
	rowFor(a)._scripts.OnClick(rowFor(a), "RightButton")
	check(moveEntry("Free")._enabled == false and moveEntry("Main")._enabled ~= false, "the current group is disabled for a reminder")
	local top = moveEntry("Top level")
	top._scripts.OnClick(top)
	check(Tree:Parent(a) == Tree.ROOT and O.selected == a and not m._shown, "Move to Top level moves the reminder out")
	rowFor(a)._scripts.OnClick(rowFor(a), "RightButton")
	local free = moveEntry("Free")
	free._scripts.OnClick(free)
	check(Tree:Parent(a) == sg.id and ns.db.root[#ns.db.root] ~= a, "Move to a group puts it back inside")
	target = rowFor(sg.id)
end
do
	local D = ns.Display
	local gem = "Interface\\Icons\\INV_Misc_Gem_01"
	local plain = Core:AddReminder({ name = "Plain", conditions = { { type = "combat", negate = true } } }, sg.id)
	check(D:GetIcon(plain) == ns.Data.QUESTION_ICON and D:GetIcon(sg) == ns.Data.STATIC_GROUP_ICON,
		"without icons: question mark and the default group icon")
	O:Select(sg.id)
	check(O.groupHeader._shown and O.groupIconBox._text == "", "group editor has an empty icon box")
	O.groupIconBox._text = gem
	O.groupIconBox._scripts.OnEditFocusLost(O.groupIconBox)
	check(sg.icon == gem and D:GetIcon(sg) == gem and O.groupIconPreview._texture == gem, "group icon saved and previewed")
	check(rowFor(sg.id).icon._texture == gem, "tree list shows the group icon")
	check(D:GetIcon(plain) == gem, "a reminder without an icon of its own uses its group's")
	check(D:GetIcon(Tree:Get(a)) ~= gem, "a reminder with its own icon source keeps it")
	local copied = ns.Serialize.Import(ns.Serialize.Export({ sg.id }))
	check(copied and copied[1].icon == gem, "group icon is exported")
	O.groupIconBox._text = ""
	O.groupIconBox._scripts.OnEditFocusLost(O.groupIconBox)
	check(sg.icon == "" and D:GetIcon(sg) == ns.Data.STATIC_GROUP_ICON and D:GetIcon(plain) == ns.Data.QUESTION_ICON,
		"clearing the group icon restores the defaults")
	Core:DeleteNode(plain.id)

	O:Select(a)
	O:ShowTab("sound")
	local r = Tree:Get(a)
	r.sound = "NONE"
	O:RefreshEditor()
	check(O.soundDropdown.play._enabled == false and O.warnSoundDropdown.play._enabled == true, "Play is off for no sound")
	local dd = O.soundDropdown
	dd._scripts.OnClick(dd)
	for _, mb in ipairs(RemindMeWhenMenu.buttons) do
		if mb._shown and mb.text._text == "Ready check" then mb._scripts.OnClick(mb) break end
	end
	check(r.sound == "READY_CHECK" and PLAYED[#PLAYED] == SOUNDKIT.READY_CHECK and dd.play._enabled == true,
		"choosing a sound saves it, plays it and enables Play")
	local before = #PLAYED
	dd.play._scripts.OnClick(dd.play)
	check(#PLAYED == before + 1 and PLAYED[#PLAYED] == SOUNDKIT.READY_CHECK, "Play previews the chosen sound")
	O.warnSoundDropdown.play._scripts.OnClick(O.warnSoundDropdown.play)
	check(PLAYED[#PLAYED] == SOUNDKIT[r.warnSound], "Play previews the warning sound")
	O:Select(sg.id)
end
O:Select(sg.id)
O:NewReminder()
check(Tree:Parent(O.selected) == sg.id, "new reminder goes into the selected group")
O:NewGroup("dynamic")
check(Tree:Parent(O.selected) == sg.id and Tree:Get(O.selected).layout == "dynamic", "new group goes into the selected static group")
local newDyn = O.selected
O:NewGroup("static")
check(Tree:Parent(O.selected) == newDyn, "new group goes into the selected dynamic group")
O:ConfirmDelete(O.selected)
check(POPUPS[#POPUPS].name == "REMINDMEWHEN_DELETE", "empty group deletes with the plain prompt")
O:Select(sg.id)
O:ConfirmDelete(sg.id)
local popup = POPUPS[#POPUPS]
check(popup.name == "REMINDMEWHEN_DELETE_GROUP" and popup.data == sg.id, "group with contents offers to keep them")
local sgChildren = #sg.children
local sgIndex = Tree:IndexOf(sg.id)
StaticPopupDialogs[popup.name].OnAlt(popup, popup.data)
check(not Tree:Get(sg.id) and ns.db.nodes[a] and Tree:Parent(a) == Tree.ROOT and O.selected == ns.db.root[sgIndex], "keep contents: group removed, items moved up, next item selected")
check(#ns.db.root >= sgChildren, "contents now top level")

O:Select(main.id)
local r = Tree:Get(main.children[#main.children])
O:Select(r.id)
r.conditions = {}
for _, key in ipairs(ns.Conditions.order) do
	r.conditions[#r.conditions + 1] = ns.Conditions:Normalize({ type = key })
end
local g = ns.Conditions:SetType({}, ns.Conditions.GROUP)
g.conditions = { ns.Conditions:Normalize({ type = "aura" }), ns.Conditions:SetType({}, ns.Conditions.GROUP) }
r.conditions[#r.conditions + 1] = g
O:ShowTab("conditions")
O:Changed(true)
step(0)
local errors = 0
ns.Conditions:Walk(r.conditions, function(c)
	local e = ns.Conditions.errors[c]
	if e then print("ERR", c.type, e) errors = errors + 1 end
end)
check(errors == 0, "every condition type evaluates without error")
local enchantRow
for _, crow in ipairs(O.condRows) do
	if crow._shown and crow.node and crow.node.type == "weaponEnchant" then enchantRow = crow end
end
local function idsBoxShown()
	for _, box in ipairs(enchantRow.boxes) do if box._shown and box.param.key == "ids" then return true end end
	return false
end
check(enchantRow and not idsBoxShown(), "enchant IDs box hidden unless the type is Enchant IDs")
local kindDropdown
for _, dd in ipairs(enchantRow.dropdowns) do if dd._shown and dd.param.key == "kind" then kindDropdown = dd end end
kindDropdown._scripts.OnClick(kindDropdown)
for _, mb in ipairs(RemindMeWhenMenu.buttons) do
	if mb._shown and mb.text._text == "Enchant IDs" then mb._scripts.OnClick(mb) break end
end
check(enchantRow.node.kind == "ids" and idsBoxShown(), "choosing Enchant IDs shows the box")
do
	local node = enchantRow.node
	local m, sub = RemindMeWhenMenu, RemindMeWhenSubmenu
	local function rowOf()
		for _, crow in ipairs(O.condRows) do if crow._shown and crow.node == node then return crow end end
	end
	local function shownLabels(frame)
		local out = {}
		for _, mb in ipairs(frame.buttons) do if mb._shown then out[#out + 1] = mb.text._text end end
		return out
	end
	local function search(text)
		m.search._text = text
		m.search._scripts.OnTextChanged(m.search)
	end
	local dd = rowOf().type
	dd._scripts.OnClick(dd)
	check(table.concat(shownLabels(m), "|") == "Group of conditions...|You|Character|Location|Party and target|Pet|Auras and spells|Gear and items"
		and m.search._shown, "condition menu shows categories and a search box")
	check(m.buttons[8].check._shown and not m.buttons[2].check._shown and m.buttons[8].arrow._shown, "the category holding the current type is checked")
	m.buttons[8]._scripts.OnEnter(m.buttons[8])
	local gear = shownLabels(sub)
	check(sub._shown and #gear == 8 and gear[2] == "Weapon has temporary enchant", "hovering a category opens its conditions")
	m.buttons[1]._scripts.OnEnter(m.buttons[1])
	check(not sub._shown, "hovering a plain row closes the flyout")
	m.buttons[8]._scripts.OnEnter(m.buttons[8])
	sub.buttons[6]._scripts.OnClick(sub.buttons[6])
	check(node.type == "ammo" and not m._shown and not sub._shown, "picking from a flyout sets the type and closes both")
	dd = rowOf().type
	check(dd.text._text == "Ammo count (hunter)", "dropdown shows the label of a categorized type")
	dd._scripts.OnClick(dd)
	check(m.search._text == "", "search starts empty")
	search("DURAB")
	local found = shownLabels(m)
	check(#found == 1 and found[1] == "Lowest equipment durability (percent)" and not m.buttons[1].arrow._shown, "search filters every category, ignoring case")
	m.search._scripts.OnEnterPressed(m.search)
	check(node.type == "durability" and not m._shown, "Enter picks the first match")
	dd = rowOf().type
	dd._scripts.OnClick(dd)
	search("zzz")
	m.search._scripts.OnEnterPressed(m.search)
	check(shownLabels(m)[1] == "No matches" and m._shown and node.type == "durability", "no matches: nothing picked")
	search("")
	check(#shownLabels(m) == 8, "clearing the search shows the categories again")
	m:Hide()
	ns.Conditions:SetType(node, "weaponEnchant")
	O:Changed(true)
	local deepest = ns.Conditions:TypeMenu(ns.Conditions.MAX_DEPTH)
	check(deepest[1].children ~= nil and #ns.Conditions:TypeMenu(0) == 8, "no group choice at the deepest level")
	local listed = 0
	for _, category in ipairs(deepest) do listed = listed + #category.children end
	check(listed == #ns.Conditions.order, "every condition type is in a category")
end
local rows = O.condRows
local groupRow, childRow
for _, crow in ipairs(rows) do
	if crow._shown and crow.node == g then groupRow = crow end
	if crow._shown and crow.node == g.conditions[1] then childRow = crow end
end
check(groupRow and groupRow.level == 0 and groupRow.addChild._shown and groupRow.groupMatch._shown, "group row shows group controls")
check(childRow and childRow.level == 1 and childRow.field.box._shown, "child row indented with spell field")
groupRow.addChild._scripts.OnClick(groupRow.addChild)
check(#g.conditions == 3, "add condition inside group")
childRow = nil
for _, crow in ipairs(rows) do if crow._shown and crow.node == g.conditions[1] then childRow = crow end end
childRow.field.box._text = "13159"
childRow.field.box._scripts.OnEditFocusLost(childRow.field.box)
check(g.conditions[1].spells == "Aspect of the Pack (13159)", "condition field canonicalizes")
STATE.auras = { { name = "Aspect of the Hawk", spellId = 13165, icon = 5, duration = 0, expirationTime = 0, auraInstanceID = 40 } }
childRow.field.box._text = "Aspect of the Pack (13159), haw"
childRow.field.box._scripts.OnEditFocusLost(childRow.field.box)
O:OpenPicker(childRow.field)
local menu = RemindMeWhenMenu
check(menu.buttons[1].text._text:find("Aspect of the Hawk %(13165%).*on player now"), "picker lists current aura first: " .. menu.buttons[1].text._text)
menu.buttons[1]._scripts.OnClick(menu.buttons[1])
check(g.conditions[1].spells == "Aspect of the Pack (13159), Aspect of the Hawk (13165)", "pick replaces filter token")
STATE.auras = {}
for _, crow in ipairs(rows) do
	if crow._shown and crow.node == g then crow.remove._scripts.OnClick(crow.remove) break end
end
check(r.conditions[#r.conditions] ~= g, "removing a group removes it")
O:Select(main.id)
check(O.condMatchLabel._text == "Active when", "group conditions say when the group is active")

O:Select(r.id)
O:ShowTab("action")
for _, kind in ipairs(ns.Actions.KINDS) do
	r.action.kind = kind.value
	O:RefreshAction(r)
end
r.action.kind = "weapon"
O:RefreshAction(r)
O.actionItem.box._text = "instant poison vi, Deadly Poison V (20844)"
O.actionItem.box._scripts.OnEditFocusLost(O.actionItem.box)
check(r.action.item == "Instant Poison VI (8928), Deadly Poison V (20844)", "action item field canonicalizes")
check(O.actionPreview._text:find("/use item:8928"), "action preview shows the macro")
check(O.actionFill._shown, "fill button shown for weapon actions")
O.actionFill._scripts.OnClick(O.actionFill)
for _, mb in ipairs(menu.buttons) do
	if mb._shown and mb.text._text == "Sharpening stones" then mb._scripts.OnClick(mb) break end
end
check(r.action.item:find("^Elemental Sharpening Stone %(18262%), Dense Sharpening Stone") and O.actionItem.box.value == r.action.item,
	"fill menu replaces the item list")
r.action.kind = "item"
O:RefreshAction(r)
check(not O.actionFill._shown, "fill button hidden for use-item actions")
r.action.kind = "weapon"
r.action.item = "Instant Poison VI (8928)"
O:RefreshAction(r)
r.action.kind = "spell"
r.action.spell = "Find Minerals (2580)"
O:RefreshAction(r)
O.actionDropdown._scripts.OnClick(O.actionDropdown)
for _, mb in ipairs(menu.buttons) do
	if mb._shown and mb.text._text == "Summon a mount" then mb._scripts.OnClick(mb) break end
end
check(r.action.kind == "mount" and r.action.spell == "", "switching spell to mount clears the spell")
O:OpenPicker(O.actionSpell)
check(menu.buttons[1].text._text:find("Brown Horse %(458%)"), "mount picker lists mounts")
menu.buttons[1]._scripts.OnClick(menu.buttons[1])
check(r.action.spell == "Brown Horse (458)" and ns.Actions:MacroFor(r) == "/cast Brown Horse", "picked mount used by action")

O:ShowExport({ main.id })
check(RemindMeWhenIO._shown and RemindMeWhenIO.box.edit._text:sub(1, 6) == "!RMW1!", "export dialog shows string")
local exportText = RemindMeWhenIO.box.edit._text
O:Select(r.id)
O:ShowImport()
RemindMeWhenIO.box.edit._text = exportText
local nodeCount, mainCount = 0, #main.children
for _ in pairs(ns.db.nodes) do nodeCount = nodeCount + 1 end
O:DoImport()
check(RemindMeWhenIO._shown and RemindMeWhenIO.mode == "review" and RemindMeWhenIO.copy._shown and not RemindMeWhenIO.box._shown, "importing something already here asks to update or copy")
check(RemindMeWhenIO.review.rows[1]._shown and RemindMeWhenIO.review.rows[1].text._text:find("Update") and RemindMeWhenIO.review.keepChecks.position._checked and not RemindMeWhenIO.review.keepChecks.conditions._checked, "review lists the update and keeps only position by default")
RemindMeWhenIO.copy._scripts.OnClick(RemindMeWhenIO.copy)
local after = 0
for _ in pairs(ns.db.nodes) do after = after + 1 end
local importedGroup = Tree:Get(O.selected)
check(after == nodeCount + 1 + mainCount and not RemindMeWhenIO._shown, "import as copy adds the group and its contents")
check(importedGroup.uid ~= main.uid and Tree:Get(importedGroup.children[1]).uid ~= Tree:Get(main.children[1]).uid, "copies get new permanent IDs")
check(importedGroup.kind == "group" and Tree:Parent(importedGroup.id) == main.id and Tree:IndexOf(importedGroup.id) == Tree:IndexOf(r.id) + 1,
	"a group imported with a reminder selected goes right after it, even in a dynamic group")
O:Select(sg and Tree:Get(static.id) and static.id or ns.db.root[1])
O:ShowImport()
RemindMeWhenIO.box.edit._text = "garbage"
O:DoImport()
check(RemindMeWhenIO.status._text:find("not a RemindMeWhen"), "import dialog reports errors")
O.frame:Hide()
check(not ns.Display:IsEditMode(), "closing the options ends edit mode")

SlashCmdList.REMINDMEWHEN("spell aspect")
SlashCmdList.REMINDMEWHEN("unsnooze")
SlashCmdList.REMINDMEWHEN("debug")
SlashCmdList.REMINDMEWHEN("help")
SlashCmdList.REMINDMEWHEN("export")
SlashCmdList.REMINDMEWHEN("test")
step(0)
check(next(ns.Display.shown) ~= nil, "test shows reminders")
SlashCmdList.REMINDMEWHEN("reset")
check(Tree:Get(ns.db.root[1]).x == 0 and Tree:Get(ns.db.root[1]).y == 160, "reset positions")
Fire("SPELL_DATA_LOAD_RESULT", 99998, true)
Fire("ITEM_DATA_LOAD_RESULT", 77777, true)

-- Migration from 1.1 (flat list plus anchors)
RemindMeWhenDB = {
	display = { locked = true, clickToDismiss = false },
	anchors = {
		{ id = 1, name = "Main", point = "CENTER", relPoint = "CENTER", x = 0, y = 180, scale = 1, iconSize = 50, grow = "DOWN" },
		{ id = 2, name = "Side", point = "TOPLEFT", relPoint = "CENTER", x = 100, y = 50, scale = 2, grow = "UP", showText = false },
	},
	reminders = {
		{ id = 5, name = "A", anchor = 1, flash = false, conditions = {} },
		{ id = 9, name = "B", anchor = 2, conditions = {} },
		{ name = "C", anchor = 99, conditions = {} },
	},
	nextID = 3,
	snoozes = {},
}
UIParent._rect = nil
ns.Core:InitDB()
local db = ns.db
local g1, g2 = Tree:Get(db.root[1]), Tree:Get(db.root[2])
check(#db.root == 2 and g1.layout == "dynamic" and g1.name == "Main" and g2.name == "Side", "1.1 anchors become dynamic groups")
check(#g1.children == 2 and g1.children[1] == 5 and #g2.children == 1 and g2.children[1] == 9, "reminders moved into their anchor's group")
check(Tree:Get(5).visual.glow == false and Tree:Get(5).flash == nil and Tree:Get(5).anchor == nil, "flash off becomes a glow override")
check(g1.x == 0 and g1.y == 160 and g1.visual.iconSize == 50 and g1.grow == "DOWN", "main anchor position and look kept")
check(g2.x == 210 and g2.y == 54 and g2.scale == 2 and g2.grow == "UP" and g2.visual.showText == false, "second anchor converted: " .. g2.x .. "," .. g2.y)
check(db.nextID > 9 and db.reminders == nil and db.anchors == nil and db.seeded, "old fields removed, no reseeding")
check(db.display.clickToDismiss == false and db.display.editWhileOptions == true, "display globals kept, new defaults added")

-- Migration from 1.0 (single display position)
RemindMeWhenDB = { display = { point = "TOP", relPoint = "TOP", x = 5, y = -10, scale = 1.5, iconSize = 50, locked = false },
	reminders = { { id = 1, name = "Old", conditions = {} } } }
ns.Core:InitDB()
local old = Tree:Get(ns.db.root[1])
check(#ns.db.root == 1 and old.scale == 1.5 and old.visual.iconSize == 50 and old.children[1] == 1, "1.0 display settings become the group")
check(ns.db.display.point == nil and ns.db.display.locked == false, "per-anchor keys removed from display, globals kept")
check(old.x == 5 and old.y == math.floor(50 / 1.5 - 10 - 16 - 20 + 0.5), "1.0 position converted: " .. old.x .. "," .. old.y)
step(0)
