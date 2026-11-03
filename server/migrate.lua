-- Declares kora_admin's tables at boot through kora_sql's schema handler.

CreateThread(function()
    local ok = Kora.sql.ready(60000)
    if not ok then
        print('^1[qbadmin:migrate]^7 qbsql never became ready -- admin logs and reports unavailable.')
        return
    end

    local reports, err = Kora.sql.ensureTables(QBAdminSchema)
    if err then
        print(('^1[qbadmin:migrate]^7 schema failed: %s'):format(tostring(err)))
        return
    end
    for _, report in ipairs(reports or {}) do
        for _, warning in ipairs(report.warnings or {}) do
            print(('^3[qbadmin:migrate]^7 %s: %s'):format(tostring(report.table), tostring(warning)))
        end
    end
    print('^2[qbadmin:migrate]^7 schema up to date.')
end)
