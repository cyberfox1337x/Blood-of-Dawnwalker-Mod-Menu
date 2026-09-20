local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_private_eye_renderer_v13_tests")
local path = assert(arg[1], "Pass the private-preview module path")
package.path = path:match("^(.*[/\\])") .. "?.lua;" .. package.path

local function object(address, name)
    local value = { address = address, name = name, valid = true }
    function value:IsValid() return self.valid end
    function value:IsA() return true end
    function value:GetAddress() return self.address end
    function value:GetFullName() return self.name end
    return value
end

local function identity_transform(z)
    return { Translation = { X = 10, Y = 20, Z = z }, Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
end

local function fixture()
    local appearance = {}
    package.loaded["DawnwalkerAppearanceSourcesV9"] = appearance
    local probe = assert(dofile(path))
    local world, player = object(1, "World World"), object(2, "Player World.Player")
    local state = { time = 1000, files = {}, game_thread = true, setters_on_player = 0, created = 0, components = {}, exports = {}, released = 0, inventory = {} }
    player.Form = 0
    function player:GetWorld() return world end
    function player:IsInWolfForm() return false end
    function player:K2_GetActorLocation() return { X = 10, Y = 20, Z = 30 } end
    function player:K2_GetActorRotation() return { pitch = 0, Yaw = 0, Roll = 0 } end
    function player:GetActorForwardVector() return { X = 1, Y = 0, Z = 0 } end
    for index, field in ipairs({ "HeadMesh", "HairMesh", "TorsoMesh" }) do
        local mesh, asset, material = object(10 + index, "Mesh Player." .. field), object(20 + index, "SkeletalMesh /Game/Actual." .. field), object(30 + index, "Material /Game/Actual." .. field)
        mesh.asset, mesh.material = asset, material
        function asset:GetBounds() return { Origin = { X = 0, Y = 0, Z = 160 }, BoxExtent = { X = 12, Y = 12, Z = 20 }, SphereRadius = 20 } end
        function mesh:GetOwner() return player end
        function mesh:GetSkeletalMeshAsset() return self.asset end
        function mesh:GetNumMaterials() return 1 end
        function mesh:GetMaterial(slot) assert(slot == 0); return self.material end
        function mesh:K2_GetComponentToWorld() return identity_transform(30) end
        local bones = { "root", "Head", "FACIAL_L_Eye", "FACIAL_R_Eye", "neck_01" }
        function mesh:GetNumBones() return #bones end
        function mesh:GetBoneName(index) return { ToString = function() return bones[index + 1] end } end
        function mesh:DoesSocketExist() return true end
        function mesh:GetSocketLocation(bone)
            if bone:ToString() == "FACIAL_L_Eye" then return { X = 18, Y = 17, Z = 197 } end
            if bone:ToString() == "FACIAL_R_Eye" then return { X = 18, Y = 23, Z = 197 } end
            return { X = 10, Y = 20, Z = 190 }
        end
        player[field] = mesh
    end
    local actor, capture = object(100, "SceneCapture2D World.Private"), object(101, "Capture Private.Capture")
    actor.CaptureComponent2D = capture
    capture.PostProcessSettings = { bOverride_AutoExposureMethod = false, bOverride_AutoExposureBias = false,
        bOverride_AutoExposureApplyPhysicalCameraExposure = false, AutoExposureApplyPhysicalCameraExposure = true,
        AutoExposureMethod = 0, AutoExposureBias = 1 }
    function capture:SetShowFlagSettings(settings) self.show_flags = settings end
    function capture:GetShowFlagSettings() return self.show_flags or {} end
    function actor:GetWorld() return world end
    function actor:SetActorEnableCollision(enabled) assert(enabled == false) end
    function actor:IsActorBeingDestroyed() return self.destroying == true end
    function actor:K2_DestroyActor()
        if not state.spawn_finished then return end
        self.destroying = true; state.destroy_calls = (state.destroy_calls or 0) + 1
    end
    function capture:GetOwner() return actor end
    function capture:ClearShowOnlyComponents() self.shown = {} end
    function capture:ShowOnlyComponent(mesh) self.shown[#self.shown + 1] = mesh end
    function capture:K2_SetWorldLocationAndRotation(location, look_at) self.location, self.rotation = location, look_at end
    function capture:K2_GetComponentLocation() return self.location end
    function capture:K2_GetComponentRotation() return self.rotation end
    function capture:CaptureScene() state.capture_calls = (state.capture_calls or 0) + 1 end
    function actor:AddComponentByClass(class)
        local component = object(200 + #state.components, "Component Private." .. (#state.components + 1))
        function component:GetOwner() return actor end
        function component:SetCollisionEnabled(value) self.collision = value end
        function component:GetCollisionEnabled() return self.collision end
        function component:SetGenerateOverlapEvents() end
        function component:SetVisibleInSceneCaptureOnly(value) self.bVisibleInSceneCaptureOnly = value end
        function component:SetHiddenInSceneCapture(value) self.bHiddenInSceneCapture = value end
        function component:SetCastShadow() end
        function component:SetAffectDynamicIndirectLighting() end
        function component:SetAffectDistanceFieldLighting() end
        function component:SetVisibleInRayTracing() end
        function component:SetLightingChannels(channel0, channel1, channel2) self.LightingChannels = { bChannel0 = channel0, bChannel1 = channel1, bChannel2 = channel2 } end
        function component:SetSkeletalMeshAsset(asset) self.asset = asset end
        function component:GetSkeletalMeshAsset() return self.asset end
        function component:SetMaterial(index, material) self.materials = self.materials or {}; self.materials[index] = material end
        function component:GetMaterial(slot) return self.materials[slot] end
        function component:GetNumMaterials()
            if self.asset then return self.asset.material_count or 1 end
            local count = 0; for _ in pairs(self.materials or {}) do count = count + 1 end; return count
        end
        function component:CreateDynamicMaterialInstance(slot, parent, native_name)
            local mid = object(700 + slot, "MaterialInstanceDynamic Private.Head." .. native_name:ToString())
            mid.Parent, mid.values = parent, {}
            function mid:GetOuter() return component end
            function mid:SetScalarParameterValueByInfo(info, value) self.values[info.name] = value end
            function mid:K2_GetScalarParameterValueByInfo(info) return self.values[info.name] end
            component:SetMaterial(slot, mid)
            if state.on_mid then return state.on_mid(component, mid, slot) end
            return mid
        end
        function component:K2_GetComponentToWorld() return self.transform end
        function component:SetStaticMesh(asset) self.StaticMesh = asset; return true end
        function component:K2_AttachToComponent(parent, socket, location_rule, rotation_rule, scale_rule, weld)
            assert(location_rule == 1 and rotation_rule == 1 and scale_rule == 1 and not weld)
            self.parent, self.socket = parent, socket; return true
        end
        function component:GetAttachParent() return self.parent end
        function component:SetGroomAsset(asset) self.GroomAsset = asset end
        component.bEnableSimulation, component.bUseAttachedParentAsPoseComponent, component.bBindToLeaderComponent = true, false, true
        function component:SetClothAsset(asset) self.cloth_asset = asset end
        function component:GetClothAsset() return self.cloth_asset end
        function component:IsSimulationEnabled() return self.bEnableSimulation end
        component.SimulationSettings = { bOverrideSettings = false, SolverSettings = { bEnableSimulation = true } }
        function component:SetEnableSimulation(enabled) self.SimulationSettings.SolverSettings.bEnableSimulation = enabled; self.bEnableSimulation = enabled end
        function component:SetBindingAsset(binding) self.BindingAsset = binding end
        function component:SetLeaderPoseComponent(source, force, tick) assert(force and not tick); self.leader = source end
        function component:K2_SetWorldTransform(transform)
            local previous = self.transform
            self.transform = transform
            if state.propagate_attachments and previous then
                for _, child in ipairs(state.components) do
                    if child.parent == self and child.transform then
                        for _, axis in ipairs({ "X", "Y", "Z" }) do
                            child.transform.Translation[axis] = child.transform.Translation[axis] + transform.Translation[axis] - previous.Translation[axis]
                        end
                    end
                end
            end
            if state.on_transform then state.on_transform(self) end
        end
        function component:SetCastShadows(value) assert(not value) end
        function component:SetLightColor(color, srgb) assert(color.R == 1 and color.G == 1 and color.B == 1 and not srgb); self.LightColor = { R = 255, G = 255, B = 255 } end
        function component:SetUseTemperature(enabled) self.bUseTemperature = enabled end
        function component:SetIndirectLightingIntensity(intensity) self.IndirectLightingIntensity = intensity end
        function component:SetVolumetricScatteringIntensity(intensity) self.VolumetricScatteringIntensity = intensity end
        function component:SetIntensityUnits(value) assert(value == 1); self.IntensityUnits = value end
        function component:SetIntensity(value) assert(value == 20); self.Intensity = value end
        function component:SetAttenuationRadius(value) assert(value == 800) end
        function component:K2_SetWorldLocation(location) self.location = location end
        state.components[#state.components + 1] = component
        if state.on_add then state.on_add(component, class) end
        return component
    end
    function actor:FinishAddComponent() end
    local target = object(102, "TextureRenderTarget2D /Engine/Transient.PrivateRT")
    function target:GetOuter() return world end
    target.SizeX, target.SizeY, target.RenderTargetFormat, target.bForceLinearGamma, target.TargetGamma = 1024, 1024, 2, true, 0
    local render, gameplay, math_library = object(300, "Library Render"), object(301, "Library Gameplay"), object(302, "Library Math")
    function render:CreateRenderTarget2D(context, width, height, format)
        assert(context == world and width == 1024 and height == 1024 and format == 2)
        assert(state.spawn_finished, "Target allocation must follow native actor finalization")
        state.target_created = true
        return target
    end
    function render:ReleaseRenderTarget2D(render_target) assert(render_target == target); state.released = state.released + 1 end
    function render:ExportRenderTarget(context, render_target, directory, filename)
        assert(context == world and render_target == target)
        state.exports[#state.exports + 1] = { directory = directory, filename = filename }
        state.files[directory .. "/" .. filename] = true
        if state.on_export then state.on_export(#state.exports) end
        if state.export_error then error(state.export_error) end
    end
    function gameplay:BeginDeferredActorSpawnFromClass(context, class, transform, collision, owner, scale)
        assert(context == world and class.name == "/Script/Engine.SceneCapture2D" and collision == 1 and owner == nil and scale == 0)
        assert(transform.Translation.Z == 100030)
        state.created = state.created + 1
        return actor
    end
    function gameplay:FinishSpawningActor(created_actor)
        assert(created_actor == actor)
        state.finish_calls = (state.finish_calls or 0) + 1
        if state.finish_error then error(state.finish_error) end
        state.spawn_finished = true
        if state.on_finish then state.on_finish() end
        return actor
    end
    function gameplay:GetRealTimeSeconds(context)
        assert(context == world)
        return state.native_time_seconds or 12.5
    end
    function math_library:FindLookAtRotation() return { pitch = -2, Yaw = 180, Roll = 0 } end
    function math_library:TransformLocation(transform, location)
        return { X = transform.Translation.X + location.X, Y = transform.Translation.Y + location.Y, Z = transform.Translation.Z + location.Z }
    end
    local deps = { game_thread = true, intent = "eye-private-preview-session", nonce = string.rep("a", 32), boot_id = "1788665589-157248",
        identity = { build_id = "25129649", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853" },
        get_player = function() return player end, find_all_of = function(class)
            if class == "SceneCapture2D" then return state.existing_actor and { actor } or {} end
            if class == "TextureRenderTarget2D" then return state.existing_target and { target } or {} end
            assert(class == "InventoryRenderDoll")
            return state.inventory
        end,
        static_find_object = function(name)
            if name == "/Script/Engine.Default__KismetRenderingLibrary" then return render end
            if name == "/Script/Engine.Default__GameplayStatics" then return gameplay end
            if name == "/Script/Engine.Default__KismetMathLibrary" then return math_library end
            if name == "/Script/Engine.KismetSystemLibrary:IsValid" then
                return setmetatable(object(450, "Function Engine.KismetSystemLibrary:IsValid"), { __call = function(_, library, receiver)
                    assert(library ~= nil and receiver == actor)
                    return state.native_destroy_invalid == true and not actor.destroying or state.native_destroy_invalid ~= true
                end })
            end
            if name:sub(1, 8) == "/Script/" then return object(400, name) end; return nil
        end,
        output_exists = function(name) return state.files[name] == true end, monotonic_ms = function() return state.time end, is_in_game_thread = function() return state.game_thread end,
        output_directory = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-frames/1788665589-157248",
        pivot_bone_name = "Head" }
    local function plain(object) return { address = tostring(object:GetAddress()), name = object:GetFullName() } end
    state.appearance_sources = {}
    for _, field in ipairs({ "HeadMesh", "HairMesh", "TorsoMesh" }) do
        local mesh = player[field]
        state.appearance_sources[#state.appearance_sources + 1] = { component = mesh, owner = player, asset = mesh.asset,
            material_refs = { mesh.material }, record = { component = plain(mesh), owner = plain(player), asset = plain(mesh.asset),
                kind = "skeletal", visible = true, hidden_in_game = false, owner_hidden = false,
                world_transform = mesh:K2_GetComponentToWorld(), relative_transform = identity_transform(0), materials = { { slot = 0, material = plain(mesh.material) } } } }
    end
    function appearance.run(dependencies)
        assert(dependencies.game_thread == true)
        if state.appearance_failure then return { ok = false, reason = "Unsupported appearance enumeration" } end
        local report = { sources = {}, discovery_complete = true, unsupported_visible_sources = state.unsupported_visible == true }
        for _, entry in ipairs(state.appearance_sources) do
            if entry.component.K2_GetComponentToWorld then entry.record.world_transform = entry.component:K2_GetComponentToWorld() end
            if entry.component.GetMaterial then
                entry.material_refs, entry.record.materials = {}, {}
                for slot = 0, entry.component:GetNumMaterials() - 1 do
                    local material = entry.component:GetMaterial(slot)
                    entry.material_refs[slot + 1] = material
                    entry.record.materials[slot + 1] = { slot = slot, material = plain(material) }
                end
            end
            local function plain_copy(value)
                if type(value) ~= "table" then return value end
                local result = {}; for key, child in pairs(value) do result[key] = plain_copy(child) end; return result
            end
            report.sources[#report.sources + 1] = plain_copy(entry.record)
        end
        return { ok = true, report = report, snapshot = { sources = state.appearance_sources, head = player.HeadMesh, report = report } }
    end
    function appearance.verify() return not state.appearance_changed, "actual appearance changed" end
    function state.add_source(kind, hidden)
        local address = 700 + #state.appearance_sources * 3
        local component, asset, material = object(address, "Actual." .. kind .. "Component"), object(address + 1, "Asset.Actual." .. kind), object(address + 2, "Material.Actual." .. kind)
        local entry = { component = component, owner = player, asset = asset, material_refs = { material },
            record = { kind = kind, component = plain(component), owner = plain(player), asset = plain(asset),
                visible = true, hidden_in_game = hidden == true, owner_hidden = false, world_transform = identity_transform(30), relative_transform = identity_transform(0),
                materials = { { slot = 0, material = plain(material) } } } }
        function component:K2_GetComponentToWorld() return entry.record.world_transform end
        if kind == "chaos-cloth" then
            entry.attach_parent = player.TorsoMesh
            entry.native_attach_socket = { ToString = function() return "None" end }
            entry.record.cloth = { geometry_scale = 1, simulation_enabled = true }
        end
        if kind == "groom" then
            local binding = object(address + 3, "GroomBinding.Actual")
            binding.Groom, binding.TargetSkeletalMesh = asset, player.HeadMesh.asset
            function binding:GetTargetSkeletalMesh() return self.TargetSkeletalMesh end
            entry.binding_asset, entry.attach_parent = binding, player.HeadMesh
            entry.native_attach_socket = { ToString = function() return "None" end }
            entry.record.binding_asset, entry.record.groom_cache = plain(binding), { present = false }
            entry.record.bUseCards, entry.record.AttachmentName = false, "HeadMesh"
            entry.record.groups = { { HairWidth = 0.01, HairWidth_Override = true, HairLengthScale = 1, HairLengthScale_Override = false } }
        end
        state.appearance_sources[#state.appearance_sources + 1] = entry
        return entry
    end
    state.player, state.world, state.actor, state.capture, state.target, state.render = player, world, actor, capture, target, render
    return probe, deps, state
end

local function duplicate(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = duplicate(child) end
    return result
end

local function prepared()
    local module, deps, state = fixture()
    local head, bindings = state.player.HeadMesh, {}
    head.materials = { [0] = head.material, [1] = head.material, [2] = head.material }
    head.asset.material_count = 5
    function head:GetNumMaterials() return 5 end
    function head:GetMaterial(slot) return self.materials[slot] end
    state.settings = { schemaId = "actual-human-uv", values = {} }
    for _, slot in ipairs({ 3, 4 }) do
        local material = object(40 + slot, "MaterialInstanceConstant /Game/Actual.Eye" .. slot)
        local binding = { slot = slot, slot_name = "eye" .. slot, native_name = { ToString = function() return "eye" .. slot end },
            original_material = material, original_identity = { name = material.name, address = tostring(material.address) },
            current_material = material, current_identity = { name = material.name, address = tostring(material.address) }, parameters = {} }
        for _, name in ipairs({ "IrisColorU", "IrisColorV", "SecondaryIrisColorU", "SecondaryIrisColorV" }) do
            local parameter = { slotId = "head:" .. slot, materialId = "original-eye" .. slot, name = name, association = 2, index = -1 }
            binding.parameters[#binding.parameters + 1] = { name = name, native_info = { name = name }, parameter = parameter, min = 0.2, max = 0.8, tolerance = 0.000001 }
            state.settings.values[#state.settings.values + 1] = { parameter = duplicate(parameter), value = { kind = "scalar", value = 0.4 } }
        end
        bindings[#bindings + 1], head.materials[slot] = binding, material
    end
    local snapshot = { identity_key = "native-human-generation-1", baseline_id = "human-baseline-1", schema_id = "actual-human-uv",
        current_settings = duplicate(state.settings), bindings = bindings }
    deps.eye_bindings = {
        inspect = function(player, current_head)
            assert(player == state.player and current_head == head and player.Form == 0, "Native context changed")
            for _, binding in ipairs(bindings) do
                local actual = head:GetMaterial(binding.slot)
                assert(actual == binding.original_material or actual == binding.current_material, "Foreign live material binding")
            end
            return snapshot
        end,
        validate_settings = function(settings, expected)
            assert(expected.baseline_id == snapshot.baseline_id and settings.schemaId == state.settings.schemaId and #settings.values == 8)
            for index, entry in ipairs(settings.values) do
                assert(entry.parameter.name == state.settings.values[index].parameter.name and entry.parameter.slotId == state.settings.values[index].parameter.slotId)
                assert(entry.value.kind == "scalar" and entry.value.value >= 0.2 and entry.value.value <= 0.8)
            end
            return duplicate(settings)
        end,
    }
    function deps.eye_bindings.verify(expected, player, current_head)
        assert(expected.baseline_id == snapshot.baseline_id)
        deps.eye_bindings.inspect(player, current_head)
        return true
    end
    state.bindings = bindings
    local renderer = module.new(deps)
    return renderer, deps, state
end

local function request(state, revision)
    return { owner_id = "menu", lease_id = "lease", identity_key = "native-human-generation-1",
        eye_revision = revision or 0, view_revision = revision or 0,
        view = { framing = "head-and-shoulders", yawDegrees = 0, zoom = 1 }, settings = duplicate(state.settings) }
end

local function opened()
    local renderer, deps, state = prepared()
    local handle = renderer.adapters.create_preview("native-human-generation-1")
    return renderer, deps, state, handle
end

local function frame(renderer, state, handle, sequence, desired)
    desired = desired or request(state)
    local readback = renderer.adapters.update_preview(handle, desired)
    assert(renderer.adapters.validate_readback(readback, desired, handle))
    local evidence = renderer.adapters.capture_preview(handle, readback, sequence)
    assert(renderer.adapters.validate_capture_evidence(evidence, readback, sequence, handle))
    return evidence
end

local count = 0
local function test(name, action) action(); count = count + 1; print("PASS " .. name) end

test("factory stays inert until open and owns separate preview eye MIDs", function()
    local renderer, _, state = prepared()
    assert(state.created == 0 and #state.exports == 0)
    local handle = renderer.adapters.create_preview("native-human-generation-1")
    assert(state.created == 1 and #state.components == 5 and state.released == 0)
    for _, binding in ipairs(state.bindings) do
        local preview = state.components[1]:GetMaterial(binding.slot)
        assert(preview ~= state.player.HeadMesh:GetMaterial(binding.slot) and preview.Parent == binding.original_material)
        assert(preview:GetOuter() == state.components[1])
    end
    assert(renderer.adapters.verify_private_preview(handle, "native-human-generation-1"))
end)

test("persistent actual updates export evidence without claiming a capture timestamp", function()
    local renderer, _, state, handle = opened()
    local evidence = frame(renderer, state, handle, 1)
    assert(evidence.sequence == 1 and evidence.view_revision == 0 and evidence.eye_revision == 0)
    assert(evidence.capture_timestamp_known == false and evidence.frame_verified == false and evidence.capturedAtMs == nil)
    assert(evidence.native_clock_id == "ue-gameplay-real-time-seconds:1788665589-157248:1")
    assert(evidence.export_call_started_monotonic_ms == 12500 and evidence.export_call_completed_monotonic_ms == 12500)
    assert(evidence.export_call_started_monotonic_ms ~= state.time)
    assert(evidence.file_name == "eye-live-" .. string.rep("a", 32) .. "-0001.png" and #state.exports == 1)
    assert(evidence.settings.values[1].value.value == state.components[1]:GetMaterial(3).values.IrisColorU)
    assert(state.player.HeadMesh:GetMaterial(3) == state.bindings[1].original_material)
end)

test("known live MID transition preserves baseline and preview original MIC parent", function()
    local renderer, _, state, handle = opened()
    frame(renderer, state, handle, 1)
    for _, binding in ipairs(state.bindings) do
        local live = object(900 + binding.slot, "LiveMID Player.Eye" .. binding.slot)
        binding.current_material = live
        binding.current_identity = { name = live.name, address = tostring(live.address) }
        state.player.HeadMesh.materials[binding.slot] = live
    end
    assert(renderer.adapters.verify_private_preview(handle, "native-human-generation-1"))
    local desired = request(state, 1)
    desired.settings.values[1].value.value = 0.6
    local evidence = frame(renderer, state, handle, 2, desired)
    assert(evidence.baseline_id == "human-baseline-1")
    assert(state.components[1]:GetMaterial(3).Parent == state.bindings[1].original_material)
    assert(state.player.HeadMesh:GetMaterial(3) == state.bindings[1].current_material)
end)

test("foreign source material replacement is rejected and never overwritten", function()
    local renderer, _, state, handle = opened()
    local foreign = object(999, "ForeignMID Player.Eye")
    state.player.HeadMesh.materials[3] = foreign
    assert(not pcall(renderer.adapters.update_preview, handle, request(state)))
    assert(#state.exports == 0 and state.player.HeadMesh:GetMaterial(3) == foreign)
    assert(renderer.adapters.release_preview(handle).owned_cleanup_acknowledged)
    assert(state.player.HeadMesh:GetMaterial(3) == foreign)
end)

test("two outstanding files apply backpressure until the exact host removal is acknowledged", function()
    local renderer, deps, state, handle = opened()
    local first = frame(renderer, state, handle, 1)
    frame(renderer, state, handle, 2)
    assert(not renderer.adapters.can_capture(handle))
    assert(not pcall(renderer.acknowledge, 1, first.file_name))
    assert(not pcall(renderer.acknowledge, 1, "unknown.png"))
    state.files[deps.output_directory .. "/" .. first.file_name] = nil
    assert(renderer.acknowledge(1, first.file_name) and renderer.adapters.can_capture(handle))
    frame(renderer, state, handle, 3)
    assert(#state.exports == 3 and not renderer.adapters.can_capture(handle))
end)

test("ordinary player movement refreshes clone pose and keeps the actual player untouched", function()
    local renderer, _, state, handle = opened()
    frame(renderer, state, handle, 1)
    function state.player:K2_GetActorLocation() return { X = 110, Y = 20, Z = 30 } end
    function state.player.HeadMesh:K2_GetComponentToWorld() local value = identity_transform(30); value.Translation.X = 110; return value end
    function state.player.HeadMesh:GetSocketLocation(bone)
        local name = bone:ToString()
        return { X = name == "Head" and 110 or 118, Y = name == "FACIAL_L_Eye" and 17 or name == "FACIAL_R_Eye" and 23 or 20, Z = name == "Head" and 190 or 197 }
    end
    local evidence = frame(renderer, state, handle, 2)
    assert(state.components[1].transform.Translation.X == 110 and evidence.camera_location.X > 110)
    assert(state.player:K2_GetActorLocation().X == 110 and state.setters_on_player == 0)
end)

test("yaw endpoints and close-up work while invalid camera bounds reject before export", function()
    local renderer, _, state, handle = opened()
    for _, yaw in ipairs({ -69, 69 }) do
        local desired = request(state)
        desired.view.yawDegrees = yaw
        desired.view.framing = "eyes-close-up"
        assert(renderer.adapters.update_preview(handle, desired).view.yawDegrees == yaw)
    end
    for _, view in ipairs({ { framing = "head-and-shoulders", yawDegrees = 70, zoom = 1 },
        { framing = "eyes-close-up", yawDegrees = 0, zoom = 100 }, { framing = "unsupported", yawDegrees = 0, zoom = 1 } }) do
        local desired = request(state)
        desired.view = view
        assert(not pcall(renderer.adapters.update_preview, handle, desired))
    end
    assert(#state.exports == 0)
end)

test("post-export camera replacement prevents accepting evidence", function()
    local renderer, _, state, handle = opened()
    state.on_export = function() state.capture.FOVAngle = 55 end
    assert(not pcall(frame, renderer, state, handle, 1))
    assert(#state.exports == 1 and renderer.adapters.release_preview(handle).owned_cleanup_acknowledged)
end)

test("private material reparenting prevents setters and never writes its new parent", function()
    local renderer, _, state, handle = opened()
    state.components[1]:GetMaterial(3).Parent = state.player.HeadMesh.material
    assert(not pcall(renderer.adapters.update_preview, handle, request(state)))
    assert(#state.exports == 0)
end)

test("native scalar getter mismatch prevents capture", function()
    local renderer, _, state, handle = opened()
    state.components[1].materials[3].K2_GetScalarParameterValueByInfo = function() return 0.9 end
    assert(not pcall(renderer.adapters.update_preview, handle, request(state)))
    assert(#state.exports == 0)
end)

test("cleanup is paired and idempotent while keeping player baseline intact", function()
    local renderer, _, state, handle = opened()
    frame(renderer, state, handle, 1)
    local receipt = renderer.adapters.release_preview(handle)
    assert(receipt.owned_cleanup_acknowledged and receipt.destruction_pending and not receipt.actor_invalidated)
    assert(receipt.target_release_requested and state.released == 1 and state.capture.TextureTarget == nil)
    assert(renderer.adapters.release_preview(handle) == receipt and state.released == 1 and state.destroy_calls == 1)
    assert(not pcall(renderer.adapters.update_preview, handle, request(state)))
    assert(state.player.HeadMesh:GetMaterial(3) == state.bindings[1].original_material)
end)

test("new world-outer target with Game path is accepted; wrong dimensions are still released", function()
    for _, wrong in ipairs({ false, true }) do
        local renderer, _, state = prepared()
        state.target.name = "TextureRenderTarget2D /Game/World.PrivateTransientTarget"
        if wrong then state.target.SizeX = 512 end
        local ok, handle = pcall(renderer.adapters.create_preview, "native-human-generation-1")
        if wrong then
            assert(not ok and state.released == 1 and state.destroy_calls == 1)
            assert(renderer.inspect_cleanup().owned_cleanup_acknowledged)
        else assert(ok and renderer.adapters.release_preview(handle).owned_cleanup_acknowledged) end
    end
end)

test("construction capture replacement rejects allocation and protects foreign ownership", function()
    local renderer, _, state = prepared()
    state.on_finish = function() state.actor.CaptureComponent2D = object(888, "Capture Replaced") end
    assert(not pcall(renderer.adapters.create_preview, "native-human-generation-1") and not state.target_created)
    assert(state.destroy_calls == 1)
end)

test("factory aliases of existing resources are never released or destroyed", function()
    for _, scenario in ipairs({ "actor", "target", "mid" }) do
        local renderer, _, state = prepared()
        if scenario == "actor" then state.existing_actor = true
        elseif scenario == "target" then state.existing_target = true
        else state.on_mid = function() return state.bindings[1].original_material end end
        assert(not pcall(renderer.adapters.create_preview, "native-human-generation-1"))
        if scenario == "actor" then assert(not state.actor.destroying)
        elseif scenario == "target" then assert(state.released == 0)
        else assert(state.player.HeadMesh:GetMaterial(3) == state.bindings[1].original_material) end
        assert(#state.exports == 0)
    end
end)

test("game-thread loss and already-existing frame path reject native export", function()
    local renderer, deps, state, handle = opened()
    state.game_thread = false
    assert(not pcall(renderer.adapters.update_preview, handle, request(state)))
    state.game_thread = true
    state.files[deps.output_directory .. "/eye-live-" .. string.rep("a", 32) .. "-0001.png"] = true
    assert(not pcall(frame, renderer, state, handle, 1) and #state.exports == 0)
end)

test("failed export cleanup exposes only its exact bounded pending file ledger", function()
    local renderer, deps, state, handle = opened()
    state.export_error = "native export failed after partial file creation"
    assert(not pcall(frame, renderer, state, handle, 1))
    local receipt = renderer.adapters.release_preview(handle)
    assert(receipt.owned_cleanup_acknowledged and #receipt.pending_frames == 1)
    local pending = receipt.pending_frames[1]
    assert(pending.sequence == 1 and pending.file_name == state.exports[1].filename)
    assert(receipt.nonce == deps.nonce and receipt.boot_id == deps.boot_id)
    state.files[deps.output_directory .. "/" .. pending.file_name] = nil
    assert(renderer.acknowledge(pending.sequence, pending.file_name))
    assert(not pcall(renderer.acknowledge, pending.sequence, pending.file_name))
end)

test("latent cleanup can be observed later without retroactively claiming acknowledgement", function()
    local renderer, _, state, handle = opened()
    function state.actor:K2_DestroyActor() end
    local receipt = renderer.adapters.release_preview(handle)
    assert(not receipt.owned_cleanup_acknowledged and receipt.target_release_requested)
    state.actor.valid = false
    local observation = renderer.observe_cleanup()
    assert(observation.actor_state.actor_invalidated and observation.production_ready == false)
    assert(not renderer.inspect_cleanup().owned_cleanup_acknowledged)
end)

test("owned descriptor exposes actual geometry bounds as plain evidence without native wrappers", function()
    local renderer, _, state, handle = opened()
    local descriptor = renderer.describe()
    assert(descriptor.production_ready == false and descriptor.width == 1024 and descriptor.schema_id == "actual-human-uv")
    for _, framing in ipairs({ "head-and-shoulders", "eyes-close-up" }) do
        local bounds = descriptor.zoom_bounds[framing]
        assert(bounds.min > 0 and bounds.min < 1 and bounds.max > 1 and bounds.initial == 1 and bounds.step == nil)
        local desired = request(state)
        desired.view.framing, desired.view.zoom = framing, bounds.min
        assert(renderer.adapters.update_preview(handle, desired))
        desired.view.zoom = bounds.max
        assert(renderer.adapters.update_preview(handle, desired))
    end
    local function plain(value)
        assert(type(value) ~= "function" and type(value) ~= "userdata")
        if type(value) == "table" then assert(getmetatable(value) == nil); for _, child in pairs(value) do plain(child) end end
    end
    plain(descriptor)
    descriptor.actor.address = "foreign"
    assert(renderer.describe().actor.address == "100")
    renderer.adapters.release_preview(handle)
    assert(not pcall(renderer.describe))
end)

test("controller uses the real adapter contract for coalescing, backpressure and pending-file cleanup", function()
    local renderer, deps, state = prepared()
    local Session = require("DawnwalkerEyePreviewSession")
    local controller = Session.new(renderer.adapters)
    assert(controller:open(request(state)).status == "opened")
    local first = controller:step()
    assert(first.status == "captured-evidence" and first.production_ready == false)
    state.time = 1100
    assert(controller:step().status == "captured-evidence")
    state.time = 1200
    assert(controller:step().status == "waiting-for-frame-consumer" and #state.exports == 2)
    assert(controller:enqueue(request(state, 1)).status == "queued")
    assert(controller:enqueue(request(state, 2)).status == "queued")
    state.files[deps.output_directory .. "/" .. first.evidence.file_name] = nil
    renderer.acknowledge(1, first.evidence.file_name)
    local latest = controller:step()
    assert(latest.sequence == 3 and latest.evidence.eye_revision == 2)
    local closed = controller:close(request(state), "hidden")
    assert(closed.status == "closed" and #closed.cleanup.pending_frames == 2)
    assert(state.player.HeadMesh:GetMaterial(3) == state.bindings[1].original_material)
end)

test("native scalar quantization is retained in evidence rather than echoing requested doubles", function()
    local renderer, _, state, handle = opened()
    state.components[1].materials[3].SetScalarParameterValueByInfo = function(material, info, scalar)
        material.values[info.name] = math.floor(scalar * 1000000 + 0.5) / 1000000
    end
    local desired = request(state)
    desired.settings.values[1].value.value = 0.3333333
    local evidence = frame(renderer, state, handle, 1, desired)
    assert(evidence.settings.values[1].value.value == 0.333333)
    assert(evidence.settings.values[1].value.value ~= desired.settings.values[1].value.value)
end)

test("invalid or regressing native capture clock never substitutes the lease clock", function()
    for _, scenario in ipairs({ "negative", "regression" }) do
        local renderer, _, state, handle = opened()
        if scenario == "negative" then state.native_time_seconds = -1
        else state.native_time_seconds = 13; state.on_export = function() state.native_time_seconds = 12 end end
        assert(not pcall(frame, renderer, state, handle, 1))
        assert(#state.exports == (scenario == "negative" and 0 or 1))
        assert(renderer.adapters.release_preview(handle).owned_cleanup_acknowledged)
    end
end)

test("V8 descriptor and every frame preserve untouched native display defaults", function()
    local renderer, _, state, handle = opened()
    local descriptor = renderer.describe()
    assert(descriptor.capture_source == 9 and descriptor.render_target_format == 2 and descriptor.target_gamma == 0)
    assert(descriptor.force_linear_gamma and descriptor.display_configuration.configuration_verified)
    assert(descriptor.display_configuration.configuration_source == "native-factory-defaults")
    assert(descriptor.display_configuration.writes_performed == false and descriptor.display_configuration.write_ok == nil)
    assert(descriptor.display_configuration.gamma_before.value == 0 and descriptor.display_configuration.gamma_after.value == 0)
    local evidence = frame(renderer, state, handle, 1)
    assert(evidence.capture_source == 9 and evidence.render_target_format == 2 and evidence.target_gamma == 0 and evidence.force_linear_gamma)
    assert(evidence.rendering_profile.exposure_method.value == 2 and evidence.rendering_profile.exposure_bias.value == 0)
    assert(#evidence.rendering_profile.lights == 2 and evidence.rendering_profile.lights[1].intensity == 20)
    assert(evidence.rendering_profile.show_flags.Fog == false and evidence.rendering_profile.show_flags.ColorGrading == false)
end)

test("attached static clothing and groom get independent receivers and private skeletal parents", function()
    local renderer, _, state = prepared()
    local clothing = state.add_source("static")
    local groom = state.add_source("groom")
    local handle = renderer.adapters.create_preview("native-human-generation-1")
    assert(#state.components == 7 and #state.capture.shown == 5)
    assert(state.components[4].StaticMesh == clothing.asset and state.components[5].GroomAsset == groom.asset)
    assert(state.components[5]:GetAttachParent() == state.components[1])
    assert(state.components[5].SimulationSettings.SolverSettings.bEnableSimulation == false)
    local evidence = frame(renderer, state, handle, 1)
    assert(evidence.sequence == 1 and state.player.HeadMesh:GetMaterial(3) == state.bindings[1].original_material)
    assert(renderer.describe().source_meshes[5].kind == "groom")
end)

test("hidden appearance stays hidden in the private render list", function()
    local renderer, _, state = prepared()
    state.add_source("static", true)
    local handle = renderer.adapters.create_preview("native-human-generation-1")
    assert(#state.components == 6 and #state.capture.shown == 3)
    assert(state.components[4].bHiddenInSceneCapture == true)
    assert(frame(renderer, state, handle, 1).sequence == 1)
end)

test("equipment cohort visibility attachment and scale changes invalidate the current preview", function()
    for _, kind in ipairs({ "membership", "visibility", "attachment", "scale", "material" }) do
        local renderer, _, state = prepared()
        local garment = state.add_source("static")
        local handle = renderer.adapters.create_preview("native-human-generation-1")
        if kind == "membership" then state.add_source("static")
        elseif kind == "visibility" then garment.record.hidden_in_game = true
        elseif kind == "attachment" then garment.record.attach_parent = { address = "123", name = "Foreign.Attachment" }
        elseif kind == "scale" then garment.record.world_transform.Scale3D.X = 1.1
        else garment.record.materials[1].material = { address = "999", name = "Foreign.Material" } end
        assert(not pcall(renderer.adapters.update_preview, handle, request(state)), kind)
        assert(#state.exports == 0 and renderer.adapters.release_preview(handle).owned_cleanup_acknowledged)
    end
end)

test("ordinary attached component motion refreshes private transforms without changing the cohort", function()
    local renderer, _, state = prepared()
    local garment = state.add_source("static")
    local handle = renderer.adapters.create_preview("native-human-generation-1")
    garment.record.world_transform.Translation.X = 125
    garment.record.relative_transform.Translation.X = 115
    local evidence = frame(renderer, state, handle, 1)
    assert(evidence.sequence == 1 and state.components[4].transform.Translation.X == 125)
end)

test("existing committed live MID is never used as a private preview parent", function()
    local renderer, _, state = prepared()
    for _, binding in ipairs(state.bindings) do
        local live = object(950 + binding.slot, "LiveMID Existing.Eye" .. binding.slot)
        binding.current_material, binding.current_identity = live, { name = live.name, address = tostring(live.address) }
        state.player.HeadMesh.materials[binding.slot] = live
    end
    local handle = renderer.adapters.create_preview("native-human-generation-1")
    assert(frame(renderer, state, handle, 1).sequence == 1)
    for _, binding in ipairs(state.bindings) do
        assert(state.components[1]:GetMaterial(binding.slot).Parent == binding.original_material)
        assert(state.player.HeadMesh:GetMaterial(binding.slot) == binding.current_material)
    end
end)

test("unsupported visible geometry and active groom caches fail with bounded owned cleanup", function()
    for _, kind in ipairs({ "unsupported", "cache", "binding" }) do
        local renderer, _, state = prepared()
        if kind == "unsupported" then state.unsupported_visible = true
        else
            local groom = state.add_source("groom")
            if kind == "cache" then groom.record.groom_cache = { address = "998", name = "GroomCache Active" }
            else groom.binding_asset.TargetSkeletalMesh = object(999, "Foreign.SkeletalMesh") end
        end
        assert(not pcall(renderer.adapters.create_preview, "native-human-generation-1"))
        assert(#state.exports == 0)
        if kind == "unsupported" then assert(state.created == 0)
        else assert(state.released == 1 and renderer.inspect_cleanup().owned_cleanup_acknowledged) end
    end
end)

test("post-export lighting and groom corruption never becomes accepted evidence", function()
    for _, kind in ipairs({ "gamma", "flags", "lamp", "groom" }) do
        local renderer, _, state = prepared()
        state.add_source("groom")
        local handle = renderer.adapters.create_preview("native-human-generation-1")
        state.on_export = function()
            if kind == "gamma" then state.target.TargetGamma = 2.2
            elseif kind == "flags" then state.capture.show_flags[1].Enabled = true
            elseif kind == "lamp" then state.components[5].Intensity = 2000
            else state.components[4].SimulationSettings.SolverSettings.bEnableSimulation = true end
        end
        assert(not pcall(frame, renderer, state, handle, 1), kind)
        assert(#state.exports == 1 and renderer.adapters.release_preview(handle).owned_cleanup_acknowledged)
    end
end)

test("explicit native logical invalidity acknowledges destruction without invoking dead actor methods", function()
    local renderer, _, state, handle = opened()
    state.native_destroy_invalid = true
    function state.actor:IsActorBeingDestroyed() assert(not self.destroying, "Called after native logical invalidity"); return false end
    local receipt = renderer.adapters.release_preview(handle)
    assert(receipt.owned_cleanup_acknowledged and receipt.native_logically_invalid and not receipt.actor_invalidated)
    assert(receipt.actor_after_destroy.native_is_valid.value == false and receipt.actor_after_destroy.being_destroyed == nil)
    assert(receipt.cleanup_error == nil and receipt.release_error == nil and receipt.target_release_requested)
end)

test("Chaos garments use only private skeletal parents and disabled private simulation", function()
    local renderer, _, state = prepared()
    local cloth = state.add_source("chaos-cloth")
    local handle = renderer.adapters.create_preview("native-human-generation-1")
    local clone = state.components[4]
    assert(clone:GetClothAsset() == cloth.asset and clone:GetAttachParent() == state.components[3])
    assert(not clone:IsSimulationEnabled() and clone.bUseAttachedParentAsPoseComponent and not clone.bBindToLeaderComponent)
    assert(clone.BlendWeight == 0 and clone.ClothGeometryScale == 1)
    assert(frame(renderer, state, handle, 1).sequence == 1)
    assert(renderer.describe().source_meshes[4].kind == "chaos-cloth")
end)

test("attachment propagation during motion defers only clone transform equality until batch completion", function()
    local renderer, _, state = prepared()
    local groom, cloth = state.add_source("groom"), state.add_source("chaos-cloth")
    local handle = renderer.adapters.create_preview("native-human-generation-1")
    state.propagate_attachments = true
    for _, field in ipairs({ "HeadMesh", "TorsoMesh" }) do
        state.player[field].K2_GetComponentToWorld = function() local value = identity_transform(30); value.Translation.X = 50; return value end
    end
    groom.record.world_transform.Translation.X = 50
    cloth.record.world_transform.Translation.X = 50
    local evidence = frame(renderer, state, handle, 1)
    assert(evidence.sequence == 1 and state.components[4].transform.Translation.X == 50 and state.components[5].transform.Translation.X == 50)
end)

test("transform batch still rejects changed private bindings before the next component write", function()
    local renderer, _, state = prepared()
    state.add_source("groom")
    local handle = renderer.adapters.create_preview("native-human-generation-1")
    local writes = 0
    state.on_transform = function(component)
        writes = writes + 1
        if component == state.components[1] then state.components[4].materials[0] = object(999, "Foreign.Material") end
    end
    assert(not pcall(frame, renderer, state, handle, 1))
    assert(writes == 1 and #state.exports == 0 and renderer.adapters.release_preview(handle).owned_cleanup_acknowledged)
end)

test("non-appearance and empty geometry retain generation evidence without private receivers", function()
    local renderer, _, state = prepared()
    local widget, empty = state.add_source("unsupported"), state.add_source("skeletal")
    widget.record.classification, empty.record.classification = "non-appearance", "empty-geometry"
    empty.asset, empty.record.asset = nil, { present = false }
    local handle = renderer.adapters.create_preview("native-human-generation-1")
    assert(#state.components == 5 and frame(renderer, state, handle, 1).sequence == 1)
    empty.record.classification = "appearance"
    assert(not pcall(renderer.adapters.update_preview, handle, request(state)))
end)

test("changed Chaos simulation or parent cannot become a matching frame", function()
    for _, kind in ipairs({ "simulation", "binding", "parent", "scale" }) do
        local renderer, _, state = prepared()
        state.add_source("chaos-cloth")
        local handle = renderer.adapters.create_preview("native-human-generation-1")
        state.on_export = function()
            local clone = state.components[4]
            if kind == "simulation" then clone.bEnableSimulation = true
            elseif kind == "binding" then clone.bBindToLeaderComponent = true
            elseif kind == "parent" then clone.parent = state.player.TorsoMesh
            else clone.ClothGeometryScale = 100 end
        end
        assert(not pcall(frame, renderer, state, handle, 1), kind)
        assert(#state.exports == 1 and renderer.adapters.release_preview(handle).owned_cleanup_acknowledged)
    end
end)

test("full appearance sweeps stay at transaction boundaries instead of scaling with the private cohort", function()
    -- V9 ran a complete appearance/material/generation sweep for every scalar setter, every clone
    -- transform and every lamp, so its per-frame cost grew with the cohort: 36 inspections at four
    -- private clones and 39 at seven. V10 pinned the sweeps to nine fixed per-frame sites: ten
    -- inspections with the pose refresh. V11 removed the mid-step intermediates and the read-only
    -- eye_settings sweeps, leaving five inspections. V12 removes the remaining mid-step full sweep
    -- (the pre-scalar verification in update_preview) and guards each read-only scalar pass once
    -- per eye instead of once per parameter, leaving three full verifications (entry, before
    -- export, after export) plus the pose refresh = four inspections, still flat while the narrow
    -- receiver guards grow instead.
    local function observe(extra)
        local renderer, _, state = prepared()
        for _ = 1, extra do state.add_source("static") end
        local appearance = package.loaded["DawnwalkerAppearanceSourcesV9"]
        local inner, inspections = appearance.run, 0
        appearance.run = function(...) inspections = inspections + 1; return inner(...) end
        local handle = renderer.adapters.create_preview("native-human-generation-1")
        local opened_at, before = inspections, renderer.stage_diagnostics()
        local evidence = frame(renderer, state, handle, 1)
        local diagnostics = renderer.stage_diagnostics()
        assert(evidence.sequence == 1)
        return { clones = #state.components - 1, inspections = inspections - opened_at,
            guards = diagnostics.receiver_guards - before.receiver_guards,
            sweeps = diagnostics.full_verifications - before.full_verifications, diagnostics = diagnostics }
    end
    local small, large = observe(0), observe(3)
    assert(large.clones > small.clones, "the larger cohort must actually be larger")
    assert(small.inspections == 4 and large.inspections == 4, small.inspections .. " vs " .. large.inspections)
    assert(small.sweeps == 3 and large.sweeps == 3, small.sweeps .. " vs " .. large.sweeps)
    assert(large.guards > small.guards, "narrow receiver guards should absorb the extra clones")
    assert(small.diagnostics.renderer == "v12")
    assert(small.diagnostics.stages.update_preview.calls == 1 and small.diagnostics.stages.capture_preview.calls == 1)
    -- The three full verifications live exactly at the entry, pre-export and post-export sites;
    -- validate_readback's pinned cohort guard plus scalar pass performs none.
    assert(small.diagnostics.stages.update_preview.full_verifications == 1
        and small.diagnostics.stages.capture_preview.full_verifications == 2
        and small.diagnostics.stages.validate_readback.full_verifications == 0, "full sweep sites drifted")
end)

test("corruption between update and capture still stops before any export", function()
    local renderer, _, state, handle = opened()
    local desired = request(state)
    local readback = renderer.adapters.update_preview(handle, desired)
    assert(renderer.adapters.validate_readback(readback, desired, handle))
    -- The pinned cohort guard and the before-export full sweep must still catch a live eye slot
    -- replaced after validation, before CaptureScene/ExportRenderTarget can run.
    state.player.HeadMesh.materials[3] = object(997, "ForeignMID Player.Eye3")
    assert(not pcall(renderer.adapters.capture_preview, handle, readback, 1))
    assert(#state.exports == 0 and state.player.HeadMesh:GetMaterial(3).name == "ForeignMID Player.Eye3")
    assert(renderer.adapters.release_preview(handle).owned_cleanup_acknowledged)
end)

test("read-only scalar passes never re-run the appearance sweep", function()
    local renderer, _, state, handle = opened()
    local appearance = package.loaded["DawnwalkerAppearanceSourcesV9"]
    local inner, inspections = appearance.run, 0
    appearance.run = function(...) inspections = inspections + 1; return inner(...) end
    local desired = request(state)
    local readback = renderer.adapters.update_preview(handle, desired)
    local after_update = inspections
    assert(renderer.adapters.validate_readback(readback, desired, handle))
    assert(inspections == after_update, "validate_readback re-ran the appearance sweep")
    local evidence = renderer.adapters.capture_preview(handle, readback, 1)
    -- update_preview: the entry full and the pose refresh; capture_preview: two export fulls.
    -- The read-only eye_settings passes add nothing.
    assert(inspections == 4, "expected exactly four inspections, saw " .. inspections)
    assert(renderer.adapters.validate_capture_evidence(evidence, readback, 1, handle))
end)

test("a live eye slot replaced between scalar writes stops the pass before the next native write", function()
    local renderer, _, state, handle = opened()
    local preview_eye, writes = state.components[1]:GetMaterial(3), 0
    local inner = preview_eye.SetScalarParameterValueByInfo
    preview_eye.SetScalarParameterValueByInfo = function(material, info, scalar)
        writes = writes + 1
        inner(material, info, scalar)
        if writes == 1 then state.player.HeadMesh.materials[3] = object(997, "ForeignMID Player.Eye3") end
    end
    assert(not pcall(frame, renderer, state, handle, 1))
    assert(writes == 1 and #state.exports == 0)
    assert(renderer.adapters.release_preview(handle).owned_cleanup_acknowledged)
end)

test("a private eye instance reparented between scalar writes is rejected before the next write", function()
    local renderer, _, state, handle = opened()
    local preview_eye, writes = state.components[1]:GetMaterial(3), 0
    local inner = preview_eye.SetScalarParameterValueByInfo
    preview_eye.SetScalarParameterValueByInfo = function(material, info, scalar)
        writes = writes + 1
        inner(material, info, scalar)
        if writes == 1 then material.Parent = state.player.HeadMesh.material end
    end
    assert(not pcall(frame, renderer, state, handle, 1))
    assert(writes == 1 and #state.exports == 0)
end)

test("stage diagnostics stay bounded and never claim a captured or GPU timestamp", function()
    local renderer, _, state, handle = opened()
    frame(renderer, state, handle, 1)
    frame(renderer, state, handle, 2)
    local diagnostics = renderer.stage_diagnostics()
    assert(diagnostics.kind == "native-private-eye-renderer-stage-diagnostics" and #diagnostics.stage_order <= 16)
    assert(diagnostics.capturedAtMs == nil and diagnostics.gpu_completed_ms == nil and diagnostics.render_completed_ms == nil)
    local named = 0
    for _, name in ipairs(diagnostics.stage_order) do
        local entry = diagnostics.stages[name]
        named = named + 1
        assert(entry.name == name and entry.calls >= 1)
        assert(entry.full_verifications >= 0 and entry.receiver_guards >= 0)
        assert(entry.last_call_interval_ms >= 0 and entry.total_call_interval_ms >= entry.last_call_interval_ms)
    end
    assert(named == #diagnostics.stage_order and named >= 3)
    assert(diagnostics.stages.update_preview.calls == 2 and diagnostics.stages.capture_preview.calls == 2)
    -- Reported counts are cumulative accounting, never a claim that a frame was verified.
    local staged = 0
    for _, name in ipairs(diagnostics.stage_order) do staged = staged + diagnostics.stages[name].full_verifications end
    -- The three construction sweeps run before any stage is open and stay deliberately unattributed.
    assert(staged > 0 and diagnostics.full_verifications - staged == 3, diagnostics.full_verifications .. " vs " .. staged)
end)

print("Passed " .. count .. " private renderer V13 groups")
