-- Single flat Config table, per-module sub-tables, a trailing comment on every
-- value -- matches qblib/qbcore's config.lua convention.

Config = Config or {}

Config.permissions = {
    -- Ranked lowest to highest. 'user' is always rank 1 and can never run a
    -- gated command; qbadmin never grants anything at 'user'.
    ranks = { user = 1, mod = 2, admin = 3, god = 4 },
    -- Must match qbcore's own Config.identity.primaryIdentifier (default
    -- 'license', not readable from this resource's VM). exports.qbcore's own
    -- addPermission reads qbcore's copy directly when GRANTING; qbadmin's
    -- /revokepermission has to mirror the same identifier kind by hand since
    -- there is no removePermission export to delegate to (see docs.md).
    principalIdentifier = 'license',
}

Config.ban = {
    durationUnits = { m = 60, h = 3600, d = 86400, w = 604800 }, -- seconds per duration-string unit ('30m', '2d', ...)
    durationWords = { perm = true, permanent = true },           -- words treated as a permanent ban (expire = NULL)
}

Config.teleport = {
    fadeTime = 500,        -- ms for the screen fade out/in around a teleport
    collisionTimeout = 2000, -- ms to wait on RequestCollisionAtCoord before teleporting anyway
    tpbackHistory = 1,      -- how many previous positions /tpback can undo (1 = last position only)
    groundSnapHeight = 200.0, -- how far above a ground-snapped destination (e.g. /tpm) to land before probing for ground
    groundSnapAttempts = 10,  -- GetGroundZFor_3dCoord retries once collision has loaded around the ground-snap landing spot
}

Config.noclip = {
    baseSpeed = 2.0,       -- metres/tick at normal speed
    fastMultiplier = 3.0,  -- speed multiplier while sprint is held
}

Config.world = {
    weatherTypes = {
        'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'RAIN', 'CLEARING',
        'THUNDER', 'SMOG', 'FOGGY', 'XMAS', 'SNOWLIGHT', 'BLIZZARD',
    },
    syncOnPlayerLoaded = true, -- re-apply the current server-held weather/time to a client on join
}

Config.vehicle = {
    -- /veh spawns this far in front of the target so it doesn't land on top of them.
    spawnOffset = 3.0,
}

Config.audit = {
    pageSize = 15, -- rows per page for /adminlog and the NUI audit log viewer
}

Config.keybind = {
    -- Opens the admin menu. The bound command only forwards to the SERVER's
    -- /admin (see client/menu.lua) -- binding a key grants nothing on its own,
    -- since /admin still runs its own 'mod' permission check server-side.
    -- Players rebind this freely in Settings > Key Bindings > FiveM; the value
    -- here is only the default. Empty string = registered but unbound.
    command = 'adminmenu',
    label = 'Open the admin menu (qbadmin)',
    defaultKey = 'F7', -- HOME/F6 are qblib-playground's palette, TAB is qbinventory
}
