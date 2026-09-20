local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("speed_descriptor_readback_tests")
local module = assert(loadfile(assert(arg[1])))()
local function fixture(count)
    local owner={IsValid=function()return true end,GetAddress=function()return 1 end}
    local objects={}
    for index=1,count or 1 do
        local captured=index+10
        local outer={IsValid=function()return true end,GetAddress=function()return 2 end}
        local class={IsValid=function()return true end,GetAddress=function()return captured+100 end,GetFullName=function()return "Class /Game/Speed"end}
        local object={IsValid=function()return true end,GetAddress=function()return captured end,
            IsA=function(_,path)return path=="/Script/GameplayAbilities.GameplayEffect"end,
            GetFullName=function()return "Effect /Game/Speed.Default__Speed"end,
            GetOuter=function()return outer end,GetClass=function()return class end,
            Modifiers={{Attribute={AttributeName="MaxSpeedModifier",AttributeOwner=owner,GetStructAddress=function()return 100 end}}}}
        class.GetCDO=function()return object end
        objects[index]=object
    end
    return {findObject=function(path)if path=="/Script/DogwoodStats.PlayerMovementAttributeSet" then return owner end end,
        findObjects=function(limit,class,short,required,banned,exact)
            assert(limit==512 and class=="GameplayEffect" and short==nil and required==nil and banned==nil and exact==false)
            return objects
        end},objects
end
local count=0
local function test(name,callback)local ok,err=pcall(callback);assert(ok,name..": "..tostring(err));count=count+1;print("PASS "..name)end
test("exact bounded class CDO descriptor scan",function()
    local deps=fixture();local result=module.Read(deps)
    assert(result:find("matches=1",1,true) and result:find("attribute=MaxSpeedModifier",1,true))
end)
test("wrong attribute owner and unrelated names omitted",function()
    local deps,objects=fixture(2)
    objects[1].Modifiers[1].Attribute.AttributeName="Health"
    objects[2].Modifiers[1].Attribute.AttributeOwner={IsValid=function()return true end,GetAddress=function()return 9 end}
    assert(module.Read(deps):find("matches=0",1,true))
end)
test("modifier bound reports skip without unbounded iteration",function()
    local deps,objects=fixture()
    local original=objects[1].Modifiers[1]
    for index=2,17 do objects[1].Modifiers[index]=original end
    assert(module.Read(deps):find("skipped=1",1,true))
end)
test("ForEach modifier ABI supported",function()
    local deps,objects=fixture();local entry=objects[1].Modifiers[1]
    objects[1].Modifiers={ForEach=function(_,callback)callback(0,{get=function()return entry end})end}
    assert(module.Read(deps):find("matches=1",1,true))
end)
test("output capped and reported",function()
    local deps=fixture(70);local result=module.Read(deps)
    assert(result:find("matches=70",1,true) and result:find("output_capped=true",1,true))
    local _,lines=result:gsub("\n","");assert(lines==64)
end)
test("native finder violating bound is rejected",function()
    local deps=fixture(513);assert(not pcall(module.Read,deps))
end)
test("exact historical SpedBoost candidate avoids prefix scan",function()
    local deps,objects=fixture();local original=deps.findObject
    local path="/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_SpedBoost_Lvl3"
    deps.findObject=function(value)
        if value==path..".GE_WolfBoost_SpedBoost_Lvl3_C" then return objects[1]:GetClass() end
        if value==path..".Default__GE_WolfBoost_SpedBoost_Lvl3_C" then return objects[1] end
        return original(value)
    end
    deps.findObjects=function()error("Fallback must not run for loaded exact candidate")end
    local result=module.Read(deps)
    assert(result:find("fallback=false",1,true) and result:find("candidate_missing=2",1,true) and result:find("matches=1",1,true))
end)
test("missing exact candidates preserve bounded fallback summary",function()
    local deps=fixture();local result=module.Read(deps)
    assert(result:find("candidate_missing=3",1,true) and result:find("fallback=true",1,true))
end)
print(count.." speed descriptor readback tests passed")
