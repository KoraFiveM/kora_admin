-- Server-only qbadmin configuration.
-- Discord role names and IDs are authorization policy and must never be sent
-- to clients through the shared config bundle.

Config.permissions.discordRoles = {
    -- Optional Discord role names or IDs for each tier. Leave this empty for
    -- ACE-only authorization. Matching any role listed for a tier grants that
    -- tier; qblib then applies the normal rank cascade. Role IDs are safest
    -- because Discord permits duplicate role names. This uses qblib's bot role
    -- cache and fails closed when the bot/cache/player identifier is unavailable.
    -- ACEs, including group.admin, are always checked first and remain active.
    --
    -- moderator = { 'Moderator' },
    -- admin = { '123456789012345678' },
    -- owner = { 'Owner' },
}

-- This file is server-only even though qbadmin's base Config is shared. Keep
-- optional Discord role mappings out of every client-side configuration
-- snapshot while still making them visible to the owner-only editor.
if QB and QB.config and QB.config.extend then
    QB.config.extend({
        permissions = {
            discordRoles = QB.config.map(Config.permissions.discordRoles,
                QB.config.list({}, QB.config.string('', { minLength = 1 }))),
        },
    }, { scope = 'server' })
end
