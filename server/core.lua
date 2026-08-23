-- Admin (server realm) -- the single namespace every qbadmin server file
-- attaches to. No exports are published from this resource: every action is
-- reached exclusively through the commands registered in server/commands/*.lua
-- (see docs.md's "commands are the only entry point" section), so there is
-- nothing else worth putting on a public export surface.

Admin = Admin or {}

-- Read-only self-info plumbing for the NUI's cosmetic menu filtering (see
-- client/core.lua) -- not a privileged action, just lets a client know its
-- own already-server-known permission level without duplicating
-- Core.permissions logic client-side. Mirrors what /permission already
-- returns for a self target.
RegisterNetEvent('qbadmin:server:requestLevel', function()
    local src = source
    local level = exports.qbcore:getPermission(src)
    TriggerClientEvent('qbadmin:client:level', src, level)
end)
