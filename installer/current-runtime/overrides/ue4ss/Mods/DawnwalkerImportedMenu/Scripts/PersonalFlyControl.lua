local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("personal_fly_control")
local M = {}

local function preserveCallback(callback, synchronize)
    return function(...)
        local results = table.pack(pcall(callback, ...))
        synchronize()
        assert(results[1], results[2])
        return table.unpack(results, 2, results.n)
    end
end
M.PreserveCallback = preserveCallback

-- Read-only closure inspection keeps the user's separately installed original intact.
-- Never write an upvalue or assume a different FLY release has the same contract.
local function findUpvalue(callback, wanted, visited)
    visited = visited or {}
    if visited[callback] then return nil end
    visited[callback] = true
    for index = 1, 100 do
        local name, value = debug.getupvalue(callback, index)
        if not name then break end
        if name == wanted then return function() return select(2, debug.getupvalue(callback, index)) end end
        if type(value) == "function" then
            local result = findUpvalue(value, wanted, visited)
            if result then return result end
        end
    end
end
M.FindUpvalue = findUpvalue

local function readPinned(path, length, checksum)
    local file, openError = io.open(path, "rb")
    assert(file, "Cannot read personal FLY file " .. path .. ": " .. tostring(openError))
    local contents = file:read(length + 1)
    local closed, failure = file:close()
    assert(closed, failure)
    assert(contents and #contents == length, "Personal FLY file does not match the reviewed release")
    local hash = 2166136261
    for index = 1, #contents do hash = ((hash ~ contents:byte(index)) * 16777619) & 0xffffffff end
    assert(hash == checksum, "Personal FLY file changed; review it before loading")
    return contents
end

function M.Init(menu, helpers, runtime, path, canStart)
    local id = "DWPersonalFly"
    local stateReader, toggle, recovery, lastState
    local armed, armHandle = false, nil
    local synchronize
    local control = { type = "checkbox", id = "enabled", label = "Fly", default = false, enabled = false,
        onChange = function(enabled)
            return runtime.ExecuteInGameThread(function()
                local ok, failure = pcall(function() assert(M.Set, "Personal FLY is unavailable"); M.Set(enabled) end)
                if synchronize then synchronize() end
                assert(ok, failure)
            end)
        end }
    menu.Register({ id = id, title = "Fly", tab = "Player", items = {
        control,
        { type = "label", id = "status", label = "Personal FLY 1.0.4 is unavailable." },
    } })
    local function state()
        assert(stateReader, "Personal FLY is unavailable")
        local result = stateReader()
        assert(result == "OFF" or result == "ENTERING" or result == "FLYING"
            or result == "EXITING" or result == "FAULTED", "Unknown personal FLY state")
        return result
    end
    synchronize = function()
        if not stateReader then return end
        local current = armed and "ARMED" or state()
        control.enabled = current ~= "ENTERING" and current ~= "EXITING"
        if menu.Get(id, "enabled") ~= (current ~= "OFF") then menu.Set(id, "enabled", current ~= "OFF") end
        if current ~= lastState then
            lastState = current
            local messages = {
                OFF = "OFF. WASD moves; Shift rises; Ctrl descends; mouse wheel changes speed.",
                ARMED = "ON, waiting to fly: return to the game and resume play. OFF cancels.",
                ENTERING = "Starting flight. Return to the game and resume play.",
                FLYING = "ON. WASD moves; Shift rises; Ctrl descends; mouse wheel changes speed. OFF lands here.",
                EXITING = "Stopping flight and restoring movement and appearance.",
                FAULTED = "FLY reported a failure. Turn OFF to run its original recovery.",
            }
            menu.SetLabel(id, "status", messages[current])
        end
    end
    local function after(callback)
        return preserveCallback(callback, function()
            synchronize()
            assert(not stateReader or state() ~= "FAULTED", "FLY reported a failure; turn OFF to recover")
        end)
    end
    local environment = setmetatable({
        package = { loaded = {} },
        require = function(name)
            if name == "UEHelpers" then return helpers end
            assert(name == "config", "Unexpected personal FLY dependency")
            return assert(load(readPinned(path .. "config.lua", 1721, 0x8c80440a), "@personal-fly-config", "t", {}))()
        end,
        RegisterKeyBind = function(_, modifiers, callback)
            -- Desktop switch owns activation. Do not install a second global hotkey.
            if type(modifiers) == "function" then
                assert(not toggle, "Unexpected additional personal FLY keybind")
                local reader = assert(findUpvalue(modifiers, "handle_toggle"), "FLY toggle contract changed")
                toggle = reader()
                stateReader = assert(findUpvalue(toggle, "state"), "FLY state contract changed")
            else recovery = assert(callback, "FLY recovery contract changed") end
        end,
        ExecuteInGameThread = function(callback) return runtime.ExecuteInGameThread(after(callback)) end,
        ExecuteInGameThreadWithDelay = function(delay, callback) return runtime.ExecuteWithDelay(delay, after(callback)) end,
        LoopInGameThreadAfterFrames = function(frames, callback) return runtime.LoopInGameThreadAfterFrames(frames, after(callback)) end,
        CancelDelayedAction = runtime.CancelDelayedAction,
    }, { __index = _G })
    local loaded, failure = pcall(function()
        assert(load(readPinned(path .. "main.lua", 94005, 0x22cb11b4), "@personal-fly-1.0.4", "t", environment))()
        assert(toggle and recovery and state() == "OFF", "Personal FLY initialization did not reach OFF")
    end)
    if not loaded then
        menu.SetLabel(id, "status", "Fly unavailable: " .. tostring(failure))
        return
    end
    local function stopArming()
        armed = false
        if armHandle then runtime.CancelDelayedAction(armHandle); armHandle = nil end
    end

    -- Flight changes the game's movement mode, and the movement component re-derives its
    -- JumpZVelocity for the gravity in force at that moment (450 became 450*sqrt(2) while
    -- airborne, measured 2026-09-18). After landing the game does not derive it again until
    -- the next jump, so the player is left jumping twice as high and Super Jump refuses to
    -- stack on a value that no longer matches the JumpVelocity attribute. The value the
    -- component held before the flight is recorded and, once the flight is over and the
    -- character is walking again with the attribute unchanged, put back.
    local JUMP_RESTORE_FRAMES = 900
    local jumpSnapshot, jumpRestoreHandle = nil, nil
    local function stopJumpRestore()
        if jumpRestoreHandle then runtime.CancelDelayedAction(jumpRestoreHandle); jumpRestoreHandle = nil end
    end
    local function jumpContext()
        local player = helpers.GetPlayer()
        if not player or not player:IsValid() then return nil end
        local movement, attributes = player:GetRebelCharacterMovement(), player.MovementAttributeSet
        if not movement or not movement:IsValid() or not attributes or not attributes:IsValid() then return nil end
        local attribute = attributes.JumpVelocity
        if attribute == nil then return nil end
        return { movement = movement, address = movement:GetAddress(), velocity = movement.JumpZVelocity, attribute = attribute.CurrentValue }
    end
    local function recordJump()
        local ok, context = pcall(jumpContext)
        jumpSnapshot = (ok and context and context.velocity == context.velocity) and context or nil
    end
    local function restoreJumpWhenLanded()
        stopJumpRestore()
        local snapshot = jumpSnapshot
        if not snapshot then return end
        local frames = 0
        jumpRestoreHandle = runtime.LoopInGameThreadAfterFrames(1, function()
            frames = frames + 1
            local ok, done = pcall(function()
                local current = jumpContext()
                if not current or current.address ~= snapshot.address then return true end
                if state() ~= "OFF" or current.movement.MovementMode ~= 1 then return false end
                -- Walking again. Only the game's own derived value is corrected, and only while
                -- the attribute the player saw before the flight is still what it was.
                if current.attribute == snapshot.attribute and math.abs(current.velocity - snapshot.velocity) > 0.01 then
                    current.movement.JumpZVelocity = snapshot.velocity
                    if math.abs(current.movement.JumpZVelocity - snapshot.velocity) > 0.01 then
                        menu.SetLabel(id, "status", string.format("OFF. Jump velocity stayed at %.0f after the flight and could not be put back to %.0f.",
                            current.movement.JumpZVelocity, snapshot.velocity))
                    end
                end
                return true
            end)
            if not ok or done or frames >= JUMP_RESTORE_FRAMES then stopJumpRestore(); jumpSnapshot = nil end
        end)
    end
    local function startNative()
        recordJump()
        toggle()
        synchronize()
        assert(state() == "ENTERING" or state() == "FLYING", "FLY rejected entry; stand still on normal ground and resume the game")
    end
    M.Set = function(enabled)
        assert(type(enabled) == "boolean", "Fly requires an on/off value")
        local current = state()
        if enabled then
            assert(menu.Get("DWNoClip", "enabled") ~= true, "Turn No Clip OFF before flying")
            assert(current == "OFF" or current == "FLYING", "Wait for flight to finish changing")
            if current == "OFF" and not armed then
                if canStart() then startNative()
                else
                    armed = true
                    local ok, failure = pcall(function()
                        armHandle = runtime.LoopInGameThreadAfterFrames(1, function()
                            local started, cause = pcall(function()
                                if canStart() then stopArming(); startNative() end
                            end)
                            if not started then stopArming(); synchronize(); error(cause) end
                            return false
                        end)
                    end)
                    if not ok then stopArming(); synchronize(); error(failure) end
                    synchronize()
                end
            end
        else
            stopArming()
            if current ~= "OFF" then
                if current == "FLYING" then toggle() else recovery() end
                restoreJumpWhenLanded()
            end
            synchronize()
        end
    end
    synchronize()
    M.ResetSession = function()
        stopArming()
        stopJumpRestore(); jumpSnapshot = nil
        assert(state() == "OFF", "Personal FLY recovery remains pending")
        synchronize()
    end
end
return M
