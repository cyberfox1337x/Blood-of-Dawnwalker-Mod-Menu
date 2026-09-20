local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("form_toggle_regression_tests")
local path = assert(arg[1])
local function fixture(beforeFormChange)
    local function object(address, name)
        return { alive = true, IsValid = function(self) return self.alive end,
            GetAddress = function() return address end, GetFullName = function() return name or "Object" end,
            IsA = function() return true end }
    end
    local human, vampire = object(10), object(11)
    local appearance = object(12); appearance.BodyPreset = human
    local component = object(13); component.GetCurrentAppearance = function() return appearance end;component.CurrentBody = human
    local failure, calls, queue, hooks = nil, 0, {}, {}
    local bodyCalls, bodyReads, pendingBody, coldReads = 0, 0, nil, 0
    component.ApplyBody = function(_, body)
        bodyCalls = bodyCalls + 1
        assert(failure ~= "body", "body failure")
        if failure == "cold-body" then pendingBody = body;coldReads = 3
        elseif failure ~= "body-readback" then component.CurrentBody = body end
    end
    local player = object(1); player.AppearanceComponent = component; player.DefaultAppearance = { IsValid = function() return true end, BodyPreset = human }
    local current, form, realNight, policy = player, false, false, 0
    player.IsVampire = function() return form end
    player.OnBeforeBecomingVampire = function() end; player.OnBeforeBecomingHuman = function() end
    player.SetFormSelectionPolicy = function(_, selection)
        calls = calls + 1; policy = selection
        assert(failure ~= "setter", "setter failure")
        form = selection == 2 or (selection == 0 and realNight)
    end
    local subsystem = object(2)
    subsystem.GetAbilityInSlot = function() return object(80) end
    local widget = object(3, "WBP_AA_Quickslots_C /Engine/Transient.WBP_GameHUD_C")
    widget.SetPropertyValue = function() assert(failure ~= "wheel", "wheel failure") end
    widget.GetPropertyValue = function() return { IsValid = function() return true end,
        SetPropertyValue = function() end, GetPropertyValue = function(_, name)
            if name == "Set Ability" then return function() end end; return 1 end } end
    local system = object(4);system.GetOffsetTime = function() return { bIsDay = not realNight } end
    local binding = { FunctionName = { ToString = function() return "On Day Phase Changed" end }, Object = object(5, "BP_PlayerCharacter_C") }
    local phase
    system.OnDayPhaseChangedDynamicDelegate = { GetBindings = function() return { binding } end,
        Broadcast = function(_, requested) assert(failure ~= "equipment", "equipment failure"); phase = requested end }
    local items = {}
    -- The module no longer registers a section: its checkbox and status are presented
    -- by the Player controls panel under the ids formOverride and formStatus. Those
    -- are pre-created and aliased to the original names the assertions use, so the
    -- existing coverage keeps testing behaviour rather than presentation.
    items.formOverride = { value = false }
    items.formStatus = { label = "" }
    items.enabled = items.formOverride
    items.status = items.formStatus
    local menu = { Register = function(section) for _,item in ipairs(section.items) do items[item.id] = item;item.value = item.default end end,
        Set = function(_, key, value) items[key] = items[key] or {};items[key].value = value end,
        SetLabel = function(_, key, text) items[key] = items[key] or {};items[key].label = text end }
    local environment = setmetatable({
        StaticFindObject = function(name) if name:find("7_APP", 1, true) then return { IsValid = function() return true end, BodyPreset = vampire } end;return object(40) end,
        FindFirstOf = function(name) if name == "TimeSystemImpl" then return system end;return subsystem end,
        FindAllOf = function() return { widget } end, print = function() end,
        RegisterHook = function(name, callback) assert(not hooks[name], "duplicate hook");hooks[name] = callback;return 1,2 end,
        -- The override releases its quickslot hooks when it turns off, so the double
        -- has to model detaching as well as attaching: without it, re-enabling looks
        -- like a duplicate registration rather than a fresh one.
        UnregisterHook = function(name, pre, post)
            assert(hooks[name], "released a hook that was never registered: " .. tostring(name))
            assert(pre == 1 and post == 2, "released with ids the registration never handed out")
            hooks[name] = nil
        end,
        ExecuteWithDelay = function(delay, callback)
            queue[#queue+1] = function()
                if delay == 250 then
                    bodyReads = bodyReads + 1
                    if pendingBody then
                        coldReads = coldReads - 1
                        if coldReads == 0 then component.CurrentBody = pendingBody;pendingBody = nil end
                    end
                end
                callback()
            end
        end,
    }, { __index = _G })
    local module = assert(loadfile(path, "t", environment))()
    module.Init(menu, { GetPlayer = function() return current end }, beforeFormChange)
    local function drain() while #queue > 0 do table.remove(queue, 1)() end end
    return { items = items, hooks = hooks, player = player, subsystem = subsystem, module = module,
        toggle = function(enabled) module.SetFormOverride(enabled);drain() end,
        setFailure = function(value) failure = value end,
        night = function() realNight = true end,
        replace = function() player.alive = false;current = object(999) end,
        state = function() return policy, form, component.CurrentBody, phase, calls end,
        human = human, vampire = vampire, appearance = appearance,
        bodyCounts = function() return bodyCalls, bodyReads end }
end
local total = 0
local function test(name, callback) local ok,err = pcall(callback);assert(ok, name .. ": " .. tostring(err));total=total+1;print("PASS " .. name) end
test("idle performs no native writes or hooks", function()
    local f=fixture();local _,_,_,_,calls=f.state();assert(calls==0 and next(f.hooks)==nil and not f.items.enabled.value)
end)
test("enable selects vampire body night equipment and disable restores human", function()
    local f=fixture();f.toggle(true);local p,v,b,phase=f.state();assert(p==2 and v and b==f.vampire and phase==2 and f.items.enabled.value)
    f.toggle(false);p,v,b,phase=f.state();assert(p==0 and not v and b==f.human and phase==1 and not f.items.enabled.value)
end)
test("actual CurrentBody validates independently of original appearance descriptor", function()
    local f=fixture();f.toggle(true);local _,_,body=f.state();assert(body==f.vampire and f.appearance.BodyPreset==f.human)
    f.toggle(false);local _,_,restored=f.state();assert(restored==f.human)
end)
test("cold body loading waits for readback with one apply per direction", function()
    local f=fixture();f.setFailure("cold-body");f.toggle(true)
    local applied,reads=f.bodyCounts();assert(applied==1 and reads==3 and f.items.enabled.value)
    f.toggle(false);applied,reads=f.bodyCounts();assert(applied==2 and reads==6 and not f.items.enabled.value)
end)
test("body readback timeout is bounded and never repeats application", function()
    local f=fixture();f.setFailure("body-readback");assert(not pcall(f.toggle,true))
    local applied,reads=f.bodyCounts();assert(applied==1 and reads==20 and f.items.enabled.value)
    assert(f.items.status.label:find("timed out",1,true))
    f.setFailure(nil);f.toggle(false);assert(not f.items.enabled.value)
end)
test("OFF at night restores automatic while remaining vampire", function()
    local f=fixture();f.toggle(true);f.night();f.toggle(false);local p,v,_,phase=f.state();assert(p==0 and v and phase==2 and not f.items.enabled.value)
end)
test("repeat enable is idempotent and hooks registered once", function()
    local f=fixture();f.toggle(true);f.toggle(true);local _,_,_,_,calls=f.state();assert(calls==1);f.toggle(false);f.toggle(true);f.toggle(false)
end)
for _,kind in ipairs({ "setter", "body", "body-readback", "equipment", "wheel" }) do
    test(kind .. " failure remains actionable and OFF recovers", function()
        local f=fixture();f.setFailure(kind);assert(not pcall(f.toggle,true));assert(f.items.enabled.value and f.items.status.label:find("incomplete",1,true))
        f.setFailure(nil);f.toggle(false);assert(not f.items.enabled.value)
    end)
end
test("turning off releases the quickslot hooks instead of leaving them attached", function()
    -- The game calls these every frame while the ability wheel is up. Left attached they
    -- cost a crossing into Lua for a callback with nothing left to decide.
    local f=fixture();f.toggle(true)
    local attached=0;for _ in pairs(f.hooks) do attached=attached+1 end
    assert(attached==2, "expected both quickslot hooks, got " .. attached)
    f.toggle(false)
    assert(next(f.hooks)==nil, "the quickslot hooks outlived the override being turned off")
end)
test("hooks affect only owned subsystem and stop when disabled", function()
    local f=fixture();f.toggle(true);local callback=next(f.hooks) and select(2,next(f.hooks));local phase=1
    local parameter={get=function()return phase end,set=function(_,v)phase=v end}
    callback({get=function()return {IsValid=function()return true end,GetAddress=function()return 999 end}end},nil,parameter);assert(phase==1)
    callback({get=function()return f.subsystem end},nil,parameter);assert(phase==2)
    f.toggle(false);phase=1;callback({get=function()return f.subsystem end},nil,parameter);assert(phase==1)
end)
test("live ownership cannot be silently discarded", function()
    local f=fixture();f.toggle(true);assert(not pcall(f.module.ResetSession));f.toggle(false);f.module.ResetSession()
end)
test("destroyed pawn reset discards cached body and hook ownership", function()
    local f=fixture();f.toggle(true);f.replace();f.module.ResetSession();assert(not f.items.enabled.value)
end)

test("eye restoration failure prevents form setters", function()
    local f = fixture(function() error("eye restoration pending") end)
    local ok = pcall(f.toggle, true)
    assert(not ok)
    local _, _, _, _, calls = f.state()
    assert(calls == 0)
end)

print(total .. " form toggle tests passed")
