-- A focus-free entity inspector for builders. kora_lib owns every reusable part:
-- raycasting resolves what the camera hits, lookup enriches model hashes,
-- textui renders the HUD, keybind keeps controls rebindable, and nui performs
-- the clipboard write. Native archetype names remain the primary source for
-- props because map archetypes are not guaranteed to appear in a catalogue.

local state = {
    active = false,
    hud = nil,
    snapshot = nil,
    text = nil,
    nextHudAt = 0,
}

local ENTITY_KINDS = {
    [1] = { label = 'Ped', lookupKind = 'ped' },
    [2] = { label = 'Vehicle', lookupKind = 'vehicle' },
    [3] = { label = 'Object', lookupKind = 'object' },
}

local function notify(kind, message)
    Kora.notify.send({ title = 'Entity picker', type = kind, message = message })
end

local function entityKind(entity)
    return ENTITY_KINDS[GetEntityType(entity)] or { label = 'Entity' }
end

local function actualArchetypeName(entity)
    if type(GetEntityArchetypeName) ~= 'function' then return nil end

    local ok, name = pcall(GetEntityArchetypeName, entity)
    if ok and type(name) == 'string' and name ~= '' and name ~= 'NULL' then return name end
end

local function lookupModelName(model, kind)
    if not Kora.lookup or type(Kora.lookup.model) ~= 'function' then return nil end

    local ok, record = pcall(Kora.lookup.model, model, kind.lookupKind)
    if ok and type(record) == 'table' and type(record.name) == 'string' and record.name ~= '' then
        return record.name, record
    end
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function inspectEntity(entity, hitCoords)
    if type(entity) ~= 'number' or entity == 0 or not DoesEntityExist(entity) then return nil end

    local kind = entityKind(entity)
    local model = GetEntityModel(entity)
    local catalogueName, record = lookupModelName(model, kind)
    -- GetEntityArchetypeName is the game's own name for the *specific* object
    -- instance. Prefer it over a lookup result so map props retain their real
    -- archetype even when they are not creatable/catalogued by kora_lib.
    local modelName = actualArchetypeName(entity) or catalogueName
    local coords = GetEntityCoords(entity)

    return {
        entity = entity,
        kind = kind.label,
        model = model,
        modelName = modelName,
        label = record and record.label or nil,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        heading = GetEntityHeading(entity),
        distance = distance(GetEntityCoords(PlayerPedId()), hitCoords),
    }
end

local function hudText(snapshot)
    if not snapshot then
        return ('Aim at a prop, ped, or vehicle\nWaiting for an entity…\n%s copies its model name · %s closes')
            :format(Config.entityPicker.copyKey, Config.entityPicker.closeKey)
    end

    local name = snapshot.modelName or ('Unknown model (%s)'):format(tostring(snapshot.model))
    local title = snapshot.label and snapshot.label ~= name and ('%s · %s'):format(snapshot.kind, snapshot.label)
        or snapshot.kind
    return ('%s\n%s\nHash: %s · %.1fm\n%s copies model · %s closes')
        :format(title, name, tostring(snapshot.model), snapshot.distance,
            Config.entityPicker.copyKey, Config.entityPicker.closeKey)
end

local function updateHud(snapshot)
    local text = hudText(snapshot)
    state.snapshot = snapshot
    if text == state.text then return end

    -- The raycast runs every frame so aiming feels immediate, but a moving
    -- player can change the displayed distance every frame. Keep the HUD
    -- responsive while avoiding a needless 60Hz stream into the browser.
    if GetGameTimer() < state.nextHudAt then return end

    state.text = text
    state.nextHudAt = GetGameTimer() + 100
    if state.hud then
        Kora.textui.update(state.hud, text, { key = Config.entityPicker.copyKey, icon = 'copy', position = 'right-center' })
    end
end

local function stopPicker(message)
    if not state.active then return end

    state.active = false
    state.snapshot = nil
    state.text = nil
    state.nextHudAt = 0
    if state.hud then Kora.textui.hide(state.hud) end
    state.hud = nil
    if message then notify('info', message) end
end

local function copyModelName()
    local snapshot = state.snapshot
    if not state.active then return end
    if not snapshot then
        return notify('error', 'Aim at an entity before copying')
    end
    if not snapshot.modelName then
        return notify('error', ('No model name is available; use hash %s instead'):format(tostring(snapshot.model)))
    end

    local result = Kora.nui.copyToClipboard(snapshot.modelName)
    if type(result) == 'table' and type(result.next) == 'function' then
        result:next(function(copied)
            if copied then
                notify('success', ('Copied %s'):format(snapshot.modelName))
            else
                notify('error', 'Could not copy the model name')
            end
        end, function()
            notify('error', 'Could not copy the model name')
        end)
    else
        notify('success', ('Copied %s'):format(snapshot.modelName))
    end
end

local function startPicker()
    if state.active then
        return notify('info', 'Entity picker is already active')
    end
    if Kora.placement and Kora.placement.isActive and Kora.placement.isActive() then
        return notify('error', 'Finish entity placement before opening the picker')
    end
    if Kora.zones and Kora.zones.isCreatorActive and Kora.zones.isCreatorActive() then
        return notify('error', 'Finish zone creation before opening the picker')
    end

    state.active = true
    state.hud = Kora.textui.show(hudText(nil), {
        key = Config.entityPicker.copyKey,
        icon = 'copy',
        position = 'right-center',
    })
    state.text = hudText(nil)
    state.nextHudAt = 0
    notify('info', 'Aim at an entity; copy and close bindings can be changed in FiveM settings')

    CreateThread(function()
        while state.active do
            local hit, hitCoords, entity = Kora.raycast.fromCamera(Config.entityPicker.maxDistance)
            updateHud(hit and inspectEntity(entity, hitCoords) or nil)
            Wait(0)
        end
    end)
end

Kora.keybind.add({
    name = 'qbadmin_entitypicker_copy',
    description = 'Entity Picker: Copy Model Name',
    defaultMapper = 'keyboard',
    defaultKey = Config.entityPicker.copyKey,
    onPressed = copyModelName,
})

Kora.keybind.add({
    name = 'qbadmin_entitypicker_close',
    description = 'Entity Picker: Close',
    defaultMapper = 'keyboard',
    defaultKey = Config.entityPicker.closeKey,
    onPressed = function() stopPicker('Entity picker closed') end,
})

RegisterNetEvent('qbadmin:client:startEntityPicker', startPicker)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then stopPicker() end
end)
