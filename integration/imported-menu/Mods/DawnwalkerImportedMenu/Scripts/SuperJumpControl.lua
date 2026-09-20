local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("super_jump_private_effect_control")
local Pilot = require("SuperJumpEffectPilot")
local M = {}
function M.Init(menu, helpers, borrower, hookDependencies)
    assert(type(borrower) == "function" and type(hookDependencies) == "table"
        and type(hookDependencies.registerHook) == "function" and type(hookDependencies.unregisterHook) == "function",
        "Super Jump requires the validated descriptor borrower and scoped native hooks")
    local id = "DWSuperJump"
    local pilot = Pilot.New({ borrow = borrower, registerHook = hookDependencies.registerHook,
        unregisterHook = hookDependencies.unregisterHook,
        exclusive = function()
            local player = helpers.GetPlayer()
            return player and player:IsValid() and player:IsInWolfForm() == false
        end })
    local ready = false
    local field = { id = "enabled", type = "checkbox", label = "Super Jump (1.5x jump velocity)", default = false, enabled = false }
    local function publish(ok, message)
        local recovery = pilot.owned()
        field.enabled = ready or recovery
        menu.Set(id, "enabled", recovery)
        menu.SetLabel(id, "status", ok and message or (recovery
            and ("Super Jump recovery required: " .. tostring(message)
                .. " Return to human form and turn OFF again. Do not save while restoration is pending.")
            or ("Super Jump unavailable: " .. tostring(message))))
    end
    local function run(callback, message)
        ExecuteInGameThread(function()
            local ok, cause = pcall(callback)
            if not ok then ready = false end
            publish(ok, ok and message or cause)
            assert(ok, cause)
        end)
    end
    field.onChange = function(value)
        run(function()
            assert(type(value) == "boolean", "Super Jump requires an ON/OFF value")
            assert(value == false or ready, "Wait for the automatic Super Jump state check before enabling")
            pilot.set(value)
            if not value then pilot.inspect() end
        end, value and "ON: private jump effect and 1.5x velocity / 2.25x derived height verified. Turn OFF to restore."
            or "OFF: private effect removed and original jump values verified.")
    end
    menu.Register({ id = id, title = "Super Jump", tab = "Player", items = {
        field,
        { id = "status", type = "label", label = "Checking jump state automatically. Turn OFF before changing form. Natural Wolf Boost interaction is untested." },
    } })
    -- Inspect once the session is up so the switch is live before its first click. Runs on
    -- the game thread already (the runner ticks there); a refused inspect leaves the switch
    -- gated and the runner retries on later ticks.
    M.SessionReady = function()
        ready = false
        pilot.inspect()
        ready = true
        publish(true, "Jump state verified. Human-form control is available; natural Wolf Boost interaction has not been tested.")
    end
    M.NeedsSessionReady = function() return not ready and not pilot.owned() end
    M.ResetSession = function()
        ready = false
        local ok, cause = pcall(pilot.reset)
        publish(ok, ok and "OFF: original jump values restored. Waiting for the automatic state check for the current session." or cause)
        assert(ok, cause)
    end
    return pilot
end
return M
