local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("combat_discovery")

-- Reads reviewed reflected fields only. Loaded config/mode assets may be shared
-- with NPCs: observing them never establishes that writing them is safe.
local M, SECTION = {}, "DWCombatDiscovery"
local MODES = { "VampireSword", "Sword", "VampireHandToHand", "HandToHand", "Fistfight" }
local METRICS = { "AttackPlayrate", "StrongAttackPlayrate", "DodgePlayrate", "BlockPlayrate", "DefaultRootMotionScaling" }
local EFFECT = "/Game/_Dawnwalker/Combat/Focus/Sword/SwiftAdvance/GE_SwiftAdvance_AttackSpeed_Lvl1"
local ATTRIBUTE = "AttackSpeedMultiplierAdditive"

local function finite(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Nonfinite effect number")
    return value
end
local function text(value)
    if type(value) ~= "string" then value = value:ToString() end
    assert(type(value) == "string" and #value <= 2048 and not value:find("[%c]"), "Unsupported effect text")
    return value
end
local function unwrap(value)
    local ok, result = pcall(function() return value:get() end)
    return ok and result or value
end
local function array(value)
    assert(value ~= nil, "Effect array unavailable")
    local result = {}
    if type(value) == "table" and value.ForEach == nil then
        local count = 0
        for key in pairs(value) do assert(type(key) == "number" and key >= 1 and key <= #value and key % 1 == 0, "Invalid effect array"); count = count + 1 end
        assert(count == #value and count <= 64, "Effect array exceeds bounds")
        for _, entry in ipairs(value) do result[#result + 1] = unwrap(entry) end
    else
        local failure
        value:ForEach(function(_, entry)
            if failure then return end
            local ok, cause = pcall(function() assert(#result < 64, "Effect array exceeds bounds"); result[#result + 1] = unwrap(entry) end)
            if not ok then failure = cause end
        end)
        assert(not failure, tostring(failure))
    end
    return result
end
local function loaded(path)
    local object = StaticFindObject(path)
    assert(object and object:IsValid(), "Loaded object unavailable: " .. path .. "; assets are never loaded by this probe")
    local name = object:GetFullName()
    assert(type(name) == "string" and name:sub(-#path) == path and name:sub(-#path - 1, -#path - 1) == " ", "Loaded object identity differs")
    assert(finite(object:GetAddress()) > 0, "Loaded object address unavailable")
    return object
end

local function inspectEffectSchema(helpers)
    assert(IsInGameThread() == true, "Effect inspection requires the game thread")
    local player = helpers.GetPlayer()
    assert(player and player:IsValid() and player:IsA("/Script/Dawnwalker.DawnwalkerPlayerCharacter"), "Player unavailable")
    local controller, world = player.Controller, player:GetWorld()
    assert(controller and controller:IsValid() and controller.Pawn:GetAddress() == player:GetAddress() and world and world:IsValid(), "Controlled player unavailable")
    assert(controller:GetWorld():GetAddress() == world:GetAddress(), "Controller world mismatch")
    local asc, attributes = player.AbilitySystemComponent, player.CharacterAttributeSet
    assert(asc and asc:IsValid() and asc:IsA("/Script/Dawnwalker.DawnwalkerAbilitySystemComponent"), "Player ASC unavailable")
    assert(attributes and attributes:IsValid() and attributes:IsA("/Script/DogwoodStats.CharacterBaseAttributeSet"), "Character attributes unavailable")
    assert(asc:GetOuter():GetAddress() == player:GetAddress() and attributes:GetOuter():GetAddress() == player:GetAddress(), "Effect player ownership mismatch")
    local effectClass = loaded(EFFECT .. ".GE_SwiftAdvance_AttackSpeed_Lvl1_C")
    local cdo = loaded(EFFECT .. ".Default__GE_SwiftAdvance_AttackSpeed_Lvl1_C")
    assert(effectClass:GetCDO():GetAddress() == cdo:GetAddress() and cdo:GetClass():GetAddress() == effectClass:GetAddress(), "Effect CDO mismatch")
    local library = loaded("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
    assert(library:GetAbilitySystemComponent(player):GetAddress() == asc:GetAddress(), "ASC library disagreement")
    local rows, gaps = {}, {}
    local function observe(name, callback)
        local ok, cause = pcall(callback)
        if not ok then gaps[#gaps + 1] = name .. " unavailable: " .. tostring(cause):sub(1, 180) end
    end
    local function add(name, value) rows[#rows + 1] = name .. "=" .. tostring(value) end
    local function scalable(name, value)
        add(name, finite(value.Value))
        local curve = value.Curve
        add(name .. ".curve", curve.CurveTable and curve.CurveTable:IsValid() and text(curve.CurveTable:GetFullName()) or "none")
        add(name .. ".row", text(curve.RowName)); add(name .. ".registry", text(value.RegistryType.Name))
    end
    local function tags(name, container)
        local values = {}
        for _, tag in ipairs(array(container.GameplayTags)) do values[#values + 1] = text(tag.TagName) end
        add(name, #values == 0 and "none" or table.concat(values, ","))
    end
    local function requirements(name, value)
        tags(name .. ".require", value.RequireTags); tags(name .. ".ignore", value.IgnoreTags)
    end
    for _, field in ipairs({ "DurationPolicy", "StackingType", "StackLimitCount", "StackDurationRefreshPolicy", "StackPeriodResetPolicy", "StackExpirationPolicy", "PeriodicInhibitionPolicy" }) do observe(field, function() add(field, finite(cdo[field])) end) end
    for _, field in ipairs({ "bExecutePeriodicEffectOnApplication", "bDenyOverflowApplication", "bClearStackOnOverflow", "bRequireModifierSuccessToTriggerCues", "bSuppressStackingCues" }) do observe(field, function() assert(type(cdo[field]) == "boolean", field .. " unavailable"); add(field, cdo[field]) end) end
    observe("Period", function() scalable("Period", cdo.Period) end)
    observe("ChanceToApply", function() scalable("ChanceToApply", cdo.ChanceToApplyToTarget) end)
    local function magnitude(name, value)
        add(name .. ".type", finite(value.MagnitudeCalculationType))
        if value.MagnitudeCalculationType == 0 then scalable(name, value.ScalableFloatMagnitude)
        else gaps[#gaps + 1] = name .. " nonconstant magnitude schema" end
    end
    observe("Duration", function() magnitude("Duration", cdo.DurationMagnitude) end)
    for _, field in ipairs({ "Executions", "GrantedAbilities", "GEComponents", "ApplicationRequirements", "ConditionalGameplayEffects", "OverflowEffects", "PrematureExpirationEffectClasses", "RoutineExpirationEffectClasses", "GameplayCues" }) do
        observe(field, function()
            local values = array(cdo[field]); add(field, #values)
            if #values > 0 then gaps[#gaps + 1] = field .. " entries require separate schema inspection" end
        end)
    end
    for _, field in ipairs({ "InheritableGameplayEffectTags", "InheritableOwnedTagsContainer", "InheritableBlockedAbilityTagsContainer", "RemoveGameplayEffectsWithTags" }) do
        for _, part in ipairs({ "CombinedTags", "Added", "Removed" }) do observe(field .. "." .. part, function() tags(field .. "." .. part, cdo[field][part]) end) end
    end
    for _, field in ipairs({ "OngoingTagRequirements", "ApplicationTagRequirements", "RemovalTagRequirements", "GrantedApplicationImmunityTags" }) do observe(field, function() requirements(field, cdo[field]) end) end
    -- Query/delegate wrappers have no proven inspection ABI here. Never treat an
    -- opaque wrapper or a zero-looking token stream as proof of absent behavior.
    gaps[#gaps + 1] = "GrantedApplicationImmunityQuery / RemoveGameplayEffectQuery / custom delegates not validated"
    local modifiers = array(cdo.Modifiers); add("Modifiers", #modifiers)
    assert(#modifiers == 1, "Expected one attack-speed modifier; complete modifier schema unavailable")
    local modifier, descriptor = modifiers[1], modifiers[1].Attribute
    assert(text(descriptor.AttributeName) == ATTRIBUTE, "Attack-speed descriptor name mismatch")
    assert(descriptor.AttributeOwner and descriptor.AttributeOwner:IsValid()
        and descriptor.AttributeOwner:GetFullName() == "Class /Script/DogwoodStats.CharacterBaseAttributeSet", "Attack-speed descriptor owner mismatch")
    assert(finite(descriptor:GetStructAddress()) > 0, "Attack-speed descriptor address unavailable")
    observe("ModifierOp", function() add("ModifierOp", finite(modifier.ModifierOp)) end)
    observe("ModifierMagnitude", function() magnitude("Modifier", modifier.ModifierMagnitude) end)
    observe("Modifier.SourceTags", function() requirements("Modifier.SourceTags", modifier.SourceTags) end)
    observe("Modifier.TargetTags", function() requirements("Modifier.TargetTags", modifier.TargetTags) end)
    observe("EvaluationChannel", function() add("EvaluationChannel", finite(modifier.EvaluationChannelSettings.Channel)) end)
    local debugName = text(library:GetDebugStringFromGameplayAttribute(descriptor))
    assert(debugName:find(ATTRIBUTE, 1, true) and debugName:find("CharacterBaseAttributeSet", 1, true), "Attack descriptor debug string mismatch")
    local data, out = attributes[ATTRIBUTE], {}
    local base, current = finite(data.BaseValue), finite(data.CurrentValue)
    local effective = finite(asc:GetGameplayAttributeValue(descriptor, out))
    assert(out.bFound == true and math.abs(effective - current) <= math.max(.00001, math.abs(current) * .00001), "Attack-speed ASC readback mismatch")
    local count = finite(asc:GetGameplayEffectCount(effectClass, nil, false))
    assert(count >= 0 and count % 1 == 0, "Invalid active attack effect count")
    assert(helpers.GetPlayer():GetAddress() == player:GetAddress() and player.Controller:GetAddress() == controller:GetAddress()
        and controller.Pawn:GetAddress() == player:GetAddress() and player:GetWorld():GetAddress() == world:GetAddress()
        and player.AbilitySystemComponent:GetAddress() == asc:GetAddress() and player.CharacterAttributeSet:GetAddress() == attributes:GetAddress()
        and effectClass:GetCDO():GetAddress() == cdo:GetAddress(), "Effect capture session changed")
    assert(finite(data.BaseValue) == base and finite(data.CurrentValue) == current, "Attack attribute changed during capture")
    local report = table.concat(rows, "; "); assert(#report <= 16000, "Effect report exceeds bounds")
    return { target = text(player:GetFullName()) .. "\n" .. text(cdo:GetFullName()), schema = report,
        attribute = ATTRIBUTE .. ": base=" .. base .. ", current=" .. current .. ", ASC=" .. effective .. ", active source effects=" .. count .. "; descriptor=" .. descriptor:GetStructAddress(),
        status = "Read-only capture; INCOMPLETE safety schema: " .. table.concat(gaps, "; ") .. ". No effect was applied." }
end

local function objectIdentity(object, className, label)
    assert(object and object:IsValid(), label .. " unavailable")
    assert(object:IsA(className), label .. " class mismatch")
    local name, address = object:GetFullName(), object:GetAddress()
    assert(type(name) == "string" and #name > 0 and #name <= 1024, label .. " name invalid")
    assert(not name:find("Default__", 1, true), label .. " is a class default")
    assert(type(address) == "number" and address > 0 and address < math.huge, label .. " address invalid")
    return name .. " @ " .. tostring(address)
end

local function resolve(helpers)
    local player = helpers.GetPlayer()
    local identity = objectIdentity(player, "/Script/Dawnwalker.DawnwalkerPlayerCharacter", "Player")
    local world = objectIdentity(player:GetWorld(), "/Script/Engine.World", "World")
    local controller = player.Controller
    local controllerIdentity = objectIdentity(controller, "/Script/Engine.PlayerController", "Controller")
    assert(controller.Pawn and controller.Pawn:IsValid() and controller.Pawn:GetAddress() == player:GetAddress(), "Controlled pawn mismatch")
    local combat = player.CombatComponent
    local combatIdentity = objectIdentity(combat, "/Script/DogwoodCombat.PlayerCombatComponent", "Combat component")
    assert(combat:IsAlive(), "A living player is required")
    local owner = combat:GetOwner()
    assert(owner and owner:IsValid() and owner:GetAddress() == player:GetAddress(), "Combat owner mismatch")
    local config = combat:GetConfig()
    local configIdentity = objectIdentity(config, "/Script/DogwoodCombat.CombatConfig", "Combat config")
    assert(objectIdentity(combat.Config, "/Script/DogwoodCombat.CombatConfig", "Config property") == configIdentity,
        "Config getter and property disagree")
    return { key = identity .. " | " .. world .. " | " .. controllerIdentity .. " | " .. combatIdentity .. " | " .. configIdentity,
        player = identity, configName = configIdentity, config = config }
end

local function readModes(config)
    local rows = {}
    for enumValue, modeName in ipairs(MODES) do
        assert(config.CombatModes:Contains(enumValue) == true, "Missing combat mode: " .. modeName)
        local mode = config.CombatModes:Find(enumValue)
        -- Containers may return a wrapped UObject. A direct UObject is also valid;
        -- objectIdentity below rejects every unsupported wrapper shape.
        local wrapped, unwrapped = pcall(function() return mode:get() end)
        if wrapped then mode = unwrapped end
        local identity = objectIdentity(mode, "/Script/DogwoodCombat.CombatMode", modeName)
        local fields = {}
        for _, field in ipairs(METRICS) do
            local number = mode.MetricsScalingSettings[field]
            assert(type(number) == "number" and number == number and math.abs(number) < math.huge,
                modeName .. " " .. field .. " is not finite")
            fields[#fields + 1] = field .. "=" .. string.format("%.6g", number)
        end
        rows[enumValue] = modeName .. ": " .. table.concat(fields, ", ") .. "\n" .. identity
    end
    return rows
end

function M.Init(menu, helpers, attackPilot, attackObserver, attributeInspection)
    local attackChecked = false
    local function runAttack(action)
        ExecuteInGameThread(function()
            local ok, result = pcall(action)
            menu.Set(SECTION, "attackEnabled", attackPilot.owned())
            menu.SetLabel(SECTION, "attackStatus", ok and attackPilot.status() or tostring(result))
            assert(ok, result)
        end)
    end
    local function clearEffect(message)
        menu.SetLabel(SECTION, "effectStatus", message)
        for _, id in ipairs({ "effectTarget", "effectSchema", "effectAttribute" }) do menu.SetLabel(SECTION, id, "") end
    end
    local function inspectEffect()
        clearEffect("Reading loaded Swift Advance effect...")
        ExecuteInGameThread(function()
            local ok, result = pcall(inspectEffectSchema, helpers)
            if not ok then clearEffect("Effect inspection unavailable: " .. tostring(result)); error(result, 0) end
            menu.SetLabel(SECTION, "effectTarget", result.target)
            menu.SetLabel(SECTION, "effectSchema", result.schema)
            menu.SetLabel(SECTION, "effectAttribute", result.attribute)
            menu.SetLabel(SECTION, "effectStatus", result.status)
        end)
    end
    local function clear(message)
        menu.SetLabel(SECTION, "status", message)
        menu.SetLabel(SECTION, "target", "No current capture.")
        for index = 1, #MODES do menu.SetLabel(SECTION, "mode" .. index, "") end
    end

    local function inspect()
        clear("Reading loaded attack settings...")
        ExecuteInGameThread(function()
            local ok, result = pcall(function()
                local before = resolve(helpers)
                local rows = readModes(before.config)
                assert(resolve(helpers).key == before.key, "Player, world or combat target changed during capture")
                return { target = before.player .. "\n" .. before.configName, rows = rows }
            end)
            if not ok then
                clear("Inspection unavailable: " .. tostring(result))
                error(result, 0)
            end
            menu.SetLabel(SECTION, "target", result.target)
            for index, row in ipairs(result.rows) do menu.SetLabel(SECTION, "mode" .. index, row) end
            menu.SetLabel(SECTION, "status", "Read-only capture complete. Shared assets and write/restore behavior remain unverified.")
        end)
    end

    local items = {
        { type = "label", id = "status", label = "Inspect loaded attack settings before any attack-speed implementation." },
        { type = "button", id = "inspect", label = "Inspect attack settings", onClick = inspect },
        { type = "label", label = "Inspection only: no attack speed, stamina, NPC or shared asset values are changed." },
        { type = "label", id = "target", label = "No current capture." },
    }
    for index = 1, #MODES do items[#items + 1] = { type = "label", id = "mode" .. index, label = "" } end
    items[#items + 1] = { type = "button", id = "inspectEffect", label = "Inspect Swift Advance effect", onClick = inspectEffect }
    items[#items + 1] = { type = "label", id = "effectStatus", label = "Loaded-only effect discovery has not run." }
    for _, id in ipairs({ "effectTarget", "effectAttribute", "effectSchema" }) do items[#items + 1] = { type = "label", id = id, label = "" } end
    if attackPilot then
        table.insert(items, 1, { type = "label", id = "attackStatus", label = "Normal human fist playback verified at +10%; other attacks unverified. Pause and check apply/removal first." })
        table.insert(items, 2, { type = "button", id = "attackCheck", label = "Check attack speed and restore", onClick = function()
            runAttack(function()
                attackChecked = false
                attackPilot.roundtrip()
                attackChecked = true
            end)
        end })
        table.insert(items, 3, { type = "checkbox", id = "attackEnabled", label = "Attack speed bonus +0.10", default = false,
            onChange = function(value)
                runAttack(function()
                    assert(type(value) == "boolean", "Attack speed requires a boolean")
                    assert(not value or attackChecked, "Pause the game and check attack speed first")
                    attackPilot.set(value)
                end)
            end })
    end
    if attackObserver then
        local function publishObservation(result)
            menu.SetLabel(SECTION, "attackObservationStatus", result.status)
            menu.SetLabel(SECTION, "attackObservationReport", result.report)
        end
        table.insert(items, attackPilot and 4 or 1, { type = "button", id = "attackObserve", label = "Record next attacks", onClick = function()
            ExecuteInGameThread(function() attackObserver.start(publishObservation) end)
        end })
        table.insert(items, attackPilot and 5 or 2, { type = "button", id = "attackObserveStop", label = "Stop attack recording", onClick = function()
            ExecuteInGameThread(function() attackObserver.stop() end)
        end })
        table.insert(items, attackPilot and 6 or 3, { type = "label", id = "attackObservationStatus", label = "Record, resume the game, and perform the same normal attack. Capture ends after 10 seconds or when paused." })
        table.insert(items, attackPilot and 7 or 4, { type = "label", id = "attackObservationReport", label = "" })
    end
    if attributeInspection then
        items[#items + 1] = { type = "button", id = "inspectAttributes", label = "Inspect stamina and focus attributes", onClick = function()
            menu.SetLabel(SECTION, "attributeReport", "")
            menu.SetLabel(SECTION, "attributeStatus", "Reading current player attributes...")
            ExecuteInGameThread(function()
                local ok, result = pcall(attributeInspection.Capture, helpers)
                if not ok then
                    menu.SetLabel(SECTION, "attributeReport", "")
                    menu.SetLabel(SECTION, "attributeStatus", "Attribute inspection unavailable: " .. tostring(result))
                    error(result, 0)
                end
                menu.SetLabel(SECTION, "attributeReport", result.report)
                menu.SetLabel(SECTION, "attributeStatus", result.status)
            end)
        end }
        items[#items + 1] = { type = "label", id = "attributeStatus", label = "Read-only attribute discovery has not run. No stamina or focus values are changed." }
        items[#items + 1] = { type = "label", id = "attributeReport", label = "" }
    end
    menu.Register({ id = SECTION, title = "Attack speed", tab = "Player", items = items })
    function M.ResetSession()
        attackChecked = false
        clear("Player session changed. Inspect again for current attack settings.")
        clearEffect("Player session changed. Inspect again for current effect settings.")
        if attributeInspection then
            menu.SetLabel(SECTION, "attributeReport", "")
            menu.SetLabel(SECTION, "attributeStatus", "Player session changed. Inspect attributes again.")
        end
        local failures = {}
        if attackObserver then
            local ok, failure = pcall(attackObserver.ResetSession)
            menu.SetLabel(SECTION, "attackObservationReport", "")
            menu.SetLabel(SECTION, "attackObservationStatus", ok and "Player session changed. Capture cleared." or tostring(failure))
            if not ok then failures[#failures + 1] = tostring(failure) end
        end
        if attackPilot then
            local ok, failure = pcall(attackPilot.reset)
            menu.Set(SECTION, "attackEnabled", attackPilot.owned())
            menu.SetLabel(SECTION, "attackStatus", ok and "Player session changed. Check attack speed again." or tostring(failure))
            if not ok then failures[#failures + 1] = tostring(failure) end
        end
        assert(#failures == 0, table.concat(failures, "; "))
    end
    return M
end

return M
