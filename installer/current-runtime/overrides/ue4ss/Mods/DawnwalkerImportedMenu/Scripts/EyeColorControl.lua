local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("eye_color_menu_adapter")
local directory = assert(debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])"))
local bindings = assert(loadfile(directory .. "EyeColorBindings.lua"))()
local observation = assert(loadfile(directory .. "EyeMaterialObservation.lua"))()
local M, SECTION = {}, "DWEyeColor"
function M.Init(menu, helpers)
    local applied, published = "", nil
    -- Glow strength the next apply uses (0 = plain colour). Set by the desktop before
    -- the colour, or changed while a colour is active to re-apply with the new glow.
    local glow = 0
    local dependencies = { get_player = helpers.GetPlayer, parameters = observation.PARAMETERS }
    dependencies.observe = function()
        return observation.run({ game_thread = IsInGameThread(), intent = "eye-variant-observe",
            identity = { build_id = "25232147", executable_sha256 = "CB9B7D7BD88A6754C0A9C08318AA64D5013DDFD92D5BADCAE84E1B4EA980DCFC" },
            get_player = helpers.GetPlayer, static_find_object = StaticFindObject })
    end
    local function sync(message)
        local active = bindings.IsActive()
        local signature = applied .. ":" .. tostring(active) .. ":" .. message
        if published == signature then return end
        menu.Set(SECTION, "color", applied)
        menu.Set(SECTION, "owned", active)
        menu.SetLabel(SECTION, "status", message)
        published = signature
    end
    local function restore()
        local result = bindings.run(dependencies, "restore")
        assert(result.ok and result.restored, result.reason or "Original eyes could not be restored.")
        applied = ""
        sync("Original game eyes restored.")
    end
    local function guarded(callback)
        ExecuteInGameThread(function()
            local ok, failure = pcall(callback)
            if ok then return end
            local message = tostring(failure):gsub("^.-:%d+: ", "")
            sync("Eye color could not be applied: " .. message)
            error(message)
        end)
    end
    local function apply(value)
        menu.Set(SECTION, "color", applied)
        guarded(function()
            assert(type(value) == "string" and value:match("^#%x%x%x%x%x%x$"), "Choose a valid six-digit eye color.")
            do
                local result = bindings.run(dependencies, "load")
                assert(result.ok and result.loaded, result.reason or "The game's eye materials could not be loaded.")
            end
            local result = bindings.run(dependencies, "apply", value:sub(2), glow)
            if not result.ok then
                if result.restored then applied = "" end
                error((result.reason or "Eye color readback failed.") .. (result.restore_error and "; original-eye restoration is incomplete. Restart the game." or ""))
            end
            applied = value:lower()
            local readback = result.readbacks and result.readbacks[1]
            local detail = readback and readback.emissive and string.format(", emissive %.0f from %.0f", readback.emissive, readback.source_emissive) or ""
            sync(string.format("Applied in game: %s (vampire-style eyes, brightness x%.1f, glow %.1f%s).", applied:upper(), result.brightness or 1, glow, detail))
        end)
    end
    -- Parent switch: the human eye material (whole iris tint + emissive) versus the
    -- vampire-night eyeshine. Changing it with a colour active restores, switches and
    -- re-applies, so the eyes never carry an instance from the previous parent.
    local function setHumanParent(value)
        assert(type(value) == "boolean", "Eye parent switch expects on or off.")
        local mode = value and "human" or "night"
        if bindings.ParentMode() == mode then return end
        menu.Set(SECTION, "human", value)
        guarded(function()
            local reapply = applied
            if bindings.IsActive() then restore() end
            bindings.SetParentMode(mode)
            if reapply ~= "" then apply(reapply) end
        end)
    end
    -- Live tuning: "Name=1.5; Other=#ff4d28*3" (hex colours are linearised, "*k" scales).
    local function parseTuning(text)
        local entries = {}
        for pair in tostring(text):gmatch("[^;]+") do
            local name, raw = pair:match("^%s*([%w_%s]-)%s*=%s*(.-)%s*$")
            assert(name and raw and name ~= "" and raw ~= "", "Tuning entries look like Name=value; Name=#rrggbb*2.")
            local hex, scale = raw:match("^#(%x%x%x%x%x%x)%*?([%d%.]*)$")
            if hex then
                local factor = tonumber(scale) or 1
                local function linear(pair2)
                    local channel = tonumber(pair2, 16) / 255
                    return (channel <= .04045 and channel / 12.92 or ((channel + .055) / 1.055) ^ 2.4) * factor
                end
                entries[#entries + 1] = { name = name, value = { R = linear(hex:sub(1, 2)), G = linear(hex:sub(3, 4)), B = linear(hex:sub(5, 6)), A = 1 } }
            else
                local number = tonumber(raw)
                assert(number ~= nil, "Tuning value must be a number or #rrggbb: " .. raw)
                entries[#entries + 1] = { name = name, value = number }
            end
        end
        return entries
    end
    local function tune(text)
        if tostring(text):match("^%s*$") then return end
        local entries = parseTuning(text)
        guarded(function()
            local result = bindings.run(dependencies, "tune", entries)
            assert(result.ok, result.reason or "Eye parameter tuning failed.")
            menu.SetLabel(SECTION, "tuning", "Tuned on private eyes: " .. table.concat(result.readbacks, ", "))
        end)
    end
    local function setGlow(value)
        assert(type(value) == "number" and value == value and value >= 0 and value <= 3, "Eye glow strength must be between 0 and 3.")
        glow = value
        menu.Set(SECTION, "glow", glow)
        if applied ~= "" then apply(applied) end
    end
    -- Read-only re-verification. The native path was reviewed on one executable; the
    -- desktop layer now disables this section on any other build until the material
    -- chain has been observed again and found to match. This publishes what the
    -- observation actually saw on the installed build - head asset, eye slot topology,
    -- and which reviewed parameters each eye material exposes - so that re-acceptance
    -- rests on evidence from this build rather than on the previous one's. Nothing here
    -- writes; the observation itself stamps mutation_authorized=false on its result.
    local function cyberfox1337x_summarizeEye(inspected)
        -- Which of the reviewed parameters this eye material actually exposes on the
        -- installed build, and which it does not. Only reviewed names are ever recorded
        -- by the observation, so "present" and "missing" together cover the whole set.
        local present = { scalar = {}, vector = {}, switch = {} }
        for _, entry in pairs(inspected.effective_parameters or {}) do
            local kind = observation.PARAMETERS.scalar[entry.name] and "scalar" or "vector"
            present[kind][entry.name] = true
        end
        for _, entry in pairs(inspected.effective_static_switches or {}) do present.switch[entry.name] = true end
        local missing = {}
        for kind, names in pairs(observation.PARAMETERS) do
            for name in pairs(names) do if not present[kind][name] then missing[#missing + 1] = kind .. ":" .. name end end
        end
        table.sort(missing)
        local function count(set) local n = 0; for _ in pairs(set) do n = n + 1 end; return n end
        local leaf = inspected.material and tostring(inspected.material.name):gsub("^MaterialInstanceConstant ", "") or "?"
        local base = inspected.base_material and tostring(inspected.base_material.name or inspected.base_material):gsub("^Material ", "") or "?"
        return string.format("%s <- %s; layers=%d; reviewed params present scalar=%d vector=%d switch=%d; missing=[%s]; Emissivnes=%s",
            leaf, base, #(inspected.layers or {}), count(present.scalar), count(present.vector), count(present.switch),
            table.concat(missing, ","), present.scalar.Emissivnes and "present" or "MISSING")
    end
    local function cyberfox1337x_observeEyeMaterial()
        ExecuteInGameThread(function()
            local report = dependencies.observe()
            if not report.ok then
                menu.SetLabel(SECTION, "observation", "Observation refused: " .. tostring(report.reason))
                return
            end
            local parts = { "OBSERVED on installed build; read-only, mutation_authorized=false." }
            parts[#parts + 1] = "head=" .. tostring(report.context.asset.name):gsub("^SkeletalMesh ", "")
            parts[#parts + 1] = "form=" .. tostring(report.context.form)
            for _, eye in ipairs(report.current_eyes or {}) do
                if eye.ok and eye.value then
                    parts[#parts + 1] = string.format("slot%d: %s", eye.slot, cyberfox1337x_summarizeEye(eye.value))
                else
                    parts[#parts + 1] = string.format("slot%d: UNREADABLE (%s)", eye.slot, tostring(eye.reason))
                end
            end
            local variants, readable = 0, 0
            for _, v in ipairs(report.loaded_variants or {}) do variants = variants + 1; if v.ok then readable = readable + 1 end end
            parts[#parts + 1] = string.format("variants=%d/%d readable; budget samples=%d getters=%d",
                readable, variants, report.budget.samples, report.budget.getters)
            menu.SetLabel(SECTION, "observation", table.concat(parts, " || "))
        end)
    end
    function M.RefreshSession()
        if not bindings.IsActive() then return end
        local ok, changed = pcall(bindings.ObserveTransition, dependencies)
        if ok and not changed then return end
        applied = ""
        sync(ok and "Form changed. Select a color again to apply it to the new form."
            or "Eye color needs attention: " .. tostring(changed):gsub("^.-:%d+: ", ""))
    end
    function M.BeforeFormChange()
        if bindings.IsActive() then restore() end
    end
    function M.ResetSession()
        bindings.ResetSession(dependencies)
        applied = ""
        sync("Select a color to apply vampire-style eyes in game.")
    end
    menu.Register({ id = SECTION, title = "Eye color", tab = "Visuals", items = {
        { id = "color", type = "input", label = "Eye color", default = "", onChange = apply },
        { id = "glow", type = "number", label = "Eye glow strength", default = 0, min = 0, max = 3, step = .1, onChange = setGlow },
        { id = "human", type = "checkbox", label = "Tint the whole human iris (instead of vampire eyeshine)", default = false, onChange = setHumanParent },
        { id = "tune", type = "input", label = "Tune eye parameters (Name=value; ...)", default = "", onChange = tune },
        { id = "tuning", type = "label", label = "Reviewed names only; written to the private eye instances and read back." },
        { id = "restore", type = "button", label = "Restore original game eyes", onClick = function() guarded(restore) end },
        { id = "owned", type = "checkbox", label = "Eye color override active", default = false,
          onChange = function(value) assert(value == false, "Use an eye preset or the color wheel."); guarded(restore) end },
        { id = "status", type = "label", label = "Select a color to apply vampire-style eyes in game." },
        { id = "observe", type = "button", label = "Observe eye material (read-only)", onClick = cyberfox1337x_observeEyeMaterial },
        { id = "observation", type = "label",
          label = "Reads the player's eye material chain on the installed build without changing anything. Used to re-verify this feature after a game update." },
    } })
end
return M
