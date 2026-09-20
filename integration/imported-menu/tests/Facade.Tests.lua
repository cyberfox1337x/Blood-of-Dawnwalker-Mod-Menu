local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("imported_menu_facade_tests")
local root = assert(arg[1], "Supply imported-menu root")
local scriptRoot = root .. "/Mods/DawnwalkerImportedMenu/Scripts/"
local Facade = assert(loadfile(scriptRoot .. "ImportedMenuFacade.lua"))()
local Loader = assert(loadfile(scriptRoot .. "ImportedSourceLoader.lua"))()
local total = 0
local function test(name, callback)
    local ok, failure = pcall(callback)
    assert(ok, name .. ": " .. tostring(failure))
    total = total + 1; print("PASS " .. name)
end
local function fixture()
    local menu, mutations = Facade.New(), 0
    menu.Register({ id = "test", title = "Test", tab = "Player", items = {
        { id = "enabled", type = "checkbox", default = true, onChange = function() mutations = mutations + 1 end },
        { id = "amount", type = "number", min = 1, max = 10, integer = true, default = 2 },
        { id = "choice", type = "dropdown", options = { "A", "B" }, default = "A" },
        { id = "status", type = "label", label = "Ready" },
        { type = "row", items = {{ id = "destroy", type = "button", confirm = { title = "Confirm", message = "Changes state" }, onClick = function() mutations = mutations + 1 end }} },
    }})
    menu.Session("session-a", true)
    return menu, function() return mutations end
end
local function command(action, item, value, valueType, id)
    return { request_id = id or "request-1", session_id = "session-a", action = action,
        section_id = "test", item_id = item, value = value, value_type = valueType }
end

test("bounded registration accommodates expanded runtime without allowing duplicate sections", function()
    local menu = Facade.New()
    for index = 1, 96 do
        menu.Register({ id = "section-" .. index, title = "Section", items = {} })
    end
    assert(#menu.Snapshot().sections == 96)
    assert(not pcall(menu.Register, { id = "section-97", title = "Excess", items = {} }))
    assert(not pcall(menu.Register, { id = "section-1", title = "Duplicate", items = {} }))
    local smaller = Facade.New()
    smaller.Register({ id = "unique", items = {} })
    assert(not pcall(smaller.Register, { id = "unique", items = {} }), "Duplicate rejected independently of section limit")
end)
test("defaults off and programmatic Set never invokes gameplay", function()
    local menu, count = fixture()
    assert(menu.Get("test", "enabled") == false)
    menu.Set("test", "enabled", true)
    assert(count() == 0)
end)

test("text inputs accept bounded names and reject control bytes or excessive length", function()
    local menu = Facade.New()
    menu.Register({ id = "test", title = "Text", items = { { id = "name", type = "input", default = "" } } })
    menu.Session("session-a", true)
    menu.Dispatch(command("set", "name", "Village gate", "string", "valid-name"))
    assert(menu.Get("test", "name") == "Village gate")
    for index, invalid in ipairs({ "bad\nname", "bad\rname", "bad\0name", string.rep("x", 513) }) do
        assert(not pcall(menu.Dispatch, command("set", "name", invalid, "string", "invalid-name-" .. index)))
        assert(menu.Get("test", "name") == "Village gate")
    end
end)
test("hidden internal values are permissive but never externally writable", function()
    local menu = fixture()
    menu.Set("test", "god", false)
    menu.Set("test", "cooldown", false)
    assert(menu.Get("test", "god") == false and menu.Get("test", "missing") == nil)
    assert(not pcall(menu.Dispatch, command("set", "god", true, "boolean")))
    assert(not Facade.Encode(menu.Snapshot()):find('"id":"god"', 1, true))
end)
test("checkboxes without gameplay callbacks publish read-only and reject external writes", function()
    local menu = Facade.New()
    menu.Register({ id = "status", title = "Status", items = {
        { id = "owned", type = "checkbox", label = "Override active", value = true },
    } })
    menu.Session("session-a", true)
    menu.Set("status", "owned", true)
    local item = menu.Snapshot().sections[1].items[1]
    assert(item.readOnly == true, "status checkbox must publish as read-only")
    local request = command("set", "owned", false, "boolean", "write-status")
    request.section_id = "status"
    assert(not pcall(menu.Dispatch, request), "read-only status must refuse external writes")
    assert(menu.Get("status", "owned") == true, "refused write changed status")
end)
test("numeric, option and registered action validation", function()
    local menu = fixture()
    assert(not pcall(menu.Dispatch, command("set", "amount", 99, "number")))
    assert(not pcall(menu.Dispatch, command("set", "amount", 1.5, "number")))
    assert(not pcall(menu.Dispatch, command("set", "choice", "C", "string")))
    assert(not pcall(menu.Dispatch, command("invoke", "not-registered")))
    menu.Dispatch(command("set", "amount", 3, "number"))
    assert(menu.Get("test", "amount") == 3)
    assert(menu.Snapshot().operation.status == "completed")
end)
test("one-use confirmation freezes fields and invokes only on confirm", function()
    local menu, count = fixture()
    menu.Dispatch(command("invoke", "destroy"))
    assert(count() == 0)
    assert(menu.Snapshot().operation.status == "awaiting-confirmation")
    assert(not pcall(menu.Dispatch, command("set", "amount", 4, "number")))
    local confirmation = { request_id = "confirm-1", session_id = "session-a", action = "confirm",
        confirmation_token = menu.Snapshot().confirmation.token, confirmed = true }
    menu.Dispatch(confirmation)
    assert(count() == 1 and menu.Snapshot().operation.id == "confirm-1")
    assert(not pcall(menu.Dispatch, confirmation))
end)
test("cancel and session replacement never invoke confirmation mutation", function()
    local menu, count = fixture()
    menu.Dispatch(command("invoke", "destroy"))
    menu.Dispatch({ request_id = "cancel", session_id = "session-a", action = "confirm",
        confirmation_token = menu.Snapshot().confirmation.token, confirmed = false })
    assert(count() == 0)
    menu.Dispatch(command("invoke", "destroy", nil, nil, "request-2"))
    local token = menu.Snapshot().confirmation.token
    menu.Session("session-b", true)
    assert(not pcall(menu.Dispatch, { request_id = "stale", session_id = "session-a", action = "confirm", confirmation_token = token, confirmed = true }))
    assert(count() == 0)
end)
test("async work remains running until drained and native error labels stay failed", function()
    local menu = fixture()
    local owner
    menu.OnOpen(function() owner = menu.Context(); menu.BeginTask(owner) end)
    menu.Dispatch(command("refresh"))
    assert(menu.Snapshot().operation.status == "running")
    menu.Run(function() menu.SetLabel("test", "status", "Unavailable: native receiver") end, owner)
    assert(menu.Snapshot().operation.status == "running")
    assert(not pcall(menu.Dispatch, { request_id = "close", session_id = "session-a", action = "close" }))
    assert(not pcall(menu.Dispatch, command("set", "amount", 4, "number", "next")))
    menu.EndTask(owner)
    assert(menu.Snapshot().operation.status == "failed")
end)
test("unowned finite work also blocks close and disabled writable fields reject", function()
    local menu = fixture()
    menu.BeginTask(nil)
    assert(not pcall(menu.Dispatch, { request_id = "close", session_id = "session-a", action = "close" }))
    menu.EndTask(nil)
    menu.Register({ id = "disabled", items = {{id="amount",type="number",min=1,max=10,enabled=false}} })
    local request = command("set", "amount", 3, "number")
    request.section_id = "disabled"
    assert(not pcall(menu.Dispatch, request))
end)
test("a clean quit is published as shutdown=quit and never by default", function()
    local menu = fixture()
    assert(menu.Snapshot().shutdown == nil and not Facade.Encode(menu.Snapshot()):find('"shutdown"', 1, true))
    assert(not pcall(menu.Shutdown, ""), "an empty reason must be refused")
    assert(not pcall(menu.Shutdown, 4), "a non-string reason must be refused")
    local before = menu.Snapshot().revision
    menu.Shutdown("quit")
    assert(menu.Snapshot().shutdown == "quit" and menu.Snapshot().revision > before, "shutdown must be published as a change")
    assert(Facade.Encode(menu.Snapshot()):find('"shutdown":"quit"', 1, true))
end)
test("snapshot strips callbacks and preserves empty arrays", function()
    local menu = fixture()
    local json = Facade.Encode(menu.Snapshot())
    assert(not json:find("onClick", 1, true))
    assert(json:find('"messages":[]', 1, true))
    assert(not pcall(Facade.Encode, { object = function() end }))
end)
test("programmatic field change invalidates confirmation but allows cancellation", function()
    local menu, count = fixture()
    menu.Dispatch(command("invoke", "destroy"))
    local token = menu.Snapshot().confirmation.token
    menu.Set("test", "amount", 9)
    local answer = { request_id = "answer", session_id = "session-a", action = "confirm", confirmation_token = token, confirmed = true }
    assert(not pcall(menu.Dispatch, answer))
    answer.confirmed = false
    menu.Dispatch(answer)
    assert(count() == 0)
end)
test("close waits for scheduled OFF callbacks", function()
    local menu = Facade.New()
    local stoppedOwner
    menu.Register({ id = "toggle", items = {{ id = "on", type = "checkbox", onChange = function(value)
        if not value then stoppedOwner = menu.Context(); menu.BeginTask(stoppedOwner) end
        menu.Set("toggle", "on", value)
    end }} })
    menu.Session("session-a", true)
    menu.Set("toggle", "on", true)
    menu.Dispatch({ request_id = "close", session_id = "session-a", action = "close" })
    assert(menu.Snapshot().operation.status == "running" and stoppedOwner == "close")
    menu.EndTask(stoppedOwner)
    assert(menu.Snapshot().operation.status == "completed")
end)

test("actual adapted source registers catalog without gameplay or overlay", function()
    local menu = Facade.New()
    local delayed, hooks = {}, 0
    local injected = setmetatable({
        UEHelpers = { GetPlayer = function() return nil end },
        print = function() end,
        StaticFindObject = function() return nil end,
        FindFirstOf = function() return nil end,
        FindAllOf = function() return {} end,
        RegisterHook = function(path)
            assert(path == "/Script/DogwoodInventory.InventoryBlueprintFunctionLibrary:GetItemHandle")
            hooks = hooks + 1; return 1, 2
        end,
        RegisterKeyBind = function() error("Unexpected hotkey") end,
        ExecuteWithDelay = function(_, callback) delayed[#delayed + 1] = callback end,
        ExecuteInGameThread = function(callback) delayed[#delayed + 1] = callback end,
        io = { open = function(_, mode)
            if mode == "r" then return nil end
            return { write = function(self) return self end, close = function() return true end }
        end },
    }, { __index = _G })
    Loader.Load(scriptRoot .. "Source/", menu, injected)
    for _, name in ipairs({ "StoryTimerControl", "CorePlayerControl", "WorldControl", "QuestReadback", "DifficultyControl", "SavedLocationControl", "PlayerLevelControl", "StorySettingsControl" }) do
        local module = assert(loadfile(scriptRoot .. name .. ".lua", "t", injected))()
        module.Init(menu, injected.UEHelpers)
    end
    local snapshot = menu.Snapshot()
    -- Adjust deliberately when a section is added or removed. Last change: the Stamina
    -- panel was retired, its Rapid stamina refill checkbox moving to Player controls.
    assert(#snapshot.sections == 28, "Incomplete stable source and adapter catalog")
    for _,section in ipairs(snapshot.sections) do assert(section.id~="DWFastTravel" and section.id~="DWMapArtworkQA", "Unverified map adapter exposed") end
    assert(hooks == 1, "Native item hook registration was lost")
    for _, section in ipairs(snapshot.sections) do assert(section.id ~= "DWGodMode", "Hidden unsupported God Mode exposed") end
    local encoded = Facade.Encode(snapshot)
    assert(#encoded < 1048576)
    if arg[2] then local output = assert(io.open(arg[2], "wb")); assert(output:write(encoded)); output:close() end
    print("Catalog sections=" .. #snapshot.sections .. " bytes=" .. #encoded)
end)
print("PASSED " .. total .. " imported facade tests")
