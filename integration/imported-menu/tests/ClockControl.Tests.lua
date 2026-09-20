local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("clock_control_tests")

-- Covers Scripts/ClockControl.lua. SetTime returns nothing, so the clock reading
-- decides the outcome, and the write must be refused while the world is in combat
-- or mid day/night transition.

local path = assert(arg[1], "Supply ClockControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function alwaysValid() return true end

local function menuDouble()
    local menu = { labels = {}, values = {}, sections = {} }
    function menu.Register(section) menu.sections[section.id] = section end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set(_, itemId, value) menu.values[itemId] = value end
    function menu.SetOptions() end
    function menu.Get(_, itemId) return menu.values[itemId] end
    function menu.click(itemId)
        for _, item in ipairs(menu.sections.DWClock.items) do
            if item.id == itemId and item.onClick then return item.onClick() end
        end
        error("no such control: " .. itemId)
    end
    return menu
end

local function fixture(overrides)
    overrides = overrides or {}
    local world = {
        hours = overrides.hours or 10.5,
        writes = {},
        obeys = overrides.obeys ~= false,
        snaps = overrides.snaps == true,
        inCombat = overrides.inCombat or false,
        transitioning = overrides.transitioning or false,
    }
    local time = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x7000 end,
        GetFullName = function() return "TimeSystemImpl /Game/World.Time" end,
        IsA = function(_, class) return class == "/Script/DogwoodSystem.TimeSystemImpl" end,
        GetCurrentDayTimeAsFloat = function() return world.hours end,
        GetCurrentDay = function() return 3 end,
        IsPhaseTransitionQueuedOrInProgress = function() return world.transitioning end,
        SetTime = function(_, hour, minute, second, absolute)
            world.writes[#world.writes + 1] = { hour = hour, minute = minute, second = second, absolute = absolute }
            if world.obeys then
                world.hours = hour + minute / 60 + second / 3600
                -- The live game keeps its clock on 1.5-hour segments anchored at 08:00.
                if world.snaps then world.hours = (8 + math.floor((world.hours - 8) / 1.5 + 0.5) * 1.5) % 24 end
            end
        end,
    }
    local combat = {
        IsValid = alwaysValid,
        GetFullName = function() return "CombatSubsystem /Game/World.Combat" end,
        GetIsInCombat = function() return world.inCombat end,
    }
    local player = { IsValid = alwaysValid, GetAddress = function() return 0x1 end }
    local environment = setmetatable({
        FindFirstOf = function(name)
            if name == "CombatSubsystem" then return combat end
            return nil
        end,
        print = function() end,
    }, { __index = _G })
    local module = assert(loadfile(path, "t", environment))()
    local menu = menuDouble()
    module.Init(menu, {
        GetPlayer = function() return player end,
        GetGameStateBase = function() return { IsValid = alwaysValid, TimeSystem = time } end,
    })
    return menu, world, module
end

test("reading reports the clock and records the original time", function()
    local menu = fixture({ hours = 10.5 })
    menu.click("refresh")
    assert(menu.labels.status:find("10:30", 1, true), menu.labels.status)
    assert(menu.labels.status:find("day 3", 1, true), menu.labels.status)
end)

test("setting a time is verified by the clock reading back", function()
    local menu, world = fixture({ hours = 10.5 })
    menu.click("refresh")
    menu.values.hour, menu.values.minute = 21, 15
    menu.click("apply")
    assert(#world.writes == 1, "expected exactly one SetTime call")
    local write = world.writes[1]
    assert(write.hour == 21 and write.minute == 15, "hour/minute must be passed as whole values")
    assert(write.absolute == true, "bAbsoluteTime must be passed explicitly")
    assert(menu.labels.status:find("Verified: the clock is now 21:15", 1, true), menu.labels.status)
end)

test("restore returns the original time", function()
    local menu, world = fixture({ hours = 8.0 })
    menu.click("refresh")
    menu.values.hour, menu.values.minute = 23, 0
    menu.click("apply")
    menu.click("restore")
    assert(math.abs(world.hours - 8.0) < 0.02, "restore must put the original clock back")
    assert(menu.labels.status:find("Restored the clock to 08:00", 1, true), menu.labels.status)
end)

test("combat blocks the write before anything is sent", function()
    local menu, world = fixture({ hours = 10, inCombat = true })
    menu.click("refresh")
    menu.values.hour, menu.values.minute = 12, 0
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok, "writing the clock during combat must fail")
    assert(#world.writes == 0, "no clock write may happen during combat")
end)

test("an in-progress phase transition blocks the write", function()
    local menu, world = fixture({ hours = 10, transitioning = true })
    menu.click("refresh")
    menu.values.hour, menu.values.minute = 12, 0
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok, "writing during a transition must fail")
    assert(#world.writes == 0)
end)

test("a refused or reinterpreted write is reported, not claimed as success", function()
    local menu, world = fixture({ hours = 10, obeys = false })
    menu.click("refresh")
    menu.values.hour, menu.values.minute = 22, 0
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok)
    assert(#world.writes == 1)
    assert(menu.labels.status:find("refused or interpreted differently", 1, true), menu.labels.status)
    assert(not menu.labels.status:find("Verified", 1, true))
end)

test("a write the game snaps to its segment grid is verified and the snap is explained", function()
    local menu, world = fixture({ hours = 8, snaps = true })
    menu.click("refresh")
    menu.values.hour, menu.values.minute = 12, 0
    menu.click("apply")
    assert(#world.writes == 1 and math.abs(world.hours - 12.5) < 0.001)
    assert(menu.labels.status:find("Verified: the clock is now 12:30.", 1, true), menu.labels.status)
    assert(menu.labels.status:find("12:00 became 12:30", 1, true), menu.labels.status)
    menu.click("restore")
    assert(math.abs(world.hours - 8) < 0.001 and menu.labels.status:find("Restored the clock to 08:00.", 1, true), menu.labels.status)
end)

test("an invalid hour is rejected before writing", function()
    local menu, world = fixture({ hours = 10 })
    menu.click("refresh")
    menu.values.hour, menu.values.minute = 26, 0
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok)
    assert(#world.writes == 0)
end)

test("setting the clock carries a confirmation that mentions the deadline", function()
    local menu = fixture()
    for _, item in ipairs(menu.sections.DWClock.items) do
        if item.id == "apply" then
            assert(item.confirm, "apply must confirm")
            assert(item.confirm.message:find("deadline", 1, true), "the confirmation must warn about the campaign deadline")
        end
    end
end)

print(count .. " Clock tests passed")
