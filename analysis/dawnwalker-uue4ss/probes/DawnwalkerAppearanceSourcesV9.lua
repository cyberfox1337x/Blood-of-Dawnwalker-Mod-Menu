local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_appearance_sources_v9")

-- Read-only, current-player component inventory. Native references never belong in IPC.
local Sources = {}
local baselines = setmetatable({}, { __mode = "k" })
local PLAYER = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local ENGINE, HAIR = "/Script/Engine.", "/Script/HairStrandsCore."
local CLOTH = "/Script/ChaosClothAssetEngine."
local GROUP_NUMBERS = { "HairLength", "HairWidth", "HairRootScale", "HairTipScale", "HairShadowDensity",
    "HairRaytracingRadiusScale", "LODBias", "HairLengthScale" }
local GROUP_FLAGS = { "HairWidth_Override", "HairRootScale_Override", "HairTipScale_Override", "HairShadowDensity_Override",
    "HairRaytracingRadiusScale_Override", "bUseHairRaytracingGeometry", "bUseHairRaytracingGeometry_Override",
    "bUseStableRasterization", "bUseStableRasterization_Override", "bScatterSceneLighting", "bScatterSceneLighting_Override",
    "bSupportVoxelization", "bSupportVoxelization_Override", "HairLengthScale_Override" }
local function check(value, reason) if value ~= true then error(reason, 0) end end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function integer(value, maximum) return finite(value) and value >= 0 and value % 1 == 0 and value <= maximum end
local function valid(value) return value ~= nil and value:IsValid() == true end
local function text(value)
    if type(value) ~= "string" then value = value:ToString() end
    check(type(value) == "string" and #value <= 1024 and not value:find("[%z\1-\31\127]"), "Invalid native appearance name")
    return value
end
local function record(value, class)
    check(valid(value) and value:IsA(class) == true, "Appearance object is unavailable or has the wrong class: " .. class)
    local address, name = value:GetAddress(), text(value:GetFullName())
    check(finite(address) and address > 0 and not name:find("Default__", 1, true), "Appearance object identity is not an instance")
    return { address = tostring(address), name = name }
end
local function optional(value, class)
    if not valid(value) then return { present = false } end
    return record(value, class)
end
local function same(value, identity)
    return identity ~= nil and valid(value) and tostring(value:GetAddress()) == identity.address and value:GetFullName() == identity.name
end
local function flag(value)
    check(type(value) == "boolean" or value == 0 or value == 1, "Unsupported native appearance flag")
    return value == true or value == 1
end
local function vector(value)
    check(finite(value.X) and finite(value.Y) and finite(value.Z), "Invalid native appearance vector")
    return { X = value.X, Y = value.Y, Z = value.Z }
end
local function transform(value)
    local rotation = value.Rotation
    check(finite(rotation.X) and finite(rotation.Y) and finite(rotation.Z) and finite(rotation.W), "Invalid appearance quaternion")
    return { Translation = vector(value.Translation), Scale3D = vector(value.Scale3D),
        Rotation = { X = rotation.X, Y = rotation.Y, Z = rotation.Z, W = rotation.W } }
end
local function array(value, maximum)
    local ok, count = pcall(function() return value:GetArrayNum() end)
    if not ok then check(type(value) == "table", "Native appearance array is unavailable"); count = #value end
    check(integer(count, maximum), "Native appearance array exceeds its bound")
    local result = {}
    for index = 1, count do
        local element = value[index]
        local unwrapped, raw = pcall(function() return element:get() end)
        if unwrapped then element = raw end
        check(element ~= nil, "Native appearance array contains a missing item")
        result[#result + 1] = element
    end
    return result
end
local function equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not equal(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function inspect(deps, progress)
    check(type(deps) == "table" and deps.game_thread == true, "Appearance discovery requires the native game thread")
    check(type(deps.identity) == "table" and deps.identity.build_id == "25129649"
        and deps.identity.executable_sha256 == "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853",
        "Appearance discovery build identity mismatch")
    local player = deps.get_player()
    local report = { schema = 2, player = record(player, PLAYER), world = record(player:GetWorld(), ENGINE .. "World"),
        form = player.Form, is_wolf_form = player:IsInWolfForm(), actors = {}, sources = {},
        mutation_authorized = false, appearance_verified = false, unsupported_visible_sources = false }
    progress.report = report
    report.discovery_complete = false
    check((report.form == 0 or report.form == 1) and report.is_wolf_form == false, "Unsupported current appearance form")
    local head, root = player.HeadMesh, player.RootComponent
    report.head = record(head, ENGINE .. "SkeletalMeshComponent")
    report.root = record(root, ENGINE .. "SceneComponent")
    check(same(head:GetOwner(), report.player) and same(root:GetOwner(), report.player), "Player head/root ownership differs")
    local mesh_class = deps.static_find_object(ENGINE .. "MeshComponent")
    check(valid(mesh_class) and mesh_class:IsA("/Script/CoreUObject.Class"), "Native MeshComponent class is unavailable")
    local snapshot = { player = player, world = player:GetWorld(), head = head, root = root,
        player_identity = report.player, world_identity = report.world, head_identity = report.head,
        form = report.form, is_wolf_form = report.is_wolf_form, sources = {}, report = report }
    local actors, meshes, nodes, node_count, material_count, group_count = {}, {}, {}, 0, 0, 0
    local function actor_chain(actor)
        local chain, seen, current = {}, {}, actor
        for _ = 1, 4 do
            local identity = record(current, ENGINE .. "Actor")
            check(not seen[identity.address], "Appearance actor attachment cycle")
            seen[identity.address] = true
            chain[#chain + 1] = identity
            current = current:GetAttachParentActor()
            if same(current, report.player) then return chain end
        end
        error("Attached appearance actor does not reach the player within four parent links", 0)
    end
    local function add_actor(actor)
        local identity = record(actor, ENGINE .. "Actor")
        if actors[identity.address] then return end
        check(#report.actors < 9 and same(actor:GetWorld(), report.world), "Attached appearance actor budget/world differs")
        local chain = same(actor, report.player) and {} or actor_chain(actor)
        actors[identity.address] = actor
        report.actors[#report.actors + 1] = { identity = identity, parent_chain = chain,
            hidden = flag(actor.bHidden), root = optional(actor.RootComponent, ENGINE .. "SceneComponent") }
        for _, component in ipairs(array(actor:K2_GetComponentsByClass(mesh_class), 32)) do
            local component_identity = record(component, ENGINE .. "MeshComponent")
            check(same(component:GetOwner(), identity), "Enumerated appearance component has another owner")
            if not meshes[component_identity.address] then
                check(#snapshot.sources < 32, "Aggregate appearance mesh budget exceeded")
                local parent = component:GetAttachParent()
                local socket = component:GetAttachSocketName()
                local entry = { component = component, owner = actor, attach_parent = parent, native_attach_socket = socket,
                    material_refs = {}, record = { component = component_identity, owner = identity,
                        attach_parent = optional(parent, ENGINE .. "SceneComponent"), attach_socket = text(socket),
                        visible = flag(component:IsVisible()), hidden_in_game = flag(component.bHiddenInGame),
                        owner_hidden = flag(actor.bHidden), relative_transform = transform(component:GetRelativeTransform()),
                        world_transform = transform(component:K2_GetComponentToWorld()), materials = {} } }
                local observed = entry.record
                -- Preserve this plain record if a later class-specific getter fails.
                meshes[component_identity.address] = entry
                snapshot.sources[#snapshot.sources + 1], report.sources[#report.sources + 1] = entry, observed
                observed.classification = "appearance"
                if component:IsA("/Script/DogwoodUI.GameplayWidgetComponent")
                    and component:IsA("/Script/UMG.WidgetComponent") then
                    -- The observed combat prompts/indicators are UI surfaces, not character meshes.
                    observed.kind, observed.classification = "gameplay-widget", "non-appearance"
                    observed.exclusion_reason = "Gameplay widget surface"
                elseif component:IsA(CLOTH .. "ChaosClothComponent") then
                    observed.kind = "chaos-cloth"
                    entry.asset = component:GetClothAsset()
                    observed.asset = optional(entry.asset, CLOTH .. "ChaosClothAsset")
                    local skinned_asset = component:GetSkinnedAsset()
                    observed.skinned_asset = optional(skinned_asset, ENGINE .. "SkinnedAsset")
                    check((observed.asset.present == false and observed.skinned_asset.present == false)
                        or same(skinned_asset, observed.asset), "Cloth and skinned asset getters disagree")
                    observed.cloth = {
                        use_attached_parent_as_pose_component = flag(component.bUseAttachedParentAsPoseComponent),
                        bind_to_leader_component = flag(component.bBindToLeaderComponent),
                        enable_simulation = flag(component.bEnableSimulation),
                        suspend_simulation = flag(component.bSuspendSimulation),
                        simulation_enabled = flag(component:IsSimulationEnabled()),
                        simulation_suspended = flag(component:IsSimulationSuspended()),
                        blend_weight = component.BlendWeight, geometry_scale = component.ClothGeometryScale,
                    }
                    check(finite(observed.cloth.blend_weight) and finite(observed.cloth.geometry_scale),
                        "Cloth appearance scalars are not finite")
                    if valid(parent) and parent:IsA(ENGINE .. "SkinnedMeshComponent") then
                        entry.parent_skinned_asset = parent:GetSkinnedAsset()
                        observed.cloth.parent_skinned_asset = optional(entry.parent_skinned_asset, ENGINE .. "SkinnedAsset")
                    else
                        observed.cloth.parent_skinned_asset = { present = false }
                    end
                elseif component:IsA(ENGINE .. "SkeletalMeshComponent") then
                    observed.kind = "skeletal"
                    entry.asset = component:GetSkeletalMeshAsset()
                    observed.asset = optional(entry.asset, ENGINE .. "SkeletalMesh")
                elseif component:IsA(HAIR .. "GroomComponent") then
                    observed.kind = "groom"
                    entry.asset, entry.binding_asset, entry.source_skeletal_mesh = component.GroomAsset, component.BindingAsset, component.SourceSkeletalMesh
                    observed.asset = optional(entry.asset, HAIR .. "GroomAsset")
                    observed.binding_asset = optional(entry.binding_asset, HAIR .. "GroomBindingAsset")
                    observed.source_skeletal_mesh = optional(entry.source_skeletal_mesh, ENGINE .. "SkeletalMesh")
                    observed.bUseCards, observed.AttachmentName = flag(component.bUseCards), text(component.AttachmentName)
                    entry.groom_cache = component.GroomCache
                    observed.groom_cache = optional(entry.groom_cache, HAIR .. "GroomCache")
                    observed.groups = {}
                    for _, group in ipairs(array(component.GroomGroupsDesc, 16)) do
                        group_count = group_count + 1
                        check(group_count <= 64, "Aggregate groom group bound exceeded")
                        local plain = {}
                        for _, name in ipairs(GROUP_NUMBERS) do
                            check(finite(group[name]), "Groom group scalar is not finite: " .. name)
                            plain[name] = group[name]
                        end
                        for _, name in ipairs(GROUP_FLAGS) do plain[name] = flag(group[name]) end
                        observed.groups[#observed.groups + 1] = plain
                    end
                    if valid(entry.binding_asset) then
                        entry.binding_target_skeletal_mesh = entry.binding_asset.TargetSkeletalMesh
                        observed.binding_target_skeletal_mesh = optional(entry.binding_target_skeletal_mesh, ENGINE .. "SkeletalMesh")
                        observed.binding_groom = optional(entry.binding_asset.Groom, HAIR .. "GroomAsset")
                        observed.binding_type = entry.binding_asset.GroomBindingType
                        check(integer(observed.binding_type, 16), "Invalid native groom binding type")
                        observed.binding_matches_groom = same(entry.binding_asset.Groom, observed.asset)
                        observed.binding_matches_parent = valid(parent) and parent:IsA(ENGINE .. "SkeletalMeshComponent") == true
                            and same(parent:GetSkeletalMeshAsset(), observed.binding_target_skeletal_mesh)
                    end
                    observed.groom = { binding_asset = observed.binding_asset, use_cards = observed.bUseCards,
                        attachment_name = observed.AttachmentName, groups = observed.groups, cache = observed.groom_cache }
                elseif component:IsA(ENGINE .. "StaticMeshComponent") and not component:IsA(ENGINE .. "InstancedStaticMeshComponent") then
                    observed.kind = "static"
                    entry.asset = component.StaticMesh
                    observed.asset = optional(entry.asset, ENGINE .. "StaticMesh")
                else
                    observed.kind, observed.unsupported_reason = "unsupported", "Unfamiliar or instanced mesh component geometry"
                end
                if observed.classification == "appearance" and observed.kind ~= "unsupported" and not valid(entry.asset) then
                    -- Reached only after a successful native asset getter; getter errors still fail discovery.
                    observed.classification = "empty-geometry"
                    observed.exclusion_reason = "Source component has no loaded asset"
                end
                local count = component:GetNumMaterials()
                check(integer(count, 32), "Appearance material slot bound exceeded")
                material_count = material_count + count
                check(material_count <= 256, "Aggregate appearance material bound exceeded")
                for slot = 0, count - 1 do
                    local material = component:GetMaterial(slot)
                    entry.material_refs[slot + 1] = material
                    observed.materials[#observed.materials + 1] = { slot = slot, material = optional(material, ENGINE .. "MaterialInterface") }
                    if not valid(material) then
                        observed.missing_material_bindings = true
                        if observed.classification == "appearance" then
                            observed.unsupported_reason = "Source material binding is unavailable"
                        end
                    end
                end
                if observed.unsupported_reason and observed.visible and not observed.hidden_in_game and not observed.owner_hidden then
                    report.unsupported_visible_sources = true
                end
            end
        end
    end
    add_actor(player)
    local function visit(node, parent, depth)
        check(depth <= 12, "Appearance scene graph depth exceeds twelve")
        local identity = record(node, ENGINE .. "SceneComponent")
        check(not nodes[identity.address], "Appearance scene graph contains a cycle or duplicate child")
        nodes[identity.address], node_count = true, node_count + 1
        check(node_count <= 128, "Appearance scene graph exceeds 128 components")
        if parent then check(same(node:GetAttachParent(), parent), "Appearance child/parent attachment disagrees") end
        add_actor(node:GetOwner())
        local count = node:GetNumChildrenComponents()
        check(integer(count, 128), "Appearance child count exceeds bounds")
        for index = 0, count - 1 do visit(node:GetChildComponent(index), identity, depth + 1) end
    end
    visit(root, nil, 0)
    check(meshes[report.head.address] ~= nil, "Actual head is absent from player mesh enumeration")
    table.sort(report.actors, function(a, b) return a.identity.address < b.identity.address end)
    table.sort(snapshot.sources, function(a, b) return a.record.component.address < b.record.component.address end)
    table.sort(report.sources, function(a, b) return a.component.address < b.component.address end)
    report.mesh_count, report.actor_count, report.scene_node_count, report.material_count, report.groom_group_count =
        #report.sources, #report.actors, node_count, material_count, group_count
    check(same(deps.get_player(), report.player) and same(player:GetWorld(), report.world) and same(player.HeadMesh, report.head)
        and same(player.RootComponent, report.root) and player.Form == report.form and player:IsInWolfForm() == report.is_wolf_form,
        "Player appearance identity changed during discovery")
    report.discovery_complete = true
    return snapshot
end

function Sources.run(deps)
    local progress = {}
    local ok, snapshot = pcall(inspect, deps, progress)
    if not ok then return { ok = false, reason = tostring(snapshot):sub(1, 1024), report = progress.report, mutation_authorized = false } end
    baselines[snapshot] = copy(snapshot.report)
    return { ok = true, report = snapshot.report, snapshot = snapshot, mutation_authorized = false }
end

function Sources.verify(deps, snapshot)
    local baseline = type(snapshot) == "table" and baselines[snapshot]
    if not baseline then return false, "Appearance snapshot is missing or unrecognized" end
    local current = Sources.run(deps)
    if not current.ok then return false, current.reason end
    if not equal(baseline, current.report) then return false, "Appearance membership, binding, visibility, pose or attachment changed" end
    return true
end

return Sources
