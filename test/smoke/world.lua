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
local serverEvents = {}
local weatherResourceState = 'missing'

function GetResourceState() return weatherResourceState end

Kora = {
    commands = {
        add = function(name, _, _, _, handler, options)
            commands[name] = { handler = handler, options = options }
        end,
    },
}
function AddEventHandler(name, handler) serverEvents[name] = handler end
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

local consoleCommands = {}
local broadcasts = {}
function RegisterCommand(name, handler, restricted)
    consoleCommands[name] = { handler = handler, restricted = restricted }
end

dofile('server/command_registry.lua')
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

local providerCalls = {}
local providerError
exports = {
    kora_weathersync = {
        setWeather = function(_, weatherType)
            providerCalls[#providerCalls + 1] = { 'weather', weatherType }
            return providerError == nil, providerError
        end,
        setTime = function(_, hour, minute)
            providerCalls[#providerCalls + 1] = { 'time', hour, minute }
            return providerError == nil, providerError
        end,
    },
}

test('standalone weather and time retain broadcasts and late-join synchronization', function()
    for _, state in ipairs({ 'missing', 'stopped', 'starting', 'stopping' }) do
        weatherResourceState = state
        commands.weather.handler(7, { 'rain' })
        equal(clientEvents[#clientEvents].name, 'qbadmin:client:setWeather', 'standalone weather relay')
        equal(clientEvents[#clientEvents].args[1], 'RAIN', 'normalized weather')
        setTime('3', '45')
        local before = #clientEvents
        serverEvents['qbcore:server:playerLoaded'](12)
        equal(#clientEvents, before + 2, 'standalone join retains both overrides')
        equal(clientEvents[before + 1].target, 12, 'join weather targets the joining player')
        equal(clientEvents[before + 2].args[1], 3, 'join hour')
        equal(clientEvents[before + 2].args[2], 45, 'join minute')
    end
    commands.weather.handler(7, { 'unknown' })
    equal(responses[#responses].ok, false, 'standalone weather keeps its configured catalogue')
    equal(#providerCalls, 0, 'non-running resource states must not invoke exports')
end)

test('running weather sync receives custom times, presets and its own weather catalogue', function()
    weatherResourceState = 'started'
    local before = #clientEvents
    commands.time.handler(7, { '4', '15' })
    truthy(providerCalls[#providerCalls], 'time must reach the authoritative provider')
    equal(providerCalls[#providerCalls][1], 'time', 'time uses the authoritative setter')
    equal(providerCalls[#providerCalls][2], 4, 'custom hour')
    equal(providerCalls[#providerCalls][3], 15, 'custom minute')
    for _, preset in ipairs(Config.world.timePresets) do
        commands.time.handler(7, { preset.id:upper() })
        equal(providerCalls[#providerCalls][2], preset.hour, 'qbadmin retains its configured preset hour')
        equal(providerCalls[#providerCalls][3], preset.minute or 0, 'preset minute')
        equal(logs[#logs].details.preset, preset.id, 'presets remain audited')
    end
    commands.weather.handler(7, { 'halloween' })
    equal(providerCalls[#providerCalls][1], 'weather', 'provider validates its own catalogue')
    equal(providerCalls[#providerCalls][2], 'HALLOWEEN', 'normalized provider weather')
    equal(responses[#responses].ok, true, 'successful provider call notifies the admin')
    equal(commands.weather.options.permission, 'admin', 'weather permission unchanged')
    equal(commands.time.options.permission, 'admin', 'time permission unchanged')
    equal(#clientEvents, before, 'provider-backed commands must not issue competing local relays')
    local calls = #providerCalls
    commands.time.handler(7, { '24' })
    commands.time.handler(7, { '12', '30.5' })
    equal(#providerCalls, calls, 'invalid times are still refused before the export')
end)

test('provider rejection does not fall back, audit success or replace standalone join state', function()
    local events, audits = #clientEvents, #logs
    providerError = 'provider refused the change'
    commands.weather.handler(7, { 'unknown' })
    equal(responses[#responses].ok, false, 'weather failure reported')
    equal(responses[#responses].message, providerError, 'weather failure reason')
    commands.time.handler(7, { '8', '20' })
    equal(responses[#responses].ok, false, 'time failure reported')
    equal(responses[#responses].message, providerError, 'time failure reason')
    equal(#clientEvents, events, 'failed provider must not fall back to client overrides')
    equal(#logs, audits, 'rejected changes must not be logged as successful')
    serverEvents['qbcore:server:playerLoaded'](12)
    equal(#clientEvents, events, 'active provider suppresses cached standalone overrides on join')
    providerError = nil
    weatherResourceState = 'stopped'
    serverEvents['qbcore:server:playerLoaded'](12)
    equal(clientEvents[#clientEvents - 1].args[1], 'RAIN', 'standalone weather remains intact')
    equal(clientEvents[#clientEvents].args[1], 3, 'standalone hour remains intact')
    equal(clientEvents[#clientEvents].args[2], 45, 'standalone minute remains intact')
end)

test('authoritative player state changes request a live selected-profile refresh', function()
    local before = #clientEvents
    Admin.refreshMenuPlayerState(7, 12)
    local event = clientEvents[#clientEvents]
    equal(#clientEvents, before + 1, 'state changes should notify the viewing admin')
    equal(event.name, 'qbadmin:client:refreshMenuPlayerState', 'selected profile refresh event')
    equal(event.target, 7, 'refresh returns to the viewing admin')
    equal(event.args[1], 12, 'refresh identifies the changed player')
end)

-- Set Time is an AppShell form: presets and exact-time inputs never open a
-- second menu or input dialog.
local netEvents = {}
local menuPayload
local menuUpdates
local executedCommand
local copiedText
local clockHour, clockMinute = 8, 0
local adminDuty = false
local adminDutyChanged

Kora = {
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
exports = {
    kora_core = {
        isDevMode = function() return false end,
        getPlayerData = function(_, path)
            if path[1] == 'metadata' and path[2] == 'adminDuty' then return adminDuty end
        end,
        onPlayerDataChange = function(_, path, callback)
            if path[1] == 'metadata' and path[2] == 'adminDuty' then adminDutyChanged = callback end
        end,
    },
}
Admin = nil
function RegisterNetEvent(name, callback)
    if callback then netEvents[name] = callback end
end
function CreateThread(fn) fn() end
function Wait() end
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

test('the sidebar is reduced to focused workspaces with a configuration editor', function()
    menuUpdates = 0
    netEvents['qbadmin:client:openMenu']('god')
    equal(#menuPayload.navigation, 5, 'the long category list should collapse into five workspaces')
    truthy(findView(menuPayload, 'players'), 'Players workspace')
    truthy(findView(menuPayload, 'reports'), 'Reports workspace')
    truthy(findView(menuPayload, 'tools'), 'My Tools workspace')
    truthy(findView(menuPayload, 'server'), 'Server workspace')
    truthy(findView(menuPayload, 'development'), 'Development workspace')
    equal(#findView(menuPayload, 'tools').tabs, 4, 'personal utilities should be split into four tabs')
    equal(#findView(menuPayload, 'server').tabs, 5, 'server controls should include the configuration tab')
    truthy(findTab(findView(menuPayload, 'tools'), 'vehicle'), 'vehicles should be a tab, not a sidebar page')
    truthy(findTab(findView(menuPayload, 'server'), 'audit'), 'audit log should be a server tab')
    truthy(findTab(findView(menuPayload, 'server'), 'configuration'), 'configuration should be a server tab')
    truthy(findAction(menuPayload, 'player:refresh'), 'online browser should have an explicit refresh action')
    equal(findAction(menuPayload, 'player:players'), nil, 'Players opens directly into the browser')
    equal(findAction(menuPayload, 'teleport:goto'), nil, 'targeted teleport only follows selection')
    equal(findAction(menuPayload, 'vehicle:veh'), nil, 'targeted vehicle spawn only follows selection')
    equal(findAction(menuPayload, 'developer:devmode_player'), nil, 'targeted dev mode only follows selection')
    truthy(findAction(menuPayload, 'world:restartresource'), 'unique server action remains available')
    equal(menuUpdates, 0, 'live tables should be seeded before registration without a second render')
end)

test('Admin Duty shows its current state and the action it will take', function()
    adminDuty = false
    netEvents['qbadmin:client:openMenu']('god')
    local action = findAction(menuPayload, 'self:aduty')
    equal(action.label, 'Turn Admin Duty On', 'off-duty staff should be offered the on action')
    equal(action.state, false, 'off-duty state is explicit')
    equal(action.variant, 'primary', 'enabling duty is the primary action')
    local noclip = findAction(menuPayload, 'teleport:noclip')
    equal(noclip.label, 'Turn Noclip On', 'noclip action should name its result')
    equal(noclip.state, false, 'noclip state is explicit')
    local spectate = findAction(menuPayload, 'teleport:spectateStop')
    equal(spectate.state, false, 'spectating state is explicit')
    truthy(spectate.disabled, 'Stop Spectating is disabled until spectating starts')

    adminDuty = true
    truthy(adminDutyChanged, 'the menu should subscribe to admin-duty replication')
    adminDutyChanged({ 'metadata', 'adminDuty' }, true)
    action = findAction(menuPayload, 'self:aduty')
    equal(action.label, 'Turn Admin Duty Off', 'on-duty staff should be offered the off action')
    equal(action.state, true, 'on-duty state is explicit')
    equal(action.variant, 'outline', 'disabling duty should not look like an enable action')
end)

test('Vehicle provides both a refreshed catalogue and a free-form spawn code', function()
    Kora.shared.all = function() return {} end
    local appUpdate
    Kora.nui.updateApp = function(_, update) appUpdate = update end
    netEvents['qbadmin:client:openMenu']('god')

    Kora.shared.all = function(name)
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

    Kora.shared.all = function() return {} end
    Kora.nui.updateApp = nil
end)

test('List Players selects a player before running their admin actions', function()
    local previousSharedAll, previousSharedGet = Kora.shared.all, Kora.shared.get
    local jobs = {
        { name = 'police', label = 'Law Enforcement', grades = {
            { name = 'Cadet' }, { name = 'Officer' },
        } },
        { name = 'ambulance', label = 'EMS', grades = { { name = 'Recruit' } } },
        -- Legacy string-keyed grades must still list, in level order.
        { name = 'mechanic2', label = 'LS Customs', grades = { ['1'] = { name = 'Novice' }, ['0'] = { name = 'Recruit' } } },
        -- Placeholder duplicate of the same label is hidden (Config.roles.hideDuplicateLabels).
        { name = 'mechanic3', label = 'LS Customs', grades = { ['0'] = { name = 'Recruit' } } },
        -- A repeated job name is listed once.
        { name = 'ambulance', label = 'EMS', grades = { { name = 'Recruit' } } },
    }
    local gangs = {
        { name = 'none', label = 'No Gang', grades = { { name = 'None' } } },
    }
    Kora.shared.all = function(name)
        if name == 'jobs' then return jobs end
        if name == 'gangs' then return gangs end
        return {}
    end
    -- Role fields must be complete from the same `all()` snapshot; a second
    -- lookup can be briefly empty while the client registry is being seeded.
    Kora.shared.get = function() return nil end
    Kora.callback.trigger = function(name)
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
                onDuty = true, frozen = false, godMode = true, invisible = false, devMode = true,
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

    local setJob = findAction(menuPayload, 'player:target:setjob')
    equal(setJob.fields[1].default, 'police', 'the first available job should be selected')
    equal(setJob.fields[2].default, '1', 'the first available grade should be selected')
    equal(#setJob.fields[2].optionsByValue.police, 2, 'the selected job should expose all of its grades')
    equal(setJob.fields[2].optionsByValue.police[2].label, '2 - Officer', 'grade choices should be labelled')
    equal(#setJob.fields[1].options, 3, 'jobs should be listed once per name')
    equal(setJob.fields[2].optionsByValue.mechanic2[1].label, '1 - Recruit', 'string-keyed grades should be sorted by level')
    equal(#setJob.fields[2].optionsByValue.mechanic2, 2, 'string-keyed grades should not be dropped')
    equal(setJob.fields[2].optionsByValue.mechanic3, nil, 'a duplicate-label job should be hidden from Set Job')

    Config.roles.hideDuplicateLabels = false
    Config.roles.hiddenJobs = { 'ambulance' }
    netEvents['qbcore:registry:snapshotAll']({})
    local reselected = menuPayload.onAction('player:select', { itemId = '7' })
    local reSetJob = findAction(menuPayload, 'player:target:setjob')
    equal(#reSetJob.fields[1].options, 3, 'hiddenJobs should drop named jobs while duplicate hiding is off')
    equal(reSetJob.fields[2].optionsByValue.ambulance, nil, 'a hidden job should have no grade list')
    Config.roles.hideDuplicateLabels = true
    Config.roles.hiddenJobs = {}

    local duty = findAction(menuPayload, 'player:target:setduty')
    equal(duty.label, 'Take Off Duty', 'selected-player duty action should name its result')
    equal(duty.state, true, 'selected-player duty state is explicit')
    local frozen = findAction(menuPayload, 'player:target:freeze')
    equal(frozen.label, 'Freeze Player', 'selected-player freeze action should name its result')
    equal(frozen.state, false, 'selected-player freeze state is explicit')
    local god = findAction(menuPayload, 'player:target:god')
    equal(god.label, 'Turn God Mode Off', 'selected-player god action should name its result')
    equal(god.state, true, 'selected-player god state is explicit')
    local invisible = findAction(menuPayload, 'player:target:invisible')
    equal(invisible.label, 'Turn Invisibility On', 'selected-player invisibility action should name its result')
    equal(invisible.state, false, 'selected-player invisibility state is explicit')
    local devMode = findAction(menuPayload, 'player:target:devmode')
    equal(devMode.label, 'Turn Development Mode Off', 'selected-player development action should name its result')
    equal(devMode.state, true, 'selected-player development state is explicit')

    jobs[1].grades[3] = { name = 'Sergeant' }
    netEvents['qbcore:registry:snapshotAll']({})
    setJob = findAction(menuPayload, 'player:target:setjob')
    equal(#setJob.fields[2].optionsByValue.police, 3,
        'an open player menu should refresh when registry data arrives')

    executedCommand = nil
    menuPayload.onAction('player:target:setjob', { value = { name = 'police', grade = '2' } })
    equal(executedCommand, 'setjob 7 police 2', 'selected job and grade should reach the command')

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

    Kora.shared.all, Kora.shared.get = previousSharedAll, previousSharedGet
end)

test('Reports list, detail, conversation, and management stay in the app shell', function()
    local createdAt = 1788744746000
    local repliedAt = 1788744806
    Kora.callback.trigger = function(name)
        if name == 'qbadmin:menuReports' then
            return { {
                id = 42, type = 'bug', status = 'open', reporter_name = 'Citizen',
                message = 'Inventory button is stuck', created_at = createdAt, updated_at = createdAt,
                category = 'Bug', subject = 'Inventory button is stuck', age = '5m',
            } }
        end
        if name == 'qbadmin:menuReport' then
            return {
                id = 42, type = 'bug', status = 'open', reporter_name = 'Citizen', reporter_source = 12,
                message = 'Inventory button is stuck', created_at = createdAt, messages = {
                    { author_name = 'Support', author_role = 'staff', message = 'Looking into it', created_at = repliedAt },
                },
            }
        end
        return {}
    end

    netEvents['qbadmin:client:openMenu']('god')
    menuPayload.onAction('reports:open', {})
    local queueTab = findTab(findView(menuPayload, 'reports'), 'reports')
    local queue = queueTab.content.blocks[#queueTab.content.blocks]
    equal(queue.rows[1].age, '5m', 'report queue shows the age')
    equal(queue.rows[1].subject, 'Inventory button is stuck', 'report queue shows a one-line subject')
    equal(queue.rows[1].type, 'Bug', 'report queue shows the category label')
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
    equal(conversation.items[1].timestamp, os.date('!%Y-%m-%d %H:%M:%S', createdAt / 1000),
        'qbsql millisecond timestamps should be converted to timeline strings')
    equal(conversation.items[2].timestamp, os.date('!%Y-%m-%d %H:%M:%S', repliedAt),
        'second timestamps should use the same conversion')
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

test('/reports opens a dedicated Reports app with the existing queue handlers', function()
    local seenFilters = {}
    Kora.callback.trigger = function(name, filters)
        if name == 'qbadmin:menuReports' then seenFilters[#seenFilters + 1] = filters end
        return {}
    end
    menuPayload = nil
    netEvents['qbadmin:client:openReports']('support', { status = 'claimed' })
    equal(menuPayload.id, 'qbadmin:reports', 'dedicated app id')
    equal(#menuPayload.navigation, 1, 'only the Reports view is registered')
    equal(menuPayload.navigation[1].id, 'reports', 'Reports view')
    equal(seenFilters[1].status, 'claimed', 'initial filter from the command')
    menuPayload.onAction('reports:resolved', {})
    equal(seenFilters[#seenFilters].status, 'resolved', 'status buttons reuse the queue loader')
    local tab = findTab(findView(menuPayload, 'reports'), 'reports')
    local labels = {}
    for _, action in ipairs(tab.content.blocks[1].actions) do labels[action.label] = true end
    truthy(labels.Open and labels.Claimed and labels.Resolved and labels.Dismissed and labels.All, 'status filter buttons')
end)

test('kora_broadcast notifies every player, but only from the console', function()
    Kora.notify = { sendToAll = function(payload) broadcasts[#broadcasts + 1] = payload end }
    local command = consoleCommands.kora_broadcast
    truthy(command and command.restricted, 'kora_broadcast should be a restricted command')

    command.handler(7, {}, 'kora_broadcast hello')
    equal(#broadcasts, 0, 'a player must not be able to broadcast')

    command.handler(0, {}, 'kora_broadcast')
    equal(#broadcasts, 0, 'an empty message is ignored')

    command.handler(0, {}, 'kora_broadcast The server will restart in 5 minutes.')
    equal(#broadcasts, 1, 'the console broadcast reaches sendToAll')
    equal(broadcasts[1].message, 'The server will restart in 5 minutes.', 'broadcast message')
    equal(broadcasts[1].duration, 60000, 'restart warnings stay up long enough to notice')
end)

print(('qbadmin world: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
