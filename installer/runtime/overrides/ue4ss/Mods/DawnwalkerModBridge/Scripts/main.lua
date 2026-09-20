local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_mod_bridge")
cyberfox1337x.function_signature("bridge_bootstrap")

local BRIDGE_PROTOCOL = "1"
local BRIDGE_VERSION = "0.1.0-discovery"
local BRIDGE_PHASE = "discovery"
local BRIDGE_ROOT = (os.getenv("TEMP") or os.getenv("TMP") or ".") .. "/DawnwalkerModMenuBridge"
local COMMAND_PATH = BRIDGE_ROOT .. "/command.txt"
local RESPONSE_PATH = BRIDGE_ROOT .. "/response.txt"
local READY_PATH = BRIDGE_ROOT .. "/ready.txt"
local BOOT_ID = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local CAPABILITY_SET = {}
local CAPABILITIES = ""

local last_command_id = ""
local last_ready_second = -1

local function log(message)
    print(string.format("[DawnwalkerModBridge] %s\n", tostring(message)))
end

local function sanitize(value)
    return tostring(value or ""):gsub("[\r\n]", " ")
end

cyberfox1337x.function_signature("local_file_transport")
local function write_atomic(path, contents)
    local temporary_path = path .. ".tmp"
    local file = io.open(temporary_path, "w")
    if file then
        file:write(contents)
        file:flush()
        file:close()
        os.remove(path)
        if os.rename(temporary_path, path) ~= nil then return true end
    end

    local fallback = io.open(path, "w")
    if not fallback then return false end
    fallback:write(contents)
    fallback:flush()
    fallback:close()
    return true
end

local function read_fields(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local fields = {}
    for line in file:lines() do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key then fields[key] = value end
    end
    file:close()
    return fields
end

local function write_ready()
    local now = os.time()
    if now == last_ready_second then return true end
    last_ready_second = now
    return write_atomic(READY_PATH, table.concat({
        "protocol=" .. BRIDGE_PROTOCOL,
        "boot_id=" .. BOOT_ID,
        "version=" .. BRIDGE_VERSION,
        "heartbeat=" .. tostring(now),
        "phase=" .. BRIDGE_PHASE,
        "capabilities=" .. CAPABILITIES,
        "active=",
        "",
    }, "\n"))
end

local function write_response(request_id, accepted, status, message, readback)
    return write_atomic(RESPONSE_PATH, table.concat({
        "protocol=" .. BRIDGE_PROTOCOL,
        "boot_id=" .. BOOT_ID,
        "request_id=" .. sanitize(request_id),
        "accepted=" .. (accepted and "1" or "0"),
        "status=" .. sanitize(status),
        "message=" .. sanitize(message),
        "readback=" .. sanitize(readback),
        "",
    }, "\n"))
end

local function poll_command()
    write_ready()
    local fields = read_fields(COMMAND_PATH)
    if not fields or not fields.request_id or fields.request_id == "" or fields.request_id == last_command_id then
        return false
    end

    last_command_id = fields.request_id
    if fields.protocol ~= BRIDGE_PROTOCOL or fields.boot_id ~= BOOT_ID then
        write_response(fields.request_id, false, "rejected", "Rejected stale or incompatible bridge command.", "")
        return false
    end

    local capability = fields.capability or ""
    if not CAPABILITY_SET[capability] then
        write_response(fields.request_id, false, "rejected", "Capability is not advertised by the verified Dawnwalker bridge.", "")
        return false
    end

    -- No capability may reach this branch until live reflection, readback,
    -- rollback, and an isolated offline test populate CAPABILITY_SET.
    write_response(fields.request_id, false, "rejected", "Capability contract is not implemented.", "")
    return false
end

log("loaded discovery bridge version " .. BRIDGE_VERSION .. " boot=" .. BOOT_ID)
if write_ready() == false then log("ready handshake write failed: " .. READY_PATH) end
LoopAsync(150, poll_command)

