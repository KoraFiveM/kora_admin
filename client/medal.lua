-- Medal's Auto-Clipping API listens only on the player's own loopback
-- interface. FiveM's Lua HTTP helper is server-only, so a tiny, invisible NUI
-- page performs the local request and reports the result back to this client.

local pending = {}
local nextRequestId = 0

local function notify(notificationType, message)
    Kora.notify.send({ type = notificationType, message = message })
end

local function trim(value)
    return type(value) == 'string' and Kora.util.trim(value) or ''
end

local function publicKey()
    local key = trim(Config.medal and Config.medal.publicKey)
    local convar = Config.medal and trim(Config.medal.publicKeyConvar)
    if convar ~= '' and type(GetConvar) == 'function' then
        local replicated = trim(GetConvar(convar, ''))
        if replicated ~= '' then key = replicated end
    end
    return key
end

---@return boolean
function Admin.isMedalConfigured()
    return Config.medal ~= nil and publicKey() ~= '' and type(Config.medal.events) == 'table'
        and #Config.medal.events > 0
end

---@param event table
---@return boolean
function Admin.invokeMedalEvent(event)
    local key = publicKey()
    if key == '' then
        notify('error', 'Medal clipping is not configured. Set qbadmin_medal_public_key on the server.')
        return false
    end

    local eventId = type(event) == 'table' and trim(tostring(event.id or '')) or ''
    local eventName = type(event) == 'table' and trim(event.name) or ''
    local duration = type(event) == 'table' and tonumber(event.duration) or nil
    local captureDelayMs = type(event) == 'table' and tonumber(event.captureDelayMs or 0) or nil
    if not eventId:match('^%d+$') or eventName == '' or not duration or duration <= 0
        or not captureDelayMs or captureDelayMs < 0 then
        notify('error', 'This Medal clip event is invalid. Check Config.medal.events.')
        return false
    end

    nextRequestId = nextRequestId + 1
    local requestId = tostring(nextRequestId)
    pending[requestId] = eventName

    SendNUIMessage({
        type = 'qbadmin:medal:invoke',
        requestId = requestId,
        publicKey = key,
        timeoutMs = tonumber(Config.medal.requestTimeoutMs) or 5000,
        body = {
            eventId = eventId,
            eventName = eventName,
            triggerActions = { 'SaveClip' },
            clipOptions = {
                duration = duration,
                captureDelayMs = captureDelayMs,
            },
        },
    })

    SetTimeout((tonumber(Config.medal.requestTimeoutMs) or 5000) + 1000, function()
        if not pending[requestId] then return end
        pending[requestId] = nil
        notify('error', 'Medal did not respond. Make sure the Medal recorder is running.')
    end)
    return true
end

RegisterNUICallback('qbadmin:medal:result', function(data, cb)
    cb({ ok = true })

    local requestId = type(data) == 'table' and tostring(data.requestId or '') or ''
    local eventName = pending[requestId]
    if not eventName then return end
    pending[requestId] = nil

    local status = tonumber(data.status) or 0
    if data.ok == true and status == 200 then
        notify('success', ('Medal accepted “%s”. The clip will appear after it finishes processing.'):format(eventName))
    elseif status == 401 then
        notify('error', 'Medal rejected the public key. Check qbadmin_medal_public_key.')
    elseif status == 400 then
        notify('error', 'Medal rejected the clip event. Check its registered ID and clip options.')
    else
        notify('error', 'Could not reach Medal. Make sure the recorder is installed and running.')
    end
end)
