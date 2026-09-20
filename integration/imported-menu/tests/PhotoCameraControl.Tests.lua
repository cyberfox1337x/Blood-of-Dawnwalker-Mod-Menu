local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("photo_camera_control_tests")

-- Covers Scripts/PhotoCameraControl.lua. Enter and exit both return nothing, so
-- IsInCameraMode is the only acceptable proof either way.

local path = assert(arg[1], "Supply PhotoCameraControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function alwaysValid() return true end

local function menuDouble()
    local menu = { labels = {}, values = {}, sections = {} }
    function menu.Register(section) menu.sections[section.id] = section end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set(_, itemId, value) menu.values[itemId] = value end
    function menu.SetOptions() end
    function menu.Get(_, itemId) return menu.values[itemId] end
    function menu.click(itemId)
        for _, item in ipairs(menu.sections.DWPhotoCamera.items) do
            if item.id == itemId and item.onClick then return item.onClick() end
        end
        error("no such control: " .. itemId)
    end
    function menu.item(itemId)
        for _, item in ipairs(menu.sections.DWPhotoCamera.items) do
            if item.id == itemId then return item end
        end
        error("no such control: " .. itemId)
    end
    return menu
end

local function fixture(overrides)
    overrides = overrides or {}
    local world = { mode = overrides.mode or false, enters = 0, exits = 0,
        obeys = overrides.obeys ~= false, missing = overrides.missing or false }
    local camera = {
        IsValid = alwaysValid,
        GetAddress = function() return 0x4000 end,
        GetFullName = function() return "PhotoCameraActor /Game/World.PhotoCamera" end,
        IsA = function(_, class) return class == "/Script/DogwoodSystem.PhotoCameraActor" end,
        IsInCameraMode = function() return world.mode end,
        EnterPhotoCamera = function() world.enters = world.enters + 1; if world.obeys then world.mode = true end end,
        ExitPhotoCamera = function() world.exits = world.exits + 1; if world.obeys then world.mode = false end end,
    }
    local player = { IsValid = alwaysValid, GetAddress = function() return 0x1 end }
    local environment = setmetatable({
        FindFirstOf = function(name)
            if name == "PhotoCameraActor" and not world.missing then return camera end
            return nil
        end,
        print = function() end,
    }, { __index = _G })
    local module = assert(loadfile(path, "t", environment))()
    local menu = menuDouble()
    module.Init(menu, { GetPlayer = function() return player end })
    return menu, world, module
end

test("reading reports the current camera mode", function()
    local menu = fixture({ mode = true })
    menu.click("refresh")
    assert(menu.labels.status:find("active", 1, true), menu.labels.status)
    assert(menu.values.active == true)
end)

test("a missing photo camera actor refuses instead of guessing", function()
    local menu, world = fixture({ missing = true })
    assert(menu.item("enter").enabled == false and menu.item("exit").enabled == false,
        "camera actions must start unavailable until the actor is proved")
    local ok = pcall(function() menu.click("refresh") end)
    assert(not ok, "a missing actor must fail")
    assert(world.enters == 0)
    assert(menu.item("enter").enabled == false and menu.item("exit").enabled == false,
        "missing actor left camera actions enabled")
    assert(menu.labels.status:find("Unavailable in this level", 1, true), menu.labels.status)
end)

test("automatic session readback treats an absent level camera as unavailable", function()
    local menu, world, module = fixture({ missing = true })
    local ok, failure = pcall(module.SessionReady)
    assert(ok, "expected level unavailability must not become a console failure: " .. tostring(failure))
    assert(world.enters == 0 and world.exits == 0, "automatic readback must remain read-only")
    assert(menu.item("enter").enabled == false and menu.item("exit").enabled == false,
        "camera actions must remain unavailable")
    assert(menu.labels.status:find("Unavailable in this level", 1, true), menu.labels.status)
end)

test("a successful read enables the reversible camera actions", function()
    local menu = fixture({ mode = false })
    assert(menu.item("enter").enabled == false and menu.item("exit").enabled == false)
    menu.click("refresh")
    assert(menu.item("enter").enabled == true and menu.item("exit").enabled == true)
end)

test("entering is verified by the mode reading back true", function()
    local menu, world = fixture({ mode = false })
    menu.click("enter")
    assert(world.enters == 1 and world.mode == true)
    assert(menu.labels.status:find("Verified: photo camera entered", 1, true), menu.labels.status)
end)

test("exiting is verified by the mode reading back false", function()
    local menu, world = fixture({ mode = true })
    menu.click("exit")
    assert(world.exits == 1 and world.mode == false)
    assert(menu.labels.status:find("Verified: photo camera exited", 1, true), menu.labels.status)
end)

test("a refused enter is reported, not claimed as success", function()
    local menu, world = fixture({ mode = false, obeys = false })
    local ok = pcall(function() menu.click("enter") end)
    assert(not ok, "a readback mismatch must not pass")
    assert(world.enters == 1)
    assert(menu.labels.status:find("refused", 1, true), menu.labels.status)
    assert(not menu.labels.status:find("Verified", 1, true))
end)

test("entering when already active writes nothing", function()
    local menu, world = fixture({ mode = true })
    menu.click("enter")
    assert(world.enters == 0, "must not re-enter an already active camera")
    assert(menu.labels.status:find("already active", 1, true), menu.labels.status)
end)

test("both an enter and an exit control are offered", function()
    local menu = fixture()
    local ids = {}
    for _, item in ipairs(menu.sections.DWPhotoCamera.items) do
        if item.id then ids[item.id] = true end
    end
    assert(ids.enter and ids.exit, "a reversible pair must expose both directions")
end)

print(count .. " Photo camera tests passed")
