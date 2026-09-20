local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_stamina_read_only_probe_tests")
local Probe = dofile(arg[1] or "integration/uue4ss/feature-candidates/StaminaReadOnlyProbe.lua")
local passed = 0
local function test(name, run)
    local ok, failure = pcall(run)
    if not ok then error(name .. ": " .. tostring(failure), 0) end
    passed = passed + 1
    print("PASS " .. name)
end
local function object(name, address, class)
    local result = { name = name, address = address, valid = true }
    function result:IsValid() return self.valid end
    function result:IsA(expected) return expected == class end
    function result:GetFullName() return self.name end
    function result:GetAddress() return self.address end
    return result
end
local function fixture()
    local f = { on_thread = true, vampire = false, getters = 0, descriptors = {} }
    local player_class = "/Script/DogwoodStats.PlayerAttributeSet"
    local dev_class = "/Script/DogwoodStats.CharDevAttributeSet"
    f.identity = { build_id = "25129649", boot_id = "probe-boot", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853",
        metadata_sha256 = "CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6" }
    f.player = object("Player", 1, "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
    f.world = object("World", 2, "/Script/Engine.World")
    function f.player:GetWorld() return f.world end
    function f.player:IsVampire() return f.vampire end
    f.controller = object("Controller", 3, "/Script/Engine.PlayerController")
    function f.controller:IsLocalController() return true end
    function f.controller:K2_GetPawn() return f.player end
    f.asc = object("AbilitySystem", 4, "/Script/GameplayAbilities.AbilitySystemComponent")
    f.player.AbilitySystemComponent = f.asc
    function f.asc:GetOwner() return f.player end
    f.attributes = object("Attributes", 5, player_class)
    f.development = object("Development", 6, dev_class)
    f.player.CharacterAttributeSet, f.player.CharDevAttributeSet = f.attributes, f.development
    f.types = {
        [player_class] = object("Class " .. player_class, 7, "/Script/CoreUObject.Class"),
        [dev_class] = object("Class " .. dev_class, 8, "/Script/CoreUObject.Class"),
    }
    local names = { "SprintStaminaCostMultiplier", "DodgeStaminaCostMultiplier", "OmniblockStaminaCostMultiplier",
        "DirectionalBlockStaminaRestoreMultiplier", "DirectionalBlockStaminaRestoreModifier" }
    for index, name in ipairs(names) do
        local set = index <= 2 and f.attributes or f.development
        set[name] = { BaseValue = index - 1, CurrentValue = index - 0.5 }
        local descriptor = { AttributeName = name, AttributeOwner = f.types[index <= 2 and player_class or dev_class], address = 20 + index }
        function descriptor:type() return "UScriptStruct" end
        function descriptor:IsValid() return true end
        function descriptor:GetStructAddress() return self.address end
        f.descriptors[index] = descriptor
    end
    function f.asc:GetAllAttributes(output)
        for index, value in ipairs(f.descriptors) do output[index] = { get = function() return value end } end
    end
    function f.asc:GetAttributeSet(class)
        if f.wrong_set then return f.wrong_set end
        return class == f.types[player_class] and f.attributes or f.development
    end
    local function pair(descriptor)
        local set = descriptor.AttributeOwner == f.types[player_class] and f.attributes or f.development
        return set[descriptor.AttributeName]
    end
    function f.asc:GetGameplayAttributeValue(descriptor)
        f.getters = f.getters + 1
        if f.on_getter then return f.on_getter(descriptor, pair(descriptor).CurrentValue) end
        return pair(descriptor).CurrentValue, true
    end
    f.library = object("AbilitySystemBlueprintLibrary /Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary", 10,
        "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary")
    function f.library:GetDebugStringFromGameplayAttribute(descriptor) return descriptor.AttributeName end
    function f.library:GetFloatAttributeBaseFromAbilitySystemComponent(asc, descriptor)
        assert(asc == f.asc)
        if f.on_base then return f.on_base(descriptor, pair(descriptor).BaseValue) end
        return pair(descriptor).BaseValue, true
    end
    f.combat = object("Combat", 11, "/Script/DogwoodCombat.PlayerCombatComponent")
    f.config = object("Config", 12, "/Script/DogwoodCombat.CombatConfig")
    f.player.CombatComponent, f.combat.Config = f.combat, f.config
    function f.combat:GetOwner() return f.player end
    function f.combat:GetConfig() return f.config end
    function f.combat:GetDodgeStaminaCost() return 10 end
    for index, name in ipairs({ "StaminaDamageEffectClass", "OmniblockStaminaDamageEffectClass", "BlockStaminaRegenEffectClass" }) do
        f.config[name] = object(name, 50 + index, "/Script/CoreUObject.Class")
    end
    f.config.CombatActionStaminaCosts = object("StaminaTable", 60, "/Script/Engine.DataTable")
    f.deps = {
        get_identity = function() return f.identity end,
        is_in_game_thread = function() return f.on_thread end,
        get_player = function() return f.player end,
        get_player_controller = function() return f.controller end,
        static_find_object = function(path)
            assert(path == "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
            return f.library
        end,
    }
    return f
end

test("five separate channels use real descriptors with base/current agreement", function()
    local f = fixture()
    local result = Probe.run(f.deps)
    assert(result.ok and not result.mutation_authorized and not result.gameplay_verified and #result.capabilities == 0)
    assert(result.native_descriptor_count == 5 and f.getters == 5 and not result.is_vampire)
    for _, channel in pairs(result.channels) do assert(channel.ok and channel.observations.getter_verified) end
    assert(result.channels.sprint.observations.property.base == 0)
    assert(result.channels.dodge.observations.property.current == 1.5)
    assert(result.channels.directional_block_restore_modifier.observations.semantic_scope:find("not a directional block cost", 1, true))
    assert(result.combat.ok and result.combat.observations.dodge_cost == 10)
end)

test("native out-bool absence is reported unverified without inventing success", function()
    local f = fixture()
    f.on_getter = function(_, value) return value end
    local result = Probe.run(f.deps)
    assert(result.ok)
    local getter = result.channels.sprint.observations.native_effective
    assert(not getter.verified and getter.return_count == 1 and getter.found == nil)
    assert(not result.channels.sprint.observations.getter_verified)
end)

test("false, swapped, extra or mismatched getter results remain unverified", function()
    for _, fake in ipairs({
        function(_, value) return value, false end,
        function(_, value) return true, value end,
        function(_, value) return value, true, "extra" end,
        function(_, value) return value + 10, true end,
        function() return 0/0, true end,
    }) do
        local f = fixture()
        f.on_getter = fake
        local result = Probe.run(f.deps)
        assert(result.ok and not result.channels.sprint.observations.native_effective.verified)
    end
end)

test("duplicate and missing descriptors affect only their channels", function()
    local f = fixture()
    f.descriptors[5] = f.descriptors[1]
    local result = Probe.run(f.deps)
    assert(result.ok and not result.channels.sprint.ok and not result.channels.directional_block_restore_modifier.ok)
    assert(result.channels.dodge.ok and result.channels.omniblock.ok)
end)

test("wrong native owner and different ASC attribute instance are refused", function()
    local f = fixture()
    f.descriptors[1].AttributeOwner = f.types["/Script/DogwoodStats.CharDevAttributeSet"]
    local result = Probe.run(f.deps)
    assert(result.ok and not result.channels.sprint.ok and f.getters == 4)
    f = fixture()
    f.wrong_set = object("UnownedAttributes", 1000, "/Script/DogwoodStats.PlayerAttributeSet")
    result = Probe.run(f.deps)
    assert(result.ok and not result.channels.sprint.ok and f.getters == 0)
end)

test("exact identity thread and local controller gates precede all getters", function()
    local f = fixture()
    f.on_thread = false
    assert(not Probe.run(f.deps).ok)
    f.on_thread = true
    f.identity.build_id = "previous"
    assert(not Probe.run(f.deps).ok)
    f.identity.build_id = "25129649"
    function f.controller:IsLocalController() return false end
    assert(not Probe.run(f.deps).ok and f.getters == 0)
end)

test("changed player form discards every partial observation", function()
    local f = fixture()
    f.on_getter = function(_, value) f.vampire = true; return value, true end
    local result = Probe.run(f.deps)
    assert(not result.ok and result.channels == nil and result.player == nil)
    assert(result.reason:find("form changed", 1, true))
end)

test("attribute drift in a later channel invalidates the complete observation", function()
    local f = fixture()
    f.on_getter = function(descriptor, value)
        if descriptor.AttributeName == "OmniblockStaminaCostMultiplier" then f.attributes.SprintStaminaCostMultiplier.BaseValue = 3 end
        return value, true
    end
    local result = Probe.run(f.deps)
    assert(not result.ok and result.channels == nil and result.reason:find("complete probe", 1, true))
end)

test("native getter errors and absent combat provenance remain distinct", function()
    local f = fixture()
    f.on_base = function() error("native ABI rejected") end
    f.config.CombatActionStaminaCosts = nil
    local result = Probe.run(f.deps)
    assert(result.ok and not result.combat.ok)
    assert(result.channels.sprint.ok and not result.channels.sprint.observations.getter_verified)
    assert(result.channels.sprint.observations.native_base.reason:find("ABI rejected", 1, true))
end)

test("empty or excessive native arrays fail before reads", function()
    local f = fixture()
    f.descriptors = {}
    assert(not Probe.run(f.deps).ok and f.getters == 0)
    function f.asc:GetAllAttributes(output) for index = 1, 1025 do output[index] = {} end end
    assert(not Probe.run(f.deps).ok and f.getters == 0)
end)

test("probe contains no native mutator or live registration", function()
    local file = assert(io.open(arg[1] or "integration/uue4ss/feature-candidates/StaminaReadOnlyProbe.lua", "r"))
    local source = file:read("*a")
    file:close()
    for _, forbidden in ipairs({ ":SetAttributeValue(", ":LockStamina(", "RegisterHook(", "RegisterKeyBind(", ":ApplyGameplayEffect", "StaticConstructObject(", "LoadAsset(" }) do
        assert(not source:find(forbidden, 1, true), "Unexpected native mutation/registration: " .. forbidden)
    end
    assert(not source:find("%.BaseValue%s*=") and not source:find("%.CurrentValue%s*="))
end)

test("selected attributes and native getters exist in current captured headers", function()
    local function read_header(name)
        local file = assert(io.open("qa/discovery-current-build-20260906/fresh-metadata/CXXHeaderDump/" .. name .. ".hpp", "r"))
        local value = file:read("*a")
        file:close()
        return value
    end
    local stats, abilities, combat = read_header("DogwoodStats"), read_header("GameplayAbilities"), read_header("DogwoodCombat")
    for _, descriptor in ipairs(fixture().descriptors) do
        assert(stats:find("FGameplayAttributeData " .. descriptor.AttributeName .. ";", 1, true))
    end
    assert(abilities:find("void GetAllAttributes(TArray<FGameplayAttribute>& OutAttributes);", 1, true))
    assert(abilities:find("float GetGameplayAttributeValue(FGameplayAttribute Attribute, bool& bFound);", 1, true))
    assert(abilities:find("float GetFloatAttributeBaseFromAbilitySystemComponent(const class UAbilitySystemComponent* AbilitySystemComponent, FGameplayAttribute Attribute, bool& bSuccessfullyFoundAttribute);", 1, true))
    assert(combat:find("float GetDodgeStaminaCost();", 1, true))
end)

print(string.format("%d stamina probe test groups passed", passed))
