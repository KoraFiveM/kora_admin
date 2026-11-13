local testLang = dofile('test/support/lang.lua')
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
Config.reports.cooldownSeconds = 30

local reports, messages, nextReport, nextMessage = {}, {}, 1, 1
local notices, logs, reads, delivered = {}, {}, {}, {}
local clock = 0
function GetGameTimer() return clock end
local lastQuery
local players = {
    [7] = { citizenid = 'STAFF', name = 'Support' },
    [9] = { citizenid = 'CITIZEN', name = 'Citizen' },
    [10] = { citizenid = 'OTHER', name = 'Other' },
}

local function copy(row)
    if not row then return nil end
    local out = {}
    for key, value in pairs(row) do out[key] = value end
    return out
end

Kora = { lang = testLang,
    sql = {
        NULL = '<NULL>',
        insert = function(sql, params)
            if sql:find('`admin_reports`', 1, true) then
                local id = nextReport; nextReport = nextReport + 1
                reports[id] = {
                    id = id, type = params[1], status = 'open', reporter_source = params[2],
                    reporter_citizenid = params[3], reporter_license = params[4], reporter_name = params[5],
                    message = params[6], created_at = 'now', updated_at = 'now',
                }
                return id
            end
            local id = nextMessage; nextMessage = nextMessage + 1
            messages[#messages + 1] = {
                id = id, report_id = params[1], author_license = params[2], author_name = params[3],
                author_role = params[4], message = params[5], created_at = 'later',
            }
            return id
        end,
        single = function(sql, params)
            if sql:find('`admin_report_reads`', 1, true) then
                if sql:find('COUNT(*)', 1, true) then
                    -- other side's progress for the reporter: every reader but the reporter and the '@staff' pseudo reader
                    local n, newest = 0, nil
                    for key, value in pairs(reads) do
                        local reportId, license = key:match('^(%d+)|(.+)$')
                        if tonumber(reportId) == params[1] and license ~= params[2] and license ~= params[3] then
                            n, newest = n + 1, math.max(newest or 0, value)
                        end
                    end
                    return { n = n, newest = newest }
                end
                local key = tostring(params[1]) .. '|' .. tostring(params[2])
                if reads[key] == nil then return nil end
                return { last_message_id = reads[key], delivered_message_id = delivered[key] }
            end
            return copy(reports[tonumber(params[1])])
        end,
        query = function(sql, params)
            lastQuery = { sql = sql, params = params }
            if sql:find('`admin_report_messages`', 1, true) then
                local out = {}
                for _, row in ipairs(messages) do if row.report_id == tonumber(params[1]) then out[#out + 1] = copy(row) end end
                return out
            end
            local out = {}
            for _, row in pairs(reports) do out[#out + 1] = copy(row) end
            return out
        end,
        scalar = function(sql, params)
            if sql:find('`admin_report_reads`', 1, true) then
                local key = tostring(params[1]) .. '|' .. tostring(params[2])
                if sql:find('SELECT `delivered_message_id`', 1, true) then return delivered[key] end
                return reads[key]
            end
        end,
        update = function(sql, params)
            if sql:find('`admin_report_reads`', 1, true) then
                local key = tostring(params[1]) .. '|' .. tostring(params[2])
                if sql:find('SELECT MAX', 1, true) then
                    -- markReportDelivered: the newest message of the report reached this reader
                    local newest = 0
                    for _, row in ipairs(messages) do if row.report_id == params[1] then newest = math.max(newest, row.id) end end
                    reads[key] = reads[key] or 0
                    delivered[key] = math.max(delivered[key] or 0, newest)
                else
                    -- markReportRead: seen up to params[3], which also counts as delivered
                    reads[key] = math.max(reads[key] or 0, params[3])
                    delivered[key] = math.max(delivered[key] or 0, params[4])
                end
                return 1
            end
            local id = tonumber(params[#params])
            local row = reports[id]
            if not row then return 0 end
            if sql:find("`status` = 'claimed'", 1, true) then
                row.status, row.claimed_by_license, row.claimed_by_name = 'claimed', params[1], params[2]
            elseif sql:find("`status` = 'open'", 1, true) then
                row.status, row.claimed_by_license, row.claimed_by_name, row.resolution = 'open', nil, nil, nil
            elseif sql:find('`status` = ?', 1, true) then
                row.status, row.resolution = params[1], params[2]
            end
            return 1
        end,
    },
    notify = { send = function(target, payload) notices[#notices + 1] = { target = target, payload = payload } end },
}
exports = { kora_core = {
    getPlayers = function() return { 7, 9, 10 } end,
    getPlayer = function(_, src) return players[src] end,
    primary = function(_, src) return 'license:' .. tostring(src) end,
} }
Admin = {
    finiteNumber = function(value, minimum, maximum, integer)
        local number = tonumber(value)
        if not number or (minimum and number < minimum) or (maximum and number > maximum) then return nil end
        if integer and number ~= math.floor(number) then return nil end
        return number
    end,
    checkLevel = function(src) return src == 7 end,
    log = function(src, action, target, details)
        logs[#logs + 1] = { src = src, action = action, target = target, details = details }
    end,
}
function GetPlayerName(src) return players[src] and players[src].name end
local pushes = {}
function TriggerClientEvent(name, target, ...) pushes[#pushes + 1] = { name = name, target = target, args = { ... } } end
function AddEventHandler() end
function SetTimeout() end

dofile('server/reports.lua')

test('a valid report persists its type, reporter, and message', function()
    local report = assert(Admin.createReport(9, 'BUG', '  Inventory will not open  '))
    equal(report.id, 1, 'report id')
    equal(report.type, 'bug', 'normalized report type')
    equal(report.reporter_name, 'Citizen', 'reporter name')
    equal(report.message, 'Inventory will not open', 'trimmed report message')
    truthy(#notices > 0, 'staff should be notified')
end)

test('submission categories and cooldown are enforced', function()
    local report, err = Admin.createReport(10, 'not-a-type', 'hello')
    equal(report, nil, 'invalid type rejected')
    truthy(err:find('invalid', 1, true), 'invalid type reason')
    report, err = Admin.createReport(9, 'bug', 'second report immediately')
    equal(report, nil, 'cooldown rejected')
    truthy(err:find('wait', 1, true), 'cooldown reason')
end)

test('report ownership protects player replies while staff can manage reports', function()
    local ok, err = Admin.replyToReport(10, 1, 'I should not see this')
    equal(ok, false, 'unrelated player reply rejected')
    truthy(err:find('cannot reply', 1, true), 'ownership rejection reason')

    equal(Admin.replyToReport(9, 1, 'More detail'), true, 'reporter reply')
    equal(Admin.claimReport(7, 1), true, 'staff claim')
    equal(reports[1].status, 'claimed', 'claimed status')
    equal(Admin.replyToReport(7, 1, 'We are checking'), true, 'staff reply')
    equal(Admin.setReportStatus(7, 1, 'resolved', 'Fixed after restart'), true, 'staff resolve')
    equal(reports[1].status, 'resolved', 'resolved status')
    equal(reports[1].resolution, 'Fixed after restart', 'resolution stored')
    truthy(#logs >= 3, 'staff actions should be audited')
end)

test('report lists are one readable line each, with markup neutralised for chat', function()
    equal(Admin.reportSubject('  line one\n\nline <b>two</b>\t ', 60), 'line one line <b>two</b>', 'whitespace collapsed')
    equal(Admin.reportSubject(('x'):rep(100), 10), 'xxxxxxxxx…', 'long subjects are cut')
    equal(Admin.formatReportAge(45), '45s', 'seconds')
    equal(Admin.formatReportAge(7200), '2h', 'hours')
    equal(Admin.formatReportAge(3 * 86400), '3d', 'days')
    equal(Admin.formatReportAge(nil), '-', 'unknown age')

    local text = Admin.formatReportList({
        { id = 4, status = 'open', type = 'bug', reporter_name = 'mas maul', message = 'm' },
        { id = 1, status = 'dismissed', type = 'player', reporter_name = 'Luffy', claimed_by_name = 'Staff',
            message = "<meta http-equiv='refresh' content='5; url=https://example.test/'>\nsecond line" },
    })
    local lines = {}
    for line in text:gmatch('[^\n]+') do lines[#lines + 1] = line end
    equal(#lines, 2, 'one line per report')
    equal(lines[1], '#4 [open] Bug · mas maul — m (-)', 'id, status, category, reporter, subject, age')
    truthy(not text:find('<', 1, true) and not text:find('>', 1, true), 'no raw angle brackets reach chat')
end)

test('queryReports can limit a listing to one reporter licence and adds age/subject/category', function()
    Admin.queryReports({ status = 'all', license = 'license:9' })
    truthy(lastQuery.sql:find('`reporter_license` = ?', 1, true), 'licence filter in SQL')
    local found
    for _, param in ipairs(lastQuery.params) do if param == 'license:9' then found = true end end
    truthy(found, 'licence passed as a bound parameter')
    local rows = Admin.queryReports({ status = 'all' })
    truthy(rows[1].category and rows[1].subject and rows[1].age, 'rows are decorated for list views')
end)

test('every report change is pushed to the staff viewing reports, and always to the actor', function()
    pushes = {}
    local staff = { [7] = true, [8] = true }
    local previousPlayers, previousCheck = exports.kora_core.getPlayers, Admin.checkLevel
    exports.kora_core.getPlayers = function() return { 7, 8, 9, 10 } end
    Admin.checkLevel = function(src) return staff[src] == true end
    Admin.reportCooldowns = {}
    Admin.reportChatSends = {}
    players[8] = { citizenid = 'STAFF2', name = 'Support Two' }

    local function targets()
        local list = {}
        for _, push in ipairs(pushes) do
            if push.name == 'kora_admin:client:reportChanged' then
                list[#list + 1] = push.target .. ':' .. tostring(push.args[1])
            else
                equal(push.name, 'kora_admin:client:myReportChanged', 'push event name')
                equal(push.target, 9, 'reporter pushes only reach the reporter')
            end
        end
        pushes = {}
        table.sort(list)
        return table.concat(list, ',')
    end

    local report = assert(Admin.createReport(9, 'bug', 'Live update check'))
    equal(targets(), ('7:%s,8:%s'):format(report.id, report.id), 'a new report reaches every staff member, not players')
    equal(Admin.replyToReport(7, report.id, 'Staff reply'), true, 'staff reply')
    equal(targets(), ('7:%s,8:%s'):format(report.id, report.id), 'a staff reply reaches the sender and other staff')
    equal(Admin.replyToReport(9, report.id, 'Reporter reply'), true, 'reporter reply')
    equal(targets(), ('7:%s,8:%s'):format(report.id, report.id), 'a reporter reply reaches staff')
    equal(Admin.claimReport(8, report.id), true, 'claim')
    equal(targets(), ('7:%s,8:%s'):format(report.id, report.id), 'a claim reaches staff')
    equal(Admin.setReportStatus(8, report.id, 'resolved', 'Done'), true, 'resolve')
    equal(targets(), ('7:%s,8:%s'):format(report.id, report.id), 'a status change reaches staff')
    equal(Admin.replyToReport(7, report.id, 'Too late'), false, 'a closed report rejects replies')
    equal(targets(), '', 'a rejected reply pushes nothing')

    Config.reports.liveUpdates = false
    equal(Admin.setReportStatus(8, report.id, 'open'), true, 'reopen')
    equal(targets(), ('8:%s'):format(report.id), 'with liveUpdates off only the actor is refreshed')
    equal(Admin.replyToReport(7, report.id, 'Back again'), true, 'reply after reopen')
    equal(targets(), ('7:%s'):format(report.id), 'the replying staff member still sees their own reply')
    Config.reports.liveUpdates = true

    exports.kora_core.getPlayers, Admin.checkLevel = previousPlayers, previousCheck
    players[8] = nil
end)

test('live chat: length, rate limit, reporter push instead of toast, and per-reader unread', function()
    Admin.reportCooldowns, Admin.reportChatSends, pushes, notices = {}, {}, {}, {}
    clock = 1000000
    local report = assert(Admin.createReport(9, 'question', 'How do I chat?'))
    notices = {}
    local ok, err = Admin.replyToReport(9, report.id, ('x'):rep(Config.reports.chat.maxLength + 1), { chat = true })
    equal(ok, false, 'an over-long chat message is refused')
    truthy(err:find('too long', 1, true), 'length reason')
    equal(Admin.replyToReport(10, report.id, 'not mine', { chat = true }), false, 'another player cannot post')

    pushes = {}
    equal(Admin.replyToReport(7, report.id, 'Hi <b>there</b>\r\n\n\n\nsecond', { chat = true }), true, 'staff chat reply')
    local stored = messages[#messages].message
    equal(stored, 'Hi <b>there</b>\n\nsecond', 'CRLF and blank-line runs are normalised, text kept as typed')
    local reporterPush
    for _, push in ipairs(pushes) do if push.name == 'kora_admin:client:myReportChanged' then reporterPush = push end end
    truthy(reporterPush and reporterPush.target == 9, 'the reporter is pushed the change')
    equal(reporterPush.args[2].kind, 'reply', 'push kind')
    equal(reporterPush.args[2].author, 'Support', 'staff name in the preview')
    for _, notice in ipairs(notices) do truthy(notice.target ~= 9, 'no server toast for the reporter; their client decides') end

    -- Unread: the reporter has not opened it yet, so the staff reply is unread for them.
    local view = Admin.reportConversation(9, Admin.getReport(report.id), 'player')
    equal(view.reporter_license, nil, 'player view drops identifiers')
    equal(view.messages[#view.messages].unread, true, 'staff reply unread for the reporter')
    view = Admin.reportConversation(9, Admin.getReport(report.id), 'player')
    equal(view.messages[#view.messages].unread, nil, 'opening it marked it read')

    -- Rate limit: 5 per 15s per sender.
    Admin.reportChatSends = {}
    for index = 1, Config.reports.chat.rateLimit.messages do
        equal(Admin.replyToReport(9, report.id, 'msg ' .. index, { chat = true }), true, 'within the limit')
    end
    ok, err = Admin.replyToReport(9, report.id, 'one too many', { chat = true })
    equal(ok, false, 'over the limit')
    truthy(err:find('too quickly', 1, true), 'rate limit reason')
    clock = clock + Config.reports.chat.rateLimit.seconds * 1000 + 1
    equal(Admin.replyToReport(9, report.id, 'after the window', { chat = true }), true, 'the window slides')

    local enabled = Config.reports.chat.enabled
    Config.reports.chat.enabled = false
    pushes, notices = {}, {}
    equal(Admin.replyToReport(7, report.id, 'chat off'), true, 'reply with chat off')
    for _, push in ipairs(pushes) do truthy(push.name ~= 'kora_admin:client:myReportChanged', 'no reporter push with chat off') end
    local toasted
    for _, notice in ipairs(notices) do if notice.target == 9 then toasted = true end end
    truthy(toasted, 'chat off keeps the old reporter toast')
    Config.reports.chat.enabled = enabled
end)

test('chat ticks: sent, then delivered once it reaches the other client, then seen once it is opened', function()
    Admin.reportCooldowns, Admin.reportChatSends, pushes = {}, {}, {}
    clock = clock + 10 * 60 * 1000
    local previousPlayers = exports.kora_core.getPlayers
    local report = assert(Admin.createReport(9, 'question', 'Tick check'))
    local function view(src, role, live) return Admin.reportConversation(src, Admin.getReport(report.id), role, live) end
    local function statusOf(conversation, text)
        for _, message in ipairs(conversation.messages) do if message.message == text then return message.status end end
    end

    -- Staff (7) was online when the report came in: delivered, but nobody has opened it.
    equal(view(9, 'player', true).initial_status, 'delivered', 'the original report reached staff')

    -- Staff reply reaches the online reporter's client; the reporter has not opened it yet.
    equal(Admin.replyToReport(7, report.id, 'first answer', { chat = true }), true, 'staff reply')
    equal(statusOf(view(7, 'staff', true), 'first answer'), 'delivered', 'online reporter: delivered')
    equal(view(7, 'staff', true).initial_status, nil, 'staff views carry no original-report tick')

    -- Reporter opens the conversation (any view of it counts as opening): the staff reply is seen,
    -- staff are pushed to refresh, and ticks only exist on the viewer's own messages.
    pushes = {}
    equal(statusOf(view(9, 'player', false), 'first answer'), nil, 'no tick on the other side\'s message')
    equal(statusOf(view(7, 'staff', true), 'first answer'), 'seen', 'opened by the reporter: seen')
    local pushedStaff
    for _, push in ipairs(pushes) do if push.name == 'kora_admin:client:reportChanged' then pushedStaff = true end end
    truthy(pushedStaff, 'staff windows are told the ticks changed')

    -- Reporter message: delivered until a staff member opens it, then seen (and so is the original report).
    Admin.reportChatSends = {}
    equal(Admin.replyToReport(9, report.id, 'thanks', { chat = true }), true, 'reporter reply')
    equal(statusOf(view(9, 'player', true), 'thanks'), 'delivered', 'staff online: delivered')
    equal(view(9, 'player', true).initial_status, 'seen', 'staff already opened the report, so the original is seen')
    view(7, 'staff', false)
    equal(statusOf(view(9, 'player', true), 'thanks'), 'seen', 'opened by staff: seen')

    -- Offline reporter: the reply stays at one tick until their client receives the list.
    exports.kora_core.getPlayers = function() return { 7, 10 } end
    Admin.reportChatSends = {}
    equal(Admin.replyToReport(7, report.id, 'are you there?', { chat = true }), true, 'staff reply to an offline reporter')
    equal(statusOf(view(7, 'staff', true), 'are you there?'), 'sent', 'offline reporter: sent')
    Admin.markReportDelivered(report.id, 'license:9')
    equal(statusOf(view(7, 'staff', true), 'are you there?'), 'delivered', 'their client got the list: delivered')
    exports.kora_core.getPlayers = previousPlayers
end)

print(('kora_admin report store: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
