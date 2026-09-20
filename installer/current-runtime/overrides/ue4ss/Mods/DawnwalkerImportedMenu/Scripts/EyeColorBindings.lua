local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("eye_color_owned_mid_bindings")
local M = {}
local PREFIX = "/Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/Materials/"
local NAMES = { "MI_Coen_Eyeball_L_Vampire_night", "MI_Coen_Eyeball_R_Vampire_Night" }
local MIC, MID = "/Script/Engine.MaterialInstanceConstant", "/Script/Engine.MaterialInstanceDynamic"
local MAX_GLOW = 3
local EMISSIVE = "Emissivnes"
-- Tuned live in game on 2026-09-12 (build 25232147, vampire night form, user judging):
--  * Leukocoria (the eyeshine) is the only emissive part of the eye. Pure hue, moderate
--    intensity: x2.5-3 at Emissivnes 250-300 stays the chosen colour; x10 at 500 or any
--    Emissivnes in the thousands tone-maps to orange/white.
--  * The iris body's colour comes from a natural-eye atlas via IrisColor U/V; there is
--    no saturated red in it, but (0.5, 0.10) reads red, (0.95, 0.70) amber, (0.05, 0.33)
--    blue, (0.5, 0.95) green-yellow. Iris_Value above ~4 also washes to orange face-on,
--    so the body stays moderate and the shine carries the glow.
--  * CloudyIrisColor/Radius/Hardness and the human material's Emissivnes change nothing.
-- The shine colour is the preset colour at (SHINE_BASE + glow * SHINE_PER_GLOW) with an
-- absolute Emissivnes of (EMISSIVE_BASE + glow * EMISSIVE_PER_GLOW); the iris body takes
-- the atlas point nearest the preset's hue, saturated and brightened with the glow.
local SHINE_BASE, SHINE_PER_GLOW = 1.0, 0.7
local EMISSIVE_BASE, EMISSIVE_PER_GLOW = 100, 70
local IRIS_ATLAS = {
    red = { u = 0.5, v = 0.10 }, amber = { u = 0.95, v = 0.70 }, green = { u = 0.5, v = 0.95 }, blue = { u = 0.05, v = 0.33 },
}
local function hueOf(r, g, b)
    local max, min = math.max(r, g, b), math.min(r, g, b)
    if max - min < 1e-6 then return 0, 0 end
    local d = max - min
    local h
    if max == r then h = ((g - b) / d) % 6 elseif max == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    return h * 60, d / max
end
local function irisRecipe(r, g, b, glow)
    local hue, saturation = hueOf(r, g, b)
    local point = IRIS_ATLAS.red
    if saturation > 0.15 then
        if hue >= 20 and hue < 65 then point = IRIS_ATLAS.amber
        elseif hue >= 65 and hue < 170 then point = IRIS_ATLAS.green
        elseif hue >= 170 and hue < 330 then point = IRIS_ATLAS.blue end
    end
    return {
        { name = "IrisColor1_U", value = point.u }, { name = "IrisColor1_V", value = point.v },
        { name = "IrisColor2_U", value = point.u }, { name = "IrisColor2_V", value = point.v },
        { name = "IrisColorBalance", value = 1 },
        -- Accepted by the user on 2026-09-12 at glow 2.4: saturation 8, value 2.3.
        { name = "Iris_Saturation", value = 1.5 + glow * 2.7 },
        { name = "Iris_Value", value = 1.6 + glow * 0.3 },
    }
end
-- Which material the private eye instances derive from. "night": the game's vampire-night
-- eyeball variants (leukocoria eyeshine - a glint in the pupil, the original design).
-- "human": the eye material the head is actually wearing, so the whole iris keeps its
-- human rendering and can be tinted and made emissive as a whole.
local parentMode = "night"
local state, loaded = nil, false
local loadedSources = {}
local function check(value, reason) assert(value == true, reason) end
local function count(values)
    local ok, length = pcall(function() return values:GetArrayNum() end)
    if not ok then length = #values end
    check(type(length) == "number" and length >= 0 and length % 1 == 0, "Invalid native array count")
    return length
end
local function unwrap(value)
    local wrapped, raw = pcall(function() return value:get() end)
    return wrapped and raw or value
end
local function identity(object, class)
    check(object ~= nil and object:IsValid() and object:IsA(class), "Eye object is absent or class changed")
    return object:GetAddress()
end
local function color(value)
    local result = {}
    for _, field in ipairs({ "R", "G", "B", "A" }) do
        local channel = value[field]
        check(type(channel) == "number" and channel == channel and math.abs(channel) < math.huge, "Invalid color readback")
        result[field] = channel
    end
    return result
end
local function equal(left, right)
    for _, field in ipairs({ "R", "G", "B", "A" }) do if math.abs(left[field] - right[field]) > .000001 then return false end end
    return true
end
local function scalar(value)
    check(type(value) == "number" and value == value and math.abs(value) < math.huge, "Invalid scalar readback")
    return value
end
local function near(left, right) return math.abs(left - right) <= math.max(.001, math.abs(right) * .0001) end
local function parameter(material)
    local values = material.VectorParameterValues
    local length = count(values)
    check(length >= 1 and length <= 128, "Unexpected vector parameter array")
    local found
    for index = 1, length do
        local entry = unwrap(values[index])
        local info = entry.ParameterInfo
        if info.Name:ToString() == "Leukocoria_Color" then
            check(found == nil and info.Association == 2 and info.Index == -1, "Ambiguous eye color parameter")
            found = info
        end
    end
    check(found ~= nil, "Eye color parameter missing")
    return found
end
local function context(deps)
    local player = deps.get_player()
    local playerId = identity(player, "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
    local worldId = identity(player:GetWorld(), "/Script/Engine.World")
    local head = player.HeadMesh
    local headId = identity(head, "/Script/Engine.SkeletalMeshComponent")
    check(head:GetOwner():GetAddress() == playerId and not player:IsInWolfForm(), "Unsupported head ownership/form")
    check(head:GetSkeletalMeshAsset():GetFullName() == "SkeletalMesh /Game/_Dawnwalker/Characters/Heads/HMA_Coen_Head_A/SK_HMA_Coen_Head_A.SK_HMA_Coen_Head_A", "Unexpected head asset")
    local nativeSlots = head:GetMaterialSlotNames()
    check(count(nativeSlots) >= 5 and count(nativeSlots) <= 16, "Unexpected eye slot count")
    local slots = { [4] = unwrap(nativeSlots[4]), [5] = unwrap(nativeSlots[5]) }
    check(slots[4]:ToString() == "shader_eyeLeft_shader" and slots[5]:ToString() == "shader_eyeRight_shader", "Eye slot topology changed")
    return { player = player, playerId = playerId, worldId = worldId, head = head, headId = headId, form = player.Form, slots = slots }
end
local function live(deps)
    local current = context(deps)
    check(state ~= nil and current.playerId == state.context.playerId and current.worldId == state.context.worldId
        and current.headId == state.context.headId and current.form == state.context.form, "Eye baseline belongs to a different form or session")
    return current
end
local function restore(deps)
    if not state or not state.active then return { ok = true, restored = true, no_changes = true } end
    local current = live(deps)
    local failures = {}
    for _, eye in ipairs(state.eyes) do
        local ok, reason = pcall(function()
            check(identity(eye.original, MIC) == eye.originalId, "Original eye material identity changed")
            local bound = current.head:GetMaterial(eye.slot)
            if bound:GetAddress() ~= eye.originalId then
                check(eye.attempted == true and identity(bound, MID) > 0 and bound:GetOuter():GetAddress() == current.headId
                    and bound.Parent:GetAddress() == eye.sourceId and bound:GetFName():ToString() == eye.name:ToString(), "Refusing restoration over foreign material")
                check(eye.midId == nil or bound:GetAddress() == eye.midId, "Refusing restoration over replacement private material")
                current.head:SetMaterial(eye.slot, eye.original)
            end
            check(current.head:GetMaterial(eye.slot):GetAddress() == eye.originalId, "Original eye binding restoration failed")
            check(equal(color(eye.original:K2_GetVectorParameterValue(parameter(eye.original).Name)), eye.originalColor), "Original shared eye color changed")
        end)
        if not ok then failures[#failures + 1] = tostring(reason) end
    end
    check(#failures == 0, table.concat(failures, " | "))
    state.active = false
    return { ok = true, restored = true }
end
function M.IsActive() return state ~= nil and state.active == true end
function M.ParentMode() return parentMode end
function M.SetParentMode(mode)
    check(mode == "night" or mode == "human", "Eye parent mode must be night or human")
    check(not M.IsActive(), "Restore the original eyes before changing the eye parent")
    parentMode = mode
end
local function sourceFor(original, index)
    if parentMode == "human" then return original end
    return StaticFindObject(PREFIX .. NAMES[index] .. "." .. NAMES[index])
end
function M.ObserveTransition(deps)
    if not M.IsActive() then return false end
    local player = deps.get_player()
    check(identity(player, "/Script/Dawnwalker.DawnwalkerPlayerCharacter") == state.context.playerId,
        "Player changed while eye restoration remains pending")
    if player.Form == state.context.form then return false end
    local head = state.context.head
    check(head:IsValid() == true and head:GetAddress() == state.context.headId,
        "Previous eye component is unavailable during form transition")
    for _, eye in ipairs(state.eyes) do
        check(eye.midId ~= nil and head:GetMaterial(eye.slot):GetAddress() ~= eye.midId,
            "Form changed while an owned eye material remains bound; restore the previous form or restart the game")
    end
    state.active = false
    return true
end
function M.ResetSession(deps)
    if state then
        -- Inspect the retained head directly: context may reject a new form while
        -- that same component still owns our materials and restoration baseline.
        local head = state.context.head
        if head:IsValid() == true and head:GetAddress() == state.context.headId then
            for _, eye in ipairs(state.eyes) do
                check(eye.midId == nil or head:GetMaterial(eye.slot):GetAddress() ~= eye.midId,
                    "The previous head still uses an owned eye material; restore it before releasing the baseline")
            end
            state.active = false
        else
            state = nil
        end
    end
    loaded = false
end
function M.run(deps, operation, hex, glow)
    check(IsInGameThread() == true, "Eye pilot requires game thread")
    if operation == "load" then
        local changed = not loaded
        local currentSources = {}
        for _, name in ipairs(NAMES) do
            local path = PREFIX .. name .. "." .. name
            local material = StaticFindObject(path)
            if material == nil or material:IsValid() ~= true then
                local library = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
                identity(library, "/Script/Engine.KismetSystemLibrary")
                local softPath = library:MakeSoftObjectPath(path)
                check(softPath ~= nil, "Soft object path construction failed")
                local reference = library:Conv_SoftObjPathToSoftObjRef(softPath)
                check(reference ~= nil, "Soft object reference construction failed")
                local text = library:Conv_SoftObjectReferenceToString(reference)
                if type(text) ~= "string" then text = text:ToString() end
                check(text == path, "Soft reference does not match the allowlisted eye material")
                material = library:LoadAsset_Blocking(reference)
            end
            local materialId = identity(material, MIC)
            currentSources[name] = materialId
            changed = changed or loadedSources[name] ~= materialId
            check(material:GetFullName() == "MaterialInstanceConstant " .. path, "Loaded material identity differs")
        end
        if not changed then return { ok = true, loaded = true } end
        local observed = deps.observe()
        check(observed.ok == true, observed.reason or "Material observation failed")
        for _, name in ipairs(NAMES) do
            local matched = false
            for _, variant in ipairs(observed.loaded_variants) do
                if variant.path == PREFIX .. name .. "." .. name then
                    local switch = variant.ok and variant.value.effective_static_switches["switch:Enable Leukocoria:2:-1"]
                    check(switch ~= nil and switch.value == true, "Loaded eye shader does not enable color branch")
                    matched = true
                end
            end
            check(matched, "Loaded source missing from bounded observation")
        end
        loaded, loadedSources = true, currentSources
        return { ok = true, loaded = true, observation = observed }
    end
    if operation == "restore" then M.ObserveTransition(deps); return restore(deps) end
    if operation == "tune" then
        -- Live parameter tuning on the private instances a colour is already applied to.
        -- Only names in the reviewed set (deps.parameters, from the observation module)
        -- are accepted, nothing is written to a shared material, and every write is read
        -- back. This exists so the right whole-iris recipe can be found in game without
        -- a restart per attempt; the recipe is then baked into "apply".
        check(M.IsActive(), "Apply a color before tuning eye parameters")
        check(type(hex) == "table" and #hex >= 1, "Provide at least one parameter to tune")
        local reviewed = deps.parameters or {}
        local current = live(deps)
        local readbacks = {}
        for _, entry in ipairs(hex) do
            local name = entry.name
            local kind = reviewed.vector and reviewed.vector[name] and "vector" or reviewed.scalar and reviewed.scalar[name] and "scalar" or nil
            check(kind ~= nil, "Not a reviewed eye parameter: " .. tostring(name))
            for _, eye in ipairs(state.eyes) do
                check(eye.mid ~= nil and eye.mid:IsValid() == true and current.head:GetMaterial(eye.slot):GetAddress() == eye.mid:GetAddress(), "Private eye instance not bound")
                local fname = FName(name)
                if kind == "vector" then
                    check(type(entry.value) == "table", "Vector parameter needs a colour")
                    eye.mid:SetVectorParameterValue(fname, entry.value)
                    local actual = color(eye.mid:K2_GetVectorParameterValue(fname))
                    check(equal(actual, entry.value), "Tuned vector readback differs: " .. name)
                    readbacks[#readbacks + 1] = string.format("%s=(%.2f,%.2f,%.2f)", name, actual.R, actual.G, actual.B)
                else
                    check(type(entry.value) == "number", "Scalar parameter needs a number")
                    eye.mid:SetScalarParameterValue(fname, entry.value)
                    local actual = scalar(eye.mid:K2_GetScalarParameterValue(fname))
                    check(near(actual, entry.value), "Tuned scalar readback differs: " .. name)
                    readbacks[#readbacks + 1] = string.format("%s=%.3f", name, actual)
                end
            end
        end
        return { ok = true, readbacks = readbacks }
    end
    check(operation == "apply" and loaded, "Observe enabled night sources before applying a color")
    check(type(hex) == "string" and hex:match("^%x%x%x%x%x%x$") ~= nil, "Six hex color digits required")
    glow = glow == nil and 0 or glow
    check(type(glow) == "number" and glow == glow and glow >= 0 and glow <= MAX_GLOW, "Eye glow strength must be between 0 and " .. MAX_GLOW)
    local brightness = SHINE_BASE + glow * SHINE_PER_GLOW
    local function linear(pair)
        local channel = tonumber(pair, 16) / 255
        return (channel <= .04045 and channel / 12.92 or ((channel + .055) / 1.055) ^ 2.4)
    end
    local base = { R = linear(hex:sub(1, 2)), G = linear(hex:sub(3, 4)), B = linear(hex:sub(5, 6)) }
    local desired = { R = base.R * brightness, G = base.G * brightness, B = base.B * brightness, A = 1 }
    local wantedEmissive = EMISSIVE_BASE + glow * EMISSIVE_PER_GLOW
    local recipe = irisRecipe(base.R, base.G, base.B, glow)
    M.ObserveTransition(deps)
    local reusable
    if state and not state.active then
        local current = context(deps)
        local same = current.playerId == state.context.playerId and current.worldId == state.context.worldId
            and current.headId == state.context.headId and current.form == state.context.form
        for index, eye in ipairs(state.eyes) do
            local source = sourceFor(current.head:GetMaterial(eye.slot), index)
            same = same and current.head:GetMaterial(eye.slot):GetAddress() == eye.originalId
                and source ~= nil and source:IsValid() == true and source:GetAddress() == eye.sourceId
        end
        if not same then
            if current.headId == state.context.headId then reusable = state.eyes end
            state = nil
        end
    end
    if not state then
        local current = context(deps)
        local captured = { context = current, eyes = {} }
        for index in ipairs(NAMES) do
            local original = current.head:GetMaterial(index + 2)
            local source = sourceFor(original, index)
            local originalId, sourceId = identity(original, MIC), identity(source, MIC)
            -- The private instance is named per parent, so switching parents never collides
            -- with an instance the previous parent left behind (UE keeps it until GC).
            local privateName = FName(current.slots[index + 3]:ToString() .. (parentMode == "human" and "_HumanTint" or ""))
            captured.eyes[index] = { slot = index + 2, original = original, originalId = originalId,
                originalColor = color(original:K2_GetVectorParameterValue(parameter(original).Name)), source = source, sourceId = sourceId,
                name = privateName }
            local prior = reusable and reusable[index]
            if prior and prior.sourceId == sourceId then
                captured.eyes[index].mid = prior.mid
                captured.eyes[index].midId = prior.midId
                captured.eyes[index].attempted = prior.attempted
            end
        end
        state = captured
    end
    local current = live(deps)
    local ok, result = pcall(function()
        local readbacks = {}
        for _, eye in ipairs(state.eyes) do
            check(identity(eye.source, MIC) == eye.sourceId, "Source material identity changed")
            if eye.mid and eye.mid:IsValid() ~= true then eye.mid, eye.midId = nil, nil end
            local bound = current.head:GetMaterial(eye.slot)
            check(bound:GetAddress() == eye.originalId or eye.mid ~= nil and bound:GetAddress() == eye.mid:GetAddress(), "Eye slot has foreign material")
            if not eye.mid then
                local objectPath = current.head:GetFullName():match("^[^ ]+ (.+)$") .. "." .. eye.name:ToString()
                local existing = StaticFindObject(objectPath)
                check(existing == nil or existing:IsValid() ~= true, "Private eye instance name occupied")
                eye.attempted = true
                state.active = true
                eye.mid = current.head:CreateDynamicMaterialInstance(eye.slot, eye.source, eye.name)
                eye.midId = identity(eye.mid, MID)
                check(eye.midId ~= eye.originalId and eye.midId ~= eye.sourceId and eye.mid:GetFName():ToString() == eye.name:ToString(), "Unexpected private eye factory result")
            else
                check(identity(eye.mid, MID) == eye.midId and eye.mid:GetOuter():GetAddress() == current.headId
                    and eye.mid.Parent:GetAddress() == eye.sourceId and eye.mid:GetFName():ToString() == eye.name:ToString(),
                    "Reusable eye material identity changed")
                state.active = true
                current.head:SetMaterial(eye.slot, eye.mid)
            end
            check(eye.mid:GetOuter():GetAddress() == current.headId and eye.mid.Parent:GetAddress() == eye.sourceId, "Private eye instance ownership differs")
            check(current.head:GetMaterial(eye.slot):GetAddress() == eye.mid:GetAddress(), "Private eye instance not bound")
            local info = parameter(eye.source)
            eye.mid:SetVectorParameterValueByInfo(info, desired)
            local actual = color(eye.mid:K2_GetVectorParameterValueByInfo(info))
            check(equal(actual, desired), "Eye color independent readback differs")
            check(equal(color(eye.original:K2_GetVectorParameterValue(parameter(eye.original).Name)), eye.originalColor), "Shared original eye changed")
            -- Glow: the source's effective Emissivnes, scaled, written to the private
            -- instance only. Read back independently; the source must still report its own.
            local emissiveName = FName(EMISSIVE)
            local sourceEmissive = scalar(eye.source:K2_GetScalarParameterValue(emissiveName))
            eye.mid:SetScalarParameterValue(emissiveName, wantedEmissive)
            local actualEmissive = scalar(eye.mid:K2_GetScalarParameterValue(emissiveName))
            check(near(actualEmissive, wantedEmissive), "Eye glow independent readback differs")
            check(near(scalar(eye.source:K2_GetScalarParameterValue(emissiveName)), sourceEmissive), "Shared eye glow changed")
            -- Iris body recipe (see the tuning notes at the top): private instance only.
            for _, entry in ipairs(recipe) do
                local name = FName(entry.name)
                local sourceValue = scalar(eye.source:K2_GetScalarParameterValue(name))
                eye.mid:SetScalarParameterValue(name, entry.value)
                check(near(scalar(eye.mid:K2_GetScalarParameterValue(name)), entry.value), "Iris readback differs: " .. entry.name)
                check(near(scalar(eye.source:K2_GetScalarParameterValue(name)), sourceValue), "Shared iris parameter changed: " .. entry.name)
            end
            readbacks[#readbacks + 1] = { slot = eye.slot, actual = actual, emissive = actualEmissive, source_emissive = sourceEmissive,
                iris = recipe, mid = eye.mid:GetFullName(), mid_address = tostring(eye.midId), parent = eye.source:GetFullName() }
        end
        live(deps)
        return { ok = true, hex = hex, glow = glow, brightness = brightness, readbacks = readbacks, visual_verified = false }
    end)
    if not ok then
        local restored, failure = pcall(restore, deps)
        return { ok = false, reason = tostring(result), restored = restored, restore_error = not restored and tostring(failure) or nil }
    end
    return result
end
return M
