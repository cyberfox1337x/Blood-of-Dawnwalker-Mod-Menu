local cyberfox1337x={signature=function(name)return name end};cyberfox1337x.signature("attack_speed_effect_pilot_tests")
local M=assert(loadfile(assert(arg[1])))()
IsInGameThread=function()return true end;FName=function(v)return v end
local function object(id) return {IsValid=function()return true end,GetAddress=function()return id end} end
local function scalable(v)return{Value=v,Curve={RowName="None"},RegistryType={Name="None"}}end
local function clean(o)
    for _,k in ipairs({"Executions","GrantedAbilities","GEComponents","GameplayCues","ApplicationRequirements","ConditionalGameplayEffects","OverflowEffects","PrematureExpirationEffectClasses","RoutineExpirationEffectClasses","Modifiers"})do o[k]={}end
    for _,k in ipairs({"InheritableGameplayEffectTags","InheritableOwnedTagsContainer","InheritableBlockedAbilityTagsContainer","RemoveGameplayEffectsWithTags"})do o[k]={CombinedTags={GameplayTags={}},Added={GameplayTags={}},Removed={GameplayTags={}}}end
    for _,k in ipairs({"OngoingTagRequirements","ApplicationTagRequirements","RemovalTagRequirements","GrantedApplicationImmunityTags"})do o[k]={RequireTags={GameplayTags={}},IgnoreTags={GameplayTags={}}}end
    o.Period=scalable(0);o.ChanceToApplyToTarget=scalable(1);o.DurationPolicy=0;o.StackingType=0
end
local function fixture()
    local ctx={};for i,k in ipairs({"player","controller","world","asc","attributes","sourceClass","effectClass","source","base","library"})do ctx[k]=object(i)end
    ctx.player.Controller=ctx.controller;ctx.controller.Pawn=ctx.player
    ctx.player.GetWorld=function()return ctx.world end;ctx.controller.GetWorld=ctx.player.GetWorld
    ctx.player.AbilitySystemComponent=ctx.asc;ctx.player.CharacterAttributeSet=ctx.attributes
    ctx.asc.GetOuter=function()return ctx.player end;ctx.attributes.GetOuter=ctx.asc.GetOuter
    ctx.source.GetClass=function()return ctx.sourceClass end;ctx.sourceClass.GetCDO=function()return ctx.source end
    ctx.base.GetClass=function()return ctx.effectClass end
    local owner=object(88);owner.GetFullName=function()return"Class /Script/DogwoodStats.CharacterBaseAttributeSet"end
    ctx.descriptor={GetStructAddress=function()return 111 end,AttributeOwner=owner,AttributeName="AttackSpeedMultiplierAdditive"}
    ctx.source.Modifiers={{Attribute=ctx.descriptor,ModifierOp=0,ModifierMagnitude={MagnitudeCalculationType=3,ScalableFloatMagnitude=scalable(0)},SourceTags={RequireTags={GameplayTags={}},IgnoreTags={GameplayTags={}},TagQuery={empty=true}},TargetTags={RequireTags={GameplayTags={}},IgnoreTags={GameplayTags={}},TagQuery={empty=true}},EvaluationChannelSettings={Channel=0}}}
    ctx.queryLibrary=object(89)
    ctx.queryLibrary.GetFullName=function()return"BlueprintGameplayTagLibrary /Script/GameplayTags.Default__BlueprintGameplayTagLibrary"end
    ctx.queryLibrary.IsTagQueryEmpty=function(_,query)assert(type(query)=="table" and type(query.empty)=="boolean");return query.empty end
    clean(ctx.base)
    ctx.attributes.AttackSpeedMultiplierAdditive={BaseValue=0,CurrentValue=0}
    ctx.library.GetAbilitySystemComponent=function()return ctx.asc end
    ctx.library.GetDebugStringFromGameplayAttribute=function()return"CharacterBaseAttributeSet.AttackSpeedMultiplierAdditive"end
    ctx.asc.GetGameplayAttributeValue=function(_,d,out)assert(d==ctx.descriptor);out.bFound=true;return ctx.attributes.AttackSpeedMultiplierAdditive.CurrentValue end
    StaticFindObject=function()return object(900)end
    local private,post,borrowed,failRemove,failApply,tableSpec,alias,paused=nil,nil,nil,false,false,false,false,true
    local applies,removes,registers,unregisters=0,0,0,0
    local function construct()
        private=object(22);clean(private);private.GetOuter=function()return ctx.asc end;private.GetClass=function()return ctx.effectClass end
        private.Modifiers=nil
        local copied={}
        setmetatable(private,{__newindex=function(t,k,v)
            if k=="Modifiers"then
                if alias then copied=v else copied={{Attribute={GetStructAddress=function()return 112 end,AttributeOwner=owner,AttributeName="AttackSpeedMultiplierAdditive"},ModifierOp=0,ModifierMagnitude={MagnitudeCalculationType=3,ScalableFloatMagnitude=scalable(0)},SourceTags={RequireTags={GameplayTags={}},IgnoreTags={GameplayTags={}},TagQuery={empty=true}},TargetTags={RequireTags={GameplayTags={}},IgnoreTags={GameplayTags={}},TagQuery={empty=true}},EvaluationChannelSettings={Channel=0}}}end
            else rawset(t,k,v)end
        end,__index=function(_,k)if k=="Modifiers"then return copied end end})
        return private
    end
    local function raw(v)return{get=function()return v end}end
    ctx.library.MakeSpecHandle=function(_,definition,p,c,l)
        assert(post and definition==private and p==ctx.player and c==p and l==1)
        local native=assert(io.tmpfile());local mt=debug.getmetatable(native);local close=native.close
        debug.setmetatable(native,{__index={GetStructAddress=function()return 555 end}})
        borrowed=tableSpec and {} or native
        post(raw(ctx.library),raw(borrowed),raw(definition),raw(p),raw(c),raw(l));borrowed=nil
        debug.setmetatable(native,mt);close(native)
        return {}
    end
    ctx.asc.BP_ApplyGameplayEffectSpecToSelf=function(_,spec)
        assert(spec==borrowed and type(spec)=="userdata");applies=applies+1
        if failApply then error("uncertain apply")end
        ctx.attributes.AttackSpeedMultiplierAdditive.CurrentValue=.1
        return{Handle=123,bPassedFiltersAndWasExecuted=true}
    end
    ctx.library.GetGameplayEffectFromActiveEffectHandle=function()return private end
    ctx.library.GetActiveGameplayEffectStackCount=function()return 1 end
    ctx.asc.RemoveActiveGameplayEffect=function(_,h,n)assert(h.Handle==123 and n==-1);removes=removes+1;if failRemove then return false end;ctx.attributes.AttackSpeedMultiplierAdditive.CurrentValue=0;return true end
    ctx.asc.GetGameplayEffectCount=function()error("Broad class count forbidden")end
    local pilot=M.New({GetPlayer=function()return ctx.player end},{borrow=function()return ctx end,construct=construct,isPaused=function()return paused end,
        registerHook=function(_,_,fn)registers=registers+1;post=fn;return 1,2 end,
        unregisterHook=function()unregisters=unregisters+1;post=nil end})
    return{pilot=pilot,ctx=ctx,counts=function()return applies,removes,registers,unregisters end,
        removeFailure=function(v)failRemove=v end,applyFailure=function()failApply=true end,tableSpec=function()tableSpec=true end,
        alias=function()alias=true end,paused=function(v)paused=v end}
end
local n=0;local function test(name,fn)fn();n=n+1;print("PASS "..name)end
test("paused private copy roundtrip restores exact baseline",function()local f=fixture();f.pilot.roundtrip();assert(not f.pilot.owned());assert(f.ctx.source.Modifiers[1].ModifierMagnitude.MagnitudeCalculationType==3);local a,r,h,u=f.counts();assert(a==1 and r==1 and h==u)end)
test("native descriptor alias refuses apply",function()local f=fixture();f.alias();f.pilot.inspect();assert(not pcall(f.pilot.set,true));assert(f.counts()==0)end)
test("opaque table rejected before apply and hook removed",function()local f=fixture();f.tableSpec();f.pilot.inspect();assert(not pcall(f.pilot.set,true));local a,r,h,u=f.counts();assert(a==0 and r==0 and h==u and not f.pilot.owned())end)
test("uncertain apply retains recovery without broad removal",function()local f=fixture();f.applyFailure();f.pilot.inspect();assert(not pcall(f.pilot.set,true));assert(f.pilot.owned());local _,r,h,u=f.counts();assert(r==0 and h==u)end)
test("removal retry survives changed enable eligibility",function()local f=fixture();f.pilot.inspect();f.pilot.set(true);f.removeFailure(true);assert(not pcall(f.pilot.set,false));assert(f.pilot.owned());f.ctx.base.GEComponents={object(66)};f.removeFailure(false);f.pilot.reset();assert(not f.pilot.owned())end)
test("changed owner refuses exact handle removal",function()local f=fixture();f.pilot.inspect();f.pilot.set(true);f.ctx.asc.GetOuter=function()return f.ctx.asc end;assert(not pcall(f.pilot.set,false));assert(f.pilot.owned());local _,r=f.counts();assert(r==0)end)
test("paused roundtrip gate",function()local f=fixture();f.paused(false);assert(not pcall(f.pilot.roundtrip));assert(f.counts()==0)end)
test("wrong private handle source cannot be removed",function()local f=fixture();f.pilot.inspect();f.pilot.set(true);f.ctx.library.GetGameplayEffectFromActiveEffectHandle=function()return f.ctx.source end;assert(not pcall(f.pilot.reset));local _,r=f.counts();assert(r==0 and f.pilot.owned())end)
test("recorded session identity change retains recovery",function()local f=fixture();f.pilot.inspect();f.pilot.set(true);f.ctx.world.GetAddress=function()return 99 end;assert(not pcall(f.pilot.reset));local _,r=f.counts();assert(r==0 and f.pilot.owned())end)
test("nonempty copied modifier query refuses inspection",function()local f=fixture();f.ctx.source.Modifiers[1].SourceTags.TagQuery.empty=false;assert(not pcall(f.pilot.inspect));assert(f.counts()==0)end)
test("nonzero modifier evaluation channel refuses inspection",function()local f=fixture();f.ctx.source.Modifiers[1].EvaluationChannelSettings.Channel=1;assert(not pcall(f.pilot.inspect));assert(f.counts()==0)end)
print(n.." attack effect pilot groups passed")
