local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("xp_award_dispatch_observation")
local M = {}
local CLASS = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"
local GETTER, AWARD = CLASS .. ":GetXPAmountByRewardType", CLASS .. ":AddQuestXP"
local MAX_COUNT, MAX_DEPTH = 1000000, 16
local function integer(value, maximum)
    return type(value) == "number" and value == value and value >= 0 and value <= maximum and value % 1 == 0
end
local function unwrap(value) return value:get() end
function M.New(deps)
    assert(type(deps) == "table" and type(deps.get_context) == "function"
        and type(deps.game_thread) == "function" and type(deps.validate_functions) == "function"
        and type(deps.register_hook) == "function" and type(deps.unregister_hook) == "function", "XP observation dependencies required")
    local api, hooks, counters, rewards = {}, {}, {}, {}
    local active, identity, subsystemId, problem = false, nil, nil, nil
    local awardStack, getterStack, directDepth = {}, {}, 0
    local function increment(name)
        counters[name] = math.min(MAX_COUNT, (counters[name] or 0) + 1)
    end
    local function fail(reason)
        active = false
        if not problem then problem = tostring(reason):sub(1, 512) end
    end
    local function context()
        assert(deps.game_thread() == true, "XP observation requires the game thread")
        local current = deps.get_context()
        assert(type(current) == "table" and type(current.sessionId) == "string"
            and #current.sessionId > 0 and #current.sessionId <= 256, "XP session identity unavailable")
        local subsystem = current.subsystem
        assert(subsystem and subsystem:IsValid() == true and subsystem:IsA(CLASS), "XP subsystem unavailable")
        local address = subsystem:GetAddress()
        assert(type(address) == "number" and address > 0, "XP subsystem address invalid")
        return subsystem, current.sessionId, address
    end
    local function scoped(remote)
        local subsystem, session, address = context()
        if session ~= identity or address ~= subsystemId then fail("XP session changed; remove observation hooks"); return false end
        local receiver = unwrap(remote)
        if not receiver or receiver:IsValid() ~= true or not receiver:IsA(CLASS)
            or receiver:GetAddress() ~= subsystem:GetAddress() then increment("foreign_calls"); return false end
        return true
    end
    local function callback(body)
        return function(...)
            if not active then return end
            local ok, reason = pcall(body, ...)
            if not ok then increment("callback_errors"); fail(reason) end
            -- Never return a value: UE4SS would replace the native return value.
        end
    end
    local function reward(remote)
        local value = unwrap(remote)
        assert(integer(value, 255), "XP reward enum outside observation bounds")
        return value
    end
    local function getterPre(receiver, rewardParam)
        if not scoped(receiver) then return end
        assert(#getterStack < MAX_DEPTH, "Getter observation nesting limit exceeded")
        local category = reward(rewardParam)
        local route = directDepth > 0 and "direct" or #awardStack > 0 and "inside_award" or "outside_award"
        getterStack[#getterStack + 1] = { category = category, route = route }
        increment("getter_pre"); increment("getter_" .. route)
        if route == "inside_award" then
            for _, frame in ipairs(awardStack) do frame.getters = math.min(MAX_COUNT, frame.getters + 1) end
        end
    end
    local function getterPost(receiver, resultParam, rewardParam)
        if not scoped(receiver) then return end
        local frame = table.remove(getterStack)
        assert(frame and frame.category == reward(rewardParam), "Getter pre/post correlation differs")
        local result = unwrap(resultParam)
        assert(integer(result, 2147483647), "XP getter result is not a nonnegative int32")
        increment("getter_post")
        local key = tostring(frame.category)
        local row = rewards[key] or { rewardType = frame.category, observations = 0 }
        row.observations = math.min(MAX_COUNT, row.observations + 1)
        row.lastAmount, row.lastRoute = result, frame.route
        rewards[key] = row
    end
    local function awardPre(receiver, rewardParam)
        if not scoped(receiver) then return end
        assert(#awardStack < MAX_DEPTH, "Award observation nesting limit exceeded")
        awardStack[#awardStack + 1] = { category = reward(rewardParam), getters = 0 }
        increment("award_pre")
    end
    local function awardPost(receiver, resultParam, rewardParam)
        if not scoped(receiver) then return end
        local frame = table.remove(awardStack)
        assert(frame and frame.category == reward(rewardParam), "Award pre/post correlation differs")
        assert(integer(unwrap(resultParam), 2147483647), "Award return is not a nonnegative int32")
        increment("award_post")
        increment(frame.getters > 0 and "awards_with_getter_dispatch" or "awards_without_getter_dispatch")
    end
    function api.Snapshot()
        local result = { active = active, cleanupPending = not active and #hooks > 0, hooksInstalled = #hooks, sessionId = identity,
            subsystemAddress = subsystemId and tostring(subsystemId) or nil, error = problem,
            counters = {}, rewards = {}, awardDepth = #awardStack, getterDepth = #getterStack,
            multiplierVerified = false, observationOnly = true }
        for key, value in pairs(counters) do result.counters[key] = value end
        for _, row in pairs(rewards) do
            result.rewards[#result.rewards + 1] = { rewardType = row.rewardType, observations = row.observations,
                lastAmount = row.lastAmount, lastRoute = row.lastRoute }
        end
        table.sort(result.rewards, function(left, right) return left.rewardType < right.rewardType end)
        return result
    end
    function api.Stop()
        assert(deps.game_thread() == true, "Hook cleanup requires the game thread")
        active = false
        local failures = {}
        for index = #hooks, 1, -1 do
            local record = hooks[index]
            local ok, reason = pcall(deps.unregister_hook, record.path, record.pre, record.post)
            if ok then table.remove(hooks, index) else failures[#failures + 1] = tostring(reason):sub(1, 256) end
        end
        awardStack, getterStack, directDepth = {}, {}, 0
        if #failures > 0 then fail("Hook cleanup incomplete: " .. table.concat(failures, " | ")); return false, problem end
        return true
    end
    function api.Start()
        assert(#hooks == 0 and not active, "Stop existing observation hooks before starting")
        local _, session, address = context()
        assert(deps.validate_functions(GETTER, AWARD) == true, "Current XP UFunction signatures are not verified")
        identity, subsystemId, problem = session, address, nil
        counters, rewards = {}, {}
        local ok, reason = pcall(function()
            for _, spec in ipairs({ { GETTER, getterPre, getterPost }, { AWARD, awardPre, awardPost } }) do
                local pre, post = deps.register_hook(spec[1], callback(spec[2]), callback(spec[3]))
                hooks[#hooks + 1] = { path = spec[1], pre = pre, post = post }
                assert(integer(pre, 2147483647) and integer(post, 2147483647), "Hook registration did not return a paired ID")
            end
        end)
        if not ok then fail(reason); api.Stop(); return false, problem end
        active = true
        return true
    end
    function api.RefreshSession()
        if #hooks == 0 then return true end
        local ok, _, session, address = pcall(context)
        if not ok or session ~= identity or address ~= subsystemId then fail("XP session changed or became unavailable") end
        if not active then return api.Stop() end
        return true
    end
    function api.ReadGetter(category)
        assert(active and integer(category, 255), "Active observation and bounded reward category required")
        local subsystem, session, address = context()
        assert(session == identity and address == subsystemId, "XP session changed before direct getter")
        assert(directDepth < MAX_DEPTH, "Direct getter nesting limit exceeded")
        directDepth = directDepth + 1
        local ok, result = pcall(function() return subsystem:GetXPAmountByRewardType(category) end)
        directDepth = directDepth - 1
        if not ok then error(result) end
        assert(integer(result, 2147483647), "XP getter result is not a nonnegative int32")
        return result
    end
    return api
end
return M
