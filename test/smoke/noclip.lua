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

-- Runs one noclip session: holds `keys` (control ids) for one frame with the
-- camera at `heading` degrees, and reports where the mover ended up.
local function run(opts)
    local held, disabled, setCoords, camHeading = {}, {}, nil, nil
    for _, key in ipairs(opts.keys) do held[key] = true end
    local handler, thread, cacheHandlers = nil, nil, {}

    Admin = {}
    Config.noclip.adMode = opts.mode
    Kora = {
        cache = {
            ped = function() return 100 end,
            vehicle = function() return opts.vehicle or false end,
            onChange = function(key, fn) cacheHandlers[key] = fn end,
        },
        nui = { send = function() end },
    }
    RegisterNetEvent = function(_, fn) handler = fn end
    AddEventHandler = function() end
    GetCurrentResourceName = function() return 'kora_admin' end
    CreateThread = function(fn) thread = fn end
    local frames = 0
    Wait = function() frames = frames + 1; if frames >= 1 then handler() end end
    GetGameplayCamRot = function() return { x = 0.0, y = 0.0, z = opts.heading } end
    GetEntityCoords = function() return { x = 0.0, y = 0.0, z = 0.0 } end
    IsControlPressed = function(_, key) return held[key] == true end
    IsDisabledControlPressed = IsControlPressed
    DisableControlAction = function(_, key) disabled[key] = true end
    SetEntityCoordsNoOffset = function(entity, x, y, z) setCoords = { entity = entity, x = x, y = y, z = z } end
    SetEntityHeading = function() end
    SetGameplayCamRelativeHeading = function(delta) camHeading = (camHeading or 0) + delta end
    DoesEntityExist = function() return true end
    FreezeEntityPosition, SetEntityCollision, SetEntityInvincible, SetEntityVisible = function() end, function() end, function() end, function() end

    dofile('client/noclip.lua')
    handler() -- enable
    thread()  -- one frame, then Wait toggles it off
    return { coords = setCoords, camHeading = camHeading, disabled = disabled }
end

local function near(a, b) return math.abs(a - b) < 1e-6 end

test('strafe mode: D moves along the camera right vector and never turns the view', function()
    local r = run({ mode = 'strafe', heading = 0.0, keys = { 35 } })
    equal(near(r.coords.x, Config.noclip.baseSpeed), true, 'D at heading 0 should move +x')
    equal(near(r.coords.y, 0.0), true, 'D should not move forward')
    equal(r.camHeading, nil, 'strafe mode must not turn the view')
end)

test('strafe mode: A is relative to the camera heading', function()
    local r = run({ mode = 'strafe', heading = 90.0, keys = { 34 } })
    equal(near(r.coords.x, 0.0), true, 'A at heading 90 has no x component')
    equal(near(r.coords.y, -Config.noclip.baseSpeed), true, 'A at heading 90 should move -y')
end)

test('turn mode: A/D turn the view and do not translate', function()
    local r = run({ mode = 'turn', heading = 0.0, keys = { 35 } })
    equal(r.coords, nil, 'turn mode must not strafe')
    equal(r.camHeading, -Config.noclip.turnSpeed, 'D turns the view right')
    r = run({ mode = 'turn', heading = 0.0, keys = { 34 } })
    equal(r.camHeading, Config.noclip.turnSpeed, 'A turns the view left')
end)

test('native move and steer controls are blocked so the game cannot turn the ped', function()
    local r = run({ mode = 'strafe', heading = 0.0, keys = {} })
    for _, key in ipairs({ 30, 34, 35, 63, 64 }) do equal(r.disabled[key], true, 'control ' .. key .. ' should be blocked') end
end)

test('in a vehicle the vehicle is what moves, with the same A/D behaviour', function()
    local r = run({ mode = 'strafe', heading = 0.0, keys = { 35 }, vehicle = 200 })
    equal(r.coords.entity, 200, 'the vehicle should be translated')
    equal(near(r.coords.x, Config.noclip.baseSpeed), true, 'D should strafe in a vehicle too')
    r = run({ mode = 'turn', heading = 0.0, keys = { 35 }, vehicle = 200 })
    equal(r.coords, nil, 'turn mode should not strafe in a vehicle')
end)

test('adMode defaults to strafe and an unknown value falls back to strafe', function()
    dofile('config.lua')
    equal(Config.noclip.adMode, 'strafe', 'default')
    local r = run({ mode = 'bogus', heading = 0.0, keys = { 35 } })
    equal(near(r.coords.x, Config.noclip.baseSpeed), true, 'unknown mode strafes')
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
