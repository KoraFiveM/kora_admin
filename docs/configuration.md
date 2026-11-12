---
title: Configuration
sidebar_position: 8
---

# Configuration

Shared settings live in `config.lua`; Discord role mappings and Discord settings live in the server-only `server/config.lua` and are never sent to clients.

`config.lua` registers itself with kora_lib (`Kora.config.adopt`), so its values can also be edited in-game with `/config` (or Server, Configuration in `/admin`). The editor shows each setting's saved and running values and whether it applies now or needs a restart, and writes overrides to the resource's `config.local.lua` (ignored by Git) instead of rewriting `config.lua`. Sensitive values, convars and executable values are not exposed. See kora_lib's documentation for schemas, scopes and live handlers: [kora_lib](https://github.com/KoraFiveM/kora_lib).

Several values are read once when the resource starts (command permissions such as `developer.menuLevel`, `configEditor.level`, `reports.staffLevel`, `temporaryGrant.managerRole`, whether `/reports` is registered, the `/admin` key mapping, `world.syncOnPlayerLoaded`). Changing them needs a resource restart.

## Permissions

`Config.permissions`

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `roles` | table | see below | Every role: `label`, unique numeric `rank`, optional `grantable` (default true) and `aliases` (legacy ACE names). `user` is required. |
| `gates` | table | `{ support = 'support', mod = 'moderator', admin = 'admin', god = 'owner' }` | Internal permission bands used by command files, mapped to roles. |
| `principalIdentifier` | string | `'license'` | Identifier kind used by `/revokepermission`; must match kora_core's `Config.identity.primaryIdentifier`. |
| `temporaryGrant.managerRole` | string | `'admin'` | Role allowed to grant and revoke temporary access. |
| `temporaryGrant.maxRole` | string | `'admin'` | Highest role that can be granted temporarily. |
| `temporaryGrant.defaultMinutes` | number | `60` | Default duration in the menu. |
| `temporaryGrant.minMinutes` | number | `1` | Minimum duration. |
| `temporaryGrant.maxMinutes` | number | `1440` | Maximum duration. |

Default roles:

```lua
roles = {
    user = { label = 'User', rank = 0, grantable = false },
    support = { label = 'Support', rank = 10 },
    moderator = { label = 'Moderator', rank = 20, aliases = { 'mod' } },
    admin = { label = 'Admin', rank = 30 },
    owner = { label = 'Owner', rank = 40, grantable = false, aliases = { 'god' } },
},
```

## Discord and permission mode (server-only)

Declared in `server/config.lua` and registered with server scope; all are live.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `permissions.mode` | enum | `'ace_discord'` | `ace_discord` (ACE plus Discord, compatible) or `discord` (Discord roles only; ignores ACE and temporary grants). |
| `permissions.discordRoles` | map of string lists | `{}` | Tier to Discord role IDs or names. |
| `discord.enabled` | boolean | `false` | Enable Discord administration. |
| `discord.applicationId` | string | `''` | Discord application ID. |
| `discord.guildId` | string | `''` | Discord server ID; falls back to the `kora_lib_discord_guild_id` convar when blank. |
| `discord.publicKey` | string | `''` | Application public key used to verify interactions. |
| `discord.channels` | string list | `{}` | Staff channel IDs; an empty list denies every staff action. |
| `discord.disabledCommands` | string list | `{}` | kora_admin commands blocked from Discord. |
| `discord.confirmCommands` | string list | `ban`, `unban`, `kick`, `clearinventory`, `restartresource`, `setpermission`, `revokepermission`, `granttempaccess`, `revoketempaccess` | Commands that need `confirm:true`. |
| `discord.cooldownSeconds` | integer | `3` | Seconds between commands per Discord user (1-60). |
| `discord.restartEnabled` | boolean | `false` | Allow full server restarts through txAdmin. |
| `discord.restartDelaySeconds` | integer | `60` | Restart countdown (30-3600). |
| `discord.restartRole` | string | `'owner'` | Minimum tier for restarts; must be a configured role. |

See [Discord administration](./features/discord.md).

## Heal and revive

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.heal.restoreNeeds` | boolean | `true` | `/heal` also sets hunger and thirst to 100. |
| `Config.HealRestoreNeeds` | boolean | `true` | `/revive` also sets hunger and thirst to 100. |

## Announcements

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.announcement.sound.enabled` | boolean | `true` | Play a frontend sound on every client with `/announce`. |
| `Config.announcement.sound.name` | string | `'CHALLENGE_UNLOCKED'` | `PlaySoundFrontend` sound name. |
| `Config.announcement.sound.set` | string | `'HUD_AWARDS'` | Sound set. |

## Moderation and bans

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.moderation.blockSelfTarget` | boolean | `true` | `/warn`, `/kick` and `/ban` refuse to target yourself. |
| `Config.ban.durationUnits` | table | `{ m = 60, h = 3600, d = 86400, w = 604800 }` | Seconds per duration unit. |
| `Config.ban.durationWords` | table | `{ perm = true, permanent = true }` | Words meaning a permanent ban. |

## Teleport

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.teleport.fadeTime` | number (ms) | `500` | Screen fade around a teleport. |
| `Config.teleport.collisionTimeout` | number (ms) | `2000` | Maximum wait for world collision. |
| `Config.teleport.tpbackHistory` | number | `1` | Documented as the `/tpback` history depth; the client keeps one slot regardless. |
| `Config.teleport.waypointLaunchHeight` | number | `100.0` | Altitude every teleport lands at first. |
| `Config.teleport.groundZAttempts` | number | `5` | Ground probes for `/tpm`. |
| `Config.teleport.groundZRetryDelay` | number (ms) | `500` | Delay between ground probes. |

## Noclip

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.noclip.baseSpeed` | number | `2.0` | Metres per frame at normal speed. |
| `Config.noclip.fastMultiplier` | number | `3.0` | Multiplier while Shift is held. |
| `Config.noclip.slowMultiplier` | number | `0.35` | Multiplier while Alt is held. |
| `Config.noclip.adMode` | enum | `'strafe'` | `strafe` (A/D slide sideways) or `turn` (A/D yaw the view). Live. |
| `Config.noclip.turnSpeed` | number | `2.0` | Degrees per frame in `turn` mode (0.1-10). Live. |

## World

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.world.weatherTypes` | string list | `EXTRASUNNY`, `CLEAR`, `CLOUDS`, `OVERCAST`, `RAIN`, `CLEARING`, `THUNDER`, `SMOG`, `FOGGY`, `XMAS`, `SNOWLIGHT`, `BLIZZARD` | Accepted `/weather` values when kora_weathersync is not running. |
| `Config.world.syncOnPlayerLoaded` | boolean | `true` | Re-apply kora_admin's last weather/time to joining players (only without kora_weathersync). |
| `Config.world.timePresets` | list | morning 08:00, noon 12:00, night 21:00 | Ordered `/time` preset words and menu buttons. |

Each preset has `id` (the word typed after `/time`), `label`, `hour` and optional `minute` (default 0). Values are range-checked when used:

```lua
timePresets = {
    { id = 'morning', label = 'Morning', hour = 8, minute = 0 },
    { id = 'noon', label = 'Noon', hour = 12, minute = 0 },
    { id = 'night', label = 'Night', hour = 21, minute = 0 },
},
```

## Vehicles and entities

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.vehicle.spawnOffset` | number | `3.0` | Metres in front of the recipient for `/car` and `/veh`. |
| `Config.vehicle.notifyTarget` | boolean | `true` | Notify the recipient of `/veh`. |
| `Config.dv.nearestRadius` | number | `5.0` | On foot, `/dv` deletes the nearest vehicle within this radius; `0` = only the vehicle you are in. |
| `Config.dv.maxRadius` | number | `50.0` | Cap for `/dv <radius>`. |
| `Config.entity.spawnOffset` | number | `2.0` | Metres in front of the recipient for `/entity` and `/entityfor`. |

## Developer tools

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.developer.menuLevel` | string | `'admin'` | Tier for the Developer Tools workspace and `/entitypicker`, `/devplacement`, `/devzone`. |
| `Config.developer.requireDevMode` | boolean | `false` | Require kora_core development mode for those tools. |
| `Config.entityPicker.maxDistance` | number | `50.0` | Raycast distance. |
| `Config.entityPicker.copyKey` | string | `'H'` | Default key to open the model-name dialog. |
| `Config.entityPicker.closeKey` | string | `'X'` | Default key to close the picker. |
| `Config.entityPicker.crosshair` | boolean | `true` | Draw a centre dot while the picker runs. |

## Spectate

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.spectate.stopKey` | string | `'BACK'` | Default key to stop spectating; empty = unbound. |
| `Config.spectate.showHint` | boolean | `true` | Show a "Stop spectating" hint. |

## Medal

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.medal.publicKey` | string | `''` | Medal public key (safe to distribute). Prefer the convar. |
| `Config.medal.publicKeyConvar` | string | `'kora_admin_medal_public_key'` | Replicated convar that overrides `publicKey` when set. |
| `Config.medal.menuLevel` | string | `'admin'` | Tier that sees Medal Clips. |
| `Config.medal.requestTimeoutMs` | number | `5000` | Request timeout. |
| `Config.medal.events` | list | `{ { id = '1', name = 'Admin Clip', duration = 30, captureDelayMs = 0 } }` | One button per event; must match the events registered with Medal. |

## Audit log and configuration editor

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.audit.pageSize` | number | `15` | Rows per page for `/adminlog` and the Audit Log tab query. |
| `Config.configEditor.level` | string | `'admin'` | Tier for `/config`, the Configuration tab and the `canEditConfig` export. Set `'owner'` to keep it above normal administration. |

## Reports

`Config.reports`

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `types` | list | `player`, `bug`, `exploit`, `gameplay`, `question`, `other` | Report categories (`id`, `label`, `description`). Keep ids stable once used. |
| `staffLevel` | string | `'support'` | Tier that sees, claims, replies to and closes reports. |
| `pageSize` | number | `20` | Reports per page. |
| `cooldownSeconds` | number | `30` | Minimum delay between new reports per player. |
| `command.enabled` | boolean | `true` | Register `/reports`. |
| `command.ui` | boolean | `true` | Staff `/reports` opens the Reports app; `false` prints a chat list. |
| `maxMessageLength` | number | `1000` | Maximum length of reports, replies and resolution notes. |
| `liveUpdates` | boolean | `true` | Push report changes to every staff member with the screen open; `false` only to the actor. |
| `chat.enabled` | boolean | `true` | Live two-way chat; `false` restores the timeline and Reply form. |
| `chat.playerUi` | boolean | `true` | Players' `/reports` opens My Reports. |
| `chat.maxLength` | number | `500` | Per chat message; longer messages are refused (must not exceed `maxMessageLength`). |
| `chat.rateLimit` | table | `{ messages = 5, seconds = 15 }` | Sliding-window limit per sender across all reports. |
| `chat.showStaffNames` | boolean | `true` | `false` shows "Staff" to players. |
| `chat.notifyStaff` | string | `'all'` | `'all'` or `'claimer'` (only the claiming staff member is notified of reporter messages). |
| `chat.fixedLayout` | boolean | `true` | Fixed, non-scrolling chat screens. |

## Menu

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.roles.hiddenJobs` | string list | `{}` | Jobs left out of the Set Job list (still usable with `/setjob`). |
| `Config.roles.hideDuplicateLabels` | boolean | `true` | Show one job per label (first in registry order wins). |
| `Config.menu.playerProfileHeaderBack` | boolean | `true` | Header back arrow on the selected-player tabs. |
| `Config.keybind.label` | string | `'Open the admin menu (kora_admin)'` | Key-binding description. |
| `Config.keybind.defaultKey` | string | `'F7'` | Default key for `/admin`; empty = registered but unbound. |

## Convars

| Convar | Kind | Used for |
| --- | --- | --- |
| `kora_admin_medal_public_key` | `setr` | Medal public key. |
| `kora_lib_discord_bot_token` | `set` | Discord bot token (kora_lib). |
| `kora_lib_discord_guild_id` | `set` | Discord guild when `discord.guildId` is blank. |
| `kora_admin_txadmin_url` | `set` | txAdmin origin, default `http://127.0.0.1:40120`. |
| `kora_admin_txadmin_username` | `set` | txAdmin account for restarts. |
| `kora_admin_txadmin_password` | `set` | txAdmin password. |
