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

local commands, responses, events, logs = {}, {}, {}, {}
local created, reply
QB = {
    commands = { add = function(name, _, _, _, handler, options)
        commands[name] = { handler = handler, options = options }
    end },
}
Admin = {
    checkLevel = function() return true end,
    createReport = function(source, type_, message)
        created = { source = source, type = type_, message = message }
        return { id = 42 }
    end,
    getReport = function() return nil end,
    getReportMessages = function() return {} end,
    queryReports = function() return {} end,
    replyToReport = function(source, id, message)
        reply = { source = source, id = id, message = message }
        return true
    end,
    claimReport = function() return true end,
    setReportStatus = function() return true end,
    respond = function(source, ok, message)
        responses[#responses + 1] = { source = source, ok = ok, message = message }
    end,
    chat = function() end,
    resolveTarget = function(_, id)
        return tonumber(id), { citizenid = 'CID', license = 'license:test', name = 'Target' }
    end,
    log = function(source, action, target, details)
        logs[#logs + 1] = { source = source, action = action, target = target, details = details }
    end,
}
exports = {
    qbcore = { primary = function() return 'license:test' end },
    qbclothing = { OpenAdminSession = function(_, target, service)
        events[#events + 1] = { name = 'appearance', target = target, service = service }
        return true
    end },
}
function TriggerClientEvent(name, target, ...)
    events[#events + 1] = { name = name, target = target, args = { ... } }
end
function GetResourceState(name) return name == 'qbclothing' and 'started' or 'missing' end
function GetPlayerName() return 'Staff' end
function GetPlayerPed() return 1 end
function GetEntityCoords() return { x = 1, y = 2, z = 3 } end

dofile('server/commands/reports.lua')
dofile('server/commands/teleport.lua')
dofile('server/commands/appearance.lua')

test('report categories are comprehensive and include bugs', function()
    local types = {}
    for _, definition in ipairs(Config.reports.types) do types[definition.id] = true end
    truthy(types.player and types.bug and types.exploit and types.gameplay and types.question and types.other,
        'expected player, bug, exploit, gameplay, question, and other categories')
end)

test('players can submit and reply while staff lifecycle commands stay gated', function()
    equal(commands.report.options.permission, 'user', '/report permission')
    equal(commands.reportreply.options.permission, 'user', '/reportreply permission')
    equal(commands.reportclaim.options.permission, Config.reports.staffLevel, '/reportclaim permission')
    equal(commands.reportresolve.options.permission, Config.reports.staffLevel, '/reportresolve permission')

    commands.report.handler(9, { 'bug', 'Inventory', 'button', 'is', 'stuck' })
    equal(created.type, 'bug', 'report type')
    equal(created.message, 'Inventory button is stuck', 'report message retains spaces')

    commands.reportreply.handler(9, { '42', 'It', 'still', 'happens' })
    equal(reply.id, '42', 'reply report id')
    equal(reply.message, 'It still happens', 'reply retains spaces')
end)

test('Send Back relays the selected player to their own teleport history', function()
    commands.sendback.handler(7, { '12' })
    local event = events[#events]
    equal(event.name, 'qbadmin:client:tpback', 'send-back event')
    equal(event.target, 12, 'send-back target')
    equal(logs[#logs].action, 'sendback', 'send-back audit action')
end)

test('remote appearance commands call qbclothing with the selected service', function()
    commands.clothingmenu.handler(7, { '12' })
    equal(events[#events].service, 'clothing', 'clothing service')
    commands.barbermenu.handler(7, { '12' })
    equal(events[#events].service, 'barber', 'barber service')
    commands.tattoomenu.handler(7, { '12' })
    equal(events[#events].service, 'tattoo', 'tattoo service')
    equal(commands.tattoomenu.options.permission, 'admin', 'remote appearance permission')
end)

print(('qbadmin reports/player tools: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
