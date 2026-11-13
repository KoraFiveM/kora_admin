-- Admin.teleportTo(coords) -- the one client-side teleport primitive that
-- goto/bring/tpcoords/tpm/tpback all funnel through via the same
-- kora_admin:client:teleportTo event; only WHO gets told and WHERE differs,
-- resolved server-side in server/commands/teleport.lua.
--
-- Matches txAdmin's own teleport algorithm (its
-- resource/menu/client/cl_main_page.lua's teleportToCoords/handleTpNormally,
-- and cl_functions.lua's FindZForCoords) -- every teleport (not just a
-- ground-snapped one) launches at a fixed safe altitude first and waits for
-- the ENGINE's own "still waiting for world collision" signal, and ground
-- resolution is a repeated, drilling-down probe rather than a single check.

local lastPosition = nil -- Config.teleport.tpbackHistory is 1, so a single slot is enough

---Moves the ped (and, via SetPedCoordsKeepVehicle, any vehicle it's in) to
---(x, y, z) and waits for the engine to finish streaming collision in there.
---Matches txAdmin's handleTpNormally exactly: it polls
---IsEntityWaitingForWorldCollision(ped) rather than RequestCollisionAtCoord +
---HasCollisionLoadedAroundEntity, and runs for EVERY teleport (ground-snapped
---or not) -- landing high first is what stops any destination, including a
---literal admin-supplied one, from clipping into not-yet-streamed geometry.
---collisionTimeout is a safety net upstream's own unconditional loop doesn't
---have, kept so a destination that never resolves collision can't leave the
---screen faded out forever.
---@param x number
---@param y number
---@param z number
local function movePedAndWaitForCollision(x, y, z)
    local ped = PlayerPedId()
    SetPedCoordsKeepVehicle(ped, x, y, z)

    local waited = 0
    while IsEntityWaitingForWorldCollision(ped) and waited < Config.teleport.collisionTimeout do
        Wait(100)
        waited = waited + 100
    end
end

---Freezes (or unfreezes) the ped's vehicle if it's in one, otherwise the ped
---itself -- same split upstream's handleTpNormally makes around its own
---collision wait, so nothing drifts/falls mid-teleport before collision (and
---then real physics) is ready for it.
---@param ped integer
---@param frozen boolean
local function freezeForTeleport(ped, frozen)
    local vehicle = GetVehiclePedIsIn(ped, false)
    FreezeEntityPosition(vehicle > 0 and vehicle or ped, frozen)
end

---Ground level at (x, y), or nil if none is found within
---Config.teleport.groundZAttempts probes. Ports txAdmin's own
---FindZForCoords (resource/menu/client/cl_functions.lua) exactly: rather
---than a single ground check, it repeatedly probes just below whatever
---ground it last found, drilling down through stacked surfaces (a bridge
---deck, then the street underneath it) until nothing more turns up below --
---so it lands on the LOWEST reachable surface at (x, y), not just the first
---one hit. Starts at 1500 (comfortably above anything on the map).
---@param x number
---@param y number
---@return number|nil groundZ
local function findGroundZ(x, y)
    local z = 1500.0
    local found = true

    while found and z > 0 do
        local ok, groundZ = GetGroundZFor_3dCoord(x, y, z - 1.0, false)
        if ok then z = groundZ end
        found = ok
        Wait(0)
    end

    if z == 1500.0 then return nil end
    return z
end

---@param coords table  -- { x, y, z, heading? }
---@param groundSnap boolean|nil  -- true when `coords.z` isn't trustworthy (e.g. a waypoint's map-projected z)
function Admin.teleportTo(coords, groundSnap)
    local ped = PlayerPedId()
    lastPosition = GetEntityCoords(ped)

    DoScreenFadeOut(Config.teleport.fadeTime)
    while not IsScreenFadedOut() do Wait(0) end

    freezeForTeleport(ped, true)
    -- Always launch at a fixed safe altitude first: coords.z can't be trusted
    -- for a ground-snapped destination until collision has streamed in.
    movePedAndWaitForCollision(coords.x, coords.y, Config.teleport.waypointLaunchHeight)

    local z = coords.z
    if groundSnap then
        -- Retry in case collision hasn't finished streaming in; delay only between failed attempts.
        local found
        for attempt = 1, Config.teleport.groundZAttempts do
            found = findGroundZ(coords.x, coords.y)
            if found then break end
            if attempt < Config.teleport.groundZAttempts then Wait(Config.teleport.groundZRetryDelay) end
        end
        -- No ground found (open water, world edge): stay at the safe high-altitude landing.
        if found then z = found end
    end

    ped = PlayerPedId() -- re-fetch: SetPedCoordsKeepVehicle above may have swapped which entity is "the vehicle"
    SetPedCoordsKeepVehicle(ped, coords.x, coords.y, z)

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle > 0 then SetVehicleOnGroundProperly(vehicle) end
    if coords.heading ~= nil then SetEntityHeading(vehicle > 0 and vehicle or ped, coords.heading) end
    freezeForTeleport(ped, false)

    SetGameplayCamRelativeHeading(0.0)

    DoScreenFadeIn(Config.teleport.fadeTime)
end

---@return table|nil coords
---@return string|nil err
local function getWaypointCoords()
    if not IsWaypointActive() then return nil, Kora.lang('error.no_waypoint') end

    local waypoint = GetFirstBlipInfoId(GetWaypointBlipEnumId())
    if not DoesBlipExist(waypoint) then return nil, Kora.lang('error.no_waypoint') end

    local coords = GetBlipInfoIdCoord(waypoint)
    return { x = coords.x, y = coords.y, z = coords.z }
end

RegisterNetEvent('kora_admin:client:teleportTo', function(coords)
    Admin.teleportTo(coords)
end)

RegisterNetEvent('kora_admin:client:tpm', function()
    local coords, err = getWaypointCoords()
    if not coords then
        Kora.notify.send({ title = Kora.lang('title.error'), message = err, type = 'error' })
        return
    end
    Admin.teleportTo(coords, true)
end)

RegisterNetEvent('kora_admin:client:tpback', function()
    if not lastPosition then
        Kora.notify.send({ title = Kora.lang('title.error'), message = Kora.lang('error.no_previous_position'), type = 'error' })
        return
    end
    Admin.teleportTo({ x = lastPosition.x, y = lastPosition.y, z = lastPosition.z })
end)
