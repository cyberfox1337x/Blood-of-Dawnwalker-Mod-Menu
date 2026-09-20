local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("blood_segment_control")

-- Repair permanent blood-segment damage on the player's blood bar.
--
-- HealAndReplenishAllSegments takes no arguments and returns nothing, so the only
-- honest proof is the blood bar's own readback: GetBloodPermDamage must fall.
-- This is a restorative, one-way change - permanent damage cannot be put back -
-- so the control states that plainly and confirms before acting.

local M = {}

local function valid(object) return object ~= nil and object:IsValid() end
local function number(value) return type(value) == "number" and value == value end

function M.Init(menu, helpers)
    local id = "DWBloodSegments"

    -- Resolve the player's blood bar the same way the shipped player controls do.
    local function resolve()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a save before reading the blood bar.")
        local world, controller = player:GetWorld(), player.Controller
        assert(valid(world) and valid(controller) and valid(controller.Pawn)
            and controller.Pawn:GetAddress() == player:GetAddress(),
            "Player possession changed; read the blood bar again.")
        local ok, blood = pcall(function() return player.BloodBar end)
        if not ok or not valid(blood) then
            ok, blood = pcall(function()
                local state = player.PlayerState
                return valid(state) and state.BloodBar or nil
            end)
        end
        assert(ok and valid(blood), "Player blood component unavailable")
        return { player = player:GetAddress(), world = world:GetAddress(),
            controller = controller:GetAddress(), blood = blood, address = blood:GetAddress() }
    end

    local function same(left, right)
        return left.player == right.player and left.world == right.world
            and left.controller == right.controller and left.address == right.address
    end

    -- Read every blood-bar figure the component exposes. Optional readings are
    -- reported as nil rather than blocking the whole panel.
    local function read()
        local record = resolve()
        local blood = record.blood
        local permanentDamage = blood:GetBloodPermDamage()
        assert(number(permanentDamage), "Blood permanent-damage reading is unavailable.")
        record.permanentDamage = permanentDamage
        local readOptional = function(name, reader)
            local ok, value = pcall(reader)
            if ok then return value end
            print(string.format("[DawnwalkerImportedMenu] Blood %s reading unavailable: %s", name, tostring(value)))
            return nil
        end
        record.segments = readOptional("segment count", function() return blood:GetSegmentCount() end)
        record.fatigued = readOptional("fatigue", function() return blood:IsFatigued() end)
        record.canRecover = readOptional("recovery", function() return blood:CanRecoverSegments() end)
        record.blood = blood
        assert(same(record, resolve()), "Player changed while reading the blood bar.")
        return record
    end

    local function describe(record)
        local parts = { string.format("Permanent blood damage: %s", tostring(record.permanentDamage)) }
        if number(record.segments) then parts[#parts + 1] = string.format("segments: %s", tostring(record.segments)) end
        if record.fatigued ~= nil then parts[#parts + 1] = string.format("fatigued: %s", tostring(record.fatigued)) end
        if record.canRecover ~= nil then parts[#parts + 1] = string.format("can recover: %s", tostring(record.canRecover)) end
        return table.concat(parts, "; ") .. "."
    end

    local function refresh(silent)
        if not silent then menu.SetLabel(id, "status", "Reading the blood bar...") end
        local ok, record = pcall(read)
        if not ok then if not silent then menu.SetLabel(id, "status", "Unavailable: " .. tostring(record)) end; error(record, 0) end
        menu.SetLabel(id, "status", describe(record))
    end

    local function repair()
        local before = read()
        before.blood:HealAndReplenishAllSegments()
        local after = read()
        assert(same(before, after), "Player changed while repairing blood segments.")
        if after.permanentDamage < before.permanentDamage then
            menu.SetLabel(id, "status", string.format(
                "Verified: permanent blood damage %s -> %s. %s",
                tostring(before.permanentDamage), tostring(after.permanentDamage), describe(after)))
            return
        end
        if before.permanentDamage == 0 then
            menu.SetLabel(id, "status", "There was no permanent blood damage to repair. " .. describe(after))
            return
        end
        menu.SetLabel(id, "status", string.format(
            "The game did not reduce permanent blood damage (still %s). %s",
            tostring(after.permanentDamage), describe(after)))
        error("Blood segment readback did not improve")
    end

    -- Read once the session is up so the panel is live before its first click; the runner
    -- retries a failed read on later ticks, and the Read button stays for a manual re-read.
    function M.SessionReady() refresh(true) end

    menu.Register({ id = id, title = "Blood segments", tab = "♡ Player", items = {
        { type = "label", id = "status", label = "Read the blood bar to see permanent segment damage." },
        { type = "button", id = "refresh", label = "Read blood bar", onClick = refresh },
        { type = "button", id = "repair", label = "Repair all blood segments", variant = "success", confirm = {
            title = "Repair permanent blood damage?",
            message = "Heals and replenishes every blood segment, clearing permanent blood-bar damage. This is a one-way restorative change: the damage cannot be put back, and it will persist once you save.",
            confirmLabel = "Repair segments", cancelLabel = "Cancel" }, onClick = repair },
        { type = "label", label = "Permanent damage shortens the usable blood bar. Repairing it cannot be undone from this menu." },
    } })

    return M
end

return M
