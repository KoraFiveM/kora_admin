fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbadmin'
author 'Jamie'
version '1.0.0'
description 'Command-driven admin menu -- every action is a command, the NUI just calls ExecuteCommand'

dependency 'qblib'
dependency 'qbcore'
dependency 'qbsql'
dependency 'qbvehiclekeys'

-- qblib strictly before qbcore/qbsql: both extend the QB table qblib's own
-- init.lua creates. qbcore's mirror is what gives us QB.shared.get/.all for
-- job/gang/vehicle/item picker lists; qbsql's init.lua is what gives us
-- QB.sql.* directly for the bans table and admin_logs.
shared_script '@qblib/init.lua'
shared_script '@qbcore/init.lua'
shared_script '@qbsql/init.lua'

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
-- commands/*.lua file that calls them; migrate.lua and ban_enforcement.lua
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
    'client/menu.lua'
}
