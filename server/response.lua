-- Admin.respond -- the one user-facing feedback call site, used by every
-- command right after it finishes, so success/error toasts look identical
-- whether the command was typed or fired by the NUI via ExecuteCommand. Built
-- directly on qblib's QB.notify.send -- no bespoke toast/UI invented.

---@param src integer
---@param ok boolean
---@param message? string  -- resolver/action failures may only have an err string some of the time; falls back to a generic message
---@param opts table|nil  -- { title?: string }
function Admin.respond(src, ok, message, opts)
    QB.notify.send(src, {
        title = ok and (opts and opts.title or 'Admin') or 'Admin — Error',
        message = message or (ok and 'Done' or 'Something went wrong'),
        type = ok and 'success' or 'error',
    })
end

---Print a chat-log-style multi-line message (player lists, audit log pages,
---server info) that doesn't fit a toast. Reuses this server's own chat
---resource event rather than inventing a second output channel.
---@param src integer
---@param message string
function Admin.chat(src, message)
    TriggerClientEvent('chatMessage', src, '[Admin]', { 255, 200, 0 }, message)
end
