local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("imported_source_session_tests")
local root = assert(arg[1]) .. "/Mods/DawnwalkerImportedMenu/Scripts/"
local Facade = assert(loadfile(root .. "ImportedMenuFacade.lua"))()
local function timeFixture()
    local menu, queued, delayed, writes = Facade.New(), {}, {}, 0
    local valid = function() return true end
    local combat = { IsValid = valid, IsAlive = valid }
    local player = { IsValid = valid, CombatComponent = combat, GetFullName = function() return "Player" end, GetAddress = function() return 1 end }
    local time = { IsValid = valid, IsPhaseTransitionQueuedOrInProgress = function() return false end,
        GetCurrentDayTimeAsFloat = function() return 10 end, GetCurrentDay = function() return 1 end,
        GetFullName = function() return "Time" end, GetAddress = function() return 2 end,
        AddTimeSegments = function() writes = writes + 1; return false end }
    local state = { IsValid = valid, TimeSystem = time }
    local environment = setmetatable({
        require = function() return { GetPlayer = function() return player end, GetGameStateBase = function() return state end } end,
        FindFirstOf = function() return { IsValid = valid, GetFullName = function() return "Combat" end, GetIsInCombat = function() return false end } end,
        StaticFindObject = function() return { IsValid = valid, TimeSegmentsPer12H = 8, DaytimeStartHour = 8 } end,
        ExecuteInGameThread = function(callback) queued[#queued + 1] = callback end,
        ExecuteWithDelay = function(_, callback) delayed[#delayed + 1] = callback end,
        print = function() end,
    }, { __index = _G })
    local module = assert(loadfile(root .. "Source/TimeControl.lua", "t", environment))()
    module.Register(menu)
    menu.Session("one", true)
    local function advance(session, suffix)
        menu.Dispatch({ request_id = "ask" .. suffix, session_id = session, action = "invoke", section_id = "DWTimeControl", item_id = "advance" })
        menu.Dispatch({ request_id = "confirm" .. suffix, session_id = session, action = "confirm", confirmation_token = menu.Snapshot().confirmation.token, confirmed = true })
    end
    return menu, module, queued, delayed, advance, function() return writes end
end
do
    local menu, module, queue, _, advance, writes = timeFixture()
    advance("one", "1")
    assert(#queue == 1)
    queue[1] = nil -- Old session's callback was never executed.
    module.ResetSession(); menu.Session("two", true)
    advance("two", "2")
    assert(#queue == 1 and writes() == 0, "Cancelled preflight left Time permanently busy")
    print("PASS cancelled Time callback clears transient busy state")
end
do
    local menu, module, queue, delayed, advance, writes = timeFixture()
    advance("one", "1")
    table.remove(queue, 1)()
    assert(writes() == 1 and #delayed == 1)
    module.ResetSession(); menu.Session("two", true)
    advance("two", "2")
    assert(#queue == 0 and writes() == 1, "Unverified issued Time change was made retryable")
    print("PASS interrupted issued Time change retains restart lockout")
end
do
    local menu, queue, stamina = Facade.New(), {}, 40
    local valid = function() return true end
    local combat = { IsValid = valid, IsAlive = valid, SetStaminaPercent = function(_, amount) stamina = amount end }
    local controller = { IsValid = valid }
    local player = { IsValid = valid, CombatComponent = combat, Controller = controller, GetFullName = function() return "Player" end }
    controller.Pawn = player
    local environment = setmetatable({
        ExecuteInGameThread = function(callback) queue[#queue + 1] = callback end,
        ExecuteWithDelay = function() end,
        LoopInGameThreadWithDelay = function() return 1 end,
        CancelDelayedAction = function() end,
        io = { open = function(_, mode)
            if mode == "r" then return nil end
            return { write = function(self) return self end, close = function() end }
        end },
    }, { __index = _G })
    local module = assert(loadfile(root .. "Source/CombatControls.lua", "t", environment))()
    module.Init(menu, function() return player end, function() end, "mock/")
    menu.Session("one", true)
    -- The Rapid stamina refill checkbox now lives on the Player controls panel, so the
    -- logic is driven through the entry point CombatControls exposes for it.
    assert(type(module.SetStaminaRefill) == "function", "CombatControls must expose SetStaminaRefill")
    module.SetStaminaRefill(true)
    table.remove(queue, 1)()
    assert(stamina == 1, "stamina should have been refilled")
    assert(module.IsStaminaRefillOn() == true, "the module should report the refill as on")
    -- It must also mirror onto the Player controls checkbox it is presented by.
    assert(menu.Get("DWCorePlayer", "staminaRefill") == true, "Player controls checkbox was not synchronized")
    module.SetStaminaRefill(false)
    assert(module.IsStaminaRefillOn() == false, "the module should report the refill as off")
    assert(menu.Get("DWCorePlayer", "staminaRefill") == false, "Player controls checkbox was not cleared")
    assert(menu.Get("DWCombatControls", "god") == false and menu.Get("DWCombatControls", "cooldown") == false)
    print("PASS relocated stamina refill drives CombatControls and syncs Player controls")
end
do
    -- A respec refusal must land on the DWRespec status row. The buttons used to hand run()
    -- a bare section name, so the "Unavailable: ..." label silently failed and the stale
    -- preview text stayed on screen (D-13, 2026-09-18).
    local menu, queue = Facade.New(), {}
    local valid = function() return true end
    local combat = { IsValid = valid, IsAlive = valid }
    local controller = { IsValid = valid }
    local player = { IsValid = valid, CombatComponent = combat, Controller = controller, GetFullName = function() return "Player" end }
    controller.Pawn = player
    local environment = setmetatable({
        ExecuteInGameThread = function(callback) queue[#queue + 1] = callback end,
        ExecuteWithDelay = function() end,
        LoopInGameThreadWithDelay = function() return 1 end,
        CancelDelayedAction = function() end,
        io = { open = function(_, mode)
            if mode == "r" then return nil end
            return { write = function(self) return self end, close = function() end }
        end },
    }, { __index = _G })
    local module = assert(loadfile(root .. "Source/CombatControls.lua", "t", environment))()
    module.Init(menu, function() return player end, function() end, "mock/")
    menu.Session("one", true)
    menu.Dispatch({ request_id = "confirm-without-preview", session_id = "one", action = "invoke", section_id = "DWRespec", item_id = "confirm" })
    assert(#queue == 1, "confirm must schedule exactly one game-thread callback")
    table.remove(queue, 1)()
    local status
    for _, section in ipairs(menu.Snapshot().sections) do
        if section.id == "DWRespec" then
            for _, item in ipairs(section.items) do if item.id == "status" then status = item.label end end
        end
    end
    assert(status == "Unavailable: Preview your refund first.", "respec refusal was not published: " .. tostring(status))
    print("PASS respec refusals are published on the status row")
end
do
    -- TraitGrant indexes the perks on its own once the session's player exists (the
    -- desktop menu never fires the in-game OnOpen that used to do it), and reports a
    -- not-yet-ready session so the runtime retries instead of leaving the placeholder.
    local menu = Facade.New()
    local valid = function() return true end
    local playerReady = false
    local player = { IsValid = function() return playerReady end, CombatComponent = { IsValid = valid, IsAlive = valid } }
    local function trait(id, name, max) return { IsValid = valid, Skill_ID = { ToString = function() return id end }, LocalizedName = { ToString = function() return name end }, MaxTraitLevel = max } end
    local traits = { trait("CombatFocus_Explosion", "Blood Surge", 4), trait("Stamina_Endless", "Endless Effort", 3) }
    local dev = { IsValid = valid, GetFullName = function() return "CharacterDevelopmentSubsystem live" end, GetAddress = function() return 7 end,
        GetTraitPointAmount = function() return 3 end, GetSpentTraitPointAmount = function() return 5 end,
        GetAllTraits = function() return traits end, GetTraitLevel = function() return 0 end }
    local environment = setmetatable({
        FindAllOf = function(name) if name == "CharacterDevelopmentSubsystem" then return { dev } end return { { IsValid = valid, GetFullName = function() return "CombatSubsystem live" end, GetIsInCombat = function() return false end } } end,
        ExecuteInGameThread = function(callback) callback() end,
        ExecuteWithDelay = function() end,
        print = function() end,
    }, { __index = _G })
    local module = assert(loadfile(root .. "Source/TraitGrant.lua", "t", environment))()
    module.Init(menu, function() return player end, function() end)
    menu.Session("one", true)
    local function perkOptions()
        for _, section in ipairs(menu.Snapshot().sections) do
            if section.id == "DWTraitGrant" then for _, item in ipairs(section.items) do if item.id == "perk" then return item.options end end end
        end
    end
    assert(not pcall(module.SessionReady), "SessionReady must report a session whose player is not there yet")
    assert(#perkOptions() == 1 and perkOptions()[1].value == false, "placeholder stays until the index lands")
    playerReady = true
    module.SessionReady()
    local options = perkOptions()
    assert(#options == 2 and options[1].label:find("Blood Surge", 1, true) and options[1].value == "CombatFocus_Explosion", options[1] and options[1].label)
    print("PASS TraitGrant indexes perks automatically once the session's player exists")
end
