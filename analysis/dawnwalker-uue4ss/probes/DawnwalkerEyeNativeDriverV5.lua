local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_native_operation_driver")

local Driver = {}
local EXPECTED_BUILD = "25129649"
local EXPECTED_EXECUTABLE = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
local EXPECTED_METADATA = "CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6"
local FIELDS = {
    schema = true, build_id = true, executable_sha256 = true, metadata_sha256 = true,
    boot_id = true, nonce = true, issued_at = true, expires_at = true, intent = true, operation = true,
}

local OPERATIONS = {
    observe = "eye-observe", export = "eye-readback-export",
    ["private-instance-roundtrip"] = "eye-private-instance-roundtrip",
    ["color-roundtrip"] = "eye-color-roundtrip", ["camera-roundtrip"] = "eye-preview-camera-roundtrip",
    ["variant-observe"] = "eye-variant-observe", ["private-preview-roundtrip"] = "eye-private-preview-roundtrip",
    ["human-iris-pair-roundtrip"] = "human-iris-pair-roundtrip",
}

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function require_epoch(value)
    local number = tonumber(value)
    require_condition(number ~= nil and number == number and number % 1 == 0 and number > 0 and number < math.huge,
        "attestation timestamp is invalid")
    return number
end

function Driver.validate_attestation(text, boot_id, now)
    require_condition(type(text) == "string" and #text <= 2048 and not text:find("%z"), "attestation is missing or oversized")
    local fields, count = {}, 0
    for line in text:gmatch("[^\r\n]+") do
        local key, value = line:match("^([a-z0-9_]+)=(.+)$")
        require_condition(key ~= nil and FIELDS[key] == true and fields[key] == nil, "attestation has unknown or duplicate fields")
        fields[key], count = value, count + 1
    end
    require_condition(count == 10 and fields.schema == "4" and OPERATIONS[fields.operation] == fields.intent, "attestation schema or intent is invalid")
    require_condition(fields.build_id == EXPECTED_BUILD and fields.executable_sha256 == EXPECTED_EXECUTABLE
        and fields.metadata_sha256 == EXPECTED_METADATA, "attestation identity or metadata differs from reviewed candidate")
    require_condition(fields.boot_id == boot_id, "attestation belongs to another driver boot")
    require_condition(#fields.nonce == 32 and fields.nonce:match("^%x+$") ~= nil, "attestation nonce is invalid")
    local issued, expires = require_epoch(fields.issued_at), require_epoch(fields.expires_at)
    require_condition(expires > issued and expires - issued <= 120 and now >= issued and now <= expires,
        "attestation is stale, future-dated, or exceeds 120 seconds")
    return fields
end

function Driver.install(deps)
    local consumed, busy, completed = {}, false, 0
    local boot_id = deps.boot_id
    local function emit(message)
        deps.log("[DawnwalkerEyeNativePilot] " .. tostring(message):gsub("[\r\n]", " ") .. "\n")
    end
    local function validate()
        return Driver.validate_attestation(deps.read_attestation(), boot_id, deps.now())
    end
    local function require_route()
        require_condition(deps.engine_tick_available() == true, "EngineTick route is unavailable; no fallback is allowed")
        require_condition(deps.process_event_available() ~= true, "Unexpected ProcessEvent route; candidate requires only EngineTick")
    end
    local function finish_read(fields)
        local ok, failure = pcall(function()
            local current = validate()
            for key, value in pairs(fields) do
                require_condition(current[key] == value, "attestation changed while queued: " .. key)
            end
            require_route()
            require_condition(deps.is_in_game_thread() == true, "callback is not on the game thread")
            local result = deps.probe.run({
                game_thread = true, intent = current.intent, operation = current.operation, nonce = current.nonce, boot_id = boot_id, now = deps.now,
                identity = { build_id = current.build_id, executable_sha256 = current.executable_sha256 },
                get_player = deps.get_player, static_find_object = deps.static_find_object,
            })
            local report = deps.probe.format_lines(result)
            require_condition(type(report) == "string" and #report <= 1048576, "read-only report exceeds one MiB")
            emit("report_begin boot_id=" .. boot_id .. " nonce=" .. fields.nonce .. " operation=" .. fields.operation)
            deps.log(report .. "\n")
            emit("report_end ok=" .. tostring(result.ok) .. " operation=" .. fields.operation .. " gameplay_verified=false")
        end)
        busy, completed = false, completed + 1
        if not ok then emit("read_failed=" .. tostring(failure)) end
    end
    local function on_key()
        local ok, failure = pcall(function()
            require_condition(not busy and completed < 8, "eye pilot is busy or its eight-operation budget is exhausted")
            local fields = validate()
            require_condition(not consumed[fields.nonce], "attestation nonce was already consumed")
            require_route()
            consumed[fields.nonce], busy = true, true
            local queued, queue_error = pcall(deps.execute_on_engine_tick, function() finish_read(fields) end)
            if not queued then busy = false; error(queue_error, 0) end
        end)
        if not ok then emit("read_rejected=" .. tostring(failure)) end
    end
    require_condition(deps.key_available(), "F6 is already registered; eye pilot did not replace it")
    deps.register_key(on_key)
    emit("ready boot_id=" .. boot_id .. " key=F6 capabilities=none automatic_operations=none")
    return { boot_id = boot_id }
end

return Driver
