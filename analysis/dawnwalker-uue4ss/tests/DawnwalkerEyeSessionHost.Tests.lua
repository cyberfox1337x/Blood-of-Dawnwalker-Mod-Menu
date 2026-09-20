local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_session_host_tests")
local path = assert(arg[1], "Pass the native session host module path")

local function native_object(address, name)
    local object = { address = address, name = name, valid = true }
    function object:IsValid() return self.valid end
    function object:IsA() return true end
    function object:GetAddress() return self.address end
    function object:GetFullName() return self.name end
    return object
end

local function fixture()
    local module = assert(dofile(path))
    local state = { game_thread = true, engine_tick = true, process_event = false, frame = 100, seconds = 12.5,
        timer_sequence = 0, timers = {}, files = {}, reads = {}, writes = {}, renames = {}, logs = {}, handled = {},
        watchdogs = 0, shutdowns = 0, binding_constructors = 0, renderer_constructors = 0, session_constructors = 0 }
    local config = { boot_id = "1788669230-158239", owner_id = string.rep("a", 32), poll_interval_ms = 100,
        identity = { build_id = "25129649", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853" } }
    state.directory = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-channel/"
        .. config.boot_id .. "/" .. config.owner_id .. "/"
    state.paths = { command = state.directory .. "command.txt", response = state.directory .. "response.txt",
        temporary = state.directory .. "response.tmp", ready = state.directory .. "channel.ready" }
    local world, player, gameplay = native_object(1, "World /Game/Actual.World"), native_object(2, "Player Actual.Coen"), native_object(3, "Library GameplayStatics")
    state.world, state.player = world, player
    function player:GetWorld() return state.world end
    function gameplay:GetRealTimeSeconds(context) assert(context == world); state.clock_reads = (state.clock_reads or 0) + 1; return state.seconds end
    local filesystem = {}
    function filesystem.exists(filename) return state.files[filename] ~= nil end
    function filesystem.read(filename, maximum)
        state.reads[#state.reads + 1] = { path = filename, maximum = maximum }
        if state.read_hook then return state.read_hook(filename, maximum) end
        return state.files[filename]
    end
    function filesystem.write_new(filename, bytes)
        assert(state.files[filename] == nil, "Cannot overwrite a file")
        state.writes[#state.writes + 1] = { path = filename, bytes = bytes }
        state.files[filename] = bytes
        if state.write_error then error(state.write_error) end
    end
    function filesystem.rename_new(source, destination)
        assert(state.files[source] ~= nil and state.files[destination] == nil)
        if state.rename_error then error(state.rename_error) end
        state.renames[#state.renames + 1] = { source = source, destination = destination }
        state.files[destination], state.files[source] = state.files[source], nil
    end
    local platform = {
        is_in_game_thread = function() return state.game_thread end,
        engine_tick_available = function() return state.engine_tick end,
        process_event_available = function() return state.process_event end,
        get_player = function() return player end,
        static_find_object = function(name) assert(name == "/Script/Engine.Default__GameplayStatics"); return gameplay end,
        find_all_of = function() return {} end,
        get_frame_count = function() return state.frame end,
        execute_after_frames = function(frames, callback)
            assert(frames == 1)
            state.timer_sequence = state.timer_sequence + 1
            state.timers[state.timer_sequence] = callback
            if state.synchronous_scheduler then callback() end
            if state.scheduler_error then error(state.scheduler_error) end
            return state.timer_sequence
        end,
        cancel_delayed_action = function(handle)
            state.cancelled = (state.cancelled or 0) + 1
            local existed = state.timers[handle] ~= nil
            state.timers[handle] = nil
            return existed
        end,
        log = function(message) state.logs[#state.logs + 1] = message end,
        filesystem = filesystem,
    }
    local registry = { marker = "one retained live baseline registry" }
    local modules = {
        bindings = { new = function(deps) state.binding_constructors = state.binding_constructors + 1; state.binding_deps = deps; return registry end },
        renderer = { new = function(deps)
            state.renderer_constructors = state.renderer_constructors + 1
            state.renderer_deps = deps
            return { adapters = { marker = "renderer", monotonic_ms = deps.monotonic_ms } }
        end },
        session = { new = function(adapters, limits)
            assert(adapters.marker == "renderer")
            state.session_constructors = state.session_constructors + 1
            state.session_limits = limits
            return { marker = "native-session" }
        end },
        dispatch = { new = function(deps)
            state.dispatch_deps = deps
            assert(deps.eye_bindings == registry and deps.owner_id == config.owner_id and deps.boot_id == config.boot_id)
            return {
                handle = function(bytes)
                    state.handled[#state.handled + 1] = bytes
                    if state.rejected then return nil, "Untrusted envelope" end
                    if state.on_handle then state.on_handle(deps, bytes) end
                    return state.response or "wire_version=1\nresult.status=fixture-response\n"
                end,
                watchdog = function()
                    state.watchdogs = state.watchdogs + 1
                    if state.watchdog_failure then return nil, "watchdog failed" end
                    return state.lifecycle or { status = "idle", production_ready = false }
                end,
                shutdown = function()
                    state.shutdowns = state.shutdowns + 1
                    if state.shutdown_failure then return nil, "cleanup unavailable" end
                    return { status = "closed", production_ready = false }
                end,
            }
        end },
    }
    local host = module.new(config, platform, modules)
    function state.advance(seconds, frames)
        state.seconds, state.frame = state.seconds + (seconds or 0.125), state.frame + (frames or 1)
        local earliest
        for id in pairs(state.timers) do if not earliest or id < earliest then earliest = id end end
        assert(earliest, "No future native frame callback")
        local callback = state.timers[earliest]
        state.timers[earliest] = nil
        callback()
    end
    return host, state, config, platform, modules, module
end

local count = 0
local function test(name, action) action(); count = count + 1; print("PASS " .. name) end

test("construction is inert and start publishes only exact transport metadata", function()
    local host, state, config = fixture()
    assert(#state.writes == 0 and state.binding_constructors == 0 and state.timer_sequence == 0)
    assert(host.start().status == "transport-started")
    local expected = "wire_version=1\nboot_id=" .. config.boot_id .. "\nowner_id=" .. config.owner_id
        .. "\nbuild_id=25129649\nexecutable_sha256=" .. config.identity.executable_sha256
        .. "\ntransport=eye-session-prototype\nproduction_ready=false\n"
    assert(state.files[state.paths.ready] == expected and #state.writes == 1 and #state.renames == 1)
    assert(state.writes[1].path == state.paths.temporary and state.renames[1].destination == state.paths.ready)
    assert(state.renderer_constructors == 0 and state.session_constructors == 0 and state.watchdogs == 0)
    assert(host.status().production_ready == false and host.status().running)
end)

test("one atomic response blocks new commands while watchdog remains active", function()
    local host, state = fixture()
    host.start()
    state.files[state.paths.command] = "first-command\n"
    state.advance()
    assert(#state.handled == 1 and state.files[state.paths.response] ~= nil)
    state.files[state.paths.command] = "second-command\n"
    state.advance()
    assert(#state.handled == 1 and state.watchdogs == 2)
    state.files[state.paths.command] = nil
    state.advance()
    assert(#state.handled == 1)
    state.files[state.paths.response] = nil
    state.files[state.paths.command] = "third-command\n"
    state.advance()
    assert(#state.handled == 2 and state.handled[2] == "third-command\n")
    assert(state.files[state.paths.command] ~= nil and state.files[state.paths.temporary] == nil)
end)

test("idle and rejected requests never produce unrequested capture or repeated rejection work", function()
    local host, state = fixture()
    host.start(); state.advance()
    assert(state.watchdogs == 1 and #state.handled == 0)
    state.rejected = true
    state.files[state.paths.command] = "bad-envelope\n"
    state.advance(); state.advance()
    assert(state.watchdogs == 3 and #state.handled == 1 and state.files[state.paths.response] == nil)
    state.files[state.paths.command] = "different-bad-envelope\n"
    state.advance()
    assert(#state.handled == 2 and state.renderer_constructors == 0 and state.shutdowns == 0)
end)

test("inert per-lease factory shares only registry and uses fixed native resources and world clock", function()
    local host, state, config = fixture()
    host.start()
    local factory = state.dispatch_deps.create_preview_session
    local created = factory({ owner_id = config.owner_id, lease_id = string.rep("b", 32), preview_nonce = string.rep("c", 32) })
    assert(created.session.marker == "native-session" and state.renderer_constructors == 1 and state.session_constructors == 1)
    assert(state.binding_constructors == 1 and state.renderer_deps.eye_bindings == state.dispatch_deps.eye_bindings)
    assert(state.renderer_deps.intent == "eye-private-preview-session" and state.renderer_deps.pivot_bone_name == "Head")
    assert(state.renderer_deps.output_directory:sub(-#config.boot_id) == config.boot_id)
    assert(state.renderer_deps.output_directory:find("/native%-frames/"))
    assert(state.renderer_deps.monotonic_ms() == 12500)
    local before = state.renderer_constructors
    assert(not pcall(factory, { owner_id = string.rep("d", 32), lease_id = string.rep("b", 32), preview_nonce = string.rep("c", 32) }))
    assert(state.renderer_constructors == before)
end)

test("fixed paths refuse traversal tokens, unsupported builds and stale channel files", function()
    for _, scenario in ipairs({ "owner", "boot", "build", "ready", "response", "temporary", "command" }) do
        local host, state, config, platform, modules, module = fixture()
        if scenario == "owner" then config.owner_id = "../../other"
        elseif scenario == "boot" then config.boot_id = "178/elsewhere"
        elseif scenario == "build" then config.identity.build_id = "old"
        else state.files[state.paths[scenario]] = "existing" end
        if scenario == "owner" or scenario == "boot" or scenario == "build" then assert(not pcall(module.new, config, platform, modules))
        else assert(not pcall(host.start)) end
        assert(#state.writes == 0 and state.binding_constructors == 0)
    end
end)

test("one configured owner claims the boot and cannot silently restart or replace its registry", function()
    local host, state, config, platform, modules, module = fixture()
    host.start()
    assert(not pcall(host.start))
    config.owner_id = string.rep("b", 32)
    local other = module.new(config, platform, modules)
    assert(not pcall(other.start))
    assert(state.binding_constructors == 1)
end)

test("poll pacing uses native world time and scheduler requires a later actual engine frame", function()
    local host, state = fixture()
    host.start(); state.advance(0.001)
    assert(state.watchdogs == 1)
    state.advance(0.01)
    assert(state.watchdogs == 1)
    state.advance(0.125)
    assert(state.watchdogs == 2)
    state.advance(0.125, 0)
    assert(not host.status().running and state.shutdowns == 1)
end)

test("wrong thread or unreviewed route never starts native ownership", function()
    for _, scenario in ipairs({ "thread", "engine", "process-event" }) do
        local host, state = fixture()
        if scenario == "thread" then state.game_thread = false
        elseif scenario == "engine" then state.engine_tick = false
        else state.process_event = true end
        assert(not pcall(host.start) and state.binding_constructors == 0 and #state.writes == 0)
    end
end)

test("world replacement or regressing native time stops preview resources without rebinding live state", function()
    for _, scenario in ipairs({ "world", "clock" }) do
        local host, state = fixture()
        host.start()
        if scenario == "world" then state.world = native_object(99, "World New.World") else state.seconds = 0 end
        state.advance()
        assert(not host.status().running and state.shutdowns == 1 and state.binding_constructors == 1)
        assert(state.renderer_constructors == 0 and #state.handled == 0)
    end
end)

test("oversized requests and unresolved publication errors stop with exact files preserved", function()
    for _, scenario in ipairs({ "oversized", "write", "rename", "temporary" }) do
        local host, state = fixture()
        host.start()
        state.files[state.paths.command] = scenario == "oversized" and string.rep("x", 32769) or "request\n"
        if scenario == "write" then state.write_error = "disk write failed"
        elseif scenario == "rename" then state.rename_error = "rename failed"
        elseif scenario == "temporary" then state.files[state.paths.temporary] = "orphan" end
        state.advance()
        assert(not host.status().running and state.shutdowns == 1)
        assert(state.files[state.paths.command] ~= nil and state.files[state.paths.ready] ~= nil)
        if scenario == "write" or scenario == "rename" or scenario == "temporary" then assert(state.files[state.paths.temporary] ~= nil) end
    end
end)

test("watchdog cleanup diagnostics survive response backpressure and shutdown failure remains visible", function()
    local host, state = fixture()
    host.start()
    state.files[state.paths.response] = "earlier response"
    state.lifecycle = { status = "cleanup-failed", production_ready = false }
    state.advance()
    assert(state.watchdogs == 1 and host.status().running and #state.handled == 0)
    state.shutdown_failure = true
    local stopped = host.stop("test-close")
    assert(stopped.status == "cleanup-failed" and stopped.cleanup_error == "cleanup unavailable")
    assert(host.stop("again") == stopped and state.shutdowns == 1)
end)

test("wrong-thread callback retains cleanup need until an explicit game-thread stop", function()
    local host, state = fixture()
    host.start(); state.game_thread = false; state.advance()
    assert(not host.status().running and host.status().final.cleanup_requires_game_thread and state.shutdowns == 0)
    state.game_thread = true
    assert(host.stop("recover-route").status == "stopped" and state.shutdowns == 1)
end)

test("synchronous scheduler refusal does not report a started service or recurse", function()
    local host, state = fixture()
    state.synchronous_scheduler = true
    assert(host.start().status == "stopped" and not host.status().running)
    assert(state.timer_sequence == 1 and state.renderer_constructors == 0 and #state.handled == 0)
end)

test("explicit stop cancels the future callback, retains files and closes preview only once", function()
    local host, state = fixture()
    host.start()
    local stopped = host.stop("owner-exit")
    assert(stopped.status == "stopped" and stopped.scheduler_cancelled and state.shutdowns == 1)
    assert(next(state.timers) == nil and state.files[state.paths.ready] ~= nil)
    assert(host.stop("again") == stopped and state.shutdowns == 1)
    assert(state.binding_constructors == 1)
end)

test("configured identity remains bound after caller mutation and stopped hosts cannot start", function()
    local host, state, config = fixture()
    assert(host.start().status == "transport-started")
    config.boot_id, config.owner_id = "1-2", string.rep("b", 32)
    host.stop("configuration-bound")
    assert(state.logs[#state.logs]:find("boot=1788669230-158239 owner=" .. string.rep("a", 32), 1, true))
    local inert, inert_state = fixture()
    assert(inert.stop("before-start").status == "stopped")
    assert(not pcall(inert.start) and inert_state.binding_constructors == 0 and #inert_state.writes == 0)
end)

test("duplicate callback delivery cannot create a second scheduler chain", function()
    local host, state = fixture()
    host.start()
    local first = state.timers[1]
    state.advance()
    local timers, handled = state.timer_sequence, state.watchdogs
    first(); first()
    assert(state.timer_sequence == timers and state.watchdogs == handled)
    host.stop()
    assert(next(state.timers) == nil)
end)

test("pilot time budget uses actual native clock and preserves final evidence", function()
    local _, state, config, platform, modules, module = fixture()
    config.pilot_limits = { max_lifetime_ms = 1000, max_responses = 64, max_preview_sessions = 3 }
    local host = module.new(config, platform, modules); host.start()
    config.pilot_limits.max_lifetime_ms = 300000
    state.advance(1)
    local final = host.status().final
    assert(not host.status().running and final.reason == "pilot-lifetime-budget-exhausted")
    assert(final.native_started_ms == 12500 and final.native_last_observed_ms == 13500 and state.shutdowns == 1)
end)
test("pilot response budget never consumes a new command and leaves published response intact", function()
    local _, state, config, platform, modules, module = fixture()
    config.pilot_limits = { max_lifetime_ms = 300000, max_responses = 1, max_preview_sessions = 3 }
    local host = module.new(config, platform, modules); host.start()
    state.files[state.paths.command] = "one\n"; state.advance()
    local response = state.files[state.paths.response]
    state.files[state.paths.command] = "two\n"; state.advance()
    assert(#state.handled == 1 and state.files[state.paths.response] == response)
    assert(host.status().final.reason == "pilot-response-budget-exhausted" and host.status().completed_responses == 1)
end)
test("pilot construction and session bounds are explicit without changing default registry lifetime", function()
    local _, state, config, platform, modules, module = fixture()
    config.pilot_limits = { max_lifetime_ms = 300000, max_responses = 64, max_preview_sessions = 3 }
    config.session_limits = { lease_ms = 3000, max_lifetime_ms = 30000, frame_interval_ms = 100, max_frames = 12 }
    local host = module.new(config, platform, modules); host.start()
    assert(state.dispatch_deps.max_preview_sessions == 3)
    local request = { owner_id = config.owner_id, lease_id = string.rep("b", 32), preview_nonce = string.rep("c", 32) }
    for _ = 1, 3 do state.dispatch_deps.create_preview_session(request) end
    assert(not pcall(state.dispatch_deps.create_preview_session, request) and state.renderer_constructors == 3)
    assert(state.binding_constructors == 1 and state.session_limits.max_frames == 12 and host.status().preview_constructions == 3)
end)
test("unknown missing excessive and invalid pilot limits reject before native construction", function()
    for _, limits in ipairs({ {}, { max_lifetime_ms = 300001, max_responses = 64, max_preview_sessions = 3 },
        { max_lifetime_ms = 300000, max_responses = 65, max_preview_sessions = 3 },
        { max_lifetime_ms = 300000, max_responses = 64, max_preview_sessions = 4 },
        { max_lifetime_ms = 300000, max_responses = 64, max_preview_sessions = 3, extra = 1 } }) do
        local _, state, config, platform, modules, module = fixture(); config.pilot_limits = limits
        assert(not pcall(module.new, config, platform, modules) and state.binding_constructors == 0)
    end
end)
test("last eight responses are reserved for explicit restore close ack and inspection", function()
    local _, state, config, platform, modules, module = fixture()
    config.pilot_limits = { max_lifetime_ms = 300000, max_responses = 64, max_preview_sessions = 3,
        cleanup_reserve_responses = 8, cleanup_reserve_ms = 30000 }
    local host = module.new(config, platform, modules); host.start()
    local admit = state.dispatch_deps.admit_request
    assert(admit({ operation = "apply" }))
    for index = 1, 56 do
        state.files[state.paths.command] = "command-" .. index .. "\n"
        state.files[state.paths.response] = nil
        state.advance()
    end
    assert(host.status().completed_responses == 56)
    for _, operation in ipairs({ "apply", "open", "enqueue", "step", "renew", "cancel" }) do assert(admit({ operation = operation }) == false) end
    for _, operation in ipairs({ "restore", "close", "ack", "inspect" }) do assert(admit({ operation = operation })) end
    assert(host.status().running)
end)
test("final native thirty seconds permit cleanup without starting another live edit", function()
    local _, state, config, platform, modules, module = fixture()
    config.pilot_limits = { max_lifetime_ms = 300000, max_responses = 64, max_preview_sessions = 3,
        cleanup_reserve_responses = 8, cleanup_reserve_ms = 30000 }
    local host = module.new(config, platform, modules); host.start(); state.advance(270)
    local admit = state.dispatch_deps.admit_request
    assert(host.status().running and admit({ operation = "apply" }) == false and admit({ operation = "restore" }))
    state.advance(30); assert(not host.status().running)
end)
print("PASS " .. count .. " native eye session host test groups")
