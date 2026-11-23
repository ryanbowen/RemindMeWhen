local _, ns = ...
local W, L = ns.Widgets, ns.L
local Options = ns.Options

local REVIEW_ROW_H = 22
local INDENT = 16
local PART_COLUMN_W = 190

function Options:CreateIODialog()
	if self.io then return self.io end
	local dialog = W.Panel(UIParent, "RemindMeWhenIO")
	dialog:SetSize(600, 400)
	dialog:SetPoint("CENTER")
	dialog:SetFrameStrata("DIALOG")
	dialog:SetToplevel(true)
	dialog:SetMovable(true)
	dialog:EnableMouse(true)
	dialog:SetClampedToScreen(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	dialog:Hide()
	tinsert(UISpecialFrames, "RemindMeWhenIO")

	dialog.title = W.Label(dialog, "", "GameFontNormalLarge")
	dialog.title:SetPoint("TOPLEFT", 14, -12)
	local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	dialog.help = W.Label(dialog, "", "GameFontDisableSmall")
	dialog.help:SetPoint("TOPLEFT", 14, -36)
	dialog.help:SetPoint("RIGHT", dialog, "RIGHT", -14, 0)
	dialog.help:SetWordWrap(true)

	dialog.box = W.MultiLineBox(dialog, 572, 270)
	dialog.box:SetPoint("TOPLEFT", 14, -60)
	dialog.review = self:CreateImportReview(dialog)

	dialog.status = W.Label(dialog, "", "GameFontHighlightSmall")
	dialog.status:SetPoint("BOTTOMLEFT", 14, 46)
	dialog.status:SetPoint("RIGHT", dialog, "RIGHT", -14, 0)
	dialog.status:SetWordWrap(true)

	dialog.primary = W.Button(dialog, "", 120, function()
		if dialog.mode == "import" then
			self:DoImport()
		elseif dialog.mode == "review" then
			self:FinishImport(false)
		else
			dialog.box.edit:SetFocus()
			dialog.box.edit:HighlightText()
		end
	end)
	dialog.primary:SetPoint("BOTTOMRIGHT", -140, 12)
	dialog.copy = W.Button(dialog, L["Import as copy"], 120, function() self:FinishImport(true) end)
	dialog.copy:SetPoint("RIGHT", dialog.primary, "LEFT", -6, 0)
	W.Tooltip(dialog.copy, L["Import as copy"], L["Adds everything as new reminders and groups without changing yours. Later imports will not update the copies."])
	dialog.copy:Hide()
	local done = W.Button(dialog, L["Close"], 120, function() dialog:Hide() end)
	done:SetPoint("BOTTOMRIGHT", -14, 12)
	self.io = dialog
	return dialog
end

-- The list of what an import will update, add and leave over, and the parts to keep.
function Options:CreateImportReview(dialog)
	local review = CreateFrame("Frame", nil, dialog)
	review:SetPoint("TOPLEFT", 14, -60)
	review:SetSize(572, 270)
	review:Hide()

	local box = W.Panel(review)
	box:SetPoint("TOPLEFT", 0, 0)
	box:SetSize(572, 160)
	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	review.child = CreateFrame("Frame", nil, scroll)
	review.child:SetSize(530, 10)
	scroll:SetScrollChild(review.child)
	review.rows = {}

	local keepLabel = W.Label(review, L["Keep my:"], "GameFontNormal")
	keepLabel:SetPoint("TOPLEFT", 0, -170)
	local keepHelp = W.Label(review, L["Checked parts of updated reminders and groups stay as you have them."], "GameFontDisableSmall")
	keepHelp:SetPoint("LEFT", keepLabel, "RIGHT", 10, 0)
	review.keepChecks = {}
	for i, part in ipairs(ns.Merge.PARTS) do
		local check = W.Check(review, part.label, function(value) review.keep[part.key] = value or nil end)
		local column, row = (i - 1) % 3, math.floor((i - 1) / 3)
		check:SetPoint("TOPLEFT", column * PART_COLUMN_W, -188 - row * 26)
		review.keepChecks[part.key] = check
	end
	return review
end

local function reviewRow(review, index)
	local row = review.rows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, review.child)
	row:SetSize(530, REVIEW_ROW_H)
	row.remove = W.Check(row, L["Remove"], function(value)
		if row.node then review.remove[row.node.id] = value or nil end
	end)
	row.text = W.Label(row, "", "GameFontHighlightSmall")
	row.text:SetWordWrap(false)
	review.rows[index] = row
	return row
end

local function describe(entry)
	local incoming = entry.incoming
	local name = incoming.kind == "group" and string.format(L["%s (group)"], incoming.name or "") or (incoming.name or "")
	if entry.status == "new" then return "|cff33ff99" .. L["New"] .. "|r  " .. name end
	local mine, theirs = entry.existing.revision or 1, incoming.revision or 1
	local revision
	if entry.status == "newer" then
		revision = string.format(L["revision %d to %d"], mine, theirs)
	elseif entry.status == "same" then
		revision = "|cffffd100" .. string.format(L["same revision (%d)"], mine) .. "|r"
	else
		revision = "|cffff6060" .. string.format(L["older: revision %d to %d"], mine, theirs) .. "|r"
	end
	return "|cffffd100" .. L["Update"] .. "|r  " .. name .. "  |cff888888" .. revision .. "|r"
end

function Options:RefreshImportReview()
	local review, plan = self.io.review, self.importPlan
	local count = 0
	local function addRow(text, depth, node)
		count = count + 1
		local row = reviewRow(review, count)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -(count - 1) * REVIEW_ROW_H)
		row.node = node
		row.remove:SetShown(node ~= nil)
		row.remove:ClearAllPoints()
		row.remove:SetPoint("LEFT", depth * INDENT, 0)
		row.remove:SetChecked(node ~= nil and review.remove[node.id] or false)
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", depth * INDENT + (node and 90 or 4), 0)
		row.text:SetText(text)
		row:Show()
	end
	local function addEntry(entry, depth)
		addRow(describe(entry), depth)
		for _, child in ipairs(entry.children or {}) do addEntry(child, depth + 1) end
	end
	for _, entry in ipairs(plan.entries) do addEntry(entry, 0) end
	for _, node in ipairs(plan.leftovers) do
		local name = ns.Tree:IsGroup(node) and string.format(L["%s (group)"], node.name) or node.name
		addRow(name .. "  |cff888888" .. L["not in the new version"] .. "|r", 0, node)
	end
	for i = count + 1, #review.rows do review.rows[i]:Hide() end
	review.child:SetHeight(math.max(10, count * REVIEW_ROW_H))
	for key, check in pairs(review.keepChecks) do check:SetChecked(review.keep[key] or false) end
end

-- Exports the given node IDs together with everything inside them.
function Options:ShowExport(ids)
	local dialog = self:CreateIODialog()
	self:SetIOMode("export")
	local single = #ids == 1 and ns.Tree:Get(ids[1])
	dialog.title:SetText(single and string.format(L["Export \"%s\""], single.name) or L["Export everything"])
	dialog.help:SetText(L["Press Ctrl+C to copy the selected text, then share it. Others can paste it with Import."])
	dialog.primary:SetText(L["Select all"])
	local reminders = 0
	for _, id in ipairs(ids) do reminders = reminders + #ns.Tree:Reminders(id) end
	dialog.status:SetText(string.format(L["%d reminder(s)"], reminders))
	dialog.box:SetValue(ns.Serialize.Export(ids))
	dialog:Show()
	dialog:Raise()
	dialog.box.edit:SetFocus()
	dialog.box.edit:HighlightText()
end

function Options:SetIOMode(mode)
	local dialog = self.io
	dialog.mode = mode
	dialog.box:SetShown(mode ~= "review")
	dialog.review:SetShown(mode == "review")
	dialog.copy:SetShown(mode == "review")
	if mode ~= "review" then self.importPlan = nil end
end

function Options:ShowImport()
	local dialog = self:CreateIODialog()
	self:SetIOMode("import")
	dialog.title:SetText(L["Import reminders"])
	dialog.help:SetText(L["Paste an export string (Ctrl+V) and click Import. New things are added to the selected group (or next to the selected reminder). If some already exist, you can choose to update them or import copies."])
	dialog.primary:SetText(L["Import"])
	dialog.status:SetText("")
	dialog.box:SetValue("")
	dialog:Show()
	dialog:Raise()
	dialog.box.edit:SetFocus()
end

function Options:DoImport()
	local dialog = self.io
	local list, err = ns.Serialize.Import(dialog.box:GetValue())
	if not list then
		dialog.status:SetText("|cffff6060" .. err .. "|r")
		return
	end
	self.importCount = ns.Serialize.CountReminders(list)
	self.importPlan = ns.Merge.Plan(list)
	if self.importPlan.matches == 0 then
		self:FinishImport(false)
		return
	end
	self:SetIOMode("review")
	local review = dialog.review
	review.remove, review.keep = {}, {}
	for _, part in ipairs(ns.Merge.PARTS) do review.keep[part.key] = part.keepByDefault or nil end
	dialog.title:SetText(L["Update or import a copy?"])
	dialog.help:SetText(L["Some of this is already here. Update changes your existing reminders and groups to match the import. Import as copy adds everything as new."])
	dialog.primary:SetText(L["Update"])
	local plan = self.importPlan
	local status = string.format(L["%d to update, %d not in the new version."], plan.matches, #plan.leftovers)
	if plan.notNewer > 0 then
		status = status .. " |cffff6060" .. L["Some imports are not newer than what you have."] .. "|r"
	end
	dialog.status:SetText(status)
	self:RefreshImportReview()
end

-- Applies the import reviewed (or parsed) in the dialog, as an update or as copies.
function Options:FinishImport(asCopy)
	local dialog, plan = self.io, self.importPlan
	if not plan then return end
	local review = dialog.review
	local options = { asCopy = asCopy }
	if dialog.mode == "review" and not asCopy then options.keep, options.remove = review.keep, review.remove end
	local top, macros = self:ImportNodes(plan, options)
	local updating = not asCopy and plan.matches > 0
	local message = updating and string.format(L["Imported %d reminder(s), updating %d existing."], self.importCount, plan.matches)
		or string.format(L["Imported %d reminder(s)."], self.importCount)
	if macros > 0 then
		message = message .. " " .. string.format(L["%d had a macro click action, which was switched off. Review it under Click action."], macros)
	end
	ns.Core:Print(message)
	self:SetIOMode("import")
	dialog:Hide()
	if self:IsOpen() and top[1] then self:Select(top[1].id) end
	if self:IsOpen() then self:Refresh() end
end

-- New top-level nodes go at the insert position for the current selection (top level when the
-- window is closed), keeping their order.
function Options:ImportNodes(plan, options)
	local shift = {}
	local selected = self:IsOpen() and self.selected or nil
	options.place = function(node)
		local parentID, index = ns.Core:InsertTarget(selected, node)
		if index then
			index = index + (shift[parentID] or 0)
			shift[parentID] = (shift[parentID] or 0) + 1
		end
		return parentID, index
	end
	return ns.Merge.Apply(plan, options)
end
