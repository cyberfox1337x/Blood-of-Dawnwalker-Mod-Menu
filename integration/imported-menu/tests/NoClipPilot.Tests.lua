local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("no_clip_pilot_tests")
local module = assert(loadfile(assert(arg[1])))()
local function fixture()
    local function object(address)
        return { IsValid = function() return true end, GetAddress = function() return address end }
    end
    local player, world, controller, movement = object(1), object(2), object(3), object(4)
    local position, calls, reject = {X=10,Y=20,Z=30}, {}, {}
    local collision = true
    player.Controller, controller.Pawn, player.CharacterMovement = controller, player, movement
    player.GetWorld = function() return world end
    player.GetRebelCharacterMovement = function() return movement end
    movement.GetOwner = function() return player end
    movement.MovementMode, movement.CustomMovementMode = 1, 0
    player.K2_GetActorLocation = function() return position end
    player.K2_GetActorRotation = function() return {pitch=0,Yaw=90,Roll=0} end
    player.K2_TeleportTo = function(_, destination)
        calls[#calls+1] = "return"
        if reject.teleport then return false end
        position = {X=destination.X,Y=destination.Y,Z=destination.Z}; return true
    end
    player.GetActorEnableCollision = function() return collision end
    player.SetActorEnableCollision = function(_, value)
        calls[#calls+1] = "collision:" .. tostring(value)
        if reject.collision and reject.collision(value) then return end
        collision = value
    end
    movement.SetMovementMode = function(_, mode, custom)
        calls[#calls+1] = "mode:" .. mode
        if reject.mode and reject.mode(mode) then return end
        movement.MovementMode, movement.CustomMovementMode = mode, custom
    end
    return { pilot = module.New({GetPlayer=function() return player end}), player=player,
        movement=movement, calls=calls, reject=reject, position=function() return position end,
        move=function() position={X=999,Y=999,Z=999} end, collision=function() return collision end }
end
local count = 0
local function test(name, callback)
    local ok, failure = pcall(callback); assert(ok, name .. ": " .. tostring(failure))
    count = count + 1; print("PASS " .. name)
end
test("ON/OFF restores origin before movement and collision", function()
    local f=fixture(); f.pilot.set(true); assert(f.pilot.owned() and f.movement.MovementMode==0 and not f.collision())
    f.move(); f.pilot.set(false)
    assert(f.position().X==10 and f.movement.MovementMode==1 and f.collision() and not f.pilot.owned())
    assert(table.concat(f.calls,",")=="mode:0,collision:false,return,mode:1,collision:true")
end)
test("idempotent requests do not duplicate native mutations", function()
    local f=fixture(); f.pilot.set(true); f.pilot.set(true); assert(#f.calls==2)
    f.pilot.set(false); f.pilot.set(false); assert(#f.calls==5)
end)
test("airborne activation rejected without mutation", function()
    local f=fixture(); f.movement.MovementMode=3
    assert(not pcall(f.pilot.set,true) and #f.calls==0 and not f.pilot.owned())
end)
test("a refusal that restored cleanly can be retried, not disabled for the session", function()
    -- A recoverable refusal used to latch the same flag as an unrecovered world, so one
    -- bad moment left the control stuck on "Prior No Clip failure requires restarting
    -- and reloading" until the game was restarted.
    local f=fixture(); f.movement.MovementMode=3
    assert(not pcall(f.pilot.set,true), "airborne activation must still be refused")
    assert(f.movement.MovementMode==3 and #f.calls==0, "a refusal must not mutate the world")
    f.movement.MovementMode=1
    f.pilot.set(true)
    assert(f.pilot.owned(), "the control must work again once the refusal no longer applies")
    f.pilot.set(false)
    assert(not f.pilot.owned() and f.collision())
end)
test("failed collision activation rolls back movement", function()
    local f=fixture(); f.reject.collision=function(value) return value==false end
    assert(not pcall(f.pilot.set,true)); assert(f.collision() and f.movement.MovementMode==1 and not f.pilot.owned())
end)
test("failed return retains ownership and leaves collision disabled", function()
    local f=fixture(); f.pilot.set(true); f.move(); f.reject.teleport=true
    assert(not pcall(f.pilot.set,false) and f.pilot.owned() and not f.collision())
    assert(not pcall(f.pilot.reset)); f.reject.teleport=false; f.pilot.set(false)
    assert(not f.pilot.owned() and f.collision() and f.position().X==10)
end)
test("failed collision restoration retains retry ownership", function()
    local f=fixture(); f.pilot.set(true); f.reject.collision=function(value) return value==true end
    assert(not pcall(f.pilot.set,false) and f.pilot.owned()); f.reject.collision=nil
    f.pilot.set(false); assert(f.collision() and not f.pilot.owned())
end)
test("identity replacement refuses mutation of replacement player", function()
    local f=fixture(); f.pilot.set(true); f.player.GetAddress=function() return 22 end
    local before=#f.calls
    assert(not pcall(f.pilot.set,false) and f.pilot.owned() and #f.calls==before)
end)
test("invalid toggle rejected", function()
    local f=fixture(); assert(not pcall(f.pilot.set,"true") and #f.calls==0)
end)
test("active state drift detected and can restore original movement", function()
    local f=fixture(); f.pilot.set(true); f.movement.MovementMode=3
    assert(not pcall(f.pilot.verify)); f.pilot.set(false)
    assert(f.movement.MovementMode==1 and f.collision() and not f.pilot.owned())
end)
test("failed movement restoration retains collision disabled and retry record", function()
    local f=fixture(); f.pilot.set(true); f.reject.mode=function(mode) return mode==1 end
    assert(not pcall(f.pilot.set,false) and f.pilot.owned() and not f.collision())
    f.reject.mode=nil; f.pilot.set(false); assert(not f.pilot.owned() and f.collision())
end)
test("registered control starts disabled and automatic inspection gates activation without a manual button", function()
    local f=fixture()
    local fields, states = {}, {}
    local flyEnabled = false
    local registered = assert(loadfile(assert(arg[1]), "t", setmetatable({ ExecuteInGameThread=function(callback) callback() end }, {__index=_G})))()
    registered.Init({Register=function(section) for _, field in ipairs(section.items) do fields[field.id]=field end end,
        Set=function(_, id, value) states[id]=value end, SetLabel=function() end,
        Get=function(section) assert(section == "DWPersonalFly"); return flyEnabled end}, {GetPlayer=function() return f.player end})
    assert(fields.enabled.enabled==false)
    assert(fields.refresh == nil, "manual No Clip verify button must not be published")
    assert(registered.NeedsSessionReady() == true)
    f.movement.MovementMode = 3
    assert(not pcall(registered.SessionReady) and registered.NeedsSessionReady() == true)
    f.movement.MovementMode = 1
    registered.SessionReady(); assert(fields.enabled.enabled==true)
    assert(registered.NeedsSessionReady() == false)
    flyEnabled = true
    states.enabled = true
    assert(not pcall(fields.enabled.onChange, true) and states.enabled == false, "Fly conflict must restore the requested No Clip checkbox")
    flyEnabled = false
    fields.enabled.onChange(true); assert(states.enabled==true)
    fields.enabled.onChange(false); assert(states.enabled==false)
    registered.ResetSession(); assert(fields.enabled.enabled==false)
end)
print(count .. " No Clip pilot tests passed")

