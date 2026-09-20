local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_appearance_sources_tests")
local Sources = dofile(assert(arg[1], "Pass appearance source module"))
local E, H = "/Script/Engine.", "/Script/HairStrandsCore."
local function object(address, classes)
    local value = { address = address, name = "Native.Object_" .. address, classes = {}, valid = true }
    for _, class in ipairs(classes) do value.classes[class] = true end
    function value:IsValid() return self.valid end
    function value:IsA(class) return self.classes[class] == true end
    function value:GetAddress() return self.address end
    function value:GetFullName() return self.name end
    return value
end
local function transform()
    return { Translation = { X = 1, Y = 2, Z = 3 }, Scale3D = { X = 1, Y = 1, Z = 1 },
        Rotation = { X = 0, Y = 0, Z = 0, W = 1 } }
end
local function fixture()
    local state = { sequence = 100, mesh_queries = 0 }
    local world = object(1, { E .. "World" })
    local player = object(2, { E .. "Actor", "/Script/Dawnwalker.DawnwalkerPlayerCharacter" })
    player.Form, player.bHidden, player.meshes = 0, false, {}
    function player:GetWorld() return world end
    function player:IsInWolfForm() return self.wolf or false end
    function player:K2_GetComponentsByClass(class) assert(class == state.class); state.mesh_queries = state.mesh_queries + 1; return self.meshes end
    local function component(owner, kind)
        state.sequence = state.sequence + 1
        local classes = { E .. "SceneComponent" }
        if kind then classes[#classes + 1] = E .. "MeshComponent"; classes[#classes + 1] = kind end
        local item = object(state.sequence, classes)
        item.owner, item.children, item.bHiddenInGame, item.visible, item.materials = owner, {}, false, true, {}
        item.relative, item.world_transform = transform(), transform()
        function item:GetOwner() return self.owner end
        function item:GetAttachParent() return self.parent end
        function item:GetAttachSocketName() return self.socket or "None" end
        function item:GetNumChildrenComponents() return #self.children end
        function item:GetChildComponent(index) return self.children[index + 1] end
        function item:IsVisible() return self.visible end
        function item:GetRelativeTransform() return self.relative end
        function item:K2_GetComponentToWorld() return self.world_transform end
        function item:GetSkeletalMeshAsset() return self.asset end
        function item:GetNumMaterials() return #self.materials end
        function item:GetMaterial(slot) return self.materials[slot + 1] end
        return item
    end
    local root = component(player)
    local head = component(player, E .. "SkeletalMeshComponent")
    head.asset, head.parent = object(20, { E .. "SkeletalMesh" }), root
    head.materials = { object(30, { E .. "MaterialInterface" }) }
    player.RootComponent, player.HeadMesh, player.meshes, root.children = root, head, { head }, { head }
    state.player, state.world, state.head, state.root, state.component = player, world, head, root, component
    state.class = object(3, { "/Script/CoreUObject.Class" })
    state.deps = { game_thread = true, identity = { build_id = "25129649",
        executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853" },
        get_player = function() return state.player end,
        static_find_object = function(path) assert(path == E .. "MeshComponent"); return state.class end }
    function state:attach_actor()
        self.sequence = self.sequence + 1
        local actor = object(self.sequence, { E .. "Actor" })
        actor.parent, actor.bHidden, actor.meshes = player, false, {}
        function actor:GetWorld() return world end
        function actor:GetAttachParentActor() return self.parent end
        function actor:K2_GetComponentsByClass(class) assert(class == state.class); return self.meshes end
        actor.RootComponent = component(actor)
        actor.RootComponent.parent = root
        root.children[#root.children + 1] = actor.RootComponent
        return actor
    end
    function state:groom()
        local groom = component(player, H .. "GroomComponent")
        groom.GroomAsset, groom.SourceSkeletalMesh = object(40, { H .. "GroomAsset" }), head.asset
        groom.BindingAsset = object(41, { H .. "GroomBindingAsset" })
        groom.BindingAsset.Groom, groom.BindingAsset.TargetSkeletalMesh, groom.BindingAsset.GroomBindingType = groom.GroomAsset, head.asset, 0
        groom.parent, groom.bUseCards, groom.AttachmentName, groom.GroomGroupsDesc = head, true, "head", {}
        head.children[#head.children + 1], player.meshes[#player.meshes + 1] = groom, groom
        return groom
    end
    return state
end
local count = 0
local function test(name, action) action(); count = count + 1; print("PASS " .. name) end

test("current player head snapshot is plain evidence with native bindings kept separately", function()
    local s = fixture(); local result = Sources.run(s.deps)
    assert(result.ok and not result.report.mutation_authorized and not result.report.appearance_verified)
    assert(result.report.mesh_count == 1 and result.report.actor_count == 1 and result.report.scene_node_count == 2)
    assert(result.snapshot.sources[1].component == s.head and result.snapshot.head == s.head)
    assert(Sources.verify(s.deps, result.snapshot))
end)
test("attached actor clothing is included only through a player attachment chain", function()
    local s = fixture(); local actor = s:attach_actor(); local clothing = s.component(actor, E .. "SkeletalMeshComponent")
    clothing.asset, clothing.parent = s.head.asset, actor.RootComponent
    actor.meshes, actor.RootComponent.children = { clothing }, { clothing }
    local result = Sources.run(s.deps)
    assert(result.ok and result.report.mesh_count == 2 and result.report.actor_count == 2)
    actor.parent = nil
    assert(not Sources.verify(s.deps, result.snapshot) and not Sources.run(s.deps).ok)
end)
test("groom preserves exact binding target and attachment references", function()
    local s = fixture(); local groom = s:groom(); local result = Sources.run(s.deps)
    assert(result.ok)
    local entry = result.snapshot.sources[2]
    assert(entry.record.kind == "groom" and entry.attach_parent == s.head and entry.binding_target_skeletal_mesh == s.head.asset)
    assert(entry.record.binding_matches_parent and entry.record.binding_matches_groom and entry.record.bUseCards)
    groom.BindingAsset.TargetSkeletalMesh = object(50, { E .. "SkeletalMesh" })
    assert(not Sources.verify(s.deps, result.snapshot))
    local changed = Sources.run(s.deps)
    assert(changed.ok and not changed.snapshot.sources[2].record.binding_matches_parent)
end)
test("unfamiliar and instanced meshes stay explicitly unsupported", function()
    local s = fixture(); local mesh = s.component(s.player, E .. "StaticMeshComponent")
    mesh.classes[E .. "InstancedStaticMeshComponent"], mesh.parent = true, s.root
    s.player.meshes[#s.player.meshes + 1], s.root.children[#s.root.children + 1] = mesh, mesh
    local result = Sources.run(s.deps)
    assert(result.ok and result.report.unsupported_visible_sources and result.report.sources[2].kind == "unsupported")
end)
test("assets materials visibility attachment pose and form invalidate snapshots", function()
    for _, mutate in ipairs({ function(s) s.head.asset = object(22, { E .. "SkeletalMesh" }) end,
        function(s) s.head.materials[1] = object(32, { E .. "MaterialInterface" }) end,
        function(s) s.head.visible = false end, function(s) s.head.bHiddenInGame = true end,
        function(s) s.head.socket = "Different" end, function(s) s.head.world_transform.Translation.X = 9 end,
        function(s) s.player.Form = 1 end }) do
        local s = fixture(); local result = Sources.run(s.deps); assert(result.ok)
        mutate(s); assert(not Sources.verify(s.deps, result.snapshot))
    end
end)
test("wrong build thread controller and component ownership fail before cloning", function()
    for _, mutate in ipairs({ function(s) s.deps.game_thread = false end, function(s) s.deps.identity.build_id = "old" end,
        function(s) s.player.wolf = true end, function(s) s.head.owner = object(500, { E .. "Actor" }) end }) do
        local s = fixture(); mutate(s); assert(not Sources.run(s.deps).ok)
    end
end)
test("scene attachment cycles and foreign child owners are refused", function()
    local s = fixture(); s.head.children[1] = s.root; assert(not Sources.run(s.deps).ok)
    s = fixture(); local actor = s:attach_actor(); actor.parent = actor; assert(not Sources.run(s.deps).ok)
end)
test("aggregate mesh and attached actor budgets fail without truncation", function()
    local s = fixture()
    for _ = 1, 32 do local mesh = s.component(s.player, E .. "SkeletalMeshComponent"); mesh.asset = s.head.asset; s.player.meshes[#s.player.meshes + 1] = mesh end
    assert(not Sources.run(s.deps).ok)
    s = fixture(); for _ = 1, 9 do s:attach_actor() end
    assert(not Sources.run(s.deps).ok)
end)
test("groom array and nonfinite scalar bounds fail explicitly", function()
    local s = fixture(); local groom = s:groom()
    groom.GroomGroupsDesc = { { HairLength = 0 / 0 } }; assert(not Sources.run(s.deps).ok)
    groom.GroomGroupsDesc = {}; for index = 1, 17 do groom.GroomGroupsDesc[index] = {} end
    assert(not Sources.run(s.deps).ok)
end)
test("native TArray wrappers unwrap component entries without external scans", function()
    local s = fixture(); s.player.meshes = { { get = function() return s.head end }, GetArrayNum = function() return 1 end }
    assert(Sources.run(s.deps).ok and s.mesh_queries == 1)
end)
test("plain report edits cannot hide a native source change or forge a snapshot", function()
    local s = fixture(); local result = Sources.run(s.deps)
    s.head.asset = object(25, { E .. "SkeletalMesh" })
    result.report.sources[1].asset.address, result.report.sources[1].asset.name = "25", s.head.asset.name
    assert(not Sources.verify(s.deps, result.snapshot))
    assert(not Sources.verify(s.deps, { report = Sources.run(s.deps).report }))
end)
test("static mesh assets and sparse unavailable material bindings remain explicit", function()
    local s = fixture(); local mesh = s.component(s.player, E .. "StaticMeshComponent")
    mesh.StaticMesh, mesh.parent = object(60, { E .. "StaticMesh" }), s.root
    s.player.meshes[#s.player.meshes + 1], s.root.children[#s.root.children + 1] = mesh, mesh
    local result = Sources.run(s.deps)
    assert(result.ok and result.report.sources[2].kind == "static" and result.snapshot.sources[2].asset == mesh.StaticMesh)
    mesh.GetNumMaterials = function() return 1 end
    result = Sources.run(s.deps)
    assert(result.ok and result.report.unsupported_visible_sources and result.report.sources[2].materials[1].material.present == false)
end)
test("aggregate material budget is shared by all component receivers", function()
    local s = fixture()
    for _ = 1, 8 do
        local mesh = s.component(s.player, E .. "SkeletalMeshComponent"); mesh.asset = s.head.asset
        for slot = 1, 32 do mesh.materials[slot] = s.head.materials[1] end
        s.player.meshes[#s.player.meshes + 1] = mesh
    end
    assert(not Sources.run(s.deps).ok)
end)
test("failed class getters retain partial plain evidence without a native snapshot", function()
    local s = fixture(); local groom = s:groom()
    groom.GroomGroupsDesc = { { HairLength = 0 / 0 } }
    local result = Sources.run(s.deps)
    assert(not result.ok and result.snapshot == nil and result.report.discovery_complete == false)
    assert(#result.report.sources == 2 and result.report.sources[1].asset.address == "20")
    assert(result.report.sources[2].kind == "groom" and result.report.sources[2].asset.address == "40")
end)
print("PASS " .. count .. " appearance source discovery groups")
