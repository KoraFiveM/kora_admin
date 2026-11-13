local testLang = dofile('test/support/lang.lua')
local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 print(('  [PASS] %s'):format(name))
    else failed = failed + 1 print(('  [FAIL] %s -- %s'):format(name, tostring(err))) end
end
local function equal(a, e, m) if a ~= e then error(('%s (expected %s, got %s)'):format(m, tostring(e), tostring(a)), 2) end end

dofile('config.lua')

local commands, responses, events, order = {}, {}, {}, {}
local state, fullRevived, throwing, meta = 'started', {}, false, {}

Kora = {
    commands = { add = function(name, _, _, _, handler) commands[name] = handler end },
    lang = testLang,
}
function AddEventHandler() end
function RegisterNetEvent() end
function GetResourceState() return state end
function TriggerClientEvent(name, target) events[#events + 1] = name order[#order + 1] = 'client' end
exports = {
    kora_core = { setMetaData = function(_, _, key, value) order[#order + 1] = 'meta' meta[#meta + 1] = key .. '=' .. tostring(value) end },
    kora_ambulance = { fullRevive = function(_, src)
        order[#order + 1] = 'full'
        if throwing then error('boom') end
        fullRevived[#fullRevived + 1] = src
        return true
    end },
}
Admin = {
    checkLevel = function() return true end,
    accessCommandAllowed = function() return true end,
    commands = {},
    respond = function(_, ok, message) responses[#responses + 1] = { ok = ok, message = message } end,
    log = function() end,
    resolveTarget = function(_, id) return tonumber(id), { name = 'Target' } end,
}
dofile('server/core.lua')
dofile('server/command_registry.lua')
dofile('server/commands/moderation.lua')
dofile('server/commands/self.lua')

local function reset() responses, events, order, fullRevived, state, throwing, meta = {}, {}, {}, {}, 'started', false, {} end

test('/revive fully revives the target in kora_ambulance after the normal revive', function()
    reset()
    commands.revive(7, { '12' })
    equal(fullRevived[1], 12, 'fullRevive called for the target')
    equal(events[1], 'kora_admin:client:revive', 'existing client revive kept')
    local clientAt, fullAt
    for i, step in ipairs(order) do
        if step == 'client' and not clientAt then clientAt = i end
        if step == 'full' then fullAt = i end
    end
    equal(clientAt ~= nil and fullAt ~= nil and fullAt > clientAt, true, 'fullRevive runs after the existing revive')
    equal(responses[#responses].ok, true, 'success')
end)

test('/selfrevive fully revives the caller', function()
    reset()
    commands.selfrevive(7, {})
    equal(fullRevived[1], 7, 'fullRevive called for the caller')
    equal(events[1], 'kora_admin:client:revive', 'existing client revive kept')
end)

test('servers without kora_ambulance keep the old behaviour', function()
    reset(); state = 'missing'
    commands.revive(7, { '12' }); commands.selfrevive(7, {})
    equal(#fullRevived, 0, 'no export call')
    equal(#events, 2, 'client revives still fire')
    equal(responses[#responses].ok, true, 'success')
end)

test('a failing fullRevive export does not break the command', function()
    reset(); throwing = true
    commands.revive(7, { '12' })
    equal(events[1], 'kora_admin:client:revive', 'client revive already sent')
    equal(responses[#responses].ok, true, 'still reports success')
end)

test('/heal fills hunger and thirst when Config.heal.restoreNeeds is on', function()
    reset()
    commands.heal(7, { '12' })
    equal(events[1], 'kora_admin:client:heal', 'client heal sent')
    equal(table.concat(meta, ','), 'hunger=100,thirst=100', 'needs restored')
end)

test('/heal leaves needs alone when restoreNeeds is off', function()
    reset(); Config.heal.restoreNeeds = false
    commands.heal(7, { '12' })
    Config.heal.restoreNeeds = true
    equal(#meta, 0, 'no needs written')
    equal(events[1], 'kora_admin:client:heal', 'still heals')
end)

test('/revive and /selfrevive leave needs alone when Config.revive.restoreNeeds is off', function()
    reset(); Config.revive.restoreNeeds = false
    commands.revive(7, { '12' }); commands.selfrevive(7, {})
    for _, entry in ipairs(meta) do
        if entry:find('hunger') or entry:find('thirst') then error('needs touched: ' .. entry) end
    end
    Config.revive.restoreNeeds = true
end)

test('/revive restores needs when Config.revive.restoreNeeds is on', function()
    reset(); Config.revive = { restoreNeeds = true }
    commands.revive(7, { '12' })
    Config.revive = { restoreNeeds = true }
    equal(table.concat(meta, ','):find('hunger=100,thirst=100', 1, true) ~= nil, true, 'needs restored')
end)

test('/revive falls back to the legacy Config.HealRestoreNeeds key', function()
    reset(); Config.revive = nil; Config.HealRestoreNeeds = true
    commands.revive(7, { '12' })
    Config.HealRestoreNeeds = nil; Config.revive = { restoreNeeds = true }
    equal(table.concat(meta, ','):find('hunger=100,thirst=100', 1, true) ~= nil, true, 'legacy key honoured')
end)

test('Config.revive.restoreNeeds wins over the legacy key', function()
    reset(); Config.revive = { restoreNeeds = false }; Config.HealRestoreNeeds = true
    commands.revive(7, { '12' })
    Config.revive = { restoreNeeds = true }; Config.HealRestoreNeeds = nil
    for _, entry in ipairs(meta) do
        if entry:find('hunger') or entry:find('thirst') then error('needs touched: ' .. entry) end
    end
end)

print(('-- %d passed, %d failed --'):format(passed, failed))
if failed > 0 then os.exit(1) end
