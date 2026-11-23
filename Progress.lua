local _, ns = ...

-- How full a reminder's bar is, from the values its conditions reported.
local Progress = {}
ns.Progress = Progress

Progress.MODES = { auto = true, time = true, value = true, full = true }

-- Called every evaluation pass, shown or not: the longest time left seen since the aura or
-- enchant appeared stands in for its full duration when the game does not report one
-- (weapon enchants only report time left).
function Progress.Track(st, vars, now)
	if not vars.expires then
		st.longestLeft = nil
		return
	end
	local left = math.max(0, vars.expires - now)
	if not st.longestLeft or left > st.longestLeft then st.longestLeft = left end
end

local function collectMeasures(conditions, found)
	for _, c in ipairs(conditions or {}) do
		if c.conditions then collectMeasures(c.conditions, found) end
		local def = ns.Conditions.types[c.type]
		if def and def.measures then found[def.measures] = true end
	end
end

-- What auto mode measures when no condition reported a value this pass (a missing aura, for example),
-- taken from the condition types of the reminder and its groups so that the bar shows empty.
function Progress.ConditionMode(r)
	local found = {}
	local node = r
	while node do
		collectMeasures(node.conditions, found)
		node = ns.Tree:ParentNode(node.id)
	end
	return found.time and "time" or found.value and "value" or "full"
end

-- vars: expires, duration, count, max from the conditions.
-- Returns the fill from 0 to 1, or nil when there is nothing to measure (an empty bar).
-- For time bars it also returns the expiry and full length so the bar can drain smoothly.
function Progress.Compute(r, vars, st, now)
	local mode = Progress.MODES[r.progress] and r.progress or "auto"
	if mode == "auto" then
		mode = vars.expires and "time" or vars.count ~= nil and "value" or Progress.ConditionMode(r)
	end
	if mode == "full" then return 1 end
	local manual = (tonumber(r.progressMax) or 0) > 0 and r.progressMax or nil
	if mode == "time" then
		if not vars.expires then return nil end
		local left = math.max(0, vars.expires - now)
		local total = manual or (vars.duration and vars.duration > 0 and vars.duration) or nil
		if not total then total = math.max(st.longestLeft or 0, left) end
		if total <= 0 then return 0 end
		return math.min(1, left / total), vars.expires, total
	end
	local count = tonumber(vars.count)
	if count == nil then return nil end
	local maximum = manual or vars.max or 100
	if maximum <= 0 then return 0 end
	return math.max(0, math.min(1, count / maximum))
end
