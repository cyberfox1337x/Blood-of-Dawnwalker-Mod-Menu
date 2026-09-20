local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_roster_enumerator")

-- TEMPORARY read-only roster enumerator for live pilot probe sessions (0.3.20 roster-unwrap
-- discovery; 0.3.21 deferred-unblock probe).
--
-- This module is NOT part of the DawnwalkerModBridge pilot payload. It is installed into the
-- game's UE4SS Mods directory for exactly one session, writes the live GetAllTraits() roster
-- (Skill_ID, unblocked level, trait level) to the bridge root, and is then removed and the
-- Mods tree restored byte-exactly. It performs only the read-only snapshot reads the Unlock
-- All Skills planner probe already proved: GetAllTraits(), GetTraitUnblockedLevel(), and
-- GetTraitLevel(). It never calls a setter and it never advertises a capability.
--
-- The only purpose is to discover a real Skill_ID for the Unblock Trait live probe, because
-- the pinned build keeps no offline roster listing and a raw-string FName guess would be
-- rejected (or, under the old 0.3.18 code, could crash the game).
--
-- The bridge's ready.txt is the gating signal: the roster is only read once the bridge itself
-- reports a stable playable pawn (phase pilot, all capabilities), and any anomalous read
-- (empty roster, invalid entry, read error) is retried instead of being recorded, because the
-- trait data tables populate during the save-load transition and reads inside that window
-- return empty or stale containers.

local MAX_TRAITS = 4096
local BRIDGE_ROOT = (os.getenv("TEMP") or os.getenv("TMP") or ".") .. "/DawnwalkerModMenuBridge"
local ROSTER_PATH = BRIDGE_ROOT .. "/roster.txt"
local READY_PATH = BRIDGE_ROOT .. "/ready.txt"
local CHAR_DEV_SUBSYSTEM_PATH = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"

local done = false
local attempts = 0
local stable_ticks = 0
local last_progress_second = 0

local function progress(message)
    local now = os.time()
    if now == last_progress_second then return end
    last_progress_second = now
    print("[DawnwalkerRosterEnumerator] " .. message)
end

local function is_valid(object)
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

local function is_whole_number(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
        and value % 1 == 0
end

local function as_string(value)
    if type(value) == "string" then return value end
    if value == nil then return nil end
    local ok, converted = pcall(function() return value:ToString() end)
    if ok and type(converted) == "string" then return converted end
    return nil
end

local function unwrap_remote_value(value)
    if value == nil then return nil end
    local unwrap_ok, unwrapped = pcall(function() return value:get() end)
    if unwrap_ok then return unwrapped end
    return value
end

local function read_text(path)
    local ok, contents = pcall(function()
        local file = io.open(path, "r")
        if file == nil then return nil end
        local text = file:read("*a")
        file:close()
        return text
    end)
    return ok and contents or nil
end

-- Returns true when the bridge ready.txt reports a freshly heartbeated playable pilot session.
local function bridge_has_stable_player()
    local text = read_text(READY_PATH)
    if text == nil then return false end
    local fields = {}
    for line in text:gmatch("[^\r\n]+") do
        local separator = line:find("=", 1, true)
        if separator and separator > 1 then
            fields[line:sub(1, separator - 1)] = line:sub(separator + 1)
        end
    end
    if fields.protocol ~= "1" or fields.phase ~= "pilot" then return false end
    local heartbeat = tonumber(fields.heartbeat or "")
    if heartbeat == nil or math.abs(os.time() - heartbeat) > 5 then return false end
    local capabilities = fields.capabilities or ""
    return capabilities:find("player:unblock-trait", 1, true) ~= nil
end

-- Bounded reflected container read through the same two ABI shapes the bridge and the
-- Unlock All Skills planner use; an incomplete walk is a hard failure, never a partial read.
local function read_bounded_array(container)
    if container == nil then return nil, "container was nil" end

    if type(container) == "table" then
        local entries = {}
        for index, value in ipairs(container) do
            if index > MAX_TRAITS then return nil, "container exceeded its safety bound" end
            entries[#entries + 1] = unwrap_remote_value(value)
        end
        return entries, nil
    end

    local for_each_ok, for_each = pcall(function() return container.ForEach end)
    if for_each_ok and type(for_each) == "function" then
        local entries = {}
        local overflow = false
        local iterate_ok, iterate_error = pcall(function()
            for_each(container, function(_index, element)
                if #entries >= MAX_TRAITS then overflow = true return end
                entries[#entries + 1] = unwrap_remote_value(element)
            end)
        end)
        if not iterate_ok then return nil, "container iteration failed: " .. tostring(iterate_error) end
        if overflow then return nil, "container exceeded its safety bound" end
        return entries, nil
    end

    local count_ok, count = pcall(function() return #container end)
    if not count_ok or not is_whole_number(count) or count < 0 then
        return nil, "container had an invalid size"
    end
    if count > MAX_TRAITS then return nil, "container exceeded its safety bound" end

    local entries = {}
    for index = 1, count do
        local element_ok, element = pcall(function() return container[index] end)
        if not element_ok or element == nil then
            return nil, "container entry " .. tostring(index) .. " was unreadable"
        end
        entries[#entries + 1] = unwrap_remote_value(element)
    end
    return entries, nil
end

local function write_atomic(path, contents)
    local temporary_path = path .. ".roster.tmp"
    local ok, error_message = pcall(function()
        local file = io.open(temporary_path, "w")
        if file == nil then error("could not open temporary roster file") end
        file:write(contents)
        file:close()
        os.remove(path)
        os.rename(temporary_path, path)
    end)
    if ok then return true, nil end
    local fallback_ok, fallback_error = pcall(function()
        local file = io.open(path, "w")
        if file == nil then error("could not open roster file") end
        file:write(contents)
        file:close()
    end)
    if fallback_ok then return true, nil end
    return false, tostring(error_message) .. " / " .. tostring(fallback_error)
end

local function run()
    if done then return end
    attempts = attempts + 1
    if attempts > 3600 then
        -- ~9 minutes at the 150 ms LoopAsync cadence; a stable pawn without a readable roster
        -- after that long is a real anomaly, not a slow boot.
        done = true
        write_atomic(ROSTER_PATH, "schema=1\nerror=timeout-no-stable-roster\n")
        return
    end

    if not bridge_has_stable_player() then
        stable_ticks = 0
        progress("waiting for a stable bridge player (tick " .. attempts .. ")")
        return
    end
    if stable_ticks < 20 then
        -- Require ~3 seconds of a fully stable bridge player state before reading.
        stable_ticks = stable_ticks + 1
        progress("bridge stable, stabilizing tick " .. stable_ticks)
        return
    end

    progress("stable; resolving subsystem")
    local UEHelpers = require("UEHelpers")
    local player = UEHelpers.GetPlayer()
    if not is_valid(player) then return end

    local library_ok, library = pcall(function()
        return StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary")
    end)
    if not library_ok or not is_valid(library) then return end

    local class_ok, subsystem_class = pcall(function()
        return StaticFindObject(CHAR_DEV_SUBSYSTEM_PATH)
    end)
    if not class_ok or not is_valid(subsystem_class) then return end

    local subsystem_ok, subsystem = pcall(function()
        return library:GetGameInstanceSubsystem(player, subsystem_class)
    end)
    if not subsystem_ok or not is_valid(subsystem) then return end

    local traits = nil
    local traits_ok, traits_call = pcall(function() return subsystem:GetAllTraits() end)
    if traits_ok and traits_call ~= nil then traits = traits_call end
    if traits == nil then
        -- Fallback: read the AllTraits member directly if the function route is unusable.
        local member_ok, member = pcall(function() return subsystem.AllTraits end)
        if member_ok and member ~= nil then traits = member end
    end
    if traits == nil then return end

    local entries, read_error = read_bounded_array(traits)
    if not entries then
        progress("roster read error: " .. tostring(read_error))
        return
    end
    if #entries == 0 then
        progress("roster read returned 0 entries; retrying")
        return
    end

    -- Any anomaly inside the read window means the container was still transitioning; retry
    -- the whole snapshot on the next tick instead of recording a poisoned roster.
    local records = {}
    local anomaly = nil
    for index = 1, #entries do
        local trait = entries[index]
        if not is_valid(trait) then
            anomaly = "trait entry " .. index .. " was not valid"
            break
        end
        local class_ok_entry, class_matches = pcall(function()
            return trait:IsA("/Script/DogwoodCharacterDevelopment.TraitAsset")
        end)
        if not class_ok_entry or not class_matches then
            anomaly = "trait entry " .. index .. " was not a TraitAsset"
            break
        end
        local id_ok, raw_id = pcall(function() return trait.Skill_ID end)
        local skill_id = id_ok and as_string(raw_id) or nil
        if skill_id == nil or skill_id == "" then
            anomaly = "trait entry " .. index .. " had no Skill_ID"
            break
        end
        local unblocked = nil
        local unblocked_ok, unblocked_value = pcall(function()
            return subsystem:GetTraitUnblockedLevel(raw_id)
        end)
        if unblocked_ok and is_whole_number(unblocked_value) then unblocked = unblocked_value end
        local level = nil
        local level_ok, level_value = pcall(function() return subsystem:GetTraitLevel(trait) end)
        if level_ok and is_whole_number(level_value) then level = level_value end
        records[#records + 1] = {
            skill_id = skill_id,
            unblocked = unblocked,
            level = level,
        }
    end
    if anomaly ~= nil then
        progress("roster anomaly: " .. anomaly)
        return
    end
    progress("roster snapshot succeeded with " .. #records .. " traits")

    table.sort(records, function(left, right) return left.skill_id < right.skill_id end)

    local lines = {
        "schema=1",
        "trait_count=" .. tostring(#records),
        "",
    }
    for index = 1, #records do
        lines[#lines + 1] = string.format(
            "%s\t%s\t%s",
            records[index].skill_id,
            records[index].unblocked == nil and "?" or tostring(records[index].unblocked),
            records[index].level == nil and "?" or tostring(records[index].level)
        )
    end
    local wrote, write_error = write_atomic(ROSTER_PATH, table.concat(lines, "\n") .. "\n")
    done = true
    print("[DawnwalkerRosterEnumerator] roster written with " .. tostring(#records) .. " traits"
        .. (wrote and "" or " (write failed: " .. tostring(write_error) .. ")"))
end

LoopAsync(150, run)