local _, ns = ...
local Compat, L = ns.Compat, ns.L

-- Load rules limit a reminder or group (and its contents) to some classes, a level range and some
-- characters. Nodes that are not loaded are never evaluated, and empty parts (no classes, level 0,
-- no names) do not restrict anything.
-- node.load = { classes = { MAGE = true }, minLevel = 0, maxLevel = 0, characters = "Name, Name-Realm" }
local Load = {}
ns.Load = Load

Load.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_SET = {}
for _, token in ipairs(Load.CLASSES) do CLASS_SET[token] = true end
Load.MAX_LEVEL = 60

function Load.ClassName(token)
	return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] or token
end

local function clampLevel(value)
	return math.max(0, math.min(Load.MAX_LEVEL, math.floor(tonumber(value) or 0)))
end

-- Returns a clean copy, or nil when nothing is restricted.
function Load.Normalize(load)
	if type(load) ~= "table" then return nil end
	local out = { classes = {}, minLevel = clampLevel(load.minLevel), maxLevel = clampLevel(load.maxLevel), characters = "" }
	local any = false
	if type(load.classes) == "table" then
		for token, on in pairs(load.classes) do
			if CLASS_SET[token] and on == true then
				out.classes[token] = true
				any = true
			end
		end
	end
	if type(load.characters) == "string" then
		local names = {}
		for name in load.characters:gmatch("[^,]+") do
			name = name:match("^%s*(.-)%s*$")
			if name ~= "" then names[#names + 1] = name end
		end
		out.characters = table.concat(names, ", ")
	end
	if out.maxLevel > 0 and out.minLevel > out.maxLevel then out.minLevel, out.maxLevel = out.maxLevel, out.minLevel end
	if not any and out.minLevel == 0 and out.maxLevel == 0 and out.characters == "" then return nil end
	return out
end

local function characterListed(list)
	local key = Compat.CharKey():lower()
	local name = key:match("^(.-)%-") or key
	for entry in list:gmatch("[^,]+") do
		entry = entry:match("^%s*(.-)%s*$"):lower()
		if entry == key or entry == name then return true end
	end
	return false
end

-- Returns true when the rules allow this character, or false and the reason.
function Load.Check(load)
	if not load then return true end
	if next(load.classes) then
		local _, token = UnitClass("player")
		if not load.classes[token] then return false, L["class"] end
	end
	local level = UnitLevel("player") or 0
	if load.minLevel > 0 and level < load.minLevel then return false, L["level"] end
	if load.maxLevel > 0 and level > load.maxLevel then return false, L["level"] end
	if load.characters ~= "" and not characterListed(load.characters) then return false, L["character"] end
	return true
end

function Load.Matches(load)
	return (Load.Check(load))
end
