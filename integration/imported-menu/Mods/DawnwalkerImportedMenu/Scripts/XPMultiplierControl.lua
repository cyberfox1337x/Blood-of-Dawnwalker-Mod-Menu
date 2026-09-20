local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("xp_multiplier_control")

--[[
Multiplies quest XP by re-running the game's own award call.

Why not the reward tables: DWXPRewards scales the rows in LoadedQuestXPRewardTable and
LoadedCombatRewardsTable, and live testing showed the granted XP does not follow those
edits - the values are read somewhere the table write does not reach. That control stays
refused rather than pretending.

The subsystem exposes exactly one way to grant XP:

    int32 AddQuestXP(EQuestExperienceRewardAmount RewardAmount)

There is no arbitrary "add N XP". So an integer multiplier is expressed the only honest
way available: when the game awards a reward tier, award the same tier (factor - 1) more
times. The extra grants go through the game's own code path, so whatever the tier is
worth at that moment is what gets added.

Scope, stated plainly: this covers XP granted through AddQuestXP. Combat rewards that do
not route through it are unaffected, which is why the control is named for quest XP.

Reentrancy is the one real hazard: each extra call re-enters this same post hook. The
guard below is what stops that becoming an infinite grant.
]]

local M = {}

local CLASS = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"
local AWARD = CLASS .. ":AddQuestXP"
local MIN_FACTOR, MAX_FACTOR = 1, 5

local function wholeNumber(value, low, high)
    return type(value) == "number" and value == value and value % 1 == 0 and value >= low and value <= high
end

function M.New(deps)
    for _, name in ipairs({ "subsystem", "register_hook", "unregister_hook" }) do
        assert(type(deps[name]) == "function", "XP multiplier dependency missing: " .. name)
    end
    local log = deps.log or function() end

    local factor = MIN_FACTOR
    local hookIds = nil
    -- True only while this module is issuing its own extra grants. Without it every
    -- extra AddQuestXP would re-enter the hook and grant again, without end.
    local granting = false
    local ownerAddress = nil
    local telemetry = { awards = 0, extras = 0, foreign = 0, skipped = 0, errors = 0 }

    local function count(key) telemetry[key] = math.min(telemetry[key] + 1, 2147483647) end

    -- The receiver must be the subsystem this session owns. A grant on anything else is
    -- not ours to amplify.
    local function ownedReceiver(receiver)
        if not ownerAddress then return nil end
        local subsystem = deps.subsystem()
        if not subsystem or subsystem:GetAddress() ~= ownerAddress then return nil end
        if not receiver or receiver:IsValid() ~= true or receiver:GetAddress() ~= ownerAddress then return nil end
        return subsystem
    end

    local function onAward(context, _returned, rewardParameter)
        if granting or factor <= MIN_FACTOR then return end
        local ok, failure = pcall(function()
            local receiver = context and context:get()
            local subsystem = ownedReceiver(receiver)
            if not subsystem then count("foreign"); return end
            local reward = rewardParameter and rewardParameter:get()
            -- Reward 0 is None; repeating it would grant nothing and log noise.
            if not wholeNumber(reward, 1, 255) then count("skipped"); return end
            count("awards")
            granting = true
            for _ = 2, factor do
                subsystem:AddQuestXP(reward)
                count("extras")
            end
        end)
        -- Never return a value here: UE4SS would replace the native return.
        granting = false
        if not ok then
            count("errors")
            log("XP_MULTIPLIER award failed: " .. tostring(failure))
        end
    end

    local function attach()
        if hookIds then return end
        local subsystem = deps.subsystem()
        assert(subsystem and subsystem:IsValid() == true, "XP subsystem unavailable")
        ownerAddress = subsystem:GetAddress()
        assert(type(ownerAddress) == "number" and ownerAddress > 0, "XP subsystem address invalid")
        local pre, post = deps.register_hook(AWARD, function() end, onAward)
        hookIds = { pre = pre, post = post }
        log("XP_MULTIPLIER attached to " .. AWARD)
    end

    local function detach()
        if not hookIds then return end
        local ids = hookIds
        hookIds = nil
        ownerAddress = nil
        local ok, failure = pcall(deps.unregister_hook, AWARD, ids.pre, ids.post)
        if not ok then log("XP_MULTIPLIER detach failed: " .. tostring(failure)) end
    end

    return {
        set = function(value)
            assert(wholeNumber(value, MIN_FACTOR, MAX_FACTOR),
                string.format("Quest XP multiplier must be a whole number from %d to %d", MIN_FACTOR, MAX_FACTOR))
            if value == MIN_FACTOR then
                detach()
                factor = MIN_FACTOR
                return
            end
            attach()
            factor = value
        end,
        factor = function() return factor end,
        currentXP = function()
            local subsystem = deps.subsystem()
            assert(subsystem and subsystem:IsValid() == true, "XP subsystem unavailable")
            local value = subsystem:GetCurrentXP()
            assert(wholeNumber(value, 0, 2147483647), "The game returned no usable XP total")
            return value
        end,
        active = function() return hookIds ~= nil and factor > MIN_FACTOR end,
        -- Called when the player session changes: the old subsystem is gone.
        reset = function()
            detach()
            factor = MIN_FACTOR
        end,
        snapshot = function()
            return string.format("factor=%d awards=%d extras=%d foreign=%d skipped=%d errors=%d",
                factor, telemetry.awards, telemetry.extras, telemetry.foreign, telemetry.skipped, telemetry.errors)
        end,
    }
end

function M.Init(menu, helpers, options)
    options = options or {}
    local section = "DWXPMultiplier"
    local log = options.log or function() end
    local library = "/Script/Engine.Default__SubsystemBlueprintLibrary"

    local control = M.New({
        subsystem = function()
            local player = helpers.GetPlayer()
            if not player or player:IsValid() ~= true then return nil end
            local blueprintLibrary, class = StaticFindObject(library), StaticFindObject(CLASS)
            if not blueprintLibrary or not class then return nil end
            local subsystem = blueprintLibrary:GetGameInstanceSubsystem(player, class)
            if not subsystem or subsystem:IsValid() ~= true then return nil end
            return subsystem
        end,
        register_hook = options.registerHook or RegisterHook,
        unregister_hook = options.unregisterHook or UnregisterHook,
        log = log,
    })

    local field = { type = "number", id = "factor", label = "Quest XP multiplier",
        min = MIN_FACTOR, max = MAX_FACTOR, step = 1, default = MIN_FACTOR,
        onChange = function(value)
            ExecuteInGameThread(function()
                local ok, failure = pcall(control.set, value)
                menu.Set(section, "factor", control.factor())
                menu.SetLabel(section, "status", ok
                    and (control.active()
                        and string.format("x%d: each quest XP award is granted %d times through the game's own reward call.", control.factor(), control.factor())
                        or "Off: quest XP is awarded normally.")
                    or ("Quest XP multiplier failed: " .. tostring(failure):gsub("^.-:%d+:%s*", "")))
                if not ok then log("XP_MULTIPLIER set failed: " .. tostring(failure)) end
            end)
        end }

    menu.Register({ id = section, title = "✦ Quest XP multiplier", tab = "♡ Player", items = {
        field,
        { type = "label", id = "status", label = "Off: quest XP is awarded normally." },
        { type = "button", id = "report", label = "Read multiplier activity", onClick = function()
            ExecuteInGameThread(function()
                local ok, xp = pcall(control.currentXP)
                menu.SetLabel(section, "activity", control.snapshot()
                    .. (ok and (" currentXP=" .. tostring(xp)) or " currentXP=unavailable"))
            end)
        end },
        { type = "label", id = "activity", label = "factor=1 awards=0 extras=0 foreign=0 skipped=0 errors=0" },
        { type = "label",
          label = "Repeats the game's own AddQuestXP call, so each extra grant is worth exactly what the reward tier is worth. Covers XP granted through that call; combat rewards that bypass it are unaffected." },
    } })

    return {
        ResetSession = function()
            control.reset()
            menu.Set(section, "factor", MIN_FACTOR)
            menu.SetLabel(section, "status", "Off: quest XP is awarded normally.")
        end,
    }
end

return M
