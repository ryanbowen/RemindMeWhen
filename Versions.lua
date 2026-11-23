local _, ns = ...

-- Permanent IDs and content revisions, used to recognise imports of things already here.
local Versions = { fingerprints = {} }
ns.Versions = Versions

local UID_CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local UID_LENGTH = 12
local MAX_UID_LENGTH = 32
-- Not content: identity, revision and the settings that belong to the player.
local PERSONAL = {
	id = true, uid = true, revision = true, children = true, items = true,
	enabled = true, disabledFor = true, x = true, y = true, scale = true,
	point = true, relPoint = true, anchorFrame = true, anchorTo = true, anchorNode = true,
}

function Versions.IsUID(value)
	return type(value) == "string" and #value <= MAX_UID_LENGTH and value:match("^%w+$") ~= nil
end

function Versions.NewUID()
	local out = {}
	for i = 1, UID_LENGTH do
		local n = math.random(1, #UID_CHARS)
		out[i] = UID_CHARS:sub(n, n)
	end
	return table.concat(out)
end

function Versions:FindByUID(uid)
	if not uid then return nil end
	for _, node in pairs(ns.db.nodes) do
		if node.uid == uid then return node end
	end
	return nil
end

-- Gives every node a permanent ID. Of two nodes sharing one, the later in tree order gets a new one.
function Versions:EnsureUIDs()
	local seen = {}
	ns.Tree:Walk(function(node)
		if not self.IsUID(node.uid) or seen[node.uid] then
			repeat node.uid = self.NewUID() until not seen[node.uid]
		end
		seen[node.uid] = true
	end)
end

-- Gives detached subtrees new permanent IDs so they are added as something new. Node anchors between
-- their nodes follow the new IDs.
function Versions.RenewUIDs(snapshots)
	local renamed, all = {}, {}
	local function renew(node)
		local uid = Versions.NewUID()
		if node.uid then renamed[node.uid] = uid end
		node.uid = uid
		all[#all + 1] = node
		for _, item in ipairs(node.items or {}) do renew(item) end
	end
	for _, snapshot in ipairs(snapshots) do renew(snapshot) end
	for _, node in ipairs(all) do
		if node.anchorNode and renamed[node.anchorNode] then node.anchorNode = renamed[node.anchorNode] end
	end
	return snapshots
end

local function hash(text)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
	return h
end

-- A number that changes when the node's content does. A group's includes its children in order.
function Versions:Fingerprint(node)
	local content = {}
	for key, value in pairs(node) do
		if not PERSONAL[key] then content[key] = value end
	end
	if ns.Tree:IsGroup(node) then
		local children = {}
		for i, id in ipairs(node.children) do
			local child = ns.Tree:Get(id)
			children[i] = child and self:Fingerprint(child) or 0
		end
		content.children = children
	end
	return hash(ns.Serialize.Encode(content))
end

-- Records the current fingerprints without changing revisions.
function Versions:Settle()
	wipe(self.fingerprints)
	ns.Tree:Walk(function(node) self.fingerprints[node.id] = self:Fingerprint(node) end)
end

-- Counts edits since the last check: each node whose content changed goes up one revision.
-- Runs when the editor moves to another node or closes, before exporting and at logout, so a
-- session of edits to one node counts once.
function Versions:Update()
	ns.Tree:Walk(function(node)
		local fingerprint = self:Fingerprint(node)
		local before = self.fingerprints[node.id]
		if before and before ~= fingerprint then node.revision = (node.revision or 1) + 1 end
		self.fingerprints[node.id] = fingerprint
	end)
end
