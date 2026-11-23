local _, ns = ...
local Compat, Resolver, L = ns.Compat, ns.Resolver, ns.L

local Spells = Resolver.New({ noun = L["spell"] })
ns.Spells = Spells

local OK, LOADING, UNVERIFIED, MISSING = Resolver.OK, Resolver.LOADING, Resolver.UNVERIFIED, Resolver.MISSING

function Spells.IsKnown(id)
	if IsPlayerSpell and Compat.Plain(IsPlayerSpell(id)) then return true end
	if IsSpellKnown and Compat.Plain(IsSpellKnown(id)) then return true end
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
		if ok and Compat.Plain(known) then return true end
	end
	return false
end

local function spellExists(id)
	if not (C_Spell and C_Spell.DoesSpellExist) then return nil end
	local ok, exists = pcall(C_Spell.DoesSpellExist, id)
	if not ok or Compat.IsSecret(exists) then return nil end
	return exists and true or false
end

function Spells:LoadData(id)
	if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, id) end
end

-- Returns { token, id, name, icon, known, status }.
function Spells:Resolve(token)
	local id, name = Resolver.ParseToken(token)
	local result = { token = token, id = id }
	if id then
		local resolvedName, _, icon = Compat.GetSpellInfo(id)
		if resolvedName then
			result.name, result.icon, result.status = resolvedName, icon, OK
		elseif spellExists(id) then
			result.status = LOADING
			self:RequestLoad(id)
		else
			result.status = MISSING
		end
	else
		local resolvedName, resolvedID, icon = Compat.GetSpellInfo(name)
		if resolvedName and resolvedID then
			result.name, result.id, result.icon, result.status = resolvedName, resolvedID, icon, OK
		else
			result.name, result.status = name, UNVERIFIED
		end
	end
	if result.status == OK then result.known = Spells.IsKnown(result.id) end
	return result
end

function Spells:Describe(results)
	local lines = {}
	for _, r in ipairs(results) do
		if r.status == OK then
			lines[#lines + 1] = string.format("|cff33ff33%s (%d)|r - %s", r.name, r.id,
				r.known and L["you know this spell"] or L["not in your spellbook (fine for buffs from others)"])
		elseif r.status == LOADING then
			lines[#lines + 1] = string.format("|cffffd100%d|r - %s", r.id, L["loading spell data, check again in a moment"])
		elseif r.status == UNVERIFIED then
			lines[#lines + 1] = string.format("|cffffd100%s|r - %s", r.name,
				L["not found in your spellbook. It still matches auras with exactly this name out of combat. Add the spell ID to track it in combat."])
		else
			lines[#lines + 1] = string.format("|cffff3333%s|r - %s", r.token, L["no spell has this ID"])
		end
	end
	if #lines == 0 then lines[1] = L["No spells entered."] end
	return lines
end

function Spells:ResetBook()
	self.book = nil
end

function Spells:Spellbook()
	if self.book then return self.book end
	local book, byName = {}, {}
	local function add(name, id, icon)
		if Compat.IsSecret(name, id, icon) or type(name) ~= "string" or type(id) ~= "number" then return end
		local index = byName[name]
		if index then
			book[index].id, book[index].icon = id, icon or book[index].icon
		else
			book[#book + 1] = { name = name, id = id, icon = icon }
			byName[name] = #book
		end
	end
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
		pcall(function()
			for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
				local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
				if info then
					local offset = info.itemIndexOffset or 0
					for i = offset + 1, offset + (info.numSpellBookItems or 0) do
						local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
						if item and (not spellType or item.itemType == spellType) then
							add(item.name, item.spellID or item.actionID, item.iconID)
						end
					end
				end
			end
		end)
	elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
		pcall(function()
			for tab = 1, GetNumSpellTabs() do
				local _, _, offset, count = GetSpellTabInfo(tab)
				for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
					local _, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
					local name, _, icon = Compat.GetSpellInfo(id)
					add(name, id, icon)
				end
			end
		end)
	end
	table.sort(book, function(a, b) return a.name < b.name end)
	if #book > 0 then self.book = book end
	return book
end

function Spells:Search(filter, limit)
	filter = filter and filter:lower() or ""
	local out = {}
	if limit <= 0 then return out end
	for _, spell in ipairs(self:Spellbook()) do
		if filter == "" or spell.name:lower():find(filter, 1, true) then
			out[#out + 1] = spell
			if #out >= limit then break end
		end
	end
	return out
end
