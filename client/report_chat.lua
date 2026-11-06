-- Report live chat (Config.reports.chat): the shared conversation block used by the
-- staff Reports screen, and the player's own "My Reports" window. Rendering only:
-- every message is sent through the qbadmin:reportChatSend callback, and the server
-- decides who may read or post (report owner or Config.reports.staffLevel), the
-- length, the rate limit and whether the report is still open. Message text is
-- handed to kora_lib's AppShell chat block, which renders it as plain text.

local MY_APP = 'qbadmin:myreports'

local function chatConfig()
    local chat = Config.reports.chat
    if type(chat) == 'table' and chat.enabled == true then return chat end
end

---True when the chat screens use the fixed, non-scrolling layout (Config.reports.chat.fixedLayout).
function Admin.reportChatFixedLayout()
    local chat = chatConfig()
    return chat ~= nil and chat.fixedLayout ~= false
end

---@param report table conversation from qbadmin:menuReport / qbadmin:myReport
---@param viewerRole 'staff'|'player'
---@param sendAction string action id of the composer
---@return table AppShell chat block
function Admin.reportChatBlock(report, viewerRole, sendAction)
    local chat = chatConfig() or {}
    local closed = report.status == 'resolved' or report.status == 'dismissed'
    local messages = {
        {
            id = 'report', author = tostring(report.reporter_name or 'Reporter'), text = tostring(report.message or ''),
            timestamp = report.created_text, badge = 'Report', tone = 'primary', mine = viewerRole == 'player',
        },
    }
    for index, message in ipairs(report.messages or {}) do
        local staff = message.author_role == 'staff'
        messages[#messages + 1] = {
            id = 'm' .. tostring(message.id or index),
            author = tostring(message.author_name or (staff and 'Staff' or 'Player')),
            text = tostring(message.message or ''),
            timestamp = type(message.created_text) == 'string' and message.created_text or nil,
            badge = staff and 'Staff' or 'Player',
            tone = staff and 'success' or 'neutral',
            mine = (viewerRole == 'staff') == staff,
            unread = message.unread == true or nil,
        }
    end
    local maxLength = math.floor(tonumber(chat.maxLength) or Config.reports.maxMessageLength)
    return {
        id = 'report-chat-' .. tostring(report.id), type = 'chat', title = 'Conversation',
        empty = 'No messages yet',
        -- Fixed layout: the block fills the screen, only its messages scroll, newest always shown.
        scrollable = Admin.reportChatFixedLayout() or nil,
        follow = Admin.reportChatFixedLayout() or nil,
        messages = messages,
        composer = {
            action = { id = sendAction, label = 'Send', icon = 'send' },
            placeholder = viewerRole == 'staff' and ('Reply to %s'):format(tostring(report.reporter_name or 'the reporter'))
                or 'Write a message to staff',
            maxLength = math.max(1, math.min(maxLength, Config.reports.maxMessageLength)),
            disabled = closed,
            note = closed and (viewerRole == 'staff' and 'This report is closed. Reopen it from Manage to reply.'
                or 'This report is closed. Open a new report with /report if you still need help.') or nil,
        },
    }
end

---Send one chat message; returns nil on success or the server's reason.
---@param reportId any
---@param message any
---@return string|nil
function Admin.sendReportChat(reportId, message)
    if type(message) ~= 'string' or message == '' then return 'Write a message first.' end
    local ok, err = Kora.callback.trigger('qbadmin:reportChatSend', reportId, message)
    if not ok then return err or 'Could not send the message.' end
end

-- ---------------------------------------------------------------------------
-- My Reports (player window)
-- ---------------------------------------------------------------------------

local selectedId
local refreshing, refreshPending = false, false

local function statusTone(status)
    return status == 'open' and 'warning' or status == 'resolved' and 'success' or 'neutral'
end

local function listView()
    local rows, err = Kora.callback.trigger('qbadmin:myReports')
    if not rows then return nil, err end
    local tableRows, unreadTotal = {}, 0
    for _, row in ipairs(rows) do
        local unread = tonumber(row.unread) or 0
        unreadTotal = unreadTotal + unread
        tableRows[#tableRows + 1] = {
            id = tostring(row.id),
            status = { label = row.status, badge = true, tone = statusTone(row.status) },
            type = row.category or row.type,
            subject = row.subject,
            unread = unread > 0 and { label = tostring(unread), badge = true, tone = 'primary' } or '',
            age = row.age or '-',
        }
    end
    return {
        id = 'reports', label = 'My Reports', icon = 'flag', badge = unreadTotal > 0 and unreadTotal or nil,
        content = {
            title = 'My Reports',
            description = 'Pick a report to chat with staff. Open a new one with /report <type> <message>.',
            blocks = { {
                id = 'my-report-list', type = 'table', title = 'Your reports', pageSize = 10,
                columns = {
                    { key = 'id', label = '#', sortable = true }, { key = 'status', label = 'Status', sortable = true },
                    { key = 'type', label = 'Category' }, { key = 'subject', label = 'Subject' },
                    { key = 'unread', label = 'New' }, { key = 'age', label = 'Age' },
                },
                rows = tableRows, empty = 'You have no reports.', action = 'my:select', idKey = 'id',
            } },
        },
    }
end

local function reportView(id, live)
    local report, err = Kora.callback.trigger('qbadmin:myReport', id, { live = live == true })
    if not report then return nil, err end
    local title = ('Report #%s · %s'):format(report.id, report.category or report.type or '')
    local description = report.claimed_by_name and ('Handled by %s · %s'):format(report.claimed_by_name, report.status)
        or ('Status: %s · waiting for staff'):format(report.status)
    local back = { id = 'my:back', label = 'Back to My Reports', icon = 'arrow-left', variant = 'ghost' }
    if Admin.reportChatFixedLayout() then
        -- One fixed screen: Back beside the title, the resolution in the header line, and the
        -- chat filling the rest (only its message list scrolls).
        if report.resolution then description = ('%s · Resolution: %s'):format(description, tostring(report.resolution)) end
        return {
            id = 'report', label = ('Report #%s'):format(report.id), icon = 'message-square',
            content = {
                title = title, description = description, actions = { back }, scrollable = false,
                blocks = { Admin.reportChatBlock(report, 'player', 'my:send') },
            },
        }, report
    end
    return {
        id = 'report', label = ('Report #%s'):format(report.id), icon = 'message-square',
        content = {
            title = ('Report #%s · %s'):format(report.id, report.category or report.type or ''),
            description = report.claimed_by_name and ('Handled by %s · %s'):format(report.claimed_by_name, report.status)
                or ('Status: %s · waiting for staff'):format(report.status),
            blocks = {
                { id = 'my-report-back', type = 'actions',
                    actions = { { id = 'my:back', label = 'Back to My Reports', icon = 'arrow-left', variant = 'ghost' } } },
                Admin.reportChatBlock(report, 'player', 'my:send'),
                report.resolution and { id = 'my-report-resolution', type = 'text', title = 'Resolution', text = tostring(report.resolution) } or nil,
            },
        },
    }, report
end

local function navigationFor(list, report)
    local navigation = { list }
    if report then navigation[2] = report end
    return navigation
end

local function showList()
    local list, err = listView()
    if not list then return nil, err end
    selectedId = nil
    return { update = { navigation = navigationFor(list) }, navigate = { viewId = 'reports', replace = true } }
end

local function showReport(id, live)
    local list = listView()
    local view, report = reportView(id, live)
    if not view then return nil, report end
    selectedId = tostring(report.id)
    return { update = { navigation = navigationFor(list or { id = 'reports', label = 'My Reports', content = { blocks = {} } }, view) },
        navigate = { viewId = 'report' } }
end

-- Server pushes for the player's own reports. Open window: reload in place (only
-- `update`, so the half-typed message survives). Closed window: a staff reply
-- becomes a kora_lib toast pointing at /reports.
local function refreshOpen()
    if refreshing then refreshPending = true return end
    refreshing = true
    repeat
        refreshPending = false
        local result = selectedId and showReport(selectedId, true) or showList()
        if result and Kora.nui.isAppOpen(MY_APP) then Kora.nui.updateApp(MY_APP, result.update) end
    until not refreshPending
    refreshing = false
end

RegisterNetEvent('qbadmin:client:myReportChanged', function(id, info)
    if not chatConfig() then return end
    info = type(info) == 'table' and info or {}
    if Kora.nui.isAppOpen and Kora.nui.isAppOpen(MY_APP) then
        local ok, err = pcall(refreshOpen)
        if not ok then refreshing = false print(('^1[qbadmin]^7 my reports refresh failed: %s'):format(tostring(err))) end
        return
    end
    if info.kind == 'reply' then
        Kora.notify.send({
            title = ('Report #%s · new reply'):format(tostring(id)),
            message = ('%s: %s\nType /reports to open the chat.'):format(tostring(info.author or 'Staff'), tostring(info.preview or '')),
            type = 'info',
        })
    end
end)

local function openMyReports(reportId)
    if not chatConfig() then return end
    local first, err
    if reportId then first, err = showReport(reportId) end
    if not first then first, err = showList() end
    if not first then
        Kora.notify.send({ type = 'error', message = err or 'Could not load your reports' })
        return
    end
    Kora.nui.registerApp({
        id = MY_APP,
        title = 'My Reports',
        description = 'Chat with server staff',
        icon = 'flag',
        layout = 'compact',
        width = 640,
        height = 720,
        defaultView = first.navigate.viewId,
        navigation = first.update.navigation,
        footer = 'Staff see your messages live.',
        onAction = function(actionId, context)
            local result, actionErr
            if actionId == 'my:select' and context and context.itemId then
                result, actionErr = showReport(context.itemId)
            elseif actionId == 'my:back' then
                result, actionErr = showList()
            elseif actionId == 'my:send' and selectedId then
                local sendErr = Admin.sendReportChat(selectedId, context and type(context.value) == 'table' and context.value.message)
                if sendErr then return { notice = { tone = 'destructive', message = sendErr } } end
                result = showReport(selectedId, true)
                if result then result.navigate = nil end
            else
                error('That action is no longer available.')
            end
            if not result then return { notice = { tone = 'destructive', message = actionErr or 'Could not load that report' } } end
            Kora.nui.updateApp(MY_APP, result.update)
            result.update = nil
            return result
        end,
    })
    Kora.nui.openApp(MY_APP, { viewId = first.navigate.viewId })
    selectedId = nil
end

RegisterNetEvent('qbadmin:client:openMyReports', function(reportId)
    openMyReports(tonumber(reportId))
end)
