local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_unlock_all_skills_planner_tests")

local planner_path = assert(arg[1], "Expected the planner source path as argument 1.")

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, received %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function assert_true(value, label)
    if value ~= true then error(label .. ": expected true", 2) end
end

local function assert_match(value, pattern, label)
    if type(value) ~= "string" or value:match(pattern) == nil then
        error(string.format("%s: value did not match %s: %s", label, pattern, tostring(value)), 2)
    end
end

local source_file = assert(io.open(planner_path, "r"))
local planner_source = source_file:read("*a")
source_file:close()

-- These consume trait points or randomise progression. They would compound the damage
-- rather than reproduce a baseline and must never appear in this path.
for _, forbidden_pattern in ipairs({
    ":TryBuyTrait%s*%(",
    ":UnlockRandomTrait%s*%(",
    ":ReceiveTraitPoints%s*%(",
    ":SpendTraitPoints%s*%(",
    ":SpendTime%s*%(",
    ":ReceiveQuestSkillRewards%s*%(",
}) do
    assert_equal(planner_source:find(forbidden_pattern), nil,
        "planner excludes forbidden pattern " .. forbidden_pattern)
end
assert_match(planner_source, "UnlockAllTraits", "exact action name present")
assert_match(planner_source, "ResetAllTraits", "reconstruct reset route present")
assert_match(planner_source, "onceBoughtLevel", "unrestorable field is named")

local Planner = assert(dofile(planner_path))

local SUBSYSTEM_PATH = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"
local TRAIT_ASSET_PATH = "/Script/DogwoodCharacterDevelopment.TraitAsset"

local function name_value(value)
    return { ToString = function() return value end }
end

local function make_trait(skill_id, tier, max_level)
    local trait = {
        _valid = true,
        Skill_ID = name_value(skill_id),
        Tier = tier or 1,
        MaxTraitLevel = max_level or 3,
    }
    function trait:IsValid() return self._valid end
    function trait:GetAddress() return 0x5000 + #skill_id end
    function trait:IsA(path) return path == TRAIT_ASSET_PATH end
    return trait
end

-- Builds a fake subsystem plus a call ledger. `options` injects each failure mode.
local function make_environment(options)
    options = options or {}

    local calls = {
        unlock_all = 0,
        reset = 0,
        unlock_trait = {},
        set_points = 0,
        set_equipped = 0,
        forbidden = 0,
    }

    local state = {}
    local order = {}
    local specs = options.traits or {
        { id = "trait.alpha", tier = 1, level = 2, once = 2, equipped = true },
        { id = "trait.beta", tier = 2, level = 0, once = 0, equipped = false },
        { id = "trait.gamma", tier = 1, level = 1, once = 3, equipped = false },
    }
    for _, spec in ipairs(specs) do
        local trait = make_trait(spec.id, spec.tier, spec.max_level)
        state[spec.id] = {
            trait = trait,
            level = spec.level,
            once = spec.once,
            unblocked = spec.unblocked or spec.level,
            hidden = spec.hidden or false,
            equipped = spec.equipped or false,
            quest_locked = false,
        }
        order[#order + 1] = spec.id
    end

    local subsystem = {
        _valid = true,
        _address = options.address or 0x1000,
        trait_points = options.trait_points or 7,
        spent_points = 4,
    }
    function subsystem:IsValid() return self._valid end
    function subsystem:GetAddress() return self._address end
    function subsystem:IsA(path)
        if options.wrong_class then return false end
        return path == SUBSYSTEM_PATH
    end

    local function entry_for(trait)
        for _, id in ipairs(order) do
            if state[id].trait == trait then return state[id] end
        end
        return nil
    end

    function subsystem:GetAllTraits()
        if options.enumeration_throws then error("GetAllTraits exploded") end
        local list = {}
        for _, id in ipairs(order) do
            -- 0.3.20: mirror the live GetAllTraits() shape, whose table entries are wrapped
            -- remote values that only resolve through a :get() proxy.
            local trait = state[id].trait
            list[#list + 1] = options.wrapped_entries and { get = function() return trait end } or trait
        end
        if options.nil_entry then list[2] = false end
        if options.oversized then
            for index = 1, 5000 do list[index] = make_trait("bulk." .. index, 1, 1) end
        end
        return list
    end

    function subsystem:GetTraitLevel(trait)
        local entry = entry_for(trait)
        if entry == nil then return nil end
        return entry.level
    end
    function subsystem:GetOnceBoughtTraitLevel(trait)
        local entry = entry_for(trait)
        return entry and entry.once or nil
    end
    function subsystem:GetTraitUnblockedLevel(_id) return 0 end
    function subsystem:IsTraitHidden(trait)
        local entry = entry_for(trait)
        if entry == nil then return nil end
        return entry.hidden
    end
    function subsystem:IsTraitEquipped(trait)
        local entry = entry_for(trait)
        return entry and entry.equipped or false
    end
    function subsystem:IsLockedByQuest(_trait, _level) return false end
    function subsystem:GetTraitPointAmount() return self.trait_points end
    function subsystem:GetSpentTraitPointAmount() return self.spent_points end

    function subsystem:UnlockAllTraits(unlock, unblock, unhide, next_only)
        calls.unlock_all = calls.unlock_all + 1
        calls.unlock_all_args = { unlock, unblock, unhide, next_only }
        if options.mutation_throws then error("UnlockAllTraits exploded") end
        if options.identity_drifts then self._address = 0x9999 end
        if options.regresses then
            for _, id in ipairs(order) do state[id].level = 0 end
            return
        end
        if options.noop then return end
        for _, id in ipairs(order) do
            state[id].level = state[id].trait.MaxTraitLevel
            state[id].hidden = false
        end
    end

    function subsystem:ResetAllTraits()
        calls.reset = calls.reset + 1
        for _, id in ipairs(order) do state[id].level = 0 end
    end

    function subsystem:UnlockTrait(trait, level, bought_event, unlock_parent, notification)
        calls.unlock_trait[#calls.unlock_trait + 1] = {
            trait = trait, level = level,
            bought_event = bought_event, unlock_parent = unlock_parent, notification = notification,
        }
        local entry = entry_for(trait)
        if entry and not options.reconstruct_partial then entry.level = level end
    end

    function subsystem:SetTraitPointsAmount(value)
        calls.set_points = calls.set_points + 1
        self.trait_points = value
    end

    function subsystem:SetTraitEquipped(_trait, _equipped, _force, _slot)
        calls.set_equipped = calls.set_equipped + 1
        return true
    end

    function subsystem:TryBuyTrait() calls.forbidden = calls.forbidden + 1 return false end
    function subsystem:SpendTraitPoints() calls.forbidden = calls.forbidden + 1 end

    return { subsystem = subsystem }, calls, state
end

local VALID_AUTH = {
    acknowledged_one_way = true,
    persisted_snapshot_sha256 = string.rep("a", 64),
}

-- Snapshot is read-only and complete.
local env, calls = make_environment()
local snapshot = Planner.snapshot(env)
assert_true(snapshot.ok, "snapshot succeeds")
assert_equal(snapshot.mutation_authorized, false, "snapshot never authorizes mutation")
assert_equal(snapshot.trait_count, 3, "snapshot enumerated every trait")
assert_equal(snapshot.trait_points, 7, "snapshot captured trait points")
assert_equal(snapshot.restorable, false, "snapshot declares itself unrestorable")
assert_equal(snapshot.unrestorable_fields[1], "onceBoughtLevel", "snapshot names the unrestorable field")
assert_equal(calls.unlock_all, 0, "snapshot performs no mutation")
assert_equal(calls.reset, 0, "snapshot performs no reset")

-- 0.3.20: wrapped remote roster entries must be unwrapped before validation.
local wrapped_env, wrapped_calls = make_environment({ wrapped_entries = true })
local wrapped_snapshot = Planner.snapshot(wrapped_env)
assert_true(wrapped_snapshot.ok, "wrapped roster snapshot succeeds after unwrap")
assert_equal(wrapped_snapshot.trait_count, 3, "wrapped roster enumerated every trait")
assert_equal(wrapped_calls.unlock_all, 0, "wrapped snapshot performs no mutation")

-- Identity and enumeration rejections.
assert_equal(Planner.snapshot({ subsystem = nil }).stage, "identity", "nil subsystem rejected")
assert_equal(Planner.snapshot((make_environment({ wrong_class = true }))).stage, "identity",
    "wrong class rejected")
assert_equal(Planner.snapshot((make_environment({ enumeration_throws = true }))).stage, "enumeration",
    "enumeration exception rejected")
assert_equal(Planner.snapshot((make_environment({ nil_entry = true }))).stage, "enumeration",
    "invalid trait entry rejected")
assert_equal(Planner.snapshot((make_environment({ oversized = true }))).stage, "enumeration",
    "oversized roster rejected")

local dup = Planner.snapshot((make_environment({ traits = {
    { id = "same.id", tier = 1, level = 1, once = 1 },
    { id = "same.id", tier = 1, level = 1, once = 1 },
} })))
assert_equal(dup.stage, "enumeration", "duplicate Skill_ID rejected")

-- Authorization gate: apply refuses without an acknowledged, persisted snapshot.
local gate_env, gate_calls = make_environment()
local gate_snapshot = Planner.snapshot(gate_env)
assert_equal(Planner.apply(gate_env, gate_snapshot, nil).stage, "authorization",
    "missing authorization rejected")
assert_equal(Planner.apply(gate_env, gate_snapshot, { acknowledged_one_way = false }).stage,
    "authorization", "unacknowledged one-way action rejected")
assert_equal(Planner.apply(gate_env, gate_snapshot, { acknowledged_one_way = true }).stage,
    "authorization", "unpersisted snapshot rejected")
assert_equal(Planner.apply(gate_env, gate_snapshot,
    { acknowledged_one_way = true, persisted_snapshot_sha256 = "short" }).stage,
    "authorization", "malformed snapshot hash rejected")
assert_equal(Planner.apply(gate_env, nil, VALID_AUTH).stage, "authorization",
    "missing snapshot rejected")
assert_equal(gate_calls.unlock_all, 0, "no rejected authorization reached the setter")

-- Successful one-way apply.
local apply_env, apply_calls = make_environment()
local apply_snapshot = Planner.snapshot(apply_env)
local applied = Planner.apply(apply_env, apply_snapshot, VALID_AUTH)
assert_true(applied.ok, "apply succeeds")
assert_equal(applied.stage, "mutation-complete", "apply reports completion")
assert_equal(applied.mutation_authorized, true, "apply is the authorized mutation site")
assert_equal(applied.reversible, false, "apply declares itself irreversible")
assert_equal(applied.recovery, "closed-game save backup", "apply names the real recovery path")
assert_equal(apply_calls.unlock_all, 1, "apply calls UnlockAllTraits exactly once")
assert_equal(apply_calls.unlock_all_args[1], true, "bUnlock true")
assert_equal(apply_calls.unlock_all_args[2], true, "bUnblock true")
assert_equal(apply_calls.unlock_all_args[3], true, "bUnhide true")
assert_equal(apply_calls.unlock_all_args[4], false, "bUnblockNextLevelOnly false")
assert_equal(apply_calls.forbidden, 0, "apply calls no forbidden function")

-- No-op detection and regression rejection.
local noop_env = make_environment({ noop = true })
local noop_result = Planner.apply(noop_env, Planner.snapshot(noop_env), VALID_AUTH)
assert_equal(noop_result.stage, "mutation-noop", "no-op reported rather than claimed success")
assert_equal(noop_result.noop, true, "no-op flagged")

local regress_env = make_environment({ regresses = true })
local regress_result = Planner.apply(regress_env, Planner.snapshot(regress_env), VALID_AUTH)
assert_equal(regress_result.ok, false, "regression rejected")
assert_equal(regress_result.stage, "postcondition", "regression stage")

local drift_env = make_environment({ identity_drifts = true })
local drift_result = Planner.apply(drift_env, Planner.snapshot(drift_env), VALID_AUTH)
assert_equal(drift_result.ok, false, "identity drift during mutation rejected")
assert_equal(drift_result.stage, "postcondition", "identity drift stage")

local throw_env, throw_calls = make_environment({ mutation_throws = true })
local throw_result = Planner.apply(throw_env, Planner.snapshot(throw_env), VALID_AUTH)
assert_equal(throw_result.ok, false, "setter exception rejected")
assert_equal(throw_result.stage, "mutation", "setter exception stage")
assert_equal(throw_calls.reset, 0, "a failed mutation does not silently reset")

-- Reconstruct: ordering, suppression flags, and honest reporting.
local rec_env, rec_calls = make_environment()
local rec_snapshot = Planner.snapshot(rec_env)
Planner.apply(rec_env, rec_snapshot, VALID_AUTH)
local reconstructed = Planner.reconstruct(rec_env, rec_snapshot)
assert_equal(rec_calls.reset, 1, "reconstruct resets once")
assert_equal(reconstructed.exact_restore_achieved, false,
    "reconstruct never claims an exact restore")
assert_equal(reconstructed.unrestorable_fields[1], "onceBoughtLevel",
    "reconstruct names the unrestorable field")
assert_equal(reconstructed.recovery, "closed-game save backup",
    "reconstruct names the real recovery path")
assert_equal(rec_calls.set_points, 1, "reconstruct restores trait points")
assert_equal(reconstructed.trait_points_restored, true, "trait points verified restored")
assert_equal(rec_calls.forbidden, 0, "reconstruct calls no forbidden function")

-- Only traits with level > 0 are replayed, quietly, in ascending Tier then level.
assert_equal(#rec_calls.unlock_trait, 2, "only unlocked traits are replayed")
for _, call in ipairs(rec_calls.unlock_trait) do
    assert_equal(call.bought_event, false, "bought event suppressed")
    assert_equal(call.unlock_parent, false, "parent unlock suppressed")
    assert_equal(call.notification, false, "notification suppressed")
end
local previous_tier = 0
for _, call in ipairs(rec_calls.unlock_trait) do
    local tier = call.trait.Tier
    assert_true(tier >= previous_tier, "reconstruct replays in ascending tier order")
    previous_tier = tier
end

-- A partial reconstruct reports each mismatch individually instead of one boolean.
local partial_env = make_environment({ reconstruct_partial = true })
local partial_snapshot = Planner.snapshot(partial_env)
Planner.apply(partial_env, partial_snapshot, VALID_AUTH)
local partial = Planner.reconstruct(partial_env, partial_snapshot)
assert_equal(partial.ok, false, "partial reconstruct is not reported as success")
assert_true(#partial.level_mismatches >= 1, "partial reconstruct lists mismatches")
assert_true(partial.level_mismatches[1].skill_id ~= nil, "mismatch names the trait")
assert_true(partial.level_mismatches[1].expected ~= nil, "mismatch states the expected level")

-- Formatted evidence always carries the irreversibility markers.
local line = Planner.format_result(applied)
assert_match(line, "planner_id=player:unlock%-all%-skills", "formatted planner id")
assert_match(line, "release_visible=0", "formatted line stays release locked")
assert_match(line, "reversible=0", "formatted line declares irreversibility")
assert_match(Planner.format_result(snapshot), "mutation_authorized=0",
    "formatted snapshot stays unauthorized")

print("Dawnwalker unlock-all-skills planner harness passed.")
