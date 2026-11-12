---
title: Exports
sidebar_position: 7
---

# Exports

kora_admin's public integration surface is its commands: another server resource can run any of them as the console with `ExecuteCommand`, which skips the permission check but still validates arguments, performs the action and writes the audit log (actor `console`).

```lua
ExecuteCommand('givemoney 3 cash 500 event-reward')
ExecuteCommand(('kick %d %s'):format(src, 'AFK'))
```

All exports below are server-side. kora_admin has no client exports.

## canEditConfig

```lua
local allowed = exports.kora_admin:canEditConfig(source)
```

Bridge used by kora_lib's configuration app to honour kora_admin's editor permission.

| Parameter | Type | Description |
| --- | --- | --- |
| `source` | integer | Player server id. |

Returns `true` when the player holds `Config.configEditor.level`. When the player does not: returns `false` in Discord-only mode, and `nil` in compatible mode so kora_lib keeps its own ACE authorization.

## grantPlaygroundTemporaryAccess

```lua
local expiresAt, err = exports.kora_admin:grantPlaygroundTemporaryAccess(targetSrc, 'moderator', 30)
```

Only callable by the resource named `kora_lib-playground` (development tooling); every other caller gets `nil, 'this temporary-access bridge is reserved for kora_lib-playground'`.

| Parameter | Type | Description |
| --- | --- | --- |
| `targetSrc` | integer | Player server id. |
| `role` | string | `moderator` or `admin` only, and not above `temporaryGrant.maxRole`. |
| `minutes` | integer | Within `temporaryGrant.minMinutes`-`maxMinutes`. |

Returns the expiry as a Unix timestamp, or `nil` and an error string.

## revokePlaygroundTemporaryAccess

```lua
local ok, err = exports.kora_admin:revokePlaygroundTemporaryAccess(targetSrc, 'moderator')
```

Same caller restriction. Returns `true`, or `false` and an error string (for example when no matching temporary grant exists).

## discordSettings

```lua
local json = exports.kora_admin:discordSettings()
```

Returns a JSON string with the non-secret transport settings `enabled`, `publicKey` and `applicationId`. Used by `server/discord.js`.

## Internal exports

These exist so the JavaScript and Lua halves of the Discord integration can talk to each other. They reject or are not meant for other resources.

| Export | Defined in | Behaviour |
| --- | --- | --- |
| `discordDispatch(encoded, callback)` | `server/discord.lua` | Runs a verified interaction; returns `false` unless invoked by kora_admin itself. |
| `discordRestartReady()` | `server/discord.js` | `true` when txAdmin username and password convars are set. |
| `discordRestart(callback)` | `server/discord.js` | Requests a txAdmin restart; returns `false` unless invoked by kora_admin itself. |

## Exports kora_admin uses

| Resource | Exports |
| --- | --- |
| kora_core (server) | `primary`, `getPlayers`, `getPlayer`, `getPlayerByCitizenId`, `getIdentifiers`, `findByIdentifier`, `getJob`, `getMetaData`, `setMetaData`, `isDevMode`, `setDevMode`, `addMoney`, `removeMoney`, `setMoney`, `addItem`, `removeItem`, `clearInventory`, `setJob`, `setGang`, `setJobDuty`, `createVehicle`, `addPermission`, `allShared` |
| kora_core (client) | `isDevMode`, `getPlayerData`, `onPlayerDataChange` |
| kora_vehiclekeys | `giveKeys(target, plate, true)` |
| kora_clothing (optional) | `OpenAdminSession(target, service)` |
| kora_ambulance (optional) | `fullRevive(target)` |
| kora_weathersync (optional) | `setWeather`, `setTime`, `getWeatherTypes` |
