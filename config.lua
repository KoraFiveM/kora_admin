-- Single flat Config table, per-module sub-tables, a trailing comment on every
-- value -- matches kora_lib/qbcore's config.lua convention.

Config = Config or {}

Config.permissions = {
    -- Every role used by kora_admin. Add roles here (with a unique rank) to make
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
    -- Must match kora_core's own Config.identity.primaryIdentifier (default
    -- 'license', not readable from this resource's VM). exports.kora_core's own
    -- addPermission reads kora_core's copy directly when GRANTING; kora_admin's
    -- /revokepermission has to mirror the same identifier kind by hand since
    -- there is no removePermission export to delegate to (see docs.md).
    principalIdentifier = 'license',
    -- Temporary access exists only in kora_admin memory: it survives reconnects
    -- during the timer but is intentionally cleared by a kora_admin/server
    -- restart. The manager may grant any grantable role at or below maxRole.
    temporaryGrant = {
        managerRole = 'admin',
        maxRole = 'admin',
        defaultMinutes = 60,
        minMinutes = 1,
        maxMinutes = 1440,
    },
}

Config.heal = {
    -- /heal (and the admin-menu Heal action) also fill hunger and thirst to 100.
    -- /revive never changes needs. Set false for health-only heals.
    restoreNeeds = true,
}

-- /revive also sets hunger and thirst to 100. Set false to keep revive health-only.
Config.HealRestoreNeeds = true

Config.announcement = {
    -- /announce (and the admin-menu Send Announcement action) plays a short frontend
    -- alert for every player when the announcement arrives. Kora.notify is silent,
    -- so this is the only sound. Set enabled = false for silent announcements.
    -- name/set is any stock GTA frontend sound (PlaySoundFrontend).
    sound = { enabled = true, name = "CHALLENGE_UNLOCKED", set = "HUD_AWARDS" },
}

Config.moderation = {
    blockSelfTarget = true, -- /warn, /kick and /ban refuse when the target is the staff member running them
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
    fastMultiplier = 3.0,  -- speed multiplier while Shift is held
    slowMultiplier = 0.35, -- precision speed multiplier while Alt is held
    adMode = 'strafe',     -- what A and D do: 'strafe' slides sideways relative to the camera, 'turn' yaws the view
    turnSpeed = 2.0,       -- degrees/frame the view turns while A or D is held and adMode is 'turn'
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
    -- Notify the receiving player when an admin gives them a vehicle (/veh) or keys (/givekeys).
    notifyTarget = true,
}

Config.dv = {
    -- /dv deletes the vehicle you are in; otherwise the closest vehicle within
    -- this many metres. 0 = old behaviour (only the vehicle you are in).
    nearestRadius = 5.0,
    -- Largest radius accepted by '/dv <radius>' (deletes every vehicle in range).
    maxRadius = 50.0,
}

Config.entity = {
    -- /entity spawns this far in front of the target. Entity spawns are
    -- intentionally local, static kora_lib entities for safe admin testing.
    spawnOffset = 2.0,
}

Config.developer = {
    -- Minimum kora_admin permission tier allowed to open the Developer submenu
    -- and run its creator commands. The commands still re-check this on the
    -- server; the client-side menu gate is only presentation.
    menuLevel = 'admin',
    -- When true, the caller must turn on kora_core's per-player development
    -- mode before launching kora_lib's placement or zone creators. Default false
    -- leaves Inspect/Place/Zone tools always available.
    requireDevMode = false,
}

Config.entityPicker = {
    -- The picker is a client-local inspection tool. Starting it still goes
    -- through the permission-checked /entitypicker command below.
    maxDistance = 50.0, -- maximum camera-ray distance when inspecting an entity
    copyKey = 'H', -- default for copying the aimed entity's actual model/archetype name
    closeKey = 'X', -- default for closing the active entity picker
    crosshair = true, -- draw a centre dot while the picker is active (green when on an entity)
}

Config.spectate = {
    stopKey = 'BACK', -- default key that exits spectating (rebindable in FiveM settings; empty = unbound)
    showHint = true,   -- show an on-screen "stop spectating" key hint while spectating
}

Config.medal = {
    -- Medal's public key is intentionally safe to distribute to clients. Set
    -- it here, or preferably add `setr qbadmin_medal_public_key "..."` to
    -- server.cfg so resource updates do not overwrite it. Generate the key
    -- and register the matching event IDs at https://medal.tv/developer/auto-clipping.
    publicKey = '',
    publicKeyConvar = 'qbadmin_medal_public_key',
    menuLevel = 'admin', -- minimum kora_admin permission tier that sees Medal Clips
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
    -- checked again on the server before it reaches kora_lib.
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
    -- /reports: ui = true opens the Reports screen for staff (same queue, filters and actions
    -- as the admin menu's Reports tab); false prints a short chat list instead. Players who are
    -- not staff only ever get a chat list of their own reports. enabled = false removes /reports.
    command = { enabled = true, ui = true },
    maxMessageLength = 1000, -- applies to initial reports, replies, and staff resolution notes
    -- true: every staff member with the Reports screen open sees new reports, replies (including
    -- the reporter's own), claims and status changes as they happen. false: only the staff member
    -- who made a change sees the screen update; others see it after reopening or going Back.
    liveUpdates = true,
    -- Live two-way chat on each report. enabled = false restores the old screens exactly: the
    -- staff Conversation timeline plus Manage > Reply to Reporter, and chat-list-only /reports for
    -- players. Messages are stored with the report (admin_report_messages) either way.
    chat = {
        enabled = true,
        playerUi = true, -- /reports opens a "My Reports" chat window for players (false: chat list as before)
        maxLength = 500, -- per chat message; longer messages are refused, never cut (must be <= maxMessageLength)
        rateLimit = { messages = 5, seconds = 15 }, -- per player/staff member, across all reports
        showStaffNames = true, -- false: players see "Staff" instead of the staff member's name
        -- Who gets a toast when the reporter writes: 'all' staff (as before) or only the 'claimer'
        -- once a report is claimed (unclaimed reports still notify all staff).
        notifyStaff = 'all',
        -- true: the staff report Overview and the player's report window fit the window: only the
        -- message list scrolls (always jumping to the newest message), the message box stays at the
        -- bottom and the report details sit in the header line. false: the old scrolling page.
        fixedLayout = true,
    },
}

Config.roles = {
    -- Job names left out of the admin Set Job list. /setjob still accepts them and
    -- players who already hold them keep them, e.g. { 'mechanic3' }.
    hiddenJobs = {},
    -- List one job per label, first in registry order wins. Hides placeholder
    -- duplicates such as the upstream qb-core mechanic2/mechanic3 "LS Customs".
    hideDuplicateLabels = true,
}

Config.menu = {
    -- true: a selected player's tabs show a header "<" that works like "Back to Online Players" (clears the player, hides their tabs). false: no arrow.
    playerProfileHeaderBack = true,
}

Config.keybind = {
    -- Attached directly to the server-owned /admin registration. Binding a
    -- key grants nothing: kora_lib dispatches it through /admin's normal support gate.
    -- Players rebind this freely in Settings > Key Bindings > FiveM; the value
    -- here is only the default. Empty string = registered but unbound.
    label = 'Open the admin menu (qbadmin)',
    defaultKey = 'F7', -- HOME/F6 are kora_lib-playground's palette, TAB is kora_inventory
}

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if Kora and Kora.config and Kora.config.adopt then
    Config = Kora.config.adopt(Config)
    if Kora.config.extend then
        Kora.config.extend({
            noclip = {
                adMode = Kora.config.enum('strafe', { options = {
                    { value = 'strafe', label = 'Strafe sideways' },
                    { value = 'turn', label = 'Turn the view' },
                }, live = true, label = 'Noclip A / D behaviour',
                    description = 'Strafe slides left/right relative to the camera heading; Turn rotates the view on the spot. The mouse always looks around.' }),
                turnSpeed = Kora.config.number(2.0, { live = true, min = 0.1, max = 10.0, label = 'Noclip turn speed',
                    description = 'Degrees per frame the view turns while A or D is held and A / D behaviour is Turn.' }),
            },
        })
    end
end
