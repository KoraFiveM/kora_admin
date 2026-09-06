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

QB = {
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
exports = { qbcore = {
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

print(('qbadmin report store: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
