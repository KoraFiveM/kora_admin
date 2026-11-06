fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_admin'
-- Keep the legacy resource name resolvable for exports['qbadmin'] callers.
provide 'qbadmin'
author 'Jamie'
version '1.0.0'
description 'Command-driven admin menu -- every action is a command, the NUI just calls ExecuteCommand'

dependency 'kora_lib'
dependency 'kora_core'
dependency 'kora_sql'
dependency 'kora_vehiclekeys'

-- kora_lib strictly before kora_core/qbsql: both extend the Kora table kora_lib's own
-- init.lua creates. kora_core's mirror is what gives us Kora.shared.get/.all for
-- job/gang/vehicle/item picker lists; kora_sql's init.lua is what gives us
-- Kora.sql.* directly for the bans table and admin_logs.
shared_script '@kora_lib/init.lua'
shared_script '@kora_core/init.lua'
shared_script '@kora_sql/init.lua'

shared_scripts {
    'config.lua'
}

-- Invisible client-local bridge for Medal's localhost Auto-Clipping API.
ui_page 'web/medal.html'

files {
    'web/medal.html',
    'web/medal.js'
}

-- Explicit, never globbed -- matches every sibling resource's own rationale.
-- Helpers (permissions/target/response/audit) must load before any
-- commands/*.lua file that calls them; migrate.lua (schema setup) and ban_enforcement.lua
-- have no such dependency and can load anywhere after core.lua.
server_scripts {
    'server/config.lua',
    'server/core.lua',
    'server/command_registry.lua',
    'server/permissions.lua',
    'server/target.lua',
    'server/response.lua',
    'server/audit.lua',
    'server/reports.lua',
    'server/menu_data.lua',
    'server/schema.lua',
    'server/migrate.lua',
    'server/ban_enforcement.lua',
    'server/commands/player.lua',
    'server/commands/moderation.lua',
    'server/commands/teleport.lua',
    'server/commands/economy.lua',
    'server/commands/jobgang.lua',
    'server/commands/appearance.lua',
    'server/commands/vehicle.lua',
    'server/commands/entities.lua',
    'server/commands/development.lua',
    'server/commands/world.lua',
    'server/commands/reports.lua',
    'server/commands/privileged.lua',
    'server/commands/self.lua',
    'server/discord.lua',
    'server/discord.js'
}

-- core.lua before relay/teleport/noclip/spectate (they attach to the Admin
-- table); menu.lua last since it references everything above.
client_scripts {
    'client/core.lua',
    'client/medal.lua',
    'client/development.lua',
    'client/entity_picker.lua',
    'client/relay.lua',
    'client/teleport.lua',
    'client/noclip.lua',
    'client/spectate.lua',
    'client/report_chat.lua',
    'client/menu.lua'
}
