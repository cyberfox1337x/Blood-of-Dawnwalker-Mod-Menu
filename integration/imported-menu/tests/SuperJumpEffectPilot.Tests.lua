local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("super_jump_effect_pilot_tests")
local M = assert(loadfile(assert(arg[1])))()
IsInGameThread = function() return true end
FName = function(value) return value end
local function object(id)
    return { IsValid = function() return true end, GetAddress = function() return id end }
end
local function name() return { ToString = function() return "None" end } end
local function scalable(value) return { Value = value, Curve = { RowName = name() }, RegistryType = { Name = name() } } end
local function fixture()
    local ctx = { validated = true }
    for index, key in ipairs({ "player", "world", "controller", "asc", "attributes", "movement", "effectClass", "abilityLibrary" }) do ctx[key] = object(index) end
    ctx.player.IsInWolfForm = function() return false end
    ctx.descriptor = { GetStructAddress = function() return 100 end, AttributeName = "JumpVelocity", AttributeOwner = object(77) }
    local cdo = object(10)
    cdo.GetClass = function() return ctx.effectClass end
    cdo.DurationPolicy, cdo.StackingType, cdo.StackLimitCount = 1, 2, 1
    cdo.Period, cdo.Executions, cdo.GrantedAbilities, cdo.GEComponents = scalable(0), {}, {}, {}
    cdo.Modifiers = {{ Attribute = ctx.descriptor, ModifierOp = 4,
        ModifierMagnitude = { MagnitudeCalculationType = 0, ScalableFloatMagnitude = scalable(1.5) } }}
    ctx.effectClass.GetCDO = function() return cdo end
    ctx.effectClass.GetFullName = function() return "BlueprintGeneratedClass /Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_JumpIncrease.GE_WolfBoost_JumpIncrease_C" end
    ctx.attributes.JumpVelocity = { BaseValue = 450, CurrentValue = 450 }
    ctx.movement.JumpZVelocity = 450
    ctx.movement.GetGravityZ = function() return -1960 end
    -- The engine's own formula, so a gravity change in a test keeps the readback consistent.
    ctx.movement.GetMaxJumpHeight = function() return ctx.movement.JumpZVelocity ^ 2 / (-2 * ctx.movement.GetGravityZ()) end
    ctx.asc.GetGameplayAttributeValue = function(_, _, out) out.bFound = true; return ctx.attributes.JumpVelocity.CurrentValue end
    local active, applied, removed, exclusive, failApply, failRemove, wrongVelocity = 0, 0, 0, true, false, false, false
    ctx.asc.GetGameplayEffectCount = function() return active end
    StaticFindObject = function() return object(90) end
    local private
    StaticConstructObject = function(class, outer, _, flags, _, _, _, template)
        assert(class == ctx.effectClass and outer == ctx.asc and flags == 0x40 and template == cdo)
        private = object(20)
        for key, value in pairs(cdo) do if key ~= "GetAddress" then private[key] = value end end
        private.GetOuter = function() return ctx.asc end
        private.Modifiers = {{ Attribute = { GetStructAddress = function() return 101 end,
            AttributeName = "JumpVelocity", AttributeOwner = ctx.descriptor.AttributeOwner }, ModifierOp = 4,
            ModifierMagnitude = cdo.Modifiers[1].ModifierMagnitude }}
        return private
    end
    local postHook, hookRegistrations, hookRemovals, tableSpec, borrowedSpec = nil, 0, 0, false, nil
    local function raw(value) return { get = function() return value end } end
    ctx.abilityLibrary.MakeSpecHandle = function(_, definition, instigator, causer, level)
        assert(definition == private and instigator == ctx.player and causer == ctx.player and level == 1)
        assert(private.StackingType == 0 and cdo.StackingType == 2)
        assert(postHook, "Scoped post hook must be installed before making spec")
        local native = assert(io.tmpfile())
        local nativeClose = native.close
        local nativeMetatable = debug.getmetatable(native)
        debug.setmetatable(native, { __index = { GetStructAddress = function() return 1234 end } })
        borrowedSpec = tableSpec and {} or native
        postHook(raw(ctx.abilityLibrary), raw(borrowedSpec), raw(definition), raw(instigator), raw(causer), raw(level))
        borrowedSpec = nil
        debug.setmetatable(native, nativeMetatable)
        nativeClose(native)
        return {} -- Ordinary return marshalling loses the opaque native fields.
    end
    ctx.asc.BP_ApplyGameplayEffectSpecToSelf = function(_, spec)
        assert(spec == borrowedSpec and type(spec) == "userdata", "Apply must happen inside the post hook")
        applied = applied + 1
        if failApply then error("injected apply error") end
        active = 1; ctx.attributes.JumpVelocity.CurrentValue = 675
        if not wrongVelocity then ctx.movement.JumpZVelocity = 675 end
        return { Handle = 123, bPassedFiltersAndWasExecuted = true }
    end
    ctx.abilityLibrary.GetGameplayEffectFromActiveEffectHandle = function() return private end
    ctx.abilityLibrary.GetActiveGameplayEffectStackCount = function() return active end
    ctx.asc.RemoveActiveGameplayEffect = function(_, handle, stacks)
        assert(handle.Handle == 123 and stacks == -1); removed = removed + 1
        if failRemove then return false end
        active = 0; ctx.attributes.JumpVelocity.CurrentValue = 450; ctx.movement.JumpZVelocity = 450; return true
    end
    local pilot = M.New({ borrow = function() return ctx end, exclusive = function() return exclusive end,
        registerHook = function(_, _, callback) assert(not postHook); postHook = callback; hookRegistrations = hookRegistrations + 1; return 11, 12 end,
        unregisterHook = function(_, pre, post) assert(pre == 11 and post == 12); postHook = nil; hookRemovals = hookRemovals + 1 end })
    return { pilot = pilot, ctx = ctx, cdo = cdo, counts = function() return applied, removed end,
        existing = function() active = 1 end, exclusivity = function(value) exclusive = value end,
        failApply = function() failApply = true end, failRemove = function(value) failRemove = value end,
        wrongVelocity = function() wrongVelocity = true end,
        tableSpec = function() tableSpec = true end,
        hooks = function() return hookRegistrations, hookRemovals, postHook end }
end
local count = 0
local function test(label, callback) callback(); count = count + 1; print("PASS " .. label) end
test("three owned effect cycles restore GAS and movement", function()
    local f = fixture(); f.pilot.inspect()
    for index = 1, 3 do
        f.pilot.set(true); f.pilot.verify(); assert(f.ctx.attributes.JumpVelocity.BaseValue == 450)
        assert(f.ctx.movement.JumpZVelocity == 675); f.pilot.set(false); assert(not f.pilot.owned())
    end
    local applied, removed = f.counts(); assert(applied == 3 and removed == 3)
end)
test("existing Wolf Boost prevents apply", function()
    local f = fixture(); f.existing(); assert(not pcall(f.pilot.inspect)); assert(f.counts() == 0)
end)
test("missing exclusive session prevents apply", function()
    local f = fixture(); f.exclusivity(false); assert(not pcall(f.pilot.inspect)); assert(f.counts() == 0)
end)
test("lost controlled-session permission retains ownership", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true); f.exclusivity(false)
    assert(not pcall(f.pilot.set, false)); local _, removed = f.counts(); assert(removed == 0 and f.pilot.owned())
    f.exclusivity(true); f.pilot.set(false); assert(not f.pilot.owned())
end)
test("unavailable required UFunction rejects before construction", function()
    local f = fixture(); StaticFindObject = function() return nil end
    assert(not pcall(f.pilot.inspect)); assert(f.counts() == 0)
end)
test("template alias is rejected before changing shared stacking", function()
    local f = fixture(); f.pilot.inspect(); StaticConstructObject = function() return f.cdo end
    assert(not pcall(f.pilot.set, true)); assert(f.cdo.StackingType == 2 and f.counts() == 0)
end)
test("active handle must reference exact private definition", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true)
    f.ctx.abilityLibrary.GetGameplayEffectFromActiveEffectHandle = function() return f.cdo end
    assert(not pcall(f.pilot.set, false)); local _, removed = f.counts(); assert(removed == 0 and f.pilot.owned())
end)
test("apply failure before mutation clears false ownership", function()
    local f = fixture(); f.pilot.inspect(); f.failApply(); assert(not pcall(f.pilot.set, true)); assert(not f.pilot.owned())
end)
test("uncertain apply with no returned handle retains recovery", function()
    local f = fixture(); f.pilot.inspect()
    local original = f.ctx.asc.BP_ApplyGameplayEffectSpecToSelf
    f.ctx.asc.BP_ApplyGameplayEffectSpecToSelf = function(...)
        original(...); error("injected post-apply transport error")
    end
    assert(not pcall(f.pilot.set, true)); local _, removed = f.counts()
    assert(f.pilot.owned() and removed == 0)
end)
test("movement callback mismatch triggers removal and baseline verification", function()
    local f = fixture(); f.pilot.inspect(); f.wrongVelocity(); assert(not pcall(f.pilot.set, true))
    local _, removed = f.counts(); assert(removed == 1 and not f.pilot.owned())
end)
test("gravity changed by another system while ON does not trap the restoration", function()
    -- Fly / No Clip / a profile switch may change gravity between ON and OFF. Once the
    -- effect is removed and the attribute and movement are back in step, OFF must release.
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true)
    f.ctx.movement.GetGravityZ = function() return -980 end
    f.pilot.set(false)
    local _, removed = f.counts(); assert(removed == 1 and not f.pilot.owned())
    assert(f.ctx.attributes.JumpVelocity.CurrentValue == 450 and f.ctx.movement.JumpZVelocity == 450)
end)
test("a lingering modifier after removal still retains recovery", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true)
    local remove = f.ctx.asc.RemoveActiveGameplayEffect
    f.ctx.asc.RemoveActiveGameplayEffect = function(...) local ok = remove(...); f.ctx.attributes.JumpVelocity.CurrentValue = 600; return ok end
    assert(not pcall(f.pilot.set, false)); assert(f.pilot.owned())
end)
test("a jump velocity still settling after a flight refuses the enable before any write", function()
    local f = fixture(); f.pilot.inspect()
    f.ctx.movement.JumpZVelocity = 450 * math.sqrt(2) -- what the game shows right after Fly OFF
    local ok, err = pcall(f.pilot.set, true)
    assert(not ok and tostring(err):find("still settling", 1, true), tostring(err))
    local applied = f.counts(); assert(applied == 0 and not f.pilot.owned())
    f.ctx.movement.JumpZVelocity = 450; f.pilot.inspect(); f.pilot.set(true); assert(f.pilot.owned())
end)
test("removal refusal retains recovery and retries", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true); f.failRemove(true)
    assert(not pcall(f.pilot.set, false)); assert(f.pilot.owned())
    f.failRemove(false); f.pilot.set(false); assert(not f.pilot.owned())
end)
test("changed component identity refuses removal", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true)
    f.ctx.movement.GetAddress = function() return 99 end
    assert(not pcall(f.pilot.set, false)); local _, removed = f.counts(); assert(removed == 0 and f.pilot.owned())
end)
test("additional effect behavior rejects inspection", function()
    local f = fixture(); f.cdo.GEComponents = { object(42) }; assert(not pcall(f.pilot.inspect)); assert(f.counts() == 0)
end)
test("cleanup restores owned effect and requires new inspection", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true); f.pilot.reset()
    assert(not f.pilot.owned() and not pcall(f.pilot.set, true))
end)
test("rejected handle evidence includes native fields and count", function()
    local f = fixture(); f.pilot.inspect()
    f.ctx.asc.BP_ApplyGameplayEffectSpecToSelf = function() return { Handle = -1, bPassedFiltersAndWasExecuted = false } end
    local ok, cause = pcall(f.pilot.set, true)
    assert(not ok and cause:find("handle=-1;passed_filters=false;effect_count=0", 1, true))
    assert(not f.pilot.owned())
end)
test("opaque spec table is rejected before apply and hook is removed", function()
    local f = fixture(); f.pilot.inspect(); f.tableSpec()
    local ok, cause = pcall(f.pilot.set, true)
    assert(not ok and cause:find("marshalled to a Lua table", 1, true) and f.counts() == 0)
    local registered, removed, hook = f.hooks(); assert(registered == 1 and removed == 1 and hook == nil)
end)
test("successful apply pairs hook cleanup before returning", function()
    local f = fixture(); f.pilot.inspect(); f.pilot.set(true)
    local registered, removed, hook = f.hooks(); assert(registered == 1 and removed == 1 and hook == nil)
    f.pilot.reset()
end)
print(count .. " super jump effect tests passed")
