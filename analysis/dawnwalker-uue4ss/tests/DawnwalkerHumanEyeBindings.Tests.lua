local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_human_eye_binding_registry_tests")
local source = assert(arg[1], "Pass DawnwalkerHumanEyeBindings.lua")
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
    local state = { creates = 0, writes = 0, original_writes = 0, bindings = {}, originals = {}, rollback_writes = 0, rebinds = 0, mids = {} }
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
            self.values[info.Name:ToString()] = state.quantize and math.floor(value * 10000000) / 10000000 or value
            if state.setter_form_change then player.Form = 1 end
            if state.setter_throws then error("scalar setter failed after write") end
        end
        function mid:SetVectorParameterValueByInfo(info, color)
            state.writes = state.writes + 1
            self.values[info.Name:ToString()] = color
            if state.setter_throws then error("setter failed after write") end
        end
        state.bindings[slot], state.mids[slot] = mid, mid
        if state.create_failure == state.creates then error("creation failed after binding") end
        if state.foreign_outer then function mid:GetOuter() return player end end
        if state.form_change then player.Form = 1 end
        return mid
    end
    function head:SetMaterial(slot, original)
        assert(original == state.originals[slot] or original == state.mids[slot], "must bind original or this fixture owned MID")
        if original == state.originals[slot] then state.rollback_writes = state.rollback_writes + 1 else state.rebinds = state.rebinds + 1 end
        state.bindings[slot] = original
    end
    local deps = { game_thread = true, identity = { build_id = "25129649", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853" },
        boot_id = "1000-123", nonce = string.rep("a", 32), get_player = function() return player end,
        static_find_object = function(class)
            if class == "/Script/Engine.SkeletalMeshComponent" then return mesh_class end
            assert(class:match("Test.Player.Face Mesh.IrisColorBalance") ~= nil)
            return state.existing_named_material
        end }
    deps.is_in_game_thread = function() return deps.game_thread end
    local api = Pilot.new(deps)
    return state, deps, api, { player = player, world = world, head = head, asset = asset, names = names }
end
local count = 0
local function test(name, fn) fn(); count = count + 1; print("PASS " .. name) end
local function target(snapshot, fraction)
    local result = { schemaId = snapshot.schema_id, values = {} }
    for _, binding in ipairs(snapshot.bindings) do
        for _, parameter in ipairs(binding.parameters) do
            result.values[#result.values + 1] = { parameter = parameter.parameter,
                value = { kind = "scalar", value = parameter.min + (parameter.max - parameter.min) * fraction } }
        end
    end
    return result
end
test("construction is inert and first inspection establishes exact asymmetric original baseline", function()
    local state, _, api, objects = fixture()
    assert(state.creates == 0 and state.writes == 0)
    local snapshot = api.inspect(objects.player, objects.head)
    assert(#snapshot.bindings == 2 and #snapshot.current_settings.values == 8)
    assert(snapshot.bindings[1].parameters[1].parameter.materialId == "coen-human-eye-left")
    assert(snapshot.bindings[1].parameters[2].min ~= snapshot.bindings[2].parameters[2].min)
    assert(snapshot.bindings[1].original_material == state.originals[3] and snapshot.bindings[1].current_material == state.originals[3])
    assert(api.verify(snapshot, objects.player, objects.head) and state.creates == 0 and state.writes == 0)
end)
test("repeated apply changes only owned scalar MIDs and keeps stable original binding identities", function()
    local state, _, api, objects = fixture(); local snapshot = api.inspect(objects.player, objects.head)
    local first = api.apply(target(snapshot, 0), snapshot)
    assert(first.ok, tostring(first.reason))
    assert(state.creates == 2 and state.writes == 8 and state.original_writes == 0)
    local second = api.apply(target(snapshot, 0.5), first.snapshot)
    assert(second.ok, tostring(second.reason))
    assert(state.creates == 2 and state.writes == 16 and first.baseline_id == second.baseline_id)
    assert(second.snapshot.bindings[1].original_identity.address == snapshot.bindings[1].original_identity.address)
    assert(second.snapshot.bindings[1].current_identity.address == first.snapshot.bindings[1].current_identity.address)
    assert(second.native_readback_verified and not second.applied_in_game and not second.visual_effect_verified)
end)
test("explicit restore rebinds original MICs and later apply reuses only the same owned instances", function()
    local state, _, api, objects = fixture(); local baseline = api.inspect(objects.player, objects.head)
    local applied = api.apply(target(baseline, 0.25), baseline); assert(applied.ok)
    local restored = api.restore(applied.snapshot); assert(restored.ok and restored.original_bindings_restored)
    assert(state.bindings[3] == state.originals[3] and state.bindings[4] == state.originals[4])
    assert(restored.baseline_id == baseline.baseline_id and state.rollback_writes == 2)
    local again = api.apply(target(baseline, 0.75), restored.snapshot)
    assert(again.ok and state.creates == 2 and state.rebinds == 2 and state.writes == 16)
end)
test("invalid domain missing duplicate and stale payloads do not change committed eyes", function()
    for _, failure in ipairs({ "range", "missing", "duplicate", "foreign-id", "stale" }) do
        local state, _, api, objects = fixture(); local baseline = api.inspect(objects.player, objects.head)
        assert(api.apply(target(baseline, 0.25), baseline).ok)
        local desired, expected = target(baseline, 0.5), baseline
        if failure == "range" then desired.values[1].value.value = 1
        elseif failure == "missing" then table.remove(desired.values)
        elseif failure == "duplicate" then desired.values[1] = desired.values[2]
        elseif failure == "foreign-id" then desired.values[1].parameter = { name = "other" }
        else expected = { identity_key = baseline.identity_key, baseline_id = "stale", schema_id = baseline.schema_id } end
        assert(not api.apply(desired, expected).ok and state.writes == 8 and state.rollback_writes == 0)
        assert(state.bindings[3] == state.mids[3])
    end
end)
test("inspection and schema validation never restore committed live edits", function()
    local state, _, api, objects = fixture(); local baseline = api.inspect(objects.player, objects.head)
    assert(api.apply(target(baseline, 0.25), baseline).ok)
    local inspected = api.inspect(objects.player, objects.head)
    local canonical = api.validate_settings(target(baseline, 0.5), inspected)
    assert(canonical.schemaId == baseline.schema_id and state.writes == 8 and state.rollback_writes == 0)
end)
test("partial native construction and after-write failures restore original player bindings", function()
    for _, failure in ipairs({ "create", "setter", "getter", "guard" }) do
        local state, _, api, objects = fixture(); local baseline = api.inspect(objects.player, objects.head)
        if failure == "create" then state.create_failure = 2 elseif failure == "setter" then state.setter_throws = true
        elseif failure == "getter" then state.bad_readback = true else state.guard_changed = true end
        local result = api.apply(target(baseline, 0.5), baseline)
        assert(not result.ok and result.original_bindings_restored, tostring(result.reason))
        assert(state.bindings[3] == state.originals[3] and state.bindings[4] == state.originals[4] and state.original_writes == 0)
    end
end)
test("foreign material replacement is neither applied over nor restored over", function()
    local state, _, api, objects = fixture(); local baseline = api.inspect(objects.player, objects.head)
    assert(api.apply(target(baseline, 0.5), baseline).ok)
    state.bindings[3] = state.originals[4]
    assert(not api.apply(target(baseline, 0.25), baseline).ok and not api.restore(baseline).ok)
    assert(state.bindings[3] == state.originals[4] and state.writes == 8 and state.rollback_writes == 0)
end)
test("same-name head asset replacement and form transitions invalidate the old baseline", function()
    for _, failure in ipairs({ "asset", "form" }) do
        local state, _, api, objects = fixture(); local baseline = api.inspect(objects.player, objects.head)
        if failure == "asset" then objects.asset.address = 999 else objects.player.Form = 1 end
        assert(not api.apply(target(baseline, 0.5), baseline).ok and state.creates == 0 and state.writes == 0)
        assert(not pcall(api.inspect, objects.player, objects.head))
    end
end)
test("transition inside first setter prevents further mutation and stale restoration", function()
    local state, _, api, objects = fixture(); local baseline = api.inspect(objects.player, objects.head)
    state.setter_form_change = true
    local result = api.apply(target(baseline, 0.5), baseline)
    assert(not result.ok and not result.original_bindings_restored and state.writes == 1 and state.rollback_writes == 0)
end)
test("occupied private native name and unavailable thread are refused before mutation", function()
    for _, failure in ipairs({ "name", "thread" }) do
        local state, deps, api, objects = fixture(); local baseline = api.inspect(objects.player, objects.head)
        if failure == "name" then state.existing_named_material = state.originals[3] else deps.game_thread = false end
        assert(not api.apply(target(baseline, 0.5), baseline).ok and state.creates == 0 and state.writes == 0)
    end
end)
test("nested calls cannot interleave a native eye mutation", function()
    local state, _, api, objects = fixture(); local baseline = api.inspect(objects.player, objects.head)
    assert(api.apply(target(baseline, 0.25), baseline).ok)
    local setter = state.mids[3].SetScalarParameterValueByInfo
    state.mids[3].SetScalarParameterValueByInfo = function(self, info, value)
        local nested = api.restore(baseline); assert(not nested.ok and nested.reason:find("progress"))
        setter(self, info, value)
    end
    assert(api.apply(target(baseline, 0.75), baseline).ok and state.writes == 16 and state.rollback_writes == 0)
end)
test("returned settings preserve actual getter floats rather than echoing requested numbers", function()
    local state, _, api, objects = fixture(); local baseline = api.inspect(objects.player, objects.head)
    state.quantize = true
    local requested = target(baseline, 0.31415926535)
    local result = api.apply(requested, baseline)
    assert(result.ok, tostring(result.reason))
    local actual = result.current_settings.values[1].value.value
    assert(actual == state.mids[3].values.IrisColor1_U and actual ~= requested.values[1].value.value)
end)
test("original settings remain the immutable first baseline after apply and reconnect", function()
    local state, _, api, objects = fixture(); local baseline = api.inspect(objects.player, objects.head)
    local original = baseline.original_settings.values[1].value.value
    assert(original == baseline.current_settings.values[1].value.value)
    baseline.original_settings.values[1].value.value = -999
    assert(api.apply(target(baseline, 0.314159), baseline).ok)
    local reconnected = api.inspect(objects.player, objects.head)
    assert(reconnected.original_settings.values[1].value.value == original)
    assert(reconnected.current_settings.values[1].value.value ~= original)
    assert(state.original_writes == 0)
end)
print("PASS " .. count .. " persistent human eye binding groups")
