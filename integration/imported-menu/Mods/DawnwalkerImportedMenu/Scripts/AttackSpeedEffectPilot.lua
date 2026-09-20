local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("attack_speed_owned_effect_pilot")
local M = {}
local SOURCE = "/Game/_Dawnwalker/Combat/Focus/Sword/SwiftAdvance/GE_SwiftAdvance_AttackSpeed_Lvl1"
local SPEC = "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:MakeSpecHandle"
local ATTRIBUTE = "AttackSpeedMultiplierAdditive"
local function valid(o) return o and o:IsValid() end
local function address(o) assert(valid(o), "Attack object unavailable"); return o:GetAddress() end
local function finite(v) assert(type(v) == "number" and v == v and math.abs(v) < math.huge, "Nonfinite attack value"); return v end
local function close(a,b) return math.abs(a-b) <= math.max(.00001, math.abs(b)*.00001) end
local function text(v) return type(v) == "string" and v or v:ToString() end
local function unwrap(v) local ok,r=pcall(function() return v:get() end); return ok and r or v end
local function count(v)
    assert(v ~= nil, "Attack schema array unavailable")
    local ok,n=pcall(function() return v:GetArrayNum() end)
    if not ok then n=#v end
    assert(type(n)=="number" and n>=0 and n<=64 and n%1==0,"Attack schema array out of bounds")
    return n
end
local function plain(v, expected)
    assert(close(finite(v.Value),expected),"Attack scalable value mismatch")
    assert(not valid(v.Curve.CurveTable) and text(v.Curve.RowName)=="None" and text(v.RegistryType.Name)=="None","Attack magnitude has curve/registry behavior")
end
local EMPTY_ARRAYS={"Executions","GrantedAbilities","GEComponents","GameplayCues","ApplicationRequirements","ConditionalGameplayEffects","OverflowEffects","PrematureExpirationEffectClasses","RoutineExpirationEffectClasses"}
local function emptyTags(v) assert(count(v.GameplayTags)==0,"Native effect unexpectedly grants or filters tags") end
local function modifierRequirements(ctx,modifier)
    local library=ctx.queryLibrary
    assert(valid(library) and library:GetFullName()=="BlueprintGameplayTagLibrary /Script/GameplayTags.Default__BlueprintGameplayTagLibrary","Tag-query library unavailable")
    assert(modifier.EvaluationChannelSettings.Channel==0,"Attack modifier evaluation channel is unsupported")
    for _,field in ipairs({"SourceTags","TargetTags"}) do
        local tags=assert(modifier[field],"Private modifier tag requirements unavailable")
        emptyTags(tags.RequireTags);emptyTags(tags.IgnoreTags)
        -- Reflected IsTagQueryEmpty takes the existing const FGameplayTagQuery&;
        -- never replace the native query struct with a reconstructed Lua table.
        assert(tags.TagQuery~=nil and library:IsTagQueryEmpty(tags.TagQuery)==true,"Attack modifier has nonempty or unreadable tag query: "..field)
    end
end
local function cleanDefinition(o)
    for _,k in ipairs(EMPTY_ARRAYS) do assert(count(o[k])==0,"Native effect behavior present: "..k) end
    for _,k in ipairs({"InheritableGameplayEffectTags","InheritableOwnedTagsContainer","InheritableBlockedAbilityTagsContainer","RemoveGameplayEffectsWithTags"}) do
        for _,part in ipairs({"CombinedTags","Added","Removed"}) do emptyTags(o[k][part]) end
    end
    for _,k in ipairs({"OngoingTagRequirements","ApplicationTagRequirements","RemovalTagRequirements","GrantedApplicationImmunityTags"}) do emptyTags(o[k].RequireTags);emptyTags(o[k].IgnoreTags) end
    plain(o.Period,0);plain(o.ChanceToApplyToTarget,1)
end
local function defaultBorrow(helpers)
    local player=helpers.GetPlayer();assert(valid(player) and player:IsA("/Script/Dawnwalker.DawnwalkerPlayerCharacter"),"Controlled player unavailable")
    assert(valid(player.CombatComponent) and player.CombatComponent:IsAlive(),"A living player is required to enable attack bonus")
    local ctx={player=player,controller=player.Controller,world=player:GetWorld(),asc=player.AbilitySystemComponent,attributes=player.CharacterAttributeSet}
    assert(valid(ctx.asc) and ctx.asc:IsA("/Script/Dawnwalker.DawnwalkerAbilitySystemComponent"),"Wrong player ASC")
    assert(valid(ctx.attributes) and ctx.attributes:IsA("/Script/DogwoodStats.CharacterBaseAttributeSet"),"Wrong player attributes")
    ctx.sourceClass=StaticFindObject(SOURCE..".GE_SwiftAdvance_AttackSpeed_Lvl1_C")
    assert(valid(ctx.sourceClass) and ctx.sourceClass:GetFullName()=="BlueprintGeneratedClass "..SOURCE..".GE_SwiftAdvance_AttackSpeed_Lvl1_C","Loaded Swift class unavailable")
    ctx.source=ctx.sourceClass:GetCDO()
    ctx.effectClass=StaticFindObject("/Script/GameplayAbilities.GameplayEffect")
    assert(valid(ctx.effectClass) and ctx.effectClass:GetFullName()=="Class /Script/GameplayAbilities.GameplayEffect","Native effect class unavailable")
    ctx.base=ctx.effectClass:GetCDO()
    ctx.library=StaticFindObject("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
    ctx.queryLibrary=StaticFindObject("/Script/GameplayTags.Default__BlueprintGameplayTagLibrary")
    assert(valid(ctx.library) and ctx.library:GetFullName()=="AbilitySystemBlueprintLibrary /Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary","Ability library unavailable")
    assert(count(ctx.source.Modifiers)==1,"Swift modifier count changed")
    ctx.descriptor=unwrap(ctx.source.Modifiers[1]).Attribute
    return ctx
end

function M.New(helpers,deps)
    deps=deps or {}
    local record,ready,hookIds,pending=nil,false,nil,nil
    local status="Not inspected; no owned attack effect."
    local function session(ctx)
        assert(IsInGameThread()==true,"Attack pilot requires game thread")
        for _,key in ipairs({"player","controller","world","asc","attributes","library"}) do assert(valid(ctx[key]),"Attack session object unavailable: "..key) end
        assert(address(helpers.GetPlayer())==address(ctx.player) and address(ctx.controller.Pawn)==address(ctx.player)
            and address(ctx.player.Controller)==address(ctx.controller) and address(ctx.player:GetWorld())==address(ctx.world)
            and address(ctx.controller:GetWorld())==address(ctx.world) and address(ctx.player.AbilitySystemComponent)==address(ctx.asc)
            and address(ctx.player.CharacterAttributeSet)==address(ctx.attributes),"Attack session changed; recovery retained")
        assert(address(ctx.asc:GetOuter())==address(ctx.player) and address(ctx.attributes:GetOuter())==address(ctx.player),"Attack ownership mismatch")
    end
    local function read(ctx)
        session(ctx)
        local d=ctx.attributes[ATTRIBUTE];local base,current=finite(d.BaseValue),finite(d.CurrentValue);local out={}
        local value=finite(ctx.asc:GetGameplayAttributeValue(ctx.descriptor,out))
        assert(out.bFound==true and close(current,value),"Attack ASC readback mismatch")
        return {base=base,current=current}
    end
    local function context()
        local ctx=(deps.borrow or function() return defaultBorrow(helpers) end)();session(ctx)
        assert(address(ctx.library:GetAbilitySystemComponent(ctx.player))==address(ctx.asc),"Attack ASC resolver mismatch")
        assert(valid(ctx.source) and address(ctx.source:GetClass())==address(ctx.sourceClass),"Swift CDO class mismatch")
        assert(address(ctx.sourceClass:GetCDO())==address(ctx.source) and address(ctx.base:GetClass())==address(ctx.effectClass),"Attack source template mismatch")
        assert(count(ctx.source.Modifiers)==1 and unwrap(ctx.source.Modifiers[1]).ModifierOp==0,"Swift additive modifier mismatch")
        assert(valid(StaticFindObject("/Script/GameplayTags.BlueprintGameplayTagLibrary:IsTagQueryEmpty")),"Native tag-query reader unavailable")
        modifierRequirements(ctx,unwrap(ctx.source.Modifiers[1]))
        local d=ctx.descriptor
        assert(unwrap(ctx.source.Modifiers[1]).Attribute:GetStructAddress()==d:GetStructAddress(),"Borrowed attack descriptor is not the source modifier")
        assert(text(d.AttributeName)==ATTRIBUTE and valid(d.AttributeOwner) and d.AttributeOwner:GetFullName()=="Class /Script/DogwoodStats.CharacterBaseAttributeSet"
            and finite(d:GetStructAddress())>0,"Attack descriptor mismatch")
        local debugName=text(ctx.library:GetDebugStringFromGameplayAttribute(d))
        assert(debugName:find(ATTRIBUTE,1,true) and debugName:find("CharacterBaseAttributeSet",1,true),"Attack descriptor debug mismatch")
        cleanDefinition(ctx.base);assert(count(ctx.base.Modifiers)==0 and ctx.base.DurationPolicy==0 and ctx.base.StackingType==0,"Native base template changed")
        local values=read(ctx);assert(close(values.base,values.current),"Other attack modifiers active")
        for _,path in ipairs({SPEC,"/Script/GameplayAbilities.AbilitySystemComponent:BP_ApplyGameplayEffectSpecToSelf"}) do assert(valid(StaticFindObject(path)),"Attack native method unavailable") end
        return ctx,values
    end
    local function releaseHook()
        pending=nil
        if not hookIds then return end
        (deps.unregisterHook or UnregisterHook)(SPEC,hookIds[1],hookIds[2]);hookIds=nil
    end
    local function verifyHandle(r)
        session(r.ctx)
        for key,id in pairs(r.ids) do assert(address(r.ctx[key])==id,"Recorded attack identity changed; recovery retained") end
        assert(r.handle and r.handle.Handle==r.handleId and r.handleId>=0,"Exact attack handle unavailable; recovery retained")
        assert(address(r.ctx.library:GetGameplayEffectFromActiveEffectHandle(r.handle))==r.privateId,"Attack handle source mismatch")
        assert(r.ctx.library:GetActiveGameplayEffectStackCount(r.handle)==1,"Attack owned stack mismatch")
    end
    local function restore()
        releaseHook()
        if not record then return end
        local r=record;session(r.ctx)
        if not r.attempted then record=nil;return end
        if not r.removed then
            verifyHandle(r)
            assert(r.ctx.asc:RemoveActiveGameplayEffect(r.handle,-1)==true,"Exact attack effect removal refused; recovery retained")
            r.removed=true
        end
        local values=read(r.ctx)
        assert(close(values.base,r.baseline.base) and close(values.current,r.baseline.current),"Attack baseline restoration mismatch; recovery retained")
        record=nil;status="OFF: exact private effect removed; attack baseline restored."
    end
    local function verify()
        assert(record,"No owned attack effect")
        verifyHandle(record);local values=read(record.ctx)
        assert(close(values.base,record.baseline.base) and close(values.current,record.baseline.current+.1),"Attack effect readback mismatch")
        status="ON: private +0.1 attack bonus verified. Normal human fist playback tested at +10%; other attacks unverified."
        return status
    end
    local function enable()
        assert(ready,"Inspect attack pilot first")
        if record then return verify() end
        local ctx,baseline=context()
        local construct=deps.construct or StaticConstructObject
        local private=construct(ctx.effectClass,ctx.asc,FName("None"),0x40,0,false,false,ctx.base)
        assert(valid(private) and address(private)~=address(ctx.base) and address(private)~=address(ctx.source)
            and address(private:GetOuter())==address(ctx.asc) and address(private:GetClass())==address(ctx.effectClass),"Private attack effect construction failed")
        cleanDefinition(private);assert(count(private.Modifiers)==0,"Private native template has modifiers")
        -- Pinned native TArray copy preserves FGameplayAttribute FieldPath.
        private.Modifiers=ctx.source.Modifiers
        assert(count(private.Modifiers)==1,"Private modifier copy failed")
        local modifier=unwrap(private.Modifiers[1]);local original=unwrap(ctx.source.Modifiers[1])
        assert(modifier.Attribute:GetStructAddress()~=ctx.descriptor:GetStructAddress()
            and text(modifier.Attribute.AttributeName)==ATTRIBUTE and address(modifier.Attribute.AttributeOwner)==address(ctx.descriptor.AttributeOwner),"Private descriptor alias or mismatch")
        local originalType=original.ModifierMagnitude.MagnitudeCalculationType
        local originalValue=original.ModifierMagnitude.ScalableFloatMagnitude.Value
        assert(modifier.ModifierOp==0,"Private modifier operation changed")
        modifierRequirements(ctx,modifier)
        modifier.ModifierMagnitude.MagnitudeCalculationType=0
        modifier.ModifierMagnitude.ScalableFloatMagnitude.Value=.1
        plain(modifier.ModifierMagnitude.ScalableFloatMagnitude,.1)
        private.DurationPolicy=1;private.StackingType=0
        assert(private.DurationPolicy==1 and private.StackingType==0 and original.ModifierMagnitude.MagnitudeCalculationType==originalType
            and original.ModifierMagnitude.ScalableFloatMagnitude.Value==originalValue and ctx.base.DurationPolicy==0,"Shared attack source changed")
        cleanDefinition(private)
        record={ctx=ctx,private=private,privateId=address(private),baseline=baseline,attempted=false}
        record.ids={}
        for _,key in ipairs({"player","controller","world","asc","attributes","library"}) do record.ids[key]=address(ctx[key]) end
        local r=record
        pending={consumed=false}
        local request=pending
        local function after(rawContext,rawReturn,rawEffect,rawInstigator,rawCauser,rawLevel)
            if pending~=request then return end
            local ok,cause=pcall(function()
                if address(rawEffect:get())~=r.privateId then return end
                assert(not request.consumed,"Duplicate attack spec callback");request.consumed=true
                session(ctx)
                assert(address(rawContext:get())==address(ctx.library) and address(rawInstigator:get())==address(ctx.player)
                    and address(rawCauser:get())==address(ctx.player) and rawLevel:get()==1,"Attack spec arguments differ")
                local spec=rawReturn:get()
                assert(type(spec)=="userdata" and finite(spec:GetStructAddress())>0,"Opaque attack spec must remain native userdata")
                r.attempted=true
                r.handle=ctx.asc:BP_ApplyGameplayEffectSpecToSelf(spec)
                if r.handle and type(r.handle.Handle)=="number" and r.handle.Handle>=0 and r.handle.Handle%1==0 then r.handleId=r.handle.Handle end
                assert(r.handleId and r.handle.bPassedFiltersAndWasExecuted==true,"Attack apply result uncertain; recovery retained")
            end)
            if not ok then request.failure=tostring(cause) end
        end
        local pre,post=(deps.registerHook or RegisterHook)(SPEC,function() end,after)
        hookIds={pre,post};assert(type(pre)=="number" and type(post)=="number","Attack hook registration uncertain")
        local ok,cause=pcall(function() ctx.library:MakeSpecHandle(private,ctx.player,ctx.player,1) end)
        releaseHook()
        assert(ok and request.consumed and not request.failure,"Attack spec failed: "..tostring(request.failure or cause or "callback absent"))
        return verify()
    end
    local function set(value)
        assert(type(value)=="boolean","Attack pilot requires boolean")
        local ok,result=pcall(value and enable or restore)
        if not ok then
            ready=false;local cleaned,cause=pcall(restore)
            status=tostring(result)..(cleaned and "; baseline restored" or "; recovery pending: "..tostring(cause))
            error(status,0)
        end
        return status
    end
    return {
        inspect=function() ready=false;if record then verify() else context() end;ready=true;status="Inspected player-local attack descriptor; no new effect applied.";return status end,
        set=set,verify=verify,owned=function() return record~=nil or hookIds~=nil end,status=function() return status end,
        roundtrip=function()
            assert(not record,"Existing attack effect requires OFF first")
            local ctx,baseline=context()
            local paused=deps.isPaused or function()
                local library=StaticFindObject("/Script/Engine.Default__GameplayStatics")
                assert(valid(library),"Pause-state library unavailable")
                return library:IsGamePaused(ctx.player)
            end
            assert(paused()==true,"Pause the game before the attack roundtrip")
            local ok,cause=pcall(function()
                ready=true;set(true);verify();set(false)
                local restored=read(ctx)
                status="Paused attack roundtrip: base="..baseline.base..", before="..baseline.current..", applied="..(baseline.current+.1)..", restored="..restored.current..". Normal human fist playback tested at +10%; other attacks unverified."
            end)
            if not ok then local cleaned,detail=pcall(restore);error(tostring(cause)..(cleaned and "; restored" or "; recovery pending: "..tostring(detail)),0) end
            return status
        end,
        reset=function() ready=false;restore();return status end,
    }
end
return M
