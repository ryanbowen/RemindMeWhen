local _, ns = ...
local L = ns.L

-- Export strings are parsed by hand and never executed. Format: PREFIX then one encoded value.
-- s<len>:<text>  n<number>;  T  F  t<key><value>...e
local Serialize = {}
ns.Serialize = Serialize

local PREFIX = "!RMW1!"
local MAX_LENGTH = 200000
local MAX_NESTING = 40

local function escape(text)
	return (text:gsub("~", "~~"):gsub("|", "~p"):gsub("\n", "~n"):gsub("\r", ""))
end

local UNESCAPE = { ["~"] = "~", p = "|", n = "\n" }
local function unescape(text)
	return (text:gsub("~(.)", UNESCAPE))
end

local function encode(value, out)
	local kind = type(value)
	if kind == "string" then
		local text = escape(value)
		out[#out + 1] = "s" .. #text .. ":" .. text
	elseif kind == "number" then
		out[#out + 1] = "n" .. string.format("%.14g", value) .. ";"
	elseif kind == "boolean" then
		out[#out + 1] = value and "T" or "F"
	elseif kind == "table" then
		out[#out + 1] = "t"
		local keys = {}
		for key in pairs(value) do
			local keyKind = type(key)
			if keyKind == "string" or keyKind == "number" then keys[#keys + 1] = key end
		end
		table.sort(keys, function(a, b)
			if type(a) == type(b) then return a < b end
			return type(a) == "number"
		end)
		for _, key in ipairs(keys) do
			local item = value[key]
			local itemKind = type(item)
			if itemKind == "string" or itemKind == "number" or itemKind == "boolean" or itemKind == "table" then
				encode(key, out)
				encode(item, out)
			end
		end
		out[#out + 1] = "e"
	end
end

function Serialize.Encode(value)
	local out = { PREFIX }
	encode(value, out)
	return table.concat(out)
end

local function decode(text, pos, depth)
	if depth > MAX_NESTING then error("too deeply nested") end
	local tag = text:sub(pos, pos)
	if tag == "s" then
		local digits, rest = text:match("^(%d+):()", pos + 1)
		local length = tonumber(digits)
		if not length then error("bad string at " .. pos) end
		local last = rest + length - 1
		if last > #text then error("string past end") end
		return unescape(text:sub(rest, last)), last + 1
	elseif tag == "n" then
		local number, rest = text:match("^([-+%d%.eE]+);()", pos + 1)
		local value = tonumber(number)
		if not value then error("bad number at " .. pos) end
		return value, rest
	elseif tag == "T" then
		return true, pos + 1
	elseif tag == "F" then
		return false, pos + 1
	elseif tag == "t" then
		local result = {}
		pos = pos + 1
		while true do
			if pos > #text then error("table not closed") end
			if text:sub(pos, pos) == "e" then return result, pos + 1 end
			local key, value
			key, pos = decode(text, pos, depth + 1)
			if type(key) ~= "string" and type(key) ~= "number" then error("bad key") end
			value, pos = decode(text, pos, depth + 1)
			result[key] = value
		end
	end
	error("unexpected '" .. tag .. "' at " .. pos)
end

-- Returns the decoded value, or nil and an error message.
function Serialize.Decode(text)
	if type(text) ~= "string" then return nil, L["Nothing to import."] end
	text = text:gsub("[\r\n]", ""):match("^%s*(.-)%s*$")
	if #text > MAX_LENGTH then return nil, L["The text is too long."] end
	if text:sub(1, #PREFIX) ~= PREFIX then return nil, L["This is not a RemindMeWhen export string."] end
	local ok, value, finish = pcall(decode, text, #PREFIX + 1, 0)
	if not ok then return nil, L["The export string is damaged: "] .. tostring(value) end
	if finish <= #text then return nil, L["The export string has extra text at the end."] end
	return value
end

local COMMON_FIELDS = {
	name = "string", enabled = "boolean", match = "string", x = "number", y = "number", scale = "number",
	uid = "string", revision = "number",
}
local FIELDS = {
	text = "string", icon = "string", delay = "number", sound = "string", repeatSound = "number",
	flash = "boolean", alert = "boolean", trigger = "string", duration = "number",
	progress = "string", progressMax = "number", warnSound = "string",
}
local GROUP_FIELDS = {
	layout = "string", grow = "string", spacing = "number", sort = "string", wrap = "number", align = "string",
	icon = "string",
}
for key, kind in pairs(COMMON_FIELDS) do FIELDS[key], GROUP_FIELDS[key] = kind, kind end

local function copyFields(src, fields, out)
	for key, kind in pairs(fields) do
		if type(src[key]) == kind then out[key] = src[key] end
	end
	if not ns.Versions.IsUID(out.uid) then out.uid = nil end
	if out.revision then out.revision = math.max(1, math.floor(out.revision)) end
	return out
end

local function sanitizeConditions(list, level)
	local out = {}
	if type(list) ~= "table" then return out end
	local Conditions = ns.Conditions
	for _, c in ipairs(list) do
		if type(c) == "table" and type(c.type) == "string" then
			local clean = { type = c.type, negate = c.negate == true }
			if Conditions:IsGroup(c) then
				if level < Conditions.MAX_DEPTH then
					clean.type = Conditions.GROUP
					clean.match = c.match == "ANY" and "ANY" or "ALL"
					clean.conditions = sanitizeConditions(c.conditions, level + 1)
					out[#out + 1] = clean
				end
			else
				local def = Conditions.types[c.type]
				if def then
					for _, param in ipairs(def.params) do
						local value = c[param.key]
						local kind = type(value)
						if (param.kind == "number" and kind == "number")
							or (param.kind == "text" and kind == "string")
							or (param.kind == "choice" and (kind == "string" or kind == "number")) then
							clean[param.key] = value
						end
					end
					out[#out + 1] = clean
				end
			end
		end
	end
	return out
end

-- Keeps only known fields with the expected types. Macro actions are switched off for review.
function Serialize.SanitizeReminder(src)
	if type(src) ~= "table" then return nil end
	local r = copyFields(src, FIELDS, { kind = "reminder" })
	r.conditions = sanitizeConditions(src.conditions, 0)
	r.visual = ns.Core.SanitizeVisual(src.visual)
	r.load = ns.Load.Normalize(src.load)
	r.warnAt = ns.Core.NormalizeWarnings(src.warnAt)
	if type(src.events) == "table" then
		r.events = {}
		for _, trigger in ipairs(ns.Data.triggers) do
			if src.events[trigger.key] == true then r.events[trigger.key] = true end
		end
	end
	local action = src.action
	if type(action) == "table" and ns.Actions.KIND_SET[action.kind] then
		r.action = {
			kind = action.kind,
			spell = type(action.spell) == "string" and action.spell or "",
			item = type(action.item) == "string" and action.item or "",
			macro = type(action.macro) == "string" and action.macro or "",
			slot = action.slot == 17 and 17 or 16,
		}
		if r.action.kind == "macro" then
			r.action.kind = "none"
			r.macroDisabled = true
		end
	end
	return r
end

-- groupLevel: how many groups enclose src. Groups deeper than the limit are dropped.
function Serialize.SanitizeNode(src, groupLevel)
	if type(src) ~= "table" then return nil end
	if src.kind ~= "group" then return Serialize.SanitizeReminder(src) end
	local Tree = ns.Tree
	if groupLevel >= Tree.MAX_GROUP_DEPTH then return nil end
	local g = copyFields(src, GROUP_FIELDS, { kind = "group", items = {} })
	g.conditions = sanitizeConditions(src.conditions, 0)
	g.visual = ns.Core.SanitizeVisual(src.visual)
	g.load = ns.Load.Normalize(src.load)
	for _, child in ipairs(type(src.items) == "table" and src.items or {}) do
		local clean = Serialize.SanitizeNode(child, groupLevel + 1)
		if clean then g.items[#g.items + 1] = clean end
	end
	return g
end

local function stripCharacterData(snapshot)
	snapshot.disabledFor = nil
	for _, item in ipairs(snapshot.items or {}) do stripCharacterData(item) end
	return snapshot
end

-- Exports the given node IDs, each with everything inside it.
function Serialize.Export(ids)
	ns.Versions:Update()
	local list = {}
	for _, id in ipairs(ids) do
		local snapshot = ns.Tree:Snapshot(id)
		if snapshot then list[#list + 1] = stripCharacterData(snapshot) end
	end
	return Serialize.Encode({ version = 2, nodes = list })
end

local function countReminders(list)
	local count = 0
	for _, node in ipairs(list) do
		count = count + (node.kind == "group" and countReminders(node.items) or 1)
	end
	return count
end
Serialize.CountReminders = countReminders

-- Returns a list of clean detached nodes (groups carry their children in "items"),
-- or nil and an error message. Version 1 strings hold plain reminders.
function Serialize.Import(text)
	local data, err = Serialize.Decode(text)
	if not data then return nil, err end
	local empty = L["The export string contains no reminders."]
	if type(data) ~= "table" then return nil, empty end
	local out = {}
	if type(data.nodes) == "table" then
		for _, src in ipairs(data.nodes) do
			local node = Serialize.SanitizeNode(src, 0)
			if node then out[#out + 1] = node end
		end
	elseif type(data.reminders) == "table" then
		for _, src in ipairs(data.reminders) do
			local r = Serialize.SanitizeReminder(src)
			if r then out[#out + 1] = r end
		end
	end
	if #out == 0 then return nil, empty end
	return out
end
