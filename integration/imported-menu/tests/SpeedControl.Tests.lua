local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("speed_pending_control_tests")
local function fixture()
    local items, values, calls, timers = {}, {}, {}, {}
    local owned, failActivation, failRestore, real, game, paused = false, false, false, 0, 0, false
    local nextId, address, lag = 0, 1, 0
    local applicable, blocker = true, "movement is airborne, flying or otherwise not normal walking"
    local pilot = {
        owned = function() return owned end,
        applicable = function() return applicable, blocker end,
        inspect = function() calls[#calls+1]="inspect" end,
        begin = function(factor) calls[#calls+1]="begin:"..factor;owned=true end,
        verify = function() calls[#calls+1]="verify";if failActivation or lag>0 then lag=lag-1;error("profile pending") end end,
        beginRestore = function() calls[#calls+1]="pop" end,
        reset = function() calls[#calls+1]="reset";assert(not failRestore,"restore pending");owned=false end,
    }
    local function object(id) return {IsValid=function()return true end,GetAddress=function()return id end} end
    local player, world, controller = object(1),object(2),object(3)
    player.GetAddress=function()return address end
    player.GetWorld=function()return world end;player.Controller=controller;controller.Pawn=player
    local library=object(4)
    library.IsGamePaused=function()return paused end
    library.GetTimeSeconds=function()return game end
    library.GetRealTimeSeconds=function()return real end
    local env=setmetatable({
        require=function(name)assert(name=="SpeedProfilePilot");return{New=function()return pilot end}end,
        ExecuteInGameThread=function(callback)callback()end,
        ExecuteWithDelay=function()error("Finite task must not keep request open")end,
        StaticFindObject=function()return library end,
        LoopInGameThreadWithDelay=function(ms,callback)assert(ms==250);nextId=nextId+1;timers[nextId]=callback;return nextId end,
        CancelDelayedAction=function(id)calls[#calls+1]="cancel";timers[id]=nil end,
    },{__index=_G})
    local module=assert(loadfile("integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts/SpeedControl.lua","t",env))()
    module.Init({Register=function(section)for _,item in ipairs(section.items)do items[item.id]=item end end,
        Set=function(_,key,value)values[key]=value end,SetLabel=function(_,key,value)values[key]=value end},
        {GetPlayer=function()return player end})
    return {module=module,values=values,calls=calls,timers=timers,
        select=function(factor)items.multiplier.onChange(factor)end,
        applicable=function(value,reason)applicable=value;if reason then blocker=reason end end,
        tick=function(seconds)
            real=real+(seconds or .25);if not paused then game=game+(seconds or .25)end
            local callbacks={};for _,callback in pairs(timers)do callbacks[#callbacks+1]=callback end
            for _,callback in ipairs(callbacks)do callback()end
        end,
        paused=function(value)paused=value end,fail=function(a,r)failActivation,failRestore=a,r end,
        lag=function(value)lag=value end,drift=function()address=9 end,
        active=function()local count=0;for _ in pairs(timers)do count=count+1 end;return count end}
end
local function test(name,run)run();print("PASS "..name)end
local function count(calls,match)local total=0;for _,call in ipairs(calls)do if call==match then total=total+1 end end;return total end
test("pending is distinct from confirmed and uses only active recurring work",function()
    local f=fixture();assert(f.active()==0 and #f.calls==0);f.select(2)
    assert(f.values.multiplier==2 and f.values.requested=="2x requested; 1x confirmed" and f.active()==1)
    assert(f.values.status:find("Pending 2x",1,true) and not f.values.status:find("game=",1,true))
    f.tick();assert(f.values.multiplier==2 and f.values.requested=="2x requested; 2x confirmed" and f.active()==0);f.select(1)
    assert(f.values.multiplier==1 and not f.values.owned and f.active()==0)
end)
test("paused time does not consume game-time failure budget",function()
    local f=fixture();f.paused(true);f.fail(true,false);f.select(2)
    for _=1,20 do f.tick()end
    assert(f.values.owned and f.values.multiplier==2 and f.values.status:find("Press Resume in the game and 2x speed applies",1,true),f.values.status)
    assert(f.values.timing:find("paused=true",1,true));f.paused(false);f.fail(false,false);f.tick()
    assert(f.values.multiplier==2 and f.active()==0)
end)
test("six advancing failures restore and cancel timer",function()
    local f=fixture();f.fail(true,false);f.select(2);for _=1,6 do f.tick()end
    assert(not f.values.owned and f.active()==0 and f.values.status:find("original movement profile restored",1,true))
end)
test("expired pending request pops once then retains stale-cache recovery",function()
    local f=fixture();f.fail(true,true);f.select(2);for _=1,240 do f.tick(0)end
    assert(f.active()==0 and f.values.owned and f.values.status:find("recovery required",1,true))
    assert(count(f.calls,"pop")==1);f.fail(false,false);f.select(1);assert(not f.values.owned)
end)
test("OFF invalidates late recurring callbacks before native work",function()
    local f=fixture();f.select(2);local callback=select(2,next(f.timers));f.select(1)
    local before=#f.calls;callback();assert(#f.calls==before and f.values.multiplier==1 and f.active()==0)
end)
test("factor changes restore old ownership before new push",function()
    local f=fixture();f.select(2);f.select(3);f.tick();assert(f.values.multiplier==3)
    local pop,begin;for index,call in ipairs(f.calls)do if call=="pop"then pop=index elseif call=="begin:3"then begin=index end end
    assert(pop and begin and pop<begin and count(f.calls,"begin:2")==1)
end)
test("stale restoration waits while paused then continues requested factor",function()
    local f=fixture();f.select(2);f.tick();f.fail(false,true);f.paused(true);f.select(3)
    for _=1,8 do f.tick()end
    assert(f.values.multiplier==3 and f.values.requested=="3x requested; 2x confirmed" and count(f.calls,"begin:3")==0 and f.active()==1)
    f.fail(false,false);f.paused(false);f.tick();f.tick();assert(f.values.multiplier==3 and f.values.requested=="3x requested; 3x confirmed" and f.active()==0)
end)
test("cleanup cancels timer before touching pilot and retains failures",function()
    local f=fixture();f.select(2);local before=#f.calls;f.fail(false,true)
    assert(not pcall(f.module.ResetSession));assert(f.calls[before+1]=="cancel" and f.active()==0 and f.values.owned)
end)
test("identity mismatch stops pending work",function()
    local f=fixture();f.select(2);f.drift();f.tick();assert(f.active()==0 and f.values.multiplier==1)
end)
test("restore and replacement share one gameplay budget",function()
    local f=fixture();f.select(2);f.tick();f.fail(false,true);f.select(3)
    for _=1,180 do f.tick(0)end -- stalled clock: no failures, 180 unpaused ticks spent
    f.fail(true,false);f.tick(0)
    assert(count(f.calls,"begin:3")==1 and f.active()==1)
    for _=1,60 do f.tick(0)end
    assert(f.active()==0 and not f.values.owned and f.values.multiplier==1,f.values.status)
end)
test("callback count bounds a stalled native real clock",function()
    local f=fixture();f.fail(true,false);f.select(2)
    for _=1,240 do f.tick(0)end
    assert(f.active()==0 and not f.values.owned)
end)
test("a paused request outlives the gameplay budget and applies on resume",function()
    -- The game pauses itself while the menu has focus; the player may take minutes to
    -- come back and press Resume. That time must not cancel the request.
    local f=fixture();f.paused(true);f.fail(true,false);f.select(2)
    f.tick(120);f.tick(120)
    assert(f.active()==1 and f.values.owned and f.values.multiplier==2,f.values.status)
    assert(f.values.status:find("The game is paused",1,true) and f.values.status:find("Press Resume",1,true),f.values.status)
    f.paused(false);f.fail(false,false);f.tick()
    assert(f.values.multiplier==2 and f.values.requested=="2x requested; 2x confirmed" and f.active()==0)
end)
test("a request left paused for fifteen minutes is expired without a speed claim",function()
    local f=fixture();f.paused(true);f.fail(true,false);f.select(2)
    for _=1,4 do f.tick(240)end
    assert(f.active()==0 and not f.values.owned and f.values.multiplier==1)
    assert(f.values.status:find("stayed paused for 15 minutes",1,true) and f.values.status:find("original movement profile restored",1,true),f.values.status)
end)
test("a paused waiting request also tells the player to resume",function()
    local f=fixture();f.applicable(false);f.paused(true);f.select(2);f.tick()
    assert(f.values.status:find("Press Resume",1,true) and f.values.multiplier==2 and not f.values.owned,f.values.status)
    f.select(1);assert(f.active()==0 and f.values.multiplier==1)
end)
test("invalid inputs never push",function()
    local f=fixture();for _,value in ipairs({0,4,1.2,"2"})do assert(not pcall(f.select,value))end
    assert(#f.calls==0 and f.active()==0)
end)
test("airborne request waits for grounded movement instead of failing",function()
    local f=fixture();f.applicable(false);f.select(2)
    assert(f.values.status:find("Waiting because movement is airborne",1,true),f.values.status)
    assert(f.values.multiplier==2 and f.values.requested=="2x requested; 1x confirmed" and f.active()==1)
    for _=1,8 do f.tick()end
    assert(f.values.multiplier==2 and f.active()==1 and count(f.calls,"begin:2")==0 and not f.values.owned)
    assert(f.values.status:find("seconds of gameplay remain",1,true))
    f.applicable(true);f.tick()
    assert(count(f.calls,"begin:2")==1 and f.active()==1)
    f.tick();assert(f.values.multiplier==2 and f.active()==0)
end)
test("waiting request is cancelled by 1x before anything is applied",function()
    local f=fixture();f.applicable(false);f.select(2);f.tick()
    f.select(1)
    assert(f.values.multiplier==1 and f.active()==0 and not f.values.owned)
    assert(f.values.status:find("original movement profile restored",1,true))
end)
test("waiting request expires without claiming a speed change",function()
    local f=fixture();f.applicable(false);f.select(2);f.tick(60)
    assert(f.active()==0 and f.values.multiplier==1 and not f.values.owned)
    assert(f.values.status:find("no speed change was applied",1,true),f.values.status)
end)
print("18 speed pending control tests passed")
