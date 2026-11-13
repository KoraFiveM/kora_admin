local testLang = dofile('test/support/lang.lua')
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

local callbacks, commands, audits = {}, {}, {}
local canEdit = false
local catalog = {
    {
        resource = 'sample', revision = 1,
        schema = {
            kind = 'object', fields = {
                enabled = { kind = 'boolean', path = { 'enabled' }, scope = 'shared', live = true },
                webhook = { kind = 'string', path = { 'webhook' }, scope = 'server', sensitive = true },
            },
        },
    },
}
local configRead = {
    resource = 'sample', revision = 1,
    schema = catalog[1].schema,
    configured = { enabled = true, webhook = 'https://secret.invalid' },
    values = { enabled = false, webhook = 'https://secret.invalid' },
}

Kora = { lang = testLang,
    callback = { register = function(name, handler) callbacks[name] = handler end },
    commands = { add = function(name, _, _, _, handler, options) commands[name] = { handler = handler, options = options } end },
    config = {
        catalog = function() return catalog end,
        read = function(resource)
            equal(resource, 'sample', 'read resource')
            return configRead
        end,
        commit = function(resource, request)
            equal(resource, 'sample', 'commit resource')
            return { ok = true, revision = request.revision + 1, applied = true, restartRequired = false }
        end,
        reset = function(resource, request)
            equal(resource, 'sample', 'reset resource')
            return { ok = true, revision = request.revision + 1, applied = false, restartRequired = true }
        end,
    },
}
Admin = {
    checkLevel = function() return canEdit end,
    log = function(source, action, _, details)
        audits[#audits + 1] = { source = source, action = action, details = details }
    end,
}
function TriggerClientEvent() end

dofile('server/config_editor.lua')

test('the configuration catalog is owner-gated', function()
    local value, err = callbacks['kora_admin:configCatalog'](12)
    equal(value, nil, 'unprivileged catalog must be hidden')
    equal(err, 'permission denied', 'unprivileged reason')

    canEdit = true
    value = callbacks['kora_admin:configCatalog'](12)
    equal(value[1].resource, 'sample', 'owner catalog entry')
    equal(value[1].schema.fields.webhook, nil, 'sensitive schema is excluded')
end)

test('reads remove sensitive saved and running values', function()
    local entry = callbacks['kora_admin:configRead'](12, 'sample')
    truthy(entry, 'owner can read the resource')
    equal(entry.configured.webhook, nil, 'saved secret removed')
    equal(entry.values.webhook, nil, 'running secret removed')
    equal(entry.schema.fields.webhook, nil, 'secret metadata removed')
end)

test('commits and resets are audited with their application status', function()
    local committed = callbacks['kora_admin:configCommit'](12, {
        resource = 'sample', path = { 'enabled' }, value = false, revision = 1,
    })
    truthy(committed.ok, 'commit result')
    equal(audits[#audits].action, 'config.commit', 'commit audit action')
    equal(audits[#audits].details.applied, true, 'commit live status')

    local reset = callbacks['kora_admin:configReset'](12, {
        resource = 'sample', path = { 'enabled' }, revision = 2,
    })
    truthy(reset.ok, 'reset result')
    equal(audits[#audits].action, 'config.reset', 'reset audit action')
    equal(audits[#audits].details.restartRequired, true, 'reset restart status')
end)

test('the command uses the configuration-editor owner role', function()
    equal(commands.config.options.permission, Config.configEditor.level, 'config command permission')
end)

print(('kora_admin config editor: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
