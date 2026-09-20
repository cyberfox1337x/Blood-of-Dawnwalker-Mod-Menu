local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_human_eye_binding_registry")

-- Inert until explicitly called on the verified game thread. Human bindings only.
local Probe = {}
local generation_sequence = 0
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

local EDITABLE = { "IrisColor1_U", "IrisColor1_V", "IrisColor2_U", "IrisColor2_V" }
local SCHEMA_ID = "dawnwalker-human-iris-uv-v1-25129649"
local function base_values(eye)
    local values = {}; for name, parameter in pairs(eye.parameters) do values[name] = copy(parameter.original) end
    return values
end
local function parameter_id(eye, name)
    return { slotId = "head:" .. eye.slot, materialId = eye.slot == 3 and "coen-human-eye-left" or "coen-human-eye-right",
        name = name, association = 2, index = -1 }
end
local function same_parameter(left, right)
    if type(left) ~= "table" then return false end
    for _, name in ipairs({ "slotId", "materialId", "name", "association", "index" }) do if left[name] ~= right[name] then return false end end
    return true
end

function Probe.new(deps)
    local state, busy
    local api = {}
    local function route()
        check(type(deps) == "table" and type(deps.is_in_game_thread) == "function" and deps.is_in_game_thread() == true,
            "Human eye registry requires the actual game thread")
        check(type(deps.identity) == "table" and deps.identity.build_id == "25129649"
            and deps.identity.executable_sha256 == "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853", "Human eye registry build mismatch")
        check(type(deps.boot_id) == "string" and deps.boot_id:match("^%d+%-%d+$") ~= nil, "Driver boot identity required")
        check(type(deps.get_player) == "function" and type(deps.static_find_object) == "function", "Native eye registry dependencies unavailable")
    end
    local function settings(values)
        local result = { schemaId = SCHEMA_ID, values = {} }
        for index, eye in ipairs(state.eyes) do
            for _, name in ipairs(EDITABLE) do result.values[#result.values + 1] = { parameter = parameter_id(eye, name),
                value = { kind = "scalar", value = values[index][name] } } end
        end
        return result
    end
    local function bounds(eye, name)
        local first, second = eye.parameters[name].original, eye.parameters[SWAPS[name]].original
        return math.min(first, second), math.max(first, second)
    end
    local function initialize()
        local ctx = context(deps)
        local eyes = {}
        for _, definition in ipairs(EYES) do
            local original = ctx.head_object:GetMaterial(definition.slot)
            local original_record = object(original, MIC)
            check(original_record.name == definition.material, "Original human eye MIC required before baseline capture")
            local parent = object(original.Parent, "/Script/Engine.MaterialInterface")
            check(parent.name == SHADER, "Observed human eye parent shader required")
            local eye = { slot = definition.slot, slot_name = definition.slot_name, original = original,
                original_record = original_record, parent = parent, native_name = ctx.slot_names[definition.slot + 1], parameters = parameters(original) }
            eyes[#eyes + 1] = eye
        end
        generation_sequence = generation_sequence + 1
        local identity_key = table.concat({ deps.boot_id, ctx.player.address, ctx.world.address, ctx.head.address, ctx.asset.address,
            "human", eyes[1].original_record.address, eyes[2].original_record.address }, ":")
        state = { ctx = ctx, eyes = eyes, identity_key = identity_key,
            baseline_id = deps.boot_id .. ":human-eyes:" .. generation_sequence, values = { base_values(eyes[1]), base_values(eyes[2]) } }
    end
    local function validate_generation()
        route()
        check(state ~= nil and not state.invalidated, "Human eye baseline is unavailable or invalidated")
        local ok, reason = pcall(same_context, deps, state.ctx)
        if not ok then state.invalidated = true; error(tostring(reason), 0) end
    end
    local function verify_native(values)
        validate_generation()
        local records = {}
        for index, eye in ipairs(state.eyes) do
            local current = state.ctx.head_object:GetMaterial(eye.slot)
            local dynamic = current:GetAddress() ~= eye.original:GetAddress()
            check(not dynamic or eye.mid_record ~= nil, "Foreign human eye material binding")
            records[index] = verify_eye(state.ctx, eye, values[index], dynamic)
        end
        return records
    end
    local function expected_snapshot(expected)
        check(type(expected) == "table" and state ~= nil and expected.identity_key == state.identity_key
            and expected.baseline_id == state.baseline_id and expected.schema_id == SCHEMA_ID, "Stale human eye baseline request")
    end
    local function expose(records)
        local observed_values = {}
        for index, record in ipairs(records) do
            observed_values[index] = {}
            for name, parameter in pairs(record.parameters) do observed_values[index][name] = copy(parameter.value) end
        end
        local result = { identity_key = state.identity_key, baseline_id = state.baseline_id, schema_id = SCHEMA_ID,
            player = copy(state.ctx.player), world = copy(state.ctx.world), head = copy(state.ctx.head), asset = copy(state.ctx.asset),
            form = 0, is_wolf_form = false, current_settings = settings(observed_values),
            original_settings = settings({ base_values(state.eyes[1]), base_values(state.eyes[2]) }), bindings = {} }
        for index, eye in ipairs(state.eyes) do
            local current = state.ctx.head_object:GetMaterial(eye.slot)
            local binding = { slot = eye.slot, slot_name = eye.slot_name, native_name = eye.native_name,
                original_material = eye.original, original_identity = copy(eye.original_record),
                current_material = current, current_identity = copy(records[index].material), parameters = {} }
            for _, name in ipairs(EDITABLE) do
                local minimum, maximum = bounds(eye, name)
                binding.parameters[#binding.parameters + 1] = { name = name, native_info = eye.parameters[name].info,
                    parameter = parameter_id(eye, name), min = minimum, max = maximum, tolerance = 0.000001 }
            end
            result.bindings[index] = binding
        end
        return result
    end
    function api.inspect(player, head)
        check(not busy, "Native eye mutation is already in progress")
        route()
        if not state then initialize() end
        same(player, state.ctx.player, PLAYER); same(head, state.ctx.head, MESH)
        local ok, result = pcall(function() return expose(verify_native(state.values)) end)
        if not ok then state.invalidated = true; error(tostring(result), 0) end
        return result
    end
    function api.verify(snapshot, player, head)
        expected_snapshot(snapshot)
        api.inspect(player, head)
        return true
    end
    function api.validate_settings(input, snapshot)
        expected_snapshot(snapshot)
        check(type(input) == "table" and input.schemaId == SCHEMA_ID and type(input.values) == "table" and #input.values == 8,
            "Exactly eight canonical human scalar values required")
        local values, consumed = {}, {}
        for index, eye in ipairs(state.eyes) do
            values[index] = base_values(eye)
            for _, name in ipairs(EDITABLE) do
                local expected, match = parameter_id(eye, name), nil
                for entry_index, entry in ipairs(input.values) do
                    if same_parameter(entry.parameter, expected) then check(match == nil, "Duplicate canonical human parameter"); match = entry; consumed[entry_index] = true end
                end
                check(match ~= nil and type(match.value) == "table" and match.value.kind == "scalar", "Missing or unsupported human parameter")
                local value, minimum, maximum = finite(match.value.value), bounds(eye, name)
                check(value >= minimum and value <= maximum, "Human iris scalar exceeds its observed pair interval")
                values[index][name] = value
            end
        end
        for index in ipairs(input.values) do check(consumed[index] == true, "Unexpected canonical human parameter") end
        return settings(values), values
    end
    local function restore_bindings()
        local errors = {}
        for index = #state.eyes, 1, -1 do
            local eye = state.eyes[index]
            local ok, reason = pcall(function()
                validate_generation()
                same(eye.original.Parent, eye.parent, "/Script/Engine.MaterialInterface")
                local current = state.ctx.head_object:GetMaterial(eye.slot)
                if current:GetAddress() ~= eye.original:GetAddress() then
                    check(eye.creation_attempted == true, "Foreign eye material cannot be restored")
                    object(current, MID); same(current:GetOuter(), state.ctx.head, MESH); same(current.Parent, eye.original_record, MIC)
                    if eye.mid_record then same(current, eye.mid_record, MID)
                    else check(current:GetFName():ToString() == eye.mid_name:ToString(), "Unknown partial native eye instance") end
                    state.ctx.head_object:SetMaterial(eye.slot, eye.original)
                end
                verify_eye(state.ctx, eye, base_values(eye), false)
            end)
            if not ok then errors[#errors + 1] = tostring(reason) end
        end
        if #errors == 0 then state.values = { base_values(state.eyes[1]), base_values(state.eyes[2]) }
        else state.invalidated = true end
        return #errors == 0, errors
    end
    local function ensure_private(eye)
        validate_generation()
        local head = state.ctx.head_object
        if eye.mid_record then
            same(eye.mid, eye.mid_record, MID); same(eye.mid:GetOuter(), state.ctx.head, MESH); same(eye.mid.Parent, eye.original_record, MIC)
            local current = head:GetMaterial(eye.slot)
            if current:GetAddress() == eye.original:GetAddress() then head:SetMaterial(eye.slot, eye.mid)
            else same(current, eye.mid_record, MID) end
        else
            -- Distinct observed native names avoid both earlier pilot names. The owned
            -- instance is retained for later edits/restores within this baseline only.
            eye.mid_name = eye.parameters[eye.slot == 3 and "IrisColorBalance" or "IrisColorBalanceSmoothness"].native_name
            local outer_path = state.ctx.head.name:match("^[^ ]+ (.+)$")
            check(type(outer_path) == "string", "Native head object path unavailable")
            local previous = deps.static_find_object(outer_path .. "." .. eye.mid_name:ToString())
            check(previous == nil or previous:IsValid() ~= true, "Persistent human eye instance name is already occupied")
            same(head:GetMaterial(eye.slot), eye.original_record, MIC)
            eye.creation_attempted = true
            local mid = head:CreateDynamicMaterialInstance(eye.slot, eye.original, eye.mid_name)
            local mid_record = object(mid, MID)
            check(mid_record.address ~= eye.original_record.address and mid:GetFName():ToString() == eye.mid_name:ToString(), "Unexpected private eye factory result")
            same(mid:GetOuter(), state.ctx.head, MESH); same(mid.Parent, eye.original_record, MIC)
            eye.mid, eye.mid_record = mid, mid_record
        end
        validate_generation()
        same(head:GetMaterial(eye.slot), eye.mid_record, MID)
    end
    local function operation(kind, input, expected)
        if busy then return { ok = false, reason = "Native eye mutation is already in progress", applied_in_game = false } end
        local entered, changed, actual, requested = false, false, nil, nil
        local ok, reason = pcall(function()
            route(); expected_snapshot(expected); verify_native(state.values)
            if kind == "apply" then requested, actual = api.validate_settings(input, expected) end
            busy, entered = true, true
            if kind == "restore" then
                local restored, errors = restore_bindings()
                check(restored, table.concat(errors, " | "))
            else
                for _, eye in ipairs(state.eyes) do changed = true; ensure_private(eye) end
                for index, eye in ipairs(state.eyes) do
                    for _, name in ipairs(EDITABLE) do
                        validate_generation()
                        local mid = state.ctx.head_object:GetMaterial(eye.slot)
                        same(mid, eye.mid_record, MID); same(mid:GetOuter(), state.ctx.head, MESH); same(mid.Parent, eye.original_record, MIC)
                        mid:SetScalarParameterValueByInfo(eye.parameters[name].info, actual[index][name])
                        check(equal(read_parameter(mid, eye.parameters[name], true), actual[index][name]), "Persistent scalar setter did not read back")
                    end
                end
                verify_native(actual)
                state.values = actual
            end
            actual = expose(verify_native(state.values))
        end)
        local recovered, recovery_errors = nil, {}
        if not ok and entered and changed and state then recovered, recovery_errors = restore_bindings() end
        busy = false
        return { ok = ok, kind = kind, reason = not ok and tostring(reason) or nil,
            identity_key = state and state.identity_key, baseline_id = state and state.baseline_id, schema_id = SCHEMA_ID,
            current_settings = ok and actual.current_settings or nil, snapshot = ok and actual or nil,
            original_bindings_restored = ok and kind == "restore" or recovered == true,
            recovery_errors = recovery_errors, native_readback_verified = ok, visual_effect_verified = false,
            applied_in_game = false, production_capabilities = "none" }
    end
    function api.apply(settings_input, expected) return operation("apply", settings_input, expected) end
    function api.restore(expected) return operation("restore", nil, expected) end
    return api
end

return Probe
