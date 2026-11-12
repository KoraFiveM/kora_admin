---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Admin is a command-driven admin menu: every action — in the NUI menu, in chat, or from Discord — ultimately calls the same server command through `ExecuteCommand`, so there is exactly one authorization and audit path.

## Install Kora Admin

1. **Add the folder** — Place `kora_admin` in your resources directory (on the Kora recipe it is `resources/[kora]/kora_admin`). Other resources (for example kora_lib-playground) call `exports.kora_admin`, so keep the folder name unchanged.

2. **Have the dependencies running** — The manifest declares `kora_lib`, `kora_core`, `kora_sql` and `kora_vehiclekeys` as dependencies. `kora_lib`’s init.lua must load before `kora_core`’s: both extend the shared `Kora` table that `kora_lib` creates. `kora_core` supplies player/job/gang data and the shared job/vehicle/item lookups the menu and commands use; `kora_sql` backs `admin_logs` and `admin_reports`; `kora_vehiclekeys` is used by `/car` and `/veh` to hand out vehicle access (`/givekeys` is provided by kora_vehiclekeys itself, not kora_admin).

3. **Start it after its dependencies** — Start kora_admin after its four dependencies. kora_clothing is not a hard dependency but `/clothingmenu`, `/barbermenu` and `/tattoomenu` only work while it is running.

   ```bash title="server.cfg" {5}
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_vehiclekeys
   ensure kora_admin
   # kora_clothing is optional but required for /clothingmenu, /barbermenu, /tattoomenu
   ensure kora_clothing
   ```

4. **Tables are created automatically** — On start, `server/schema.lua` defines `KoraAdminSchema` (`admin_logs`, `admin_reports`, plus report-message tables) and `server/migrate.lua` waits for `Kora.sql.ready(60000)` then calls `Kora.sql.ensureTables(KoraAdminSchema)`. It is additive only and prints `[kora_admin:schema] schema up to date.` once done. No SQL file has to be run by hand.

5. **Ban enforcement needs the bans table** — `server/ban_enforcement.lua` hooks `playerConnecting` and checks the `bans` table for a matching, unexpired `license`, `discord` or `ip`. That table is created by kora_core’s own SQL migration, not by kora_admin — kora_core must be set up first.

6. **Review config.lua** — Open `config.lua`: it defines every permission role and its rank, the internal gate names (`support`/`mod`/`admin`/`god`) each command checks, the admin-menu keybind, report types, teleport/noclip tuning, and the Medal.tv auto-clipping key. See Configuration for the full list.

## Manifest reference

Load order inside the manifest is deliberate and commented in the source.

```lua title="fxmanifest.lua"
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_admin'

dependency 'kora_lib'
dependency 'kora_core'
dependency 'kora_sql'
dependency 'kora_vehiclekeys'

shared_script '@kora_lib/init.lua'
shared_script '@kora_core/init.lua'

shared_scripts { 'config.lua' }
```

- Server scripts load helpers (`core`, `command_registry`, `permissions`, `target`, `response`, `audit`, `reports`, `menu_data`) before any `server/commands/*.lua` file, since every command module calls into them. `schema.lua`/`migrate.lua` (table setup) and `ban_enforcement.lua` have no such ordering requirement.
- Client scripts load `client/core.lua` first (it owns the shared `Admin` client table), then the feature modules that attach to it (`relay`, `teleport`, `noclip`, `spectate`, `report_chat`), then `client/menu.lua` last since the NUI menu references everything above.
- The manifest also serves `web/medal.html` as a hidden `ui_page` plus `web/medal.js` — an invisible client-local bridge to Medal’s localhost Auto-Clipping HTTP API, unrelated to the main admin-menu NUI.

## If something does not work

- `/admin` answers "Admin menu unavailable..." with your resolved role and rank — see Permissions below; the message tells you exactly which role/rank you are missing.
- Console-only diagnostic: `kora_admin_whyperms <server id>` (run from the server console, not in-game) prints the target’s raw FiveM identifiers and every ACE object `Kora.permissions` checked, with the resolved level — the fastest way to debug a permission grant that is not taking effect.
- Ban checks depend on kora_core’s `bans` table existing; if `kora_core` has not created it yet, `playerConnecting` fails safely open (no admin_logs row is written either way) rather than referencing a table that is not there — confirm `kora_core`’s own migration ran first.

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

## Installation steps (quick form)

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
