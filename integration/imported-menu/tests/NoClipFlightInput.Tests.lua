local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("no_clip_flight_input_tests")
local M = assert(loadfile(assert(arg[1])))()
local function fixture()
    local state = { ignored = false, allowed = true, keys = {}, calls = 0, releases = 0 }
    local controller = {
        IsMoveInputIgnored = function() return state.ignored end,
        SetIgnoreMoveInput = function(_, value) state.ignored = value; if not value then state.releases = state.releases + 1 end end,
        IsInputKeyDown = function(_, key) return state.keys[key] == true end,
        GetControlRotation = function() return { pitch = 0, Yaw = 0 } end,
    }
    local context = { controller = controller, player = { K2_AddActorWorldOffset = function(_, direction, sweep, hit, teleport)
        assert(sweep == false and type(hit) == "table" and teleport == true); state.calls = state.calls + 1; state.direction = direction
    end } }
    local pilot = M.New({ context = function() return context end, validate = function() assert(not state.changed, "identity changed") end,
        deltaSeconds = function() return state.delta or 1/600 end, allowed = function() return state.allowed end, makeKey = function(name) return name end,
        subscribe = function(callback) state.frame = callback; return function() state.unsubscribed = true end end,
        onFailure = function(message) state.failure = message end })
    return pilot, state
end
local count = 0
local function test(name, callback) callback(); count = count + 1; print("PASS " .. name) end
test("normalizes camera-relative diagonal movement", function()
    local direction = M.Direction(0, 90, 1, 1, 1)
    assert(math.abs(direction.X + 1/math.sqrt(3)) < 0.00001)
    assert(math.abs(direction.Y - 1/math.sqrt(3)) < 0.00001)
    assert(M.Direction(0, 0, 0, 0, 0) == nil)
end)
test("arms while the game is unfocused instead of refusing, then flies once it is back", function()
    -- The switch lives in a separate desktop window, so pressing it means the game is
    -- paused or showing its cursor. Refusing here made No Clip fail every single time
    -- it was used the only way it can be used.
    local pilot, state = fixture()
    state.allowed = false
    pilot.start()
    assert(pilot.owned(), "flight must arm even while the game is not accepting input")
    assert(pilot.waitingForGame(), "the armed-but-waiting state must be reportable")
    state.keys.W = true; state.frame()
    assert(state.calls == 0, "no movement may happen while the game is paused")
    state.allowed = true; state.frame()
    assert(state.calls == 1, "movement must begin as soon as the game has focus")
    assert(not pilot.waitingForGame(), "waiting must clear once a frame has been accepted")
    pilot.stop()
    assert(not pilot.waitingForGame(), "a stopped pilot is not waiting")
end)
test("suppresses ordinary movement and feeds forced input once per callback", function()
    local pilot, state = fixture(); pilot.start(); state.keys.D = true; state.frame()
    assert(state.ignored and state.calls == 1 and state.direction.Y == 1)
    pilot.stop(); state.frame(); assert(state.calls == 1 and state.releases == 1 and state.unsubscribed)
    pilot.stop(); assert(state.releases == 1)
end)
test("supports vertical input without held WASD", function()
    local pilot, state = fixture(); pilot.start(); state.keys.SpaceBar = true; state.frame()
    assert(state.direction.Z == 1); state.keys.SpaceBar = false; state.keys.Q = true; state.frame()
    assert(state.direction.Z == -1); pilot.stop()
end)
test("pause or UI gating suspends input and resumes without duplicate ownership", function()
    local pilot, state = fixture(); pilot.start(); state.allowed = false; state.frame()
    assert(state.calls == 0 and not state.failure and state.ignored and pilot.owned())
    state.allowed = true; state.keys.W = true; state.frame()
    assert(state.calls == 1); pilot.stop(); assert(not state.ignored)
end)
test("rejects an existing suppression owner", function()
    local pilot, state = fixture(); state.ignored = true
    assert(not pcall(pilot.start) and state.releases == 0)
end)
test("identity change stops input and retains recovery without touching new pawn", function()
    local pilot, state = fixture(); pilot.start(); state.changed = true; state.frame()
    assert(state.calls == 0 and state.releases == 0 and state.unsubscribed and pilot.owned())
end)
test("telemetry distinguishes gating and vertical keys while bounding long frames", function()
    local pilot, state = fixture(); pilot.start(); state.allowed = false; state.frame()
    state.allowed = true; state.keys.SpaceBar = true; state.delta = 1; state.frame()
    local snapshot = pilot.snapshot()
    assert(snapshot.frames == 2 and snapshot.allowed == 1 and snapshot.verticalFrames == 1
        and snapshot.moves == 1 and snapshot.clampedFrames == 1 and state.direction.Z == 30)
    snapshot.moves = 999; assert(pilot.snapshot().moves == 1)
    pilot.stop(); state.frame(); assert(pilot.snapshot().frames == 2)
end)
test("zero delta sends no spatial movement", function()
    local pilot, state = fixture(); pilot.start(); state.delta = 0; state.keys.W = true; state.frame()
    assert(state.calls == 0); pilot.stop()
end)
print(count .. " flight input tests passed")

