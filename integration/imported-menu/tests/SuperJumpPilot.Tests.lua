local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("super_jump_pilot_tests")
local module = assert(loadfile(assert(arg[1])))()
local function fixture()
    local context, calls, faults = {validated=true}, {}, {}
    local address=0
    for _, name in ipairs({"player","world","controller","asc","attributes","movement","library","effectClass"}) do
        address=address+1; local captured=address
        context[name]={IsValid=function() return true end,GetAddress=function() return captured end}
    end
    context.descriptor={GetStructAddress=function() return 99 end}
    context.attributes.JumpVelocity={BaseValue=450,CurrentValue=450}
    context.movement.JumpZVelocity=450
    context.movement.GetMaxJumpHeight=function() return context.movement.JumpZVelocity^2/(2*1960) end
    context.movement.GetGravityZ=function() return -1960 end
    context.asc.GetGameplayEffectCount=function() return faults.effect and 1 or 0 end
    context.asc.GetGameplayAttributeValue=function(_,descriptor,output)
        assert(descriptor==context.descriptor and type(output)=="table")
        output.bFound = not faults.missing
        return context.attributes.JumpVelocity.CurrentValue
    end
    context.library.SetAttributeValue=function(_,asc,descriptor,value)
        assert(asc==context.asc and descriptor==context.descriptor)
        calls[#calls+1]=value
        if faults.argument then error("Out parameter requires a table before ProcessEvent") end
        if faults.reject and faults.reject(value) then return end
        context.attributes.JumpVelocity.BaseValue=value
        context.attributes.JumpVelocity.CurrentValue=value
        if not faults.cache then context.movement.JumpZVelocity=value*(faults.factor or 1) end
        if faults.throw and faults.throw(value) then error("Setter threw after write") end
    end
    return {context=context,calls=calls,faults=faults,pilot=module.New({borrow=function() return context end})}
end
local count=0
local function test(name,callback)
    local ok,failure=pcall(callback);assert(ok,name..": "..tostring(failure))
    count=count+1;print("PASS "..name)
end
test("official setter 1.5x and exact baseline restoration",function()
    local f=fixture();f.pilot.set(true)
    assert(f.context.attributes.JumpVelocity.BaseValue==675 and f.pilot.owned())
    f.pilot.verify();f.pilot.set(false)
    assert(f.calls[1]==675 and f.calls[2]==450 and not f.pilot.owned())
end)
test("repeated ON verifies without duplicate setters",function()
    local f=fixture();f.pilot.set(true);f.pilot.set(true);assert(#f.calls==1)
    f.pilot.set(false);f.pilot.set(false);assert(#f.calls==2)
end)
test("Wolf Boost owner blocks mutation",function()
    local f=fixture();f.faults.effect=true
    assert(not pcall(f.pilot.set,true) and #f.calls==0 and not f.pilot.owned())
end)
test("additional jump modifier blocks mutation",function()
    local f=fixture();f.context.attributes.JumpVelocity.CurrentValue=600
    assert(not pcall(f.pilot.set,true) and #f.calls==0)
end)
test("setter throws after mutation restores exact baseline",function()
    local f=fixture();f.faults.throw=function(value)return value==675 end
    assert(not pcall(f.pilot.set,true))
    assert(f.context.attributes.JumpVelocity.BaseValue==450 and not f.pilot.owned())
end)
test("unsynchronized movement cache rejects and rolls back",function()
    local f=fixture();f.faults.cache=true
    assert(not pcall(f.pilot.set,true))
    assert(f.context.attributes.JumpVelocity.BaseValue==450 and not f.pilot.owned())
end)
test("failed rollback retains recovery and blocks reset",function()
    local f=fixture();f.pilot.set(true);f.faults.reject=function(value)return value==450 end
    assert(not pcall(f.pilot.set,false) and f.pilot.owned() and not pcall(f.pilot.reset))
    f.faults.reject=nil;f.pilot.set(false);assert(not f.pilot.owned())
end)
test("identity change refuses restoration on replacement",function()
    local f=fixture();f.pilot.set(true);f.context.player.GetAddress=function()return 999 end
    assert(not pcall(f.pilot.set,false) and f.pilot.owned() and #f.calls==1)
end)
test("external base modification is not overwritten",function()
    local f=fixture();f.pilot.set(true);f.context.attributes.JumpVelocity.BaseValue=777
    assert(not pcall(f.pilot.set,false) and #f.calls==1 and f.pilot.owned())
end)
test("unvalidated borrower is never used for mutation",function()
    local f=fixture();f.context.validated=false
    assert(not pcall(f.pilot.set,true) and #f.calls==0)
end)
test("negative bFound out parameter rejects mutation",function()
    local f=fixture();f.faults.missing=true
    assert(not pcall(f.pilot.set,true) and #f.calls==0)
end)
test("game-derived movement scale is captured and restored independently",function()
    local f=fixture();f.faults.factor=math.sqrt(2)
    local baselineVelocity=450*math.sqrt(2)
    f.context.movement.JumpZVelocity=baselineVelocity
    f.pilot.inspect();f.pilot.set(true)
    assert(math.abs(f.context.movement.JumpZVelocity-baselineVelocity*1.5)<.001)
    f.pilot.set(false)
    assert(f.context.attributes.JumpVelocity.BaseValue==450 and math.abs(f.context.movement.JumpZVelocity-baselineVelocity)<.001)
end)
test("inconsistent derived jump height blocks mutation",function()
    local f=fixture();f.context.movement.GetMaxJumpHeight=function()return 999 end
    assert(not pcall(f.pilot.set,true) and #f.calls==0)
end)
test("premutation reference-argument failure clears verified unchanged ownership",function()
    local f=fixture();f.faults.argument=true
    assert(not pcall(f.pilot.set,true))
    assert(#f.calls==1 and not f.pilot.owned() and f.context.attributes.JumpVelocity.BaseValue==450)
    f.pilot.reset()
end)
test("registered unsupported setter remains disabled after successful read-only refresh",function()
    local f=fixture()
    local fields,states={},{}
    local registered=assert(loadfile(assert(arg[1]),"t",setmetatable({ExecuteInGameThread=function(callback)callback()end},{__index=_G})))()
    registered.Init({Register=function(section)for _,field in ipairs(section.items)do fields[field.id]=field end end,
        Set=function(_,id,value)states[id]=value end,SetLabel=function()end},{},function()return f.context end)
    assert(fields.enabled.enabled==false)
    fields.refresh.onClick();assert(fields.enabled.enabled==false and #f.calls==0)
    assert(not pcall(fields.enabled.onChange,true) and #f.calls==0)
    fields.enabled.onChange(false);assert(states.enabled==false)
    registered.ResetSession();assert(fields.enabled.enabled==false)
end)
print(count.." Super Jump pilot tests passed")
