# kora_admin agent guide

kora_admin is a command-driven admin menu for the Kora FiveM framework: every privileged action is a kora_lib chat command, and the `/admin` NUI, Discord slash command and other resources all run those same command handlers. Layout: `config.lua` (shared config) and `server/config.lua` (server-only Discord settings); `server/` holds permissions, target resolution, audit log, reports, ban enforcement, schema/migration, menu callbacks, the Discord integration (`discord.lua`, `discord.js`) and one file per command group in `server/commands/`; `client/` holds the AppShell menu, relays, teleport, noclip, spectate, entity picker, report chat and the Medal bridge (`web/`); smoke tests live in `test/` and QA scenarios in `tests/`.

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first for an overview of features, configuration, commands, exports, events and database usage.

Docs layout: `docs/index.md` (overview and documentation map), `installation.md` (requirements, manifest, install steps), `how-to-use.md` (permissions model, menu, reports, auditing, Discord relay, examples), `commands.md` (every command; update it when a command changes), `api/` (`index.md`, `permissions.md`, `audit.md`, `integration.md`: Admin functions and exports, including the former exports page), and topic pages `permissions.md`, `ui.md`, `configuration.md`, `events.md`, `database.md`, `troubleshooting.md` and `features/*.md`. Feature and behaviour changes must update the matching docs in the same change.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.

## Shared contribution standards

Read [CONTRIBUTING.md](CONTRIBUTING.md) before editing. Humans and agents follow
the same Kora standards and self-contained local Lua checks. Preserve the domain
constraints above and in module guides; record policy conflicts explicitly.

Copyright © 2026 Kora Framework (new contribution guidance).
