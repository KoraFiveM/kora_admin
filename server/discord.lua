-- Discord verifies the transport in discord.js; this file owns staff policy.
local cooldowns = {}
local restartPending = false
local registrationGeneration = 0

local PLAYER_COMMANDS = {
    admin = true, config = true, aduty = true, coords = true, vec4 = true,
    health = true, armor = true, selfrevive = true, car = true, dv = true, fix = true,
    ['goto'] = true, bring = true, tpm = true, tpcoords = true, tpback = true,
    spectate = true, noclip = true, entity = true, deleteentity = true,
    entitypicker = true, devplacement = true, devzone = true, report = true,
}

local function contains(values, wanted)
    for _, value in ipairs(values or {}) do if value == wanted then return true end end
    return false
end

-- kora_lib_discord_guild_id supersedes the deprecated qblib_discord_guild_id,
-- which stays readable for servers that configured it before the rename.
local function guildConvar()
    local value = GetConvar('kora_lib_discord_guild_id', '')
    if value ~= '' then return value end
    return GetConvar('qblib_discord_guild_id', '')
end

local function guildId()
    local configured = Config.discord.guildId
    return configured ~= '' and configured or guildConvar()
end

function Admin.parseDiscordArgs(text)
    if text == nil or text == '' then return {} end
    if type(text) ~= 'string' or #text > 2000 or text:find('%c') then return nil, 'invalid arguments' end
    local args, current, quote = {}, '', nil
    local started, index = false, 1
    while index <= #text do
        local char = text:sub(index, index)
        if char == '\\' and quote and (text:sub(index + 1, index + 1) == quote or text:sub(index + 1, index + 1) == '\\') then
            index = index + 1
            current = current .. text:sub(index, index)
        elseif quote then
            if char == quote then quote = nil else current = current .. char end
        elseif char == '"' or char == "'" then
            quote, started = char, true
        elseif char:match('%s') then
            if started then args[#args + 1] = current; current, started = '', false end
        else
            current, started = current .. char, true
        end
        if #args > 32 then return nil, 'too many arguments' end
        index = index + 1
    end
    if quote then return nil, 'unclosed quote in arguments' end
    if started then args[#args + 1] = current end
    if #args > 32 then return nil, 'too many arguments' end
    return args
end

local function freshLevel(userId)
    local result = promise.new()
    local finished = false
    local function finish(level, err)
        if finished then return end
        finished = true
        result:resolve({ level = level, error = err })
    end
    SetTimeout(10000, function() finish(nil, 'Discord role verification timed out') end)
    Kora.discord.getMember(guildId(), userId, function(ok, response)
        local member = response and response.data
        if not ok or type(member) ~= 'table' or type(member.roles) ~= 'table' then
            return finish(nil, 'Could not verify your current Discord roles')
        end
        local levels, canonical = Admin.aceLevels()
        for _, level in ipairs(levels) do
            for _, role in ipairs(Config.permissions.discordRoles[level] or {}) do
                local resolved = role:match('^%d+$') and role or nil
                if not resolved then
                    local cached = Kora.discord.getRole(role, guildId())
                    resolved = cached and cached.id
                end
                if resolved and contains(member.roles, resolved) then return finish(canonical[level]) end
            end
        end
        finish('user')
    end)
    local resolved = Citizen.Await(result)
    return resolved.level, resolved.error
end

local function playerSource(userId)
    for _, src in ipairs(exports.kora_core:getPlayers()) do
        if GetPlayerIdentifierByType(src, 'discord') == 'discord:' .. userId then return src end
    end
    return 0
end

local function runCommand(context, name, args, confirmed)
    if type(name) ~= 'string' then return Admin.respond(context.source, false, 'command required') end
    name = name:lower():gsub('^/', '')
    local definition = Admin.commands[name]
    if not definition or contains(Config.discord.disabledCommands, name) then
        return Admin.respond(context.source, false, 'That qbadmin command is unavailable')
    end
    local required = definition.permission
    if required == 'user' then required = context.source == 0 and Config.reports.staffLevel or 'support' end
    if not Admin.checkLevel(context.source, required) then
        return Admin.respond(context.source, false, 'Your Discord roles do not allow this command')
    end
    if not Admin.accessCommandAllowed(name) then
        return Admin.respond(context.source, false, 'Manage access through Discord roles while Discord-only mode is active')
    end
    if name == 'restartresource' and (args[1] == 'kora_admin' or args[1] == 'kora_lib' or args[1] == 'monitor') then
        return Admin.respond(context.source, false, 'Restart this resource from txAdmin so the Discord response can complete')
    end
    if PLAYER_COMMANDS[name] and context.source == 0 then
        return Admin.respond(0, false, 'Join the game with this Discord account to use this command')
    end
    if contains(Config.discord.confirmCommands, name) and confirmed ~= true then
        return Admin.respond(context.source, false, 'Set confirm to true to run this command')
    end
    if definition.argsRequired and definition.args and #args < #definition.args then
        return Admin.respond(context.source, false, ('Missing arguments for /%s'):format(name))
    end
    Admin.log(context.source, 'discord.command', nil, {
        command = name, args = args, discord_id = context.userId,
        channel_id = context.channelId, interaction_id = context.interactionId,
    })
    if context.source ~= 0 and GetPlayerIdentifierByType(context.source, 'discord') ~= 'discord:' .. context.userId then
        return Admin.respond(context.source, false, 'Your in-game session changed; retry the command')
    end
    definition.handler(context.source, args, name .. ' ' .. table.concat(args, ' '))
    if #context.messages == 0 then
        context.messages[1] = 'Command dispatched. In-game actions report completion in the game.'
    end
end

local function scheduleRestart(context, reason, confirmed)
    if not Config.discord.restartEnabled then return Admin.respond(context.source, false, 'Server restarts are disabled') end
    if not Admin.checkLevel(context.source, Config.discord.restartRole) then
        return Admin.respond(context.source, false, 'Your Discord roles do not allow server restarts')
    end
    if confirmed ~= true then return Admin.respond(context.source, false, 'Set confirm to true to restart the server') end
    if type(reason) ~= 'string' or #reason < 3 or #reason > 256 or reason:find('%c') then
        return Admin.respond(context.source, false, 'Provide a restart reason (3-256 characters)')
    end
    if restartPending then return Admin.respond(context.source, false, 'A Discord restart is already pending') end
    local ready = exports.kora_admin:discordRestartReady()
    if ready ~= true then return Admin.respond(context.source, false, 'Configure the txAdmin restart credentials first') end
    local delay = Config.discord.restartDelaySeconds
    Admin.log(context.source, 'discord.restart.scheduled', nil, {
        discord_id = context.userId, reason = reason, delay_seconds = delay,
    })
    restartPending = true
    Kora.notify.sendToAll({ title = 'Server restart', message = ('Restart in %d seconds: %s'):format(delay, reason),
        type = 'warning', duration = 10000 })
    SetTimeout(delay * 1000, function()
        CreateThread(function()
            local level = freshLevel(context.userId)
            local rank, required = level and Admin.roleRank(level), Admin.roleRank(Config.discord.restartRole)
            if not Config.discord.enabled or not Config.discord.restartEnabled or not rank or not required or rank < required
                or guildId() ~= context.guildId or Config.discord.applicationId ~= context.applicationId
                or not contains(Config.discord.channels, context.channelId) then
                restartPending = false
                Admin.log(0, 'discord.restart.cancelled', nil, { discord_id = context.userId, reason = 'Access or configuration changed' })
                Kora.notify.sendToAll({ title = 'Server restart cancelled', message = 'Restart authorization is no longer available.', type = 'info' })
                return
            end
            Admin.commandContexts[coroutine.running()] = context
            Admin.log(context.source, 'discord.restart.executing', nil, { discord_id = context.userId, reason = reason })
            Admin.commandContexts[coroutine.running()] = nil
            exports.kora_admin:discordRestart(function(ok, message)
                restartPending = false
                if ok then return end
                -- SQL may yield; keep it outside the JavaScript callback stack.
                CreateThread(function()
                    print(('^1[qbadmin:discord]^7 txAdmin restart failed: %s'):format(tostring(message)))
                    Admin.log(0, 'discord.restart.failed', nil, { discord_id = context.userId, error = tostring(message) })
                    Kora.notify.sendToAll({ title = 'Server restart unconfirmed', message = 'txAdmin did not confirm the restart. Staff should check its control panel.', type = 'error' })
                end)
            end)
        end)
    end)
    Admin.respond(context.source, true, ('Server restart scheduled in %d seconds. Reason: %s'):format(delay, reason))
end

local function optionValues(interaction)
    local subcommand = interaction.data and interaction.data.options and interaction.data.options[1]
    local values = {}
    for _, option in ipairs(subcommand and subcommand.options or {}) do values[option.name] = option.value end
    return subcommand and subcommand.name, values
end

function Admin.handleDiscordInteraction(interaction)
    local settings = Config.discord
    local member = interaction.member
    local userId = member and member.user and member.user.id
    if not settings.enabled or interaction.application_id ~= settings.applicationId
        or interaction.guild_id ~= guildId() or not contains(settings.channels, interaction.channel_id)
        or interaction.type ~= 2 or not interaction.data or interaction.data.name ~= 'qbadmin'
        or type(userId) ~= 'string' or not userId:match('^%d+$') then
        return { ok = false, message = 'Discord administration is unavailable in this server or channel' }
    end
    local now = os.time()
    if cooldowns[userId] and cooldowns[userId] > now then return { ok = false, message = 'Wait a few seconds before another command' } end
    cooldowns[userId] = now + settings.cooldownSeconds
    SetTimeout(settings.cooldownSeconds * 1000, function()
        if cooldowns[userId] and cooldowns[userId] <= os.time() then cooldowns[userId] = nil end
    end)

    local level, err = freshLevel(userId)
    if not level then return { ok = false, message = err } end
    -- Re-check live policy after the yielding Discord request.
    if not Config.discord.enabled or interaction.application_id ~= Config.discord.applicationId
        or interaction.guild_id ~= guildId() or not contains(Config.discord.channels, interaction.channel_id) then
        return { ok = false, message = 'Discord configuration changed; retry the command' }
    end
    local context = {
        source = playerSource(userId), userId = userId, level = level,
        name = 'Discord ' .. userId, channelId = interaction.channel_id,
        interactionId = interaction.id, ok = true, messages = {},
        guildId = interaction.guild_id, applicationId = interaction.application_id,
    }
    local thread = coroutine.running()
    Admin.commandContexts[thread] = context
    local worked, failure = xpcall(function()
        if not Admin.checkLevel(context.source, 'support') then
            Admin.log(context.source, 'discord.denied', nil, { discord_id = userId, interaction_id = interaction.id })
            return Admin.respond(context.source, false, 'No staff role is linked to your Discord account')
        end
        local action, values = optionValues(interaction)
        if action == 'run' then
            local args, parseError = Admin.parseDiscordArgs(values.arguments)
            if not args then return Admin.respond(context.source, false, parseError) end
            runCommand(context, values.command, args, values.confirm)
        elseif action == 'commands' then
            local names = {}
            for name, definition in pairs(Admin.commands) do
                if not contains(settings.disabledCommands, name) and Admin.accessCommandAllowed(name)
                    and Admin.checkLevel(context.source, definition.permission == 'user' and 'support' or definition.permission) then
                    names[#names + 1] = '/' .. name .. (PLAYER_COMMANDS[name] and ' (in-game)' or '')
                end
            end
            table.sort(names)
            Admin.chat(context.source, table.concat(names, ', '))
        elseif action == 'status' then
            Admin.chat(context.source, ('Online players: %d\nUptime: %d minutes\nYour tier: %s\nRestart pending: %s')
                :format(#exports.kora_core:getPlayers(), math.floor(GetGameTimer() / 60000), Admin.roleLabel(level), tostring(restartPending)))
        elseif action == 'restart' then
            scheduleRestart(context, values.reason, values.confirm)
        else
            Admin.respond(context.source, false, 'Unknown Discord action')
        end
        Admin.log(context.source, 'discord.result', nil, {
            discord_id = userId, interaction_id = interaction.id, action = action, ok = context.ok,
        })
    end, debug.traceback)
    Admin.commandContexts[thread] = nil
    if not worked then
        print(('^1[qbadmin:discord]^7 command failed: %s'):format(failure))
        return { ok = false, message = 'Command failed. Staff should check the server log.' }
    end
    return { ok = context.ok, message = table.concat(context.messages, '\n') }
end

exports('discordSettings', function()
    return json.encode({ enabled = Config.discord.enabled, publicKey = Config.discord.publicKey,
        applicationId = Config.discord.applicationId })
end)

-- This is a local server export, never a network event. Only the signed HTTP
-- handler in this resource may dispatch a Discord identity.
exports('discordDispatch', function(encoded, callback)
    if GetInvokingResource() ~= GetCurrentResourceName() then return false end
    CreateThread(function()
        local ok, result = pcall(function() return Admin.handleDiscordInteraction(json.decode(encoded)) end)
        callback(json.encode(ok and result or { ok = false, message = 'Discord administration failed' }))
    end)
    return true
end)

local function registrationPayload()
    return {
        name = 'qbadmin', description = 'Server staff administration', type = 1,
        options = {
            { name = 'run', description = 'Run an authorized qbadmin command', type = 1, options = {
                { name = 'command', description = 'Command name (use commands to list)', type = 3, required = true },
                { name = 'arguments', description = 'Arguments, with quotes around values containing spaces', type = 3, max_length = 2000 },
                { name = 'confirm', description = 'Confirm a destructive action', type = 5 },
            } },
            { name = 'commands', description = 'List commands allowed by your Discord roles', type = 1 },
            { name = 'status', description = 'Show server status and your staff tier', type = 1 },
            { name = 'restart', description = 'Restart the full server through txAdmin', type = 1, options = {
                { name = 'reason', description = 'Reason shown to players', type = 3, required = true, min_length = 3, max_length = 256 },
                { name = 'confirm', description = 'Confirm the server restart', type = 5, required = true },
            } },
        },
    }
end

local function configureDiscord()
    registrationGeneration = registrationGeneration + 1
    local generation = registrationGeneration
    if Config.discord.guildId ~= '' then
        SetConvar('kora_lib_discord_guild_id', Config.discord.guildId)
        -- Keep a kora_lib that predates the rename able to resolve the guild.
        SetConvar('qblib_discord_guild_id', Config.discord.guildId)
    end
    if not Config.discord.enabled then return end
    local application, guild = Config.discord.applicationId, guildId()
    if not application:match('^%d+$') or not guild:match('^%d+$') or not Config.discord.publicKey:match('^%x+$')
        or #Config.discord.publicKey ~= 64 then
        return print('^1[qbadmin:discord]^7 Configure the application ID, server ID and public key in appshell before enabling Discord.')
    end
    -- Upsert our one command; never replace another integration's commands.
    Kora.discord.botRequest('POST', '/applications/' .. application .. '/guilds/' .. guild .. '/commands', registrationPayload(), function(ok)
        if generation ~= registrationGeneration then return end
        print(ok and '^2[qbadmin:discord]^7 /qbadmin registered.' or '^1[qbadmin:discord]^7 Could not register /qbadmin; check the bot token and guild access.')
    end)
    Kora.discord.syncRoles()
end

Kora.config.onValidate(function(proposed)
    local settings = proposed.discord
    if settings.enabled then
        if not settings.applicationId:match('^%d+$') or not settings.publicKey:match('^%x+$') or #settings.publicKey ~= 64
            or not (settings.guildId ~= '' and settings.guildId or guildConvar()):match('^%d+$') then
            return false, 'Set a valid Discord application ID, server ID and public key before enabling administration.'
        end
        if not Kora.discord.botEnabled() then return false, 'Set the server-only kora_lib_discord_bot_token first.' end
    end
    if not proposed.permissions.roles[settings.restartRole] then return false, 'Restart tier must be a configured staff role.' end
    for _, id in ipairs(settings.channels) do
        if not id:match('^%d+$') then return false, 'Staff channels must be Discord channel IDs.' end
    end
    if proposed.permissions.mode == 'discord' then
        if not Kora.discord.botEnabled() or not (settings.guildId ~= '' and settings.guildId or guildConvar()):match('^%d+$') then
            return false, 'Configure the Discord bot and server before enabling Discord-only access.'
        end
        local owner = proposed.permissions.discordRoles[proposed.configEditor.level]
        if not owner or #owner == 0 then return false, 'Map the configuration editor role before enabling Discord-only access.' end
    end
    return true
end)

Kora.config.onApply(function(_, _, path)
    if path[1] ~= 'discord' and path[1] ~= 'permissions' then return end
    SetTimeout(0, function()
        if path[1] == 'discord' and (path[2] == 'enabled' or path[2] == 'applicationId' or path[2] == 'guildId' or path[2] == 'publicKey') then
            configureDiscord()
        end
        for _, src in ipairs(exports.kora_core:getPlayers()) do Admin.syncLevel(src) end
    end)
end)

Admin.addCommand('config', 'Open the configuration appshell', nil, false, function(src)
    TriggerClientEvent('kora_lib:client:configOpened', src, 'kora_admin')
end, { permission = Config.configEditor.level, checkPermission = Admin.checkLevel, resource = 'kora_admin' })

SetTimeout(0, configureDiscord)
