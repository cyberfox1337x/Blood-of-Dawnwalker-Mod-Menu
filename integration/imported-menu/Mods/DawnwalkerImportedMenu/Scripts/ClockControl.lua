local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("clock_control")

-- Set the in-game clock to an exact time of day.
--
-- SetTime returns nothing, so the result is proved by GetCurrentDayTimeAsFloat
-- matching the requested hour. The session's original time is recorded so the clock
-- can be put back, but putting the clock back is NOT an undo: anything the world or
-- a timed quest did while the clock was moved has already happened.
--
-- The guards mirror the shipped Time Segments control: no combat, and no writing
-- while a day/night phase transition is queued or running.

local M = {}

local TIME_SYSTEM_CLASS = "/Script/DogwoodSystem.TimeSystemImpl"
local SECONDS_PER_HOUR = 3600

local function valid(object) return object ~= nil and object:IsValid() end
local function integer(value) return type(value) == "number" and value == value and value % 1 == 0 end
local function finite(value) return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge end

function M.Init(menu, helpers)
    local id, baseline = "DWClock", nil

    local function resolve()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a save before changing the clock.")
        local state = helpers.GetGameStateBase()
        assert(valid(state), "Game state unavailable.")
        local time = state.TimeSystem
        assert(valid(time) and not time:GetFullName():find("Default__", 1, true), "Time system unavailable.")
        assert(time:IsA(TIME_SYSTEM_CLASS), "Resolved object is not the time system.")
        return { player = player:GetAddress(), time = time, address = time:GetAddress() }
    end

    local function same(left, right)
        return left.player == right.player and left.address == right.address
    end

    local function readTime(record)
        local hours = record.time:GetCurrentDayTimeAsFloat()
        assert(finite(hours) and hours >= 0 and hours < 24, "Clock reading is outside the expected hour range.")
        return hours
    end

    local function clockText(hours)
        local wholeHours = math.floor(hours)
        local minutes = math.floor((hours - wholeHours) * 60 + 0.5)
        if minutes == 60 then wholeHours, minutes = (wholeHours + 1) % 24, 0 end
        return string.format("%02d:%02d", wholeHours, minutes)
    end

    local function read()
        local record = resolve()
        record.hours = readTime(record)
        local dayOk, day = pcall(function() return record.time:GetCurrentDay() end)
        record.day = dayOk and day or nil
        assert(same(record, resolve()), "Player changed while reading the clock.")
        return record
    end

    local function sync(record, message)
        menu.Set(id, "owned", baseline ~= nil and record ~= nil and math.abs(record.hours - baseline) > 0.01)
        -- Pre-fill the hour and minute fields from the live clock whenever they are still
        -- blank, so Set time of day works after editing just one of them. Fields the player
        -- has already typed into are left alone.
        if record then
            local wholeHours = math.floor(record.hours)
            local minutes = math.floor((record.hours - wholeHours) * 60 + 0.5)
            if minutes == 60 then wholeHours, minutes = (wholeHours + 1) % 24, 0 end
            if menu.Get(id, "hour") == nil then menu.Set(id, "hour", wholeHours) end
            if menu.Get(id, "minute") == nil then menu.Set(id, "minute", minutes) end
        end
        menu.SetLabel(id, "status", message)
    end

    local function refresh(silent)
        if not silent then sync(nil, "Reading the clock...") end
        local ok, record = pcall(read)
        if not ok then if not silent then sync(nil, "Unavailable: " .. tostring(record)) end; error(record, 0) end
        if baseline == nil then baseline = record.hours end
        sync(record, string.format("Clock: %s%s. Original this session: %s.",
            clockText(record.hours),
            integer(record.day) and (" (day " .. record.day .. ")") or "",
            clockText(baseline)))
    end

    -- Refuse to write while the world is mid-transition or the player is fighting.
    local function assertSafeToWrite(record)
        local combat = FindFirstOf("CombatSubsystem")
        if valid(combat) and not combat:GetFullName():find("Default__", 1, true) then
            assert(not combat:GetIsInCombat(), "Leave combat before changing the clock.")
        end
        local transitioning = record.time:IsPhaseTransitionQueuedOrInProgress()
        assert(transitioning ~= true, "A day/night transition is in progress; wait for it to finish.")
    end

    local SEGMENT_HOURS, SEGMENT_ANCHOR_HOURS = 1.5, 8
    local function applyHours(targetHours, successMessage)
        assert(finite(targetHours) and targetHours >= 0 and targetHours < 24,
            "Choose a time between 00:00 and 23:59.")
        local record = read()
        assertSafeToWrite(record)
        local hour = math.floor(targetHours)
        local remainingSeconds = math.floor((targetHours - hour) * SECONDS_PER_HOUR + 0.5)
        local minute = math.floor(remainingSeconds / 60)
        local second = remainingSeconds % 60
        -- bAbsoluteTime is passed true so the values are read as a wall-clock time
        -- rather than an offset; the readback below is what actually confirms it.
        record.time:SetTime(hour, minute, second, true)
        local after = readTime(record)
        assert(same(record, resolve()), "Player changed while writing the clock.")
        record.hours = after
        if math.abs(after - targetHours) > 0.05 then
            -- The game keeps its clock on the Time Segment grid (1.5 hours, anchored at
            -- 08:00; measured live 2026-09-17: asking for 12:00 landed on 12:30). A readback
            -- on the segment nearest the request is the game honouring it in its own units
            -- and is reported as such; anything else is a refused write.
            local snapped = (SEGMENT_ANCHOR_HOURS + math.floor((targetHours - SEGMENT_ANCHOR_HOURS) / SEGMENT_HOURS + 0.5) * SEGMENT_HOURS) % 24
            if math.abs(after - snapped) > 0.05 then
                sync(record, string.format("The game kept the clock at %s; the change to %s was refused or interpreted differently.",
                    clockText(after), clockText(targetHours)))
                error("Clock readback did not match the requested time")
            end
            sync(record, string.format(successMessage, clockText(after))
                .. string.format(" The game keeps time in 1.5-hour segments, so %s became %s.", clockText(targetHours), clockText(after)))
            return
        end
        sync(record, string.format(successMessage, clockText(after)))
    end

    local function apply()
        local hour = menu.Get(id, "hour")
        local minute = menu.Get(id, "minute")
        assert(integer(hour) and hour >= 0 and hour <= 23, "Choose an hour between 0 and 23.")
        assert(integer(minute) and minute >= 0 and minute <= 59, "Choose a minute between 0 and 59.")
        applyHours(hour + minute / 60, "Verified: the clock is now %s.")
    end

    local function restore()
        assert(baseline ~= nil, "Read the clock first; no original time has been recorded.")
        applyHours(baseline, "Restored the clock to %s.")
    end

    function M.ResetSession()
        baseline = nil
    end

    -- Read once the session is up so the panel is live before its first click; the runner
    -- retries a failed read on later ticks, and the Read button stays for a manual re-read.
    function M.SessionReady() refresh(true) end

    menu.Register({ id = id, title = "Clock", tab = "☆ World", items = {
        { type = "label", id = "status", label = "Read the clock to record this session's original time." },
        { type = "row", items = {
            { type = "number", id = "hour", label = "Hour", value = 12, min = 0, max = 23, integer = true },
            { type = "number", id = "minute", label = "Minute", value = 0, min = 0, max = 59, integer = true },
        } },
        { type = "button", id = "refresh", label = "Read clock", onClick = refresh },
        { type = "button", id = "apply", label = "Set time of day", variant = "warning", confirm = {
            title = "Set the in-game clock?",
            message = "Moves the clock to an exact time. This can cross into day or night, trigger the phase transition, and advance time-sensitive quests and the campaign deadline. Putting the clock back afterwards restores the number only, not anything that happened. Keep a backup save.",
            confirmLabel = "Set time", cancelLabel = "Cancel" }, onClick = apply },
        { type = "button", id = "restore", label = "Restore original time", onClick = restore },
        { type = "checkbox", id = "owned", label = "Clock differs from this session's original", value = false },
        { type = "label", label = "Leave combat first. Restoring the time is not an undo for quests or world events." },
    } })

    return M
end

return M
