-- /announce, /weather, /time, /serverinfo, /adminlog
--
-- kora_weathersync owns world state while running. Keep the local relays for
-- standalone servers and for joins while the optional sync resource is stopped.

local OPTS_MOD = { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'kora_admin' }
local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'kora_admin' }

local currentWeather = nil
local currentTime = nil -- { hour, minute }

if Config.world.syncOnPlayerLoaded then
    AddEventHandler('qbcore:server:playerLoaded', function(src)
        if GetResourceState('kora_weathersync') == 'started' then return end
        if currentWeather then TriggerClientEvent('qbadmin:client:setWeather', src, currentWeather) end
        if currentTime then TriggerClientEvent('qbadmin:client:setTime', src, currentTime.hour, currentTime.minute) end
    end)
end

Admin.addCommand('announce', 'Broadcast a message to every player', { { name = 'message' } }, true, function(source, args)
    local message = table.concat(args, ' ')
    if message == '' then return Admin.respond(source, false, 'message required') end

    Kora.notify.sendToAll({ title = 'Announcement', message = message, type = 'info', duration = 8000 })
    Admin.log(source, 'announce', nil, { message = message })
    Admin.respond(source, true, 'Announcement sent')
end, OPTS_ADMIN)

-- Console/RCON only: lets the Discord bot put restart warnings on every player's screen.
-- Usage: kora_broadcast <message>
RegisterCommand('kora_broadcast', function(source, _, raw)
    if source ~= 0 then return end

    local message = raw:match('^%S+%s+(.+)$')
    if not message then return end

    Kora.notify.sendToAll({ title = 'Server', message = message:sub(1, 200), type = 'warning', duration = 60000 })
end, true)

Admin.addCommand('weather', 'Set the server weather', { { name = 'type' } }, true, function(source, args)
    local weatherType = args[1] and args[1]:upper()
    if GetResourceState('kora_weathersync') == 'started' then
        local ok, err = exports['kora_weathersync']:setWeather(weatherType)
        if not ok then return Admin.respond(source, false, err) end
    else
        local valid = false
        for _, w in ipairs(Config.world.weatherTypes) do
            if w == weatherType then valid = true; break end
        end
        if not valid then
            return Admin.respond(source, false, ('unknown weather type (options: %s)'):format(table.concat(Config.world.weatherTypes, ', ')))
        end

        currentWeather = weatherType
        TriggerClientEvent('qbadmin:client:setWeather', -1, weatherType)
    end
    Admin.log(source, 'weather', nil, { type = weatherType })
    Admin.respond(source, true, ('Weather set to %s'):format(weatherType))
end, OPTS_ADMIN)

---A preset is a Config-owned word, not a number the menu supplies, so the NUI
---and a typed '/time night' hand the server the exact same input and travel
---the same validation path below.
---@param name any
---@return table|nil
local function findTimePreset(name)
    if type(name) ~= 'string' then return nil end
    local wanted = name:lower()
    for _, preset in ipairs(Config.world.timePresets) do
        if preset.id == wanted then return preset end
    end
    return nil
end

local function presetNames()
    local names = {}
    for _, preset in ipairs(Config.world.timePresets) do names[#names + 1] = preset.id end
    return table.concat(names, ', ')
end

-- argsRequired=false: minute defaults to 0 below and a preset carries its own,
-- so only the first argument is truly required.
Admin.addCommand('time', 'Set the server clock', { { name = 'hour|preset' }, { name = 'minute' } }, false, function(source, args)
    local preset = findTimePreset(args[1])
    local hour, minute

    if preset then
        -- Config values are re-checked exactly like typed digits: a mistyped
        -- preset (hour = 25) must be refused here rather than reaching
        -- NetworkOverrideClockTime with a nonsense clock.
        hour = Admin.finiteNumber(preset.hour, 0, 23, true)
        minute = Admin.finiteNumber(preset.minute or 0, 0, 59, true)
        if hour == nil or minute == nil then
            return Admin.respond(source, false,
                ('preset "%s" is misconfigured -- hour must be 0-23 and minute 0-59 in config.lua'):format(preset.id))
        end
    else
        hour = Admin.finiteNumber(args[1], 0, 23, true)
        minute = args[2] == nil and 0 or Admin.finiteNumber(args[2], 0, 59, true)
        -- Naming the presets here is the only hint an admin who typed a word
        -- gets that words are accepted at all.
        if hour == nil then
            return Admin.respond(source, false,
                ('hour must be a whole number from 0-23, or one of: %s'):format(presetNames()))
        end
        if minute == nil then return Admin.respond(source, false, 'minute must be a whole number from 0-59') end
    end

    if GetResourceState('kora_weathersync') == 'started' then
        local ok, err = exports['kora_weathersync']:setTime(hour, minute)
        if not ok then return Admin.respond(source, false, err) end
    else
        currentTime = { hour = hour, minute = minute }
        TriggerClientEvent('qbadmin:client:setTime', -1, hour, minute)
    end
    Admin.log(source, 'time', nil, { hour = hour, minute = minute, preset = preset and preset.id or nil })
    Admin.respond(source, true, preset
        and ('Time set to %s (%02d:%02d)'):format(preset.label, hour, minute)
        or ('Time set to %02d:%02d'):format(hour, minute))
end, OPTS_ADMIN)

Admin.addCommand('serverinfo', 'Show basic server stats', nil, false, function(source)
    local players = exports.kora_core:getPlayers()
    local lines = {
        ('Online players: %d'):format(#players),
        ('Uptime: %d minutes'):format(math.floor(GetGameTimer() / 60000)),
        ('Resources running: %d'):format(GetNumResources()),
    }
    Admin.chat(source, table.concat(lines, '\n'))
end, OPTS_MOD)

Admin.addCommand('adminlog', 'View the admin audit log', { { name = 'action' }, { name = 'target' }, { name = 'page' } }, false,
    function(source, args)
        local rows = Admin.queryLogs({ action = args[1], target = args[2], page = tonumber(args[3]) })
        if #rows == 0 then return Admin.respond(source, false, 'no matching log entries') end

        local lines = {}
        for _, row in ipairs(rows) do
            lines[#lines + 1] = ('%s | %s | %s -> %s | %s'):format(
                tostring(row.created_at), row.action, row.actor_name, row.target_name or '-', row.details or '')
        end
        Admin.chat(source, table.concat(lines, '\n'))
    end, OPTS_ADMIN)
