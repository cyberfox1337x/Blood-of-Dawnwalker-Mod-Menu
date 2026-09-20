local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("equipment_loadout_control_tests")

-- Covers Scripts/EquipmentLoadoutControl.lua: the loadout roster must come from the
-- game's own day-phase mapping, and every outcome must be decided by a readback of
-- GetActiveLoadoutIndex rather than by the void SetActiveLoadout call.

local path = assert(arg[1], "Supply EquipmentLoadoutControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function alwaysValid() return true end

-- Minimal menu double recording what the control publishes.
local function menuDouble()
    local menu = { labels = {}, values = {}, options = {}, sections = {} }
    function menu.Register(section) menu.sections[section.id] = section end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set(_, itemId, value) menu.values[itemId] = value end
    function menu.SetOptions(_, itemId, options) menu.options[itemId] = options end
    function menu.Get(_, itemId) return menu.values[itemId] end
    function menu.click(itemId)
        for _, item in ipairs(menu.sections.DWLoadout.items) do
            if item.id == itemId and item.onClick then return item.onClick() end
        end
        error("no such control: " .. itemId)
    end
    return menu
end

-- world.active is the authoritative loadout the readback reports.
local function fixture(overrides)
    overrides = overrides or {}
    local world = {
        active = overrides.active or 1,
        inCombat = overrides.inCombat or false,
        -- Day phase 1 -> loadout 1, night phase 2 -> loadout 2, unless overridden.
        phaseToIndex = overrides.phaseToIndex or { [1] = 1, [2] = 2 },
        indexToPhase = overrides.indexToPhase or { [1] = 1, [2] = 2 },
        setCalls = {},
        acceptSet = overrides.acceptSet ~= false,
    }

    local inventory = {
        IsValid = alwaysValid,
        IsA = function(_, class) return class == "/Script/DogwoodInventory.InventoryComponent" end,
        GetAddress = function() return 0x1000 end,
        GetActiveLoadoutIndex = function() return world.active end,
        SetActiveLoadout = function(_, index)
            world.setCalls[#world.setCalls + 1] = index
            if world.acceptSet then world.active = index end
        end,
    }
    local player = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x1 end,
        GetWorld = function() return { IsValid = alwaysValid, GetAddress = function() return 0x2 end } end,
        InventoryComponent = inventory,
    }
    player.Controller = { IsValid = alwaysValid, GetAddress = function() return 0x3 end, Pawn = player }

    local library = {
        IsValid = alwaysValid,
        GetLoadoutIndexFromDayPhase = function(_, phase) return world.phaseToIndex[phase] end,
        GetLoadoutDayPhaseFromIndex = function(_, index) return world.indexToPhase[index] end,
    }
    local combat = {
        IsValid = alwaysValid,
        GetFullName = function() return "CombatSubsystem /Game/World.Combat" end,
        GetIsInCombat = function() return world.inCombat end,
    }

    local environment = setmetatable({
        StaticFindObject = function(objectPath)
            if objectPath:find("InventoryBlueprintFunctionLibrary", 1, true) then return library end
            return nil
        end,
        FindFirstOf = function(name)
            if name == "CombatSubsystem" then return combat end
            return nil
        end,
        print = function() end,
    }, { __index = _G })

    local module = assert(loadfile(path, "t", environment))()
    local menu = menuDouble()
    module.Init(menu, { GetPlayer = function() return player end })
    return menu, world, module
end

test("roster comes from the game's day-phase mapping", function()
    local menu, world = fixture()
    menu.click("refresh")
    local options = menu.options.target
    assert(#options == 2, "expected both day-phase loadouts, got " .. #options)
    assert(options[1].label == "Day" and options[1].value == world.phaseToIndex[1], "day loadout mismatch")
    assert(options[2].label == "Night" and options[2].value == world.phaseToIndex[2], "night loadout mismatch")
end)

test("indices that do not round-trip are not offered", function()
    -- The engine reports a night index whose reverse lookup disagrees.
    local menu = fixture({ indexToPhase = { [1] = 1, [2] = 1 } })
    menu.click("refresh")
    assert(#menu.options.target == 1, "a non round-tripping index must be dropped")
    assert(menu.options.target[1].label == "Day")
end)

test("an empty roster refuses instead of guessing an index", function()
    local menu = fixture({ phaseToIndex = {}, indexToPhase = {} })
    local ok = pcall(function() menu.click("refresh") end)
    assert(not ok, "an empty loadout roster must not succeed")
    assert(menu.labels.status:find("Unavailable", 1, true), "the failure must be shown to the user")
end)

test("switching is verified by reading the index back", function()
    local menu, world = fixture({ active = 1 })
    menu.click("refresh")
    menu.values.target = 2
    menu.click("apply")
    assert(#world.setCalls == 1 and world.setCalls[1] == 2, "expected one SetActiveLoadout(2)")
    assert(menu.labels.status:find("Verified", 1, true), "a verified switch must say so")
    assert(menu.values.owned == true, "switching away from the original must flag ownership")
end)

test("a refused switch is reported, not claimed as success", function()
    local menu, world = fixture({ active = 1, acceptSet = false })
    menu.click("refresh")
    menu.values.target = 2
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok, "a readback mismatch must not be treated as success")
    assert(#world.setCalls == 1, "the switch must be attempted exactly once")
    assert(menu.labels.status:find("refused", 1, true), "the refusal must be explained")
    assert(not menu.labels.status:find("Verified", 1, true), "a refused switch must never say Verified")
end)

test("restore returns to the loadout observed at the first read", function()
    local menu, world = fixture({ active = 1 })
    menu.click("refresh")
    menu.values.target = 2
    menu.click("apply")
    assert(world.active == 2)
    menu.click("restore")
    assert(world.active == 1, "restore must put the original loadout back")
    assert(menu.labels.status:find("Restored", 1, true), "restore must be reported")
    assert(menu.values.owned == false, "restoring must clear the ownership flag")
end)

test("restore before any read refuses rather than guessing a baseline", function()
    local menu, world = fixture({ active = 2 })
    local ok = pcall(function() menu.click("restore") end)
    assert(not ok, "restore without a recorded baseline must fail")
    assert(#world.setCalls == 0, "no loadout may be written without a baseline")
end)

test("combat blocks the switch before anything is written", function()
    local menu, world = fixture({ active = 1, inCombat = true })
    menu.click("refresh")
    menu.values.target = 2
    local ok = pcall(function() menu.click("apply") end)
    assert(not ok, "switching during combat must fail")
    assert(#world.setCalls == 0, "no loadout may be written during combat")
end)

test("selecting the already active loadout writes nothing", function()
    local menu, world = fixture({ active = 1 })
    menu.click("refresh")
    menu.values.target = 1
    menu.click("apply")
    assert(#world.setCalls == 0, "an unchanged selection must not call SetActiveLoadout")
    assert(menu.labels.status:find("already active", 1, true))
end)

test("a new session forgets the previous save's baseline", function()
    local menu, world, module = fixture({ active = 1 })
    menu.click("refresh")
    menu.values.target = 2
    menu.click("apply")
    module.ResetSession()
    local ok = pcall(function() menu.click("restore") end)
    assert(not ok, "a reset session must not restore into a different save")
    assert(#world.setCalls == 1, "no extra loadout write may happen after a session reset")
end)

print(count .. " Equipment loadout tests passed")
