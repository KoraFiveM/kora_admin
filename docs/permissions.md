---
title: Permissions
sidebar_position: 2
---

# Permissions

Every command handler and every menu-data callback uses one check, `Admin.checkLevel(source, required)` in `server/permissions.lua`. It resolves the player's tier and compares ranks, so a higher tier always satisfies a lower requirement. The console (source `0`) is never permission-checked by kora_lib's command dispatcher.

## Tiers

The default ladder comes from `Config.permissions.roles`:

| Role | Rank | Label | `grantable` | ACE aliases |
| --- | --- | --- | --- | --- |
| `user` | 0 | User | `false` | - |
| `support` | 10 | Support | yes | - |
| `moderator` | 20 | Moderator | yes | `mod` |
| `admin` | 30 | Admin | yes | - |
| `owner` | 40 | Owner | `false` | `god` |

`grantable = false` removes a role from the menu's Grant Permission and temporary-access pickers and makes it impossible to grant temporarily. A typed `/setpermission` accepts any configured role except `user`, including `owner`.

What each tier covers by default:

| Tier | Covers |
| --- | --- |
| `support` | Open `/admin`, list players (`/players`), view player profiles, handle player reports. |
| `moderator` | Reversible, first-responder tools: warn/warnings, kick, freeze, kill, heal, revive, self god mode / development mode / invisibility, goto/bring/send back, waypoint and coordinate teleport, spectate, vehicle repair, duty toggle, admin duty, server info, self health/armour/revive, coordinates. |
| `admin` | Persistent, economic or identity-affecting actions: ban/unban, money, items, inventory clear, job/gang, hunger/thirst, appearance sessions for others, vehicle and entity spawning, `/dv`, noclip, god/devmode/invisibility on another player, checking another player's permission, announce, weather/time, audit log, developer tools, configuration editor, temporary access. |
| `owner` | `/restartresource`, `/setpermission`, `/revokepermission`. |

The exact requirement of every command is listed in [Commands](./commands.md).

### Feature gates

Command files request internal gate names, which `Config.permissions.gates` maps to roles:

| Gate | Default role |
| --- | --- |
| `support` | `support` |
| `mod` | `moderator` |
| `admin` | `admin` |
| `god` | `owner` |

Point a gate at a different role to retune a whole band without editing command files. Some features have their own setting instead: `Config.reports.staffLevel`, `Config.developer.menuLevel`, `Config.medal.menuLevel`, `Config.configEditor.level` and `Config.permissions.temporaryGrant.managerRole`. See [Configuration](./configuration.md).

### Adding a role

Add an entry to `Config.permissions.roles` with a unique numeric `rank`, for example:

```lua
senior_moderator = { label = 'Senior Moderator', rank = 25 },
```

Role names must be alphanumeric, `_` or `-`; ranks must be unique and `user` must exist (the resource asserts this). New roles appear automatically in the menu's Grant Permission and Temporary Access pickers and can be referenced from `gates`.

## How a player's tier is resolved

`Config.permissions.mode` (server-only, editable in the configuration editor) selects the mode.

### `ace_discord` (default, compatible)

1. kora_lib's `Kora.permissions.getLevel` checks, from highest rank down, the ACE objects for each role and alias with the `kora_core` prefix (for example `kora_core.admin` and `group.admin`), plus any Discord roles mapped in `Config.permissions.discordRoles`.
2. If the player holds an unexpired temporary grant with a higher rank, that grant wins.

ACE examples:

```cfg
add_ace identifier.license:XXXX kora_core.support allow
add_ace identifier.license:YYYY kora_core.moderator allow
add_principal identifier.license:ZZZZ group.admin
add_ace identifier.license:WWWW kora_core.owner allow
```

The legacy `mod` and `god` ACE/group names are still recognised through the role `aliases`; remove them from the role configuration once your `server.cfg` is migrated.

### Discord roles

`Config.permissions.discordRoles` (declared in `server/config.lua`, server-only, never sent to clients) maps tiers to Discord role names or, preferably, role IDs:

```lua
Config.permissions.discordRoles = {
    moderator = { 'Moderator' },
    admin = { '123456789012345678' },
    owner = { 'Owner' },
}
```

Role checks use kora_lib's Discord bot and role cache, so `kora_lib_discord_bot_token` (server-only `set`) and `kora_lib_discord_guild_id` must be configured. Missing or stale Discord data fails closed for Discord only; ACE grants keep working. The mapping is editable in the configuration editor and applies live.

### `discord` (Discord roles only)

kora_admin ignores ACEs and temporary grants and uses only `Kora.discord.hasAnyRole` against `discordRoles`. In this mode `/setpermission`, `/revokepermission`, `/granttempaccess` and `/revoketempaccess` refuse with "Manage access through Discord roles while Discord-only mode is active". The configuration editor refuses to enable this mode unless the Discord bot and guild are configured and the role for `Config.configEditor.level` is mapped. See [Discord administration](./features/discord.md).

### Menu level sync

The client keeps a cached tier only to hide or disable menu items. It is requested on resource start (retried up to 15 times) and on `QBCore:Client:OnPlayerLoaded`, refreshed every time `/admin` opens, after grants/revokes, after permission-related configuration changes, and when kora_core fires `kora_core:server:txAdminPermissionChanged`. A stale or forged client level grants nothing.

## Temporary access

Members of `Config.permissions.temporaryGrant.managerRole` (default `admin`) can grant a grantable role up to `maxRole` (default `admin`) for `minMinutes`-`maxMinutes` (1-1440, default 60 in the menu):

```text
/granttempaccess <id> <role> <minutes>
/revoketempaccess <id> <role>
```

Temporary grants:

- live only in kora_admin's memory, keyed by the player's kora_core primary identifier, so they follow a reconnect during the timer;
- expire automatically and are cleared when kora_admin or the server restarts;
- never call `add_principal`, so expiry can never remove a permanent ACE from `server.cfg`;
- are audited (`granttempaccess`, `revoketempaccess`);
- are ignored in Discord-only mode.

Set `maxRole` lower than `managerRole` if you do not want peer-level delegation.

## Runtime ACE grants (owner)

```text
/setpermission <id> <role>
/revokepermission <id> <role>
```

`/setpermission` calls kora_core's `addPermission` export (a runtime `add_principal`; it does not persist past a restart unless `server.cfg` is edited). `/revokepermission` runs `remove_principal identifier.<principalIdentifier>:<id> kora_core.<role>` itself because kora_core has no `removePermission` export; keep `Config.permissions.principalIdentifier` equal to kora_core's `Config.identity.primaryIdentifier` (default `license`).

## Diagnosing permissions

The console-only command `kora_admin_whyperms <server id>` prints the player's identifiers, every ACE object checked with its raw result, and the resolved level. See [Troubleshooting](./troubleshooting.md).

When `/admin` is denied, the player receives a message naming the required role and rank, their highest role and their effective roles.
