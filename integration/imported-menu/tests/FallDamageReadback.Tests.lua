local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("fall_damage_readback_tests")
local module=assert(loadfile(assert(arg[1])))()
local function fixture()
    local function object(address)
        return {IsValid=function()return true end,GetAddress=function()return address end,
            IsA=function()return true end,GetFullName=function()return "Object /Test/"..address end}
    end
    local player,world,controller,component,config,class,effect=object(1),object(2),object(3),object(4),object(5),object(6),object(7)
    player.Controller,controller.Pawn,player.FallDamageComponent=controller,player,component
    player.GetWorld=function()return world end
    component.GetOwner=function()return player end
    component.FallDamageConfig,config.DamageEffect= config,class
    class.GetCDO=function()return effect end
    component.IsActive=function()return false end
    component.IsComponentTickEnabled=function()return false end
    effect.DurationPolicy,effect.Executions,effect.Modifiers=0,{},{}
    effect.ApplicationTagRequirements={RequireTags={GameplayTags={}},IgnoreTags={GameplayTags={{TagName="Immunity.Test"}}}}
    return {GetPlayer=function()return player end},player,component,effect
end
local count=0
local function test(name,callback)local ok,err=pcall(callback);assert(ok,name..": "..tostring(err));count=count+1;print("PASS "..name)end
test("explicit read preserves inactive state and exact effect requirements",function()
    local helpers=fixture();local result=module.Read(helpers)
    assert(result:find("component_active=false",1,true) and result:find("application_IgnoreTags=Immunity.Test",1,true))
end)
test("foreign component rejected",function()
    local helpers,_,component=fixture();component.GetOwner=function()return component end
    assert(not pcall(module.Read,helpers))
end)
test("bounded arrays report unavailable rather than walking arbitrary entries",function()
    local helpers,_,_,effect=fixture()
    for index=1,17 do effect.ApplicationTagRequirements.IgnoreTags.GameplayTags[index]={TagName="Tag"} end
    assert(module.Read(helpers):find("application_IgnoreTags=UNAVAILABLE",1,true))
end)
test("effect replacement during read rejected",function()
    local helpers,player,component=fixture()
    component.IsActive=function()player.FallDamageComponent=player;return false end
    assert(not pcall(module.Read,helpers))
end)
test("execution class read through ForEach ABI",function()
    local helpers,_,_,effect=fixture()
    effect.Executions={ForEach=function(_,callback)callback(0,{get=function()return {CalculationClass={GetFullName=function()return "Class /Test/Damage"end}}end})end}
    assert(module.Read(helpers):find("executions=Class /Test/Damage",1,true))
end)
print(count.." fall damage readback tests passed")
