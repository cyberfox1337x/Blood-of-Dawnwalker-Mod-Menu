local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_loaded_variant_readonly_tests")
local source = assert(arg[1], "Pass DawnwalkerEyeVariantReadOnlyProbe.lua")
local function fname(name) return { ToString = function() return name end } end
local function object(id, name, classes)
    local value = { id = id, name = name }
    function value:IsValid() return true end
    function value:GetAddress() return self.id end
    function value:GetFullName() return self.name end
    function value:IsA(class) for _, expected in ipairs(classes) do if class == expected then return true end end return false end
    return value
end
local function fixture()
    local Probe = dofile(source)
    local player = object(1, "Player Test", { "/Script/Dawnwalker.DawnwalkerPlayerCharacter" })
    local world = object(2, "World Test", { "/Script/Engine.World" })
    local head = object(3, "Mesh Test", { "/Script/Engine.SkeletalMeshComponent" })
    local asset = object(4, "SkeletalMesh /Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/SK_HMA_Coen_Head_A.SK_HMA_Coen_Head_A", { "/Script/Engine.SkeletalMesh" })
    local base = object(5, "Material Eye", { "/Script/Engine.Material", "/Script/Engine.MaterialInterface" })
    local state = { lookups = {}, materials = {}, getters = 0 }
    local function material(id, name)
        local result = object(id, name, { "/Script/Engine.MaterialInstanceConstant", "/Script/Engine.MaterialInterface" })
        result.Parent = base
        result.VectorParameterValues = { { ParameterInfo = { Name = fname("Leukocoria_Color"), Association = 2, Index = -1 }, ParameterValue = { R = 3, G = 0.1, B = 0.2, A = 1 } } }
        result.ScalarParameterValues = { { ParameterInfo = { Name = fname("Iris_Value"), Association = 2, Index = -1 }, ParameterValue = 1.5 } }
        result.StaticParametersRuntime = { StaticSwitchParameters = { { ParameterInfo = { Name = fname("Enable Leukocoria"), Association = 2, Index = -1 }, bOverride = true, Value = false } } }
        function result:K2_GetVectorParameterValue(name) assert(name:ToString() == "Leukocoria_Color"); state.getters = state.getters + 1; return self.VectorParameterValues[1].ParameterValue end
        function result:K2_GetScalarParameterValue(name) assert(name:ToString() == "Iris_Value"); state.getters = state.getters + 1; return 1.5 end
        return result
    end
    state.materials[3], state.materials[4] = material(6, "MaterialInstanceConstant EyeL"), material(7, "MaterialInstanceConstant EyeR")
    player.Form, player.HeadMesh = 0, head
    function player:GetWorld() return world end
    function player:IsInWolfForm() return false end
    function head:GetSkeletalMeshAsset() return asset end
    function head:GetOwner() return player end
    function head:GetNumMaterials() return 5 end
    function head:GetMaterialSlotNames() return { fname("head"), fname("teeth"), fname("saliva"), fname("shader_eyeLeft_shader"), fname("shader_eyeRight_shader") } end
    function head:GetMaterial(slot) return state.materials[slot] end
    local deps = { game_thread = true, intent = "eye-variant-observe", identity = { build_id = "25129649", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853" }, get_player = function() return player end }
    deps.static_find_object = function(path)
        state.lookups[#state.lookups + 1] = path
        if state.missing then return nil end
        if state.form_change then player.Form = 1 end
        if state.asset_change then asset.id = 99 end
        local result = material(10 + #state.lookups, "MaterialInstanceConstant " .. path)
        if state.override_false then result.StaticParametersRuntime.StaticSwitchParameters[1].bOverride = false end
        if state.oversized then for i = 1, 129 do result.VectorParameterValues[i] = result.VectorParameterValues[1] end end
        return result
    end
    return Probe, deps, state
end
local count = 0
local function test(name, fn) fn(); count = count + 1; print("PASS " .. name) end
test("exact seven loaded lookups with HDR native values and explicit static false", function()
    local Probe, deps, state = fixture()
    local result = Probe.run(deps)
    assert(result.ok and #result.loaded_variants == 7 and #state.lookups == 7 and state.getters == 18)
    assert(result.current_eyes[1].value.effective_parameters["vector:Leukocoria_Color:2:-1"].native_value.R == 3)
    assert(result.current_eyes[1].value.effective_static_switches["switch:Enable Leukocoria:2:-1"].value == false)
    assert(not result.mutation_authorized and not result.visual_effect_verified)
end)
test("absent loaded assets do not force loads or hide current material observations", function()
    local Probe, deps, state = fixture(); state.missing = true
    local result = Probe.run(deps)
    assert(result.ok and result.current_eyes[1].ok and not result.loaded_variants[1].ok and #state.lookups == 7)
end)
test("switch override false is not presented as effective inherited activation", function()
    local Probe, deps, state = fixture(); state.override_false = true
    local result = Probe.run(deps)
    assert(result.ok and next(result.loaded_variants[1].value.effective_static_switches) == nil)
end)
test("wrong build and intent reject before native lookup", function()
    for _, key in ipairs({ "build", "intent", "thread" }) do
        local Probe, deps, state = fixture()
        if key == "build" then deps.identity.build_id = "old" elseif key == "intent" then deps.intent = "eye-color-roundtrip" else deps.game_thread = false end
        assert(not Probe.run(deps).ok and #state.lookups == 0 and state.getters == 0)
    end
end)
test("form or same-name asset replacement invalidates the full observation", function()
    for _, key in ipairs({ "form_change", "asset_change" }) do
        local Probe, deps, state = fixture(); state[key] = true
        assert(not Probe.run(deps).ok)
    end
end)
test("oversized parameter arrays remain explicit errors", function()
    local Probe, deps, state = fixture(); state.oversized = true
    local result = Probe.run(deps)
    assert(result.ok and result.loaded_variants[1].value.layers[1].vector.ok == false)
end)
test("name-only layer getter is refused while preserving separate switch evidence", function()
    local Probe, deps, state = fixture()
    state.materials[3].VectorParameterValues[1].ParameterInfo.Association = 0
    local result = Probe.run(deps)
    assert(result.ok and not result.current_eyes[1].value.layers[1].vector.ok)
    assert(result.current_eyes[1].value.effective_static_switches["switch:Enable Leukocoria:2:-1"])
end)
test("parent cycle rejects that material", function()
    local Probe, deps, state = fixture(); state.materials[3].Parent = state.materials[3]
    local result = Probe.run(deps)
    assert(result.ok and not result.current_eyes[1].ok)
end)
test("unreadable or duplicate child switches cannot falsely establish parent activation", function()
    for _, failure in ipairs({ "unreadable", "duplicate" }) do
        local Probe, deps, state = fixture()
        local child, parent = state.materials[3], state.materials[4]
        child.Parent = parent
        parent.StaticParametersRuntime.StaticSwitchParameters[1].Value = true
        if failure == "unreadable" then child.StaticParametersRuntime = nil
        else
            local switches = child.StaticParametersRuntime.StaticSwitchParameters
            switches[2] = switches[1]
        end
        local result = Probe.run(deps)
        assert(result.ok and result.current_eyes[1].ok)
        assert(result.current_eyes[1].value.static_switch_resolution_incomplete)
        assert(result.current_eyes[1].value.layers[2].switch.entries[1].value == true)
        assert(next(result.current_eyes[1].value.effective_static_switches) == nil)
    end
end)
print(tostring(count) .. " variant read-only test groups passed")
