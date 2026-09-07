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

QB = {
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

Admin = {
    checkLevel = function() return true end,
    respond = function(_, ok, message)
        responses[#responses + 1] = { ok = ok, message = message }
    end,
    log = function() end,
}

function GetPlayerPed() return 101 end
function GetEntityCoords() return { x = 10, y = 20, z = 30 } end
function GetEntityHeading() return 90 end
function GetPlayerRoutingBucket() return 0 end
function GetHashKey() return 123 end
function joaat() return 123 end
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
function DeleteEntity() error('the eventually ready vehicle must not be deleted') end
function TriggerClientEvent(name, target, ...)
    events[#events + 1] = { name = name, target = target, args = { ... } }
end

dofile('server/commands/vehicle.lua')

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
end)

print(('-- %d passed, %d failed --'):format(passed, failed))
if failed > 0 then os.exit(1) end
