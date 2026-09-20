local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("free_crafting_control_tests")

-- Covers Scripts/FreeCraftingControl.lua: the bForFree argument of the game's crafting
-- calls is forced true only while the switch is ON, only for the player's own subsystem,
-- and the result of each forced craft is reported from the native return value.
-- usage: lua FreeCraftingControl.Tests.lua <path to Scripts/FreeCraftingControl.lua>

local path = assert(arg[1], "Supply FreeCraftingControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function object(id, extra)
    local o = { IsValid = function() return true end, GetAddress = function() return id end }
    for key, value in pairs(extra or {}) do o[key] = value end
    return o
end
local function param(value) return { get = function() return value end, set = function(_, v) value = v end } end

local function fixture()
    local world = object(1)
    local subsystem = object(2, { IsA = function(_, class) return class == "/Script/DogwoodInventory.CraftingSubsystem" end,
        GetOuter = function() return world end, GetFullName = function() return "CraftingSubsystem /Game/Map.Map:PersistentLevel.CraftingSubsystem_0" end })
    local foreign = object(3, { IsA = subsystem.IsA, GetOuter = function() return object(9) end,
        GetFullName = function() return "CraftingSubsystem /Game/Other.Other:PersistentLevel.CraftingSubsystem_1" end })
    local player = object(4, { GetWorld = function() return world end })
    local hooks = {}
    local menu = { labels = {}, values = {}, sections = {} }
    -- Registration seeds the labels with their defaults, as the real facade publishes them.
    function menu.Register(section) menu.sections[section.id] = section; for _, item in ipairs(section.items) do if item.type == "label" and item.id then menu.labels[item.id] = item.label end end end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set(_, itemId, value) menu.values[itemId] = value end
    function menu.toggle(value)
        for _, item in ipairs(menu.sections.DWFreeCrafting.items) do if item.id == "enabled" then return item.onChange(value) end end
        error("no switch")
    end
    local module = assert(loadfile(path))().Init(menu, { GetPlayer = function() return player end }, {
        registerHook = function(functionPath, pre, post) hooks[functionPath] = { pre = pre, post = post }; return 1, 2 end,
    })
    -- Simulates the native call: pre-hook, body reads the (possibly rewritten) flag, post-hook.
    local function craft(target, forFree, result)
        local flag = param(forFree)
        local hook = hooks["/Script/DogwoodInventory.CraftingSubsystem:CraftItem"]
        hook.pre(param(target), param({}), param(1), flag, param(1))
        hook.post(param(target), param(result), param({}), param(1), flag, param(1))
        return flag.get()
    end
    local function check(target, forFree)
        local flag = param(forFree)
        hooks["/Script/DogwoodInventory.CraftingSubsystem:CanItemBeCrafted"].pre(param(target), param({}), flag, param(1))
        return flag.get()
    end
    -- Simulates a readback: the native body returned `value`; the post-hook may rewrite it.
    local function readback(functionPath, target, value)
        local returned = param(value)
        hooks["/Script/DogwoodInventory.CraftingSubsystem:" .. functionPath].post(param(target), returned, param({}))
        return returned.get()
    end
    return { menu = menu, module = module, subsystem = subsystem, foreign = foreign, craft = craft, check = check, readback = readback, hooks = hooks }
end

test("all four crafting hooks are installed", function()
    local f = fixture()
    for _, name in ipairs({ "CraftItem", "CanItemBeCrafted", "IsItemCraftable", "GetItemMaxCraftCount" }) do
        assert(f.hooks["/Script/DogwoodInventory.CraftingSubsystem:" .. name], name)
    end
end)

test("ON reports every recipe craftable and at least one craft possible; OFF leaves readbacks alone", function()
    local f = fixture()
    assert(f.readback("IsItemCraftable", f.subsystem, false) == false and f.readback("GetItemMaxCraftCount", f.subsystem, 0) == 0)
    f.menu.toggle(true)
    assert(f.readback("IsItemCraftable", f.subsystem, false) == true)
    assert(f.readback("GetItemMaxCraftCount", f.subsystem, 0) == 1)
    assert(f.readback("GetItemMaxCraftCount", f.subsystem, 5) == 5, "a real count is never lowered")
    assert(f.readback("IsItemCraftable", f.foreign, false) == false, "another world's subsystem is left alone")
    f.craft(f.subsystem, false, 1)
    assert(f.menu.labels.status:find("2 craftable readbacks forced", 1, true), f.menu.labels.status)
end)

test("OFF leaves every argument exactly as the game made it", function()
    local f = fixture()
    assert(f.check(f.subsystem, false) == false)
    assert(f.craft(f.subsystem, false, 3) == false)
    assert(f.menu.labels.status == "Ignore crafting requirement OFF.")
end)

test("ON forces bForFree on the player's subsystem and reports the native result", function()
    local f = fixture(); f.menu.toggle(true)
    assert(f.check(f.subsystem, false) == true, "availability check must run free")
    assert(f.craft(f.subsystem, false, 1) == true, "craft must run free")
    assert(f.menu.labels.status:find("1 craft made free", 1, true) and f.menu.labels.status:find("1 availability check passed", 1, true)
        and f.menu.labels.status:find("Last craft: Success", 1, true), f.menu.labels.status)
    f.craft(f.subsystem, false, 7)
    assert(f.menu.labels.status:find("2 crafts made free", 1, true) and f.menu.labels.status:find("CraftingLimitReached", 1, true), f.menu.labels.status)
end)

test("a call already free is counted as untouched", function()
    local f = fixture(); f.menu.toggle(true)
    assert(f.craft(f.subsystem, true, 1) == true)
    assert(f.menu.labels.status:find("0 crafts made free", 1, true), f.menu.labels.status)
end)

test("another world's subsystem is never rewritten", function()
    local f = fixture(); f.menu.toggle(true)
    assert(f.check(f.foreign, false) == false)
    assert(f.craft(f.foreign, false, 1) == false)
    assert(f.menu.labels.status:find("0 crafts made free", 1, true), f.menu.labels.status)
end)

test("turning OFF stops forcing and clears the counters", function()
    local f = fixture(); f.menu.toggle(true); f.craft(f.subsystem, false, 1)
    f.menu.toggle(false)
    assert(f.craft(f.subsystem, false, 3) == false)
    assert(f.menu.labels.status == "Ignore crafting requirement OFF.")
    f.menu.toggle(true)
    assert(f.menu.labels.status:find("0 crafts made free", 1, true), f.menu.labels.status)
end)

test("a session change resets the counters but keeps the switch", function()
    local f = fixture(); f.menu.toggle(true); f.craft(f.subsystem, false, 1)
    f.module.ResetSession()
    assert(f.menu.labels.status:find("0 crafts made free", 1, true), f.menu.labels.status)
    assert(f.craft(f.subsystem, false, 1) == true)
end)

test("a failed hook installation refuses the switch with a reason", function()
    local menu = { labels = {}, values = {}, sections = {} }
    function menu.Register(section) menu.sections[section.id] = section end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set(_, itemId, value) menu.values[itemId] = value end
    assert(loadfile(path))().Init(menu, { GetPlayer = function() return nil end }, { registerHook = function() error("no such function") end })
    for _, item in ipairs(menu.sections.DWFreeCrafting.items) do if item.id == "enabled" then item.onChange(true) end end
    assert(menu.values.enabled == false and menu.labels.status:find("unavailable", 1, true), menu.labels.status)
end)

print(string.format("%d/%d free-crafting tests passed", count, count))
