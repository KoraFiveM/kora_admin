-- Keep the real handlers here so Discord calls the same Lua as chat and NUI.
Admin.commands = {}
Admin.commandContexts = {}

local ACCESS_COMMANDS = {
    setpermission = true, revokepermission = true,
    granttempaccess = true, revoketempaccess = true,
}

function Admin.accessCommandAllowed(name)
    return Config.permissions.mode ~= 'discord' or not ACCESS_COMMANDS[name]
end

function Admin.addCommand(name, help, args, argsRequired, handler, options)
    local function run(source, parsedArgs, raw)
        if not Admin.accessCommandAllowed(name) then
            return Admin.respond(source, false, 'Manage access through Discord roles while Discord-only mode is active')
        end
        return handler(source, parsedArgs, raw)
    end
    Kora.commands.add(name, help, args, argsRequired, run, options)
    Admin.commands[name] = {
        help = help, args = args, argsRequired = argsRequired,
        handler = run, permission = options and options.permission or 'user',
    }
end

-- Coroutine-local: SQL/HTTP calls may yield while another admin is working.
function Admin.commandContext(src)
    local context = Admin.commandContexts[coroutine.running()]
    if context and context.source == src then return context end
end

function Admin.actorIdentity(src)
    local context = Admin.commandContext(src)
    if context then
        -- Preserve the license columns' meaning; offline Discord actors are
        -- identified by name and the Discord request audit details.
        return src ~= 0 and exports.kora_core:primary(src) or nil, context.name
    end
    if src == 0 then return nil, 'console' end
    return exports.kora_core:primary(src), GetPlayerName(src) or ('unknown(%d)'):format(src)
end
