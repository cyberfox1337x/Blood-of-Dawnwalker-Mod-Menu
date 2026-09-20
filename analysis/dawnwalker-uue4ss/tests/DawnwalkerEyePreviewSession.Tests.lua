local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_preview_session_tests")
local Session = assert(dofile(assert(arg[1], "Pass the persistent session module path")))

local function request(view_revision, eye_revision)
    return { owner_id = "menu-window", lease_id = "lease-1", identity_key = "actual-identity-1",
        view_revision = view_revision or 0, eye_revision = eye_revision or 0,
        view = { framing = "head-and-shoulders", yawDegrees = view_revision or 0, zoom = 1 },
        settings = { schemaId = "native-eye-schema", color = eye_revision or 0 } }
end

local function fixture(limits)
    local state = { time = 1000, identity = "actual-identity-1", created = 0, released = 0, captures = {}, updates = {}, game_thread = true }
    local adapters = {
        is_game_thread = function() return state.game_thread end,
        monotonic_ms = function() return state.time end,
        inspect_identity = function() return state.identity end,
        validate_view = function(view) return view.zoom >= 0.75 and view.zoom <= 1.25 end,
        validate_settings = function(settings) return settings.schemaId == "native-eye-schema" end,
        create_preview = function(identity)
            state.created = state.created + 1
            local handle = { id = state.created, identity = identity, owns_private_mids = true }
            state.handle = handle
            return handle
        end,
        verify_private_preview = function(handle, identity) return handle == state.handle and handle.identity == identity and handle.owns_private_mids end,
        update_preview = function(handle, desired)
            assert(handle == state.handle)
            state.updates[#state.updates + 1] = desired
            if state.on_update then state.on_update() end
            return { observed = desired, native_readback = true }
        end,
        validate_readback = function(readback, desired)
            return not state.bad_readback and readback.native_readback and readback.observed.eye_revision == desired.eye_revision
        end,
        capture_preview = function(handle, readback, sequence)
            if state.on_capture then state.on_capture() end
            local evidence = { kind = "native-preview-evidence", preview_id = handle.id, sequence = sequence,
                eye_revision = readback.observed.eye_revision, view_revision = readback.observed.view_revision,
                capture_timestamp_known = false, frame_verified = false }
            state.captures[#state.captures + 1] = evidence
            return evidence
        end,
        validate_capture_evidence = function(evidence, readback, sequence, handle)
            return not state.bad_evidence and evidence.preview_id == handle.id and evidence.sequence == sequence
                and evidence.eye_revision == readback.observed.eye_revision and evidence.view_revision == readback.observed.view_revision
        end,
        release_preview = function(handle, cause)
            state.released = state.released + 1
            assert(handle == state.handle)
            if state.cleanup_error then error(state.cleanup_error) end
            state.cleanup_reason = cause
            return { owned_cleanup_acknowledged = true, destruction_pending = true, target_release_requested = true }
        end,
    }
    state.adapters = adapters
    return Session.new(adapters, limits), state
end

local count = 0
local function test(name, action) action(); count = count + 1; print("PASS " .. name) end

test("construction is inert and open remains evidence-only until actual adapter capture", function()
    local controller, state = fixture()
    assert(state.created == 0 and state.released == 0)
    assert(controller:open(request()).status == "opened" and state.created == 1)
    assert(#state.captures == 0)
    local result = controller:step()
    assert(result.status == "captured-evidence" and result.production_ready == false and result.evidence == state.captures[1])
    assert(result.capturedAtMs == nil and result.evidence.capture_timestamp_known == false)
end)

test("malformed or unsupported requests never create native resources", function()
    for _, scenario in ipairs({ "identity", "yaw", "zoom", "revision", "schema", "cyclic" }) do
        local controller, state = fixture()
        local value = request()
        if scenario == "identity" then value.identity_key = "old"
        elseif scenario == "yaw" then value.view.yawDegrees = 70
        elseif scenario == "zoom" then value.view.zoom = 2
        elseif scenario == "revision" then value.eye_revision = 0.5
        elseif scenario == "schema" then value.settings.schemaId = "unknown"
        else value.settings.cycle = value.settings end
        assert(controller:open(value).status == "rejected" and state.created == 0, scenario)
    end
end)

test("unisolated preview eye bindings reject open and clean only returned private handle", function()
    local controller, state = fixture()
    state.adapters.verify_private_preview = function() return false end
    assert(controller:open(request()).status == "invalidated" and state.released == 1)
end)

test("foreign owner cannot enqueue, renew, replace or close the active preview", function()
    local controller, state = fixture()
    assert(controller:open(request()).status == "opened")
    local foreign = request(1, 1); foreign.owner_id = "other-window"
    assert(controller:enqueue(foreign).status == "rejected")
    assert(controller:renew(foreign).status == "rejected")
    assert(controller:close(foreign).status == "rejected")
    assert(controller:open(foreign).status == "rejected" and state.created == 1 and state.released == 0)
end)

test("queued view and eye updates coalesce to newest state and request objects are copied", function()
    local controller, state = fixture()
    controller:open(request())
    controller:enqueue(request(1, 1))
    local newest = request(2, 2)
    assert(controller:enqueue(newest).status == "queued")
    newest.view.yawDegrees, newest.settings.color = 60, 99
    assert(controller:step().status == "captured-evidence")
    assert(#state.updates == 1 and state.updates[1].view.yawDegrees == 2 and state.updates[1].settings.color == 2)
end)

test("stale or reused revisions reject without displacing newest queued work", function()
    local controller, state = fixture()
    controller:open(request())
    controller:enqueue(request(2, 2))
    assert(controller:enqueue(request(1, 2)).status == "rejected")
    assert(controller:enqueue(request(2, 1)).status == "rejected")
    local conflict = request(2, 2); conflict.settings.color = 4
    assert(controller:enqueue(conflict).status == "rejected")
    assert(controller:enqueue(request(2, 2)).status == "unchanged")
    controller:step()
    assert(state.updates[1].eye_revision == 2 and state.updates[1].settings.color == 2)
end)

test("frame interval caps idle and edited capture frequency with no frame backlog", function()
    local controller, state = fixture()
    controller:open(request()); controller:step()
    controller:enqueue(request(1, 1))
    state.time = 1099
    assert(controller:step().status == "waiting" and #state.captures == 1)
    state.time = 1100
    assert(controller:step().sequence == 2 and #state.captures == 2)
    state.time = 1200
    assert(controller:step().sequence == 3 and state.updates[3].eye_revision == 1)
end)

test("lease expiration clears queued work and performs paired preview cleanup once", function()
    local controller, state = fixture()
    controller:open(request()); controller:enqueue(request(1, 1))
    state.time = 4000
    assert(controller:step().status == "invalidated" and state.cleanup_reason == "lease-expired")
    assert(#state.updates == 0 and state.released == 1)
    assert(controller:close(request()).already_closed and state.released == 1)
end)

test("renewal cannot exceed hard session lifetime or revive an expired lease", function()
    local controller, state = fixture({ lease_ms = 500, max_lifetime_ms = 1000 })
    controller:open(request())
    state.time = 1400; assert(controller:renew(request()).status == "renewed")
    state.time = 1800; assert(controller:renew(request()).status == "renewed")
    state.time = 2000; assert(controller:renew(request()).status == "invalidated" and state.released == 1)
end)

test("source generation change invalidates before native mutation", function()
    local controller, state = fixture()
    controller:open(request()); controller:enqueue(request(1, 1)); state.identity = "replacement-pawn"
    assert(controller:step().status == "invalidated" and #state.updates == 0 and state.released == 1)
end)

test("identity loss or lease expiry during capture drops evidence and cleans resources", function()
    for _, scenario in ipairs({ "identity", "lease" }) do
        local controller, state = fixture()
        controller:open(request())
        state.on_capture = function()
            if scenario == "identity" then state.identity = "replacement-world" else state.time = 4001 end
        end
        local result = controller:step()
        assert(result.status == "invalidated" and result.evidence == nil and state.released == 1, scenario)
    end
end)

test("unverified native readback or capture evidence never becomes a published frame", function()
    for _, scenario in ipairs({ "readback", "capture" }) do
        local controller, state = fixture()
        controller:open(request())
        if scenario == "readback" then state.bad_readback = true else state.bad_evidence = true end
        local result = controller:step()
        assert(result.status == "invalidated" and result.evidence == nil and state.released == 1, scenario)
        if scenario == "readback" then assert(#state.captures == 0) end
    end
end)

test("native operation failure cleans resources and failed cleanup blocks further opens", function()
    local controller, state = fixture()
    controller:open(request())
    state.on_update = function() error("private material read failed") end
    state.cleanup_error = "native owner unavailable"
    assert(controller:step().status == "cleanup-failed" and state.released == 1)
    local next_request = request(); next_request.lease_id = "lease-2"
    assert(controller:open(next_request).status == "rejected" and state.created == 1)
    assert(controller:close(request()).status == "cleanup-failed" and state.released == 1)
    assert(controller:shutdown().status == "cleanup-failed" and state.released == 1)
end)

test("unconfirmed partial construction cleanup locks out replacement resource creation", function()
    for _, scenario in ipairs({ "throw", "nil" }) do
        local controller, state = fixture()
        state.adapters.create_preview = function()
            state.created = state.created + 1
            if scenario == "throw" then error("deferred native allocation failed") end
            return nil
        end
        assert(controller:open(request()).status == "cleanup-failed" and state.created == 1)
        local next_request = request(); next_request.lease_id = "lease-2"
        assert(controller:open(next_request).status == "rejected" and state.created == 1)
        assert(controller:close(request()).status == "cleanup-failed")
    end
end)

test("close and reopen require a new lease and a fresh owned native handle", function()
    local controller, state = fixture()
    controller:open(request()); controller:step(); controller:close(request(), "menu-hidden")
    assert(state.released == 1 and state.cleanup_reason == "menu-hidden")
    assert(controller:open(request()).status == "rejected")
    local next_request = request(); next_request.lease_id = "lease-2"
    assert(controller:open(next_request).status == "opened" and state.created == 2)
    local result = controller:step()
    assert(result.sequence == 1 and result.evidence.preview_id == 2)
end)

test("frame budget and shutdown bound retained native resources", function()
    local controller, state = fixture({ max_frames = 1 })
    controller:open(request()); assert(controller:step().status == "captured-evidence")
    state.time = 1100
    assert(controller:step().status == "invalidated" and state.cleanup_reason == "frame-budget-exhausted")
    assert(controller:shutdown().status == "closed")
    local next_request = request(); next_request.lease_id = "lease-2"
    assert(controller:open(next_request).status == "rejected")
end)

test("wrong-thread and nested operations cannot run native controller work", function()
    local controller, state = fixture()
    state.game_thread = false
    assert(controller:open(request()).status == "rejected" and state.created == 0)
    state.game_thread = true
    controller:open(request())
    state.on_update = function() assert(controller:close(request()).status == "rejected") end
    assert(controller:step().status == "captured-evidence" and state.released == 0)
end)

test("backward monotonic clock invalidates before additional capture", function()
    local controller, state = fixture()
    controller:open(request()); controller:step(); state.time = 999
    assert(controller:step().status == "invalidated" and #state.captures == 1 and state.released == 1)
end)

test("backpressure retains only the newest request without native work and still expires leases", function()
    local controller, state = fixture()
    state.adapters.can_capture = function() return state.consumer_ready == true end
    assert(controller:open(request()).status == "opened")
    assert(controller:enqueue(request(1, 1)).status == "queued")
    assert(controller:step().status == "waiting-for-frame-consumer" and #state.updates == 0)
    assert(controller:enqueue(request(2, 2)).status == "queued")
    state.consumer_ready = true
    assert(controller:step().status == "captured-evidence" and #state.updates == 1)
    assert(state.updates[1].view_revision == 2 and state.updates[1].eye_revision == 2)
    state.consumer_ready, state.time = false, 4000
    assert(controller:step().status == "invalidated" and state.released == 1)
end)

test("cancelled initial or later queued tuples never replay through idle latest fallback", function()
    for _, captured_before_cancel in ipairs({ false, true }) do
        local controller, state = fixture()
        assert(controller:open(request()).status == "opened")
        if captured_before_cancel then assert(controller:step().status == "captured-evidence") end
        assert(controller:enqueue(request(2, 2)).status == "queued")
        local result = controller:cancel(request())
        assert(result.status == "cancelled" and result.view_revision == 2 and result.eye_revision == 2)
        assert(result.production_ready == false and not result.already_cancelled)
        for _, instant in ipairs({ 1100, 1200, 1300 }) do
            state.time = instant
            assert(controller:step().status == "waiting-for-preview-request")
        end
        assert(#state.updates == (captured_before_cancel and 1 or 0) and #state.captures == #state.updates)
        assert(state.released == 0 and controller:cancel(request()).already_cancelled)
    end
end)

test("cancel preserves revision validation and resumes only on an explicit valid enqueue", function()
    local controller, state = fixture()
    controller:open(request()); controller:enqueue(request(2, 2)); controller:cancel(request())
    assert(controller:enqueue(request(1, 2)).status == "rejected")
    local conflicting = request(2, 2); conflicting.settings.color = 3
    assert(controller:enqueue(conflicting).status == "rejected")
    local unsupported = request(3, 3); unsupported.view.yawDegrees = 100
    assert(controller:enqueue(unsupported).status == "rejected")
    assert(controller:step().status == "waiting-for-preview-request" and #state.captures == 0)
    assert(controller:enqueue(request(2, 2)).status == "queued")
    assert(controller:step().status == "captured-evidence" and state.updates[1].eye_revision == 2)
    assert(controller:cancel(request()).status == "cancelled")
    state.time = 1100
    assert(controller:enqueue(request(3, 3)).status == "queued")
    assert(controller:step().status == "captured-evidence" and state.updates[2].eye_revision == 3)
end)

test("foreign or nested cancellation cannot interrupt the owned native operation", function()
    local controller, state = fixture()
    assert(controller:cancel(request()).status == "rejected")
    controller:open(request()); controller:enqueue(request(1, 1))
    for _, field in ipairs({ "owner_id", "lease_id", "identity_key" }) do
        local foreign = request(); foreign[field] = "foreign"
        assert(controller:cancel(foreign).status == "rejected")
    end
    state.game_thread = false
    assert(controller:cancel(request()).status == "rejected")
    state.game_thread = true
    state.on_update = function() assert(controller:cancel(request()).status == "rejected") end
    assert(controller:step().status == "captured-evidence" and #state.updates == 1 and state.released == 0)
end)

test("cancelled previews still enforce leases, capacity and source invalidation", function()
    local controller, state = fixture()
    controller:open(request()); controller:step(); controller:enqueue(request(1, 1)); controller:cancel(request())
    state.adapters.can_capture = function() return false end
    state.time = 1100
    assert(controller:step().status == "waiting-for-preview-request")
    assert(controller:renew(request()).status == "renewed")
    assert(controller:step().status == "waiting-for-preview-request" and #state.updates == 1)
    state.time = 4100
    assert(controller:step().status == "invalidated" and state.cleanup_reason == "lease-expired")
    assert(state.released == 1 and #state.updates == 1)

    local replaced, replacement = fixture()
    replaced:open(request()); replaced:cancel(request()); replacement.identity = "new-pawn"
    assert(replaced:step().status == "invalidated" and replacement.released == 1 and #replacement.updates == 0)
end)

test("maintenance expires abandoned previews without unsolicited updates or captures", function()
    local controller, state = fixture()
    assert(controller:maintain().status == "idle")
    controller:open(request()); controller:enqueue(request(1, 1))
    assert(controller:maintain().status == "active")
    controller:cancel(request())
    assert(controller:maintain().suspended and #state.updates == 0 and #state.captures == 0)
    state.time = 4000
    assert(controller:maintain().status == "invalidated" and state.released == 1)
    assert(#state.updates == 0 and #state.captures == 0 and controller:maintain().status == "idle")
end)

test("maintenance retains thread and source ownership checks without renewing the lease", function()
    local controller, state = fixture()
    controller:open(request())
    state.game_thread = false
    assert(controller:maintain().status == "rejected" and state.released == 0)
    state.game_thread = true
    state.identity = "replacement-world"
    assert(controller:maintain().status == "invalidated" and state.released == 1 and #state.updates == 0)
end)

print("PASS " .. count .. " persistent eye preview session test groups")
