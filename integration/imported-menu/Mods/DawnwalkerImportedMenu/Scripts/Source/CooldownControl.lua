local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("imported_CooldownControl")
-- Player-local cooldown reset. No global lookups in the recurring callback.
local M={}
function M.Init(menu,getPlayer,log)
    local ID='DWCooldownControl'
    local enabled=false
    local timer,player,controller,combat,focus,address
    local generation=0
    local function valid(o) return o and o:IsValid() end
    local function status(s) menu.SetLabel(ID,'status',s) end
    local function stop()
        enabled=false
        if timer then CancelDelayedAction(timer);timer=nil end
        player=nil;controller=nil;combat=nil;focus=nil;address=nil
        menu.Set(ID,'enabled',false)
    end
    local function tick()
        if not enabled then return end
        if not valid(player) or not valid(controller) or not valid(combat) or not valid(focus) then
            stop();status('OFF: player components unavailable');return
        end
        local pawn=controller.Pawn
        if not valid(pawn) or pawn:GetAddress()~=address or not combat:IsAlive() then
            stop();status('OFF: controlled character changed or died');return
        end
        -- Native function confirmed in the patched game's reflected API.
        -- Clears existing timers; does not change ability costs or unlocks.
        focus:ResetCooldowns()
    end
    local function safeTick()
        local ok,err=pcall(tick)
        if not ok then stop();status('OFF after an error; see log');log('Cooldown reset error: '..tostring(err)) end
    end
    local function toggle(on)
        generation=generation+1
        local request=generation
        ExecuteInGameThread(function()
            if request~=generation then return end
            local ok,err=pcall(function()
                if not on then stop();status('OFF: normal cooldowns resume on future uses');return end
                if enabled then stop() end
                local p=getPlayer(true)
                assert(valid(p),'Load a save first')
                local c,cc,cf=p.Controller,p.CombatComponent,p.CombatFocusComponent
                assert(valid(c) and valid(cc) and valid(cf),'Live combat components unavailable')
                assert(cc:IsAlive(),'A living player is required')
                assert(valid(c.Pawn) and c.Pawn:GetAddress()==p:GetAddress(),'Controlled player mismatch')
                local fn=StaticFindObject('/Script/DogwoodCombat.CombatFocusComponent:ResetCooldowns')
                assert(valid(fn),'Cooldown reset API unavailable on this build')
                player=p;controller=c;combat=cc;focus=cf;address=p:GetAddress()
                enabled=true
                tick()
                if not enabled then return end
                timer=LoopInGameThreadWithDelay(250,function()
                    if request==generation then safeTick() end
                end)
                status('Cooldown reset: ON')
                log('Cooldown reset ON: cached player only, 250ms interval; gameplay verification pending')
            end)
            if not ok then stop();status('Unavailable: '..tostring(err));log('Cooldown toggle: '..tostring(err)) end
            menu.Set(ID,'enabled',enabled)
        end)
    end
    menu.Register({id=ID,title='☆ Ability Cooldowns',tab='♡ Player',items={
        {type='label',id='status',label='Cooldown reset: OFF'},
        {type='checkbox',id='enabled',label='No ability cooldown (quick reset)',default=false,onChange=function(v) toggle(v==true) end},
        {type='label',label='Quickly clears cooldowns. Charge, blood and item costs still apply.'},
    }})
    M._tick=safeTick
end
return M
