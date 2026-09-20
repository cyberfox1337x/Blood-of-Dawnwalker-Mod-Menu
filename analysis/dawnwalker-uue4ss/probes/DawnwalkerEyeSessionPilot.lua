local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_session_pilot")

-- Inert operation adapter for a separate, reviewed channel candidate. Not installed.
local Host = require("DawnwalkerEyeSessionHost")
local Pilot = {}
local owned_host, owned_boot, owned_owner, attempted
local function check(condition, reason) if condition ~= true then error(reason, 0) end end
local function token(value) return type(value) == "string" and #value == 32 and value:match("^[a-f0-9]+$") ~= nil end
local function context(deps)
    check(type(deps) == "table" and deps.game_thread == true, "Session pilot requires the game thread")
    check(type(deps.boot_id) == "string" and deps.boot_id:match("^%d+%-%d+$") ~= nil and #deps.boot_id <= 33
        and token(deps.nonce), "Session pilot boot/nonce is invalid")
    check(type(deps.identity) == "table" and deps.identity.build_id == "25129649"
        and deps.identity.executable_sha256 == "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853",
        "Session pilot build identity differs")
end
function Pilot.run(deps)
    local ok, result = pcall(function()
        context(deps)
        if deps.operation == "session-start" then
            check(deps.intent == "eye-session-start", "Wrong session start intent")
            check(not attempted, "This module already attempted its one session host")
            attempted, owned_boot, owned_owner = true, deps.boot_id, deps.nonce
            owned_host = Host.from_native({ boot_id = owned_boot, owner_id = owned_owner, identity = deps.identity,
                poll_interval_ms = 100,
                pilot_limits = { max_lifetime_ms = 300000, max_responses = 64, max_preview_sessions = 3,
                    cleanup_reserve_responses = 8, cleanup_reserve_ms = 30000 },
                session_limits = { lease_ms = 10000, max_lifetime_ms = 30000, frame_interval_ms = 100, max_frames = 12 } })
            check(type(owned_host) == "table" and type(owned_host.start) == "function" and type(owned_host.stop) == "function"
                and type(owned_host.status) == "function", "Session host factory returned no owned controller")
            local started = owned_host.start()
            check(type(started) == "table", "Session host start returned no evidence")
            return { ok = started.status == "transport-started", status = started.status, host = owned_host.status(),
                native = started, limitation = "Transport prototype only. Native eye and preview operations require separate correlated commands." }
        elseif deps.operation == "session-stop" then
            check(deps.intent == "eye-session-stop", "Wrong session stop intent")
            check(owned_host ~= nil and owned_boot == deps.boot_id, "This boot has no owned session host to stop")
            local stopped = owned_host.stop("explicit-pilot-stop")
            check(type(stopped) == "table", "Session host stop returned no evidence")
            return { ok = stopped.status == "stopped", status = stopped.status, host = owned_host.status(), native = stopped,
                limitation = "Stops the preview channel. Committed player eyes require explicit verified restore before stopping; no implicit restore occurs." }
        end
        error("Unsupported explicit session operation", 0)
    end)
    if not ok then result = { ok = false, status = "rejected", reason = tostring(result):sub(1, 1024) } end
    result.boot_id = type(deps) == "table" and deps.boot_id or nil
    result.owner_id = owned_owner
    result.production_ready, result.gameplay_verified, result.production_capabilities = false, false, "none"
    return result
end
function Pilot.is_active()
    return owned_host ~= nil and owned_host.status().running == true
end
return Pilot
