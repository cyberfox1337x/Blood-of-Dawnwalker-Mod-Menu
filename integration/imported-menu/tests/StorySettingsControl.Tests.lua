local cyberfox1337x={signature=function(name)return name end}
cyberfox1337x.signature("story_settings_tests")
local path=assert(arg[1])
local function fixture()
    local function object(address,name)return {address=address,IsValid=function()return true end,IsA=function()return true end,GetAddress=function(self)return self.address end,GetFullName=function()return name or "Object" end}end
    local player,world,controller=object(1),object(2),object(3)
    local contextCalls=0
    player.Controller=controller;controller.Pawn=player;player.GetWorld=function()contextCalls=contextCalls+1;return world end
    local settings,system,trait=object(4),object(5),object(6,"TraitAsset /Game/Trait")
    settings.DaysToPass=31;system.GetCurrentDay=function()return 0 end;system.GetMainGoalDay=function()return 31 end
    local costs={2,5};local reject
    trait.Levels={}
    for index=1,2 do trait.Levels[index]=setmetatable({}, {__index=function(_,key)if key=="TimeCost" then return costs[index] end end,
        __newindex=function(_,key,value)assert(key=="TimeCost");if not reject or not reject(index,value) then costs[index]=value end end}) end
    local items={}
    local menu={Register=function(section)for _,item in ipairs(section.items)do items[item.id]=item;item.value=item.default end end,
        Set=function(_,key,value)items[key].value=value end,SetLabel=function(_,key,value)items[key].label=value end}
    local scans=0
    local environment=setmetatable({StaticFindObject=function()return settings end,FindFirstOf=function()return system end,
        FindAllOf=function()scans=scans+1;return {trait}end},{__index=_G})
    local module=assert(loadfile(path,"t",environment))();module.Init(menu,{GetPlayer=function()return player end})
    return {items=items,costs=costs,trait=trait,settings=settings,system=system,module=module,world=world,
        toggle=function(value)items.traits.onChange(value)end,read=function()items.refresh.onClick()end,
        days=function(enabled)items.daysEnabled.onChange(enabled)end,reject=function(callback)reject=callback end,scans=function()return scans end,contextCalls=function()return contextCalls end}
end
local total=0
local function test(name,callback)local ok,err=pcall(callback);assert(ok,name..": "..tostring(err));total=total+1;print("PASS "..name)end
test("initialization performs no scan and explicit read never mutates",function()
    local f=fixture();assert(f.scans()==0);f.read();assert(f.scans()==1 and f.costs[1]==2 and f.settings.DaysToPass==31)
end)
test("traits zero exact rank costs and restore original values",function()
    local f=fixture();f.toggle(true);assert(f.costs[1]==0 and f.costs[2]==0 and f.items.traits.value)
    f.toggle(false);assert(f.costs[1]==2 and f.costs[2]==5 and not f.items.traits.value)
end)
test("batch validation does not resolve player context for every rank",function()
    local f=fixture();f.toggle(true);assert(f.contextCalls()<=4)
end)
test("repeated enable does not rescan or replace baseline",function()
    local f=fixture();f.toggle(true);f.toggle(true);assert(f.scans()==1);f.toggle(false);assert(f.costs[1]==2)
end)
test("partial write failure restores prior rank and clears confirmed ON",function()
    local f=fixture();f.reject(function(index,value)return index==2 and value==0 end)
    assert(not pcall(f.toggle,true));assert(f.costs[1]==2 and f.costs[2]==5 and not f.items.traits.value)
end)
test("failed restoration remains owned and prevents reset until resolved",function()
    local f=fixture();f.toggle(true);f.reject(function(_,value)return value>0 end)
    assert(not pcall(f.toggle,false) and f.items.traits.value and not pcall(f.module.ResetSession))
    f.reject(nil);f.toggle(false);f.module.ResetSession();assert(f.costs[1]==2)
end)
test("external changes are preserved rather than overwritten",function()
    local f=fixture();f.toggle(true);f.costs[1]=9;f.toggle(false);assert(f.costs[1]==9 and f.costs[2]==5)
end)
test("invalid trait values fail before any writes",function()
    local f=fixture();f.costs[2]=-1;assert(not pcall(f.toggle,true));assert(f.costs[1]==2 and not f.items.traits.value)
end)
test("90-day live toggle retains verified deadline and restores baseline",function()
    local f=fixture();f.system.GetMainGoalDay=function()return f.settings.DaysToPass end
    f.days(true);assert(f.settings.DaysToPass==91 and f.items.daysEnabled.value)
    f.days(false);assert(f.settings.DaysToPass==31 and not f.items.dayOwned.value and not f.items.daysEnabled.value)
end)
test("cached active deadline refuses enabled state and restores settings",function()
    local f=fixture();assert(not pcall(f.days,true));assert(f.settings.DaysToPass==31 and not f.items.daysEnabled.value)
end)
test("unexpected persistent active deadline retains recovery",function()
    local f=fixture();local changed=false
    f.system.GetMainGoalDay=function()if f.settings.DaysToPass==91 then changed=true end;return changed and 91 or 31 end
    f.days(true);assert(not pcall(f.days,false));assert(f.items.dayOwned.value and not pcall(f.module.ResetSession))
end)
print(total.." StorySettings tests passed")
