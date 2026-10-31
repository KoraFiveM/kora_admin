-- Admin.resolveTarget / Admin.resolveOfflineTarget -- the "me" convention and
-- the only place a player-id command argument is turned into a server id (or
-- citizenid) + a snapshot. Every command with an `[id=me]` argument calls
-- resolveTarget; only /ban and /unban (which must work on an offline player)
-- call resolveOfflineTarget instead, and deliberately do not accept 'me'.

---Resolve an online player from a command argument. nil/''/'me' resolves to
---the actor themselves; numeric resolves to that server id; anything else is
---a case-insensitive substring match against online player names.
---@param actorSrc integer
---@param arg string|nil
---@return integer|nil targetSrc
---@return table|nil playerData
---@return string|nil err
function Admin.resolveTarget(actorSrc, arg)
    if arg == nil or arg == '' or arg:lower() == 'me' then
        local data = exports.kora_core:getPlayer(actorSrc)
        if not data then return nil, nil, 'you are not logged in' end
        return actorSrc, data
    end

    local id = tonumber(arg)
    if id then
        local data = exports.kora_core:getPlayer(id)
        if not data then return nil, nil, 'that player is not online' end
        return id, data
    end

    local needle = arg:lower()
    local matches = {}
    for _, src in ipairs(exports.kora_core:getPlayers()) do
        local name = GetPlayerName(src)
        if name and name:lower():find(needle, 1, true) then
            matches[#matches + 1] = src
        end
    end

    if #matches == 0 then return nil, nil, 'no matching player found' end
    if #matches > 1 then
        local names = {}
        for i, src in ipairs(matches) do names[i] = ('%s (%d)'):format(GetPlayerName(src), src) end
        return nil, nil, ('ambiguous, matches: %s'):format(table.concat(names, ', '))
    end

    local src = matches[1]
    return src, exports.kora_core:getPlayer(src)
end

---Resolve a player for offline-capable actions (ban/unban). Tries an online
---match first, then a citizenid, then a name lookup against the `players`
---table. Never treats a missing/'me' arg as self -- banning yourself by
---accident via the "me" convenience is not a case worth supporting.
---@param arg string
---@return string|nil citizenid
---@return string|nil name
---@return table|nil identifiers  -- {license, discord?, ip?}, best-known
---@return string|nil err
function Admin.resolveOfflineTarget(arg)
    if not arg or arg == '' then return nil, nil, nil, 'target required' end

    local id = tonumber(arg)
    if id then
        local data = exports.kora_core:getPlayer(id)
        if data then
            return data.citizenid, data.name, exports.kora_core:getIdentifiers(id)
        end
    end

    local byCid = exports.kora_core:getPlayerByCitizenId(arg)
    if byCid then
        return byCid.citizenid, byCid.name, { license = byCid.license }
    end

    local row = Kora.sql.single(
        'SELECT `citizenid`, `license`, `name` FROM `players` WHERE `deleted_at` IS NULL AND `name` LIKE ? ORDER BY `last_updated` DESC LIMIT 1',
        { '%' .. arg .. '%' }
    )
    if not row then return nil, nil, nil, 'no matching player found (online, citizenid, or name)' end

    local identifiers = { license = row.license }
    local discordRow = Kora.sql.single(
        'SELECT `value` FROM `player_identifiers` WHERE `citizenid` = ? AND `kind` = ? LIMIT 1', { row.citizenid, 'discord' })
    if discordRow then identifiers.discord = discordRow.value end
    local ipRow = Kora.sql.single(
        'SELECT `value` FROM `player_identifiers` WHERE `citizenid` = ? AND `kind` = ? LIMIT 1', { row.citizenid, 'ip' })
    if ipRow then identifiers.ip = ipRow.value end

    return row.citizenid, row.name, identifiers
end
