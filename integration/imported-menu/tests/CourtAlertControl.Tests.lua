local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("court_alert_control_tests")

-- Covers Scripts/CourtAlertControl.lua.
--
-- The single most important property: the control must reach Infamy through
-- DropAlertLevelByInt (which negates its input and routes through the game's own
-- change pipeline) and must NEVER call the milestone setter SetAlertLevel, which
-- soft-locks the game by raising the Infamy Level without proclaiming its Edict.

local path = assert(arg[1], "Supply CourtAlertControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function alwaysValid() return true end

local function menuDouble()
    local menu = { labels = {}, values = {}, sections = {}, plainLabels = {} }
    function menu.Register(section)
        menu.sections[section.id] = section
        for _, item in ipairs(section.items) do
            if item.type == "label" and not item.id then
                menu.plainLabels[#menu.plainLabels + 1] = item.label
            end
        end
    end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set(_, itemId, value) menu.values[itemId] = value end
    function menu.SetOptions() end
    function menu.Get(_, itemId) return menu.values[itemId] end
    function menu.item(itemId)
        for _, item in ipairs(menu.sections.DWCourtAlert.items) do
            if item.id == itemId then return item end
        end
        return nil
    end
    function menu.click(itemId)
        local item = menu.item(itemId)
        assert(item and item.onClick, "no such control: " .. itemId)
        return item.onClick()
    end
    return menu
end

local function fixture(overrides)
    overrides = overrides or {}
    local world = {
        points = overrides.points or 0,
        cap = overrides.cap or 900,
        step = overrides.step or 100,
        drops = {},
        milestoneCalls = 0,
        obeys = overrides.obeys ~= false,
        inCombat = overrides.inCombat or false,
        alive = overrides.alive ~= false,
        writeThrows = overrides.writeThrows or false,
    }
    local court = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x6000 end,
        GetFullName = function() return "CourtSubsystem /Game/World.Court" end,
        IsA = function(_, class) return class == "/Script/DogwoodQuest.CourtSubsystem" end,
        GetAlertLevel = function() return world.points end,
        GetSingleAlertThresholdBarValue = function() return world.step end,
        DropAlertLevelByInt = function(_, amount)
            world.drops[#world.drops + 1] = amount
            if world.writeThrows then error("native drop failed") end
            -- Drop negates its input: a negative amount adds points.
            if world.obeys then world.points = math.max(0, math.min(world.cap, world.points - amount)) end
        end,
        -- Present but forbidden; calling it must fail the suite.
        SetAlertLevel = function() world.milestoneCalls = world.milestoneCalls + 1 end,
    }
    local combatComponent = { IsValid = alwaysValid, IsAlive = function() return world.alive end }
    local player = { IsValid = alwaysValid, GetAddress = function() return 0x1 end, CombatComponent = combatComponent }
    local combatSystem = {
        IsValid = alwaysValid,
        GetFullName = function() return "CombatSubsystem /Game/World.Combat" end,
        GetIsInCombat = function() return world.inCombat end,
    }
    local settings = { IsValid = alwaysValid, MaxAlertLevel = world.cap }
    local environment = setmetatable({
        FindFirstOf = function(name)
            if name == "CourtSubsystem" then return court end
            if name == "CombatSubsystem" then return combatSystem end
            return nil
        end,
        StaticFindObject = function(objectPath)
            if objectPath:find("CourtSettings", 1, true) then return settings end
            return nil
        end,
        print = function() end,
    }, { __index = _G })
    local module = assert(loadfile(path, "t", environment))()
    local menu = menuDouble()
    module.Init(menu, { GetPlayer = function() return player end })
    return menu, world, module
end

test("reading reports points, level, cap and step from the game", function()
    local menu = fixture({ points = 300 })
    menu.click("refresh")
    assert(menu.labels.status:find("300 points (level 3)", 1, true), menu.labels.status)
    assert(menu.labels.status:find("Range 0-900", 1, true), menu.labels.status)
    assert(menu.labels.status:find("100 points per level", 1, true), menu.labels.status)
end)

test("a part-way value is described without rounding to a level", function()
    local menu = fixture({ points = 250 })
    menu.click("refresh")
    assert(menu.labels.status:find("250 points (part way through level 2)", 1, true), menu.labels.status)
end)

test("raising Infamy uses a negative drop and never the milestone setter", function()
    local menu, world = fixture({ points = 0 })
    menu.click("refresh")
    menu.values.points = 250
    menu.click("apply")
    assert(#world.drops == 1, "expected exactly one DropAlertLevelByInt call")
    assert(world.drops[1] == -250, "raising must pass a negative drop, got " .. tostring(world.drops[1]))
    assert(world.milestoneCalls == 0, "SetAlertLevel must never be called")
    assert(world.points == 250)
    assert(menu.labels.status:find("Verified: Infamy is now 250 points", 1, true), menu.labels.status)
end)

test("lowering Infamy uses a positive drop", function()
    local menu, world = fixture({ points = 400 })
    menu.click("refresh")
    menu.values.points = 100
    menu.click("apply")
    assert(world.drops[1] == 300, "lowering must pass a positive drop, got " .. tostring(world.drops[1]))
    assert(world.milestoneCalls == 0)
    assert(world.points == 100)
end)

test("restore returns the session's original points", function()
    local menu, world = fixture({ points = 100 })
    menu.click("refresh")
    menu.values.points = 500
    menu.click("apply")
    menu.click("restore")
    assert(world.points == 100, "restore must put the original points back")
    assert(world.milestoneCalls == 0)
    assert(menu.labels.status:find("Restored the original Infamy of 100 points", 1, true), menu.labels.status)
    assert(menu.values.owned == false)
end)

test("a readback mismatch latches the panel and demands a reload", function()
    local menu, world = fixture({ points = 0, obeys = false })
    menu.click("refresh")
    menu.values.points = 200
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok, "a mismatch must not pass")
    assert(menu.labels.status:find("STOP", 1, true), menu.labels.status)
    local retried = pcall(function() menu.click("apply") end)
    assert(not retried, "a latched panel must refuse further writes")
    assert(#world.drops == 1, "no second write may be issued after an unverified change")
end)

test("a throwing native write also latches the panel", function()
    local menu, world = fixture({ points = 0, writeThrows = true })
    menu.click("refresh")
    menu.values.points = 100
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok)
    assert(menu.labels.status:find("STOP", 1, true), menu.labels.status)
    local retried = pcall(function() menu.click("apply") end)
    assert(not retried, "a latched panel must refuse further writes")
end)

test("the latch survives a session reset", function()
    local menu, _, module = fixture({ points = 0, obeys = false })
    menu.click("refresh")
    menu.values.points = 200
    pcall(function() menu.click("apply") end)
    module.ResetSession()
    local retried = pcall(function() menu.click("apply") end)
    assert(not retried, "an unverified write must stay blocked across a session change")
end)

test("combat blocks the write before anything is issued", function()
    local menu, world = fixture({ points = 0, inCombat = true })
    menu.click("refresh")
    menu.values.points = 100
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok)
    assert(#world.drops == 0, "no Infamy write may happen during combat")
end)

test("a dead player blocks the panel entirely", function()
    local menu, world = fixture({ points = 0, alive = false })
    local ok = pcall(function() menu.click("refresh") end)
    assert(not ok)
    assert(#world.drops == 0)
end)

test("a value above the game's cap is rejected before writing", function()
    local menu, world = fixture({ points = 0 })
    menu.click("refresh")
    menu.values.points = 5000
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok)
    assert(#world.drops == 0)
end)

test("an unexpected Infamy configuration refuses rather than writing", function()
    local menu, world = fixture({ points = 0, cap = 500, step = 50 })
    local ok = pcall(function() menu.click("refresh") end)
    assert(not ok, "a changed configuration must block the panel")
    assert(#world.drops == 0)
end)

test("selecting the current value writes nothing", function()
    local menu, world = fixture({ points = 200 })
    menu.click("refresh")
    menu.values.points = 200
    menu.click("apply")
    assert(#world.drops == 0)
    assert(menu.labels.status:find("already 200 points", 1, true), menu.labels.status)
end)

test("the write control confirms and warns about Edicts", function()
    local menu = fixture()
    local apply = menu.item("apply")
    assert(apply.confirm, "the write must confirm")
    assert(apply.confirm.message:find("Edict", 1, true), "the confirmation must mention the Edict")
    assert(apply.enabled ~= false, "the write must be enabled now that it uses the safe pipeline")
end)

print(count .. " Court alert tests passed")
