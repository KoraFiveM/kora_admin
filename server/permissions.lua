-- Admin.checkLevel -- the one permission check every command and menu-data
-- callback uses. qblib owns ACE + optional Discord resolution and ranked
-- cascading, so the menu has no parallel permission implementation.
--
-- No src == 0 special-case is needed: QB.commands.add's own wrapper already
-- exempts the server console from calling checkPermission at all.

local LEVELS = { 'god', 'admin', 'mod', 'user' }
local OPTIONS = {
    prefix = 'qbcore',
    discordRoles = Config.permissions.discordRoles,
}

---@param src integer
---@return string
function Admin.getLevel(src)
    return QB.permissions.getLevel(src, LEVELS, OPTIONS)
end

---@param src integer
---@param required string  -- 'mod'|'admin'|'god'
---@return boolean
function Admin.checkLevel(src, required)
    return QB.permissions.hasLevel(src, required, LEVELS, OPTIONS)
end

-- Server-console-only diagnostic for "my ACEs look right but I have no
-- permissions". Deliberately NOT a QB.commands.add registration: every one of
-- those is permission-gated, and a player who cannot pass a permission check is
-- exactly who this needs to answer for. Console-only (source 0) keeps it
-- unreachable from in-game chat, so it grants nothing and leaks nothing.
RegisterCommand('qbadmin_whyperms', function(source, args)
    if source ~= 0 then return end

    local target = tonumber(args[1])
    if not target then
        print('^3[qbadmin]^7 usage: qbadmin_whyperms <server id>')
        return
    end
    if GetPlayerName(target) == nil then
        print(('^1[qbadmin]^7 no player online with server id %d.'):format(target))
        return
    end

    print(('^5[qbadmin]^7 permission report for %s (id %d)'):format(GetPlayerName(target), target))

    -- Printed first because this is where these reports almost always end:
    -- an add_principal line naming an identifier the player does not actually
    -- hold. Compare these against the add_principal lines in server.cfg.
    print('  identifiers:')
    for index = 0, GetNumPlayerIdentifiers(target) - 1 do
        print(('    %s'):format(GetPlayerIdentifier(target, index)))
    end

    local checks, resolved = QB.permissions.explain(target, LEVELS, OPTIONS)
    print('  ace checks (object -> raw value returned by IsPlayerAceAllowed):')
    for _, check in ipairs(checks) do
        print(('    %-24s -> %s (%s)%s')
            :format(check.object, check.raw, check.type, check.allowed and '  <= GRANTS ' .. check.level or ''))
    end

    print(('  resolved level: %s'):format(resolved))
    if resolved == 'user' then
        print('^3  no ACE matched. The grant must reach this player as: add_ace <a principal above> qbcore.<level> allow^7')
    end
end, true)
