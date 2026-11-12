---
title: "Permissions"
sidebar_position: 2
---


# Permissions

The role/rank/gate model every command and the native config editor authorize against. ACE mode is the default; an optional Discord-role mode exists as an alternative source of truth.

Namespace: `Admin.* / exports.kora_admin` · Source: `server/permissions.lua, config.lua (Config.permissions)`

## How it works

Roles are declared in Config.permissions.roles with a unique rank; Admin.levels() validates them at boot (unique ranks, alphanumeric names, a mandatory `user` floor). Config.permissions.gates maps four internal keys (support/mod/admin/god) onto real role ids so commands never hardcode a role name directly. Admin.getLevel resolves ACE or Discord role, then layers any active temporary grant on top if it outranks the resolved role.

## Gate a new command the same way

1. **Pick or add a gate** — Use an existing Config.permissions.gates key, or add your own role in Config.permissions.roles with a unique rank.
2. **Check it in your handler** — Call Admin.checkLevel(source, '&lt;gate or role>') before doing anything, and Admin.respond(source, false, ...) on failure.
3. **Log the action** — Call Admin.log(source, action, targetData, details) so the action shows up in /adminlog.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Rank | A unique integer per role; higher ranks pass every check a lower rank passes. |
| Gate | One of support/mod/admin/god — an internal key in Config.permissions.gates pointed at a real role, used by command registrations instead of a hardcoded role name. |
| Temporary grant | An in-memory, time-limited role bump that is not written to server.cfg and does not survive a kora_admin restart. |

## Functions

The exported checks and grant/revoke helpers other resources can call.

### `Admin.checkLevel(src, required)`

The one permission check every command and menu-data callback uses.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |
| `required` | string | A configured role, or one of the internal gate keys (support/mod/admin/god). |

**Returns**

- **boolean** — true when the resolved rank is ≥ the required rank.

**Example**

```lua
if not Admin.checkLevel(source, 'admin') then
    return Admin.respond(source, false, 'admin level required')
end
```

**Representative console output**

```text
Resolves both sides through Admin.roleRank, so a gate key and a real role name both work as `required`.
```

### `Admin.getLevel(src)`

Resolves a player’s current role: ACE/Discord role plus any active temporary grant, whichever outranks the other.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **string** — a role id, defaulting to `user` when nothing matches.

**Example**

```lua
local level = Admin.getLevel(source)
print('caller is', level)
```

**Representative console output**

```text
Inside an active command/Discord context it instead returns the context’s already-resolved level, so the result stays stable for the duration of that call even if an ACE changes mid-call.
```

### `Admin.grantTemporaryAccess(src, role, minutes)`

Grants an in-memory role for a bounded duration.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Target player server id. |
| `role` | string | Must be grantable and not `user`. |
| `minutes` | integer | Within Config.permissions.temporaryGrant.minMinutes/maxMinutes. |

**Returns**

- **expiresAt** — unix timestamp on success.
- **err** — set (expiresAt nil) when the role or duration is invalid.

**Example**

```lua
local expiresAt, err = Admin.grantTemporaryAccess(targetSrc, 'moderator', 60)
```

**Representative console output**

```text
Survives a reconnect (keyed by the player’s primary identifier) but is cleared by a kora_admin resource restart.
```

### `exports('canEditConfig', function(src) ... end)`

Bridge kora_lib’s native AppShell config editor uses to ask whether a player may edit server configuration.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id. |

**Returns**

- **In Discord mode: boolean, always returned.**
- **Otherwise: `true` when allowed, or `nil` (not `false`) when denied, so kora_lib falls back to its own standalone ACE authorization instead of treating the answer as an explicit refusal.**

**Example**

```lua
local allowed = exports.kora_admin:canEditConfig(source)
```

**Representative console output**

```text
Checks Admin.checkLevel(src, Config.configEditor.level) (default `admin`).
```

### `exports.kora_admin:grantPlaygroundTemporaryAccess(targetSrc, role, minutes)`

Narrow bridge reserved for the `kora_lib-playground` development resource to grant itself moderator/admin for hands-on permission testing.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `targetSrc` | integer | Target player. |
| `role` | string | `moderator` or `admin` only. |
| `minutes` | integer | Grant duration. |

**Returns**

- **expiresAt** — unix timestamp on success.
- **err** — set when the invoking resource is not `kora_lib-playground`, the role is not allowed, or it exceeds Config.permissions.temporaryGrant.maxRole.

**Example**

```lua
-- Only callable from kora_lib-playground; GetInvokingResource() is checked.
exports.kora_admin:grantPlaygroundTemporaryAccess(targetSrc, 'moderator', 15)
```

**Representative console output**

```text
Refuses any other calling resource name outright. Not intended as a general-purpose grant API.
```

### `exports.kora_admin:revokePlaygroundTemporaryAccess(targetSrc, role)`

Revokes a grant made by the playground bridge above.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `targetSrc` | integer | Target player. |
| `role` | string | `moderator` or `admin` only. |

**Returns**

- **boolean revoked.**
- **err** — set when the invoking resource is not kora_lib-playground, or nothing matched.

**Example**

```lua
exports.kora_admin:revokePlaygroundTemporaryAccess(targetSrc, 'moderator')
```

**Representative console output**

```text
Same resource-name restriction as the grant bridge.
```

## Limits and related APIs

Server only. Discord-mode specifics (role id format, how Kora.discord.hasAnyRole resolves them) live in kora_lib/kora_core’s Discord integration, not in this resource’s source.

## Related guides

- [Audit log](./audit.md)
