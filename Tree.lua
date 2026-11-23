local _, ns = ...
local Compat = ns.Compat

-- Reminders and groups are nodes in db.nodes, keyed by ID. db.root and each group's children list
-- child IDs in order, and the parent index is built from those lists.
local Tree = { parent = {} }
ns.Tree = Tree

Tree.ROOT = 0
Tree.MAX_GROUP_DEPTH = 3

Tree.VISUAL_DEFAULTS = {
	iconSize = 40,
	showText = true,
	fontSize = 16,
	textPos = "RIGHT",
	textColor = { 1, 0.82, 0 },
	glow = true,
	timer = true,
	sweep = true,
	style = "icon",
	barWidth = 220,
	barHeight = 24,
	barTexture = "blizzard",
	barColor = { 0.2, 0.55, 1 },
	barBackground = { 0.08, 0.08, 0.1 },
	iconSide = "LEFT",
	barReverse = false,
}
Tree.VISUAL_KEYS = {
	"iconSize", "showText", "fontSize", "textPos", "textColor", "glow", "timer", "sweep",
	"style", "barWidth", "barHeight", "barTexture", "barColor", "barBackground", "iconSide", "barReverse",
}

local function db() return ns.db end

function Tree:Get(id)
	return id and db().nodes[id] or nil
end

function Tree:IsGroup(node)
	return node ~= nil and node.kind == "group"
end

function Tree:ChildList(id)
	if id == nil or id == self.ROOT then return db().root end
	local node = self:Get(id)
	return node and node.children or nil
end

function Tree:Parent(id)
	return self.parent[id]
end

function Tree:ParentNode(id)
	local parent = self.parent[id]
	if parent == nil or parent == self.ROOT then return nil end
	return self:Get(parent)
end

-- Rebuilds the parent index and drops IDs that point nowhere or appear twice.
function Tree:Reindex()
	local seen = {}
	wipe(self.parent)
	local function scan(list, parentID)
		local i = 1
		while i <= #list do
			local id = list[i]
			local node = db().nodes[id]
			if node and not seen[id] then
				seen[id] = true
				self.parent[id] = parentID
				if self:IsGroup(node) then scan(node.children, id) end
				i = i + 1
			else
				table.remove(list, i)
			end
		end
	end
	scan(db().root, self.ROOT)
	for id in pairs(db().nodes) do
		if not seen[id] then db().nodes[id] = nil end
	end
end

function Tree:IndexOf(id)
	local list = self:ChildList(self.parent[id])
	for i, child in ipairs(list or {}) do
		if child == id then return i, list end
	end
	return nil
end

-- Calls fn(node, level, parentID) for every node in tree order, with level 0 at the top.
function Tree:Walk(fn, list, level, parentID)
	list, level, parentID = list or db().root, level or 0, parentID or self.ROOT
	for _, id in ipairs(list) do
		local node = db().nodes[id]
		if node then
			if fn(node, level, parentID) ~= false and self:IsGroup(node) then
				self:Walk(fn, node.children, level + 1, id)
			end
		end
	end
end

function Tree:Reminders(startID)
	local out = {}
	local start = startID and self:Get(startID)
	if start and not self:IsGroup(start) then return { start } end
	self:Walk(function(node)
		if not self:IsGroup(node) then out[#out + 1] = node end
	end, start and start.children or nil)
	return out
end

-- Number of groups from the top down to and including this node (0 for the root).
function Tree:GroupDepth(id)
	local depth = 0
	while id and id ~= self.ROOT do
		local node = self:Get(id)
		if self:IsGroup(node) then depth = depth + 1 end
		id = self.parent[id]
	end
	return depth
end

-- How many group levels this node adds: 0 for a reminder, 1 + deepest child group for a group.
-- Works for attached nodes (children IDs) and snapshots (nested items).
function Tree:GroupHeight(node)
	if not self:IsGroup(node) then return 0 end
	local height = 1
	if node.items then
		for _, item in ipairs(node.items) do height = math.max(height, 1 + self:GroupHeight(item)) end
	else
		for _, id in ipairs(node.children or {}) do height = math.max(height, 1 + self:GroupHeight(self:Get(id))) end
	end
	return height
end

function Tree:IsAncestor(ancestorID, id)
	while id and id ~= self.ROOT do
		if id == ancestorID then return true end
		id = self.parent[id]
	end
	return false
end

-- Whether node (attached or not) may live under parentID.
function Tree:CanPlace(node, parentID)
	if parentID == nil or parentID == self.ROOT then
		return self:GroupHeight(node) <= self.MAX_GROUP_DEPTH
	end
	local parent = self:Get(parentID)
	if not self:IsGroup(parent) then return false end
	if node.id and self:IsAncestor(node.id, parentID) then return false end
	return self:GroupDepth(parentID) + self:GroupHeight(node) <= self.MAX_GROUP_DEPTH
end

function Tree:Insert(node, parentID, index)
	parentID = parentID or self.ROOT
	local list = self:ChildList(parentID)
	db().nodes[node.id] = node
	index = math.max(1, math.min(index or (#list + 1), #list + 1))
	table.insert(list, index, node.id)
	self.parent[node.id] = parentID
	return node
end

function Tree:Detach(id)
	local index, list = self:IndexOf(id)
	if index then table.remove(list, index) end
	self.parent[id] = nil
	return index
end

-- Moves a node to position index under parentID. Returns false when the move is not allowed.
function Tree:Move(id, parentID, index)
	parentID = parentID or self.ROOT
	local node = self:Get(id)
	if not node or not self:CanPlace(node, parentID) then return false end
	local oldParent = self.parent[id]
	local oldIndex = self:Detach(id)
	local list = self:ChildList(parentID)
	if oldParent == parentID and oldIndex and index and oldIndex < index then index = index - 1 end
	index = math.max(1, math.min(index or (#list + 1), #list + 1))
	table.insert(list, index, id)
	self.parent[id] = parentID
	return true
end

-- Removes a node. With keepChildren, a group's children take its place in its parent.
-- Returns the IDs of every node that was removed.
function Tree:Remove(id, keepChildren)
	local node = self:Get(id)
	if not node then return {} end
	local parentID = self.parent[id]
	local index = self:Detach(id)
	local removed = { id }
	db().nodes[id] = nil
	if self:IsGroup(node) then
		if keepChildren then
			local list = self:ChildList(parentID)
			for offset, childID in ipairs(node.children) do
				table.insert(list, (index or #list + 1) + offset - 1, childID)
				self.parent[childID] = parentID
			end
		else
			for _, childID in ipairs(node.children) do
				self.parent[childID] = id
				for _, gone in ipairs(self:Remove(childID)) do removed[#removed + 1] = gone end
			end
		end
	end
	return removed
end

-- Returns a detached deep copy of the subtree with child nodes nested under "items" instead of IDs.
function Tree:Snapshot(id)
	local node = self:Get(id)
	if not node then return nil end
	local copy = Compat.CopyTable(node)
	copy.id = nil
	if self:IsGroup(node) then
		copy.children = nil
		copy.items = {}
		for _, childID in ipairs(node.children) do copy.items[#copy.items + 1] = self:Snapshot(childID) end
	end
	return copy
end

-- Attaches a snapshot (see Snapshot) under parentID, giving every node a fresh ID via newID.
function Tree:Restore(snapshot, parentID, index, newID, normalize)
	local items = snapshot.items
	snapshot.items = nil
	snapshot.id = newID()
	if snapshot.kind == "group" then snapshot.children = {} end
	normalize(snapshot)
	self:Insert(snapshot, parentID, index)
	if snapshot.kind == "group" then
		for _, item in ipairs(items or {}) do
			if self:CanPlace(item, snapshot.id) then self:Restore(item, snapshot.id, nil, newID, normalize) end
		end
	end
	return snapshot
end

-- Nearest setting up the tree: the node, its groups, the global defaults, then built-in defaults.
function Tree:Visual(node, key)
	local id = node and node.id
	while node do
		local value = node.visual and node.visual[key]
		if value ~= nil then return value end
		id = self.parent[id]
		node = id and id ~= self.ROOT and self:Get(id) or nil
	end
	local global = db().display.visual
	if global and global[key] ~= nil then return global[key] end
	return self.VISUAL_DEFAULTS[key]
end

-- What a node would inherit if it had no override of its own.
function Tree:InheritedVisual(node, key)
	local parent = node and self:ParentNode(node.id)
	if parent then return self:Visual(parent, key) end
	local global = db().display.visual
	if global and global[key] ~= nil then return global[key] end
	return self.VISUAL_DEFAULTS[key]
end

-- A node has its own screen position unless a dynamic group lays it out.
function Tree:IsPositioned(node)
	local parent = self:ParentNode(node.id)
	return not (parent and parent.layout == "dynamic")
end
