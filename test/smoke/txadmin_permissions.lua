local handlers, updates = {}, {}
local invoking = 'kora_core'
local coreState = 'started'
Admin = { syncLevel = function(src) updates[#updates + 1] = src end }
function AddEventHandler(name, fn) handlers[name] = fn end
function RegisterNetEvent() end
function GetInvokingResource() return invoking end
function GetResourceState() return coreState end
function GetPlayerName(src) return src == 1 and 'Staff' or nil end
dofile('server/core.lua')

local handler = assert(handlers['kora_core:server:txAdminPermissionChanged'])
handler(1)
assert(#updates == 1 and updates[1] == 1, 'kora_core changes must refresh the menu through the existing resolver')
handler(2)
assert(#updates == 1, 'disconnected players must not receive menu updates')
invoking = 'other'
handler(1)
assert(#updates == 1, 'other callers must not drive menu updates')
invoking = 'kora_core'
coreState = 'stopping'
handler(1)
assert(#updates == 1, 'menu refresh must not call into a stopping kora_core resource')
print('txadmin_permissions: menu refresh, disconnected player, caller and shutdown checks passed')
