local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("player_resolver")

--[[
Resolves the local player pawn without paying for a full object scan every time.

UEHelpers.GetPlayer() calls FindAllOf("PlayerController"), which walks the entire
UObject array - 60,931 objects on build 25191761, measured by the reflection dump - and
builds a Lua table of every match. Paying that once is reasonable. Paying it 6.7 times a
second on the runtime tick is not, and paying it inside a hook the game calls several
times per frame is what made the vampire form override cost frames: that hook resolved
the player on every ability quickslot lookup.

The cache is deliberately conservative. A cached pawn is handed back only while all of
these still hold:

  * the controller and the pawn both still answer IsValid(), and
  * the controller still reports that same pawn as its own, and
  * the entry is younger than the revalidation backstop.

Any of those failing costs one full resolve and then returns to the cheap path. So a
pawn swap, a controller swap or a destroyed player is picked up on the next call, and no
caller is ever handed a pawn the controller has already replaced.

The backstop deadline is measured with os.clock, which is processor time rather than
wall time. Under a busy game that runs faster than the wall, so the deadline expires
early rather than late - it errs toward re-resolving, never toward serving a stale pawn.
]]

local M = {}

-- Generous on purpose: the validity checks above are what make the cache correct, and
-- this only exists to recover from a swap those checks could not observe.
local REVALIDATE_MS = 2000

local function alive(object)
    if object == nil or object.IsValid == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

local function addressOf(object)
    local ok, address = pcall(function() return object:GetAddress() end)
    if not ok then return nil end
    return address
end

local function answers(object, method)
    if object[method] == nil then return false end
    local ok, answer = pcall(function() return object[method](object) end)
    return ok and answer == true
end

function M.New(deps)
    assert(type(deps) == "table", "Player resolver dependencies required")
    assert(type(deps.findAllOf) == "function", "Player resolver requires findAllOf")
    -- os.clock reports seconds of processor time; milliseconds keep the arithmetic
    -- readable and the unit obvious at the call site.
    local now = deps.now or function() return os.clock() * 1000 end

    local cachedController, cachedPawn, cachedAt = nil, nil, nil
    local scans, reuses = 0, 0

    local function forget()
        cachedController, cachedPawn, cachedAt = nil, nil, nil
    end

    -- The only expensive path in this module. Everything else exists to avoid it.
    local function fullResolve()
        scans = scans + 1
        forget()
        local controllers = deps.findAllOf("PlayerController")
        if type(controllers) ~= "table" or #controllers == 0 then
            controllers = deps.findAllOf("Controller")
        end
        if type(controllers) ~= "table" then return nil end
        for _, controller in ipairs(controllers) do
            if alive(controller)
                and (answers(controller, "IsPlayerController") or answers(controller, "IsLocalPlayerController")) then
                local ok, pawn = pcall(function() return controller.Pawn end)
                if ok and alive(pawn) then
                    cachedController, cachedPawn, cachedAt = controller, pawn, now()
                    return pawn
                end
            end
        end
        return nil
    end

    -- A handful of native calls instead of a sixty-thousand object walk.
    local function stillOurs()
        if not cachedPawn or not cachedController or not cachedAt then return false end
        if now() - cachedAt >= REVALIDATE_MS then return false end
        if not alive(cachedController) or not alive(cachedPawn) then return false end
        local ok, current = pcall(function() return cachedController.Pawn end)
        if not ok or not alive(current) then return false end
        local currentAddress, cachedAddress = addressOf(current), addressOf(cachedPawn)
        return currentAddress ~= nil and currentAddress == cachedAddress
    end

    return {
        -- The local player pawn, or nil when there is not one to hand out.
        Player = function()
            if stillOurs() then
                reuses = reuses + 1
                return cachedPawn
            end
            return fullResolve()
        end,
        -- The controller behind the cached pawn. Resolves first when nothing is cached.
        Controller = function()
            if not stillOurs() then
                if fullResolve() == nil then return nil end
            else
                reuses = reuses + 1
            end
            return cachedController
        end,
        -- Called when the session changes, so the next caller pays for a fresh look
        -- rather than trusting handles from a player that is gone.
        Invalidate = forget,
        -- Exposed so the saving can be demonstrated rather than asserted.
        Stats = function() return { scans = scans, reuses = reuses } end,
    }
end

return M
