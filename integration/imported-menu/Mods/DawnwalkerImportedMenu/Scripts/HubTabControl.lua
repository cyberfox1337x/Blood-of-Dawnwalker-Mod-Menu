local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("hub_tab_control")

--[[
Reads and changes hub tab lock states.

This panel shipped fully disabled for a long time because every hub function is keyed by
FGameplayTag and the only ways to enumerate them - GetAllTabTags(TArray<FGameplayTag>&)
and GetRegisteredHubTabs(TArray<FHubTabRow>&) - marshal a struct array into Lua, which
killed the game with EXCEPTION_ACCESS_VIOLATION in FName::ToString() <-
push_structproperty(). Those two remain untouched.

What unblocked it: HubTagProbe watches the calls the game itself makes while building
the hub and reads each tag's FName out of the parameter, inside the hook's lifetime.
Opening the hub once named all eight tabs, including UI.Menu.HUB.BrencisCourt - the tab
the Edict tutorial asks the player to open.

With a name in hand a tag can be rebuilt as { TagName = FName(name) }, the same
single-FName shape the No Clip control already builds an FKey from. Every rebuilt tag is
checked with IsGameplayTagValid and a GetTagName round trip before it is used, and only
names the probe actually observed are accepted - a typed-in name is never trusted.

BP_IsTabLocked and BP_SetTabLocked take plain arguments and were never the problem.
]]

local M = {}

local TAG_LIBRARY = "/Script/GameplayTags.Default__BlueprintGameplayTagLibrary"

local function valid(object)
    return object ~= nil and object.IsValid ~= nil and object:IsValid()
end

function M.Init(menu, helpers, options)
    options = options or {}
    local section = "DWHubTabs"
    local log = options.log or function() end
    local probe = options.hubTags
    local findFirstOf = options.findFirstOf or FindFirstOf
    local findObject = options.findObject or StaticFindObject
    local makeName = options.makeName or FName
    local runOnGameThread = options.runOnGameThread or ExecuteInGameThread

    -- Lock state as it was before this session first changed it, per tag.
    local original = {}

    local function library()
        local found = findObject(TAG_LIBRARY)
        assert(valid(found), "Gameplay tag library unavailable")
        return found
    end

    local function hub()
        local found = findFirstOf("HUBManagerSubystem")
        assert(valid(found), "Hub manager unavailable; load a save first")
        return found
    end

    -- A tag is only ever built from a name the probe saw the game use, and the rebuilt
    -- tag has to survive a round trip before anything touches it.
    local function tagFor(name)
        assert(type(name) == "string" and name ~= "", "Choose a hub tab first")
        assert(probe and probe.HasObserved and probe.HasObserved(name),
            "That tab was not observed from the game. Open the hub once with the tag watcher armed.")
        local tags = library()
        local tag = { TagName = makeName(name) }
        assert(tags:IsGameplayTagValid(tag) == true, "The game does not recognise a tag built from " .. name)
        assert(tags:GetTagName(tag):ToString() == name, "Rebuilt tag does not read back as " .. name)
        return tag
    end

    local function describe(manager, tag, name)
        return string.format("%s: locked=%s disabled=%s blocked=%s", name,
            tostring(manager:BP_IsTabLocked(tag)), tostring(manager:BP_IsTabDisabled(tag)),
            tostring(manager:BP_IsTabBlocked(tag)))
    end

    local function observedNames()
        if not probe or not probe.ObservedTags then return {} end
        return probe.ObservedTags()
    end

    local function refreshOptions()
        local list = {}
        for _, name in ipairs(observedNames()) do list[#list + 1] = { label = name, value = name } end
        if #list == 0 then list = { { label = "Arm the tag watcher and open the hub first", value = false } } end
        menu.SetOptions(section, "tab", list, false)
    end

    local function ownedFlag()
        for _ in pairs(original) do return true end
        return false
    end

    local function status(message)
        menu.SetLabel(section, "status", message)
        menu.Set(section, "owned", ownedFlag())
    end

    local function readAll()
        local names = observedNames()
        assert(#names > 0, "No hub tab observed yet. Arm the tag watcher and open the hub once.")
        refreshOptions()
        local manager, lines = hub(), {}
        for _, name in ipairs(names) do
            lines[#lines + 1] = describe(manager, tagFor(name), name)
        end
        status(table.concat(lines, " | "))
    end

    -- Records the pre-change state once per tag, so restore returns exactly what the
    -- save had rather than a guess at a sensible default.
    local function remember(manager, name, tag)
        if original[name] == nil then original[name] = manager:BP_IsTabLocked(tag) end
    end

    local function setLocked(name, locked)
        local manager = hub()
        local tag = tagFor(name)
        remember(manager, name, tag)
        -- The setter's second argument is bEnabled, not bLocked - the reflected
        -- parameter name, confirmed live: passing true made BP_IsTabLocked return
        -- false. The function name reads the other way round, so it is inverted here
        -- once, deliberately, rather than at every call site.
        -- bModifyVisibility true so the wheel redraws the tab, not just its flag.
        manager:BP_SetTabLocked(tag, not locked, true)
        local actual = manager:BP_IsTabLocked(tag)
        assert(actual == locked,
            string.format("The game kept %s locked=%s after the change", name, tostring(actual)))
        log(string.format("HUB_TAB %s locked -> %s", name, tostring(locked)))
        return actual
    end

    local function unlockSelected()
        local name = menu.Get(section, "tab")
        setLocked(name, false)
        status(string.format("Verified: %s is unlocked. Open the hub in game to use it.", name))
    end

    local function unlockAll()
        local names = observedNames()
        assert(#names > 0, "No hub tab observed yet. Arm the tag watcher and open the hub once.")
        local changed = {}
        for _, name in ipairs(names) do
            local manager, tag = hub(), tagFor(name)
            if manager:BP_IsTabLocked(tag) == true then
                setLocked(name, false)
                changed[#changed + 1] = name
            end
        end
        status(#changed == 0 and "No hub tab was locked; nothing to change."
            or ("Verified unlocked: " .. table.concat(changed, ", ")))
    end

    local function restore()
        local restored = {}
        for name, wasLocked in pairs(original) do
            local manager, tag = hub(), tagFor(name)
            manager:BP_SetTabLocked(tag, not wasLocked, true)
            local actual = manager:BP_IsTabLocked(tag)
            assert(actual == wasLocked,
                string.format("The game kept %s locked=%s while restoring", name, tostring(actual)))
            restored[#restored + 1] = string.format("%s->%s", name, tostring(wasLocked))
        end
        original = {}
        status(#restored == 0 and "Nothing was changed this session."
            or ("Restored this session's original lock states: " .. table.concat(restored, ", ")))
    end

    local function guarded(action)
        return function()
            runOnGameThread(function()
                local ok, failure = pcall(action)
                if not ok then
                    local clean = tostring(failure):gsub("^.-:%d+:%s*", "")
                    status("Hub tabs: " .. clean)
                    log("HUB_TAB failed: " .. tostring(failure))
                end
            end)
        end
    end

    menu.Register({ id = section, title = "Hub tabs", tab = "☆ World", items = {
        { type = "label", id = "status",
          label = "Arm the tag watcher above and open the hub once, then read the tabs here." },
        { type = "dropdown", id = "tab", label = "Hub tab",
          options = { { label = "Arm the tag watcher and open the hub first", value = false } }, default = false },
        { type = "button", id = "refresh", label = "Read hub tabs", onClick = guarded(readAll) },
        { type = "button", id = "unlock", label = "Unlock selected tab", onClick = guarded(unlockSelected) },
        { type = "button", id = "unlockAll", label = "Unlock every locked tab", onClick = guarded(unlockAll) },
        { type = "button", id = "restore", label = "Restore original lock states", variant = "secondary",
          onClick = guarded(restore) },
        { type = "checkbox", id = "owned", label = "A tab differs from this session's original", value = false },
        { type = "label",
          label = "UI.Menu.HUB.BrencisCourt is the tab the Edict tutorial asks for. Unlocking it lets that prompt be satisfied." },
        { type = "label",
          label = "Tabs are addressed by tags the game itself supplied while the hub was open; the tag list is never enumerated, because that crashes the game." },
    } })

    function M.ResetSession()
        original = {}
        refreshOptions()
        status("Arm the tag watcher above and open the hub once, then read the tabs here.")
    end

    return M
end

return M
