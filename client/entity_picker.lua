-- A focus-free entity inspector for builders. kora_lib owns every reusable part:
-- raycasting resolves what the camera hits, lookup enriches model hashes,
-- textui renders the HUD, keybind keeps controls rebindable, and nui performs
-- the dialog's Copy Text button. Native archetype names remain the primary source for
-- props because map archetypes are not guaranteed to appear in a catalogue.

local state = {
    active = false,
    hud = nil,
    snapshot = nil,
    text = nil,
    nextHudAt = 0,
}

local ENTITY_KINDS = {
    [1] = { label = Kora.lang('ui.ped'), lookupKind = 'ped' },
    [2] = { label = Kora.lang('ui.vehicle'), lookupKind = 'vehicle' },
    [3] = { label = Kora.lang('ui.object'), lookupKind = 'object' },
}

-- StartShapeTestRay intersect mask: vehicles (2) + peds (8) + objects (16).
local ENTITY_RAY_FLAGS = 26

local function notify(kind, message)
    Kora.notify.send({ title = Kora.lang('title.entity_picker'), type = kind, message = message })
end

local function entityKind(entity)
    return ENTITY_KINDS[GetEntityType(entity)] or { label = Kora.lang('ui.entity') }
end

local function actualArchetypeName(entity)
    if type(GetEntityArchetypeName) ~= 'function' then return nil end
    -- The native raises an unrecoverable engine exception (pcall cannot catch it)
    -- for peds and vehicles, killing the picker thread. Only query real objects.
    if GetEntityType(entity) ~= 3 then return nil end

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

    -- Map buildings and other non-ped/vehicle/object handles make GetEntityModel
    -- (native 0x9F47B058362C84B5, GET_ENTITY_MODEL) throw inside gta-streaming-five.dll,
    -- which aborted every picker frame. Only peds (1), vehicles (2) and objects (3) pass.
    if not ENTITY_KINDS[GetEntityType(entity)] then return nil end

    local kind = entityKind(entity)
    local okModel, model = pcall(GetEntityModel, entity)
    if not okModel or type(model) ~= 'number' then return nil end
    local catalogueName, record = lookupModelName(model, kind)
    -- GetEntityArchetypeName is the game's own name for the *specific* object
    -- instance. Prefer it over a lookup result so map props retain their real
    -- archetype even when they are not creatable/catalogued by kora_lib.
    -- Peds and vehicles use the catalogue name only (see actualArchetypeName).
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

-- A handle the game cannot describe (a building, or an entity streamed out between
-- the ray and the read) is "no entity", not an error: protect the whole read so one
-- bad hit neither aborts the other ray's result nor stalls the picker loop.
local function safeInspect(entity, hitCoords)
    local ok, snapshot = pcall(inspectEntity, entity, hitCoords)
    if ok then return snapshot end
end

local function hudText(snapshot)
    if not snapshot then
        return ('Aim at a prop, ped, or vehicle\nWaiting for an entity…\n%s opens the model menu · %s closes')
            :format(Config.entityPicker.copyKey, Config.entityPicker.closeKey)
    end

    local name = snapshot.modelName or ('Unknown model (%s)'):format(tostring(snapshot.model))
    local title = snapshot.label and snapshot.label ~= name and ('%s · %s'):format(snapshot.kind, snapshot.label)
        or snapshot.kind
    return ('%s\n%s\nHash: %s · %.1fm\n%s model menu · %s closes')
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
    state.menuOpen = false
    if state.hud then Kora.textui.hide(state.hud) end
    state.hud = nil
    if message then notify('info', message) end
end

-- H opens the input dialog instead of writing to the clipboard on its own: the browser
-- often refuses a programmatic copy (no focus, previous clipboard kept), but a click on the
-- dialog's Copy Text button, or the player's own Ctrl+C on the selected name, is a real user
-- copy that always works.
local function openCopyDialog(modelName)
    if state.manualCopyOpen then return end
    if type(Kora.nui.openInputDialog) ~= 'function' then
        return notify('error', Kora.lang('ui.model_name', modelName))
    end

    state.manualCopyOpen = true
    CreateThread(function()
        pcall(Kora.nui.openInputDialog, {
            { id = 'model', label = Kora.lang('ui.model_name_label'), type = 'text', default = modelName, copyButton = { label = Kora.lang('ui.copy_text') } },
        }, 'Entity picker', 'Select the name and press Ctrl+C, then close this dialog.')
        state.manualCopyOpen = false
    end)
end

local function copyModelName()
    local snapshot = state.snapshot
    if not state.active then return end
    if not snapshot then
        return notify('error', Kora.lang('error.aim_entity'))
    end
    if not snapshot.modelName then
        return notify('error', Kora.lang('error.model_name_unavailable', tostring(snapshot.model)))
    end

    openCopyDialog(snapshot.modelName)
end

-- The ray follows the screen centre, but on foot GTA shows no reticle unless a
-- weapon is aimed, so the picker draws a small dot there: green while an entity
-- is under it, white otherwise. Its height is scaled by the aspect ratio so it
-- stays square on any resolution.
local function drawCrosshair(onEntity)
    local width = 0.003
    local height = width * GetAspectRatio(false)
    if onEntity then
        DrawRect(0.5, 0.5, width, height, 80, 220, 100, 230)
    else
        DrawRect(0.5, 0.5, width, height, 255, 255, 255, 200)
    end
end

local function startPicker()
    if state.active then
        return notify('info', Kora.lang('error.entity_picker_active'))
    end
    if Kora.placement and Kora.placement.isActive and Kora.placement.isActive() then
        return notify('error', Kora.lang('error.finish_entity_placement'))
    end
    if Kora.zones and Kora.zones.isCreatorActive and Kora.zones.isCreatorActive() then
        return notify('error', Kora.lang('error.finish_zone_creation'))
    end

    state.active = true
    state.hud = Kora.textui.show(hudText(nil), {
        key = Config.entityPicker.copyKey,
        icon = 'copy',
        position = 'right-center',
    })
    state.text = hudText(nil)
    state.nextHudAt = 0
    notify('info', Kora.lang('ui.entity_picker_help'))

    CreateThread(function()
        while state.active do
            -- Fire the entity-only ray and the catch-all ray together so they settle
            -- in the same frame. The entity mask (peds, vehicles, objects) is what
            -- kora_target uses; the catch-all alone can stop on foliage, glass or
            -- map collision and report entity 0 even with a prop under the dot.
            local ok, err = pcall(function()
                local maxDistance = Config.entityPicker.maxDistance
                local entityRay = Kora.raycast.startFromCamera(maxDistance, ENTITY_RAY_FLAGS)
                local anyRay = Kora.raycast.startFromCamera(maxDistance)
                local hit, hitCoords, entity = Kora.raycast.await(entityRay)
                local snapshot = hit and safeInspect(entity, hitCoords) or nil
                local anyHit, anyCoords, anyEntity = Kora.raycast.await(anyRay)
                if not snapshot and anyHit then snapshot = safeInspect(anyEntity, anyCoords) end
                if not state.menuOpen then updateHud(snapshot) end
            end)
            if not ok then
                print(('[kora_admin] entity picker raycast failed: %s'):format(tostring(err)))
                Wait(1000)
            end
            Wait(0)
        end
    end)

    -- Own thread: the raycast above waits a frame or more for each shape test,
    -- and DrawRect only lasts one frame, so drawing there would flicker.
    if Config.entityPicker.crosshair ~= false then
        CreateThread(function()
            while state.active do
                drawCrosshair(state.snapshot ~= nil)
                Wait(0)
            end
        end)
    end
end

Kora.keybind.add({
    name = 'kora_admin_entitypicker_copy',
    description = Kora.lang('ui.entity_picker_open'),
    defaultMapper = 'keyboard',
    defaultKey = Config.entityPicker.copyKey,
    onPressed = copyModelName,
})

Kora.keybind.add({
    name = 'kora_admin_entitypicker_close',
    description = Kora.lang('ui.entity_picker_close'),
    defaultMapper = 'keyboard',
    defaultKey = Config.entityPicker.closeKey,
    onPressed = function() stopPicker('Entity picker closed') end,
})

RegisterNetEvent('kora_admin:client:startEntityPicker', startPicker)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then stopPicker() end
end)
