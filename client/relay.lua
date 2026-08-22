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

RegisterNetEvent('qbadmin:client:setHealth', function(value)
    local ped = PlayerPedId()
    SetEntityHealth(ped, value or GetEntityMaxHealth(ped))
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
