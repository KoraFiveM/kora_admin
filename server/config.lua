-- Server-only kora_admin configuration.
-- Discord role names and IDs are authorization policy and must never be sent
-- to clients through the shared config bundle.

Config.permissions.discordRoles = {
    -- Optional Discord role names or IDs for each tier. Leave this empty for
    -- ACE-only authorization. Matching any role listed for a tier grants that
    -- tier; kora_lib then applies the normal rank cascade. Role IDs are safest
    -- because Discord permits duplicate role names. This uses kora_lib's bot role
    -- cache and fails closed when the bot/cache/player identifier is unavailable.
    -- ACEs, including group.admin, are always checked first and remain active.
    --
    -- moderator = { 'Moderator' },
    -- admin = { '123456789012345678' },
    -- owner = { 'Owner' },
}

-- This file is server-only even though kora_admin's base Config is shared. Keep
-- optional Discord role mappings out of every client-side configuration
-- snapshot while still making them visible to the owner-only editor.
if QB and QB.config and QB.config.extend then
    QB.config.extend({
        permissions = {
            mode = QB.config.enum('ace_discord', { options = {
                { value = 'ace_discord', label = 'ACE and Discord (compatible)' },
                { value = 'discord', label = 'Discord roles only' },
            }, live = true, description = 'Discord-only access ignores ACE and temporary grants for qbadmin. Map an owner role before switching.' }),
            discordRoles = QB.config.map(Config.permissions.discordRoles,
                QB.config.list({}, QB.config.string('', { minLength = 1 })),
                { live = true, advanced = false, description = 'Map each staff tier to Discord role IDs. Higher tiers inherit lower tiers.' }),
        },
        discord = {
            enabled = QB.config.boolean(false, { live = true, label = 'Enable Discord administration' }),
            applicationId = QB.config.string('', { live = true, label = 'Discord application ID' }),
            guildId = QB.config.string('', { live = true, label = 'Discord server ID',
                description = 'Uses kora_lib_discord_guild_id (or the deprecated qblib_discord_guild_id) when blank. This is also the guild used for in-game role checks.' }),
            publicKey = QB.config.string('', { live = true, label = 'Discord application public key',
                description = 'The public key from the Developer Portal verifies signed slash command requests. This is safe to display.' }),
            channels = QB.config.list({}, QB.config.string('', { minLength = 1 }), {
                live = true, advanced = false, label = 'Staff channel IDs',
                description = 'Slash commands are accepted only in these channels. An empty list denies every staff action.' }),
            disabledCommands = QB.config.list({}, QB.config.string('', { minLength = 1 }), {
                live = true, advanced = false, label = 'Commands disabled in Discord' }),
            confirmCommands = QB.config.list({ 'ban', 'unban', 'kick', 'clearinventory', 'restartresource',
                'setpermission', 'revokepermission', 'granttempaccess', 'revoketempaccess' },
                QB.config.string('', { minLength = 1 }), { live = true, advanced = false,
                    label = 'Commands requiring confirmation' }),
            cooldownSeconds = QB.config.integer(3, { live = true, min = 1, max = 60,
                label = 'Seconds between staff commands' }),
            restartEnabled = QB.config.boolean(false, { live = true, label = 'Allow full server restarts' }),
            restartDelaySeconds = QB.config.integer(60, { live = true, min = 30, max = 3600,
                label = 'Restart countdown (seconds)' }),
            restartRole = QB.config.string('owner', { live = true, label = 'Minimum restart tier' }),
        },
    }, { scope = 'server' })
end
