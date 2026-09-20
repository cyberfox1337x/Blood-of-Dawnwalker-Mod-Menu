local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_session_dispatch")

-- Uninstalled codec/dispatcher. Its constructor has no native work or file IO.
local Dispatch = {}
local SCHEMA = "dawnwalker-human-iris-uv-v1-25129649"
local COMMON = { "wire_version", "operation", "boot_id", "owner_id", "request_id", "command_sequence" }
local OWNED = { "lease_id", "preview_nonce", "identity_key", "baseline_id" }
local OPERATIONS = { inspect = true, open = true, enqueue = true, step = true, renew = true,
    cancel = true, apply = true, restore = true, ack = true, close = true }
local SETTINGS = {
    { "left_primary_u", 3, "IrisColor1_U", "coen-human-eye-left" },
    { "left_primary_v", 3, "IrisColor1_V", "coen-human-eye-left" },
    { "left_secondary_u", 3, "IrisColor2_U", "coen-human-eye-left" },
    { "left_secondary_v", 3, "IrisColor2_V", "coen-human-eye-left" },
    { "right_primary_u", 4, "IrisColor1_U", "coen-human-eye-right" },
    { "right_primary_v", 4, "IrisColor1_V", "coen-human-eye-right" },
    { "right_secondary_u", 4, "IrisColor2_U", "coen-human-eye-right" },
    { "right_secondary_v", 4, "IrisColor2_V", "coen-human-eye-right" },
}
local function check(value, message) if value ~= true then error(message, 0) end end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function token(value) return type(value) == "string" and #value == 32 and value:match("^[a-f0-9]+$") ~= nil end
local function boot(value)
    if type(value) ~= "string" then return false end
    local first, second = value:match("^(%d+)%-(%d+)$")
    return first ~= nil and #first <= 16 and #second <= 16
end
local function plain(value, maximum)
    return type(value) == "string" and #value > 0 and #value <= maximum and not value:find("[%z\1-\31\127]")
end
local function decode(value)
    local position = 1
    while true do
        local found = value:find("%", position, true)
        if not found then break end
        local escape = value:sub(found + 1, found + 2)
        check(escape == "25" or escape == "0D" or escape == "0A", "Invalid eye request escape")
        position = found + 3
    end
    return (value:gsub("%%(25)", function() return "\1" end):gsub("%%0D", "\r"):gsub("%%0A", "\n"):gsub("\1", "%%"))
end
local function numeric(value)
    check(type(value) == "string" and #value <= 32, "Invalid numeric eye field")
    local mantissa, exponent = value:match("^(.-)[eE]([+-]?%d+)$")
    if not mantissa then mantissa = value; check(not value:find("[eE]"), "Invalid decimal eye value") end
    check(mantissa:match("^[+-]?%d+%.?%d*$") ~= nil or mantissa:match("^[+-]?%.%d+$") ~= nil, "Invalid decimal eye value")
    local number = tonumber(value)
    check(finite(number), "Nonfinite eye value")
    return number
end
local function integer(value, minimum, maximum)
    check(type(value) == "string" and value:match("^%d+$") ~= nil and #value <= 10, "Invalid eye integer")
    local result = tonumber(value)
    check(result >= minimum and result <= maximum and (value == "0" or value:sub(1, 1) ~= "0"), "Eye integer outside canonical bounds")
    return result
end

function Dispatch.parse_request(text)
    check(type(text) == "string" and #text > 0 and #text <= 32768 and text:sub(-1) == "\n"
        and not text:find("[\r%z\1-\9\11-\31\127]"), "Malformed or oversized eye request")
    check(utf8.len(text) ~= nil, "Eye request is not UTF-8")
    local result, count = {}, 0
    for line in text:gmatch("([^\n]*)\n") do
        local key, raw = line:match("^([a-z][a-z0-9_]*)=(.*)$")
        check(key ~= nil and result[key] == nil and #key <= 64, "Unknown shape or duplicate eye request field")
        result[key], count = decode(raw), count + 1
        check(count <= 23, "Eye request has too many fields")
    end
    check(result.wire_version == "1" and OPERATIONS[result.operation] == true, "Unsupported eye wire version or operation")
    local allowed = {}
    local function allow(keys) for _, key in ipairs(keys) do allowed[key] = true end end
    allow(COMMON)
    if result.operation ~= "inspect" then allow(OWNED) end
    if result.operation == "open" or result.operation == "enqueue" then allow({ "view_revision", "yaw_degrees", "framing", "zoom" }) end
    if result.operation == "open" or result.operation == "enqueue" or result.operation == "apply" or result.operation == "restore" then allow({ "eye_revision" }) end
    if result.operation == "open" or result.operation == "enqueue" or result.operation == "apply" then
        for _, definition in ipairs(SETTINGS) do allowed[definition[1]] = true end
    end
    if result.operation == "ack" then allow({ "frame_sequence", "file_name" }) end
    for key in pairs(result) do check(allowed[key] == true, "Unknown eye request field: " .. key) end
    for key in pairs(allowed) do check(result[key] ~= nil, "Missing eye request field: " .. key) end
    check(boot(result.boot_id) and token(result.owner_id) and token(result.request_id), "Invalid eye request identity")
    result.command_sequence = integer(result.command_sequence, 1, 2147483647)
    if result.operation ~= "inspect" then
        check(token(result.lease_id) and token(result.preview_nonce) and plain(result.identity_key, 2048)
            and plain(result.baseline_id, 2048), "Invalid eye lease or generation")
    end
    if result.eye_revision then result.eye_revision = integer(result.eye_revision, 0, 2147483647) end
    if result.view_revision then
        result.view_revision = integer(result.view_revision, 0, 2147483647)
        result.yaw_degrees, result.zoom = numeric(result.yaw_degrees), numeric(result.zoom)
        check(math.abs(result.yaw_degrees) <= 69 and result.zoom > 0 and result.zoom <= 10
            and (result.framing == "head-and-shoulders" or result.framing == "eyes-close-up"), "Unsupported eye view")
    end
    if result.left_primary_u then for _, definition in ipairs(SETTINGS) do result[definition[1]] = numeric(result[definition[1]]) end end
    if result.frame_sequence then
        result.frame_sequence = integer(result.frame_sequence, 1, 1200)
        check(result.file_name == "eye-live-" .. result.preview_nonce .. "-" .. string.format("%04d", result.frame_sequence) .. ".png",
            "Eye acknowledgement filename is not its exact owned frame")
    end
    return result
end

function Dispatch.format_response(value)
    local lines, bytes, visiting, nodes = {}, 0, {}, 0
    local function visit(prefix, item, depth)
        nodes = nodes + 1
        check(nodes <= 8192, "Eye response exceeds aggregate node budget")
        check(depth <= 12 and #prefix <= 192 and #lines < 4096, "Eye response exceeds structural bounds")
        if type(item) == "table" then
            check(getmetatable(item) == nil and not visiting[item], "Eye response is not plain acyclic data")
            visiting[item] = true
            local keys = {}
            for key in pairs(item) do
                check((type(key) == "string" and key:match("^[a-zA-Z_][a-zA-Z0-9_-]*$") ~= nil
                    and key ~= "__proto__" and key ~= "constructor" and key ~= "prototype")
                    or (type(key) == "number" and key % 1 == 0 and key >= 1 and key <= 4096), "Invalid eye response key")
                keys[#keys + 1] = key; check(#keys <= 4096, "Eye response table exceeds bounds")
            end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, key in ipairs(keys) do visit(prefix == "" and tostring(key) or prefix .. "." .. tostring(key), item[key], depth + 1) end
            visiting[item] = nil
        else
            check(type(item) == "string" or type(item) == "boolean" or finite(item), "Eye response includes native/nonfinite data")
            local text = type(item) == "number" and string.format("%.17g", item) or tostring(item)
            check(utf8.len(text) ~= nil and not text:find("[%z\1-\9\11\12\14-\31\127]"), "Invalid eye response text")
            local encoded = text:gsub("[%%\r\n]", function(c) return string.format("%%%02X", string.byte(c)) end)
            check(#encoded <= 16384, "Eye response value exceeds bounds")
            local line = prefix .. "=" .. encoded
            bytes = bytes + #line + 1; check(bytes <= 262144, "Eye response exceeds 256 KiB")
            lines[#lines + 1] = line
        end
    end
    visit("", value, 0)
    return table.concat(lines, "\n") .. "\n"
end

local function canonical(request)
    local result = { schemaId = SCHEMA, values = {} }
    for _, definition in ipairs(SETTINGS) do
        result.values[#result.values + 1] = { parameter = { slotId = "head:" .. definition[2], materialId = definition[4],
            name = definition[3], association = 2, index = -1 }, value = { kind = "scalar", value = request[definition[1]] } }
    end
    return result
end
local function descriptor(snapshot)
    check(type(snapshot) == "table" and snapshot.schema_id == SCHEMA and snapshot.form == 0 and snapshot.is_wolf_form == false,
        "Supported native human descriptor required")
    local result = { identity_key = snapshot.identity_key, baseline_id = snapshot.baseline_id, schema_id = snapshot.schema_id,
        player = snapshot.player, world = snapshot.world, head = snapshot.head, asset = snapshot.asset,
        form = snapshot.form, is_wolf_form = snapshot.is_wolf_form, current_settings = snapshot.current_settings,
        original_settings = snapshot.original_settings, bindings = {} }
    check(type(snapshot.original_settings) == "table" and type(snapshot.current_settings) == "table", "Original and current native settings required")
    for index, binding in ipairs(snapshot.bindings) do
        local item = { slot = binding.slot, slot_name = binding.slot_name, original = binding.original_identity,
            current = binding.current_identity, parameters = {} }
        for parameter_index, parameter in ipairs(binding.parameters) do
            item.parameters[parameter_index] = { parameter = parameter.parameter, min = parameter.min, max = parameter.max, tolerance = parameter.tolerance }
        end
        result.bindings[index] = item
    end
    return result
end

function Dispatch.new(deps)
    check(type(deps) == "table" and boot(deps.boot_id) and token(deps.owner_id), "Fixed native boot/owner required")
    for _, name in ipairs({ "is_in_game_thread", "get_player", "create_preview_session" }) do check(type(deps[name]) == "function", "Missing dispatcher dependency: " .. name) end
    check(type(deps.eye_bindings) == "table", "Persistent eye registry required")
    for _, name in ipairs({ "inspect", "validate_settings", "apply", "restore" }) do
        check(type(deps.eye_bindings[name]) == "function", "Missing native eye registry method: " .. name)
    end
    local max_preview_sessions = deps.max_preview_sessions or 64
    check(type(max_preview_sessions) == "number" and max_preview_sessions % 1 == 0 and max_preview_sessions >= 1
        and max_preview_sessions <= 64, "Invalid preview construction budget")
    check(deps.admit_request == nil or type(deps.admit_request) == "function", "Invalid native request admission callback")
    local api, busy, sequence, cache, preview, used_leases, used_nonces, opened = {}, false, 0, nil, nil, {}, {}, 0
    local last_lifecycle, disposed = nil, false
    local eye_revision, eye_payload = nil, nil
    local function current(request)
        local player = deps.get_player()
        local snapshot = deps.eye_bindings.inspect(player, player.HeadMesh)
        if request.operation ~= "inspect" then
            check(snapshot.identity_key == request.identity_key and snapshot.baseline_id == request.baseline_id, "Eye baseline or generation changed")
        end
        return snapshot
    end
    local function owned(request, active)
        check(preview ~= nil and preview.owner_id == request.owner_id and preview.lease_id == request.lease_id
            and preview.preview_nonce == request.preview_nonce and preview.identity_key == request.identity_key
            and preview.baseline_id == request.baseline_id, "Eye request does not own this preview generation")
        if active then check(preview.active == true, "Eye preview is not active") end
        return preview
    end
    local function address(request)
        return { owner_id = request.owner_id, lease_id = request.lease_id, identity_key = request.identity_key }
    end
    local function state_after(result)
        if preview and (result.status == "closed" or result.status == "invalidated" or result.status == "cleanup-failed") then
            preview.active = false
            preview.cleanup_blocked = result.status == "cleanup-failed"
        end
        return result
    end
    local function work(request)
        local operation = request.operation
        if operation == "inspect" then return { status = "observed", descriptor = descriptor(current(request)) } end
        if operation == "open" then
            check(not preview or (not preview.active and not preview.cleanup_blocked), "Previous preview still active or awaiting cleanup")
            if preview then
                local cleanup = preview.renderer.inspect_cleanup()
                check(type(cleanup) == "table" and type(cleanup.pending_frames) == "table" and #cleanup.pending_frames <= 2,
                    "Previous preview frame cleanup ledger is unavailable")
                for _, pending in ipairs(cleanup.pending_frames) do
                    check(type(pending) == "table" and preview.acknowledged[pending.sequence] == pending.file_name,
                        "Previous preview frame cleanup is not acknowledged")
                end
            end
            check(opened < max_preview_sessions and not used_leases[request.lease_id] and not used_nonces[request.preview_nonce], "Preview lease/nonce reused or budget exhausted")
            local snapshot = current(request)
            local settings = deps.eye_bindings.validate_settings(canonical(request), snapshot)
            used_leases[request.lease_id], used_nonces[request.preview_nonce], opened = true, true, opened + 1
            preview = { owner_id = request.owner_id, lease_id = request.lease_id, preview_nonce = request.preview_nonce,
                identity_key = request.identity_key, baseline_id = request.baseline_id, active = false, cleanup_blocked = true, acknowledged = {} }
            local created = deps.create_preview_session({ owner_id = request.owner_id, lease_id = request.lease_id,
                preview_nonce = request.preview_nonce, identity_key = request.identity_key, baseline_id = request.baseline_id })
            check(type(created) == "table" and type(created.session) == "table" and type(created.renderer) == "table", "Native preview factory returned no controller")
            preview.session, preview.renderer = created.session, created.renderer
            local result = created.session:open({ owner_id = request.owner_id, lease_id = request.lease_id, identity_key = request.identity_key,
                view_revision = request.view_revision, eye_revision = request.eye_revision,
                view = { yawDegrees = request.yaw_degrees, framing = request.framing, zoom = request.zoom }, settings = settings })
            check(type(result) == "table", "Preview controller returned no operation evidence")
            if result.status == "opened" then
                preview.active, preview.cleanup_blocked = true, false
                result.descriptor, result.preview = descriptor(snapshot), created.renderer.describe()
            end
            return state_after(result)
        end
        owned(request, operation == "enqueue" or operation == "step" or operation == "renew" or operation == "cancel")
        if operation == "apply" or operation == "restore" then
            local snapshot = current(request)
            local desired
            if operation == "apply" then desired = deps.eye_bindings.validate_settings(canonical(request), snapshot)
            else desired = snapshot.original_settings end
            check(type(desired) == "table", "Canonical native eye settings were not returned")
            local fingerprint = Dispatch.format_response({ settings = desired })
            check(eye_revision == nil or request.eye_revision >= eye_revision, "Stale live eye revision")
            check(eye_revision ~= request.eye_revision or eye_payload == fingerprint, "Live eye revision reused for another payload")
            eye_revision, eye_payload = request.eye_revision, fingerprint
            local native
            if operation == "apply" then native = deps.eye_bindings.apply(desired, snapshot)
            else native = deps.eye_bindings.restore(snapshot) end
            check(type(native) == "table", "Native eye operation returned no readback receipt")
            local result = { status = native.ok and "native-readback" or "rejected", ok = native.ok, kind = native.kind,
                reason = native.reason, identity_key = native.identity_key, baseline_id = native.baseline_id,
                schema_id = native.schema_id, current_settings = native.current_settings,
                original_bindings_restored = native.original_bindings_restored, recovery_errors = native.recovery_errors,
                native_readback_verified = native.native_readback_verified, applied_in_game = false }
            if native.snapshot then result.descriptor = descriptor(native.snapshot) end
            return result
        elseif operation == "enqueue" then
            local snapshot = current(request)
            return state_after(preview.session:enqueue({ owner_id = request.owner_id, lease_id = request.lease_id, identity_key = request.identity_key,
                view_revision = request.view_revision, eye_revision = request.eye_revision,
                view = { yawDegrees = request.yaw_degrees, framing = request.framing, zoom = request.zoom },
                settings = deps.eye_bindings.validate_settings(canonical(request), snapshot) }))
        elseif operation == "step" then return state_after(preview.session:step())
        elseif operation == "renew" then return state_after(preview.session:renew(address(request)))
        elseif operation == "cancel" then return state_after(preview.session:cancel(address(request)))
        elseif operation == "close" then return state_after(preview.session:close(address(request), "owner-closed"))
        elseif operation == "ack" then
            check(preview.renderer.acknowledge(request.frame_sequence, request.file_name) == true, "Native frame acknowledgement failed")
            preview.acknowledged[request.frame_sequence] = request.file_name
            return { status = "acknowledged", frame_sequence = request.frame_sequence, file_name = request.file_name }
        end
        error("Unsupported eye dispatcher operation", 0)
    end
    function api.handle(text)
        if busy then return nil, "Native eye dispatcher is busy" end
        local parsed, request = pcall(Dispatch.parse_request, text)
        if not parsed then return nil, tostring(request):sub(1, 512) end
        if request.boot_id ~= deps.boot_id or request.owner_id ~= deps.owner_id then return nil, "Eye channel boot or owner mismatch" end
        if cache and request.command_sequence == cache.sequence and request.request_id == cache.request_id then
            if cache.request == text then return cache.response end
            return nil, "Eye retry differs from its reserved request bytes"
        end
        if disposed then return nil, "Native eye dispatcher is shut down" end
        if request.command_sequence ~= sequence + 1 or (cache and request.request_id == cache.request_id) then return nil, "Eye command sequence or request ID was already used" end
        if deps.is_in_game_thread() ~= true then return nil, "Eye dispatcher requires the native game thread" end
        busy, sequence = true, request.command_sequence
        local ok, result = pcall(function()
            if deps.admit_request then
                local allowed, reason = deps.admit_request(request)
                check(allowed == true, type(reason) == "string" and reason or "Native request admission refused")
            end
            return work(request)
        end)
        if not ok then result = { status = "rejected", reason = tostring(result):sub(1, 1024) } end
        local response = { wire_version = 1, operation = request.operation, boot_id = deps.boot_id, owner_id = deps.owner_id,
            request_id = request.request_id, command_sequence = request.command_sequence, production_ready = false,
            gameplay_verified = false, production_capabilities = "none", result = result, lifecycle = last_lifecycle }
        response.known_preview = preview and { present = true, boot_id = deps.boot_id, owner_id = preview.owner_id,
            lease_id = preview.lease_id, preview_nonce = preview.preview_nonce, identity_key = preview.identity_key,
            baseline_id = preview.baseline_id, active = preview.active, cleanup_blocked = preview.cleanup_blocked }
            or { present = false }
        for _, key in ipairs({ "lease_id", "preview_nonce", "identity_key", "baseline_id", "eye_revision", "view_revision", "frame_sequence", "file_name" }) do response[key] = request[key] end
        local encoded, output = pcall(Dispatch.format_response, response)
        if not encoded then
            response.lifecycle = nil
            response.result = { status = "result-unavailable", native_operation_returned = ok,
                reason = "Native result did not fit the plain bounded response: " .. tostring(output):sub(1, 512) }
            output = Dispatch.format_response(response)
        end
        cache = { sequence = sequence, request_id = request.request_id, request = text, response = output }
        busy = false
        return output
    end
    function api.watchdog()
        if busy then return nil, "Native eye dispatcher is busy" end
        if deps.is_in_game_thread() ~= true then return nil, "Eye watchdog requires the native game thread" end
        if not preview or not preview.active then return { status = "idle", production_ready = false } end
        busy = true
        local ok, result = pcall(function() return state_after(preview.session:maintain()) end)
        busy = false
        if not ok then
            preview.active, preview.cleanup_blocked = false, true
            result = { status = "cleanup-failed", reason = "Native maintenance failed: " .. tostring(result):sub(1, 512), production_ready = false }
        end
        if result.status ~= "active" and result.status ~= "idle" then
            last_lifecycle = { owner_id = preview.owner_id, lease_id = preview.lease_id, preview_nonce = preview.preview_nonce,
                identity_key = preview.identity_key, baseline_id = preview.baseline_id, result = result }
        end
        return result
    end
    function api.shutdown()
        if busy then return nil, "Native eye dispatcher is busy" end
        if deps.is_in_game_thread() ~= true then return nil, "Eye shutdown requires the native game thread" end
        if disposed then return last_lifecycle or { status = "closed", already_closed = true, production_ready = false } end
        disposed, busy = true, true
        local ok, result = pcall(function()
            if preview and preview.session then return state_after(preview.session:shutdown()) end
            if preview and preview.cleanup_blocked then return { status = "cleanup-failed",
                reason = "Preview construction did not return a cleanup controller", production_ready = false } end
            return { status = "closed", production_ready = false }
        end)
        busy = false
        if not ok then
            last_lifecycle = { status = "cleanup-failed", reason = tostring(result):sub(1, 512), production_ready = false }
            return last_lifecycle
        end
        last_lifecycle = result
        return result
    end
    return api
end

return Dispatch
