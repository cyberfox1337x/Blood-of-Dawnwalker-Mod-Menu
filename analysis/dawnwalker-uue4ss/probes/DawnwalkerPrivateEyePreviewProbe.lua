local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_private_eye_preview_probe")

-- Uninstalled lifecycle prototype. Uses only native classes and already loaded player assets.
local Probe = {}
local Geometry = require("DawnwalkerEyePreviewGeometry")
local BUILD_ID = "25129649"
local EXECUTABLE_SHA256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
local ROOT = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-frames"
local SOURCE_FIELDS = { "HeadMesh", "HairMesh", "EyebrowMeshComponent", "BeardMeshComponent", "TorsoMesh" }
local OFFSET_Z = 100000
local consumed = {}
local operation_count = 0

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

local function snapshot_sources(deps)
    local player = deps.get_player()
    local snapshot = { player = record(player, "/Script/Dawnwalker.DawnwalkerPlayerCharacter", "player"), meshes = {} }
    snapshot.world = record(player:GetWorld(), "/Script/Engine.World", "world")
    snapshot.form, snapshot.wolf = player.Form, player:IsInWolfForm()
    require_condition((snapshot.form == 0 or snapshot.form == 1) and snapshot.wolf == false, "Unsupported player form")
    snapshot.location, snapshot.rotation = vector(player:K2_GetActorLocation()), rotation(player:K2_GetActorRotation())
    local fields = {}
    for _, field in ipairs(SOURCE_FIELDS) do
        local source = player[field]
        if valid(source) then
            local identity = record(source, "/Script/Engine.SkeletalMeshComponent", field)
            require_condition(same(source:GetOwner(), snapshot.player), field .. " is not owned by the current player")
            local asset = source:GetSkeletalMeshAsset()
            if valid(asset) then
                local entry = { source = source, identity = identity, field = field, asset = asset,
                    asset_identity = record(asset, "/Script/Engine.SkeletalMesh", field .. " asset"),
                    transform = transform(source:K2_GetComponentToWorld()), materials = {}, material_objects = {} }
                local count = source:GetNumMaterials()
                require_condition(type(count) == "number" and count % 1 == 0 and count >= 1 and count <= 16, field .. " material count is outside bounds")
                for slot = 0, count - 1 do
                    local material = source:GetMaterial(slot)
                    entry.materials[#entry.materials + 1] = record(material, "/Script/Engine.MaterialInterface", field .. " material")
                    entry.material_objects[#entry.material_objects + 1] = material
                end
                snapshot.meshes[#snapshot.meshes + 1] = entry
                fields[field] = entry
            end
        end
    end
    require_condition(fields.HeadMesh ~= nil and fields.TorsoMesh ~= nil, "Actual loaded head and torso assets are required")
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
    for _, entry in ipairs(snapshot.meshes) do
        require_condition(same(player[entry.field], entry.identity) and same(entry.source:GetOwner(), snapshot.player)
            and same(entry.source:GetSkeletalMeshAsset(), entry.asset_identity), "Source mesh changed during private preview")
        require_condition(entry.source:GetNumMaterials() == #entry.materials, "Source material count changed during private preview")
        for index, binding in ipairs(entry.materials) do
            require_condition(same(entry.source:GetMaterial(index - 1), binding), "Source material changed during private preview")
        end
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
    capture.bSuppressWorldPostProcessing, capture.PrimitiveRenderMode, capture.CaptureSource = true, 2, 2
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

local function configure_mesh(mesh, source, target_transform)
    mesh:SetCollisionEnabled(0)
    mesh:SetGenerateOverlapEvents(false)
    mesh:SetVisibleInSceneCaptureOnly(true)
    mesh:SetHiddenInSceneCapture(false)
    mesh:SetCastShadow(false)
    mesh:SetAffectDynamicIndirectLighting(false)
    mesh:SetAffectDistanceFieldLighting(false)
    mesh:SetVisibleInRayTracing(false)
    mesh:SetLightingChannels(false, false, true)
    mesh:SetSkeletalMeshAsset(source.asset)
    for index, material in ipairs(source.material_objects) do mesh:SetMaterial(index - 1, material) end
    mesh:SetLeaderPoseComponent(source.source, true, false)
    mesh:K2_SetWorldTransform(target_transform, false, {}, true)
end

local function configure_light(light, location)
    light:SetLightingChannels(false, false, true)
    light:SetCastShadows(false)
    light:SetLightColor({ R = 1, G = 1, B = 1, A = 1 }, false)
    light:SetIntensityUnits(1)
    light:SetIntensity(2000)
    light:SetAttenuationRadius(800)
    light:K2_SetWorldLocation(location, false, {}, true)
end

function Probe.run(deps)
    local actor, actor_identity, capture, capture_identity, target, target_identity, render_library, world_identity
    local resources = { meshes = {}, lights = {} }
    local created, destroyed, released, captures, exported = false, false, false, 0, false
    local target_owned = false
    local source_snapshot, geometry, math_library
    local frames, view_applied, front_restored = {}, false, false
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
        local player, snapshot = snapshot_sources(deps)
        source_snapshot = snapshot
        world_identity = snapshot.world
        render_library = static(deps, "/Script/Engine.Default__KismetRenderingLibrary", "/Script/Engine.KismetRenderingLibrary")
        local gameplay = static(deps, "/Script/Engine.Default__GameplayStatics", "/Script/Engine.GameplayStatics")
        math_library = static(deps, "/Script/Engine.Default__KismetMathLibrary", "/Script/Engine.KismetMathLibrary")
        geometry = derive_geometry(snapshot, player, math_library)
        local actor_class = static(deps, "/Script/Engine.SceneCapture2D", "/Script/CoreUObject.Class")
        local mesh_class = static(deps, "/Script/Engine.SkeletalMeshComponent", "/Script/CoreUObject.Class")
        local light_class = static(deps, "/Script/Engine.PointLightComponent", "/Script/CoreUObject.Class")
        local spawn = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Scale3D = { X = 1, Y = 1, Z = 1 },
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
        target = render_library:CreateRenderTarget2D(player:GetWorld(), 1024, 1024, 3, { R = 0.018, G = 0.018, B = 0.018, A = 1 }, false, false)
        target_identity = record(target, "/Script/Engine.TextureRenderTarget2D", "new private render target")
        require_condition(not existing_targets[target_identity.address] and not target_identity.name:find("/Game/", 1, true),
            "Private renderer did not receive a new transient target")
        target_owned = true
        require_condition(target.SizeX == 1024 and target.SizeY == 1024 and target.RenderTargetFormat == 3,
            "Private target dimensions or format differ from the request")
        target.TargetGamma = 2.2
        require_condition(math.abs(target.TargetGamma - 2.2) < 0.00001 and flag(target.bForceLinearGamma, false),
            "Private display target gamma did not read back")
        capture.TextureTarget = target
        gameplay:FinishSpawningActor(actor, spawn, 0)
        require_condition(same(actor, actor_identity) and same(capture:GetOwner(), actor_identity) and same(capture.TextureTarget, target_identity),
            "Private native actor changed during construction")
        for _, source in ipairs(snapshot.meshes) do
            local copied = transform(source.transform)
            copied.Translation.Z = copied.Translation.Z + OFFSET_Z
            local mesh = actor:AddComponentByClass(mesh_class, true, spawn, true)
            local mesh_identity = record(mesh, "/Script/Engine.SkeletalMeshComponent", "private " .. source.field)
            require_condition(mesh_identity.address ~= source.identity.address and same(mesh:GetOwner(), actor_identity), "Cloned mesh aliases or is not privately owned")
            resources.meshes[#resources.meshes + 1] = { object = mesh, identity = mesh_identity, source = source }
            configure_mesh(mesh, source, copied)
            actor:FinishAddComponent(mesh, true, spawn)
            mesh:K2_SetWorldTransform(copied, false, {}, true)
            require_condition(same(mesh:GetSkeletalMeshAsset(), source.asset_identity) and mesh:GetCollisionEnabled() == 0,
                "Private clone asset or non-collision state did not read back")
            require_condition(flag(mesh.bVisibleInSceneCaptureOnly, true) and flag(mesh.bHiddenInSceneCapture, false)
                and private_lighting(mesh), "Private clone visibility or lighting channel did not read back")
            capture:ShowOnlyComponent(mesh)
        end
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
        for _, view in ipairs(geometry.views) do
            verify_sources(deps, snapshot)
            no_inventory_doll(deps)
            require_condition(same(actor, actor_identity) and same(capture, capture_identity) and same(capture:GetOwner(), actor_identity)
                and same(capture.TextureTarget, target_identity), "Private capture ownership or target changed before rendering")
            require_condition(capture.bCaptureEveryFrame == false and capture.bCaptureOnMovement == false
                and capture.bMainViewCamera == false and capture.bMainViewFamily == false and capture.bMainViewResolution == false
                and capture.bRenderInMainRenderer == false and capture.bSuppressWorldPostProcessing == true
                and capture.PrimitiveRenderMode == 2 and capture.CaptureSource == 2, "Private capture isolation settings did not read back")
            local filename = filenames[view.phase]
            require_condition(deps.output_exists(directory .. "/" .. filename) == false, "Private phase output already exists or cannot be checked")
            view_applied = true
            local camera_location, camera_rotation = apply_view(capture, view, math_library)
            local frame = { phase = view.phase, file_name = filename, framing = view.framing, yaw_degrees = view.yaw_degrees,
                zoom = view.zoom, camera_distance = view.distance, field_of_view = view.field_of_view, near_clip = view.near_clip,
                pivot = view.pivot, camera_location = camera_location, camera_rotation = camera_rotation,
                export_started_at_epoch_ms = number(deps.now(), "export start time") * 1000 }
            capture:CaptureScene()
            captures = captures + 1
            exported = true
            render_library:ExportRenderTarget(player:GetWorld(), target, directory, filename)
            frame.export_completed_at_epoch_ms = number(deps.now(), "export completion time") * 1000
            frames[#frames + 1] = frame
            require_condition(equal_fields(vector(capture:K2_GetComponentLocation()), camera_location)
                and equal_fields(rotation(capture:K2_GetComponentRotation()), camera_rotation), "Private camera changed during export")
            verify_sources(deps, snapshot)
        end
        local sources = {}
        for _, source in ipairs(snapshot.meshes) do sources[#sources + 1] = { field = source.field, mesh = source.identity, asset = source.asset_identity, materials = source.materials } end
        return { ok = true, schema = 2, kind = "native-private-eye-preview-evidence", boot_id = deps.boot_id, nonce = deps.nonce:lower(),
            frames = frames, width = 1024, height = 1024, render_target_format = 3, capture_source = 2, target_gamma = target.TargetGamma,
            player = snapshot.player, world = snapshot.world, form = snapshot.form, is_wolf_form = snapshot.wolf,
            actor = actor_identity, capture = capture_identity, target = target_identity, source_meshes = sources, pivot_bone_name = snapshot.pivot_bone_name,
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
            actor:K2_DestroyActor()
            destroyed = not valid(actor) or actor:IsActorBeingDestroyed() == true
            require_condition(destroyed, "Private actor destruction did not complete")
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
    local actor_invalidated = created and not valid(actor)
    local destruction_pending = created and valid(actor) and destroyed
    if ok and restore_ok and cleanup_ok and release_ok and source_ok then
        result.created, result.destruction_acknowledged, result.target_released, result.capture_requests, result.export_invoked = created, destroyed, released, captures, exported
        result.actor_invalidated, result.destruction_pending = actor_invalidated, destruction_pending
        result.front_restored = front_restored
        return result
    end
    return { ok = false, created = created, destruction_acknowledged = destroyed, actor_invalidated = actor_invalidated,
        destruction_pending = destruction_pending, target_released = released, capture_requests = captures, export_invoked = exported,
        frames = frames, front_restored = front_restored, frame_verified = false, preview_verified = false, gameplay_verified = false,
        reason = tostring(not ok and result or "Private renderer cleanup failed"):sub(1, 1024),
        cleanup_error = cleanup_ok and nil or tostring(cleanup_error):sub(1, 1024),
        restore_error = restore_ok and nil or tostring(restore_error):sub(1, 1024),
        release_error = release_ok and nil or tostring(release_error):sub(1, 1024),
        source_error = source_ok and nil or tostring(source_error):sub(1, 1024) }
end

return Probe
