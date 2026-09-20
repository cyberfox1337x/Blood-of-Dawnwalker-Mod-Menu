local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("difficulty_control_adapter")
-- Ported exact config fingerprint and two-axis ownership contract from the bridge.
-- No broad preset, persistent settings confirmation, or config-map mutation.
local M = {}
local function is_finite_number(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function is_valid(o) return o ~= nil and o:IsValid() end
local function sanitize(v) return tostring(v):sub(1, 512) end
local function get_object_address(o)
    if not is_valid(o) then return nil end
    local a = o:GetAddress(); return is_finite_number(a) and a > 0 and a or nil
end
local function object_matches_address(o, a) return a ~= nil and get_object_address(o) == a end
local function is_read_only_query(v) return tostring(v or ""):match("^%s*$") ~= nil end
local DIFFICULTY_CONFIG_PATH = "/Game/_Dawnwalker/Combat/DA_DifficultyConfig.DA_DifficultyConfig"
local RPG_DIFFICULTY_SETTING = 69
local ACTION_DIFFICULTY_SETTING = 70
local DIFFICULTY_NAMES = {
    [0] = "Story",
    [1] = "Normal",
    [2] = "Immersive",
    [3] = "Nightmare",
}

local function get_default_object(path, label)
    local ok, object = pcall(function() return StaticFindObject(path) end)
    if not ok or not is_valid(object) then return nil, "The " .. label .. " default object is unavailable." end
    return object, nil
end

local function get_subsystem(context, class_path, scope, label)
    local library, library_error = get_default_object("/Script/Engine.Default__SubsystemBlueprintLibrary", "subsystem library")
    if not library then return nil, library_error end

    local ok, subsystem_class = pcall(function() return StaticFindObject(class_path) end)
    if not ok or not is_valid(subsystem_class) then return nil, "The " .. label .. " class is unavailable." end

    local subsystem_ok, subsystem = pcall(function()
        if scope == "world" then return library:GetWorldSubsystem(context, subsystem_class) end
        return library:GetGameInstanceSubsystem(context, subsystem_class)
    end)
    if not subsystem_ok or not is_valid(subsystem) then return nil, "The live " .. label .. " is unavailable." end

    local class_ok, matches = pcall(function() return subsystem:IsA(class_path) end)
    if not class_ok or not matches then return nil, "The resolved " .. label .. " has the wrong class." end
    return subsystem, nil
end

function M.Init(menu, helpers)
local active, difficulty_override = {}, nil
local failed, refreshed = false, false
local id = "DWCoreDifficulty"
local fields = {}
local function get_live_player_context()
    local player = helpers.GetPlayer()
    if not is_valid(player) then return nil, nil, "Load a controlled player first" end
    local world, controller = player:GetWorld(), player.Controller
    if not is_valid(world) or not is_valid(controller) or not object_matches_address(controller.Pawn, get_object_address(player)) then
        return nil, nil, "Controlled player/world identity unavailable"
    end
    return player, { player = player, player_address = get_object_address(player), world = world, world_address = get_object_address(world) }
end
local function unwrap_remote_value(value)
    if value == nil then return nil end
    local unwrap_ok, unwrapped = pcall(function() return value:get() end)
    if unwrap_ok then return unwrapped end
    return value
end

local function object_full_name(object)
    if not is_valid(object) then return nil end
    local name_ok, name = pcall(function() return object:GetFullName() end)
    if not name_ok or type(name) ~= "string" or name == "" then return nil end
    return name
end

local function exact_string(value)
    local unwrapped = unwrap_remote_value(value)
    if type(unwrapped) == "string" then return unwrapped end
    local string_ok, converted = pcall(function() return unwrapped:ToString() end)
    if string_ok and type(converted) == "string" then return converted end
    return nil
end

local function difficulty_value(value)
    local unwrapped = unwrap_remote_value(value)
    local numeric = tonumber(unwrapped)
    if is_finite_number(numeric) and numeric % 1 == 0 and DIFFICULTY_NAMES[numeric] ~= nil then
        return math.floor(numeric)
    end

    local normalized = tostring(unwrapped or ""):lower():match("^%s*(.-)%s*$")
    for candidate, name in pairs(DIFFICULTY_NAMES) do
        local exact_name = name:lower()
        if normalized == exact_name or normalized == "erebelgamedifficulty::" .. exact_name then
            return candidate
        end
    end
    return nil
end

local function parse_difficulty_request(value)
    if is_read_only_query(value) then return nil end
    return difficulty_value(value)
end

local function fingerprint_float(value)
    local numeric = tonumber(unwrap_remote_value(value))
    if not is_finite_number(numeric) then return nil end
    return string.format("%.9g", numeric)
end

local function fingerprint_boolean(value)
    local unwrapped = unwrap_remote_value(value)
    if type(unwrapped) ~= "boolean" then return nil end
    return unwrapped and "1" or "0"
end

local function object_identity_fingerprint(object)
    local address = get_object_address(object)
    local name = object_full_name(object)
    if address == nil or name == nil then return nil end
    return tostring(#name) .. ":" .. name .. "@" .. address
end

local function fingerprint_rpg_settings(settings)
    local read_ok, health, damage, stamina = pcall(function()
        return settings.HealthMultiplier, settings.DamageMultiplier, settings.PlayerCombatStaminaCostsMultiplier
    end)
    if not read_ok then return nil, "RPG difficulty settings fields were unavailable." end
    local fields = {
        fingerprint_float(health),
        fingerprint_float(damage),
        fingerprint_float(stamina),
    }
    if fields[1] == nil or fields[2] == nil or fields[3] == nil then
        return nil, "RPG difficulty settings contained a non-finite multiplier."
    end
    return table.concat(fields, "|"), nil
end

local function fingerprint_parry_windows(parry_windows)
    local entries = {}
    local function capture_entry(key_parameter, value_parameter)
        local key = exact_string(key_parameter)
        local value = fingerprint_float(value_parameter)
        if key == nil or key == "" or value == nil then
            error("Action difficulty parry-window entry was invalid.")
        end
        if #entries >= 32 then error("Action difficulty parry-window map exceeded its safety bound.") end
        table.insert(entries, tostring(#key) .. ":" .. key .. "=" .. value)
    end

    local iterate_ok, iterate_error = pcall(function()
        if type(parry_windows) == "table" then
            for key_parameter, value_parameter in pairs(parry_windows) do
                capture_entry(key_parameter, value_parameter)
            end
            return
        end

        local count_ok, expected_count = pcall(function() return #parry_windows end)
        if not count_ok or not is_finite_number(expected_count) or expected_count % 1 ~= 0
            or expected_count < 0 or expected_count > 32 then
            error("Action difficulty parry-window map had an invalid size.")
        end
        local method_ok, for_each = pcall(function() return parry_windows.ForEach end)
        if method_ok and type(for_each) == "function" then
            for_each(parry_windows, function(key_parameter, value_parameter)
                capture_entry(key_parameter, value_parameter)
            end)
            if #entries ~= expected_count then
                error("Action difficulty parry-window iteration was incomplete.")
            end
            return
        end

        error("Action difficulty parry-window map used an unsupported container ABI.")
    end)
    if not iterate_ok then return nil, "Action difficulty parry-window iteration failed: " .. sanitize(iterate_error) end
    table.sort(entries)
    return tostring(#entries) .. ":" .. table.concat(entries, ","), nil
end

local function fingerprint_action_settings(settings)
    local read_ok, attack_speed, parry_windows, auto_block, best_node, attacking,
        parry_reaction, block_reaction, omniblock_reaction, helper_cooldown,
        low_health_cooldown, ranged_cooldown, global_scaling = pcall(function()
            return settings.AttackAnimationSpeedMultiplier,
                settings.ParryWindowMultipliers,
                settings.AutoSelectBlockDirection,
                settings.bAllowAttackingWhileAnotherNPCIsPerformingBestNodeInject,
                settings.bAllowAttackingWhileAnotherNPCIsAttacking,
                settings.bAllowAttackingWhileAnotherNPCIsInParryReaction,
                settings.bAllowAttackingWhileAnotherNPCIsInBlockReaction,
                settings.bAllowAttackingWhileAnotherNPCIsInOmniblockReaction,
                settings.HelperTicketCooldownMultiplier,
                settings.LowHealthHelperTicketCooldownMultiplier,
                settings.HelperRangedAttackCooldownMultiplier,
                settings.GlobalAILevelScaling
        end)
    if not read_ok then return nil, "Action difficulty settings fields were unavailable." end

    local parry_fingerprint, parry_error = fingerprint_parry_windows(parry_windows)
    if not parry_fingerprint then return nil, parry_error end
    local fields = {
        fingerprint_float(attack_speed),
        parry_fingerprint,
        fingerprint_boolean(auto_block),
        fingerprint_boolean(best_node),
        fingerprint_boolean(attacking),
        fingerprint_boolean(parry_reaction),
        fingerprint_boolean(block_reaction),
        fingerprint_boolean(omniblock_reaction),
        fingerprint_float(helper_cooldown),
        fingerprint_float(low_health_cooldown),
        fingerprint_float(ranged_cooldown),
        object_identity_fingerprint(global_scaling),
    }
    for index = 1, 12 do
        if fields[index] == nil then return nil, "Action difficulty settings contained an invalid semantic field." end
    end
    return table.concat(fields, "|"), nil
end

local function read_map_settings(map, level, fingerprint, label)
    local contains_ok, contains = pcall(function() return map:Contains(level) end)
    if not contains_ok or contains ~= true then
        return nil, label .. " config does not contain " .. sanitize(DIFFICULTY_NAMES[level]) .. "."
    end
    local find_ok, parameter = pcall(function() return map:Find(level) end)
    if not find_ok or parameter == nil then return nil, label .. " config lookup failed." end
    return fingerprint(unwrap_remote_value(parameter))
end

local function read_config_fingerprints(config)
    local maps_ok, action_map, rpg_map = pcall(function()
        return config.ActionDifficulties, config.RPGDifficulties
    end)
    if not maps_ok or action_map == nil or rpg_map == nil then
        return nil, nil, "The difficulty config maps were unavailable."
    end

    local action_fingerprints = {}
    local rpg_fingerprints = {}
    for level = 0, 3 do
        local action_fingerprint, action_error = read_map_settings(
            action_map,
            level,
            fingerprint_action_settings,
            "Action difficulty"
        )
        if not action_fingerprint then return nil, nil, action_error end
        local rpg_fingerprint, rpg_error = read_map_settings(
            rpg_map,
            level,
            fingerprint_rpg_settings,
            "RPG difficulty"
        )
        if not rpg_fingerprint then return nil, nil, rpg_error end
        action_fingerprints[level] = action_fingerprint
        rpg_fingerprints[level] = rpg_fingerprint
    end
    return action_fingerprints, rpg_fingerprints, nil
end

local function read_owner_difficulty(settings, setting, label)
    local output = {}
    local call_ok, succeeded = pcall(function()
        return settings:GetSettingAsDifficulty(setting, output)
    end)
    local level = difficulty_value(output.OutDifficulty)
    if not call_ok or succeeded ~= true or level == nil then
        return nil, label .. " owner setting readback failed."
    end
    return level, nil
end

local function get_combat_difficulty_context()
    local player, identity, player_error = get_live_player_context()
    if not player then return nil, player_error end
    local subsystem, subsystem_error = get_subsystem(
        player,
        "/Script/DogwoodCombat.CombatSubsystem",
        "world",
        "combat subsystem"
    )
    if not subsystem then return nil, subsystem_error end

    local subsystem_name = object_full_name(subsystem)
    local subsystem_address = get_object_address(subsystem)
    local subsystem_world_ok, subsystem_world = pcall(function() return subsystem:GetWorld() end)
    if subsystem_name == nil or subsystem_name:find("Default__", 1, true) ~= nil or subsystem_address == nil
        or not subsystem_world_ok or not object_matches_address(subsystem_world, identity.world_address) then
        return nil, "The combat subsystem did not match the live world identity."
    end

    local config_ok, config = pcall(function() return subsystem.DifficultyConfig end)
    local config_class_ok, config_class_matches = pcall(function()
        return config:IsA("/Script/DogwoodStats.DifficultyConfig")
    end)
    local config_name = object_full_name(config)
    local config_address = get_object_address(config)
    if not config_ok or not is_valid(config) or not config_class_ok or not config_class_matches
        or config_name == nil or config_name:find(DIFFICULTY_CONFIG_PATH, 1, true) == nil or config_address == nil then
        return nil, "The assigned live difficulty config did not match the pinned build asset."
    end

    local settings_default, settings_default_error = get_default_object(
        "/Script/RebelSettings.Default__RebelGameUserSettings",
        "game user settings"
    )
    if not settings_default then return nil, settings_default_error end
    local settings_ok, settings = pcall(function() return settings_default:Get() end)
    local settings_class_ok, settings_class_matches = pcall(function()
        return settings:IsA("/Script/RebelSettings.RebelGameUserSettings")
    end)
    local settings_name = object_full_name(settings)
    local settings_address = get_object_address(settings)
    if not settings_ok or not is_valid(settings) or not settings_class_ok or not settings_class_matches
        or settings_name == nil or settings_name:find("Default__", 1, true) ~= nil or settings_address == nil then
        return nil, "The live Rebel game user settings singleton was unavailable."
    end

    return {
        player = player,
        player_address = identity.player_address,
        world = identity.world,
        world_address = identity.world_address,
        subsystem = subsystem,
        subsystem_address = subsystem_address,
        subsystem_name = subsystem_name,
        config = config,
        config_address = config_address,
        config_name = config_name,
        settings = settings,
        settings_address = settings_address,
        settings_name = settings_name,
    }, nil
end

local function read_difficulty_state(context)
    local action_getter_ok, action_getter = pcall(function()
        return context.subsystem:GetActionDifficultyLevel()
    end)
    local property_ok, action_property, rpg_property = pcall(function()
        return context.subsystem.ActionDifficultyLevel, context.subsystem.RPGDifficultyLevel
    end)
    local action = difficulty_value(action_getter)
    local reflected_action = difficulty_value(action_property)
    local rpg = difficulty_value(rpg_property)
    if not action_getter_ok or not property_ok or action == nil or reflected_action ~= action or rpg == nil then
        return nil, "The two-axis difficulty level readback was invalid or inconsistent."
    end

    local config_action, config_rpg, config_error = read_config_fingerprints(context.config)
    if not config_action then return nil, config_error end
    local getters_ok, action_settings, rpg_settings = pcall(function()
        return unwrap_remote_value(context.subsystem:GetActionDifficultySettings()),
            unwrap_remote_value(context.subsystem:GetRPGDifficultySettings())
    end)
    if not getters_ok then return nil, "The active difficulty settings readback failed." end
    local action_fingerprint, action_error = fingerprint_action_settings(action_settings)
    if not action_fingerprint then return nil, action_error end
    local rpg_fingerprint, rpg_error = fingerprint_rpg_settings(rpg_settings)
    if not rpg_fingerprint then return nil, rpg_error end
    if action_fingerprint ~= config_action[action] or rpg_fingerprint ~= config_rpg[rpg] then
        return nil, "The active difficulty settings did not match their assigned config entries."
    end

    local owner_action, owner_action_error = read_owner_difficulty(
        context.settings,
        ACTION_DIFFICULTY_SETTING,
        "Action difficulty"
    )
    if owner_action == nil then return nil, owner_action_error end
    local owner_rpg, owner_rpg_error = read_owner_difficulty(
        context.settings,
        RPG_DIFFICULTY_SETTING,
        "RPG difficulty"
    )
    if owner_rpg == nil then return nil, owner_rpg_error end

    return {
        action = action,
        rpg = rpg,
        action_fingerprint = action_fingerprint,
        rpg_fingerprint = rpg_fingerprint,
        config_action = config_action,
        config_rpg = config_rpg,
        owner_action = owner_action,
        owner_rpg = owner_rpg,
    }, nil
end

local function fingerprint_tables_match(left, right)
    if left == nil or right == nil then return false end
    for level = 0, 3 do
        if left[level] ~= right[level] then return false end
    end
    return true
end

local function difficulty_binding_matches(record, context)
    if record == nil or context == nil then return false end
    if not object_matches_address(record.player, record.player_address)
        or not object_matches_address(record.world, record.world_address)
        or not object_matches_address(record.subsystem, record.subsystem_address)
        or not object_matches_address(record.config, record.config_address)
        or not object_matches_address(record.settings, record.settings_address) then
        return false
    end
    local world_ok, subsystem_world = pcall(function() return record.subsystem:GetWorld() end)
    return world_ok and object_matches_address(subsystem_world, record.world_address)
        and context.player_address == record.player_address
        and context.world_address == record.world_address
        and context.subsystem_address == record.subsystem_address
        and context.subsystem_name == record.subsystem_name
        and context.config_address == record.config_address
        and context.config_name == record.config_name
        and context.settings_address == record.settings_address
        and context.settings_name == record.settings_name
end

local function difficulty_record_binding_is_live(record)
    if record == nil or not object_matches_address(record.player, record.player_address)
        or not object_matches_address(record.world, record.world_address)
        or not object_matches_address(record.subsystem, record.subsystem_address)
        or not object_matches_address(record.config, record.config_address)
        or not object_matches_address(record.settings, record.settings_address) then
        return false
    end
    if object_full_name(record.subsystem) ~= record.subsystem_name
        or object_full_name(record.config) ~= record.config_name
        or object_full_name(record.settings) ~= record.settings_name then
        return false
    end
    local world_ok, subsystem_world = pcall(function() return record.subsystem:GetWorld() end)
    return world_ok and object_matches_address(subsystem_world, record.world_address)
end

local function difficulty_record_context(record)
    return {
        player = record.player,
        player_address = record.player_address,
        world = record.world,
        world_address = record.world_address,
        subsystem = record.subsystem,
        subsystem_address = record.subsystem_address,
        subsystem_name = record.subsystem_name,
        config = record.config,
        config_address = record.config_address,
        config_name = record.config_name,
        settings = record.settings,
        settings_address = record.settings_address,
        settings_name = record.settings_name,
    }
end

local function difficulty_state_matches_record(record, state)
    return state.owner_action == record.owner_action
        and state.owner_rpg == record.owner_rpg
        and fingerprint_tables_match(state.config_action, record.config_action)
        and fingerprint_tables_match(state.config_rpg, record.config_rpg)
end

local function refresh_difficulty_active(record)
    active["combat:rpg-difficulty"] = record ~= nil and record.expected_rpg ~= record.baseline_rpg or nil
    active["combat:action-difficulty"] = record ~= nil and record.expected_action ~= record.baseline_action or nil
end

local function capture_difficulty_override(context, state)
    if state.action ~= state.owner_action or state.rpg ~= state.owner_rpg then
        return nil, "The live difficulty axes are already owned by another runtime override."
    end
    return {
        player = context.player,
        player_address = context.player_address,
        world = context.world,
        world_address = context.world_address,
        subsystem = context.subsystem,
        subsystem_address = context.subsystem_address,
        subsystem_name = context.subsystem_name,
        config = context.config,
        config_address = context.config_address,
        config_name = context.config_name,
        settings = context.settings,
        settings_address = context.settings_address,
        settings_name = context.settings_name,
        baseline_action = state.action,
        baseline_rpg = state.rpg,
        expected_action = state.action,
        expected_rpg = state.rpg,
        expected_action_fingerprint = state.action_fingerprint,
        expected_rpg_fingerprint = state.rpg_fingerprint,
        owner_action = state.owner_action,
        owner_rpg = state.owner_rpg,
        config_action = state.config_action,
        config_rpg = state.config_rpg,
        owned_action_values = { [state.action] = true },
        owned_rpg_values = { [state.rpg] = true },
    }, nil
end

local function restore_difficulty_override()
    local record = difficulty_override
    if record == nil then return true, nil end
    if not difficulty_record_binding_is_live(record) then
        return false, "the retained Combat difficulty binding is no longer live in its original world"
    end

    local context = difficulty_record_context(record)
    local state, state_error = read_difficulty_state(context)
    if not state then return false, state_error end
    if not fingerprint_tables_match(state.config_action, record.config_action)
        or not fingerprint_tables_match(state.config_rpg, record.config_rpg) then
        return false, "the live difficulty config changed; no rollback setter was called"
    end

    if state.owner_action ~= record.owner_action or state.owner_rpg ~= record.owner_rpg then
        if state.action == state.owner_action and state.rpg == state.owner_rpg then
            difficulty_override = nil
            refresh_difficulty_active(nil)
            return true, nil
        end
        return false, "the game settings owner changed without reclaiming both axes; no rollback setter was called"
    end

    local rpg_safe = state.rpg == record.baseline_rpg or record.owned_rpg_values[state.rpg] == true
    local action_safe = state.action == record.baseline_action or record.owned_action_values[state.action] == true
    local rpg_set_ok, rpg_set_error = true, nil
    local action_set_ok, action_set_error = true, nil

    if rpg_safe and state.rpg ~= record.baseline_rpg then
        rpg_set_ok, rpg_set_error = pcall(function()
            record.subsystem:SetRPGDifficulty(record.baseline_rpg)
        end)
    end
    if action_safe and state.action ~= record.baseline_action then
        action_set_ok, action_set_error = pcall(function()
            record.subsystem:SetActionDifficulty(record.baseline_action)
        end)
    end

    local restored_state, restored_error = nil, "the Combat difficulty binding changed during rollback"
    if difficulty_record_binding_is_live(record) then
        restored_state, restored_error = read_difficulty_state(context)
    end
    if restored_state ~= nil and difficulty_state_matches_record(record, restored_state) then
        if restored_state.rpg == record.baseline_rpg
            and restored_state.rpg_fingerprint == record.config_rpg[record.baseline_rpg] then
            record.expected_rpg = record.baseline_rpg
            record.expected_rpg_fingerprint = restored_state.rpg_fingerprint
            record.owned_rpg_values = { [record.baseline_rpg] = true }
            active["combat:rpg-difficulty"] = nil
        end
        if restored_state.action == record.baseline_action
            and restored_state.action_fingerprint == record.config_action[record.baseline_action] then
            record.expected_action = record.baseline_action
            record.expected_action_fingerprint = restored_state.action_fingerprint
            record.owned_action_values = { [record.baseline_action] = true }
            active["combat:action-difficulty"] = nil
        end
    end

    if record.expected_rpg == record.baseline_rpg and record.expected_action == record.baseline_action then
        difficulty_override = nil
        refresh_difficulty_active(nil)
        return true, nil
    end

    refresh_difficulty_active(record)
    return false, "RPG safe=" .. sanitize(rpg_safe)
        .. ", RPG setter=" .. sanitize(rpg_set_error or rpg_set_ok)
        .. ", Action safe=" .. sanitize(action_safe)
        .. ", Action setter=" .. sanitize(action_set_error or action_set_ok)
        .. ", readback=" .. sanitize(restored_error or "did not match both baselines")
end

local function handle_difficulty_axis(axis, value)
    local query_only = is_read_only_query(value)
    local requested = parse_difficulty_request(value)
    if not query_only and requested == nil then
        return false, "rejected", "Difficulty requires Story, Normal, Immersive, Nightmare, or an exact value from 0 to 3.", ""
    end

    local context, context_error = get_combat_difficulty_context()
    if not context then return false, "rejected", context_error, "" end
    local state, state_error = read_difficulty_state(context)
    if not state then return false, "rejected", state_error, "" end
    local current = axis == "rpg" and state.rpg or state.action
    local label = axis == "rpg" and "RPG Difficulty" or "Action Difficulty"
    if query_only then
        return true, "applied", label .. " read as " .. DIFFICULTY_NAMES[current] .. ".", tostring(current)
    end

    local record = difficulty_override
    if record ~= nil then
        if not difficulty_binding_matches(record, context) then
            return false, "rejected", "A retained Combat difficulty rollback belongs to another live identity.", ""
        end
        if not difficulty_state_matches_record(record, state)
            or state.rpg ~= record.expected_rpg
            or state.action ~= record.expected_action
            or state.rpg_fingerprint ~= record.expected_rpg_fingerprint
            or state.action_fingerprint ~= record.expected_action_fingerprint then
            local restored, restore_error = restore_difficulty_override()
            return false, "rejected", "Combat difficulty ownership changed before mutation; rollback="
                .. sanitize(restored and "verified" or restore_error) .. ". Retry only after a clean readback.", ""
        end
    elseif requested == current then
        return true, "applied", label .. " is already " .. DIFFICULTY_NAMES[current] .. ".", tostring(current)
    else
        record, state_error = capture_difficulty_override(context, state)
        if not record then return false, "rejected", state_error, "" end
        difficulty_override = record
    end

    if requested == current then
        return true, "applied", label .. " is already " .. DIFFICULTY_NAMES[current] .. ".", tostring(current)
    end

    local previous_rpg = record.expected_rpg
    local previous_action = record.expected_action
    if axis == "rpg" then
        record.owned_rpg_values[requested] = true
    else
        record.owned_action_values[requested] = true
    end
    local set_ok, set_error = pcall(function()
        if axis == "rpg" then record.subsystem:SetRPGDifficulty(requested)
        else record.subsystem:SetActionDifficulty(requested) end
    end)

    local after_context, after_context_error = get_combat_difficulty_context()
    local after_state, after_state_error = nil, nil
    if after_context ~= nil and difficulty_binding_matches(record, after_context) then
        after_state, after_state_error = read_difficulty_state(after_context)
    else
        after_state_error = after_context_error or "The Combat difficulty identity changed after the setter."
    end
    local target_matches = after_state ~= nil
        and (axis == "rpg" and after_state.rpg == requested or axis == "action" and after_state.action == requested)
    local other_matches = after_state ~= nil
        and (axis == "rpg" and after_state.action == previous_action or axis == "action" and after_state.rpg == previous_rpg)
    local ownership_matches = after_state ~= nil and difficulty_state_matches_record(record, after_state)
    if set_ok and target_matches and other_matches and ownership_matches then
        if axis == "rpg" then
            record.expected_rpg = requested
            record.expected_rpg_fingerprint = after_state.rpg_fingerprint
            record.owned_rpg_values = { [record.baseline_rpg] = true, [requested] = true }
        else
            record.expected_action = requested
            record.expected_action_fingerprint = after_state.action_fingerprint
            record.owned_action_values = { [record.baseline_action] = true, [requested] = true }
        end
        if record.expected_rpg == record.baseline_rpg and record.expected_action == record.baseline_action then
            difficulty_override = nil
            refresh_difficulty_active(nil)
        else
            refresh_difficulty_active(record)
        end
        return true, "applied", label .. " set to " .. DIFFICULTY_NAMES[requested]
            .. " with exact config and owner readback.", tostring(requested)
    end

    local restored, restore_error = restore_difficulty_override()
    return false, "rejected", label .. " did not pass exact two-axis readback ("
        .. sanitize(set_error or after_state_error or "value mismatch") .. "); rollback="
        .. sanitize(restored and "verified" or restore_error) .. ".", ""
end


local function sync(message)
    menu.Set(id, "owned", difficulty_override ~= nil)
    menu.SetLabel(id, "status", message)
end
local function captureReadback()
    local context, err = get_combat_difficulty_context(); assert(context, err)
    local state, failure = read_difficulty_state(context); assert(state, failure)
    local after, afterError = get_combat_difficulty_context(); assert(after, afterError)
    assert(context.player_address == after.player_address and context.world_address == after.world_address
        and context.subsystem_address == after.subsystem_address and context.config_address == after.config_address
        and context.settings_address == after.settings_address, "Difficulty identity changed during capture")
    menu.Set(id, "rpg", state.rpg); menu.Set(id, "action", state.action)
    return state
end
local function refresh()
    local ok, state = pcall(captureReadback)
    refreshed = ok and not failed
    fields.rpg.enabled, fields.action.enabled = refreshed, refreshed
    sync(ok and "Difficulty axes read from the current game settings." or "Difficulty readback unavailable. Load a save and refresh.")
    assert(ok, state)
end
local function restore()
    local ok, err = restore_difficulty_override()
    if not ok then failed = true; fields.rpg.enabled = false; fields.action.enabled = false end
    sync(ok and "Original difficulty axes restored." or "STOP: difficulty cleanup remains unresolved. Restart and reload the save.")
    assert(ok, err)
    captureReadback()
end
local function setAxis(axis, value)
    ExecuteInGameThread(function()
        assert(refreshed and not failed, "Refresh and verify the current difficulty settings first")
        local callOk, accepted, _, message = pcall(handle_difficulty_axis, axis, value)
        if not callOk or not accepted then
            failed = true; fields.rpg.enabled = false; fields.action.enabled = false
            local restored, restoreError = pcall(restore)
            sync(restored and "Difficulty change failed; original axes restored." or "STOP: difficulty rollback remains unresolved.")
            error(tostring(callOk and message or accepted) .. (restored and "" or "; " .. tostring(restoreError)))
        end
        -- Publish ownership before a later getter can fail, so close still visits
        -- the retained rollback record even after post-set readback errors.
        sync(message); captureReadback()
    end)
end
function M.ResetSession()
    refreshed = false
    fields.rpg.enabled, fields.action.enabled = false, false
    assert(not difficulty_override, "Cannot discard unresolved difficulty ownership")
    sync("Refresh to read the current difficulty axes.")
end

-- Both selectors stay disabled until a readback proves what the game currently has, so
-- without this they sit on "Awaiting readback" for the entire session and read as broken.
-- Doing that read when the session comes up costs exactly the work the Refresh button
-- already does, and it is the same work the player would have had to ask for by hand.
--
-- A failure deliberately propagates: refresh() has already published its own "readback
-- unavailable" status, and the runtime retries a failing SessionReady on later ticks,
-- which is what covers a pawn that exists a moment before its subsystems resolve.
local function cyberfox1337x_ReadDifficultyOnSessionStart()
    if refreshed or failed then return end
    -- Deliberately not refresh(): that publishes a failure status, and this read runs
    -- unprompted on the runtime tick. A pawn can exist a moment before the difficulty
    -- subsystem resolves, so an early attempt must leave the panel exactly as it was -
    -- the standing "Refresh to read the current difficulty axes." is still the correct
    -- and actionable message - and let the runtime retry. Only success publishes.
    local ok, failure = pcall(captureReadback)
    if not ok then error(failure, 0) end
    refreshed = true
    fields.rpg.enabled, fields.action.enabled = true, true
    sync("Difficulty axes read from the current game settings.")
end

-- Named to match the ResetSession contract the runtime already looks up by convention.
M.SessionReady = cyberfox1337x_ReadDifficultyOnSessionStart
local options = {}
for value = 0, 3 do options[#options + 1] = { label = DIFFICULTY_NAMES[value], value = value } end
for _, axis in ipairs({ "rpg", "action" }) do
    fields[axis] = { type = "dropdown", id = axis, label = axis == "rpg" and "RPG Difficulty" or "Action Difficulty",
        options = options, default = 1, enabled = false, onChange = function(v) setAxis(axis, v) end }
end
menu.Register({ id = id, title = "Difficulty", tab = "Player", items = {
    fields.rpg, fields.action,
    { type = "button", id = "refresh", label = "Read difficulty", onClick = refresh },
    { type = "button", id = "restore", label = "Restore difficulty", onClick = function() ExecuteInGameThread(restore) end },
    { type = "checkbox", id = "owned", label = "Difficulty override active", default = false,
      onChange = function(v) assert(v == false, "Use the independent difficulty selectors"); ExecuteInGameThread(restore) end },
    { type = "label", id = "status", label = "Refresh to verify the current difficulty axes." },
} })
end
return M
