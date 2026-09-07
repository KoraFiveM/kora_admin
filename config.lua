-- Single flat Config table, per-module sub-tables, a trailing comment on every
-- value -- matches qblib/qbcore's config.lua convention.

Config = Config or {}

Config.permissions = {
    -- Every role used by qbadmin. Add roles here (with a unique rank) to make
    -- them available to ACE/Discord and the temporary-access picker. `user`
    -- is the non-staff floor and can never be granted.
    roles = {
        user = { label = 'User', rank = 0, grantable = false },
        support = { label = 'Support', rank = 10 },
        moderator = { label = 'Moderator', rank = 20, aliases = { 'mod' } },
        admin = { label = 'Admin', rank = 30 },
        owner = { label = 'Owner', rank = 40, grantable = false, aliases = { 'god' } },
        -- Example: senior_moderator = { label = 'Senior Moderator', rank = 25 },
    },
    -- Internal feature bands. Leave these defaults alone for the standard
    -- roles, or point a band at one of your added roles to tune access without
    -- editing command files. `mod`/`god` retain their old names internally so
    -- existing command definitions and integrations remain compatible.
    gates = {
        support = 'support',
        mod = 'moderator',
        admin = 'admin',
        god = 'owner',
    },
    -- Must match qbcore's own Config.identity.primaryIdentifier (default
    -- 'license', not readable from this resource's VM). exports.qbcore's own
    -- addPermission reads qbcore's copy directly when GRANTING; qbadmin's
    -- /revokepermission has to mirror the same identifier kind by hand since
    -- there is no removePermission export to delegate to (see docs.md).
    principalIdentifier = 'license',
    -- Temporary access exists only in qbadmin memory: it survives reconnects
    -- during the timer but is intentionally cleared by a qbadmin/server
    -- restart. The manager may grant any grantable role at or below maxRole.
    temporaryGrant = {
        managerRole = 'admin',
        maxRole = 'admin',
        defaultMinutes = 60,
        minMinutes = 1,
        maxMinutes = 1440,
    },
}

Config.ban = {
    durationUnits = { m = 60, h = 3600, d = 86400, w = 604800 }, -- seconds per duration-string unit ('30m', '2d', ...)
    durationWords = { perm = true, permanent = true },           -- words treated as a permanent ban (expire = NULL)
}

-- Matches txAdmin's own teleport algorithm (resource/menu/client/
-- cl_main_page.lua's handleTpNormally + cl_functions.lua's FindZForCoords) --
-- see client/teleport.lua for the full port. Defaults below are txAdmin's
-- own (100.0 launch height, 5 ground attempts, 500ms apart) except
-- collisionTimeout, which upstream doesn't have at all (its own wait loop
-- has no timeout) -- kept here as a safety net so a destination that never
-- resolves collision can't leave the screen faded out forever.
Config.teleport = {
    fadeTime = 500,             -- ms for the screen fade out/in around a teleport
    collisionTimeout = 2000,    -- ms to wait on IsEntityWaitingForWorldCollision before teleporting anyway
    tpbackHistory = 1,          -- how many previous positions /tpback can undo (1 = last position only)
    waypointLaunchHeight = 100.0, -- fixed altitude every teleport lands at first, before collision has streamed in
    groundZAttempts = 5,        -- findGroundZ (ground-snapped destinations only, e.g. /tpm) retries this many times
    groundZRetryDelay = 500,    -- ms between groundZAttempts retries
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
    -- One-click clock presets. These are the words `/time` accepts in place of
    -- an hour, and the buttons the admin menu's time selector offers, so both
    -- entry points mean the same thing -- change an entry's hour here to change
    -- what "night" means on this server. An ordered list rather than a keyed
    -- table so the buttons cannot shuffle between openings the way pairs()
    -- order would. `minute` is optional and treated as 0 when omitted; every
    -- value still goes through the same 0-23/0-59 whole-number check a typed
    -- hour does, so a mistyped entry is refused at use time rather than
    -- reaching the clock.
    timePresets = {
        { id = 'morning', label = 'Morning', hour = 8, minute = 0 },
        { id = 'noon', label = 'Noon', hour = 12, minute = 0 },
        { id = 'night', label = 'Night', hour = 21, minute = 0 },
    },
}

Config.vehicle = {
    -- /veh spawns this far in front of the target so it doesn't land on top of them.
    spawnOffset = 3.0,
}

Config.entity = {
    -- /entity spawns this far in front of the target. Entity spawns are
    -- intentionally local, static qblib entities for safe admin testing.
    spawnOffset = 2.0,
}

Config.developer = {
    -- Minimum qbadmin permission tier allowed to open the Developer submenu
    -- and run its creator commands. The commands still re-check this on the
    -- server; the client-side menu gate is only presentation.
    menuLevel = 'admin',
    -- When enabled, the caller must turn on qbcore's per-player development
    -- mode before launching qblib's placement or zone creators.
    requireDevMode = true,
}

Config.medal = {
    -- Medal's public key is intentionally safe to distribute to clients. Set
    -- it here, or preferably add `setr qbadmin_medal_public_key "..."` to
    -- server.cfg so resource updates do not overwrite it. Generate the key
    -- and register the matching event IDs at https://medal.tv/developer/auto-clipping.
    publicKey = '',
    publicKeyConvar = 'qbadmin_medal_public_key',
    menuLevel = 'admin', -- minimum qbadmin permission tier that sees Medal Clips
    requestTimeoutMs = 5000, -- fail promptly when Medal is closed/not installed
    events = {
        -- IDs, names, durations, and delays must match the events submitted to
        -- Medal. Add more entries to expose more clip buttons in the menu.
        { id = '1', name = 'Admin Clip', duration = 30, captureDelayMs = 0 },
    },
}

Config.audit = {
    pageSize = 15, -- rows per page for /adminlog and the NUI audit log viewer
}

Config.configEditor = {
    -- Editing server configuration can change gameplay, economy, and access
    -- policy. Keep it above normal administration by default; each request is
    -- checked again on the server before it reaches qblib.
    level = 'owner',
}

Config.reports = {
    -- Ordered so both the /report suggestion and admin-menu filters remain
    -- predictable. IDs are persisted; rename labels freely, but retain an ID
    -- once players have used it so old reports remain filterable.
    types = {
        { id = 'player', label = 'Player', description = 'Rule breaking, harassment, or another player issue' },
        { id = 'bug', label = 'Bug', description = 'Something on the server is broken or behaving incorrectly' },
        { id = 'exploit', label = 'Exploit / Cheating', description = 'Possible exploit abuse, cheating, or suspicious behaviour' },
        { id = 'gameplay', label = 'Gameplay', description = 'A character, job, item, vehicle, or world issue' },
        { id = 'question', label = 'Question / Help', description = 'Help understanding or using a server feature' },
        { id = 'other', label = 'Other', description = 'Anything that does not fit another report type' },
    },
    staffLevel = 'support', -- minimum role that can see, claim, reply to, and close reports
    pageSize = 20, -- reports shown per admin-menu page or /reports output
    cooldownSeconds = 30, -- minimum delay between new reports from one connected player
    maxMessageLength = 1000, -- applies to initial reports, replies, and staff resolution notes
}

Config.keybind = {
    -- Attached directly to the server-owned /admin registration. Binding a
    -- key grants nothing: qblib dispatches it through /admin's normal support gate.
    -- Players rebind this freely in Settings > Key Bindings > FiveM; the value
    -- here is only the default. Empty string = registered but unbound.
    label = 'Open the admin menu (qbadmin)',
    defaultKey = 'F7', -- HOME/F6 are qblib-playground's palette, TAB is qbinventory
}

-- Registers this resource-owned configuration with qblib without changing its public Config table.
if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end
