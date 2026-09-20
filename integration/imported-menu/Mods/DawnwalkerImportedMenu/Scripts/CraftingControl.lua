local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("crafting_control")

-- Crafting helpers backed by the game's own CraftingSubsystem.
--
-- Both actions take no arguments and return nothing, so each is proved only by a
-- readback that must actually move: the count of available recipes for Unlock, and
-- the daily free-item count for Refill. Both write to the save and cannot be undone
-- from this menu, so both confirm first and say so.
--
-- AddIngredientsForAllCraftingRecipes is deliberately NOT offered: its single
-- CraftableItems integer has no discovered unit or bound in the captured build, so
-- there is no honest way to verify what a given value did.

local M = {}

local CRAFTING_SUBSYSTEM_CLASS = "/Script/DogwoodInventory.CraftingSubsystem"

local function valid(object) return object ~= nil and object:IsValid() end
local function integer(value) return type(value) == "number" and value == value and value % 1 == 0 end

function M.Init(menu, helpers)
    local id = "DWCrafting"

    local function resolve()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a save before using the crafting helpers.")
        local world, controller = player:GetWorld(), player.Controller
        assert(valid(world) and valid(controller) and valid(controller.Pawn)
            and controller.Pawn:GetAddress() == player:GetAddress(),
            "Player possession changed; read the crafting status again.")
        local subsystem = FindFirstOf("CraftingSubsystem")
        assert(valid(subsystem) and not subsystem:GetFullName():find("Default__", 1, true),
            "Crafting subsystem unavailable; it may only exist once crafting has been used.")
        assert(subsystem:IsA(CRAFTING_SUBSYSTEM_CLASS), "Resolved object is not the crafting subsystem.")
        return { player = player:GetAddress(), world = world:GetAddress(),
            controller = controller:GetAddress(), subsystem = subsystem, address = subsystem:GetAddress() }
    end

    local function same(left, right)
        return left.player == right.player and left.world == right.world
            and left.controller == right.controller and left.address == right.address
    end

    -- GetAvailableItemRecipes returns a TArray; its length is the only figure needed
    -- here. An unreadable array yields nil so the panel degrades instead of failing.
    local function recipeCount(subsystem)
        local ok, count = pcall(function()
            local recipes = subsystem:GetAvailableItemRecipes()
            if recipes == nil then return nil end
            if type(recipes) == "table" then return #recipes end
            return recipes:GetArrayNum()
        end)
        if not ok then
            print("[DawnwalkerImportedMenu] Crafting recipe count unavailable: " .. tostring(count))
            return nil
        end
        return count
    end

    -- Read one optional figure. Returns nil only when the call actually failed, so a
    -- legitimate false or 0 is never mistaken for an unavailable reading.
    local function readOptional(name, reader)
        local ok, value = pcall(reader)
        if ok then return value end
        print(string.format("[DawnwalkerImportedMenu] Crafting %s unavailable: %s", name, tostring(value)))
        return nil
    end

    local function read()
        local record = resolve()
        local subsystem = record.subsystem
        record.recipes = recipeCount(subsystem)
        record.daily = readOptional("daily free items", function() return subsystem:GetPlayerCraftDailyFreeItems() end)
        record.limits = readOptional("craft limits", function() return subsystem:AreCraftLimitsEnabled() end)
        assert(same(record, resolve()), "Player changed while reading crafting status.")
        return record
    end

    local function describe(record)
        local parts = {}
        parts[#parts + 1] = integer(record.recipes) and ("available recipes: " .. record.recipes)
            or "available recipes: unreadable"
        if record.daily ~= nil then parts[#parts + 1] = "daily free items: " .. tostring(record.daily) end
        if record.limits ~= nil then parts[#parts + 1] = "craft limits enabled: " .. tostring(record.limits) end
        return table.concat(parts, "; ") .. "."
    end

    local function refresh(silent)
        if not silent then menu.SetLabel(id, "status", "Reading crafting status...") end
        local ok, record = pcall(read)
        if not ok then if not silent then menu.SetLabel(id, "status", "Unavailable: " .. tostring(record)) end; error(record, 0) end
        menu.SetLabel(id, "status", describe(record))
    end

    local function unlockRecipes()
        local before = read()
        before.subsystem:UnlockAllCraftingRecipes()
        local after = read()
        assert(same(before, after), "Player changed while unlocking crafting recipes.")
        if integer(before.recipes) and integer(after.recipes) then
            if after.recipes > before.recipes then
                menu.SetLabel(id, "status", string.format("Verified: available recipes %d -> %d. %s",
                    before.recipes, after.recipes, describe(after)))
                return
            end
            menu.SetLabel(id, "status", string.format(
                "Available recipes did not change (%d). They may already all be unlocked. %s",
                after.recipes, describe(after)))
            return
        end
        -- Without a readable recipe count there is no proof, so do not claim one.
        menu.SetLabel(id, "status", "Unlock was requested, but the recipe count could not be read, so the result is unverified. " .. describe(after))
        error("Crafting recipe count unavailable; unlock result unverified")
    end

    local function refillDaily()
        local before = read()
        before.subsystem:RefillDailyFreeItems()
        local after = read()
        assert(same(before, after), "Player changed while refilling daily crafting supplies.")
        if before.daily ~= nil and after.daily ~= nil then
            if after.daily ~= before.daily then
                menu.SetLabel(id, "status", string.format("Verified: daily free items %s -> %s. %s",
                    tostring(before.daily), tostring(after.daily), describe(after)))
                return
            end
            menu.SetLabel(id, "status", string.format(
                "Daily free items did not change (%s). They may already be full. %s",
                tostring(after.daily), describe(after)))
            return
        end
        menu.SetLabel(id, "status", "Refill was requested, but the daily free-item count could not be read, so the result is unverified. " .. describe(after))
        error("Daily free-item count unavailable; refill result unverified")
    end

    -- Read once the session is up so the panel is live before its first click; the runner
    -- retries a failed read on later ticks, and the Read button stays for a manual re-read.
    function M.SessionReady() refresh(true) end

    menu.Register({ id = id, title = "Crafting", tab = "❀ Inventory", items = {
        { type = "label", id = "status", label = "Read crafting status to see recipes and daily supplies." },
        { type = "button", id = "refresh", label = "Read crafting status", onClick = refresh },
        { type = "button", id = "unlock", label = "Unlock all crafting recipes", variant = "warning", confirm = {
            title = "Unlock every crafting recipe?",
            message = "Permanently marks all crafting recipes as unlocked in your save. It bypasses the manuals, purchases and discoveries that normally grant them, may trigger achievements, and cannot be undone from this menu.",
            confirmLabel = "Unlock recipes", cancelLabel = "Cancel" }, onClick = unlockRecipes },
        { type = "button", id = "daily", label = "Refill daily free crafting supplies", onClick = refillDaily },
        { type = "label", label = "Ingredient granting is not offered: the game's ingredient function takes an undocumented amount whose unit is unknown in this build, so its result could not be verified." },
    } })

    return M
end

return M
