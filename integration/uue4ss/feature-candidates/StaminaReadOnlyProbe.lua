local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_stamina_read_only_probe")

-- Current-build native getter candidate only. No setters, effects, asset loads,
-- hooks, automatic execution, or capability registration.
local Probe = {}
local PLAYER = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local ATTRIBUTES = "/Script/DogwoodStats.PlayerAttributeSet"
local DEVELOPMENT = "/Script/DogwoodStats.CharDevAttributeSet"
local LIBRARY = "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"
local SPECS = {
    { name = "SprintStaminaCostMultiplier", channel = "sprint", owner = ATTRIBUTES, property = "CharacterAttributeSet" },
    { name = "DodgeStaminaCostMultiplier", channel = "dodge", owner = ATTRIBUTES, property = "CharacterAttributeSet" },
    { name = "OmniblockStaminaCostMultiplier", channel = "omniblock", owner = DEVELOPMENT, property = "CharDevAttributeSet" },
    { name = "DirectionalBlockStaminaRestoreMultiplier", channel = "directional_block_restore_multiplier", owner = DEVELOPMENT, property = "CharDevAttributeSet" },
    { name = "DirectionalBlockStaminaRestoreModifier", channel = "directional_block_restore_modifier", owner = DEVELOPMENT, property = "CharDevAttributeSet" },
}

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function near(left, right)
    return finite(left) and finite(right) and math.abs(left - right) <= 0.00001 * math.max(1, math.abs(right))
end

local function object_record(object, class, label, allow_default)
    require_condition(object ~= nil and object:IsValid() == true and object:IsA(class) == true,
        label .. " is unavailable or has an unexpected class")
    local name, address = object:GetFullName(), object:GetAddress()
    require_condition(type(name) == "string" and #name > 0 and #name <= 1024
        and finite(address) and address > 0, label .. " identity is invalid")
    require_condition(allow_default == true or not name:find("Default__", 1, true), label .. " is a default object")
    return { name = name, address = tostring(address), identity = name .. "@" .. tostring(address) }
end

local function unwrap(value)
    local ok, entry = pcall(function() return value:get() end)
    return ok and entry or value
end

local function array_entries(array)
    local ok, count = pcall(function() return array:GetArrayNum() end)
    if not ok then ok, count = pcall(function() return #array end) end
    require_condition(ok and finite(count) and count % 1 == 0 and count > 0 and count <= 1024,
        "Native descriptor array is empty or exceeds its bound")
    local entries = {}
    for index = 1, count do
        local value = unwrap(array[index])
        require_condition(value ~= nil, "Native descriptor array has a missing entry")
        entries[index] = value
    end
    return entries
end

local function context(deps)
    require_condition(deps.is_in_game_thread() == true, "Stamina probe requires the game thread")
    local identity = deps.get_identity()
    require_condition(type(identity) == "table" and identity.build_id == "25129649"
        and identity.executable_sha256 == "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
        and identity.metadata_sha256 == "CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6"
        and type(identity.boot_id) == "string" and #identity.boot_id > 0,
        "Exact current-build/session attestation is missing")
    local player = deps.get_player()
    local player_record = object_record(player, PLAYER, "local player")
    local controller = deps.get_player_controller()
    object_record(controller, "/Script/Engine.PlayerController", "local controller")
    require_condition(controller:IsLocalController() == true
        and object_record(controller:K2_GetPawn(), PLAYER, "controller pawn").identity == player_record.identity,
        "Local controller and player disagree")
    local world_record = object_record(player:GetWorld(), "/Script/Engine.World", "player world")
    local asc = player.AbilitySystemComponent
    local asc_record = object_record(asc, "/Script/GameplayAbilities.AbilitySystemComponent", "player ability system")
    require_condition(object_record(asc:GetOwner(), PLAYER, "ability system owner").identity == player_record.identity,
        "Ability system belongs to another actor")
    local attribute_record = object_record(player.CharacterAttributeSet, ATTRIBUTES, "player attribute set")
    local development_record = object_record(player.CharDevAttributeSet, DEVELOPMENT, "development attribute set")
    local vampire = player:IsVampire()
    require_condition(type(vampire) == "boolean", "Character form readback is invalid")
    return { player = player, asc = asc, player_record = player_record, world_record = world_record,
        asc_record = asc_record, vampire = vampire,
        identity = table.concat({ identity.boot_id, player_record.identity, world_record.identity, asc_record.identity,
            attribute_record.identity, development_record.identity, tostring(vampire) }, "|") }
end

local function property_pair(set, name)
    local attribute = set[name]
    require_condition(attribute ~= nil and finite(attribute.BaseValue) and finite(attribute.CurrentValue),
        name .. " base/current observation is invalid")
    return { base = attribute.BaseValue, current = attribute.CurrentValue }
end

local function getter_report(call, expected)
    local result = { verified = false }
    local ok, values = pcall(function() return table.pack(call()) end)
    if not ok then result.reason = tostring(values); return result end
    result.return_count, result.return_types = values.n, {}
    for index = 1, values.n do result.return_types[index] = type(values[index]) end
    if finite(values[1]) then result.value = values[1] end
    if type(values[2]) == "boolean" then result.found = values[2] end
    if values.n ~= 2 or not finite(values[1]) or type(values[2]) ~= "boolean" then
        result.reason = "Getter return/out-bool marshaling is unverified; expected exactly number, boolean"
    elseif values[2] ~= true then
        result.reason = "Native getter did not find the attribute"
    elseif not near(values[1], expected) then
        result.reason = "Native getter disagrees with the attribute property's captured value"
    else
        result.verified = true
    end
    return result
end

local function descriptor_name(descriptor)
    local name = descriptor.AttributeName
    if type(name) ~= "string" then name = name:ToString() end
    require_condition(type(name) == "string" and #name > 0 and #name <= 256, "Native descriptor name is invalid")
    return name
end

local function observe_attribute(current, spec, descriptor, library)
    local owner = current.player[spec.property]
    local before = property_pair(owner, spec.name)
    require_condition(descriptor ~= nil, "No native descriptor found for " .. spec.name)
    require_condition(descriptor:type() == "UScriptStruct" and descriptor:IsValid() == true,
        "Native gameplay-attribute descriptor is not a valid UScriptStruct")
    local struct_address = descriptor:GetStructAddress()
    require_condition(finite(struct_address) and struct_address > 0, "Native descriptor address is invalid")
    local descriptor_owner = descriptor.AttributeOwner
    local owner_type = object_record(descriptor_owner, "/Script/CoreUObject.Class", "native attribute owner type")
    require_condition(owner_type.name == "Class " .. spec.owner, "Native descriptor belongs to the wrong attribute owner type")
    local asc_set = current.asc:GetAttributeSet(descriptor_owner)
    require_condition(object_record(asc_set, spec.owner, "ASC attribute set").identity
        == object_record(owner, spec.owner, "player attribute set property").identity,
        "ASC native attribute set and player property disagree")
    local debug_string = library:GetDebugStringFromGameplayAttribute(descriptor)
    if type(debug_string) ~= "string" then debug_string = debug_string:ToString() end
    require_condition(type(debug_string) == "string" and debug_string:find(spec.name, 1, true) ~= nil,
        "Native descriptor debug readback disagrees with its name")
    local effective = getter_report(function() return current.asc:GetGameplayAttributeValue(descriptor) end, before.current)
    local base = getter_report(function()
        return library:GetFloatAttributeBaseFromAbilitySystemComponent(current.asc, descriptor)
    end, before.base)
    local after = property_pair(owner, spec.name)
    require_condition(near(before.base, after.base) and near(before.current, after.current)
        and descriptor_name(descriptor) == spec.name and descriptor:GetStructAddress() == struct_address,
        "Attribute or native descriptor changed during getter observations")
    return { channel = spec.channel, attribute = spec.name, attribute_owner_type = owner_type,
        descriptor_address = tostring(struct_address), property = before, native_effective = effective, native_base = base,
        getter_verified = effective.verified and base.verified,
        semantic_scope = spec.channel:find("directional_block", 1, true)
            and "restoration attribute; not a directional block cost contract" or "cost multiplier semantics require gameplay evidence" }
end

local function combat_observations(current)
    local combat = current.player.CombatComponent
    local combat_record = object_record(combat, "/Script/DogwoodCombat.PlayerCombatComponent", "player combat")
    require_condition(object_record(combat:GetOwner(), PLAYER, "combat owner").identity == current.player_record.identity,
        "Combat component belongs to another actor")
    local config = combat:GetConfig()
    local config_record = object_record(config, "/Script/DogwoodCombat.CombatConfig", "combat config")
    require_condition(object_record(combat.Config, "/Script/DogwoodCombat.CombatConfig", "combat config property").identity
        == config_record.identity, "Combat config getter and property disagree")
    local dodge_cost = combat:GetDodgeStaminaCost()
    require_condition(finite(dodge_cost) and dodge_cost >= 0, "Native dodge-cost getter is invalid")
    local records = {}
    for _, name in ipairs({ "StaminaDamageEffectClass", "OmniblockStaminaDamageEffectClass", "BlockStaminaRegenEffectClass" }) do
        records[name] = object_record(config[name], "/Script/CoreUObject.Class", name)
    end
    records.CombatActionStaminaCosts = object_record(config.CombatActionStaminaCosts, "/Script/Engine.DataTable", "combat stamina-cost table")
    return { combat = combat_record, config = config_record, dodge_cost = dodge_cost,
        provenance = records, limitation = "Loaded class/table identities only; directional-block cost rows and effect formulas are not decoded." }
end

local function section(run)
    local ok, value = pcall(run)
    return ok and { ok = true, observations = value } or { ok = false, reason = tostring(value) }
end

function Probe.run(deps)
    local result = { ok = false, mutation_authorized = false, gameplay_verified = false, capabilities = {} }
    local ok, failure = pcall(function()
        for _, name in ipairs({ "get_identity", "is_in_game_thread", "get_player", "get_player_controller", "static_find_object" }) do
            require_condition(type(deps) == "table" and type(deps[name]) == "function", "Missing probe dependency: " .. name)
        end
        local current = context(deps)
        result.context_identity, result.player, result.world, result.ability_system, result.is_vampire =
            current.identity, current.player_record, current.world_record, current.asc_record, current.vampire
        local library = deps.static_find_object(LIBRARY)
        object_record(library, "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary", "attribute library", true)
        local native_array = {}
        current.asc:GetAllAttributes(native_array)
        local descriptors, duplicate = {}, {}
        local wanted = {}
        for _, spec in ipairs(SPECS) do wanted[spec.name] = true end
        local entries = array_entries(native_array)
        result.native_descriptor_count = #entries
        for _, descriptor in ipairs(entries) do
            local name = descriptor_name(descriptor)
            if wanted[name] then
                if descriptors[name] then duplicate[name] = true end
                descriptors[name] = descriptor
            end
        end
        result.channels = {}
        for _, spec in ipairs(SPECS) do
            result.channels[spec.channel] = section(function()
                require_condition(not duplicate[spec.name], "Duplicate native descriptor: " .. spec.name)
                return observe_attribute(current, spec, descriptors[spec.name], library)
            end)
        end
        result.combat = section(function() return combat_observations(current) end)
        for _, spec in ipairs(SPECS) do
            local entry = result.channels[spec.channel]
            if entry.ok then
                local final_pair = property_pair(current.player[spec.property], spec.name)
                require_condition(near(final_pair.base, entry.observations.property.base)
                    and near(final_pair.current, entry.observations.property.current),
                    "Stamina attribute changed across the complete probe")
            end
        end
        require_condition(context(deps).identity == current.identity, "Player/world/ASC/attributes/form changed during stamina probe")
        result.ok, result.stage = true, "read-only-observations"
    end)
    if not ok then
        return { ok = false, mutation_authorized = false, gameplay_verified = false, capabilities = {}, stage = "blocked", reason = tostring(failure) }
    end
    return result
end

return Probe
