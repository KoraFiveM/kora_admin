-- The NUI menu. It never talks to the server directly -- every leaf ends in
-- runCommand(), which is nothing more than ExecuteCommand(table.concat(...)),
-- exactly like this server's own chat resource does for a typed "/command"
-- (cl_chat.lua's ExecuteCommand(data.message:sub(2))). Permission gating,
-- argument parsing, the actual work, logging, and the response toast all
-- happen exactly once, in the command handler -- this file only builds the
-- string and decides which buttons to show.

local function runCommand(...)
    ExecuteCommand(table.concat({ ... }, ' '))
end

local function confirm(message)
    local result = QB.nui.openAlert({ message = message, destructive = true })
    return result and result.confirmed
end

---Player picker: a synthetic "Me" entry first, then every other online
---player. Returns the literal string 'me' or a server-id string, or nil if
---cancelled -- both are valid first arguments to the eventual command.
---@param title string|nil
---@return string|nil
local function pickPlayer(title)
    local items = { { id = 'me', label = 'Me (myself)' } }
    local mySrc = GetPlayerServerId(PlayerId())
    for _, playerId in ipairs(GetActivePlayers()) do
        local serverId = GetPlayerServerId(playerId)
        if serverId ~= mySrc then
            items[#items + 1] = { id = tostring(serverId), label = ('#%d  %s'):format(serverId, GetPlayerName(playerId)) }
        end
    end
    local result = QB.nui.openMenu(items, title or 'Select a player')
    if not result or result.cancelled then return nil end
    return result.selectedId
end

---Fields may be a plain list or a function returning one, resolved right
---before the dialog opens rather than when CATEGORIES is built (see below):
---a field using jobOptions()/itemOptions()/etc. needs QB.shared to have
---already received its mirror snapshot from qbcore, which may not have
---happened yet at resource-start when CATEGORIES itself is constructed.
---@param fields? table[]|fun():table[]
---@return table[]|nil
local function resolveFields(fields)
    if type(fields) == 'function' then return fields() end
    return fields
end

---Pick a player, then optionally collect extra fields via openInputDialog,
---then run `commandName target [field values in order]`. Empty/omitted
---trailing field values are simply not appended (same as a human leaving
---optional trailing chat-command args blank). One generic builder instead of
---one bespoke closure per menu leaf.
---@param commandName string
---@param extraFields? table[]|fun():table[]  -- openInputDialog fields
---@param dialogTitle? string
---@return fun()
local function withPlayer(commandName, extraFields, dialogTitle)
    return function()
        local target = pickPlayer(dialogTitle)
        if not target then return end

        local fields = resolveFields(extraFields)
        if not fields then
            runCommand(commandName, target)
            return
        end

        local result = QB.nui.openInputDialog(fields, dialogTitle or commandName)
        if not result or result.cancelled then return end

        local args = { commandName, target }
        for _, field in ipairs(fields) do
            local value = result.values[field.id]
            if value ~= nil and value ~= '' then args[#args + 1] = tostring(value) end
        end
        runCommand(table.unpack(args))
    end
end

---Same as withPlayer but with no target -- collects fields (if any) and runs
---`commandName [field values]`.
---@param commandName string
---@param fieldsOrFn? table[]|fun():table[]
---@param dialogTitle? string
---@return fun()
local function withFields(commandName, fieldsOrFn, dialogTitle)
    return function()
        local fields = resolveFields(fieldsOrFn)
        if not fields then
            runCommand(commandName)
            return
        end

        local result = QB.nui.openInputDialog(fields, dialogTitle or commandName)
        if not result or result.cancelled then return end

        local args = { commandName }
        for _, field in ipairs(fields) do
            local value = result.values[field.id]
            if value ~= nil and value ~= '' then args[#args + 1] = tostring(value) end
        end
        runCommand(table.unpack(args))
    end
end

local function withConfirm(message, fn)
    return function()
        if confirm(message) then fn() end
    end
end

local function showPlayers()
    local players, err = QB.callback.trigger('qbadmin:menuPlayers')
    if not players then
        QB.notify.send({ type = 'error', message = err or 'Could not load players' })
        return
    end

    if #players == 0 then
        QB.notify.send({ type = 'info', message = 'No players are online' })
        return
    end

    local items = {}
    for _, player in ipairs(players) do
        items[#items + 1] = {
            id = player.id,
            label = ('#%s  %s'):format(player.id, player.name),
            description = ('%s · %dms'):format(player.job, player.ping),
        }
    end
    local result = QB.nui.openMenu(items, 'Online Players')
    if result and not result.cancelled then runCommand('checkplayer', result.selectedId) end
end

local function showAuditLog(filters)
    local rows, err = QB.callback.trigger('qbadmin:menuAuditLog', filters)
    if not rows then
        QB.notify.send({ type = 'error', message = err or 'Could not load audit log' })
        return
    end
    if #rows == 0 then
        QB.notify.send({ type = 'info', message = 'No matching audit entries' })
        return
    end

    local items = {}
    for index, row in ipairs(rows) do
        items[#items + 1] = {
            id = tostring(index),
            label = ('%s · %s'):format(row.action or 'unknown', row.actor_name or 'unknown'),
            description = ('%s → %s · %s'):format(row.target_name or '-', row.created_at or '-', row.details or ''),
            disabled = true,
        }
    end
    QB.nui.openMenu(items, 'Audit Log')
end

local function filterAuditLog()
    local fields = {
        { id = 'action', label = 'Action filter (optional)', type = 'text' },
        { id = 'target', label = 'Target filter (optional)', type = 'text' },
        { id = 'page', label = 'Page', type = 'number', default = 1, min = 1 },
    }
    local result = QB.nui.openInputDialog(fields, 'Filter Audit Log')
    if result and not result.cancelled then showAuditLog(result.values) end
end

local function openClothing(mode)
    if GetResourceState('qbclothing') ~= 'started' then
        QB.notify.send({ type = 'error', message = 'qbclothing is not running' })
        return
    end
    if mode == 'shop' then
        TriggerEvent('qbclothing:client:openNearestShop')
    else
        TriggerEvent('qb-clothing:client:openOutfitMenu')
    end
end

local function jobOptions()
    local out = {}
    for _, job in ipairs(QB.shared.all('jobs')) do out[#out + 1] = { value = job.name, label = job.label } end
    return out
end

local function gangOptions()
    local out = {}
    for _, gang in ipairs(QB.shared.all('gangs')) do out[#out + 1] = { value = gang.name, label = gang.label } end
    return out
end

local function vehicleOptions()
    local out = {}
    for _, veh in ipairs(QB.shared.all('vehicles')) do out[#out + 1] = { value = veh.model, label = ('%s (%s)'):format(veh.name, veh.model) } end
    return out
end

local function itemOptions()
    local out = {}
    for _, item in ipairs(QB.shared.all('items')) do out[#out + 1] = { value = item.name, label = item.label or item.name } end
    return out
end

local function weatherOptions()
    local out = {}
    for _, w in ipairs(Config.world.weatherTypes) do out[#out + 1] = { value = w, label = w } end
    return out
end

local function levelOptions()
    return { { value = 'mod', label = 'mod' }, { value = 'admin', label = 'admin' }, { value = 'god', label = 'god' } }
end

-- name/level/run -- level is this item's OWN gate (may exceed the category's
-- floor, e.g. god/invisible on another player, or the god-only items sitting
-- in an admin-floor category). Filtering here is cosmetic only: every command
-- re-checks server-side regardless of what this menu shows.
local CATEGORIES = {
    {
        id = 'player', label = 'Player Management', level = 'mod',
        items = {
            { id = 'players', label = 'List Players', level = 'mod', run = showPlayers },
            { id = 'checkplayer', label = 'Check Player', level = 'mod', run = withPlayer('checkplayer') },
        },
    },
    {
        id = 'moderation', label = 'Moderation', level = 'mod',
        items = {
            { id = 'warn', label = 'Warn', level = 'mod',
                run = withPlayer('warn', { { id = 'reason', label = 'Reason', type = 'text', required = true } }, 'Warn Player') },
            { id = 'warnings', label = 'Warning History', level = 'mod', run = withPlayer('warnings', nil, 'Warning History') },
            { id = 'kick', label = 'Kick', level = 'mod',
                run = withConfirm('Kick this player?', withPlayer('kick', { { id = 'reason', label = 'Reason', type = 'text' } }, 'Kick Player')) },
            { id = 'ban', label = 'Ban', level = 'admin',
                run = withConfirm('Ban this player? This is persistent.', withFields('ban', {
                    { id = 'target', label = 'Target (server id, citizenid, or name)', type = 'text', required = true },
                    { id = 'duration', label = 'Duration (30m, 2h, 7d, or perm)', type = 'text', default = 'perm', required = true },
                    { id = 'reason', label = 'Reason', type = 'text', required = true },
                }, 'Ban Player')) },
            { id = 'unban', label = 'Unban', level = 'admin',
                run = withFields('unban', { { id = 'target', label = 'License or ban id', type = 'text', required = true } }, 'Unban') },
            { id = 'freeze', label = 'Freeze', level = 'mod',
                run = withPlayer('freeze', { { id = 'state', label = 'State', type = 'select',
                    options = { { value = 'true', label = 'Freeze' }, { value = 'false', label = 'Unfreeze' } }, default = 'true' } }, 'Freeze') },
            { id = 'kill', label = 'Kill', level = 'mod', run = withConfirm('Kill this player?', withPlayer('kill')) },
            { id = 'heal', label = 'Heal', level = 'mod', run = withPlayer('heal') },
            { id = 'revive', label = 'Revive', level = 'mod', run = withPlayer('revive') },
            { id = 'god', label = 'Toggle God Mode', level = 'mod', run = withPlayer('god') },
            { id = 'invisible', label = 'Toggle Invisible', level = 'mod', run = withPlayer('invisible') },
        },
    },
    {
        id = 'teleport', label = 'Teleport / Spectate', level = 'mod',
        items = {
            { id = 'goto', label = 'Goto Player', level = 'mod', run = withPlayer('goto') },
            { id = 'bring', label = 'Bring Player', level = 'mod', run = withPlayer('bring') },
            { id = 'tpm', label = 'Teleport to Waypoint', level = 'mod', run = withFields('tpm') },
            { id = 'tpcoords', label = 'Teleport to Coords', level = 'mod',
                run = withFields('tpcoords', {
                    { id = 'x', label = 'X', type = 'number', required = true },
                    { id = 'y', label = 'Y', type = 'number', required = true },
                    { id = 'z', label = 'Z', type = 'number', required = true },
                }, 'Teleport to Coords') },
            { id = 'tpback', label = 'Teleport Back', level = 'mod', run = withFields('tpback') },
            { id = 'spectate', label = 'Spectate Player', level = 'mod', run = withPlayer('spectate') },
            { id = 'spectateStop', label = 'Stop Spectating', level = 'mod', run = withFields('spectate') },
            { id = 'noclip', label = 'Toggle Noclip', level = 'admin', run = withFields('noclip') },
        },
    },
    {
        id = 'economy', label = 'Economy', level = 'admin',
        items = {
            { id = 'givemoney', label = 'Give Money', level = 'admin',
                run = withPlayer('givemoney', {
                    { id = 'account', label = 'Account (cash/bank/crypto)', type = 'text', required = true },
                    { id = 'amount', label = 'Amount', type = 'number', required = true, min = 1 },
                    { id = 'reason', label = 'Reason', type = 'text' },
                }, 'Give Money') },
            { id = 'removemoney', label = 'Remove Money', level = 'admin',
                run = withPlayer('removemoney', {
                    { id = 'account', label = 'Account (cash/bank/crypto)', type = 'text', required = true },
                    { id = 'amount', label = 'Amount', type = 'number', required = true, min = 1 },
                    { id = 'reason', label = 'Reason', type = 'text' },
                }, 'Remove Money') },
            { id = 'setmoney', label = 'Set Money', level = 'admin',
                run = withPlayer('setmoney', {
                    { id = 'account', label = 'Account (cash/bank/crypto)', type = 'text', required = true },
                    { id = 'amount', label = 'Amount', type = 'number', required = true, min = 0 },
                    { id = 'reason', label = 'Reason', type = 'text' },
                }, 'Set Money') },
            { id = 'giveitem', label = 'Give Item', level = 'admin',
                run = withPlayer('giveitem', function() return {
                    { id = 'item', label = 'Item', type = 'select', options = itemOptions(), required = true },
                    { id = 'amount', label = 'Amount', type = 'number', default = 1, min = 1 },
                } end, 'Give Item') },
            { id = 'removeitem', label = 'Remove Item', level = 'admin',
                run = withPlayer('removeitem', function() return {
                    { id = 'item', label = 'Item', type = 'select', options = itemOptions(), required = true },
                    { id = 'amount', label = 'Amount', type = 'number', default = 1, min = 1 },
                } end, 'Remove Item') },
            { id = 'clearinventory', label = 'Clear Inventory', level = 'admin',
                run = withConfirm("Clear this player's entire inventory?", withPlayer('clearinventory')) },
        },
    },
    {
        id = 'jobgang', label = 'Job / Gang', level = 'mod',
        items = {
            { id = 'setjob', label = 'Set Job', level = 'admin',
                run = withPlayer('setjob', function() return {
                    { id = 'job', label = 'Job', type = 'select', options = jobOptions(), required = true },
                    { id = 'grade', label = 'Grade', type = 'number', default = 1, min = 1 },
                } end, 'Set Job') },
            { id = 'setgang', label = 'Set Gang', level = 'admin',
                run = withPlayer('setgang', function() return {
                    { id = 'gang', label = 'Gang', type = 'select', options = gangOptions(), required = true },
                    { id = 'grade', label = 'Grade', type = 'number', default = 0, min = 0 },
                } end, 'Set Gang') },
            { id = 'setduty', label = 'Toggle Duty', level = 'mod', run = withPlayer('setduty') },
        },
    },
    {
        id = 'vehicle', label = 'Vehicle', level = 'mod',
        items = {
            { id = 'car', label = 'Spawn Vehicle (self)', level = 'admin',
                run = withFields('car', function() return { { id = 'model', label = 'Model', type = 'select', options = vehicleOptions(), required = true } } end, 'Spawn Vehicle') },
            { id = 'veh', label = 'Spawn Vehicle for Player', level = 'admin',
                run = withPlayer('veh', function() return { { id = 'model', label = 'Model', type = 'select', options = vehicleOptions(), required = true } } end, 'Spawn Vehicle') },
            { id = 'dv', label = 'Delete My Vehicle', level = 'admin', visible = function() return QB.cache.vehicle() ~= false end,
                run = withConfirm('Delete the vehicle you are in?', withFields('dv')) },
            { id = 'fix', label = 'Repair My Vehicle', level = 'mod', run = withFields('fix') },
        },
    },
    {
        id = 'world', label = 'World / Server', level = 'mod',
        items = {
            { id = 'announce', label = 'Announce', level = 'admin',
                run = withFields('announce', { { id = 'message', label = 'Message', type = 'textarea', required = true } }, 'Announce') },
            { id = 'weather', label = 'Set Weather', level = 'admin',
                run = withFields('weather', function() return { { id = 'type', label = 'Weather', type = 'select', options = weatherOptions(), required = true } } end, 'Set Weather') },
            { id = 'time', label = 'Set Time', level = 'admin',
                run = withFields('time', {
                    { id = 'hour', label = 'Hour (0-23)', type = 'number', required = true, min = 0, max = 23 },
                    { id = 'minute', label = 'Minute', type = 'number', default = 0, min = 0, max = 59 },
                }, 'Set Time') },
            { id = 'serverinfo', label = 'Server Info', level = 'mod', run = withFields('serverinfo') },
        },
    },
    {
        id = 'audit', label = 'Audit Log', level = 'admin',
        items = {
            { id = 'adminlog', label = 'View Recent Log', level = 'admin', run = showAuditLog },
            { id = 'adminlogfilter', label = 'Filter Log', level = 'admin', run = filterAuditLog },
        },
    },
    {
        id = 'privileged', label = 'Privileged', level = 'god',
        items = {
            { id = 'setpermission', label = 'Grant Permission', level = 'god',
                run = withConfirm('Grant this level? This can create another privileged account.',
                    withPlayer('setpermission', { { id = 'level', label = 'Level', type = 'select', options = levelOptions(), required = true } }, 'Grant Permission')) },
            { id = 'revokepermission', label = 'Revoke Permission', level = 'god',
                run = withPlayer('revokepermission', { { id = 'level', label = 'Level', type = 'select', options = levelOptions(), required = true } }, 'Revoke Permission') },
            { id = 'restartresource', label = 'Restart Resource', level = 'god',
                run = withConfirm('Restart this resource?', withFields('restartresource', { { id = 'name', label = 'Resource name', type = 'text', required = true } }, 'Restart Resource')) },
        },
    },
    {
        id = 'self', label = 'Self / Utility', level = 'mod',
        items = {
            { id = 'aduty', label = 'Toggle Admin Duty', level = 'mod', run = withFields('aduty') },
            { id = 'coords', label = 'Copy Coordinates', level = 'mod', run = withFields('coords') },
            { id = 'health', label = 'Set Health', level = 'mod',
                run = withFields('health', { { id = 'value', label = 'Health (0-100%, blank = full)', type = 'number', min = 0, max = 100 } }, 'Set Health') },
            { id = 'armor', label = 'Set Armor', level = 'mod',
                run = withFields('armor', { { id = 'value', label = 'Armor (blank = full)', type = 'number', min = 0, max = 100 } }, 'Set Armor') },
            { id = 'permission', label = 'My Permission Level', level = 'mod', run = withFields('permission') },
            { id = 'wardrobe', label = 'Open Wardrobe', level = 'mod', run = function() openClothing('wardrobe') end },
            { id = 'clothingshop', label = 'Open Clothing Shop (nearby)', level = 'mod', run = function() openClothing('shop') end },
        },
    },
}

local function openCategory(category)
    local items = {}
    for _, item in ipairs(category.items) do
        -- `visible`, unlike the level check below, hides the item entirely
        -- rather than greying it out: it's for state that makes an item
        -- nonsensical to even offer (e.g. deleting a vehicle you're not in),
        -- not permission, which is always worth showing so a lower-level
        -- admin can see what exists above them.
        if not item.visible or item.visible() then
            items[#items + 1] = { id = item.id, label = item.label, disabled = not Admin.hasLevel(item.level) }
        end
    end

    local result = QB.nui.openMenu(items, category.label)
    if not result or result.cancelled then return end

    for _, item in ipairs(category.items) do
        if item.id == result.selectedId then
            if Admin.hasLevel(item.level) then item.run() end
            return
        end
    end
end

local function openRoot()
    local items = {}
    for _, category in ipairs(CATEGORIES) do
        if Admin.hasLevel(category.level) then
            items[#items + 1] = { id = category.id, label = category.label }
        end
    end

    local result = QB.nui.openMenu(items, 'Admin Menu')
    if not result or result.cancelled then return end

    for _, category in ipairs(CATEGORIES) do
        if category.id == result.selectedId then
            openCategory(category)
            return
        end
    end
end

RegisterNetEvent('qbadmin:client:openMenu', function()
    openRoot()
end)

-- Keybind entry point. This deliberately does NOT call openRoot() directly: it
-- runs the same server-side /admin the player would type, so the 'mod'
-- permission check in server/commands/player.lua stays the single gate and the
-- server remains the thing that decides the menu may open. Calling openRoot()
-- here would let anyone with the key bound render the menu locally -- harmless
-- in itself (every leaf still runs a permission-checked command) but it would
-- put an admin-looking UI in front of players who have no admin rights at all.
--
-- Registered unconditionally rather than gated on Admin.hasLevel: the level
-- arrives asynchronously from the server (client/core.lua) and can change
-- mid-session, whereas RegisterKeyMapping only takes effect at resource start
-- -- so a level-gated registration would leave a freshly-promoted admin with a
-- dead key until they reconnected.
RegisterCommand(Config.keybind.command, function()
    ExecuteCommand('admin')
end, false)

RegisterKeyMapping(Config.keybind.command, Config.keybind.label, 'keyboard', Config.keybind.defaultKey)
