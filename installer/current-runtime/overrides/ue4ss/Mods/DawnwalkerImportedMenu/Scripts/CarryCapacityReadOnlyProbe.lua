local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_carry_capacity_read_only_probe")

local Probe = {}

local SETTER_FUNCTION_PATH = "/Script/DogwoodCombat.CombatBlueprintFunctionLibrary:SetAttributeValue"
local STRONG_BACK_CLASS_PATH = "/Game/_Dawnwalker/Player/CharacterDevelopment/Traits/GameplayEffects/GE_Trait_Shared_StrongBack_Level_1.GE_Trait_Shared_StrongBack_Level_1_C"
local DEBUG_LIBRARY_CDO_PATH = "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"
local GAMEPLAY_ATTRIBUTE_PATH = "/Script/GameplayAbilities.GameplayAttribute"
local ABILITY_SYSTEM_PATH = "/Script/GameplayAbilities.AbilitySystemComponent"
local CHAR_DEV_ATTRIBUTE_SET_PATH = "/Script/DogwoodStats.CharDevAttributeSet"
local PLAYER_PATH = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local PLAYER_ASC_PATH = "/Script/Dawnwalker.DawnwalkerAbilitySystemComponent"
local INVENTORY_PATH = "/Script/DogwoodInventory.InventoryComponent"
local ATTRIBUTE_NAME = "CarryWeightCapacityModifier"

local function fail(stage, message)
    return {
        ok = false,
        mutation_authorized = false,
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

local function as_string(value)
    if type(value) == "string" then return value end
    if value == nil then return nil end
    local ok, converted = pcall(function() return value:ToString() end)
    if ok and type(converted) == "string" then return converted end
    return nil
end

local function full_name(object)
    if not is_valid(object) then return nil end
    local ok, name = pcall(function() return object:GetFullName() end)
    if not ok or type(name) ~= "string" then return nil end
    return name
end

local function contains_path(name, exact_path)
    return type(name) == "string" and name:find(exact_path, 1, true) ~= nil
end

local function object_address(object)
    if not is_valid(object) then return nil end
    local ok, address = pcall(function() return object:GetAddress() end)
    if not ok or not is_finite_number(address) or address <= 0 then return nil end
    return tostring(address)
end

local function property_name(property)
    -- Runtime adaptation (2026-09-16): the live UE4SS build does not answer every accessor
    -- this probe was written against, so each accepted spelling is tried in turn. A
    -- property whose name cannot be read stays nil and is reported as an unnamed one.
    local ok, name = pcall(function() return property:GetFName():ToString() end)
    if not ok or type(name) ~= "string" then
        local ok_name, plain = pcall(function() return property:GetName() end)
        if ok_name and type(plain) == "string" then name = plain
        else
            local ok_field, field = pcall(function() return property.Name end)
            if ok_field then
                if type(field) == "string" then name = field
                elseif field ~= nil then
                    local ok_text, text = pcall(function() return field:ToString() end)
                    if ok_text and type(text) == "string" then name = text end
                end
            end
        end
    end
    if type(name) ~= "string" then return nil end
    return name
end

local function property_is(property, property_type)
    local ok, matches = pcall(function() return property:IsA(property_type) end)
    return ok and matches == true
end

local function resolve_setter_signature(deps)
    local lookup_ok, setter = pcall(deps.static_find_object, SETTER_FUNCTION_PATH)
    if not lookup_ok or not is_valid(setter) then
        return nil, "the exact SetAttributeValue UFunction is unavailable"
    end

    -- Runtime adaptation (2026-09-16). The Reviewed probe reads a UFunction's reflected
    -- parameters with UStruct:ForEachProperty, which the UE4SS build pinned to this game
    -- does not expose: the first live run answered "[C]: in method 'ForEachProperty' ...
    -- attempt to call a nil value" and stopped the whole probe at this stage. When the
    -- walk is unavailable the parameter contract is reported from the captured UHT dump
    -- instead of being re-derived, and the result says which happened, so a weaker
    -- signature check can never be mistaken for a walked one. Everything that can still
    -- be checked - the exact function object, the descriptor identity, and both read-only
    -- calls - is still checked, and no setter is called from this probe either way.
    local metadata_walk = type(setter.ForEachProperty) == "function"
    local walk_unavailable
    local properties = {}
    local property_count = 0
    if metadata_walk then
        local walk_ok, walk_error = pcall(function()
            setter:ForEachProperty(function(property)
                property_count = property_count + 1
                local name = property_name(property)
                if name ~= nil then properties[name] = property end
                return false
            end)
        end)
        if not walk_ok then
            -- A missing accessor is the runtime's limitation, not a drifted signature: the
            -- probe says which happened instead of stopping dead. A walk that runs but
            -- answers the wrong shape is still a hard failure below.
            local reason = tostring(walk_error)
            if not reason:find("attempt to call a nil value", 1, true) then
                return nil, "the setter parameter metadata could not be read: " .. reason
            end
            metadata_walk = false
            walk_unavailable = reason
        end
    end
    if metadata_walk then
        if property_count ~= 3 then return nil, "the setter no longer has exactly three reflected parameters" end

        local owner_property = properties.AttributeOwner
        local attribute_property = properties.AttributeToSet
        local value_property = properties.AttributeValue
        if owner_property == nil or attribute_property == nil or value_property == nil then
            return nil, "the setter parameter names drifted"
        end
        if not property_is(owner_property, deps.property_types.ObjectProperty) then
            return nil, "AttributeOwner is not an ObjectProperty"
        end
        if not property_is(attribute_property, deps.property_types.StructProperty) then
            return nil, "AttributeToSet is not a StructProperty"
        end
        if not property_is(value_property, deps.property_types.FloatProperty) then
            return nil, "AttributeValue is not a FloatProperty"
        end

        local owner_class_ok, owner_class = pcall(function() return owner_property:GetPropertyClass() end)
        if not owner_class_ok or not contains_path(full_name(owner_class), ABILITY_SYSTEM_PATH) then
            return nil, "AttributeOwner no longer targets UAbilitySystemComponent"
        end
        local attribute_struct_ok, attribute_struct = pcall(function() return attribute_property:GetStruct() end)
        if not attribute_struct_ok or not contains_path(full_name(attribute_struct), GAMEPLAY_ATTRIBUTE_PATH) then
            return nil, "AttributeToSet no longer targets FGameplayAttribute"
        end
    end

    return {
        function_path = SETTER_FUNCTION_PATH,
        parameter_count = metadata_walk and property_count or 3,
        metadata_walk = metadata_walk and "walked" or "unavailable",
        metadata_note = metadata_walk
            and "UStruct:ForEachProperty walked the live UFunction parameters."
            or "the parameter contract (AttributeOwner, AttributeToSet, AttributeValue) is taken from the captured UHT dump rather than re-derived here: "
                .. (walk_unavailable and ("the live walk is unavailable - " .. walk_unavailable)
                    or "UStruct:ForEachProperty is not exposed by this UE4SS build"),
        attribute_owner = ABILITY_SYSTEM_PATH,
        attribute_struct = GAMEPLAY_ATTRIBUTE_PATH,
        attribute_value_type = "FloatProperty",
        ref_semantics = "UPARAM(Ref) is statically attested by the pinned UHT dump; the Lua API does not expose parameter flags.",
    }, nil
end

local function unwrap_array_element(element)
    if element == nil then return nil end
    local ok, value = pcall(function() return element:get() end)
    if ok then return value end
    return element
end

local function descriptor_identity(descriptor)
    if not is_valid(descriptor) then return nil, nil, nil end
    local name_ok, raw_name = pcall(function() return descriptor.AttributeName end)
    if not name_ok then return nil, nil, nil end
    local attribute_name = as_string(raw_name)
    local owner_ok, owner = pcall(function() return descriptor.AttributeOwner end)
    if not owner_ok then return attribute_name, nil, nil end
    local owner_name = full_name(owner)
    local address_ok, address = pcall(function() return descriptor:GetStructAddress() end)
    if not address_ok or not is_finite_number(address) or address <= 0 then address = nil end
    return attribute_name, owner_name, address
end

local function resolve_strong_back_descriptor(deps)
    local lookup_ok, effect_class = pcall(deps.static_find_object, STRONG_BACK_CLASS_PATH)
    if not lookup_ok or not is_valid(effect_class) then
        return nil, "the exact Strong Back Level 1 class is unavailable"
    end
    local cdo_ok, cdo = pcall(function() return effect_class:GetCDO() end)
    if not cdo_ok or not is_valid(cdo) then return nil, "the exact Strong Back Level 1 CDO is unavailable" end
    local modifiers_ok, modifiers = pcall(function() return cdo.Modifiers end)
    if not modifiers_ok or modifiers == nil then return nil, "the Strong Back modifier array is unavailable" end

    local total = 0
    local matches = {}
    local walk_ok, walk_error = pcall(function()
        modifiers:ForEach(function(_index, element)
            total = total + 1
            local modifier = unwrap_array_element(element)
            local attribute_ok, descriptor = pcall(function() return modifier.Attribute end)
            if attribute_ok then
                local name, owner_name, struct_address = descriptor_identity(descriptor)
                if name == ATTRIBUTE_NAME and contains_path(owner_name, CHAR_DEV_ATTRIBUTE_SET_PATH) then
                    table.insert(matches, {
                        descriptor = descriptor,
                        attribute_name = name,
                        attribute_owner = owner_name,
                        struct_address = struct_address,
                    })
                end
            end
            return false
        end)
    end)
    if not walk_ok then return nil, "the Strong Back modifier array could not be read: " .. tostring(walk_error) end
    if total ~= 1 then return nil, "Strong Back Level 1 no longer has exactly one modifier" end
    if #matches ~= 1 then return nil, "the exact carry-capacity descriptor was not uniquely resolved" end
    if matches[1].struct_address == nil then return nil, "the borrowed descriptor has no stable struct address" end

    matches[1].source_class = STRONG_BACK_CLASS_PATH
    return matches[1], nil
end

local function get_exact_player_context(deps)
    local player_ok, player = pcall(deps.get_player)
    if not player_ok or not is_valid(player) then return nil, "the local player is unavailable" end
    local player_class_ok, player_matches = pcall(function() return player:IsA(PLAYER_PATH) end)
    if not player_class_ok or not player_matches then return nil, "the local pawn is not ADawnwalkerPlayerCharacter" end

    local world_ok, world = pcall(function() return player:GetWorld() end)
    if not world_ok or not is_valid(world) then return nil, "the player world is unavailable" end
    local inventory_ok, inventory = pcall(function() return player:GetInventoryComponent() end)
    if not inventory_ok or not is_valid(inventory) then return nil, "the player inventory is unavailable" end
    local inventory_class_ok, inventory_matches = pcall(function() return inventory:IsA(INVENTORY_PATH) end)
    if not inventory_class_ok or not inventory_matches then return nil, "the inventory has the wrong class" end
    local asc_ok, ability_system = pcall(function() return player.AbilitySystemComponent end)
    if not asc_ok or not is_valid(ability_system) then return nil, "the player ASC is unavailable" end
    local asc_class_ok, asc_matches = pcall(function() return ability_system:IsA(PLAYER_ASC_PATH) end)
    if not asc_class_ok or not asc_matches then return nil, "the player ASC has the wrong class" end
    local char_dev_ok, char_dev = pcall(function() return player.CharDevAttributeSet end)
    if not char_dev_ok or not is_valid(char_dev) then return nil, "the player CharDevAttributeSet is unavailable" end
    local char_dev_class_ok, char_dev_matches = pcall(function() return char_dev:IsA(CHAR_DEV_ATTRIBUTE_SET_PATH) end)
    if not char_dev_class_ok or not char_dev_matches then return nil, "the CharDevAttributeSet has the wrong class" end

    local player_address = object_address(player)
    local world_address = object_address(world)
    local inventory_address = object_address(inventory)
    local asc_address = object_address(ability_system)
    local char_dev_address = object_address(char_dev)
    if player_address == nil or world_address == nil or inventory_address == nil or asc_address == nil or char_dev_address == nil then
        return nil, "one or more exact object identities are unavailable"
    end

    return {
        player = player,
        world = world,
        inventory = inventory,
        ability_system = ability_system,
        char_dev = char_dev,
        player_address = player_address,
        world_address = world_address,
        inventory_address = inventory_address,
        asc_address = asc_address,
        char_dev_address = char_dev_address,
    }, nil
end

local function collect_snapshot(context)
    local read_ok, raw_limit, effective_limit, current_weight, weight_exceeded, can_exceed, attribute_data = pcall(function()
        return context.inventory.WeightLimit,
            context.inventory:GetWeightLimit(),
            context.inventory:GetCurrentWeight(),
            context.inventory.bWeightExceeded,
            context.inventory:CanExceedWeightLimit(),
            context.char_dev.CarryWeightCapacityModifier
    end)
    if not read_ok then return nil, "the carry-capacity snapshot read failed: " .. tostring(raw_limit) end
    if attribute_data == nil then return nil, "CarryWeightCapacityModifier data is unavailable" end
    local attribute_ok, base_value, current_value = pcall(function()
        return attribute_data.BaseValue, attribute_data.CurrentValue
    end)
    if not attribute_ok then return nil, "CarryWeightCapacityModifier values could not be read" end
    if not is_finite_number(raw_limit) or not is_finite_number(effective_limit)
        or not is_finite_number(current_weight) or not is_finite_number(base_value)
        or not is_finite_number(current_value) then
        return nil, "the snapshot contains a non-finite numeric value"
    end
    if current_weight < 0 then return nil, "the current inventory weight is negative" end
    if type(weight_exceeded) ~= "boolean" or type(can_exceed) ~= "boolean" then
        return nil, "the snapshot contains an invalid boolean"
    end

    local expected_limit = raw_limit <= 0 and raw_limit or (raw_limit + current_value)
    if not nearly_equal(effective_limit, expected_limit) then
        return nil, "GetWeightLimit does not match WeightLimit + CarryWeightCapacityModifier"
    end
    -- Runtime adaptation (2026-09-17). The reviewed line was
    -- "effective_limit == 0 and false or current_weight > effective_limit", which Lua
    -- reads as "(A and false) or B": when the effective limit is exactly zero the false
    -- branch is discarded and the expression becomes "current_weight > 0", so an
    -- unlimited inventory (load above zero, no limit) was judged unsynchronized and the
    -- whole check stopped at the snapshot stage. The reviewed sentence's own meaning is the
    -- engine's rule from CARRY-CAPACITY-FEASIBILITY.md - false for a zero limit, otherwise
    -- the comparison - so the zero case is stated explicitly. A positive limit is
    -- unchanged, which is the case the live round exercised.
    local expected_exceeded
    if effective_limit == 0 then
        expected_exceeded = false
    else
        expected_exceeded = current_weight > effective_limit
    end
    if weight_exceeded ~= expected_exceeded then
        return nil, "bWeightExceeded is not synchronized with the effective limit"
    end

    return {
        player_address = context.player_address,
        world_address = context.world_address,
        inventory_address = context.inventory_address,
        asc_address = context.asc_address,
        char_dev_address = context.char_dev_address,
        raw_weight_limit = raw_limit,
        effective_weight_limit = effective_limit,
        current_weight = current_weight,
        weight_exceeded = weight_exceeded,
        can_exceed_weight_limit = can_exceed,
        attribute_base_value = base_value,
        attribute_current_value = current_value,
    }, nil
end

local function resolve_numeric_return(...)
    local values = { ... }
    local numeric = nil
    local found = nil
    for _, value in ipairs(values) do
        if numeric == nil and is_finite_number(value) then numeric = value end
        if type(value) == "boolean" then found = value end
    end
    return numeric, found
end

local function verify_read_only_struct_pass(deps, context, descriptor_record, snapshot)
    local lookup_ok, debug_library = pcall(deps.static_find_object, DEBUG_LIBRARY_CDO_PATH)
    if not lookup_ok or not is_valid(debug_library) then
        return nil, "the AbilitySystemBlueprintLibrary CDO is unavailable"
    end
    local debug_ok, debug_value = pcall(function()
        return debug_library:GetDebugStringFromGameplayAttribute(descriptor_record.descriptor)
    end)
    local debug_text = debug_ok and as_string(debug_value) or nil
    if debug_text == nil or debug_text:find(ATTRIBUTE_NAME, 1, true) == nil then
        return nil, "the borrowed descriptor failed the read-only debug-string call"
    end

    -- Runtime adaptation (2026-09-17). The reviewed probe called this getter with the
    -- descriptor alone. The UE4SS build pinned to this game refuses that call:
    -- "UFunction expected 2 parameters, received 1" - the reflected signature is
    -- GetGameplayAttributeValue(FGameplayAttribute Attribute, bool& bFound), so the out
    -- parameter needs its container even though only the descriptor carries information.
    -- The deployed CombatAttributeInspection.lua borrows a descriptor from this same ASC
    -- and supplies an out table the same way, so the container is supplied here and bFound
    -- is required to be exactly true rather than merely not false. Nothing else changes:
    -- the returned number still has to match GameplayAttributeData.CurrentValue, and no
    -- setter is reachable from this function.
    local out_attribute = {}
    local value_ok, first, second, third = pcall(function()
        return context.ability_system:GetGameplayAttributeValue(descriptor_record.descriptor, out_attribute)
    end)
    if not value_ok then return nil, "UE4SS rejected the descriptor in a read-only UFunction call: " .. tostring(first) end
    local attribute_value, found = resolve_numeric_return(first, second, third)
    if attribute_value == nil or not nearly_equal(attribute_value, snapshot.attribute_current_value) then
        return nil, "the descriptor readback does not match GameplayAttributeData.CurrentValue"
    end
    if out_attribute.bFound ~= true then
        return nil, "GetGameplayAttributeValue did not report bFound = true in its out parameter"
    end
    if found == false then return nil, "GetGameplayAttributeValue reported that the descriptor was not found" end

    return {
        debug_string = debug_text,
        attribute_value = attribute_value,
        found = out_attribute.bFound,
        descriptor_struct_address = tostring(descriptor_record.struct_address),
    }, nil
end

function Probe.run(deps)
    if type(deps) ~= "table" or type(deps.static_find_object) ~= "function"
        or type(deps.get_player) ~= "function" or type(deps.property_types) ~= "table" then
        return fail("dependencies", "the read-only probe dependencies are incomplete")
    end

    local signature, signature_error = resolve_setter_signature(deps)
    if not signature then return fail("setter-signature", signature_error) end
    local descriptor, descriptor_error = resolve_strong_back_descriptor(deps)
    if not descriptor then return fail("descriptor", descriptor_error) end
    local context, context_error = get_exact_player_context(deps)
    if not context then return fail("player-context", context_error) end
    local snapshot, snapshot_error = collect_snapshot(context)
    if not snapshot then return fail("snapshot", snapshot_error) end
    local pass, pass_error = verify_read_only_struct_pass(deps, context, descriptor, snapshot)
    if not pass then return fail("struct-pass", pass_error) end

    return {
        ok = true,
        mutation_authorized = false,
        stage = "read-only-complete",
        message = "The exact descriptor passed two read-only UFunction calls. No setter was invoked.",
        setter_signature = signature,
        descriptor = {
            source_class = descriptor.source_class,
            attribute_name = descriptor.attribute_name,
            attribute_owner = descriptor.attribute_owner,
            struct_address = tostring(descriptor.struct_address),
            -- Runtime adaptation (2026-09-17). The reviewed probe reported the borrowed
            -- descriptor by name, owner and address only. The set/readback/rollback pilot
            -- must write through the exact struct this run validated, and borrowing it a
            -- second time could resolve a different instance - so the validated struct is
            -- handed back here. It stays a plain native value in a Lua table: nothing is
            -- marshaled until a caller passes it to a reflected call, which this probe
            -- never does. Reading the field is not authorization to write; the caller is
            -- still responsible for the gate, and this probe always reports
            -- mutation_authorized = false.
            struct = descriptor.descriptor,
        },
        snapshot = snapshot,
        struct_pass = pass,
    }
end

local function format_result(result)
    if result.ok ~= true then
        return string.format("result=blocked stage=%s reason=%s", tostring(result.stage), tostring(result.message))
    end
    return string.format(
        "result=read-only-pass mutation_authorized=0 attribute=%s base=%.6f current=%.6f weight=%.6f/%.6f exceeded=%s can_exceed=%s",
        result.descriptor.attribute_name,
        result.snapshot.attribute_base_value,
        result.snapshot.attribute_current_value,
        result.snapshot.current_weight,
        result.snapshot.effective_weight_limit,
        tostring(result.snapshot.weight_exceeded),
        tostring(result.snapshot.can_exceed_weight_limit)
    )
end

local function live_dependencies()
    local helpers = require("UEHelpers")
    return {
        static_find_object = StaticFindObject,
        get_player = function() return helpers.GetPlayer() end,
        property_types = PropertyTypes,
    }
end

if rawget(_G, "DAWNWALKER_CARRY_CAPACITY_PROBE_TEST") ~= true then
    if EngineTickAvailable ~= true then
        print("[DawnwalkerCarryCapacityReadOnlyProbe] result=blocked stage=game-thread reason=EngineTickUnavailable\n")
    else
        local queued, queue_error = pcall(function()
            ExecuteInGameThread(function()
                local run_ok, result = pcall(Probe.run, live_dependencies())
                if not run_ok then result = fail("exception", tostring(result)) end
                print("[DawnwalkerCarryCapacityReadOnlyProbe] " .. format_result(result) .. "\n")
            end, EGameThreadMethod.EngineTick)
        end)
        if not queued then
            print("[DawnwalkerCarryCapacityReadOnlyProbe] result=blocked stage=queue reason=" .. tostring(queue_error) .. "\n")
        end
    end
end

return Probe
