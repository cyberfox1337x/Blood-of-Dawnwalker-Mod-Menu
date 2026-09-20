local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature('skin_tint_control')
local M = {}
local SECTION = 'DWSkinTint'
local SKELETAL = '/Script/Engine.SkeletalMeshComponent'
local MID = '/Script/Engine.MaterialInstanceDynamic'
local DOLL = '/Game/_Dawnwalker/UI/_Unified/GameHub/Inventory/Doll/BP_RenderDoll2.BP_RenderDoll2_C'
local function valid(object) return object ~= nil and object:IsValid() == true end
local function same(a,b) return valid(a) and valid(b) and a:GetAddress() == b:GetAddress() end
local function unwrap(value)
    local ok, result = pcall(function() return value:get() end)
    return ok and result or value
end
local function array(values, limit)
    assert(values ~= nil, 'Native array unavailable')
    local ok, count = pcall(function() return values:GetArrayNum() end)
    if not ok then count = #values end
    assert(type(count)=='number' and count>=0 and count%1==0 and count<=limit, 'Native array exceeds safe bounds')
    local result={}
    for index=1,count do result[index]=unwrap(values[index]) end
    return result
end
local function colour(value)
    local result={}
    for _,key in ipairs({'R','G','B','A'}) do
        local channel=value[key]
        assert(type(channel)=='number' and channel==channel and math.abs(channel)<math.huge, 'Invalid skin vector readback')
        result[key]=channel
    end
    return result
end
local function equal(a,b)
    for _,key in ipairs({'R','G','B','A'}) do if math.abs(a[key]-b[key])>0.00001 then return false end end
    return true
end
local function parse(text)
    assert(type(text)=='string','Skin tint requires R,G,B')
    local r,g,b=text:match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$')
    assert(r and g and b,'Skin tint requires three integer channels')
    local values={tonumber(r),tonumber(g),tonumber(b)}
    for _,value in ipairs(values) do assert(value>=0 and value<=100,'Skin tint channels must be 0-100') end
    return {R=values[1]/50,G=values[2]/50,B=values[3]/50,A=1},table.concat(values,',')
end
function M.New(helpers)
    local entries, context, applied = {}, nil, nil
    local generation=0
    local function current()
        local player=helpers.GetPlayer()
        assert(valid(player) and player:IsA('/Script/Dawnwalker.DawnwalkerPlayerCharacter'),'Load Coen before applying skin tint')
        local world,controller=player:GetWorld(),player.Controller
        assert(valid(world) and valid(controller) and same(controller.Pawn,player),'Player possession changed')
        assert(player:IsInWolfForm()==false,'Skin tint is unavailable in wolf form')
        return {player=player,world=world,controller=controller,form=player.Form}
    end
    local function discover(ctx)
        local actors={ctx.player}
        for _,doll in ipairs(array(FindAllOf('BP_RenderDoll2_C') or {},16)) do
            if valid(doll) and doll:IsA(DOLL) and same(doll:GetWorld(),ctx.world) and not doll:GetFullName():find('Default__',1,true) then
                local inventory=doll.TargetInventory
                if valid(inventory) and same(inventory:GetOwner(),ctx.player) then actors[#actors+1]=doll end
            end
        end
        local found,seen={},{}
        for _,actor in ipairs(actors) do
            for _,component in ipairs(array(actor:K2_GetComponentsByClass(StaticFindObject(SKELETAL)),64)) do
                if valid(component) and component:IsA(SKELETAL) and same(component:GetOwner(),actor) then
                    local name=component:GetFullName()
                    local face=name:find('.Face',1,true) or name:find('.Head',1,true)
                    local body=name:find('.Torso',1,true) or name:find('.Hand',1,true) or name:find('.Leg',1,true) or name:find('.Feet',1,true)
                    local mesh=component:GetSkeletalMeshAsset()
                    if (face or body) and valid(mesh) and mesh:GetFullName():find('Coen',1,true) then
                        local count=component:GetNumMaterials()
                        assert(type(count)=='number' and count>=0 and count%1==0 and count<=32,'Unexpected skin material count')
                        for slot=0,count-1 do
                            if body or slot==0 or slot==10 or slot==11 or slot==12 then
                                local original=component:GetMaterial(slot)
                                local key=tostring(component:GetAddress())..':'..slot
                                -- Cooked shader parameters may be absent from VectorParameterValues.
                                -- Probe only scoped Coen slots through a private MID, with readback/rollback.
                                if valid(original) and not seen[key] then
                                    found[#found+1]={component=component,componentId=component:GetAddress(),owner=actor,mesh=mesh,slot=slot,key=key,original=original,baseline=colour(original:K2_GetVectorParameterValue(FName('SkinTint')))}
                                    assert(#found<=64,'Too many skin material targets')
                                    seen[key]=true
                                end
                            end
                        end
                    end
                end
            end
        end
        local worldCount=0
        for _,entry in ipairs(found) do if same(entry.owner,ctx.player) then worldCount=worldCount+1 end end
        assert(worldCount>0,'No player-owned Coen skin material is available')
        return found
    end
    local function checkEntry(entry)
        assert(valid(entry.component) and entry.component:GetAddress()==entry.componentId and same(entry.component:GetOwner(),entry.owner),'Skin component ownership changed')
        assert(same(entry.component:GetSkeletalMeshAsset(),entry.mesh),'Skin mesh changed; restore before retrying')
        assert(valid(entry.original),'Original skin material is unavailable')
        local bound=entry.component:GetMaterial(entry.slot)
        assert(same(bound,entry.mid or entry.original),'Refusing to overwrite a foreign skin material')
    end
    local function restore()
        local failures={}
        for _,entry in ipairs(entries) do
            local ok,failure=pcall(function()
                checkEntry(entry)
                if entry.mid then entry.component:SetMaterial(entry.slot,entry.original) end
                assert(same(entry.component:GetMaterial(entry.slot),entry.original),'Original skin material restoration failed')
                entry.mid=nil
            end)
            if not ok then failures[#failures+1]=tostring(failure) end
        end
        assert(#failures==0,table.concat(failures,' | '))
        entries,context,applied={},nil,nil
        return 'Original skin materials restored.'
    end
    local function apply(text)
        local tint,canonical=parse(text)
        local ctx=current()
        if context then
            assert(same(ctx.player,context.player) and same(ctx.world,context.world) and same(ctx.controller,context.controller) and ctx.form==context.form,'Skin baseline belongs to another session or form; restore first')
        end
        local candidates=discover(ctx)
        local owned={}
        for _,entry in ipairs(entries) do checkEntry(entry);owned[entry.key]=true end
        for _,entry in ipairs(candidates) do if not owned[entry.key] then entries[#entries+1]=entry end end
        context=ctx
        local ok,failure=pcall(function()
            for _,entry in ipairs(entries) do
                checkEntry(entry)
                if not entry.mid then
                    generation=generation+1
                    local created=entry.component:CreateDynamicMaterialInstance(entry.slot,entry.original,FName('DWSkinTint_'..generation))
                    -- Capture a returned instance before further checks so partial creation can restore.
                    if valid(created) then entry.mid=created end
                    assert(valid(created) and created:IsA(MID) and same(created.Parent,entry.original),'Private skin instance creation failed')
                    assert(same(entry.component:GetMaterial(entry.slot),created),'Private skin instance was not bound')
                end
                entry.mid:SetVectorParameterValue(FName('SkinTint'),tint)
                assert(equal(colour(entry.mid:K2_GetVectorParameterValue(FName('SkinTint'))),tint),'Skin tint readback mismatch')
                assert(equal(colour(entry.original:K2_GetVectorParameterValue(FName('SkinTint'))),entry.baseline),'Shared skin material changed')
            end
        end)
        if not ok then
            local restored,restoreFailure=pcall(restore)
            error(tostring(failure)..(restored and '; original materials restored' or '; recovery required: '..tostring(restoreFailure)),0)
        end
        applied=canonical
        return 'Skin tint native readback verified on '..#entries..' owned slots. Check the in-game appearance.'
    end
    return {
        Apply=apply,Restore=restore,IsActive=function()return #entries>0 end,
        Applied=function()return applied or '' end,
        ResetSession=function()
            if context and not valid(context.player) then entries,context,applied={},nil,nil;return end
            restore()
        end,
        RefreshSession=function()
            if not context then return end
            local player=helpers.GetPlayer()
            if not same(player,context.player) or player.Form~=context.form or player:IsInWolfForm() then restore();return end
            local ctx=current()
            if not same(ctx.player,context.player) or not same(ctx.world,context.world) or ctx.form~=context.form then restore();return end
            for _,entry in ipairs(entries) do checkEntry(entry) end
            -- An inventory doll may appear after application; only associated new slots are added.
            local candidates=discover(ctx)
            if #candidates>#entries and applied then apply(applied) end
        end,
    }
end
function M.Init(menu,helpers)
    local control=M.New(helpers)
    local function sync(message)
        menu.Set(SECTION,'tint',control.Applied())
        menu.Set(SECTION,'owned',control.IsActive())
        menu.SetLabel(SECTION,'status',message)
    end
    local function guarded(callback)
        local ok,message=pcall(callback)
        sync(ok and message or 'Skin tint unavailable: '..tostring(message))
        assert(ok,message)
    end
    local function restore() guarded(control.Restore) end
    menu.Register({id=SECTION,title='Skin Color',tab='Visuals',items={
        {id='tint',type='input',label='Skin tint RGB (0-100; 50 is neutral)',value='',onChange=function(text)guarded(function()return control.Apply(text)end)end},
        {id='owned',type='checkbox',label='Skin tint applied',value=false,enabled=false,onChange=function(value)assert(value==false,'Use the skin color controls');restore()end},
        {id='restore',type='button',label='Restore original skin color',onClick=restore},
        {id='status',type='label',label='Choose a skin tint after loading Coen. Original materials are preserved.'},
    }})
    function M.BeforeFormChange() if control.IsActive() then restore() end end
    function M.ResetSession() guarded(function()control.ResetSession();return 'Skin tint reset for the current session.' end) end
    function M.RefreshSession()
        if control.IsActive() then guarded(function()control.RefreshSession();return control.IsActive() and 'Skin tint ownership verified.' or 'Original skin materials restored.' end) end
    end
    return control
end
return M
