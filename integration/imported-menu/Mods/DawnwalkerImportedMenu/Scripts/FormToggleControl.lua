local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("dawnwalker_form_toggle_adapter")
-- Adapted from DawnwalkerFormToggle 0.3.0; see FORM_TOGGLE_LICENSE.txt.
local M, UEHelpers, menu = {}, nil, nil
local owner, hookSubsystem = nil, nil
local registeredHooks = {}
-- The Vampire form override checkbox and status are presented by the Player
-- controls panel; this module owns the behaviour but registers no section.
local SECTION = "DWCorePlayer"
-- This module does not own that panel, so presentation writes are attempted and
-- ignored when it is not registered (for example in isolation tests).
local function present(menu, method, item, value)
    pcall(function() menu[method](SECTION, item, value) end)
end

local MOD_NAME = "DawnwalkerFormToggle"
local MOD_VERSION = "0.3.0"

local FORM_POLICY = {
    AUTOMATIC = 0,
    FORCE_HUMAN = 1,
    FORCE_VAMPIRE = 2,
}

local DAY_PHASE = {
    DAY = 1,
    NIGHT = 2,
}

local QUICK_SLOT_NAMES = { "Bottom", "Left", "Right", "Top" }

local VAMPIRE_APPEARANCE_PATH = "/Game/_Dawnwalker/Characters/Appearance/Player/Appearance/7_APP_Vampire_Coen_PostQ101.7_APP_Vampire_Coen_PostQ101"

local cached_human_body = nil
local player_class = nil
local forced_ability_phase = nil

local function log(message)
    print(string.format("[%s] %s\n", MOD_NAME, message))
end

local function force_ability_lookup_phase(context, _, day_phase)
    if not forced_ability_phase or not owner or not owner.player:IsValid() then
        return
    end

    local current = UEHelpers.GetPlayer()
    if not current or not current:IsValid() or current:GetAddress() ~= owner.address then return end
    local target = context:get()
    if not target or not target:IsValid() or not hookSubsystem or not hookSubsystem:IsValid()
        or target:GetAddress() ~= hookSubsystem:GetAddress() then return end
    local requested_phase = day_phase:get()
    if requested_phase ~= forced_ability_phase then
        day_phase:set(forced_ability_phase)
    end
end

local function get_player()
    local ok, player = pcall(UEHelpers.GetPlayer)

    if not ok or not player or not player:IsValid() then
        log("No active local player pawn found. Load into gameplay and try again.")
        return nil
    end

    if not player_class or not player_class:IsValid() then
        player_class = StaticFindObject("/Script/Dawnwalker.DawnwalkerPlayerCharacter")
    end

    local class_ok, is_dawnwalker_player = pcall(function()
        return player_class and player_class:IsValid() and player:IsA(player_class)
    end)

    if not class_ok or not is_dawnwalker_player then
        log("The active local pawn is not a DawnwalkerPlayerCharacter. Load into gameplay and try again.")
        return nil
    end

    return player
end

local function object_name(object)
    if not object then
        return "<nil>"
    end

    local ok, value = pcall(function()
        return object:GetFullName()
    end)

    return ok and value or tostring(object)
end

local function report_form(player, prefix)
    local ok, is_vampire = pcall(function()
        return player:IsVampire()
    end)

    if ok then
        log(string.format("%s%s", prefix, is_vampire and "Vampire" or "Human"))
    else
        log(prefix .. "unknown (IsVampire call failed)")
    end
end

local function read_is_vampire(player)
    local ok, is_vampire = pcall(function()
        return player:IsVampire()
    end)

    if not ok then
        return nil
    end

    return is_vampire
end

local function begin_cosmetic_transition(player, becoming_vampire)
    local transition_name = becoming_vampire
        and "OnBeforeBecomingVampire"
        or "OnBeforeBecomingHuman"

    local ok, error_message = pcall(function()
        if becoming_vampire then
            player:OnBeforeBecomingVampire()
        else
            player:OnBeforeBecomingHuman()
        end
    end)

    if ok then
        log("Triggered cosmetic transition: " .. transition_name)
    else
        log(string.format("%s failed: %s", transition_name, tostring(error_message)))
    end

    return ok
end

local function get_appearance_component(player)
    local ok, component = pcall(function()
        return player.AppearanceComponent
    end)

    if not ok or not component or not component:IsValid() then
        log("Player AppearanceComponent is unavailable.")
        return nil
    end

    return component
end

local function current_body(component)
    if not component or not component:IsValid() then return nil end
    -- ApplyBody updates CurrentBody independently from the appearance asset.
    -- GetCurrentAppearance().BodyPreset can remain the original human descriptor.
    local ok, body = pcall(function() return component.CurrentBody end)
    if not ok or not body or not body:IsValid() then return nil end
    return body
end

local function body_from_appearance(appearance)
    if not appearance or not appearance:IsValid() then
        return nil
    end

    local ok, body = pcall(function()
        return appearance.BodyPreset
    end)

    if not ok or not body or not body:IsValid() then
        return nil
    end

    return body
end

local function apply_body(component, body, form_name)
    if not body or not body:IsValid() then
        log("No valid body preset was available for " .. form_name .. ".")
        return false
    end

    local ok, error_message = pcall(function()
        component:ApplyBody(body)
    end)

    if ok then
        log(string.format("Applied %s body preset: %s", form_name, object_name(body)))
    else
        log(string.format("ApplyBody for %s failed: %s", form_name, tostring(error_message)))
    end

    return ok, body
end

local function apply_form_appearance(player, becoming_vampire)
    local component = get_appearance_component(player)
    if not component then
        return false
    end


    if becoming_vampire then
        local body = current_body(component)
        if body and read_is_vampire(player) == false and not cached_human_body then
            cached_human_body = body
            log("Cached human body preset: " .. object_name(cached_human_body))
        end

        local vampire_appearance = StaticFindObject(VAMPIRE_APPEARANCE_PATH)
        if not vampire_appearance or not vampire_appearance:IsValid() then
            pcall(LoadAsset, VAMPIRE_APPEARANCE_PATH)
            vampire_appearance = StaticFindObject(VAMPIRE_APPEARANCE_PATH)
        end

        if not vampire_appearance or not vampire_appearance:IsValid() then
            log("Vampire appearance asset was not loaded: " .. VAMPIRE_APPEARANCE_PATH)
            return false
        end

        return apply_body(component, body_from_appearance(vampire_appearance), "Vampire")
    end

    local human_body = cached_human_body
    if not human_body or not human_body:IsValid() then
        local default_ok, default_appearance = pcall(function()
            return player.DefaultAppearance
        end)

        if default_ok then
            human_body = body_from_appearance(default_appearance)
        end
    end

    return apply_body(component, human_body, "Human")
end

local function get_live_hud_ability_quickslots()
    local widgets = FindAllOf("WBP_AA_Quickslots_C")
    if not widgets then
        return {}
    end

    local live_hud_widgets = {}
    for _, widget in ipairs(widgets) do
        if widget and widget:IsValid() then
            local name = object_name(widget)
            if string.find(name, "/Engine/Transient", 1, true)
                and string.find(name, "WBP_GameHUD_C", 1, true)
                and not string.find(name, "WBP_Hub_", 1, true) then
                table.insert(live_hud_widgets, widget)
            end
        end
    end

    return live_hud_widgets
end

local function refresh_ability_quickslots(lookup_phase, widget_phase, phase_name)
    local widgets = get_live_hud_ability_quickslots()
    if #widgets ~= 1 then
        log(string.format(
            "Ability wheel refresh skipped: expected one live HUD widget, found %d.",
            #widgets
        ))
        return false
    end

    local subsystem = FindFirstOf("CharacterDevelopmentQuickslotSubsystem")
    if not subsystem or not subsystem:IsValid() then
        log("Ability wheel refresh skipped: quickslot subsystem is unavailable.")
        return false
    end

    local widget = widgets[1]
    local ok, error_message = pcall(function()
        widget:SetPropertyValue("Day Phase", widget_phase)

        for _, slot_name in ipairs(QUICK_SLOT_NAMES) do
            local slot = widget:GetPropertyValue(slot_name)
            if not slot or not slot:IsValid() then
                error(slot_name .. " ability quickslot is unavailable")
            end

            local target_quickslot = slot:GetPropertyValue("TargetQuickslot")
            local ability = subsystem:GetAbilityInSlot(target_quickslot, lookup_phase)
            slot:SetPropertyValue("Day Phase", widget_phase)

            local set_ability = slot:GetPropertyValue("Set Ability")
            set_ability(slot, ability)
        end
    end)

    if not ok then
        log("Ability wheel refresh failed: " .. tostring(error_message))
        return false
    end

    log(string.format("Ability wheel synchronized to %s.", phase_name))
    return true
end

local function broadcast_equipment_phase(day_phase, phase_name)
    local time_system = FindFirstOf("TimeSystemImpl")
    if not time_system or not time_system:IsValid() then
        log("Equipment synchronization skipped: time system is unavailable.")
        return false
    end

    local delegate = time_system.OnDayPhaseChangedDynamicDelegate
    if not delegate then
        log("Equipment synchronization skipped: day-phase delegate is unavailable.")
        return false
    end

    local bindings = delegate:GetBindings()
    if not bindings or #bindings ~= 1 then
        log(string.format(
            "Equipment synchronization skipped for safety: expected one player subscriber, found %s.",
            bindings and tostring(#bindings) or "none"
        ))
        return false
    end

    local binding = bindings[1]
    local function_name = binding.FunctionName:ToString()
    local target_name = object_name(binding.Object)
    if function_name ~= "On Day Phase Changed"
        or not string.find(target_name, "BP_PlayerCharacter_C", 1, true) then
        log("Equipment synchronization skipped: the day-phase subscriber was not the player.")
        return false
    end

    delegate:Broadcast(day_phase)
    log(string.format("Equipment loadout synchronized to %s.", phase_name))
    return true
end

local function get_real_day_phase()
    local time_system = FindFirstOf("TimeSystemImpl")
    if not time_system or not time_system:IsValid() then
        return nil
    end

    local ok, segmented_time = pcall(function()
        return time_system:GetOffsetTime(0.0)
    end)
    if not ok or not segmented_time then
        return nil
    end

    local phase_ok, is_day = pcall(function()
        return segmented_time.bIsDay
    end)
    if not phase_ok then
        return nil
    end

    return is_day and DAY_PHASE.DAY or DAY_PHASE.NIGHT
end

local function synchronize_phase_state(requested_vampire)
    if requested_vampire ~= nil then
        local phase = requested_vampire and DAY_PHASE.NIGHT or DAY_PHASE.DAY
        local phase_name = requested_vampire and "Night" or "Day"
        forced_ability_phase = phase
        assert(broadcast_equipment_phase(phase, phase_name), "Equipment loadout synchronization failed.")
        assert(refresh_ability_quickslots(phase, phase, phase_name), "Ability wheel synchronization failed.")
        return
    end

    forced_ability_phase = nil
    local real_phase = get_real_day_phase()
    if not real_phase then
        error("Automatic loadout synchronization failed: current day phase unavailable.")
    end

    local phase_name = real_phase == DAY_PHASE.DAY and "Day (automatic)" or "Night (automatic)"
    assert(broadcast_equipment_phase(real_phase, phase_name), "Automatic equipment restoration failed.")
    assert(refresh_ability_quickslots(real_phase, 0, phase_name), "Automatic ability wheel restoration failed.")
end

local QUICKSLOT_HOOKS = { "GetAbilityInSlot", "GetLoadoutInfoInSlot" }
local QUICKSLOT_PATH = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentQuickslotSubsystem:"

local function ensure_hooks()
    for _, name in ipairs(QUICKSLOT_HOOKS) do
        if not registeredHooks[name] then
            local preId, postId = RegisterHook(QUICKSLOT_PATH .. name, force_ability_lookup_phase)
            registeredHooks[name] = { pre = preId, post = postId }
        end
    end
end

-- The game calls these while the ability wheel is up, so every frame they stay attached
-- costs a crossing into Lua for a callback that has nothing left to do. They used to be
-- registered once and kept for the rest of the session; now they are released the
-- moment the override stops needing them.
local function release_hooks()
    for _, name in ipairs(QUICKSLOT_HOOKS) do
        local ids = registeredHooks[name]
        if ids then
            registeredHooks[name] = nil
            local ok, failure = pcall(UnregisterHook, QUICKSLOT_PATH .. name, ids.pre, ids.post)
            if not ok then log("Quickslot hook release failed for " .. name .. ": " .. tostring(failure)) end
        end
    end
end

function M.Init(targetMenu, helpers, beforeFormChange)
    menu, UEHelpers = targetMenu, helpers
    local function set_enabled(enabled)
        assert(type(enabled) == "boolean", "Boolean form override required.")
        present(menu, "Set", "formOverride", owner ~= nil)
        local player = get_player()
        assert(player, "Load a controlled Dawnwalker player before changing form.")
        if owner and owner.address ~= player:GetAddress() then
            -- Never transfer a cached body or force policy to a replacement pawn.
            forced_ability_phase, hookSubsystem, cached_human_body = nil, nil, nil
            if owner.player:IsValid() then
                error("Previous player still owns the form override; return to that player or restart the game.")
            end
            owner = nil
            present(menu, "Set", "formOverride", false)
        end
        if enabled and owner and owner.confirmed then return end
        if not enabled and not owner then return end
        if beforeFormChange then beforeFormChange() end
        local was_vampire = read_is_vampire(player)
        assert(type(was_vampire) == "boolean", "Current form cannot be read.")
        if enabled then
            ensure_hooks()
            hookSubsystem = FindFirstOf("CharacterDevelopmentQuickslotSubsystem")
            assert(hookSubsystem and hookSubsystem:IsValid(), "Ability quickslot subsystem unavailable.")
            if not owner then
                cached_human_body = not was_vampire and current_body(get_appearance_component(player)) or nil
                assert(was_vampire or cached_human_body, "Current human body is unavailable; form change cancelled.")
                owner = { player = player, address = player:GetAddress(), confirmed = false }
            end
        end
        present(menu, "Set", "formOverride", true)
        local function run_verified(callback)
            local ok, failure = pcall(callback)
            if not ok then
                if owner then owner.confirmed = false end
                present(menu, "SetLabel", "formStatus", "Form change incomplete: " .. tostring(failure) .. " Switch OFF to retry automatic restoration.")
                error(failure)
            end
        end
        local function verify_player()
            local current = UEHelpers.GetPlayer()
            assert(owner and player:IsValid() and current and current:IsValid()
                and current:GetAddress() == owner.address, "Player changed before form verification.")
        end
        run_verified(function()
            if enabled and not was_vampire then
                assert(begin_cosmetic_transition(player, true), "Vampire cosmetic transition failed.")
            end
            player:SetFormSelectionPolicy(enabled and FORM_POLICY.FORCE_VAMPIRE or FORM_POLICY.AUTOMATIC)
            ExecuteWithDelay(1500, function()
                run_verified(function()
                    verify_player()
                    local actual = read_is_vampire(player)
                    assert(type(actual) == "boolean", "Form readback failed after selection.")
                    if enabled then assert(actual, "Game has not entered vampire form.") end
                    if not enabled and actual ~= was_vampire then
                        assert(begin_cosmetic_transition(player, actual), "Automatic cosmetic restoration failed.")
                    end
                    local applied, expectedBody = apply_form_appearance(player, actual)
                    assert(applied, "Form body application failed.")
                    local function verify_body(attempt)
                        run_verified(function()
                            verify_player()
                            local body = current_body(get_appearance_component(player))
                            local matches = body and body:GetAddress() == expectedBody:GetAddress()
                            if not matches and attempt < 20 then
                                -- Cold asset loading is asynchronous. Read only: never repeat ApplyBody.
                                ExecuteWithDelay(250, function() verify_body(attempt + 1) end)
                                return
                            end
                            assert(matches, "CurrentBody verification timed out; expected "
                                .. object_name(expectedBody) .. "; observed " .. object_name(body))
                            assert(read_is_vampire(player) == actual, "Form changed while loading its body.")
                            synchronize_phase_state(enabled and true or nil)
                            verify_player()
                            if enabled then
                                owner.confirmed = true
                                present(menu, "SetLabel", "formStatus", "Vampire form active; Night equipment and abilities selected.")
                            else
                                owner, cached_human_body, hookSubsystem = nil, nil, nil
                                -- Nothing left for the quickslot callback to decide, so
                                -- stop the game crossing into Lua for it every frame.
                                release_hooks()
                                present(menu, "Set", "formOverride", false)
                                present(menu, "SetLabel", "formStatus", "Automatic day/night selection restored. Current form: " .. (actual and "Vampire" or "Human") .. ".")
                            end
                        end)
                    end
                    verify_body(0)
                end)
            end)
        end)
    end
    function M.ResetSession()
        forced_ability_phase, hookSubsystem = nil, nil
        -- Released before the ownership check below, which can raise: hooks pointing at
        -- a session that is already gone must not outlive it either way.
        release_hooks()
        if owner and owner.player:IsValid() then
            error("Form override restoration remains unverified on the previous player; restart before further use.")
        end
        owner, cached_human_body = nil, nil
        present(menu, "Set", "formOverride", false)
        present(menu, "SetLabel", "formStatus", "OFF restores automatic day/night form. Use after unlocking both forms.")
    end
    function M.SetFormOverride(value)
        set_enabled(value == true)
    end
end
return M
