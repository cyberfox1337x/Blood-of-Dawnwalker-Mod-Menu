local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("hub_tag_probe")

--[[
Learns the real hub tab GameplayTags from the running game, read only.

Why a probe instead of reading them directly: every hub tab function is keyed by
FGameplayTag, and the two ways to enumerate them - GetAllTabTags(TArray<FGameplayTag>&)
and GetRegisteredHubTabs(TArray<FHubTabRow>&) - marshal a struct array into Lua, which
killed the game with EXCEPTION_ACCESS_VIOLATION in FName::ToString() <-
push_structproperty(). That route stays closed.

The safe route is the one the ItemHandle bridge already proves: let the game hand us a
native struct inside a hook's lifetime and consume it there. The game calls
BP_IsTabLocked and TryShowHUB with a tab's tag while it builds the hub, so opening the
hub once names every tab without a single struct crossing the bridge as a value.

Nothing here mutates the game. Unlocking is a separate, explicit control that only
becomes available once a tag has been observed.
]]

local M = {}

local TAG_LIBRARY = "/Script/GameplayTags.Default__BlueprintGameplayTagLibrary"
local HUB = "/Script/DogwoodUI.HUBManagerSubystem:"

-- Which argument slot holds the tag, taken from the reflected parameter list rather
-- than guessed: a post hook receives (context, [ReturnValue,] ...parameters), so a
-- function that returns a value shifts its parameters along by one.
--
-- The first attempt watched only BP_IsTabLocked and TryShowHUB and saw nothing, so the
-- set is widened and each watcher counts its own calls. That way "no tags" can be told
-- apart from "that function is never called", which is the thing the first attempt
-- could not distinguish.
local WATCHERS = {
    { name = "BP_IsTabLocked", path = HUB .. "BP_IsTabLocked", slot = 2 },
    { name = "TryShowHUB", path = HUB .. "TryShowHUB", slot = 3 },
    { name = "IsTabActive", path = HUB .. "IsTabActive", slot = 2 },
    -- announce: this one is not just a source of names, it is the only call that says
    -- which tab the player actually opened. See noteActivation.
    { name = "NotifyTabActivated", path = HUB .. "NotifyTabActivated", slot = 1, announce = true },
    { name = "RegisterSpawnedTabWidget", path = HUB .. "RegisterSpawnedTabWidget", slot = 1 },
    { name = "LaunchHUB", path = HUB .. "LaunchHUB", slot = 2 },
}

local WATCHER_BY_NAME = {}
for _, watcher in ipairs(WATCHERS) do WATCHER_BY_NAME[watcher.name] = watcher end

local function valid(object)
    return object ~= nil and object.IsValid ~= nil and object:IsValid()
end

function M.Init(menu, helpers, options)
    options = options or {}
    local registerHook = options.registerHook or RegisterHook
    local unregisterHook = options.unregisterHook or UnregisterHook
    local deferToGameThread = options.deferToGameThread or ExecuteInGameThread
    local section = "DWHubTags"
    local log = options.log or function() end

    -- Insertion-ordered so the list reads in the order the game asked about the tabs.
    local seenOrder, seenNames = {}, {}
    -- Watcher name -> the pre/post ids UE4SS handed back. Previously those ids were
    -- discarded, which left all six hooks attached for the rest of the process: every
    -- one of them still crossed into Lua on every call long after its budget was spent
    -- and its callback had nothing left to do.
    local attachedHooks = {}
    -- The game may ask about every tab on every frame the hub is open, so the probe
    -- stops doing work once it has clearly seen the whole set. Without this the hook
    -- would keep making a native call per tab per frame for the rest of the session.
    local INSPECTION_BUDGET = 600
    local inspections, harvesting = 0, true
    -- Per-watcher call counts, so a silent harvest can be diagnosed.
    local calls = {}
    -- The name of the tab the player most recently opened, and a budget for reading it.
    -- Separate from the harvest above because the two answer different questions; see
    -- noteActivation for why the harvest alone cannot report this.
    local ACTIVATION_READ_BUDGET = 200
    local activationReads, lastActivated = 0, nil

    local function tagLibrary()
        local library = StaticFindObject(TAG_LIBRARY)
        return valid(library) and library or nil
    end

    -- Reads only the tag's FName. An FName return crosses the bridge safely; the tag
    -- struct itself is never copied out.
    local function tagName(tag)
        local library = tagLibrary()
        if not library then return nil end
        local ok, name = pcall(function() return library:GetTagName(tag):ToString() end)
        if not ok or type(name) ~= "string" or name == "" then return nil end
        return name
    end

    -- UnregisterHook must never run inside the callback it is unregistering, and every
    -- release below is decided from inside a hook. So a release is queued and drained on
    -- the next game-thread pass, once the callback that asked for it has returned.
    local releaseQueue, releaseQueued, releaseScheduled = {}, {}, false

    local function cyberfox1337x_ReleaseWatcher(name)
        local ids = attachedHooks[name]
        releaseQueued[name] = nil
        if not ids then return end
        attachedHooks[name] = nil
        local watcher = WATCHER_BY_NAME[name]
        local ok, failure = pcall(unregisterHook, watcher.path, ids.pre, ids.post)
        if not ok then log("HUB_TAG hook release failed for " .. name .. ": " .. tostring(failure)) end
    end

    local function cyberfox1337x_DrainHookReleases()
        releaseScheduled = false
        local queued = releaseQueue
        releaseQueue = {}
        for _, name in ipairs(queued) do cyberfox1337x_ReleaseWatcher(name) end
    end

    local function cyberfox1337x_ReleaseWatcherLater(name)
        -- The activation watcher asks for this on every call once its budget is spent,
        -- so without the queued set a drain that cannot be scheduled would grow the
        -- queue for as long as the hub keeps calling.
        if not attachedHooks[name] or releaseQueued[name] then return end
        releaseQueued[name] = true
        releaseQueue[#releaseQueue + 1] = name
        if releaseScheduled then return end
        local ok, failure = pcall(deferToGameThread, cyberfox1337x_DrainHookReleases)
        if ok then releaseScheduled = true
        else
            -- The queue keeps the name, so ResetSession or a later release still detaches
            -- it. Detaching here instead would unregister a hook from inside its own
            -- callback, which is the one thing this indirection exists to prevent.
            log("HUB_TAG deferred hook release unavailable: " .. tostring(failure))
        end
    end

    local function activityReport()
        local parts = {}
        for _, watcher in ipairs(WATCHERS) do
            parts[#parts + 1] = string.format("%s=%d", watcher.name, calls[watcher.name] or 0)
        end
        return table.concat(parts, " ")
    end

    local function publish()
        local options_list = {}
        for _, name in ipairs(seenOrder) do options_list[#options_list + 1] = { label = name, value = name } end
        if #options_list == 0 then options_list = { { label = "Open the hub in game to list its tabs", value = false } } end
        menu.SetOptions(section, "tag", options_list, false)
        menu.SetLabel(section, "status", #seenOrder == 0
            and "No hub tab observed yet. Open the hub in game once; each tab it asks about is listed here."
            or string.format("%d hub tab tag(s) observed%s: %s", #seenOrder,
                harvesting and "" or " (watching stopped; the set looks complete)", table.concat(seenOrder, ", ")))
        menu.SetLabel(section, "activity", "Hub calls seen: " .. activityReport())
        menu.SetLabel(section, "activated", lastActivated
            and ("Last tab opened in the hub: " .. lastActivated)
            or "No tab opened yet. Open the hub in game and select a tab.")
    end

    local function record(tag)
        if not harvesting then return end
        inspections = inspections + 1
        if inspections > INSPECTION_BUDGET then
            harvesting = false
            log(string.format("HUB_TAG harvest finished after %d inspections; %d tag(s) found",
                inspections - 1, #seenOrder))
            -- These five only ever fed the harvest, and the harvest is done. Two of them
            -- are called per tab per frame while the hub is open, so leaving them armed
            -- costs a bridge crossing for a callback that now returns immediately.
            for _, watcher in ipairs(WATCHERS) do
                if not watcher.announce then cyberfox1337x_ReleaseWatcherLater(watcher.name) end
            end
            publish()
            return
        end
        local name = tagName(tag)
        if not name or seenNames[name] then return end
        seenNames[name] = true
        seenOrder[#seenOrder + 1] = name
        log("HUB_TAG observed " .. name)
        publish()
    end

    -- Answers "which tab did the player just open", which the harvest cannot: record()
    -- drops a tag it has already seen, and by the time a tab can be activated its name
    -- is always already known. So the activation is read on its own path or not at all.
    --
    -- Bounded like the harvest, because this runs inside a game-thread hook and a chatty
    -- caller must not be able to cost frames without end.
    local function noteActivation(tag)
        if activationReads >= ACTIVATION_READ_BUDGET then
            cyberfox1337x_ReleaseWatcherLater("NotifyTabActivated")
            return
        end
        activationReads = activationReads + 1
        local name = tagName(tag)
        if not name or name == lastActivated then return end
        lastActivated = name
        log("HUB_TAG activated " .. name)
        publish()
    end

    local function cyberfox1337x_WatcherCallback(watcher)
        return function(...)
            calls[watcher.name] = (calls[watcher.name] or 0) + 1
            local tagParameter = select(watcher.slot + 1, ...)
            if not tagParameter then return end
            pcall(function()
                local tag = tagParameter:get()
                record(tag)
                if watcher.announce then noteActivation(tag) end
            end)
        end
    end

    -- Re-arms whatever is currently detached rather than gating on a single "armed"
    -- flag. A watcher released after its budget was spent has to be re-attachable, or
    -- Watch again would silently do nothing for exactly the watchers it exists to revive.
    local function armHooks()
        local armed, alreadyArmed, failures = {}, 0, {}
        for _, watcher in ipairs(WATCHERS) do
            if attachedHooks[watcher.name] then
                alreadyArmed = alreadyArmed + 1
            else
                local ok, preId, postId = pcall(registerHook, watcher.path,
                    function() end, cyberfox1337x_WatcherCallback(watcher))
                if ok then
                    attachedHooks[watcher.name] = { pre = preId, post = postId }
                    armed[#armed + 1] = watcher.name
                    if type(preId) ~= "number" or type(postId) ~= "number" then
                        log("HUB_TAG " .. watcher.name
                            .. " attached without hook ids; it cannot be released early")
                    end
                else
                    failures[#failures + 1] = watcher.name .. " (" .. tostring(preId) .. ")"
                end
            end
        end
        local total = #armed + alreadyArmed
        if total == 0 then
            return false, "No hub watcher could be attached: " .. table.concat(failures, "; ")
        end
        if #armed == 0 then return true, "Hub tag observation is already armed" end
        log("HUB_TAG watching " .. table.concat(armed, ", "))
        return true, string.format("Watching %d hub call(s): %s. Open the hub in game.",
            total, table.concat(armed, ", "))
    end

    -- FGameplayTag is one FName, the same shape as the FKey the No Clip control already
    -- builds from a Lua table. Constructing one is read-tested here before anything is
    -- allowed to mutate with it: IsGameplayTagValid answers safely, returning false for
    -- a tag the game does not know rather than doing anything dangerous.
    local function buildTag(name)
        return { TagName = FName(name) }
    end

    -- Read only. Reports whether a constructed tag is real and what the hub says about
    -- it, which is exactly what an unlock would need to rely on.
    local function checkSelected()
        local name = menu.Get(section, "tag")
        if type(name) ~= "string" or name == "" then
            menu.SetLabel(section, "check", "Select an observed tab tag first.")
            return
        end
        if not seenNames[name] then
            menu.SetLabel(section, "check", "That tag was not observed from the game; refusing to use it.")
            return
        end
        local ok, report = pcall(function()
            local library = tagLibrary()
            assert(library, "Gameplay tag library unavailable")
            local hub = FindFirstOf("HUBManagerSubystem")
            assert(valid(hub), "Hub manager unavailable")
            local tag = buildTag(name)
            local isValid = library:IsGameplayTagValid(tag)
            assert(isValid == true, "The game does not recognise a tag built from this name")
            local roundTrip = library:GetTagName(tag):ToString()
            assert(roundTrip == name, "Constructed tag reads back as " .. tostring(roundTrip))
            local locked = hub:BP_IsTabLocked(tag)
            local disabled = hub:BP_IsTabDisabled(tag)
            local blocked = hub:BP_IsTabBlocked(tag)
            return string.format("%s: valid=true locked=%s disabled=%s blocked=%s",
                name, tostring(locked), tostring(disabled), tostring(blocked))
        end)
        menu.SetLabel(section, "check", ok and report
            or ("Could not read that tab: " .. tostring(report):gsub("^.-:%d+:%s*", "")))
        log("HUB_TAG check " .. tostring(ok and report or report))
    end

    -- Proves, rather than infers, whether UnregisterHook takes effect on the installed
    -- build. Every other release in this module is decided inside a callback and
    -- deferred, and the log stopped recording unregisters after the game patched, so
    -- the only honest answer is to watch a callback: attach a counting hook to a
    -- function this module already calls safely, call it, detach, call again.
    --
    -- Three outcomes, each reported as what it is. Callbacks stop: released. Callbacks
    -- keep firing: hooks accumulate on this build and the log's silence was real. No
    -- callback at all: Lua-initiated calls do not trigger hooks here, and the test is
    -- inconclusive rather than a pass.
    local RELEASE_PROBE_CALLS = 3
    local function cyberfox1337x_TestHookRelease()
        local name = seenOrder[1]
        if not name then
            menu.SetLabel(section, "release", "Open the hub in game once first, so there is an observed tag to call with.")
            return
        end
        local path = HUB .. "BP_IsTabLocked"
        local count, preId, postId = 0, nil, nil
        local ok, report = pcall(function()
            local library = tagLibrary()
            assert(library, "Gameplay tag library unavailable")
            local hub = FindFirstOf("HUBManagerSubystem")
            assert(valid(hub), "Hub manager unavailable")
            local tag = buildTag(name)
            assert(library:IsGameplayTagValid(tag) == true, "The game does not recognise the observed tag")

            preId, postId = registerHook(path, function() end, function() count = count + 1 end)
            assert(type(preId) == "number" and type(postId) == "number", "RegisterHook returned no ids")
            for _ = 1, RELEASE_PROBE_CALLS do hub:BP_IsTabLocked(tag) end
            local before = count
            if before == 0 then
                return string.format("INCONCLUSIVE: hooks (%d, %d) never fired for %d Lua-initiated calls, "
                    .. "so this test cannot observe a release. Hooks were still detached.", preId, postId, RELEASE_PROBE_CALLS)
            end

            unregisterHook(path, preId, postId)
            local detached = preId
            preId, postId = nil, nil
            for _ = 1, RELEASE_PROBE_CALLS do hub:BP_IsTabLocked(tag) end
            local after = count - before

            if after == 0 then
                return string.format("RELEASED: UnregisterHook is effective on this build. Hook (%d) fired %d/%d "
                    .. "times before release and 0/%d after.", detached, before, RELEASE_PROBE_CALLS, RELEASE_PROBE_CALLS)
            end
            return string.format("NOT RELEASED: hook (%d) still fired %d/%d times after UnregisterHook. "
                .. "Hooks accumulate on this build; treat every release in this runtime as ineffective.",
                detached, after, RELEASE_PROBE_CALLS)
        end)
        -- The counting hook must not outlive the test whatever happened above.
        if preId ~= nil then
            local released, failure = pcall(unregisterHook, path, preId, postId)
            if not released then log("HUB_TAG release probe cleanup failed: " .. tostring(failure)) end
        end
        local text = ok and report or ("Release test failed before it could conclude: " .. tostring(report))
        log("HUB_TAG release probe: " .. text)
        menu.SetLabel(section, "release", text)
    end

    -- Exposed so the unlock control can only ever act on a tag the game itself supplied.
    function M.ObservedTags()
        local copy = {}
        for index, name in ipairs(seenOrder) do copy[index] = name end
        return copy
    end
    function M.HasObserved(name) return seenNames[name] == true end
    -- The tab the game last reported as activated, or nil. Proof that a tab is not only
    -- flagged unlocked but actually reachable in the wheel.
    function M.LastActivated() return lastActivated end

    -- Runs from the runtime's cleanup on a session change. The hooks are deliberately
    -- NOT released here: they observe the HUB subsystem, which outlives any save, and
    -- a release-then-re-arm on every load would leave an untracked duplicate behind if
    -- the native unregister ever silently failed - which cannot be ruled out from the
    -- log on the current build. Only the budgets and the per-session readout reset.
    -- They bound what the probe costs a session, not a process, and a watcher whose
    -- budget was already spent has already released itself through the queue above.
    -- Observed names are kept: they are the game's tag vocabulary rather than anything
    -- about this world, and the hub tab controls read them through ObservedTags.
    function M.ResetSession()
        inspections, harvesting = 0, true
        activationReads, lastActivated = 0, nil
        publish()
    end

    -- Re-arms only what the budgets released during the previous session. armHooks
    -- skips anything still attached, so a watcher that was never released is never
    -- registered twice.
    function M.SessionReady()
        local ok, message = armHooks()
        if not ok then error(message, 0) end
    end

    -- Unload is main.lua's job: every hook registered through its RegisterHook wrapper
    -- is recorded there and swept when the mod unloads, this module's included.

    -- Armed at load rather than on a button. The watchers are read-only and stop
    -- working after a bounded number of inspections, so the cost is fixed, and this way
    -- the tags are collected the first time the player opens the hub during normal play
    -- instead of requiring a ritual before the hub tab controls will work.
    local armedAtLoad, armMessage = armHooks()
    if not armedAtLoad then log("HUB_TAG auto-arm failed: " .. tostring(armMessage)) end

    menu.Register({ id = section, title = "Hub tab tags (read only)", tab = "☆ World", items = {
        { type = "label", id = "status", label = armedAtLoad
            and "Watching for hub tabs. Open the hub in game once and they are listed here."
            or ("Hub tab watching unavailable: " .. tostring(armMessage)) },
        { type = "button", id = "arm", label = "Watch again", onClick = function()
            -- Pressing it again resumes a finished harvest, for a tab that appears later.
            inspections, harvesting = 0, true
            local ok, message = armHooks()
            menu.SetLabel(section, "status", message)
            if not ok then log("HUB_TAG arm failed: " .. message) end
        end },
        { type = "label", id = "activity", label = "Hub calls seen: none yet" },
        { type = "button", id = "report", label = "Read hub call activity", onClick = function()
            menu.SetLabel(section, "activity", "Hub calls seen: " .. activityReport())
        end },
        { type = "label", id = "activated", label = "No tab opened yet. Open the hub in game and select a tab." },
        { type = "dropdown", id = "tag", label = "Observed tab tag",
          options = { { label = "Open the hub in game to list its tabs", value = false } }, default = false },
        { type = "button", id = "checkTab", label = "Read selected tab's lock state", onClick = function()
            ExecuteInGameThread(checkSelected)
        end },
        { type = "label", id = "check", label = "Select an observed tag, then read its lock state." },
        { type = "button", id = "testRelease", label = "Test hook release", onClick = function()
            ExecuteInGameThread(cyberfox1337x_TestHookRelease)
        end },
        { type = "label", id = "release",
          label = "Attaches a counting hook, calls the hub, detaches it, calls again. Reports whether UnregisterHook takes effect on this build." },
        { type = "label",
          label = "Reading only. Enumerating the tags directly crashes the game, so they are collected from the calls the game itself makes." },
    } })

    return M
end

return M
