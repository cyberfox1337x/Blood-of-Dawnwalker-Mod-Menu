local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_loaded_variant_readonly")

-- An explicit metadata observation, never an asset loader or gameplay/material setter.
local Probe = {}
local MIC = "/Script/Engine.MaterialInstanceConstant"
local MATERIAL = "/Script/Engine.MaterialInterface"
local MESH = "/Script/Engine.SkeletalMeshComponent"
local PLAYER = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local PREFIX = "/Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/Materials/"
local VARIANTS = {
    PREFIX .. "MI_Coen_Eyeball_L_Vampire", PREFIX .. "MI_Coen_Eyeball_R_Vampire",
    PREFIX .. "MI_Coen_Eyeball_L_Vampire_night", PREFIX .. "MI_Coen_Eyeball_R_Vampire_Night",
    PREFIX .. "MI_Coen_Eyeball_L_Vampire_night_Monster", PREFIX .. "MI_Coen_Eyeball_R_Vampire_Night_Monster",
    "/Game/_Dawnwalker/VFX/06_q104_06_IsbrandDissolve/MI_Coen_Eyeball_R_Vampire_CutsceneOnly",
}
local PARAMETERS = {
    vector = { Leukocoria_Color = true, CloudyIrisColor = true },
    scalar = { IrisColor1_U = true, IrisColor1_V = true, IrisColor2_U = true, IrisColor2_V = true,
        IrisColorBalance = true, IrisColorBalanceSmoothness = true, Iris_Saturation = true, Iris_Value = true, Emissivnes = true,
        -- The cloudy-iris overlay's extent and edge (observed on the human material on
        -- 25129649: radius ~0.33, hardness 0). With the colour, they paint the whole iris
        -- a chosen colour - the atlas has no saturated red, so this is the blood-red path.
        CloudyIrisRadius = true, CloudyIrisHardness = true },
    switch = { ["Enable Leukocoria"] = true, EnableCatEye = true },
}
local function check(value, message) if value ~= true then error(message, 0) end end
local function finite(value)
    check(type(value) == "number" and value == value and math.abs(value) < math.huge, "Non-finite native value")
    return value
end
local function identity(value, class)
    check(value ~= nil and value:IsValid() == true and value:IsA(class) == true, "Native object absent or class differs")
    local address, name = finite(value:GetAddress()), value:GetFullName()
    check(address > 0 and type(name) == "string" and #name > 0 and #name <= 1024 and not name:find("Default__", 1, true), "Invalid native identity")
    return { address = tostring(address), name = name }
end
local function same(value, expected, class)
    local actual = identity(value, class)
    check(actual.address == expected.address and actual.name == expected.name, "Native context changed")
end
local function array_values(value, maximum, budget)
    check(value ~= nil, "Native parameter array absent")
    local ok, count = pcall(function() return value:GetArrayNum() end)
    if not ok then ok, count = pcall(function() return #value end) end
    check(ok and type(count) == "number" and count % 1 == 0 and count >= 0 and count <= maximum, "Native array exceeds bounds")
    budget.samples = budget.samples + count
    check(budget.samples <= 2048, "Global native sample budget exceeded")
    local result = {}
    for index = 1, count do
        local entry = value[index]
        local wrapped, actual = pcall(function() return entry:get() end)
        if wrapped then entry = actual end
        check(entry ~= nil, "Native array item absent")
        result[#result + 1] = entry
    end
    return result
end
local function color(value)
    return { R = finite(value.R), G = finite(value.G), B = finite(value.B), A = finite(value.A) }
end
local function inspect_material(material, budget)
    local leaf = identity(material, MIC)
    local report = { material = leaf, layers = {}, effective_parameters = {}, effective_static_switches = {},
        static_switch_limitation = "Only explicit nearest bOverride=true runtime switch records establish the reported value; missing base defaults remain unknown." }
    local contexts, current, seen = {}, material, {}
    local switch_resolution_blocked = false
    for depth = 0, 3 do
        local record = identity(current, MATERIAL)
        check(not seen[record.address], "Material parent cycle")
        seen[record.address] = true
        if current:IsA(MIC) ~= true then
            check(current:IsA("/Script/Engine.Material") == true, "Unexpected non-constant material ancestor")
            report.base_material = record
            break
        end
        local parent = identity(current.Parent, MATERIAL)
        local layer = { identity = record, parent = parent, depth = depth, parameters = {}, static_switches = {} }
        contexts[#contexts + 1] = { object = current, identity = record, parent = parent }
        for _, kind in ipairs({ "scalar", "vector", "switch" }) do
            local ok, result = pcall(function()
                local values = kind == "scalar" and current.ScalarParameterValues or kind == "vector" and current.VectorParameterValues
                    or current.StaticParametersRuntime.StaticSwitchParameters
                local records, unique = {}, {}
                for _, entry in ipairs(array_values(values, 128, budget)) do
                    local info = entry.ParameterInfo
                    local name = info.Name:ToString()
                    if PARAMETERS[kind][name] then
                        check(type(info.Association) == "number" and type(info.Index) == "number", "Parameter identity unavailable")
                        local key = kind .. ":" .. name .. ":" .. tostring(info.Association) .. ":" .. tostring(info.Index)
                        check(not unique[key], "Duplicate material parameter identity")
                        unique[key] = true
                        local observed = { name = name, association = info.Association, index = info.Index, depth = depth }
                        if kind == "switch" then
                            check(type(entry.Value) == "boolean" and type(entry.bOverride) == "boolean", "Static switch flags unavailable")
                            observed.value, observed.overridden = entry.Value, entry.bOverride
                            if entry.bOverride and not switch_resolution_blocked and not report.effective_static_switches[key] then report.effective_static_switches[key] = observed end
                        else
                            observed.override_value = kind == "vector" and color(entry.ParameterValue) or finite(entry.ParameterValue)
                            if not report.effective_parameters[key] then
                                check(info.Association == 2 and info.Index == -1, "Name-only native getter requires Global2/index-1")
                                budget.getters = budget.getters + 1
                                check(budget.getters <= 128, "Global getter budget exceeded")
                                local value = kind == "vector" and material:K2_GetVectorParameterValue(info.Name) or material:K2_GetScalarParameterValue(info.Name)
                                observed.native_value = kind == "vector" and color(value) or finite(value)
                                observed.source = "runtime-material-getter"
                                report.effective_parameters[key] = observed
                            end
                        end
                        records[#records + 1] = observed
                    end
                end
                return records
            end)
            if ok then layer[kind] = { ok = true, entries = result }
            else
                layer[kind] = { ok = false, reason = tostring(result) }
                local destination = kind == "switch" and report.effective_static_switches or report.effective_parameters
                for key, observation in pairs(destination) do
                    if key:sub(1, #kind + 1) == kind .. ":" and observation.depth == depth then destination[key] = nil end
                end
                if kind == "switch" then
                    switch_resolution_blocked = true
                    report.static_switch_resolution_incomplete = true
                end
            end
            check(budget.samples <= 2048 and budget.getters <= 128, "Global native observation budget exceeded")
        end
        report.layers[#report.layers + 1] = layer
        current = current.Parent
    end
    check(report.base_material ~= nil, "Material parent depth exceeds four")
    same(material, leaf, MIC)
    for _, entry in ipairs(contexts) do
        same(entry.object, entry.identity, MIC)
        same(entry.object.Parent, entry.parent, MATERIAL)
    end
    return report
end
function Probe.run(deps)
    local ok, result = pcall(function()
        check(deps.game_thread == true and deps.intent == "eye-variant-observe", "Explicit game-thread variant observation required")
        check(deps.identity.build_id == "25232147" and deps.identity.executable_sha256 == "CB9B7D7BD88A6754C0A9C08318AA64D5013DDFD92D5BADCAE84E1B4EA980DCFC", "Reviewed native identity differs")
        local budget = { samples = 0, getters = 0 }
        local player = deps.get_player()
        local context = { player = identity(player, PLAYER), world = identity(player:GetWorld(), "/Script/Engine.World"),
            head = identity(player.HeadMesh, MESH), asset = identity(player.HeadMesh:GetSkeletalMeshAsset(), "/Script/Engine.SkeletalMesh"),
            form = player.Form, is_wolf_form = player:IsInWolfForm() }
        check((context.form == 0 or context.form == 1) and context.is_wolf_form == false, "Unsupported current form")
        check(context.asset.name == "SkeletalMesh /Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/SK_HMA_Coen_Head_A.SK_HMA_Coen_Head_A", "Exact Coen head asset required")
        same(player.HeadMesh:GetOwner(), context.player, PLAYER)
        local names = array_values(player.HeadMesh:GetMaterialSlotNames(), 16, budget)
        check(#names == player.HeadMesh:GetNumMaterials() and #names >= 5
            and names[4]:ToString() == "shader_eyeLeft_shader" and names[5]:ToString() == "shader_eyeRight_shader", "Observed eye slot topology differs")
        local report = { context = context, current_eyes = {}, loaded_variants = {} }
        if type(deps.observe_head_landmarks) == "function" then
            local observed, landmarks = pcall(deps.observe_head_landmarks, player.HeadMesh)
            report.head_landmarks = { ok = observed, value = observed and landmarks or nil, reason = not observed and tostring(landmarks) or nil }
        else report.head_landmarks = { ok = false, reason = "Bounded native head landmark observer was not composed" } end
        local originals = {}
        for slot = 3, 4 do
            local material = player.HeadMesh:GetMaterial(slot)
            originals[slot] = identity(material, MIC)
            local success, value = pcall(inspect_material, material, budget)
            report.current_eyes[#report.current_eyes + 1] = { slot = slot, ok = success, value = success and value or nil, reason = not success and tostring(value) or nil }
        end
        for _, package in ipairs(VARIANTS) do
            check(budget.samples <= 2048 and budget.getters <= 128, "Global native observation budget exceeded")
            local path = package .. "." .. package:match("([^/]+)$")
            local success, value = pcall(function()
                local material = deps.static_find_object(path)
                local record = identity(material, MIC)
                check(record.name == "MaterialInstanceConstant " .. path, "Loaded variant lookup identity differs")
                return inspect_material(material, budget)
            end)
            report.loaded_variants[#report.loaded_variants + 1] = { path = path, ok = success, value = success and value or nil, reason = not success and tostring(value) or nil }
        end
        same(deps.get_player(), context.player, PLAYER)
        same(player:GetWorld(), context.world, "/Script/Engine.World")
        same(player.HeadMesh, context.head, MESH)
        same(player.HeadMesh:GetOwner(), context.player, PLAYER)
        same(player.HeadMesh:GetSkeletalMeshAsset(), context.asset, "/Script/Engine.SkeletalMesh")
        check(player.Form == context.form and player:IsInWolfForm() == context.is_wolf_form, "Player form changed")
        check(player.HeadMesh:GetNumMaterials() == #names, "Material slot count changed")
        for slot = 3, 4 do same(player.HeadMesh:GetMaterial(slot), originals[slot], MIC) end
        check(budget.samples <= 2048 and budget.getters <= 128, "Global native observation budget exceeded")
        report.ok, report.budget = true, budget
        return report
    end)
    if not ok then result = { ok = false, reason = tostring(result) } end
    result.mutation_authorized, result.gameplay_verified, result.visual_effect_verified = false, false, false
    return result
end
-- Exposed read-only so the control can report which reviewed parameters the installed
-- build actually exposes, against this one list rather than a copy of it.
Probe.PARAMETERS = PARAMETERS
return Probe
