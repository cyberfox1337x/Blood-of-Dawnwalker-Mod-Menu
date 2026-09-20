local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("imported_give_and_equip_tests")

-- Covers the "Give and equip selected item" control in Source/GameplayMenu.lua.
-- The native ItemHandle is opaque userdata, so the fixture drives the same
-- GetItemHandle return-hook bridge the live mod uses and substitutes a real Lua
-- userdata value for the handle.

local root = assert(arg[1]) .. "/Mods/DawnwalkerImportedMenu/Scripts/"
local Facade = assert(loadfile(root .. "ImportedMenuFacade.lua"))()

local ITEMS = "DWItems"
local ITEM_PATH = "/Game/Items/Weapons/TestBlade.TestBlade"

-- A genuine userdata value; the bridge rejects anything else as an empty handle.
local NATIVE_HANDLE = io.stdout

local function alwaysValid() return true end

-- Build a fully stubbed game world. "world" collects the observable state the
-- control is supposed to read and change, so assertions inspect it directly.
local function fixture(overrides)
    overrides = overrides or {}
    local menu = Facade.New()
    local world = {
        quantity = overrides.quantity or 0,
        equipped = overrides.equipped or false,
        inCombat = overrides.inCombat or false,
        slotCount = overrides.slotCount,
        result = overrides.result or 1,
        equipCalls = 0,
        addCalls = 0,
        log = {},
    }
    if world.slotCount == nil then world.slotCount = 1 end

    local inventory
    inventory = {
        IsValid = alwaysValid,
        GetFullName = function() return "InventoryComponent /Game/World.Player.Inventory" end,
        GetActiveLoadoutIndex = function() return 0 end,
        GetItemQuantity = function() return world.quantity end,
        IsItemEquipped = function() return world.equipped end,
        GetValidEquipmentSlotsForItem = function()
            if world.slotCount == "error" then error("slot roster unavailable") end
            local slots = {}
            for index = 1, world.slotCount do slots[index] = index end
            return slots
        end,
        TryAddAndEquipItem = function(_, handle, skipNewItemCheck)
            world.equipCalls = world.equipCalls + 1
            world.receivedHandle = handle
            world.receivedSkipFlag = skipNewItemCheck
            if overrides.onEquip then overrides.onEquip(world) end
            return world.result
        end,
        TryAddItem = function() world.addCalls = world.addCalls + 1; return 1 end,
    }

    local playerClass = { IsValid = alwaysValid, name = "DawnwalkerPlayerCharacter" }
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
    local library
    library = {
        IsValid = alwaysValid,
        MakeInvalidItemHandle = function() return "invalid" end,
        EqualEqual_ItemHandleItemHandle = function(_, left) return left == "invalid" end,
        GetItemHandle = function()
            local post = hooks["/Script/DogwoodInventory.InventoryBlueprintFunctionLibrary:GetItemHandle"]
            if not post then error("GetItemHandle hook was never registered") end
            post(nil, { get = function() return NATIVE_HANDLE end })
        end,
    }

    local combat = {
        IsValid = alwaysValid,
        GetFullName = function() return "CombatSubsystem /Game/World.Combat" end,
        GetIsInCombat = function() return world.inCombat end,
    }

    local environment
    local loadedModules = {}
    environment = setmetatable({
        __IMPORT_DIRECTORY = "C:/nonexistent-test-directory/",
        -- Mirrors ImportedSourceLoader: sibling Source modules resolve by name, so
        -- GameplayMenu registers alongside the same companions as in the live mod.
        require = function(name)
            if name == "ModMenu.ModMenu" then return menu end
            if name == "UEHelpers.UEHelpers" then
                return { GetPlayer = function() return player end,
                    GetGameStateBase = function() return { IsValid = alwaysValid } end }
            end
            if not loadedModules[name] then
                loadedModules[name] = assert(loadfile(root .. "Source/" .. name .. ".lua", "t", environment))()
            end
            return loadedModules[name]
        end,
        StaticFindObject = function(path)
            if path:find("InventoryBlueprintFunctionLibrary", 1, true) then return library end
            if path:find("DawnwalkerPlayerCharacter", 1, true) then return playerClass end
            if path == ITEM_PATH then return asset end
            return nil
        end,
        FindFirstOf = function(name)
            if name == "CombatSubsystem" then return combat end
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

-- Select the test item, then press "Give and equip selected item".
local function pressGiveAndEquip(menu, requestSuffix)
    menu.SetOptions(ITEMS, "item", { { label = "Test Blade", value = ITEM_PATH } }, false)
    menu.Dispatch({ request_id = "select" .. requestSuffix, session_id = "test-session",
        action = "set", section_id = ITEMS, item_id = "item", value = ITEM_PATH })
    menu.Dispatch({ request_id = "equip" .. requestSuffix, session_id = "test-session",
        action = "invoke", section_id = ITEMS, item_id = "giveEquip" })
end

local function statusLabel(menu)
    for _, section in ipairs(menu.Snapshot().sections) do
        if section.id == ITEMS then
            for _, item in ipairs(section.items) do
                if item.id == "actionStatus" then return item.label end
            end
        end
    end
    return nil
end

do
    local menu, world = fixture({
        quantity = 0, equipped = false,
        onEquip = function(state) state.quantity = 1; state.equipped = true end,
    })
    pressGiveAndEquip(menu, "1")
    assert(world.equipCalls == 1, "Expected exactly one TryAddAndEquipItem call")
    assert(world.receivedHandle == NATIVE_HANDLE, "Native ItemHandle userdata was not forwarded")
    assert(world.receivedSkipFlag == false, "bSkipNewItemCheck must be passed explicitly as false")
    local status = statusLabel(menu)
    assert(status:find("Verified", 1, true) and status:find("equipped", 1, true),
        "Successful equip must report a verified readback, got: " .. tostring(status))
    print("PASS give and equip reports a verified equip after readback")
end

do
    -- The game refuses equipment changes during combat; refuse before mutating.
    local menu, world = fixture({ inCombat = true })
    pressGiveAndEquip(menu, "2")
    assert(world.equipCalls == 0, "Must not call the native equip while in combat")
    assert(statusLabel(menu):find("combat", 1, true), "Combat refusal must be explained")
    print("PASS give and equip refuses to mutate the inventory during combat")
end

do
    -- Materials and other non-equipment have no valid slot; say so instead of failing.
    local menu, world = fixture({ slotCount = 0 })
    pressGiveAndEquip(menu, "3")
    assert(world.equipCalls == 0, "Must not attempt to equip an item with no equipment slot")
    assert(statusLabel(menu):find("no equipment slot", 1, true), "Unequippable item must be explained")
    print("PASS give and equip blocks items that have no equipment slot")
end

do
    -- An unreadable slot roster must not block a legitimate item.
    local menu, world = fixture({
        slotCount = "error",
        onEquip = function(state) state.quantity = 1; state.equipped = true end,
    })
    pressGiveAndEquip(menu, "4")
    assert(world.equipCalls == 1, "Unreadable slot roster must fall through to the native call")
    print("PASS give and equip continues when the slot roster cannot be read")
end

do
    -- Item added but the game declined the equip: report the real reason.
    local menu, world = fixture({
        result = 14,
        onEquip = function(state) state.quantity = 1 end,
    })
    pressGiveAndEquip(menu, "5")
    local status = statusLabel(menu)
    assert(status:find("did not equip", 1, true) and status:find("locked", 1, true),
        "A declined equip must report the EInventoryResult reason, got: " .. tostring(status))
    print("PASS give and equip explains a declined equip using the result enum")
end

do
    -- Nothing changed at all: surface the native result rather than a false success.
    local menu = fixture({ result = 5 })
    pressGiveAndEquip(menu, "6")
    assert(statusLabel(menu):find("Not enough space", 1, true),
        "An unchanged inventory must surface the native failure reason")
    print("PASS give and equip reports the native failure when nothing changed")
end

do
    -- Already-equipped item must not be reported as a fresh success.
    local menu = fixture({ quantity = 1, equipped = true, result = 1 })
    pressGiveAndEquip(menu, "7")
    assert(statusLabel(menu):find("already equipped", 1, true),
        "An already-equipped item must be reported as unchanged")
    print("PASS give and equip reports an already-equipped item as unchanged")
end

print("ALL GiveAndEquip tests passed")
