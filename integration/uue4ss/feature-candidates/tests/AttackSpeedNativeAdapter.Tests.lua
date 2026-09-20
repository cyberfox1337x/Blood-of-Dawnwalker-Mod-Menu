local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_attack_speed_native_adapter_tests")
local Adapter = dofile(arg[1] or "integration/uue4ss/feature-candidates/AttackSpeedNativeAdapter.lua")
local Controller = dofile(arg[2] or "integration/uue4ss/feature-candidates/AttackSpeedController.lua")
local passed = 0
local function test(name, run)
    local ok, failure = pcall(run)
    if not ok then error(name .. ": " .. tostring(failure), 0) end
    passed = passed + 1
    print("PASS " .. name)
end
local function rejects(run, fragment)
    local ok, failure = pcall(run)
    assert(not ok and tostring(failure):find(fragment, 1, true), "Expected " .. fragment .. ", got " .. tostring(failure))
end
local function object(name, address, classes)
    local value = { name = name, address = address, valid = true }
    function value:IsValid() return self.valid end
    function value:IsA(class) return classes[class] == true end
    function value:GetFullName() return self.name end
    function value:GetAddress() return self.address end
    return value
end
local function mode(name, address)
    local value = object(name, address, { ["/Script/DogwoodCombat.CombatMode"] = true })
    value.DodgeStaminaCost = 9
    local data = {
        DefaultRootMotionScaling = 1, AttackPlayrate = 1.2, StrongAttackPlayrate = 0.8,
        DodgePlayrate = 1, ShadowDodgePlayrate = 1, BlockPlayrate = 1, BlockReactionPlayrate = 1,
        ParryPlayrate = 1, ParryVsUnarmedPlayrate = 1, ParryReactionPlayrate = 1, HitReactionPlayrate = 1,
        StrongHitReactionPlayrate = 1, TauntPlayrate = 1, TurnInPlacePlayrate = 1,
        AttackMetric = 0, StrongAttackMetric = 0, DodgeMetric = 0, ShadowDodgeMetric = 0,
        BlockMetric = 0, BlockReactionMetric = 0, ParryMetric = 0, ParryVsUnarmedMetric = 0,
        ParryReactionMetric = 0, HitReactionMetric = 0, StrongHitReactionMetric = 0, TauntMetric = 0,
    }
    local methods = { mapped = true, address = address + 140 }
    function methods:type() return "UScriptStruct" end
    function methods:IsValid() return true end
    function methods:IsMappedToObject() return self.mapped end
    function methods:IsMappedToProperty() return self.mapped end
    function methods:GetStructAddress() return self.address end
    function methods:GetPropertyAddress() return 800 end
    local writes = {}
    value.MetricsScalingSettings = setmetatable({}, {
        __index = function(_, key) return methods[key] ~= nil and methods[key] or data[key] end,
        __newindex = function(_, key, next_value)
            writes[#writes + 1] = key
            data[key] = next_value
        end,
    })
    value.data, value.methods, value.writes = data, methods, writes
    return value
end
local function map(entries)
    return {
        Contains = function(_, key) return entries[key] ~= nil end,
        Find = function(_, key) return { get = function() return entries[key] end } end,
        ForEach = function(_, fn)
            for key, entry in pairs(entries) do fn({ get = function() return key end }, { get = function() return entry end }) end
        end,
    }
end
local function fixture()
    local f = { on_thread = true, review = nil, scans = 0 }
    f.identity = { build_id = "25129649", executable_sha256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853",
        metadata_sha256 = "CFEA26EA90EDA15B8BE09DC397029BC9FE33459588E53AC2FBB6D4594BD9ACD6", boot_id = "current-boot" }
    f.player = object("Player", 1000, { ["/Script/Dawnwalker.DawnwalkerPlayerCharacter"] = true, ["/Script/Engine.Actor"] = true })
    f.world = object("World", 1100, { ["/Script/Engine.World"] = true })
    function f.player:GetWorld() return f.world end
    f.controller = object("LocalController", 1200, { ["/Script/Engine.PlayerController"] = true })
    function f.controller:IsLocalController() return true end
    function f.controller:K2_GetPawn() return f.player end
    f.combat = object("PlayerCombat", 1300, { ["/Script/DogwoodCombat.PlayerCombatComponent"] = true, ["/Script/DogwoodCombat.CombatComponentBase"] = true })
    function f.combat:GetOwner() return f.player end
    f.config = object("PlayerConfig", 1400, { ["/Script/DogwoodCombat.CombatConfig"] = true })
    f.modes = {}
    for index = 1, 5 do f.modes[index] = mode("Mode" .. index, 2000 + 1000 * index) end
    f.config.CombatModes = map(f.modes)
    f.combat.Config = f.config
    function f.combat:GetConfig() return f.config end
    f.player.CombatComponent = f.combat
    f.npc = object("NPC", 9000, { ["/Script/Engine.Actor"] = true })
    f.npc_combat = object("NPCCombat", 10000, { ["/Script/DogwoodCombat.CombatComponentBase"] = true })
    function f.npc_combat:GetOwner() return f.npc end
    f.npc_config = object("NPCConfig", 11000, { ["/Script/DogwoodCombat.CombatConfig"] = true })
    f.npc_modes = { [19] = mode("NPCMode", 12000) }
    f.npc_config.CombatModes = map(f.npc_modes)
    function f.npc_combat:GetConfig() return f.npc_config end
    f.components = { f.combat, f.npc_combat }
    f.adapter = Adapter.new({
        get_identity = function() return f.identity end,
        is_in_game_thread = function() return f.on_thread end,
        get_player = function() return f.player end,
        get_player_controller = function() return f.controller end,
        find_all_of = function(class) assert(class == "CombatComponentBase"); f.scans = f.scans + 1; return f.components end,
        get_write_review = function() return f.review end,
    })
    function f.authorize()
        local context = f.adapter.resolve()
        f.review = { context_identity = context.identity, mode_set_identity = context.mode_set_identity,
            native_struct_write_verified = true, player_only_assets_verified = true, evidence_id = "offline-test-only" }
    end
    return f
end

test("read-only mode observation does not establish mutation eligibility", function()
    local f = fixture()
    local context = f.adapter.resolve()
    assert(context.player_modes_verified and not context.npc_isolation_verified)
    assert(context.nonplayer_component_count == 1 and context.write_review_error:find("review is missing", 1, true))
    assert(context.modes[1].read().attack == 1.2)
    rejects(function() context.modes[1].write_attack(1.5) end, "review is missing")
    assert(#f.modes[1].writes == 0)
end)

test("concrete adapter and controller modify only two fields and exactly restore", function()
    local f = fixture()
    f.authorize()
    local controller = Controller.new(f.adapter.resolve)
    assert(controller.apply(1.5).consistent)
    assert(math.abs(f.modes[1].data.AttackPlayrate - 1.8) < 0.00001)
    assert(f.npc_modes[19].data.AttackPlayrate == 1.2)
    assert(controller.restore().restored)
    for _, item in ipairs(f.modes) do
        assert(item.data.AttackPlayrate == 1.2 and item.data.StrongAttackPlayrate == 0.8)
        for _, field in ipairs(item.writes) do assert(field == "AttackPlayrate" or field == "StrongAttackPlayrate") end
    end
    assert(#f.npc_modes[19].writes == 0)
end)

test("exact build metadata and game-thread gates run before scans", function()
    local f = fixture()
    f.on_thread = false
    rejects(f.adapter.resolve, "game thread")
    f.on_thread = true
    f.identity.build_id = "25107392"
    rejects(f.adapter.resolve, "build or metadata differs")
    f.identity.build_id = "25129649"
    f.identity.metadata_sha256 = "stale"
    rejects(f.adapter.resolve, "build or metadata differs")
    assert(f.scans == 0)
end)

test("local controller mismatch and class defaults are rejected", function()
    local f = fixture()
    function f.controller:IsLocalController() return false end
    rejects(f.adapter.resolve, "controller and player disagree")
    function f.controller:IsLocalController() return true end
    f.player.name = "Default__Player"
    rejects(f.adapter.resolve, "class default")
end)

test("unmapped struct and changed struct address reject writes", function()
    local f = fixture()
    f.modes[1].methods.mapped = false
    rejects(f.adapter.resolve, "not a mapped native struct")
    f.modes[1].methods.mapped = true
    f.authorize()
    local context = f.adapter.resolve()
    f.modes[1].methods.address = 99999
    rejects(function() context.modes[1].write_attack(1.5) end, "struct identity changed")
    assert(#f.modes[1].writes == 0)
end)

test("NPC alias under any enum key blocks even with prior review", function()
    local f = fixture()
    f.authorize()
    f.npc_modes[19] = f.modes[2]
    rejects(f.adapter.resolve, "non-player actor shares a player combat mode")
    assert(#f.modes[2].writes == 0)
end)

test("shared config, player aliases, empty and missing NPC scans refuse", function()
    local f = fixture()
    f.npc_config = f.config
    rejects(f.adapter.resolve, "shares the player's combat config")
    f = fixture()
    f.modes[2] = f.modes[1]
    rejects(f.adapter.resolve, "alias the same asset")
    f = fixture()
    f.components = {}
    rejects(f.adapter.resolve, "scan is empty")
    f.components = { f.combat }
    rejects(f.adapter.resolve, "isolation witnesses")
end)

test("outside unrelated metric edit prevents further controller writes", function()
    local f = fixture()
    f.authorize()
    local controller = Controller.new(f.adapter.resolve)
    controller.apply(1.5)
    f.modes[1].data.ParryVsUnarmedMetric = 3
    local count = #f.modes[1].writes
    rejects(function() controller.restore() end, "changed outside")
    assert(#f.modes[1].writes == count)
end)

test("stale boot or player context cannot reuse an old review", function()
    local f = fixture()
    f.authorize()
    local context = f.adapter.resolve()
    f.identity.boot_id = "next-boot"
    rejects(function() context.modes[1].write_attack(1.5) end, "Player/world/config changed")
    assert(not f.adapter.resolve().npc_isolation_verified)
    assert(#f.modes[1].writes == 0)
end)

test("withdrawn review and non-native-range values cannot write", function()
    local f = fixture()
    f.authorize()
    local context = f.adapter.resolve()
    rejects(function() context.modes[1].write_attack(1e50) end, "Invalid native attack value")
    f.review = nil
    rejects(function() context.modes[1].write_strong_attack(1) end, "review is missing")
    assert(#f.modes[1].writes == 0)
end)

test("adapter class paths and scan class exist in fresh captured headers", function()
    local source_file = assert(io.open(arg[1] or "integration/uue4ss/feature-candidates/AttackSpeedNativeAdapter.lua", "r"))
    local source = source_file:read("*a")
    source_file:close()
    local headers = {}
    for module, class in source:gmatch('"/Script/([%w_]+)%.([%w_]+)"') do
        if not headers[module] then
            local file = assert(io.open("qa/discovery-current-build-20260906/fresh-metadata/CXXHeaderDump/" .. module .. ".hpp", "r"))
            headers[module] = file:read("*a")
            file:close()
        end
        assert(headers[module]:find("\nclass [UA]" .. class .. "[%s:]"), "No fresh reflected class: " .. module .. "." .. class)
    end
    local scanned_class = assert(source:match('find_all_of%("([%w_]+)"%)'))
    assert(headers.DogwoodCombat:find("\nclass U" .. scanned_class .. "[%s:]"), "Missing scan class in native metadata")
end)

print(string.format("%d attack native adapter test groups passed", passed))
