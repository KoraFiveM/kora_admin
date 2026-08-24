-- /car, /veh, /dv, /fix
--
-- Vehicle creation is deliberately performed by the recipient client.  The
-- older server-side CreateVehicle path fails silently on some FXServer builds;
-- client creation is also the reliable ownership path for immediately warping
-- that player into the vehicle.  This remains server-authorised: only these
-- permission-checked commands issue the relay event.

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'qbadmin' }
local OPTS_MOD = { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'qbadmin' }

local function validModel(model)
    if type(model) ~= 'string' or not model:match('^[%w_]+$') then return nil end
    model = model:lower()

    -- Prefer the canonical shared registry.  Keeping the native hash check as
    -- a fallback preserves support for deliberately registered addon vehicles.
    if QB.shared.get('vehicles', model) then return model end
    local hash = GetHashKey(model)
    if hash == 0 or hash == -1 or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end
    return model
end

QB.commands.add('car', 'Spawn a vehicle and get in', { { name = 'model' } }, true, function(source, args)
    local model = validModel(args[1])
    if not model then return Admin.respond(source, false, 'unknown vehicle model') end

    TriggerClientEvent('qbadmin:client:spawnVehicle', source, model, true)
    Admin.log(source, 'car', nil, { model = model })
    Admin.respond(source, true, ('Spawned %s'):format(model))
end, OPTS_ADMIN)

QB.commands.add('veh', 'Spawn a vehicle for a player', { { name = 'id' }, { name = 'model' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    local model = validModel(args[2])
    if not model then return Admin.respond(source, false, 'unknown vehicle model') end

    TriggerClientEvent('qbadmin:client:spawnVehicle', targetSrc, model, true)
    Admin.log(source, 'veh', data, { model = model })
    Admin.respond(source, true, ('Spawned %s for %s'):format(model, data.name))
end, OPTS_ADMIN)

QB.commands.add('dv', 'Delete the vehicle you are in', nil, false, function(source)
    if GetVehiclePedIsIn(GetPlayerPed(source)) == 0 then
        return Admin.respond(source, false, 'you are not in a vehicle')
    end
    TriggerClientEvent('qbadmin:client:deleteVehicle', source)
    Admin.log(source, 'dv')
    Admin.respond(source, true, 'Deleted your current vehicle')
end, OPTS_ADMIN)

QB.commands.add('fix', 'Repair the vehicle you are in', nil, false, function(source)
    if GetVehiclePedIsIn(GetPlayerPed(source)) == 0 then
        return Admin.respond(source, false, 'you are not in a vehicle')
    end
    TriggerClientEvent('qbadmin:client:fix', source)
    Admin.log(source, 'fix')
    Admin.respond(source, true, 'Repaired your current vehicle')
end, OPTS_MOD)
