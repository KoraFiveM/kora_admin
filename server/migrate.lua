-- Runs qbadmin's own SQL migration at boot via qbsql's migration runner.
-- Mirrors qbcore/modules/persistence/migrate.lua's pattern exactly, including
-- the checksum function -- no shared checksum utility exists in qblib/qbcore
-- to reuse (qbcore's own copy is private too), so this is consistent
-- duplication, not an oversight.

local function fnv1a(str)
    local hash = 0xCBF29CE484222325
    local prime = 0x100000001B3
    for i = 1, #str do
        hash = hash ~ string.byte(str, i)
        hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF
    end
    return hash
end

local function checksum(str)
    local a = fnv1a(str)
    local b = fnv1a(str:reverse())
    return (('%016x%016x'):format(a, b) .. string.rep('0', 32))
end

CreateThread(function()
    local ok = QB.sql.ready(60000)
    if not ok then
        print('^1[qbadmin:migrate]^7 qbsql never became ready -- admin logs and reports unavailable.')
        return
    end

    local resource = GetCurrentResourceName()
    local applied, err = QB.sql.migrateFiles(resource, {
        { version = 1, name = 'admin_logs', file = 'sql/001_admin_logs.sql' },
        { version = 2, name = 'admin_reports', file = 'sql/002_admin_reports.sql' },
    }, checksum)
    if err then
        print(('^1[qbadmin:migrate]^7 migration failed: %s'):format(tostring(err)))
    else
        print('^2[qbadmin:migrate]^7 schema up to date.')
    end
end)
