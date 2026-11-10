local passed = 0
local function test(name, fn)
    fn()
    passed = passed + 1
    print('  PASS  ' .. name)
end
local function equal(actual, expected)
    assert(actual == expected, ('expected %s, got %s'):format(tostring(expected), tostring(actual)))
end

dofile('config.lua')
local timers, registered, api, sql, events = {}, {}, {}, {}, {}
local savedTime, clock = os.time, 1800000000
os.time = function() return clock end
local apiOk, remoteRoles, aceLevel = true, { '200' }, 'owner'
local linkedUser, queuedRoles, restarted = nil, nil, 0
local validate, apply
Kora = {
    commands = { add = function(name, _, _, _, handler) registered[name] = handler end },
    permissions = { getLevel = function(_, _, options)
        if options.discordRoles.moderator and options.discordRoles.moderator[1] == 'new' then return 'moderator' end
        return aceLevel
    end },
    discord = {
        botEnabled = function() return true end,
        hasAnyRole = function(_, roles) return roles[1] == '200' end,
        getRole = function() return nil end,
        getMember = function(guild, user, callback)
            api[#api + 1] = { guild = guild, user = user }
            if queuedRoles then queuedRoles[#queuedRoles + 1] = callback
            else callback(apiOk, { data = { roles = remoteRoles } }) end
        end,
        botRequest = function() end, syncRoles = function() end,
    },
    notify = { send = function(src, data) events[#events + 1] = { target = src, data = data } end,
        sendToAll = function() end },
    sql = { NULL = {}, insert = function(query, params)
        sql[#sql + 1] = { query = query, params = params }; return 1
    end },
    config = { enum = function(value) return value end, string = function(value) return value end,
        boolean = function(value) return value end, integer = function(value) return value end,
        list = function(value) return value end, map = function(value) return value end,
        extend = function(values, options)
            equal(options.scope, 'server')
            for key, value in pairs(values) do
                Config[key] = Config[key] or {}
                for child, item in pairs(value) do Config[key][child] = item end
            end
        end,
        onValidate = function(fn) validate = fn end, onApply = function(fn) apply = fn end,
    },
}
local convars = { kora_lib_discord_guild_id = '900' }
function GetConvar(name, fallback) return convars[name] or fallback end
function SetConvar(name, value) convars[name] = value end
function GetCurrentResourceName() return 'kora_admin' end
function GetInvokingResource() return 'kora_admin' end
function GetPlayerName(src) return src == 12 and 'Target' or nil end
function GetPlayerIdentifierByType() return linkedUser and 'discord:' .. linkedUser or nil end
function GetGameTimer() return 60000 end
function AddEventHandler() end
function RegisterNetEvent() end
function RegisterCommand() end
function TriggerClientEvent(event, target) events[#events + 1] = { event = event, target = target } end
function SetTimeout(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end
function CreateThread(fn) local co = coroutine.create(fn); assert(coroutine.resume(co)); return co end
function ExecuteCommand() error('Discord must not dispatch arbitrary console text') end
function DropPlayer() end
promise = { new = function() return { resolve = function(self, value) self.value = value end } end }
Citizen = { Await = function(result)
    if result.value == nil then coroutine.yield() end
    return result.value
end }
json = { encode = function(value) return value end, decode = function(value) return value end }
exports = setmetatable({ kora_core = {
    getPlayers = function() return { 12 } end,
    getPlayer = function(_, src) return src == 12 and { citizenid = 'CID12', name = 'Target', license = 'license:target' } or nil end,
    primary = function() return 'license:target' end,
    getIdentifiers = function() return { license = 'license:target', discord = 'discord:target', ip = '127.0.0.1' } end,
    findByIdentifier = function() return {} end,
    setMetaData = function() return true end,
}, kora_admin = {
    discordRestartReady = function() return true end,
    discordRestart = function(_, callback) restarted = restarted + 1; callback(true, 'accepted') end,
} }, { __call = function(_, name, callback) exports.kora_admin[name] = callback end })

dofile('server/config.lua')
dofile('server/core.lua')
dofile('server/command_registry.lua')
dofile('server/permissions.lua')
dofile('server/target.lua')
dofile('server/response.lua')
dofile('server/audit.lua')
dofile('server/commands/moderation.lua')
dofile('server/commands/privileged.lua')
dofile('server/commands/teleport.lua')
dofile('server/discord.lua')
Config.discord.enabled, Config.discord.applicationId, Config.discord.channels = true, '901', { '902' }
Config.discord.publicKey = string.rep('a', 64)
Config.permissions.discordRoles = { moderator = { '200' }, owner = { '400' } }

local nextId = 100
local function interaction(action, values)
    nextId = nextId + 1
    local options = {}
    for name, value in pairs(values or {}) do options[#options + 1] = { name = name, value = value } end
    return { id = tostring(nextId), application_id = '901', guild_id = '900', channel_id = '902', type = 2,
        member = { user = { id = '1000' }, roles = { '400' } },
        data = { name = 'kora_admin', options = { { name = action, options = options } } } }
end
local function execute(value)
    clock = clock + 10
    local response
    local thread = coroutine.create(function() response = Admin.handleDiscordInteraction(value) end)
    assert(coroutine.resume(thread))
    return response, thread
end

test('parser preserves quoted arguments and rejects malformed input', function()
    local args = assert(Admin.parseDiscordArgs([[12 "a reason" 'another value' "a\"b"]]))
    equal(args[2], 'a reason'); equal(args[3], 'another value'); equal(args[4], 'a"b')
    equal(Admin.parseDiscordArgs('"unclosed'), nil)
    equal(Admin.parseDiscordArgs('bad\ninput'), nil)
end)

test('wrong guild/channel and API failures fail closed; signed member roles do not grant access', function()
    local value = interaction('status'); value.guild_id = '999'
    equal(execute(value).ok, false); equal(#api, 0)
    value = interaction('status'); value.channel_id = '999'
    equal(execute(value).ok, false); equal(#api, 0)
    apiOk = false; equal(execute(interaction('status')).ok, false); apiOk = true
    remoteRoles = {}; equal(execute(interaction('status')).ok, false); remoteRoles = { '200' }
    equal(execute(interaction('run', { command = 'ban', arguments = '12 perm testing', confirm = true })).ok, false)
end)

test('offline Discord staff use real handlers, keep inner rank gates, and receive named audit entries', function()
    local response = execute(interaction('run', { command = 'heal', arguments = '12' }))
    equal(response.ok, true); assert(response.message:find('Healed Target', 1, true))
    local audit = sql[#sql].params
    equal(audit[2], Kora.sql.NULL); equal(audit[3], 'Discord 1000'); equal(audit[7].discord_id, '1000')
    equal(execute(interaction('run', { command = 'god', arguments = '12 on' })).ok, false)
    equal(execute(interaction('run', { command = 'noclip' })).ok, false)
    equal(execute(interaction('run', { command = 'quit; restart' })).ok, false)
    equal(next(Admin.commandContexts), nil)
end)

test('owner actions require confirmation and bans persist the Discord actor', function()
    remoteRoles = { '400' }
    equal(execute(interaction('run', { command = 'ban', arguments = '12 perm testing' })).ok, false)
    equal(execute(interaction('run', { command = 'ban', arguments = '12 perm testing', confirm = true })).ok, true)
    for _, row in ipairs(sql) do
        if row.query:find('INSERT INTO `bans`', 1, true) then equal(row.params[7], 'Discord 1000'); return end
    end
    error('ban was not persisted')
end)

test('Discord-only mode ignores ACE/temporary grants, blocks access mutations, and applies new role maps', function()
    Config.permissions.mode = 'discord'
    Admin.temporaryGrants['license:target'] = { owner = clock + 1000 }
    equal(Admin.getLevel(12), 'moderator')
    equal(Admin.accessCommandAllowed('setpermission'), false)
    equal(exports.kora_admin.canEditConfig(12), false)
    Config.permissions.mode = 'ace_discord'
    Admin.temporaryGrants = {}
    Config.permissions.discordRoles = { moderator = { 'new' }, owner = { '400' } }
    equal(Admin.getLevel(12), 'moderator')
    Config.permissions.discordRoles = { moderator = { '200' }, owner = { '400' } }
end)

test('yielding commands keep actor context separate from another request and normal game permissions', function()
    Admin.addCommand('yielding', 'test', nil, false, function(src)
        coroutine.yield()
        Admin.respond(src, true, Admin.getLevel(src))
    end, { permission = 'admin', resource = 'kora_admin' })
    local value = interaction('run', { command = 'yielding' })
    local response, thread = execute(value)
    equal(response, nil); equal(coroutine.status(thread), 'suspended')
    equal(Admin.getLevel(12), 'owner')
    remoteRoles = { '200' }
    equal(execute(interaction('run', { command = 'yielding' })).ok, false)
    assert(coroutine.resume(thread)); equal(next(Admin.commandContexts), nil)
    remoteRoles = { '400' }
end)

test('restart requires confirmation and re-checks roles when the countdown expires', function()
    Config.discord.restartEnabled = true
    equal(execute(interaction('restart', { reason = 'Maintenance' })).ok, false)
    equal(execute(interaction('restart', { reason = 'Maintenance', confirm = true })).ok, true)
    equal(execute(interaction('restart', { reason = 'Duplicate', confirm = true })).ok, false)
    remoteRoles = { '200' }
    for index = #timers, 1, -1 do
        if timers[index].delay == 60000 then timers[index].fn(); break end
    end
    equal(restarted, 0)
    remoteRoles = { '400' }
    equal(execute(interaction('restart', { reason = 'Maintenance', confirm = true })).ok, true)
    for index = #timers, 1, -1 do
        if timers[index].delay == 60000 then timers[index].fn(); break end
    end
    equal(restarted, 1)
end)

test('configuration validation prevents a role-only lockout and invalid channel IDs', function()
    equal(validate(Config), true)
    Config.discord.channels = { 'not-an-id' }; equal(validate(Config), false)
    Config.discord.channels = { '902' }; Config.permissions.mode = 'discord'
    Config.permissions.discordRoles.owner = {}; equal(validate(Config), false)
    Config.permissions.discordRoles.owner = { '400' }; equal(validate(Config), true)
end)

test('the deprecated kora_lib_discord_guild_id convar is still honoured', function()
    local saved = convars
    convars = { kora_lib_discord_guild_id = '900' }
    equal(execute(interaction('status')).ok, true)
    local wrongGuild = interaction('status'); wrongGuild.guild_id = '999'
    equal(execute(wrongGuild).ok, false)
    convars = saved
end)

os.time = savedTime
print(('kora_admin Discord: %d passed'):format(passed))
