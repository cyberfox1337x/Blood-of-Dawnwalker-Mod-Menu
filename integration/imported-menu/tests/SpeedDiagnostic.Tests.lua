local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("speed_diagnostic_input_lifecycle_tests")
local handle = assert(io.open(assert(arg[1]), "r"))
local source = handle:read("a"); handle:close()
local block = assert(source:match("(local speedProfileLoaded, speedProfileFailure = pcall%b().-if not speedProfileLoaded then.- end)\n"))
local function fixture()
    local callbacks, items, adapters, values, errors = {}, {}, {}, {}, {}
    local inputCount, offCalls, moving, pawnId, failProfile = 0, 0, false, 1, false
    local player, controller = {}, {}
    player.IsValid = function() return true end
    player.GetAddress = function() return pawnId end
    player.Controller = controller
    player.GetVelocity = function() return { X = moving and 10 or 0, Y = 0, Z = 0 } end
    controller.IsValid = function() return true end
    controller.GetAddress = function() return 2 end
    controller.Pawn = player
    controller.IsMoveInputIgnored = function() return inputCount > 0 end
    controller.SetIgnoreMoveInput = function(_, enabled)
        if enabled then inputCount = inputCount + 1 else inputCount = inputCount - 1; offCalls = offCalls + 1 end
    end
    local owned = false
    local pilot = { inspect = function() end, begin = function() owned = true end,
        verify = function() assert(not failProfile, "profile refused") end,
        beginRestore = function() owned = false end, reset = function() owned = false end, owned = function() return owned end }
    local env = setmetatable({ scriptDirectory = "", adapterModules = adapters,
        helpers = { GetPlayer = function() return player end },
        injected = { ExecuteInGameThread = function(callback) callback() end,
            ExecuteWithDelay = function(_, callback) callbacks[#callbacks + 1] = callback end },
        StaticFindObject = function() return { IsValid = function() return true end, IsGamePaused = function() return false end } end,
        loadfile = function() return function() return { New = function() return pilot end } end end,
        menu = { Register = function(section) for _, item in ipairs(section.items) do items[item.id] = item end end,
            Set = function(_, key, value) values[key] = value end, SetLabel = function(_, _, text) values.status = text end,
            Fail = function(message) error(message) end },
    }, { __index = _G })
    assert(load(block, "speed-diagnostic", "t", env))()
    local function drain()
        local count = 0
        while #callbacks > 0 do
            count = count + 1; assert(count <= 30)
            local ok, cause = pcall(table.remove(callbacks, 1)); if not ok then errors[#errors + 1] = cause end
        end
    end
    return { start = items.roundtrip_unpaused.onClick, drain = drain, cancel = function() items.owned.onChange(false) end,
        values = values, errors = errors, reset = adapters[1].ResetSession,
        input = function() return inputCount, offCalls end,
        preignored = function() inputCount = 1 end, externalLock = function() inputCount = inputCount + 1 end,
        move = function() moving = true end, drift = function() pawnId = 9 end,
        fail = function() failProfile = true end }
end
local count = 0
local function test(name, callback) callback(); count = count + 1; print("PASS " .. name) end
test("unpaused trial restores owned input and profile", function()
    local f = fixture(); f.start(); assert(f.input() == 1); f.drain()
    local input, off = f.input(); assert(input == 0 and off == 1 and f.values.owned == false and #f.errors == 0)
end)
test("already ignored movement is not decremented", function()
    local f = fixture(); f.preignored(); f.start(); f.drain(); local input, off = f.input()
    assert(input == 1 and off == 0 and #f.errors == 1)
end)
test("profile failure still restores input", function()
    local f = fixture(); f.fail(); f.start(); f.drain(); assert(f.input() == 0 and #f.errors == 1)
end)
test("cancellation restores input once and cancels old verification", function()
    local f = fixture(); f.start(); f.cancel(); f.drain(); local input, off = f.input()
    assert(input == 0 and off == 1 and #f.errors == 0)
end)
test("foreign input count is not repeatedly decremented", function()
    local f = fixture(); f.start(); f.externalLock(); f.drain(); local input, off = f.input()
    assert(input == 1 and off == 1 and f.values.owned == true and #f.errors == 1)
end)
test("replacement player keeps input recovery pending", function()
    local f = fixture(); f.start(); f.drift(); f.drain(); local input, off = f.input()
    assert(input == 1 and off == 0 and f.values.owned == true and #f.errors == 1)
end)
print(count .. " speed diagnostic tests passed")
