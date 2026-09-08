-- Admin spectate -- the server only tells this client WHICH server id to
-- spectate (or nil to stop); the target's ped may not have streamed in yet on
-- this client, so entering spectator mode waits briefly rather than failing
-- immediately.

local spectating = nil

local function stop()
    if not spectating then return end
    NetworkSetInSpectatorMode(false, PlayerPedId())
    spectating = nil
    Admin.spectating = false
end

local function start(targetSrc)
    local targetPlayer = GetPlayerFromServerId(targetSrc)
    if targetPlayer == -1 then
        QB.notify.send({ title = 'Admin — Error', message = 'target is not visible to your client yet', type = 'error' })
        return
    end

    local ped = GetPlayerPed(targetPlayer)
    local waited = 0
    while not DoesEntityExist(ped) and waited < 3000 do
        Wait(100)
        waited = waited + 100
        ped = GetPlayerPed(targetPlayer)
    end
    if not DoesEntityExist(ped) then
        QB.notify.send({ title = 'Admin — Error', message = 'could not find target ped', type = 'error' })
        return
    end

    NetworkSetInSpectatorMode(true, ped)
    spectating = targetSrc
    Admin.spectating = true
end

RegisterNetEvent('qbadmin:client:spectate', function(targetSrc)
    if not targetSrc then
        stop()
        return
    end
    start(targetSrc)
    if Admin.refreshAppActionStates then Admin.refreshAppActionStates() end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then stop() end
end)
