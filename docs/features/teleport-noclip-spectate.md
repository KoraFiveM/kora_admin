---
title: Teleport, noclip and spectate
sidebar_position: 2
---

# Teleport, noclip and spectate

## Teleport

All teleports end in one client primitive, `Admin.teleportTo` (`client/teleport.lua`). The server only decides who moves and where:

| Command | Who moves | Destination |
| --- | --- | --- |
| `/goto <id>` | you | the target's current position |
| `/bring <id>` | the target | your current position |
| `/tpcoords <coordinates>` | you | the given coordinates (optional heading) |
| `/tpm` | you | your waypoint, ground-snapped |
| `/tpback` | you | your position before your last teleport |
| `/sendback <id>` | the target | their position before their last teleport |

The algorithm follows txAdmin's teleport:

1. The screen fades out (`Config.teleport.fadeTime` ms) and the ped, or its vehicle, is frozen.
2. The ped is moved (keeping its vehicle) to the destination x/y at `Config.teleport.waypointLaunchHeight` and the client waits while `IsEntityWaitingForWorldCollision` is true, up to `Config.teleport.collisionTimeout` ms.
3. For `/tpm` only, the ground is found by probing downward from z 1500 through stacked surfaces (a bridge deck, then the street below) to the lowest reachable one, retrying `groundZAttempts` times `groundZRetryDelay` ms apart. If no ground is found (open water, world edge), the player stays at the launch height.
4. The ped is placed at the final z, a vehicle is set on the ground properly, the heading is applied if one was given, the entity is unfrozen and the screen fades back in.

Every teleport records the previous position in a single slot, which `/tpback` and `/sendback` restore.

`/tpcoords` accepts:

```text
/tpcoords 123.4 456.7 78.9
/tpcoords 123.4, 456.7, 78.9, 90.0
/tpcoords vec3(123.4, 456.7, 78.9)
/tpcoords vector4(123.4, 456.7, 78.9, 90.0)
```

A fourth component is the destination heading, not a z offset. `/vec4` and `/coords` copy your current position in these formats.

## Noclip

`/noclip` (admin) toggles a free-fly mode on your own client. The ped (or the vehicle you are in) is frozen with collision off, made invincible and invisible, and moved every frame along the gameplay camera direction, so the mouse keeps looking around.

| Key | Action |
| --- | --- |
| W / S | forward / back along the camera direction |
| A / D | strafe left / right (`adMode = 'strafe'`) or turn the view (`adMode = 'turn'`, at `turnSpeed` degrees per frame) |
| Space / Ctrl | up / down |
| Shift | faster (`fastMultiplier`) |
| Alt | precision (`slowMultiplier`) |

Native movement and vehicle controls are blocked while noclip runs. kora_admin sends a `noclip:hud` NUI message when noclip starts and stops. Noclip is disabled automatically when the resource stops. `adMode` and `turnSpeed` are registered as live settings in the configuration editor.

## Spectate

`/spectate <id>` puts your client in spectator mode on the target (waiting up to 3 seconds for their ped to stream in). Running it with no id, selecting Spectate on the same player again, or pressing the `kora_admin_spectate_stop` key mapping (default `BACK`) stops it. With `Config.spectate.showHint` a "Stop spectating" kora_lib text UI hint with that key is shown.

The menu's My Tools, Movement tab has a Stop Spectating button that is enabled only while spectating.
