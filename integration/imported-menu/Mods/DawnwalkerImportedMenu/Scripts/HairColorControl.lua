local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("hair_color_control")

-- Runtime hair colour, on the same footing as the eye colour control.
--
-- The player (AHumanoidCharacter, CXXHeaderDump/Dawnwalker.hpp) wears its hair as three
-- separate skeletal mesh components - HairMesh (haircut), BeardMeshComponent and
-- EyebrowMeshComponent - next to the HeadMesh the eyes live on. Their material
-- instances derive from the game's hair shaders: the haircut from M_Hair_v02, whose
-- colour is a melanin/redness model with a multiplicative dye ("BC DyeColor (white
-- means off)") and a grey-hair amount; facial hair from M_Hair_v01 with plain
-- RootColor/TipColor. Those parameter names were read from the game's own material
-- instances (the MI_HMFACE_Coen_Haircuts_A_S0_v2 / MI_HMA_Coen_FacialHair assets).
--
-- Nothing shared is ever written: each component gets a private dynamic instance
-- parented to the material it was wearing, every write is read back, the shared
-- material is re-read afterwards and must be unchanged, and restore rebinds the
-- originals. A colour is applied per hair component and reported per component, so a
-- shader that ignores a parameter is visible in the status rather than hidden.
local M, SECTION = {}, "DWHairColor"
local PLAYER = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local MIC, MID = "/Script/Engine.MaterialInstanceConstant", "/Script/Engine.MaterialInstanceDynamic"
local MATERIAL = "/Script/Engine.MaterialInterface"
local COMPONENTS = { { field = "HairMesh", label = "hair" }, { field = "BeardMeshComponent", label = "beard" }, { field = "EyebrowMeshComponent", label = "eyebrows" } }
-- Reviewed parameter names; tuning and applying accept nothing else.
local PARAMETERS = {
    scalar = { ["BC Melanin"] = true, ["BC Redness"] = true, ["BC Gray Hair Amount"] = true, ["BC Gray Hair Variation Intensity"] = true,
        ["BC Melanin Variation"] = true, ["BC Redness Variation"] = true, ["BC Root Melanin Intensity"] = true, ["BC Tip Melanin Intensity"] = true,
        ["BC Root Redness Intensity"] = true, ["BC Tip Redness Intensity"] = true, ["BC Dye Root Mask Intensity"] = true,
        ["Roughness"] = true, ["Specular"] = true, ["RootRouhness"] = true, ["TipRoughness"] = true },
    vector = { ["BC DyeColor(white means off)"] = true, ["RootColor"] = true, ["TipColor"] = true },
}
-- What an applied colour writes, per shader family.
--
-- Measured in game on 2026-09-12 (build 25232147, Coen, daylight):
--  * Haircut (M_Hair_v02): "BC Melanin" is the lightness knob and it is steep -
--    0.93 black, 0.75 dark brown, 0.6 ash brown, 0.45 blond, 0.3 near white. "BC
--    Redness" warms it (0.4 warm brown; 1.0 goes yellow-green, so it is capped).
--    "BC Gray Hair Amount" mixes grey strands. "BC DyeColor(white means off)" does
--    nothing on this material: its static "Has Dye Color" switch is off in the game's
--    instance and a dynamic instance cannot flip it - light hair with a pure blue dye
--    stayed white. So the haircut takes natural colours only, and a requested colour is
--    mapped to the nearest natural one (lightness -> melanin, warm saturation -> redness).
--  * Facial hair / eyebrows (M_Hair_v01): RootColor/TipColor are the colour itself,
--    any RGB (red eyebrows confirmed on screen).
local MAX_REDNESS = 0.75
local function linearChannel(pair)
    local channel = tonumber(pair, 16) / 255
    return channel <= .04045 and channel / 12.92 or ((channel + .055) / 1.055) ^ 2.4
end
local function parseColour(hex)
    return { R = linearChannel(hex:sub(1, 2)), G = linearChannel(hex:sub(3, 4)), B = linearChannel(hex:sub(5, 6)), A = 1 }
end
-- Natural-hair mapping for the haircut shader. Returns melanin, redness, grey amount.
local function naturalHair(colour)
    local r, g, b = colour.R, colour.G, colour.B
    local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    local lightness = luminance ^ (1 / 2.2)                     -- perceptual 0..1
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local saturation = max > 0 and (max - min) / max or 0
    -- Melanin against perceived lightness, from the in-game sweep of 2026-09-12: the
    -- shader's response is compressed at the dark end (0.93 black, 0.79 still reads
    -- near-black in shade, 0.6 ash brown) and steep at the light end (0.45 already pale
    -- silver-blond, 0.3 white). Piecewise-linear through those observations.
    local anchors = { { 0.00, 0.96 }, { 0.10, 0.92 }, { 0.20, 0.84 }, { 0.35, 0.72 }, { 0.50, 0.62 }, { 0.66, 0.53 }, { 0.87, 0.38 }, { 1.00, 0.08 } }
    local melanin = anchors[#anchors][2]
    for index = 1, #anchors - 1 do
        local a, b = anchors[index], anchors[index + 1]
        if lightness >= a[1] and lightness <= b[1] then
            melanin = a[2] + (b[2] - a[2]) * (lightness - a[1]) / (b[1] - a[1])
            break
        end
    end
    -- Warmth: red-through-yellow hues pull the redness knob (red strongest); cool hues
    -- stay neutral, and dark colours barely warm at all - a black with a red cast is
    -- still black.
    local warmth = 0
    if max > 0 and max - min > 1e-6 then
        local d = max - min
        local hue = max == r and ((g - b) / d) % 6 or max == g and (b - r) / d + 2 or (r - g) / d + 4
        if hue > 3 then hue = hue - 6 end                          -- centre red on 0
        if math.abs(hue) <= 1.2 then warmth = saturation * (1 - math.abs(hue) / 2.4) end
    end
    warmth = warmth * math.min(1, lightness * 2.5)
    -- Warmth is a weak knob on this shader (0.48 barely showed on blond), so it is
    -- driven hard: a saturated warm colour lands at the cap.
    local redness = math.min(MAX_REDNESS, warmth * 1.4)
    -- Grey strands only for near-neutral light colours (white, silver, platinum).
    local grey = (saturation < 0.12 and lightness > 0.6) and math.min(1, (lightness - 0.6) * 2.5) or 0
    return math.max(0, math.min(1, melanin)), redness, grey
end
M.NaturalHair = naturalHair
local function recipe(hairHex, browHex)
    local plan = {}
    if hairHex then
        local colour = parseColour(hairHex)
        local melanin, redness, grey = naturalHair(colour)
        plan.haircut = { scalar = { ["BC Melanin"] = melanin, ["BC Redness"] = redness, ["BC Gray Hair Amount"] = grey } }
    end
    if browHex then
        local colour = parseColour(browHex)
        plan.facial = { vector = { RootColor = colour, TipColor = colour } }
    end
    return plan
end

local state = nil
local function check(value, reason) assert(value == true, reason) end
local function valid(object) return object ~= nil and object:IsValid() == true end
local function identity(object, class)
    check(valid(object) and object:IsA(class) == true, "Hair object is absent or class changed")
    return object:GetAddress()
end
local function color(value)
    local result = {}
    for _, field in ipairs({ "R", "G", "B", "A" }) do
        local channel = value[field]
        check(type(channel) == "number" and channel == channel and math.abs(channel) < math.huge, "Invalid colour readback")
        result[field] = channel
    end
    return result
end
local function scalar(value)
    check(type(value) == "number" and value == value and math.abs(value) < math.huge, "Invalid scalar readback")
    return value
end
local function equal(left, right)
    for _, field in ipairs({ "R", "G", "B", "A" }) do if math.abs(left[field] - right[field]) > .000001 then return false end end
    return true
end
local function near(left, right) return math.abs(left - right) <= math.max(.001, math.abs(right) * .0001) end
local function shortName(object)
    -- "MaterialInstanceConstant /Game/.../MI_X.MI_X" -> "MI_X"
    local path = tostring(object:GetFullName()):gsub("^%S+%s+", "")
    return path:match("%.([^./]+)$") or path:match("([^/]+)$") or "?"
end

-- Which shader family a component's material belongs to, by walking to the base
-- material. Unknown families are reported and left alone.
local function family(material)
    -- Eyelashes share the facial-hair shader but are not hair the player colours.
    if tostring(material:GetFullName()):find("Eyelash", 1, true) then return "unknown" end
    local current = material
    for _ = 1, 4 do
        if not valid(current) then return "unknown" end
        if current:IsA(MIC) ~= true then
            local name = tostring(current:GetFullName())
            if name:find("M_Hair_v02", 1, true) then return "haircut" end
            if name:find("M_Hair_v01", 1, true) then return "facial" end
            return "unknown"
        end
        current = current.Parent
    end
    return "unknown"
end

-- Every skeletal mesh component the player actually has, with a label: the named
-- HairMesh/Beard/Eyebrow fields when they are set, otherwise the component's own name.
-- The appearance system attaches meshes dynamically, so the named fields alone are not
-- enough (observed empty on build 25232147); the material's shader family decides.
local function skeletalComponents(player)
    local components, seen = {}, {}
    for _, entry in ipairs(COMPONENTS) do
        local component = player[entry.field]
        if valid(component) then components[#components + 1] = { label = entry.label, component = component }; seen[component:GetAddress()] = true end
    end
    -- UMeshComponent covers skeletal meshes and grooms alike (CXXHeaderDump: UGroomComponent
    -- derives from UMeshComponent); on this build the haircut is a groom, not a skeletal
    -- mesh, and the facial hair lives on the Face Mesh.
    local class = StaticFindObject("/Script/Engine.MeshComponent")
    if valid(class) then
        local ok, all = pcall(function() return player:K2_GetComponentsByClass(class) end)
        if ok and all ~= nil then
            local function add(_, wrapped)
                local component = wrapped
                local unwrapped, raw = pcall(function() return wrapped:get() end)
                if unwrapped and raw ~= nil then component = raw end
                if valid(component) and not seen[component:GetAddress()] then
                    seen[component:GetAddress()] = true
                    components[#components + 1] = { label = tostring(component:GetFName():ToString()), component = component }
                end
            end
            if type(all) == "table" then for index = 1, #all do add(index, all[index]) end else all:ForEach(add) end
        end
    end
    check(#components <= 96, "Unexpected number of mesh components")
    return components
end

local function componentsOf(player)
    local found = {}
    for _, entry in ipairs(skeletalComponents(player)) do
        local component = entry.component
        local ok, count = pcall(function() return component:GetNumMaterials() end)
        if ok and type(count) == "number" and count >= 0 and count <= 16 then
            for slot = 0, count - 1 do
                local material = component:GetMaterial(slot)
                if valid(material) then
                    found[#found + 1] = { label = entry.label, component = component, componentId = component:GetAddress(), slot = slot,
                        material = material, family = family(material) }
                end
            end
        end
    end
    check(#found > 0, "The player has no mesh materials to inspect")
    return found
end

function M.IsActive() return state ~= nil and state.active == true end

function M.Observe(getPlayer)
    local player = getPlayer(true)
    check(valid(player) and player:IsA(PLAYER) == true, "Load a save first")
    local parts, other = {}, {}
    for _, hair in ipairs(componentsOf(player)) do
        if hair.family == "unknown" then
            other[#other + 1] = string.format("%s slot%d: %s", hair.label, hair.slot, shortName(hair.material))
            goto continue
        end
        local values = {}
        for name in pairs(PARAMETERS.scalar) do
            local ok, value = pcall(function() return scalar(hair.material:K2_GetScalarParameterValue(FName(name))) end)
            if ok then values[#values + 1] = string.format("%s=%.3f", name, value) end
        end
        for name in pairs(PARAMETERS.vector) do
            local ok, value = pcall(function() return color(hair.material:K2_GetVectorParameterValue(FName(name))) end)
            if ok then values[#values + 1] = string.format("%s=(%.2f,%.2f,%.2f)", name, value.R, value.G, value.B) end
        end
        table.sort(values)
        parts[#parts + 1] = string.format("%s slot%d: %s [%s] %s", hair.label, hair.slot, shortName(hair.material), hair.family, table.concat(values, ", "))
        ::continue::
    end
    if #parts == 0 then return "OBSERVED (read-only): no hair-shader material on any mesh component; other slots: " .. table.concat(other, "; ") end
    return "OBSERVED (read-only): " .. table.concat(parts, " || ") .. (#other > 0 and (" || other: " .. table.concat(other, "; ")) or "")
end

local function writeParameters(hair, mid, scalars, vectors, readbacks)
    for name, value in pairs(scalars or {}) do
        check(PARAMETERS.scalar[name] == true, "Not a reviewed hair parameter: " .. name)
        local fname = FName(name)
        local shared = scalar(hair.material:K2_GetScalarParameterValue(fname))
        mid:SetScalarParameterValue(fname, value)
        check(near(scalar(mid:K2_GetScalarParameterValue(fname)), value), "Hair readback differs: " .. name)
        check(near(scalar(hair.material:K2_GetScalarParameterValue(fname)), shared), "Shared hair material changed: " .. name)
        readbacks[#readbacks + 1] = string.format("%s=%.2f", name, value)
    end
    for name, value in pairs(vectors or {}) do
        check(PARAMETERS.vector[name] == true, "Not a reviewed hair parameter: " .. name)
        local fname = FName(name)
        local shared = color(hair.material:K2_GetVectorParameterValue(fname))
        mid:SetVectorParameterValue(fname, value)
        check(equal(color(mid:K2_GetVectorParameterValue(fname)), value), "Hair readback differs: " .. name)
        check(equal(color(hair.material:K2_GetVectorParameterValue(fname)), shared), "Shared hair material changed: " .. name)
        readbacks[#readbacks + 1] = string.format("%s=(%.2f,%.2f,%.2f)", name, value.R, value.G, value.B)
    end
end

-- Bind (or reuse) a private instance on every hair slot of a known family.
local function ensurePrivate(getPlayer)
    local player = getPlayer(true)
    check(valid(player) and player:IsA(PLAYER) == true, "Load a save first")
    local playerId = player:GetAddress()
    if state and state.playerId ~= playerId then check(not state.active, "Player changed while hair colour is applied; restart the game"); state = nil end
    if not state then
        state = { playerId = playerId, entries = {}, active = false, generation = 0 }
        for _, hair in ipairs(componentsOf(player)) do
            if hair.family ~= "unknown" then
                state.entries[#state.entries + 1] = { label = hair.label, field = hair.field, slot = hair.slot, family = hair.family,
                    component = hair.component, componentId = hair.componentId, material = hair.material, original = hair.material, originalId = identity(hair.material, MATERIAL) }
            end
        end
        check(#state.entries > 0, "No hair-shader material is bound on the player; press Observe to see what is")
    end
    for _, entry in ipairs(state.entries) do
        check(valid(entry.component) and entry.component:GetAddress() == entry.componentId, "Hair component changed; restart the game")
        local bound = entry.component:GetMaterial(entry.slot)
        check(valid(bound), "Hair slot lost its material")
        if entry.mid and (not valid(entry.mid) or bound:GetAddress() ~= entry.mid:GetAddress()) then
            -- Something else rebound the slot; only the original is an acceptable state.
            check(bound:GetAddress() == entry.originalId, "Hair slot has a foreign material")
            entry.mid = nil
        end
        if not entry.mid then
            check(bound:GetAddress() == entry.originalId, "Hair slot has a foreign material")
            state.generation = state.generation + 1
            local name = FName(string.format("DWHair_%s_%d_%d", entry.label, entry.slot, state.generation))
            local mid = entry.component:CreateDynamicMaterialInstance(entry.slot, entry.original, name)
            check(valid(mid) and mid:IsA(MID) == true and mid.Parent:GetAddress() == entry.originalId, "Private hair instance was not created")
            check(entry.component:GetMaterial(entry.slot):GetAddress() == mid:GetAddress(), "Private hair instance not bound")
            entry.mid = mid
        end
    end
    state.active = true
    return state.entries
end

-- Apply the hair colour and/or the eyebrow colour (nil leaves that family alone).
function M.Apply(getPlayer, hairHex, browHex)
    for _, hex in ipairs({ hairHex or "", browHex or "" }) do
        check(hex == "" or hex:match("^%x%x%x%x%x%x$") ~= nil, "Six hex colour digits required")
    end
    check((hairHex or browHex) ~= nil, "Choose a hair or eyebrow colour")
    local plan = recipe(hairHex, browHex)
    local entries = ensurePrivate(getPlayer)
    local report, touched = {}, false
    for _, entry in ipairs(entries) do
        local part = plan[entry.family]
        if part then
            local readbacks = {}
            writeParameters(entry, entry.mid, part.scalar, part.vector, readbacks)
            report[#report + 1] = entry.label .. ": " .. table.concat(readbacks, ", ")
            touched = true
        end
    end
    check(touched, "No hair component of that kind is bound on the player")
    return table.concat(report, " || ")
end

function M.Tune(getPlayer, tuning)
    check(M.IsActive(), "Apply a hair colour before tuning")
    local entries = ensurePrivate(getPlayer)
    local report = {}
    for _, entry in ipairs(entries) do
        local readbacks = {}
        local ok, failure = pcall(writeParameters, entry, entry.mid, tuning.scalar, tuning.vector, readbacks)
        report[#report + 1] = entry.label .. ": " .. (ok and table.concat(readbacks, ", ") or ("skipped - " .. tostring(failure):gsub("^.-:%d+: ", "")))
    end
    return table.concat(report, " || ")
end

function M.Restore()
    if not state or not state.active then return "Original hair already in place." end
    local failures = {}
    for _, entry in ipairs(state.entries) do
        local ok, failure = pcall(function()
            check(valid(entry.component) and entry.component:GetAddress() == entry.componentId, "Hair component changed")
            local bound = entry.component:GetMaterial(entry.slot)
            if valid(bound) and bound:GetAddress() ~= entry.originalId then
                check(entry.mid ~= nil and bound:GetAddress() == entry.mid:GetAddress(), "Refusing restoration over a foreign material")
                entry.component:SetMaterial(entry.slot, entry.original)
            end
            check(entry.component:GetMaterial(entry.slot):GetAddress() == entry.originalId, "Original hair binding restoration failed")
        end)
        if not ok then failures[#failures + 1] = tostring(failure) end
    end
    check(#failures == 0, table.concat(failures, " | "))
    state.active = false
    return "Original hair restored."
end

function M.ResetSession()
    -- A new session has a new pawn; the retained instances belong to the old one.
    state = nil
end

-- "Name=value; Other=#rrggbb" for tuning. Hex values are linearised; "*k" scales.
local function parseTuning(text)
    local tuning = { scalar = {}, vector = {} }
    local any = false
    for pair in tostring(text):gmatch("[^;]+") do
        local name, raw = pair:match("^%s*(.-)%s*=%s*(.-)%s*$")
        check(name ~= nil and name ~= "" and raw ~= nil and raw ~= "", "Tuning entries look like Name=value; Name=#rrggbb*2.")
        local hex, scale = raw:match("^#(%x%x%x%x%x%x)%*?([%d%.]*)$")
        if hex then
            local factor = tonumber(scale) or 1
            local function linear(pair2)
                local channel = tonumber(pair2, 16) / 255
                return (channel <= .04045 and channel / 12.92 or ((channel + .055) / 1.055) ^ 2.4) * factor
            end
            check(PARAMETERS.vector[name] == true, "Not a reviewed hair colour parameter: " .. name)
            tuning.vector[name] = { R = linear(hex:sub(1, 2)), G = linear(hex:sub(3, 4)), B = linear(hex:sub(5, 6)), A = 1 }
        else
            local number = tonumber(raw)
            check(number ~= nil, "Tuning value must be a number or #rrggbb: " .. raw)
            check(PARAMETERS.scalar[name] == true, "Not a reviewed hair scalar parameter: " .. name)
            tuning.scalar[name] = number
        end
        any = true
    end
    check(any, "Provide at least one parameter to tune")
    return tuning
end
M.ParseTuning = parseTuning

function M.Init(menu, helpers)
    local applied, published = "", nil
    local function sync(message)
        local signature = applied .. ":" .. tostring(M.IsActive()) .. ":" .. message
        if published == signature then return end
        menu.Set(SECTION, "color", applied)
        menu.Set(SECTION, "owned", M.IsActive())
        menu.SetLabel(SECTION, "status", message)
        published = signature
    end
    local function guarded(callback)
        ExecuteInGameThread(function()
            local ok, failure = pcall(callback)
            if ok then return end
            local message = tostring(failure):gsub("^.-:%d+: ", "")
            sync("Hair colour could not be applied: " .. message)
            error(message, 0)
        end)
    end
    local appliedBrows = ""
    local function apply(value)
        menu.Set(SECTION, "color", applied)
        guarded(function()
            assert(type(value) == "string" and value:match("^#%x%x%x%x%x%x$"), "Choose a valid six-digit hair colour.")
            local report = M.Apply(helpers.GetPlayer, value:sub(2), nil)
            applied = value:lower()
            local melanin, redness, grey = naturalHair(parseColour(value:sub(2)))
            sync(string.format("Applied in game: hair %s as natural melanin %.2f, redness %.2f, grey %.2f. %s", applied:upper(), melanin, redness, grey, report))
        end)
    end
    local function applyBrows(value)
        menu.Set(SECTION, "brows", appliedBrows)
        guarded(function()
            assert(type(value) == "string" and value:match("^#%x%x%x%x%x%x$"), "Choose a valid six-digit eyebrow colour.")
            local report = M.Apply(helpers.GetPlayer, nil, value:sub(2))
            appliedBrows = value:lower()
            menu.Set(SECTION, "brows", appliedBrows)
            menu.Set(SECTION, "owned", true)
            menu.SetLabel(SECTION, "browStatus", string.format("Eyebrows in game: %s. %s", appliedBrows:upper(), report))
        end)
    end
    local function restore()
        guarded(function()
            local message = M.Restore()
            applied, appliedBrows = "", ""
            menu.Set(SECTION, "brows", "")
            menu.SetLabel(SECTION, "browStatus", "Select an eyebrow colour to apply it in game.")
            sync(message)
        end)
    end
    local function observe()
        ExecuteInGameThread(function()
            local ok, report = pcall(M.Observe, helpers.GetPlayer)
            menu.SetLabel(SECTION, "observation", ok and report or ("Observation refused: " .. tostring(report):gsub("^.-:%d+: ", "")))
        end)
    end
    local function tune(text)
        if tostring(text):match("^%s*$") then return end
        local tuning = parseTuning(text)
        guarded(function()
            menu.SetLabel(SECTION, "tuning", "Tuned on private hair: " .. M.Tune(helpers.GetPlayer, tuning))
        end)
    end
    function M.RefreshSession() end
    function M.BeforeFormChange() if M.IsActive() then restore() end end
    local resetSession = M.ResetSession
    function M.ResetSession()
        resetSession()
        applied, appliedBrows = "", ""
        menu.Set(SECTION, "brows", "")
        menu.SetLabel(SECTION, "browStatus", "Select an eyebrow colour to apply it in game.")
        sync("Select a hair colour to apply it in game.")
    end
    menu.Register({ id = SECTION, title = "Hair color", tab = "Visuals", items = {
        { id = "color", type = "input", label = "Hair color (natural range)", default = "", onChange = apply },
        { id = "brows", type = "input", label = "Eyebrow color", default = "", onChange = applyBrows },
        { id = "browStatus", type = "label", label = "Select an eyebrow colour to apply it in game." },
        { id = "restore", type = "button", label = "Restore original hair and eyebrows", onClick = restore },
        { id = "owned", type = "checkbox", label = "Hair color override active", default = false,
          onChange = function(value) assert(value == false, "Use a hair preset or the color wheel."); restore() end },
        { id = "status", type = "label", label = "Select a hair colour to apply it in game." },
        { id = "observe", type = "button", label = "Observe hair materials (read-only)", onClick = observe },
        { id = "observation", type = "label", label = "Reads the player's hair, beard and eyebrow materials without changing anything." },
        { id = "tune", type = "input", label = "Tune hair parameters (Name=value; ...)", default = "", onChange = tune },
        { id = "tuning", type = "label", label = "Reviewed names only; written to the private hair instances and read back." },
    } })
end

return M
