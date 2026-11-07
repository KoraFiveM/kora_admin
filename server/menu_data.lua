-- Data and guarded actions for the admin NUI. Callbacks enforce permissions on
-- the server; list views never trust client-submitted summary values.

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

-- Resource versions are read from local Git metadata only; resources without a
-- checkout (or with missing/inaccessible metadata) remain visible without a ref.
local function readLine(path)
    local file = io.open(path, 'r')
    if not file then return nil end
    local ok, line = pcall(file.read, file, '*l')
    file:close()
    return ok and line or nil
end

local function gitDirectory(resourcePath)
    local dotGit = resourcePath .. '/.git'
    local marker = readLine(dotGit)
    if marker and marker:match('^gitdir:%s*(.+)$') then
        local directory = marker:match('^gitdir:%s*(.+)$')
        if directory:sub(1, 1) ~= '/' then directory = resourcePath .. '/' .. directory end
        return directory
    end
    if readLine(dotGit .. '/HEAD') then return dotGit end
end

local function githubRepository(directory)
    local file = io.open(directory .. '/config', 'r')
    if not file then return nil end
    local inOrigin, url = false, nil
    for line in file:lines() do
        if line:match('^%s*%[') then
            inOrigin = line:match('^%s*%[remote%s+"origin"%]%s*$') ~= nil
        elseif inOrigin then
            url = line:match('^%s*url%s*=%s*(%S+)%s*$')
            if url then break end
        end
    end
    file:close()
    if not url then return nil end
    local repository = url:match('^https?://github%.com/([%w_.%-]+/[%w_.%-]+)$')
        or url:match('^git@github%.com:([%w_.%-]+/[%w_.%-]+)$')
        or url:match('^ssh://git@github%.com/([%w_.%-]+/[%w_.%-]+)$')
    if repository then return repository:gsub('%.git$', '') end
end

local function gitCommit(resourcePath)
    local directory = gitDirectory(resourcePath)
    if not directory then return nil end

    local head = readLine(directory .. '/HEAD')
    if not head then return nil end
    local ref = head:match('^ref:%s*(.+)$')
    local branch = ref and ref:match('^refs/heads/(.+)$') or nil
    local commit
    if not ref then
        commit = head
    else
        commit = readLine(directory .. '/' .. ref)
        if not commit then
            local packed = io.open(directory .. '/packed-refs', 'r')
            if packed then
                for line in packed:lines() do
                    local hash, packedRef = line:match('^([%da-fA-F]+)%s+(.+)$')
                    if packedRef == ref then commit = hash; break end
                end
                packed:close()
            end
        end
    end
    if not commit or not commit:match('^[%da-fA-F]+$') then return nil end

    local message
    local reflogs = {}
    if ref then reflogs[#reflogs + 1] = directory .. '/logs/' .. ref end
    reflogs[#reflogs + 1] = directory .. '/logs/HEAD'
    for _, path in ipairs(reflogs) do
        local file = io.open(path, 'r')
        if file then
            local last
            local readOk = pcall(function()
                for line in file:lines() do last = line end
            end)
            file:close()
            if readOk and last then
                local newCommit, subject = last:match('^[%da-fA-F]+%s+([%da-fA-F]+).-	(.*)$')
                if newCommit and newCommit:lower() == commit:lower() and subject:match('^commit[%w%s%(%)%-]*:') then
                    message = subject:gsub('^commit[%w%s%(%)%-]*:%s*', '')
                    break
                end
            end
        end
    end
    local repository = githubRepository(directory)
    return {
        ref = commit:sub(1, 12), fullCommit = commit, branch = branch, message = message,
        url = repository and ('https://github.com/%s/commit/%s'):format(repository, commit) or nil,
    }
end

Kora.callback.register('qbadmin:menuResources', function(src)
    local ok, err = allowed(src, 'admin')
    if not ok then return nil, err end

    local rows = {}
    for index = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(index)
        if name then
            local path = GetResourcePath(name)
            local git = path and gitCommit(path) or nil
            rows[#rows + 1] = {
                name = name,
                state = GetResourceState(name) or 'unknown',
                commit = git and git.ref or nil,
                fullCommit = git and git.fullCommit or nil,
                branch = git and git.branch or nil,
                message = git and git.message or nil,
                url = git and git.url or nil,
            }
        end
    end
    table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
    return rows
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
    local rows = Admin.queryLogs({
        action = type(filters.action) == 'string' and filters.action ~= '' and filters.action or nil,
        target = type(filters.target) == 'string' and filters.target ~= '' and filters.target or nil,
        page = math.max(1, tonumber(filters.page) or 1),
    })
    -- Client Lua has no `os`, so format the time here (UTC, same as /adminlog).
    for _, row in ipairs(rows) do
        local epoch = tonumber(row.created_epoch)
        row.created_text = epoch and os.date('!%Y-%m-%d %H:%M:%S', math.floor(epoch)) or nil
    end
    return rows
end)

Kora.callback.register('qbadmin:menuReports', function(src, filters)
    local ok, err = allowed(src, Config.reports.staffLevel)
    if not ok then return nil, err end

    filters = type(filters) == 'table' and filters or {}
    local chat = Admin.reportChat()
    return Admin.queryReports({
        status = type(filters.status) == 'string' and filters.status or 'open',
        type = type(filters.type) == 'string' and filters.type or nil,
        reporter = type(filters.reporter) == 'string' and filters.reporter ~= '' and filters.reporter or nil,
        page = math.max(1, tonumber(filters.page) or 1),
        unreadFor = chat and exports.kora_core:primary(src) or nil,
        unreadRole = chat and 'player' or nil,
    })
end)

-- Opening (or live-refreshing) a report marks it read for this staff member.
-- `opts.live` is a refresh of a conversation already on screen: nothing is flagged unread.
Kora.callback.register('qbadmin:menuReport', function(src, id, opts)
    local ok, err = allowed(src, Config.reports.staffLevel)
    if not ok then return nil, err end

    local report = Admin.getReport(id)
    if not report then return nil, 'report not found' end
    if Admin.reportChat() then
        return Admin.reportConversation(src, report, 'staff', type(opts) == 'table' and opts.live == true)
    end
    report.messages = Admin.getReportMessages(report.id)
    return report
end)

-- Player side of the report chat. Ownership is always the reporter licence on the
-- stored row (never a client-supplied id or name); staff use the staff callbacks.
local function playerLicense(src)
    if not Admin.reportChat() or Admin.reportChat().playerUi == false then return nil, 'report chat is disabled' end
    local license = exports.kora_core:primary(src)
    if not license then return nil, 'you are not logged in' end
    return license
end

Kora.callback.register('qbadmin:myReports', function(src, page)
    local license, err = playerLicense(src)
    if not license then return nil, err end
    local rows = Admin.queryReports({
        status = 'all', license = license, page = math.max(1, math.floor(tonumber(page) or 1)),
        unreadFor = license, unreadRole = 'staff',
    })
    local out = {}
    for index, row in ipairs(rows) do
        out[index] = { id = row.id, status = row.status, category = row.category, subject = row.subject, age = row.age, unread = row.unread }
    end
    return out
end, { rateLimit = { max = 20, window = 10000 } })

Kora.callback.register('qbadmin:myReport', function(src, id, opts)
    local license, err = playerLicense(src)
    if not license then return nil, err end
    local report = Admin.getReport(id)
    if not report or report.reporter_license ~= license then return nil, 'report not found' end
    return Admin.reportConversation(src, report, 'player', type(opts) == 'table' and opts.live == true)
end, { rateLimit = { max = 30, window = 10000 } })

-- The chat composer (staff screen and My Reports). replyToReport re-checks that the
-- sender owns the report or holds Config.reports.staffLevel, that it is still open,
-- the message length and the per-sender rate limit, and writes the audit entry.
Kora.callback.register('qbadmin:reportChatSend', function(src, id, message)
    if not Admin.reportChat() then return nil, 'report chat is disabled' end
    if type(message) ~= 'string' then return nil, 'message required' end
    if #message > 8 * Config.reports.maxMessageLength then return nil, 'message too long' end
    local ok, err = Admin.replyToReport(src, id, message, { chat = true })
    if not ok then return nil, err end
    return true
end, { rateLimit = { max = 10, window = 10000 } })
