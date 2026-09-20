local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("personal_fly_control_tests")
local root = "integration/imported-menu/Mods/DawnwalkerImportedMenu/Scripts/"
local function fixture(path)
    local menu = assert(loadfile(root .. "ImportedMenuFacade.lua"))().New()
    local module = assert(loadfile(root .. "PersonalFlyControl.lua"))()
    Key = { V = 86, X = 88 }
    ModifierKey = { CONTROL = 1, ALT = 2 }
    local helpers = { FindOrAddFName = function(name) return name end, GetPlayerController = function() return nil end }
    local calls = 0
    local runtime = { ExecuteInGameThread = function(callback) calls = calls + 1; return callback() end }
    module.Init(menu, helpers, runtime, path, function() return true end)
    return module, menu, function() return calls end
end
-- The reviewed FLY release is the user's own mod, not part of this payload. arg[1] may point
-- at its Scripts folder; otherwise the two places it has lived are tried, and the suite says
-- so plainly when neither exists instead of failing on an unrelated assertion.
local function exists(directory) local file = io.open(directory .. "main.lua", "rb"); if file then file:close(); return true end; return false end
local candidates = { os.getenv("LOCALAPPDATA") .. "/DawnwalkerModMenu/PersonalMods/FLY-1.0.4/Scripts/",
    "C:/Program Files (x86)/Steam/steamapps/common/The Blood of Dawnwalker/Dawnwalker/Binaries/Win64/ue4ss/Mods/DawnwalkerPersonalFly-1.0.4/Scripts/" }
if arg[1] then table.insert(candidates, 1, arg[1]) end -- a nil first element would end ipairs at once
local personal
for _, candidate in ipairs(candidates) do if candidate and exists(candidate) then personal = candidate; break end end
assert(personal, "Personal FLY 1.0.4 Scripts folder not found; pass its path as arg[1]")
local module, menu = fixture(personal)
assert(module.Set, "Original FLY initialization must expose the reviewed adapter")
assert(menu.Get("DWPersonalFly", "enabled") == false)
module.Set(false)
module.ResetSession()
assert(not pcall(module.Set, "true"), "Non-boolean request must fail")
menu.Set("DWNoClip", "enabled", true)
assert(not pcall(module.Set, true), "No Clip conflict must reject entry")
menu.Session("facade-test", true)
menu.Dispatch({ session_id = "facade-test", request_id = "conflict", action = "set", section_id = "DWPersonalFly", item_id = "enabled", value = true, value_type = "boolean" })
assert(menu.Get("DWPersonalFly", "enabled") == false, "Facade prewrite must roll back after a rejected ON")
assert(menu.Snapshot().operation.status == "failed")
menu.Set("DWNoClip", "enabled", false)
assert(not pcall(module.Set, true), "Missing player must reject entry without pretending to fly")
menu.Dispatch({ session_id = "facade-test", request_id = "missing-player", action = "set", section_id = "DWPersonalFly", item_id = "enabled", value = true, value_type = "boolean" })
assert(menu.Get("DWPersonalFly", "enabled") == false, "Native entry rejection must correct the facade's requested value")
assert(menu.Get("DWPersonalFly", "enabled") == false)
module.ResetSession()
local unavailable, missing = fixture(personal .. "missing/")
assert(not unavailable.Set and missing.Get("DWPersonalFly", "enabled") == false)
local state = "OFF"
local function toggle() state = "FLYING" end
local function nested() return function() toggle() end end
local read = assert(module.FindUpvalue(nested, "state"))
assert(read() == "OFF")
toggle()
assert(read() == "FLYING", "Named closure inspection must read actual changing state")
assert(module.FindUpvalue(nested, "absent") == nil)
local synchronized = 0
for _, boolean in ipairs({ true, false }) do
    local wrapped = module.PreserveCallback(function(argument) return boolean, nil, argument end,
        function() synchronized = synchronized + 1 end)
    local results = table.pack(wrapped("tail"))
    assert(results.n == 3 and results[1] == boolean and results[2] == nil and results[3] == "tail")
end
assert(synchronized == 2)
assert(not pcall(module.PreserveCallback(function() error("original failure") end, function() end)))
-- Model the reviewed closure contract without calling any game function.
local scheduled, modelState, modelMenu, originalCalls = {}, "OFF", nil, 0
local environment = setmetatable({ load = function(contents, name, mode, sourceEnvironment)
    if name ~= "@personal-fly-1.0.4" then return load(contents, name, mode, sourceEnvironment) end
    return function()
        local state = "OFF"
        local function handle_toggle()
            originalCalls = originalCalls + 1
            state = state == "OFF" and "ENTERING" or "EXITING"
            sourceEnvironment.ExecuteInGameThreadWithDelay(25, function()
                state = state == "ENTERING" and "FLYING" or "OFF"
                modelState = state
            end)
        end
        sourceEnvironment.RegisterKeyBind(86, function() sourceEnvironment.ExecuteInGameThread(handle_toggle) end)
        sourceEnvironment.RegisterKeyBind(88, {}, function()
            sourceEnvironment.ExecuteInGameThread(function() state = "OFF"; modelState = state end)
        end)
    end
end }, { __index = _G })
local modeled = assert(loadfile(root .. "PersonalFlyControl.lua", "t", environment))()
modelMenu = assert(loadfile(root .. "ImportedMenuFacade.lua"))().New()
local ready, frame, cancelled = true, nil, 0
modeled.Init(modelMenu, {}, {
    ExecuteInGameThread = function(callback) return callback() end,
    ExecuteWithDelay = function(delay, callback) assert(delay == 25); scheduled[#scheduled + 1] = callback end,
    LoopInGameThreadAfterFrames = function(frames, callback) assert(frames == 1); frame = callback; return 42 end,
    CancelDelayedAction = function(handle) assert(handle == 42); cancelled = cancelled + 1; frame = nil end,
}, personal, function() return ready end)
modeled.Set(true)
assert(modelMenu.Get("DWPersonalFly", "enabled") == true and originalCalls == 1)
assert(not pcall(modeled.Set, true), "Duplicate transition request must be rejected")
table.remove(scheduled, 1)()
assert(modelState == "FLYING")
modeled.Set(true)
assert(originalCalls == 1, "Already ON must not toggle OFF")
modeled.Set(false)
assert(modelMenu.Get("DWPersonalFly", "enabled") == true, "OFF cannot be reported before original exit completes")
assert(not pcall(modeled.ResetSession), "Pending restoration cannot be discarded")
table.remove(scheduled, 1)()
assert(modelState == "OFF" and modelMenu.Get("DWPersonalFly", "enabled") == false)
modeled.ResetSession()
modeled.Set(true)
modeled.Set(false)
assert(modelState == "OFF", "Disable during transition must invoke original recovery")
ready = false
local beforeArming = originalCalls
modeled.Set(true)
assert(modelMenu.Get("DWPersonalFly", "enabled") == true and originalCalls == beforeArming)
frame()
assert(originalCalls == beforeArming, "Paused game must not run native Jump entry")
modeled.Set(false)
assert(frame == nil and cancelled == 1 and modelMenu.Get("DWPersonalFly", "enabled") == false)
modeled.Set(true)
ready = true
frame()
assert(frame == nil and originalCalls == beforeArming + 1, "Resume must run original entry once")
modeled.Set(false)
modeled.ResetSession()
print("Personal FLY: original initialization, rejected entry, mutual exclusion, missing package, state introspection passed")
