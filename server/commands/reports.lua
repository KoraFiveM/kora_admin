-- Player-facing report submission/status commands and staff lifecycle tools.
-- The admin menu executes these same commands, keeping one authorization and
-- audit path for both interfaces.

local OPTS_USER = { permission = 'user', resource = 'kora_admin' }
local OPTS_STAFF = { permission = Config.reports.staffLevel, checkPermission = Admin.checkLevel, resource = 'kora_admin' }

local function typeNames()
    local values = {}
    for _, definition in ipairs(Config.reports.types) do values[#values + 1] = definition.id end
    return values
end

Admin.addCommand('report', 'Send a report to server staff', {
    { name = 'type', help = 'report category', values = typeNames() },
    { name = 'message', help = 'what happened and any useful details' },
}, true, function(source, args)
    local report, err = Admin.createReport(source, args[1], table.concat(args, ' ', 2))
    if not report then return Admin.respond(source, false, err) end
    local chat = Admin.reportChat()
    local hint = chat and chat.playerUi ~= false and ' Use /reports to chat with staff.' or ''
    Admin.respond(source, true, ('Report #%s submitted. Staff have been notified.%s'):format(report.id, hint), { title = 'Report sent' })
end, OPTS_USER)

Admin.addCommand('reportstatus', 'View one of your reports and its replies', { { name = 'id' } }, true, function(source, args)
    local report = Admin.getReport(args[1])
    if not report then return Admin.respond(source, false, 'report not found') end
    local license = source ~= 0 and exports.kora_core:primary(source) or nil
    if source ~= 0 and not Admin.checkLevel(source, Config.reports.staffLevel) and report.reporter_license ~= license then
        return Admin.respond(source, false, 'you cannot view that report')
    end

    local lines = {
        ('#%s · %s · %s'):format(report.id, report.type, report.status),
        ('From %s: %s'):format(report.reporter_name, report.message),
    }
    for _, reply in ipairs(Admin.getReportMessages(report.id)) do
        local created = tonumber(reply.created_epoch) or reply.created_at
        if type(created) == 'number' then
            if math.abs(created) >= 100000000000 then created = created / 1000 end
            local ok, formatted = pcall(os.date, '!%Y-%m-%d %H:%M:%S', math.floor(created))
            created = ok and formatted or '-'
        elseif type(created) ~= 'string' or created == '' then
            created = '-'
        end
        lines[#lines + 1] = ('[%s] %s: %s'):format(created, tostring(reply.author_name or '-'), tostring(reply.message or ''))
    end
    if report.resolution then lines[#lines + 1] = 'Resolution: ' .. report.resolution end
    -- Report text is player/staff input and chat renders markup, so neutralise brackets.
    Admin.chat(source, Admin.chatSafe(table.concat(lines, '\n')))
end, OPTS_USER)

Admin.addCommand('reportreply', 'Reply to your report (staff may reply to any report)', {
    { name = 'id' }, { name = 'message' },
}, true, function(source, args)
    local ok, err = Admin.replyToReport(source, args[1], table.concat(args, ' ', 2))
    Admin.respond(source, ok, ok and ('Reply added to report #%s'):format(args[1]) or err)
end, OPTS_USER)

-- Staff get the Reports screen (or a tidy chat list with Config.reports.command.ui
-- off); everyone else sees only their own reports. Staff-only data and actions
-- stay behind the existing Config.reports.staffLevel callbacks and commands.
if Config.reports.command.enabled then
    Admin.addCommand('reports', 'List player reports (your own unless you are staff)', {
        { name = 'status', help = 'all, open, claimed, resolved, or dismissed' },
        { name = 'type', help = 'all or a report category' },
        { name = 'page' },
    }, false, function(source, args)
        local filters = { status = args[1], type = args[2], page = args[3] }
        local staff = source == 0 or Admin.checkLevel(source, Config.reports.staffLevel)
        if not staff then
            filters.license = exports.kora_core:primary(source)
            if not filters.license then return Admin.respond(source, false, 'you are not logged in') end
            local chat = Admin.reportChat()
            if chat and chat.playerUi ~= false and source ~= 0 and not Admin.commandContext(source) then
                return TriggerClientEvent('qbadmin:client:openMyReports', source, tonumber(args[1]))
            end
            filters.status = filters.status or 'all'
        else
            filters.status = filters.status or 'open'
            if Config.reports.command.ui and source ~= 0 and not Admin.commandContext(source) then
                return TriggerClientEvent('qbadmin:client:openReports', source, Admin.getLevel(source), filters)
            end
        end

        local rows = Admin.queryReports(filters)
        if #rows == 0 then return Admin.chat(source, staff and 'No matching reports.' or 'You have no matching reports.') end
        local text = Admin.formatReportList(rows)
        Admin.chat(source, staff and text or (text .. '\nUse /reportstatus <id> to read a report.'))
    end, OPTS_USER)
end

Admin.addCommand('reportclaim', 'Claim a player report', { { name = 'id' } }, true, function(source, args)
    local ok, err = Admin.claimReport(source, args[1])
    Admin.respond(source, ok, ok and ('Claimed report #%s'):format(args[1]) or err)
end, OPTS_STAFF)

local function addStatusCommand(name, help, status)
    -- Only the id is mandatory; kora_lib's argsRequired flag is all-or-nothing,
    -- so leave it false and let setReportStatus validate the id while keeping
    -- the note optional for typed commands. The menu asks for a note when
    -- resolving/dismissing to encourage useful closure context.
    Admin.addCommand(name, help, { { name = 'id' }, { name = 'note' } }, false, function(source, args)
        local ok, err = Admin.setReportStatus(source, args[1], status, table.concat(args, ' ', 2))
        Admin.respond(source, ok, ok and ('Report #%s marked %s'):format(args[1], status) or err)
    end, OPTS_STAFF)
end

addStatusCommand('reportresolve', 'Resolve a player report', 'resolved')
addStatusCommand('reportdismiss', 'Dismiss a player report', 'dismissed')
addStatusCommand('reportreopen', 'Reopen a resolved or dismissed report', 'open')
