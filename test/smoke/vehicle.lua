local passed, failed = 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print(('  [PASS] %s'):format(name))
    else
        failed = failed + 1
        print(('  [FAIL] %s -- %s'):format(name, tostring(err)))
    end
end

local function equal(actual, expected, message)
    if actual ~= expected then error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)), 2) end
end

dofile('config.lua')

local commands = {}
local responses = {}
local events = {}
local existenceChecks = 0
local networkChecks = 0
local waits = 0
local grantedKeys = {}
local createdVehicles = {}

Kora = {
    lookup = {
        vehicle = function(hash) return hash == 123 and {} or nil end,
        model = function(hash)
            if hash == 123 then return { namespace = 'vehicle' } end
            if hash == 456 then return { namespace = 'ped' } end
        end,
    },
    commands = {
        add = function(name, description, arguments, required, handler, options)
            commands[name] = {
                description = description, arguments = arguments, required = required,
                handler = handler, options = options,
            }
        end,
    },
    shared = {
        get = function(kind, model)
            return kind == 'vehicles' and model == 'adder' and { model = model } or nil
        end,
    },
}

exports = {
    kora_core = {
        createVehicle = function(_, citizenid, model, plate, job)
            createdVehicles[#createdVehicles + 1] = {
                citizenid = citizenid, model = model, plate = plate, job = job,
            }
            return true
        end,
    },
    kora_vehiclekeys = {
        giveKeys = function(_, target, plate, override)
            grantedKeys[#grantedKeys + 1] = { target = target, plate = plate, override = override }
            return true
        end,
    },
}

Admin = {
    checkLevel = function() return true end,
    respond = function(_, ok, message)
        responses[#responses + 1] = { ok = ok, message = message }
    end,
    log = function() end,
    resolveTarget = function(_, id)
        return tonumber(id), { name = 'Target', citizenid = 'CID123' }
    end,
}

function GetPlayerPed() return 101 end
function GetEntityCoords() return { x = 10, y = 20, z = 30 } end
function GetEntityHeading() return 90 end
function GetPlayerRoutingBucket() return 0 end
function GetHashKey() return 123 end
function joaat(model)
    if model == 'ped_model' then return 456 end
    if model == 'invalid_model' then return 789 end
    return 123
end
IsModelInCdimage, IsModelAVehicle = nil, nil
function CreateVehicle() return 201 end
function DoesEntityExist()
    existenceChecks = existenceChecks + 1
    return existenceChecks >= 3
end
function Wait()
    waits = waits + 1
end
function SetEntityRoutingBucket() end
function NetworkGetNetworkIdFromEntity()
    networkChecks = networkChecks + 1
    return networkChecks >= 3 and 301 or 0
end
function GetVehicleNumberPlateText() return 'ADMIN 1' end
function GetVehiclePedIsIn() return 201 end
function GetPedInVehicleSeat() return 101 end
function DeleteEntity() error('the eventually ready vehicle must not be deleted') end
function TriggerClientEvent(name, target, ...)
    events[#events + 1] = { name = name, target = target, args = { ... } }
end

dofile('server/command_registry.lua')
dofile('server/commands/vehicle.lua')
dofile('server/commands/entities.lua')

test('car waits for server entity and network registration before succeeding', function()
    equal(commands.car.required, true, '/car should require a model')
    equal(commands.car.arguments[1].name, 'model', '/car model argument')
    equal(commands.car.options.permission, 'admin', '/car permission')
    commands.car.handler(7, { 'adder' })

    equal(waits, 4, 'the command should wait for both readiness stages')
    equal(responses[#responses].ok, true, 'a spawned vehicle must report success')
    equal(responses[#responses].message, 'Spawned adder', 'success message')
    equal(events[#events].name, 'qbadmin:client:enterVehicle', 'warp event')
    equal(events[#events].target, 7, 'warp target')
    equal(events[#events].args[1], 301, 'registered network id')
    equal(grantedKeys[#grantedKeys].target, 7, 'spawn recipient receives the keys')
    equal(grantedKeys[#grantedKeys].plate, 'ADMIN 1', 'spawned vehicle plate is granted')
    equal(grantedKeys[#grantedKeys].override, true, 'admin grants work when ordinary temporary keys are disabled')
end)

test('givekeys grants the driver keys to their current vehicle', function()
    commands.givekeys.handler(7, { '7' })

    equal(commands.givekeys.options.permission, 'admin', '/givekeys permission')
    equal(responses[#responses].ok, true, 'key grant must report success')
    equal(grantedKeys[#grantedKeys].target, 7, 'driver receives the keys')
end)

test('givevehicle creates a persistent personal garage vehicle', function()
    commands.givevehicle.handler(7, { '12', 'adder', 'staff01' })

    equal(commands.givevehicle.options.permission, 'admin', '/givevehicle permission')
    equal(createdVehicles[#createdVehicles].citizenid, 'CID123', 'vehicle owner')
    equal(createdVehicles[#createdVehicles].model, 'adder', 'vehicle model')
    equal(createdVehicles[#createdVehicles].plate, 'STAFF01', 'normalised plate')
    equal(createdVehicles[#createdVehicles].job, nil, 'personal vehicles have no job owner')
    equal(responses[#responses].ok, true, 'persistent grant must report success')
end)

test('givevehicle rejects invalid plates before persistence', function()
    local createdBefore = #createdVehicles
    commands.givevehicle.handler(7, { '12', 'adder', 'BAD-PLATE' })

    equal(#createdVehicles, createdBefore, 'invalid plate must not reach persistence')
    equal(responses[#responses].ok, false, 'invalid plate must report failure')
end)

test('model lookup supports addon vehicles and rejects unknown models', function()
    commands.givevehicle.handler(7, { '12', 'addon_car', 'ADDON1' })
    equal(responses[#responses].ok, true, 'addon model succeeds without client natives')
    equal(createdVehicles[#createdVehicles].model, 'addon_car', 'addon model is retained')
    local before = #createdVehicles
    commands.givevehicle.handler(7, { '12', 'invalid_model', 'BAD1' })
    equal(responses[#responses].ok, false, 'unknown models fail')
    equal(#createdVehicles, before, 'unknown models are not persisted')
    commands.entity.handler(7, { 'ped_model' })
    equal(responses[#responses].ok, true, 'ped models are supported')
    equal(events[#events].name, 'qbadmin:client:spawnEntity', 'entity creation stays on the recipient')
    commands.entity.handler(7, { 'addon_car' })
    equal(responses[#responses].ok, false, 'vehicle models use vehicle commands')
    commands.entity.handler(7, { 'invalid_model' })
    equal(responses[#responses].ok, false, 'unknown entity models fail')
end)

print(('-- %d passed, %d failed --'):format(passed, failed))
if failed > 0 then os.exit(1) end
