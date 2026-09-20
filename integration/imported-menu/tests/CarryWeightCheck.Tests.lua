local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("carry_weight_check_tests")

-- Covers Scripts/CarryWeightCheck.lua.
--
-- Two capabilities live in this section: the reviewed read-only probe, and the Zero Weight
-- switch served by CarryCapacityEffectPilot.lua. The tests below pin what separates them -
-- the probe button never touches the capability, the switch inspects before an enable but
-- never before a disable, and a refusal reports the pilot's own view of whether an effect is
-- applied rather than the value that was asked for.
--
-- The suite still pins the withdrawal-era property as its default: with no capacity pilot
-- handed in, the section must offer no control that can change a capacity value at all.

local path = assert(arg[1], "Supply CarryWeightCheck.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function menuDouble()
    local menu = { labels = {}, values = {}, sections = {} }
    function menu.Register(section) menu.sections[section.id] = section end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set(_, itemId, value) menu.values[itemId] = value end
    function menu.SetOptions() end
    function menu.Get(_, itemId) return menu.values[itemId] end
    local function find(itemId)
        for _, item in ipairs(menu.sections.DWWeight.items) do
            if item.id == itemId then return item end
        end
        error("no such control: " .. itemId)
    end
    menu.item = find
    function menu.click(itemId)
        local item = find(itemId)
        if item.onClick then return item.onClick() end
        error("no click handler: " .. itemId)
    end
    function menu.toggle(itemId, value)
        local item = find(itemId)
        assert(item.onChange, "no change handler: " .. itemId)
        return item.onChange(value)
    end
    return menu
end

local PASSING = {
    ok = true,
    mutation_authorized = false,
    stage = "read-only-complete",
    descriptor = {
        source_class = "/Game/_Dawnwalker/Player/CharacterDevelopment/Traits/GameplayEffects/GE_Trait_Shared_StrongBack_Level_1.GE_Trait_Shared_StrongBack_Level_1_C",
        attribute_name = "CarryWeightCapacityModifier",
        attribute_owner = "/Script/DogwoodStats.CharDevAttributeSet",
        struct_address = "0x1c39faf1580",
    },
    -- The check reports the probe's parameter-contract verdict verbatim. This UE4SS
    -- build does not expose UStruct:ForEachProperty, so the probe reports the walk as
    -- unavailable rather than claiming it read the live function.
    setter_signature = { metadata_walk = "unavailable" },
    snapshot = {
        attribute_base_value = 60,
        attribute_current_value = 60,
        current_weight = 87.5,
        effective_weight_limit = 180,
        weight_exceeded = false,
        can_exceed_weight_limit = false,
    },
}

-- A stand-in for CarryCapacityEffectPilot.lua that records the order of the calls the
-- section makes, so "inspect before enable, never before disable" is observable.
local function fakeCapacity(overrides)
    overrides = overrides or {}
    local calls = {}
    -- `owned` is a function on the real pilot: it reports whether an effect is still
    -- applied, which is the value the section shows after a refusal.
    local pilot = { applied = overrides.owned == true }
    pilot.inspect = function()
        calls[#calls + 1] = "inspect"
        if overrides.inspectFails then error("the session could not be proven") end
    end
    pilot.set = function(value)
        calls[#calls + 1] = "set:" .. tostring(value)
        if overrides.setFails then error(value and "the write was refused" or "the removal was refused") end
        pilot.applied = value
        return value and "ON: effective weight limit 0 (no limit) verified." or "OFF: exact private effect removed."
    end
    pilot.owned = function() return pilot.applied end
    if overrides.noSet then pilot.set = nil end
    if overrides.noInspect then pilot.inspect = nil end
    if overrides.noOwned then pilot.owned = nil end
    return pilot, calls
end

local function fixture(verdict, overrides, capacity)
    overrides = overrides or {}
    local seen = {}
    local probe = {
        run = function(deps)
            seen.deps = deps
            seen.calls = (seen.calls or 0) + 1
            return verdict
        end,
    }
    local player = { IsValid = function() return true end }
    local environment = setmetatable({
        EngineTickAvailable = overrides.engineTick ~= false,
        ExecuteInGameThread = function(callback) return callback() end,
        StaticFindObject = function(inner) seen.staticFind = inner; return nil end,
        PropertyTypes = { StructProperty = "StructProperty" },
        print = function() end,
    }, { __index = _G })
    local module = assert(loadfile(path, "t", environment))()
    local menu = menuDouble()
    module.Init(menu, { GetPlayer = function() return player end }, probe, capacity)
    return menu, seen, player
end

test("with no pilot the section offers the check and nothing that can change state", function()
    local menu = fixture(PASSING)
    local section = menu.sections.DWWeight
    assert(section ~= nil, "the section must register as DWWeight")
    assert(section.tab == "♡ Player", "the section belongs with the player")
    local ids = {}
    for _, item in ipairs(section.items) do
        ids[item.id or "-"] = item.type
        assert(item.type ~= "checkbox", "no capacity switch may be offered without a pilot")
        assert(item.type ~= "button" or item.id == "probe", "the check is the only action")
    end
    assert(ids.status == "label", "the section must publish a status label")
    assert(ids.probe == "button", "the section must offer the read-only check")
    assert(ids.zeroWeight == nil, "the switch must not exist without a capability")
end)

test("with a pilot the section offers exactly one switch and the check", function()
    local pilot = fakeCapacity()
    local menu = fixture(PASSING, nil, pilot)
    local section = menu.sections.DWWeight
    local ids, changes = {}, 0
    for _, item in ipairs(section.items) do
        ids[item.id or "-"] = item.type
        if item.type == "checkbox" then changes = changes + 1 end
        if item.type == "button" then assert(item.id == "probe", "the check is the only action") end
    end
    assert(ids.zeroWeight == "checkbox", "the Zero Weight switch must be offered")
    assert(ids.probe == "button", "the read-only check stays")
    assert(changes == 1, "exactly one control may change state")
    assert(menu.item("zeroWeight").default == false, "the switch must start OFF")
end)

test("a passing check reports the live state and names the route it does not use", function()
    local menu = fixture(PASSING)
    menu.click("probe")
    local status = menu.labels.status
    assert(status:find("Read%-only check passed"), status)
    assert(status:find("CarryWeightCapacityModifier", 1, true), status)
    assert(status:find("/Script/DogwoodStats.CharDevAttributeSet", 1, true), status)
    assert(status:find("base 60", 1, true), status)
    assert(status:find("load 87.5 of limit 180", 1, true), status)
    assert(status:find("Setter parameter metadata: unavailable.", 1, true), status)
    assert(status:find("private%-effect route"), status)
    assert(not status:find("not loaded", 1, true), "the withdrawn pilot is gone, so this claim must be gone too")
    -- The status is one sentence-complete string. A stray argument to string.format is
    -- silently ignored by Lua, so the end of the line is pinned here instead of trusted.
    assert(status:find("on the same session%.$"), "status must end on its last sentence: " .. status)
end)

test("the read-only check never touches the capability", function()
    local pilot, calls = fakeCapacity()
    local menu = fixture(PASSING, nil, pilot)
    menu.click("probe")
    assert(#calls == 0, "the check must not inspect or write")
    assert(menu.values.zeroWeight == nil, "the check must not move the switch")
end)

test("enabling inspects the session and then writes", function()
    local pilot, calls = fakeCapacity()
    local menu = fixture(PASSING, nil, pilot)
    menu.toggle("zeroWeight", true)
    assert(calls[1] == "inspect" and calls[2] == "set:true", table.concat(calls, ","))
    assert(#calls == 2, "an enable is exactly an inspection and a write")
    assert(menu.values.zeroWeight == true, "the switch follows the successful write")
    assert(menu.labels.status == "ON: effective weight limit 0 (no limit) verified.", menu.labels.status)
end)

test("disabling never inspects, so a changed session cannot block the OFF", function()
    local pilot, calls = fakeCapacity()
    local menu = fixture(PASSING, nil, pilot)
    menu.toggle("zeroWeight", true)
    for i = #calls, 1, -1 do calls[i] = nil end
    menu.toggle("zeroWeight", false)
    assert(#calls == 1 and calls[1] == "set:false", table.concat(calls, ","))
    assert(menu.values.zeroWeight == false)
end)

test("a refused enable reports the reason and shows OFF, not ON", function()
    local pilot, calls = fakeCapacity({ setFails = true })
    local menu = fixture(PASSING, nil, pilot)
    menu.toggle("zeroWeight", true)
    assert(menu.values.zeroWeight == false, "a refused enable must never show ON")
    assert(menu.labels.status:find("was refused", 1, true), menu.labels.status)
    assert(menu.labels.status:find("the write was refused", 1, true), menu.labels.status)
    assert(calls[1] == "inspect" and calls[2] == "set:true", table.concat(calls, ","))
end)

test("a refused disable shows ON because the effect is still applied", function()
    local pilot = fakeCapacity({ setFails = true, owned = true })
    local menu = fixture(PASSING, nil, pilot)
    menu.toggle("zeroWeight", false)
    assert(menu.values.zeroWeight == true, "a refused disable must show the effect is still applied")
    assert(menu.labels.status:find("the removal was refused", 1, true), menu.labels.status)
end)

test("a refused inspection never reaches a write", function()
    local pilot, calls = fakeCapacity({ inspectFails = true })
    local menu = fixture(PASSING, nil, pilot)
    menu.toggle("zeroWeight", true)
    assert(#calls == 1 and calls[1] == "inspect", table.concat(calls, ","))
    assert(menu.values.zeroWeight == false)
    assert(menu.labels.status:find("could not be proven", 1, true), menu.labels.status)
end)

test("the switch cannot be exercised while the game is unloaded", function()
    local pilot, calls = fakeCapacity()
    local menu = fixture(PASSING, { engineTick = false }, pilot)
    menu.toggle("zeroWeight", true)
    assert(#calls == 0, "nothing may be inspected or written with no game")
    assert(menu.values.zeroWeight == false)
    assert(menu.labels.status:find("game is not running", 1, true), menu.labels.status)
end)

test("a partial pilot adds no switch", function()
    for _, broken in ipairs({ { noSet = true }, { noInspect = true }, { noOwned = true } }) do
        local menu = fixture(PASSING, nil, fakeCapacity(broken))
        for _, item in ipairs(menu.sections.DWWeight.items) do
            assert(item.id ~= "zeroWeight", "an incomplete capability must not be offered")
        end
    end
end)

test("the probe receives the runtime's reflection and player resolver", function()
    local menu, seen = fixture(PASSING)
    menu.click("probe")
    assert(seen.calls == 1, "the probe must run exactly once per press")
    assert(type(seen.deps.static_find_object) == "function", "the probe needs StaticFindObject")
    assert(type(seen.deps.get_player) == "function", "the probe needs the live player getter")
    assert(seen.deps.property_types ~= nil, "the probe needs the UE4SS property types")
end)

test("a blocked verdict is reported as blocked, not as a pass", function()
    local menu = fixture({ ok = false, mutation_authorized = false, stage = "descriptor",
        message = "the setter parameter metadata could not be read" })
    menu.click("probe")
    local status = menu.labels.status
    assert(status:find("Blocked at descriptor", 1, true), status)
    assert(status:find("setter parameter metadata could not be read", 1, true), status)
    assert(status:find("Nothing was written", 1, true), status)
    assert(not status:find("passed", 1, true), "a blocked check must not read as a pass")
end)

test("the check refuses to run without a loaded game", function()
    local menu, seen = fixture(PASSING, { engineTick = false })
    menu.click("probe")
    assert(seen.calls == nil, "the probe must not run while the game is unloaded")
    assert(menu.labels.status:find("game is not running", 1, true), menu.labels.status)
end)

test("a probe that throws is reported instead of leaving the status pending", function()
    local broken = menuDouble()
    local environment = setmetatable({
        EngineTickAvailable = true,
        ExecuteInGameThread = function(callback) return callback() end,
        StaticFindObject = function() return nil end,
        PropertyTypes = {},
        print = function() end,
    }, { __index = _G })
    local module = assert(loadfile(path, "t", environment))()
    module.Init(broken, { GetPlayer = function() return nil end }, { run = function() error("probe exploded") end })
    broken.click("probe")
    assert(broken.labels.status:find("check failed", 1, true), broken.labels.status)
    assert(broken.labels.status:find("probe exploded", 1, true), broken.labels.status)
end)

print(count .. " CarryWeightCheck tests passed")
