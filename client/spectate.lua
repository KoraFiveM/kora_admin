-- Admin spectate -- the server only tells this client WHICH server id to
-- spectate (or nil to stop); the target's ped may not have streamed in yet on
-- this client, so entering spectator mode waits briefly rather than failing
-- immediately.

local spectating = nil
local hint = nil

local function stop()
    if not spectating then return end
    NetworkSetInSpectatorMode(false, PlayerPedId())
    spectating = nil
    Admin.spectating = false
    if hint then Kora.textui.hide(hint); hint = nil end
    if Admin.refreshAppActionStates then Admin.refreshAppActionStates() end
end

local function start(targetSrc)
    local targetPlayer = GetPlayerFromServerId(targetSrc)
    if targetPlayer == -1 then
        Kora.notify.send({ title = Kora.lang('title.error'), message = Kora.lang('error.target_not_visible'), type = 'error' })
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
        Kora.notify.send({ title = Kora.lang('title.error'), message = Kora.lang('error.target_ped_missing'), type = 'error' })
        return
    end

    NetworkSetInSpectatorMode(true, ped)
    spectating = targetSrc
    Admin.spectating = true
    if Config.spectate.showHint and not hint then
        hint = Kora.textui.show('Stop spectating', { key = Config.spectate.stopKey ~= '' and Config.spectate.stopKey or nil, icon = 'eye-off' })
    end
end

RegisterNetEvent('kora_admin:client:spectate', function(targetSrc)
    if not targetSrc then
        stop()
        return
    end
    -- Selecting Spectate on the player already being spectated toggles it off.
    if spectating == targetSrc then
        stop()
        Kora.notify.send({ title = Kora.lang('title.admin'), message = Kora.lang('success.spectating_stopped'), type = 'info' })
        return
    end
    start(targetSrc)
    if Admin.refreshAppActionStates then Admin.refreshAppActionStates() end
end)

Kora.keybind.add({
    name = 'kora_admin_spectate_stop',
    description = Kora.lang('ui.stop_spectating'),
    defaultMapper = 'keyboard',
    defaultKey = Config.spectate.stopKey,
    onPressed = function()
        if not spectating then return end
        stop()
        Kora.notify.send({ title = Kora.lang('title.admin'), message = Kora.lang('success.spectating_stopped'), type = 'info' })
    end,
})

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then stop() end
end)
