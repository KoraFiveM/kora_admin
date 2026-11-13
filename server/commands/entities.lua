-- /entity, /entityfor, /deleteentity
--
-- kora_lib's entities module deliberately creates local, non-networked entities.
-- This command therefore asks the recipient client to create its own static
-- ped or prop after the server has authenticated and validated the request.
-- Networked vehicles continue through vehicle.lua instead.

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'kora_admin' }

local function validEntityModel(model)
    if type(model) ~= 'string' or not model:match('^[%w_]+$') then return nil end
    model = model:lower()

    local hash = joaat(model)
    if hash == 0 or hash == -1 then return nil end
    local record = Kora.lookup.model(hash)
    if not record then return nil end
    if record.namespace == 'vehicle' then return nil, Kora.lang('error.use_car_or_veh_for_vehicle') end
    return model
end

Admin.addCommand('entity', 'Spawn a static ped or prop in front of you', { { name = 'model' } }, true, function(source, args)
    local model, err = validEntityModel(args[1])
    if not model then return Admin.respond(source, false, err or Kora.lang('error.unknown_ped_prop')) end

    TriggerClientEvent('kora_admin:client:spawnEntity', source, model)
    Admin.log(source, 'entity', nil, { model = model })
    Admin.respond(source, true, Kora.lang('success.success_spawning_s', model))
end, OPTS_ADMIN)

Admin.addCommand('entityfor', 'Spawn a static ped or prop for a player', { { name = 'id' }, { name = 'model' } }, true, function(source, args)
    local targetSrc, data, targetErr = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, targetErr) end

    local model, err = validEntityModel(args[2])
    if not model then return Admin.respond(source, false, err or Kora.lang('error.unknown_ped_prop')) end

    TriggerClientEvent('kora_admin:client:spawnEntity', targetSrc, model)
    Admin.log(source, 'entityfor', data, { model = model })
    Admin.respond(source, true, Kora.lang('success.success_spawning_s_for_s', model, data.name))
end, OPTS_ADMIN)

Admin.addCommand('deleteentity', 'Delete your last admin-spawned entity', nil, false, function(source)
    TriggerClientEvent('kora_admin:client:deleteLastEntity', source)
    Admin.log(source, 'deleteentity')
    Admin.respond(source, true, Kora.lang('success.deleting_your_last_admin_spawned_entity'))
end, OPTS_ADMIN)
