local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("fall_drop_diagnostic_tests")
local M = assert(loadfile(assert(arg[1])))()
local function fixture()
    local function object(id) return {IsValid=function()return true end,GetAddress=function()return id end} end
    local p,c,w,h,m=object(1),object(2),object(3),object(4),object(5)
    local state={z=0,health=1,teleports=0,time=0,allowed=true}
    p.Controller=c;c.Pawn=p;p.CombatComponent=h;p.CharacterMovement=m
    p.GetWorld=function()return w end;p.GetRebelCharacterMovement=function()return m end;m.GetOwner=function()return p end
    m.MovementMode=1;m.CustomMovementMode=0
    p.GetActorEnableCollision=function()return true end
    p.K2_GetActorLocation=function()return{X=0,Y=0,Z=state.z}end
    p.K2_GetActorRotation=function()return{pitch=0,Yaw=0,Roll=0}end
    p.K2_TeleportTo=function(_,dest)state.teleports=state.teleports+1;state.z=dest.Z;return not state.reject end
    h.IsAlive=function()return true end;h.GetHealthPercentage=function()return state.health end
    h.SetHealthPercent=function(_,v)state.health=v end
    local pilot=M.New({GetPlayer=function()return p end,allOff=function()return state.allowed end,now=function()return state.time end,
        schedule=function(ms,callback)assert(ms==100);state.callback=callback;return 1 end,
        cancel=function()state.cancelled=true end,onComplete=function(report)state.report=report end})
    state.movement=m;return pilot,state
end
local pilot,state=fixture();assert(state.teleports==0)
local taller,tallerState=fixture();taller.start(400);assert(tallerState.z==400);taller.cancel();assert(tallerState.z==0)
assert(not pcall(pilot.start,199) and state.teleports==0)
pilot.start(200);assert(state.z==200)
state.movement.MovementMode=3;state.callback();state.movement.MovementMode=1;state.health=.9;state.z=0;state.callback()
assert(state.report.airborne and state.report.landed and state.report.restored and state.health==1 and not pilot.owned())
local before=state.teleports;state.callback();assert(state.teleports==before)
pilot,state=fixture();pilot.start(200);pilot.cancel();assert(state.z==0 and state.report.restored)
pilot,state=fixture();state.allowed=false;assert(not pcall(pilot.start,200) and state.teleports==0)
pilot,state=fixture();pilot.start(200);state.time=4;state.callback();assert(state.report.error and state.report.restored)
pilot,state=fixture();pilot.start(200);state.reject=true;pilot.cancel();assert(pilot.owned() and state.report.cleanupError)
state.reject=false;pilot.cancel();assert(not pilot.owned())
print("PASS bounds, no construction writes, natural mode observation, baseline restoration, cancellation, gate, timeout, retained recovery")
