local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_human_iris_scalar_roundtrip_tests")
local source = assert(arg[1], "Pass DawnwalkerHumanIrisRoundtripProbe.lua")
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
        material.ScalarParameterValues = {}
        material.scalar_values = { IrisColor1_U = 0.671602, IrisColor1_V = slot == 3 and 0.3344 or 0.402668,
            IrisColor2_U = 0.184, IrisColor2_V = 0.629203, IrisColorBalance = 0.87497,
            IrisColorBalanceSmoothness = 0.136762, Iris_Saturation = 1.153279, Iris_Value = 1.625103, Emissivnes = 300 }
        for name, value in pairs(material.scalar_values) do
            material.ScalarParameterValues[#material.ScalarParameterValues + 1] = {
                ParameterInfo = { Name = fname(name), Association = 2, Index = -1 }, ParameterValue = value }
        end
        function material:K2_GetScalarParameterValue(name) return self.scalar_values[name:ToString()] end
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
        function mid:K2_GetScalarParameterValueByInfo(info)
            assert(info.Association == 2 and info.Index == -1)
            local name = info.Name:ToString()
            if state.bad_readback and self.values[name] ~= nil then return -99 end
            if state.guard_changed and name == "IrisColorBalance" and state.writes > 0 then return 0 end
            return self.values[name] or parent.scalar_values[name]
        end
        function mid:SetScalarParameterValueByInfo(info, value)
            state.writes = state.writes + 1
            self.values[info.Name:ToString()] = value
            if state.setter_form_change then player.Form = 1 end
            if state.setter_throws then error("scalar setter failed after write") end
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
        static_find_object = function(class)
            if class == "/Script/Engine.SkeletalMeshComponent" then return mesh_class end
            assert(class:match("Test.Player.Face Mesh.IrisColor[12]_U$"))
            return state.existing_named_material
        end }
    state.capture_phases = {}
    deps.intent = "human-iris-pair-roundtrip"
    deps.capture_callback = function(phase, sample)
        state.capture_phases[#state.capture_phases + 1] = phase
        assert(sample.phase == phase and sample.form == 0 and sample.baseline_id == deps.boot_id .. ":" .. deps.nonce)
        if state.capture_failure == phase then error("capture failed " .. phase) end
        if state.foreign_capture_binding == phase then state.bindings[3] = state.originals[4] end
        if state.capture_asset_change == phase then asset.address = 999 end
        if state.bad_receipt == phase then return { ok = true, phase = "other", nonce = deps.nonce } end
        if state.mutate_sample then sample.eyes[1].parameters.IrisColor1_U.value = -999 end
        return { ok = true, phase = phase, nonce = deps.nonce, boot_id = state.bad_boot and "999-999" or deps.boot_id, evidence = "fixture-only" }
    end
    local function run() return Pilot.run(deps) end
    return state, deps, run, Pilot, { player = player, world = world, head = head, asset = asset, names = names }
end
local count = 0
local function test(name, fn) fn(); count = count + 1; print("PASS " .. name) end
test("known scalar pairs swap on private eyes with three matched captures and exact originals", function()
    local state, _, run = fixture()
    local result = run()
    assert(result.ok, tostring(result.reason))
    assert(result.scalar_swap_readback_verified and result.original_bindings_restored and result.original_values_verified)
    assert(state.creates == 2 and state.writes == 8 and state.rollback_writes == 2 and state.original_writes == 0)
    assert(table.concat(state.capture_phases, ",") == "baseline,changed,restored" and #result.captures == 3)
    local changed = result.captures[2].native_readback.eyes
    assert(changed[1].parameters.IrisColor1_U.value == 0.184 and changed[1].parameters.IrisColor2_U.value == 0.671602)
    assert(changed[1].parameters.IrisColor2_V.value == 0.3344 and changed[2].parameters.IrisColor2_V.value == 0.402668)
    assert(changed[1].parameters.IrisColorBalance.value == 0.87497 and changed[1].parameters.Leukocoria_Color.value.R == 0.635)
    assert(not result.applied_in_game and not result.visual_effect_verified and state.bindings[3] == state.originals[3] and state.bindings[4] == state.originals[4])
end)
test("required callback thread build intent and human form reject before creation", function()
    for _, field in ipairs({ "callback", "thread", "build", "intent", "form" }) do
        local state, deps, run, _, objects = fixture()
        if field == "callback" then deps.capture_callback = nil elseif field == "thread" then deps.game_thread = false
        elseif field == "build" then deps.identity.build_id = "old" elseif field == "intent" then deps.intent = "eye-observe" else objects.player.Form = 1 end
        assert(not run().ok and state.creates == 0 and state.writes == 0)
    end
end)
test("scalar baseline disagreement layer identity and duplicate metadata reject mutation", function()
    for _, failure in ipairs({ "getter", "layer", "duplicate" }) do
        local state, _, run = fixture()
        local material = state.originals[3]
        if failure == "getter" then material.K2_GetScalarParameterValue = function() return -99 end
        elseif failure == "layer" then material.ScalarParameterValues[1].ParameterInfo.Association = 0
        else material.ScalarParameterValues[#material.ScalarParameterValues + 1] = material.ScalarParameterValues[1] end
        assert(not run().ok and state.creates == 0 and state.writes == 0)
    end
end)
test("creation after-bind exception still restores original bindings", function()
    local state, _, run = fixture(); state.create_failure = 2
    local result = run()
    assert(not result.ok and result.original_bindings_restored and state.writes == 0)
    assert(state.bindings[3] == state.originals[3] and state.bindings[4] == state.originals[4])
end)
test("setter after-write exception and wrong native readback both restore originals", function()
    for _, flag in ipairs({ "setter_throws", "bad_readback", "guard_changed" }) do
        local state, _, run = fixture(); state[flag] = true
        local result = run()
        assert(not result.ok and result.original_bindings_restored and result.original_values_verified)
        assert(state.bindings[3] == state.originals[3] and state.bindings[4] == state.originals[4] and state.original_writes == 0)
    end
end)
test("phase capture failures preserve evidence and restore player originals", function()
    for _, phase in ipairs({ "baseline", "changed", "restored" }) do
        local state, _, run = fixture(); state.capture_failure = phase
        local result = run()
        assert(not result.ok and result.original_bindings_restored)
        assert(state.bindings[3] == state.originals[3] and state.bindings[4] == state.originals[4])
        if phase == "baseline" then assert(state.creates == 0 and state.writes == 0) end
    end
end)
test("mismatched capture acknowledgement is never accepted", function()
    local state, _, run = fixture(); state.bad_receipt = "changed"
    local result = run()
    assert(not result.ok and result.original_bindings_restored and #result.captures == 2)
    assert(#result.failed_captures == 1 and result.failed_captures[1].phase == "changed"
        and result.failed_captures[1].capture_receipt ~= nil and result.failed_captures[1].native_readback ~= nil)
end)
test("foreign replacement from callback is not overwritten on cleanup", function()
    local state, _, run = fixture(); state.foreign_capture_binding = "changed"
    local result = run()
    assert(not result.ok and not result.original_bindings_restored and #result.cleanup_failures > 0)
    assert(state.bindings[3] == state.originals[4])
end)
test("same-name asset transition during baseline capture prevents creation", function()
    local state, _, run = fixture(); state.capture_asset_change = "baseline"
    assert(not run().ok and state.creates == 0 and state.writes == 0)
end)
test("form transition in first setter forbids subsequent writes or stale rebinding", function()
    local state, _, run = fixture(); state.setter_form_change = true
    local result = run()
    assert(not result.ok and state.writes == 1 and state.rollback_writes == 0 and not result.original_bindings_restored)
end)
test("one attempt per boot prevents native object name reuse", function()
    local state, deps, run = fixture(); assert(run().ok)
    deps.nonce = string.rep("b", 32)
    assert(not run().ok and state.creates == 2 and state.writes == 8)
end)
test("existing scoped material name prevents accidental instance reuse", function()
    local state, _, run = fixture(); state.existing_named_material = state.originals[3]
    local result = run()
    assert(not result.ok and state.creates == 0 and state.writes == 0 and result.original_bindings_restored)
end)
test("callback cannot change retained native evidence or acknowledge another boot", function()
    local state, _, run = fixture(); state.mutate_sample = true
    local result = run()
    assert(result.ok and result.captures[1].native_readback.eyes[1].parameters.IrisColor1_U.value == 0.671602)
    state, _, run = fixture(); state.bad_boot = true
    assert(not run().ok and state.creates == 0)
end)
print("PASS " .. count .. " human iris scalar roundtrip groups")
