local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("hub_tag_probe_tests")

-- Covers Scripts/HubTagProbe.lua.
--
-- The probe is the only source of hub tab names, because enumerating the tags directly
-- kills the game. Everything the hub tab controls do rests on it, so what it observes
-- and what it refuses to invent both need holding down.
--
-- The case that motivated these tests: the harvest dedupes by name, so by the time a
-- player opens a tab its name is already known and the harvest drops the call. That
-- made "which tab did the player actually open" unobservable - the one fact needed to
-- show a tab is reachable in the wheel rather than merely flagged unlocked.

local path = assert(arg[1], "Supply HubTagProbe.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function boxed(value) return { get = function() return value end } end

local function fixture(overrides)
    overrides = overrides or {}
    local world = { hooks = {}, labels = {}, options = {}, values = {}, sections = {}, log = {},
        tagReads = 0, released = {}, nextHookId = 0 }

    local library = {
        IsValid = function() return true end,
        GetTagName = function(_, tag)
            world.tagReads = world.tagReads + 1
            return { ToString = function()
                if world.unreadable then error("tag name unavailable") end
                return tag.TagName
            end }
        end,
        IsGameplayTagValid = function(_, tag) return tag.TagName ~= nil end,
    }
    -- Firing every hook attached to a path is what UE4SS does on a native call. The
    -- fake hub does the same, so a hook that was really detached stops being observed
    -- and one that was not keeps counting - the distinction the release probe exists
    -- to make.
    local PREFIX = "/Script/DogwoodUI.HUBManagerSubystem:"
    local function fireHooks(name, ...)
        for _, post in pairs(world.hooks[PREFIX .. name] or {}) do post(...) end
    end
    local hub = {
        IsValid = function() return true end,
        BP_IsTabLocked = function(_, tag)
            if not world.silentHub then fireHooks("BP_IsTabLocked", boxed("context"), boxed(0), boxed(tag)) end
            return world.locked and world.locked[tag.TagName] or false
        end,
        BP_IsTabDisabled = function() return false end,
        BP_IsTabBlocked = function() return false end,
    }

    local menu = {
        Register = function(spec) world.sections[spec.id] = spec end,
        SetLabel = function(_, id, value) world.labels[id] = tostring(value) end,
        Set = function(_, id, value) world.values[id] = value end,
        Get = function(_, id) return world.values[id] end,
        SetOptions = function(_, id, list) world.options[id] = list end,
    }

    local environment = setmetatable({
        StaticFindObject = function() return library end,
        FindFirstOf = function() return hub end,
        FName = function(name) return name end,
        ExecuteInGameThread = function(callback) callback() end,
    }, { __index = _G })

    local module = assert(loadfile(path, "t", environment))()
    local deferred = {}
    world.probe = module.Init(menu, {}, {
        registerHook = function(hookPath, _pre, post)
            if overrides.refuseHooks then error("cannot attach") end
            world.nextHookId = world.nextHookId + 1
            local pre = world.nextHookId * 10
            world.hooks[hookPath] = world.hooks[hookPath] or {}
            world.hooks[hookPath][pre] = post
            -- UE4SS hands back a pre id and a post id; the probe has to keep both or it
            -- can never detach what it attached.
            return pre, pre + 1
        end,
        unregisterHook = function(hookPath, pre, post)
            local attached = world.hooks[hookPath]
            assert(attached and attached[pre], "released a hook that was not attached: " .. hookPath)
            world.released[#world.released + 1] = { path = hookPath, pre = pre, post = post }
            -- A build on which UnregisterHook silently does nothing is exactly what the
            -- release probe has to be able to detect, so the fake can be told to no-op.
            if overrides.unregisterIsNoop then return end
            attached[pre] = nil
            if next(attached) == nil then world.hooks[hookPath] = nil end
        end,
        -- Queued rather than run inline, because that is what the runtime does: the
        -- release lands on a later game-thread pass, never inside the callback that
        -- asked for it. world.settle() below is that later pass.
        deferToGameThread = function(callback)
            if overrides.refuseDefer then error("no game thread available") end
            deferred[#deferred + 1] = callback
        end,
        log = function(line) world.log[#world.log + 1] = line end,
    })
    function world.settle()
        local queued = deferred
        deferred = {}
        for _, callback in ipairs(queued) do callback() end
    end
    function world.attachedCount()
        local total = 0
        for _ in pairs(world.hooks) do total = total + 1 end
        return total
    end

    -- Drives one watcher the way UE4SS does: (context, [return,] ...parameters). The
    -- tag sits in the slot the module declared, so this exercises the real offsets.
    local SLOTS = { BP_IsTabLocked = 2, TryShowHUB = 3, IsTabActive = 2,
        NotifyTabActivated = 1, RegisterSpawnedTabWidget = 1, LaunchHUB = 2 }
    function world.fire(watcher, tagName)
        assert(world.hooks[PREFIX .. watcher], "watcher not attached: " .. watcher)
        local arguments = { boxed("context") }
        for slot = 1, SLOTS[watcher] do
            arguments[slot + 1] = slot == SLOTS[watcher] and boxed({ TagName = tagName }) or boxed(0)
        end
        fireHooks(watcher, table.unpack(arguments))
    end
    function world.hookCount(watcher)
        local total = 0
        for _ in pairs(world.hooks[PREFIX .. watcher] or {}) do total = total + 1 end
        return total
    end
    -- A label starts life as the text Register() declared and is only replaced once
    -- something publishes, so both sources have to be consulted.
    function world.label(itemId)
        if world.labels[itemId] then return world.labels[itemId] end
        for _, item in ipairs(world.sections.DWHubTags.items) do
            if item.id == itemId then return tostring(item.label) end
        end
        error("no such label: " .. itemId)
    end
    function world.click(itemId)
        for _, item in ipairs(world.sections.DWHubTags.items) do
            if item.id == itemId then assert(item.onClick, itemId .. " has no action"); return item.onClick() end
        end
        error("no such control: " .. itemId)
    end
    return world
end

test("arms every hub watcher at load without being asked", function()
    local world = fixture()
    local attached = 0
    for _ in pairs(world.hooks) do attached = attached + 1 end
    assert(attached == 6, "expected 6 watchers, got " .. attached)
    assert(world.label("status"):find("Watching", 1, true), world.label("status"))
end)

test("reports that watching is unavailable instead of pretending it is armed", function()
    local world = fixture({ refuseHooks = true })
    assert(world.label("status"):find("unavailable", 1, true), world.label("status"))
    assert(next(world.hooks) == nil)
end)

test("harvests a tab name from a call the game makes, in the order it was seen", function()
    local world = fixture()
    world.fire("RegisterSpawnedTabWidget", "UI.Menu.HUB.Map")
    world.fire("RegisterSpawnedTabWidget", "UI.Menu.HUB.BrencisCourt")
    local observed = world.probe.ObservedTags()
    assert(observed[1] == "UI.Menu.HUB.Map" and observed[2] == "UI.Menu.HUB.BrencisCourt",
        table.concat(observed, ", "))
    assert(world.probe.HasObserved("UI.Menu.HUB.BrencisCourt"))
end)

test("never claims to have observed a name the game did not supply", function()
    local world = fixture()
    world.fire("RegisterSpawnedTabWidget", "UI.Menu.HUB.Map")
    assert(world.probe.HasObserved("UI.Menu.HUB.MadeUp") == false)
end)

test("a repeated tab is recorded once", function()
    local world = fixture()
    for _ = 1, 5 do world.fire("BP_IsTabLocked", "UI.Menu.HUB.Map") end
    assert(#world.probe.ObservedTags() == 1)
end)

test("a tag whose name cannot be read is skipped rather than recorded as nil", function()
    local world = fixture()
    world.unreadable = true
    world.fire("BP_IsTabLocked", "UI.Menu.HUB.Map")
    assert(#world.probe.ObservedTags() == 0)
end)

test("stops harvesting after the inspection budget so the hooks cost a fixed amount", function()
    local world = fixture()
    for index = 1, 700 do world.fire("IsTabActive", "UI.Menu.HUB.Tab" .. index) end
    local observed = #world.probe.ObservedTags()
    assert(observed <= 600, "harvest ran past its budget: " .. observed)
    assert(world.label("status"):find("watching stopped", 1, true), world.label("status"))
end)

test("no tab is reported as opened until the game says one was", function()
    local world = fixture()
    assert(world.probe.LastActivated() == nil)
    world.fire("RegisterSpawnedTabWidget", "UI.Menu.HUB.BrencisCourt")
    assert(world.probe.LastActivated() == nil, "spawning a widget is not the player opening a tab")
    assert(world.label("activated"):find("No tab opened yet", 1, true), world.label("activated"))
end)

test("reports the opened tab even though the harvest already knew its name", function()
    local world = fixture()
    -- This is the regression: the harvest dedupes, so the activation of an
    -- already-harvested tab used to leave no trace at all.
    world.fire("RegisterSpawnedTabWidget", "UI.Menu.HUB.BrencisCourt")
    world.fire("NotifyTabActivated", "UI.Menu.HUB.BrencisCourt")
    assert(world.probe.LastActivated() == "UI.Menu.HUB.BrencisCourt", tostring(world.probe.LastActivated()))
    assert(world.label("activated"):find("UI.Menu.HUB.BrencisCourt", 1, true), world.label("activated"))
end)

test("reports the opened tab after the harvest budget is spent", function()
    local world = fixture()
    for index = 1, 700 do world.fire("IsTabActive", "UI.Menu.HUB.Tab" .. index) end
    world.fire("NotifyTabActivated", "UI.Menu.HUB.BrencisCourt")
    assert(world.probe.LastActivated() == "UI.Menu.HUB.BrencisCourt",
        "a finished harvest must not silence the activation readout")
end)

test("the latest opened tab replaces the previous one", function()
    local world = fixture()
    world.fire("NotifyTabActivated", "UI.Menu.HUB.Map")
    world.fire("NotifyTabActivated", "UI.Menu.HUB.BrencisCourt")
    assert(world.probe.LastActivated() == "UI.Menu.HUB.BrencisCourt")
end)

test("activation reads are bounded so a chatty caller cannot cost frames forever", function()
    local world = fixture()
    -- Spend the harvest budget first, so from here every name read is an activation
    -- read and the count below measures only the thing this test is about.
    for index = 1, 700 do world.fire("IsTabActive", "UI.Menu.HUB.Tab" .. index) end
    local beforeActivations = world.tagReads
    for index = 1, 400 do world.fire("NotifyTabActivated", "UI.Menu.HUB.Opened" .. index) end
    local activationReads = world.tagReads - beforeActivations
    assert(activationReads <= 200, "activation reads ran past their budget: " .. activationReads)
    local budgeted = world.tagReads
    world.fire("NotifyTabActivated", "UI.Menu.HUB.Late")
    assert(world.tagReads == budgeted, "a read happened past the budget")
    assert(world.probe.LastActivated() ~= "UI.Menu.HUB.Late",
        "the readout must stop rather than report past its budget")
end)

test("reading a selected tab reports what the hub says about it", function()
    local world = fixture()
    world.fire("RegisterSpawnedTabWidget", "UI.Menu.HUB.BrencisCourt")
    world.locked = { ["UI.Menu.HUB.BrencisCourt"] = true }
    world.values.tag = "UI.Menu.HUB.BrencisCourt"
    world.click("checkTab")
    assert(world.label("check"):find("locked=true", 1, true), world.label("check"))
end)

test("refuses to read a tag the game never supplied", function()
    local world = fixture()
    world.values.tag = "UI.Menu.HUB.MadeUp"
    world.click("checkTab")
    assert(world.label("check"):find("not observed", 1, true), world.label("check"))
end)

test("keeps the harvest watchers armed until the callback that finished the harvest returns", function()
    local world = fixture()
    for index = 1, 700 do world.fire("IsTabActive", "UI.Menu.HUB.Tab" .. index) end
    -- Unregistering a hook from inside its own callback is the hazard the deferral
    -- exists to avoid, so nothing may have been detached yet.
    assert(world.attachedCount() == 6, "a watcher was released inside its own callback")
    assert(#world.released == 0, "a release ran before the game thread came back")
end)

test("releases the harvest watchers once the harvest is done", function()
    local world = fixture()
    for index = 1, 700 do world.fire("IsTabActive", "UI.Menu.HUB.Tab" .. index) end
    world.settle()
    assert(world.attachedCount() == 1, "expected only the activation watcher, got "
        .. world.attachedCount())
    assert(world.hooks["/Script/DogwoodUI.HUBManagerSubystem:NotifyTabActivated"],
        "the activation watcher still has work to do and must stay armed")
    for _, release in ipairs(world.released) do
        assert(type(release.pre) == "number" and type(release.post) == "number",
            "a watcher was released without the ids RegisterHook returned")
    end
end)

test("releases the activation watcher once its read budget is spent", function()
    local world = fixture()
    for index = 1, 700 do world.fire("IsTabActive", "UI.Menu.HUB.Tab" .. index) end
    world.settle()
    for index = 1, 400 do world.fire("NotifyTabActivated", "UI.Menu.HUB.Opened" .. index) end
    world.settle()
    assert(world.attachedCount() == 0,
        "every watcher's work is finished, so none may be left crossing into Lua")
end)

test("watching again re-arms the watchers that were released", function()
    local world = fixture()
    for index = 1, 700 do world.fire("IsTabActive", "UI.Menu.HUB.Tab" .. index) end
    world.settle()
    world.click("arm")
    assert(world.attachedCount() == 6, "Watch again left released watchers detached: "
        .. world.attachedCount())
    world.fire("RegisterSpawnedTabWidget", "UI.Menu.HUB.Map")
    assert(world.probe.HasObserved("UI.Menu.HUB.Map"), "a re-armed watcher recorded nothing")
end)

test("a session change keeps the watchers armed and never registers a duplicate", function()
    local world = fixture()
    -- The hooks observe a subsystem that outlives any save. Releasing and re-arming
    -- them on every load would leave an untracked duplicate behind if the native
    -- unregister ever silently failed, so a session change must touch neither.
    world.probe.ResetSession()
    assert(world.attachedCount() == 6, "a session change detached watchers")
    assert(#world.released == 0, "a session change released a watcher")
    world.probe.SessionReady()
    assert(world.attachedCount() == 6, "SessionReady registered a duplicate: "
        .. world.attachedCount())
end)

test("the next session re-arms only what the budgets released", function()
    local world = fixture()
    for index = 1, 700 do world.fire("IsTabActive", "UI.Menu.HUB.Tab" .. index) end
    world.settle()
    assert(world.attachedCount() == 1, "harvest watchers should have released")
    world.probe.ResetSession()
    world.probe.SessionReady()
    assert(world.attachedCount() == 6, "the new session left the probe deaf: "
        .. world.attachedCount())
    assert(#world.released == 5, "expected exactly the 5 saturated releases, got "
        .. #world.released)
    world.fire("RegisterSpawnedTabWidget", "UI.Menu.HUB.Map")
    assert(world.probe.HasObserved("UI.Menu.HUB.Map"))
end)

test("a session change restores the budgets so the next session can harvest", function()
    local world = fixture()
    for index = 1, 700 do world.fire("IsTabActive", "UI.Menu.HUB.Tab" .. index) end
    world.settle()
    world.probe.ResetSession()
    world.probe.SessionReady()
    -- A re-armed harvest watcher whose budget was still spent would release itself on
    -- its first call, which is the failure this reset exists to prevent.
    world.fire("IsTabActive", "UI.Menu.HUB.FreshWorldTab")
    world.settle()
    assert(world.attachedCount() == 6, "the re-armed watchers released themselves again")
    assert(world.probe.HasObserved("UI.Menu.HUB.FreshWorldTab"))
end)

test("a session change clears the tab the previous session reported as opened", function()
    local world = fixture()
    world.fire("NotifyTabActivated", "UI.Menu.HUB.BrencisCourt")
    assert(world.probe.LastActivated() == "UI.Menu.HUB.BrencisCourt")
    world.probe.ResetSession()
    assert(world.probe.LastActivated() == nil, "a tab opened in the previous session was still reported")
    assert(world.label("activated"):find("No tab opened yet", 1, true), world.label("activated"))
end)

test("a release that cannot be deferred is reported and never done inside the callback", function()
    local world = fixture({ refuseDefer = true })
    -- Detaching inline here would unregister a hook from inside its own callback, so the
    -- probe must keep going; unload (main.lua's sweep) is what eventually detaches it.
    for index = 1, 700 do world.fire("IsTabActive", "UI.Menu.HUB.Tab" .. index) end
    assert(world.attachedCount() == 6, "a watcher was detached from inside its own callback")
    assert(world.log[#world.log]:find("deferred hook release unavailable", 1, true),
        "a release that could not be scheduled was not reported: " .. tostring(world.log[#world.log]))
end)

test("the release probe reports RELEASED when a detached hook stops firing", function()
    local world = fixture()
    world.fire("RegisterSpawnedTabWidget", "UI.Menu.HUB.Inventory")
    world.click("testRelease")
    local verdict = world.label("release")
    assert(verdict:find("RELEASED", 1, true) and not verdict:find("NOT RELEASED", 1, true), verdict)
    assert(verdict:find("3/3 times before", 1, true) and verdict:find("0/3 after", 1, true), verdict)
    -- Its own counting hook is gone; only the probe's watcher remains on that path.
    assert(world.hookCount("BP_IsTabLocked") == 1, "the probe left its counting hook attached")
end)

test("the release probe reports NOT RELEASED on a build where UnregisterHook is a no-op", function()
    local world = fixture({ unregisterIsNoop = true })
    world.fire("RegisterSpawnedTabWidget", "UI.Menu.HUB.Inventory")
    world.click("testRelease")
    local verdict = world.label("release")
    -- This is the outcome the whole test exists to be able to say out loud.
    assert(verdict:find("NOT RELEASED", 1, true), verdict)
    assert(verdict:find("still fired 3/3", 1, true), verdict)
end)

test("the release probe is INCONCLUSIVE rather than passing when hooks never fire", function()
    local world = fixture()
    world.fire("RegisterSpawnedTabWidget", "UI.Menu.HUB.Inventory")
    -- A hub whose native call does not trigger hooks at all.
    world.silentHub = true
    world.click("testRelease")
    local verdict = world.label("release")
    assert(verdict:find("INCONCLUSIVE", 1, true) and not verdict:find("RELEASED:", 1, true), verdict)
end)

test("the release probe needs an observed tag and says so", function()
    local world = fixture()
    world.click("testRelease")
    assert(world.label("release"):find("Open the hub in game once first", 1, true), world.label("release"))
    assert(world.hookCount("BP_IsTabLocked") == 1, "a hook was attached without a tag to call with")
end)

print(count .. " hub tag probe tests passed")
