local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("carry_capacity_owned_effect_pilot")

-- Zero Weight: an ownable, exactly reversible carry-capacity effect.
--
-- Why this module exists instead of the documented setter route.
-- CARRY-CAPACITY-FEASIBILITY.md prescribes
-- `CombatBlueprintFunctionLibrary.SetAttributeValue(ASC, UPARAM(Ref) FGameplayAttribute&,
-- float)`. That route was driven live on 2026-09-17 and is refused by the UE4SS build
-- pinned to this game: the non-const reference parameter is an out parameter to the
-- runtime, which demands a Lua table of the right shape for it. The reviewed arrangement
-- is therefore unreachable, the reference position cannot be resolved read-only (the only
-- other reflected function carrying this attribute takes it by value, pinned UHT dump
-- GameplayAbilities line 1244), and the attempt to vary the arrangement to work around
-- that crashed the game with an access violation inside
-- `RC::LuaType::call_ufunction_from_lua`. That module and its harness are withdrawn.
--
-- What this module does instead is the route this payload already runs live for attack
-- speed (`AttackSpeedEffectPilot.lua`): build a *private* native GameplayEffect instance
-- owned by the player's own ASC, give it one modifier copied from a loaded effect, and
-- apply it through the game's own GAS instrumentation. Nothing here calls
-- SetAttributeValue, and no descriptor is ever passed across the bridge as an out
-- parameter. The engine contract this relies on is recorded in the feasibility note:
-- the inventory registers an ASC change callback for `CarryWeightCapacityModifier`, so a
-- GAS base-value change re-derives `bWeightExceeded` and broadcasts
-- `OnWeightExceededChanged`, which a raw property write would not do.
--
-- The engine's unlimited-carry sentinel is an effective limit of exactly zero:
-- `GetWeightLimit()` is the raw `WeightLimit` plus this attribute, `HasWeightLimit` is
-- `GetWeightLimit() > 0`, and `TryAddItem` skips its weight rejection when there is no
-- positive limit. The note warns that reaching exactly zero through a modifier needs
-- exact cancellation and can drift, so the delta is computed from the live read, the
-- post-state is required to be *exactly* zero, and any mismatch restores and fails
-- closed rather than publishing ownership.
--
-- The borrowed asset is the Strong Back level 1 gameplay effect. It is a descriptor
-- source only, exactly as the read-only probe uses it: the CDO is never applied,
-- removed, stacked or edited, and that is asserted by comparing its magnitude before and
-- after the private modifier is written.

local M = {}

local SOURCE = "/Game/_Dawnwalker/Player/CharacterDevelopment/Traits/GameplayEffects/GE_Trait_Shared_StrongBack_Level_1"
local SOURCE_CLASS_NAME = "GE_Trait_Shared_StrongBack_Level_1_C"
local SPEC = "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:MakeSpecHandle"
local ATTRIBUTE = "CarryWeightCapacityModifier"
local CHAR_DEV_SET = "/Script/DogwoodStats.CharDevAttributeSet"
local PLAYER_PATH = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local PLAYER_ASC_PATH = "/Script/Dawnwalker.DawnwalkerAbilitySystemComponent"
local INVENTORY_PATH = "/Script/DogwoodInventory.InventoryComponent"
local DEBUG_LIBRARY = "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"

local function valid(object)
    return object ~= nil and object:IsValid()
end
local function address(object)
    assert(valid(object), "Carry-capacity object unavailable")
    return object:GetAddress()
end
local function finite(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Nonfinite carry-capacity value")
    return value
end
local function close(left, right)
    return math.abs(finite(left) - finite(right)) <= math.max(0.00001, math.abs(finite(right)) * 0.00001)
end
local function exact(value, expected)
    return finite(value) == expected
end
local function text(value)
    if type(value) ~= "string" then value = value:ToString() end
    assert(type(value) == "string" and #value <= 1024 and not value:find("[%c]"), "Invalid carry-capacity text")
    return value
end
local function unwrap(value)
    local ok, result = pcall(function() return value:get() end)
    return ok and result or value
end
local function count(array)
    assert(array ~= nil, "Carry-capacity array unavailable")
    local ok, total = pcall(function() return array:GetArrayNum() end)
    if not ok then total = #array end
    assert(type(total) == "number" and total >= 0 and total <= 64 and total % 1 == 0, "Carry-capacity array out of bounds")
    return total
end
local function plain(value, expected)
    assert(close(value.Value, expected), "Carry-capacity scalable value mismatch")
    assert(not valid(value.Curve.CurveTable) and text(value.Curve.RowName) == "None" and text(value.RegistryType.Name) == "None",
        "Carry-capacity magnitude has curve or registry behaviour")
end

local EMPTY_ARRAYS = { "Executions", "GrantedAbilities", "GEComponents", "GameplayCues", "ApplicationRequirements",
    "ConditionalGameplayEffects", "OverflowEffects", "PrematureExpirationEffectClasses", "RoutineExpirationEffectClasses" }

local function emptyTags(container)
    assert(count(container.GameplayTags) == 0, "Effect unexpectedly grants or filters tags")
end

-- The native GameplayEffect template the private instance is constructed from must be
-- behaviourless, or the private instance would carry behaviour nobody reviewed.
local function cleanDefinition(object)
    for _, key in ipairs(EMPTY_ARRAYS) do assert(count(object[key]) == 0, "Native effect behaviour present: " .. key) end
    for _, key in ipairs({ "InheritableGameplayEffectTags", "InheritableOwnedTagsContainer",
        "InheritableBlockedAbilityTagsContainer", "RemoveGameplayEffectsWithTags" }) do
        for _, part in ipairs({ "CombinedTags", "Added", "Removed" }) do emptyTags(object[key][part]) end
    end
    for _, key in ipairs({ "OngoingTagRequirements", "ApplicationTagRequirements", "RemovalTagRequirements",
        "GrantedApplicationImmunityTags" }) do
        emptyTags(object[key].RequireTags); emptyTags(object[key].IgnoreTags)
    end
    plain(object.Period, 0)
    plain(object.ChanceToApplyToTarget, 1)
end

-- A copied modifier may be gated by tags the reviewer never saw. Reflected
-- IsTagQueryEmpty takes the existing const FGameplayTagQuery&, so the native query struct
-- is never replaced with a reconstructed Lua table.
local function modifierRequirements(ctx, modifier)
    local library = ctx.queryLibrary
    assert(valid(library) and library:GetFullName() == "BlueprintGameplayTagLibrary /Script/GameplayTags.Default__BlueprintGameplayTagLibrary",
        "Tag-query library unavailable")
    assert(modifier.EvaluationChannelSettings.Channel == 0, "Carry-capacity modifier evaluation channel is unsupported")
    for _, field in ipairs({ "SourceTags", "TargetTags" }) do
        local tags = assert(modifier[field], "Private modifier tag requirements unavailable")
        emptyTags(tags.RequireTags); emptyTags(tags.IgnoreTags)
        assert(tags.TagQuery ~= nil and library:IsTagQueryEmpty(tags.TagQuery) == true,
            "Carry-capacity modifier has nonempty or unreadable tag query: " .. field)
    end
end

local function defaultBorrow(helpers)
    local player = helpers.GetPlayer()
    assert(valid(player) and player:IsA(PLAYER_PATH), "Controlled player unavailable")
    local ctx = {
        player = player,
        controller = player.Controller,
        world = player:GetWorld(),
        asc = player.AbilitySystemComponent,
        char_dev = player.CharDevAttributeSet,
        inventory = player:GetInventoryComponent(),
    }
    assert(valid(ctx.asc) and ctx.asc:IsA(PLAYER_ASC_PATH), "Wrong player ASC")
    assert(valid(ctx.char_dev) and ctx.char_dev:IsA(CHAR_DEV_SET), "Wrong CharDev attribute set")
    assert(valid(ctx.inventory) and ctx.inventory:IsA(INVENTORY_PATH), "Wrong player inventory")
    ctx.sourceClass = StaticFindObject(SOURCE .. "." .. SOURCE_CLASS_NAME)
    assert(valid(ctx.sourceClass) and ctx.sourceClass:GetFullName() == "BlueprintGeneratedClass " .. SOURCE .. "." .. SOURCE_CLASS_NAME,
        "Loaded Strong Back class unavailable")
    ctx.source = ctx.sourceClass:GetCDO()
    ctx.effectClass = StaticFindObject("/Script/GameplayAbilities.GameplayEffect")
    assert(valid(ctx.effectClass) and ctx.effectClass:GetFullName() == "Class /Script/GameplayAbilities.GameplayEffect",
        "Native effect class unavailable")
    ctx.base = ctx.effectClass:GetCDO()
    -- One library object serves both roles: it is the CDO whose name the descriptor
    -- debug call and the ASC resolver are validated against.
    ctx.library = StaticFindObject(DEBUG_LIBRARY)
    ctx.queryLibrary = StaticFindObject("/Script/GameplayTags.Default__BlueprintGameplayTagLibrary")
    assert(valid(ctx.library) and ctx.library:GetFullName() == "AbilitySystemBlueprintLibrary " .. DEBUG_LIBRARY,
        "Ability library unavailable")
    assert(count(ctx.source.Modifiers) == 1, "Strong Back modifier count changed")
    ctx.descriptor = unwrap(ctx.source.Modifiers[1]).Attribute
    return ctx
end

function M.New(helpers, deps)
    deps = deps or {}
    local record, ready, hookIds, pending = nil, false, nil, nil
    local status = "Not inspected; no owned carry-capacity effect."

    local function session(ctx)
        assert(IsInGameThread() == true, "Carry-capacity pilot requires the game thread")
        for _, key in ipairs({ "player", "controller", "world", "asc", "char_dev", "inventory", "library" }) do
            assert(valid(ctx[key]), "Carry-capacity session object unavailable: " .. key)
        end
        assert(address(helpers.GetPlayer()) == address(ctx.player)
            and address(ctx.controller.Pawn) == address(ctx.player)
            and address(ctx.player.Controller) == address(ctx.controller)
            and address(ctx.player:GetWorld()) == address(ctx.world)
            and address(ctx.controller:GetWorld()) == address(ctx.world)
            and address(ctx.player.AbilitySystemComponent) == address(ctx.asc)
            and address(ctx.player.CharDevAttributeSet) == address(ctx.char_dev)
            and address(ctx.player:GetInventoryComponent()) == address(ctx.inventory),
            "Carry-capacity session changed; recovery retained")
        assert(address(ctx.asc:GetOuter()) == address(ctx.player) and address(ctx.char_dev:GetOuter()) == address(ctx.player),
            "Carry-capacity ownership mismatch")
    end

    -- One read of every value the gate compares: the attribute through both the property
    -- and the game's own reflected getter, the raw and effective limit, the current load
    -- and the derived exceeded flag.
    local function read(ctx)
        session(ctx)
        local data = ctx.char_dev[ATTRIBUTE]
        assert(data ~= nil, "CarryWeightCapacityModifier data is unavailable")
        local base, current = finite(data.BaseValue), finite(data.CurrentValue)
        local out = {}
        local native = finite(ctx.asc:GetGameplayAttributeValue(ctx.descriptor, out))
        assert(out.bFound == true and close(current, native), "Carry-capacity ASC readback mismatch")
        local raw = finite(ctx.inventory.WeightLimit)
        local effective = finite(ctx.inventory:GetWeightLimit())
        local weight = finite(ctx.inventory:GetCurrentWeight())
        local exceeded = ctx.inventory.bWeightExceeded
        assert(type(exceeded) == "boolean", "bWeightExceeded is unavailable")
        -- The engine's own formula, from CARRY-CAPACITY-FEASIBILITY.md: a non-positive raw
        -- limit is returned as-is, otherwise raw plus the attribute.
        local expected = raw <= 0 and raw or (raw + current)
        assert(close(effective, expected), "GetWeightLimit does not match WeightLimit + CarryWeightCapacityModifier")
        -- The engine's rule, stated explicitly. Written as
        -- `effective == 0 and false or weight > effective` Lua reads it as
        -- "(A and false) or B", and the false branch is discarded, so a zero limit would be
        -- asserted to be *exceeded* - the exact opposite of the unlimited case this pilot
        -- is trying to reach. Same defect the read-only probe carried and fixed.
        local expected_exceeded
        if effective == 0 then
            expected_exceeded = false
        else
            expected_exceeded = weight > effective
        end
        assert(exceeded == expected_exceeded, "bWeightExceeded is not synchronized with the limit")
        return { base = base, current = current, raw_limit = raw, effective_limit = effective,
            weight = weight, exceeded = exceeded }
    end

    local function context()
        local ctx = (deps.borrow or function() return defaultBorrow(helpers) end)()
        session(ctx)
        assert(address(ctx.library:GetAbilitySystemComponent(ctx.player)) == address(ctx.asc), "ASC resolver mismatch")
        assert(valid(ctx.source) and address(ctx.source:GetClass()) == address(ctx.sourceClass), "Strong Back CDO class mismatch")
        assert(address(ctx.sourceClass:GetCDO()) == address(ctx.source)
            and address(ctx.base:GetClass()) == address(ctx.effectClass), "Effect source template mismatch")
        local modifier = unwrap(ctx.source.Modifiers[1])
        assert(count(ctx.source.Modifiers) == 1 and modifier.ModifierOp == 0, "Strong Back must be a single additive modifier")
        modifierRequirements(ctx, modifier)
        local descriptor = ctx.descriptor
        -- The borrowed descriptor is a struct property, not a UObject: it is identified by
        -- name, owner class and stable address, the same three fields the read-only probe
        -- validates, rather than by IsValid.
        assert(descriptor ~= nil and text(descriptor.AttributeName) == ATTRIBUTE
            and valid(descriptor.AttributeOwner) and descriptor.AttributeOwner:GetFullName() == "Class " .. CHAR_DEV_SET
            and finite(descriptor:GetStructAddress()) > 0, "Carry-capacity descriptor mismatch")
        assert(modifier.Attribute:GetStructAddress() == descriptor:GetStructAddress(),
            "Borrowed carry-capacity descriptor is not the source modifier")
        local debugName = text(ctx.library:GetDebugStringFromGameplayAttribute(descriptor))
        assert(debugName:find(ATTRIBUTE, 1, true) and debugName:find("CharDevAttributeSet", 1, true),
            "Carry-capacity descriptor debug name mismatch")
        cleanDefinition(ctx.base)
        assert(count(ctx.base.Modifiers) == 0 and ctx.base.DurationPolicy == 0 and ctx.base.StackingType == 0,
            "Native base template changed")
        local values = read(ctx)
        -- The delta is computed from the live effective limit, so a pre-existing additive
        -- contribution (an owned Strong Back level, say) is already accounted for and is
        -- cancelled correctly rather than assumed away. What must be refused is a
        -- divergence between BaseValue and CurrentValue: that means a multiplicative
        -- modifier is aggregating this attribute, and an additive delta would no longer
        -- land on the effective limit it was derived from.
        assert(close(values.base, values.current), "A multiplicative carry-capacity modifier is active")
        for _, path in ipairs({ SPEC, "/Script/GameplayAbilities.AbilitySystemComponent:BP_ApplyGameplayEffectSpecToSelf" }) do
            assert(valid(StaticFindObject(path)), "Carry-capacity native method unavailable")
        end
        return ctx, values
    end

    -- The feasibility note's first Enable precondition, implemented literally: the
    -- read-only probe contract has to pass on this exact player, world, inventory, ASC,
    -- attribute set and descriptor identity before anything may be written.
    local function gate(ctx)
        local probe = deps.probe
        assert(type(probe) == "table" and type(probe.run) == "function", "The read-only carry-capacity probe is unavailable")
        local result = probe.run({
            static_find_object = deps.static_find_object,
            get_player = helpers.GetPlayer,
            property_types = deps.property_types or PropertyTypes,
        })
        assert(type(result) == "table", "The read-only carry-capacity probe returned no verdict")
        assert(result.ok == true, "The read-only carry-capacity probe did not pass: "
            .. tostring(result.stage) .. " " .. tostring(result.message))
        local snapshot = result.snapshot
        assert(type(snapshot) == "table", "The read-only carry-capacity probe returned no snapshot")
        assert(tostring(address(ctx.player)) == snapshot.player_address
            and tostring(address(ctx.world)) == snapshot.world_address
            and tostring(address(ctx.inventory)) == snapshot.inventory_address
            and tostring(address(ctx.asc)) == snapshot.asc_address
            and tostring(address(ctx.char_dev)) == snapshot.char_dev_address,
            "The probe passed on a different session than the one about to be written")
        return snapshot
    end

    local function releaseHook()
        pending = nil
        if not hookIds then return end
        (deps.unregisterHook or UnregisterHook)(SPEC, hookIds[1], hookIds[2])
        hookIds = nil
    end

    local function verifyHandle(r)
        session(r.ctx)
        for key, id in pairs(r.ids) do assert(address(r.ctx[key]) == id, "Recorded carry-capacity identity changed; recovery retained") end
        assert(r.handle and r.handle.Handle == r.handleId and r.handleId >= 0,
            "Exact carry-capacity handle unavailable; recovery retained")
        assert(address(r.ctx.library:GetGameplayEffectFromActiveEffectHandle(r.handle)) == r.privateId,
            "Carry-capacity handle source mismatch")
        assert(r.ctx.library:GetActiveGameplayEffectStackCount(r.handle) == 1,
            "Carry-capacity owned stack mismatch")
    end

    local function restore()
        releaseHook()
        if not record then return end
        local r = record
        session(r.ctx)
        if not r.attempted then record = nil; return end
        if not r.removed then
            verifyHandle(r)
            assert(r.ctx.asc:RemoveActiveGameplayEffect(r.handle, -1) == true,
                "Exact carry-capacity effect removal refused; recovery retained")
            r.removed = true
        end
        local values = read(r.ctx)
        assert(close(values.base, r.baseline.base) and close(values.current, r.baseline.current)
            and exact(values.effective_limit, r.baseline.effective_limit)
            and values.exceeded == r.baseline.exceeded and exact(values.raw_limit, r.baseline.raw_limit)
            and exact(values.weight, r.baseline.weight),
            "Carry-capacity baseline restoration mismatch; recovery retained")
        record = nil
        status = "OFF: exact private effect removed; weight limit and load restored."
    end

    local function verify()
        assert(record, "No owned carry-capacity effect")
        verifyHandle(record)
        local values = read(record.ctx)
        assert(exact(values.effective_limit, 0),
            "The owned effect did not reach the zero effective limit; recovery retained")
        assert(values.exceeded == false, "bWeightExceeded did not clear; recovery retained")
        assert(close(values.base, record.predicted.base) and close(values.current, record.predicted.current),
            "Carry-capacity attribute readback mismatch; recovery retained")
        assert(exact(values.raw_limit, record.baseline.raw_limit), "Raw WeightLimit changed under the owned effect")
        status = string.format(
            "ON: effective weight limit 0 (no limit) verified; raw %.3f, modifier %.3f, load %.3f, over-limit %s.",
            values.raw_limit, values.current, values.weight, tostring(values.exceeded))
        return status
    end

    local function enable()
        assert(ready, "Inspect the carry-weight capability first")
        if record then return verify() end
        -- Full re-validation of every identity, the borrowed descriptor and the native
        -- template, exactly as inspect() runs it, before the probe gate is asked.
        local ctx, values = context()
        gate(ctx)
        assert(values.raw_limit > 0, "The inventory already has no positive weight limit")
        assert(values.effective_limit > 0, "The effective weight limit is already non-positive")
        local delta = -values.effective_limit
        assert(delta < 0 and finite(delta) == delta, "Invalid carry-capacity delta")
        -- An infinite-duration additive modifier lands on the aggregated CurrentValue and
        -- leaves BaseValue alone (only Instant effects rewrite the base); the live attack
        -- pilot expects the same. Predicting a moved base refused a correctly applied effect
        -- on 2026-09-17 ("attribute readback mismatch") and rolled it back.
        local predicted = { base = values.base, current = values.current + delta }

        local construct = deps.construct or StaticConstructObject
        local private = construct(ctx.effectClass, ctx.asc, FName("None"), 0x40, 0, false, false, ctx.base)
        assert(valid(private) and address(private) ~= address(ctx.base) and address(private) ~= address(ctx.source)
            and address(private:GetOuter()) == address(ctx.asc) and address(private:GetClass()) == address(ctx.effectClass),
            "Private carry-capacity effect construction failed")
        cleanDefinition(private)
        assert(count(private.Modifiers) == 0, "Private native template has modifiers")
        -- Pinned native TArray copy, the same call the live attack pilot uses: it preserves
        -- FGameplayAttribute FieldPath and gives the private instance its own descriptor.
        private.Modifiers = ctx.source.Modifiers
        assert(count(private.Modifiers) == 1, "Private carry-capacity modifier copy failed")
        local modifier = unwrap(private.Modifiers[1])
        local original = unwrap(ctx.source.Modifiers[1])
        assert(modifier.Attribute:GetStructAddress() ~= ctx.descriptor:GetStructAddress()
            and text(modifier.Attribute.AttributeName) == ATTRIBUTE
            and address(modifier.Attribute.AttributeOwner) == address(ctx.descriptor.AttributeOwner),
            "Private descriptor alias or mismatch")
        local originalType = original.ModifierMagnitude.MagnitudeCalculationType
        local originalValue = original.ModifierMagnitude.ScalableFloatMagnitude.Value
        assert(modifier.ModifierOp == 0, "Private modifier operation changed")
        modifierRequirements(ctx, modifier)
        modifier.ModifierMagnitude.MagnitudeCalculationType = 0
        modifier.ModifierMagnitude.ScalableFloatMagnitude.Value = delta
        plain(modifier.ModifierMagnitude.ScalableFloatMagnitude, delta)
        private.DurationPolicy = 1
        private.StackingType = 0
        assert(private.DurationPolicy == 1 and private.StackingType == 0
            and original.ModifierMagnitude.MagnitudeCalculationType == originalType
            and original.ModifierMagnitude.ScalableFloatMagnitude.Value == originalValue
            and ctx.base.DurationPolicy == 0, "The borrowed Strong Back source was changed")
        cleanDefinition(private)

        record = { ctx = ctx, private = private, privateId = address(private), baseline = values,
            predicted = predicted, delta = delta, attempted = false }
        record.ids = {}
        for _, key in ipairs({ "player", "controller", "world", "asc", "char_dev", "inventory", "library" }) do
            record.ids[key] = address(ctx[key])
        end
        local r = record
        pending = { consumed = false }
        local request = pending
        local function after(rawContext, rawReturn, rawEffect, rawInstigator, rawCauser, rawLevel)
            if pending ~= request then return end
            local ok, cause = pcall(function()
                if address(rawEffect:get()) ~= r.privateId then return end
                assert(not request.consumed, "Duplicate carry-capacity spec callback")
                request.consumed = true
                session(ctx)
                assert(address(rawContext:get()) == address(ctx.library)
                    and address(rawInstigator:get()) == address(ctx.player)
                    and address(rawCauser:get()) == address(ctx.player) and rawLevel:get() == 1,
                    "Carry-capacity spec arguments differ")
                local spec = rawReturn:get()
                assert(type(spec) == "userdata" and finite(spec:GetStructAddress()) > 0,
                    "Opaque carry-capacity spec must remain native userdata")
                r.attempted = true
                r.handle = ctx.asc:BP_ApplyGameplayEffectSpecToSelf(spec)
                if r.handle and type(r.handle.Handle) == "number" and r.handle.Handle >= 0 and r.handle.Handle % 1 == 0 then
                    r.handleId = r.handle.Handle
                end
                assert(r.handleId and r.handle.bPassedFiltersAndWasExecuted == true,
                    "Carry-capacity apply result uncertain; recovery retained")
            end)
            if not ok then request.failure = tostring(cause) end
        end
        local pre, post = (deps.registerHook or RegisterHook)(SPEC, function() end, after)
        hookIds = { pre, post }
        assert(type(pre) == "number" and type(post) == "number", "Carry-capacity hook registration uncertain")
        local ok, cause = pcall(function() ctx.library:MakeSpecHandle(private, ctx.player, ctx.player, 1) end)
        releaseHook()
        assert(ok and request.consumed and not request.failure,
            "Carry-capacity spec failed: " .. tostring(request.failure or cause or "callback absent"))
        return verify()
    end

    local function set(value)
        assert(type(value) == "boolean", "Carry-capacity pilot requires a boolean")
        local ok, result = pcall(value and enable or restore)
        if not ok then
            ready = false
            local cleaned, cause = pcall(restore)
            status = tostring(result) .. (cleaned and "; baseline restored" or "; recovery pending: " .. tostring(cause))
            error(status, 0)
        end
        return status
    end

    return {
        inspect = function()
            ready = false
            if record then verify() else context() end
            ready = true
            status = "Inspected the player-local carry-capacity descriptor; no effect applied."
            return status
        end,
        set = set,
        verify = verify,
        owned = function() return record ~= nil or hookIds ~= nil end,
        status = function() return status end,
        -- Bounded paused roundtrip for the QA harness: enable, verify, disable, and prove
        -- the baseline came back exactly.
        roundtrip = function()
            assert(not record, "An existing carry-capacity effect requires OFF first")
            local ctx, baseline = context()
            local paused = deps.isPaused or function()
                local library = StaticFindObject("/Script/Engine.Default__GameplayStatics")
                assert(valid(library), "Pause-state library unavailable")
                return library:IsGamePaused(ctx.player)
            end
            assert(paused() == true, "Pause the game before the carry-capacity roundtrip")
            local ok, cause = pcall(function()
                ready = true
                set(true)
                verify()
                local held = read(ctx)
                assert(exact(held.effective_limit, 0) and held.exceeded == false,
                    "The frozen roundtrip did not hold the zero limit")
                set(false)
                local restored = read(ctx)
                status = string.format(
                    "Paused carry-capacity roundtrip: raw %.3f, baseline limit %.3f, held limit %.3f, restored limit %.3f, exceeded %s->%s->%s.",
                    restored.raw_limit, baseline.effective_limit, held.effective_limit,
                    restored.effective_limit, tostring(baseline.exceeded), tostring(held.exceeded), tostring(restored.exceeded))
            end)
            if not ok then
                local cleaned, detail = pcall(restore)
                error(tostring(cause) .. (cleaned and "; restored" or "; recovery pending: " .. tostring(detail)), 0)
            end
            return status
        end,
        reset = function()
            ready = false
            restore()
            return status
        end,
    }
end

return M
