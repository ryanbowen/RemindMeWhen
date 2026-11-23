local _, ns = ...
local Compat, Resolver, L = ns.Compat, ns.Resolver, ns.L

local Items = Resolver.New({ noun = L["item"] })
ns.Items = Items

local OK, LOADING, UNVERIFIED, MISSING = Resolver.OK, Resolver.LOADING, Resolver.UNVERIFIED, Resolver.MISSING
local BAG_COUNT = NUM_BAG_SLOTS or 4

local function itemExists(id)
	if not (C_Item and C_Item.DoesItemExistByID) then return nil end
	local ok, exists = pcall(C_Item.DoesItemExistByID, id)
	if not ok or Compat.IsSecret(exists) then return nil end
	return exists and true or false
end

function Items:LoadData(id)
	if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

-- Returns { token, id, name, icon, count, status }.
function Items:Resolve(token)
	local id, name = Resolver.ParseToken(token)
	local result = { token = token, id = id }
	if id then
		local resolvedName, _, icon = Compat.GetItemInfo(id)
		if resolvedName then
			result.name, result.icon, result.status = resolvedName, icon or Compat.GetItemIcon(id), OK
		elseif itemExists(id) ~= false then
			result.status, result.icon = LOADING, Compat.GetItemIcon(id)
			self:RequestLoad(id)
		else
			result.status = MISSING
		end
	else
		local resolvedName, resolvedID, icon = Compat.GetItemInfo(name)
		if not resolvedID then
			resolvedID = Compat.GetItemInstant(name)
			if resolvedID then resolvedName, _, icon = Compat.GetItemInfo(resolvedID) end
		end
		if resolvedName and resolvedID then
			result.name, result.id, result.icon, result.status = resolvedName, resolvedID, icon, OK
		else
			result.name, result.status = name, UNVERIFIED
		end
	end
	if result.id then result.count = Compat.GetItemCount(result.id) end
	return result
end

function Items:Describe(results)
	local lines = {}
	for _, r in ipairs(results) do
		if r.status == OK then
			lines[#lines + 1] = string.format("|cff33ff33%s (%d)|r - %s", r.name, r.id,
				string.format(L["you have %d"], r.count or 0))
		elseif r.status == LOADING then
			lines[#lines + 1] = string.format("|cffffd100%d|r - %s", r.id, L["loading item data, check again in a moment"])
		elseif r.status == UNVERIFIED then
			lines[#lines + 1] = string.format("|cffffd100%s|r - %s", r.name,
				L["not found. Names only resolve for items the game has seen. Use the item ID or pick it from your bags."])
		else
			lines[#lines + 1] = string.format("|cffff3333%s|r - %s", r.token, L["no item has this ID"])
		end
	end
	if #lines == 0 then lines[1] = L["No items entered."] end
	return lines
end

local function bagItem(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
		if ok and type(info) == "table" then return info.itemID, info.iconFileID end
		return nil
	end
	if GetContainerItemInfo then
		local ok, icon, _, _, _, _, _, _, _, _, id = pcall(GetContainerItemInfo, bag, slot)
		if ok then return id, icon end
	end
	return nil
end

local function bagSlots(bag)
	local fn = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	if not fn then return 0 end
	local ok, count = pcall(fn, bag)
	return ok and tonumber(Compat.Plain(count)) or 0
end

function Items:Search(filter, limit)
	filter = filter and filter:lower() or ""
	local out, seen = {}, {}
	if limit <= 0 then return out end
	for bag = 0, BAG_COUNT do
		for slot = 1, bagSlots(bag) do
			local id, icon = bagItem(bag, slot)
			if type(id) == "number" and not seen[id] then
				seen[id] = true
				local name = Compat.GetItemInfo(id)
				if name and (filter == "" or name:lower():find(filter, 1, true)) then
					out[#out + 1] = { name = name, id = id, icon = icon }
					if #out >= limit then return out end
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

local WEAPON_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
-- Weapon subclasses that take sharpening stones (axes, polearms, swords, daggers) or weightstones
-- (maces, staves, fist weapons). Other weapons take either.
local SHARP = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [15] = true }
local BLUNT = { [4] = true, [5] = true, [10] = true, [13] = true }

local function weaponEdge(slot)
	local id = slot and GetInventoryItemID and Compat.Plain(GetInventoryItemID("player", slot))
	if not id then return nil end
	local _, classID, _, subclassID = Compat.GetItemInstant(id)
	if classID ~= WEAPON_CLASS then return nil end
	if SHARP[subclassID] then return "sharp" end
	if BLUNT[subclassID] then return "blunt" end
	return nil
end

local function usable(id, edge, level)
	if edge == "sharp" and ns.Data.bluntOnly[id] then return false end
	if edge == "blunt" and ns.Data.sharpOnly[id] then return false end
	local _, _, _, minLevel = Compat.GetItemInfo(id)
	return not (minLevel and level and minLevel > level)
end

-- Best entry of the list: the first one in your bags that your level allows and, when a weapon slot
-- is given, that fits the equipped weapon. Falls back to the first resolved entry.
function Items:FirstOwned(text, slot)
	local edge = weaponEdge(slot)
	local level = Compat.Plain(UnitLevel("player"))
	local fallback
	for _, token in ipairs(Compat.SplitList(text)) do
		local id, name = Resolver.ParseToken(token)
		id = id or Compat.GetItemInstant(name)
		if id then
			fallback = fallback or id
			if (Compat.GetItemCount(id) or 0) > 0 and usable(id, edge, level) then return id end
		end
	end
	return fallback
end
