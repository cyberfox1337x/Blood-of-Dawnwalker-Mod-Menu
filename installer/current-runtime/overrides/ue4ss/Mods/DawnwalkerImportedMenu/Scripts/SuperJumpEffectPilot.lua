local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("super_jump_owned_effect_pilot")
local M = {}
local PATH = "/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_JumpIncrease"
local SPEC_FUNCTION = "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:MakeSpecHandle"
local IDENTITIES = { "player", "world", "controller", "asc", "attributes", "movement", "effectClass", "abilityLibrary" }
local function finite(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Invalid jump number")
    return value
end
local function close(left, right) return math.abs(left - right) <= math.max(.01, math.abs(right) * .001) end
local function count(array)
    local ok, amount = pcall(function() return array:GetArrayNum() end)
    if not ok then amount = #array end
    assert(type(amount) == "number" and amount >= 0 and amount <= 16 and amount % 1 == 0, "Unsupported jump array")
    return amount
end
local function unwrap(value)
    local ok, raw = pcall(function() return value:get() end)
    return ok and raw or value
end
local function text(value) return type(value) == "string" and value or value:ToString() end
local function plainScalable(scalable, expected)
    assert(close(finite(scalable.Value), expected), "Jump scalable magnitude changed")
    assert(not scalable.Curve.CurveTable or not scalable.Curve.CurveTable:IsValid(), "Jump curve is not constant")
    assert(scalable.Curve.RowName:ToString() == "None" and scalable.RegistryType.Name:ToString() == "None",
        "Jump curve or registry lookup is unsupported")
end
-- Use a transient effect definition with stacking disabled; the shared source
-- stays untouched. Retain controlled-session gating until this new native path
-- has live apply/removal and natural-ability overlap evidence.
function M.New(deps)
    assert(type(deps.borrow) == "function" and type(deps.exclusive) == "function", "Controlled jump pilot dependencies required")
    local owned, ready, hookIds, pending = nil, false, nil, nil
    local function releaseHook()
        pending = nil
        if not hookIds then return end
        local unregister = deps.unregisterHook or UnregisterHook
        assert(type(unregister) == "function", "Private spec hook cleanup unavailable")
        unregister(SPEC_FUNCTION, hookIds[1], hookIds[2])
        hookIds = nil
    end
    local function context()
        assert(IsInGameThread() == true, "Jump effect pilot requires game thread")
        assert(deps.exclusive() == true, "Wolf Boost exclusivity lost; recovery retained")
        local result = deps.borrow()
        assert(result.validated == true, "Jump descriptor validation failed")
        for _, path in ipairs({ "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:MakeSpecHandle",
            "/Script/GameplayAbilities.AbilitySystemComponent:BP_ApplyGameplayEffectSpecToSelf" }) do
            local method = StaticFindObject(path)
            assert(method and method:IsValid(), "Required private jump UFunction unavailable: " .. path)
        end
        local ids = {}
        for _, key in ipairs(IDENTITIES) do
            local object = result[key]
            assert(object and object:IsValid(), "Jump context unavailable: " .. key)
            ids[key] = object:GetAddress()
        end
        assert(result.player:IsInWolfForm() == false, "Wolf form is unsupported during this pilot")
        assert(result.effectClass:GetFullName() == "BlueprintGeneratedClass " .. PATH .. ".GE_WolfBoost_JumpIncrease_C", "Jump effect class differs")
        local cdo = result.effectClass:GetCDO()
        assert(cdo and cdo:IsValid() and cdo:GetClass():GetAddress() == ids.effectClass, "Jump CDO identity differs")
        assert(cdo.DurationPolicy == 1 and cdo.StackingType == 2 and cdo.StackLimitCount == 1, "Jump effect lifecycle changed")
        plainScalable(cdo.Period, 0)
        assert(count(cdo.Executions) == 0 and count(cdo.GrantedAbilities) == 0 and count(cdo.GEComponents) == 0
            and count(cdo.Modifiers) == 1, "Jump effect includes additional behavior")
        local modifier = unwrap(cdo.Modifiers[1])
        assert(modifier.ModifierOp == 4 and modifier.ModifierMagnitude.MagnitudeCalculationType == 0, "Jump operation changed")
        plainScalable(modifier.ModifierMagnitude.ScalableFloatMagnitude, 1.5)
        ids.descriptor = result.descriptor:GetStructAddress()
        assert(finite(ids.descriptor) > 0 and modifier.Attribute:GetStructAddress() == ids.descriptor, "Jump descriptor differs")
        ids.cdo = cdo:GetAddress()
        result.sourceEffect = cdo
        return result, ids
    end
    local function current(record)
        local ctx, ids = context()
        for key, id in pairs(record.ids) do assert(ids[key] == id, "Jump session or source changed; recovery retained") end
        return ctx
    end
    local function read(ctx)
        local attribute, out = ctx.attributes.JumpVelocity, {}
        local base, value = finite(attribute.BaseValue), finite(attribute.CurrentValue)
        local effective = ctx.asc:GetGameplayAttributeValue(ctx.descriptor, out)
        assert(out.bFound == true and close(finite(effective), value), "Jump ASC readback mismatch")
        local velocity = finite(ctx.movement.JumpZVelocity)
        local height, gravity = finite(ctx.movement:GetMaxJumpHeight()), finite(ctx.movement:GetGravityZ())
        assert(base > 0 and base <= 2000 and value > 0 and velocity > 0 and height > 0 and gravity < 0
            and close(height, velocity * velocity / (-2 * gravity)), "Invalid jump movement readback")
        return { base = base, value = value, velocity = velocity, height = height, gravity = gravity }
    end
    -- Each expectation is named so a refusal says which value did not follow the effect.
    local function verifyValues(ctx, baseline, multiplier)
        local values = read(ctx)
        local expected = {
            { "base", values.base, baseline.base }, { "attribute", values.value, baseline.value * multiplier },
            { "JumpZVelocity", values.velocity, baseline.velocity * multiplier },
            { "max jump height", values.height, baseline.height * multiplier * multiplier },
            { "gravity", values.gravity, baseline.gravity },
        }
        for _, check in ipairs(expected) do
            assert(close(check[2], check[3]), string.format("Jump effect movement readback failed: %s is %.3f, expected %.3f",
                check[1], check[2], check[3]))
        end
    end
    local function effectCount(ctx) return ctx.asc:GetGameplayEffectCount(ctx.effectClass, nil, false) end
    local function verifyHandle(ctx, record)
        assert(record.handle and record.handle.Handle == record.handleId and record.handleId >= 0, "Jump handle is unavailable; recovery retained")
        local source = ctx.abilityLibrary:GetGameplayEffectFromActiveEffectHandle(record.handle)
        assert(source and source:IsValid() and source:GetAddress() == record.privateId
            and source:GetClass():GetAddress() == record.ids.effectClass and source.StackingType == 0,
            "Jump active handle source changed; recovery retained")
        assert(ctx.abilityLibrary:GetActiveGameplayEffectStackCount(record.handle) == 1,
            "Jump effect overlap detected; recovery retained")
    end
    -- What restoration must prove is that the jump effect is gone: no effect of its class is
    -- active, the attribute carries no multiplier (CurrentValue == BaseValue) and the movement
    -- component follows the attribute again. Gravity and the movement profile belong to other
    -- systems (Fly, No Clip, the game's own profile switches) and may legitimately differ from
    -- the moment the baseline was read; on 2026-09-18 comparing them trapped a finished
    -- restoration in "recovery pending" while the values were already back to normal.
    local function verifyReleased(ctx)
        local values = read(ctx)
        assert(close(values.base, values.value), "Jump attribute still carries a modifier; recovery retained")
        assert(close(values.velocity, values.value), "Jump movement does not follow the attribute; recovery retained")
        return values
    end
    local function restore()
        releaseHook()
        if not owned then return end
        local record, ctx = owned, current(owned)
        if effectCount(ctx) == 0 or record.removed then
            verifyReleased(ctx); owned = nil; return
        end
        verifyHandle(ctx, record)
        assert(ctx.asc:RemoveActiveGameplayEffect(record.handle, -1) == true, "Jump effect removal refused")
        record.removed = true
        assert(effectCount(ctx) == 0, "Jump effect remains after removal")
        verifyReleased(ctx)
        owned = nil
    end
    local function verify()
        if not owned then return end
        local ctx = current(owned)
        assert(effectCount(ctx) == 1, "Another jump effect is active")
        verifyHandle(ctx, owned); verifyValues(ctx, owned.baseline, 1.5)
    end
    local function enable()
        assert(ready, "Inspect the controlled jump pilot first")
        if owned then verify(); return end
        local ctx, ids = context()
        assert(effectCount(ctx) == 0, "Natural Wolf Boost is already active")
        local baseline = read(ctx)
        assert(close(baseline.base, baseline.value), "Another jump modifier is active")
        -- Right after a flight or a long fall the movement component still carries the
        -- jump velocity the game derived for the other gravity (450 * sqrt(2) was measured
        -- 2026-09-18 straight after Fly OFF); the game re-derives it from the attribute a
        -- few seconds later. Applying on top of the stale value would fail the readback and
        -- roll back anyway, so refuse up front with the reason and the remedy.
        assert(close(baseline.velocity, baseline.value), string.format(
            "Jump movement is still settling (JumpZVelocity %.1f, attribute %.1f); wait a few seconds after landing and try again",
            baseline.velocity, baseline.value))
        -- RF_Transient is 0x40 in pinned UE4SS shared/Types.lua. Native Template
        -- copying preserves the full FGameplayAttribute, including its FieldPath.
        local private = StaticConstructObject(ctx.effectClass, ctx.asc, FName("None"), 0x40, 0, false, false, ctx.sourceEffect)
        assert(private and private:IsValid() and private:GetAddress() ~= ids.cdo
            and private:GetOuter():GetAddress() == ids.asc and private:GetClass():GetAddress() == ids.effectClass,
            "Private jump effect construction failed")
        assert(private.DurationPolicy == 1 and private.StackingType == 2 and private.StackLimitCount == 1
            and count(private.Modifiers) == 1 and count(private.Executions) == 0 and count(private.GrantedAbilities) == 0
            and count(private.GEComponents) == 0, "Private effect template was not preserved")
        local privateModifier = unwrap(private.Modifiers[1])
        assert(privateModifier.Attribute:GetStructAddress() ~= ids.descriptor and privateModifier.ModifierOp == 4
            and privateModifier.ModifierMagnitude.MagnitudeCalculationType == 0, "Private modifier template differs")
        assert(text(privateModifier.Attribute.AttributeName) == text(ctx.descriptor.AttributeName)
            and privateModifier.Attribute.AttributeOwner:GetAddress() == ctx.descriptor.AttributeOwner:GetAddress(),
            "Private jump attribute owner or name differs")
        plainScalable(privateModifier.ModifierMagnitude.ScalableFloatMagnitude, 1.5)
        plainScalable(private.Period, 0)
        private.StackingType = 0
        assert(private.StackingType == 0 and ctx.sourceEffect.StackingType == 2, "Private stacking isolation failed")
        owned = { ids = ids, baseline = baseline, private = private, privateId = private:GetAddress() }
        local record = owned
        local register = deps.registerHook or RegisterHook
        assert(type(register) == "function", "Private spec hook registration unavailable")
        pending = { record = record, consumed = false }
        local function after(rawContext, rawReturn, rawEffect, rawInstigator, rawCauser, rawLevel)
            local request = pending
            if not request or request.record ~= record then return end
            local ok, cause = pcall(function()
                local definition = rawEffect:get()
                if not definition or definition:GetAddress() ~= record.privateId then return end
                assert(not request.consumed, "Duplicate private spec callback")
                request.consumed = true
                assert(IsInGameThread() == true and deps.exclusive() == true, "Private spec callback lost controlled context")
                assert(rawContext:get():GetAddress() == ids.abilityLibrary
                    and rawInstigator:get():GetAddress() == ids.player and rawCauser:get():GetAddress() == ids.player
                    and rawLevel:get() == 1.0, "Private spec callback arguments differ")
                local spec = rawReturn:get()
                assert(type(spec) == "userdata", "Opaque private spec was marshalled to a Lua table; refusing apply")
                assert(finite(spec:GetStructAddress()) > 0, "Private spec wrapper address invalid")
                -- LocalUnrealParam:get() produces the live UScriptStruct. The
                -- apply call copies its complete native value before this hook
                -- returns; never store the borrowed spec outside this callback.
                record.handle = ctx.asc:BP_ApplyGameplayEffectSpecToSelf(spec)
                if record.handle and type(record.handle.Handle) == "number" and record.handle.Handle >= 0
                    and record.handle.Handle % 1 == 0 then record.handleId = record.handle.Handle end
            end)
            if not ok then request.failure = tostring(cause) end
            -- No return value: the original MakeSpecHandle result is unchanged.
        end
        local preId, postId = register(SPEC_FUNCTION, function() end, after)
        hookIds = { preId, postId }
        assert(type(preId) == "number" and type(postId) == "number", "Private spec hook IDs unavailable")
        local request = pending
        local called, callFailure = pcall(function()
            ctx.abilityLibrary:MakeSpecHandle(private, ctx.player, ctx.player, 1.0)
        end)
        local released, releaseFailure = pcall(releaseHook)
        assert(released, "Private spec hook cleanup failed: " .. tostring(releaseFailure))
        assert(called and request.consumed and not request.failure,
            "Private spec callback failed: " .. tostring(request.failure or callFailure or "post hook did not run"))
        local handle = record.handle
        owned.handle = handle
        if handle and type(handle.Handle) == "number" and handle.Handle >= 0 and handle.Handle % 1 == 0 then
            owned.handleId = handle.Handle
        end
        assert(handle and type(handle.Handle) == "number" and handle.Handle >= 0
            and handle.Handle % 1 == 0 and handle.bPassedFiltersAndWasExecuted == true,
            "Jump effect handle rejected: handle=" .. tostring(handle and handle.Handle)
                .. ";passed_filters=" .. tostring(handle and handle.bPassedFiltersAndWasExecuted)
                .. ";effect_count=" .. tostring(effectCount(ctx))
                .. ";private=" .. tostring(owned.privateId) .. ";source=" .. tostring(ids.cdo))
        owned.handleId = handle.Handle
        verify()
    end
    return {
        inspect = function()
            ready = false
            if owned then verify() else
                local ctx = context(); local values = read(ctx)
                assert(effectCount(ctx) == 0 and close(values.base, values.value), "Natural jump modifier is active")
            end
            ready = true
        end,
        set = function(value)
            assert(type(value) == "boolean", "Jump pilot requires boolean")
            local ok, cause = pcall(value and enable or restore)
            if not ok then
                ready = false
                local restored, failure = pcall(restore)
                error(tostring(cause) .. (restored and "; baseline restored" or "; recovery pending: " .. tostring(failure)))
            end
        end,
        verify = verify,
        owned = function() return owned ~= nil or hookIds ~= nil end,
        reset = function() restore(); ready = false end,
    }
end
return M
