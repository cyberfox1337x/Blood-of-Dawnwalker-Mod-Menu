local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_inventory_eye_capture_probe")

local Geometry = require("DawnwalkerEyePreviewGeometry")
local Probe = {}
local ROOT = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-frames"
local TARGET = "TextureRenderTarget2D /Game/_Dawnwalker/UI/_Unified/GameHub/Inventory/Doll/RT_RenderDoll.RT_RenderDoll"
local requests, request_count = {}, 0
local function check(condition, message) if condition ~= true then error(message, 0) end end
local function finite(value) check(type(value) == "number" and value == value and math.abs(value) < math.huge, "Nonfinite native coordinate"); return value end
local function vector(value) return { X = finite(value.X), Y = finite(value.Y), Z = finite(value.Z) } end
local function rotation(value) return { pitch = finite(value.pitch), Yaw = finite(value.Yaw), Roll = finite(value.Roll) } end
local function transform(value)
    return { Translation = vector(value.Translation), Scale3D = vector(value.Scale3D), Rotation = {
        X = finite(value.Rotation.X), Y = finite(value.Rotation.Y), Z = finite(value.Rotation.Z), W = finite(value.Rotation.W) } }
end
local function valid(object) return object ~= nil and object:IsValid() == true end
local function identity(value) return { address = value.address, name = value.name } end
local function flag(value)
    check(type(value) == "boolean" or value == 0 or value == 1, "Unknown native capture flag")
    return value == true or value == 1
end
local function record(object, class)
    check(valid(object) and object:IsA(class) == true, "Native capture object class is unavailable")
    local address, name = object:GetAddress(), object:GetFullName()
    check(finite(address) > 0 and type(name) == "string" and #name <= 1024 and not name:find("Default__", 1, true), "Invalid native capture instance")
    return { address = tostring(address), name = name }
end
local function same(object, expected)
    return type(expected) == "table" and valid(object) and tostring(object:GetAddress()) == expected.address and object:GetFullName() == expected.name
end
local function equal(left, right)
    for key, expected in pairs(right) do
        if type(expected) == "table" then if not equal(left[key], expected) then return false end
        elseif type(expected) == "number" then if math.abs(finite(left[key]) - expected) > 0.00001 then return false end
        elseif left[key] ~= expected then return false end
    end
    return true
end
local function entries(array, maximum)
    local ok, count = pcall(function() return array:GetArrayNum() end)
    if not ok then count = #array end
    check(type(count) == "number" and count % 1 == 0 and count >= 0 and count <= maximum, "Native capture array exceeds its bound")
    local result = {}
    for index = 1, count do
        local value = array[index]
        local wrapped, raw = pcall(function() return value:get() end)
        result[index] = wrapped and raw or value
    end
    return result
end

local function authorize(deps, phase, sample)
    check(type(deps) == "table" and deps.game_thread == true and deps.intent == "human-iris-pair-roundtrip", "Explicit human iris capture intent required")
    check(deps.identity.build_id == "25129649" and deps.identity.executable_sha256 == "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853", "Native iris capture build mismatch")
    check(type(deps.nonce) == "string" and #deps.nonce == 32 and deps.nonce:match("^%x+$") ~= nil
        and type(deps.boot_id) == "string" and #deps.boot_id <= 64 and deps.boot_id:match("^%d+%-%d+$") ~= nil, "Invalid iris capture nonce or boot")
    check(phase == "baseline" or phase == "changed" or phase == "restored", "Unsupported iris capture phase")
    check(type(sample) == "table" and sample.phase == phase and sample.nonce == deps.nonce and sample.boot_id == deps.boot_id
        and sample.baseline_id == deps.boot_id .. ":" .. deps.nonce and sample.form == 0 and sample.is_wolf_form == false,
        "Iris capture sample does not match the native transaction")
    for _, name in ipairs({ "preview_probe", "get_player", "find_all_of", "static_find_object", "now", "output_exists" }) do
        check(type(deps[name]) == "function", "Missing iris capture dependency: " .. name)
    end
    local key = deps.boot_id .. ":" .. deps.nonce:lower()
    local state = requests[key]
    if not state then
        check(phase == "baseline" and request_count < 2, "Iris capture requires a fresh baseline within its two-request budget")
        state = { phases = {}, player = identity(sample.player), world = identity(sample.world), head = identity(sample.head) }
        requests[key], request_count = state, request_count + 1
    end
    check(not state.phases[phase] and not state.phases.restored, "Iris capture phase was already attempted or transaction ended")
    check(phase ~= "changed" or state.baseline_success == true, "Changed iris capture requires the successful baseline frame")
    check(equal(sample.player, state.player) and equal(sample.world, state.world) and equal(sample.head, state.head), "Iris capture source generation changed")
    state.phases[phase] = true
    return state
end

local function inspect(deps, sample)
    local observation = deps.preview_probe(deps)
    check(observation.ok == true and observation.observed_doll_count == 1 and observation.form == 0
        and observation.is_wolf_form == false, "Exactly one owned human inventory preview is required")
    local doll_record
    for _, entry in ipairs(observation.dolls) do if entry.ok then check(doll_record == nil, "Multiple native dolls"); doll_record = entry.value end end
    check(doll_record ~= nil, "Native inventory doll observation is unavailable")
    local player = deps.get_player()
    check(same(player, sample.player) and same(player, observation.player) and same(player:GetWorld(), sample.world)
        and same(player:GetWorld(), observation.world) and player.Form == 0 and player:IsInWolfForm() == false, "Actual iris sample source is no longer current")
    local player_head = player.HeadMesh
    check(same(player_head, sample.head) and same(player_head:GetOwner(), sample.player)
        and same(player_head:GetSkeletalMeshAsset(), sample.asset), "Actual iris sample head changed")
    local doll
    for _, candidate in ipairs(entries(deps.find_all_of("InventoryRenderDoll") or {}, 8)) do
        if same(candidate, doll_record) then check(doll == nil, "Duplicate native doll reference"); doll = candidate end
    end
    check(doll ~= nil and doll:IsA("/Script/DogwoodInventory.InventoryRenderDoll") == true, "Native inventory doll disappeared")
    local head, capture = doll.HeadMeshComponent, doll.SceneCapture
    local current = { player = player, player_head = player_head, doll = doll, head = head, capture = capture,
        target = capture.TextureTarget, observation = observation, record = doll_record, sample = sample, eyes = {} }
    check(same(head, doll_record.meshes.HeadMeshComponent) and same(head:GetOwner(), doll_record)
        and same(head:GetSkeletalMeshAsset(), sample.asset) and same(capture, doll_record.capture)
        and same(capture:GetOwner(), doll_record), "Inventory capture/head ownership or actual model changed")
    check(same(current.target, doll_record.capture.target) and current.target:GetFullName() == TARGET
        and current.target.SizeX == 2048 and current.target.SizeY == 2048 and current.target.RenderTargetFormat == 2
        and current.target.OverrideFormat == 0 and capture.CaptureSource == 9 and capture.PrimitiveRenderMode == 2,
        "Native inventory target format or capture mode changed")
    for _, field in ipairs({ "bMainViewCamera", "bMainViewFamily", "bMainViewResolution", "bRenderInMainRenderer" }) do
        check(capture[field] == false, "Inventory capture is connected to a gameplay view")
    end
    local head_shown = false
    local shown = doll_record.capture.lists.ShowOnlyComponents
    check(shown.ok == true, "Native inventory capture inclusion list is unavailable")
    for _, entry in ipairs(shown.value) do
        if entry.ok and entry.value.address == doll_record.meshes.HeadMeshComponent.address then head_shown = true end
    end
    check(head_shown, "Native inventory head is absent from its capture inclusion list")
    check(type(sample.eyes) == "table" and #sample.eyes == 2, "Exactly two sampled eyes are required")
    local player_slots, doll_slots = entries(player_head:GetMaterialSlotNames(), 16), entries(head:GetMaterialSlotNames(), 16)
    for index, expected_name in ipairs({ "shader_eyeLeft_shader", "shader_eyeRight_shader" }) do
        local slot, eye = index + 2, sample.eyes[index]
        check(eye.slot == slot and eye.slot_name == expected_name and player_slots[slot + 1]:ToString() == expected_name
            and doll_slots[slot + 1]:ToString() == expected_name, "Native iris slot topology changed")
        local source, original = player_head:GetMaterial(slot), head:GetMaterial(slot)
        check(same(source, eye.material), "Sampled current player eye material changed")
        current.eyes[index] = { slot = slot, source = source, source_identity = record(source, "/Script/Engine.MaterialInterface"),
            original = original, original_identity = record(original, "/Script/Engine.MaterialInterface"), attempted = false }
    end
    current.player_location, current.player_rotation = vector(player:K2_GetActorLocation()), rotation(player:K2_GetActorRotation())
    current.relative = transform(capture:GetRelativeTransform())
    current.camera_before = { location = vector(capture:K2_GetComponentLocation()), rotation = rotation(capture:K2_GetComponentRotation()),
        fov = finite(capture.FOVAngle), projection = finite(capture.ProjectionType), near_clip = finite(capture.CustomNearClippingPlane),
        override_near = flag(capture.bOverride_CustomNearClippingPlane), every_frame = flag(capture.bCaptureEveryFrame), on_movement = flag(capture.bCaptureOnMovement),
        capture_source = capture.CaptureSource, primitive_render_mode = capture.PrimitiveRenderMode }
    return current
end

local function verify_doll(current)
    local record, sample = current.record, current.sample
    check(same(current.doll, record) and same(current.doll:GetWorld(), sample.world)
        and same(current.doll.TargetInventory, record.inventory) and same(current.doll.TargetInventory:GetOwner(), sample.player), "Inventory owner changed")
end

local function verify_head(current)
    verify_doll(current)
    local record, sample = current.record, current.sample
    check(same(current.doll.HeadMeshComponent, record.meshes.HeadMeshComponent) and same(current.head:GetOwner(), record)
        and same(current.head:GetSkeletalMeshAsset(), sample.asset), "Inventory head receiver changed")
end

local function verify_capture(current)
    verify_doll(current)
    local record = current.record
    check(same(current.doll.SceneCapture, record.capture) and same(current.capture:GetOwner(), record)
        and same(current.capture.TextureTarget, record.capture.target) and same(current.capture:GetAttachParent(), record.root)
        and same(current.doll.RootComponent, record.root), "Inventory capture receiver changed")
    check(current.target.SizeX == 2048 and current.target.SizeY == 2048 and current.target.RenderTargetFormat == 2
        and current.target.OverrideFormat == 0 and current.capture.CaptureSource == 9 and current.capture.PrimitiveRenderMode == 2,
        "Inventory target format or capture source changed")
    for _, field in ipairs({ "bMainViewCamera", "bMainViewFamily", "bMainViewResolution", "bRenderInMainRenderer" }) do
        check(current.capture[field] == false, "Inventory capture connected to gameplay during operation")
    end
end

local function verify_receivers(current)
    verify_head(current)
    verify_capture(current)
end

local function verify_player(deps, current)
    local player, sample = deps.get_player(), current.sample
    check(same(player, sample.player) and same(player:GetWorld(), sample.world) and player.Form == 0 and player:IsInWolfForm() == false
        and same(player.HeadMesh, sample.head) and same(player.HeadMesh:GetSkeletalMeshAsset(), sample.asset), "Player changed during iris capture")
    check(equal(vector(player:K2_GetActorLocation()), current.player_location) and equal(rotation(player:K2_GetActorRotation()), current.player_rotation),
        "Player transform changed during iris capture")
    for _, eye in ipairs(current.eyes) do check(same(player.HeadMesh:GetMaterial(eye.slot), eye.source_identity), "Live eye binding changed during iris capture") end
end

local function closeup(current, math_library)
    local landmarks = Geometry.observe_landmarks(current.head)
    check(landmarks.eye_pair_count == 1 and landmarks.eye_pair ~= nil, "Native doll has no unambiguous actual eye pair")
    local head_pivot
    for _, entry in ipairs(landmarks.matches) do if entry.name == "Head" then head_pivot = entry.location end end
    check(head_pivot ~= nil, "Observed native Head pivot is unavailable")
    local bounds = current.head:GetSkeletalMeshAsset():GetBounds()
    local world_transform = transform(current.head:K2_GetComponentToWorld())
    local scale = world_transform.Scale3D
    check(scale.X > 0 and scale.Y > 0 and scale.Z > 0 and math.max(scale.X, scale.Y, scale.Z) <= 10, "Unsupported native preview scale")
    local geometry = Geometry.build_views({ head_center = vector(math_library:TransformLocation(world_transform, vector(bounds.Origin))),
        head_pivot = head_pivot, eye_left = landmarks.eye_pair.left.location, eye_right = landmarks.eye_pair.right.location,
        head_radius = finite(bounds.SphereRadius) * math.max(scale.X, scale.Y, scale.Z), forward = vector(current.doll:GetActorForwardVector()) })
    return geometry.views[4], geometry, landmarks.eye_pair
end

function Probe.run(deps, phase, sample)
    local current, view, geometry, pair, state, camera_after
    local camera_attempted, export_invoked, refresh_requested = false, false, false
    local ok, result = pcall(function()
        state = authorize(deps, phase, sample)
        local directory = type(deps.output_directory) == "string" and deps.output_directory:gsub("\\", "/"):gsub("/+$", "") or ""
        check(directory:lower() == (ROOT .. "/" .. deps.boot_id):lower(), "Iris capture output is outside its boot directory")
        local filename = "eye-iris-" .. deps.nonce:lower() .. "-" .. phase .. ".png"
        check(deps.output_exists(directory .. "/" .. filename) == false, "Iris capture output already exists or cannot be checked")
        current = inspect(deps, sample)
        verify_receivers(current)
        local math_library = deps.static_find_object("/Script/Engine.Default__KismetMathLibrary")
        local rendering = deps.static_find_object("/Script/Engine.Default__KismetRenderingLibrary")
        check(valid(math_library) and math_library:IsA("/Script/Engine.KismetMathLibrary") == true
            and valid(rendering) and rendering:IsA("/Script/Engine.KismetRenderingLibrary") == true, "Native iris capture libraries are unavailable")
        view, geometry, pair = closeup(current, math_library)
        verify_receivers(current); verify_player(deps, current)
        camera_attempted = true
        local capture = current.capture
        capture.bCaptureEveryFrame, capture.bCaptureOnMovement = false, false
        for _, eye in ipairs(current.eyes) do
            verify_receivers(current); verify_player(deps, current)
            eye.attempted = true
            current.head:SetMaterial(eye.slot, eye.source)
            check(same(current.head:GetMaterial(eye.slot), eye.source_identity), "Inventory eye borrowing did not read back")
        end
        verify_receivers(current); verify_player(deps, current)
        capture.ProjectionType, capture.FOVAngle, capture.CustomNearClippingPlane, capture.bOverride_CustomNearClippingPlane = 0, view.field_of_view, view.near_clip, true
        local look_at = rotation(math_library:FindLookAtRotation(view.location, view.pivot))
        verify_receivers(current); verify_player(deps, current)
        capture:K2_SetWorldLocationAndRotation(view.location, look_at, false, {}, true)
        check(equal(vector(capture:K2_GetComponentLocation()), view.location) and equal(rotation(capture:K2_GetComponentRotation()), look_at)
            and capture.ProjectionType == 0 and capture.FOVAngle == view.field_of_view and capture.CustomNearClippingPlane == view.near_clip
            and flag(capture.bOverride_CustomNearClippingPlane) and not flag(capture.bCaptureEveryFrame) and not flag(capture.bCaptureOnMovement),
            "Native eye close-up camera did not read back")
        verify_receivers(current); verify_player(deps, current)
        check(equal(vector(capture:K2_GetComponentLocation()), view.location) and equal(rotation(capture:K2_GetComponentRotation()), look_at)
            and capture.FOVAngle == view.field_of_view, "Inventory close-up camera changed during export")
        local started = finite(deps.now()) * 1000
        capture:CaptureScene()
        export_invoked = true
        rendering:ExportRenderTarget(current.player:GetWorld(), current.target, directory, filename)
        local completed = finite(deps.now()) * 1000
        verify_receivers(current); verify_player(deps, current)
        check(equal(vector(capture:K2_GetComponentLocation()), view.location) and equal(rotation(capture:K2_GetComponentRotation()), look_at)
            and capture.ProjectionType == 0 and capture.FOVAngle == view.field_of_view and capture.CustomNearClippingPlane == view.near_clip
            and flag(capture.bOverride_CustomNearClippingPlane) and not flag(capture.bCaptureEveryFrame) and not flag(capture.bCaptureOnMovement),
            "Native close-up camera settings changed during export")
        for _, eye in ipairs(current.eyes) do check(same(current.head:GetMaterial(eye.slot), eye.source_identity), "Borrowed preview binding changed during export") end
        check(completed >= started, "Native export clock moved backwards")
        return { ok = true, kind = "native-inventory-iris-capture-evidence", phase = phase, nonce = deps.nonce, boot_id = deps.boot_id,
            baseline_id = sample.baseline_id, file_name = filename, width = 2048, height = 2048, render_target_format = 2, capture_source = 9,
            player = sample.player, world = sample.world, player_head = sample.head, player_asset = sample.asset,
            doll = record(current.doll, "/Script/DogwoodInventory.InventoryRenderDoll"),
            capture = record(capture, "/Script/Engine.SceneCaptureComponent2D"), preview_head = record(current.head, "/Script/Engine.SkeletalMeshComponent"),
            target = record(current.target, "/Script/Engine.TextureRenderTarget2D"), sampled_eyes = sample.eyes,
            eye_pair = pair, head_center = geometry.head_center, head_radius = geometry.head_radius, view = view, camera_rotation = look_at,
            camera_before = current.camera_before, camera_relative_before = current.relative,
            export_started_at_epoch_ms = started, export_completed_at_epoch_ms = completed,
            capture_timestamp_known = false, frame_verified = false, preview_verified = false, gameplay_verified = false }
    end)
    local failures = {}
    if current then
        for _, eye in ipairs(current.eyes) do
            if eye.attempted then
                local restored, message = pcall(function()
                    verify_head(current)
                    local actual = current.head:GetMaterial(eye.slot)
                    check(same(actual, eye.source_identity) or same(actual, eye.original_identity), "Replacement inventory eye binding will not be overwritten")
                    current.head:SetMaterial(eye.slot, eye.original)
                    check(same(current.head:GetMaterial(eye.slot), eye.original_identity), "Original inventory eye binding did not restore")
                    eye.restored_identity = record(current.head:GetMaterial(eye.slot), "/Script/Engine.MaterialInterface")
                end)
                if not restored then failures[#failures + 1] = tostring(message):sub(1, 512) end
            end
        end
        if camera_attempted then
            local restored, message = pcall(function()
                verify_capture(current)
                local capture, before = current.capture, current.camera_before
                capture:K2_SetRelativeTransform(current.relative, false, {}, true)
                capture.FOVAngle, capture.ProjectionType = before.fov, before.projection
                capture.CustomNearClippingPlane, capture.bOverride_CustomNearClippingPlane = before.near_clip, before.override_near
                capture.bCaptureEveryFrame, capture.bCaptureOnMovement = before.every_frame, before.on_movement
                check(equal(transform(capture:GetRelativeTransform()), current.relative) and capture.FOVAngle == before.fov
                    and capture.ProjectionType == before.projection and capture.CustomNearClippingPlane == before.near_clip
                    and flag(capture.bOverride_CustomNearClippingPlane) == before.override_near
                    and flag(capture.bCaptureEveryFrame) == before.every_frame and flag(capture.bCaptureOnMovement) == before.on_movement,
                    "Original inventory camera settings did not restore")
                camera_after = { relative_transform = transform(capture:GetRelativeTransform()), location = vector(capture:K2_GetComponentLocation()),
                    rotation = rotation(capture:K2_GetComponentRotation()), fov = capture.FOVAngle, projection = capture.ProjectionType,
                    near_clip = capture.CustomNearClippingPlane, override_near = flag(capture.bOverride_CustomNearClippingPlane),
                    every_frame = flag(capture.bCaptureEveryFrame), on_movement = flag(capture.bCaptureOnMovement),
                    capture_source = capture.CaptureSource, primitive_render_mode = capture.PrimitiveRenderMode }
                capture:CaptureScene()
                refresh_requested = true
            end)
            if not restored then failures[#failures + 1] = tostring(message):sub(1, 512) end
        end
        local player_ok, player_error = pcall(verify_player, deps, current)
        if not player_ok then failures[#failures + 1] = tostring(player_error):sub(1, 512) end
    end
    if ok and #failures == 0 then
        if phase == "baseline" then state.baseline_success = true end
        result.inventory_bindings_restored, result.inventory_camera_restored, result.inventory_refresh_requested = true, true, refresh_requested
        result.preview_eye_bindings = {}
        for _, eye in ipairs(current.eyes) do
            result.preview_eye_bindings[#result.preview_eye_bindings + 1] = { slot = eye.slot, original = eye.original_identity,
                borrowed = eye.source_identity, restored = eye.restored_identity }
        end
        result.export_invoked = export_invoked
        result.camera_after = camera_after
        return result
    end
    return { ok = false, phase = phase, nonce = deps and deps.nonce, boot_id = deps and deps.boot_id,
        kind = "native-inventory-iris-capture-evidence", export_invoked = export_invoked, inventory_refresh_requested = refresh_requested,
        doll = current and identity(current.record), capture = current and identity(current.record.capture),
        preview_head = current and identity(current.record.meshes.HeadMeshComponent), target = current and identity(current.record.capture.target),
        frame_verified = false, preview_verified = false, gameplay_verified = false,
        reason = ok and "Inventory capture restoration failed" or tostring(result):sub(1, 1024), restoration_failures = failures }
end

return Probe
