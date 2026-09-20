local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("trait_point_control")

-- Set the available trait-point total directly.
--
-- The shipped Skill Points panel adds and spends points through ReceiveTraitPoints
-- and SpendTraitPoints. This control instead writes the total with the game's own
-- SetTraitPointsAmount, which is the only way to lower it below what has been spent
-- or to set an exact figure, and it records the session's original total so the
-- change can be put back.

local M = {}

local CHARACTER_DEVELOPMENT_CLASS = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"
local MAXIMUM_TRAIT_POINTS = 999

local function valid(object) return object ~= nil and object:IsValid() end
local function integer(value) return type(value) == "number" and value == value and value % 1 == 0 end

function M.Init(menu, helpers)
    local id, baseline = "DWTraitPoints", nil

    local function resolve()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a save before editing trait points.")
        local world, controller = player:GetWorld(), player.Controller
        assert(valid(world) and valid(controller) and valid(controller.Pawn)
            and controller.Pawn:GetAddress() == player:GetAddress(),
            "Player possession changed; read trait points again.")
        local subsystem = FindFirstOf("CharacterDevelopmentSubsystem")
        assert(valid(subsystem) and not subsystem:GetFullName():find("Default__", 1, true),
            "Character development subsystem unavailable.")
        assert(subsystem:IsA(CHARACTER_DEVELOPMENT_CLASS), "Resolved object is not the character development subsystem.")
        return { player = player:GetAddress(), world = world:GetAddress(),
            controller = controller:GetAddress(), subsystem = subsystem, address = subsystem:GetAddress() }
    end

    local function same(left, right)
        return left.player == right.player and left.world == right.world
            and left.controller == right.controller and left.address == right.address
    end

    local function readPoints(record)
        local points = record.subsystem:GetTraitPointAmount()
        assert(integer(points) and points >= 0 and points <= MAXIMUM_TRAIT_POINTS,
            "Trait point total is outside the supported range.")
        return points
    end

    local function read()
        local record = resolve()
        record.points = readPoints(record)
        assert(same(record, resolve()), "Player changed while reading trait points.")
        return record
    end

    local function sync(record, message)
        menu.Set(id, "owned", baseline ~= nil and record ~= nil and record.points ~= baseline)
        menu.SetLabel(id, "status", message)
    end

    local function refresh(silent)
        if not silent then sync(nil, "Reading trait points...") end
        local ok, record = pcall(read)
        if not ok then if not silent then sync(nil, "Unavailable: " .. tostring(record)) end; error(record, 0) end
        if baseline == nil then baseline = record.points end
        sync(record, string.format("Available trait points: %d. Original this session: %d.", record.points, baseline))
    end

    -- Write an exact total and prove it with GetTraitPointAmount.
    local function applyAmount(target, successMessage)
        assert(integer(target) and target >= 0 and target <= MAXIMUM_TRAIT_POINTS,
            "Choose a whole trait-point total between 0 and " .. MAXIMUM_TRAIT_POINTS .. ".")
        local record = read()
        if record.points == target then
            sync(record, string.format("Trait points are already %d; nothing changed.", target))
            return
        end
        record.subsystem:SetTraitPointsAmount(target)
        local after = readPoints(record)
        assert(same(record, resolve()), "Player changed while writing trait points.")
        record.points = after
        if after ~= target then
            sync(record, string.format("The game kept %d trait points; the change to %d was refused.", after, target))
            error("Trait point readback did not match the requested total")
        end
        sync(record, string.format(successMessage, after))
    end

    local function apply()
        applyAmount(menu.Get(id, "amount"), "Verified: trait points set to %d.")
    end

    local function restore()
        assert(baseline ~= nil, "Read trait points first; no original total has been recorded.")
        applyAmount(baseline, "Restored the original %d trait points.")
    end

    function M.ResetSession()
        baseline = nil
    end

    -- Read once the session is up so the panel is live before its first click; the runner
    -- retries a failed read on later ticks, and the Read button stays for a manual re-read.
    function M.SessionReady() refresh(true) end

    menu.Register({ id = id, title = "Trait points", tab = "✦ Progression", items = {
        { type = "label", id = "status", label = "Read trait points to record this session's original total." },
        { type = "number", id = "amount", label = "Trait point total", value = 1, min = 0, max = MAXIMUM_TRAIT_POINTS, integer = true },
        { type = "button", id = "refresh", label = "Read trait points", onClick = refresh },
        { type = "button", id = "apply", label = "Set exact trait point total", variant = "warning", confirm = {
            title = "Set the exact trait point total?",
            message = "Writes the available trait-point total directly, bypassing normal progression. Lowering it does not remove skills you already unlocked, and the change persists once you save.",
            confirmLabel = "Set total", cancelLabel = "Cancel" }, onClick = apply },
        { type = "button", id = "restore", label = "Restore original total", onClick = restore },
        { type = "checkbox", id = "owned", label = "Total differs from this session's original", value = false },
        { type = "label", label = "This sets the total directly. The Skill Points panel adds and spends points through the normal progression calls instead." },
    } })

    return M
end

return M
