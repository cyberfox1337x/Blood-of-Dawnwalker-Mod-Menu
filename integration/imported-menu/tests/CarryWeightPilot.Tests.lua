local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("carry_weight_pilot_tests")

-- Covers Scripts/CarryWeightPilot.lua, the set/readback/rollback pilot the carry-capacity
-- feasibility gate requires after the read-only contract.
--
-- The pilot used to try several argument arrangements in turn, on the assumption that a
-- wrong arrangement could not reach native code. That assumption was wrong and it crashed
-- the game on 2026-09-17. These cases therefore also pin that exactly one reviewed
-- arrangement exists and that no candidate machinery comes back.

local pilot_path = assert(arg[1], "Expected the carry-weight pilot source path as argument 1.")

local SETTER_CDO_PATH = "/Script/DogwoodCombat.Default__CombatBlueprintFunctionLibrary"
local SETTER_CLASS_NAME = "Class /Script/DogwoodCombat.CombatBlueprintFunctionLibrary"
local SETTER_FUNCTION_PATH = "/Script/DogwoodCombat.CombatBlueprintFunctionLibrary:SetAttributeValue"
local BINDING_LIBRARY_PATH = "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"
local ATTRIBUTE_NAME = "CarryWeightCapacityModifier"

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

local source_file = assert(io.open(pilot_path, "r"))
local pilot_source = source_file:read("*a")
source_file:close()

-- The feasibility note forbids every one of these, so a source check fails the suite if one
-- appears even in a form no test case exercises.
for _, forbidden_pattern in ipairs({
    "%.BaseValue%s*=",
    "%.CurrentValue%s*=",
    "%.WeightLimit%s*=",
    "%.bWeightExceeded%s*=",
    ":BP_ApplyGameplayEffectToSelf%s*%(",
    ":RemoveActiveGameplayEffect%s*%(",
}) do
    assert_equal(pilot_source:find(forbidden_pattern), nil, "pilot excludes direct write " .. forbidden_pattern)
end
assert_match(pilot_source, "Default__CombatBlueprintFunctionLibrary", "the documented CDO route is used")
assert_match(pilot_source, "SetAttributeValue", "the documented setter is the only writer")
assert_match(pilot_source, "GetGameplayAttributeValue%(descriptor, out%)", "the proven getter takes the out container")
assert_match(pilot_source, "Default__AbilitySystemBlueprintLibrary", "the read-only record uses the library CDO")
assert_match(pilot_source, "GetFloatAttributeBaseFromAbilitySystemComponent", "the read-only record reads the base value")
assert_match(pilot_source, "reviewed_arguments", "one reviewed arrangement builds the write")
assert_match(pilot_source, "REVIEWED_WRITE_SHAPE", "the single write shape is named")
assert_match(pilot_source, "signature%.metadata_walk ~= \"walked\"", "the write is gated on a walked parameter contract")
assert_match(pilot_source, "PILOT_TARGET_BASE_VALUE%s*=%s*%d+%.0", "the reviewed high finite target is a literal")
assert_match(pilot_source, "call_ufunction_from_lua", "the crash note names the native call site")
assert_match(pilot_source, "UECC%-Windows%-BFFF9348408C7188BB738FB818A1E8CC", "the crash note names the dump")
-- Guards against the regression that crashed the game: a list of candidate arrangements, or
-- an attribute argument built as a Lua table instead of the validated descriptor.
assert_equal(pilot_source:find("ipairs%(WRITE_SHAPES%)"), nil, "no candidate arrangement list may return")
assert_equal(pilot_source:find("descriptor_fields"), nil, "no table-shaped attribute argument may return")
assert_equal(pilot_source:find("refused_shapes"), nil, "no multi-shape reporting may return")

local Pilot = assert(dofile(pilot_path))

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

-- A live-shaped environment. The inventory derives its limit from the raw limit plus the
-- attribute's CurrentValue, and the setter only accepts the reviewed arrangement: the ability
-- system, the validated descriptor itself, and a number.
local function make_environment(options)
    options = options or {}
    local calls = { attempts = {}, applied = {}, binding = 0, getter = 0 }

    local raw_limit = options.raw_limit or 200.0
    local current_weight = options.current_weight or 3.82
    local attribute = {
        BaseValue = options.base_value or 0.0,
        CurrentValue = options.current_value or 0.0,
    }

    local char_dev = make_object(9004, "CharDevAttributeSet /Game/Test.Player.CharDev", {
        ["/Script/DogwoodStats.CharDevAttributeSet"] = true,
    })
    char_dev[ATTRIBUTE_NAME] = attribute

    local inventory = make_object(9002, "InventoryComponent /Game/Test.Player.Inventory", {
        ["/Script/DogwoodInventory.InventoryComponent"] = true,
    })
    inventory.WeightLimit = raw_limit
    inventory.bWeightExceeded = false
    local function effective_limit()
        return raw_limit <= 0 and raw_limit or (raw_limit + attribute.CurrentValue)
    end
    function inventory:GetWeightLimit() return effective_limit() end
    function inventory:GetCurrentWeight() return current_weight end
    function inventory:CanExceedWeightLimit() return true end

    local ability_system = make_object(9003, "DawnwalkerAbilitySystemComponent /Game/Test.Player.ASC", {
        ["/Script/Dawnwalker.DawnwalkerAbilitySystemComponent"] = true,
    })
    function ability_system:GetGameplayAttributeValue(descriptor, out)
        calls.getter = calls.getter + 1
        assert_equal(descriptor, calls.descriptor, "ASC getter descriptor identity")
        assert_equal(type(out), "table", "the ASC getter needs the bFound container")
        if options.getter_fails then error("UFunction expected 2 parameters, received 1") end
        local value = attribute.CurrentValue + (options.getter_offset or 0)
        out.bFound = options.getter_found_false ~= true
        return value
    end
    function ability_system:SetAttributeValue() error("the pilot wrote through the ASC instead of the library") end

    local player = make_object(9001, "DawnwalkerPlayerCharacter /Game/Test.Player", {
        ["/Script/Dawnwalker.DawnwalkerPlayerCharacter"] = true,
    })
    player.AbilitySystemComponent = ability_system
    player.CharDevAttributeSet = char_dev
    function player:GetInventoryComponent()
        if options.inventory_missing then return nil end
        return inventory
    end

    local descriptor_owner = make_object(9100, "Class /Script/DogwoodStats.CharDevAttributeSet")
    local descriptor = make_object(9101, "ScriptStruct /Script/GameplayAbilities.GameplayAttribute")
    descriptor.AttributeName = string_value(ATTRIBUTE_NAME)
    descriptor.AttributeOwner = descriptor_owner
    function descriptor:GetStructAddress() return options.descriptor_address or 5001 end
    calls.descriptor = descriptor

    -- The read-only record: the library getter takes the attribute by value, so the validated
    -- descriptor goes in as it is. A table argument is refused the way the runtime refuses an
    -- out parameter with no table.
    local library = make_object(9300, "AbilitySystemBlueprintLibrary " .. BINDING_LIBRARY_PATH)
    function library:GetFloatAttributeBaseFromAbilitySystemComponent(owner, argument, out)
        calls.binding = calls.binding + 1
        assert_equal(owner, ability_system, "library getter ASC identity")
        assert_equal(type(out), "table", "the library getter needs its found container")
        if argument ~= descriptor then
            error("the library getter was given something other than the validated descriptor")
        end
        if options.binding_reports_failure then
            out.bSuccessfullyFoundAttribute = false
            return 0.0
        end
        if options.binding_postcondition_failure and #calls.applied > 0 then
            out.bSuccessfullyFoundAttribute = true
            return attribute.BaseValue + 1.0
        end
        out.bSuccessfullyFoundAttribute = true
        return options.binding_value or attribute.BaseValue
    end

    local setter_class = make_object(9200, SETTER_CLASS_NAME, { ["/Script/CoreUObject.Class"] = true })
    function setter_class:GetFullName()
        return options.setter_class_name or SETTER_CLASS_NAME
    end
    local cdo = make_object(9201, "CombatBlueprintFunctionLibrary /Script/DogwoodCombat.Default__CombatBlueprintFunctionLibrary")
    function cdo:GetClass() return setter_class end
    function cdo:SetAttributeValue(...)
        local argc = select("#", ...)
        local owner, reference, value = ...
        calls.attempts[#calls.attempts + 1] = { argc = argc, reference = reference, value = value }
        assert_equal(argc, 3, "the reviewed arrangement passes exactly three arguments")
        assert_equal(owner, ability_system, "setter ASC identity")
        assert_equal(reference, descriptor, "the write must pass the validated descriptor itself, not a table")
        assert_equal(type(value), "number", "the write passes a number")
        if options.setter_refuses then
            if options.refused_call_mutates and #calls.attempts == 1 then
                attribute.BaseValue = value
                attribute.CurrentValue = value
                error("synthetic refusal after mutating the attribute")
            end
            error("Tried storing reference to a Lua table for an 'Out' parameter when calling a UFunction but no table was on the stack")
        end
        calls.applied[#calls.applied + 1] = value
        if options.setter_ignores_rollback and #calls.applied == 2 then return end
        local applied = options.setter_doubles and (value * 2) or value
        attribute.CurrentValue = attribute.CurrentValue - attribute.BaseValue + applied
        attribute.BaseValue = applied
        inventory.bWeightExceeded = effective_limit() == 0 and false or (current_weight > effective_limit())
    end

    local setter_function = make_object(9202, "Function " .. SETTER_FUNCTION_PATH)

    local contract = options.contract
    if contract == nil then
        local contract_descriptor = { struct_address = options.contract_struct_address or tostring(descriptor:GetStructAddress()) }
        if not options.contract_struct_missing then contract_descriptor.struct = descriptor end
        contract = {
            ok = true,
            stage = "read-only-complete",
            message = "The exact descriptor passed two read-only UFunction calls.",
            descriptor = contract_descriptor,
            snapshot = {
                player_address = tostring(player:GetAddress()),
                inventory_address = tostring(inventory:GetAddress()),
                asc_address = tostring(ability_system:GetAddress()),
                char_dev_address = tostring(char_dev:GetAddress()),
            },
        }
        -- The write gate: only a contract that walked the live parameter kinds unlocks the
        -- setter. `contract_signature = false` models a contract without the block at all.
        if options.contract_signature ~= false then
            contract.setter_signature = {
                function_path = SETTER_FUNCTION_PATH,
                parameter_count = 3,
                metadata_walk = options.contract_metadata_walk or "walked",
            }
        end
    end

    local objects = {
        [SETTER_CDO_PATH] = cdo,
        [SETTER_FUNCTION_PATH] = setter_function,
        [BINDING_LIBRARY_PATH] = library,
    }
    if options.cdo_missing then objects[SETTER_CDO_PATH] = nil end
    if options.setter_missing then objects[SETTER_FUNCTION_PATH] = nil end
    if options.binding_library_missing then objects[BINDING_LIBRARY_PATH] = nil end
    local deps = {
        probe = { run = function() return contract end },
        static_find_object = function(path) return objects[path] end,
        get_player = function()
            if options.player_replaced then
                return make_object(9999, "DawnwalkerPlayerCharacter /Game/Test.OtherPlayer", {
                    ["/Script/Dawnwalker.DawnwalkerPlayerCharacter"] = true,
                })
            end
            return player
        end,
        property_types = {},
    }
    return deps, calls, attribute, inventory
end

local deps, calls, attribute, inventory = make_environment()
local result = Pilot.Roundtrip(deps)
assert_true(result.ok, "the pilot round trip passes")
assert_equal(result.stage, "rollback-complete", "rollback completion stage")
assert_equal(result.ownership, "none", "a completed round trip owns nothing")
assert_equal(result.mutation_authorized, true, "the pilot is the authorized writer")
assert_equal(result.target_base_value, 1000.0, "the reviewed target base value")
assert_equal(result.binding, "struct-value", "the read-only record is reported")
assert_equal(result.write_shape, "reviewed-struct-argument", "the single reviewed arrangement is reported")
assert_equal(#calls.applied, 2, "exactly one write and one rollback")
assert_equal(calls.applied[1], 1000.0, "the write uses the reviewed target")
assert_equal(calls.applied[2], 0.0, "the rollback uses the captured base value")
assert_equal(#calls.attempts, 2, "each accepted call was made once")
assert_equal(calls.attempts[1].reference, calls.descriptor, "the write passes the validated descriptor")
assert_equal(calls.binding, 2, "the attribute was read through the library before and after the write")
assert_equal(calls.getter, 3, "the proven getter confirmed the baseline, the applied state and the restoration")
assert_equal(result.applied.attribute_base_value, 1000.0, "readback base value after the write")
assert_equal(result.applied.attribute_current_value, 1000.0, "readback current value after the write")
assert_equal(result.applied.effective_weight_limit, 1200.0, "the derived limit moved by exactly the target")
assert_equal(result.applied.weight_exceeded, false, "the derived flag followed the limit")
assert_equal(result.restored.attribute_base_value, 0.0, "the captured base value came back")
assert_equal(result.restored.attribute_current_value, 0.0, "the captured current value came back")
assert_equal(result.restored.effective_weight_limit, 200.0, "the original limit came back")
assert_equal(result.restored.weight_exceeded, false, "the original derived flag came back")
assert_equal(attribute.BaseValue, 0.0, "the live attribute ends at the baseline")
assert_equal(inventory:GetWeightLimit(), 200.0, "the live limit ends at the baseline")
assert_match(result.message, "Pilot passed", "the success message names the pilot")
assert_match(result.message, "reviewed%-struct%-argument", "the success message names the arrangement")

-- The live behaviour of this build: the reviewed arrangement is refused before the native
-- call, so nothing is written and the run ends there. No second arrangement is attempted.
local refused_deps, refused_calls, refused_attribute = make_environment({ setter_refuses = true })
local refused = Pilot.Roundtrip(refused_deps)
assert_equal(refused.ok, false, "a refused arrangement fails the pilot")
assert_equal(refused.stage, "setter-call", "refused arrangement stage")
assert_match(refused.message, "the runtime refused the reviewed call shape", "the refusal names the reviewed shape")
assert_match(refused.message, "nothing was written", "the refusal is reported as no write")
assert_equal(refused.ownership, "none", "a refusal owns nothing")
assert_equal(#refused_calls.attempts, 1, "exactly one arrangement is ever attempted")
assert_equal(#refused_calls.applied, 0, "nothing was applied")
assert_equal(refused_attribute.BaseValue, 0.0, "a refusal leaves the attribute alone")

-- A refusal that mutated the attribute anyway, where the same arrangement is then refused
-- again: the pilot cannot prove the baseline and says so as pending ownership rather than
-- reporting a plain refusal or a pass. (The recoverable variant is the postcondition case
-- below, where the arrangement is accepted and the baseline really does come back.)
local mutating_deps, mutating_calls, mutating_attribute = make_environment({
    setter_refuses = true, refused_call_mutates = true,
})
local mutating = Pilot.Roundtrip(mutating_deps)
assert_equal(mutating.ok, false, "a refusal that changed the attribute fails the pilot")
assert_equal(mutating.stage, "setter-call", "mutating refusal stage")
assert_match(mutating.message, "changed the attribute anyway", "the unexpected change is reported")
assert_match(mutating.message, "could not be restored", "an unprovable baseline is reported, not claimed")
assert_equal(mutating.ownership, "pending", "an unprovable baseline is reported as pending ownership")
assert_equal(#mutating_calls.attempts, 2, "the recovery attempt was made once")
assert_equal(mutating_attribute.BaseValue, 1000.0, "a pending refusal leaves the changed value visible")

-- The write must not be attempted when the attribute cannot even be read through the
-- library, and the read-only record never varies its argument either.
local no_library_deps, no_library_calls = make_environment({ binding_library_missing = true })
assert_equal(Pilot.Roundtrip(no_library_deps).stage, "binding", "missing library stage")
assert_equal(#no_library_calls.attempts, 0, "a missing library writes nothing")

local not_found = Pilot.Roundtrip((make_environment({ binding_reports_failure = true })))
assert_equal(not_found.ok, false, "a library read without the found flag refuses the pilot")
assert_equal(not_found.stage, "binding", "missing found flag stage")

local wrong_base = Pilot.Roundtrip((make_environment({ binding_value = 99.0 })))
assert_equal(wrong_base.ok, false, "a library read that disagrees with the base value refuses the pilot")
assert_equal(wrong_base.stage, "binding", "disagreeing library read stage")

-- The read-only contract is the gate: a blocked contract must write nothing at all.
local blocked_probe_deps, blocked_probe_calls = make_environment({
    contract = { ok = false, stage = "struct-pass", message = "UE4SS rejected the descriptor" },
})
local blocked_probe = Pilot.Roundtrip(blocked_probe_deps)
assert_equal(blocked_probe.ok, false, "a blocked contract refuses the pilot")
assert_equal(blocked_probe.stage, "read-only-contract", "blocked contract stage")
assert_match(blocked_probe.message, "struct%-pass", "the blocked reason names the read-only stage")
assert_equal(#blocked_probe_calls.attempts, 0, "a blocked contract writes nothing")

-- The gate that exists because of the 2026-09-17 crash: on a build where the read-only
-- check cannot walk the setter's live parameter kinds, the setter is never called at all -
-- not attempted, not varied, not hoped for.
local unwalked_deps, unwalked_calls = make_environment({ contract_metadata_walk = "unavailable" })
local unwalked = Pilot.Roundtrip(unwalked_deps)
assert_equal(unwalked.ok, false, "a contract that could not read the parameter kinds refuses the pilot")
assert_equal(unwalked.stage, "signature-contract", "unread parameter contract stage")
assert_match(unwalked.message, "could not read the setter's parameter kinds", "the unread parameter contract is named")
assert_match(unwalked.message, "metadata_walk = unavailable", "the unread parameter contract reports its own evidence")
assert_match(unwalked.message, "no write was attempted", "the unread parameter contract reports no write")
assert_equal(unwalked.ownership, "none", "an unread parameter contract owns nothing")
assert_equal(#unwalked_calls.attempts, 0, "an unread parameter contract never calls the setter")
assert_equal(unwalked_calls.binding, 0, "an unread parameter contract does not even read the attribute")

-- The contract must supply the signature block at all: without it the pilot has no evidence
-- its argument shape matches the function, so it refuses for the same reason.
local no_signature_deps, no_signature_calls = make_environment({ contract_signature = false })
local no_signature = Pilot.Roundtrip(no_signature_deps)
assert_equal(no_signature.ok, false, "a contract without the setter signature refuses the pilot")
assert_equal(no_signature.stage, "signature-contract", "missing signature stage")
assert_equal(#no_signature_calls.attempts, 0, "a missing signature never calls the setter")

local no_struct = Pilot.Roundtrip((make_environment({ contract_struct_missing = true })))
assert_equal(no_struct.ok, false, "a contract without the descriptor refuses the pilot")
assert_equal(no_struct.stage, "descriptor", "missing descriptor stage")

local drift_options = { descriptor_address = 7002, contract_struct_address = "5001" }
local drift_deps, drift_calls = make_environment(drift_options)
local drifted_descriptor = Pilot.Roundtrip(drift_deps)
assert_equal(drifted_descriptor.ok, false, "a descriptor that changed since the contract is refused")
assert_equal(drifted_descriptor.stage, "descriptor", "changed descriptor stage")
assert_equal(#drift_calls.attempts, 0, "a changed descriptor writes nothing")

assert_equal(Pilot.Roundtrip((make_environment({ cdo_missing = true }))).stage, "setter", "missing setter stage")
assert_equal(Pilot.Roundtrip((make_environment({ setter_missing = true }))).stage, "setter", "missing setter function stage")
assert_equal(Pilot.Roundtrip((make_environment({ setter_class_name = "Class /Script/DogwoodCombat.SomethingElse" }))).stage,
    "setter", "wrong setter class stage")

local replaced_player, replaced_calls = make_environment({ player_replaced = true })
assert_equal(Pilot.Roundtrip(replaced_player).stage, "player-context", "replaced player stage")
assert_equal(#replaced_calls.attempts, 0, "a replaced player writes nothing")

assert_equal(Pilot.Roundtrip((make_environment({ inventory_missing = true }))).stage, "player-context", "missing inventory stage")
assert_equal(Pilot.Roundtrip((make_environment({ raw_limit = 0.0 }))).stage, "target", "non-positive raw limit stage")
assert_equal(Pilot.Roundtrip((make_environment({ getter_fails = true }))).stage, "player-context", "refused read-only getter stage")
assert_equal(Pilot.Roundtrip((make_environment({ getter_offset = 5.0 }))).stage, "player-context", "getter disagreement stage")
assert_equal(Pilot.Roundtrip((make_environment({ getter_found_false = true }))).stage, "player-context", "missing bFound stage")

-- A postcondition mismatch: the derived state did not match the prediction, so the pilot
-- restores through the same arrangement and verifies the baseline before reporting.
local mismatch_deps, mismatch_calls, mismatch_attribute = make_environment({ setter_doubles = true })
local mismatch = Pilot.Roundtrip(mismatch_deps)
assert_equal(mismatch.ok, false, "a postcondition mismatch fails the pilot")
assert_equal(mismatch.stage, "postcondition", "postcondition mismatch stage")
assert_match(mismatch.message, "the exact baseline was restored and verified", "the mismatch is recovered and reported")
assert_equal(mismatch.ownership, "none", "a recovered mismatch owns nothing")
assert_equal(mismatch_attribute.BaseValue, 0.0, "the recovered mismatch ends at the baseline")
assert_equal(mismatch_calls.applied[2], 0.0, "the recovery writes the captured base value")

-- The write path has to be able to read its own value back.
local readback_deps, readback_calls = make_environment({ binding_postcondition_failure = true })
local readback = Pilot.Roundtrip(readback_deps)
assert_equal(readback.ok, false, "a write path that cannot read its value back fails the pilot")
assert_equal(readback.stage, "postcondition", "unreadable write path stage")
assert_match(readback.message, "could not read the new base value back", "the failed confirmation is named")
assert_equal(readback.ownership, "none", "a recovered readback failure owns nothing")
assert_equal(#readback_calls.applied, 2, "a recovered readback failure still restores")

-- A rollback that does not take effect is reported as pending ownership, never as success.
local rollback_deps, rollback_calls, rollback_attribute = make_environment({ setter_ignores_rollback = true })
local rollback = Pilot.Roundtrip(rollback_deps)
assert_equal(rollback.ok, false, "a rollback that does not take effect fails the pilot")
assert_equal(rollback.stage, "rollback", "rollback failure stage")
assert_equal(rollback.ownership, "pending", "a failed rollback is reported as pending ownership")
assert_equal(rollback_attribute.BaseValue, 1000.0, "the failed rollback leaves the written value, not a silent pass")
assert_equal(#rollback_calls.attempts, 2, "the failed rollback still attempted the restoring call")

-- A baseline that is not zero has to come back exactly too.
local nonzero_deps, nonzero_calls, nonzero_attribute = make_environment({ base_value = 30.0, current_value = 30.0 })
local nonzero = Pilot.Roundtrip(nonzero_deps)
assert_true(nonzero.ok, "a non-zero baseline round trip passes")
assert_equal(nonzero.restored.attribute_base_value, 30.0, "a non-zero baseline comes back exactly")
assert_equal(nonzero.restored.effective_weight_limit, 230.0, "a non-zero baseline limit comes back exactly")
assert_equal(nonzero_calls.applied[2], 30.0, "the rollback writes the captured non-zero base value")
assert_equal(nonzero_attribute.BaseValue, 30.0, "the live attribute ends at the non-zero baseline")

local missing_dependencies = Pilot.Roundtrip({})
assert_equal(missing_dependencies.ok, false, "missing dependencies refuse the pilot")
assert_equal(missing_dependencies.stage, "dependencies", "missing dependency stage")

print("Carry-weight set/readback/rollback pilot harness passed.")
