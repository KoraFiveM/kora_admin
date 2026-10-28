local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print('  PASS  ' .. name)
    else failed = failed + 1; print(('  FAIL  %s — %s'):format(name, err)) end
end
local function equal(actual, expected, message)
    if actual ~= expected then error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)), 2) end
end
local function truthy(value, message) if not value then error(message, 2) end end

dofile('config.lua')
local callbacks, commands = {}, {}
local adminViewer = false
QB = {
    callback = { register = function(name, handler) callbacks[name] = handler end },
    commands = { add = function(name, _, _, _, handler, options) commands[name] = { handler = handler, options = options } end },
    notify = { send = function() end },
}
Admin = {
    states = { frozen = {}, god = {}, invisible = {} },
    checkLevel = function(_, level) return level ~= 'admin' or adminViewer end,
    resolveTarget = function(_, target)
        if target ~= '12' then return nil, nil, 'player not found' end
        return 12, {
            citizenid = 'CITIZEN12', name = 'Jane Doe',
            job = { name = 'police', label = 'Police', onduty = true, grade = { name = 'Sergeant', level = 3 } },
            gang = { name = 'none', label = 'None', grade = { name = 'None', level = 0 } },
            money = { cash = 250, bank = 4000 },
            metadata = { armor = 50, hunger = 80, thirst = 70, isdead = false, ishandcuffed = true },
        }
    end,
    getLevel = function() return 'moderator' end,
    menuAccessDeniedMessage = function() return 'Admin menu unavailable: requires Support (rank 10).' end,
    queryLogs = function() return {} end,
    queryReports = function() return {} end,
    getReport = function() return nil end,
    getReportMessages = function() return {} end,
}
exports = { kora_core = {
    getPlayers = function() return { 12 } end,
    getJob = function() return { label = 'Police' } end,
    getIdentifiers = function() return { license = 'license:test', discord = 'discord:test' } end,
    isDevMode = function() return true end,
} }
function GetPlayerName() return 'Jane Doe' end
function GetPlayerPing() return 24 end
function GetPlayerPed() return 120 end
function GetEntityHealth() return 175 end
function TriggerClientEvent() end

dofile('server/menu_data.lua')
dofile('server/command_registry.lua')
dofile('server/commands/player.lua')

test('selecting a player returns a complete fresh profile', function()
    local profile = callbacks['qbadmin:menuPlayerProfile'](7, '12')
    equal(profile.id, '12', 'server id')
    equal(profile.citizenid, 'CITIZEN12', 'citizen id')
    equal(profile.job, 'Police (Sergeant)', 'job and grade')
    equal(profile.gang, 'None (None)', 'gang and grade')
    equal(profile.money, 'bank: 4000, cash: 250', 'sorted balances')
    equal(profile.health, 175, 'live health')
    equal(profile.armor, 50, 'armor')
    equal(profile.cuffed, true, 'state')
    equal(profile.onDuty, true, 'duty state')
    equal(profile.devMode, true, 'development state')
    equal(profile.frozen, false, 'frozen state defaults off')
    equal(profile.license, nil, 'support must not receive platform identifiers')
end)

test('admin profiles include permission and platform identifiers', function()
    adminViewer = true
    local profile = callbacks['qbadmin:menuPlayerProfile'](7, '12')
    equal(profile.permission, 'moderator', 'permission level')
    equal(profile.license, 'license:test', 'license')
    equal(profile.discord, 'discord:test', 'discord')
end)

test('the old player-details command is no longer registered', function()
    truthy(commands.admin and commands.players, 'remaining player commands should register')
    equal(#(function()
        local matches = {}
        for name in pairs(commands) do
            if name ~= 'admin' and name ~= 'players' and name ~= 'sethunger' and name ~= 'setthirst' then matches[#matches + 1] = name end
        end
        return matches
    end)(), 0, 'unexpected player command')
end)

test('a denied admin-menu open explains the permission requirement and roles', function()
    local message, kind
    QB.notify.send = function(_, payload) message, kind = payload.message, payload.type end

    commands.admin.options.notify(7)

    equal(message, 'Admin menu unavailable: requires Support (rank 10).', 'the access reason is shown')
    equal(kind, 'error', 'the access reason is an error notification')
end)

print(('qbadmin player profile: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
