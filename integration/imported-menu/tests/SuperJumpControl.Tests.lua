local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("super_jump_control_tests")
local source = assert(arg[1])
local function fixture()
    local items, values, owned, setCalls, read, failRestore, failInspect, wolf = {}, {}, false, 0, false, false, false, false
    local pilot = { inspect = function() assert(not failInspect, "injected inspection failure"); read = true end,
        set = function(value)
            setCalls = setCalls + 1
            if value then assert(read); owned = true else assert(not failRestore, "injected restoration failure"); owned = false end
        end,
        owned = function() return owned end,
        reset = function() assert(not failRestore, "injected restoration failure"); owned = false; read = false end }
    local dependencies
    local env = setmetatable({
        require = function(name) assert(name == "SuperJumpEffectPilot"); return { New = function(deps) dependencies = deps; return pilot end } end,
        ExecuteInGameThread = function(callback) callback() end,
    }, { __index = _G })
    local module = assert(loadfile(source, "t", env))()
    local player = { IsValid = function() return true end, IsInWolfForm = function() return wolf end }
    module.Init({ Register = function(section) for _, item in ipairs(section.items) do items[item.id] = item end end,
        Set = function(_, key, value) values[key] = value end, SetLabel = function(_, _, message) values.status = message end },
        { GetPlayer = function() return player end }, function() return { validated = true } end,
        { registerHook = function() end, unregisterHook = function() end })
    return { items = items, values = values, module = module, deps = dependencies,
        calls = function() return setCalls end, fail = function(value) failRestore = value end,
        failInspect = function(value) failInspect = value end, wolf = function() wolf = true end }
end
local count = 0
local function test(name, callback) callback(); count = count + 1; print("PASS " .. name) end
test("automatic read gates enable and OFF restores the real pilot without a manual button", function()
    local f = fixture(); assert(f.items.enabled.enabled == false)
    assert(f.items.refresh == nil, "manual Super Jump read button must not be published")
    assert(not pcall(f.items.enabled.onChange, true) and f.calls() == 0)
    f.module.SessionReady(); assert(f.items.enabled.enabled)
    f.items.enabled.onChange(true); assert(f.values.enabled == true)
    f.items.enabled.onChange(false); assert(f.values.enabled == false and f.calls() == 2)
end)
test("automatic readiness remains retryable after a transient inspection failure", function()
    local f = fixture()
    assert(f.module.NeedsSessionReady() == true)
    f.failInspect(true); assert(not pcall(f.module.SessionReady)); assert(f.module.NeedsSessionReady() == true)
    f.failInspect(false); f.module.SessionReady(); assert(f.module.NeedsSessionReady() == false and f.items.enabled.enabled)
end)
test("unpaused human context is permitted but wolf context rejected", function()
    local f = fixture(); assert(f.deps.exclusive() == true); f.wolf(); assert(f.deps.exclusive() == false)
end)
test("failed OFF keeps recovery checkbox actionable", function()
    local f = fixture(); f.module.SessionReady(); f.items.enabled.onChange(true); f.fail(true)
    assert(not pcall(f.items.enabled.onChange, false))
    assert(f.values.enabled == true and f.items.enabled.enabled and f.values.status:find("recovery required", 1, true))
    f.fail(false); f.items.enabled.onChange(false); assert(not f.values.enabled and not f.items.enabled.enabled)
end)
test("session cleanup publishes restored state and disables until the next automatic read", function()
    local f = fixture(); f.module.SessionReady(); f.items.enabled.onChange(true); f.module.ResetSession()
    assert(f.values.enabled == false and f.items.enabled.enabled == false)
end)
test("failed session cleanup retains true recovery state", function()
    local f = fixture(); f.module.SessionReady(); f.items.enabled.onChange(true); f.fail(true)
    assert(not pcall(f.module.ResetSession)); assert(f.values.enabled and f.items.enabled.enabled)
end)
print(count .. " Super Jump control tests passed")
