-- Admin schema is declared for kora_sql and applied through ensureTables.
local captured, threads = nil, {}
_G.Kora = { sql = {
    NULL = {},
    ready = function() return true end,
    ensureTables = function(specs) captured = specs; return {}, nil end,
} }
_G.CreateThread = function(fn) threads[#threads + 1] = fn end

dofile('server/schema.lua')
dofile('server/migrate.lua')
for _, fn in ipairs(threads) do fn() end

local names = {}
for _, spec in ipairs(QBAdminSchema) do names[#names + 1] = spec.name end
local got = table.concat(names, ',')
assert(got == 'admin_logs,admin_reports,admin_report_messages', 'schema tables: ' .. got)
assert(captured == QBAdminSchema, 'migrate must pass QBAdminSchema to ensureTables')
assert(QBAdminSchema[3].foreign[1].ref_table == 'admin_reports', 'messages FK must reference reports')
print('schema: 3 passed')
