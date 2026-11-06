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
local isStaff, chats, queries = true, {}, {}
Kora = {
    commands = { add = function(name, _, _, _, handler, options)
        commands[name] = { handler = handler, options = options }
    end },
}
Admin = {
    checkLevel = function() return isStaff end,
    commandContext = function() return nil end,
    reportChat = function()
        return Config.reports.chat and Config.reports.chat.enabled == true and Config.reports.chat or nil
    end,
    chatSafe = function(text) return (text:gsub('<', '‹'):gsub('>', '›')) end,
    getLevel = function() return 'support' end,
    formatReportList = function(rows) return 'LIST:' .. #rows end,
    createReport = function(source, type_, message)
        created = { source = source, type = type_, message = message }
        return { id = 42 }
    end,
    getReport = function() return nil end,
    getReportMessages = function() return {} end,
    queryReports = function(filters) queries[#queries + 1] = filters return { { id = 1 } } end,
    replyToReport = function(source, id, message)
        reply = { source = source, id = id, message = message }
        return true
    end,
    claimReport = function() return true end,
    setReportStatus = function() return true end,
    respond = function(source, ok, message)
        responses[#responses + 1] = { source = source, ok = ok, message = message }
    end,
    chat = function(_, message) chats[#chats + 1] = message end,
    resolveTarget = function(_, id)
        return tonumber(id), { citizenid = 'CID', license = 'license:test', name = 'Target' }
    end,
    log = function(source, action, target, details)
        logs[#logs + 1] = { source = source, action = action, target = target, details = details }
    end,
}
exports = {
    kora_core = { primary = function() return 'license:test' end },
    kora_clothing = { OpenAdminSession = function(_, target, service)
        events[#events + 1] = { name = 'appearance', target = target, service = service }
        return true
    end },
}
function TriggerClientEvent(name, target, ...)
    events[#events + 1] = { name = name, target = target, args = { ... } }
end
function GetResourceState(name) return name == 'kora_clothing' and 'started' or 'missing' end
function GetPlayerName() return 'Staff' end
function GetPlayerPed() return 1 end
function GetEntityCoords() return { x = 1, y = 2, z = 3 } end

dofile('server/command_registry.lua')
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

test('/reports opens the Reports screen for staff and a chat list when ui is off', function()
    equal(commands.reports.options.permission, 'user', '/reports is reachable by players')
    isStaff, events, chats, queries = true, {}, {}, {}
    commands.reports.handler(7, { 'claimed' })
    equal(events[1].name, 'qbadmin:client:openReports', 'staff get the dedicated screen')
    equal(events[1].args[2].status, 'claimed', 'status filter forwarded')
    equal(#queries, 0, 'no chat dump when the screen opens')

    commands.reports.handler(7, {})
    equal(events[2].args[2].status, 'open', 'staff default to open reports')

    Config.reports.command.ui = false
    commands.reports.handler(7, {})
    Config.reports.command.ui = true
    equal(#events, 2, 'ui = false opens no screen')
    equal(chats[1], 'LIST:1', 'chat list used instead')
end)

test('/reports opens My Reports for players when the live chat is on', function()
    isStaff, events, chats, queries = false, {}, {}, {}
    commands.reports.handler(9, { '42' })
    equal(events[1].name, 'qbadmin:client:openMyReports', 'players get their own chat window')
    equal(events[1].args[1], 42, 'an id opens that report (ownership is checked by the callback)')
    equal(#queries, 0, 'no chat dump when the window opens')
    isStaff = true
end)

test('/reports shows non-staff players only their own reports', function()
    isStaff, events, chats, queries = false, {}, {}, {}
    local playerUi = Config.reports.chat.playerUi
    Config.reports.chat.playerUi = false
    commands.reports.handler(9, { 'open' })
    Config.reports.chat.playerUi = playerUi
    equal(#events, 0, 'no staff screen for players')
    equal(queries[1].license, 'license:test', 'query pinned to the caller licence')
    truthy(chats[1]:find('/reportstatus', 1, true), 'points to /reportstatus')
    isStaff = true
end)

print(('qbadmin reports/player tools: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
