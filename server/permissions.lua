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
