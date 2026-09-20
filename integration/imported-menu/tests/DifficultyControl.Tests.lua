local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("difficulty_adapter_tests")
local path = assert(arg[1])
local function assert_equal(a,b,label) assert(a==b,label) end
local function fixture()
local function make_object(address, class_path, full_name)
    return {
        IsValid = function() return true end,
        GetAddress = function() return address end,
        GetFullName = function() return full_name or (class_path .. " HarnessObject") end,
        IsA = function(_, requested_class) return requested_class == class_path end,
    }
end

local function parameter(value)
    return { get = function() return value end }
end

local function make_map(entries)
    local map = { _entries = entries }
    return setmetatable(map, {
        __len = function()
            local count = 0
            for _ in pairs(entries) do count = count + 1 end
            return count
        end,
        __index = {
            Contains = function(_, key) return entries[key] ~= nil end,
            Find = function(_, key)
                if entries[key] == nil then error("missing key") end
                return parameter(entries[key])
            end,
            ForEach = function(_, callback)
                for key, value in pairs(entries) do callback(parameter(key), parameter(value)) end
            end,
        },
    })
end

local function make_local_map_table(entries)
    local result = {}
    for key, value in pairs(entries) do
        result[parameter(key)] = parameter(value)
    end
    return result
end

local function make_single_lookup_map(entries)
    local lookups = 0
    local length_generation = 0
    local result = assert(io.tmpfile(), "Unable to create userdata map fixture.")
    debug.setmetatable(result, {
        __len = function()
            length_generation = length_generation + 1
            local count = 0
            for _ in pairs(entries) do count = count + 1 end
            return count
        end,
        __index = function(_, key)
            if key ~= "ForEach" then return nil end
            lookups = lookups + 1
            if lookups > 1 then return nil end
            local captured_generation = length_generation
            return function(self, callback)
                assert_equal(self, result, "captured ForEach receiver")
                assert_equal(type(callback), "function", "captured ForEach callback")
                assert_equal(length_generation, captured_generation, "no ABI operation occurs after ForEach lookup")
                lookups = 0
                for entry_key, entry_value in pairs(entries) do
                    local callback_result = callback(parameter(entry_key), parameter(entry_value))
                    if callback_result == false then
                        error("UE4SS v3.0.1 TMap callback must return nil while continuing")
                    end
                end
            end
        end,
    })
    return result
end

local world = make_object(5101, "/Script/Engine.World", "World /Game/Harness.Harness")
local alternate_world = make_object(5199, "/Script/Engine.World", "World /Game/Other.Other")
local player = make_object(5102, "/Script/Dawnwalker.DawnwalkerPlayerCharacter", "DawnwalkerPlayerCharacter /Game/Harness.Player")
local subsystem = make_object(5103, "/Script/DogwoodCombat.CombatSubsystem", "CombatSubsystem /Game/Harness.Harness:CombatSubsystem_1")
local config = make_object(5104, "/Script/DogwoodStats.DifficultyConfig", "DifficultyConfig /Game/_Dawnwalker/Combat/DA_DifficultyConfig.DA_DifficultyConfig")
local settings_default = make_object(5105, "/Script/RebelSettings.RebelGameUserSettings", "RebelGameUserSettings /Script/RebelSettings.Default__RebelGameUserSettings")
local settings = make_object(5106, "/Script/RebelSettings.RebelGameUserSettings", "RebelGameUserSettings /Engine/Transient.RebelGameUserSettings_Harness")
local subsystem_library = make_object(5107, "/Script/Engine.SubsystemBlueprintLibrary", "SubsystemBlueprintLibrary /Script/Engine.Default__SubsystemBlueprintLibrary")
local subsystem_class = make_object(5108, "/Script/CoreUObject.Class", "Class /Script/DogwoodCombat.CombatSubsystem")
local scaling_table = make_object(5109, "/Script/Engine.DataTable", "DataTable /Game/Harness.DT_Scaling")

local function make_action(level)
    return {
        AttackAnimationSpeedMultiplier = 0.9 + level * 0.1,
        ParryWindowMultipliers = make_local_map_table({ Light = 1.0 + level * 0.1, Heavy = 0.8 + level * 0.1 }),
        AutoSelectBlockDirection = level < 2,
        bAllowAttackingWhileAnotherNPCIsPerformingBestNodeInject = level > 0,
        bAllowAttackingWhileAnotherNPCIsAttacking = level > 1,
        bAllowAttackingWhileAnotherNPCIsInParryReaction = true,
        bAllowAttackingWhileAnotherNPCIsInBlockReaction = level ~= 3,
        bAllowAttackingWhileAnotherNPCIsInOmniblockReaction = false,
        HelperTicketCooldownMultiplier = 1.0 + level,
        LowHealthHelperTicketCooldownMultiplier = 1.5 + level,
        HelperRangedAttackCooldownMultiplier = 2.0 + level,
        GlobalAILevelScaling = scaling_table,
    }
end

local function make_rpg(level)
    return {
        HealthMultiplier = 1.0 + level * 0.25,
        DamageMultiplier = 0.75 + level * 0.25,
        PlayerCombatStaminaCostsMultiplier = 0.5 + level * 0.25,
    }
end

local action_entries = {}
local rpg_entries = {}
for level = 0, 3 do
    action_entries[level] = make_action(level)
    rpg_entries[level] = make_rpg(level)
end
action_entries[1].ParryWindowMultipliers = make_single_lookup_map({ Light = 1.1, Heavy = 0.9 })
config.ActionDifficulties = make_map(action_entries)
config.RPGDifficulties = make_map(rpg_entries)

local action_level = 1
local rpg_level = 1
local owner_action = 1
local owner_rpg = 1
local subsystem_world = world
local action_set_calls = {}
local rpg_set_calls = {}
local fail_next_action_restore = false
local corrupt_next_action_readback = false
local corrupt_after_action_set = false

player.GetWorld = function() return world end
subsystem.GetWorld = function() return subsystem_world end
subsystem.DifficultyConfig = config
subsystem.ActionDifficultyLevel = action_level
subsystem.RPGDifficultyLevel = rpg_level
subsystem.GetActionDifficultyLevel = function() return action_level end
subsystem.GetActionDifficultySettings = function()
    if corrupt_next_action_readback then
        corrupt_next_action_readback = false
        return action_entries[(action_level + 1) % 4]
    end
    return action_entries[action_level]
end
subsystem.GetRPGDifficultySettings = function() return rpg_entries[rpg_level] end
subsystem.SetActionDifficulty = function(_, level)
    table.insert(action_set_calls, level)
    if fail_next_action_restore and level == 1 then
        fail_next_action_restore = false
        error("synthetic Action rollback failure")
    end
    action_level = level
    subsystem.ActionDifficultyLevel = level
    if corrupt_after_action_set then
        corrupt_after_action_set = false
        corrupt_next_action_readback = true
    end
end
subsystem.SetRPGDifficulty = function(_, level)
    table.insert(rpg_set_calls, level)
    rpg_level = level
    subsystem.RPGDifficultyLevel = level
end

settings_default.Get = function() return settings end
settings.GetSettingAsDifficulty = function(_, setting, output)
    if setting == 70 then output.OutDifficulty = parameter(owner_action)
    elseif setting == 69 then output.OutDifficulty = parameter(owner_rpg)
    else return false end
    return true
end

subsystem_library.GetWorldSubsystem = function(_, context, class)
    assert_equal(context, player, "Combat subsystem context")
    assert_equal(class, subsystem_class, "Combat subsystem class identity")
    return subsystem
end


local controller = make_object(5110,"Controller")
controller.Pawn=player; player.Controller=controller
local fields, values, labels = {}, {}, {}
-- Labels are captured rather than discarded: the automatic session readback must not
-- publish anything when it fails, and that is only observable through SetLabel.
local menu={ Register=function(section) for _,item in ipairs(section.items) do fields[item.id]=item end end,
Set=function(_,key,value) values[key]=value end, SetLabel=function(_,key,value) labels[key]=value end }
local subsystem_available=true
local env=setmetatable({ExecuteInGameThread=function(fn) fn() end, StaticFindObject=function(name)
if name=="/Script/Engine.Default__SubsystemBlueprintLibrary" then return subsystem_library end
if name=="/Script/DogwoodCombat.CombatSubsystem" then return subsystem_available and subsystem_class or nil end
if name=="/Script/RebelSettings.Default__RebelGameUserSettings" then return settings_default end
end},{__index=_G})
local module=assert(loadfile(path,"t",env))(); module.Init(menu,{GetPlayer=function() return player end})
return { refresh=fields.refresh.onClick, set=function(axis,v) fields[axis].onChange(v) end,
restore=fields.restore.onClick, module=module, values=values, fields=fields, labels=labels,
breakSubsystem=function() subsystem_available=false end,
levels=function() return action_level,rpg_level end,
owner=function() return owner_action,owner_rpg end,
failRestore=function() fail_next_action_restore=true end,
corrupt=function() corrupt_after_action_set=true end,
worldChange=function() subsystem_world=alternate_world end,
configChange=function() action_entries[0].AttackAnimationSpeedMultiplier=99 end,
setCalls=function() return #rpg_set_calls+#action_set_calls end }
end
local count=0
local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..": "..tostring(err));count=count+1;print("PASS "..name) end
test("refresh gates setters and preserves settings owners",function()
local f=fixture(); assert(f.fields.rpg.enabled==false); assert(not pcall(f.set,"rpg",2));assert(f.setCalls()==0)
f.refresh();assert(f.fields.rpg.enabled);f.set("rpg",2);f.set("action",3)
local a,r=f.levels();assert(a==3 and r==2);local oa,orr=f.owner();assert(oa==1 and orr==1)
f.restore();a,r=f.levels();assert(a==1 and r==1 and not f.values.owned)
end)
test("axis-specific restore preserves other override",function()
local f=fixture();f.refresh();f.set("rpg",2);f.set("action",3);f.set("rpg",1)
local a,r=f.levels();assert(a==3 and r==1 and f.values.owned);f.restore()
end)
test("changed config prevents rollback setter",function()
local f=fixture();f.refresh();f.set("action",2);f.configChange();local before=f.setCalls()
assert(not pcall(f.restore));assert(f.setCalls()==before and f.values.owned);assert(not pcall(f.module.ResetSession))
end)
test("world mismatch refuses acquisition",function()
local f=fixture();f.refresh();f.worldChange();assert(not pcall(f.set,"rpg",2));assert(f.setCalls()==0)
end)
test("failed setter readback rolls back owned axes",function()
local f=fixture();f.refresh();f.corrupt();assert(not pcall(f.set,"action",3));local a,r=f.levels();assert(a==1 and r==1)
end)
test("failed restore ownership retained for retry",function()
local f=fixture();f.refresh();f.set("action",2);f.failRestore();assert(not pcall(f.restore));assert(f.values.owned)
f.restore();assert(not f.values.owned);f.module.ResetSession()
end)
test("session readback enables both axes without a manual refresh",function()
local f=fixture(); assert(f.fields.rpg.enabled==false and f.fields.action.enabled==false)
f.module.SessionReady()
assert(f.fields.rpg.enabled and f.fields.action.enabled,"automatic readback left the selectors disabled")
assert(f.values.rpg~=nil and f.values.action~=nil,"automatic readback published no axis values")
f.set("rpg",2);local _,r=f.levels();assert(r==2,"setters stayed gated after the automatic readback")
f.restore()
end)
test("a failed session readback publishes nothing and is left retryable",function()
local f=fixture();f.breakSubsystem()
assert(not pcall(f.module.SessionReady),"a failed automatic readback must report rather than pass silently")
assert(f.fields.rpg.enabled==false and f.fields.action.enabled==false,"a failed readback enabled the selectors")
assert(f.labels.status==nil,"a failed automatic readback overwrote the panel status")
assert(f.values.rpg==nil and f.values.action==nil,"a failed automatic readback published axis values")
end)
test("session readback does not re-read once the axes are known",function()
local f=fixture();f.refresh();f.breakSubsystem()
-- Returning early is what keeps this off the tick after the first success; a second
-- read would now fail, so completing quietly proves the guard held.
f.module.SessionReady()
assert(f.fields.rpg.enabled,"the guard cleared a readback that had already succeeded")
end)
print(count.." DifficultyControl tests passed")
