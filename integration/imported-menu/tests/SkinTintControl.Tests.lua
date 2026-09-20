local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature('skin_tint_tests')
local source = assert(arg[1])
local function fixture()
    local sequence, writes = 0, 0
    local function object(class, name)
        sequence = sequence + 1
        local value = { address = sequence, class = class, name = name, valid = true }
        function value:IsValid() return self.valid end
        function value:GetAddress() return self.address end
        function value:IsA(expected) return self.class == expected end
        function value:GetFullName() return self.name end
        return value
    end
    local materialClass = '/Script/Engine.MaterialInstanceConstant'
    local midClass = '/Script/Engine.MaterialInstanceDynamic'
    local function material(name)
        local m = object(materialClass, name)
        m.color = {R=1,G=1,B=1,A=1}
        m.VectorParameterValues = {{ParameterInfo={Name={ToString=function() return 'SkinTint' end}}}}
        function m:K2_GetVectorParameterValue() return self.color end
        function m:SetVectorParameterValue(_, color)
            writes = writes + 1
            if self.fail then error('injected write failure') end
            self.color = self.refuse and {R=0,G=0,B=0,A=1} or color
        end
        return m
    end
    local world = object('/Script/Engine.World','world')
    local player = object('/Script/Dawnwalker.DawnwalkerPlayerCharacter','player')
    player.Form = 0
    function player:GetWorld() return world end
    function player:IsInWolfForm() return false end
    player.Controller = object('controller','controller'); player.Controller.Pawn = player
    local inventory = object('inventory','inventory')
    function inventory:GetOwner() return player end
    local function actor(name, owner)
        local a = object('/Game/_Dawnwalker/UI/_Unified/GameHub/Inventory/Doll/BP_RenderDoll2.BP_RenderDoll2_C',name)
        a.TargetInventory = owner or inventory
        function a:GetWorld() return world end
        return a
    end
    local function component(owner, name)
        local c = object('/Script/Engine.SkeletalMeshComponent',name)
        c.original = material('Coen skin'); c.bound = c.original
        function c:GetOwner() return owner end
        c.mesh = object('mesh','SkeletalMesh /Game/Coen_Head')
        function c:GetSkeletalMeshAsset() return self.mesh end
        function c:GetNumMaterials() return 1 end
        function c:GetMaterial() return self.bound end
        function c:SetMaterial(_, value) self.bound = value end
        function c:CreateDynamicMaterialInstance(_, original)
            local mid = material('private'); mid.class = midClass; mid.Parent = original
            mid.fail = self.fail; mid.refuse = self.refuse; self.bound = mid; return mid
        end
        return c
    end
    local head = component(player,'player.Head'); player.components={head}
    function player:K2_GetComponentsByClass() return self.components end
    local doll = actor('doll'); doll.components={component(doll,'doll.Head')}
    function doll:K2_GetComponentsByClass() return self.components end
    local dolls = {}
    local env=setmetatable({FName=function(v)return v end,StaticFindObject=function()return object('class','class')end,
        FindAllOf=function()return dolls end,ExecuteInGameThread=function(fn)fn()end},{__index=_G})
    local module=assert(loadfile(source,'t',env))()
    local control=module.New({GetPlayer=function()return player end})
    return {module=module,control=control,player=player,head=head,doll=doll,dolls=dolls,material=material,
        writes=function()return writes end,component=component,actor=actor}
end
local count=0
local function test(name, callback) callback();count=count+1;print('PASS '..name) end
local function fails(fn) assert(not pcall(fn),'expected refusal') end

test('neutral maps to one, bounded channels and exact restoration',function()
    local f=fixture(); f.control.Apply('50,50,50'); assert(f.head.bound.color.R==1 and f.control.IsActive())
    f.control.Apply('0,100,25'); assert(f.head.bound.color.R==0 and f.head.bound.color.G==2 and f.head.bound.color.B==.5)
    assert(f.head.original.color.R==1); f.control.Restore(); assert(f.head.bound==f.head.original and not f.control.IsActive())
end)
test('reject malformed and out of range tuples before writes',function()
    local f=fixture()
    for _,v in ipairs({'-1,50,50','101,50,50','1.5,50,50','nan,50,50','50,50','50,50,50,50'})do fails(function()f.control.Apply(v)end)end
    assert(f.writes()==0)
end)
test('foreign material cannot be overwritten',function()
    local f=fixture();f.control.Apply('60,50,50');local foreign=f.material('foreign');f.head.bound=foreign
    fails(function()f.control.Apply('70,50,50')end);assert(f.head.bound==foreign)
    fails(f.control.Restore);assert(f.head.bound==foreign and f.control.IsActive())
end)
test('failed second slot rolls all private bindings back',function()
    local f=fixture(); local body=f.component(f.player,'player.Torso');body.fail=true;f.player.components[2]=body
    fails(function()f.control.Apply('60,50,50')end)
    assert(f.head.bound==f.head.original and body.bound==body.original and not f.control.IsActive())
end)
test('readback mismatch refuses and restores',function()
    local f=fixture();f.head.refuse=true;fails(function()f.control.Apply('60,50,50')end);assert(f.head.bound==f.head.original)
end)
test('only player associated render doll is touched',function()
    local f=fixture();f.dolls[1]=f.doll;local foreign=f.actor('foreign',{IsValid=function()return true end,GetOwner=function()return nil end})
    foreign.components={f.component(foreign,'foreign.Head')};f.dolls[2]=foreign
    f.control.Apply('60,50,50');assert(f.doll.components[1].bound~=f.doll.components[1].original)
    assert(foreign.components[1].bound==foreign.components[1].original);f.control.Restore()
end)
test('hidden functional parameter succeeds without declaration enumeration',function()
    local f=fixture();f.head.original.VectorParameterValues=nil
    f.control.Apply('60,50,50')
    assert(f.head.bound~=f.head.original and f.head.bound.color.R==1.2 and f.head.original.color.R==1)
    f.control.Restore();assert(f.head.bound==f.head.original)
end)
test('hidden nonfunctional parameter fails readback and rolls back',function()
    local f=fixture();f.head.original.VectorParameterValues=nil;f.head.refuse=true
    fails(function()f.control.Apply('60,50,50')end)
    assert(f.writes()>0 and f.head.bound==f.head.original and not f.control.IsActive())
end)
test('changed possession refuses before writes',function()
    local f=fixture();f.player.Controller.Pawn=nil;fails(function()f.control.Apply('60,50,50')end)
    assert(f.writes()==0)
end)
test('form cleanup restores and new session does not auto enable',function()
    local f=fixture();f.control.Apply('60,50,50');f.control.ResetSession();assert(f.head.bound==f.head.original and not f.control.IsActive())
end)
test('inventory appearance refresh only runs for an explicitly active override',function()
    local f=fixture();f.control.RefreshSession();assert(f.writes()==0)
    f.control.Apply('60,50,50');f.dolls[1]=f.doll;f.control.RefreshSession()
    assert(f.doll.components[1].bound.color.R==1.2 and f.doll.components[1].bound~=f.doll.components[1].original)
    f.player.Form=1;f.control.RefreshSession();assert(not f.control.IsActive() and f.head.bound==f.head.original)
end)
test('UI publishes tuple and read only ownership, close handler restores',function()
    local f=fixture();local items,values={},{}
    f.module.Init({Register=function(s)assert(s.id=='DWSkinTint');for _,i in ipairs(s.items)do items[i.id]=i end end,
        Set=function(_,id,v)values[id]=v end,SetLabel=function()end},{GetPlayer=function()return f.player end})
    assert(items.owned.enabled==false and items.tint.value=='')
    items.tint.onChange('60,50,50');assert(values.owned==true and values.tint=='60,50,50')
    items.owned.onChange(false);assert(values.owned==false and f.head.bound==f.head.original)
end)
print(count..' Skin Tint tests passed')
