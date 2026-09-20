local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_private_eye_renderer_v12")

-- Uninstalled lifecycle prototype. Uses only native classes and already loaded player assets.
--
-- V12 is the measured follow-up to V11. V11's first live frame was accepted at 5,979 ms against
-- the honest 5,000 ms frame-age bound, and its ten-second lease died between apply and the next
-- capture because the write phase consumed the margin. V12 removes the remaining mid-step full
-- sweep (the pre-scalar verification in update_preview, which the entry sweep and the cohort
-- guards already bracket) and verifies the exact private eye receiver once per eye in the
-- read-only scalar passes instead of once per parameter, because a read pass performs no native
-- setter that needs a before-next-write guard. The write pass still re-checks the receiver before
-- every setter, so a replaced live slot or reparented private MID still stops the batch before
-- the next native write. Per exported frame this is three full verifications plus the pose
-- refresh: four appearance inspections, down from V11's five.
--
-- The entry sweep stays: it re-verifies against the live eye registry after an explicit apply or
-- restore created or removed a registry-owned live MID, so the narrow pins are refreshed before
-- any cohort guard is trusted. capture_preview keeps both export-boundary sweeps, which is the
-- real export contract. Every boundary keeps its V10/V11 meaning; nothing below is ever reported
-- as appearance, generation or scalar readback verification.
local Renderer = {}
local Geometry = require("DawnwalkerEyePreviewGeometryV8")
local Appearance = require("DawnwalkerAppearanceSourcesV9")
local BUILD_ID = "25129649"
local EXECUTABLE_SHA256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
local ROOT = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-frames"
local OFFSET_Z = 100000
local ISOLATED_FLAGS = { "Fog", "VolumetricFog", "Atmosphere", "Cloud", "SkyLighting", "GlobalIllumination",
    "LumenGlobalIllumination", "ReflectionEnvironment", "LumenReflections", "ScreenSpaceReflections", "AmbientCubemap",
    "Bloom", "LocalExposure", "LensFlares", "MotionBlur", "DepthOfField", "Vignette", "Grain", "ColorGrading" }
local PROFILE = { phase = "persistent-appearance", isolated = true, manual = true, inventory_color = true, intensity = 20 }



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
    return previous ~= nil and valid(object) and tostring(object:GetAddress()) == previous.address and object:GetFullName() == previous.name
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, child in pairs(left) do if not equal(child, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local function equal_fields(left, right)
    for key, expected in pairs(right) do if math.abs(number(left[key], key) - expected) > 0.00001 then return false end end
    return true
end

local MAX_DIAGNOSTIC_STAGES = 16

local function diagnostics(handle)
    if handle.diagnostics == nil then
        handle.diagnostics = { kind = "native-private-eye-renderer-stage-diagnostics", renderer = "v12",
            full_verifications = 0, receiver_guards = 0, stage_order = {}, stages = {} }
    end
    return handle.diagnostics
end

local function count(handle, field)
    local observed = diagnostics(handle)
    observed[field] = observed[field] + 1
    local current = handle.current_stage
    if current ~= nil then current[field] = current[field] + 1 end
end

-- The engine's tick-cached game clock. It bounds the native call, and inside a single tick the
-- start and end can be equal. It is never a GPU completion timestamp and is reported as such.
local function call_clock_ms(handle, deps)
    local ok, seconds = pcall(function() return handle.gameplay:GetRealTimeSeconds(deps.get_player():GetWorld()) end)
    if not ok or type(seconds) ~= "number" or seconds ~= seconds or math.abs(seconds) == math.huge then return nil end
    return seconds * 1000
end

-- Opens a bounded accounting scope for one public renderer stage and returns its closer. The
-- closer is only reached on success; a raised error leaves the stage open and the next stage
-- entry resets the pointer, so counts never migrate into an unrelated stage.
local function enter_stage(handle, deps, name)
    local observed = diagnostics(handle)
    local entry = observed.stages[name]
    if entry == nil then
        require_condition(#observed.stage_order < MAX_DIAGNOSTIC_STAGES, "Renderer stage diagnostics exceeded their bound")
        entry = { name = name, calls = 0, full_verifications = 0, receiver_guards = 0,
            last_call_interval_ms = 0, total_call_interval_ms = 0 }
        observed.stages[name], observed.stage_order[#observed.stage_order + 1] = entry, name
    end
    entry.calls = entry.calls + 1
    handle.current_stage = entry
    local started = call_clock_ms(handle, deps)
    return function()
        local completed = call_clock_ms(handle, deps)
        if started ~= nil and completed ~= nil and completed >= started then
            entry.last_call_interval_ms = completed - started
            entry.total_call_interval_ms = entry.total_call_interval_ms + entry.last_call_interval_ms
        end
        handle.current_stage = nil
    end
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

local function inspect_appearance(deps)
    local observed = Appearance.run({ game_thread = deps.is_in_game_thread() == true,
        identity = deps.identity, get_player = deps.get_player, static_find_object = deps.static_find_object })
    require_condition(observed.ok == true and observed.report.discovery_complete == true,
        "Actual appearance inspection failed: " .. tostring(observed.reason))
    require_condition(observed.report.unsupported_visible_sources ~= true, "Actual visible appearance has no supported clone route")
    return observed
end

local function appearance_fingerprint(report, bindings, head_identity, allow_pose)
    local normalized = copy(report)
    for _, source in ipairs(normalized.sources) do
        if allow_pose then
            -- Motion is expected; scaling changes geometry and invalidates this lease.
            source.world_transform = { Scale3D = copy(source.world_transform.Scale3D) }
            source.relative_transform = { Scale3D = copy(source.relative_transform.Scale3D) }
        end
        if equal(source.component, head_identity) then
            for _, material in ipairs(source.materials) do
                for _, eye in ipairs(bindings.bindings) do
                    if material.slot == eye.slot then material.material = copy(eye.original_identity) end
                end
            end
        end
    end
    return normalized
end

local function snapshot_sources(deps)
    local player = deps.get_player()
    local snapshot = { player = record(player, "/Script/Dawnwalker.DawnwalkerPlayerCharacter", "player"), meshes = {} }
    snapshot.world = record(player:GetWorld(), "/Script/Engine.World", "world")
    snapshot.form, snapshot.wolf = player.Form, player:IsInWolfForm()
    require_condition((snapshot.form == 0 or snapshot.form == 1) and snapshot.wolf == false, "Unsupported player form")
    snapshot.location, snapshot.rotation = vector(player:K2_GetActorLocation()), rotation(player:K2_GetActorRotation())
    local observed = inspect_appearance(deps)
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
        if name:ToString() == deps.pivot_bone_name then pivot_name = name; snapshot.pivot_index = index; break end
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
    snapshot.head = fields.HeadMesh
    return player, snapshot
end


local function verify_sources(deps, snapshot, allow_movement)
    local player = deps.get_player()
    require_condition(same(player, snapshot.player) and same(player:GetWorld(), snapshot.world)
        and player.Form == snapshot.form and player:IsInWolfForm() == snapshot.wolf, "Player/world/form changed during private preview")
    require_condition(snapshot.eye_bindings ~= nil and deps.eye_bindings.verify(snapshot.eye_bindings, player, player.HeadMesh) == true,
        "Live eye material ownership or generation changed")
    local current = inspect_appearance(deps)
    require_condition(deps.eye_bindings.verify(snapshot.eye_bindings, player, player.HeadMesh) == true,
        "Live eye binding changed during appearance inspection")
    local fingerprint = appearance_fingerprint(current.report, snapshot.eye_bindings, snapshot.head.identity, true)
    require_condition(equal(fingerprint, snapshot.appearance_generation), "Appearance membership, attachment, visibility or material generation changed")
    if not allow_movement then
        require_condition(equal_fields(vector(player:K2_GetActorLocation()), snapshot.location)
            and equal_fields(rotation(player:K2_GetActorRotation()), snapshot.rotation), "Player transform changed during capture")
        require_condition(equal(appearance_fingerprint(current.report, snapshot.eye_bindings, snapshot.head.identity, false),
            snapshot.appearance_pose), "Source appearance pose changed during capture")
    end
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

local function observe_clone(owned, actor_identity, private_by_source, defer_transform)
    local mesh, source = owned.object, owned.source
    require_condition(same(mesh, owned.identity) and same(mesh:GetOwner(), actor_identity), "Private appearance ownership changed")
    local asset = source.kind == "skeletal" and mesh:GetSkeletalMeshAsset()
        or source.kind == "static" and mesh.StaticMesh
        or source.kind == "chaos-cloth" and mesh:GetClothAsset() or mesh.GroomAsset
    require_condition(same(asset, source.asset_identity), "Private appearance asset changed")
    local expected = owned.applied_transform and transform(owned.applied_transform) or transform(source.transform)
    if not owned.applied_transform then expected.Translation.Z = expected.Translation.Z + OFFSET_Z end
    local actual = transform(mesh:K2_GetComponentToWorld())
    if not defer_transform then
        require_condition(equal_fields(actual.Translation, expected.Translation) and equal_fields(actual.Rotation, expected.Rotation)
            and equal_fields(actual.Scale3D, expected.Scale3D), "Private appearance transform changed")
    end
    require_condition(mesh:GetCollisionEnabled() == 0 and flag(mesh.bVisibleInSceneCaptureOnly, true)
        and flag(mesh.bHiddenInSceneCapture, not source.visible) and private_lighting(mesh), "Private appearance isolation changed")
    require_condition(mesh:GetNumMaterials() == #source.materials, "Private appearance slot count changed")
    local result = { component = owned.identity, source = source.identity, kind = source.kind, asset = source.asset_identity,
        visible = source.visible, world_transform = actual, materials = {} }
    for index, binding in ipairs(source.materials) do
        local material = mesh:GetMaterial(index - 1)
        local eye = owned.eyes and owned.eyes[index - 1]
        if eye then
            require_condition(same(material, eye.identity) and same(eye.object:GetOuter(), owned.identity)
                and same(eye.object.Parent, eye.binding.original_identity), "Private eye material was replaced or reparented")
        else require_condition(same(material, binding), "Private appearance binding changed") end
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
    light:SetIntensity(20)
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

local function observe_actor(handle, deps)
    local actor, result = handle.actor, { valid = valid(handle.actor) }
    if not result.valid then result.actor_invalidated = true; return result end
    result.identity_matches = same(actor, handle.actor_identity)
    if not result.identity_matches then return result end
    result.native_is_valid = observe_scalar(function()
        local library = static(deps, "/Script/Engine.Default__KismetSystemLibrary", "/Script/Engine.KismetSystemLibrary")
        local native_function = static(deps, "/Script/Engine.KismetSystemLibrary:IsValid", "/Script/CoreUObject.Function")
        return native_function(library, actor)
    end)
    if result.native_is_valid.ok and flag(result.native_is_valid.value, false) then return result end
    result.world_matches = same(actor:GetWorld(), handle.snapshot.world)
    if not result.world_matches then return result end
    result.being_destroyed = observe_scalar(function() return actor:IsActorBeingDestroyed() end)
    result.destroyed_flag = observe_scalar(function() return actor.bActorIsBeingDestroyed end)
    result.authority = observe_scalar(function() return actor:HasAuthority() end)
    result.local_role = observe_scalar(function() return actor:GetLocalRole() end)
    return result
end

local function refresh_pose(deps, snapshot, player)
    local observed = inspect_appearance(deps)
    snapshot.appearance_pose = appearance_fingerprint(observed.report, snapshot.eye_bindings, snapshot.head.identity, false)
    snapshot.location, snapshot.rotation = vector(player:K2_GetActorLocation()), rotation(player:K2_GetActorRotation())
    for _, source in ipairs(snapshot.meshes) do source.transform = transform(source.source:K2_GetComponentToWorld()) end
    local head = snapshot.head.source
    require_condition(head:GetNumBones() == snapshot.landmarks.bone_count, "Native head skeleton changed")
    local function socket(index, expected)
        local name = head:GetBoneName(index)
        require_condition(name:ToString() == expected and head:DoesSocketExist(name) == true, "Cached head landmark changed")
        return vector(head:GetSocketLocation(name))
    end
    snapshot.pivot = socket(snapshot.pivot_index, snapshot.pivot_bone_name)
    for _, side in ipairs({ "left", "right" }) do
        local endpoint = snapshot.landmarks.eye_pair[side]
        endpoint.location = socket(endpoint.index, endpoint.name)
    end
    snapshot.head_transform = snapshot.head.transform
end

local function view_geometry(geometry, view, player)
    require_condition(type(view) == "table", "Preview view is required")
    local profile = geometry.profiles[view.framing]
    require_condition(profile ~= nil and number(view.yawDegrees, "preview yaw") >= -69 and view.yawDegrees <= 69,
        "Preview framing or yaw is unsupported")
    local distance = profile.default_distance / number(view.zoom, "preview zoom")
    require_condition(view.zoom > 0 and distance >= profile.minimum_distance - 0.00001
        and distance <= profile.maximum_distance + 0.00001, "Preview zoom exceeds native geometry bounds")
    local forward = vector(player:GetActorForwardVector())
    local length = math.sqrt(forward.X ^ 2 + forward.Y ^ 2)
    require_condition(length >= 0.5 and length <= 1.5 and math.abs(forward.Z) <= 0.5, "Unsupported preview facing basis")
    local angle, pivot = math.rad(view.yawDegrees), profile.pivot
    local direction_x = (forward.X * math.cos(angle) - forward.Y * math.sin(angle)) / length
    local direction_y = (forward.X * math.sin(angle) + forward.Y * math.cos(angle)) / length
    return { pivot = vector(pivot), distance = distance, field_of_view = profile.field_of_view, near_clip = profile.near_clip,
        location = { X = pivot.X + direction_x * distance, Y = pivot.Y + direction_y * distance, Z = pivot.Z } }
end

local function verify_capture(handle)
    require_condition(not handle.closed and same(handle.actor, handle.actor_identity)
        and same(handle.actor:GetWorld(), handle.snapshot.world)
        and same(handle.actor.CaptureComponent2D, handle.capture_identity)
        and same(handle.capture, handle.capture_identity) and same(handle.capture:GetOwner(), handle.actor_identity)
        and same(handle.capture.TextureTarget, handle.target_identity), "Private capture ownership changed")
    local capture, target = handle.capture, handle.target
    require_condition(same(target, handle.target_identity) and same(target:GetOuter(), handle.snapshot.world)
        and target.SizeX == 1024 and target.SizeY == 1024 and target.RenderTargetFormat == 2
        and target.TargetGamma == 0 and flag(target.bForceLinearGamma, true), "Private render target changed")
    require_condition(flag(capture.bCaptureEveryFrame, false) and flag(capture.bCaptureOnMovement, false)
        and flag(capture.bMainViewCamera, false) and flag(capture.bMainViewFamily, false)
        and flag(capture.bMainViewResolution, false) and flag(capture.bRenderInMainRenderer, false)
        and flag(capture.bSuppressWorldPostProcessing, true) and capture.PrimitiveRenderMode == 2
        and capture.CaptureSource == 9, "Private capture isolation changed")
end

local function verify_mesh(handle, entry, defer_transform)
    return observe_clone(entry, handle.actor_identity, handle.private_by_source, defer_transform)
end


-- Pins each live eye slot to the exact material the eye registry has just verified, including its
-- outer and parent. The narrow loop guard then only has to prove that slot has not moved since,
-- which needs identity alone and never re-enters the registry.
local function record_live_eyes(deps, handle)
    local head = deps.get_player().HeadMesh
    local observed = {}
    for _, binding in ipairs(handle.snapshot.eye_bindings.bindings) do
        observed[binding.slot] = record(head:GetMaterial(binding.slot), "/Script/Engine.MaterialInterface", "live eye material")
    end
    handle.live_eyes = observed
end

local function verify_owned(deps, handle, allow_movement, defer_transform)
    count(handle, "full_verifications")
    verify_capture(handle)
    verify_sources(deps, handle.snapshot, allow_movement)
    for _, entry in ipairs(handle.meshes) do verify_mesh(handle, entry, defer_transform) end
    if handle.profile_ready then read_profile(handle.capture, handle, PROFILE, handle.actor_identity) end
    for _, entry in ipairs(handle.lights) do
        require_condition(same(entry.object, entry.identity) and same(entry.object:GetOwner(), handle.actor_identity)
            and private_lighting(entry.object), "Private light ownership or isolation changed")
    end
    record_live_eyes(deps, handle)
end


-- Ownership-only guard for the tight write loops that sit between two full verifications.
--
-- It proves that this lease still addresses the same player, world, form, head component and
-- head asset, that the original eye constants are unchanged, and that each live eye slot still
-- holds exactly the material the eye registry verified at the last full boundary. It deliberately
-- enumerates no live appearance cohort, re-enters no registry and reads none of the twenty-two
-- tracked parameters, so it must never be reported as appearance, generation or scalar readback
-- verification. Those stay with verify_owned at the surrounding transaction boundary.
local function verify_live_ownership(deps, handle)
    local snapshot = handle.snapshot
    require_condition(handle.closed ~= true, "Private preview is already closed")
    require_condition(type(handle.live_eyes) == "table", "A full verification must precede any narrow receiver guard")
    local player = deps.get_player()
    require_condition(same(player, snapshot.player) and same(player:GetWorld(), snapshot.world)
        and player.Form == snapshot.form and player:IsInWolfForm() == snapshot.wolf,
        "Player, world or form changed during private preview")
    local head = player.HeadMesh
    require_condition(same(head, snapshot.head.identity) and same(head:GetSkeletalMeshAsset(), snapshot.head.asset_identity),
        "Live head component or head asset changed during private preview")
    for _, binding in ipairs(snapshot.eye_bindings.bindings) do
        require_condition(same(binding.original_material, binding.original_identity), "Original live eye binding changed")
        require_condition(same(head:GetMaterial(binding.slot), handle.live_eyes[binding.slot]),
            "Live eye slot changed since the last full verification")
    end
    require_condition(same(handle.actor, handle.actor_identity) and same(handle.capture, handle.capture_identity)
        and same(handle.capture:GetOwner(), handle.actor_identity)
        and same(handle.capture.TextureTarget, handle.target_identity), "Private capture ownership changed")
end

-- Every owned private receiver is still re-checked between writes, so a corrupted clone still
-- stops the batch before the next native write. What this does not do is re-enumerate the live
-- appearance cohort or re-read the tracked parameters; that is the expensive part and it belongs
-- at the transaction boundary.
local function verify_private_cohort(deps, handle, defer_transform)
    verify_live_ownership(deps, handle)
    verify_capture(handle)
    for _, entry in ipairs(handle.meshes) do verify_mesh(handle, entry, defer_transform) end
    for _, entry in ipairs(handle.lights) do
        require_condition(same(entry.object, entry.identity) and same(entry.object:GetOwner(), handle.actor_identity)
            and private_lighting(entry.object), "Private light ownership or isolation changed")
    end
end

local function verify_receiver(deps, handle, receiver, eye, defer_transform)
    count(handle, "receiver_guards")
    verify_private_cohort(deps, handle, defer_transform)
    require_condition(same(receiver.object, receiver.identity) and same(receiver.object:GetOwner(), handle.actor_identity),
        "Private receiver ownership changed")
    if eye ~= nil then
        require_condition(same(eye.object, eye.identity) and same(eye.object:GetOuter(), receiver.identity)
            and same(eye.object.Parent, eye.binding.original_identity)
            and same(receiver.object:GetMaterial(eye.binding.slot), eye.identity),
            "Private eye receiver was replaced or reparented")
    end
end

local function create_eye_instances(deps, handle, entry)
    entry.eyes = {}
    for _, binding in ipairs(handle.snapshot.eye_bindings.bindings) do
        require_condition(binding.slot == 3 or binding.slot == 4, "Unsupported native eye slot")
        require_condition(entry.eyes[binding.slot] == nil and same(binding.original_material, binding.original_identity),
            "Original eye binding changed")
        local name = binding.native_name:ToString()
        local outer_path = entry.identity.name:match("^%S+ (.+)$")
        require_condition(outer_path ~= nil and type(name) == "string" and #name > 0 and #name <= 128,
            "Native preview instance name is unavailable")
        require_condition(not valid(deps.static_find_object(outer_path .. "." .. name)), "Preview material instance already exists")
        verify_capture(handle)
        verify_sources(deps, handle.snapshot, false)
        local material = entry.object:CreateDynamicMaterialInstance(binding.slot, binding.original_material, binding.native_name)
        local identity = record(material, "/Script/Engine.MaterialInstanceDynamic", "private preview eye instance")
        -- These MIDs always derive from the original MIC, never a live player's MID.
        for _, live in ipairs(handle.snapshot.eye_bindings.bindings) do
            require_condition(identity.address ~= live.original_identity.address and identity.address ~= live.current_identity.address,
                "Preview material aliases a live eye binding")
        end
        require_condition(same(material:GetOuter(), entry.identity) and same(material.Parent, binding.original_identity)
            and same(entry.object:GetMaterial(binding.slot), identity), "Private eye instance ownership did not read back")
        entry.eyes[binding.slot] = { object = material, identity = identity, binding = binding }
    end
end

local function eye_settings(deps, handle, requested, write, already_verified)
    -- One complete appearance/material/generation validation for the whole settings pass. V9 ran
    -- this inside the scalar loop, which cost eight full sweeps for eight values. V11 let a caller
    -- that had just completed the verification its call site requires skip the repeat. V12 keeps
    -- the entry and export sweeps as the real full boundaries; a read-only scalar pass verifies
    -- its exact receiver once per eye (no setter runs, so no per-parameter guard is needed), while
    -- the write pass still re-checks the receiver before every native setter so a replaced live
    -- slot or reparented private MID stops the batch before the next write. The default remains
    -- fail-closed: an unlabelled call still performs the full sweep.
    if already_verified ~= true then verify_owned(deps, handle, false) end
    local canonical = deps.eye_bindings.validate_settings(requested, handle.snapshot.eye_bindings)
    require_condition(type(canonical) == "table" and type(canonical.values) == "table" and #canonical.values <= 64,
        "Eye binding registry returned invalid canonical settings")
    local observed, consumed = { schemaId = canonical.schemaId, values = {} }, {}
    for _, entry in ipairs(handle.meshes) do
        for _, eye in pairs(entry.eyes or {}) do
            if not write then verify_receiver(deps, handle, entry, eye) end
            for _, parameter in ipairs(eye.binding.parameters) do
                local wanted, wanted_index
                for index, candidate in ipairs(canonical.values) do
                    if equal(candidate.parameter, parameter.parameter) then
                        require_condition(wanted == nil, "Duplicate preview parameter")
                        wanted, wanted_index = candidate.value, index
                    end
                end
                require_condition(wanted ~= nil and wanted.kind == "scalar" and not consumed[wanted_index], "Unsupported preview eye value")
                local scalar = number(wanted.value, "preview scalar")
                require_condition(scalar >= parameter.min and scalar <= parameter.max, "Preview scalar exceeds observed native bounds")
                if write then
                    verify_receiver(deps, handle, entry, eye)
                    eye.object:SetScalarParameterValueByInfo(parameter.native_info, scalar)
                end
                local actual = number(eye.object:K2_GetScalarParameterValueByInfo(parameter.native_info), "native preview scalar")
                require_condition(math.abs(actual - scalar) <= parameter.tolerance, "Private preview scalar did not read back")
                consumed[wanted_index] = true
                observed.values[wanted_index] = { parameter = copy(parameter.parameter), value = { kind = "scalar", value = actual } }
            end
        end
    end
    for index in ipairs(canonical.values) do require_condition(consumed[index] == true, "Preview parameter has no owned material receiver") end
    return observed
end

local function cleanup(handle, deps)
    if handle.cleanup_receipt then return handle.cleanup_receipt end
    handle.closed = true
    local receipt = { owned_cleanup_acknowledged = false, actor = handle.actor_identity, capture = handle.capture_identity,
        target = handle.target_identity, target_outer = handle.target_outer, target_owned = handle.target_owned == true,
        nonce = handle.nonce, boot_id = handle.boot_id, pending_frames = {},
        display_configuration = copy(handle.display), destruction_acknowledged = false, target_release_requested = false }
    for sequence, filename in pairs(handle.pending) do
        receipt.pending_frames[#receipt.pending_frames + 1] = { sequence = sequence, file_name = filename }
    end
    table.sort(receipt.pending_frames, function(left, right) return left.sequence < right.sequence end)
    local destroyed, destroy_error = pcall(function()
        if not handle.created then return end
        if not valid(handle.actor) then receipt.destruction_acknowledged = true; return end
        require_condition(same(handle.actor, handle.actor_identity) and same(handle.actor:GetWorld(), handle.snapshot.world),
            "Private actor identity changed before cleanup")
        if valid(handle.capture) then
            require_condition(same(handle.capture, handle.capture_identity) and same(handle.capture:GetOwner(), handle.actor_identity),
                "Private capture ownership changed before cleanup")
            handle.capture.bCaptureEveryFrame, handle.capture.bCaptureOnMovement = false, false
            handle.capture.TextureTarget = nil
        end
        if not handle.finish_attempted then
            handle.finish_attempted = true
            handle.gameplay:FinishSpawningActor(handle.actor, handle.spawn, 0)
            handle.spawn_finished = true
        end
        receipt.actor_before_destroy = observe_actor(handle, deps)
        receipt.destroy_call_return = observe_scalar(function() return handle.actor:K2_DestroyActor() end)
        receipt.actor_after_destroy = observe_actor(handle, deps)
        require_condition(receipt.destroy_call_return.ok, "Private actor destroy call raised an error")
        local after = receipt.actor_after_destroy
        receipt.native_logically_invalid = after.identity_matches == true and after.native_is_valid ~= nil
            and after.native_is_valid.ok == true and flag(after.native_is_valid.value, false)
        receipt.destruction_acknowledged = not valid(handle.actor) or receipt.native_logically_invalid
            or (after.identity_matches == true and after.world_matches == true
                and ((after.being_destroyed and after.being_destroyed.ok and flag(after.being_destroyed.value, true))
                    or (after.destroyed_flag and after.destroyed_flag.ok and flag(after.destroyed_flag.value, true))))
        require_condition(receipt.destruction_acknowledged, "Private actor destruction is not yet acknowledged")
    end)
    local released, release_error = pcall(function()
        if not handle.target_owned or not valid(handle.target) then return end
        require_condition(same(handle.target, handle.target_identity), "Private target identity changed before release")
        require_condition(not valid(handle.capture) or (same(handle.capture, handle.capture_identity) and not valid(handle.capture.TextureTarget)),
            "Private target remains bound to a capture")
        handle.render:ReleaseRenderTarget2D(handle.target)
        receipt.target_release_requested = true
    end)
    receipt.actor_invalidated = handle.created == true and not valid(handle.actor)
    receipt.destruction_pending = handle.created == true and valid(handle.actor) and receipt.destruction_acknowledged
    receipt.owned_cleanup_acknowledged = destroyed and released and (not handle.created or receipt.destruction_acknowledged)
        and (not handle.target_owned or not valid(handle.target) or receipt.target_release_requested)
    if not destroyed then receipt.cleanup_error = tostring(destroy_error):sub(1, 512) end
    if not released then receipt.release_error = tostring(release_error):sub(1, 512) end
    if receipt.owned_cleanup_acknowledged then
        -- No pixel buffers are stored here. Dropping private UObject wrappers lets
        -- native actor/GC ownership retire the clone MIDs without touching the player.
        handle.meshes, handle.lights, handle.private_by_source, handle.last_readback, handle.last_evidence = {}, {}, {}, nil, nil
    end
    handle.cleanup_receipt = receipt
    return receipt
end

local function create_resources(deps, handle)
    no_inventory_doll(deps)
    local existing_actors, existing_targets = existing_addresses(deps, "SceneCapture2D"), existing_addresses(deps, "TextureRenderTarget2D")
    local player, snapshot = snapshot_sources(deps)
    snapshot.eye_bindings = deps.eye_bindings.inspect(player, player.HeadMesh)
    require_condition(snapshot.eye_bindings.identity_key == handle.identity_key, "Current native eye generation differs from requested preview")
    snapshot.appearance_generation = appearance_fingerprint(snapshot.appearance_report, snapshot.eye_bindings, snapshot.head.identity, true)
    snapshot.appearance_pose = appearance_fingerprint(snapshot.appearance_report, snapshot.eye_bindings, snapshot.head.identity, false)
    -- Private eye MIDs start from original assets even if the registry owns live MIDs.
    for _, eye in ipairs(snapshot.eye_bindings.bindings) do
        snapshot.head.material_objects[eye.slot + 1] = eye.original_material
        snapshot.head.materials[eye.slot + 1] = copy(eye.original_identity)
    end
    handle.snapshot = snapshot
    handle.render = static(deps, "/Script/Engine.Default__KismetRenderingLibrary", "/Script/Engine.KismetRenderingLibrary")
    handle.gameplay = static(deps, "/Script/Engine.Default__GameplayStatics", "/Script/Engine.GameplayStatics")
    handle.math_library = static(deps, "/Script/Engine.Default__KismetMathLibrary", "/Script/Engine.KismetMathLibrary")
    handle.geometry = derive_geometry(snapshot, player, handle.math_library)
    local actor_class = static(deps, "/Script/Engine.SceneCapture2D", "/Script/CoreUObject.Class")
    local mesh_classes = { skeletal = "/Script/Engine.SkeletalMeshComponent", static = "/Script/Engine.StaticMeshComponent",
        groom = "/Script/HairStrandsCore.GroomComponent", ["chaos-cloth"] = "/Script/ChaosClothAssetEngine.ChaosClothComponent" }
    local light_class = static(deps, "/Script/Engine.PointLightComponent", "/Script/CoreUObject.Class")
    handle.spawn = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Scale3D = { X = 1, Y = 1, Z = 1 }, Translation = shifted(snapshot.location) }
    handle.actor = handle.gameplay:BeginDeferredActorSpawnFromClass(player:GetWorld(), actor_class, handle.spawn, 1, nil, 0)
    handle.actor_identity = record(handle.actor, "/Script/Engine.SceneCapture2D", "new private capture actor")
    require_condition(not existing_actors[handle.actor_identity.address], "Native factory returned an existing capture actor")
    handle.created = true
    require_condition(handle.actor_identity.address ~= snapshot.player.address and same(handle.actor:GetWorld(), snapshot.world), "Private actor aliases player or world differs")
    handle.capture = handle.actor.CaptureComponent2D
    handle.capture_identity = record(handle.capture, "/Script/Engine.SceneCaptureComponent2D", "new private capture")
    require_condition(same(handle.capture:GetOwner(), handle.actor_identity) and not valid(handle.capture.TextureTarget), "Private capture references an existing target")
    capture_settings(handle.capture)
    handle.actor:SetActorEnableCollision(false)
    handle.finish_attempted = true
    handle.gameplay:FinishSpawningActor(handle.actor, handle.spawn, 0)
    handle.spawn_finished = true
    require_condition(same(handle.actor, handle.actor_identity) and same(handle.actor.CaptureComponent2D, handle.capture_identity)
        and same(handle.capture:GetOwner(), handle.actor_identity) and not valid(handle.capture.TextureTarget), "Private actor changed during construction")
    handle.target = handle.render:CreateRenderTarget2D(player:GetWorld(), 1024, 1024, 2, { R = 0, G = 0, B = 0, A = 0 }, false, false)
    handle.target_identity = record(handle.target, "/Script/Engine.TextureRenderTarget2D", "new private target")
    require_condition(not existing_targets[handle.target_identity.address], "Native target factory returned a preexisting target")
    handle.target_owned = true
    handle.target_outer = record(handle.target:GetOuter(), "/Script/Engine.World", "new private target outer")
    require_condition(equal(handle.target_outer, snapshot.world), "New private target does not belong to its requested world")
    require_condition(handle.target.SizeX == 1024 and handle.target.SizeY == 1024 and handle.target.RenderTargetFormat == 2, "Private target dimensions or format differ")
    handle.display = { requested_gamma = 0, requested_force_linear_gamma = true, configuration_source = "native-factory-defaults",
        gamma_before = observe_scalar(function() return handle.target.TargetGamma end),
        force_linear_before = observe_scalar(function() return handle.target.bForceLinearGamma end) }
    handle.display.gamma_after = observe_scalar(function() return handle.target.TargetGamma end)
    handle.display.force_linear_after = observe_scalar(function() return handle.target.bForceLinearGamma end)
    require_condition(handle.display.gamma_after.ok and handle.display.gamma_after.value == 0
        and handle.display.force_linear_after.ok and flag(handle.display.force_linear_after.value, true),
        "Private target native display defaults differ")
    handle.display.configuration_verified = true
    handle.display.writes_performed = false
    handle.capture.TextureTarget = handle.target
    verify_capture(handle)
    handle.private_by_source = {}
    local ordered_sources = {}
    for _, kind in ipairs({ "skeletal", "static", "chaos-cloth", "groom" }) do
        for _, source in ipairs(snapshot.meshes) do if source.kind == kind then ordered_sources[#ordered_sources + 1] = source end end
    end
    for _, source in ipairs(ordered_sources) do
        verify_sources(deps, snapshot, false)
        local copied = transform(source.transform)
        copied.Translation.Z = copied.Translation.Z + OFFSET_Z
        local mesh_class = static(deps, mesh_classes[source.kind], "/Script/CoreUObject.Class")
        local mesh = handle.actor:AddComponentByClass(mesh_class, true, handle.spawn, true)
        local identity = record(mesh, mesh_classes[source.kind], "private " .. source.field)
        require_condition(identity.address ~= source.identity.address and same(mesh:GetOwner(), handle.actor_identity), "Clone aliases source or lacks private ownership")
        local entry = { object = mesh, identity = identity, source = source }
        handle.meshes[#handle.meshes + 1] = entry
        configure_primitive(mesh, source)
        configure_appearance(mesh, source, handle.private_by_source)
        mesh:K2_SetWorldTransform(copied, false, {}, true)
        handle.actor:FinishAddComponent(mesh, true, handle.spawn)
        mesh:K2_SetWorldTransform(copied, false, {}, true)
        entry.applied_transform = copy(copied)
        handle.private_by_source[source.identity.address] = entry
        if source.field == "HeadMesh" then create_eye_instances(deps, handle, entry) end
        verify_mesh(handle, entry)
        if source.visible then handle.capture:ShowOnlyComponent(mesh) end
    end
    local pivot, forward = shifted(snapshot.pivot), vector(player:GetActorForwardVector())
    for _, sign in ipairs({ -1, 1 }) do
        verify_owned(deps, handle, false)
        local light = handle.actor:AddComponentByClass(light_class, true, handle.spawn, true)
        local identity = record(light, "/Script/Engine.PointLightComponent", "private fill light")
        require_condition(same(light:GetOwner(), handle.actor_identity), "Fill light lacks private ownership")
        handle.lights[#handle.lights + 1] = { object = light, identity = identity, sign = sign }
        local location = { X = pivot.X + forward.X * 100 - forward.Y * sign * 100,
            Y = pivot.Y + forward.Y * 100 + forward.X * sign * 100, Z = pivot.Z + 60 }
        configure_light(light, location)
        handle.actor:FinishAddComponent(light, true, handle.spawn)
        light:K2_SetWorldLocation(location, false, {}, true)
    end
    configure_profile(handle.capture, handle, PROFILE, function() verify_capture(handle) end, handle.actor_identity)
    handle.profile_ready = true
    verify_owned(deps, handle, false)
end

function Renderer.new(deps)
    require_condition(type(deps) == "table" and deps.intent == "eye-private-preview-session", "Explicit persistent private preview intent required")
    require_condition(type(deps.identity) == "table" and deps.identity.build_id == BUILD_ID
        and deps.identity.executable_sha256 == EXECUTABLE_SHA256, "Current-build identity mismatch")
    for _, name in ipairs({ "is_in_game_thread", "monotonic_ms", "get_player", "find_all_of", "static_find_object", "output_exists" }) do
        require_condition(type(deps[name]) == "function", "Missing native preview dependency: " .. name)
    end
    require_condition(type(deps.eye_bindings) == "table" and type(deps.eye_bindings.inspect) == "function"
        and type(deps.eye_bindings.verify) == "function" and type(deps.eye_bindings.validate_settings) == "function", "Native eye registry is required")
    require_condition(type(deps.nonce) == "string" and #deps.nonce == 32 and deps.nonce:match("^%x+$") ~= nil
        and type(deps.boot_id) == "string" and #deps.boot_id <= 64 and deps.boot_id:match("^%d+%-%d+$") ~= nil, "Invalid renderer identity")
    local directory = type(deps.output_directory) == "string" and deps.output_directory:gsub("\\", "/"):gsub("/+$", "") or ""
    require_condition(directory:lower() == (ROOT .. "/" .. deps.boot_id):lower(), "Private preview directory differs from its boot")
    local adapters, handle, attempted, failed_cleanup = {}, nil, false, nil
    local function guard()
        require_condition(deps.is_in_game_thread() == true, "Private native preview requires the game thread")
    end
    local function owned(candidate)
        guard()
        require_condition(candidate ~= nil and candidate == handle and not candidate.closed, "Unknown or closed private preview handle")
    end
    local function current_binding()
        guard()
        local player = deps.get_player()
        return deps.eye_bindings.inspect(player, player.HeadMesh)
    end
    adapters.is_game_thread, adapters.monotonic_ms = deps.is_in_game_thread, deps.monotonic_ms
    function adapters.inspect_identity() return current_binding().identity_key end
    function adapters.validate_settings(settings)
        return type(deps.eye_bindings.validate_settings(settings, current_binding())) == "table"
    end
    function adapters.validate_view(view)
        guard()
        local player = deps.get_player()
        local geometry
        if handle and not handle.closed then geometry = handle.geometry
        else
            local snapshot
            player, snapshot = snapshot_sources(deps)
            geometry = derive_geometry(snapshot, player, static(deps, "/Script/Engine.Default__KismetMathLibrary", "/Script/Engine.KismetMathLibrary"))
        end
        return view_geometry(geometry, view, player) ~= nil
    end
    function adapters.create_preview(identity_key)
        guard()
        require_condition(not attempted, "This native renderer nonce already attempted creation")
        attempted = true
        local candidate = { identity_key = identity_key, nonce = deps.nonce:lower(), boot_id = deps.boot_id,
            meshes = {}, lights = {}, pending = {}, sequence = 0 }
        local ok, failure = pcall(create_resources, deps, candidate)
        if not ok then
            failed_cleanup = cleanup(candidate, deps)
            error("Private construction failed: " .. tostring(failure):sub(1, 512)
                .. "; cleanup acknowledged=" .. tostring(failed_cleanup.owned_cleanup_acknowledged), 0)
        end
        handle = candidate
        return candidate
    end
    function adapters.verify_private_preview(candidate, identity_key)
        owned(candidate)
        require_condition(identity_key == candidate.identity_key, "Private preview generation differs")
        verify_owned(deps, candidate, true)
        return true
    end
    function adapters.can_capture(candidate)
        owned(candidate)
        local count = 0
        for _ in pairs(candidate.pending) do count = count + 1 end
        return count < 2
    end
    function adapters.update_preview(candidate, desired)
        owned(candidate)
        local close_stage = enter_stage(candidate, deps, "update_preview")
        verify_owned(deps, candidate, true)
        local player = deps.get_player()
        refresh_pose(deps, candidate.snapshot, player)
        candidate.geometry = derive_geometry(candidate.snapshot, player, candidate.math_library)
        local view = view_geometry(candidate.geometry, desired.view, player)
        for _, entry in ipairs(candidate.meshes) do
            verify_receiver(deps, candidate, entry, nil, true)
            local copied = transform(entry.source.transform)
            copied.Translation.Z = copied.Translation.Z + OFFSET_Z
            entry.object:K2_SetWorldTransform(copied, false, {}, true)
            entry.applied_transform = copy(copied)
        end
        verify_private_cohort(deps, candidate, false)
        local pivot, forward = shifted(candidate.snapshot.pivot), vector(player:GetActorForwardVector())
        for _, entry in ipairs(candidate.lights) do
            verify_receiver(deps, candidate, entry)
            entry.object:K2_SetWorldLocation({ X = pivot.X + forward.X * 100 - forward.Y * entry.sign * 100,
                Y = pivot.Y + forward.Y * 100 + forward.X * entry.sign * 100, Z = pivot.Z + 60 }, false, {}, true)
        end
        -- No mid-step full verification: the entry sweep established the pins and every write
        -- since then was preceded by a cohort guard that re-checks all owned receivers, so a
        -- corrupted clone still stops the batch before the next native write. eye_settings may
        -- therefore skip its own sweep via already_verified; any drift is still caught by
        -- capture_preview's before-export full sweep before evidence is exported.
        verify_private_cohort(deps, candidate, false)
        local settings = eye_settings(deps, candidate, desired.settings, true, true)
        verify_private_cohort(deps, candidate, false)
        local location, look_at = apply_view(candidate.capture, view, candidate.math_library)
        verify_private_cohort(deps, candidate, false)
        local readback = { identity_key = candidate.identity_key, baseline_id = candidate.snapshot.eye_bindings.baseline_id,
            view_revision = desired.view_revision, eye_revision = desired.eye_revision, view = copy(desired.view), settings = settings,
            camera_location = location, camera_rotation = look_at, field_of_view = view.field_of_view, near_clip = view.near_clip }
        candidate.last_readback = readback
        close_stage()
        return readback
    end
    function adapters.validate_readback(readback, desired, candidate)
        owned(candidate)
        local close_stage = enter_stage(candidate, deps, "validate_readback")
        -- No native write happens between update_preview's final sweep and this pure read, so a
        -- pinned cohort guard plus a read-only scalar pass replaces the V10 full sweep here. Any
        -- drift is still caught by capture_preview's before-export full sweep before evidence.
        verify_private_cohort(deps, candidate, false)
        local matches = readback == candidate.last_readback and readback.identity_key == candidate.identity_key
            and readback.view_revision == desired.view_revision and readback.eye_revision == desired.eye_revision
            and equal(readback.view, desired.view) and equal(readback.settings, eye_settings(deps, candidate, desired.settings, false, true))
        close_stage()
        return matches
    end
    local function verify_camera(candidate, readback)
        local capture = candidate.capture
        require_condition(equal_fields(vector(capture:K2_GetComponentLocation()), readback.camera_location)
            and equal_fields(rotation(capture:K2_GetComponentRotation()), readback.camera_rotation)
            and capture.ProjectionType == 0 and math.abs(capture.FOVAngle - readback.field_of_view) < 0.00001
            and flag(capture.bOverride_CustomNearClippingPlane, true) and capture.CustomNearClippingPlane == readback.near_clip,
            "Private camera changed during frame export")
    end
    function adapters.capture_preview(candidate, readback, sequence)
        owned(candidate)
        local close_stage = enter_stage(candidate, deps, "capture_preview")
        require_condition(readback == candidate.last_readback and sequence == candidate.sequence + 1
            and sequence >= 1 and sequence <= 1200 and sequence % 1 == 0 and adapters.can_capture(candidate), "Capture sequence or backlog limit rejected")
        verify_owned(deps, candidate, false)
        verify_camera(candidate, readback)
        local filename = "eye-live-" .. candidate.nonce .. "-" .. string.format("%04d", sequence) .. ".png"
        require_condition(deps.output_exists(directory .. "/" .. filename) == false, "Private frame path already exists or cannot be checked")
        -- A failed export may have left a partial file. Consume the sequence before
        -- invoking native IO, retain its receipt, and never overwrite that path.
        candidate.sequence = sequence
        candidate.pending[sequence] = filename
        -- This is the observed native game-world clock around the call interval,
        -- not the lease clock or a GPU completion timestamp. It can be equal
        -- before/after a synchronous operation inside one engine tick.
        local started = number(candidate.gameplay:GetRealTimeSeconds(deps.get_player():GetWorld()), "native export call start") * 1000
        require_condition(started >= 0 and started <= 9007199254740991, "Native export clock is outside its representable range")
        candidate.capture:CaptureScene()
        candidate.render:ExportRenderTarget(deps.get_player():GetWorld(), candidate.target, directory, filename)
        local completed = number(candidate.gameplay:GetRealTimeSeconds(deps.get_player():GetWorld()), "native export call completion") * 1000
        require_condition(completed >= started and completed <= 9007199254740991
            and deps.output_exists(directory .. "/" .. filename) == true, "Native export clock or bounded frame file could not be verified")
        verify_owned(deps, candidate, false)
        verify_camera(candidate, readback)
        -- The after-export full sweep just completed, so this read-only scalar pass repeats no
        -- appearance inspection; the export-boundary sweeps are the real export contract.
        local settings = eye_settings(deps, candidate, readback.settings, false, true)
        local evidence = { kind = "native-private-eye-session-evidence", nonce = candidate.nonce, boot_id = deps.boot_id,
            identity_key = candidate.identity_key, baseline_id = readback.baseline_id, sequence = sequence, file_name = filename,
            actor = copy(candidate.actor_identity), capture = copy(candidate.capture_identity), target = copy(candidate.target_identity),
            target_outer = copy(candidate.target_outer), width = 1024, height = 1024, render_target_format = 2, capture_source = 9,
            target_gamma = candidate.target.TargetGamma, force_linear_gamma = flag(candidate.target.bForceLinearGamma, true),
            rendering_profile = read_profile(candidate.capture, candidate, PROFILE, candidate.actor_identity), view_revision = readback.view_revision, eye_revision = readback.eye_revision,
            view = copy(readback.view), settings = settings, camera_location = copy(readback.camera_location), camera_rotation = copy(readback.camera_rotation),
            field_of_view = readback.field_of_view, near_clip = readback.near_clip,
            native_clock_id = "ue-gameplay-real-time-seconds:" .. deps.boot_id .. ":" .. candidate.snapshot.world.address,
            export_call_started_monotonic_ms = started, export_call_completed_monotonic_ms = completed,
            capture_timestamp_known = false, frame_verified = false, preview_verified = false, gameplay_verified = false }
        candidate.last_evidence = evidence
        close_stage()
        return evidence
    end
    function adapters.validate_capture_evidence(evidence, readback, sequence, candidate)
        owned(candidate)
        return evidence == candidate.last_evidence and evidence.sequence == sequence and sequence == candidate.sequence
            and evidence.identity_key == candidate.identity_key and evidence.file_name == candidate.pending[sequence]
            and evidence.view_revision == readback.view_revision and evidence.eye_revision == readback.eye_revision
            and equal(evidence.settings, readback.settings) and equal(evidence.view, readback.view)
    end
    function adapters.release_preview(candidate)
        guard()
        require_condition(candidate ~= nil and candidate == handle, "Unknown private preview cleanup handle")
        return cleanup(candidate, deps)
    end
    local api = { adapters = adapters }
    function api.describe()
        owned(handle)
        verify_owned(deps, handle, true)
        local zoom_bounds, sources = {}, {}
        for framing, profile in pairs(handle.geometry.profiles) do
            zoom_bounds[framing] = { min = profile.default_distance / profile.maximum_distance,
                max = profile.default_distance / profile.minimum_distance, initial = 1 }
        end
        for _, entry in ipairs(handle.snapshot.meshes) do
            sources[#sources + 1] = { field = entry.field, kind = entry.kind, visible = entry.visible, mesh = copy(entry.identity), asset = copy(entry.asset_identity) }
        end
        return { kind = "native-private-eye-preview-descriptor", nonce = handle.nonce, boot_id = deps.boot_id,
            identity_key = handle.identity_key, baseline_id = handle.snapshot.eye_bindings.baseline_id,
            schema_id = handle.snapshot.eye_bindings.schema_id, actor = copy(handle.actor_identity),
            capture = copy(handle.capture_identity), target = copy(handle.target_identity), target_outer = copy(handle.target_outer),
            player = copy(handle.snapshot.player), world = copy(handle.snapshot.world), form = handle.snapshot.form,
            is_wolf_form = handle.snapshot.wolf, source_meshes = sources, width = 1024, height = 1024,
            render_target_format = 2, capture_source = 9, target_gamma = handle.target.TargetGamma,
            force_linear_gamma = flag(handle.target.bForceLinearGamma, true), display_configuration = copy(handle.display),
            rendering_profile = read_profile(handle.capture, handle, PROFILE, handle.actor_identity),
            yaw_min = -69, yaw_max = 69, zoom_bounds = zoom_bounds,
            production_ready = false, preview_verified = false, gameplay_verified = false }
    end
    function api.acknowledge(sequence, filename)
        guard()
        require_condition(handle ~= nil and handle.pending[sequence] == filename, "Unknown native frame acknowledgement")
        require_condition(deps.output_exists(directory .. "/" .. filename) == false, "Host must consume and remove the exact frame before acknowledgement")
        handle.pending[sequence] = nil
        if handle.last_evidence and handle.last_evidence.sequence == sequence then handle.last_evidence = nil end
        return true
    end
    function api.stage_diagnostics()
        guard()
        require_condition(handle ~= nil, "No native renderer stage diagnostics are available")
        -- Bounded call and native-call-interval accounting per public stage. The intervals come
        -- from the engine's tick-cached game clock, so they bound the native call and are never
        -- GPU completion times or measured capture latency.
        return copy(diagnostics(handle))
    end
    function api.inspect_cleanup() return failed_cleanup or (handle and handle.cleanup_receipt) end
    function api.observe_cleanup()
        guard()
        require_condition(handle ~= nil and handle.closed and handle.cleanup_receipt ~= nil, "No closed native renderer to observe")
        -- A later host-owned engine-frame callback may inspect this evidence.
        -- It does not retroactively turn an unconfirmed release into success.
        return { nonce = handle.nonce, boot_id = deps.boot_id, actor = copy(handle.actor_identity),
            actor_state = observe_actor(handle, deps), production_ready = false }
    end
    return api
end

return Renderer
