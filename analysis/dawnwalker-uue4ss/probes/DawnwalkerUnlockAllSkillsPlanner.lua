local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_unlock_all_skills_planner")

-- Standalone one-way Unlock All Skills planner for the pinned Dawnwalker build.
--
-- This module is not a mod entrypoint. It does not schedule itself, is absent from the
-- bridge capability list, and is absent from every installer and release artifact.
-- Importing it only returns a table of functions; a future operator must deliberately
-- supply the live dependencies and call them on the game thread.
--
-- `snapshot` is read-only. `apply` performs the single irreversible UnlockAllTraits call
-- and refuses unless the caller passes an explicit authorization carrying the SHA-256 of an
-- already-persisted snapshot. `reconstruct` is a best-effort convenience and is never a
-- rollback guarantee -- see UNLOCK-ALL-SKILLS-FEASIBILITY.md for the fidelity gaps.

local Planner = {}

local SUBSYSTEM_PATH = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"
local TRAIT_ASSET_PATH = "/Script/DogwoodCharacterDevelopment.TraitAsset"

-- Bounded so a corrupt or hostile container can never spin the game thread.
local MAX_TRAITS = 4096

local SCHEMA_VERSION = 1
local PLANNER_ID = "player:unlock-all-skills"
local EVIDENCE_CLASS = "development-one-way"

local function fail(stage, message)
    return {
        ok = false,
        mutation_authorized = false,
        stage = stage,
        message = message,
    }
end

local function is_whole_number(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
        and value % 1 == 0
end

local function is_valid(object)
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

local function address_of(object)
    if not is_valid(object) then return nil end
    local ok, address = pcall(function() return object:GetAddress() end)
    if not ok or not is_whole_number(address) then return nil end
    return address
end

local function as_string(value)
    if type(value) == "string" then return value end
    if value == nil then return nil end
    local ok, converted = pcall(function() return value:ToString() end)
    if ok and type(converted) == "string" then return converted end
    return nil
end

local function unwrap_remote_value(value)
    if value == nil then return nil end
    local unwrap_ok, unwrapped = pcall(function() return value:get() end)
    if unwrap_ok then return unwrapped end
    return value
end

local function is_a(object, class_path)
    if not is_valid(object) then return false end
    local ok, result = pcall(function() return object:IsA(class_path) end)
    return ok and result == true
end

-- Reads a bounded reflected container through either supported UE4SS ABI shape. A live
-- nested container has already been observed to reject `ForEach` in this build, so both
-- shapes are required and an incomplete walk is a hard failure rather than a partial read.
local function read_bounded_array(container)
    if container == nil then return nil, "container was nil" end

    -- Every entry is unwrapped before validation: the live GetAllTraits() container in the
    -- pinned build returns wrapped remote values on the table and numeric shapes (the 0.3.19
    -- live probe proved this when every roster entry failed IsValid), so an entry may carry a
    -- :get() proxy that must be resolved before IsValid/IsA can see the real UObject.
    if type(container) == "table" then
        local entries = {}
        for index, value in ipairs(container) do
            if index > MAX_TRAITS then return nil, "container exceeded its safety bound" end
            entries[#entries + 1] = unwrap_remote_value(value)
        end
        return entries, nil
    end

    local for_each_ok, for_each = pcall(function() return container.ForEach end)
    if for_each_ok and type(for_each) == "function" then
        local entries = {}
        local overflow = false
        local iterate_ok, iterate_error = pcall(function()
            for_each(container, function(_index, element)
                if #entries >= MAX_TRAITS then overflow = true return end
                entries[#entries + 1] = unwrap_remote_value(element)
            end)
        end)
        if not iterate_ok then return nil, "container iteration failed: " .. tostring(iterate_error) end
        if overflow then return nil, "container exceeded its safety bound" end
        return entries, nil
    end

    local count_ok, count = pcall(function() return #container end)
    if not count_ok or not is_whole_number(count) or count < 0 then
        return nil, "container had an invalid size"
    end
    if count > MAX_TRAITS then return nil, "container exceeded its safety bound" end

    local entries = {}
    for index = 1, count do
        local element_ok, element = pcall(function() return container[index] end)
        if not element_ok or element == nil then
            return nil, "container entry " .. tostring(index) .. " was unreadable"
        end
        entries[#entries + 1] = unwrap_remote_value(element)
    end
    return entries, nil
end

local function call_number(subsystem, method, argument)
    local ok, value = pcall(function()
        if argument == nil then return subsystem[method](subsystem) end
        return subsystem[method](subsystem, argument)
    end)
    if not ok or not is_whole_number(value) then return nil end
    return value
end

local function call_boolean(subsystem, method, argument, second_argument)
    local ok, value = pcall(function()
        if second_argument ~= nil then return subsystem[method](subsystem, argument, second_argument) end
        return subsystem[method](subsystem, argument)
    end)
    if not ok or type(value) ~= "boolean" then return nil end
    return value
end

local function resolve_subsystem(environment)
    if type(environment) ~= "table" then return nil, "environment was not a table" end

    local subsystem = environment.subsystem
    if not is_valid(subsystem) then return nil, "the character development subsystem was not valid" end
    if not is_a(subsystem, SUBSYSTEM_PATH) then
        return nil, "the supplied object was not a CharacterDevelopmentSubsystem"
    end
    local address = address_of(subsystem)
    if address == nil then return nil, "the subsystem address was unreadable" end
    return { subsystem = subsystem, address = address }, nil
end

-- Read-only. Enumerates every trait and captures the full restorable state plus the two
-- global trait-point counters. Never calls a setter.
function Planner.snapshot(environment)
    local context, context_error = resolve_subsystem(environment)
    if not context then return fail("identity", context_error) end
    local subsystem = context.subsystem

    local traits_ok, traits_container = pcall(function() return subsystem:GetAllTraits() end)
    if not traits_ok then return fail("enumeration", "GetAllTraits threw") end

    local entries, entries_error = read_bounded_array(traits_container)
    if not entries then return fail("enumeration", entries_error) end
    if #entries == 0 then return fail("enumeration", "the trait roster was empty") end

    local records = {}
    local seen_ids = {}
    for index = 1, #entries do
        local trait = entries[index]
        if not is_valid(trait) then
            return fail("enumeration", "trait entry " .. index .. " was not valid")
        end
        if not is_a(trait, TRAIT_ASSET_PATH) then
            return fail("enumeration", "trait entry " .. index .. " was not a TraitAsset")
        end

        local id_ok, raw_id = pcall(function() return trait.Skill_ID end)
        local skill_id = id_ok and as_string(raw_id) or nil
        if skill_id == nil or skill_id == "" then
            return fail("enumeration", "trait entry " .. index .. " had no Skill_ID")
        end
        if seen_ids[skill_id] then
            return fail("enumeration", "duplicate Skill_ID " .. skill_id)
        end
        seen_ids[skill_id] = true

        local level = call_number(subsystem, "GetTraitLevel", trait)
        if level == nil then return fail("readback", "GetTraitLevel failed for " .. skill_id) end

        local once_bought = call_number(subsystem, "GetOnceBoughtTraitLevel", trait)
        if once_bought == nil then
            return fail("readback", "GetOnceBoughtTraitLevel failed for " .. skill_id)
        end

        local unblocked = call_number(subsystem, "GetTraitUnblockedLevel", raw_id)
        if unblocked == nil then
            return fail("readback", "GetTraitUnblockedLevel failed for " .. skill_id)
        end

        local hidden = call_boolean(subsystem, "IsTraitHidden", trait)
        if hidden == nil then return fail("readback", "IsTraitHidden failed for " .. skill_id) end

        local equipped = call_boolean(subsystem, "IsTraitEquipped", trait)
        if equipped == nil then return fail("readback", "IsTraitEquipped failed for " .. skill_id) end

        local quest_locked = call_boolean(subsystem, "IsLockedByQuest", trait, level)
        if quest_locked == nil then
            return fail("readback", "IsLockedByQuest failed for " .. skill_id)
        end

        local tier_ok, tier = pcall(function() return trait.Tier end)
        local max_level_ok, max_level = pcall(function() return trait.MaxTraitLevel end)

        records[#records + 1] = {
            skill_id = skill_id,
            trait = trait,
            level = level,
            once_bought_level = once_bought,
            unblocked_level = unblocked,
            hidden = hidden,
            equipped = equipped,
            quest_locked = quest_locked,
            tier = (tier_ok and is_whole_number(tier)) and tier or 0,
            max_level = (max_level_ok and is_whole_number(max_level)) and max_level or nil,
        }
    end

    local trait_points = call_number(subsystem, "GetTraitPointAmount")
    if trait_points == nil then return fail("readback", "GetTraitPointAmount failed") end

    local spent_points = call_number(subsystem, "GetSpentTraitPointAmount")
    if spent_points == nil then return fail("readback", "GetSpentTraitPointAmount failed") end

    return {
        ok = true,
        mutation_authorized = false,
        stage = "snapshot-complete",
        schema_version = SCHEMA_VERSION,
        planner_id = PLANNER_ID,
        evidence_class = EVIDENCE_CLASS,
        subsystem_address = context.address,
        trait_count = #records,
        traits = records,
        trait_points = trait_points,
        spent_trait_points = spent_points,
        -- Stated on every snapshot so no caller can claim this operation is reversible.
        restorable = false,
        unrestorable_fields = { "onceBoughtLevel" },
    }
end

-- Performs the single irreversible UnlockAllTraits call. Refuses unless the caller passes
-- an authorization proving the snapshot was already persisted to disk.
function Planner.apply(environment, snapshot, authorization)
    if type(snapshot) ~= "table" or snapshot.ok ~= true or snapshot.traits == nil then
        return fail("authorization", "a valid snapshot is required before mutation")
    end
    if type(authorization) ~= "table" then
        return fail("authorization", "an explicit authorization is required")
    end
    if authorization.acknowledged_one_way ~= true then
        return fail("authorization", "the operator did not acknowledge the one-way action")
    end
    local persisted = authorization.persisted_snapshot_sha256
    if type(persisted) ~= "string" or #persisted ~= 64 then
        return fail("authorization", "the snapshot was not persisted before mutation")
    end

    local context, context_error = resolve_subsystem(environment)
    if not context then return fail("identity", context_error) end
    if context.address ~= snapshot.subsystem_address then
        return fail("identity", "the subsystem identity changed after the snapshot")
    end
    local subsystem = context.subsystem

    local call_ok, call_error = pcall(function()
        subsystem:UnlockAllTraits(true, true, true, false)
    end)
    if not call_ok then
        return fail("mutation", "UnlockAllTraits threw: " .. tostring(call_error))
    end

    if address_of(subsystem) ~= snapshot.subsystem_address then
        return fail("postcondition", "the subsystem identity changed during mutation")
    end

    local increased = 0
    local regressed = {}
    local still_hidden = {}
    for index = 1, #snapshot.traits do
        local record = snapshot.traits[index]
        local level = call_number(subsystem, "GetTraitLevel", record.trait)
        if level == nil then
            return fail("postcondition", "GetTraitLevel failed for " .. record.skill_id)
        end
        if level < record.level then
            regressed[#regressed + 1] = record.skill_id
        elseif level > record.level then
            increased = increased + 1
        end
        local hidden = call_boolean(subsystem, "IsTraitHidden", record.trait)
        if hidden ~= false then still_hidden[#still_hidden + 1] = record.skill_id end
    end

    if #regressed > 0 then
        return fail("postcondition", "traits regressed: " .. table.concat(regressed, ","))
    end

    return {
        ok = true,
        -- True only here: this is the one call site that is allowed to mutate.
        mutation_authorized = true,
        stage = (increased > 0) and "mutation-complete" or "mutation-noop",
        schema_version = SCHEMA_VERSION,
        planner_id = PLANNER_ID,
        evidence_class = EVIDENCE_CLASS,
        subsystem_address = context.address,
        traits_increased = increased,
        traits_still_hidden = still_hidden,
        noop = (increased == 0),
        reversible = false,
        recovery = "closed-game save backup",
    }
end

-- Best-effort convenience only. Never described or reported as a rollback.
function Planner.reconstruct(environment, snapshot)
    if type(snapshot) ~= "table" or snapshot.ok ~= true or snapshot.traits == nil then
        return fail("authorization", "a valid snapshot is required before reconstruct")
    end

    local context, context_error = resolve_subsystem(environment)
    if not context then return fail("identity", context_error) end
    if context.address ~= snapshot.subsystem_address then
        return fail("identity", "the subsystem identity changed after the snapshot")
    end
    local subsystem = context.subsystem

    local reset_ok, reset_error = pcall(function() subsystem:ResetAllTraits() end)
    if not reset_ok then
        return fail("reset", "ResetAllTraits threw: " .. tostring(reset_error))
    end

    -- Parents must exist before children, so replay ascending Tier then ascending level.
    local ordered = {}
    for index = 1, #snapshot.traits do ordered[#ordered + 1] = snapshot.traits[index] end
    table.sort(ordered, function(left, right)
        if left.tier ~= right.tier then return left.tier < right.tier end
        if left.level ~= right.level then return left.level < right.level end
        return left.skill_id < right.skill_id
    end)

    local unlock_failures = {}
    for index = 1, #ordered do
        local record = ordered[index]
        if record.level > 0 then
            local ok = pcall(function()
                -- bTriggerBoughtEvent and bShowNotification stay false so the replay is quiet.
                subsystem:UnlockTrait(record.trait, record.level, false, false, false)
            end)
            if not ok then unlock_failures[#unlock_failures + 1] = record.skill_id end
        end
    end

    local points_ok = pcall(function()
        subsystem:SetTraitPointsAmount(snapshot.trait_points)
    end)

    local equip_failures = {}
    for index = 1, #ordered do
        local record = ordered[index]
        if record.equipped then
            local ok = pcall(function()
                subsystem:SetTraitEquipped(record.trait, true, true, -1)
            end)
            if not ok then equip_failures[#equip_failures + 1] = record.skill_id end
        end
    end

    -- Report every per-trait mismatch individually rather than collapsing to one boolean.
    local level_mismatches = {}
    for index = 1, #snapshot.traits do
        local record = snapshot.traits[index]
        local level = call_number(subsystem, "GetTraitLevel", record.trait)
        if level ~= record.level then
            level_mismatches[#level_mismatches + 1] = {
                skill_id = record.skill_id,
                expected = record.level,
                actual = level,
            }
        end
    end

    local restored_points = call_number(subsystem, "GetTraitPointAmount")

    return {
        ok = (#level_mismatches == 0) and (#unlock_failures == 0) and points_ok
            and (restored_points == snapshot.trait_points),
        mutation_authorized = true,
        stage = "reconstruct-complete",
        schema_version = SCHEMA_VERSION,
        planner_id = PLANNER_ID,
        evidence_class = EVIDENCE_CLASS,
        level_mismatches = level_mismatches,
        unlock_failures = unlock_failures,
        equip_failures = equip_failures,
        trait_points_restored = (restored_points == snapshot.trait_points),
        -- Always true regardless of outcome: onceBoughtLevel has no setter in this build.
        exact_restore_achieved = false,
        unrestorable_fields = { "onceBoughtLevel" },
        recovery = "closed-game save backup",
    }
end

function Planner.format_result(result)
    if type(result) ~= "table" then return "schema_version=1;planner_id=" .. PLANNER_ID .. ";ok=0" end
    local parts = {
        "schema_version=" .. SCHEMA_VERSION,
        "planner_id=" .. PLANNER_ID,
        "evidence_class=" .. EVIDENCE_CLASS,
        "ok=" .. (result.ok and "1" or "0"),
        "mutation_authorized=" .. (result.mutation_authorized and "1" or "0"),
        "release_visible=0",
        "reversible=0",
        "stage=" .. tostring(result.stage or "unknown"),
    }
    if result.message then parts[#parts + 1] = "message=" .. tostring(result.message) end
    if result.trait_count then parts[#parts + 1] = "trait_count=" .. tostring(result.trait_count) end
    if result.traits_increased then
        parts[#parts + 1] = "traits_increased=" .. tostring(result.traits_increased)
    end
    return table.concat(parts, ";")
end

return Planner
