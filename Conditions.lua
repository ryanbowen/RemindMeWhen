local _, ns = ...
local Compat, L = ns.Compat, ns.L

-- Each condition evaluates to true, false, or nil when the game hides the answer right now.
-- A condition of type GROUP holds its own list and All/Any setting.
local Conditions = { types = {}, order = {}, errors = setmetatable({}, { __mode = "k" }) }
ns.Conditions = Conditions

Conditions.GROUP = "conditionGroup"
Conditions.MAX_DEPTH = 3
-- Version 1.1.0 stored nested groups as type "group", which is also the party/raid condition.
local LEGACY_GROUP = "group"

function Conditions:Define(key, def)
	def.key = key
	def.params = def.params or {}
	self.types[key] = def
	self.order[#self.order + 1] = key
end

-- Stores a placeholder value unless an earlier condition already set it.
function Conditions.SetVar(vars, key, value)
	if vars and vars[key] == nil and value ~= nil then vars[key] = value end
end

function Conditions:IsGroup(c)
	return c.type == self.GROUP or (c.type == LEGACY_GROUP and type(c.conditions) == "table")
end

function Conditions:Normalize(c)
	c.negate = c.negate and true or false
	if self:IsGroup(c) then
		c.type = self.GROUP
		c.match = c.match == "ANY" and "ANY" or "ALL"
		c.conditions = type(c.conditions) == "table" and c.conditions or {}
		for _, child in ipairs(c.conditions) do self:Normalize(child) end
		return c
	end
	local def = self.types[c.type]
	if def then
		for _, param in ipairs(def.params) do
			if c[param.key] == nil then c[param.key] = param.default end
		end
	end
	return c
end

function Conditions:SetType(c, key)
	for k in pairs(c) do
		if k ~= "negate" then c[k] = nil end
	end
	c.type = key
	if key == self.GROUP then c.match, c.conditions = "ALL", {} end
	return self:Normalize(c)
end

local leafChoices, allChoices
function Conditions:TypeChoices(level)
	if not leafChoices then
		leafChoices = {}
		for _, key in ipairs(self.order) do
			leafChoices[#leafChoices + 1] = { value = key, label = self.types[key].label }
		end
		allChoices = { { value = self.GROUP, label = L["Group of conditions..."] } }
		for _, choice in ipairs(leafChoices) do allChoices[#allChoices + 1] = choice end
	end
	if (level or 0) < self.MAX_DEPTH then return allChoices end
	return leafChoices
end

local categoryMenu
-- The type choices by category (see CATEGORIES), for the condition type menu.
function Conditions:TypeMenu(level)
	if not categoryMenu then
		categoryMenu = {}
		local listed = {}
		for _, category in ipairs(self.CATEGORIES or {}) do
			local children = {}
			for _, key in ipairs(category.types) do
				local def = self.types[key]
				if def and not listed[key] then
					listed[key] = true
					children[#children + 1] = { value = key, label = def.label }
				end
			end
			if #children > 0 then categoryMenu[#categoryMenu + 1] = { label = category.label, children = children } end
		end
		local other = {}
		for _, key in ipairs(self.order) do
			if not listed[key] then other[#other + 1] = { value = key, label = self.types[key].label } end
		end
		if #other > 0 then categoryMenu[#categoryMenu + 1] = { label = L["Other"], children = other } end
	end
	if (level or 0) >= self.MAX_DEPTH then return categoryMenu end
	local withGroup = { { value = self.GROUP, label = L["Group of conditions..."] } }
	for _, category in ipairs(categoryMenu) do withGroup[#withGroup + 1] = category end
	return withGroup
end

function Conditions:Evaluate(c, vars)
	local result
	if self:IsGroup(c) then
		result = self:EvaluateList(c.conditions, c.match, vars)
	else
		local def = self.types[c.type]
		if not def then return nil end
		local ok, value = pcall(def.eval, c, vars)
		if not ok then
			self.errors[c] = tostring(value)
			return nil
		end
		self.errors[c] = nil
		result = value
	end
	if result == nil then return nil end
	result = result and true or false
	if c.negate then return not result end
	return result
end

-- Every condition is evaluated each pass, so aura state is already known when it turns secret.
function Conditions:EvaluateList(list, match, vars)
	if #list == 0 then return false end
	local anyTrue, anyFalse, unknown = false, false, false
	for _, c in ipairs(list) do
		local value = self:Evaluate(c, vars)
		if value == nil then
			unknown = true
		elseif value then
			anyTrue = true
		else
			anyFalse = true
		end
	end
	if match == "ANY" then
		if anyTrue then return true end
		if unknown then return nil end
		return false
	end
	if anyFalse then return false end
	if unknown then return nil end
	return true
end

-- Returns the result and the placeholder values collected on the way.
function Conditions:EvaluateReminder(r)
	local vars = {}
	return self:EvaluateList(r.conditions, r.match, vars), vars
end

function Conditions:GetIcon(c)
	if self:IsGroup(c) then
		for _, child in ipairs(c.conditions) do
			local icon = self:GetIcon(child)
			if icon then return icon end
		end
		return nil
	end
	local def = self.types[c.type]
	if not (def and def.icon) then return nil end
	local ok, icon = pcall(def.icon, c)
	if not ok or Compat.IsSecret(icon) then return nil end
	return icon
end

function Conditions:Walk(list, fn, level)
	level = level or 0
	for index, c in ipairs(list) do
		fn(c, list, index, level)
		if self:IsGroup(c) then self:Walk(c.conditions, fn, level + 1) end
	end
end

-- Depth of the deepest group below this condition (0 for a plain condition).
function Conditions:GroupDepth(c)
	if not self:IsGroup(c) then return 0 end
	local depth = 1
	for _, child in ipairs(c.conditions) do depth = math.max(depth, 1 + self:GroupDepth(child)) end
	return depth
end
