local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("jump_descriptor_readback")
local Probe = require("DawnwalkerSuperJumpDescriptorReadOnlyProbe")
local M = {}
local ABILITY_LIBRARY = "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"
local COMBAT_LIBRARY = "/Script/DogwoodCombat.Default__CombatBlueprintFunctionLibrary"
local COMBAT_LIBRARY_CLASS = "/Script/DogwoodCombat.CombatBlueprintFunctionLibrary"

local function address(object)
    assert(object and object:IsValid(), "Borrowed object is unavailable.")
    return tostring(object:GetAddress())
end

local function sole_modifier(container)
    local count, modifier = 0, nil
    local function take(element)
        count = count + 1
        assert(count == 1, "The borrowed effect no longer has exactly one modifier.")
        local ok, unwrapped = pcall(function() return element:get() end)
        modifier = ok and unwrapped or element
    end
    if type(container.ForEach) == "function" then
        container:ForEach(function(_, element) take(element); return false end)
    else
        assert(#container == 1, "The borrowed modifier array changed.")
        take(container[1])
    end
    assert(count == 1 and modifier, "The borrowed modifier is unavailable.")
    return modifier
end

-- Returns only in-process references after successful descriptor validation.
-- Callers must independently authorize any mutation and reborrow each time.
function M.Borrow(helpers)
    assert(type(helpers) == "table" and type(helpers.GetPlayer) == "function", "Player resolver is unavailable.")
    local evidence = Probe.run({ static_find_object = StaticFindObject,
        get_player = helpers.GetPlayer,
        get_player_controller = function() local player = helpers.GetPlayer(); return player and player.Controller end })
    assert(type(evidence) == "table" and evidence.ok == true,
        "Descriptor probe failed: " .. tostring(evidence and evidence.stage) .. ": " .. tostring(evidence and evidence.message))
    local player = helpers.GetPlayer()
    local controller, world = player.Controller, player:GetWorld()
    local asc, attributes = player.AbilitySystemComponent, player.MovementAttributeSet
    local identity = evidence.identity
    assert(address(player) == identity.player_address and address(controller) == identity.controller_address
        and address(world) == identity.world_address and address(asc) == identity.asc_address
        and address(attributes) == identity.attribute_set_address, "Player identities changed after the descriptor probe.")
    local effectClass = StaticFindObject(evidence.source.class_path)
    local effectCDO = effectClass:GetCDO()
    assert(address(effectClass) == evidence.source.class_address and address(effectCDO) == evidence.source.cdo_address,
        "Effect source changed after the descriptor probe.")
    local descriptor = sole_modifier(effectCDO.Modifiers).Attribute
    assert(tostring(descriptor:GetStructAddress()) == evidence.descriptor.struct_address
        and address(descriptor.AttributeOwner) == identity.attribute_set_class_address,
        "The borrowed descriptor changed after validation.")
    local data = attributes.JumpVelocity
    assert(data.BaseValue == evidence.readback.base_value and data.CurrentValue == evidence.readback.current_value,
        "Jump values changed after descriptor validation.")
    local movement = player:GetRebelCharacterMovement()
    assert(address(movement) == address(player.CharacterMovement) and address(movement:GetOwner()) == identity.player_address,
        "The movement component is not owned by the validated player.")
    local library, libraryClass = StaticFindObject(COMBAT_LIBRARY), StaticFindObject(COMBAT_LIBRARY_CLASS)
    assert(library and library:IsValid() and library:IsA(COMBAT_LIBRARY_CLASS)
        and address(libraryClass:GetCDO()) == address(library), "The exact combat library CDO is unavailable.")
    assert(address(helpers.GetPlayer()) == identity.player_address and address(player.Controller) == identity.controller_address
        and address(player:GetWorld()) == identity.world_address and address(player.AbilitySystemComponent) == identity.asc_address
        and address(player.MovementAttributeSet) == identity.attribute_set_address,
        "Player identity changed while borrowing the descriptor.")
    return { validated = true, player = player, controller = controller, world = world, asc = asc,
        attributes = attributes, movement = movement, descriptor = descriptor, library = library,
        abilityLibrary = StaticFindObject(ABILITY_LIBRARY), effectClass = effectClass,
        base = evidence.readback.base_value, current = evidence.readback.current_value, evidence = evidence }
end

local function failure(message)
    return "schema_version=1;probe_id=player:super-jump-descriptor;evidence_class=development-read-only;"
        .. "passed=0;mutation_authorized=0;release_visible=0;stage=adapter\n" .. tostring(message)
end

-- Invoked only on the game thread. The borrowed descriptor is inspected, never
-- stored or passed to a mutation API; the existing probe checks identity twice.
function M.Read(helpers)
    local ok, result = pcall(function()
        assert(type(helpers) == "table" and type(helpers.GetPlayer) == "function", "Player resolver is unavailable.")
        return Probe.run({
            static_find_object = StaticFindObject,
            get_player = helpers.GetPlayer,
            get_player_controller = function()
                local player = helpers.GetPlayer()
                return player and player.Controller
            end,
        })
    end)
    if not ok then return failure(result) end
    if type(result) ~= "table" then return failure("The descriptor probe returned no structured result.") end
    local formatted, text = pcall(Probe.format_result, result)
    if not formatted then return failure(text) end
    -- format_result deliberately omits diagnostic prose; retain it for failures.
    return text .. "\n" .. tostring(result.message or "No probe detail returned.")
end

function M.Init(menu, helpers)
    local id = "DWJumpReadback"
    menu.Register({ id = id, title = "Jump descriptor diagnostics", tab = "Player", items = {
        { type = "button", id = "refresh", label = "Read jump descriptor", onClick = function()
            local ok, cause = pcall(function()
                ExecuteInGameThread(function() menu.SetLabel(id, "status", M.Read(helpers)) end)
            end)
            if not ok then menu.SetLabel(id, "status", failure(cause)) end
        end },
        { type = "label", id = "status", label = "Read-only jump descriptor discovery has not run." },
    } })
end
return M
