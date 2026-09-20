local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("speed_private_profile_tests")
local M = assert(loadfile(assert(arg[1])))()
IsInGameThread = function() return true end
FName = function(value) return value end
local function object(id) return { IsValid = function() return true end, IsA = function() return true end, GetAddress = function() return id end } end
local function fixture()
    local player, world, controller, movement, profile, class = object(1), object(2), object(3), object(4), object(5), object(6)
    profile.Priority = 0
    profile.GetClass = function() return class end
    profile.MovementConfig = { RootSpeedScale = 1, MaxSpeed = 425, MinSpeed = 0, GravityScale = 2, MaxStepHeight = 45,
        MinAcceleration = 0, MaxAcceleration = 2048, GroundFriction = 8, BrakingDeceleration = 2048 }
    player.Controller, player.CharacterMovement, controller.Pawn = controller, movement, player
    player.GetWorld = function() return world end
    player.GetRebelCharacterMovement = function() return movement end
    player.IsInWolfForm = function() return false end
    movement.GetOwner = function() return player end
    movement.MovementMode, movement.MovementProfileStack = 1, {}
    local active, failPop, ignoreSpeed, created, pushed, popped = profile, false, false, 0, 0, 0
    movement.GetCurrentMovementProfile = function() return active end
    movement.GetMaxSpeed = function() return ignoreSpeed and 425 or active.MovementConfig.MaxSpeed end
    movement.PushMovementProfile = function(_, copy)
        pushed = pushed + 1; movement.MovementProfileStack = {{ MovementProfile = copy, MovementProfileHandle = 40 }}
        active = copy; return 40
    end
    movement.PopMovementProfile = function(_, handle)
        assert(handle == 40); popped = popped + 1
        if failPop then return false end
        movement.MovementProfileStack = {}; active = profile; return true
    end
    StaticConstructObject = function(receivedClass, outer, name, flags, internal, copyTransients, archetype, template)
        assert(receivedClass == class and outer == movement and name == "None" and flags == 0x40 and internal == 0
            and copyTransients == false and archetype == false and template == profile)
        created = created + 1; local copy = object(20 + created); copy.Priority = template.Priority
        copy.MovementConfig = {}; for key, value in pairs(template.MovementConfig) do copy.MovementConfig[key] = value end
        copy.GetOuter = function() return movement end
        return copy
    end
    return { pilot = M.New({ GetPlayer = function() return player end }), profile = profile, movement = movement, player = player,
        failPop = function(value) failPop = value end, ignoreSpeed = function() ignoreSpeed = true end,
        counts = function() return created, pushed, popped end }
end
local count = 0
local function test(label, callback) callback(); count = count + 1; print("PASS " .. label) end
test("private profile applies restores and preserves shared config", function()
    local f = fixture(); f.pilot.inspect()
    for index = 1, 3 do
        f.pilot.set(2); f.pilot.verify(); assert(f.movement:GetMaxSpeed() == 850 and f.profile.MovementConfig.MaxSpeed == 425)
        assert(f.profile.MovementConfig.RootSpeedScale == 1 and f.profile.Priority == 0)
        f.pilot.set(1); assert(f.movement:GetMaxSpeed() == 425 and not f.pilot.owned())
    end
end)
test("read is required and invalid factor does not create profile", function()
    local f = fixture(); assert(not pcall(f.pilot.set, 2)); assert(f.counts() == 0)
    f.pilot.inspect(); assert(not pcall(f.pilot.set, 4)); assert(f.counts() == 0)
end)
test("ignored native profile speed fails and restores", function()
    local f = fixture(); f.pilot.inspect(); f.ignoreSpeed()
    assert(not pcall(f.pilot.set, 2)); assert(not f.pilot.owned() and #f.movement.MovementProfileStack == 0)
end)
test("pop failure retains handle and permits retry", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(2); f.failPop(true)
    assert(not pcall(f.pilot.set, 1)); assert(f.pilot.owned())
    f.failPop(false); f.pilot.set(1); assert(not f.pilot.owned())
end)
test("foreign stack entry blocks restoration without deleting it", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(2)
    f.movement.MovementProfileStack[2] = { MovementProfile = object(99), MovementProfileHandle = 50 }
    assert(not pcall(f.pilot.set, 1)); local _, _, popped = f.counts(); assert(popped == 0 and f.pilot.owned())
end)
test("session identity drift blocks pop", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(2); f.movement.GetAddress = function() return 100 end
    assert(not pcall(f.pilot.set, 1)); local _, _, popped = f.counts(); assert(popped == 0 and f.pilot.owned())
end)
test("reset restores and requires renewed inspection", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(2); f.pilot.reset()
    assert(not f.pilot.owned()); assert(not pcall(f.pilot.set, 2))
end)
test("deferred profile selection can settle before verification and cleanup", function()
    local f = fixture(); f.pilot.inspect()
    local actual = f.movement.GetCurrentMovementProfile
    local pending = true
    f.movement.GetCurrentMovementProfile = function() return pending and f.profile or actual() end
    f.pilot.begin(1.5); assert(f.pilot.owned() and not pcall(f.pilot.verify))
    pending = false; f.pilot.verify()
    local private = actual()
    f.movement.GetCurrentMovementProfile = function() return pending and private or actual() end
    pending = true; f.pilot.beginRestore(); assert(not pcall(f.pilot.reset) and f.pilot.owned())
    pending = false; f.pilot.reset(); assert(not f.pilot.owned())
end)
test("airborne activation is rejected but exact owned cleanup remains available", function()
    local f = fixture(); f.movement.MovementMode = 3
    assert(not pcall(f.pilot.inspect)); assert(f.counts() == 0)
    f.movement.MovementMode = 1; f.pilot.inspect(); f.pilot.set(1.5)
    f.movement.MovementMode = 3
    f.movement.GetMaxSpeed = function() return 300 end
    f.pilot.beginRestore(); f.pilot.reset()
    assert(not f.pilot.owned() and #f.movement.MovementProfileStack == 0)
    assert(f.movement:GetCurrentMovementProfile() == f.profile and f.profile.MovementConfig.MaxSpeed == 425)
end)
test("applicable reports airborne and wolf states without touching the profile stack", function()
    local f = fixture()
    assert(f.pilot.applicable() == true)
    f.movement.MovementMode = 3
    local airborne, airborneReason = f.pilot.applicable()
    assert(airborne == false and airborneReason:find("not normal walking", 1, true), tostring(airborneReason))
    f.movement.MovementMode = 1
    f.player.IsInWolfForm = function() return true end
    local wolf, wolfReason = f.pilot.applicable()
    assert(wolf == false and wolfReason == "the wolf form is active", tostring(wolfReason))
    f.player.IsInWolfForm = function() return false end
    assert(f.pilot.applicable() == true)
    local created, pushed, popped = f.counts()
    assert(created == 0 and pushed == 0 and popped == 0 and #f.movement.MovementProfileStack == 0)
    assert(not f.pilot.owned())
end)
print(count .. " private speed profile tests passed")
