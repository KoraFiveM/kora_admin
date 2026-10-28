# Discord administration

`/qbadmin` adds Discord control to the existing admin commands. Lua keeps the
command handlers, role gates, input validation and audit trail. JavaScript
verifies signed requests using the bundled Node runtime and its standard
library. There is no additional bot process or npm dependency.

The integration is disabled by default. Existing commands, ACE permissions,
exports and database schemas retain their compatible defaults.

## Setup

1. Create an application and bot in the
   [Discord Developer Portal](https://discord.com/developers/applications).
   Install it in your server with the `bot` and `applications.commands` scopes.
   Give the bot access to your staff channels. Use a separate application from
   a gateway bot: Discord delivers interactions through either the gateway or
   an HTTP endpoint.
2. Add the bot token to your private server configuration with a **server-only**
   convar. Use `set`, never `setr` or `sets`:

   ```cfg
   set qblib_discord_bot_token "YOUR_BOT_TOKEN"
   ```

3. Open `/config`, or **Admin → Server → Configuration**, and select `kora_admin`.
   Enter the Discord application ID, server ID, application public key, and
   allowed staff channel IDs. Leave administration disabled while entering
   these values. The public key is safe to display. Bot tokens and txAdmin
   passwords are never registered as editable fields.
4. Under `permissions.discordRoles`, map each tier to Discord **role IDs**:
   `moderator = { "123..." }`, `admin = { "456..." }`, `owner = { "789..." }`.
   Higher tiers inherit lower tiers. Existing role names and legacy aliases
   remain supported; IDs avoid duplicate or renamed role names. These settings
   apply live and are saved in `config.local.lua`.
5. Expose the interaction endpoint through your existing HTTPS reverse proxy.
   With FiveM listening locally on port 30120, add this nginx location to an
   existing TLS server block:

   ```nginx
   location = /discord/interactions {
       client_max_body_size 64k;
       proxy_pass http://127.0.0.1:30120/kora_admin/discord/interactions;
       proxy_set_header Host $host;
   }
   ```

   Adjust the upstream address/port. Preserve the raw body and the
   `X-Signature-Ed25519` / `X-Signature-Timestamp` headers. Set
   `https://YOUR_DOMAIN/discord/interactions` as the application's
   **Interactions Endpoint URL**. Signed verification pings work while
   administration is disabled.
6. Enable **Discord administration** in appshell. The server upserts its one
   guild slash command without overwriting other commands. Check
   `/qbadmin status`, then `/qbadmin commands`, in an allowed staff channel.
7. Select **Discord roles only** under `permissions.mode` when Discord should
   be the sole authority for kora_admin and the configuration editor. Map the
   editor tier (`owner` by default) first. This mode ignores ACE and temporary
   grants and disables commands that mint/revoke separate permissions.
   Compatible mode keeps existing ACE authorization and adds Discord roles.
   Other resources retain their own permission contracts.

## Commands

| Command | Behavior |
| --- | --- |
| `/qbadmin status` | Online players, uptime, staff tier and pending restart state. |
| `/qbadmin commands` | Commands your Discord tier can use. |
| `/qbadmin run command:heal arguments:12` | Calls the existing `/heal 12` handler. |
| `/qbadmin run command:ban arguments:12 7d "Repeated abuse" confirm:true` | Runs the existing ban handler after confirmation. |
| `/qbadmin restart reason:Maintenance confirm:true` | Announces a countdown, then requests a full restart through txAdmin. |

Replies are private and suppress mentions. Unknown commands and arbitrary
console text cannot be executed. Configure disabled commands, confirmation
requirements, staff channels, cooldown and restart policy in appshell. An
empty staff-channel list denies every staff action.

Player-independent actions work while staff are offline. Tools needing their
ped, vehicle, camera, clipboard or UI require that same Discord account to be
connected to the game. Targeted commands need an explicit target while staff
are offline. Client actions are reported as dispatched when their existing
handler has no completion result.

The registered kora_admin handlers form the catalog; third-party console
commands are not automatically granted remote access. Restarting `kora_admin`,
`kora_lib` or `monitor` through Discord is refused because it interrupts the
transport or txAdmin. Use txAdmin for those maintenance actions.

## Full server restarts

Create a dedicated txAdmin account with `control.server`. Add its credentials
to your private server configuration:

```cfg
set qbadmin_txadmin_url "http://127.0.0.1:40120"
set qbadmin_txadmin_username "discord-service"
set qbadmin_txadmin_password "YOUR_PRIVATE_PASSWORD"
```

Remote txAdmin endpoints require HTTPS. Then enable **Allow full server
restarts** in appshell and choose the minimum tier and countdown, which
default to owner and 60 seconds. A reason and explicit confirmation are
required. Only one Discord countdown can be pending. Roles are fetched again
when it expires; removed access or changed guild/channel policy cancels it.

The adapter logs in to txAdmin, retains its cookie and CSRF token, and calls
its restart control. txAdmin owns shutdown and relaunch, including the
framework's existing shutdown-save hooks. The adapter never executes a shell
command or kills the process itself. Failed or unconfirmed requests are
logged and are not automatically retried.

The endpoint runs inside FiveM and is unavailable while the server is stopped.
Start a stopped server through txAdmin. Discord control returns after the
restarted resource loads.

## Authorization and audit

Every HTTP request verifies Discord's Ed25519 signature over the raw body and
timestamp. Invalid or stale signatures are rejected. Duplicate signed
interaction IDs receive the same acknowledgement without repeating actions.
Staff requests check the application, guild, channel, current membership and
freshly fetched roles. Client-provided roles and in-game ACEs never authorize
Discord commands. Missing roles or API errors deny access.

Command attempts/results and restarts use the existing `admin_logs`. Actors
appear as `Discord <user ID>`, with Discord/channel/interaction IDs in request
details. Existing action records, bans and report replies use that actor name.
License columns retain real player licenses, or NULL for offline actors.

The local `discordDispatch` and `discordRestart` exports accept calls only
from this resource. `discordSettings` exposes non-secret transport settings.
`canEditConfig(source)` lets kora_lib's native appshell honor Discord owners and
role-only policy while retaining the compatible ACE editor path.

Run `test/run.sh` for Lua and transport checks (standalone JavaScript tests use
Node 18+). Live Discord registration, HTTPS delivery and a real txAdmin
restart require deployment credentials and are not exercised by these tests.

References: [Discord interactions](https://docs.discord.com/developers/interactions/receiving-and-responding),
[FiveM HTTP handlers](https://github.com/citizenfx/fivem/blob/master/ext/native-decls/SetHttpHandler.md),
[txAdmin permissions](https://github.com/citizenfx/txAdmin/blob/master/docs/permissions.md).
