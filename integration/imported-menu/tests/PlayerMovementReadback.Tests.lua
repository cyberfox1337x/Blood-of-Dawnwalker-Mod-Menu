local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("player_movement_readback_tests")
local module = assert(loadfile(assert(arg[1])))()
local function fixture()
    local function object(address)
        return { IsValid = function() return true end, GetAddress = function() return address end }
    end
    local player, controller, world, movement, attributes = object(1), object(2), object(3), object(4), object(5)
    player.Controller, controller.Pawn, player.CharacterMovement, player.MovementAttributeSet = controller, player, movement, attributes
    player.GetWorld = function() return world end
    player.GetRebelCharacterMovement = function() return movement end
    player.GetActorEnableCollision = function() return true end
    movement.GetOwner, attributes.GetOuter = function() return player end, function() return player end
    movement.GetClass = function() return { GetFullName = function() return "Class /Script/Dawnwalker.DWPlayerMovementComponent" end } end
    movement.MovementMode, movement.CustomMovementMode, movement.MaxWalkSpeed = 1, 0, 400
    movement.MaxFlySpeed, movement.JumpZVelocity = 600, 420
    movement.GetMaxSpeed, movement.GetMaxJumpHeight = function() return 400 end, function() return 90 end
    for _, name in ipairs({"WalkSpeed", "RunSpeed", "SprintSpeed", "MaxSpeedModifier", "JumpVelocity"}) do
        attributes[name] = { BaseValue = 1, CurrentValue = 1 }
    end
    return { GetPlayer = function() return player end }, player, movement, attributes
end
local count = 0
local function test(name, callback)
    assert(pcall(callback), name); count = count + 1; print("PASS " .. name)
end
test("bounded read-only values and unavailable optional fall fields", function()
    local helpers = fixture()
    local result = module.Read(helpers)
    assert(result:find("read_only=true", 1, true) and result:find("max_walk_speed=400", 1, true))
    assert(result:find("JumpVelocity=1/1", 1, true) and result:find("fall_damage_effect=UNAVAILABLE", 1, true))
end)
test("possession mismatch rejected", function()
    local helpers, player = fixture(); player.Controller.Pawn = { IsValid = function() return true end, GetAddress = function() return 99 end }
    assert(not pcall(module.Read, helpers))
end)
test("movement resolver mismatch rejected", function()
    local helpers, player = fixture(); player.CharacterMovement = player
    assert(not pcall(module.Read, helpers))
end)
test("foreign attribute owner rejected", function()
    local helpers, _, _, attributes = fixture(); attributes.GetOuter = function() return attributes end
    assert(not pcall(module.Read, helpers))
end)
test("invalid numeric field is unavailable without losing other evidence", function()
    local helpers, _, movement = fixture(); movement.JumpZVelocity = 0/0
    local result = module.Read(helpers)
    assert(result:find("jump_z_velocity=UNAVAILABLE", 1, true) and result:find("max_walk_speed=400", 1, true))
end)
test("identity drift rejected", function()
    local helpers, player, movement = fixture()
    movement.GetMaxSpeed = function() player.GetAddress = function() return 99 end; return 400 end
    assert(not pcall(module.Read, helpers))
end)
print(count .. " movement readback tests passed")
