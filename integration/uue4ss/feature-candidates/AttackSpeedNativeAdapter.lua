local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_attack_speed_native_adapter")

-- Inert current-build candidate. No hooks, loops, capability registration, asset
-- loading, or calls occur until a reviewed game-thread host invokes resolve().
local Adapter = {}
local BUILD = "25129649"
local EXECUTABLE = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
local METADATA = "CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6"
local PLAYER = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local COMBAT = "/Script/DogwoodCombat.CombatComponentBase"
local CONFIG = "/Script/DogwoodCombat.CombatConfig"
local MODE = "/Script/DogwoodCombat.CombatMode"
local MAX_NATIVE_FLOAT = 3.4028234663852886e38
local UNRELATED_METRICS = {
    "DefaultRootMotionScaling", "DodgePlayrate", "ShadowDodgePlayrate", "BlockPlayrate",
    "BlockReactionPlayrate", "ParryPlayrate", "ParryVsUnarmedPlayrate", "ParryReactionPlayrate",
    "HitReactionPlayrate", "StrongHitReactionPlayrate", "TauntPlayrate", "TurnInPlacePlayrate",
    "AttackMetric", "StrongAttackMetric", "DodgeMetric", "ShadowDodgeMetric", "BlockMetric",
    "BlockReactionMetric", "ParryMetric", "ParryVsUnarmedMetric", "ParryReactionMetric",
    "HitReactionMetric", "StrongHitReactionMetric", "TauntMetric",
}

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function identifier(value, label)
    require_condition(type(value) == "string" and #value > 0 and #value <= 2048, label .. " is invalid")
    return value
end

local function object_id(object, class, label)
    require_condition(object ~= nil and object:IsValid() == true and object:IsA(class) == true,
        label .. " is unavailable or has an unexpected class")
    local name = identifier(object:GetFullName(), label .. " name")
    require_condition(not name:find("Default__", 1, true), label .. " is a class default object")
    local address = object:GetAddress()
    require_condition(finite(address) and address > 0, label .. " address is invalid")
    return name .. "@" .. tostring(address)
end

local function unwrap(value)
    local ok, unwrapped = pcall(function() return value:get() end)
    return ok and unwrapped or value
end

local function metrics_for(mode)
    local metrics = mode.MetricsScalingSettings
    require_condition(metrics ~= nil and metrics:type() == "UScriptStruct"
        and metrics:IsValid() == true and metrics:IsMappedToObject() == true
        and metrics:IsMappedToProperty() == true, "MetricsScalingSettings is not a mapped native struct")
    local address = metrics:GetStructAddress()
    local property = metrics:GetPropertyAddress()
    require_condition(finite(address) and address > 0 and finite(property) and property > 0,
        "Native struct identity is unavailable")
    return metrics, tostring(address) .. "/" .. tostring(property)
end

local function read_values(mode)
    local metrics = metrics_for(mode)
    local fingerprint = {}
    for _, field in ipairs(UNRELATED_METRICS) do
        local value = metrics[field]
        require_condition(finite(value), "Invalid unrelated native metric: " .. field)
        fingerprint[#fingerprint + 1] = field .. "=" .. string.format("%.17g", value)
    end
    require_condition(finite(mode.DodgeStaminaCost), "Dodge stamina baseline is invalid")
    fingerprint[#fingerprint + 1] = "DodgeStaminaCost=" .. string.format("%.17g", mode.DodgeStaminaCost)
    require_condition(finite(metrics.AttackPlayrate) and metrics.AttackPlayrate > 0
        and finite(metrics.StrongAttackPlayrate) and metrics.StrongAttackPlayrate > 0,
        "Native attack playrates are invalid")
    return { attack = metrics.AttackPlayrate, strong_attack = metrics.StrongAttackPlayrate,
        unrelated_fingerprint = table.concat(fingerprint, ";") }
end

function Adapter.new(deps)
    for _, name in ipairs({ "get_identity", "is_in_game_thread", "get_player", "get_player_controller",
        "find_all_of", "get_write_review" }) do
        require_condition(type(deps) == "table" and type(deps[name]) == "function", "Missing adapter dependency: " .. name)
    end

    local function session()
        require_condition(deps.is_in_game_thread() == true, "Attack adapter requires the game thread")
        local identity = deps.get_identity()
        require_condition(type(identity) == "table" and identity.build_id == BUILD
            and identity.executable_sha256 == EXECUTABLE and identity.metadata_sha256 == METADATA,
            "Current attack candidate build or metadata differs")
        return identifier(identity.boot_id, "boot identity")
    end

    local function player_context()
        local boot = session()
        local player = deps.get_player()
        local player_key = object_id(player, PLAYER, "local player")
        local controller = deps.get_player_controller()
        object_id(controller, "/Script/Engine.PlayerController", "local controller")
        require_condition(controller:IsLocalController() == true
            and object_id(controller:K2_GetPawn(), PLAYER, "controller pawn") == player_key,
            "Local controller and player disagree")
        local world_key = object_id(player:GetWorld(), "/Script/Engine.World", "player world")
        local combat = player.CombatComponent
        local combat_key = object_id(combat, "/Script/DogwoodCombat.PlayerCombatComponent", "player combat")
        require_condition(object_id(combat:GetOwner(), PLAYER, "combat owner") == player_key,
            "Combat component does not belong to the local player")
        local config = combat:GetConfig()
        local config_key = object_id(config, CONFIG, "combat config")
        require_condition(object_id(combat.Config, CONFIG, "config property") == config_key,
            "Combat config getter and property disagree")
        return { identity = table.concat({ boot, player_key, world_key, combat_key, config_key }, "|"),
            player_key = player_key, combat_key = combat_key, config_key = config_key, config = config }
    end

    local adapter = {}
    function adapter.resolve()
        local current = player_context()
        local modes, identities, seen = {}, {}, {}
        for enum_value = 1, 5 do
            require_condition(current.config.CombatModes:Contains(enum_value) == true, "A reviewed player combat mode is missing")
            local mode = unwrap(current.config.CombatModes:Find(enum_value))
            local key = object_id(mode, MODE, "player combat mode")
            require_condition(not seen[key], "Player combat modes alias the same asset")
            seen[key] = true
            local _, struct_key = metrics_for(mode)
            modes[enum_value] = { object = mode, key = key, struct_key = struct_key }
            identities[enum_value] = key .. "/" .. struct_key
            read_values(mode)
        end

        -- Check every loaded non-player component, including all map keys. This
        -- is bounded read-only evidence, not proof about future streamed assets.
        local components = deps.find_all_of("CombatComponentBase")
        require_condition(type(components) == "table" and #components > 0 and #components <= 4096,
            "Loaded combat-component scan is empty or exceeds its bound")
        local found_player, nonplayer_count = false, 0
        for _, combat in ipairs(components) do
            local key = object_id(combat, COMBAT, "scanned combat component")
            if key == current.combat_key then
                found_player = true
            else
                local owner_key = object_id(combat:GetOwner(), "/Script/Engine.Actor", "scanned combat owner")
                require_condition(owner_key ~= current.player_key, "Multiple combat components on the player need review")
                local config = combat:GetConfig()
                local config_key = object_id(config, CONFIG, "non-player combat config")
                require_condition(config_key ~= current.config_key, "A non-player actor shares the player's combat config")
                local count = 0
                config.CombatModes:ForEach(function(_, value)
                    count = count + 1
                    require_condition(count <= 64, "Non-player combat map exceeds its bound")
                    require_condition(not seen[object_id(unwrap(value), MODE, "non-player combat mode")],
                        "A non-player actor shares a player combat mode")
                end)
                require_condition(count > 0, "Non-player combat map is empty")
                nonplayer_count = nonplayer_count + 1
            end
        end
        require_condition(found_player and nonplayer_count > 0, "Player and non-player isolation witnesses are required")
        local mode_set_key = table.concat(identities, "|")

        local function guard()
            require_condition(player_context().identity == current.identity, "Player/world/config changed during attack transaction")
        end

        local function write_review()
            local review = deps.get_write_review()
            require_condition(type(review) == "table" and review.context_identity == current.identity
                and review.mode_set_identity == mode_set_key and review.native_struct_write_verified == true
                and review.player_only_assets_verified == true,
                "Current native write/restoration and player-only asset review is missing")
            identifier(review.evidence_id, "native review evidence")
        end

        local context = { identity = current.identity, modes = {}, player_modes_verified = true,
            npc_isolation_verified = false, mode_set_identity = mode_set_key,
            nonplayer_component_count = nonplayer_count }
        for enum_value, record in ipairs(modes) do
            local function resolve_mode()
                guard()
                require_condition(current.config.CombatModes:Contains(enum_value) == true, "Player mode disappeared")
                local mode = unwrap(current.config.CombatModes:Find(enum_value))
                require_condition(object_id(mode, MODE, "current player mode") == record.key, "Player mode changed")
                local metrics, key = metrics_for(mode)
                require_condition(key == record.struct_key, "Mapped native struct identity changed")
                return mode, metrics
            end
            context.modes[enum_value] = {
                enum_value = enum_value, identity = identities[enum_value],
                read = function() local mode = resolve_mode(); return read_values(mode) end,
                write_attack = function(value)
                    require_condition(finite(value) and value > 0 and value <= MAX_NATIVE_FLOAT, "Invalid native attack value")
                    local _, metrics = resolve_mode()
                    write_review()
                    metrics.AttackPlayrate = value
                end,
                write_strong_attack = function(value)
                    require_condition(finite(value) and value > 0 and value <= MAX_NATIVE_FLOAT, "Invalid native strong-attack value")
                    local _, metrics = resolve_mode()
                    write_review()
                    metrics.StrongAttackPlayrate = value
                end,
            }
        end
        guard()
        -- A loaded-NPC scan alone cannot authorize mutating shared data assets.
        -- Read-only callers may inspect the context without supplying this review.
        local reviewed, reason = pcall(write_review)
        context.npc_isolation_verified = reviewed
        context.write_review_error = not reviewed and tostring(reason) or nil
        return context
    end
    return adapter
end

return Adapter
