-- Player-facing report submission/status commands and staff lifecycle tools.
-- The admin menu executes these same commands, keeping one authorization and
-- audit path for both interfaces.

local OPTS_USER = { permission = 'user', resource = 'qbadmin' }
local OPTS_STAFF = { permission = Config.reports.staffLevel, checkPermission = Admin.checkLevel, resource = 'qbadmin' }

local function typeNames()
    local values = {}
    for _, definition in ipairs(Config.reports.types) do values[#values + 1] = definition.id end
    return values
end

QB.commands.add('report', 'Send a report to server staff', {
    { name = 'type', help = 'report category', values = typeNames() },
    { name = 'message', help = 'what happened and any useful details' },
}, true, function(source, args)
    local report, err = Admin.createReport(source, args[1], table.concat(args, ' ', 2))
    if not report then return Admin.respond(source, false, err) end
    Admin.respond(source, true, ('Report #%s submitted. Staff have been notified.'):format(report.id), { title = 'Report sent' })
end, OPTS_USER)

QB.commands.add('reportstatus', 'View one of your reports and its replies', { { name = 'id' } }, true, function(source, args)
    local report = Admin.getReport(args[1])
    if not report then return Admin.respond(source, false, 'report not found') end
    local license = source ~= 0 and exports.qbcore:primary(source) or nil
    if source ~= 0 and not Admin.checkLevel(source, Config.reports.staffLevel) and report.reporter_license ~= license then
        return Admin.respond(source, false, 'you cannot view that report')
    end

    local lines = {
        ('#%s · %s · %s'):format(report.id, report.type, report.status),
        ('From %s: %s'):format(report.reporter_name, report.message),
    }
    for _, reply in ipairs(Admin.getReportMessages(report.id)) do
        lines[#lines + 1] = ('[%s] %s: %s'):format(reply.created_at or '-', reply.author_name, reply.message)
    end
    if report.resolution then lines[#lines + 1] = 'Resolution: ' .. report.resolution end
    Admin.chat(source, table.concat(lines, '\n'))
end, OPTS_USER)

QB.commands.add('reportreply', 'Reply to your report (staff may reply to any report)', {
    { name = 'id' }, { name = 'message' },
}, true, function(source, args)
    local ok, err = Admin.replyToReport(source, args[1], table.concat(args, ' ', 2))
    Admin.respond(source, ok, ok and ('Reply added to report #%s'):format(args[1]) or err)
end, OPTS_USER)

QB.commands.add('reports', 'List player reports', {
    { name = 'status', help = 'all, open, claimed, resolved, or dismissed' },
    { name = 'type', help = 'all or a report category' },
    { name = 'page' },
}, false, function(source, args)
    local rows = Admin.queryReports({ status = args[1] or 'open', type = args[2], page = args[3] })
    if #rows == 0 then return Admin.chat(source, 'No matching reports.') end
    local lines = {}
    for _, row in ipairs(rows) do
        lines[#lines + 1] = ('#%s [%s/%s] %s%s — %s'):format(
            row.id, row.status, row.type, row.reporter_name,
            row.claimed_by_name and (' · ' .. row.claimed_by_name) or '', row.message)
    end
    Admin.chat(source, table.concat(lines, '\n'))
end, OPTS_STAFF)

QB.commands.add('reportclaim', 'Claim a player report', { { name = 'id' } }, true, function(source, args)
    local ok, err = Admin.claimReport(source, args[1])
    Admin.respond(source, ok, ok and ('Claimed report #%s'):format(args[1]) or err)
end, OPTS_STAFF)

local function addStatusCommand(name, help, status)
    -- Only the id is mandatory; qblib's argsRequired flag is all-or-nothing,
    -- so leave it false and let setReportStatus validate the id while keeping
    -- the note optional for typed commands. The menu asks for a note when
    -- resolving/dismissing to encourage useful closure context.
    QB.commands.add(name, help, { { name = 'id' }, { name = 'note' } }, false, function(source, args)
        local ok, err = Admin.setReportStatus(source, args[1], status, table.concat(args, ' ', 2))
        Admin.respond(source, ok, ok and ('Report #%s marked %s'):format(args[1], status) or err)
    end, OPTS_STAFF)
end

addStatusCommand('reportresolve', 'Resolve a player report', 'resolved')
addStatusCommand('reportdismiss', 'Dismiss a player report', 'dismissed')
addStatusCommand('reportreopen', 'Reopen a resolved or dismissed report', 'open')
