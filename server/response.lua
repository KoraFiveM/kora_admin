-- Admin.respond -- the one user-facing feedback call site, used by every
-- command right after it finishes, so success/error toasts look identical
-- whether the command was typed or fired by the NUI via ExecuteCommand. Built
-- directly on kora_lib's Kora.notify.send -- no bespoke toast/UI invented.

---@param src integer
---@param ok boolean
---@param message? string  -- resolver/action failures may only have an err string some of the time; falls back to a generic message
---@param opts table|nil  -- { title?: string }
function Admin.respond(src, ok, message, opts)
    local context = Admin.commandContext(src)
    if context then
        context.ok = context.ok and ok
        context.messages[#context.messages + 1] = message or (ok and Kora.lang('error.done') or Kora.lang('error.unknown'))
        return
    end
    Kora.notify.send(src, {
        title = ok and (opts and opts.title or Kora.lang('title.admin')) or Kora.lang('title.error'),
        message = message or (ok and Kora.lang('error.done') or Kora.lang('error.unknown')),
        type = ok and 'success' or 'error',
    })
end

---Print a chat-log-style multi-line message (player lists, audit log pages,
---server info) that doesn't fit a toast. Reuses this server's own chat
---resource event rather than inventing a second output channel.
---@param src integer
---@param message string
function Admin.chat(src, message)
    local context = Admin.commandContext(src)
    if context then
        context.messages[#context.messages + 1] = message
        return
    end
    TriggerClientEvent('chatMessage', src, '[Admin]', { 255, 200, 0 }, message)
end
