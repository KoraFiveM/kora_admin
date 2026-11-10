-- Persistent player reports and their conversation/status lifecycle. Commands
-- and the admin NUI both call this one store so typed and menu-driven actions
-- have identical validation, notifications, and audit history.

Admin.reportCooldowns = Admin.reportCooldowns or {}
Admin.reportChatSends = Admin.reportChatSends or {}

---The live-chat settings, or nil when the chat is switched off (or missing from an
---older config.lua), in which case every report screen behaves exactly as before.
---@return table|nil
function Admin.reportChat()
    local chat = Config.reports.chat
    if type(chat) == 'table' and chat.enabled == true then return chat end
end

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
Admin.chatSafe = chatSafe

---Server-formatted message time. Both SQL drivers' date shapes are avoided by
---selecting UNIX_TIMESTAMP(...) and formatting here (FiveM client Lua has no os.date).
---@param epoch any
---@return string|nil
function Admin.formatReportTime(epoch)
    epoch = tonumber(epoch)
    if not epoch then return nil end
    local ok, formatted = pcall(os.date, '!%Y-%m-%d %H:%M', math.floor(epoch))
    return ok and (formatted .. ' UTC') or nil
end

---Chat text: CRLF to LF, control characters other than newline and tab removed,
---runs of blank lines collapsed, outer whitespace trimmed. Markup is kept as typed
---text: AppShell renders it as a text node and chat output goes through chatSafe.
---@param value any
---@return string|nil
function Admin.cleanChatMessage(value)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('\r\n?', '\n'):gsub('[%z\1-\8\11-\31\127]', ''):gsub('\n%s*\n[%s\n]*', '\n\n')
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    return value
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

local function notifyStaff(payload, onlySrc)
    eachStaff(function(playerSrc)
        if not onlySrc or playerSrc == onlySrc then Kora.notify.send(playerSrc, payload) end
    end)
end

---The online staff member who claimed `row`, when the chat is set to notify only them.
---@param row table
---@return integer|nil
local function claimerSource(row)
    local chat = Admin.reportChat()
    if not chat or chat.notifyStaff ~= 'claimer' or not row.claimed_by_license then return nil end
    for _, playerSrc in ipairs(exports.kora_core:getPlayers()) do
        if exports.kora_core:primary(playerSrc) == row.claimed_by_license then return playerSrc end
    end
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
            TriggerClientEvent('kora_admin:client:reportChanged', playerSrc, id)
        end
    end)
end

local function notifyReporter(row, payload)
    local src = Admin.reporterSource(row)
    if src then Kora.notify.send(src, payload) end
end

---With the chat on, tell the reporter's own client that their report changed so an
---open My Reports window reloads it. `info` carries a staff reply's preview, which
---the client shows as a toast only while that window is closed. The client
---re-fetches through kora_admin:myReport, which re-checks ownership.
---@param row table
---@param info table|nil
local function pushReporter(row, info)
    if not Admin.reportChat() then return end
    local src = Admin.reporterSource(row)
    if src then
        TriggerClientEvent('kora_admin:client:myReportChanged', src, row.id, info)
        -- A staff reply that reached an online reporter is "delivered" (toast or open window).
        if info and info.kind == 'reply' then Admin.markReportDelivered(row.id, row.reporter_license) end
    end
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
    if Admin.reportChat() then Admin.markReportDeliveredToStaff(id, src) end
    return report or { id = id, type = definition.id, status = 'open', reporter_name = reporterName, message = message }
end

---@param id any
---@return table|nil
function Admin.getReport(id)
    id = Admin.finiteNumber(id, 1, nil, true)
    if not id then return nil end
    local row = Kora.sql.single('SELECT *,UNIX_TIMESTAMP(`created_at`) AS `created_epoch` FROM `admin_reports` WHERE `id` = ? LIMIT 1', { id })
    if row then
        row.reporter_source = Admin.reporterSource(row)
        row.category = categoryLabel(row.type)
        row.created_text = Admin.formatReportTime(row.created_epoch)
    end
    return row
end

---@param id any
---@return table[]
function Admin.getReportMessages(id)
    id = Admin.finiteNumber(id, 1, nil, true)
    if not id then return {} end
    local rows = Kora.sql.query(
        'SELECT `id`,`author_name`,`author_role`,`message`,`created_at`,UNIX_TIMESTAMP(`created_at`) AS `created_epoch` FROM `admin_report_messages` WHERE `report_id` = ? ORDER BY `created_at`,`id`',
        { id }
    ) or {}
    for _, row in ipairs(rows) do row.created_text = Admin.formatReportTime(row.created_epoch) end
    return rows
end

---The newest message id `license` has seen on report `id` (0 when never opened).
---@param id integer
---@param license string|nil
---@return integer
function Admin.reportLastRead(id, license)
    if not license then return 0 end
    local value = Kora.sql.scalar('SELECT `last_message_id` FROM `admin_report_reads` WHERE `report_id` = ? AND `reader_license` = ? LIMIT 1',
        { id, license })
    return math.floor(tonumber(value) or 0)
end

---Record that `license` has seen report `id` up to message `lastId`. Never moves backwards.
---@param id integer
---@param license string|nil
---@param lastId integer|nil
function Admin.markReportRead(id, license, lastId)
    lastId = math.floor(tonumber(lastId) or 0)
    -- 0 is recorded too: a row with no messages read yet still means "opened" (the original report was seen).
    if not license or lastId < 0 then return end
    -- Seeing a message implies it was delivered.
    Kora.sql.update(
        'INSERT INTO `admin_report_reads` (`report_id`,`reader_license`,`last_message_id`,`delivered_message_id`) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE `last_message_id` = GREATEST(`last_message_id`, VALUES(`last_message_id`)), `delivered_message_id` = GREATEST(COALESCE(`delivered_message_id`, 0), VALUES(`delivered_message_id`))',
        { id, license, lastId, lastId })
end

-- Pseudo reader that carries "a staff client received it" for a report. Real staff
-- licences only ever appear in admin_report_reads once they actually opened the report.
local STAFF_DELIVERY = '@staff'

---Record that the newest message of report `id` (the original report counts as message 0)
---reached `license`'s client. Never moves backwards.
---@param id integer
---@param license string|nil
function Admin.markReportDelivered(id, license)
    if not license then return end
    Kora.sql.update(
        'INSERT INTO `admin_report_reads` (`report_id`,`reader_license`,`last_message_id`,`delivered_message_id`) '
        .. 'VALUES (?,?,0,COALESCE((SELECT MAX(`id`) FROM `admin_report_messages` WHERE `report_id` = ?), 0)) '
        .. 'ON DUPLICATE KEY UPDATE `delivered_message_id` = GREATEST(COALESCE(`delivered_message_id`, 0), VALUES(`delivered_message_id`))',
        { id, license, id })
end

---Delivery for staff: true when someone besides `actor` holding the staff level is online.
---@param id integer
---@param actor integer|nil
function Admin.markReportDeliveredToStaff(id, actor)
    local reached = false
    for _, playerSrc in ipairs(exports.kora_core:getPlayers()) do
        if playerSrc ~= actor and Admin.checkLevel(playerSrc, Config.reports.staffLevel) then reached = true break end
    end
    if reached then Admin.markReportDelivered(id, STAFF_DELIVERY) end
end

---Tick for one message from the author's point of view: 'seen' once the other side
---opened it, 'delivered' once it reached their client, otherwise 'sent'.
---@param messageId integer 0 for the original report
---@param seenUpTo integer|nil newest message id the other side has opened (nil = never opened)
---@param deliveredUpTo integer|nil newest message id that reached the other side (nil = none)
---@return 'sent'|'delivered'|'seen'
local function messageStatus(messageId, seenUpTo, deliveredUpTo)
    if seenUpTo and seenUpTo >= messageId then return 'seen' end
    if deliveredUpTo and deliveredUpTo >= messageId then return 'delivered' end
    return 'sent'
end

---What the other side of report `row` has received/seen, for `viewerRole`'s own messages.
---@param row table
---@param viewerRole 'staff'|'player'
---@return integer|nil seenUpTo
---@return integer|nil deliveredUpTo
local function otherSideProgress(row, viewerRole)
    if viewerRole == 'staff' then
        local reader = Kora.sql.single('SELECT `last_message_id`,`delivered_message_id` FROM `admin_report_reads` WHERE `report_id` = ? AND `reader_license` = ? LIMIT 1',
            { row.id, row.reporter_license or '' })
        if not reader then return nil, nil end
        return math.floor(tonumber(reader.last_message_id) or 0), tonumber(reader.delivered_message_id) and math.floor(tonumber(reader.delivered_message_id)) or nil
    end
    local seen = Kora.sql.single('SELECT COUNT(*) AS `n`,MAX(`last_message_id`) AS `newest` FROM `admin_report_reads` WHERE `report_id` = ? AND `reader_license` NOT IN (?, ?)',
        { row.id, row.reporter_license or '', STAFF_DELIVERY })
    local delivered = Kora.sql.scalar('SELECT `delivered_message_id` FROM `admin_report_reads` WHERE `report_id` = ? AND `reader_license` = ? LIMIT 1',
        { row.id, STAFF_DELIVERY })
    local seenUpTo = seen and (tonumber(seen.n) or 0) > 0 and math.floor(tonumber(seen.newest) or 0) or nil
    return seenUpTo, tonumber(delivered) and math.floor(tonumber(delivered)) or nil
end

---Report `id` with its conversation shaped for one reader, and marks it read for
---them. `viewerRole` is 'staff' or 'player' and decides which side's messages count
---as unread ("the other side's messages after my read marker"). The caller has
---already checked that `src` may read the report. Player views drop identifiers.
---@param src integer
---@param row table
---@param viewerRole 'staff'|'player'
---@param live boolean|nil true for a refresh of an already open conversation (nothing is flagged unread)
---@return table
function Admin.reportConversation(src, row, viewerRole, live)
    local license = src ~= 0 and exports.kora_core:primary(src) or nil
    local lastRead = Admin.reportLastRead(row.id, license)
    local chat = Admin.reportChat() or {}
    local otherRole = viewerRole == 'staff' and 'player' or 'staff'
    local messages, newest = {}, 0
    -- Ticks on the viewer's own messages: what the other side has received / opened so far.
    local seenUpTo, deliveredUpTo = otherSideProgress(row, viewerRole)
    for _, message in ipairs(Admin.getReportMessages(row.id)) do
        local messageId = math.floor(tonumber(message.id) or 0)
        if messageId > newest then newest = messageId end
        local author = message.author_name
        if viewerRole == 'player' and message.author_role == 'staff' and chat.showStaffNames == false then author = 'Staff' end
        messages[#messages + 1] = {
            id = messageId, author_name = author, author_role = message.author_role, message = message.message,
            created_text = message.created_text,
            unread = not live and message.author_role == otherRole and messageId > lastRead or nil,
            status = message.author_role == viewerRole and messageStatus(messageId, seenUpTo, deliveredUpTo) or nil,
        }
    end
    local advanced = newest > lastRead or (lastRead == 0 and not live)
    Admin.markReportRead(row.id, license, newest)
    -- The other side's open window shows the new ticks right away.
    if advanced and src ~= 0 then
        if viewerRole == 'player' then broadcastReportChange(row.id) else pushReporter(row, { kind = 'seen' }) end
    end
    row.messages = messages
    -- The original report is message 0 and belongs to the reporter.
    row.initial_status = viewerRole == 'player' and messageStatus(0, seenUpTo, deliveredUpTo) or nil
    if viewerRole == 'player' then
        return {
            id = row.id, type = row.type, category = row.category, status = row.status, message = row.message,
            reporter_name = row.reporter_name, created_text = row.created_text, resolution = row.resolution,
            claimed_by_name = row.claimed_by_name and (chat.showStaffNames == false and 'Staff' or row.claimed_by_name) or nil,
            messages = messages, initial_status = row.initial_status,
        }
    end
    return row
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
    local sql = 'SELECT `id`,`type`,`status`,`reporter_name`,`claimed_by_name`,`message`,`created_at`,`updated_at`,UNIX_TIMESTAMP(`created_at`) AS `created_epoch`'
    local selectParams = {}
    -- Unread for one reader: the other side's messages after that reader's marker.
    if filters.unreadFor and (filters.unreadRole == 'staff' or filters.unreadRole == 'player') then
        sql = sql .. ',(SELECT COUNT(*) FROM `admin_report_messages` `m` WHERE `m`.`report_id` = `admin_reports`.`id` AND `m`.`author_role` = ?'
            .. ' AND `m`.`id` > COALESCE((SELECT `rr`.`last_message_id` FROM `admin_report_reads` `rr` WHERE `rr`.`report_id` = `admin_reports`.`id` AND `rr`.`reader_license` = ?), 0)) AS `unread`'
        selectParams = { filters.unreadRole, filters.unreadFor }
    end
    sql = sql .. ' FROM `admin_reports`'
    for index = #selectParams, 1, -1 do table.insert(params, 1, selectParams[index]) end
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
        row.unread = tonumber(row.unread) and math.floor(tonumber(row.unread)) or nil
    end
    return rows
end

local function canRead(src, row)
    if src == 0 or Admin.checkLevel(src, Config.reports.staffLevel) then return true, 'staff' end
    local license = exports.kora_core:primary(src)
    if license and row.reporter_license == license then return true, 'player' end
    return false
end
Admin.canReadReport = canRead

---Sliding-window chat rate limit per sender (Config.reports.chat.rateLimit).
---@param src integer
---@return boolean ok
---@return string|nil err
local function takeChatSlot(src)
    local chat = Admin.reportChat()
    if not chat or src == 0 or type(chat.rateLimit) ~= 'table' then return true end
    local limit = math.floor(tonumber(chat.rateLimit.messages) or 0)
    local window = (tonumber(chat.rateLimit.seconds) or 0) * 1000
    if limit < 1 or window <= 0 then return true end
    local now = GetGameTimer()
    local kept = {}
    for _, at in ipairs(Admin.reportChatSends[src] or {}) do
        if now - at < window then kept[#kept + 1] = at end
    end
    if #kept >= limit then
        Admin.reportChatSends[src] = kept
        return false, ('you are sending messages too quickly; wait %d seconds'):format(math.max(1, math.ceil((window - (now - kept[1])) / 1000)))
    end
    kept[#kept + 1] = now
    Admin.reportChatSends[src] = kept
    return true
end

---@param src integer
---@param id any
---@param message string
---@param opts table|nil { chat = true } from the chat composer: over-long text is refused rather than cut
---@return boolean
---@return string|nil
function Admin.replyToReport(src, id, message, opts)
    local row = Admin.getReport(id)
    if not row then return false, 'report not found' end
    local allowed, role = canRead(src, row)
    if not allowed then return false, 'you cannot reply to that report' end
    if row.status == 'resolved' or row.status == 'dismissed' then return false, 'reopen the report before replying' end
    local chat = Admin.reportChat()
    message = chat and Admin.cleanChatMessage(message) or cleanMessage(message)
    if not message then return false, 'reply required' end
    if chat and opts and opts.chat then
        local max = math.min(math.floor(tonumber(chat.maxLength) or Config.reports.maxMessageLength), Config.reports.maxMessageLength)
        if (utf8.len(message) or #message) > max then return false, ('message too long (max %d characters)'):format(max) end
    else
        message = message:sub(1, Config.reports.maxMessageLength)
    end
    local slotOk, slotErr = takeChatSlot(src)
    if not slotOk then return false, slotErr end

    local license, name = actorIdentity(src)
    local inserted, dbErr = Kora.sql.insert(
        'INSERT INTO `admin_report_messages` (`report_id`,`author_license`,`author_name`,`author_role`,`message`) VALUES (?,?,?,?,?)',
        { row.id, license or Kora.sql.NULL, name, role, message }
    )
    if not inserted then return false, dbErr or 'could not save reply' end
    Kora.sql.update('UPDATE `admin_reports` SET `updated_at` = CURRENT_TIMESTAMP WHERE `id` = ?', { row.id })

    if role == 'staff' then
        if chat then
            -- The reporter's client toasts only while My Reports is closed; open, it just refreshes.
            local shownName = chat.showStaffNames == false and 'Staff' or name
            pushReporter(row, { kind = 'reply', author = shownName, preview = Admin.reportSubject(message, 120) })
        else
            notifyReporter(row, { title = ('Report #%s reply'):format(row.id), message = message, type = 'info' })
        end
        Admin.log(src, 'report_reply', reportTarget(row), { reportId = row.id, message = message })
    else
        notifyStaff({ title = ('Report #%s updated'):format(row.id), message = ('%s: %s'):format(name, chat and Admin.reportSubject(message, 200) or message), type = 'info' }, claimerSource(row))
        pushReporter(row, { kind = 'own' })
        if chat then Admin.markReportDeliveredToStaff(row.id, src) end
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
    pushReporter(row, { kind = 'status' })
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
    pushReporter(row, { kind = 'status' })
    broadcastReportChange(row.id, src)
    return true
end

AddEventHandler('playerDropped', function()
    Admin.reportCooldowns[source] = nil
    Admin.reportChatSends[source] = nil
end)
