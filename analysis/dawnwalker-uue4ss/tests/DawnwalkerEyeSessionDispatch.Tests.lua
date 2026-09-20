local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_session_dispatch_tests")
local Dispatch = dofile(assert(arg[1], "Pass dispatcher source"))
local BOOT, OWNER, LEASE, NONCE = "1000-123", string.rep("a", 32), string.rep("b", 32), string.rep("c", 32)
local KEYS = { "left_primary_u", "left_primary_v", "left_secondary_u", "left_secondary_v",
    "right_primary_u", "right_primary_v", "right_secondary_u", "right_secondary_v" }
local NAMES = { "IrisColor1_U", "IrisColor1_V", "IrisColor2_U", "IrisColor2_V" }
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in pairs(value) do out[k] = copy(v) end; return out
end
local function fields(operation, sequence, changes)
    local value = { wire_version = "1", operation = operation, boot_id = BOOT, owner_id = OWNER,
        request_id = string.format("%032x", sequence), command_sequence = sequence }
    if operation ~= "inspect" then value.lease_id, value.preview_nonce, value.identity_key, value.baseline_id = LEASE, NONCE, "identity", "baseline" end
    if operation == "open" or operation == "enqueue" then
        value.view_revision, value.eye_revision, value.yaw_degrees, value.zoom, value.framing = 0, 0, 0, 1, "head-and-shoulders"
    end
    if operation == "open" or operation == "enqueue" or operation == "apply" then
        value.eye_revision = 1
        for index, key in ipairs(KEYS) do value[key] = index / 10 end
    elseif operation == "restore" then value.eye_revision = 2
    elseif operation == "ack" then value.frame_sequence, value.file_name = 1, "eye-live-" .. NONCE .. "-0001.png" end
    for key, child in pairs(changes or {}) do value[key] = child end
    return value
end
local function wire(value)
    local keys, lines = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local text = tostring(value[key]):gsub("[%%\r\n]", function(c) return string.format("%%%02X", string.byte(c)) end)
        lines[#lines + 1] = key .. "=" .. text
    end
    return table.concat(lines, "\n") .. "\n"
end
local function decoded(text)
    assert(type(text) == "string", "Expected bounded response")
    local result = {}; for key, value in text:gmatch("([^=\n]+)=([^\n]*)\n") do result[key] = value end; return result
end
local function settings()
    local result = { schemaId = "dawnwalker-human-iris-uv-v1-25129649", values = {} }
    for index = 1, 8 do
        local left = index <= 4
        result.values[index] = { parameter = { slotId = left and "head:3" or "head:4",
            materialId = left and "coen-human-eye-left" or "coen-human-eye-right", name = NAMES[(index - 1) % 4 + 1],
            association = 2, index = -1 }, value = { kind = "scalar", value = 0.2 } }
    end
    return result
end
local function fixture(max_preview_sessions)
    local state = { inspections = 0, applies = 0, restores = 0, factories = 0, captures = 0, maintained = 0, closed = 0,
        sequence = 0, on_thread = true, pending = {}, current = settings(), original = settings(), sessions = {} }
    local function snapshot()
        local result = { identity_key = state.foreign and "foreign" or "identity", baseline_id = "baseline",
            schema_id = state.current.schemaId, form = 0, is_wolf_form = false,
            player = { address = "1", name = "Player" }, world = { address = "2", name = "World" },
            head = { address = "3", name = "Head" }, asset = { address = "4", name = "Asset" },
            original_settings = copy(state.original), current_settings = copy(state.current), bindings = {} }
        for side = 1, 2 do
            local item = { slot = side + 2, slot_name = "eye", original_identity = { address = "1" .. side, name = "Original" },
                current_identity = { address = "2" .. side, name = "Current" },
                original_material = { native = function() end }, native_name = function() end, parameters = {} }
            for parameter = 1, 4 do item.parameters[parameter] = { parameter = settings().values[(side - 1) * 4 + parameter].parameter,
                min = 0, max = 1, tolerance = 1e-6, native_info = function() end } end
            result.bindings[side] = item
        end
        return result
    end
    local registry = {}
    function registry.inspect() state.inspections = state.inspections + 1; return snapshot() end
    function registry.validate_settings(value)
        assert(#value.values == 8 and value.schemaId == settings().schemaId)
        for index, entry in ipairs(value.values) do
            local expected = settings().values[index].parameter
            for key, wanted in pairs(expected) do assert(entry.parameter[key] == wanted) end
            assert(entry.value.kind == "scalar" and entry.value.value >= 0 and entry.value.value <= 1, "Native domain rejected")
        end
        return copy(value)
    end
    local function receipt(kind)
        return { ok = true, kind = kind, identity_key = "identity", baseline_id = "baseline", schema_id = state.current.schemaId,
            current_settings = copy(state.current), snapshot = snapshot(), original_bindings_restored = kind == "restore",
            recovery_errors = {}, native_readback_verified = true, applied_in_game = false }
    end
    function registry.apply(value)
        state.applies = state.applies + 1
        if state.reenter then state.reenter() end
        if state.nil_apply then return nil end
        if state.fail_apply then error("Native setter failed with protected recovery") end
        state.current = copy(value)
        if state.quantize then state.current.values[1].value.value = 0.10000000149011612 end
        return receipt("apply")
    end
    function registry.restore() state.restores = state.restores + 1; state.current = copy(state.original); return receipt("restore") end
    local deps = { boot_id = BOOT, owner_id = OWNER, is_in_game_thread = function() return state.on_thread end,
        max_preview_sessions = max_preview_sessions,
        admit_request = function(request)
            if state.blocked_operations and state.blocked_operations[request.operation] then return false, "Cleanup reserve" end
            return true
        end,
        get_player = function() return { HeadMesh = {} } end, eye_bindings = registry,
        create_preview_session = function(identity)
            state.factories = state.factories + 1
            if state.fail_factory then error("Factory did not return a controller") end
            local session, renderer = {}, {}
            function session:open(request) state.open_request = request; return { status = "opened" } end
            function session:enqueue(request) state.enqueue_request = request; return { status = "queued" } end
            function session:step() state.captures = state.captures + 1; return { status = "captured-evidence", evidence = { actual = true } } end
            function session:renew() state.renewed = true; return { status = "renewed" } end
            function session:cancel() state.cancelled = true; return { status = "cancelled" } end
            function session:close()
                state.closed = state.closed + 1
                state.cleanup_ledger = { pending_frames = copy(state.pending) }
                return { status = state.cleanup_failure and "cleanup-failed" or "closed", cleanup = state.cleanup_ledger }
            end
            function session:maintain()
                state.maintained = state.maintained + 1
                if state.expired then return self:close() end
                return { status = "active" }
            end
            function session:shutdown() return self:close() end
            function renderer.describe()
                if state.bad_descriptor then return { native = function() end } end
                return { nonce = identity.preview_nonce, actor = { address = "91", name = "PrivateActor" } }
            end
            function renderer.inspect_cleanup() return state.cleanup_ledger or { pending_frames = copy(state.pending) } end
            function renderer.acknowledge(sequence, filename)
                assert(sequence == 1 and filename == "eye-live-" .. identity.preview_nonce .. "-0001.png")
                assert(state.removed, "File is not absent")
                state.pending = {}; state.acked = true; return true
            end
            state.sessions[#state.sessions + 1] = session
            return { session = session, renderer = renderer }
        end }
    local api = Dispatch.new(deps)
    local function send(operation, changes)
        state.sequence = state.sequence + 1
        local request = wire(fields(operation, state.sequence, changes))
        return decoded(api.handle(request)), request
    end
    return state, deps, api, send
end
local count = 0
local function test(name, run) run(); count = count + 1; print("PASS " .. name) end

test("exact ten operations parse with correct canonical fields", function()
    for _, op in ipairs({ "inspect", "open", "enqueue", "step", "renew", "cancel", "apply", "restore", "ack", "close" }) do
        assert(Dispatch.parse_request(wire(fields(op, 1))).operation == op)
    end
end)
test("malformed duplicate missing unknown oversized and invalid escapes reject", function()
    local request = wire(fields("inspect", 1))
    for _, bad in ipairs({ request .. "operation=inspect\n", request:gsub("operation=inspect\n", ""), request .. "extra=value\n",
        request:sub(1, -2), request .. "\n", request .. "x=" .. string.rep("x", 32768) .. "\n",
        request:gsub("operation=inspect", "operation=inspect%%GG"), request .. "\0", request .. string.char(255) .. "\n" }) do
        assert(not pcall(Dispatch.parse_request, bad))
    end
end)
test("decimal numbers bounded views integers and ACK paths reject ambiguity", function()
    for _, bad in ipairs({ "nan", "inf", "0x1", " 0.1", "1e9999", "1e2e3" }) do
        assert(not pcall(Dispatch.parse_request, wire(fields("apply", 1, { left_primary_u = bad }))))
    end
    for _, change in ipairs({ { yaw_degrees = 70 }, { zoom = 0 }, { view_revision = "01" }, { framing = "arbitrary" } }) do
        assert(not pcall(Dispatch.parse_request, wire(fields("open", 1, change))))
    end
    assert(not pcall(Dispatch.parse_request, wire(fields("ack", 1, { file_name = "../other.png" }))))
end)
test("percent decoding occurs once and encoded controls remain forbidden in identities", function()
    local parsed = Dispatch.parse_request(wire(fields("open", 1, { identity_key = "literal%25" })))
    assert(parsed.identity_key == "literal%25")
    assert(not pcall(Dispatch.parse_request, wire(fields("open", 1, { identity_key = "line\nidentity" }))))
end)
test("construction inert inspect strips wrappers and preserves actual originals", function()
    local state, _, _, send = fixture()
    assert(state.inspections == 0 and state.factories == 0)
    local result = send("inspect")
    assert(state.inspections == 1 and result["result.descriptor.original_settings.values.1.value.value"] == "0.20000000000000001")
    assert(result.production_ready == "false" and result["result.descriptor.bindings.1.original_material"] == nil)
end)
test("preview view and eight settings use exact stable schema identity", function()
    local state, _, _, send = fixture(); send("inspect")
    local response = send("open", { yaw_degrees = -69, framing = "eyes-close-up", view_revision = 3 })
    assert(response["result.status"] == "opened" and state.factories == 1)
    assert(state.open_request.view.yawDegrees == -69 and #state.open_request.settings.values == 8)
    assert(response.view_revision == "3" and response.eye_revision == "1" and response.preview_nonce == NONCE)
end)
test("byte-identical apply retry uses one cached response and never repeats mutation", function()
    local state, _, api, send = fixture(); send("open")
    local response, request = send("apply")
    local cached = api.handle(request)
    assert(decoded(cached)["result.status"] == response["result.status"] and state.applies == 1)
    assert(api.handle(request:gsub("left_primary_u=0.1", "left_primary_u=0.2")) == nil)
    assert(api.handle(wire(fields("inspect", 1))) == nil and state.applies == 1)
end)
test("owner boot skipped sequence and thread rejection do not reserve a mutation", function()
    local state, _, api = fixture()
    for _, change in ipairs({ { owner_id = string.rep("d", 32) }, { boot_id = "wrong" }, { command_sequence = 2 } }) do
        assert(api.handle(wire(fields("inspect", 1, change))) == nil)
    end
    state.on_thread = false; assert(api.handle(wire(fields("inspect", 1))) == nil)
    state.on_thread = true; assert(api.handle(wire(fields("inspect", 1))) ~= nil and state.inspections == 1)
end)
test("native failure is cached without retrying or silently invoking restore", function()
    for _, failure in ipairs({ "throw", "nil" }) do
        local state, _, api, send = fixture(); send("open")
        state.fail_apply, state.nil_apply = failure == "throw", failure == "nil"
        local result, request = send("apply")
        assert(result["result.status"] == "rejected")
        assert(api.handle(request) ~= nil and state.applies == 1 and state.restores == 0)
    end
end)
test("restoration uses registry after preview close or failed cleanup", function()
    for _, failure in ipairs({ false, true }) do
        local state, _, _, send = fixture(); send("open"); send("apply")
        state.cleanup_failure = failure; send("close")
        local result = send("restore")
        assert(result["result.original_bindings_restored"] == "true" and state.restores == 1 and state.factories == 1)
    end
end)
test("foreign baseline and conflicting live revision reject before setter", function()
    local state, _, _, send = fixture(); send("open"); send("apply")
    assert(send("apply", { left_primary_u = 0.3 })["result.status"] == "rejected" and state.applies == 1)
    state.foreign = true
    assert(send("restore")["result.status"] == "rejected" and state.restores == 0)
end)
test("native getter quantization is serialized instead of requested values", function()
    local state, _, _, send = fixture(); send("open"); state.quantize = true
    local result = send("apply")
    assert(tonumber(result["result.current_settings.values.1.value.value"]) == 0.10000000149011612)
    assert(result["result.applied_in_game"] == "false")
end)
test("watchdog maintains expiry without producing unsolicited frames or live mutations", function()
    local state, _, api, send = fixture(); send("open")
    assert(api.watchdog().status == "active" and state.captures == 0)
    state.expired = true; assert(api.watchdog().status == "closed")
    local result = send("inspect")
    assert(result["lifecycle.result.status"] == "closed" and result["lifecycle.preview_nonce"] == NONCE
        and state.captures == 0 and state.applies == 0 and state.restores == 0)
end)
test("queued controls and ACK use exact current lease with echoed identity", function()
    local state, _, _, send = fixture(); send("open")
    assert(send("enqueue", { view_revision = 1 })["result.status"] == "queued")
    assert(send("cancel")["result.status"] == "cancelled" and state.cancelled)
    assert(send("renew")["result.status"] == "renewed" and state.renewed)
    state.removed = true
    local result = send("ack")
    assert(result.frame_sequence == "1" and result.file_name == "eye-live-" .. NONCE .. "-0001.png" and state.acked)
    assert(send("step", { lease_id = string.rep("d", 32) })["result.status"] == "rejected" and state.captures == 0)
end)
test("close reopen waits for pending files and never recaptures original baseline", function()
    local state, _, _, send = fixture(); send("open"); send("apply")
    state.pending = { { sequence = 1, file_name = "eye-live-" .. NONCE .. "-0001.png" } }; send("close")
    local changed = { lease_id = string.rep("d", 32), preview_nonce = string.rep("e", 32) }
    assert(send("open", changed)["result.status"] == "rejected" and state.factories == 1)
    state.removed = true; send("ack")
    assert(send("open", changed)["result.status"] == "opened" and state.factories == 2)
    assert(state.original.values[1].value.value == 0.2 and state.current.values[1].value.value == 0.1)
end)
test("reentrant dispatcher call cannot interleave live setters", function()
    local state, _, api, send = fixture(); send("open")
    state.reenter = function() assert(api.handle(wire(fields("restore", 3))) == nil) end
    send("apply"); assert(state.applies == 1 and state.restores == 0)
end)
test("unserializable native result is cached and never claimed as successful", function()
    local state, _, api, send = fixture(); state.bad_descriptor = true
    local result, request = send("open")
    assert(result["result.status"] == "result-unavailable")
    assert(api.handle(request) ~= nil and state.factories == 1)
end)
test("plain response serializer rejects cycles native values oversized records and unsafe keys", function()
    local cycle = {}; cycle.child = cycle
    for _, value in ipairs({ cycle, { callback = function() end }, { value = string.rep("x", 16385) }, { __proto__ = {} }, { value = 0/0 } }) do
        assert(not pcall(Dispatch.format_response, value))
    end
    assert(Dispatch.format_response({ value = "100%\n" }) == "value=100%25%0A\n")
end)
test("shutdown closes preview once without restoring live eyes", function()
    local state, _, api, send = fixture(); send("open"); send("apply")
    assert(api.shutdown().status == "closed" and api.shutdown().status == "closed")
    assert(state.closed == 1 and state.restores == 0 and api.handle(wire(fields("inspect", 3))) == nil)
end)
test("early open rejection reports the retained restoration lease without native replay", function()
    local state, _, api, send = fixture(1)
    local empty = send("inspect"); assert(empty["known_preview.present"] == "false")
    send("open"); send("apply"); send("close")
    local rejected, request = send("open", { lease_id = string.rep("d", 32), preview_nonce = string.rep("e", 32) })
    assert(rejected["result.status"] == "rejected" and rejected["known_preview.lease_id"] == LEASE)
    assert(rejected["known_preview.preview_nonce"] == NONCE and rejected["known_preview.active"] == "false")
    assert(rejected["known_preview.boot_id"] == BOOT and rejected["known_preview.owner_id"] == OWNER)
    assert(decoded(api.handle(request))["known_preview.lease_id"] == LEASE and state.factories == 1)
    assert(send("restore")["result.status"] == "native-readback" and state.restores == 1)
end)
test("post-reservation factory failure reports the new known recovery context", function()
    local state, _, _, send = fixture()
    send("open"); send("apply"); send("close"); state.fail_factory = true
    local lease, nonce = string.rep("d", 32), string.rep("e", 32)
    local rejected = send("open", { lease_id = lease, preview_nonce = nonce })
    assert(rejected["result.status"] == "rejected" and rejected["known_preview.lease_id"] == lease)
    assert(rejected["known_preview.preview_nonce"] == nonce and rejected["known_preview.cleanup_blocked"] == "true")
    assert(send("restore", { lease_id = lease, preview_nonce = nonce })["result.status"] == "native-readback")
    assert(state.restores == 1)
end)
test("cleanup admission rejects mutation before getters or setters and retains explicit restore", function()
    local state, _, api, send = fixture(); send("open")
    state.blocked_operations = { apply = true, step = true }
    local inspections = state.inspections
    local rejected, bytes = send("apply")
    assert(rejected["result.status"] == "rejected" and rejected["known_preview.lease_id"] == LEASE)
    assert(state.inspections == inspections and state.applies == 0)
    api.handle(bytes); assert(state.applies == 0)
    assert(send("restore")["result.status"] == "native-readback" and state.restores == 1)
end)
print("PASS " .. count .. " native eye session dispatcher groups")
