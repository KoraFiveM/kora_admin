-- Admin (client realm) -- the namespace client/*.lua files attach to, plus
-- the caller's cached permission level. This is UX filtering ONLY (which menu
-- items to show enabled) -- every actual action still goes through a command,
-- and every command's own checkPermission re-checks server-side regardless of
-- what the menu displayed. A stale or forged client-side level here cannot
-- grant anything; it can only hide/show buttons.

Admin = Admin or {}
Admin.level = 'user'
Admin.noclipActive = false
Admin.spectating = false

local function roleName(role)
    return Config.permissions.gates[role] or role
end

local function roleRank(role)
    local definition = Config.permissions.roles[roleName(role)]
    return definition and definition.rank or -1
end

---@param required string
---@return boolean
function Admin.hasLevel(required)
    return roleRank(Admin.level) >= roleRank(required)
end

---Reads qbcore's server-controlled development mode mirrored on this client.
---A failed export call is treated as disabled so the menu fails closed while
---qbcore is starting or restarting.
---@return boolean
function Admin.isDevMode()
    local ok, enabled = pcall(function() return exports.qbcore:isDevMode() end)
    return ok and enabled == true
end

---Returns the current server-replicated admin-duty state for this character.
---The server remains authoritative; a missing player snapshot is treated as
---off until qbcore has finished loading it.
---@return boolean
function Admin.isAdminDuty()
    local ok, state = pcall(function()
        return exports.qbcore:getPlayerData({ 'metadata', 'adminDuty' })
    end)
    return ok and state == true
end

---@return boolean
function Admin.isNoclipActive()
    return Admin.noclipActive == true
end

---@return boolean
function Admin.isSpectating()
    return Admin.spectating == true
end

-- `user` is both the default and a legitimate server answer, so track the
-- response separately while retrying the initial request.
local levelAnswered = false

RegisterNetEvent('qbadmin:client:level', function(level)
    Admin.level = level or 'user'
    levelAnswered = true
end)

CreateThread(function()
    for _ = 1, 15 do
        TriggerServerEvent('qbadmin:server:requestLevel')
        Wait(2000)
        if levelAnswered then return end
    end
    print('^1[qbadmin]^7 the server never answered the permission-level request; menu items will stay filtered to "user". Every command still re-checks server-side.')
end)

-- Re-request on the client's own player-loaded signal, so a (re)connect
-- always gets a fresh level rather than relying only on resource-start timing.
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('qbadmin:server:requestLevel')
end)
