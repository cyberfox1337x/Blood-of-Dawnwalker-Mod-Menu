local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_attack_speed_controller")

-- The native adapter must verify exact build, game thread, local-player ownership,
-- concrete mapped mode structs, and the current NPC isolation evidence before it
-- returns a context. This module is not loaded or advertised by the main bridge.
local Controller = {}
local MIN_MULTIPLIER, MAX_MULTIPLIER = 0.5, 2.0

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function finite(number)
    return type(number) == "number" and number == number and math.abs(number) < math.huge
end

local function near(left, right)
    return finite(left) and finite(right) and math.abs(left - right) <= math.max(0.00001, math.abs(right) * 0.00001)
end

local function read_mode(mode)
    local current = mode.read()
    require_condition(type(current) == "table" and finite(current.attack) and current.attack > 0
        and finite(current.strong_attack) and current.strong_attack > 0, "Attack rate readback is invalid")
    require_condition(type(current.unrelated_fingerprint) == "string" and #current.unrelated_fingerprint > 0,
        "Unrelated animation baseline is missing")
    return { attack = current.attack, strong_attack = current.strong_attack,
        unrelated_fingerprint = current.unrelated_fingerprint }
end

local function matches(current, expected)
    return near(current.attack, expected.attack) and near(current.strong_attack, expected.strong_attack)
        and current.unrelated_fingerprint == expected.unrelated_fingerprint
end

local function snapshot(context)
    require_condition(type(context) == "table" and type(context.identity) == "string" and #context.identity > 0,
        "Player/world/config identity is unavailable")
    require_condition(context.player_modes_verified == true and context.npc_isolation_verified == true,
        "Current native mode ownership and NPC isolation are not verified")
    require_condition(type(context.modes) == "table" and #context.modes == 5, "Exactly five reviewed player modes are required")
    local count = 0
    for key in pairs(context.modes) do
        require_condition(type(key) == "number" and key % 1 == 0 and key >= 1 and key <= 5,
            "Unexpected player mode key")
        count = count + 1
    end
    require_condition(count == 5, "Exactly five reviewed player modes are required")
    local records, seen = {}, {}
    for index, mode in ipairs(context.modes) do
        require_condition(mode.enum_value == index and type(mode.identity) == "string" and #mode.identity > 0,
            "Player mode identity or enum ordering changed")
        require_condition(type(mode.read) == "function" and type(mode.write_attack) == "function"
            and type(mode.write_strong_attack) == "function", "Typed native mode adapter is incomplete")
        require_condition(not seen[mode.identity], "Aliased player mode assets require a separate reviewed contract")
        seen[mode.identity] = true
        records[index] = { identity = mode.identity, adapter = mode, original = read_mode(mode) }
    end
    return { identity = context.identity, records = records, multiplier = 1.0, restore_pending = false, recovery = nil }
end

local function expected_rates(record, multiplier)
    return { attack = record.original.attack * multiplier, strong_attack = record.original.strong_attack * multiplier,
        unrelated_fingerprint = record.original.unrelated_fingerprint }
end

local function current_context(resolve, state)
    local current = snapshot(resolve())
    if state then
        require_condition(current.identity == state.identity, "Player/world/config changed; saved restoration is still pending")
        for index, record in ipairs(current.records) do
            require_condition(record.identity == state.records[index].identity, "Concrete player mode changed; saved restoration is still pending")
        end
        -- Use fresh mapped wrappers after checking identity; never retain a stale
        -- native wrapper merely because its path text is unchanged.
        for index, record in ipairs(current.records) do state.records[index].adapter = record.adapter end
    end
    return current
end

local function restore_transaction(records, journal)
    local failures = {}
    -- Preflight all fields before the inverse so an outside edit is not clobbered.
    for index, record in ipairs(records) do
        local observed = read_mode(record.adapter)
        local before, attempted = journal.before[index], journal.attempted[index]
        require_condition(observed.unrelated_fingerprint == before.unrelated_fingerprint,
            "Unrelated animations changed; recovery requires review")
        require_condition((near(observed.attack, before.attack) or near(observed.attack, attempted.attack))
            and (near(observed.strong_attack, before.strong_attack) or near(observed.strong_attack, attempted.strong_attack)),
            "Attack rates changed outside the pending transaction; recovery requires review")
    end
    for index = journal.touched, 1, -1 do
        local record = records[index]
        -- A failing first inverse must not skip restoration of the second field.
        for _, field in ipairs({ "attack", "strong_attack" }) do
            local ok, failure = pcall(record.adapter["write_" .. field], journal.before[index][field])
            if not ok then failures[#failures + 1] = record.identity .. "." .. field .. ": " .. tostring(failure) end
        end
    end
    for index, record in ipairs(records) do
        local ok, failure = pcall(function()
            require_condition(matches(read_mode(record.adapter), journal.before[index]), "Transaction inverse did not read back")
        end)
        if not ok then failures[#failures + 1] = record.identity .. ": " .. tostring(failure) end
    end
    return #failures == 0, table.concat(failures, "; ")
end

local function recover(state)
    local ok, restored, failure = pcall(restore_transaction, state.records, state.recovery)
    if not ok then failure, restored = restored, false end
    state.restore_pending = not restored
    if restored then state.recovery = nil end
    return restored, failure
end

local function apply_transaction(state, multiplier)
    local before, attempted = {}, {}
    for index, record in ipairs(state.records) do
        before[index] = read_mode(record.adapter)
        require_condition(matches(before[index], expected_rates(record, state.multiplier)),
            "Native rates or unrelated animations changed outside this controller")
        attempted[index] = expected_rates(record, multiplier)
        require_condition(finite(attempted[index].attack) and finite(attempted[index].strong_attack), "Scaled attack rate overflow")
    end
    state.recovery = { before = before, attempted = attempted, touched = 0 }
    local ok, failure = pcall(function()
        for index, record in ipairs(state.records) do
            state.recovery.touched = index
            local expected = attempted[index]
            record.adapter.write_attack(expected.attack)
            record.adapter.write_strong_attack(expected.strong_attack)
            require_condition(matches(read_mode(record.adapter), expected), "Applied attack rates did not read back exactly")
        end
        for _, record in ipairs(state.records) do
            require_condition(matches(read_mode(record.adapter), expected_rates(record, multiplier)),
                "A previously applied mode changed during the transaction")
        end
    end)
    if not ok then
        local restored, restore_error = recover(state)
        error(tostring(failure) .. (restored and "; previous rates restored" or "; restoration pending: " .. restore_error), 0)
    end
    state.multiplier, state.restore_pending, state.recovery = multiplier, false, nil
end

function Controller.new(resolve_context)
    require_condition(type(resolve_context) == "function", "A verified native context resolver is required")
    local state = nil
    local controller = {}

    function controller.read()
        local current = current_context(resolve_context, state)
        local observations = {}
        for index, record in ipairs(current.records) do
            observations[index] = { identity = record.identity, attack = record.original.attack,
                strong_attack = record.original.strong_attack }
        end
        local consistent = true
        if state then
            for index, record in ipairs(state.records) do
                if not matches(current.records[index].original, expected_rates(record, state.multiplier)) then consistent = false end
            end
        end
        local pending = state ~= nil and state.restore_pending
        return { mode_rates = observations, applied_multiplier = state and not pending and consistent and state.multiplier or nil,
            active = state ~= nil and (state.multiplier ~= 1 or pending),
            consistent = consistent and not pending, restore_pending = pending }
    end

    function controller.apply(multiplier)
        require_condition(finite(multiplier) and multiplier >= MIN_MULTIPLIER and multiplier <= MAX_MULTIPLIER,
            "Attack multiplier must be between 0.5 and 2.0")
        local current = current_context(resolve_context, state)
        if not state then state = current end
        require_condition(not state.restore_pending, "A previous native transaction still requires restoration")
        apply_transaction(state, multiplier)
        return controller.read()
    end

    function controller.restore()
        if not state then return { active = false, restored = true, restore_pending = false } end
        current_context(resolve_context, state)
        if state.restore_pending then
            local restored, failure = recover(state)
            require_condition(restored, "Restoration still pending: " .. tostring(failure))
        end
        apply_transaction(state, 1)
        state = nil
        return { active = false, restored = true, restore_pending = false }
    end

    function controller.has_pending_restore()
        return state ~= nil
    end

    return controller
end

return Controller
