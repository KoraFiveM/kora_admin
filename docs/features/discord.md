---
title: Discord administration
sidebar_position: 6
---

# Discord administration

kora_admin can register one guild slash command, `/kora_admin`, that runs the existing kora_admin command handlers from Discord. Lua (`server/discord.lua`) owns the staff policy, role checks, validation and audit trail; JavaScript (`server/discord.js`) verifies signed HTTP requests with the bundled Node runtime's standard library. There is no extra bot process and no npm dependency.

The integration is disabled by default (`discord.enabled = false`).

## Setup

1. Create an application and bot in the [Discord Developer Portal](https://discord.com/developers/applications) and install it in your server with the `bot` and `applications.commands` scopes. Give the bot access to your staff channels. Use an application that does not also receive interactions over the gateway: Discord delivers interactions through either the gateway or an HTTP endpoint.
2. Add the bot token as a **server-only** convar (use `set`, never `setr` or `sets`):

   ```cfg
   set kora_lib_discord_bot_token "YOUR_BOT_TOKEN"
   ```

3. Open `/config` (or `/admin`, Server, Configuration) and select `kora_admin`. Under `discord`, enter the application ID, the server (guild) ID, the application public key (64 hex characters) and the allowed staff channel IDs. Leave administration disabled while entering these. If the guild ID is blank, the `kora_lib_discord_guild_id` convar is used; a configured guild ID is written back to that convar so in-game role checks use the same guild. Bot tokens and txAdmin passwords are never editable fields.
4. Under `permissions.discordRoles`, map tiers to Discord role IDs, for example `moderator = { "123..." }`, `admin = { "456..." }`, `owner = { "789..." }`. Higher tiers inherit lower ones. These settings apply live.
5. Expose the endpoint through your HTTPS reverse proxy. kora_admin's HTTP handler answers `POST /discord/interactions` under the resource path, so with FiveM listening locally on port 30120:

   ```nginx
   location = /discord/interactions {
       client_max_body_size 64k;
       proxy_pass http://127.0.0.1:30120/kora_admin/discord/interactions;
       proxy_set_header Host $host;
   }
   ```

   Preserve the raw body and the `X-Signature-Ed25519` / `X-Signature-Timestamp` headers. Set `https://YOUR_DOMAIN/discord/interactions` as the application's Interactions Endpoint URL. Signed verification pings are answered even while administration is disabled.
6. Enable `discord.enabled`. The configuration editor refuses unless the application ID, guild ID and public key are valid and the bot token is set. kora_admin then upserts its `/kora_admin` command for that guild (other commands are not overwritten) and asks kora_lib to sync roles. Check `/kora_admin status` and `/kora_admin commands` in an allowed channel.
7. Optional: set `permissions.mode` to **Discord roles only** to make Discord the sole authority for kora_admin and the configuration editor. Map the role for `Config.configEditor.level` (default `admin`) first; the editor refuses otherwise. See [Permissions](../permissions.md).

## Slash command

| Subcommand | Options | Behaviour |
| --- | --- | --- |
| `status` | - | Online players, uptime, your staff tier, whether a restart is pending. |
| `commands` | - | kora_admin commands your Discord tier may run; commands that need you in game are marked "(in-game)". |
| `run` | `command` (required), `arguments`, `confirm` | Runs a registered kora_admin command handler. |
| `restart` | `reason` (3-256 characters, required), `confirm` (required) | Schedules a full server restart through txAdmin. |

Examples:

```text
/kora_admin run command:heal arguments:12
/kora_admin run command:ban arguments:12 7d "Repeated abuse" confirm:true
/kora_admin restart reason:Maintenance confirm:true
```

`arguments` is split on whitespace; quote values containing spaces with `"` or `'` (backslash escapes the quote). At most 32 arguments and 2000 characters.

Replies are ephemeral and suppress mentions. Only commands in kora_admin's own registry can run; unknown commands, third-party console commands and arbitrary console text cannot.

### Rules for `run`

- The command must not be listed in `discord.disabledCommands`.
- Your tier must satisfy the command's permission. Player-level commands (`/report` etc.) need `support` from Discord.
- Commands in `discord.confirmCommands` need `confirm:true` (default list: `ban`, `unban`, `kick`, `clearinventory`, `restartresource`, `setpermission`, `revokepermission`, `granttempaccess`, `revoketempaccess`).
- `/restartresource` refuses `kora_admin`, `kora_lib` and `monitor`; restart those from txAdmin.
- Commands that need your ped, vehicle, camera, clipboard or UI (`admin`, `config`, `aduty`, `coords`, `vec4`, `health`, `armor`, `selfrevive`, `car`, `dv`, `fix`, `goto`, `bring`, `tpm`, `tpcoords`, `tpback`, `spectate`, `noclip`, `entity`, `deleteentity`, `entitypicker`, `devplacement`, `devzone`, `report`) require the same Discord account to be connected to the game. Otherwise the command runs as an offline actor, and targeted commands need an explicit target.
- If a client-side action gives no completion result, the reply says the command was dispatched.
- Each Discord user may send one command every `discord.cooldownSeconds` (3) seconds.

## Full server restarts

Create a dedicated txAdmin account with the `control.server` permission and add its credentials as server-only convars:

```cfg
set kora_admin_txadmin_url "http://127.0.0.1:40120"
set kora_admin_txadmin_username "discord-service"
set kora_admin_txadmin_password "YOUR_PRIVATE_PASSWORD"
```

The URL must be an origin only; plain HTTP is accepted only for `127.0.0.1`, `localhost` or `[::1]`, remote txAdmin requires HTTPS. Then enable `discord.restartEnabled` and choose `discord.restartRole` (default `owner`) and `discord.restartDelaySeconds` (default 60, 30-3600).

A restart needs a reason and `confirm:true`, and only one Discord restart can be pending. Every player is notified of the countdown. When it expires the requester's roles are fetched again; if access, the guild, the application or the channel policy changed, the restart is cancelled. Otherwise kora_admin logs in to txAdmin (`/auth/password`), keeps its cookie and CSRF token and posts `restart` to `/fxserver/controls`. txAdmin owns shutdown and relaunch. Failures are logged and announced to players and are not retried. The endpoint runs inside FiveM, so it is unavailable while the server is stopped.

## Authorization and audit

- Every request's Ed25519 signature is verified over the timestamp and raw body; timestamps older than 5 minutes, invalid signatures and bodies over 64 KB are rejected.
- Duplicate interaction ids within 10 minutes get the same acknowledgement without repeating the action.
- Requests must come from the configured application, guild and an allowed channel (an empty channel list denies everything). The user's current guild roles are fetched fresh for each request; client-provided roles and in-game ACEs never authorise Discord commands. Missing roles or API errors deny access.
- Results are posted back to the interaction within 120 seconds; after that the reply asks staff to check the audit log before retrying.

Audit actions in `admin_logs`: `discord.command`, `discord.denied`, `discord.result`, `discord.restart.scheduled`, `discord.restart.cancelled`, `discord.restart.executing`, `discord.restart.failed`. Discord actors appear as `Discord <user id>` with Discord, channel and interaction ids in the details. Actions performed through Discord (bans, report replies, ...) use that actor name; license columns keep real player licenses, or NULL for offline actors.

## Settings

All `discord.*` settings and `permissions.mode` are server-scoped and live. See [Configuration](../configuration.md#discord-and-permission-mode-server-only).

## Tests

`test/run.sh` runs the Lua smoke tests and `node --test test/discord.test.js` (Node 18+) for the transport. Live Discord registration, HTTPS delivery and a real txAdmin restart are not covered by these tests.
