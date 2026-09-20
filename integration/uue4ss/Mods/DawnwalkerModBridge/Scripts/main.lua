local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_mod_bridge")
cyberfox1337x.function_signature("bridge_bootstrap")

local BRIDGE_PROTOCOL = "1"
local BRIDGE_VERSION = "0.3.21-pilot"
local BRIDGE_PHASE = "pilot"
local BRIDGE_ROOT = (os.getenv("TEMP") or os.getenv("TMP") or ".") .. "/DawnwalkerModMenuBridge"
local COMMAND_PATH = BRIDGE_ROOT .. "/command.txt"
local RESPONSE_PATH = BRIDGE_ROOT .. "/response.txt"
local READY_PATH = BRIDGE_ROOT .. "/ready.txt"
local BOOT_ID = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local CAPABILITY_LIST = {
    "player:infinite-health",
    "player:unlimited-stamina",
    "player:blood-energy",
    "player:god-mode",
    "player:player-info",
    "player:trait-points",
    "player:add-gold",
    "inventory:add-item",
    "player:add-level",
    "player:unblock-trait",
    "combat:infinite-blood-energy",
    "combat:rpg-difficulty",
    "combat:action-difficulty",
    "quests:journal-readback",
    "teleport:save-location",
    "teleport:teleport-saved-location",
    "visuals:hud-visible",
    "world:game-speed",
    "world:location-readback",
}
local CAPABILITY_SET = {}
for _, capability in ipairs(CAPABILITY_LIST) do CAPABILITY_SET[capability] = true end
local CAPABILITIES = table.concat(CAPABILITY_LIST, ",")

local last_command_id = ""
-- 0.3.21: Unblock Trait commits its unblocked level a beat after UnblockTraitToLevel returns
-- in the live game (proved on 0.3.20: the same-dispatch readback stayed at the pre-call value
-- while the next dispatch read the exact requested level), so an ambiguous post-call readback
-- is deferred to a bounded later-tick verification instead of being reported as a failure.
local current_request_id = ""
local pending_unblock_verify = nil
local unblock_verify_queued = false
local MAX_UNBLOCK_VERIFY_TICKS = 40 -- ~6 s at the 150 ms poll cadence
local last_ready_second = -1
local game_thread_available = false
local player_ready = false
local player_address = nil
local world_address = nil
local probe_pending = false
local last_probe_second = -1
local active = {}
local snapshots = {}
local difficulty_override = nil
local saved_locations = {}
local teardown_retry_pending = false
local MAX_TEARDOWN_OPERATIONS = 8
local MAX_QUESTS = 6
local MAX_OBJECTIVES_PER_QUEST = 3
local MAX_QUEST_TEXT_ENCODED_BYTES = 240
local MAX_QUEST_READBACK_BYTES = 8192
local COIN_CURRENCY_TYPE = 0
local MAX_GOLD_DELTA = 10000
-- Add Item is bounded far tighter than Gold because each unit is a distinct object the
-- inventory must allocate, and because the first pilot has no stacking evidence.
local MAX_ITEM_QUANTITY = 100
local ITEM_ASSET_CLASS = "/Script/DogwoodInventory.ItemBaseDataAsset"
local ITEM_LIBRARY_CDO = "/Script/DogwoodInventory.Default__InventoryBlueprintFunctionLibrary"
-- Only loaded assets under the shipped item root are addressable. The bridge never calls
-- StaticLoadObject, so an asset the running game has not loaded is rejected rather than
-- pulled in.
local ITEM_ASSET_PREFIX = "/Game/_Dawnwalker/Inventory/Items/"
-- Quest items are refused outright: granting or destroying one can desynchronise quest
-- state, and the pilot has no evidence that quest bookkeeping tolerates it.
local ITEM_QUEST_MARKER = "ITM_Quest_"
local DEFAULT_ITEM_LEVEL = 1
-- Character level and trait unblocking are forward-only: the pinned build exposes no
-- inverse for either, and both are save-backed through ISaveGameInterface. Trait ids are
-- resolved against the live roster before any call because GetTrait, GetTraitUnblockedLevel,
-- and UnblockTraitToLevel all take `const FName&`, which the pinned UE4SS build refuses to
-- marshal from a raw Lua string (a live probe crashed the game with an access violation);
-- the bridge therefore only ever passes a Skill_ID value read back from a trait asset.
local MAX_CHARACTER_LEVEL = 100
local MAX_TRAIT_UNBLOCK_LEVEL = 10
-- Bounded so a corrupt or hostile roster container can never spin the game thread.
local MAX_TRAIT_ROSTER = 4096
local CHAR_DEV_SUBSYSTEM_PATH = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"
local TRAIT_ASSET_PATH = "/Script/DogwoodCharacterDevelopment.TraitAsset"
local INT32_MAX = 2147483647
local DIFFICULTY_CONFIG_PATH = "/Game/_Dawnwalker/Combat/DA_DifficultyConfig.DA_DifficultyConfig"
local RPG_DIFFICULTY_SETTING = 69
local ACTION_DIFFICULTY_SETTING = 70
local DIFFICULTY_NAMES = {
    [0] = "Story",
    [1] = "Normal",
    [2] = "Immersive",
    [3] = "Nightmare",
}

local function new_resource_state()
    return {
        owners = {},
        baseline = nil,
        target = nil,
        target_address = nil,
        player = nil,
        player_address = nil,
        world = nil,
        world_address = nil,
    }
end

local resource_locks = {
    health = new_resource_state(),
    stamina = new_resource_state(),
    blood = new_resource_state(),
}

local function log(message)
    print(string.format("[DawnwalkerModBridge] %s\n", tostring(message)))
end

local function sanitize(value)
    return tostring(value or ""):gsub("[\r\n]", " ")
end

cyberfox1337x.function_signature("local_file_transport")
local function write_atomic(path, contents)
    local temporary_path = path .. ".tmp"
    local file = io.open(temporary_path, "w")
    if file then
        file:write(contents)
        file:flush()
        file:close()
        os.remove(path)
        if os.rename(temporary_path, path) ~= nil then return true end
    end

    local fallback = io.open(path, "w")
    if not fallback then return false end
    fallback:write(contents)
    fallback:flush()
    fallback:close()
    return true
end

local function read_fields(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local fields = {}
    for line in file:lines() do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key then fields[key] = value end
    end
    file:close()
    return fields
end

local function is_valid(object)
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

local function is_finite_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function get_object_address(object)
    if not is_valid(object) then return nil end
    local ok, address = pcall(function() return object:GetAddress() end)
    if not ok or not is_finite_number(address) or address <= 0 then return nil end
    return tostring(address)
end

local function object_matches_address(object, expected_address)
    return expected_address ~= nil and get_object_address(object) == expected_address
end

local function clear_session_state()
    active = {}
    snapshots = {}
    difficulty_override = nil
    saved_locations = {}
    teardown_retry_pending = false
    pending_unblock_verify = nil
    unblock_verify_queued = false
    resource_locks = {
        health = new_resource_state(),
        stamina = new_resource_state(),
        blood = new_resource_state(),
    }
end

local function session_state_has_pending_restore()
    if next(snapshots) ~= nil then return true end
    if difficulty_override ~= nil then return true end
    for _, resource in pairs(resource_locks) do
        if resource.baseline ~= nil or next(resource.owners) ~= nil then return true end
    end
    return false
end

local function retain_only_pending_active_state()
    local pending_active = {}
    for _, resource in pairs(resource_locks) do
        for owner, enabled in pairs(resource.owners) do
            if enabled then pending_active[owner] = true end
        end
    end
    for capability, snapshot in pairs(snapshots) do
        if snapshot ~= nil then pending_active[capability] = true end
    end
    if difficulty_override ~= nil then
        if difficulty_override.expected_rpg ~= difficulty_override.baseline_rpg then
            pending_active["combat:rpg-difficulty"] = true
        end
        if difficulty_override.expected_action ~= difficulty_override.baseline_action then
            pending_active["combat:action-difficulty"] = true
        end
    end
    active = pending_active
end

local function active_capabilities()
    local names = {}
    for capability, enabled in pairs(active) do
        if enabled then table.insert(names, capability) end
    end
    table.sort(names)
    return table.concat(names, ",")
end

local function advertised_capabilities()
    if teardown_retry_pending or not game_thread_available or not player_ready then return "" end
    return CAPABILITIES
end

local function current_phase()
    if not game_thread_available then return "waiting-game-thread" end
    if teardown_retry_pending then return "waiting-player" end
    if not player_ready then return "waiting-player" end
    return BRIDGE_PHASE
end

local function get_player()
    local UEHelpers = require("UEHelpers")
    local player = UEHelpers.GetPlayer()
    if not is_valid(player) then return nil, "The local player pawn is not loaded." end

    local ok, is_dawnwalker = pcall(function()
        return player:IsA("/Script/Dawnwalker.DawnwalkerPlayerCharacter")
    end)
    if not ok or not is_dawnwalker then return nil, "The local pawn is not a Dawnwalker player character." end
    return player, nil
end

local function get_session_identity(player)
    local next_player_address = get_object_address(player)
    if next_player_address == nil then return nil, "The local player identity is unavailable." end

    local world_ok, world = pcall(function() return player:GetWorld() end)
    if not world_ok or not is_valid(world) then return nil, "The local player world is unavailable." end
    local next_world_address = get_object_address(world)
    if next_world_address == nil then return nil, "The local world identity is unavailable." end

    return {
        player = player,
        player_address = next_player_address,
        world = world,
        world_address = next_world_address,
        key = next_world_address .. ":" .. next_player_address,
    }, nil
end

local function get_live_player_context()
    local player, player_error = get_player()
    if not player then return nil, nil, player_error end
    local identity, identity_error = get_session_identity(player)
    if not identity then return nil, nil, identity_error end
    if identity.player_address ~= player_address or identity.world_address ~= world_address then
        return nil, nil, "The live player or world changed; wait for the bridge identity probe."
    end
    return player, identity, nil
end

local function get_combat_component(player)
    local ok, component = pcall(function() return player.CombatComponent end)
    if not ok or not is_valid(component) then return nil, "The player combat component is unavailable." end
    return component, nil
end

local function get_blood_bar(player)
    local ok, blood_bar = pcall(function() return player.BloodBar end)
    if ok and is_valid(blood_bar) then return blood_bar, nil end

    ok, blood_bar = pcall(function()
        local state = player.PlayerState
        if not is_valid(state) then return nil end
        return state.BloodBar
    end)
    if ok and is_valid(blood_bar) then return blood_bar, nil end
    return nil, "The player blood bar component is unavailable."
end

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

local function get_gold_inventory(player)
    local direct_ok, direct_inventory = pcall(function() return player:GetInventoryComponent() end)
    if not direct_ok or not is_valid(direct_inventory) then
        return nil, nil, "The player's inventory component is unavailable."
    end
    local direct_class_ok, direct_class_matches = pcall(function()
        return direct_inventory:IsA("/Script/DogwoodInventory.InventoryComponent")
    end)
    if not direct_class_ok or not direct_class_matches then
        return nil, nil, "The player's inventory component has the wrong class."
    end

    local subsystem, subsystem_error = get_subsystem(
        player,
        "/Script/DogwoodInventory.InventorySubsystem",
        "game-instance",
        "inventory subsystem"
    )
    if not subsystem then return nil, nil, subsystem_error end
    local subsystem_inventory_ok, subsystem_inventory = pcall(function()
        return subsystem:GetPlayerInventoryComponent()
    end)
    if not subsystem_inventory_ok or not is_valid(subsystem_inventory) then
        return nil, nil, "The inventory subsystem's player component is unavailable."
    end
    local subsystem_class_ok, subsystem_class_matches = pcall(function()
        return subsystem_inventory:IsA("/Script/DogwoodInventory.InventoryComponent")
    end)
    if not subsystem_class_ok or not subsystem_class_matches then
        return nil, nil, "The inventory subsystem returned the wrong component class."
    end

    local direct_address = get_object_address(direct_inventory)
    local subsystem_address = get_object_address(subsystem_inventory)
    if direct_address == nil or subsystem_address == nil or direct_address ~= subsystem_address then
        return nil, nil, "The player and inventory subsystem resolved different inventory components."
    end
    return direct_inventory, direct_address, nil
end

local function read_gold_quantity(inventory)
    local read_ok, quantity = pcall(function()
        return inventory:GetCurrencyQuantity(COIN_CURRENCY_TYPE)
    end)
    if not read_ok or not is_finite_number(quantity) or quantity < 0 or quantity > INT32_MAX or quantity % 1 ~= 0 then
        return nil, "Gold readback was not a nonnegative int32 Coin quantity."
    end
    return math.floor(quantity), nil
end

local function get_live_gold_inventory(binding)
    local player, identity, player_error = get_live_player_context()
    if not player then return nil, player_error end
    if identity.player_address ~= binding.player_address or identity.world_address ~= binding.world_address then
        return nil, "The player or world identity changed."
    end
    local inventory, inventory_address, inventory_error = get_gold_inventory(player)
    if not inventory then return nil, inventory_error end
    if inventory_address ~= binding.inventory_address then
        return nil, "The inventory component identity changed."
    end
    return inventory, nil
end

-- Splits "assetPath", "assetPath|quantity" or "assetPath|quantity|level" without allowing
-- any other shape. Returns path, quantity (nil for a read-only query), and level.
local function parse_item_request(value)
    local text = tostring(value or "")
    -- Explicit split: gmatch with an empty-capable class silently drops a leading empty
    -- field, which would turn "|5" into the asset path "5". Preserve every field exactly.
    local fields = {}
    local cursor = 1
    while true do
        local separator = string.find(text, "|", cursor, true)
        if separator == nil then
            fields[#fields + 1] = string.sub(text, cursor)
            break
        end
        fields[#fields + 1] = string.sub(text, cursor, separator - 1)
        cursor = separator + 1
        if #fields > 3 then break end
    end
    if #fields == 0 or #fields > 3 then return nil, nil, nil, "Add Item expects assetPath[|quantity[|level]]." end

    local asset_path = fields[1]
    if type(asset_path) ~= "string" or asset_path == "" then
        return nil, nil, nil, "Add Item requires an exact item asset path."
    end
    if string.sub(asset_path, 1, #ITEM_ASSET_PREFIX) ~= ITEM_ASSET_PREFIX then
        return nil, nil, nil, "Add Item only accepts assets under " .. ITEM_ASSET_PREFIX .. "."
    end
    if string.find(asset_path, ITEM_QUEST_MARKER, 1, true) ~= nil then
        return nil, nil, nil, "Add Item refuses quest items."
    end

    local quantity = nil
    if #fields >= 2 then
        quantity = tonumber(fields[2])
        if not is_finite_number(quantity) or quantity % 1 ~= 0 or quantity == 0
            or math.abs(quantity) > MAX_ITEM_QUANTITY then
            return nil, nil, nil, "Add Item requires a nonzero whole quantity from -"
                .. tostring(MAX_ITEM_QUANTITY) .. " to " .. tostring(MAX_ITEM_QUANTITY) .. "."
        end
        quantity = math.floor(quantity)
    end

    local level = DEFAULT_ITEM_LEVEL
    if #fields == 3 then
        level = tonumber(fields[3])
        if not is_finite_number(level) or level % 1 ~= 0 or level < 0 or level > 255 then
            return nil, nil, nil, "Add Item level must be a whole number from 0 to 255."
        end
        level = math.floor(level)
    end

    return asset_path, quantity, level, nil
end

local function get_item_asset(asset_path)
    local ok, asset = pcall(function() return StaticFindObject(asset_path) end)
    if not ok or not is_valid(asset) then
        return nil, "The item asset is not loaded in the running game."
    end
    local class_ok, matches = pcall(function() return asset:IsA(ITEM_ASSET_CLASS) end)
    if not class_ok or not matches then return nil, "The resolved object is not an item data asset." end
    return asset, nil
end

-- Builds the opaque FItemHandle through the reflected factory. The struct has no public
-- fields, so this is the only supported construction route.
local function get_item_handle(player, asset, level)
    local library, library_error = get_default_object(ITEM_LIBRARY_CDO, "inventory blueprint library")
    if not library then return nil, library_error end
    local ok, handle = pcall(function() return library:GetItemHandle(player, asset, level) end)
    if not ok or handle == nil then return nil, "The item handle could not be constructed." end
    return handle, nil
end

local function read_item_quantity(inventory, handle)
    local read_ok, quantity = pcall(function()
        return inventory:GetItemQuantity(handle, false)
    end)
    if not read_ok or not is_finite_number(quantity) or quantity < 0
        or quantity > INT32_MAX or quantity % 1 ~= 0 then
        return nil, "Item readback was not a nonnegative int32 quantity."
    end
    return math.floor(quantity), nil
end

local function parse_boolean(value)
    local normalized = tostring(value or ""):lower()
    if normalized == "1" or normalized == "true" or normalized == "on" then return true end
    if normalized == "0" or normalized == "false" or normalized == "off" then return false end
    return nil
end

local function is_read_only_query(value)
    return tostring(value or ""):match("^%s*$") ~= nil
end

local function normalize_quest_text(value, fallback)
    local text = tostring(value or "")
    text = text:gsub("[%z\1-\31\127]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    if text == "" then return fallback end
    return text
end

local function encode_quest_character(character)
    local encoded = {}
    for index = 1, #character do
        local byte = character:byte(index)
        local safe = (byte >= 48 and byte <= 57)
            or (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or byte == 32 or byte == 39 or byte == 40 or byte == 41
            or byte == 45 or byte == 46 or byte == 95
        table.insert(encoded, safe and string.char(byte) or string.format("%%%02X", byte))
    end
    return table.concat(encoded)
end

local function percent_encode_quest_text(text)
    local pieces = {}
    local encoded_length = 0
    local truncated = false
    local encode_ok, encode_error = pcall(function()
        for _, codepoint in utf8.codes(text) do
            local piece = encode_quest_character(utf8.char(codepoint))
            if encoded_length + #piece > MAX_QUEST_TEXT_ENCODED_BYTES then
                truncated = true
                break
            end
            table.insert(pieces, piece)
            encoded_length = encoded_length + #piece
        end
    end)
    if not encode_ok then return nil, "Quest text was not valid UTF-8: " .. sanitize(encode_error) end

    if truncated then
        while #pieces > 0 and encoded_length + 3 > MAX_QUEST_TEXT_ENCODED_BYTES do
            local removed = table.remove(pieces)
            encoded_length = encoded_length - #removed
        end
        table.insert(pieces, "...")
    end
    return table.concat(pieces), nil
end

local function read_encoded_ftext(ftext, fallback)
    if ftext == nil then return nil, "Quest text was unavailable." end
    local read_ok, text = pcall(function() return ftext:ToString() end)
    if not read_ok or type(text) ~= "string" then return nil, "Quest text readback failed." end
    return percent_encode_quest_text(normalize_quest_text(text, fallback))
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

local function normalized_quest_state(value)
    local numeric = tonumber(value)
    if numeric == 1 then return "active" end
    if numeric == 2 then return "success" end
    if numeric == 3 then return "failure" end

    local named = tostring(value or ""):lower()
    if named:find("active", 1, true) then return "active" end
    if named:find("success", 1, true) then return "success" end
    if named:find("failure", 1, true) then return "failure" end
    return "unknown"
end

local function get_quest_journal(identity)
    local UEHelpers = require("UEHelpers")
    if type(UEHelpers.GetGameStateBase) ~= "function" then
        return nil, "The game-state helper is unavailable."
    end

    local state_ok, game_state = pcall(UEHelpers.GetGameStateBase)
    if not state_ok or not is_valid(game_state) then return nil, "The Dawnwalker game state is unavailable." end
    local class_ok, is_dawnwalker_state = pcall(function()
        return game_state:IsA("/Script/Dawnwalker.DawnwalkerGameStateBase")
    end)
    if not class_ok or not is_dawnwalker_state then return nil, "The resolved game state has the wrong class." end

    local world_ok, state_world = pcall(function() return game_state:GetWorld() end)
    if not world_ok or not object_matches_address(state_world, identity.world_address) then
        return nil, "The quest journal belongs to a different world identity."
    end

    local journal_ok, journal = pcall(function() return game_state.QuestJournal end)
    if not journal_ok or not is_valid(journal) then return nil, "The QuestJournal is not loaded." end
    local journal_class_ok, is_journal = pcall(function() return journal:IsA("/Script/Quest.Journal") end)
    if not journal_class_ok or not is_journal then return nil, "The QuestJournal has the wrong class." end
    return journal, nil
end

local function parse_number(value, minimum, maximum)
    local parsed = tonumber(value)
    if parsed == nil or parsed ~= parsed or parsed == math.huge or parsed == -math.huge then return nil end
    if parsed < minimum or parsed > maximum then return nil end
    return parsed
end

local function blood_percentage(blood_bar)
    local current = blood_bar:GetBlood()
    local maximum = blood_bar:GetBloodBarLength()
    if type(current) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then
        error("Blood readback returned an invalid range.")
    end
    return current / maximum
end

local function has_resource_owners(resource)
    for _, enabled in pairs(resource.owners) do
        if enabled then return true end
    end
    return false
end

local RESOURCE_OPERATIONS = {
    health = {
        read = function(target) return target:GetHealthPercentage() end,
        set = function(target, percentage) target:SetHealthPercent(percentage) end,
        lock = function(target) target:LockHealth() end,
        unlock = function(target) target:UnlockHealth() end,
    },
    stamina = {
        read = function(target) return target:GetStaminaPercentage() end,
        set = function(target, percentage) target:SetStaminaPercent(percentage) end,
        lock = function(target) target:LockStamina() end,
        unlock = function(target) target:UnlockStamina() end,
    },
    blood = {
        read = blood_percentage,
        set = function(target, percentage) target:SetBloodPercent(percentage) end,
        lock = function(target) target:LockBlood() end,
        unlock = function(target) target:UnlockBlood() end,
    },
}

local function percentage_is_valid(value)
    return is_finite_number(value) and value >= 0 and value <= 1.001
end

local function reset_resource_state(resource)
    resource.owners = {}
    resource.baseline = nil
    resource.target = nil
    resource.target_address = nil
    resource.player = nil
    resource.player_address = nil
    resource.world = nil
    resource.world_address = nil
end

local function resource_binding_is_live(resource)
    return object_matches_address(resource.target, resource.target_address)
        and object_matches_address(resource.player, resource.player_address)
        and object_matches_address(resource.world, resource.world_address)
end

local function resource_binding_matches(resource, target, identity)
    return resource_binding_is_live(resource)
        and resource.target_address == get_object_address(target)
        and resource.player_address == identity.player_address
        and resource.world_address == identity.world_address
end

local function bind_resource(resource, target, identity, baseline)
    resource.baseline = baseline
    resource.target = target
    resource.target_address = get_object_address(target)
    resource.player = identity.player
    resource.player_address = identity.player_address
    resource.world = identity.world
    resource.world_address = identity.world_address
end

local function restore_resource_baseline(resource, operations)
    if not percentage_is_valid(resource.baseline) then return false, "the captured baseline is invalid" end
    if not resource_binding_is_live(resource) then return false, "the bound game objects are no longer valid" end

    local unlock_ok, unlock_error = pcall(operations.unlock, resource.target)
    local set_ok, set_error = pcall(operations.set, resource.target, resource.baseline)
    local read_ok, readback = pcall(operations.read, resource.target)
    local restored = unlock_ok and set_ok and read_ok and percentage_is_valid(readback)
        and math.abs(readback - resource.baseline) <= 0.0025
    if restored then return true, nil end
    return false, "unlock=" .. sanitize(unlock_error or unlock_ok)
        .. ", set=" .. sanitize(set_error or set_ok)
        .. ", readback=" .. sanitize(readback)
end

local function reassert_resource_lock(resource, operations)
    if not resource_binding_is_live(resource) then return false, nil, "the bound game objects are no longer valid" end
    local set_ok, set_error = pcall(operations.set, resource.target, 1.0)
    local lock_ok, lock_error = pcall(operations.lock, resource.target)
    local read_ok, readback = pcall(operations.read, resource.target)
    local applied = set_ok and lock_ok and read_ok and percentage_is_valid(readback) and readback >= 0.999
    if applied then return true, readback, nil end
    return false, readback, "set=" .. sanitize(set_error or set_ok)
        .. ", lock=" .. sanitize(lock_error or lock_ok)
        .. ", readback=" .. sanitize(readback)
end

local function has_other_resource_owner(resource, excluded_owner)
    for owner, enabled in pairs(resource.owners) do
        if owner ~= excluded_owner and enabled then return true end
    end
    return false
end

local function change_resource_lock(resource_name, target, identity, owner, requested)
    local resource = resource_locks[resource_name]
    local operations = RESOURCE_OPERATIONS[resource_name]
    if not resource or not operations then return false, nil, "Unknown resource lock." end

    if not has_resource_owners(resource) and resource.baseline ~= nil then
        local pending_restored, pending_error = restore_resource_baseline(resource, operations)
        if not pending_restored then return false, nil, "A pending resource rollback could not finish: " .. sanitize(pending_error) end
        reset_resource_state(resource)
    end

    if not requested and not resource.owners[owner] then
        local read_ok, readback = pcall(operations.read, target)
        if not read_ok or not percentage_is_valid(readback) then return false, nil, "Resource readback was invalid." end
        return true, readback, nil
    end

    if has_resource_owners(resource) then
        if not resource_binding_matches(resource, target, identity) then
            return false, nil, "The existing resource lock belongs to a different player or world."
        end
    else
        local baseline_ok, baseline = pcall(operations.read, target)
        if not baseline_ok or not percentage_is_valid(baseline) then return false, nil, "The resource baseline was invalid." end
        bind_resource(resource, target, identity, baseline)
        if resource.target_address == nil then
            reset_resource_state(resource)
            return false, nil, "The resource target identity was unavailable."
        end
    end

    if requested then
        local applied, readback, apply_error = reassert_resource_lock(resource, operations)
        if not applied then
            if not has_resource_owners(resource) then
                local restored = restore_resource_baseline(resource, operations)
                if restored then reset_resource_state(resource) end
            end
            return false, readback, "Resource acquisition failed atomically: " .. sanitize(apply_error)
        end
        resource.owners[owner] = true
        return true, readback, nil
    end

    if has_other_resource_owner(resource, owner) then
        local applied, readback, apply_error = reassert_resource_lock(resource, operations)
        if not applied then return false, readback, "Resource owner release could not preserve the remaining owners: " .. sanitize(apply_error) end
        resource.owners[owner] = nil
        return true, readback, nil
    end

    local restored, restore_error = restore_resource_baseline(resource, operations)
    if restored then
        local restored_value = resource.baseline
        reset_resource_state(resource)
        return true, restored_value, nil
    end

    reassert_resource_lock(resource, operations)
    return false, nil, "Resource owner release could not restore its baseline: " .. sanitize(restore_error)
end

local function set_health_lock(combat, identity, owner, requested)
    return change_resource_lock("health", combat, identity, owner, requested)
end

local function set_stamina_lock(combat, identity, owner, requested)
    return change_resource_lock("stamina", combat, identity, owner, requested)
end

local function set_blood_lock(blood_bar, identity, owner, requested)
    return change_resource_lock("blood", blood_bar, identity, owner, requested)
end

local function force_release_resource_owner(resource_name, target, identity, owner)
    local released, readback, release_error = change_resource_lock(resource_name, target, identity, owner, false)
    if released then return true, readback, nil end

    local resource = resource_locks[resource_name]
    resource.owners[owner] = nil
    if has_resource_owners(resource) then
        reassert_resource_lock(resource, RESOURCE_OPERATIONS[resource_name])
    else
        local restored = restore_resource_baseline(resource, RESOURCE_OPERATIONS[resource_name])
        if restored then reset_resource_state(resource) end
    end
    return false, readback, release_error
end

local function snapshot_binding_is_live(snapshot)
    if not object_matches_address(snapshot.target, snapshot.target_address) then return false end
    if not object_matches_address(snapshot.world, snapshot.world_address) then return false end
    if snapshot.player ~= nil and not object_matches_address(snapshot.player, snapshot.player_address) then return false end
    return true
end

local function snapshot_binding_matches(snapshot, target, identity)
    return snapshot_binding_is_live(snapshot)
        and snapshot.target_address == get_object_address(target)
        and snapshot.world_address == identity.world_address
        and (snapshot.player == nil or snapshot.player_address == identity.player_address)
end

local function restore_snapshot(capability)
    local snapshot = snapshots[capability]
    if snapshot == nil then return true, nil end
    if type(snapshot.restore) ~= "function" then return false, "the snapshot has no restore operation" end

    local call_ok, restored, restore_error = pcall(snapshot.restore, snapshot)
    if call_ok and restored then
        snapshots[capability] = nil
        active[capability] = nil
        return true, nil
    end
    return false, sanitize(call_ok and restore_error or restored)
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

local function handle_rpg_difficulty(value)
    return handle_difficulty_axis("rpg", value)
end

local function handle_action_difficulty(value)
    return handle_difficulty_axis("action", value)
end

local function teardown_resource(resource_name)
    local resource = resource_locks[resource_name]
    if resource.baseline == nil and not has_resource_owners(resource) then return true, nil end
    local restored, restore_error = restore_resource_baseline(resource, RESOURCE_OPERATIONS[resource_name])
    if restored then reset_resource_state(resource) end
    return restored, restore_error
end

local function teardown_session_state(reason)
    local operations = {
        { label = "health lock", run = function() return teardown_resource("health") end },
        { label = "stamina lock", run = function() return teardown_resource("stamina") end },
        { label = "blood lock", run = function() return teardown_resource("blood") end },
        { label = "blood energy rollback", run = function() return restore_snapshot("player:blood-energy") end },
        { label = "trait points rollback", run = function() return restore_snapshot("player:trait-points") end },
        { label = "Combat difficulty baselines", run = restore_difficulty_override },
        { label = "HUD baseline", run = function() return restore_snapshot("visuals:hud-visible") end },
        { label = "game-speed baseline", run = function() return restore_snapshot("world:game-speed") end },
    }
    local failures = 0
    local operation_count = math.min(#operations, MAX_TEARDOWN_OPERATIONS)
    for index = 1, operation_count do
        local operation = operations[index]
        local call_ok, restored, restore_error = pcall(operation.run)
        if not call_ok or restored ~= true then
            failures = failures + 1
            log("teardown skipped " .. operation.label .. ": " .. sanitize(call_ok and restore_error or restored))
        end
    end
    local unresolved_state_remains = session_state_has_pending_restore()
    if failures > 0 or unresolved_state_remains then
        teardown_retry_pending = true
        retain_only_pending_active_state()
        local message = "bounded teardown for " .. sanitize(reason) .. " retained state for "
            .. tostring(math.max(failures, unresolved_state_remains and 1 or 0)) .. " unresolved restore operation(s)"
        log(message)
        return false, message
    end
    clear_session_state()
    return true, nil
end

local function refresh_player_probe()
    local now = os.time()
    game_thread_available = EngineTickAvailable == true
    if not game_thread_available or probe_pending or now == last_probe_second then return end
    last_probe_second = now
    probe_pending = true

    local queued, queue_error = pcall(function()
        ExecuteInGameThread(function()
            local probe_ok, probe_error = pcall(function()
                local player = get_player()
                local identity = nil
                if is_valid(player) then identity = get_session_identity(player) end
                local next_player_address = identity and identity.player_address or nil
                local next_world_address = identity and identity.world_address or nil

                if teardown_retry_pending then
                    local retry_restored, retry_error = teardown_session_state("pending restore retry")
                    if not retry_restored then
                        player_ready = false
                        log("pending session restore remains unresolved: " .. sanitize(retry_error))
                        return
                    end
                end

                if next_player_address ~= player_address or next_world_address ~= world_address then
                    local restored, restore_error = teardown_session_state("player or world identity change")
                    if not restored then
                        player_ready = false
                        log("player identity transition blocked by unresolved restore state: " .. sanitize(restore_error))
                        return
                    end
                    player_address = next_player_address
                    world_address = next_world_address
                end
                player_ready = next_player_address ~= nil and next_world_address ~= nil
            end)
            probe_pending = false
            if not probe_ok then
                player_ready = false
                log("player identity probe failed: " .. sanitize(probe_error))
            end
        end, EGameThreadMethod.EngineTick)
    end)
    if not queued then
        probe_pending = false
        game_thread_available = false
        log("game-thread probe queue failed: " .. sanitize(queue_error))
    end
end

local function write_ready()
    refresh_player_probe()
    local now = os.time()
    if now == last_ready_second then return true end
    last_ready_second = now
    return write_atomic(READY_PATH, table.concat({
        "protocol=" .. BRIDGE_PROTOCOL,
        "boot_id=" .. BOOT_ID,
        "version=" .. BRIDGE_VERSION,
        "heartbeat=" .. tostring(now),
        "phase=" .. current_phase(),
        "capabilities=" .. advertised_capabilities(),
        "active=" .. active_capabilities(),
        "",
    }, "\n"))
end

local function write_response(request_id, accepted, status, message, readback)
    return write_atomic(RESPONSE_PATH, table.concat({
        "protocol=" .. BRIDGE_PROTOCOL,
        "boot_id=" .. BOOT_ID,
        "request_id=" .. sanitize(request_id),
        "accepted=" .. (accepted and "1" or "0"),
        "status=" .. sanitize(status),
        "message=" .. sanitize(message),
        "readback=" .. sanitize(readback),
        "",
    }, "\n"))
end

local handlers = {}

local function handle_infinite_health(value)
    local requested = parse_boolean(value)
    if requested == nil then return false, "rejected", "Infinite Health requires a boolean value.", "" end
    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local combat, combat_error = get_combat_component(player)
    if not combat then return false, "rejected", combat_error, "" end

    local capability = "player:infinite-health"
    local applied, percentage, lock_error = set_health_lock(combat, identity, capability, requested)
    active[capability] = resource_locks.health.owners[capability] and true or nil
    if not applied then
        return false, "rejected", "Infinite Health was not changed: " .. sanitize(lock_error), ""
    end
    return true, "applied", string.format("Infinite Health %s; health %.1f%%.", requested and "enabled" or "disabled", percentage * 100), requested and "1" or "0"
end

local function handle_unlimited_stamina(value)
    local requested = parse_boolean(value)
    if requested == nil then return false, "rejected", "Unlimited Stamina requires a boolean value.", "" end
    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local combat, combat_error = get_combat_component(player)
    if not combat then return false, "rejected", combat_error, "" end

    local capability = "player:unlimited-stamina"
    local applied, percentage, lock_error = set_stamina_lock(combat, identity, capability, requested)
    active[capability] = resource_locks.stamina.owners[capability] and true or nil
    if not applied then
        return false, "rejected", "Unlimited Stamina was not changed: " .. sanitize(lock_error), ""
    end
    return true, "applied", string.format("Unlimited Stamina %s; stamina %.1f%%.", requested and "enabled" or "disabled", percentage * 100), requested and "1" or "0"
end

local function handle_blood_energy(value)
    local query_only = is_read_only_query(value)
    local requested = query_only and nil or parse_number(value, 0, 100)
    if not query_only and requested == nil then return false, "rejected", "Blood Energy requires a number from 0 to 100.", "" end
    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local blood_bar, blood_error = get_blood_bar(player)
    if not blood_bar then return false, "rejected", blood_error, "" end

    local capability = "player:blood-energy"
    if not query_only and snapshots[capability] ~= nil then
        local restored, restore_error = restore_snapshot(capability)
        if not restored then
            return false, "rejected", "A pending Blood Energy rollback must finish before another mutation: " .. sanitize(restore_error), ""
        end
    end
    local before_ok, before = pcall(blood_percentage, blood_bar)
    if not before_ok or not percentage_is_valid(before) then return false, "rejected", "Blood Energy baseline readback was invalid.", "" end
    if query_only then
        local readback = before * 100
        return true, "applied", string.format("Blood Energy read as %.1f%%.", readback), string.format("%.6f", readback)
    end
    local rollback = {
        target = blood_bar,
        target_address = get_object_address(blood_bar),
        player = identity.player,
        player_address = identity.player_address,
        world = identity.world,
        world_address = identity.world_address,
        baseline = before,
    }
    if rollback.target_address == nil then return false, "rejected", "The blood-energy target identity was unavailable.", "" end
    rollback.restore = function(snapshot)
        if not snapshot_binding_is_live(snapshot) then return false, "the blood-energy binding is no longer live" end
        local set_ok = pcall(function() snapshot.target:SetBloodPercent(snapshot.baseline) end)
        local read_ok, restored = pcall(blood_percentage, snapshot.target)
        return set_ok and read_ok and percentage_is_valid(restored) and math.abs(restored - snapshot.baseline) <= 0.0025,
            "blood-energy baseline readback=" .. sanitize(restored)
    end

    local set_ok, set_error = pcall(function() blood_bar:SetBloodPercent(requested / 100) end)
    local read_ok, readback_percentage = pcall(blood_percentage, blood_bar)
    local matches = set_ok and read_ok and percentage_is_valid(readback_percentage)
        and math.abs(readback_percentage * 100 - requested) <= 0.25
    if not matches then
        snapshots[capability] = rollback
        local restored, restore_error = restore_snapshot(capability)
        local rollback_message = restored and "the previous value was restored and verified"
            or "the previous value could not be verified after rollback: " .. sanitize(restore_error)
        return false, "rejected", "Blood Energy did not match after readback (" .. sanitize(set_error or readback_percentage) .. "); " .. rollback_message .. ".", ""
    end
    local readback = readback_percentage * 100
    return true, "applied", string.format("Blood Energy set to %.1f%%.", readback), string.format("%.6f", readback)
end

local function handle_infinite_blood(value)
    local requested = parse_boolean(value)
    if requested == nil then return false, "rejected", "Infinite Blood Energy requires a boolean value.", "" end
    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local blood_bar, blood_error = get_blood_bar(player)
    if not blood_bar then return false, "rejected", blood_error, "" end

    local capability = "combat:infinite-blood-energy"
    local applied, percentage, lock_error = set_blood_lock(blood_bar, identity, capability, requested)
    active[capability] = resource_locks.blood.owners[capability] and true or nil
    if not applied then
        return false, "rejected", "Infinite Blood Energy was not changed: " .. sanitize(lock_error), ""
    end
    return true, "applied", string.format("Infinite Blood Energy %s; blood %.1f%%.", requested and "enabled" or "disabled", percentage * 100), requested and "1" or "0"
end

local function handle_player_info()
    local player, _, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local combat, combat_error = get_combat_component(player)
    if not combat then return false, "rejected", combat_error, "" end
    local blood_bar, blood_error = get_blood_bar(player)
    if not blood_bar then return false, "rejected", blood_error, "" end

    local alive = player:IsAlive()
    local fields = {
        "alive=" .. (alive and "1" or "0"),
        "health_percent=" .. string.format("%.6f", combat:GetHealthPercentage() * 100),
        "stamina_percent=" .. string.format("%.6f", combat:GetStaminaPercentage() * 100),
        "blood=" .. string.format("%.6f", blood_bar:GetBlood()),
        "blood_max=" .. string.format("%.6f", blood_bar:GetBloodBarLength()),
    }
    local char_dev = get_subsystem(player, "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem", "game-instance", "character development subsystem")
    if char_dev then
        local development_ok, level, trait_points = pcall(function()
            return char_dev:GetCurrentLevel(), char_dev:GetTraitPointAmount()
        end)
        if development_ok and type(level) == "number" and type(trait_points) == "number" then
            table.insert(fields, "level=" .. tostring(math.floor(level)))
            table.insert(fields, "trait_points=" .. tostring(math.floor(trait_points)))
        end
    end
    local readback = table.concat(fields, ";")
    return true, "applied", "Player status read successfully.", readback
end

local function release_god_mode_owner(combat, blood_bar, identity)
    local capability = "player:god-mode"
    local releases = {
        { name = "health", target = combat },
        { name = "stamina", target = combat },
        { name = "blood", target = blood_bar },
    }
    local failures = {}
    for _, release in ipairs(releases) do
        local call_ok, released, _, release_error = pcall(
            force_release_resource_owner,
            release.name,
            release.target,
            identity,
            capability
        )
        if not call_ok or not released then
            resource_locks[release.name].owners[capability] = nil
            table.insert(failures, release.name .. ": " .. sanitize(call_ok and release_error or released))
        end
    end
    active[capability] = nil
    return #failures == 0, table.concat(failures, "; ")
end

local function handle_god_mode(value)
    local requested = parse_boolean(value)
    if requested == nil then return false, "rejected", "God Mode requires a boolean value.", "" end
    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local combat, combat_error = get_combat_component(player)
    if not combat then return false, "rejected", combat_error, "" end
    local blood_bar, blood_error = get_blood_bar(player)
    if not blood_bar then return false, "rejected", blood_error, "" end

    local capability = "player:god-mode"
    if not requested then
        local released, release_error = release_god_mode_owner(combat, blood_bar, identity)
        if not released then
            return false, "rejected", "God Mode ownership was released, but one or more baselines could not be verified: " .. sanitize(release_error), ""
        end
        return true, "applied", "God Mode disabled and all three owned resource baselines restored.", "0"
    end

    local acquisitions = {
        { name = "health", apply = function() return set_health_lock(combat, identity, capability, true) end },
        { name = "stamina", apply = function() return set_stamina_lock(combat, identity, capability, true) end },
        { name = "blood", apply = function() return set_blood_lock(blood_bar, identity, capability, true) end },
    }
    for _, acquisition in ipairs(acquisitions) do
        local call_ok, applied, _, apply_error = pcall(acquisition.apply)
        if not call_ok or not applied then
            local released, release_error = release_god_mode_owner(combat, blood_bar, identity)
            local rollback_status = released and "all acquired owners released and verified" or sanitize(release_error)
            return false, "rejected", "God Mode acquisition failed at " .. acquisition.name .. ": "
                .. sanitize(call_ok and apply_error or applied) .. ". Rollback: " .. rollback_status, ""
        end
    end

    local read_ok, healthy, rested, fed = pcall(function()
        return combat:GetHealthPercentage() >= 0.999,
            combat:GetStaminaPercentage() >= 0.999,
            blood_percentage(blood_bar) >= 0.999
    end)
    if not read_ok or not (healthy and rested and fed) then
        local released, release_error = release_god_mode_owner(combat, blood_bar, identity)
        local rollback_status = released and "all acquired owners released and verified" or sanitize(release_error)
        return false, "rejected", "God Mode could not verify all three resources; its owner was released. Rollback: " .. rollback_status, ""
    end

    active[capability] = true
    return true, "applied", "God Mode enabled with health, stamina, and blood readback.", "1"
end

local function handle_trait_points(value)
    local query_only = is_read_only_query(value)
    local requested = query_only and nil or parse_number(value, 0, 9999)
    if not query_only and (requested == nil or requested % 1 ~= 0) then return false, "rejected", "Trait Points requires a whole number from 0 to 9999.", "" end
    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local subsystem, subsystem_error = get_subsystem(player, "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem", "game-instance", "character development subsystem")
    if not subsystem then return false, "rejected", subsystem_error, "" end

    local capability = "player:trait-points"
    if not query_only and snapshots[capability] ~= nil then
        local restored, restore_error = restore_snapshot(capability)
        if not restored then
            return false, "rejected", "A pending Trait Points rollback must finish before another mutation: " .. sanitize(restore_error), ""
        end
    end
    local before_ok, before = pcall(function() return subsystem:GetTraitPointAmount() end)
    if not before_ok or not is_finite_number(before) then return false, "rejected", "Trait Points baseline readback was invalid.", "" end
    if query_only then
        return true, "applied", "Trait Points read as " .. tostring(math.floor(before)) .. ".", tostring(math.floor(before))
    end
    local rollback = {
        target = subsystem,
        target_address = get_object_address(subsystem),
        world = identity.world,
        world_address = identity.world_address,
        baseline = math.floor(before),
    }
    if rollback.target_address == nil then return false, "rejected", "The Trait Points target identity was unavailable.", "" end
    rollback.restore = function(snapshot)
        if not snapshot_binding_is_live(snapshot) then return false, "the Trait Points binding is no longer live" end
        local set_ok = pcall(function() snapshot.target:SetTraitPointsAmount(snapshot.baseline) end)
        local read_ok, restored = pcall(function() return snapshot.target:GetTraitPointAmount() end)
        return set_ok and read_ok and is_finite_number(restored) and math.floor(restored) == snapshot.baseline,
            "Trait Points baseline readback=" .. sanitize(restored)
    end

    local set_ok, set_error = pcall(function() subsystem:SetTraitPointsAmount(requested) end)
    local read_ok, readback = pcall(function() return subsystem:GetTraitPointAmount() end)
    if not set_ok or not read_ok or not is_finite_number(readback) or math.floor(readback) ~= requested then
        snapshots[capability] = rollback
        local restored, restore_error = restore_snapshot(capability)
        local rollback_message = restored and "the previous value was restored and verified"
            or "the previous value could not be verified after rollback: " .. sanitize(restore_error)
        return false, "rejected", "Trait Points did not match after readback (" .. sanitize(set_error or readback) .. "); " .. rollback_message .. ".", ""
    end
    return true, "applied", "Trait Points set to " .. tostring(readback) .. ".", tostring(math.floor(readback))
end

local function handle_add_gold(value)
    local query_only = is_read_only_query(value)
    local requested = query_only and nil or tonumber(value)
    if not query_only and (not is_finite_number(requested) or requested % 1 ~= 0
        or requested == 0 or math.abs(requested) > MAX_GOLD_DELTA) then
        return false, "rejected", "Add Gold requires a nonzero whole-number delta from -10000 to 10000.", ""
    end
    if requested ~= nil then requested = math.floor(requested) end

    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local inventory, inventory_address, inventory_error = get_gold_inventory(player)
    if not inventory then return false, "rejected", inventory_error, "" end
    local before, before_error = read_gold_quantity(inventory)
    if before == nil then return false, "rejected", before_error, "" end
    if query_only then
        return true, "applied", "Gold balance read as " .. tostring(before) .. ".", tostring(before)
    end

    local expected = before + requested
    if expected < 0 then
        return false, "rejected", "Add Gold cannot reduce the Coin balance below zero.", ""
    end
    if expected > INT32_MAX then
        return false, "rejected", "Add Gold was refused because the Coin int32 balance would overflow.", ""
    end

    local binding = {
        player_address = identity.player_address,
        world_address = identity.world_address,
        inventory_address = inventory_address,
    }
    local call_ok, call_error = pcall(function()
        inventory:AddCurrency(COIN_CURRENCY_TYPE, requested)
    end)
    local after, after_error = read_gold_quantity(inventory)
    if call_ok and after == expected then
        local action = requested > 0 and "Added" or "Removed"
        return true, "applied", action .. " " .. tostring(math.abs(requested))
            .. " Gold; balance is " .. tostring(after) .. ".", tostring(after)
    end

    if after == nil then
        return false, "rejected", "Add Gold could not verify its readback (" .. sanitize(call_error or after_error)
            .. "); automatic rollback was refused because the observed Coin delta is unknown.", ""
    end

    local observed_delta = after - before
    if observed_delta == 0 then
        return false, "rejected", "Add Gold did not reach the requested balance (" .. sanitize(call_error or after)
            .. "); the original balance remained exact.", ""
    end

    local lower_bound = math.min(before, expected)
    local upper_bound = math.max(before, expected)
    local observed_is_bounded = after >= lower_bound and after <= upper_bound
        and math.abs(observed_delta) <= math.abs(requested)
        and observed_delta * requested > 0
    if not observed_is_bounded then
        return false, "rejected", "Add Gold observed an out-of-bounds Coin delta of " .. tostring(observed_delta)
            .. "; automatic rollback was refused to avoid changing unrelated currency state.", ""
    end

    local rollback_inventory, binding_error = get_live_gold_inventory(binding)
    if not rollback_inventory then
        return false, "rejected", "Add Gold observed a partial Coin delta of " .. tostring(observed_delta)
            .. ", but automatic rollback was refused because " .. sanitize(binding_error), ""
    end
    local rollback_ok, rollback_error = pcall(function()
        rollback_inventory:AddCurrency(COIN_CURRENCY_TYPE, -observed_delta)
    end)
    local verified_rollback_inventory, post_rollback_identity_error = get_live_gold_inventory(binding)
    if not verified_rollback_inventory then
        return false, "rejected", "Add Gold issued a bounded inverse, but rollback identity could not be verified ("
            .. sanitize(post_rollback_identity_error) .. "). Restore the pretest save backup before saving.", ""
    end
    local restored, restored_error = read_gold_quantity(verified_rollback_inventory)
    if rollback_ok and restored == before then
        return false, "rejected", "Add Gold did not reach the requested balance; observed Coin delta "
            .. tostring(observed_delta) .. " was reversed and baseline " .. tostring(before) .. " was verified.", ""
    end
    return false, "rejected", "Add Gold did not reach the requested balance and exact rollback could not be verified ("
        .. sanitize(rollback_error or restored_error or restored) .. "). Restore the pretest save backup before saving.", ""
end

-- Adds or removes a bounded quantity of one exact loaded item asset.
--
-- Reuses get_gold_inventory so the dual-route inventory identity check (player component and
-- UInventorySubsystem must resolve the same UObject address) is shared with Add Gold rather
-- than reimplemented. The reflected EInventoryResult return is ignored exactly as Add Gold
-- ignores its own: only the GetItemQuantity readback is authoritative.
local function handle_add_item(value)
    local asset_path, requested, level, parse_error = parse_item_request(value)
    if asset_path == nil then return false, "rejected", parse_error, "" end

    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local inventory, inventory_address, inventory_error = get_gold_inventory(player)
    if not inventory then return false, "rejected", inventory_error, "" end

    local asset, asset_error = get_item_asset(asset_path)
    if not asset then return false, "rejected", asset_error, "" end
    local asset_address = get_object_address(asset)
    if asset_address == nil then return false, "rejected", "The item asset address was unreadable.", "" end

    local handle, handle_error = get_item_handle(player, asset, level)
    if not handle then return false, "rejected", handle_error, "" end

    local before, before_error = read_item_quantity(inventory, handle)
    if before == nil then return false, "rejected", before_error, "" end
    if requested == nil then
        return true, "applied", "Item quantity read as " .. tostring(before) .. ".", tostring(before)
    end

    local expected = before + requested
    if expected < 0 then
        return false, "rejected", "Add Item cannot reduce the quantity below zero.", ""
    end
    if expected > INT32_MAX then
        return false, "rejected", "Add Item was refused because the int32 quantity would overflow.", ""
    end

    local binding = {
        player_address = identity.player_address,
        world_address = identity.world_address,
        inventory_address = inventory_address,
    }

    local call_ok, call_error = pcall(function()
        if requested > 0 then
            inventory:TryAddItem(handle, requested, true)
        else
            inventory:RemoveItem(handle, -requested)
        end
    end)
    local after, after_error = read_item_quantity(inventory, handle)
    if call_ok and after == expected then
        local action = requested > 0 and "Added" or "Removed"
        return true, "applied", action .. " " .. tostring(math.abs(requested))
            .. "; quantity is " .. tostring(after) .. ".", tostring(after)
    end

    if after == nil then
        return false, "rejected", "Add Item could not verify its readback (" .. sanitize(call_error or after_error)
            .. "); automatic rollback was refused because the observed delta is unknown.", ""
    end

    local observed_delta = after - before
    if observed_delta == 0 then
        return false, "rejected", "Add Item did not reach the requested quantity ("
            .. sanitize(call_error or after) .. "); the original quantity remained exact.", ""
    end

    local lower_bound = math.min(before, expected)
    local upper_bound = math.max(before, expected)
    local observed_is_bounded = after >= lower_bound and after <= upper_bound
        and math.abs(observed_delta) <= math.abs(requested)
        and observed_delta * requested > 0
    if not observed_is_bounded then
        return false, "rejected", "Add Item observed an out-of-bounds delta of " .. tostring(observed_delta)
            .. "; automatic rollback was refused to avoid changing unrelated inventory state.", ""
    end

    local rollback_inventory, binding_error = get_live_gold_inventory(binding)
    if not rollback_inventory then
        return false, "rejected", "Add Item observed a partial delta of " .. tostring(observed_delta)
            .. ", but automatic rollback was refused because " .. sanitize(binding_error), ""
    end
    -- Re-resolve the asset and rebuild the handle so the inverse cannot act on a stale struct.
    local rollback_asset, rollback_asset_error = get_item_asset(asset_path)
    if not rollback_asset or get_object_address(rollback_asset) ~= asset_address then
        return false, "rejected", "Add Item observed a partial delta of " .. tostring(observed_delta)
            .. ", but rollback was refused because the item asset identity changed ("
            .. sanitize(rollback_asset_error or "address drift") .. ").", ""
    end
    local rollback_handle, rollback_handle_error = get_item_handle(player, rollback_asset, level)
    if not rollback_handle then
        return false, "rejected", "Add Item observed a partial delta of " .. tostring(observed_delta)
            .. ", but rollback was refused because " .. sanitize(rollback_handle_error), ""
    end

    local rollback_ok, rollback_error = pcall(function()
        if observed_delta > 0 then
            rollback_inventory:RemoveItem(rollback_handle, observed_delta)
        else
            rollback_inventory:TryAddItem(rollback_handle, -observed_delta, true)
        end
    end)
    local restored, restored_error = read_item_quantity(rollback_inventory, rollback_handle)
    if rollback_ok and restored == before then
        return false, "rejected", "Add Item did not reach the requested quantity; observed delta "
            .. tostring(observed_delta) .. " was reversed and baseline " .. tostring(before)
            .. " was verified.", ""
    end
    return false, "rejected", "Add Item did not reach the requested quantity and exact rollback could not be "
        .. "verified (" .. sanitize(rollback_error or restored_error or restored)
        .. "). Restore the pretest save backup before saving.", ""
end

-- Resolves the same game-instance subsystem that player:trait-points already proves live.
local function get_char_dev_subsystem(player)
    return get_subsystem(player, CHAR_DEV_SUBSYSTEM_PATH, "game-instance", "character development subsystem")
end

local function read_character_level(subsystem)
    local ok, level = pcall(function() return subsystem:GetCurrentLevel() end)
    if not ok or not is_finite_number(level) or level % 1 ~= 0 or level < 0 then
        return nil, "Character level readback was invalid."
    end
    return math.floor(level), nil
end

-- Reads a bounded reflected container through either supported UE4SS ABI shape. A live
-- nested container has already been observed to reject `ForEach` in the pinned build, so
-- both shapes are required and an incomplete walk is a hard failure rather than a partial
-- read. This mirrors the bounded walk the Unlock All Skills planner probe reuses for the
-- same GetAllTraits container.
local function read_bounded_container(container, maximum, label)
    if container == nil then return nil, "the " .. label .. " was nil" end

    -- Every entry is unwrapped before it leaves this reader: the live GetAllTraits()
    -- container in the pinned UE4SS build returns wrapped remote values on the table and
    -- numeric shapes (0.3.19 probed this live -- every trait id was rejected with "a trait
    -- roster entry was no longer valid" until the unwrap was added), so an entry may carry
    -- a :get() proxy that must be resolved before IsValid/IsA can see the real UObject.
    if type(container) == "table" then
        local entries = {}
        for index, value in ipairs(container) do
            if index > maximum then return nil, "the " .. label .. " exceeded its safety bound" end
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
                if #entries >= maximum then overflow = true return end
                entries[#entries + 1] = unwrap_remote_value(element)
            end)
        end)
        if not iterate_ok then return nil, "the " .. label .. " iteration failed" end
        if overflow then return nil, "the " .. label .. " exceeded its safety bound" end
        return entries, nil
    end

    local count_ok, count = pcall(function() return #container end)
    if not count_ok or not is_finite_number(count) or count < 0 or count % 1 ~= 0 then
        return nil, "the " .. label .. " had an invalid size"
    end
    if count > maximum then return nil, "the " .. label .. " exceeded its safety bound" end

    local entries = {}
    for index = 1, count do
        local element_ok, element = pcall(function() return container[index] end)
        if not element_ok or element == nil then
            return nil, "the " .. label .. " entry " .. tostring(index) .. " was unreadable"
        end
        entries[#entries + 1] = unwrap_remote_value(element)
    end
    return entries, nil
end

-- ONE-WAY. Resolves a requested trait id to the exact Skill_ID value of the matching live
-- trait, or fails without ever calling an FName-typed subsystem function with an unresolved
-- id. The roster is the authoritative source: the returned Skill_ID is the value the engine
-- itself stored on the matched trait, which is the only shape the FName parameters of
-- GetTrait, GetTraitUnblockedLevel, and UnblockTraitToLevel can safely receive from this
-- pinned UE4SS build.
local function resolve_trait_id(subsystem, trait_id)
    local traits_ok, traits_container = pcall(function() return subsystem:GetAllTraits() end)
    if not traits_ok then return nil, "could not read the trait roster" end

    local entries, entries_error = read_bounded_container(traits_container, MAX_TRAIT_ROSTER, "trait roster")
    if not entries then return nil, entries_error end
    if #entries == 0 then return nil, "the trait roster was empty" end

    local match = nil
    local seen = {}
    for index = 1, #entries do
        local trait = entries[index]
        if not is_valid(trait) then return nil, "a trait roster entry was no longer valid" end
        local class_ok, is_trait = pcall(function() return trait:IsA(TRAIT_ASSET_PATH) end)
        if not class_ok or not is_trait then return nil, "a trait roster entry had the wrong class" end

        local id_ok, raw_skill_id = pcall(function() return trait.Skill_ID end)
        local skill_id = id_ok and exact_string(raw_skill_id) or nil
        if skill_id == nil or skill_id == "" then
            return nil, "a trait roster entry had no readable Skill_ID"
        end
        if seen[skill_id] then return nil, "the trait roster contained duplicate Skill_ID values" end
        seen[skill_id] = true

        if match == nil and skill_id == trait_id then
            local address = get_object_address(trait)
            if address == nil then return nil, "the matched trait address was unreadable" end
            match = { trait = trait, address = address, name = raw_skill_id }
        end
    end
    if match == nil then return nil, "could not resolve trait id " .. sanitize(trait_id) end
    return match, nil
end

-- ONE-WAY. ForceLevelUpTo has no inverse in this build; a level cannot be lowered again.
local function handle_add_level(value)
    local query_only = is_read_only_query(value)
    local requested = query_only and nil or tonumber(value)
    if not query_only and (not is_finite_number(requested) or requested % 1 ~= 0
        or requested < 1 or requested > MAX_CHARACTER_LEVEL) then
        return false, "rejected", "Add Level requires a whole target level from 1 to "
            .. tostring(MAX_CHARACTER_LEVEL) .. ".", ""
    end
    if requested ~= nil then requested = math.floor(requested) end

    local player, _identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local subsystem, subsystem_error = get_char_dev_subsystem(player)
    if not subsystem then return false, "rejected", subsystem_error, "" end
    local subsystem_address = get_object_address(subsystem)
    if subsystem_address == nil then
        return false, "rejected", "The character development subsystem address was unreadable.", ""
    end

    local before, before_error = read_character_level(subsystem)
    if before == nil then return false, "rejected", before_error, "" end
    if query_only then
        local xp_ok, xp = pcall(function() return subsystem:GetCurrentXP() end)
        local xp_text = (xp_ok and is_finite_number(xp)) and tostring(math.floor(xp)) or "unknown"
        return true, "applied", "Character level read as " .. tostring(before) .. " (XP " .. xp_text .. ").",
            tostring(before)
    end

    -- Forward-only. Refusing a lower or equal target is what keeps this call safe: there is
    -- no route back down, so a mistaken lower target must never be treated as a no-op.
    if requested <= before then
        return false, "rejected", "Add Level is one-way and cannot lower or repeat level "
            .. tostring(before) .. "; request a higher target.", ""
    end

    local call_ok, call_error = pcall(function()
        subsystem:ForceLevelUpTo(requested, true)
    end)
    if get_object_address(subsystem) ~= subsystem_address then
        return false, "rejected", "The character development subsystem identity changed during the level change. "
            .. "Restore the pretest save backup before saving.", ""
    end

    local after, after_error = read_character_level(subsystem)
    if after == nil then
        return false, "rejected", "Add Level could not verify its readback ("
            .. sanitize(call_error or after_error) .. "). Restore the pretest save backup before saving.", ""
    end
    if call_ok and after == requested then
        return true, "applied", "Character level set to " .. tostring(after)
            .. " with trait points granted. This is one-way; the closed-game save backup is the only recovery.",
            tostring(after)
    end
    if after == before then
        return false, "rejected", "Add Level did not change the level ("
            .. sanitize(call_error or after) .. "); level " .. tostring(before) .. " remained exact.", ""
    end
    return false, "rejected", "Add Level reached level " .. tostring(after) .. " instead of "
        .. tostring(requested) .. " and cannot be reversed. Restore the pretest save backup before saving.", ""
end

-- ONE-WAY. UnblockTraitToLevel has no inverse; a trait cannot be re-blocked.
local function handle_unblock_trait(value)
    local text = tostring(value or "")
    if is_read_only_query(value) then
        return false, "rejected", "Unblock Trait requires a trait id, optionally traitId|level.", ""
    end

    local fields = {}
    local cursor = 1
    while true do
        local separator = string.find(text, "|", cursor, true)
        if separator == nil then
            fields[#fields + 1] = string.sub(text, cursor)
            break
        end
        fields[#fields + 1] = string.sub(text, cursor, separator - 1)
        cursor = separator + 1
        if #fields > 2 then break end
    end
    if #fields == 0 or #fields > 2 then
        return false, "rejected", "Unblock Trait expects traitId[|level].", ""
    end

    local trait_id = fields[1]:match("^%s*(.-)%s*$")
    if trait_id == nil or trait_id == "" or #trait_id > 128 or trait_id:match("^[%w_.%-]+$") == nil then
        return false, "rejected", "Unblock Trait requires a simple trait id.", ""
    end

    local target_level = 1
    if #fields == 2 then
        target_level = tonumber(fields[2])
        if not is_finite_number(target_level) or target_level % 1 ~= 0
            or target_level < 1 or target_level > MAX_TRAIT_UNBLOCK_LEVEL then
            return false, "rejected", "Unblock Trait level must be a whole number from 1 to "
                .. tostring(MAX_TRAIT_UNBLOCK_LEVEL) .. ".", ""
        end
        target_level = math.floor(target_level)
    end

    local player, _identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local subsystem, subsystem_error = get_char_dev_subsystem(player)
    if not subsystem then return false, "rejected", subsystem_error, "" end
    local subsystem_address = get_object_address(subsystem)
    if subsystem_address == nil then
        return false, "rejected", "The character development subsystem address was unreadable.", ""
    end

    -- The trait must already exist in the roster; an unknown id is rejected rather than
    -- silently unblocking nothing. Resolution is roster-first so a raw request string never
    -- reaches an FName-typed engine call: the matched trait's own Skill_ID value is the only
    -- argument shape the pinned UE4SS build marshals safely into `const FName&`.
    local resolved, resolve_error = resolve_trait_id(subsystem, trait_id)
    if not resolved then
        return false, "rejected", "Unblock Trait " .. resolve_error .. ".", ""
    end
    local trait_address = resolved.address
    local trait_name = resolved.name

    -- Second resolution source: the subsystem's own name map must return the same trait the
    -- roster identified before any FName-typed unblock call is made.
    local lookup_ok, looked_up = pcall(function() return subsystem:GetTrait(trait_name) end)
    if not lookup_ok or not is_valid(looked_up) or get_object_address(looked_up) ~= trait_address then
        return false, "rejected", "Unblock Trait could not resolve trait id " .. sanitize(trait_id) .. ".", ""
    end

    local before_ok, before = pcall(function() return subsystem:GetTraitUnblockedLevel(trait_name) end)
    if not before_ok or not is_finite_number(before) then
        return false, "rejected", "Trait unblocked-level readback was invalid.", ""
    end
    before = math.floor(before)
    if before >= target_level then
        return true, "applied", "Trait " .. sanitize(trait_id) .. " is already unblocked to level "
            .. tostring(before) .. ".", tostring(before)
    end

    local call_ok, call_error = pcall(function()
        -- bCanShowVideo and bShowNotification stay false so the unblock is quiet.
        subsystem:UnblockTraitToLevel(trait_name, target_level, false, false)
    end)
    if get_object_address(subsystem) ~= subsystem_address then
        return false, "rejected", "The character development subsystem identity changed during the unblock. "
            .. "Restore the pretest save backup before saving.", ""
    end

    local after_ok, after = pcall(function() return subsystem:GetTraitUnblockedLevel(trait_name) end)
    if not after_ok or not is_finite_number(after) then
        return false, "rejected", "Unblock Trait could not verify its readback ("
            .. sanitize(call_error) .. "). Restore the pretest save backup before saving.", ""
    end
    after = math.floor(after)
    if call_ok and after >= target_level then
        return true, "applied", "Trait " .. sanitize(trait_id) .. " unblocked to level " .. tostring(after)
            .. ". This is one-way; the closed-game save backup is the only recovery.", tostring(after)
    end
    if call_ok then
        -- The engine call succeeded but the immediate readback has not caught up. The live
        -- game commits the unblocked level a beat after UnblockTraitToLevel returns, so the
        -- verdict is deferred to a bounded later-tick verification (see
        -- poll_unblock_verification); this command answers once the commit is observable.
        pending_unblock_verify = {
            request_id = current_request_id,
            trait_id = trait_id,
            trait_name = trait_name,
            target_level = target_level,
            before = before,
            subsystem = subsystem,
            subsystem_address = subsystem_address,
            ticks_left = MAX_UNBLOCK_VERIFY_TICKS,
        }
        return false, "commit-pending", "", ""
    end
    if after == before then
        return false, "rejected", "Unblock Trait did not change trait " .. sanitize(trait_id)
            .. " (" .. sanitize(call_error or after) .. "); level " .. tostring(before) .. " remained exact.", ""
    end
    return false, "rejected", "Unblock Trait reached level " .. tostring(after) .. " instead of "
        .. tostring(target_level) .. " and cannot be reversed. Restore the pretest save backup before saving.", ""
end

-- Resolves a deferred Unblock Trait verdict on the game thread. Runs once per bridge poll
-- (never more than one queued read at a time) until the committed level reaches the target,
-- the subsystem identity changes, the bounded attempt budget is exhausted, or the record is
-- superseded or cleared.
local function poll_unblock_verification()
    local record = pending_unblock_verify
    if record == nil or unblock_verify_queued then return end
    unblock_verify_queued = true
    local queued, queue_error = pcall(function()
        ExecuteInGameThread(function()
            unblock_verify_queued = false
            local active_record = pending_unblock_verify
            if active_record == nil then return end
            active_record.ticks_left = active_record.ticks_left - 1
            if get_object_address(active_record.subsystem) ~= active_record.subsystem_address then
                pending_unblock_verify = nil
                write_response(active_record.request_id, false, "rejected",
                    "Unblock Trait could not verify before the character development subsystem "
                    .. "identity changed. Restore the pretest save backup before saving.", "")
                return
            end
            local read_ok, level = pcall(function()
                return active_record.subsystem:GetTraitUnblockedLevel(active_record.trait_name)
            end)
            local committed = read_ok and is_finite_number(level) and math.floor(level) or nil
            if committed ~= nil and committed >= active_record.target_level then
                pending_unblock_verify = nil
                write_response(active_record.request_id, true, "applied",
                    "Trait " .. sanitize(active_record.trait_id) .. " unblocked to level "
                    .. tostring(committed) .. ". This is one-way; the closed-game save backup is the only recovery.",
                    tostring(committed))
                return
            end
            if active_record.ticks_left <= 0 then
                pending_unblock_verify = nil
                write_response(active_record.request_id, false, "rejected",
                    "Unblock Trait did not change trait " .. sanitize(active_record.trait_id)
                    .. " within the bounded verification window; level "
                    .. tostring(committed or active_record.before) .. " remained exact.", "")
            end
        end, EGameThreadMethod.EngineTick)
    end)
    if not queued then
        unblock_verify_queued = false
        log("unblock verification queue failed: " .. sanitize(queue_error))
    end
end

local function read_quest_objectives(quest)
    local objectives_ok, objectives = pcall(function() return quest.Objectives end)
    if not objectives_ok or objectives == nil then return nil, nil, "Quest Objectives were unavailable." end
    local count_ok, objective_count = pcall(function() return #objectives end)
    if not count_ok or not is_finite_number(objective_count) or objective_count < 0 or objective_count % 1 ~= 0 then
        return nil, nil, "Quest objective count was invalid."
    end

    local expected_count = math.min(objective_count, MAX_OBJECTIVES_PER_QUEST)
    local records = {}
    local iterate_ok, iterate_error = pcall(function()
        for index = 1, expected_count do
            local remote_objective = objectives[index]
            local objective = unwrap_remote_value(remote_objective)
            if objective == nil then error("Quest objective was unavailable.") end

            local fields_ok, text_value, state_value, current_count, max_count, optional = pcall(function()
                return objective.Text, objective.State, objective.CurrentCount, objective.MaxCount, objective.bIsOptional
            end)
            if not fields_ok then error("Quest objective fields were unavailable: " .. sanitize(text_value)) end
            if not is_finite_number(current_count) or current_count < 0 or current_count > 1000000000 then
                error("Quest objective current count was invalid.")
            end
            if not is_finite_number(max_count) or max_count < 0 or max_count > 1000000000 or max_count % 1 ~= 0 then
                error("Quest objective maximum count was invalid.")
            end
            if type(optional) ~= "boolean" then error("Quest objective optional state was invalid.") end

            local encoded_text, text_error = read_encoded_ftext(text_value, "Untitled objective")
            if not encoded_text then error(text_error) end
            table.insert(records, {
                text = encoded_text,
                state = normalized_quest_state(state_value),
                current_count = current_count,
                max_count = math.floor(max_count),
                optional = optional,
            })
        end
    end)
    if not iterate_ok then return nil, nil, sanitize(iterate_error) end
    if #records ~= expected_count then return nil, nil, "Quest objective iteration returned an incomplete snapshot." end
    return objective_count, records, nil
end

local function read_quest_record(quest, tracked_address)
    if not is_valid(quest) then return nil, "An opened quest was no longer valid." end
    local class_ok, is_quest = pcall(function() return quest:IsA("/Script/Quest.Quest") end)
    if not class_ok or not is_quest then return nil, "An opened quest had the wrong class." end

    local fields_ok, title_value, state_value = pcall(function() return quest.Title, quest.State end)
    if not fields_ok then return nil, "Quest fields were unavailable: " .. sanitize(title_value) end
    local encoded_title, title_error = read_encoded_ftext(title_value, "Untitled quest")
    if not encoded_title then return nil, title_error end
    local objective_count, objectives, objective_error = read_quest_objectives(quest)
    if not objectives then return nil, objective_error end

    return {
        title = encoded_title,
        state = normalized_quest_state(state_value),
        tracked = tracked_address ~= nil and get_object_address(quest) == tracked_address,
        objective_count = objective_count,
        objectives = objectives,
    }, nil
end

local function handle_quest_journal(value)
    if not is_read_only_query(value) then
        return false, "rejected", "Quest Journal is a read-only capability and does not accept a value.", ""
    end
    local _, identity, player_error = get_live_player_context()
    if not identity then return false, "rejected", player_error, "" end
    local journal, journal_error = get_quest_journal(identity)
    if not journal then return false, "rejected", journal_error, "" end

    local tracked_ok, tracked_quest = pcall(function() return journal:GetTrackedQuest() end)
    if not tracked_ok then return false, "rejected", "Tracked quest readback failed.", "" end
    local tracked_address = get_object_address(tracked_quest)

    local opened_out = {}
    local opened_ok, opened_error = pcall(function() journal:GetOpenedQuests(opened_out) end)
    if not opened_ok then
        return false, "rejected", "GetOpenedQuests readback failed: " .. sanitize(opened_error), ""
    end
    local opened_quests = opened_out
    local count_ok, open_quest_count = pcall(function() return #opened_quests end)
    if not count_ok or not is_finite_number(open_quest_count) or open_quest_count < 0 or open_quest_count % 1 ~= 0 then
        return false, "rejected", "Opened quest count was invalid.", ""
    end

    local expected_quest_count = math.min(open_quest_count, MAX_QUESTS)
    local quests = {}
    local iterate_ok, iterate_error = pcall(function()
        for index = 1, expected_quest_count do
            local remote_quest = opened_quests[index]
            local quest, quest_error = read_quest_record(unwrap_remote_value(remote_quest), tracked_address)
            if not quest then error(quest_error) end
            table.insert(quests, quest)
        end
    end)
    if not iterate_ok then return false, "rejected", "Quest Journal snapshot failed: " .. sanitize(iterate_error), "" end
    if #quests ~= expected_quest_count then
        return false, "rejected", "Quest Journal iteration returned an incomplete snapshot.", ""
    end

    table.sort(quests, function(first, second) return first.title:lower() < second.title:lower() end)
    local records = {
        "schema=1",
        "open_total=" .. tostring(open_quest_count),
        "returned=" .. tostring(#quests),
        "truncated=" .. (open_quest_count > #quests and "1" or "0"),
    }
    for quest_index, quest in ipairs(quests) do
        local zero_based_index = quest_index - 1
        table.insert(records, table.concat({
            "q=" .. tostring(zero_based_index),
            quest.state,
            quest.tracked and "1" or "0",
            quest.title,
            tostring(quest.objective_count),
            quest.objective_count > #quest.objectives and "1" or "0",
        }, ","))
        for _, objective in ipairs(quest.objectives) do
            table.insert(records, table.concat({
                "o=" .. tostring(zero_based_index),
                objective.state,
                objective.text,
                string.format("%.6f", objective.current_count),
                tostring(objective.max_count),
                objective.optional and "1" or "0",
            }, ","))
        end
    end

    local readback = table.concat(records, ";")
    if #readback > MAX_QUEST_READBACK_BYTES then
        return false, "rejected", "Quest Journal exceeded its bounded readback size.", ""
    end
    return true, "applied", string.format("Read %d open quest(s); returned %d bounded record(s).", open_quest_count, #quests), readback
end

local function read_player_transform(player)
    local read_ok, location, rotation = pcall(function()
        return player:K2_GetActorLocation(), player:K2_GetActorRotation()
    end)
    if not read_ok or location == nil or rotation == nil then return nil, nil, "The player transform is unavailable." end
    if not (is_finite_number(location.X) and is_finite_number(location.Y) and is_finite_number(location.Z)
        and is_finite_number(rotation.pitch) and is_finite_number(rotation.Yaw) and is_finite_number(rotation.Roll)) then
        return nil, nil, "The player transform contained an invalid number."
    end
    return {
        X = location.X,
        Y = location.Y,
        Z = location.Z,
    }, {
        pitch = rotation.pitch,
        Yaw = rotation.Yaw,
        Roll = rotation.Roll,
    }, nil
end

local function squared_distance(first, second)
    if first == nil or second == nil then return nil end
    if not (is_finite_number(first.X) and is_finite_number(first.Y) and is_finite_number(first.Z)
        and is_finite_number(second.X) and is_finite_number(second.Y) and is_finite_number(second.Z)) then return nil end
    local dx = first.X - second.X
    local dy = first.Y - second.Y
    local dz = first.Z - second.Z
    return dx * dx + dy * dy + dz * dz
end

local function handle_save_location(value)
    local name = tostring(value or ""):match("^%s*(.-)%s*$")
    if name == "" or #name > 64 or name:find("[\r\n;=]") then
        return false, "rejected", "Saved location names must contain 1 to 64 safe characters.", ""
    end
    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local location, rotation, transform_error = read_player_transform(player)
    if not location then return false, "rejected", transform_error, "" end

    local session_locations = saved_locations[identity.key]
    if session_locations == nil then
        session_locations = {}
        saved_locations[identity.key] = session_locations
    end
    session_locations[name] = {
        player_address = identity.player_address,
        world_address = identity.world_address,
        location = location,
        rotation = rotation,
    }
    return true, "applied", "Saved the current location as " .. name .. ".", name
end

local function handle_teleport_saved_location(value)
    local name = tostring(value or "")
    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local session_locations = saved_locations[identity.key]
    local destination = session_locations and session_locations[name] or nil
    if not destination
        or destination.player_address ~= identity.player_address
        or destination.world_address ~= identity.world_address then
        return false, "rejected", "That saved location does not belong to this player and world session.", ""
    end

    local origin, origin_rotation, origin_error = read_player_transform(player)
    if not origin then return false, "rejected", origin_error, "" end
    local teleport_ok, moved = pcall(function() return player:K2_TeleportTo(destination.location, destination.rotation) end)
    local arrived_location = read_player_transform(player)
    local arrival_distance = squared_distance(arrived_location, destination.location)
    if not teleport_ok or moved ~= true or arrival_distance == nil or arrival_distance > 100 then
        local rollback_call_ok, rollback_moved = pcall(function() return player:K2_TeleportTo(origin, origin_rotation) end)
        local rollback_location = read_player_transform(player)
        local rollback_distance = squared_distance(rollback_location, origin)
        local rollback_verified = rollback_call_ok and rollback_moved == true and rollback_distance ~= nil and rollback_distance <= 100
        local rollback_message = rollback_verified and "the original position was restored and verified"
            or "the original position could not be verified after rollback"
        return false, "rejected", "Teleport did not reach the saved location; " .. rollback_message .. ".", ""
    end
    return true, "applied", "Teleported to " .. name .. " and verified the destination.", name
end

local function handle_hud_visible(value)
    local query_only = is_read_only_query(value)
    local requested = query_only and nil or parse_boolean(value)
    if not query_only and requested == nil then return false, "rejected", "HUD Visible requires a boolean value.", "" end
    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local subsystem, subsystem_error = get_subsystem(player, "/Script/DogwoodUI.HUDManagerSubsystem", "world", "HUD manager subsystem")
    if not subsystem then return false, "rejected", subsystem_error, "" end

    local capability = "visuals:hud-visible"
    if query_only then
        local read_ok, visible = pcall(function() return subsystem:IsHUDVisible() end)
        if not read_ok or type(visible) ~= "boolean" then return false, "rejected", "HUD visibility readback was invalid.", "" end
        return true, "applied", "HUD visibility read successfully.", visible and "1" or "0"
    end
    local snapshot = snapshots[capability]
    if snapshot and not snapshot_binding_matches(snapshot, subsystem, identity) then
        local restored, restore_error = restore_snapshot(capability)
        if not restored then
            return false, "rejected", "The prior HUD baseline belongs to another live identity and could not be restored: " .. sanitize(restore_error), ""
        end
        snapshot = nil
    end
    if snapshot == nil then
        local baseline_ok, baseline = pcall(function() return subsystem:IsHUDVisible() end)
        if not baseline_ok or type(baseline) ~= "boolean" then return false, "rejected", "HUD visibility baseline readback was invalid.", "" end
        snapshot = {
            target = subsystem,
            target_address = get_object_address(subsystem),
            world = identity.world,
            world_address = identity.world_address,
            baseline = baseline,
        }
        if snapshot.target_address == nil then return false, "rejected", "The HUD target identity was unavailable.", "" end
        snapshot.restore = function(record)
            if not snapshot_binding_is_live(record) then return false, "the HUD binding is no longer live" end
            local set_ok = pcall(function() record.target:SetHUDVisible(record.baseline) end)
            local read_ok, restored = pcall(function() return record.target:IsHUDVisible() end)
            return set_ok and read_ok and restored == record.baseline,
                "HUD baseline readback=" .. sanitize(restored)
        end
        snapshots[capability] = snapshot
    end

    local set_ok, set_error = pcall(function() subsystem:SetHUDVisible(requested) end)
    local read_ok, readback = pcall(function() return subsystem:IsHUDVisible() end)
    if not set_ok or not read_ok or readback ~= requested then
        local restored, restore_error = restore_snapshot(capability)
        if restored then active[capability] = nil else active[capability] = true end
        return false, "rejected", "HUD visibility did not match (" .. sanitize(set_error or readback)
            .. "); baseline rollback=" .. sanitize(restored and "verified" or restore_error), ""
    end

    if readback == snapshot.baseline then
        snapshots[capability] = nil
        active[capability] = nil
    else
        active[capability] = true
    end
    return true, "applied", "HUD is now " .. (requested and "visible" or "hidden") .. ".", requested and "1" or "0"
end

local function handle_game_speed(value)
    local query_only = is_read_only_query(value)
    local requested = query_only and nil or parse_number(value, 0.1, 3.0)
    if not query_only and requested == nil then return false, "rejected", "Game Speed requires a number from 0.1 to 3.0.", "" end
    local player, identity, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local statics, statics_error = get_default_object("/Script/Engine.Default__GameplayStatics", "gameplay statics")
    if not statics then return false, "rejected", statics_error, "" end

    local capability = "world:game-speed"
    if query_only then
        local read_ok, speed = pcall(function() return statics:GetGlobalTimeDilation(player) end)
        if not read_ok or not is_finite_number(speed) or speed <= 0 then return false, "rejected", "Game Speed readback was invalid.", "" end
        return true, "applied", string.format("Game Speed read as %.2fx.", speed), string.format("%.6f", speed)
    end
    local snapshot = snapshots[capability]
    if snapshot and not snapshot_binding_matches(snapshot, statics, identity) then
        local restored, restore_error = restore_snapshot(capability)
        if not restored then
            return false, "rejected", "The prior game-speed baseline belongs to another live identity and could not be restored: " .. sanitize(restore_error), ""
        end
        snapshot = nil
    end
    if snapshot == nil then
        local baseline_ok, baseline = pcall(function() return statics:GetGlobalTimeDilation(player) end)
        if not baseline_ok or not is_finite_number(baseline) or baseline <= 0 then return false, "rejected", "Game Speed baseline readback was invalid.", "" end
        snapshot = {
            target = statics,
            target_address = get_object_address(statics),
            context = identity.world,
            world = identity.world,
            world_address = identity.world_address,
            baseline = baseline,
        }
        if snapshot.target_address == nil then return false, "rejected", "The game-speed target identity was unavailable.", "" end
        snapshot.restore = function(record)
            if not snapshot_binding_is_live(record) or not object_matches_address(record.context, record.world_address) then
                return false, "the game-speed binding is no longer live"
            end
            local set_ok = pcall(function() record.target:SetGlobalTimeDilation(record.context, record.baseline) end)
            local read_ok, restored = pcall(function() return record.target:GetGlobalTimeDilation(record.context) end)
            return set_ok and read_ok and is_finite_number(restored) and math.abs(restored - record.baseline) <= 0.01,
                "game-speed baseline readback=" .. sanitize(restored)
        end
        snapshots[capability] = snapshot
    end

    local set_ok, set_error = pcall(function() statics:SetGlobalTimeDilation(player, requested) end)
    local read_ok, readback = pcall(function() return statics:GetGlobalTimeDilation(player) end)
    if not set_ok or not read_ok or not is_finite_number(readback) or math.abs(readback - requested) > 0.01 then
        local restored, restore_error = restore_snapshot(capability)
        if restored then active[capability] = nil else active[capability] = true end
        return false, "rejected", "Game Speed did not match (" .. sanitize(set_error or readback)
            .. "); baseline rollback=" .. sanitize(restored and "verified" or restore_error), ""
    end

    if math.abs(readback - snapshot.baseline) <= 0.01 then
        snapshots[capability] = nil
        active[capability] = nil
    else
        active[capability] = true
    end
    return true, "applied", string.format("Game Speed set to %.2fx.", readback), string.format("%.6f", readback)
end

local function handle_location_readback()
    local player, _, player_error = get_live_player_context()
    if not player then return false, "rejected", player_error, "" end
    local location = player:K2_GetActorLocation()
    if location == nil or type(location.X) ~= "number" or type(location.Y) ~= "number" or type(location.Z) ~= "number" then
        return false, "rejected", "The player location readback was invalid.", ""
    end
    local readback = string.format("x=%.6f;y=%.6f;z=%.6f", location.X, location.Y, location.Z)
    return true, "applied", "Player location read successfully.", readback
end

handlers["player:infinite-health"] = handle_infinite_health
handlers["player:unlimited-stamina"] = handle_unlimited_stamina
handlers["player:blood-energy"] = handle_blood_energy
handlers["player:god-mode"] = handle_god_mode
handlers["player:player-info"] = handle_player_info
handlers["player:trait-points"] = handle_trait_points
handlers["player:add-gold"] = handle_add_gold
handlers["inventory:add-item"] = handle_add_item
handlers["player:add-level"] = handle_add_level
handlers["player:unblock-trait"] = handle_unblock_trait
handlers["combat:infinite-blood-energy"] = handle_infinite_blood
handlers["combat:rpg-difficulty"] = handle_rpg_difficulty
handlers["combat:action-difficulty"] = handle_action_difficulty
handlers["quests:journal-readback"] = handle_quest_journal
handlers["teleport:save-location"] = handle_save_location
handlers["teleport:teleport-saved-location"] = handle_teleport_saved_location
handlers["visuals:hud-visible"] = handle_hud_visible
handlers["world:game-speed"] = handle_game_speed
handlers["world:location-readback"] = handle_location_readback

local function execute_command(fields)
    if not game_thread_available then
        write_response(fields.request_id, false, "rejected", "The safe game-thread route is unavailable.", "")
        return
    end

    local handler = handlers[fields.capability]
    if handler == nil then
        write_response(fields.request_id, false, "rejected", "Capability has no bridge handler.", "")
        return
    end

    current_request_id = fields.request_id
    if pending_unblock_verify ~= nil and pending_unblock_verify.request_id ~= fields.request_id then
        -- A new command arrived before the deferred verification settled (client timeout and
        -- retry); resolve the stale record so the response file cannot be written out of order.
        local superseded = pending_unblock_verify
        pending_unblock_verify = nil
        write_response(superseded.request_id, false, "rejected",
            "Unblock Trait verification was superseded by a newer bridge command; re-dispatch "
            .. "the trait id to confirm its level.", "")
    end

    local queued, queue_error = pcall(function()
        ExecuteInGameThread(function()
            local ok, accepted, status, message, readback = pcall(handler, fields.value)
            if not ok then
                log("command " .. sanitize(fields.capability) .. " failed: " .. sanitize(accepted))
                write_response(fields.request_id, false, "rejected", "The reflected game call failed safely: " .. sanitize(accepted), "")
                return
            end
            if status == "commit-pending" then
                -- The handler registered a deferred Unblock Trait verification; its final
                -- response is written by poll_unblock_verification once the commit is observed.
                return
            end
            write_response(fields.request_id, accepted == true, status or "rejected", message or "", readback or "")
        end, EGameThreadMethod.EngineTick)
    end)
    if not queued then
        game_thread_available = false
        write_response(fields.request_id, false, "rejected", "Unable to queue the game-thread call: " .. sanitize(queue_error), "")
    end
end

local function poll_command()
    write_ready()
    poll_unblock_verification()
    local fields = read_fields(COMMAND_PATH)
    if not fields or not fields.request_id or fields.request_id == "" or fields.request_id == last_command_id then
        return false
    end

    last_command_id = fields.request_id
    if fields.protocol ~= BRIDGE_PROTOCOL or fields.boot_id ~= BOOT_ID then
        write_response(fields.request_id, false, "rejected", "Rejected stale or incompatible bridge command.", "")
        return false
    end

    local capability = fields.capability or ""
    if not CAPABILITY_SET[capability] or advertised_capabilities() == "" then
        write_response(fields.request_id, false, "rejected", "Capability is not advertised by the verified Dawnwalker bridge.", "")
        return false
    end

    execute_command(fields)
    return false
end

ModRef.OnUnload = function()
    local function unload_teardown()
        pending_unblock_verify = nil
        unblock_verify_queued = false
        local restored, restore_error = teardown_session_state("mod unload")
        if not restored then
            log("mod-unload teardown retained unresolved restore state: " .. sanitize(restore_error))
        end
        player_ready = false
        player_address = nil
        world_address = nil
    end

    local thread_check_ok, in_game_thread = pcall(IsInGameThread)
    if thread_check_ok and in_game_thread then
        local teardown_ok, teardown_error = pcall(unload_teardown)
        if not teardown_ok then log("mod-unload teardown failed safely: " .. sanitize(teardown_error)) end
        return
    end

    if EngineTickAvailable == true then
        local queued, queue_error = pcall(function()
            ExecuteInGameThread(unload_teardown, EGameThreadMethod.EngineTick)
        end)
        if queued then return end
        log("mod-unload teardown could not be queued: " .. sanitize(queue_error))
    end

    if session_state_has_pending_restore() then
        teardown_retry_pending = true
        retain_only_pending_active_state()
        log("mod-unload teardown could not run; unresolved restore state was retained instead of discarded")
    else
        clear_session_state()
    end
    player_ready = false
    player_address = nil
    world_address = nil
end

log("loaded bridge pilot version " .. BRIDGE_VERSION .. " boot=" .. BOOT_ID)
if write_ready() == false then log("ready handshake write failed: " .. READY_PATH) end
LoopAsync(150, poll_command)
