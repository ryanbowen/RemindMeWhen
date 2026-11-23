local _, ns = ...
local Compat = ns.Compat

-- Shared logic for comma separated "Name (ID)" lists, where the ID decides and the name is a label.
local Resolver = {}
ns.Resolver = Resolver

Resolver.OK, Resolver.LOADING, Resolver.UNVERIFIED, Resolver.MISSING = "ok", "loading", "unverified", "missing"
local RANK = { ok = 1, loading = 2, unverified = 3, missing = 4 }

-- Returns the ID (or nil) and the typed name (nil when the token is a bare ID).
function Resolver.ParseToken(token)
	local label, id = token:match("^(.-)%s*%((%d+)%)$")
	if id then return tonumber(id), label end
	id = tonumber(token)
	if id then return id, nil end
	return nil, token
end

local Mixin = {}
Resolver.Mixin = Mixin

function Mixin:Format(entry)
	return string.format("%s (%d)", entry.name, entry.id)
end

function Mixin:Canonicalize(text)
	local out = {}
	for _, token in ipairs(Compat.SplitList(text)) do
		local result = self:Resolve(token)
		out[#out + 1] = result.status == Resolver.OK and self:Format(result) or token
	end
	return table.concat(out, ", ")
end

-- Returns the resolved entries and the worst status among them.
function Mixin:Check(text)
	local results, worst = {}, nil
	for _, token in ipairs(Compat.SplitList(text)) do
		local result = self:Resolve(token)
		results[#results + 1] = result
		if not worst or RANK[result.status] > RANK[worst] then worst = result.status end
	end
	return results, worst
end

function Mixin:RequestLoad(id)
	if self.pending[id] then return end
	self.pending[id] = true
	self:LoadData(id)
end

function Mixin:OnLoaded(id)
	if not self.pending[id] then return false end
	self.pending[id] = nil
	return true
end

function Resolver.New(module)
	module.pending = {}
	for key, fn in pairs(Mixin) do module[key] = module[key] or fn end
	module.OK, module.LOADING, module.UNVERIFIED, module.MISSING = Resolver.OK, Resolver.LOADING, Resolver.UNVERIFIED, Resolver.MISSING
	module.ParseToken = Resolver.ParseToken
	return module
end
