local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("corruption_reset_tests")

-- Covers the session reset added to Source/CorruptionLevelControl.lua.
--
-- Corruption was the one control that could change a save with no way back. The reset
-- records the values before the first change of a session and writes them back, proving
-- the result with the game's own GetCurrentMutationLevel rather than assuming the write
-- landed.

local root = assert(arg[1]) .. "/Mods/DawnwalkerImportedMenu/Scripts/"

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
    function menu.item(itemId)
        for _, entry in ipairs(menu.sections.DWMutation.items) do
            if entry.id == itemId then return entry end
            if entry.type == "row" then
                for _, inner in ipairs(entry.items) do
                    if inner.id == itemId then return inner end
                end
            end
        end
        return nil
    end
    function menu.click(itemId)
        local item = menu.item(itemId)
        assert(item and item.onClick, "no such control: " .. itemId)
        return item.onClick()
    end
    return menu
end

-- attribute doubles mirror the game's FGameplayAttributeData shape.
local function attribute(base, current)
    return { BaseValue = base, CurrentValue = current }
end

local function fixture(startLevel, startCharge)
    local world = { delayed = {}, log = {} }
    local attributes = {
        IsValid = alwaysValid,
        GetAddress = function() return 0xA000 end,
        MutationLevel = attribute(startLevel, startLevel),
        MutationCharged = attribute(startCharge, startCharge),
    }
    local player = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x1 end,
        GetFullName = function() return "BP_PlayerCharacter_C /Game.World.Player" end,
        GetWorld = function() return { IsValid = alwaysValid } end,
        VampireAttributeSet = attributes,
        CombatComponent = { IsValid = alwaysValid, IsAlive = function() return true end },
    }
    player.Controller = { IsValid = alwaysValid, Pawn = player,
        GetAddress = function() return 0x3 end }
    -- The development subsystem reports whatever the attribute set currently holds.
    local development = {
        IsValid = alwaysValid,
        GetCurrentMutationLevel = function() return attributes.MutationLevel.CurrentValue end,
        GetCurrentMutationCharges = function() return attributes.MutationCharged.CurrentValue end,
    }
    local environment = setmetatable({
        FindFirstOf = function(name)
            if name == "CombatSubsystem" then
                return { IsValid = alwaysValid, GetIsInCombat = function() return false end }
            end
            return nil
        end,
        ExecuteInGameThread = function(callback) callback() end,
        ExecuteWithDelay = function(_, callback) world.delayed[#world.delayed + 1] = callback end,
        print = function() end,
    }, { __index = _G })

    local module = assert(loadfile(root .. "Source/CorruptionLevelControl.lua", "t", environment))()
    local menu = menuDouble()
    module.Init(menu, function() return player end, function() return development end,
        function(line) world.log[#world.log + 1] = line end, { refresh = function() end })
    world.attributes, world.menu, world.module = attributes, menu, module
    -- Run any queued verification pass.
    function world.settle()
        local queued = world.delayed
        world.delayed = {}
        for _, callback in ipairs(queued) do callback() end
    end
    return menu, world, module
end

test("the reset control exists and confirms before acting", function()
    local menu = fixture(3, 0)
    local reset = menu.item("resetOriginal")
    assert(reset, "a reset control must be registered")
    assert(reset.confirm, "the reset must confirm")
    assert(reset.confirm.message:find("not reversed", 1, true),
        "the confirmation must be clear that events are not undone")
end)

test("resetting before any change reports there is nothing to undo", function()
    local menu, world = fixture(3, 0)
    menu.click("resetOriginal")
    assert(menu.labels.lastChange:find("nothing to reset", 1, true), menu.labels.lastChange)
    assert(world.attributes.MutationLevel.CurrentValue == 3, "no write may happen")
end)

test("a level change is undone by the reset", function()
    local menu, world = fixture(2, 0)
    menu.values.level = 9
    menu.click("setLevel")
    world.settle()
    assert(world.attributes.MutationLevel.CurrentValue == 9, "the setter should have applied")
    assert(menu.values.owned == true, "ownership must be flagged once it differs")
    menu.click("resetOriginal")
    world.settle()
    assert(world.attributes.MutationLevel.CurrentValue == 2, "reset must restore the original level")
    assert(menu.labels.lastChange:find("Verified", 1, true), menu.labels.lastChange)
    assert(menu.values.owned == false, "ownership must clear after a verified reset")
end)

test("the reset restores the raw charge too, not just the level", function()
    local menu, world = fixture(4, 7)
    menu.values.level = 6
    menu.click("setLevel")
    world.settle()
    menu.click("resetOriginal")
    world.settle()
    assert(world.attributes.MutationLevel.CurrentValue == 4, "level must come back")
    assert(world.attributes.MutationCharged.CurrentValue == 7, "charge must come back")
end)

test("the baseline is the value before the FIRST change, not the latest", function()
    local menu, world = fixture(1, 0)
    menu.values.level = 5
    menu.click("setLevel"); world.settle()
    menu.values.level = 12
    menu.click("setLevel"); world.settle()
    menu.click("resetOriginal"); world.settle()
    assert(world.attributes.MutationLevel.CurrentValue == 1,
        "reset must return to 1, got " .. tostring(world.attributes.MutationLevel.CurrentValue))
end)

test("NoteBaseline lets a raw-charge change be reset as well", function()
    local menu, world, module = fixture(3, 2)
    -- The raw-charge buttons live in GameplayMenu; they call NoteBaseline first.
    module.NoteBaseline()
    world.attributes.MutationCharged.CurrentValue = 40
    world.attributes.MutationCharged.BaseValue = 40
    menu.click("resetOriginal"); world.settle()
    assert(world.attributes.MutationCharged.CurrentValue == 2,
        "a charge-only change must be undone, got " .. tostring(world.attributes.MutationCharged.CurrentValue))
    assert(world.attributes.MutationLevel.CurrentValue == 3)
end)

test("NoteBaseline never overwrites an existing baseline", function()
    local menu, world, module = fixture(3, 0)
    menu.values.level = 8
    menu.click("setLevel"); world.settle()
    module.NoteBaseline()
    menu.click("resetOriginal"); world.settle()
    assert(world.attributes.MutationLevel.CurrentValue == 3,
        "the original baseline must survive a later NoteBaseline call")
end)

test("a new session forgets the previous save's baseline", function()
    local menu, world, module = fixture(2, 0)
    menu.values.level = 7
    menu.click("setLevel"); world.settle()
    module.ResetSession()
    menu.click("resetOriginal")
    assert(menu.labels.lastChange:find("nothing to reset", 1, true), menu.labels.lastChange)
    assert(world.attributes.MutationLevel.CurrentValue == 7,
        "a reset session must not write another save's values")
end)

print(count .. " Corruption reset tests passed")
