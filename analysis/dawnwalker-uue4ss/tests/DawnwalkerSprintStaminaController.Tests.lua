local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_sprint_stamina_controller_tests")
local path = assert(arg[1], "Pass the controller module path")
package.path = path:match("^(.*[/\\\\])") .. "?.lua;" .. package.path

-- Colon-style accessors, exactly like real UEHelpers property objects: the
-- controller calls attribute:get() and attribute:set(value), so the implicit
-- self must land in the first parameter of each accessor.
local function attribute(initial)
    local value = initial
    local writes_blocked = false
    return {
        get = function() return value end,
        set = function(_self, next)
            if writes_blocked then return false end
            value = next; return true
        end,
        value = function() return value end,
        block_writes = function() writes_blocked = true end,
    }
end

local function object(address, name, expected_class)
    local value = { address = address, name = name, expected_class = expected_class, valid = true, seen_writes = {} }
    function value:IsValid() return self.valid end
    function value:IsA(class) return class == self.expected_class or self.expected_class == nil end
    function value:GetAddress() return self.address end
    function value:GetFullName() return self.name end
    return value
end

local function fixture()
    local player = object(10, "Player World.Player", "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
    local attributes = object(11, "PlayerAttributeSet World.Player.CharacterAttributeSet", "/Script/DogwoodStats.PlayerAttributeSet")
    local char_dev = object(12, "CharDevAttributeSet World.Player.CharDevAttributeSet", nil)
    player.CharacterAttributeSet = attributes
    player.CharDevAttributeSet = char_dev
    attributes.SprintStaminaCostMultiplier = attribute(1.0)
    attributes.DodgeStaminaCostMultiplier = attribute(0.5)
    char_dev.OmniblockStaminaCostMultiplier = attribute(0.25)
    local build_verified = true
    local controller = nil
    local deps = {
        verify_build = function()
            if not build_verified then error("Build verification failed; no mutation may run.", 0) end
        end,
        get_local_player = function() return player end,
    }
    controller = assert(loadfile(path))().create(deps)
    return { player = player, attributes = attributes, char_dev = char_dev, controller = controller,
        set_build_verified = function(value) build_verified = value end }
end

local failures = 0
local function test(name, action)
    local ok, message = pcall(action)
    if ok then print("PASS " .. name) else failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(message)) end
end

local function expect_equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
end

test("controller exposes the pinned build and target attribute", function()
    local env = fixture()
    expect_equal(env.controller.expected_build, "25129649", "build pin")
    expect_equal(env.controller.expected_executable, "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853", "exe pin")
    expect_equal(env.controller.target_attribute, "SprintStaminaCostMultiplier", "target")
end)

test("observe reads the player's multipliers without writing anything", function()
    local env = fixture()
    local result = env.controller.observe()
    expect_equal(result.ok, true, "ok")
    expect_equal(result.active, false, "active")
    expect_equal(result.sprint_stamina_cost_multiplier, 1.0, "sprint multiplier")
    expect_equal(result.dodge_stamina_cost_multiplier, 0.5, "dodge multiplier")
    expect_equal(result.omniblock_stamina_cost_multiplier, 0.25, "omniblock multiplier")
    expect_equal(env.attributes.SprintStaminaCostMultiplier.value(), 1.0, "sprint untouched by observe")
    expect_equal(env.attributes.DodgeStaminaCostMultiplier.value(), 0.5, "dodge untouched by observe")
end)

test("apply(true) writes exactly zero to the player's sprint multiplier and nothing else", function()
    local env = fixture()
    local result = env.controller.apply(true)
    expect_equal(result.ok, true, "ok")
    expect_equal(result.active, true, "active")
    expect_equal(result.applied, true, "applied")
    expect_equal(result.sprint_stamina_cost_multiplier, 0, "readback")
    expect_equal(env.attributes.SprintStaminaCostMultiplier.value(), 0, "sprint written")
    expect_equal(env.attributes.DodgeStaminaCostMultiplier.value(), 0.5, "dodge untouched")
    expect_equal(env.char_dev.OmniblockStaminaCostMultiplier.value(), 0.25, "omniblock untouched")
end)

test("apply(true) twice keeps the original snapshot instead of resnapshotting", function()
    local env = fixture()
  env.attributes.SprintStaminaCostMultiplier:set(0.75)
  env.controller.apply(true)
  env.attributes.SprintStaminaCostMultiplier:set(0.5)  -- drift while active
    env.controller.apply(true)
    expect_equal(env.controller.state().original, 0.75, "original snapshot preserved")
end)

test("apply(false) restores the captured original exactly and clears state", function()
    local env = fixture()
    env.controller.apply(true)
    local result = env.controller.apply(false)
    expect_equal(result.active, false, "inactive after off")
    expect_equal(env.attributes.SprintStaminaCostMultiplier.value(), 1.0, "original restored")
    expect_equal(env.controller.state().original, nil, "snapshot cleared")
end)

test("apply(false) with nothing active does not write", function()
    local env = fixture()
    local result = env.controller.apply(false)
    expect_equal(result.active, false, "inactive")
    expect_equal(env.attributes.SprintStaminaCostMultiplier.value(), 1.0, "unchanged")
end)

test("restore refuses when not active", function()
    local env = fixture()
    local ok, message = pcall(function() env.controller.restore() end)
    assert(ok == false and tostring(message):find("nothing to restore", 1, true) ~= nil, "restore must refuse when idle")
end)

test("restore returns the captured original and verifies the readback", function()
  local env = fixture()
  env.attributes.SprintStaminaCostMultiplier:set(0.6)
  env.controller.apply(true)
    local result = env.controller.restore()
    expect_equal(result.ok, true, "ok")
    expect_equal(result.restored_original, 0.6, "restored original")
    expect_equal(result.sprint_stamina_cost_multiplier, 0.6, "readback after restore")
    expect_equal(env.controller.state().active, false, "inactive after restore")
end)test("a refused restore write fails closed instead of reporting success", function()
    local env = fixture()
    env.attributes.SprintStaminaCostMultiplier:set(0.6)
    env.controller.apply(true)
    env.attributes.SprintStaminaCostMultiplier.block_writes()
    local ok, message = pcall(function() env.controller.restore() end)
    assert(ok == false, "restore must fail when the attribute refuses the write")
    assert(tostring(message):find("refused the write", 1, true) ~= nil, "failure names the refused write")
end)

test("apply refuses to run when build verification fails", function()
    local env = fixture()
    env.set_build_verified(false)
    local ok, message = pcall(function() env.controller.apply(true) end)
    assert(ok == false and tostring(message):find("Build verification failed", 1, true) ~= nil,
        "apply must refuse without build verification")
    expect_equal(env.attributes.SprintStaminaCostMultiplier.value(), 1.0, "nothing written")
end)

test("observe refuses to run when build verification fails", function()
    local env = fixture()
    env.set_build_verified(false)
    local ok, message = pcall(function() env.controller.observe() end)
    assert(ok == false and tostring(message):find("Build verification failed", 1, true) ~= nil,
        "observe must refuse without build verification")
end)

test("missing sprint attribute fails closed", function()
    local env = fixture()
    env.attributes.SprintStaminaCostMultiplier = nil
    local ok, message = pcall(function() env.controller.observe() end)
    assert(ok == false and tostring(message):find("unavailable", 1, true) ~= nil, "missing attribute must fail closed")
end)

test("class default players are refused", function()
    local env = fixture()
    env.player.name = "Default__Player"
    local ok, message = pcall(function() env.controller.observe() end)
    assert(ok == false and tostring(message):find("class default", 1, true) ~= nil, "class defaults must be refused")
end)

test("players of an unexpected class are refused", function()
    local env = fixture()
    env.player.expected_class = "/Script/Engine.Pawn"
    local ok, message = pcall(function() env.controller.observe() end)
    assert(ok == false and tostring(message):find("unexpected class", 1, true) ~= nil, "foreign class must be refused")
end)

test("every operation returns the player record so the pilot can pin identity", function()
    local env = fixture()
    local observed = env.controller.observe()
    expect_equal(observed.player.address, "10", "observe player address")
    local applied = env.controller.apply(true)
    expect_equal(applied.player.name, "Player World.Player", "apply player name")
    local restored = env.controller.restore()
    expect_equal(restored.player.address, "10", "restore player address")
end)

test("invalid apply values are rejected", function()
    local env = fixture()
    local ok, message = pcall(function() env.controller.apply("yes") end)
    assert(ok == false and tostring(message):find("boolean", 1, true) ~= nil, "non-boolean apply must be rejected")
end)

test("the controller accepts only its two required dependencies", function()
    local ok, message = pcall(function() return assert(loadfile(path))().create({}) end)
    assert(ok == false and tostring(message):find("dependencies", 1, true) ~= nil, "missing deps must fail at creation")
end)

print(string.format("%s%s", failures == 0 and "ALL " or (tostring(failures) .. " FAILED; "), "Sprint Stamina Controller"))
os.exit(failures == 0 and 0 or 1)