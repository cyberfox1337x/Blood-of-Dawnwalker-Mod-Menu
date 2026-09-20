local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_sprint_stamina_controller")

-- Live controller for the menu's "Sprint No Drain" toggle. It is the write
-- counterpart of DawnwalkerRequestedFeaturesReadOnlyProbe.lua: the same
-- player-only identity checks, but for the single attribute SprintStamina
-- CostMultiplier, with an explicit snapshot, exact readback and a restore
-- that returns the saved bytes. It deliberately performs no mutation on its
-- own; the pilot dispatches apply/restore on the game thread after the
-- installer's exact-build check passes.
--
-- Honest boundaries (mirroring the read-only probe's limitation note):
--   * This module targets ONLY the player's CharacterAttributeSet.
--   * It reads/writes ONLY SprintStaminaCostMultiplier.
--   * Dodge/Omniblock costs are reported read-only, never written.
--   * No descriptor ABI, aggregation or cross-form replication is claimed.
-- A capability becomes live only after this module passes the in-game cycle:
-- candidate install, fresh boot attestation, apply -> exact readback,
-- restore -> exact original readback, on a verified build.

local Controller = {}

local EXPECTED_BUILD = "25129649"
local EXPECTED_EXECUTABLE = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
local PLAYER_CLASS = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local PLAYER_ATTRIBUTE_CLASS = "/Script/DogwoodStats.PlayerAttributeSet"
local TARGET_ATTRIBUTE = "SprintStaminaCostMultiplier"

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function checked_number(number, label)
    require_condition(type(number) == "number" and number == number and math.abs(number) < math.huge,
        label .. " is not a finite number")
    return number
end

local function bounded_string(value, label, maximum)
    require_condition(type(value) == "string" and #value > 0 and #value <= maximum, label .. " is missing or oversized")
    return value
end

-- A read of a FloatProperty through UEHelpers' unwrapped property access
-- yields a plain number. The typed read below still fails closed on a
-- wrapper the controller does not understand.
local function read_attribute(attribute, label)
    require_condition(attribute ~= nil, label .. " is unavailable")
    local ok, value = pcall(function() return attribute:get() end)
    require_condition(ok, label .. " could not be read")
    return checked_number(value, label)
end

local function write_attribute(attribute, value, label)
    require_condition(attribute ~= nil, label .. " is unavailable")
    local ok, written = pcall(function() return attribute:set(value) end)
    require_condition(ok and written == true, label .. " refused the write")
end

local function player_record(player, expected_class, label)
    require_condition(player ~= nil and player:IsValid() == true, label .. " is unavailable")
    if expected_class then
        require_condition(player:IsA(expected_class) == true, label .. " has an unexpected class")
    end
    local name = player:GetFullName()
    require_condition(type(name) == "string" and #name > 0 and #name <= 1024, label .. " has an invalid name")
    require_condition(name:find("Default__", 1, true) == nil, label .. " is a class default object")
    local address = checked_number(player:GetAddress(), label .. " address")
    require_condition(address > 0, label .. " has an invalid address")
    return { name = name, address = tostring(address) }
end

-- Build a controller bound to one deps table. The pilot supplies real deps
-- (attestation-backed build verification and the local-player accessor); the
-- offline suite supplies fixtures. The controller never locates or writes
-- anything itself beyond the single player attribute.
function Controller.create(deps)
    require_condition(type(deps) == "table" and type(deps.verify_build) == "function" and type(deps.get_local_player) == "function",
        "controller requires verify_build and get_local_player dependencies")
    local state = { active = false, original = nil }

    local function require_player()
        local player = deps.get_local_player()
        local record = player_record(player, PLAYER_CLASS, "player")
        local attributes = player.CharacterAttributeSet
        player_record(attributes, PLAYER_ATTRIBUTE_CLASS, "player attributes")
        require_condition(attributes:GetAddress() > 0, "player attribute set has an invalid address")
        local sprint = attributes[TARGET_ATTRIBUTE]
        require_condition(sprint ~= nil, TARGET_ATTRIBUTE .. " is unavailable on the player attribute set")
        -- The record is returned so the PILOT can pin player + attribute-set
        -- addresses against the session-verified descriptor; identity pinning
        -- lives where the verified identity does, not inside this module.
        return { player = player, record = record, attributes = attributes, sprint = sprint }
    end

    local function observe()
        deps.verify_build()
        local found = require_player()
        local current = read_attribute(found.sprint, TARGET_ATTRIBUTE)
        -- Read-only companions are reported, never written.
        local dodge = found.attributes.DodgeStaminaCostMultiplier
        local omniblock = found.player.CharDevAttributeSet and found.player.CharDevAttributeSet.OmniblockStaminaCostMultiplier
        return {
            ok = true, active = state.active,
            player = found.record,
            sprint_stamina_cost_multiplier = current,
            original_sprint_stamina_cost_multiplier = state.original,
            dodge_stamina_cost_multiplier = dodge ~= nil and read_attribute(dodge, "DodgeStaminaCostMultiplier") or nil,
            omniblock_stamina_cost_multiplier = omniblock ~= nil and read_attribute(omniblock, "OmniblockStaminaCostMultiplier") or nil,
            limitation = "Writes SprintStaminaCostMultiplier only; dodge and omniblock costs are observed, never written.",
        }
    end

    local function apply(requested)
        deps.verify_build()
        require_condition(requested == true or requested == false, "Sprint No Drain requires a boolean value.")
        local found = require_player()
        local expected
        if requested then
            if not state.active then
                state.original = read_attribute(found.sprint, TARGET_ATTRIBUTE)
                require_condition(state.original >= 0 and state.original <= 1000, TARGET_ATTRIBUTE .. " original is out of range")
            end
            write_attribute(found.sprint, 0, TARGET_ATTRIBUTE)
            state.active = true
            expected = 0
        else
            if state.active and state.original ~= nil then
                write_attribute(found.sprint, state.original, TARGET_ATTRIBUTE)
                expected = state.original
            else
                expected = read_attribute(found.sprint, TARGET_ATTRIBUTE)
            end
            state.active = false
            state.original = nil
        end
        local readback = read_attribute(found.sprint, TARGET_ATTRIBUTE)
        require_condition(readback == expected, "readback does not match the requested value")
        return {
            ok = true, applied = requested, active = state.active,
            player = found.record,
            sprint_stamina_cost_multiplier = readback,
            original = state.original,
            message = string.format("Sprint No Drain %s; sprint stamina cost multiplier %.6f.",
                requested and "enabled" or "disabled", readback),
        }
    end

    local function restore()
        deps.verify_build()
        local found = require_player()
        require_condition(state.active, "Sprint No Drain is not active; nothing to restore.")
        local original = state.original
        require_condition(original ~= nil, "Sprint No Drain has no captured original to restore.")
        write_attribute(found.sprint, original, TARGET_ATTRIBUTE)
        local readback = read_attribute(found.sprint, TARGET_ATTRIBUTE)
        require_condition(readback == original, "restored readback does not match the captured original")
        state.active = false
        state.original = nil
        return {
            ok = true, active = false, player = found.record,
            sprint_stamina_cost_multiplier = readback,
            restored_original = original,
            message = string.format("Sprint No Drain restored; sprint stamina cost multiplier %.6f.", readback),
        }
    end

    return {
        observe = observe,
        apply = apply,
        restore = restore,
        state = function() return { active = state.active, original = state.original } end,
        expected_build = EXPECTED_BUILD,
        expected_executable = EXPECTED_EXECUTABLE,
        target_attribute = TARGET_ATTRIBUTE,
    }
end

return Controller