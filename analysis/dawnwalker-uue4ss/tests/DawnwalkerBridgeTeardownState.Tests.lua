local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_bridge_teardown_state_tests")

local bridge_source = assert(arg[1], "Expected the bridge source path as argument 1.")
local bridge_root = assert(os.getenv("TEMP"), "TEMP must be set for the bridge harness.") .. "/DawnwalkerModMenuBridge"

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, received %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function assert_match(actual, pattern, label)
    if not tostring(actual):match(pattern) then
        error(string.format("%s did not match %s", label, pattern), 2)
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

local function write_command(path, ready, request_id, capability, value)
    local command_file = assert(io.open(path, "w"), "Unable to write command file.")
    command_file:write(table.concat({
        "protocol=1",
        "boot_id=" .. ready.boot_id,
        "request_id=" .. request_id,
        "capability=" .. capability,
        "value=" .. value,
        "",
    }, "\n"))
    command_file:close()
end

local function make_object(address, class_path)
    return {
        IsValid = function() return true end,
        GetAddress = function() return address end,
        IsA = function(_, requested_class) return requested_class == class_path end,
    }
end

local source_text = read_file(bridge_source)
assert_match(source_text, "local teardown_retry_pending = false", "pending teardown state")
assert_match(source_text, "retain_only_pending_active_state%(%)", "pending active-state reconciliation")
assert_match(source_text, "teardown_session_state%(%\"pending restore retry%\"%)", "bounded restore retry")
assert_match(source_text, "player identity transition blocked by unresolved restore state", "identity transition gate")
assert_match(source_text, "unresolved restore state was retained instead of discarded", "unload retention gate")

local old_world = make_object(4101, "/Script/Engine.World")
local new_world = make_object(4102, "/Script/Engine.World")
local current_world = old_world
local combat = make_object(4103, "/Script/DogwoodCombat.CombatComponentBase")
local player = make_object(4104, "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
local hud = make_object(4105, "/Script/DogwoodUI.HUDManagerSubsystem")
local subsystem_library = make_object(4106, "/Script/Engine.SubsystemBlueprintLibrary")
local hud_class = make_object(4107, "/Script/CoreUObject.Class")

local health = 0.55
local health_locked = false
local hud_visible = true
local health_restore_failures = 0
local hud_restore_failures = 0
local health_restore_attempts = 0
local hud_restore_attempts = 0

player.GetWorld = function() return current_world end
player.CombatComponent = combat
combat.GetHealthPercentage = function() return health end
combat.SetHealthPercent = function(_, percentage)
    if math.abs(percentage - 0.55) <= 0.000001 then
        health_restore_attempts = health_restore_attempts + 1
        if health_restore_failures > 0 then
            health_restore_failures = health_restore_failures - 1
            return
        end
    end
    health = percentage
end
combat.LockHealth = function() health_locked = true end
combat.UnlockHealth = function() health_locked = false end

hud.IsHUDVisible = function() return hud_visible end
hud.SetHUDVisible = function(_, requested)
    if requested == true then
        hud_restore_attempts = hud_restore_attempts + 1
        if hud_restore_failures > 0 then
            hud_restore_failures = hud_restore_failures - 1
            return
        end
    end
    hud_visible = requested
end

subsystem_library.GetWorldSubsystem = function(_, context, subsystem_class)
    assert_equal(context, player, "HUD subsystem world context")
    assert_equal(subsystem_class, hud_class, "HUD subsystem class identity")
    return hud
end

package.preload["UEHelpers"] = function()
    return { GetPlayer = function() return player end }
end

local clock = 1900002000
os.time = function()
    clock = clock + 1
    return clock
end
math.random = function() return 876543 end

ModRef = {}
EngineTickAvailable = true
EGameThreadMethod = { EngineTick = 1 }
ExecuteInGameThread = function(callback, method)
    assert_equal(method, EGameThreadMethod.EngineTick, "game-thread method")
    callback()
end
IsInGameThread = function() return true end
StaticFindObject = function(path)
    if path == "/Script/Engine.Default__SubsystemBlueprintLibrary" then return subsystem_library end
    if path == "/Script/DogwoodUI.HUDManagerSubsystem" then return hud_class end
    return nil
end

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
assert_equal(ready.phase, "pilot", "initial bridge phase")

local function execute(request_id, capability, value)
    write_command(command_path, ready, request_id, capability, value)
    poll_callback()
    ready = read_fields(ready_path)
    return read_fields(response_path)
end

local health_enabled = execute("teardown-health-enable", "player:infinite-health", "1")
assert_equal(health_enabled.accepted, "1", "Infinite Health enabled")
assert_equal(health, 1.0, "health lock target applied")
assert_equal(health_locked, true, "health lock engaged")

local hud_hidden = execute("teardown-hud-hide", "visuals:hud-visible", "0")
assert_equal(hud_hidden.accepted, "1", "HUD hidden")
assert_equal(hud_visible, false, "HUD mutation applied")

health_restore_failures = 2
hud_restore_failures = 2
current_world = new_world
poll_callback()
ready = read_fields(ready_path)
assert_equal(ready.phase, "waiting-player", "failed teardown blocks the next player identity")
assert_equal(ready.capabilities, "", "failed teardown withdraws all capabilities")
assert_equal(ready.active, "player:infinite-health,visuals:hud-visible", "failed teardown retains unresolved active records")
assert_equal(health, 1.0, "failed resource restore keeps observable mutated health")
assert_equal(hud_visible, false, "failed snapshot restore keeps observable HUD state")

local blocked = execute("teardown-command-blocked", "visuals:hud-visible", "1")
assert_equal(blocked.accepted, "0", "new command rejected while teardown is unresolved")
assert_match(blocked.message, "not advertised", "pending teardown command rejection")
assert_equal(ready.phase, "waiting-player", "second failed retry remains fail closed")
assert_equal(ready.capabilities, "", "second failed retry still withdraws capabilities")
assert_equal(health_restore_attempts, 2, "resource restoration retried once per probe")
assert_equal(hud_restore_attempts, 2, "snapshot restoration retried once per probe")

poll_callback()
ready = read_fields(ready_path)
assert_equal(ready.phase, "pilot", "successful retry adopts the next identity")
assert_match(ready.capabilities, "player:infinite%-health", "capabilities return only after exact restoration")
assert_equal(ready.active, "", "successful retry clears resolved active state")
assert_equal(health, 0.55, "resource baseline restored on retry")
assert_equal(health_locked, false, "resource unlocked on retry")
assert_equal(hud_visible, true, "snapshot baseline restored on retry")
assert_equal(health_restore_attempts, 3, "resource restoration eventually succeeded")
assert_equal(hud_restore_attempts, 3, "snapshot restoration eventually succeeded")

execute("teardown-unload-health-enable", "player:infinite-health", "1")
execute("teardown-unload-hud-hide", "visuals:hud-visible", "0")
EngineTickAvailable = false
IsInGameThread = function() return false end
ModRef.OnUnload()
poll_callback()
ready = read_fields(ready_path)
assert_equal(ready.phase, "waiting-game-thread", "unavailable game thread keeps unload fail closed")
assert_equal(ready.capabilities, "", "unload fallback never advertises capabilities")
assert_equal(ready.active, "player:infinite-health,visuals:hud-visible", "unload fallback retains rollback handles")

EngineTickAvailable = true
IsInGameThread = function() return true end
poll_callback()
ready = read_fields(ready_path)
assert_equal(ready.phase, "pilot", "retained unload state can be retried when the game thread returns")
assert_equal(ready.active, "", "unload retry clears resolved active state")
assert_equal(health, 0.55, "unload retry restores health baseline")
assert_equal(health_locked, false, "unload retry releases health lock")
assert_equal(hud_visible, true, "unload retry restores HUD baseline")

print("Dawnwalker bridge teardown-state harness passed.")
