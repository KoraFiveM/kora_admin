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
local menuUpdates
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
        updateApp = function(_, update)
            menuUpdates = (menuUpdates or 0) + 1
            if update.navigation then menuPayload.navigation = update.navigation end
        end,
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

local function findView(definition, id)
    for _, view in ipairs(definition.navigation) do
        if view.id == id then return view end
    end
end

local function findTab(view, id)
    for _, tab in ipairs(view and view.tabs or {}) do
        if tab.id == id then return tab end
    end
end

local function findAction(definition, id)
    for _, view in ipairs(definition.navigation) do
        for _, tab in ipairs(view.tabs or {}) do
            for _, block in ipairs(tab.content and tab.content.blocks or {}) do
                for _, action in ipairs(block.actions or {}) do
                    if action.id == id then return action end
                end
            end
        end
    end
end

local function timeAction()
    executedCommand, menuPayload = nil, nil
    netEvents['qbadmin:client:openMenu']('god')
    return findAction(menuPayload, 'world:time')
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

test('the sidebar is reduced to focused workspaces with tabbed tools', function()
    menuUpdates = 0
    netEvents['qbadmin:client:openMenu']('god')
    equal(#menuPayload.navigation, 5, 'the long category list should collapse into five workspaces')
    truthy(findView(menuPayload, 'players'), 'Players workspace')
    truthy(findView(menuPayload, 'reports'), 'Reports workspace')
    truthy(findView(menuPayload, 'tools'), 'My Tools workspace')
    truthy(findView(menuPayload, 'server'), 'Server workspace')
    truthy(findView(menuPayload, 'development'), 'Development workspace')
    equal(#findView(menuPayload, 'tools').tabs, 4, 'personal utilities should be split into four tabs')
    equal(#findView(menuPayload, 'server').tabs, 4, 'server controls should be split into four tabs')
    truthy(findTab(findView(menuPayload, 'tools'), 'vehicle'), 'vehicles should be a tab, not a sidebar page')
    truthy(findTab(findView(menuPayload, 'server'), 'audit'), 'audit log should be a server tab')
    truthy(findAction(menuPayload, 'player:refresh'), 'online browser should have an explicit refresh action')
    equal(findAction(menuPayload, 'player:players'), nil, 'Players opens directly into the browser')
    equal(findAction(menuPayload, 'teleport:goto'), nil, 'targeted teleport only follows selection')
    equal(findAction(menuPayload, 'vehicle:veh'), nil, 'targeted vehicle spawn only follows selection')
    equal(findAction(menuPayload, 'developer:devmode_player'), nil, 'targeted dev mode only follows selection')
    truthy(findAction(menuPayload, 'world:restartresource'), 'unique server action remains available')
    equal(menuUpdates, 0, 'live tables should be seeded before registration without a second render')
end)

test('Vehicle provides both a refreshed catalogue and a free-form spawn code', function()
    QB.shared.all = function() return {} end
    local appUpdate
    QB.nui.updateApp = function(_, update) appUpdate = update end
    netEvents['qbadmin:client:openMenu']('god')

    QB.shared.all = function(name)
        if name == 'vehicles' then return { { model = 'zentorno', name = 'Zentorno' } } end
        return {}
    end
    netEvents['qbcore:registry:snapshotAll']({})

    local code = findAction({ navigation = appUpdate.navigation }, 'vehicle:car')
    local catalogue = findAction({ navigation = appUpdate.navigation }, 'vehicle:car_catalogue')
    equal(code.fields[1].type, 'text', 'Spawn from Code accepts a plain model name')
    equal(catalogue.fields[1].type, 'combobox', 'catalogue stays searchable')
    equal(catalogue.fields[1].options[1].value, 'zentorno', 'catalogue uses the synced vehicle registry')

    executedCommand = nil
    menuPayload.onAction('vehicle:car', { value = { model = 'adder' } })
    equal(executedCommand, 'car adder', 'Spawn from Code calls the self-spawn command')

    QB.shared.all = function() return {} end
    QB.nui.updateApp = nil
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
    local selectedResult = menuPayload.onAction('player:select', { itemId = '7' })
    equal(selectedResult.navigate.viewId, 'players', 'player selection returns AppShell navigation')
    equal(selectedResult.navigate.tabId, 'overview', 'player selection opens the profile overview')

    local selectedActionGroups, profileDetails, onlinePlayers, back = {}, nil, nil, nil
    local playerWorkspace = findView(menuPayload, 'players')
    equal(playerWorkspace.defaultTab, 'overview', 'a selected player should open on a concise overview')
    equal(#playerWorkspace.tabs, 6, 'the player detail should be split into manageable tabs')
    for _, tab in ipairs(playerWorkspace.tabs) do
        for _, block in ipairs(tab.content.blocks) do
                if block.id and block.id:match('^selected%-player%-actions') then
                    selectedActionGroups[block.title] = block.actions
                end
                if block.id == 'selected-player-details' then profileDetails = block end
                if block.id == 'online-players' then onlinePlayers = block end
                if block.id == 'selected-player-back' then back = block end
        end
    end
    truthy(profileDetails and profileDetails.type == 'details' and #profileDetails.items >= 10,
        'clicking a player should open their full profile as structured details')
    equal(onlinePlayers, nil, 'the player list should be replaced by the profile')
    truthy(back and back.actions[1].id == 'player:back', 'the profile should offer a back button')
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

    local backResult = menuPayload.onAction('player:back', {})
    equal(backResult.navigate.viewId, 'players', 'profile Back returns an AppShell navigation result')
    playerWorkspace = findView(menuPayload, 'players')
    equal(#playerWorkspace.tabs, 1, 'Back should collapse player detail tabs to the online browser')
    for _, block in ipairs(playerWorkspace.tabs[1].content.blocks) do
        if block.id == 'online-players' then onlinePlayers = block end
    end
    truthy(onlinePlayers, 'Back should return to the online-player browser')
    truthy(onlinePlayers.searchable and onlinePlayers.pageSize == 12,
        'the restored online-player table is searchable and paged')
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
    local selectedResult = menuPayload.onAction('reports:select', { itemId = '42' })
    equal(selectedResult.navigate.viewId, 'reports', 'report selection returns AppShell navigation')
    equal(selectedResult.navigate.tabId, 'overview', 'report selection opens the report overview')

    local conversation, management, reporter, back
    local reportWorkspace = findView(menuPayload, 'reports')
    equal(reportWorkspace.defaultTab, 'overview', 'selected reports should open on their overview')
    equal(#reportWorkspace.tabs, 3, 'report detail should separate overview, management, and reporter tools')
    for _, tab in ipairs(reportWorkspace.tabs) do
        for _, block in ipairs(tab.content.blocks) do
                if block.id == 'selected-report-conversation' then conversation = block end
                if block.id == 'selected-report-management' then management = block end
                if block.id == 'selected-report-player' then reporter = block end
                if block.id == 'selected-report-back' then back = block end
        end
    end
    equal(conversation.type, 'timeline', 'report conversation should use the AppShell timeline')
    equal(#conversation.items, 2, 'initial report and staff reply should both be visible')
    truthy(management and #management.actions == 4, 'open report should offer claim, reply, resolve, and dismiss')
    truthy(reporter and #reporter.actions == 4, 'online reporter should have movement and spectate tools')
    truthy(back and back.actions[1].id == 'reports:back', 'report detail should offer a queue back button')

    menuPayload.onAction('reports:selected:reply', { value = { message = 'Please try that again now' } })
    equal(executedCommand, 'reportreply 42 Please try that again now', 'report reply command')

    local backResult = menuPayload.onAction('reports:back', {})
    equal(backResult.navigate.viewId, 'reports', 'report Back returns an AppShell navigation result')
    reportWorkspace = findView(menuPayload, 'reports')
    equal(#reportWorkspace.tabs, 1, 'Back should restore the queue tab')
    truthy(findTab(reportWorkspace, 'reports'), 'report queue tab should be restored')
    local queue = findTab(reportWorkspace, 'reports').content.blocks[#findTab(reportWorkspace, 'reports').content.blocks]
    truthy(queue.searchable and queue.pageSize == 12, 'the restored report queue is searchable and paged')
    truthy(queue.rows[1].status.badge, 'report status uses a rich AppShell badge cell')
end)

print(('qbadmin world: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
