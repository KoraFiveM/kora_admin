-- /car, /veh, /dv, /fix
--
-- Vehicle creation is server-owned so it remains compatible with strict entity
-- lockdown. The recipient client receives only the resulting network id for
-- the local warp after this permission-checked command succeeds.

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'qbadmin' }
local OPTS_MOD = { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'qbadmin' }

local function validModel(model)
    if type(model) ~= 'string' or not model:match('^[%w_]+$') then return nil end
    model = model:lower()

    -- Prefer the canonical shared registry.  Keeping the native hash check as
    -- a fallback preserves support for deliberately registered addon vehicles.
    if QB.shared.get('vehicles', model) then return model end
    local hash = joaat(model)
    if hash == 0 or hash == -1 or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end
    return model
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

    TriggerClientEvent('qbadmin:client:enterVehicle', targetSrc, netId, -1)
    return netId
end

QB.commands.add('car', 'Spawn a vehicle and get in', { { name = 'model' } }, true, function(source, args)
    local model = validModel(args[1])
    if not model then return Admin.respond(source, false, 'unknown vehicle model') end

    local _, spawnErr = spawnFor(source, model)
    if spawnErr then return Admin.respond(source, false, spawnErr) end
    Admin.log(source, 'car', nil, { model = model })
    Admin.respond(source, true, ('Spawned %s'):format(model))
end, OPTS_ADMIN)

QB.commands.add('veh', 'Spawn a vehicle for a player', { { name = 'id' }, { name = 'model' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    local model = validModel(args[2])
    if not model then return Admin.respond(source, false, 'unknown vehicle model') end

    local _, spawnErr = spawnFor(targetSrc, model)
    if spawnErr then return Admin.respond(source, false, spawnErr) end
    Admin.log(source, 'veh', data, { model = model })
    Admin.respond(source, true, ('Spawned %s for %s'):format(model, data.name))
end, OPTS_ADMIN)

QB.commands.add('dv', 'Delete the vehicle you are in', nil, false, function(source)
    local vehicle = GetVehiclePedIsIn(GetPlayerPed(source))
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return Admin.respond(source, false, 'you are not in a vehicle')
    end
    DeleteEntity(vehicle)
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
