# kora_admin

A comprehensive admin menu for this server's kora_core/kora_lib framework. There is
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

The default staff ladder is `Support < Moderator < Admin < Owner`. Roles are
ranked, so a higher role automatically receives every lower role's access.

| Tier | Covers |
|---|---|
| `support` | Open the admin menu, list online players, and inspect player information. |
| `moderator` | Reversible, low-harm, first-responder tools: spectate, freeze, heal/revive/kill, self god/dev mode/invisible, warn, kick, vehicle repair, on-duty toggle, self teleport, server info, self utilities. |
| `admin` | Persistent-state, economic, or identity-affecting actions, or projecting power onto another player's world: ban/unban, money, items, job/gang, vehicle/entity spawn/delete, noclip, god/dev mode/invisible **on another player**, announce, weather/time, audit log. |
| `owner` | Server-wide or unrestricted privilege changes: configuration editor, permanent runtime grants/revokes, and resource restart. |

Commands register through **kora_lib's** `Kora.commands.add` and all use
`Admin.checkLevel` (`server/permissions.lua`). That is a thin adapter over the
central `Kora.permissions.hasLevel` gateway, so command execution, menu data,
and the level sent to the client menu all resolve permissions identically.
Rank checks cascade: a resolved `owner` satisfies `admin`, `moderator`, and
`support` without manual principal chaining.

ACE authorization is always active. kora_lib checks `kora_core.<role>` and
`group.<role>`; in particular, a `group.admin` ACE grants the admin tier even
if Discord is disabled or unavailable. Examples:

```cfg
add_ace identifier.license:XXXX qbcore.support allow
add_ace identifier.license:YYYY qbcore.moderator allow
add_ace identifier.license:ZZZZ qbcore.owner allow
add_principal identifier.license:XXXX group.support
add_principal identifier.license:YYYY group.admin
add_principal identifier.license:ZZZZ group.owner
```

For a smooth upgrade, the default `moderator` and `owner` roles also recognize
the old `mod` and `god` ACE/group names. Remove those aliases from the role
configuration once your server.cfg has been migrated.

Discord roles are optional additive grants. Configure role names or, ideally,
role IDs under `Config.permissions.discordRoles`:

```lua
discordRoles = {
    moderator = { 'Moderator' },
    admin = { '123456789012345678' },
    owner = { 'Owner' },
}
```

This uses kora_lib's Discord bot role cache, so `kora_lib_discord_bot_token` and
`kora_lib_discord_guild_id` must be configured for role grants (the deprecated
`qblib_discord_bot_token` / `qblib_discord_guild_id` names are still read as fallbacks). Missing/stale
role data fails closed for Discord only; ACE grants continue to work.

For slash commands, full txAdmin restarts, appshell setup and optional
Discord-only staff authorization, see [Discord administration](discord.md).

With kora_core's txAdmin bridge installed, txAdmin master/full-access accounts
automatically inherit `group.admin`; limited txAdmin accounts do not. Grants and
removals refresh the menu through the same `Admin.getLevel` resolver. Explicit
Discord-only mode still uses Discord roles for kora_admin access. See kora_core's
permissions module documentation for bridge installation and lifecycle details.

### Temporary access

The selected player's **Access & Permissions** group is available to
`temporaryGrant.managerRole` (`admin` by default). It grants a selected configured role for a specified
number of minutes and can revoke that grant early. The default manager may
grant through `admin`; set `maxRole` lower if you do not want peer-level
delegation. Grants are memory-only, expire automatically, are audited, follow
the recipient through a reconnect during their timer, and are cleared if
`kora_admin` or the server restarts. They do not call `add_principal`, so expiry
can never remove a permanent ACE from `server.cfg`.

Use `/granttempaccess <id> <role> <minutes>` and
`/revoketempaccess <id> <role>` if you prefer commands. Add a role in
`Config.permissions.roles` with a unique numeric rank; it then appears in the
pickers automatically. Configure the `gates` table to assign existing feature
bands to an added role.

## Heal restores needs

`/heal` (and the admin-menu Heal action, which runs the same command) also sets
the target's hunger and thirst to 100 through `kora_core`'s `setMetaData`, so the
HUD updates immediately. `/revive` and `/selfrevive` never change hunger or
thirst. Set `Config.heal.restoreNeeds = false` for health-only heals.

## Announcement sound

`/announce` (and the admin-menu Send Announcement action) plays a short alert on
every client when the announcement arrives, because `Kora.notify` itself is
silent. Configure it with `Config.announcement.sound = { enabled, name, set }`
(default `CHALLENGE_UNLOCKED` / `HUD_AWARDS`, any stock `PlaySoundFrontend` pair).
Set `enabled = false` for silent announcements. `kora_broadcast` restart warnings
are unaffected.

## The `me` convention

Every command that takes a player-id argument treats a missing argument, or
the literal word `me`, as "the player who ran this command"
(`server/target.lua`, `Admin.resolveTarget`). `/heal`, `/heal me`, and
`/heal 3` all work -- the first two heal the caller, the third heals server id
3. This applies to heal/revive/kill/freeze/god/devmode/invisible/spectate/
setduty/sethunger/setthirst/permission. Commands that operate purely on the caller (noclip,
coords, aduty, health, armor, fix, dv, tpm/tpcoords/tpback, selfrevive) take no id
argument at all -- there's nothing to resolve.

`/devmode [id=me] [true|false]` calls kora_core's per-player
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
`client/relay.lua`), which fires the kora_lib-native `kora_ambulance` rebuild's
`qbambulance:client:revived` event. Without this, raw natives alone leave that
job's own death-loop thread running forever even after health reads full.

`/selfrevive` (Self / Utility menu: "Revive Me", next to Set Health) is
deliberately a **different command name** from the existing targeted
`/revive` (Moderation menu), so the self-service case cannot be shadowed.

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

`/admin` opens five focused workspaces -- **Players**, **Reports**, **My
Tools**, **Server**, and **Development** -- filtered to what your tier can
reach (cosmetic only; every command re-checks server-side regardless of what
the menu shows). Tabs inside each page group related actions. **Players** is
the main player-first workflow: click any online player (including yourself)
and the list becomes a tabbed profile with player tools, moderation,
economy/items, roles/access, and advanced actions.
Movement includes **Send Back**, which returns the player to their position
before the last kora_admin teleport. Appearance includes server-authorized free
clothing, barber/hairdresser, and tattoo sessions for the selected player.
**My Tools** contains General, Movement, Vehicles, and Appearance tabs.
**Server** contains Environment, Server, Offline Bans, Audit Log, and the
owner-only Configuration tab;
**Development** contains Builders and Medal Clips. Targeted moderation,
economy, job/gang, appearance, spawning, development-mode, and permission
controls appear only after selecting a player.

Selecting a player replaces the online list with a fresh server-built profile:
identity, job/gang, balances, health/armour, needs, state, and ping. Admins also
see the player's permission and platform identifiers. **Copy Player Info**
copies exactly the fields visible to that staff member to the clipboard.
Destructive actions (ban, kick, clear inventory, delete vehicle, restart
resource) show a confirmation dialog before the command actually runs.

Actions that need an unobstructed game view explicitly set `shouldClose` in
the menu definition. Clothing/styling, teleports, spectating, noclip, and the
developer placement and zone tools close the admin shell before they start.

`F7` is mapped directly on the server-owned `/admin` definition through
`Kora.commands` keymapping support. It therefore enters the exact same permission
and error-handling path as typing `/admin`; there is no client forwarding
command that can open the menu independently.

A menu item can also set `visible` or `disabled` functions, evaluated each time
the workspace is built. `visible` hides actions that make no sense in the
current state (for example, Delete Current Vehicle while on foot); `disabled`
keeps an action visible but unavailable, as the creator shortcuts are until
development mode is enabled. Both are presentation only and never replace
server checks.

### Player reports

Players submit `/report <type> <message>` using the configured `player`, `bug`,
`exploit`, `gameplay`, `question`, or `other` types. Reports persist in
`admin_reports` with their full conversation in `admin_report_messages`; the
`Config.reports.cooldownSeconds` submission delay limits spam without losing
reports when kora_admin restarts.

`/reports [status] [type] [page]` opens a dedicated **Player Reports** screen for
staff (the same queue, status filters, detail view and actions as the **Reports**
workspace in `/admin`). Rows show id, status, category, reporter, a one-line
subject and age; report text is displayed as text, never rendered as HTML.
`Config.reports.command = { enabled, ui }`: `ui = false` prints a short chat list
instead, `enabled = false` removes the command. Players below
`Config.reports.staffLevel` get a chat list of only their own reports.

Staff at `Config.reports.staffLevel` see the **Reports** workspace in `/admin`.
Reports can be filtered by status, type, reporter, and page. Selecting one
opens separate Overview, Manage, and Online Reporter tabs for claiming,
replying, resolving, dismissing, reopening, and player shortcuts. Players
receive status and staff-reply notifications and can read or continue their
own conversation with `/reportstatus <id>` and `/reportreply <id> <message>`.

The Reports screen updates while it is open: after **Reply to Reporter** the
conversation shows the new message at once, and new reports, the reporter's own
replies, claims and status changes made by other staff appear without reopening.
The queue or the open report reloads in the background; the selected tab and any
reply being typed are kept. `Config.reports.liveUpdates = false` limits the push
to the staff member who made the change.

#### Live report chat (`Config.reports.chat`)

With `chat.enabled` (default on) every report has a two-way chat. Staff see the
conversation on the report's Overview tab as message bubbles with a message box
and Send button underneath (Enter sends, Shift+Enter adds a line); it replaces
Manage > Reply to Reporter. Players type `/reports` (or `/reports <id>`) to open
**My Reports**: their own reports with an unread count, and the same chat for
each one. New messages appear on both sides without reopening; the view sticks
to the newest message unless you scrolled up, in which case a "N new messages"
button appears. A "New" divider marks the first unread message, and the staff
queue gets a **New** column (unread player messages since you last opened that
report). Read markers live in `admin_report_reads` (report, reader licence, last
message id); messages stay in `admin_report_messages` with the report.

When staff reply while My Reports is closed, the player gets a kora_lib toast
with a preview and a pointer to `/reports`; with it open the chat just updates.

Every message goes through `qbadmin:reportChatSend` and `Admin.replyToReport`,
which check that the sender owns the report (stored reporter licence) or holds
`Config.reports.staffLevel`, that the report is open, the length
(`chat.maxLength`, refused rather than cut) and a per-sender sliding window
(`chat.rateLimit`, which also covers `/reportreply`). Text is stored as typed
(control characters stripped, blank-line runs collapsed) and always rendered as
text; `/reportstatus` output is bracket-escaped for chat. `chat.playerUi = false`
keeps players on the chat-list commands, `chat.showStaffNames = false` shows
"Staff" instead of names, and `chat.notifyStaff = 'claimer'` limits reporter
message toasts to the claiming staff member. `chat.enabled = false` restores the
previous screens. Live staff updates still follow `Config.reports.liveUpdates`.

### Development workspace

The **Development → Builders** tab is available at
`Config.developer.menuLevel` (`admin` by default). Its **Inspect Entity** view
uses kora_lib's camera raycast and focus-free HUD to identify the prop, ped, or
vehicle being aimed at. It prefers GTA's own entity archetype name, so map
props show their actual model name; `H` copies that name and `X` closes the
picker by default (both are rebindable in FiveM settings). The tab also launches
`Kora.placement.start(model)` and opens the kora_lib box/sphere/poly zone creator.
Development mode for yourself or another player is changed from that selected
player's **Development** group. When
`Config.developer.requireDevMode` is set to `true` (default `false`), the builder shortcuts remain
disabled until the caller enables their own development mode. Each greyed button is labelled "(turn Development Mode on first)", and the tab
has a **Turn Development Mode On** toggle for yourself that unlocks them.

The menu executes the permission-checked `/entitypicker`, `/devplacement`, and `/devzone`
commands. Their server handlers verify both the configured admin tier and the
Kora-owned Development Mode state before relaying to the client. The two creator tools
are data-capture utilities: placement deletes its preview, and zone creation
returns/copies a definition without registering a live zone.

## Medal clips

The **Development → Medal Clips** tab captures a highlight from the admin who
clicks it. Medal listens on that player's `localhost`, so `client/medal.lua` sends the
request through kora_admin's invisible NUI bridge rather than relaying it through
FXServer. A successful response means Medal accepted the event; processing the
clip remains asynchronous in the Medal desktop app.

Generate a public key and register the event list with [Medal's Auto-Clipping
builder](https://medal.tv/developer/auto-clipping), then add the key to
`server.cfg`:

```cfg
setr qbadmin_medal_public_key "your-public-key"
```

The entries in `Config.medal.events` must use the same numeric IDs, names,
durations, and capture delays submitted to Medal. Each entry becomes its own
menu button. `Config.medal.menuLevel` controls who sees the tab; the
default is `admin`. Medal must be installed and running on each admin's PC.

## Command reference

The compact sidebar contains five workspaces; their tabs hold self/server
tools, and selecting a player reveals the complete categorized targeted
command set. Every command also has its own in-game help text via `/help
<command>` or the chat autocomplete suggestion.

The **My Tools → Vehicles** tab has **Spawn from Code**, a direct text field
that runs `/car` for any valid GTA/addon spawn code (for example `outlaw`), and
**Browse Vehicle Catalogue**, a searchable common-vehicle quick-pick. The
catalogue is convenience only; the server's native model validation decides
whether an entered code can spawn.

The selected player's **Advanced** tab spawns any valid **ped or prop** model,
such as `a_m_m_skater_01` or `prop_barrel_02a`, for yourself or a selected player. It
uses kora_lib's local, static entity API, so an entity is visible only to the
client it was spawned for and is cleaned up on resource restart. **Delete My
Last Spawned Entity** removes that client's most recent admin entity. Vehicle
models deliberately stay on the Vehicle flow so they remain networked.

The **Server → Environment** tab's **Set Time** action is a selector, not a
number entry: one button per `Config.world.timePresets` entry (Morning, Noon, Night by
default) plus **Custom**, which is the only path that opens the hour/minute
inputs at all. A preset button runs `/time <preset>` -- the word, not its
hour -- so the menu and a typed command hand the server the same input and
`server/commands/world.lua` resolves and range-checks the configured values
there, exactly as it does typed digits. The selector's title shows the live
clock, the preset already in effect is marked `current`, and Custom opens
prefilled with that clock, so an admin can see what the server time actually
is before changing it.

The **Development → Builders** tab adds `/entitypicker` for a focus-free entity
inspector that copies the aimed entity's actual model/archetype name, `/devplacement <model>`
for kora_lib's temporary ped/vehicle/object placement creator, and
`/devzone <box|sphere|poly>` for its zone creator. The existing `/devmode [id=me] [true|false]` command delegates to
kora_core's `setDevMode` export; its state is per-player and ephemeral.

## Ban system

`server/ban_enforcement.lua` adds a `playerConnecting` deferral that checks
the existing `bans` table (`kora_core/sql/002_identifiers.sql`) by license,
discord, and IP. kora_core itself has no `playerConnecting` hook, so there is no
load-order dependency to worry about. IP matching is inherently less reliable
this early in the connection handshake than license/discord -- those two are
the primary, trustworthy match keys.

`/ban` records alt-account candidates (other citizenids sharing the banned
player's license, via `exports.kora_core:findByIdentifier`) in the audit log and
surfaces them in the response message, but **never auto-bans them** -- that's
advisory information for the human admin, not an automated action, since a
shared identifier (a household Discord, for instance) is not proof of
ban-evasion.

`/unban` updates the ban's `expire` to now rather than deleting the row, so
its history (reason, who banned, original date) survives for `/adminlog`.

## Audit log

`admin_logs` (declared in `server/schema.lua`, created at startup by `server/migrate.lua`) is
the durable audit trail -- kora_core's own `logEvent` is an in-memory 500-entry
ring buffer only, unsuitable for "who banned whom, when" lookups later.
`/adminlog [action] [target] [page]` and the **Server → Audit Log** tab both
read from it via `Admin.queryLogs`. No auto-pruning in v1 -- if retention
becomes a concern, add a scheduled `DELETE ... WHERE created_at < ...` and a
`Config.audit.retentionDays` knob. Configuration saves and resets use the
`config.commit` and `config.reset` actions in this same audit trail.

## Configuration

`config.lua` remains the documented, community-editable baseline for every
tunable: permission ranks and the ACE principal identifier kind, ban duration
units, teleport fade/collision timing, noclip speed (including fast and precision multipliers), weather types, clock
presets and join-sync behavior, vehicle/entity spawn offsets, Developer-menu
level/dev-mode requirement, Medal events/key/menu level, and audit log page
size.

The owner-only **Server → Configuration** tab and `/config` command open the
kora_lib-backed configuration editor. It lists only resources that register a
schema, shows each setting’s saved and running values, and labels it **Applies
now** or **Restart required**. A save writes only the changed values to the
owning resource’s `config.local.lua`; it never rearranges or reformats
`config.lua`. Reset removes that setting’s override. The backup
`config.local.lua.bak` lets kora_lib recover if a generated override becomes
invalid.

The editor permission is `Config.configEditor.level` (`owner` by default).
Successful edits are audited as `config.commit` or `config.reset`. Sensitive
values, server.cfg/convars, database-managed definitions, runtime state, and
executable configuration are intentionally absent. `Config.permissions.discordRoles`
lives in `server/config.lua`, is server-only, and remains hidden from clients.

Resources choose `shared`, `client`, or `server` scope and explicitly opt in
to live application through kora_lib. Most settings are saved for the next
resource restart. Refer to [kora_lib’s configuration guide](https://qbcore2.github.io/kora_lib/modules/config/docs.html)
for field types, validation, local overrides, migration, scopes, and safe
live handlers.

## Known gaps (out of scope for v1)

- **Separate-resource NUI compositing in screenshots** -- kora_lib’s screenshot
  module can capture the game view and supports screenshot-basic-compatible
  call sites, but it cannot composite another resource’s CEF layer into that
  frame.
- **Freeform SQL console** -- deliberately not built. `kora_sql` already ships
  read-only `/qbsql ping|stats|slow|queue` gated by the `command.qbsql` ACE;
  point admins at those instead of adding a second, riskier query surface.
- **Character deletion/wipe** -- too destructive for a quick-action menu.

## Upstreaming candidate

`/revokepermission` (`server/commands/privileged.lua`) hand-builds a
`remove_principal` command mirroring `exports.kora_core:addPermission`'s own
identifier formatting, because no `removePermission` counterpart exists in
`kora_core/modules/permissions/server.lua`. Worth adding there directly so other
resources don't have to repeat this.

## Set Job / Set Gang lists

The Job and Grade pickers are filled from the kora_core registry on the server
(`qbadmin:menuRoles`, admin level), falling back to the client mirror only if
that call fails. `Config.roles` trims the job list without changing any job:

- `hiddenJobs` (default `{}`): job names to leave out, e.g. `{ "mechanic3" }`.
- `hideDuplicateLabels` (default `true`): list one job per label, first in
  registry order wins. The upstream qb-core `mechanic2`/`mechanic3` share the
  label "LS Customs", so only one is offered.

Hidden jobs still work with `/setjob`, and players who hold them keep them.

### Why menu screens are pushed with `updateApp`

kora_lib runs the menu's `onAction` from its own resource, so FiveM
msgpack-encodes whatever the handler returns, and that encoder silently turns
any table nested 16 or more levels deep into `nil`. Inside a returned
`{ update = { navigation = ... } }` the Grade choices
(`field.optionsByValue[job][i]`) sit at exactly level 16, so every Set Job and
Set Gang grade list reached the NUI empty while the job list, one level
shallower, still showed. `onAction` therefore sends any `update` through
`Kora.nui.updateApp` (an export argument, two levels shallower) and returns
only `navigate`/`notice`/`close`. Keep new screens on that path rather than
returning large navigation trees.
