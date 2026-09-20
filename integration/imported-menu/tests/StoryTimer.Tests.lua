local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("story_timer_restore_tests")
local path = assert(arg[1], "Supply StoryTimerControl.lua")
local count = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end
local function object(cost, progression)
    local state = { TimeCost = cost, InteractionTimeProgressionType = progression, valid = true }
    local proxy = setmetatable({}, {
        __index = function(_, key)
            if key == "IsValid" then return function() return state.valid end end
            if key == "GetFullName" then return function() return "QuestConditionInteractionType /Game/Test" end end
            return state[key]
        end,
        __newindex = function(_, key, value)
            if state.reject and state.reject(key, value) then return end
            state[key] = value
        end,
    })
    return proxy, state
end
local function fixture(objects)
    local values, labels, items, confirmation = {}, {}, {}, nil
    local menu = {
        Register = function(section) for _, item in ipairs(section.items) do if item.id then items[item.id] = item end end end,
        Set = function(_, key, value) values[key] = value end,
        SetLabel = function(_, key, value) labels[key] = value end,
        Confirm = function(value) confirmation = value end,
    }
    local env = setmetatable({ ExecuteInGameThread = function(fn) fn() end,
        FindAllOf = function() return objects end, FindFirstOf = function() return nil end,
        print = function() end }, { __index = _G })
    local module = assert(loadfile(path, "t", env))()
    module.Init(menu, {})
    return {
        toggle = function(value) return items.notimecost.onChange(value) end,
        confirm = function() return assert(confirmation).onConfirm() end,
        cancel = function() return assert(confirmation).onCancel() end,
        module = module, values = values, labels = labels,
    }
end
test("confirmation cancellation makes no writes", function()
    local o, s = object(1, 3); local f = fixture({o})
    f.toggle(true); assert(s.TimeCost == 1); f.cancel()
    assert(s.TimeCost == 1 and f.values.notimecost == false)
end)
test("ON and OFF restore both original properties", function()
    local o, s = object(1, 3); local f = fixture({o})
    f.toggle(true); f.confirm(); assert(s.TimeCost == 0 and s.InteractionTimeProgressionType == 0)
    f.toggle(false); assert(s.TimeCost == 1 and s.InteractionTimeProgressionType == 3)
end)
test("silent restore refusal fails and retains cleanup ownership", function()
    local o, s = object(1, 3); local f = fixture({o})
    f.toggle(true); f.confirm()
    s.reject = function(key, value) return key == "TimeCost" and value == 1 end
    assert(not pcall(f.toggle, false), "must not report successful OFF")
    assert(f.values.notimecost == true, "close must still attempt owned cleanup")
    s.reject = nil; f.toggle(false)
    assert(s.TimeCost == 1 and s.InteractionTimeProgressionType == 3)
    assert(not pcall(f.toggle, true), "failed restore must latch activation until restart")
end)
test("restore preserves independent changes", function()
    local o, s = object(1, 3); local f = fixture({o})
    f.toggle(true); f.confirm(); s.TimeCost = 2; f.toggle(false)
    assert(s.TimeCost == 2 and s.InteractionTimeProgressionType == 3)
end)
test("partial apply rollback is verified and failure is reported", function()
    local o, s = object(1, 3); local f = fixture({o})
    s.reject = function(key, value) return key == "InteractionTimeProgressionType" and value == 0 end
    f.toggle(true); assert(not pcall(f.confirm))
    assert(s.TimeCost == 1 and s.InteractionTimeProgressionType == 3 and f.values.notimecost == false)
end)
test("failed rollback retains records and cannot claim nothing changed", function()
    local o, s = object(1, 3); local f = fixture({o})
    s.reject = function(key, value) return (key == "InteractionTimeProgressionType" and value == 0) or (key == "TimeCost" and value == 1) end
    f.toggle(true); local ok, err = pcall(f.confirm)
    assert(not ok and not tostring(err):find("nothing was left changed", 1, true))
    assert(f.values.notimecost == true)
    s.reject = nil; f.toggle(false); assert(s.TimeCost == 1)
end)
test("session reset invalidates pending confirmation", function()
    local o, s = object(1, 3); local f = fixture({o})
    f.toggle(true); f.module.ResetSession(); assert(not pcall(f.confirm)); assert(s.TimeCost == 1)
end)
print(string.format("%d Story Timer tests passed", count))
