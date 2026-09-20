local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("no_clip_flight_input")
local M = {}
local function finite(number)
    return type(number) == "number" and number == number and math.abs(number) < math.huge
end

function M.Direction(pitch, yaw, forward, right, vertical)
    assert(finite(pitch) and finite(yaw), "Invalid flight camera rotation")
    local p, y = math.rad(pitch), math.rad(yaw)
    local x = math.cos(p) * math.cos(y) * forward - math.sin(y) * right
    local z = math.sin(p) * forward + vertical
    local lateral = math.cos(p) * math.sin(y) * forward + math.cos(y) * right
    local length = math.sqrt(x*x + lateral*lateral + z*z)
    if length < 0.000001 then return nil end
    return { X = x/length, Y = lateral/length, Z = z/length }
end

-- All callbacks run on the game thread. subscribe must return an unsubscribe
-- closure for one real input/frame callback; a bridge polling loop is not valid.
-- makeKey supplies the exact verified FKey ABI. No guessed Lua struct is built.
function M.New(deps)
    for _, name in ipairs({"context", "validate", "allowed", "subscribe", "makeKey", "onFailure", "deltaSeconds"}) do
        assert(type(deps[name]) == "function", "Missing flight dependency: " .. name)
    end
    local owned
    local telemetry = { frames = 0, allowed = 0, moves = 0, keyFrames = 0, verticalFrames = 0, clampedFrames = 0 }
    -- True while the game is paused or showing its cursor, which is the normal state at
    -- the moment the desktop menu sends the command: the user has to leave the game to
    -- press the switch. The frame loop below already skips those frames, so flight is
    -- armed now and starts moving as soon as the game has focus again.
    local waitingForGame = false
    local function increment(key) telemetry[key] = math.min(telemetry[key] + 1, 2147483647) end
    local function stop()
        if not owned then return end
        local record = owned
        record.active = false
        if record.unsubscribe then record.unsubscribe(); record.unsubscribe = nil end
        -- Identity failure keeps recovery ownership; never touch a new pawn.
        deps.validate(record.context)
        if record.suppressionOwned then
            record.context.controller:SetIgnoreMoveInput(false)
            record.suppressionOwned = false
        end
        assert(record.context.controller:IsMoveInputIgnored() == false,
            "Flight input suppression did not restore; another owner may be active")
        owned = nil
    end
    local function frame()
        if not owned or not owned.active then return end
        increment("frames")
        local ok, cause = pcall(function()
            local record = owned
            deps.validate(record.context)
            if deps.allowed(record.context) ~= true then return end
            waitingForGame = false
            increment("allowed")
            local controller, player = record.context.controller, record.context.player
            assert(controller:IsMoveInputIgnored() == true, "Flight input suppression ownership changed")
            local function down(name) return controller:IsInputKeyDown(record.keys[name]) and 1 or 0 end
            local rotation = controller:GetControlRotation()
            local forward, right, vertical = down("W")-down("S"), down("D")-down("A"), down("SpaceBar")-down("Q")
            if vertical ~= 0 then increment("verticalFrames") end
            local direction = M.Direction(rotation.pitch, rotation.Yaw, forward, right, vertical)
            if direction then
                increment("keyFrames")
                local delta = deps.deltaSeconds(record.context)
                assert(finite(delta) and delta >= 0, "Invalid world delta seconds")
                if delta > 0.05 then increment("clampedFrames") end
                delta = math.min(delta, 0.05)
                if delta > 0 then
                    -- Exact reflected ABI: FVector, bool, FHitResult& out, bool.
                    -- Direct offset avoids custom locomotion discarding input.
                    local distance = 600 * delta
                    player:K2_AddActorWorldOffset({ X = direction.X * distance, Y = direction.Y * distance,
                        Z = direction.Z * distance }, false, {}, true)
                    increment("moves")
                end
            end
        end)
        if not ok then
            local restored, restoreCause = pcall(stop)
            deps.onFailure(tostring(cause) .. (restored and "; input suppression restored" or "; input recovery pending: " .. tostring(restoreCause)))
        end
    end
    local function start()
        assert(not owned, "Flight input is already active or recovery is pending")
        local context = deps.context()
        deps.validate(context)
        -- Not an error: enabling from the desktop menu necessarily means the game is
        -- not focused. Refusing here made the switch fail every time it was used the
        -- only way it can be used.
        waitingForGame = deps.allowed(context) ~= true
        assert(context.controller:IsMoveInputIgnored() == false, "Existing movement suppression prevents flight")
        local keys = {}
        for _, name in ipairs({"W", "A", "S", "D", "SpaceBar", "Q"}) do
            keys[name] = assert(deps.makeKey(name), "Flight key unavailable: " .. name)
            assert(type(context.controller:IsInputKeyDown(keys[name])) == "boolean", "Flight key ABI was not verified")
        end
        owned = { context = context, keys = keys, active = false, suppressionOwned = true }
        local ok, cause = pcall(function()
            context.controller:SetIgnoreMoveInput(true)
            assert(context.controller:IsMoveInputIgnored() == true, "Flight movement suppression refused")
            owned.unsubscribe = deps.subscribe(frame)
            assert(type(owned.unsubscribe) == "function", "Flight frame subscription has no cleanup closure")
            owned.active = true
        end)
        if not ok then
            local restored, restoreCause = pcall(stop)
            error(tostring(cause) .. (restored and "; input suppression restored" or "; input recovery pending: " .. tostring(restoreCause)))
        end
    end
    return { start = start, stop = stop, owned = function() return owned ~= nil end,
        waitingForGame = function() return owned ~= nil and waitingForGame end,
        snapshot = function() local result = {}; for key, value in pairs(telemetry) do result[key] = value end; return result end }
end
return M
