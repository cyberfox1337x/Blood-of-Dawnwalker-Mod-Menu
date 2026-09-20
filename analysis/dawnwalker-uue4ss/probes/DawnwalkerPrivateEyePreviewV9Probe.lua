local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_private_eye_preview_v9_probe")

-- Uninstalled lifecycle prototype. Uses only native classes and already loaded player assets.
local Probe = {}
local Geometry = require("DawnwalkerEyePreviewGeometryV8")
local Appearance = require("DawnwalkerAppearanceSourcesV9")
local BUILD_ID = "25129649"
local EXECUTABLE_SHA256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
local ROOT = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-frames"
local OFFSET_Z = 100000
local consumed = {}
local operation_count = 0
local ISOLATED_FLAGS = { "Fog", "VolumetricFog", "Atmosphere", "Cloud", "SkyLighting", "GlobalIllumination",
    "LumenGlobalIllumination", "ReflectionEnvironment", "LumenReflections", "ScreenSpaceReflections", "AmbientCubemap",
    "Bloom", "LocalExposure", "LensFlares", "MotionBlur", "DepthOfField", "Vignette", "Grain", "ColorGrading" }

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function number(value, label)
    require_condition(type(value) == "number" and value == value and math.abs(value) < math.huge, label .. " is not finite")
    return value
end

local function vector(value)
    return { X = number(value.X, "X"), Y = number(value.Y, "Y"), Z = number(value.Z, "Z") }
end

local function rotation(value)
    return { pitch = number(value.pitch, "pitch"), Yaw = number(value.Yaw, "Yaw"), Roll = number(value.Roll, "Roll") }
end

local function transform(value)
    return { Translation = vector(value.Translation), Scale3D = vector(value.Scale3D), Rotation = {
        X = number(value.Rotation.X, "rotation X"), Y = number(value.Rotation.Y, "rotation Y"),
        Z = number(value.Rotation.Z, "rotation Z"), W = number(value.Rotation.W, "rotation W") } }
end

local function valid(object)
    return object ~= nil and object:IsValid() == true
end

local function flag(value, expected)
    return expected and (value == true or value == 1) or not expected and (value == false or value == 0)
end

local function private_lighting(component)
    local channels = component.LightingChannels
    return flag(channels.bChannel0, false) and flag(channels.bChannel1, false) and flag(channels.bChannel2, true)
end

local function record(object, class, label)
    require_condition(valid(object) and object:IsA(class) == true, label .. " is unavailable or has the wrong class")
    local name, address = object:GetFullName(), object:GetAddress()
    require_condition(type(name) == "string" and #name <= 1024 and not name:find("Default__", 1, true), label .. " is not an instance")
    require_condition(number(address, label .. " address") > 0, label .. " address is invalid")
    return { address = tostring(address), name = name }
end

local function same(object, previous)
    return valid(object) and tostring(object:GetAddress()) == previous.address and object:GetFullName() == previous.name
end

local function equal_fields(left, right)
    for key, expected in pairs(right) do if math.abs(number(left[key], key) - expected) > 0.00001 then return false end end
    return true
end

local function static(deps, name, class)
    local object = deps.static_find_object(name)
    require_condition(valid(object) and object:IsA(class) == true, "Loaded native dependency is unavailable: " .. name)
    return object
end

local function array(array, maximum, label)
    local ok, count = pcall(function() return array:GetArrayNum() end)
    if not ok then count = #array end
    require_condition(type(count) == "number" and count % 1 == 0 and count >= 0 and count <= maximum, label .. " exceeds its bound")
    local values = {}
    for index = 1, count do
        local value = array[index]
        local unwrapped, raw = pcall(function() return value:get() end)
        if unwrapped then value = raw end
        require_condition(value ~= nil, label .. " contains a missing entry")
        values[#values + 1] = value
    end
    return values
end

local function snapshot_sources(deps, record_appearance)
    local player = deps.get_player()
    local snapshot = { player = record(player, "/Script/Dawnwalker.DawnwalkerPlayerCharacter", "player"), meshes = {} }
    snapshot.world = record(player:GetWorld(), "/Script/Engine.World", "world")
    snapshot.form, snapshot.wolf = player.Form, player:IsInWolfForm()
    require_condition((snapshot.form == 0 or snapshot.form == 1) and snapshot.wolf == false, "Unsupported player form")
    snapshot.location, snapshot.rotation = vector(player:K2_GetActorLocation()), rotation(player:K2_GetActorRotation())
    local observed = Appearance.run(deps)
    record_appearance(observed.report)
    require_condition(observed.ok == true, "Actual appearance inspection failed: " .. tostring(observed.reason))
    require_condition(observed.report.unsupported_visible_sources ~= true, "Actual visible appearance contains unsupported geometry or bindings")
    snapshot.appearance, snapshot.appearance_report = observed.snapshot, observed.report
    local fields = {}
    for _, source in ipairs(observed.snapshot.sources) do
        local observed_source = source.record
        if observed_source.classification == "non-appearance" or observed_source.classification == "empty-geometry" then
            -- Their continued empty/UI status remains part of the inspected cohort.
        elseif observed_source.kind == "unsupported" then
            require_condition(not observed_source.visible or observed_source.hidden_in_game, "Visible appearance component has no supported private clone route")
        elseif valid(source.asset) and observed_source.unsupported_reason == nil then
            local field = observed_source.component.name
            if source.component:GetAddress() == player.HeadMesh:GetAddress() then field = "HeadMesh" end
            local bindings = {}
            for index, binding in ipairs(observed_source.materials) do
                require_condition(binding.slot == index - 1 and binding.material ~= nil and binding.material.present ~= false, "Actual appearance material record is unavailable")
                bindings[index] = binding.material
            end
            local entry = { source = source.component, identity = observed_source.component, field = field,
                kind = observed_source.kind, asset = source.asset, asset_identity = observed_source.asset,
                transform = transform(observed_source.world_transform), materials = bindings,
                material_objects = source.material_refs, appearance_source = source,
                visible = observed_source.visible and not observed_source.hidden_in_game and not observed_source.owner_hidden }
            snapshot.meshes[#snapshot.meshes + 1] = entry
            fields[field] = entry
        end
    end
    require_condition(fields.HeadMesh ~= nil and fields.HeadMesh.kind == "skeletal", "Actual loaded head asset is required")
    require_condition(type(deps.pivot_bone_name) == "string" and #deps.pivot_bone_name >= 1 and #deps.pivot_bone_name <= 128,
        "An observed head/eye pivot bone is required")
    local head, pivot_name = fields.HeadMesh.source, nil
    local count = head:GetNumBones()
    require_condition(type(count) == "number" and count % 1 == 0 and count >= 1 and count <= 2048, "Head skeleton exceeds the observation bound")
    for index = 0, count - 1 do
        local name = head:GetBoneName(index)
        if name:ToString() == deps.pivot_bone_name then pivot_name = name; break end
    end
    require_condition(pivot_name ~= nil and head:DoesSocketExist(pivot_name) == true, "Requested pivot was not found in this actual head skeleton")
    snapshot.pivot = vector(head:GetSocketLocation(pivot_name))
    snapshot.pivot_bone_name = deps.pivot_bone_name
    snapshot.landmarks = Geometry.observe_landmarks(head)
    require_condition(snapshot.landmarks.eye_pair_count == 1 and snapshot.landmarks.eye_pair ~= nil,
        "This current head does not expose one unambiguous native left/right eye bone pair")
    local bounds = fields.HeadMesh.asset:GetBounds()
    snapshot.head_bounds = { origin = vector(bounds.Origin), extent = vector(bounds.BoxExtent), radius = number(bounds.SphereRadius, "head sphere radius") }
    snapshot.head_transform = fields.HeadMesh.transform
    return player, snapshot
end

local function verify_sources(deps, snapshot)
    local player = deps.get_player()
    require_condition(same(player, snapshot.player) and same(player:GetWorld(), snapshot.world)
        and player.Form == snapshot.form and player:IsInWolfForm() == snapshot.wolf, "Player/world/form changed during private preview")
    require_condition(equal_fields(vector(player:K2_GetActorLocation()), snapshot.location)
        and equal_fields(rotation(player:K2_GetActorRotation()), snapshot.rotation), "Player transform changed during private preview")
    local appearance_ok, appearance_error = Appearance.verify(deps, snapshot.appearance)
    require_condition(appearance_ok == true, "Actual appearance changed: " .. tostring(appearance_error))
end

local function no_inventory_doll(deps)
    for _, doll in ipairs(array(deps.find_all_of("InventoryRenderDoll") or {}, 8, "inventory dolls")) do
        if valid(doll) and not doll:GetFullName():find("Default__", 1, true) then error("Close the native inventory before testing independent preview lifetime", 0) end
    end
end

local function existing_addresses(deps, class)
    local addresses = {}
    for _, object in ipairs(array(deps.find_all_of(class) or {}, 256, class)) do
        if valid(object) then addresses[tostring(object:GetAddress())] = true end
    end
    return addresses
end

local function capture_settings(capture)
    capture.bCaptureEveryFrame, capture.bCaptureOnMovement = false, false
    capture.bMainViewCamera, capture.bMainViewFamily, capture.bMainViewResolution, capture.bRenderInMainRenderer = false, false, false, false
    capture.bSuppressWorldPostProcessing, capture.PrimitiveRenderMode, capture.CaptureSource = true, 2, 9
    capture.ProjectionType, capture.FOVAngle, capture.PostProcessBlendWeight = 0, 30, 0
    capture:ClearShowOnlyComponents()
end

local function shifted(point)
    return { X = point.X, Y = point.Y, Z = point.Z + OFFSET_Z }
end

local function derive_geometry(snapshot, player, math_library)
    local scale = snapshot.head_transform.Scale3D
    require_condition(scale.X > 0 and scale.Y > 0 and scale.Z > 0 and math.max(scale.X, scale.Y, scale.Z) <= 10,
        "Native head scale is outside supported bounds")
    local center = vector(math_library:TransformLocation(snapshot.head_transform, snapshot.head_bounds.origin))
    return Geometry.build_views({ head_center = shifted(center), head_pivot = shifted(snapshot.pivot),
        eye_left = shifted(snapshot.landmarks.eye_pair.left.location), eye_right = shifted(snapshot.landmarks.eye_pair.right.location),
        head_radius = snapshot.head_bounds.radius * math.max(scale.X, scale.Y, scale.Z), forward = vector(player:GetActorForwardVector()) })
end

local function apply_view(capture, view, math_library)
    local look_at = rotation(math_library:FindLookAtRotation(view.location, view.pivot))
    capture.ProjectionType, capture.FOVAngle = 0, view.field_of_view
    capture.bOverride_CustomNearClippingPlane, capture.CustomNearClippingPlane = true, view.near_clip
    capture:K2_SetWorldLocationAndRotation(view.location, look_at, false, {}, true)
    local actual_location, actual_rotation = vector(capture:K2_GetComponentLocation()), rotation(capture:K2_GetComponentRotation())
    require_condition(equal_fields(actual_location, view.location) and equal_fields(actual_rotation, look_at)
        and capture.ProjectionType == 0 and math.abs(capture.FOVAngle - view.field_of_view) < 0.00001
        and flag(capture.bOverride_CustomNearClippingPlane, true) and capture.CustomNearClippingPlane == view.near_clip,
        "Private camera projection or transform did not read back")
    return actual_location, actual_rotation
end

local function set_native_flag(receiver, name, enabled)
    local original = receiver[name]
    require_condition(type(original) == "boolean" or original == 0 or original == 1, "Unsupported native flag: " .. name)
    receiver[name] = type(original) == "number" and (enabled and 1 or 0) or enabled
    require_condition(flag(receiver[name], enabled), "Native flag did not read back: " .. name)
end

local function configure_primitive(mesh, source)
    mesh:SetCollisionEnabled(0)
    mesh:SetGenerateOverlapEvents(false)
    mesh:SetVisibleInSceneCaptureOnly(true)
    mesh:SetHiddenInSceneCapture(not source.visible)
    mesh:SetCastShadow(false)
    mesh:SetAffectDynamicIndirectLighting(false)
    mesh:SetAffectDistanceFieldLighting(false)
    mesh:SetVisibleInRayTracing(false)
    mesh:SetLightingChannels(false, false, true)
end

local function configure_appearance(mesh, source, private_by_source)
    if source.kind == "skeletal" then
        mesh:SetSkeletalMeshAsset(source.asset)
        mesh:SetLeaderPoseComponent(source.source, true, false)
        require_condition(same(mesh:GetSkeletalMeshAsset(), source.asset_identity), "Private skeletal asset did not read back")
    elseif source.kind == "static" then
        require_condition(mesh:SetStaticMesh(source.asset) == true and same(mesh.StaticMesh, source.asset_identity), "Private static asset did not read back")
    elseif source.kind == "chaos-cloth" then
        local original = source.appearance_source
        local parent = original.attach_parent and private_by_source[tostring(original.attach_parent:GetAddress())]
        require_condition(parent ~= nil and parent.source.kind == "skeletal", "Chaos cloth requires a mapped private skeletal parent")
        local details = original.record.cloth
        require_condition(type(details) == "table" and number(details.geometry_scale, "cloth geometry scale") > 0
            and details.geometry_scale <= 100, "Actual cloth geometry scale exceeds supported bounds")
        -- Use the private parent's skinned pose. Never bind to live cloth simulation
        -- or change any original garment, solver, asset or player component.
        mesh:SetEnableSimulation(false)
        set_native_flag(mesh, "bUseAttachedParentAsPoseComponent", true)
        set_native_flag(mesh, "bBindToLeaderComponent", false)
        require_condition(mesh:K2_AttachToComponent(parent.object, original.native_attach_socket, 1, 1, 1, false) == true,
            "Private cloth attachment did not succeed")
        mesh:SetClothAsset(source.asset)
        mesh:SetEnableSimulation(false)
        mesh.BlendWeight, mesh.ClothGeometryScale = 0, details.geometry_scale
        require_condition(same(mesh:GetClothAsset(), source.asset_identity) and same(mesh:GetAttachParent(), parent.identity)
            and flag(mesh:IsSimulationEnabled(), false) and flag(mesh.bUseAttachedParentAsPoseComponent, true)
            and flag(mesh.bBindToLeaderComponent, false), "Private cloth asset, pose parent or disabled simulation did not read back")
    elseif source.kind == "groom" then
        local original = source.appearance_source
        require_condition(original.record.groom_cache and original.record.groom_cache.present == false,
            "A live groom cache requires an independently verified copy route")
        local parent = original.attach_parent and private_by_source[tostring(original.attach_parent:GetAddress())]
        require_condition(parent ~= nil and parent.source.kind == "skeletal", "Groom does not have a verified private skeletal attachment")
        if valid(original.binding_asset) then
            require_condition(same(original.binding_asset:GetTargetSkeletalMesh(), parent.source.asset_identity)
                and same(original.binding_asset.Groom, source.asset_identity), "Groom binding does not match its actual skeletal parent and hair asset")
        end
        require_condition(mesh:K2_AttachToComponent(parent.object, original.native_attach_socket, 1, 1, 1, false) == true,
            "Private groom attachment did not succeed")
        mesh:SetGroomAsset(source.asset)
        mesh.SimulationSettings.bOverrideSettings = true
        mesh.SimulationSettings.SolverSettings.bEnableSimulation = false
        mesh:SetEnableSimulation(false)
        if valid(original.binding_asset) then mesh:SetBindingAsset(original.binding_asset) end
        local details = original.record
        require_condition(type(details) == "table" and type(details.bUseCards) == "boolean" and type(details.AttachmentName) == "string"
            and type(details.groups) == "table" and #details.groups <= 16, "Groom rendering descriptors are incomplete")
        mesh.bUseCards, mesh.AttachmentName, mesh.GroomGroupsDesc = details.bUseCards, details.AttachmentName, details.groups
        require_condition(same(mesh.GroomAsset, source.asset_identity) and same(mesh:GetAttachParent(), parent.identity)
            and mesh.bUseCards == details.bUseCards, "Private groom asset, attachment or representation did not read back")
        if valid(original.binding_asset) then require_condition(same(mesh.BindingAsset, details.binding_asset), "Private groom binding did not read back") end
    else error("Unsupported actual appearance component", 0) end
    for index, material in ipairs(source.material_objects) do mesh:SetMaterial(index - 1, material) end
    require_condition(mesh:GetNumMaterials() == #source.material_objects, "Private appearance material slot count differs")
    for index, binding in ipairs(source.materials) do require_condition(same(mesh:GetMaterial(index - 1), binding), "Private appearance material did not read back") end
end

local function observe_clone(owned, actor_identity, private_by_source)
    local mesh, source = owned.object, owned.source
    require_condition(same(mesh, owned.identity) and same(mesh:GetOwner(), actor_identity), "Private appearance ownership changed")
    local asset = source.kind == "skeletal" and mesh:GetSkeletalMeshAsset()
        or source.kind == "static" and mesh.StaticMesh
        or source.kind == "chaos-cloth" and mesh:GetClothAsset() or mesh.GroomAsset
    require_condition(same(asset, source.asset_identity), "Private appearance asset changed")
    local expected = transform(source.transform)
    expected.Translation.Z = expected.Translation.Z + OFFSET_Z
    local actual = transform(mesh:K2_GetComponentToWorld())
    require_condition(equal_fields(actual.Translation, expected.Translation) and equal_fields(actual.Rotation, expected.Rotation)
        and equal_fields(actual.Scale3D, expected.Scale3D), "Private appearance transform changed")
    require_condition(mesh:GetCollisionEnabled() == 0 and flag(mesh.bVisibleInSceneCaptureOnly, true)
        and flag(mesh.bHiddenInSceneCapture, not source.visible) and private_lighting(mesh), "Private appearance isolation changed")
    require_condition(mesh:GetNumMaterials() == #source.materials, "Private appearance slot count changed")
    local result = { component = owned.identity, source = source.identity, kind = source.kind, asset = source.asset_identity,
        visible = source.visible, world_transform = actual, materials = {} }
    for index, binding in ipairs(source.materials) do
        local material = mesh:GetMaterial(index - 1)
        require_condition(same(material, binding), "Private appearance binding changed")
        result.materials[index] = record(material, "/Script/Engine.MaterialInterface", "private appearance material")
    end
    if source.kind == "groom" then
        local original = source.appearance_source
        local parent = private_by_source[tostring(original.attach_parent:GetAddress())]
        require_condition(parent ~= nil and same(mesh:GetAttachParent(), parent.identity), "Private groom parent changed")
        require_condition(mesh.bUseCards == original.record.bUseCards and flag(mesh.SimulationSettings.bOverrideSettings, true)
            and flag(mesh.SimulationSettings.SolverSettings.bEnableSimulation, false), "Private groom representation or simulation changed")
        local attachment = type(mesh.AttachmentName) == "string" and mesh.AttachmentName or mesh.AttachmentName:ToString()
        require_condition(attachment == original.record.AttachmentName, "Private groom attachment name changed")
        local groups = array(mesh.GroomGroupsDesc, 16, "private groom descriptors")
        require_condition(#groups == #original.record.groups, "Private groom group count changed")
        result.groom_groups = {}
        for index, expected_group in ipairs(original.record.groups) do
            local observed_group = {}
            for key, expected_value in pairs(expected_group) do
                local actual_value = groups[index][key]
                require_condition(type(expected_value) == "number" and type(actual_value) == "number" and math.abs(actual_value - expected_value) < 0.00001
                    or type(expected_value) == "boolean" and flag(actual_value, expected_value), "Private groom group descriptor changed: " .. key)
                observed_group[key] = actual_value
            end
            result.groom_groups[index] = observed_group
        end
        if valid(original.binding_asset) then require_condition(same(mesh.BindingAsset, original.record.binding_asset), "Private groom binding changed") end
        result.attach_parent, result.binding_asset = parent.identity, original.record.binding_asset
        result.simulation_disabled = true
    elseif source.kind == "chaos-cloth" then
        local original = source.appearance_source
        local parent = private_by_source[tostring(original.attach_parent:GetAddress())]
        require_condition(parent ~= nil and same(mesh:GetAttachParent(), parent.identity), "Private cloth pose parent changed")
        require_condition(flag(mesh:IsSimulationEnabled(), false) and flag(mesh.bEnableSimulation, false)
            and flag(mesh.bUseAttachedParentAsPoseComponent, true) and flag(mesh.bBindToLeaderComponent, false)
            and mesh.BlendWeight == 0 and math.abs(number(mesh.ClothGeometryScale, "private cloth scale") - original.record.cloth.geometry_scale) < 0.00001,
            "Private cloth simulation, pose binding or geometry scale changed")
        result.cloth = { pose_parent = parent.identity, simulation_enabled = mesh:IsSimulationEnabled(),
            use_attached_parent_pose = mesh.bUseAttachedParentAsPoseComponent, bind_to_leader_simulation = mesh.bBindToLeaderComponent,
            blend_weight = mesh.BlendWeight, geometry_scale = mesh.ClothGeometryScale, pose_fidelity_verified = false }
    end
    return result
end

local function configure_light(light, location)
    light:SetLightingChannels(false, false, true)
    light:SetCastShadows(false)
    light:SetLightColor({ R = 1, G = 1, B = 1, A = 1 }, false)
    light:SetUseTemperature(false)
    light:SetIndirectLightingIntensity(0)
    light:SetVolumetricScatteringIntensity(0)
    light:SetIntensityUnits(1)
    light:SetIntensity(2000)
    light:SetAttenuationRadius(800)
    light:K2_SetWorldLocation(location, false, {}, true)
end

local function observe_scalar(getter)
    local ok, value = pcall(getter)
    if not ok then return { ok = false, reason = tostring(value):sub(1, 256) } end
    local kind = type(value)
    if kind == "nil" then return { ok = true, type = kind, value = "nil" } end
    if kind == "number" then
        if value ~= value or math.abs(value) == math.huge then return { ok = false, reason = "Non-finite native observation" } end
    elseif kind ~= "boolean" and kind ~= "string" then return { ok = false, type = kind, reason = "Unsupported native scalar type" } end
    return { ok = true, type = kind, value = value }
end

local function show_flags(capture)
    local result = {}
    for _, entry in ipairs(array(capture:GetShowFlagSettings(), 64, "capture show flags")) do
        local name = type(entry.ShowFlagName) == "string" and entry.ShowFlagName or entry.ShowFlagName:ToString()
        require_condition(type(name) == "string" and #name > 0 and #name <= 80 and result[name] == nil
            and type(entry.Enabled) == "boolean", "Capture show-flag readback is invalid")
        result[name] = entry.Enabled
    end
    return result
end

local function read_profile(capture, resources, profile, actor_identity)
    local actual = show_flags(capture)
    if profile.isolated then
        for _, name in ipairs(ISOLATED_FLAGS) do require_condition(actual[name] == false, "Private show flag did not read back: " .. name) end
    else
        require_condition(next(actual) == nil, "Original diagnostic show-flag override list is not empty")
    end
    local lights = {}
    for _, entry in ipairs(resources.lights) do
        require_condition(same(entry.object, entry.identity) and same(entry.object:GetOwner(), actor_identity)
            and private_lighting(entry.object), "Private lamp changed before profile")
        require_condition(entry.object.IntensityUnits == 1 and math.abs(number(entry.object.Intensity, "lamp intensity") - profile.intensity) < 0.00001,
            "Private lamp intensity or candelas unit did not read back")
        local color = entry.object.LightColor
        require_condition(color.R == 255 and color.G == 255 and color.B == 255 and flag(entry.object.bUseTemperature, false)
            and entry.object.IndirectLightingIntensity == 0 and entry.object.VolumetricScatteringIntensity == 0,
            "Private lamp color or isolated contribution did not read back")
        lights[#lights + 1] = { identity = entry.identity, intensity = entry.object.Intensity, units = entry.object.IntensityUnits,
            color = { R = color.R, G = color.G, B = color.B }, use_temperature = entry.object.bUseTemperature,
            indirect_intensity = entry.object.IndirectLightingIntensity, volumetric_intensity = entry.object.VolumetricScatteringIntensity }
    end
    local post = capture.PostProcessSettings
    local observed = { phase = profile.phase, isolated = profile.isolated, manual = profile.manual, show_flags = actual,
        capture_source = capture.CaptureSource, post_process_blend_weight = capture.PostProcessBlendWeight, lights = lights,
        exposure_method = observe_scalar(function() return post.AutoExposureMethod end),
        exposure_bias = observe_scalar(function() return post.AutoExposureBias end),
        exposure_physical = observe_scalar(function() return post.AutoExposureApplyPhysicalCameraExposure end),
        override_exposure_method = observe_scalar(function() return post.bOverride_AutoExposureMethod end),
        override_exposure_bias = observe_scalar(function() return post.bOverride_AutoExposureBias end),
        override_exposure_physical = observe_scalar(function() return post.bOverride_AutoExposureApplyPhysicalCameraExposure end) }
    require_condition(observed.capture_source == (profile.inventory_color and 9 or 2)
        and observed.post_process_blend_weight == (profile.manual and 1 or 0), "Private profile did not read back")
    if profile.manual then
        require_condition(observed.exposure_method.ok and observed.exposure_method.value == 2 and observed.exposure_bias.ok
            and observed.exposure_bias.value == 0 and observed.exposure_physical.ok and flag(observed.exposure_physical.value, false)
            and flag(post.bOverride_AutoExposureMethod, true) and flag(post.bOverride_AutoExposureBias, true)
            and flag(post.bOverride_AutoExposureApplyPhysicalCameraExposure, true), "Private manual exposure did not read back")
    end
    return observed
end

local function configure_profile(capture, resources, profile, verify_capture, actor_identity)
    verify_capture()
    local settings = {}
    if profile.isolated then
        for _, name in ipairs(ISOLATED_FLAGS) do settings[#settings + 1] = { ShowFlagName = name, Enabled = false } end
    end
    capture:SetShowFlagSettings(settings)
    verify_capture()
    capture.CaptureSource = profile.inventory_color and 9 or 2
    capture.PostProcessBlendWeight = profile.manual and 1 or 0
    if profile.manual then
        local post = capture.PostProcessSettings
        set_native_flag(post, "bOverride_AutoExposureMethod", true)
        set_native_flag(post, "bOverride_AutoExposureBias", true)
        set_native_flag(post, "bOverride_AutoExposureApplyPhysicalCameraExposure", true)
        post.AutoExposureMethod, post.AutoExposureBias = 2, 0
        set_native_flag(post, "AutoExposureApplyPhysicalCameraExposure", false)
    end
    for _, entry in ipairs(resources.lights) do
        verify_capture()
        require_condition(same(entry.object, entry.identity) and same(entry.object:GetOwner(), actor_identity)
            and private_lighting(entry.object), "Private lamp changed before profile setter")
        entry.object:SetIntensity(profile.intensity)
    end
    verify_capture()
    return read_profile(capture, resources, profile, actor_identity)
end

local function observe_actor(actor, identity, world, deps)
    local result = { valid = valid(actor) }
    if not result.valid then result.actor_invalidated = true; return result end
    result.identity_matches = same(actor, identity)
    if not result.identity_matches then return result end
    result.native_is_valid = observe_scalar(function()
        local library = static(deps, "/Script/Engine.Default__KismetSystemLibrary", "/Script/Engine.KismetSystemLibrary")
        local native_function = static(deps, "/Script/Engine.KismetSystemLibrary:IsValid", "/Script/CoreUObject.Function")
        -- The UE4SS wrapper also has IsValid(). Explicit reflected dispatch avoids
        -- accidentally validating the library wrapper instead of this actor.
        return native_function(library, actor)
    end)
    if result.native_is_valid.ok and flag(result.native_is_valid.value, false) then return result end
    result.world_matches = same(actor:GetWorld(), world)
    if not result.world_matches then return result end
    result.being_destroyed = observe_scalar(function() return actor:IsActorBeingDestroyed() end)
    result.destroyed_flag = observe_scalar(function() return actor.bActorIsBeingDestroyed end)
    result.authority = observe_scalar(function() return actor:HasAuthority() end)
    result.local_role = observe_scalar(function() return actor:GetLocalRole() end)
    result.life_span = observe_scalar(function() return actor:GetLifeSpan() end)
    return result
end

function Probe.run(deps)
    local actor, actor_identity, capture, capture_identity, target, target_identity, render_library, world_identity
    local resources = { meshes = {}, lights = {} }
    local created, destroyed, released, captures, exported = false, false, false, 0, false
    local target_owned = false
    local source_snapshot, geometry, math_library, gameplay, spawn, target_outer, appearance_report, preview_components, preview_components_after
    local finish_attempted, spawn_finished, target_new_address = false, false, false
    local frames, view_applied, front_restored = {}, false, false
    local current_profile
    local display = { requested_gamma = 0, requested_force_linear_gamma = true }
    local actor_before_destroy, actor_after_destroy, destroy_call_return, destroy_invoked
    local observation_schedules, observation_schedule_errors = {}, {}
    local ok, result = pcall(function()
        require_condition(type(deps) == "table" and deps.game_thread == true and deps.intent == "eye-private-preview-roundtrip",
            "Explicit game-thread private preview intent required")
        require_condition(type(deps.identity) == "table" and deps.identity.build_id == BUILD_ID
            and deps.identity.executable_sha256 == EXECUTABLE_SHA256, "Current-build identity mismatch")
        require_condition(type(deps.get_player) == "function" and type(deps.find_all_of) == "function"
            and type(deps.static_find_object) == "function" and type(deps.output_exists) == "function" and type(deps.now) == "function",
            "Private preview dependencies are incomplete")
        require_condition(type(deps.nonce) == "string" and #deps.nonce == 32 and deps.nonce:match("^%x+$") ~= nil
            and type(deps.boot_id) == "string" and #deps.boot_id <= 64 and deps.boot_id:match("^%d+%-%d+$") ~= nil, "Invalid private preview request identity")
        local request_key = deps.boot_id .. ":" .. deps.nonce:lower()
        require_condition(not consumed[request_key] and operation_count < 2, "Private preview request was consumed or its two-operation budget is exhausted")
        consumed[request_key], operation_count = true, operation_count + 1
        local directory = type(deps.output_directory) == "string" and deps.output_directory:gsub("\\", "/"):gsub("/+$", "") or ""
        require_condition(directory:lower() == (ROOT .. "/" .. deps.boot_id):lower(), "Private preview export path is outside this driver session")
        local filenames = {}
        for _, phase in ipairs(Geometry.phase_names()) do
            filenames[phase] = "eye-private-" .. deps.nonce:lower() .. "-" .. phase .. ".png"
            require_condition(deps.output_exists(directory .. "/" .. filenames[phase]) == false,
                "Private preview output already exists or cannot be checked")
        end
        no_inventory_doll(deps)
        local existing_actors = existing_addresses(deps, "SceneCapture2D")
        local existing_targets = existing_addresses(deps, "TextureRenderTarget2D")
        local player, snapshot = snapshot_sources(deps, function(report) appearance_report = report end)
        source_snapshot = snapshot
        world_identity = snapshot.world
        render_library = static(deps, "/Script/Engine.Default__KismetRenderingLibrary", "/Script/Engine.KismetRenderingLibrary")
        gameplay = static(deps, "/Script/Engine.Default__GameplayStatics", "/Script/Engine.GameplayStatics")
        math_library = static(deps, "/Script/Engine.Default__KismetMathLibrary", "/Script/Engine.KismetMathLibrary")
        geometry = derive_geometry(snapshot, player, math_library)
        local actor_class = static(deps, "/Script/Engine.SceneCapture2D", "/Script/CoreUObject.Class")
        local mesh_classes = { skeletal = "/Script/Engine.SkeletalMeshComponent", static = "/Script/Engine.StaticMeshComponent", groom = "/Script/HairStrandsCore.GroomComponent", ["chaos-cloth"] = "/Script/ChaosClothAssetEngine.ChaosClothComponent" }
        local light_class = static(deps, "/Script/Engine.PointLightComponent", "/Script/CoreUObject.Class")
        spawn = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Scale3D = { X = 1, Y = 1, Z = 1 },
            Translation = { X = snapshot.location.X, Y = snapshot.location.Y, Z = snapshot.location.Z + OFFSET_Z } }
        actor = gameplay:BeginDeferredActorSpawnFromClass(player:GetWorld(), actor_class, spawn, 1, nil, 0)
        actor_identity = record(actor, "/Script/Engine.SceneCapture2D", "new private capture actor")
        require_condition(not existing_actors[actor_identity.address], "Native factory returned an existing capture actor")
        created = true
        require_condition(actor_identity.address ~= snapshot.player.address and same(actor:GetWorld(), snapshot.world), "Private actor aliases player or world differs")
        capture = actor.CaptureComponent2D
        capture_identity = record(capture, "/Script/Engine.SceneCaptureComponent2D", "new private capture")
        require_condition(same(capture:GetOwner(), actor_identity) and not valid(capture.TextureTarget), "Native capture unexpectedly references an existing target")
        capture_settings(capture)
        actor:SetActorEnableCollision(false)
        finish_attempted = true
        gameplay:FinishSpawningActor(actor, spawn, 0)
        spawn_finished = true
        require_condition(same(actor, actor_identity) and same(actor.CaptureComponent2D, capture_identity) and same(capture:GetOwner(), actor_identity)
            and not valid(capture.TextureTarget), "Private native actor changed during construction")
        target = render_library:CreateRenderTarget2D(player:GetWorld(), 1024, 1024, 2, { R = 0, G = 0, B = 0, A = 0 }, false, false)
        target_identity = record(target, "/Script/Engine.TextureRenderTarget2D", "new private render target")
        target_new_address = not existing_targets[target_identity.address]
        require_condition(target_new_address, "Native target factory returned a preexisting render target")
        target_owned = true
        target_outer = record(target:GetOuter(), "/Script/Engine.World", "new private target outer")
        require_condition(target_outer.address == snapshot.world.address and target_outer.name == snapshot.world.name,
            "New private render target does not belong to the requested world context")
        require_condition(target.SizeX == 1024 and target.SizeY == 1024 and target.RenderTargetFormat == 2,
            "Private target dimensions or format differ from the request")
        display.gamma_before = observe_scalar(function() return target.TargetGamma end)
        display.force_linear_before = observe_scalar(function() return target.bForceLinearGamma end)
        display.gamma_after = observe_scalar(function() return target.TargetGamma end)
        display.force_linear_after = observe_scalar(function() return target.bForceLinearGamma end)
        require_condition(display.gamma_after.ok and display.gamma_after.type == "number" and display.gamma_after.value == 0,
            "Private inventory-color target default gamma did not read back")
        require_condition(display.force_linear_after.ok and flag(display.force_linear_after.value, true),
            "Private inventory-color target default force-linear flag did not read back")
        capture.TextureTarget = target
        require_condition(same(actor, actor_identity) and same(actor.CaptureComponent2D, capture_identity)
            and same(capture:GetOwner(), actor_identity) and same(capture.TextureTarget, target_identity),
            "Private native actor changed during target binding")
        local private_by_source = {}
        local ordered_sources = {}
        for _, kind in ipairs({ "skeletal", "static", "chaos-cloth", "groom" }) do
            for _, source in ipairs(snapshot.meshes) do if source.kind == kind then ordered_sources[#ordered_sources + 1] = source end end
        end
        for _, source in ipairs(ordered_sources) do
            verify_sources(deps, snapshot)
            local copied = transform(source.transform)
            copied.Translation.Z = copied.Translation.Z + OFFSET_Z
            local mesh_class = static(deps, mesh_classes[source.kind], "/Script/CoreUObject.Class")
            local mesh = actor:AddComponentByClass(mesh_class, true, spawn, true)
            local mesh_identity = record(mesh, mesh_classes[source.kind], "private " .. source.field)
            require_condition(mesh_identity.address ~= source.identity.address and same(mesh:GetOwner(), actor_identity), "Cloned mesh aliases or is not privately owned")
            local owned = { object = mesh, identity = mesh_identity, source = source }
            resources.meshes[#resources.meshes + 1] = owned
            configure_primitive(mesh, source)
            configure_appearance(mesh, source, private_by_source)
            mesh:K2_SetWorldTransform(copied, false, {}, true)
            actor:FinishAddComponent(mesh, true, spawn)
            mesh:K2_SetWorldTransform(copied, false, {}, true)
            require_condition(mesh:GetCollisionEnabled() == 0, "Private clone non-collision state did not read back")
            require_condition(flag(mesh.bVisibleInSceneCaptureOnly, true) and flag(mesh.bHiddenInSceneCapture, not source.visible)
                and private_lighting(mesh), "Private clone visibility or lighting channel did not read back")
            private_by_source[source.identity.address] = owned
            if source.visible then capture:ShowOnlyComponent(mesh) end
        end
        local function observe_clones()
            local observed = {}
            for _, owned in ipairs(resources.meshes) do observed[#observed + 1] = observe_clone(owned, actor_identity, private_by_source) end
            return observed
        end
        preview_components = observe_clones()
        local pivot = shifted(snapshot.pivot)
        local forward = vector(player:GetActorForwardVector())
        for _, sign in ipairs({ -1, 1 }) do
            local light = actor:AddComponentByClass(light_class, true, spawn, true)
            local light_identity = record(light, "/Script/Engine.PointLightComponent", "private fill light")
            require_condition(same(light:GetOwner(), actor_identity), "Fill light is not privately owned")
            resources.lights[#resources.lights + 1] = { object = light, identity = light_identity }
            local location = { X = pivot.X + forward.X * 100 - forward.Y * sign * 100,
                Y = pivot.Y + forward.Y * 100 + forward.X * sign * 100, Z = pivot.Z + 60 }
            configure_light(light, location)
            actor:FinishAddComponent(light, true, spawn)
            light:K2_SetWorldLocation(location, false, {}, true)
            require_condition(private_lighting(light), "Private fill light channel did not read back")
        end
        local function verify_capture(expected_target)
            no_inventory_doll(deps)
            require_condition(same(actor, actor_identity) and same(actor.CaptureComponent2D, capture_identity)
                and same(capture, capture_identity) and same(capture:GetOwner(), actor_identity)
                and same(capture.TextureTarget, expected_target), "Private capture ownership or target changed before rendering")
            require_condition(capture.bCaptureEveryFrame == false and capture.bCaptureOnMovement == false
                and capture.bMainViewCamera == false and capture.bMainViewFamily == false and capture.bMainViewResolution == false
                and capture.bRenderInMainRenderer == false and capture.bSuppressWorldPostProcessing == true
                and capture.PrimitiveRenderMode == 2, "Private capture isolation settings did not read back")
        end
        local function export_view(view, profile, output, output_identity, destination)
            verify_sources(deps, snapshot)
            observe_clones()
            verify_capture(output_identity)
            current_profile = configure_profile(capture, resources, profile, function() verify_capture(output_identity) end, actor_identity)
            verify_capture(output_identity)
            local filename = filenames[view.phase]
            require_condition(deps.output_exists(directory .. "/" .. filename) == false, "Private phase output already exists or cannot be checked")
            view_applied = true
            local camera_location, camera_rotation = apply_view(capture, view, math_library)
            local frame = { phase = view.phase, file_name = filename, framing = view.framing, yaw_degrees = view.yaw_degrees,
                zoom = view.zoom, camera_distance = view.distance, field_of_view = view.field_of_view, near_clip = view.near_clip,
                pivot = view.pivot, camera_location = camera_location, camera_rotation = camera_rotation,
                profile = current_profile, target = output_identity, render_target_format = output.RenderTargetFormat,
                target_gamma = output.TargetGamma, force_linear_gamma = output.bForceLinearGamma,
                export_started_at_epoch_ms = number(deps.now(), "export start time") * 1000 }
            verify_capture(output_identity)
            capture:CaptureScene()
            captures = captures + 1
            require_condition(captures <= 9, "Private diagnostic capture budget exceeded")
            exported = true
            render_library:ExportRenderTarget(player:GetWorld(), output, directory, filename)
            frame.export_completed_at_epoch_ms = number(deps.now(), "export completion time") * 1000
            destination[#destination + 1] = frame
            require_condition(equal_fields(vector(capture:K2_GetComponentLocation()), camera_location)
                and equal_fields(rotation(capture:K2_GetComponentRotation()), camera_rotation)
                and capture.CaptureSource == current_profile.capture_source
                and capture.PostProcessBlendWeight == current_profile.post_process_blend_weight, "Private camera changed during export")
            verify_capture(output_identity)
            verify_sources(deps, snapshot)
            observe_clones()
            frame.profile_after = read_profile(capture, resources, profile, actor_identity)
            frame.component_readback_after_export = true
            require_condition(output.RenderTargetFormat == frame.render_target_format and output.TargetGamma == frame.target_gamma
                and output.bForceLinearGamma == frame.force_linear_gamma, "Private target display configuration changed during export")
        end
        for _, view in ipairs(geometry.views) do
            export_view(view, { phase = "isolated-inventory-color", isolated = true, manual = true, intensity = 20, inventory_color = true }, target, target_identity, frames)
        end
        preview_components_after = observe_clones()
        local sources = {}
        for _, source in ipairs(snapshot.meshes) do sources[#sources + 1] = { field = source.field, mesh = source.identity, asset = source.asset_identity, materials = source.materials } end
        return { ok = true, schema = 4, kind = "native-private-eye-preview-evidence", boot_id = deps.boot_id, nonce = deps.nonce:lower(),
            frames = frames, width = 1024, height = 1024, render_target_format = 2, capture_source = 9, target_gamma = target.TargetGamma,
            selected_profile = "isolated-inventory-color", capture_limit = 9, render_target_limit = 1,
            appearance_report = snapshot.appearance_report,
            preview_components = preview_components, preview_components_after = preview_components_after,
            player = snapshot.player, world = snapshot.world, form = snapshot.form, is_wolf_form = snapshot.wolf,
            actor = actor_identity, capture = capture_identity, target = target_identity, target_outer = target_outer,
            target_new_address = target_new_address, target_owned = target_owned,
            spawn_finish_attempted = finish_attempted, spawn_finished = spawn_finished,
            source_meshes = sources, pivot_bone_name = snapshot.pivot_bone_name,
            pivot = pivot, eye_pair = snapshot.landmarks.eye_pair, native_head_bounds = snapshot.head_bounds,
            head_center = geometry.head_center, head_radius = geometry.head_radius, eye_distance = geometry.eye_distance,
            framing_profiles = geometry.profiles,
            capture_timestamp_known = false, frame_verified = false, preview_verified = false, gameplay_verified = false,
            limitation = "New native capture with actual loaded mesh/material references. Visual fidelity, neutral exposure, frame ordering and independent-lifetime rendering need native validation." }
    end)
    local restore_ok, restore_error = pcall(function()
        if view_applied and valid(capture) then
            require_condition(same(actor, actor_identity) and same(actor:GetWorld(), world_identity)
                and same(capture, capture_identity) and same(capture:GetOwner(), actor_identity), "Private camera ownership changed before front restoration")
            apply_view(capture, geometry.views[1], math_library)
            front_restored = true
        end
    end)
    local cleanup_ok, cleanup_error = pcall(function()
        if valid(actor) and created then
            require_condition(actor_identity ~= nil and same(actor, actor_identity) and same(actor:GetWorld(), world_identity), "Private actor identity changed before cleanup")
            if valid(capture) then
                require_condition(same(capture, capture_identity) and same(capture:GetOwner(), actor_identity), "Private capture ownership changed before cleanup")
                capture.bCaptureEveryFrame, capture.bCaptureOnMovement = false, false
                capture.TextureTarget = nil
            end
            -- Complete a proven new plain actor once if configuration failed
            -- before normal finalization. Never repeat a failed finish call.
            if not finish_attempted then
                require_condition(gameplay ~= nil and spawn ~= nil, "Deferred actor finalization context is unavailable")
                finish_attempted = true
                gameplay:FinishSpawningActor(actor, spawn, 0)
                spawn_finished = true
            end
            actor_before_destroy = observe_actor(actor, actor_identity, world_identity, deps)
            destroy_invoked = true
            destroy_call_return = observe_scalar(function() return actor:K2_DestroyActor() end)
            actor_after_destroy = observe_actor(actor, actor_identity, world_identity, deps)
            require_condition(destroy_call_return.ok, "Private actor destroy call raised an error")
            destroyed = not valid(actor)
                or (actor_after_destroy.native_is_valid and actor_after_destroy.native_is_valid.ok and flag(actor_after_destroy.native_is_valid.value, false))
                or (actor_after_destroy.being_destroyed and actor_after_destroy.being_destroyed.ok and flag(actor_after_destroy.being_destroyed.value, true))
                or (actor_after_destroy.identity_matches == true and actor_after_destroy.world_matches == true
                    and actor_after_destroy.destroyed_flag and actor_after_destroy.destroyed_flag.ok
                    and flag(actor_after_destroy.destroyed_flag.value, true))
            destroyed = destroyed == true
            require_condition(destroyed, "Private actor destruction is not yet acknowledged")
        else destroyed = created end
    end)
    local release_ok, release_error = pcall(function()
        if valid(target) and target_owned then
            require_condition(target_identity ~= nil and same(target, target_identity), "Private render target changed before release")
            require_condition(not valid(capture) or (same(capture, capture_identity) and not valid(capture.TextureTarget)),
                "Private render target is still bound to a surviving capture")
            render_library:ReleaseRenderTarget2D(target)
            released = true
        end
    end)
    local source_ok, source_error = pcall(function()
        if source_snapshot then verify_sources(deps, source_snapshot) end
    end)
    -- Destruction is latent in Unreal. These callbacks only observe the exact
    -- newly owned actor after later engine frames; they never repeat destruction
    -- or convert a scheduled callback into a cleanup success claim.
    if destroy_invoked and type(deps.schedule_after_frames) == "function" and type(deps.report_cleanup_observation) == "function" then
        for _, frames_later in ipairs({ 1, 3, 30 }) do
            local observation_delivered = false
            local schedule_ok, schedule_result = pcall(deps.schedule_after_frames, frames_later, function(schedule)
                if observation_delivered then return end
                observation_delivered = true
                local observation_ok, observation = pcall(function()
                    require_condition(type(schedule) == "table" and schedule.schedule_complete == true
                        and schedule.requested_frames == frames_later and type(schedule.elapsed_frames) == "number"
                        and schedule.elapsed_frames % 1 == 0 and schedule.elapsed_frames >= frames_later
                        and schedule.elapsed_frames <= 120, "Native frame scheduler did not confirm its bounded observation interval")
                    require_condition(type(schedule.started_frame) == "number" and type(schedule.observed_frame) == "number"
                        and schedule.started_frame >= 0 and schedule.started_frame % 1 == 0 and schedule.observed_frame % 1 == 0
                        and schedule.observed_frame - schedule.started_frame == schedule.elapsed_frames,
                        "Native frame counter evidence is missing or inconsistent")
                    return observe_actor(actor, actor_identity, world_identity, deps)
                end)
                local receipt = { kind = "native-private-preview-cleanup-observation", schema = 1,
                    boot_id = deps.boot_id, nonce = deps.nonce:lower(), after_frames = frames_later,
                    schedule = observation_ok and { requested_frames = schedule.requested_frames, elapsed_frames = schedule.elapsed_frames,
                        schedule_complete = true, started_frame = schedule.started_frame, observed_frame = schedule.observed_frame }
                        or { requested_frames = frames_later, schedule_complete = false },
                    actor = actor_identity, capture = capture_identity, target = target_identity, world = world_identity,
                    target_release_requested = released, observation_ok = observation_ok,
                    actor_state = observation_ok and observation or nil,
                    frame_verified = false, preview_verified = false, gameplay_verified = false }
                if not observation_ok then receipt.observation_error = tostring(observation):sub(1, 512) end
                deps.report_cleanup_observation(receipt)
            end)
            if schedule_ok and type(schedule_result) == "number" and schedule_result > 0 then
                observation_schedules[#observation_schedules + 1] = { after_frames = frames_later, handle = schedule_result }
            else observation_schedule_errors[#observation_schedule_errors + 1] = { after_frames = frames_later,
                reason = tostring(schedule_result):sub(1, 512) } end
        end
    end
    local actor_invalidated = created and not valid(actor)
    local destruction_pending = created and valid(actor) and destroyed
    if ok and restore_ok and cleanup_ok and release_ok and source_ok then
        result.created, result.destruction_acknowledged, result.target_released, result.capture_requests, result.export_invoked = created, destroyed, released, captures, exported
        result.actor_invalidated, result.destruction_pending = actor_invalidated, destruction_pending
        result.spawn_finish_attempted, result.spawn_finished = finish_attempted, spawn_finished
        result.front_restored = front_restored
        result.display_configuration, result.actor_before_destroy, result.actor_after_destroy = display, actor_before_destroy, actor_after_destroy
        result.destroy_call_return, result.destroy_invoked = destroy_call_return, destroy_invoked == true
        result.cleanup_observation_schedules, result.cleanup_observation_schedule_errors = observation_schedules, observation_schedule_errors
        return result
    end
    local failure = { ok = false, created = created, destruction_acknowledged = destroyed, actor_invalidated = actor_invalidated,
        destruction_pending = destruction_pending, target_released = released, capture_requests = captures, export_invoked = exported,
        actor = actor_identity, capture = capture_identity, target = target_identity, target_outer = target_outer, world = world_identity,
        target_owned = target_owned, target_new_address = target_new_address, spawn_finish_attempted = finish_attempted, spawn_finished = spawn_finished,
        frames = frames, current_profile = current_profile, appearance_report = appearance_report,
        preview_components = preview_components, preview_components_after = preview_components_after,
        front_restored = front_restored, frame_verified = false, preview_verified = false, gameplay_verified = false,
        display_configuration = display, actor_before_destroy = actor_before_destroy, actor_after_destroy = actor_after_destroy,
        destroy_invoked = destroy_invoked == true, destroy_call_return = destroy_call_return,
        cleanup_observation_schedules = observation_schedules, cleanup_observation_schedule_errors = observation_schedule_errors,
        reason = tostring(not ok and result or "Private renderer cleanup failed"):sub(1, 1024) }
    if not cleanup_ok then failure.cleanup_error = tostring(cleanup_error):sub(1, 1024) end
    if not restore_ok then failure.restore_error = tostring(restore_error):sub(1, 1024) end
    if not release_ok then failure.release_error = tostring(release_error):sub(1, 1024) end
    if not source_ok then failure.source_error = tostring(source_error):sub(1, 1024) end
    if ok and type(result) == "table" then
        -- Preserve independently observed capture metadata if only later cleanup
        -- failed. This does not change ok=false or acknowledge native destruction.
        failure.capture_operation_completed = true
        for _, key in ipairs({ "schema", "kind", "boot_id", "nonce", "width", "height", "render_target_format",
            "capture_source", "target_gamma", "player", "form", "is_wolf_form", "source_meshes", "pivot_bone_name",
            "pivot", "eye_pair", "native_head_bounds", "head_center", "head_radius", "eye_distance", "framing_profiles",
            "capture_timestamp_known", "limitation", "selected_profile", "capture_limit", "render_target_limit", "appearance_report" }) do failure[key] = result[key] end
    end
    return failure
end

return Probe
