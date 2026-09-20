local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("tutorial_dismiss_control")

-- Recover from a popup the game has left on screen with input disabled.
--
-- WHAT THIS IS FOR
--
-- Raising the Infamy Level proclaims an Edict. On this build the Edict popup can be
-- left up with input dead: Tab does nothing and play is blocked until the game is
-- restarted.
--
-- WHAT IT ACTUALLY IS (established from the CL257186 dumps, see
-- Dawnwalker_RE/SYSTEM_STUDY_court_infamy_notifications.md)
--
-- It is NOT a tutorial. Hooking TutorialSchema:ShowTutorial across a full Infamy
-- level-up recorded zero events. It is a NOTIFICATION: the live widget is
-- WBP_NotificationPanel_Infamy_C inside the HUD's notification panel, driven by
-- NotificationSubsystem.
--
-- The correct chain, all of it the game's own API:
--   NotificationSubsystem:GetCurrentNotificationInfo() -> what is on screen
--   NotificationInfo:NotifyEnded()                     -> end it properly
--   NotificationInfo:ShouldBlockQueue()                -> whether it holds the queue
--   NotificationWidget:RestoreInputConfig()            -> give input back
--   NotificationSubsystem:TryShowNotificationFromNonBlockingQueue() -> nudge the queue
--
-- Because GetCurrentNotificationInfo is a real getter, dismissal is VERIFIABLE: the
-- current notification must clear or change. An earlier attempt used
-- InfamyNotificationWidget:OnAnimationsDone(), which reached the live widget but did
-- not clear the popup; that call is kept as a secondary recovery, clearly labelled.

local M = {}

local NOTIFICATION_SUBSYSTEM_CLASS = "/Script/DogwoodUI.NotificationSubsystem"
local TUTORIAL_SUBSYSTEM_CLASS = "/Script/DogwoodSystem.TutorialSubsystem"
local SHOW_TUTORIAL_PATH = "/Script/DogwoodSystem.TutorialSchema:ShowTutorial"

local function valid(object) return object ~= nil and object:IsValid() end

function M.Init(menu, helpers, hooks)
    local id = "DWTutorialDismiss"
    local lastTutorialRequest, tutorialsSeen, hookReady = nil, 0, false

    local function status(text) menu.SetLabel(id, "status", text) end

    -- Record every tutorial the game raises. Kept because other popups do use the
    -- tutorial system even though the Edict popup does not.
    local registered, hookError = pcall(function()
        hooks.registerHook(SHOW_TUTORIAL_PATH, function() end, function(_context, requestParameter)
            local ok, value = pcall(function()
                return tonumber(requestParameter and requestParameter:get())
            end)
            if ok and value then
                lastTutorialRequest, tutorialsSeen = value, tutorialsSeen + 1
                print(string.format("[DawnwalkerImportedMenu] Tutorial shown: request %s", tostring(value)))
            end
        end)
        hookReady = true
    end)
    if not registered then
        print("[DawnwalkerImportedMenu] Tutorial hook unavailable: " .. tostring(hookError))
    end

    local function notificationSubsystem()
        local object = FindFirstOf("NotificationSubsystem")
        assert(valid(object) and not object:GetFullName():find("Default__", 1, true),
            "Notification subsystem unavailable in this session.")
        assert(object:IsA(NOTIFICATION_SUBSYSTEM_CLASS), "Resolved object is not the notification subsystem.")
        return object
    end

    -- The identity of the notification on screen, or nil when nothing is showing.
    -- Returns the object and a stable address so a change can be detected.
    local function currentNotification(subsystem)
        local ok, info = pcall(function() return subsystem:GetCurrentNotificationInfo() end)
        if not ok then
            print("[DawnwalkerImportedMenu] Current notification unreadable: " .. tostring(info))
            return nil, nil
        end
        if not valid(info) then return nil, nil end
        return info, info:GetAddress()
    end

    local function describeNotification(info)
        local parts = {}
        local function optional(name, reader)
            local ok, value = pcall(reader)
            if ok and value ~= nil then parts[#parts + 1] = string.format("%s: %s", name, tostring(value)) end
        end
        optional("type", function() return info:GetType() end)
        optional("blocks the queue", function() return info:ShouldBlockQueue() end)
        optional("closes automatically", function() return info:ShouldCloseAutomatically() end)
        if #parts == 0 then return "a notification is on screen" end
        return "on screen - " .. table.concat(parts, "; ")
    end

    local function refresh()
        local ok, message = pcall(function()
            local subsystem = notificationSubsystem()
            local info = currentNotification(subsystem)
            local canShow = select(2, pcall(function() return subsystem:CanShowNotificationsNow() end))
            local tutorialPart = hookReady
                and string.format(" Tutorials raised this session: %d.", tutorialsSeen)
                or " The tutorial hook is unavailable."
            if not info then
                return string.format("No notification is currently on screen.%s", tutorialPart)
            end
            return string.format("Notification %s. Can show more: %s.%s",
                describeNotification(info), tostring(canShow), tutorialPart)
        end)
        if not ok then status("Unavailable: " .. tostring(message)); error(message) end
        status(message)
    end

    -- End the notification the game says is current, then prove it changed.
    local function dismissNotification()
        local subsystem = notificationSubsystem()
        local info, beforeAddress = currentNotification(subsystem)
        assert(info, "No notification is on screen, so there is nothing to dismiss.")
        local description = describeNotification(info)
        info:NotifyEnded()
        print("[DawnwalkerImportedMenu] NotifyEnded sent to notification " .. tostring(beforeAddress))
        local _, afterAddress = currentNotification(subsystem)
        if afterAddress == nil then
            status("Verified: the notification ended and nothing is on screen now. If input is still stuck, press Restore input.")
            return
        end
        if afterAddress ~= beforeAddress then
            status("The notification ended and the next queued one is now showing. Press Dismiss again to clear it too.")
            return
        end
        status("The game kept the same notification on screen (" .. description .. "). Try Restore input, then Dismiss again.")
        error("Notification did not change after NotifyEnded")
    end

    -- Collect the live notification widgets. FindFirstOf is not usable here: the HUD
    -- holds several NotificationWidget instances (quest-complete toasts among them) and
    -- the first one found is usually NOT the Infamy popup. InfamyNotificationWidget
    -- inherits NotificationWidget, so the Infamy instance also carries the hide and
    -- input-restore calls.
    local function notificationWidgets()
        local found, seen = {}, {}
        for _, className in ipairs({ "InfamyNotificationWidget", "NotificationWidget" }) do
            local ok, list = pcall(function() return FindAllOf(className) end)
            if ok and type(list) == "table" then
                for _, widget in ipairs(list) do
                    local usable = valid(widget) and not widget:GetFullName():find("Default__", 1, true)
                    if usable then
                        local name = widget:GetFullName()
                        if not seen[name] then
                            seen[name] = true
                            found[#found + 1] = { widget = widget, name = name,
                                isInfamy = name:find("Infamy", 1, true) ~= nil }
                        end
                    end
                end
            end
        end
        return found
    end

    -- Is this widget actually displaying something?
    --
    -- CRITICAL SAFETY CHECK. The HUD keeps a POOL of notification widgets - 36 were
    -- observed live, and the list is identical whether or not a popup is on screen.
    -- Most have never been shown and hold no CurrentNotification. Calling their hide
    -- or input-restore functions dereferences that null and crashes the game with
    -- EXCEPTION_ACCESS_VIOLATION reading address 0x38 (observed 2026-09-09).
    --
    -- pcall CANNOT protect against this: an access violation is not a Lua error. The
    -- only safe approach is to read CurrentNotification first and skip any widget that
    -- does not have one.
    local function isDisplaying(widget)
        local ok, current = pcall(function() return widget.CurrentNotification end)
        return ok and valid(current)
    end

    -- ESlateVisibility, /Script/UMG. Collapsed is what the game uses to take a widget
    -- out of the layout entirely.
    local SLATE_VISIBILITY = { [0] = "Visible", [1] = "Collapsed", [2] = "Hidden",
        [3] = "HitTestInvisible", [4] = "SelfHitTestInvisible" }
    local COLLAPSED = 1

    local function describeVisibility(widget)
        local parts = {}
        local ok, visibility = pcall(function() return widget:GetVisibility() end)
        if ok then
            local numeric = tonumber(visibility)
            parts[#parts + 1] = "visibility " .. (numeric and (SLATE_VISIBILITY[numeric] or numeric) or tostring(visibility))
        end
        local visibleOk, visible = pcall(function() return widget:IsVisible() end)
        if visibleOk then parts[#parts + 1] = "IsVisible " .. tostring(visible) end
        local stateOk, state = pcall(function() return widget.State end)
        if stateOk and state ~= nil then parts[#parts + 1] = "State " .. tostring(state) end
        return table.concat(parts, ", ")
    end

    -- Report only the widgets that are actually displaying, with their real visibility.
    -- Listing all 36 pooled widgets is noise; what matters is which one is on screen.
    local function listWidgets()
        local widgets = notificationWidgets()
        if #widgets == 0 then status("No notification widgets exist in this session."); return end
        local shown = {}
        for _, entry in ipairs(widgets) do
            if isDisplaying(entry.widget) then
                local short = entry.name:match("([^%.]+)$") or entry.name
                shown[#shown + 1] = string.format("%s (%s)", short, describeVisibility(entry.widget))
                print(string.format("[DawnwalkerImportedMenu] Displaying widget %s: %s",
                    entry.name, describeVisibility(entry.widget)))
            end
        end
        if #shown == 0 then
            status(string.format("%d pooled notification widgets exist; none is displaying anything.", #widgets))
            return
        end
        status(string.format("%d of %d notification widgets displaying: %s",
            #shown, #widgets, table.concat(shown, "; ")))
    end

    -- Read-only scan of every UserWidget the game currently has, reporting the ones
    -- that are actually visible.
    --
    -- This exists because guessing at widget classes was wrong twice: the Edict popup
    -- is not a TutorialSchema tutorial, and collapsing the Infamy notification widget
    -- did not remove it either. Rather than guess a third time, enumerate what is on
    -- screen and let the game name it.
    --
    -- Only base UMG.Widget calls are used (GetFullName, IsVisible, GetVisibility).
    -- Nothing subclass-specific is touched, so this cannot repeat the pooled-widget
    -- crash, which came from calling notification-specific functions on idle widgets.
    local function scanVisibleWidgets()
        local ok, list = pcall(function() return FindAllOf("UserWidget") end)
        assert(ok and type(list) == "table", "The game returned no widget list to scan.")
        local visible, total = {}, 0
        for _, widget in ipairs(list) do
            if valid(widget) then
                local nameOk, name = pcall(function() return widget:GetFullName() end)
                if nameOk and not name:find("Default__", 1, true) then
                    total = total + 1
                    local visibleOk, isVisible = pcall(function() return widget:IsVisible() end)
                    if visibleOk and isVisible then
                        local short = name:match("([^%.]+)$") or name
                        -- Strip the instance suffix so repeated classes read cleanly.
                        short = short:gsub("_C_%d+$", "_C")
                        visible[#visible + 1] = short
                        print("[DawnwalkerImportedMenu] VISIBLE widget: " .. name)
                    end
                end
            end
        end
        if #visible == 0 then
            status(string.format("Scanned %d widgets; none reports itself visible.", total))
            return
        end
        -- Keep the status line readable; the full list goes to the log.
        local shown = {}
        for index = 1, math.min(#visible, 14) do shown[index] = visible[index] end
        status(string.format("%d of %d widgets visible: %s%s. Full list in the log.",
            #visible, total, table.concat(shown, ", "),
            #visible > #shown and (" (+" .. (#visible - #shown) .. " more)") or ""))
    end

    -- Collapse the displaying widget outright and prove it with GetVisibility.
    -- Used when the notification has already ended but its widget is still drawn.
    local function collapseWidget()
        local widgets = notificationWidgets()
        local targets = {}
        for _, entry in ipairs(widgets) do
            if isDisplaying(entry.widget) then targets[#targets + 1] = entry end
        end
        if #targets == 0 then
            status("No notification widget is displaying, so there is nothing to collapse. Nothing was called.")
            return
        end
        local results = {}
        for _, entry in ipairs(targets) do
            local before = describeVisibility(entry.widget)
            entry.widget:SetVisibility(COLLAPSED)
            local okAfter, after = pcall(function() return tonumber(entry.widget:GetVisibility()) end)
            local short = entry.name:match("([^%.]+)$") or entry.name
            if okAfter and after == COLLAPSED then
                results[#results + 1] = short .. " collapsed"
            else
                results[#results + 1] = string.format("%s did NOT collapse (%s)", short,
                    okAfter and tostring(SLATE_VISIBILITY[after] or after) or "unreadable")
            end
            print(string.format("[DawnwalkerImportedMenu] Collapse %s: before %s; after %s",
                entry.name, before, describeVisibility(entry.widget)))
        end
        status("Collapse: " .. table.concat(results, "; ") .. ". Check the game.")
    end

    -- Walk a widget through its own hide sequence and give input back. Only ever called
    -- for a widget that passed isDisplaying.
    local function forceHideWidget(entry)
        local applied, failed = {}, {}
        local steps = {
            { name = "OnAnimationsDone", infamyOnly = true },
            { name = "OnHideAnimationFinished" },
            { name = "OnNotificationHidden" },
            { name = "RestoreInputConfig" },
        }
        for _, step in ipairs(steps) do
            if not (step.infamyOnly and not entry.isInfamy) then
                local ok, err = pcall(function() entry.widget[step.name](entry.widget) end)
                if ok then applied[#applied + 1] = step.name
                else failed[#failed + 1] = step.name end
                if not ok then
                    print(string.format("[DawnwalkerImportedMenu] %s failed on %s: %s",
                        step.name, entry.name, tostring(err)))
                end
            end
        end
        print(string.format("[DawnwalkerImportedMenu] Force-hide %s: applied %s; unavailable %s",
            entry.name, table.concat(applied, ","), table.concat(failed, ",")))
        return applied, failed
    end

    -- Act ONLY on widgets that are genuinely displaying a notification. There is
    -- deliberately no "try them all" fallback: doing that crashed the game, because the
    -- pool is full of widgets that were never shown.
    local function forcePopupClosed()
        local widgets = notificationWidgets()
        assert(#widgets > 0, "No notification widgets exist in this session.")
        local targets = {}
        for _, entry in ipairs(widgets) do
            if isDisplaying(entry.widget) then targets[#targets + 1] = entry end
        end
        if #targets == 0 then
            status(string.format(
                "None of the %d pooled notification widgets is currently displaying anything, so there is nothing safe to close. Nothing was called.",
                #widgets))
            return
        end
        local total, names = 0, {}
        for _, entry in ipairs(targets) do
            local applied = forceHideWidget(entry)
            total = total + #applied
            names[#names + 1] = entry.name:match("([^%.]+)$") or entry.name
        end
        status(string.format("Ran the hide and input-restore sequence on %d displaying widget(s) (%s); %d call(s) accepted. Check the game.",
            #targets, table.concat(names, ", "), total))
    end

    local function nudgeQueue()
        local subsystem = notificationSubsystem()
        subsystem:TryShowNotificationFromNonBlockingQueue()
        status("Asked the queue to move on. Press Check to see what is on screen now.")
    end

    local function closeTutorial()
        assert(hookReady, "The tutorial hook is unavailable, so no request id was recorded.")
        assert(lastTutorialRequest ~= nil, "No tutorial has been raised this session.")
        local object = FindFirstOf("TutorialSubsystem")
        assert(valid(object) and object:IsA(TUTORIAL_SUBSYSTEM_CLASS), "Tutorial subsystem unavailable.")
        object:NotifyTutorialClosed(lastTutorialRequest)
        status(string.format("Sent close for tutorial request %s.", tostring(lastTutorialRequest)))
    end

    function M.ResetSession()
        lastTutorialRequest, tutorialsSeen = nil, 0
    end

    menu.Register({ id = id, title = "Stuck popup", tab = "☆ World", items = {
        { type = "label", id = "status", label = "Use this if a popup will not close and the game stops responding." },
        { type = "button", id = "refresh", label = "Check what is on screen", onClick = refresh },
        { type = "button", id = "dismiss", label = "Dismiss the popup", variant = "success", onClick = dismissNotification },
        { type = "button", id = "force", label = "Force the popup closed", variant = "warning", onClick = forcePopupClosed },
        { type = "label", label = "Dismiss ends the notification the game reports as current. Force runs the widget's own hide sequence and input restore, for when the notification already ended but the popup is still on screen." },
        { type = "button", id = "collapse", label = "Collapse the popup widget", variant = "warning", onClick = collapseWidget },
        { type = "label", label = "Collapse hides the widget outright and confirms it with the game's own visibility reading. Use it when the notification has already ended but the popup is still drawn." },
        { type = "button", id = "widgets", label = "Show which widget is displaying", onClick = listWidgets },
        { type = "button", id = "scan", label = "Scan every visible widget", onClick = scanVisibleWidgets },
        { type = "label", label = "Scan is read-only. Use it when a popup is stuck to find out which widget is actually on screen instead of guessing." },
        { type = "button", id = "queue", label = "Nudge the notification queue", onClick = nudgeQueue },
        { type = "button", id = "close", label = "Close a stuck tutorial", onClick = closeTutorial },
        { type = "label", label = "The last three are fallbacks. The Edict popup is a notification, not a tutorial, so Dismiss is the one that applies to it." },
    } })

    return M
end

return M
