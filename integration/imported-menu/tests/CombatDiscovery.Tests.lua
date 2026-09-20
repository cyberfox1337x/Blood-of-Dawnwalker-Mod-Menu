local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("combat_discovery_tests")
local path = assert(arg[1], "Pass CombatDiscovery.lua path")
local function object(className, name, address)
    return { IsValid = function() return true end, IsA = function(_, requested) return requested == className end,
        GetFullName = function() return name end, GetAddress = function() return address end }
end
local function fixture(attackPilot, attackObserver)
    local queue, labels, registrations, reads, values = {}, {}, {}, 0, {}
    local player = object("/Script/Dawnwalker.DawnwalkerPlayerCharacter", "Player", 10)
    local world = object("/Script/Engine.World", "World", 20)
    player.GetWorld = function() return world end
    local controller = object("/Script/Engine.PlayerController", "Controller", 30)
    controller.Pawn = player; player.Controller = controller
    controller.GetWorld = function() return world end
    local combat = object("/Script/DogwoodCombat.PlayerCombatComponent", "Combat", 40)
    combat.GetOwner = function() return player end
    combat.IsAlive = function() return true end
    player.CombatComponent = combat
    local config = object("/Script/DogwoodCombat.CombatConfig", "Config", 50)
    combat.Config = config; combat.GetConfig = function() return config end
    local modes = {}
    for index = 1, 5 do
        local mode = object("/Script/DogwoodCombat.CombatMode", "Mode" .. index, 60 + index)
        mode.MetricsScalingSettings = { AttackPlayrate = 1, StrongAttackPlayrate = 1.2,
            DodgePlayrate = 0.8, BlockPlayrate = 0.9, DefaultRootMotionScaling = 1 }
        modes[index] = mode
    end
    config.CombatModes = { Contains = function(_, index) return modes[index] ~= nil end,
        Find = function(_, index) return modes[index] end }
    local environment = setmetatable({ IsInGameThread = function() return true end,
        ExecuteInGameThread = function(callback) queue[#queue + 1] = callback end }, { __index = _G })
    local module = assert(loadfile(path, "t", environment))()
    module.Init({ Register = function(section) registrations[#registrations + 1] = section end,
        SetLabel = function(_, id, text) labels[id] = text end,
        Set = function(_, id, value) values[id] = value end },
        { GetPlayer = function() reads = reads + 1; return player end }, attackPilot, attackObserver)
    local function inspect()
        registrations[1].items[2].onClick()
        assert(#queue == 1, "Exactly one game-thread callback")
        local callback = table.remove(queue, 1)
        return pcall(callback)
    end
    local function inspectEffect()
        local action
        for _, item in ipairs(registrations[1].items) do if item.id == "inspectEffect" then action = item end end
        assert(action, "Missing explicit effect inspection action")
        action.onClick()
        return pcall(table.remove(queue, 1))
    end
    return { invokeAttack = function(id, value)
            for _, item in ipairs(registrations[1].items) do
                if item.id == id then
                    if item.onClick then item.onClick() else item.onChange(value) end
                    return pcall(table.remove(queue, 1))
                end
            end
            error("Attack action missing")
        end, values = values, inspect = inspect, module = module, player = player, combat = combat, config = config,
        modes = modes, labels = labels, reads = function() return reads end, inspectEffect = inspectEffect, environment = environment }
end
local count = 0
local function effectFixture()
    local env = fixture()
    local asc = object("/Script/Dawnwalker.DawnwalkerAbilitySystemComponent", "ASC", 101)
    local attributes = object("/Script/DogwoodStats.CharacterBaseAttributeSet", "Attributes", 102)
    asc.GetOuter = function() return env.player end; attributes.GetOuter = asc.GetOuter
    env.player.AbilitySystemComponent = asc; env.player.CharacterAttributeSet = attributes
    attributes.AttackSpeedMultiplierAdditive = { BaseValue = 0, CurrentValue = 0.1 }
    local root = "/Game/_Dawnwalker/Combat/Focus/Sword/SwiftAdvance/GE_SwiftAdvance_AttackSpeed_Lvl1"
    local class = object("class", "BlueprintGeneratedClass " .. root .. ".GE_SwiftAdvance_AttackSpeed_Lvl1_C", 103)
    local cdo = object("effect", "GE_SwiftAdvance_AttackSpeed_Lvl1_C " .. root .. ".Default__GE_SwiftAdvance_AttackSpeed_Lvl1_C", 104)
    class.GetCDO = function() return cdo end; cdo.GetClass = function() return class end
    local owner = object("class", "Class /Script/DogwoodStats.CharacterBaseAttributeSet", 105)
    local descriptor = { AttributeName = "AttackSpeedMultiplierAdditive", AttributeOwner = owner, GetStructAddress = function() return 110 end }
    cdo.Modifiers = { { Attribute = descriptor } }
    cdo.DurationPolicy = 2; cdo.Executions = {}; cdo.GEComponents = {}
    local library = object("library", "AbilitySystemBlueprintLibrary /Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary", 106)
    library.GetAbilitySystemComponent = function() return asc end
    library.GetDebugStringFromGameplayAttribute = function(_, d) assert(d == descriptor); return "CharacterBaseAttributeSet.AttackSpeedMultiplierAdditive" end
    asc.GetGameplayAttributeValue = function(_, d, out) assert(d == descriptor); out.bFound = true; return attributes.AttackSpeedMultiplierAdditive.CurrentValue end
    asc.GetGameplayEffectCount = function() return 0 end
    env.environment.StaticFindObject = function(path)
        if path == root .. ".GE_SwiftAdvance_AttackSpeed_Lvl1_C" then return class end
        if path == root .. ".Default__GE_SwiftAdvance_AttackSpeed_Lvl1_C" then return cdo end
        if path == "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary" then return library end
    end
    for _, method in ipairs({ "StaticConstructObject", "LoadAsset", "RegisterHook" }) do env.environment[method] = function() error("Mutation or autoload forbidden") end end
    env.asc, env.attributes, env.cdo, env.descriptor = asc, attributes, cdo, descriptor
    return env
end
local function test(name, callback)
    callback(); count = count + 1; print("PASS " .. name)
end
test("inert initialization and complete five-mode read", function()
    local env = fixture(); assert(env.reads() == 0)
    assert(env.inspect()); assert(env.labels.mode5:find("Fistfight", 1, true))
    assert(env.labels.mode1:find("AttackPlayrate=1", 1, true))
    assert(env.modes[1].MetricsScalingSettings.StrongAttackPlayrate == 1.2)
    env.module.ResetSession(); assert(env.labels.mode1 == "" and env.labels.target == "No current capture.")
end)
test("missing mode clears stale successful report", function()
    local env = fixture(); assert(env.inspect()); env.modes[4] = nil
    assert(not env.inspect()); assert(env.labels.mode1 == "" and env.labels.status:find("Missing combat mode", 1, true))
end)
test("nonfinite metric rejected", function()
    local env = fixture(); env.modes[1].MetricsScalingSettings.AttackPlayrate = 0/0
    assert(not env.inspect()); assert(env.labels.mode1 == "")
end)
test("wrong component owner rejected", function()
    local env = fixture(); env.combat.GetOwner = function() return env.combat end
    assert(not env.inspect()); assert(env.labels.status:find("owner mismatch", 1, true))
end)
test("config getter disagreement rejected", function()
    local env = fixture(); env.combat.Config = object("/Script/DogwoodCombat.CombatConfig", "Other", 99)
    assert(not env.inspect()); assert(env.labels.status:find("disagree", 1, true))
end)
test("world transition discards partial observations", function()
    local env = fixture(); local calls = 0
    env.player.GetWorld = function()
        calls = calls + 1; return object("/Script/Engine.World", "World", calls == 1 and 20 or 21)
    end
    assert(not env.inspect()); assert(env.labels.mode1 == "" and env.labels.status:find("changed during capture", 1, true))
end)
test("CDO mode rejected", function()
    local env = fixture(); env.modes[2].GetFullName = function() return "Default__CombatMode" end
    assert(not env.inspect())
end)
test("wrapped mode entries supported", function()
    local env = fixture()
    env.config.CombatModes.Find = function(_, index) return { get = function() return env.modes[index] end } end
    assert(env.inspect())
end)
test("effect inspection stays loaded-only and clears stale results", function()
    local env = fixture(); env.environment.StaticFindObject = function() return nil end
    env.labels.effectAttribute = "stale"
    assert(not env.inspectEffect())
    assert(env.labels.effectAttribute == "" and env.labels.effectStatus:find("unavailable", 1, true))
    assert(env.reads() > 0)
end)
test("effect capture keeps observed data and marks unsupported optional schema incomplete", function()
    local env = effectFixture(); assert(env.reads() == 0)
    local ok, cause = env.inspectEffect(); assert(ok, tostring(cause))
    assert(env.labels.effectSchema:find("DurationPolicy=2", 1, true))
    assert(env.labels.effectAttribute:find("current=0.1", 1, true))
    assert(env.labels.effectStatus:find("INCOMPLETE", 1, true) and env.labels.effectStatus:find("StackingType unavailable", 1, true))
    assert(env.attributes.AttackSpeedMultiplierAdditive.BaseValue == 0)
    env.module.ResetSession(); assert(env.labels.effectAttribute == "")
end)
test("effect descriptor mismatch clears entire capture", function()
    local env = effectFixture(); assert(env.inspectEffect()); env.descriptor.AttributeName = "Other"
    assert(not env.inspectEffect()); assert(env.labels.effectSchema == "" and env.labels.effectAttribute == "")
end)
test("effect readback and ownership must agree", function()
    local env = effectFixture(); env.asc.GetGameplayAttributeValue = function(_, _, out) out.bFound = false; return 0.1 end
    assert(not env.inspectEffect()); assert(env.labels.effectStatus:find("readback mismatch", 1, true))
    env = effectFixture(); env.asc.GetOuter = function() return env.asc end
    assert(not env.inspectEffect()); assert(env.labels.effectStatus:find("ownership mismatch", 1, true))
end)
test("nonfinite attribute is rejected and oversized optional array reported incomplete", function()
    local env = effectFixture(); env.attributes.AttackSpeedMultiplierAdditive.CurrentValue = 0/0
    assert(not env.inspectEffect())
    env = effectFixture(); for index = 1, 65 do env.cdo.Executions[index] = {} end
    assert(env.inspectEffect()); assert(env.labels.effectStatus:find("Executions unavailable", 1, true))
end)
test("attack enable waits for successful roundtrip and session reset clears permission", function()
    local active, checks, changes = false, 0, 0
    local pilot = { owned = function() return active end, status = function() return "readback" end,
        roundtrip = function() checks = checks + 1 end,
        set = function(value) active = value; changes = changes + 1 end,
        reset = function() active = false end }
    local env = fixture(pilot)
    assert(not env.invokeAttack("attackEnabled", true) and changes == 0)
    assert(env.invokeAttack("attackCheck") and checks == 1)
    assert(env.invokeAttack("attackEnabled", true) and active and env.values.attackEnabled)
    env.module.ResetSession()
    assert(not active and not env.values.attackEnabled)
    assert(not env.invokeAttack("attackEnabled", true) and changes == 1)
    assert(env.invokeAttack("attackEnabled", false) and changes == 2)
end)
test("attack failures stay visible with recovery ownership", function()
    local pilot = { owned = function() return true end, status = function() return "unused" end,
        roundtrip = function() error("native removal pending") end,
        set = function() error("retry pending") end,
        reset = function() error("session cleanup pending") end }
    local env = fixture(pilot)
    assert(not env.invokeAttack("attackCheck"))
    assert(env.values.attackEnabled and env.labels.attackStatus:find("native removal pending", 1, true))
    assert(not env.invokeAttack("attackEnabled", false))
    assert(env.labels.attackStatus:find("retry pending", 1, true))
    env.labels.effectAttribute = "stale previous session"
    env.labels.mode1 = "stale previous session"
    assert(not pcall(env.module.ResetSession))
    assert(env.values.attackEnabled and env.labels.attackStatus:find("session cleanup pending", 1, true))
    assert(env.labels.effectAttribute == "" and env.labels.mode1 == "")
end)
test("read-only observation publishes and reset still restores when timer cleanup fails", function()
    local callback, restored
    local pilot = { owned = function() return false end, reset = function() restored = true end }
    local observer = { start = function(publish) callback = publish end,
        stop = function() callback({ status = "stopped", report = "" }) end,
        ResetSession = function() error("timer cleanup failed") end }
    local env = fixture(pilot, observer)
    assert(env.invokeAttack("attackObserve"))
    callback({ status = "captured", report = "native rates" })
    assert(env.labels.attackObservationReport == "native rates")
    assert(env.invokeAttack("attackObserveStop"))
    assert(env.labels.attackObservationReport == "")
    env.labels.attackObservationReport = "old session"
    assert(not pcall(env.module.ResetSession))
    assert(restored and env.labels.attackObservationReport == "")
    assert(env.labels.attackObservationStatus:find("timer cleanup failed", 1, true))
end)
print(tostring(count) .. " combat discovery groups passed")
