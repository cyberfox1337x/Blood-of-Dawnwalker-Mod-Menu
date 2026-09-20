local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_add_item_pilot_tests")

local bridge_source = assert(arg[1], "Expected the bridge source path as argument 1.")
local bridge_root = assert(os.getenv("TEMP"), "TEMP must be set for the bridge harness.") .. "/DawnwalkerModMenuBridge"

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, received %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function assert_match(actual, pattern, label)
    if not tostring(actual):match(pattern) then
        error(string.format("%s did not match %s: %s", label, pattern, tostring(actual)), 2)
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
        "capability=inventory:add-item",
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
assert_match(source_text, '"inventory:add%-item"', "Add Item capability")
assert_match(source_text, "local MAX_ITEM_QUANTITY = 100", "per-command quantity cap")
assert_match(source_text, "ITEM_QUEST_MARKER", "quest item guard")
assert_match(source_text, "library:GetItemHandle%(player, asset, level%)", "reflected handle factory")
assert_match(source_text, "inventory:GetItemQuantity%(handle, false%)", "exact quantity readback")
assert_match(source_text, "inventory:TryAddItem%(handle, requested, true%)", "bounded add")
assert_match(source_text, "inventory:RemoveItem%(handle, %-requested%)", "bounded remove")
-- The bridge must never pull an unloaded asset into memory. Match an actual call rather
-- than the bare name, which legitimately appears in the explanatory comment.
assert_equal(source_text:find("StaticLoadObject%s*%("), nil, "bridge never calls StaticLoadObject")

local ITEM_PREFIX = "/Game/_Dawnwalker/Inventory/Items/"
local VALID_ITEM = ITEM_PREFIX .. "ITM_Herb_Common.ITM_Herb_Common"
local QUEST_ITEM = ITEM_PREFIX .. "ITM_Quest_NPOI_Dshrine01QuestItem.ITM_Quest_NPOI_Dshrine01QuestItem"

local world = make_object(4001, "/Script/Engine.World")
local inventory = make_object(4002, "/Script/DogwoodInventory.InventoryComponent")
local alternate_inventory = make_object(4003, "/Script/DogwoodInventory.InventoryComponent")
local player = make_object(4004, "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
local inventory_subsystem = make_object(4005, "/Script/DogwoodInventory.InventorySubsystem")
local subsystem_library = make_object(4006, "/Script/Engine.SubsystemBlueprintLibrary")
local inventory_subsystem_class = make_object(4007, "/Script/CoreUObject.Class")
local item_library = make_object(4008, "/Script/DogwoodInventory.InventoryBlueprintFunctionLibrary")
local item_asset = make_object(4009, "/Script/DogwoodInventory.ItemBaseDataAsset")
local wrong_asset = make_object(4010, "/Script/Engine.Texture2D")

local quantity = 5
local current_inventory = inventory
local add_behavior = "normal"
local mutation_calls = {}
local handle_calls = 0
local current_item_asset = item_asset

player.GetWorld = function() return world end
player.GetInventoryComponent = function() return current_inventory end
inventory_subsystem.GetPlayerInventoryComponent = function() return current_inventory end
subsystem_library.GetGameInstanceSubsystem = function(_, context, subsystem_class)
    assert_equal(context, player, "inventory subsystem context")
    assert_equal(subsystem_class, inventory_subsystem_class, "inventory subsystem class identity")
    return inventory_subsystem
end

local ITEM_HANDLE = { handle = true }
item_library.GetItemHandle = function(_, context, asset, level)
    handle_calls = handle_calls + 1
    assert_equal(context, player, "handle world context")
    assert_equal(asset, current_item_asset, "handle asset identity")
    assert_equal(type(level), "number", "handle item level type")
    return ITEM_HANDLE
end

inventory.GetItemQuantity = function(_, handle, match_asset_only)
    assert_equal(handle, ITEM_HANDLE, "quantity readback handle")
    assert_equal(match_asset_only, false, "quantity readback exactness flag")
    return quantity
end
inventory.TryAddItem = function(_, handle, amount, skip_new_item_check)
    assert_equal(handle, ITEM_HANDLE, "add handle")
    assert_equal(skip_new_item_check, true, "add skips the new-item check")
    table.insert(mutation_calls, amount)
    if add_behavior == "partial" then
        quantity = quantity + 1
        add_behavior = "normal"
    elseif add_behavior == "out-of-bounds" then
        quantity = quantity + amount + 1
        add_behavior = "normal"
    elseif add_behavior == "noop" then
        add_behavior = "normal"
    else
        quantity = quantity + amount
    end
    return 1
end
inventory.RemoveItem = function(_, handle, amount)
    assert_equal(handle, ITEM_HANDLE, "remove handle")
    table.insert(mutation_calls, -amount)
    quantity = math.max(0, quantity - amount)
    return 1
end
alternate_inventory.GetItemQuantity = function() return 999 end
alternate_inventory.TryAddItem = function() return 1 end
alternate_inventory.RemoveItem = function() return 1 end

package.preload["UEHelpers"] = function()
    return { GetPlayer = function() return player end }
end

local clock = 1900002000
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

local missing_asset = false
StaticFindObject = function(path)
    if path == "/Script/Engine.Default__SubsystemBlueprintLibrary" then return subsystem_library end
    if path == "/Script/DogwoodInventory.InventorySubsystem" then return inventory_subsystem_class end
    if path == "/Script/DogwoodInventory.Default__InventoryBlueprintFunctionLibrary" then return item_library end
    if path == VALID_ITEM then
        if missing_asset then return nil end
        return current_item_asset
    end
    if path == ITEM_PREFIX .. "ITM_Wrong.ITM_Wrong" then return wrong_asset end
    return nil
end

local poll_callback = nil
LoopAsync = function(milliseconds, callback)
    assert_equal(milliseconds, 150, "bridge poll interval")
    poll_callback = callback
end

assert(loadfile(bridge_source))()
assert_equal(type(poll_callback), "function", "bridge poll callback")

local command_path = bridge_root .. "/command.txt"
local response_path = bridge_root .. "/response.txt"
local ready = read_fields(bridge_root .. "/ready.txt")
assert_equal(ready.version, "0.3.21-pilot", "bridge version")
assert_match(ready.capabilities, "inventory:add%-item", "advertised Add Item capability")

local function execute(request_id, value)
    write_command(command_path, ready, request_id, value)
    poll_callback()
    return read_fields(response_path)
end

-- Read-only query: an asset path alone never mutates.
local calls_before_query = #mutation_calls
local query = execute("item-query", VALID_ITEM)
assert_equal(query.accepted, "1", "item query accepted")
assert_equal(query.readback, "5", "item query readback")
assert_equal(#mutation_calls, calls_before_query, "query performs no mutation")
assert_equal(handle_calls > 0, true, "query built a handle through the factory")

-- Exact add and exact inverse.
local added = execute("item-add", VALID_ITEM .. "|3")
assert_equal(added.accepted, "1", "add accepted")
assert_equal(added.readback, "8", "add exact readback")
local removed = execute("item-remove", VALID_ITEM .. "|-3")
assert_equal(removed.accepted, "1", "remove accepted")
assert_equal(removed.readback, "5", "remove restores exact baseline")

-- Malformed and out-of-range requests never reach a setter.
local calls_before_invalid = #mutation_calls
for index, invalid in ipairs({
    "",
    "|3",
    VALID_ITEM .. "|0",
    VALID_ITEM .. "|101",
    VALID_ITEM .. "|-101",
    VALID_ITEM .. "|1.5",
    VALID_ITEM .. "|3|4|5",
    VALID_ITEM .. "|3|256",
    "/Game/Other/ITM_Elsewhere.ITM_Elsewhere|1",
    QUEST_ITEM .. "|1",
}) do
    local rejected = execute("item-invalid-" .. tostring(index), invalid)
    assert_equal(rejected.accepted, "0", "invalid Add Item request rejected: " .. invalid)
end
assert_equal(#mutation_calls, calls_before_invalid, "invalid requests never mutate")

local quest_rejection = execute("item-quest", QUEST_ITEM .. "|1")
assert_match(quest_rejection.message, "quest items", "quest item refusal message")

-- Unloaded assets are refused rather than loaded.
missing_asset = true
local unloaded = execute("item-unloaded", VALID_ITEM .. "|1")
assert_equal(unloaded.accepted, "0", "unloaded asset rejected")
assert_match(unloaded.message, "not loaded", "unloaded asset message")
missing_asset = false

-- A resolved object of the wrong class is refused.
local wrong_class = execute("item-wrong-class", ITEM_PREFIX .. "ITM_Wrong.ITM_Wrong|1")
assert_equal(wrong_class.accepted, "0", "wrong asset class rejected")
assert_match(wrong_class.message, "not an item data asset", "wrong class message")

-- Underflow guard.
quantity = 0
local underflow = execute("item-underflow", VALID_ITEM .. "|-1")
assert_equal(underflow.accepted, "0", "quantity below zero rejected")
assert_match(underflow.message, "below zero", "underflow message")

-- A no-op mutation reports the exact untouched baseline instead of claiming success.
quantity = 10
add_behavior = "noop"
local noop = execute("item-noop", VALID_ITEM .. "|4")
assert_equal(noop.accepted, "0", "no-op rejected")
assert_match(noop.message, "remained exact", "no-op message")
assert_equal(quantity, 10, "no-op left the baseline untouched")

-- A partial delta is inverted by exactly the observed amount.
quantity = 20
add_behavior = "partial"
local partial = execute("item-partial", VALID_ITEM .. "|5")
assert_equal(partial.accepted, "0", "partial delta rejected")
assert_match(partial.message, "was reversed", "partial rollback message")
assert_equal(quantity, 20, "partial delta restored the exact baseline")

-- An out-of-bounds observed delta is never inverted.
quantity = 30
add_behavior = "out-of-bounds"
local calls_before_oob = #mutation_calls
local out_of_bounds = execute("item-out-of-bounds", VALID_ITEM .. "|2")
assert_equal(out_of_bounds.accepted, "0", "out-of-bounds delta rejected")
assert_match(out_of_bounds.message, "out%-of%-bounds", "out-of-bounds message")
assert_equal(#mutation_calls, calls_before_oob + 1, "out-of-bounds delta is not inverted")

-- Divergent inventory identity is refused before any mutation.
quantity = 40
current_inventory = alternate_inventory
local divergent = execute("item-divergent", VALID_ITEM .. "|1")
assert_equal(divergent.accepted, "0", "divergent inventory identity rejected")
current_inventory = inventory

print("Dawnwalker Add Item pilot harness passed.")
