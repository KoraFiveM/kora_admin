-- Persistent player reports and their conversation/status lifecycle. Commands
-- and the admin NUI both call this one store so typed and menu-driven actions
-- have identical validation, notifications, and audit history.

Admin.reportCooldowns = Admin.reportCooldowns or {}

local VALID_STATUSES = { open = true, claimed = true, resolved = true, dismissed = true }

local function cleanMessage(value)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    return value:sub(1, Config.reports.maxMessageLength)
end

local function typeDefinition(typeId)
    if type(typeId) ~= 'string' then return nil end
    typeId = typeId:lower()
    for _, definition in ipairs(Config.reports.types) do
        if definition.id == typeId then return definition end
    end
end

local function categoryLabel(typeId)
    local definition = typeDefinition(typeId)
    return definition and definition.label or tostring(typeId or '-')
end

---One plain line of report text: control characters and line breaks collapse to
---single spaces and the result is cut to `max` characters. Markup is left as-is
---(the app shell renders text, never HTML); chat output goes through chatSafe.
---@param message any
---@param max integer
---@return string
function Admin.reportSubject(message, max)
    local text = tostring(message or ''):gsub('%c+', ' '):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
    if #text > max then text = text:sub(1, max - 1):gsub('%s+$', '') .. '…' end
    return text
end

---@param seconds number|nil
---@return string
function Admin.formatReportAge(seconds)
    seconds = tonumber(seconds)
    if not seconds then return '-' end
    seconds = math.max(0, math.floor(seconds))
    if seconds < 60 then return seconds .. 's' end
    if seconds < 3600 then return (seconds // 60) .. 'm' end
    if seconds < 86400 then return (seconds // 3600) .. 'h' end
    return (seconds // 86400) .. 'd'
end

---Chat renders what it is given, so angle brackets in player text are swapped
---for look-alike characters before a report is echoed there.
---@param text string
---@return string
local function chatSafe(text)
    return (text:gsub('<', '‹'):gsub('>', '›'))
end

---One readable chat line per report: id, status, category, reporter, subject, age.
---@param rows table[]
---@return string
function Admin.formatReportList(rows)
    local lines = {}
    for _, row in ipairs(rows) do
        lines[#lines + 1] = chatSafe(('#%s [%s] %s · %s%s — %s (%s)'):format(
            row.id, row.status, row.category or categoryLabel(row.type), Admin.reportSubject(row.reporter_name, 24),
            row.claimed_by_name and (' → ' .. Admin.reportSubject(row.claimed_by_name, 24)) or '',
            row.subject or Admin.reportSubject(row.message, 60), row.age or '-'))
    end
    return table.concat(lines, '\n')
end

local function reportTarget(row)
    return {
        citizenid = row.reporter_citizenid,
        license = row.reporter_license,
        name = row.reporter_name,
    }
end

local function actorIdentity(src)
    if Admin.actorIdentity then return Admin.actorIdentity(src) end
    if src == 0 then return nil, 'console' end
    return exports.kora_core:primary(src), GetPlayerName(src) or ('unknown(%d)'):format(src)
end

---Find the report's author in the current player list without trusting the
---stored server id, which can be reused by a different player after reconnect.
---@param row table
---@return integer|nil
function Admin.reporterSource(row)
    for _, playerSrc in ipairs(exports.kora_core:getPlayers()) do
        local data = exports.kora_core:getPlayer(playerSrc)
        if data and row.reporter_citizenid and data.citizenid == row.reporter_citizenid then return playerSrc end
        if row.reporter_license and exports.kora_core:primary(playerSrc) == row.reporter_license then return playerSrc end
    end
end

local function eachStaff(fn)
    for _, playerSrc in ipairs(exports.kora_core:getPlayers()) do
        if Admin.checkLevel(playerSrc, Config.reports.staffLevel) then fn(playerSrc) end
    end
end

local function notifyStaff(payload)
    eachStaff(function(playerSrc) Kora.notify.send(playerSrc, payload) end)
end

---Tell staff clients that report `id` changed (new report, reply, claim, status)
---so an open Reports screen reloads it. The staff member who made the change
---always gets the push, which is what refreshes their own conversation after
---"Reply to Reporter"; everyone else only when Config.reports.liveUpdates is on.
---@param id any
---@param actor integer|nil
local function broadcastReportChange(id, actor)
    eachStaff(function(playerSrc)
        if playerSrc == actor or Config.reports.liveUpdates then
            TriggerClientEvent('qbadmin:client:reportChanged', playerSrc, id)
        end
    end)
end

local function notifyReporter(row, payload)
    local src = Admin.reporterSource(row)
    if src then Kora.notify.send(src, payload) end
end

---@param src integer
---@param typeId string
---@param message string
---@return table|nil report
---@return string|nil err
function Admin.createReport(src, typeId, message)
    if src == 0 then return nil, 'reports must be submitted by a player' end
    local definition = typeDefinition(typeId)
    if not definition then return nil, 'invalid report type' end
    message = cleanMessage(message)
    if not message then return nil, 'report message required' end

    local now = os.time()
    local retryAt = Admin.reportCooldowns[src]
    if retryAt and retryAt > now then
        return nil, ('wait %d seconds before opening another report'):format(retryAt - now)
    end

    local data = exports.kora_core:getPlayer(src)
    if not data then return nil, 'you are not logged in' end
    local reporterName = data.name or GetPlayerName(src) or ('unknown(%d)'):format(src)
    local id, dbErr = Kora.sql.insert(
        'INSERT INTO `admin_reports` (`type`,`reporter_source`,`reporter_citizenid`,`reporter_license`,`reporter_name`,`message`) VALUES (?,?,?,?,?,?)',
        {
            definition.id, src, data.citizenid or Kora.sql.NULL,
            exports.kora_core:primary(src) or Kora.sql.NULL, reporterName, message,
        }
    )
    if not id then return nil, dbErr or 'could not save report' end

    Admin.reportCooldowns[src] = now + Config.reports.cooldownSeconds
    local report = Admin.getReport(id)
    notifyStaff({
        title = ('New %s report #%s'):format(definition.label, id),
        message = ('%s: %s'):format(reporterName, message),
        type = definition.id == 'exploit' and 'error' or 'info',
    })
    broadcastReportChange(id, src)
    return report or { id = id, type = definition.id, status = 'open', reporter_name = reporterName, message = message }
end

---@param id any
---@return table|nil
function Admin.getReport(id)
    id = Admin.finiteNumber(id, 1, nil, true)
    if not id then return nil end
    local row = Kora.sql.single('SELECT * FROM `admin_reports` WHERE `id` = ? LIMIT 1', { id })
    if row then
        row.reporter_source = Admin.reporterSource(row)
        row.category = categoryLabel(row.type)
    end
    return row
end

---@param id any
---@return table[]
function Admin.getReportMessages(id)
    id = Admin.finiteNumber(id, 1, nil, true)
    if not id then return {} end
    return Kora.sql.query(
        'SELECT `id`,`author_name`,`author_role`,`message`,`created_at` FROM `admin_report_messages` WHERE `report_id` = ? ORDER BY `created_at`,`id`',
        { id }
    ) or {}
end

---@param filters table|nil
---@return table[]
function Admin.queryReports(filters)
    filters = filters or {}
    local where, params = {}, {}
    if filters.status and filters.status ~= 'all' and VALID_STATUSES[filters.status] then
        where[#where + 1] = '`status` = ?'
        params[#params + 1] = filters.status
    end
    if filters.type and filters.type ~= 'all' and typeDefinition(filters.type) then
        where[#where + 1] = '`type` = ?'
        params[#params + 1] = filters.type
    end
    if filters.reporter and filters.reporter ~= '' then
        where[#where + 1] = '(`reporter_citizenid` = ? OR `reporter_license` = ? OR `reporter_name` LIKE ?)'
        params[#params + 1] = filters.reporter
        params[#params + 1] = filters.reporter
        params[#params + 1] = '%' .. filters.reporter .. '%'
    end

    -- Exact reporter licence: how /reports limits non-staff to their own reports.
    if filters.license then
        where[#where + 1] = '`reporter_license` = ?'
        params[#params + 1] = filters.license
    end

    local page = math.max(1, math.floor(tonumber(filters.page) or 1))
    local sql = 'SELECT `id`,`type`,`status`,`reporter_name`,`claimed_by_name`,`message`,`created_at`,`updated_at`,UNIX_TIMESTAMP(`created_at`) AS `created_epoch` FROM `admin_reports`'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY FIELD(`status`,\'open\',\'claimed\',\'resolved\',\'dismissed\'), `updated_at` DESC LIMIT ? OFFSET ?'
    params[#params + 1] = Config.reports.pageSize
    params[#params + 1] = (page - 1) * Config.reports.pageSize
    local rows = Kora.sql.query(sql, params) or {}
    local now = os.time()
    for _, row in ipairs(rows) do
        row.category = categoryLabel(row.type)
        row.subject = Admin.reportSubject(row.message, 60)
        row.age = Admin.formatReportAge(tonumber(row.created_epoch) and now - tonumber(row.created_epoch))
    end
    return rows
end

local function canRead(src, row)
    if src == 0 or Admin.checkLevel(src, Config.reports.staffLevel) then return true, 'staff' end
    local license = exports.kora_core:primary(src)
    if license and row.reporter_license == license then return true, 'player' end
    return false
end

---@param src integer
---@param id any
---@param message string
---@return boolean
---@return string|nil
function Admin.replyToReport(src, id, message)
    local row = Admin.getReport(id)
    if not row then return false, 'report not found' end
    local allowed, role = canRead(src, row)
    if not allowed then return false, 'you cannot reply to that report' end
    if row.status == 'resolved' or row.status == 'dismissed' then return false, 'reopen the report before replying' end
    message = cleanMessage(message)
    if not message then return false, 'reply required' end

    local license, name = actorIdentity(src)
    local inserted, dbErr = Kora.sql.insert(
        'INSERT INTO `admin_report_messages` (`report_id`,`author_license`,`author_name`,`author_role`,`message`) VALUES (?,?,?,?,?)',
        { row.id, license or Kora.sql.NULL, name, role, message }
    )
    if not inserted then return false, dbErr or 'could not save reply' end
    Kora.sql.update('UPDATE `admin_reports` SET `updated_at` = CURRENT_TIMESTAMP WHERE `id` = ?', { row.id })

    if role == 'staff' then
        notifyReporter(row, { title = ('Report #%s reply'):format(row.id), message = message, type = 'info' })
        Admin.log(src, 'report_reply', reportTarget(row), { reportId = row.id })
    else
        notifyStaff({ title = ('Report #%s updated'):format(row.id), message = ('%s: %s'):format(name, message), type = 'info' })
    end
    broadcastReportChange(row.id, src)
    return true
end

---@param src integer
---@param id any
---@return boolean
---@return string|nil
function Admin.claimReport(src, id)
    if src ~= 0 and not Admin.checkLevel(src, Config.reports.staffLevel) then return false, 'permission denied' end
    local row = Admin.getReport(id)
    if not row then return false, 'report not found' end
    if row.status == 'resolved' or row.status == 'dismissed' then return false, 'reopen the report before claiming it' end
    local license, name = actorIdentity(src)
    local updated, dbErr = Kora.sql.update(
        'UPDATE `admin_reports` SET `status` = \'claimed\',`claimed_by_license` = ?,`claimed_by_name` = ? WHERE `id` = ?',
        { license or Kora.sql.NULL, name, row.id }
    )
    if updated == nil then return false, dbErr or 'could not claim report' end
    Admin.log(src, 'report_claim', reportTarget(row), { reportId = row.id })
    notifyReporter(row, { title = ('Report #%s claimed'):format(row.id), message = ('%s is handling your report.'):format(name), type = 'info' })
    broadcastReportChange(row.id, src)
    return true
end

---@param src integer
---@param id any
---@param status 'resolved'|'dismissed'|'open'
---@param note string|nil
---@return boolean
---@return string|nil
function Admin.setReportStatus(src, id, status, note)
    if src ~= 0 and not Admin.checkLevel(src, Config.reports.staffLevel) then return false, 'permission denied' end
    if status ~= 'resolved' and status ~= 'dismissed' and status ~= 'open' then return false, 'invalid report status' end
    local row = Admin.getReport(id)
    if not row then return false, 'report not found' end
    note = cleanMessage(note)

    local sql, params
    if status == 'open' then
        sql = 'UPDATE `admin_reports` SET `status` = \'open\',`claimed_by_license` = NULL,`claimed_by_name` = NULL,`resolution` = NULL,`closed_at` = NULL WHERE `id` = ?'
        params = { row.id }
    else
        sql = 'UPDATE `admin_reports` SET `status` = ?,`resolution` = ?,`closed_at` = CURRENT_TIMESTAMP WHERE `id` = ?'
        params = { status, note or Kora.sql.NULL, row.id }
    end
    local updated, dbErr = Kora.sql.update(sql, params)
    if updated == nil then return false, dbErr or 'could not update report' end

    local _, actorName = actorIdentity(src)
    Admin.log(src, 'report_' .. status, reportTarget(row), { reportId = row.id, note = note })
    notifyReporter(row, {
        title = ('Report #%s %s'):format(row.id, status),
        message = note or (status == 'open' and ('Reopened by %s'):format(actorName) or ('Updated by %s'):format(actorName)),
        type = status == 'dismissed' and 'error' or 'info',
    })
    broadcastReportChange(row.id, src)
    return true
end

AddEventHandler('playerDropped', function()
    Admin.reportCooldowns[source] = nil
end)
