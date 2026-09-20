local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_preview_session")

-- Inert controller. Native construction/readback/capture/cleanup remain adapters;
-- this module never creates a ReadyEyeSession or changes live player materials.
local Session = {}
local Controller = {}
Controller.__index = Controller
local ADAPTERS = { "is_game_thread", "monotonic_ms", "inspect_identity", "validate_settings", "validate_view",
    "create_preview", "verify_private_preview", "update_preview", "validate_readback", "capture_preview",
    "validate_capture_evidence", "release_preview" }

local function check(condition, message) if condition ~= true then error(message, 0) end end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function text(value, maximum) return type(value) == "string" and #value > 0 and #value <= maximum and not value:find("[%z\1-\31\127]") end
local function integer(value, minimum, maximum) return finite(value) and value % 1 == 0 and value >= minimum and value <= maximum end
local function reason(value) return tostring(value):sub(1, 512) end
local function rejected(message) return { status = "rejected", reason = message, production_ready = false } end

local function copy_plain(value, depth, budget)
    budget.count = budget.count + 1
    check(budget.count <= 2048 and depth <= 10, "Preview payload is oversized")
    if type(value) == "table" then
        check(getmetatable(value) == nil, "Preview payload has a metatable")
        local result = {}
        for key, child in pairs(value) do
            check((type(key) == "string" and #key <= 128) or integer(key, 1, 128), "Invalid preview payload key")
            result[key] = copy_plain(child, depth + 1, budget)
        end
        return result
    end
    check(type(value) == "boolean" or (type(value) == "string" and #value <= 2048) or finite(value), "Preview payload contains a non-plain value")
    return value
end

local function equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not equal(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local function request_copy(self, request)
    local ok, result = pcall(function()
        check(type(request) == "table" and text(request.owner_id, 128) and text(request.lease_id, 128)
            and text(request.identity_key, 2048), "Preview request identity is invalid")
        check(integer(request.view_revision, 0, 2147483647) and integer(request.eye_revision, 0, 2147483647), "Preview revision is invalid")
        local budget = { count = 0 }
        local view, settings = copy_plain(request.view, 0, budget), copy_plain(request.settings, 0, budget)
        check(type(view) == "table" and (view.framing == "head-and-shoulders" or view.framing == "eyes-close-up")
            and finite(view.yawDegrees) and view.yawDegrees >= -69 and view.yawDegrees <= 69
            and finite(view.zoom) and view.zoom > 0 and view.zoom <= 10, "Preview view is outside controller bounds")
        check(type(settings) == "table" and self.adapters.validate_view(view) == true and self.adapters.validate_settings(settings) == true,
            "Preview view or eye settings are unsupported")
        return { owner_id = request.owner_id, lease_id = request.lease_id, identity_key = request.identity_key,
            view_revision = request.view_revision, eye_revision = request.eye_revision, view = view, settings = settings }
    end)
    if not ok then return nil, reason(result) end
    return result
end

local function now(self)
    local current = self.adapters.monotonic_ms()
    check(finite(current) and current >= 0 and (self.last_time == nil or current >= self.last_time), "Preview monotonic clock is invalid or moved backwards")
    self.last_time = current
    return current
end

local function close_owned(self, cause)
    local active = self.active
    self.active = nil
    if not active then
        if self.cleanup_blocked then return { status = "cleanup-failed", reason = "Earlier owned cleanup still requires recovery", production_ready = false } end
        return { status = "closed", reason = cause, already_closed = true, production_ready = false }
    end
    active.pending = nil
    -- Detach the handle before cleanup so a failed callback is never blindly retried.
    local ok, cleanup = pcall(self.adapters.release_preview, active.handle, cause)
    if not ok or type(cleanup) ~= "table" or cleanup.owned_cleanup_acknowledged ~= true then
        self.cleanup_blocked = true
        self.failed_cleanup_handle = active.handle
        return { status = "cleanup-failed", reason = cause, cleanup = ok and cleanup or nil,
            cleanup_error = ok and "Owned native cleanup was not acknowledged" or reason(cleanup), production_ready = false }
    end
    return { status = "closed", reason = cause, cleanup = cleanup, production_ready = false }
end

local function execute(self, action)
    if self.busy then return rejected("Preview controller operation is already running") end
    local thread_ok, on_game_thread = pcall(self.adapters.is_game_thread)
    if not thread_ok or on_game_thread ~= true then return rejected("Preview controller requires the game thread") end
    self.busy = true
    local ok, result = pcall(action)
    if not ok then
        local failure = reason(result)
        result = close_owned(self, "native-operation-failed")
        result.status = result.status == "cleanup-failed" and result.status or "invalidated"
        result.reason = failure
    end
    self.busy = false
    return result
end

local function address_matches(active, address)
    return type(address) == "table" and address.owner_id == active.owner_id and address.lease_id == active.lease_id
        and address.identity_key == active.identity_key
end

local function check_lifetime(self, current)
    local active = self.active
    if not active then return { status = "idle", production_ready = false } end
    local cause
    if current >= active.lease_expires then cause = "lease-expired"
    elseif current - active.opened_at >= self.limits.max_lifetime_ms then cause = "lifetime-budget-exhausted"
    elseif active.sequence >= self.limits.max_frames then cause = "frame-budget-exhausted"
    elseif self.adapters.inspect_identity() ~= active.identity_key then cause = "source-identity-changed" end
    if cause then
        local result = close_owned(self, cause)
        result.status = result.status == "cleanup-failed" and result.status or "invalidated"
        return result
    end
    check(self.adapters.verify_private_preview(active.handle, active.identity_key) == true,
        "Preview ownership, private eye bindings or source generation changed")
    return nil
end

function Session.new(adapters, limits)
    check(type(adapters) == "table", "Preview adapters are required")
    for _, name in ipairs(ADAPTERS) do check(type(adapters[name]) == "function", "Missing preview adapter: " .. name) end
    check(adapters.can_capture == nil or type(adapters.can_capture) == "function", "Invalid native frame capacity adapter")
    limits = limits or {}
    local bounded = { lease_ms = limits.lease_ms or 3000, max_lifetime_ms = limits.max_lifetime_ms or 30000,
        frame_interval_ms = limits.frame_interval_ms or 100, max_frames = limits.max_frames or 120 }
    check(integer(bounded.lease_ms, 250, 10000) and integer(bounded.max_lifetime_ms, bounded.lease_ms, 120000)
        and integer(bounded.frame_interval_ms, 16, 1000) and integer(bounded.max_frames, 1, 1200), "Preview controller limits are invalid")
    return setmetatable({ adapters = adapters, limits = bounded, used_leases = {}, opened_count = 0 }, Controller)
end

function Controller:open(request)
    return execute(self, function()
        if self.disposed or self.cleanup_blocked then return rejected("Preview controller is disposed or awaiting cleanup recovery") end
        if self.active then return rejected("A preview already has an owner") end
        local copied, failure = request_copy(self, request)
        if not copied then return rejected(failure) end
        if self.used_leases[copied.lease_id] or self.opened_count >= 64 then return rejected("Preview lease was used or open budget is exhausted") end
        local current = now(self)
        if self.adapters.inspect_identity() ~= copied.identity_key then return rejected("Preview source identity is no longer current") end
        self.used_leases[copied.lease_id], self.opened_count = true, self.opened_count + 1
        -- The factory owns partial-construction cleanup until it returns a handle.
        local created_ok, handle = pcall(self.adapters.create_preview, copied.identity_key)
        if not created_ok or handle == nil then
            -- A factory exception cannot prove whether partial resources escaped.
            self.cleanup_blocked = true
            error(created_ok and "Native preview factory returned no handle or cleanup acknowledgement"
                or "Native preview factory failed; partial cleanup is unconfirmed: " .. reason(handle), 0)
        end
        self.active = { owner_id = copied.owner_id, lease_id = copied.lease_id, identity_key = copied.identity_key,
            handle = handle, opened_at = current, lease_expires = current + self.limits.lease_ms, sequence = 0,
            latest = copied, pending = copied, last_capture_at = nil }
        local invalidated = check_lifetime(self, now(self))
        if invalidated then return invalidated end
        return { status = "opened", owner_id = copied.owner_id, lease_id = copied.lease_id, production_ready = false }
    end)
end

function Controller:enqueue(request)
    return execute(self, function()
        if not self.active or not address_matches(self.active, request) then return rejected("Preview request does not own the current lease") end
        local invalidated = check_lifetime(self, now(self))
        if invalidated then return invalidated end
        local copied, failure = request_copy(self, request)
        if not copied then return rejected(failure) end
        local latest = self.active.latest
        if copied.view_revision < latest.view_revision or copied.eye_revision < latest.eye_revision then return rejected("Preview request revisions are stale") end
        if (copied.view_revision == latest.view_revision and not equal(copied.view, latest.view))
            or (copied.eye_revision == latest.eye_revision and not equal(copied.settings, latest.settings)) then
            return rejected("A preview revision cannot be reused for different settings")
        end
        if copied.view_revision == latest.view_revision and copied.eye_revision == latest.eye_revision then
            if not self.active.suspended then return { status = "unchanged", production_ready = false } end
        end
        self.active.latest, self.active.pending = copied, copied
        self.active.suspended = false
        return { status = "queued", view_revision = copied.view_revision, eye_revision = copied.eye_revision, production_ready = false }
    end)
end

function Controller:cancel(address)
    return execute(self, function()
        if not self.active or not address_matches(self.active, address) then return rejected("Preview cancellation does not own the current lease") end
        local invalidated = check_lifetime(self, now(self))
        if invalidated then return invalidated end
        local active = self.active
        local already_cancelled = active.suspended == true
        active.pending, active.suspended = nil, true
        -- Keep immutable revision watermarks for subsequent validation, but do not
        -- let idle capture replay their cancelled values through latest fallback.
        return { status = "cancelled", already_cancelled = already_cancelled,
            view_revision = active.latest.view_revision, eye_revision = active.latest.eye_revision, production_ready = false }
    end)
end

function Controller:renew(address)
    return execute(self, function()
        if not self.active or not address_matches(self.active, address) then return rejected("Preview lease is not owned by this caller") end
        local current = now(self)
        local invalidated = check_lifetime(self, current)
        if invalidated then return invalidated end
        self.active.lease_expires = math.min(current + self.limits.lease_ms, self.active.opened_at + self.limits.max_lifetime_ms)
        return { status = "renewed", production_ready = false }
    end)
end

function Controller:maintain()
    return execute(self, function()
        local invalidated = check_lifetime(self, now(self))
        if invalidated then return invalidated end
        return { status = "active", suspended = self.active.suspended == true, production_ready = false }
    end)
end

function Controller:step()
    return execute(self, function()
        local current = now(self)
        local invalidated = check_lifetime(self, current)
        if invalidated then return invalidated end
        local active = self.active
        if active.suspended then return { status = "waiting-for-preview-request", production_ready = false } end
        if active.last_capture_at and current - active.last_capture_at < self.limits.frame_interval_ms then
            return { status = "waiting", production_ready = false }
        end
        if self.adapters.can_capture and self.adapters.can_capture(active.handle) ~= true then
            return { status = "waiting-for-frame-consumer", production_ready = false }
        end
        local desired = active.pending or active.latest
        active.pending = nil
        -- Refresh pose and derived pivot as well as applying queued settings. The
        -- adapter writes only clone MIDs/camera, then performs native readbacks.
        local readback = self.adapters.update_preview(active.handle, copy_plain(desired, 0, { count = 0 }))
        check(self.adapters.validate_readback(readback, desired, active.handle) == true, "Preview native readback does not match the requested state")
        invalidated = check_lifetime(self, now(self))
        if invalidated then return invalidated end
        local sequence = active.sequence + 1
        local evidence = self.adapters.capture_preview(active.handle, readback, sequence)
        check(self.adapters.validate_capture_evidence(evidence, readback, sequence, active.handle) == true,
            "Native capture evidence does not match its readback, resources or sequence")
        invalidated = check_lifetime(self, now(self))
        if invalidated then return invalidated end
        active.sequence, active.last_capture_at = sequence, now(self)
        return { status = "captured-evidence", evidence = evidence, sequence = sequence, production_ready = false }
    end)
end

function Controller:close(address, cause)
    return execute(self, function()
        if not self.active then return close_owned(self, "owner-closed") end
        if not address_matches(self.active, address) then return rejected("Preview lease is not owned by this caller") end
        return close_owned(self, text(cause, 128) and cause or "owner-closed")
    end)
end

function Controller:shutdown()
    return execute(self, function()
        self.disposed = true
        return close_owned(self, "controller-shutdown")
    end)
end

return Session
