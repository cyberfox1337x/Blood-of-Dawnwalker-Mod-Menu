local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("dawnwalker_imported_menu_runtime")

local scriptPath = debug.getinfo(1, "S").source:gsub("^@", "")
local scriptDirectory = scriptPath:match("^(.*[/\\])")
assert(scriptDirectory, "Imported runtime directory unavailable")
local sourceDirectory = scriptDirectory .. "Source/"
local Facade = assert(loadfile(scriptDirectory .. "ImportedMenuFacade.lua"))()
local Loader = assert(loadfile(scriptDirectory .. "ImportedSourceLoader.lua"))()
local menu = Facade.New()
local PlayerResolver = assert(loadfile(scriptDirectory .. "PlayerResolver.lua"))()
local nativeHelpers = require("UEHelpers.UEHelpers")
-- UEHelpers.GetPlayer resolves through FindAllOf("PlayerController"), which walks every
-- UObject in the game - 60,931 of them on this build. The runtime tick called it 6.7
-- times a second, and the vampire form override called it from inside a hook the game
-- runs on every ability quickslot lookup, which is what made that toggle cost frames.
--
-- Wrapping it here rather than at each call site means one cache serves every module,
-- including the ones that captured helpers.GetPlayer as a bare function reference.
local playerResolver = PlayerResolver.New({ findAllOf = FindAllOf })
-- Kept before the replacement below, both to avoid recursing into ourselves and because
-- it is still the right answer when there is no player to cache.
local resolvePlayerUncached = nativeHelpers.GetPlayer
local function cachedGetPlayer()
    local cached = playerResolver.Player()
    if cached then return cached end
    -- Nothing cached means there is genuinely no player to hand back. Defer to UEHelpers
    -- so callers still receive its invalid-object sentinel, which is the contract every
    -- existing call site was written against, rather than nil.
    return resolvePlayerUncached()
end
-- Replaced on the module table rather than wrapped in a proxy because several Source
-- modules require UEHelpers directly and would otherwise keep paying for the full scan.
-- UE4SS gives every Lua mod its own state, so this replacement is private to this mod
-- and cannot reach FastTravelToAnyMarker or anything else installed alongside it.
nativeHelpers.GetPlayer = cachedGetPlayer
local helpers = nativeHelpers

local channel = (os.getenv("TEMP") or os.getenv("TMP") or ".") .. "/DawnwalkerImportedMenu/"
local boot = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
local generation, identity, sessionId = 0, nil, boot .. "-waiting"
local closing, unloaded, ending = false, false, false
local pollHandle, writeState
local tasks, timers, pinned, hooks, seenRequests = {}, {}, {}, {}, {}
local requestOrder = {}
local sourceModules
local adapterModules = {}
-- Shared with CorePlayerControl so it can present controls that other modules own.
local moduleRegistry = {}
local closeRequestId, closeVerified = nil, false
local function finishScheduled(record)
    if record.counted then record.counted=false;menu.EndTask(record.owner) end
end

local function playerIdentity()
    if ending or unloaded then return nil end
    local player = helpers.GetPlayer()
    if not player or not player:IsValid() then return nil end
    local world, controller = player:GetWorld(), player.Controller
    if not world or not world:IsValid() or not controller or not controller:IsValid() then return nil end
    local pawn, combat = controller.Pawn, player.CombatComponent
    if not pawn or not pawn:IsValid() or pawn:GetAddress() ~= player:GetAddress()
        or not combat or not combat:IsValid() or not combat:IsAlive() then return nil end
    return tostring(player:GetAddress()) .. ":" .. tostring(world:GetAddress()) .. ":" .. tostring(controller:GetAddress())
end
local function currentGeneration(expected)
    if expected ~= generation then return false end
    local ok, actual = pcall(playerIdentity)
    return ok and identity ~= nil and actual == identity
end
local function runOwned(callback, owner, expected)
    if ending or unloaded then return end
    if not closing and not currentGeneration(expected) then
        menu.Fail("Cancelled callback after player/session changed", owner); return
    end
    menu.Run(callback, owner)
end
local function schedule(callback, milliseconds, recurring, frames)
    assert(not ending and (not unloaded or closing), "Game shutdown has started; new native work refused")
    assert(type(callback) == "function", "Scheduled callback required")
    assert(type(milliseconds) == "number" and milliseconds >= 0 and milliseconds <= 60000, "Schedule delay outside bounds")
    if closing then
        assert(not recurring, "New recurring work refused during cleanup")
        menu.Run(callback, nil); return nil
    end
    local owner, expected = menu.Context(), generation
    local count = 0; for _ in pairs(tasks) do count = count + 1 end
    assert(count < 256, "Too many imported scheduled callbacks")
    local record = { owner = owner, recurring = recurring, live = true, counted = not recurring }
    tasks[record] = true
    if not recurring then menu.BeginTask(owner) end
    local wrapped
    wrapped = function()
        if not record.live then return end
        if not recurring then record.live = false; tasks[record] = nil; if record.handle then timers[record.handle] = nil end end
        runOwned(callback, owner, expected)
        if not recurring then finishScheduled(record); pinned[wrapped] = nil end
    end
    record.wrapped = wrapped
    pinned[wrapped] = true
    local ok, handle = pcall(function()
        if frames then return LoopInGameThreadAfterFrames(frames, wrapped) end
        if recurring then return LoopInGameThreadWithDelay(milliseconds, wrapped) end
        if milliseconds == 0 then return ExecuteInGameThread(wrapped, EGameThreadMethod.EngineTick) end
        -- Native game-thread timer avoids the async Lua-state hop. The pinned
        -- loader and installed settings both default delayed work to EngineTick.
        return ExecuteInGameThreadWithDelay(milliseconds, wrapped)
    end)
    if not ok then
        record.live = false; tasks[record] = nil; pinned[wrapped] = nil
        finishScheduled(record)
        error(handle)
    end
    record.handle = handle
    if handle then timers[handle] = record end
    return handle
end
local function cancel(handle)
    local record = timers[handle]
    if not record then return end
    local ok, failure = pcall(CancelDelayedAction, handle)
    if not ok then menu.Fail("Timer cancellation failed: " .. tostring(failure)) end
    record.live = false; tasks[record] = nil; timers[handle] = nil
    pinned[record.wrapped] = nil
    if record.delayed then pinned[record.delayed] = nil end
    finishScheduled(record)
end
local function invalidateScheduling(cancelNative)
    generation = generation + 1
    if cancelNative then for handle in pairs(timers) do cancel(handle) end end
    for record in pairs(tasks) do record.live=false;finishScheduled(record) end
    tasks={};timers={}
end
local function onEndPlay(_, reason)
    -- EEndPlayReason::Quit is 4. Do not resolve the actor or call UFunctions
    -- during teardown; only consume the supplied scalar argument.
    local ok, value = pcall(function() return reason:get() end)
    if not ok or value ~= 4 or ending then return end
    ending = true
    menu.Fail("Game shutdown started. Pending native work cancelled; OFF restoration during teardown is unverified.")
    invalidateScheduling(true)
    if pollHandle then
        local cancelled, failure = pcall(CancelDelayedAction, pollHandle)
        if not cancelled then menu.Fail("Shutdown poll cancellation failed: " .. tostring(failure)) end
        pollHandle = nil
    end
    identity = nil
    menu.Shutdown("quit")
    menu.Session(sessionId, false)
    if writeState then
        local saved, failure = pcall(writeState)
        if not saved then print("[DawnwalkerImportedMenu] Shutdown publication failed: " .. tostring(failure)) end
    end
end
RegisterEndPlayPreHook(onEndPlay)
local function cleanup()
    if ending then return end
    if menu.PendingCount()>0 then menu.Fail("Finite callbacks cancelled by player session change or unload") end
    closing = true
    menu.StopControls()
    closing = false
    invalidateScheduling(true)
    for _,module in pairs(sourceModules or {}) do
        if type(module)=="table" and type(module.ResetSession)=="function" then
            local ok,failure=pcall(module.ResetSession)
            if not ok then menu.Fail("Source session reset failed: "..tostring(failure)) end
        end
    end
    for _,module in ipairs(adapterModules or {}) do
        if type(module)=="table" and type(module.ResetSession)=="function" then
            local ok,failure=pcall(module.ResetSession)
            if not ok then menu.Fail("Adapter session reset failed: "..tostring(failure)) end
        end
    end
end

local injected = setmetatable({ UEHelpers = helpers }, { __index = _G })
injected.ExecuteInGameThread = function(callback) return schedule(callback, 0, false) end
injected.ExecuteWithDelay = function(milliseconds, callback) return schedule(callback, milliseconds, false) end
injected.LoopInGameThreadWithDelay = function(milliseconds, callback) return schedule(callback, milliseconds, true) end
injected.LoopInGameThreadAfterFrames = function(frames, callback)
    assert(frames == 1, "Only one-frame input scheduling is supported")
    return schedule(callback, 0, true, frames)
end
injected.CancelDelayedAction = cancel
injected.RegisterKeyBind = function() error("Imported runtime cannot register hotkeys") end
injected.RegisterHook = function(path, before, after)
    assert(path == "/Script/DogwoodInventory.InventoryBlueprintFunctionLibrary:GetItemHandle"
        or path == "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentQuickslotSubsystem:GetAbilityInSlot"
        or path == "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentQuickslotSubsystem:GetLoadoutInfoInSlot"
        -- Read-only: records the RequestID of each tutorial the game raises so a
        -- popup the game leaves stuck can be closed with its own Notify calls.
        or path == "/Script/DogwoodSystem.TutorialSchema:ShowTutorial"
        -- Read-only: the hub tab GameplayTags cannot be enumerated (the struct array
        -- marshal crashes the game), so they are collected from the calls the game
        -- itself makes while it builds the hub.
        or path == "/Script/DogwoodUI.HUBManagerSubystem:BP_IsTabLocked"
        or path == "/Script/DogwoodUI.HUBManagerSubystem:TryShowHUB"
        or path == "/Script/DogwoodUI.HUBManagerSubystem:IsTabActive"
        or path == "/Script/DogwoodUI.HUBManagerSubystem:NotifyTabActivated"
        or path == "/Script/DogwoodUI.HUBManagerSubystem:RegisterSpawnedTabWidget"
        or path == "/Script/DogwoodUI.HUBManagerSubystem:LaunchHUB", "Unapproved imported native hook")
    local preId, postId = RegisterHook(path, before, after)
    hooks[#hooks + 1] = { path = path, pre = preId, post = postId }
    return preId, postId
end
injected.print = function(message)
    message = tostring(message)
    print("[DawnwalkerImportedMenu] " .. message)
    menu.Message(message)
end
local permittedFiles = { ["settings.ini"] = true, ["combat-session.ini"] = true,
    ["activation-session.ini"] = true, ["god-session.ini"] = true, ["parry-session.ini"] = true }
injected.io = setmetatable({ open = function(path, mode)
    local normalized = tostring(path):gsub("\\", "/")
    local root = sourceDirectory:gsub("\\", "/")
    assert(normalized:sub(1, #root) == root and permittedFiles[normalized:sub(#root + 1)], "Unapproved imported state file")
    return io.open(path, mode)
end }, { __index = io })
local loaded, loadFailure = pcall(Loader.Load, sourceDirectory, menu, injected)
if not loaded then menu.Fail("Imported source initialization failed: " .. tostring(loadFailure)) end
if loaded then sourceModules=loadFailure; moduleRegistry.source=sourceModules end

-- Adapter-owned controls live beside the imported source, never inside it, so the
-- supplied package stays byte-identical. They share the same bounded environment:
-- scheduling is accounted and cancellable, and print routes through the menu.
local storyLoaded, storyModule = pcall(function()
    local chunk = assert(loadfile(scriptDirectory .. "StoryTimerControl.lua", "t", injected))
    local module = chunk()
    module.Init(menu, helpers)
    return module
end)
if not storyLoaded then menu.Fail("Story timer initialization failed: " .. tostring(storyModule))
else adapterModules[#adapterModules + 1] = storyModule end

local coreLoaded, coreModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "CorePlayerControl.lua", "t", injected))()
    -- CorePlayerControl presents controls owned by other modules. The registry is
    -- filled in as they load, and read at click time rather than captured now.
    module.Init(menu, helpers, moduleRegistry)
    return module
end)
if not coreLoaded then menu.Fail("Player control initialization failed: " .. tostring(coreModule))
else adapterModules[#adapterModules + 1] = coreModule end

local movementLoaded, movementModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "PlayerMovementReadback.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not movementLoaded then menu.Fail("Movement discovery initialization failed: " .. tostring(movementModule))
else adapterModules[#adapterModules + 1] = movementModule end

local noClipLoaded, noClipModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "NoClipPilot.lua", "t", injected))()
    local flight = assert(loadfile(scriptDirectory .. "NoClipFlightInput.lua", "t", injected))()
    module.Init(menu, helpers, flight)
    return module
end)
if not noClipLoaded then menu.Fail("No Clip initialization failed: " .. tostring(noClipModule))
else adapterModules[#adapterModules + 1] = noClipModule end

local personalFlyLoaded, personalFlyModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "PersonalFlyControl.lua"))()
    -- This user-installed sibling is not part of the distributable menu payload.
    -- Derive it from the loaded runtime; the game's profile file view may differ.
    local personalPath = scriptDirectory .. "../../DawnwalkerPersonalFly-1.0.4/Scripts/"
    module.Init(menu, helpers, injected, personalPath, function()
        local player = helpers.GetPlayer()
        assert(player and player:IsValid(), "Load a player before flying")
        local controller = player.Controller
        assert(controller and controller:IsValid(), "Controlled player required for flight")
        local library = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        assert(library and library:IsValid(), "Flight pause state unavailable")
        return library:IsGamePaused(player) == false and controller.bShowMouseCursor == false
    end)
    return module
end)
if not personalFlyLoaded then menu.Fail("Personal Fly initialization failed: " .. tostring(personalFlyModule))
else adapterModules[#adapterModules + 1] = personalFlyModule end

local jumpLoaded, jumpModule = pcall(function()
    local environment = setmetatable({ require = function(name)
        assert(name == "DawnwalkerSuperJumpDescriptorReadOnlyProbe", "Unexpected jump dependency")
        return assert(loadfile(scriptDirectory .. name .. ".lua", "t", injected))()
    end }, { __index = injected })
    local module = assert(loadfile(scriptDirectory .. "JumpDescriptorReadback.lua", "t", environment))()
    module.Init(menu, helpers)
    return module
end)
if not jumpLoaded then menu.Fail("Jump discovery initialization failed: " .. tostring(jumpModule))
else adapterModules[#adapterModules + 1] = jumpModule end

local superJumpLoaded, superJumpModule = pcall(function()
    assert(jumpLoaded, "Jump descriptor verification is unavailable")
    local environment = setmetatable({ require = function(name)
        assert(name == "SuperJumpEffectPilot", "Unexpected Super Jump dependency")
        return assert(loadfile(scriptDirectory .. name .. ".lua", "t", injected))()
    end }, { __index = injected })
    local module = assert(loadfile(scriptDirectory .. "SuperJumpControl.lua", "t", environment))()
    -- The private effect pilot pairs its short-lived native hooks itself.
    module.Init(menu, helpers, function() return jumpModule.Borrow(helpers) end,
        { registerHook = RegisterHook, unregisterHook = UnregisterHook })
    return module
end)
if not superJumpLoaded then menu.Fail("Super Jump initialization failed: " .. tostring(superJumpModule))
else adapterModules[#adapterModules + 1] = superJumpModule end

local xpReadLoaded, xpReadModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "XPRewardReadback.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not xpReadLoaded then menu.Fail("XP discovery initialization failed: " .. tostring(xpReadModule))
else adapterModules[#adapterModules + 1] = xpReadModule end

local xpRewardsLoaded, xpRewardsModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "XPRewardControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not xpRewardsLoaded then menu.Fail("XP rewards initialization failed: " .. tostring(xpRewardsModule))
else adapterModules[#adapterModules + 1] = xpRewardsModule end

local xpMultiplierLoaded, xpMultiplierModule = pcall(function()
    -- Owns its own hook lifecycle, like the XP observer: the hook is attached only while
    -- a multiplier above 1 is selected and removed the moment it returns to 1, so it is
    -- deliberately not added to the shared allowlisted registry.
    local module = assert(loadfile(scriptDirectory .. "XPMultiplierControl.lua", "t", injected))()
    return module.Init(menu, helpers, { registerHook = RegisterHook, unregisterHook = UnregisterHook,
        log = function(line) print("[DawnwalkerModMenu] " .. line) end })
end)
if not xpMultiplierLoaded then menu.Fail("Quest XP multiplier initialization failed: " .. tostring(xpMultiplierModule))
else adapterModules[#adapterModules + 1] = xpMultiplierModule end

local xpObservationLoaded, xpObservationModule = pcall(function()
    -- This observer owns its paired removals; do not duplicate them in the
    -- shared hook registry used by other imported controls.
    local nativeRegisterHook, nativeUnregisterHook = RegisterHook, UnregisterHook
    local observationEnvironment = setmetatable({
        RegisterHook = nativeRegisterHook,
        UnregisterHook = nativeUnregisterHook,
        require = function(name)
            if name == "ImportedMenuFacade" then return Facade end
            assert(name == "DawnwalkerXPAwardObservation", "Unexpected XP observation dependency")
            return assert(loadfile(scriptDirectory .. "DawnwalkerXPAwardObservation.lua"))()
        end,
    }, { __index = injected })
    local module = assert(loadfile(scriptDirectory .. "XPAwardObservationControl.lua", "t", observationEnvironment))()
    module.Init(menu, helpers)
    return module
end)
if not xpObservationLoaded then menu.Fail("XP observation initialization failed: " .. tostring(xpObservationModule))
else adapterModules[#adapterModules + 1] = xpObservationModule end

local speedReadLoaded, speedReadModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "SpeedDescriptorReadback.lua", "t", injected))()
    module.Init(menu)
    return module
end)
if not speedReadLoaded then menu.Fail("Speed discovery initialization failed: " .. tostring(speedReadModule))
else adapterModules[#adapterModules + 1] = speedReadModule end

local speedControlLoaded, speedControlModule = pcall(function()
    local speedEnvironment = setmetatable({ require = function(name)
        assert(name == "SpeedProfilePilot", "Unexpected movement speed dependency")
        return assert(loadfile(scriptDirectory .. "SpeedProfilePilot.lua", "t", injected))()
    end }, { __index = injected })
    local module = assert(loadfile(scriptDirectory .. "SpeedControl.lua", "t", speedEnvironment))()
    module.Init(menu, helpers)
    return module
end)
if not speedControlLoaded then menu.Fail("Movement speed initialization failed: " .. tostring(speedControlModule))
else adapterModules[#adapterModules + 1] = speedControlModule end

local fallReadLoaded, fallReadModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "FallDamageReadback.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not fallReadLoaded then menu.Fail("Fall damage discovery initialization failed: " .. tostring(fallReadModule))
else adapterModules[#adapterModules + 1] = fallReadModule end

local fallObserverLoaded, fallObserverFailure = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "FallDamageObservation.lua", "t", injected))()
    local observer = module.New({ GetPlayer = helpers.GetPlayer, StaticFindObject = StaticFindObject,
        RegisterHook = RegisterHook, UnregisterHook = UnregisterHook })
    local id = "DWFallObservation"
    local function publish()
        local state = observer.snapshot()
        menu.Set(id, "owned", state.active)
        menu.SetLabel(id, "status", Facade.Encode(state))
    end
    local function execute(callback)
        injected.ExecuteInGameThread(function()
            local ok, failure = pcall(callback)
            publish(); assert(ok, failure)
        end)
    end
    menu.Register({ id = id, title = "Fall dispatch diagnostics", tab = "Player", items = {
        { id = "start", type = "button", label = "Observe fall dispatch", onClick = function() execute(observer.start) end },
        { id = "read", type = "button", label = "Read fall dispatch", onClick = function() execute(function() end) end },
        { id = "stop", type = "button", label = "Stop fall observation", onClick = function() execute(observer.stop) end },
        { id = "owned", type = "checkbox", label = "Fall observation active", default = false,
            onChange = function(value) assert(value == false, "Use observation start"); execute(observer.stop) end },
        { id = "status", type = "label", label = "Read-only fall observation has not started." },
    } })
    adapterModules[#adapterModules + 1] = { ResetSession = function() observer.stop(); publish() end }
end)
local fallDropLoaded, fallDropFailure = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "FallDropDiagnostic.lua", "t", injected))()
    local id, diagnostic = "DWFallDropTest", nil
    local library = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local function gate()
        local player = helpers.GetPlayer()
        if not player or not player:IsValid() or not library or not library:IsValid()
            or library:IsGamePaused(player) or player.Controller.bShowMouseCursor or not player.CombatComponent:IsAlive() then return false end
        local function clear(sectionId, items)
            for _, item in ipairs(items) do
                if item.type == "checkbox" and item.value == true and not ((sectionId == id or sectionId == "DWFallObservation") and item.id == "owned") then return false end
                if item.items and not clear(sectionId, item.items) then return false end
            end
            return true
        end
        for _, section in ipairs(menu.Snapshot().sections) do if not clear(section.id, section.items) then return false end end
        return true
    end
    local function publish(state)
        menu.Set(id, "owned", state.recoveryPending)
        menu.SetLabel(id, "status", Facade.Encode(state))
    end
    diagnostic = module.New({ GetPlayer = helpers.GetPlayer, allOff = gate,
        now = function() return library:GetRealTimeSeconds(helpers.GetPlayer()) end,
        schedule = injected.ExecuteWithDelay, cancel = injected.CancelDelayedAction, onComplete = publish })
    local function execute(callback)
        injected.ExecuteInGameThread(function()
            local ok, cause = pcall(callback); publish(diagnostic.snapshot()); assert(ok, cause)
        end)
    end
    menu.Register({ id = id, title = "Bounded fall diagnostic", tab = "Player", items = {
        { id = "drop200", type = "button", label = "Observe one 200-unit fall", onClick = function() execute(function() diagnostic.start(200) end) end },
        { id = "drop400", type = "button", label = "Observe one 400-unit fall", onClick = function() execute(function() diagnostic.start(400) end) end },
        { id = "owned", type = "checkbox", label = "Fall diagnostic recovery pending", default = false,
            onChange = function(value) assert(value == false, "Use the bounded diagnostic button"); execute(diagnostic.cancel) end },
        { id = "status", type = "label", label = "Fall diagnostic has not run." },
    } })
    adapterModules[#adapterModules + 1] = { ResetSession = function() if diagnostic.owned() then diagnostic.cancel() end end }
end)
if not fallDropLoaded then menu.Fail("Fall drop initialization failed: " .. tostring(fallDropFailure)) end
if not fallObserverLoaded then menu.Fail("Fall observer initialization failed: " .. tostring(fallObserverFailure)) end

local movementEffectLoaded, movementEffectModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "MovementEffectReadback.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not movementEffectLoaded then menu.Fail("Movement effect discovery failed: " .. tostring(movementEffectModule))
else adapterModules[#adapterModules + 1] = movementEffectModule end

-- Controlled diagnostic only: one synchronous apply/verify/remove while paused.
-- Private non-stacking definition still requires live gameplay validation.
local jumpEffectLoaded, jumpEffectFailure = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "SuperJumpEffectPilot.lua", "t", injected))()
    local pilot = module.New({ borrow = function() return jumpModule.Borrow(helpers) end,
        registerHook = RegisterHook, unregisterHook = UnregisterHook,
        exclusive = function()
            local library = StaticFindObject("/Script/Engine.Default__GameplayStatics")
            return library and library:IsValid() and library:IsGamePaused(helpers.GetPlayer()) == true
        end })
    menu.Register({ id = "DWJumpEffectTest", title = "Controlled jump diagnostic", tab = "Player", items = {
        { id = "roundtrip", type = "button", label = "Test paused jump effect and restore", onClick = function()
            injected.ExecuteInGameThread(function()
                local ok, failure = pcall(function() pilot.inspect(); pilot.set(true); pilot.verify(); pilot.set(false) end)
                local restored, restoreFailure = pcall(pilot.reset)
                menu.SetLabel("DWJumpEffectTest", "status", ok and restored and "Effect apply/readback/removal passed; gameplay jump not tested."
                    or (tostring(failure) .. "; cleanup=" .. tostring(restoreFailure or restored)))
                assert(ok and restored, tostring(failure) .. "; cleanup=" .. tostring(restoreFailure or restored))
            end)
        end },
        { id = "status", type = "label", label = "Pause the game before this controlled diagnostic." },
    } })
    adapterModules[#adapterModules + 1] = { ResetSession = pilot.reset }
end)
if not jumpEffectLoaded then menu.Fail("Jump effect diagnostic failed: " .. tostring(jumpEffectFailure)) end

local jumpTrajectoryLoaded, jumpTrajectoryFailure = pcall(function()
    local id = "DWJumpTrajectoryTest"
    local module = assert(loadfile(scriptDirectory .. "JumpTrajectoryDiagnostic.lua", "t", injected))()
    local effect = assert(loadfile(scriptDirectory .. "SuperJumpEffectPilot.lua", "t", injected))()
    local function library()
        local object = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        assert(object and object:IsValid(), "Gameplay timing library unavailable")
        return object
    end
    local pilot = effect.New({ borrow = function() return jumpModule.Borrow(helpers) end,
        registerHook = RegisterHook, unregisterHook = UnregisterHook,
        exclusive = function()
            local player = helpers.GetPlayer()
            return player and player:IsValid() and player:IsInWolfForm() == false
        end })
    local diagnostic = module.New(helpers, pilot, { subscribe = function(callback)
            local handle = injected.LoopInGameThreadAfterFrames(1, callback)
            return function() injected.CancelDelayedAction(handle) end
        end,
        now = function() return library():GetRealTimeSeconds(helpers.GetPlayer()) * 1000 end,
        isPaused = function(player) return library():IsGamePaused(player) end })
    local function publish(state)
        state.recoveryPending = diagnostic.owned()
        menu.Set(id, "owned", state.recoveryPending)
        menu.SetLabel(id, "status", Facade.Encode(state))
    end
    local function allOff(items, sectionId)
        for _, item in ipairs(items) do
            assert(item.type ~= "checkbox" or item.value ~= true or (sectionId == id and item.id == "owned"),
                "Turn every other control OFF before the physical jump test")
            if item.items then allOff(item.items, sectionId) end
        end
    end
    local function reset()
        local ok, cause = pcall(diagnostic.reset)
        publish({ cancelled = true, restorationVerified = ok, failure = not ok and tostring(cause) or nil })
        assert(ok, cause)
    end
    menu.Register({ id = id, title = "Physical jump diagnostic", tab = "Player", items = {
        { id = "run", type = "button", label = "Compare two physical jumps and restore", onClick = function()
            injected.ExecuteInGameThread(function()
                local ok, cause = pcall(function()
                    for _, section in ipairs(menu.Snapshot().sections) do allOff(section.items, section.id) end
                    diagnostic.run(publish)
                end)
                if not ok then publish({ passed = false, failure = tostring(cause) })
                elseif diagnostic.owned() then publish({ running = true }) end
                assert(ok, cause)
            end)
        end },
        { id = "owned", type = "checkbox", label = "Physical jump recovery pending", default = false,
            onChange = function(value)
                assert(value == false, "Use the physical comparison button")
                injected.ExecuteInGameThread(reset)
            end },
        { id = "status", type = "label", label = "Use unpaused clear flat ground, with every other control OFF." },
    } })
    adapterModules[#adapterModules + 1] = { ResetSession = reset }
end)
if not jumpTrajectoryLoaded then menu.Fail("Physical jump diagnostic failed: " .. tostring(jumpTrajectoryFailure)) end

-- Temporary bounded speed profile diagnostics; no gameplay toggle is exposed.
local speedProfileLoaded, speedProfileFailure = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "SpeedProfilePilot.lua", "t", injected))()
    local pilot = module.New(helpers)
    local testGeneration, running, inputOwner, unpausedTrial = 0, false, nil, false
    local function checkPause()
        local library = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        assert(library and library:IsValid() and library:IsGamePaused(helpers.GetPlayer()) == not unpausedTrial,
            unpausedTrial and "Unpause the game before the standing speed trial" or "Pause the game before testing the speed profile")
    end
    local function checkInputOwner()
        local player = helpers.GetPlayer()
        assert(player and player:IsValid() and player:GetAddress() == inputOwner.playerId
            and player.Controller:IsValid() and player.Controller:GetAddress() == inputOwner.controllerId
            and player.Controller.Pawn:GetAddress() == inputOwner.playerId,
            "Speed input suppression belongs to another player; recovery retained")
        return player.Controller
    end
    local function releaseInput()
        if not inputOwner then return end
        local controller = checkInputOwner()
        if not inputOwner.removed then
            if controller:IsMoveInputIgnored() then controller:SetIgnoreMoveInput(false) end
            inputOwner.removed = true -- Never decrement another owner's input lock on retry.
        end
        assert(controller:IsMoveInputIgnored() == false, "Speed trial input baseline not restored")
        inputOwner = nil
    end
    local function suppressInput()
        local player = helpers.GetPlayer()
        local controller, velocity = player.Controller, player:GetVelocity()
        local speedSquared = velocity.X * velocity.X + velocity.Y * velocity.Y + velocity.Z * velocity.Z
        assert(speedSquared == speedSquared and speedSquared <= 1, "Stand still before the speed trial")
        assert(controller:IsMoveInputIgnored() == false, "Movement input is already suppressed")
        inputOwner = { playerId = player:GetAddress(), controllerId = controller:GetAddress(), removed = false }
        checkInputOwner()
        controller:SetIgnoreMoveInput(true)
        assert(controller:IsMoveInputIgnored() == true, "Speed trial input suppression failed")
    end
    local function syncOwnership()
        menu.Set("DWSpeedProfileTest", "owned", pilot.owned() or inputOwner ~= nil)
    end
    local function restoreTest(token, applied, failure, cancelled)
        local begun, beginFailure = pcall(pilot.beginRestore)
        local attempts = 0
        local function check()
            if token ~= testGeneration then return end
            attempts = attempts + 1
            local restored, restoreFailure = pcall(pilot.reset)
            local inputsRestored, inputFailure = pcall(releaseInput)
            syncOwnership()
            if (not restored or not inputsRestored) and attempts < 6 then injected.ExecuteWithDelay(100, check); return end
            restored = restored and inputsRestored
            running = false
            menu.SetLabel("DWSpeedProfileTest", "status", cancelled and restored and "Speed diagnostic cancelled; original profile restored."
                or applied and restored
                and (unpausedTrial and "Unpaused profile apply/readback/restoration and input restoration passed at 1.5x; movement distance not tested."
                    or "Paused profile apply/readback/restoration passed at 1.5x; gameplay movement not tested.")
                or ("Speed profile trial failed: " .. tostring(failure) .. "; cleanup="
                    .. tostring(restoreFailure or inputFailure or (not begun and beginFailure) or restored)))
            assert((applied or cancelled) and restored, tostring(failure) .. "; cleanup=" .. tostring(restoreFailure or inputFailure or restored))
        end
        injected.ExecuteWithDelay(100, check)
    end
    local function startTrial(unpaused)
            injected.ExecuteInGameThread(function()
                assert(not running and not inputOwner and not pilot.owned(), "Speed diagnostic or recovery already active")
                unpausedTrial = unpaused
                testGeneration = testGeneration + 1
                local token = testGeneration
                running = true
                local ok, failure = pcall(function()
                    checkPause(); pilot.inspect()
                    if unpausedTrial then suppressInput() end
                    pilot.begin(1.5)
                end)
                syncOwnership()
                if not ok then restoreTest(token, false, failure); return end
                local attempts = 0
                local function check()
                    if token ~= testGeneration then return end
                    attempts = attempts + 1
                    local verified, cause = pcall(function()
                        checkPause()
                        if inputOwner then assert(checkInputOwner():IsMoveInputIgnored() == true, "Speed input suppression changed") end
                        pilot.verify()
                    end)
                    if not verified and attempts < 6 then injected.ExecuteWithDelay(100, check); return end
                    restoreTest(token, verified, cause)
                end
                injected.ExecuteWithDelay(100, check)
            end)
    end
    menu.Register({ id = "DWSpeedProfileTest", title = "Controlled speed diagnostic", tab = "Player", items = {
        { id = "roundtrip", type = "button", label = "Test paused speed profile and restore", onClick = function() startTrial(false) end },
        { id = "roundtrip_unpaused", type = "button", label = "Test unpaused speed while standing still", onClick = function() startTrial(true) end },
        { id = "owned", type = "checkbox", label = "Speed diagnostic recovery", default = false, onChange = function(value)
            assert(value == false, "Use the paused speed diagnostic")
            testGeneration = testGeneration + 1
            restoreTest(testGeneration, false, "Speed diagnostic cancelled; restoring its profile", true)
        end },
        { id = "status", type = "label", label = "Pause the game before this controlled speed diagnostic." },
    } })
    adapterModules[#adapterModules + 1] = { ResetSession = function()
        testGeneration = testGeneration + 1
        local restored, failure = pcall(pilot.reset)
        local inputsRestored, inputFailure = pcall(releaseInput)
        syncOwnership(); running = false
        assert(restored and inputsRestored, tostring(failure or inputFailure))
    end }
end)
if not speedProfileLoaded then menu.Fail("Speed profile diagnostic failed: " .. tostring(speedProfileFailure)) end

local worldLoaded, worldModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "WorldControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not worldLoaded then menu.Fail("World control initialization failed: " .. tostring(worldModule))
else adapterModules[#adapterModules + 1] = worldModule end

local questLoaded, questModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "QuestReadback.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not questLoaded then menu.Fail("Quest readback initialization failed: " .. tostring(questModule))
else adapterModules[#adapterModules + 1] = questModule end

local difficultyLoaded, difficultyModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "DifficultyControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not difficultyLoaded then menu.Fail("Difficulty initialization failed: " .. tostring(difficultyModule))
else adapterModules[#adapterModules + 1] = difficultyModule end

local teleportLoaded, teleportModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "SavedLocationControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not teleportLoaded then menu.Fail("Saved location initialization failed: " .. tostring(teleportModule))
else adapterModules[#adapterModules + 1] = teleportModule end

-- Menu-map adapters were removed; marker travel uses the separate in-game mod.


local levelLoaded, levelModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "PlayerLevelControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not levelLoaded then menu.Fail("Player level initialization failed: " .. tostring(levelModule))
else adapterModules[#adapterModules + 1] = levelModule end

local hubTagsLoaded, hubTagsModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "HubTagProbe.lua", "t", injected))()
    module.Init(menu, helpers, { registerHook = injected.RegisterHook,
        unregisterHook = injected.UnregisterHook,
        deferToGameThread = injected.ExecuteInGameThread,
        log = function(line) print("[DawnwalkerModMenu] " .. line) end })
    return module
end)
if not hubTagsLoaded then menu.Fail("Hub tag probe initialization failed: " .. tostring(hubTagsModule))
else
    moduleRegistry.hubTags = hubTagsModule
    -- Also an adapter module, so cleanup detaches its watchers on a session change or
    -- unload. Registering it only in moduleRegistry left it outside that lifecycle, and
    -- its six hooks survived every session for the life of the process.
    adapterModules[#adapterModules + 1] = hubTagsModule
end

local hubTabsLoaded, hubTabsModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "HubTabControl.lua", "t", injected))()
    module.Init(menu, helpers, { hubTags = hubTagsLoaded and hubTagsModule or nil,
        log = function(line) print("[DawnwalkerModMenu] " .. line) end })
    return module
end)
if not hubTabsLoaded then menu.Fail("Hub tab initialization failed: " .. tostring(hubTabsModule))
else adapterModules[#adapterModules + 1] = hubTabsModule end

local tutorialLoaded, tutorialModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "TutorialDismissControl.lua", "t", injected))()
    module.Init(menu, helpers, { registerHook = injected.RegisterHook })
    return module
end)
if not tutorialLoaded then menu.Fail("Tutorial dismiss initialization failed: " .. tostring(tutorialModule))
else adapterModules[#adapterModules + 1] = tutorialModule end

local photoCameraLoaded, photoCameraModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "PhotoCameraControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not photoCameraLoaded then menu.Fail("Photo camera initialization failed: " .. tostring(photoCameraModule))
else adapterModules[#adapterModules + 1] = photoCameraModule end

local traitPointLoaded, traitPointModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "TraitPointControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not traitPointLoaded then menu.Fail("Trait point initialization failed: " .. tostring(traitPointModule))
else adapterModules[#adapterModules + 1] = traitPointModule end

local courtAlertLoaded, courtAlertModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "CourtAlertControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not courtAlertLoaded then menu.Fail("Court alert initialization failed: " .. tostring(courtAlertModule))
else adapterModules[#adapterModules + 1] = courtAlertModule end

local clockLoaded, clockModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "ClockControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not clockLoaded then menu.Fail("Clock initialization failed: " .. tostring(clockModule))
else adapterModules[#adapterModules + 1] = clockModule end

local bloodSegmentLoaded, bloodSegmentModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "BloodSegmentControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not bloodSegmentLoaded then menu.Fail("Blood segment initialization failed: " .. tostring(bloodSegmentModule))
else adapterModules[#adapterModules + 1] = bloodSegmentModule end

local craftingLoaded, craftingModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "CraftingControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not craftingLoaded then menu.Fail("Crafting initialization failed: " .. tostring(craftingModule))
else adapterModules[#adapterModules + 1] = craftingModule end

local loadoutLoaded, loadoutModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "EquipmentLoadoutControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not loadoutLoaded then menu.Fail("Equipment loadout initialization failed: " .. tostring(loadoutModule))
else adapterModules[#adapterModules + 1] = loadoutModule end

local weightLoaded, weightModule = pcall(function()
    -- The reviewed carry-capacity probe is written to run itself on load. This runtime
    -- runs it on demand from the menu instead, so it is loaded with the probe's own test
    -- flag set. _G points at that private environment because the probe tests the flag
    -- with rawget(_G, ...): writing the real global would outlive this load.
    local probeEnvironment = setmetatable({ DAWNWALKER_CARRY_CAPACITY_PROBE_TEST = true }, { __index = injected })
    probeEnvironment._G = probeEnvironment
    local probe = assert(loadfile(scriptDirectory .. "CarryCapacityReadOnlyProbe.lua", "t", probeEnvironment))()
    -- CarryWeightPilot.lua is deliberately still not loaded. Its one reviewed write
    -- arrangement - SetAttributeValue with the UPARAM(Ref) descriptor - is refused by this
    -- UE4SS build, and the attempt to vary the argument arrangement crashed the game on
    -- 2026-09-17 (access violation inside RC::LuaType::call_ufunction_from_lua). A
    -- mis-marshalled native call cannot be caught, so that harness stays out of the payload
    -- and in the repository with its own tests.
    --
    -- Zero Weight is served instead by CarryCapacityEffectPilot.lua, which never passes a
    -- descriptor as an out parameter and never calls the setter: it constructs a private
    -- native GameplayEffect owned by the player's ASC, applies it through the game's own
    -- GAS instrumentation, and removes that exact handle again. It pairs its own short-lived
    -- MakeSpecHandle hook - the same call the live attack pilot makes, and one the shared
    -- injected.RegisterHook allowlist does not cover - so it is handed the raw hook
    -- functions, as CombatDiscovery does for AttackSpeedEffectPilot.
    local capacity = assert(loadfile(scriptDirectory .. "CarryCapacityEffectPilot.lua", "t", injected))()
    local capacityPilot = capacity.New(helpers, {
        probe = probe,
        static_find_object = StaticFindObject,
        property_types = PropertyTypes,
        registerHook = RegisterHook,
        unregisterHook = UnregisterHook,
    })
    local module = assert(loadfile(scriptDirectory .. "CarryWeightCheck.lua", "t", injected))()
    module.Init(menu, helpers, probe, capacityPilot)
    return module
end)
if not weightLoaded then menu.Fail("Carry weight check initialization failed: " .. tostring(weightModule))
else adapterModules[#adapterModules + 1] = weightModule end

-- Edit Item Amount and Unlimited Consumables. Both ride the reflected inventory calls the
-- Give route already exercises live (GetItemHandle bridge, TryAddItem, RemoveItem,
-- GetItemQuantity); the consumables switch needs a hook on InventoryComponent:UseItem,
-- which the shared allowlist does not cover, so the module is handed the raw hook function.
local itemAmountLoaded, itemAmountModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "ItemAmountControl.lua", "t", injected))()
    return module.Init(menu, helpers, { registerHook = RegisterHook })
end)
if not itemAmountLoaded then menu.Fail("Item amount initialization failed: " .. tostring(itemAmountModule))
else adapterModules[#adapterModules + 1] = itemAmountModule end

-- Super Damage / One-Hit Kills: three private additive GameplayEffects on the player's
-- melee, claws and magic damage multipliers, built and applied exactly as the live attack
-- and Zero Weight pilots do. The pilot pairs its own short-lived MakeSpecHandle hook, which
-- the shared allowlist does not cover, so it is handed the raw hook functions.
local superDamageLoaded, superDamageModule = pcall(function()
    local pilotModule = assert(loadfile(scriptDirectory .. "SuperDamageEffectPilot.lua", "t", injected))()
    local pilot = pilotModule.New(helpers, { registerHook = RegisterHook, unregisterHook = UnregisterHook })
    local module = assert(loadfile(scriptDirectory .. "SuperDamageControl.lua", "t", injected))()
    return module.Init(menu, helpers, pilot, module.SUPER_DAMAGE)
end)
if not superDamageLoaded then menu.Fail("Super damage initialization failed: " .. tostring(superDamageModule))
else adapterModules[#adapterModules + 1] = superDamageModule end

-- Extended Parry Window: the same owned-effect pilot on CharDevAttributeSet.ParryWindowMultiplier,
-- descriptor borrowed from the shipped GE_ParryWindowMultiplier item modifier.
local parryWindowLoaded, parryWindowModule = pcall(function()
    local pilotModule = assert(loadfile(scriptDirectory .. "SuperDamageEffectPilot.lua", "t", injected))()
    local pilot = pilotModule.New(helpers, {
        registerHook = RegisterHook, unregisterHook = UnregisterHook,
        targets = { { attribute = "ParryWindowMultiplier", source = "GE_ParryWindowMultiplier", family = "parry", set = "CharDevAttributeSet" } },
        wording = { subject = "parry window", sets = "parry window multiplier", descriptors = "parry window descriptor", footnote = "" },
    })
    local module = assert(loadfile(scriptDirectory .. "SuperDamageControl.lua", "t", injected))()
    return module.Init(menu, helpers, pilot, module.PARRY_WINDOW)
end)
if not parryWindowLoaded then menu.Fail("Parry window initialization failed: " .. tostring(parryWindowModule))
else adapterModules[#adapterModules + 1] = parryWindowModule end

-- Ignore Crafting Requirement: pre-hooks on CraftingSubsystem:CraftItem/CanItemBeCrafted
-- force the game's own bForFree argument; neither is on the shared allowlist.
local freeCraftingLoaded, freeCraftingModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "FreeCraftingControl.lua", "t", injected))()
    return module.Init(menu, helpers, { registerHook = RegisterHook })
end)
if not freeCraftingLoaded then menu.Fail("Free crafting initialization failed: " .. tostring(freeCraftingModule))
else adapterModules[#adapterModules + 1] = freeCraftingModule end

local storySettingsLoaded, storySettingsModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "StorySettingsControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not storySettingsLoaded then menu.Fail("Story settings initialization failed: " .. tostring(storySettingsModule))
else adapterModules[#adapterModules + 1] = storySettingsModule end

local combatDiscoveryLoaded, combatDiscoveryModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "CombatDiscovery.lua", "t", injected))()
    local attack = assert(loadfile(scriptDirectory .. "AttackSpeedEffectPilot.lua", "t", injected))()
    local pilot = attack.New(helpers, { registerHook = RegisterHook, unregisterHook = UnregisterHook })
    local observation = assert(loadfile(scriptDirectory .. "AttackRateObservation.lua", "t", injected))()
    local attributes = assert(loadfile(scriptDirectory .. "CombatAttributeInspection.lua", "t", injected))()
    module.Init(menu, helpers, pilot, observation.New(helpers), attributes)
    return module
end)
if not combatDiscoveryLoaded then menu.Fail("Combat inspection initialization failed: " .. tostring(combatDiscoveryModule))
else adapterModules[#adapterModules + 1] = combatDiscoveryModule end

local eyeLoaded, eyeModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "EyeColorControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not eyeLoaded then menu.Fail("Eye color initialization failed: " .. tostring(eyeModule))
else adapterModules[#adapterModules + 1] = eyeModule end

local hairLoaded, hairModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "HairColorControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not hairLoaded then menu.Fail("Hair color initialization failed: " .. tostring(hairModule))
else adapterModules[#adapterModules + 1] = hairModule end

local skinLoaded, skinModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "SkinTintControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not skinLoaded then menu.Fail("Skin tint initialization failed: " .. tostring(skinModule))
else adapterModules[#adapterModules + 1] = skinModule end

local courtLoaded, courtModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "TimelessCourtControl.lua", "t", injected))()
    module.Init(menu, helpers)
    return module
end)
if not courtLoaded then menu.Fail("Court activities initialization failed: " .. tostring(courtModule))
else adapterModules[#adapterModules + 1] = courtModule end

local formLoaded, formModule = pcall(function()
    local module = assert(loadfile(scriptDirectory .. "FormToggleControl.lua", "t", injected))()
    module.Init(menu, helpers, function()
        assert(eyeLoaded, "Eye color cleanup is unavailable; restart the menu before changing form.")
        eyeModule.BeforeFormChange()
        -- Hair components can be swapped with the form; release the private instances first.
        if hairLoaded then hairModule.BeforeFormChange() end
        if skinLoaded then skinModule.BeforeFormChange() end
    end)
    return module
end)
if not formLoaded then menu.Fail("Form toggle initialization failed: " .. tostring(formModule))
else
    adapterModules[#adapterModules + 1] = formModule
    -- Player controls presents the Vampire form override checkbox and looks the module
    -- up here at click time, because this loads after that panel is built.
    moduleRegistry.formToggle = formModule
end

local function decode(value)
    local cursor = 1
    while true do
        local position = value:find("%", cursor, true)
        if not position then break end
        assert(value:sub(position + 1, position + 2):match("^%x%x$"), "Malformed percent encoding")
        cursor = position + 3
    end
    local decoded = value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    assert(not decoded:find("%z"), "NUL command field")
    return decoded
end
local commandFields = { request_id = true, session_id = true, action = true, section_id = true,
    item_id = true, value = true, value_type = true, confirmation_token = true, confirmed = true, expires_at = true }
local function readCommand()
    local file = io.open(channel .. "command.txt", "rb")
    if not file then return nil end
    local contents = file:read(16385); file:close()
    if not contents or #contents > 16384 then error("Command exceeds size bound") end
    local fields = {}
    for line in contents:gmatch("[^\r\n]+") do
        local key, value = line:match("^([a-z_]+)=(.*)$")
        assert(key and commandFields[key] and fields[key] == nil, "Unknown/duplicate command field")
        fields[key] = decode(value)
    end
    if fields.value_type == "boolean" then
        assert(fields.value == "true" or fields.value == "false", "Invalid boolean")
        fields.value = fields.value == "true"
    elseif fields.value_type == "number" then
        fields.value = tonumber(fields.value); assert(fields.value, "Invalid number")
    elseif fields.value_type and fields.value_type ~= "" and fields.value_type ~= "string" then error("Invalid value type") end
    if fields.confirmed ~= nil then
        assert(fields.confirmed == "true" or fields.confirmed == "false", "Invalid confirmation decision")
        fields.confirmed = fields.confirmed == "true"
    end
    return fields
end
local publishedRevision,publishedPending,publishedStatus,publishedHeartbeat
-- Last published payload, kept so a new second does not rebuild the whole snapshot.
-- Snapshot() deep-copies every section and item and Encode() walks and sorts every
-- object: measured at 8.5 ms for a 50 KB payload, and the live one is larger. The
-- revision bumps on every content change, so when revision, pending count and status
-- are all unchanged the payload is identical apart from the heartbeat integer.
local publishedPayload
local HEARTBEAT_FIELD = '"heartbeat":%-?%d+'
writeState = function()
    local revision,pendingCount,status=menu.PublicationState()
    local heartbeat=os.time()
    local contentUnchanged = publishedRevision==revision and publishedPending==pendingCount
        and publishedStatus==status
    if contentUnchanged and publishedHeartbeat==heartbeat then return end
    local encoded
    if contentUnchanged and publishedPayload then
        local patched,replaced = publishedPayload:gsub(HEARTBEAT_FIELD,'"heartbeat":'..heartbeat,1)
        assert(replaced==1,"Snapshot heartbeat field vanished from the cached payload")
        encoded = patched
    else
        local snapshot=menu.Snapshot()
        if closeRequestId and snapshot.operation and snapshot.operation.id==closeRequestId
            and snapshot.operation.status=="completed" and menu.PendingCount()==0 then closeVerified=true end
        encoded = Facade.Encode(snapshot)
        heartbeat = snapshot.heartbeat
        -- Uniqueness is checked once per encode, not once per heartbeat. Encoded strings
        -- escape every quote as ", so this field name cannot occur inside a value;
        -- the check proves that rather than trusting it.
        assert(select(2,encoded:gsub(HEARTBEAT_FIELD,''))==1,
            "Snapshot heartbeat field is not unique; refusing to publish a patchable payload")
    end
    assert(#encoded <= 1048576, "Imported snapshot exceeds 1 MiB")
    local temporary = channel .. "state.json.tmp"
    local file, failure = io.open(temporary, "wb")
    assert(file, "Create the imported transport directory before loading the mod: " .. tostring(failure))
    local written, writeFailure = file:write(encoded); file:close(); assert(written, writeFailure)
    -- The desktop app polls this file several times a second, so the swap can lose the
    -- race. That is transient and must cost one tick, not the whole runtime, which is
    -- what asserting here used to do.
    --
    -- Order matters: the target is only removed once a plain rename has been tried, so
    -- a failure never leaves the channel with no state file at all. If the swap cannot
    -- be made either way, the payload is written straight to the target, because a
    -- readable state file matters more than an atomic replacement.
    local target = channel .. "state.json"
    local renamed = os.rename(temporary, target)
    if not renamed then
        os.remove(target)
        renamed = os.rename(temporary, target)
    end
    if not renamed then
        local direct = io.open(target, "wb")
        if not direct then os.remove(temporary); return end
        local wrote = direct:write(encoded)
        direct:close()
        os.remove(temporary)
        if not wrote then return end
    end
    -- Commit only after publication succeeds; failed writes remain retryable.
    publishedRevision,publishedPending,publishedStatus,publishedHeartbeat=revision,pendingCount,status,heartbeat
    publishedPayload=encoded
end
-- Modules that need one live read as soon as a player session exists implement
-- SessionReady. Without it a read-gated control - the difficulty axes are the visible
-- case - stays disabled showing "Awaiting readback" until the player happens to find its
-- Refresh button, which reads as the control being broken rather than merely unread.
--
-- A pawn can exist for a few ticks before the subsystems those reads depend on resolve,
-- so a module that fails is retried on later ticks rather than written off after one
-- attempt. Only a module still failing on the final attempt is reported; each one already
-- publishes its own status label, so the report explains why the automatic read never
-- landed rather than replacing the module's own message.
local SESSION_READY_ATTEMPTS = 5
local sessionReadySession, sessionReadyAttempt, sessionReadyDone, sessionReadyNext = nil, 0, {}, {}
local function cyberfox1337x_RunSessionReady()
    if sessionReadySession ~= sessionId then
        sessionReadySession, sessionReadyAttempt, sessionReadyDone, sessionReadyNext = sessionId, 0, {}, {}
    end
    local initialPass = sessionReadyAttempt < SESSION_READY_ATTEMPTS
    if initialPass then sessionReadyAttempt = sessionReadyAttempt + 1 end
    local finalAttempt = initialPass and sessionReadyAttempt >= SESSION_READY_ATTEMPTS
    local now = os.time()
    local outstanding = 0
    for _, modules in ipairs({ sourceModules or {}, adapterModules or {} }) do
        for _, module in pairs(modules) do
            local hasRead = type(module) == "table" and type(module.SessionReady) == "function"
            local needsMaintenance = false
            if hasRead and type(module.NeedsSessionReady) == "function" then
                local checked, needed = pcall(module.NeedsSessionReady)
                needsMaintenance = checked and needed == true
            end
            local maintenanceDue = needsMaintenance and menu.PendingCount() == 0
                and (not sessionReadyNext[module] or now >= sessionReadyNext[module])
            if hasRead and ((initialPass and not sessionReadyDone[module]) or maintenanceDue) then
                local ok, failure = pcall(module.SessionReady)
                if ok then
                    sessionReadyDone[module], sessionReadyNext[module] = true, nil
                else
                    outstanding = outstanding + 1
                    sessionReadyNext[module] = now + 2
                    if finalAttempt then
                        -- Deliberately use the log rather than menu.Fail. This read was
                        -- never asked for and each module publishes its own unavailable
                        -- status. Read-only maintenance retries continue at a bounded rate;
                        -- they never replay an ON/OFF request or discard owned recovery.
                        print("[DawnwalkerImportedMenu] Automatic session readback failed: "
                            .. tostring(failure))
                    end
                end
            end
        end
    end
    -- Nothing left to read means the remaining attempts would walk both module lists for
    -- no reason on every tick, so retire the pass rather than counting it out.
    if initialPass and outstanding == 0 then sessionReadyAttempt = SESSION_READY_ATTEMPTS end
end
local lastEyeHeartbeat, lastSkinHeartbeat, lastSkinFailure, lastCourtHeartbeat, lastCourtFailure
local function tick()
    if ending or unloaded then return end
    local actual = playerIdentity()
    if actual ~= identity then
        -- The resolver notices a swapped pawn on its own, but a session change is the
        -- one moment worth paying for a fresh look rather than inferring one.
        playerResolver.Invalidate()
        cleanup(); identity = actual
        closeRequestId=nil;closeVerified=false
        sessionId = boot .. "-" .. tostring(generation)
        menu.Session(sessionId, loaded and actual ~= nil)
    end
    if identity and loaded then
        cyberfox1337x_RunSessionReady()
        local heartbeat = os.time()
        if courtLoaded and menu.PendingCount() == 0 and lastCourtHeartbeat ~= heartbeat then
            lastCourtHeartbeat = heartbeat
            local ok, failure = pcall(courtModule.RefreshSession)
            local message = not ok and tostring(failure) or nil
            if message and message ~= lastCourtFailure then menu.Fail("Court time recovery: " .. message) end
            lastCourtFailure = message
        end
        if skinLoaded and menu.PendingCount() == 0 and lastSkinHeartbeat ~= heartbeat then
            lastSkinHeartbeat = heartbeat
            local ok, failure = pcall(skinModule.RefreshSession)
            local message = not ok and tostring(failure) or nil
            if message and message ~= lastSkinFailure then menu.Fail("Skin tint recovery: " .. message) end
            lastSkinFailure = message
        end
        if eyeLoaded and menu.PendingCount() == 0 and lastEyeHeartbeat ~= heartbeat then
            lastEyeHeartbeat = heartbeat
            eyeModule.RefreshSession()
        end
        local command = readCommand()
        if command and command.request_id and not seenRequests[command.request_id] then
            -- Consume even rejected envelopes so a stale mailbox cannot generate
            -- the same failure on every runtime tick. No callback runs before validation.
            seenRequests[command.request_id] = true; requestOrder[#requestOrder + 1] = command.request_id
            if #requestOrder > 1024 then seenRequests[table.remove(requestOrder, 1)] = nil end
            -- Session changes routinely race an already-published read request. Consume
            -- that old envelope without turning a safe rejection into a path-bearing Lua
            -- failure. A current but invalid deadline remains visible as a clean message.
            if command.session_id == sessionId then
                local expires = tonumber(command.expires_at)
                if not expires or expires < os.time() or expires > os.time() + 5 then
                    menu.Fail("Expired or invalid imported command deadline")
                else
                    if command.action=="close" then closeRequestId=command.request_id
                    else closeRequestId=nil;closeVerified=false end
                    local dispatched, failure = pcall(menu.Dispatch, command)
                    if not dispatched then menu.Fail(failure) end
                end
            end
        end
    end
    writeState()
end
menu.Session(sessionId, false)
local function poll()
    if unloaded or ending then return true end
    if EngineTickAvailable ~= true then
        menu.Session(sessionId, false)
        local ok, failure = pcall(writeState); if not ok then print("[DawnwalkerImportedMenu] " .. tostring(failure)) end
        return false
    end
    local ok, failure = pcall(tick)
    if not ok then menu.Fail(failure); local saved, saveFailure = pcall(writeState); if not saved then print(tostring(saveFailure)) end end
    return false
end
ModRef.OnUnload = function()
    -- UE4SS discards queued game-thread calls during unload. Never enqueue OFF
    -- here and report it as restored; the desktop must obtain close's ACK first.
    unloaded = true
    if pollHandle then
        local cancelled, failure = pcall(CancelDelayedAction, pollHandle)
        if not cancelled then menu.Fail("Unload poll cancellation failed: " .. tostring(failure)) end
        pollHandle = nil
    end
    local checked,inGameThread=pcall(IsInGameThread)
    if ending then
        invalidateScheduling(false)
        identity=nil;menu.Session(sessionId,false)
    elseif checked and inGameThread then
        cleanup(); identity = nil; menu.Session(sessionId, false)
        for _, hook in ipairs(hooks) do
            local ok, failure = pcall(UnregisterHook, hook.path, hook.pre, hook.post)
            if not ok then menu.Fail("Item hook cleanup failed: " .. tostring(failure)) end
        end
    else
        if not closeVerified then menu.Fail("Unload occurred without a verified game-thread close handshake; OFF restoration is unverified. Restart the game before further testing.") end
        invalidateScheduling(false)
        identity=nil;menu.Session(sessionId,false)
    end
    local saved, failure = pcall(writeState); if not saved then print(tostring(failure)) end
end
pollHandle = LoopInGameThreadWithDelay(150, poll)
