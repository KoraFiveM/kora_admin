-- Admin noclip -- freezes ped physics (so gravity/collision stop fighting
-- manual movement) and translates the ped (or its vehicle) each frame along the
-- direction the player is looking. Native movement controls are blocked while
-- it runs so only Config.noclip.adMode decides what A and D do.
--
-- Yaw is owned here, not read back from the gameplay camera: horizontal mouse
-- look (control 1) is blocked and applied to `yaw`, the mover is turned to it
-- and the follow camera is pinned straight behind (relative heading 0) every
-- frame. Reading the camera's heading and writing it to the ped fed back into
-- the follow camera, which swings round on its own when the ped moves towards
-- it -- holding S made the view shake or snap to a random side (kora_admin#21).
-- Vertical look is left to the game camera; its pitch still steers W/S.

local active = false

-- Local copies of kora_lib's cache so the frame loop never makes a
-- cross-resource call. Kept current by onChange.
local ped = Kora.cache.ped()
local vehicle = Kora.cache.vehicle()
local frozenVehicle = false -- the vehicle currently held by this noclip session
local yaw = 0.0 -- heading in degrees the mover faces and the camera sits behind

local function toRadians(deg) return deg * math.pi / 180.0 end

-- Native controls that would otherwise act on the frozen ped/vehicle. Letting
-- A/D (34/35, axis 30) through is what made the character yaw on the spot and
-- drag the follow camera round while noclip also tried to strafe.
local blockedControls = {
    1,                      -- horizontal look: applied to `yaw` instead
    30, 31, 32, 33, 34, 35, -- on-foot move axes and W/A/S/D
    21, 22, 36,             -- sprint, jump, stealth (Shift/Space/Ctrl are noclip speed + height)
    59, 60, 63, 64,         -- vehicle steer axes and A/D
    71, 72, 76,             -- vehicle accelerate, brake, handbrake
}

-- 'strafe': A/D slide sideways relative to the camera. 'turn': A/D yaw the view.
-- Read from Config each frame (a plain local table, edited live by the config editor).
local function adMode()
    return Config.noclip.adMode == 'turn' and 'turn' or 'strafe'
end

local function hold(entity, on)
    FreezeEntityPosition(entity, on)
    SetEntityCollision(entity, not on, not on)
end

local function holdVehicle(veh)
    if frozenVehicle and frozenVehicle ~= veh and DoesEntityExist(frozenVehicle) then hold(frozenVehicle, false) end
    frozenVehicle = veh
    if veh and DoesEntityExist(veh) then hold(veh, true) end
end

local function tick()
    for i = 1, #blockedControls do DisableControlAction(0, blockedControls[i], true) end

    -- In a vehicle the car is what moves; the occupant is carried with it.
    local mover = vehicle or ped
    local coords = GetEntityCoords(mover)

    local speed = Config.noclip.baseSpeed
    if IsDisabledControlPressed(0, 21) then -- Shift = faster
        speed = speed * Config.noclip.fastMultiplier
    elseif IsControlPressed(0, 19) then -- Alt = precision movement
        speed = speed * Config.noclip.slowMultiplier
    end

    local left, right = IsDisabledControlPressed(0, 34), IsDisabledControlPressed(0, 35)

    -- Mouse/right-stick right is a positive normal; GTA headings grow to the left.
    yaw = yaw - GetDisabledControlNormal(0, 1) * (Config.noclip.lookSpeed or 8.0)
    if adMode() == 'turn' then
        yaw = yaw + (Config.noclip.turnSpeed or 2.0) * ((left and 1.0 or 0.0) - (right and 1.0 or 0.0))
    end
    yaw = yaw % 360.0

    local headingRad, pitchRad = toRadians(yaw), toRadians(GetGameplayCamRot(2).x)
    local forwardX, forwardY, forwardZ = -math.sin(headingRad) * math.cos(pitchRad), math.cos(headingRad) * math.cos(pitchRad), math.sin(pitchRad)
    local rightX, rightY = math.cos(headingRad), math.sin(headingRad)

    local dx, dy, dz = 0.0, 0.0, 0.0
    if IsDisabledControlPressed(0, 32) then dx, dy, dz = dx + forwardX, dy + forwardY, dz + forwardZ end -- W
    if IsDisabledControlPressed(0, 33) then dx, dy, dz = dx - forwardX, dy - forwardY, dz - forwardZ end -- S
    if adMode() == 'strafe' then
        if left then dx, dy = dx - rightX, dy - rightY end  -- A
        if right then dx, dy = dx + rightX, dy + rightY end -- D
    end
    if IsDisabledControlPressed(0, 22) then dz = dz + 1.0 end -- space = up
    if IsDisabledControlPressed(0, 36) then dz = dz - 1.0 end -- ctrl = down

    local mag = math.sqrt(dx * dx + dy * dy + dz * dz)
    if mag > 0.0 then
        SetEntityCoordsNoOffset(mover, coords.x + (dx / mag) * speed, coords.y + (dy / mag) * speed, coords.z + (dz / mag) * speed, false, false, false)
    end
    SetEntityHeading(mover, yaw)
    SetGameplayCamRelativeHeading(0.0)
end

local function enable()
    active = true
    Admin.noclipActive = true
    ped = Kora.cache.ped()
    vehicle = Kora.cache.vehicle()
    holdVehicle(vehicle)
    yaw = GetGameplayCamRot(2).z -- start facing wherever the camera already looks
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    SetEntityVisible(ped, false, false)
    Kora.nui.send('noclip:hud', { active = true, adMode = adMode() })

    CreateThread(function()
        while active do
            tick()
            Wait(0)
        end
    end)
end

local function disable()
    active = false
    Admin.noclipActive = false
    holdVehicle(false)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    SetEntityVisible(ped, true, false)
    Kora.nui.send('noclip:hud', nil)
end

Kora.cache.onChange('ped', function(new) ped = new end)
Kora.cache.onChange('vehicle', function(new)
    vehicle = new
    if active then holdVehicle(new) end
end)

RegisterNetEvent('kora_admin:client:noclip', function()
    if active then disable() else enable() end
    if Admin.refreshAppActionStates then Admin.refreshAppActionStates() end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() and active then disable() end
end)
