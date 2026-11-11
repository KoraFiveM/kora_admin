-- Client launchers for kora_admin's Developer submenu. The corresponding server
-- commands authenticate every request before either event can be sent.

local function notify(kind, message)
    Kora.notify.send({
        title = 'Developer tools',
        type = kind,
        message = message,
    })
end

local function runCreator(label, create)
    CreateThread(function()
        local ok, result = pcall(create)
        if not ok then
            notify('error', tostring(result))
        elseif result then
            notify('success', ('%s data copied'):format(label))
        else
            notify('info', ('%s cancelled or unavailable'):format(label))
        end
    end)
end

RegisterNetEvent('kora_admin:client:startPlacement', function(model)
    runCreator('Entity placement', function()
        return Kora.placement.start(model)
    end)
end)

RegisterNetEvent('kora_admin:client:startZoneCreator', function(zoneType)
    runCreator(('%s zone'):format(zoneType), function()
        return Kora.zones.startCreator(zoneType)
    end)
end)
