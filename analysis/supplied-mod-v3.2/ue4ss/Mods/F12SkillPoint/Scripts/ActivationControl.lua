-- Native charge override. No global searches inside the timer.
local M={}
function M.Init(menu,getPlayer,log,directory)
    local ID='DWActivationControl'
    local timer,player,controller,focus,combat,attributes=nil,nil,nil,nil,nil,nil
    local enabled,applied=false,false
    local appliedCap=nil
    local target=''
    local generation=0
    local ledger=directory..'activation-session.ini'
    local function valid(o) return o and o:IsValid() end
    local function status(s) menu.SetLabel(ID,'status',s) end
    local function record(value)
        local f=assert(io.open(ledger,'w'),'Cannot record charge override ownership')
        f:write(value or '');f:close()
    end
    local function clearOverride()
        if applied then
            if valid(focus) then focus:ResetSlotsChargedOverride() end
            record('');applied=false;appliedCap=nil
        end
    end
    local function stop()
        enabled=false
        if timer then CancelDelayedAction(timer);timer=nil end
        clearOverride()
        menu.Set(ID,'enabled',false)
    end
    local function tick()
        if not enabled then return end
        if not valid(player) or not valid(controller) or not valid(focus)
            or not valid(combat) or not valid(attributes) then stop();status('OFF: character changed');return end
        local pawn=controller.Pawn
        if not valid(pawn) or pawn:GetFullName()~=target then stop();status('OFF: controlled character changed');return end
        if not player.CombatComponent:IsAlive() then stop();status('OFF: player is not alive');return end
        if not combat:GetIsInCombat() then
            if applied then clearOverride();status('ON: waiting for combat') end
            return
        end
        local cap=tonumber(attributes.UnlockedActionSlots.CurrentValue)
        if not cap or cap~=cap or cap<=0 or cap>100 then clearOverride();status('Waiting for a valid charge cap');return end
        if not applied or appliedCap~=cap then
            -- Record first so a hot reload can remove an outstanding override.
            record(target)
            applied=true
            focus:SetSlotsChargedOverride(cap)
            appliedCap=cap
            status(string.format('ON: keeping %.0f activation charges full',cap))
            log(string.format('Activation override applied to controlled player: cap=%.2f',cap))
        end
    end
    local function safeTick()
        local ok,err=pcall(tick)
        if not ok then
            local clean,cleanupError=pcall(stop)
            status('Stopped after an error; see log')
            log('Activation override error: '..tostring(err))
            if not clean then log('Activation cleanup failed; restart game: '..tostring(cleanupError)) end
        end
    end
    M._tick=safeTick
    local function recover(p)
        local f=io.open(ledger,'r')
        if not f then return end
        local old=f:read('*a');f:close()
        if old=='' then return end
        if old==p:GetFullName() then
            local component=p.CombatFocusComponent
            if not valid(component) then error('Charge component unavailable for reload cleanup') end
            component:ResetSlotsChargedOverride()
        end
        record('')
    end
    local function toggle(on)
        generation=generation+1
        local request=generation
        ExecuteInGameThread(function()
            if request~=generation then return end
            local ok,err=pcall(function()
                if not on then stop();status('Activation charge refill: OFF');return end
                if enabled then return end
                local p=getPlayer(true)
                if not p then error('Load a save first') end
                recover(p)
                local c=p.Controller
                local cf=p.CombatFocusComponent
                local a=p.CharacterAttributeSet
                if not valid(c) or not valid(cf) or not valid(a) then error('Live player components unavailable') end
                local found=nil
                for _,s in ipairs(FindAllOf('CombatSubsystem') or {}) do
                    if valid(s) and not s:GetFullName():find('Default__',1,true) then
                        if found then error('Multiple combat subsystems; refusing ambiguous target') end
                        found=s
                    end
                end
                if not found then error('Combat subsystem unavailable') end
                player=p;controller=c;focus=cf;combat=found;attributes=a;target=p:GetFullName()
                enabled=true
                status('ON: waiting for combat')
                tick()
                if enabled then timer=LoopInGameThreadWithDelay(200,safeTick) end
            end)
            if not ok then
                pcall(stop)
                local clean=tostring(err):gsub('^.-:[0-9]+:%s*','')
                status('Unavailable: '..clean)
                log('Activation toggle: '..tostring(err))
            end
            menu.Set(ID,'enabled',enabled)
        end)
    end
    menu.Register({id=ID,title='✦ Activation Charges',tab='♡ Player',items={
        {type='label',id='status',label='Activation charge refill: OFF'},
        {type='checkbox',id='enabled',label='Quick fill activation charge',default=false,onChange=function(v) toggle(v==true) end},
        {type='label',label='Keeps activation charges full during combat, up to your unlocked limit.'},
    }})
    -- Read/cleanup on menu open, not a startup polling loop.
    M.Recover=function()
        if enabled then return end
        local p=getPlayer(true)
        if p then local ok,err=pcall(recover,p);if not ok then log('Activation recovery: '..tostring(err)) end end
    end
    log('Activation controls loaded: combat-transition override; OFF by default')
end
return M
