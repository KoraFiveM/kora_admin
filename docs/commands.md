---
title: "Commands"
sidebar_position: 4
---


# Commands

Every command below is registered through `Admin.addCommand`, which wraps `Kora.commands.add` with a permission gate (`checkPermission = Admin.checkLevel`, `resource = 'kora_admin'`) and, for access-management commands, the Discord-mode lockout described in How To Use. "Access" below names the internal gate (see Permissions); the gate’s label can be re-pointed at a different role in `config.lua` without changing these commands. Most commands also accept the target "me" or an omitted id where noted in source (`Admin.resolveTarget`); argument parsing errors return a chat-visible failure message rather than throwing.

## Built-in commands

### `/admin`

Opens the NUI admin menu, built entirely from the same commands documented here.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | support gate. |

**Example**

```text
/admin
```

**Result**

Opens the menu, or (if denied) an error naming the required gate, your resolved role/rank, and every gate you do pass.

### `/players [search]`

Lists online players with their job label and ping.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | search? — case-insensitive substring filter on player name. |
| Access | support gate. |

**Example**

```text
/players john
```

**Result**

Chat lines `#<id>  <name>  [<job label>]  <ping>ms`, or "no players matched".

### `/sethunger <id> <value>`

Sets a player's hunger metadata (0-100).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, value (0-100). |
| Access | admin gate. |

**Example**

```text
/sethunger 5 100
```

**Result**

Sets the value via exports.kora_core:setMetaData and logs it.

### `/setthirst <id> <value>`

Sets a player's thirst metadata (0-100).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, value (0-100). |
| Access | admin gate. |

**Example**

```text
/setthirst 5 100
```

**Result**

Same as /sethunger for thirst.

### `/warn <id> <reason>`

Sends the target a warning notification and records it.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, reason (required, joined from remaining args). |
| Access | mod gate. |

**Example**

```text
/warn 3 Stop teamkilling
```

**Result**

Target sees a "Warning" toast; `/warnings` on that player shows it afterwards. Refused against yourself when `Config.moderation.blockSelfTarget` is true.

### `/warnings <id>`

Lists a player's recorded warnings from admin_logs.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | mod gate. |

**Example**

```text
/warnings 3
```

**Result**

One chat line per warning with timestamp, actor and reason, or "no warnings on record".

### `/kick <id|me> [reason]`

Drops the target from the server.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id (or "me"/omitted for self), reason? (default "Kicked by an administrator"). |
| Access | mod gate. |

**Example**

```text
/kick 3 Breaking rules
```

**Result**

Target is disconnected with the reason shown as the kick message.

### `/ban <target> <duration> <reason>`

Bans a player by identifiers, online or offline, and drops them if currently connected. Surfaces possible alt accounts sharing the same license (advisory only, never auto-banned).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | target (server id or offline identifier via Admin.resolveOfflineTarget), duration (e.g. `30m`, `2h`, `7d`, `1w`, or `perm`/`permanent`), reason. |
| Access | admin gate. |

**Example**

```text
/ban 3 7d Cheating
```

**Result**

Inserts a `bans` row (license/discord/ip/reason/expire/bannedby) and responds with the ban confirmation plus any possible alt citizen IDs.

### `/unban <licenseOrId>`

Lifts an active ban by numeric ban id or by license, without deleting the row (history is preserved).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | licenseOrId. |
| Access | admin gate. |

**Example**

```text
/unban 42
```

**Result**

Sets `expire` to now on matching active rows; reports how many were lifted.

### `/freeze <id> [state]`

Freezes or unfreezes a player in place. Omitted state toggles.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, state? (on/off/toggle — parsed by Admin.resolveToggle). |
| Access | mod gate. |

**Example**

```text
/freeze 3 on
```

**Result**

Target can no longer move; menu player-state view refreshes for the caller.

### `/kill <id>`

Kills the target player.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | mod gate. |

**Example**

```text
/kill 3
```

**Result**

Target dies client-side via kora_admin:client:kill.

### `/heal <id>`

Fully heals the target. Also restores hunger/thirst to 100 when `Config.heal.restoreNeeds` is true.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | mod gate. |

**Example**

```text
/heal 3
```

**Result**

Target is healed; needs reset if configured.

### `/revive <id>`

Revives a downed player and clears whichever ambulance job’s downed/laststand metadata is active (`Admin.fullReviveAmbulance`). Also restores needs when `Config.HealRestoreNeeds` is true.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | mod gate. |

**Example**

```text
/revive 3
```

**Result**

Target is revived regardless of which ambulance resource is tracking their downed state.

### `/god <id> [state]`

Toggles invincibility. Omitted state toggles.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, state?. |
| Access | mod gate to use on yourself; toggling it on another player additionally requires the admin gate (checked ad hoc in the handler). |

**Example**

```text
/god 3 on
```

**Result**

Target becomes invincible client-side.

### `/devmode <id> [state]`

Toggles kora_core development mode for a player.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, state?. |
| Access | mod gate for self; admin gate required to target another player. |

**Example**

```text
/devmode me on
```

**Result**

Toggles exports.kora_core:setDevMode and refreshes the menu player state.

### `/invisible <id> [state]`

Toggles invisibility.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, state?. |
| Access | mod gate for self; admin gate required to target another player. |

**Example**

```text
/invisible 3 on
```

**Result**

Target becomes invisible client-side.

### `/announce <message>`

Broadcasts a frontend toast to every player, with an optional alert sound (`Config.announcement.sound`).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | message. |
| Access | admin gate. |

**Example**

```text
/announce Server restarting in 10 minutes
```

**Result**

Every player sees an "Announcement" toast (and hears the sound, if enabled).

### `kora_broadcast <message>`

Lets an external bot (e.g. the Discord bot) push a longer-lived warning toast to every player without going through the gate system.

| Field | Details |
| --- | --- |
| Context | Server console / RCON only |
| Arguments | message (free text after the first word, truncated to 200 chars). |
| Access | Console/RCON only (`source == 0`); not reachable in-game. |

**Example**

```text
kora_broadcast Restarting for an update in 5 minutes
```

**Result**

Every player sees a 60-second "Server" warning toast.

### `/weather <type>`

Sets the global weather. Delegates to `kora_weathersync` if it is running, otherwise relays directly to every client and remembers it for newly-loaded players.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | type — one of Config.world.weatherTypes (e.g. CLEAR, RAIN, THUNDER). |
| Access | admin gate. |

**Example**

```text
/weather THUNDER
```

**Result**

Weather changes server-wide.

### `/time <hour|preset> [minute]`

Sets the server clock, accepting either a numeric hour (0-23) and optional minute (0-59), or one of `Config.world.timePresets`’ ids (default: morning, noon, night).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | hour\|preset, minute? (ignored for a preset, which carries its own). |
| Access | admin gate. |

**Example**

```text
/time night
/time 14 30
```

**Result**

Clock changes server-wide (or via kora_weathersync if running).

### `/serverinfo`

Prints online player count, uptime and running resource count.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | mod gate. |

**Example**

```text
/serverinfo
```

**Result**

Three chat lines of basic stats.

### `/adminlog [action] [target] [page]`

Reads the admin_logs audit trail with optional filters, paged by Config.audit.pageSize.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | action?, target?, page? (all optional filters passed to Admin.queryLogs). |
| Access | admin gate. |

**Example**

```text
/adminlog ban
```

**Result**

One chat line per matching log row: timestamp, action, actor -> target, details.

### `/setjob <id> <job> [grade]`

Sets a player's job and grade. Job/grade validity is enforced by kora_core's own setJob export, not duplicated here.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, job, grade? (defaults applied by kora_core). |
| Access | admin gate. |

**Example**

```text
/setjob 3 police 2
```

**Result**

Target's job changes; kora_core returns "unknown job" if the name is invalid.

### `/setgang <id> <gang> [grade]`

Sets a player's gang and grade, same validation model as /setjob.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, gang, grade?. |
| Access | admin gate. |

**Example**

```text
/setgang 3 ballas 1
```

**Result**

Target's gang changes.

### `/setduty <id> [state]`

Toggles a player’s on/off duty state for their current job. Omitted state toggles from their current duty.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, state?. |
| Access | mod gate. |

**Example**

```text
/setduty 3 on
```

**Result**

Duty state changes via exports.kora_core:setJobDuty.

### `/givemoney <id> <account> <amount> [reason]`

Adds money to one of a player’s accounts via exports.kora_core:addMoney. Account names are not validated here — an invalid account name is rejected by kora_core itself.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, account, amount (> 0), reason? (default "admin:givemoney"). |
| Access | admin gate. |

**Example**

```text
/givemoney 3 cash 500 bonus
```

**Result**

Balance increases; logged with account/amount/reason.

### `/removemoney <id> <account> <amount> [reason]`

Removes money, same shape as /givemoney, via exports.kora_core:removeMoney.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, account, amount (> 0), reason?. |
| Access | admin gate. |

**Example**

```text
/removemoney 3 bank 200
```

**Result**

Balance decreases, or fails with kora_core’s error (e.g. insufficient funds).

### `/setmoney <id> <account> <amount> [reason]`

Sets an account balance outright via exports.kora_core:setMoney.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, account, amount (> 0), reason?. |
| Access | admin gate. |

**Example**

```text
/setmoney 3 cash 1000
```

**Result**

Balance set to the given amount.

### `/giveitem <id> <item> [amount] [infoJson]`

Gives an inventory item, with optional JSON metadata.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, item, amount? (default 1, positive whole number), infoJson? (must decode to a JSON object). |
| Access | admin gate. |

**Example**

```text
/giveitem 3 water 5
```

**Result**

Item added via exports.kora_core:addItem, reason tagged "admin:giveitem".

### `/removeitem <id> <item> [amount]`

Removes an inventory item.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, item, amount? (default 1). |
| Access | admin gate. |

**Example**

```text
/removeitem 3 weapon_pistol 1
```

**Result**

Item removed via exports.kora_core:removeItem.

### `/clearinventory <id>`

Empties a player's entire inventory.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | admin gate. |

**Example**

```text
/clearinventory 3
```

**Result**

Inventory cleared via exports.kora_core:clearInventory.

### `/car <model>`

Spawns a vehicle in front of you and grants yourself the keys (via kora_vehiclekeys, privileged override flag set).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | model — must resolve through Kora.shared.get('vehicles', ...) or a valid streamed model hash. |
| Access | admin gate. |

**Example**

```text
/car sultan
```

**Result**

Vehicle spawns and you are warped into it.

### `/veh <id> <model>`

Spawns a vehicle for another player and grants them the keys.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, model. |
| Access | admin gate. |

**Example**

```text
/veh 3 sultan
```

**Result**

Vehicle spawns near the target; they are notified if Config.vehicle.notifyTarget is true.

### `/givevehicle <id> <model> <plate>`

Adds a persistent, garage-owned vehicle to a player's characters via exports.kora_core:createVehicle, without spawning it.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, model, plate (1-15 letters/digits). |
| Access | admin gate. |

**Example**

```text
/givevehicle 3 sultan ABC123
```

**Result**

Vehicle row created for the target’s citizen id.

### `/givekeys <id>`

Not a kora_admin command. `/givekeys` belongs to kora_vehiclekeys (a player hands over keys they hold); kora_admin deliberately does not register a command with that name (`server/commands/vehicle.lua:3-4`). Use `/car`, `/veh` or `/givevehicle`, which grant keys automatically through `exports.kora_vehiclekeys:giveKeys`.

| Field | Details |
| --- | --- |
| Context | Provided by kora_vehiclekeys, not registered by kora_admin |
| Arguments | id. |
| Access | Defined by kora_vehiclekeys, not by kora_admin gates. |

**Example**

```text
/givekeys 3
```

**Result**

Behaviour is defined by kora_vehiclekeys; kora_admin does not handle this command.

### `/dv [radius]`

Deletes the vehicle you are in; with no vehicle and `Config.dv.nearestRadius` > 0, deletes the nearest vehicle; with a radius argument, deletes every vehicle within it (capped at `Config.dv.maxRadius`), skipping any vehicle occupied by another player.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | radius? — metres, must be positive. |
| Access | admin gate. |

**Example**

```text
/dv
/dv 20
```

**Result**

Deletes one or more server-side vehicle entities and logs plates and mode (current/nearest/radius).

### `/fix`

Repairs the vehicle you are currently in.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | mod gate. |

**Example**

```text
/fix
```

**Result**

Fails with "you are not in a vehicle" outside one.

### `/entity <model>`

Spawns a static, non-networked ped or prop in front of you via kora_lib’s entities module. Vehicle models are refused (use /car or /veh).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | model. |
| Access | admin gate. |

**Example**

```text
/entity prop_box_ammo01a
```

**Result**

Entity appears client-side for you only.

### `/entityfor <id> <model>`

Same as /entity but spawned for another player.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, model. |
| Access | admin gate. |

**Example**

```text
/entityfor 3 prop_box_ammo01a
```

**Result**

Entity appears client-side for the target.

### `/deleteentity`

Deletes your own last admin-spawned static entity.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | admin gate. |

**Example**

```text
/deleteentity
```

**Result**

Removes the last entity spawned by /entity or /entityfor for you.

### `/entitypicker`

Starts the client-local entity inspector to find and copy a model/archetype name you are aiming at.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | Config.developer.menuLevel gate (default admin); also requires kora_core dev mode first if Config.developer.requireDevMode is true. |

**Example**

```text
/entitypicker
```

**Result**

A crosshair and copy hotkey (default H, close X) appear; see Configuration.

### `/devplacement <model>`

Opens kora_lib’s client-local entity placement tool for a model name or numeric hash.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | model. |
| Access | Config.developer.menuLevel gate. |

**Example**

```text
/devplacement 1234567
```

**Result**

Opens the placement tool; nothing is persisted or networked.

### `/devzone <box|sphere|poly>`

Opens kora_lib’s client-local zone creator.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | type — box, sphere, or poly. |
| Access | Config.developer.menuLevel gate. |

**Example**

```text
/devzone sphere
```

**Result**

Opens the zone creator; nothing is persisted or networked.

### `/clothingmenu <id>`

Opens a one-use kora_clothing session for another player via exports.kora_clothing:OpenAdminSession(targetSrc, 'clothing'). Fails if kora_clothing is not running.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | admin gate. |

**Example**

```text
/clothingmenu 3
```

**Result**

kora_clothing owns the session lifecycle and authorization from here; kora_admin only resolves the target and audits the call.

### `/barbermenu <id>`

Same as /clothingmenu with service 'barber'.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | admin gate. |

**Example**

```text
/barbermenu 3
```

**Result**

Opens the barber/hairdresser session.

### `/tattoomenu <id>`

Same as /clothingmenu with service 'tattoo'.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | admin gate. |

**Example**

```text
/tattoomenu 3
```

**Result**

Opens the tattoo session.

### `/goto <id>`

Teleports you to the target player.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | mod gate. |

**Example**

```text
/goto 3
```

**Result**

Refused against yourself ("cannot goto yourself").

### `/bring <id>`

Teleports the target to you.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | mod gate. |

**Example**

```text
/bring 3
```

**Result**

Refused against yourself.

### `/sendback <id>`

Returns the target to their own position before the last admin teleport they received, via the target client's bounded undo history.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | mod gate. |

**Example**

```text
/sendback 3
```

**Result**

Target is returned to their own prior position (not yours).

### `/tpm`

Teleports you to your own waypoint.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | mod gate. |

**Example**

```text
/tpm
```

**Result**

Client-local; fails silently if no waypoint is set.

### `/tpcoords <coords>`

Teleports you to literal coordinates: `x y z`, `x, y, z`, `vec3(x, y, z)`, `vector3(...)`, `vec4(x, y, z, heading)`, or `vector4(...)` (4th component is heading, not a Z offset).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | coordinates. |
| Access | mod gate. |

**Example**

```text
/tpcoords vec4(100, 200, 30, 90)
```

**Result**

Teleports you; invalid syntax is rejected with a usage hint.

### `/tpback`

Returns you to your position before your last teleport.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | mod gate. |

**Example**

```text
/tpback
```

**Result**

Undo depth is Config.teleport.tpbackHistory (default 1).

### `/spectate [id]`

Spectates a player; omit the id to stop spectating.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id? (omit to stop). |
| Access | mod gate. |

**Example**

```text
/spectate 3
/spectate
```

**Result**

Refused against yourself.

### `/noclip`

Toggles a free-fly noclip camera for yourself, tuned by Config.noclip.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | admin gate. |

**Example**

```text
/noclip
```

**Result**

Toggles noclip on/off.

### `/aduty`

Toggles your own admin on-duty metadata flag.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | mod gate. |

**Example**

```text
/aduty
```

**Result**

Toggles on/off; purely a status flag (unclear if anything else in source reads it beyond the response text).

### `/coords`

Copies your current coordinates to the clipboard client-side.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | mod gate. |

**Example**

```text
/coords
```

**Result**

No chat response; the client copies via Kora.nui.copyToClipboard.

### `/vec4`

Copies your current vector4 (position + heading) to the clipboard.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | mod gate. |

**Example**

```text
/vec4
```

**Result**

Same mechanism as /coords.

### `/health [percentage]`

Sets your own health percentage (0-100, default 100). If you are currently downed/in last stand and the new value would be non-zero, you are revived first (clearing ambulance downed metadata) rather than just having health set on a corpse state.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | percentage? (default 100). |
| Access | mod gate. |

**Example**

```text
/health 50
```

**Result**

Health changes; a downed player is revived as a side effect when reviving to non-zero health.

### `/armor [percentage]`

Sets your own armor percentage (0-100, default 100).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | percentage? (default 100). |
| Access | mod gate. |

**Example**

```text
/armor 100
```

**Result**

Armor changes client-side.

### `/selfrevive`

Revives yourself and clears whichever ambulance job’s downed/laststand metadata is active. Deliberately named differently from /revive so it can never be shadowed by an ambulance resource’s own /revive command (both share the same command table with no collision detection).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | No arguments. |
| Access | mod gate. |

**Example**

```text
/selfrevive
```

**Result**

You are revived regardless of load order against the ambulance resource.

### `/permission [id]`

Shows a player's resolved permission level. Checking another player's level requires the admin gate; checking your own only requires mod.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id? (defaults to checking yourself — exact default-target behavior for an omitted id should be confirmed against Admin.resolveTarget if scripting around it). |
| Access | mod gate for self; admin gate to check another player. |

**Example**

```text
/permission 3
```

**Result**

"&lt;name>: &lt;level>" in chat.

### `/restartresource <name>`

Restarts an arbitrary resource by name.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | name — alphanumeric/underscore/hyphen only; must not be a missing resource. |
| Access | god gate (owner). |

**Example**

```text
/restartresource kora_banking
```

**Result**

Runs `restart <name>` on the server.

### `/setpermission <id> <level>`

Grants a runtime-only permission level via exports.kora_core:addPermission (an add_principal ACE grant that does not survive a restart unless server.cfg is also edited).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, level (a configured role, not "user"). |
| Access | god gate; disabled entirely in Discord-only permission mode. |

**Example**

```text
/setpermission 3 moderator
```

**Result**

Grant takes effect immediately; does not persist past a restart on its own.

### `/revokepermission <id> <level>`

Revokes a runtime permission level by running `remove_principal` for the target's primary identifier. There is no removePermission export on kora_core to delegate to, so this mirrors kora_core's own identifier formatting by hand.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, level. |
| Access | god gate; disabled entirely in Discord-only permission mode. |

**Example**

```text
/revokepermission 3 moderator
```

**Result**

Removes the matching ACE principal grant.

### `/granttempaccess <id> <role> <minutes>`

Grants a temporary, in-memory role that survives a reconnect but is cleared by a kora_admin restart. Bounded by Config.permissions.temporaryGrant (managerRole, maxRole, min/maxMinutes).

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, role (must be grantable and at or below maxRole), minutes (within min/maxMinutes). |
| Access | Config.permissions.temporaryGrant.managerRole gate (default admin); disabled entirely in Discord-only permission mode. |

**Example**

```text
/granttempaccess 3 moderator 60
```

**Result**

Target's level is immediately synced client-side and expires automatically after the duration.

### `/revoketempaccess <id> <role>`

Revokes a temporary role grant early.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, role. |
| Access | Config.permissions.temporaryGrant.managerRole gate; disabled entirely in Discord-only permission mode. |

**Example**

```text
/revoketempaccess 3 moderator
```

**Result**

Fails with "has no temporary &lt;role> access" if nothing matched.

### `/report <type> <message>`

Submits a player report in one of Config.reports.types.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | type (a configured report type id), message. |
| Access | user gate (every player). |

**Example**

```text
/report bug The ATM at the bank is not working
```

**Result**

Returns a report id; hints at /reports if chat is enabled.

### `/reportstatus <id>`

Shows one of your own reports (or any report, for staff) with its replies.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | user gate (ownership/staff checked inside the handler). |

**Example**

```text
/reportstatus 12
```

**Result**

Prints the report and every reply with timestamps.

### `/reportreply <id> <message>`

Replies to your own report; staff may reply to any report.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, message. |
| Access | user gate (ownership/staff checked inside the handler). |

**Example**

```text
/reportreply 12 Still happening
```

**Result**

Adds a message to the report thread.

### `/reports [status] [type] [page]`

Lists reports: staff see the shared queue (opens the NUI Reports screen if Config.reports.command.ui is true), non-staff see only their own (opens "My Reports" chat if Config.reports.chat.playerUi is true). Registered only when Config.reports.command.enabled is true.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | status? (all/open/claimed/resolved/dismissed), type?, page?. |
| Access | user gate (staff vs. own-reports branching happens inside the handler). |

**Example**

```text
/reports open
```

**Result**

Opens a UI or prints a chat list depending on config and caller role.

### `/reportclaim <id>`

Claims a report for yourself as the handling staff member.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id. |
| Access | Config.reports.staffLevel gate (default support). |

**Example**

```text
/reportclaim 12
```

**Result**

Marks the report claimed by you.

### `/reportresolve <id> [note]`

Marks a report resolved.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, note?. |
| Access | Config.reports.staffLevel gate. |

**Example**

```text
/reportresolve 12 Fixed in the next restart
```

**Result**

Report status becomes resolved.

### `/reportdismiss <id> [note]`

Marks a report dismissed.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, note?. |
| Access | Config.reports.staffLevel gate. |

**Example**

```text
/reportdismiss 12 Not a bug
```

**Result**

Report status becomes dismissed.

### `/reportreopen <id> [note]`

Reopens a resolved or dismissed report.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | id, note?. |
| Access | Config.reports.staffLevel gate. |

**Example**

```text
/reportreopen 12
```

**Result**

Report status becomes open.

### `kora_admin_whyperms <server id>`

Diagnostic: prints a target player's raw FiveM identifiers and every ACE object Kora.permissions checked against, with the resolved level.

| Field | Details |
| --- | --- |
| Context | Server console only |
| Arguments | server id. |
| Access | Console only (source must be 0); not reachable in-game. |

**Example**

```text
kora_admin_whyperms 3
```

**Result**

Multi-line console report; hints at the exact `add_ace` line needed if nothing matched.

## Legacy command table

Internally every command also lives in `Admin.commands[name]` (help, args, argsRequired, handler, permission) so the Discord relay and other in-process consumers can introspect or re-invoke a command without going through chat.

## Granting roles via ACE

In the default ACE mode, grant a role with `add_ace identifier.license:<id> kora_core.<role> allow` in server.cfg (or via add_principal at runtime for temporary/manual grants). Use `kora_admin_whyperms` from the console to verify a grant actually resolves.

## Reference tables by group

The same commands grouped into summary tables with tiers and audit action names, plus shared conventions, console-only commands and key mappings.

All commands below are registered with kora_lib's `Kora.commands.add` (through `Admin.addCommand`), so they get chat suggestions and `/help` text, and the console may run any of them without a permission check. Tiers refer to the default role mapping described in [Permissions](./permissions.md); "mod" means the `moderator` role.

### Conventions

- **Target argument (`id`)** - resolved by `Admin.resolveTarget`: a missing argument, an empty string or the word `me` means yourself; a number is a server id; any other text is a case-insensitive substring match against online player names (it fails if no player or more than one player matches). The target must be loaded in kora_core.
- **Toggle argument (`state`)** - `true`/`on`/`1` or `false`/`off`/`0`; omitted toggles the current state.
- **Feedback** - results are shown as kora_lib notifications; multi-line output (player lists, logs, reports) is printed to chat with the `[Admin]` prefix.
- **Audited** - "yes" means the command writes a row to `admin_logs` with that action name. See [Database](./database.md).

### Menu and information

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/admin` | - | support | Opens the admin menu. Key mapping: `Config.keybind.defaultKey` (default `F7`), rebindable in FiveM key bindings. A denied player gets a message explaining the required and held roles. | no |
| `/players` | `[search]` | support | Lists online players in chat: id, name, job label, ping. | no |
| `/permission` | `[id]` | mod | Shows a player's resolved tier. Checking another player requires admin. | no |
| `/serverinfo` | - | mod | Prints online player count, uptime in minutes and number of resources. | no |
| `/config` | - | `Config.configEditor.level` (admin) | Opens kora_lib's configuration app (`kora_lib:client:configOpened`) on kora_admin. The editor lists every resource that registered a kora_lib config schema and shows whether a change applies now or needs a restart. | no |

### Moderation

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

### Teleport, noclip and spectate

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

### Self and utility

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/aduty` | - | mod | Toggles the `adminDuty` metadata flag on your character. | no |
| `/coords` | - | mod | Copies `vector3(x, y, z)` of your position to the clipboard and prints it to F8. | no |
| `/vec4` | - | mod | Copies `vector4(x, y, z, heading)` to the clipboard and prints it to F8. | no |
| `/health` | `[percentage]` | mod | Sets your own health as 0-100 percent of the ped's real range (100 is GTA's death floor, 100% is the ped's max). A non-zero value while dead or downed revives first. Default 100. | no |
| `/armor` | `[value]` | mod | Sets your own armour (default 100). | no |
| `/selfrevive` | - | mod | Revives yourself, clearing the downed metadata and ambulance state. Named differently from `/revive` so another resource's `/revive` cannot shadow it. | no |

### Economy and inventory

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/givemoney` | `<id> <account> <amount> [reason]` | admin | kora_core `addMoney`. Default reason `admin:givemoney`. | `givemoney` |
| `/removemoney` | `<id> <account> <amount> [reason]` | admin | kora_core `removeMoney`. | `removemoney` |
| `/setmoney` | `<id> <account> <amount> [reason]` | admin | kora_core `setMoney`. The amount must be positive. | `setmoney` |
| `/giveitem` | `<id> <item> [amount] [infoJson]` | admin | kora_core `addItem`; amount defaults to 1; the optional fourth argument must be a JSON object (one word, no spaces) used as item metadata. | `giveitem` |
| `/removeitem` | `<id> <item> [amount]` | admin | kora_core `removeItem`. | `removeitem` |
| `/clearinventory` | `<id>` | admin | kora_core `clearInventory`. | `clearinventory` |

Account names are validated by kora_core (its configured money types); kora_admin surfaces kora_core's error.

### Jobs, gangs and duty

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/setjob` | `<id> <job> [grade]` | admin | kora_core `setJob`; kora_core validates the job and grade. | `setjob` |
| `/setgang` | `<id> <gang> [grade]` | admin | kora_core `setGang`. | `setgang` |
| `/setduty` | `[id] [state]` | mod | kora_core `setJobDuty`; toggles when no state is given. | `setduty` |

`Config.roles.hiddenJobs` and `hideDuplicateLabels` only trim the menu's job list; hidden jobs still work with `/setjob`.

### Appearance (kora_clothing)

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/clothingmenu` | `<id>` | admin | Opens a free, one-use kora_clothing clothing session for the player via `exports.kora_clothing:OpenAdminSession(target, 'clothing')`. | `clothingmenu` |
| `/barbermenu` | `<id>` | admin | Same with the `barber` service. | `barbermenu` |
| `/tattoomenu` | `<id>` | admin | Same with the `tattoo` service. | `tattoomenu` |

These fail with "kora_clothing is not running" when kora_clothing is not started. The session authorisation is created server-to-server; clients cannot mint it.

### Vehicles

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/car` | `<model>` | admin | Spawns the vehicle server-side `Config.vehicle.spawnOffset` metres in front of you, in your routing bucket, grants you keys and warps you in. | `car` |
| `/veh` | `<id> <model>` | admin | Same for another player; notifies them when `Config.vehicle.notifyTarget` is on. | `veh` |
| `/givevehicle` | `<id> <model> <plate>` | admin | Adds a persistent personal vehicle to the online player's garage through kora_core `createVehicle`. Plates are 1-15 letters or digits (upper-cased). | `givevehicle` |
| `/dv` | `[radius]` | admin | Deletes the vehicle you are in; on foot, the nearest vehicle within `Config.dv.nearestRadius`; with a radius, every vehicle in range (capped at `Config.dv.maxRadius`). Vehicles with another player inside are skipped. With `nearestRadius = 0` only your current vehicle is deleted. | `dv` |
| `/fix` | - | mod | Repairs the vehicle you are in (body, engine, deformation). | `fix` |

Models must match `^[A-Za-z0-9_]+$` and be either in kora_core's shared vehicle list or a vehicle model known to `Kora.lookup.model` (streamed addon vehicles included). Keys are granted with `exports.kora_vehiclekeys:giveKeys(target, plate, true)` (administrative override); if that fails the vehicle is deleted. `/givekeys` belongs to kora_vehiclekeys, not kora_admin.

### Entities

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/entity` | `<model>` | admin | Spawns a static, local (non-networked) ped or prop `Config.entity.spawnOffset` metres in front of you using `Kora.entities.create` with the `static` preset. | `entity` |
| `/entityfor` | `<id> <model>` | admin | Same, spawned on the target player's client. | `entityfor` |
| `/deleteentity` | - | admin | Deletes your client's most recent admin-spawned entity. | `deleteentity` |

Vehicle models are refused ("use /car or /veh for vehicle models"). Entities are visible only to the client they were spawned for and are cleaned up by kora_lib when the resource stops.

### Developer tools

Tier: `Config.developer.menuLevel` (default admin). With `Config.developer.requireDevMode = true` the caller must also have kora_core development mode enabled.

| Command | Arguments | Effect | Audited |
| --- | --- | --- | --- |
| `/entitypicker` | - | Starts the entity picker HUD. | `entitypicker` |
| `/devplacement` | `<model or hash>` | Starts `Kora.placement.start(model)` for any ped, vehicle or object. | `devplacement` |
| `/devzone` | `<box or sphere or poly>` | Starts `Kora.zones.startCreator(type)`. | `devzone` |

Details: [Developer tools](./features/developer-tools.md).

### World and server

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/announce` | `<message>` | admin | Notifies every player ("Announcement", 8 s) and plays `Config.announcement.sound` when enabled. | `announce` |
| `/weather` | `<type>` | admin | If kora_weathersync is started, calls its `setWeather`; otherwise validates against `Config.world.weatherTypes` and applies it to all clients. | `weather` |
| `/time` | `<hour or preset> [minute]` | admin | Hour 0-23 with optional minute 0-59 (default 0), or a preset id from `Config.world.timePresets` (`morning`, `noon`, `night`). Out-of-range values are refused, never clamped. Uses kora_weathersync's `setTime` when it runs. | `time` |
| `/adminlog` | `[action] [target] [page]` | admin | Prints a page (`Config.audit.pageSize`) of the audit log, newest first. `target` matches citizen id, license or name. Times are UTC. | no |
| `/restartresource` | `<name>` | owner | Runs `restart <name>` for an existing resource. | `restartresource` |

Without kora_weathersync, the last weather and time set by kora_admin are re-applied to joining players when `Config.world.syncOnPlayerLoaded` is on.

### Access management

| Command | Arguments | Tier | Effect | Audited |
| --- | --- | --- | --- | --- |
| `/setpermission` | `<id> <role>` | owner | Runtime `add_principal` via kora_core `addPermission`. | `setpermission` |
| `/revokepermission` | `<id> <role>` | owner | Runtime `remove_principal` for `kora_core.<role>`. | `revokepermission` |
| `/granttempaccess` | `<id> <role> <minutes>` | `temporaryGrant.managerRole` (admin) | Memory-only temporary tier. | `granttempaccess` |
| `/revoketempaccess` | `<id> <role>` | `temporaryGrant.managerRole` (admin) | Removes a temporary grant early. | `revoketempaccess` |

All four are disabled in Discord-only permission mode. See [Permissions](./permissions.md).

### Player reports

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

### Console-only commands

These are registered with `RegisterCommand` and do nothing unless run from the server console or RCON.

| Command | Arguments | Effect |
| --- | --- | --- |
| `kora_admin_whyperms` | `<server id>` | Prints the player's identifiers, the ACE checks kora_lib performs and the resolved level. |
| `kora_broadcast` | `<message>` | Shows a "Server" warning notification (60 s, first 200 characters) to every player. Intended for external restart warnings. |

### Key mappings

| Mapping | Default key | Action |
| --- | --- | --- |
| `/admin` | `F7` (`Config.keybind.defaultKey`) | Opens the menu through the normal `/admin` permission check. |
| `kora_admin_spectate_stop` | `BACK` (`Config.spectate.stopKey`) | Stops spectating. |
| `kora_admin_entitypicker_copy` | `H` (`Config.entityPicker.copyKey`) | Opens the model-name dialog for the aimed entity. |
| `kora_admin_entitypicker_close` | `X` (`Config.entityPicker.closeKey`) | Closes the entity picker. |

All key mappings can be rebound by each player in Settings, Key Bindings, FiveM.
