-- Admin.checkLevel -- the one permission check every command and menu-data
-- callback uses. ACE/Discord resolution remains in qblib; qbadmin adds its
-- deliberately in-memory temporary grants on top.

local OPTIONS = {
    prefix = 'qbcore',
    discordRoles = Config.permissions.discordRoles,
}

Admin.temporaryGrants = Admin.temporaryGrants or {}

local function roleDefinition(role)
    return Config.permissions.roles[role]
end

---@param role string
---@return string
function Admin.resolveRole(role)
    return Config.permissions.gates[role] or role
end

---@return string[] -- highest rank first; qblib requires `user` as its floor
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
    local primary = exports.qbcore:primary(src)
    return primary and primary:lower() or nil
end

local function syncIdentifier(key)
    for _, src in ipairs(exports.qbcore:getPlayers()) do
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
    local aceLevels, canonical = Admin.aceLevels()
    local held = canonical[QB.permissions.getLevel(src, aceLevels, OPTIONS)] or 'user'
    local temporary = temporaryLevel(src)
    if temporary and Admin.roleRank(temporary) > Admin.roleRank(held) then return temporary end
    return held
end

---@param src integer
---@param required string -- a configured role or an internal Config.permissions.gates key
---@return boolean
function Admin.checkLevel(src, required)
    local requiredRank = Admin.roleRank(required)
    local heldRank = Admin.roleRank(Admin.getLevel(src))
    return requiredRank ~= nil and heldRank ~= nil and heldRank >= requiredRank
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
        return nil, 'invalid or non-grantable role'
    end
    if type(minutes) ~= 'number' or minutes ~= math.floor(minutes)
        or minutes < settings.minMinutes or minutes > settings.maxMinutes then
        return nil, ('duration must be %d-%d minutes'):format(settings.minMinutes, settings.maxMinutes)
    end

    local key = primaryKey(src)
    if not key then return nil, 'could not resolve target identifier' end
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
    TriggerClientEvent('qbadmin:client:level', src, Admin.getLevel(src))
end
