-- Server -> client relays. A command handler running on the server cannot
-- directly call FreezeEntityPosition/SetEntityHealth/etc. on a ped it doesn't
-- own, so these events are how a command's own implementation reaches into a
-- specific client's world. This file is internal plumbing for the commands in
-- server/commands/*.lua -- it is never a second entry point, nothing outside
-- a command handler ever fires these events.

RegisterNetEvent('qbadmin:client:freeze', function(state)
    FreezeEntityPosition(PlayerPedId(), state)
end)

RegisterNetEvent('qbadmin:client:kill', function()
    SetEntityHealth(PlayerPedId(), 0)
end)

RegisterNetEvent('qbadmin:client:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
end)

RegisterNetEvent('qbadmin:client:revive', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedTasksImmediately(ped)
end)

RegisterNetEvent('qbadmin:client:god', function(state)
    SetEntityInvincible(PlayerPedId(), state)
end)

RegisterNetEvent('qbadmin:client:invisible', function(state)
    SetEntityVisible(PlayerPedId(), not state, false)
end)

RegisterNetEvent('qbadmin:client:fix', function()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then return end
    SetVehicleFixed(veh)
    SetVehicleDeformationFixed(veh)
    SetVehicleUndriveable(veh, false)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
end)

RegisterNetEvent('qbadmin:client:deleteVehicle', function()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 or not DoesEntityExist(veh) then return end
    SetEntityAsMissionEntity(veh, true, true)
    DeleteEntity(veh)
end)

-- This relay is sent only by the permission-checked server commands.  It
-- intentionally owns the resulting network entity locally: that is reliable
-- across FXServer artifacts and lets the recipient enter it immediately.
RegisterNetEvent('qbadmin:client:spawnVehicle', function(model, warp)
    if type(model) ~= 'string' then return end

    local hash = joaat(model)
    if hash == 0 or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return end

    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(hash) then
        QB.notify.send({ type = 'error', message = ('Could not load %s'):format(model) })
        return
    end

    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, Config.vehicle.spawnOffset, 0.0)
    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, GetEntityHeading(ped), true, true)
    SetModelAsNoLongerNeeded(hash)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        QB.notify.send({ type = 'error', message = ('Could not spawn %s'):format(model) })
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    SetNetworkIdCanMigrate(netId, true)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetVehicleNeedsToBeHotwired(vehicle, false)
    SetVehicleFuelLevel(vehicle, 100.0)
    SetVehicleDirtLevel(vehicle, 0.0)
    if warp then TaskWarpPedIntoVehicle(ped, vehicle, -1) end
end)

RegisterNetEvent('qbadmin:client:enterVehicle', function(netId, seat)
    CreateThread(function()
        local attempts = 0
        while not NetworkDoesEntityExistWithNetworkId(netId) and attempts < 50 do
            Wait(100)
            attempts = attempts + 1
        end
        if not NetworkDoesEntityExistWithNetworkId(netId) then return end
        TaskWarpPedIntoVehicle(PlayerPedId(), NetworkGetEntityFromNetworkId(netId), seat or -1)
    end)
end)

RegisterNetEvent('qbadmin:client:coords', function()
    local coords = GetEntityCoords(PlayerPedId())
    QB.nui.copyToClipboard(('%.2f, %.2f, %.2f'):format(coords.x, coords.y, coords.z))
end)

-- GTA health uses 100 as the death floor rather than as a 50% midpoint.
-- Convert the admin command's human-friendly percentage onto the current
-- ped's actual native range: freemode male peds normally top out at 200,
-- while freemode female peds normally top out at 175.
local HEALTH_FLOOR = 100

RegisterNetEvent('qbadmin:client:setHealth', function(value)
    local ped = PlayerPedId()
    local percentage = math.max(0, math.min(100, tonumber(value) or 100))
    local maxHealth = math.max(HEALTH_FLOOR + 1, GetEntityMaxHealth(ped))
    local health = HEALTH_FLOOR + (maxHealth - HEALTH_FLOOR) * (percentage / 100)
    SetEntityHealth(ped, math.floor(health))
end)

RegisterNetEvent('qbadmin:client:setArmor', function(value)
    SetPedArmour(PlayerPedId(), value or 100)
end)

RegisterNetEvent('qbadmin:client:setWeather', function(weatherType)
    SetWeatherTypeNow(weatherType)
    SetWeatherTypeNowPersist(weatherType)
end)

RegisterNetEvent('qbadmin:client:setTime', function(hour, minute)
    NetworkOverrideClockTime(hour, minute or 0, 0)
end)
