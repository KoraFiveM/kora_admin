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

-- Set Time is an AppShell form: presets and exact-time inputs never open a
-- second menu or input dialog.
local netEvents = {}
local menuPayload
local executedCommand
local copiedText
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
        registerApp = function(definition) menuPayload = definition end,
        openApp = function() return { closed = true } end,
        copyToClipboard = function(value) copiedText = value end,
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

local function timeAction()
    executedCommand, menuPayload = nil, nil
    netEvents['qbadmin:client:openMenu']('god')
    for _, category in ipairs(menuPayload.navigation) do
        if category.id == 'world' then
            for _, action in ipairs(category.content.blocks[1].actions) do
                if action.id == 'world:time' then return action end
            end
        end
    end
end

test('Set Time provides presets and exact inputs in the app shell', function()
    clockHour, clockMinute = 8, 0
    local action = timeAction()
    equal(#action.fields[1].options, #Config.world.timePresets + 1, 'preset choices plus Custom')
    for index, preset in ipairs(Config.world.timePresets) do
        equal(action.fields[1].options[index].value, preset.id, ('preset %d id'):format(index))
    end
    equal(action.fields[1].options[#action.fields[1].options].value, 'custom', 'Custom is offered last')
    equal(action.fields[2].default, 8, 'custom hour defaults to the live clock')
    equal(action.fields[3].default, 0, 'custom minute defaults to the live clock')
end)

test('a preset submission runs /time with the preset word and no numbers', function()
    timeAction()
    menuPayload.onAction('world:time', { value = { preset = 'noon', hour = 8, minute = 0 } })
    equal(executedCommand, 'time noon', 'preset command')
end)

test('a Custom submission runs the exact time', function()
    clockHour, clockMinute = 8, 30
    timeAction()
    menuPayload.onAction('world:time', { value = { preset = 'custom', hour = 3, minute = 45 } })
    equal(executedCommand, 'time 3 45', 'custom command')
end)

test('the sidebar omits actions already available after selecting a player', function()
    netEvents['qbadmin:client:openMenu']('god')
    local categories, actions = {}, {}
    for _, category in ipairs(menuPayload.navigation) do
        categories[category.id] = true
        actions[category.id] = {}
        for _, action in ipairs(category.content.blocks[1].actions) do actions[category.id][action.id] = true end
    end

    equal(categories.economy, nil, 'no duplicate economy sidebar')
    equal(categories.jobgang, nil, 'no duplicate job/gang sidebar')
    equal(categories.temporary_access, nil, 'no duplicate access sidebar')
    equal(categories.entities, nil, 'no duplicate target-spawning sidebar')
    equal(categories.privileged, nil, 'single server action should be folded into World / Server')
    truthy(actions.player['player:players'], 'Players remains the entry point')
    equal(actions.teleport['teleport:goto'], nil, 'targeted teleport only follows selection')
    equal(actions.vehicle['vehicle:veh'], nil, 'targeted vehicle spawn only follows selection')
    equal(actions.developer['developer:devmode_player'], nil, 'targeted dev mode only follows selection')
    truthy(actions.world['world:restartresource'], 'unique server action remains available')
end)

test('List Players selects a player before running their admin actions', function()
    QB.callback.trigger = function(name)
        if name == 'qbadmin:menuPlayers' then
            -- The caller is deliberately present in this list: staff may
            -- select themselves and use the same player-first workflow.
            return { { id = '7', name = 'Admin', job = 'Police', ping = 12 } }
        end
        if name == 'qbadmin:menuPlayerProfile' then
            return {
                id = '7', name = 'Admin', citizenid = 'TEST123', job = 'Police (Chief)', gang = 'None',
                money = 'bank: 5000, cash: 100', ping = 12, health = 200, armor = 50,
                hunger = 80, thirst = 70, dead = false, cuffed = false,
                permission = 'owner', license = 'license:test', discord = 'discord:test',
            }
        end
        return {}
    end
    netEvents['qbadmin:client:openMenu']('god')
    menuPayload.onAction('player:players', {})
    menuPayload.onAction('player:select', { itemId = '7' })

    local selectedActionGroups, profileDetails, onlinePlayers = {}, nil, nil
    for _, category in ipairs(menuPayload.navigation) do
        if category.id == 'player' then
            for _, block in ipairs(category.content.blocks) do
                if block.id and block.id:match('^selected%-player%-actions') then
                    selectedActionGroups[block.title] = block.actions
                end
                if block.id == 'selected-player-details' then profileDetails = block end
                if block.id == 'online-players' then onlinePlayers = block end
            end
        end
    end
    truthy(profileDetails and #profileDetails.rows >= 10, 'clicking a player should open their full profile')
    equal(onlinePlayers, nil, 'the player list should be replaced by the profile')
    truthy(selectedActionGroups['Profile'], 'profile controls should have their own category')
    truthy(selectedActionGroups['Movement & Spectating'], 'movement commands should have their own category')
    truthy(selectedActionGroups['Health & State'], 'health commands should have their own category')
    truthy(selectedActionGroups['Moderation'], 'moderation commands should have their own category')
    truthy(selectedActionGroups['Appearance'], 'appearance commands should have their own category')
    truthy(selectedActionGroups['Economy & Inventory'], 'economy commands should have their own category')
    truthy(selectedActionGroups['Job, Gang & Duty'], 'role commands should have their own category')
    truthy(selectedActionGroups['Spawning'], 'spawn commands should have their own category')
    truthy(selectedActionGroups['Development'], 'development commands should have their own category')
    truthy(selectedActionGroups['Access & Permissions'], 'access commands should have their own category')

    executedCommand = nil
    menuPayload.onAction('player:target:heal', { value = {} })
    equal(executedCommand, 'heal 7', 'selected player id is retained by the action')

    menuPayload.onAction('player:target:sendback', { value = {} })
    equal(executedCommand, 'sendback 7', 'Send Back uses the selected player')

    menuPayload.onAction('player:target:barbermenu', { value = {} })
    equal(executedCommand, 'barbermenu 7', 'appearance tools use the selected player')

    copiedText = nil
    menuPayload.onAction('player:target:copyinfo', { value = {} })
    truthy(copiedText and copiedText:find('Citizen ID: TEST123', 1, true), 'copy button should copy the player profile')
end)

test('Reports list, detail, conversation, and management stay in the app shell', function()
    QB.callback.trigger = function(name)
        if name == 'qbadmin:menuReports' then
            return { {
                id = 42, type = 'bug', status = 'open', reporter_name = 'Citizen',
                message = 'Inventory button is stuck', created_at = 'now', updated_at = 'now',
            } }
        end
        if name == 'qbadmin:menuReport' then
            return {
                id = 42, type = 'bug', status = 'open', reporter_name = 'Citizen', reporter_source = 12,
                message = 'Inventory button is stuck', created_at = 'now', messages = {
                    { author_name = 'Support', author_role = 'staff', message = 'Looking into it', created_at = 'later' },
                },
            }
        end
        return {}
    end

    netEvents['qbadmin:client:openMenu']('god')
    menuPayload.onAction('reports:open', {})
    menuPayload.onAction('reports:select', { itemId = '42' })

    local conversation, management, reporter
    for _, category in ipairs(menuPayload.navigation) do
        if category.id == 'reports' then
            for _, block in ipairs(category.content.blocks) do
                if block.id == 'selected-report-conversation' then conversation = block end
                if block.id == 'selected-report-management' then management = block end
                if block.id == 'selected-report-player' then reporter = block end
            end
        end
    end
    equal(#conversation.rows, 2, 'initial report and staff reply should both be visible')
    truthy(management and #management.actions == 4, 'open report should offer claim, reply, resolve, and dismiss')
    truthy(reporter and #reporter.actions == 4, 'online reporter should have movement and spectate tools')

    menuPayload.onAction('reports:selected:reply', { value = { message = 'Please try that again now' } })
    equal(executedCommand, 'reportreply 42 Please try that again now', 'report reply command')
end)

print(('qbadmin world: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
