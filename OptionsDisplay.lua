local _, ns = ...
local W, L = ns.Widgets, ns.L
local Options = ns.Options

StaticPopupDialogs.REMINDMEWHEN_RESET_POSITIONS = {
	text = L["Move every top-level reminder and group back to the middle of the screen?"],
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function()
		ns.Core:ResetPositions()
		Options:Refresh()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function Options:CreateDisplayPage()
	local panel = W.Panel(self.frame)
	panel:SetPoint("TOPLEFT", self.LIST_W + 20, -40)
	panel:SetPoint("BOTTOMRIGHT", -12, 12)
	panel:Hide()
	self.displayPage = panel

	local header = W.Label(panel, L["Display settings"], "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", 14, -14)

	self.displayChecks = {}
	local checks = {
		{ "locked", L["Lock positions (uncheck to drag reminders and groups at any time)"] },
		{ "editWhileOptions", L["Show everything and allow dragging while this window is open"] },
		{ "clickToDismiss", L["Right-click a reminder to snooze it"] },
		{ "hideWhenDead", L["Hide all reminders while dead"] },
		{ "hideOnTaxi", L["Hide all reminders on flight paths"] },
	}
	local y = -44
	for _, info in ipairs(checks) do
		local key = info[1]
		local check = W.Check(panel, info[2], function(value)
			ns.db.display[key] = value
			ns.Display:ApplySettings()
		end)
		check:SetPoint("TOPLEFT", 14, y)
		self.displayChecks[key] = check
		y = y - 28
	end

	y = y - 10
	local lookHeader = W.Label(panel, L["Default look"], "GameFontNormal")
	lookHeader:SetPoint("TOPLEFT", 14, y)
	local lookHelp = W.Label(panel, L["Used by every group and reminder that does not set its own."], "GameFontDisableSmall")
	lookHelp:SetPoint("LEFT", lookHeader, "RIGHT", 10, 0)
	self.globalVisuals = self:VisualControls(panel, 14, y - 26, true)

	y = y - 26 - Options.VISUAL_ROW_COUNT * 28 - 14
	local reset = W.Button(panel, L["Reset positions"], 140, function()
		self:ClearEditFocus()
		StaticPopup_Show("REMINDMEWHEN_RESET_POSITIONS")
	end)
	reset:SetPoint("TOPLEFT", 14, y)
	W.Tooltip(reset, L["Reset positions"], L["Moves every top-level reminder and group back to the middle of the screen (also /rmw reset)."])

	local testAll = W.Button(panel, L["Test all reminders"], 150, function() ns.Core:Test() end)
	testAll:SetPoint("LEFT", reset, "RIGHT", 8, 0)
	local clearSnoozes = W.Button(panel, L["Clear snoozes"], 130, function()
		ns.Core:ClearSnoozes()
		ns.Core:Print(L["All snoozes cleared."])
	end)
	clearSnoozes:SetPoint("LEFT", testAll, "RIGHT", 8, 0)
	W.Tooltip(clearSnoozes, L["Clear snoozes"], L["Shows every snoozed reminder again (also /rmw unsnooze)."])
	local back = W.Button(panel, L["Back to reminders"], 150, function() self:ShowPage("node") end)
	back:SetPoint("LEFT", clearSnoozes, "RIGHT", 8, 0)
end

function Options:RefreshDisplayPage()
	if not self.displayPage then return end
	local d = ns.db.display
	for key, check in pairs(self.displayChecks) do check:SetChecked(d[key]) end
	self.globalVisuals:Refresh()
end
