-- playerConnecting deferral -- the enforcement half of the ban system. The
-- `bans` table (qbcore/sql/002_identifiers.sql) already exists but nothing in
-- qbcore checks it on connect (confirmed by search); this is genuinely new
-- ground, and qbcore has no playerConnecting hook of its own to order against.

AddEventHandler('playerConnecting', function(_name, _setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(0) -- required before the first deferrals.update() call, per FiveM's deferrals contract

    deferrals.update('Checking ban status...')

    local ids = exports.qbcore:getIdentifiers(src)
    -- ip matching is inherently less reliable this early in the handshake than
    -- license/discord (see docs.md); still included since a repeat offender's
    -- IP is still worth catching even if occasionally missed here.
    local ban = QB.sql.single(
        'SELECT `id`, `reason`, `expire` FROM `bans` '
        .. 'WHERE (`license` = ? OR `discord` = ? OR `ip` = ?) AND (`expire` IS NULL OR `expire` > ?) '
        .. 'ORDER BY `id` DESC LIMIT 1',
        { ids.license, ids.discord, ids.ip, os.time() }
    )

    if ban then
        deferrals.done(('You are banned.\nReason: %s\nExpires: %s'):format(
            ban.reason or 'No reason given',
            ban.expire and os.date('%Y-%m-%d %H:%M', ban.expire) or 'Never'
        ))
        return
    end

    deferrals.done()
end)
