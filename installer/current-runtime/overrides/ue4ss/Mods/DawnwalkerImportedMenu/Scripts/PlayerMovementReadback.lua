local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("player_movement_readback")
local M = {}

local function valid(object)
    return object ~= nil and object:IsValid()
end
local function number(value)
    assert(type(value) == "number" and value == value and math.abs(value) < 10000000, "Invalid numeric readback")
    return tostring(value)
end

-- Read-only discovery of exact fields present in the saved native SDK. No
-- attribute, movement, collision, effect, or fall-damage state is modified.
function M.Read(helpers)
    local player = helpers.GetPlayer()
    assert(valid(player), "Load a player first")
    local controller, world = player.Controller, player:GetWorld()
    assert(valid(controller) and valid(world) and valid(controller.Pawn), "Controlled player required")
    local address = player:GetAddress()
    assert(controller.Pawn:GetAddress() == address, "Possession mismatch")
    local movement = player:GetRebelCharacterMovement()
    assert(valid(movement) and valid(player.CharacterMovement), "Movement component unavailable")
    assert(movement:GetAddress() == player.CharacterMovement:GetAddress(), "Movement resolver mismatch")
    assert(movement:GetOwner():GetAddress() == address, "Movement owner mismatch")
    local movementAddress, worldAddress, controllerAddress = movement:GetAddress(), world:GetAddress(), controller:GetAddress()
    local rows = { "read_only=true", "player=" .. tostring(address), "movement=" .. tostring(movementAddress) }
    local function read(label, callback)
        local ok, value = pcall(callback)
        rows[#rows + 1] = label .. "=" .. (ok and tostring(value) or "UNAVAILABLE")
    end
    read("movement_class", function() return movement:GetClass():GetFullName() end)
    read("movement_mode", function() return number(movement.MovementMode) end)
    read("custom_mode", function() return number(movement.CustomMovementMode) end)
    read("max_walk_speed", function() return number(movement.MaxWalkSpeed) end)
    read("max_fly_speed", function() return number(movement.MaxFlySpeed) end)
    read("jump_z_velocity", function() return number(movement.JumpZVelocity) end)
    read("effective_max_speed", function() return number(movement:GetMaxSpeed()) end)
    read("max_jump_height", function() return number(movement:GetMaxJumpHeight()) end)
    read("collision_enabled", function()
        local value = player:GetActorEnableCollision()
        assert(type(value) == "boolean", "Collision readback invalid")
        return tostring(value)
    end)
    local attributes = player.MovementAttributeSet
    if valid(attributes) then
        assert(attributes:GetOuter():GetAddress() == address, "Movement attribute owner mismatch")
        for _, name in ipairs({ "WalkSpeed", "RunSpeed", "SprintSpeed", "MaxSpeedModifier", "JumpVelocity" }) do
            read(name, function()
                local attribute = attributes[name]
                return number(attribute.BaseValue) .. "/" .. number(attribute.CurrentValue)
            end)
        end
    else
        rows[#rows + 1] = "movement_attributes=UNAVAILABLE"
    end
    read("fall_damage_class", function()
        local component = player.FallDamageComponent
        assert(valid(component) and component:GetOwner():GetAddress() == address, "Fall component unavailable")
        return component:GetClass():GetFullName()
    end)
    read("fall_damage_effect", function()
        local config = player.FallDamageComponent.FallDamageConfig
        assert(valid(config), "Fall config unavailable")
        return config.DamageEffect:GetFullName()
    end)
    assert(player:IsValid() and player:GetAddress() == address and player:GetWorld():GetAddress() == worldAddress
        and player.Controller:GetAddress() == controllerAddress and controller.Pawn:GetAddress() == address
        and player:GetRebelCharacterMovement():GetAddress() == movementAddress, "Player identity changed during readback")
    return table.concat(rows, "\n")
end

function M.Init(menu, helpers)
    local id = "DWMovementReadback"
    menu.Register({ id = id, title = "Movement diagnostics", tab = "Player", items = {
        { type = "button", id = "refresh", label = "Read movement capabilities", onClick = function()
            ExecuteInGameThread(function() menu.SetLabel(id, "status", M.Read(helpers)) end)
        end },
        { type = "label", id = "status", label = "Read-only movement discovery has not run." },
    } })
end
return M
