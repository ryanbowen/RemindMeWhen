local ns = NS
local function check(cond, msg) if not cond then error("FAILED: " .. msg, 2) end print("ok  " .. msg) end

Fire("ADDON_LOADED", "RemindMeWhen")
Fire("PLAYER_LOGIN")
for _, r in ipairs(ns.Tree:Reminders()) do r.enabled = false end

local function poisonReminder(name, text, slot, list)
	return {
		name = name, text = text, icon = ns.Data.POISON_ICON, enabled = true,
		action = { kind = "weapon", item = ns.Data.itemListByKey[list].items, slot = slot },
		conditions = {
			{ type = "class", class = "ROGUE" },
			{ type = "weaponEquipped", slot = slot },
			{ type = "conditionGroup", match = "ANY", conditions = {
				{ type = "conditionGroup", match = "ALL", conditions = {
					{ type = "combat" },
					{ type = "weaponEnchant", negate = true, slot = slot, kind = "poison", minLeft = 60 },
				} },
				{ type = "conditionGroup", match = "ALL", conditions = {
					{ type = "combat", negate = true },
					{ type = "weaponEnchant", negate = true, slot = slot, kind = "poison", minLeft = 600 },
				} },
			} },
		},
	}
end

local MH, OH = "Rogue: main hand poison low", "Rogue: off hand poison low"
local mh = ns.Core:AddReminder(poisonReminder(MH, "Main hand poison {left:missing}", 16, "instant"))
local oh = ns.Core:AddReminder(poisonReminder(OH, "Off hand poison {left:missing}", 17, "deadly"))
local strings = { main = ns.Serialize.Export({ mh.id }), off = ns.Serialize.Export({ oh.id }) }
ns.Core:DeleteNode(mh.id)
ns.Core:DeleteNode(oh.id)

-- Import both and check behavior
for _, key in ipairs({ "main", "off" }) do
	ns.Options:Open()
	ns.Options.selected = nil
	local list, err = ns.Serialize.Import(strings[key])
	check(list and #list == 1, key .. " imports: " .. tostring(err))
	ns.Options:ImportNodes(ns.Merge.Plan(list), {})
end
local function byName(name)
	for _, r in ipairs(ns.Tree:Reminders()) do if r.name == name then return r end end
end
local function shown(name)
	ns.Core:Evaluate()
	return ns.Display.shown[byName(name).id] or false
end
local function poison(slot, seconds)
	STATE.weapons[slot] = seconds and { { hasEnchant = true, enchantType = 2, enchantID = 7, timeLeft = seconds * 1000 } } or {}
	Fire("WEAPON_ENCHANT_CHANGED")
end
ns.Options.frame:Hide()
STATE.class = "ROGUE"
poison(16, nil) poison(17, nil)
check(shown(MH) and shown(OH), "missing poisons show")
check(ns.Display:FormatText(byName(MH)) == "Main hand poison missing", "text says missing")
poison(16, 1200) poison(17, 300)
check(not shown(MH) and shown(OH), "out of combat: 20 min hides, 5 min shows")
check(ns.Display:FormatText(byName(OH)) == "Off hand poison 5:00", "text shows time left: " .. ns.Display:FormatText(byName(OH)))
STATE.combat = true
check(not shown(MH) and not shown(OH), "in combat: 5 min hides")
poison(17, 30)
check(shown(OH) and ns.Display:FormatText(byName(OH)) == "Off hand poison 30s", "in combat: 30 s shows with time")
STATE.combat = false
STATE.weapons[16] = { { hasEnchant = true, enchantType = 1, enchantID = 1643, timeLeft = 1800000 } }
Fire("WEAPON_ENCHANT_CHANGED")
check(shown(MH) and ns.Display:FormatText(byName(MH)) == "Main hand poison missing", "a sharpening stone does not count as poison")
STATE.bag[8928] = 5
check(ns.Actions:MacroFor(byName(MH)) == "/use item:8928\n/use 16", "click applies best instant poison to main hand")

local out = io.open(TEST_DIR .. "/poison_imports.txt", "w")
out:write(strings.main, "\n\n", strings.off, "\n")
out:close()
