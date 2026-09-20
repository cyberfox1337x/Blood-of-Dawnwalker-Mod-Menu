local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("super_jump_pilot")
local M = {}
local identities = { "player", "world", "controller", "asc", "attributes", "movement", "library", "effectClass" }
local function numeric(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Invalid jump readback")
    return value
end
local function close(actual, expected)
    return math.abs(actual - expected) <= math.max(.01, math.abs(expected) * .001)
end

-- The caller must supply a borrower which first passes the existing exact
-- descriptor probe and returns the validated UObject/descriptor wrappers.
-- No entrypoint or menu registration exposes this candidate automatically.
function M.New(deps)
    assert(type(deps.borrow) == "function", "Validated jump descriptor borrower required")
    local owned, failed = nil, false
    local function borrow()
        local borrowed = deps.borrow()
        assert(borrowed.validated == true, "Jump descriptor has not passed read-only validation")
        local context = { descriptor = borrowed.descriptor }
        for _, name in ipairs(identities) do
            local object = borrowed[name]
            assert(object and object:IsValid(), "Invalid jump identity: " .. name)
            context[name] = object
            context[name .. "Address"] = object:GetAddress()
        end
        context.descriptorAddress = context.descriptor:GetStructAddress()
        assert(numeric(context.descriptorAddress) > 0, "Invalid jump descriptor address")
        assert(context.asc:GetGameplayEffectCount(context.effectClass, nil, false) == 0,
            "Disable Wolf Boost before changing jump strength")
        return context
    end
    local function verifyIdentity(record)
        local current = borrow()
        for _, name in ipairs(identities) do
            assert(record[name]:IsValid() and record[name]:GetAddress() == record[name .. "Address"]
                and current[name .. "Address"] == record[name .. "Address"], "Jump player or descriptor owner changed")
        end
        assert(current.descriptorAddress == record.descriptorAddress, "Jump descriptor identity changed")
    end
    local function read(record)
        local attribute = record.attributes.JumpVelocity
        local base, current = numeric(attribute.BaseValue), numeric(attribute.CurrentValue)
        local output = {}
        local effective = record.asc:GetGameplayAttributeValue(record.descriptor, output)
        assert(output.bFound == true, "Jump attribute was not confirmed by bFound out parameter")
        assert(close(numeric(effective), current), "Jump ASC readback mismatch")
        assert(close(base, current), "Another gameplay modifier owns jump strength")
        local velocity, height = numeric(record.movement.JumpZVelocity), numeric(record.movement:GetMaxJumpHeight())
        local gravity = numeric(record.movement:GetGravityZ())
        assert(velocity > 0 and height > 0 and gravity < 0, "Invalid jump movement baseline")
        assert(close(height, velocity * velocity / (-2 * gravity)), "Jump height and velocity disagree")
        return base, height, velocity
    end
    local function verifyValue(record, expected, height, velocity)
        verifyIdentity(record)
        local actual, actualHeight, actualVelocity = read(record)
        assert(close(actual, expected) and close(actualHeight, height) and close(actualVelocity, velocity),
            "Jump value, velocity or height readback failed")
    end
    local function restore()
        if not owned then return end
        local record = owned
        verifyIdentity(record)
        local currentBase = numeric(record.attributes.JumpVelocity.BaseValue)
        -- UE4SS can reject a reference parameter before ProcessEvent. If every
        -- captured value is already unchanged, there is nothing to restore and
        -- retrying that rejected setter would falsely retain recovery ownership.
        if close(currentBase, record.baseline) then
            local unchanged = pcall(verifyValue, record, record.baseline, record.height, record.velocity)
            if unchanged then owned = nil; return end
        end
        assert(close(currentBase, record.target) or close(currentBase, record.baseline),
            "Jump value was changed by another owner; refusing to overwrite it")
        record.library:SetAttributeValue(record.asc, record.descriptor, record.baseline)
        verifyValue(record, record.baseline, record.height, record.velocity)
        owned = nil
    end
    local function enable()
        assert(not failed, "Prior jump failure requires restarting and reloading")
        if owned then verifyValue(owned, owned.target, owned.height * 2.25, owned.velocity * 1.5); return end
        local record = borrow()
        -- The live movement baseline can include a game-derived scale. Capture
        -- it independently instead of assuming it equals the GAS attribute.
        record.baseline, record.height, record.velocity = read(record)
        assert(record.baseline > 0 and record.baseline <= 2000, "Jump baseline outside bounded pilot range")
        record.target = record.baseline * 1.5
        verifyIdentity(record)
        owned = record
        record.library:SetAttributeValue(record.asc, record.descriptor, record.target)
        verifyValue(record, record.target, record.height * 2.25, record.velocity * 1.5)
    end
    return {
        set = function(value)
            assert(type(value) == "boolean", "Super Jump requires a boolean")
            local ok, failure = pcall(value and enable or restore)
            if not ok then
                failed = true
                local restored, restoration = pcall(restore)
                error(tostring(failure) .. (restored and "; baseline restored" or "; jump recovery pending: " .. tostring(restoration)))
            end
        end,
        owned = function() return owned ~= nil end,
        verify = function() if owned then verifyValue(owned, owned.target, owned.height * 2.25, owned.velocity * 1.5) end end,
        inspect = function()
            assert(not failed, "Prior jump failure requires restarting and reloading")
            if owned then verifyValue(owned, owned.target, owned.height * 2.25, owned.velocity * 1.5); return end
            local record = borrow()
            local baseline = read(record)
            assert(baseline > 0 and baseline <= 2000, "Jump baseline outside bounded pilot range")
            verifyIdentity(record)
        end,
        reset = function() assert(owned == nil, "Cannot discard pending jump restoration") end,
    }
end
function M.Init(menu, helpers, borrower)
    assert(type(borrower) == "function", "Validated jump borrower required")
    local id, pilot = "DWSuperJump", M.New({ borrow = function() return borrower(helpers) end })
    local unsupported = "Super Jump unavailable: this runtime cannot preserve the attribute descriptor in the setter. A compatible native adapter is required."
    local field
    field = { type = "checkbox", id = "enabled", label = "Super Jump (1.5x velocity)", default = false, enabled = false,
        onChange = function(value)
            assert(value == false, unsupported)
            ExecuteInGameThread(function()
                local ok, failure = pcall(pilot.set, value)
                field.enabled = pilot.owned()
                menu.Set(id, "enabled", pilot.owned())
                menu.SetLabel(id, "status", ok and (pilot.owned()
                    and "ON: jump velocity and derived height verified."
                    or "OFF: original jump strength restored and verified.")
                    or ("Super Jump failed: " .. tostring(failure)))
                assert(ok, failure)
            end)
        end }
    menu.Register({ id = id, title = "Super Jump", tab = "Player", items = {
        field,
        { type = "button", id = "refresh", label = "Verify Super Jump capabilities", onClick = function()
            ExecuteInGameThread(function()
                local ok, failure = pcall(pilot.inspect)
                field.enabled = pilot.owned()
                menu.SetLabel(id, "status", ok and unsupported or (unsupported .. " Readback: " .. tostring(failure)))
                assert(ok, failure)
            end)
        end },
        { type = "label", id = "status", label = unsupported },
    } })
    M.ResetSession = function() pilot.reset(); field.enabled = false end
end
return M
