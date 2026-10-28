-- Permission boundary and audit adapter for kora_lib's configuration catalog.
-- kora_lib validates and persists the data; kora_admin decides which players may
-- see/edit it and records the resulting administrative action.

local function allowed(source)
    return source == 0 or Admin.checkLevel(source, Config.configEditor.level)
end

local function deny(source)
    if not allowed(source) then return nil, 'permission denied' end
    return true
end

local function sanitize(schema, value)
    if type(schema) ~= 'table' then return value end
    if schema.sensitive == true then return nil end
    if schema.kind == 'object' and type(value) == 'table' then
        local out = {}
        for key, child in pairs(schema.fields or {}) do
            local sanitized = sanitize(child, value[key])
            if sanitized ~= nil then out[key] = sanitized end
        end
        return out
    end
    return value
end

local function sanitizeSchema(schema)
    if type(schema) ~= 'table' or schema.sensitive == true then return nil end
    local out = {}
    for key, value in pairs(schema) do
        if key ~= 'fields' and key ~= 'items' and key ~= 'values' and key ~= 'item' and key ~= 'inner' then out[key] = value end
    end
    if schema.fields then
        out.fields = {}
        for key, child in pairs(schema.fields) do
            local sanitized = sanitizeSchema(child)
            if sanitized then out.fields[key] = sanitized end
        end
    end
    if schema.items then
        out.items = {}
        for index, child in pairs(schema.items) do
            local sanitized = sanitizeSchema(child)
            if sanitized then out.items[index] = sanitized end
        end
    end
    if schema.values then
        out.values = {}
        for key, child in pairs(schema.values) do
            local sanitized = sanitizeSchema(child)
            if sanitized then out.values[key] = sanitized end
        end
    end
    if schema.item then out.item = sanitizeSchema(schema.item) end
    if schema.inner then out.inner = sanitizeSchema(schema.inner) end
    return out
end

QB.callback.register('qbadmin:configCatalog', function(source)
    local ok, err = deny(source)
    if not ok then return nil, err end
    local catalog = QB.config.catalog()
    for _, entry in ipairs(catalog) do entry.schema = sanitizeSchema(entry.schema) end
    return catalog
end)

QB.callback.register('qbadmin:configRead', function(source, resource)
    local ok, err = deny(source)
    if not ok then return nil, err end
    if type(resource) ~= 'string' then return nil, 'invalid resource' end

    local readOk, entry = pcall(QB.config.read, resource)
    if not readOk or type(entry) ~= 'table' then return nil, 'configuration is unavailable' end
    entry.configured = sanitize(entry.schema, entry.configured)
    entry.values = sanitize(entry.schema, entry.values)
    entry.schema = sanitizeSchema(entry.schema)
    return entry
end)

QB.commands.add('config', 'Open the configuration editor', nil, false, function(source)
    TriggerClientEvent('qbadmin:client:configOpened', source)
end, {
    permission = Config.configEditor.level,
    checkPermission = Admin.checkLevel,
    resource = 'kora_admin',
})

local function validRequest(request)
    if type(request) ~= 'table' or type(request.resource) ~= 'string' or type(request.path) ~= 'table'
        or type(request.revision) ~= 'number' then return false end
    if not request.resource:match('^[%w_%-]+$') then return false end
    for _, key in ipairs(request.path) do
        if type(key) ~= 'string' and type(key) ~= 'number' then return false end
    end
    return #request.path > 0
end

QB.callback.register('qbadmin:configCommit', function(source, request)
    local ok, err = deny(source)
    if not ok then return nil, err end
    if not validRequest(request) then return nil, 'invalid configuration request' end

    local result = QB.config.commit(request.resource, {
        path = request.path,
        value = request.value,
        revision = request.revision,
    })
    if result.ok then
        Admin.log(source, 'config.commit', nil, {
            resource = request.resource, path = table.concat(request.path, '.'),
            applied = result.applied == true, restartRequired = result.restartRequired == true,
        })
    end
    return result
end)

QB.callback.register('qbadmin:configReset', function(source, request)
    local ok, err = deny(source)
    if not ok then return nil, err end
    if not validRequest(request) then return nil, 'invalid configuration request' end

    local result = QB.config.reset(request.resource, {
        path = request.path,
        revision = request.revision,
    })
    if result.ok then
        Admin.log(source, 'config.reset', nil, {
            resource = request.resource, path = table.concat(request.path, '.'),
            applied = result.applied == true, restartRequired = result.restartRequired == true,
        })
    end
    return result
end)
