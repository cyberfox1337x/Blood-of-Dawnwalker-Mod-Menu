local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("super_damage_control")

-- Menu section for an owned multiplier effect (SuperDamageEffectPilot.lua). All state lives
-- in the pilot; this module only queues its calls on the game thread and mirrors the pilot's
-- own view of ownership back to the switch, the same rule the Zero Weight switch follows: a
-- refused enable never shows ON, a refused disable never shows OFF.
--
-- The default spec is Super Damage / One-Hit Kills. `spec` may describe another multiplier
-- served by the same pilot with another target list; the parry-window control does that.

local M = {}

M.SUPER_DAMAGE = {
    id = "DWSuperDamage", title = "Super damage", tab = "♡ Player", name = "super damage",
    switch = "Super damage / one-hit kills", default = 100, min = 2, max = 1000,
    idle = "Off. Multiplies your sword, claw and spell damage through a private effect on your own ability system.",
    note = "Adds (multiplier - 1) to the melee, claws and magic damage multipliers with three private GameplayEffects owned by your ability system, applied and removed by the game's own GAS calls. x100 one-shots ordinary enemies; x1000 is the ceiling. Fists are not covered: the game ships no descriptor for the unarmed multiplier. Turning it off removes the exact effects and verifies every multiplier came back.",
}

M.PARRY_WINDOW = {
    id = "DWParryWindow", title = "Extended parry window", tab = "♡ Player", name = "extended parry window",
    switch = "Extended parry window", default = 2, min = 2, max = 5,
    idle = "Off. Widens the parry timing window through a private effect on your own ability system.",
    note = "Adds (multiplier - 1) to the ParryWindowMultiplier attribute with one private GameplayEffect owned by your ability system, applied and removed by the game's own GAS calls, so every parry check reads a wider window. x2 doubles the timing window; x5 is the ceiling. Turning it off removes the exact effect and verifies the multiplier came back.",
}

function M.Init(menu, helpers, pilot, spec)
    spec = spec or M.SUPER_DAMAGE
    assert(type(pilot) == "table" and type(pilot.set) == "function", spec.name .. " pilot unavailable")
    local id = spec.id
    local multiplier = spec.default

    local function publish(message)
        menu.SetLabel(id, "status", message)
    end

    local function apply(value)
        -- Inspect before an enable, never before a disable: inspection refuses a session the
        -- pilot cannot prove, but turning the effect off must be attempted regardless.
        if value then pilot.inspect() end
        return pilot.set(value, multiplier)
    end

    local function queue(value)
        if EngineTickAvailable ~= true then
            menu.Set(id, "enabled", false)
            publish("The game is not running; load a save before changing " .. spec.name .. ".")
            return
        end
        publish(value and string.format("Enabling %s x%d...", spec.name, multiplier) or ("Disabling " .. spec.name .. "..."))
        local queued, failure = pcall(function()
            ExecuteInGameThread(function()
                local ran, reason = pcall(apply, value)
                menu.Set(id, "enabled", pilot.owned())
                if ran then publish(tostring(reason)) else publish(spec.name:sub(1, 1):upper() .. spec.name:sub(2) .. " was refused: " .. tostring(reason)) end
            end)
        end)
        if not queued then publish("The " .. spec.name .. " control could not be queued: " .. tostring(failure)) end
    end

    local function setMultiplier(value)
        assert(type(value) == "number" and value % 1 == 0 and value >= spec.min and value <= spec.max,
            string.format("Multiplier must be a whole number from %d to %d", spec.min, spec.max))
        multiplier = value
        -- A live effect follows the new figure; otherwise it simply waits for the switch.
        if pilot.owned() then queue(true) else publish(string.format("Multiplier set to x%d; turn the switch on to apply it.", value)) end
    end

    menu.Register({ id = id, title = spec.title, tab = spec.tab, items = {
        { type = "label", id = "status", label = spec.idle },
        { type = "checkbox", id = "enabled", label = spec.switch, default = false,
            onChange = function(value) queue(value) end },
        { type = "number", id = "multiplier", label = "Multiplier", default = spec.default, min = spec.min, max = spec.max, step = 1, integer = true,
            onChange = function(value) setMultiplier(value) end },
        { type = "label", label = spec.note },
    } })

    -- A session change (save load, death, pawn swap) took the old ability system and its
    -- effects with it, so the switch falls back to OFF and nothing is restored.
    local module = {}
    function module.ResetSession()
        local ok, failure = pcall(pilot.forget)
        if not ok then print("[DawnwalkerImportedMenu] " .. spec.name .. " session reset failed: " .. tostring(failure)) end
        menu.Set(id, "enabled", false)
        publish(spec.idle)
    end

    return module
end

return M
