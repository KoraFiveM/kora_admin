-- Test stand-in for kora_lib's Kora.lang, which the smoke suites do not load.
-- Resolves 'group.key' against locales/en.lua and applies string.format with the
-- remaining arguments. An unknown key returns the key itself, so a missing locale
-- entry is visible in assertions instead of crashing the handler.
local locale = dofile('locales/en.lua')

return function(key, ...)
    local node = locale
    for part in tostring(key):gmatch('[^%.]+') do
        node = type(node) == 'table' and node[part] or nil
    end
    if type(node) ~= 'string' then return key end
    if select('#', ...) == 0 then return node end
    local ok, text = pcall(string.format, node, ...)
    return ok and text or node
end
