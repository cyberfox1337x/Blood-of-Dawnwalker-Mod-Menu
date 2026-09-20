local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_quest_journal_pilot_tests")

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
        "capability=quests:journal-readback",
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

local function make_text(value)
    return { ToString = function() return value end }
end

local function make_remote(value)
    return { get = function() return value end }
end

local function make_array(values)
    return setmetatable({}, {
        __len = function() return #values end,
        __index = function(_, index)
            if type(index) ~= "number" then return nil end
            local value = values[index]
            if value == nil then return nil end
            return make_remote(value)
        end,
    })
end

local function make_objective(text, state, current_count, max_count, optional)
    return {
        Text = make_text(text),
        State = state,
        CurrentCount = current_count,
        MaxCount = max_count,
        bIsOptional = optional,
    }
end

local function make_quest(address, title, objectives)
    local quest = make_object(address, "/Script/Quest.Quest")
    quest.Title = make_text(title)
    quest.State = 1
    quest.Objectives = make_array(objectives)
    return quest
end

local source_text = read_file(bridge_source)
assert_match(source_text, "/Script/Dawnwalker%.DawnwalkerGameStateBase", "exact ADawnwalkerGameStateBase contract")
assert_match(source_text, "game_state%.QuestJournal", "QuestJournal property contract")
assert_match(source_text, "journal:GetOpenedQuests%(opened_out%)", "GetOpenedQuests out-parameter contract")
assert_match(source_text, "local opened_quests = opened_out", "TArray out parameter reuses the passed table")
assert_match(source_text, "journal:GetTrackedQuest%(%)", "tracked quest readback")
assert_match(source_text, "for index = 1, expected_count do", "bounded direct TArray iteration")
assert_match(source_text, "objectives%[index%]", "one-based TArray element access")
assert_match(source_text, "for index = 1, expected_quest_count do", "bounded direct open-quest iteration")
assert_match(source_text, "opened_quests%[index%]", "one-based open-quest TArray access")
assert_equal(source_text:match("opened_out%.OutQuests"), nil, "incorrect named TArray out field absence")
assert_equal(source_text:match("journal%.OpenedQuests"), nil, "unsupported OpenedQuests property absence")
assert_equal(source_text:match("opened_quests:ForEach"), nil, "unsupported open-quest TArray ForEach absence")
assert_equal(source_text:match("objectives:ForEach"), nil, "unsupported TArray ForEach absence")
assert_equal(source_text:match("journal:TrackQuest"), nil, "quest mutation API absence")

local special_objectives = {
    make_objective("Find the key, then return; safely.", 1, 1, 3, false),
    make_objective("Optional: visit Łuków", 2, 1, 1, true),
    make_objective("Third objective", 0, 0, 0, false),
    make_objective("This fourth objective must be truncated", 1, 0, 1, false),
}
local quests = {
    make_quest(2101, "Blood, Stone;= Dawn", special_objectives),
    make_quest(2102, "Quest 2", {}),
    make_quest(2103, "Quest 3", { make_objective("Tracked objective", 1, 2.5, 5, false) }),
    make_quest(2104, "Quest 4", {}),
    make_quest(2105, "Quest 5", {}),
    make_quest(2106, "Quest 6", {}),
    make_quest(2107, "Quest 7 must be truncated", {}),
}
assert_equal(quests[1].Objectives.ForEach, nil, "live-shaped objective array has no ForEach")

local world = make_object(2001, "/Script/Engine.World")
local player = make_object(2002, "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
player.GetWorld = function() return world end
local journal = make_object(2003, "/Script/Quest.Journal")
local opened_quest_values = quests
local observed_opened_out = nil
journal.GetOpenedQuests = function(_, out)
    assert_equal(type(out), "table", "GetOpenedQuests out parameter")
    observed_opened_out = out
    for index, quest in ipairs(opened_quest_values) do
        out[index] = make_remote(quest)
    end
end
journal.GetTrackedQuest = function() return quests[3] end
assert_equal(journal.OpenedQuests, nil, "live-shaped Journal has no OpenedQuests property")
local game_state = make_object(2004, "/Script/Dawnwalker.DawnwalkerGameStateBase")
game_state.GetWorld = function() return world end
game_state.QuestJournal = journal

package.preload["UEHelpers"] = function()
    return {
        GetPlayer = function() return player end,
        GetGameStateBase = function() return game_state end,
    }
end

local clock = 1900000000
os.time = function()
    clock = clock + 1
    return clock
end
math.random = function() return 654321 end

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
assert_match(ready.capabilities, "quests:journal%-readback", "advertised Quest Journal capability")

write_command(command_path, ready, "quest-harness-1", "")
poll_callback()
local snapshot = read_fields(response_path)
assert_equal(snapshot.accepted, "1", "Quest Journal accepted flag")
assert_equal(snapshot.status, "applied", "Quest Journal status")
assert_match(snapshot.readback, "^schema=1;open_total=7;returned=6;truncated=1;", "bounded journal header")
assert_match(snapshot.readback, "Blood%%2C Stone%%3B%%3D Dawn", "delimiter-safe title")
assert_match(snapshot.readback, "Optional%%3A visit %%C5%%81uk%%C3%%B3w", "UTF-8 objective")
assert_match(snapshot.readback, "q=0,active,0,[^;]+,4,1", "objective truncation marker")
assert_match(snapshot.readback, "q=2,active,1,Quest 3,1,0", "tracked quest marker")
assert_equal(#snapshot.readback <= 8192, true, "bounded snapshot bytes")
assert_equal(#observed_opened_out, 7, "TArray out table receives one-based numeric entries")
assert_equal(observed_opened_out.OutQuests, nil, "TArray out table has no named OutQuests field")
assert_equal(observed_opened_out.ForEach, nil, "TArray out table has no ForEach method")

write_command(command_path, ready, "quest-harness-2", "mutate")
poll_callback()
local rejected = read_fields(response_path)
assert_equal(rejected.accepted, "0", "mutation accepted flag")
assert_equal(rejected.status, "rejected", "mutation status")
assert_match(rejected.message, "read%-only capability", "mutation rejection message")

opened_quest_values = {}
journal.GetTrackedQuest = function() return nil end
write_command(command_path, ready, "quest-harness-3", "")
poll_callback()
local empty_snapshot = read_fields(response_path)
assert_equal(empty_snapshot.accepted, "1", "empty journal accepted flag")
assert_equal(empty_snapshot.readback, "schema=1;open_total=0;returned=0;truncated=0", "empty journal readback")

print("Dawnwalker Quest Journal read-only harness passed.")
