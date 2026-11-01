-- Admin noclip -- freezes ped physics (so gravity/collision stop fighting
-- manual movement) and translates the ped each frame along the direction the
-- player is already looking (GetGameplayCamRot), so mouse-look keeps working
-- for free without taking over the render camera.

local active = false

local function toRadians(deg) return deg * math.pi / 180.0 end

local function tick()
    local ped = PlayerPedId()
    local rot = GetGameplayCamRot(2)
    local coords = GetEntityCoords(ped)

    local speed = Config.noclip.baseSpeed
    if IsControlPressed(0, 21) then -- Shift = faster
        speed = speed * Config.noclip.fastMultiplier
    elseif IsControlPressed(0, 19) then -- Alt = precision movement
        speed = speed * Config.noclip.slowMultiplier
    end

    local headingRad, pitchRad = toRadians(rot.z), toRadians(rot.x)
    local forwardX, forwardY, forwardZ = -math.sin(headingRad) * math.cos(pitchRad), math.cos(headingRad) * math.cos(pitchRad), math.sin(pitchRad)
    local rightX, rightY = math.cos(headingRad), math.sin(headingRad)

    local dx, dy, dz = 0.0, 0.0, 0.0
    if IsControlPressed(0, 32) then dx, dy, dz = dx + forwardX, dy + forwardY, dz + forwardZ end -- W
    if IsControlPressed(0, 33) then dx, dy, dz = dx - forwardX, dy - forwardY, dz - forwardZ end -- S
    if IsControlPressed(0, 34) then dx, dy = dx - rightX, dy - rightY end                          -- A
    if IsControlPressed(0, 35) then dx, dy = dx + rightX, dy + rightY end                          -- D
    if IsControlPressed(0, 22) then dz = dz + 1.0 end                                              -- space = up
    if IsControlPressed(0, 36) then dz = dz - 1.0 end                                              -- ctrl = down

    local mag = math.sqrt(dx * dx + dy * dy + dz * dz)
    if mag > 0.0 then
        SetEntityCoordsNoOffset(ped, coords.x + (dx / mag) * speed, coords.y + (dy / mag) * speed, coords.z + (dz / mag) * speed, false, false, false)
    end
    SetEntityHeading(ped, rot.z)
end

local function enable()
    active = true
    Admin.noclipActive = true
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    SetEntityVisible(ped, false, false)
    Kora.nui.send('noclip:hud', { active = true })

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
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    SetEntityVisible(ped, true, false)
    Kora.nui.send('noclip:hud', nil)
end

RegisterNetEvent('qbadmin:client:noclip', function()
    if active then disable() else enable() end
    if Admin.refreshAppActionStates then Admin.refreshAppActionStates() end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() and active then disable() end
end)
