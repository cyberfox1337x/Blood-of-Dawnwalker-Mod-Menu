local cyberfox1337x={signature=function(name)return name end};cyberfox1337x.signature("carry_capacity_effect_pilot_tests")
local M=assert(loadfile(assert(arg[1])))()
IsInGameThread=function()return true end;FName=function(v)return v end
PropertyTypes={}
local function object(id) return {IsValid=function()return true end,GetAddress=function()return id end} end
local function scalable(v)return{Value=v,Curve={RowName="None"},RegistryType={Name="None"}}end
local function clean(o)
    for _,k in ipairs({"Executions","GrantedAbilities","GEComponents","GameplayCues","ApplicationRequirements","ConditionalGameplayEffects","OverflowEffects","PrematureExpirationEffectClasses","RoutineExpirationEffectClasses","Modifiers"})do o[k]={}end
    for _,k in ipairs({"InheritableGameplayEffectTags","InheritableOwnedTagsContainer","InheritableBlockedAbilityTagsContainer","RemoveGameplayEffectsWithTags"})do o[k]={CombinedTags={GameplayTags={}},Added={GameplayTags={}},Removed={GameplayTags={}}}end
    for _,k in ipairs({"OngoingTagRequirements","ApplicationTagRequirements","RemovalTagRequirements","GrantedApplicationImmunityTags"})do o[k]={RequireTags={GameplayTags={}},IgnoreTags={GameplayTags={}}}end
    o.Period=scalable(0);o.ChanceToApplyToTarget=scalable(1);o.DurationPolicy=0;o.StackingType=0
end
-- The fixture models the engine contract from CARRY-CAPACITY-FEASIBILITY.md rather than a
-- convenient one: GetWeightLimit is the raw WeightLimit plus the attribute, bWeightExceeded
-- is false for a zero effective limit and a comparison otherwise, and applying the private
-- effect is what moves the attribute. A module that got the arithmetic wrong would fail
-- these assertions instead of passing them.
local RAW,WEIGHT=200,3.82
local function fixture(options)
    options=options or {}
    local ctx={}
    for i,k in ipairs({"player","controller","world","asc","char_dev","inventory","sourceClass","effectClass","source","base","library"})do ctx[k]=object(i)end
    ctx.player.Controller=ctx.controller;ctx.controller.Pawn=ctx.player
    ctx.player.GetWorld=function()return ctx.world end;ctx.controller.GetWorld=ctx.player.GetWorld
    ctx.player.AbilitySystemComponent=ctx.asc;ctx.player.CharDevAttributeSet=ctx.char_dev
    ctx.player.GetInventoryComponent=function()return ctx.inventory end
    ctx.asc.GetOuter=function()return ctx.player end;ctx.char_dev.GetOuter=ctx.asc.GetOuter
    ctx.source.GetClass=function()return ctx.sourceClass end;ctx.sourceClass.GetCDO=function()return ctx.source end
    ctx.base.GetClass=function()return ctx.effectClass end
    local owner=object(88);owner.GetFullName=function()return "Class /Script/DogwoodStats.CharDevAttributeSet" end
    ctx.descriptor={GetStructAddress=function()return 111 end,AttributeOwner=owner,AttributeName="CarryWeightCapacityModifier"}
    ctx.source.Modifiers={{Attribute=ctx.descriptor,ModifierOp=0,ModifierMagnitude={MagnitudeCalculationType=3,ScalableFloatMagnitude=scalable(30)},SourceTags={RequireTags={GameplayTags={}},IgnoreTags={GameplayTags={}},TagQuery={empty=true}},TargetTags={RequireTags={GameplayTags={}},IgnoreTags={GameplayTags={}},TagQuery={empty=true}},EvaluationChannelSettings={Channel=0}}}
    ctx.queryLibrary=object(89)
    ctx.queryLibrary.GetFullName=function()return "BlueprintGameplayTagLibrary /Script/GameplayTags.Default__BlueprintGameplayTagLibrary" end
    ctx.queryLibrary.IsTagQueryEmpty=function(_,query)assert(type(query)=="table" and type(query.empty)=="boolean");return query.empty end
    ctx.library.GetAbilitySystemComponent=function()return ctx.asc end
    ctx.library.GetDebugStringFromGameplayAttribute=function()return "CharDevAttributeSet.CarryWeightCapacityModifier" end
    clean(ctx.base)
    local data={BaseValue=options.base or 0,CurrentValue=options.current or options.base or 0}
    ctx.char_dev.CarryWeightCapacityModifier=data
    ctx.inventory.WeightLimit=RAW
    ctx.inventory.GetCurrentWeight=function()return WEIGHT end
    ctx.inventory.CanExceedWeightLimit=function()return true end
    local function effective()
        local limit=RAW+data.CurrentValue
        if options.limitDrift then limit=limit+options.limitDrift end
        return limit
    end
    ctx.inventory.GetWeightLimit=effective
    local function recompute()
        local limit=RAW+data.CurrentValue
        -- Stated as the engine's rule, not as `limit==0 and false or WEIGHT>limit`: that
        -- spelling evaluates to true for a zero limit and would hide the very case the
        -- pilot exists to reach.
        if limit==0 then ctx.inventory.bWeightExceeded=false else ctx.inventory.bWeightExceeded=WEIGHT>limit end
    end
    recompute()
    ctx.asc.GetGameplayAttributeValue=function(_,d,out)assert(d==ctx.descriptor);out.bFound=true;return data.CurrentValue end
    StaticFindObject=function()return object(900)end

    local private,post,borrowed=nil,nil,nil
    local applies,removes,registers,unregisters=0,0,0,0
    local failRemove,failApply,tableSpec,alias=options.removeFails or false,false,false,false
    local drift=options.drift or 0
    local function construct()
        private=object(22);clean(private);private.GetOuter=function()return ctx.asc end;private.GetClass=function()return ctx.effectClass end
        -- Cleared so the assignment below really goes through the copy trap, exactly as the
        -- native TArray copy is the only thing that gives the private instance a modifier.
        private.Modifiers=nil
        local copied={}
        setmetatable(private,{__newindex=function(t,k,v)
            if k=="Modifiers"then
                if alias then copied=v else copied={{Attribute={GetStructAddress=function()return 112 end,AttributeOwner=owner,AttributeName="CarryWeightCapacityModifier"},ModifierOp=0,ModifierMagnitude={MagnitudeCalculationType=3,ScalableFloatMagnitude=scalable(30)},SourceTags={RequireTags={GameplayTags={}},IgnoreTags={GameplayTags={}},TagQuery={empty=true}},TargetTags={RequireTags={GameplayTags={}},IgnoreTags={GameplayTags={}},TagQuery={empty=true}},EvaluationChannelSettings={Channel=0}}}end
            else rawset(t,k,v)end
        end,__index=function(_,k)if k=="Modifiers"then return copied end end})
        return private
    end
    local function raw(v)return{get=function()return v end}end
    ctx.library.MakeSpecHandle=function(_,definition,p,c,l)
        assert(post and definition==private and p==ctx.player and c==p and l==1)
        local native=assert(io.tmpfile());local mt=debug.getmetatable(native);local closer=native.close
        debug.setmetatable(native,{__index={GetStructAddress=function()return 555 end}})
        borrowed=tableSpec and {} or native
        post(raw(ctx.library),raw(borrowed),raw(definition),raw(p),raw(c),raw(l));borrowed=nil
        debug.setmetatable(native,mt);closer(native)
        return {}
    end
    ctx.asc.BP_ApplyGameplayEffectSpecToSelf=function(_,spec)
        assert(spec==borrowed and type(spec)=="userdata");applies=applies+1
        if failApply then error("uncertain apply")end
        local delta=private.Modifiers[1].ModifierMagnitude.ScalableFloatMagnitude.Value+drift
        data.CurrentValue=data.CurrentValue+delta;recompute() -- duration effects leave BaseValue alone
        return{Handle=123,bPassedFiltersAndWasExecuted=true}
    end
    ctx.library.GetGameplayEffectFromActiveEffectHandle=function()return private end
    ctx.library.GetActiveGameplayEffectStackCount=function()return 1 end
    ctx.asc.RemoveActiveGameplayEffect=function(_,h,n)
        assert(h.Handle==123 and n==-1);removes=removes+1
        if failRemove then return false end
        local delta=private.Modifiers[1].ModifierMagnitude.ScalableFloatMagnitude.Value+drift
        data.CurrentValue=data.CurrentValue-delta;recompute()
        return true
    end
    ctx.asc.GetGameplayEffectCount=function()error("Broad class count forbidden")end

    local probeOk=options.probeOk~=false
    local snapshot={player_address=tostring(ctx.player:GetAddress()),world_address=tostring(ctx.world:GetAddress()),
        inventory_address=tostring(ctx.inventory:GetAddress()),asc_address=tostring(ctx.asc:GetAddress()),
        char_dev_address=tostring(ctx.char_dev:GetAddress())}
    local probe={run=function()return{ok=probeOk,mutation_authorized=false,stage="read-only-complete",
        message="no setter was invoked",snapshot=snapshot}end}
    local pilot=M.New({GetPlayer=function()return ctx.player end},{borrow=function()return ctx end,construct=construct,
        probe=probe,static_find_object=StaticFindObject,property_types=PropertyTypes,
        isPaused=function()return options.paused~=false end,
        registerHook=function(_,_,fn)registers=registers+1;post=fn;return 1,2 end,
        unregisterHook=function()unregisters=unregisters+1;post=nil end})
    return{pilot=pilot,ctx=ctx,data=data,counts=function()return applies,removes,registers,unregisters end,
        applyFailure=function()failApply=true end,tableSpec=function()tableSpec=true end,alias=function()alias=true end,
        probeFailure=function()snapshot.player_address="999" end}
end
local n=0
local function test(name,fn)local ok,err=pcall(fn);assert(ok,name..": "..tostring(err));n=n+1;print("PASS "..name)end

test("paused roundtrip reaches an exact zero limit and restores the exact baseline",function()
    local f=fixture();f.pilot.roundtrip()
    assert(not f.pilot.owned(),"ownership must be released after the roundtrip")
    assert(f.ctx.inventory:GetWeightLimit()==RAW,"the limit must be back to the raw value")
    assert(f.ctx.inventory.bWeightExceeded==false)
    assert(f.data.BaseValue==0 and f.data.CurrentValue==0,"the attribute must be back to zero")
    local a,r,h,u=f.counts();assert(a==1 and r==1 and h==u,"one apply, one removal, hooks paired")
end)

test("the applied delta is exactly the negative of the live effective limit",function()
    local f=fixture();f.pilot.inspect()
    f.pilot.set(true)
    assert(f.data.BaseValue==0 and f.data.CurrentValue==-RAW,"delta must cancel the live limit exactly, on the current value only")
    assert(f.ctx.inventory:GetWeightLimit()==0,"the engine sentinel is an exactly zero effective limit")
    assert(f.ctx.inventory.bWeightExceeded==false,"a zero limit must report not exceeded")
    assert(f.pilot.status():find("no limit",1,true),f.pilot.status())
    f.pilot.set(false)
    assert(f.ctx.inventory:GetWeightLimit()==RAW)
end)

test("the roundtrip holds the zero limit before it restores",function()
    local f=fixture();f.pilot.roundtrip()
    local status=f.pilot.status()
    assert(status:find("held limit 0",1,true),status)
    assert(status:find("restored limit 200",1,true),status)
end)

test("a pre-existing additive contribution is cancelled exactly and restored",function()
    -- An owned Strong Back level, or any other additive source, is already reflected in the
    -- live effective limit, so the delta derived from that limit cancels it correctly.
    local f=fixture({base=30});f.pilot.inspect()
    f.pilot.set(true)
    assert(f.data.CurrentValue==-RAW,"the existing 30 must be absorbed into the cancellation")
    assert(f.ctx.inventory:GetWeightLimit()==0)
    assert(f.ctx.inventory.bWeightExceeded==false)
    f.pilot.set(false)
    assert(f.data.BaseValue==30 and f.data.CurrentValue==30,"the existing contribution must come back")
    assert(f.ctx.inventory:GetWeightLimit()==RAW+30)
end)

test("a multiplicative carry-capacity modifier is refused before any write",function()
    local f=fixture({base=30,current=45})
    assert(not pcall(f.pilot.inspect),"a divergent attribute must be refused at inspection")
    -- A refused inspection must leave the pilot un-armed, so the toggle cannot write either.
    assert(not pcall(f.pilot.set,true),"an un-inspected pilot must not enable")
    assert(f.counts()==0,"nothing may be constructed or applied")
end)

test("an inventory with no positive limit is refused at the write",function()
    -- Reading such a session is fine; granting it a limit would be a change, so the refusal
    -- belongs at the preconditions of the write rather than at inspection.
    local f=fixture();f.ctx.inventory.WeightLimit=0;f.ctx.inventory.GetWeightLimit=function()return 0 end
    f.pilot.inspect()
    assert(not pcall(f.pilot.set,true),"an inventory with no limit must not be given one")
    assert(f.counts()==0)
end)

test("a probe that did not pass blocks the write",function()
    local f=fixture({probeOk=false});f.pilot.inspect()
    assert(not pcall(f.pilot.set,true),"the enable gate must require the probe verdict")
    assert(f.counts()==0,"no effect may be constructed when the probe did not pass")
end)

test("a probe that passed on another session blocks the write",function()
    local f=fixture();f.pilot.inspect();f.probeFailure()
    assert(not pcall(f.pilot.set,true))
    assert(f.counts()==0)
end)

test("an inexact zero limit is refused, restored, and never published as ON",function()
    -- The feasibility note warns that reaching exactly zero through a modifier needs exact
    -- cancellation. Here the applied delta is deliberately 0.5 out, so the post-state is a
    -- 0.5 limit rather than zero: the pilot must refuse to own it and must put the baseline
    -- back through the same exact handle.
    local f=fixture({drift=0.5});f.pilot.inspect()
    local ok,err=pcall(f.pilot.set,true)
    assert(not ok,"an inexact zero limit must fail closed")
    assert(tostring(err):find("did not reach the zero effective limit",1,true),tostring(err))
    assert(not f.pilot.owned(),"a refused write must not stay applied")
    assert(f.ctx.inventory:GetWeightLimit()==RAW,"the baseline must be restored")
    local a,r=f.counts();assert(a==1 and r==1,"one apply and one exact removal")
end)

test("the borrowed Strong Back source is never changed",function()
    local f=fixture();f.pilot.inspect();f.pilot.set(true)
    local m=f.ctx.source.Modifiers[1]
    assert(m.ModifierMagnitude.MagnitudeCalculationType==3,"the source calculation type changed")
    assert(m.ModifierMagnitude.ScalableFloatMagnitude.Value==30,"the source magnitude changed")
    assert(f.ctx.base.DurationPolicy==0,"the native template changed")
    f.pilot.reset()
end)

test("the private descriptor is a copy, not the borrowed one",function()
    local f=fixture();f.alias();f.pilot.inspect()
    assert(not pcall(f.pilot.set,true),"an aliased descriptor must be refused")
    assert(f.counts()==0)
end)

test("a Lua table in place of the opaque spec is refused before apply",function()
    local f=fixture();f.tableSpec();f.pilot.inspect()
    assert(not pcall(f.pilot.set,true))
    local a,r,h,u=f.counts();assert(a==0 and r==0 and h==u and not f.pilot.owned())
end)

test("an uncertain apply retains recovery without a broad removal",function()
    local f=fixture();f.applyFailure();f.pilot.inspect()
    assert(not pcall(f.pilot.set,true))
    assert(f.pilot.owned(),"an uncertain apply must keep recovery")
    local _,r,h,u=f.counts();assert(r==0 and h==u)
end)

test("the effect is applied once and re-verify does not stack it",function()
    local f=fixture();f.pilot.inspect();f.pilot.set(true)
    assert(f.pilot.set(true):find("ON:",1,true),"a repeated ON reports the ON state")
    local a,r=f.counts();assert(a==1 and r==0,"a repeated ON must verify, not apply again")
    f.pilot.set(false)
    local a2,r2=f.counts();assert(a2==1 and r2==1,"a second ON must not have added a second removal")
    assert(f.ctx.inventory:GetWeightLimit()==RAW)
end)

test("removal retry after a refused removal restores the baseline",function()
    local f=fixture();f.pilot.inspect();f.pilot.set(true)
    f.ctx.asc.RemoveActiveGameplayEffect=function(_,h,n)
        assert(h.Handle==123 and n==-1)
        return false
    end
    assert(not pcall(f.pilot.set,false),"a refused removal must fail closed")
    assert(f.pilot.owned())
    f.ctx.asc.RemoveActiveGameplayEffect=function(_,h,n)
        assert(h.Handle==123 and n==-1)
        f.data.CurrentValue=f.data.BaseValue
        f.ctx.inventory.bWeightExceeded=false
        return true
    end
    f.pilot.reset()
    assert(not f.pilot.owned(),"a successful retry must release ownership")
    assert(f.ctx.inventory:GetWeightLimit()==RAW)
end)

test("a changed session identity retains recovery instead of removing",function()
    local f=fixture();f.pilot.inspect();f.pilot.set(true)
    f.ctx.world.GetAddress=function()return 99 end
    assert(not pcall(f.pilot.reset))
    local _,r=f.counts()
    assert(r==0 and f.pilot.owned(),"a changed session must not be removed through")
end)

test("an ON without inspect is refused",function()
    local f=fixture()
    assert(not pcall(f.pilot.set,true))
    assert(f.counts()==0)
end)

test("a nonempty copied modifier query refuses inspection",function()
    local f=fixture();f.ctx.source.Modifiers[1].SourceTags.TagQuery.empty=false
    assert(not pcall(f.pilot.inspect))
    assert(f.counts()==0)
end)

test("a descriptor owned by another attribute set refuses inspection",function()
    local f=fixture();f.ctx.descriptor.AttributeName="SprintStaminaCostMultiplier"
    assert(not pcall(f.pilot.inspect))
    assert(f.counts()==0)
end)

test("a roundtrip on an unpaused game is refused before any write",function()
    local f=fixture({paused=false})
    assert(not pcall(f.pilot.roundtrip))
    assert(f.counts()==0)
end)

test("a non-boolean set is refused",function()
    local f=fixture();f.pilot.inspect()
    assert(not pcall(f.pilot.set,1))
    assert(f.counts()==0)
end)

print(n.." carry-capacity effect pilot groups passed")
