-- Admin.teleportTo(coords) -- the one client-side teleport primitive that
-- goto/bring/tpcoords/tpm/tpback all funnel through via the same
-- qbadmin:client:teleportTo event; only WHO gets told and WHERE differs,
-- resolved server-side in server/commands/teleport.lua.

local lastPosition = nil -- Config.teleport.tpbackHistory is 1, so a single slot is enough

---@param coords table  -- { x, y, z }
function Admin.teleportTo(coords)
    local ped = PlayerPedId()
    lastPosition = GetEntityCoords(ped)

    DoScreenFadeOut(Config.teleport.fadeTime)
    while not IsScreenFadedOut() do Wait(0) end

    if IsPedInAnyVehicle(ped, false) then
        SetEntityCoords(GetVehiclePedIsIn(ped, false), coords.x, coords.y, coords.z, false, false, false, false)
    else
        SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    end

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    local waited = 0
    while not HasCollisionLoadedAroundEntity(ped) and waited < Config.teleport.collisionTimeout do
        Wait(50)
        waited = waited + 50
    end

    DoScreenFadeIn(Config.teleport.fadeTime)
end

---@return table|nil coords
---@return string|nil err
local function getWaypointCoords()
    local waypoint = GetFirstBlipInfoId(8)
    if not DoesBlipExist(waypoint) then return nil, 'no waypoint set' end

    local coords = GetBlipInfoIdCoord(waypoint)
    local groundZ = nil
    for _ = 1, 5 do
        local found, z = GetGroundZFor_3dCoord(coords.x, coords.y, 750.0, false)
        if found then groundZ = z; break end
        Wait(0)
    end

    return { x = coords.x, y = coords.y, z = groundZ or coords.z }
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
    Admin.teleportTo(coords)
end)

RegisterNetEvent('qbadmin:client:tpback', function()
    if not lastPosition then
        QB.notify.send({ title = 'Admin — Error', message = 'no previous position recorded', type = 'error' })
        return
    end
    Admin.teleportTo({ x = lastPosition.x, y = lastPosition.y, z = lastPosition.z })
end)
