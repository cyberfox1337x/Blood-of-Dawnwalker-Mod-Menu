local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("activation_recovery_failure_tests")
local source = assert(arg[1], "ActivationControl.lua path required")

local function fixture(fault)
    local state = { labels = {}, logs = {}, values = {}, closes = 0, readCloses = 0, sets = 0, resets = 0,
        ledger = fault and fault:find("read", 1, true) and "Player Fixture" or "", queued = {} }
    local valid = function() return true end
    local focus = { IsValid = valid,
        SetSlotsChargedOverride = function() state.sets = state.sets + 1 end,
        ResetSlotsChargedOverride = function()
            state.resets = state.resets + 1
            if state.resetFailure then error("native reset refused") end
        end }
    local attributes = { IsValid = valid, UnlockedActionSlots = { CurrentValue = 2 } }
    local controller = { IsValid = valid }
    local combat = { IsValid = valid, IsAlive = valid }
    local player = { IsValid = valid, GetFullName = function() return "Player Fixture" end,
        Controller = controller, CombatFocusComponent = focus, CharacterAttributeSet = attributes, CombatComponent = combat }
    controller.Pawn = player
    local menu = {
        SetLabel = function(_, key, text) state.labels[key] = text end,
        Set = function(_, key, value) state.values[key] = value end,
        Register = function(section)
            for _, item in ipairs(section.items) do if item.id == "enabled" then state.toggle = item.onChange end end
        end,
    }
    local environment = setmetatable({
        ExecuteInGameThread = function(callback) state.queued[#state.queued + 1] = callback end,
        LoopInGameThreadWithDelay = function(_, callback) state.tick = callback; return 1 end,
        CancelDelayedAction = function() state.tick = nil end,
        FindAllOf = function() return {{ IsValid = valid, GetFullName = function() return "CombatSubsystem live" end, GetIsInCombat = valid }} end,
        io = { open = function(_, mode)
            if mode == "r" then
                if fault == "read-open" then return nil, "permission denied", 13 end
                if fault == "missing" then return nil, "No such file or directory", 2 end
                return {
                    read = function()
                        if fault == "read-return" then return nil, "read failed" end
                        if fault == "read-throw" then error("read threw") end
                        return state.ledger
                    end,
                    close = function()
                        state.readCloses = state.readCloses + 1
                        if fault == "read-close" then return nil, "read close failed" end
                        return true
                    end,
                }
            end
            return {
                write = function(self, text)
                    if text ~= "" and fault == "write-return" then return nil, "disk full" end
                    if text ~= "" and fault == "write-throw" then error("disk disconnected") end
                    state.ledger = text
                    return self
                end,
                close = function()
                    state.closes = state.closes + 1
                    if state.ledger ~= "" and fault == "close-return" then return nil, "flush failed" end
                    return true
                end,
            }
        end },
    }, { __index = _G })
    local module = assert(loadfile(source, "t", environment))()
    module.Init(menu, function() return player end, function(text) state.logs[#state.logs + 1] = text end, "fixture/")
    function state.dispatch(value)
        state.toggle(value)
        table.remove(state.queued, 1)()
    end
    return state
end

for _, fault in ipairs({ "read-return", "read-throw", "read-close", "read-open" }) do
    local state = fixture(fault)
    state.dispatch(true)
    assert(state.sets == 0 and state.resets == 0, fault .. ": unread recovery record allowed a native mutation")
    assert(state.ledger == "Player Fixture", fault .. ": unread recovery ledger was discarded")
    if fault ~= "read-open" then assert(state.readCloses == 1, fault .. ": read handle was not closed") end
    assert(state.values.enabled == false and state.labels.status:find("Unavailable", 1, true))
    print("PASS " .. fault .. " preserves recovery ownership without native mutation")
end
for _, fault in ipairs({ "write-return", "write-throw", "close-return" }) do
    local state = fixture(fault)
    state.dispatch(true)
    assert(state.sets == 0, fault .. ": override was applied without a durable ownership record")
    assert(state.closes > 0, fault .. ": ledger handle was not closed after failure")
    assert(state.values.enabled == false, fault .. ": failed toggle remained enabled")
    assert(state.labels.status:find("Unavailable", 1, true), fault .. ": failure was not visible")
    print("PASS " .. fault .. " refuses mutation and closes ledger")
end
do
    local state = fixture()
    state.dispatch(true)
    assert(state.sets == 1 and state.values.enabled == true)
    state.resetFailure = true
    state.dispatch(false)
    local logs = table.concat(state.logs, "\n")
    assert(logs:find("Activation cleanup failed", 1, true), "Secondary cleanup failure was swallowed")
    assert(state.labels.status:find("cleanup", 1, true), "Outstanding cleanup was hidden from the control status")
    assert(state.ledger ~= "", "Failed native reset discarded recovery ownership")
    state.dispatch(true)
    assert(state.sets == 1, "Re-enable replaced a still-owned override")
    state.resetFailure = false
    state.dispatch(false)
    assert(state.ledger == "" and state.values.enabled == false, "Retry did not release recorded ownership")
    print("PASS cleanup failure is visible, retains ownership and remains retryable")
end
do
    local state = fixture()
    state.dispatch(true)
    state.dispatch(false)
    assert(state.sets == 1 and state.resets == 1 and state.ledger == "" and state.values.enabled == false)
    print("PASS successful activation and cleanup behavior preserved")
end
do
    local state = fixture("missing")
    state.dispatch(true)
    state.dispatch(false)
    assert(state.sets == 1 and state.resets == 1 and state.ledger == "" and state.values.enabled == false)
    print("PASS absent recovery file permits a normal first-use cycle")
end
