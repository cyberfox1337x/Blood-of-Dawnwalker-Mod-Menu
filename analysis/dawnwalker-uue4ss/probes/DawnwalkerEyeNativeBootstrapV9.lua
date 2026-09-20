local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_native_operation_bootstrap")
local source = debug.getinfo(1, "S").source
assert(source:sub(1, 1) == "@", "Native eye pilot requires an on-disk module path")
local scripts_directory = assert(source:sub(2):match("^(.*[/\\])"), "Cannot locate pilot module directory")
local Driver, Operations, UEHelpers = require("ReadOnlyDriver"), require("EyeDiscoveryProbe"), require("UEHelpers")
local OUTPUT_ROOT = "C:/Users/Cyberfox1337/Documents/ChatGPT/The Blood of DawnWalker/qa/eye-appearance/native-frames/"
local function read_attestation()
    local file, message = io.open(scripts_directory .. "attestation.txt", "r")
    assert(file, "Fresh issuer attestation required: " .. tostring(message))
    local ok, text = pcall(file.read, file, 2049)
    local closed, close_error = file:close()
    assert(ok and closed, "Attestation read/close failed: " .. tostring(close_error))
    return text
end
local function output_exists(path)
    local file, message, code = io.open(path, "rb")
    if file then assert(file:close(), "Cannot close existing artifact"); return true end
    if code == 2 then return false end
    error("Cannot determine artifact existence: " .. tostring(message), 0)
end
local function get_local_player()
    local controller = UEHelpers.GetPlayerController()
    assert(controller:IsValid() and controller:IsLocalPlayerController() == true, "Local controller unavailable")
    local pawn = controller:K2_GetPawn()
    assert(pawn:IsValid() and pawn:GetAddress() == controller.Pawn:GetAddress() and pawn:IsPlayerControlled() == true,
        "Local player-controller pawn identity mismatch")
    return pawn
end
local function get_frame_count()
    assert(IsInGameThread() == true, "Native frame observation requires the game thread")
    local library = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    assert(library:IsValid() and library:IsA("/Script/Engine.KismetSystemLibrary"), "Native frame count library is unavailable")
    return library:GetFrameCount()
end
Driver.install({
    probe = { run = function(deps)
        deps.find_all_of, deps.output_exists = FindAllOf, output_exists
        deps.output_directory = OUTPUT_ROOT .. deps.boot_id
        return Operations.run(deps)
    end, format_lines = Operations.format_lines },
    boot_id = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999)), now = os.time,
    read_attestation = read_attestation, log = print,
    engine_tick_available = function() return EngineTickAvailable end,
    process_event_available = function() return ProcessEventAvailable end,
    is_in_game_thread = IsInGameThread,
    key_available = function() return not IsKeyBindRegistered(Key.F6) end,
    register_key = function(callback) RegisterKeyBindAsync(Key.F6, callback) end,
    execute_on_engine_tick = function(callback) ExecuteInGameThread(callback, EGameThreadMethod.EngineTick) end,
    execute_after_frames = function(frames, callback)
        assert(EngineTickAvailable == true and ProcessEventAvailable ~= true
            and type(ExecuteInGameThreadAfterFrames) == "function", "EngineTick frame scheduler is unavailable")
        return ExecuteInGameThreadAfterFrames(frames, callback)
    end,
    get_frame_count = get_frame_count,
    get_player = get_local_player, static_find_object = StaticFindObject,
})
