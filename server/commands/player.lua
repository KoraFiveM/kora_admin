-- /admin, /players, /checkplayer, /sethunger, /setthirst

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'qbadmin' }

QB.commands.add('admin', 'Open the admin menu', nil, false, function(source)
    -- Refresh the cosmetic client-side filter on every open. Discord roles can
    -- change between heartbeat syncs; the server command gate above remains
    -- authoritative, while this keeps the visible tier in step with it.
    TriggerClientEvent('qbadmin:client:openMenu', source, Admin.getLevel(source))
end, {
    permission = 'mod',
    checkPermission = Admin.checkLevel,
    resource = 'qbadmin',
    keybind = {
        description = Config.keybind.label,
        defaultMapper = 'keyboard',
        defaultKey = Config.keybind.defaultKey,
    },
})

QB.commands.add('players', 'List online players', { { name = 'search', help = 'optional name filter' } }, false,
    function(source, args)
        local search = args[1] and args[1]:lower() or nil
        local lines = {}
        for _, src in ipairs(exports.qbcore:getPlayers()) do
            local name = GetPlayerName(src) or 'unknown'
            if not search or name:lower():find(search, 1, true) then
                local job = exports.qbcore:getJob(src)
                lines[#lines + 1] = ('#%d  %s  [%s]  %dms'):format(src, name, job and job.label or '?', GetPlayerPing(src))
            end
        end
        if #lines == 0 then
            Admin.respond(source, false, 'no players matched')
            return
        end
        Admin.chat(source, table.concat(lines, '\n'))
    end, { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'qbadmin' })

QB.commands.add('checkplayer', 'Show a player info panel', { { name = 'id', help = 'server id, or "me"/omit for self' } }, false,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local moneyParts = {}
        for account, amount in pairs(data.money or {}) do
            moneyParts[#moneyParts + 1] = ('%s: %s'):format(account, amount)
        end
        table.sort(moneyParts)

        local lines = {
            ('Player #%d - %s'):format(targetSrc, data.name),
            ('citizenid: %s'):format(data.citizenid),
            ('job: %s (%s) | gang: %s (%s)'):format(
                data.job and data.job.label or '?', data.job and data.job.grade and data.job.grade.name or '?',
                data.gang and data.gang.label or '?', data.gang and data.gang.grade and data.gang.grade.name or '?'
            ),
            ('money: %s'):format(table.concat(moneyParts, ', ')),
            ('health: %d  armor: %d  dead: %s  cuffed: %s'):format(
                GetEntityHealth(GetPlayerPed(targetSrc)), data.metadata and data.metadata.armor or 0,
                tostring(data.metadata and data.metadata.isdead), tostring(data.metadata and data.metadata.ishandcuffed)
            ),
            ('hunger: %s  thirst: %s'):format(
                tostring(data.metadata and data.metadata.hunger or 100),
                tostring(data.metadata and data.metadata.thirst or 100)
            ),
        }

        if Admin.checkLevel(source, 'admin') then
            local ids = exports.qbcore:getIdentifiers(targetSrc)
            lines[#lines + 1] = ('license: %s  discord: %s  ip: %s'):format(ids.license or '?', ids.discord or '?', ids.ip or '?')
        end

        Admin.chat(source, table.concat(lines, '\n'))
    end, { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'qbadmin' })

local function addSetNeedCommand(commandName, metadataKey, label)
    QB.commands.add(commandName, ('Set a player\'s %s'):format(label:lower()),
        { { name = 'id' }, { name = 'value', help = '0-100' } }, true,
        function(source, args)
            local targetSrc, data, err = Admin.resolveTarget(source, args[1])
            if not targetSrc then return Admin.respond(source, false, err) end

            local value = Admin.finiteNumber(args[2], 0, 100)
            if value == nil then
                return Admin.respond(source, false, ('%s must be between 0 and 100'):format(label))
            end

            local ok, setErr = exports.qbcore:setMetaData(targetSrc, metadataKey, value)
            if not ok then return Admin.respond(source, false, setErr or ('could not set %s'):format(label:lower())) end

            Admin.log(source, commandName, data, { value = value })
            Admin.respond(source, true, ('Set %s\'s %s to %s'):format(data.name, label:lower(), value))
        end, OPTS_ADMIN)
end

addSetNeedCommand('sethunger', 'hunger', 'Hunger')
addSetNeedCommand('setthirst', 'thirst', 'Thirst')
