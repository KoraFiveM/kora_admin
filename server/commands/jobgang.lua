-- /setjob, /setgang, /setduty
--
-- Grade validation is NOT duplicated here: exports.qbcore:setJob/setGang
-- already validate the job/gang name against the live registry and return
-- 'unknown job'/'unknown gang' on failure, and already parse/clamp the grade
-- argument themselves -- this file just passes the raw string through.

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'qbadmin' }
local OPTS_MOD = { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'qbadmin' }

-- argsRequired=false: grade defaults inside exports.qbcore:setJob itself; only id/job are truly required.
QB.commands.add('setjob', "Set a player's job and grade", { { name = 'id' }, { name = 'job' }, { name = 'grade' } }, false,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local jobName = args[2]
        if not jobName then return Admin.respond(source, false, 'job name required') end

        local ok, actionErr = exports.qbcore:setJob(targetSrc, jobName, args[3])
        if not ok then return Admin.respond(source, false, actionErr or 'could not set job') end

        Admin.log(source, 'setjob', data, { job = jobName, grade = args[3] })
        Admin.respond(source, true, ("Set %s's job to %s"):format(data.name, jobName))
    end, OPTS_ADMIN)

-- argsRequired=false: grade defaults inside exports.qbcore:setGang itself; only id/gang are truly required.
QB.commands.add('setgang', "Set a player's gang and grade", { { name = 'id' }, { name = 'gang' }, { name = 'grade' } }, false,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local gangName = args[2]
        if not gangName then return Admin.respond(source, false, 'gang name required') end

        local ok, actionErr = exports.qbcore:setGang(targetSrc, gangName, args[3])
        if not ok then return Admin.respond(source, false, actionErr or 'could not set gang') end

        Admin.log(source, 'setgang', data, { gang = gangName, grade = args[3] })
        Admin.respond(source, true, ("Set %s's gang to %s"):format(data.name, gangName))
    end, OPTS_ADMIN)

QB.commands.add('setduty', 'Toggle on/off duty', { { name = 'id' }, { name = 'state' } }, false, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    local state = args[2] == nil or args[2]:lower() ~= 'false'
    exports.qbcore:setJobDuty(targetSrc, state)
    Admin.log(source, 'setduty', data, { state = state })
    Admin.respond(source, true, ('%s is now %s duty'):format(data.name, state and 'on' or 'off'))
end, OPTS_MOD)
