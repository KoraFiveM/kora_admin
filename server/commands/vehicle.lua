-- /car, /veh, /givevehicle, /givekeys, /dv, /fix
--
-- Vehicle creation is server-owned so it remains compatible with strict entity
-- lockdown. The recipient client receives only the resulting network id for
-- the local warp after this permission-checked command succeeds.

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'kora_admin' }
local OPTS_MOD = { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'kora_admin' }

local function validModel(model)
    if type(model) ~= 'string' or not model:match('^[%w_]+$') then return nil end
    model = model:lower()

    -- The shared lookup also includes streamed addon vehicles.
    if QB.shared.get('vehicles', model) then return model end
    local hash = joaat(model)
    if hash == 0 or hash == -1 or not QB.lookup.vehicle(hash) then return nil end
    return model
end

local function validPlate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:upper()
    if #plate < 1 or #plate > 15 or not plate:match('^[A-Z0-9]+$') then return nil end
    return plate
end

---@param targetSrc integer
---@param vehicle integer
---@return boolean granted
local function giveVehicleKeys(targetSrc, vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local plate = GetVehicleNumberPlateText(vehicle)
    if type(plate) ~= 'string' or plate:match('^%s*$') then return false end

    -- Administrative grants must work on servers that have disabled ordinary
    -- temporary keys. kora_vehiclekeys still owns plate normalisation and access
    -- state; this flag marks the grant as an intentional privileged override.
    return exports.kora_vehiclekeys:giveKeys(targetSrc, plate, true) == true
end

local function spawnFor(targetSrc, model)
    local ped = GetPlayerPed(targetSrc)
    if not ped or ped == 0 then return nil, 'target player is unavailable' end

    local origin = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local radians = math.rad(heading)
    local distance = tonumber(Config.vehicle.spawnOffset) or 3.0
    local x = origin.x - math.sin(radians) * distance
    local y = origin.y + math.cos(radians) * distance
    local vehicle = CreateVehicle(joaat(model), x, y, origin.z, heading, true, true)
    -- Server-created entities are registered asynchronously.  Checking in the
    -- same tick can report a failure even though the vehicle is about to
    -- appear, which made /car and /veh show a false error notification.
    local attempts = 0
    while vehicle and vehicle ~= 0 and not DoesEntityExist(vehicle) and attempts < 100 do
        Wait(0)
        attempts = attempts + 1
    end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil, 'vehicle creation failed'
    end

    SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(targetSrc))

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    attempts = 0
    while (type(netId) ~= 'number' or netId <= 0) and attempts < 100 do
        Wait(0)
        attempts = attempts + 1
        netId = NetworkGetNetworkIdFromEntity(vehicle)
    end
    if type(netId) ~= 'number' or netId <= 0 then
        DeleteEntity(vehicle)
        return nil, 'vehicle network registration failed'
    end

    if not giveVehicleKeys(targetSrc, vehicle) then
        DeleteEntity(vehicle)
        return nil, 'could not grant vehicle keys'
    end

    TriggerClientEvent('qbadmin:client:enterVehicle', targetSrc, netId, -1)
    return netId
end

Admin.addCommand('car', 'Spawn a vehicle and get in', { { name = 'model' } }, true, function(source, args)
    local model = validModel(args[1])
    if not model then return Admin.respond(source, false, 'unknown vehicle model') end

    local _, spawnErr = spawnFor(source, model)
    if spawnErr then return Admin.respond(source, false, spawnErr) end
    Admin.log(source, 'car', nil, { model = model })
    Admin.respond(source, true, ('Spawned %s'):format(model))
end, OPTS_ADMIN)

Admin.addCommand('veh', 'Spawn a vehicle for a player', { { name = 'id' }, { name = 'model' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    local model = validModel(args[2])
    if not model then return Admin.respond(source, false, 'unknown vehicle model') end

    local _, spawnErr = spawnFor(targetSrc, model)
    if spawnErr then return Admin.respond(source, false, spawnErr) end
    Admin.log(source, 'veh', data, { model = model })
    Admin.respond(source, true, ('Spawned %s for %s'):format(model, data.name))
end, OPTS_ADMIN)

Admin.addCommand('givevehicle', 'Add a personal vehicle to a player garage', {
    { name = 'id' }, { name = 'model' }, { name = 'plate' },
}, true, function(source, args)
    local _, data, err = Admin.resolveTarget(source, args[1])
    if not data then return Admin.respond(source, false, err) end

    local model = validModel(args[2])
    if not model then return Admin.respond(source, false, 'unknown vehicle model') end

    local plate = validPlate(args[3])
    if not plate then return Admin.respond(source, false, 'plate must be 1-15 letters or numbers') end

    local created, createErr = exports.kora_core:createVehicle(data.citizenid, model, plate)
    if not created then return Admin.respond(source, false, createErr or 'could not save vehicle') end

    Admin.log(source, 'givevehicle', data, { model = model, plate = plate })
    Admin.respond(source, true, ('Added %s (%s) to %s\'s garage'):format(model, plate, data.name))
end, OPTS_ADMIN)

Admin.addCommand('givekeys', 'Give a player keys to the vehicle they are driving', { { name = 'id' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    local targetPed = GetPlayerPed(targetSrc)
    local vehicle = targetPed and targetPed ~= 0 and GetVehiclePedIsIn(targetPed, false) or 0
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= targetPed then
        return Admin.respond(source, false, ('%s must be driving a vehicle'):format(data.name))
    end
    if not giveVehicleKeys(targetSrc, vehicle) then
        return Admin.respond(source, false, 'could not grant vehicle keys')
    end

    Admin.log(source, 'givekeys', data, { plate = GetVehicleNumberPlateText(vehicle) })
    Admin.respond(source, true, ('Gave %s the keys to their current vehicle'):format(data.name))
end, OPTS_ADMIN)

Admin.addCommand('dv', 'Delete the vehicle you are in', nil, false, function(source)
    local vehicle = GetVehiclePedIsIn(GetPlayerPed(source))
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return Admin.respond(source, false, 'you are not in a vehicle')
    end
    DeleteEntity(vehicle)
    Admin.log(source, 'dv')
    Admin.respond(source, true, 'Deleted your current vehicle')
end, OPTS_ADMIN)

Admin.addCommand('fix', 'Repair the vehicle you are in', nil, false, function(source)
    if GetVehiclePedIsIn(GetPlayerPed(source)) == 0 then
        return Admin.respond(source, false, 'you are not in a vehicle')
    end
    TriggerClientEvent('qbadmin:client:fix', source)
    Admin.log(source, 'fix')
    Admin.respond(source, true, 'Repaired your current vehicle')
end, OPTS_MOD)
