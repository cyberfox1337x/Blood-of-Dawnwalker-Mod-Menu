local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("hub_tab_control_tests")

-- Covers Scripts/HubTabControl.lua.
--
-- The panel used to ship inert because the hub tab GameplayTags could not be enumerated
-- without crashing the game. It now addresses tabs by names HubTagProbe observed the
-- game itself using, rebuilding each tag as { TagName = FName(name) }.
--
-- What these tests hold down: a tag is never built from a name the probe did not
-- observe, a rebuilt tag is validated before use, a write is proved by reading it back,
-- and restore returns exactly the state the session started with. The two enumerating
-- functions must never be called at all.

local path = assert(arg[1], "Supply HubTabControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local OBSERVED = { "UI.Menu.HUB.Map", "UI.Menu.HUB.BrencisCourt" }

local function fixture(overrides)
    overrides = overrides or {}
    local world = { calls = {}, locked = { ["UI.Menu.HUB.Map"] = false, ["UI.Menu.HUB.BrencisCourt"] = true },
        labels = {}, values = {}, options = {}, sections = {}, log = {} }

    local function note(name) world.calls[#world.calls + 1] = name end

    local manager = {
        IsValid = function() return true end,
        BP_IsTabLocked = function(_, tag) note("BP_IsTabLocked"); return world.locked[tag.TagName] end,
        BP_IsTabDisabled = function(_, _) note("BP_IsTabDisabled"); return false end,
        BP_IsTabBlocked = function(_, _) note("BP_IsTabBlocked"); return false end,
        -- The second argument is bEnabled, not bLocked. Confirmed live: passing true
        -- makes BP_IsTabLocked report false. The double models that inversion so a
        -- regression back to passing the locked value fails here.
        BP_SetTabLocked = function(_, tag, enabledValue, modifyVisibility)
            note("BP_SetTabLocked")
            assert(modifyVisibility == true, "the wheel must be asked to redraw")
            assert(type(enabledValue) == "boolean", "bEnabled must be a boolean")
            if not world.refuseWrite then world.locked[tag.TagName] = not enabledValue end
        end,
        -- Present so a test can prove they are never reached.
        GetAllTabTags = function() note("GetAllTabTags"); error("would crash the game") end,
        GetRegisteredHubTabs = function() note("GetRegisteredHubTabs"); error("would crash the game") end,
    }
    local tagLibrary = {
        IsValid = function() return true end,
        IsGameplayTagValid = function(_, tag) return world.knownTags ~= false and tag.TagName ~= nil end,
        GetTagName = function(_, tag) return { ToString = function() return tag.TagName end } end,
    }

    local menu = {
        Register = function(spec) world.sections[spec.id] = spec end,
        SetLabel = function(_, id, value) world.labels[id] = tostring(value) end,
        Set = function(_, id, value) world.values[id] = value end,
        Get = function(_, id) return world.values[id] end,
        SetOptions = function(_, id, list) world.options[id] = list end,
    }

    local module = assert(loadfile(path, "t", setmetatable({}, { __index = _G })))()
    module.Init(menu, {}, {
        hubTags = {
            ObservedTags = function() return overrides.observed or OBSERVED end,
            HasObserved = function(name)
                for _, seen in ipairs(overrides.observed or OBSERVED) do if seen == name then return true end end
                return false
            end,
        },
        findFirstOf = function(name) assert(name == "HUBManagerSubystem"); return manager end,
        findObject = function() return tagLibrary end,
        makeName = function(name) return name end,
        runOnGameThread = function(callback) callback() end,
        log = function(line) world.log[#world.log + 1] = line end,
    })

    function world.click(itemId)
        for _, item in ipairs(world.sections.DWHubTabs.items) do
            if item.id == itemId then assert(item.onClick, itemId .. " has no action"); return item.onClick() end
        end
        error("no such control: " .. itemId)
    end
    world.menu = menu
    return world
end

test("reads every observed tab without touching the enumerating functions", function()
    local world = fixture()
    world.click("refresh")
    assert(world.labels.status:find("UI.Menu.HUB.BrencisCourt", 1, true), world.labels.status)
    assert(world.labels.status:find("locked=true", 1, true), world.labels.status)
    for _, call in ipairs(world.calls) do
        assert(call ~= "GetAllTabTags" and call ~= "GetRegisteredHubTabs",
            "the crashing enumeration must never be called")
    end
end)

test("unlocks the selected tab and proves it by reading back", function()
    local world = fixture()
    world.values.tab = "UI.Menu.HUB.BrencisCourt"
    world.click("unlock")
    assert(world.locked["UI.Menu.HUB.BrencisCourt"] == false, "the tab must end unlocked")
    assert(world.labels.status:find("Verified", 1, true), world.labels.status)
    assert(world.values.owned == true, "a changed tab must be flagged")
end)

test("refuses a tag the probe never observed", function()
    local world = fixture()
    world.values.tab = "UI.Menu.HUB.MadeUp"
    world.click("unlock")
    assert(world.labels.status:find("not observed", 1, true), world.labels.status)
    assert(world.locked["UI.Menu.HUB.BrencisCourt"] == true, "nothing may change on a refusal")
end)

test("refuses a name the game does not recognise as a tag", function()
    local world = fixture()
    world.knownTags = false
    world.values.tab = "UI.Menu.HUB.BrencisCourt"
    world.click("unlock")
    assert(world.labels.status:find("does not recognise", 1, true), world.labels.status)
    assert(world.locked["UI.Menu.HUB.BrencisCourt"] == true, "nothing may change on a refusal")
end)

test("reports a refused write instead of claiming success", function()
    local world = fixture()
    world.refuseWrite = true
    world.values.tab = "UI.Menu.HUB.BrencisCourt"
    world.click("unlock")
    assert(world.labels.status:find("kept", 1, true), world.labels.status)
    assert(not world.labels.status:find("Verified", 1, true), "a refused write must not read as verified")
end)

test("unlock all changes only the tabs that were locked", function()
    local world = fixture()
    world.click("unlockAll")
    assert(world.labels.status:find("UI.Menu.HUB.BrencisCourt", 1, true), world.labels.status)
    assert(not world.labels.status:find("UI.Menu.HUB.Map", 1, true), "an already-unlocked tab is not a change")
    assert(world.locked["UI.Menu.HUB.BrencisCourt"] == false)
end)

test("restore returns the session's original states and clears ownership", function()
    local world = fixture()
    world.values.tab = "UI.Menu.HUB.BrencisCourt"
    world.click("unlock")
    world.click("restore")
    assert(world.locked["UI.Menu.HUB.BrencisCourt"] == true, "the original locked state must come back")
    assert(world.labels.status:find("Restored", 1, true), world.labels.status)
    assert(world.values.owned == false, "ownership must clear after a restore")
end)

test("the baseline is the state before the first change, not the latest", function()
    local world = fixture()
    world.values.tab = "UI.Menu.HUB.BrencisCourt"
    world.click("unlock")
    world.click("unlock")
    world.click("restore")
    assert(world.locked["UI.Menu.HUB.BrencisCourt"] == true, "restore must return to the original, not an interim state")
end)

test("refuses everything while no tab has been observed", function()
    local world = fixture({ observed = {} })
    world.click("refresh")
    assert(world.labels.status:find("No hub tab observed", 1, true), world.labels.status)
    world.click("unlockAll")
    assert(world.labels.status:find("No hub tab observed", 1, true), world.labels.status)
    for _, call in ipairs(world.calls) do
        assert(call ~= "BP_SetTabLocked", "nothing may be written without an observed tag")
    end
end)

print(count .. " hub tab tests passed")
