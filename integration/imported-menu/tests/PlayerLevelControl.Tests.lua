local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("player_level_tests")
local path = assert(arg[1])
local function fixture()
    local function object(address) return { address=address, IsValid=function() return true end,
        IsA=function() return true end, GetAddress=function(self) return self.address end } end
    local player, world, controller, subsystem, settings, library = object(1),object(2),object(3),object(4),object(5),object(6)
    player.Controller=controller; controller.Pawn=player; player.GetWorld=function() return world end
    local current, writes, confirmation, refuse = 2, 0, nil, false
    settings.LevelCap=7
    subsystem.GetCurrentLevel=function() return current end
    subsystem.GetCurrentLevelXPRequirement=function(_, level) return level*100 end
    subsystem.ForceLevelUpTo=function(_, target, traits) assert(traits); writes=writes+1; if not refuse then current=target end end
    library.GetGameInstanceSubsystem=function() return subsystem end
    local environment=setmetatable({StaticFindObject=function(name)
        if name:find("Default__Subsystem") then return library end
        if name:find("Default__Dogwood") then return settings end
        return object(7)
    end}, {__index=_G})
    local items={}
    local menu={Register=function(section) for _, item in ipairs(section.items) do items[item.id]=item end end,
        Get=function(_, key) return items[key].value end, Set=function(_, key, value) items[key].value=value end,
        SetLabel=function(_, key, value) items[key].label=value end,
        SetOptions=function(_, key, options, selected) items[key].options=options; items[key].value=selected or nil end,
        Confirm=function(spec) confirmation=spec end}
    local module=assert(loadfile(path,"t",environment))(); module.Init(menu,{GetPlayer=function() return player end})
    return {items=items,settings=settings,subsystem=subsystem,world=world,module=module,
        refresh=function() items.refresh.onClick() end,
        apply=function(level) items.target.value=level; items.apply.onClick() end,
        confirm=function() confirmation.onConfirm() end,
        writes=function() return writes end, refuse=function() refuse=true end,
        current=function(value) current=value end}
end
local total=0
local function test(name, callback) local ok,err=pcall(callback); assert(ok,name..": "..tostring(err));total=total+1;print("PASS "..name) end
test("read-only live cap enumerates numeric forward targets",function()
    local f=fixture();f.refresh();assert(f.writes()==0 and f.items.current.value==2 and #f.items.target.options==5)
    assert(f.items.target.options[5].value==7)
end)
test("invalid live cap fails closed",function()
    local f=fixture();f.settings.LevelCap=nil;assert(not pcall(f.refresh));assert(#f.items.target.options==0 and f.writes()==0)
end)
test("invalid experience table fails closed",function()
    local f=fixture();f.subsystem.GetCurrentLevelXPRequirement=function() return nil end
    assert(not pcall(f.refresh));assert(not pcall(f.apply,3) and f.writes()==0)
end)
test("zero experience table and replaced settings are rejected",function()
    local f=fixture();f.subsystem.GetCurrentLevelXPRequirement=function() return 0 end
    assert(not pcall(f.refresh) and f.writes()==0)
    f=fixture();f.refresh();f.apply(4);f.settings.address=999
    assert(not pcall(f.confirm) and f.writes()==0)
end)
test("apply waits for confirmation and exact readback",function()
    local f=fixture();f.refresh();f.apply(5);assert(f.writes()==0);f.confirm();assert(f.writes()==1 and f.items.current.value==5)
end)
test("downward same and above-cap targets never write",function()
    local f=fixture();f.refresh();for _,v in ipairs({1,2,8,3.5}) do assert(not pcall(f.apply,v)) end;assert(f.writes()==0)
end)
test("changed session or level rejects confirmed request",function()
    local f=fixture();f.refresh();f.apply(4);f.module.ResetSession();assert(not pcall(f.confirm) and f.writes()==0)
    f=fixture();f.refresh();f.apply(4);f.current(3);assert(not pcall(f.confirm) and f.writes()==0)
end)
test("setter refusal cannot claim success or retain selectable targets",function()
    local f=fixture();f.refresh();f.apply(5);f.refuse();assert(not pcall(f.confirm));assert(#f.items.target.options==0 and f.items.current.value==nil)
end)
print(total .. " PlayerLevel tests passed")
