# qbadmin

A comprehensive admin menu for this server's qbcore/qblib framework. There is
exactly one entry point for every privileged action: a chat command. The NUI
menu (`/admin`) is not a parallel code path -- after collecting a target and
some parameters, it builds the exact command string a human would type and
runs it with `ExecuteCommand`, the same mechanism this server's own chat
resource uses for anything typed starting with `/`
(`[gameplay]/chat/cl_chat.lua`). Whether an action was typed or clicked, the
same permission check, argument parsing, handler, audit log write, and
notification run -- there is nothing to keep in sync between the two UIs
because there is only one implementation.

## Permission model

Three tiers above `user`, ranked `mod < admin < god`:

| Tier | Covers |
|---|---|
| `mod` | Reversible, low-harm, first-responder tools: player info, spectate, freeze, heal/revive/kill, self god/dev mode/invisible, warn, kick, vehicle repair, on-duty toggle, self teleport, server info, self utilities. |
| `admin` | Persistent-state, economic, or identity-affecting actions, or projecting power onto another player's world: ban/unban, money, items, job/gang, vehicle/entity spawn/delete, noclip, god/dev mode/invisible **on another player**, announce, weather/time, audit log. |
| `god` | Server-wide or privilege-altering: grant/revoke permission level, resource restart. |

Commands register through **qblib's** `QB.commands.add` and all use
`Admin.checkLevel` (`server/permissions.lua`). That is a thin adapter over the
central `QB.permissions.hasLevel` gateway, so command execution, menu data,
and the level sent to the client menu all resolve permissions identically.
Rank checks cascade: a resolved `god` satisfies `admin` and `mod` without
manual principal chaining.

ACE authorization is always active. qblib checks `qbcore.<tier>` and
`group.<tier>`; in particular, a `group.admin` ACE grants the admin tier even
if Discord is disabled or unavailable. Examples:

```cfg
add_ace identifier.license:XXXX qbcore.mod allow
add_ace identifier.license:YYYY qbcore.admin allow
add_ace identifier.license:ZZZZ qbcore.god allow
add_principal identifier.license:XXXX group.mod
add_principal identifier.license:YYYY group.admin
add_principal identifier.license:ZZZZ group.god
```

Discord roles are optional additive grants. Configure role names or, ideally,
role IDs under `Config.permissions.discordRoles`:

```lua
discordRoles = {
    mod = { 'Moderator' },
    admin = { '123456789012345678' },
    god = { 'Owner' },
}
```

This uses qblib's Discord bot role cache, so `qblib_discord_bot_token` and
`qblib_discord_guild_id` must be configured for role grants. Missing/stale
role data fails closed for Discord only; ACE grants continue to work.

## The `me` convention

Every command that takes a player-id argument treats a missing argument, or
the literal word `me`, as "the player who ran this command"
(`server/target.lua`, `Admin.resolveTarget`). `/heal`, `/heal me`, and
`/heal 3` all work -- the first two heal the caller, the third heals server id
3. This applies to heal/revive/kill/freeze/god/devmode/invisible/spectate/checkplayer/
setduty/sethunger/setthirst/permission. Commands that operate purely on the caller (noclip,
coords, aduty, health, armor, fix, dv, tpm/tpcoords/tpback, selfrevive) take no id
argument at all -- there's nothing to resolve.

`/devmode [id=me] [true|false]` calls qbcore's per-player
`setDevMode` export. It combines god mode, paused passive hunger/thirst, and
fast walking; omitting the state toggles the current core-owned state. Mods may
use it on themselves, while targeting another player requires `admin`.

`/health [percentage]` and the corresponding admin-menu field use `0-100%`,
not GTA's native health number. Internally, 0% maps to the 100-health death
floor and 100% maps to the current ped's maximum (normally 200 for freemode
male peds and 175 for freemode female peds). Setting a non-zero percentage
while dead revives first (same as `/revive`/`/selfrevive`) -- raw health
alone doesn't clear GTA's internal death state, so the ped would otherwise
stay stuck on the death screen with a healthy-looking value underneath it.

**Revive clears whichever ambulance job is actually running, not just raw
health.** `/revive`, `/selfrevive`, and Set Health's own dead-to-alive branch
all funnel through the same client relay (`reviveLocalPed`,
`client/relay.lua`), which fires both real `qb-ambulancejob`'s
`hospital:client:Revive` and the qblib-native `qbambulance` rebuild's
`qbambulance:client:revived` -- whichever resource isn't currently started
simply has no handler for its own event name, so this is a harmless no-op for
the inactive one. Without this, raw natives alone leave that job's own
death-loop thread (the one forcing the death animation/disabled controls)
running forever even after health reads full.

`/selfrevive` (Self / Utility menu: "Revive Me", next to Set Health) is
deliberately a **different command name** from the existing targeted
`/revive` (Moderation menu) -- real `qb-ambulancejob` registers its own
`/revive` too, and qblib's command registry has no collision detection
(whichever resource registers the name last wins, silently). A dedicated
name for the self-service case means it can never be shadowed regardless of
which ambulance resource is active or what it names its own commands.

`/ban` and `/unban` deliberately do **not** support `me` -- they use a
separate offline-capable resolver (`Admin.resolveOfflineTarget`) since a ban
must be able to target a player who is not currently online, and banning
yourself by accident is not a case worth making convenient.

`Admin.teleportTo` matches txAdmin's own teleport algorithm exactly (its
`resource/menu/client/cl_main_page.lua`/`cl_functions.lua`): every teleport,
ground-snapped or not, first lands at a fixed safe altitude
(`Config.teleport.waypointLaunchHeight`) and waits for
`IsEntityWaitingForWorldCollision` to clear, so nothing ever clips into
not-yet-streamed geometry at the destination, not even a literal
admin-supplied one. `/tpm` additionally ground-snaps -- a waypoint's z is a
map-projected value, not real world elevation -- by then repeatedly probing
for ground beneath itself (`findGroundZ`, ported from txAdmin's own
`FindZForCoords`: drills down through stacked surfaces, e.g. a bridge deck
then the street under it, rather than stopping at the first hit), retrying
up to `Config.teleport.groundZAttempts` times, `groundZRetryDelay` ms apart,
in case collision is still streaming in. `/tpcoords`/`/goto`/`/bring`/
`/tpback` don't ground-snap -- their z already comes from a live entity or an
admin-supplied literal -- so they land at that z directly once the initial
high-altitude collision wait clears.

`/tpcoords` accepts either separate numbers (`/tpcoords 123.4 456.7 78.9`) or
pasted FiveM coordinate literals: `vec3(...)`, `vector3(...)`, `vec4(...)`,
and `vector4(...)`. A fourth vector component is applied as the destination
heading.

## Menu usage

`/admin` opens the root category menu, filtered to what your tier can reach
(cosmetic only -- every command re-checks server-side regardless of what the
menu shows). Most actions that target another player open a searchable player
picker with a "Me (myself)" entry pinned first. Destructive actions (ban,
kick, clear inventory, delete vehicle, restart resource) show a confirmation
dialog before the command actually runs.

`F7` is mapped directly on the server-owned `/admin` definition through
`QB.commands` keymapping support. It therefore enters the exact same permission
and error-handling path as typing `/admin`; there is no client forwarding
command that can open the menu independently.

A menu item can also set `visible` or `disabled` functions, evaluated each time
its category opens. `visible` hides actions that make no sense in the current
state (for example, Delete My Vehicle while on foot); `disabled` keeps an
action visible but unavailable, as the creator shortcuts are until development
mode is enabled. Both are presentation only and never replace server checks.

### Developer submenu

The **Developer** category is available at `Config.developer.menuLevel`
(`admin` by default). It can enable/disable qbcore's per-player development
mode, set that mode for another player, launch `QB.placement.start(model)`, and
open the qblib box/sphere/poly zone creator. When
`Config.developer.requireDevMode` is enabled, the two creator shortcuts remain
disabled until the caller enables their own development mode.

The menu executes the permission-checked `/devplacement` and `/devzone`
commands. Their server handlers verify both the configured admin tier and the
qbcore-owned development-mode state before relaying to the client. Both tools
are data-capture utilities: placement deletes its preview, and zone creation
returns/copies a definition without registering a live zone.

## Command reference

See the category tables in the project's admin-menu design plan for the full
list (Player Management, Moderation, Teleport/Noclip/Spectate, Economy,
Job/Gang, Vehicle, Developer, World/Server, Privileged, Self/Utility) -- every command
also has its own in-game help text via `/help <command>` or the chat
autocomplete suggestion.

The Vehicle category has **Spawn by Model**, a direct text field for any valid
GTA/addon spawn code (for example `outlaw`), and **Spawn from Catalogue**, a
searchable common-vehicle quick-pick. The catalogue is convenience only; the
server's native model validation decides whether an entered code can spawn.

The Entities category spawns any valid **ped or prop** model, such as
`a_m_m_skater_01` or `prop_barrel_02a`, for yourself or a selected player. It
uses qblib's local, static entity API, so an entity is visible only to the
client it was spawned for and is cleaned up on resource restart. **Delete My
Last Spawned Entity** removes that client's most recent admin entity. Vehicle
models deliberately stay on the Vehicle flow so they remain networked.

The Developer category adds `/devplacement <model>` for qblib's temporary
ped/vehicle/object placement creator and `/devzone <box|sphere|poly>` for its
zone creator. The existing `/devmode [id=me] [true|false]` command delegates to
qbcore's `setDevMode` export; its state is per-player and ephemeral.

## Ban system

`server/ban_enforcement.lua` adds a `playerConnecting` deferral that checks
the existing `bans` table (`qbcore/sql/002_identifiers.sql`) by license,
discord, and IP. qbcore itself has no `playerConnecting` hook, so there is no
load-order dependency to worry about. IP matching is inherently less reliable
this early in the connection handshake than license/discord -- those two are
the primary, trustworthy match keys.

`/ban` records alt-account candidates (other citizenids sharing the banned
player's license, via `exports.qbcore:findByIdentifier`) in the audit log and
surfaces them in the response message, but **never auto-bans them** -- that's
advisory information for the human admin, not an automated action, since a
shared identifier (a household Discord, for instance) is not proof of
ban-evasion.

`/unban` updates the ban's `expire` to now rather than deleting the row, so
its history (reason, who banned, original date) survives for `/adminlog`.

## Audit log

`admin_logs` (migrated by `server/migrate.lua`, `sql/001_admin_logs.sql`) is
the durable audit trail -- qbcore's own `logEvent` is an in-memory 500-entry
ring buffer only, unsuitable for "who banned whom, when" lookups later.
`/adminlog [action] [target] [page]` and the NUI's Audit Log category both
read from it via `Admin.queryLogs`. No auto-pruning in v1 -- if retention
becomes a concern, add a scheduled `DELETE ... WHERE created_at < ...` and a
`Config.audit.retentionDays` knob.

## Configuration

See `config.lua` for every tunable: permission ranks and the ACE principal
identifier kind, ban duration units, teleport fade/collision timing, noclip
speed, weather types and join-sync behavior, vehicle/entity spawn offsets,
Developer-menu level/dev-mode requirement, and audit log page size.

## Known gaps (out of scope for v1)

- **Screenshot capture** -- no such capability exists anywhere in
  `qbcore`/`qblib`, and FiveM has no native client screenshot API. Integrate
  an external resource (e.g. `screenshot-basic`) separately if needed.
- **Freeform SQL console** -- deliberately not built. `qbsql` already ships
  read-only `/qbsql ping|stats|slow|queue` gated by the `command.qbsql` ACE;
  point admins at those instead of adding a second, riskier query surface.
- **Character deletion/wipe** -- too destructive for a quick-action menu.

## Upstreaming candidate

`/revokepermission` (`server/commands/privileged.lua`) hand-builds a
`remove_principal` command mirroring `exports.qbcore:addPermission`'s own
identifier formatting, because no `removePermission` counterpart exists in
`qbcore/modules/permissions/server.lua`. Worth adding there directly so other
resources don't have to repeat this.
