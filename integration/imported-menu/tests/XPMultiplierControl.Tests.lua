local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("xp_multiplier_control_tests")

-- Covers Scripts/XPMultiplierControl.lua.
--
-- The multiplier works by re-running the game's own AddQuestXP for a reward tier. The
-- hazard that matters is reentrancy: every extra grant re-enters the same post hook, so
-- without a guard one award becomes an unbounded grant. These tests drive the hook the
-- way UE4SS does, including re-entering it from inside the extra calls.

local module = assert(loadfile(assert(arg[1])))()

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function boxed(value) return { get = function() return value end } end

local function fixture()
    local world = { awards = {}, hooks = {}, unregistered = {}, log = {} }
    local subsystem
    subsystem = {
        IsValid = function() return true end,
        GetAddress = function() return world.address or 4242 end,
        GetCurrentXP = function() return world.xp or 0 end,
        AddQuestXP = function(_, reward)
            world.xp = (world.xp or 0) + 10
            world.awards[#world.awards + 1] = reward
            -- UE4SS calls the post hook for every invocation, including ours.
            local post = world.hooks["/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem:AddQuestXP"]
            if post then post(boxed(subsystem), boxed(10), boxed(reward)) end
            return 10
        end,
    }
    world.subsystem = subsystem
    local control = module.New({
        subsystem = function() return world.present == false and nil or subsystem end,
        register_hook = function(path, _pre, post) world.hooks[path] = post; return 1, 2 end,
        unregister_hook = function(path, pre, post)
            world.unregistered[#world.unregistered + 1] = { path = path, pre = pre, post = post }
            world.hooks[path] = nil
        end,
        log = function(line) world.log[#world.log + 1] = line end,
    })
    -- One award as the game would make it, from outside this module.
    function world.award(reward)
        subsystem:AddQuestXP(reward or 3)
    end
    return control, world
end

test("off by default and no hook is attached", function()
    local control, world = fixture()
    assert(control.factor() == 1 and not control.active())
    assert(next(world.hooks) == nil, "nothing may be hooked while the multiplier is off")
    world.award(3)
    assert(#world.awards == 1, "an award must pass through untouched")
end)

test("rejects a factor outside the supported whole-number range", function()
    local control = fixture()
    for _, bad in ipairs({ 0, 6, -1, 2.5, "2", true }) do
        assert(not pcall(control.set, bad), "accepted " .. tostring(bad))
    end
    assert(control.factor() == 1, "a rejected value must not change the factor")
end)

test("x2 grants each award exactly twice, and reentry does not compound", function()
    local control, world = fixture()
    control.set(2)
    assert(control.active())
    world.award(3)
    -- One from the game, one extra from us. Not three, not unbounded.
    assert(#world.awards == 2, "expected 2 awards, got " .. #world.awards)
    for _, reward in ipairs(world.awards) do assert(reward == 3, "the extra grant must use the same reward tier") end
end)

test("x5 grants five times for one award", function()
    local control, world = fixture()
    control.set(5)
    world.award(4)
    assert(#world.awards == 5, "expected 5 awards, got " .. #world.awards)
end)

test("several separate awards each multiply independently", function()
    local control, world = fixture()
    control.set(3)
    world.award(2); world.award(5)
    assert(#world.awards == 6, "expected 6 awards, got " .. #world.awards)
end)

test("returning to x1 detaches the hook and stops multiplying", function()
    local control, world = fixture()
    control.set(2)
    control.set(1)
    assert(not control.active() and control.factor() == 1)
    assert(#world.unregistered == 1, "the hook must be removed, not left attached")
    world.award(3)
    assert(#world.awards == 1, "no extra grant may happen once it is off")
end)

test("a reward of None is not repeated", function()
    local control, world = fixture()
    control.set(3)
    world.award(0)
    assert(#world.awards == 1, "None must not be amplified")
    assert(control.snapshot():find("skipped=1", 1, true), control.snapshot())
end)

test("an award on another subsystem is left alone", function()
    local control, world = fixture()
    control.set(2)
    world.address = 9999 -- the session's subsystem was replaced
    world.award(3)
    assert(#world.awards == 1, "a foreign receiver must not be amplified")
    assert(control.snapshot():find("foreign=1", 1, true), control.snapshot())
end)

test("a session reset detaches and returns to x1", function()
    local control, world = fixture()
    control.set(4)
    control.reset()
    assert(control.factor() == 1 and not control.active())
    assert(#world.unregistered == 1)
    world.award(3)
    assert(#world.awards == 1)
end)

test("telemetry counts the awards it amplified", function()
    local control, world = fixture()
    control.set(3)
    world.award(3)
    local snapshot = control.snapshot()
    assert(snapshot:find("factor=3", 1, true), snapshot)
    assert(snapshot:find("awards=1", 1, true), snapshot)
    assert(snapshot:find("extras=2", 1, true), snapshot)
end)

test("reports the live XP total so the multiplier can be checked against it", function()
    local control, world = fixture()
    assert(control.currentXP() == 0)
    control.set(2)
    world.award(3)
    -- One grant from the game plus one from us, at 10 XP each in this double.
    assert(control.currentXP() == 20, "expected 20, got " .. tostring(control.currentXP()))
end)

print(count .. " XP multiplier tests passed")
