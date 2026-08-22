-- Admin.checkLevel -- the one permission check every command's checkPermission
-- uses. exports.qbcore:getPermission already walks qbcore's ordered level list
-- and returns the single highest tier a player holds, so comparing ranks here
-- gives correct cascading (god satisfies a 'mod' check) with zero server.cfg
-- principal-chaining required -- unlike exports.qbcore:hasPermission, which
-- checks one exact ACE string and does not cascade on its own.
--
-- No src == 0 special-case is needed: QB.commands.add's own wrapper already
-- exempts the server console from calling checkPermission at all.

local RANKS = Config.permissions.ranks

---@param src integer
---@param required string  -- 'mod'|'admin'|'god'
---@return boolean
function Admin.checkLevel(src, required)
    local level = exports.qbcore:getPermission(src)
    return (RANKS[level] or RANKS.user) >= (RANKS[required] or RANKS.user)
end
