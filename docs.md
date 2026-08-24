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
| `mod` | Reversible, low-harm, first-responder tools: player info, spectate, freeze, heal/revive/kill, self god/invisible, warn, kick, vehicle repair, on-duty toggle, self teleport, server info, self utilities. |
| `admin` | Persistent-state, economic, or identity-affecting actions, or projecting power onto another player's world: ban/unban, money, items, job/gang, vehicle spawn/delete, noclip, god/invisible **on another player**, announce, weather/time, audit log. |
| `god` | Server-wide or privilege-altering: grant/revoke permission level, resource restart. |

Commands register through **qblib's** `QB.commands.add` directly, not
qbcore's `exports.qbcore:addCommand`. The reason: `exports.qbcore:addCommand`
wires `checkPermission = Core.permissions.hasPermission`, which checks one
exact ACE string and does **not** cascade -- a `god` ACE does not
automatically satisfy a `mod` check unless the server operator manually
chains `add_principal group.god group.admin` etc. in `server.cfg`. qbadmin
instead supplies its own `checkPermission = Admin.checkLevel`
(`server/permissions.lua`), which wraps `exports.qbcore:getPermission(src)`
-- already cascading, since it walks qbcore's own ordered level list and
returns the single highest tier a player holds. Grant tiers with three ACE
principals and nothing else is required:

```cfg
add_ace identifier.license:XXXX qbcore.mod allow
add_ace identifier.license:YYYY qbcore.admin allow
add_ace identifier.license:ZZZZ qbcore.god allow
add_principal identifier.license:XXXX group.mod
add_principal identifier.license:YYYY group.admin
add_principal identifier.license:ZZZZ group.god
```

## The `me` convention

Every command that takes a player-id argument treats a missing argument, or
the literal word `me`, as "the player who ran this command"
(`server/target.lua`, `Admin.resolveTarget`). `/heal`, `/heal me`, and
`/heal 3` all work -- the first two heal the caller, the third heals server id
3. This applies to heal/revive/kill/freeze/god/invisible/spectate/checkplayer/
setduty/permission. Commands that operate purely on the caller (noclip,
coords, aduty, health, armor, fix, dv, tpm/tpcoords/tpback) take no id
argument at all -- there's nothing to resolve.

`/health [percentage]` and the corresponding admin-menu field use `0-100%`,
not GTA's native health number. Internally, 0% maps to the 100-health death
floor and 100% maps to the current ped's maximum (normally 200 for freemode
male peds and 175 for freemode female peds). Setting a non-zero percentage
while dead revives first (same as `/revive`) -- raw health alone doesn't
clear GTA's internal death state, so the ped would otherwise stay stuck on
the death screen with a healthy-looking value underneath it.

`/ban` and `/unban` deliberately do **not** support `me` -- they use a
separate offline-capable resolver (`Admin.resolveOfflineTarget`) since a ban
must be able to target a player who is not currently online, and banning
yourself by accident is not a case worth making convenient.

`/tpm` ground-snaps: a waypoint's z is a map-projected value, not real world
elevation, and the actual terrain isn't streamed in around a destination
until collision is requested there -- so `Admin.teleportTo(coords, true)`
lands `Config.teleport.groundSnapHeight` units above the target first, waits
for collision to load, then probes for and settles onto the real ground.
`/tpcoords`/`/goto`/`/bring`/`/tpback` don't ground-snap -- their z already
comes from a live entity or an admin-supplied literal.

## Menu usage

`/admin` opens the root category menu, filtered to what your tier can reach
(cosmetic only -- every command re-checks server-side regardless of what the
menu shows). Most actions that target another player open a searchable player
picker with a "Me (myself)" entry pinned first. Destructive actions (ban,
kick, clear inventory, delete vehicle, restart resource) show a confirmation
dialog before the command actually runs.

A menu item can also set `visible` (a function, evaluated each time its
category opens) to hide itself entirely when it wouldn't make sense to offer
right now -- distinct from the permission-level gate, which greys an item out
rather than hiding it, so a lower-level admin can still see what exists above
their tier. "Delete My Vehicle" is the current example: it only appears while
you're actually in a vehicle.

## Command reference

See the category tables in the project's admin-menu design plan for the full
list (Player Management, Moderation, Teleport/Noclip/Spectate, Economy,
Job/Gang, Vehicle, World/Server, Privileged, Self/Utility) -- every command
also has its own in-game help text via `/help <command>` or the chat
autocomplete suggestion.

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
speed, weather types and join-sync behavior, vehicle spawn offset, and audit
log page size.

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
