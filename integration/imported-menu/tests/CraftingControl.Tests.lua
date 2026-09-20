local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("crafting_control_tests")

-- Covers Scripts/CraftingControl.lua. Both crafting actions return nothing, so a
-- readback that does not move must never be reported as success.

local path = assert(arg[1], "Supply CraftingControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function alwaysValid() return true end

local function menuDouble()
    local menu = { labels = {}, sections = {} }
    function menu.Register(section) menu.sections[section.id] = section end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set() end
    function menu.SetOptions() end
    function menu.Get() end
    function menu.click(itemId)
        for _, item in ipairs(menu.sections.DWCrafting.items) do
            if item.id == itemId and item.onClick then return item.onClick() end
        end
        error("no such control: " .. itemId)
    end
    return menu
end

local function fixture(overrides)
    overrides = overrides or {}
    local world = {
        recipes = overrides.recipes or 10,
        daily = overrides.daily or 2,
        unlockCalls = 0,
        refillCalls = 0,
        recipesUnreadable = overrides.recipesUnreadable or false,
        missingSubsystem = overrides.missingSubsystem or false,
    }
    local subsystem
    subsystem = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x3000 end,
        GetFullName = function() return "CraftingSubsystem /Game/World.Crafting" end,
        IsA = function(_, class) return class == "/Script/DogwoodInventory.CraftingSubsystem" end,
        GetAvailableItemRecipes = function()
            if world.recipesUnreadable then error("recipe array unavailable") end
            local list = {}
            for index = 1, world.recipes do list[index] = index end
            return list
        end,
        GetPlayerCraftDailyFreeItems = function() return world.daily end,
        AreCraftLimitsEnabled = function() return true end,
        UnlockAllCraftingRecipes = function()
            world.unlockCalls = world.unlockCalls + 1
            if overrides.onUnlock then overrides.onUnlock(world) end
        end,
        RefillDailyFreeItems = function()
            world.refillCalls = world.refillCalls + 1
            if overrides.onRefill then overrides.onRefill(world) end
        end,
    }
    local player = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x1 end,
        GetWorld = function() return { IsValid = alwaysValid, GetAddress = function() return 0x2 end } end,
    }
    player.Controller = { IsValid = alwaysValid, GetAddress = function() return 0x3 end, Pawn = player }

    local environment = setmetatable({
        FindFirstOf = function(name)
            if name == "CraftingSubsystem" and not world.missingSubsystem then return subsystem end
            return nil
        end,
        print = function() end,
    }, { __index = _G })

    local module = assert(loadfile(path, "t", environment))()
    local menu = menuDouble()
    module.Init(menu, { GetPlayer = function() return player end })
    return menu, world
end

test("reading reports recipes, daily supplies and craft limits", function()
    local menu = fixture({ recipes = 12, daily = 3 })
    menu.click("refresh")
    assert(menu.labels.status:find("available recipes: 12", 1, true), menu.labels.status)
    assert(menu.labels.status:find("daily free items: 3", 1, true), menu.labels.status)
end)

test("a missing crafting subsystem refuses instead of guessing", function()
    local menu, world = fixture({ missingSubsystem = true })
    local ok = pcall(function() menu.click("refresh") end)
    assert(not ok, "a missing subsystem must fail")
    assert(menu.labels.status:find("Unavailable", 1, true), menu.labels.status)
    assert(world.unlockCalls == 0)
end)

test("unlock is verified by the recipe count rising", function()
    local menu, world = fixture({
        recipes = 10,
        onUnlock = function(state) state.recipes = 44 end,
    })
    menu.click("unlock")
    assert(world.unlockCalls == 1)
    assert(menu.labels.status:find("Verified: available recipes 10 -> 44", 1, true), menu.labels.status)
end)

test("an unchanged recipe count is reported as unchanged, not verified", function()
    local menu = fixture({ recipes = 10 })
    menu.click("unlock")
    assert(menu.labels.status:find("did not change", 1, true), menu.labels.status)
    assert(not menu.labels.status:find("Verified", 1, true), "must not claim Verified without movement")
end)

test("an unreadable recipe count leaves the unlock explicitly unverified", function()
    local menu = fixture({ recipesUnreadable = true })
    local ok = pcall(function() menu.click("unlock") end)
    assert(not ok, "an unverifiable unlock must not pass silently")
    assert(menu.labels.status:find("unverified", 1, true), menu.labels.status)
end)

test("daily refill is verified by the free-item count moving", function()
    local menu, world = fixture({
        daily = 0,
        onRefill = function(state) state.daily = 3 end,
    })
    menu.click("daily")
    assert(world.refillCalls == 1)
    assert(menu.labels.status:find("Verified: daily free items 0 -> 3", 1, true), menu.labels.status)
end)

test("an unchanged daily count is reported as already full", function()
    local menu = fixture({ daily = 3 })
    menu.click("daily")
    assert(menu.labels.status:find("did not change", 1, true), menu.labels.status)
end)

test("the permanent unlock confirms before acting", function()
    local menu = fixture()
    local unlock
    for _, item in ipairs(menu.sections.DWCrafting.items) do
        if item.id == "unlock" then unlock = item end
    end
    assert(unlock and unlock.confirm, "unlock must carry a confirmation")
    assert(unlock.confirm.message:find("cannot be undone", 1, true), "the confirmation must state it is permanent")
end)

test("ingredient granting is not offered as a control", function()
    local menu = fixture()
    for _, item in ipairs(menu.sections.DWCrafting.items) do
        assert(item.id ~= "ingredients", "an unverifiable ingredient control must not be registered")
    end
end)

-- Regression: a legitimate "false" reading must not be reported as unavailable.
test("craft limits reported as false is shown, not treated as missing", function()
    local menu = fixture()
    -- Rebuild with AreCraftLimitsEnabled returning false rather than true.
    local module = nil
    local world = { recipes = 4, daily = 1 }
    local subsystem = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x3000 end,
        GetFullName = function() return "CraftingSubsystem /Game/World.Crafting" end,
        IsA = function(_, class) return class == "/Script/DogwoodInventory.CraftingSubsystem" end,
        GetAvailableItemRecipes = function() return { 1, 2, 3, 4 } end,
        GetPlayerCraftDailyFreeItems = function() return 0 end,
        AreCraftLimitsEnabled = function() return false end,
        UnlockAllCraftingRecipes = function() end,
        RefillDailyFreeItems = function() end,
    }
    local player = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x1 end,
        GetWorld = function() return { IsValid = alwaysValid, GetAddress = function() return 0x2 end } end,
    }
    player.Controller = { IsValid = alwaysValid, GetAddress = function() return 0x3 end, Pawn = player }
    local environment = setmetatable({
        FindFirstOf = function(name) if name == "CraftingSubsystem" then return subsystem end return nil end,
        print = function() end,
    }, { __index = _G })
    module = assert(loadfile(path, "t", environment))()
    local menu2 = menuDouble()
    module.Init(menu2, { GetPlayer = function() return player end })
    menu2.click("refresh")
    assert(menu2.labels.status:find("craft limits enabled: false", 1, true),
        "a false craft-limit reading must be displayed: " .. menu2.labels.status)
    assert(menu2.labels.status:find("daily free items: 0", 1, true),
        "a zero daily count must be displayed: " .. menu2.labels.status)
end)

print(count .. " Crafting tests passed")
