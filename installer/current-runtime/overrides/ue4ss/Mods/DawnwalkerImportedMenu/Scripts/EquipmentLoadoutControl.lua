local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("equipment_loadout_control")

-- Switch the active equipment loadout and put the original one back.
--
-- The loadout roster is derived from the game rather than guessed: the engine's
-- own InventoryBlueprintFunctionLibrary maps each EDayPhase to its loadout index
-- and back again, so only indices that survive that round trip are offered.
--
-- SetActiveLoadout returns void, so every outcome here is decided by a
-- GetActiveLoadoutIndex readback, never by the call appearing to succeed.

local M = {}

local INVENTORY_LIBRARY = "/Script/DogwoodInventory.Default__InventoryBlueprintFunctionLibrary"
local INVENTORY_COMPONENT_CLASS = "/Script/DogwoodInventory.InventoryComponent"

-- /Script/DogwoodSystem.EDayPhase, CL257186 capture. None (0) is not a loadout.
local DAY_PHASES = {
    { value = 1, label = "Day" },
    { value = 2, label = "Night" },
}

local function valid(object) return object ~= nil and object:IsValid() end
local function integer(value) return type(value) == "number" and value == value and value % 1 == 0 end

function M.Init(menu, helpers)
    local id, observed, baseline = "DWLoadout", nil, nil

    -- Resolve the live player inventory and record the identity of everything the
    -- decision depends on, so a later readback can prove nothing was swapped.
    local function context()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a player before reading equipment loadouts.")
        local world, controller = player:GetWorld(), player.Controller
        assert(valid(world) and valid(controller) and valid(controller.Pawn)
            and controller.Pawn:GetAddress() == player:GetAddress(),
            "Player possession changed; read the loadout again.")
        local inventory = player.InventoryComponent
        if not valid(inventory) then
            local subsystem = FindFirstOf("InventorySubsystem")
            assert(valid(subsystem) and not subsystem:GetFullName():find("Default__", 1, true),
                "Player inventory is unavailable.")
            inventory = subsystem:GetPlayerInventoryComponent()
        end
        assert(valid(inventory) and inventory:IsA(INVENTORY_COMPONENT_CLASS),
            "Player inventory component is unavailable.")
        local library = StaticFindObject(INVENTORY_LIBRARY)
        assert(valid(library), "Inventory loadout reflection is unavailable.")
        return { player = player:GetAddress(), world = world:GetAddress(),
            controller = controller:GetAddress(), inventory = inventory,
            address = inventory:GetAddress(), library = library }
    end

    local function same(left, right)
        return left.player == right.player and left.world == right.world
            and left.controller == right.controller and left.address == right.address
    end

    -- Ask the game which loadout index belongs to each day phase, and keep only the
    -- indices that map back to the same phase. An engine that reports a different
    -- loadout model here yields an empty roster instead of a guessed index.
    local function readLoadouts(record)
        local loadouts = {}
        for _, phase in ipairs(DAY_PHASES) do
            local index = record.library:GetLoadoutIndexFromDayPhase(phase.value)
            if integer(index) and index >= 0 and index < 64 then
                local roundTrip = record.library:GetLoadoutDayPhaseFromIndex(index)
                if roundTrip == phase.value then
                    loadouts[#loadouts + 1] = { index = index, label = phase.label }
                end
            end
        end
        return loadouts
    end

    local function readActiveIndex(record)
        local index = record.inventory:GetActiveLoadoutIndex()
        assert(integer(index) and index >= 0 and index < 64, "Active loadout index is outside the live range.")
        return index
    end

    local function labelFor(loadouts, index)
        for _, loadout in ipairs(loadouts) do
            if loadout.index == index then return loadout.label end
        end
        return "index " .. tostring(index)
    end

    local function read()
        local record = context()
        record.loadouts = readLoadouts(record)
        assert(#record.loadouts > 0, "The game reported no day-phase loadouts; switching is not supported here.")
        record.active = readActiveIndex(record)
        assert(same(record, context()), "Player changed while reading the loadout.")
        return record
    end

    local function sync(record, message)
        observed = record
        local options = {}
        if record then
            for _, loadout in ipairs(record.loadouts) do
                options[#options + 1] = { label = loadout.label, value = loadout.index }
            end
        end
        menu.SetOptions(id, "target", options, false)
        menu.Set(id, "owned", baseline ~= nil and record ~= nil and record.active ~= baseline)
        menu.SetLabel(id, "status", message)
    end

    local function refresh(silent)
        if not silent then sync(nil, "Reading the active equipment loadout...") end
        local ok, record = pcall(read)
        if not ok then if not silent then sync(nil, "Unavailable: " .. tostring(record)) end; error(record, 0) end
        if baseline == nil then baseline = record.active end
        sync(record, string.format(
            "Active loadout: %s. Original loadout this session: %s. The game switches loadouts itself at day/night transitions.",
            labelFor(record.loadouts, record.active), labelFor(record.loadouts, baseline)))
    end

    -- Apply one loadout index and prove the change by reading the index back.
    local function switchTo(target, successMessage)
        local record = read()
        assert(integer(target), "Choose a loadout first.")
        local known = false
        for _, loadout in ipairs(record.loadouts) do
            if loadout.index == target then known = true end
        end
        assert(known, "That loadout index is not offered by the live game.")
        -- The game refuses equipment changes during combat; do not leave a half-applied switch.
        local combat = FindFirstOf("CombatSubsystem")
        if valid(combat) and not combat:GetFullName():find("Default__", 1, true) then
            assert(not combat:GetIsInCombat(), "Leave combat before switching equipment loadouts.")
        end
        if record.active == target then
            sync(record, "That loadout is already active; nothing changed.")
            return
        end
        record.inventory:SetActiveLoadout(target)
        local after = readActiveIndex(record)
        assert(same(record, context()), "Player changed while switching the loadout.")
        record.active = after
        if after ~= target then
            sync(record, string.format("The game kept loadout %s; the switch to %s was refused.",
                labelFor(record.loadouts, after), labelFor(record.loadouts, target)))
            error("Loadout readback did not match the requested loadout")
        end
        sync(record, string.format(successMessage, labelFor(record.loadouts, after)))
    end

    local function apply()
        switchTo(menu.Get(id, "target"), "Verified: %s loadout is active.")
    end

    local function restore()
        assert(baseline ~= nil, "Read the loadout first; no original loadout has been recorded.")
        switchTo(baseline, "Restored the original %s loadout.")
    end

    -- A new session must not restore into a different save's loadout.
    function M.ResetSession()
        observed, baseline = nil, nil
    end

    -- Read once the session is up so the panel is live before its first click; the runner
    -- retries a failed read on later ticks, and the Read button stays for a manual re-read.
    function M.SessionReady() refresh(true) end

    menu.Register({ id = id, title = "Equipment loadout", tab = "❀ Inventory", items = {
        { type = "label", id = "status", label = "Read the active loadout to see which day-phase sets exist." },
        { type = "dropdown", id = "target", label = "Loadout", options = {} },
        { type = "button", id = "refresh", label = "Read active loadout", onClick = refresh },
        { type = "button", id = "apply", label = "Switch to selected loadout", onClick = apply },
        { type = "button", id = "restore", label = "Restore original loadout", onClick = restore },
        { type = "checkbox", id = "owned", label = "Loadout differs from this session's original", value = false },
        { type = "label", label = "Switches which equipment set is worn. It does not create or delete items, and the game may switch loadouts again at the next day/night transition." },
    } })

    return M
end

return M
