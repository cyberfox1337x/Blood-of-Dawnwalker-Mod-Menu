local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_focus_read_only_probe")

-- Standalone current-build observation module. Importing it schedules nothing;
-- the host must supply a fresh attested game-thread session for every run.
local Probe = {}
local PLAYER = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local ATTRIBUTES = "/Script/DogwoodStats.PlayerAttributeSet"
local ASC = "/Script/GameplayAbilities.AbilitySystemComponent"
local CAMERA = "/Script/RebelCamera.RebelCameraComponent"
local CAMERA_MODE = "/Script/RebelCamera.RebelCameraMode"
local FOCUS_MODE = "/Script/DogwoodCombat.FocusAbilityCameraMode"
local LIBRARY = "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"
local ATTRIBUTE_NAMES = { "MaxFocusRange", "MaxFocusSmellRange", "ActiveFocusRange", "ActiveFocusSmellRange" }

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function number(value, label)
    require_condition(finite(value), label .. " is not finite")
    return value
end

local function integer(value, minimum, maximum, label)
    require_condition(finite(value) and value % 1 == 0 and value >= minimum and value <= maximum, label .. " is outside its bound")
    return value
end

local function boolean(value, label)
    require_condition(type(value) == "boolean", label .. " is not a boolean")
    return value
end

local function text(value, label)
    if type(value) ~= "string" then value = value:ToString() end
    require_condition(type(value) == "string" and #value > 0 and #value <= 1024
        and not value:find("[%z\r\n]"), label .. " is not valid text")
    return value
end

local function object_record(value, class, label, allow_default)
    require_condition(value ~= nil and value:IsValid() == true and value:IsA(class) == true, label .. " has no valid expected object")
    local name = text(value:GetFullName(), label .. " name")
    require_condition(allow_default == true or not name:find("Default__", 1, true), label .. " is a default object")
    local address = number(value:GetAddress(), label .. " address")
    require_condition(address > 0, label .. " address is invalid")
    return { name = name, identity = name .. "@" .. tostring(address) }
end

local function unwrap(value)
    local ok, native = pcall(function() return value:get() end)
    -- Direct native values require no RemoteUnrealParam wrapper.
    return ok and native or value
end

local function array_values(array, maximum, label)
    require_condition(array ~= nil, label .. " is missing")
    local ok, count = pcall(function() return array:GetArrayNum() end)
    if not ok then count = #array end
    integer(count, 0, maximum, label .. " count")
    local entries = {}
    for index = 1, count do
        entries[index] = unwrap(array[index])
        require_condition(entries[index] ~= nil, label .. " is sparse")
    end
    if type(array) == "table" then
        for key in pairs(array) do
            if type(key) == "number" then integer(key, 1, count, label .. " index") end
        end
    end
    return entries
end

local function session_context(deps)
    require_condition(deps.is_in_game_thread() == true, "Focus probe requires the game thread")
    local identity = deps.get_identity()
    require_condition(type(identity) == "table" and identity.build_id == "25129649"
        and identity.executable_sha256 == "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
        and identity.metadata_sha256 == "CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6",
        "Focus candidate exact build or metadata attestation differs")
    local boot = text(identity.boot_id, "boot id")
    local player, controller = deps.get_player(), deps.get_controller()
    local player_record = object_record(player, PLAYER, "player")
    local controller_record = object_record(controller, "/Script/Engine.PlayerController", "controller")
    require_condition(controller:IsLocalPlayerController() == true
        and object_record(controller:K2_GetPawn(), PLAYER, "controller pawn").identity == player_record.identity
        and object_record(player:GetController(), "/Script/Engine.PlayerController", "player controller").identity == controller_record.identity,
        "Local player possession is inconsistent")
    local world_record = object_record(player:GetWorld(), "/Script/Engine.World", "world")
    require_condition(object_record(controller:GetWorld(), "/Script/Engine.World", "controller world").identity == world_record.identity,
        "Player and controller worlds disagree")
    local in_focus = boolean(player.bIsInFocusMode, "focus state")
    local vampire = boolean(player:IsVampire(), "character form")
    return { player = player, player_record = player_record, world_record = world_record, in_focus = in_focus, vampire = vampire,
        identity = table.concat({ boot, controller_record.identity, player_record.identity, world_record.identity, tostring(in_focus), tostring(vampire) }, "|") }
end

local function capture_getter(call, expected, label)
    local returned = table.pack(call())
    require_condition(returned.n <= 4, label .. " returned too many output values")
    local return_types = {}
    local numeric, found, numeric_count, flag_count = nil, nil, 0, 0
    for index = 1, returned.n do
        local value = returned[index]
        return_types[index] = type(value)
        if finite(value) then numeric, numeric_count = value, numeric_count + 1
        elseif type(value) == "boolean" then found, flag_count = value, flag_count + 1
        elseif value ~= nil then error(label .. " returned an unsupported " .. type(value) .. " result", 0) end
    end
    require_condition(numeric_count == 1 and flag_count <= 1, label .. " returned ambiguous output values")
    require_condition(found ~= false, label .. " explicitly reported attribute not found")
    require_condition(math.abs(numeric - expected) <= math.max(0.00001, math.abs(expected) * 0.00001), label .. " disagrees with the current attribute data")
    -- Some UE4SS call shapes omit bool out parameters. Preserve that observation,
    -- without treating a coincidentally matching number as full getter proof.
    return { value = numeric, found = found == true, found_flag_returned = found ~= nil, return_count = returned.n,
        return_shape = table.concat(return_types, ","),
        native_shape_verified = returned.n == 2 and type(returned[1]) == "number" and returned[2] == true }
end

local function read_attributes(context, deps)
    local player = context.player
    local attributes = player.CharacterAttributeSet
    local attribute_record = object_record(attributes, ATTRIBUTES, "player attributes")
    local ability_system = player.AbilitySystemComponent
    local asc_record = object_record(ability_system, ASC, "player ASC")
    require_condition(object_record(ability_system:GetOwner(), PLAYER, "ASC owner").identity == context.player_record.identity
        and object_record(attributes:GetOuter(), PLAYER, "attribute outer").identity == context.player_record.identity,
        "Focus attribute ownership differs from the local player")
    local attribute_class = deps.static_find_object(ATTRIBUTES)
    object_record(attribute_class, "/Script/CoreUObject.Class", "attribute class", true)
    require_condition(object_record(ability_system:GetAttributeSet(attribute_class), ATTRIBUTES, "ASC attribute set").identity == attribute_record.identity,
        "ASC and player attribute sets disagree")
    local library = deps.static_find_object(LIBRARY)
    object_record(library, "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary", "native attribute library", true)
    require_condition(object_record(library:GetAbilitySystemComponent(player), ASC, "independent ASC").identity == asc_record.identity,
        "Independent ASC lookup disagrees")

    local output = {}
    ability_system:GetAllAttributes(output)
    local all = array_values(output, 1024, "ASC attribute descriptors")
    require_condition(#all > 0, "ASC returned no native descriptors")
    local wanted, selected = {}, {}
    for _, name in ipairs(ATTRIBUTE_NAMES) do wanted[name] = true end
    for _, descriptor in ipairs(all) do
        local name = text(descriptor.AttributeName, "native descriptor name")
        if wanted[name] then
            require_condition(selected[name] == nil, "Duplicate Focus descriptor: " .. name)
            require_condition(descriptor:IsValid() == true and descriptor:type() == "UScriptStruct",
                "Focus descriptor is not a native struct")
            require_condition(object_record(descriptor.AttributeOwner, "/Script/CoreUObject.Struct", "descriptor owner", true).identity
                == object_record(attribute_class, "/Script/CoreUObject.Struct", "expected descriptor owner", true).identity,
                "Focus descriptor belongs to another attribute class")
            require_condition(number(descriptor:GetStructAddress(), "descriptor address") > 0, "Descriptor has no native address")
            selected[name] = descriptor
        end
    end
    local observations, fully_verified = {}, true
    for _, name in ipairs(ATTRIBUTE_NAMES) do
        local descriptor = selected[name]
        require_condition(descriptor ~= nil, "Missing Focus descriptor: " .. name)
        local field = attributes[name]
        local base, current = number(field.BaseValue, name .. " base"), number(field.CurrentValue, name .. " current")
        require_condition(base >= 0 and current >= 0, "Focus attribute range is negative")
        local debug_string = text(library:GetDebugStringFromGameplayAttribute(descriptor), name .. " descriptor debug string")
        require_condition(debug_string:find(name, 1, true) ~= nil, "Descriptor debug string names another attribute")
        local asc_current = capture_getter(function() return ability_system:GetGameplayAttributeValue(descriptor) end, current, name .. " ASC getter")
        local library_current = capture_getter(function() return library:GetFloatAttributeFromAbilitySystemComponent(ability_system, descriptor) end,
            current, name .. " current getter")
        local library_base = capture_getter(function() return library:GetFloatAttributeBaseFromAbilitySystemComponent(ability_system, descriptor) end,
            base, name .. " base getter")
        require_condition(field.BaseValue == base and field.CurrentValue == current, "Focus attribute changed while being read")
        fully_verified = fully_verified and asc_current.native_shape_verified
            and library_current.native_shape_verified and library_base.native_shape_verified
        observations[name] = { base = base, current = current, debug_string = debug_string,
            asc_current = asc_current, library_current = library_current, library_base = library_base }
    end
    require_condition(object_record(player.AbilitySystemComponent, ASC, "ASC after reads").identity == asc_record.identity
        and object_record(player.CharacterAttributeSet, ATTRIBUTES, "attributes after reads").identity == attribute_record.identity,
        "Focus attribute objects changed during collection")
    return { attributes = attribute_record, ability_system = asc_record, descriptor_count = #all,
        values = observations, native_getter_verified = fully_verified,
        limitation = "Getter agreement does not establish aggregation, reentry, setter semantics, or restoration." }
end

local function validate_attribute_snapshot(context, observations)
    local attributes = context.player.CharacterAttributeSet
    require_condition(object_record(attributes, ATTRIBUTES, "final player attributes").identity == observations.attributes.identity
        and object_record(context.player.AbilitySystemComponent, ASC, "final player ASC").identity == observations.ability_system.identity,
        "Focus attribute objects changed after collection")
    for _, name in ipairs(ATTRIBUTE_NAMES) do
        local field, observed = attributes[name], observations.values[name]
        require_condition(field.BaseValue == observed.base and field.CurrentValue == observed.current,
            "Focus attribute changed across the complete snapshot: " .. name)
    end
end

local function stack_records(camera)
    local records, seen = {}, {}
    for _, entry in ipairs(array_values(camera.CameraModeStack, 16, "camera stack")) do
        local handle = integer(entry.Handle.Handle, 0, 2147483647, "camera handle")
        require_condition(not seen[handle], "Duplicate camera stack handle")
        seen[handle] = true
        local record = object_record(entry.CameraMode, CAMERA_MODE, "stacked camera mode")
        records[#records + 1] = { handle = handle, mode = entry.CameraMode, record = record }
    end
    return records
end

local function stack_identity(records)
    local parts = {}
    for _, entry in ipairs(records) do parts[#parts + 1] = tostring(entry.handle) .. ":" .. entry.record.identity end
    return table.concat(parts, "|")
end

local function camera_offsets(mode)
    local offsets, count = {}, 0
    mode.CameraOffsets:ForEach(function(raw_key, raw_offset)
        count = count + 1
        require_condition(count <= 4, "Camera offset map exceeds reflected enum bound")
        local key, offset = integer(unwrap(raw_key), 0, 3, "camera type"), unwrap(raw_offset)
        require_condition(offsets[key] == nil, "Duplicate camera offset type")
        offsets[key] = { type = key, override_fov = boolean(offset.bOverrideFOV, "FOV override"),
            fov = number(offset.OverriddenFieldOfView, "overridden FOV"), pivot_z = number(offset.PivotZOffset, "pivot offset"),
            use_pitch_curves = boolean(offset.bUseOffsetPitchCurves, "pitch-curve override"),
            x = number(offset.TargetOffset.X, "target offset X"), y = number(offset.TargetOffset.Y, "target offset Y"),
            z = number(offset.TargetOffset.Z, "target offset Z") }
    end)
    require_condition(count > 0, "Focus camera has no camera-type offsets")
    return offsets
end

local function read_camera(context)
    local camera = context.player.FollowCamera
    local camera_record = object_record(camera, CAMERA, "follow camera")
    require_condition(object_record(camera:GetOwner(), PLAYER, "camera owner").identity == context.player_record.identity,
        "Follow camera belongs to another actor")
    local stack = stack_records(camera)
    local camera_type = integer(camera:GetCameraType(), 0, 3, "selected camera type")
    local records, focus_count = {}, 0
    for _, entry in ipairs(stack) do
        local mode = entry.mode
        require_condition(object_record(mode:GetCameraComponent(), CAMERA, "mode camera").identity == camera_record.identity
            and object_record(mode:GetTargetActor(), PLAYER, "mode target").identity == context.player_record.identity,
            "Camera mode ownership differs from the local player")
        local record = { identity = entry.record.identity, name = entry.record.name, handle = entry.handle,
            state = integer(mode:GetState(), 0, 3, "camera mode state"), is_focus_mode = mode:IsA(FOCUS_MODE) == true,
            default_fov = number(mode.DefaultFieldOfView, "default FOV"), effective_fov = number(mode:GetFieldOfView(), "effective FOV"),
            applies_postprocessing = boolean(mode.bApplyPostProcessing, "postprocessing flag") }
        if record.is_focus_mode then
            focus_count = focus_count + 1
            record.offsets = camera_offsets(mode)
        end
        records[#records + 1] = record
    end
    require_condition(stack_identity(stack_records(camera)) == stack_identity(stack)
        and camera:GetCameraType() == camera_type
        and object_record(context.player.FollowCamera, CAMERA, "follow camera after read").identity == camera_record.identity,
        "Camera stack or selection changed during collection")
    return { camera = camera_record, camera_type = camera_type, stack = records, focus_mode_count = focus_count,
        active_focus_range = number(context.player.FocusModeActiveRange, "player active focus range"),
        limitation = "A missing Focus mode outside Focus is valid. Observe entry, steady state, exit and reentry; no FOV, offset, or postprocess write is authorized." }
end

local function section(run)
    local ok, observations = pcall(run)
    if ok then return { ok = true, observations = observations } end
    return { ok = false, reason = tostring(observations) }
end

function Probe.run(deps)
    local result = { ok = false, mutation_authorized = false, gameplay_verified = false, capabilities = {} }
    local ok, failure = pcall(function()
        for _, name in ipairs({ "get_identity", "is_in_game_thread", "get_player", "get_controller", "static_find_object" }) do
            require_condition(type(deps) == "table" and type(deps[name]) == "function", "Missing Focus dependency: " .. name)
        end
        local context = session_context(deps)
        result.context_identity, result.in_focus, result.vampire = context.identity, context.in_focus, context.vampire
        result.attributes = section(function() return read_attributes(context, deps) end)
        result.camera = section(function() return read_camera(context) end)
        if result.attributes.ok then validate_attribute_snapshot(context, result.attributes.observations) end
        require_condition(session_context(deps).identity == context.identity, "Focus player/world/form state changed during observation")
        result.ok = true
    end)
    if not ok then return { ok = false, mutation_authorized = false, gameplay_verified = false, capabilities = {}, reason = tostring(failure) } end
    return result
end

return Probe
