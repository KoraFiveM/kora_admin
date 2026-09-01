-- Admin (server realm) -- the single namespace every qbadmin server file
-- attaches to. No exports are published from this resource: every action is
-- reached exclusively through the commands registered in server/commands/*.lua
-- (see docs.md's "commands are the only entry point" section), so there is
-- nothing else worth putting on a public export surface.

Admin = Admin or {}

-- Client-native states do not have a reliable server getter.  Keep track of
-- the values this resource has applied so commands with an omitted state can
-- actually toggle rather than silently enabling the feature every time.
-- These are intentionally ephemeral: they represent qbadmin's own relays,
-- not player data that belongs in qbcore persistence.
Admin.states = Admin.states or {
    frozen = {},
    god = {},
    invisible = {},
}

---@param value string|nil
---@param current boolean
---@return boolean|nil state
---@return string|nil err
function Admin.resolveToggle(value, current)
    if value == nil or value == '' then return not current end
    if type(value) ~= 'string' then return nil, 'state must be on or off' end

    local normalized = value:lower()
    if normalized == 'true' or normalized == 'on' or normalized == '1' then return true end
    if normalized == 'false' or normalized == 'off' or normalized == '0' then return false end
    return nil, 'state must be on or off'
end

---@param value any
---@param minimum number|nil
---@param maximum number|nil
---@param integer boolean|nil
---@return number|nil
function Admin.finiteNumber(value, minimum, maximum, integer)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    if minimum and number < minimum then return nil end
    if maximum and number > maximum then return nil end
    if integer and number ~= math.floor(number) then return nil end
    return number
end

AddEventHandler('playerDropped', function()
    local src = source
    for _, states in pairs(Admin.states) do states[src] = nil end
end)

-- Read-only self-info plumbing for the NUI's cosmetic menu filtering (see
-- client/core.lua) -- not a privileged action, just lets a client know its
-- own already-server-known permission level. This uses the same qblib-backed
-- resolver as every command, including optional Discord roles.
RegisterNetEvent('qbadmin:server:requestLevel', function()
    local src = source
    local level = Admin.getLevel(src)
    TriggerClientEvent('qbadmin:client:level', src, level)
end)
