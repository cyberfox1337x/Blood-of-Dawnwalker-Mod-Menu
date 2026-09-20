local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_save_driver")

-- TEMPORARY save/load driver for the Unblock Trait level-3+ persistence probe session.
--
-- This module is NOT part of the DawnwalkerModBridge pilot payload. It is installed into the
-- game's UE4SS Mods directory for exactly one probe session, consumes trigger files from the
-- bridge root, and is then removed with the Mods tree restored byte-exactly (the established
-- RosterEnumerator temporary-probe pattern).
--
-- Purpose: the persistence probe needs the game's own save pipeline (a real quicksave and a
-- real save reload), but the bridge deliberately never calls the save library (the repo
-- contract: the gold persistence control "never called the private TryQuicksave function"),
-- and blind pause-menu keyboard automation is fragile. This driver calls the shipping save
-- functions the game itself exposes -- /Script/Persistency SaveSystemBlueprintFunctionLibrary
-- TryQuicksave / TryQuickload / LoadLastSave -- exactly as the game's own UI would, records
-- every attempt, and never advertises a capability.
--
-- Trigger protocol (bridge root):
--   save_driver_cmd.txt:  cmd_id=<n>\nboot_id=<bridge boot>\naction=<quicksave|quickload>\n
--   save_driver_log.txt:  one appended line per attempt:
--                         cmd_id=<n> action=<a> ... result=<0|1> ...
-- Commands are gated on the bridge boot id: a command written for a previous boot is ignored,
-- so a stale quicksave trigger can never re-fire on the reload boot.

local BRIDGE_ROOT = (os.getenv("TEMP") or os.getenv("TMP") or ".") .. "/DawnwalkerModMenuBridge"
local CMD_PATH = BRIDGE_ROOT .. "/save_driver_cmd.txt"
local LOG_PATH = BRIDGE_ROOT .. "/save_driver_log.txt"
local READY_PATH = BRIDGE_ROOT .. "/ready.txt"

local SAVE_LIBRARY_PATH = "/Script/Persistency.Default__SaveSystemBlueprintFunctionLibrary"

local MAX_QUICKSAVE_RETRIES = 20
local MAX_QUICKLOAD_ATTEMPTS = 60
local STABLE_TICKS_REQUIRED = 20 -- ~3 s of stable gameplay at the 150 ms cadence

local consumed_cmd_id = 0
local quicksave_retries = 0
local quicksave_stable_ticks = 0
local quickload_attempts = 0
local quickload_stable_ticks = 0
local quickload_zero_streak = 0
local used_load_last_save = false
local quickload_done = false
local boot_ticks = 0

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

local function parse_fields(text)
    local fields = {}
    for line in text:gmatch("[^\r\n]+") do
        local separator = line:find("=", 1, true)
        if separator and separator > 1 then
            fields[line:sub(1, separator - 1)] = line:sub(separator + 1)
        end
    end
    return fields
end

local function read_ready_fields()
    local text = read_text(READY_PATH)
    if text == nil then return nil end
    return parse_fields(text)
end

local function current_boot_id()
    local fields = read_ready_fields()
    if fields == nil then return nil end
    return fields.boot_id
end

-- A freshly heartbeated playable pilot session, same gate the RosterEnumerator uses.
local function bridge_has_stable_player()
    local fields = read_ready_fields()
    if fields == nil then return false end
    if fields.protocol ~= "1" or fields.phase ~= "pilot" then return false end
    local heartbeat = tonumber(fields.heartbeat or "")
    if heartbeat == nil or math.abs(os.time() - heartbeat) > 5 then return false end
    local capabilities = fields.capabilities or ""
    return capabilities:find("player:unblock-trait", 1, true) ~= nil
end

local function is_valid(object)
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

local function get_save_library()
    local ok, library = pcall(function() return StaticFindObject(SAVE_LIBRARY_PATH) end)
    if ok and is_valid(library) then return library end
    return nil
end

local function call_bool(library, name)
    local ok, result = pcall(function() return library[name](library) end)
    if ok and type(result) == "boolean" then return result end
    if ok and type(result) == "number" then return result ~= 0 end
    return nil
end

local function append_log(line)
    local ok = pcall(function()
        local file = io.open(LOG_PATH, "a")
        if file == nil then return end
        file:write(line .. "\n")
        file:close()
    end)
    if not ok then print("[DawnwalkerSaveDriver] log write failed: " .. line) end
    print("[DawnwalkerSaveDriver] " .. line)
end

local function execute_quicksave(cmd_id)
    if not bridge_has_stable_player() then
        quicksave_stable_ticks = 0
        return
    end
    quicksave_stable_ticks = quicksave_stable_ticks + 1
    if quicksave_stable_ticks < STABLE_TICKS_REQUIRED then return end

    local library = get_save_library()
    if library == nil then
        append_log("cmd_id=" .. cmd_id .. " action=quicksave result=0 error=no-save-library")
        consumed_cmd_id = cmd_id
        return
    end
    local locked = call_bool(library, "IsSavingLocked")
    local has_saves = call_bool(library, "HasSavesToLoad")
    local saved = call_bool(library, "TryQuicksave")
    if saved then
        append_log(string.format("cmd_id=%d action=quicksave result=1 locked=%s hasSaves=%s",
            cmd_id, tostring(locked), tostring(has_saves)))
        consumed_cmd_id = cmd_id
        quicksave_retries = 0
    else
        quicksave_retries = quicksave_retries + 1
        if quicksave_retries % 5 == 0 then
            append_log(string.format("cmd_id=%d action=quicksave retry=%d locked=%s hasSaves=%s",
                cmd_id, quicksave_retries, tostring(locked), tostring(has_saves)))
        end
        if quicksave_retries > MAX_QUICKSAVE_RETRIES then
            append_log("cmd_id=" .. cmd_id .. " action=quicksave result=0 error=retries-exhausted")
            consumed_cmd_id = cmd_id
            quicksave_retries = 0
        end
    end
end

local function execute_quickload(cmd_id)
    if quickload_done then return end
    boot_ticks = boot_ticks + 1
    -- Let the boot settle ~45 s (startup movies + main menu interactivity) before touching saves.
    if boot_ticks < 300 then return end

    if bridge_has_stable_player() then
        -- The quickload landed: a playable pawn is back with the bridge fully ready.
        quickload_stable_ticks = quickload_stable_ticks + 1
        if quickload_stable_ticks >= STABLE_TICKS_REQUIRED then
            quickload_done = true
            consumed_cmd_id = cmd_id
            append_log("cmd_id=" .. cmd_id .. " action=quickload result=1 stable-player-confirmed")
        end
        return
    end
    quickload_stable_ticks = 0

    quickload_attempts = quickload_attempts + 1
    if quickload_attempts > MAX_QUICKLOAD_ATTEMPTS then
        append_log("cmd_id=" .. cmd_id .. " action=quickload result=0 error=attempts-exhausted")
        consumed_cmd_id = cmd_id
        quickload_done = true
        return
    end

    local library = get_save_library()
    if library == nil then return end

    local result
    if not used_load_last_save then
        result = call_bool(library, "TryQuickload")
        if result == false then
            quickload_zero_streak = quickload_zero_streak + 1
            if quickload_zero_streak >= 5 then
                used_load_last_save = true
                append_log("cmd_id=" .. cmd_id .. " action=quickload switching-to-LoadLastSave")
            end
        end
    else
        result = call_bool(library, "LoadLastSave")
    end
    if result == true then
        append_log("cmd_id=" .. cmd_id .. " action=quickload result=1 accepted-awaiting-pawn")
    elseif quickload_attempts % 5 == 0 then
        append_log("cmd_id=" .. cmd_id .. " action=quickload attempt=" .. quickload_attempts .. " result=0")
    end
end

local function run()
    local text = read_text(CMD_PATH)
    if text == nil then return end
    local fields = parse_fields(text)
    local cmd_id = tonumber(fields.cmd_id or "")
    local action = fields.action
    if cmd_id == nil or cmd_id <= consumed_cmd_id then return end

    -- Boot gating: only commands written for THIS bridge boot are ever executed.
    local cmd_boot = fields.boot_id
    local boot = current_boot_id()
    if cmd_boot == nil or boot == nil or cmd_boot ~= boot then return end

    if action == "quicksave" then
        execute_quicksave(cmd_id)
    elseif action == "quickload" then
        execute_quickload(cmd_id)
    else
        append_log("cmd_id=" .. cmd_id .. " action=" .. tostring(action) .. " result=0 error=unknown-action")
        consumed_cmd_id = cmd_id
    end
end

LoopAsync(150, run)
