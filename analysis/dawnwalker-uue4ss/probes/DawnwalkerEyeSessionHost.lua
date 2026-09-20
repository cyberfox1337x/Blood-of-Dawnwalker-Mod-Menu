local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_session_host")

-- Uninstalled, inert native host. The attested loader must configure one owner
-- and start it explicitly on EngineTick after the host creates its directories.
local Host = {}
local ROOT = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/"
local BUILD_ID = "25129649"
local EXECUTABLE_SHA256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
local REQUEST_LIMIT, RESPONSE_LIMIT = 32768, 262144
local claimed_boots = {}

local function check(condition, message) if condition ~= true then error(message, 0) end end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function integer(value, minimum, maximum) return finite(value) and value % 1 == 0 and value >= minimum and value <= maximum end
local function token(value) return type(value) == "string" and #value == 32 and value:match("^[a-f0-9]+$") ~= nil end
local function boot(value)
    if type(value) ~= "string" then return false end
    local first, second = value:match("^(%d+)%-(%d+)$")
    return first ~= nil and #first <= 16 and #second <= 16
end
local function reason(value) return tostring(value):sub(1, 512) end
local function valid(object) return object ~= nil and object:IsValid() == true end
local function identify(object, class)
    check(valid(object) and object:IsA(class) == true, "Native host object is unavailable or has the wrong class")
    local address, name = object:GetAddress(), object:GetFullName()
    check(finite(address) and address > 0 and type(name) == "string" and #name > 0 and #name <= 1024
        and not name:find("Default__", 1, true), "Native host identity is invalid")
    return { address = tostring(address), name = name }
end
local function same(object, identity)
    return identity ~= nil and valid(object) and tostring(object:GetAddress()) == identity.address and object:GetFullName() == identity.name
end

local function native_filesystem()
    local filesystem = {}
    function filesystem.exists(path)
        local file, message, code = io.open(path, "rb")
        if file then check(file:close() == true, "Cannot close channel existence handle"); return true end
        if code == 2 then return false end
        error("Cannot determine channel file existence: " .. reason(message), 0)
    end
    function filesystem.read(path, maximum)
        local file, message, code = io.open(path, "rb")
        if not file then
            if code == 2 then return nil end
            error("Cannot open channel input: " .. reason(message), 0)
        end
        local ok, bytes = pcall(function()
            local first = file:read(maximum + 1) or ""
            check(#first <= maximum, "Channel input exceeds its byte bound")
            check(file:seek("set", 0) == 0, "Cannot verify channel input stability")
            check(first == (file:read(maximum + 1) or ""), "Channel input changed while reading")
            return first
        end)
        local closed, close_error = file:close()
        check(closed == true, "Cannot close channel input: " .. reason(close_error))
        if not ok then error(bytes, 0) end
        return bytes
    end
    function filesystem.write_new(path, bytes)
        check(filesystem.exists(path) == false, "Channel temporary output already exists")
        local file, message = io.open(path, "wb")
        check(file ~= nil, "Cannot create channel output: " .. reason(message))
        local ok, failure = pcall(function()
            check(file:write(bytes) ~= nil, "Cannot write complete channel output")
            check(file:flush() == true, "Cannot flush channel output")
        end)
        local closed, close_error = file:close()
        check(closed == true, "Cannot close channel output: " .. reason(close_error))
        if not ok then error(failure, 0) end
    end
    function filesystem.rename_new(source, destination)
        check(filesystem.exists(destination) == false, "Channel destination already exists")
        local renamed, message = os.rename(source, destination)
        check(renamed == true, "Cannot publish channel output: " .. reason(message))
    end
    return filesystem
end

function Host.new(config, platform, modules)
    check(type(config) == "table" and boot(config.boot_id) and token(config.owner_id), "Invalid configured native channel owner or boot")
    check(type(config.identity) == "table" and config.identity.build_id == BUILD_ID
        and config.identity.executable_sha256 == EXECUTABLE_SHA256, "Native eye host build identity mismatch")
    check(type(platform) == "table", "Native host platform is required")
    for _, name in ipairs({ "is_in_game_thread", "engine_tick_available", "process_event_available", "get_player",
        "static_find_object", "find_all_of", "execute_after_frames", "cancel_delayed_action", "get_frame_count", "log" }) do
        check(type(platform[name]) == "function", "Missing native host platform: " .. name)
    end
    local interval = config.poll_interval_ms or 100
    check(integer(interval, 50, 1000), "Native channel poll interval is outside bounds")
    local configured_limits
    if config.session_limits ~= nil then
        check(type(config.session_limits) == "table", "Native session limits must be a table")
        configured_limits = {}
        for key, value in pairs(config.session_limits) do
            check(type(key) == "string" and type(value) == "number", "Native session limits must contain numeric fields")
            configured_limits[key] = value
        end
    end
    local pilot_limits
    if config.pilot_limits ~= nil then
        check(type(config.pilot_limits) == "table", "Pilot limits must be a table")
        for key in pairs(config.pilot_limits) do
            check(key == "max_lifetime_ms" or key == "max_responses" or key == "max_preview_sessions"
                or key == "cleanup_reserve_responses" or key == "cleanup_reserve_ms", "Unknown native pilot limit")
        end
        check(integer(config.pilot_limits.max_lifetime_ms, 1000, 300000)
            and integer(config.pilot_limits.max_responses, 1, 64)
            and integer(config.pilot_limits.max_preview_sessions, 1, 3), "Native pilot limit is outside its reviewed bound")
        pilot_limits = { max_lifetime_ms = config.pilot_limits.max_lifetime_ms,
            max_responses = config.pilot_limits.max_responses, max_preview_sessions = config.pilot_limits.max_preview_sessions,
            cleanup_reserve_responses = config.pilot_limits.cleanup_reserve_responses or 0,
            cleanup_reserve_ms = config.pilot_limits.cleanup_reserve_ms or 0 }
        check(integer(pilot_limits.cleanup_reserve_responses, 0, pilot_limits.max_responses - 1)
            and integer(pilot_limits.cleanup_reserve_ms, 0, pilot_limits.max_lifetime_ms - 1), "Invalid native cleanup reserve")
    end
    config = { boot_id = config.boot_id, owner_id = config.owner_id, session_limits = configured_limits, pilot_limits = pilot_limits }
    local filesystem = platform.filesystem or native_filesystem()
    for _, name in ipairs({ "exists", "read", "write_new", "rename_new" }) do
        check(type(filesystem[name]) == "function", "Missing fixed channel filesystem operation: " .. name)
    end
    modules = modules or { bindings = require("DawnwalkerHumanEyeBindings"), renderer = require("DawnwalkerPrivateEyeRenderer"),
        session = require("DawnwalkerEyePreviewSession"), dispatch = require("DawnwalkerEyeSessionDispatch") }
    for _, name in ipairs({ "bindings", "renderer", "session", "dispatch" }) do
        check(type(modules[name]) == "table" and type(modules[name].new) == "function", "Missing native integration module: " .. name)
    end
    local directory = ROOT .. "native-channel/" .. config.boot_id .. "/" .. config.owner_id .. "/"
    local paths = { command = directory .. "command.txt", response = directory .. "response.txt",
        temporary = directory .. "response.tmp", ready = directory .. "channel.ready" }
    local ready = "wire_version=1\nboot_id=" .. config.boot_id .. "\nowner_id=" .. config.owner_id
        .. "\nbuild_id=" .. BUILD_ID .. "\nexecutable_sha256=" .. EXECUTABLE_SHA256
        .. "\ntransport=eye-session-prototype\nproduction_ready=false\n"
    local state = { running = false, started = false, completed_responses = 0, preview_constructions = 0 }
    local api = {}

    local function route()
        check(platform.is_in_game_thread() == true, "Native eye host requires the game thread")
        check(platform.engine_tick_available() == true and platform.process_event_available() ~= true,
            "Native eye host requires its reviewed EngineTick-only route")
    end
    local function current_world()
        route()
        local player = platform.get_player()
        identify(player, "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
        check(same(player:GetWorld(), state.world_identity), "Native eye host world changed")
        return player:GetWorld()
    end
    local function native_clock()
        local world = current_world()
        check(valid(state.gameplay) and state.gameplay:IsA("/Script/Engine.GameplayStatics"), "Native real-time clock library is unavailable")
        local milliseconds = state.gameplay:GetRealTimeSeconds(world) * 1000
        check(finite(milliseconds) and milliseconds >= 0 and milliseconds <= 9007199254740991
            and (state.last_clock == nil or milliseconds >= state.last_clock), "Native world real-time clock is invalid or regressed")
        state.last_clock = milliseconds
        return milliseconds
    end
    local function log(event, detail)
        platform.log("[DawnwalkerEyeSessionHost] " .. event .. " boot=" .. config.boot_id .. " owner=" .. config.owner_id
            .. (detail and " reason=" .. reason(detail) or ""))
    end
    local function publish(destination, bytes, maximum)
        check(type(bytes) == "string" and #bytes > 0 and #bytes <= maximum, "Native channel output exceeds its bound")
        check(filesystem.exists(destination) == false and filesystem.exists(paths.temporary) == false,
            "Native channel output has not been consumed")
        filesystem.write_new(paths.temporary, bytes)
        check(filesystem.read(paths.temporary, maximum) == bytes, "Native channel temporary output did not read back")
        filesystem.rename_new(paths.temporary, destination)
    end
    local function stop(cause)
        state.running = false
        local cancelled, cancel_error = true, nil
        if state.timer ~= nil then
            local ok, result = pcall(platform.cancel_delayed_action, state.timer)
            cancelled, cancel_error = ok and result == true, ok and nil or reason(result)
            state.timer = nil
        end
        local cleanup, cleanup_error
        if state.dispatcher then
            local ok, result, failure = pcall(state.dispatcher.shutdown)
            if ok then cleanup, cleanup_error = result, failure else cleanup_error = reason(result) end
        end
        local cleanup_failed = state.dispatcher ~= nil and (cleanup == nil or cleanup_error ~= nil or cleanup.status == "cleanup-failed")
        state.final = { status = cleanup_failed and "cleanup-failed" or "stopped",
            reason = cause, scheduler_cancelled = cancelled, scheduler_cancel_error = cancel_error,
            cleanup = cleanup, cleanup_error = cleanup_error, production_ready = false,
            completed_responses = state.completed_responses, preview_constructions = state.preview_constructions,
            native_started_ms = state.native_started_ms, native_last_observed_ms = state.last_clock }
        log("stopped", cause)
        return state.final
    end
    local function poll()
        route()
        local now = native_clock()
        if config.pilot_limits then
            if now - state.native_started_ms >= config.pilot_limits.max_lifetime_ms then stop("pilot-lifetime-budget-exhausted"); return end
            if state.completed_responses >= config.pilot_limits.max_responses then stop("pilot-response-budget-exhausted"); return end
        end
        if state.last_poll ~= nil and now - state.last_poll < interval then return end
        state.last_poll = now
        local lifecycle, failure = state.dispatcher.watchdog()
        check(lifecycle ~= nil, "Native eye watchdog failed: " .. reason(failure))
        if lifecycle.status ~= "active" and lifecycle.status ~= "idle" and lifecycle.status ~= state.last_lifecycle_status then
            log("preview-lifecycle", lifecycle.status)
        end
        state.last_lifecycle_status = lifecycle.status
        -- The host removes its stable command before removing the response.
        -- While the response remains, native work is limited to the watchdog.
        if filesystem.exists(paths.response) then return end
        check(filesystem.exists(paths.temporary) == false, "Native channel has an unresolved temporary response")
        local request = filesystem.read(paths.command, REQUEST_LIMIT)
        if request == nil then state.last_rejected = nil; return end
        check(type(request) == "string" and #request <= REQUEST_LIMIT, "Native channel request exceeds its byte bound")
        if request == state.last_rejected then return end
        local response, rejection = state.dispatcher.handle(request)
        if response == nil then state.last_rejected = request; log("request-rejected", rejection); return end
        state.last_rejected = nil
        publish(paths.response, response, RESPONSE_LIMIT)
        state.completed_responses = state.completed_responses + 1
    end
    local queue_next
    queue_next = function()
        route()
        local scheduled_frame = platform.get_frame_count()
        check(integer(scheduled_frame, 0, 9007199254740991), "Native scheduling frame counter is invalid")
        state.scheduling = true
        local delivered = false
        local handle = platform.execute_after_frames(1, function()
            if delivered then return end
            delivered = true
            state.timer = nil
            if not state.running then return end
            if platform.is_in_game_thread() ~= true then
                state.running = false
                state.final = { status = "cleanup-failed", reason = "Scheduler returned outside the game thread",
                    cleanup_requires_game_thread = true, production_ready = false }
                log("scheduler-rejected", state.final.reason)
                return
            end
            local ok, failure = pcall(function()
                check(not state.scheduling, "Scheduler executed synchronously instead of a future engine frame")
                local current_frame = platform.get_frame_count()
                check(integer(current_frame, 0, 9007199254740991) and current_frame > scheduled_frame,
                    "Native scheduler did not advance to a future engine frame")
                poll()
                if state.running then queue_next() end
            end)
            if not ok then stop(reason(failure)) end
        end)
        state.scheduling = false
        check(integer(handle, 1, 9007199254740991), "Native frame scheduler returned an invalid handle")
        if not state.running then
            local cancelled, cancellation = pcall(platform.cancel_delayed_action, handle)
            check(cancelled and cancellation == true, "Rejected scheduler handle could not be cancelled")
            error("Native scheduler stopped the channel during registration", 0)
        end
        state.timer = handle
    end

    function api.start()
        route()
        check(not state.started and state.final == nil and claimed_boots[config.boot_id] == nil, "This boot already owns or stopped its native eye channel")
        for _, path in pairs(paths) do check(filesystem.exists(path) == false, "Native eye channel is not fresh") end
        state.started, claimed_boots[config.boot_id] = true, config.owner_id
        local ok, failure = pcall(function()
            local player = platform.get_player()
            identify(player, "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
            state.world_identity = identify(player:GetWorld(), "/Script/Engine.World")
            state.gameplay = platform.static_find_object("/Script/Engine.Default__GameplayStatics")
            state.native_started_ms = native_clock()
            local shared = { identity = { build_id = BUILD_ID, executable_sha256 = EXECUTABLE_SHA256 }, boot_id = config.boot_id,
                is_in_game_thread = platform.is_in_game_thread, get_player = platform.get_player, static_find_object = platform.static_find_object }
            local registry = modules.bindings.new(shared)
            state.dispatcher = modules.dispatch.new({ boot_id = config.boot_id, owner_id = config.owner_id,
                is_in_game_thread = platform.is_in_game_thread, get_player = platform.get_player, eye_bindings = registry,
                max_preview_sessions = config.pilot_limits and config.pilot_limits.max_preview_sessions or nil,
                admit_request = function(request)
                    if config.pilot_limits then
                        local bounds = config.pilot_limits
                        local response_reserve = state.completed_responses >= bounds.max_responses - bounds.cleanup_reserve_responses
                        local time_reserve = state.last_clock - state.native_started_ms >= bounds.max_lifetime_ms - bounds.cleanup_reserve_ms
                        if response_reserve or time_reserve then
                            local operation = request.operation
                            if operation ~= "restore" and operation ~= "close" and operation ~= "ack" and operation ~= "inspect" then
                                return false, "Native pilot entered its cleanup reserve; explicitly restore and close before stopping"
                            end
                        end
                    end
                    return true
                end,
                create_preview_session = function(request)
                    route()
                    current_world()
                    check(request.owner_id == config.owner_id and token(request.lease_id) and token(request.preview_nonce), "Native preview factory owner mismatch")
                    check(not config.pilot_limits or state.preview_constructions < config.pilot_limits.max_preview_sessions,
                        "Native pilot preview construction budget exhausted")
                    state.preview_constructions = state.preview_constructions + 1
                    local renderer = modules.renderer.new({ intent = "eye-private-preview-session", nonce = request.preview_nonce,
                        boot_id = config.boot_id, identity = shared.identity, eye_bindings = registry,
                        is_in_game_thread = platform.is_in_game_thread, monotonic_ms = native_clock,
                        get_player = platform.get_player, static_find_object = platform.static_find_object, find_all_of = platform.find_all_of,
                        output_exists = filesystem.exists, output_directory = ROOT .. "native-frames/" .. config.boot_id, pivot_bone_name = "Head" })
                    return { session = modules.session.new(renderer.adapters, config.session_limits), renderer = renderer }
                end })
            publish(paths.ready, ready, 1024)
            state.running = true
            queue_next()
            log("transport-started")
        end)
        if not ok then return stop(reason(failure)) end
        return { status = "transport-started", production_ready = false }
    end
    function api.stop(cause)
        check(platform.is_in_game_thread() == true, "Native eye host cleanup requires the game thread")
        if state.final and not state.final.cleanup_requires_game_thread then return state.final end
        return stop(type(cause) == "string" and reason(cause) or "host-stopped")
    end
    function api.status()
        return { running = state.running, started = state.started, final = state.final, production_ready = false,
            completed_responses = state.completed_responses, preview_constructions = state.preview_constructions,
            native_started_ms = state.native_started_ms, native_last_observed_ms = state.last_clock }
    end
    return api
end

function Host.from_native(config)
    local helpers = require("UEHelpers")
    local function local_player()
        local controller = helpers.GetPlayerController()
        check(valid(controller) and controller:IsLocalPlayerController() == true, "Local controller is unavailable")
        local pawn = controller:K2_GetPawn()
        check(valid(pawn) and valid(controller.Pawn) and pawn:GetAddress() == controller.Pawn:GetAddress()
            and pawn:IsPlayerControlled() == true, "Local player-controller pawn differs")
        return pawn
    end
    return Host.new(config, {
        is_in_game_thread = IsInGameThread,
        engine_tick_available = function() return EngineTickAvailable end,
        process_event_available = function() return ProcessEventAvailable end,
        get_player = local_player, static_find_object = StaticFindObject, find_all_of = FindAllOf, log = print,
        get_frame_count = function()
            check(IsInGameThread() == true, "Native frame counter requires the game thread")
            local library = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
            check(valid(library) and library:IsA("/Script/Engine.KismetSystemLibrary"), "Native frame counter is unavailable")
            return library:GetFrameCount()
        end,
        execute_after_frames = function(frames, callback)
            check(EngineTickAvailable == true and ProcessEventAvailable ~= true and type(ExecuteInGameThreadAfterFrames) == "function",
                "Native EngineTick scheduler is unavailable")
            return ExecuteInGameThreadAfterFrames(frames, callback)
        end,
        cancel_delayed_action = function(handle)
            check(type(CancelDelayedAction) == "function", "Native delayed-action cancellation is unavailable")
            return CancelDelayedAction(handle)
        end,
    })
end

return Host
