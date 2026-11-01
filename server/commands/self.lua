-- /aduty, /coords, /health, /armor, /permission -- all act on the caller
-- unless noted; Kora.nui.copyToClipboard is client-realm only (kora_lib's entire
-- nui module has no server.lua), so /coords relays to the caller's own client
-- rather than doing anything server-side itself.

local OPTS_MOD = { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'kora_admin' }

Admin.addCommand('aduty', 'Toggle admin on-duty status', nil, false, function(source)
    local state = not exports.kora_core:getMetaData(source, 'adminDuty')
    exports.kora_core:setMetaData(source, 'adminDuty', state)
    Admin.respond(source, true, ('Admin duty %s'):format(state and 'enabled' or 'disabled'))
end, OPTS_MOD)

Admin.addCommand('coords', 'Copy your current coordinates to the clipboard', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:coords', source)
end, OPTS_MOD)

Admin.addCommand('vec4', 'Copy your current vector4 coordinates to the clipboard', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:vec4', source)
end, OPTS_MOD)

Admin.addCommand('health', 'Set your own health percentage (0-100, default: 100)', { { name = 'percentage' } }, false, function(source, args)
    TriggerClientEvent('qbadmin:client:setHealth', source, tonumber(args[1]))
end, OPTS_MOD)

Admin.addCommand('armor', 'Set your own armor (default: full)', { { name = 'value' } }, false, function(source, args)
    TriggerClientEvent('qbadmin:client:setArmor', source, tonumber(args[1]))
end, OPTS_MOD)

-- Deliberately named 'selfrevive', not 'revive' -- the existing targeted
-- /revive (server/commands/moderation.lua) already collides with real
-- qb-ambulancejob's own '/revive' command (both register through the same
-- kora_lib command table with no collision detection; load order in server.cfg
-- currently makes qb-ambulancejob's win). A distinct name here means this
-- command can never be shadowed by either ambulance resource, now or if one
-- adds its own '/revive' in the future.
Admin.addCommand('selfrevive', 'Revive yourself, clearing whichever ambulance job is running', nil, false, function(source)
    exports.kora_core:setMetaData(source, 'isdead', false)
    exports.kora_core:setMetaData(source, 'inlaststand', false)
    TriggerClientEvent('qbadmin:client:revive', source)
    Admin.fullReviveAmbulance(source)
    Admin.respond(source, true, 'Revived')
end, OPTS_MOD)

Admin.addCommand('permission', "Show a player's permission level", { { name = 'id' } }, false, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end
    if targetSrc ~= source and not Admin.checkLevel(source, 'admin') then
        return Admin.respond(source, false, "admin level required to check another player's permission")
    end

    Admin.respond(source, true, ('%s: %s'):format(data.name, Admin.getLevel(targetSrc)))
end, OPTS_MOD)
