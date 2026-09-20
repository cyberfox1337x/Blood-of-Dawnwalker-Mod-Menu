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
    require_condition(count == 10 and fields.schema == "5" and OPERATIONS[fields.operation] == fields.intent, "attestation schema or intent is invalid")
    require_condition(fields.build_id == EXPECTED_BUILD and fields.executable_sha256 == EXPECTED_EXECUTABLE
        and fields.metadata_sha256 == EXPECTED_METADATA, "attestation identity or metadata differs from reviewed candidate")
    require_condition(fields.boot_id == boot_id, "attestation belongs to another driver boot")
    require_condition(#fields.nonce == 32 and fields.nonce:match("^%x+$") ~= nil, "attestation nonce is invalid")
    local issued, expires = require_epoch(fields.issued_at), require_epoch(fields.expires_at)
    require_condition(expires > issued and expires - issued <= 120 and now >= issued and now <= expires,
        "attestation is stale, future-dated, or exceeds 120 seconds")
    return fields
end

local function cleanup_lines(value)
    local lines, bytes, seen = {}, 0, {}
    local function visit(prefix, item, depth)
        require_condition(depth <= 10 and #lines < 1024, "cleanup observation exceeds structure bounds")
        if type(item) == "table" then
            require_condition(getmetatable(item) == nil and not seen[item], "cleanup observation is not a plain acyclic value")
            seen[item] = true
            local keys = {}
            for key in pairs(item) do
                require_condition((type(key) == "string" and key:match("^[a-zA-Z][a-zA-Z0-9_]*$") ~= nil)
                    or (type(key) == "number" and key % 1 == 0 and key > 0 and key <= 1024), "cleanup observation key is invalid")
                keys[#keys + 1] = key
                require_condition(#keys <= 1024, "cleanup observation table exceeds bounds")
            end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, key in ipairs(keys) do visit(prefix .. "." .. tostring(key), item[key], depth + 1) end
            seen[item] = nil
        else
            local kind = type(item)
            require_condition(kind == "string" or kind == "number" or kind == "boolean", "cleanup observation contains unsupported value")
            require_condition(kind ~= "number" or (item == item and math.abs(item) < math.huge), "cleanup observation number is not finite")
            local encoded = tostring(item):gsub("[%%\r\n]", function(c) return string.format("%%%02X", string.byte(c)) end)
            local line = prefix .. "=" .. encoded
            bytes = bytes + #line + 1
            require_condition(bytes <= 65536, "cleanup observation exceeds 64 KiB")
            lines[#lines + 1] = line
        end
    end
    visit("eye_cleanup", value, 0)
    return table.concat(lines, "\n")
end

function Driver.install(deps)
    local consumed, busy, completed, pending_cleanup = {}, false, 0, 0
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
    local function frame_count()
        require_route()
        require_condition(deps.is_in_game_thread() == true, "cleanup observation is not on the game thread")
        require_condition(type(deps.get_frame_count) == "function", "native frame count reader is unavailable")
        local frame = deps.get_frame_count()
        require_condition(type(frame) == "number" and frame % 1 == 0 and frame >= 0 and frame < 9007199254740992,
            "native frame count is invalid")
        return frame
    end
    local function cleanup_dependencies(fields)
        local scheduled, accepting, current_observation = {}, true, nil
        local function report(receipt)
            require_condition(current_observation ~= nil and not current_observation.reported,
                "cleanup receipt must be emitted once inside its scheduled callback")
            require_condition(type(receipt) == "table" and receipt.boot_id == boot_id and receipt.nonce == fields.nonce:lower()
                and receipt.after_frames == current_observation.frames,
                "cleanup receipt identity or requested frame differs")
            require_condition(receipt.kind == "native-private-preview-cleanup-observation" and receipt.schema == 1,
                "cleanup receipt kind differs")
            current_observation.reported = true
            local envelope = { schema = 5, operation = fields.operation, boot_id = boot_id, nonce = fields.nonce,
                requested_frames = current_observation.frames, schedule = current_observation.metadata,
                mutation_authorized = false, gameplay_verified = false, production_capabilities = "none", observation = receipt }
            local text = cleanup_lines(envelope)
            deps.log("[DawnwalkerEyeCleanupObservation] report_begin boot_id=" .. boot_id .. " nonce=" .. fields.nonce
                .. " operation=" .. fields.operation .. " after_frames=" .. tostring(current_observation.frames) .. "\n")
            deps.log(text .. "\n")
            deps.log("[DawnwalkerEyeCleanupObservation] report_end operation=" .. fields.operation .. " after_frames="
                .. tostring(current_observation.frames) .. " gameplay_verified=false\n")
        end
        local function schedule(frames, callback)
            require_condition(accepting and fields.operation == "private-preview-roundtrip" and type(callback) == "function",
                "cleanup scheduling is restricted to the active private preview operation")
            require_condition((frames == 1 or frames == 3 or frames == 30) and not scheduled[frames],
                "cleanup schedule exceeds the distinct 1/3/30-frame profile")
            require_condition(type(deps.execute_after_frames) == "function", "EngineTick frame scheduler is unavailable")
            local started = frame_count()
            scheduled[frames] = true
            pending_cleanup = pending_cleanup + 1
            local fired, registering = false, true
            local queued, handle = pcall(deps.execute_after_frames, frames, function()
                if fired then return end
                fired = true
                local metadata = { requested_frames = frames, started_frame = started, schedule_complete = false }
                local observed_ok, observed = pcall(function()
                    require_condition(not registering, "frame scheduler executed synchronously")
                    local current = frame_count()
                    require_condition(current >= started, "native frame count went backwards")
                    metadata.observed_frame, metadata.elapsed_frames = current, current - started
                    require_condition(current - started >= frames, "native frame count has not advanced by requested frames")
                    require_condition(current - started <= 120, "native cleanup observation exceeded its 120-frame window")
                    return current
                end)
                metadata.schedule_complete = observed_ok
                if not observed_ok then metadata.reason = tostring(observed):sub(1, 512) end
                local entry = { frames = frames, metadata = metadata, reported = false }
                current_observation = entry
                local passed_metadata = {}
                for key, value in pairs(metadata) do passed_metadata[key] = value end
                local callback_ok, callback_error = pcall(callback, passed_metadata)
                current_observation = nil
                pending_cleanup = pending_cleanup - 1
                if not callback_ok or not entry.reported then
                    emit("cleanup_observation_failed nonce=" .. fields.nonce .. " after_frames=" .. tostring(frames)
                        .. " reason=" .. tostring(callback_ok and "callback did not emit a receipt" or callback_error):sub(1, 512))
                end
            end)
            registering = false
            if not queued or type(handle) ~= "number" or handle <= 0 or handle % 1 ~= 0 then
                if not fired then pending_cleanup = pending_cleanup - 1; fired = true end
                error("cleanup scheduling failed: " .. tostring(handle), 0)
            end
            require_condition(not fired, "frame scheduler did not defer its callback")
            return handle
        end
        return schedule, report, function() accepting = false end
    end
    local function finish_read(fields)
        local close_cleanup
        local ok, failure = pcall(function()
            local current = validate()
            for key, value in pairs(fields) do
                require_condition(current[key] == value, "attestation changed while queued: " .. key)
            end
            require_route()
            require_condition(deps.is_in_game_thread() == true, "callback is not on the game thread")
            local arguments = {
                game_thread = true, intent = current.intent, operation = current.operation, nonce = current.nonce, boot_id = boot_id, now = deps.now,
                identity = { build_id = current.build_id, executable_sha256 = current.executable_sha256 },
                get_player = deps.get_player, static_find_object = deps.static_find_object,
            }
            if current.operation == "private-preview-roundtrip" then
                arguments.schedule_after_frames, arguments.report_cleanup_observation, close_cleanup = cleanup_dependencies(fields)
            end
            local result = deps.probe.run(arguments)
            if close_cleanup then close_cleanup() end
            local report = deps.probe.format_lines(result)
            require_condition(type(report) == "string" and #report <= 1048576, "read-only report exceeds one MiB")
            emit("report_begin boot_id=" .. boot_id .. " nonce=" .. fields.nonce .. " operation=" .. fields.operation)
            deps.log(report .. "\n")
            emit("report_end ok=" .. tostring(result.ok) .. " operation=" .. fields.operation .. " gameplay_verified=false")
        end)
        if close_cleanup then close_cleanup() end
        busy, completed = false, completed + 1
        if not ok then emit("read_failed=" .. tostring(failure)) end
    end
    local function on_key()
        local ok, failure = pcall(function()
            require_condition(not busy and pending_cleanup == 0 and completed < 8, "eye pilot is busy or its eight-operation budget is exhausted")
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
