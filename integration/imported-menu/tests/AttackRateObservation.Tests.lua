local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("attack_rate_observation_tests")
local module = assert(loadfile(assert(arg[1], "Pass AttackRateObservation.lua path")))()
local function object(id, class)
    return { IsValid = function() return true end, GetAddress = function() return id end,
        IsA = function(_, requested) return requested == class end,
        GetFullName = function() return class .. " Object" .. id end }
end
local function fixture()
    local player = object(1, "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
    local world = object(2, "/Script/Engine.World")
    local controller = object(3, "/Script/Engine.PlayerController")
    local mesh = object(4, "/Script/Engine.SkeletalMeshComponent")
    local anim = object(5, "/Script/Engine.AnimInstance")
    local attributes = object(6, "/Script/DogwoodStats.CharacterBaseAttributeSet")
    local montage = object(7, "/Script/Engine.AnimMontage")
    local combat = object(8, "/Script/DogwoodCombat.PlayerCombatComponent")
    local library = object(9, "/Script/Engine.GameplayStatics")
    player.Controller, player.Mesh, player.CharacterAttributeSet, player.CombatComponent = controller, mesh, attributes, combat
    controller.Pawn = player
    player.GetWorld = function() return world end
    controller.GetWorld = player.GetWorld
    mesh.GetOwner = function() return player end
    mesh.GetAnimInstance = function() return anim end
    anim.GetOwningActor = mesh.GetOwner
    attributes.GetOuter = mesh.GetOwner
    combat.GetOwner = mesh.GetOwner
    combat.IsAlive = function() return true end
    combat.CachedAnimInstance = anim
    attributes.AttackSpeedMultiplierAdditive = { BaseValue = 0, CurrentValue = 0 }
    local real, game, paused, playing, rate = 0, 0, true, false, 1
    library.GetRealTimeSeconds = function() return real end
    library.GetTimeSeconds = function() return game end
    library.IsGamePaused = function() return paused end
    anim.GetCurrentActiveMontage = function() return playing and montage or nil end
    anim.Montage_IsPlaying = function(_, selected) assert(selected == montage); return playing end
    anim.Montage_GetPlayRate = function() return rate end
    anim.Montage_GetEffectivePlayRate = function() return rate end
    anim.Montage_GetPosition = function() return game * rate end
    anim.Montage_GetCurrentSection = function() return "Normal" end
    local scheduled, cancelled, callback, reports = 0, 0, nil, {}
    local observer = module.New({ GetPlayer = function() return player end }, {
        library = library, inGameThread = function() return true end,
        schedule = function(delay, fn) assert(delay == 50 and callback == nil); scheduled = scheduled + 1; callback = fn; return scheduled end,
        cancel = function(handle) assert(handle == scheduled); cancelled = cancelled + 1; callback = nil end,
    })
    local function publish(report) reports[#reports + 1] = report end
    local function tick(seconds)
        real = real + (seconds or .05)
        if not paused then game = game + (seconds or .05) end
        if callback then callback() end
    end
    return { observer = observer, publish = publish, reports = reports, tick = tick,
        pause = function(value) paused = value end, play = function(value) playing = value end,
        rate = function(value) rate = value end, player = player, mesh = mesh, anim = anim,
        attributes = attributes, combat = combat,
        counts = function() return scheduled, cancelled end,
        rawCallback = function() return callback end }
end
local total = 0
local function test(name, callback) callback(); total = total + 1; print("PASS " .. name) end
test("paused wait then bounded named-montage capture", function()
    local f = fixture(); f.observer.start(f.publish); f.tick(2)
    assert(f.observer.active() and #f.reports == 1)
    f.pause(false); f.play(true)
    for _ = 1, 105 do f.tick() end
    assert(not f.observer.active()); local report = f.reports[#f.reports]
    assert(report.records == 100 and report.truncated and #report.report <= 14000)
    assert(report.report:find("Normal", 1, true) and report.report:find("effective", 1, true))
    assert(f.attributes.AttackSpeedMultiplierAdditive.CurrentValue == 0)
    local _, cancelled = f.counts(); assert(cancelled == 1)
end)
test("paused wait times out without reads being called changes", function()
    local f = fixture(); f.observer.start(f.publish); f.tick(30)
    assert(not f.observer.active() and f.reports[#f.reports].records == 0)
    assert(f.reports[#f.reports].status:find("paused", 1, true))
end)
test("empty active capture reports no montage evidence", function()
    local f = fixture(); f.pause(false); f.observer.start(f.publish)
    for _ = 1, 200 do f.tick() end
    assert(not f.observer.active() and f.reports[#f.reports].records == 0)
    assert(f.reports[#f.reports].status:find("No playing montage", 1, true))
end)
test("session drift clears report and cancels exact timer", function()
    local f = fixture(); f.pause(false); f.play(true); f.observer.start(f.publish); f.tick()
    f.mesh.GetAddress = function() return 99 end
    assert(not pcall(f.tick)); assert(not f.observer.active())
    assert(f.reports[#f.reports].report == "" and f.reports[#f.reports].phase == "failed")
    local _, cancelled = f.counts(); assert(cancelled == 1)
end)
test("bonus drift and nonfinite montage readings fail closed", function()
    for _, scenario in ipairs({ "bonus", "rate" }) do
        local f = fixture(); f.pause(false); f.play(true); f.observer.start(f.publish); f.tick()
        if scenario == "bonus" then f.attributes.AttackSpeedMultiplierAdditive.CurrentValue = .1 else f.rate(0/0) end
        assert(not pcall(f.tick) and not f.observer.active())
        assert(f.reports[#f.reports].report == "")
    end
end)
test("pause ends active capture without inventing attack type", function()
    local f = fixture(); f.pause(false); f.play(true); f.observer.start(f.publish); f.tick(); f.pause(true); f.tick()
    assert(not f.observer.active() and f.reports[#f.reports].status:find("paused", 1, true))
    assert(f.reports[#f.reports].records > 0)
end)
test("replacement and reset cancel callbacks and clear evidence", function()
    local f = fixture(); f.observer.start(f.publish); local stale = f.rawCallback()
    f.observer.start(f.publish); stale(); assert(f.observer.active())
    f.observer.ResetSession(); assert(not f.observer.active())
    local scheduled, cancelled = f.counts(); assert(scheduled == 2 and cancelled == 2)
    assert(f.reports[#f.reports].report == "")
end)
test("publish failure cleans up before propagating", function()
    local f = fixture(); f.pause(false)
    f.observer.start(function(report) if report.phase == "complete" then error("publish failed") end end)
    assert(not pcall(function() f.tick(10) end)); assert(not f.observer.active())
    local _, cancelled = f.counts(); assert(cancelled == 1)
end)
test("failed replacement clears the old published capture", function()
    local f = fixture(); f.observer.start(f.publish)
    f.player.GetWorld = function() return nil end
    assert(not pcall(f.observer.start, f.publish))
    assert(not f.observer.active() and f.reports[#f.reports].phase == "failed" and f.reports[#f.reports].report == "")
end)
test("name table is bounded and truncation is explicit", function()
    local f = fixture(); f.pause(false); f.play(true); local section = 0
    f.anim.Montage_GetCurrentSection = function() section = section + 1; return "Section" .. section end
    f.observer.start(f.publish)
    for _ = 1, 20 do f.tick() end
    local result = f.reports[#f.reports]
    assert(not f.observer.active() and result.truncated and result.records == 15)
    assert(result.status:find("Identity limit", 1, true) and #result.report <= 14000)
end)
test("initial publisher failure leaves no active timer", function()
    local f = fixture()
    assert(not pcall(f.observer.start, function() error("initial publication refused") end))
    assert(not f.observer.active()); local scheduled = f.counts(); assert(scheduled == 0)
end)
print(total .. " attack observation groups passed")
