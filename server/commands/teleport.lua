-- /goto, /bring, /sendback, /tpm, /tpcoords, /tpback, /spectate, /noclip
--
-- All of goto/bring/tpcoords ultimately just tell a client "go to these
-- coords" -- server/commands never duplicate that movement logic, they only
-- resolve WHO gets told and WHERE, then relay to client/teleport.lua's single
-- teleportPedTo(coords) primitive via the same qbadmin:client:teleportTo
-- event. tpm/tpback don't even need coords from the server -- the waypoint
-- and the undo history are client-local state -- so those two are a bare
-- relay with no payload.

local OPTS_MOD = { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'kora_admin' }
local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'kora_admin' }

---Parses the normal chat-coordinate form plus common FiveM/Lua literals:
---`x y z`, `x, y, z`, `vec3(x, y, z)`, `vector3(x, y, z)`, and the vec4 /
---vector4 variants. The fourth component is a heading, not a Z offset.
---@param args string[]
---@return table|nil coords `{x, y, z, heading?}`
local function parseCoordinates(args)
    local text = table.concat(args, ' ')
    local lower = text:lower()
    local dimensions, values = lower:match('^%s*vec%s*([34])%s*%(([^()]*)%)%s*$')
    if not dimensions then
        dimensions, values = lower:match('^%s*vector%s*([34])%s*%(([^()]*)%)%s*$')
    end

    local parts = {}
    if dimensions then
        for value in values:gmatch('[^,]+') do parts[#parts + 1] = value end
        if #parts ~= tonumber(dimensions) then return nil end
    else
        -- A comma-separated paste without a vec/vector wrapper is friendly
        -- too, while still rejecting arbitrary words and extra dimensions.
        for value in text:gsub(',', ' '):gmatch('%S+') do parts[#parts + 1] = value end
        if #parts ~= 3 and #parts ~= 4 then return nil end
    end

    local x, y, z = Admin.finiteNumber(parts[1]), Admin.finiteNumber(parts[2]), Admin.finiteNumber(parts[3])
    local heading = parts[4] and Admin.finiteNumber(parts[4]) or nil
    if not (x and y and z) or (parts[4] and not heading) then return nil end

    return { x = x, y = y, z = z, heading = heading }
end

Admin.addCommand('goto', 'Teleport to a player', { { name = 'id' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end
    if targetSrc == source then return Admin.respond(source, false, 'cannot goto yourself') end

    local coords = GetEntityCoords(GetPlayerPed(targetSrc))
    TriggerClientEvent('qbadmin:client:teleportTo', source, { x = coords.x, y = coords.y, z = coords.z })
    Admin.log(source, 'goto', data)
    Admin.respond(source, true, ('Teleported to %s'):format(data.name))
end, OPTS_MOD)

Admin.addCommand('bring', 'Teleport a player to you', { { name = 'id' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end
    if targetSrc == source then return Admin.respond(source, false, 'cannot bring yourself') end

    local coords = GetEntityCoords(GetPlayerPed(source))
    TriggerClientEvent('qbadmin:client:teleportTo', targetSrc, { x = coords.x, y = coords.y, z = coords.z })
    Admin.log(source, 'bring', data)
    Admin.respond(source, true, ('Brought %s to you'):format(data.name))
end, OPTS_MOD)

-- Every kora_admin teleport is recorded by the destination client's own bounded
-- history. Sending a brought player back therefore uses the exact same undo
-- primitive as /tpback, but relays it to the selected player instead.
Admin.addCommand('sendback', 'Return a player to their position before the last admin teleport', { { name = 'id' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    TriggerClientEvent('qbadmin:client:tpback', targetSrc)
    Admin.log(source, 'sendback', data)
    Admin.respond(source, true, ('Sent %s back'):format(data.name))
end, OPTS_MOD)

Admin.addCommand('tpm', 'Teleport to your waypoint', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:tpm', source)
end, OPTS_MOD)

Admin.addCommand('tpcoords', 'Teleport to coordinates or vec3/vector3/vec4/vector4', { { name = 'coordinates' } }, true,
    function(source, args)
        local coords = parseCoordinates(args)
        if not coords then
            return Admin.respond(source, false, 'use x y z, vec3(x, y, z), or vec4(x, y, z, heading)')
        end
        TriggerClientEvent('qbadmin:client:teleportTo', source, coords)
    end, OPTS_MOD)

Admin.addCommand('tpback', 'Return to your position before the last teleport', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:tpback', source)
end, OPTS_MOD)

Admin.addCommand('spectate', 'Spectate a player; omit id to stop', { { name = 'id' } }, false, function(source, args)
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

Admin.addCommand('noclip', 'Toggle a free-fly camera', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:noclip', source)
    Admin.log(source, 'noclip')
end, OPTS_ADMIN)
