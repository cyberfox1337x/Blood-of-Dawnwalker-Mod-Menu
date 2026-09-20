local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("fall_drop_diagnostic")
local M = {}
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function address(object)
    assert(object and object:IsValid(), "Fall drop object unavailable")
    return tostring(object:GetAddress())
end
local function health(combat)
    local value = combat:GetHealthPercentage()
    assert(finite(value) and value > 0 and value <= 1.001, "Living health baseline required")
    return value
end
local function position(player)
    local value = player:K2_GetActorLocation()
    assert(finite(value.X) and finite(value.Y) and finite(value.Z), "Invalid fall drop position")
    return { X = value.X, Y = value.Y, Z = value.Z }
end
local function distance(a, b) return (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2 end

-- All entry points and scheduled callbacks must run on the game thread.
-- deps: GetPlayer(), allOff() ownership/paused/UI gate, schedule(ms,fn)->handle,
-- cancel(handle), now() monotonic seconds, onComplete(snapshot). schedule must be asynchronous.
-- start(height) performs one lift (200..600); cancel() restores; snapshot()
-- returns scalar evidence. A failed restoration retains owned() for retry.
function M.New(deps)
    for _, key in ipairs({"GetPlayer", "allOff", "schedule", "cancel", "now", "onComplete"}) do
        assert(type(deps[key]) == "function", "Missing fall drop dependency: " .. key)
    end
    local owned, handle, generation = nil, nil, 0
    local report = { phase = "idle", suppressionVerified = false, restored = false, samples = 0 }
    local function context()
        local player = deps.GetPlayer()
        address(player)
        local record = { player = player, world = player:GetWorld(), controller = player.Controller,
            combat = player.CombatComponent, movement = player:GetRebelCharacterMovement() }
        for _, key in ipairs({"player", "world", "controller", "combat", "movement"}) do record[key .. "Address"] = address(record[key]) end
        assert(address(record.controller.Pawn) == record.playerAddress
            and address(record.movement:GetOwner()) == record.playerAddress
            and address(player.CharacterMovement) == record.movementAddress, "Fall drop ownership differs")
        return record
    end
    local function verify(record)
        local current = context()
        for _, key in ipairs({"player", "world", "controller", "combat", "movement"}) do
            assert(address(record[key]) == current[key .. "Address"] and current[key .. "Address"] == record[key .. "Address"], "Fall drop session changed; recovery retained")
        end
    end
    local function snapshot()
        local copy = {}; for key, value in pairs(report) do copy[key] = value end
        copy.recoveryPending = owned ~= nil
        return copy
    end
    local function restore()
        generation = generation + 1
        if handle then deps.cancel(handle); handle = nil end
        if not owned then return end
        local record = owned
        verify(record)
        assert(record.combat:IsAlive(), "Player died; restore the backed-up save instead of resurrecting")
        assert(record.player:K2_TeleportTo(record.position, record.rotation) == true, "Fall drop return teleport refused")
        assert(distance(position(record.player), record.position) <= 100, "Fall drop return position differs")
        record.combat:SetHealthPercent(record.health)
        assert(math.abs(health(record.combat)-record.health) <= 0.001, "Fall drop health restoration differs")
        assert(record.player:GetActorEnableCollision() == record.collision, "Collision changed during fall drop")
        verify(record)
        report.restored = true; owned = nil
    end
    local function finish(message)
        local restored, cause = pcall(restore)
        report.phase = restored and "complete" or "recovery-pending"
        report.error = message or (not restored and tostring(cause) or nil)
        if not restored then report.cleanupError = tostring(cause) end
        deps.onComplete(snapshot())
    end
    local function sample(token)
        if token ~= generation or not owned then return end
        handle = nil
        local ok, cause = pcall(function()
            verify(owned)
            assert(deps.allOff() == true, "Fall drop gate changed")
            assert(owned.combat:IsAlive(), "Player died during fall drop")
            report.samples = report.samples + 1
            local mode = owned.movement.MovementMode
            if mode == 3 then report.airborne = true end
            report.lastZ = position(owned.player).Z
            report.healthAfter = health(owned.combat)
            report.healthDelta = report.healthAfter - owned.health
            if report.airborne and mode == 1 then report.landed = true; finish(); return end
            if report.samples >= 40 or deps.now() >= owned.deadline then finish("No verified falling-to-walking transition within four seconds"); return end
            handle = deps.schedule(100, function() sample(token) end)
        end)
        if not ok then finish(tostring(cause)) end
    end
    local function start(height)
        assert(not owned, "Fall drop active or recovery pending")
        assert(finite(height) and height >= 200 and height <= 600, "Fall drop height must be 200..600 units")
        assert(deps.allOff() == true, "All conflicting controls must be OFF")
        local record = context()
        assert(record.combat:IsAlive() and record.movement.MovementMode == 1 and record.movement.CustomMovementMode == 0
            and record.player:GetActorEnableCollision() == true, "Grounded living player with normal collision required")
        record.position, record.health, record.collision = position(record.player), health(record.combat), true
        local rotation = record.player:K2_GetActorRotation()
        assert(finite(rotation.pitch) and finite(rotation.Yaw) and finite(rotation.Roll), "Invalid fall drop rotation")
        record.rotation = { pitch = rotation.pitch, Yaw = rotation.Yaw, Roll = rotation.Roll }
        verify(record)
        report = { phase = "sampling", suppressionVerified = false, restored = false, samples = 0,
            airborne = false, landed = false, height = height, healthBefore = record.health, baselineZ = record.position.Z }
        local now = deps.now(); assert(finite(now), "Fall drop monotonic clock unavailable")
        record.deadline = now + 4
        owned = record; generation = generation + 1
        local token = generation
        local ok, cause = pcall(function()
            local destination = { X = record.position.X, Y = record.position.Y, Z = record.position.Z + height }
            assert(record.player:K2_TeleportTo(destination, record.rotation) == true, "Fall drop lift refused")
            assert(distance(position(record.player), destination) <= 100, "Fall drop lift readback differs")
            handle = deps.schedule(100, function() sample(token) end)
        end)
        if not ok then finish(tostring(cause)) end
    end
    return { start = start, cancel = function() finish("Cancelled") end, snapshot = snapshot,
        owned = function() return owned ~= nil end }
end
return M
