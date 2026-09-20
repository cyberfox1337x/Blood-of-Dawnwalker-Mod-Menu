local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_requested_features_read_only_probe")

-- This module deliberately has no automatic execution or mutation entry point.
-- Run it on the game thread only after the installer's exact-build check passes.
local Probe = {}
local EXPECTED_BUILD = "25107392"
local EXPECTED_EXECUTABLE_SHA256 = "45B7C2949F519ED3E45F7FBDB7127A03373FE44B34ABB58E3C987C5054E2409E"
local PLAYER_CLASS = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local PLAYER_ATTRIBUTE_CLASS = "/Script/DogwoodStats.PlayerAttributeSet"
local CHAR_DEV_CLASS = "/Script/DogwoodStats.CharDevAttributeSet"
local COMBAT_CLASS = "/Script/DogwoodCombat.PlayerCombatComponent"
local CONFIG_CLASS = "/Script/DogwoodCombat.CombatConfig"
local MODE_CLASS = "/Script/DogwoodCombat.CombatMode"
local MESH_CLASS = "/Script/Engine.SkeletalMeshComponent"
local MATERIAL_CLASS = "/Script/Engine.MaterialInstance"
local MODE_NAMES = { "VampireSword", "Sword", "VampireHandToHand", "HandToHand", "Fistfight" }
local PLAYER_ATTRIBUTES = {
    "MaxFocusRange", "MaxFocusSmellRange", "ActiveFocusRange", "ActiveFocusSmellRange",
    "SprintStaminaCostMultiplier", "DodgeStaminaCostMultiplier",
}

local function finite(number)
    return type(number) == "number" and number == number and math.abs(number) < math.huge
end

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function checked_number(number, label)
    require_condition(finite(number), label .. " is not a finite number")
    return number
end

local function unwrap(entry)
    if entry == nil then return nil end
    local ok, unwrapped = pcall(function() return entry:get() end)
    -- Native values need no wrapper. The following typed reads still reject an
    -- unsupported wrapper; this fallback never supplies a guessed default.
    if ok then return unwrapped end
    return entry
end

local function object_record(object, expected_class, label)
    require_condition(object ~= nil and object:IsValid() == true, label .. " is unavailable")
    if expected_class then
        require_condition(object:IsA(expected_class) == true, label .. " has an unexpected class")
    end
    local name = object:GetFullName()
    require_condition(type(name) == "string" and #name > 0 and #name <= 1024, label .. " has an invalid name")
    require_condition(name:find("Default__", 1, true) == nil, label .. " is a class default object")
    local address = checked_number(object:GetAddress(), label .. " address")
    require_condition(address > 0, label .. " has an invalid address")
    return { name = name, address = tostring(address) }
end

local function bounded_array(array, maximum, label)
    require_condition(array ~= nil, label .. " is unavailable")
    local ok, count = pcall(function() return array:GetArrayNum() end)
    if not ok then
        ok, count = pcall(function() return #array end)
    end
    require_condition(ok and finite(count) and count % 1 == 0 and count >= 0 and count <= maximum,
        label .. " length is invalid or exceeds the probe bound")
    local entries = {}
    for index = 1, count do
        local entry = unwrap(array[index])
        require_condition(entry ~= nil, label .. " has a missing element")
        entries[index] = entry
    end
    return entries
end

local function attribute_pair(owner, name)
    local attribute = owner[name]
    require_condition(attribute ~= nil, name .. " is unavailable")
    return {
        base = checked_number(attribute.BaseValue, name .. " base"),
        current = checked_number(attribute.CurrentValue, name .. " current"),
    }
end

local function read_attributes(player)
    local attributes = player.CharacterAttributeSet
    local attributes_record = object_record(attributes, PLAYER_ATTRIBUTE_CLASS, "player attributes")
    local character_development = player.CharDevAttributeSet
    local character_development_record = object_record(character_development, CHAR_DEV_CLASS, "character development attributes")
    local values = {}
    for _, name in ipairs(PLAYER_ATTRIBUTES) do values[name] = attribute_pair(attributes, name) end
    values.OmniblockStaminaCostMultiplier = attribute_pair(character_development, "OmniblockStaminaCostMultiplier")
    return {
        player_attribute_set = attributes_record,
        character_development_attribute_set = character_development_record,
        values = values,
        limitation = "Property observations only. Native attribute descriptor ABI, aggregation, setter, and restoration are unverified.",
    }
end

local function read_modes(player)
    local combat = player.CombatComponent
    local combat_record = object_record(combat, COMBAT_CLASS, "player combat component")
    local config = combat:GetConfig()
    local config_record = object_record(config, CONFIG_CLASS, "combat config")
    require_condition(object_record(combat.Config, CONFIG_CLASS, "combat config property").address == config_record.address,
        "combat config getter and property disagree")
    local modes = {}
    for enum_value, name in ipairs(MODE_NAMES) do
        require_condition(config.CombatModes:Contains(enum_value) == true, "combat mode missing: " .. name)
        local mode = unwrap(config.CombatModes:Find(enum_value))
        local mode_record = object_record(mode, MODE_CLASS, name .. " combat mode")
        local metrics = mode.MetricsScalingSettings
        mode_record.mode = name
        mode_record.enum_value = enum_value
        mode_record.attack_playrate = checked_number(metrics.AttackPlayrate, name .. " attack playrate")
        mode_record.strong_attack_playrate = checked_number(metrics.StrongAttackPlayrate, name .. " strong attack playrate")
        mode_record.dodge_playrate = checked_number(metrics.DodgePlayrate, name .. " dodge playrate")
        mode_record.block_playrate = checked_number(metrics.BlockPlayrate, name .. " block playrate")
        mode_record.root_motion_scaling = checked_number(metrics.DefaultRootMotionScaling, name .. " root motion scaling")
        mode_record.dodge_stamina_cost = checked_number(mode.DodgeStaminaCost, name .. " dodge stamina cost")
        modes[#modes + 1] = mode_record
    end
    return {
        combat_component = combat_record,
        config = config_record,
        modes = modes,
        limitation = "Loaded assets are observed through the player. This does not prove exclusive ownership or exclude NPC use.",
    }
end

local function parameter_name(parameter)
    local name = parameter.ParameterInfo.Name:ToString()
    require_condition(type(name) == "string" and #name > 0 and #name <= 256, "invalid material parameter name")
    return name
end

local function material_parameters(material)
    if material:IsA(MATERIAL_CLASS) ~= true then
        return { status = "non-instance", scalar = {}, vector = {} }
    end
    local parameters = { status = "local-overrides-only", scalar = {}, vector = {} }
    for _, parameter in ipairs(bounded_array(material.ScalarParameterValues, 128, "scalar parameters")) do
        parameters.scalar[#parameters.scalar + 1] = {
            name = parameter_name(parameter),
            value = checked_number(parameter.ParameterValue, "scalar parameter"),
        }
    end
    for _, parameter in ipairs(bounded_array(material.VectorParameterValues, 128, "vector parameters")) do
        local color = parameter.ParameterValue
        parameters.vector[#parameters.vector + 1] = {
            name = parameter_name(parameter),
            r = checked_number(color.R, "red"), g = checked_number(color.G, "green"),
            b = checked_number(color.B, "blue"), a = checked_number(color.A, "alpha"),
        }
    end
    return parameters
end

local function read_materials(player, deps)
    local mesh_class = deps.static_find_object(MESH_CLASS)
    require_condition(mesh_class ~= nil and mesh_class:IsValid() == true, "skeletal mesh class is unavailable")
    local components = bounded_array(player:K2_GetComponentsByClass(mesh_class), 32, "player skeletal meshes")
    require_condition(#components > 0, "no player skeletal meshes were returned")
    local records = {}
    for _, component in ipairs(components) do
        local component_record = object_record(component, MESH_CLASS, "player skeletal mesh")
        require_condition(object_record(component:GetOwner(), PLAYER_CLASS, "mesh owner").address == tostring(player:GetAddress()),
            "a skeletal mesh belongs to a different actor")
        local count = checked_number(component:GetNumMaterials(), "material count")
        require_condition(count >= 0 and count <= 32 and count % 1 == 0, "material count exceeds the probe bound")
        component_record.materials = {}
        for index = 0, count - 1 do
            local material = component:GetMaterial(index)
            local material_record = object_record(material, nil, "material slot " .. tostring(index))
            material_record.slot = index
            material_record.parameters = material_parameters(material)
            component_record.materials[#component_record.materials + 1] = material_record
        end
        records[#records + 1] = component_record
    end
    return {
        components = records,
        limitation = "Only current local material overrides are listed. Eye ownership, inherited parameters, form transitions, and live appearance effects are unverified.",
    }
end

local function read_section(reader)
    local ok, observations = pcall(reader)
    if not ok then return { ok = false, reason = tostring(observations) } end
    return { ok = true, observations = observations }
end

function Probe.run(deps)
    local result = { ok = false, mutation_authorized = false, gameplay_verified = false }
    local ok, failure = pcall(function()
        require_condition(type(deps) == "table" and type(deps.get_player) == "function"
            and type(deps.static_find_object) == "function", "read-only dependencies are incomplete")
        require_condition(deps.game_thread == true, "probe must run on the game thread")
        require_condition(type(deps.identity) == "table" and deps.identity.build_id == EXPECTED_BUILD
            and deps.identity.executable_sha256 == EXPECTED_EXECUTABLE_SHA256,
            "installer exact-build attestation is missing or mismatched")
        local player = deps.get_player()
        local player_record = object_record(player, PLAYER_CLASS, "player")
        local world = player:GetWorld()
        local world_record = object_record(world, "/Script/Engine.World", "world")
        result.player = player_record
        result.world = world_record
        result.attributes = read_section(function() return read_attributes(player) end)
        result.attack_modes = read_section(function() return read_modes(player) end)
        result.materials = read_section(function() return read_materials(player, deps) end)
        local current_player = deps.get_player()
        require_condition(object_record(current_player, PLAYER_CLASS, "player after probe").address == player_record.address
            and object_record(current_player:GetWorld(), "/Script/Engine.World", "world after probe").address == world_record.address,
            "player or world changed during the read-only probe")
        result.ok = true
        result.stage = "read-only-observations"
    end)
    if not ok then
        -- Do not retain partial snapshots from a changed world or rejected preflight.
        return { ok = false, mutation_authorized = false, gameplay_verified = false,
            stage = "blocked", reason = tostring(failure) }
    end
    return result
end

function Probe.format_lines(result)
    local lines = {}
    local function visit(prefix, entry, depth)
        require_condition(depth <= 12 and #lines <= 40000, "report exceeded the output bound")
        if type(entry) == "table" then
            local keys = {}
            for key in pairs(entry) do keys[#keys + 1] = key end
            table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
            for _, key in ipairs(keys) do visit(prefix .. "." .. tostring(key), entry[key], depth + 1) end
        else
            local encoded = tostring(entry):gsub("[%%\r\n]", function(character)
                return string.format("%%%02X", string.byte(character))
            end)
            lines[#lines + 1] = prefix .. "=" .. encoded
        end
    end
    visit("requested_features", result, 0)
    return table.concat(lines, "\n")
end

return Probe
