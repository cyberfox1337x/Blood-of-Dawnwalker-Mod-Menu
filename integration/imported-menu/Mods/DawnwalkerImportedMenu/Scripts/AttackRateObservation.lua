local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("attack_rate_observation")
local M = {}
local ATTRIBUTE = "AttackSpeedMultiplierAdditive"
local MAX_ROWS, MAX_NAMES, MAX_REPORT = 100, 16, 14000
local function valid(object) return object and object:IsValid() end
local function finite(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Nonfinite animation observation")
    return value
end
local function address(object)
    assert(valid(object), "Animation observation object unavailable")
    local result = finite(object:GetAddress())
    assert(result > 0, "Animation observation address invalid")
    return result
end
local function text(value, limit)
    if type(value) ~= "string" then value = value:ToString() end
    assert(type(value) == "string" and #value <= limit and not value:find("[%c]"), "Animation observation text invalid")
    return value
end
local function checked(object, class)
    assert(valid(object) and object:IsA(class), "Animation observation class mismatch: " .. class)
    address(object)
    return object
end

-- Public output contains strings/counts only. UObject wrappers stay inside this
-- short-lived capture; there are no montage/attribute setters or input actions.
function M.New(helpers, deps)
    deps = deps or {}
    local state, timer, generation, publisher = nil, nil, 0, nil
    local schedule = deps.schedule or LoopInGameThreadWithDelay
    local cancel = deps.cancel or CancelDelayedAction
    local function cancelTimer()
        generation = generation + 1
        state = nil
        if timer ~= nil then
            cancel(timer)
            timer = nil
        end
    end
    local function publish(result)
        local ok, failure = pcall(publisher, result)
        if not ok then
            local cleaned, cleanup = pcall(cancelTimer)
            error(tostring(failure) .. (cleaned and "" or "; timer cleanup pending: " .. tostring(cleanup)), 0)
        end
    end
    local function library()
        if deps.library then return deps.library end
        local result = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        assert(valid(result) and result:GetFullName() == "GameplayStatics /Script/Engine.Default__GameplayStatics", "Animation observation clock library unavailable")
        return result
    end
    local function snapshot()
        assert((deps.inGameThread or IsInGameThread)() == true, "Animation observation requires game thread")
        local player = checked(helpers.GetPlayer(), "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
        local world = checked(player:GetWorld(), "/Script/Engine.World")
        local controller = checked(player.Controller, "/Script/Engine.PlayerController")
        assert(address(controller.Pawn) == address(player) and address(controller:GetWorld()) == address(world), "Animation observation controlled pawn mismatch")
        local mesh = checked(player.Mesh, "/Script/Engine.SkeletalMeshComponent")
        assert(address(mesh:GetOwner()) == address(player), "Animation mesh owner mismatch")
        local combat = checked(player.CombatComponent, "/Script/DogwoodCombat.PlayerCombatComponent")
        assert(address(combat:GetOwner()) == address(player) and combat:IsAlive(), "Animation combat owner unavailable")
        local attributes = checked(player.CharacterAttributeSet, "/Script/DogwoodStats.CharacterBaseAttributeSet")
        assert(address(attributes:GetOuter()) == address(player), "Animation attribute owner mismatch")
        local animations = { checked(mesh:GetAnimInstance(), "/Script/Engine.AnimInstance") }
        local cached = combat.CachedAnimInstance
        if valid(cached) and address(cached) ~= address(animations[1]) then
            animations[2] = checked(cached, "/Script/Engine.AnimInstance")
        end
        local identities = { address(player), address(world), address(controller), address(mesh), address(combat), address(attributes) }
        for _, anim in ipairs(animations) do
            assert(address(anim:GetOwningActor()) == address(player), "Animation instance owner mismatch")
            identities[#identities + 1] = address(anim)
        end
        local clock = library()
        local paused = clock:IsGamePaused(player)
        assert(type(paused) == "boolean", "Animation pause state unavailable")
        local attribute = attributes[ATTRIBUTE]
        return { key = table.concat(identities, ":"), animations = animations,
            real = finite(clock:GetRealTimeSeconds(player)), game = finite(clock:GetTimeSeconds(player)), paused = paused,
            base = finite(attribute.BaseValue), bonus = finite(attribute.CurrentValue) }
    end
    local function report(capture)
        local parts = { "Named montages only; attack type is not inferred.",
            "rows: real_s,game_s,anim,clip,section,position,rate,effective,bonus" }
        for index, name in ipairs(capture.names) do parts[#parts + 1] = index .. "=" .. name end
        for _, row in ipairs(capture.rows) do parts[#parts + 1] = row end
        local result = table.concat(parts, "\n")
        assert(#result <= MAX_REPORT, "Animation report exceeds transport bounds")
        return result
    end
    local function finish(message, truncated)
        local capture = assert(state)
        local body = report(capture)
        cancelTimer()
        if #capture.rows == 0 then message = message .. " No playing montage was observed." end
        publish({ phase = "complete", status = message, report = body, records = #capture.rows, truncated = truncated == true })
    end
    local function nameIndex(capture, kind, value)
        local key = kind .. ":" .. value
        local existing = capture.nameIndexes[key]
        if existing then return existing end
        if #capture.names >= MAX_NAMES then return nil end
        capture.names[#capture.names + 1] = key
        capture.nameIndexes[key] = #capture.names
        return #capture.names
    end
    local function sample(capture, current)
        for animIndex, anim in ipairs(current.animations) do
            local montage = anim:GetCurrentActiveMontage()
            if valid(montage) then
                checked(montage, "/Script/Engine.AnimMontage")
                local playing = anim:Montage_IsPlaying(montage)
                assert(type(playing) == "boolean", "Montage playing state unavailable")
                if playing then
                    local name = text(montage:GetFullName(), 512) .. "@" .. address(montage)
                    local section = text(anim:Montage_GetCurrentSection(montage), 128)
                    local clipId = nameIndex(capture, "montage", name)
                    local sectionId = nameIndex(capture, "section", section)
                    if not clipId or not sectionId then return "Identity limit reached; capture truncated." end
                    local position = finite(anim:Montage_GetPosition(montage))
                    local rate = finite(anim:Montage_GetPlayRate(montage))
                    local effective = finite(anim:Montage_GetEffectivePlayRate(montage))
                    assert(position >= 0, "Negative montage position")
                    local row = string.format("%.4g,%.4g,%d,%d,%d,%.5g,%.5g,%.5g,%.5g",
                        current.real - capture.started, current.game - capture.gameStart, animIndex, clipId, sectionId, position, rate, effective, current.bonus)
                    -- Reserve enough room for the complete identity dictionary,
                    -- row heading and summary before accepting another sample.
                    if capture.rowBytes + #row + 1 > 4800 then return "Report size limit reached; capture truncated." end
                    capture.rows[#capture.rows + 1] = row
                    capture.rowBytes = capture.rowBytes + #row + 1
                    if #capture.rows >= MAX_ROWS then return "100-record limit reached; capture truncated." end
                end
            end
        end
        return nil
    end
    local function tick(token)
        if generation ~= token or not state then return end
        local ok, failure = pcall(function()
            local capture = state
            local current = snapshot()
            assert(current.key == capture.key, "Animation session changed; capture discarded")
            assert(current.real >= capture.lastReal and current.game >= capture.lastGame, "Animation clock moved backwards")
            capture.lastReal, capture.lastGame = current.real, current.game
            if not capture.started then
                if current.real - capture.waitStart >= 30 then finish("Waiting for unpause expired while paused.", false); return end
                if current.paused then return end
                capture.started, capture.gameStart = current.real, current.game
                capture.base, capture.bonus = current.base, current.bonus
                publish({ phase = "sampling", status = "Observing named montages for up to 10 seconds.", report = "", records = 0, truncated = false })
            end
            assert(current.base == capture.base and current.bonus == capture.bonus, "Attack bonus changed; capture discarded")
            if current.paused then finish("Game paused; capture ended.", false); return end
            capture.ticks = capture.ticks + 1
            if current.real - capture.started >= 10 or capture.ticks > 200 then finish("Observation window ended.", false); return end
            local limited = sample(capture, current)
            local after = snapshot()
            assert(after.key == capture.key and after.base == capture.base and after.bonus == capture.bonus, "Animation session or attack bonus changed during read; capture discarded")
            if limited then finish(limited, true)
            elseif capture.ticks >= 200 then finish("200-callback limit reached.", true) end
        end)
        if not ok then
            local cleaned, cleanup = pcall(cancelTimer)
            local message = tostring(failure) .. (cleaned and "" or "; timer cleanup pending: " .. tostring(cleanup))
            publish({ phase = "failed", status = message, report = "", records = 0, truncated = false })
            error(message, 0)
        end
    end
    local function start(callback)
        assert(type(callback) == "function", "Animation report callback required")
        cancelTimer()
        publisher = callback
        local available, initial = pcall(snapshot)
        if not available then
            publish({ phase = "failed", status = tostring(initial), report = "", records = 0, truncated = false })
            error(initial, 0)
        end
        state = { key = initial.key, waitStart = initial.real, lastReal = initial.real, lastGame = initial.game,
            started = not initial.paused and initial.real or nil, gameStart = initial.game,
            base = initial.base, bonus = initial.bonus, ticks = 0, rows = {}, names = {}, nameIndexes = {}, rowBytes = 0 }
        publish({ phase = initial.paused and "waiting" or "sampling", status = initial.paused and "Waiting up to 30 seconds for unpause." or "Observing named montages for up to 10 seconds.", report = "", records = 0, truncated = false })
        local token = generation
        local ok, result = pcall(schedule, 50, function() tick(token) end)
        if not ok or result == nil then
            cancelTimer()
            local failure = ok and "Animation timer handle unavailable" or tostring(result)
            publish({ phase = "failed", status = failure, report = "", records = 0, truncated = false })
            error(failure, 0)
        end
        timer = result
    end
    local function stop(message)
        cancelTimer()
        if publisher then publish({ phase = "stopped", status = message or "Observation stopped; capture cleared.", report = "", records = 0, truncated = false }) end
    end
    return { start = start, stop = stop, ResetSession = function() stop("Player session changed; capture cleared.") end,
        active = function() return state ~= nil or timer ~= nil end }
end
return M
