local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_requested_features_read_only_probe_tests")

local source_path = assert(arg[1], "Pass the requested-feature probe source path.")
local source_file = assert(io.open(source_path, "r"))
local source = source_file:read("*a")
source_file:close()
for _, pattern in ipairs({
    "SetAttributeValue%s*%(", "SetVectorParameterValue%s*%(", "SetScalarParameterValue%s*%(",
    "CreateDynamicMaterialInstance%s*%(", "ApplyGameplayEffect", "RemoveActiveGameplayEffect",
    "BaseValue%s*=", "CurrentValue%s*=", "AttackPlayrate%s*=", "StrongAttackPlayrate%s*=",
    "StaticLoadObject", "RegisterKeyBind", "io%.open", "os%.execute",
}) do
    assert(source:find(pattern) == nil, "Read-only source contains a forbidden mutation or side effect: " .. pattern)
end
local Probe = assert(dofile(source_path))

local function check(condition, label)
    if not condition then error(label, 2) end
end

local function object(address, name, class)
    local instance = { address = address, name = name, class = class, valid = true }
    function instance:IsValid() return self.valid end
    function instance:IsA(expected) return expected == self.class end
    function instance:GetAddress() return self.address end
    function instance:GetFullName() return self.name end
    return instance
end

local function fixture()
    local world = object(10, "World /Game/Test.Test", "/Script/Engine.World")
    local player = object(20, "BP_Player_C /Game/Test.Test:PersistentLevel.Player", "/Script/Dawnwalker.DawnwalkerPlayerCharacter")
    function player:GetWorld() return world end
    local attributes = object(30, "PlayerAttributeSet Player.PlayerAttributes", "/Script/DogwoodStats.PlayerAttributeSet")
    local char_dev = object(31, "CharDevAttributeSet Player.CharDev", "/Script/DogwoodStats.CharDevAttributeSet")
    for _, name in ipairs({ "MaxFocusRange", "MaxFocusSmellRange", "ActiveFocusRange", "ActiveFocusSmellRange",
        "SprintStaminaCostMultiplier", "DodgeStaminaCostMultiplier" }) do
        attributes[name] = { BaseValue = 1, CurrentValue = 1 }
    end
    attributes.MaxFocusRange = { BaseValue = 4000, CurrentValue = 4000 }
    attributes.MaxFocusSmellRange = { BaseValue = 2000, CurrentValue = 2000 }
    char_dev.OmniblockStaminaCostMultiplier = { BaseValue = 1, CurrentValue = 1 }
    player.CharacterAttributeSet = attributes
    player.CharDevAttributeSet = char_dev
    local combat = object(40, "PlayerCombatComponent Player.Combat", "/Script/DogwoodCombat.PlayerCombatComponent")
    local config = object(41, "CombatConfig /Game/Test.Config", "/Script/DogwoodCombat.CombatConfig")
    local modes = {}
    for index = 1, 5 do
        local mode = object(50 + index, "CombatMode /Game/Test.Mode" .. index, "/Script/DogwoodCombat.CombatMode")
        mode.MetricsScalingSettings = { AttackPlayrate = 1, StrongAttackPlayrate = 1, DodgePlayrate = 1,
            BlockPlayrate = 1, DefaultRootMotionScaling = 1 }
        mode.DodgeStaminaCost = 20
        modes[index] = mode
    end
    config.CombatModes = {
        Contains = function(_, index) return modes[index] ~= nil end,
        Find = function(_, index) return { get = function() return modes[index] end } end,
    }
    combat.Config = config
    function combat:GetConfig() return self.Config end
    player.CombatComponent = combat
    local material = object(61, "MaterialInstanceDynamic /Game/Test.Iris", "/Script/Engine.MaterialInstance")
    local function parameter(name, value)
        return { ParameterInfo = { Name = { ToString = function() return name end } }, ParameterValue = value }
    end
    material.ScalarParameterValues = { parameter("ObservedScalar", 0.5) }
    material.VectorParameterValues = { parameter("ObservedVector", { R = 1, G = 0, B = 0.5, A = 1 }) }
    local mesh = object(60, "SkeletalMeshComponent Player.Head", "/Script/Engine.SkeletalMeshComponent")
    function mesh:GetOwner() return player end
    function mesh:GetNumMaterials() return 1 end
    function mesh:GetMaterial(index) check(index == 0, "material indexing must be zero based"); return material end
    local mesh_class = object(62, "Class /Script/Engine.SkeletalMeshComponent", "/Script/CoreUObject.Class")
    function player:K2_GetComponentsByClass(actual_class)
        check(actual_class == mesh_class, "exact skeletal class required")
        return { { get = function() return mesh end } }
    end
    local deps = {
        get_player = function() return player end,
        static_find_object = function(path) check(path == "/Script/Engine.SkeletalMeshComponent", "exact class path"); return mesh_class end,
        game_thread = true,
        identity = { build_id = "25107392", executable_sha256 = "45B7C2949F519ED3E45F7FBDB7127A03373FE44B34ABB58E3C987C5054E2409E" },
    }
    return deps, { player = player, world = world, attributes = attributes, char_dev = char_dev,
        combat = combat, config = config, modes = modes, material = material, mesh = mesh }
end

local total = 0
local function test(label, run)
    run()
    total = total + 1
    print("PASS " .. label)
end

test("complete read-only snapshot has no mutation or gameplay authority", function()
    local deps, objects = fixture()
    local result = Probe.run(deps)
    check(result.ok and result.attributes.ok and result.attack_modes.ok and result.materials.ok, "all read sections should pass")
    check(result.mutation_authorized == false and result.gameplay_verified == false, "must not promote read observations")
    check(result.attributes.observations.values.MaxFocusRange.current == 4000, "focus range readback")
    check(#result.attack_modes.observations.modes == 5, "all known player modes")
    check(result.materials.observations.components[1].materials[1].parameters.vector[1].name == "ObservedVector", "reads actual parameter names")
    check(objects.modes[1].MetricsScalingSettings.AttackPlayrate == 1 and objects.attributes.MaxFocusRange.CurrentValue == 4000,
        "observed values remain unchanged")
    check(Probe.format_lines(result):find("requested_features.mutation_authorized=false", 1, true) ~= nil, "report preserves read-only declaration")
end)

test("identity and game-thread preflights reject without reading player", function()
    for _, reason in ipairs({ "build", "hash", "thread" }) do
        local deps = fixture()
        deps.get_player = function() error("must not inspect player after failed preflight") end
        if reason == "build" then deps.identity.build_id = "unknown"
        elseif reason == "hash" then deps.identity.executable_sha256 = "unknown"
        else deps.game_thread = false end
        local result = Probe.run(deps)
        check(not result.ok and result.reason:find("must not inspect", 1, true) == nil, "failed preflight must precede player read")
    end
end)

test("class default player and wrong attribute class reject", function()
    local deps, objects = fixture()
    objects.player.name = "Default__DawnwalkerPlayerCharacter"
    check(not Probe.run(deps).ok, "reject CDO player")
    deps, objects = fixture()
    objects.attributes.class = "/Script/DogwoodStats.CharacterBaseAttributeSet"
    local result = Probe.run(deps)
    check(result.ok and not result.attributes.ok and result.attack_modes.ok, "section fails separately without guessing inherited player fields")
end)

test("nonfinite attributes and partial mode maps fail their sections", function()
    local deps, objects = fixture()
    objects.attributes.MaxFocusRange.CurrentValue = 0 / 0
    objects.modes[5] = nil
    local result = Probe.run(deps)
    check(result.ok and not result.attributes.ok and not result.attack_modes.ok and result.materials.ok,
        "invalid sections remain blocked while independent observations survive")
end)

test("different config owner and foreign mesh owner reject", function()
    local deps, objects = fixture()
    function objects.combat:GetConfig() return object(999, "CombatConfig Other.Config", "/Script/DogwoodCombat.CombatConfig") end
    function objects.mesh:GetOwner() return object(999, "Player Other.Player", "/Script/Dawnwalker.DawnwalkerPlayerCharacter") end
    local result = Probe.run(deps)
    check(not result.attack_modes.ok and not result.materials.ok, "ownership disagreement must block observations")
end)

test("excessive component and material counts are bounded", function()
    local deps, objects = fixture()
    function objects.player:K2_GetComponentsByClass() return { GetArrayNum = function() return 33 end } end
    check(not Probe.run(deps).materials.ok, "component bound")
    deps, objects = fixture()
    function objects.mesh:GetNumMaterials() return 33 end
    check(not Probe.run(deps).materials.ok, "material bound")
    deps, objects = fixture()
    objects.material.ScalarParameterValues = { GetArrayNum = function() return 129 end }
    check(not Probe.run(deps).materials.ok, "parameter bound")
end)

test("world change discards every partial observation", function()
    local deps, objects = fixture()
    local calls = 0
    deps.get_player = function()
        calls = calls + 1
        if calls > 1 then objects.world.address = 999 end
        return objects.player
    end
    local result = Probe.run(deps)
    check(not result.ok and result.attributes == nil and result.attack_modes == nil and result.materials == nil,
        "world drift discards partial snapshots")
end)

test("material names are reported only as observations and encoded safely", function()
    local deps, objects = fixture()
    objects.material.VectorParameterValues[1].ParameterInfo.Name.ToString = function() return "Eye\nColor%" end
    local result = Probe.run(deps)
    local report = Probe.format_lines(result)
    check(report:find("Eye%0AColor%25", 1, true) ~= nil, "report must encode newline and percent")
    check(result.mutation_authorized == false, "a discovered eye-like name never authorizes edits")
end)

print(string.format("Passed %d requested-feature read-only probe tests.", total))
