local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("carry_weight_check_control")

-- The carry-capacity section, runnable from the menu.
--
-- Two things live here and nothing else: the project's read-only capacity check, and the
-- Zero Weight toggle that the read-only check gates.
--
-- Zero Weight does not go through the setter route CARRY-CAPACITY-FEASIBILITY.md
-- prescribes. That route is `CombatBlueprintFunctionLibrary.SetAttributeValue` with an
-- `UPARAM(Ref) FGameplayAttribute&`, which this pinned UE4SS build refuses as an out
-- parameter, and the attempt to vary the argument arrangement to work around it crashed
-- the game on 2026-09-17 inside `RC::LuaType::call_ufunction_from_lua`. The capability is
-- therefore built on the route this payload already runs live for attack speed: a private
-- native GameplayEffect owned by the player's own ASC, applied and removed through the
-- game's own GAS instrumentation, in `CarryCapacityEffectPilot.lua`. Nothing here passes a
-- descriptor as an out parameter, and the setter is never called.
--
-- The pilot owns every precondition, including the feasibility note's first one: it refuses
-- to write unless the read-only probe contract passes on that exact player, world,
-- inventory, ASC, attribute set and descriptor identity. This module therefore inspects
-- before every enable and refuses the OFF path nothing - turning the effect off must always
-- be attempted, even if the session has since changed.

local M = {}

function M.Init(menu, helpers, probe, capacity)
    local id = "DWWeight"
    local canWrite = type(capacity) == "table" and type(capacity.set) == "function"
        and type(capacity.inspect) == "function" and type(capacity.owned) == "function"

    local function publish(message)
        menu.SetLabel(id, "status", message)
    end

    local function run()
        assert(probe ~= nil and type(probe.run) == "function", "The carry-weight check is unavailable.")
        local result = probe.run({
            static_find_object = StaticFindObject,
            get_player = helpers.GetPlayer,
            property_types = PropertyTypes,
        })
        assert(type(result) == "table", "The carry-weight check returned no verdict.")
        if result.ok ~= true then
            publish(string.format("Blocked at %s: %s Nothing was written and the setter was not called.",
                tostring(result.stage), tostring(result.message)))
            return
        end
        local snapshot = result.snapshot
        local signature = result.setter_signature or {}
        publish(string.format(
            "Read-only check passed: %s on %s, base %s, effective %s, load %s of limit %s, over-limit %s, may-exceed %s. Setter parameter metadata: %s. The check itself changes nothing. Zero Weight uses the private-effect route instead, and refuses to write until this check passes on the same session.",
            tostring(result.descriptor.attribute_name), tostring(result.descriptor.attribute_owner),
            tostring(snapshot.attribute_base_value), tostring(snapshot.attribute_current_value),
            tostring(snapshot.current_weight), tostring(snapshot.effective_weight_limit),
            tostring(snapshot.weight_exceeded), tostring(snapshot.can_exceed_weight_limit),
            tostring(signature.metadata_walk)))
    end

    -- The probe reads live native state, so it runs on the game thread rather than on
    -- whichever thread the menu command happened to arrive on.
    local function queue()
        if EngineTickAvailable ~= true then
            publish("The game is not running; load a save and run the check again.")
            return
        end
        publish("Running the read-only carry-weight check...")
        local queued, failure = pcall(function()
            ExecuteInGameThread(function()
                local ran, reason = pcall(run)
                if not ran then publish("The carry-weight check failed: " .. tostring(reason)) end
            end)
        end)
        if not queued then publish("The carry-weight check could not be queued: " .. tostring(failure)) end
    end

    local function setZeroWeight(value)
        assert(type(value) == "boolean", "The Zero Weight control requires a boolean.")
        assert(canWrite, "The Zero Weight capability is unavailable.")
        -- Inspect before an enable, never before a disable: inspection re-resolves the
        -- descriptor and refuses a session the pilot cannot prove, but turning the effect
        -- off has to be attempted whatever the session now looks like.
        if value then capacity.inspect() end
        return capacity.set(value)
    end

    local function queueZeroWeight(value)
        if EngineTickAvailable ~= true then
            menu.Set(id, "zeroWeight", false)
            publish("The game is not running; load a save before changing Zero Weight.")
            return
        end
        publish(value and "Enabling Zero Weight..." or "Disabling Zero Weight...")
        local queued, failure = pcall(function()
            ExecuteInGameThread(function()
                local ran, reason = pcall(function() return setZeroWeight(value) end)
                -- The switch follows the pilot's own view of whether an effect is applied,
                -- on success and on refusal alike. One rule rather than an optimistic
                -- overlay plus a correction: a refused enable never shows ON, a refused
                -- disable never shows OFF, and a pilot holding a recovery still shows ON.
                menu.Set(id, "zeroWeight", capacity.owned())
                if ran then publish(tostring(reason)) else publish("Zero Weight was refused: " .. tostring(reason)) end
            end)
        end)
        if not queued then publish("The Zero Weight control could not be queued: " .. tostring(failure)) end
    end

    -- Run the read-only check once the session is up: Zero Weight refuses until the check
    -- has passed on the same session, so this is what makes the switch live on first click.
    function M.SessionReady() run() end

    -- This section offers the read-only check and, when a capacity pilot is loaded, the
    -- Zero Weight switch it gates. No setter is reachable from either, and with no pilot
    -- loaded there is no control here that can change a capacity value at all.
    local items = {
        { type = "label", id = "status", label = "Run the read-only check to see the live capacity state." },
        { type = "button", id = "probe", label = "Run read-only carry-weight check", onClick = queue },
    }
    if canWrite then
        items[#items + 1] = {
            type = "checkbox", id = "zeroWeight", label = "Zero weight (no carry limit)", default = false,
            onChange = function(value) queueZeroWeight(value) end,
        }
    end
    items[#items + 1] = { type = "label", label = "Reports the live carry-weight attribute, inventory weight and limit, and whether the documented setter route can be reached on this build. The check changes nothing and calls no setter. Zero Weight grants an exactly zero effective limit through a private effect owned by your own ability system, applied and removed by the game's own GAS instrumentation; enabling it requires the read-only check to pass on the same session, and disabling it removes that exact effect and verifies the original limit, load and exceeded flag came back byte for byte. The setter route the feasibility note prescribes is refused by this UE4SS build and is not used." }

    menu.Register({ id = id, title = "Carry weight", tab = "♡ Player", items = items })

    return M
end

return M
