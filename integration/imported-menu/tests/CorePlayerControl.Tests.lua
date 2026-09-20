local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("core_player_control_tests")
local path = assert(arg[1])
local function fixture()
    local nextAddress = 0
    local function object()
        nextAddress = nextAddress + 1
        return { address = nextAddress, valid = true, IsValid = function(o) return o.valid end,
            GetAddress = function(o) return o.address end }
    end
    local player, world, controller, combat, blood = object(), object(), object(), object(), object()
    player.GetWorld = function() return world end
    player.Controller, player.CombatComponent, player.BloodBar, controller.Pawn = controller, combat, blood, player
    combat.IsAlive = function() return true end
    local values, locks, reject = { health = .7, stamina = .4, blood = .3 }, {}, {}
    for _, entry in ipairs({ {"health","Health",combat}, {"stamina","Stamina",combat}, {"blood","Blood",blood} }) do
        local key, suffix, target = table.unpack(entry)
        target["Get" .. suffix .. "Percentage"] = function() return values[key] end
        target["Set" .. suffix .. "Percent"] = function(_, value)
            if not (reject[key] and reject[key](value)) then values[key] = value end
        end
        target["Lock" .. suffix] = function() locks[key] = true end
        target["Unlock" .. suffix] = function() locks[key] = false end
    end
    blood.GetBlood = function() return values.blood end
    blood.GetBloodBarLength = function() return 1 end
    local checkbox, bloodCheckbox, sprintCheckbox, healthCheckbox, state, refill = nil, nil, nil, nil, {}, false
    local fields = {}
    local menu = { Register = function(section)
        for _, item in ipairs(section.items) do
            fields[item.id] = item
            if item.id == "god" then checkbox = item end
            if item.id == "bloodEnabled" then bloodCheckbox = item end
            if item.id == "sprintEnabled" then sprintCheckbox = item end
            if item.id == "healthEnabled" then healthCheckbox = item end
        end
    end,
        Set = function(_, key, value) state[key] = value end, SetLabel = function() end,
        Get = function() return refill end }
    local module = assert(loadfile(path, "t", setmetatable({ ExecuteInGameThread = function(fn) fn() end }, {__index = _G})))()
    module.Init(menu, { GetPlayer = function() return player end })
    return { toggle = function(on) checkbox.onChange(on) end, values = values, locks = locks,
        reject = reject, module = module, player = player, controller = controller,
        blood = function(on) bloodCheckbox.onChange(on) end,
        sprint = function(on) sprintCheckbox.onChange(on) end,
        health = function(on) healthCheckbox.onChange(on) end,
        healthState = function() return state.healthEnabled end,
        amount = function(value) fields.bloodPercent.onChange(value) end,
        recovery = function() fields.bloodRecovery.onChange(false) end,
        fields = fields, valuesState = state,
        refill = function(on) refill = on end, state = function() return state.god end,
        bloodState = function() return state.bloodEnabled end }
end
local count = 0
local function test(name, fn)
    local ok, err = pcall(fn); assert(ok, name .. ": " .. tostring(err))
    count = count + 1; print("PASS " .. name)
end
test("resource ON/OFF roundtrip and idempotent ON", function()
    local f = fixture(); f.toggle(true); f.toggle(true)
    assert(f.values.health == 1 and f.values.stamina == 1 and f.values.blood == 1)
    f.toggle(false); assert(f.values.health == .7 and f.values.stamina == .4 and f.values.blood == .3)
    assert(not f.locks.health and not f.locks.stamina and not f.locks.blood and not f.state())
end)
test("partial acquisition rolls back every touched resource", function()
    local f = fixture(); f.reject.blood = function(v) return v == 1 end
    assert(not pcall(f.toggle, true)); assert(f.values.health == .7 and f.values.stamina == .4 and f.values.blood == .3)
    assert(not f.state() and not f.locks.health and not f.locks.blood)
end)
test("failed restore remains owned and retries without allowing new activation", function()
    local f = fixture(); f.toggle(true); f.reject.health = function(v) return v == .7 end
    assert(not pcall(f.toggle, false)); assert(f.state()); assert(not pcall(f.module.ResetSession))
    f.reject.health = nil; f.toggle(false); assert(f.values.health == .7 and not f.state())
    assert(not pcall(f.toggle, true))
end)
test("expired targets are never replaced by newly resolved targets", function()
    local f = fixture(); f.toggle(true); f.player.address = 999
    assert(not pcall(f.toggle, false)); assert(f.values.health == 1 and f.state())
end)
test("unpossessed player cannot acquire resources", function()
    local f = fixture(); f.controller.Pawn = nil
    assert(not pcall(f.toggle, true)); assert(f.values.health == .7)
end)
test("rapid stamina refill ownership survives God OFF", function()
    local f = fixture(); f.toggle(true); f.refill(true); f.toggle(false)
    assert(f.values.stamina == 1 and not f.locks.stamina and f.values.health == .7)
end)
test("refill OFF before God OFF restores captured baseline", function()
    local f = fixture(); f.toggle(true); f.refill(true); f.refill(false); f.toggle(false)
    assert(f.values.stamina == .4)
end)
test("a second owner joining a shared lock restores a drifted value instead of failing", function()
    -- The bug this pins: Sprint No Drain held stamina, gameplay moved the value under
    -- the native lock, and turning God Mode on then threw "Shared resource lock readback
    -- failed" - refusing the player's request for drift they did not cause.
    local f = fixture(); f.sprint(true); assert(f.values.stamina == 1 and f.locks.stamina)
    f.values.stamina = .82
    f.toggle(true)
    assert(f.values.stamina == 1, "the shared resource was not restored to full")
    assert(f.locks.stamina, "the existing native lock must be left as it was")
    f.toggle(false); f.sprint(false)
    assert(f.values.stamina == .4, "release still restores the sprint owner's captured baseline")
end)
test("a shared lock that cannot be restored is still refused, with the reason", function()
    local f = fixture(); f.sprint(true)
    f.values.stamina = .5
    f.reject.stamina = function(v) return v == 1 end
    local ok, err = pcall(f.toggle, true)
    assert(not ok and tostring(err):find("could not be restored", 1, true), tostring(err))
end)
test("blood alone only changes blood", function()
    local f = fixture(); f.blood(true)
    assert(f.values.blood == 1 and f.values.health == .7 and f.values.stamina == .4)
    f.blood(false); assert(f.values.blood == .3 and not f.locks.blood)
end)
for _, bloodFirst in ipairs({true, false}) do
    for _, releaseBloodFirst in ipairs({true, false}) do
        test("shared blood ownership " .. tostring(bloodFirst) .. "/" .. tostring(releaseBloodFirst), function()
            local f = fixture()
            if bloodFirst then f.blood(true); f.toggle(true) else f.toggle(true); f.blood(true) end
            if releaseBloodFirst then
                f.blood(false); assert(f.locks.blood and f.values.blood == 1 and f.state()); f.toggle(false)
            else
                f.toggle(false); assert(f.locks.blood and f.values.blood == 1 and f.bloodState()); f.blood(false)
            end
            assert(f.values.blood == .3 and f.values.health == .7 and f.values.stamina == .4)
            assert(not f.locks.blood and not f.state() and not f.bloodState())
        end)
    end
end
test("failed God acquisition preserves independent blood owner", function()
    local f = fixture(); f.blood(true); f.reject.health = function(v) return v == 1 end
    assert(not pcall(f.toggle, true)); assert(f.locks.blood and f.bloodState() and f.values.blood == 1)
    f.blood(false); assert(f.values.blood == .3)
end)
test("persistent blood target cannot share ownership across worlds", function()
    local f = fixture(); f.blood(true)
    f.player.GetWorld = function() return { IsValid = function() return true end, GetAddress = function() return 987 end } end
    assert(not pcall(f.toggle, true)); assert(not f.state() and f.bloodState() and f.locks.blood)
    f.blood(false); assert(f.values.blood == .3)
end)
test("shared release retains ownership when remaining lock readback fails", function()
    local f = fixture(); f.toggle(true); f.blood(true); f.values.blood = .2
    assert(not pcall(f.blood, false)); assert(f.bloodState() and f.state())
    f.values.blood = 1; f.blood(false); f.toggle(false); assert(f.values.blood == .3)
end)
test("sprint control locks only stamina and restores its original value", function()
    local f=fixture(); f.sprint(true)
    assert(f.values.stamina==1 and f.locks.stamina and f.values.health==.7 and f.values.blood==.3)
    f.sprint(false); assert(f.values.stamina==.4 and not f.locks.stamina)
end)
for _, sprintFirst in ipairs({true,false}) do
    for _, releaseSprintFirst in ipairs({true,false}) do
        test("God and sprint shared stamina "..tostring(sprintFirst).."/"..tostring(releaseSprintFirst), function()
            local f=fixture()
            if sprintFirst then f.sprint(true); f.toggle(true) else f.toggle(true); f.sprint(true) end
            if releaseSprintFirst then f.sprint(false); assert(f.locks.stamina); f.toggle(false)
            else f.toggle(false); assert(f.locks.stamina); f.sprint(false) end
            assert(f.values.stamina==.4 and not f.locks.stamina)
        end)
    end
end
test("all three resource owners and rapid refill preserve independent ownership", function()
    local f=fixture(); f.sprint(true); f.blood(true); f.toggle(true); f.refill(true)
    f.toggle(false); assert(f.locks.stamina and f.locks.blood and not f.locks.health)
    f.blood(false); f.sprint(false)
    assert(f.values.stamina==1 and f.values.blood==.3 and f.values.health==.7)
    assert(not f.locks.stamina and not f.locks.blood)
end)
test("independent health only locks health and restores baseline", function()
    local f = fixture(); f.health(true); f.health(true)
    assert(f.values.health == 1 and f.locks.health and f.healthState())
    assert(f.values.stamina == .4 and f.values.blood == .3 and not f.state())
    f.health(false); f.health(false)
    assert(f.values.health == .7 and not f.locks.health and not f.healthState())
    f.module.ResetSession()
end)
for _, healthFirst in ipairs({true, false}) do
    for _, releaseHealthFirst in ipairs({true, false}) do
        test("God and health share original baseline " .. tostring(healthFirst) .. "/" .. tostring(releaseHealthFirst), function()
            local f = fixture()
            if healthFirst then f.health(true); f.toggle(true) else f.toggle(true); f.health(true) end
            if releaseHealthFirst then
                f.health(false); assert(f.locks.health and f.values.health == 1 and f.state()); f.toggle(false)
            else
                f.toggle(false); assert(f.locks.health and f.values.health == 1 and f.healthState()); f.health(false)
            end
            assert(f.values.health == .7 and not f.locks.health and not f.healthState() and not f.state())
        end)
    end
end
test("failed God acquisition preserves independent health ownership", function()
    local f = fixture(); f.health(true); f.reject.blood = function(v) return v == 1 end
    assert(not pcall(f.toggle, true)); assert(f.healthState() and f.locks.health and not f.state())
    f.health(false); assert(f.values.health == .7 and not f.locks.health)
end)
test("failed health restoration retains ownership and blocks session reset", function()
    local f = fixture(); f.health(true); f.reject.health = function(v) return v == .7 end
    assert(not pcall(f.health, false)); assert(f.healthState() and not pcall(f.module.ResetSession))
    f.reject.health = nil; f.health(false); assert(not f.healthState() and f.values.health == .7)
end)
test("all independent owners survive God disable and release separately", function()
    local f = fixture(); f.health(true); f.sprint(true); f.blood(true); f.toggle(true)
    f.toggle(false); assert(f.locks.health and f.locks.stamina and f.locks.blood)
    f.health(false); assert(not f.locks.health and f.locks.stamina and f.locks.blood)
    f.sprint(false); f.blood(false)
    assert(f.values.health == .7 and f.values.stamina == .4 and f.values.blood == .3)
    f.module.ResetSession()
end)
test("blood amount writes only requested percentage without acquiring a lock", function()
    local f = fixture(); f.amount(45)
    assert(f.values.blood == .45 and f.values.health == .7 and f.values.stamina == .4)
    assert(not f.locks.blood and f.valuesState.bloodPercent == 45 and not f.valuesState.bloodRecovery)
    f.module.ResetSession(); assert(f.values.blood == .45)
end)
test("blood amount refuses conflicting God and blood locks", function()
    for _, owner in ipairs({"toggle", "blood"}) do
        local f = fixture(); f[owner](true)
        assert(not f.fields.bloodPercent.enabled and not pcall(f.amount, 25))
        assert(f.values.blood == 1 and f.locks.blood); f[owner](false)
    end
end)
test("blood amount rejects invalid percentages before mutation", function()
    for _, value in ipairs({-1, 101, math.huge, -math.huge, 0/0, "50"}) do
        local f = fixture(); assert(not pcall(f.amount, value)); assert(f.values.blood == .3)
    end
end)
test("blood amount failed write restores baseline without unlocking blood", function()
    local f = fixture(); f.reject.blood = function(value) return value == .45 end
    assert(not pcall(f.amount, 45)); assert(f.values.blood == .3 and f.locks.blood == nil)
    assert(not f.valuesState.bloodRecovery and f.valuesState.bloodPercent == 30)
end)
test("blood amount failed rollback retains recovery until explicit restoration", function()
    local f = fixture()
    f.reject.blood = function(value)
        if value == .45 then f.values.blood = .2; return true end
        return value == .3
    end
    assert(not pcall(f.amount, 45)); assert(f.valuesState.bloodRecovery)
    assert(not pcall(f.module.ResetSession) and not pcall(f.amount, 50))
    f.reject.blood = nil; f.recovery()
    assert(f.values.blood == .3 and not f.valuesState.bloodRecovery and f.valuesState.bloodPercent == 30)
end)
test("blood amount can coexist with independent health and sprint", function()
    local f = fixture(); f.health(true); f.sprint(true); f.amount(60)
    assert(f.locks.health and f.locks.stamina and f.values.blood == .6)
    f.health(false); f.sprint(false); assert(f.values.blood == .6)
end)
print(string.format("%d CorePlayerControl tests passed", count))
