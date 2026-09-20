local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("trait_point_control_tests")

-- Covers Scripts/TraitPointControl.lua. SetTraitPointsAmount returns nothing, so
-- GetTraitPointAmount decides every outcome, and restore must use the session's
-- own recorded original rather than any assumed default.

local path = assert(arg[1], "Supply TraitPointControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function alwaysValid() return true end

local function menuDouble()
    local menu = { labels = {}, values = {}, sections = {} }
    function menu.Register(section) menu.sections[section.id] = section end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set(_, itemId, value) menu.values[itemId] = value end
    function menu.SetOptions() end
    function menu.Get(_, itemId) return menu.values[itemId] end
    function menu.click(itemId)
        for _, item in ipairs(menu.sections.DWTraitPoints.items) do
            if item.id == itemId and item.onClick then return item.onClick() end
        end
        error("no such control: " .. itemId)
    end
    return menu
end

local function fixture(overrides)
    overrides = overrides or {}
    local world = { points = overrides.points or 5, writes = {}, obeys = overrides.obeys ~= false }
    local subsystem = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x5000 end,
        GetFullName = function() return "CharacterDevelopmentSubsystem /Game/World.Dev" end,
        IsA = function(_, class) return class == "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem" end,
        GetTraitPointAmount = function() return world.points end,
        SetTraitPointsAmount = function(_, value)
            world.writes[#world.writes + 1] = value
            if world.obeys then world.points = value end
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
            if name == "CharacterDevelopmentSubsystem" then return subsystem end
            return nil
        end,
        print = function() end,
    }, { __index = _G })
    local module = assert(loadfile(path, "t", environment))()
    local menu = menuDouble()
    module.Init(menu, { GetPlayer = function() return player end })
    return menu, world, module
end

test("reading records the session's original total", function()
    local menu = fixture({ points = 7 })
    menu.click("refresh")
    assert(menu.labels.status:find("Available trait points: 7", 1, true), menu.labels.status)
    assert(menu.labels.status:find("Original this session: 7", 1, true), menu.labels.status)
end)

test("setting an exact total is verified by the readback", function()
    local menu, world = fixture({ points = 5 })
    menu.click("refresh")
    menu.values.amount = 25
    menu.click("apply")
    assert(#world.writes == 1 and world.writes[1] == 25)
    assert(menu.labels.status:find("Verified: trait points set to 25", 1, true), menu.labels.status)
    assert(menu.values.owned == true)
end)

test("restore returns the original total and clears ownership", function()
    local menu, world = fixture({ points = 5 })
    menu.click("refresh")
    menu.values.amount = 25
    menu.click("apply")
    menu.click("restore")
    assert(world.points == 5, "restore must put the original total back")
    assert(menu.labels.status:find("Restored the original 5", 1, true), menu.labels.status)
    assert(menu.values.owned == false)
end)

test("a refused write is reported, not claimed as success", function()
    local menu, world = fixture({ points = 5, obeys = false })
    menu.click("refresh")
    menu.values.amount = 25
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok, "a readback mismatch must not pass")
    assert(#world.writes == 1)
    assert(menu.labels.status:find("refused", 1, true), menu.labels.status)
end)

test("an out-of-range total is rejected before writing", function()
    local menu, world = fixture({ points = 5 })
    menu.click("refresh")
    menu.values.amount = -3
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok, "a negative total must be rejected")
    assert(#world.writes == 0, "nothing may be written for an invalid total")
end)

test("restore before any read refuses rather than guessing", function()
    local menu, world = fixture({ points = 5 })
    local ok = pcall(function() menu.click("restore") end)
    assert(not ok)
    assert(#world.writes == 0)
end)

test("a new session forgets the previous save's original total", function()
    local menu, world, module = fixture({ points = 5 })
    menu.click("refresh")
    module.ResetSession()
    local ok = pcall(function() menu.click("restore") end)
    assert(not ok, "a reset session must not restore into another save")
    assert(#world.writes == 0)
end)

test("setting the total carries a confirmation", function()
    local menu = fixture()
    for _, item in ipairs(menu.sections.DWTraitPoints.items) do
        if item.id == "apply" then assert(item.confirm, "apply must confirm") end
    end
end)

print(count .. " Trait point tests passed")
