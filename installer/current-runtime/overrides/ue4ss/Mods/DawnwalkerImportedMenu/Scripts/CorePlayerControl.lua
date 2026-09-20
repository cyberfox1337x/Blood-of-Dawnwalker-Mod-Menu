local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("core_player_resource_control")
local M = {}

-- These exact resource methods passed the build 25129649 resource roundtrip.
-- This does not establish enemy-hit immunity or a sprint-specific attribute setter.
local operations = {
    { name = "health", read = function(o) return o:GetHealthPercentage() end,
      set = function(o,v) o:SetHealthPercent(v) end, lock = function(o) o:LockHealth() end,
      unlock = function(o) o:UnlockHealth() end },
    { name = "stamina", read = function(o) return o:GetStaminaPercentage() end,
      set = function(o,v) o:SetStaminaPercent(v) end, lock = function(o) o:LockStamina() end,
      unlock = function(o) o:UnlockStamina() end },
    { name = "blood", read = function(o)
          local maximum = o:GetBloodBarLength()
          assert(type(maximum) == "number" and maximum > 0, "Invalid blood maximum")
          return o:GetBlood() / maximum
      end, set = function(o,v) o:SetBloodPercent(v) end, lock = function(o) o:LockBlood() end,
      unlock = function(o) o:UnlockBlood() end },
}
local function valid(o) return o ~= nil and o:IsValid() end
local function percentage(v)
    assert(type(v) == "number" and v == v and v >= 0 and v <= 1.001, "Invalid resource percentage")
    return v
end

-- modules is a registry the runtime fills in as it loads: modules.source holds the
-- Source/ modules, and modules.formToggle is added after this panel is built. Both
-- are read at click time, never captured at Init, because form loads later.
function M.Init(menu, helpers, modules)
    local id, records, failed = "DWCorePlayer", {}, false
    local bloodAmountRead = false
    local bloodPercentField = { type = "number", id = "bloodPercent", label = "Blood Energy (%)",
        min = 0, max = 100, step = 1, default = 0, enabled = false }
    local function owns(owner)
        for _, record in ipairs(records) do if record.owners[owner] then return true end end
        return false
    end
    local function sync(text)
        menu.Set(id, "god", owns("god"))
        menu.Set(id, "healthEnabled", owns("health"))
        menu.Set(id, "bloodEnabled", owns("blood"))
        menu.Set(id, "sprintEnabled", owns("sprint"))
        menu.Set(id, "bloodRecovery", owns("bloodAmount"))
        bloodPercentField.enabled = bloodAmountRead and not failed and not owns("god") and not owns("blood")
        menu.SetLabel(id, "status", text)
    end
    local function resolve()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a living player first")
        local world, controller, combat = player:GetWorld(), player.Controller, player.CombatComponent
        assert(valid(world) and valid(controller) and valid(combat) and combat:IsAlive(), "Living controlled player required")
        assert(valid(controller.Pawn) and controller.Pawn:GetAddress() == player:GetAddress(), "Player possession changed")
        local bloodOk, blood = pcall(function() return player.BloodBar end)
        if not bloodOk or not valid(blood) then
            bloodOk, blood = pcall(function()
                local state = player.PlayerState
                return valid(state) and state.BloodBar or nil
            end)
        end
        assert(bloodOk, "Player blood component unavailable")
        assert(valid(blood), "Player blood component unavailable")
        return player, world, controller, combat, blood
    end
    local function bindingLive(record)
        for _, binding in ipairs(record.bindings) do
            assert(valid(binding.object) and binding.object:GetAddress() == binding.address,
                "Owned resource identity expired; reload the save before retrying")
        end
    end
    local function hasOtherOwner(record, owner)
        for candidate in pairs(record.owners) do
            if candidate ~= owner then return true end
        end
        return false
    end
    local function restore(owner)
        local unresolved, errors = {}, {}
        for _, record in ipairs(records) do
            if not record.owners[owner] then
                unresolved[#unresolved + 1] = record
            elseif hasOtherOwner(record, owner) then
                -- The remaining owner keeps the original lock and original baseline.
                local ok, err = pcall(function()
                    bindingLive(record)
                    assert(percentage(record.operation.read(record.target)) >= .999, "Remaining resource owner's readback failed")
                    record.owners[owner] = nil
                end)
                if not ok then errors[#errors + 1] = tostring(err) end
                unresolved[#unresolved + 1] = record
            else
            local ok, err = pcall(function()
                bindingLive(record)
                -- A one-shot amount write never acquired a resource lock.
                if not record.oneShot then record.operation.unlock(record.target) end
                -- Rapid refill owns its own timer, not this lock. Preserve its full
                -- stamina while active, without stopping or changing that control.
                local refill = record.operation.name == "stamina" and menu.Get("DWCombatControls", "stamina") == true
                local target = refill and 1 or record.baseline
                record.operation.set(record.target, target)
                assert(math.abs(percentage(record.operation.read(record.target)) - target) <= .0025,
                    "Resource restoration readback failed")
                if record.oneShot then
                    menu.Set(id, "bloodPercent", target * 100)
                    menu.Set(id, "blood", { percent = target, text = tostring(target) })
                end
            end)
            if not ok then unresolved[#unresolved + 1] = record; errors[#errors + 1] = tostring(err) end
            end
        end
        records = unresolved
        assert(not owns(owner), table.concat(errors, "; "))
    end
    local function apply(owner)
        assert(not failed and not owns(owner), "A prior resource failure requires restarting and reloading the save")
        local player, world, controller, combat, blood = resolve()
        -- Capture every baseline before any mutation, including the resource whose
        -- setter/lock might throw after changing native state.
        local planned = {}
        for index, operation in ipairs(operations) do
            if owner == "god" or (owner == "blood" and operation.name == "blood")
                or (owner == "health" and operation.name == "health")
                or (owner == "sprint" and operation.name == "stamina") then
            local target = index == 3 and blood or combat
            local existing
            for _, record in ipairs(records) do
                if record.operation.name == operation.name then existing = record; break end
            end
            if existing then
                bindingLive(existing)
                for bindingIndex, object in ipairs({ player, world, controller }) do
                    assert(existing.bindings[bindingIndex].address == object:GetAddress(), "Resource belongs to another player, world or controller")
                end
                assert(existing.target:GetAddress() == target:GetAddress(), "Resource belongs to another target")
                -- The other owner's native lock is held, but the game can still move the
                -- value underneath it (a scripted drain, blood decay). Reading below full
                -- here used to fail THIS owner's request for drift it did not cause. Restore
                -- the value instead - that is the lock's stated effect and idempotent - then
                -- verify. The native lock is deliberately not re-applied: whether Lock*()
                -- is a flag or a counter is not established, and a counter would be left
                -- held after the single Unlock*() the release path performs.
                if percentage(operation.read(target)) < .999 then operation.set(target, 1) end
                assert(percentage(operation.read(target)) >= .999,
                    "Shared resource could not be restored to full; the existing lock is not holding it")
                planned[#planned + 1] = { shared = existing }
            else
            local bindings = {}
            for _, object in ipairs({player, world, controller, target}) do
                bindings[#bindings + 1] = { object = object, address = object:GetAddress() }
            end
            planned[#planned + 1] = { operation = operation, target = target,
                baseline = percentage(operation.read(target)), bindings = bindings, owners = { [owner] = true } }
            end
            end
        end
        for _, record in ipairs(planned) do
            if record.shared then
                record.shared.owners[owner] = true
            else
            records[#records + 1] = record
            record.operation.set(record.target, 1)
            record.operation.lock(record.target)
            assert(percentage(record.operation.read(record.target)) >= .999, "Resource activation readback failed")
            end
        end
    end
    local function toggle(owner, value)
        assert(type(value) == "boolean", "Resource toggle requires a boolean")
        ExecuteInGameThread(function()
            if value and owns(owner) and not failed then return end
            local ok, err = pcall(value and apply or restore, owner)
            if not ok then
                failed = true
                local restored, restoreError = pcall(restore, owner)
                sync(restored and "Request failed; this control's resource ownership released." or "STOP: resource cleanup remains unresolved. Restart and reload the save.")
                error(tostring(err) .. (restored and "" or "; " .. tostring(restoreError)), 0)
            end
            sync(owns("god") and "ON: health, stamina and blood resource locks active."
                or owns("health") and "Health lock active; God Mode OFF."
                or owns("blood") and "Blood energy lock active; God Mode OFF."
                or owns("sprint") and "Stamina lock active for sprinting and other actions; God Mode OFF."
                or "OFF: owned resources released and restoration verified.")
        end)
    end
    function M.ResetSession()
        if #records > 0 then
            failed = true
            error("Cannot discard unresolved God Mode resource ownership")
        end
        bloodAmountRead = false
        sync(failed and "OFF: prior failure requires restarting and reloading the save." or "God Mode: OFF")
    end
    local function refresh()
        local _, _, _, combat, blood = resolve()
        for index, operation in ipairs(operations) do
            local value = percentage(operation.read(index == 3 and blood or combat))
            menu.Set(id, operation.name, { percent = value, text = tostring(value) })
            if operation.name == "blood" then
                bloodAmountRead = true
                menu.Set(id, "bloodPercent", value * 100)
                bloodPercentField.enabled = not failed and not owns("god") and not owns("blood")
            end
        end
    end
    -- The sidebar's Health / Stamina / Blood meters show "-" until this read has run,
    -- which left player statistics blank on a live session with a save loaded. Read
    -- once when the session comes up; it is the same work the button does. A failure
    -- propagates so the runtime retries a pawn that exists before its components do.
    function M.SessionReady()
        if bloodAmountRead or failed then return end
        refresh()
    end
    bloodPercentField.onChange = function(value)
        assert(type(value) == "number" and value == value and value >= 0 and value <= 100,
            "Blood Energy must be a finite percentage from 0 to 100")
        ExecuteInGameThread(function()
            assert(not failed and not owns("god") and not owns("blood") and not owns("bloodAmount"),
                "Turn God Mode and Infinite Blood Energy OFF before changing the blood amount")
            local player, world, controller, _, blood = resolve()
            local operation = operations[3]
            local baseline = percentage(operation.read(blood))
            local record = { operation = operation, target = blood, baseline = baseline,
                bindings = {}, owners = { bloodAmount = true }, oneShot = true }
            for _, object in ipairs({ player, world, controller, blood }) do
                record.bindings[#record.bindings + 1] = { object = object, address = object:GetAddress() }
            end
            records[#records + 1] = record
            local ok, failure = pcall(function()
                operation.set(blood, value / 100)
                bindingLive(record)
                local actual = percentage(operation.read(blood))
                assert(math.abs(actual - value / 100) <= .0025, "Blood amount readback failed")
                menu.Set(id, "bloodPercent", actual * 100)
                menu.Set(id, "blood", { percent = actual, text = tostring(actual) })
            end)
            if not ok then
                failed = true
                local restored, restoreError = pcall(restore, "bloodAmount")
                if restored then menu.Set(id, "bloodPercent", baseline * 100) end
                sync(restored and "Blood amount failed; original amount restored. Restart before retrying."
                    or "Blood restoration pending. Use Restore Blood Energy; do not save.")
                error(tostring(failure) .. (restored and "" or "; " .. tostring(restoreError)))
            end
            records[#records] = nil
            bloodAmountRead = true
            sync("Blood Energy amount applied and read back.")
        end)
    end
    -- Relocated from the Stamina panel. The logic stays in CombatControls; this only
    -- forwards the toggle and reports when that module is unavailable.
    -- Look a relocated control's owning module up lazily and report if it is absent,
    -- rather than leaving a checkbox that silently does nothing.
    local function delegate(itemId, owner, method, value, description)
        if type(owner) ~= "table" or type(owner[method]) ~= "function" then
            menu.Set(id, itemId, false)
            sync(description .. " is unavailable: its control module did not load.")
            return
        end
        local ok, failure = pcall(owner[method], value == true)
        if not ok then
            menu.Set(id, itemId, false)
            sync(description .. " failed: " .. tostring(failure))
        end
    end

    local function setStaminaRefill(value)
        local combat = modules and modules.source and modules.source.CombatControls
        delegate("staminaRefill", combat, "SetStaminaRefill", value, "Rapid stamina refill")
    end

    local function setFormOverride(value)
        delegate("formOverride", modules and modules.formToggle, "SetFormOverride", value,
            "Vampire form override")
    end

    menu.Register({ id = id, title = "♡ Player controls", tab = "♡ Player", items = {
        { type = "checkbox", id = "god", label = "God Mode", default = false, onChange = function(value) toggle("god", value) end },
        { type = "checkbox", id = "healthEnabled", label = "Infinite Health", default = false, onChange = function(value) toggle("health", value) end },
        { type = "checkbox", id = "bloodEnabled", label = "Infinite Blood Energy", default = false, onChange = function(value) toggle("blood", value) end },
        bloodPercentField,
        { type = "checkbox", id = "bloodRecovery", label = "Blood amount recovery pending", default = false,
            onChange = function(value)
                assert(value == false, "Blood recovery can only restore a pending amount")
                toggle("bloodAmount", false)
            end },
        -- Uses the verified resource lock, not the unverified sprint attribute setter.
        { type = "checkbox", id = "sprintEnabled", label = "Sprint No Drain (stamina lock)", default = false, onChange = function(value) toggle("sprint", value) end },
        { type = "checkbox", id = "staminaRefill", label = "Rapid stamina refill", default = false, onChange = function(value) setStaminaRefill(value) end },
        { type = "label", id = "staminaStatus", label = "Stamina refill: OFF" },
        { type = "checkbox", id = "formOverride", label = "Vampire form override", default = false, onChange = function(value) setFormOverride(value) end },
        { type = "label", id = "formStatus", label = "OFF restores automatic day/night form. Use after unlocking both forms." },
        { type = "label", id = "status", label = "God Mode: OFF" },
        { type = "button", id = "refresh", label = "Read player resources", onClick = refresh },
        { type = "meter", id = "health", label = "Health", default = { percent = 0, text = "Unread" } },
        { type = "meter", id = "stamina", label = "Stamina", default = { percent = 0, text = "Unread" } },
        { type = "meter", id = "blood", label = "Blood", default = { percent = 0, text = "Unread" } },
    } })
end
return M
