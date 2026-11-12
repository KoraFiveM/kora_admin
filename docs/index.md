---
title: kora_admin
sidebar_position: 1
---

# kora_admin

kora_admin is a command-driven admin menu for the Kora framework (kora_lib, kora_core, kora_sql). Every privileged action is a chat command registered through kora_lib's `Kora.commands`. The `/admin` NUI menu is not a separate code path: after collecting a target and parameters, it builds the same command string a human would type and runs it with `ExecuteCommand`. Typed, clicked and Discord-dispatched actions therefore share the same permission check, argument parsing, handler, audit-log entry and notification.

## Features

- **Admin menu (`/admin`, default key `F7`)** - a kora_lib AppShell app with five workspaces: Players, Reports, My Tools, Server and Developer Tools. Items are filtered by your tier for presentation only; every command re-checks permissions on the server. See [Admin menu](./ui.md).
- **Player-first workflow** - select an online player to open a fresh server-built profile (identity, job/gang, balances, health/armour, needs, state, ping) plus tabbed tools for movement, health, moderation, appearance, economy, roles/access and spawning.
- **Ranked permission tiers** - `support`, `moderator`, `admin`, `owner` (configurable, cascading) resolved by kora_lib from ACEs and optional Discord roles, plus memory-only temporary grants. See [Permissions](./permissions.md).
- **Moderation and bans** - warn (with history), kick, freeze, kill, heal, revive, god mode, invisibility, development mode, and persistent online/offline bans enforced on connect, with advisory alt-account detection. See [Moderation and bans](./features/moderation-and-bans.md).
- **Teleport, noclip and spectate** - txAdmin-style ground-snapped waypoint teleport, coordinate teleport (accepts pasted `vec3`/`vector4` literals), goto/bring/send back, a free-fly noclip and spectating. See [Teleport, noclip and spectate](./features/teleport-noclip-spectate.md).
- **Player reports with live chat** - `/report` creates a persistent report; staff manage a queue (claim, resolve, dismiss, reopen) and chat with the reporter live, with unread counts and sent/delivered/seen ticks. See [Player reports](./features/reports.md).
- **Economy, inventory, jobs and vehicles** - money and item management, job/gang/duty changes, vehicle spawning with automatic keys, persistent garage vehicles, nearby/radius vehicle deletion and repair. See [Commands](./commands.md).
- **World control** - announcements with a sound, weather and clock (delegated to kora_weathersync when it runs), time presets. See [Commands](./commands.md#world-and-server).
- **Developer tools** - entity picker (aimed-entity model names), kora_lib placement and zone creators, static local ped/prop spawning, and a Resources table showing each resource's Git branch and commit. See [Developer tools](./features/developer-tools.md).
- **Medal clips** - save a highlight from the clicking admin's local Medal recorder. See [Medal clips](./features/medal-clips.md).
- **Discord administration** - an optional signed `/kora_admin` slash command that runs the same command handlers, plus full server restarts through txAdmin. See [Discord administration](./features/discord.md).
- **Configuration editor entry point** - `/config` and the Server, Configuration tab open kora_lib's configuration app for resources that registered a schema.
- **Durable audit log** - most actions are written to the `admin_logs` table and can be read with `/adminlog` or the Audit Log tab. See [Database](./database.md).

## Documentation map

- [Installation](./installation.md) - dependencies, manifest reference, requirements, ACE setup and quick install steps
- [How to use](./how-to-use.md) - permissions model, admin menu, reports, auditing, Discord relay and quick examples
- [Commands](./commands.md) - every command with arguments, results, tiers and audit names
- API reference
  - [API reference index](./api/index.md) - modules and namespaces
  - [Permissions API](./api/permissions.md) - `Admin.checkLevel`, `Admin.getLevel`, temporary grants and the permission exports
  - [Audit log API](./api/audit.md) - `Admin.log` and `Admin.queryLogs`
  - [Discord and other integration points](./api/integration.md) - Discord exports, the `ExecuteCommand` bridge and exports kora_admin uses
- [Permissions](./permissions.md) - tiers, ACE and Discord resolution, temporary access
- [Admin menu](./ui.md) - workspaces, tabs and selected-player tools
- [Configuration](./configuration.md) - every `config.lua` and server-only option
- [Events and callbacks](./events.md) - internal events and callbacks
- [Database](./database.md) - tables and audit log schema
- [Troubleshooting](./troubleshooting.md) - common problems
- Features
  - [Moderation and bans](./features/moderation-and-bans.md)
  - [Teleport, noclip and spectate](./features/teleport-noclip-spectate.md)
  - [Player reports](./features/reports.md)
  - [Developer tools](./features/developer-tools.md)
  - [Medal clips](./features/medal-clips.md)
  - [Discord administration](./features/discord.md)
