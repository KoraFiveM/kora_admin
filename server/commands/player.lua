-- /admin, /players, /sethunger, /setthirst

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'kora_admin' }

Admin.addCommand('admin', 'Open the admin menu', nil, false, function(source)
    -- Refresh the cosmetic client-side filter on every open. Discord roles can
    -- change between heartbeat syncs; the server command gate above remains
    -- authoritative, while this keeps the visible tier in step with it.
    TriggerClientEvent('qbadmin:client:openMenu', source, Admin.getLevel(source))
end, {
    permission = 'support',
    checkPermission = Admin.checkLevel,
    resource = 'kora_admin',
    -- The command dispatcher invokes this only after its server-side gate
    -- denies access. Give the player the exact requirement and their resolved
    -- role tiers instead of its generic permission error.
    notify = function(source)
        QB.notify.send(source, { message = Admin.menuAccessDeniedMessage(source, 'support'), type = 'error' })
    end,
    keybind = {
        description = Config.keybind.label,
        defaultMapper = 'keyboard',
        defaultKey = Config.keybind.defaultKey,
    },
})

Admin.addCommand('players', 'List online players', { { name = 'search', help = 'optional name filter' } }, false,
    function(source, args)
        local search = args[1] and args[1]:lower() or nil
        local lines = {}
        for _, src in ipairs(exports.kora_core:getPlayers()) do
            local name = GetPlayerName(src) or 'unknown'
            if not search or name:lower():find(search, 1, true) then
                local job = exports.kora_core:getJob(src)
                lines[#lines + 1] = ('#%d  %s  [%s]  %dms'):format(src, name, job and job.label or '?', GetPlayerPing(src))
            end
        end
        if #lines == 0 then
            Admin.respond(source, false, 'no players matched')
            return
        end
        Admin.chat(source, table.concat(lines, '\n'))
    end, { permission = 'support', checkPermission = Admin.checkLevel, resource = 'kora_admin' })

local function addSetNeedCommand(commandName, metadataKey, label)
    Admin.addCommand(commandName, ('Set a player\'s %s'):format(label:lower()),
        { { name = 'id' }, { name = 'value', help = '0-100' } }, true,
        function(source, args)
            local targetSrc, data, err = Admin.resolveTarget(source, args[1])
            if not targetSrc then return Admin.respond(source, false, err) end

            local value = Admin.finiteNumber(args[2], 0, 100)
            if value == nil then
                return Admin.respond(source, false, ('%s must be between 0 and 100'):format(label))
            end

            local ok, setErr = exports.kora_core:setMetaData(targetSrc, metadataKey, value)
            if not ok then return Admin.respond(source, false, setErr or ('could not set %s'):format(label:lower())) end

            Admin.log(source, commandName, data, { value = value })
            Admin.respond(source, true, ('Set %s\'s %s to %s'):format(data.name, label:lower(), value))
        end, OPTS_ADMIN)
end

addSetNeedCommand('sethunger', 'hunger', 'Hunger')
addSetNeedCommand('setthirst', 'thirst', 'Thirst')
