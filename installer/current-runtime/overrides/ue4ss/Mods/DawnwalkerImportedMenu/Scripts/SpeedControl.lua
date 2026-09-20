local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("speed_private_profile_control")
local Pilot = require("SpeedProfilePilot")
local M = {}
-- The game opens its own pause menu whenever another window (this menu) takes focus,
-- so a request made from the menu can only take effect after the player presses Resume.
-- The verification budget therefore counts unpaused time only; the absolute cap keeps a
-- request that is never resumed from living forever.
local ACTIVE_BUDGET_SECONDS, ACTIVE_BUDGET_TICKS, ABSOLUTE_CAP_SECONDS = 60, 240, 15 * 60
local function finite(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Speed clock unavailable")
    return value
end
function M.Init(menu, helpers)
    local pilot = Pilot.New(helpers)
    local id, confirmed, requested, generation = "DWSpeed", 1, 1, 0
    local timer, pending, clockState, requestStart
    local activeSeconds, activeTicks = 0, 0
    local function readClock(expected)
        local player = helpers.GetPlayer()
        assert(player and player:IsValid(), "Speed player unavailable")
        local world, controller = player:GetWorld(), player.Controller
        assert(world and world:IsValid() and controller and controller:IsValid()
            and controller.Pawn:GetAddress() == player:GetAddress(), "Speed possession unavailable")
        local identity = tostring(player:GetAddress()) .. ":" .. tostring(world:GetAddress()) .. ":" .. tostring(controller:GetAddress())
        assert(not expected or identity == expected, "Speed session changed; recovery retained")
        local library = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        assert(library and library:IsValid(), "Speed timing library unavailable")
        return { identity = identity, paused = library:IsGamePaused(player),
            real = finite(library:GetRealTimeSeconds(player)), game = finite(library:GetTimeSeconds(player)) }
    end
    local function publish(message)
        -- While a request is pending the slider shows what was asked for; the
        -- "requested; confirmed" label and the status keep the distinction honest.
        menu.Set(id, "multiplier", pending and requested or confirmed)
        menu.Set(id, "owned", pilot.owned())
        menu.SetLabel(id, "requested", tostring(requested) .. "x requested; " .. tostring(confirmed) .. "x confirmed")
        local clocks = clockState and string.format(" [paused=%s; game=%.3f; real=%.3f]", tostring(clockState.paused), clockState.game, clockState.real) or ""
        menu.SetLabel(id, "timing", clocks)
        menu.SetLabel(id, "status", message)
    end
    local function cancel()
        generation = generation + 1
        pending = nil
        if timer then CancelDelayedAction(timer); timer = nil end
    end
    local function restoreNow(cause)
        cancel() -- Stop recurring work before any UObject cleanup.
        local owned = pilot.owned()
        local ok, failure = pcall(function() pilot.beginRestore(); pilot.reset() end)
        if ok then confirmed = 1 end
        publish(ok and (cause and ("Speed request failed: " .. tostring(cause)
                .. (owned and "; original movement profile restored." or "; no speed change was applied."))
            or "1x: original movement profile restored.")
            or ("Speed recovery required: " .. tostring(failure) .. ". Select 1x again after gameplay resumes."))
        return ok, failure
    end
    -- A request made while the player is airborne, flying or in wolf form cannot own a
    -- private grounded profile yet. It is held instead of failed: it applies as soon as
    -- normal grounded movement returns, and its deadline still expires it.
    local function remainingBudget() return math.max(0, ACTIVE_BUDGET_SECONDS - activeSeconds) end
    local function waiting(reason)
        return "Requested " .. tostring(requested) .. "x speed. Waiting because " .. tostring(reason)
            .. "; it applies when normal grounded movement returns. "
            .. string.format("Select 1x to cancel; %.0f seconds of gameplay remain.", remainingBudget())
    end
    local function pausedMessage(mode)
        local goal = mode == "apply" and (tostring(requested) .. "x speed") or "the speed change"
        return "The game is paused (its pause menu opens whenever this window has focus). Press Resume in the game and "
            .. goal .. " applies within a second. Select 1x to cancel."
    end
    local start, activate
    activate = function(factor, clock)
        pilot.inspect()
        pilot.begin(factor)
        start("apply", clock)
    end
    start = function(mode, clock, afterRestore)
        cancel()
        local token = generation
        pending = { mode = mode, start = clock.real, lastReal = clock.real, lastGame = clock.game, identity = clock.identity,
            failures = 0, ticks = 0, afterRestore = afterRestore, factor = requested }
        clockState = clock
        publish(mode == "apply" and ("Pending " .. tostring(requested) .. "x speed application. Resume gameplay to verify application.")
            or mode == "wait" and waiting(select(2, pilot.applicable()))
            or "Pending: restoring speed profile. Resume gameplay to verify restoration.")
        timer = LoopInGameThreadWithDelay(250, function()
            if generation ~= token or not pending then return end
            local request = pending
            local ok, cause = pcall(function()
                local current = readClock(request.identity)
                clockState = current
                assert(current.real >= request.start and current.game >= request.lastGame, "Speed clock moved backwards")
                request.ticks = request.ticks + 1
                if not current.paused then
                    activeTicks = activeTicks + 1
                    activeSeconds = activeSeconds + (current.real - request.lastReal)
                end
                request.lastReal = current.real
                if activeSeconds >= ACTIVE_BUDGET_SECONDS or activeTicks >= ACTIVE_BUDGET_TICKS then
                    restoreNow("Pending request exceeded 60 seconds of gameplay; no applied-speed claim was made")
                    return
                end
                if current.real - requestStart >= ABSOLUTE_CAP_SECONDS then
                    restoreNow("Pending request stayed paused for 15 minutes; no applied-speed claim was made")
                    return
                end
                local advanced = not current.paused and current.game > request.lastGame
                request.lastGame = current.game
                if mode == "wait" then
                    local canApply, reason = pilot.applicable()
                    if not canApply then publish(current.paused and pausedMessage(mode) or waiting(reason)); return end
                    cancel()
                    activate(request.factor, current)
                    return
                end
                local verified, failure = pcall(mode == "apply" and pilot.verify or pilot.reset)
                if verified then
                    local nextFactor = request.afterRestore
                    cancel()
                    if mode == "apply" then
                        confirmed = requested
                        publish(tostring(confirmed) .. "x: private profile and effective speed verified. Movement distance is not yet verified.")
                    else
                        confirmed = 1
                        if nextFactor then activate(nextFactor, current)
                        else publish("1x: original movement profile restored.") end
                    end
                    return
                end
                if advanced then request.failures = request.failures + 1 end
                if request.failures >= 6 then restoreNow(failure); return end
                if current.paused then publish(pausedMessage(mode)); return end
                publish((mode == "apply" and ("Pending " .. tostring(requested) .. "x speed application") or "Pending speed restoration")
                    .. "; game-time verification attempts=" .. tostring(request.failures) .. "/6. Keep playing; select 1x to cancel.")
            end)
            if not ok then restoreNow(cause) end
        end)
    end
    local function select(factor)
        menu.Set(id, "multiplier", confirmed)
        assert(type(factor) == "number" and factor >= 1 and factor <= 3 and factor % .5 == 0,
            "Speed must be 1x to 3x in 0.5x steps")
        ExecuteInGameThread(function()
            cancel()
            requested = factor
            local ok, cause = pcall(function()
                local clock = readClock()
                clockState = clock
                requestStart, activeSeconds, activeTicks = clock.real, 0, 0
                if pilot.owned() then
                    pilot.beginRestore()
                    local restored = pcall(pilot.reset)
                    if not restored then start("restore", clock, factor ~= 1 and factor or nil); return end
                    confirmed = 1
                end
                if factor == 1 then publish("1x: original movement profile restored.")
                elseif pilot.applicable() then activate(factor, clock)
                else start("wait", clock) end
            end)
            if not ok then restoreNow(cause); error(cause) end
        end)
    end
    function M.ResetSession()
        requested = 1
        local ok, cause = restoreNow()
        assert(ok, cause)
    end
    menu.Register({ id = id, title = "Movement speed", tab = "Player", items = {
        { id = "multiplier", type = "number", label = "Movement speed multiplier", default = 1, min = 1, max = 3, step = .5, onChange = select },
        { id = "requested", type = "label", label = "1x requested; 1x confirmed" },
        { id = "timing", type = "label", label = "Timing not sampled." },
        { id = "restore", type = "button", label = "Restore normal movement speed", onClick = function() select(1) end },
        { id = "owned", type = "checkbox", label = "Speed profile ownership / recovery", default = false,
          onChange = function(value) assert(value == false, "Use the speed multiplier"); select(1) end },
        { id = "status", type = "label", label = "1x: normal movement. A change made while the game is paused applies as soon as you press Resume." },
    } })
    return pilot
end
return M
