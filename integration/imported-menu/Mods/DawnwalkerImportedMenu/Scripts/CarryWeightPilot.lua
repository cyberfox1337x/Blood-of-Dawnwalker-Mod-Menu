local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("carry_weight_roundtrip_pilot")

-- Set / readback / rollback pilot for carry capacity.
--
-- CARRY-CAPACITY-FEASIBILITY.md sets the order: the read-only probe must pass in the
-- pinned runtime first, then a separate set/readback/rollback pilot must prove exact
-- restoration, and only then may a production capability exist. The read-only probe now
-- passes live (2026-09-17), so this module is that second step and no more: it writes one
-- high finite base value through the game's own setter, proves the derived weight limit
-- moved to the predicted value, restores the exact captured base value, and proves the
-- full baseline came back. It owns nothing afterwards.
--
-- Route rules taken from that feasibility note, enforced here:
--   * only CombatBlueprintFunctionLibrary.SetAttributeValue, with the attribute the
--     read-only contract just validated in this same run;
--   * never a direct write to GameplayAttributeData, the raw WeightLimit or
--     bWeightExceeded - a source test fails the suite if such a write appears;
--   * the write is unreachable unless this run's read-only contract walked the setter's
--     live parameter kinds: an argument shape that cannot be verified is never passed to
--     the native setter, because an unverified one already crashed the process;
--   * any postcondition failure restores through the same setter and re-verifies the
--     baseline before reporting, and a failed restoration is reported as pending rather
--     than falling back to a direct property write.
--
-- Two things this pinned UE4SS build does that the reviewed route did not anticipate, both
-- measured live rather than assumed:
--   1. A reflected non-const `FGameplayAttribute&` is an out parameter, so the validated
--      descriptor struct in that position is refused before the native call runs ("Tried
--      storing reference to a Lua table for an 'Out' parameter when calling a UFunction but
--      no table was on the stack"). That is the reviewed arrangement below, so on this build
--      the pilot reports a refusal and stops.
--   2. What the reference position does want cannot be resolved read-only: the only other
--      reflected function carrying this attribute takes it *by value* (pinned UHT dump,
--      GameplayAbilities line 1244), so it accepts the struct and says nothing at all about a
--      reference position.
--
-- The first attempt to work around (2) built a Lua table carrying the descriptor's own
-- AttributeName and AttributeOwner for that position, and the first attempt to work around a
-- refusal tried the plausible arrangements in turn, each refusal re-read before the next.
-- Both were wrong and the game crashed. A refused arrangement raises inside UE4SS before the
-- native call, but an arrangement that is merely wrong in another way does not - it binds,
-- hands the native setter a value it cannot use, and the game dies with an access violation
-- inside `RC::LuaType::call_ufunction_from_lua` (crash
-- `UECC-Windows-BFFF9348408C7188BB738FB818A1E8CC`, 2026-09-17, reading address 0x10).
-- pcall cannot catch that.
--
-- So this module calls exactly one reviewed arrangement and never varies it, and it never
-- builds an attribute argument as a Lua table. If the arrangement is refused, the pilot
-- reports it and stops: the capability stays withdrawn, and no other arrangement is ever
-- attempted from the menu.

local M = {}

local ATTRIBUTE_NAME = "CarryWeightCapacityModifier"
local BINDING_LIBRARY_CDO_PATH = "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"
local SETTER_CDO_PATH = "/Script/DogwoodCombat.Default__CombatBlueprintFunctionLibrary"
local SETTER_CLASS_NAME = "Class /Script/DogwoodCombat.CombatBlueprintFunctionLibrary"
local SETTER_FUNCTION_PATH = "/Script/DogwoodCombat.CombatBlueprintFunctionLibrary:SetAttributeValue"

-- "Prefer a separately reviewed high finite effective-capacity target for the first
-- mutation pilot" - this is that target. It is a base value, not a limit: the observed
-- immutable raw limit is added on top by GetWeightLimit().
local PILOT_TARGET_BASE_VALUE = 1000.0

-- The one arrangement this module calls: the setter, the ability system, the descriptor the
-- read-only contract validated in this run, and the value. Nothing else is ever attempted -
-- see the crash note in the header. A source test fails the suite if a second arrangement
-- appears here.
local REVIEWED_WRITE_SHAPE = "reviewed-struct-argument"

local function reviewed_arguments(ability_system, descriptor, value)
    return ability_system, descriptor, value
end

local function fail(stage, message, ownership)
    return {
        ok = false,
        mutation_authorized = true,
        ownership = ownership or "none",
        stage = stage,
        message = message,
    }
end

local function is_finite_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function nearly_equal(left, right)
    if not is_finite_number(left) or not is_finite_number(right) then return false end
    local scale = math.max(1.0, math.abs(left), math.abs(right))
    return math.abs(left - right) <= (scale * 0.00001)
end

local function is_valid(object)
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

local function full_name(object)
    if not is_valid(object) then return nil end
    local ok, name = pcall(function() return object:GetFullName() end)
    if not ok or type(name) ~= "string" then return nil end
    return name
end

local function object_address(object)
    if not is_valid(object) then return nil end
    local ok, address = pcall(function() return object:GetAddress() end)
    if not ok or not is_finite_number(address) or address <= 0 then return nil end
    return tostring(address)
end

local function resolve_setter(deps)
    local cdo_ok, cdo = pcall(deps.static_find_object, SETTER_CDO_PATH)
    if not cdo_ok or not is_valid(cdo) then
        return nil, "the CombatBlueprintFunctionLibrary CDO is unavailable"
    end
    local name = full_name(cdo)
    if name == nil or name:find("Default__CombatBlueprintFunctionLibrary", 1, true) == nil then
        return nil, "the resolved setter target is not the CombatBlueprintFunctionLibrary CDO"
    end
    local class_ok, class_name = pcall(function() return cdo:GetClass():GetFullName() end)
    if not class_ok or class_name ~= SETTER_CLASS_NAME then
        return nil, "the setter CDO no longer has the pinned class"
    end
    local function_ok, setter = pcall(deps.static_find_object, SETTER_FUNCTION_PATH)
    if not function_ok or not is_valid(setter) then
        return nil, "the exact SetAttributeValue UFunction is unavailable"
    end
    return cdo, nil
end

-- Reads the live state and proves the objects are the exact ones the read-only contract
-- validated in this run. Returns the state and the live objects the setter needs.
local function read_live(deps, contract)
    local player_ok, player = pcall(deps.get_player)
    if not player_ok or not is_valid(player) then return nil, "the local player is unavailable", nil end
    local inventory_ok, inventory = pcall(function() return player:GetInventoryComponent() end)
    if not inventory_ok or not is_valid(inventory) then return nil, "the player inventory is unavailable", nil end
    local asc_ok, ability_system = pcall(function() return player.AbilitySystemComponent end)
    if not asc_ok or not is_valid(ability_system) then return nil, "the player ASC is unavailable", nil end
    local char_dev_ok, char_dev = pcall(function() return player.CharDevAttributeSet end)
    if not char_dev_ok or not is_valid(char_dev) then return nil, "the player CharDevAttributeSet is unavailable", nil end

    local expected = contract.snapshot
    local identity_errors = {}
    local function same(label, object, expected_address)
        local address = object_address(object)
        if address == nil or address ~= tostring(expected_address) then
            identity_errors[#identity_errors + 1] = label
        end
    end
    same("player", player, expected.player_address)
    same("inventory", inventory, expected.inventory_address)
    same("ability system", ability_system, expected.asc_address)
    same("attribute set", char_dev, expected.char_dev_address)
    if #identity_errors > 0 then
        return nil, "the objects changed since the read-only contract: " .. table.concat(identity_errors, ", "), nil
    end

    local read_ok, raw_limit, effective_limit, current_weight, weight_exceeded, attribute_data = pcall(function()
        return inventory.WeightLimit,
            inventory:GetWeightLimit(),
            inventory:GetCurrentWeight(),
            inventory.bWeightExceeded,
            char_dev[ATTRIBUTE_NAME]
    end)
    if not read_ok then return nil, "the live read failed: " .. tostring(raw_limit), nil end
    if attribute_data == nil then return nil, "CarryWeightCapacityModifier data is unavailable", nil end
    local values_ok, base_value, current_value = pcall(function()
        return attribute_data.BaseValue, attribute_data.CurrentValue
    end)
    if not values_ok then return nil, "CarryWeightCapacityModifier values could not be read", nil end
    if not is_finite_number(raw_limit) or not is_finite_number(effective_limit)
        or not is_finite_number(current_weight) or not is_finite_number(base_value)
        or not is_finite_number(current_value) then
        return nil, "the live read contains a non-finite numeric value", nil
    end
    if type(weight_exceeded) ~= "boolean" then return nil, "the live weight flag is not a boolean", nil end

    local expected_limit = raw_limit <= 0 and raw_limit or (raw_limit + current_value)
    if not nearly_equal(effective_limit, expected_limit) then
        return nil, "GetWeightLimit does not match WeightLimit + CarryWeightCapacityModifier", nil
    end
    -- The engine's own rule: false for a limit of exactly zero, otherwise the comparison.
    -- Stated as a branch on purpose - "A and false or B" would discard the false branch.
    local expected_exceeded
    if effective_limit == 0 then
        expected_exceeded = false
    else
        expected_exceeded = current_weight > effective_limit
    end
    if weight_exceeded ~= expected_exceeded then
        return nil, "bWeightExceeded is not synchronized with the effective limit", nil
    end

    return {
        raw_weight_limit = raw_limit,
        effective_weight_limit = effective_limit,
        current_weight = current_weight,
        weight_exceeded = weight_exceeded,
        attribute_base_value = base_value,
        attribute_current_value = current_value,
    }, nil, {
        player = player,
        inventory = inventory,
        ability_system = ability_system,
        char_dev = char_dev,
    }
end

-- The by-value descriptor getter the read-only contract proved: it must agree with the
-- property value.
local function read_through_descriptor(objects, descriptor, expected_current)
    local out = {}
    local ok, value = pcall(function()
        return objects.ability_system:GetGameplayAttributeValue(descriptor, out)
    end)
    if not ok then return nil, "the read-only ASC getter rejected the descriptor: " .. tostring(value) end
    if not is_finite_number(value) then return nil, "the ASC getter returned a non-finite value" end
    if out.bFound ~= true then return nil, "the ASC getter did not report bFound = true" end
    if not nearly_equal(value, expected_current) then
        return nil, "the ASC getter disagrees with GameplayAttributeData.CurrentValue"
    end
    return value, nil
end

-- Reads the attribute's base value through the library getter, read-only. Single shape for
-- the same reason the write is: this parameter is `FGameplayAttribute Attribute` by value
-- (pinned UHT dump, GameplayAbilities line 1244), so the validated descriptor goes in as it
-- is and no alternative arrangement is attempted.
local function read_base_through_binding(deps, objects, descriptor, expected_base)
    local library_ok, library = pcall(deps.static_find_object, BINDING_LIBRARY_CDO_PATH)
    if not library_ok or not is_valid(library) then
        return nil, "the ability-system library CDO is unavailable"
    end
    local out = {}
    local ok, value = pcall(function()
        return library:GetFloatAttributeBaseFromAbilitySystemComponent(objects.ability_system, descriptor, out)
    end)
    if not ok then return nil, tostring(value) end
    if type(out) ~= "table" or out.bSuccessfullyFoundAttribute ~= true then
        return nil, "the library getter did not report the attribute as found"
    end
    if not is_finite_number(value) then return nil, "the library getter returned a non-finite value" end
    if not nearly_equal(value, expected_base) then
        return nil, string.format("the library getter reads %s where %s was expected", tostring(value), tostring(expected_base))
    end
    return value, nil
end

-- Records that the validated attribute can be read back through the library before any
-- write route is attempted at all. The record is evidence only: as the note above explains,
-- this call cannot resolve the reference position the setter needs.
local function record_binding(deps, objects, descriptor, expected_base)
    local value, reason = read_base_through_binding(deps, objects, descriptor, expected_base)
    local record = { value ~= nil
        and string.format("struct-value read %s", tostring(value))
        or string.format("struct-value refused: %s", tostring(reason)) }
    if value == nil then
        return nil, record, "the library getter could not read the validated attribute: " .. tostring(reason)
    end
    return "struct-value", record, nil
end

-- Compares a live read against an expected state, listing every disagreement.
local function describe_differences(actual, expected)
    local differences = {}
    for _, field in ipairs({
        "attribute_base_value",
        "attribute_current_value",
        "effective_weight_limit",
        "weight_exceeded",
    }) do
        if field == "weight_exceeded" then
            if actual[field] ~= expected[field] then differences[#differences + 1] = field end
        elseif not nearly_equal(actual[field], expected[field]) then
            differences[#differences + 1] = string.format("%s (%s vs %s)", field, tostring(actual[field]), tostring(expected[field]))
        end
    end
    return differences
end

-- Applies one base value through the documented setter in the single reviewed arrangement.
-- A refusal raises inside UE4SS before the native call runs; the live state is still read
-- before and after it, and a refusal that somehow changed the attribute is reported instead
-- of being hidden. No second arrangement is ever attempted.
local function write_base_value(deps, contract, setter, objects, descriptor, value)
    local before, before_error = read_live(deps, contract)
    if before == nil then
        return nil, "the live state could not be read before a write: " .. tostring(before_error)
    end
    local ok, reason = pcall(function()
        return setter:SetAttributeValue(reviewed_arguments(objects.ability_system, descriptor, value))
    end)
    if ok then return REVIEWED_WRITE_SHAPE, nil end
    local after, after_error = read_live(deps, contract)
    if after == nil then
        return nil, "the refused call could not be re-read: " .. tostring(after_error)
    end
    local differences = describe_differences(after, before)
    if #differences > 0 then
        return nil, "the refused call changed the attribute anyway (" .. table.concat(differences, ", ") .. ")"
    end
    return nil, string.format("the runtime refused the reviewed call shape (%s); the live state still matches the baseline",
        tostring(reason))
end

-- Puts the captured base value back through the same setter order and proves the full
-- baseline came back. Returns the verified baseline read, or a reason it could not be
-- proven. Never falls back to a direct property write.
local function restore_baseline(deps, contract, setter, objects, descriptor, baseline)
    local ok, reason = pcall(function()
        return setter:SetAttributeValue(reviewed_arguments(objects.ability_system, descriptor, baseline.attribute_base_value))
    end)
    if not ok then return nil, "the restoring call was refused: " .. tostring(reason) end
    local restored, read_error = read_live(deps, contract)
    if restored == nil then return nil, "the restoring readback failed: " .. tostring(read_error) end
    local through, through_error = read_through_descriptor(objects, descriptor, restored.attribute_current_value)
    if through == nil then return nil, through_error end
    local differences = describe_differences(restored, baseline)
    if #differences > 0 then
        return nil, "the baseline did not come back exactly (" .. table.concat(differences, ", ") .. ")"
    end
    return restored, nil
end

-- One set / readback / rollback round trip. `deps` carries the probe module and the same
-- reflection, player and property-type handles the probe takes.
function M.Roundtrip(deps)
    if type(deps) ~= "table" or type(deps.probe) ~= "table"
        or type(deps.static_find_object) ~= "function" or type(deps.get_player) ~= "function"
        or type(deps.property_types) ~= "table" then
        return fail("dependencies", "the pilot dependencies are incomplete")
    end

    -- Gate 1: the read-only contract, re-run now, on this session.
    local contract = deps.probe.run({
        static_find_object = deps.static_find_object,
        get_player = deps.get_player,
        property_types = deps.property_types,
    })
    if type(contract) ~= "table" or contract.ok ~= true then
        local stage = type(contract) == "table" and contract.stage or "unknown"
        local message = type(contract) == "table" and contract.message or "no verdict"
        return fail("read-only-contract",
            string.format("the read-only carry-weight check did not pass, so no value was written (%s: %s)",
                tostring(stage), tostring(message)))
    end
    -- Gate 2: the setter's argument contract has to have been read from the live function
    -- on this run. The first version of this pilot called the setter with an argument shape
    -- it could not verify, and that crashed the process (see the header): a refusal this
    -- module can detect is recoverable, a mis-marshalled native call is not. So the write
    -- below is unreachable unless the read-only check walked the live parameter kinds.
    local signature = contract.setter_signature
    if type(signature) ~= "table" then
        return fail("signature-contract", "the read-only contract did not hand back the setter signature")
    end
    if signature.metadata_walk ~= "walked" then
        return fail("signature-contract", string.format(
            "the read-only check could not read the setter's parameter kinds on this build (metadata_walk = %s), and a call whose argument shape could not be verified already crashed the game on 2026-09-17, so no write was attempted",
            tostring(signature.metadata_walk)))
    end

    local descriptor = contract.descriptor and contract.descriptor.struct
    if descriptor == nil then
        return fail("descriptor", "the read-only contract did not hand back its validated descriptor")
    end
    local descriptor_ok, descriptor_address = pcall(function() return descriptor:GetStructAddress() end)
    if not descriptor_ok or not is_finite_number(descriptor_address) or descriptor_address <= 0 then
        return fail("descriptor", "the validated descriptor no longer has a readable struct address")
    end
    if tostring(descriptor_address) ~= tostring(contract.descriptor.struct_address) then
        return fail("descriptor", "the descriptor identity changed between the contract and this pilot")
    end

    local setter, setter_error = resolve_setter(deps)
    if setter == nil then return fail("setter", setter_error) end

    if not is_finite_number(PILOT_TARGET_BASE_VALUE) then
        return fail("target", "the reviewed pilot target is not a finite number")
    end

    local baseline, read_error, objects = read_live(deps, contract)
    if baseline == nil then return fail("player-context", read_error) end
    if baseline.raw_weight_limit <= 0 then
        -- GetWeightLimit() returns the raw value unchanged when it is non-positive, so a
        -- modifier change would not be observable and the pilot could not prove anything.
        return fail("target", "the raw weight limit is not positive, so a modifier change would not be observable")
    end
    local baseline_read, baseline_read_error = read_through_descriptor(objects, descriptor, baseline.attribute_current_value)
    if baseline_read == nil then return fail("player-context", baseline_read_error) end

    -- Record what the attribute reads like through the library before anything is written.
    local binding, binding_attempts, binding_error = record_binding(deps, objects, descriptor, baseline.attribute_base_value)
    if binding == nil then return fail("binding", binding_error) end

    -- The documented prediction: base value replaces the base, the attribute's other
    -- contribution (CurrentValue - BaseValue) is unchanged, and GetWeightLimit() adds the
    -- resulting CurrentValue to the raw limit.
    local other_contribution = baseline.attribute_current_value - baseline.attribute_base_value
    local predicted_limit = baseline.raw_weight_limit + PILOT_TARGET_BASE_VALUE + other_contribution
    local predicted_exceeded
    if predicted_limit == 0 then
        predicted_exceeded = false
    else
        predicted_exceeded = baseline.current_weight > predicted_limit
    end
    local expected = {
        attribute_base_value = PILOT_TARGET_BASE_VALUE,
        attribute_current_value = PILOT_TARGET_BASE_VALUE + other_contribution,
        effective_weight_limit = predicted_limit,
        weight_exceeded = predicted_exceeded,
    }

    local shape, write_error = write_base_value(deps, contract, setter, objects, descriptor, PILOT_TARGET_BASE_VALUE)
    if shape == nil then
        -- Nothing bound. The attribute has already been re-read after every refusal, but the
        -- baseline is proved once more before this is reported as a plain refusal.
        local unchanged, verify_error = read_live(deps, contract)
        if unchanged == nil then
            return fail("setter-call",
                string.format("no call order was accepted (%s) and the live state could not be re-read: %s",
                    tostring(write_error), tostring(verify_error)), "pending")
        end
        local differences = describe_differences(unchanged, baseline)
        if #differences == 0 then
            return fail("setter-call",
                string.format("%s, so nothing was written", tostring(write_error)))
        end
        local recovered, recovered_error = restore_baseline(deps, contract, setter, objects, descriptor, baseline)
        if recovered == nil then
            return fail("setter-call",
                string.format("%s after changing the attribute (%s), and the baseline could not be restored (%s)",
                    tostring(write_error), table.concat(differences, ", "), tostring(recovered_error)), "pending")
        end
        return fail("setter-call",
            string.format("%s after changing the attribute (%s); the exact baseline was restored and verified",
                tostring(write_error), table.concat(differences, ", ")))
    end

    local post, post_error = read_live(deps, contract)
    if post == nil then
        local recovered, recovered_error = restore_baseline(deps, contract, setter, objects, descriptor, baseline)
        return fail("postcondition",
            string.format("the attribute was written through %s but the readback failed (%s); baseline restoration %s",
                shape, tostring(post_error),
                recovered ~= nil and "was verified" or ("could not be verified: " .. tostring(recovered_error))),
            recovered ~= nil and "none" or "pending")
    end
    local post_read, post_read_error = read_through_descriptor(objects, descriptor, post.attribute_current_value)
    local differences = post_read == nil and { post_read_error } or describe_differences(post, expected)
    if #differences == 0 then
        -- The write path must be able to read its own value back too.
        local written, written_error = read_base_through_binding(deps, objects, descriptor, PILOT_TARGET_BASE_VALUE)
        if written == nil then differences = { "the write path could not read the new base value back: " .. tostring(written_error) } end
    end

    if #differences > 0 then
        -- Fail closed: put the baseline back through the same setter order and prove it
        -- before reporting, exactly as the feasibility note requires.
        local recovered, recovered_error = restore_baseline(deps, contract, setter, objects, descriptor, baseline)
        if recovered == nil then
            return fail("postcondition",
                string.format("the readback disagreed with the prediction (%s) and the baseline could not be restored (%s)",
                    table.concat(differences, ", "), tostring(recovered_error)), "pending")
        end
        return fail("postcondition",
            string.format("the readback disagreed with the prediction (%s); the exact baseline was restored and verified",
                table.concat(differences, ", ")))
    end

    -- Rollback from the verified post-state through the resolved order, then prove the
    -- whole baseline came back.
    local restored, restore_error = restore_baseline(deps, contract, setter, objects, descriptor, baseline)
    if restored == nil then
        return fail("rollback", tostring(restore_error), "pending")
    end

    return {
        ok = true,
        mutation_authorized = true,
        ownership = "none",
        stage = "rollback-complete",
        message = string.format(
            "Pilot passed: base %s -> %s (limit %s -> %s, over-limit %s -> %s), then restored to base %s and limit %s. The exact baseline is back and nothing is owned. The library read the attribute as %s and the runtime accepted the %s arrangement.",
            tostring(baseline.attribute_base_value), tostring(post.attribute_base_value),
            tostring(baseline.effective_weight_limit), tostring(post.effective_weight_limit),
            tostring(baseline.weight_exceeded), tostring(post.weight_exceeded),
            tostring(restored.attribute_base_value), tostring(restored.effective_weight_limit),
            tostring(binding), tostring(shape)),
        binding = binding,
        binding_attempts = binding_attempts,
        write_shape = shape,
        descriptor = contract.descriptor,
        target_base_value = PILOT_TARGET_BASE_VALUE,
        before = baseline,
        applied = post,
        restored = restored,
    }
end

return M
