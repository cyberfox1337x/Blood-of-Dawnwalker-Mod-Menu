local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_inventory_eye_capture_probe_tests")
local path = assert(arg[1], "Pass the inventory iris capture module path")
package.path = path:match("^(.*[/\\])") .. "?.lua;" .. package.path
local function object(address, name)
    local value = { address = address, name = name, valid = true }
    function value:IsValid() return self.valid end
    function value:IsA() return true end
    function value:GetAddress() return self.address end
    function value:GetFullName() return self.name end
    return value
end
local function identity(value) return { address = tostring(value.address), name = value.name } end
local function point(x, y, z) return { X = x, Y = y, Z = z } end
local function transform(position) return { Translation = position, Scale3D = point(1, 1, 1), Rotation = { X = 0, Y = 0, Z = 0, W = 1 } } end
local function name(value) return { ToString = function() return value end } end
local function fixture()
    local probe = assert(dofile(path))
    local world, player, doll = object(1, "World /Game/Actual.World"), object(2, "Player World.Player"), object(3, "InventoryRenderDoll World.Doll")
    local player_head, head, capture, root, inventory = object(4, "Mesh Player.Head"), object(5, "Mesh Doll.Head"),
        object(6, "Capture Doll.Capture"), object(7, "Component Doll.Root"), object(8, "Inventory Player.Inventory")
    local asset = object(9, "SkeletalMesh /Game/Actual.Head")
    local target = object(10, "TextureRenderTarget2D /Game/_Dawnwalker/UI/_Unified/GameHub/Inventory/Doll/RT_RenderDoll.RT_RenderDoll")
    local state = { exports = {}, capture_calls = {}, live_setters = 0, set_calls = 0 }
    local original_left, original_right = object(20, "Material Doll.Left"), object(21, "Material Doll.Right")
    local live_left, live_right = object(30, "Material Player.Left"), object(31, "Material Player.Right")
    local slots = { name("skin"), name("mouth"), name("lashes"), name("shader_eyeLeft_shader"), name("shader_eyeRight_shader") }
    player.Form, player.HeadMesh = 0, player_head
    function player:GetWorld() return world end
    function player:IsInWolfForm() return false end
    function player:K2_GetActorLocation() return point(10, 20, 30) end
    function player:K2_GetActorRotation() return { pitch = 0, Yaw = 0, Roll = 0 } end
    function player_head:GetOwner() return player end
    function player_head:GetSkeletalMeshAsset() return asset end
    player_head.materials = { [3] = live_left, [4] = live_right }
    function player_head:GetMaterial(slot) return self.materials[slot] end
    function player_head:GetMaterialSlotNames() return slots end
    function player_head:SetMaterial() state.live_setters = state.live_setters + 1; error("Player is read-only to capture adapter") end
    doll.HeadMeshComponent, doll.SceneCapture, doll.RootComponent, doll.TargetInventory = head, capture, root, inventory
    function doll:GetWorld() return world end
    function doll:GetActorForwardVector() return point(1, 0, 0) end
    function inventory:GetOwner() return player end
    head.materials = { [3] = original_left, [4] = original_right }
    function head:GetOwner() return state.head_owner or doll end
    function head:GetSkeletalMeshAsset() return asset end
    function head:GetMaterialSlotNames() return slots end
    function head:GetMaterial(slot) return self.materials[slot] end
    function head:SetMaterial(slot, material)
        state.set_calls = state.set_calls + 1
        self.materials[slot] = material
        if state.fail_borrow_slot == slot and material == player_head.materials[slot] then error("borrow setter failed after native write") end
    end
    function head:K2_GetComponentToWorld() return transform(point(10, 20, 30)) end
    local bones = { "root", "Head", "FACIAL_L_Eye", "FACIAL_R_Eye" }
    function head:GetNumBones() return #bones end
    function head:GetBoneName(index) return name(bones[index + 1]) end
    function head:DoesSocketExist() return true end
    function head:GetSocketLocation(bone)
        if bone:ToString() == "FACIAL_L_Eye" then return point(18, 17, 197) end
        if bone:ToString() == "FACIAL_R_Eye" then return point(18, 23, 197) end
        return point(10, 20, 190)
    end
    function asset:GetBounds() return { Origin = point(0, 0, 160), SphereRadius = 20 } end
    target.SizeX, target.SizeY, target.RenderTargetFormat, target.OverrideFormat = 2048, 2048, 2, 0
    capture.TextureTarget, capture.CaptureSource, capture.PrimitiveRenderMode = target, 9, 2
    capture.bMainViewCamera, capture.bMainViewFamily, capture.bMainViewResolution, capture.bRenderInMainRenderer = false, false, false, false
    capture.FOVAngle, capture.ProjectionType, capture.CustomNearClippingPlane = 30, 0, 10
    capture.bOverride_CustomNearClippingPlane, capture.bCaptureEveryFrame, capture.bCaptureOnMovement = false, true, true
    capture.relative, capture.location, capture.rotation = transform(point(425, 0, 45)), point(435, 20, 75), { pitch = 6.3, Yaw = 180, Roll = 0 }
    function capture:GetOwner() return state.capture_owner or doll end
    function capture:GetAttachParent() return root end
    function capture:GetRelativeTransform() return self.relative end
    function capture:K2_GetComponentLocation() return self.location end
    function capture:K2_GetComponentRotation() return self.rotation end
    function capture:K2_SetWorldLocationAndRotation(location, rotation)
        self.location, self.rotation = location, rotation
        self.relative = transform(point(location.X - 10, location.Y - 20, location.Z - 30))
    end
    function capture:K2_SetRelativeTransform(relative)
        self.relative = relative
        self.location = point(relative.Translation.X + 10, relative.Translation.Y + 20, relative.Translation.Z + 30)
        self.rotation = { pitch = 6.3, Yaw = 180, Roll = 0 }
    end
    function capture:CaptureScene()
        state.capture_calls[#state.capture_calls + 1] = { left = head.materials[3], right = head.materials[4], fov = self.FOVAngle }
    end
    local math_library, rendering = object(100, "Library Math"), object(101, "Library Rendering")
    function math_library:FindLookAtRotation() return { pitch = 0, Yaw = 180, Roll = 0 } end
    function math_library:TransformLocation(world_transform, location)
        return point(world_transform.Translation.X + location.X, world_transform.Translation.Y + location.Y, world_transform.Translation.Z + location.Z)
    end
    function rendering:ExportRenderTarget(context, render_target, directory, filename)
        assert(context == world and render_target == target)
        state.exports[#state.exports + 1] = { file_name = filename, directory = directory, captured = state.capture_calls[#state.capture_calls] }
        if state.on_export then state.on_export() end
    end
    local function observation()
        local head_record, capture_record = identity(head), identity(capture)
        head_record.asset = identity(asset)
        capture_record.target = identity(target)
        capture_record.lists = { ShowOnlyComponents = { ok = true, value = { { ok = true, value = identity(head) } } } }
        local doll_record = identity(doll)
        doll_record.capture, doll_record.meshes, doll_record.root, doll_record.inventory = capture_record, { HeadMeshComponent = head_record }, identity(root), identity(inventory)
        return { ok = true, observed_doll_count = state.no_inventory and 0 or 1, form = 0, is_wolf_form = false,
            player = identity(player), world = identity(world), dolls = { { ok = true, value = doll_record } } }
    end
    local deps = { game_thread = true, intent = "human-iris-pair-roundtrip", nonce = string.rep("a", 32), boot_id = "1788668034-658838",
        identity = { build_id = "25129649", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853" },
        get_player = function() return player end, find_all_of = function(class) assert(class == "InventoryRenderDoll"); return { doll } end,
        preview_probe = observation, now = function() return 1788668040 end, output_exists = function() return false end,
        output_directory = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-frames/1788668034-658838",
        static_find_object = function(name) return name:find("KismetMathLibrary", 1, true) and math_library or rendering end }
    local function sample(phase)
        return { phase = phase, nonce = deps.nonce, boot_id = deps.boot_id, baseline_id = deps.boot_id .. ":" .. deps.nonce,
            player = identity(player), world = identity(world), head = identity(player_head), asset = identity(asset), form = 0, is_wolf_form = false,
            eyes = { { slot = 3, slot_name = "shader_eyeLeft_shader", material = identity(player_head.materials[3]), parameters = {} },
                { slot = 4, slot_name = "shader_eyeRight_shader", material = identity(player_head.materials[4]), parameters = {} } } }
    end
    state.player, state.player_head, state.doll, state.head, state.capture, state.target = player, player_head, doll, head, capture, target
    state.original_left, state.original_right = original_left, original_right
    return probe, deps, state, sample
end

local count = 0
local function test(name, action) action(); count = count + 1; print("PASS " .. name) end
local function assert_restored(state)
    assert(state.head.materials[3] == state.original_left and state.head.materials[4] == state.original_right)
    assert(state.capture.FOVAngle == 30 and state.capture.CustomNearClippingPlane == 10 and not state.capture.bOverride_CustomNearClippingPlane)
    assert(state.capture.bCaptureEveryFrame and state.capture.bCaptureOnMovement and state.capture.relative.Translation.X == 425)
    assert(state.live_setters == 0)
end

test("actual current bindings are borrowed for eye closeup then both inventory bindings and camera restore", function()
    local probe, deps, state, sample = fixture()
    local receipt = probe.run(deps, "baseline", sample("baseline"))
    assert(receipt.ok, receipt.reason or table.concat(receipt.restoration_failures or {}, ","))
    assert(#state.exports == 1 and #state.capture_calls == 2 and state.exports[1].captured.fov == 20)
    assert(state.exports[1].captured.left == state.player_head.materials[3] and state.exports[1].captured.right == state.player_head.materials[4])
    assert(receipt.inventory_bindings_restored and receipt.inventory_camera_restored and not receipt.frame_verified)
    assert(receipt.boot_id == deps.boot_id and receipt.preview_eye_bindings[1].original.address == "20")
    assert_restored(state)
end)

test("three scalar phases capture the current changing player material without sharing inventory state", function()
    local probe, deps, state, sample = fixture()
    assert(probe.run(deps, "baseline", sample("baseline")).ok)
    local left, right = state.player_head.materials[3], state.player_head.materials[4]
    state.player_head.materials[3], state.player_head.materials[4] = object(60, "MID Player.Left"), object(61, "MID Player.Right")
    assert(probe.run(deps, "changed", sample("changed")).ok)
    assert(state.exports[2].captured.left.address == 60)
    state.player_head.materials[3], state.player_head.materials[4] = left, right
    assert(probe.run(deps, "restored", sample("restored")).ok)
    assert(#state.exports == 3 and state.exports[3].captured.left == left)
    assert_restored(state)
end)

test("guard failures and absent inventory reject all mutation", function()
    for _, scenario in ipairs({ "intent", "build", "phase", "nonce", "path", "file", "inventory", "sample" }) do
        local probe, deps, state, make_sample = fixture()
        local phase, sample = "baseline", make_sample("baseline")
        if scenario == "intent" then deps.intent = "read-only"
        elseif scenario == "build" then deps.identity.build_id = "old"
        elseif scenario == "phase" then phase = "changed"; sample.phase = phase
        elseif scenario == "nonce" then sample.nonce = string.rep("b", 32)
        elseif scenario == "path" then deps.output_directory = "C:/other"
        elseif scenario == "file" then deps.output_exists = function() return true end
        elseif scenario == "inventory" then state.no_inventory = true
        else sample.eyes[1].material.address = "999" end
        assert(not probe.run(deps, phase, sample).ok and state.set_calls == 0 and #state.exports == 0, scenario)
    end
end)

test("phase replay and captures after restoration reject without extra writes", function()
    local probe, deps, state, sample = fixture()
    assert(probe.run(deps, "baseline", sample("baseline")).ok)
    local calls = state.set_calls
    assert(not probe.run(deps, "baseline", sample("baseline")).ok and state.set_calls == calls)
    assert(probe.run(deps, "restored", sample("restored")).ok)
    calls = state.set_calls
    assert(not probe.run(deps, "changed", sample("changed")).ok and state.set_calls == calls)
end)

test("partial native borrow failure restores attempted eyes and the camera", function()
    local probe, deps, state, sample = fixture()
    state.fail_borrow_slot = 4
    local receipt = probe.run(deps, "baseline", sample("baseline"))
    assert(not receipt.ok and #state.exports == 0 and #receipt.restoration_failures == 0)
    assert_restored(state)
end)

test("export failure still restores inventory state without touching live materials", function()
    local probe, deps, state, sample = fixture()
    state.on_export = function() error("native PNG export failed") end
    local receipt = probe.run(deps, "baseline", sample("baseline"))
    assert(not receipt.ok and receipt.export_invoked and #receipt.restoration_failures == 0)
    assert_restored(state)
end)

test("capture receiver loss does not prevent independent original eye restoration", function()
    local probe, deps, state, sample = fixture()
    state.on_export = function() state.capture_owner = state.player end
    local receipt = probe.run(deps, "baseline", sample("baseline"))
    assert(not receipt.ok and #receipt.restoration_failures == 1)
    assert(state.head.materials[3] == state.original_left and state.head.materials[4] == state.original_right)
    assert(state.capture.FOVAngle == 20 and state.live_setters == 0)
end)

test("head receiver loss does not prevent independent original camera restoration", function()
    local probe, deps, state, sample = fixture()
    state.on_export = function() state.head_owner = state.player end
    local receipt = probe.run(deps, "baseline", sample("baseline"))
    assert(not receipt.ok and #receipt.restoration_failures == 2)
    assert(state.capture.FOVAngle == 30 and state.capture.bCaptureEveryFrame and state.live_setters == 0)
end)

test("replacement inventory eye is not overwritten while other eye and camera restore", function()
    local probe, deps, state, sample = fixture()
    local replacement = object(90, "Material OtherOwner.Replacement")
    state.on_export = function() state.head.materials[3] = replacement end
    local receipt = probe.run(deps, "baseline", sample("baseline"))
    assert(not receipt.ok and #receipt.restoration_failures == 1 and state.head.materials[3] == replacement)
    assert(state.head.materials[4] == state.original_right and state.capture.FOVAngle == 30)
end)

test("missing exact native eye endpoints fail before inventory changes", function()
    local probe, deps, state, sample = fixture()
    function state.head:GetNumBones() return 2 end
    assert(not probe.run(deps, "baseline", sample("baseline")).ok and state.set_calls == 0 and #state.exports == 0)
end)

test("unexpected source material replacement is reported without changing the player", function()
    local probe, deps, state, sample = fixture()
    local replacement = object(90, "MID Player.NewGeneration")
    state.on_export = function() state.player_head.materials[3] = replacement end
    local receipt = probe.run(deps, "baseline", sample("baseline"))
    assert(not receipt.ok and state.player_head.materials[3] == replacement and #receipt.restoration_failures == 1)
    assert_restored(state)
end)

test("camera changes during native export reject its earlier requested-view evidence", function()
    local probe, deps, state, sample = fixture()
    state.on_export = function() state.capture.FOVAngle = 15 end
    local receipt = probe.run(deps, "baseline", sample("baseline"))
    assert(not receipt.ok and receipt.reason:find("settings changed during export", 1, true))
    assert_restored(state)
end)

test("receiver change during first material setter blocks further borrowed writes", function()
    local probe, deps, state, sample = fixture()
    local original_setter = state.head.SetMaterial
    function state.head:SetMaterial(slot, material)
        original_setter(self, slot, material)
        if slot == 3 and material == state.player_head.materials[3] then state.capture_owner = state.player end
    end
    local receipt = probe.run(deps, "baseline", sample("baseline"))
    assert(not receipt.ok and #state.exports == 0 and state.set_calls == 2)
    assert(state.head.materials[3] == state.original_left and state.head.materials[4] == state.original_right)
end)

print("PASS " .. count .. " inventory iris capture test groups")
