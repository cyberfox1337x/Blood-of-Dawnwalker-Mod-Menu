local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("blood_segment_control_tests")

-- Covers Scripts/BloodSegmentControl.lua. HealAndReplenishAllSegments returns
-- nothing, so success must come from GetBloodPermDamage actually falling.

local path = assert(arg[1], "Supply BloodSegmentControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function alwaysValid() return true end

local function menuDouble()
    local menu = { labels = {}, sections = {} }
    function menu.Register(section) menu.sections[section.id] = section end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set() end
    function menu.SetOptions() end
    function menu.Get() end
    function menu.click(itemId)
        for _, item in ipairs(menu.sections.DWBloodSegments.items) do
            if item.id == itemId and item.onClick then return item.onClick() end
        end
        error("no such control: " .. itemId)
    end
    return menu
end

local function fixture(overrides)
    overrides = overrides or {}
    local world = {
        permanentDamage = overrides.permanentDamage or 0,
        healCalls = 0,
        segmentsError = overrides.segmentsError or false,
    }
    local blood
    blood = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x2000 end,
        GetBloodPermDamage = function() return world.permanentDamage end,
        GetSegmentCount = function()
            if world.segmentsError then error("segment count unavailable") end
            return 5
        end,
        IsFatigued = function() return world.permanentDamage > 0 end,
        CanRecoverSegments = function() return true end,
        HealAndReplenishAllSegments = function()
            world.healCalls = world.healCalls + 1
            if overrides.onHeal then overrides.onHeal(world) end
        end,
    }
    local player = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x1 end,
        GetWorld = function() return { IsValid = alwaysValid, GetAddress = function() return 0x2 end } end,
        BloodBar = blood,
    }
    player.Controller = { IsValid = alwaysValid, GetAddress = function() return 0x3 end, Pawn = player }

    local environment = setmetatable({ print = function() end }, { __index = _G })
    local module = assert(loadfile(path, "t", environment))()
    local menu = menuDouble()
    module.Init(menu, { GetPlayer = function() return player end })
    return menu, world
end

test("reading reports permanent damage and segment figures", function()
    local menu = fixture({ permanentDamage = 40 })
    menu.click("refresh")
    assert(menu.labels.status:find("Permanent blood damage: 40", 1, true), menu.labels.status)
    assert(menu.labels.status:find("segments: 5", 1, true), menu.labels.status)
end)

test("an unreadable optional figure does not block the panel", function()
    local menu = fixture({ permanentDamage = 10, segmentsError = true })
    menu.click("refresh")
    assert(menu.labels.status:find("Permanent blood damage: 10", 1, true), menu.labels.status)
    assert(not menu.labels.status:find("segments:", 1, true), "unreadable figure must be omitted, not invented")
end)

test("repair is verified by permanent damage falling", function()
    local menu, world = fixture({
        permanentDamage = 40,
        onHeal = function(state) state.permanentDamage = 0 end,
    })
    menu.click("repair")
    assert(world.healCalls == 1, "expected exactly one heal call")
    assert(menu.labels.status:find("Verified", 1, true), menu.labels.status)
    assert(menu.labels.status:find("40 -> 0", 1, true), menu.labels.status)
end)

test("a heal that changes nothing is not reported as success", function()
    local menu, world = fixture({ permanentDamage = 40 })
    local ok = pcall(function() menu.click("repair") end)
    assert(not ok, "an unchanged readback must not be treated as success")
    assert(world.healCalls == 1)
    assert(menu.labels.status:find("did not reduce", 1, true), menu.labels.status)
    assert(not menu.labels.status:find("Verified", 1, true), "must never claim Verified without a change")
end)

test("no existing damage is reported plainly, not as a failure", function()
    local menu = fixture({ permanentDamage = 0 })
    menu.click("repair")
    assert(menu.labels.status:find("no permanent blood damage to repair", 1, true), menu.labels.status)
end)

test("the repair control confirms before acting", function()
    local menu = fixture({ permanentDamage = 10 })
    local repair
    for _, item in ipairs(menu.sections.DWBloodSegments.items) do
        if item.id == "repair" then repair = item end
    end
    assert(repair and repair.confirm and repair.confirm.title, "repair must carry a confirmation")
    assert(repair.confirm.message:find("cannot be put back", 1, true), "the confirmation must state it is one-way")
end)

print(count .. " Blood segment tests passed")
