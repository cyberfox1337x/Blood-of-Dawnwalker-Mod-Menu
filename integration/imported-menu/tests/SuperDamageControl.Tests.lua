local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("super_damage_control_tests")

-- Covers Scripts/SuperDamageControl.lua: the switch mirrors the pilot's own view of
-- ownership, the multiplier is validated and re-applied to a live effect, a refused enable
-- never shows ON, and a session change forgets the record without touching the game.
-- usage: lua SuperDamageControl.Tests.lua <path to Scripts/SuperDamageControl.lua>

local path = assert(arg[1], "Supply SuperDamageControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function fixture(options)
    options = options or {}
    local pilot = { calls = {}, ownedFlag = false, forgotten = 0 }
    function pilot.inspect() pilot.calls[#pilot.calls + 1] = "inspect"; if options.inspectFails then error("Controlled player unavailable", 0) end end
    function pilot.set(value, multiplier)
        pilot.calls[#pilot.calls + 1] = { set = value, multiplier = multiplier }
        if value and options.enableFails then error("Super-damage spec failed: callback absent; baseline restored", 0) end
        pilot.ownedFlag = value
        return value and string.format("ON: outgoing damage multiplied by %d verified.", multiplier) or "OFF: private effects removed."
    end
    function pilot.owned() return pilot.ownedFlag end
    function pilot.forget() pilot.forgotten = pilot.forgotten + 1; pilot.ownedFlag = false end
    local menu = { labels = {}, values = {}, sections = {} }
    function menu.Register(section) menu.sections[section.id] = section; for _, item in ipairs(section.items) do if item.type == "label" and item.id then menu.labels[item.id] = item.label end end end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set(_, itemId, value) menu.values[itemId] = value end
    local function control(itemId) for _, item in ipairs(menu.sections.DWSuperDamage.items) do if item.id == itemId then return item end end; error("no control " .. itemId) end
    -- Game-thread scheduling runs inline; the module only ever queues one callback per action.
    EngineTickAvailable = options.gameRunning ~= false
    ExecuteInGameThread = function(callback) callback() end
    local module = assert(loadfile(path))()
    local returned = module.Init(menu, {}, pilot, module.SUPER_DAMAGE)
    return { menu = menu, pilot = pilot, module = returned, toggle = function(value) control("enabled").onChange(value) end,
        multiplier = function(value) control("multiplier").onChange(value) end }
end

test("the default spec registers a switch, a 2..1000 multiplier and an idle status", function()
    local f = fixture()
    local items = {}
    for _, item in ipairs(f.menu.sections.DWSuperDamage.items) do if item.id then items[item.id] = item end end
    assert(items.enabled.type == "checkbox" and items.enabled.default == false)
    assert(items.multiplier.type == "number" and items.multiplier.min == 2 and items.multiplier.max == 1000 and items.multiplier.default == 100)
    assert(f.menu.labels.status:find("^Off%."), f.menu.labels.status)
end)

test("ON inspects first, applies the current multiplier and shows the pilot's verified status", function()
    local f = fixture(); f.toggle(true)
    assert(f.pilot.calls[1] == "inspect" and f.pilot.calls[2].set == true and f.pilot.calls[2].multiplier == 100)
    assert(f.menu.values.enabled == true and f.menu.labels.status:find("multiplied by 100", 1, true), f.menu.labels.status)
end)

test("OFF never inspects and mirrors the released ownership", function()
    local f = fixture(); f.toggle(true); f.toggle(false)
    local last = f.pilot.calls[#f.pilot.calls]
    assert(last.set == false and f.pilot.calls[#f.pilot.calls - 1].set == true, "OFF must not inspect before restoring")
    assert(f.menu.values.enabled == false and f.menu.labels.status:find("^OFF"), f.menu.labels.status)
end)

test("a refused enable leaves the switch OFF and names the refusal", function()
    local f = fixture({ enableFails = true })
    f.toggle(true) -- the refusal is published on the row, never raised at the caller
    assert(f.menu.values.enabled == false and f.menu.labels.status:find("Super damage was refused: ", 1, true), f.menu.labels.status)
end)

test("a refused inspection is reported the same way", function()
    local f = fixture({ inspectFails = true })
    f.toggle(true)
    assert(f.menu.values.enabled == false and f.menu.labels.status:find("Controlled player unavailable", 1, true), f.menu.labels.status)
    assert(#f.pilot.calls == 1, "set must not run when inspect refuses")
end)

test("the multiplier is validated and waits for the switch when nothing is owned", function()
    local f = fixture()
    for _, bad in ipairs({ 1, 1001, 2.5, "x" }) do assert(not pcall(f.multiplier, bad), tostring(bad)) end
    f.multiplier(250)
    assert(f.menu.labels.status:find("x250; turn the switch on", 1, true), f.menu.labels.status)
    assert(#f.pilot.calls == 0, "no pilot call while idle")
    f.toggle(true)
    assert(f.pilot.calls[2].multiplier == 250)
end)

test("changing the multiplier while ON re-applies through the pilot", function()
    local f = fixture(); f.toggle(true); f.multiplier(500)
    local last = f.pilot.calls[#f.pilot.calls]
    assert(last.set == true and last.multiplier == 500 and f.menu.labels.status:find("multiplied by 500", 1, true), f.menu.labels.status)
end)

test("without a running game the switch is refused and reset", function()
    local f = fixture({ gameRunning = false }); f.toggle(true)
    assert(f.menu.values.enabled == false and f.menu.labels.status:find("not running", 1, true), f.menu.labels.status)
    assert(#f.pilot.calls == 0)
end)

test("a session change forgets the record, resets the switch and never restores", function()
    local f = fixture(); f.toggle(true)
    f.module.ResetSession()
    assert(f.pilot.forgotten == 1 and f.menu.values.enabled == false and f.menu.labels.status:find("^Off%."), f.menu.labels.status)
    assert(f.pilot.calls[#f.pilot.calls].set == true, "ResetSession must not call set(false) on a dead session")
end)

test("the parry-window spec drives the same module with its own ids and bounds", function()
    local pilot = { owned = function() return false end, set = function() end, inspect = function() end, forget = function() end }
    local menu = { sections = {}, SetLabel = function() end, Set = function() end }
    function menu.Register(section) menu.sections[section.id] = section end
    local module = assert(loadfile(path))()
    module.Init(menu, {}, pilot, module.PARRY_WINDOW)
    local section = assert(menu.sections.DWParryWindow)
    local multiplier
    for _, item in ipairs(section.items) do if item.id == "multiplier" then multiplier = item end end
    assert(section.tab == "♡ Player" and multiplier.min == 2 and multiplier.max == 5 and multiplier.default == 2)
end)

print(string.format("%d/%d super-damage control tests passed", count, count))
