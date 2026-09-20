local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_native_pilot")

-- Explicit transaction only. Importing this module never queries or changes the game.
local Pilot = {}
local baseline
local attempted_operations = {}
local private_roundtrip_baseline_id
local BUILD = "25129649"
local HASH = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
local PLAYER = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local MESH = "/Script/Engine.SkeletalMeshComponent"
local MIC = "/Script/Engine.MaterialInstanceConstant"
local MID = "/Script/Engine.MaterialInstanceDynamic"
local HEAD = "SkeletalMesh /Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/SK_HMA_Coen_Head_A.SK_HMA_Coen_Head_A"
local MATERIAL_PREFIX = "MaterialInstanceConstant /Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/Materials/"
local PARENT_MATERIAL = "Material /Game/_Dawnwalker/Shaders/Characters/Face/M_EyeRefractive_Optimized.M_EyeRefractive_Optimized"
local EYES = {
    { slot = 3, slot_name = "shader_eyeLeft_shader", material_name = MATERIAL_PREFIX .. "MI_Coen_Eyeball_L.MI_Coen_Eyeball_L" },
    { slot = 4, slot_name = "shader_eyeRight_shader", material_name = MATERIAL_PREFIX .. "MI_Coen_Eyeball_R.MI_Coen_Eyeball_R" },
}
local PARAMETERS = { "Leukocoria_Color", "CloudyIrisColor" }
-- Exact captured native enum Engine_enums.hpp:2011-2015: Layer=0, Blend=1, Global=2.
local GLOBAL_PARAMETER = 2

local function check(condition, message) if condition ~= true then error(message, 0) end end
local function finite(value, label)
    check(type(value) == "number" and value == value and math.abs(value) < math.huge, label .. " is not finite")
    return value
end
local function object(object_value, class, label)
    check(object_value ~= nil and object_value:IsValid() == true and object_value:IsA(class) == true, label .. " unavailable or class mismatch")
    local name, address = object_value:GetFullName(), finite(object_value:GetAddress(), label .. " address")
    check(type(name) == "string" and #name > 0 and #name <= 1024 and not name:find("Default__", 1, true) and address > 0,
        label .. " identity is invalid")
    return { name = name, address = tostring(address) }
end
local function same(actual, expected, class, label)
    local value = object(actual, class, label)
    check(value.name == expected.name and value.address == expected.address, label .. " changed")
end
local function entries(array, maximum, label)
    check(array ~= nil, label .. " unavailable")
    local ok, count = pcall(function() return array:GetArrayNum() end)
    if not ok then ok, count = pcall(function() return #array end) end
    check(ok and type(count) == "number" and count % 1 == 0 and count >= 0 and count <= maximum, label .. " exceeds bound")
    local values = {}
    for index = 1, count do
        local value = array[index]
        local wrapped, raw = pcall(function() return value:get() end)
        if wrapped then value = raw end
        check(value ~= nil, label .. " entry unavailable")
        values[index] = value
    end
    return values
end
local function color(value)
    -- FLinearColor has R/G/B/A in the captured native SDK; unlike FRotator it is not lower-case.
    return { R = finite(value.R, "red"), G = finite(value.G, "green"), B = finite(value.B, "blue"), A = finite(value.A, "alpha") }
end
local function colors_equal(left, right)
    for _, field in ipairs({ "R", "G", "B", "A" }) do if math.abs(left[field] - right[field]) > 0.000001 then return false end end
    return true
end
local function native_color(material, parameter, dynamic)
    local result
    if dynamic then result = material:K2_GetVectorParameterValueByInfo(parameter.native_info)
    else result = material:K2_GetVectorParameterValue(parameter.native_name) end
    return color(result)
end
local function resolve_head(deps)
    local player = deps.get_player()
    local record = object(player, PLAYER, "player")
    local world = player:GetWorld()
    local world_record = object(world, "/Script/Engine.World", "world")
    local form, wolf = player.Form, player:IsInWolfForm()
    check((form == 0 or form == 1) and type(wolf) == "boolean" and not wolf, "unsupported player form")
    local head = player.HeadMesh
    local head_record = object(head, MESH, "HeadMesh")
    same(head:GetOwner(), record, PLAYER, "head owner")
    local head_asset = object(head:GetSkeletalMeshAsset(), "/Script/Engine.SkeletalMesh", "head asset")
    check(head_asset.name == HEAD, "observed Coen head asset changed")
    local mesh_class = deps.static_find_object(MESH)
    local count = 0
    for _, component in ipairs(entries(player:K2_GetComponentsByClass(mesh_class), 32, "player components")) do
        if component:GetAddress() == head:GetAddress() then count = count + 1 end
    end
    check(count == 1, "HeadMesh must occur once in the local player's component list")
    local slots = entries(head:GetMaterialSlotNames(), 16, "head slot names")
    check(#slots == head:GetNumMaterials() and #slots >= 5, "head material topology changed")
    return { player = player, player_record = record, world = world, world_record = world_record,
        head = head, head_record = head_record, head_asset = head_asset, form = form, wolf = wolf, slots = slots }
end
local function check_context(deps, expected)
    local current = resolve_head(deps)
    same(current.player, expected.player_record, PLAYER, "player")
    same(current.world, expected.world_record, "/Script/Engine.World", "world")
    same(current.head, expected.head_record, MESH, "head")
    same(current.head:GetSkeletalMeshAsset(), expected.head_asset, "/Script/Engine.SkeletalMesh", "head asset")
    check(current.form == expected.form and current.wolf == expected.wolf and #current.slots == #expected.slots,
        "player form or head topology changed")
    for _, eye in ipairs(EYES) do check(current.slots[eye.slot + 1]:ToString() == eye.slot_name, "eye slot name changed") end
    return current
end
local function discover_eye(context, definition)
    check(context.slots[definition.slot + 1]:ToString() == definition.slot_name, "observed eye slot name changed")
    local material = context.head:GetMaterial(definition.slot)
    local material_record = object(material, MIC, "original eye material")
    check(material_record.name == definition.material_name, "observed eye material asset changed")
    local parent_record = object(material.Parent, "/Script/Engine.MaterialInterface", "original eye parent")
    check(parent_record.name == PARENT_MATERIAL, "observed eye parent shader changed")
    local parameters = {}
    for _, entry in ipairs(entries(material.VectorParameterValues, 128, "eye vector parameters")) do
        local info = entry.ParameterInfo
        local name = info.Name:ToString()
        if name == PARAMETERS[1] or name == PARAMETERS[2] then
            check(parameters[name] == nil, "duplicate eye parameter identity")
            check(info.Association == GLOBAL_PARAMETER and info.Index == -1, "eye parameter is not observed Global2/-1")
            local parameter = { name = name, association = info.Association, index = info.Index,
                native_name = info.Name, native_info = info, observed_override = color(entry.ParameterValue) }
            parameter.original = native_color(material, parameter, false)
            check(colors_equal(parameter.original, parameter.observed_override), "native eye getter disagrees with the observed original override")
            parameters[name] = parameter
        end
    end
    for _, name in ipairs(PARAMETERS) do check(parameters[name] ~= nil, "required observed eye parameter is unavailable: " .. name) end
    return { slot = definition.slot, slot_name = definition.slot_name, native_slot_name = context.slots[definition.slot + 1],
        original = material, original_record = material_record, parent_record = parent_record, parameters = parameters }
end
local function eye_report(eye)
    local result = { slot = eye.slot, slot_name = eye.slot_name, original_material = eye.original_record, original_parent = eye.parent_record, parameters = {} }
    for _, name in ipairs(PARAMETERS) do
        local value = eye.parameters[name]
        result.parameters[name] = { association = value.association, index = value.index, original = value.original,
            observed_override = value.observed_override, source = "runtime-material-getter" }
    end
    return result
end
local function baseline_report(value)
    return { baseline_id = value.id, player = value.context.player_record, world = value.context.world_record,
        head = value.context.head_record, asset = value.context.head_asset, form = value.context.form,
        is_wolf_form = value.context.wolf, eyes = { eye_report(value.eyes[1]), eye_report(value.eyes[2]) } }
end
local function observe(deps)
    baseline = nil
    private_roundtrip_baseline_id = nil
    local context = resolve_head(deps)
    local value = { id = deps.boot_id .. ":" .. deps.nonce, boot_id = deps.boot_id, context = context, eyes = {} }
    for _, definition in ipairs(EYES) do value.eyes[#value.eyes + 1] = discover_eye(context, definition) end
    check_context(deps, context)
    for _, eye in ipairs(value.eyes) do same(context.head:GetMaterial(eye.slot), eye.original_record, MIC, "original eye binding") end
    baseline = value
    return { ok = true, baseline = baseline_report(value), native_original_getters_verified = true }
end
local function revalidate_originals(deps, value)
    check(value ~= nil and value.boot_id == deps.boot_id, "successful baseline observation from this boot is required")
    local current = check_context(deps, value.context)
    for index, eye in ipairs(value.eyes) do
        same(current.head:GetMaterial(eye.slot), eye.original_record, MIC, "original eye binding")
        same(eye.original.Parent, eye.parent_record, "/Script/Engine.MaterialInterface", "original eye parent")
        local fresh = discover_eye(current, EYES[index])
        for _, name in ipairs(PARAMETERS) do
            check(colors_equal(fresh.parameters[name].original, eye.parameters[name].original), "original eye value changed")
            -- Refresh native parameter-info references from the current array before any ByInfo call.
            eye.parameters[name].native_info = fresh.parameters[name].native_info
            eye.parameters[name].native_name = fresh.parameters[name].native_name
        end
    end
    return current
end
local function restore(deps, value, attempts)
    local failures = {}
    for index = #value.eyes, 1, -1 do
        local eye = value.eyes[index]
        local ok, reason = pcall(function()
            local current = check_context(deps, value.context)
            same(eye.original.Parent, eye.parent_record, "/Script/Engine.MaterialInterface", "original eye parent")
            local bound = current.head:GetMaterial(eye.slot)
            if bound:GetAddress() ~= eye.original:GetAddress() then
                local attempted = attempts[index]
                check(attempted ~= nil, "unexpected material replacement; restore refused")
                object(bound, MID, "pilot dynamic material")
                same(bound:GetOuter(), value.context.head_record, MESH, "pilot material outer")
                same(bound.Parent, eye.original_record, MIC, "pilot material parent")
                if attempted.mid_record then same(bound, attempted.mid_record, MID, "pilot material binding")
                else check(bound:GetFName():ToString() == attempted.native_instance_name:ToString(), "unidentified partial pilot material") end
                current.head:SetMaterial(eye.slot, eye.original)
            end
            same(current.head:GetMaterial(eye.slot), eye.original_record, MIC, "restored eye binding")
            for _, name in ipairs(PARAMETERS) do
                check(colors_equal(native_color(eye.original, eye.parameters[name], false), eye.parameters[name].original), "original eye value was altered")
            end
        end)
        if not ok then failures[#failures + 1] = "slot " .. eye.slot .. ": " .. tostring(reason) end
    end
    return #failures == 0, failures
end
local function roundtrip(deps, change_color)
    local value = baseline
    revalidate_originals(deps, value)
    if change_color then check(private_roundtrip_baseline_id == value.id, "verified private-instance restoration for this baseline is required before color") end
    check(not attempted_operations[deps.operation], "each native material pilot is limited to one attempt per boot")
    attempted_operations[deps.operation] = true
    local attempts, readbacks = {}, {}
    local ok, failure = pcall(function()
        for index, eye in ipairs(value.eyes) do
            check_context(deps, value.context)
            same(value.context.head:GetMaterial(eye.slot), eye.original_record, MIC, "pre-create original eye binding")
            local native_instance_name = change_color and eye.native_slot_name or eye.original:GetFName()
            attempts[index] = { native_instance_name = native_instance_name }
            -- OptionalName is an observed native FName, never a Lua string.
            local mid = value.context.head:CreateDynamicMaterialInstance(eye.slot, eye.original, native_instance_name)
            local mid_record = object(mid, MID, "private eye material")
            attempts[index].mid_record = mid_record
            check(mid_record.address ~= eye.original_record.address, "private material aliases the shared original")
            same(mid:GetOuter(), value.context.head_record, MESH, "private material outer")
            same(mid.Parent, eye.original_record, MIC, "private material parent")
            same(value.context.head:GetMaterial(eye.slot), mid_record, MID, "private eye slot binding")
            local eye_readback = { slot = eye.slot, private_material = mid_record, inherited = {} }
            for _, name in ipairs(PARAMETERS) do
                local parameter = eye.parameters[name]
                eye_readback.inherited[name] = native_color(mid, parameter, true)
                check(colors_equal(eye_readback.inherited[name], parameter.original), "private instance does not inherit the verified original value")
            end
            if change_color then
                check_context(deps, value.context)
                local parameter = eye.parameters.Leukocoria_Color
                local original = parameter.original
                local desired = { R = original.B, G = original.G, B = original.R, A = original.A }
                check(math.abs(desired.R - original.R) >= 0.01, "bounded color test would be indistinguishable")
                -- Only the newly created, verified player-owned private MID receives a color write.
                mid:SetVectorParameterValueByInfo(parameter.native_info, desired)
                eye_readback.test_color = native_color(mid, parameter, true)
                eye_readback.desired = desired
                check(colors_equal(eye_readback.test_color, desired), "private color setter readback mismatch")
                check(colors_equal(native_color(mid, eye.parameters.CloudyIrisColor, true), eye.parameters.CloudyIrisColor.original),
                    "unselected eye parameter changed")
            end
            readbacks[#readbacks + 1] = eye_readback
        end
        check_context(deps, value.context)
    end)
    local restored, restore_failures = restore(deps, value, attempts)
    if not restored then baseline = nil end
    if not change_color and ok and restored then private_roundtrip_baseline_id = value.id end
    return { ok = ok and restored, baseline_id = value.id, operation = deps.operation, native_roundtrip_verified = ok and restored,
        original_bindings_restored = restored, original_values_verified = restored, readbacks = readbacks,
        failure = not ok and tostring(failure) or nil, restoration_failures = restore_failures,
        applied_in_game = false, visual_effect_verified = false,
        limitation = "The transaction restores original bindings before returning. Numeric readback is not visible eye-color or shader color-space proof." }
end

function Pilot.run(deps)
    local ok, result = pcall(function()
        check(type(deps) == "table" and deps.game_thread == true and type(deps.identity) == "table"
            and deps.identity.build_id == BUILD and deps.identity.executable_sha256 == HASH, "exact current-build game thread required")
        check(type(deps.boot_id) == "string" and type(deps.nonce) == "string" and #deps.nonce == 32
            and deps.nonce:match("^%x+$") ~= nil, "fresh boot and nonce required")
        if deps.operation == "observe" then check(deps.intent == "eye-observe", "wrong observe intent"); return observe(deps) end
        if deps.operation == "private-instance-roundtrip" then
            check(deps.intent == "eye-private-instance-roundtrip", "wrong private-instance intent"); return roundtrip(deps, false)
        end
        if deps.operation == "color-roundtrip" then
            check(deps.intent == "eye-color-roundtrip", "wrong color intent"); return roundtrip(deps, true)
        end
        error("unsupported eye pilot operation", 0)
    end)
    if not ok then baseline = nil; result = { ok = false, reason = tostring(result), applied_in_game = false } end
    result.gameplay_verified, result.visual_effect_verified = false, false
    return result
end

return Pilot
