-- Admin.log / Admin.queryLogs -- the durable audit trail. exports.qbcore's own
-- logEvent is an in-memory 500-entry ring buffer only (confirmed in
-- qbcore/modules/logging/server.lua) -- not durable, not queryable later, so
-- "who banned/kicked/teleported whom, when" needs qbadmin's own table.
-- Migrated via server/migrate.lua.

---@param actorSrc integer  -- 0 for console
---@param action string
---@param target table|nil  -- { citizenid?, license?, name? }
---@param details table|nil -- action-specific, JSON-encoded
function Admin.log(actorSrc, action, target, details)
    local actorLicense = actorSrc ~= 0 and exports.qbcore:primary(actorSrc) or nil
    local actorName = actorSrc ~= 0 and (GetPlayerName(actorSrc) or ('unknown(%d)'):format(actorSrc)) or 'console'

    QB.sql.insert(
        'INSERT INTO `admin_logs` (`action`,`actor_license`,`actor_name`,`target_citizenid`,`target_license`,`target_name`,`details`) '
        .. 'VALUES (?,?,?,?,?,?,?)',
        {
            -- A console action has no actor license, and most actions have no
            -- target or details. Each of those is a real NULL column, not an
            -- absent parameter -- binding nil would hole or truncate the array.
            action, actorLicense or QB.sql.NULL, actorName,
            (target and target.citizenid) or QB.sql.NULL,
            (target and target.license) or QB.sql.NULL,
            (target and target.name) or QB.sql.NULL,
            details and json.encode(details) or QB.sql.NULL,
        }
    )
end

---Query the audit log with optional filters, newest first, paged.
---@param filters table|nil  -- { action?, actor?, target?, since?: unix seconds, page?: integer (1-based) }
---@return table[] rows
function Admin.queryLogs(filters)
    filters = filters or {}
    local where, params = {}, {}

    if filters.action then
        where[#where + 1] = '`action` = ?'
        params[#params + 1] = filters.action
    end
    if filters.actor then
        where[#where + 1] = '(`actor_license` = ? OR `actor_name` LIKE ?)'
        params[#params + 1] = filters.actor
        params[#params + 1] = '%' .. filters.actor .. '%'
    end
    if filters.target then
        where[#where + 1] = '(`target_citizenid` = ? OR `target_license` = ? OR `target_name` LIKE ?)'
        params[#params + 1] = filters.target
        params[#params + 1] = filters.target
        params[#params + 1] = '%' .. filters.target .. '%'
    end
    if filters.since then
        where[#where + 1] = '`created_at` >= FROM_UNIXTIME(?)'
        params[#params + 1] = filters.since
    end

    local pageSize = Config.audit.pageSize
    local page = math.max(1, tonumber(filters.page) or 1)
    local offset = (page - 1) * pageSize

    local sql = 'SELECT * FROM `admin_logs`'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY `created_at` DESC LIMIT ? OFFSET ?'
    params[#params + 1] = pageSize
    params[#params + 1] = offset

    return QB.sql.query(sql, params) or {}
end
