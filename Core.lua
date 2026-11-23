local addonName, ns = ...
local Compat, Data, Conditions, Tracker, Tree, Layout, Display, Actions, Options, L =
	ns.Compat, ns.Data, ns.Conditions, ns.Tracker, ns.Tree, ns.Layout, ns.Display, ns.Actions, ns.Options, ns.L

local Core = { state = {} }
ns.Core = Core

local DISPLAY_DEFAULTS = {
	locked = true,
	clickToDismiss = true,
	hideWhenDead = true,
	hideOnTaxi = true,
	editWhileOptions = true,
}

local GROW = { DOWN = true, UP = true, LEFT = true, RIGHT = true, HCENTER = true, VCENTER = true }
local SORT = { order = true, timeLeft = true, name = true }
local ALIGN = { LEFT = true, CENTER = true, RIGHT = true }
local TEXT_POS = { RIGHT = true, LEFT = true, TOP = true, BOTTOM = true, CENTER = true }
local VISUAL_TYPES = {
	iconSize = "number", showText = "boolean", fontSize = "number", textPos = "string",
	textColor = "table", glow = "boolean", timer = "boolean", sweep = "boolean",
	style = "string", barWidth = "number", barHeight = "number", barTexture = "string",
	barColor = "table", barBackground = "table", iconSide = "string", barReverse = "boolean",
}
local VISUAL_RANGES = { iconSize = { 6, 128 }, fontSize = { 6, 128 }, barWidth = { 20, 800 }, barHeight = { 6, 128 } }
local VISUAL_CHOICES = {
	textPos = TEXT_POS,
	style = { icon = true, bar = true },
	iconSide = { LEFT = true, RIGHT = true, NONE = true },
	barTexture = Data.barTextureByKey,
}
Core.GROW, Core.SORT, Core.ALIGN, Core.TEXT_POS = GROW, SORT, ALIGN, TEXT_POS

local TEST_SECONDS = 6
local DEFAULT_EVENT_SECONDS = 10
local MIN_INTERVAL, MAX_INTERVAL = 0.1, 0.5
local NEW_ROOT_Y = 120
-- Size of the 1.1 anchor handle and the gap below it where its reminders started.
local OLD_ANCHOR_W, OLD_ANCHOR_H, OLD_ANCHOR_GAP = 220, 32, 4

local EVENTS = {
	"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_AURA",
	"PLAYER_MOUNT_DISPLAY_CHANGED", "MOUNT_JOURNAL_USABILITY_CHANGED", "COMPANION_UPDATE", "COMPANION_LEARNED",
	"NEW_MOUNT_ADDED", "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "WEAPON_ENCHANT_CHANGED",
	"BAG_UPDATE_DELAYED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
	"GROUP_ROSTER_UPDATE", "UNIT_PET", "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS",
	"UPDATE_STEALTH", "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
	"MINIMAP_UPDATE_TRACKING", "SPELL_UPDATE_COOLDOWN", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
	"PLAYER_CONTROL_GAINED", "PLAYER_CONTROL_LOST", "SPELL_DATA_LOAD_RESULT", "ITEM_DATA_LOAD_RESULT",
	"GET_ITEM_INFO_RECEIVED", "READY_CHECK", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED",
	"UPDATE_INVENTORY_DURABILITY", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "UNIT_HAPPINESS", "PET_UI_UPDATE",
	"UNIT_CONNECTION", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_MONEY", "PLAYER_TOTEM_UPDATE",
	"ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_FLAGS_CHANGED", "PARTY_LEADER_CHANGED", "BAG_UPDATE_COOLDOWN",
	"UNIT_FACTION",
}
local PLAYER_UNIT_EVENTS = {
	"UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_POWER_UPDATE",
}

function Core:Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99RemindMeWhen|r: " .. tostring(message))
end

function Core:NextID()
	local id = ns.db.nextID
	ns.db.nextID = id + 1
	return id
end

local function sanitizeVisual(visual)
	local out = {}
	if type(visual) ~= "table" then return out end
	for key, kind in pairs(VISUAL_TYPES) do
		local value = visual[key]
		if type(value) == kind then
			if kind == "table" then
				if type(value[1]) == "number" and type(value[2]) == "number" and type(value[3]) == "number" then
					out[key] = { value[1], value[2], value[3] }
				end
			elseif VISUAL_CHOICES[key] then
				if VISUAL_CHOICES[key][value] then out[key] = value end
			elseif kind == "number" then
				local range = VISUAL_RANGES[key]
				out[key] = math.max(range[1], math.min(range[2], value))
			else
				out[key] = value
			end
		end
	end
	return out
end
Core.SanitizeVisual = sanitizeVisual

local function normalizeCommon(node, defaultName)
	node.id = node.id or Core:NextID()
	if not ns.Versions.IsUID(node.uid) then node.uid = ns.Versions.NewUID() end
	node.revision = math.max(1, math.floor(tonumber(node.revision) or 1))
	node.name = type(node.name) == "string" and node.name or defaultName
	if node.enabled == nil then node.enabled = true end
	node.enabled = node.enabled and true or false
	if type(node.disabledFor) ~= "table" then node.disabledFor = nil end
	node.load = ns.Load.Normalize(node.load)
	node.match = node.match == "ANY" and "ANY" or "ALL"
	node.conditions = type(node.conditions) == "table" and node.conditions or {}
	for _, c in ipairs(node.conditions) do Conditions:Normalize(c) end
	node.x = tonumber(node.x) or 0
	node.y = tonumber(node.y) or 0
	node.scale = math.max(0.3, math.min(3, tonumber(node.scale) or 1))
	node.visual = sanitizeVisual(node.visual)
end

local MAX_WARNINGS = 5

-- Seconds left at which a shown reminder warns again, largest first.
local function normalizeWarnings(list)
	local out, seen = {}, {}
	if type(list) ~= "table" then return out end
	for _, value in ipairs(list) do
		value = tonumber(value)
		if value and value >= 1 and not seen[math.floor(value)] and #out < MAX_WARNINGS then
			value = math.floor(value)
			seen[value] = true
			out[#out + 1] = value
		end
	end
	table.sort(out, function(a, b) return a > b end)
	return out
end
Core.NormalizeWarnings = normalizeWarnings

function Core:NormalizeReminder(r)
	r.kind = "reminder"
	if r.flash == false and r.visual == nil then r.visual = { glow = false } end
	r.flash, r.anchor = nil, nil
	normalizeCommon(r, L["Reminder"])
	r.text = type(r.text) == "string" and r.text or ""
	r.icon = type(r.icon) == "string" and r.icon or ""
	r.delay = tonumber(r.delay) or 0
	r.sound = r.sound or "NONE"
	r.repeatSound = math.max(0, tonumber(r.repeatSound) or 0)
	r.warnAt = normalizeWarnings(r.warnAt)
	r.warnSound = type(r.warnSound) == "string" and r.warnSound or "RAID_WARNING"
	r.alert = r.alert and true or false
	r.trigger = r.trigger == "event" and "event" or "state"
	r.events = type(r.events) == "table" and r.events or {}
	r.duration = math.max(1, tonumber(r.duration) or DEFAULT_EVENT_SECONDS)
	r.progress = ns.Progress.MODES[r.progress] and r.progress or "auto"
	r.progressMax = math.max(0, tonumber(r.progressMax) or 0)
	Actions:Normalize(r)
	return r
end

function Core:NormalizeGroup(g)
	g.kind = "group"
	normalizeCommon(g, L["Group"])
	g.layout = g.layout == "static" and "static" or "dynamic"
	g.icon = type(g.icon) == "string" and g.icon or ""
	g.children = type(g.children) == "table" and g.children or {}
	g.grow = GROW[g.grow] and g.grow or "DOWN"
	g.spacing = math.max(0, tonumber(g.spacing) or 6)
	g.sort = SORT[g.sort] and g.sort or "order"
	g.wrap = math.max(0, math.floor(tonumber(g.wrap) or 0))
	g.align = ALIGN[g.align] and g.align or "CENTER"
	return g
end

function Core:NormalizeNode(node)
	if node.kind == "group" then return self:NormalizeGroup(node) end
	return self:NormalizeReminder(node)
end

-- Enabled, not switched off for this character and loaded here, for the node and all of its groups.
function Core:IsEnabledHere(node)
	while node do
		if not self:IsOwnEnabledHere(node) then return false end
		node = Tree:ParentNode(node.id)
	end
	return true
end

function Core:IsOwnEnabledHere(node)
	return node.enabled and not (node.disabledFor and node.disabledFor[Compat.CharKey()])
		and ns.Load.Matches(node.load) or false
end

-- Turns the single 1.0 position in db.display into the first 1.1 anchor.
local OLD_ANCHOR_KEYS = { "point", "relPoint", "x", "y", "scale", "iconSize", "fontSize", "grow", "showText" }
local function migrateDisplayToAnchor(db)
	db.anchors = type(db.anchors) == "table" and db.anchors or {}
	if #db.anchors == 0 then
		local a = { id = 1, name = L["Main"] }
		for _, key in ipairs(OLD_ANCHOR_KEYS) do a[key] = db.display[key] end
		db.anchors[1] = a
	end
	for _, key in ipairs(OLD_ANCHOR_KEYS) do db.display[key] = nil end
end

-- Where the reminders of a 1.1 anchor started, relative to the screen center in the anchor's scale.
local function anchorOrigin(a)
	local scale = tonumber(a.scale) or 1
	local w, h = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
	local rx, ry = Layout.PointOffset(a.relPoint or "CENTER", w, h)
	local px, py = Layout.PointOffset(a.point or "CENTER", OLD_ANCHOR_W, OLD_ANCHOR_H)
	local cx = rx / scale + (tonumber(a.x) or 0) - px
	local cy = ry / scale + (tonumber(a.y) or 180) - py
	local edge = OLD_ANCHOR_H / 2 + OLD_ANCHOR_GAP
	if a.grow == "UP" then return cx, cy + edge end
	return cx, cy - edge
end

-- Converts the 1.1 reminder list and anchors into a tree, with each anchor as a dynamic group.
local function migrateToTree(db)
	migrateDisplayToAnchor(db)
	db.nodes, db.root = {}, {}
	for _, r in ipairs(db.reminders) do
		if type(r) == "table" and type(r.id) == "number" and r.id >= db.nextID then db.nextID = r.id + 1 end
	end
	local groups, first = {}, nil
	for _, a in ipairs(db.anchors) do
		local x, y = anchorOrigin(a)
		local visual = {}
		if a.iconSize ~= nil then visual.iconSize = a.iconSize end
		if a.fontSize ~= nil then visual.fontSize = a.fontSize end
		if a.showText ~= nil then visual.showText = a.showText end
		local g = Core:NormalizeGroup({
			name = type(a.name) == "string" and a.name or L["Main"], layout = "dynamic",
			grow = a.grow == "UP" and "UP" or "DOWN", scale = a.scale, visual = visual,
			x = math.floor(x + 0.5), y = math.floor(y + 0.5),
		})
		db.nodes[g.id] = g
		db.root[#db.root + 1] = g.id
		groups[tonumber(a.id) or 1] = g
		first = first or g
	end
	for _, r in ipairs(db.reminders) do
		if type(r) == "table" then
			local g = groups[tonumber(r.anchor) or 1] or first
			Core:NormalizeReminder(r)
			db.nodes[r.id] = r
			table.insert(g.children, r.id)
		end
	end
	db.reminders, db.anchors, db.nextAnchorID = nil, nil, nil
	db.seeded = true
end

function Core:InitDB()
	local db = type(RemindMeWhenDB) == "table" and RemindMeWhenDB or {}
	RemindMeWhenDB = db
	ns.db = db
	db.display = type(db.display) == "table" and db.display or {}
	for key, value in pairs(DISPLAY_DEFAULTS) do
		if db.display[key] == nil then db.display[key] = value end
	end
	db.display.visual = sanitizeVisual(db.display.visual)
	db.learned = type(db.learned) == "table" and db.learned or {}
	db.snoozes = type(db.snoozes) == "table" and db.snoozes or {}
	db.collapsed = type(db.collapsed) == "table" and db.collapsed or {}
	db.nextID = tonumber(db.nextID) or 1
	if type(db.reminders) == "table" and type(db.nodes) ~= "table" then migrateToTree(db) end
	db.nodes = type(db.nodes) == "table" and db.nodes or {}
	db.root = type(db.root) == "table" and db.root or {}
	db.reminders, db.anchors = nil, nil
	for id, node in pairs(db.nodes) do
		if type(node) ~= "table" or type(id) ~= "number" then
			db.nodes[id] = nil
		else
			node.id = id
			if id >= db.nextID then db.nextID = id + 1 end
		end
	end
	for _, node in pairs(db.nodes) do self:NormalizeNode(node) end
	Tree:Reindex()
	if not db.seeded then
		db.seeded = true
		local main = self:AddGroup("dynamic", nil, nil, L["Main"])
		main.y = 160
		for _, preset in ipairs(ns.Presets.list) do
			if preset.default then self:AddReminder(ns.Presets:Build(preset), main.id) end
		end
	end
	ns.Versions:EnsureUIDs()
	ns.Versions:Settle()
end

function Core:ConfigChanged()
	Display:InvalidateIcons()
	self:RequestUpdate()
end

-- Adds a node under parentID (top level when nil or not allowed there).
function Core:AddNode(node, parentID, index)
	node.id = nil
	self:NormalizeNode(node)
	if not Tree:CanPlace(node, parentID) then parentID, index = Tree.ROOT, nil end
	if (parentID or Tree.ROOT) == Tree.ROOT and node.x == 0 and node.y == 0 then node.y = NEW_ROOT_Y end
	Tree:Insert(node, parentID, index)
	self:ConfigChanged()
	return node
end

function Core:AddReminder(r, parentID, index)
	r.kind = "reminder"
	return self:AddNode(r, parentID, index)
end

function Core:AddGroup(layout, parentID, index, name)
	return self:AddNode({ kind = "group", layout = layout, name = name or L["New group"] }, parentID, index)
end

-- Adds a detached subtree (from Tree:Snapshot or an import) and returns its top node.
function Core:AddSnapshot(snapshot, parentID, index)
	if not Tree:CanPlace(snapshot, parentID) then parentID, index = Tree.ROOT, nil end
	local top = Tree:Restore(snapshot, parentID, index, function() return self:NextID() end,
		function(node) self:NormalizeNode(node) end)
	ns.Versions:EnsureUIDs()
	self:ConfigChanged()
	return top
end

function Core:DeleteNode(id, keepChildren)
	for _, removed in ipairs(Tree:Remove(id, keepChildren)) do
		self.state[removed] = nil
		ns.db.snoozes[removed] = nil
		ns.db.collapsed[removed] = nil
	end
	self:ConfigChanged()
end

function Core:DuplicateNode(id)
	local node = Tree:Get(id)
	if not node then return nil end
	local snapshot = ns.Versions.StripUIDs(Tree:Snapshot(id))
	snapshot.name = (node.name or "") .. L[" (copy)"]
	local index = Tree:IndexOf(id)
	return self:AddSnapshot(snapshot, Tree:Parent(id), index and index + 1)
end

function Core:MoveNode(id, parentID, index)
	local moved = Tree:Move(id, parentID, index)
	if moved then self:ConfigChanged() end
	return moved
end

-- Moves a node up (-1) or down (1) among its siblings.
function Core:Nudge(id, delta)
	local index, list = Tree:IndexOf(id)
	local target = index and index + delta
	if not target or not list[target] then return false end
	list[index], list[target] = list[target], list[index]
	self:ConfigChanged()
	return true
end

function Core:SetLayout(group, layout)
	group.layout = layout
	self:ConfigChanged()
end

-- Where a new node goes, given the selected node: into a selected group, else right after it,
-- else right after the nearest group above it that allows it.
function Core:InsertTarget(selectedID, node)
	local selected = Tree:Get(selectedID)
	if not selected then return Tree.ROOT, nil end
	if Tree:IsGroup(selected) and Tree:CanPlace(node, selected.id) then return selected.id, nil end
	local id = selected.id
	while id and id ~= Tree.ROOT do
		local parentID = Tree:Parent(id)
		if parentID == nil then break end
		if Tree:CanPlace(node, parentID) then
			local index = Tree:IndexOf(id)
			return parentID, index and index + 1
		end
		id = parentID
	end
	return Tree.ROOT, nil
end

function Core:ResetPositions()
	for i, id in ipairs(ns.db.root) do
		local node = Tree:Get(id)
		node.x, node.y = 0, 160 - (i - 1) * 60
	end
	self:ConfigChanged()
end

function Core:State(node)
	local st = self.state[node.id]
	if not st then
		st = {}
		self.state[node.id] = st
	end
	return st
end

-- how: "clear" (until the conditions clear or the event window ends), seconds, "zone" or "session".
function Core:Snooze(r, how)
	local st = self:State(r)
	if how == "zone" then
		st.snoozeZone = true
	elseif how == "session" then
		st.snoozeSession = true
	elseif type(how) == "number" then
		ns.db.snoozes[r.id] = time() + how
	else
		st.snoozed = true
	end
	st.forcedUntil = nil
	self:RequestUpdate()
end

function Core:ClearSnoozes()
	wipe(ns.db.snoozes)
	for _, st in pairs(self.state) do st.snoozed, st.snoozeZone, st.snoozeSession = nil, nil, nil end
	self:RequestUpdate()
end

function Core:IsSnoozed(r, st)
	if st.snoozed or st.snoozeZone or st.snoozeSession then return true end
	local untilTime = ns.db.snoozes[r.id]
	if not untilTime then return false end
	if untilTime > time() then return true end
	ns.db.snoozes[r.id] = nil
	return false
end

-- Shows a reminder, every reminder in a group, or (nil) every enabled reminder for a few seconds.
function Core:Test(node)
	local untilTime = GetTime() + TEST_SECONDS
	local list = node and Tree:Reminders(node.id) or Tree:Reminders()
	for _, r in ipairs(list) do
		if node or self:IsEnabledHere(r) then self:State(r).forcedUntil = untilTime end
	end
	self:RequestUpdate()
	C_Timer.After(TEST_SECONDS + 0.1, function() Core:RequestUpdate() end)
end

function Core:FireTriggers(event)
	local triggers = Data.triggersByEvent[event]
	if not triggers then return end
	local now = GetTime()
	for _, trigger in ipairs(triggers) do
		if not trigger.check or trigger.check() then
			for _, r in ipairs(Tree:Reminders()) do
				if r.trigger == "event" and r.events[trigger.key] and self:IsEnabledHere(r) then
					local st = self:State(r)
					st.triggeredUntil = now + r.duration
					st.snoozed = nil
				end
			end
		end
	end
end

-- Own values first, then the ones inherited from groups.
local function mergeVars(own, inherited)
	local out = {}
	for key, value in pairs(inherited or {}) do out[key] = value end
	for key, value in pairs(own or {}) do out[key] = value end
	return out
end

-- Evaluates a node's own conditions, keeping the last known result while the answer is unknown.
local function evaluateConditions(node, st, emptyResult)
	local result, vars
	if #node.conditions == 0 then
		result, vars = emptyResult, {}
	else
		result, vars = Conditions:EvaluateReminder(node)
	end
	st.unknown = false
	if result == nil then
		result = st.raw or false
		st.unknown = true
		vars = mergeVars(vars, st.ownVars)
	end
	st.raw, st.ownVars = result, vars or {}
	return result, st.ownVars
end

-- groupsActive: whether every group above is active. Conditions are evaluated either way so that
-- aura state is known before it turns secret in combat.
-- gated: whether a group above has conditions, in which case a reminder without its own follows it.
function Core:EvaluateReminder(r, now, groupsActive, inherited, gated)
	local st = self:State(r)
	local result = false
	if self:IsOwnEnabledHere(r) then
		result = evaluateConditions(r, st, r.trigger == "event" or gated or false)
	else
		st.raw, st.ownVars, st.unknown = false, {}, false
	end
	st.vars = mergeVars(st.ownVars, inherited)
	ns.Progress.Track(st, st.vars, now)
	if r.trigger == "event" then
		local live = st.triggeredUntil and st.triggeredUntil > now
		if not live then st.triggeredUntil, st.snoozed = nil, nil end
		st.active = groupsActive and live and result and not self:IsSnoozed(r, st) or false
	else
		if result and groupsActive then
			st.since = st.since or now
		else
			st.since = nil
			if not result then st.snoozed = nil end
		end
		st.active = groupsActive and result and not self:IsSnoozed(r, st) and (now - st.since) >= r.delay or false
	end
	local forced = st.forcedUntil and st.forcedUntil > now
	if not forced then st.forcedUntil = nil end
	return st, forced
end

function Core:EvaluateNodes(list, groupsActive, inherited, now, active, gated)
	for _, id in ipairs(list) do
		local node = Tree:Get(id)
		if Tree:IsGroup(node) then
			local st = self:State(node)
			local result, vars = false, {}
			if self:IsOwnEnabledHere(node) then
				result, vars = evaluateConditions(node, st, true)
			else
				st.raw, st.ownVars, st.unknown = false, {}, false
			end
			st.active = groupsActive and result or false
			self:EvaluateNodes(node.children, st.active, mergeVars(vars, inherited), now, active,
				gated or #node.conditions > 0)
		elseif node then
			local st, forced = self:EvaluateReminder(node, now, groupsActive, inherited, gated)
			if forced or (st.active and not active.suppressed) then active[id] = true end
		end
	end
end

function Core:Evaluate()
	Tracker:BeginPass()
	local now = GetTime()
	local d = ns.db.display
	local active = {}
	active.suppressed = (d.hideWhenDead and Compat.Plain(UnitIsDeadOrGhost("player")))
		or (d.hideOnTaxi and Compat.Plain(UnitOnTaxi("player"))) or nil
	self:EvaluateNodes(ns.db.root, true, {}, now, active)
	active.suppressed = nil
	local wasShown = Display.shown
	Display:Update(active)
	for id in pairs(active) do
		local r, st = Tree:Get(id), self.state[id]
		if wasShown[id] and r.repeatSound > 0 and st.lastSound and now - st.lastSound >= r.repeatSound then
			Display:PlaySound(r)
		end
		self:CheckWarnings(r, st, now, wasShown[id])
	end
	Options:OnEvaluated()
end

-- Warns once each time the time left of a shown reminder drops past one of its warnAt values.
function Core:CheckWarnings(r, st, now, wasShown)
	local expires = st.vars and st.vars.expires
	if not expires or #r.warnAt == 0 then
		st.warnLeft = nil
		return
	end
	local left = expires - now
	if wasShown and st.warnLeft then
		for _, seconds in ipairs(r.warnAt) do
			if st.warnLeft > seconds and left <= seconds then
				Display:Warn(r)
				break
			end
		end
	end
	st.warnLeft = left
end

local driver = CreateFrame("Frame")
local sinceLast, dirty = 0, true

function Core:RequestUpdate()
	dirty = true
end

local function onUpdate(_, elapsed)
	sinceLast = sinceLast + elapsed
	if (dirty and sinceLast >= MIN_INTERVAL) or sinceLast >= MAX_INTERVAL then
		sinceLast, dirty = 0, false
		Core:Evaluate()
	end
end

local WINDOW_EVENTS = {
	MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
	MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
}

function Core:OnEvent(event, ...)
	local window = WINDOW_EVENTS[event]
	if window then Tracker:SetWindow(window[1], window[2]) end
	if event == "UNIT_AURA" then
		local unit, info = ...
		if Compat.IsSecret(unit) then return end
		if unit == "player" or unit == "pet" or unit == "target" then Tracker:OnUnitAura(unit, info) end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellID = ...
		if Compat.IsSecret(unit) or unit ~= "player" then return end
		Tracker:OnPlayerCast(spellID)
	elseif event == "UNIT_HEALTH" then
		local unit = ...
		if not Compat.IsSecret(unit) and unit == "pet" then Tracker:OnPetHealth() end
	elseif event == "ENCOUNTER_START" then
		local id, name = ...
		if not Compat.IsSecret(id, name) then Tracker:SetEncounter(tonumber(id), name) end
	elseif event == "ENCOUNTER_END" then
		Tracker:SetEncounter(nil)
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		Tracker:InvalidateWeapon((...))
		Display:InvalidateIcons()
	elseif event == "PLAYER_TARGET_CHANGED" then
		Tracker:ResetUnit("target")
	elseif event == "UNIT_PET" then
		Tracker:ResetUnit("pet")
		Tracker:OnPetGone()
		Tracker:UpdatePet()
	elseif event == "SPELLS_CHANGED" then
		Tracker:ResetResolved()
		ns.Spells:ResetBook()
		Display:InvalidateIcons()
	elseif event == "SPELL_DATA_LOAD_RESULT" or event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
		local id = ...
		if Compat.IsSecret(id) then return end
		local resolver = event == "SPELL_DATA_LOAD_RESULT" and ns.Spells or ns.Items
		if not resolver:OnLoaded(id) then return end
		Tracker:ResetResolved()
		Display:InvalidateIcons()
		Options:OnDataLoaded()
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		for _, st in pairs(self.state) do st.snoozeZone = nil end
	elseif event == "PLAYER_REGEN_ENABLED" then
		Actions:OnCombatEnded()
	elseif event == "PLAYER_ENTERING_WORLD" or event == "COMPANION_LEARNED" or event == "NEW_MOUNT_ADDED" then
		if event == "PLAYER_ENTERING_WORLD" then Tracker:SetEncounter(nil) end
		Conditions:InvalidateMounts()
		Display:InvalidateIcons()
	end
	self:FireTriggers(event)
	self:RequestUpdate()
end

function Core:OnLogin()
	Display:Create()
	Actions:Create()
	Options:RegisterSettings()
	for _, event in ipairs(EVENTS) do pcall(driver.RegisterEvent, driver, event) end
	for _, event in ipairs(PLAYER_UNIT_EVENTS) do pcall(driver.RegisterUnitEvent, driver, event, "player") end
	pcall(driver.RegisterUnitEvent, driver, "UNIT_HEALTH", "pet", "target")
	driver:SetScript("OnUpdate", onUpdate)
	if not ns.db.welcomed then
		ns.db.welcomed = true
		self:Print(L["Loaded. Type /rmw to set up your reminders."])
	end
end

local function describe(value)
	if value == nil then return "|cffffd100" .. L["unknown"] .. "|r" end
	return value and ("|cff33ff33" .. L["true"] .. "|r") or ("|cffff3333" .. L["false"] .. "|r")
end

function Core:Debug()
	local version, build, _, interface = GetBuildInfo()
	self:Print(string.format(L["client %s (%s), interface %s"], tostring(version), tostring(build), tostring(interface)))
	self:Print(L["in combat: "] .. describe(Compat.InCombat()) .. L[", auras secret: "] .. describe(Compat.AurasSecret()))
	self:Print(L["mount usable here: "] .. describe(Conditions:Evaluate({ type = "mountUsable" })))
	local instanceName, instanceID = ns.Instances.Current()
	self:Print(string.format(L["map ID %s, instance %s (ID %s)"], tostring(Compat.MapID()), tostring(instanceName), tostring(instanceID)))
	local trees = {}
	for _, tab in ipairs(Compat.TalentTabs()) do trees[#trees + 1] = string.format("%s %d", tab.name, tab.points) end
	self:Print(L["talent points: "] .. (#trees > 0 and table.concat(trees, ", ") or L["unknown"]))
	Tracker:BeginPass()
	for _, slot in ipairs({ 16, 17 }) do
		local enchants = Tracker:GetWeaponEnchants(slot)
		local parts = {}
		for _, enchant in ipairs(enchants or {}) do
			local left = enchant.expires and (" (" .. Compat.FormatTime(enchant.expires - GetTime()) .. ")") or ""
			parts[#parts + 1] = tostring(enchant.id) .. left
		end
		local label = slot == 16 and L["main hand"] or L["off hand"]
		local text = enchants == nil and L["unknown"] or (#parts > 0 and table.concat(parts, ", ") or L["none"])
		self:Print(string.format(L["%s enchant IDs: %s"], label, text))
	end
	Tree:Walk(function(node, level)
		local st = self.state[node.id] or {}
		local status
		if not self:IsEnabledHere(node) then
			status = L["disabled"]
		elseif Tree:IsGroup(node) then
			status = st.active and L["active"] or L["inactive"]
		else
			status = st.active and L["showing"] or L["hidden"]
		end
		local unknown = st.unknown and L[" (using last known state)"] or ""
		self:Print(string.format("%s%s: %s%s", string.rep("  ", level), node.name, status, unknown))
	end)
end

function Core:LookupSpell(text)
	if text == "" then
		self:Print(L["Usage: /rmw spell <name or ID>"])
		return
	end
	local results = ns.Spells:Check(text)
	if #results == 1 and results[1].status == ns.Spells.UNVERIFIED then
		local matches = ns.Spells:Search(text, 10)
		if #matches > 0 then
			self:Print(string.format(L["Spellbook spells containing \"%s\":"], text))
			for _, spell in ipairs(matches) do self:Print("  " .. ns.Spells:Format(spell)) end
			return
		end
	end
	for _, line in ipairs(ns.Spells:Describe(results)) do self:Print(line) end
end

local function handleSlash(message)
	message = message or ""
	local command = message:lower():match("^%s*(%S*)")
	local rest = message:match("^%s*%S+%s+(.-)%s*$") or ""
	if command == "" or command == "config" or command == "options" then
		Options:Toggle()
	elseif command == "lock" or command == "unlock" then
		ns.db.display.locked = command == "lock"
		Display:ApplySettings()
		Core:Print(command == "lock" and L["Display locked."] or L["Display unlocked. Drag reminders and groups to move them."])
	elseif command == "test" then
		Core:Test()
	elseif command == "reset" then
		Core:ResetPositions()
		Core:Print(L["Display positions reset."])
	elseif command == "unsnooze" then
		Core:ClearSnoozes()
		Core:Print(L["All snoozes cleared."])
	elseif command == "debug" then
		Core:Debug()
	elseif command == "spell" then
		Core:LookupSpell(rest)
	elseif command == "import" then
		Options:ShowImport()
	elseif command == "export" then
		Options:ShowExport(ns.db.root)
	else
		Core:Print(L["/rmw - open the editor"])
		Core:Print(L["/rmw lock | unlock - lock or move the display"])
		Core:Print(L["/rmw test - show all enabled reminders for a few seconds"])
		Core:Print(L["/rmw reset - move all top-level reminders and groups back to the middle of the screen"])
		Core:Print(L["/rmw unsnooze - show all snoozed reminders again"])
		Core:Print(L["/rmw import | export - share reminders as text"])
		Core:Print(L["/rmw debug - print map, instance and weapon enchant IDs and talent points"])
		Core:Print(L["/rmw spell <name or ID> - show which spell a name or ID resolves to"])
	end
end

SLASH_REMINDMEWHEN1 = "/rmw"
SLASH_REMINDMEWHEN2 = "/remindmewhen"
SlashCmdList.REMINDMEWHEN = handleSlash

function RemindMeWhen_OnAddonCompartmentClick()
	Options:Toggle()
end

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_LOGOUT")
driver:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == addonName then Core:InitDB() end
		return
	end
	if event == "PLAYER_LOGOUT" then
		if ns.db then ns.Versions:Update() end
		return
	end
	if event == "PLAYER_LOGIN" then
		Core:OnLogin()
		return
	end
	Core:OnEvent(event, ...)
end)
