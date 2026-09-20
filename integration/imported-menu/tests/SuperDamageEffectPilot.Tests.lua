local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("super_damage_effect_pilot_tests")
-- usage: lua SuperDamageEffectPilot.Tests.lua <path to Scripts/SuperDamageEffectPilot.lua>
local M = assert(loadfile(assert(arg[1], "pass the pilot module path")))()
IsInGameThread = function() return true end
FName = function(value) return value end

local function object(id, extra)
    local o = { IsValid = function() return true end, GetAddress = function() return id end }
    for key, value in pairs(extra or {}) do o[key] = value end
    return o
end
local function scalable(value) return { Value = value, Curve = { RowName = "None" }, RegistryType = { Name = "None" } } end
local function tagless() return { RequireTags = { GameplayTags = {} }, IgnoreTags = { GameplayTags = {} }, TagQuery = { empty = true } } end
local function clean(effect)
    for _, key in ipairs({ "Executions", "GrantedAbilities", "GEComponents", "GameplayCues", "ApplicationRequirements",
        "ConditionalGameplayEffects", "OverflowEffects", "PrematureExpirationEffectClasses", "RoutineExpirationEffectClasses", "Modifiers" }) do effect[key] = {} end
    for _, key in ipairs({ "InheritableGameplayEffectTags", "InheritableOwnedTagsContainer", "InheritableBlockedAbilityTagsContainer", "RemoveGameplayEffectsWithTags" }) do
        effect[key] = { CombinedTags = { GameplayTags = {} }, Added = { GameplayTags = {} }, Removed = { GameplayTags = {} } }
    end
    for _, key in ipairs({ "OngoingTagRequirements", "ApplicationTagRequirements", "RemovalTagRequirements", "GrantedApplicationImmunityTags" }) do
        effect[key] = { RequireTags = { GameplayTags = {} }, IgnoreTags = { GameplayTags = {} } }
    end
    effect.Period = scalable(0); effect.ChanceToApplyToTarget = scalable(1); effect.DurationPolicy = 0; effect.StackingType = 0
end

-- The fixture models GAS aggregation for infinite additive modifiers: applying moves
-- CurrentValue only, removing moves it back, BaseValue never changes. Each borrowed source
-- ships as a *multiply* set-by-caller modifier, the shape an item modifier is likely to
-- have, so the tests prove the private copy is forced to a plain additive constant.
local function fixture(options)
    options = options or {}
    local targets = options.targets or M.TARGETS
    local ctx = {}
    for index, key in ipairs({ "player", "controller", "world", "asc", "effectClass", "base", "library", "queryLibrary" }) do ctx[key] = object(index) end
    ctx.player.Controller = ctx.controller; ctx.controller.Pawn = ctx.player
    ctx.player.GetWorld = function() return ctx.world end
    ctx.player.AbilitySystemComponent = ctx.asc
    ctx.asc.GetOuter = function() return ctx.player end
    -- One attribute-set object per set the targets name, owned by the player.
    ctx.sets = {}
    for index, target in ipairs(targets) do
        if not ctx.sets[target.set] then
            local set = object(40 + index); set.GetOuter = ctx.asc.GetOuter
            ctx.sets[target.set] = set; ctx.player[target.set] = set
        end
    end
    ctx.base.GetClass = function() return ctx.effectClass end
    clean(ctx.base)
    ctx.queryLibrary.GetFullName = function() return "BlueprintGameplayTagLibrary /Script/GameplayTags.Default__BlueprintGameplayTagLibrary" end
    ctx.queryLibrary.IsTagQueryEmpty = function(_, query) assert(type(query) == "table" and type(query.empty) == "boolean"); return query.empty end
    ctx.library.GetAbilitySystemComponent = function() return ctx.asc end
    ctx.library.GetDebugStringFromGameplayAttribute = function(_, descriptor) return descriptor.AttributeOwner:GetFullName():match("[^.]+$") .. "." .. descriptor.AttributeName end
    local owners = {
        CharacterAttributeSet = object(88, { GetFullName = function() return "Class /Script/DogwoodStats.CharacterBaseAttributeSet" end }),
        CharDevAttributeSet = object(89, { GetFullName = function() return "Class /Script/DogwoodStats.CharDevAttributeSet" end }),
    }

    local data, descriptors, sources = {}, {}, {}
    ctx.sources = {}
    for index, target in ipairs(targets) do
        data[target.attribute] = { BaseValue = 1, CurrentValue = (options.current or {})[target.attribute] or 1 }
        ctx.sets[target.set][target.attribute] = data[target.attribute]
        local descriptor = { GetStructAddress = function() return 100 + index end, AttributeOwner = owners[target.set], AttributeName = target.attribute }
        descriptors[descriptor] = target.attribute
        local class, cdo = object(200 + index), object(300 + index)
        cdo.GetClass = function() return class end; class.GetCDO = function() return cdo end
        cdo.Modifiers = { { Attribute = descriptor, ModifierOp = 1, ModifierMagnitude = { MagnitudeCalculationType = 3, ScalableFloatMagnitude = scalable(1.25) },
            SourceTags = tagless(), TargetTags = tagless(), EvaluationChannelSettings = { Channel = 0 } } }
        sources[target.attribute] = cdo
        ctx.sources[target.attribute] = { class = class, cdo = cdo, descriptor = descriptor, target = target }
    end
    ctx.asc.GetGameplayAttributeValue = function(_, descriptor, out)
        local attribute = assert(descriptors[descriptor], "unknown descriptor"); out.bFound = true; return data[attribute].CurrentValue
    end
    StaticFindObject = function() return object(900) end

    local privates, applied, post = {}, {}, nil
    local applies, removes, registers, unregisters, nextId = 0, 0, 0, 0, 20
    local failApply, failRemove = false, options.removeFails or false
    local function construct()
        nextId = nextId + 1
        local private = object(nextId); clean(private)
        private.GetOuter = function() return ctx.asc end; private.GetClass = function() return ctx.effectClass end
        private.Modifiers = nil
        local copied = {}
        setmetatable(private, {
            __newindex = function(t, key, value)
                if key == "Modifiers" then
                    -- The native TArray copy hands the private instance its own descriptor
                    -- (a new struct address) carrying the same attribute identity.
                    local source = value[1]
                    local twin = { GetStructAddress = function() return source.Attribute:GetStructAddress() + 50 end,
                        AttributeOwner = source.Attribute.AttributeOwner, AttributeName = source.Attribute.AttributeName }
                    copied = { { Attribute = twin, ModifierOp = source.ModifierOp,
                        ModifierMagnitude = { MagnitudeCalculationType = source.ModifierMagnitude.MagnitudeCalculationType,
                            ScalableFloatMagnitude = scalable(source.ModifierMagnitude.ScalableFloatMagnitude.Value) },
                        SourceTags = tagless(), TargetTags = tagless(), EvaluationChannelSettings = { Channel = 0 } } }
                else rawset(t, key, value) end
            end,
            __index = function(_, key) if key == "Modifiers" then return copied end end,
        })
        privates[nextId] = private
        return private
    end
    local function raw(value) return { get = function() return value end } end
    local borrowed, current
    ctx.library.MakeSpecHandle = function(_, definition, player, causer, level)
        assert(post and privates[definition:GetAddress()] == definition and player == ctx.player and causer == player and level == 1)
        local native = assert(io.tmpfile()); local mt = debug.getmetatable(native); local closer = native.close
        debug.setmetatable(native, { __index = { GetStructAddress = function() return 555 end } })
        borrowed, current = native, definition
        post(raw(ctx.library), raw(borrowed), raw(definition), raw(player), raw(causer), raw(level)); borrowed = nil
        debug.setmetatable(native, mt); closer(native)
        return {}
    end
    local function effectOf(private) return private.Modifiers[1] end
    local function move(private, sign)
        local modifier = effectOf(private)
        assert(modifier.ModifierOp == 0, "the fixture only aggregates additive modifiers; the pilot must force the op")
        local attribute = modifier.Attribute.AttributeName
        data[attribute].CurrentValue = data[attribute].CurrentValue + sign * (modifier.ModifierMagnitude.ScalableFloatMagnitude.Value + (options.drift or 0))
    end
    ctx.asc.BP_ApplyGameplayEffectSpecToSelf = function(_, spec)
        assert(spec == borrowed and type(spec) == "userdata"); applies = applies + 1
        if failApply then error("uncertain apply") end
        local private = assert(current, "no spec under construction")
        applied[private] = 1000 + private:GetAddress()
        move(private, 1)
        return { Handle = applied[private], bPassedFiltersAndWasExecuted = true }
    end
    ctx.library.GetGameplayEffectFromActiveEffectHandle = function(_, handle)
        for private, id in pairs(applied) do if id == handle.Handle then return private end end
        error("unknown handle")
    end
    ctx.library.GetActiveGameplayEffectStackCount = function() return 1 end
    ctx.asc.RemoveActiveGameplayEffect = function(_, handle, stacks)
        assert(stacks == -1); removes = removes + 1
        if failRemove then return false end
        for private, id in pairs(applied) do
            if id == handle.Handle then move(private, -1); applied[private] = nil; return true end
        end
        error("unknown handle")
    end

    local pilot = M.New({ GetPlayer = function() return ctx.player end }, {
        borrow = function() return ctx end, construct = construct, targets = options.targets, wording = options.wording,
        registerHook = function(_, _, fn) registers = registers + 1; post = fn; return 1, 2 end,
        unregisterHook = function() unregisters = unregisters + 1; post = nil end,
    })
    return { pilot = pilot, ctx = ctx, data = data, sources = sources,
        counts = function() return applies, removes, registers, unregisters end,
        applyFailure = function() failApply = true end }
end

local n = 0
local function test(name, fn) local ok, err = pcall(fn); assert(ok, name .. ": " .. tostring(err)); n = n + 1; print("PASS " .. name) end
local function near(a, b) return math.abs(a - b) < 0.000001 end
local function fails(fn, needle) local ok, err = pcall(fn); assert(not ok, "expected a refusal"); assert(tostring(err):find(needle, 1, true), tostring(err)) end

test("enable adds (multiplier - 1) to every family on the current value only", function()
    local f = fixture(); f.pilot.inspect()
    f.pilot.set(true, 100)
    for _, target in ipairs(M.TARGETS) do
        assert(f.data[target.attribute].BaseValue == 1 and f.data[target.attribute].CurrentValue == 100, target.attribute)
    end
    assert(f.pilot.owned() and f.pilot.multiplier() == 100)
    assert(f.pilot.status():find("multiplied by 100", 1, true) and f.pilot.status():find("Fists are not boosted", 1, true), f.pilot.status())
    local a, r, h, u = f.counts(); assert(a == 3 and r == 0 and h == 1 and u == 1, "three applies under one paired hook")
end)

test("disable removes the exact handles and restores every baseline", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true, 50)
    f.pilot.set(false)
    for _, target in ipairs(M.TARGETS) do assert(f.data[target.attribute].CurrentValue == 1, target.attribute) end
    assert(not f.pilot.owned())
    local a, r = f.counts(); assert(a == 3 and r == 3)
end)

test("the borrowed item modifiers are never edited", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true, 10)
    for attribute, cdo in pairs(f.sources) do
        local modifier = cdo.Modifiers[1]
        assert(modifier.ModifierOp == 1 and modifier.ModifierMagnitude.MagnitudeCalculationType == 3
            and modifier.ModifierMagnitude.ScalableFloatMagnitude.Value == 1.25, attribute .. " source was changed")
    end
end)

test("changing the multiplier while owned re-applies on a clean baseline", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true, 10)
    f.pilot.set(true, 200)
    for _, target in ipairs(M.TARGETS) do assert(f.data[target.attribute].CurrentValue == 200, target.attribute) end
    f.pilot.set(false)
    for _, target in ipairs(M.TARGETS) do assert(f.data[target.attribute].CurrentValue == 1) end
end)

test("an out-of-range or fractional multiplier is refused before anything is built", function()
    local f = fixture(); f.pilot.inspect()
    fails(function() f.pilot.set(true, 1) end, "from 2 to 1000")
    fails(function() f.pilot.set(true, 1001) end, "from 2 to 1000")
    fails(function() f.pilot.set(true, 2.5) end, "from 2 to 1000")
    local a = f.counts(); assert(a == 0 and not f.pilot.owned())
end)

test("enable without inspect is refused", function()
    local f = fixture()
    fails(function() f.pilot.set(true, 100) end, "Inspect")
end)

test("a pre-existing additive modifier is stacked on, not refused, and comes back exactly", function()
    local f = fixture({ current = { ClawsDamageMultiplier = 1.4 } }); f.pilot.inspect()
    f.pilot.set(true, 100)
    assert(near(f.data.ClawsDamageMultiplier.CurrentValue, 100.4) and f.data.MeleeDamageMultiplier.CurrentValue == 100)
    f.pilot.set(false)
    assert(near(f.data.ClawsDamageMultiplier.CurrentValue, 1.4) and f.data.MeleeDamageMultiplier.CurrentValue == 1)
    assert(not f.pilot.status():find("changed meanwhile", 1, true), f.pilot.status())
end)

test("another buff moving a value while ON is reported on OFF, with the handles still removed", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true, 100)
    f.data.MagicDamageMultiplier.CurrentValue = f.data.MagicDamageMultiplier.CurrentValue + 0.25 -- a perk rank landed meanwhile
    f.pilot.set(false)
    assert(not f.pilot.owned())
    local a, r = f.counts(); assert(a == 3 and r == 3, "every owned handle must still be removed")
    assert(f.pilot.status():find("MagicDamageMultiplier 1.000 -> 1.250", 1, true), f.pilot.status())
end)

test("a moved base value on OFF retains the recovery", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true, 100)
    f.data.MeleeDamageMultiplier.BaseValue = 2
    fails(function() f.pilot.set(false) end, "base value changed")
end)

test("an uncertain apply rolls back whatever was applied and reports it", function()
    local f = fixture(); f.pilot.inspect()
    f.applyFailure()
    fails(function() f.pilot.set(true, 100) end, "baseline restored")
    for _, target in ipairs(M.TARGETS) do assert(f.data[target.attribute].CurrentValue == 1, target.attribute) end
    assert(not f.pilot.owned())
end)

test("a drifted readback refuses ownership and restores", function()
    local f = fixture({ drift = 0.5 }); f.pilot.inspect()
    fails(function() f.pilot.set(true, 100) end, "readback mismatch")
    for _, target in ipairs(M.TARGETS) do assert(f.data[target.attribute].CurrentValue == 1, target.attribute) end
    assert(not f.pilot.owned())
end)

test("a refused removal keeps the recovery and says so", function()
    local f = fixture({ removeFails = true }); f.pilot.inspect(); f.pilot.set(true, 100)
    fails(function() f.pilot.set(false) end, "recovery pending")
    assert(f.pilot.owned(), "ownership must be retained while the effect is still applied")
end)

test("forget drops a stale record without touching the old ability system", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true, 100)
    f.pilot.forget()
    assert(not f.pilot.owned())
    local a, r = f.counts(); assert(a == 3 and r == 0, "forget must not call the remover")
    fails(function() f.pilot.set(true, 100) end, "Inspect")
end)

local PARRY = { { attribute = "ParryWindowMultiplier", source = "GE_ParryWindowMultiplier", family = "parry", set = "CharDevAttributeSet" } }
test("another target list on another attribute set works with its own wording", function()
    local f = fixture({ targets = PARRY, wording = { subject = "parry window", sets = "parry window multiplier", descriptors = "parry window descriptor" } })
    f.pilot.inspect()
    f.pilot.set(true, 3)
    assert(f.data.ParryWindowMultiplier.CurrentValue == 3 and f.data.ParryWindowMultiplier.BaseValue == 1)
    assert(f.pilot.status():find("parry window multiplied by 3", 1, true) and not f.pilot.status():find("Fists", 1, true), f.pilot.status())
    f.pilot.set(false)
    assert(f.data.ParryWindowMultiplier.CurrentValue == 1 and f.pilot.status():find("parry window multiplier restored", 1, true), f.pilot.status())
end)

test("a target on a set the player does not expose is refused", function()
    local f = fixture({ targets = PARRY })
    f.ctx.player.CharDevAttributeSet = object(999, { GetOuter = function() return f.ctx.player end })
    fails(function() f.pilot.inspect() end, "attribute set changed")
end)

test("a session change is refused with the recovery retained", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true, 100)
    local other = object(777); other.Controller = f.ctx.controller
    f.ctx.controller.Pawn = other
    fails(function() f.pilot.verify() end, "session changed")
    assert(f.pilot.owned())
end)

print(string.format("%d/%d super-damage pilot tests passed", n, n))
