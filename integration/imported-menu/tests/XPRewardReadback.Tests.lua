local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("xp_reward_readback_tests")
local module = assert(loadfile(assert(arg[1])))()
local function object(id)
    return { IsValid = function() return true end, GetAddress = function() return id end,
        IsA = function() return true end }
end
local questStruct, combatStruct = object(10), object(11)
local function dataTable(id, struct, source)
    local result = object(id)
    result.GetRowStruct = function() return struct end
    result.ForEachRow = function() error("Native callback bridge must not be used") end
    result.GetAllRows = function()
        local rows = {}
        for index, row in ipairs(source) do rows[index] = { Name = row.name, Data = row } end
        return rows
    end
    return setmetatable(result, { __len = function() return #source end })
end
local function fixture()
    local player, world, controller, subsystem = object(1), object(2), object(3), object(4)
    player.Controller, controller.Pawn = controller, player
    player.GetWorld = function() return world end
    local questRows = { { name = "Small", QuestXPRewardType = 2, QuestXPRewardNormal = 50 } }
    local combatRows = { { name = "Enemy", XP = 20 } }
    subsystem.LoadedQuestXPRewardTable = dataTable(5, questStruct, questRows)
    subsystem.LoadedCombatRewardsTable = dataTable(6, combatStruct, combatRows)
    subsystem.GetXPAmountByRewardType = function(_, rewardType) assert(rewardType == 2); return 50 end
    local library = object(7)
    library.GetGameInstanceSubsystem = function() return subsystem end
    StaticFindObject = function(path)
        if path:find("Default__SubsystemBlueprintLibrary", 1, true) then return library end
        if path:find("XPQuestRewardTypeRow", 1, true) then return questStruct end
        if path:find("CombatReward", 1, true) then return combatStruct end
        return object(8)
    end
    return { GetPlayer = function() return player end }, subsystem, questRows, combatRows, controller
end
local count = 0
local function test(name, callback)
    callback(); count = count + 1; print("PASS " .. name)
end
test("reads both tables without modifying scalar rows", function()
    local helpers, _, quest, combat = fixture()
    local result = module.Probe(helpers)
    assert(result.quest.rows[1].getter == 50 and result.combat.rows[1].xp == 20)
    assert(quest[1].QuestXPRewardNormal == 50 and combat[1].XP == 20)
end)
test("retains getter mismatch as explicit observation without approving multiplier", function()
    local helpers, subsystem = fixture()
    subsystem.GetXPAmountByRewardType = function() return 51 end
    local result = module.Probe(helpers)
    assert(result.quest.rows[1].xp == 50 and result.quest.rows[1].getter == 51)
    assert(result.mismatchCount == 1 and result.multiplierVerified == false)
    local text = module.Read(helpers)
    assert(text:find("quest_getter_mismatches=1", 1, true) and text:find("getter_matches_row=0", 1, true))
end)
test("still rejects invalid getter values", function()
    local helpers, subsystem = fixture()
    subsystem.GetXPAmountByRewardType = function() return -1 end
    assert(not pcall(module.Probe, helpers))
end)
test("rejects unexpected row struct", function()
    local helpers, subsystem = fixture()
    subsystem.LoadedCombatRewardsTable.GetRowStruct = function() return questStruct end
    assert(not pcall(module.Probe, helpers))
end)
test("rejects noninteger XP", function()
    local helpers, _, _, combat = fixture(); combat[1].XP = 1.5
    assert(not pcall(module.Probe, helpers))
end)
test("rejects oversized tables before iteration", function()
    local helpers, _, quest = fixture()
    for index = 2, 257 do quest[index] = quest[1] end
    assert(not pcall(module.Probe, helpers))
end)
test("rejects changed possession", function()
    local helpers, _, _, _, controller = fixture(); controller.Pawn = object(90)
    assert(not pcall(module.Probe, helpers))
end)
test("rejects malformed GetAllRows entries", function()
    local helpers, subsystem = fixture()
    subsystem.LoadedQuestXPRewardTable.GetAllRows = function() return { false } end
    assert(not pcall(module.Probe, helpers))
end)
test("checks returned row count against native count", function()
    local helpers, subsystem = fixture()
    subsystem.LoadedQuestXPRewardTable.GetAllRows = function() return {} end
    assert(not pcall(module.Probe, helpers))
end)
test("explicit refresh only schedules read on game thread", function()
    local helpers = fixture()
    local registered, scheduled, status
    ExecuteInGameThread = function(callback) scheduled = callback end
    module.Init({ Register = function(section) registered = section end,
        SetLabel = function(_, _, label) status = label end }, helpers)
    assert(not scheduled and not status and registered.id == "DWXPReadback")
    registered.items[1].onClick(); assert(scheduled and not status)
    scheduled(); assert(status:find("passed=1", 1, true))
end)
print(count .. " XP reward readback tests passed")
