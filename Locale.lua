local _, ns = ...

-- Keys are the English strings. Translations go below, one block per locale, for example:
-- if GetLocale() == "deDE" then L["Mount up!"] = "Aufsitzen!" end
-- Missing keys fall back to English.
local L = setmetatable({}, {
	__index = function(t, key)
		t[key] = key
		return key
	end,
})
ns.L = L
