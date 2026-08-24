-- Admin.teleportTo(coords) -- the one client-side teleport primitive that
-- goto/bring/tpcoords/tpm/tpback all funnel through via the same
-- qbadmin:client:teleportTo event; only WHO gets told and WHERE differs,
-- resolved server-side in server/commands/teleport.lua.

local lastPosition = nil -- Config.teleport.tpbackHistory is 1, so a single slot is enough

---Moves the ped/vehicle to `coords` and waits for collision to stream in
---around the destination. Split out of Admin.teleportTo so a ground-snap
---pass can request collision at an intermediate altitude, then again at the
---final one, without duplicating the wait loop.
---@param entity integer
---@param x number
---@param y number
---@param z number
local function moveAndWaitForCollision(entity, x, y, z)
    SetEntityCoords(entity, x, y, z, false, false, false, false)

    RequestCollisionAtCoord(x, y, z)
    local waited = 0
    while not HasCollisionLoadedAroundEntity(entity) and waited < Config.teleport.collisionTimeout do
        Wait(50)
        waited = waited + 50
    end
end

---@param coords table  -- { x, y, z }
---@param groundSnap boolean|nil  -- true when `coords.z` isn't trustworthy (e.g. a waypoint's map-projected z)
function Admin.teleportTo(coords, groundSnap)
    local ped = PlayerPedId()
    lastPosition = GetEntityCoords(ped)
    local entity = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped

    DoScreenFadeOut(Config.teleport.fadeTime)
    while not IsScreenFadedOut() do Wait(0) end

    if groundSnap then
        -- `coords.z` cannot be trusted yet -- nothing is streamed in around
        -- the destination until collision is requested there, so any ground
        -- check run beforehand (e.g. from the player's current, unrelated
        -- location) reliably fails and would otherwise fall back to the
        -- waypoint's raw map-projected z, which is not real world elevation
        -- and can land well under the terrain. Land high above the target
        -- first -- with collision not yet loaded there's nothing to clip
        -- into -- then, once collision has actually streamed in, look for
        -- the ground and settle onto it.
        moveAndWaitForCollision(entity, coords.x, coords.y, coords.z + Config.teleport.groundSnapHeight)

        local found, groundZ
        for _ = 1, Config.teleport.groundSnapAttempts do
            found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + Config.teleport.groundSnapHeight, false)
            if found then break end
            Wait(0)
        end

        if found then
            SetEntityCoords(entity, coords.x, coords.y, groundZ + 1.0, false, false, false, false)
        end
        -- If ground was never found (open water, world edge, etc.), stay at
        -- the safe high-altitude coords rather than guess -- ragdolling to a
        -- fall is preferable to spawning under the map with no way out.
    else
        moveAndWaitForCollision(entity, coords.x, coords.y, coords.z)
    end

    DoScreenFadeIn(Config.teleport.fadeTime)
end

---@return table|nil coords
---@return string|nil err
local function getWaypointCoords()
    local waypoint = GetFirstBlipInfoId(8)
    if not DoesBlipExist(waypoint) then return nil, 'no waypoint set' end

    local coords = GetBlipInfoIdCoord(waypoint)
    return { x = coords.x, y = coords.y, z = coords.z }
end

RegisterNetEvent('qbadmin:client:teleportTo', function(coords)
    Admin.teleportTo(coords)
end)

RegisterNetEvent('qbadmin:client:tpm', function()
    local coords, err = getWaypointCoords()
    if not coords then
        QB.notify.send({ title = 'Admin — Error', message = err, type = 'error' })
        return
    end
    Admin.teleportTo(coords, true)
end)

RegisterNetEvent('qbadmin:client:tpback', function()
    if not lastPosition then
        QB.notify.send({ title = 'Admin — Error', message = 'no previous position recorded', type = 'error' })
        return
    end
    Admin.teleportTo({ x = lastPosition.x, y = lastPosition.y, z = lastPosition.z })
end)
