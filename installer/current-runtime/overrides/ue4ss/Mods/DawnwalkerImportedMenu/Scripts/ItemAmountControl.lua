local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("item_amount_control")

-- Edit Item Amount and Unlimited Consumables, on the player's own inventory component.
--
-- Listing what the player owns: the component's `GetCurrentItems()` and `InventoryItems`
-- map come back empty through the Lua bridge (measured live 2026-09-17; the stacks live
-- in the InventorySubsystem), so ownership is established per asset: ask the component
-- for the owned instance handle (`GetHandleForAssetInInventory`) and count it with
-- `GetItemQuantity`. Handles have no reflected fields, so each one is consumed inside the
-- function's own return hook, exactly as the live Give control does. Measured live:
-- owned handle f=1/t=1, minted handle t=1, HasItem sweep finds all five owned stacks.
--
-- Edit Item Amount sets an owned stack to an exact count with the two reflected calls the
-- inventory exposes: `TryAddItem(handle, n, true)` to raise, `RemoveItem(handle, n)` to
-- lower, using the exact owned instance handle from `GetHandleForAssetInInventory` (also
-- consumed in its return hook). Every write is read back and reported before -> after.
--
-- Unlimited Consumables hooks `InventoryComponent:UseItem`: the pre-hook records the
-- player's consumable counts, the post-hook puts back exactly what the use took. Only
-- `ItemConsumableDataAsset` items (food, draughts, ointments) qualify; manuals,
-- readables, keys and quest items are never touched.

local M = {}

local INVENTORY_PATH = "/Script/DogwoodInventory.InventoryComponent"
local ITEM_BASE_PATH = "/Script/DogwoodInventory.ItemBaseDataAsset"
local CONSUMABLE_PATH = "/Script/DogwoodInventory.ItemConsumableDataAsset"
local LIBRARY_PATH = "/Script/DogwoodInventory.Default__InventoryBlueprintFunctionLibrary"
local HANDLE_FUNCTION = "/Script/DogwoodInventory.InventoryBlueprintFunctionLibrary:GetItemHandle"
local OWNED_HANDLE_FUNCTION = "/Script/DogwoodInventory.InventoryComponent:GetHandleForAssetInInventory"
local USE_FUNCTION = "/Script/DogwoodInventory.InventoryComponent:UseItem"
local MAX_AMOUNT = 999
local MAX_CATALOG = 4096

local RESULTS = {
    [0] = "no result reported", [1] = "success reported", [2] = "failure", [3] = "item not found",
    [4] = "not enough items", [5] = "not enough space", [6] = "not enough currency", [12] = "quantity limit reached",
}

local function valid(object) return object ~= nil and object:IsValid() end

local function displayName(asset)
    local ok, name = pcall(function() return asset:GetItemName():ToString() end)
    if ok and type(name) == "string" and name ~= "" and not name:find("<MISSING", 1, true) then return name end
    local raw = asset:GetFName():ToString():gsub("^ITM_[A-Za-z]+_", "")
    return (raw:gsub("_", " "):gsub("(%l)(%u)", "%1 %2"))
end

function M.Init(menu, helpers, deps)
    deps = deps or {}
    local registerHook = assert(deps.registerHook, "ItemAmountControl needs the native RegisterHook")
    local id = "DWItemAmount"
    local selected = nil          -- asset path of the chosen owned item
    local unlimited = false
    local catalog = nil           -- loaded item data assets, scanned once per session
    local consumables = nil       -- the subset that is ItemConsumableDataAsset

    local function publish(text) menu.SetLabel(id, "status", text) end

    local function playerInventory()
        local player = helpers.GetPlayer()
        assert(valid(player), "No controlled player; load a save first.")
        local inventory = player:GetInventoryComponent()
        assert(valid(inventory) and inventory:IsA(INVENTORY_PATH), "The player's inventory component is unavailable.")
        return player, inventory
    end

    -- Return-hook bridges. FItemHandle carries no reflected fields, so the native struct
    -- is only usable while the hook that returned it is on the stack.
    local function bridge(functionPath)
        local state = { pending = nil, ready = false }
        local ok, failure = pcall(function()
            registerHook(functionPath, function() end, function(_, returned)
                local request = state.pending
                if not request then return end
                state.pending = nil
                local done, cause = pcall(function()
                    local handle = returned:get()
                    assert(type(handle) == "userdata", "Native ItemHandle userdata unavailable")
                    request.callback(handle)
                end)
                request.done, request.error = done, cause
            end)
            state.ready = true
        end)
        if not ok then print("Item handle bridge unavailable for " .. functionPath .. ": " .. tostring(failure)) end
        return state
    end
    local mintBridge = bridge(HANDLE_FUNCTION)
    local ownedBridge = bridge(OWNED_HANDLE_FUNCTION)

    local function through(state, invoke, callback)
        assert(state.ready and not state.pending, "Item handle bridge unavailable or busy")
        local request = { callback = callback, done = false }
        state.pending = request
        local ok, failure = pcall(invoke)
        state.pending = nil
        assert(ok, tostring(failure))
        assert(request.done, tostring(request.error or "Native return hook did not run"))
    end

    local function withMintedHandle(player, asset, level, callback)
        local library = StaticFindObject(LIBRARY_PATH)
        assert(valid(library), "Inventory library unavailable")
        through(mintBridge, function() library:GetItemHandle(player, asset, level) end, callback)
    end

    local function withOwnedHandle(inventory, asset, callback)
        through(ownedBridge, function() inventory:GetHandleForAssetInInventory(asset) end, callback)
    end

    -- Loaded item data assets, once per session. Class defaults and abstract classes are
    -- skipped; the scan is the same one the Give control runs.
    local function scanCatalog()
        if catalog then return end
        local base = StaticFindObject(ITEM_BASE_PATH)
        assert(valid(base), "Item data class unavailable")
        local found, foundConsumables = {}, {}
        ForEachUObject(function(object)
            if #found >= MAX_CATALOG or not object:IsA(base) or object:IsAnyClass() then return end
            local path = object:GetFullName():match("^%S+%s+(.+)$")
            if not path or not path:find("^/Game/") or path:find("Default__", 1, true) then return end
            found[#found + 1] = { asset = object, path = path }
            if object:IsA(CONSUMABLE_PATH) then foundConsumables[#foundConsumables + 1] = found[#found] end
        end)
        catalog, consumables = found, foundConsumables
    end

    -- Owned quantity per asset. The player's stacks live in the InventorySubsystem (the
    -- component's own map is empty at runtime), so the owned instance handle is asked for
    -- with GetHandleForAssetInInventory and counted with GetItemQuantity; an asset that is
    -- not owned yields an invalid handle and a zero count. A minted handle is the fallback
    -- when the owned-handle bridge cannot answer.
    local lastScan = { catalog = 0, consumables = 0, probed = 0, failures = 0, sample = "" }
    local function ownedItems(player, inventory, subset)
        scanCatalog()
        local rows = {}
        local probed, failures = 0, 0
        for _, entry in ipairs(subset or catalog) do
            if valid(entry.asset) then
                probed = probed + 1
                local quantity = 0
                local ok, failure = pcall(withOwnedHandle, inventory, entry.asset, function(handle)
                    quantity = inventory:GetItemQuantity(handle, false)
                    if quantity == 0 then quantity = inventory:GetItemQuantity(handle, true) end
                end)
                if not ok then
                    failures = failures + 1
                    if lastScan.sample == "" then lastScan.sample = tostring(failure) end
                    ok = pcall(withMintedHandle, player, entry.asset, 0, function(handle) quantity = inventory:GetItemQuantity(handle, true) end)
                end
                if ok and type(quantity) == "number" and quantity > 0 then
                    rows[#rows + 1] = { asset = entry.asset, path = entry.path, quantity = quantity, consumable = entry.asset:IsA(CONSUMABLE_PATH) }
                end
            end
        end
        lastScan.catalog, lastScan.consumables, lastScan.probed, lastScan.failures = #catalog, #consumables, probed, failures
        table.sort(rows, function(a, b) return displayName(a.asset) < displayName(b.asset) end)
        return rows
    end

    local function refreshOptions(silent)
        local ok, result = pcall(function()
            local player, inventory = playerInventory()
            local options = {}
            for _, row in ipairs(ownedItems(player, inventory)) do
                options[#options + 1] = { label = string.format("%s  x%d", displayName(row.asset), row.quantity), value = row.path }
            end
            local still = nil
            for _, option in ipairs(options) do if option.value == selected then still = selected end end
            selected = still
            menu.SetOptions(id, "item", #options > 0 and options or { { label = "No items in the inventory", value = false } }, still or false)
            return #options
        end)
        -- SessionReady must not publish on failure (the runner retries on later ticks);
        -- a user-requested refresh says what went wrong.
        if not ok and silent then error(result, 0) end
        if not ok then publish("Could not list the inventory: " .. tostring(result)) end
        if ok and silent then return result end
        if ok and result == 0 then
            publish(string.format("No owned items found (catalog %d, consumables %d, probed %d, handle failures %d%s).",
                lastScan.catalog, lastScan.consumables, lastScan.probed, lastScan.failures,
                lastScan.sample ~= "" and (": " .. lastScan.sample) or ""))
        end
        return ok
    end

    -- Sets the owned stack for `asset` to `target`, verified by readback.
    local function setAmount(player, inventory, asset, target)
        local before, after, result
        local function change(handle)
            before = inventory:GetItemQuantity(handle, true)
            if target > before then result = inventory:TryAddItem(handle, target - before, true)
            elseif target < before then result = inventory:RemoveItem(handle, before - target)
            else result = 1 end
            after = inventory:GetItemQuantity(handle, true)
        end
        -- The exact owned instance first (right level, right stack); a freshly minted
        -- handle only when nothing is owned yet and the owned pass could not create the
        -- stack, which is how a refund re-creates a stack that was used to zero. A second
        -- pass would otherwise overwrite `before` with the count the first pass produced.
        local owned = pcall(withOwnedHandle, inventory, asset, change)
        if not owned or before == nil or (before == 0 and after ~= target) then
            local firstBefore = before
            withMintedHandle(player, asset, 0, change)
            before = firstBefore or before
        end
        return before, after, result
    end

    local function apply()
        local target = tonumber(menu.Get(id, "amount"))
        if not selected then publish("Choose an owned item first."); return end
        if not target or target < 0 or target > MAX_AMOUNT or target % 1 ~= 0 then
            publish(string.format("Amount must be a whole number from 0 to %d.", MAX_AMOUNT)); return
        end
        publish("Setting the item amount...")
        ExecuteInGameThread(function()
            local ok, failure = pcall(function()
                local player, inventory = playerInventory()
                local asset = StaticFindObject(selected)
                assert(valid(asset) and asset:IsA(ITEM_BASE_PATH), "That item is no longer available; refresh the list.")
                local before, after, result = setAmount(player, inventory, asset, target)
                local name = displayName(asset)
                if after == target then
                    publish(string.format("Verified: %s is now x%d (was x%d).", name, after, before))
                else
                    publish(string.format("%s went x%d -> x%d, not x%d: %s.", name, before or 0, after or 0, target,
                        RESULTS[result] or ("inventory result " .. tostring(result))))
                end
                refreshOptions()
            end)
            if not ok then publish("Edit Item Amount failed: " .. tostring(failure)) end
        end)
    end

    -- Unlimited Consumables: refund what a use consumed, for consumables only.
    local useSnapshot = nil
    local useHookOk, useHookError = pcall(function()
        registerHook(USE_FUNCTION, function(context)
            useSnapshot = nil
            if not unlimited then return end
            local ok, failure = pcall(function()
                local inventory = context:get()
                local player = helpers.GetPlayer()
                if not (valid(inventory) and valid(player) and inventory:GetAddress() == player:GetInventoryComponent():GetAddress()) then return end
                scanCatalog()
                local before = {}
                for _, row in ipairs(ownedItems(player, inventory, consumables)) do before[row.path] = row end
                useSnapshot = { inventory = inventory, player = player, before = before }
            end)
            if not ok then print("Unlimited consumables pre-hook failed: " .. tostring(failure)) end
        end, function(context)
            local snapshot = useSnapshot
            useSnapshot = nil
            if not snapshot or not unlimited then return end
            local ok, failure = pcall(function()
                local inventory = context:get()
                if inventory:GetAddress() ~= snapshot.inventory:GetAddress() then return end
                local after = {}
                for _, row in ipairs(ownedItems(snapshot.player, inventory, consumables)) do after[row.path] = row.quantity end
                for path, row in pairs(snapshot.before) do
                    local remaining = after[path] or 0
                    if remaining < row.quantity then
                        local missing = row.quantity - remaining
                        -- Outside the hook, on the next game-thread turn: the game has finished
                        -- the use, and the refund's own handle hooks do not nest inside this one.
                        ExecuteInGameThread(function()
                            local refunded, cause = pcall(function()
                                local before, restored, result = setAmount(snapshot.player, inventory, row.asset, row.quantity)
                                if restored == row.quantity then
                                    publish(string.format("Unlimited Consumables: %s used, x%d refunded (x%d -> x%d).", displayName(row.asset), missing, before or 0, restored))
                                else
                                    publish(string.format("Unlimited Consumables could not refund %s: %s (x%d -> x%d).", displayName(row.asset),
                                        RESULTS[result] or tostring(result), before or 0, restored or 0))
                                end
                                refreshOptions()
                            end)
                            if not refunded then publish("Unlimited Consumables refund failed: " .. tostring(cause)) end
                        end)
                    end
                end
            end)
            if not ok then print("Unlimited consumables post-hook failed: " .. tostring(failure)) end
        end)
    end)
    if not useHookOk then print("Unlimited consumables hook unavailable: " .. tostring(useHookError)) end

    menu.Register({ id = id, title = "☆ Item Amount", tab = "❀ Inventory", collapsible = true, items = {
        { type = "label", id = "status", label = "Pick an owned item, type the amount it should have, press Set amount." },
        { type = "dropdown", id = "item", label = "Owned item", searchable = true, placeholder = "Search your inventory...", maxVisible = 200,
          options = { { label = "Load a save, then Refresh", value = false } }, onChange = function(value) selected = value or nil end },
        { type = "row", items = {
            { type = "number", id = "amount", label = "Amount", default = 1, min = 0, max = MAX_AMOUNT, integer = true },
            { type = "button", id = "apply", label = "Set amount", variant = "success", onClick = apply },
            { type = "button", id = "refresh", label = "Refresh list", onClick = function() ExecuteInGameThread(function() if refreshOptions() then publish("Inventory list refreshed.") end end) end },
        } },
        { type = "checkbox", id = "unlimitedConsumables", label = "Unlimited consumables", default = false,
          onChange = function(value)
              unlimited = value == true
              if unlimited and not useHookOk then unlimited = false; menu.Set(id, "unlimitedConsumables", false); publish("Unlimited Consumables is unavailable: the UseItem hook could not be installed."); return end
              publish(unlimited and "Unlimited Consumables ON: food, draughts and ointments are refunded after each use."
                  or "Unlimited Consumables OFF.")
          end },
        { type = "label", label = "Set amount raises a stack with the game's own add call and lowers it with its remove call, then reads the count back. Unlimited consumables refunds exactly what a use took, for consumable items only - manuals, readables, keys and quest items are never touched." },
    } })

    -- The list is worth having before the first click. The inventory is restored from the
    -- save a little after the pawn appears, so an empty first read is treated as "not yet"
    -- (the runner retries on later ticks) and a delayed pass catches a slow restore.
    local delayedRefresh = nil
    function M.SessionReady()
        local rows = refreshOptions(true)
        if rows == 0 then error("inventory not restored yet", 0) end
        if not delayedRefresh then
            delayedRefresh = ExecuteWithDelay(6000, function() delayedRefresh = nil; pcall(refreshOptions, true) end)
        end
    end
    function M.ResetSession()
        if delayedRefresh then pcall(CancelDelayedAction, delayedRefresh); delayedRefresh = nil end
        selected = nil
        useSnapshot = nil
        catalog, consumables = nil, nil
    end

    return M
end

return M
