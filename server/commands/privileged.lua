-- /restartresource, /setpermission, /revokepermission -- god only. Anything
-- here can either take the server offline or mint another privileged
-- account, which is exactly the blast radius this tier exists to contain.

local OPTS_GOD = { permission = 'god', checkPermission = Admin.checkLevel, resource = 'qbadmin' }

QB.commands.add('restartresource', 'Restart a resource', { { name = 'name' } }, true, function(source, args)
    local resourceName = args[1]
    if not resourceName or resourceName == '' then return Admin.respond(source, false, 'resource name required') end
    if GetResourceState(resourceName) == 'missing' then return Admin.respond(source, false, 'no such resource') end

    Admin.log(source, 'restartresource', nil, { resource = resourceName })
    ExecuteCommand(('restart %s'):format(resourceName))
    Admin.respond(source, true, ('Restarted %s'):format(resourceName))
end, OPTS_GOD)

QB.commands.add('setpermission', 'Grant a player a permission level (runtime only)', { { name = 'id' }, { name = 'level' } }, true,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local level = args[2]
        if not level or not Config.permissions.ranks[level] or level == 'user' then
            return Admin.respond(source, false, 'level must be one of mod/admin/god')
        end

        -- exports.qbcore:addPermission is a runtime add_principal grant only --
        -- it does not persist past a restart unless server.cfg is also
        -- edited. That is qbcore's own documented behavior, not a bug here.
        exports.qbcore:addPermission(targetSrc, level)
        Admin.log(source, 'setpermission', data, { level = level })
        Admin.respond(source, true, ('Granted %s to %s (runtime only -- edit server.cfg to persist)'):format(level, data.name))
    end, OPTS_GOD)

QB.commands.add('revokepermission', "Revoke a player's permission level (runtime only)", { { name = 'id' }, { name = 'level' } }, true,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local level = args[2]
        if not level or not Config.permissions.ranks[level] or level == 'user' then
            return Admin.respond(source, false, 'level must be one of mod/admin/god')
        end

        -- No removePermission counterpart exists in qbcore/modules/permissions
        -- -- this mirrors exports.qbcore:addPermission's own identifier
        -- formatting by hand (candidate to upstream into qbcore itself later,
        -- see docs.md). Config.permissions.principalIdentifier must be kept in
        -- sync with qbcore's own Config.identity.primaryIdentifier.
        local license = exports.qbcore:primary(targetSrc)
        if not license then return Admin.respond(source, false, 'could not resolve target identifier') end

        ExecuteCommand(('remove_principal identifier.%s:%s qbcore.%s'):format(
            Config.permissions.principalIdentifier, license:gsub('^%w+:', ''), level))
        Admin.log(source, 'revokepermission', data, { level = level })
        Admin.respond(source, true, ('Revoked %s from %s (runtime only)'):format(level, data.name))
    end, OPTS_GOD)
