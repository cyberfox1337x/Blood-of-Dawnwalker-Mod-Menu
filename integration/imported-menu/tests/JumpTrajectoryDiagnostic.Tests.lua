local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("jump_trajectory_diagnostic_tests")
local source = assert(arg[1])
local function fixture()
    local queue, now, count, lock, owned, jumps, ticks, result = {}, 0, 0, 0, false, 0, 0, nil
    local allowed, address, health, location = true, 1, 1, { X=0, Y=0, Z=0 }
    local function object(id) return { IsValid=function() return true end, GetAddress=function() return id end } end
    local player, controller, movement, world, combat = object(1), object(2), object(3), object(4), object(5)
    player.GetAddress = function() return address end
    player.Controller, player.CombatComponent, controller.Pawn = controller, combat, player
    player.GetWorld = function() return world end
    player.GetRebelCharacterMovement = function() return movement end
    movement.GetOwner = function() return player end
    movement.MovementMode, movement.CustomMovementMode = 1, 0
    player.IsInWolfForm = function() return false end
    player.GetActorEnableCollision = function() return true end
    player.GetVelocity = function() return { X=0,Y=0,Z=0 } end
    player.CanJump = function() return allowed end
    player.bPressedJump, player.bWasJumping = false, false
    player.JumpCurrentCount, player.JumpKeyHoldTime, player.JumpForceTimeRemaining = 0, 0, 0
    player.K2_GetActorLocation = function() return location end
    player.K2_GetActorRotation = function() return { pitch=0,Yaw=0,Roll=0 } end
    player.K2_TeleportTo = function(_, position) location={ X=position.X,Y=position.Y,Z=position.Z };count=count+1;return true end
    player.Jump = function() jumps=jumps+1;ticks=0;movement.MovementMode=3;count=count+1;player.bPressedJump=true end
    player.StopJumping = function() count=count+1;player.bPressedJump=false end
    combat.GetHealthPercentage = function() return health end
    controller.IsMoveInputIgnored = function() return lock>0 end
    controller.SetIgnoreMoveInput = function(_, value) lock=lock+(value and 1 or -1);count=count+1 end
    local pilot = { inspect=function() end, owned=function() return owned end,
        set=function(value) owned=value end, reset=function() owned=false end, verify=function() assert(owned) end }
    local module = assert(loadfile(source,"t",setmetatable({IsInGameThread=function() return true end},{__index=_G})))()
    local control = module.New({GetPlayer=function() return player end}, pilot, {
        now=function() return now end, isPaused=function() return false end,
        subscribe=function(callback)
            local task={callback=callback,live=true};queue[#queue+1]=task
            return function() task.live=false end
        end })
    local function step(delta)
        now=now+(delta or 30)
        ticks=ticks+1
        if ticks>=3 then location.Z=0;movement.MovementMode=1 else location.Z=owned and 22.5 or 10 end
        local task=table.remove(queue,1)
        if task.live then task.callback();if task.live then queue[#queue+1]=task end end
    end
    return { control=control, run=function() control.run(function(evidence) result=evidence end) end,
        step=step, drain=function() while #queue>0 do step() end end,
        result=function() return result end, mutations=function() return count end, lock=function() return lock end,
        jumps=function() return jumps end, deny=function() allowed=false end, drift=function(value) address=value end,
        hurt=function() health=0.9 end, land=function() movement.MovementMode=1;location.Z=0 end,
        foreignLock=function() lock=lock+1 end }
end
local function test(name, callback) callback(); print("PASS "..name) end
test("physical baseline and modified jump restore all owned state",function()
    local f=fixture();f.run();f.drain()
    assert(f.result().passed and f.result().apexRatio==2.25 and f.jumps()==2 and f.lock()==0 and not f.control.owned())
end)
test("CanJump refusal is read-only",function()
    local f=fixture();f.deny();assert(not pcall(f.run));assert(f.mutations()==0 and not f.control.owned())
end)
test("identity drift retains recovery and does not write replacement",function()
    local f=fixture();f.run();local mutations=f.mutations();f.drift(99);f.step()
    assert(not f.result().passed and f.control.owned() and f.mutations()==mutations)
    f.drift(1);f.land();f.control.reset();assert(not f.control.owned() and f.lock()==0)
end)
test("deadline stops samples and retains airborne position recovery",function()
    local f=fixture();f.run();f.step(4000)
    assert(not f.result().passed and not f.result().restorationVerified and f.control.owned() and f.lock()==0)
    f.land();f.control.reset();assert(not f.control.owned())
end)
test("sparse frames preserve pre-stop flags but reject physical proof",function()
    local f=fixture();f.run();f.step(280)
    local result=f.result()
    assert(not result.passed and result.samples.baseline.initialFrames[1].pressed==true)
    assert(result.samples.baseline.maxIntervalMs==280 and result.failure:find("cadence too sparse",1,true))
    f.land();f.control.reset();f.drain();assert(not f.control.owned())
end)
test("changed health is reported without health writes",function()
    local f=fixture();f.run();f.hurt();f.drain()
    assert(not f.result().passed and f.control.owned() and f.lock()==0)
end)
test("foreign input suppression is never repeatedly decremented",function()
    local f=fixture();f.run();f.foreignLock();f.land();assert(not pcall(f.control.reset))
    assert(f.lock()==1);assert(not pcall(f.control.reset));assert(f.lock()==1)
    f.drain();assert(f.result()==nil)
end)
print("7 jump trajectory diagnostic tests passed")
