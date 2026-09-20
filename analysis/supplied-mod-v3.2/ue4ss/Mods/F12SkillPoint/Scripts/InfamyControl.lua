-- Native setters only; no recurring work or raw property writes.
local M = {}
function M.Register(menu)
    local id, busy, failed = "DWInfamyControl", false, false
    local function status(s) menu.SetLabel(id,"status",s) end
    local function change(delta)
        if busy or failed then return end
        busy = true
        ExecuteInGameThread(function()
            local issued = false
            local ok, err = pcall(function()
                local player = require("UEHelpers.UEHelpers").GetPlayer()
                assert(player and player:IsValid(),"Load a save first")
                local combat=player.CombatComponent
                assert(combat and combat:IsValid() and combat:IsAlive(),"Player must be alive")
                local combatSystem=FindFirstOf("CombatSubsystem")
                assert(combatSystem and combatSystem:IsValid() and not combatSystem:GetFullName():find("Default__",1,true),"Combat subsystem unavailable")
                assert(not combatSystem:GetIsInCombat(),"Leave combat before changing Infamy")
                local court=FindFirstOf("CourtSubsystem")
                assert(court and court:IsValid() and not court:GetFullName():find("Default__",1,true),"Court unavailable")
                local settings=StaticFindObject("/Script/DogwoodQuest.Default__CourtSettings")
                assert(settings and settings:IsValid(),"Court settings unavailable")
                local cap=tonumber(settings.MaxAlertLevel)
                local step=tonumber(court:GetSingleAlertThresholdBarValue())
                assert(cap==900 and step==100,"Infamy configuration changed; compatibility update required")
                local before=tonumber(court:GetAlertLevel())
                assert(before and before==math.floor(before) and before>=0 and before<=cap,"Invalid current Infamy")
                local target=math.max(0,math.min(cap,before+delta*step))
                if target==before then status("Already at the Infamy limit"); return end
                print(string.format("[DWInfamy] REQUEST before=%d target=%d\n",before,target))
                issued=true
                -- Native inspection: Drop negates its signed input, then routes to
                -- ChangeAlertLevelByInt (raw current + delta) and clamped raw setter.
                -- Negative drop therefore adds raw points. Never call milestone SetAlertLevel.
                court:DropAlertLevelByInt(before-target)
                local after=tonumber(court:GetAlertLevel())
                print(string.format("[DWInfamy] RESULT before=%d target=%d actual=%s\n",before,target,tostring(after)))
                assert(after==target,"Native result did not match requested Infamy; do not retry or save")
                status(string.format("Infamy %d -> %d. Check the Court screen and world effects.",before,after))
            end)
            busy=false
            if not ok then
                if issued then failed=true end
                print("[DWInfamy] ERROR "..tostring(err).."\n")
                status((issued and "STOP: reload your backup. " or "Blocked: ")..tostring(err))
            end
        end)
    end
    menu.Register({id=id,title="! Infamy",tab="☆ World",items={
        {type="label",id="status",label="Adjust by 100 points. Range: 0–900; partial progress is kept except at the limits."},
        {type="label",label="Changing Infamy may trigger world/quest events. Lowering it is not an undo."},
        {type="button",id="plus",label="Increase Infamy (+100 points)",confirm={title="Increase Infamy?",message="May trigger world or quest events. Keep your original backup save.",confirmLabel="Increase"},onClick=function() change(1) end},
        {type="button",id="minus",label="Decrease Infamy (-100 points)",confirm={title="Decrease Infamy?",message="Lowering Infamy does not undo existing world or quest events. Keep your backup.",confirmLabel="Decrease"},onClick=function() change(-1) end},
    }})
end
return M
