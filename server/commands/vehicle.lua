-- /car, /veh, /dv, /fix
--
-- Neither QB.entities.create (qblib, explicitly local/non-networked) nor any
-- other export spawns a vehicle other clients can see -- this is genuinely new
-- code, not reuse. Server-side CreateVehicle(..., isNetwork=true, ...)
-- produces a properly networked entity on modern FXServer artifacts with no
-- manual NetworkRegisterEntityAsNetworked dance needed; if the deployed
-- artifact predates server-side vehicle creation this needs a client-relay
-- fallback instead (server resolves model/coords only, target client creates
-- + registers as networked) -- flagged in docs.md, not silently assumed.

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'qbadmin' }
local OPTS_MOD = { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'qbadmin' }

---@param model string
---@param coords vector3
---@param heading number|nil
---@return integer|nil vehicle
---@return string|nil err
local function spawnVehicle(model, coords, heading)
    local hash = GetHashKey(model)
    if hash == 0 or hash == -1 or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return nil, 'unknown vehicle model'
    end
    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, heading or 0.0, true, false)
    if not veh or veh == 0 then return nil, 'failed to spawn vehicle' end
    return veh
end

QB.commands.add('car', 'Spawn a vehicle and get in', { { name = 'model' } }, true, function(source, args)
    local model = args[1]
    if not model then return Admin.respond(source, false, 'vehicle model required') end

    local ped = GetPlayerPed(source)
    local veh, err = spawnVehicle(model, GetEntityCoords(ped), GetEntityHeading(ped))
    if not veh then return Admin.respond(source, false, err) end

    TriggerClientEvent('qbadmin:client:enterVehicle', source, NetworkGetNetworkIdFromEntity(veh), -1)
    Admin.log(source, 'car', nil, { model = model })
    Admin.respond(source, true, ('Spawned %s'):format(model))
end, OPTS_ADMIN)

QB.commands.add('veh', 'Spawn a vehicle for a player', { { name = 'id' }, { name = 'model' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    local model = args[2]
    if not model then return Admin.respond(source, false, 'vehicle model required') end

    local ped = GetPlayerPed(targetSrc)
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, Config.vehicle.spawnOffset, 0.0)
    local veh, spawnErr = spawnVehicle(model, coords, GetEntityHeading(ped))
    if not veh then return Admin.respond(source, false, spawnErr) end

    TriggerClientEvent('qbadmin:client:enterVehicle', targetSrc, NetworkGetNetworkIdFromEntity(veh), -1)
    Admin.log(source, 'veh', data, { model = model })
    Admin.respond(source, true, ('Spawned %s for %s'):format(model, data.name))
end, OPTS_ADMIN)

QB.commands.add('dv', 'Delete the vehicle you are in', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:deleteVehicle', source)
    Admin.log(source, 'dv')
    Admin.respond(source, true, 'Deleted your current vehicle')
end, OPTS_ADMIN)

QB.commands.add('fix', 'Repair the vehicle you are in', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:fix', source)
    Admin.log(source, 'fix')
    Admin.respond(source, true, 'Repaired your current vehicle')
end, OPTS_MOD)
