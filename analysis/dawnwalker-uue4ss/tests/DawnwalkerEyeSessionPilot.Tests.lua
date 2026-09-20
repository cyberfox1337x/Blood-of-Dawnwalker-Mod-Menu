local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_session_pilot_tests")
local path = assert(arg[1], "Pass session pilot adapter")
local function fixture()
    local state = { constructed = 0, started = 0, stopped = 0 }
    package.loaded.DawnwalkerEyeSessionHost = { from_native = function(config)
        state.constructed, state.config = state.constructed + 1, config
        if state.factory_failure then error("Native host unavailable") end
        return { start = function() state.started = state.started + 1; return { status = state.start_status or "transport-started" } end,
            stop = function() state.stopped = state.stopped + 1; return { status = state.stop_status or "stopped" } end,
            status = function() return { running = state.started > 0 and state.stopped == 0, production_ready = false } end }
    end }
    local pilot = dofile(path)
    local deps = { game_thread = true, operation = "session-start", intent = "eye-session-start", boot_id = "1000-123",
        nonce = string.rep("a", 32), identity = { build_id = "25129649",
            executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853" } }
    return state, pilot, deps
end
local count = 0
local function test(name, action) action(); count = count + 1; print("PASS " .. name) end
test("import is inert and explicit start pins owner and exact finite budgets", function()
    local s, p, d = fixture(); assert(s.constructed == 0)
    local r = p.run(d)
    assert(r.ok and not r.production_ready and r.production_capabilities == "none" and r.owner_id == d.nonce)
    assert(s.config.boot_id == d.boot_id and s.config.owner_id == d.nonce and s.config.poll_interval_ms == 100)
    assert(s.config.pilot_limits.max_lifetime_ms == 300000 and s.config.pilot_limits.max_responses == 64
        and s.config.pilot_limits.max_preview_sessions == 3 and s.config.session_limits.max_frames == 12
        and s.config.session_limits.lease_ms == 10000 and s.config.pilot_limits.cleanup_reserve_responses == 8
        and s.config.pilot_limits.cleanup_reserve_ms == 30000 and p.is_active())
    assert(not p.run(d).ok and s.constructed == 1)
end)
test("stop addresses the existing boot owner without silently restoring or starting another host", function()
    local s, p, d = fixture(); assert(p.run(d).ok)
    d.operation, d.intent, d.nonce = "session-stop", "eye-session-stop", string.rep("b", 32)
    local r = p.run(d); assert(r.ok and r.owner_id == string.rep("a", 32) and s.stopped == 1 and s.constructed == 1)
    assert(not p.is_active())
end)
test("unattested wrong build thread identity and operation reject before construction", function()
    for _, change in ipairs({ function(d) d.game_thread = false end, function(d) d.identity.build_id = "old" end,
        function(d) d.intent = "eye-observe" end, function(d) d.operation = "arbitrary" end,
        function(d) d.nonce = "../else" end, function(d) d.boot_id = "bad" end }) do
        local s, p, d = fixture(); change(d); assert(not p.run(d).ok and s.constructed == 0)
    end
end)
test("failed start is never retried and native cleanup failure remains unsuccessful", function()
    local s, p, d = fixture(); s.factory_failure = true
    assert(not p.run(d).ok and not p.run(d).ok and s.constructed == 1)
    s, p, d = fixture(); assert(p.run(d).ok); s.stop_status = "cleanup-failed"
    d.operation, d.intent = "session-stop", "eye-session-stop"
    assert(not p.run(d).ok)
end)
test("missing host or another boot cannot be stopped", function()
    local s, p, d = fixture(); d.operation, d.intent = "session-stop", "eye-session-stop"
    assert(not p.run(d).ok and s.stopped == 0)
    d.operation, d.intent = "session-start", "eye-session-start"; assert(p.run(d).ok)
    d.operation, d.intent, d.boot_id = "session-stop", "eye-session-stop", "1000-999"
    assert(not p.run(d).ok and s.stopped == 0)
end)
print("PASS " .. count .. " native eye session pilot groups")
