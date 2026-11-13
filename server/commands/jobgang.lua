-- /setjob, /setgang, /setduty
--
-- Grade validation is NOT duplicated here: exports.kora_core:setJob/setGang
-- already validate the job/gang name against the live registry and return
-- 'unknown job'/'unknown gang' on failure, and already parse/clamp the grade
-- argument themselves -- this file just passes the raw string through.

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'kora_admin' }
local OPTS_MOD = { permission = 'mod', checkPermission = Admin.checkLevel, resource = 'kora_admin' }

-- argsRequired=false: grade defaults inside exports.kora_core:setJob itself; only id/job are truly required.
Admin.addCommand('setjob', "Set a player's job and grade", { { name = 'id' }, { name = 'job' }, { name = 'grade' } }, false,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local jobName = args[2]
        if not jobName then return Admin.respond(source, false, Kora.lang('error.job_name_required')) end

        local ok, actionErr = exports.kora_core:setJob(targetSrc, jobName, args[3])
        if not ok then return Admin.respond(source, false, actionErr or Kora.lang('error.set_job_failed')) end

        Admin.log(source, 'setjob', data, { job = jobName, grade = args[3] })
        Admin.respond(source, true, Kora.lang('success.success_set_s_s_job_to_s', data.name, jobName))
    end, OPTS_ADMIN)

-- argsRequired=false: grade defaults inside exports.kora_core:setGang itself; only id/gang are truly required.
Admin.addCommand('setgang', "Set a player's gang and grade", { { name = 'id' }, { name = 'gang' }, { name = 'grade' } }, false,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local gangName = args[2]
        if not gangName then return Admin.respond(source, false, Kora.lang('error.gang_name_required')) end

        local ok, actionErr = exports.kora_core:setGang(targetSrc, gangName, args[3])
        if not ok then return Admin.respond(source, false, actionErr or Kora.lang('error.set_gang_failed')) end

        Admin.log(source, 'setgang', data, { gang = gangName, grade = args[3] })
        Admin.respond(source, true, Kora.lang('success.success_set_s_s_gang_to_s', data.name, gangName))
    end, OPTS_ADMIN)

Admin.addCommand('setduty', 'Toggle on/off duty', { { name = 'id' }, { name = 'state' } }, false, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    local current = data.job and data.job.onduty == true
    local state, stateErr = Admin.resolveToggle(args[2], current)
    if state == nil then return Admin.respond(source, false, stateErr) end

    local ok, actionErr = exports.kora_core:setJobDuty(targetSrc, state)
    if not ok then return Admin.respond(source, false, actionErr or Kora.lang('error.set_duty_failed')) end
    Admin.refreshMenuPlayerState(source, targetSrc)
    Admin.log(source, 'setduty', data, { state = state })
    Admin.respond(source, true, Kora.lang('success.success_s_is_now_s_duty', data.name, state and 'on' or 'off'))
end, OPTS_MOD)
