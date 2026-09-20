local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("xp_award_observation_tests")
local module = assert(loadfile(arg[1] or "analysis/dawnwalker-uue4ss/probes/DawnwalkerXPAwardObservation.lua"))()
local function fixture()
    local registry, removed, ids, calls = {}, {}, 0, 0
    local session, thread, verified, registerFailure, removeFailure = "session-a", true, true, false, nil
    local class = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"
    local getter, award = class .. ":GetXPAmountByRewardType", class .. ":AddQuestXP"
    local function object(address)
        return { IsValid = function() return true end, IsA = function(_, expected) return expected == class end,
            GetAddress = function() return address end }
    end
    local subsystem, foreign = object(10), object(20)
    local function remote(value) return { get = function() return value end, set = function() error("Mutation forbidden") end } end
    local function invoke(path, receiver, category, body)
        local hook = registry[path]
        if hook then assert(hook.before(remote(receiver), remote(category)) == nil) end
        local result = body and body() or 100
        if hook then assert(hook.after(remote(receiver), remote(result), remote(category)) == nil) end
        return result
    end
    function subsystem:GetXPAmountByRewardType(category)
        calls = calls + 1
        return invoke(getter, self, category)
    end
    local api = module.New({
        get_context = function() return { subsystem = subsystem, sessionId = session } end,
        game_thread = function() return thread end,
        validate_functions = function(left, right) assert(left == getter and right == award); return verified end,
        register_hook = function(path, before, after)
            if registerFailure and path == award then error("registration failed") end
            ids = ids + 2; registry[path] = { before = before, after = after, pre = ids - 1, post = ids }
            return ids - 1, ids
        end,
        unregister_hook = function(path, pre, post)
            assert(registry[path].pre == pre and registry[path].post == post)
            if path == removeFailure then error("removal failed") end
            removed[#removed + 1] = path; registry[path] = nil
        end,
    })
    return { api = api, registry = registry, getter = getter, award = award, removed = removed,
        getterCall = function(receiver) return invoke(getter, receiver or subsystem, 2) end,
        awardCall = function(withGetter) return invoke(award, subsystem, 2, function()
            if withGetter then return subsystem:GetXPAmountByRewardType(2) end
            return 100
        end) end,
        nestedAward = function()
            return invoke(award, subsystem, 2, function()
                return invoke(award, subsystem, 2, function() return subsystem:GetXPAmountByRewardType(2) end)
            end)
        end,
        recursiveAward = function(depth)
            local function recurse(n) return invoke(award, subsystem, 2, function() if n > 0 then return recurse(n - 1) end; return 100 end) end
            return recurse(depth)
        end,
        foreign = foreign, calls = function() return calls end,
        session = function() session = "session-b" end,
        thread = function(value) thread = value end,
        validation = function(value) verified = value end,
        failRegistration = function() registerFailure = true end,
        failRemoval = function(path) removeFailure = path end }
end
local total = 0
local function test(name, run) run(); total = total + 1; print("PASS " .. name) end
test("registration is explicit and requires verified loaded signatures", function()
    local f = fixture(); assert(next(f.registry) == nil and f.calls() == 0)
    f.validation(false); assert(not pcall(f.api.Start)); assert(next(f.registry) == nil)
    f.validation(true); assert(f.api.Start()); assert(not pcall(f.api.Start)); assert(f.api.Stop())
end)
test("direct getter is separate from award traversal and does not grant XP", function()
    local f = fixture(); f.api.Start(); assert(f.api.ReadGetter(2) == 100)
    local result = f.api.Snapshot(); assert(result.counters.getter_direct == 1 and result.counters.award_pre == nil)
    assert(result.rewards[1].lastAmount == 100 and result.rewards[1].lastRoute == "direct")
    assert(f.calls() == 1 and result.multiplierVerified == false)
end)
test("native post callback reads ReturnValue before reward argument without replacing it", function()
    local f = fixture(); f.api.Start(); assert(f.awardCall(true) == 100)
    local counters = f.api.Snapshot().counters
    assert(counters.award_pre == 1 and counters.award_post == 1 and counters.getter_inside_award == 1)
    assert(counters.awards_with_getter_dispatch == 1 and counters.getter_post == 1)
end)
test("award without reflected getter dispatch is recorded honestly", function()
    local f = fixture(); f.api.Start(); assert(f.awardCall(false) == 100)
    assert(f.api.Snapshot().counters.awards_without_getter_dispatch == 1 and f.calls() == 0)
    assert(f.getterCall() == 100); assert(f.api.Snapshot().counters.getter_outside_award == 1)
end)
test("nested awards retain getter traversal evidence for both dynamic scopes", function()
    local f = fixture(); f.api.Start(); assert(f.nestedAward() == 100)
    local state = f.api.Snapshot()
    assert(state.counters.award_post == 2 and state.counters.awards_with_getter_dispatch == 2)
    assert(state.awardDepth == 0 and state.getterDepth == 0)
end)
test("foreign subsystem calls cannot enter the target correlation stack", function()
    local f = fixture(); f.api.Start(); assert(f.getterCall(f.foreign) == 100)
    local state = f.api.Snapshot(); assert(state.counters.foreign_calls == 2 and state.counters.getter_pre == nil)
    assert(state.getterDepth == 0)
end)
test("session changes disable callbacks and paired hooks are removed on refresh", function()
    local f = fixture(); f.api.Start(); f.session(); assert(f.getterCall() == 100)
    assert(not f.api.Snapshot().active); assert(f.api.RefreshSession()); assert(#f.removed == 2)
    assert(not f.api.Snapshot().cleanupPending and f.api.Stop())
end)
test("partial registration rolls back the first complete hook pair", function()
    local f = fixture(); f.failRegistration(); assert(not f.api.Start())
    assert(#f.removed == 1 and next(f.registry) == nil and not f.api.Snapshot().active)
end)
test("failed removal retains only failed pair and retry never double unregisters", function()
    local f = fixture(); f.api.Start(); f.failRemoval(f.getter); assert(not f.api.Stop())
    assert(#f.removed == 1 and f.api.Snapshot().cleanupPending)
    assert(f.getterCall() == 100 and f.api.Snapshot().counters.getter_pre == nil)
    f.failRemoval(nil); assert(f.api.Stop()); assert(#f.removed == 2 and not f.api.Snapshot().cleanupPending)
end)
test("callback errors are contained with bounded nesting and no return override", function()
    local f = fixture(); f.api.Start(); assert(f.recursiveAward(20) == 100)
    local state = f.api.Snapshot(); assert(not state.active and state.awardDepth <= 16 and state.counters.callback_errors == 1)
    assert(f.api.Stop()); assert(f.api.Snapshot().awardDepth == 0)
end)
test("off-thread callbacks become inert until game-thread cleanup", function()
    local f = fixture(); f.api.Start(); f.thread(false); assert(f.getterCall() == 100)
    assert(not f.api.Snapshot().active); assert(not pcall(f.api.Stop))
    f.thread(true); assert(f.api.RefreshSession()); assert(#f.removed == 2)
end)
test("snapshot is scalar-only copied evidence and invalid enums are refused", function()
    local f = fixture(); f.api.Start(); assert(not pcall(f.api.ReadGetter, 256)); f.api.ReadGetter(2)
    local snapshot = f.api.Snapshot(); snapshot.rewards[1].lastAmount = 999; snapshot.counters.getter_direct = 99
    local again = f.api.Snapshot(); assert(again.rewards[1].lastAmount == 100 and again.counters.getter_direct == 1)
    f.api.Stop(); assert(not pcall(f.api.ReadGetter, 2))
end)
print(total .. " XP observation tests passed")
