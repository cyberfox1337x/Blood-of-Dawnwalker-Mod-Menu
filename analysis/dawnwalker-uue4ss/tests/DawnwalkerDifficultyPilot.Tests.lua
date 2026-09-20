local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_difficulty_pilot_tests")

local bridge_source = assert(arg[1], "Expected the bridge source path as argument 1.")
local bridge_root = assert(os.getenv("TEMP"), "TEMP must be set for the bridge harness.") .. "/DawnwalkerModMenuBridge"

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, received %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function assert_match(actual, pattern, label)
    if not tostring(actual):match(pattern) then
        error(string.format("%s did not match %s", label, pattern), 2)
    end
end

local function read_file(path)
    local file = assert(io.open(path, "r"), "Unable to read " .. path)
    local contents = file:read("*a")
    file:close()
    return contents
end

local function read_fields(path)
    local fields = {}
    for line in read_file(path):gmatch("[^\r\n]+") do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key then fields[key] = value end
    end
    return fields
end

local function write_command(path, ready, request_id, capability, value)
    local command_file = assert(io.open(path, "w"), "Unable to write command file.")
    command_file:write(table.concat({
        "protocol=1",
        "boot_id=" .. ready.boot_id,
        "request_id=" .. request_id,
        "capability=" .. capability,
        "value=" .. value,
        "",
    }, "\n"))
    command_file:close()
end

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

local source_text = read_file(bridge_source)
assert_match(source_text, '"combat:rpg%-difficulty"', "RPG difficulty capability")
assert_match(source_text, '"combat:action%-difficulty"', "Action difficulty capability")
assert_match(source_text, "/Script/DogwoodCombat%.CombatSubsystem", "Combat subsystem class")
assert_match(source_text, "subsystem:GetWorld%(%)", "same-world gate")
assert_match(source_text, "settings_default:Get%(%)", "live settings singleton resolver")
assert_match(source_text, "settings:GetSettingAsDifficulty%(setting, output%)", "owner setting readback")
assert_match(source_text, "map:Contains%(level%)", "config membership preflight")
assert_match(source_text, "for key_parameter, value_parameter in pairs%(parry_windows%)", "nested local-map ABI")
assert_match(source_text, "for_each%(parry_windows, function", "captured UE4SS ForEach callable with exact receiver")
local length_lookup = assert(source_text:find("return #parry_windows", 1, true), "missing bounded map length lookup")
local method_lookup = assert(source_text:find("return parry_windows.ForEach", 1, true), "missing protected ForEach lookup")
local method_call = assert(source_text:find("for_each(parry_windows", 1, true), "missing captured ForEach invocation")
assert_equal(length_lookup < method_lookup and method_lookup < method_call, true, "length precedes the immediate ForEach lookup and call")
assert_equal(source_text:find("parry_windows:ForEach", 1, true), nil, "ForEach is never looked up twice")
assert_match(
    source_text,
    "for_each%(parry_windows, function%(key_parameter, value_parameter%)%s+capture_entry%(key_parameter, value_parameter%)%s+end%)",
    "TMap callback continues with an implicit nil return"
)
assert_match(source_text, "record%.subsystem:SetRPGDifficulty%(record%.baseline_rpg%)", "RPG rollback setter")
assert_match(source_text, "record%.subsystem:SetActionDifficulty%(record%.baseline_action%)", "Action rollback setter")
assert_match(source_text, "local MAX_TEARDOWN_OPERATIONS = 8", "bounded teardown operation count")
assert_equal(source_text:find("PreviewDifficultyPreset", 1, true), nil, "broad preset is never called")
assert_equal(source_text:find("ConfirmSetting", 1, true), nil, "game settings are never confirmed")

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

package.preload["UEHelpers"] = function()
    return { GetPlayer = function() return player end }
end

local clock = 1900003000
os.time = function()
    clock = clock + 1
    return clock
end
math.random = function() return 246810 end

ModRef = {}
EngineTickAvailable = true
EGameThreadMethod = { EngineTick = 1 }
ExecuteInGameThread = function(callback, method)
    assert_equal(method, EGameThreadMethod.EngineTick, "game-thread method")
    callback()
end
IsInGameThread = function() return true end
StaticFindObject = function(path)
    if path == "/Script/Engine.Default__SubsystemBlueprintLibrary" then return subsystem_library end
    if path == "/Script/DogwoodCombat.CombatSubsystem" then return subsystem_class end
    if path == "/Script/RebelSettings.Default__RebelGameUserSettings" then return settings_default end
    return nil
end

local poll_callback = nil
LoopAsync = function(milliseconds, callback)
    assert_equal(milliseconds, 150, "bridge poll interval")
    poll_callback = callback
end

assert(loadfile(bridge_source))()
assert_equal(type(poll_callback), "function", "bridge poll callback")

local ready_path = bridge_root .. "/ready.txt"
local command_path = bridge_root .. "/command.txt"
local response_path = bridge_root .. "/response.txt"
local ready = read_fields(ready_path)
assert_equal(ready.version, "0.3.21-pilot", "bridge version")
assert_match(ready.capabilities, "combat:rpg%-difficulty", "advertised RPG difficulty")
assert_match(ready.capabilities, "combat:action%-difficulty", "advertised Action difficulty")

local sequence = 0
local function execute(capability, value)
    sequence = sequence + 1
    write_command(command_path, ready, "difficulty-harness-" .. tostring(sequence), capability, value)
    poll_callback()
    return read_fields(response_path)
end

local function refreshed_ready()
    poll_callback()
    return read_fields(ready_path)
end

local rpg_query = execute("combat:rpg-difficulty", "")
assert_equal(rpg_query.accepted, "1", "RPG query accepted")
assert_equal(rpg_query.readback, "1", "RPG query readback")
local action_query = execute("combat:action-difficulty", "")
assert_equal(action_query.accepted, "1", "Action query accepted")
assert_equal(action_query.readback, "1", "Action query readback")

local setters_before_invalid = #rpg_set_calls + #action_set_calls
for index, invalid in ipairs({ "4", "-1", "1.5", "MAX", "unknown" }) do
    local response = execute(index % 2 == 0 and "combat:action-difficulty" or "combat:rpg-difficulty", invalid)
    assert_equal(response.accepted, "0", "invalid difficulty rejected")
end
assert_equal(#rpg_set_calls + #action_set_calls, setters_before_invalid, "invalid values never call setters")

local rpg_changed = execute("combat:rpg-difficulty", "Immersive")
assert_equal(rpg_changed.accepted, "1", "RPG change accepted")
assert_equal(rpg_changed.readback, "2", "RPG change exact readback")
assert_equal(rpg_level, 2, "RPG setter applied")
assert_equal(refreshed_ready().active, "combat:rpg-difficulty", "RPG active ownership")

local action_changed = execute("combat:action-difficulty", "3")
assert_equal(action_changed.accepted, "1", "Action change accepted")
assert_equal(action_changed.readback, "3", "Action change exact readback")
assert_equal(action_level, 3, "Action setter applied")
assert_match(refreshed_ready().active, "combat:action%-difficulty", "Action active ownership")
assert_match(refreshed_ready().active, "combat:rpg%-difficulty", "RPG remains active")
assert_equal(owner_action, 1, "Action settings owner untouched")
assert_equal(owner_rpg, 1, "RPG settings owner untouched")

assert_equal(execute("combat:rpg-difficulty", "Normal").accepted, "1", "RPG baseline restore accepted")
assert_equal(rpg_level, 1, "RPG baseline restored")
assert_equal(refreshed_ready().active, "combat:action-difficulty", "only Action remains active")
assert_equal(execute("combat:action-difficulty", "Normal").accepted, "1", "Action baseline restore accepted")
assert_equal(action_level, 1, "Action baseline restored")
assert_equal(refreshed_ready().active, "", "two-axis ownership released")

corrupt_after_action_set = true
local corrupt_readback = execute("combat:action-difficulty", "Immersive")
assert_equal(corrupt_readback.accepted, "0", "mismatched settings fingerprint rejected")
assert_match(corrupt_readback.message, "rollback=verified", "fingerprint mismatch rollback")
assert_equal(action_level, 1, "fingerprint mismatch restored exact baseline")

assert_equal(execute("combat:rpg-difficulty", "2").accepted, "1", "owner test override accepted")
owner_rpg = 3
rpg_level = 3
subsystem.RPGDifficultyLevel = 3
local action_calls_before_owner_reclaim = #action_set_calls
local owner_reclaimed = execute("combat:action-difficulty", "2")
assert_equal(owner_reclaimed.accepted, "0", "owner change blocks new mutation")
assert_equal(#action_set_calls, action_calls_before_owner_reclaim, "owner change does not call unrelated setter")
assert_equal(refreshed_ready().active, "", "owner reclaim releases bridge ownership")
owner_rpg = 1
rpg_level = 1
subsystem.RPGDifficultyLevel = 1

assert_equal(execute("combat:rpg-difficulty", "2").accepted, "1", "teardown retry RPG override accepted")
assert_equal(execute("combat:action-difficulty", "2").accepted, "1", "teardown retry Action override accepted")
fail_next_action_restore = true
ModRef.OnUnload()
assert_equal(rpg_level, 1, "first teardown restores RPG even when Action restore fails")
assert_equal(action_level, 2, "failed Action rollback retains its applied value")
ModRef.OnUnload()
assert_equal(action_level, 1, "second teardown retries and restores retained Action baseline")

player.GetWorld = function() return world end
subsystem_world = world
assert_equal(execute("combat:rpg-difficulty", "2").accepted, "1", "world identity test override accepted")
subsystem_world = alternate_world
local calls_before_world_refusal = #rpg_set_calls
ModRef.OnUnload()
assert_equal(#rpg_set_calls, calls_before_world_refusal, "world drift prevents stale rollback setter")
assert_equal(rpg_level, 2, "world drift retains unresolved value")
subsystem_world = world
ModRef.OnUnload()
assert_equal(rpg_level, 1, "same-world retry restores retained RPG baseline")

print("Dawnwalker two-axis difficulty pilot harness passed.")
