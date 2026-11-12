---
title: Events and callbacks
sidebar_position: 9
---

# Events and callbacks

kora_admin's events are internal plumbing between its own server command handlers and clients. They are documented so you can recognise them; do not trigger them from other resources. Run the matching command instead (see [Exports](./api/integration.md) for `ExecuteCommand`).

## Server events

| Event | Type | Payload | Notes |
| --- | --- | --- | --- |
| `kora_admin:server:requestLevel` | net | - | Internal. The client asks for its cached tier; the server replies with `kora_admin:client:level`. Grants nothing. |

## Client events (internal relays)

All are sent only by kora_admin's server after a permission-checked command or callback.

| Event | Payload | Purpose |
| --- | --- | --- |
| `kora_admin:client:level` | `level` | Cached tier for menu filtering. |
| `kora_admin:client:openMenu` | `level` | Open the admin menu. |
| `kora_admin:client:openReports` | `level, filters` | Open the standalone staff Reports app. |
| `kora_admin:client:openMyReports` | `reportId` or nil | Open the player's My Reports window. |
| `kora_admin:client:reportChanged` | `reportId` | Reload an open staff report screen. |
| `kora_admin:client:myReportChanged` | `reportId, info` | Reload My Reports, or toast a staff reply (`info.kind`, `info.author`, `info.preview`). |
| `kora_admin:client:refreshMenuPlayerState` | `targetSrc` | Refresh the selected-player profile after a state change. |
| `kora_admin:client:freeze` | `state` | Freeze the local ped. |
| `kora_admin:client:kill` | - | Set health to 0. |
| `kora_admin:client:heal` | - | Restore max health. |
| `kora_admin:client:revive` | - | Resurrect and fire ambulance revive events. |
| `kora_admin:client:god` | `state` | Invincibility. |
| `kora_admin:client:invisible` | `state` | Visibility. |
| `kora_admin:client:fix` | - | Repair the current vehicle. |
| `kora_admin:client:enterVehicle` | `netId, seat` | Warp into a server-spawned vehicle. |
| `kora_admin:client:spawnEntity` | `model` | Spawn a static local ped or prop. |
| `kora_admin:client:deleteLastEntity` | - | Remove the last spawned entity. |
| `kora_admin:client:coords` / `kora_admin:client:vec4` | - | Copy coordinates. |
| `kora_admin:client:setHealth` | `percentage` | Set health (0-100%). |
| `kora_admin:client:setArmor` | `value` | Set armour. |
| `kora_admin:client:setWeather` | `weatherType` | Apply weather (no kora_weathersync). |
| `kora_admin:client:setTime` | `hour, minute` | Apply clock (no kora_weathersync). |
| `kora_admin:client:announceSound` | - | Play the announcement sound. |
| `kora_admin:client:teleportTo` | `{ x, y, z, heading? }` | Teleport. |
| `kora_admin:client:tpm` | - | Teleport to waypoint. |
| `kora_admin:client:tpback` | - | Return to the previous position. |
| `kora_admin:client:spectate` | `targetSrc` or nil | Start or stop spectating. |
| `kora_admin:client:noclip` | - | Toggle noclip. |
| `kora_admin:client:startEntityPicker` | - | Start the entity picker. |
| `kora_admin:client:startPlacement` | `model` | Start kora_lib placement. |
| `kora_admin:client:startZoneCreator` | `zoneType` | Start kora_lib zone creator. |

## Server callbacks (Kora.callback)

Used by the NUI. Each callback checks permissions on the server.

| Callback | Required | Arguments | Returns |
| --- | --- | --- | --- |
| `kora_admin:menuPlayers` | support | - | Online players (id, name, job, ping). |
| `kora_admin:menuPlayerProfile` | support | `target` | Profile; license, Discord and permission only for admins. |
| `kora_admin:menuRoles` | admin | - | Jobs and gangs with ordered grades. |
| `kora_admin:menuResources` | admin | - | Resources with state and Git branch/commit. |
| `kora_admin:menuAuditLog` | admin | `{ action?, target?, page? }` | Audit rows with UTC `created_text`. |
| `kora_admin:menuReports` | `reports.staffLevel` | `{ status?, type?, reporter?, page? }` | Report queue. |
| `kora_admin:menuReport` | `reports.staffLevel` | `id, { live? }` | Report with conversation; marks it read. |
| `kora_admin:myReports` | report chat enabled | `page` | The caller's own reports (rate limited 20 per 10 s). |
| `kora_admin:myReport` | report owner | `id, { live? }` | One own report with conversation (30 per 10 s). |
| `kora_admin:reportChatSend` | owner or staff | `id, message` | Sends a chat message (10 per 10 s plus `chat.rateLimit`). |

## Events kora_admin listens to

| Event | Side | Use |
| --- | --- | --- |
| `playerConnecting` | server | Ban enforcement (deferral). |
| `playerDropped` | server | Clears per-player state, report cooldowns and chat rate limits. |
| `kora_core:server:playerLoaded` | server | Re-sends weather/time to joining players (without kora_weathersync). |
| `kora_core:server:txAdminPermissionChanged` | server | Re-syncs the player's tier; accepted only from kora_core. |
| `kora_core:registry:snapshotAll` | client | Refreshes vehicle/job/gang pickers in an open menu. |
| `QBCore:Client:OnPlayerLoaded` | client | Re-requests the cached tier. |

## Events kora_admin triggers in other resources

| Event | Side | When |
| --- | --- | --- |
| `hospital:client:Revive` | client (local) | On revive, for qb-ambulancejob compatibility. |
| `kora_ambulance:client:revived` | client (local) | On revive, payload `100` (health percent). |
| `kora_clothing:client:openNearestShop` | client (local) | My Tools, Appearance shop buttons (`clothing`, `barber`, `tattoo`). |
| `kora_clothing:client:openAdminSession` | client (local) | Full Administrative Styling. |
| `qb-clothing:client:openOutfitMenu` | client (local) | Open Wardrobe. |
| `kora_lib:client:configOpened` | client (net) | `/config`, payload `'kora_admin'`. |
| `chatMessage` | client (net) | Multi-line `[Admin]` chat output. |
