local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("quickslot_assign_tests")

-- Covers the Quickslots panel in Source/GameplayMenu.lua.
--
-- SetItemInSlot returns nothing, so the assignment is proved by asking the game which
-- slot now holds the item (GetItemQuickslot, whose Result is a plain enum out
-- parameter). The panel must also refuse to bind a slot to an item the player does not
-- own, and must honour the game's own CanSetItemInQuickslot gate.
--
-- The inventory double below models the real GetItemQuantity contract:
--   int32 GetItemQuantity(const FItemHandle& Item, bool bMatchAssetOnly)
-- A handle minted by GetItemHandle has a fresh instance identity, so an exact-handle
-- match (bMatchAssetOnly=false) reports 0 even for an item the player is carrying.
-- Passing false there is the bug this suite pins; it made the assign always refuse.

local root = assert(arg[1]) .. "/Mods/DawnwalkerImportedMenu/Scripts/"
local Facade = assert(loadfile(root .. "ImportedMenuFacade.lua"))()

local ITEMS, QUICKSLOTS = "DWItems", "DWQuickslots"
local ITEM_PATH = "/Game/_Dawnwalker/Inventory/Items/ITM_Weapon_Test.ITM_Weapon_Test"
local NATIVE_HANDLE = io.stdout -- a real userdata; the bridge rejects anything else

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function alwaysValid() return true end

local function fixture(overrides)
    overrides = overrides or {}
    local menu = Facade.New()
    local world = {
        owned = overrides.owned == nil and 1 or overrides.owned,
        slotContents = {},
        writes = {},
        quantityCalls = {},
        canSet = overrides.canSet ~= false,
        placeSucceeds = overrides.placeSucceeds ~= false,
        log = {},
    }

    local inventory = {
        IsValid = alwaysValid,
        GetFullName = function() return "InventoryComponent /Game/World.Player.Inventory" end,
        -- Only an asset match can see a stack the player already owns; an exact
        -- handle match against a freshly minted handle is always 0, as in game.
        GetItemQuantity = function(_, handle, matchAssetOnly)
            world.quantityCalls[#world.quantityCalls + 1] =
                { handle = handle, matchAssetOnly = matchAssetOnly }
            if matchAssetOnly ~= true then return 0 end
            return world.owned
        end,
        GetActiveLoadoutIndex = function() return 0 end,
        IsItemEquipped = function() return false end,
        GetValidEquipmentSlotsForItem = function() return {} end,
        TryAddItem = function() return 1 end,
        TryAddAndEquipItem = function() return 1 end,
    }
    local playerClass = { IsValid = alwaysValid }
    local player = {
        IsValid = alwaysValid,
        InventoryComponent = inventory,
        GetFullName = function() return "DawnwalkerPlayerCharacter /Game/World.Player" end,
        GetWorld = function() return { IsValid = alwaysValid } end,
        IsA = function(_, class) return class == playerClass end,
    }
    local asset = {
        IsValid = alwaysValid,
        HasItemLevel = function() return true end,
        GetItemName = function() return { ToString = function() return "Test Blade" end } end,
        GetFName = function() return { ToString = function() return "TestBlade" end } end,
    }

    local hooks = {}
    local library = {
        IsValid = alwaysValid,
        MakeInvalidItemHandle = function() return "invalid" end,
        EqualEqual_ItemHandleItemHandle = function(_, left, right)
            if left == "invalid" or right == "invalid" then return left == right end
            return left == right
        end,
        GetItemHandle = function()
            local post = hooks["/Script/DogwoodInventory.InventoryBlueprintFunctionLibrary:GetItemHandle"]
            assert(post, "GetItemHandle hook was never registered")
            post(nil, { get = function() return NATIVE_HANDLE end })
        end,
    }
    local quickslotSubsystem = {
        IsValid = alwaysValid,
        GetFullName = function() return "InventoryQuickslotSubsystem /Game/World.Quickslots" end,
        GetItemInSlot = function(_, slot) return world.slotContents[slot] or "invalid" end,
        CanSetItemInQuickslot = function(_, _handle, _presetId) return world.canSet end,
        SetItemInSlot = function(_, slot, handle, presetId)
            world.writes[#world.writes + 1] = { slot = slot, handle = handle, presetId = presetId }
            if world.placeSucceeds then world.slotContents[slot] = handle end
        end,
        -- Fills the Result out parameter with the slot holding this handle, exactly
        -- as the native signature does, and returns whether it found one at all.
        GetItemQuickslot = function(_, handle, result, _presetId)
            for slot, contents in pairs(world.slotContents) do
                if contents == handle then result.Result = slot; return true end
            end
            return false
        end,
    }

    local environment
    local loaded = {}
    environment = setmetatable({
        __IMPORT_DIRECTORY = "C:/nonexistent-test-directory/",
        require = function(name)
            if name == "ModMenu.ModMenu" then return menu end
            if name == "UEHelpers.UEHelpers" then
                return { GetPlayer = function() return player end,
                    GetGameStateBase = function() return { IsValid = alwaysValid } end }
            end
            if not loaded[name] then
                loaded[name] = assert(loadfile(root .. "Source/" .. name .. ".lua", "t", environment))()
            end
            return loaded[name]
        end,
        StaticFindObject = function(path)
            if path:find("InventoryBlueprintFunctionLibrary", 1, true) then return library end
            if path:find("DawnwalkerPlayerCharacter", 1, true) then return playerClass end
            if path == ITEM_PATH then return asset end
            return nil
        end,
        FindFirstOf = function(name)
            if name == "InventoryQuickslotSubsystem" then return quickslotSubsystem end
            if name == "CombatSubsystem" then
                return { IsValid = alwaysValid,
                    GetFullName = function() return "CombatSubsystem /Game/World.Combat" end,
                    GetIsInCombat = function() return false end }
            end
            return nil
        end,
        ExecuteInGameThread = function(callback) callback() end,
        ExecuteWithDelay = function(_, callback) callback() end,
        RegisterHook = function(path, _pre, post) hooks[path] = post end,
        ForEachUObject = function() end,
        RegisterKeyBind = function() end,
        IsKeyBindRegistered = function() return false end,
        print = function(text) world.log[#world.log + 1] = tostring(text) end,
    }, { __index = _G })

    assert(loadfile(root .. "Source/GameplayMenu.lua", "t", environment))()
    menu.Session("test-session", true)
    return menu, world
end

local requestCounter = 0
local function dispatch(menu, section, item, action, value, valueType)
    requestCounter = requestCounter + 1
    menu.Dispatch({ request_id = "r" .. requestCounter, session_id = "test-session",
        action = action or "invoke", section_id = section, item_id = item,
        value = value, value_type = valueType })
end

local function selectItem(menu)
    menu.SetOptions(ITEMS, "item", { { label = "Test Blade", value = ITEM_PATH } }, false)
    dispatch(menu, ITEMS, "item", "set", ITEM_PATH, "string")
end

local function slotStatus(menu)
    for _, section in ipairs(menu.Snapshot().sections) do
        if section.id == QUICKSLOTS then
            for _, item in ipairs(section.items) do
                if item.id == "slotStatus" then return item.label end
            end
        end
    end
    return nil
end

test("the panel offers exactly the four real quickslots", function()
    local menu = fixture()
    for _, section in ipairs(menu.Snapshot().sections) do
        if section.id == QUICKSLOTS then
            for _, item in ipairs(section.items) do
                if item.id == "slot" then
                    assert(#item.options == 4, "expected 4 slots, got " .. #item.options)
                    assert(item.options[1].label == "Left" and item.options[1].value == 0)
                    assert(item.options[4].label == "Bottom" and item.options[4].value == 3)
                end
            end
        end
    end
end)

test("assigning with no item selected asks for one and writes nothing", function()
    local menu, world = fixture()
    dispatch(menu, QUICKSLOTS, "assign")
    assert(#world.writes == 0)
    assert(slotStatus(menu):find("Choose an item", 1, true), slotStatus(menu))
end)

test("an unowned item is refused before the slot is written", function()
    local menu, world = fixture({ owned = 0 })
    selectItem(menu)
    dispatch(menu, QUICKSLOTS, "assign")
    assert(#world.writes == 0, "a slot must not be bound to an unowned item")
    assert(slotStatus(menu):find("do not own", 1, true), slotStatus(menu))
end)

test("an owned item is assigned and verified by reading the slot back", function()
    local menu, world = fixture({ owned = 2 })
    selectItem(menu)
    dispatch(menu, QUICKSLOTS, "assign")
    assert(#world.writes == 1, "expected exactly one SetItemInSlot call")
    local write = world.writes[1]
    assert(write.slot == 0, "the default slot is Left (0)")
    assert(write.handle == NATIVE_HANDLE, "the native handle must be forwarded")
    assert(write.presetId == 0, "preset 0 must be passed explicitly")
    assert(slotStatus(menu):find("Verified", 1, true), slotStatus(menu))
end)

test("ownership is asked of the asset, not of the freshly minted handle", function()
    -- The regression: GetItemQuantity(handle, false) matches the exact handle, which a
    -- new handle never satisfies, so the assign refused every item the player owned.
    local menu, world = fixture({ owned = 3 })
    selectItem(menu)
    dispatch(menu, QUICKSLOTS, "assign")
    assert(#world.quantityCalls >= 1, "the ownership pre-check must run")
    assert(world.quantityCalls[1].matchAssetOnly == true,
        "bMatchAssetOnly must be true or an owned item reads as unowned")
    assert(slotStatus(menu):find("Verified", 1, true), slotStatus(menu))
end)

test("the game's own quickslot gate is honoured", function()
    local menu, world = fixture({ owned = 1, canSet = false })
    selectItem(menu)
    dispatch(menu, QUICKSLOTS, "assign")
    assert(#world.writes == 0, "nothing may be written once the game refuses the item")
    assert(slotStatus(menu):find("will not accept", 1, true), slotStatus(menu))
end)

test("choosing a different slot targets that slot", function()
    local menu, world = fixture({ owned = 1 })
    selectItem(menu)
    dispatch(menu, QUICKSLOTS, "slot", "set", 2, "number")
    dispatch(menu, QUICKSLOTS, "assign")
    assert(world.writes[1].slot == 2, "expected the Right slot, got " .. tostring(world.writes[1].slot))
    assert(slotStatus(menu):find("Right", 1, true), slotStatus(menu))
end)

test("a slot the game did not fill is reported, not claimed as success", function()
    local menu, world = fixture({ owned = 1, placeSucceeds = false })
    selectItem(menu)
    dispatch(menu, QUICKSLOTS, "assign")
    assert(#world.writes == 1)
    assert(slotStatus(menu):find("did not put", 1, true), slotStatus(menu))
    assert(not slotStatus(menu):find("Verified", 1, true), "must not claim Verified without a matching readback")
end)

test("reading an empty slot says so", function()
    local menu = fixture()
    dispatch(menu, QUICKSLOTS, "read")
    assert(slotStatus(menu):find("is empty", 1, true), slotStatus(menu))
end)

test("reading a filled slot says so", function()
    local menu, world = fixture({ owned = 1 })
    selectItem(menu)
    dispatch(menu, QUICKSLOTS, "assign")
    dispatch(menu, QUICKSLOTS, "read")
    assert(slotStatus(menu):find("holds an item", 1, true), slotStatus(menu))
end)

print(count .. " Quickslot tests passed")
