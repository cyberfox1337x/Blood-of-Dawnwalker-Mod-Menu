local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("combat_attribute_inspection_tests")
local path = assert(arg[1], "Pass CombatAttributeInspection.lua path")
local function fixture()
    local names = { "SprintStaminaCostMultiplier", "DodgeStaminaCostMultiplier", "OmniblockStaminaCostMultiplier",
        "DirectionalBlockStaminaRestoreMultiplier", "DirectionalBlockStaminaRestoreModifier",
        "MaxFocusRange", "ActiveFocusRange", "MaxFocusSmellRange", "ActiveFocusSmellRange" }
    local function object(class, address, name)
        return { IsValid = function() return true end, IsA = function(_, expected) return expected == class end,
            GetAddress = function() return address end, GetFullName = function() return name or class end }
    end
    local player = object("/Script/Dawnwalker.DawnwalkerPlayerCharacter", 1)
    local world = object("/Script/Engine.World", 2)
    local controller = object("/Script/Engine.PlayerController", 3)
    local asc = object("/Script/Dawnwalker.DawnwalkerAbilitySystemComponent", 4)
    player.Controller = controller; controller.Pawn = player; player.AbilitySystemComponent = asc
    player.GetWorld = function() return world end; controller.GetWorld = player.GetWorld
    player.IsVampire = function() return false end; asc.GetOuter = function() return player end
    local sets, owners, descriptors = {}, {}, {}
    for index, name in ipairs({ "PlayerAttributeSet", "CharDevAttributeSet" }) do
        sets[name] = object("/Script/DogwoodStats." .. name, 10 + index)
        sets[name].GetOuter = function() return player end
        owners[name] = object("/Script/CoreUObject.Class", 20 + index, "Class /Script/DogwoodStats." .. name)
    end
    player.CharacterAttributeSet = sets.PlayerAttributeSet; player.CharDevAttributeSet = sets.CharDevAttributeSet
    for index, name in ipairs(names) do
        local ownerName = index >= 3 and index <= 5 and "CharDevAttributeSet" or "PlayerAttributeSet"
        sets[ownerName][name] = { BaseValue = index, CurrentValue = index + 0.5 }
        descriptors[index] = { AttributeName = name, AttributeOwner = owners[ownerName],
            IsValid = function() return true end, type = function() return "UScriptStruct" end,
            GetStructAddress = function() return 100 + index end, ownerName = ownerName }
    end
    asc.GetAllAttributes = function(_, out) out.OutAttributes = descriptors end
    asc.GetAttributeSet = function(_, owner)
        for name, value in pairs(owners) do if value == owner then return sets[name] end end
    end
    asc.GetGameplayAttributeValue = function(_, descriptor, out)
        out.bFound = true; return sets[descriptor.ownerName][descriptor.AttributeName].CurrentValue
    end
    local library = object("/Script/GameplayAbilities.AbilitySystemBlueprintLibrary", 30, "Default__AbilitySystemBlueprintLibrary")
    library.GetAbilitySystemComponent = function() return asc end
    library.GetDebugStringFromGameplayAttribute = function(_, descriptor) return descriptor.ownerName .. "." .. descriptor.AttributeName end
    library.GetFloatAttributeBaseFromAbilitySystemComponent = function(_, _, descriptor, out)
        out.bSuccessfullyFoundAttribute = true; return sets[descriptor.ownerName][descriptor.AttributeName].BaseValue
    end
    local environment = setmetatable({ IsInGameThread = function() return true end,
        StaticFindObject = function() return library end }, { __index = _G })
    local module = assert(loadfile(path, "t", environment))()
    return { capture = function() return module.Capture({ GetPlayer = function() return player end }) end,
        asc = asc, player = player, controller = controller, descriptors = descriptors,
        sets = sets, library = library, environment = environment }
end
local tests = {
    { "complete owned descriptor capture", function()
        local result = fixture().capture()
        assert(result.status:find("9/9", 1, true)); assert(result.report:find("base=1, effective=1.5", 1, true))
        assert(result.report:find("zoom/visibility owners remain unresolved", 1, true))
    end },
    { "wrong pawn rejected", function()
        local f = fixture(); f.controller.Pawn = f.asc; assert(not pcall(f.capture))
    end },
    { "wrong ASC owner rejected", function()
        local f = fixture(); f.asc.GetOuter = function() return f.asc end; assert(not pcall(f.capture))
    end },
    { "thread rejected", function()
        local f = fixture(); f.environment.IsInGameThread = function() return false end; assert(not pcall(f.capture))
    end },
    { "missing descriptor explicit", function()
        local f = fixture(); table.remove(f.descriptors, 1); local result = f.capture()
        assert(result.status:find("8/9", 1, true)); assert(result.report:find("Native descriptor absent", 1, true))
    end },
    { "duplicate selected descriptor explicit", function()
        local f = fixture(); f.descriptors[#f.descriptors + 1] = f.descriptors[1]
        assert(f.capture().report:find("Duplicate selected descriptor", 1, true))
    end },
    { "found flag mandatory", function()
        local f = fixture(); f.asc.GetGameplayAttributeValue = function() return 1.5 end
        assert(f.capture().status:find("0/9", 1, true))
    end },
    { "getter mismatch explicit", function()
        local f = fixture(); f.asc.GetGameplayAttributeValue = function(_, _, out) out.bFound = true; return 900 end
        assert(f.capture().report:find("Native getter/property disagreement", 1, true))
    end },
    { "late cross-channel drift rejected", function()
        local f = fixture(); local get = f.library.GetFloatAttributeBaseFromAbilitySystemComponent
        f.library.GetFloatAttributeBaseFromAbilitySystemComponent = function(self, asc, descriptor, out)
            if descriptor.AttributeName == "ActiveFocusSmellRange" then f.sets.PlayerAttributeSet.SprintStaminaCostMultiplier.BaseValue = 99 end
            return get(self, asc, descriptor, out)
        end
        assert(not pcall(f.capture))
    end },
    { "form drift rejected", function()
        local f = fixture(); local calls = 0
        f.player.IsVampire = function() calls = calls + 1; return calls > 1 end
        assert(not pcall(f.capture))
    end },
    { "malformed output rejected", function()
        local f = fixture(); f.asc.GetAllAttributes = function(_, out) out.unknown = {} end
        assert(not pcall(f.capture))
    end },
    { "descriptor limit rejected", function()
        local f = fixture(); for index = 10, 1025 do f.descriptors[index] = f.descriptors[1] end
        assert(not pcall(f.capture))
    end },
    { "wrong attribute owner explicit", function()
        local f = fixture(); f.sets.PlayerAttributeSet.GetOuter = function() return f.asc end
        assert(f.capture().report:find("unavailable", 1, true)); assert(f.capture().status:find("3/9", 1, true))
    end },
    { "nonfinite read explicit", function()
        local f = fixture(); f.sets.PlayerAttributeSet.SprintStaminaCostMultiplier.BaseValue = 0/0
        assert(f.capture().report:find("Nonfinite native value", 1, true))
    end },
}
for _, test in ipairs(tests) do
    local ok, failure = pcall(test[2]); assert(ok, test[1] .. ": " .. tostring(failure))
end
local queue, labels, section = {}, {}, nil
local environment = setmetatable({ ExecuteInGameThread = function(callback) queue[#queue + 1] = callback end }, { __index = _G })
local discoveryPath = path:gsub("CombatAttributeInspection.lua$", "CombatDiscovery.lua")
local discovery = assert(loadfile(discoveryPath, "t", environment))()
local inspection = { Capture = function() return { status = "Observed", report = "Current capture" } end }
discovery.Init({ Register = function(value) section = value end,
    SetLabel = function(_, id, value) labels[id] = value end }, {}, nil, nil, inspection)
assert(#queue == 0, "Registration must be inert")
local action
for _, entry in ipairs(section.items) do if entry.id == "inspectAttributes" then action = entry end end
assert(action, "Explicit inspection action missing")
action.onClick(); assert(#queue == 1 and labels.attributeReport == "")
table.remove(queue, 1)(); assert(labels.attributeReport == "Current capture")
inspection.Capture = function() error("Native failure") end
action.onClick(); assert(not pcall(table.remove(queue, 1)))
assert(labels.attributeReport == "" and labels.attributeStatus:find("Native failure", 1, true))
labels.attributeReport = "Old session"
discovery.ResetSession(); assert(labels.attributeReport == "")
print("CombatAttributeInspection: " .. #tests .. " groups passed")
print("Combat attribute action: inert registration, queued capture, propagated failure and session clearing passed")
