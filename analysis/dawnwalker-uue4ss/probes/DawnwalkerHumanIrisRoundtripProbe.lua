local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_human_iris_scalar_roundtrip")

-- Explicit, single-request human iris pilot. No startup work or persistent override.
local Probe = {}
local attempted_boots = {}
local MIC, MID = "/Script/Engine.MaterialInstanceConstant", "/Script/Engine.MaterialInstanceDynamic"
local MESH, PLAYER = "/Script/Engine.SkeletalMeshComponent", "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local PREFIX = "MaterialInstanceConstant /Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/Materials/"
local HEAD = "SkeletalMesh /Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/SK_HMA_Coen_Head_A.SK_HMA_Coen_Head_A"
local SHADER = "Material /Game/_Dawnwalker/Shaders/Characters/Face/M_EyeRefractive_Optimized.M_EyeRefractive_Optimized"
local EYES = {
    { slot = 3, slot_name = "shader_eyeLeft_shader", material = PREFIX .. "MI_Coen_Eyeball_L.MI_Coen_Eyeball_L" },
    { slot = 4, slot_name = "shader_eyeRight_shader", material = PREFIX .. "MI_Coen_Eyeball_R.MI_Coen_Eyeball_R" },
}
local SWAPS = { IrisColor1_U = "IrisColor2_U", IrisColor1_V = "IrisColor2_V", IrisColor2_U = "IrisColor1_U", IrisColor2_V = "IrisColor1_V" }
local SCALARS = { "IrisColor1_U", "IrisColor1_V", "IrisColor2_U", "IrisColor2_V", "IrisColorBalance", "IrisColorBalanceSmoothness", "Iris_Saturation", "Iris_Value", "Emissivnes" }
local VECTORS = { "Leukocoria_Color", "CloudyIrisColor" }
local function check(value, message) if value ~= true then error(message, 0) end end
local function finite(value)
    check(type(value) == "number" and value == value and math.abs(value) < math.huge, "Non-finite native parameter")
    return value
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local function color(value) return { R = finite(value.R), G = finite(value.G), B = finite(value.B), A = finite(value.A) } end
local function equal(left, right)
    if type(left) == "table" and type(right) == "table" then
        for _, field in ipairs({ "R", "G", "B", "A" }) do if math.abs(left[field] - right[field]) > 0.000001 then return false end end
        return true
    end
    return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.000001
end
local function object(value, class)
    check(value ~= nil and value:IsValid() == true and value:IsA(class) == true, "Required native object is absent or has a different class")
    local name, address = value:GetFullName(), finite(value:GetAddress())
    check(type(name) == "string" and #name > 0 and #name <= 1024 and not name:find("Default__", 1, true) and address > 0, "Invalid native object identity")
    return { name = name, address = tostring(address) }
end
local function same(value, record, class)
    local actual = object(value, class)
    check(actual.name == record.name and actual.address == record.address, "Native object generation changed")
end
local function array(value, maximum)
    check(value ~= nil, "Required native array is absent")
    local ok, count = pcall(function() return value:GetArrayNum() end)
    if not ok then ok, count = pcall(function() return #value end) end
    check(ok and type(count) == "number" and count % 1 == 0 and count >= 0 and count <= maximum, "Native array exceeds bound")
    local result = {}
    for index = 1, count do
        local item = value[index]
        local wrapped, raw = pcall(function() return item:get() end)
        if wrapped then item = raw end
        check(item ~= nil, "Native array item absent")
        result[index] = item
    end
    return result
end
local function context(deps)
    local player = deps.get_player()
    local result = { player_object = player, player = object(player, PLAYER), world = object(player:GetWorld(), "/Script/Engine.World") }
    check(player.Form == 0 and player:IsInWolfForm() == false, "This exact pilot supports the observed human form only")
    result.head_object, result.head = player.HeadMesh, object(player.HeadMesh, MESH)
    result.asset = object(player.HeadMesh:GetSkeletalMeshAsset(), "/Script/Engine.SkeletalMesh")
    check(result.asset.name == HEAD, "Exact observed Coen head asset required")
    same(result.head_object:GetOwner(), result.player, PLAYER)
    local head_count = 0
    for _, mesh in ipairs(array(player:K2_GetComponentsByClass(deps.static_find_object(MESH)), 32)) do
        if mesh:GetAddress() == result.head_object:GetAddress() then head_count = head_count + 1 end
    end
    check(head_count == 1, "Current head must occur once in the owned component list")
    result.slot_names = array(result.head_object:GetMaterialSlotNames(), 16)
    check(#result.slot_names == result.head_object:GetNumMaterials() and #result.slot_names >= 5, "Observed head topology changed")
    for _, eye in ipairs(EYES) do check(result.slot_names[eye.slot + 1]:ToString() == eye.slot_name, "Observed eye slot names differ") end
    return result
end
local function same_context(deps, expected)
    local current = context(deps)
    same(current.player_object, expected.player, PLAYER)
    same(current.player_object:GetWorld(), expected.world, "/Script/Engine.World")
    same(current.head_object, expected.head, MESH)
    same(current.head_object:GetSkeletalMeshAsset(), expected.asset, "/Script/Engine.SkeletalMesh")
    check(#current.slot_names == #expected.slot_names, "Head slot count changed")
    return current
end
local function read_parameter(material, parameter, dynamic)
    if parameter.kind == "vector" then
        return color(dynamic and material:K2_GetVectorParameterValueByInfo(parameter.info) or material:K2_GetVectorParameterValue(parameter.native_name))
    end
    return finite(dynamic and material:K2_GetScalarParameterValueByInfo(parameter.info) or material:K2_GetScalarParameterValue(parameter.native_name))
end
local function parameters(material)
    local result = {}
    for _, group in ipairs({ { kind = "scalar", wanted = SCALARS, source = material.ScalarParameterValues }, { kind = "vector", wanted = VECTORS, source = material.VectorParameterValues } }) do
        local wanted = {}; for _, name in ipairs(group.wanted) do wanted[name] = true end
        for _, entry in ipairs(array(group.source, 128)) do
            local info, name = entry.ParameterInfo, entry.ParameterInfo.Name:ToString()
            if wanted[name] then
                check(result[name] == nil and info.Association == 2 and info.Index == -1, "Duplicate or non-global required parameter")
                local parameter = { name = name, kind = group.kind, info = info, native_name = info.Name, association = 2, index = -1 }
                parameter.original = read_parameter(material, parameter, false)
                local observed = group.kind == "vector" and color(entry.ParameterValue) or finite(entry.ParameterValue)
                check(equal(parameter.original, observed), "Native getter differs from original override: " .. name)
                result[name] = parameter
            end
        end
        for _, name in ipairs(group.wanted) do check(result[name] ~= nil, "Required observed parameter missing: " .. name) end
    end
    return result
end
local function verify_eye(ctx, eye, expected_values, dynamic)
    same(eye.original.Parent, eye.parent, "/Script/Engine.MaterialInterface")
    local current = ctx.head_object:GetMaterial(eye.slot)
    if dynamic then
        same(current, eye.mid_record, MID)
        same(current:GetOuter(), ctx.head, MESH)
        same(current.Parent, eye.original_record, MIC)
    else same(current, eye.original_record, MIC) end
    local observed = {}
    for name, parameter in pairs(eye.parameters) do
        local value = read_parameter(current, parameter, dynamic)
        check(equal(value, expected_values[name]), "Independent native value differs: " .. name)
        observed[name] = { kind = parameter.kind, association = 2, index = -1, value = value }
    end
    return { slot = eye.slot, slot_name = eye.slot_name, material = object(current, dynamic and MID or MIC), parameters = observed }
end
local function desired(eye, changed)
    local values = {}
    for name, parameter in pairs(eye.parameters) do values[name] = copy(eye.parameters[changed and SWAPS[name] or name].original) end
    return values
end
local function snapshot(deps, ctx, eyes, changed, dynamic)
    same_context(deps, ctx)
    local sample = { player = copy(ctx.player), world = copy(ctx.world), head = copy(ctx.head), asset = copy(ctx.asset), form = 0, is_wolf_form = false, eyes = {} }
    for _, eye in ipairs(eyes) do sample.eyes[#sample.eyes + 1] = verify_eye(ctx, eye, desired(eye, changed), dynamic) end
    return sample
end
function Probe.run(deps)
    local ctx, eyes, captures, failed_captures = nil, {}, {}, {}
    local created_any, mutation_attempted, numeric_changed = false, false, false
    local cleanup_failures = {}
    local function capture_phase(phase, changed, dynamic)
        local sample = snapshot(deps, ctx, eyes, changed, dynamic)
        sample.phase, sample.nonce, sample.boot_id = phase, deps.nonce, deps.boot_id
        sample.baseline_id = deps.boot_id .. ":" .. deps.nonce
        local callback_ok, receipt = pcall(deps.capture_callback, phase, copy(sample))
        local matched = callback_ok and type(receipt) == "table" and receipt.ok == true
            and receipt.phase == phase and receipt.nonce == deps.nonce and receipt.boot_id == deps.boot_id
        if not matched then
            failed_captures[#failed_captures + 1] = { phase = phase, native_readback = sample,
                capture_receipt = type(receipt) == "table" and copy(receipt) or nil,
                callback_error = not callback_ok and tostring(receipt):sub(1, 1024) or nil }
            error("Capture callback did not return the matching successful phase/nonce/boot: "
                .. tostring(type(receipt) == "table" and receipt.reason or receipt):sub(1, 1024), 0)
        end
        snapshot(deps, ctx, eyes, changed, dynamic)
        captures[#captures + 1] = { phase = phase, native_readback = sample, capture_receipt = copy(receipt) }
    end
    local ok, failure = pcall(function()
        check(type(deps) == "table" and deps.game_thread == true and deps.intent == "human-iris-pair-roundtrip", "Explicit game-thread human iris intent required")
        check(deps.identity.build_id == "25129649" and deps.identity.executable_sha256 == "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853", "Exact reviewed current build required")
        check(type(deps.boot_id) == "string" and deps.boot_id:match("^%d+%-%d+$") ~= nil and type(deps.nonce) == "string" and #deps.nonce == 32 and deps.nonce:match("^%x+$") ~= nil, "Invalid boot/nonce")
        check(type(deps.capture_callback) == "function", "Explicit bounded phase capture callback required")
        check(not attempted_boots[deps.boot_id], "One human iris pilot attempt per driver boot")
        attempted_boots[deps.boot_id] = true
        ctx = context(deps)
        for _, definition in ipairs(EYES) do
            local original = ctx.head_object:GetMaterial(definition.slot)
            local record = object(original, MIC)
            check(record.name == definition.material, "Exact observed original human eye material required")
            local parent = object(original.Parent, "/Script/Engine.MaterialInterface")
            check(parent.name == SHADER, "Exact observed eye shader parent required")
            eyes[#eyes + 1] = { slot = definition.slot, slot_name = definition.slot_name, original = original, original_record = record,
                parent = parent, native_name = ctx.slot_names[definition.slot + 1], parameters = parameters(original) }
        end
        capture_phase("baseline", false, false)
        same_context(deps, ctx)
        for _, eye in ipairs(eyes) do
            local fresh = parameters(eye.original)
            for name, value in pairs(fresh) do check(equal(value.original, eye.parameters[name].original), "Original scalar metadata/value changed before mutation") end
            eye.parameters = fresh
            -- Use distinct, already-observed native names; never collide with the older
            -- vector pilot's slot-named MIDs or silently reuse another named instance.
            eye.native_name = fresh[eye.slot == 3 and "IrisColor1_U" or "IrisColor2_U"].native_name
            local outer_path = ctx.head.name:match("^[^ ]+ (.+)$")
            check(type(outer_path) == "string", "Cannot identify native head object path")
            local existing = deps.static_find_object(outer_path .. "." .. eye.native_name:ToString())
            check(existing == nil or existing:IsValid() ~= true, "Named private iris material already exists")
            verify_eye(ctx, eye, desired(eye, false), false)
            eye.creation_attempted, mutation_attempted = true, true
            local mid = ctx.head_object:CreateDynamicMaterialInstance(eye.slot, eye.original, eye.native_name)
            eye.mid_record = object(mid, MID)
            check(eye.mid_record.address ~= eye.original_record.address, "Factory reused the original material")
            check(mid:GetFName():ToString() == eye.native_name:ToString(), "Private iris material name differs from the scoped factory request")
            created_any = true
            same_context(deps, ctx)
            verify_eye(ctx, eye, desired(eye, false), true)
        end
        for _, eye in ipairs(eyes) do
            same_context(deps, ctx)
            verify_eye(ctx, eye, desired(eye, false), true)
            for _, name in ipairs(SCALARS) do
                if SWAPS[name] then
                    same_context(deps, ctx)
                    local mid = ctx.head_object:GetMaterial(eye.slot)
                    same(mid, eye.mid_record, MID)
                    same(mid:GetOuter(), ctx.head, MESH)
                    same(mid.Parent, eye.original_record, MIC)
                    mid:SetScalarParameterValueByInfo(eye.parameters[name].info, eye.parameters[SWAPS[name]].original)
                end
            end
        end
        snapshot(deps, ctx, eyes, true, true)
        numeric_changed = true
        capture_phase("changed", true, true)
    end)
    local original_bindings_restored = ctx ~= nil and #eyes == 2
    if ctx then
        for index = #eyes, 1, -1 do
            local eye = eyes[index]
            local restored, reason = pcall(function()
                same_context(deps, ctx)
                same(eye.original.Parent, eye.parent, "/Script/Engine.MaterialInterface")
                local current = ctx.head_object:GetMaterial(eye.slot)
                if current:GetAddress() ~= eye.original:GetAddress() then
                    check(eye.creation_attempted == true, "Foreign replacement cannot be restored")
                    object(current, MID)
                    same(current:GetOuter(), ctx.head, MESH)
                    same(current.Parent, eye.original_record, MIC)
                    if eye.mid_record then same(current, eye.mid_record, MID)
                    else check(current:GetFName():ToString() == eye.native_name:ToString(), "Unidentified partially created MID cannot be restored") end
                    ctx.head_object:SetMaterial(eye.slot, eye.original)
                end
                verify_eye(ctx, eye, desired(eye, false), false)
            end)
            if not restored then original_bindings_restored = false; cleanup_failures[#cleanup_failures + 1] = tostring(reason) end
        end
    end
    if original_bindings_restored and mutation_attempted then
        local captured, reason = pcall(capture_phase, "restored", false, false)
        if not captured then ok = false; failure = tostring(failure or "") .. " Restored capture: " .. tostring(reason) end
    end
    return { ok = ok and original_bindings_restored and #captures == 3, kind = "native-human-iris-pair-roundtrip-evidence",
        reason = not ok and tostring(failure) or not original_bindings_restored and "Original material cleanup could not be verified" or nil,
        mutation_attempted = mutation_attempted, private_materials_created = created_any, scalar_swap_readback_verified = numeric_changed,
        original_bindings_restored = original_bindings_restored, original_values_verified = original_bindings_restored,
        cleanup_failures = cleanup_failures, captures = captures, failed_captures = failed_captures,
        boot_id = deps and deps.boot_id, nonce = deps and deps.nonce,
        scalar_parameters_verified = copy(SCALARS), vector_parameters_verified = copy(VECTORS),
        visual_effect_verified = false, gameplay_verified = false, applied_in_game = false,
        limitation = "Only observed primary/secondary scalar values are swapped. Captures are callback evidence requiring independent pixel review. Original slot bindings are restored before returning; no RGB picker mapping or persistent application is claimed." }
end
return Probe
