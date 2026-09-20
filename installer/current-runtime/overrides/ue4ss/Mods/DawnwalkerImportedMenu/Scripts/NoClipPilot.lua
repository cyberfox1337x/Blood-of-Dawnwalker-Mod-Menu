local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("no_clip_pilot")
local M = {}
local function valid(object) return object ~= nil and object:IsValid() end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end

-- MOVE_None=0 suspends custom locomotion during direct spatial flight.
-- MOVE_Walking=1 is required for a recoverable starting position.
function M.New(helpers, flightModule, onFlightFailure)
    local owned, failed = nil, false
    local flight
    local function context()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a player first")
        local world, controller, movement = player:GetWorld(), player.Controller, player:GetRebelCharacterMovement()
        assert(valid(world) and valid(controller) and valid(movement), "Controlled movement required")
        assert(valid(controller.Pawn) and controller.Pawn:GetAddress() == player:GetAddress(), "Possession mismatch")
        assert(valid(player.CharacterMovement) and player.CharacterMovement:GetAddress() == movement:GetAddress(), "Movement resolver mismatch")
        assert(movement:GetOwner():GetAddress() == player:GetAddress(), "Movement owner mismatch")
        local record = { player = player, world = world, controller = controller, movement = movement }
        for _, name in ipairs({"player", "world", "controller", "movement"}) do record[name .. "Address"] = record[name]:GetAddress() end
        return record
    end
    local function verify(record)
        local current = context()
        for _, name in ipairs({"player", "world", "controller", "movement"}) do
            assert(valid(record[name]) and record[name]:GetAddress() == record[name .. "Address"]
                and current[name .. "Address"] == record[name .. "Address"], "No Clip player identity changed; reload the save")
        end
    end
    local function restore()
        if flight then flight.stop(); flight = nil end
        if not owned then return end
        local record = owned
        verify(record)
        assert(record.player:K2_TeleportTo(record.position, record.rotation) == true, "No Clip return teleport refused")
        local actual = record.player:K2_GetActorLocation()
        assert(finite(actual.X) and finite(actual.Y) and finite(actual.Z), "No Clip return position invalid")
        local distance = (actual.X-record.position.X)^2 + (actual.Y-record.position.Y)^2 + (actual.Z-record.position.Z)^2
        assert(distance <= 100, "No Clip return position readback failed")
        record.movement:SetMovementMode(record.mode, record.customMode)
        assert(record.movement.MovementMode == record.mode and record.movement.CustomMovementMode == record.customMode,
            "No Clip movement restoration failed")
        record.player:SetActorEnableCollision(record.collision)
        assert(record.player:GetActorEnableCollision() == record.collision, "No Clip collision restoration failed")
        verify(record)
        owned = nil
    end
    local function verifyActive()
        if not owned then return end
        verify(owned)
        assert(owned.movement.MovementMode == 0 and owned.movement.CustomMovementMode == 0
            and owned.player:GetActorEnableCollision() == false, "No Clip state changed; disable to restore the start position")
    end
    local function enable()
        assert(not failed, "Prior No Clip failure requires restarting and reloading")
        if owned then verifyActive(); return end
        local record = context()
        record.mode, record.customMode = record.movement.MovementMode, record.movement.CustomMovementMode
        record.collision = record.player:GetActorEnableCollision()
        assert(record.mode == 1 and record.customMode == 0 and record.collision == true,
            "Stand on normal ground before enabling No Clip")
        local position, rotation = record.player:K2_GetActorLocation(), record.player:K2_GetActorRotation()
        assert(finite(position.X) and finite(position.Y) and finite(position.Z)
            and finite(rotation.pitch) and finite(rotation.Yaw) and finite(rotation.Roll), "Invalid No Clip starting transform")
        record.position = { X = position.X, Y = position.Y, Z = position.Z }
        record.rotation = { pitch = rotation.pitch, Yaw = rotation.Yaw, Roll = rotation.Roll }
        verify(record)
        owned = record
        record.movement:SetMovementMode(0, 0)
        assert(record.movement.MovementMode == 0 and record.movement.CustomMovementMode == 0, "Movement suspension refused")
        record.player:SetActorEnableCollision(false)
        assert(record.player:GetActorEnableCollision() == false, "No Clip collision change refused")
        verify(record)
        if flightModule then
            local library = StaticFindObject("/Script/Engine.Default__GameplayStatics")
            assert(valid(library), "Flight pause state unavailable")
            flight = flightModule.New({
                context = function() return record end, validate = verify,
                allowed = function(current)
                    return library:IsGamePaused(current.player) == false and current.controller.bShowMouseCursor == false
                end,
                makeKey = function(name) return { KeyName = FName(name) } end,
                deltaSeconds = function(current) return library:GetWorldDeltaSeconds(current.player) end,
                subscribe = function(callback)
                    local handle = LoopInGameThreadAfterFrames(1, callback)
                    return function() CancelDelayedAction(handle) end
                end,
                onFailure = function(message)
                    local restored, failure = pcall(restore)
                    failed = not restored
                    if onFlightFailure then onFlightFailure(message .. (restored and "; No Clip restored" or "; recovery=" .. tostring(failure))) end
                end,
            })
            flight.start()
        end
    end
    return {
        set = function(value)
            assert(type(value) == "boolean", "No Clip requires a boolean")
            local ok, failure = pcall(value and enable or restore)
            if not ok then
                local restored, restoreFailure = pcall(restore)
                -- Only an unrecovered world latches. If restore put movement and
                -- collision back, the attempt cost nothing and may be retried.
                failed = not restored
                error(tostring(failure) .. (restored and "; original movement restored" or "; recovery pending: " .. tostring(restoreFailure)))
            end
        end,
        owned = function() return owned ~= nil end,
        -- Armed, but the game is paused or showing its cursor, so no frame has moved yet.
        waitingForGame = function() return flight ~= nil and flight.waitingForGame() end,
        snapshot = function()
            if not flight then return "flight=inactive" end
            local state = flight.snapshot()
            return string.format("frames=%d allowed=%d keys=%d vertical=%d moves=%d clamped=%d", state.frames,
                state.allowed, state.keyFrames, state.verticalFrames, state.moves, state.clampedFrames)
        end,
        verify = verifyActive,
        inspect = function()
            assert(not failed, "Prior No Clip failure requires restarting and reloading")
            if owned then verifyActive(); return end
            local record = context()
            assert(record.movement.MovementMode == 1 and record.movement.CustomMovementMode == 0
                and record.player:GetActorEnableCollision() == true, "Stand on normal ground before enabling No Clip")
            verify(record)
        end,
        reset = function() assert(owned == nil, "Cannot discard pending No Clip restoration") end,
    }
end
function M.Init(menu, helpers, flightModule)
    local id, pilot = "DWNoClip"
    local field
    local ready = false
    pilot = M.New(helpers, flightModule, function(message)
        field.enabled = pilot.owned()
        ready = false
        menu.Set(id, "enabled", pilot.owned())
        menu.SetLabel(id, "status", message)
        menu.Fail(message)
    end)
    field = { type = "checkbox", id = "enabled", label = "No Clip (OFF returns to start)", default = false, enabled = false,
            onChange = function(value)
                ExecuteInGameThread(function()
                    local ok, failure = pcall(function()
                        assert(not value or menu.Get("DWPersonalFly", "enabled") ~= true, "Turn Fly OFF before enabling No Clip")
                        pilot.set(value)
                    end)
                    field.enabled = ok or pilot.owned()
                    if not ok and not pilot.owned() then ready = false end
                    menu.Set(id, "enabled", pilot.owned())
                    menu.SetLabel(id, "status", ok and (pilot.owned()
                        and (pilot.waitingForGame()
                            and "ON: return to the game window - flight starts as soon as the game has focus. WASD flies relative to the camera; Space rises, Q descends."
                            or "ON: WASD flies relative to the camera; Space rises, Q descends. OFF returns to start.")
                        or "OFF: starting position, movement and collision restored.")
                        or ("No Clip failed: " .. tostring(failure)))
                    assert(ok, failure)
                end)
            end }
    -- Verify once the session is up so the switch is live before its first click. The
    -- inspect needs the player standing on normal ground, so an early tick may refuse; the
    -- runner retries on later ticks and the Verify button stays for a manual re-check.
    function M.SessionReady()
        pilot.inspect()
        ready = true
        field.enabled = true
        menu.SetLabel(id, "status", "Grounded movement and collision verified; No Clip is available.")
    end
    menu.Register({ id = id, title = "No Clip", tab = "Player", items = {
        field,
        { type = "label", id = "status", label = "OFF. Checking grounded movement and collision automatically. OFF returns to the starting position." },
    } })
    M.NeedsSessionReady = function() return not ready and not pilot.owned() end
    M.ResetSession = function() pilot.reset(); ready = false; field.enabled = false end
end
return M
