-- /goto, /bring, /tpm, /tpcoords, /tpback, /spectate, /noclip
--
-- All of goto/bring/tpcoords ultimately just tell a client "go to these
-- coords" -- server/commands never duplicate that movement logic, they only
-- resolve WHO gets told and WHERE, then relay to client/teleport.lua's single
-- teleportPedTo(coords) primitive via the same qbadmin:client:teleportTo
-- event. tpm/tpback don't even need coords from the server -- the waypoint
-- and the undo history are client-local state -- so those two are a bare
-- relay with no payload.

local OPTS_MOD = { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'qbadmin' }
local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'qbadmin' }

QB.commands.add('goto', 'Teleport to a player', { { name = 'id' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end
    if targetSrc == source then return Admin.respond(source, false, 'cannot goto yourself') end

    local coords = GetEntityCoords(GetPlayerPed(targetSrc))
    TriggerClientEvent('qbadmin:client:teleportTo', source, { x = coords.x, y = coords.y, z = coords.z })
    Admin.log(source, 'goto', data)
    Admin.respond(source, true, ('Teleported to %s'):format(data.name))
end, OPTS_MOD)

QB.commands.add('bring', 'Teleport a player to you', { { name = 'id' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end
    if targetSrc == source then return Admin.respond(source, false, 'cannot bring yourself') end

    local coords = GetEntityCoords(GetPlayerPed(source))
    TriggerClientEvent('qbadmin:client:teleportTo', targetSrc, { x = coords.x, y = coords.y, z = coords.z })
    Admin.log(source, 'bring', data)
    Admin.respond(source, true, ('Brought %s to you'):format(data.name))
end, OPTS_MOD)

QB.commands.add('tpm', 'Teleport to your waypoint', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:tpm', source)
end, OPTS_MOD)

QB.commands.add('tpcoords', 'Teleport to literal coordinates', { { name = 'x' }, { name = 'y' }, { name = 'z' } }, true,
    function(source, args)
        local x = Admin.finiteNumber(args[1])
        local y = Admin.finiteNumber(args[2])
        local z = Admin.finiteNumber(args[3])
        if not (x and y and z) then return Admin.respond(source, false, 'x, y and z must all be numbers') end
        TriggerClientEvent('qbadmin:client:teleportTo', source, { x = x, y = y, z = z })
    end, OPTS_MOD)

QB.commands.add('tpback', 'Return to your position before the last teleport', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:tpback', source)
end, OPTS_MOD)

QB.commands.add('spectate', 'Spectate a player; omit id to stop', { { name = 'id' } }, false, function(source, args)
    if not args[1] or args[1] == '' then
        TriggerClientEvent('qbadmin:client:spectate', source, nil)
        Admin.respond(source, true, 'Stopped spectating')
        return
    end

    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end
    if targetSrc == source then return Admin.respond(source, false, 'cannot spectate yourself') end

    TriggerClientEvent('qbadmin:client:spectate', source, targetSrc)
    Admin.log(source, 'spectate', data)
    Admin.respond(source, true, ('Spectating %s'):format(data.name))
end, OPTS_MOD)

QB.commands.add('noclip', 'Toggle a free-fly camera', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:noclip', source)
    Admin.log(source, 'noclip')
end, OPTS_ADMIN)
