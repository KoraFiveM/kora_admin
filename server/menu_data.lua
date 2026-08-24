-- Read-only data for the admin NUI.  Commands remain the only mutation
-- surface; these callbacks exist so the menu can present useful lists instead
-- of making an administrator type an optional filter before seeing anything.

local function allowed(src, level)
    if not Admin.checkLevel(src, level) then
        return nil, 'permission denied'
    end
    return true
end

QB.callback.register('qbadmin:menuPlayers', function(src)
    local ok, err = allowed(src, 'mod')
    if not ok then return nil, err end

    local players = {}
    for _, playerSrc in ipairs(exports.qbcore:getPlayers()) do
        local job = exports.qbcore:getJob(playerSrc)
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

QB.callback.register('qbadmin:menuAuditLog', function(src, filters)
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
