local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_super_jump_descriptor_read_only_probe")

local Probe = {}

local EFFECT_CLASS_PATH = "/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_JumpIncrease.GE_WolfBoost_JumpIncrease_C"
local EFFECT_CDO_PATH = "/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_JumpIncrease.Default__GE_WolfBoost_JumpIncrease_C"
local ABILITY_SYSTEM_LIBRARY_CDO_PATH = "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"
local PLAYER_CONTROLLER_CLASS_PATH = "/Script/Dawnwalker.DawnwalkerPlayerControllerBase"
local PLAYER_CLASS_PATH = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local PLAYER_ASC_CLASS_PATH = "/Script/Dawnwalker.DawnwalkerAbilitySystemComponent"
local MOVEMENT_ATTRIBUTE_SET_CLASS_PATH = "/Script/DogwoodStats.PlayerMovementAttributeSet"
local ATTRIBUTE_NAME = "JumpVelocity"
local MAX_MODIFIERS = 16
local PROBE_ID = "player:super-jump-descriptor"

local function fail(stage, message)
    return {
        schema_version = 1,
        probe_id = PROBE_ID,
        evidence_class = "development-read-only",
        ok = false,
        mutation_authorized = false,
        release_visible = false,
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
    return math.abs(left - right) <= scale * 0.00001
end

local function is_valid(object)
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

local function object_address(object)
    if not is_valid(object) then return nil end
    local ok, address = pcall(function() return object:GetAddress() end)
    if not ok or not is_finite_number(address) or address <= 0 then return nil end
    return tostring(address)
end

local function full_name(object)
    if not is_valid(object) then return nil end
    local ok, name = pcall(function() return object:GetFullName() end)
    if not ok or type(name) ~= "string" then return nil end
    return name
end

local function has_exact_object_path(name, exact_path)
    if type(name) ~= "string" or type(exact_path) ~= "string" then return false end
    if name == exact_path then return true end
    if #name <= #exact_path or name:sub(-#exact_path) ~= exact_path then return false end
    return name:sub(#name - #exact_path, #name - #exact_path) == " "
end

local function as_string(value)
    if type(value) == "string" then return value end
    if value == nil then return nil end
    local ok, converted = pcall(function() return value:ToString() end)
    if not ok or type(converted) ~= "string" then return nil end
    return converted
end

local function class_matches(object, class_path)
    local ok, matches = pcall(function() return object:IsA(class_path) end)
    return ok and matches == true
end

local function unwrap_array_element(element)
    if element == nil then return nil end
    local ok, value = pcall(function() return element:get() end)
    if ok then return value end
    return element
end

local function bounded_array_values(container)
    if container == nil then return nil, nil, "the modifier container is unavailable" end

    local foreach_ok, foreach = pcall(function() return container.ForEach end)
    if foreach_ok and type(foreach) == "function" then
        local values = {}
        local walk_ok, walk_error = pcall(function()
            container:ForEach(function(_index, element)
                if #values >= MAX_MODIFIERS then error("the modifier array exceeds the bounded inspection limit") end
                local value = unwrap_array_element(element)
                if value == nil then error("a modifier array element was unavailable") end
                table.insert(values, value)
                return false
            end)
        end)
        if not walk_ok then return nil, nil, "the modifier ForEach ABI failed: " .. tostring(walk_error) end
        return values, "foreach", nil
    end

    local length_ok, length = pcall(function() return #container end)
    if not length_ok or not is_finite_number(length) or length < 0 or length % 1 ~= 0 then
        return nil, nil, "the modifier container exposes neither the ForEach nor indexed TArray ABI"
    end
    if length > MAX_MODIFIERS then return nil, nil, "the modifier array exceeds the bounded inspection limit" end

    local values = {}
    local walk_ok, walk_error = pcall(function()
        for index = 1, length do
            local value = unwrap_array_element(container[index])
            if value == nil then error("modifier index " .. tostring(index) .. " was unavailable") end
            table.insert(values, value)
        end
    end)
    if not walk_ok then return nil, nil, "the indexed modifier ABI failed: " .. tostring(walk_error) end
    return values, "indexed", nil
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

local function resolve_player_context(deps)
    local controller_ok, controller = pcall(deps.get_player_controller)
    if not controller_ok or not is_valid(controller) then return nil, "the local player controller is unavailable" end
    if not class_matches(controller, PLAYER_CONTROLLER_CLASS_PATH) then
        return nil, "the local controller is not ADawnwalkerPlayerControllerBase"
    end
    local local_ok, is_local = pcall(function() return controller:IsLocalPlayerController() end)
    if not local_ok or is_local ~= true then return nil, "the resolved player controller is not local" end

    local player_ok, player = pcall(deps.get_player)
    if not player_ok or not is_valid(player) then return nil, "the local player is unavailable" end
    if not class_matches(player, PLAYER_CLASS_PATH) then return nil, "the local pawn is not ADawnwalkerPlayerCharacter" end

    local possession_ok, k2_pawn, direct_pawn, possessed_character = pcall(function()
        return controller:K2_GetPawn(), controller.Pawn, controller.PossessedCharacter
    end)
    if not possession_ok then return nil, "the controller possession snapshot could not be read" end
    local player_address = object_address(player)
    if player_address == nil or object_address(k2_pawn) ~= player_address
        or object_address(direct_pawn) ~= player_address or object_address(possessed_character) ~= player_address then
        return nil, "K2_GetPawn, Pawn, PossessedCharacter, and the local-player resolver disagree"
    end

    local controller_links_ok, getter_controller, direct_controller = pcall(function()
        return player:GetController(), player.Controller
    end)
    local controller_address = object_address(controller)
    if not controller_links_ok or controller_address == nil
        or object_address(getter_controller) ~= controller_address or object_address(direct_controller) ~= controller_address then
        return nil, "the player's controller links disagree with the local controller"
    end

    local world_ok, world, controller_world = pcall(function()
        return player:GetWorld(), controller:GetWorld()
    end)
    if not world_ok or not is_valid(world) then return nil, "the player world is unavailable" end
    local world_address = object_address(world)
    if world_address == nil or object_address(controller_world) ~= world_address then
        return nil, "the controller and player worlds disagree"
    end
    local direct_ok, ability_system, movement_attributes = pcall(function()
        return player.AbilitySystemComponent, player.MovementAttributeSet
    end)
    if not direct_ok or not is_valid(ability_system) or not is_valid(movement_attributes) then
        return nil, "the direct player ASC or MovementAttributeSet is unavailable"
    end
    if not class_matches(ability_system, PLAYER_ASC_CLASS_PATH) then
        return nil, "the direct player ASC has the wrong class"
    end
    if not class_matches(movement_attributes, MOVEMENT_ATTRIBUTE_SET_CLASS_PATH) then
        return nil, "the direct MovementAttributeSet has the wrong class"
    end

    local asc_address = object_address(ability_system)
    local attribute_set_address = object_address(movement_attributes)
    if asc_address == nil or attribute_set_address == nil then
        return nil, "one or more player-context identities are unavailable"
    end
    local outer_ok, asc_outer, attribute_set_outer = pcall(function()
        return ability_system:GetOuter(), movement_attributes:GetOuter()
    end)
    if not outer_ok or object_address(asc_outer) ~= player_address or object_address(attribute_set_outer) ~= player_address then
        return nil, "the ASC or MovementAttributeSet is not outered to the exact player"
    end

    local library_ok, ability_library = pcall(deps.static_find_object, ABILITY_SYSTEM_LIBRARY_CDO_PATH)
    if not library_ok or not is_valid(ability_library)
        or not has_exact_object_path(full_name(ability_library), ABILITY_SYSTEM_LIBRARY_CDO_PATH) then
        return nil, "the AbilitySystemBlueprintLibrary CDO is unavailable"
    end
    local resolved_asc_ok, resolved_asc = pcall(function()
        return ability_library:GetAbilitySystemComponent(player)
    end)
    if not resolved_asc_ok or object_address(resolved_asc) ~= asc_address then
        return nil, "the direct and Blueprint-library ASC resolvers disagree"
    end

    local class_ok, attribute_set_class = pcall(deps.static_find_object, MOVEMENT_ATTRIBUTE_SET_CLASS_PATH)
    if not class_ok or not is_valid(attribute_set_class)
        or not has_exact_object_path(full_name(attribute_set_class), MOVEMENT_ATTRIBUTE_SET_CLASS_PATH) then
        return nil, "the exact PlayerMovementAttributeSet class is unavailable"
    end
    local attribute_set_class_address = object_address(attribute_set_class)
    if attribute_set_class_address == nil then return nil, "the PlayerMovementAttributeSet class identity is unavailable" end
    local resolved_set_ok, resolved_set = pcall(function()
        return ability_system:GetAttributeSet(attribute_set_class)
    end)
    if not resolved_set_ok or object_address(resolved_set) ~= attribute_set_address then
        return nil, "the direct and ASC MovementAttributeSet resolvers disagree"
    end

    return {
        controller = controller,
        player = player,
        world = world,
        ability_system = ability_system,
        movement_attributes = movement_attributes,
        ability_library = ability_library,
        controller_address = controller_address,
        player_address = player_address,
        world_address = world_address,
        asc_address = asc_address,
        attribute_set_address = attribute_set_address,
        attribute_set_class = attribute_set_class,
        attribute_set_class_address = attribute_set_class_address,
    }, nil
end

local function resolve_descriptor(deps, context)
    local class_ok, effect_class = pcall(deps.static_find_object, EFFECT_CLASS_PATH)
    if not class_ok or not is_valid(effect_class) or not has_exact_object_path(full_name(effect_class), EFFECT_CLASS_PATH) then
        return nil, "the exact loaded Wolf Boost jump-effect class is unavailable; the probe never loads assets"
    end
    local effect_class_address = object_address(effect_class)
    if effect_class_address == nil then return nil, "the Wolf Boost jump-effect class identity is unavailable" end
    local cdo_ok, effect_cdo = pcall(deps.static_find_object, EFFECT_CDO_PATH)
    if not cdo_ok or not is_valid(effect_cdo) or not has_exact_object_path(full_name(effect_cdo), EFFECT_CDO_PATH) then
        return nil, "the exact loaded Wolf Boost jump-effect CDO is unavailable; the probe never loads assets"
    end
    local cdo_address = object_address(effect_cdo)
    if cdo_address == nil then return nil, "the Wolf Boost jump-effect CDO identity is unavailable" end
    local class_cdo_ok, class_cdo = pcall(function() return effect_class:GetCDO() end)
    if not class_cdo_ok or object_address(class_cdo) ~= cdo_address then
        return nil, "the exact CDO path and effect-class CDO resolver disagree"
    end

    local modifiers_ok, modifiers = pcall(function() return effect_cdo.Modifiers end)
    if not modifiers_ok then return nil, "the Wolf Boost modifier array could not be read" end
    local values, iteration_abi, values_error = bounded_array_values(modifiers)
    if not values then return nil, values_error end
    if #values ~= 1 then
        return nil, "the Wolf Boost jump effect no longer has exactly one bounded modifier; observed " .. tostring(#values)
    end

    local descriptor_ok, descriptor = pcall(function() return values[1].Attribute end)
    if not descriptor_ok or descriptor == nil then return nil, "the sole modifier has no readable Attribute descriptor" end
    local name_ok, raw_name = pcall(function() return descriptor.AttributeName end)
    if not name_ok or as_string(raw_name) ~= ATTRIBUTE_NAME then
        return nil, "the sole modifier is not the JumpVelocity attribute"
    end
    local owner_ok, owner = pcall(function() return descriptor.AttributeOwner end)
    if not owner_ok or not is_valid(owner)
        or not has_exact_object_path(full_name(owner), MOVEMENT_ATTRIBUTE_SET_CLASS_PATH)
        or object_address(owner) ~= context.attribute_set_class_address then
        return nil, "the JumpVelocity descriptor owner is not PlayerMovementAttributeSet"
    end
    local descriptor_ok_address, descriptor_address = pcall(function() return descriptor:GetStructAddress() end)
    if not descriptor_ok_address or not is_finite_number(descriptor_address) or descriptor_address <= 0 then
        return nil, "the JumpVelocity descriptor has no stable struct address"
    end

    return {
        effect_class = effect_class,
        effect_cdo = effect_cdo,
        effect_class_address = effect_class_address,
        cdo_address = cdo_address,
        descriptor = descriptor,
        descriptor_address = tostring(descriptor_address),
        iteration_abi = iteration_abi,
        modifier_count = #values,
    }, nil
end

local function collect_read_only_evidence(context, descriptor_record)
    local data_ok, attribute_data = pcall(function() return context.movement_attributes.JumpVelocity end)
    if not data_ok or attribute_data == nil then return nil, "JumpVelocity GameplayAttributeData is unavailable" end
    local values_ok, base_value, current_value = pcall(function()
        return attribute_data.BaseValue, attribute_data.CurrentValue
    end)
    if not values_ok or not is_finite_number(base_value) or not is_finite_number(current_value) then
        return nil, "JumpVelocity base/current readback is invalid"
    end

    local debug_ok, debug_value = pcall(function()
        return context.ability_library:GetDebugStringFromGameplayAttribute(descriptor_record.descriptor)
    end)
    local debug_text = debug_ok and as_string(debug_value) or nil
    if debug_text == nil or debug_text:find(ATTRIBUTE_NAME, 1, true) == nil
        or debug_text:find("PlayerMovementAttributeSet", 1, true) == nil then
        return nil, "the descriptor failed the read-only gameplay-attribute debug-string check"
    end

    local value_ok, first, second, third = pcall(function()
        return context.ability_system:GetGameplayAttributeValue(descriptor_record.descriptor)
    end)
    if not value_ok then return nil, "GetGameplayAttributeValue rejected the borrowed descriptor: " .. tostring(first) end
    local asc_value, found = resolve_numeric_return(first, second, third)
    if asc_value == nil or not nearly_equal(asc_value, current_value) then
        return nil, "the ASC descriptor readback does not match JumpVelocity.CurrentValue"
    end
    if found == false then return nil, "GetGameplayAttributeValue reported that JumpVelocity was not found" end

    local count_ok, source_effect_count = pcall(function()
        return context.ability_system:GetGameplayEffectCount(descriptor_record.effect_class, nil, false)
    end)
    if not count_ok or not is_finite_number(source_effect_count) or source_effect_count < 0
        or source_effect_count % 1 ~= 0 then
        return nil, "the active Wolf Boost source-effect count is invalid"
    end

    return {
        base_value = base_value,
        current_value = current_value,
        asc_value = asc_value,
        found = found,
        debug_text = debug_text,
        source_effect_count = source_effect_count,
    }, nil
end

local function identities_remain_stable(deps, context, descriptor_record)
    local stable_context = resolve_player_context(deps)
    if not stable_context then return false end
    if stable_context.controller_address ~= context.controller_address
        or stable_context.player_address ~= context.player_address
        or stable_context.world_address ~= context.world_address
        or stable_context.asc_address ~= context.asc_address
        or stable_context.attribute_set_address ~= context.attribute_set_address
        or stable_context.attribute_set_class_address ~= context.attribute_set_class_address then
        return false
    end
    local stable_descriptor = resolve_descriptor(deps, stable_context)
    return stable_descriptor ~= nil
        and stable_descriptor.effect_class_address == descriptor_record.effect_class_address
        and stable_descriptor.cdo_address == descriptor_record.cdo_address
        and stable_descriptor.descriptor_address == descriptor_record.descriptor_address
end

function Probe.run(deps)
    if type(deps) ~= "table" or type(deps.static_find_object) ~= "function"
        or type(deps.get_player) ~= "function" or type(deps.get_player_controller) ~= "function" then
        return fail("dependencies", "the read-only probe dependencies are incomplete")
    end

    local context, context_error = resolve_player_context(deps)
    if not context then return fail("player-context", context_error) end
    local descriptor, descriptor_error = resolve_descriptor(deps, context)
    if not descriptor then return fail("descriptor", descriptor_error) end
    local evidence, evidence_error = collect_read_only_evidence(context, descriptor)
    if not evidence then return fail("readback", evidence_error) end
    if not identities_remain_stable(deps, context, descriptor) then
        return fail("identity-stability", "the controller, player, world, ASC, attribute set, effect source, or descriptor changed during the probe")
    end

    return {
        schema_version = 1,
        probe_id = PROBE_ID,
        evidence_class = "development-read-only",
        ok = true,
        mutation_authorized = false,
        release_visible = false,
        stage = "read-only-complete",
        message = "The exact JumpVelocity descriptor passed bounded read-only identity and value checks. No mutation API was invoked.",
        source = {
            class_path = EFFECT_CLASS_PATH,
            class_address = descriptor.effect_class_address,
            cdo_address = descriptor.cdo_address,
            modifier_count = descriptor.modifier_count,
            iteration_abi = descriptor.iteration_abi,
        },
        descriptor = {
            attribute_name = ATTRIBUTE_NAME,
            attribute_owner = MOVEMENT_ATTRIBUTE_SET_CLASS_PATH,
            struct_address = descriptor.descriptor_address,
        },
        identity = {
            controller_address = context.controller_address,
            player_address = context.player_address,
            world_address = context.world_address,
            asc_address = context.asc_address,
            attribute_set_address = context.attribute_set_address,
            attribute_set_class_address = context.attribute_set_class_address,
            asc_crosscheck = true,
            attribute_set_crosscheck = true,
        },
        readback = evidence,
    }
end

function Probe.format_result(result)
    if type(result) ~= "table" or result.ok ~= true then
        local stage = type(result) == "table" and tostring(result.stage or "unknown") or "unknown"
        return "schema_version=1;probe_id=" .. PROBE_ID
            .. ";evidence_class=development-read-only;passed=0;mutation_authorized=0;release_visible=0;stage=" .. stage
    end
    return table.concat({
        "schema_version=1",
        "probe_id=" .. PROBE_ID,
        "evidence_class=development-read-only",
        "passed=1",
        "mutation_authorized=0",
        "release_visible=0",
        "stage=read-only-complete",
        "source_path=" .. result.source.class_path,
        "source_class_address=" .. result.source.class_address,
        "source_cdo_address=" .. result.source.cdo_address,
        "modifier_count=" .. tostring(result.source.modifier_count),
        "iteration_abi=" .. result.source.iteration_abi,
        "attribute_name=" .. result.descriptor.attribute_name,
        "attribute_owner=" .. result.descriptor.attribute_owner,
        "descriptor_address=" .. result.descriptor.struct_address,
        "controller_address=" .. result.identity.controller_address,
        "player_address=" .. result.identity.player_address,
        "world_address=" .. result.identity.world_address,
        "asc_address=" .. result.identity.asc_address,
        "attribute_set_address=" .. result.identity.attribute_set_address,
        "attribute_set_class_address=" .. result.identity.attribute_set_class_address,
        "asc_crosscheck=1",
        "attribute_set_crosscheck=1",
        "base_value=" .. string.format("%.6f", result.readback.base_value),
        "current_value=" .. string.format("%.6f", result.readback.current_value),
        "asc_value=" .. string.format("%.6f", result.readback.asc_value),
        "source_effect_count=" .. tostring(result.readback.source_effect_count),
        "found_flag=" .. (result.readback.found == true and "explicit" or "not-returned"),
        "debug_verified=1",
    }, ";")
end

return Probe
