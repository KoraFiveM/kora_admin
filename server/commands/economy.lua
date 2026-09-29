-- /givemoney, /removemoney, /setmoney, /giveitem, /removeitem, /clearinventory
--
-- Account names are NOT validated here against a hardcoded list: qbcore's own
-- addMoney/removeMoney/setMoney already reject any account not in
-- Config.money.types (a config value that lives in qbcore's own VM, not
-- readable from here) with a 'invalid account' error -- surfacing that error
-- is simpler and can't drift out of sync with qbcore's own config.

local OPTS_ADMIN = { permission = 'admin', checkPermission = Admin.checkLevel, resource = 'qbadmin' }

---Shared shape for all three money commands: resolve target, parse amount,
---call the given qbcore export, log, respond. One function, three thin
---registrations below -- the DRY analogue of qbadmin's other command files,
---just parameterized over which export to call instead of split per file.
---@param name string
---@param help string
---@param exportFn fun(targetSrc:integer, account:string, amount:number, reason:string):boolean, string|nil
local function moneyCommand(name, help, exportFn)
    -- argsRequired=false: 'reason' is optional (defaults below), and qblib's
    -- wrapper would otherwise demand every declared arg -- including it --
    -- before the handler ever runs. account/amount are still enforced here.
    Admin.addCommand(name, help, { { name = 'id' }, { name = 'account' }, { name = 'amount' }, { name = 'reason' } }, false,
        function(source, args)
            local targetSrc, data, err = Admin.resolveTarget(source, args[1])
            if not targetSrc then return Admin.respond(source, false, err) end

            local account = args[2]
            local amount = Admin.finiteNumber(args[3], 0)
            if not account or not amount then return Admin.respond(source, false, 'account and amount are required') end
            if amount <= 0 then return Admin.respond(source, false, 'amount must be positive') end

            local reason = table.concat(args, ' ', 4)
            if reason == '' then reason = ('admin:%s'):format(name) end

            local ok, actionErr = exportFn(targetSrc, account, amount, reason)
            if not ok then return Admin.respond(source, false, actionErr or 'action failed') end

            Admin.log(source, name, data, { account = account, amount = amount, reason = reason })
            Admin.respond(source, true, ('%s %s %s (%s) for %s'):format(name, amount, account, reason, data.name))
        end, OPTS_ADMIN)
end

moneyCommand('givemoney', 'Give a player money', function(targetSrc, account, amount, reason)
    return exports.qbcore:addMoney(targetSrc, account, amount, reason)
end)

moneyCommand('removemoney', 'Remove money from a player', function(targetSrc, account, amount, reason)
    return exports.qbcore:removeMoney(targetSrc, account, amount, reason)
end)

moneyCommand('setmoney', "Set a player's account balance", function(targetSrc, account, amount, reason)
    return exports.qbcore:setMoney(targetSrc, account, amount, reason)
end)

-- argsRequired=false: amount/info both default below; only id/item are truly required.
Admin.addCommand('giveitem', 'Give a player an item', { { name = 'id' }, { name = 'item' }, { name = 'amount' }, { name = 'info' } }, false,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local item = args[2]
        local amount = args[3] == nil and 1 or Admin.finiteNumber(args[3], 1, nil, true)
        if not item then return Admin.respond(source, false, 'item name required') end
        if not amount then return Admin.respond(source, false, 'amount must be a positive whole number') end
        local info
        if args[4] then
            local decoded, decodeErr = pcall(json.decode, args[4])
            if not decoded then return Admin.respond(source, false, ('invalid item metadata JSON: %s'):format(tostring(decodeErr))) end
            info = decodeErr
            if type(info) ~= 'table' then return Admin.respond(source, false, 'item metadata must decode to an object') end
        end

        local ok, actionErr = exports.qbcore:addItem(targetSrc, item, amount, nil, info, 'admin:giveitem')
        if not ok then return Admin.respond(source, false, actionErr or 'could not give item') end

        Admin.log(source, 'giveitem', data, { item = item, amount = amount })
        Admin.respond(source, true, ('Gave %d x %s to %s'):format(amount, item, data.name))
    end, OPTS_ADMIN)

-- argsRequired=false: amount defaults below; only id/item are truly required.
Admin.addCommand('removeitem', 'Remove an item from a player', { { name = 'id' }, { name = 'item' }, { name = 'amount' } }, false,
    function(source, args)
        local targetSrc, data, err = Admin.resolveTarget(source, args[1])
        if not targetSrc then return Admin.respond(source, false, err) end

        local item = args[2]
        local amount = args[3] == nil and 1 or Admin.finiteNumber(args[3], 1, nil, true)
        if not item then return Admin.respond(source, false, 'item name required') end
        if not amount then return Admin.respond(source, false, 'amount must be a positive whole number') end

        local ok, actionErr = exports.qbcore:removeItem(targetSrc, item, amount, nil, 'admin:removeitem')
        if not ok then return Admin.respond(source, false, actionErr or 'could not remove item') end

        Admin.log(source, 'removeitem', data, { item = item, amount = amount })
        Admin.respond(source, true, ('Removed %d x %s from %s'):format(amount, item, data.name))
    end, OPTS_ADMIN)

Admin.addCommand('clearinventory', "Clear a player's inventory", { { name = 'id' } }, true, function(source, args)
    local targetSrc, data, err = Admin.resolveTarget(source, args[1])
    if not targetSrc then return Admin.respond(source, false, err) end

    exports.qbcore:clearInventory(targetSrc)
    Admin.log(source, 'clearinventory', data)
    Admin.respond(source, true, ("Cleared %s's inventory"):format(data.name))
end, OPTS_ADMIN)
