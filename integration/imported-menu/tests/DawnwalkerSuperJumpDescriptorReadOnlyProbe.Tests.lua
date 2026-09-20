local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_super_jump_descriptor_read_only_probe_tests")

local probe_path = assert(arg[1], "Expected the Super Jump probe source path as argument 1.")

local EFFECT_CLASS_PATH = "/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_JumpIncrease.GE_WolfBoost_JumpIncrease_C"
local EFFECT_CDO_PATH = "/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_JumpIncrease.Default__GE_WolfBoost_JumpIncrease_C"
local ABILITY_SYSTEM_LIBRARY_CDO_PATH = "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"
local PLAYER_CONTROLLER_CLASS_PATH = "/Script/Dawnwalker.DawnwalkerPlayerControllerBase"
local PLAYER_CLASS_PATH = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local PLAYER_ASC_CLASS_PATH = "/Script/Dawnwalker.DawnwalkerAbilitySystemComponent"
local MOVEMENT_ATTRIBUTE_SET_CLASS_PATH = "/Script/DogwoodStats.PlayerMovementAttributeSet"

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
    "%.BaseValue%s*=",
    "%.CurrentValue%s*=",
    "%.JumpZVelocity%s*=",
    "StaticLoadObject%s*%(",
    "LoadAsset%s*%(",
    "ExecuteInGameThread%s*%(",
    "LoopAsync%s*%(",
}) do
    assert_equal(probe_source:find(forbidden_pattern), nil, "probe excludes mutation or activation pattern " .. forbidden_pattern)
end
assert_match(probe_source, "GE_WolfBoost_JumpIncrease", "exact descriptor source")
assert_match(probe_source, "controller:K2_GetPawn%(%)", "controller-first possessed-pawn resolver")
assert_match(probe_source, "controller%.PossessedCharacter", "Dawnwalker possession crosscheck")
assert_match(probe_source, "player:GetController%(%)", "player-to-controller crosscheck")
assert_match(probe_source, "GetAbilitySystemComponent%(player%)", "independent ASC resolver")
assert_match(probe_source, "ability_system:GetAttributeSet%(attribute_set_class%)", "independent attribute-set resolver")
assert_match(probe_source, "GetDebugStringFromGameplayAttribute", "read-only descriptor debug call")
assert_match(probe_source, "GetGameplayAttributeValue", "read-only descriptor value call")
assert_match(probe_source, "mutation_authorized%s*=%s*false", "explicit mutation denial")

local Probe = assert(dofile(probe_path))

local function string_value(value)
    return { ToString = function() return value end }
end

local function make_object(address, full_object_name, class_paths)
    local object = {
        _valid = true,
        _address = address,
        _full_name = full_object_name,
        _class_paths = class_paths or {},
    }
    function object:IsValid() return self._valid end
    function object:GetAddress() return self._address end
    function object:GetFullName() return self._full_name end
    function object:IsA(class_path) return self._class_paths[class_path] == true end
    return object
end

local function make_foreach_array(values)
    local array = {}
    function array:ForEach(callback)
        for index, value in ipairs(values) do
            callback(index, { get = function() return value end })
        end
    end
    return array
end

local function make_indexed_array(values)
    return setmetatable({}, {
        __len = function() return #values end,
        __index = function(_, index)
            if type(index) ~= "number" then return nil end
            local value = values[index]
            if value == nil then return nil end
            return { get = function() return value end }
        end,
    })
end

local function make_environment(options)
    options = options or {}
    local calls = {
        get_player = 0,
        asc_resolve = 0,
        attribute_set_resolve = 0,
        debug = 0,
        attribute_read = 0,
        mutation = 0,
        asset_load = 0,
    }

    local world = make_object(2001, "World /Game/Test.Test:PersistentLevel")
    local ability_system = make_object(2002, "DawnwalkerAbilitySystemComponent /Game/Test.Player.ASC", {
        [PLAYER_ASC_CLASS_PATH] = true,
    })
    local movement_attributes = make_object(2003, "PlayerMovementAttributeSet /Game/Test.Player.MovementAttributeSet", {
        [MOVEMENT_ATTRIBUTE_SET_CLASS_PATH] = true,
    })
    movement_attributes.JumpVelocity = {
        BaseValue = options.base_value or 600.0,
        CurrentValue = options.current_value or 660.0,
    }

    local alternate_asc = make_object(2902, "DawnwalkerAbilitySystemComponent /Game/Test.Other.ASC", {
        [PLAYER_ASC_CLASS_PATH] = true,
    })
    local alternate_attributes = make_object(2903, "PlayerMovementAttributeSet /Game/Test.Other.MovementAttributeSet", {
        [MOVEMENT_ATTRIBUTE_SET_CLASS_PATH] = true,
    })

    local player = make_object(2004, "BP_PlayerCharacter_C /Game/Test.Player", {
        [PLAYER_CLASS_PATH] = options.wrong_player_class ~= true,
    })
    local controller = make_object(2010, "BP_PlayerController_C /Game/Test.Controller", {
        [PLAYER_CONTROLLER_CLASS_PATH] = options.wrong_controller_class ~= true,
    })
    function controller:IsLocalPlayerController() return options.nonlocal_controller ~= true end
    function controller:GetWorld()
        if options.world_mismatch then return make_object(2910, "World /Game/Test.OtherWorld") end
        return world
    end
    function controller:K2_GetPawn()
        if options.pawn_mismatch then return make_object(2911, "BP_PlayerCharacter_C /Game/Test.OtherPawn", { [PLAYER_CLASS_PATH] = true }) end
        return player
    end
    controller.Pawn = options.pawn_property_mismatch
        and make_object(2912, "BP_PlayerCharacter_C /Game/Test.OtherPawnProperty", { [PLAYER_CLASS_PATH] = true }) or player
    controller.PossessedCharacter = options.possessed_character_mismatch
        and make_object(2913, "BP_PlayerCharacter_C /Game/Test.OtherPossessedCharacter", { [PLAYER_CLASS_PATH] = true }) or player
    player.AbilitySystemComponent = ability_system
    player.MovementAttributeSet = movement_attributes
    function player:GetWorld() return world end
    function player:GetController()
        if options.controller_link_mismatch then
            return make_object(2914, "BP_PlayerController_C /Game/Test.OtherController", { [PLAYER_CONTROLLER_CLASS_PATH] = true })
        end
        return controller
    end
    player.Controller = controller
    function ability_system:GetOuter()
        if options.outer_mismatch then return world end
        return player
    end
    function movement_attributes:GetOuter() return player end

    local resolved_player = player
    local ability_library = make_object(2005, "AbilitySystemBlueprintLibrary " .. ABILITY_SYSTEM_LIBRARY_CDO_PATH)
    function ability_library:GetAbilitySystemComponent(received)
        calls.asc_resolve = calls.asc_resolve + 1
        assert_equal(received, player, "ability-library player identity")
        return options.asc_mismatch and alternate_asc or ability_system
    end

    local attribute_set_class = make_object(2006, "Class " .. MOVEMENT_ATTRIBUTE_SET_CLASS_PATH)
    function ability_system:GetAttributeSet(received)
        calls.attribute_set_resolve = calls.attribute_set_resolve + 1
        assert_equal(received, attribute_set_class, "attribute-set class identity")
        return options.attribute_set_mismatch and alternate_attributes or movement_attributes
    end

    local attribute_owner = options.wrong_owner
        and make_object(2007, "Class /Script/DogwoodStats.CharacterBaseAttributeSet") or attribute_set_class
    local descriptor = {
        AttributeName = string_value(options.wrong_name and "MaxSpeedModifier" or "JumpVelocity"),
        AttributeOwner = attribute_owner,
        GetStructAddress = function() return options.invalid_descriptor_address and 0 or 7001 end,
    }
    local modifier = { Attribute = descriptor }
    local modifiers = { modifier }
    if options.extra_modifier then table.insert(modifiers, modifier) end
    local modifier_container = options.indexed_abi and make_indexed_array(modifiers) or make_foreach_array(modifiers)

    local effect_cdo = make_object(2008, "GE_WolfBoost_JumpIncrease_C " .. EFFECT_CDO_PATH)
    effect_cdo.Modifiers = modifier_container
    local effect_class = make_object(2009, "BlueprintGeneratedClass " .. EFFECT_CLASS_PATH)
    local replacement_class = make_object(2996, "BlueprintGeneratedClass " .. EFFECT_CLASS_PATH)
    local replacement_cdo = make_object(2999, "GE_WolfBoost_JumpIncrease_C " .. EFFECT_CDO_PATH)
    replacement_cdo.Modifiers = modifier_container
    local resolved_cdo = effect_cdo
    function effect_class:GetCDO()
        return resolved_cdo
    end
    function replacement_class:GetCDO()
        return resolved_cdo
    end

    function ability_library:GetDebugStringFromGameplayAttribute(received)
        calls.debug = calls.debug + 1
        assert_equal(received, descriptor, "debug descriptor identity")
        if options.debug_failure then error("synthetic debug failure") end
        if options.wrong_debug then return "PlayerMovementAttributeSet.MaxSpeedModifier" end
        return "PlayerMovementAttributeSet.JumpVelocity"
    end
    function ability_system:GetGameplayAttributeValue(received, output)
        calls.attribute_read = calls.attribute_read + 1
        assert_equal(received, descriptor, "ASC descriptor identity")
        assert_equal(type(output), "table", "Required bFound out parameter")
        if options.attribute_read_failure then error("synthetic attribute failure") end
        if not options.found_missing then output.bFound = options.found_false ~= true end
        return options.asc_value or movement_attributes.JumpVelocity.CurrentValue
    end
    function ability_system:GetGameplayEffectCount(received_class, source, include_predicted)
        assert_equal(received_class, effect_class, "source-effect class identity")
        assert_equal(source, nil, "source-effect optional source")
        assert_equal(include_predicted, false, "source-effect predicted flag")
        return options.source_effect_count or 0
    end
    function ability_system:SetAttributeValue()
        calls.mutation = calls.mutation + 1
        error("the read-only probe invoked a setter")
    end
    function ability_system:BP_ApplyGameplayEffectToSelf()
        calls.mutation = calls.mutation + 1
        error("the read-only probe applied an effect")
    end

    local objects = {
        [ABILITY_SYSTEM_LIBRARY_CDO_PATH] = ability_library,
        [MOVEMENT_ATTRIBUTE_SET_CLASS_PATH] = attribute_set_class,
        [EFFECT_CLASS_PATH] = effect_class,
        [EFFECT_CDO_PATH] = effect_cdo,
    }
    if options.effect_missing then objects[EFFECT_CLASS_PATH] = nil end
    local deps = {
        static_find_object = function(path)
            if path ~= EFFECT_CLASS_PATH and path ~= EFFECT_CDO_PATH
                and path ~= ABILITY_SYSTEM_LIBRARY_CDO_PATH and path ~= MOVEMENT_ATTRIBUTE_SET_CLASS_PATH then
                calls.asset_load = calls.asset_load + 1
            end
            if path == EFFECT_CDO_PATH and options.cdo_identity_changed then
                calls.cdo_lookup = (calls.cdo_lookup or 0) + 1
                if calls.cdo_lookup > 1 then
                    resolved_cdo = replacement_cdo
                    return replacement_cdo
                end
            end
            if path == EFFECT_CLASS_PATH and options.class_identity_changed then
                calls.class_lookup = (calls.class_lookup or 0) + 1
                if calls.class_lookup > 1 then return replacement_class end
            end
            return objects[path]
        end,
        get_player_controller = function()
            if options.controller_identity_changed and calls.get_player >= 1 then
                return make_object(2997, "BP_PlayerController_C /Game/Test.ReplacedController", {
                    [PLAYER_CONTROLLER_CLASS_PATH] = true,
                })
            end
            return controller
        end,
        get_player = function()
            calls.get_player = calls.get_player + 1
            if options.player_identity_changed and calls.get_player > 1 then
                return make_object(2998, "BP_PlayerCharacter_C /Game/Test.ReplacedPlayer", { [PLAYER_CLASS_PATH] = true })
            end
            return resolved_player
        end,
    }
    return deps, calls
end

local deps, calls = make_environment()
local result = Probe.run(deps)
assert_true(result.ok, "valid descriptor probe")
assert_equal(result.stage, "read-only-complete", "valid completion stage")
assert_equal(result.mutation_authorized, false, "successful probe never authorizes mutation")
assert_equal(result.source.class_path, EFFECT_CLASS_PATH, "exact effect source")
assert_equal(result.source.class_address, "2009", "exact effect-class identity")
assert_equal(result.source.modifier_count, 1, "exact modifier count")
assert_equal(result.source.iteration_abi, "foreach", "documented property-array ABI")
assert_equal(result.descriptor.attribute_name, "JumpVelocity", "exact attribute name")
assert_equal(result.descriptor.attribute_owner, MOVEMENT_ATTRIBUTE_SET_CLASS_PATH, "exact attribute owner")
assert_equal(result.identity.asc_crosscheck, true, "ASC crosscheck")
assert_equal(result.identity.attribute_set_crosscheck, true, "attribute-set crosscheck")
assert_equal(result.readback.base_value, 600.0, "base-value readback")
assert_equal(result.readback.current_value, 660.0, "current-value readback")
assert_equal(result.readback.asc_value, 660.0, "ASC value readback")
assert_equal(result.readback.found, true, "explicit found flag")
assert_equal(result.readback.source_effect_count, 0, "read-only source-effect count")
assert_equal(calls.mutation, 0, "zero mutation calls")
assert_equal(calls.asset_load, 0, "zero asset-load calls")
assert_true(calls.get_player >= 2, "identity was rechecked")

local formatted = Probe.format_result(result)
assert_match(formatted, "^schema_version=1;probe_id=player:super%-jump%-descriptor;evidence_class=development%-read%-only;passed=1;mutation_authorized=0;release_visible=0;stage=read%-only%-complete;", "structured success evidence")
assert_match(formatted, "source_path=/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_JumpIncrease", "structured source")
assert_match(formatted, "source_class_address=2009;source_cdo_address=2008", "structured source identities")
assert_match(formatted, "modifier_count=1;iteration_abi=foreach;attribute_name=JumpVelocity", "structured descriptor evidence")
assert_match(formatted, "base_value=600%.000000;current_value=660%.000000;asc_value=660%.000000", "structured numeric evidence")
assert_match(formatted, "source_effect_count=0", "structured source-effect evidence")

local indexed_result = Probe.run((make_environment({ indexed_abi = true })))
assert_true(indexed_result.ok, "indexed TArray ABI fallback")
assert_equal(indexed_result.source.iteration_abi, "indexed", "indexed ABI evidence")

local wrong_name = Probe.run((make_environment({ wrong_name = true })))
assert_equal(wrong_name.ok, false, "wrong attribute rejected")
assert_equal(wrong_name.stage, "descriptor", "wrong attribute rejection stage")
assert_equal(wrong_name.mutation_authorized, false, "wrong attribute stays read-only")

local wrong_owner = Probe.run((make_environment({ wrong_owner = true })))
assert_equal(wrong_owner.ok, false, "wrong owner rejected")
assert_equal(wrong_owner.stage, "descriptor", "wrong owner rejection stage")

local extra_modifier = Probe.run((make_environment({ extra_modifier = true })))
assert_equal(extra_modifier.ok, false, "extra modifier rejected")
assert_equal(extra_modifier.stage, "descriptor", "extra modifier rejection stage")

local asc_mismatch = Probe.run((make_environment({ asc_mismatch = true })))
assert_equal(asc_mismatch.ok, false, "ASC resolver mismatch rejected")
assert_equal(asc_mismatch.stage, "player-context", "ASC mismatch stage")

local set_mismatch = Probe.run((make_environment({ attribute_set_mismatch = true })))
assert_equal(set_mismatch.ok, false, "attribute-set resolver mismatch rejected")
assert_equal(set_mismatch.stage, "player-context", "attribute-set mismatch stage")

local wrong_controller = Probe.run((make_environment({ wrong_controller_class = true })))
assert_equal(wrong_controller.ok, false, "wrong controller class rejected")
assert_equal(wrong_controller.stage, "player-context", "wrong controller class stage")

local nonlocal_controller = Probe.run((make_environment({ nonlocal_controller = true })))
assert_equal(nonlocal_controller.ok, false, "nonlocal controller rejected")
assert_equal(nonlocal_controller.stage, "player-context", "nonlocal controller stage")

local pawn_mismatch = Probe.run((make_environment({ pawn_mismatch = true })))
assert_equal(pawn_mismatch.ok, false, "controller pawn disagreement rejected")
assert_equal(pawn_mismatch.stage, "player-context", "controller pawn disagreement stage")

local possessed_mismatch = Probe.run((make_environment({ possessed_character_mismatch = true })))
assert_equal(possessed_mismatch.ok, false, "PossessedCharacter disagreement rejected")
assert_equal(possessed_mismatch.stage, "player-context", "PossessedCharacter disagreement stage")

local world_mismatch = Probe.run((make_environment({ world_mismatch = true })))
assert_equal(world_mismatch.ok, false, "controller/world disagreement rejected")
assert_equal(world_mismatch.stage, "player-context", "controller/world disagreement stage")

local outer_mismatch = Probe.run((make_environment({ outer_mismatch = true })))
assert_equal(outer_mismatch.ok, false, "ASC outer disagreement rejected")
assert_equal(outer_mismatch.stage, "player-context", "ASC outer disagreement stage")

local stale_value = Probe.run((make_environment({ asc_value = 777.0 })))
assert_equal(stale_value.ok, false, "inconsistent effective value rejected")
assert_equal(stale_value.stage, "readback", "inconsistent effective value stage")

local invalid_effect_count = Probe.run((make_environment({ source_effect_count = -1 })))
assert_equal(invalid_effect_count.ok, false, "invalid source-effect count rejected")
assert_equal(invalid_effect_count.stage, "readback", "invalid source-effect count stage")

local missing_effect = Probe.run((make_environment({ effect_missing = true })))
assert_equal(missing_effect.ok, false, "missing loaded effect rejected")
assert_equal(missing_effect.stage, "descriptor", "missing effect stage")

local changed_player = Probe.run((make_environment({ player_identity_changed = true })))
assert_equal(changed_player.ok, false, "mid-probe player replacement rejected")
assert_equal(changed_player.stage, "identity-stability", "mid-probe replacement stage")

local changed_cdo = Probe.run((make_environment({ cdo_identity_changed = true })))
assert_equal(changed_cdo.ok, false, "mid-probe effect CDO replacement rejected")
assert_equal(changed_cdo.stage, "identity-stability", "mid-probe CDO replacement stage")

local changed_class = Probe.run((make_environment({ class_identity_changed = true })))
assert_equal(changed_class.ok, false, "mid-probe effect-class replacement rejected")
assert_equal(changed_class.stage, "identity-stability", "mid-probe effect-class replacement stage")

local changed_controller = Probe.run((make_environment({ controller_identity_changed = true })))
assert_equal(changed_controller.ok, false, "mid-probe controller replacement rejected")
assert_equal(changed_controller.stage, "identity-stability", "mid-probe controller replacement stage")

local found_false = Probe.run((make_environment({ found_false = true })))
assert_equal(found_false.ok, false, "explicit missing attribute rejected")
assert_equal(found_false.stage, "readback", "explicit missing attribute stage")
local found_missing = Probe.run((make_environment({ found_missing = true })))
assert_equal(found_missing.ok, false, "missing out parameter rejected")

local blocked_format = Probe.format_result(found_false)
assert_equal(blocked_format, "schema_version=1;probe_id=player:super-jump-descriptor;evidence_class=development-read-only;passed=0;mutation_authorized=0;release_visible=0;stage=readback", "structured blocked evidence")

print("Dawnwalker Super Jump descriptor read-only probe harness passed.")
