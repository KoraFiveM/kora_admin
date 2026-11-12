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

## Requirements

Hard dependencies (from `fxmanifest.lua`):

- [kora_lib](https://github.com/KoraFiveM/kora_lib) - commands, permissions, NUI AppShell, notify, callbacks, config, Discord, raycast, placement, zones, entities
- [kora_core](https://github.com/KoraFiveM/kora_core) - players, money, items, jobs, metadata, development mode, registry mirror
- [kora_sql](https://github.com/KoraFiveM/kora_sql) - database access and schema creation
- [kora_vehiclekeys](https://github.com/KoraFiveM/kora_vehiclekeys) - keys for vehicles spawned with `/car` and `/veh`

Optional integrations (used only when the resource is started):

- [kora_clothing](https://github.com/KoraFiveM/kora_clothing) - `/clothingmenu`, `/barbermenu`, `/tattoomenu` and the My Tools, Appearance tab
- [kora_ambulance](https://github.com/KoraFiveM/kora_ambulance) - full revive (bleeding and wounds cleared) on `/revive`, `/selfrevive` and `/health`
- [kora_weathersync](https://github.com/KoraFiveM/kora_weathersync) - owns `/weather` and `/time` state and the weather list when running
- Medal desktop app on the admin's PC - Medal clips
- txAdmin - Discord-triggered full restarts

## Installation

1. Place the resource in your resources folder and ensure it after its dependencies in `server.cfg`:

   ```cfg
   ensure kora_sql
   ensure kora_lib
   ensure kora_core
   ensure kora_vehiclekeys
   ensure kora_admin
   ```

2. No SQL import is needed. On start, kora_admin waits for kora_sql and creates or updates its own tables (`admin_logs`, `admin_reports`, `admin_report_messages`, `admin_report_reads`) with `Kora.sql.ensureTables`. Bans use kora_core's existing `bans` table. See [Database](./database.md).
3. Grant staff tiers with ACEs (see [Permissions](./permissions.md)):

   ```cfg
   add_ace identifier.license:XXXX kora_core.support allow
   add_principal identifier.license:YYYY group.admin
   add_ace identifier.license:ZZZZ kora_core.owner allow
   ```

4. Optional: set `setr kora_admin_medal_public_key "..."` for [Medal clips](./features/medal-clips.md), and the Discord/txAdmin convars for [Discord administration](./features/discord.md).

kora_admin defines no inventory items.

## Quick examples

```text
/admin                         open the menu (or press F7)
/givemoney 3 cash 500 event    give player 3 500 cash
/giveitem 3 water_bottle 5     give player 3 five water bottles
/tpm                           teleport to your waypoint
/ban 3 7d Repeated abuse       ban player 3 for seven days
/report bug The garage door at Legion does not open
```

Other server resources can run any command as the console, which bypasses the permission check:

```lua
-- server side, e.g. an anti-cheat resource
ExecuteCommand(('ban %d 7d %s'):format(targetSrc, 'Automated detection'))
```

## Documentation

- [Permissions](./permissions.md) - tiers, ACE and Discord resolution, temporary access
- Features
  - [Moderation and bans](./features/moderation-and-bans.md)
  - [Teleport, noclip and spectate](./features/teleport-noclip-spectate.md)
  - [Player reports](./features/reports.md)
  - [Developer tools](./features/developer-tools.md)
  - [Medal clips](./features/medal-clips.md)
  - [Discord administration](./features/discord.md)
- [Commands](./commands.md) - every command with arguments and required tier
- [Admin menu](./ui.md) - workspaces, tabs and selected-player tools
- [Configuration](./configuration.md) - every `config.lua` and server-only option
- [Exports](./exports.md)
- [Events and callbacks](./events.md)
- [Database](./database.md)
- [Troubleshooting](./troubleshooting.md)
