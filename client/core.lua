-- Admin (client realm) -- the namespace client/*.lua files attach to, plus
-- the caller's cached permission level. This is UX filtering ONLY (which menu
-- items to show enabled) -- every actual action still goes through a command,
-- and every command's own checkPermission re-checks server-side regardless of
-- what the menu displayed. A stale or forged client-side level here cannot
-- grant anything; it can only hide/show buttons.

Admin = Admin or {}
Admin.level = 'user'

local RANKS = Config.permissions.ranks

---@param required string
---@return boolean
function Admin.hasLevel(required)
    return (RANKS[Admin.level] or RANKS.user) >= (RANKS[required] or RANKS.user)
end

---Reads qbcore's server-controlled development mode mirrored on this client.
---A failed export call is treated as disabled so the menu fails closed while
---qbcore is starting or restarting.
---@return boolean
function Admin.isDevMode()
    local ok, enabled = pcall(function() return exports.qbcore:isDevMode() end)
    return ok and enabled == true
end

RegisterNetEvent('qbadmin:client:level', function(level)
    Admin.level = level or 'user'
end)

CreateThread(function()
    TriggerServerEvent('qbadmin:server:requestLevel')
end)

-- Re-request on the client's own player-loaded signal, so a (re)connect
-- always gets a fresh level rather than relying only on resource-start timing.
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('qbadmin:server:requestLevel')
end)
