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
---before the form opens rather than when SECTIONS is built (see below):
---a field using registry-backed job/item/vehicle options needs Kora.shared to have
---already received its mirror snapshot from kora_core, which may not have
---happened yet at resource-start when SECTIONS itself is constructed.
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
    if GetResourceState('kora_clothing') ~= 'started' then
        Kora.notify.send({ type = 'error', message = 'qbclothing is not running' })
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

---Grades arrive as a one-based array from the registry, but a record that
---bypassed registry normalisation may key them "0", "1", ... (legacy QBCore) or
---by number. Return them as one list sorted by level so the dropdown is never
---empty for a job that does have grades.
---@param grades table|nil
---@return table[]
local function sortedGrades(grades)
    local entries = {}
    for key, grade in pairs(type(grades) == 'table' and grades or {}) do
        local level = tonumber(key)
        if level and type(grade) == 'table' then entries[#entries + 1] = { level = level, grade = grade } end
    end
    table.sort(entries, function(a, b) return a.level < b.level end)
    return entries
end

---Role records (jobs/gangs) the server last sent for the Set Job / Set Gang forms.
---The server reads its authoritative registry, so grades never depend on how
---this client mirror was seeded; the mirror is only the fallback.
local roleCatalogue = {}

local function roleHidden(kind, role, hiddenNames, seenLabels)
    if kind ~= 'jobs' then return false end
    if hiddenNames[role.name] then return true end
    local label = tostring(role.label or role.name):lower()
    if Config.roles.hideDuplicateLabels and seenLabels[label] then return true end
    seenLabels[label] = true
    return false
end

---Build a role selector and its dependent grade selector from one registry
---snapshot. Reading each record directly from the list avoids a second lookup
---returning nil while a client mirror is being re-seeded. Records are
---deduplicated by name (first wins); Config.roles hides placeholder jobs.
---@param kind 'jobs'|'gangs'
---@param label string
---@return table[]
local function roleFields(kind, label)
    local records = roleCatalogue[kind]
    if type(records) ~= 'table' or #records == 0 then records = Kora.shared.all(kind) end
    local hiddenNames = {}
    for _, name in ipairs(Config.roles.hiddenJobs) do hiddenNames[name] = true end

    local roles, gradesByRole, seen, seenLabels = {}, {}, {}, {}
    for _, role in ipairs(records) do
        if not seen[role.name] and not roleHidden(kind, role, hiddenNames, seenLabels) then
            seen[role.name] = true
            roles[#roles + 1] = { value = role.name, label = role.label }
            local grades = {}
            for position, entry in ipairs(sortedGrades(role.grades)) do
                grades[#grades + 1] = {
                    value = tostring(position),
                    label = ('%d - %s'):format(position, entry.grade.name),
                }
            end
            gradesByRole[role.name] = grades
        end
    end

    local firstRole = roles[1] and roles[1].value
    local firstGrade = firstRole and gradesByRole[firstRole][1]
    return {
        { id = 'name', label = label, type = 'select', options = roles, default = firstRole, required = true },
        {
            id = 'grade', label = 'Grade', type = 'select', dependsOn = 'name',
            optionsByValue = gradesByRole, default = firstGrade and firstGrade.value, required = true,
        },
    }
end

local function vehicleOptions()
    local out = {}
    for _, veh in ipairs(Kora.shared.all('vehicles')) do out[#out + 1] = { value = veh.model, label = ('%s (%s)'):format(veh.name, veh.model) } end
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

local function personalVehicleFields(catalogue)
    return {
        catalogue and vehicleCatalogueField() or vehicleModelField(),
        {
            id = 'plate',
            label = 'License plate',
            type = 'text',
            placeholder = 'e.g. STAFF01',
            required = true,
            pattern = '^[A-Za-z0-9]{1,15}$',
        },
    }
end

-- kora_lib calls onAction from its own resource, so FiveM msgpack-encodes the
-- returned table, and that encoder sends any table nested 16 or more levels
-- deep as nil. In a returned { update = { navigation } } a dependent select's
-- choices (field.optionsByValue[value][i]) sit at exactly level 16, so every
-- Set Job / Set Gang grade list reached the NUI empty while the job list (one
-- level shallower) survived. updateApp carries the same navigation as an
-- export argument, two levels shallower, so push updates that way and return
-- only what is left (navigate/notice/close).
---@param appId string
---@param handler fun(actionId: string, context: table): table|nil
---@return fun(actionId: string, context: table): table|nil
local function pushActionUpdates(appId, handler)
    return function(actionId, context)
        local result = handler(actionId, context)
        if type(result) == 'table' and result.update ~= nil and Kora.nui.updateApp then
            Kora.nui.updateApp(appId, result.update)
            result.update = nil
        end
        return result
    end
end

-- AppShell receives its action fields as a snapshot. The kora_core registry
-- snapshot can arrive just after this resource builds the menu, which would
-- leave catalogue and role fields permanently empty for that menu session.
-- Keep the active navigation so registry sync/delta events can replace those
-- fields with the now-populated live lists.
local activeNavigation

local function toggleLabel(subject, enabled)
    return enabled and ('Turn %s Off'):format(subject) or ('Turn %s On'):format(subject)
end

local function toggleVariant(enabled)
    return enabled and 'outline' or 'primary'
end

-- The builder tools are gated on kora_core development mode when
-- Config.developer.requireDevMode is set. Say so on the button instead of
-- leaving a silent grey one, and offer a self toggle in the same section.
local function devGateActive()
    return Config.developer.requireDevMode == true and not Admin.isDevMode()
end

local function gatedLabel(label)
    return devGateActive() and (label .. ' (turn Development Mode on first)') or label
end

local DEV_TOOLS = {
    ['developer:entitypicker'] = 'Inspect Entity',
    ['developer:devplacement'] = 'Place Entity / Model',
    ['developer:devzone'] = 'Create Zone',
}

local function adminDutyLabel()
    return toggleLabel('Admin Duty', Admin.isAdminDuty())
end

local function adminDutyVariant()
    return toggleVariant(Admin.isAdminDuty())
end

local function forEachNavigationContent(navigation, callback)
    for _, view in ipairs(navigation or {}) do
        if view.content then callback(view.content, view) end
        for _, tab in ipairs(view.tabs or {}) do
            if tab.content then callback(tab.content, view, tab) end
        end
    end
end

local function refreshRegistryFields(navigation)
    if type(navigation) ~= 'table' then return end
    forEachNavigationContent(navigation, function(content)
        for _, block in ipairs(content.blocks or {}) do
            if block.type == 'actions' then
                for _, action in ipairs(block.actions or {}) do
                    if action.id == 'vehicle:car_catalogue' or action.id == 'player:target:veh_catalogue' then
                        action.fields = { vehicleCatalogueField() }
                    elseif action.id == 'player:target:setjob' then
                        action.fields = roleFields('jobs', 'Job')
                    elseif action.id == 'player:target:setgang' then
                        action.fields = roleFields('gangs', 'Gang')
                    end
                end
            end
        end
    end)
end

local function updateActiveRegistryFields()
    roleCatalogue = {}
    if not activeNavigation then return end
    refreshRegistryFields(activeNavigation)
    if Kora.nui.updateApp then Kora.nui.updateApp('qbadmin:menu', { navigation = activeNavigation }) end
end

local function refreshAppActionStates()
    if not activeNavigation then return end
    forEachNavigationContent(activeNavigation, function(content)
        for _, block in ipairs(content.blocks or {}) do
            if block.type == 'actions' then
                for _, action in ipairs(block.actions or {}) do
                    if action.id == 'self:aduty' then
                        action.label = adminDutyLabel()
                        action.variant = adminDutyVariant()
                        action.state = Admin.isAdminDuty()
                    elseif action.id == 'teleport:noclip' then
                        local active = Admin.isNoclipActive()
                        action.label = toggleLabel('Noclip', active)
                        action.variant = toggleVariant(active)
                        action.state = active
                    elseif action.id == 'developer:selfdevmode' then
                        local active = Admin.isDevMode()
                        action.label = toggleLabel('Development Mode', active)
                        action.variant = toggleVariant(active)
                        action.state = active
                    elseif DEV_TOOLS[action.id] then
                        action.label = gatedLabel(DEV_TOOLS[action.id])
                        action.disabled = devGateActive() or not Admin.hasLevel(Config.developer.menuLevel)
                    elseif action.id == 'teleport:spectateStop' then
                        action.state = Admin.isSpectating()
                        action.disabled = not Admin.isSpectating()
                    end
                end
            end
        end
    end)
    if Kora.nui.updateApp then Kora.nui.updateApp('qbadmin:menu', { navigation = activeNavigation }) end
end
Admin.refreshAppActionStates = refreshAppActionStates

-- `@kora_core/init.lua` re-seeds its local mirror before later event handlers
-- run, so the snapshot event is the reliable initial-load hook. Changes after
-- that point arrive through the shared-list subscription.
RegisterNetEvent('qbcore:registry:snapshotAll', updateActiveRegistryFields)
if Kora.shared.onChange then
    Kora.shared.onChange('vehicles', updateActiveRegistryFields)
    Kora.shared.onChange('jobs', updateActiveRegistryFields)
    Kora.shared.onChange('gangs', updateActiveRegistryFields)
end

-- Admin duty is replicated by kora_core after the server accepts /aduty. Refresh
-- an already-open shell from that authoritative update instead of guessing at
-- the post-click state locally.
pcall(function()
    exports.kora_core:onPlayerDataChange({ 'metadata', 'adminDuty' }, refreshAppActionStates)
end)

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
    for _, item in ipairs(Kora.shared.all('items')) do out[#out + 1] = { value = item.name, label = item.label or item.name } end
    return out
end

local function weatherOptions()
    local out = {}
    -- kora_weathersync owns the accepted weather list.  kora_admin intentionally
    -- has no manifest dependency on it (the sync resource starts after this
    -- one so it can own /weather), therefore retain the local list only as a
    -- graceful fallback while that resource is stopped/restarting.
    local ok, weatherTypes = pcall(function() return exports['kora_weathersync']:getWeatherTypes() end)
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
        items[#items + 1] = {
            id = 'clip_' .. tostring(event.id or index),
            label = ('Save %s (%ss)'):format(event.name or 'Medal Clip', tostring(event.duration or '?')),
            description = 'Saves this admin’s local replay buffer; requires Medal to be configured and running.',
            icon = 'radio',
            level = Config.medal.menuLevel,
            disabled = function()
                return type(Admin.isMedalConfigured) ~= 'function' or not Admin.isMedalConfigured()
            end,
            run = appAction(function() Admin.invokeMedalEvent(event) end),
        }
    end
    return items
end

-- Sections become tabs inside the broader PAGE_LAYOUT workspaces below.
-- `actionGroup` keeps the established action ids stable when one old section
-- is split into clearer tabs (for example Environment and Server both still
-- dispatch `world:*`). Permission filtering here is cosmetic only: every
-- command re-checks server-side regardless of what this menu shows.
local SECTIONS = {
    {
        id = 'player', label = 'Online', level = 'support',
        title = 'Online Players',
        description = 'Select a player once, then use focused tabs for their profile and administrative tools.',
        items = {
            { id = 'refresh', label = 'Refresh Online Players', level = 'support', icon = 'activity', run = appAction(function() end) },
        },
    },
    {
        id = 'reports', label = 'Queue', level = Config.reports.staffLevel,
        title = 'Player Reports',
        description = 'Review open reports, search the full queue, and manage a report without leaving this workspace.',
        items = {
            { id = 'open', label = 'Open', level = Config.reports.staffLevel, run = appAction(function() end) },
            { id = 'claimed', label = 'Claimed', level = Config.reports.staffLevel, run = appAction(function() end) },
            { id = 'resolved', label = 'Resolved', level = Config.reports.staffLevel, run = appAction(function() end) },
            { id = 'dismissed', label = 'Dismissed', level = Config.reports.staffLevel, run = appAction(function() end) },
            { id = 'all', label = 'All', level = Config.reports.staffLevel, run = appAction(function() end) },
            { id = 'filter', label = 'Filter Reports', level = Config.reports.staffLevel, run = filterReports },
        },
    },
    {
        id = 'self', label = 'General', level = 'mod',
        title = 'Personal Admin Tools',
        description = 'Common staff-state, recovery, and coordinate utilities for your own character.',
        items = {
            {
                id = 'aduty', label = adminDutyLabel, level = 'mod', icon = 'shield',
                variant = adminDutyVariant, state = Admin.isAdminDuty, run = withFields('aduty'),
            },
            { id = 'coords', label = 'Copy Coordinates', level = 'mod', icon = 'copy', run = withFields('coords') },
            { id = 'health', label = 'Set Health', level = 'mod', icon = 'heart',
                run = withFields('health', { { id = 'value', label = 'Health (0-100%, blank = full)', type = 'number', min = 0, max = 100 } }, 'Set Health') },
            { id = 'selfrevive', label = 'Revive Me', level = 'mod', icon = 'activity', run = withFields('selfrevive') },
            { id = 'armor', label = 'Set Armor', level = 'mod', icon = 'shield',
                run = withFields('armor', { { id = 'value', label = 'Armor (blank = full)', type = 'number', min = 0, max = 100 } }, 'Set Armor') },
        },
    },
    {
        id = 'teleport', label = 'Movement', level = 'mod',
        title = 'Movement & Spectating',
        description = 'Move around the map, return to your last position, or leave an active spectate session.',
        items = {
            { id = 'tpm', label = 'Teleport to Waypoint', level = 'mod', icon = 'map-pin', run = withFields('tpm', nil, nil, true) },
            { id = 'tpcoords', label = 'Teleport to Coordinates', level = 'mod', icon = 'map',
                run = withFields('tpcoords', {
                    { id = 'coordinates', label = 'Coordinates', type = 'text', placeholder = 'vec4(123.4, 456.7, 78.9, 90.0)', required = true },
                }, 'Teleport to Coordinates', true) },
            { id = 'tpback', label = 'Teleport Back', level = 'mod', icon = 'arrow-left', run = withFields('tpback', nil, nil, true) },
            {
                id = 'spectateStop', label = 'Stop Spectating', level = 'mod', icon = 'crosshair',
                state = Admin.isSpectating, disabled = function() return not Admin.isSpectating() end,
                run = withFields('spectate', nil, nil, true),
            },
            {
                id = 'noclip', label = function() return toggleLabel('Noclip', Admin.isNoclipActive()) end,
                level = 'admin', icon = 'unlock', variant = function() return toggleVariant(Admin.isNoclipActive()) end,
                state = Admin.isNoclipActive, run = withFields('noclip', nil, nil, true),
            },
        },
    },
    {
        id = 'vehicle', label = 'Vehicles', level = 'mod',
        title = 'Vehicle Tools',
        description = 'Spawn a vehicle for yourself, or repair and remove the vehicle you are using.',
        items = {
            { id = 'car', label = 'Spawn from Code', level = 'admin', icon = 'car', variant = 'primary',
                description = 'Spawn any valid GTA or streamed addon vehicle model for yourself',
                run = withFields('car', function() return { vehicleModelField() } end, 'Spawn vehicle from code') },
            { id = 'car_catalogue', label = 'Browse Vehicle Catalogue', level = 'admin', icon = 'search',
                run = withFields('car', function() return { vehicleCatalogueField() } end, 'Spawn vehicle from catalogue') },
            { id = 'fix', label = 'Repair Current Vehicle', level = 'mod', icon = 'wrench', run = withFields('fix') },
            { id = 'dv', label = 'Delete Vehicle', level = 'admin', icon = 'trash-2', variant = 'destructive',
                description = 'Delete the vehicle you are in, or the nearest vehicle when on foot',
                visible = function() return Kora.cache.vehicle() ~= false or (tonumber(Config.dv.nearestRadius) or 0) > 0 end,
                run = withConfirm('Delete your vehicle, or the nearest one if you are on foot?', withFields('dv')) },
        },
    },
    {
        id = 'appearance', actionGroup = 'self', label = 'Appearance', level = 'mod',
        title = 'Appearance & Clothing',
        description = 'Open a nearby fitting service or your full administrative styling session.',
        items = {
            { id = 'wardrobe', label = 'Open Wardrobe', level = 'mod', icon = 'shopping-bag', run = appAction(function() openClothing('wardrobe') end, nil, nil, true) },
            { id = 'clothingshop', label = 'Nearby Clothing Shop', level = 'mod', icon = 'shopping-bag', run = appAction(function() openClothing('shop', 'clothing') end, nil, nil, true) },
            { id = 'barbershop', label = 'Nearby Barber Shop', level = 'mod', icon = 'user', run = appAction(function() openClothing('shop', 'barber') end, nil, nil, true) },
            { id = 'tattooshop', label = 'Nearby Tattoo Shop', level = 'mod', icon = 'edit', run = appAction(function() openClothing('shop', 'tattoo') end, nil, nil, true) },
            { id = 'stylingall', label = 'Full Administrative Styling', level = 'admin', icon = 'star', variant = 'primary', run = appAction(function() openClothing('admin') end, nil, nil, true) },
        },
    },
    {
        id = 'environment', actionGroup = 'world', label = 'Environment', level = 'admin',
        title = 'World & Environment',
        description = 'Control announcements, global weather, and the server clock.',
        items = {
            { id = 'announce', label = 'Send Announcement', level = 'admin', icon = 'bell',
                run = withFields('announce', { { id = 'message', label = 'Message', type = 'textarea', required = true } }, 'Announce') },
            { id = 'weather', label = 'Set Weather', level = 'admin', icon = 'activity',
                run = withFields('weather', function() return { { id = 'type', label = 'Weather', type = 'select', options = weatherOptions(), required = true } } end, 'Set Weather') },
            { id = 'dynamicweather', label = 'Dynamic Weather', level = 'admin', icon = 'settings',
                description = 'Choose whether weather changes automatically',
                run = withFields('freezeweather', function()
                    return { { id = 'enabled', label = 'Automatic changes', type = 'select', required = true,
                        options = { { value = 'true', label = 'Enabled' }, { value = 'false', label = 'Disabled' } } } }
                end, 'Dynamic Weather') },
            { id = 'time', label = 'Set Time', level = 'admin', icon = 'clock', run = setTime },
        },
    },
    {
        id = 'server', actionGroup = 'world', label = 'Server', level = 'mod',
        title = 'Server Utilities',
        description = 'Inspect the running server or perform carefully gated resource operations.',
        items = {
            { id = 'serverinfo', label = 'Server Information', level = 'mod', icon = 'info', run = withFields('serverinfo') },
            { id = 'restartresource', label = 'Restart Resource', level = 'god', icon = 'activity', variant = 'destructive',
                run = withConfirm('Restart this resource?', withFields('restartresource', { { id = 'name', label = 'Resource name', type = 'text', required = true } }, 'Restart Resource')) },
        },
    },
    {
        -- Online moderation lives in the selected-player workspace. These
        -- actions remain for players who cannot be selected from the table.
        id = 'moderation', label = 'Offline Bans', level = 'admin',
        title = 'Offline Moderation',
        description = 'Ban an offline character or revoke an existing ban by identifier.',
        items = {
            { id = 'ban', label = 'Ban Offline Player', level = 'admin', icon = 'ban', variant = 'destructive',
                run = withConfirm('Ban this player? This is persistent.', withFields('ban', {
                    { id = 'target', label = 'Citizen ID or character name', type = 'text', required = true },
                    { id = 'duration', label = 'Duration (30m, 2h, 7d, or perm)', type = 'text', default = 'perm', required = true },
                    { id = 'reason', label = 'Reason', type = 'text', required = true },
                }, 'Ban Player')) },
            { id = 'unban', label = 'Unban', level = 'admin', icon = 'unlock',
                run = withFields('unban', { { id = 'target', label = 'License or ban id', type = 'text', required = true } }, 'Unban') },
        },
    },
    {
        id = 'audit', label = 'Audit Log', level = 'admin',
        title = 'Administrative Audit Log',
        description = 'Review recent staff actions or narrow the log by action, target, and page.',
        items = {
            { id = 'adminlog', label = 'View Recent Activity', level = 'admin', icon = 'list', run = appAction(function() end) },
            { id = 'adminlogfilter', label = 'Filter Audit Log', level = 'admin', icon = 'search', run = filterAuditLog },
        },
    },
    {
        id = 'configuration', label = 'Configuration', level = Config.configEditor.level,
        title = 'Configuration Editor',
        description = 'Edit registered resource settings. Each field states whether it applies now or needs a restart.',
        items = {
            { id = 'open', label = 'Open Configuration Editor', level = Config.configEditor.level, icon = 'settings',
                run = appAction(function() Kora.config.open() end, nil, nil, true) },
        },
    },
    {
        id = 'developer', label = 'Developer Tools', level = Config.developer.menuLevel,
        title = 'Development Tools',
        description = 'Inspect world entities, place models, build zones, and clean up entities created during your current session.',
        items = {
            {
                id = 'selfdevmode',
                label = function() return toggleLabel('Development Mode', Admin.isDevMode()) end,
                variant = function() return toggleVariant(Admin.isDevMode()) end,
                state = function() return Admin.isDevMode() end,
                icon = 'hammer', level = 'admin',
                visible = function() return Config.developer.requireDevMode == true end,
                run = appAction(function()
                    runCommand('devmode', tostring(Kora.cache.serverId()))
                    -- kora_core mirrors the new state to this client asynchronously.
                    SetTimeout(750, function()
                        if Admin.refreshAppActionStates then Admin.refreshAppActionStates() end
                    end)
                end),
            },
            {
                id = 'entitypicker', label = function() return gatedLabel('Inspect Entity') end, icon = 'scan-search',
                description = 'Aim at a prop, ped, or vehicle to see and copy its real model name',
                level = Config.developer.menuLevel,
                disabled = devGateActive,
                run = withFields('entitypicker', nil, nil, true),
            },
            {
                id = 'devplacement', label = function() return gatedLabel('Place Entity / Model') end, icon = 'box',
                description = 'Position any valid ped, vehicle, or object and copy its transform',
                level = Config.developer.menuLevel,
                disabled = devGateActive,
                run = withFields('devplacement', function() return { placementModelField() } end, 'Entity Placement Creator', true),
            },
            {
                id = 'devzone', label = function() return gatedLabel('Create Zone') end, icon = 'map',
                description = 'Open kora_lib’s box, sphere, or polygon creator',
                level = Config.developer.menuLevel,
                disabled = devGateActive,
                run = withFields('devzone', function() return { zoneTypeField() } end, 'Zone Creator', true),
            },
            { id = 'deleteLastEntity', actionGroup = 'self', label = 'Delete Last Spawned Entity', icon = 'trash-2', variant = 'destructive', level = 'admin',
                run = withConfirm('Delete your last admin-spawned entity?', withFields('deleteentity')) },
        },
    },
    {
        id = 'resource_versions', label = 'Resources', level = Config.developer.menuLevel,
        title = 'Resources', items = {},
    },
    {
        id = 'medal', label = 'Medal Clips', level = Config.medal.menuLevel,
        title = 'Medal Clips',
        description = 'Capture a configured highlight from your local Medal replay buffer.',
        items = medalItems(),
    },
}

local PAGE_LAYOUT = {
    { id = 'players', label = 'Players', icon = 'users', description = 'Online player management', sections = { 'player' } },
    { id = 'reports', label = 'Reports', icon = 'flag', description = 'Player support queue', sections = { 'reports' } },
    { id = 'tools', label = 'My Tools', icon = 'wrench', description = 'Personal and in-world utilities', sections = { 'self', 'teleport', 'vehicle', 'appearance' } },
    { id = 'server', label = 'Server', icon = 'database', description = 'World control and oversight', sections = { 'environment', 'server', 'moderation', 'audit', 'configuration' } },
    { id = 'development', label = 'Developer Tools', icon = 'hammer', description = 'Developer utilities and local captures', sections = { 'developer', 'resource_versions', 'medal' } },
}

local REPORT_STATUS_FILTERS = { open = true, claimed = true, resolved = true, dismissed = true, all = true }

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

-- kora_sql follows mysql2 and returns DATETIME/TIMESTAMP columns as epoch
-- numbers, while oxmysql returns strings. AppShell timelines deliberately
-- require strings, so normalise both drivers' shapes at this UI boundary.
local function formatTimestamp(value)
    if type(value) == 'string' and value ~= '' then return value end
    if type(value) ~= 'number' then return '-' end
    if not os then return tostring(value) end -- FiveM client Lua has no `os`

    local seconds = value
    if math.abs(seconds) >= 100000000000 then seconds = seconds / 1000 end
    local ok, formatted = pcall(os.date, '!%Y-%m-%d %H:%M:%S', math.floor(seconds))
    return ok and formatted or tostring(value)
end

---@param options? { reportsOnly?: boolean, filters?: table } reportsOnly opens a dedicated Reports app (the /reports screen) instead of the full admin menu.
local function openRoot(options)
    local reportsOnly = options and options.reportsOnly == true
    local appId = reportsOnly and 'qbadmin:reports' or 'qbadmin:menu'
    local navigation = {}
    local selectedPlayerActions = {}
    local selectedReportActions = {}
    local selectedReportId
    local koraOnlyResources = true
    local currentReportFilters = options and options.filters or { status = 'open' }
    local sectionsById = {}
    for _, section in ipairs(SECTIONS) do sectionsById[section.id] = section end

    local function actionGroup(section, item)
        return item.actionGroup or section.actionGroup or section.id
    end

    local function buildSectionContent(section)
        local actions = {}
        for _, item in ipairs(section.items) do
            -- `visible`, unlike the level check below, hides the item entirely
            -- when offering it would make no sense in the current game state.
            if not item.visible or item.visible() then
                local label = type(item.label) == 'function' and item.label() or item.label
                local variant = type(item.variant) == 'function' and item.variant() or item.variant
                local state = item.state
                if type(state) == 'function' then state = state() end
                local stateDisabled = type(item.disabled) == 'function' and item.disabled() or item.disabled == true
                actions[#actions + 1] = {
                    id = actionGroup(section, item) .. ':' .. item.id,
                    label = label,
                    icon = item.icon,
                    variant = variant,
                    state = state,
                    disabled = not Admin.hasLevel(item.level) or stateDisabled,
                    fields = type(item.run) == 'table' and item.run.fields and item.run.fields() or nil,
                    confirm = type(item.run) == 'table' and item.run.confirm or nil,
                    closeBeforeAction = type(item.run) == 'table' and item.run.shouldClose or nil,
                }
            end
        end

        local blocks = {}
        if #actions > 0 then blocks[1] = { type = 'actions', actions = actions } end
        return {
            title = section.title or section.label,
            description = section.description or 'Choose an administrative action. Permissions are enforced again by the command handler.',
            blocks = blocks,
        }
    end

    local function sectionTab(section)
        return { id = section.id, label = section.label, content = buildSectionContent(section) }
    end

    for _, page in ipairs(PAGE_LAYOUT) do
        local tabs = {}
        if reportsOnly and page.id ~= 'reports' then goto nextPage end
        for _, sectionId in ipairs(page.sections) do
            local section = sectionsById[sectionId]
            if section and Admin.hasLevel(section.level) then tabs[#tabs + 1] = sectionTab(section) end
        end
        if #tabs > 0 then
            navigation[#navigation + 1] = {
                id = page.id,
                label = page.label,
                icon = page.icon,
                description = page.description,
                defaultTab = tabs[1].id,
                tabs = tabs,
            }
        end
        ::nextPage::
    end

    local function findView(id)
        for _, view in ipairs(navigation) do
            if view.id == id then return view end
        end
    end

    local function findTab(view, id)
        for _, tab in ipairs(view and view.tabs or {}) do
            if tab.id == id then return tab end
        end
    end

    local function showAuditInShell(filters)
        local rows, err = Kora.callback.trigger('qbadmin:menuAuditLog', filters)
        if not rows then
            Kora.notify.send({ type = 'error', message = err or 'Could not load audit log' })
            return {}
        end
        local tab = findTab(findView('server'), 'audit')
        if not tab then return {} end
        local blocks = tab.content.blocks
        for index = #blocks, 1, -1 do
            if blocks[index].id == 'audit-log' then table.remove(blocks, index) end
        end
        local tableRows = {}
        for _, row in ipairs(rows) do
            tableRows[#tableRows + 1] = {
                action = row.action or 'unknown', actor = row.actor_name or 'unknown',
                target = row.target_name or '-', created = formatTimestamp(row.created_text or row.created_at), details = row.details or '',
            }
        end
        blocks[#blocks + 1] = {
            id = 'audit-log', type = 'table', title = 'Audit Log',
            searchable = true, pageSize = 15,
            columns = {
                { key = 'action', label = 'Action', sortable = true }, { key = 'actor', label = 'Actor', sortable = true },
                { key = 'target', label = 'Target', sortable = true }, { key = 'created', label = 'When', sortable = true }, { key = 'details', label = 'Details' },
            },
            rows = tableRows, empty = 'No matching audit entries',
        }
        return { update = { navigation = navigation }, navigate = { viewId = 'server', tabId = 'audit' } }
    end

    local function showResourcesInShell(koraOnly)
        if koraOnly ~= nil then koraOnlyResources = koraOnly == true end
        local resources, err = Kora.callback.trigger('qbadmin:menuResources')
        if not resources then
            Kora.notify.send({ type = 'error', message = err or 'Could not load resources' })
            return {}
        end
        local tab = findTab(findView('development'), 'resource_versions')
        if not tab then return {} end
        tab.content.title = nil
        tab.content.description = nil
        local blocks = tab.content.blocks
        for index = #blocks, 1, -1 do
            if blocks[index].id == 'resource-versions' or blocks[index].id == 'resource-filters' then
                table.remove(blocks, index)
            end
        end
        local rows = {}
        for _, resource in ipairs(resources) do
            if not koraOnlyResources or resource.name:sub(1, 5) == 'kora_' then
                local isKora = resource.name:match('^kora_[%w_%-]+$') ~= nil
                local repositoryUrl = isKora and ('https://github.com/KoraFiveM/%s'):format(resource.name) or nil
                local commitUrl = resource.url
                if repositoryUrl and type(resource.fullCommit) == 'string'
                    and ( #resource.fullCommit == 40 or #resource.fullCommit == 64 )
                    and resource.fullCommit:match('^[%da-fA-F]+$') then
                    commitUrl = ('%s/commit/%s'):format(repositoryUrl, resource.fullCommit)
                end
                rows[#rows + 1] = {
                    resource = isKora
                        and { value = resource.name, label = resource.name, tone = 'primary', badge = true, href = repositoryUrl }
                        or resource.name,
                    state = resource.state,
                    branch = resource.branch or 'Unavailable',
                    commit = resource.commit and {
                        value = resource.commit,
                        description = resource.message or 'Commit message unavailable',
                        href = commitUrl,
                        copyText = commitUrl,
                    } or 'Unavailable',
                }
            end
        end
        blocks[#blocks + 1] = {
            id = 'resource-versions', type = 'table', title = ('Resources (%d)'):format(#rows),
            searchable = true, pageSize = 20,
            headerToggle = { label = 'Kora only', checked = koraOnlyResources, action = 'developer:resources:toggle' },
            refreshAction = 'resource_versions:refresh',
            columns = {
                { key = 'resource', label = 'Resource', sortable = true },
                { key = 'state', label = 'State', sortable = true },
                { key = 'branch', label = 'Branch', sortable = true },
                { key = 'commit', label = 'Commit ref', sortable = true },
            },
            rows = rows, empty = 'No resources found',
        }
        return { update = { navigation = navigation }, navigate = { viewId = 'development', tabId = 'resource_versions' } }
    end

    local function showPlayersInShell()
        local view = findView('players')
        if not view then return {} end
        local players, err = Kora.callback.trigger('qbadmin:menuPlayers')
        if not players then
            Kora.notify.send({ type = 'error', message = err or 'Could not load players' })
            return {}
        end

        -- Back on the list means no player is selected: a later state push for the old
        -- target must not bring its tabs back.
        Admin.refreshSelectedPlayerState = nil
        local tab = sectionTab(sectionsById.player)
        tab.badge = #players
        view.defaultTab = tab.id
        view.tabs = { tab }
        local blocks = tab.content.blocks

        local rows = {}
        for _, player in ipairs(players) do
            rows[#rows + 1] = { id = tostring(player.id), name = player.name, job = player.job, ping = player.ping }
        end
        blocks[#blocks + 1] = {
            id = 'online-players', type = 'table', title = 'Online Players',
            searchable = true, pageSize = 12,
            columns = { { key = 'id', label = 'ID', sortable = true }, { key = 'name', label = 'Name', sortable = true }, { key = 'job', label = 'Job', sortable = true }, { key = 'ping', label = 'Ping', align = 'right', sortable = true } },
            rows = rows, empty = 'No players are online', action = 'player:select', idKey = 'id',
        }
        return { update = { navigation = navigation }, navigate = { viewId = 'players', tabId = tab.id, replace = true } }
    end

    ---`quiet` is a background reload: no error toast, and it gives way if a report
    ---was opened while the queue was loading.
    local function showReportsInShell(filters, quiet)
        local view = findView('reports')
        if not view then return {} end
        currentReportFilters = filters or currentReportFilters
        local rows, err = Kora.callback.trigger('qbadmin:menuReports', currentReportFilters)
        if quiet and selectedReportId then return {} end
        if not rows then
            if not quiet then Kora.notify.send({ type = 'error', message = err or 'Could not load reports' }) end
            return {}
        end
        selectedReportId = nil
        local tab = sectionTab(sectionsById.reports)
        tab.badge = #rows
        view.defaultTab = tab.id
        view.tabs = { tab }
        local blocks = tab.content.blocks

        local tableRows = {}
        local chatOn = Config.reports.chat and Config.reports.chat.enabled == true
        for _, row in ipairs(rows) do
            local unread = tonumber(row.unread) or 0
            tableRows[#tableRows + 1] = {
                id = tostring(row.id), status = { label = row.status, badge = true,
                    tone = row.status == 'open' and 'warning' or row.status == 'resolved' and 'success' or 'neutral' },
                type = row.category or row.type, reporter = row.reporter_name, assigned = row.claimed_by_name or '-',
                subject = row.subject or row.message, age = row.age or '-',
                unread = unread > 0 and { label = tostring(unread), badge = true, tone = 'primary' } or '',
            }
        end
        local columns = {
            { key = 'id', label = '#', sortable = true }, { key = 'status', label = 'Status', sortable = true },
            { key = 'type', label = 'Category', sortable = true }, { key = 'reporter', label = 'Reporter', sortable = true },
            { key = 'subject', label = 'Subject' }, { key = 'assigned', label = 'Assigned' },
            { key = 'age', label = 'Age' },
        }
        -- Live chat: unread player messages since this staff member last opened the report.
        if chatOn then table.insert(columns, 5, { key = 'unread', label = 'New', align = 'center' }) end
        blocks[#blocks + 1] = {
            id = 'report-list', type = 'table', title = 'Player Reports',
            searchable = true, pageSize = 12,
            columns = columns,
            rows = tableRows, empty = 'No matching reports', action = 'reports:select', idKey = 'id',
        }
        return { update = { navigation = navigation }, navigate = { viewId = 'reports', tabId = tab.id, replace = true } }
    end

    ---`quiet` is a background reload of the report already open: no error toast,
    ---and it gives way if the user went Back or opened another report meanwhile.
    local function showSelectedReport(id, quiet)
        local report, err = Kora.callback.trigger('qbadmin:menuReport', id, { live = quiet == true })
        if quiet and selectedReportId ~= tostring(id) then return {} end
        local chatOn = Config.reports.chat and Config.reports.chat.enabled == true
        if not report then
            if not quiet then Kora.notify.send({ type = 'error', message = err or 'Could not load report' }) end
            return {}
        end
        local view = findView('reports')
        if not view then return {} end
        selectedReportActions = {}

        local function add(id_, label, run, destructive)
            selectedReportActions[id_] = run
            return {
                id = 'reports:selected:' .. id_, label = label,
                fields = run.fields and run.fields() or nil,
                confirm = run.confirm,
                variant = destructive == true and 'destructive' or nil,
                closeBeforeAction = run.shouldClose,
            }
        end
        local function action(command, fields, confirmMessage, shouldClose)
            return forSelectedPlayer(tostring(report.id), command, fields, confirmMessage, shouldClose)
        end

        local management = {}
        if report.status == 'open' or report.status == 'claimed' then
            management[#management + 1] = add('claim', report.status == 'claimed' and 'Take Over Report' or 'Claim Report', action('reportclaim'))
            -- With the live chat the composer under the conversation replaces this form.
            if not chatOn then
                management[#management + 1] = add('reply', 'Reply to Reporter', action('reportreply', {
                    { id = 'message', label = 'Reply', type = 'textarea', required = true },
                }))
            end
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
                    closeBeforeAction = run.shouldClose,
                }
            end
            playerAction('goto', 'Teleport to Reporter', 'goto', nil, true)
            playerAction('bring', 'Bring Reporter', 'bring')
            playerAction('sendback', 'Send Reporter Back', 'sendback')
            playerAction('spectate', 'Spectate Reporter', 'spectate', nil, true)
        end

        local conversation = {
            { id = 'report', title = report.reporter_name, description = report.message,
                timestamp = formatTimestamp(report.created_text or report.created_at), icon = 'message-square', tone = 'primary',
                metadata = { { label = 'Role', value = 'player' } } },
        }
        for index, reply in ipairs(report.messages or {}) do
            conversation[#conversation + 1] = {
                id = 'reply-' .. (reply.id or index), title = reply.author_name, description = reply.message,
                timestamp = formatTimestamp(reply.created_text or reply.created_at), icon = 'message-square',
                tone = reply.author_role == 'staff' and 'success' or 'neutral',
                metadata = { { label = 'Role', value = reply.author_role or 'unknown' } },
            }
        end

        local overview
        if chatOn and Admin.reportChatFixedLayout() then
            -- Config.reports.chat.fixedLayout: one screen that never scrolls. The summary moves
            -- into the header line and Back beside the title, so the chat gets the remaining
            -- height and only its message list scrolls.
            local summary = ('%s · %s · Reporter: %s · Assigned to: %s'):format(tostring(report.status),
                tostring(report.category or report.type), tostring(report.reporter_name), tostring(report.claimed_by_name or 'Unassigned'))
            if report.resolution then summary = ('%s · Resolution: %s'):format(summary, tostring(report.resolution)) end
            overview = {
                title = ('Report #%s · %s'):format(report.id, report.type),
                description = summary .. '. Claim, resolve or dismiss from Manage.',
                actions = { { id = 'reports:back', label = 'Back to Report Queue', icon = 'arrow-left', variant = 'ghost' } },
                scrollable = false,
                blocks = { Admin.reportChatBlock(report, 'staff', 'reports:chat:send') },
            }
        end

        local tabs = {
            {
                id = 'overview', label = 'Overview',
                content = overview or {
                    title = ('Report #%s · %s'):format(report.id, report.type),
                    description = chatOn and 'Chat with the reporter live. Claim, resolve or dismiss from Manage.'
                        or 'Review the report conversation and current assignment before taking action.',
                    blocks = {
                        {
                            id = 'selected-report-back', type = 'actions',
                            actions = { { id = 'reports:back', label = 'Back to Report Queue', icon = 'arrow-left', variant = 'ghost' } },
                        },
                        {
                            id = 'selected-report-summary', type = 'details', title = 'Report summary', columns = 2,
                            items = {
                                { label = 'Status', value = report.status, tone = report.status == 'open' and 'warning' or 'neutral' },
                                { label = 'Category', value = report.category or report.type },
                                { label = 'Reporter', value = report.reporter_name },
                                { label = 'Assigned to', value = report.claimed_by_name or 'Unassigned' },
                                { label = 'Resolution', value = report.resolution or 'Open' },
                            },
                        },
                        chatOn and Admin.reportChatBlock(report, 'staff', 'reports:chat:send') or {
                            id = 'selected-report-conversation', type = 'timeline', title = 'Conversation',
                            items = conversation,
                        },
                    },
                },
            },
            {
                id = 'manage', label = 'Manage', badge = #management,
                content = {
                    title = 'Report Management',
                    description = 'Claim, respond to, or resolve this report. Every action is written to the audit log.',
                    blocks = { { id = 'selected-report-management', type = 'actions', actions = management } },
                },
            },
        }
        if #reporterActions > 0 then
            tabs[#tabs + 1] = {
                id = 'reporter', label = 'Online Reporter',
                content = {
                    title = report.reporter_name,
                    description = 'The reporter is online. Use these shortcuts without leaving the report.',
                    blocks = { { id = 'selected-report-player', type = 'actions', actions = reporterActions } },
                },
            }
        end
        view.defaultTab = 'overview'
        view.tabs = tabs
        selectedReportId = tostring(report.id)
        return { update = { navigation = navigation }, navigate = { viewId = 'reports', tabId = 'overview' } }
    end

    -- Server pushes (qbadmin:client:reportChanged) land here. The open report's
    -- conversation reloads when it is the one that changed, otherwise the queue
    -- reloads. Only `update` is applied -- never `navigate` -- so the staff
    -- member keeps their tab, and the shell keeps any half-typed reply in its
    -- form drafts. Bursts are folded into one reload at a time.
    local liveRefreshing, livePending = false, {}
    local function refreshReportsLive(pending)
        local result
        if selectedReportId then
            if not pending[selectedReportId] then return end
            result = showSelectedReport(selectedReportId, true)
        else
            result = showReportsInShell(currentReportFilters, true)
        end
        if result.update and Kora.nui.updateApp then Kora.nui.updateApp(appId, result.update) end
    end

    Admin.refreshOpenReports = function(changedId)
        if Kora.nui.isAppOpen and not Kora.nui.isAppOpen(appId) then return end
        livePending[tostring(changedId)] = true
        if liveRefreshing then return end
        liveRefreshing = true
        while next(livePending) do
            local pending = livePending
            livePending = {}
            local ok, refreshErr = pcall(refreshReportsLive, pending)
            if not ok then print(('^1[qbadmin]^7 live report refresh failed: %s'):format(tostring(refreshErr))) end
        end
        liveRefreshing = false
    end

    -- Selecting a row is the player-first workflow.  It exposes every
    -- meaningful online-player command in one place, with the selected server
    -- id fixed into the action so staff never have to choose the same person
    -- twice.  The table includes the caller too, so self actions work through
    -- exactly the same screen.
    local function showSelectedPlayer(player)
        local profile, profileErr = Kora.callback.trigger('qbadmin:menuPlayerProfile', player.id)
        if not profile then
            Kora.notify.send({ type = 'error', message = profileErr or 'That player is no longer online' })
            return {}
        end

        local roles = Kora.callback.trigger('qbadmin:menuRoles')
        if type(roles) == 'table' then roleCatalogue = roles end

        local view = findView('players')
        if not view then return {} end

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

        local function add(groupId, id, label, level, run, state, variant)
            if not Admin.hasLevel(level) then return end
            selectedPlayerActions[id] = { level = level, run = run }
            local actions = groupById[groupId].actions
            actions[#actions + 1] = {
                id = 'player:target:' .. id,
                label = label,
                fields = run.fields and run.fields() or nil,
                confirm = run.confirm,
                closeBeforeAction = run.shouldClose,
                state = state,
                variant = variant,
            }
        end
        local function selected(command, fields, confirmMessage, shouldClose)
            return forSelectedPlayer(target, command, fields, confirmMessage, shouldClose)
        end

        add('profile', 'copyinfo', 'Copy Player Info', 'support', appAction(function()
            Kora.nui.copyToClipboard(playerProfileClipboard(profile))
            Kora.notify.send({ type = 'success', message = 'Player information copied' })
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
        add('wellbeing', 'freeze', profile.frozen and 'Unfreeze Player' or 'Freeze Player', 'mod', selected('freeze'),
            profile.frozen, toggleVariant(profile.frozen))
        add('wellbeing', 'god', toggleLabel('God Mode', profile.godMode), 'mod', selected('god'),
            profile.godMode, toggleVariant(profile.godMode))
        add('wellbeing', 'invisible', toggleLabel('Invisibility', profile.invisible), 'mod', selected('invisible'),
            profile.invisible, toggleVariant(profile.invisible))

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
            return roleFields('jobs', 'Job')
        end))
        add('roles', 'setgang', 'Set Gang', 'admin', selected('setgang', function()
            return roleFields('gangs', 'Gang')
        end))
        add('roles', 'setduty', profile.onDuty and 'Take Off Duty' or 'Put On Duty', 'mod', selected('setduty'),
            profile.onDuty, toggleVariant(profile.onDuty))

        add('spawning', 'veh', 'Spawn Vehicle', 'admin', selected('veh', function() return { vehicleModelField() } end))
        add('spawning', 'veh_catalogue', 'Spawn Vehicle from Catalogue', 'admin', selected('veh', function()
            return { vehicleCatalogueField() }
        end))
        add('spawning', 'givevehicle', 'Add Personal Vehicle', 'admin', selected('givevehicle', function()
            return personalVehicleFields(false)
        end))
        add('spawning', 'givevehicle_catalogue', 'Add Personal Vehicle from Catalogue', 'admin', selected('givevehicle', function()
            return personalVehicleFields(true)
        end))
        add('spawning', 'entityfor', 'Spawn Ped / Prop', 'admin', selected('entityfor', function() return { entityModelField() } end))

        add('development', 'devmode', toggleLabel('Development Mode', profile.devMode), 'admin', selected('devmode'),
            profile.devMode, toggleVariant(profile.devMode))

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

        local function actionBlocks(groupIds)
            local blocks = {}
            for _, groupId in ipairs(groupIds) do
                local group = groupById[groupId]
                if group and #group.actions > 0 then
                    blocks[#blocks + 1] = {
                        id = 'selected-player-actions-' .. group.id,
                        type = 'actions', title = group.title, actions = group.actions,
                    }
                end
            end
            return blocks
        end

        local overviewBlocks = {
            {
                id = 'selected-player-back', type = 'actions',
                actions = { { id = 'player:back', label = 'Back to Online Players', icon = 'arrow-left', variant = 'ghost' } },
            },
            {
                id = 'selected-player-header', type = 'text', title = ('#%s · %s'):format(target, profile.name),
                text = ('%s · %s · %dms'):format(profile.job or 'Unknown job', profile.citizenid or 'Unknown citizen', profile.ping or 0),
            },
            {
                id = 'selected-player-details', type = 'details', title = 'Player Information', columns = 2,
                items = (function()
                    local items = {}
                    for _, row in ipairs(playerProfileRows(profile)) do
                        items[#items + 1] = { label = row.field, value = row.value }
                    end
                    return items
                end)(),
            },
        }
        for _, block in ipairs(actionBlocks({ 'profile', 'history' })) do overviewBlocks[#overviewBlocks + 1] = block end

        local tabGroups = {
            { id = 'player-tools', label = 'Player Tools', groups = { 'movement', 'wellbeing', 'appearance' } },
            { id = 'moderation', label = 'Moderation', groups = { 'moderation' } },
            { id = 'inventory', label = 'Economy & Items', groups = { 'economy' } },
            { id = 'roles', label = 'Roles & Access', groups = { 'roles', 'access' } },
            { id = 'advanced', label = 'Advanced', groups = { 'spawning', 'development' } },
        }
        local tabs = {
            {
                id = 'overview', label = 'Overview',
                content = {
                    title = ('Player Profile · #%s %s'):format(target, profile.name),
                    description = 'Fresh server data for the selected player. Use the tabs to keep related actions together.',
                    blocks = overviewBlocks,
                },
            },
        }
        for _, tabGroup in ipairs(tabGroups) do
            local blocks = actionBlocks(tabGroup.groups)
            if #blocks > 0 then
                tabs[#tabs + 1] = {
                    id = tabGroup.id, label = tabGroup.label,
                    content = {
                        title = ('%s · %s'):format(profile.name, tabGroup.label),
                        description = 'Actions apply to the selected player until you return to the online list.',
                        blocks = blocks,
                    },
                }
            end
        end
        -- The header "<" (Config.menu.playerProfileHeaderBack) is the same action as
        -- "Back to Online Players": it clears the selected player, so these per-player
        -- tabs disappear. It is set on the per-player tabs only, never on the Online tab.
        local headerBack = Config.menu and Config.menu.playerProfileHeaderBack == true
        if headerBack then
            for _, playerTab in ipairs(tabs) do playerTab.back = 'player:back' end
        end
        -- Keep the Online list as the first tab: it is the one-click way back to the list.
        local listTab = findTab(view, 'player')
        if listTab then table.insert(tabs, 1, listTab) end
        view.defaultTab = 'overview'
        view.tabs = tabs
        Admin.refreshSelectedPlayerState = function(updatedTarget)
            if tostring(updatedTarget) ~= target then return end
            local refreshed = showSelectedPlayer({ id = target })
            if refreshed.update and Kora.nui.updateApp then Kora.nui.updateApp('qbadmin:menu', refreshed.update) end
        end
        -- No history step: the per-player tabs carry their own header back action (above),
        -- so the shell's history arrow cannot outlive the selected player.
        return { update = { navigation = navigation }, navigate = { viewId = 'players', tabId = 'overview', replace = true } }
    end

    -- Seed the live-data workspaces before registration so opening the
    -- menu lands on useful tables immediately, without a blank first frame or
    -- an extra "view" click. The same functions handle refresh/back actions.
    if reportsOnly then
        showReportsInShell(currentReportFilters)
    else
        activeNavigation = navigation
        showPlayersInShell()
        showReportsInShell({ status = 'open' })
        if Admin.hasLevel(Config.developer.menuLevel) then showResourcesInShell() end
        refreshRegistryFields(activeNavigation)
    end
    Kora.nui.registerApp({
        id = appId,
        title = reportsOnly and 'Player Reports' or 'Administration',
        description = reportsOnly and 'Player support queue' or 'Server administration',
        icon = reportsOnly and 'flag' or 'shield-check',
        defaultView = navigation[1] and navigation[1].id,
        navigation = navigation,
        footer = 'Every action is checked and audited by the server.',
        onAction = pushActionUpdates(appId, function(actionId, context)
            local categoryId, itemId = actionId:match('^([^:]+):(.+)$')
            if categoryId == 'reports' and itemId == 'select' and context and context.itemId then
                return showSelectedReport(context.itemId)
            end
            if categoryId == 'reports' and itemId == 'chat:send' then
                if not selectedReportId then error('Open a report first.') end
                local sendErr = Admin.sendReportChat(selectedReportId, context and type(context.value) == 'table' and context.value.message)
                if sendErr then return { notice = { tone = 'destructive', message = sendErr } } end
                local refreshed = showSelectedReport(selectedReportId, true)
                return { update = refreshed.update }
            end
            if categoryId == 'reports' and itemId:match('^selected:') then
                local selectedAction = selectedReportActions[itemId:sub(#'selected:' + 1)]
                if not selectedAction then error('That report action is no longer available.') end
                selectedAction.run(context and context.value)
                return {}
            end
            if categoryId == 'reports' and REPORT_STATUS_FILTERS[itemId] then
                return showReportsInShell({ status = itemId })
            end
            if categoryId == 'reports' and itemId == 'filter' then
                return showReportsInShell(context and context.value or {})
            end
            if categoryId == 'reports' and itemId == 'back' then
                return showReportsInShell(currentReportFilters)
            end
            if categoryId == 'player' and itemId == 'refresh' then
                return showPlayersInShell()
            end
            if categoryId == 'player' and itemId == 'select' and context and context.itemId then
                local selected
                local tab = findTab(findView('players'), 'player')
                for _, block in ipairs(tab and tab.content.blocks or {}) do
                    if block.id == 'online-players' then
                        for _, row in ipairs(block.rows) do
                            if tostring(row.id) == tostring(context.itemId) then
                                selected = row
                                break
                            end
                        end
                    end
                end
                if selected then return showSelectedPlayer(selected) end
                Kora.notify.send({ type = 'error', message = 'That player is no longer online' })
                return {}
            end
            if categoryId == 'player' and itemId == 'back' then
                return showPlayersInShell()
            end
            if categoryId == 'player' and itemId:match('^target:') then
                local selectedAction = selectedPlayerActions[itemId:sub(#'target:' + 1)]
                if not selectedAction or not Admin.hasLevel(selectedAction.level) then
                    error('That player action is no longer available.')
                end
                selectedAction.run.run(context and context.value)
                return {}
            end
            if categoryId == 'audit' and itemId == 'adminlog' then return showAuditInShell() end
            if categoryId == 'audit' and itemId == 'adminlogfilter' then
                return showAuditInShell(context and context.value or {})
            end
            if categoryId == 'resource_versions' and itemId == 'refresh' then return showResourcesInShell() end
            if categoryId == 'developer' and itemId == 'resources:toggle' then
                return showResourcesInShell(context and context.value == true)
            end
            for _, section in ipairs(SECTIONS) do
                for _, item in ipairs(section.items) do
                    local stateDisabled = type(item.disabled) == 'function' and item.disabled() or item.disabled == true
                    if actionGroup(section, item) == categoryId and item.id == itemId
                        and Admin.hasLevel(item.level) and not stateDisabled
                        and (not item.visible or item.visible()) then
                        if type(item.run) == 'table' then
                            item.run.run(context and context.value)
                        else
                            item.run()
                        end
                        return {}
                    end
                end
            end
            error('That administrative action is no longer available.')
        end),
    })
    Kora.nui.openApp(appId)
end

RegisterNetEvent('qbadmin:client:refreshMenuPlayerState', function(targetSrc)
    if Admin.refreshSelectedPlayerState then Admin.refreshSelectedPlayerState(targetSrc) end
end)

RegisterNetEvent('qbadmin:client:reportChanged', function(id)
    if Admin.refreshOpenReports then Admin.refreshOpenReports(id) end
end)

RegisterNetEvent('qbadmin:client:openReports', function(level, filters)
    if type(level) == 'string' then Admin.level = level end
    openRoot({ reportsOnly = true, filters = type(filters) == 'table' and filters or nil })
end)

RegisterNetEvent('qbadmin:client:openMenu', function(level)
    if type(level) == 'string' then Admin.level = level end
    openRoot()
end)
