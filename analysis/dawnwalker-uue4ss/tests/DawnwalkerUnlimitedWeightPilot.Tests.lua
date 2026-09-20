local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_unlimited_weight_withdrawal_tests")

local bridge_source = assert(arg[1], "Expected the bridge source path as argument 1.")
local bridge_root = assert(os.getenv("TEMP"), "TEMP must be set for the bridge harness.") .. "/DawnwalkerModMenuBridge"

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, received %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function assert_not_match(actual, pattern, label)
    if tostring(actual):match(pattern) then
        error(string.format("%s unexpectedly matched %s", label, pattern), 2)
    end
end

local function read_file(path)
    local file = assert(io.open(path, "r"), "Unable to read " .. path)
    local contents = file:read("*a")
    file:close()
    return contents
end

local function read_fields(path)
    local fields = {}
    for line in read_file(path):gmatch("[^\r\n]+") do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key then fields[key] = value end
    end
    return fields
end

local function make_object(address, class_path)
    return {
        IsValid = function() return true end,
        GetAddress = function() return address end,
        IsA = function(_, requested_class) return requested_class == class_path end,
    }
end

local source_text = read_file(bridge_source)
assert_not_match(source_text, "player:unlimited%-weight", "bridge source capability")
assert_not_match(source_text, "GE_EnableWeightLimitExceed", "incorrect gameplay-effect target")

local world = make_object(1001, "/Script/Engine.World")
local player = make_object(1002, "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
player.GetWorld = function() return world end

package.preload["UEHelpers"] = function()
    return { GetPlayer = function() return player end }
end

local clock = 1900000000
os.time = function()
    clock = clock + 1
    return clock
end
math.random = function() return 123456 end

ModRef = {}
EngineTickAvailable = true
EGameThreadMethod = { EngineTick = 1 }
ExecuteInGameThread = function(callback, method)
    assert_equal(method, EGameThreadMethod.EngineTick, "game-thread method")
    callback()
end
IsInGameThread = function() return true end
StaticFindObject = function() return nil end

local poll_callback = nil
LoopAsync = function(milliseconds, callback)
    assert_equal(milliseconds, 150, "bridge poll interval")
    poll_callback = callback
end

assert(loadfile(bridge_source))()
assert_equal(type(poll_callback), "function", "bridge poll callback")

local ready_path = bridge_root .. "/ready.txt"
local command_path = bridge_root .. "/command.txt"
local response_path = bridge_root .. "/response.txt"
local ready = read_fields(ready_path)
assert_equal(ready.version, "0.3.21-pilot", "bridge version")
assert_equal(ready.phase, "pilot", "bridge phase")
assert_not_match(ready.capabilities, "player:unlimited%-weight", "advertised capabilities")

local capability_count = 0
for _ in ready.capabilities:gmatch("[^,]+") do capability_count = capability_count + 1 end
assert_equal(capability_count, 19, "advertised capability count")

local command_file = assert(io.open(command_path, "w"), "Unable to write command file.")
command_file:write(table.concat({
    "protocol=1",
    "boot_id=" .. ready.boot_id,
    "request_id=withdrawal-harness-1",
    "capability=player:unlimited-weight",
    "value=1",
    "",
}, "\n"))
command_file:close()
poll_callback()

local rejected = read_fields(response_path)
assert_equal(rejected.accepted, "0", "withdrawn capability accepted flag")
assert_equal(rejected.status, "rejected", "withdrawn capability status")
assert_not_match(rejected.readback, "1", "withdrawn capability readback")

print("Dawnwalker Unlimited Weight withdrawal harness passed.")
