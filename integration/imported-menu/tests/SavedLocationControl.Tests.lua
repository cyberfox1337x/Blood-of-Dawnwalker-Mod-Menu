local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("saved_location_tests")
local path = assert(arg[1])
local function fixture()
    local function object(address) return { address = address, IsValid = function() return true end, GetAddress = function(o) return o.address end } end
    local p, w, c = object(1), object(2), object(3)
    p.Controller = c; c.Pawn = p; p.GetWorld = function() return w end
    local position, calls, reject = {X=1,Y=2,Z=3}, 0, nil
    p.K2_GetActorLocation = function() return position end
    p.K2_GetActorRotation = function() return {pitch=0,Yaw=5,Roll=0} end
    p.K2_TeleportTo = function(_, value)
        calls = calls + 1
        if reject then return reject(value, calls) end
        position = value; return true
    end
    local items = {}
    local menu = {
        Register = function(section) for _, item in ipairs(section.items) do items[item.id] = item; item.value = item.default end end,
        Get = function(_, key) return items[key].value end,
        Set = function(_, key, value) items[key].value = value end,
        SetLabel = function(_, key, value) items[key].label = value end,
        SetOptions = function(_, key, options, selected) items[key].options = options; items[key].value = selected end,
    }
    local module = assert(loadfile(path))(); module.Init(menu, {GetPlayer=function() return p end})
    return { items=items, module=module, world=w, player=p,
        save=function(name) items.name.value=name; items.save.onClick() end,
        teleport=function() items.teleport.onClick() end,
        move=function(value) position=value end, position=function() return position end,
        calls=function() return calls end, reject=function(fn) reject=fn end }
end
local count=0
local function test(name, fn) local ok, err=pcall(fn); assert(ok, name..": "..tostring(err)); count=count+1; print("PASS "..name) end
test("save is read-only and teleport verifies saved position", function()
    local f=fixture(); f.save("Home"); assert(f.calls()==0)
    f.move({X=100,Y=200,Z=300}); f.teleport(); assert(f.position().X==1 and not f.items.cleanup.value)
end)
test("cross-world destinations are rejected before writes", function()
    local f=fixture(); f.save("Home"); f.world.address=9
    assert(not pcall(f.teleport)); assert(f.calls()==0)
end)
test("session reset clears locations", function()
    local f=fixture(); f.save("Home"); f.module.ResetSession()
    assert(#f.items.destination.options==0 and not pcall(f.teleport) and f.calls()==0)
end)
test("failed arrival restores exact origin", function()
    local f=fixture(); f.save("Home"); f.move({X=100,Y=200,Z=300})
    f.reject(function(value, call)
        f.move(value); if call==1 then f.move({X=50,Y=50,Z=50}) end; return true
    end)
    assert(not pcall(f.teleport)); assert(f.position().X==100 and not f.items.cleanup.value)
end)
test("failed restoration retains recovery for retry", function()
    local f=fixture(); f.save("Home"); f.move({X=100,Y=200,Z=300}); f.reject(function() return false end)
    assert(not pcall(f.teleport)); assert(f.items.cleanup.value and not pcall(f.module.ResetSession))
    f.reject(nil); f.items.cleanup.onChange(false); assert(not f.items.cleanup.value and f.position().X==100)
end)
test("names and location count are bounded", function()
    local f=fixture(); assert(not pcall(f.save,"bad\nname")); assert(not pcall(f.save,string.rep("x",65)))
    for index=1,32 do f.save(tostring(index)) end
    assert(not pcall(f.save,"33")); assert(not pcall(f.save,"1")); assert(f.calls()==0)
end)
test("opaque IDs preserve selection across sorting and reject duplicate labels", function()
    local f=fixture();f.save("Zulu");local zulu=f.items.destination.value
    assert(zulu~="Zulu");f.move({X=100,Y=200,Z=300});f.save("Alpha")
    assert(f.items.destination.options[1].label=="Alpha")
    f.items.destination.value=zulu;f.teleport();assert(f.position().X==1)
    assert(not pcall(f.save,"zULu"))
end)
test("old IDs cannot be reused after a new session saves the same label", function()
    local f=fixture();f.save("Home");local old=f.items.destination.value;f.module.ResetSession();f.save("Home")
    assert(f.items.destination.value~=old);f.items.destination.value=old
    assert(not pcall(f.teleport));assert(f.calls()==0)
end)
print(count.." SavedLocation tests passed")
