local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("xp_reward_control")
local M = {}
local QUEST = "/Script/DogwoodCharacterDevelopment.XPQuestRewardTypeRow"
local COMBAT = "/Script/DogwoodCombat.CombatReward"
local SUBSYSTEM = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"
local UNSUPPORTED = "XP multiplier unavailable: native rewards do not follow loaded table changes. A verified reward update route is required."
local function integer(value)
    return type(value) == "number" and value == value and value >= 0 and value <= 2147483647 and value % 1 == 0
end
local function address(object)
    assert(object and object:IsValid(), "XP object unavailable")
    return tostring(object:GetAddress())
end
local function snapshot(helpers)
    local player = helpers.GetPlayer()
    local playerAddress = address(player)
    local world, controller = player:GetWorld(), player.Controller
    assert(address(controller.Pawn) == playerAddress, "Player possession changed")
    local library = StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary")
    local class = StaticFindObject(SUBSYSTEM)
    address(library); address(class)
    local subsystem = library:GetGameInstanceSubsystem(player, class)
    assert(subsystem and subsystem:IsA(SUBSYSTEM), "XP subsystem unavailable")
    local result = { identity = table.concat({playerAddress, address(world), address(controller), address(subsystem)}, ":"), rows = {}, getters = {} }
    for _, source in ipairs({
        { subsystem.LoadedQuestXPRewardTable, QUEST, "QuestXPRewardNormal" },
        { subsystem.LoadedCombatRewardsTable, COMBAT, "XP" },
    }) do
        local dataTable, path, field = source[1], source[2], source[3]
        local tableAddress = address(dataTable)
        assert(dataTable:IsA("/Script/Engine.DataTable"), "XP source is not a table")
        local structAddress = address(StaticFindObject(path))
        assert(address(dataTable:GetRowStruct()) == structAddress, "XP row structure changed")
        local count = #dataTable
        assert(integer(count) and count > 0 and count <= 256, "XP table size exceeds supported bounds")
        local allRows = dataTable:GetAllRows()
        assert(type(allRows) == "table", "XP row enumeration failed")
        local seen, found = {}, 0
        for _, entry in pairs(allRows) do
            found = found + 1
            assert(found <= count and type(entry) == "table", "XP table changed during enumeration")
            local name = entry.Name
            assert(type(name) == "string" and #name > 0 and #name <= 256 and not seen[name], "XP row name invalid")
            seen[name] = true
            -- FindRow returns the actual reflected row; GetAllRows is used only for names.
            local row = dataTable:FindRow(name)
            assert(row, "XP row disappeared")
            local pointer = row:GetStructAddress()
            assert(type(pointer) == "number" and pointer > 0, "XP row address unavailable")
            local amount = row[field]
            assert(integer(amount), "XP row is not a nonnegative int32")
            local rewardType
            if path == QUEST then
                rewardType = row.QuestXPRewardType
                assert(integer(rewardType) and rewardType <= 255, "XP reward enum invalid")
                local getter = subsystem:GetXPAmountByRewardType(rewardType)
                assert(integer(getter), "XP getter invalid")
                assert(result.getters[rewardType] == nil or result.getters[rewardType] == getter, "XP getter changed during capture")
                result.getters[rewardType] = getter
            end
            result.rows[#result.rows + 1] = { key = path .. ":" .. name, tableAddress = tableAddress,
                structAddress = structAddress, pointer = pointer, field = field, ref = row, xp = amount, rewardType = rewardType }
        end
        assert(found == count and #dataTable == count, "XP row count changed")
    end
    table.sort(result.rows, function(a, b) return a.key < b.key end)
    assert(address(helpers.GetPlayer()) == playerAddress and address(controller.Pawn) == playerAddress
        and address(player:GetWorld()) == address(world), "XP context changed during capture")
    return result
end
local function sameContext(baseline, current)
    assert(baseline.identity == current.identity and #baseline.rows == #current.rows, "XP session or table rows changed; recovery retained")
    for index, row in ipairs(baseline.rows) do
        local other = current.rows[index]
        assert(row.key == other.key and row.tableAddress == other.tableAddress and row.structAddress == other.structAddress
            and row.pointer == other.pointer and row.rewardType == other.rewardType, "XP row identity changed; recovery retained")
    end
end
function M.New(helpers)
    local owned, ready, factor = nil, false, 1
    local function readOwned()
        local current = snapshot(helpers)
        sameContext(owned.baseline, current)
        return current
    end
    local function verify(expectedFactor)
        local current = readOwned()
        for index, row in ipairs(current.rows) do
            assert(row.xp == owned.baseline.rows[index].xp * expectedFactor, "XP row readback rejected")
        end
        for enum, amount in pairs(owned.baseline.getters) do
            assert(current.getters[enum] == amount * expectedFactor, "Native XP getter did not reflect changed rewards")
        end
    end
    local function restore()
        if not owned then factor = 1; return end
        local current = readOwned()
        -- Preflight every row before restoring any: never overwrite another owner's edit.
        for index, row in ipairs(current.rows) do
            assert(row.xp == owned.expected[index] or row.xp == owned.baseline.rows[index].xp,
                "XP row changed externally; recovery retained")
        end
        for index, row in ipairs(current.rows) do
            local amount = owned.baseline.rows[index].xp
            if row.xp ~= amount then row.ref[row.field] = amount end
        end
        verify(1)
        owned, factor = nil, 1
    end
    local function apply(value)
        assert(integer(value) and value >= 1 and value <= 5, "XP multiplier must be an integer from 1 to 5")
        if value == 1 then restore(); return end
        assert(ready, "Read XP rewards before changing the multiplier")
        if owned then verify(factor) end
        local current = snapshot(helpers)
        if owned then
            sameContext(owned.baseline, current)
            for index, row in ipairs(current.rows) do
                assert(row.xp == owned.expected[index], "XP row changed before assignment")
            end
        end
        local baseline = owned and owned.baseline or current
        for _, row in ipairs(baseline.rows) do assert(integer(row.xp * value), "Scaled XP exceeds int32") end
        for _, amount in pairs(baseline.getters) do assert(integer(amount * value), "Scaled XP getter exceeds int32") end
        if not owned then
            owned = { baseline = baseline, expected = {} }
            for index, row in ipairs(current.rows) do owned.expected[index] = row.xp end
        end
        for index, row in ipairs(current.rows) do
            local amount = baseline.rows[index].xp * value
            -- Retain both old and intended state if the native field assignment throws.
            local previous = owned.expected[index]
            owned.expected[index] = amount
            local ok, cause = pcall(function() row.ref[row.field] = amount end)
            if not ok then
                if row.ref[row.field] == previous then owned.expected[index] = previous end
                error(cause)
            end
        end
        verify(value)
        factor = value
    end
    return {
        inspect = function()
            ready = false
            if owned then verify(factor) else snapshot(helpers) end
            ready = true
        end,
        set = function(value)
            local ok, cause = pcall(apply, value)
            if not ok then
                ready = false
                local restored, recovery = pcall(restore)
                error(tostring(cause) .. (restored and "; baseline restored" or "; recovery pending: " .. tostring(recovery)))
            end
        end,
        restore = restore,
        owned = function() return owned ~= nil end,
        value = function() return factor end,
        reset = function() restore(); ready = false end,
    }
end
function M.Init(menu, helpers)
    local id, control = "DWXPRewards", M.New(helpers)
    local field = { type = "number", id = "multiplier", label = "Quest & combat XP rewards",
        min = 1, max = 5, step = 1, default = 1, enabled = false }
    local function execute(callback, success, enable)
        local ok, cause = pcall(callback)
        -- Live verification rejected the table-only route. Reads must not unlock it.
        field.enabled = false
        menu.Set(id, "multiplier", control.value())
        menu.Set(id, "owned", control.owned())
        menu.SetLabel(id, "status", ok and success or ("XP rewards failed: " .. tostring(cause)))
        assert(ok, cause)
    end
    local function run(callback, success, enable)
        ExecuteInGameThread(function() execute(callback, success, enable) end)
    end
    field.onChange = function(value)
        run(function()
            assert(value == 1, UNSUPPORTED)
            control.reset()
        end, "Original XP rewards restored.", false)
    end
    menu.Register({ id = id, title = "Quest & combat XP rewards", tab = "Player", items = {
        field,
        { type = "button", id = "refresh", label = "Read XP rewards", onClick = function()
            run(control.inspect, UNSUPPORTED) end },
        { type = "button", id = "restore", label = "Restore XP rewards", onClick = function()
            run(control.reset, "Original loaded XP rewards restored. Read rewards before enabling again.", false)
        end },
        { type = "label", id = "status", label = UNSUPPORTED },
        -- The facade closes number controls by restoring their registered ownership flag.
        -- Keep this actionable after errors so cleanup can retry without enabling writes.
        { type = "checkbox", id = "owned", label = "XP reward override active", default = false,
            onChange = function(value)
                run(function()
                    assert(value == false, "Use the XP reward multiplier after reading rewards")
                    control.reset()
                end, "Original XP rewards restored. Read rewards before enabling again.", false)
            end },
    } })
    M.ResetSession = function()
        execute(control.reset, "Original XP rewards restored. Read rewards before enabling again.", false)
    end
    return control
end
return M
