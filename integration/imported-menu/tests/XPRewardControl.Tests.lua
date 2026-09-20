local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("xp_reward_control_tests")
local module = assert(loadfile(assert(arg[1])))()
local function object(id)
    return { IsValid = function() return true end, GetAddress = function() return id end, IsA = function() return true end }
end
local function fixture()
    local player, world, controller, subsystem = object(1), object(2), object(3), object(4)
    player.Controller, controller.Pawn = controller, player
    player.GetWorld = function() return world end
    local questStruct, combatStruct = object(10), object(11)
    local quest = {
        { name = "Small", QuestXPRewardType = 2, QuestXPRewardNormal = 50 },
        { name = "Large", QuestXPRewardType = 0, QuestXPRewardNormal = 100 },
        { name = "VeryLarge", QuestXPRewardType = 0, QuestXPRewardNormal = 1800 },
    }
    local combat = { { name = "Enemy", XP = 20 } }
    local writes, failName, cached = 0, nil, false
    local function dataTable(id, struct, source)
        local result = object(id)
        result.GetRowStruct = function() return struct end
        result.GetAllRows = function()
            local rows = {}
            for index, row in ipairs(source) do rows[index] = { Name = row.name } end
            return rows
        end
        result.FindRow = function(_, name)
            for index, row in ipairs(source) do
                if row.name == name then
                    return setmetatable({}, {
                        __index = function(_, key)
                            if key == "GetStructAddress" then return function() return id * 100 + index end end
                            return row[key]
                        end,
                        __newindex = function(_, key, value)
                            writes = writes + 1
                            if failName == name then error("injected row write failure") end
                            row[key] = value
                        end,
                    })
                end
            end
        end
        return setmetatable(result, { __len = function() return #source end })
    end
    subsystem.LoadedQuestXPRewardTable = dataTable(5, questStruct, quest)
    subsystem.LoadedCombatRewardsTable = dataTable(6, combatStruct, combat)
    subsystem.GetXPAmountByRewardType = function(_, rewardType)
        if rewardType == 2 then return cached and 50 or quest[1].QuestXPRewardNormal end
        return cached and 1800 or quest[3].QuestXPRewardNormal
    end
    local library = object(7)
    library.GetGameInstanceSubsystem = function() return subsystem end
    StaticFindObject = function(path)
        if path:find("Default__SubsystemBlueprintLibrary", 1, true) then return library end
        if path:find("XPQuestRewardTypeRow", 1, true) then return questStruct end
        if path:find("CombatReward", 1, true) then return combatStruct end
        return object(8)
    end
    local helpers = { GetPlayer = function() return player end }
    return { helpers = helpers, control = module.New(helpers), quest = quest, combat = combat, subsystem = subsystem,
        controller = controller, writes = function() return writes end,
        fail = function(name) failName = name end, cache = function() cached = true end }
end
local count = 0
local function test(name, callback) callback(); count = count + 1; print("PASS " .. name) end
test("explicit read is required before writes", function()
    local f = fixture(); assert(not pcall(f.control.set, 2)); assert(f.writes() == 0)
end)
test("scales all rows including duplicate enum values and restores", function()
    local f = fixture(); f.control.inspect(); assert(f.writes() == 0)
    for cycle = 1, 3 do
        f.control.set(2); assert(f.quest[2].QuestXPRewardNormal == 200 and f.quest[3].QuestXPRewardNormal == 3600)
        assert(f.combat[1].XP == 40 and f.control.owned())
        f.control.set(5); assert(f.quest[1].QuestXPRewardNormal == 250)
        f.control.set(1); assert(f.quest[1].QuestXPRewardNormal == 50 and f.combat[1].XP == 20 and not f.control.owned())
    end
end)
test("native getter caching rejects mutation and restores baseline", function()
    local f = fixture(); f.control.inspect(); f.cache()
    assert(not pcall(f.control.set, 2)); assert(not f.control.owned())
    assert(f.quest[3].QuestXPRewardNormal == 1800 and f.combat[1].XP == 20)
end)
test("partial write failure restores successfully written rows", function()
    local f = fixture(); f.control.inspect(); f.fail("Small")
    assert(not pcall(f.control.set, 2)); assert(not f.control.owned())
    assert(f.quest[2].QuestXPRewardNormal == 100 and f.combat[1].XP == 20)
end)
test("external edit prevents rollback overwrite and retains ownership", function()
    local f = fixture(); f.control.inspect(); f.control.set(2); f.quest[1].QuestXPRewardNormal = 99
    local before = f.writes(); assert(not pcall(f.control.restore))
    assert(f.control.owned() and f.writes() == before and f.quest[1].QuestXPRewardNormal == 99)
    f.quest[1].QuestXPRewardNormal = 100; f.control.restore(); assert(not f.control.owned())
end)
test("changed possession prevents any restore writes", function()
    local f = fixture(); f.control.inspect(); f.control.set(2); f.controller.Pawn = object(99)
    local before = f.writes(); assert(not pcall(f.control.reset)); assert(f.control.owned() and f.writes() == before)
end)
test("changed row names prevent any restore writes", function()
    local f = fixture(); f.control.inspect(); f.control.set(2); f.quest[1].name = "Different"
    local before = f.writes(); assert(not pcall(f.control.restore)); assert(f.control.owned() and f.writes() == before)
end)
test("invalid multipliers cause no initial writes", function()
    for _, value in ipairs({ 0, 6, 1.5, math.huge, "2" }) do
        local f = fixture(); f.control.inspect(); assert(not pcall(f.control.set, value)); assert(f.writes() == 0)
    end
end)
test("int32 overflow preflight prevents writes", function()
    local f = fixture(); f.quest[1].QuestXPRewardNormal = 2147483647; f.control.inspect()
    assert(not pcall(f.control.set, 2)); assert(f.writes() == 0)
end)
test("session cleanup restores and requires a new read", function()
    local f = fixture(); f.control.inspect(); f.control.set(3); f.control.reset()
    assert(f.quest[1].QuestXPRewardNormal == 50 and not f.control.owned())
    assert(not pcall(f.control.set, 2))
end)
test("failed rollback retains ownership for later retry", function()
    local f = fixture(); f.control.inspect(); f.control.set(2); f.fail("Small")
    assert(not pcall(f.control.restore)); assert(f.control.owned())
    f.fail(nil); f.control.restore(); assert(not f.control.owned() and f.combat[1].XP == 20)
end)
test("successful read keeps unsupported UI disabled and rejects direct activation", function()
    local f = fixture(); local registration, queue
    ExecuteInGameThread = function(callback) queue = callback end
    local menu = { Register = function(value) registration = value end, Set = function() end, SetLabel = function() end }
    module.Init(menu, f.helpers)
    local field = registration.items[1]; assert(field.enabled == false)
    registration.items[2].onClick(); queue(); assert(field.enabled == false)
    field.onChange(2); assert(not pcall(queue)); assert(f.quest[1].QuestXPRewardNormal == 50 and f.writes() == 0)
    registration.items[3].onClick(); queue(); assert(field.enabled == false and f.quest[1].QuestXPRewardNormal == 50)
end)
local Facade = assert(loadfile((arg[1]:gsub("XPRewardControl.lua$", "ImportedMenuFacade.lua"))))()
local function facadeFixture()
    local f, menu = fixture(), Facade.New()
    ExecuteInGameThread = function(callback) callback() end
    local candidate = module.Init(menu, f.helpers)
    menu.Session("xp-test", true)
    local counter = 0
    local function dispatch(action, item, value)
        counter = counter + 1
        menu.Dispatch({ request_id = "xp-" .. counter, session_id = "xp-test", action = action,
            section_id = "DWXPRewards", item_id = item, value = value, value_type = type(value) })
    end
    -- Isolated candidate ownership simulates a prior adapter requiring cleanup;
    -- the release facade can never activate this known-unsupported route.
    candidate.inspect(); candidate.set(2)
    dispatch("invoke", "refresh")
    assert(menu.Get("DWXPRewards", "owned") == true)
    return f, menu, dispatch
end
test("real facade StopControls restores row and native getter baselines", function()
    local f, menu = facadeFixture()
    menu.StopControls()
    assert(menu.Get("DWXPRewards", "owned") == false and menu.Get("DWXPRewards", "multiplier") == 1)
    assert(f.quest[1].QuestXPRewardNormal == 50 and f.combat[1].XP == 20)
    assert(f.subsystem:GetXPAmountByRewardType(0) == 1800)
end)
test("failed StopControls preserves active recovery flag and retries", function()
    local f, menu = facadeFixture(); f.fail("Small")
    menu.StopControls(); assert(menu.Get("DWXPRewards", "owned") == true)
    f.fail(nil); menu.StopControls()
    assert(menu.Get("DWXPRewards", "owned") == false and f.quest[1].QuestXPRewardNormal == 50)
end)
test("owned true cannot activate rewards while false restores", function()
    local f, menu, dispatch = facadeFixture()
    dispatch("set", "owned", false)
    assert(menu.Get("DWXPRewards", "owned") == false and f.quest[1].QuestXPRewardNormal == 50)
    local before = f.writes(); dispatch("set", "owned", true)
    assert(menu.Get("DWXPRewards", "owned") == false and f.writes() == before)
end)
test("ResetSession publishes actual ownership on failure and restoration", function()
    local f, menu = facadeFixture(); f.fail("Small")
    assert(not pcall(module.ResetSession)); assert(menu.Get("DWXPRewards", "owned") == true)
    f.fail(nil); module.ResetSession()
    assert(menu.Get("DWXPRewards", "owned") == false and menu.Get("DWXPRewards", "multiplier") == 1)
end)
print(count .. " XP reward control tests passed")
