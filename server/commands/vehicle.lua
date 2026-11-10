-- /car, /veh, /givevehicle, /dv, /fix
--
-- /givekeys belongs to kora_vehiclekeys (a player hands over keys they hold);
-- this resource must not register a command with that name.
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
    if Kora.shared.get('vehicles', model) then return model end
    local hash = joaat(model)
    if hash == 0 or hash == -1 or not Kora.lookup.vehicle(hash) then return nil end
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

    TriggerClientEvent('kora_admin:client:enterVehicle', targetSrc, netId, -1)
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
    if Config.vehicle.notifyTarget and targetSrc ~= source then
        Kora.notify.send(targetSrc, { message = ('You received a %s and its keys'):format(model), type = 'success' })
    end
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

-- True when another player is sitting in the vehicle; /dv never deletes those
-- out from under their driver.
local function occupiedByOther(vehicle, source)
    local own = GetPlayerPed(source)
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped and ped ~= 0 and ped ~= own and IsPedAPlayer(ped) then return true end
    end
    return false
end

-- Vehicles within `radius` of the admin, nearest first. Enumerated server-side
-- so wrecks owned by other clients are found and can be deleted without
-- requesting network control.
local function vehiclesNear(source, radius)
    local origin = GetEntityCoords(GetPlayerPed(source))
    local bucket = GetPlayerRoutingBucket(source)
    local found = {}
    for _, vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) and GetEntityRoutingBucket(vehicle) == bucket then
            local coords = GetEntityCoords(vehicle)
            local dx, dy, dz = coords.x - origin.x, coords.y - origin.y, coords.z - origin.z
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            if distance <= radius then found[#found + 1] = { entity = vehicle, distance = distance } end
        end
    end
    table.sort(found, function(a, b) return a.distance < b.distance end)
    return found
end

Admin.addCommand('dv', 'Delete the vehicle you are in, else the nearest one (or all within [radius])', { { name = 'radius' } }, false, function(source, args)
    local nearest = tonumber(Config.dv.nearestRadius) or 0
    local maxRadius = tonumber(Config.dv.maxRadius) or 0
    local vehicle = GetVehiclePedIsIn(GetPlayerPed(source))
    local inVehicle = vehicle ~= 0 and DoesEntityExist(vehicle)

    -- nearestRadius = 0 keeps the original in-vehicle-only behaviour.
    if nearest <= 0 then
        if not inVehicle then return Admin.respond(source, false, 'you are not in a vehicle') end
        DeleteEntity(vehicle)
        Admin.log(source, 'dv')
        return Admin.respond(source, true, 'Deleted your current vehicle')
    end

    local radius
    if args and args[1] ~= nil and args[1] ~= '' then
        radius = tonumber(args[1])
        if not radius or radius ~= radius or radius <= 0 or radius == math.huge then
            return Admin.respond(source, false, 'radius must be a positive number')
        end
        radius = math.min(radius, maxRadius > 0 and maxRadius or nearest)
    elseif inVehicle then
        local plate = GetVehicleNumberPlateText(vehicle)
        DeleteEntity(vehicle)
        Admin.log(source, 'dv', nil, { mode = 'current', plate = plate })
        return Admin.respond(source, true, 'Deleted your current vehicle')
    end

    local candidates = {}
    for _, found in ipairs(vehiclesNear(source, radius or nearest)) do
        if not occupiedByOther(found.entity, source) then candidates[#candidates + 1] = found.entity end
    end
    if #candidates == 0 then
        return Admin.respond(source, false, ('no vehicle within %.1f m'):format(radius or nearest))
    end
    if not radius then candidates = { candidates[1] } end

    local plates = {}
    for _, entity in ipairs(candidates) do
        plates[#plates + 1] = tostring(GetVehicleNumberPlateText(entity))
        DeleteEntity(entity) -- server-side delete works whichever client owns the entity
    end
    Admin.log(source, 'dv', nil, {
        mode = radius and 'radius' or 'nearest', radius = radius or nearest,
        count = #candidates, plates = table.concat(plates, ','),
    })
    Admin.respond(source, true, #candidates == 1
        and ('Deleted nearby vehicle %s'):format(plates[1])
        or ('Deleted %d vehicles within %.1f m'):format(#candidates, radius))
end, OPTS_ADMIN)

Admin.addCommand('fix', 'Repair the vehicle you are in', nil, false, function(source)
    if GetVehiclePedIsIn(GetPlayerPed(source)) == 0 then
        return Admin.respond(source, false, 'you are not in a vehicle')
    end
    TriggerClientEvent('kora_admin:client:fix', source)
    Admin.log(source, 'fix')
    Admin.respond(source, true, 'Repaired your current vehicle')
end, OPTS_MOD)
