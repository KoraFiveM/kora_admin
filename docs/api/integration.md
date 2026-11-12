---
title: "Discord and other integration points"
sidebar_position: 4
---


# Discord and other integration points

A relay that lets kora_admin's own signed Discord slash command (`/kora_admin`, verified in `server/discord.js`) execute kora_admin commands using the same handlers, permission checks and audit trail as chat. It is not an API for other resources: `discordDispatch` returns `false` unless kora_admin itself invokes it (`server/discord.lua:270`). See [Discord administration](../features/discord.md).

Namespace: `exports.kora_admin` · Source: `server/discord.lua, server/discord.js`

## How it works

`server/discord.js` verifies the signed Discord HTTP interaction and calls `discordDispatch` with the JSON-encoded interaction (`encoded`); `server/discord.lua` applies staff policy (`Admin.handleDiscordInteraction`) and runs the matching `Admin.commands` handler. The callback receives a JSON string (`json.encode` of the result, or `{ ok = false, message = 'Discord administration failed' }` on error). No external bot resource is involved.

## Functions

Two exports.

### `exports('discordSettings', function() ... end)`

Returns configuration an external Discord bot resource needs to talk to kora_admin.

**Parameters**



**Returns**

- **table** — correction: it returns a JSON string (`json.encode`) of the non-secret transport settings `enabled`, `publicKey` and `applicationId` (`server/discord.lua:262-265`).

**Example**

```lua
local settings = exports.kora_admin:discordSettings()
```

**Representative console output**

```text
Source: server/discord.lua.
```

### `exports('discordDispatch', function(encoded, callback) ... end)`

Runs a kora_admin command on behalf of an external Discord bot, through the same Admin.commands handlers used by chat.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `encoded` | string | Encoded command request; exact format unclear from the files read for this page. |
| `callback` | function | Invoked with the result; exact signature unclear from the files read for this page. |

**Returns**

- **No return value documented here.**

**Example**

```lua
exports.kora_admin:discordDispatch(encoded, function(result) print(result) end)
```

**Representative console output**

```text
Goes through the same permission checks and admin_logs auditing as an in-game command. Wire format and the external bot resource itself were out of scope for this page — confirm both against server/discord.lua and server/discord.js directly before integrating.
```

## Limits and related APIs

Server only. Treat discordSettings/discordDispatch’s exact payload shapes as unclear/unconfirmed.

## Related guides

- [Audit log](./audit.md)

## Command bridge, exports and internal exports

kora_admin's public integration surface is its commands: another server resource can run any of them as the console with `ExecuteCommand`, which skips the permission check but still validates arguments, performs the action and writes the audit log (actor `console`).

```lua
ExecuteCommand('givemoney 3 cash 500 event-reward')
ExecuteCommand(('kick %d %s'):format(src, 'AFK'))
```

All exports below are server-side. kora_admin has no client exports.

### canEditConfig

```lua
local allowed = exports.kora_admin:canEditConfig(source)
```

Bridge used by kora_lib's configuration app to honour kora_admin's editor permission.

| Parameter | Type | Description |
| --- | --- | --- |
| `source` | integer | Player server id. |

Returns `true` when the player holds `Config.configEditor.level`. When the player does not: returns `false` in Discord-only mode, and `nil` in compatible mode so kora_lib keeps its own ACE authorization.

### grantPlaygroundTemporaryAccess

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

### revokePlaygroundTemporaryAccess

```lua
local ok, err = exports.kora_admin:revokePlaygroundTemporaryAccess(targetSrc, 'moderator')
```

Same caller restriction. Returns `true`, or `false` and an error string (for example when no matching temporary grant exists).

### discordSettings

```lua
local json = exports.kora_admin:discordSettings()
```

Returns a JSON string with the non-secret transport settings `enabled`, `publicKey` and `applicationId`. Used by `server/discord.js`.

### Internal exports

These exist so the JavaScript and Lua halves of the Discord integration can talk to each other. They reject or are not meant for other resources.

| Export | Defined in | Behaviour |
| --- | --- | --- |
| `discordDispatch(encoded, callback)` | `server/discord.lua` | Runs a verified interaction; returns `false` unless invoked by kora_admin itself. |
| `discordRestartReady()` | `server/discord.js` | `true` when txAdmin username and password convars are set. |
| `discordRestart(callback)` | `server/discord.js` | Requests a txAdmin restart; returns `false` unless invoked by kora_admin itself. |

### Exports kora_admin uses

| Resource | Exports |
| --- | --- |
| kora_core (server) | `primary`, `getPlayers`, `getPlayer`, `getPlayerByCitizenId`, `getIdentifiers`, `findByIdentifier`, `getJob`, `getMetaData`, `setMetaData`, `isDevMode`, `setDevMode`, `addMoney`, `removeMoney`, `setMoney`, `addItem`, `removeItem`, `clearInventory`, `setJob`, `setGang`, `setJobDuty`, `createVehicle`, `addPermission`, `allShared` |
| kora_core (client) | `isDevMode`, `getPlayerData`, `onPlayerDataChange` |
| kora_vehiclekeys | `giveKeys(target, plate, true)` |
| kora_clothing (optional) | `OpenAdminSession(target, service)` |
| kora_ambulance (optional) | `fullRevive(target)` |
| kora_weathersync (optional) | `setWeather`, `setTime`, `getWeatherTypes` |
