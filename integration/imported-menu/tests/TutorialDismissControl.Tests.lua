local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("tutorial_dismiss_control_tests")

-- Covers Scripts/TutorialDismissControl.lua.
--
-- The Edict popup is a NOTIFICATION, not a tutorial, so the primary path is
-- NotificationSubsystem:GetCurrentNotificationInfo() -> NotificationInfo:NotifyEnded().
-- GetCurrentNotificationInfo is a real getter, so a dismissal must be verified by the
-- current notification clearing or changing, and must never be claimed otherwise.

local path = assert(arg[1], "Supply TutorialDismissControl.lua")

local count = 0
local function test(name, body)
    local ok, err = pcall(body)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
    print("PASS " .. name)
end

local function alwaysValid() return true end

local function menuDouble()
    local menu = { labels = {}, sections = {}, plainLabels = {} }
    function menu.Register(section)
        menu.sections[section.id] = section
        for _, item in ipairs(section.items) do
            if item.type == "label" and not item.id then
                menu.plainLabels[#menu.plainLabels + 1] = item.label
            end
        end
    end
    function menu.SetLabel(_, itemId, text) menu.labels[itemId] = tostring(text) end
    function menu.Set() end
    function menu.SetOptions() end
    function menu.Get() end
    function menu.click(itemId)
        for _, item in ipairs(menu.sections.DWTutorialDismiss.items) do
            if item.id == itemId and item.onClick then return item.onClick() end
        end
        error("no such control: " .. itemId)
    end
    return menu
end

-- queue models the notifications the game will show, newest first.
local function fixture(overrides)
    overrides = overrides or {}
    local world = {
        queue = overrides.queue and { table.unpack(overrides.queue) } or {},
        ended = {},
        inputRestores = 0,
        animationsDone = 0,
        hidesFinished = 0,
        hiddenCalls = 0,
        touched = {},
        visibility = {},
        visibilityWrites = {},
        allWidgets = {},
        queueNudges = 0,
        tutorialCloses = {},
        subsystemMissing = overrides.subsystemMissing or false,
        widgetMissing = overrides.widgetMissing or false,
        endingClears = overrides.endingClears ~= false,
    }

    local function makeInfo(spec)
        return {
            IsValid = alwaysValid,
            GetAddress = function() return spec.address end,
            GetType = function() return spec.kind or "Infamy" end,
            ShouldBlockQueue = function() return spec.blocks ~= false end,
            ShouldCloseAutomatically = function() return spec.auto or false end,
            NotifyEnded = function()
                world.ended[#world.ended + 1] = spec.address
                if world.endingClears then table.remove(world.queue, 1) end
            end,
        }
    end

    local subsystem = {
        IsValid = alwaysValid,
        GetFullName = function() return "NotificationSubsystem /Game/World.Notifications" end,
        IsA = function(_, class) return class == "/Script/DogwoodUI.NotificationSubsystem" end,
        GetCurrentNotificationInfo = function()
            local spec = world.queue[1]
            if not spec then return nil end
            return makeInfo(spec)
        end,
        CanShowNotificationsNow = function() return #world.queue == 0 end,
        TryShowNotificationFromNonBlockingQueue = function() world.queueNudges = world.queueNudges + 1 end,
    }
    -- A toast that is NOT the Infamy popup; the recovery must not target it when the
    -- Infamy widget is present. This is the exact bug the live run exposed.
    local function makeWidget(fullName, isInfamy, displaying)
        local widget
        widget = {
            IsValid = alwaysValid,
            GetFullName = function() return fullName end,
            -- A pooled widget that never displayed anything has no CurrentNotification.
            -- Touching such a widget's hide functions crashes the real game.
            CurrentNotification = displaying and { IsValid = alwaysValid } or nil,
            GetVisibility = function() return world.visibility[fullName] or 0 end,
            IsVisible = function() return (world.visibility[fullName] or 0) == 0 end,
            State = 1,
            SetVisibility = function(_, value)
                world.visibility[fullName] = value
                world.visibilityWrites[#world.visibilityWrites + 1] = fullName
            end,
            RestoreInputConfig = function() world.inputRestores = world.inputRestores + 1; world.touched[#world.touched + 1] = fullName end,
            OnHideAnimationFinished = function() world.hidesFinished = world.hidesFinished + 1 end,
            OnNotificationHidden = function() world.hiddenCalls = world.hiddenCalls + 1 end,
        }
        if isInfamy then
            widget.OnAnimationsDone = function() world.animationsDone = world.animationsDone + 1 end
        end
        return widget
    end
    local toastWidget = makeWidget("WBP_NotificationPanel_Toast_Entry_C /Game.QuestComplete.ToastGold", false,
        overrides.toastDisplaying or false)
    local infamyWidget = makeWidget("WBP_NotificationPanel_Infamy_C /Game.HUD.WBP_NotificationPanel_Infamy", true,
        overrides.infamyDisplaying ~= false)
    world.allWidgets = { toastWidget, infamyWidget,
        { IsValid = alwaysValid,
          GetFullName = function() return "WBP_Hub_Court_C /Game.HUD.WBP_Hub_Court_C_2147469001" end,
          IsVisible = function() return true end },
        { IsValid = alwaysValid,
          GetFullName = function() return "WBP_Hidden_C /Game.HUD.WBP_Hidden_C_2147469002" end,
          IsVisible = function() return false end },
        { IsValid = alwaysValid,
          GetFullName = function() return "Default__WBP_Template_C /Game.Default__WBP_Template_C" end,
          IsVisible = function() return true end } }
    local tutorialSubsystem = {
        IsValid = alwaysValid,
        GetFullName = function() return "TutorialSubsystem /Game/World.Tutorial" end,
        IsA = function(_, class) return class == "/Script/DogwoodSystem.TutorialSubsystem" end,
        NotifyTutorialClosed = function(_, requestId) world.tutorialCloses[#world.tutorialCloses + 1] = requestId end,
    }

    local capturedPost
    local environment = setmetatable({
        FindFirstOf = function(name)
            if name == "NotificationSubsystem" and not world.subsystemMissing then return subsystem end
            if name == "TutorialSubsystem" then return tutorialSubsystem end
            return nil
        end,
        FindAllOf = function(name)
            if name == "UserWidget" then return world.allWidgets end
            if world.widgetMissing then return nil end
            -- The HUD reports the toast first, mirroring the live ordering.
            if name == "NotificationWidget" then return { toastWidget, infamyWidget } end
            if name == "InfamyNotificationWidget" then return { infamyWidget } end
            return nil
        end,
        print = function() end,
    }, { __index = _G })

    local module = assert(loadfile(path, "t", environment))()
    local menu = menuDouble()
    module.Init(menu, {}, {
        registerHook = function(_path, _pre, post)
            if overrides.hookThrows then error("hook rejected") end
            capturedPost = post
        end,
    })
    local function raiseTutorial(value) capturedPost(nil, { get = function() return value end }) end
    return menu, world, module, raiseTutorial
end

test("with nothing showing it says so rather than inventing a popup", function()
    local menu = fixture()
    menu.click("refresh")
    assert(menu.labels.status:find("No notification is currently on screen", 1, true), menu.labels.status)
end)

test("it describes the notification the game reports as current", function()
    local menu = fixture({ queue = { { address = 1, kind = "Infamy", blocks = true, auto = false } } })
    menu.click("refresh")
    assert(menu.labels.status:find("Infamy", 1, true), menu.labels.status)
    assert(menu.labels.status:find("blocks the queue: true", 1, true), menu.labels.status)
end)

test("dismissing ends the current notification and verifies it cleared", function()
    local menu, world = fixture({ queue = { { address = 7 } } })
    menu.click("dismiss")
    assert(#world.ended == 1 and world.ended[1] == 7, "NotifyEnded must target the current notification")
    assert(menu.labels.status:find("Verified", 1, true), menu.labels.status)
end)

test("dismissing with nothing on screen refuses instead of guessing", function()
    local menu, world = fixture()
    local ok = pcall(function() menu.click("dismiss") end)
    assert(not ok, "there is nothing to dismiss")
    assert(#world.ended == 0)
end)

test("a queued follow-up notification is reported, not called verified-clear", function()
    local menu, world = fixture({ queue = { { address = 1 }, { address = 2 } } })
    menu.click("dismiss")
    assert(#world.ended == 1)
    assert(menu.labels.status:find("next queued one", 1, true), menu.labels.status)
    assert(not menu.labels.status:find("nothing is on screen", 1, true))
end)

test("a notification that will not end is reported as still there", function()
    local menu, world = fixture({ queue = { { address = 3 } }, endingClears = false })
    local ok = pcall(function() menu.click("dismiss") end)
    assert(not ok, "an unchanged notification must not pass")
    assert(#world.ended == 1, "the end call is still made once")
    assert(menu.labels.status:find("kept the same notification", 1, true), menu.labels.status)
    assert(not menu.labels.status:find("Verified", 1, true), "must never claim Verified when nothing changed")
end)

test("force drives only the widget that is actually displaying", function()
    local menu, world = fixture()
    menu.click("force")
    assert(#world.touched == 1, "exactly one widget should be driven, got " .. #world.touched)
    assert(world.touched[1]:find("Infamy", 1, true), "the displaying widget must be the target, got " .. world.touched[1])
    assert(world.animationsDone == 1, "the Infamy-only animation step must run")
    assert(world.hidesFinished == 1 and world.hiddenCalls == 1 and world.inputRestores == 1,
        "the full hide and input-restore sequence must run")
end)

-- Regression for the crash: calling hide functions on a pooled widget that never
-- displayed anything dereferences a null and takes the game down with
-- EXCEPTION_ACCESS_VIOLATION. Nothing may be called in that case.
test("force calls NOTHING when no widget is displaying", function()
    local menu, world = fixture({ infamyDisplaying = false })
    menu.click("force")
    assert(#world.touched == 0, "no pooled widget may be touched")
    assert(world.hidesFinished == 0 and world.hiddenCalls == 0 and world.inputRestores == 0
        and world.animationsDone == 0, "no hide call may reach an idle pooled widget")
    assert(menu.labels.status:find("Nothing was called", 1, true), menu.labels.status)
end)

test("force never falls back to driving every pooled widget", function()
    local menu, world = fixture({ infamyDisplaying = false, toastDisplaying = false })
    menu.click("force")
    assert(#world.touched == 0, "there must be no try-them-all fallback")
end)

test("force refuses when no notification widget is live", function()
    local menu, world = fixture({ widgetMissing = true })
    local ok = pcall(function() menu.click("force") end)
    assert(not ok)
    assert(world.inputRestores == 0)
end)

test("listing reports only the displaying widget, with its real visibility", function()
    local menu = fixture()
    menu.click("widgets")
    assert(menu.labels.status:find("1 of 2 notification widgets displaying", 1, true), menu.labels.status)
    assert(menu.labels.status:find("Infamy", 1, true), menu.labels.status)
    assert(menu.labels.status:find("visibility Visible", 1, true), menu.labels.status)
end)

test("listing says so plainly when nothing is displaying", function()
    local menu = fixture({ infamyDisplaying = false })
    menu.click("widgets")
    assert(menu.labels.status:find("none is displaying", 1, true), menu.labels.status)
end)

test("collapse hides the displaying widget and verifies with GetVisibility", function()
    local menu, world = fixture()
    menu.click("collapse")
    assert(#world.visibilityWrites == 1, "only the displaying widget may be collapsed")
    assert(world.visibilityWrites[1]:find("Infamy", 1, true), world.visibilityWrites[1])
    assert(menu.labels.status:find("collapsed", 1, true), menu.labels.status)
end)

test("collapse touches nothing when no widget is displaying", function()
    local menu, world = fixture({ infamyDisplaying = false })
    menu.click("collapse")
    assert(#world.visibilityWrites == 0, "no pooled widget may have its visibility written")
    assert(menu.labels.status:find("Nothing was called", 1, true), menu.labels.status)
end)

test("the queue nudge calls the subsystem's own queue advance", function()
    local menu, world = fixture()
    menu.click("queue")
    assert(world.queueNudges == 1)
end)

test("a missing notification subsystem refuses rather than erroring blindly", function()
    local menu, world = fixture({ subsystemMissing = true })
    local ok = pcall(function() menu.click("refresh") end)
    assert(not ok)
    assert(#world.ended == 0)
end)

test("the tutorial fallback still needs a real raised request id", function()
    local menu, world, _, raiseTutorial = fixture()
    local refused = pcall(function() menu.click("close") end)
    assert(not refused, "no tutorial has been raised yet")
    raiseTutorial(88)
    menu.click("close")
    assert(#world.tutorialCloses == 1 and world.tutorialCloses[1] == 88)
end)

test("a new session forgets the previous tutorial id", function()
    local menu, world, module, raiseTutorial = fixture()
    raiseTutorial(5)
    module.ResetSession()
    local ok = pcall(function() menu.click("close") end)
    assert(not ok, "a stale id must not be reused")
    assert(#world.tutorialCloses == 0)
end)

test("the panel explains that the Edict popup is a notification", function()
    local menu = fixture()
    local text = table.concat(menu.plainLabels, " ")
    assert(text:find("notification, not a tutorial", 1, true), "the panel must state what the popup is: " .. text)
end)

test("the scan reports visible widgets and skips class defaults", function()
    local menu = fixture()
    menu.click("scan")
    assert(menu.labels.status:find("WBP_Hub_Court_C", 1, true), menu.labels.status)
    assert(not menu.labels.status:find("WBP_Hidden_C", 1, true), "an invisible widget must not be listed")
    assert(not menu.labels.status:find("Default__", 1, true), "class defaults must be skipped")
end)

test("the scan strips instance suffixes so repeats read cleanly", function()
    local menu = fixture()
    menu.click("scan")
    assert(not menu.labels.status:find("_C_2147469001", 1, true),
        "the instance suffix should be trimmed: " .. menu.labels.status)
end)

print(count .. " Stuck popup tests passed")
