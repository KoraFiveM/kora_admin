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
local notices, logs = {}, {}
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

Kora = {
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
        single = function(_, params) return copy(reports[tonumber(params[1])]) end,
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
        update = function(sql, params)
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
    players[8] = { citizenid = 'STAFF2', name = 'Support Two' }

    local function targets()
        local list = {}
        for _, push in ipairs(pushes) do
            equal(push.name, 'qbadmin:client:reportChanged', 'push event name')
            list[#list + 1] = push.target .. ':' .. tostring(push.args[1])
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

print(('qbadmin report store: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
