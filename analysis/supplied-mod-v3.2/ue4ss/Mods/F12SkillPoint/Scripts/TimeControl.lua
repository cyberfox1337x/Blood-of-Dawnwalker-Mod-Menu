-- v2 signed-segment experiment. No automatic advancement, rollback or repeating timer.
local M = {}
function M.Register(menu)
    local id = "DWTimeControl"
    local busy, used = false, false
    local function status(s) menu.SetLabel(id,"status",s) end
    local function log(s) print("[DWTime] "..s.."\n") end
    local function valid(o) return o and o:IsValid() end
    local function number(v)
        v=tonumber(v)
        assert(v and v==v and v~=math.huge and v~=-math.huge,"Invalid time value")
        return v
    end
    local function change(delta)
        assert(delta==1 or delta==-1,"Only single-segment changes supported")
        if busy then status("Wait for the previous change to finish verifying.");return end
        if used then status("Previous change failed verification. Reload your backup and restart before retrying.");return end
        busy=true
        ExecuteInGameThread(function()
            local ok,err=pcall(function()
                local helpers=require("UEHelpers.UEHelpers")
                local player=helpers.GetPlayer()
                assert(valid(player),"Load a save first")
                assert(valid(player.CombatComponent) and player.CombatComponent:IsAlive(),"Player must be alive")
                local combat=FindFirstOf("CombatSubsystem")
                assert(valid(combat) and not combat:GetFullName():find("Default__",1,true),"Combat subsystem unavailable")
                assert(not combat:GetIsInCombat(),"Leave combat before changing time")
                local state=helpers.GetGameStateBase()
                assert(valid(state),"Game state unavailable")
                local time=state.TimeSystem
                assert(valid(time) and not time:GetFullName():find("Default__",1,true),"Time system unavailable")
                assert(not time:IsPhaseTransitionQueuedOrInProgress(),"Day/night transition in progress")
                local config=StaticFindObject("/Script/DogwoodSystem.Default__DogwoodSystemSettings")
                assert(valid(config),"Time configuration unavailable")
                local segments=number(config.TimeSegmentsPer12H)
                local start=number(config.DaytimeStartHour)
                assert(segments==8 and start==8,"Time configuration changed; compatibility update required")
                local before=number(time:GetCurrentDayTimeAsFloat())
                local day=number(time:GetCurrentDay())
                assert(before>=0 and before<24,"Time getter is outside expected hour range")
                local unwrapped=before+delta*12/segments
                local expected=unwrapped%24
                local function phase(hour) return math.floor(((hour-start)%24)/12) end
                local crossing=unwrapped<0 or unwrapped>=24 or phase(before)~=phase(expected)
                assert(delta>0 or not crossing,"Rewind cannot cross a day/night boundary or midnight")
                local playerName, timeName=player:GetFullName(),time:GetFullName()
                local playerAddress,timeAddress=player:GetAddress(),time:GetAddress()
                log(string.format("REQUEST day=%s time=%s segments=%s predictedTime=%s",day,before,delta,expected))
                used=true -- Unlock only after matching readback; failures must not be retried.
                local accepted=time:AddTimeSegments(delta*1.0)
                log("NATIVE_RETURN "..tostring(accepted))
                status("One-segment request sent. Waiting for readback; do not save or load.")
                local attempts=0
                local function verify()
                    ExecuteInGameThread(function()
                        attempts=attempts+1
                        local pending=false
                        local verified,message=pcall(function()
                            local currentPlayer=helpers.GetPlayer()
                            local currentState=helpers.GetGameStateBase()
                            assert(valid(currentPlayer) and currentPlayer:GetFullName()==playerName and currentPlayer:GetAddress()==playerAddress,"Player changed during verification")
                            assert(valid(currentState) and valid(currentState.TimeSystem) and currentState.TimeSystem:GetFullName()==timeName and currentState.TimeSystem:GetAddress()==timeAddress,"Time system changed during verification")
                            local currentTime=currentState.TimeSystem
                            local after=number(currentTime:GetCurrentDayTimeAsFloat())
                            local afterDay=number(currentTime:GetCurrentDay())
                            local transitioning=currentTime:IsPhaseTransitionQueuedOrInProgress()
                            log(string.format("RESULT before=%s after=%s predicted=%s beforeDay=%s afterDay=%s transition=%s",before,after,expected,day,afterDay,tostring(transitioning)))
                            if transitioning then
                                assert(crossing and delta==1,"Unexpected transition during an in-phase change")
                                assert(attempts<30,"Transition did not finish within 30 checks")
                                pending=true
                                status("Day/night rollover in progress. Close the menu if needed; do not advance again or save/load.")
                                return
                            end
                            -- Observed AddTimeSegments(+1) returned false while advancing exactly
                            -- one segment. Boolean meaning is unknown; validate actual state instead.
                            assert(after>=0 and after<24 and math.abs(after-expected)<0.01,"Time change differs from predicted one segment")
                            -- Boundary day-counter convention is not yet gameplay calibrated.
                            -- Accept only unchanged/+1, report it explicitly, never write the day.
                            local dayChange=afterDay-day
                            assert((crossing and (dayChange==0 or dayChange==1)) or (not crossing and dayChange==0),"Unexpected day-counter change")
                            if crossing then
                                status(string.format("Rollover observed: hour %s -> %s; day counter %s -> %s. Check phase and days left before saving.",before,after,day,afterDay))
                            else
                                status(string.format("Readback matched: %s -> %s, day %s. Check the game's time display.",before,after,day))
                            end
                            used=false
                        end)
                        if verified and pending then ExecuteWithDelay(1000,verify);return end
                        busy=false
                        if not verified then log("VERIFY_FAILED "..tostring(message));status("STOP: do not save or retry. Reload an earlier save; check log.") end
                    end)
                end
                ExecuteWithDelay(1000,verify)
            end)
            if not ok then
                busy=false
                log("ERROR "..tostring(err))
                status((used and "STOP: reload an earlier save. " or "Blocked: ")..tostring(err))
            end
        end)
    end
    menu.Register({id=id,title="☆ Time Segments",tab="☆ World",items={
        {type="label",id="status",label="Add or remove one segment (1.5 game hours). Wait for each change to verify."},
        {type="label",label="Leave combat/dialogue/cutscenes. Turn cheats off. Time-sensitive quests may advance."},
        {type="button",id="advance",label="Advance 1 segment",confirm={title="Advance time by one segment?",message="Can roll into the next day/night and advance the campaign deadline or timed quests. Keep your backup. Wait for the transition and verification.",confirmLabel="Advance"},onClick=function() change(1) end},
        {type="button",id="rewind",label="Rewind 1 segment",confirm={title="Rewind time by one segment?",message="Changes the clock, not quest history. World events are not undone. Keep your backup and wait for verification.",confirmLabel="Rewind"},onClick=function() change(-1) end},
        {type="label",label="Forward can cross into later days. Rewind only changes slots within the current day/phase; it cannot return to a previous day or undo quests."},
    }})
end
return M
