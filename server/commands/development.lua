-- /devplacement, /devzone -- permission-checked entry points for the kora_lib
-- data-capture creators exposed in kora_admin's Developer submenu. Both tools
-- remain client-local and never persist an entity or register a live zone.

local OPTS_DEVELOPER = {
    permission = Config.developer.menuLevel,
    checkPermission = Admin.checkLevel,
    resource = 'kora_admin',
}

local ZONE_TYPES = { box = true, sphere = true, poly = true }

local function developmentReady(source)
    if not Config.developer.requireDevMode then return true end
    if exports.kora_core:isDevMode(source) then return true end

    Admin.respond(source, false, 'enable qbcore development mode before using creator tools')
    return false
end

Admin.addCommand('entitypicker', 'Inspect the entity you are aiming at and copy its model name', nil, true, function(source)
    if not developmentReady(source) then return end

    TriggerClientEvent('qbadmin:client:startEntityPicker', source)
    Admin.log(source, 'entitypicker')
end, OPTS_DEVELOPER)

Admin.addCommand('devplacement', 'Open qblib entity placement for a model', {
    { name = 'model', help = 'model name or numeric hash' },
}, true, function(source, args)
    if not developmentReady(source) then return end

    local model = args[1]
    if type(model) ~= 'string' or model == '' or not model:match('^[%w_%-]+$') then
        return Admin.respond(source, false, 'model must be a model name or numeric hash')
    end

    if model:match('^%-?%d+$') then model = tonumber(model) end
    TriggerClientEvent('qbadmin:client:startPlacement', source, model)
    Admin.log(source, 'devplacement', nil, { model = model })
end, OPTS_DEVELOPER)

Admin.addCommand('devzone', 'Open qblib zone creator (box, sphere, or poly)', {
    { name = 'type', help = 'box, sphere, or poly' },
}, true, function(source, args)
    if not developmentReady(source) then return end

    local zoneType = type(args[1]) == 'string' and args[1]:lower() or nil
    if not zoneType or not ZONE_TYPES[zoneType] then
        return Admin.respond(source, false, 'zone type must be box, sphere, or poly')
    end

    TriggerClientEvent('qbadmin:client:startZoneCreator', source, zoneType)
    Admin.log(source, 'devzone', nil, { type = zoneType })
end, OPTS_DEVELOPER)
