local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_add_gold_pilot_tests")

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

local function write_command(path, ready, request_id, value)
    local command_file = assert(io.open(path, "w"), "Unable to write command file.")
    command_file:write(table.concat({
        "protocol=1",
        "boot_id=" .. ready.boot_id,
        "request_id=" .. request_id,
        "capability=player:add-gold",
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
assert_match(source_text, '"player:add%-gold"', "Add Gold capability")
assert_match(source_text, "player:GetInventoryComponent%(%)", "player inventory getter")
assert_match(source_text, "/Script/DogwoodInventory%.InventorySubsystem", "inventory subsystem class")
assert_match(source_text, "subsystem:GetPlayerInventoryComponent%(%)", "independent inventory getter")
assert_match(source_text, "inventory:GetCurrencyQuantity%(COIN_CURRENCY_TYPE%)", "Coin quantity readback")
assert_match(source_text, "inventory:AddCurrency%(COIN_CURRENCY_TYPE, requested%)", "signed Coin mutation")
assert_match(source_text, "rollback_inventory:AddCurrency%(COIN_CURRENCY_TYPE, %-observed_delta%)", "observed-delta rollback")
assert_match(source_text, "local MAX_GOLD_DELTA = 10000", "per-command magnitude cap")
assert_match(source_text, "local INT32_MAX = 2147483647", "int32 overflow guard")

local world = make_object(3001, "/Script/Engine.World")
local alternate_world = make_object(3008, "/Script/Engine.World")
local inventory = make_object(3002, "/Script/DogwoodInventory.InventoryComponent")
local alternate_inventory = make_object(3003, "/Script/DogwoodInventory.InventoryComponent")
local player = make_object(3004, "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
local inventory_subsystem = make_object(3005, "/Script/DogwoodInventory.InventorySubsystem")
local subsystem_library = make_object(3006, "/Script/Engine.SubsystemBlueprintLibrary")
local inventory_subsystem_class = make_object(3007, "/Script/CoreUObject.Class")

local quantity = 42
local alternate_quantity = 900
local current_inventory = inventory
local add_behavior = "normal"
local add_calls = {}
local player_getter_calls = 0
local subsystem_getter_calls = 0

player.GetWorld = function() return world end
player.GetInventoryComponent = function()
    player_getter_calls = player_getter_calls + 1
    return current_inventory
end
inventory_subsystem.GetPlayerInventoryComponent = function()
    subsystem_getter_calls = subsystem_getter_calls + 1
    return current_inventory
end
subsystem_library.GetGameInstanceSubsystem = function(_, context, subsystem_class)
    assert_equal(context, player, "inventory subsystem context")
    assert_equal(subsystem_class, inventory_subsystem_class, "inventory subsystem class identity")
    return inventory_subsystem
end

inventory.GetCurrencyQuantity = function(_, currency)
    assert_equal(currency, 0, "Coin enum readback")
    return quantity
end
inventory.AddCurrency = function(_, currency, delta)
    assert_equal(currency, 0, "Coin enum mutation")
    table.insert(add_calls, delta)
    if add_behavior == "partial" then
        quantity = quantity + (delta > 0 and 3 or -3)
        add_behavior = "normal"
    elseif add_behavior == "partial-then-post-identity-change" then
        quantity = quantity + (delta > 0 and 2 or -2)
        add_behavior = "post-identity-change"
    elseif add_behavior == "post-identity-change" then
        quantity = math.max(0, quantity + delta)
        world = alternate_world
        add_behavior = "normal"
    elseif add_behavior == "partial-and-change-identity" then
        quantity = quantity + (delta > 0 and 2 or -2)
        current_inventory = alternate_inventory
        add_behavior = "normal"
    elseif add_behavior == "out-of-bounds" then
        quantity = quantity + delta + (delta > 0 and 1 or -1)
        add_behavior = "normal"
    elseif add_behavior == "error-after-partial" then
        quantity = quantity + (delta > 0 and 1 or -1)
        add_behavior = "normal"
        error("synthetic AddCurrency failure")
    else
        quantity = math.max(0, quantity + delta)
    end
    return 1
end
alternate_inventory.GetCurrencyQuantity = function(_, currency)
    assert_equal(currency, 0, "alternate Coin enum readback")
    return alternate_quantity
end
alternate_inventory.AddCurrency = function(_, currency, delta)
    assert_equal(currency, 0, "alternate Coin enum mutation")
    alternate_quantity = math.max(0, alternate_quantity + delta)
end

package.preload["UEHelpers"] = function()
    return { GetPlayer = function() return player end }
end

local clock = 1900001000
os.time = function()
    clock = clock + 1
    return clock
end
math.random = function() return 765432 end

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
    if path == "/Script/DogwoodInventory.InventorySubsystem" then return inventory_subsystem_class end
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
assert_match(ready.capabilities, "player:add%-gold", "advertised Add Gold capability")

local function execute(request_id, value)
    write_command(command_path, ready, request_id, value)
    poll_callback()
    return read_fields(response_path)
end

local query = execute("gold-harness-query", "")
assert_equal(query.accepted, "1", "Gold query accepted")
assert_equal(query.readback, "42", "Gold query readback")
assert_equal(player_getter_calls > 0, true, "player inventory getter used")
assert_equal(subsystem_getter_calls > 0, true, "subsystem inventory getter used")

local added = execute("gold-harness-add", "1")
assert_equal(added.accepted, "1", "positive Gold delta accepted")
assert_equal(added.readback, "43", "positive Gold delta exact readback")
local removed = execute("gold-harness-remove", "-1")
assert_equal(removed.accepted, "1", "negative Gold delta accepted")
assert_equal(removed.readback, "42", "negative Gold delta exact restoration")

local calls_before_invalid = #add_calls
for index, invalid_value in ipairs({ "10001", "-10001", "0", "1.5", "NaN" }) do
    local rejected = execute("gold-harness-invalid-" .. tostring(index), invalid_value)
    assert_equal(rejected.accepted, "0", "invalid Gold delta rejected")
end
assert_equal(#add_calls, calls_before_invalid, "invalid deltas never invoke AddCurrency")

quantity = 2147483647
local overflow = execute("gold-harness-overflow", "1")
assert_equal(overflow.accepted, "0", "int32 overflow rejected")
assert_match(overflow.message, "overflow", "int32 overflow message")
quantity = 0
local underflow = execute("gold-harness-underflow", "-1")
assert_equal(underflow.accepted, "0", "negative balance rejected")
assert_match(underflow.message, "below zero", "negative balance message")

quantity = 50
add_behavior = "partial"
local partial = execute("gold-harness-partial", "10")
assert_equal(partial.accepted, "0", "partial mutation rejected")
assert_match(partial.message, "was reversed", "partial mutation rollback message")
assert_equal(quantity, 50, "partial mutation exact baseline restored")
assert_equal(add_calls[#add_calls - 1], 10, "partial mutation requested delta")
assert_equal(add_calls[#add_calls], -3, "partial mutation inverse observed delta")

quantity = 60
add_behavior = "error-after-partial"
local failed_call = execute("gold-harness-call-failure", "5")
assert_equal(failed_call.accepted, "0", "throwing mutation rejected")
assert_match(failed_call.message, "was reversed", "throwing mutation rollback message")
assert_equal(quantity, 60, "throwing mutation exact baseline restored")
assert_equal(add_calls[#add_calls], -1, "throwing mutation inverse observed delta")

quantity = 70
add_behavior = "partial-and-change-identity"
local calls_before_identity_change = #add_calls
local identity_changed = execute("gold-harness-identity-change", "10")
assert_equal(identity_changed.accepted, "0", "identity-changing partial mutation rejected")
assert_match(identity_changed.message, "identity changed", "identity change refusal message")
assert_equal(#add_calls, calls_before_identity_change + 1, "identity change prevents inverse mutation")
assert_equal(quantity, 72, "identity-changing partial delta remains observable for save-backup recovery")
current_inventory = inventory

quantity = 75
add_behavior = "partial-then-post-identity-change"
local post_rollback_identity_changed = execute("gold-harness-post-rollback-identity-change", "10")
assert_equal(post_rollback_identity_changed.accepted, "0", "post-rollback identity change rejected")
assert_match(post_rollback_identity_changed.message, "rollback identity could not be verified", "post-rollback identity refusal message")
assert_match(post_rollback_identity_changed.message, "pretest save backup", "post-rollback identity recovery direction")
assert_equal(quantity, 75, "post-rollback identity change restored only the observed bounded delta")
world = make_object(3001, "/Script/Engine.World")

quantity = 80
add_behavior = "out-of-bounds"
local calls_before_out_of_bounds = #add_calls
local out_of_bounds = execute("gold-harness-out-of-bounds", "5")
assert_equal(out_of_bounds.accepted, "0", "out-of-bounds observed delta rejected")
assert_match(out_of_bounds.message, "out%-of%-bounds", "out-of-bounds rollback refusal message")
assert_equal(#add_calls, calls_before_out_of_bounds + 1, "out-of-bounds delta is not inverted")

print("Dawnwalker Add Gold pilot harness passed.")
