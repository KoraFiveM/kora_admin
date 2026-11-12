---
title: Moderation and bans
sidebar_position: 1
---

# Moderation and bans

## Player state tools

`/freeze`, `/god` and `/invisible` are applied on the target's client (`FreezeEntityPosition`, `SetEntityInvincible`, `SetEntityVisible`). Because GTA has no reliable server getter for these, kora_admin remembers the last state it applied per player (cleared on disconnect) so an omitted state toggles. When kora_admin stops, every client resets these three effects so nobody is left frozen, invisible or invincible.

Moderators can use god mode, invisibility and development mode on themselves; targeting another player requires `admin`.

`/devmode` delegates to kora_core's `setDevMode`/`isDevMode` exports; the state is per-player and owned by kora_core.

## Heal and revive

- `/heal` sets the ped to max health. With `Config.heal.restoreNeeds = true` (default) it also sets hunger and thirst to 100 through kora_core `setMetaData`, so HUDs update at once.
- `/revive` clears `isdead` and `inlaststand`, then on the target's client resurrects the ped (only when on foot, so seated players are not launched out of their vehicle), restores max health and fires both `hospital:client:Revive` (qb-ambulancejob) and `kora_ambulance:client:revived` with `100`. If kora_ambulance is started, the server also calls `exports.kora_ambulance:fullRevive(target)` to clear bleeding and wounds. `Config.HealRestoreNeeds` (default `true`) additionally restores hunger and thirst on `/revive`.
- `/selfrevive` and `/health` with a non-zero value while downed use the same revive path for yourself. They never change hunger or thirst.

## Warnings and kicks

`/warn <id> <reason>` notifies the player and writes a `warn` audit entry with the reason. `/warnings <id>` reads those entries back for the player's citizen id. `/kick` logs the reason and drops the player. `Config.moderation.blockSelfTarget` (default `true`) makes `/warn`, `/kick` and `/ban` refuse to target the staff member running them.

## Bans

### Issuing a ban

```text
/ban <target> <duration> [reason]
/ban 12 7d Repeated abuse
/ban ABC12345 perm Cheating
/ban john 2h Spawn killing
```

- `target` is resolved by `Admin.resolveOfflineTarget`: an online server id first, then a citizen id (kora_core `getPlayerByCitizenId`), then the most recently updated non-deleted character whose name contains the text (`players` table). `me` is deliberately not supported.
- For an online player the ban stores their license, Discord and IP identifiers. For an offline player it stores the license and, when recorded in `player_identifiers`, the Discord and IP values.
- `duration` is `<number><unit>` with units from `Config.ban.durationUnits` (`m`, `h`, `d`, `w`) or a word from `Config.ban.durationWords` (`perm`, `permanent`) for a permanent ban (`expire` is NULL).
- The reason defaults to "No reason given". The actor name is stored in `bannedby`.
- If the player is online they are dropped with "Banned: reason".

**Alt detection is advisory.** kora_admin asks kora_core's `findByIdentifier('license', ...)` for other citizen ids sharing the banned license, lists them in the response and in the audit entry (`possibleAlts`), but never bans them automatically.

### Enforcement

`server/ban_enforcement.lua` defers every `playerConnecting` and looks up the newest active row in kora_core's `bans` table matching the player's license, Discord or IP (`expire` NULL or in the future). A banned player is rejected with the reason and expiry date. IP matching is less reliable this early in the handshake than license or Discord.

### Lifting a ban

```text
/unban <license or ban id>
```

`/unban` sets `expire` to the current time on every active matching ban instead of deleting rows, so the reason, issuer and date remain for the audit trail.

### Offline Bans tab

Admins can also ban by citizen id or character name and unban by license or ban id from Server, Offline Bans in `/admin`. Online players are banned from their selected-player Moderation tab.

## Audit trail

Moderation actions are written to `admin_logs` with the actor's license and name, the target's citizen id, license and name, and JSON details. Read them with `/adminlog [action] [target] [page]` or Server, Audit Log in the menu. There is no automatic pruning. See [Database](../database.md).
