---
title: Database
sidebar_position: 9
---

# Database

kora_admin declares its tables in `server/schema.lua` and creates or updates them on start (`server/migrate.lua`) with kora_sql's `Kora.sql.ensureTables`, after waiting up to 60 seconds for kora_sql. Schema warnings are printed with the `[kora_admin:schema]` prefix. No manual import is needed. All tables use `utf8mb4_unicode_ci`.

## admin_logs

The durable audit trail. kora_core's own `logEvent` is an in-memory ring buffer, so kora_admin keeps its own table.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | int unsigned, auto increment | primary key |
| `action` | varchar(50) | action name, see below |
| `actor_license` | varchar(60), nullable | NULL for console and offline Discord actors |
| `actor_name` | varchar(100) | default `console`; `Discord <user id>` for Discord actions |
| `target_citizenid` | varchar(50), nullable | |
| `target_license` | varchar(60), nullable | |
| `target_name` | varchar(100), nullable | |
| `details` | longtext, nullable | JSON |
| `created_at` | timestamp | default `CURRENT_TIMESTAMP` |

Indexes: `action`, `actor_license`, `target_citizenid`, `created_at`.

Actions written by kora_admin:

- Moderation: `warn`, `kick`, `ban` (details: `banId`, `reason`, `expire`, `possibleAlts`), `unban`, `freeze`, `kill`, `heal`, `revive`, `god`, `invisible`, `devmode`, `sethunger`, `setthirst`
- Movement: `goto`, `bring`, `sendback`, `spectate`, `noclip`
- Economy: `givemoney`, `removemoney`, `setmoney`, `giveitem`, `removeitem`, `clearinventory`
- Roles: `setjob`, `setgang`, `setduty`
- Appearance: `clothingmenu`, `barbermenu`, `tattoomenu`
- Vehicles and entities: `car`, `veh`, `givevehicle`, `dv`, `fix`, `entity`, `entityfor`, `deleteentity`
- Developer: `entitypicker`, `devplacement`, `devzone`
- World: `announce`, `weather`, `time`, `restartresource`
- Access: `setpermission`, `revokepermission`, `granttempaccess`, `revoketempaccess`
- Reports: `report_reply` (staff replies), `report_claim`, `report_resolved`, `report_dismissed`, `report_open`
- Discord: `discord.command`, `discord.denied`, `discord.result`, `discord.restart.scheduled`, `discord.restart.cancelled`, `discord.restart.executing`, `discord.restart.failed`

There is no automatic pruning. Example query from another resource:

```lua
local rows = Kora.sql.query(
    'SELECT * FROM `admin_logs` WHERE `action` = ? ORDER BY `created_at` DESC LIMIT 20', { 'ban' })
for _, row in ipairs(rows) do
    print(row.actor_name, 'banned', row.target_name, row.details)
end
```

## admin_reports

| Column | Type | Notes |
| --- | --- | --- |
| `id` | int unsigned, auto increment | primary key |
| `type` | varchar(32) | report type id |
| `status` | varchar(16) | `open` (default), `claimed`, `resolved`, `dismissed` |
| `reporter_source` | int, nullable | server id at submission (not trusted later) |
| `reporter_citizenid` | varchar(50), nullable | |
| `reporter_license` | varchar(60), nullable | ownership check for players |
| `reporter_name` | varchar(100) | |
| `message` | text | |
| `claimed_by_license` | varchar(60), nullable | |
| `claimed_by_name` | varchar(100), nullable | |
| `resolution` | text, nullable | resolution or dismissal note |
| `created_at` | timestamp | default `CURRENT_TIMESTAMP` |
| `updated_at` | timestamp | updated on change |
| `closed_at` | timestamp, nullable | |

Indexes: (`status`, `updated_at`), (`type`, `updated_at`), (`reporter_license`, `updated_at`).

## admin_report_messages

| Column | Type | Notes |
| --- | --- | --- |
| `id` | int unsigned, auto increment | primary key |
| `report_id` | int unsigned | foreign key to `admin_reports.id`, `ON DELETE CASCADE` |
| `author_license` | varchar(60), nullable | |
| `author_name` | varchar(100) | |
| `author_role` | varchar(16) | `staff` or `player` |
| `message` | text | |
| `created_at` | timestamp | default `CURRENT_TIMESTAMP` |

Index: (`report_id`, `created_at`).

## admin_report_reads

Read and delivery markers for the report chat.

| Column | Type | Notes |
| --- | --- | --- |
| `report_id` | int unsigned | primary key part; foreign key to `admin_reports.id`, `ON DELETE CASCADE` |
| `reader_license` | varchar(60) | primary key part; a player or staff license, or `@staff` for staff-side delivery |
| `last_message_id` | int unsigned | newest message the reader has opened (default 0) |
| `delivered_message_id` | int unsigned, nullable | newest message that reached the reader's client |
| `updated_at` | timestamp | updated on change |

## Tables owned by other resources

| Table | Owner | Use |
| --- | --- | --- |
| `bans` | kora_core | `/ban` inserts `name`, `license`, `discord`, `ip`, `reason`, `expire` (Unix time, NULL = permanent), `bannedby`; `/unban` updates `expire`; connection checks read `id`, `reason`, `expire`. |
| `players` | kora_core | Offline ban lookup by name (`citizenid`, `license`, `name`, `deleted_at`, `last_updated`). |
| `player_identifiers` | kora_core | Offline ban lookup of `discord` and `ip` identifiers (`citizenid`, `kind`, `value`). |

Personal vehicles from `/givevehicle` are written by kora_core's `createVehicle` export, not directly by kora_admin.
