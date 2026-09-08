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

-- Server command registration and authorization.
local commands = {}
local responses = {}
local clientEvents = {}
local logs = {}
local devMode = false

QB = {
    commands = {
        add = function(name, _, _, _, handler, options)
            commands[name] = { handler = handler, options = options }
        end,
    },
}
Admin = {
    checkLevel = function() return true end,
    respond = function(source, ok, message)
        responses[#responses + 1] = { source = source, ok = ok, message = message }
    end,
    log = function(source, action, _, details)
        logs[#logs + 1] = { source = source, action = action, details = details }
    end,
}
exports = {
    qbcore = {
        isDevMode = function(_, source)
            equal(source, 7, 'server dev-mode lookup should use the command source')
            return devMode
        end,
    },
}
function TriggerClientEvent(name, target, ...)
    clientEvents[#clientEvents + 1] = { name = name, target = target, args = { ... } }
end

dofile('server/commands/development.lua')

test('developer commands use the configured server permission gate', function()
    equal(commands.entitypicker.options.permission, Config.developer.menuLevel, 'entity picker permission')
    equal(commands.devplacement.options.permission, Config.developer.menuLevel, 'placement permission')
    equal(commands.devzone.options.permission, Config.developer.menuLevel, 'zone permission')
    equal(commands.devplacement.options.checkPermission, Admin.checkLevel, 'placement check function')
end)

test('entity picker launches only after the developer gate passes', function()
    devMode = true
    commands.entitypicker.handler(7, {})
    local event = clientEvents[#clientEvents]
    equal(event.name, 'qbadmin:client:startEntityPicker', 'entity picker event')
    equal(event.target, 7, 'entity picker target')
    equal(logs[#logs].action, 'entitypicker', 'entity picker request should be audited')
end)

test('creator commands reject until qbcore development mode is enabled', function()
    devMode = false
    local before = #clientEvents
    commands.devplacement.handler(7, { 'prop_barrel_02a' })
    equal(#clientEvents, before, 'disabled dev mode must not launch placement')
    truthy(responses[#responses] and not responses[#responses].ok, 'the rejection should notify the caller')
end)

test('placement forwards model names and numeric hashes to the authenticated client', function()
    devMode = true
    commands.devplacement.handler(7, { 'prop_barrel_02a' })
    local event = clientEvents[#clientEvents]
    equal(event.name, 'qbadmin:client:startPlacement', 'placement event')
    equal(event.target, 7, 'placement target')
    equal(event.args[1], 'prop_barrel_02a', 'placement model')

    commands.devplacement.handler(7, { '-12345' })
    event = clientEvents[#clientEvents]
    equal(event.args[1], -12345, 'numeric model hashes should remain numeric')
    equal(logs[#logs].action, 'devplacement', 'placement request should be audited')
end)

test('zone creator validates and forwards only supported shapes', function()
    local before = #clientEvents
    commands.devzone.handler(7, { 'cylinder' })
    equal(#clientEvents, before, 'invalid zone type must not launch a creator')

    commands.devzone.handler(7, { 'POLY' })
    local event = clientEvents[#clientEvents]
    equal(event.name, 'qbadmin:client:startZoneCreator', 'zone event')
    equal(event.args[1], 'poly', 'zone type should be normalized')
    equal(logs[#logs].action, 'devzone', 'zone request should be audited')
end)

-- Client launchers and dynamic Developer submenu state.
local netEvents = {}
local notifications = {}
local placementResult = { model = 'prop_test' }
local zoneResult = { type = 'box' }
local localDevMode = false
local menuPayload
local selectedMenuResult = { cancelled = true }
local inputResult = { cancelled = true }
local executedCommand
local keybinds = {}
local textUi = {}
local copiedText

QB = {
    notify = { send = function(payload) notifications[#notifications + 1] = payload end },
    placement = { start = function() return placementResult end },
    zones = { startCreator = function() return zoneResult end },
    cache = {
        serverId = function() return 7 end,
        vehicle = function() return false end,
    },
    callback = { trigger = function() return {} end },
    raycast = { fromCamera = function() return true, { x = 3.0, y = 4.0, z = 0.0 }, 99 end },
    lookup = { model = function() return { name = 'prop_catalogue', label = 'Catalogue prop' } end },
    shared = {
        all = function() return {} end,
        get = function() return nil end,
    },
    nui = {
        registerApp = function(definition) menuPayload = definition end,
        openApp = function()
            if selectedMenuResult and selectedMenuResult.path and selectedMenuResult.selectedId then
                return menuPayload.onAction(selectedMenuResult.path[1] .. ':' .. selectedMenuResult.selectedId, { value = inputResult.values })
            end
            return { closed = true }
        end,
        openMenu = function(items, title)
            menuPayload = { items = items, title = title }
            return selectedMenuResult
        end,
        openInputDialog = function() return inputResult end,
        openAlert = function() return { confirmed = false } end,
        copyToClipboard = function(text) copiedText = text end,
    },
    keybind = {
        add = function(options)
            keybinds[options.name] = options
            return {}
        end,
    },
    textui = {
        show = function(text, options)
            textUi.text, textUi.options = text, options
            return 1
        end,
        update = function(_, text, options)
            textUi.text, textUi.options = text, options
            return true
        end,
        hide = function() end,
    },
}
exports = {
    qbcore = {
        isDevMode = function() return localDevMode end,
    },
}
Admin = nil
function RegisterNetEvent(name, callback)
    if callback then netEvents[name] = callback end
end
function CreateThread(fn)
    local thread = coroutine.create(fn)
    local ok, err = coroutine.resume(thread)
    if not ok then error(err, 0) end
end
function Wait() coroutine.yield() end
function TriggerServerEvent() end
function ExecuteCommand(command) executedCommand = command end
function GetActivePlayers() return {} end
function GetResourceState() return 'missing' end
function AddEventHandler() end
function GetCurrentResourceName() return 'qbadmin' end
function DoesEntityExist(entity) return entity == 99 end
function GetEntityType() return 3 end
function GetEntityModel() return 123456 end
function GetEntityArchetypeName() return 'prop_actual_map_name' end
function GetEntityCoords(entity)
    if entity == 99 then return { x = 3.0, y = 4.0, z = 0.0 } end
    return { x = 0.0, y = 0.0, z = 0.0 }
end
function PlayerPedId() return 1 end
function GetEntityHeading() return 90.0 end
function GetGameTimer() return 0 end

dofile('client/core.lua')
Admin.level = Config.developer.menuLevel
dofile('client/development.lua')
dofile('client/entity_picker.lua')
dofile('client/menu.lua')

test('client launch events call qblib creators and report completion', function()
    netEvents['qbadmin:client:startPlacement']('prop_test')
    equal(notifications[#notifications].type, 'success', 'placement completion notification')

    netEvents['qbadmin:client:startZoneCreator']('box')
    equal(notifications[#notifications].type, 'success', 'zone completion notification')
end)

local function developerCategory()
    for _, category in ipairs(menuPayload.navigation) do
        if category.id == 'development' then return category end
    end
end

local function developerItem(id)
    local category = developerCategory()
    if not category then return nil end
    for _, tab in ipairs(category.tabs or {}) do
        if tab.id == 'developer' then
            for _, item in ipairs(tab.content.blocks[1].actions) do
                if item.id == ('developer:' .. id) then return item end
            end
        end
    end
end

test('Builders tab reflects qbcore dev mode and gates creator shortcuts', function()
    localDevMode = false
    selectedMenuResult = { cancelled = true }
    netEvents['qbadmin:client:openMenu'](Config.developer.menuLevel)
    truthy(developerCategory(), 'Development workspace should be present')
    equal(developerItem('devmode_self'), nil, 'player dev mode belongs under the selected-player workflow')
    truthy(developerItem('devplacement').disabled, 'placement should be disabled outside dev mode')
    truthy(developerItem('devzone').disabled, 'zone creator should be disabled outside dev mode')
    truthy(developerItem('entitypicker').disabled, 'entity picker should be disabled outside dev mode')

    localDevMode = true
    netEvents['qbadmin:client:openMenu'](Config.developer.menuLevel)
    equal(developerItem('devplacement').disabled, false, 'placement should enable in dev mode')
    equal(developerItem('devzone').disabled, false, 'zone creator should enable in dev mode')
    equal(developerItem('entitypicker').disabled, false, 'entity picker should enable in dev mode')
end)

test('entity picker registers rebindable copy and close controls', function()
    equal(keybinds.qbadmin_entitypicker_copy.defaultKey, Config.entityPicker.copyKey, 'copy key default')
    equal(keybinds.qbadmin_entitypicker_close.defaultKey, Config.entityPicker.closeKey, 'close key default')
end)

test('entity picker displays and copies the real prop archetype name', function()
    netEvents['qbadmin:client:startEntityPicker']()
    truthy(textUi.text:find('prop_actual_map_name', 1, true), 'HUD should prefer the game archetype name')

    keybinds.qbadmin_entitypicker_copy.onPressed()
    equal(copiedText, 'prop_actual_map_name', 'copy binding should copy the real prop name')
    keybinds.qbadmin_entitypicker_close.onPressed()
end)

test('Builders tab zone shortcut runs the permission-checked command', function()
    selectedMenuResult = { path = { 'developer' }, selectedId = 'devzone' }
    inputResult = { values = { type = 'sphere' } }
    netEvents['qbadmin:client:openMenu'](Config.developer.menuLevel)
    equal(executedCommand, 'devzone sphere', 'zone shortcut command')
end)

print(('qbadmin development: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
