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

-- Raw natives alone (NetworkResurrectLocalPlayer/SetEntityHealth) only clear
-- GTA's own death state -- they say nothing to whichever ambulance job is
-- actually running. Both real qb-ambulancejob and the kora_lib-native kora_ambulance
-- rebuild track their OWN client-local "is this player dead/downed" flags
-- (plain module locals in one, a Kora.notify-driven state table in the other)
-- that gate a persistent per-frame thread forcing the death animation/ragdoll/
-- disabled controls -- if that thread's flag is never cleared, the player
-- stays visibly stuck in the death loop even after their raw health reads
-- full. Firing BOTH resources' own revive event covers whichever one is
-- actually started: a RegisterNetEvent name with no registered handler is a
-- harmless no-op, so this never needs to detect which job is active. Event
-- names and required args confirmed against each resource's own source
-- (qb-ambulancejob's client/main.lua takes none; kora_ambulance's client/death.lua
-- takes a 0-100 health percentage).
local function reviveLocalPed()
    local ped = PlayerPedId()
    -- NetworkResurrectLocalPlayer places its subject at world coordinates.  If
    -- that subject is seated, GTA resolves those coordinates outside the
    -- vehicle and can launch the player upward.  kora_ambulance already prevents
    -- the native wasted flow, so restoring health is sufficient here; preserve
    -- the current seat instead of trying to resurrect onto the vehicle.
    local inVehicle = IsPedInAnyVehicle(ped, false)
    if not inVehicle then
        local coords = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
    end
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    if not inVehicle then ClearPedTasksImmediately(ped) end
    TriggerEvent('hospital:client:Revive')
    TriggerEvent('qbambulance:client:revived', 100)
end

RegisterNetEvent('qbadmin:client:revive', reviveLocalPed)

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

-- kora_lib entities are local and resource-tracked by design, which makes them
-- useful for admin/testing props and peds without turning this command into a
-- networked-world cleanup problem. Keep the one most recently spawned by this
-- client so the matching admin command can remove it explicitly.
local lastAdminEntity

RegisterNetEvent('qbadmin:client:spawnEntity', function(model)
    if type(model) ~= 'string' then return end

    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, Config.entity.spawnOffset, 0.0)
    -- The entities module owns model hashing, streaming, type detection, and
    -- creation. Vehicle commands are rejected server-side before this relay
    -- so they keep kora_admin's existing networked vehicle path.
    local entity, err = Kora.entities.create(model, {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = GetEntityHeading(ped),
    }, { preset = 'static' })

    if not entity then
        Kora.notify.send({ type = 'error', message = ('Could not spawn %s: %s'):format(model, err or 'unknown error') })
        return
    end

    lastAdminEntity = entity
    Kora.notify.send({ type = 'success', message = ('Spawned entity %s'):format(model) })
end)

RegisterNetEvent('qbadmin:client:deleteLastEntity', function()
    if not lastAdminEntity then
        Kora.notify.send({ type = 'error', message = 'No admin-spawned entity to delete' })
        return
    end

    local entity = lastAdminEntity
    lastAdminEntity = nil
    local removed, err = Kora.entities.remove(entity)
    if not removed then
        Kora.notify.send({ type = 'error', message = err or 'Could not delete the entity' })
        return
    end

    Kora.notify.send({ type = 'success', message = 'Deleted your last admin-spawned entity' })
end)

RegisterNetEvent('qbadmin:client:enterVehicle', function(netId, seat)
    CreateThread(function()
        local attempts = 0
        while not NetworkDoesEntityExistWithNetworkId(netId) and attempts < 50 do
            Wait(100)
            attempts = attempts + 1
        end
        if not NetworkDoesEntityExistWithNetworkId(netId) then return end
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if vehicle == 0 or not DoesEntityExist(vehicle) then return end
        SetVehicleHasBeenOwnedByPlayer(vehicle, true)
        SetVehicleNeedsToBeHotwired(vehicle, false)
        SetVehicleFuelLevel(vehicle, 100.0)
        SetVehicleDirtLevel(vehicle, 0.0)
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, seat or -1)
    end)
end)

-- Copies a coordinate string, always prints it to F8, and never raises: a failed
-- clipboard copy (no NUI focus, old kora_lib that rejects) only changes the notification.
local function copyCoords(text)
    print(text)
    local ok, result = pcall(Kora.nui.copyToClipboard, text)
    if ok and type(result) == 'table' and type(result.next) == 'function' then
        ok, result = pcall(Citizen.Await, result)
    end
    local copied = ok and result == true
    Kora.notify.send({
        type = copied and 'success' or 'error',
        message = copied and 'Copied' or 'Copy failed - coordinates printed to F8',
    })
    return copied
end

RegisterNetEvent('qbadmin:client:coords', function()
    local coords = GetEntityCoords(PlayerPedId())
    copyCoords(('vector3(%.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z))
end)

RegisterNetEvent('qbadmin:client:vec4', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    copyCoords(('vector4(%.2f, %.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z, heading))
end)

-- GTA health uses 100 as the death floor rather than as a 50% midpoint.
-- Convert the admin command's human-friendly percentage onto the current
-- ped's actual native range: freemode male peds normally top out at 200,
-- while freemode female peds normally top out at 175.
local HEALTH_FLOOR = 100

RegisterNetEvent('qbadmin:client:setHealth', function(value)
    local ped = PlayerPedId()
    local percentage = math.max(0, math.min(100, tonumber(value) or 100))

    -- SetEntityHealth alone does not clear GTA's internal death state, NOR
    -- whichever ambulance job's own death-loop tracking -- a dead ped stays
    -- stuck on the ragdoll/death screen (or the job's own forced animation)
    -- even once its raw health value reads above 0. Asking for non-zero
    -- health while dead has to actually revive first, the same way /revive
    -- does (reviveLocalPed, above), or the menu's health field would appear
    -- to do nothing.
    if percentage > 0 and IsPedDeadOrDying(ped, true) then
        reviveLocalPed()
    end

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

-- These native effects outlive a resource restart.  Reset only qbadmin-owned
-- overrides when this resource stops so an admin cannot be left frozen,
-- invisible, or invincible after its authoritative state table is cleared.
AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local ped = PlayerPedId()
    if ped == 0 then return end
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetEntityVisible(ped, true, false)
end)

-- Played alongside the /announce notification (Kora.notify has no sound of its own).
RegisterNetEvent('kora_admin:client:announceSound', function()
    local sound = Config.announcement.sound
    if not sound.enabled then return end
    Kora.sound.playFrontend(sound.name, sound.set)
end)
