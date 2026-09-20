local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("court_alert_control")

-- Set Infamy (the court alert value) to an exact number of points.
--
-- WHY THIS USES DropAlertLevelByInt AND NOT SetAlertLevel
--
-- SetAlertLevel is the milestone setter. Writing it live jumps the Infamy Level
-- without running the pipeline that proclaims the matching Edict, so Brencis' Edict
-- tutorial opens with nothing to complete against, cannot be dismissed, and
-- soft-locks the game until restart. Scripts/Source/InfamyControl.lua already
-- carried that warning: "Never call milestone SetAlertLevel."
--
-- DropAlertLevelByInt negates its signed input and routes through
-- ChangeAlertLevelByInt (raw current + delta) into the clamped raw setter, which is
-- the path the game itself uses. A negative drop therefore adds points. That is the
-- route the shipped Infamy panel uses, so the Edict is proclaimed normally.
--
-- This panel adds exact point targeting over the shipped panel's fixed +/-100 steps,
-- reports both points and level, and can restore the session's original value.
--
-- Every figure is read from the game: the cap from CourtSettings.MaxAlertLevel and
-- the points-per-level step from GetSingleAlertThresholdBarValue. Nothing is assumed.

local M = {}

local COURT_SUBSYSTEM_CLASS = "/Script/DogwoodQuest.CourtSubsystem"
local COURT_SETTINGS_PATH = "/Script/DogwoodQuest.Default__CourtSettings"

-- The configuration this control was validated against. A different configuration
-- means its compatibility is unproven, so it refuses rather than writing against
-- assumptions.
local VALIDATED_CAP = 900
local VALIDATED_STEP = 100

local function valid(object) return object ~= nil and object:IsValid() end
local function integer(value) return type(value) == "number" and value == value and value % 1 == 0 end

function M.Init(menu, helpers)
    local id, baseline, unverified = "DWCourtAlert", nil, false

    local function resolve()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a save before reading Infamy.")
        local combat = player.CombatComponent
        assert(valid(combat) and combat:IsAlive(), "Player must be alive.")
        local court = FindFirstOf("CourtSubsystem")
        assert(valid(court) and not court:GetFullName():find("Default__", 1, true),
            "Court subsystem unavailable in this session.")
        assert(court:IsA(COURT_SUBSYSTEM_CLASS), "Resolved object is not the court subsystem.")
        local settings = StaticFindObject(COURT_SETTINGS_PATH)
        assert(valid(settings), "Court settings unavailable.")
        return { player = player:GetAddress(), court = court, address = court:GetAddress(), settings = settings }
    end

    local function same(left, right)
        return left.player == right.player and left.address == right.address
    end

    -- Read the live configuration rather than trusting the constants above; the
    -- constants only decide whether this control considers itself compatible.
    local function readConfiguration(record)
        local cap = tonumber(record.settings.MaxAlertLevel)
        local step = tonumber(record.court:GetSingleAlertThresholdBarValue())
        assert(integer(cap) and cap > 0, "Infamy cap is unavailable.")
        assert(integer(step) and step > 0, "Infamy points-per-level step is unavailable.")
        assert(cap == VALIDATED_CAP and step == VALIDATED_STEP,
            "Infamy configuration changed; this control needs a compatibility update before it may write.")
        return cap, step
    end

    local function readPoints(record)
        local points = tonumber(record.court:GetAlertLevel())
        assert(integer(points) and points >= 0, "Infamy did not read back as a whole number.")
        return points
    end

    local function describe(points, step)
        if points % step == 0 then
            return string.format("%d points (level %d)", points, points / step)
        end
        return string.format("%d points (part way through level %d)", points, math.floor(points / step))
    end

    local function read()
        local record = resolve()
        record.cap, record.step = readConfiguration(record)
        record.points = readPoints(record)
        assert(record.points <= record.cap, "Infamy is above the reported cap.")
        assert(same(record, resolve()), "Player changed while reading Infamy.")
        return record
    end

    local function sync(record, message)
        menu.Set(id, "owned", baseline ~= nil and record ~= nil and record.points ~= baseline)
        menu.SetLabel(id, "status", message)
    end

    local function refresh(silent)
        if unverified then
            sync(nil, "STOP: a previous Infamy change could not be verified. Reload your backup save and restart before using this panel.")
            return
        end
        if not silent then sync(nil, "Reading Infamy...") end
        local ok, record = pcall(read)
        if not ok then if not silent then sync(nil, "Unavailable: " .. tostring(record)) end; error(record, 0) end
        if baseline == nil then baseline = record.points end
        sync(record, string.format("Infamy: %s. Range 0-%d, %d points per level. Original this session: %s.",
            describe(record.points, record.step), record.cap, record.step, describe(baseline, record.step)))
    end

    -- Move Infamy to an exact point total through the game's own change pipeline.
    local function applyPoints(targetPoints, successMessage)
        assert(not unverified,
            "A previous Infamy change could not be verified. Reload your backup save and restart before writing again.")
        assert(integer(targetPoints) and targetPoints >= 0, "Choose a whole number of Infamy points.")
        local record = read()
        assert(targetPoints <= record.cap,
            string.format("Infamy cannot exceed the game's cap of %d points.", record.cap))
        -- The shipped Infamy panel blocks on the same condition.
        local combatSystem = FindFirstOf("CombatSubsystem")
        if valid(combatSystem) and not combatSystem:GetFullName():find("Default__", 1, true) then
            assert(not combatSystem:GetIsInCombat(), "Leave combat before changing Infamy.")
        end
        local before = record.points
        if before == targetPoints then
            sync(record, string.format("Infamy is already %s; nothing changed.", describe(before, record.step)))
            return
        end
        print(string.format("[DawnwalkerImportedMenu] Infamy REQUEST before=%d target=%d", before, targetPoints))
        -- Drop negates its input, so a negative drop adds points. This is the same
        -- call the shipped Infamy panel makes; never SetAlertLevel.
        local writeOk, writeError = pcall(function()
            record.court:DropAlertLevelByInt(before - targetPoints)
        end)
        if not writeOk then
            -- The request was issued and the outcome is unknown, so latch the panel.
            unverified = true
            sync(record, "STOP: the Infamy change failed while running. Reload your backup save and restart. " .. tostring(writeError))
            error(writeError)
        end
        local after = readPoints(record)
        print(string.format("[DawnwalkerImportedMenu] Infamy RESULT before=%d target=%d actual=%d", before, targetPoints, after))
        if after ~= targetPoints then
            unverified = true
            sync(record, string.format("STOP: Infamy reads %d after requesting %d. Do not retry or save; reload your backup.", after, targetPoints))
            error("Infamy readback did not match the requested points")
        end
        assert(same(record, resolve()), "Player changed while writing Infamy.")
        record.points = after
        sync(record, string.format(successMessage, describe(after, record.step)))
    end

    local function apply()
        applyPoints(menu.Get(id, "points"), "Verified: Infamy is now %s. Check the Court screen for the resulting Edict.")
    end

    local function restore()
        assert(baseline ~= nil, "Read Infamy first; no original value has been recorded.")
        applyPoints(baseline, "Restored the original Infamy of %s.")
    end

    function M.ResetSession()
        baseline = nil
        -- The unverified latch deliberately survives a session change: an unproven
        -- write stays blocked until the game is restarted.
    end

    -- Read once the session is up so the panel is live before its first click; the runner
    -- retries a failed read on later ticks, and the Read button stays for a manual re-read.
    function M.SessionReady() refresh(true) end

    menu.Register({ id = id, title = "Infamy (exact)", tab = "☆ World", items = {
        { type = "label", id = "status", label = "Read Infamy to record this session's original value." },
        { type = "number", id = "points", label = "Infamy points", value = 0, min = 0, max = VALIDATED_CAP, integer = true },
        { type = "button", id = "refresh", label = "Read Infamy", onClick = refresh },
        { type = "button", id = "apply", label = "Set exact Infamy", variant = "warning", confirm = {
            title = "Set Infamy to an exact value?",
            message = "Moves Infamy through the game's own change pipeline, so crossing a level proclaims the matching Edict exactly as normal play would. That can trigger world and quest events. Lowering it afterwards restores the number only, not the events. Keep a backup save.",
            confirmLabel = "Set Infamy", cancelLabel = "Cancel" }, onClick = apply },
        { type = "button", id = "restore", label = "Restore original Infamy", onClick = restore },
        { type = "checkbox", id = "owned", label = "Infamy differs from this session's original", value = false },
        { type = "label", label = "Sets any exact point total; the Infamy panel above moves in fixed 100-point steps. Both use the game's own change pipeline." },
    } })

    return M
end

return M
