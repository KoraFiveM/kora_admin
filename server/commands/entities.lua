-- /entity, /entityfor, /deleteentity
--
-- qblib's entities module deliberately creates local, non-networked entities.
-- This command therefore asks the recipient client to create its own static
-- ped or prop after the server has authenticated and validated the request.
-- Networked vehicles continue through vehicle.lua instead.

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'qbadmin' }

local function validEntityModel(model)
    if type(model) ~= 'string' or not model:match('^[%w_]+$') then return nil end
    model = model:lower()

    local hash = joaat(model)
    if hash == 0 or hash == -1 or not IsModelInCdimage(hash) then return nil end
    if IsModelAVehicle(hash) then return nil, 'use /car or /veh for vehicle models' end
    return model
end

QB.commands.add('entity', 'Spawn a static ped or prop in front of you', { { name = 'model' } }, true, function(source, args)
    local model, err = validEntityModel(args[1])
    if not model then return Admin.respond(source, false, err or 'unknown ped or prop model') end

    TriggerClientEvent('qbadmin:client:spawnEntity', source, model)
    Admin.log(source, 'entity', nil, { model = model })
    Admin.respond(source, true, ('Spawning %s'):format(model))
end, OPTS_ADMIN)

QB.commands.add('entityfor', 'Spawn a static ped or prop for a player', { { name = 'id' }, { name = 'model' } }, true, function(source, args)
    local targetSrc, data, targetErr = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, targetErr) end

    local model, err = validEntityModel(args[2])
    if not model then return Admin.respond(source, false, err or 'unknown ped or prop model') end

    TriggerClientEvent('qbadmin:client:spawnEntity', targetSrc, model)
    Admin.log(source, 'entityfor', data, { model = model })
    Admin.respond(source, true, ('Spawning %s for %s'):format(model, data.name))
end, OPTS_ADMIN)

QB.commands.add('deleteentity', 'Delete your last admin-spawned entity', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:deleteLastEntity', source)
    Admin.log(source, 'deleteentity')
    Admin.respond(source, true, 'Deleting your last admin-spawned entity')
end, OPTS_ADMIN)
