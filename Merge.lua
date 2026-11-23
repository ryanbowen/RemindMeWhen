local _, ns = ...
local L = ns.L

-- Matches imported nodes with existing ones and applies an import as an update.
local Merge = {}
ns.Merge = Merge

-- Parts an update can leave unchanged. The name and revision always follow the import, and the
-- enabled and per-character switches always stay.
Merge.PARTS = {
	{ key = "conditions", label = L["Conditions"], fields = { "conditions", "match" } },
	{ key = "load", label = L["Load settings"], fields = { "load" } },
	{ key = "trigger", label = L["Text, icon and trigger"], fields = { "text", "icon", "trigger", "events", "duration", "delay" } },
	{ key = "sound", label = L["Sound"], fields = { "sound", "repeatSound", "warnAt", "warnSound", "alert" } },
	{ key = "action", label = L["Click action"], fields = { "action", "macroDisabled" } },
	{ key = "look", label = L["Look"], fields = { "visual", "progress", "progressMax" } },
	{ key = "layout", label = L["Group layout"], fields = { "grow", "spacing", "sort", "wrap", "align" } },
	{ key = "position", label = L["Position"], fields = { "x", "y", "scale", "point", "relPoint", "anchorFrame", "anchorTo", "anchorNode" }, keepByDefault = true },
}

local function nameKey(node)
	return node.kind .. "\0" .. (node.name or "")
end

-- Candidates for matching: by permanent ID, and by name and kind when that name is unique.
local function newPool(nodes)
	local pool = { byUID = {}, byName = {} }
	for _, node in ipairs(nodes) do
		if node.uid then pool.byUID[node.uid] = node end
		local key = nameKey(node)
		pool.byName[key] = pool.byName[key] == nil and node or false
	end
	return pool
end

local function findMatch(incoming, pool, claimed)
	local node = incoming.uid and pool.byUID[incoming.uid]
	if node and node.kind == incoming.kind and not claimed[node.id] then return node end
	node = pool.byName[nameKey(incoming)]
	if node and not claimed[node.id] then return node end
	return nil
end

local function descendants(group)
	local out = {}
	ns.Tree:Walk(function(node) out[#out + 1] = node end, group.children)
	return out
end

-- Returns a plan: entries (one per imported top node) with status "new", "newer", "same" or
-- "older", nested entries for group contents, and leftovers (existing contents of updated groups
-- that the import does not have). Nothing changes until Apply.
function Merge.Plan(list)
	ns.Versions:Update()
	local all = {}
	for _, node in pairs(ns.db.nodes) do all[#all + 1] = node end
	local topPool = newPool(all)
	local plan = { entries = {}, matches = 0, notNewer = 0, leftovers = {} }
	local claimed = {}

	local function planNode(incoming, pool)
		local existing = pool and findMatch(incoming, pool, claimed)
		local entry = { incoming = incoming, existing = existing, status = "new" }
		if existing then
			claimed[existing.id] = true
			plan.matches = plan.matches + 1
			local theirs, mine = incoming.revision or 1, existing.revision or 1
			entry.status = theirs > mine and "newer" or theirs == mine and "same" or "older"
			if entry.status ~= "newer" then plan.notNewer = plan.notNewer + 1 end
		end
		if incoming.kind == "group" then
			local inner = existing and ns.Tree:IsGroup(existing) and newPool(descendants(existing)) or nil
			entry.children = {}
			for _, item in ipairs(incoming.items) do entry.children[#entry.children + 1] = planNode(item, inner) end
		end
		return entry
	end
	for _, incoming in ipairs(list) do plan.entries[#plan.entries + 1] = planNode(incoming, topPool) end

	local function collectLeftovers(entry)
		if entry.existing and entry.children then
			for _, id in ipairs(entry.existing.children) do
				if not claimed[id] then plan.leftovers[#plan.leftovers + 1] = ns.Tree:Get(id) end
			end
		end
		for _, child in ipairs(entry.children or {}) do collectLeftovers(child) end
	end
	for _, entry in ipairs(plan.entries) do collectLeftovers(entry) end
	return plan
end

local function setFields(node, incoming, keep)
	for _, part in ipairs(Merge.PARTS) do
		if not keep[part.key] then
			for _, field in ipairs(part.fields) do node[field] = ns.Compat.CopyTable(incoming[field]) end
		end
	end
	node.name = incoming.name
	node.revision = incoming.revision or 1
	ns.Core:NormalizeNode(node)
end

local function countMacros(snapshot)
	if snapshot.kind == "group" then
		local count = 0
		for _, item in ipairs(snapshot.items or {}) do count = count + countMacros(item) end
		return count
	end
	return snapshot.macroDisabled and 1 or 0
end

-- Adds an unmatched imported subtree. Permanent IDs already used here are replaced.
local function addNew(snapshot, parentID, index)
	local function clearTaken(node)
		if ns.Versions:FindByUID(node.uid) then node.uid = nil end
		for _, item in ipairs(node.items or {}) do clearTaken(item) end
	end
	clearTaken(snapshot)
	local Tree = ns.Tree
	if parentID and parentID ~= Tree.ROOT and not Tree:CanPlace(snapshot, parentID) then
		parentID, index = ns.Core:InsertTarget(parentID, snapshot)
	end
	return ns.Core:AddSnapshot(snapshot, parentID, index)
end

local function localize(snapshot)
	ns.Presets:Localize(snapshot)
	for _, item in ipairs(snapshot.items or {}) do localize(item) end
end

-- options.place(snapshot): parent ID and index for a new top-level node.
-- options.asCopy: add everything as new copies. Otherwise matched nodes are updated:
-- options.keep (part key -> true) keeps those parts as they are, and options.remove
-- (node ID -> true) deletes those leftovers.
-- Returns the updated or added top nodes and how many reminders had a macro switched off.
function Merge.Apply(plan, options)
	local Tree, Core = ns.Tree, ns.Core
	local keep, remove = options.keep or {}, options.remove or {}
	local macros = 0
	for _, entry in ipairs(plan.entries) do localize(entry.incoming) end

	local applyEntry
	local function applyChildren(entry, group)
		local index = 0
		for _, child in ipairs(entry.children) do
			if child.existing then
				applyEntry(child)
				if Tree:CanPlace(child.existing, group.id) then
					index = index + 1
					Tree:Move(child.existing.id, group.id, index)
				end
			else
				local canPlace = Tree:CanPlace(child.incoming, group.id)
				if canPlace then index = index + 1 end
				macros = macros + countMacros(child.incoming)
				addNew(child.incoming, group.id, canPlace and index or nil)
			end
		end
	end

	function applyEntry(entry)
		local node, incoming = entry.existing, entry.incoming
		if not keep.action and incoming.macroDisabled then macros = macros + 1 end
		setFields(node, incoming, keep)
		if Tree:IsGroup(node) and not keep.layout then node.layout = incoming.layout == "static" and "static" or "dynamic" end
		if entry.children then applyChildren(entry, node) end
		return node
	end

	if options.asCopy then
		local incoming = {}
		for i, entry in ipairs(plan.entries) do incoming[i] = entry.incoming end
		ns.Versions.RenewUIDs(incoming)
	end
	local top = {}
	for _, entry in ipairs(plan.entries) do
		if entry.existing and not options.asCopy then
			top[#top + 1] = applyEntry(entry)
		else
			macros = macros + countMacros(entry.incoming)
			local parentID, index = options.place(entry.incoming)
			top[#top + 1] = addNew(entry.incoming, parentID, index)
		end
	end
	if not options.asCopy then
		for _, node in ipairs(plan.leftovers) do
			if remove[node.id] and Tree:Get(node.id) then Core:DeleteNode(node.id) end
		end
	end
	ns.Versions:EnsureUIDs()
	ns.Versions:Settle()
	Core:ConfigChanged()
	return top, macros
end
