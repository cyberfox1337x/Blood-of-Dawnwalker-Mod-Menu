local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("super_damage_owned_effect_pilot")

-- Super Damage / One-Hit Kills: ownable, exactly reversible outgoing-damage multipliers.
--
-- The captured build has no single outgoing-damage attribute, but the player's
-- CharacterBaseAttributeSet carries one multiplier per attack family - MeleeDamageMultiplier
-- (swords), ClawsDamageMultiplier (vampire claws) and MagicDamageMultiplier (spells) - and
-- the game ships one item-modifier GameplayEffect per attribute under
-- /Game/_Dawnwalker/Stats/CustomItemModifiers. Those effects are borrowed as descriptor
-- sources only, exactly as the live attack-speed and Zero Weight pilots borrow theirs: the
-- CDO is never applied, edited or removed, and that is asserted after every copy.
--
-- For each attribute a *private* native GameplayEffect owned by the player's own ASC is
-- constructed, given the copied modifier (its FGameplayAttribute FieldPath survives the
-- pinned native TArray copy), forced to a plain additive ScalableFloat magnitude of
-- (multiplier - 1), and applied through the game's GAS instrumentation. An infinite-duration
-- additive modifier moves the aggregated CurrentValue and leaves BaseValue alone, so the
-- readback predicted here is current + delta, the same rule the Zero Weight pilot learned
-- on 2026-09-17. Disabling removes each exact handle and requires the baseline back.
--
-- UnarmedDamageMultiplier has no shipped descriptor source and is left alone: fists are
-- not boosted, and the status says so.

local M = {}

local SPEC = "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:MakeSpecHandle"
local APPLY = "/Script/GameplayAbilities.AbilitySystemComponent:BP_ApplyGameplayEffectSpecToSelf"
-- Attribute sets the targets may live on: the player property that holds the instance and
-- the reflected class the borrowed descriptor must name as its owner.
local ATTRIBUTE_SETS = {
    CharacterAttributeSet = "/Script/DogwoodStats.CharacterBaseAttributeSet",
    CharDevAttributeSet = "/Script/DogwoodStats.CharDevAttributeSet",
}
local PLAYER_PATH = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local PLAYER_ASC_PATH = "/Script/Dawnwalker.DawnwalkerAbilitySystemComponent"
local SOURCE_ROOT = "/Game/_Dawnwalker/Stats/CustomItemModifiers/"
local MIN_MULTIPLIER, MAX_MULTIPLIER = 2, 1000

-- One entry per boosted attribute. `source` is the borrowed descriptor asset under
-- SOURCE_ROOT, `set` the player property holding the attribute set. `deps.targets` may
-- supply another list built the same way (the parry-window control does), with
-- `deps.wording` naming what the effect does for the status lines.
M.TARGETS = {
    { attribute = "MeleeDamageMultiplier", source = "GE_MeleeDamageMultiplier", family = "melee", set = "CharacterAttributeSet" },
    { attribute = "ClawsDamageMultiplier", source = "GE_ClawsDamageMultiplier", family = "claws", set = "CharacterAttributeSet" },
    { attribute = "MagicDamageMultiplier", source = "GE_MagicDamageMultiplier", family = "magic", set = "CharacterAttributeSet" },
}
M.WORDING = {
    subject = "outgoing damage", sets = "melee, claws and magic multipliers",
    descriptors = "melee, claws and magic damage descriptors", footnote = " Fists are not boosted.",
}

local function valid(object) return object ~= nil and object:IsValid() end
local function address(object) assert(valid(object), "Super-damage object unavailable"); return object:GetAddress() end
local function finite(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Nonfinite super-damage value")
    return value
end
local function close(left, right)
    return math.abs(finite(left) - finite(right)) <= math.max(0.001, math.abs(finite(right)) * 0.0001)
end
local function text(value)
    if type(value) ~= "string" then value = value:ToString() end
    assert(type(value) == "string" and #value <= 1024 and not value:find("[%c]"), "Invalid super-damage text")
    return value
end
local function unwrap(value)
    local ok, result = pcall(function() return value:get() end)
    return ok and result or value
end
local function count(array)
    assert(array ~= nil, "Super-damage array unavailable")
    local ok, total = pcall(function() return array:GetArrayNum() end)
    if not ok then total = #array end
    assert(type(total) == "number" and total >= 0 and total <= 64 and total % 1 == 0, "Super-damage array out of bounds")
    return total
end
local function plain(value, expected)
    assert(close(value.Value, expected), "Super-damage scalable value mismatch")
    assert(not valid(value.Curve.CurveTable) and text(value.Curve.RowName) == "None" and text(value.RegistryType.Name) == "None",
        "Super-damage magnitude has curve or registry behaviour")
end

local EMPTY_ARRAYS = { "Executions", "GrantedAbilities", "GEComponents", "GameplayCues", "ApplicationRequirements",
    "ConditionalGameplayEffects", "OverflowEffects", "PrematureExpirationEffectClasses", "RoutineExpirationEffectClasses" }
local function emptyTags(container) assert(count(container.GameplayTags) == 0, "Effect unexpectedly grants or filters tags") end

-- The native template and every private instance must be behaviourless apart from their
-- modifiers, or the private effect would carry behaviour nobody reviewed.
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

-- The private modifier must not be gated by source or target tags the reviewer never saw.
local function modifierRequirements(ctx, modifier, family)
    local library = ctx.queryLibrary
    assert(valid(library) and library:GetFullName() == "BlueprintGameplayTagLibrary /Script/GameplayTags.Default__BlueprintGameplayTagLibrary",
        "Tag-query library unavailable")
    assert(modifier.EvaluationChannelSettings.Channel == 0, "Super-damage " .. family .. " modifier evaluation channel is unsupported")
    for _, field in ipairs({ "SourceTags", "TargetTags" }) do
        local tags = assert(modifier[field], "Private modifier tag requirements unavailable")
        emptyTags(tags.RequireTags); emptyTags(tags.IgnoreTags)
        assert(tags.TagQuery ~= nil and library:IsTagQueryEmpty(tags.TagQuery) == true,
            "Super-damage " .. family .. " modifier has nonempty or unreadable tag query: " .. field)
    end
end

local function defaultBorrow(helpers, targets)
    local player = helpers.GetPlayer()
    assert(valid(player) and player:IsA(PLAYER_PATH), "Controlled player unavailable")
    assert(valid(player.CombatComponent) and player.CombatComponent:IsAlive(), "A living player is required for this effect")
    local ctx = { player = player, controller = player.Controller, world = player:GetWorld(),
        asc = player.AbilitySystemComponent, sets = {} }
    assert(valid(ctx.asc) and ctx.asc:IsA(PLAYER_ASC_PATH), "Wrong player ASC")
    for _, target in ipairs(targets) do
        local class = assert(ATTRIBUTE_SETS[target.set], "Unknown attribute set: " .. tostring(target.set))
        local set = player[target.set]
        assert(valid(set) and set:IsA(class), "Wrong player attribute set: " .. target.set)
        ctx.sets[target.set] = set
    end
    ctx.effectClass = StaticFindObject("/Script/GameplayAbilities.GameplayEffect")
    assert(valid(ctx.effectClass) and ctx.effectClass:GetFullName() == "Class /Script/GameplayAbilities.GameplayEffect",
        "Native effect class unavailable")
    ctx.base = ctx.effectClass:GetCDO()
    ctx.library = StaticFindObject("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
    ctx.queryLibrary = StaticFindObject("/Script/GameplayTags.Default__BlueprintGameplayTagLibrary")
    assert(valid(ctx.library) and ctx.library:GetFullName() == "AbilitySystemBlueprintLibrary /Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary",
        "Ability library unavailable")
    ctx.sources = {}
    for _, target in ipairs(targets) do
        local path = SOURCE_ROOT .. target.source .. "." .. target.source .. "_C"
        local class = StaticFindObject(path)
        if not valid(class) then pcall(LoadAsset, SOURCE_ROOT .. target.source); class = StaticFindObject(path) end
        assert(valid(class) and class:GetFullName() == "BlueprintGeneratedClass " .. path,
            "Borrowed " .. target.family .. " damage effect is not loaded: " .. target.source)
        local cdo = class:GetCDO()
        assert(valid(cdo) and count(cdo.Modifiers) == 1, target.source .. " must carry exactly one modifier")
        ctx.sources[target.attribute] = { class = class, cdo = cdo, descriptor = unwrap(cdo.Modifiers[1]).Attribute, target = target }
    end
    return ctx
end

function M.New(helpers, deps)
    deps = deps or {}
    local targets = deps.targets or M.TARGETS
    local wording = deps.wording or M.WORDING
    local idle = "Not inspected; no owned " .. wording.subject .. " effects."
    local record, ready, hookIds, pending = nil, false, nil, nil
    local status = idle

    local function session(ctx)
        assert(IsInGameThread() == true, "Super-damage pilot requires the game thread")
        for _, key in ipairs({ "player", "controller", "world", "asc", "library" }) do
            assert(valid(ctx[key]), "Super-damage session object unavailable: " .. key)
        end
        assert(address(helpers.GetPlayer()) == address(ctx.player)
            and address(ctx.controller.Pawn) == address(ctx.player)
            and address(ctx.player.Controller) == address(ctx.controller)
            and address(ctx.player:GetWorld()) == address(ctx.world)
            and address(ctx.player.AbilitySystemComponent) == address(ctx.asc),
            "Super-damage session changed; recovery retained")
        assert(address(ctx.asc:GetOuter()) == address(ctx.player), "Super-damage ownership mismatch")
        for name, set in pairs(ctx.sets) do
            assert(valid(set) and address(ctx.player[name]) == address(set) and address(set:GetOuter()) == address(ctx.player),
                "Super-damage attribute set changed: " .. name)
        end
    end

    -- Every boosted attribute through the property and the game's own reflected getter.
    local function read(ctx)
        session(ctx)
        local values = {}
        for attribute, source in pairs(ctx.sources) do
            local data = ctx.sets[source.target.set][attribute]
            assert(data ~= nil, attribute .. " data is unavailable")
            local base, current = finite(data.BaseValue), finite(data.CurrentValue)
            local out = {}
            local native = finite(ctx.asc:GetGameplayAttributeValue(source.descriptor, out))
            assert(out.bFound == true and close(current, native), attribute .. " ASC readback mismatch")
            values[attribute] = { base = base, current = current }
        end
        return values
    end

    local function context()
        local ctx = (deps.borrow or function() return defaultBorrow(helpers, targets) end)()
        session(ctx)
        assert(address(ctx.library:GetAbilitySystemComponent(ctx.player)) == address(ctx.asc), "ASC resolver mismatch")
        assert(address(ctx.base:GetClass()) == address(ctx.effectClass), "Effect template mismatch")
        cleanDefinition(ctx.base)
        assert(count(ctx.base.Modifiers) == 0 and ctx.base.DurationPolicy == 0 and ctx.base.StackingType == 0,
            "Native base template changed")
        for _, target in ipairs(targets) do
            local source = assert(ctx.sources[target.attribute], "Borrowed source missing: " .. target.attribute)
            assert(valid(source.cdo) and address(source.cdo:GetClass()) == address(source.class)
                and address(source.class:GetCDO()) == address(source.cdo), target.source .. " CDO class mismatch")
            local modifier = unwrap(source.cdo.Modifiers[1])
            local descriptor = source.descriptor
            assert(modifier.Attribute:GetStructAddress() == descriptor:GetStructAddress(),
                "Borrowed " .. target.family .. " descriptor is not the source modifier")
            assert(descriptor ~= nil and text(descriptor.AttributeName) == target.attribute
                and valid(descriptor.AttributeOwner) and descriptor.AttributeOwner:GetFullName() == "Class " .. ATTRIBUTE_SETS[target.set]
                and finite(descriptor:GetStructAddress()) > 0, target.family .. " descriptor mismatch")
            local debugName = text(ctx.library:GetDebugStringFromGameplayAttribute(descriptor))
            assert(debugName:find(target.attribute, 1, true) and debugName:find(ATTRIBUTE_SETS[target.set]:match("[^.]+$"), 1, true),
                target.family .. " descriptor debug name mismatch")
        end
        local values = read(ctx)
        -- Other modifiers may already aggregate these attributes (perks grant magic damage,
        -- for one). An additive delta still lands on CurrentValue as current + delta unless a
        -- multiply modifier is active, and that case is caught by the readback after the
        -- apply, which restores rather than publishing ownership.
        for _, path in ipairs({ SPEC, APPLY }) do assert(valid(StaticFindObject(path)), "Super-damage native method unavailable") end
        return ctx, values
    end

    local function releaseHook()
        pending = nil
        if not hookIds then return end
        (deps.unregisterHook or UnregisterHook)(SPEC, hookIds[1], hookIds[2])
        hookIds = nil
    end

    local function verifyHandle(r, effect)
        assert(effect.handle and effect.handle.Handle == effect.handleId and effect.handleId >= 0,
            "Exact " .. effect.family .. " handle unavailable; recovery retained")
        assert(address(r.ctx.library:GetGameplayEffectFromActiveEffectHandle(effect.handle)) == effect.privateId,
            effect.family .. " handle source mismatch")
        assert(r.ctx.library:GetActiveGameplayEffectStackCount(effect.handle) == 1, effect.family .. " owned stack mismatch")
    end

    local function verifyRecord(r)
        session(r.ctx)
        for key, id in pairs(r.ids) do assert(address(r.ctx[key]) == id, "Recorded super-damage identity changed; recovery retained") end
    end

    local function restore()
        releaseHook()
        if not record then return end
        local r = record
        session(r.ctx)
        -- Only an effect that came back with an exact handle can be removed by handle. An
        -- apply that raised before returning one left nothing identifiable behind; whether it
        -- left anything at all is decided by the baseline comparison below, not assumed.
        for _, effect in ipairs(r.effects) do
            if effect.handleId and not effect.removed then
                verifyHandle(r, effect)
                assert(r.ctx.asc:RemoveActiveGameplayEffect(effect.handle, -1) == true,
                    "Exact " .. effect.family .. " effect removal refused; recovery retained")
                effect.removed = true
            end
        end
        local values = read(r.ctx)
        -- BaseValue never moves under a duration effect, so it must be back exactly. The
        -- aggregated CurrentValue may legitimately differ if some other buff (a draught, a
        -- perk rank) came or went while the effect was ON; with every owned handle removed
        -- that is reported, not treated as a failed recovery.
        local drifted = {}
        for attribute, baseline in pairs(r.baseline) do
            assert(close(values[attribute].base, baseline.base), attribute .. " base value changed; recovery retained")
            if not close(values[attribute].current, baseline.current) then
                drifted[#drifted + 1] = string.format("%s %.3f -> %.3f", attribute, baseline.current, values[attribute].current)
            end
        end
        table.sort(drifted)
        record = nil
        status = "OFF: private effects removed; " .. wording.sets .. " restored."
        if #drifted > 0 then
            status = status .. " Other modifiers changed meanwhile: " .. table.concat(drifted, ", ") .. "."
        end
    end

    -- Right after the apply the readback must match the prediction exactly; later checks
    -- (a repeated ON, a re-inspect) only prove the exact handles are still owned, because
    -- unrelated buffs may legitimately have moved the aggregated values since.
    local function verify(strict)
        assert(record, "No owned super-damage effects")
        verifyRecord(record)
        local values = read(record.ctx)
        local parts = {}
        for _, effect in ipairs(record.effects) do
            verifyHandle(record, effect)
            local value = values[effect.attribute]
            if strict then
                assert(close(value.base, effect.predicted.base) and close(value.current, effect.predicted.current),
                    effect.attribute .. " readback mismatch; recovery retained")
            end
            parts[#parts + 1] = string.format("%s x%.2f", effect.family, value.current)
        end
        status = string.format("ON: %s multiplied by %d verified (%s).%s",
            wording.subject, record.multiplier, table.concat(parts, ", "), wording.footnote or "")
        return status
    end

    -- Build one private effect for one attribute. Nothing is applied here.
    local function build(ctx, source, delta)
        local target = source.target
        local construct = deps.construct or StaticConstructObject
        local private = construct(ctx.effectClass, ctx.asc, FName("None"), 0x40, 0, false, false, ctx.base)
        assert(valid(private) and address(private) ~= address(ctx.base) and address(private) ~= address(source.cdo)
            and address(private:GetOuter()) == address(ctx.asc) and address(private:GetClass()) == address(ctx.effectClass),
            "Private " .. target.family .. " effect construction failed")
        cleanDefinition(private)
        assert(count(private.Modifiers) == 0, "Private native template has modifiers")
        private.Modifiers = source.cdo.Modifiers
        assert(count(private.Modifiers) == 1, "Private " .. target.family .. " modifier copy failed")
        local modifier, original = unwrap(private.Modifiers[1]), unwrap(source.cdo.Modifiers[1])
        assert(modifier.Attribute:GetStructAddress() ~= source.descriptor:GetStructAddress()
            and text(modifier.Attribute.AttributeName) == target.attribute
            and address(modifier.Attribute.AttributeOwner) == address(source.descriptor.AttributeOwner),
            "Private " .. target.family .. " descriptor alias or mismatch")
        local originalOp = original.ModifierOp
        local originalType = original.ModifierMagnitude.MagnitudeCalculationType
        local originalValue = original.ModifierMagnitude.ScalableFloatMagnitude.Value
        -- The item modifier may ship as a multiply or set-by-caller modifier; the private
        -- copy is forced to a plain additive constant so the readback is predictable.
        modifier.ModifierOp = 0
        modifier.ModifierMagnitude.MagnitudeCalculationType = 0
        modifier.ModifierMagnitude.ScalableFloatMagnitude.Value = delta
        assert(modifier.ModifierOp == 0, "Private " .. target.family .. " modifier operation refused")
        plain(modifier.ModifierMagnitude.ScalableFloatMagnitude, delta)
        modifierRequirements(ctx, modifier, target.family)
        private.DurationPolicy = 1
        private.StackingType = 0
        assert(private.DurationPolicy == 1 and private.StackingType == 0
            and original.ModifierOp == originalOp
            and original.ModifierMagnitude.MagnitudeCalculationType == originalType
            and original.ModifierMagnitude.ScalableFloatMagnitude.Value == originalValue
            and ctx.base.DurationPolicy == 0, "The borrowed " .. target.source .. " was changed")
        cleanDefinition(private)
        return { attribute = target.attribute, family = target.family, private = private, privateId = address(private), attempted = false }
    end

    local function enable(multiplier)
        assert(ready, "Inspect the super-damage capability first")
        if record then
            if record.multiplier == multiplier then return verify() end
            -- A different multiplier is a fresh apply on a clean baseline.
            restore()
        end
        local ctx, baseline = context()
        local delta = multiplier - 1
        record = { ctx = ctx, baseline = baseline, multiplier = multiplier, effects = {}, ids = {} }
        for _, key in ipairs({ "player", "controller", "world", "asc", "library" }) do record.ids[key] = address(ctx[key]) end
        local r = record
        for _, target in ipairs(targets) do
            local effect = build(ctx, ctx.sources[target.attribute], delta)
            local value = baseline[target.attribute]
            effect.predicted = { base = value.base, current = value.current + delta }
            r.effects[#r.effects + 1] = effect
        end
        -- One short-lived MakeSpecHandle hook serves all three applies; each callback claims
        -- the spec whose effect is one of ours and applies it to the player's own ASC.
        pending = { consumed = 0, failure = nil }
        local request = pending
        local byId = {}
        for _, effect in ipairs(r.effects) do byId[effect.privateId] = effect end
        local function after(rawContext, rawReturn, rawEffect, rawInstigator, rawCauser, rawLevel)
            if pending ~= request then return end
            local ok, cause = pcall(function()
                local effect = byId[address(rawEffect:get())]
                if not effect then return end
                assert(not effect.attempted, "Duplicate " .. effect.family .. " spec callback")
                session(ctx)
                assert(address(rawContext:get()) == address(ctx.library) and address(rawInstigator:get()) == address(ctx.player)
                    and address(rawCauser:get()) == address(ctx.player) and rawLevel:get() == 1, "Super-damage spec arguments differ")
                local spec = rawReturn:get()
                assert(type(spec) == "userdata" and finite(spec:GetStructAddress()) > 0, "Opaque spec must remain native userdata")
                request.consumed = request.consumed + 1
                effect.handle = ctx.asc:BP_ApplyGameplayEffectSpecToSelf(spec)
                effect.attempted = true
                if effect.handle and type(effect.handle.Handle) == "number" and effect.handle.Handle >= 0 and effect.handle.Handle % 1 == 0 then
                    effect.handleId = effect.handle.Handle
                end
                assert(effect.handleId and effect.handle.bPassedFiltersAndWasExecuted == true,
                    effect.family .. " apply result uncertain; recovery retained")
            end)
            if not ok then request.failure = tostring(cause) end
        end
        local pre, post = (deps.registerHook or RegisterHook)(SPEC, function() end, after)
        hookIds = { pre, post }
        assert(type(pre) == "number" and type(post) == "number", "Super-damage hook registration uncertain")
        local ok, cause = pcall(function()
            for _, effect in ipairs(r.effects) do
                ctx.library:MakeSpecHandle(effect.private, ctx.player, ctx.player, 1)
                assert(not request.failure, request.failure)
            end
        end)
        releaseHook()
        assert(ok and request.consumed == #r.effects and not request.failure,
            "Super-damage spec failed: " .. tostring(request.failure or cause or "callback absent"))
        return verify(true)
    end

    local function set(value, multiplier)
        assert(type(value) == "boolean", "Super-damage pilot requires a boolean")
        if value then
            assert(type(multiplier) == "number" and multiplier % 1 == 0 and multiplier >= MIN_MULTIPLIER and multiplier <= MAX_MULTIPLIER,
                string.format("Super-damage multiplier must be a whole number from %d to %d", MIN_MULTIPLIER, MAX_MULTIPLIER))
        end
        local ok, result = pcall(function() if value then return enable(multiplier) end return restore() end)
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
            status = "Inspected the player's " .. wording.descriptors .. "; no effect applied."
            return status
        end,
        set = set,
        verify = verify,
        owned = function() return record ~= nil or hookIds ~= nil end,
        status = function() return status end,
        multiplier = function() return record and record.multiplier or nil end,
        reset = function() ready = false; restore(); return status end,
        -- A new session (save load, death, pawn swap) took the old ASC and its effects with
        -- it: nothing is left to remove, so the stale record is dropped rather than restored.
        forget = function()
            releaseHook()
            record = nil
            ready = false
            status = idle
        end,
    }
end

return M
