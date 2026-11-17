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

-- Zone types the server accepts for /devzone (server/commands/development.lua).
local ZONE_LABELS = { box = 'ui.box_zone', sphere = 'ui.sphere_zone', poly = 'ui.poly_zone' }

RegisterNetEvent('kora_admin:client:startPlacement', function(model)
    runCreator(Kora.lang('ui.entity_placement'), function()
        return Kora.placement.start(model)
    end)
end)

RegisterNetEvent('kora_admin:client:startZoneCreator', function(zoneType)
    runCreator(ZONE_LABELS[zoneType] and Kora.lang(ZONE_LABELS[zoneType]) or tostring(zoneType), function()
        return Kora.zones.startCreator(zoneType)
    end)
end)
