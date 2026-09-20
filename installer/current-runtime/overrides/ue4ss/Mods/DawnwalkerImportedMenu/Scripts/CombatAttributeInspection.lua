local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("combat_attribute_inspection")

-- Invoked only by the existing build-pinned DWCombatDiscovery dispatcher.
-- Descriptors are borrowed from the player's ASC; no attribute is constructed or written.
local M = {}
local PLAYER = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local SPECS = {
    { "SprintStaminaCostMultiplier", "CharacterAttributeSet", "PlayerAttributeSet" },
    { "DodgeStaminaCostMultiplier", "CharacterAttributeSet", "PlayerAttributeSet" },
    { "OmniblockStaminaCostMultiplier", "CharDevAttributeSet", "CharDevAttributeSet" },
    { "DirectionalBlockStaminaRestoreMultiplier", "CharDevAttributeSet", "CharDevAttributeSet" },
    { "DirectionalBlockStaminaRestoreModifier", "CharDevAttributeSet", "CharDevAttributeSet" },
    { "MaxFocusRange", "CharacterAttributeSet", "PlayerAttributeSet" },
    { "ActiveFocusRange", "CharacterAttributeSet", "PlayerAttributeSet" },
    { "MaxFocusSmellRange", "CharacterAttributeSet", "PlayerAttributeSet" },
    { "ActiveFocusSmellRange", "CharacterAttributeSet", "PlayerAttributeSet" },
}
local function finite(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Nonfinite native value")
    return value
end
local function text(value)
    if type(value) ~= "string" then value = value:ToString() end
    assert(type(value) == "string" and #value <= 1024 and not value:find("[%c]"), "Invalid native text")
    return value
end
local function identity(object, class, allowDefault)
    assert(object and object:IsValid() and object:IsA(class), "Unavailable or wrong class: " .. class)
    local name, address = text(object:GetFullName()), finite(object:GetAddress())
    assert(address > 0 and (allowDefault or not name:find("Default__", 1, true)), "Invalid native identity")
    return name .. "@" .. tostring(address)
end
local function context(helpers)
    assert(IsInGameThread() == true, "Attribute inspection requires the game thread")
    local player = helpers.GetPlayer()
    local playerKey = identity(player, PLAYER)
    local controller, world, asc = player.Controller, player:GetWorld(), player.AbilitySystemComponent
    local controllerKey = identity(controller, "/Script/Engine.PlayerController")
    local worldKey = identity(world, "/Script/Engine.World")
    local ascKey = identity(asc, "/Script/Dawnwalker.DawnwalkerAbilitySystemComponent")
    assert(identity(controller.Pawn, PLAYER) == playerKey, "Controlled pawn mismatch")
    assert(identity(controller:GetWorld(), "/Script/Engine.World") == worldKey, "Controller world mismatch")
    assert(identity(asc:GetOuter(), PLAYER) == playerKey, "ASC owner mismatch")
    local form = player:IsVampire()
    assert(type(form) == "boolean", "Player form unavailable")
    return { player = player, asc = asc, playerKey = playerKey,
        key = table.concat({ playerKey, controllerKey, worldKey, ascKey, tostring(form) }, "|") }
end
local function descriptors(asc)
    local output = {}
    asc:GetAllAttributes(output)
    -- UE4SS out-parameter wrappers may retain the named output or the array itself.
    local entries = output.OutAttributes or output
    local result, duplicates, count = {}, {}, 0
    local function accept(entry)
        count = count + 1
        assert(count <= 1024, "Native descriptor limit exceeded")
        if type(entry) ~= "table" or entry.AttributeName == nil then
            local ok, unwrapped = pcall(function() return entry:get() end)
            if ok then entry = unwrapped end -- Native struct values need no remote wrapper.
        end
        assert(entry and entry:IsValid() and entry:type() == "UScriptStruct", "Invalid native descriptor")
        local name = text(entry.AttributeName)
        if result[name] then duplicates[name] = true end
        result[name] = entry
    end
    if entries.ForEach then
        local failure
        entries:ForEach(function(_, entry)
            if failure then return end
            local ok, cause = pcall(accept, entry)
            if not ok then failure = cause end
        end)
        assert(not failure, tostring(failure))
    else
        for key in pairs(entries) do
            assert(type(key) == "number" and key >= 1 and key % 1 == 0 and key <= #entries, "Unsupported descriptor output shape")
        end
        for _, entry in ipairs(entries) do accept(entry) end
    end
    assert(count > 0, "No native descriptors returned")
    return result, duplicates, output
end
local function near(left, right)
    return math.abs(finite(left) - finite(right)) <= math.max(0.00001, math.abs(right) * 0.00001)
end
local function observe(current, spec, descriptor, library)
    assert(descriptor, "Native descriptor absent")
    local name, property, ownerName = table.unpack(spec)
    local owner = current.player[property]
    local ownerClass = "/Script/DogwoodStats." .. ownerName
    local ownerKey = identity(owner, ownerClass)
    assert(identity(owner:GetOuter(), PLAYER) == current.playerKey, "Attribute owner mismatch")
    identity(descriptor.AttributeOwner, "/Script/CoreUObject.Class", true)
    assert(text(descriptor.AttributeOwner:GetFullName()) == "Class " .. ownerClass, "Descriptor owner type mismatch")
    assert(identity(current.asc:GetAttributeSet(descriptor.AttributeOwner), ownerClass) == ownerKey, "ASC attribute set mismatch")
    local address = finite(descriptor:GetStructAddress())
    assert(address > 0, "Descriptor address unavailable")
    local debugName = text(library:GetDebugStringFromGameplayAttribute(descriptor))
    assert(debugName:find(name, 1, true) and debugName:find(ownerName, 1, true), "Descriptor debug name mismatch")
    local base, effective = finite(owner[name].BaseValue), finite(owner[name].CurrentValue)
    local currentOut, baseOut = {}, {}
    local nativeCurrent = finite(current.asc:GetGameplayAttributeValue(descriptor, currentOut))
    local nativeBase = finite(library:GetFloatAttributeBaseFromAbilitySystemComponent(current.asc, descriptor, baseOut))
    assert(currentOut.bFound == true and baseOut.bSuccessfullyFoundAttribute == true, "Native getter found flags unavailable or false")
    assert(near(nativeCurrent, effective) and near(nativeBase, base), "Native getter/property disagreement")
    assert(descriptor:GetStructAddress() == address and text(descriptor.AttributeName) == name, "Descriptor changed")
    local function stable()
        assert(identity(current.player[property], ownerClass) == ownerKey, "Attribute set changed")
        assert(identity(owner:GetOuter(), PLAYER) == current.playerKey, "Attribute owner changed")
        assert(identity(current.asc:GetAttributeSet(descriptor.AttributeOwner), ownerClass) == ownerKey, "ASC set changed")
        assert(near(owner[name].BaseValue, base) and near(owner[name].CurrentValue, effective), "Attribute changed during capture")
        assert(descriptor:GetStructAddress() == address and text(descriptor.AttributeName) == name, "Descriptor changed during capture")
    end
    stable()
    return name .. ": base=" .. base .. ", effective=" .. effective .. ", descriptor=" .. address .. ", owner=" .. ownerKey, stable
end
function M.Capture(helpers)
    local current = context(helpers)
    local library = StaticFindObject("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
    identity(library, "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary", true)
    assert(identity(library:GetAbilitySystemComponent(current.player), "/Script/Dawnwalker.DawnwalkerAbilitySystemComponent")
        == identity(current.asc, "/Script/Dawnwalker.DawnwalkerAbilitySystemComponent"), "ASC library disagreement")
    local native, duplicates, borrowed = descriptors(current.asc)
    local rows, checks, complete = { current.key }, {}, 0
    for _, spec in ipairs(SPECS) do
        local ok, row, stable = pcall(function()
            assert(not duplicates[spec[1]], "Duplicate selected descriptor")
            return observe(current, spec, native[spec[1]], library)
        end)
        if ok then
            complete = complete + 1; rows[#rows + 1] = row; checks[#checks + 1] = stable
        else rows[#rows + 1] = spec[1] .. ": unavailable: " .. tostring(row):sub(1, 240) end
    end
    for _, stable in ipairs(checks) do stable() end
    assert(context(helpers).key == current.key, "Player/world/ASC/form changed during capture")
    assert(borrowed, "Descriptor storage released") -- Retain native out storage through all borrowed calls.
    rows[#rows + 1] = "Read-only. Cost formulas, setters and restoration unverified. Directional-block fields describe restoration; zoom/visibility owners remain unresolved."
    return { status = complete .. "/" .. #SPECS .. " native attribute reads confirmed; no gameplay capability verified.", report = table.concat(rows, "\n") }
end
return M
