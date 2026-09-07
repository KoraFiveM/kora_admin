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

local definition, netEvents, notifications, committed = nil, {}, {}, nil
local entry = {
    resource = 'sample', revision = 2,
    schema = {
        kind = 'object', fields = {
            enabled = { kind = 'boolean', path = { 'enabled' }, label = 'Enabled', scope = 'client', live = true },
            interval = { kind = 'integer', path = { 'interval' }, label = 'Interval', scope = 'server', live = false },
        },
    },
    configured = { enabled = true, interval = 10 },
    values = { enabled = false, interval = 10 },
}

QB = {
    callback = {
        trigger = function(name, request)
            if name == 'qbadmin:configCatalog' then return { { resource = 'sample' } } end
            if name == 'qbadmin:configRead' then return entry end
            if name == 'qbadmin:configCommit' then
                committed = request
                return { ok = true, applied = true, revision = 3 }
            end
            error('unexpected callback ' .. name)
        end,
    },
    notify = { send = function(payload) notifications[#notifications + 1] = payload end },
    nui = {
        registerApp = function(value) definition = value end,
        openApp = function() end,
    },
}
json = {
    encode = function() return '{}' end,
    decode = function() return {} end,
}
function RegisterNetEvent(name, handler)
    if handler then netEvents[name] = handler end
end

dofile('client/config_editor.lua')
netEvents['qbadmin:client:configOpened']()

test('the workspace lists registered resources and status labels', function()
    equal(definition.id, 'qbadmin:config', 'workspace id')
    equal(definition.navigation[1].content.blocks[1].rows[1].resource, 'sample', 'registered resource')

    local result = definition.onAction('config:resource', { itemId = 'sample' })
    local rows = result.update.navigation[2].content.blocks[1].rows
    equal(rows[1].status.label, 'Applies now', 'live field label')
    equal(rows[2].status.label, 'Restart required', 'restart field label')
    equal(rows[1].scope, 'client', 'client-only field scope')
    equal(rows[2].scope, 'server', 'server-only field scope')
end)

test('the editor shows saved and running values, then commits through qbadmin', function()
    definition.onAction('config:resource', { itemId = 'sample' })
    local result = definition.onAction('config:setting', { itemId = 'enabled' })
    local details = result.update.navigation[3].content.blocks[1].items
    equal(details[1].value, 'true', 'saved value')
    equal(details[2].value, 'false', 'running value')

    definition.onAction('config:save', { value = { value = false } })
    truthy(committed, 'save request')
    equal(committed.resource, 'sample', 'commit resource')
    equal(committed.path[1], 'enabled', 'commit path')
    equal(committed.value, false, 'commit value')
    equal(notifications[#notifications].message, 'Configuration updated live.', 'live confirmation')
end)

print(('qbadmin config editor client: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
