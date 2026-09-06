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

-- App actions are deliberately shell-only: fields and confirmations render
-- inline, and no action falls back to a standalone qb-menu/qb-input dialog.
local function appAction(run, fields, confirmMessage, shouldClose)
    return { run = run, fields = fields, confirm = confirmMessage, shouldClose = shouldClose == true }
end

---Collect fields inline (when any) and run the command.
---@param commandName string
---@param fieldsOrFn? table[]|fun():table[]
---@param dialogTitle? string
---@return fun()
local function withFields(commandName, fieldsOrFn, dialogTitle, shouldClose)
    return appAction(function(values)
        local args = { commandName }
        local fields = resolveFields(fieldsOrFn) or {}
        if #fields > 0 then assert(type(values) == 'table', 'This action requires AppShell input values.') end
        for _, field in ipairs(fields) do
            local value = values and values[field.id]
            if value ~= nil and value ~= '' then args[#args + 1] = tostring(value) end
        end
        runCommand(table.unpack(args))
    end, function() return resolveFields(fieldsOrFn) or {} end, nil, shouldClose)
end

local function withConfirm(message, fn)
    return appAction(function(values)
        assert(type(values) == 'table', 'This action requires AppShell confirmation.')
        return fn.run(values)
    end, fn.fields, message, fn.shouldClose)
end

---Build an action for the player selected from the online-player table.  The
---target is intentionally closed over rather than rendered again: selecting a
---player should lead straight to their tools, not another player picker.
local function forSelectedPlayer(target, commandName, extraFields, confirmMessage, shouldClose)
    return appAction(function(values)
        local args = { commandName, target }
        for _, field in ipairs(resolveFields(extraFields) or {}) do
            local value = values and values[field.id]
            if value ~= nil and value ~= '' then args[#args + 1] = tostring(value) end
        end
        runCommand(table.unpack(args))
    end, function()
        return resolveFields(extraFields) or {}
    end, confirmMessage, shouldClose)
end

local filterAuditLog = appAction(function(values)
    return values
end, function()
    return {
        { id = 'action', label = 'Action filter (optional)', type = 'text' },
        { id = 'target', label = 'Target filter (optional)', type = 'text' },
        { id = 'page', label = 'Page', type = 'number', default = 1, min = 1 },
    }
end)

local function reportTypeOptions(includeAll)
    local options = {}
    if includeAll then options[#options + 1] = { value = 'all', label = 'All types' } end
    for _, definition in ipairs(Config.reports.types) do
        options[#options + 1] = { value = definition.id, label = definition.label }
    end
    return options
end

local filterReports = appAction(function(values)
    return values
end, function()
    return {
        { id = 'status', label = 'Status', type = 'select', default = 'open', required = true, options = {
            { value = 'all', label = 'All statuses' },
            { value = 'open', label = 'Open' },
            { value = 'claimed', label = 'Claimed' },
            { value = 'resolved', label = 'Resolved' },
            { value = 'dismissed', label = 'Dismissed' },
        } },
        { id = 'type', label = 'Type', type = 'select', default = 'all', required = true, options = reportTypeOptions(true) },
        { id = 'reporter', label = 'Reporter name or identifier (optional)', type = 'text' },
        { id = 'page', label = 'Page', type = 'number', default = 1, min = 1 },
    }
end)

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
    -- qb-weathersync owns the accepted weather list.  qbadmin intentionally
    -- has no manifest dependency on it (the sync resource starts after this
    -- one so it can own /weather), therefore retain the local list only as a
    -- graceful fallback while that resource is stopped/restarting.
    local ok, weatherTypes = pcall(function() return exports['qb-weathersync']:getWeatherTypes() end)
    for _, w in ipairs(ok and weatherTypes or Config.world.weatherTypes) do
        out[#out + 1] = { value = w, label = w }
    end
    return out
end

---Time selector: one button per Config.world.timePresets entry, plus Custom.
---The hour/minute inputs are a second step rather than conditional fields in
---one dialog because openInputDialog fields aren't reactive to each other
---within a call -- which is
---also why a preset click never renders, or has to validate, a number at all.
---Both paths end in `/time`, so the server re-checks either one.
-- Keep the preset and exact-clock paths in the AppShell. The optional exact
-- fields are ignored unless Custom is selected, so choosing a preset does not
-- require a second menu just to avoid rendering those controls.
local setTime = appAction(function(values)
    assert(type(values) == 'table', 'This action requires AppShell input values.')
    if values.preset and values.preset ~= 'custom' then
        return runCommand('time', tostring(values.preset))
    end
    local args = { 'time', tostring(values.hour) }
    if values.minute ~= nil and values.minute ~= '' then args[#args + 1] = tostring(values.minute) end
    runCommand(table.unpack(args))
end, function()
    local hour = GetClockHours and GetClockHours() or 0
    local minute = GetClockMinutes and GetClockMinutes() or 0
    local options = {}
    for _, preset in ipairs(Config.world.timePresets) do
        options[#options + 1] = { value = preset.id, label = ('%s (%02d:%02d)'):format(preset.label, preset.hour, preset.minute or 0) }
    end
    options[#options + 1] = { value = 'custom', label = 'Custom exact time' }
    return {
        { id = 'preset', label = 'Time preset', type = 'select', options = options, default = 'custom', required = true },
        { id = 'hour', label = 'Hour for Custom (0-23)', type = 'number', default = hour, min = 0, max = 23, required = true },
        { id = 'minute', label = 'Minute for Custom', type = 'number', default = minute, min = 0, max = 59 },
    }
end)

local function levelOptions()
    local options = {}
    for role, definition in pairs(Config.permissions.roles) do
        if role ~= 'user' and definition.grantable ~= false then
            options[#options + 1] = { value = role, label = definition.label or role, rank = definition.rank }
        end
    end
    table.sort(options, function(a, b) return a.rank == b.rank and a.value < b.value or a.rank < b.rank end)
    for _, option in ipairs(options) do option.rank = nil end
    return options
end

local function temporaryLevelOptions()
    local maxRole = Config.permissions.roles[Config.permissions.temporaryGrant.maxRole]
    if not maxRole then return {} end

    local options = {}
    for role, definition in pairs(Config.permissions.roles) do
        if role ~= 'user' and definition.grantable ~= false and definition.rank <= maxRole.rank then
            options[#options + 1] = { value = role, label = definition.label or role, rank = definition.rank }
        end
    end
    table.sort(options, function(a, b) return a.rank == b.rank and a.value < b.value or a.rank < b.rank end)
    for _, option in ipairs(options) do option.rank = nil end
    return options
end

local function medalItems()
    local items = {}
    for index, event in ipairs(Config.medal.events or {}) do
        local configuredEvent = event
        items[#items + 1] = {
            id = 'clip_' .. tostring(event.id or index),
            label = ('Save %s (%ss)'):format(event.name or 'Medal Clip', tostring(event.duration or '?')),
            description = 'Saves this admin’s local replay buffer; requires Medal to be configured and running.',
            icon = 'radio',
            level = Config.medal.menuLevel,
            disabled = function()
                return type(Admin.isMedalConfigured) ~= 'function' or not Admin.isMedalConfigured()
            end,
            run = appAction(function() Admin.invokeMedalEvent(configuredEvent) end),
        }
    end
    return items
end

-- label/level/run -- label and disabled may be functions evaluated whenever
-- the menu opens. `level` is this item's OWN gate (and may exceed the
-- category's floor). Filtering here is cosmetic only: every command re-checks
-- server-side regardless of what this menu shows.
local CATEGORIES = {
    {
        id = 'reports', label = 'Reports', level = Config.reports.staffLevel,
        items = {
            { id = 'open', label = 'View Open Reports', level = Config.reports.staffLevel, run = appAction(function() end) },
            { id = 'all', label = 'View All Reports', level = Config.reports.staffLevel, run = appAction(function() end) },
            { id = 'filter', label = 'Filter Reports', level = Config.reports.staffLevel, run = filterReports },
        },
    },
    {
        id = 'player', label = 'Players', level = 'support',
        items = {
            { id = 'players', label = 'Browse Online Players', level = 'support', run = appAction(function() end) },
        },
    },
    {
        -- Online moderation lives under Players. These remain because an
        -- offline citizen/license cannot be selected from the player table.
        id = 'moderation', label = 'Offline Bans', level = 'admin',
        items = {
            { id = 'ban', label = 'Ban Offline Player', level = 'admin',
                run = withConfirm('Ban this player? This is persistent.', withFields('ban', {
                    { id = 'target', label = 'Citizen ID or character name', type = 'text', required = true },
                    { id = 'duration', label = 'Duration (30m, 2h, 7d, or perm)', type = 'text', default = 'perm', required = true },
                    { id = 'reason', label = 'Reason', type = 'text', required = true },
                }, 'Ban Player')) },
            { id = 'unban', label = 'Unban', level = 'admin',
                run = withFields('unban', { { id = 'target', label = 'License or ban id', type = 'text', required = true } }, 'Unban') },
        },
    },
    {
        id = 'teleport', label = 'Teleport / Spectate', level = 'mod',
        items = {
            { id = 'tpm', label = 'Teleport to Waypoint', level = 'mod', run = withFields('tpm', nil, nil, true) },
            { id = 'tpcoords', label = 'Teleport to Coords', level = 'mod',
                run = withFields('tpcoords', {
                    { id = 'coordinates', label = 'Coordinates', type = 'text', placeholder = 'vec4(123.4, 456.7, 78.9, 90.0)', required = true },
                }, 'Teleport to Coords', true) },
            { id = 'tpback', label = 'Teleport Back', level = 'mod', run = withFields('tpback', nil, nil, true) },
            { id = 'spectateStop', label = 'Stop Spectating', level = 'mod', run = withFields('spectate', nil, nil, true) },
            { id = 'noclip', label = 'Toggle Noclip', level = 'admin', run = withFields('noclip', nil, nil, true) },
        },
    },
    {
        id = 'vehicle', label = 'Vehicle', level = 'mod',
        items = {
            { id = 'car_catalogue', label = 'Spawn from Catalogue', level = 'admin',
                run = withFields('car', function() return { vehicleCatalogueField() } end, 'Spawn vehicle from catalogue') },
            { id = 'dv', label = 'Delete My Vehicle', level = 'admin', visible = function() return QB.cache.vehicle() ~= false end,
                run = withConfirm('Delete the vehicle you are in?', withFields('dv')) },
            { id = 'fix', label = 'Repair My Vehicle', level = 'mod', run = withFields('fix') },
        },
    },
    {
        id = 'developer', label = 'Developer', level = Config.developer.menuLevel,
        items = {
            {
                id = 'devplacement',
                label = 'Place Entity / Model',
                description = 'Position any valid ped, vehicle, or object and copy its transform',
                level = Config.developer.menuLevel,
                disabled = function() return Config.developer.requireDevMode and not Admin.isDevMode() end,
                run = withFields('devplacement', function() return { placementModelField() } end, 'Entity Placement Creator', true),
            },
            {
                id = 'devzone',
                label = 'Create Zone',
                description = 'Open qblib’s box, sphere, or polygon creator',
                level = Config.developer.menuLevel,
                disabled = function() return Config.developer.requireDevMode and not Admin.isDevMode() end,
                run = withFields('devzone', function() return { zoneTypeField() } end, 'Zone Creator', true),
            },
        },
    },
    {
        id = 'world', label = 'World / Server', level = 'mod',
        items = {
            { id = 'announce', label = 'Announce', level = 'admin',
                run = withFields('announce', { { id = 'message', label = 'Message', type = 'textarea', required = true } }, 'Announce') },
            { id = 'weather', label = 'Set Weather', level = 'admin',
                run = withFields('weather', function() return { { id = 'type', label = 'Weather', type = 'select', options = weatherOptions(), required = true } } end, 'Set Weather') },
            { id = 'dynamicweather', label = 'Dynamic Weather', level = 'admin',
                description = 'Choose whether weather changes automatically',
                run = withFields('freezeweather', function()
                    return { { id = 'enabled', label = 'Automatic changes', type = 'select', required = true,
                        options = { { value = 'true', label = 'Enabled' }, { value = 'false', label = 'Disabled' } } } }
                end, 'Dynamic Weather') },
            { id = 'time', label = 'Set Time', level = 'admin', run = setTime },
            { id = 'serverinfo', label = 'Server Info', level = 'mod', run = withFields('serverinfo') },
            { id = 'restartresource', label = 'Restart Resource', level = 'god',
                run = withConfirm('Restart this resource?', withFields('restartresource', { { id = 'name', label = 'Resource name', type = 'text', required = true } }, 'Restart Resource')) },
        },
    },
    {
        id = 'medal', label = 'Medal Clips', level = Config.medal.menuLevel,
        description = 'Capture a configured highlight on your local Medal recorder.',
        items = medalItems(),
    },
    {
        id = 'audit', label = 'Audit Log', level = 'admin',
        items = {
            { id = 'adminlog', label = 'View Recent Log', level = 'admin', run = appAction(function() end) },
            { id = 'adminlogfilter', label = 'Filter Log', level = 'admin', run = filterAuditLog },
        },
    },
    {
        id = 'self', label = 'Self / Utility', level = 'mod',
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
            { id = 'deleteLastEntity', label = 'Delete My Last Spawned Entity', level = 'admin',
                run = withConfirm('Delete your last admin-spawned entity?', withFields('deleteentity')) },
            { id = 'wardrobe', label = 'Open Wardrobe', level = 'mod', run = appAction(function() openClothing('wardrobe') end, nil, nil, true) },
            { id = 'clothingshop', label = 'Open Clothing Shop (nearby)', level = 'mod', run = appAction(function() openClothing('shop', 'clothing') end, nil, nil, true) },
            { id = 'barbershop', label = 'Open Barber Shop (nearby)', level = 'mod', run = appAction(function() openClothing('shop', 'barber') end, nil, nil, true) },
            { id = 'tattooshop', label = 'Open Tattoo Shop (nearby)', level = 'mod', run = appAction(function() openClothing('shop', 'tattoo') end, nil, nil, true) },
            { id = 'stylingall', label = 'Open Full Styling (Clothing + Barber + Tattoo)', level = 'admin', run = appAction(function() openClothing('admin') end, nil, nil, true) },
        },
    },
}

local function playerProfileRows(profile)
    local states = { 'Online' }
    if profile.dead then states[#states + 1] = 'Dead / last stand' end
    if profile.cuffed then states[#states + 1] = 'Handcuffed' end
    local rows = {
        { field = 'Server ID', value = tostring(profile.id) },
        { field = 'Name', value = profile.name or 'Unknown' },
        { field = 'Citizen ID', value = profile.citizenid or 'Unknown' },
        { field = 'Job', value = profile.job or 'Unknown' },
        { field = 'Gang', value = profile.gang or 'None' },
        { field = 'Money', value = profile.money or 'None' },
        { field = 'Health / Armor', value = ('%s / %s'):format(profile.health or 0, profile.armor or 0) },
        { field = 'Hunger / Thirst', value = ('%s / %s'):format(profile.hunger or 0, profile.thirst or 0) },
        { field = 'State', value = table.concat(states, ' · ') },
        { field = 'Ping', value = ('%sms'):format(profile.ping or 0) },
    }
    if profile.permission then rows[#rows + 1] = { field = 'Permission', value = profile.permission } end
    if profile.license then rows[#rows + 1] = { field = 'License', value = profile.license } end
    if profile.discord then rows[#rows + 1] = { field = 'Discord', value = profile.discord } end
    return rows
end

local function playerProfileClipboard(profile)
    local lines = { ('Player Profile — #%s %s'):format(profile.id, profile.name or 'Unknown') }
    for _, row in ipairs(playerProfileRows(profile)) do lines[#lines + 1] = ('%s: %s'):format(row.field, row.value) end
    return table.concat(lines, '\n')
end

local function openRoot()
    local navigation = {}
    local selectedPlayerActions = {}
    local selectedReportActions = {}
    for _, category in ipairs(CATEGORIES) do
        if Admin.hasLevel(category.level) then
            local actions = {}
            for _, item in ipairs(category.items) do
                -- `visible`, unlike the level check below, hides the item
                -- entirely rather than greying it out: it is for state that
                -- makes an item nonsensical to offer, not permission.
                if not item.visible or item.visible() then
                    local label = type(item.label) == 'function' and item.label() or item.label
                    local stateDisabled = type(item.disabled) == 'function' and item.disabled() or item.disabled == true
                    actions[#actions + 1] = {
                        id = category.id .. ':' .. item.id,
                        label = label,
                        description = item.description,
                        icon = item.icon,
                        disabled = not Admin.hasLevel(item.level) or stateDisabled,
                        fields = type(item.run) == 'table' and item.run.fields and item.run.fields() or nil,
                        confirm = type(item.run) == 'table' and item.run.confirm or nil,
                    }
                end
            end

            navigation[#navigation + 1] = {
                id = category.id,
                label = category.label,
                content = {
                    title = category.label,
                    description = category.description or 'Choose an administrative action. Permissions are enforced again by the command handler.',
                    blocks = { { type = 'actions', actions = actions } },
                },
            }
        end
    end

    local function showAuditInShell(filters)
        local rows, err = QB.callback.trigger('qbadmin:menuAuditLog', filters)
        if not rows then
            QB.notify.send({ type = 'error', message = err or 'Could not load audit log' })
            return {}
        end
        for _, view in ipairs(navigation) do
            if view.id == 'audit' then
                local blocks = view.content.blocks
                for index = #blocks, 1, -1 do
                    if blocks[index].id == 'audit-log' then table.remove(blocks, index) end
                end
                local tableRows = {}
                for _, row in ipairs(rows) do
                    tableRows[#tableRows + 1] = {
                        action = row.action or 'unknown', actor = row.actor_name or 'unknown',
                        target = row.target_name or '-', created = row.created_at or '-', details = row.details or '',
                    }
                end
                blocks[#blocks + 1] = {
                    id = 'audit-log', type = 'table', title = 'Audit Log',
                    columns = {
                        { key = 'action', label = 'Action' }, { key = 'actor', label = 'Actor' },
                        { key = 'target', label = 'Target' }, { key = 'created', label = 'When' }, { key = 'details', label = 'Details' },
                    },
                    rows = tableRows, empty = 'No matching audit entries',
                }
                return { update = { navigation = navigation } }
            end
        end
        return {}
    end

    local function reportView()
        for _, view in ipairs(navigation) do
            if view.id == 'reports' then return view end
        end
    end

    local function clearReportDetail(blocks)
        for index = #blocks, 1, -1 do
            local id = blocks[index].id
            if id and id:match('^selected%-report') then table.remove(blocks, index) end
        end
    end

    local function showReportsInShell(filters)
        local rows, err = QB.callback.trigger('qbadmin:menuReports', filters or { status = 'open' })
        if not rows then
            QB.notify.send({ type = 'error', message = err or 'Could not load reports' })
            return {}
        end
        local view = reportView()
        if not view then return {} end
        local blocks = view.content.blocks
        clearReportDetail(blocks)
        for index = #blocks, 1, -1 do
            if blocks[index].id == 'report-list' then table.remove(blocks, index) end
        end

        local tableRows = {}
        for _, row in ipairs(rows) do
            tableRows[#tableRows + 1] = {
                id = tostring(row.id), status = row.status, type = row.type,
                reporter = row.reporter_name, assigned = row.claimed_by_name or '-',
                message = row.message, updated = row.updated_at or row.created_at or '-',
            }
        end
        blocks[#blocks + 1] = {
            id = 'report-list', type = 'table', title = 'Player Reports',
            columns = {
                { key = 'id', label = '#' }, { key = 'status', label = 'Status' },
                { key = 'type', label = 'Type' }, { key = 'reporter', label = 'Reporter' },
                { key = 'assigned', label = 'Assigned' }, { key = 'message', label = 'Report' },
                { key = 'updated', label = 'Updated' },
            },
            rows = tableRows, empty = 'No matching reports', action = 'reports:select', idKey = 'id',
        }
        return { update = { navigation = navigation } }
    end

    local function showSelectedReport(id)
        local report, err = QB.callback.trigger('qbadmin:menuReport', id)
        if not report then
            QB.notify.send({ type = 'error', message = err or 'Could not load report' })
            return {}
        end
        local view = reportView()
        if not view then return {} end
        local blocks = view.content.blocks
        clearReportDetail(blocks)
        selectedReportActions = {}

        local function add(id_, label, run, destructive)
            selectedReportActions[id_] = run
            return {
                id = 'reports:selected:' .. id_, label = label,
                fields = run.fields and run.fields() or nil,
                confirm = run.confirm,
                destructive = destructive == true,
            }
        end
        local function action(command, fields, confirmMessage, shouldClose)
            return forSelectedPlayer(tostring(report.id), command, fields, confirmMessage, shouldClose)
        end

        local management = {}
        if report.status == 'open' or report.status == 'claimed' then
            management[#management + 1] = add('claim', report.status == 'claimed' and 'Take Over Report' or 'Claim Report', action('reportclaim'))
            management[#management + 1] = add('reply', 'Reply to Reporter', action('reportreply', {
                { id = 'message', label = 'Reply', type = 'textarea', required = true },
            }))
            management[#management + 1] = add('resolve', 'Resolve Report', action('reportresolve', {
                { id = 'note', label = 'Resolution', type = 'textarea', required = true },
            }, 'Resolve this report?'))
            management[#management + 1] = add('dismiss', 'Dismiss Report', action('reportdismiss', {
                { id = 'note', label = 'Reason', type = 'textarea', required = true },
            }, 'Dismiss this report?'), true)
        else
            management[#management + 1] = add('reopen', 'Reopen Report', action('reportreopen', {
                { id = 'note', label = 'Reason for reopening (optional)', type = 'textarea' },
            }, 'Reopen this report?'))
        end

        local reporterActions = {}
        if report.reporter_source then
            local source = tostring(report.reporter_source)
            local function playerAction(id_, label, command, confirmMessage, shouldClose)
                local run = forSelectedPlayer(source, command, nil, confirmMessage, shouldClose)
                selectedReportActions[id_] = run
                reporterActions[#reporterActions + 1] = {
                    id = 'reports:selected:' .. id_, label = label, confirm = run.confirm,
                }
            end
            playerAction('goto', 'Teleport to Reporter', 'goto', nil, true)
            playerAction('bring', 'Bring Reporter', 'bring')
            playerAction('sendback', 'Send Reporter Back', 'sendback')
            playerAction('spectate', 'Spectate Reporter', 'spectate', nil, true)
        end

        local conversation = {
            { author = report.reporter_name, role = 'player', message = report.message, created = report.created_at or '-' },
        }
        for _, reply in ipairs(report.messages or {}) do
            conversation[#conversation + 1] = {
                author = reply.author_name, role = reply.author_role, message = reply.message, created = reply.created_at or '-',
            }
        end

        blocks[#blocks + 1] = {
            id = 'selected-report-summary', type = 'text', title = ('Report #%s · %s · %s'):format(report.id, report.type, report.status),
            text = ('Reporter: %s%s%s'):format(
                report.reporter_name,
                report.claimed_by_name and (' · Assigned to ' .. report.claimed_by_name) or '',
                report.resolution and (' · Resolution: ' .. report.resolution) or ''),
        }
        blocks[#blocks + 1] = {
            id = 'selected-report-conversation', type = 'table', title = 'Conversation',
            columns = {
                { key = 'author', label = 'From' }, { key = 'role', label = 'Role' },
                { key = 'message', label = 'Message' }, { key = 'created', label = 'When' },
            },
            rows = conversation,
        }
        blocks[#blocks + 1] = { id = 'selected-report-management', type = 'actions', title = 'Report Management', actions = management }
        if #reporterActions > 0 then
            blocks[#blocks + 1] = { id = 'selected-report-player', type = 'actions', title = 'Online Reporter', actions = reporterActions }
        end
        return { update = { navigation = navigation } }
    end

    -- Selecting a row is the player-first workflow.  It exposes every
    -- meaningful online-player command in one place, with the selected server
    -- id fixed into the action so staff never have to choose the same person
    -- twice.  The table includes the caller too, so self actions work through
    -- exactly the same screen.
    local function showSelectedPlayer(player)
        local profile, profileErr = QB.callback.trigger('qbadmin:menuPlayerProfile', player.id)
        if not profile then
            QB.notify.send({ type = 'error', message = profileErr or 'That player is no longer online' })
            return {}
        end

        local playerView
        for _, view in ipairs(navigation) do
            if view.id == 'player' then playerView = view break end
        end
        if not playerView then return {} end

        local blocks = playerView.content.blocks
        for index = #blocks, 1, -1 do
            local blockId = blocks[index].id
            if blockId == 'online-players' or (blockId and blockId:match('^selected%-player%-')) then
                table.remove(blocks, index)
            end
        end

        selectedPlayerActions = {}
        local target = tostring(profile.id)
        local groups = {
            { id = 'profile', title = 'Profile', actions = {} },
            { id = 'history', title = 'History', actions = {} },
            { id = 'movement', title = 'Movement & Spectating', actions = {} },
            { id = 'wellbeing', title = 'Health & State', actions = {} },
            { id = 'moderation', title = 'Moderation', actions = {} },
            { id = 'appearance', title = 'Appearance', actions = {} },
            { id = 'economy', title = 'Economy & Inventory', actions = {} },
            { id = 'roles', title = 'Job, Gang & Duty', actions = {} },
            { id = 'spawning', title = 'Spawning', actions = {} },
            { id = 'development', title = 'Development', actions = {} },
            { id = 'access', title = 'Access & Permissions', actions = {} },
        }
        local groupById = {}
        for _, group in ipairs(groups) do groupById[group.id] = group end

        local function add(groupId, id, label, level, run)
            if not Admin.hasLevel(level) then return end
            selectedPlayerActions[id] = { level = level, run = run }
            local actions = groupById[groupId].actions
            actions[#actions + 1] = {
                id = 'player:target:' .. id,
                label = label,
                fields = run.fields and run.fields() or nil,
                confirm = run.confirm,
            }
        end
        local function selected(command, fields, confirmMessage, shouldClose)
            return forSelectedPlayer(target, command, fields, confirmMessage, shouldClose)
        end

        add('profile', 'copyinfo', 'Copy Player Info', 'support', appAction(function()
            QB.nui.copyToClipboard(playerProfileClipboard(profile))
            QB.notify.send({ type = 'success', message = 'Player information copied' })
        end))
        add('history', 'warnings', 'Warning History', 'mod', selected('warnings'))

        add('movement', 'goto', 'Teleport to Player', 'mod', selected('goto', nil, nil, true))
        add('movement', 'bring', 'Bring to Me', 'mod', selected('bring'))
        add('movement', 'sendback', 'Send Back', 'mod', selected('sendback'))
        add('movement', 'spectate', 'Spectate', 'mod', selected('spectate', nil, nil, true))

        add('wellbeing', 'heal', 'Heal', 'mod', selected('heal'))
        add('wellbeing', 'revive', 'Revive', 'mod', selected('revive'))
        add('wellbeing', 'sethunger', 'Set Hunger', 'admin', selected('sethunger', {
            { id = 'value', label = 'Hunger', type = 'number', min = 0, max = 100, required = true },
        }))
        add('wellbeing', 'setthirst', 'Set Thirst', 'admin', selected('setthirst', {
            { id = 'value', label = 'Thirst', type = 'number', min = 0, max = 100, required = true },
        }))
        add('wellbeing', 'freeze', 'Freeze / Unfreeze', 'mod', selected('freeze', {
            { id = 'state', label = 'State', type = 'select', default = 'true', options = {
                { value = 'true', label = 'Freeze' }, { value = 'false', label = 'Unfreeze' },
            } },
        }))
        add('wellbeing', 'god', 'Toggle God Mode', 'mod', selected('god'))
        add('wellbeing', 'invisible', 'Toggle Invisible', 'mod', selected('invisible'))

        add('moderation', 'warn', 'Warn', 'mod', selected('warn', {
            { id = 'reason', label = 'Reason', type = 'text', required = true },
        }))
        add('moderation', 'kick', 'Kick', 'mod', selected('kick', {
            { id = 'reason', label = 'Reason', type = 'text' },
        }, 'Kick this player?'))
        add('moderation', 'ban', 'Ban', 'admin', selected('ban', {
            { id = 'duration', label = 'Duration (30m, 2h, 7d, or perm)', type = 'text', default = 'perm', required = true },
            { id = 'reason', label = 'Reason', type = 'text', required = true },
        }, 'Ban this player? This is persistent.'))
        add('moderation', 'kill', 'Kill', 'mod', selected('kill', nil, 'Kill this player?'))

        add('appearance', 'clothingmenu', 'Open Clothing Menu', 'admin', selected('clothingmenu', nil, nil, true))
        add('appearance', 'barbermenu', 'Open Barber / Hairdresser', 'admin', selected('barbermenu', nil, nil, true))
        add('appearance', 'tattoomenu', 'Open Tattoo Menu', 'admin', selected('tattoomenu', nil, nil, true))

        add('economy', 'givemoney', 'Give Money', 'admin', selected('givemoney', {
            { id = 'account', label = 'Account (cash/bank/crypto)', type = 'text', required = true },
            { id = 'amount', label = 'Amount', type = 'number', min = 1, required = true },
            { id = 'reason', label = 'Reason', type = 'text' },
        }))
        add('economy', 'removemoney', 'Remove Money', 'admin', selected('removemoney', {
            { id = 'account', label = 'Account (cash/bank/crypto)', type = 'text', required = true },
            { id = 'amount', label = 'Amount', type = 'number', min = 1, required = true },
            { id = 'reason', label = 'Reason', type = 'text' },
        }))
        add('economy', 'setmoney', 'Set Money', 'admin', selected('setmoney', {
            { id = 'account', label = 'Account (cash/bank/crypto)', type = 'text', required = true },
            { id = 'amount', label = 'Amount', type = 'number', min = 0, required = true },
            { id = 'reason', label = 'Reason', type = 'text' },
        }))
        add('economy', 'giveitem', 'Give Item', 'admin', selected('giveitem', function() return {
            { id = 'item', label = 'Item', type = 'select', options = itemOptions(), required = true },
            { id = 'amount', label = 'Amount', type = 'number', default = 1, min = 1 },
        } end))
        add('economy', 'removeitem', 'Remove Item', 'admin', selected('removeitem', function() return {
            { id = 'item', label = 'Item', type = 'select', options = itemOptions(), required = true },
            { id = 'amount', label = 'Amount', type = 'number', default = 1, min = 1 },
        } end))
        add('economy', 'clearinventory', 'Clear Inventory', 'admin', selected('clearinventory', nil, "Clear this player's entire inventory?"))

        add('roles', 'setjob', 'Set Job', 'admin', selected('setjob', function()
            local roles, gradesByJob = jobOptions(), {}
            for _, option in ipairs(roles) do gradesByJob[option.value] = gradeOptions('jobs', option.value) end
            local first = roles[1] and roles[1].value
            return {
                { id = 'name', label = 'Job', type = 'select', options = roles, default = first, required = true },
                { id = 'grade', label = 'Grade', type = 'select', dependsOn = 'name', optionsByValue = gradesByJob, required = true },
            }
        end))
        add('roles', 'setgang', 'Set Gang', 'admin', selected('setgang', function()
            local roles, gradesByGang = gangOptions(), {}
            for _, option in ipairs(roles) do gradesByGang[option.value] = gradeOptions('gangs', option.value) end
            local first = roles[1] and roles[1].value
            return {
                { id = 'name', label = 'Gang', type = 'select', options = roles, default = first, required = true },
                { id = 'grade', label = 'Grade', type = 'select', dependsOn = 'name', optionsByValue = gradesByGang, required = true },
            }
        end))
        add('roles', 'setduty', 'Toggle Duty', 'mod', selected('setduty'))

        add('spawning', 'veh', 'Spawn Vehicle', 'admin', selected('veh', function() return { vehicleModelField() } end))
        add('spawning', 'veh_catalogue', 'Spawn Vehicle from Catalogue', 'admin', selected('veh', function()
            return { vehicleCatalogueField() }
        end))
        add('spawning', 'entityfor', 'Spawn Ped / Prop', 'admin', selected('entityfor', function() return { entityModelField() } end))

        add('development', 'devmode', 'Set Development Mode', 'admin', selected('devmode', {
            { id = 'state', label = 'State', type = 'select', default = 'true', options = {
                { value = 'true', label = 'Enable' }, { value = 'false', label = 'Disable' },
            } },
        }))

        add('access', 'granttempaccess', 'Grant Temporary Access', Config.permissions.temporaryGrant.managerRole,
            selected('granttempaccess', {
                { id = 'role', label = 'Role', type = 'select', options = temporaryLevelOptions(), required = true },
                { id = 'minutes', label = 'Duration (minutes)', type = 'number', required = true,
                    min = Config.permissions.temporaryGrant.minMinutes,
                    max = Config.permissions.temporaryGrant.maxMinutes,
                    default = Config.permissions.temporaryGrant.defaultMinutes },
            }, 'Grant temporary admin access?'))
        add('access', 'revoketempaccess', 'Revoke Temporary Access', Config.permissions.temporaryGrant.managerRole,
            selected('revoketempaccess', {
                { id = 'role', label = 'Role', type = 'select', options = temporaryLevelOptions(), required = true },
            }))
        add('access', 'setpermission', 'Grant Permission', 'god', selected('setpermission', {
            { id = 'level', label = 'Level', type = 'select', options = levelOptions(), required = true },
        }, 'Grant this level? This can create another privileged account.'))
        add('access', 'revokepermission', 'Revoke Permission', 'god', selected('revokepermission', {
            { id = 'level', label = 'Level', type = 'select', options = levelOptions(), required = true },
        }))

        table.insert(blocks, 1, {
            id = 'selected-player-header', type = 'text', title = ('Player Profile · #%s %s'):format(target, profile.name),
            text = ('%s · %s · %dms'):format(profile.job or 'Unknown job', profile.citizenid or 'Unknown citizen', profile.ping or 0),
        })
        table.insert(blocks, 2, {
            id = 'selected-player-details', type = 'table', title = 'Player Information',
            columns = { { key = 'field', label = 'Field' }, { key = 'value', label = 'Value' } },
            rows = playerProfileRows(profile),
        })
        local insertAt = 3
        for _, group in ipairs(groups) do
            if #group.actions > 0 then
                table.insert(blocks, insertAt, {
                    id = 'selected-player-actions-' .. group.id,
                    type = 'actions', title = group.title, actions = group.actions,
                })
                insertAt = insertAt + 1
            end
        end
        return { update = { navigation = navigation } }
    end

    QB.nui.registerApp({
        id = 'qbadmin:menu',
        title = 'Administration',
        description = 'Server administration',
        icon = 'shield-check',
        defaultView = navigation[1] and navigation[1].id,
        navigation = navigation,
        footer = 'Every action is checked and audited by the server.',
        onAction = function(actionId, context)
            local categoryId, itemId = actionId:match('^([^:]+):(.+)$')
            if categoryId == 'reports' and itemId == 'select' and context and context.itemId then
                return showSelectedReport(context.itemId)
            end
            if categoryId == 'reports' and itemId:match('^selected:') then
                local selectedAction = selectedReportActions[itemId:sub(#'selected:' + 1)]
                if not selectedAction then error('That report action is no longer available.') end
                if selectedAction.shouldClose and QB.nui.closeApp then QB.nui.closeApp('qbadmin:menu') end
                selectedAction.run(context and context.value)
                return {}
            end
            if categoryId == 'reports' and itemId == 'open' then
                return showReportsInShell({ status = 'open' })
            end
            if categoryId == 'reports' and itemId == 'all' then
                return showReportsInShell({ status = 'all' })
            end
            if categoryId == 'reports' and itemId == 'filter' then
                return showReportsInShell(context and context.value or {})
            end
            if categoryId == 'player' and itemId == 'select' and context and context.itemId then
                local selected
                for _, view in ipairs(navigation) do
                    if view.id == 'player' then
                        for _, block in ipairs(view.content.blocks) do
                            if block.id == 'online-players' then
                                for _, row in ipairs(block.rows) do
                                    if tostring(row.id) == tostring(context.itemId) then selected = row break end
                                end
                            end
                        end
                    end
                end
                if selected then return showSelectedPlayer(selected) end
                QB.notify.send({ type = 'error', message = 'That player is no longer online' })
                return {}
            end
            if categoryId == 'player' and itemId:match('^target:') then
                local selectedAction = selectedPlayerActions[itemId:sub(#'target:' + 1)]
                if not selectedAction or not Admin.hasLevel(selectedAction.level) then
                    error('That player action is no longer available.')
                end
                if selectedAction.run.shouldClose and QB.nui.closeApp then QB.nui.closeApp('qbadmin:menu') end
                selectedAction.run.run(context and context.value)
                return {}
            end
            if categoryId == 'player' and itemId == 'players' then
                local players, err = QB.callback.trigger('qbadmin:menuPlayers')
                if not players then
                    QB.notify.send({ type = 'error', message = err or 'Could not load players' })
                    return {}
                end
                for _, view in ipairs(navigation) do
                    if view.id == 'player' then
                        local blocks = view.content.blocks
                        for index = #blocks, 1, -1 do
                            local blockId = blocks[index].id
                            if blockId == 'online-players' or (blockId and blockId:match('^selected%-player%-')) then
                                table.remove(blocks, index)
                            end
                        end
                        local rows = {}
                        for _, player in ipairs(players) do
                            rows[#rows + 1] = { id = tostring(player.id), name = player.name, job = player.job, ping = player.ping }
                        end
                        blocks[#blocks + 1] = {
                            id = 'online-players', type = 'table', title = 'Online Players',
                            columns = { { key = 'id', label = 'ID' }, { key = 'name', label = 'Name' }, { key = 'job', label = 'Job' }, { key = 'ping', label = 'Ping', align = 'right' } },
                            rows = rows, empty = 'No players are online', action = 'player:select', idKey = 'id',
                        }
                        return { update = { navigation = navigation } }
                    end
                end
            end
            if categoryId == 'audit' and itemId == 'adminlog' then return showAuditInShell() end
            if categoryId == 'audit' and itemId == 'adminlogfilter' then
                return showAuditInShell(context and context.value or {})
            end
            for _, category in ipairs(CATEGORIES) do
                if category.id == categoryId then
                    for _, item in ipairs(category.items) do
                        local stateDisabled = type(item.disabled) == 'function' and item.disabled() or item.disabled == true
                        if item.id == itemId and Admin.hasLevel(item.level) and not stateDisabled
                            and (not item.visible or item.visible()) then
                            if type(item.run) == 'table' then
                                if item.run.shouldClose and QB.nui.closeApp then QB.nui.closeApp('qbadmin:menu') end
                                item.run.run(context and context.value)
                            else
                                item.run()
                            end
                            return {}
                        end
                    end
                end
            end
            error('That administrative action is no longer available.')
        end,
    })
    QB.nui.openApp('qbadmin:menu')
end

RegisterNetEvent('qbadmin:client:openMenu', function(level)
    if type(level) == 'string' then Admin.level = level end
    openRoot()
end)
