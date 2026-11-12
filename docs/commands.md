---
title: Commands
sidebar_position: 4
---

# Commands

All commands below are registered with kora_lib's `Kora.commands.add` (through `Admin.addCommand`), so they get chat suggestions and `/help` text, and the console may run any of them without a permission check. Tiers refer to the default role mapping described in [Permissions](./permissions.md); "mod" means the `moderator` role.

## Conventions

- **Target argument (`id`)** - resolved by `Admin.resolveTarget`: a missing argument, an empty string or the word `me` means yourself; a number is a server id; any other text is a case-insensitive substring match against online player names (it fails if no player or more than one player matches). The target must be loaded in kora_core.
- **Toggle argument (`state`)** - `true`/`on`/`1` or `false`/`off`/`0`; omitted toggles the current state.
- **Feedback** - results are shown as kora_lib notifications; multi-line output (player lists, logs, reports) is printed to chat with the `[Admin]` prefix.
- **Audited** - "yes" means the command writes a row to `admin_logs` with that action name. See [Database](./database.md).

## Menu and information

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/admin` | - | support | Opens the admin menu. Key mapping: `Config.keybind.defaultKey` (default `F7`), rebindable in FiveM key bindings. A denied player gets a message explaining the required and held roles. | no |
| `/players` | `[search]` | support | Lists online players in chat: id, name, job label, ping. | no |
| `/permission` | `[id]` | mod | Shows a player's resolved tier. Checking another player requires admin. | no |
| `/serverinfo` | - | mod | Prints online player count, uptime in minutes and number of resources. | no |
| `/config` | - | `Config.configEditor.level` (admin) | Opens kora_lib's configuration app (`kora_lib:client:configOpened`) on kora_admin. The editor lists every resource that registered a kora_lib config schema and shows whether a change applies now or needs a restart. | no |

## Moderation

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/warn` | `<id> <reason>` | mod | Sends the player a warning notification and records it. Refuses self-targeting when `Config.moderation.blockSelfTarget` is on. | `warn` |
| `/warnings` | `<id>` | mod | Prints the player's warning history (first audit-log page of `warn` entries for their citizen id). | no |
| `/kick` | `[id] [reason]` | mod | Drops the player (default reason "Kicked by an administrator"). Self-kick is refused with `blockSelfTarget`. | `kick` |
| `/ban` | `<target> <duration> [reason]` | admin | Persistent ban, online or offline. `target` is an online server id, a citizen id, or a character-name search. `duration` is `<n>m`, `<n>h`, `<n>d`, `<n>w` or `perm`/`permanent`. Does not accept `me`. See [Moderation and bans](./features/moderation-and-bans.md). | `ban` |
| `/unban` | `<license or ban id>` | admin | Ends every matching active ban by setting its `expire` to now (history is kept). | `unban` |
| `/freeze` | `[id] [state]` | mod | Freezes or unfreezes the player's ped. | `freeze` |
| `/kill` | `[id]` | mod | Sets the player's health to 0. | `kill` |
| `/heal` | `[id]` | mod | Restores the ped to max health; with `Config.heal.restoreNeeds` also sets hunger and thirst to 100. | `heal` |
| `/revive` | `[id]` | mod | Clears `isdead`/`inlaststand`, resurrects the ped, fires the ambulance revive events and, if kora_ambulance runs, its `fullRevive`. With `Config.HealRestoreNeeds` (default `true`) also sets hunger and thirst to 100. | `revive` |
| `/god` | `[id] [state]` | mod (admin for others) | Toggles invincibility. | `god` |
| `/invisible` | `[id] [state]` | mod (admin for others) | Toggles visibility of the ped. | `invisible` |
| `/devmode` | `[id] [state]` | mod (admin for others) | Toggles kora_core development mode through its `setDevMode` export (god mode, paused passive needs, fast walk - as implemented by kora_core). | `devmode` |
| `/sethunger` | `<id> <0-100>` | admin | Sets the hunger metadata. | `sethunger` |
| `/setthirst` | `<id> <0-100>` | admin | Sets the thirst metadata. | `setthirst` |

## Teleport, noclip and spectate

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/goto` | `<id>` | mod | Teleports you to the player. | `goto` |
| `/bring` | `<id>` | mod | Teleports the player to you. | `bring` |
| `/sendback` | `<id>` | mod | Returns the player to where they were before their last kora_admin teleport. | `sendback` |
| `/tpm` | - | mod | Teleports to your waypoint with ground detection. | no |
| `/tpcoords` | `<coordinates>` | mod | Accepts `x y z`, `x, y, z`, an optional fourth heading value, or `vec3(...)`, `vector3(...)`, `vec4(...)`, `vector4(...)` literals. | no |
| `/tpback` | - | mod | Returns you to your position before your last teleport (one slot). | no |
| `/spectate` | `[id]` | mod | Spectates the player; without an id (or on the same player again) stops. | `spectate` |
| `/noclip` | - | admin | Toggles free-fly noclip. | `noclip` |

Details: [Teleport, noclip and spectate](./features/teleport-noclip-spectate.md).

## Self and utility

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/aduty` | - | mod | Toggles the `adminDuty` metadata flag on your character. | no |
| `/coords` | - | mod | Copies `vector3(x, y, z)` of your position to the clipboard and prints it to F8. | no |
| `/vec4` | - | mod | Copies `vector4(x, y, z, heading)` to the clipboard and prints it to F8. | no |
| `/health` | `[percentage]` | mod | Sets your own health as 0-100 percent of the ped's real range (100 is GTA's death floor, 100% is the ped's max). A non-zero value while dead or downed revives first. Default 100. | no |
| `/armor` | `[value]` | mod | Sets your own armour (default 100). | no |
| `/selfrevive` | - | mod | Revives yourself, clearing the downed metadata and ambulance state. Named differently from `/revive` so another resource's `/revive` cannot shadow it. | no |

## Economy and inventory

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/givemoney` | `<id> <account> <amount> [reason]` | admin | kora_core `addMoney`. Default reason `admin:givemoney`. | `givemoney` |
| `/removemoney` | `<id> <account> <amount> [reason]` | admin | kora_core `removeMoney`. | `removemoney` |
| `/setmoney` | `<id> <account> <amount> [reason]` | admin | kora_core `setMoney`. The amount must be positive. | `setmoney` |
| `/giveitem` | `<id> <item> [amount] [infoJson]` | admin | kora_core `addItem`; amount defaults to 1; the optional fourth argument must be a JSON object (one word, no spaces) used as item metadata. | `giveitem` |
| `/removeitem` | `<id> <item> [amount]` | admin | kora_core `removeItem`. | `removeitem` |
| `/clearinventory` | `<id>` | admin | kora_core `clearInventory`. | `clearinventory` |

Account names are validated by kora_core (its configured money types); kora_admin surfaces kora_core's error.

## Jobs, gangs and duty

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/setjob` | `<id> <job> [grade]` | admin | kora_core `setJob`; kora_core validates the job and grade. | `setjob` |
| `/setgang` | `<id> <gang> [grade]` | admin | kora_core `setGang`. | `setgang` |
| `/setduty` | `[id] [state]` | mod | kora_core `setJobDuty`; toggles when no state is given. | `setduty` |

`Config.roles.hiddenJobs` and `hideDuplicateLabels` only trim the menu's job list; hidden jobs still work with `/setjob`.

## Appearance (kora_clothing)

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/clothingmenu` | `<id>` | admin | Opens a free, one-use kora_clothing clothing session for the player via `exports.kora_clothing:OpenAdminSession(target, 'clothing')`. | `clothingmenu` |
| `/barbermenu` | `<id>` | admin | Same with the `barber` service. | `barbermenu` |
| `/tattoomenu` | `<id>` | admin | Same with the `tattoo` service. | `tattoomenu` |

These fail with "kora_clothing is not running" when kora_clothing is not started. The session authorisation is created server-to-server; clients cannot mint it.

## Vehicles

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/car` | `<model>` | admin | Spawns the vehicle server-side `Config.vehicle.spawnOffset` metres in front of you, in your routing bucket, grants you keys and warps you in. | `car` |
| `/veh` | `<id> <model>` | admin | Same for another player; notifies them when `Config.vehicle.notifyTarget` is on. | `veh` |
| `/givevehicle` | `<id> <model> <plate>` | admin | Adds a persistent personal vehicle to the online player's garage through kora_core `createVehicle`. Plates are 1-15 letters or digits (upper-cased). | `givevehicle` |
| `/dv` | `[radius]` | admin | Deletes the vehicle you are in; on foot, the nearest vehicle within `Config.dv.nearestRadius`; with a radius, every vehicle in range (capped at `Config.dv.maxRadius`). Vehicles with another player inside are skipped. With `nearestRadius = 0` only your current vehicle is deleted. | `dv` |
| `/fix` | - | mod | Repairs the vehicle you are in (body, engine, deformation). | `fix` |

Models must match `^[A-Za-z0-9_]+$` and be either in kora_core's shared vehicle list or a vehicle model known to `Kora.lookup.model` (streamed addon vehicles included). Keys are granted with `exports.kora_vehiclekeys:giveKeys(target, plate, true)` (administrative override); if that fails the vehicle is deleted. `/givekeys` belongs to kora_vehiclekeys, not kora_admin.

## Entities

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/entity` | `<model>` | admin | Spawns a static, local (non-networked) ped or prop `Config.entity.spawnOffset` metres in front of you using `Kora.entities.create` with the `static` preset. | `entity` |
| `/entityfor` | `<id> <model>` | admin | Same, spawned on the target player's client. | `entityfor` |
| `/deleteentity` | - | admin | Deletes your client's most recent admin-spawned entity. | `deleteentity` |

Vehicle models are refused ("use /car or /veh for vehicle models"). Entities are visible only to the client they were spawned for and are cleaned up by kora_lib when the resource stops.

## Developer tools

Tier: `Config.developer.menuLevel` (default admin). With `Config.developer.requireDevMode = true` the caller must also have kora_core development mode enabled.

| Command | Arguments | Effect | Audited |
| --- | --- | --- | --- |
| `/entitypicker` | - | Starts the entity picker HUD. | `entitypicker` |
| `/devplacement` | `<model or hash>` | Starts `Kora.placement.start(model)` for any ped, vehicle or object. | `devplacement` |
| `/devzone` | `<box or sphere or poly>` | Starts `Kora.zones.startCreator(type)`. | `devzone` |

Details: [Developer tools](./features/developer-tools.md).

## World and server

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/announce` | `<message>` | admin | Notifies every player ("Announcement", 8 s) and plays `Config.announcement.sound` when enabled. | `announce` |
| `/weather` | `<type>` | admin | If kora_weathersync is started, calls its `setWeather`; otherwise validates against `Config.world.weatherTypes` and applies it to all clients. | `weather` |
| `/time` | `<hour or preset> [minute]` | admin | Hour 0-23 with optional minute 0-59 (default 0), or a preset id from `Config.world.timePresets` (`morning`, `noon`, `night`). Out-of-range values are refused, never clamped. Uses kora_weathersync's `setTime` when it runs. | `time` |
| `/adminlog` | `[action] [target] [page]` | admin | Prints a page (`Config.audit.pageSize`) of the audit log, newest first. `target` matches citizen id, license or name. Times are UTC. | no |
| `/restartresource` | `<name>` | owner | Runs `restart <name>` for an existing resource. | `restartresource` |

Without kora_weathersync, the last weather and time set by kora_admin are re-applied to joining players when `Config.world.syncOnPlayerLoaded` is on.

## Access management

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/setpermission` | `<id> <role>` | owner | Runtime `add_principal` via kora_core `addPermission`. | `setpermission` |
| `/revokepermission` | `<id> <role>` | owner | Runtime `remove_principal` for `kora_core.<role>`. | `revokepermission` |
| `/granttempaccess` | `<id> <role> <minutes>` | `temporaryGrant.managerRole` (admin) | Memory-only temporary tier. | `granttempaccess` |
| `/revoketempaccess` | `<id> <role>` | `temporaryGrant.managerRole` (admin) | Removes a temporary grant early. | `revoketempaccess` |

All four are disabled in Discord-only permission mode. See [Permissions](./permissions.md).

## Player reports

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/report` | `<type> <message>` | everyone | Creates a report. Types: `player`, `bug`, `exploit`, `gameplay`, `question`, `other` (from `Config.reports.types`). | no |
| `/reportstatus` | `<id>` | reporter or staff | Prints the report and its conversation in chat. | no |
| `/reportreply` | `<id> <message>` | reporter or staff | Adds a message to an open report. | staff replies: `report_reply` |
| `/reports` | `[status] [type] [page]` | everyone | Staff: opens the Player Reports app (or a chat list with `command.ui = false`). Players: opens My Reports (first argument may be a report id) or a chat list of their own reports. Only registered when `Config.reports.command.enabled` is on. | no |
| `/reportclaim` | `<id>` | `Config.reports.staffLevel` (support) | Claims or takes over a report. | `report_claim` |
| `/reportresolve` | `<id> [note]` | staffLevel | Marks the report resolved. | `report_resolved` |
| `/reportdismiss` | `<id> [note]` | staffLevel | Marks the report dismissed. | `report_dismissed` |
| `/reportreopen` | `<id> [note]` | staffLevel | Reopens a closed report and clears its claim. | `report_open` |

Details: [Player reports](./features/reports.md).

## Console-only commands

These are registered with `RegisterCommand` and do nothing unless run from the server console or RCON.

| Command | Arguments | Effect |
| --- | --- | --- |
| `kora_admin_whyperms` | `<server id>` | Prints the player's identifiers, the ACE checks kora_lib performs and the resolved level. |
| `kora_broadcast` | `<message>` | Shows a "Server" warning notification (60 s, first 200 characters) to every player. Intended for external restart warnings. |

## Key mappings

| Mapping | Default key | Action |
| --- | --- | --- |
| `/admin` | `F7` (`Config.keybind.defaultKey`) | Opens the menu through the normal `/admin` permission check. |
| `kora_admin_spectate_stop` | `BACK` (`Config.spectate.stopKey`) | Stops spectating. |
| `kora_admin_entitypicker_copy` | `H` (`Config.entityPicker.copyKey`) | Opens the model-name dialog for the aimed entity. |
| `kora_admin_entitypicker_close` | `X` (`Config.entityPicker.closeKey`) | Closes the entity picker. |

All key mappings can be rebound by each player in Settings, Key Bindings, FiveM.
