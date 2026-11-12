-- Staff-opened appearance sessions for another player. kora_clothing owns the
-- one-use authorization and fitting-room lifecycle; kora_admin only resolves the
-- target, applies its admin permission gate, and audits the request.

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'kora_admin' }

local function addAppearanceCommand(name, label, service)
    Admin.addCommand(name, ('Open the %s for a player'):format(label:lower()), { { name = 'id' } }, true, function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end
        if GetResourceState('kora_clothing') ~= 'started' then
            return Admin.respond(source, false, 'kora_clothing is not running')
        end

        local callOk, opened, openErr = pcall(function()
            return exports.kora_clothing:OpenAdminSession(targetSrc, service)
        end)
        if not callOk or not opened then
            return Admin.respond(source, false, openErr or (callOk and 'could not open appearance session' or tostring(opened)))
        end

        Admin.log(source, name, data, { service = service })
        Admin.respond(source, true, ('Opened %s for %s'):format(label:lower(), data.name))
    end, OPTS_ADMIN)
end

addAppearanceCommand('clothingmenu', 'Clothing Menu', 'clothing')
addAppearanceCommand('barbermenu', 'Barber / Hairdresser', 'barber')
addAppearanceCommand('tattoomenu', 'Tattoo Menu', 'tattoo')
