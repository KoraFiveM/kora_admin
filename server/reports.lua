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

local function reportTarget(row)
    return {
        citizenid = row.reporter_citizenid,
        license = row.reporter_license,
        name = row.reporter_name,
    }
end

local function actorIdentity(src)
    if src == 0 then return nil, 'console' end
    return exports.qbcore:primary(src), GetPlayerName(src) or ('unknown(%d)'):format(src)
end

---Find the report's author in the current player list without trusting the
---stored server id, which can be reused by a different player after reconnect.
---@param row table
---@return integer|nil
function Admin.reporterSource(row)
    for _, playerSrc in ipairs(exports.qbcore:getPlayers()) do
        local data = exports.qbcore:getPlayer(playerSrc)
        if data and row.reporter_citizenid and data.citizenid == row.reporter_citizenid then return playerSrc end
        if row.reporter_license and exports.qbcore:primary(playerSrc) == row.reporter_license then return playerSrc end
    end
end

local function notifyStaff(payload)
    for _, playerSrc in ipairs(exports.qbcore:getPlayers()) do
        if Admin.checkLevel(playerSrc, Config.reports.staffLevel) then QB.notify.send(playerSrc, payload) end
    end
end

local function notifyReporter(row, payload)
    local src = Admin.reporterSource(row)
    if src then QB.notify.send(src, payload) end
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

    local data = exports.qbcore:getPlayer(src)
    if not data then return nil, 'you are not logged in' end
    local reporterName = data.name or GetPlayerName(src) or ('unknown(%d)'):format(src)
    local id, dbErr = QB.sql.insert(
        'INSERT INTO `admin_reports` (`type`,`reporter_source`,`reporter_citizenid`,`reporter_license`,`reporter_name`,`message`) VALUES (?,?,?,?,?,?)',
        {
            definition.id, src, data.citizenid or QB.sql.NULL,
            exports.qbcore:primary(src) or QB.sql.NULL, reporterName, message,
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
    return report or { id = id, type = definition.id, status = 'open', reporter_name = reporterName, message = message }
end

---@param id any
---@return table|nil
function Admin.getReport(id)
    id = Admin.finiteNumber(id, 1, nil, true)
    if not id then return nil end
    local row = QB.sql.single('SELECT * FROM `admin_reports` WHERE `id` = ? LIMIT 1', { id })
    if row then row.reporter_source = Admin.reporterSource(row) end
    return row
end

---@param id any
---@return table[]
function Admin.getReportMessages(id)
    id = Admin.finiteNumber(id, 1, nil, true)
    if not id then return {} end
    return QB.sql.query(
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

    local page = math.max(1, math.floor(tonumber(filters.page) or 1))
    local sql = 'SELECT `id`,`type`,`status`,`reporter_name`,`claimed_by_name`,`message`,`created_at`,`updated_at` FROM `admin_reports`'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY FIELD(`status`,\'open\',\'claimed\',\'resolved\',\'dismissed\'), `updated_at` DESC LIMIT ? OFFSET ?'
    params[#params + 1] = Config.reports.pageSize
    params[#params + 1] = (page - 1) * Config.reports.pageSize
    return QB.sql.query(sql, params) or {}
end

local function canRead(src, row)
    if src == 0 or Admin.checkLevel(src, Config.reports.staffLevel) then return true, 'staff' end
    local license = exports.qbcore:primary(src)
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
    local inserted, dbErr = QB.sql.insert(
        'INSERT INTO `admin_report_messages` (`report_id`,`author_license`,`author_name`,`author_role`,`message`) VALUES (?,?,?,?,?)',
        { row.id, license or QB.sql.NULL, name, role, message }
    )
    if not inserted then return false, dbErr or 'could not save reply' end
    QB.sql.update('UPDATE `admin_reports` SET `updated_at` = CURRENT_TIMESTAMP WHERE `id` = ?', { row.id })

    if role == 'staff' then
        notifyReporter(row, { title = ('Report #%s reply'):format(row.id), message = message, type = 'info' })
        Admin.log(src, 'report_reply', reportTarget(row), { reportId = row.id })
    else
        notifyStaff({ title = ('Report #%s updated'):format(row.id), message = ('%s: %s'):format(name, message), type = 'info' })
    end
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
    local updated, dbErr = QB.sql.update(
        'UPDATE `admin_reports` SET `status` = \'claimed\',`claimed_by_license` = ?,`claimed_by_name` = ? WHERE `id` = ?',
        { license or QB.sql.NULL, name, row.id }
    )
    if updated == nil then return false, dbErr or 'could not claim report' end
    Admin.log(src, 'report_claim', reportTarget(row), { reportId = row.id })
    notifyReporter(row, { title = ('Report #%s claimed'):format(row.id), message = ('%s is handling your report.'):format(name), type = 'info' })
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
        params = { status, note or QB.sql.NULL, row.id }
    end
    local updated, dbErr = QB.sql.update(sql, params)
    if updated == nil then return false, dbErr or 'could not update report' end

    local _, actorName = actorIdentity(src)
    Admin.log(src, 'report_' .. status, reportTarget(row), { reportId = row.id, note = note })
    notifyReporter(row, {
        title = ('Report #%s %s'):format(row.id, status),
        message = note or (status == 'open' and ('Reopened by %s'):format(actorName) or ('Updated by %s'):format(actorName)),
        type = status == 'dismissed' and 'error' or 'info',
    })
    return true
end

AddEventHandler('playerDropped', function()
    Admin.reportCooldowns[source] = nil
end)
