-- /warn, /warnings, /kick, /ban, /unban, /freeze, /kill, /heal, /revive, /god, /invisible

local OPTS_MOD = { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'kora_admin' }
local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'kora_admin' }

---Parse a ban duration string. 'perm'/'permanent' -> nil expire, nil error
---(permanent ban). '<n><m|h|d|w>' -> unix expire timestamp. Anything else is
---an error. Note nil expire is legitimately returned on success (permanent)
---as well as failure -- callers must branch on the error, not on expire.
---@param str string
---@return integer|nil expire
---@return string|nil err
local function parseDuration(str)
    if not str or str == '' then return nil, 'duration required' end
    if Config.ban.durationWords[str:lower()] then return nil end

    local amount, unit = str:match('^(%d+)(%a)$')
    amount = tonumber(amount)
    local seconds = amount and Config.ban.durationUnits[unit]
    if not seconds then
        return nil, ("invalid duration '%s' (use e.g. 30m, 2h, 7d, 1w, or perm)"):format(str)
    end
    return os.time() + amount * seconds
end

Admin.addCommand('warn', 'Warn a player', { { name = 'id' }, { name = 'reason' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end
    local reason = table.concat(args, ' ', 2)
    if reason == '' then return Admin.respond(source, false, 'a reason is required') end

    Admin.respond(targetSrc, false, ('You have been warned: %s'):format(reason), { title = 'Warning' })
    Admin.log(source, 'warn', data, { reason = reason })
    Admin.respond(source, true, ('Warned %s'):format(data.name))
end, OPTS_MOD)

Admin.addCommand('warnings', "Show a player's warning history", { { name = 'id' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    local rows = Admin.queryLogs({ action = 'warn', target = data.citizenid })
    if #rows == 0 then return Admin.respond(source, false, 'no warnings on record') end

    local lines = {}
    for _, row in ipairs(rows) do
        local details = {}
        if row.details then
            local ok, decoded = pcall(json.decode, row.details)
            if ok and type(decoded) == 'table' then details = decoded end
        end
        lines[#lines + 1] = ('%s - %s: %s'):format(tostring(row.created_at), row.actor_name, details.reason or '?')
    end
    Admin.chat(source, table.concat(lines, '\n'))
end, OPTS_MOD)

Admin.addCommand('kick', 'Kick a player', { { name = 'id', help = 'server id, or "me"/omit for self' }, { name = 'reason' } }, false,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end
        local reason = table.concat(args, ' ', 2)
        if reason == '' then reason = 'Kicked by an administrator' end

        Admin.log(source, 'kick', data, { reason = reason })
        DropPlayer(targetSrc, reason)
        Admin.respond(source, true, ('Kicked %s'):format(data.name))
    end, OPTS_MOD)

Admin.addCommand('ban', 'Ban a player, online or offline', { { name = 'target' }, { name = 'duration' }, { name = 'reason' } }, true,
    function(source, args)
        local citizenid, name, identifiers, resolveErr = Admin.resolveOfflineTarget(args[1])
        if not citizenid then return Admin.respond(source, false, resolveErr) end

        local expire, durationErr = parseDuration(args[2])
        if durationErr then return Admin.respond(source, false, durationErr) end

        local reason = table.concat(args, ' ', 3)
        if reason == '' then reason = 'No reason given' end

        -- Advisory alt detection only -- never auto-banned, just surfaced.
        local possibleAlts = {}
        if identifiers.license then
            for _, cid in ipairs(exports.kora_core:findByIdentifier('license', identifiers.license)) do
                if cid ~= citizenid then possibleAlts[#possibleAlts + 1] = cid end
            end
        end

        local _, actorName = Admin.actorIdentity(source)
        local banId, insertErr = QB.sql.insert(
            'INSERT INTO `bans` (`name`,`license`,`discord`,`ip`,`reason`,`expire`,`bannedby`) VALUES (?,?,?,?,?,?,?)',
            { name, identifiers.license, identifiers.discord, identifiers.ip, reason, expire, actorName }
        )
        if not banId then return Admin.respond(source, false, insertErr or 'could not persist ban') end

        Admin.log(source, 'ban', { citizenid = citizenid, license = identifiers.license, name = name },
            { banId = banId, reason = reason, expire = expire, possibleAlts = possibleAlts })

        for _, onlineSrc in ipairs(exports.kora_core:getPlayers()) do
            local onlineData = exports.kora_core:getPlayer(onlineSrc)
            if onlineData and onlineData.citizenid == citizenid then
                DropPlayer(onlineSrc, ('Banned: %s'):format(reason))
                break
            end
        end

        local altsMsg = #possibleAlts > 0 and (' Possible alts: ' .. table.concat(possibleAlts, ', ')) or ''
        Admin.respond(source, true, ('Banned %s (%s).%s'):format(
            name or citizenid, expire and os.date('%Y-%m-%d %H:%M', expire) or 'permanent', altsMsg))
    end, OPTS_ADMIN)

Admin.addCommand('unban', 'Lift a ban by license or ban id (preserves history)', { { name = 'licenseOrId' } }, true,
    function(source, args)
        local arg = args[1]
        if not arg or arg == '' then return Admin.respond(source, false, 'license or ban id required') end

        local id = tonumber(arg)
        local result
        if id then
            result = QB.sql.execute(
                'UPDATE `bans` SET `expire` = ? WHERE `id` = ? AND (`expire` IS NULL OR `expire` > ?)', { os.time(), id, os.time() })
        else
            result = QB.sql.execute(
                'UPDATE `bans` SET `expire` = ? WHERE `license` = ? AND (`expire` IS NULL OR `expire` > ?)', { os.time(), arg, os.time() })
        end

        local rows = result and result.affectedRows or 0
        if rows == 0 then return Admin.respond(source, false, 'no active ban matched') end

        Admin.log(source, 'unban', { license = not id and arg or nil }, { banId = id })
        Admin.respond(source, true, ('Lifted %d ban(s)'):format(rows))
    end, OPTS_ADMIN)

Admin.addCommand('freeze', 'Freeze/unfreeze a player', { { name = 'id' }, { name = 'state' } }, false, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    local state, stateErr = Admin.resolveToggle(args[2], Admin.states.frozen[targetSrc] == true)
    if state == nil then return Admin.respond(source, false, stateErr) end
    Admin.states.frozen[targetSrc] = state
    TriggerClientEvent('qbadmin:client:freeze', targetSrc, state)
    Admin.refreshMenuPlayerState(source, targetSrc)
    Admin.log(source, 'freeze', data, { state = state })
    Admin.respond(source, true, ('%s %s'):format(state and 'Froze' or 'Unfroze', data.name))
end, OPTS_MOD)

Admin.addCommand('kill', 'Kill a player', { { name = 'id' } }, false, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    TriggerClientEvent('qbadmin:client:kill', targetSrc)
    Admin.log(source, 'kill', data)
    Admin.respond(source, true, ('Killed %s'):format(data.name))
end, OPTS_MOD)

Admin.addCommand('heal', 'Fully heal a player', { { name = 'id' } }, false, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    TriggerClientEvent('qbadmin:client:heal', targetSrc)
    Admin.log(source, 'heal', data)
    Admin.respond(source, true, ('Healed %s'):format(data.name))
end, OPTS_MOD)

Admin.addCommand('revive', 'Revive a downed player', { { name = 'id' } }, false, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    TriggerClientEvent('qbadmin:client:revive', targetSrc)
    exports.kora_core:setMetaData(targetSrc, 'isdead', false)
    exports.kora_core:setMetaData(targetSrc, 'inlaststand', false)
    Admin.log(source, 'revive', data)
    Admin.respond(source, true, ('Revived %s'):format(data.name))
end, OPTS_MOD)

Admin.addCommand('god', 'Toggle god mode (invincibility)', { { name = 'id' }, { name = 'state' } }, false, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end
    if targetSrc ~= source and not Admin.checkLevel(source, 'admin') then
        return Admin.respond(source, false, 'admin level required to toggle god mode on another player')
    end

    local state, stateErr = Admin.resolveToggle(args[2], Admin.states.god[targetSrc] == true)
    if state == nil then return Admin.respond(source, false, stateErr) end
    Admin.states.god[targetSrc] = state
    TriggerClientEvent('qbadmin:client:god', targetSrc, state)
    Admin.refreshMenuPlayerState(source, targetSrc)
    Admin.log(source, 'god', data, { state = state })
    Admin.respond(source, true, ('God mode %s for %s'):format(state and 'enabled' or 'disabled', data.name))
end, OPTS_MOD)

Admin.addCommand('devmode', 'Toggle core development mode', { { name = 'id' }, { name = 'state' } }, false, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end
    if targetSrc ~= source and not Admin.checkLevel(source, 'admin') then
        return Admin.respond(source, false, 'admin level required to toggle development mode on another player')
    end

    local state, stateErr = Admin.resolveToggle(args[2], exports.kora_core:isDevMode(targetSrc))
    if state == nil then return Admin.respond(source, false, stateErr) end

    local ok, setErr = exports.kora_core:setDevMode(targetSrc, state)
    if not ok then return Admin.respond(source, false, setErr or 'could not update development mode') end

    Admin.refreshMenuPlayerState(source, targetSrc)
    Admin.log(source, 'devmode', data, { state = state })
    Admin.respond(source, true, ('Development mode %s for %s'):format(state and 'enabled' or 'disabled', data.name))
end, OPTS_MOD)

Admin.addCommand('invisible', 'Toggle invisibility', { { name = 'id' }, { name = 'state' } }, false, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end
    if targetSrc ~= source and not Admin.checkLevel(source, 'admin') then
        return Admin.respond(source, false, 'admin level required to toggle invisibility on another player')
    end

    local state, stateErr = Admin.resolveToggle(args[2], Admin.states.invisible[targetSrc] == true)
    if state == nil then return Admin.respond(source, false, stateErr) end
    Admin.states.invisible[targetSrc] = state
    TriggerClientEvent('qbadmin:client:invisible', targetSrc, state)
    Admin.refreshMenuPlayerState(source, targetSrc)
    Admin.log(source, 'invisible', data, { state = state })
    Admin.respond(source, true, ('Invisibility %s for %s'):format(state and 'enabled' or 'disabled', data.name))
end, OPTS_MOD)
