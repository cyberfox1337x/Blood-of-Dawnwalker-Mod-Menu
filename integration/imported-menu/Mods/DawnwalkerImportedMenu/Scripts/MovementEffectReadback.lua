local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("movement_effect_readback")
local M = {}
local PREFIX = "/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/"
local NAMES = { "GE_WolfBoost_JumpIncrease", "GE_WolfBoost_SpedBoost_Lvl3", "GE_WolfBoost_SpedBoost_Lvl4" }
local function address(object)
    assert(object and object:IsValid(), "Required movement object unavailable")
    return tostring(object:GetAddress())
end
local function scalar(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Invalid movement scalar")
    return tostring(value)
end
local function length(array)
    local ok, count = pcall(function() return array:GetArrayNum() end)
    if not ok then count = #array end
    assert(type(count) == "number" and count >= 0 and count % 1 == 0 and count <= 16, "Movement array exceeds 16 entries")
    return count
end
local function element(array, index)
    local result = array[index]
    local ok, raw = pcall(function() return result:get() end)
    return ok and raw or result
end
local function scalable(value)
    local curve = value.Curve
    local curveTable = curve.CurveTable
    return "value=" .. scalar(value.Value) .. ";curve="
        .. (curveTable and curveTable:IsValid() and curveTable:GetFullName() or "none")
        .. ";row=" .. curve.RowName:ToString() .. ";registry=" .. value.RegistryType.Name:ToString()
end
local function tags(container)
    local result = {}
    for index = 1, length(container.GameplayTags) do
        result[#result + 1] = element(container.GameplayTags, index).TagName:ToString()
    end
    return table.concat(result, ",")
end
local function effect(name, prefix)
    local path = (prefix or PREFIX) .. name
    local class = StaticFindObject(path .. "." .. name .. "_C")
    if not class or not class:IsValid() then return "effect=" .. name .. ";loaded=0" end
    local cdo = StaticFindObject(path .. ".Default__" .. name .. "_C")
    assert(address(class:GetCDO()) == address(cdo) and address(cdo:GetClass()) == address(class)
        and cdo:IsA("/Script/GameplayAbilities.GameplayEffect"), "Movement effect identity differs")
    local lines = { "effect=" .. name .. ";loaded=1;address=" .. address(cdo)
        .. ";duration=" .. scalar(cdo.DurationPolicy) .. ";stacking=" .. scalar(cdo.StackingType)
        .. ";stacklimit=" .. scalar(cdo.StackLimitCount) .. ";period:" .. scalable(cdo.Period)
        .. ";executions=" .. length(cdo.Executions) .. ";grantedabilities=" .. length(cdo.GrantedAbilities)
        .. ";components=" .. length(cdo.GEComponents) }
    for index = 1, length(cdo.Modifiers) do
        local modifier = element(cdo.Modifiers, index)
        local magnitude = modifier.ModifierMagnitude
        local textOk, attributeName = pcall(function() return modifier.Attribute.AttributeName:ToString() end)
        lines[#lines + 1] = "modifier=" .. index .. ";attribute=" .. (textOk and attributeName or tostring(modifier.Attribute.AttributeName))
            .. ";owner=" .. modifier.Attribute.AttributeOwner:GetFullName() .. ";operation=" .. scalar(modifier.ModifierOp)
            .. ";calculation=" .. scalar(magnitude.MagnitudeCalculationType)
            .. ";magnitude:" .. scalable(magnitude.ScalableFloatMagnitude)
        if magnitude.MagnitudeCalculationType == 2 then
            local customOk, customDetails = pcall(function()
                local custom = magnitude.CustomMagnitude
                local calculationClass = custom.CalculationClassMagnitude
                local calculationCDO = calculationClass:GetCDO()
                assert(address(calculationCDO:GetClass()) == address(calculationClass)
                    and calculationCDO:IsA("/Script/GameplayAbilities.GameplayModMagnitudeCalculation"), "Custom calculation CDO identity differs")
                local details = { "custom_modifier=" .. index .. ";class=" .. calculationClass:GetFullName()
                    .. ";class_address=" .. address(calculationClass) .. ";cdo=" .. calculationCDO:GetFullName()
                    .. ";cdo_address=" .. address(calculationCDO)
                    .. ";non_authority_dependency=" .. tostring(calculationCDO.bAllowNonNetAuthorityDependencyRegistration),
                    "coefficient:" .. scalable(custom.Coefficient),
                    "pre_additive:" .. scalable(custom.PreMultiplyAdditiveValue),
                    "post_additive:" .. scalable(custom.PostMultiplyAdditiveValue) }
                local curve = custom.FinalLookupCurve
                details[#details + 1] = "final_curve=" .. (curve.CurveTable and curve.CurveTable:IsValid() and curve.CurveTable:GetFullName() or "none") .. ";row=" .. curve.RowName:ToString()
                for captureIndex = 1, length(calculationCDO.RelevantAttributesToCapture) do
                    local capture = element(calculationCDO.RelevantAttributesToCapture, captureIndex)
                    details[#details + 1] = "capture=" .. captureIndex .. ";attribute=" .. tostring(capture.AttributeToCapture.AttributeName)
                        .. ";owner=" .. capture.AttributeToCapture.AttributeOwner:GetFullName()
                        .. ";source=" .. scalar(capture.AttributeSource) .. ";snapshot=" .. tostring(capture.bSnapshot)
                end
                return table.concat(details, "\n")
            end)
            lines[#lines + 1] = customOk and customDetails or ("custom_modifier=" .. index .. ";inspection_failed=" .. tostring(customDetails))
        end
    end
    for index = 1, length(cdo.GEComponents) do
        local component = element(cdo.GEComponents, index)
        lines[#lines + 1] = "component=" .. component:GetFullName()
        local detailsOk, details = pcall(function()
            local class = component:GetClass():GetFullName()
            if class == "Class /Script/GameplayAbilities.AssetTagsGameplayEffectComponent" then
                return "asset_tags=" .. tags(component.InheritableAssetTags.CombinedTags)
            elseif class == "Class /Script/GameplayAbilities.TargetTagsGameplayEffectComponent" then
                return "granted_tags=" .. tags(component.InheritableGrantedTagsContainer.CombinedTags)
            elseif class == "Class /Script/GameplayAbilities.TargetTagRequirementsGameplayEffectComponent" then
                local rows = {}
                for _, key in ipairs({ "ApplicationTagRequirements", "OngoingTagRequirements", "RemovalTagRequirements" }) do
                    local requirements = component[key]
                    rows[#rows + 1] = key .. ";require=" .. tags(requirements.RequireTags) .. ";ignore=" .. tags(requirements.IgnoreTags)
                end
                return table.concat(rows, "\n")
            end
            return "component_details=unsupported"
        end)
        lines[#lines + 1] = detailsOk and details or "component_details=UNAVAILABLE"
    end
    return table.concat(lines, "\n")
end
function M.Read(helpers)
    local ok, result = pcall(function()
        local player = helpers.GetPlayer()
        local playerId, worldId = address(player), address(player:GetWorld())
        local movement = player:GetRebelCharacterMovement()
        assert(address(movement:GetOwner()) == playerId and address(player.CharacterMovement) == address(movement), "Movement ownership differs")
        local profile = movement:GetCurrentMovementProfile()
        assert(profile:IsA("/Script/RebelLocomotion.RebelCharacterMovementProfile"), "Movement profile type differs")
        local config = profile.MovementConfig
        local lines = { "probe=movement:effect-profile;mutation_authorized=0;profile=" .. profile:GetFullName()
            .. ";profile_address=" .. address(profile) .. ";priority=" .. scalar(profile.Priority)
            .. ";root_speed_scale=" .. scalar(config.RootSpeedScale) .. ";max_speed=" .. scalar(config.MaxSpeed)
            .. ";gravity_scale=" .. scalar(config.GravityScale) .. ";use_gravity=" .. tostring(config.bUseGravityScale)
            .. ";effective_max_speed=" .. scalar(movement:GetMaxSpeed()) }
        for _, name in ipairs(NAMES) do
            local read, evidence = pcall(effect, name)
            lines[#lines + 1] = read and evidence or ("effect=" .. name .. ";inspection_failed=" .. tostring(evidence))
        end
        local fallOk, fallDetails = pcall(effect, "GE_FallDamage", "/Game/_Dawnwalker/Player/FallDamage/")
        lines[#lines + 1] = fallOk and fallDetails or ("effect=GE_FallDamage;inspection_failed=" .. tostring(fallDetails))
        assert(address(helpers.GetPlayer()) == playerId and address(player:GetWorld()) == worldId
            and address(player:GetRebelCharacterMovement()) == address(movement), "Movement context changed")
        return table.concat(lines, "\n")
    end)
    return ok and result or ("probe=movement:effect-profile;mutation_authorized=0;failed=" .. tostring(result))
end
function M.Init(menu, helpers)
    local id = "DWMovementEffectReadback"
    menu.Register({ id = id, title = "Movement effect diagnostics", tab = "Player", items = {
        { type = "button", id = "refresh", label = "Read movement effect metadata", onClick = function()
            ExecuteInGameThread(function() menu.SetLabel(id, "status", M.Read(helpers)) end)
        end },
        { type = "label", id = "status", label = "Movement profile and exact loaded effects have not been inspected." },
    } })
end
return M
