local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("imported_menu_facade")

local M = {}
local ARRAY = { __json_array = true }
local function array(contents) return setmetatable(contents or {}, ARRAY) end
local function finite(number) return type(number) == "number" and number == number and math.abs(number) < math.huge end
local function encode(value, depth)
    depth = depth or 0
    assert(depth < 20, "Snapshot nesting exceeds limit")
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then assert(finite(value), "Nonfinite snapshot number"); return tostring(value) end
    if kind == "string" then
        assert(#value <= 32768, "Snapshot string exceeds limit")
        -- Nearly every label is already clean. find is far cheaper than a gsub carrying
        -- a replacement function, and this runs for every string in the snapshot on the
        -- game thread, so the common case skips the rewrite entirely.
        if not value:find('[%z\1-\31\\"]') then return '"' .. value .. '"' end
        return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
            return string.format("\\u%04x", string.byte(character))
        end) .. '"'
    end
    assert(kind == "table", "Unsupported snapshot value")
    local parts = {}
    if getmetatable(value) == ARRAY or #value > 0 then
        for _, entry in ipairs(value) do parts[#parts + 1] = encode(entry, depth + 1) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for key, entry in pairs(value) do
        assert(type(key) == "string", "Invalid snapshot key")
        parts[#parts + 1] = encode(key, depth + 1) .. ":" .. encode(entry, depth + 1)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end
M.Encode = encode
M.Array = array

local scalarFields = { "id", "type", "label", "min", "max", "step", "integer", "variant", "searchable", "placeholder", "maxVisible", "enabled", "readOnly" }
local function plainScalar(value)
    return type(value) == "string" or type(value) == "boolean" or finite(value)
end
local function optionsCopy(options)
    local result = array()
    assert(#(options or {}) <= 4096, "Too many dropdown options")
    for _, option in ipairs(options or {}) do
        if type(option) == "string" or finite(option) then result[#result + 1] = option
        elseif type(option) == "table" and type(option.label) == "string" and plainScalar(option.value) then
            result[#result + 1] = { label = option.label, value = option.value }
        else error("Invalid dropdown option") end
    end
    return result
end
local function confirmationCopy(spec)
    local result = {}
    for _, key in ipairs({ "title", "message", "confirmLabel", "cancelLabel", "variant" }) do
        if type(spec[key]) == "string" then result[key] = spec[key] end
    end
    return result
end

function M.New()
    local facade = {}
    local sections, registered, callbacks, messages, virtualValues = array(), {}, {}, array(), {}
    local revision, fieldRevision, sessionId, ready = 0, 0, "disconnected", false
    local shutdown -- nil until a clean quit is published (see facade.Shutdown)
    local operation, confirmation, pendingConfirmation
    local pending, context, counter, pendingTotal = {}, nil, 0, 0
    local function changed() revision = revision + 1 end
    local function find(sectionId, itemId)
        local item = registered[sectionId] and registered[sectionId][itemId]
        assert(item, "Unknown registered item")
        return item
    end
    function facade.Message(message)
        message = tostring(message):sub(1, 4096)
        messages[#messages + 1] = message
        while #messages > 32 do table.remove(messages, 1) end
        changed()
    end
    function facade.Init() end
    function facade.Register(section)
        assert(type(section.id) == "string" and not registered[section.id], "Invalid/duplicate section")
        -- Keep aligned with the desktop snapshot validator; feature adapters share this budget.
        assert(#sections < 96, "Section limit exceeded (96)")
        local index = {}
        local count = 0
        local function visit(items, depth)
            assert(depth < 8 and type(items) == "table", "Invalid item nesting")
            for _, item in ipairs(items) do
                count = count + 1; assert(count <= 512, "Section item limit")
                assert(type(item.type) == "string", "Missing item type")
                if item.id then
                    assert(type(item.id) == "string" and not index[item.id], "Duplicate item id")
                    index[item.id] = item
                    item.value = item.default
                    if item.type == "checkbox" then item.value = false end
                end
                if item.options then optionsCopy(item.options) end
                if item.items then visit(item.items, depth + 1) end
            end
        end
        visit(section.items, 0)
        registered[section.id] = index
        sections[#sections + 1] = section
        changed()
    end
    function facade.Get(sectionId, itemId)
        local item = registered[sectionId] and registered[sectionId][itemId]
        if item then return item.value end
        return virtualValues[sectionId] and virtualValues[sectionId][itemId]
    end
    function facade.Set(sectionId, itemId, value)
        local item = registered[sectionId] and registered[sectionId][itemId]
        if not item then
            -- Supplied modules synchronize hidden legacy fields internally. They do not
            -- become registered controls or externally callable command targets.
            assert(type(sectionId) == "string" and type(itemId) == "string"
                and #sectionId <= 128 and #itemId <= 128, "Invalid internal value key")
            assert(value == nil or plainScalar(value), "Invalid internal virtual value")
            virtualValues[sectionId] = virtualValues[sectionId] or {}
            virtualValues[sectionId][itemId] = value
            return
        end
        assert(value == nil or plainScalar(value) or (item.type == "meter" and type(value) == "table"), "Invalid programmatic value")
        if item.type ~= "meter" and item.value ~= value then fieldRevision = fieldRevision + 1 end
        item.value = value; changed()
    end
    function facade.SetLabel(sectionId, itemId, text)
        text = tostring(text):sub(1, 16384)
        find(sectionId, itemId).label = text; changed()
        local lower = text:lower()
        if context and operation and operation.id == context and
            (lower:match("^unavailable") or lower:match("^blocked") or lower:match("^stop:")
                or lower:match("^stopped after") or lower:match("verification failed")) then
            facade.Fail(text, context)
        end
    end
    function facade.SetOptions(sectionId, itemId, options, selected)
        local item = find(sectionId, itemId)
        assert(item.type == "dropdown", "Options require dropdown")
        item.options = optionsCopy(options)
        if selected == false then item.value = nil elseif selected ~= nil then item.value = selected end
        fieldRevision = fieldRevision + 1; changed()
        return true
    end
    function facade.OnOpen(callback) assert(type(callback) == "function"); callbacks[#callbacks + 1] = callback end
    function facade.Context() return context end
    function facade.PendingCount() return pendingTotal end
    function facade.BeginTask(owner)
        pendingTotal = pendingTotal + 1
        if owner then pending[owner] = (pending[owner] or 0) + 1 end
    end
    function facade.EndTask(owner)
        pendingTotal = math.max(0, pendingTotal - 1)
        if owner then pending[owner] = math.max(0, (pending[owner] or 1) - 1) end
        if operation and pendingTotal == 0 and operation.status == "running" then
            operation.status = operation.failureMessage and "failed" or "completed"
            operation.message = operation.failureMessage or "Scheduled callback work completed; inspect native status labels."
            changed()
        end
    end
    -- Lua's error() prefixes "<path>:<line>: " to a message, and a wrapper that re-raises
    -- adds a second one. That is useful in UE4SS.log and useless on screen, where the
    -- player saw two file paths before the sentence that mattered. The full text still
    -- reaches the log through facade.Message; only the published copy is trimmed.
    local function cyberfox1337x_withoutSourcePositions(text)
        local stripped = tostring(text)
        -- Strips a leading "<anything>Name.lua:123: ", repeatedly, and nothing else: a
        -- message that merely mentions a .lua file further along is left intact.
        for _ = 1, 4 do
            local trimmed = stripped:gsub("^%s*[^\n]-[%w_%-]+%.lua:%d+:%s*", "", 1)
            if trimmed == stripped then break end
            stripped = trimmed
        end
        return stripped
    end
    function facade.Fail(message, owner)
        facade.Message(message)
        if operation and (not owner or operation.id == owner) then
            operation.failureMessage = cyberfox1337x_withoutSourcePositions(message):sub(1, 4096)
            operation.status = pendingTotal > 0 and "running" or "failed"
            operation.message = operation.failureMessage
            confirmation = nil; pendingConfirmation = nil
            changed()
        end
    end
    function facade.Run(callback, owner)
        local previous = context; context = owner
        if operation and operation.id == owner and operation.status == "queued" then operation.status = "running" end
        facade.BeginTask(owner)
        local ok, message = pcall(callback)
        context = previous
        if not ok then facade.Fail(message, owner) end
        facade.EndTask(owner)
        return ok
    end
    function facade.Confirm(spec)
        assert(type(spec) == "table" and type(spec.onConfirm) == "function", "Confirmation callback required")
        assert(not pendingConfirmation, "Confirmation already pending")
        counter = counter + 1
        confirmation = confirmationCopy(spec)
        confirmation.token = sessionId .. ":" .. tostring(counter)
        pendingConfirmation = { spec = spec, revision = fieldRevision, sessionId = sessionId, owner = context }
        if operation then operation.status = "awaiting-confirmation"; operation.message = confirmation.message end
        changed()
    end
    local function itemCopy(item)
        local result = {}
        for _, key in ipairs(scalarFields) do if plainScalar(item[key]) then result[key] = item[key] end end
        -- A checkbox without a gameplay callback is a live status indicator. Publishing
        -- that distinction prevents the desktop from offering a switch that can only
        -- change its own displayed value while leaving the game untouched.
        if item.type == "checkbox" and type(item.onChange) ~= "function" then result.readOnly = true end
        if plainScalar(item.value) then result.value = item.value
        elseif item.type == "meter" and type(item.value) == "table" then
            result.value = { percent = finite(item.value.percent) and item.value.percent or 0, text = tostring(item.value.text or "") }
        end
        if item.options then result.options = optionsCopy(item.options) end
        if item.confirm then result.confirm = confirmationCopy(item.confirm) end
        if item.items then result.items = array(); for _, child in ipairs(item.items) do result.items[#result.items + 1] = itemCopy(child) end end
        return result
    end
    function facade.PublicationState()
        return revision, pendingTotal, operation and operation.status or ""
    end
    function facade.Snapshot()
        local copied = array()
        for _, section in ipairs(sections) do
            local entry = { id = section.id, title = section.title, tab = section.tab, items = array() }
            for _, item in ipairs(section.items) do entry.items[#entry.items + 1] = itemCopy(item) end
            copied[#copied + 1] = entry
        end
        return { schema = 1, buildId = "25232147", heartbeat = os.time(), sessionId = sessionId, revision = revision,
            ready = ready, sections = copied, operation = operation, confirmation = confirmation, messages = messages,
            pendingFiniteTasks = pendingTotal, shutdown = shutdown }
    end
    -- A clean quit is published as `shutdown = "quit"` in the final snapshot. A crash or a
    -- forced close never writes it, which is how the desktop tells the two apart: after an
    -- unclean exit Steam's overlay session for the game is left stale and the next launch
    -- freezes at startup (see qa/validation-20260918/HANG-ANALYSIS.md).
    function facade.Shutdown(reason)
        assert(type(reason) == "string" and reason ~= "", "Shutdown reason required")
        shutdown = reason; changed()
    end
    function facade.Session(newSession, isReady)
        if sessionId ~= newSession then
            confirmation = nil; pendingConfirmation = nil
            if operation and operation.status ~= "completed" then facade.Fail("Player session changed") end
        end
        sessionId = newSession; ready = isReady; changed()
    end
    local function validateValue(item, value, valueType)
        if item.type == "checkbox" then assert(valueType == "boolean" and type(value) == "boolean", "Boolean required")
        elseif item.type == "number" then
            assert(valueType == "number" and finite(value), "Finite number required")
            assert((not item.min or value >= item.min) and (not item.max or value <= item.max), "Number outside bounds")
            assert(not item.integer or value == math.floor(value), "Whole number required")
            if item.step then local quotient = (value - (item.min or 0)) / item.step; assert(math.abs(quotient - math.floor(quotient + 0.5)) < 0.000001, "Number violates step") end
        elseif item.type == "dropdown" then
            local found = false
            for _, option in ipairs(item.options or {}) do
                local candidate = type(option) == "table" and option.value or option
                if candidate == value then found = true end
            end
            assert(found and value ~= false, "Choose a registered dropdown option")
        elseif item.type == "input" or item.type == "text" then
            assert(valueType == "string" and type(value) == "string" and #value <= 512
                and not value:find("[%z\r\n]"), "Invalid input text")
        else error("Item is not a writable control") end
    end
    function facade.Dispatch(command)
        assert(ready and command.session_id == sessionId, "Stale or unavailable player session")
        assert(type(command.request_id) == "string" and #command.request_id > 0 and #command.request_id <= 128, "Invalid request id")
        assert(pendingTotal == 0, "Wait for all finite callbacks to drain before another command")
        if command.action == "close" then
            assert(not operation or operation.status ~= "running" and operation.status ~= "queued", "Wait for current finite operation before closing imported runtime")
            local cancelled = pendingConfirmation and pendingConfirmation.spec.onCancel
            pendingConfirmation = nil; confirmation = nil
            operation = { id = command.request_id, requestId = command.request_id, operationrequestId = command.request_id,
                status = "running", message = "Stopping imported controls" }
            facade.Run(function()
                if cancelled then cancelled() end
                facade.StopControls()
            end, command.request_id)
            changed(); return
        end
        if command.action == "confirm" then
            assert(pendingConfirmation and confirmation and command.confirmation_token == confirmation.token, "Unknown confirmation token")
            assert(pendingConfirmation.sessionId == sessionId, "Confirmation session changed")
            assert(command.confirmed == true or command.confirmed == false, "Confirmation decision required")
            assert(not command.confirmed or pendingConfirmation.revision == fieldRevision, "Confirmation inputs changed")
            local saved = pendingConfirmation; pendingConfirmation = nil; confirmation = nil
            if operation then operation.status = "running"; operation.id = command.request_id; operation.requestId = command.request_id; operation.operationrequestId = command.request_id end
            local callback = command.confirmed and saved.spec.onConfirm or saved.spec.onCancel
            facade.Run(callback or function() end, command.request_id)
            changed(); return
        end
        assert(not pendingConfirmation, "Respond to the pending confirmation first")
        assert(not operation or operation.status == "completed" or operation.status == "failed", "Previous operation is still running")
        local callback
        if command.action == "refresh" then callback = function() for _, refresh in ipairs(callbacks) do refresh() end end
        else
            local item = find(command.section_id, command.item_id)
            if command.action == "invoke" then
                assert(item.type == "button" and item.enabled ~= false and type(item.onClick) == "function", "Item is not an enabled action")
                callback = item.confirm and function()
                    local spec = confirmationCopy(item.confirm); spec.onConfirm = item.onClick; facade.Confirm(spec)
                end or item.onClick
            elseif command.action == "set" then
                assert(item.enabled ~= false, "Item is disabled")
                assert(item.readOnly ~= true and not (item.type == "checkbox" and type(item.onChange) ~= "function"), "Item is read-only")
                validateValue(item, command.value, command.value_type)
                callback = function()
                    item.value = command.value; fieldRevision = fieldRevision + 1; changed()
                    if item.onChange then item.onChange(command.value) end
                end
            else error("Unknown action") end
        end
        operation = { id = command.request_id, requestId = command.request_id, operationrequestId = command.request_id, status = "queued", message = "Queued registered callback" }
        changed(); facade.Run(callback, operation.id)
    end
    function facade.StopControls()
        for _, index in pairs(registered) do
            for _, item in pairs(index) do
                if item.type == "checkbox" and item.value == true and type(item.onChange) == "function" then
                    facade.Run(function() item.onChange(false) end, context)
                end
            end
        end
    end
    return facade
end
return M
