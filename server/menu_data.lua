-- Read-only data for the admin NUI.  Commands remain the only mutation
-- surface; these callbacks exist so the menu can present useful lists instead
-- of making an administrator type an optional filter before seeing anything.

local function allowed(src, level)
    if not Admin.checkLevel(src, level) then
        return nil, 'permission denied'
    end
    return true
end

-- Job and gang records for the Set Job / Set Gang forms, read from kora_core's
-- authoritative registry and reduced to name, label and an ordered grade list so
-- the form never depends on how a client mirror was seeded. Hiding duplicates is
-- left to the client (Config.roles).
local function roleRecords(kind)
    local out = {}
    for _, role in ipairs(exports.kora_core:allShared(kind) or {}) do
        local entries = {}
        for key, grade in pairs(type(role.grades) == 'table' and role.grades or {}) do
            local level = tonumber(key)
            if level and type(grade) == 'table' then entries[#entries + 1] = { level = level, name = grade.name } end
        end
        table.sort(entries, function(a, b) return a.level < b.level end)
        local grades = {}
        for index, entry in ipairs(entries) do grades[index] = { name = entry.name or tostring(index) } end
        out[#out + 1] = { name = role.name, label = role.label or role.name, grades = grades }
    end
    return out
end

Kora.callback.register('qbadmin:menuRoles', function(src)
    local ok, err = allowed(src, 'admin')
    if not ok then return nil, err end
    return { jobs = roleRecords('jobs'), gangs = roleRecords('gangs') }
end)

Kora.callback.register('qbadmin:menuPlayers', function(src)
    local ok, err = allowed(src, 'support')
    if not ok then return nil, err end

    local players = {}
    for _, playerSrc in ipairs(exports.kora_core:getPlayers()) do
        local job = exports.kora_core:getJob(playerSrc)
        players[#players + 1] = {
            id = tostring(playerSrc),
            name = GetPlayerName(playerSrc) or ('unknown(%d)'):format(playerSrc),
            job = job and (job.label or job.name) or 'Unknown',
            ping = GetPlayerPing(playerSrc),
        }
    end

    table.sort(players, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
    return players
end)

-- A row selection opens a fresh, server-authenticated profile rather than
-- trusting the summary values that were rendered in the player list. Sensitive
-- identifiers remain admin-only.
Kora.callback.register('qbadmin:menuPlayerProfile', function(src, target)
    local ok, err = allowed(src, 'support')
    if not ok then return nil, err end

    local targetSrc, data, targetErr = Admin.resolveTarget(src, tostring(target or ''))
    if not targetSrc then return nil, targetErr end
    local metadata = data.metadata or {}
    local job, gang = data.job or {}, data.gang or {}
    local moneyParts = {}
    for account, amount in pairs(data.money or {}) do
        moneyParts[#moneyParts + 1] = ('%s: %s'):format(account, amount)
    end
    table.sort(moneyParts)

    local profile = {
        id = tostring(targetSrc),
        name = data.name or GetPlayerName(targetSrc) or ('unknown(%d)'):format(targetSrc),
        citizenid = data.citizenid or 'Unknown',
        job = ('%s (%s)'):format(job.label or job.name or 'Unknown', job.grade and (job.grade.name or job.grade.level) or 'No grade'),
        gang = ('%s (%s)'):format(gang.label or gang.name or 'None', gang.grade and (gang.grade.name or gang.grade.level) or 'No grade'),
        money = #moneyParts > 0 and table.concat(moneyParts, ', ') or 'None',
        ping = GetPlayerPing(targetSrc),
        health = GetEntityHealth(GetPlayerPed(targetSrc)),
        armor = metadata.armor or 0,
        hunger = metadata.hunger or 100,
        thirst = metadata.thirst or 100,
        dead = metadata.isdead == true or metadata.inlaststand == true,
        cuffed = metadata.ishandcuffed == true,
        onDuty = job.onduty == true,
        frozen = Admin.states.frozen[targetSrc] == true,
        godMode = Admin.states.god[targetSrc] == true,
        invisible = Admin.states.invisible[targetSrc] == true,
    }

    profile.devMode = exports.kora_core:isDevMode(targetSrc) == true

    if Admin.checkLevel(src, 'admin') then
        local identifiers = exports.kora_core:getIdentifiers(targetSrc)
        profile.license = identifiers.license
        profile.discord = identifiers.discord
        profile.permission = Admin.getLevel(targetSrc)
    end
    return profile
end)

Kora.callback.register('qbadmin:menuAuditLog', function(src, filters)
    local ok, err = allowed(src, 'admin')
    if not ok then return nil, err end

    -- The client may choose filters for convenience, but queryLogs still
    -- parameterises all values and permission is decided here, on the server.
    filters = type(filters) == 'table' and filters or {}
    return Admin.queryLogs({
        action = type(filters.action) == 'string' and filters.action ~= '' and filters.action or nil,
        target = type(filters.target) == 'string' and filters.target ~= '' and filters.target or nil,
        page = math.max(1, tonumber(filters.page) or 1),
    })
end)

Kora.callback.register('qbadmin:menuReports', function(src, filters)
    local ok, err = allowed(src, Config.reports.staffLevel)
    if not ok then return nil, err end

    filters = type(filters) == 'table' and filters or {}
    return Admin.queryReports({
        status = type(filters.status) == 'string' and filters.status or 'open',
        type = type(filters.type) == 'string' and filters.type or nil,
        reporter = type(filters.reporter) == 'string' and filters.reporter ~= '' and filters.reporter or nil,
        page = math.max(1, tonumber(filters.page) or 1),
    })
end)

Kora.callback.register('qbadmin:menuReport', function(src, id)
    local ok, err = allowed(src, Config.reports.staffLevel)
    if not ok then return nil, err end

    local report = Admin.getReport(id)
    if not report then return nil, 'report not found' end
    report.messages = Admin.getReportMessages(report.id)
    return report
end)
