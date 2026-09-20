local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("speed_private_profile_pilot")
local M = {}
local CLASS = "/Script/RebelLocomotion.RebelCharacterMovementProfile"
local FIELDS = { "RootSpeedScale", "MinSpeed", "MaxSpeed", "GravityScale", "MaxStepHeight", "MinAcceleration", "MaxAcceleration", "GroundFriction", "BrakingDeceleration" }
local function number(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Invalid movement profile scalar")
    return value
end
local function close(a, b) return math.abs(a - b) <= math.max(.01, math.abs(b) * .001) end
local function address(object)
    assert(object and object:IsValid(), "Movement profile object unavailable")
    return object:GetAddress()
end
local function length(array)
    local ok, count = pcall(function() return array:GetArrayNum() end)
    if not ok then count = #array end
    assert(type(count) == "number" and count >= 0 and count <= 16 and count % 1 == 0, "Movement profile stack too large")
    return count
end
local function stack(movement)
    local result, array = {}, movement.MovementProfileStack
    for index = 1, length(array) do
        local row = array[index]
        local ok, raw = pcall(function() return row:get() end)
        if ok then row = raw end
        local handle = number(row.MovementProfileHandle)
        assert(handle % 1 == 0 and result[handle] == nil, "Movement profile handle invalid")
        result[handle] = address(row.MovementProfile)
    end
    return result
end
local function snapshot(profile)
    local result = { priority = number(profile.Priority) }
    for _, key in ipairs(FIELDS) do result[key] = number(profile.MovementConfig[key]) end
    return result
end
local function sameConfig(profile, expected)
    local actual = snapshot(profile)
    for key, value in pairs(expected) do assert(close(actual[key], value), "Shared movement profile changed") end
end
-- Read-only description of why this movement state cannot accept a private profile.
-- Nil means it can. Used to hold a request until the player is grounded again instead
-- of failing it while airborne, flying or in wolf form.
local function blocker(player, movement)
    if player:IsInWolfForm() then return "the wolf form is active" end
    if movement.MovementMode ~= 1 then return "movement is airborne, flying or otherwise not normal walking" end
end
function M.New(helpers)
    local owned, ready, clone = nil, false, nil
    local function context(requireGrounded)
        assert(IsInGameThread() == true, "Speed pilot requires game thread")
        local player = helpers.GetPlayer()
        local id = address(player)
        local world, controller, movement = player:GetWorld(), player.Controller, player:GetRebelCharacterMovement()
        local worldId, controllerId, movementId = address(world), address(controller), address(movement)
        assert(address(controller.Pawn) == id and address(movement:GetOwner()) == id
            and address(player.CharacterMovement) == address(movement), "Speed movement ownership differs")
        if requireGrounded then
            assert(blocker(player, movement) == nil, "Speed pilot requires normal grounded movement")
        end
        return { player = player, movement = movement, identity = table.concat({id, worldId, controllerId, movementId}, ":") }
    end
    -- Read-only pre-flight answering whether normal grounded movement is available
    -- right now. Nothing is pushed, popped or written, so a caller can wait for the
    -- landing instead of starting an operation that must be undone immediately.
    local function applicable()
        local ok, player, movement = pcall(function()
            assert(IsInGameThread() == true, "Speed pilot requires game thread")
            local current = helpers.GetPlayer()
            return current, current:GetRebelCharacterMovement()
        end)
        if not ok or not player or not player:IsValid() or not movement or not movement:IsValid() then
            return false, "the player movement session is unavailable"
        end
        local reason = blocker(player, movement)
        return reason == nil, reason
    end
    local function live(record)
        local ctx = context()
        assert(ctx.identity == record.identity, "Speed session changed; recovery retained")
        sameConfig(record.original, record.baseline)
        local currentStack = stack(ctx.movement)
        for handle, profile in pairs(record.stack) do assert(currentStack[handle] == profile, "Original movement stack changed") end
        for handle, profile in pairs(currentStack) do
            assert(record.stack[handle] == profile or (handle == record.handle and profile == record.cloneId), "Another movement profile intervened")
        end
        return ctx, currentStack
    end
    local function restore(deferReadback)
        if not owned then return end
        local record, ctx = owned, live(owned)
        local currentStack = stack(ctx.movement)
        if record.handle ~= nil and currentStack[record.handle] then
            assert(currentStack[record.handle] == record.cloneId, "Owned speed handle replaced")
            assert(ctx.movement:PopMovementProfile(record.handle) == true, "Speed profile pop refused")
            record.popped = true
        elseif not record.popped and ctx.movement:GetCurrentMovementProfile():GetAddress() == record.cloneId then
            error("Speed profile applied without a recoverable handle")
        end
        if deferReadback then return end
        local final = stack(ctx.movement)
        for handle, profile in pairs(record.stack) do assert(final[handle] == profile, "Baseline stack restoration failed") end
        for handle in pairs(final) do assert(record.stack[handle], "Extra movement profile remains") end
        assert(address(ctx.movement:GetCurrentMovementProfile()) == record.originalId, "Original movement profile not restored")
        -- Airborne/form-specific speed can legitimately differ from the original
        -- grounded sample. Exact profile, stack and config restoration still
        -- proves our override is removed without forcing a movement-mode change.
        if ctx.movement.MovementMode == 1 and not ctx.player:IsInWolfForm() then
            assert(close(number(ctx.movement:GetMaxSpeed()), record.effective), "Original effective movement speed not restored")
        end
        sameConfig(record.original, record.baseline)
        owned = nil
    end
    local function verify()
        if not owned then return end
        local ctx, currentStack = live(owned)
        assert(currentStack[owned.handle] == owned.cloneId and address(ctx.movement:GetCurrentMovementProfile()) == owned.cloneId,
            "Owned speed profile is not active: current=" .. tostring(address(ctx.movement:GetCurrentMovementProfile()))
                .. ";private=" .. tostring(owned.cloneId) .. ";handle=" .. tostring(owned.handle)
                .. ";stack_binding=" .. tostring(currentStack[owned.handle]) .. ";source_priority=" .. tostring(owned.baseline.priority))
        assert(close(number(ctx.movement:GetMaxSpeed()), owned.effective * owned.factor), "Effective movement speed did not follow profile")
    end
    local function inspect()
        ready = false
        if owned then verify(); ready = true; return end
        local ctx = context(true)
        local profile = ctx.movement:GetCurrentMovementProfile()
        assert(profile:IsA(CLASS), "Unexpected movement profile class")
        local values = snapshot(profile)
        assert(values.priority >= 0 and values.priority < 255 and values.priority % 1 == 0
            and values.MaxSpeed > 0 and values.MaxSpeed <= 2000 and values.RootSpeedScale > 0,
            "Movement profile outside pilot limits")
        assert(close(number(ctx.movement:GetMaxSpeed()), values.MaxSpeed), "Another speed modifier is active")
        stack(ctx.movement)
        ready = true
    end
    local function apply(factor, deferReadback)
        assert(type(factor) == "number" and factor >= 1 and factor <= 3 and factor % .5 == 0, "Speed factor must be 1 to 3 in half steps")
        if factor == 1 then restore(); return end
        assert(ready, "Read the speed profile before enabling")
        if owned then
            if owned.factor == factor then verify(); return end
            restore()
        end
        inspect()
        local ctx = context(true)
        local original = ctx.movement:GetCurrentMovementProfile()
        local baseline = snapshot(original)
        -- Pinned Types.lua defines RF_Transient as 0x40. Template copies the
        -- complete native config, including curves; no shared asset is edited.
        clone = StaticConstructObject(original:GetClass(), ctx.movement, FName("None"), 0x40, 0, false, false, original)
        assert(address(clone) ~= address(original) and clone:IsA(CLASS)
            and address(clone:GetOuter()) == address(ctx.movement), "Private profile construction failed")
        sameConfig(clone, baseline)
        clone.Priority = baseline.priority + 1
        clone.MovementConfig.MaxSpeed = baseline.MaxSpeed * factor
        clone.MovementConfig.RootSpeedScale = baseline.RootSpeedScale * factor
        assert(close(clone.MovementConfig.MaxSpeed, baseline.MaxSpeed * factor)
            and close(clone.MovementConfig.RootSpeedScale, baseline.RootSpeedScale * factor), "Private profile field write refused")
        sameConfig(original, baseline)
        owned = { identity = ctx.identity, original = original, originalId = address(original), baseline = baseline,
            cloneId = address(clone), stack = stack(ctx.movement), effective = number(ctx.movement:GetMaxSpeed()), factor = factor }
        local handle = ctx.movement:PushMovementProfile(clone)
        owned.handle = handle
        assert(type(handle) == "number" and handle >= 0 and handle % 1 == 0 and owned.stack[handle] == nil, "Private profile handle rejected")
        if not deferReadback then verify() end
    end
    return {
        applicable = applicable, inspect = inspect, verify = verify,
        begin = function(factor)
            local ok, cause = pcall(apply, factor, true)
            if not ok then
                ready = false
                local restored, failure = pcall(restore)
                error(tostring(cause) .. (restored and "; baseline restored" or "; recovery retained: " .. tostring(failure)))
            end
        end,
        beginRestore = function() restore(true) end,
        set = function(factor)
            local ok, cause = pcall(apply, factor)
            if not ok then
                ready = false
                local restored, failure = pcall(restore)
                error(tostring(cause) .. (restored and "; baseline restored" or "; recovery retained: " .. tostring(failure)))
            end
        end,
        owned = function() return owned ~= nil end,
        reset = function() restore(); ready = false; clone = nil end,
    }
end
return M
