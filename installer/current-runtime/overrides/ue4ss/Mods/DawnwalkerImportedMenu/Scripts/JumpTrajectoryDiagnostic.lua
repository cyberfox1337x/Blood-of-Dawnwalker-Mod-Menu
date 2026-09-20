local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("bounded_jump_trajectory_diagnostic")
local M = {}
local function finite(number)
    assert(type(number) == "number" and number == number and math.abs(number) < math.huge, "Invalid trajectory number")
    return number
end
local function vector(source, keys)
    local result = {}
    for _, key in ipairs(keys) do result[key] = finite(source[key]) end
    return result
end
local function distance(left, right)
    return (left.X-right.X)^2 + (left.Y-right.Y)^2 + (left.Z-right.Z)^2
end
function M.New(helpers, pilot, deps)
    assert(type(deps.subscribe) == "function" and type(deps.now) == "function" and type(deps.isPaused) == "function",
        "One-frame game-thread subscription, monotonic milliseconds and pause reader required")
    local record, generation, running = nil, 0, false
    local unsubscribe, sampleGeneration = nil, 0
    local function stopSamples()
        sampleGeneration = sampleGeneration+1
        if unsubscribe then unsubscribe(); unsubscribe = nil end
    end
    local function context()
        assert(IsInGameThread() == true, "Trajectory diagnostic requires game thread")
        local player = helpers.GetPlayer()
        assert(player and player:IsValid(), "Load a player")
        local result = { player = player, world = player:GetWorld(), controller = player.Controller,
            movement = player:GetRebelCharacterMovement(), combat = player.CombatComponent }
        for _, key in ipairs({ "player", "world", "controller", "movement", "combat" }) do
            assert(result[key] and result[key]:IsValid(), "Missing trajectory context: " .. key)
            result[key .. "Id"] = result[key]:GetAddress()
        end
        assert(result.controller.Pawn:GetAddress() == result.playerId
            and result.movement:GetOwner():GetAddress() == result.playerId, "Trajectory possession mismatch")
        return result
    end
    local function same()
        local current = context()
        for _, key in ipairs({ "player", "world", "controller", "movement", "combat" }) do
            assert(current[key .. "Id"] == record[key .. "Id"], "Trajectory identity changed; recovery retained")
        end
        return current
    end
    local function grounded(current)
        return current.movement.MovementMode == 1 and current.movement.CustomMovementMode == 0
    end
    local function position(current) return vector(current.player:K2_GetActorLocation(), { "X", "Y", "Z" }) end
    local function returnStart()
        local current = same()
        assert(grounded(current), "Land before returning to the diagnostic start")
        assert(current.player:K2_TeleportTo(record.position, record.rotation) == true, "Return teleport refused")
        assert(distance(position(current), record.position) <= 1, "Return position differs")
        local rotation = vector(current.player:K2_GetActorRotation(), { "pitch", "Yaw", "Roll" })
        for key, original in pairs(record.rotation) do
            assert(math.abs(rotation[key]-original) <= 0.1, "Return rotation differs")
        end
        assert(math.abs(finite(current.combat:GetHealthPercentage())-record.health) <= 0.00001,
            "Health changed during trajectory test; health was not overwritten")
    end
    local function cleanup()
        if not record then return end
        local failures = {}
        local function attempt(callback)
            local ok, cause = pcall(callback)
            if not ok then failures[#failures+1] = tostring(cause) end
        end
        attempt(stopSamples)
        attempt(function() same().player:StopJumping() end)
        attempt(function() same(); pilot.reset() end)
        attempt(returnStart)
        attempt(function()
            local controller = same().controller
            if record.inputOwned and not record.inputReleased then
                if controller:IsMoveInputIgnored() then controller:SetIgnoreMoveInput(false) end
                record.inputReleased = true -- Never decrement another owner's count on retry.
            end
            assert(controller:IsMoveInputIgnored() == false, "Input baseline not restored")
        end)
        assert(#failures == 0, table.concat(failures, "; "))
        record = nil
    end
    local function run(done)
        assert(type(done) == "function" and not running and not record and not pilot.owned(), "Diagnostic already active or recovery pending")
        local current = context()
        assert(deps.isPaused(current.player) == false and grounded(current)
            and current.player:IsInWolfForm() == false and current.player:GetActorEnableCollision() == true,
            "Use an unpaused human player standing on clear normal ground")
        local velocity = vector(current.player:GetVelocity(), { "X", "Y", "Z" })
        assert(distance(velocity, { X=0, Y=0, Z=0 }) <= 1, "Stand still")
        assert(current.controller:IsMoveInputIgnored() == false, "Input is already suppressed")
        assert(current.player:CanJump() == true, "Native CanJump rejected the trial")
        pilot.inspect() -- All prerequisites are read-only, before input or game mutations.
        current.position = position(current)
        current.rotation = vector(current.player:K2_GetActorRotation(), { "pitch", "Yaw", "Roll" })
        current.health = finite(current.combat:GetHealthPercentage())
        record, running, generation = current, true, generation+1
        local token, evidence = generation, { samples = {}, restorationVerified = false }
        local function finish(failure)
            if token ~= generation then return end
            generation, running = generation+1, false
            local restored, cause = pcall(cleanup)
            evidence.restorationVerified = restored
            evidence.failure = failure and tostring(failure) or nil
            evidence.cleanupFailure = not restored and tostring(cause) or nil
            evidence.passed = not failure and restored
            done(evidence)
        end
        local phase
        phase = function(name)
            stopSamples()
            local phaseToken = sampleGeneration
            local started, count, airborne, released = finite(deps.now()), 0, false, false
            local previous = started
            local currentPhase = { apex = 0, samples = 0, maxIntervalMs = 0, initialFrames = {} }
            evidence.samples[name] = currentPhase
            local currentPlayer = same().player
            assert(currentPlayer:CanJump() == true, "Native CanJump rejected comparison")
            currentPlayer:Jump()
            local function sample()
                if token ~= generation or phaseToken ~= sampleGeneration then return end
                local ok, cause = pcall(function()
                    local ctx, elapsed = same(), finite(deps.now())-started
                    assert(elapsed >= 0 and elapsed <= 3000 and count < 1000, "Jump sample deadline exceeded; recovery required")
                    assert(deps.isPaused(ctx.player) == false and ctx.player:IsInWolfForm() == false, "Jump context changed")
                    count = count+1
                    local location = position(ctx)
                    local interval = started+elapsed-previous
                    previous = started+elapsed
                    currentPhase.maxIntervalMs = math.max(currentPhase.maxIntervalMs, interval)
                    local function flag(value)
                        assert(type(value) == "boolean" or value == 0 or value == 1, "Invalid jump flag")
                        return value == true or value == 1
                    end
                    local frame = { elapsedMs = elapsed, z = location.Z, velocityZ = finite(ctx.player:GetVelocity().Z),
                        mode = ctx.movement.MovementMode, pressed = flag(ctx.player.bPressedJump),
                        wasJumping = flag(ctx.player.bWasJumping), jumpCount = finite(ctx.player.JumpCurrentCount),
                        holdTime = finite(ctx.player.JumpKeyHoldTime), forceTime = finite(ctx.player.JumpForceTimeRemaining),
                        ignoredInput = ctx.controller:IsMoveInputIgnored() }
                    if #currentPhase.initialFrames < 12 then currentPhase.initialFrames[#currentPhase.initialFrames+1] = frame end
                    currentPhase.lastFrame = frame
                    currentPhase.apex = math.max(currentPhase.apex, location.Z-record.position.Z)
                    currentPhase.samples, currentPhase.elapsedMs = count, elapsed
                    -- Capture before stopping: a delayed callback must not erase
                    -- the only evidence of a jump request before actor ticking.
                    assert(interval >= 0 and interval <= 100, "Frame cadence too sparse for physical jump proof")
                    if elapsed >= 60 and not released then ctx.player:StopJumping(); released = true end
                    airborne = airborne or frame.mode == 3
                    assert(distance(location, record.position) <= 4000000, "Trajectory left bounded test area")
                    if airborne and grounded(ctx) then
                        assert(currentPhase.apex > 0 and released, "No physical jump measured")
                        returnStart()
                        if name == "baseline" then
                            pilot.set(true); pilot.verify(); phase("modified")
                        else
                            pilot.verify()
                            evidence.apexRatio = currentPhase.apex/evidence.samples.baseline.apex
                            assert(currentPhase.apex > evidence.samples.baseline.apex, "Modified physical jump did not increase")
                            finish()
                        end
                    end
                end)
                if not ok then finish(cause) end
            end
            unsubscribe = deps.subscribe(sample)
            assert(type(unsubscribe) == "function", "Frame subscription did not return cancellation")
        end
        local ok, cause = pcall(function()
            record.inputOwned = true
            record.controller:SetIgnoreMoveInput(true)
            assert(record.controller:IsMoveInputIgnored() == true, "Input suppression refused")
            phase("baseline")
        end)
        if not ok then finish(cause) end
    end
    return { run = run, owned = function() return record ~= nil end,
        reset = function() generation, running = generation+1, false; cleanup() end }
end
return M
