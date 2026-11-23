local _, ns = ...
local Tree = ns.Tree

-- What a top-level reminder or group is anchored to, and the checks that keep node anchors from
-- forming loops. Nodes inside groups always follow their group.
local Anchors = {}
ns.Anchors = Anchors

Anchors.KINDS = { SCREEN = true, FRAME = true, NODE = true, MOUSE = true }

function Anchors.IsTopLevel(node)
	return Tree:Parent(node.id) == Tree.ROOT
end

-- The top-level node that holds id, or id itself at the top level.
function Anchors.Root(id)
	local parent = Tree:Parent(id)
	while parent and parent ~= Tree.ROOT do
		id = parent
		parent = Tree:Parent(id)
	end
	return id
end

local function storedTarget(node)
	if node.anchorTo ~= "NODE" or node.anchorNode == "" or not Anchors.IsTopLevel(node) then return nil end
	return ns.Versions:FindByUID(node.anchorNode)
end

-- Whether node can anchor to target: not itself or anything inside it, and no chain of node
-- anchors that leads back to it.
function Anchors.CanAnchor(node, target)
	if not target or Tree:IsAncestor(node.id, target.id) then return false end
	local seen = {}
	local id = Anchors.Root(target.id)
	while id and not seen[id] do
		if id == node.id then return false end
		seen[id] = true
		local next = storedTarget(Tree:Get(id))
		id = next and Anchors.Root(next.id)
	end
	return true
end

-- The node that node follows, or nil when it is not anchored to a node or the anchor is not allowed.
function Anchors.Resolve(node)
	local target = storedTarget(node)
	if target and Anchors.CanAnchor(node, target) then return target end
	return nil
end

-- Whether moving node id also moves otherID: it is id or inside it, or its top-level node follows
-- (through a chain of node anchors) id or something inside it.
function Anchors.MovesWith(otherID, id)
	local seen = {}
	while otherID and not seen[otherID] do
		if Tree:IsAncestor(id, otherID) then return true end
		seen[otherID] = true
		local root = Tree:Get(Anchors.Root(otherID))
		local target = root and Anchors.Resolve(root)
		otherID = target and target.id
	end
	return false
end

-- list reordered so that each node comes after the top-level node it follows.
function Anchors.Order(list)
	local inList, placed, out = {}, {}, {}
	for _, id in ipairs(list) do inList[id] = true end
	local remaining = list
	while #remaining > 0 do
		local rest = {}
		for _, id in ipairs(remaining) do
			local node = Tree:Get(id)
			local target = node and Anchors.Resolve(node)
			local after = target and Anchors.Root(target.id)
			if not after or not inList[after] or placed[after] then
				out[#out + 1] = id
				placed[id] = true
			else
				rest[#rest + 1] = id
			end
		end
		if #rest == #remaining then
			for _, id in ipairs(rest) do out[#out + 1] = id end
			break
		end
		remaining = rest
	end
	return out
end
