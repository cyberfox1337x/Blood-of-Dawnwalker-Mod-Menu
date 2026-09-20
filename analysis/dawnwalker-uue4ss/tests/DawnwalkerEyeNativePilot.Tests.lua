local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_native_pilot_tests")
local source = assert(arg[1], "Pass DawnwalkerEyeNativePilot.lua")
local function fname(name) return { ToString = function() return name end } end
local function obj(address, name, classes)
    local value = { address = address, name = name, valid = true }
    function value:IsValid() return self.valid end
    function value:GetAddress() return self.address end
    function value:GetFullName() return self.name end
    function value:GetFName() return fname(self.name:match("([^%.]+)$")) end
    function value:IsA(class) for _, expected in ipairs(classes) do if expected == class then return true end end return false end
    return value
end
local function fixture()
    local Pilot = dofile(source)
    local state = { creates = 0, writes = 0, original_writes = 0, bindings = {}, originals = {}, rollback_writes = 0 }
    local player = obj(1, "BP_PlayerCharacter_C Test.Player", { "/Script/Dawnwalker.DawnwalkerPlayerCharacter" })
    local world = obj(2, "World Test.World", { "/Script/Engine.World" })
    local head = obj(3, "SkeletalMeshComponentBudgeted Test.Player.Face Mesh", { "/Script/Engine.SkeletalMeshComponent" })
    local asset = obj(4, "SkeletalMesh /Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/SK_HMA_Coen_Head_A.SK_HMA_Coen_Head_A", { "/Script/Engine.SkeletalMesh" })
    local mesh_class = obj(5, "Class SkeletalMeshComponent", { "/Script/CoreUObject.Class" })
    player.Form, player.HeadMesh = 0, head
    function player:IsInWolfForm() return false end
    function player:GetWorld() return world end
    function player:K2_GetComponentsByClass(class) assert(class == mesh_class); return { head } end
    function head:GetOwner() return player end
    function head:GetSkeletalMeshAsset() return asset end
    local names = { fname("head"), fname("teeth"), fname("saliva"), fname("shader_eyeLeft_shader"), fname("shader_eyeRight_shader") }
    function head:GetMaterialSlotNames() return names end
    function head:GetNumMaterials() return 5 end
    function head:GetMaterial(slot) assert(slot == 3 or slot == 4); return state.bindings[slot] end
    for slot = 3, 4 do
        local side = slot == 3 and "L" or "R"
        local material = obj(10 + slot, "MaterialInstanceConstant /Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/Materials/MI_Coen_Eyeball_" .. side .. ".MI_Coen_Eyeball_" .. side,
            { "/Script/Engine.MaterialInstanceConstant" })
        material.VectorParameterValues = {}
        material.Parent = obj(50, "Material /Game/_Dawnwalker/Shaders/Characters/Face/M_EyeRefractive_Optimized.M_EyeRefractive_Optimized", { "/Script/Engine.MaterialInterface" })
        material.values = { Leukocoria_Color = { R = 0.635, G = 0.542, B = 0.306, A = 1 }, CloudyIrisColor = { R = 0.02676, G = 0.027612, B = 0.03, A = 1 } }
        for _, name in ipairs({ "Leukocoria_Color", "CloudyIrisColor" }) do
            material.VectorParameterValues[#material.VectorParameterValues + 1] = {
                ParameterInfo = { Name = fname(name), Association = 2, Index = -1 }, ParameterValue = material.values[name] }
        end
        function material:K2_GetVectorParameterValue(name)
            assert(type(name) == "table" and name.ToString, "native FName required")
            return self.values[name:ToString()]
        end
        function material:SetVectorParameterValueByInfo() state.original_writes = state.original_writes + 1; error("shared asset setter prohibited") end
        state.bindings[slot], state.originals[slot] = material, material
    end
    function head:CreateDynamicMaterialInstance(slot, parent, optional_name)
        assert(parent == state.originals[slot] and type(optional_name) == "table" and optional_name.ToString)
        state.creates = state.creates + 1
        local mid = obj(100 + state.creates, "MaterialInstanceDynamic Test.Player.Face Mesh." .. optional_name:ToString(), { "/Script/Engine.MaterialInstanceDynamic" })
        mid.Parent, mid.values = parent, {}
        function mid:GetOuter() return head end
        function mid:K2_GetVectorParameterValueByInfo(info)
            assert(info.Association == 2 and info.Index == -1)
            local value = self.values[info.Name:ToString()] or parent.values[info.Name:ToString()]
            if state.bad_readback and self.values[info.Name:ToString()] then return { R = 0, G = 0, B = 0, A = 1 } end
            return value
        end
        function mid:SetVectorParameterValueByInfo(info, color)
            state.writes = state.writes + 1
            self.values[info.Name:ToString()] = color
            if state.setter_throws then error("setter failed after write") end
        end
        state.bindings[slot] = mid
        if state.create_failure == state.creates then error("creation failed after binding") end
        if state.foreign_outer then function mid:GetOuter() return player end end
        if state.form_change then player.Form = 1 end
        return mid
    end
    function head:SetMaterial(slot, original)
        assert(original == state.originals[slot], "rollback may bind only preserved originals")
        state.rollback_writes = state.rollback_writes + 1
        state.bindings[slot] = original
    end
    local deps = { game_thread = true, identity = { build_id = "25129649", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853" },
        boot_id = "1000-123", nonce = string.rep("a", 32), get_player = function() return player end,
        static_find_object = function(class) assert(class == "/Script/Engine.SkeletalMeshComponent"); return mesh_class end }
    local function run(operation)
        deps.operation = operation
        deps.intent = operation == "observe" and "eye-observe" or operation == "color-roundtrip" and "eye-color-roundtrip" or "eye-private-instance-roundtrip"
        return Pilot.run(deps)
    end
    return state, deps, run, Pilot, { player = player, world = world, head = head, asset = asset, names = names }
end
local count = 0
local function test(name, run) run(); count = count + 1; print("PASS " .. name) end

test("observed Global2 native FName getters establish a baseline without writes", function()
    local state, _, run = fixture()
    local result = run("observe")
    assert(result.ok and result.native_original_getters_verified and result.baseline.eyes[1].parameters.Leukocoria_Color.association == 2)
    assert(state.creates == 0 and state.writes == 0 and not result.gameplay_verified)
end)
test("wrong thread build intent and missing baseline reject before mutation", function()
    for _, change in ipairs({ "thread", "build", "intent", "baseline" }) do
        local state, deps, run, Pilot = fixture()
        local result
        if change == "baseline" then result = run("color-roundtrip")
        else
            deps.operation, deps.intent = "observe", "eye-observe"
            if change == "thread" then deps.game_thread = false elseif change == "build" then deps.identity.build_id = "old" else deps.intent = "read-only" end
            result = Pilot.run(deps)
        end
        assert(not result.ok and state.creates == 0 and state.writes == 0)
    end
end)
test("Layer0 is not mistaken for Global2 and getter disagreement cannot authorize mutation", function()
    local state, _, run = fixture()
    state.originals[3].VectorParameterValues[1].ParameterInfo.Association = 0
    assert(not run("observe").ok and not run("color-roundtrip").ok and state.creates == 0)
    state, _, run = fixture()
    state.originals[3].K2_GetVectorParameterValue = function() return { R = 0, G = 0, B = 0, A = 1 } end
    assert(not run("observe").ok and state.creates == 0)
end)
test("private material roundtrip binds only private children and restores exact originals", function()
    local state, _, run = fixture()
    assert(run("observe").ok)
    local result = run("private-instance-roundtrip")
    assert(result.ok and result.native_roundtrip_verified and result.original_bindings_restored and result.original_values_verified)
    assert(state.creates == 2 and state.writes == 0 and state.rollback_writes == 2 and state.original_writes == 0)
    assert(state.bindings[3] == state.originals[3] and state.bindings[4] == state.originals[4])
end)
test("bounded color roundtrip verifies then restores without claiming a persistent or visible change", function()
    local state, _, run = fixture()
    assert(run("observe").ok and run("private-instance-roundtrip").ok)
    local result = run("color-roundtrip")
    assert(result.ok and result.native_roundtrip_verified and not result.applied_in_game and not result.visual_effect_verified)
    assert(result.readbacks[1].desired.R == 0.306 and result.readbacks[1].desired.B == 0.635 and result.readbacks[1].desired.A == 1)
    assert(state.writes == 2 and state.original_writes == 0 and state.bindings[3] == state.originals[3] and state.bindings[4] == state.originals[4])
    assert(not run("color-roundtrip").ok and state.writes == 2, "one native pilot attempt per operation/boot")
end)
test("partial creation and throwing setters still restore both original bindings", function()
    for _, failure in ipairs({ "creation", "setter", "readback" }) do
        local state, _, run = fixture()
        assert(run("observe").ok and run("private-instance-roundtrip").ok)
        state.creates, state.rollback_writes = 0, 0
        if failure == "creation" then state.create_failure = 2 elseif failure == "setter" then state.setter_throws = true else state.bad_readback = true end
        local result = run("color-roundtrip")
        assert(not result.ok and result.original_bindings_restored and result.original_values_verified)
        assert(state.bindings[3] == state.originals[3] and state.bindings[4] == state.originals[4] and state.original_writes == 0)
    end
end)
test("changed pawn world asset or slot invalidates baseline before creating materials", function()
    for _, field in ipairs({ "player", "world", "asset", "slot" }) do
        local state, _, run, _, objects = fixture()
        assert(run("observe").ok)
        if field == "slot" then objects.names[4] = fname("other") else objects[field].address = 999 end
        assert(not run("color-roundtrip").ok and state.creates == 0)
    end
end)
test("same-name parent replacement rejects before private material creation", function()
    local state, _, run = fixture()
    assert(run("observe").ok)
    state.originals[3].Parent.address = 900
    assert(not run("color-roundtrip").ok and state.creates == 0)
end)
test("form change during creation forbids a color write or restoring an old form binding", function()
    local state, _, run = fixture()
    assert(run("observe").ok and run("private-instance-roundtrip").ok)
    state.creates, state.rollback_writes = 0, 0
    state.form_change = true
    local result = run("color-roundtrip")
    assert(not result.ok and not result.original_bindings_restored and #result.restoration_failures > 0)
    assert(state.writes == 0 and state.rollback_writes == 0)
end)
test("foreign material outer never receives color and is not overwritten on failed recovery", function()
    local state, _, run = fixture()
    assert(run("observe").ok and run("private-instance-roundtrip").ok)
    state.creates, state.rollback_writes = 0, 0
    state.foreign_outer = true
    local result = run("color-roundtrip")
    assert(not result.ok and not result.original_bindings_restored and state.writes == 0 and state.rollback_writes == 0)
end)
test("color cannot skip verified private-instance restoration", function()
    local state, _, run = fixture()
    assert(run("observe").ok)
    local result = run("color-roundtrip")
    assert(not result.ok and state.creates == 0 and state.writes == 0)
end)
print("Eye native pilot: " .. count .. " tests passed")
