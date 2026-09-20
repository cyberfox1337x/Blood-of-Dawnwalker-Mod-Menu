local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_focus_read_only_probe_tests")
local source_path = arg[1] or "integration/uue4ss/feature-candidates/FocusReadOnlyProbe.lua"
local Probe = dofile(source_path)
local passed = 0
local function test(name, run)
    local ok, failure = pcall(run)
    assert(ok, name .. ": " .. tostring(failure))
    passed = passed + 1
    print("PASS " .. name)
end
local function read(path)
    local file = assert(io.open(path, "r"))
    local contents = assert(file:read("*a"))
    assert(file:close())
    return contents
end
local function object(name, address, classes)
    local entry = { name = name, address = address, valid = true }
    function entry:IsValid() return self.valid end
    function entry:IsA(class) return classes[class] == true end
    function entry:GetFullName() return self.name end
    function entry:GetAddress() return self.address end
    return entry
end
local names = { "MaxFocusRange", "MaxFocusSmellRange", "ActiveFocusRange", "ActiveFocusSmellRange" }
local function fixture()
    local f = { on_thread = true, vampire = false, found = true, getter_calls = 0, static_calls = 0, lookups = {} }
    f.identity = { build_id = "25129649", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853",
        metadata_sha256 = "CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6", boot_id = "focus-test-boot" }
    f.world = object("World /Game/Test", 100, { ["/Script/Engine.World"] = true })
    f.player = object("Player /Game/Test.Player", 200, { ["/Script/Dawnwalker.DawnwalkerPlayerCharacter"] = true })
    f.controller = object("Controller /Game/Test.Controller", 300, { ["/Script/Engine.PlayerController"] = true })
    function f.player:GetWorld() return f.world end
    function f.player:GetController() return f.controller end
    function f.player:IsVampire() return f.vampire end
    function f.controller:GetWorld() return f.world end
    function f.controller:IsLocalPlayerController() return true end
    function f.controller:K2_GetPawn() return f.player end
    f.player.bIsInFocusMode, f.player.FocusModeActiveRange = false, 1000
    f.attributes = object("PlayerAttributeSet Player.Attributes", 400, { ["/Script/DogwoodStats.PlayerAttributeSet"] = true })
    function f.attributes:GetOuter() return f.player end
    f.attribute_class = object("Class /Script/DogwoodStats.PlayerAttributeSet", 410,
        { ["/Script/CoreUObject.Class"] = true, ["/Script/CoreUObject.Struct"] = true })
    f.asc = object("ASC Player.ASC", 500, { ["/Script/GameplayAbilities.AbilitySystemComponent"] = true })
    function f.asc:GetOwner() return f.player end
    function f.asc:GetAttributeSet(class) assert(class == f.attribute_class); return f.attributes end
    f.descriptors = {}
    for index, name in ipairs(names) do
        f.attributes[name] = { BaseValue = index * 1000, CurrentValue = index * 1000 + 10 }
        local descriptor = { AttributeName = name, AttributeOwner = f.attribute_class, address = 500 + index }
        function descriptor:IsValid() return true end
        function descriptor:type() return "UScriptStruct" end
        function descriptor:GetStructAddress() return self.address end
        f.descriptors[index] = descriptor
    end
    function f.asc:GetAllAttributes(output)
        for index, descriptor in ipairs(f.descriptors) do output[index] = { get = function() return descriptor end } end
    end
    function f.asc:GetGameplayAttributeValue(descriptor)
        f.getter_calls = f.getter_calls + 1
        assert(f.attributes[descriptor.AttributeName], "Must borrow an existing native descriptor")
        if f.found == "omitted" then return f.attributes[descriptor.AttributeName].CurrentValue end
        return f.attributes[descriptor.AttributeName].CurrentValue, f.found
    end
    f.library = object("AbilitySystemBlueprintLibrary /Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary", 600,
        { ["/Script/GameplayAbilities.AbilitySystemBlueprintLibrary"] = true })
    function f.library:GetAbilitySystemComponent(player) assert(player == f.player); return f.asc end
    function f.library:GetDebugStringFromGameplayAttribute(descriptor) return "PlayerAttributeSet." .. descriptor.AttributeName end
    function f.library:GetFloatAttributeFromAbilitySystemComponent(asc, descriptor)
        assert(asc == f.asc); return f.attributes[descriptor.AttributeName].CurrentValue, true
    end
    function f.library:GetFloatAttributeBaseFromAbilitySystemComponent(asc, descriptor)
        assert(asc == f.asc); return f.attributes[descriptor.AttributeName].BaseValue, true
    end
    f.player.CharacterAttributeSet, f.player.AbilitySystemComponent = f.attributes, f.asc
    f.camera = object("RebelCameraComponent Player.Camera", 700, { ["/Script/RebelCamera.RebelCameraComponent"] = true })
    function f.camera:GetOwner() return f.player end
    function f.camera:GetCameraType() return 1 end
    f.mode = object("FocusAbilityCameraMode Player.Camera.Focus", 800,
        { ["/Script/RebelCamera.RebelCameraMode"] = true, ["/Script/DogwoodCombat.FocusAbilityCameraMode"] = true })
    function f.mode:GetCameraComponent() return f.camera end
    function f.mode:GetTargetActor() return f.player end
    function f.mode:GetState() return 1 end
    function f.mode:GetFieldOfView() return 70 end
    f.mode.DefaultFieldOfView, f.mode.bApplyPostProcessing = 75, true
    f.offsets = { [1] = { bOverrideFOV = true, OverriddenFieldOfView = 70, PivotZOffset = 4,
        bUseOffsetPitchCurves = false, TargetOffset = { X = -2, Y = 8, Z = 0 } } }
    f.mode.CameraOffsets = { ForEach = function(_, callback)
        for key, offset in pairs(f.offsets) do callback({ get = function() return key end }, { get = function() return offset end }) end
    end }
    f.camera.CameraModeStack = { { Handle = { Handle = 1 }, CameraMode = f.mode } }
    f.player.FollowCamera = f.camera
    f.deps = {
        is_in_game_thread = function() return f.on_thread end, get_identity = function() return f.identity end,
        get_player = function() return f.player end, get_controller = function() return f.controller end,
        static_find_object = function(path)
            f.static_calls = f.static_calls + 1
            f.lookups[#f.lookups + 1] = path
            if path == "/Script/DogwoodStats.PlayerAttributeSet" then return f.attribute_class end
            assert(path == "/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary", "Off-contract lookup")
            return f.library
        end,
    }
    return f
end

test("exact native descriptors validate independent base/current getters and camera ownership", function()
    local f = fixture()
    local result = Probe.run(f.deps)
    assert(result.ok and result.attributes.ok and result.camera.ok)
    assert(result.attributes.observations.native_getter_verified and f.getter_calls == 4 and f.static_calls == 2)
    assert(result.attributes.observations.values.MaxFocusRange.base == 1000)
    assert(result.attributes.observations.values.MaxFocusRange.current == 1010)
    assert(result.camera.observations.stack[1].offsets[1].fov == 70)
    assert(result.mutation_authorized == false and result.gameplay_verified == false and #result.capabilities == 0)
end)
test("preflight mismatch performs no native observations", function()
    for _, field in ipairs({ "build_id", "executable_sha256", "metadata_sha256", "thread" }) do
        local f = fixture()
        if field == "thread" then f.on_thread = false else f.identity[field] = "wrong" end
        f.deps.get_player = function() error("No player access permitted") end
        local result = Probe.run(f.deps)
        assert(not result.ok and not result.reason:find("No player access", 1, true))
    end
end)
test("nonlocal possession and class defaults fail before queries", function()
    local f = fixture()
    function f.controller:IsLocalPlayerController() return false end
    assert(not Probe.run(f.deps).ok and f.static_calls == 0)
    f = fixture(); f.player.name = "Default__DawnwalkerPlayerCharacter"
    assert(not Probe.run(f.deps).ok and f.static_calls == 0)
end)
test("missing bool output remains explicitly unverified despite numeric agreement", function()
    local f = fixture(); f.found = "omitted"
    local result = Probe.run(f.deps)
    assert(result.attributes.ok and not result.attributes.observations.native_getter_verified)
    assert(not result.attributes.observations.values.MaxFocusRange.asc_current.found_flag_returned)
end)
test("false found flag rejects only attributes and preserves camera", function()
    local f = fixture(); f.found = false
    local result = Probe.run(f.deps)
    assert(result.ok and not result.attributes.ok and result.camera.ok)
    assert(result.attributes.reason:find("not found", 1, true))
end)
test("unexpected return ordering preserves diagnostic shape without verifying the native call", function()
    for _, shape in ipairs({ "prefix-nil", "reversed", "trailing-nil" }) do
        local f = fixture()
        function f.asc:GetGameplayAttributeValue(descriptor)
            local current = f.attributes[descriptor.AttributeName].CurrentValue
            if shape == "prefix-nil" then return nil, current, true
            elseif shape == "reversed" then return true, current
            else return current, true, nil end
        end
        local result = Probe.run(f.deps)
        assert(result.attributes.ok and not result.attributes.observations.native_getter_verified)
        assert(not result.attributes.observations.values.MaxFocusRange.asc_current.native_shape_verified)
        assert(#result.attributes.observations.values.MaxFocusRange.asc_current.return_shape > 0)
    end
end)
test("wrong descriptor owner and missing or duplicate names are rejected", function()
    for _, defect in ipairs({ "owner", "missing", "duplicate" }) do
        local f = fixture()
        if defect == "owner" then f.descriptors[1].AttributeOwner = object("OtherClass", 411, { ["/Script/CoreUObject.Struct"] = true })
        elseif defect == "missing" then table.remove(f.descriptors, 1)
        else f.descriptors[5] = f.descriptors[1] end
        local result = Probe.run(f.deps)
        assert(not result.attributes.ok and result.camera.ok and f.getter_calls == 0)
    end
end)
test("invalid or oversized descriptor containers are rejected", function()
    for _, defect in ipairs({ "empty", "oversized", "sparse" }) do
        local f = fixture()
        function f.asc:GetAllAttributes(output)
            if defect == "oversized" then for index = 1, 1025 do output[index] = f.descriptors[1] end
            elseif defect == "sparse" then output[10000] = f.descriptors[1] end
        end
        assert(not Probe.run(f.deps).attributes.ok and f.getter_calls == 0)
    end
end)
test("native getter mismatch and ambiguous return shapes cannot pass", function()
    for _, defect in ipairs({ "mismatch", "ambiguous", "table" }) do
        local f = fixture()
        function f.library:GetFloatAttributeBaseFromAbilitySystemComponent()
            if defect == "mismatch" then return 12, true
            elseif defect == "ambiguous" then return 1000, 1000, true
            else return { value = 1000 }, true end
        end
        assert(not Probe.run(f.deps).attributes.ok)
    end
end)
test("wrong ASC ownership and independent resolver disagreement fail", function()
    local f = fixture()
    function f.asc:GetOwner() return f.world end
    assert(not Probe.run(f.deps).attributes.ok)
    f = fixture()
    function f.library:GetAbilitySystemComponent() return f.world end
    assert(not Probe.run(f.deps).attributes.ok)
end)
test("mid-read attribute mutation invalidates native agreement", function()
    local f = fixture()
    function f.library:GetFloatAttributeBaseFromAbilitySystemComponent(_, descriptor)
        local field = f.attributes[descriptor.AttributeName]
        field.CurrentValue = field.CurrentValue + 1
        return field.BaseValue, true
    end
    assert(not Probe.run(f.deps).attributes.ok)
end)
test("focus mode can be absent outside focus without inventing a camera", function()
    local f = fixture(); f.camera.CameraModeStack = {}
    local result = Probe.run(f.deps)
    assert(result.camera.ok and result.camera.observations.focus_mode_count == 0)
end)
test("camera ownership failure preserves attribute observations", function()
    local f = fixture()
    function f.mode:GetTargetActor() return f.world end
    local result = Probe.run(f.deps)
    assert(result.ok and result.attributes.ok and not result.camera.ok)
end)
test("camera stack and offset bounds reject unsafe traversal", function()
    local f = fixture()
    f.camera.CameraModeStack[2] = f.camera.CameraModeStack[1]
    assert(not Probe.run(f.deps).camera.ok)
    f = fixture(); f.offsets[4] = f.offsets[1]
    assert(not Probe.run(f.deps).camera.ok)
end)
test("camera stack drift invalidates that observation", function()
    local f = fixture()
    function f.mode:GetFieldOfView() f.camera.CameraModeStack = {}; return 70 end
    assert(not Probe.run(f.deps).camera.ok)
end)
test("later attribute getter and camera reads cannot leave earlier values apparently current", function()
    for _, trigger in ipairs({ "later-getter", "camera" }) do
        local f = fixture()
        if trigger == "later-getter" then
            function f.library:GetFloatAttributeBaseFromAbilitySystemComponent(_, descriptor)
                if descriptor.AttributeName == "ActiveFocusSmellRange" then
                    f.attributes.MaxFocusRange.BaseValue = 8000
                end
                return f.attributes[descriptor.AttributeName].BaseValue, true
            end
        else
            function f.mode:GetFieldOfView() f.attributes.MaxFocusRange.CurrentValue = 8000; return 70 end
        end
        local result = Probe.run(f.deps)
        assert(not result.ok and result.attributes == nil and result.camera == nil)
        assert(result.reason:find("complete snapshot", 1, true))
    end
end)
test("world, focus and vampire transitions discard the full partial snapshot", function()
    for _, transition in ipairs({ "world", "focus", "vampire" }) do
        local f = fixture()
        function f.mode:GetFieldOfView()
            if transition == "world" then f.world.address = f.world.address + 1
            elseif transition == "focus" then f.player.bIsInFocusMode = true
            else f.vampire = true end
            return 70
        end
        local result = Probe.run(f.deps)
        assert(not result.ok and result.attributes == nil and result.camera == nil)
    end
end)
test("read-only source has no native mutations or side-effect entrypoints", function()
    local source = read(source_path)
    for _, pattern in ipairs({ "BaseValue%s*=[^=]", "CurrentValue%s*=[^=]", "DefaultFieldOfView%s*=", "OverriddenFieldOfView%s*=",
        "bOverrideFOV%s*=", "SetAttribute", "ApplyGameplayEffect", "RemoveActiveGameplayEffect", "PushCameraMode",
        "PopCameraMode", "StaticLoadObject", "LoadAsset", "RegisterKeyBind", "LoopAsync", "io%.open", "os%.execute" }) do
        assert(not source:find(pattern), "Forbidden source operation: " .. pattern)
    end
end)
test("native getter names and camera fields match the current captured headers", function()
    local root = arg[2] or "qa/discovery-current-build-20260906/fresh-metadata/CXXHeaderDump/"
    local gameplay, camera, player, stats, combat = read(root .. "GameplayAbilities.hpp"), read(root .. "RebelCamera.hpp"),
        read(root .. "Dawnwalker.hpp"), read(root .. "DogwoodStats.hpp"), read(root .. "DogwoodCombat.hpp")
    for _, signature in ipairs({ "float GetGameplayAttributeValue(FGameplayAttribute Attribute, bool& bFound);",
        "void GetAllAttributes(TArray<FGameplayAttribute>& OutAttributes);",
        "float GetFloatAttributeFromAbilitySystemComponent(const class UAbilitySystemComponent* AbilitySystem, FGameplayAttribute Attribute, bool& bSuccessfullyFoundAttribute);",
        "float GetFloatAttributeBaseFromAbilitySystemComponent(const class UAbilitySystemComponent* AbilitySystemComponent, FGameplayAttribute Attribute, bool& bSuccessfullyFoundAttribute);" }) do
        assert(gameplay:find(signature, 1, true), "Native signature drift: " .. signature)
    end
    assert(combat:find("class UFocusAbilityCameraMode : public URebelCameraModeTPP", 1, true))
    assert(camera:find("TArray<FStackedCameraMode> CameraModeStack;", 1, true))
    assert(camera:find("TMap<ECameraType, FCameraOffset> CameraOffsets;", 1, true))
    assert(camera:find("class URebelCameraComponent* GetCameraComponent();", 1, true))
    assert(camera:find("class AActor* GetTargetActor();", 1, true))
    assert(player:find("bool IsVampire();", 1, true))
    assert(player:find("class URebelCameraComponent* FollowCamera;", 1, true))
    for _, name in ipairs(names) do assert(stats:find("FGameplayAttributeData " .. name .. ";", 1, true)) end
end)
print(tostring(passed) .. " Focus read-only groups passed; no gameplay proof implied")
