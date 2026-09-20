-- Unsupported player-only damage gate retained solely for state cleanup.
local M={}
function M.Init(menu,getPlayer,log,directory,hideUI)
    local ID='DWGodMode'
    local ledger=directory..'god-session.ini'
    local enabled,owned=false,false
    local player,controller,combat,timer,identity,original
    local generation=0
    local function valid(o) return o and o:IsValid() end
    local function key(p)
        return p:GetFullName()..'|'..tostring(p:GetAddress())..'|'..tostring(p:GetWorld():GetAddress())
    end
    local function record(s)
        local f=assert(io.open(ledger,'w'),'Cannot record god-mode ownership')
        assert(f:write(s or ''));f:close()
    end
    local function flag(p)
        local v=p.bCanBeDamaged
        assert(type(v)=='boolean','Damage flag is not a reflected boolean on this build')
        return v
    end
    local function status(s) menu.SetLabel(ID,'status',s) end
    local function stop()
        enabled=false
        if timer then CancelDelayedAction(timer);timer=nil end
        menu.Set(ID,'enabled',false)
        if owned then
            if valid(player) and valid(player:GetWorld()) and key(player)==identity then
                -- Do not overwrite an independently changed value.
                if flag(player)==false then
                    player.bCanBeDamaged=original
                    assert(flag(player)==original,'Damage flag restore did not stick')
                end
            end
            record('');owned=false
        end
    end
    local function recover(p)
        local f=io.open(ledger,'r');if not f then return end
        local saved=f:read('*a');f:close()
        if saved=='' then return end
        local oldKey,oldValue=saved:match('^(.-)\n(%a+)$')
        assert(oldKey and (oldValue=='true' or oldValue=='false'),'Invalid god-mode recovery record')
        if key(p)==oldKey and flag(p)==false then
            p.bCanBeDamaged=oldValue=='true'
            assert(flag(p)==(oldValue=='true'),'God-mode reload recovery failed')
        end
        record('')
    end
    local function tick()
        if not enabled then return end
        if not valid(player) or not valid(controller) or not valid(combat) then
            stop();status('OFF: character unavailable');return
        end
        local pawn=controller.Pawn
        if not valid(pawn) or not valid(pawn:GetWorld()) or key(pawn)~=identity or not combat:IsAlive() then
            stop();status('OFF: character changed or died');return
        end
        if flag(player)~=false then
            stop();status('OFF: game changed the damage flag; not forcing it back');return
        end
    end
    local function safeTick()
        local ok,err=pcall(tick)
        if not ok then
            local clean,cleanupError=pcall(stop)
            status('OFF after error; see log')
            log('God mode: '..tostring(err))
            if not clean then log('God mode cleanup failed; restart game: '..tostring(cleanupError)) end
        end
    end
    local function toggle(on)
        generation=generation+1
        local requested=generation
        ExecuteInGameThread(function()
            if requested~=generation then return end
            local ok,err=pcall(function()
                if not on then stop();status('OFF: original damage flag restored');return end
                if enabled then return end
                local p=getPlayer(true);assert(valid(p),'Load a save first')
                assert(valid(p:GetWorld()),'Player world unavailable')
                recover(p)
                local c,cc=p.Controller,p.CombatComponent
                assert(valid(c) and valid(cc) and cc:IsAlive(),'Living controlled player required')
                assert(valid(c.Pawn) and key(c.Pawn)==key(p),'Controlled player mismatch')
                player=p;controller=c;combat=cc;identity=key(p);original=flag(p)
                -- Persist before mutation; preserve pre-existing invulnerability.
                record(identity..'\n'..tostring(original));owned=true
                p.bCanBeDamaged=false
                assert(flag(p)==false,'Damage flag write did not stick')
                enabled=true
                timer=LoopInGameThreadWithDelay(500,safeTick)
                status('ON: damage flag OFF. Enemy-hit verification required.')
                log('God mode ON: player damageable=false; prior='..tostring(original))
            end)
            if not ok then
                local clean,cleanupError=pcall(stop)
                status('Unavailable: '..tostring(err));log('God mode toggle: '..tostring(err))
                if not clean then log('God mode cleanup failed; restart game: '..tostring(cleanupError)) end
            end
            menu.Set(ID,'enabled',enabled)
        end)
    end
    M.Recover=function()
        if enabled then return end
        local p=getPlayer(true)
        if valid(p) and valid(p:GetWorld()) then
            local ok,err=pcall(function() recover(p) end)
            if not ok then status('Recovery failed; restart game');log(tostring(err)) end
        end
    end
    if not hideUI then
    menu.Register({id=ID,title='♡ God Mode — damage prevention',tab='♡ Player',items={
        {type='label',id='status',label='OFF. Player-only damage flag; no health refill.'},
        {type='checkbox',id='enabled',label='God mode',default=false,onChange=function(v) toggle(v==true) end},
        {type='label',label='Enemy hit reactions may remain.'},
        {type='label',label='OFF restores the original flag. Turn OFF before reloading/uninstalling.'},
    }})
    end
    M._tick=safeTick
end
return M
