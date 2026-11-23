local _, ns = ...

-- Pure geometry for the display: no frames, so it can be checked outside the game.
-- Offsets use WoW conventions: x grows right, y grows up.
local Layout = {}
ns.Layout = Layout

Layout.TEXT_GAP = 8
Layout.TEXT_GAP_VERTICAL = 4
Layout.POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
Layout.IS_POINT = {}
for _, point in ipairs(Layout.POINTS) do Layout.IS_POINT[point] = true end

-- Offset of a named point from the center of a w x h box.
function Layout.PointOffset(point, w, h)
	local x, y = 0, 0
	if point:find("LEFT") then x = -w / 2 elseif point:find("RIGHT") then x = w / 2 end
	if point:find("TOP") then y = h / 2 elseif point:find("BOTTOM") then y = -h / 2 end
	return x, y
end

-- Size of a reminder (icon plus text) and where the icon center sits relative to the box center.
function Layout.Box(size, textW, textH, showText, textPos)
	if not showText or textW <= 0 or textPos == "CENTER" then return size, size, 0, 0 end
	if textPos == "LEFT" or textPos == "RIGHT" then
		local w, h = size + Layout.TEXT_GAP + textW, math.max(size, textH)
		local ix = (w - size) / 2
		return w, h, textPos == "RIGHT" and -ix or ix, 0
	end
	local w, h = math.max(size, textW), size + Layout.TEXT_GAP_VERTICAL + textH
	local iy = (h - size) / 2
	return w, h, 0, textPos == "TOP" and -iy or iy
end

local VERTICAL = { DOWN = true, UP = true, VCENTER = true }

local function chunk(list, size)
	if not size or size <= 0 then return { list } end
	local lines, line = {}, {}
	for _, item in ipairs(list) do
		line[#line + 1] = item
		if #line >= size then
			lines[#lines + 1] = line
			line = {}
		end
	end
	if #line > 0 then lines[#lines + 1] = line end
	return lines
end

Layout.COLUMN_ALIGN = { LEFT = true, CENTER = true, RIGHT = true }
Layout.ROW_ALIGN = { TOP = true, CENTER = true, BOTTOM = true }

function Layout.IsVertical(grow)
	return VERTICAL[grow] or false
end

-- Arranges boxes ({ w, h }) for a dynamic group.
-- opts: grow (DOWN, UP, LEFT, RIGHT, HCENTER, VCENTER), spacing, wrap (items per line, 0 = none),
-- align (LEFT, CENTER or RIGHT for columns, TOP, CENTER or BOTTOM for rows).
-- Returns { anchor = point name, width, height, centers = { { x, y } } } with centers relative to the anchor.
function Layout.Dynamic(boxes, opts)
	local grow, spacing, wrap = opts.grow or "DOWN", opts.spacing or 0, opts.wrap or 0
	local vertical = VERTICAL[grow] or false
	local valid = vertical and Layout.COLUMN_ALIGN or Layout.ROW_ALIGN
	local align = valid[opts.align] and opts.align or "CENTER"
	local items = {}
	for i, box in ipairs(boxes) do items[i] = { index = i, w = box.w, h = box.h } end
	local lines = chunk(items, wrap)
	local longest, cross = 0, 0
	for _, line in ipairs(lines) do
		local length, thickness = 0, 0
		for i, item in ipairs(line) do
			length = length + (vertical and item.h or item.w) + (i > 1 and spacing or 0)
			thickness = math.max(thickness, vertical and item.w or item.h)
		end
		line.length, line.thickness = length, thickness
		longest = math.max(longest, length)
	end
	for i, line in ipairs(lines) do cross = cross + line.thickness + (i > 1 and spacing or 0) end
	local width, height = vertical and cross or longest, vertical and longest or cross

	-- Box coordinates first: origin top-left, x right, y down.
	local centers, lineStart = {}, 0
	for _, line in ipairs(lines) do
		local cursor = 0
		if grow == "VCENTER" or grow == "HCENTER" then cursor = (longest - line.length) / 2 end
		for _, item in ipairs(line) do
			local along = vertical and item.h or item.w
			local mid = cursor + along / 2
			cursor = cursor + along + spacing
			local x, y
			if vertical then
				y = grow == "UP" and (longest - mid) or mid
				if align == "LEFT" then
					x = lineStart + item.w / 2
				elseif align == "RIGHT" then
					x = lineStart + line.thickness - item.w / 2
				else
					x = lineStart + line.thickness / 2
				end
			else
				x = grow == "LEFT" and (longest - mid) or mid
				if align == "TOP" then
					y = lineStart + item.h / 2
				elseif align == "BOTTOM" then
					y = lineStart + line.thickness - item.h / 2
				else
					y = lineStart + line.thickness / 2
				end
			end
			centers[item.index] = { x, y }
		end
		lineStart = lineStart + line.thickness + spacing
	end

	-- The anchor is where the first item starts, so the group grows away from it.
	local vpart, hpart
	if vertical then
		vpart = grow == "DOWN" and "TOP" or grow == "UP" and "BOTTOM" or ""
		hpart = (wrap > 0 or align == "LEFT") and "LEFT" or align == "RIGHT" and "RIGHT" or ""
	else
		hpart = grow == "RIGHT" and "LEFT" or grow == "LEFT" and "RIGHT" or ""
		vpart = (wrap > 0 or align == "TOP") and "TOP" or align == "BOTTOM" and "BOTTOM" or ""
	end
	local anchor = (vpart .. hpart) ~= "" and (vpart .. hpart) or "CENTER"
	local ax, ay = Layout.PointOffset(anchor, width, height)
	ax, ay = ax + width / 2, height / 2 - ay
	for _, c in pairs(centers) do
		c[1], c[2] = c[1] - ax, ay - c[2]
	end
	return { anchor = anchor, width = width, height = height, centers = centers }
end

-- How far to move a dragged box so its nearest edge or center lands on a line within threshold.
-- edges and lines are coordinates on one axis. Returns the shift and the line, or 0 and nil.
function Layout.Snap(edges, lines, threshold)
	local best, line
	for _, edge in ipairs(edges) do
		for _, candidate in ipairs(lines) do
			local shift = candidate - edge
			if math.abs(shift) <= threshold and (not best or math.abs(shift) < math.abs(best)) then
				best, line = shift, candidate
			end
		end
	end
	return best or 0, line
end

-- How far to move a dragged box so its nearest edge or center lands on a grid line at
-- origin + n * step. Returns the shift and the line.
function Layout.SnapGrid(edges, origin, step)
	local best, line
	for _, edge in ipairs(edges) do
		local candidate = origin + math.floor((edge - origin) / step + 0.5) * step
		local shift = candidate - edge
		if not best or math.abs(shift) < math.abs(best) then best, line = shift, candidate end
	end
	return best or 0, line
end

function Layout.Sort(entries, mode)
	if mode == "name" then
		table.sort(entries, function(a, b)
			if a.name == b.name then return a.order < b.order end
			return a.name < b.name
		end)
	elseif mode == "timeLeft" then
		table.sort(entries, function(a, b)
			local ea, eb = a.expires, b.expires
			if ea and eb and ea ~= eb then return ea < eb end
			if (ea ~= nil) ~= (eb ~= nil) then return ea ~= nil end
			return a.order < b.order
		end)
	else
		table.sort(entries, function(a, b) return a.order < b.order end)
	end
	return entries
end
