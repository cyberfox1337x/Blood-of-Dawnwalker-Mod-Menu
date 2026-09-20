local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("fall_damage_observation")
local M = {}
M.FALL = "/Script/Dawnwalker.FallDamageComponent:OnMovementModeChanged"
M.MAGNITUDE = "/Script/GameplayAbilities.GameplayModMagnitudeCalculation:CalculateBaseMagnitude"
local EFFECT = "/Game/_Dawnwalker/Player/FallDamage/GE_FallDamage.Default__GE_FallDamage_C"
local function address(object)
    assert(object and object:IsValid(), "Fall observation object unavailable")
    return tostring(object:GetAddress())
end
function M.New(deps)
    local hooks, stack, baseline = {}, {}, nil
    local state = { fallCalls = 0, playerFallCalls = 0, magnitudeCalls = 0, scopedCalls = 0, exactSpecCalls = 0, failures = 0 }
    local function increment(key) state[key] = math.min(state[key] + 1, 2147483647) end
    local function current()
        local player = deps.GetPlayer()
        return { player = address(player), world = address(player:GetWorld()), component = address(player.FallDamageComponent) }
    end
    local function same()
        local now = current()
        assert(now.player == baseline.player and now.world == baseline.world and now.component == baseline.component,
            "Fall observation session changed")
    end
    local function observe(callback)
        -- Hooks deliberately return nothing: neither arguments nor results change.
        return function(...)
            local ok, cause = pcall(callback, ...)
            if not ok then increment("failures"); state.lastError = tostring(cause); stack = {} end
        end
    end
    local function stop()
        for index = #hooks, 1, -1 do
            local hook = hooks[index]
            deps.UnregisterHook(hook.path, hook.pre, hook.post)
            table.remove(hooks, index)
        end
        stack = {}; baseline = nil
    end
    local function start()
        assert(#hooks == 0, "Fall observation already active")
        baseline = current()
        local effect = deps.StaticFindObject(EFFECT)
        local effectAddress = address(effect)
        local function install(path, before, after)
            address(deps.StaticFindObject(path))
            local pre, post = deps.RegisterHook(path, before, after)
            assert(type(pre) == "number" and type(post) == "number", "Fall hook identifiers unavailable")
            hooks[#hooks + 1] = { path = path, pre = pre, post = post }
        end
        local ok, cause = pcall(function()
            install(M.FALL, observe(function(receiver, character)
                same(); increment("fallCalls")
                assert(#stack < 16, "Fall scope depth exceeded")
                local owned = address(receiver:get()) == baseline.component and address(character:get()) == baseline.player
                stack[#stack + 1] = owned
                if owned then increment("playerFallCalls") end
            end), observe(function()
                assert(#stack > 0, "Fall scope post without pre")
                table.remove(stack)
            end))
            install(M.MAGNITUDE, observe(function(_, spec)
                same(); increment("magnitudeCalls")
                if stack[#stack] ~= true then return end
                increment("scopedCalls")
                local raw = spec:get()
                if address(raw.Def) == effectAddress then increment("exactSpecCalls") end
            end), observe(function() end))
        end)
        if not ok then
            local cleaned, cleanupError = pcall(stop)
            error(tostring(cause) .. (cleaned and "" or "; hook cleanup failed: " .. tostring(cleanupError)))
        end
    end
    return { start = start, stop = stop, snapshot = function()
        local copy = {}; for key, value in pairs(state) do copy[key] = value end
        copy.active, copy.depth, copy.mutationAuthorized = #hooks > 0, #stack, false
        return copy
    end }
end
return M
