local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_private_eye_preview_v8_probe_tests")
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
    package.loaded["DawnwalkerAppearanceSources"] = appearance
    local probe = assert(dofile(path))
    local world, player = object(1, "World World"), object(2, "Player World.Player")
    local state = { setters_on_player = 0, created = 0, components = {}, exports = {}, released = 0, inventory = {} }
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
        function component:GetNumMaterials() local count = 0; for _ in pairs(self.materials or {}) do count = count + 1 end; return count end
        function component:GetMaterial(index) return self.materials and self.materials[index] end
        function component:K2_GetComponentToWorld() return self.transform end
        function component:SetStaticMesh(asset) self.StaticMesh = asset; return true end
        function component:K2_AttachToComponent(parent, socket, location_rule, rotation_rule, scale_rule, weld)
            assert(location_rule == 1 and rotation_rule == 1 and scale_rule == 1 and not weld)
            self.parent, self.socket = parent, socket; return true
        end
        function component:GetAttachParent() return self.parent end
        function component:SetGroomAsset(asset) self.GroomAsset = asset end
        component.SimulationSettings = { bOverrideSettings = false, SolverSettings = { bEnableSimulation = true } }
        function component:SetEnableSimulation(enabled) self.SimulationSettings.SolverSettings.bEnableSimulation = enabled end
        function component:SetBindingAsset(binding) self.BindingAsset = binding end
        function component:SetLeaderPoseComponent(source, force, tick) assert(force and not tick); self.leader = source end
        function component:K2_SetWorldTransform(transform) self.transform = transform end
        function component:SetCastShadows(value) assert(not value) end
        function component:SetLightColor(color, srgb) assert(color.R == 1 and color.G == 1 and color.B == 1 and not srgb); self.LightColor = { R = 255, G = 255, B = 255 } end
        function component:SetUseTemperature(enabled) self.bUseTemperature = enabled end
        function component:SetIndirectLightingIntensity(intensity) self.IndirectLightingIntensity = intensity end
        function component:SetVolumetricScatteringIntensity(intensity) self.VolumetricScatteringIntensity = intensity end
        function component:SetIntensityUnits(value) assert(value == 1); self.IntensityUnits = value end
        function component:SetIntensity(value) assert(value >= 0 and value <= 2000); self.Intensity = value end
        function component:SetAttenuationRadius(value) assert(value == 800) end
        function component:K2_SetWorldLocation(location) self.location = location end
        state.components[#state.components + 1] = component
        if state.on_add then state.on_add(component, class) end
        return component
    end
    function actor:FinishAddComponent() end
    local target = object(102, "TextureRenderTarget2D /Engine/Transient.PrivateRT")
    local comparison = object(103, "TextureRenderTarget2D World.ComparisonRT")
    function comparison:GetOuter() return world end
    comparison.SizeX, comparison.SizeY, comparison.RenderTargetFormat, comparison.TargetGamma, comparison.bForceLinearGamma = 1024, 1024, 2, 0, true
    function target:GetOuter() return world end
    target.SizeX, target.SizeY, target.RenderTargetFormat, target.bForceLinearGamma, target.TargetGamma = 1024, 1024, 2, true, 0
    local render, gameplay, math_library = object(300, "Library Render"), object(301, "Library Gameplay"), object(302, "Library Math")
    function render:CreateRenderTarget2D(context, width, height, format)
        assert(context == world and width == 1024 and height == 1024 and (format == 3 or format == 2))
        assert(state.spawn_finished, "Target allocation must follow native actor finalization")
        state.target_created = true
        return target
    end
    function render:ReleaseRenderTarget2D(render_target)
        assert(render_target == target or render_target == comparison)
        state.released = state.released + 1
        if render_target == comparison then state.comparison_released = true end
    end
    function render:ExportRenderTarget(context, render_target, directory, filename)
        assert(context == world and (render_target == target or render_target == comparison))
        state.exports[#state.exports + 1] = { directory = directory, filename = filename }
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
    function math_library:FindLookAtRotation() return { pitch = -2, Yaw = 180, Roll = 0 } end
    function math_library:TransformLocation(transform, location)
        return { X = transform.Translation.X + location.X, Y = transform.Translation.Y + location.Y, Z = transform.Translation.Z + location.Z }
    end
    local deps = { game_thread = true, intent = "eye-private-preview-roundtrip", nonce = string.rep("a", 32), boot_id = "1788665589-157248",
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
            return object(400, name)
        end,
        output_exists = function() return false end, now = function() return 1788665700 end,
        output_directory = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-frames/1788665589-157248",
        pivot_bone_name = "Head" }
    local function plain(object) return { address = tostring(object:GetAddress()), name = object:GetFullName() } end
    state.appearance_sources = {}
    for _, field in ipairs({ "HeadMesh", "HairMesh", "TorsoMesh" }) do
        local mesh = player[field]
        state.appearance_sources[#state.appearance_sources + 1] = { component = mesh, owner = player, asset = mesh.asset,
            material_refs = { mesh.material }, record = { component = plain(mesh), owner = plain(player), asset = plain(mesh.asset),
                kind = "skeletal", visible = true, hidden_in_game = false, owner_hidden = false,
                world_transform = mesh:K2_GetComponentToWorld(), materials = { { slot = 0, material = plain(mesh.material) } } } }
    end
    function appearance.run()
        if state.appearance_failure then return { ok = false, reason = "Unsupported appearance enumeration" } end
        local report = { sources = {}, unsupported_visible_sources = state.unsupported_visible == true }
        for _, entry in ipairs(state.appearance_sources) do report.sources[#report.sources + 1] = entry.record end
        return { ok = true, report = report, snapshot = { sources = state.appearance_sources, head = player.HeadMesh, report = report } }
    end
    function appearance.verify() return not state.appearance_changed, "actual appearance changed" end
    function state.add_source(kind, hidden)
        local address = 700 + #state.appearance_sources * 3
        local component, asset, material = object(address, "Actual." .. kind .. "Component"), object(address + 1, "Asset.Actual." .. kind), object(address + 2, "Material.Actual." .. kind)
        local entry = { component = component, owner = player, asset = asset, material_refs = { material },
            record = { kind = kind, component = plain(component), owner = plain(player), asset = plain(asset),
                visible = true, hidden_in_game = hidden == true, owner_hidden = false, world_transform = identity_transform(30),
                materials = { { slot = 0, material = plain(material) } } } }
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
    state.player, state.world, state.actor, state.capture, state.target, state.render, state.comparison = player, world, actor, capture, target, render, comparison
    return probe, deps, state
end

local count = 0
local function test(name, action) action(); count = count + 1; print("PASS " .. name) end

test("nine owned views use the actual readable inventory color profile and tighter geometry", function()
    local probe, deps, state = fixture()
    local receipt = probe.run(deps)
    assert(receipt.ok, receipt.reason or receipt.cleanup_error)
    assert(receipt.schema == 4 and #receipt.frames == 9 and receipt.capture_requests == 9 and state.released == 1)
    assert(receipt.capture_source == 9 and receipt.render_target_format == 2 and receipt.target_gamma == 0)
    assert(receipt.target_released and receipt.destruction_acknowledged and not receipt.preview_verified)
    assert(#receipt.preview_components == 3 and #receipt.preview_components_after == 3)
    for _, frame in ipairs(receipt.frames) do
        assert(frame.profile.capture_source == 9 and frame.profile.phase == "isolated-inventory-color")
        assert(frame.profile.lights[1].intensity == 20 and frame.target_gamma == 0 and frame.force_linear_gamma == true)
        assert(frame.component_readback_after_export == true)
    end
    assert(receipt.frames[2].yaw_degrees == -69 and receipt.frames[3].yaw_degrees == 69)
    assert(receipt.frames[1].camera_distance < 125 and receipt.frames[4].framing == "eyes-close-up")
end)

test("dynamically enumerated clothing static accessories and bound groom get separate actual-asset clones", function()
    local probe, deps, state = fixture()
    local clothing, accessory, groom = state.add_source("skeletal"), state.add_source("static"), state.add_source("groom")
    local receipt = probe.run(deps)
    assert(receipt.ok, receipt.reason)
    assert(#receipt.preview_components == 6 and #state.capture.shown == 6 and #state.components == 8)
    local seen = {}
    for _, clone in ipairs(receipt.preview_components_after) do seen[clone.source.address] = clone end
    assert(seen[clothing.record.component.address].asset.address == clothing.record.asset.address)
    assert(seen[accessory.record.component.address].kind == "static")
    assert(seen[groom.record.component.address].kind == "groom" and seen[groom.record.component.address].simulation_disabled)
    assert(seen[groom.record.component.address].groom_groups[1].HairWidth == 0.01)
    assert(state.capture.TextureTarget == nil and state.released == 1)
end)

test("hidden skeletal parents remain private pose dependencies without appearing in capture show-list", function()
    local probe, deps, state = fixture()
    state.appearance_sources[1].record.hidden_in_game = true
    state.add_source("groom")
    local receipt = probe.run(deps)
    assert(receipt.ok and #receipt.preview_components == 4 and #state.capture.shown == 3)
    assert(receipt.preview_components[1].visible == false)
end)

test("failed appearance inspection or unsupported visible geometry reject before private resource creation", function()
    for _, scenario in ipairs({ "inspection", "unsupported" }) do
        local probe, deps, state = fixture()
        state.appearance_failure = scenario == "inspection"
        state.unsupported_visible = scenario == "unsupported"
        local receipt = probe.run(deps)
        assert(not receipt.ok and state.created == 0 and not state.target_created and #state.exports == 0)
        if scenario == "unsupported" then assert(receipt.appearance_report.unsupported_visible_sources) end
    end
end)

test("actual appearance replacement during rendering refuses later frames and releases owned resources", function()
    local probe, deps, state = fixture()
    state.on_export = function(index) if index == 2 then state.appearance_changed = true end end
    local receipt = probe.run(deps)
    assert(not receipt.ok and #state.exports == 2 and receipt.target_released and receipt.destruction_acknowledged)
    assert(receipt.frames[2].component_readback_after_export == nil)
end)

test("private component material changes after export are not repaired or reported as matching", function()
    local probe, deps, state = fixture()
    local replacement = object(999, "Material.Replacement")
    state.on_export = function(index) if index == 1 then state.components[1].materials[0] = replacement end end
    local receipt = probe.run(deps)
    assert(not receipt.ok and #state.exports == 1 and receipt.frames[1].component_readback_after_export == nil)
    assert(state.components[1].materials[0] == replacement and receipt.target_released)
end)

test("groom cache unmatched binding or missing private parent rejects the unsupported route with paired cleanup", function()
    for _, scenario in ipairs({ "cache", "binding", "parent" }) do
        local probe, deps, state = fixture()
        local groom = state.add_source("groom")
        if scenario == "cache" then groom.record.groom_cache = { address = "999", name = "GroomCache.Actual" }
        elseif scenario == "binding" then groom.binding_asset.TargetSkeletalMesh = object(998, "Asset.WrongHead")
        else groom.attach_parent = object(997, "Component.NotEnumerated") end
        local receipt = probe.run(deps)
        assert(not receipt.ok and #state.exports == 0 and receipt.target_released and receipt.destruction_acknowledged, scenario)
    end
end)

test("a changed groom descriptor after export invalidates before the next camera phase", function()
    local probe, deps, state = fixture()
    state.add_source("groom")
    state.on_export = function(index)
        if index == 1 then state.components[4].GroomGroupsDesc = { { HairWidth = 0.09, HairWidth_Override = true, HairLengthScale = 1, HairLengthScale_Override = false } } end
    end
    local receipt = probe.run(deps)
    assert(not receipt.ok and #state.exports == 1 and receipt.target_released)
end)

test("default target color-profile mismatch is diagnosed without modifying it or rendering", function()
    local probe, deps, state = fixture()
    state.target.TargetGamma = 1
    local receipt = probe.run(deps)
    assert(not receipt.ok and #state.exports == 0 and state.target.TargetGamma == 1 and receipt.target_released)
    assert(receipt.display_configuration.gamma_before.value == 1 and receipt.display_configuration.gamma_after.value == 1)
end)

test("all fixed filenames are checked before creation and every export remains creation-only", function()
    local probe, deps, state = fixture()
    deps.output_exists = function(filename) return filename:find("-eyes-closeup.png", 1, true) ~= nil end
    assert(not probe.run(deps).ok and state.created == 0)
end)

test("later export failure retains completed frame evidence and restores front before cleanup", function()
    local probe, deps, state = fixture()
    state.on_export = function(index) if index == 4 then error("native export failed") end end
    local receipt = probe.run(deps)
    assert(not receipt.ok and #receipt.frames == 3 and receipt.front_restored and receipt.target_released and receipt.destruction_acknowledged)
end)

test("owned target sizing failure and capture replacement preserve original resources", function()
    local probe, deps, state = fixture()
    state.target.SizeX = 512
    local receipt = probe.run(deps)
    assert(not receipt.ok and receipt.target_released and #state.exports == 0)
    probe, deps, state = fixture()
    state.on_finish = function() state.actor.CaptureComponent2D = object(999, "Capture.Replacement") end
    receipt = probe.run(deps)
    assert(not receipt.ok and not state.target_created)
end)

test("source materials and transforms never receive renderer setter calls", function()
    local probe, deps, state = fixture()
    for _, source in ipairs(state.appearance_sources) do
        function source.component:SetMaterial() error("Original material mutation") end
        function source.component:K2_SetWorldTransform() error("Original transform mutation") end
    end
    assert(probe.run(deps).ok)
end)

print("PASS " .. count .. " private appearance V8 test groups")

