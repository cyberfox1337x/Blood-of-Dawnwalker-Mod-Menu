local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_native_driver_tests")
local Driver = assert(dofile(assert(arg[1], "Pass the read-only driver path")))

local function attestation(overrides)
    local fields = {
        schema = "4", operation = "observe", intent = "eye-observe", build_id = "25129649",
        executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853",
        metadata_sha256 = "CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6",
        boot_id = "1000-123", nonce = string.rep("a", 32), issued_at = "1000", expires_at = "1100",
    }
    for key, value in pairs(overrides or {}) do fields[key] = value end
    local lines = {}
    for key, value in pairs(fields) do lines[#lines + 1] = key .. "=" .. value end
    return table.concat(lines, "\n")
end

local function fixture()
    local state = { text = attestation(), now = 1000, engine = true, process_event = false,
        game_thread = true, available = true, reads = 0, logs = {}, callbacks = {} }
    local deps = {
        boot_id = "1000-123", now = function() return state.now end,
        read_attestation = function() return state.text end,
        log = function(line) state.logs[#state.logs + 1] = line end,
        engine_tick_available = function() return state.engine end,
        process_event_available = function() return state.process_event end,
        is_in_game_thread = function() return state.game_thread end,
        key_available = function() return state.available end,
        register_key = function(callback) state.key = callback end,
        execute_on_engine_tick = function(callback) state.callbacks[#state.callbacks + 1] = callback end,
        get_player = function() error("mock probe must not call game") end,
        static_find_object = function() error("mock probe must not call game") end,
        probe = {
            run = function(arguments)
                assert(arguments.game_thread and arguments.identity.build_id == "25129649")
                state.reads = state.reads + 1
                return { ok = true }
            end,
            format_lines = function() return "requested_features.mutation_authorized=false" end,
        },
    }
    return state, deps
end

local total = 0
local function test(name, run)
    run(); total = total + 1; print("PASS " .. name)
end

test("valid exact attestation and registration do not read the game", function()
    assert(Driver.validate_attestation(attestation(), "1000-123", 1000).build_id == "25129649")
    local state, deps = fixture()
    Driver.install(deps)
    assert(state.reads == 0 and #state.callbacks == 0 and state.key)
    state.key()
    assert(state.reads == 0 and #state.callbacks == 1)
    state.callbacks[1]()
    assert(state.reads == 1)
end)

test("identity metadata intent and nonce reject before queue", function()
    for _, overrides in ipairs({ { build_id = "25107392" }, { executable_sha256 = "wrong" },
        { metadata_sha256 = "wrong" }, { boot_id = "old" }, { nonce = "short" }, { intent = "mutate" },
        { schema = "1" }, { unexpected = "field" } }) do
        local state, deps = fixture()
        state.text = attestation(overrides); Driver.install(deps); state.key()
        assert(state.reads == 0 and #state.callbacks == 0)
    end
end)

test("malformed duplicate oversized and stale attestations reject", function()
    for _, text in ipairs({ attestation() .. "\nschema=2", attestation() .. "\nbad line",
        string.rep("x", 2049), attestation() .. "\0", attestation({ expires_at = "999" }),
        attestation({ issued_at = "1001" }), attestation({ expires_at = "1121" }),
        attestation({ issued_at = "NaN" }) }) do
        assert(not pcall(Driver.validate_attestation, text, "1000-123", 1000))
    end
end)

test("route availability prohibits fallback", function()
    for _, route in ipairs({ "none", "process" }) do
        local state, deps = fixture()
        if route == "none" then state.engine = false else state.process_event = true end
        Driver.install(deps); state.key()
        assert(state.reads == 0 and #state.callbacks == 0)
    end
end)

test("busy nonce replay and report budget remain bounded", function()
    local state, deps = fixture(); Driver.install(deps)
    state.key(); state.key(); assert(#state.callbacks == 1)
    state.callbacks[1](); state.key(); assert(#state.callbacks == 1)
    for index = 2, 8 do
        state.text = attestation({ nonce = string.format("%032x", index) })
        state.key(); state.callbacks[index]()
    end
    state.text = attestation({ nonce = string.format("%032x", 9) }); state.key()
    assert(#state.callbacks == 8 and state.reads == 8)
end)

test("queued read revalidates expiry identity nonce route and game thread", function()
    for _, failure in ipairs({ "expiry", "nonce", "identity", "route", "thread" }) do
        local state, deps = fixture(); Driver.install(deps); state.key()
        if failure == "expiry" then state.now = 1101
        elseif failure == "nonce" then state.text = attestation({ nonce = string.rep("b", 32) })
        elseif failure == "identity" then state.text = attestation({ build_id = "wrong" })
        elseif failure == "route" then state.engine = false
        else state.game_thread = false end
        state.callbacks[1](); assert(state.reads == 0)
    end
end)

test("occupied F6 is preserved and schedule failure is logged", function()
    local state, deps = fixture(); state.available = false
    assert(not pcall(Driver.install, deps) and state.key == nil)
    state, deps = fixture()
    deps.execute_on_engine_tick = function() error("queue failed") end
    Driver.install(deps); state.key()
    assert(state.reads == 0 and state.logs[#state.logs]:find("queue failed", 1, true))
end)

test("probe failures produce no successful result and allow fresh bounded attempt", function()
    local state, deps = fixture()
    deps.probe.run = function() error("read failed") end
    Driver.install(deps); state.key(); state.callbacks[1]()
    assert(state.logs[#state.logs]:find("read_failed=", 1, true))
    state.text = attestation({ nonce = string.rep("b", 32) }); state.key()
    assert(#state.callbacks == 2)
end)

test("only an exact operation-intent pair may reach the game thread", function()
    local allowed = { observe = "eye-observe", export = "eye-readback-export", ["private-instance-roundtrip"] = "eye-private-instance-roundtrip", ["color-roundtrip"] = "eye-color-roundtrip", ["camera-roundtrip"] = "eye-preview-camera-roundtrip", ["variant-observe"] = "eye-variant-observe", ["private-preview-roundtrip"] = "eye-private-preview-roundtrip", ["human-iris-pair-roundtrip"] = "human-iris-pair-roundtrip" }
    for operation, intent in pairs(allowed) do
        assert(Driver.validate_attestation(attestation({ operation = operation, intent = intent }), "1000-123", 1000).operation == operation)
        if operation ~= "observe" then assert(not pcall(Driver.validate_attestation, attestation({ operation = operation, intent = "eye-observe" }), "1000-123", 1000)) end
    end
    assert(not pcall(Driver.validate_attestation, attestation({ operation = "arbitrary-command", intent = "eye-observe" }), "1000-123", 1000))
end)

test("same nonce cannot change operation or lease while queued", function()
    for _, changed in ipairs({ { operation = "color-roundtrip", intent = "eye-color-roundtrip" }, { issued_at = "999" } }) do
        local state, deps = fixture(); Driver.install(deps); state.key()
        state.text = attestation(changed)
        state.callbacks[1](); assert(state.reads == 0)
    end
end)

test("schema four is required for human scalar operation and queued operation cannot change", function()
    for _, schema in ipairs({ "2", "3" }) do
        assert(not pcall(Driver.validate_attestation, attestation({ schema = schema,
            operation = "human-iris-pair-roundtrip", intent = "human-iris-pair-roundtrip" }), "1000-123", 1000))
    end
    local state, deps = fixture()
    state.text = attestation({ operation = "human-iris-pair-roundtrip", intent = "human-iris-pair-roundtrip" })
    Driver.install(deps); state.key()
    assert(state.reads == 0 and #state.callbacks == 1)
    state.text = attestation({ operation = "private-preview-roundtrip", intent = "eye-private-preview-roundtrip" })
    state.callbacks[1](); assert(state.reads == 0)
end)

print(string.format("Passed %d eye native driver tests.", total))
