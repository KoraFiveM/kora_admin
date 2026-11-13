local testLang = dofile('test/support/lang.lua')
local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print('  PASS  ' .. name)
    else failed = failed + 1; print('  FAIL  ' .. name .. ': ' .. tostring(err)) end
end
local function equal(actual, expected, message)
    if actual ~= expected then error(('%s: expected %s, got %s'):format(message or 'values differ', tostring(expected), tostring(actual)), 2) end
end
local function truthy(value, message)
    if not value then error(message or 'expected a truthy value', 2) end
end

dofile('config.lua')

local convar = ''
local messages = {}
local notifications = {}
local callbacks = {}
local timers = {}

Admin = {}
Kora = { lang = testLang,
    notify = { send = function(payload) notifications[#notifications + 1] = payload end },
    util = { trim = function(value) return type(value) == 'string' and value:match('^%s*(.-)%s*$') or value end },
}
function GetConvar(_, default) return convar ~= '' and convar or default end
function SendNUIMessage(payload) messages[#messages + 1] = payload end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function SetTimeout(_, callback) timers[#timers + 1] = callback end

dofile('client/medal.lua')

test('missing public key disables Medal and sends no request', function()
    equal(Admin.isMedalConfigured(), false, 'configured state')
    equal(Admin.invokeMedalEvent(Config.medal.events[1]), false, 'invoke result')
    equal(#messages, 0, 'NUI message count')
    equal(notifications[#notifications].type, 'error', 'notification type')
end)

test('configured event sends Medal API payload to the local bridge', function()
    convar = 'public-test-key'
    equal(Admin.isMedalConfigured(), true, 'configured state')
    truthy(Admin.invokeMedalEvent(Config.medal.events[1]), 'invoke should succeed')

    local message = messages[#messages]
    equal(message.type, 'kora_admin:medal:invoke', 'message type')
    equal(message.publicKey, convar, 'public key')
    equal(message.body.eventId, '1', 'event id')
    equal(message.body.eventName, 'Admin Clip', 'event name')
    equal(message.body.triggerActions[1], 'SaveClip', 'trigger action')
    equal(message.body.clipOptions.duration, 30, 'duration')
    equal(message.body.clipOptions.captureDelayMs, 0, 'capture delay')
end)

test('Medal callback maps success and API errors to useful notifications', function()
    local message = messages[#messages]
    callbacks['kora_admin:medal:result']({ requestId = message.requestId, ok = true, status = 200 }, function() end)
    equal(notifications[#notifications].type, 'success', 'success notification')

    Admin.invokeMedalEvent(Config.medal.events[1])
    message = messages[#messages]
    callbacks['kora_admin:medal:result']({ requestId = message.requestId, ok = false, status = 401 }, function() end)
    equal(notifications[#notifications].type, 'error', 'error notification')
    truthy(notifications[#notifications].message:find('public key', 1, true), '401 guidance')
end)

test('invalid event is refused before reaching the bridge', function()
    local before = #messages
    equal(Admin.invokeMedalEvent({ id = 'custom', name = '', duration = 0 }), false, 'invoke result')
    equal(#messages, before, 'NUI message count')
end)

local manifest = assert(io.open('fxmanifest.lua', 'r')):read('*a')
local bridge = assert(io.open('web/medal.js', 'r')):read('*a')
local menu = assert(io.open('client/menu.lua', 'r')):read('*a')
test('admin menu and manifest load a fixed localhost Medal bridge', function()
    truthy(manifest:find("ui_page 'web/medal.html'", 1, true), 'ui_page registration')
    truthy(manifest:find("'client/medal.lua'", 1, true), 'client script registration')
    truthy(menu:find("id = 'medal'", 1, true), 'Medal menu category')
    truthy(menu:find('Admin.invokeMedalEvent', 1, true), 'Medal menu action')
    truthy(bridge:find('http://localhost:12665/api/v1/event/invoke', 1, true), 'Medal endpoint')
end)

print(('kora_admin medal: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
