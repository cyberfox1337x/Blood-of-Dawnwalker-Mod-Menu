local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_material_read_only_probe_tests")

local path = assert(arg[1], "Pass the visual probe module path")
local file = assert(io.open(path, "r"))
local source = file:read("*a")
file:close()
for _, pattern in ipairs({ "SetVectorParameter", "SetScalarParameter", "CreateDynamicMaterial", "SetMaterial%s*%(",
    "ExecuteConsoleCommand", "RegisterKeyBind", "StaticLoadObject", "io%.open", "os%.execute" }) do
    assert(not source:find(pattern), "visual probe must remain read-only: " .. pattern)
end
local Probe = assert(dofile(path))
local function object(address, name, classes)
    local result = { address = address, name = name, classes = classes, valid = true }
    function result:IsValid() return self.valid end
    function result:IsA(class) for _, expected in ipairs(self.classes) do if expected == class then return true end end; return false end
    function result:GetAddress() return self.address end
    function result:GetFullName() return self.name end
    return result
end
local function fname(name) return { ToString = function() return name end } end
local function parameter(name, value)
    return { ParameterInfo = { Name = fname(name), Association = 0, Index = -1 }, ParameterValue = value }
end
local function fixture()
    local world = object(10, "World Test.World", { "/Script/Engine.World" })
    local player = object(20, "DawnwalkerPlayerCharacter World.Player", { "/Script/Dawnwalker.DawnwalkerPlayerCharacter" })
    player.Form = 1
    player.wolf_form = false
    function player:IsInWolfForm() return self.wolf_form end
    function player:GetWorld() return world end
    local base = object(50, "Material /Game/Observed.Base", { "/Script/Engine.MaterialInterface" })
    local parent = object(40, "MaterialInstanceConstant /Game/Observed.Parent", { "/Script/Engine.MaterialInterface", "/Script/Engine.MaterialInstance", "/Script/Engine.MaterialInstanceConstant" })
    parent.Parent = base
    parent.ScalarParameterValues = {}
    parent.TextureParameterValues = {}
    parent.VectorParameterValues = { parameter("ObservedTint", { R = 0.3, G = 0.4, B = 0.5, A = 1 }) }
    local dynamic = object(30, "MaterialInstanceDynamic Player.Instance", { "/Script/Engine.MaterialInterface", "/Script/Engine.MaterialInstance", "/Script/Engine.MaterialInstanceDynamic" })
    dynamic.Parent = parent
    dynamic.VectorParameterValues = {}
    dynamic.ScalarParameterValues = { parameter("ObservedAmount", 0.7) }
    dynamic.TextureParameterValues = { parameter("ObservedTexture", object(70, "Texture2D /Game/Observed.Texture", { "/Script/Engine.Texture" })) }
    local reads = {}
    local function read_parameter(material, kind, info)
        reads[#reads + 1] = { kind = kind, info = info }
        local current = material
        while current.Parent do
            for _, entry in ipairs(current[kind .. "ParameterValues"]) do
                local observed = entry.ParameterInfo
                if observed.Name:ToString() == info.Name:ToString() and observed.Association == info.Association
                    and observed.Index == info.Index then return entry.ParameterValue end
            end
            current = current.Parent
        end
        error("missing test parameter")
    end
    function dynamic:K2_GetScalarParameterValueByInfo(info) return read_parameter(self, "Scalar", info) end
    function dynamic:K2_GetVectorParameterValueByInfo(info) return read_parameter(self, "Vector", info) end
    function dynamic:K2_GetTextureParameterValueByInfo(info) return read_parameter(self, "Texture", info) end
    function parent:K2_GetVectorParameterValue(name)
        return read_parameter(self, "Vector", { Name = name, Association = 0, Index = -1 })
    end
    local mesh = object(60, "SkeletalMeshComponent Player.Head", { "/Script/Engine.SkeletalMeshComponent" })
    local asset = object(61, "SkeletalMesh /Game/Observed.Head", { "/Script/Engine.SkeletalMesh" })
    function mesh:GetSkeletalMeshAsset() return asset end
    function mesh:GetOwner() return player end
    function mesh:GetNumMaterials() return 1 end
    function mesh:GetMaterial(index) assert(index == 0); return dynamic end
    function mesh:GetMaterialSlotNames() return { fname("ObservedSlot") } end
    local mesh_class = object(80, "Class /Script/Engine.SkeletalMeshComponent", { "/Script/CoreUObject.Class" })
    player.HeadMesh = mesh
    function player:K2_GetComponentsByClass(class) assert(class == mesh_class); return { mesh } end
    local library = object(90, "KismetSystemLibrary /Script/Engine.Default__KismetSystemLibrary", { "/Script/Engine.KismetSystemLibrary" })
    function library:GetConsoleVariableIntValue(name) assert(name == "r.Fog" or name == "r.VolumetricFog"); return 1 end
    local deps = { game_thread = true,
        identity = { build_id = "25129649", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853" },
        get_player = function() return player end,
        static_find_object = function(pathname)
            if pathname == "/Script/Engine.SkeletalMeshComponent" then return mesh_class end
            if pathname == "/Script/Engine.Default__KismetSystemLibrary" then return library end
            error("unexpected static lookup")
        end }
    return deps, { player = player, world = world, mesh = mesh, dynamic = dynamic, parent = parent, base = base,
        library = library, asset = asset, reads = reads }
end
local total = 0
local function test(name, action) action(); total = total + 1; print("PASS " .. name) end

test("inherited parameters preserve source layer, slot name, and full parameter identity", function()
    local deps, objects = fixture()
    local result = Probe.run(deps)
    assert(result.ok and not result.mutation_authorized and not result.gameplay_verified)
    local slot = result.materials[1].materials[1]
    assert(slot.ok and slot.slot == 0 and slot.slot_name == "ObservedSlot" and #slot.chain == 3)
    assert(slot.chain[1].dynamic and slot.chain[3].base_material)
    local tint = slot.chain[2].overrides.vector[1]
    assert(tint.name == "ObservedTint" and tint.association == 0 and tint.index == -1 and tint.g == 0.4)
    assert(result.form_name == "Vampire" and result.fog == nil and result.scope == "eye-material-discovery")
    assert(result.head_mesh.address == "60" and not result.is_wolf_form and result.materials[1].asset.address == "61")
    assert(result.head_mesh.observed_in_player_meshes)
    assert(#slot.effective_parameters == 3 and slot.player_slot_references == 1)
    local readback = slot.effective_parameters[3]
    assert(readback.ok and readback.kind == "vector" and readback.nearest_override_depth == 1 and readback.readback.g == 0.4)
    assert(objects.reads[3].info == objects.parent.VectorParameterValues[1].ParameterInfo)
end)
test("wrong build, hash, or thread rejects before any player access", function()
    for _, field in ipairs({ "build", "hash", "thread" }) do
        local deps = fixture()
        deps.get_player = function() error("unexpected player read") end
        if field == "build" then deps.identity.build_id = "old"
        elseif field == "hash" then deps.identity.executable_sha256 = "bad"
        else deps.game_thread = false end
        local result = Probe.run(deps)
        assert(not result.ok and not result.reason:find("unexpected player read", 1, true))
    end
end)
test("parent cycles fail only the affected slot without manufactured parameters", function()
    local deps, objects = fixture()
    objects.parent.Parent = objects.dynamic
    local result = Probe.run(deps)
    assert(result.ok and not result.materials[1].materials[1].ok and result.materials[1].materials[1].chain == nil)
    assert(result.materials[1].materials[1].reason:find("cycle", 1, true))
end)
test("invalid color and layer metadata fail the material slot", function()
    for _, field in ipairs({ "color", "association", "index" }) do
        local deps, objects = fixture()
        local tint = objects.parent.VectorParameterValues[1]
        if field == "color" then tint.ParameterValue.R = 0 / 0
        elseif field == "association" then tint.ParameterInfo.Association = 9
        else tint.ParameterInfo.Index = 0.5 end
        assert(not Probe.run(deps).materials[1].materials[1].ok)
    end
end)
test("foreign mesh owner and excessive component count fail safely", function()
    local deps, objects = fixture()
    function objects.mesh:GetOwner() return objects.world end
    assert(not Probe.run(deps).ok)
    deps, objects = fixture()
    function objects.player:K2_GetComponentsByClass() return { GetArrayNum = function() return 33 end } end
    assert(not Probe.run(deps).ok)
end)
test("form transition discards the complete snapshot", function()
    local deps, objects = fixture()
    local reads = 0
    deps.get_player = function() reads = reads + 1; if reads > 1 then objects.player.Form = 0 end; return objects.player end
    local result = Probe.run(deps)
    assert(not result.ok and result.materials == nil and result.fog == nil)
end)
test("eye capture never queries fog or any console variable", function()
    local deps, objects = fixture()
    function objects.library:GetConsoleVariableIntValue() error("unrelated console getter invoked") end
    local original = deps.static_find_object
    deps.static_find_object = function(pathname)
        assert(pathname == "/Script/Engine.SkeletalMeshComponent", "unexpected unrelated class lookup")
        return original(pathname)
    end
    local result = Probe.run(deps)
    assert(result.ok and result.fog == nil and result.materials[1].materials[1].ok)
end)
test("reported names cannot inject extra report lines", function()
    local deps, objects = fixture()
    objects.parent.VectorParameterValues[1].ParameterInfo.Name = fname("Tint\nInjected%")
    local result = Probe.run(deps)
    assert(Probe.format_lines(result):find("Tint%0AInjected%25", 1, true))
end)

test("effective readback deduplicates inherited overrides but keeps distinct layer identities", function()
    local deps, objects = fixture()
    objects.dynamic.VectorParameterValues = { parameter("ObservedTint", { R = 0.8, G = 0.1, B = 0.2, A = 1 }) }
    local layer = parameter("ObservedTint", { R = 0.9, G = 0.2, B = 0.3, A = 1 })
    layer.ParameterInfo.Association, layer.ParameterInfo.Index = 1, 0
    objects.parent.VectorParameterValues[2] = layer
    local slot = Probe.run(deps).materials[1].materials[1]
    assert(slot.ok and #slot.effective_parameters == 4)
    assert(slot.effective_parameters[2].nearest_override_depth == 0 and slot.effective_parameters[2].readback.r == 0.8)
    assert(slot.effective_parameters[4].association == 1 and slot.effective_parameters[4].readback.r == 0.9)
end)

test("constant getter never drops layer identity or invents a fallback color", function()
    local deps, objects = fixture()
    function objects.mesh:GetMaterial() return objects.parent end
    local result = Probe.run(deps)
    assert(result.ok and result.materials[1].materials[1].effective_parameters[1].readback.r == 0.3)
    objects.parent.VectorParameterValues[1].ParameterInfo.Association = 1
    objects.parent.VectorParameterValues[1].ParameterInfo.Index = 0
    function objects.parent:K2_GetVectorParameterValue() error("unsafe name-only getter invoked") end
    local entry = Probe.run(deps).materials[1].materials[1].effective_parameters[1]
    assert(not entry.ok and entry.readback == nil and entry.reason:find("preserves this parameter identity", 1, true))
end)

test("native getter failure keeps source observations and a per-parameter error", function()
    local deps, objects = fixture()
    function objects.dynamic:K2_GetVectorParameterValueByInfo() error("native marshalling unavailable") end
    local slot = Probe.run(deps).materials[1].materials[1]
    assert(slot.ok and slot.chain[2].overrides.vector[1].r == 0.3)
    local entry = slot.effective_parameters[3]
    assert(not entry.ok and entry.readback == nil and entry.reason:find("native marshalling unavailable", 1, true))
end)

test("duplicate parameter identities are rejected rather than selecting an arbitrary original", function()
    local deps, objects = fixture()
    objects.parent.VectorParameterValues[2] = objects.parent.VectorParameterValues[1]
    local slot = Probe.run(deps).materials[1].materials[1]
    assert(not slot.ok and slot.reason:find("duplicate parameter identity", 1, true))
end)

test("shared material slot references are reported without claiming exclusive ownership", function()
    local deps, objects = fixture()
    function objects.mesh:GetNumMaterials() return 2 end
    function objects.mesh:GetMaterial() return objects.dynamic end
    function objects.mesh:GetMaterialSlotNames() return { fname("ObservedSlot"), fname("OtherSlot") } end
    local result = Probe.run(deps)
    assert(result.ok and result.materials[1].materials[1].player_slot_references == 2)
    assert(result.materials[1].materials[2].player_slot_references == 2)
    assert(result.limitation:find("exclusive material ownership", 1, true))
end)

test("mesh, asset, slot, parent, and head changes discard the entire snapshot", function()
    for _, change in ipairs({ "mesh", "asset", "slot_name", "slot_material", "parent", "head", "slot_count", "owner" }) do
        local deps, objects = fixture()
        local player_reads = 0
        deps.get_player = function()
            player_reads = player_reads + 1
            if player_reads > 1 then
                if change == "mesh" then function objects.player:K2_GetComponentsByClass() return {} end
                elseif change == "asset" then objects.asset.address = 999
                elseif change == "slot_name" then function objects.mesh:GetMaterialSlotNames() return { fname("ChangedSlot") } end
                elseif change == "slot_material" then function objects.mesh:GetMaterial() return objects.parent end
                elseif change == "parent" then objects.dynamic.Parent = objects.base
                elseif change == "head" then objects.player.HeadMesh = nil
                elseif change == "slot_count" then function objects.mesh:GetNumMaterials() return 0 end
                else function objects.mesh:GetOwner() return objects.world end end
            end
            return objects.player
        end
        local result = Probe.run(deps)
        assert(not result.ok and result.materials == nil and result.reason, change)
    end
end)

test("wolf transformation is distinguished from the human/vampire enum", function()
    local deps, objects = fixture()
    objects.player.wolf_form = true
    assert(Probe.run(deps).is_wolf_form)
    local player_reads = 0
    deps.get_player = function()
        player_reads = player_reads + 1
        if player_reads > 1 then objects.player.wolf_form = false end
        return objects.player
    end
    assert(not Probe.run(deps).ok)
end)

test("duplicate meshes and slot-name count mismatch fail closed", function()
    local deps, objects = fixture()
    function objects.player:K2_GetComponentsByClass() return { objects.mesh, objects.mesh } end
    assert(not Probe.run(deps).ok)
    deps, objects = fixture()
    function objects.mesh:GetMaterialSlotNames() return {} end
    assert(not Probe.run(deps).ok)
end)

test("form changes during the topology recheck cannot escape the final state guard", function()
    local deps, objects = fixture()
    local slot_reads = 0
    function objects.mesh:GetMaterialSlotNames()
        slot_reads = slot_reads + 1
        if slot_reads > 1 then objects.player.Form = 0 end
        return { fname("ObservedSlot") }
    end
    local result = Probe.run(deps)
    assert(not result.ok and result.materials == nil and result.reason:find("form changed", 1, true))
end)
test("global parameter budget stops traversal and discards the entire snapshot", function()
    local deps, objects = fixture()
    for index = 1, 128 do
        objects.parent.VectorParameterValues[index] = parameter("ObservedTint" .. index, { R = 0.3, G = 0.4, B = 0.5, A = 1 })
    end
    local material_reads = 0
    function objects.mesh:GetNumMaterials() return 32 end
    function objects.mesh:GetMaterial() material_reads = material_reads + 1; return objects.dynamic end
    function objects.mesh:GetMaterialSlotNames()
        local names = {}
        for index = 1, 32 do names[index] = fname("ObservedSlot" .. index) end
        return names
    end
    local result = Probe.run(deps)
    assert(not result.ok and result.materials == nil and result.reason:find("global parameters budget exhausted", 1, true))
    assert(material_reads <= 16 and #objects.reads < 2048)
end)

test("global material-layer budget stops across multiple player meshes", function()
    local deps, objects = fixture()
    local all = {}
    for component_index = 1, 5 do
        local mesh = object(500 + component_index, "SkeletalMeshComponent Player.Part" .. component_index, { "/Script/Engine.SkeletalMeshComponent" })
        function mesh:GetOwner() return objects.player end
        function mesh:GetSkeletalMeshAsset() return objects.asset end
        function mesh:GetNumMaterials() return 32 end
        function mesh:GetMaterial() return objects.dynamic end
        function mesh:GetMaterialSlotNames()
            local names = {}
            for index = 1, 32 do names[index] = fname("Slot" .. index) end
            return names
        end
        all[component_index] = mesh
    end
    function objects.player:K2_GetComponentsByClass() return all end
    local result = Probe.run(deps)
    assert(not result.ok and result.materials == nil and result.reason:find("global material_layers budget exhausted", 1, true))
end)
print("Eye material read-only probe: " .. total .. " tests passed")
