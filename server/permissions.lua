-- Admin.checkLevel -- the one permission check every command and menu-data
-- callback uses. ACE/Discord resolution remains in kora_lib; kora_admin adds its
-- deliberately in-memory temporary grants on top.

local function permissionOptions()
    return { prefix = 'kora_core', discordRoles = Config.permissions.discordRoles }
end

Admin.temporaryGrants = Admin.temporaryGrants or {}

local function roleDefinition(role)
    return Config.permissions.roles[role]
end

---@param role string
---@return string
function Admin.resolveRole(role)
    return Config.permissions.gates[role] or role
end

---@return string[] -- highest rank first; kora_lib requires `user` as its floor
function Admin.levels()
    local levels = {}
    local ranks = {}
    for role, definition in pairs(Config.permissions.roles) do
        assert(type(role) == 'string' and role:match('^[%w_-]+$'), 'Permission role names must be alphanumeric, _ or -.')
        assert(type(definition) == 'table' and type(definition.rank) == 'number',
            ('Permission role %q needs a numeric rank.'):format(role))
        assert(not ranks[definition.rank], ('Permission role rank %s is used by both %q and %q.'):format(
            definition.rank, role, ranks[definition.rank]))
        ranks[definition.rank] = role
        levels[#levels + 1] = role
    end
    assert(roleDefinition('user'), 'Config.permissions.roles must include user.')
    table.sort(levels, function(a, b)
        local aRank, bRank = roleDefinition(a).rank, roleDefinition(b).rank
        return aRank == bRank and a < b or aRank > bRank
    end)
    return levels
end

---@return string[] levels -- real role IDs plus configured legacy ACE aliases
---@return table<string, string> canonical -- resolved role for each candidate
function Admin.aceLevels()
    local candidates, canonical = {}, {}
    for _, role in ipairs(Admin.levels()) do
        candidates[#candidates + 1] = { id = role, role = role, rank = roleDefinition(role).rank }
        canonical[role] = role
        local aliases = roleDefinition(role).aliases
        if aliases ~= nil then
            assert(type(aliases) == 'table', ('Permission role %q aliases must be an array.'):format(role))
            for _, alias in ipairs(aliases) do
                assert(type(alias) == 'string' and alias:match('^[%w_-]+$'),
                    ('Permission alias for %q must be alphanumeric, _ or -.'):format(role))
                assert(not canonical[alias], ('Permission role or alias %q is declared more than once.'):format(alias))
                candidates[#candidates + 1] = { id = alias, role = role, rank = roleDefinition(role).rank }
                canonical[alias] = role
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        -- Prefer the real role over an alias at the same rank so getLevel
        -- reports the current name when both ACEs are present.
        if a.role == b.role then
            if a.id == a.role then return b.id ~= b.role end
            if b.id == b.role then return false end
            return a.id < b.id
        end
        return a.id < b.id
    end)

    local levels = {}
    for index, candidate in ipairs(candidates) do levels[index] = candidate.id end
    return levels, canonical
end

---@param role string
---@return number|nil
function Admin.roleRank(role)
    local definition = roleDefinition(Admin.resolveRole(role))
    return definition and definition.rank or nil
end

---@param role string
---@return boolean
function Admin.isRole(role)
    return roleDefinition(role) ~= nil
end

---@param role string
---@return string
function Admin.roleLabel(role)
    local definition = roleDefinition(role)
    return definition and definition.label or role
end

local function primaryKey(src)
    local primary = exports.kora_core:primary(src)
    return primary and primary:lower() or nil
end

local function syncIdentifier(key)
    for _, src in ipairs(exports.kora_core:getPlayers()) do
        if primaryKey(src) == key then Admin.syncLevel(src) end
    end
end

local function temporaryLevel(src)
    local key = primaryKey(src)
    if not key then return nil end

    local grants = Admin.temporaryGrants[key]
    if not grants then return nil end

    local now, highest = os.time(), nil
    for role, expiresAt in pairs(grants) do
        if expiresAt <= now or not Admin.isRole(role) then
            grants[role] = nil
        elseif not highest or Admin.roleRank(role) > Admin.roleRank(highest) then
            highest = role
        end
    end
    if next(grants) == nil then Admin.temporaryGrants[key] = nil end
    return highest
end

---@param src integer
---@return string
function Admin.getLevel(src)
    local context = Admin.commandContext and Admin.commandContext(src)
    if context then return context.level end
    local aceLevels, canonical = Admin.aceLevels()
    if Config.permissions.mode == 'discord' then
        for _, level in ipairs(aceLevels) do
            local roles = Config.permissions.discordRoles[level]
            if roles and #roles > 0 then
                local ok, allowed = pcall(Kora.discord.hasAnyRole, src, roles)
                if ok and allowed == true then return canonical[level] end
            end
        end
        return 'user'
    end
    local held = canonical[Kora.permissions.getLevel(src, aceLevels, permissionOptions())] or 'user'
    local temporary = temporaryLevel(src)
    if temporary and Admin.roleRank(temporary) > Admin.roleRank(held) then return temporary end
    return held
end

-- The native appshell uses this bridge for Discord owners. Returning nil in
-- compatible mode retains kora_lib's existing standalone ACE authorization.
exports('canEditConfig', function(src)
    local allowed = Admin.checkLevel(src, Config.configEditor.level)
    if Config.permissions.mode == 'discord' then return allowed end
    if allowed then return true end
end)

---@param src integer
---@param required string -- a configured role or an internal Config.permissions.gates key
---@return boolean
function Admin.checkLevel(src, required)
    local requiredRank = Admin.roleRank(required)
    local heldRank = Admin.roleRank(Admin.getLevel(src))
    return requiredRank ~= nil and heldRank ~= nil and heldRank >= requiredRank
end

---Build an understandable access summary for a denied admin-menu request.
---Roles are effective tiers: a higher tier inherits every tier below it.
---@param src integer
---@param required string
---@return string
function Admin.menuAccessDeniedMessage(src, required)
    local requiredRole = Admin.resolveRole(required)
    local heldRole = Admin.getLevel(src)
    local heldRank = Admin.roleRank(heldRole) or 0
    local effectiveRoles = {}

    for _, role in ipairs(Admin.levels()) do
        if Admin.roleRank(role) <= heldRank then
            effectiveRoles[#effectiveRoles + 1] = role
        end
    end
    table.sort(effectiveRoles, function(a, b) return Admin.roleRank(a) < Admin.roleRank(b) end)

    local labels = {}
    for index, role in ipairs(effectiveRoles) do labels[index] = Admin.roleLabel(role) end

    return ('Admin menu unavailable: requires %s (rank %d). Your highest role is %s (rank %d); effective roles: %s.')
        :format(
            Admin.roleLabel(requiredRole), Admin.roleRank(requiredRole) or 0,
            Admin.roleLabel(heldRole), heldRank,
            #labels > 0 and table.concat(labels, ', ') or 'none'
        )
end

---@param src integer
---@param role string
---@return boolean
function Admin.canManageTemporaryAccess(src, role)
    local settings = Config.permissions.temporaryGrant
    local maxRank = Admin.roleRank(settings.maxRole)
    local roleConfig = roleDefinition(role)
    return Admin.checkLevel(src, settings.managerRole)
        and maxRank ~= nil
        and roleConfig ~= nil
        and roleConfig.grantable ~= false
        and role ~= 'user'
        and roleConfig.rank <= maxRank
end

---@param src integer
---@param role string
---@param minutes integer
---@return integer|nil expiresAt
---@return string|nil err
function Admin.grantTemporaryAccess(src, role, minutes)
    local settings = Config.permissions.temporaryGrant
    if not Admin.isRole(role) or role == 'user' or roleDefinition(role).grantable == false then
        return nil, Kora.lang('error.invalid_or_non_grantable_role')
    end
    if type(minutes) ~= 'number' or minutes ~= math.floor(minutes)
        or minutes < settings.minMinutes or minutes > settings.maxMinutes then
        return nil, ('duration must be %d-%d minutes'):format(settings.minMinutes, settings.maxMinutes)
    end

    local key = primaryKey(src)
    if not key then return nil, Kora.lang('error.could_not_resolve_target_identifier_2') end
    local expiresAt = os.time() + minutes * 60
    local grants = Admin.temporaryGrants[key] or {}
    Admin.temporaryGrants[key] = grants
    grants[role] = expiresAt

    SetTimeout(minutes * 60 * 1000, function()
        local current = Admin.temporaryGrants[key]
        if current and current[role] == expiresAt and os.time() >= expiresAt then
            current[role] = nil
            if next(current) == nil then Admin.temporaryGrants[key] = nil end
            syncIdentifier(key)
        end
    end)
    return expiresAt
end

---@param src integer
---@param role string
---@return boolean
function Admin.revokeTemporaryAccess(src, role)
    local key = primaryKey(src)
    local grants = key and Admin.temporaryGrants[key]
    if not grants or not grants[role] then return false end
    grants[role] = nil
    if next(grants) == nil then Admin.temporaryGrants[key] = nil end
    return true
end

---@param src integer
function Admin.syncLevel(src)
    TriggerClientEvent('kora_admin:client:level', src, Admin.getLevel(src))
end

-- The playground is a development-only, trusted consumer.  It needs a narrow
-- bridge for hands-on permission tests, but must not gain a general-purpose
-- way to mint owner access or mutate durable ACE configuration.  Its own
-- server callback supplies the player-facing ACE gate; this export confines
-- the cross-resource contract to the two explicitly testable staff tiers.
local PLAYGROUND_RESOURCE = 'kora_lib-playground'
local PLAYGROUND_ROLES = { moderator = true, admin = true }

---@param targetSrc integer
---@param role string
---@param minutes integer
---@return integer|nil expiresAt
---@return string|nil err
exports('grantPlaygroundTemporaryAccess', function(targetSrc, role, minutes)
    if GetInvokingResource() ~= PLAYGROUND_RESOURCE then
        return nil, Kora.lang('error.this_temporary_access_bridge_is_reserved')
    end
    if not PLAYGROUND_ROLES[role] then
        return nil, Kora.lang('error.playground_may_grant_only_moderator_or')
    end
    local maxRank = Admin.roleRank(Config.permissions.temporaryGrant.maxRole)
    if not maxRank or Admin.roleRank(role) > maxRank then
        return nil, Kora.lang('error.that_role_is_disabled_by_kora')
    end

    local expiresAt, err = Admin.grantTemporaryAccess(targetSrc, role, minutes)
    if expiresAt then Admin.syncLevel(targetSrc) end
    return expiresAt, err
end)

---@param targetSrc integer
---@param role string
---@return boolean revoked
---@return string|nil err
exports('revokePlaygroundTemporaryAccess', function(targetSrc, role)
    if GetInvokingResource() ~= PLAYGROUND_RESOURCE then
        return false, Kora.lang('error.this_temporary_access_bridge_is_reserved_2')
    end
    if not PLAYGROUND_ROLES[role] then
        return false, Kora.lang('error.playground_may_revoke_only_moderator_or')
    end
    if not Admin.revokeTemporaryAccess(targetSrc, role) then
        return false, Kora.lang('error.the_player_has_no_matching_temporary')
    end

    Admin.syncLevel(targetSrc)
    return true
end)

-- Console-only so this diagnostic remains available when the permission
-- configuration itself is what prevents an administrator from using commands.
RegisterCommand('kora_admin_whyperms', function(source, args)
    if source ~= 0 then return end

    local target = tonumber(args[1])
    if not target then
        print('^3[kora_admin]^7 usage: kora_admin_whyperms <server id>')
        return
    end
    if GetPlayerName(target) == nil then
        print(('^1[kora_admin]^7 no player online with server id %d.'):format(target))
        return
    end

    print(('^5[kora_admin]^7 permission report for %s (id %d)'):format(GetPlayerName(target), target))
    print('  identifiers:')
    for index = 0, GetNumPlayerIdentifiers(target) - 1 do
        print(('    %s'):format(GetPlayerIdentifier(target, index)))
    end

    local levels, canonical = Admin.aceLevels()
    local checks, matchedLevel = Kora.permissions.explain(target, levels, permissionOptions())
    local resolved = canonical[matchedLevel] or 'user'
    print('  ace checks (object -> raw value returned by IsPlayerAceAllowed):')
    for _, check in ipairs(checks) do
        print(('    %-24s -> %s (%s)%s')
            :format(check.object, check.raw, check.type, check.allowed and '  <= GRANTS ' .. check.level or ''))
    end

    print(('  resolved level: %s'):format(resolved))
    if resolved == 'user' then
        print('^3  no ACE matched. The grant must reach this player as: add_ace <a principal above> kora_core.<level> allow^7')
    end
end, true)
