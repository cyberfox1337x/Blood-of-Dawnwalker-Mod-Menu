local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("xp_award_observation_control_tests")
local root = "integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts/"
local observer = assert(loadfile(root .. "DawnwalkerXPAwardObservation.lua"))()
local json = assert(loadfile(root .. "ImportedMenuFacade.lua"))()
local function fixture()
    local class = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"
    local properties = { IntProperty = 1, EnumProperty = 2 }
    local section, hooks, removed, getterCalls = nil, {}, 0, 0
    local changedSignature, changedEnum, extraParameter, pawnId = false, false, false, 1
    local function object(id, kind)
        return { IsValid = function() return true end, GetAddress = function() return id end,
            IsA = function(_, expected) return expected == kind end }
    end
    local player, world, owner, subsystem = object(1), object(2), object(3), object(4, class)
    player.GetAddress = function() return pawnId end
    player.Controller, owner.Pawn = owner, player
    function player:GetWorld() return world end
    local rowStruct, tableRows = object(5), object(6, "/Script/Engine.DataTable")
    tableRows[1] = true
    function tableRows:GetRowStruct() return rowStruct end
    function tableRows:GetAllRows() return { { Name = "Small", Data = { QuestXPRewardType = 2 } } } end
    subsystem.LoadedQuestXPRewardTable = tableRows
    function subsystem:GetCurrentXP() return 1000 end
    function subsystem:AddQuestXP() error("Granting XP is forbidden in observation") end
    local function remote(value) return { get = function() return value end } end
    function subsystem:GetXPAmountByRewardType(category)
        getterCalls = getterCalls + 1
        local hook = hooks[class .. ":GetXPAmountByRewardType"]
        if hook then assert(hook.pre(remote(self), remote(category)) == nil) end
        if hook then assert(hook.post(remote(self), remote(50), remote(category)) == nil) end
        return 50
    end
    local library, enum = object(7), object(8)
    function library:GetGameInstanceSubsystem() return subsystem end
    function enum:GetNameByValue(value) assert(value == 2); return { ToString = function() return changedEnum and "Medium" or "EQuestExperienceRewardAmount::Small" end } end
    local function property(name, kind)
        return { GetFName = function() return { ToString = function() return name end } end,
            IsA = function(_, expected) return kind == expected end }
    end
    local function reflected(path)
        local fn = object(9, "/Script/CoreUObject.Function")
        function fn:ForEachProperty(visit)
            local continuation = visit(property("ReturnValue", changedSignature and 99 or properties.IntProperty))
            if not path:match(":GetCurrentXP$") then
                -- Reproduce the observed second-iteration native callback loss.
                assert(continuation == nil, "attempt to call a nil value after boolean continuation")
                assert(visit(property("RewardAmount", properties.EnumProperty)) == nil)
                if extraParameter then visit(property("Unexpected", properties.IntProperty)) end
            end
        end
        return fn
    end
    local values = {}
    local menu = { Register = function(value) section = value end,
        Set = function(_, key, value) values[key] = value end, SetLabel = function(_, key, value) values[key] = value end }
    local env = setmetatable({
        require = function(name) return name == "DawnwalkerXPAwardObservation" and observer or json end,
        IsInGameThread = function() return true end,
        PropertyTypes = properties,
        ExecuteInGameThread = function(callback) callback() end,
        StaticFindObject = function(path)
            if path:match("Default__SubsystemBlueprintLibrary$") then return library end
            if path == class then return object(10) end
            if path:match("XPQuestRewardTypeRow$") then return rowStruct end
            if path:match("EQuestExperienceRewardAmount$") then return enum end
            return reflected(path)
        end,
        RegisterHook = function(path, pre, post) hooks[path] = { pre = pre, post = post }; return 11, 12 end,
        UnregisterHook = function(path, pre, post) assert(pre == 11 and post == 12); assert(hooks[path]); hooks[path] = nil; removed = removed + 1 end,
    }, { __index = _G })
    local control = assert(loadfile(root .. "XPAwardObservationControl.lua", "t", env))()
    control.Init(menu, { GetPlayer = function() return player end })
    return { control = control, values = values, hooks = hooks,
        action = function(id) for _, item in ipairs(section.items) do if item.id == id then return item.onClick() end end; error("unknown action") end,
        badSignature = function() changedSignature = true end, badEnum = function() changedEnum = true end,
        missingEnumType = function() properties.EnumProperty = nil end,
        extraParameter = function() extraParameter = true end,
        changeSession = function() pawnId = 20 end, getters = function() return getterCalls end, removed = function() return removed end }
end
local function test(name, run) run(); print("PASS " .. name) end
test("start and explicit getter capture baseline without granting XP", function()
    local f = fixture(); assert(next(f.hooks) == nil and f.getters() == 0)
    f.action("start"); assert(f.values.owned == true)
    f.action("getter"); local state = f.control.Snapshot()
    assert(state.baselineXP == 1000 and state.currentXP == 1000 and state.directGetter.amount == 50)
    assert(state.directGetter.beforeXP == state.directGetter.afterXP and state.counters.getter_direct == 1)
    f.action("read"); f.action("stop"); assert(f.values.owned == false and f.removed() == 2)
end)
test("signature mismatch fails before hooks or calls", function()
    local f = fixture(); f.badSignature(); assert(not pcall(f.action, "start"))
    assert(next(f.hooks) == nil and f.getters() == 0)
end)
test("loaded Small enum must match before direct getter", function()
    local f = fixture(); f.action("start"); f.badEnum(); assert(not pcall(f.action, "getter"))
    assert(f.getters() == 0); f.action("stop"); assert(f.removed() == 2)
end)
test("missing EnumProperty metadata refuses before registration", function()
    local f = fixture(); f.missingEnumType(); assert(not pcall(f.action, "start"))
    assert(next(f.hooks) == nil and f.getters() == 0)
end)
test("nil continuation still rejects extra reflected parameters", function()
    local f = fixture(); f.extraParameter(); assert(not pcall(f.action, "start"))
    assert(next(f.hooks) == nil and f.getters() == 0)
end)
test("session lifecycle removes both hook pairs and retains observation evidence", function()
    local f = fixture(); f.action("start"); f.changeSession(); f.control.RefreshSession()
    assert(f.removed() == 2 and f.values.owned == false)
    f.control.ResetSession(); assert(f.removed() == 2)
end)
