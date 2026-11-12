---
title: "Audit log"
sidebar_position: 3
---


# Audit log

Every state-changing command writes an audit row through Admin.log; /adminlog and the NUI viewer read it back through Admin.queryLogs.

Namespace: `Admin.*` · Source: `server/audit.lua, server/schema.lua (admin_logs table)`

## How it works

Rows store actor license/name, target citizenid/license/name when applicable, a JSON `details` blob, and a timestamp. The schema is created by kora_sql’s ensureTables call in server/migrate.lua.

## Functions

Two functions: write and read.

### `Admin.log(source, action, targetData?, details?)`

Writes one row to `admin_logs` recording an admin action.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `source` | integer | Acting player, or 0 for console. |
| `action` | string | Short action key, e.g. `ban`, `kick`, `setjob`. |
| `targetData?` | table | Resolved target info (citizenid/license/name) when the action has a target. |
| `details?` | table | Extra JSON-encoded context, e.g. `{ reason = ... }`. |

**Returns**

- **No return value documented; failures are not surfaced to the caller.**

**Example**

```lua
Admin.log(source, 'kick', data, { reason = reason })
```

**Representative console output**

```text
Called by nearly every command handler after a successful action.
```

### `Admin.queryLogs({ action?, target?, page? })`

Reads back admin_logs rows for /adminlog, /warnings and similar.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `filter` | table | `{ action?, target?, page? }` — all optional. |

> Beyond the three keys above, the code also accepts `actor` (license or name) and `since` (unix seconds) (`server/audit.lua:31-54`).

**Returns**

- **table[]** — matching rows, newest first, paged by Config.audit.pageSize.

**Example**

```lua
local rows = Admin.queryLogs({ action = 'warn', target = data.citizenid })
```

**Representative console output**

```text
Used both by the chat commands and the NUI audit log viewer.
```

## Limits and related APIs

Server only. No retention/trimming policy was found in the files read for this page — rows accumulate indefinitely unless pruned manually.

## Related guides

- [Permissions](./permissions.md)
