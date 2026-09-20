local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_frame_export_probe")

-- Explicitly requested QA operations only. Requiring this module performs no work.
local Probe = {}
local BUILD_ID = "25129649"
local EXECUTABLE_SHA256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
local OUTPUT_ROOT = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-frames"
local DOLL_CLASS = "/Script/DogwoodInventory.InventoryRenderDoll"
local TARGET_NAME = "TextureRenderTarget2D /Game/_Dawnwalker/UI/_Unified/GameHub/Inventory/Doll/RT_RenderDoll.RT_RenderDoll"
local used_requests, attempted_operations = {}, 0

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function finite(value, label)
    require_condition(type(value) == "number" and value == value and math.abs(value) < math.huge, label .. " is not finite")
    return value
end

local function matches(object, record)
    return object ~= nil and object:IsValid() == true and tostring(object:GetAddress()) == record.address
        and object:GetFullName() == record.name
end

local function observe_rotation(rotator)
    -- Current CL-257186 CoreUObject.hpp: pitch, Yaw, Roll (mixed case).
    return { pitch = finite(rotator.pitch, "pitch"), yaw = finite(rotator.Yaw, "yaw"), roll = finite(rotator.Roll, "roll") }
end

local function observe_vector(vector)
    return { x = finite(vector.X, "X"), y = finite(vector.Y, "Y"), z = finite(vector.Z, "Z") }
end

local function close(left, right, angular)
    for key, expected in pairs(right) do
        local actual = finite(left[key], key)
        local difference = angular and ((actual - expected + 180) % 360 - 180) or actual - expected
        if math.abs(difference) > 0.00001 then return false end
    end
    return true
end

local function authorize(deps, intent)
    require_condition(type(deps) == "table" and deps.game_thread == true, "Game-thread operation required")
    require_condition(type(deps.identity) == "table" and deps.identity.build_id == BUILD_ID
        and deps.identity.executable_sha256 == EXECUTABLE_SHA256, "Current-build identity mismatch")
    require_condition(deps.intent == intent, "Explicit operation intent mismatch")
    require_condition(type(deps.nonce) == "string" and #deps.nonce == 32 and deps.nonce:match("^%x+$") ~= nil,
        "Operation nonce must be 32 hexadecimal characters")
    require_condition(type(deps.boot_id) == "string" and #deps.boot_id <= 64
        and deps.boot_id:match("^%d+%-%d+$") ~= nil, "Driver boot identity is invalid")
    require_condition(type(deps.preview_probe) == "function" and type(deps.get_player) == "function"
        and type(deps.find_all_of) == "function", "Native observation dependencies are incomplete")
    local key = deps.boot_id .. ":" .. deps.nonce:lower()
    require_condition(not used_requests[key] and attempted_operations < 4, "Native operation was consumed or its budget is exhausted")
    used_requests[key], attempted_operations = true, attempted_operations + 1
end

local function require_flag(record, key, expected)
    local observed = record.flags[key]
    require_condition(observed ~= nil and observed.ok == true and observed.value == expected, "Capture flag mismatch: " .. key)
end

local function context(deps)
    local snapshot = deps.preview_probe(deps)
    require_condition(snapshot.ok == true and snapshot.observed_doll_count == 1 and snapshot.is_wolf_form == false,
        "Exactly one owned non-wolf native preview is required")
    local record
    for _, candidate in ipairs(snapshot.dolls) do if candidate.ok then record = candidate.value end end
    require_condition(record ~= nil and record.root and not record.root.unset, "Owned native preview root is unavailable")
    local player = deps.get_player()
    require_condition(matches(player, snapshot.player) and matches(player:GetWorld(), snapshot.world), "Player identity changed")
    local selected
    for _, doll in ipairs(deps.find_all_of("InventoryRenderDoll") or {}) do
        if matches(doll, record) then require_condition(selected == nil, "Duplicate preview actor"); selected = doll end
    end
    require_condition(selected ~= nil and selected:IsA(DOLL_CLASS) == true, "Owned preview actor disappeared")
    local capture, head = selected.SceneCapture, selected.HeadMeshComponent
    require_condition(matches(capture, record.capture) and matches(head, record.meshes.HeadMeshComponent), "Preview components changed")
    require_condition(matches(capture:GetOwner(), record) and matches(head:GetOwner(), record), "Preview ownership changed")
    require_condition(matches(capture:GetAttachParent(), record.root), "Capture must be attached directly to its own preview root")
    require_condition(matches(selected.RootComponent, record.root) and matches(selected:GetWorld(), snapshot.world), "Preview root/world changed")
    local target = capture.TextureTarget
    require_condition(matches(target, record.capture.target) and target:GetFullName() == TARGET_NAME
        and target.SizeX == 2048 and target.SizeY == 2048 and target.RenderTargetFormat == 2 and target.OverrideFormat == 0,
        "The observed native RGBA8 render target changed")
    require_condition(record.capture.fields.CaptureSource.ok and record.capture.fields.CaptureSource.value == 9
        and capture.CaptureSource == 9 and capture.PrimitiveRenderMode == 2, "Native capture source or show-only mode changed")
    for _, key in ipairs({ "bMainViewCamera", "bMainViewFamily", "bMainViewResolution", "bRenderInMainRenderer" }) do
        require_flag(record.capture, key, false)
        require_condition(capture[key] == false, "Capture is connected to the gameplay view")
    end
    require_flag(record.capture, "bCaptureEveryFrame", true)
    require_condition(capture.bCaptureEveryFrame == true, "Native inventory capture is inactive")
    local head_shown = false
    local listed = record.capture.lists.ShowOnlyComponents
    require_condition(listed.ok == true, "Native capture inclusion list is unavailable")
    for _, entry in ipairs(listed.value) do
        if entry.ok and entry.value.address == record.meshes.HeadMeshComponent.address then head_shown = true end
    end
    require_condition(head_shown, "Native head is not explicitly included by its capture")
    return { player = player, doll = selected, capture = capture, head = head, target = target, snapshot = snapshot, record = record }
end

local function verify_context(deps, current)
    local player, record, snapshot = deps.get_player(), current.record, current.snapshot
    require_condition(matches(player, snapshot.player) and matches(player:GetWorld(), snapshot.world)
        and player.Form == snapshot.form and player:IsInWolfForm() == snapshot.is_wolf_form, "Player/world/form changed during native operation")
    require_condition(matches(current.doll, record) and matches(current.doll:GetWorld(), snapshot.world)
        and matches(current.doll.TargetInventory, record.inventory) and matches(current.doll.TargetInventory:GetOwner(), snapshot.player),
        "Preview ownership changed during native operation")
    require_condition(matches(current.doll.SceneCapture, record.capture) and matches(current.capture:GetOwner(), record)
        and matches(current.capture:GetAttachParent(), record.root) and matches(current.doll.RootComponent, record.root),
        "Preview capture topology changed during native operation")
    require_condition(matches(current.capture.TextureTarget, record.capture.target) and current.target.SizeX == 2048
        and current.target.SizeY == 2048 and current.target.RenderTargetFormat == 2 and current.target.OverrideFormat == 0,
        "Native render target changed during operation")
    require_condition(matches(current.doll.HeadMeshComponent, record.meshes.HeadMeshComponent)
        and matches(current.head:GetOwner(), record) and matches(current.head:GetSkeletalMeshAsset(), record.meshes.HeadMeshComponent.asset),
        "Preview head changed during native operation")
    require_condition(current.head:GetNumMaterials() == #record.meshes.HeadMeshComponent.materials, "Preview material count changed")
    for _, binding in ipairs(record.meshes.HeadMeshComponent.materials) do
        require_condition(matches(current.head:GetMaterial(binding.slot), binding), "Preview eye/head material changed during native operation")
    end
    require_condition(current.capture.CaptureSource == 9 and current.capture.PrimitiveRenderMode == 2
        and current.capture.bCaptureEveryFrame == true, "Native capture configuration changed during operation")
    for _, key in ipairs({ "bMainViewCamera", "bMainViewFamily", "bMainViewResolution", "bRenderInMainRenderer" }) do
        require_condition(current.capture[key] == false, "Capture is connected to the gameplay view")
    end
end

local function identity_evidence(current)
    return { player = current.snapshot.player, world = current.snapshot.world, form = current.snapshot.form,
        is_wolf_form = current.snapshot.is_wolf_form, doll = { address = current.record.address, name = current.record.name },
        capture = { address = current.record.capture.address, name = current.record.capture.name },
        head = { address = current.record.meshes.HeadMeshComponent.address, name = current.record.meshes.HeadMeshComponent.name },
        head_asset = current.record.meshes.HeadMeshComponent.asset, target = { address = current.record.capture.target.address,
            name = current.record.capture.target.name }, head_materials = current.record.meshes.HeadMeshComponent.materials }
end

local function export_frame(deps, current, filename, capture_now, on_invoked)
    require_condition(type(deps.static_find_object) == "function" and type(deps.now) == "function"
        and type(deps.output_exists) == "function", "Native frame export dependencies are incomplete")
    local directory = type(deps.output_directory) == "string" and deps.output_directory:gsub("\\", "/"):gsub("/+$", "") or ""
    require_condition(directory:lower() == (OUTPUT_ROOT .. "/" .. deps.boot_id):lower(), "Export directory is outside this driver session")
    require_condition(deps.output_exists(directory .. "/" .. filename) == false, "Native export destination already exists or cannot be checked")
    verify_context(deps, current)
    local library = deps.static_find_object("/Script/Engine.Default__KismetRenderingLibrary")
    require_condition(library ~= nil and library:IsValid() == true and library:IsA("/Script/Engine.KismetRenderingLibrary") == true,
        "The native rendering library is unavailable")
    local started = finite(deps.now(), "export start time") * 1000
    if capture_now then current.capture:CaptureScene() end
    on_invoked()
    library:ExportRenderTarget(current.player:GetWorld(), current.target, directory, filename)
    local completed = finite(deps.now(), "export completion time") * 1000
    verify_context(deps, current)
    require_condition(completed >= started, "Export clock moved backwards")
    return { file_name = filename, export_invoked = true, capture_requested = capture_now,
        width = 2048, height = 2048, render_target_format = 2, capture_source = 9,
        export_started_at_epoch_ms = started, export_completed_at_epoch_ms = completed,
        capture_timestamp_known = false, frame_verified = false }
end

function Probe.run(deps)
    local invoked = false
    local ok, result = pcall(function()
        authorize(deps, "eye-readback-export")
        local filename = "eye-frame-" .. deps.nonce:lower() .. ".png"
        local current = context(deps)
        local receipt = export_frame(deps, current, filename, false, function() invoked = true end)
        receipt.ok, receipt.schema, receipt.kind = true, 1, "native-eye-frame-export-evidence"
        receipt.nonce, receipt.boot_id = deps.nonce:lower(), deps.boot_id
        receipt.preview_verified, receipt.gameplay_verified = false, false
        receipt.identity, receipt.capture_relative_rotation = identity_evidence(current), current.record.capture.relative_rotation
        receipt.limitation = "One existing native render target export. PNG integrity, visible content and frame freshness need independent validation."
        return receipt
    end)
    if ok then return result end
    return { ok = false, export_invoked = invoked, frame_verified = false, preview_verified = false,
        gameplay_verified = false, reason = tostring(result):sub(1, 1024) }
end

function Probe.run_camera_roundtrip(deps)
    local current, baseline, player_location, player_rotation
    local attempted, restored = false, false
    local frames, exports_invoked = {}, 0
    local function capture_phase(phase)
        local frame = export_frame(deps, current, "eye-camera-" .. deps.nonce:lower() .. "-" .. phase .. ".png", true,
            function() exports_invoked = exports_invoked + 1 end)
        frame.phase, frame.relative_rotation = phase, observe_rotation(current.capture.RelativeRotation)
        frames[#frames + 1] = frame
    end
    local ok, result = pcall(function()
        authorize(deps, "eye-preview-camera-roundtrip")
        current = context(deps)
        verify_context(deps, current)
        baseline = observe_rotation(current.capture.RelativeRotation)
        player_location = observe_vector(current.player:K2_GetActorLocation())
        player_rotation = observe_rotation(current.player:K2_GetActorRotation())
        require_condition(math.abs(baseline.yaw) <= 360 and math.abs(baseline.pitch) <= 90 and math.abs(baseline.roll) <= 360,
            "Native relative camera rotation is outside expected bounds")
        require_condition(type(deps.capture_frames) == "boolean", "Camera frame-export choice must be explicit")
        if deps.capture_frames then capture_phase("baseline") end
        attempted = true
        current.capture:K2_SetRelativeRotation({ pitch = baseline.pitch, Yaw = baseline.yaw + 3, Roll = baseline.roll }, false, {}, true)
        verify_context(deps, current)
        local changed = observe_rotation(current.capture.RelativeRotation)
        require_condition(close(changed, { pitch = baseline.pitch, yaw = baseline.yaw + 3, roll = baseline.roll }, true),
            "Preview camera rotation did not read back the requested three degrees")
        if deps.capture_frames then capture_phase("changed") end
        return { ok = true, schema = 1, kind = "native-eye-camera-roundtrip-evidence", nonce = deps.nonce:lower(), boot_id = deps.boot_id,
            identity = identity_evidence(current),
            before = baseline, changed = changed, delta_yaw_degrees = 3, frame_verified = false, gameplay_verified = false }
    end)
    local restore_ok, restore_error = true, nil
    if attempted then
        restore_ok, restore_error = pcall(function()
            -- Restore only the exact surviving capture, never a replacement or the gameplay camera.
            require_condition(matches(current.capture, current.record.capture) and matches(current.capture:GetOwner(), current.record)
                and matches(current.capture:GetAttachParent(), current.record.root) and matches(current.doll.RootComponent, current.record.root)
                and matches(current.doll:GetWorld(), current.snapshot.world), "Original preview capture cannot safely be restored")
            current.capture:K2_SetRelativeRotation({ pitch = baseline.pitch, Yaw = baseline.yaw, Roll = baseline.roll }, false, {}, true)
            require_condition(close(observe_rotation(current.capture.RelativeRotation), baseline, true), "Preview camera restoration failed readback")
            restored = true
            require_condition(close(observe_vector(current.player:K2_GetActorLocation()), player_location, false)
                and close(observe_rotation(current.player:K2_GetActorRotation()), player_rotation, true), "Player transform changed during preview-only test")
            verify_context(deps, current)
            if deps.capture_frames then capture_phase("restored") end
        end)
    end
    if ok and restore_ok then
        result.mutation_attempted, result.restored, result.frames, result.exports_invoked = attempted, restored, frames, exports_invoked
        return result
    end
    return { ok = false, mutation_attempted = attempted, restored = restored, frame_verified = false, gameplay_verified = false,
        reason = tostring(not ok and result or "Preview camera restore failed"):sub(1, 1024),
        restore_error = restore_ok and nil or tostring(restore_error):sub(1, 1024), frames = frames, exports_invoked = exports_invoked }
end

return Probe
