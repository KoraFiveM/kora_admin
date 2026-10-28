-- /restartresource, /setpermission, /revokepermission -- owner only. Anything
-- here can either take the server offline or mint an unrestricted runtime
-- account, which is exactly the blast radius this tier exists to contain.

local OPTS_GOD = { permission = 'god', checkPermission = Admin.checkLevel, resource = 'kora_admin' }
local OPTS_TEMPORARY_ACCESS = {
    permission = Config.permissions.temporaryGrant.managerRole,
    checkPermission = Admin.checkLevel,
    resource = 'kora_admin',
}

Admin.addCommand('restartresource', 'Restart a resource', { { name = 'name' } }, true, function(source, args)
    local resourceName = args[1]
    if not resourceName or resourceName == '' then return Admin.respond(source, false, 'resource name required') end
    if not resourceName:match('^[%w_-]+$') then return Admin.respond(source, false, 'invalid resource name') end
    if GetResourceState(resourceName) == 'missing' then return Admin.respond(source, false, 'no such resource') end

    Admin.log(source, 'restartresource', nil, { resource = resourceName })
    ExecuteCommand(('restart %s'):format(resourceName))
    Admin.respond(source, true, ('Restarted %s'):format(resourceName))
end, OPTS_GOD)

Admin.addCommand('setpermission', 'Grant a player a permission level (runtime only)', { { name = 'id' }, { name = 'level' } }, true,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local level = Admin.resolveRole(args[2] or '')
        if not level or not Admin.isRole(level) or level == 'user' then
            return Admin.respond(source, false, 'invalid permission level')
        end

        -- exports.kora_core:addPermission is a runtime add_principal grant only --
        -- it does not persist past a restart unless server.cfg is also
        -- edited. That is kora_core's own documented behavior, not a bug here.
        exports.kora_core:addPermission(targetSrc, level)
        Admin.log(source, 'setpermission', data, { level = level })
        Admin.respond(source, true, ('Granted %s to %s (runtime only -- edit server.cfg to persist)'):format(level, data.name))
    end, OPTS_GOD)

Admin.addCommand('revokepermission', "Revoke a player's permission level (runtime only)", { { name = 'id' }, { name = 'level' } }, true,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local level = Admin.resolveRole(args[2] or '')
        if not level or not Admin.isRole(level) or level == 'user' then
            return Admin.respond(source, false, 'invalid permission level')
        end

        -- No removePermission counterpart exists in kora_core/modules/permissions
        -- -- this mirrors exports.kora_core:addPermission's own identifier
        -- formatting by hand (candidate to upstream into kora_core itself later,
        -- see docs.md). Config.permissions.principalIdentifier must be kept in
        -- sync with kora_core's own Config.identity.primaryIdentifier.
        local license = exports.kora_core:primary(targetSrc)
        if not license then return Admin.respond(source, false, 'could not resolve target identifier') end

        ExecuteCommand(('remove_principal identifier.%s:%s qbcore.%s'):format(
            Config.permissions.principalIdentifier, license:gsub('^%w+:', ''), level))
        Admin.log(source, 'revokepermission', data, { level = level })
        Admin.respond(source, true, ('Revoked %s from %s (runtime only)'):format(level, data.name))
    end, OPTS_GOD)

-- Timed grants do not use add_principal. They live only in kora_admin memory,
-- cannot remove a server.cfg ACE on expiry, and follow the player across a
-- reconnect because they are keyed by kora_core's primary identifier.
Admin.addCommand('granttempaccess', 'Grant a player a temporary admin role',
    { { name = 'id' }, { name = 'role' }, { name = 'minutes' } }, true,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local role = Admin.resolveRole(args[2] or '')
        if not Admin.canManageTemporaryAccess(source, role) then
            return Admin.respond(source, false, 'that temporary role cannot be granted')
        end

        local minutes = Admin.finiteNumber(args[3], Config.permissions.temporaryGrant.minMinutes,
            Config.permissions.temporaryGrant.maxMinutes, true)
        if not minutes then
            return Admin.respond(source, false, ('duration must be %d-%d minutes'):format(
                Config.permissions.temporaryGrant.minMinutes, Config.permissions.temporaryGrant.maxMinutes))
        end

        local expiresAt, grantErr = Admin.grantTemporaryAccess(targetSrc, role, minutes)
        if not expiresAt then return Admin.respond(source, false, grantErr) end

        Admin.syncLevel(targetSrc)
        Admin.log(source, 'granttempaccess', data, { role = role, minutes = minutes, expires_at = expiresAt })
        Admin.respond(source, true, ('Granted %s access to %s for %d minute%s'):format(
            Admin.roleLabel(role), data.name, minutes, minutes == 1 and '' or 's'))
    end, OPTS_TEMPORARY_ACCESS)

Admin.addCommand('revoketempaccess', 'Revoke a player\'s temporary admin role',
    { { name = 'id' }, { name = 'role' } }, true,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local role = Admin.resolveRole(args[2] or '')
        if not Admin.canManageTemporaryAccess(source, role) then
            return Admin.respond(source, false, 'that temporary role cannot be revoked')
        end

        if not Admin.revokeTemporaryAccess(targetSrc, role) then
            return Admin.respond(source, false, ('%s has no temporary %s access'):format(data.name, Admin.roleLabel(role)))
        end

        Admin.syncLevel(targetSrc)
        Admin.log(source, 'revoketempaccess', data, { role = role })
        Admin.respond(source, true, ('Revoked temporary %s access from %s'):format(Admin.roleLabel(role), data.name))
    end, OPTS_TEMPORARY_ACCESS)
