---
title: Troubleshooting
sidebar_position: 11
---

# Troubleshooting

## A staff member cannot open the menu

Run in the server console:

```text
kora_admin_whyperms <server id>
```

It prints the player's identifiers, every ACE object kora_lib checks with the raw `IsPlayerAceAllowed` result, and the resolved level. If nothing matched, the grant must reach the player as `add_ace <principal> kora_core.<level> allow` (or through a `group.<level>` principal). In Discord-only mode ACEs are ignored; check `permissions.discordRoles` and the bot configuration instead.

The player also sees why `/admin` was refused: the required role and rank, their highest role and their effective roles.

## Menu items stay disabled

The client caches its tier for presentation only. If the server never answers, the F8 console shows "the server never answered the permission-level request". Reopening `/admin` always refreshes the tier.

## Admin logs or reports do not work

Look for `[kora_admin:schema]` lines in the server console. "kora_sql never became ready" means the tables were not created; "schema up to date" means they exist.

## A vehicle does not spawn

- "unknown vehicle model": the model is neither in kora_core's shared vehicle list nor known to `Kora.lookup.model`.
- "could not grant vehicle keys": kora_vehiclekeys refused; the spawned vehicle is deleted again.

## Appearance commands fail

"kora_clothing is not running" means kora_clothing is not started; the appearance commands and tab need it.

## Weather or time changes are overridden

When kora_weathersync is started, `/weather` and `/time` delegate to it and kora_admin's own sync is skipped. The Dynamic Weather button runs `/freezeweather`, which kora_admin does not register.

## Medal clips fail

See [Medal clips](./features/medal-clips.md): check `kora_admin_medal_public_key`, that the event IDs match those registered with Medal, and that the Medal app is running on the admin's PC.

## Discord commands are refused

- "Discord administration is unavailable in this server or channel": disabled, wrong application or guild, or the channel is not listed in `discord.channels`.
- "Could not verify your current Discord roles": the bot cannot fetch the member (token, guild access).
- "No staff role is linked to your Discord account": map the user's role in `permissions.discordRoles`.
- On start, "Configure the application ID, server ID and public key in appshell before enabling Discord." or "Could not register /kora_admin" in the console point to missing or invalid settings.

See [Discord administration](./features/discord.md).

## Compatibility notes

- Legacy ACE names `mod` and `god` are accepted as aliases of `moderator` and `owner`.
- Revive fires both `hospital:client:Revive` (qb-ambulancejob) and `kora_ambulance:client:revived`, so either ambulance job clears its death state.
- Open Wardrobe fires `qb-clothing:client:openOutfitMenu`.
- The client re-requests its tier on `QBCore:Client:OnPlayerLoaded`.
