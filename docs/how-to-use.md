---
title: "How to use"
sidebar_position: 3
---


# How to use

Every feature — the NUI menu, chat commands, and Discord relay commands — runs through the same `Admin.addCommand` registrations in `server/commands/*.lua`, so permission checks, audit logging and player-facing responses are identical no matter which surface was used.

## Permissions: roles, ranks and gates

Every role is declared in `Config.permissions.roles` with a unique numeric `rank` (higher outranks lower) and optional ACE `aliases`. Shipped roles: `user` (rank 0, not grantable), `support` (10), `moderator`/`mod` alias (20), `admin` (30), `owner`/`god` alias (40, not grantable). Commands do not check a role name directly — they check one of four internal gate keys in `Config.permissions.gates` (`support`, `mod`, `admin`, `god`), each of which currently points at `support`, `moderator`, `admin` and `owner` respectively. Re-point a gate at a custom role to retune every command that uses it without editing any command file.

- `Admin.getLevel(src)` resolves a player’s role: in ACE mode it walks `Kora.permissions.getLevel` against every role/alias ACE object (prefix `kora_core`, e.g. `kora_core.admin`), highest rank first; in `Config.permissions.mode = 'discord'` mode it instead checks `Kora.discord.hasAnyRole` against `Config.permissions.discordRoles[level]` for each role, top rank first, defaulting to `user` if nothing matches.
- Temporary, in-memory grants (`/granttempaccess`) are layered on top: if a player’s temporary grant outranks their resolved ACE/Discord role, the temporary role wins. Temporary grants are keyed by `Config.permissions.principalIdentifier` (default `license`) and are cleared by a kora_admin restart — they are not written to `server.cfg`.
- `Admin.checkLevel(src, required)` is the single check every command and the `canEditConfig` export uses: `true` only when the resolved rank is ≥ the required gate’s rank.
- In Discord-only mode (`Config.permissions.mode = 'discord'`), the four access-management commands (`/setpermission`, `/revokepermission`, `/granttempaccess`, `/revoketempaccess`) are disabled outright — `Admin.accessCommandAllowed` refuses them — since access is meant to be managed entirely through Discord roles in that mode.

## The admin menu

`/admin` (default key `F7`, rebindable in FiveM Settings) requires at least `support`. The server answers with `kora_admin:client:openMenu` and the caller’s resolved level; the client builds the NUI menu from `server/menu_data.lua` and, per the manifest’s own description, every menu action simply calls `ExecuteCommand` for the matching command above — there is no separate "menu-only" code path or permission check.

- A denied `/admin` does not get the generic permission error: its `notify` callback calls `Admin.menuAccessDeniedMessage`, which lists the caller’s resolved role, its rank, and every gate they could still pass, so staff can self-diagnose a missing grant.
- Selecting a player in the menu shows additional tabs (bans, warnings, job/gang, money, etc.); `Config.menu.playerProfileHeaderBack` controls whether those tabs show a "&lt;" header that clears the selection instead of a full menu close.

## Reports

Players submit reports with `/report <type> <message>` (type is one of `Config.reports.types`, e.g. `player`, `bug`, `exploit`). Staff at or above `Config.reports.staffLevel` (default `support`) see and act on the shared queue; everyone else only ever sees their own reports.

- With `Config.reports.command.ui = true`, `/admin`-eligible staff running `/reports` get the full NUI Reports screen instead of a chat list; players get a "My Reports" chat window when `Config.reports.chat.playerUi` is also true.
- Two-way chat on a report (`Config.reports.chat.enabled`) lets the reporter and staff exchange messages inline; disabling it falls back to one-shot `Manage > Reply to Reporter` and a plain `/reportreply`.
- `Config.reports.liveUpdates` pushes new reports/replies/claims to every staff member with the screen open in real time; off, staff only see changes after reopening the screen.

## Auditing

Every state-changing command calls `Admin.log(source, action, targetData, details)`, which inserts into `admin_logs` with the actor’s identity (resolved via `Admin.actorIdentity`), the target’s identity when there is one, and a JSON `details` blob. `/adminlog [action] [target] [page]` and the NUI audit log viewer both read it back, paged by `Config.audit.pageSize`.

## Discord relay

`server/discord.lua` exposes `discordSettings` and `discordDispatch` exports, used by kora_admin's own `server/discord.js` (a signed `/kora_admin` slash command; other resources cannot call `discordDispatch`, `server/discord.lua:270`), so Discord can run kora_admin commands as if typed in chat, going through the exact same `Admin.commands` handlers (and therefore the same permission checks and audit log) as a player. The actor identity for a Discord-originated command resolves to the Discord request’s name instead of a `source`/license pair; see `Admin.actorIdentity` and `Admin.commandContext`.

- The `encoded` argument is the JSON-encoded verified Discord interaction and `callback` receives a JSON string result (`server/discord.lua:269-276`). The full setup is in [Discord administration](./features/discord.md).

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
