local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("fall_damage_readback")
local M = {}
local function valid(object) return object ~= nil and object:IsValid() end
local function text(value)
    if type(value) ~= "string" then value = value:ToString() end
    assert(type(value) == "string" and #value <= 512, "Invalid diagnostic text")
    return value:gsub("[\r\n;]", " ")
end
local function each(container, callback)
    local count = 0
    local function visit(element)
        count = count + 1; assert(count <= 16, "Diagnostic array exceeds 16 entries")
        local ok, value = pcall(function() return element:get() end)
        callback(ok and value or element, count)
    end
    local ok, method = pcall(function() return container.ForEach end)
    if ok and type(method) == "function" then container:ForEach(function(_, element) visit(element); return false end)
    else assert(#container <= 16, "Diagnostic array exceeds 16 entries"); for index = 1, #container do visit(container[index]) end end
    return count
end
function M.Read(helpers)
    local player = helpers.GetPlayer()
    assert(valid(player), "Load a player first")
    local world, controller, component = player:GetWorld(), player.Controller, player.FallDamageComponent
    assert(valid(world) and valid(controller) and valid(component) and valid(controller.Pawn), "Player fall-damage component unavailable")
    local address, worldAddress, controllerAddress = player:GetAddress(), world:GetAddress(), controller:GetAddress()
    assert(controller.Pawn:GetAddress() == address and component:GetOwner():GetAddress() == address, "Fall-damage owner mismatch")
    assert(component:IsA("/Script/Dawnwalker.FallDamageComponent"), "Unexpected fall-damage component class")
    local config = component.FallDamageConfig
    assert(valid(config) and config:IsA("/Script/Dawnwalker.FallDamageConfig"), "Fall-damage config unavailable")
    local effectClass = config.DamageEffect
    assert(valid(effectClass), "Fall-damage effect class unavailable")
    local effect = effectClass:GetCDO()
    assert(valid(effect) and effect:IsA("/Script/GameplayAbilities.GameplayEffect"), "Fall-damage effect CDO unavailable")
    local bindings = {component, config, effectClass, effect}
    local addresses = {}; for index, object in ipairs(bindings) do addresses[index] = object:GetAddress() end
    local rows = {"read_only=true", "component=" .. text(component:GetFullName()), "config=" .. text(config:GetFullName()),
        "effect=" .. text(effectClass:GetFullName())}
    local function read(label, callback)
        local ok, result = pcall(callback)
        rows[#rows + 1] = label .. "=" .. (ok and tostring(result) or "UNAVAILABLE")
    end
    read("component_active", function() return component:IsActive() end)
    read("component_tick_enabled", function() return component:IsComponentTickEnabled() end)
    read("duration_policy", function() return effect.DurationPolicy end)
    read("executions", function()
        local values = {}
        each(effect.Executions, function(entry) values[#values + 1] = text(entry.CalculationClass:GetFullName()) end)
        return table.concat(values, " | ")
    end)
    read("modifiers", function()
        local values = {}
        each(effect.Modifiers, function(entry)
            values[#values + 1] = text(entry.Attribute.AttributeOwner:GetFullName()) .. ":" .. text(entry.Attribute.AttributeName)
        end)
        return table.concat(values, " | ")
    end)
    for _, key in ipairs({"RequireTags", "IgnoreTags"}) do
        read("application_" .. key, function()
            local values = {}
            each(effect.ApplicationTagRequirements[key].GameplayTags, function(tag) values[#values + 1] = text(tag.TagName) end)
            return table.concat(values, " | ")
        end)
    end
    for index, object in ipairs(bindings) do assert(valid(object) and object:GetAddress() == addresses[index], "Fall-damage identity expired") end
    assert(player:GetAddress() == address and player:GetWorld():GetAddress() == worldAddress
        and player.Controller:GetAddress() == controllerAddress and controller.Pawn:GetAddress() == address
        and player.FallDamageComponent:GetAddress() == addresses[1] and component.FallDamageConfig:GetAddress() == addresses[2]
        and config.DamageEffect:GetAddress() == addresses[3] and effectClass:GetCDO():GetAddress() == addresses[4], "Fall-damage binding changed")
    return table.concat(rows, "\n")
end
function M.Init(menu, helpers)
    menu.Register({id="DWFallReadback",title="Fall damage diagnostics",tab="Player",items={
        {type="button",id="refresh",label="Read fall damage capabilities",onClick=function()
            ExecuteInGameThread(function() menu.SetLabel("DWFallReadback","status",M.Read(helpers)) end)
        end},
        {type="label",id="status",label="Read-only fall-damage discovery has not run."},
    }})
end
return M
