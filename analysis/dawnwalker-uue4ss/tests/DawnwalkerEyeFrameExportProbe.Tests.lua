local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_frame_export_probe_tests")
local path = assert(arg[1], "Pass the frame-export probe source path")

local function object(address, name)
    return { address = address, name = name, valid = true,
        IsValid = function(self) return self.valid end,
        IsA = function() return true end,
        GetAddress = function(self) return self.address end,
        GetFullName = function(self) return self.name end }
end

local function identity(value) return { address = tostring(value.address), name = value.name } end

local function fixture()
    local probe = assert(dofile(path))
    local world, player, doll = object(1, "World NativeWorld"), object(2, "Player NativeWorld.Player"), object(3, "Doll NativeWorld.Doll")
    local capture, root, head, asset = object(4, "Capture Doll.Capture"), object(5, "SceneComponent Doll.Root"), object(6, "Head Doll.Head"), object(7, "HeadAsset Coen")
    local material, inventory = object(8, "Material Eye"), object(9, "Inventory Player.Inventory")
    local target = object(10, "TextureRenderTarget2D /Game/_Dawnwalker/UI/_Unified/GameHub/Inventory/Doll/RT_RenderDoll.RT_RenderDoll")
    player.Form, player.wolf = 0, false
    function player:GetWorld() return world end
    function player:IsInWolfForm() return self.wolf end
    function player:K2_GetActorLocation() return { X = 1, Y = 2, Z = 3 } end
    function player:K2_GetActorRotation() return { pitch = 0, Yaw = 20, Roll = 0 } end
    function doll:GetWorld() return world end
    function inventory:GetOwner() return player end
    doll.TargetInventory, doll.RootComponent, doll.HeadMeshComponent, doll.SceneCapture = inventory, root, head, capture
    function capture:GetOwner() return doll end
    function capture:GetAttachParent() return root end
    function head:GetOwner() return doll end
    function head:GetSkeletalMeshAsset() return asset end
    function head:GetNumMaterials() return 1 end
    function head:GetMaterial(index) assert(index == 0); return material end
    capture.TextureTarget, capture.CaptureSource, capture.PrimitiveRenderMode = target, 9, 2
    capture.bCaptureEveryFrame = true
    capture.RelativeRotation = { pitch = -6, Yaw = 180, Roll = 0 }
    target.SizeX, target.SizeY, target.RenderTargetFormat, target.OverrideFormat = 2048, 2048, 2, 0
    local record = identity(doll)
    record.root, record.inventory = identity(root), identity(inventory)
    record.capture = identity(capture)
    record.capture.target = identity(target)
    record.capture.flags = { bCaptureEveryFrame = { ok = true, value = true } }
    for _, flag in ipairs({ "bMainViewCamera", "bMainViewFamily", "bMainViewResolution", "bRenderInMainRenderer" }) do
        capture[flag] = false
        record.capture.flags[flag] = { ok = true, value = false }
    end
    record.capture.fields = { CaptureSource = { ok = true, value = 9 } }
    record.capture.lists = { ShowOnlyComponents = { ok = true, value = { { ok = true, value = identity(head) } } } }
    record.meshes = { HeadMeshComponent = identity(head) }
    record.meshes.HeadMeshComponent.asset = identity(asset)
    record.meshes.HeadMeshComponent.materials = { identity(material) }
    record.meshes.HeadMeshComponent.materials[1].slot = 0
    local snapshot = { ok = true, observed_doll_count = 1, is_wolf_form = false, form = 0,
        player = identity(player), world = identity(world), dolls = { { ok = true, value = record } } }
    local state = { exports = {}, captures = {}, setters = {}, files = {}, snapshot = snapshot }
    function capture:CaptureScene() state.captures[#state.captures + 1] = self.RelativeRotation.Yaw end
    function capture:K2_SetRelativeRotation(rotation, sweep, hit, teleport)
        assert(type(rotation.pitch) == "number" and type(rotation.Yaw) == "number" and type(rotation.Roll) == "number")
        assert(sweep == false and teleport == true and type(hit) == "table")
        state.setters[#state.setters + 1] = rotation.Yaw
        self.RelativeRotation = rotation
    end
    local library = object(11, "KismetRenderingLibrary Native")
    function library:ExportRenderTarget(context, exported_target, directory, filename)
        assert(context == world and exported_target == target)
        state.exports[#state.exports + 1] = { filename = filename, yaw = capture.RelativeRotation.Yaw }
        state.files[directory .. "/" .. filename] = true
    end
    local deps = { game_thread = true, intent = "eye-readback-export", nonce = string.rep("a", 32), boot_id = "1788665589-157248",
        identity = { build_id = "25129649", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853" },
        get_player = function() return player end, find_all_of = function() return { doll } end,
        preview_probe = function() return snapshot end, now = function() return 1788665700 end,
        static_find_object = function(name) assert(name == "/Script/Engine.Default__KismetRenderingLibrary"); return library end,
        output_directory = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-frames/1788665589-157248",
        output_exists = function(filename) return state.files[filename] == true end, capture_frames = true }
    state.player, state.doll, state.capture, state.target, state.material, state.library = player, doll, capture, target, material, library
    return probe, deps, state
end

local count = 0
local function test(name, action) action(); count = count + 1; print("PASS " .. name) end

test("export is one native PNG request tied to observed current identity, with no freshness or render verification claim", function()
    local probe, deps, state = fixture()
    local receipt = probe.run(deps)
    assert(receipt.ok and receipt.export_invoked and not receipt.capture_timestamp_known and not receipt.frame_verified)
    assert(receipt.kind == "native-eye-frame-export-evidence" and receipt.identity.head.address == "6")
    assert(#state.exports == 1 and #state.captures == 0 and #state.setters == 0)
    assert(receipt.file_name == "eye-frame-" .. deps.nonce .. ".png" and receipt.export_started_at_epoch_ms == 1788665700000)
end)

test("intent, build, thread, invalid boot, traversal and existing destination reject writes", function()
    for _, scenario in ipairs({ "intent", "build", "thread", "boot", "path", "exists" }) do
        local probe, deps, state = fixture()
        if scenario == "intent" then deps.intent = "read-only"
        elseif scenario == "build" then deps.identity.build_id = "old"
        elseif scenario == "thread" then deps.game_thread = false
        elseif scenario == "boot" then deps.boot_id = "../other"
        elseif scenario == "path" then deps.output_directory = deps.output_directory .. "/../other"
        else deps.output_exists = function() return true end end
        assert(not probe.run(deps).ok and #state.exports == 0 and #state.setters == 0, scenario)
    end
end)

test("missing doll, foreign ownership, main camera and changed RT refuse export", function()
    for _, scenario in ipairs({ "doll", "owner", "camera", "target", "headlist" }) do
        local probe, deps, state = fixture()
        if scenario == "doll" then state.snapshot.observed_doll_count = 0
        elseif scenario == "owner" then function state.capture:GetOwner() return state.player end
        elseif scenario == "camera" then state.capture.bMainViewCamera = true
        elseif scenario == "headlist" then state.snapshot.dolls[1].value.capture.lists.ShowOnlyComponents.value = {}
        else state.target.RenderTargetFormat = 6 end
        assert(not probe.run(deps).ok and #state.exports == 0, scenario)
    end
end)

test("nonce replay and a fifth native operation refuse additional work", function()
    local probe, deps, state = fixture()
    assert(probe.run(deps).ok and not probe.run(deps).ok)
    for index = 1, 3 do deps.nonce = string.rep(tostring(index), 32); assert(probe.run(deps).ok) end
    deps.nonce = string.rep("f", 32)
    assert(not probe.run(deps).ok and #state.exports == 4)
end)

test("export errors and changing identities cannot report a verified frame", function()
    for _, scenario in ipairs({ "throw", "changed" }) do
        local probe, deps, state = fixture()
        function state.library:ExportRenderTarget()
            if scenario == "throw" then error("native export failed") else state.material.address = 999 end
        end
        local receipt = probe.run(deps)
        assert(not receipt.ok and receipt.export_invoked and not receipt.frame_verified)
    end
end)

test("camera roundtrip captures native baseline, changed, restored with stable player transform", function()
    local probe, deps, state = fixture()
    deps.intent = "eye-preview-camera-roundtrip"
    local receipt = probe.run_camera_roundtrip(deps)
    assert(receipt.ok and receipt.mutation_attempted and receipt.restored and not receipt.frame_verified)
    assert(#state.exports == 3 and #state.captures == 3 and #state.setters == 2 and state.capture.RelativeRotation.Yaw == 180)
    assert(state.exports[1].yaw == 180 and state.exports[2].yaw == 183 and state.exports[3].yaw == 180)
    assert(receipt.frames[1].phase == "baseline" and receipt.frames[2].phase == "changed" and receipt.frames[3].phase == "restored")
end)

test("camera rejects unobserved rotator layout before any scene capture or setter", function()
    local probe, deps, state = fixture()
    deps.intent = "eye-preview-camera-roundtrip"
    state.capture.RelativeRotation = { Pitch = 1, Yaw = 2, Roll = 3 }
    local receipt = probe.run_camera_roundtrip(deps)
    assert(not receipt.ok and not receipt.mutation_attempted and #state.captures == 0 and #state.setters == 0)
end)

test("camera readback mismatch still restores through the same surviving capture", function()
    local probe, deps, state = fixture()
    deps.intent, deps.capture_frames = "eye-preview-camera-roundtrip", false
    function state.capture:K2_SetRelativeRotation(rotation)
        state.setters[#state.setters + 1] = rotation.Yaw
        self.RelativeRotation = { pitch = rotation.pitch, Yaw = rotation.Yaw == 183 and 184 or rotation.Yaw, Roll = rotation.Roll }
    end
    local receipt = probe.run_camera_roundtrip(deps)
    assert(not receipt.ok and receipt.mutation_attempted and receipt.restored and #state.setters == 2)
end)

test("partial camera export failure restores and records available evidence", function()
    local probe, deps, state = fixture()
    deps.intent = "eye-preview-camera-roundtrip"
    local export = state.library.ExportRenderTarget
    function state.library:ExportRenderTarget(context, target, directory, filename)
        if filename:find("changed", 1, true) then error("changed frame export failed") end
        return export(self, context, target, directory, filename)
    end
    local receipt = probe.run_camera_roundtrip(deps)
    assert(not receipt.ok and receipt.restored and state.capture.RelativeRotation.Yaw == 180 and #receipt.frames == 2)
end)

test("replaced capture never receives restoration writes", function()
    local probe, deps, state = fixture()
    deps.intent, deps.capture_frames = "eye-preview-camera-roundtrip", false
    function state.capture:K2_SetRelativeRotation() state.capture.address = 999; state.setters[#state.setters + 1] = 1 end
    local receipt = probe.run_camera_roundtrip(deps)
    assert(not receipt.ok and not receipt.restored and #state.setters == 1 and receipt.restore_error)
end)

print("PASS " .. count .. " native frame-export probe test groups")
