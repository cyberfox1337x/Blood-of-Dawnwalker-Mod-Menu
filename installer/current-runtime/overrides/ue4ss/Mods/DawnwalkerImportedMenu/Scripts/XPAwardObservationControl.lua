local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("xp_award_observation_control")
local Observer = require("DawnwalkerXPAwardObservation")
local Json = require("ImportedMenuFacade")
local M = {}
local CLASS, SECTION = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem", "DWXPAwardObservation"
local ENUM = "/Script/Quest.EQuestExperienceRewardAmount"
local function address(object)
    assert(object and object:IsValid() == true, "XP observation object unavailable")
    return tostring(object:GetAddress())
end
local function amount(value)
    assert(type(value) == "number" and value == value and value >= 0 and value <= 2147483647 and value % 1 == 0,
        "XP amount is not a nonnegative int32")
    return value
end
local function signature(path, withReward)
    assert(PropertyTypes and PropertyTypes.IntProperty ~= nil and PropertyTypes.EnumProperty ~= nil,
        "Required XP reflected property types are unavailable")
    local fn = StaticFindObject(path)
    address(fn)
    assert(fn:IsA("/Script/CoreUObject.Function"), "XP target is not a loaded UFunction")
    local properties, count = {}, 0
    fn:ForEachProperty(function(property)
        count = count + 1
        assert(count <= 2, "XP UFunction parameter count changed")
        local name = property:GetFName():ToString()
        assert(properties[name] == nil, "XP UFunction has duplicate parameter names")
        properties[name] = property
        -- Pinned UE4SS explicitly supports nil for continuation. Returning false
        -- enters its boolean stack-consumption branch, which failed on the
        -- second property in the live getter walk. Keep all descriptor guards.
    end)
    assert(count == (withReward and 2 or 1), "XP UFunction signature count changed")
    assert(properties.ReturnValue and properties.ReturnValue:IsA(PropertyTypes.IntProperty), "XP return is not IntProperty")
    if withReward then
        assert(properties.RewardAmount and properties.RewardAmount:IsA(PropertyTypes.EnumProperty), "XP reward is not the expected EnumProperty")
    end
end
function M.Init(menu, helpers)
    local baselineXP, baselineSession, direct, lastError
    local function context()
        local player = helpers.GetPlayer()
        local playerId = address(player)
        local world, controller = player:GetWorld(), player.Controller
        local worldId, controllerId = address(world), address(controller)
        assert(address(controller.Pawn) == playerId, "XP player possession changed")
        local library, class = StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary"), StaticFindObject(CLASS)
        address(library); address(class)
        local subsystem = library:GetGameInstanceSubsystem(player, class)
        assert(subsystem and subsystem:IsA(CLASS), "Current XP subsystem class differs")
        return { subsystem = subsystem, sessionId = table.concat({ playerId, worldId, controllerId, address(subsystem) }, ":") }
    end
    local controller = Observer.New({ get_context = context, game_thread = IsInGameThread,
        register_hook = RegisterHook, unregister_hook = UnregisterHook,
        validate_functions = function(getter, award)
            assert(getter == CLASS .. ":GetXPAmountByRewardType" and award == CLASS .. ":AddQuestXP", "Unexpected XP hook target")
            signature(getter, true); signature(award, true); signature(CLASS .. ":GetCurrentXP", false)
            return true
        end })
    local function currentXP()
        signature(CLASS .. ":GetCurrentXP", false)
        local before = context()
        local xp = amount(before.subsystem:GetCurrentXP())
        assert(context().sessionId == before.sessionId, "XP identity changed during read")
        return xp, before
    end
    local function smallReward(subsystem)
        local enum = StaticFindObject(ENUM)
        address(enum)
        local name = enum:GetNameByValue(2):ToString()
        assert(name == "Small" or name == "EQuestExperienceRewardAmount::Small", "Loaded Small XP enum no longer equals 2")
        local rows, rowStruct = subsystem.LoadedQuestXPRewardTable, StaticFindObject("/Script/DogwoodCharacterDevelopment.XPQuestRewardTypeRow")
        address(rows); address(rowStruct)
        assert(rows:IsA("/Script/Engine.DataTable") and address(rows:GetRowStruct()) == address(rowStruct), "XP reward table row structure changed")
        local count = #rows
        assert(type(count) == "number" and count >= 1 and count <= 256 and count % 1 == 0, "XP row count outside bounds")
        local records = rows:GetAllRows()
        assert(type(records) == "table", "XP rows are not a bounded Lua table")
        local seen, found = 0, false
        for _, entry in pairs(records) do
            seen = seen + 1; assert(seen <= count, "XP table changed during observation")
            assert(type(entry) == "table" and entry.Data, "XP row is malformed")
            if entry.Data.QuestXPRewardType == 2 then assert(not found, "Small XP reward row is ambiguous"); found = true end
        end
        assert(found and seen == count and #rows == count, "Small XP reward row unavailable or changed")
        return 2
    end
    local function snapshot(readXP)
        local report = controller.Snapshot()
        report.baselineXP, report.baselineSession, report.controlError = baselineXP, baselineSession, lastError
        report.directGetter = direct and { rewardType = direct.rewardType, amount = direct.amount,
            beforeXP = direct.beforeXP, afterXP = direct.afterXP } or nil
        if readXP then report.currentXP = currentXP() end
        return report
    end
    local function publish(readXP)
        local report = snapshot(readXP)
        report.rewards = nil -- Keep the menu transport summary bounded; full rows remain in Snapshot().
        menu.Set(SECTION, "owned", report.hooksInstalled > 0)
        menu.SetLabel(SECTION, "status", Json.Encode(report))
    end
    local function execute(callback)
        ExecuteInGameThread(function()
            local ok, reason = pcall(callback)
            if not ok then
                lastError = tostring(reason):sub(1, 512)
                publish(false)
                error(lastError)
            end
            lastError = nil; publish(true)
        end)
    end
    local function stop()
        local ok, reason = controller.Stop()
        assert(ok, reason)
    end
    function M.ResetSession()
        stop(); publish(false)
    end
    function M.RefreshSession()
        local before = controller.Snapshot()
        if before.hooksInstalled == 0 then return end
        local ok, reason = controller.RefreshSession()
        assert(ok, reason)
        local after = controller.Snapshot()
        if before.active ~= after.active or before.hooksInstalled ~= after.hooksInstalled then publish(false) end
    end
    function M.Snapshot() return snapshot(true) end
    menu.Register({ id = SECTION, title = "XP award observation diagnostics", tab = "Player", items = {
        { id = "start", type = "button", label = "Start XP dispatch observation", onClick = function() execute(function()
            signature(CLASS .. ":GetCurrentXP", false)
            local xp, current = currentXP()
            local ok, reason = controller.Start(); assert(ok, reason)
            baselineXP, baselineSession, direct = xp, current.sessionId, nil
        end) end },
        { id = "getter", type = "button", label = "Observe Small XP getter (no award)", onClick = function() execute(function()
            local before, current = currentXP()
            local reward = smallReward(current.subsystem)
            local result = controller.ReadGetter(reward)
            local after, fresh = currentXP()
            assert(current.sessionId == fresh.sessionId and before == after, "Direct XP getter changed XP or session")
            direct = { rewardType = reward, amount = result, beforeXP = before, afterXP = after }
        end) end },
        { id = "read", type = "button", label = "Read XP dispatch observation", onClick = function() execute(function()
            local ok, reason = controller.RefreshSession(); assert(ok, reason)
        end) end },
        { id = "stop", type = "button", label = "Stop XP dispatch observation", onClick = function() execute(stop) end },
        { id = "owned", type = "checkbox", label = "XP observation hooks installed", default = false,
          onChange = function(value) assert(value == false, "Use the explicit observation start action"); execute(stop) end },
        { id = "status", type = "label", label = "Read-only observation has not started. No XP will be granted." },
    } })
end
return M
