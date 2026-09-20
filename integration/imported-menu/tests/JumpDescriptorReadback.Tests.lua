local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("jump_descriptor_readback_tests")
local probe, calls = {}, 0
package.loaded.DawnwalkerSuperJumpDescriptorReadOnlyProbe = probe
local module = assert(loadfile(assert(arg[1])))()
local controller, player = {}, {}
player.Controller = controller
local helpers = { GetPlayer = function() calls = calls + 1; return player end }
StaticFindObject = function() return nil end
local function contains(text, expected) assert(text:find(expected, 1, true), text) end
local count = 0
local function test(name, callback)
    local ok, cause = pcall(callback)
    assert(ok, name .. ": " .. tostring(cause))
    count = count + 1; print("PASS " .. name)
end
test("exact probe dependencies and detailed failed stage retained", function()
    probe.run = function(deps)
        assert(deps.static_find_object == StaticFindObject)
        assert(deps.get_player() == player and deps.get_player_controller() == controller)
        return { ok = false, message = "Exact effect CDO is unavailable." }
    end
    probe.format_result = function(result) assert(result.ok == false); return "passed=0;stage=descriptor" end
    local text = module.Read(helpers)
    contains(text, "passed=0;stage=descriptor"); contains(text, "Exact effect CDO is unavailable.")
end)
test("successful read-only evidence retained", function()
    probe.run = function() return { ok = true, message = "No mutation API was invoked." } end
    probe.format_result = function(result) assert(result.ok); return "passed=1;mutation_authorized=0" end
    contains(module.Read(helpers), "passed=1;mutation_authorized=0")
end)
test("unexpected ABI failure becomes actionable read-only failure", function()
    probe.run = function() error("reflection ABI changed") end
    local text = module.Read(helpers)
    contains(text, "passed=0"); contains(text, "reflection ABI changed")
end)
test("refresh is explicit and executes only in scheduled game-thread callback", function()
    local section, scheduled, output
    calls = 0
    local menu = { Register = function(value) section = value end, SetLabel = function(id, item, text)
        assert(id == "DWJumpReadback" and item == "status"); output = text
    end }
    ExecuteInGameThread = function(callback) scheduled = callback end
    probe.run = function(deps) deps.get_player(); return { ok = false, message = "read complete" } end
    probe.format_result = function() return "passed=0;mutation_authorized=0" end
    module.Init(menu, helpers)
    assert(calls == 0 and scheduled == nil and #section.items == 2)
    section.items[1].onClick()
    assert(calls == 0 and output == nil)
    scheduled(); assert(calls == 1); contains(output, "read complete")
    ExecuteInGameThread = function() error("scheduler unavailable") end
    section.items[1].onClick(); contains(output, "scheduler unavailable")
end)
local function borrow_fixture()
    local function object(id) return { IsValid = function() return true end, GetAddress = function() return id end } end
    local p, c, w, asc, attrs, attrClass = object(1), object(2), object(3), object(4), object(5), object(6)
    local effect, cdo, movement, library, libraryClass = object(7), object(8), object(10), object(11), object(12)
    local descriptor = { GetStructAddress = function() return 9 end, AttributeOwner = attrClass }
    p.Controller, p.AbilitySystemComponent, p.MovementAttributeSet, p.CharacterMovement = c, asc, attrs, movement
    p.GetWorld, p.GetRebelCharacterMovement = function() return w end, function() return movement end
    movement.GetOwner = function() return p end
    attrs.JumpVelocity = { BaseValue = 700, CurrentValue = 700 }
    effect.GetCDO, libraryClass.GetCDO = function() return cdo end, function() return library end
    library.IsA = function(_, path) return path == "/Script/DogwoodCombat.CombatBlueprintFunctionLibrary" end
    library.SetAttributeValue = function() error("Mutation must never be invoked") end
    cdo.Modifiers = { { Attribute = descriptor } }
    local evidence = { ok = true, identity = { player_address = "1", controller_address = "2", world_address = "3",
        asc_address = "4", attribute_set_address = "5", attribute_set_class_address = "6" },
        source = { class_path = "/Game/ValidatedEffect", class_address = "7", cdo_address = "8" },
        descriptor = { struct_address = "9" }, readback = { base_value = 700, current_value = 700 } }
    probe.run = function() return evidence end
    StaticFindObject = function(path)
        if path == "/Game/ValidatedEffect" then return effect end
        if path == "/Script/DogwoodCombat.Default__CombatBlueprintFunctionLibrary" then return library end
        if path == "/Script/DogwoodCombat.CombatBlueprintFunctionLibrary" then return libraryClass end
        return object(13)
    end
    return { GetPlayer = function() return p end }, descriptor, attrs, movement, evidence
end
test("borrow returns validated references without writing", function()
    local h = borrow_fixture()
    local borrowed = module.Borrow(h)
    assert(borrowed.validated and borrowed.base == 700 and borrowed.current == 700)
    assert(borrowed.player == h.GetPlayer() and borrowed.library:GetAddress() == 11)
end)
test("borrow rejects unsuccessful original probe", function()
    local h, _, _, _, evidence = borrow_fixture(); evidence.ok = false
    assert(not pcall(module.Borrow, h))
end)
test("borrow rejects stale descriptor and changed attribute readback", function()
    local h, descriptor = borrow_fixture(); descriptor.GetStructAddress = function() return 99 end
    assert(not pcall(module.Borrow, h))
    local h2, _, attributes = borrow_fixture(); attributes.JumpVelocity.CurrentValue = 701
    assert(not pcall(module.Borrow, h2))
end)
test("borrow rejects foreign movement owner and extra modifiers", function()
    local h, _, _, movement = borrow_fixture(); movement.GetOwner = function() return movement end
    assert(not pcall(module.Borrow, h))
    local h2 = borrow_fixture()
    StaticFindObject("/Game/ValidatedEffect"):GetCDO().Modifiers[2] = {}
    assert(not pcall(module.Borrow, h2))
end)
print(count .. " jump descriptor adapter tests passed")
