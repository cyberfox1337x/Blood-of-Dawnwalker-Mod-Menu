local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("xp_reward_readback")
local M = {}
local SUBSYSTEM = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"
local QUEST_ROW = "/Script/DogwoodCharacterDevelopment.XPQuestRewardTypeRow"
local COMBAT_ROW = "/Script/DogwoodCombat.CombatReward"
local LIMIT = 256

local function address(object)
    assert(object and object:IsValid(), "Required XP object is unavailable.")
    return tostring(object:GetAddress())
end

local function integer(value)
    return type(value) == "number" and value == value and value >= 0 and value <= 2147483647 and value % 1 == 0
end

local function context(helpers)
    local player = helpers.GetPlayer()
    local playerAddress = address(player)
    local world, controller = player:GetWorld(), player.Controller
    local worldAddress, controllerAddress = address(world), address(controller)
    assert(address(controller.Pawn) == playerAddress, "Player possession changed.")
    local library = StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary")
    local class = StaticFindObject(SUBSYSTEM)
    address(library); address(class)
    local subsystem = library:GetGameInstanceSubsystem(player, class)
    assert(subsystem and subsystem:IsA(SUBSYSTEM), "Character development subsystem is unavailable.")
    return subsystem, table.concat({ playerAddress, worldAddress, controllerAddress, address(subsystem) }, ":")
end

local function rows(dataTable, structPath, field, subsystem)
    local tableAddress = address(dataTable)
    assert(dataTable:IsA("/Script/Engine.DataTable"), "XP source is not a DataTable.")
    local expectedStruct = StaticFindObject(structPath)
    local structAddress = address(expectedStruct)
    assert(address(dataTable:GetRowStruct()) == structAddress, "XP row structure differs from the captured SDK: " .. structPath)
    local count = #dataTable
    assert(integer(count) and count > 0 and count <= LIMIT, "XP table row count is empty or exceeds the inspection limit.")
    local result, seen = {}, {}
    -- The installed build fails inside ForEachRow's native callback bridge.
    -- GetAllRows is a documented plain-table return and avoids that bridge.
    -- Bound the native allocation above; retain only scalar copies below.
    local allRows = dataTable:GetAllRows()
    assert(type(allRows) == "table", "XP GetAllRows did not return a Lua table.")
    for _, entry in pairs(allRows) do
        assert(#result < LIMIT, "XP table changed beyond the inspection limit.")
        assert(type(entry) == "table", "XP GetAllRows entry is malformed.")
        local name, row = entry.Name, entry.Data
        assert(type(name) == "string" and #name > 0 and #name <= 256 and not seen[name], "XP row name is invalid or duplicated.")
        assert(row ~= nil, "XP row data is unavailable: " .. name)
        seen[name] = true
        local amount = row[field]
        assert(integer(amount), "XP amount is not a nonnegative int32: " .. name)
        local record = { name = name, xp = amount }
        if structPath == QUEST_ROW then
            local rewardType = row.QuestXPRewardType
            assert(integer(rewardType) and rewardType <= 255, "Quest reward enum is invalid: " .. name)
            local getter = subsystem:GetXPAmountByRewardType(rewardType)
            assert(integer(getter), "Quest XP getter is not a nonnegative int32: " .. name)
            record.rewardType, record.getter, record.getterMatchesRow = rewardType, getter, getter == amount
        end
        result[#result + 1] = record
    end
    assert(#result == count and #dataTable == count, "XP table row count changed during inspection.")
    assert(address(dataTable:GetRowStruct()) == structAddress, "XP row structure changed during inspection.")
    table.sort(result, function(a, b) return a.name < b.name end)
    return { address = tableAddress, structAddress = structAddress, rows = result }
end

function M.Probe(helpers)
    local subsystem, identity = context(helpers)
    local quest = rows(subsystem.LoadedQuestXPRewardTable, QUEST_ROW, "QuestXPRewardNormal", subsystem)
    local combat = rows(subsystem.LoadedCombatRewardsTable, COMBAT_ROW, "XP", subsystem)
    local fresh, freshIdentity = context(helpers)
    assert(identity == freshIdentity and address(fresh.LoadedQuestXPRewardTable) == quest.address
        and address(fresh.LoadedCombatRewardsTable) == combat.address, "XP source identity changed during inspection.")
    local mismatchCount = 0
    for _, row in ipairs(quest.rows) do
        if not row.getterMatchesRow then mismatchCount = mismatchCount + 1 end
    end
    return { ok = true, quest = quest, combat = combat, mismatchCount = mismatchCount, multiplierVerified = false }
end

function M.Read(helpers)
    local ok, result = pcall(M.Probe, helpers)
    local prefix = "probe_id=player:xp-rewards;mutation_authorized=0;release_visible=0;passed="
    if not ok then return prefix .. "0\n" .. tostring(result) end
    local lines = { prefix .. "1;multiplier_verified=0;quest_getter_mismatches=" .. result.mismatchCount,
        "Read-only observations only. Table/getter agreement does not establish a usable XP multiplier." }
    for _, kind in ipairs({ "quest", "combat" }) do
        local source = result[kind]
        lines[#lines + 1] = kind .. ":table=" .. source.address .. ";struct=" .. source.structAddress .. ";rows=" .. #source.rows
        for _, row in ipairs(source.rows) do
            lines[#lines + 1] = kind .. ":" .. row.name .. ";xp=" .. row.xp
                .. (row.rewardType and ";type=" .. row.rewardType .. ";getter=" .. row.getter
                    .. ";getter_matches_row=" .. (row.getterMatchesRow and "1" or "0") or "")
        end
    end
    return table.concat(lines, "\n")
end

function M.Init(menu, helpers)
    local id = "DWXPReadback"
    menu.Register({ id = id, title = "XP reward diagnostics", tab = "Player", items = {
        { type = "button", id = "refresh", label = "Read XP reward tables", onClick = function()
            local ok, cause = pcall(function()
                ExecuteInGameThread(function() menu.SetLabel(id, "status", M.Read(helpers)) end)
            end)
            if not ok then menu.SetLabel(id, "status", "XP readback scheduling failed: " .. tostring(cause)) end
        end },
        { type = "label", id = "status", label = "Read-only XP reward inspection has not run." },
    } })
end
return M
