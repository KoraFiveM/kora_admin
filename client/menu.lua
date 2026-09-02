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
    local mySrc = QB.cache.serverId()
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

local function openClothing(mode, service)
    if GetResourceState('qbclothing') ~= 'started' then
        QB.notify.send({ type = 'error', message = 'qbclothing is not running' })
        return
    end
    if mode == 'shop' then
        TriggerEvent('qbclothing:client:openNearestShop', service)
    elseif mode == 'admin' then
        TriggerEvent('qbclothing:client:openAdminSession')
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

---Grades for one job/gang, in ascending order -- value is the 1-based grade
---number CoreInternal.player.buildJob/buildGang index `def.grades` with
---directly (see qbcore/modules/player/shared.lua), not a 0-based offset.
---@param kind 'jobs'|'gangs'
---@param name string
---@return table[]
local function gradeOptions(kind, name)
    local record = QB.shared.get(kind, name)
    local out = {}
    if record and record.grades then
        for i, grade in ipairs(record.grades) do
            out[#out + 1] = { value = tostring(i), label = ('%d - %s'):format(i, grade.name) }
        end
    end
    return out
end

---Set a player's job or gang. Grade can't be a single reactive dropdown
---alongside the job/gang picker (openInputDialog fields aren't reactive to
---each other within one call -- see resolveFields above), so this asks in
---two steps: pick the job/gang, then pick its grade from that job/gang's own
---ordered list.
---@param commandName string
---@param kind 'jobs'|'gangs'
---@param optionsFn fun():table[]
---@param label string
---@return fun()
local function setJobOrGang(commandName, kind, optionsFn, label)
    return function()
        local target = pickPlayer('Set ' .. label)
        if not target then return end

        local nameResult = QB.nui.openInputDialog({
            { id = 'name', label = label, type = 'select', options = optionsFn(), required = true },
        }, 'Set ' .. label)
        if not nameResult or nameResult.cancelled then return end
        local name = nameResult.values.name

        local grades = gradeOptions(kind, name)
        local gradeResult = QB.nui.openInputDialog({
            { id = 'grade', label = 'Grade', type = 'select', options = grades, default = grades[1] and grades[1].value, required = true },
        }, 'Set ' .. label .. ' Grade')
        if not gradeResult or gradeResult.cancelled then return end

        runCommand(commandName, target, name, gradeResult.values.grade)
    end
end

local function vehicleOptions()
    local out = {}
    for _, veh in ipairs(QB.shared.all('vehicles')) do out[#out + 1] = { value = veh.model, label = ('%s (%s)'):format(veh.name, veh.model) } end
    table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
    return out
end

-- Keep free-text spawning separate from the quick-pick catalogue. A combobox
-- technically accepts typed text too, but putting this in an ordinary text
-- field makes the "any valid GTA/addon spawn code" path obvious and avoids a
-- long suggestion list obscuring the input. The server remains authoritative:
-- server/commands/vehicle.lua checks the supplied model with GTA natives.
local function vehicleModelField()
    return {
        id = 'model',
        label = 'Spawn code',
        type = 'text',
        placeholder = 'e.g. outlaw',
        required = true,
        pattern = '^[A-Za-z0-9_]+$',
    }
end

local function vehicleCatalogueField()
    return {
        id = 'model',
        label = 'Vehicle',
        type = 'combobox',
        placeholder = 'Search the common vehicle catalogue...',
        options = vehicleOptions(),
        required = true,
        pattern = '^[A-Za-z0-9_]+$',
    }
end

local function entityModelField()
    return {
        id = 'model',
        label = 'Ped or prop spawn code',
        type = 'text',
        placeholder = 'e.g. a_m_m_skater_01 or prop_barrel_02a',
        required = true,
        pattern = '^[A-Za-z0-9_]+$',
    }
end

local function placementModelField()
    return {
        id = 'model',
        label = 'Model name or numeric hash',
        type = 'text',
        placeholder = 'e.g. prop_barrel_02a, blista, or a model hash',
        required = true,
        pattern = '^-?[A-Za-z0-9_]+$',
    }
end

local function zoneTypeField()
    return {
        id = 'type',
        label = 'Zone shape',
        type = 'select',
        default = 'box',
        required = true,
        options = {
            { value = 'box', label = 'Box' },
            { value = 'sphere', label = 'Sphere' },
            { value = 'poly', label = 'Polygon' },
        },
    }
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

-- label/level/run -- label and disabled may be functions evaluated whenever
-- the menu opens. `level` is this item's OWN gate (and may exceed the
-- category's floor). Filtering here is cosmetic only: every command re-checks
-- server-side regardless of what this menu shows.
local CATEGORIES = {
    {
        id = 'self', label = 'Self / Utility', description = 'Your character and quick tools', icon = 'User', level = 'mod',
        items = {
            { id = 'aduty', label = 'Toggle Admin Duty', level = 'mod', run = withFields('aduty') },
            { id = 'coords', label = 'Copy Coordinates', level = 'mod', run = withFields('coords') },
            { id = 'health', label = 'Set Health', level = 'mod',
                run = withFields('health', { { id = 'value', label = 'Health (0-100%, blank = full)', type = 'number', min = 0, max = 100 } }, 'Set Health') },
            -- Runs /selfrevive, not /revive -- see server/commands/self.lua
            -- for why a distinct command name matters here.
            { id = 'selfrevive', label = 'Revive Me', level = 'mod', run = withFields('selfrevive') },
            { id = 'armor', label = 'Set Armor', level = 'mod',
                run = withFields('armor', { { id = 'value', label = 'Armor (blank = full)', type = 'number', min = 0, max = 100 } }, 'Set Armor') },
            { id = 'permission', label = 'My Permission Level', level = 'mod', run = withFields('permission') },
            { id = 'wardrobe', label = 'Open Wardrobe', level = 'mod', run = function() openClothing('wardrobe') end },
            { id = 'clothingshop', label = 'Open Clothing Shop (nearby)', level = 'mod', run = function() openClothing('shop', 'clothing') end },
            { id = 'barbershop', label = 'Open Barber Shop (nearby)', level = 'mod', run = function() openClothing('shop', 'barber') end },
            { id = 'tattooshop', label = 'Open Tattoo Shop (nearby)', level = 'mod', run = function() openClothing('shop', 'tattoo') end },
            { id = 'stylingall', label = 'Open Full Styling (Clothing + Barber + Tattoo)', level = 'admin', run = function() openClothing('admin') end },
        },
    },
    {
        id = 'player', label = 'Players', description = 'Inspect and manage online players', icon = 'Users', level = 'mod',
        items = {
            { id = 'players', label = 'List Players', level = 'mod', run = showPlayers },
            { id = 'checkplayer', label = 'Check Player', level = 'mod', run = withPlayer('checkplayer') },
            { id = 'sethunger', label = 'Set Hunger', level = 'admin',
                run = withPlayer('sethunger', { { id = 'value', label = 'Hunger', type = 'number', min = 0, max = 100, required = true } }, 'Set Hunger') },
            { id = 'setthirst', label = 'Set Thirst', level = 'admin',
                run = withPlayer('setthirst', { { id = 'value', label = 'Thirst', type = 'number', min = 0, max = 100, required = true } }, 'Set Thirst') },
        },
    },
    {
        id = 'moderation', label = 'Moderation', description = 'Warnings, restrictions, and recovery', icon = 'ShieldAlert', level = 'mod',
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
        id = 'teleport', label = 'Teleport / Spectate', description = 'Move around the map or observe players', icon = 'MapPin', level = 'mod',
        items = {
            { id = 'goto', label = 'Goto Player', level = 'mod', run = withPlayer('goto') },
            { id = 'bring', label = 'Bring Player', level = 'mod', run = withPlayer('bring') },
            { id = 'tpm', label = 'Teleport to Waypoint', level = 'mod', run = withFields('tpm') },
            { id = 'tpcoords', label = 'Teleport to Coords', level = 'mod',
                run = withFields('tpcoords', {
                    { id = 'coordinates', label = 'Coordinates', type = 'text', placeholder = 'vec4(123.4, 456.7, 78.9, 90.0)', required = true },
                }, 'Teleport to Coords') },
            { id = 'tpback', label = 'Teleport Back', level = 'mod', run = withFields('tpback') },
            { id = 'spectate', label = 'Spectate Player', level = 'mod', run = withPlayer('spectate') },
            { id = 'spectateStop', label = 'Stop Spectating', level = 'mod', run = withFields('spectate') },
            { id = 'noclip', label = 'Toggle Noclip', level = 'admin', run = withFields('noclip') },
        },
    },
    {
        id = 'economy', label = 'Economy & Inventory', description = 'Money and item administration', icon = 'Wallet', level = 'admin',
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
        id = 'jobgang', label = 'Jobs & Gangs', description = 'Assignments and duty status', icon = 'Briefcase', level = 'mod',
        items = {
            { id = 'setjob', label = 'Set Job', level = 'admin', run = setJobOrGang('setjob', 'jobs', jobOptions, 'Job') },
            { id = 'setgang', label = 'Set Gang', level = 'admin', run = setJobOrGang('setgang', 'gangs', gangOptions, 'Gang') },
            { id = 'setduty', label = 'Toggle Duty', level = 'mod', run = withPlayer('setduty') },
        },
    },
    {
        id = 'vehicle', label = 'Vehicles', description = 'Spawn, repair, and remove vehicles', icon = 'Car', level = 'mod',
        items = {
            { id = 'car', label = 'Spawn by Model (self)', level = 'admin',
                run = withFields('car', function() return { vehicleModelField() } end, 'Spawn vehicle by model') },
            { id = 'car_catalogue', label = 'Spawn from Catalogue (self)', level = 'admin',
                run = withFields('car', function() return { vehicleCatalogueField() } end, 'Spawn vehicle from catalogue') },
            { id = 'veh', label = 'Spawn by Model for Player', level = 'admin',
                run = withPlayer('veh', function() return { vehicleModelField() } end, 'Spawn vehicle for player') },
            { id = 'veh_catalogue', label = 'Spawn from Catalogue for Player', level = 'admin',
                run = withPlayer('veh', function() return { vehicleCatalogueField() } end, 'Spawn vehicle for player') },
            { id = 'dv', label = 'Delete My Vehicle', level = 'admin', visible = function() return QB.cache.vehicle() ~= false end,
                run = withConfirm('Delete the vehicle you are in?', withFields('dv')) },
            { id = 'fix', label = 'Repair My Vehicle', level = 'mod', run = withFields('fix') },
        },
    },
    {
        id = 'entities', label = 'Entities', description = 'Spawn and remove peds or props', icon = 'Box', level = 'admin',
        items = {
            { id = 'entity', label = 'Spawn Ped / Prop (self)', level = 'admin',
                run = withFields('entity', function() return { entityModelField() } end, 'Spawn ped or prop') },
            { id = 'entityfor', label = 'Spawn Ped / Prop for Player', level = 'admin',
                run = withPlayer('entityfor', function() return { entityModelField() } end, 'Spawn ped or prop for player') },
            { id = 'deleteLastEntity', label = 'Delete My Last Spawned Entity', level = 'admin',
                run = withConfirm('Delete your last admin-spawned entity?', withFields('deleteentity')) },
        },
    },
    {
        id = 'developer', label = 'Developer', description = 'Development mode and creation tools', icon = 'Wrench', level = Config.developer.menuLevel,
        items = {
            {
                id = 'devmode_self',
                label = function() return Admin.isDevMode() and 'Disable My Dev Mode' or 'Enable My Dev Mode' end,
                description = 'God mode, paused passive needs, and faster walking',
                level = Config.developer.menuLevel,
                run = function() runCommand('devmode', 'me', tostring(not Admin.isDevMode())) end,
            },
            {
                id = 'devmode_player',
                label = 'Set Player Dev Mode',
                description = 'Enable or disable qbcore development mode for a player',
                level = 'admin',
                run = withPlayer('devmode', {
                    { id = 'state', label = 'State', type = 'select', default = 'true', required = true,
                        options = { { value = 'true', label = 'Enable' }, { value = 'false', label = 'Disable' } } },
                }, 'Set Player Dev Mode'),
            },
            {
                id = 'devplacement',
                label = 'Place Entity / Model',
                description = 'Position any valid ped, vehicle, or object and copy its transform',
                level = Config.developer.menuLevel,
                disabled = function() return Config.developer.requireDevMode and not Admin.isDevMode() end,
                run = withFields('devplacement', function() return { placementModelField() } end, 'Entity Placement Creator'),
            },
            {
                id = 'devzone',
                label = 'Create Zone',
                description = 'Open qblib’s box, sphere, or polygon creator',
                level = Config.developer.menuLevel,
                disabled = function() return Config.developer.requireDevMode and not Admin.isDevMode() end,
                run = withFields('devzone', function() return { zoneTypeField() } end, 'Zone Creator'),
            },
        },
    },
    {
        id = 'world', label = 'World & Server', description = 'Announcements, weather, time, and status', icon = 'Settings', level = 'mod',
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
        id = 'audit', label = 'Audit Log', description = 'Review administration activity', icon = 'List', level = 'admin',
        items = {
            { id = 'adminlog', label = 'View Recent Log', level = 'admin', run = showAuditLog },
            { id = 'adminlogfilter', label = 'Filter Log', level = 'admin', run = filterAuditLog },
        },
    },
    {
        id = 'privileged', label = 'Permissions & Resources', description = 'High-privilege server controls', icon = 'Key', level = 'god',
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
}

local function openRoot()
    local items = {}
    for _, category in ipairs(CATEGORIES) do
        if Admin.hasLevel(category.level) then
            local categoryItems = {}
            for _, item in ipairs(category.items) do
                -- `visible`, unlike the level check below, hides the item
                -- entirely rather than greying it out: it is for state that
                -- makes an item nonsensical to offer, not permission.
                if not item.visible or item.visible() then
                    local label = type(item.label) == 'function' and item.label() or item.label
                    local stateDisabled = type(item.disabled) == 'function' and item.disabled() or item.disabled == true
                    categoryItems[#categoryItems + 1] = {
                        id = item.id,
                        label = label,
                        description = item.description,
                        disabled = not Admin.hasLevel(item.level) or stateDisabled,
                    }
                end
            end

            -- Keep categories in one NUI menu tree. This gives every category
            -- screen the built-in Back action (and Escape-to-back behaviour)
            -- instead of opening an unrelated second menu request.
            items[#items + 1] = {
                id = category.id,
                label = category.label,
                description = category.description,
                icon = category.icon,
                submenu = { title = category.label, items = categoryItems },
            }
        end
    end

    local result = QB.nui.openMenu(items, 'Admin Menu', {
        position = { horizontal = 'right', vertical = 'center', offsetX = 48 },
        maxWidth = 400,
        maxHeight = 680,
    })
    if not result or result.cancelled then return end

    local categoryId, itemId = result.path and result.path[1], result.selectedId
    for _, category in ipairs(CATEGORIES) do
        if category.id == categoryId then
            for _, item in ipairs(category.items) do
                local stateDisabled = type(item.disabled) == 'function' and item.disabled() or item.disabled == true
                if item.id == itemId and Admin.hasLevel(item.level) and not stateDisabled
                    and (not item.visible or item.visible()) then
                    item.run()
                end
            end
            return
        end
    end
end

RegisterNetEvent('qbadmin:client:openMenu', function(level)
    if type(level) == 'string' then Admin.level = level end
    openRoot()
end)
