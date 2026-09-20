local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("imported_runtime_mock_tests")
local root = assert(arg[1]) .. "/Mods/DawnwalkerImportedMenu/Scripts/"
local files, queue, delayed, loops = {}, {}, {}, {}
local poll, nextId, playerAddress, endPlay, playerLookups = nil, 0, 11, nil, 0
local clock,stateWrites= os.time(),0
local combat = { IsValid = function() return true end, IsAlive = function() return true end }
local world = { IsValid = function() return true end, GetAddress = function() return 21 end }
local player = { IsValid = function() return true end, GetAddress = function() return playerAddress end,
    GetWorld = function() return world end, CombatComponent = combat }
local controller = { IsValid = function() return true end, GetAddress = function() return 31 end, Pawn = player }
player.Controller = controller
local mock = setmetatable({}, { __index = _G })
mock._G = mock
mock.loadfile = function(path, mode, environment) return loadfile(path, mode or "t", environment or mock) end
mock.os = setmetatable({ time=function()return clock end, getenv = function() return "MOCK_TEMP" end, remove = function(path) files[path] = nil; return true end,
    rename = function(source, target) files[target] = files[source]; files[source] = nil; return true end }, { __index = os })
mock.io = { open = function(path, mode)
    if mode:sub(1, 1) == "r" and files[path] == nil then return nil end
    return { read = function(_, count) return type(count) == "number" and files[path]:sub(1, count) or files[path] end,
        write = function(self, contents) if path:find("state.json.tmp",1,true) then stateWrites=stateWrites+1 end;files[path] = (files[path] or "") .. contents; return self end,
        close = function() return true end,
        lines = function() return function() return nil end end }
end }
-- Opening with w truncates the in-memory file, just as real io.open does.
local open = mock.io.open
mock.io.open = function(path, mode) if mode:sub(1, 1) == "w" then files[path] = "" end; return open(path, mode) end
-- Captured rather than discarded: the automatic session readback reports a persistent
-- failure to the log precisely so it does not publish, and the log is the only evidence
-- that it ran, retried, and then stopped.
local prints = {}
mock.print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do parts[index] = tostring((select(index, ...))) end
    prints[#prints + 1] = table.concat(parts, " ")
end
local function logLines(needle)
    local found = 0
    for _, line in ipairs(prints) do if line:find(needle, 1, true) then found = found + 1 end end
    return found
end
mock.EngineTickAvailable = true
mock.EGameThreadMethod = { EngineTick = 1 }
mock.ModRef = {}
mock.IsInGameThread = function() return true end
mock.require = function(name) assert(name == "UEHelpers.UEHelpers"); return { GetPlayer = function() playerLookups=playerLookups+1;return player end } end
mock.StaticFindObject = function() return nil end
mock.FindFirstOf = function() return nil end
mock.FindAllOf = function() return {} end
mock.RegisterHook = function() return 1, 2 end
mock.UnregisterHook = function() return true end
mock.RegisterEndPlayPreHook = function(callback) endPlay = callback end
mock.ExecuteInGameThread = function(callback) queue[#queue + 1] = callback end
mock.ExecuteWithDelay = function() error("Async timer hop must not be used") end
mock.ExecuteInGameThreadWithDelay = function(_, callback) nextId = nextId + 1; delayed[nextId] = callback; return nextId end
mock.LoopInGameThreadWithDelay = function(milliseconds, callback) nextId = nextId + 1; loops[nextId] = callback;if milliseconds==150 then poll=callback end;return nextId end
mock.CancelDelayedAction = function(id) delayed[id] = nil; loops[id] = nil end
mock.LoopAsync = function() error("Async polling must not be used") end
assert(loadfile(root .. "main.lua", "t", mock))()
local function drain()
    local count = 0
    while #queue > 0 do count = count + 1; assert(count < 200); table.remove(queue, 1)() end
end
local function tick() poll(); drain() end
local function snapshot() return assert(files["MOCK_TEMP/DawnwalkerImportedMenu/state.json"]) end
tick()
assert(snapshot():find('"ready":true', 1, true))
assert(snapshot():find('"id":"DWSkinTint"', 1, true), "Skin tint did not register in the complete runtime")
assert(snapshot():find('"id":"DWTimelessCourt"', 1, true), "Court activities did not register in the complete runtime")
assert(not snapshot():find('Skin tint initialization failed:', 1, true), "Skin tint boot registration failed")
assert(not snapshot():find('"id":"DWFastTravel"', 1, true), "Experimental map travel registered at boot")
assert(not snapshot():find('"id":"DWMapArtworkQA"', 1, true), "Experimental artwork exporter registered at boot")
assert(snapshot():find('Super Jump (1.5x jump velocity)', 1, true), "Private-effect Super Jump control did not register")
assert(not snapshot():find('Read Super Jump state', 1, true), "Manual Super Jump read action is still visible")
assert(not snapshot():find('Verify No Clip state', 1, true), "Manual No Clip verification action is still visible")
assert(not snapshot():find('Super Jump initialization failed:', 1, true), "Super Jump sibling dependency injection failed")
assert(snapshot():find('"id":"DWJumpTrajectoryTest"', 1, true), "Physical jump diagnostic failed to register")
assert(snapshot():find('Compare two physical jumps and restore', 1, true), "Physical jump action missing")
local baselineWrites=stateWrites
for _=1,6 do tick() end
assert(stateWrites==baselineWrites,"Unchanged same-second state was republished")
-- Nothing in this mock can satisfy a difficulty readback, so the runtime's automatic
-- session pass must give up after its bounded retries and say so once in the log. More
-- than one line would mean it never stopped; none would mean it never ran at all - and
-- either way the assertion above proves it published nothing while trying.
local reported = logLines("Automatic session readback failed")
assert(reported >= 1, "Automatic session readback never ran, or never reported after exhausting its retries")
-- Ran, reported, stopped: more ticks must add no more reports. Pinning an exact count
-- would break every time another module opts into SessionReady, which is the intended
-- way for read-gated controls to come up populated.
for _=1,10 do tick() end
assert(logLines("Automatic session readback failed")==reported,
    "Automatic session readback kept reporting after its retries were exhausted")
local beforeHeartbeat=snapshot()
clock=clock+1;tick()
assert(stateWrites==baselineWrites+1,"Next-second heartbeat was not published")
-- A new second must move the heartbeat and nothing else. writeState reuses the cached
-- payload for these ticks instead of rebuilding the snapshot, which cost ~8.5 ms of
-- game thread every second; this pins that the shortcut still publishes the same bytes.
local afterHeartbeat=snapshot()
assert(beforeHeartbeat~=afterHeartbeat,"Heartbeat tick published an identical payload")
local function withoutHeartbeat(payload) return (payload:gsub('"heartbeat":%-?%d+','"heartbeat":0')) end
assert(withoutHeartbeat(beforeHeartbeat)==withoutHeartbeat(afterHeartbeat),
    "Heartbeat-only publication changed something other than the heartbeat")
assert(afterHeartbeat:find('"heartbeat":'..clock,1,true),"Patched payload does not carry the new heartbeat")
assert(select(2,afterHeartbeat:gsub('"heartbeat":%-?%d+',''))==1,"Heartbeat field must stay unique for patching")
-- A rename that loses the race with the desktop poller must cost one tick, not the
-- whole runtime: writeState leaves its markers unadvanced and the next tick republishes.
do
    local kept = snapshot()
    local realRename = mock.os.rename
    mock.os.rename = function(source, target)
        if target:find("state.json", 1, true) and not target:find("tmp", 1, true) then return nil, "File exists" end
        return realRename(source, target)
    end
    clock = clock + 1
    local survived = pcall(tick)
    mock.os.rename = realRename
    assert(survived, "a lost rename race must not abort the tick")
    -- The channel must never be left without a readable state file: the desktop reads
    -- its absence as a lost connection.
    local afterRace = snapshot()
    assert(afterRace:find('"heartbeat":' .. clock, 1, true),
        "a lost rename must still publish through the direct write")
    assert(afterRace ~= kept, "the payload must have moved on")
    clock = clock + 1; tick()
    assert(snapshot() ~= afterRace, "publishing must continue after the race clears")
end

local session = assert(snapshot():match('"sessionId":"([^"]+)"'))
local function command(id, expiry, targetSession)
    files["MOCK_TEMP/DawnwalkerImportedMenu/command.txt"] = table.concat({
        "request_id=" .. id, "session_id=" .. (targetSession or session), "action=set", "section_id=DWSkills",
        "item_id=amount", "value_type=number", "value=5", "expires_at=" .. expiry, "" }, "\n")
end
command("valid-request", clock + 5)
local beforeCommandWrites=stateWrites
tick()
assert(stateWrites>beforeCommandWrites,"Same-second command revision was not published immediately")
assert(snapshot():find('"id":"valid-request"', 1, true))
assert(snapshot():find('"status":"completed"', 1, true))
assert(files[root .. "Source/settings.ini"]:find("skillAmount=5", 1, true))
local priorConfig = files[root .. "Source/settings.ini"]
command("expired-request", clock - 1)
tick()
assert(files[root .. "Source/settings.ini"] == priorConfig)
assert(snapshot():find("Expired or invalid imported command deadline", 1, true))
assert(not snapshot():find("main%.lua:%d+: Expired or invalid imported command deadline"),
    "an invalid envelope must not expose a Lua source path in runtime diagnostics")
local function occurrences(text, needle)
    local count, cursor = 0, 1
    while true do
        local first, last = text:find(needle, cursor, true)
        if not first then return count end
        count, cursor = count + 1, last + 1
    end
end
local expiredCount = occurrences(snapshot(), "Expired or invalid imported command deadline")
tick(); tick()
assert(occurrences(snapshot(), "Expired or invalid imported command deadline") == expiredCount,
    "Expired mailbox command repeated its failure")
command("stale-request", clock + 5, "previous-session")
tick()
local staleCount = occurrences(snapshot(), "Stale imported command session")
assert(staleCount == 0, "a normal session race must be consumed without polluting runtime diagnostics")
tick(); tick()
assert(occurrences(snapshot(), "Stale imported command session") == staleCount,
    "stale mailbox command polluted diagnostics after it was consumed")
assert(files[root .. "Source/settings.ini"] == priorConfig)
playerAddress = 12
tick()
local nextSession = snapshot():match('"sessionId":"([^"]+)"')
assert(nextSession ~= session)
assert(files[root .. "Source/settings.ini"] == priorConfig)
files["MOCK_TEMP/DawnwalkerImportedMenu/command.txt"] = "request_id=close-request\nsession_id=" .. nextSession
    .. "\naction=close\nexpires_at=" .. (clock + 5) .. "\nvalue_type=\n"
tick()
assert(snapshot():find('"id":"close-request"', 1, true))
assert(snapshot():find('"status":"completed"', 1, true))
if arg[2] == "shutdown" then
    assert(type(endPlay) == "function")
    endPlay(nil, { get = function() return 0 end })
    assert(snapshot():find('"ready":true', 1, true), "Ordinary actor destruction incorrectly latched shutdown")
    assert(not snapshot():find('"shutdown"', 1, true), "no shutdown marker before a real quit")
    files["MOCK_TEMP/DawnwalkerImportedMenu/command.txt"] = "request_id=pending-on-quit\nsession_id=" .. nextSession
        .. "\naction=invoke\nsection_id=DWFallReadback\nitem_id=refresh\nexpires_at=" .. (clock + 5) .. "\n"
    poll() -- Leave the finite game-thread callback queued while Quit begins.
    assert(#queue > 0, "Shutdown test requires a pending native callback")
    local callbacks = {};for _,callback in pairs(delayed) do callbacks[#callbacks+1]=callback end
    for _,callback in pairs(loops) do callbacks[#callbacks+1]=callback end
    local before = playerLookups
    endPlay(nil, { get = function() return 4 end })
    endPlay(nil, { get = function() return 4 end })
    player.GetWorld = function() error("UFunction lookup after shutdown") end
    for _,callback in ipairs(callbacks) do callback() end
    tick();mock.ModRef.OnUnload()
    assert(playerLookups == before, "Late shutdown work attempted player/native lookup")
    assert(snapshot():find("restoration during teardown is unverified", 1, true))
    -- The desktop restarts Steam after an exit that lacks this marker (stale overlay
    -- session -> startup freeze), so a real quit must publish it and nothing else may.
    assert(snapshot():find('"shutdown":"quit"', 1, true), "clean quit must publish shutdown=quit")
elseif arg[2] == "non-game-thread" then
    command("after-close", clock + 5, nextSession)
    tick() -- A new operation invalidates the earlier close acknowledgement.
    mock.IsInGameThread = function() return false end
    local queuedBefore = #queue
    mock.ModRef.OnUnload()
    assert(#queue == queuedBefore, "Unload queued OFF cleanup that UE4SS would discard")
    assert(snapshot():find("OFF restoration is unverified", 1, true))
else
    mock.ModRef.OnUnload()
end
assert(snapshot():find('"ready":false', 1, true))
print("PASS isolated runtime boot, typed command, deadline, session change, close and unload")
