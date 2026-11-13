-- Client launchers for kora_admin's Developer submenu. The corresponding server
-- commands authenticate every request before either event can be sent.

local function notify(kind, message)
    Kora.notify.send({
        title = Kora.lang('title.developer_tools'),
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
            notify('success', Kora.lang('success.developer_data_copied', label))
        else
            notify('info', Kora.lang('ui.developer_action_unavailable', label))
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
