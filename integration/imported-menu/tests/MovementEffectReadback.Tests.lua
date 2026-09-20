local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("movement_effect_readback_tests")
local M = assert(loadfile(assert(arg[1])))()
local function object(id)
    return { IsValid = function() return true end, IsA = function() return true end,
        GetAddress = function() return id end, GetFullName = function() return "object:" .. id end }
end
local function name(text) return { ToString = function() return text end } end
local function fixture()
    local player, world, movement, profile = object(1), object(2), object(3), object(4)
    player.GetWorld = function() return world end
    player.GetRebelCharacterMovement = function() return movement end
    player.CharacterMovement = movement
    movement.GetOwner = function() return player end
    movement.GetMaxSpeed = function() return 425 end
    movement.GetCurrentMovementProfile = function() return profile end
    profile.Priority = 1
    profile.MovementConfig = { RootSpeedScale = 1, MaxSpeed = 600, GravityScale = 1, bUseGravityScale = false }
    local class, cdo = object(5), object(6)
    class.GetCDO = function() return cdo end
    cdo.GetClass = function() return class end
    local scalable = { Value = 0, Curve = { RowName = name("None") }, RegistryType = { Name = name("None") } }
    cdo.DurationPolicy, cdo.StackingType, cdo.StackLimitCount, cdo.Period = 1, 0, 0, scalable
    cdo.Executions, cdo.GrantedAbilities, cdo.GEComponents = {}, {}, {}
    cdo.Modifiers = {{ Attribute = { AttributeName = "JumpVelocity", AttributeOwner = object(7) }, ModifierOp = 1,
        ModifierMagnitude = { MagnitudeCalculationType = 0, ScalableFloatMagnitude = scalable } }}
    local lookups = 0
    StaticFindObject = function(path)
        lookups = lookups + 1
        if not path:find("JumpIncrease", 1, true) then return nil end
        return path:find("Default__", 1, true) and cdo or class
    end
    return { GetPlayer = function() return player end }, cdo, movement, function() return lookups end
end
local count = 0
local function test(label, callback) callback(); count = count + 1; print("PASS " .. label) end
test("reads exact effects and profile without game writes", function()
    local helpers, _, _, calls = fixture()
    local result = M.Read(helpers)
    assert(result:find("attribute=JumpVelocity", 1, true) and result:find("effective_max_speed=425", 1, true))
    assert(result:find("GE_WolfBoost_SpedBoost_Lvl3;loaded=0", 1, true) and calls() == 5)
    assert(result:find("GE_FallDamage;loaded=0", 1, true))
end)
test("caps modifier arrays before iterating", function()
    local helpers, cdo = fixture()
    for index = 2, 17 do cdo.Modifiers[index] = cdo.Modifiers[1] end
    assert(M.Read(helpers):find("Movement array exceeds 16 entries", 1, true))
end)
test("rejects component ownership mismatch before effect discovery", function()
    local helpers, _, movement, calls = fixture(); movement.GetOwner = function() return object(99) end
    assert(M.Read(helpers):find("Movement ownership differs", 1, true) and calls() == 0)
end)
test("reports invalid effect CDO independently", function()
    local helpers, cdo = fixture(); cdo.GetClass = function() return object(99) end
    local result = M.Read(helpers)
    assert(result:find("Movement effect identity differs", 1, true) and result:find("SpedBoost_Lvl4;loaded=0", 1, true))
end)
test("reads granted tags without confusing missing metadata with empty tags", function()
    local helpers, cdo = fixture()
    local component, class = object(8), object(9)
    class.GetFullName = function() return "Class /Script/GameplayAbilities.TargetTagsGameplayEffectComponent" end
    component.GetClass = function() return class end
    component.InheritableGrantedTagsContainer = { CombinedTags = { GameplayTags = { { TagName = name("Movement.Test") } } } }
    cdo.GEComponents = { component }
    assert(M.Read(helpers):find("granted_tags=Movement.Test", 1, true))
    component.InheritableGrantedTagsContainer = nil
    assert(M.Read(helpers):find("component_details=UNAVAILABLE", 1, true))
end)
test("reads custom magnitude class and coefficients without invoking calculation", function()
    local helpers, cdo = fixture()
    local class, calculation = object(12), object(13)
    class.GetCDO = function() return calculation end
    calculation.GetClass = function() return class end
    calculation.RelevantAttributesToCapture = {}
    calculation.bAllowNonNetAuthorityDependencyRegistration = false
    calculation.CalculateBaseMagnitude = function() error("Must not calculate or mutate") end
    local magnitude = cdo.Modifiers[1].ModifierMagnitude
    magnitude.MagnitudeCalculationType = 2
    magnitude.CustomMagnitude = { CalculationClassMagnitude = class, Coefficient = cdo.Period,
        PreMultiplyAdditiveValue = cdo.Period, PostMultiplyAdditiveValue = cdo.Period,
        FinalLookupCurve = { RowName = name("None") } }
    local result = M.Read(helpers)
    assert(result:find("custom_modifier=1;class=object:12", 1, true) and result:find("coefficient:value=0", 1, true))
    calculation.GetClass = function() return object(99) end
    assert(M.Read(helpers):find("Custom calculation CDO identity differs", 1, true))
end)
print(count .. " movement effect readback tests passed")
