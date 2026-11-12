local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 print(('  [PASS] %s'):format(name))
    else failed = failed + 1 print(('  [FAIL] %s -- %s'):format(name, tostring(err))) end
end
local function equal(a, e, m) if a ~= e then error(('%s (expected %s, got %s)'):format(m, tostring(e), tostring(a)), 2) end end

dofile('config.lua')

local commands, responses, logs, deleted = {}, {}, {}, {}
local world = {}      -- entity -> { x, y, z, plate, bucket, seats = {[seat]=ped} }
local playerVehicle = 0
local players = { [900] = true }

Kora = { commands = { add = function(name, _, args, required, handler, options)
    commands[name] = { arguments = args, required = required, handler = handler, options = options }
end } }
Admin = {
    checkLevel = function() return true end,
    respond = function(_, ok, message) responses[#responses + 1] = { ok = ok, message = message } end,
    log = function(_, action, _, details) logs[#logs + 1] = { action = action, details = details } end,
}
function GetPlayerPed() return 100 end
function GetPlayerRoutingBucket() return 0 end
function GetEntityRoutingBucket(e) return world[e].bucket or 0 end
function GetEntityCoords(e) if e == 100 then return { x = 0, y = 0, z = 0 } end return world[e] end
function GetVehiclePedIsIn() return playerVehicle end
function DoesEntityExist(e) return e == 100 or world[e] ~= nil end
function GetVehicleNumberPlateText(e) return world[e].plate end
function GetPedInVehicleSeat(e, seat) return world[e].seats and world[e].seats[seat] or 0 end
function IsPedAPlayer(p) return players[p] == true end
function GetAllVehicles() local l = {} for e in pairs(world) do l[#l + 1] = e end return l end
function DeleteEntity(e) deleted[#deleted + 1] = e world[e] = nil end

Admin.commands = {}
Admin.accessCommandAllowed = function() return true end
dofile('server/command_registry.lua')
dofile('server/commands/vehicle.lua')

local function reset(vehicles)
    world, deleted, responses, logs, playerVehicle = vehicles or {}, {}, {}, {}, 0
    Config.dv.nearestRadius, Config.dv.maxRadius = 5.0, 50.0
end
local function run(...) commands.dv.handler(7, { ... }) return responses[#responses] end

test('defaults keep nearest on and cap at 50', function()
    equal(Config.dv.nearestRadius, 5.0, 'nearest default')
    equal(Config.dv.maxRadius, 50.0, 'max default')
    equal(commands.dv.required, false, 'radius optional')
end)

test('on foot deletes the closest wreck within range, not farther ones', function()
    reset({ [1] = { x = 3, y = 0, z = 0, plate = 'NEAR' }, [2] = { x = 1, y = 1, z = 0, plate = 'NEARER' }, [3] = { x = 30, y = 0, z = 0, plate = 'FAR' } })
    local r = run()
    equal(r.ok, true, 'success')
    equal(#deleted, 1, 'one deleted')
    equal(deleted[1], 2, 'closest')
    equal(logs[1].details.plates, 'NEARER', 'logged plate')
end)

test('on foot with nothing in range fails', function()
    reset({ [1] = { x = 30, y = 0, z = 0, plate = 'FAR' } })
    equal(run().ok, false, 'fails')
    equal(#deleted, 0, 'nothing deleted')
end)

test('in a vehicle still deletes that vehicle', function()
    reset({ [5] = { x = 0, y = 0, z = 0, plate = 'MINE' }, [6] = { x = 1, y = 0, z = 0, plate = 'OTHER' } })
    playerVehicle = 5
    equal(run().ok, true, 'success')
    equal(deleted[1], 5, 'own vehicle')
    equal(#deleted, 1, 'only one')
end)

test('radius argument deletes all in range and is capped', function()
    reset({ [1] = { x = 8, y = 0, z = 0, plate = 'A' }, [2] = { x = 40, y = 0, z = 0, plate = 'B' }, [3] = { x = 49, y = 0, z = 0, plate = 'C' }, [4] = { x = 80, y = 0, z = 0, plate = 'D' } })
    local r = run('10')
    equal(#deleted, 1, 'radius 10 reaches one')
    reset({ [1] = { x = 8, y = 0, z = 0, plate = 'A' }, [2] = { x = 40, y = 0, z = 0, plate = 'B' }, [3] = { x = 49, y = 0, z = 0, plate = 'C' }, [4] = { x = 80, y = 0, z = 0, plate = 'D' } })
    run('9999')
    equal(#deleted, 3, 'capped at maxRadius 50')
    equal(logs[1].details.radius, 50.0, 'logged capped radius')
    equal(logs[1].details.count, 3, 'logged count')
end)

test('invalid radius is rejected', function()
    reset({ [1] = { x = 1, y = 0, z = 0, plate = 'A' } })
    equal(run('abc').ok, false, 'text')
    equal(run('-3').ok, false, 'negative')
    equal(run('0').ok, false, 'zero')
    equal(#deleted, 0, 'nothing deleted')
end)

test('vehicles with another player inside are skipped, other routing buckets ignored', function()
    reset({ [1] = { x = 1, y = 0, z = 0, plate = 'TAXI', seats = { [-1] = 900 } }, [2] = { x = 2, y = 0, z = 0, plate = 'WRECK' }, [3] = { x = 1, y = 0, z = 0, plate = 'OTHERBUCKET', bucket = 9 } })
    run()
    equal(deleted[1], 2, 'wreck deleted')
    equal(#deleted, 1, 'only wreck')
end)

test('nearestRadius = 0 restores in-vehicle-only behaviour', function()
    reset({ [1] = { x = 1, y = 0, z = 0, plate = 'A' } })
    Config.dv.nearestRadius = 0
    equal(run().ok, false, 'on foot fails')
    equal(run('10').ok, false, 'radius ignored')
    equal(#deleted, 0, 'nothing deleted')
    world[5] = { x = 0, y = 0, z = 0, plate = 'MINE' }
    playerVehicle = 5
    equal(run().ok, true, 'in vehicle works')
    equal(deleted[1], 5, 'own vehicle')
end)

print(('-- %d passed, %d failed --'):format(passed, failed))
if failed > 0 then os.exit(1) end
