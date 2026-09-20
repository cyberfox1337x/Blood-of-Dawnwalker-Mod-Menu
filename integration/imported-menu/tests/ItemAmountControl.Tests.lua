local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("item_amount_control_tests")

-- Covers Scripts/ItemAmountControl.lua with a fake inventory that keeps stacks per asset:
-- the owned list, Set amount up and down with readback, refusal of bad amounts, the
-- Unlimited Consumables refund after a UseItem, its consumables-only scope, and the
-- session reset. Handle bridges are modelled the way the game answers: the function's
-- return hook fires with a native-looking handle while the call is on the stack.
-- usage: lua ItemAmountControl.Tests.lua <path to Scripts/ItemAmountControl.lua>

local path = assert(arg[1], "Supply ItemAmountControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local ITEM_BASE = "/Script/DogwoodInventory.ItemBaseDataAsset"
local CONSUMABLE = "/Script/DogwoodInventory.ItemConsumableDataAsset"

local function fixture(options)
    options = options or {}
    -- The item base class object the module resolves once, and the assets under it.
    local baseClass = { IsValid = function() return true end }
    local assets = {}
    local function asset(name, display, consumable)
        local object = {
            path = "/Game/_Dawnwalker/Inventory/Items/" .. name .. "." .. name,
            IsValid = function() return true end,
            GetFullName = function() return (consumable and "ItemConsumableDataAsset " or "ItemClothingDataAsset ") .. "/Game/_Dawnwalker/Inventory/Items/" .. name .. "." .. name end,
            GetFName = function() return { ToString = function() return name end } end,
            GetItemName = function() return { ToString = function() return display end } end,
            IsAnyClass = function() return false end,
        }
        object.IsA = function(_, class) return class == ITEM_BASE or class == baseClass or (consumable and class == CONSUMABLE) end
        assets[object.path] = object
        return object
    end
    local ointment = asset("ITM_Consumable_Medicaments1", "Minor Mending Ointment", true)
    local loafers = asset("ITM_Clothing_GreyLoafers", "Grey Loafers", false)
    local bread = asset("ITM_Consumable_Food2", "Bread", true)
    local stacks = { [ointment.path] = 3, [loafers.path] = 1 }

    -- Handles are opaque userdata in the game (the module insists on userdata); a temp file
    -- handle stands in, mapped back to its asset path.
    local hooks = {}
    local handleAsset = setmetatable({}, { __mode = "k" })
    local function handleFor(assetObject) local handle = io.tmpfile(); handleAsset[handle] = assetObject.path; return handle end
    local function assetOf(handle) return handleAsset[handle] end
    local inventoryComponent = { IsValid = function() return true end, IsA = function(_, class) return class == "/Script/DogwoodInventory.InventoryComponent" end }
    function inventoryComponent.GetHandleForAssetInInventory(_, assetObject)
        local hook = hooks["/Script/DogwoodInventory.InventoryComponent:GetHandleForAssetInInventory"]
        if hook then hook.post(nil, { get = function() return handleFor(assetObject) end }) end
    end
    function inventoryComponent.GetItemQuantity(_, handle) return stacks[assetOf(handle)] or 0 end
    function inventoryComponent.TryAddItem(_, handle, amount)
        if options.addFails then return 5 end
        stacks[assetOf(handle)] = (stacks[assetOf(handle)] or 0) + amount; return 1
    end
    function inventoryComponent.RemoveItem(_, handle, amount)
        local have = stacks[assetOf(handle)] or 0
        if amount > have then return 4 end
        stacks[assetOf(handle)] = have - amount; return 1
    end
    function inventoryComponent.GetAddress() return 1 end
    local player = { IsValid = function() return true end, GetInventoryComponent = function() return inventoryComponent end }
    local library = { IsValid = function() return true end }
    function library.GetItemHandle(_, _, assetObject)
        local hook = hooks["/Script/DogwoodInventory.InventoryBlueprintFunctionLibrary:GetItemHandle"]
        if hook then hook.post(nil, { get = function() return handleFor(assetObject) end }) end
    end

    -- Globals the module reaches for.
    StaticFindObject = function(objectPath)
        if objectPath == "/Script/DogwoodInventory.Default__InventoryBlueprintFunctionLibrary" then return library end
        if objectPath == ITEM_BASE then return baseClass end
        return assets[objectPath]
    end
    ForEachUObject = function(callback) for _, object in pairs(assets) do callback(object) end end
    ExecuteInGameThread = function(callback) callback() end
    local delayed = {}
    ExecuteWithDelay = function(_, callback) delayed[#delayed + 1] = callback; return #delayed end
    CancelDelayedAction = function() end

    local menu = { labels = {}, values = { amount = 1 }, options = {}, sections = {} }
    function menu.Register(section) menu.sections[section.id] = section; for _, item in ipairs(section.items) do if item.type == "label" and item.id then menu.labels[item.id] = item.label end end end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set(_, itemId, value) menu.values[itemId] = value end
    function menu.SetOptions(_, itemId, list, current) menu.options[itemId] = list; menu.values[itemId] = current end
    function menu.Get(_, itemId) return menu.values[itemId] end
    local function item(itemId)
        for _, entry in ipairs(menu.sections.DWItemAmount.items) do
            if entry.id == itemId then return entry end
            for _, child in ipairs(entry.items or {}) do if child.id == itemId then return child end end
        end
        error("no control " .. itemId)
    end

    local module = assert(loadfile(path))().Init(menu, { GetPlayer = function() return player end }, {
        registerHook = function(functionPath, pre, post) hooks[functionPath] = { pre = pre, post = post }; return #hooks, #hooks end,
    })
    local function useItem(assetObject, consumed)
        local hook = hooks["/Script/DogwoodInventory.InventoryComponent:UseItem"]
        local context = { get = function() return inventoryComponent end }
        hook.pre(context)
        stacks[assetObject.path] = math.max(0, (stacks[assetObject.path] or 0) - consumed)
        hook.post(context)
    end
    return { menu = menu, module = module, stacks = stacks, ointment = ointment, loafers = loafers, bread = bread, hooks = hooks,
        select = function(assetObject) item("item").onChange(assetObject.path) end,
        setAmount = function(value) menu.values.amount = value end,
        apply = function() item("apply").onClick() end,
        refresh = function() item("refresh").onClick() end,
        unlimited = function(value) item("unlimitedConsumables").onChange(value) end,
        useItem = useItem, delayed = delayed }
end

test("the owned list shows only owned stacks, sorted, with counts", function()
    local f = fixture(); f.refresh()
    local labels = {}
    for _, option in ipairs(f.menu.options.item) do labels[#labels + 1] = option.label end
    assert(table.concat(labels, "|") == "Grey Loafers  x1|Minor Mending Ointment  x3", table.concat(labels, "|"))
    assert(f.menu.labels.status == "Inventory list refreshed.", f.menu.labels.status)
end)

test("SessionReady fills the list itself and errors while the inventory is still empty", function()
    local f = fixture()
    for key in pairs(f.stacks) do f.stacks[key] = 0 end
    assert(not pcall(f.module.SessionReady), "an empty inventory must make the runner retry")
    f.stacks[f.loafers.path] = 1
    f.module.SessionReady()
    assert(#f.menu.options.item == 1 and f.menu.options.item[1].label == "Grey Loafers  x1")
    assert(#f.delayed == 1, "one delayed refresh is scheduled")
end)

test("Set amount raises a stack with the add call and reads it back", function()
    local f = fixture(); f.refresh(); f.select(f.loafers); f.setAmount(3); f.apply()
    assert(f.stacks[f.loafers.path] == 3)
    assert(f.menu.labels.status == "Verified: Grey Loafers is now x3 (was x1).", f.menu.labels.status)
end)

test("Set amount lowers a stack with the remove call", function()
    local f = fixture(); f.refresh(); f.select(f.ointment); f.setAmount(1); f.apply()
    assert(f.stacks[f.ointment.path] == 1 and f.menu.labels.status:find("now x1 %(was x3%)"), f.menu.labels.status)
end)

test("a refused add is reported with the game's own result, never as success", function()
    local f = fixture({ addFails = true }); f.refresh(); f.select(f.loafers); f.setAmount(5); f.apply()
    assert(f.stacks[f.loafers.path] == 1)
    assert(f.menu.labels.status:find("went x1 %-> x1, not x5: not enough space"), f.menu.labels.status)
end)

test("bad amounts and a missing selection are refused before any inventory call", function()
    local f = fixture(); f.refresh()
    f.setAmount(2); f.apply()
    assert(f.menu.labels.status == "Choose an owned item first.", f.menu.labels.status)
    f.select(f.loafers)
    for _, bad in ipairs({ -1, 1000, 2.5, "abc" }) do
        f.setAmount(bad); f.apply()
        assert(f.menu.labels.status:find("whole number from 0 to 999", 1, true), tostring(bad) .. " → " .. f.menu.labels.status)
    end
    assert(f.stacks[f.loafers.path] == 1)
end)

test("Unlimited Consumables refunds exactly what a use took", function()
    local f = fixture(); f.refresh(); f.unlimited(true)
    assert(f.menu.labels.status:find("Unlimited Consumables ON", 1, true), f.menu.labels.status)
    f.useItem(f.ointment, 1)
    assert(f.stacks[f.ointment.path] == 3, "stack must be back to 3")
    assert(f.menu.labels.status:find("Minor Mending Ointment used, x1 refunded %(x2 %-> x3%)"), f.menu.labels.status)
end)

test("Unlimited Consumables leaves non-consumables alone and does nothing while OFF", function()
    local f = fixture(); f.refresh(); f.unlimited(true)
    f.useItem(f.loafers, 1)
    assert(f.stacks[f.loafers.path] == 0, "clothing is never refunded")
    f.unlimited(false)
    f.useItem(f.ointment, 1)
    assert(f.stacks[f.ointment.path] == 2, "OFF must not refund")
end)

test("a refund re-creates a stack that was used to zero", function()
    local f = fixture(); f.refresh(); f.unlimited(true)
    f.stacks[f.ointment.path] = 1; f.refresh()
    f.useItem(f.ointment, 1)
    assert(f.stacks[f.ointment.path] == 1 and f.menu.labels.status:find("x1 refunded %(x0 %-> x1%)"), f.menu.labels.status)
end)

test("ResetSession drops the selection and catalog so a new save is rescanned", function()
    local f = fixture(); f.refresh(); f.select(f.loafers)
    f.module.ResetSession()
    f.stacks[f.bread.path] = 2
    f.refresh()
    local labels = {}
    for _, option in ipairs(f.menu.options.item) do labels[#labels + 1] = option.label end
    assert(table.concat(labels, "|") == "Bread  x2|Grey Loafers  x1|Minor Mending Ointment  x3", table.concat(labels, "|"))
end)

print(string.format("%d/%d item-amount tests passed", count, count))
