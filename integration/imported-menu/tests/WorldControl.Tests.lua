local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("world_control_tests")
local path = assert(arg[1])
local function fixture()
    local function object(address) return { address = address, valid = true,
        IsValid = function(o) return o.valid end, GetAddress = function(o) return o.address end } end
    local player, world, controller, statics = object(1), object(2), object(3), object(4)
    local speed, reject, writes = .8, nil, 0
    player.Controller, controller.Pawn = controller, player
    player.GetWorld = function() return world end
    player.K2_GetActorLocation = function() return { X = 1, Y = 2, Z = 3 } end
    statics.GetGlobalTimeDilation = function() return speed end
    statics.SetGlobalTimeDilation = function(_, _, value) writes = writes + 1; if not reject or not reject(value) then speed = value end end
    local items, values, labels = {}, {}, {}
    local menu = { Register = function(section) for _, item in ipairs(section.items) do items[item.id] = item end end,
        Set = function(_, key, value) values[key] = value end,
        SetLabel = function(_, key, value) labels[key] = value end, OnOpen = function() end }
    local env = setmetatable({ ExecuteInGameThread = function(fn) fn() end, StaticFindObject = function() return statics end }, {__index = _G})
    local module = assert(loadfile(path, "t", env))(); module.Init(menu, { GetPlayer = function() return player end })
    return { set = function(v) items.speed.onChange(v) end, stop = function() items.owned.onChange(false) end,
        refresh = items.refresh.onClick, module = module, values = values, labels = labels, player = player, world = world,
        speed = function() return speed end, writes = function() return writes end, reject = function(fn) reject = fn end }
end
local count = 0
local function test(name, fn) local ok, err = pcall(fn); assert(ok, name .. ": " .. tostring(err)); count = count + 1; print("PASS " .. name) end
test("location and speed refresh are read only", function()
    local f = fixture(); f.refresh(); assert(f.writes() == 0 and f.values.speed == .8)
    assert(f.labels.location == "X: 1.00  Y: 2.00  Z: 3.00")
end)
test("repeated speed changes preserve original baseline for stop", function()
    local f = fixture(); f.set(2); f.set(.5); assert(f.values.owned); f.stop()
    assert(f.speed() == .8 and not f.values.owned); f.module.ResetSession()
end)
test("invalid and nonfinite speed never writes", function()
    for _, value in ipairs({0, 4, math.huge, 0/0}) do
        local f = fixture(); assert(not pcall(f.set, value)); assert(f.writes() == 0)
    end
end)
test("silent setter failure rolls back", function()
    local f = fixture(); f.reject(function(v) return v == 2 end)
    assert(not pcall(f.set, 2)); assert(f.speed() == .8 and not f.values.owned)
end)
test("failed restoration remains owned and retryable", function()
    local f = fixture(); f.set(2); f.reject(function(v) return v == .8 end)
    assert(not pcall(f.stop)); assert(f.values.owned); assert(not pcall(f.module.ResetSession))
    f.reject(nil); f.stop(); assert(f.speed() == .8 and not f.values.owned)
    assert(not pcall(f.set, 2))
end)
test("expired world never receives restore writes", function()
    local f = fixture(); f.set(2); f.world.address = 20; local before = f.writes()
    assert(not pcall(f.stop)); assert(f.writes() == before and f.values.owned)
end)
test("nonfinite location rejected without writes", function()
    local f = fixture(); f.player.K2_GetActorLocation = function() return {X=math.huge,Y=0,Z=0} end
    assert(not pcall(f.refresh)); assert(f.writes() == 0)
end)
print(string.format("%d WorldControl tests passed", count))
