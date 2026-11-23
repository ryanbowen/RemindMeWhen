local _, ns = ...
local Compat, Resolver, L = ns.Compat, ns.Resolver, ns.L

-- Instance names and IDs. The game only describes the instance you are in, so other names stay
-- as typed and match by name.
local Instances = Resolver.New({ noun = L["instance"], pickSource = L["the instance you are in"] })
ns.Instances = Instances

local OK, UNVERIFIED = Resolver.OK, Resolver.UNVERIFIED

-- Name and ID of the current instance, or nil outside instances.
function Instances.Current()
	if not (IsInInstance and Compat.Plain(IsInInstance())) or not GetInstanceInfo then return nil end
	local name, _, _, _, _, _, _, id = GetInstanceInfo()
	if Compat.IsSecret(name, id) or type(name) ~= "string" then return nil end
	return name, tonumber(id)
end

function Instances:LoadData() end

function Instances:Resolve(token)
	local id, name = Resolver.ParseToken(token)
	local currentName, currentID = Instances.Current()
	local result = { token = token, id = id, name = name, status = UNVERIFIED }
	if id and currentID == id then
		result.name, result.status = currentName, OK
	elseif id and name then
		result.status = OK
	elseif name and currentName and name:lower() == currentName:lower() and currentID then
		result.name, result.id, result.status = currentName, currentID, OK
	end
	return result
end

function Instances:Describe(results)
	local lines = {}
	for _, r in ipairs(results) do
		if r.status == OK then
			lines[#lines + 1] = string.format("|cff33ff33%s (%d)|r", r.name, r.id)
		elseif r.id then
			lines[#lines + 1] = string.format("|cffffd100%d|r - %s", r.id, L["matches the instance with this ID"])
		else
			lines[#lines + 1] = string.format("|cffffd100%s|r - %s", r.name, L["matches instance names containing this text"])
		end
	end
	if #lines == 0 then lines[1] = L["No instances entered: any instance of the chosen type matches."] end
	return lines
end

function Instances:Search(filter)
	local name, id = Instances.Current()
	if not (name and id) then return {} end
	if filter and filter ~= "" and not name:lower():find(filter, 1, true) then return {} end
	return { { name = name, id = id } }
end

-- Whether the current instance is one of the comma separated names or IDs.
function Instances.Matches(text)
	local name, id = Instances.Current()
	if not name then return false end
	local lower = name:lower()
	for _, token in ipairs(Compat.SplitList(text)) do
		local tokenID, tokenName = Resolver.ParseToken(token)
		if tokenID and tokenID == id then return true end
		if not tokenID and tokenName and lower:find(tokenName:lower(), 1, true) then return true end
	end
	return false
end
