-- Report live chat (Config.reports.chat): the shared conversation block used by the
-- staff Reports screen, and the player's own "My Reports" window. Rendering only:
-- every message is sent through the kora_admin:reportChatSend callback, and the server
-- decides who may read or post (report owner or Config.reports.staffLevel), the
-- length, the rate limit and whether the report is still open. Message text is
-- handed to kora_lib's AppShell chat block, which renders it as plain text.

local MY_APP = 'kora_admin:myreports'

local function chatConfig()
    local chat = Config.reports.chat
    if type(chat) == 'table' and chat.enabled == true then return chat end
end

---True when the chat screens use the fixed, non-scrolling layout (Config.reports.chat.fixedLayout).
function Admin.reportChatFixedLayout()
    local chat = chatConfig()
    return chat ~= nil and chat.fixedLayout ~= false
end

---@param report table conversation from kora_admin:menuReport / kora_admin:myReport
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
            status = viewerRole == 'player' and report.initial_status or nil,
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
            -- Sent / delivered / seen ticks, only ever on the viewer's own messages.
            status = (viewerRole == 'staff') == staff and message.status or nil,
        }
    end
    local maxLength = math.floor(tonumber(chat.maxLength) or Config.reports.maxMessageLength)
    return {
        id = 'report-chat-' .. tostring(report.id), type = 'chat', title = Kora.lang('ui.report_conversation'),
        empty = Kora.lang('ui.no_messages'),
        -- Fixed layout: the block fills the screen, only its messages scroll, newest always shown.
        scrollable = Admin.reportChatFixedLayout() or nil,
        follow = Admin.reportChatFixedLayout() or nil,
        messages = messages,
        composer = {
            action = { id = sendAction, label = Kora.lang('ui.report_send'), icon = 'send' },
            placeholder = viewerRole == 'staff' and Kora.lang('ui.reply_to', tostring(report.reporter_name or Kora.lang('ui.the_reporter')))
                or Kora.lang('ui.reply_to_staff'),
            maxLength = math.max(1, math.min(maxLength, Config.reports.maxMessageLength)),
            disabled = closed,
            note = closed and (viewerRole == 'staff' and Kora.lang('ui.report_closed_staff')
                or Kora.lang('ui.report_closed_player')) or nil,
        },
    }
end

---Send one chat message; returns nil on success or the server's reason.
---@param reportId any
---@param message any
---@return string|nil
function Admin.sendReportChat(reportId, message)
    if type(message) ~= 'string' or message == '' then return Kora.lang('error.report_message_required') end
    local ok, err = Kora.callback.trigger('kora_admin:reportChatSend', reportId, message)
    if not ok then return err or Kora.lang('error.report_send_failed') end
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
    local rows, err = Kora.callback.trigger('kora_admin:myReports')
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
        id = 'reports', label = Kora.lang('ui.my_reports'), icon = 'flag', badge = unreadTotal > 0 and unreadTotal or nil,
        content = {
            title = Kora.lang('ui.my_reports'),
            description = Kora.lang('ui.reports_description'),
            blocks = { {
                id = 'my-report-list', type = 'table', title = Kora.lang('ui.your_reports'), pageSize = 10,
                columns = {
                    { key = 'id', label = '#', sortable = true }, { key = 'status', label = Kora.lang('ui.status'), sortable = true },
                    { key = 'type', label = Kora.lang('ui.category') }, { key = 'subject', label = Kora.lang('ui.subject') },
                    { key = 'unread', label = Kora.lang('ui.new') }, { key = 'age', label = Kora.lang('ui.age') },
                },
                rows = tableRows, empty = Kora.lang('ui.no_reports'), action = 'my:select', idKey = 'id',
            } },
        },
    }
end

local function reportView(id, live)
    local report, err = Kora.callback.trigger('kora_admin:myReport', id, { live = live == true })
    if not report then return nil, err end
    local title = Kora.lang('ui.report_number_category', report.id, report.category or report.type or '')
    local description = report.claimed_by_name and Kora.lang('ui.handled_by', report.claimed_by_name, report.status)
        or Kora.lang('ui.report_waiting', report.status)
    local back = { id = 'my:back', label = Kora.lang('ui.report_back'), icon = 'arrow-left', variant = 'ghost' }
    if Admin.reportChatFixedLayout() then
        -- One fixed screen: Back beside the title, the resolution in the header line, and the
        -- chat filling the rest (only its message list scrolls).
        if report.resolution then description = Kora.lang('ui.resolution', description, tostring(report.resolution)) end
        return {
            id = 'report', label = Kora.lang('ui.report_number', report.id), icon = 'message-square',
            content = {
                title = title, description = description, actions = { back }, scrollable = false,
                blocks = { Admin.reportChatBlock(report, 'player', 'my:send') },
            },
        }, report
    end
    return {
        id = 'report', label = Kora.lang('ui.report_number', report.id), icon = 'message-square',
        content = {
            title = Kora.lang('ui.report_number_category', report.id, report.category or report.type or ''),
            description = report.claimed_by_name and Kora.lang('ui.handled_by', report.claimed_by_name, report.status)
                or Kora.lang('ui.report_waiting', report.status),
            blocks = {
                { id = 'my-report-back', type = 'actions',
                    actions = { { id = 'my:back', label = Kora.lang('ui.report_back'), icon = 'arrow-left', variant = 'ghost' } } },
                Admin.reportChatBlock(report, 'player', 'my:send'),
                report.resolution and { id = 'my-report-resolution', type = 'text', title = Kora.lang('ui.resolution_title'), text = tostring(report.resolution) } or nil,
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
    return { update = { navigation = navigationFor(list or { id = 'reports', label = Kora.lang('ui.my_reports'), content = { blocks = {} } }, view) },
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

RegisterNetEvent('kora_admin:client:myReportChanged', function(id, info)
    if not chatConfig() then return end
    info = type(info) == 'table' and info or {}
    if Kora.nui.isAppOpen and Kora.nui.isAppOpen(MY_APP) then
        local ok, err = pcall(refreshOpen)
        if not ok then refreshing = false print(('^1[kora_admin]^7 my reports refresh failed: %s'):format(tostring(err))) end
        return
    end
    if info.kind == 'reply' then
        Kora.notify.send({
            title = Kora.lang('ui.new_reply_title', tostring(id)),
            message = Kora.lang('ui.new_reply_message', tostring(info.author or Kora.lang('ui.staff')), tostring(info.preview or '')),
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
        Kora.notify.send({ type = 'error', message = err or Kora.lang('ui.reports_load_failed') })
        return
    end
    Kora.nui.registerApp({
        id = MY_APP,
        title = Kora.lang('ui.my_reports'),
        description = Kora.lang('ui.report_chat_description'),
        icon = 'flag',
        layout = 'compact',
        width = 640,
        height = 720,
        defaultView = first.navigate.viewId,
        navigation = first.update.navigation,
        footer = Kora.lang('ui.report_footer'),
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

RegisterNetEvent('kora_admin:client:openMyReports', function(reportId)
    openMyReports(tonumber(reportId))
end)
