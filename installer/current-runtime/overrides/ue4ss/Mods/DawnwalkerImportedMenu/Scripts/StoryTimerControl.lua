local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("dawnwalker_story_timer_control")
-- Adapter-owned module, loaded by main.lua under the same bounded environment as the
-- imported source. It is deliberately NOT in Source/ and NOT in the imported loader
-- allowlist: the supplied v3.2 package stays byte-identical to its author's release.
--
-- Native targets and their provenance: qa/story-timer/NATIVE-TARGETS.md
--   UTimeSystemImpl (UGameInstanceSubsystem) -> GetCurrentDay(), GetMainGoalDay()
--   UQuestConditionInteractionType -> TimeCost (ETimeCostType), InteractionTimeProgressionType
--
-- Scope note: only the trait-time-cost half is implemented. Extending the story day count
-- has no established write path, so no control is offered for it; the day figures here are
-- read-only. Do not add a day-setting control until a live probe resolves the target.
local M = {}

local TIME_COST_NONE = 0
local PROGRESSION_NONE = 0
local CONDITION_CLASS = "QuestConditionInteractionType"

function M.Init(menu, helpers)
    local id = "DWStoryTimer"
    local enabled, owned, failed = false, false, false
    local records = {}
    local generation = 0

    local function valid(object) return object ~= nil and object:IsValid() end
    local function concrete(object)
        return valid(object) and not object:GetFullName():find("Default__", 1, true)
    end
    local function status(text) menu.SetLabel(id, "status", text) end
    local function detail(text) menu.SetLabel(id, "detail", text) end

    -- UE4SS returns uint8 enum properties as numbers, but stay tolerant of a wrapper.
    local function scalar(value)
        if type(value) == "number" then return value end
        local ok, converted = pcall(tonumber, value)
        if ok and type(converted) == "number" then return converted end
        return nil
    end

    local function timeSystem()
        local system = FindFirstOf("TimeSystemImpl")
        return concrete(system) and system or nil
    end

    local function readDays()
        local system = timeSystem()
        assert(system, "Load a save first; the time system is not available")
        local current = scalar(system:GetCurrentDay())
        local goal = scalar(system:GetMainGoalDay())
        assert(current and goal, "The time system did not return readable day values")
        return current, goal
    end

    local function refresh()
        local ok, current, goal = pcall(readDays)
        if not ok then status("Story day unavailable: " .. tostring(current)); return end
        if goal > 0 then
            status(string.format("Day %d of %d. %d day(s) remain before the main goal.",
                current, goal, math.max(0, goal - current)))
        else
            status(string.format("Day %d. No main-goal deadline is currently set.", current))
        end
    end

    -- The story day is a plain readback with no mutation behind it, so reading it as the
    -- session comes up is the same work the button does. Unlike refresh(), a failure
    -- here publishes nothing - the standing "Load a save, then refresh" label is still
    -- correct - and propagates so the runtime retries on a later tick.
    function M.SessionReady()
        local ok, current, goal = pcall(readDays)
        if not ok then error(current, 0) end
        if goal > 0 then
            status(string.format("Day %d of %d. %d day(s) remain before the main goal.",
                current, goal, math.max(0, goal - current)))
        else
            status(string.format("Day %d. No main-goal deadline is currently set.", current))
        end
    end

    -- Restores only entries this module still owns, and only where the value is still the
    -- one it wrote. A value the game or another mod changed in the meantime is left alone.
    local function restore()
        local restored, skipped, unresolved = 0, 0, {}
        for _, record in ipairs(records) do
            local ok = pcall(function()
                if not valid(record.object) then skipped = skipped + 1; return end
                local changedAway = false
                if scalar(record.object.TimeCost) == TIME_COST_NONE then
                    record.object.TimeCost = record.cost
                    assert(scalar(record.object.TimeCost) == record.cost, "TimeCost restore readback failed")
                else changedAway = true end
                if scalar(record.object.InteractionTimeProgressionType) == PROGRESSION_NONE then
                    record.object.InteractionTimeProgressionType = record.progression
                    assert(scalar(record.object.InteractionTimeProgressionType) == record.progression,
                        "InteractionTimeProgressionType restore readback failed")
                else changedAway = true end
                if changedAway then skipped = skipped + 1 else restored = restored + 1 end
            end)
            if not ok then unresolved[#unresolved + 1] = record end
        end
        records = unresolved
        owned = #records > 0
        assert(not owned, string.format("%d interaction condition(s) could not be restored and verified", #records))
        return restored, skipped
    end

    local function apply()
        local conditions = FindAllOf(CONDITION_CLASS)
        assert(type(conditions) == "table" and #conditions > 0,
            "No quest interaction conditions are loaded; load a save and try again")
        local cleared, failedWrites = 0, 0
        for _, condition in ipairs(conditions) do
            if concrete(condition) then
                local ok = pcall(function()
                    local cost = scalar(condition.TimeCost)
                    local progression = scalar(condition.InteractionTimeProgressionType)
                    assert(cost ~= nil and progression ~= nil, "Unreadable interaction time cost")
                    if cost == TIME_COST_NONE and progression == PROGRESSION_NONE then return end
                    records[#records + 1] = { object = condition, cost = cost, progression = progression }
                    owned = true
                    condition.TimeCost = TIME_COST_NONE
                    condition.InteractionTimeProgressionType = PROGRESSION_NONE
                    assert(scalar(condition.TimeCost) == TIME_COST_NONE
                        and scalar(condition.InteractionTimeProgressionType) == PROGRESSION_NONE,
                        "Time cost write did not stick")
                    cleared = cleared + 1
                end)
                if not ok then failedWrites = failedWrites + 1 end
            end
        end
        -- Fail closed: a partial sweep is put back before it can reach a save.
        assert(failedWrites == 0, string.format(
            "%d interaction condition(s) refused the write", failedWrites))
        assert(cleared > 0, "No interaction condition currently carries a time cost")
        return cleared, #conditions
    end

    local function disable(message)
        local restored, skipped = restore()
        enabled = false
        menu.Set(id, "notimecost", false)
        status(message or string.format("OFF: %d restored, %d left as the game changed them.", restored, skipped))
    end

    local function toggle(on)
        generation = generation + 1
        local request = generation
        ExecuteInGameThread(function()
            if request ~= generation then return end
            if not on then
                local ok, err = pcall(disable)
                if not ok then
                    failed = true
                    menu.Set(id, "notimecost", owned)
                    status("STOP: trait time costs could not be restored. Reload your backup save and restart. " .. tostring(err))
                    error(err)
                end
                return
            end
            if enabled then return end
            if failed then
                menu.Set(id, "notimecost", false)
                status("STOP: a prior restore failed. Reload the backup save and restart before retrying.")
                error("A prior restore failed; activation remains blocked until restart")
            end
            menu.Set(id, "notimecost", false)
            menu.Confirm({
                title = "Remove trait time costs?",
                message = "This clears the time each tracked interaction adds to the clock, across every loaded quest condition. "
                    .. "It changes quest data in memory. Keep a manual backup save, leave combat, and switch it OFF before saving or reloading scripts. "
                    .. "Only currently loaded interactions are affected.",
                confirmLabel = "Remove time costs",
                cancelLabel = "Cancel",
                onConfirm = function()
                    assert(request == generation, "Story Timer confirmation belongs to an expired session or request")
                    local ok, cleared, total = pcall(apply)
                    if not ok then
                        local restored, restoreError = pcall(restore)
                        menu.Set(id, "notimecost", owned)
                        if not restored then
                            failed = true
                            enabled = owned
                            status("STOP: apply rollback could not be verified. Restart and reload your backup save. " .. tostring(restoreError))
                            error(tostring(cleared) .. "; rollback failed: " .. tostring(restoreError))
                        end
                        status("Blocked: " .. tostring(cleared))
                        error(cleared)
                    end
                    enabled = true
                    menu.Set(id, "notimecost", true)
                    status(string.format("ON: cleared the time cost on %d of %d loaded interaction conditions.", cleared, total))
                    print(string.format("[DWStoryTimer] cleared=%d scanned=%d owned=%s", cleared, total, tostring(owned)))
                end,
                onCancel = function()
                    menu.Set(id, "notimecost", false)
                    status("Cancelled. No quest data was changed.")
                end,
            })
        end)
    end

    function M.ResetSession()
        generation = generation + 1
        if owned then
            failed = true
            status("STOP: owned time costs remain unresolved. Restart and reload your backup save.")
            error("Cannot discard unresolved Story Timer restoration records")
        end
        -- The player session changed underneath us; recorded objects belong to the old world.
        records = {}
        owned = false
        enabled = false
        if failed then
            status("STOP: a prior restore failed. Reload the backup save and restart before retrying.")
        end
    end

    menu.Register({ id = id, title = "☆ Story Timer", tab = "☆ World", items = {
        { type = "label", id = "status", label = "Load a save, then refresh to read the current story day." },
        { type = "button", id = "refresh", label = "Refresh story day", onClick = refresh },
        { type = "checkbox", id = "notimecost", label = "Remove trait time costs", default = false,
          onChange = function(value) toggle(value == true) end },
        { type = "label", id = "detail", label = "Clears the time each tracked interaction adds, and puts the recorded values back when switched OFF." },
        { type = "label", label = "Affects currently loaded interactions. Switch OFF before saving or loading another save." },
        { type = "label", label = "Extending the story day count is not offered: its write path is not established. The day figures above are read-only." },
    } })
    detail("Clears the time each tracked interaction adds, and puts the recorded values back when switched OFF.")
end

return M
