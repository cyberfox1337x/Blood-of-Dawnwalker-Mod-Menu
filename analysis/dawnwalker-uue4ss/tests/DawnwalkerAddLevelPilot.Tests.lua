local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_add_level_unblock_pilot_tests")

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
assert_match(source_text, '"player:add%-level"', "Add Level capability")
assert_match(source_text, '"player:unblock%-trait"', "Unblock Trait capability")
assert_match(source_text, "subsystem:ForceLevelUpTo%(requested, true%)", "exact level setter with trait points")
assert_match(source_text, "subsystem:UnblockTraitToLevel%(trait_name, target_level, false, false%)", "quiet unblock call")
assert_match(source_text, "subsystem:GetCurrentLevel%(%)", "level readback")
assert_match(source_text, "subsystem:GetTraitUnblockedLevel%(trait_name%)", "unblock readback")
assert_match(source_text, "local MAX_CHARACTER_LEVEL = 100", "level cap")
assert_match(source_text, "local MAX_TRAIT_ROSTER = 4096", "trait roster bound")
assert_match(source_text, "subsystem:GetAllTraits%(%) end", "roster enumeration")
assert_match(source_text, "return trait%.Skill_ID end", "roster Skill_ID property read")
-- 0.3.20: every container read path must unwrap wrapped remote entries before validation.
assert_match(source_text, "entries%[#entries %+ 1%] = unwrap_remote_value%(value%)", "roster table branch unwraps")
assert_match(source_text, "entries%[#entries %+ 1%] = unwrap_remote_value%(element%)", "roster numeric branch unwraps")
-- 0.3.21: an unblock the game commits a beat later is verified on later polls, never reported
-- as a failure on the same dispatch that performed the call (proved on 0.3.20: the readback
-- lagged exactly one beat while the next dispatch read the requested level).
assert_match(source_text, "local MAX_UNBLOCK_VERIFY_TICKS = 40", "deferred verification tick bound")
assert_match(source_text, "local function poll_unblock_verification%(%)", "deferred verification poll")
assert_match(source_text, "poll_unblock_verification%(%)%s*$?", "deferred verification runs each poll")
assert_match(source_text, 'status == "commit%-pending"', "commit-pending status defers the response")
-- Neither call has an inverse in this build; the source must never pretend otherwise.
assert_equal(source_text:find("ForceLevelDown"), nil, "no fabricated level-down inverse")
assert_equal(source_text:find("BlockTraitToLevel"), nil, "no fabricated re-block inverse")
-- Raw request strings must never reach an FName-typed engine call: the 0.3.17 live crash
-- was exactly that marshalling failure, so only a roster-derived Skill_ID value is allowed.
for _, forbidden in ipairs({
    "subsystem:GetTrait(trait_id",
    "subsystem:GetTraitUnblockedLevel(trait_id",
    "subsystem:UnblockTraitToLevel(trait_id",
}) do
    assert_equal(source_text:find(forbidden, 1, true), nil, "no raw-string FName call: " .. forbidden)
end

local world = make_object(5001, "/Script/Engine.World")
local player = make_object(5002, "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
local char_dev = make_object(5003, "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem")
local char_dev_class = make_object(5004, "/Script/CoreUObject.Class")
local subsystem_library = make_object(5005, "/Script/Engine.SubsystemBlueprintLibrary")

local TRAIT_ASSET_PATH = "/Script/DogwoodCharacterDevelopment.TraitAsset"

-- FName properties surface as values whose only reliable string conversion is ToString,
-- exactly like a live Skill_ID property read in the pinned UE4SS build.
local function name_value(value)
    return { ToString = function() return value end }
end

local function make_trait(address, skill_id)
    local trait = make_object(address, TRAIT_ASSET_PATH)
    trait.Skill_ID = name_value(skill_id)
    return trait
end

local trait_alpha = make_trait(5006, "trait.alpha")
local trait_beta = make_trait(5007, "trait.beta")
local trait_gamma = make_trait(5010, "trait.gamma")
local roster = { trait_alpha, trait_beta }
local roster_mode = "normal"

-- 0.3.20: the live GetAllTraits() container returns wrapped remote values on the table and
-- numeric shapes (proved by the 0.3.19 live probe, where every roster entry failed IsValid),
-- so mocks must also exercise entries that only resolve through a :get() proxy.
local function wrap_remote(object)
    return { get = function() return object end }
end

local function id_key(value)
    if type(value) == "string" then return value end
    if value == nil then return nil end
    local ok, key = pcall(function() return value:ToString() end)
    return (ok and type(key) == "string") and key or nil
end

local function trait_for(key)
    if key == "trait.alpha" then return trait_alpha end
    if key == "trait.beta" then return trait_beta end
    if key == "trait.gamma" then return trait_gamma end
    return nil
end

local level = 3
local xp = 250
local unblocked = { ["trait.alpha"] = 0, ["trait.beta"] = 2, ["trait.gamma"] = 0 }
local force_calls = {}
local unblock_calls = {}
local drift_next_level_call = false
-- 0.3.21: reproduce the live game's beat-late unblock commit. While commit_lag is set,
-- UnblockTraitToLevel records its intent and the unblocked level only moves once
-- flush_pending_commits() runs (the game's own later beat).
local commit_lag = false
local pending_commits = {}

player.GetWorld = function() return world end
subsystem_library.GetGameInstanceSubsystem = function(_, context, subsystem_class)
    assert_equal(context, player, "char dev subsystem context")
    assert_equal(subsystem_class, char_dev_class, "char dev subsystem class identity")
    return char_dev
end

char_dev.GetCurrentLevel = function() return level end
char_dev.GetCurrentXP = function() return xp end
char_dev.ForceLevelUpTo = function(_, target, receive_points)
    table.insert(force_calls, { target = target, receive_points = receive_points })
    if drift_next_level_call then
        char_dev._address = 9999
        drift_next_level_call = false
        return
    end
    level = target
end
char_dev.GetAllTraits = function()
    if roster_mode == "throws" then error("GetAllTraits exploded") end
    if roster_mode == "oversized" then
        local oversized = {}
        for index = 1, 5000 do oversized[index] = make_trait(6000 + index, "bulk." .. index) end
        return oversized
    end
    if roster_mode == "wrong_class" then
        return { trait_alpha, make_object(5099, "/Script/Engine.Actor") }
    end
    if roster_mode == "duplicate" then
        return { trait_alpha, make_trait(5008, "trait.alpha") }
    end
    if roster_mode == "wrapped" then
        return { wrap_remote(trait_alpha), wrap_remote(trait_gamma) }
    end
    return roster
end
char_dev.GetTrait = function(_, id)
    return trait_for(id_key(id))
end
char_dev.GetTraitUnblockedLevel = function(_, id) return unblocked[id_key(id)] or 0 end
char_dev.UnblockTraitToLevel = function(_, id, target, can_show_video, show_notification)
    local key = id_key(id)
    table.insert(unblock_calls, {
        id = id, key = key, target = target, video = can_show_video, notification = show_notification,
    })
    if key ~= nil and unblocked[key] ~= nil then
        if commit_lag then
            pending_commits[key] = target
        else
            unblocked[key] = target
        end
    end
end

-- Applies intents recorded under commit_lag, mimicking the game's own later commit beat.
local function flush_pending_commits()
    for key, target in pairs(pending_commits) do
        if unblocked[key] ~= nil then unblocked[key] = target end
    end
    pending_commits = {}
end

package.preload["UEHelpers"] = function()
    return { GetPlayer = function() return player end }
end

local clock = 1900003000
os.time = function() clock = clock + 1 return clock end
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
    if path == "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem" then return char_dev_class end
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
assert_match(ready.capabilities, "player:add%-level", "advertised Add Level")
assert_match(ready.capabilities, "player:unblock%-trait", "advertised Unblock Trait")

local counter = 0
local function execute(capability, value)
    counter = counter + 1
    write_command(command_path, ready, "lvl-" .. tostring(counter), capability, value)
    poll_callback()
    return read_fields(response_path)
end

-- ADD LEVEL -----------------------------------------------------------------

local query = execute("player:add-level", "")
assert_equal(query.accepted, "1", "level query accepted")
assert_equal(query.readback, "3", "level query readback")
assert_match(query.message, "XP 250", "level query reports XP")
assert_equal(#force_calls, 0, "query performs no mutation")

-- Forward-only: equal and lower targets must be refused, never silently ignored.
local same = execute("player:add-level", "3")
assert_equal(same.accepted, "0", "same level refused")
assert_match(same.message, "one%-way", "same level explains one-way")
local lower = execute("player:add-level", "2")
assert_equal(lower.accepted, "0", "lower level refused")
assert_equal(#force_calls, 0, "refused targets never call the setter")

for _, invalid in ipairs({ "0", "101", "-5", "2.5", "abc" }) do
    local rejected = execute("player:add-level", invalid)
    assert_equal(rejected.accepted, "0", "invalid level refused: " .. invalid)
end
assert_equal(#force_calls, 0, "invalid levels never call the setter")

local raised = execute("player:add-level", "7")
assert_equal(raised.accepted, "1", "forward level accepted")
assert_equal(raised.readback, "7", "exact level readback")
assert_equal(#force_calls, 1, "one setter call")
assert_equal(force_calls[1].target, 7, "setter target")
assert_equal(force_calls[1].receive_points, true, "trait points granted on level up")
assert_match(raised.message, "one%-way", "success states irreversibility")

-- A setter that does not move the level reports the exact untouched baseline.
level = 7
char_dev.ForceLevelUpTo = function(_, target, receive_points)
    table.insert(force_calls, { target = target, receive_points = receive_points })
end
local noop = execute("player:add-level", "9")
assert_equal(noop.accepted, "0", "no-op level refused")
assert_match(noop.message, "did not change", "no-op message")
assert_equal(level, 7, "no-op left the level untouched")

-- Identity drift during the call is a hard failure that names the save backup.
char_dev.ForceLevelUpTo = function(_, target)
    table.insert(force_calls, { target = target })
    char_dev._address = 8888
    char_dev.GetAddress = function() return 8888 end
end
local drift = execute("player:add-level", "10")
assert_equal(drift.accepted, "0", "identity drift refused")
assert_match(drift.message, "save backup", "drift names the recovery path")
char_dev.GetAddress = function() return 5003 end

-- UNBLOCK TRAIT --------------------------------------------------------------

local no_id = execute("player:unblock-trait", "")
assert_equal(no_id.accepted, "0", "empty trait id refused")

for _, invalid in ipairs({ "bad id!", "a|b|c", "trait.alpha|0", "trait.alpha|11", "trait.alpha|x" }) do
    local rejected = execute("player:unblock-trait", invalid)
    assert_equal(rejected.accepted, "0", "invalid unblock refused: " .. invalid)
end
assert_equal(#unblock_calls, 0, "invalid unblocks never call the setter")

local unknown = execute("player:unblock-trait", "trait.missing")
assert_equal(unknown.accepted, "0", "unknown trait id refused")
assert_match(unknown.message, "could not resolve", "unknown trait message")
assert_equal(#unblock_calls, 0, "unknown trait never calls the setter")

-- Roster resolution failures reject before any FName-typed engine call.
roster_mode = "throws"
local roster_throws = execute("player:unblock-trait", "trait.alpha")
assert_equal(roster_throws.accepted, "0", "unreadable roster refused")
assert_match(roster_throws.message, "could not read the trait roster", "unreadable roster message")
assert_equal(#unblock_calls, 0, "unreadable roster never calls the setter")

roster_mode = "oversized"
local oversized = execute("player:unblock-trait", "trait.alpha")
assert_equal(oversized.accepted, "0", "oversized roster refused")
assert_match(oversized.message, "safety bound", "oversized roster message")
assert_equal(#unblock_calls, 0, "oversized roster never calls the setter")

roster_mode = "wrong_class"
local wrong_class = execute("player:unblock-trait", "trait.alpha")
assert_equal(wrong_class.accepted, "0", "wrong-class roster entry refused")
assert_match(wrong_class.message, "wrong class", "wrong-class roster message")
assert_equal(#unblock_calls, 0, "wrong-class roster never calls the setter")

roster_mode = "duplicate"
local duplicate = execute("player:unblock-trait", "trait.alpha")
assert_equal(duplicate.accepted, "0", "duplicate Skill_ID refused")
assert_match(duplicate.message, "duplicate Skill_ID", "duplicate roster message")
assert_equal(#unblock_calls, 0, "duplicate roster never calls the setter")
roster_mode = "normal"

local unblock = execute("player:unblock-trait", "trait.alpha")
assert_equal(unblock.accepted, "1", "unblock accepted")
assert_equal(unblock.readback, "1", "unblock exact readback")
assert_equal(#unblock_calls, 1, "one unblock call")
assert_equal(unblock_calls[1].id, trait_alpha.Skill_ID, "unblock passes the roster Skill_ID value")
assert_equal(unblock_calls[1].key, "trait.alpha", "unblock trait id")
assert_equal(unblock_calls[1].target, 1, "default unblock level")
assert_equal(unblock_calls[1].video, false, "unblock video suppressed")
assert_equal(unblock_calls[1].notification, false, "unblock notification suppressed")
assert_match(unblock.message, "one%-way", "unblock states irreversibility")

local levelled = execute("player:unblock-trait", "trait.alpha|4")
assert_equal(levelled.accepted, "1", "levelled unblock accepted")
assert_equal(levelled.readback, "4", "levelled unblock readback")

-- Already unblocked at or above the target is a success that calls no setter.
local calls_before_idempotent = #unblock_calls
local idempotent = execute("player:unblock-trait", "trait.beta|1")
assert_equal(idempotent.accepted, "1", "already-unblocked accepted")
assert_match(idempotent.message, "already unblocked", "already-unblocked message")
assert_equal(#unblock_calls, calls_before_idempotent, "already-unblocked calls no setter")

-- 0.3.20 wrapped remote roster: entries that only resolve through a :get() proxy must be
-- unwrapped by the reader before resolution, exactly like the live GetAllTraits() shape.
roster_mode = "wrapped"
local calls_before_wrapped = #unblock_calls
local wrapped = execute("player:unblock-trait", "trait.gamma")
assert_equal(wrapped.accepted, "1", "wrapped roster resolves after unwrap")
assert_equal(wrapped.readback, "1", "wrapped unblock exact readback")
assert_equal(#unblock_calls, calls_before_wrapped + 1, "wrapped unblock calls the setter once")
assert_equal(unblock_calls[#unblock_calls].id, trait_gamma.Skill_ID, "wrapped unblock passes the roster Skill_ID value")
assert_equal(unblock_calls[#unblock_calls].key, "trait.gamma", "wrapped unblock trait id")
roster_mode = "normal"

-- 0.3.21 DEFERRED VERIFICATION ------------------------------------------------

-- A commit-pending command must not carry a premature verdict: its final response arrives
-- from poll_unblock_verification on a later poll once the commit is observable, so these
-- helpers dispatch by request id and pump polls until that request's response appears.
local verify_index = 0
local function send(capability, value)
    verify_index = verify_index + 1
    local request_id = "vr-" .. tostring(verify_index)
    write_command(command_path, ready, request_id, capability, value)
    poll_callback()
    return request_id
end
local function pump(request_id, ticks)
    for _ = 1, ticks do
        poll_callback()
        local fields = read_fields(response_path)
        if fields.request_id == request_id then return fields end
    end
    return nil
end

-- Success is reported only once the later beat commits the level (alpha 4 -> 5); the
-- dispatch poll itself must not answer.
commit_lag = true
local calls_before_lagged = #unblock_calls
local lagged_id = send("player:unblock-trait", "trait.alpha|5")
assert_equal(pump(lagged_id, 1), nil, "no response before the commit beat")
flush_pending_commits()
local lagged = pump(lagged_id, 4)
assert_match(lagged, "table", "deferred response arrives after the commit")
assert_equal(lagged.accepted, "1", "deferred unblock accepted")
assert_equal(lagged.readback, "5", "deferred unblock readback after commit")
assert_match(lagged.message, "unblocked to level 5", "deferred success message")
assert_match(lagged.message, "one%-way", "deferred success states irreversibility")
assert_equal(#unblock_calls, calls_before_lagged + 1, "lagged unblock calls the setter once")
assert_equal(unblock_calls[#unblock_calls].key, "trait.alpha", "lagged unblock trait id")
assert_equal(unblock_calls[#unblock_calls].target, 5, "lagged unblock target")

-- A newer command supersedes an unsettled verification; the stale record is answered with
-- the recovery action instead of silently discarding the client's request.
local calls_before_supersede = #unblock_calls
local stale_id = send("player:unblock-trait", "trait.alpha|6")
local current_id = send("player:unblock-trait", "trait.beta|3")
local stale_response = read_fields(response_path)
assert_equal(stale_response.request_id, stale_id, "superseded record answered first")
assert_equal(stale_response.accepted, "0", "superseded record rejected")
assert_match(stale_response.message, "superseded by a newer bridge command", "supersede message")
flush_pending_commits()
local current = pump(current_id, 4)
assert_match(current, "table", "current unblock settles after supersede")
assert_equal(current.accepted, "1", "current unblock accepted after supersede")
assert_equal(current.readback, "3", "current unblock readback after commit")
assert_equal(#unblock_calls, calls_before_supersede + 2, "both supersede dispatches call the setter")

-- A level the game never commits is rejected once the bounded window is exhausted, with the
-- exact untouched level named (beta is at 3 after the supersede test; the 4 request never lands).
local calls_before_hung = #unblock_calls
local hung_id = send("player:unblock-trait", "trait.beta|4")
local exhausted = pump(hung_id, 48)
assert_match(exhausted, "table", "bounded verification eventually answers")
assert_equal(exhausted.accepted, "0", "never-committed unblock rejected")
assert_match(exhausted.message, "bounded verification window", "exhaustion message")
assert_match(exhausted.message, "level 3 remained exact", "exhaustion reports the exact stale level")
assert_equal(#unblock_calls, calls_before_hung + 1, "hung unblock calls the setter once")
commit_lag = false

print("Dawnwalker Add Level and Unblock Trait pilot harness passed.")
