local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_private_eye_preview_v7_probe_tests")
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
    target.SizeX, target.SizeY, target.RenderTargetFormat, target.bForceLinearGamma = 1024, 1024, 3, false
    local render, gameplay, math_library = object(300, "Library Render"), object(301, "Library Gameplay"), object(302, "Library Math")
    function render:CreateRenderTarget2D(context, width, height, format)
        assert(context == world and width == 1024 and height == 1024 and (format == 3 or format == 2))
        assert(state.spawn_finished, "Target allocation must follow native actor finalization")
        if format == 2 then
            state.comparison_created = true
            if state.on_comparison then state.on_comparison() end
            return state.comparison_alias or comparison
        end
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
    state.player, state.world, state.actor, state.capture, state.target, state.render, state.comparison = player, world, actor, capture, target, render, comparison
    return probe, deps, state
end

local count = 0
local function test(name, action) action(); count = count + 1; print("PASS " .. name) end

test("actual loaded source meshes receive private capture-only clones and dedicated target with paired cleanup", function()
    local probe, deps, state = fixture()
    local receipt = probe.run(deps)
    assert(receipt.ok, receipt.reason or receipt.cleanup_error)
    assert(receipt.created and receipt.destruction_acknowledged and receipt.target_released and not receipt.preview_verified)
    assert(#state.components == 5 and #state.exports == 15 and state.released == 2 and state.actor.destroying)
    assert(state.capture.TextureTarget == nil and #state.capture.shown == 3)
    assert(state.components[1].asset == state.player.HeadMesh.asset and state.components[1].leader == state.player.HeadMesh)
    assert(state.components[1].bVisibleInSceneCaptureOnly and state.components[1].LightingChannels.bChannel2)
    assert(not state.components[1].LightingChannels.bChannel0 and receipt.pivot.Z == 100190)
    assert(receipt.capture_requests == 15 and receipt.front_restored and receipt.schema == 3)
    assert(#receipt.diagnostics == 6 and receipt.comparison_target.released and receipt.comparison_target.owned)
    assert(receipt.destruction_pending and not receipt.actor_invalidated and receipt.capture.address == "101")
    assert(receipt.frames[2].yaw_degrees == -69 and receipt.frames[3].yaw_degrees == 69)
    assert(receipt.frames[4].framing == "eyes-close-up" and receipt.frames[9].phase == "restored-front")
    assert(receipt.frames[1].camera_location.X == receipt.frames[9].camera_location.X)
    assert(receipt.render_target_format == 3 and receipt.capture_source == 2 and receipt.target_gamma == 2.2)
end)

test("identity, intent, path, existing files and unobserved pivot reject creation", function()
    for _, scenario in ipairs({ "identity", "intent", "path", "existing", "pivot" }) do
        local probe, deps, state = fixture()
        if scenario == "identity" then deps.identity.build_id = "old"
        elseif scenario == "intent" then deps.intent = "read-only"
        elseif scenario == "path" then deps.output_directory = "C:/elsewhere"
        elseif scenario == "existing" then deps.output_exists = function() return true end
        else deps.pivot_bone_name = "not_in_skeleton" end
        assert(not probe.run(deps).ok and state.created == 0, scenario)
    end
end)

test("open inventory and absent actual torso reject independent preview", function()
    for _, scenario in ipairs({ "inventory", "torso" }) do
        local probe, deps, state = fixture()
        if scenario == "inventory" then state.inventory = { object(50, "InventoryRenderDoll World.Existing") }
        else state.player.TorsoMesh = nil end
        assert(not probe.run(deps).ok and state.created == 0)
    end
end)

test("unexpected existing capture target is never reused and owned actor is destroyed", function()
    local probe, deps, state = fixture()
    state.capture.TextureTarget = object(999, "TextureRenderTarget2D /Game/Shared")
    local receipt = probe.run(deps)
    assert(not receipt.ok and receipt.destruction_acknowledged and not state.target_created and #state.exports == 0)
end)

test("partial private mesh creation failure destroys actor and releases its target", function()
    local probe, deps, state = fixture()
    state.on_add = function(component) function component:SetSkeletalMeshAsset() error("native asset bind failed") end end
    local receipt = probe.run(deps)
    assert(not receipt.ok and receipt.destruction_acknowledged and receipt.target_released and state.released == 1)
end)

test("new target with unexpected dimensions is still released during failed construction", function()
    local probe, deps, state = fixture()
    state.target.SizeX = 512
    local receipt = probe.run(deps)
    assert(not receipt.ok and receipt.destruction_acknowledged and receipt.target_released and state.released == 1 and #state.exports == 0)
end)

test("native factory reuse never destroys a preexisting actor or releases a shared target", function()
    for _, scenario in ipairs({ "actor", "target" }) do
        local probe, deps, state = fixture()
        if scenario == "actor" then state.existing_actor = true
        else state.existing_target = true end
        local receipt = probe.run(deps)
        assert(not receipt.ok and state.released == 0 and #state.exports == 0)
        if scenario == "actor" then assert(not state.actor.destroying) else assert(state.actor.destroying) end
    end
end)

test("export failure preserves failure and still performs native resource cleanup", function()
    local probe, deps, state = fixture()
    state.export_error = "native export failed"
    local receipt = probe.run(deps)
    assert(not receipt.ok and receipt.export_invoked and receipt.destruction_acknowledged and receipt.target_released)
end)

test("loss of private capture ownership prevents writing replacement receiver during cleanup", function()
    local probe, deps, state = fixture()
    state.on_add = function()
        function state.capture:GetOwner() return state.player end
        error("capture owner replaced")
    end
    local receipt = probe.run(deps)
    assert(not receipt.ok and not receipt.destruction_acknowledged and not receipt.target_released and receipt.cleanup_error)
end)

test("unacknowledged isolation prevents capture", function()
    local probe, deps, state = fixture()
    state.on_add = function(component) function component:SetVisibleInSceneCaptureOnly() self.bVisibleInSceneCaptureOnly = false end end
    local receipt = probe.run(deps)
    assert(not receipt.ok and receipt.destruction_acknowledged and receipt.target_released and #state.exports == 0)
end)

test("source changes after private export are rejected without restoring player state", function()
    local probe, deps, state = fixture()
    function state.render:ExportRenderTarget() state.player.HeadMesh.material.address = 900 end
    local receipt = probe.run(deps)
    assert(not receipt.ok and receipt.destruction_acknowledged and receipt.target_released and receipt.source_error)
    assert(state.player.HeadMesh.material.address == 900)
end)

test("absent eye pair and invalid mesh bounds prevent any native creation", function()
    for _, scenario in ipairs({ "eyes", "bounds" }) do
        local probe, deps, state = fixture()
        if scenario == "eyes" then function state.player.HeadMesh:GetNumBones() return 2 end
        else function state.player.HeadMesh.asset:GetBounds() return { Origin = { X = 0, Y = 0, Z = 0 }, BoxExtent = {}, SphereRadius = 0 } end end
        local receipt = probe.run(deps)
        assert(not receipt.ok and state.created == 0, scenario)
    end
end)

test("phase collision is checked before creation and again before each native export", function()
    for _, after_creation in ipairs({ false, true }) do
        local probe, deps, state = fixture()
        deps.output_exists = function(filename)
            return filename:find("-eyes-closeup.png", 1, true) ~= nil and (not after_creation or state.created > 0)
        end
        local receipt = probe.run(deps)
        assert(not receipt.ok)
        if after_creation then assert(#state.exports == 9 and receipt.front_restored and receipt.destruction_acknowledged and receipt.target_released)
        else assert(state.created == 0) end
    end
end)

test("failed later export restores front projection before destroying only the private actor", function()
    local probe, deps, state = fixture()
    state.on_export = function(index) if index == 10 then error("fourth view export failed") end end
    local receipt = probe.run(deps)
    assert(not receipt.ok and #state.exports == 10 and receipt.front_restored and receipt.destruction_acknowledged and receipt.target_released)
    assert(state.capture.FOVAngle == 30 and state.capture.CustomNearClippingPlane == 1)
    assert(#receipt.frames == 3 and state.capture.location.X == receipt.frames[1].camera_location.X)
end)

test("native camera readback refusal still releases its privately owned resources", function()
    local probe, deps, state = fixture()
    function state.capture:K2_GetComponentLocation() return { X = 0, Y = 0, Z = 0 } end
    local receipt = probe.run(deps)
    assert(not receipt.ok and #state.exports == 0 and receipt.restore_error and receipt.destruction_acknowledged and receipt.target_released)
end)

test("immediate actor invalidation is distinguished from pending native destruction", function()
    local probe, deps, state = fixture()
    function state.actor:K2_DestroyActor() self.valid = false end
    local receipt = probe.run(deps)
    assert(receipt.ok and receipt.destruction_acknowledged and receipt.actor_invalidated and not receipt.destruction_pending)
    assert(receipt.target_released and receipt.destroyed == nil)
end)

test("new world-owned target is accepted even when its native path contains Game", function()
    local probe, deps, state = fixture()
    state.world.name = "World /Game/Maps/NativeWorld.NativeWorld"
    state.target.name = "TextureRenderTarget2D /Game/Maps/NativeWorld.NativeWorld:TextureRenderTarget2D_101"
    local receipt = probe.run(deps)
    assert(receipt.ok, receipt.reason or receipt.cleanup_error)
    assert(receipt.target_new_address and receipt.target_owned and receipt.target_outer.name == state.world.name)
    assert(receipt.spawn_finished and state.finish_calls == 1 and receipt.target_released)
end)

test("unexpected new target outer is diagnosed and the owned new resource is released", function()
    local probe, deps, state = fixture()
    function state.target:GetOuter() return object(909, "World OtherWorld") end
    local receipt = probe.run(deps)
    assert(not receipt.ok and receipt.target_new_address and receipt.target_owned and receipt.target_released)
    assert(receipt.target.address == "102" and receipt.target_outer.address == "909")
    assert(receipt.actor.address == "100" and receipt.capture.address == "101" and receipt.destruction_acknowledged)
end)

test("configuration failure before allocation still finalizes owned deferred actor for cleanup", function()
    local probe, deps, state = fixture()
    function state.capture:ClearShowOnlyComponents() error("capture setup failed") end
    local receipt = probe.run(deps)
    assert(not receipt.ok and receipt.spawn_finished and state.finish_calls == 1 and receipt.destruction_acknowledged)
    assert(not state.target_created and receipt.actor.address == "100")
end)

test("failed finalization is never blindly repeated and reports the unresolved native actor", function()
    local probe, deps, state = fixture()
    state.finish_error = "native finish rejected"
    local receipt = probe.run(deps)
    assert(not receipt.ok and receipt.spawn_finish_attempted and not receipt.spawn_finished and state.finish_calls == 1)
    assert(not receipt.destruction_acknowledged and receipt.cleanup_error and receipt.actor.address == "100")
    assert(not state.target_created and #state.exports == 0)
end)

test("native construction replacement of capture rejects before target allocation", function()
    local probe, deps, state = fixture()
    state.on_finish = function() state.actor.CaptureComponent2D = object(909, "Capture Private.Replacement") end
    local receipt = probe.run(deps)
    assert(not receipt.ok and not state.target_created and #state.exports == 0 and receipt.destruction_acknowledged)
end)

test("owned target config explicitly clears native boolean or byte force-linear gamma and records actual values", function()
    for _, before in ipairs({ true, 1 }) do
        local probe, deps, state = fixture()
        state.target.bForceLinearGamma, state.target.TargetGamma = before, 0
        local result = probe.run(deps)
        assert(result.ok and result.display_configuration.force_linear_before.value == before)
        assert(result.display_configuration.gamma_after.value == 2.2 and result.display_configuration.write_ok)
        assert(result.display_configuration.force_linear_after.value == (type(before) == "number" and 0 or false))
    end
end)

test("native display write rejection preserves separate before and after diagnostics", function()
    local probe, deps, state = fixture()
    state.target.bForceLinearGamma = nil
    setmetatable(state.target, { __index = function(_, key) if key == "bForceLinearGamma" then return true end end,
        __newindex = function(target, key, value) if key == "bForceLinearGamma" then error("native byte setter rejected") end; rawset(target, key, value) end })
    local result = probe.run(deps)
    assert(not result.ok and result.display_configuration.write_ok == false and result.display_configuration.force_linear_after.value == true)
    assert(result.display_configuration.gamma_after.value == 2.2 and result.target_released and #state.exports == 0)
end)

test("latent actor destruction schedules only three read-only nonce-bound observations", function()
    local probe, deps, state = fixture()
    local callbacks, reports = {}, {}
    function state.actor:K2_DestroyActor() state.destroy_calls = (state.destroy_calls or 0) + 1 end
    function state.actor:HasAuthority() return true end
    function state.actor:GetLocalRole() return 3 end
    function state.actor:GetLifeSpan() return 0 end
    deps.schedule_after_frames = function(frames, callback) callbacks[frames] = callback; return frames end
    deps.report_cleanup_observation = function(receipt) reports[#reports + 1] = receipt end
    local result = probe.run(deps)
    assert(not result.ok and result.destroy_invoked and not result.destruction_acknowledged and result.target_released)
    assert(result.capture_operation_completed and #result.frames == 9 and result.width == 1024 and result.capture_source == 2)
    assert(#result.source_meshes == 3 and result.player.address == "2" and result.form == 0 and not result.is_wolf_form)
    assert(result.framing_profiles["eyes-close-up"] and result.capture_timestamp_known == false and not result.preview_verified)
    assert(result.destroy_call_return.ok and result.destroy_call_return.type == "nil")
    assert(result.actor_before_destroy.local_role.value == 3 and #result.cleanup_observation_schedules == 3)
    callbacks[1]({ requested_frames = 1, elapsed_frames = 1, schedule_complete = true, started_frame = 100, observed_frame = 101 })
    assert(reports[1].actor_state.valid and not reports[1].actor_state.being_destroyed.value)
    state.actor.valid = false
    callbacks[3]({ requested_frames = 3, elapsed_frames = 3, schedule_complete = true, started_frame = 100, observed_frame = 103 })
    callbacks[30]({ requested_frames = 30, elapsed_frames = 30, schedule_complete = true, started_frame = 100, observed_frame = 130 })
    assert(#reports == 3 and reports[2].actor_state.actor_invalidated and reports[3].after_frames == 30)
    assert(reports[3].nonce == deps.nonce and reports[3].boot_id == deps.boot_id and state.destroy_calls == 1)
end)

test("future actor address reuse is recorded without operating on the replacement", function()
    local probe, deps, state = fixture()
    local callbacks, reports = {}, {}
    deps.schedule_after_frames = function(frames, callback) callbacks[frames] = callback; return frames end
    deps.report_cleanup_observation = function(receipt) reports[#reports + 1] = receipt end
    assert(probe.run(deps).ok)
    state.actor.name = "SceneCapture2D DifferentActor"
    function state.actor:GetWorld() error("replacement actor must not be queried") end
    callbacks[1]({ requested_frames = 1, elapsed_frames = 1, schedule_complete = true, started_frame = 100, observed_frame = 101 })
    assert(reports[1].observation_ok and not reports[1].actor_state.identity_matches and reports[1].actor_state.being_destroyed == nil)
end)

test("missing or rejected frame scheduler never implies delayed cleanup confirmation", function()
    local probe, deps, state = fixture()
    function state.actor:K2_DestroyActor() end
    deps.schedule_after_frames = function() error("engine tick is unavailable") end
    deps.report_cleanup_observation = function() error("should not run") end
    local result = probe.run(deps)
    assert(not result.ok and not result.destruction_acknowledged and #result.cleanup_observation_schedules == 0)
    assert(#result.cleanup_observation_schedule_errors == 3 and result.target_released)
end)

test("incomplete native frame counter interval prevents actor reads and duplicate callbacks are ignored", function()
    local probe, deps, state = fixture()
    local callbacks, reports = {}, {}
    deps.schedule_after_frames = function(frames, callback) callbacks[frames] = callback; return frames end
    deps.report_cleanup_observation = function(receipt) reports[#reports + 1] = receipt end
    assert(probe.run(deps).ok)
    function state.actor:IsValid() error("no read allowed before actual future frame interval") end
    callbacks[1]({ requested_frames = 1, elapsed_frames = 0, schedule_complete = false, started_frame = 100, observed_frame = 100 })
    callbacks[1]({ requested_frames = 1, elapsed_frames = 1, schedule_complete = true, started_frame = 100, observed_frame = 101 })
    callbacks[3]({ requested_frames = 3, elapsed_frames = 3, schedule_complete = true, started_frame = 100, observed_frame = 101 })
    assert(#reports == 2 and not reports[1].observation_ok and not reports[2].observation_ok)
    assert(reports[1].actor_state == nil and reports[1].schedule.schedule_complete == false)
end)

test("logical Unreal validity is dispatched explicitly and distinguished from wrapper lifetime", function()
    local probe, deps, state = fixture()
    function state.actor:IsActorBeingDestroyed()
        assert(not self.destroying, "No actor methods after native logical invalidation")
        return false
    end
    local original_lookup = deps.static_find_object
    local library, native_function = object(990, "KismetSystemLibrary Default__KismetSystemLibrary"), object(991, "Function Engine.KismetSystemLibrary.IsValid")
    setmetatable(native_function, { __call = function(fn, context, actor)
        assert(fn == native_function and context == library and actor == state.actor)
        return not actor.destroying
    end })
    deps.static_find_object = function(name)
        if name == "/Script/Engine.Default__KismetSystemLibrary" then return library end
        if name == "/Script/Engine.KismetSystemLibrary:IsValid" then return native_function end
        return original_lookup(name)
    end
    local result = probe.run(deps)
    assert(result.ok and result.actor_before_destroy.native_is_valid.value == true)
    assert(result.actor_after_destroy.valid and result.actor_after_destroy.native_is_valid.value == false)
    assert(result.actor_after_destroy.being_destroyed == nil)
end)

test("six fixed diagnostic profiles preserve actual per-frame settings before nine fixed views", function()
    local probe, deps, state = fixture()
    local receipt = probe.run(deps)
    assert(receipt.ok and receipt.capture_limit == 15 and receipt.render_target_limit == 2)
    local names = { "diag-world-ldr", "diag-isolated-ldr", "diag-manual-zero", "diag-manual-low", "diag-manual-high", "diag-inventory-color" }
    local intensity = { 2000, 2000, 0, 20, 200, 20 }
    for index, name in ipairs(names) do
        local frame = receipt.diagnostics[index]
        assert(frame.phase == name and frame.profile.phase == name and frame.profile.lights[1].intensity == intensity[index])
        assert(frame.profile_after.lights[2].intensity == intensity[index])
        assert(frame.file_name == "eye-private-" .. deps.nonce .. "-" .. name .. ".png")
        assert(frame.profile.capture_source == (index == 6 and 9 or 2))
        assert(frame.render_target_format == (index == 6 and 2 or 3))
        if index > 1 then assert(frame.profile.show_flags.Fog == false and frame.profile.show_flags.Atmosphere == false) end
        if index > 2 then assert(frame.profile.exposure_method.value == 2 and frame.profile.exposure_bias.value == 0 and frame.profile.exposure_physical.value == false) end
    end
    assert(receipt.diagnostics[6].target_gamma == 0 and receipt.diagnostics[6].force_linear_gamma == true)
    for _, frame in ipairs(receipt.frames) do
        assert(frame.profile.phase == "isolated-manual-20cd" and frame.profile.lights[1].intensity == 20)
        assert(frame.profile_after.lights[1].intensity == 20 and frame.profile.manual and frame.profile.isolated)
    end
    assert(state.setters_on_player == 0 and receipt.comparison_target.released)
end)

test("unsupported native show-flag or exposure readback rejects without claiming calibrated views", function()
    for _, scenario in ipairs({ "flags", "exposure" }) do
        local probe, deps, state = fixture()
        if scenario == "flags" then
            function state.capture:SetShowFlagSettings(settings) self.show_flags = {}; assert(type(settings) == "table") end
        else
            local original = state.capture.PostProcessSettings
            original.bOverride_AutoExposureMethod = nil
            setmetatable(original, { __index = function(_, key) if key == "bOverride_AutoExposureMethod" then return false end end,
                __newindex = function(table, key, value) if key ~= "bOverride_AutoExposureMethod" then rawset(table, key, value) end end })
        end
        local receipt = probe.run(deps)
        assert(not receipt.ok and #receipt.frames == 0 and receipt.target_released and receipt.destruction_acknowledged)
        assert(#receipt.diagnostics == (scenario == "flags" and 1 or 2))
    end
end)

test("native profile and target are reread after export without setter repair", function()
    for _, scenario in ipairs({ "lamp", "exposure", "flags", "target" }) do
        local probe, deps, state = fixture()
        state.on_export = function(index)
            if index ~= 4 then return end
            if scenario == "lamp" then state.components[4].Intensity = 900
            elseif scenario == "exposure" then state.capture.PostProcessSettings.AutoExposureMethod = 0
            elseif scenario == "flags" then state.capture.show_flags = {}
            else state.target.TargetGamma = 1 end
        end
        local receipt = probe.run(deps)
        assert(not receipt.ok and #state.exports == 4 and #receipt.frames == 0 and receipt.target_released, scenario)
        assert(receipt.diagnostics[4].profile_after == nil or scenario == "target")
    end
end)

test("comparison target alias is rejected before binding and never released as a second resource", function()
    local probe, deps, state = fixture()
    state.comparison_alias = state.target
    local receipt = probe.run(deps)
    assert(not receipt.ok and #state.exports == 5 and not receipt.comparison_target.owned)
    assert(receipt.target_released and state.released == 1 and state.capture.TextureTarget == nil)
end)

test("new comparison target is owned before size validation and both resources are cleaned", function()
    local probe, deps, state = fixture()
    state.comparison.SizeX = 512
    local receipt = probe.run(deps)
    assert(not receipt.ok and #state.exports == 5 and receipt.comparison_target.owned and receipt.comparison_target.released)
    assert(receipt.target_released and state.released == 2)
end)

test("comparison release failure does not prevent the other owned target release", function()
    local probe, deps, state = fixture()
    function state.render:ReleaseRenderTarget2D(target)
        if target == state.comparison then
            state.comparison_release_calls = (state.comparison_release_calls or 0) + 1
            error("comparison release unavailable")
        end
        assert(target == state.target); state.primary_release_attempted = true
    end
    local receipt = probe.run(deps)
    assert(not receipt.ok and receipt.comparison_release_error and not receipt.comparison_target.released)
    assert(state.primary_release_attempted and receipt.target_released and receipt.destruction_acknowledged)
    assert(state.comparison_release_calls == 1)
end)

test("observed native destroyed flag acknowledges marked destruction separately from wrapper invalidation", function()
    local probe, deps, state = fixture()
    function state.actor:K2_DestroyActor() self.bActorIsBeingDestroyed = true end
    local receipt = probe.run(deps)
    assert(receipt.ok and receipt.destruction_acknowledged and receipt.destruction_pending and not receipt.actor_invalidated)
    assert(receipt.actor_after_destroy.destroyed_flag.value == true and receipt.actor_after_destroy.being_destroyed.value == false)
end)

test("successful optional observations omit error fields instead of serializing nil or table strings", function()
    local probe, deps, state = fixture()
    local callbacks, receipts = {}, {}
    deps.schedule_after_frames = function(frames, callback) callbacks[frames] = callback; return frames end
    deps.report_cleanup_observation = function(receipt) receipts[#receipts + 1] = receipt end
    local receipt = probe.run(deps)
    assert(receipt.ok and receipt.display_configuration.write_error == nil)
    callbacks[1]({ requested_frames = 1, elapsed_frames = 1, started_frame = 10, observed_frame = 11, schedule_complete = true })
    assert(receipts[1].observation_ok and receipts[1].observation_error == nil)
end)

print("PASS " .. count .. " private native preview test groups")
