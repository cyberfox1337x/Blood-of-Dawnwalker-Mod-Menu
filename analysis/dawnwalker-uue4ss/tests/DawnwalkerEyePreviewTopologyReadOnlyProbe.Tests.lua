local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_preview_topology_read_only_probe_tests")

local path = assert(arg[1], "Pass the eye-preview probe module path")
local file = assert(io.open(path, "r"))
local source = file:read("*a")
file:close()
for _, pattern in ipairs({ "SetMaterial%s*%(", "SetVectorParameter", "SetScalarParameter", "CreateDynamicMaterial",
    "K2_Set", "SpawnActor", "DestroyActor", "CaptureScene%s*%(", "ExportRenderTarget%s*%(", "ReadRenderTarget%s*%(",
    "ExecuteConsoleCommand", "RegisterKeyBind", "RegisterHook", "StaticLoadObject", "io%.open", "os%.execute" }) do
    assert(not source:find(pattern), "preview probe must remain read-only: " .. pattern)
end
local Probe = assert(dofile(path))

local function object(address, name, classes)
    local result = { address = address, name = name, classes = classes, valid = true }
    function result:IsValid() return self.valid end
    function result:IsA(class)
        for _, expected in ipairs(self.classes) do if expected == class then return true end end
        return false
    end
    function result:GetAddress() return self.address end
    function result:GetFullName() return self.name end
    return result
end

local function fixture()
    local world = object(10, "World World", { "/Script/Engine.World" })
    local player = object(20, "DawnwalkerPlayerCharacter World.Player", { "/Script/Dawnwalker.DawnwalkerPlayerCharacter" })
    player.Form, player.wolf = 1, false
    function player:GetWorld() return world end
    function player:IsInWolfForm() return self.wolf end
    function player:K2_GetActorLocation() return { X = 1, Y = 2, Z = 3 } end
    function player:K2_GetActorRotation() return { Pitch = 0, Yaw = 25, Roll = 0 } end
    local doll = object(30, "BP_RenderDoll2_C World.Doll", { "/Script/DogwoodInventory.InventoryRenderDoll" })
    function doll:GetWorld() return world end
    function doll:K2_GetActorLocation() return { X = 10000, Y = 0, Z = 10000 } end
    function doll:K2_GetActorRotation() return { Pitch = 0, Yaw = 0, Roll = 0 } end
    local inventory = object(40, "InventoryComponent Player.Inventory", { "/Script/DogwoodInventory.InventoryComponent" })
    function inventory:GetOwner() return player end
    doll.TargetInventory = inventory
    doll.AppearanceToApply = object(45, "AppearanceBase /Game/Observed.Appearance", { "/Script/DogwoodInventory.AppearanceBase" })
    local capture = object(50, "SceneCaptureComponent2D Doll.Capture", { "/Script/Engine.SceneCaptureComponent2D", "/Script/Engine.SceneComponent" })
    function capture:GetOwner() return doll end
    function capture:K2_GetComponentLocation() return { X = 9850, Y = 0, Z = 10165 } end
    function capture:K2_GetComponentRotation() return { Pitch = 0, Yaw = 0, Roll = 0 } end
    capture.ProjectionType, capture.FOVAngle, capture.OrthoWidth = 0, 30, 512
    capture.PrimitiveRenderMode, capture.CaptureSource = 2, 0
    capture.PostProcessBlendWeight, capture.CustomNearClippingPlane = 0, 1
    for _, flag in ipairs({ "bCaptureEveryFrame", "bCaptureOnMovement", "bMainViewCamera", "bMainViewFamily",
        "bMainViewResolution", "bRenderInMainRenderer", "bSuppressWorldPostProcessing", "bOverride_CustomNearClippingPlane" }) do
        capture[flag] = false
    end
    capture.ShowOnlyActors, capture.HiddenActors = { doll }, {}
    capture.ShowOnlyComponents, capture.HiddenComponents = {}, {}
    local target = object(60, "TextureRenderTarget2D /Game/Observed.Target", { "/Script/Engine.TextureRenderTarget2D" })
    target.SizeX, target.SizeY, target.RenderTargetFormat, target.OverrideFormat, target.TargetGamma = 1024, 1024, 4, 0, 2.2
    target.SRGB, target.bForceLinearGamma, target.bHDR, target.bGPUSharedFlag = true, false, false, false
    capture.TextureTarget, doll.SceneCapture = target, capture
    local mesh = object(70, "SkeletalMeshComponent Doll.Head", { "/Script/Engine.SkeletalMeshComponent", "/Script/Engine.SceneComponent" })
    mesh.asset = object(71, "SkeletalMesh /Game/Observed.Head", { "/Script/Engine.SkeletalMesh" })
    mesh.material = object(72, "MaterialInstanceConstant /Game/Observed.Eye", { "/Script/Engine.MaterialInterface" })
    function mesh:GetOwner() return doll end
    function mesh:GetSkeletalMeshAsset() return self.asset end
    function mesh:GetNumMaterials() return 1 end
    function mesh:GetMaterial(index) assert(index == 0); return self.material end
    function mesh:GetMaterialSlotNames() return { { ToString = function() return "ObservedSlot" end } } end
    doll.HeadMeshComponent = mesh
    local light = object(80, "SpotLightComponent Doll.Key", { "/Script/Engine.LightComponentBase" })
    function light:GetOwner() return doll end
    function light:GetLightColor() return { R = 1, G = 1, B = 1, A = 1 } end
    light.Intensity = 100
    doll["Key Light Spot"] = light
    local root = object(90, "SceneComponent Doll.Root", { "/Script/Engine.SceneComponent" })
    function root:GetOwner() return doll end
    doll.RootComponent = root
    capture.parent, mesh.parent = root, root
    for _, component in ipairs({ root, capture, mesh }) do
        function component:GetAttachParent() return self.parent end
        function component:GetRelativeTransform() return { Translation = { X = 1, Y = 2, Z = 3 },
            Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Scale3D = { X = 1, Y = 1, Z = 1 } } end
        if not component.K2_GetComponentLocation then
            function component:K2_GetComponentLocation() return { X = 10000, Y = 0, Z = 10165 } end
            function component:K2_GetComponentRotation() return { Pitch = 0, Yaw = 0, Roll = 0 } end
        end
    end
    local deps = { game_thread = true,
        identity = { build_id = "25129649", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853" },
        get_player = function() return player end,
        find_all_of = function(class) assert(class == "InventoryRenderDoll"); return { doll } end }
    return deps, { world = world, player = player, doll = doll, inventory = inventory, capture = capture,
        target = target, mesh = mesh, light = light, root = root }
end

local total = 0
local function test(name, action)
    action()
    total = total + 1
    print("PASS " .. name)
end

test("native doll references, isolated transforms, render target and capture list are observations only", function()
    local deps = fixture()
    local result = Probe.run(deps)
    assert(result.ok and result.observed_doll_count == 1 and not result.preview_verified
        and not result.gameplay_verified and not result.mutation_authorized)
    assert(result.player_rotation.value.yaw == 25 and result.form == 1 and not result.is_wolf_form)
    local doll = result.dolls[1].value
    assert(doll.rotation.value.yaw == 0 and doll.location.value.x == 10000)
    assert(doll.capture.target.width == 1024 and doll.capture.target.format == 4)
    assert(doll.capture.lists.ShowOnlyActors.value[1].value.address == "30")
    assert(doll.capture.flags.bMainViewCamera.ok and not doll.capture.flags.bMainViewCamera.value)
    assert(doll.meshes.HeadMeshComponent.materials[1].slot_name == "ObservedSlot")
    assert(doll.meshes.HeadMeshComponent.asset.address == "71" and doll.meshes.HairMeshComponent == nil)
    assert(doll.lights == nil and doll.topology.SceneCapture.value[1].parent.address == "90")
    assert(doll.topology.HeadMeshComponent.value[1].relative.value.rotation.w == 1)
    assert(doll.topology.HeadMeshComponent.value[1].location.value.z == 10165)
end)

test("no doll and class defaults never become a fabricated preview", function()
    local deps, objects = fixture()
    deps.find_all_of = function() return nil end
    local result = Probe.run(deps)
    assert(result.ok and result.observed_doll_count == 0 and #result.dolls == 0 and not result.preview_verified)
    objects.doll.name = "BP_RenderDoll2_C /Game/Observed.Default__BP_RenderDoll2_C"
    deps.find_all_of = function() return { objects.doll } end
    result = Probe.run(deps)
    assert(result.ok and result.observed_doll_count == 0 and #result.dolls == 0)
end)

test("wrong build hash or thread rejects before resolving game objects", function()
    for _, field in ipairs({ "build", "hash", "thread" }) do
        local deps = fixture()
        deps.get_player = function() error("unexpected player access") end
        if field == "build" then deps.identity.build_id = "old"
        elseif field == "hash" then deps.identity.executable_sha256 = "bad"
        else deps.game_thread = false end
        local result = Probe.run(deps)
        assert(not result.ok and not result.reason:find("unexpected player access", 1, true))
    end
end)

test("foreign inventory owner or player-owned capture/mesh cannot establish a doll", function()
    for _, field in ipairs({ "inventory", "capture", "mesh" }) do
        local deps, objects = fixture()
        if field == "inventory" then function objects.inventory:GetOwner() return objects.doll end
        elseif field == "capture" then function objects.capture:GetOwner() return objects.player end
        else function objects.mesh:GetOwner() return objects.player end end
        local result = Probe.run(deps)
        assert(result.ok and result.observed_doll_count == 0 and not result.dolls[1].ok)
        assert(result.dolls[1].value == nil)
    end
end)

test("missing head, oversized target and invalid slot count remain explicit unavailable results", function()
    for _, field in ipairs({ "head", "target", "slots" }) do
        local deps, objects = fixture()
        if field == "head" then objects.doll.HeadMeshComponent = nil
        elseif field == "target" then objects.target.SizeX = 8193
        else function objects.mesh:GetNumMaterials() return 17 end end
        local result = Probe.run(deps)
        assert(result.ok and not result.dolls[1].ok and result.observed_doll_count == 0)
    end
end)

test("unknown optional capture flags are failures rather than guessed defaults", function()
    local deps, objects = fixture()
    objects.capture.bMainViewCamera = nil
    local result = Probe.run(deps)
    assert(result.ok and result.dolls[1].ok and not result.dolls[1].value.capture.flags.bMainViewCamera.ok)
    assert(result.dolls[1].value.capture.flags.bMainViewCamera.value == nil)
end)

test("wrapped weak capture entries resolve without hiding unreadable entries", function()
    local deps, objects = fixture()
    objects.capture.ShowOnlyActors = { { Get = function() return objects.doll end }, {} }
    local entries = Probe.run(deps).dolls[1].value.capture.lists.ShowOnlyActors.value
    assert(entries[1].ok and entries[1].value.address == "30" and not entries[2].ok)
end)

test("doll enumeration count and duplicates are bounded", function()
    local deps, objects = fixture()
    deps.find_all_of = function() return { GetArrayNum = function() return 9 end } end
    assert(not Probe.run(deps).ok)
    deps.find_all_of = function() return { objects.doll, objects.doll } end
    assert(not Probe.run(deps).ok)
end)

test("replacement of material, capture target or mesh ownership invalidates whole snapshot", function()
    for _, field in ipairs({ "material", "target", "owner" }) do
        local deps, objects = fixture()
        local reads = 0
        function objects.mesh:GetMaterial(index)
            assert(index == 0)
            reads = reads + 1
            if reads == 1 then
                if field == "target" then objects.target.SizeY = 512 end
                if field == "owner" then function self:GetOwner() return objects.player end end
            end
            if field == "material" and reads > 1 then return nil end
            return self.material
        end
        local result = Probe.run(deps)
        assert(not result.ok and result.dolls == nil, field .. " changed without rejection")
    end
end)

test("player world, human/vampire and wolf transitions invalidate observations", function()
    for _, field in ipairs({ "world", "form", "wolf" }) do
        local deps, objects = fixture()
        local reads = 0
        deps.get_player = function()
            reads = reads + 1
            if reads > 1 then
                if field == "world" then objects.world.address = 99
                elseif field == "form" then objects.player.Form = 0
                else objects.player.wolf = true end
            end
            return objects.player
        end
        local result = Probe.run(deps)
        assert(not result.ok and result.dolls == nil)
    end
end)

test("reported object names cannot inject output lines", function()
    local deps, objects = fixture()
    objects.mesh.material.name = "Material /Game/Observed.Eye\nInjected%"
    local output = Probe.format_lines(Probe.run(deps))
    assert(output:find("Eye%0AInjected%25", 1, true))
end)

test("unreadable transforms are explicit and attachment cycles or foreign owners do not prove topology", function()
    for _, scenario in ipairs({ "transform", "cycle", "foreign" }) do
        local deps, objects = fixture()
        if scenario == "transform" then function objects.capture:GetRelativeTransform() error("unsupported return layout") end
        elseif scenario == "cycle" then objects.root.parent = objects.capture
        else function objects.root:GetOwner() return objects.player end end
        local result = Probe.run(deps)
        assert(result.ok and result.dolls[1].ok)
        local topology = result.dolls[1].value.topology.SceneCapture
        if scenario == "transform" then assert(topology.ok and not topology.value[1].relative.ok)
        else assert(not topology.ok and topology.value == nil) end
    end
end)

test("attachment replacement invalidates the observed snapshot", function()
    local deps, objects = fixture()
    local reads = 0
    function objects.capture:GetAttachParent()
        reads = reads + 1
        return reads == 1 and objects.root or nil
    end
    local result = Probe.run(deps)
    assert(not result.ok and result.dolls == nil and result.reason:find("attach parent changed", 1, true))
end)

test("topology output stays compact and excludes body and material parameter inventories", function()
    local deps = fixture()
    local output = Probe.format_lines(Probe.run(deps))
    assert(#output < 24000 and not output:find("HairMeshComponent", 1, true))
    assert(not output:find("ParameterInfo", 1, true) and not output:find("lights.", 1, true))
end)

print("PASS " .. total .. " eye-preview topology read-only probe test groups")
