local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("carry_capacity_read_only_probe_tests")

-- Covers the deployed Scripts/CarryCapacityReadOnlyProbe.lua, including the documented
-- runtime adaptations: the setter metadata walk that is unavailable in the pinned UE4SS
-- build, the property-name accessor fallbacks, and the bFound out container that
-- GetGameplayAttributeValue requires. The reviewed original and its harness in
-- analysis/dawnwalker-uue4ss/ are not this file's subject and stay untouched.

local probe_path = assert(arg[1], "Expected the deployed carry-capacity probe source path as argument 1.")

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, received %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function assert_true(value, label)
    if value ~= true then error(label .. ": expected true", 2) end
end

local function assert_match(value, pattern, label)
    if type(value) ~= "string" or value:match(pattern) == nil then
        error(string.format("%s: value did not match %s: %s", label, pattern, tostring(value)), 2)
    end
end

local source_file = assert(io.open(probe_path, "r"))
local probe_source = source_file:read("*a")
source_file:close()

for _, forbidden_pattern in ipairs({
    ":SetAttributeValue%s*%(",
    ":BP_ApplyGameplayEffectToSelf%s*%(",
    ":RemoveActiveGameplayEffect%s*%(",
    ":TryAddItem%s*%(",
    ":RemoveItem%s*%(",
    "inventory%.WeightLimit%s*=",
    "inventory%.bWeightExceeded%s*=",
    "attribute_data%.BaseValue%s*=",
    "attribute_data%.CurrentValue%s*=",
}) do
    assert_equal(probe_source:find(forbidden_pattern), nil, "probe excludes mutation pattern " .. forbidden_pattern)
end
assert_match(probe_source, "CombatBlueprintFunctionLibrary:SetAttributeValue", "exact setter metadata path")
assert_match(probe_source, "GE_Trait_Shared_StrongBack_Level_1", "exact Strong Back descriptor source")
assert_match(probe_source, "GetDebugStringFromGameplayAttribute", "read-only descriptor pass")
assert_match(probe_source, "GetGameplayAttributeValue", "read-only attribute readback")
-- The live failure this adaptation answers was "UFunction expected 2 parameters, received
-- 1": the runtime needs the bFound container, so the call must carry both arguments.
assert_match(probe_source, "GetGameplayAttributeValue%(descriptor_record%.descriptor, out_attribute%)",
    "the getter is called with the descriptor and the bFound container")
assert_match(probe_source, "out_attribute%.bFound ~= true", "bFound is required to be exactly true")
-- The set/readback/rollback pilot must write through the descriptor this run validated,
-- so the validated struct has to come back with the result.
assert_match(probe_source, "struct = descriptor%.descriptor", "the validated descriptor is handed back")
assert_match(probe_source, "mutation_authorized%s*=%s*false", "explicit mutation denial")

DAWNWALKER_CARRY_CAPACITY_PROBE_TEST = true
local Probe = assert(dofile(probe_path))

local PropertyTypes = {
    ObjectProperty = {},
    StructProperty = {},
    FloatProperty = {},
}

local function string_value(value)
    return { ToString = function() return value end }
end

local function make_object(address, full_name, class_paths)
    local object = {
        _valid = true,
        _address = address,
        _full_name = full_name,
        _class_paths = class_paths or {},
    }
    function object:IsValid() return self._valid end
    function object:GetAddress() return self._address end
    function object:GetFullName() return self._full_name end
    function object:IsA(class_path) return self._class_paths[class_path] == true end
    return object
end

local function make_property(name, property_type, target)
    local property = {}
    function property:GetFName() return string_value(name) end
    function property:IsA(candidate) return candidate == property_type end
    function property:GetPropertyClass() return target end
    function property:GetStruct() return target end
    return property
end

local function make_environment(options)
    options = options or {}
    local calls = { debug = 0, attribute_read = 0, mutation = 0, walk = 0 }
    local ability_system_class = make_object(101, "Class /Script/GameplayAbilities.AbilitySystemComponent")
    local gameplay_attribute_struct = make_object(102, "ScriptStruct /Script/GameplayAbilities.GameplayAttribute")
    local setter = make_object(103, "Function /Script/DogwoodCombat.CombatBlueprintFunctionLibrary:SetAttributeValue")
    if options.metadata_walk_available ~= false then
        local properties = {
            make_property("AttributeOwner", PropertyTypes.ObjectProperty, ability_system_class),
            make_property("AttributeToSet",
                options.wrong_attribute_property_type and PropertyTypes.FloatProperty or PropertyTypes.StructProperty,
                gameplay_attribute_struct),
            make_property("AttributeValue", PropertyTypes.FloatProperty),
        }
        if options.missing_setter_parameter then table.remove(properties, 3) end
        function setter:ForEachProperty(callback)
            calls.walk = calls.walk + 1
            if options.walk_error then error(options.walk_error) end
            for _, property in ipairs(properties) do
                if callback(property) == true then break end
            end
        end
    end

    local attribute_owner_name = options.wrong_owner
        and "Class /Script/DogwoodStats.CharacterBaseAttributeSet"
        or "Class /Script/DogwoodStats.CharDevAttributeSet"
    local attribute_owner = make_object(104, attribute_owner_name)
    local descriptor = make_object(105, "ScriptStruct /Script/GameplayAbilities.GameplayAttribute")
    descriptor.AttributeName = string_value(options.wrong_descriptor and "Health" or "CarryWeightCapacityModifier")
    descriptor.AttributeOwner = attribute_owner
    function descriptor:GetStructAddress() return 5001 end
    calls.descriptor = descriptor

    local modifier = { Attribute = descriptor }
    local modifiers = {}
    function modifiers:ForEach(callback)
        local param = { get = function() return modifier end }
        callback(1, param)
        if options.extra_modifier then callback(2, param) end
    end
    local strong_back_cdo = make_object(106, "GE_Trait_Shared_StrongBack_Level_1_C Default__GE_Trait_Shared_StrongBack_Level_1_C")
    strong_back_cdo.Modifiers = modifiers
    local strong_back_class = make_object(107, "BlueprintGeneratedClass /Game/GE_Trait_Shared_StrongBack_Level_1_C")
    function strong_back_class:GetCDO() return strong_back_cdo end

    local debug_library = make_object(108, "AbilitySystemBlueprintLibrary /Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
    function debug_library:GetDebugStringFromGameplayAttribute(received)
        calls.debug = calls.debug + 1
        assert_equal(received, descriptor, "debug call descriptor identity")
        if options.debug_call_fails then error("synthetic debug failure") end
        return "CharDevAttributeSet.CarryWeightCapacityModifier"
    end

    local world = make_object(201, "World /Game/Test.Test:PersistentLevel", {})
    local inventory = make_object(202, "InventoryComponent /Game/Test.Player.Inventory", {
        ["/Script/DogwoodInventory.InventoryComponent"] = true,
    })
    inventory.WeightLimit = options.raw_limit or 200.0
    inventory.bWeightExceeded = options.weight_exceeded or false
    function inventory:GetWeightLimit() return options.effective_limit or 230.0 end
    function inventory:GetCurrentWeight() return options.current_weight or 3.82 end
    function inventory:CanExceedWeightLimit() return true end

    local ability_system = make_object(203, "DawnwalkerAbilitySystemComponent /Game/Test.Player.ASC", {
        ["/Script/Dawnwalker.DawnwalkerAbilitySystemComponent"] = true,
    })
    function ability_system:GetGameplayAttributeValue(...)
        calls.attribute_read = calls.attribute_read + 1
        local argc = select("#", ...)
        local received, output = ...
        -- The pinned runtime refuses a call that omits the out parameter with exactly this
        -- message; reproducing it here means a regression reads as the live failure did.
        if argc ~= 2 then
            error(string.format("UFunction expected 2 parameters, received %d", argc))
        end
        assert_equal(type(output), "table", "the bFound container must be a table")
        assert_equal(received, descriptor, "ASC read descriptor identity")
        if options.attribute_call_fails then error("synthetic attribute failure") end
        if not options.found_missing then output.bFound = options.found_false ~= true end
        return options.attribute_current or 30.0
    end
    function ability_system:SetAttributeValue()
        calls.mutation = calls.mutation + 1
        error("the read-only probe invoked a mutation")
    end

    local char_dev = make_object(204, "CharDevAttributeSet /Game/Test.Player.CharDev", {
        ["/Script/DogwoodStats.CharDevAttributeSet"] = true,
    })
    char_dev.CarryWeightCapacityModifier = {
        BaseValue = options.attribute_base or 0.0,
        CurrentValue = options.attribute_current or 30.0,
    }

    local player = make_object(205, "DawnwalkerPlayerCharacter /Game/Test.Player", {
        ["/Script/Dawnwalker.DawnwalkerPlayerCharacter"] = true,
    })
    player.AbilitySystemComponent = ability_system
    player.CharDevAttributeSet = char_dev
    function player:GetWorld() return world end
    function player:GetInventoryComponent() return inventory end

    local objects = {
        ["/Script/DogwoodCombat.CombatBlueprintFunctionLibrary:SetAttributeValue"] = setter,
        ["/Game/_Dawnwalker/Player/CharacterDevelopment/Traits/GameplayEffects/GE_Trait_Shared_StrongBack_Level_1.GE_Trait_Shared_StrongBack_Level_1_C"] = strong_back_class,
        ["/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"] = debug_library,
    }
    local deps = {
        static_find_object = function(path) return objects[path] end,
        get_player = function() return player end,
        property_types = PropertyTypes,
    }
    return deps, calls
end

-- The walk the reviewed probe depends on is missing in the pinned UE4SS build, so the
-- deployed probe must still complete and must say which contract it used.
local live_deps, live_calls = make_environment({ metadata_walk_available = false })
local live_result = Probe.run(live_deps)
assert_true(live_result.ok, "probe completes when the metadata walk is unavailable")
assert_equal(live_result.stage, "read-only-complete", "completion stage without the walk")
assert_equal(live_result.mutation_authorized, false, "read-only probe never authorizes mutation")
assert_equal(live_result.setter_signature.metadata_walk, "unavailable", "the weaker contract is reported")
assert_equal(live_result.setter_signature.parameter_count, 3, "dump-declared setter parameter count")
assert_match(live_result.setter_signature.metadata_note, "captured UHT dump", "the fallback source is named")

local deps, calls = make_environment()
local result = Probe.run(deps)
assert_true(result.ok, "valid feasibility probe")
assert_equal(result.stage, "read-only-complete", "valid completion stage")
assert_equal(result.mutation_authorized, false, "read-only probe never authorizes mutation")
assert_equal(result.setter_signature.metadata_walk, "walked", "walked contract is reported")
assert_equal(result.setter_signature.parameter_count, 3, "exact setter parameter count")
assert_equal(result.descriptor.attribute_name, "CarryWeightCapacityModifier", "exact descriptor name")
assert_match(result.descriptor.attribute_owner, "/Script/DogwoodStats%.CharDevAttributeSet", "exact descriptor owner")
assert_equal(result.snapshot.attribute_base_value, 0.0, "baseline attribute base")
assert_equal(result.snapshot.attribute_current_value, 30.0, "baseline attribute current")
assert_equal(result.snapshot.effective_weight_limit, 230.0, "effective weight limit")
assert_equal(result.snapshot.can_exceed_weight_limit, true, "permission telemetry remains read-only")
assert_equal(result.struct_pass.attribute_value, 30.0, "struct pass attribute readback")
assert_equal(result.struct_pass.found, true, "explicit bFound flag from the out container")
assert_equal(result.descriptor.struct, calls.descriptor, "the validated descriptor is handed back unchanged")
assert_equal(calls.debug, 1, "one read-only debug descriptor call")
assert_equal(calls.attribute_read, 1, "one read-only ASC descriptor call")
assert_equal(calls.walk, 1, "one metadata walk")
assert_equal(calls.mutation, 0, "zero mutation calls")

-- A walk that exists but fails for any reason other than a missing accessor is a hard
-- failure: it must not degrade into the dump fallback.
local broken_walk = Probe.run((make_environment({ walk_error = "synthetic walk failure" })))
assert_equal(broken_walk.ok, false, "a broken metadata walk is rejected")
assert_equal(broken_walk.stage, "setter-signature", "broken metadata walk stage")

local missing_accessor = Probe.run((make_environment({ walk_error = "attempt to call a nil value" })))
assert_true(missing_accessor.ok, "a walk that is missing an accessor degrades to the dump contract")
assert_equal(missing_accessor.setter_signature.metadata_walk, "unavailable", "missing accessor is reported")

local bad_descriptor = Probe.run((make_environment({ wrong_descriptor = true })))
assert_equal(bad_descriptor.ok, false, "wrong descriptor rejected")
assert_equal(bad_descriptor.stage, "descriptor", "wrong descriptor stage")
assert_equal(bad_descriptor.mutation_authorized, false, "wrong descriptor stays fail closed")

local bad_owner = Probe.run((make_environment({ wrong_owner = true })))
assert_equal(bad_owner.ok, false, "wrong owner rejected")
assert_equal(bad_owner.stage, "descriptor", "wrong owner stage")

local bad_signature = Probe.run((make_environment({ wrong_attribute_property_type = true })))
assert_equal(bad_signature.ok, false, "wrong setter signature rejected")
assert_equal(bad_signature.stage, "setter-signature", "wrong setter signature stage")

local missing_parameter = Probe.run((make_environment({ missing_setter_parameter = true })))
assert_equal(missing_parameter.ok, false, "drifted setter parameter count rejected")
assert_equal(missing_parameter.stage, "setter-signature", "drifted setter parameter count stage")

local extra_modifier = Probe.run((make_environment({ extra_modifier = true })))
assert_equal(extra_modifier.ok, false, "descriptor source drift rejected")
assert_equal(extra_modifier.stage, "descriptor", "descriptor source drift stage")

local stale_snapshot = Probe.run((make_environment({ effective_limit = 999.0 })))
assert_equal(stale_snapshot.ok, false, "inconsistent effective limit rejected")
assert_equal(stale_snapshot.stage, "snapshot", "inconsistent snapshot stage")

local stale_exceeded = Probe.run((make_environment({ weight_exceeded = true })))
assert_equal(stale_exceeded.ok, false, "inconsistent weight flag rejected")
assert_equal(stale_exceeded.stage, "snapshot", "inconsistent weight flag stage")

-- Regression guard for the zero-limit branch. The reviewed line was
-- "effective_limit == 0 and false or current_weight > effective_limit", which Lua reads as
-- "(A and false) or B": with an unlimited inventory the false branch is dropped and a load
-- above zero was judged unsynchronized, stopping the whole check. The engine's rule is
-- false for a limit of exactly zero, so this exact combination has to pass.
local unlimited, unlimited_calls = make_environment({
    raw_limit = 0.0,
    effective_limit = 0.0,
    attribute_base = 0.0,
    attribute_current = 0.0,
    current_weight = 3.82,
})
local unlimited_result = Probe.run(unlimited)
assert_true(unlimited_result.ok, "an unlimited inventory is accepted")
assert_equal(unlimited_result.stage, "read-only-complete", "unlimited inventory completion stage")
assert_equal(unlimited_result.snapshot.effective_weight_limit, 0.0, "an unlimited effective limit is zero")
assert_equal(unlimited_result.snapshot.weight_exceeded, false, "an unlimited inventory is not over-limit")
assert_equal(unlimited_calls.mutation, 0, "the unlimited case still writes nothing")
-- The comparison branch must still work: a positive limit with a load above it is a
-- legitimate snapshot when the engine's flag agrees.
local over_limit = Probe.run((make_environment({
    raw_limit = 200.0,
    effective_limit = 230.0,
    attribute_base = 0.0,
    attribute_current = 30.0,
    current_weight = 250.0,
    weight_exceeded = true,
})))
assert_true(over_limit.ok, "a legitimately over-limit snapshot is accepted")
assert_equal(over_limit.snapshot.weight_exceeded, true, "the positive-limit comparison still reports over-limit")

local failed_pass, failed_calls = make_environment({ attribute_call_fails = true })
local failed_result = Probe.run(failed_pass)
assert_equal(failed_result.ok, false, "struct pass exception rejected")
assert_equal(failed_result.stage, "struct-pass", "struct pass exception stage")
assert_equal(failed_result.mutation_authorized, false, "struct pass exception stays fail closed")
assert_equal(failed_calls.mutation, 0, "struct pass failure makes no mutation")

local found_false = Probe.run((make_environment({ found_false = true })))
assert_equal(found_false.ok, false, "explicit bFound = false rejected")
assert_equal(found_false.stage, "struct-pass", "explicit bFound = false stage")
assert_match(tostring(found_false.message), "bFound = true", "explicit bFound = false reason")

-- The regression this adaptation fixes: a getter call that never received the bFound
-- container. It must fail at the struct pass, not be reported as a read-only success.
local found_missing = Probe.run((make_environment({ found_missing = true })))
assert_equal(found_missing.ok, false, "missing bFound value rejected")
assert_equal(found_missing.stage, "struct-pass", "missing bFound value stage")
assert_match(tostring(found_missing.message), "bFound = true", "missing bFound value reason")

local bad_debug = Probe.run((make_environment({ debug_call_fails = true })))
assert_equal(bad_debug.ok, false, "debug pass exception rejected")
assert_equal(bad_debug.stage, "struct-pass", "debug pass exception stage")

assert_equal(calls.mutation, 0, "every completed case is still mutation-free")

print("Carry-capacity read-only probe (deployed) harness passed.")
