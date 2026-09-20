local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_attack_speed_controller_tests")
local Controller = dofile(arg[1] or "integration/uue4ss/feature-candidates/AttackSpeedController.lua")
local passed = 0
local function test(name, run)
    local ok, failure = pcall(run)
    if not ok then error(name .. ": " .. tostring(failure), 0) end
    passed = passed + 1
    print("PASS " .. name)
end
local function rejects(run, fragment)
    local ok, message = pcall(run)
    assert(not ok and tostring(message):find(fragment, 1, true), "Expected failure containing " .. fragment .. ", got " .. tostring(message))
end
local function equal(actual, expected)
    assert(math.abs(actual - expected) < 0.000001, tostring(actual) .. " ~= " .. tostring(expected))
end
local function fixture()
    local f = { context = "boot/player/world/config", writes = 0, reads = 0, resolves = 0, modes = {}, ownership = true }
    for index = 1, 5 do
        f.modes[index] = { attack = 0.8 + index * 0.1, strong_attack = 1.1 + index * 0.1, fingerprint = "unchanged-" .. index }
    end
    f.resolve = function()
        f.resolves = f.resolves + 1
        local context = { identity = f.context, player_modes_verified = f.ownership, npc_isolation_verified = true, modes = {} }
        for index, data in ipairs(f.modes) do
            local function write(field, value)
                f.writes = f.writes + 1
                if f.before_write then f.before_write(index, field, value) end
                data[field] = value
                if f.after_write then f.after_write(index, field, value) end
            end
            context.modes[index] = {
                enum_value = index, identity = data.identity or "mode-" .. index,
                read = function()
                    f.reads = f.reads + 1
                    if f.before_read then f.before_read(index) end
                    return { attack = data.attack, strong_attack = data.strong_attack, unrelated_fingerprint = data.fingerprint }
                end,
                write_attack = function(value) write("attack", value) end,
                write_strong_attack = function(value) write("strong_attack", value) end,
            }
        end
        if f.change_context then f.change_context(context) end
        return context
    end
    f.controller = Controller.new(f.resolve)
    return f
end

test("absolute multiplier changes preserve per-mode originals and restore", function()
    local f = fixture()
    assert(not f.controller.read().active)
    local result = f.controller.apply(1.5)
    assert(result.active and result.consistent and result.applied_multiplier == 1.5)
    equal(f.modes[1].attack, 0.9 * 1.5)
    result = f.controller.apply(2)
    equal(f.modes[1].attack, 1.8)
    equal(f.modes[5].strong_attack, 3.2)
    result = f.controller.restore()
    assert(result.restored and not result.active and not f.controller.has_pending_restore())
    equal(f.modes[1].attack, 0.9)
    equal(f.modes[5].strong_attack, 1.6)
    local writes = f.writes
    assert(f.controller.restore().restored and f.writes == writes)
end)

test("reject invalid inputs before resolution or writes", function()
    local f = fixture()
    for _, input in ipairs({ -1, 0, 0.49, 2.01, math.huge, -math.huge, 0/0, "1", true }) do
        rejects(function() f.controller.apply(input) end, "between 0.5 and 2.0")
    end
    assert(f.writes == 0 and f.resolves == 0)
end)

test("both multiplier endpoints are supported", function()
    local f = fixture()
    f.controller.apply(0.5)
    equal(f.modes[1].attack, 0.45)
    f.controller.apply(2)
    equal(f.modes[1].attack, 1.8)
    f.controller.restore()
end)

test("incomplete ownership, aliases and unexpected map keys refuse writes", function()
    local f = fixture()
    f.ownership = false
    rejects(function() f.controller.apply(1.5) end, "ownership and NPC isolation")
    f.ownership = true
    f.modes[2].identity = "mode-1"
    rejects(function() f.controller.apply(1.5) end, "Aliased")
    f.modes[2].identity = nil
    f.change_context = function(context) context.modes.extra = context.modes[1] end
    rejects(function() f.controller.apply(1.5) end, "Unexpected player mode key")
    assert(f.writes == 0)
end)

test("partial write failure rolls all touched modes back", function()
    local f = fixture()
    local failed = false
    f.before_write = function(index, field)
        if index == 3 and field == "strong_attack" and not failed then failed = true; error("injected setter failure") end
    end
    rejects(function() f.controller.apply(1.5) end, "previous rates restored")
    for index, data in ipairs(f.modes) do
        equal(data.attack, 0.8 + index * 0.1)
        equal(data.strong_attack, 1.1 + index * 0.1)
    end
    assert(not f.controller.read().restore_pending)
    f.controller.restore()
end)

test("failed inverse retains journal and retries both fields", function()
    local f = fixture()
    local fail_apply, fail_inverse = true, true
    f.after_write = function(index, field, value)
        if fail_apply and index == 2 and field == "strong_attack" and value > 1.5 then
            fail_apply = false
            error("setter threw after mutation")
        end
    end
    f.before_write = function(index, field, value)
        if fail_inverse and index == 2 and field == "attack" and value < 1.1 then error("inverse temporarily unavailable") end
    end
    rejects(function() f.controller.apply(1.5) end, "restoration pending")
    equal(f.modes[2].strong_attack, 1.3) -- restored despite attack inverse failure
    equal(f.modes[2].attack, 1.5)
    assert(f.controller.read().restore_pending and f.controller.read().applied_multiplier == nil)
    rejects(function() f.controller.apply(2) end, "requires restoration")
    fail_inverse = false
    assert(f.controller.restore().restored)
    equal(f.modes[2].attack, 1)
    assert(not f.controller.has_pending_restore())
end)

test("recovery returns through last successful multiplier before original", function()
    local f = fixture()
    f.controller.apply(1.25)
    local fail_apply = true
    local fail_inverse = true
    f.after_write = function(index, field, value)
        if fail_apply and index == 1 and field == "strong_attack" and value > 2 then
            fail_apply = false; error("late failure")
        end
    end
    f.before_write = function(index, field, value)
        if fail_inverse and index == 1 and field == "attack" and value < 1.5 then error("inverse failure") end
    end
    rejects(function() f.controller.apply(2) end, "restoration pending")
    fail_inverse = false
    assert(f.controller.restore().restored)
    equal(f.modes[1].attack, 0.9)
end)

test("outside attack or unrelated changes refuse overwrite and report inconsistency", function()
    local f = fixture()
    f.controller.apply(1.5)
    f.modes[3].attack = 1.8
    local writes = f.writes
    assert(not f.controller.read().consistent and f.controller.read().applied_multiplier == nil)
    rejects(function() f.controller.restore() end, "changed outside")
    assert(f.writes == writes)
    f.modes[3].attack = 1.1 * 1.5
    f.modes[3].fingerprint = "outside-edit"
    rejects(function() f.controller.restore() end, "changed outside")
    assert(f.writes == writes)
end)

test("pending recovery refuses third-party value without any new writes", function()
    local f = fixture()
    f.before_write = function(index, field, value)
        if index == 1 and field == "strong_attack" then error("persistent failure") end
        if index == 1 and field == "attack" and value < 1 then error("inverse failure") end
    end
    rejects(function() f.controller.apply(1.5) end, "restoration pending")
    f.modes[1].attack = 1.77
    local writes = f.writes
    rejects(function() f.controller.restore() end, "outside the pending transaction")
    assert(f.writes == writes and f.controller.has_pending_restore())
end)

test("player/world or mode transition retains old snapshot and rejects mutation", function()
    local f = fixture()
    f.controller.apply(1.5)
    local writes = f.writes
    f.context = "new-world"
    rejects(function() f.controller.restore() end, "Player/world/config changed")
    assert(f.writes == writes and f.controller.has_pending_restore())
    f.context = "boot/player/world/config"
    f.modes[1].identity = "replacement-mode"
    rejects(function() f.controller.restore() end, "Concrete player mode changed")
    assert(f.writes == writes)
end)

test("all target rates validate before first write", function()
    local f = fixture()
    f.modes[5].attack = 1.7e308
    rejects(function() f.controller.apply(2) end, "overflow")
    assert(f.writes == 0)
end)

test("silent setter no-op is detected and rolled back", function()
    local f = fixture()
    local mutate = f.change_context
    f.change_context = function(context)
        if mutate then mutate(context) end
        context.modes[2].write_strong_attack = function() end
    end
    rejects(function() f.controller.apply(1.5) end, "previous rates restored")
    equal(f.modes[1].attack, 0.9)
    equal(f.modes[2].attack, 1)
end)

print(string.format("%d attack controller test groups passed", passed))
