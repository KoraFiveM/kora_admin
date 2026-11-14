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

-- Runs one noclip session: holds `keys` (control ids) for `opts.frames` frames
-- (default 1) with the camera at `heading` degrees, and reports where the mover
-- ended up, the heading it was given and what was done to the camera.
-- `opts.camDrift(frame)` returns how far the follow camera swings by itself.
local function run(opts)
    local held, disabled, setCoords, camHeading, entityHeading = {}, {}, nil, nil, nil
    local relativeResets, camZ, frame = 0, opts.heading, 0
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
    Wait = function()
        frames = frames + 1
        frame = frames
        if frames >= (opts.frames or 1) then handler() end
    end
    -- The follow camera sits behind the ped's heading plus any self-drift.
    GetGameplayCamRot = function()
        local drift = opts.camDrift and opts.camDrift(frame) or 0.0
        return { x = 0.0, y = 0.0, z = camZ + drift }
    end
    GetDisabledControlNormal = function(_, key) return (opts.look and key == 1) and opts.look or 0.0 end
    GetEntityCoords = function() return { x = 0.0, y = 0.0, z = 0.0 } end
    IsControlPressed = function(_, key) return held[key] == true end
    IsDisabledControlPressed = IsControlPressed
    DisableControlAction = function(_, key) disabled[key] = true end
    SetEntityCoordsNoOffset = function(entity, x, y, z) setCoords = { entity = entity, x = x, y = y, z = z } end
    SetEntityHeading = function(_, h) entityHeading = h; camZ = h end
    SetGameplayCamRelativeHeading = function(delta)
        if delta == 0.0 then relativeResets = relativeResets + 1 else camHeading = (camHeading or 0) + delta end
    end
    DoesEntityExist = function() return true end
    FreezeEntityPosition, SetEntityCollision, SetEntityInvincible, SetEntityVisible = function() end, function() end, function() end, function() end

    dofile('client/noclip.lua')
    handler() -- enable
    thread()  -- one frame, then Wait toggles it off
    return { coords = setCoords, camHeading = camHeading, disabled = disabled, heading = entityHeading, relativeResets = relativeResets }
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
    equal(near(r.heading, 360.0 - Config.noclip.turnSpeed), true, 'D turns the view right')
    r = run({ mode = 'turn', heading = 0.0, keys = { 34 } })
    equal(near(r.heading, Config.noclip.turnSpeed), true, 'A turns the view left')
    equal(r.camHeading, nil, 'the camera is never offset from behind the mover')
end)

test('mouse look turns the mover and the camera is pinned behind it', function()
    local r = run({ mode = 'strafe', heading = 90.0, keys = {}, look = 1.0 })
    equal(near(r.heading, 90.0 - Config.noclip.lookSpeed), true, 'looking right lowers the heading')
    equal(r.relativeResets, 1, 'camera relative heading reset every frame')
    equal(r.disabled[1], true, 'native horizontal look is blocked so it cannot double-apply')
end)

test('holding S is unaffected by the follow camera swinging on its own (#21)', function()
    -- The old loop copied the camera heading onto the ped every frame, so a
    -- camera that swings while the ped backs towards it dragged the ped round.
    local r = run({ mode = 'strafe', heading = 0.0, keys = { 33 }, frames = 120,
        camDrift = function(f) return f > 0 and 3.0 or 0.0 end }) -- swings 3 degrees a frame once moving
    equal(near(r.heading, 0.0), true, 'heading holds steady without look input')
    equal(near(r.coords.x, 0.0), true, 'S moves straight back, no sideways drift')
    equal(near(r.coords.y, -Config.noclip.baseSpeed), true, 'S moves straight back')
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
