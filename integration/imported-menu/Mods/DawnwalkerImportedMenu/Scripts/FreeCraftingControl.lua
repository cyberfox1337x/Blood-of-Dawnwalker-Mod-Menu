local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("free_crafting_control")

-- Ignore Crafting Requirement: craft without spending ingredients.
--
-- The game's own crafting entry points already carry the switch. CraftingSubsystem::CraftItem
-- and CanItemBeCrafted both take a `bForFree` argument (pinned dump DogwoodInventory.hpp:
-- `CraftItem(Handle, GeneratedQuantity, bForFree, CraftQuantity)` and
-- `CanItemBeCrafted(Handle, bForFree, CraftQuantity)`), which the daily-free-item path sets
-- true to skip the ingredient check and the ingredient removal. While this control is ON, a
-- pre-hook on each function flips that argument to true before the native body runs, so
-- the crafting screen's own availability check and its craft call both see a free craft.
-- The crafting screen also decides whether its Craft button is live from two ingredient-
-- derived readbacks, `IsItemCraftable(Handle)` and `GetItemMaxCraftCount(Handle)` (how many
-- the ingredients on hand allow, shown as "Craft all (N)"); with nothing in the pouch both
-- report nothing craftable and the button never reaches CraftItem. While ON, post-hooks
-- report craftable and at least one, so the button is live and the free craft can run.
-- Nothing is added or removed by this module; recipe unlocks and craft limits are untouched.
--
-- Writing a hook argument is the technique FormToggleControl uses live for the day-phase
-- override (`day_phase:set(...)`). Only the player's own crafting subsystem is affected: the
-- hook checks the called object against the world's subsystem the player resolves to.

local M = {}

local CRAFT_FUNCTION = "/Script/DogwoodInventory.CraftingSubsystem:CraftItem"
local CAN_CRAFT_FUNCTION = "/Script/DogwoodInventory.CraftingSubsystem:CanItemBeCrafted"
local IS_CRAFTABLE_FUNCTION = "/Script/DogwoodInventory.CraftingSubsystem:IsItemCraftable"
local MAX_COUNT_FUNCTION = "/Script/DogwoodInventory.CraftingSubsystem:GetItemMaxCraftCount"
local CRAFTING_SUBSYSTEM_CLASS = "/Script/DogwoodInventory.CraftingSubsystem"

local RESULTS = { [0] = "None", [1] = "Success", [2] = "Failure", [3] = "NotEnoughIngredients", [4] = "ItemNotCraftable",
    [5] = "NotEnoughSpace", [6] = "RecipeLocked", [7] = "CraftingLimitReached" }

local function valid(object) return object ~= nil and object:IsValid() end

function M.Init(menu, helpers, deps)
    deps = deps or {}
    local registerHook = assert(deps.registerHook, "FreeCraftingControl needs the native RegisterHook")
    local id = "DWFreeCrafting"
    local enabled = false
    local forcedChecks, forcedCrafts, forcedReadbacks = 0, 0, 0
    local lastCraft = nil

    local function publish(message) menu.SetLabel(id, "status", message) end

    local function summary()
        if not enabled then return "Ignore crafting requirement OFF." end
        local tail = lastCraft and string.format(" Last craft: %s.", lastCraft) or ""
        return string.format("Ignore crafting requirement ON: %d craft%s made free, %d availability check%s passed, %d craftable readback%s forced.%s",
            forcedCrafts, forcedCrafts == 1 and "" or "s", forcedChecks, forcedChecks == 1 and "" or "s",
            forcedReadbacks, forcedReadbacks == 1 and "" or "s", tail)
    end

    -- True only for the crafting subsystem of the world the controlled player is in, so a
    -- call on any other subsystem instance (none is expected) is left exactly as made.
    local function ownSubsystem(target)
        if not valid(target) or not target:IsA(CRAFTING_SUBSYSTEM_CLASS) then return false end
        local player = helpers.GetPlayer()
        if not valid(player) then return false end
        local world = player:GetWorld()
        return valid(world) and valid(target:GetOuter()) and target:GetOuter():GetAddress() == world:GetAddress()
            and not target:GetFullName():find("Default__", 1, true)
    end

    local function force(flag, counter)
        if not enabled then return false end
        local ok, forced = pcall(function()
            if flag:get() == true then return false end
            flag:set(true)
            return flag:get() == true
        end)
        if not ok then print("Free crafting hook could not set bForFree: " .. tostring(forced)); return false end
        if forced then counter() end
        return forced
    end

    -- Rewrites a native return value after the body ran, for the player's subsystem only.
    local function rewriteReturn(functionPath, rewrite)
        registerHook(functionPath, function() end, function(context, returned)
            if not enabled then return end
            local ok, failure = pcall(function()
                if not ownSubsystem(context:get()) then return end
                local replacement = rewrite(returned:get())
                if replacement == nil then return end
                returned:set(replacement)
                if returned:get() == replacement then forcedReadbacks = forcedReadbacks + 1 end
            end)
            if not ok then print("Free crafting readback hook failed (" .. functionPath .. "): " .. tostring(failure)) end
        end)
    end

    local hookOk, hookError = pcall(function()
        rewriteReturn(IS_CRAFTABLE_FUNCTION, function(value) if value ~= true then return true end end)
        rewriteReturn(MAX_COUNT_FUNCTION, function(value) if type(value) == "number" and value < 1 then return 1 end end)
        registerHook(CAN_CRAFT_FUNCTION, function(context, _, forFree)
            if not enabled then return end
            local ok, failure = pcall(function()
                if not ownSubsystem(context:get()) then return end
                force(forFree, function() forcedChecks = forcedChecks + 1 end)
            end)
            if not ok then print("Free crafting availability hook failed: " .. tostring(failure)) end
        end, function() end)
        local pendingCraft = nil
        registerHook(CRAFT_FUNCTION, function(context, _, _, forFree)
            pendingCraft = nil
            if not enabled then return end
            local ok, failure = pcall(function()
                if not ownSubsystem(context:get()) then return end
                if force(forFree, function() forcedCrafts = forcedCrafts + 1 end) then pendingCraft = true end
            end)
            if not ok then print("Free crafting craft hook failed: " .. tostring(failure)) end
        end, function(_, returned)
            if not pendingCraft then return end
            pendingCraft = nil
            local ok, failure = pcall(function()
                local result = returned:get()
                lastCraft = RESULTS[result] or tostring(result)
                publish(summary())
            end)
            if not ok then print("Free crafting result hook failed: " .. tostring(failure)) end
        end)
    end)
    if not hookOk then print("Free crafting hooks unavailable: " .. tostring(hookError)) end

    menu.Register({ id = id, title = "Free crafting", tab = "❀ Inventory", items = {
        { type = "label", id = "status", label = "Ignore crafting requirement OFF." },
        { type = "checkbox", id = "enabled", label = "Ignore crafting requirement", default = false, onChange = function(value)
            if value and not hookOk then
                menu.Set(id, "enabled", false)
                publish("Ignore crafting requirement is unavailable: the crafting hooks could not be installed.")
                return
            end
            enabled = value == true
            if not enabled then forcedChecks, forcedCrafts, forcedReadbacks, lastCraft = 0, 0, 0, nil end
            publish(summary())
        end },
        { type = "label", label = "While ON, every craft the crafting screen makes runs through the game's own free-craft path (the same one it uses for daily free supplies), so no ingredients are checked or spent, and the Craft button stays live with an empty pouch. Craft all still counts real ingredients. Recipes still need to be unlocked and craft limits still apply; use Unlock all crafting recipes for the former." },
    } })

    function M.ResetSession()
        forcedChecks, forcedCrafts, forcedReadbacks, lastCraft = 0, 0, 0, nil
        if enabled then publish(summary()) end
    end

    return M
end

return M
