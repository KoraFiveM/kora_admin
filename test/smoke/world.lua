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
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(value, message)
    if not value then error(message, 2) end
end

dofile('config.lua')

-- The /time clock, with the real Admin.finiteNumber from server/core.lua
-- rather than a stub: the point of these tests is that the SERVER refuses a
-- bad hour/minute or an unknown preset word, so the validator under test has
-- to be the one the command actually calls.
local commands = {}
local responses = {}
local clientEvents = {}
local logs = {}

QB = {
    commands = {
        add = function(name, _, _, _, handler, options)
            commands[name] = { handler = handler, options = options }
        end,
    },
}
function AddEventHandler() end
function RegisterNetEvent() end
function TriggerClientEvent(name, target, ...)
    clientEvents[#clientEvents + 1] = { name = name, target = target, args = { ... } }
end

dofile('server/core.lua')
Admin.checkLevel = function() return true end
Admin.respond = function(source, ok, message)
    responses[#responses + 1] = { source = source, ok = ok, message = message }
end
Admin.log = function(source, action, _, details)
    logs[#logs + 1] = { source = source, action = action, details = details }
end

dofile('server/commands/world.lua')

---Runs /time with the given args and reports the applied clock (nil when the
---command refused, in which case nothing may have reached a client).
local function setTime(...)
    local events, refusals = #clientEvents, #responses
    commands.time.handler(7, { ... })
    if #clientEvents == events then
        truthy(#responses > refusals and not responses[#responses].ok,
            'a refused /time must notify the caller with a reason')
        return nil
    end
    local event = clientEvents[#clientEvents]
    equal(event.name, 'qbadmin:client:setTime', 'clock event')
    equal(event.target, -1, 'the clock is server-wide, so every client gets it')
    return event.args[1], event.args[2]
end

local function refused(...)
    local hour = setTime(...)
    equal(hour, nil, 'this input should have been refused')
    return responses[#responses].message
end

test('every configured preset resolves to its own hour and minute', function()
    truthy(#Config.world.timePresets > 0, 'config should ship presets')
    for _, preset in ipairs(Config.world.timePresets) do
        local hour, minute = setTime(preset.id)
        equal(hour, preset.hour, ('%s hour'):format(preset.id))
        equal(minute, preset.minute or 0, ('%s minute'):format(preset.id))
        equal(logs[#logs].details.preset, preset.id, 'the preset word should be audited, not just its hour')
    end
end)

test('preset names are matched case-insensitively', function()
    local first = Config.world.timePresets[1]
    local hour = setTime(first.id:upper())
    equal(hour, first.hour, 'an upper-cased preset is the same preset')
end)

test('an unknown preset is refused and names the real ones', function()
    local message = refused('midnight')
    truthy(message:find(Config.world.timePresets[1].id, 1, true),
        'the refusal should list the configured preset words')
end)

test('out-of-range and non-integer clock values are refused, never clamped', function()
    refused('24')
    refused('-1')
    refused('12', '60')
    refused('12', '-1')
    refused('12.5')
    refused('12', '30.5')
    refused('lunchtime')
    refused('')
    refused(nil)
end)

test('a valid custom hour and minute still applies', function()
    local hour, minute = setTime('3', '45')
    equal(hour, 3, 'custom hour')
    equal(minute, 45, 'custom minute')
    equal(logs[#logs].details.preset, nil, 'a typed clock has no preset to audit')

    hour, minute = setTime('0')
    equal(hour, 0, 'hour 0 is valid')
    equal(minute, 0, 'an omitted minute defaults to 0')

    hour, minute = setTime('23', '59')
    equal(hour, 23, 'hour 23 is valid')
    equal(minute, 59, 'minute 59 is valid')
end)

-- The menu's own time selector: presets are one click, and the hour/minute
-- inputs exist only on the Custom path.
local netEvents = {}
local menuPayload
local selectorResult = { cancelled = true }
local inputFields
local inputResult = { cancelled = true }
local executedCommand
local clockHour, clockMinute = 8, 0

QB = {
    notify = { send = function() end },
    cache = {
        serverId = function() return 7 end,
        vehicle = function() return false end,
    },
    callback = { trigger = function() return {} end },
    shared = {
        all = function() return {} end,
        get = function() return nil end,
    },
    nui = {
        -- The root menu and the time selector share this one mock: the first
        -- call is the root (answered with World / Server -> Set Time so the
        -- selector opens at all), the second is the selector itself.
        openMenu = function(items, title)
            menuPayload = { items = items, title = title }
            if title == 'Admin Menu' then return { path = { 'world' }, selectedId = 'time' } end
            return selectorResult
        end,
        openInputDialog = function(fields)
            inputFields = fields
            return inputResult
        end,
        openAlert = function() return { confirmed = false } end,
    },
}
exports = { qbcore = { isDevMode = function() return false end } }
Admin = nil
function RegisterNetEvent(name, callback)
    if callback then netEvents[name] = callback end
end
function CreateThread(fn) fn() end
function TriggerServerEvent() end
function ExecuteCommand(command) executedCommand = command end
function GetActivePlayers() return {} end
function GetResourceState() return 'missing' end
function GetClockHours() return clockHour end
function GetClockMinutes() return clockMinute end

dofile('client/core.lua')
Admin.level = 'god'
dofile('client/development.lua')
dofile('client/menu.lua')

---Opens the root menu, drills into World / Server -> Set Time, answers the
---selector with `answer`, and returns the selector's own menu payload.
local function openTimeSelector(answer)
    executedCommand, inputFields, menuPayload = nil, nil, nil
    selectorResult = answer or { cancelled = true }
    netEvents['qbadmin:client:openMenu']('god')
    return menuPayload
end

test('the selector offers one button per configured preset plus Custom', function()
    clockHour, clockMinute = 8, 0
    local selector = openTimeSelector()
    equal(#selector.items, #Config.world.timePresets + 1, 'preset buttons plus Custom')
    for index, preset in ipairs(Config.world.timePresets) do
        equal(selector.items[index].id, preset.id, ('button %d id'):format(index))
        equal(selector.items[index].label, preset.label, ('button %d label'):format(index))
    end
    equal(selector.items[#selector.items].id, 'custom', 'Custom is offered last')
    equal(executedCommand, nil, 'cancelling the selector must not touch the clock')
end)

test('the selector shows the live clock and marks the preset already applied', function()
    local applied = Config.world.timePresets[#Config.world.timePresets]
    clockHour, clockMinute = applied.hour, applied.minute or 0
    local selector = openTimeSelector()
    truthy(selector.title:find(('%02d:%02d'):format(clockHour, clockMinute), 1, true),
        'the title should show the current clock')
    local marked
    for _, item in ipairs(selector.items) do
        if item.description and item.description:find('current', 1, true) then marked = item.id end
    end
    equal(marked, applied.id, 'the preset matching the current clock should say so')

    -- Any minute no preset uses, so nothing can legitimately be current.
    clockHour, clockMinute = applied.hour, 37
    selector = openTimeSelector()
    for _, item in ipairs(selector.items) do
        truthy(not (item.description and item.description:find('current', 1, true)),
            'no preset should claim to be current at an unconfigured minute')
    end
end)

test('a preset click runs /time with the preset word and no numbers', function()
    openTimeSelector({ selectedId = 'noon' })
    equal(executedCommand, 'time noon', 'preset command')
    equal(inputFields, nil, 'a preset must not open the hour/minute dialog')
end)

test('Custom opens the hour and minute inputs and runs the typed clock', function()
    clockHour, clockMinute = 8, 30
    inputResult = { values = { hour = 3, minute = 45 } }
    openTimeSelector({ selectedId = 'custom' })
    equal(#inputFields, 2, 'Custom collects an hour and a minute')
    equal(inputFields[1].id, 'hour', 'first field')
    equal(inputFields[1].default, 8, 'hour should default to the live clock')
    equal(inputFields[2].default, 30, 'minute should default to the live clock')
    equal(executedCommand, 'time 3 45', 'custom command')
end)

test('a cancelled Custom dialog runs nothing', function()
    inputResult = { cancelled = true }
    openTimeSelector({ selectedId = 'custom' })
    equal(executedCommand, nil, 'cancelling the dialog must not touch the clock')
end)

print(('qbadmin world: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
