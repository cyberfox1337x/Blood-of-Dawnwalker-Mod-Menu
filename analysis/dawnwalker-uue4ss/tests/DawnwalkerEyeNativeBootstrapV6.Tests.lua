local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_native_bootstrap_v6_tests")
local captured, native_reads, in_thread, available = nil, 0, true, true
package.loaded.ReadOnlyDriver = { install = function(deps) captured = deps end }
package.loaded.EyeDiscoveryProbe = { run = function(deps) return deps end, format_lines = function() return "" end }
package.loaded.UEHelpers = { GetPlayerController = function() error("Startup cannot inspect the player") end }
IsInGameThread = function() return in_thread end
EngineTickAvailable, ProcessEventAvailable = true, false
StaticFindObject = function(path)
    native_reads = native_reads + 1
    assert(path == "/Script/Engine.Default__KismetSystemLibrary")
    return { IsValid = function() return available end,
        IsA = function(_, class) assert(class == "/Script/Engine.KismetSystemLibrary"); return true end,
        GetFrameCount = function() return 12345 end }
end
local queued
ExecuteInGameThreadAfterFrames = function(frames, callback) queued = { frames, callback }; return 77 end
dofile(assert(arg[1], "Pass bootstrap path"))
assert(captured ~= nil and native_reads == 0 and queued == nil)
print("PASS bootstrap registration performs no native work")
assert(captured.get_frame_count() == 12345 and native_reads == 1)
in_thread = false
assert(not pcall(captured.get_frame_count) and native_reads == 1)
in_thread, available = true, false
assert(not pcall(captured.get_frame_count) and native_reads == 2)
print("PASS native frame getter requires current game thread and exact native library")
local callback = function() end
assert(captured.execute_after_frames(3, callback) == 77 and queued[1] == 3 and queued[2] == callback)
ProcessEventAvailable = true
assert(not pcall(captured.execute_after_frames, 1, callback))
ProcessEventAvailable, EngineTickAvailable = false, false
assert(not pcall(captured.execute_after_frames, 1, callback))
EngineTickAvailable, ExecuteInGameThreadAfterFrames = true, nil
assert(not pcall(captured.execute_after_frames, 1, callback))
print("PASS frame scheduling preserves exact callback and refuses unavailable route")
print("Passed 3 native bootstrap groups.")
