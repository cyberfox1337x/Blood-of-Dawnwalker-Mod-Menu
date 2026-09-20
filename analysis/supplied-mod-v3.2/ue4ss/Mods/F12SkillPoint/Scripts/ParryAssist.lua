-- Attribute-based parry assist; not a universal defense hook.
local M={}
function M.Init(menu,getPlayer,log,directory)
    local id='DWParryAssist'
    local ledger=directory..'parry-session.ini'
    local enabled,owned=false,false
    local player,controller,combat,attributes,identity,original,timer
    local generation=0
    local function valid(o) return o and o:IsValid() end
    local function key(p,a)
        return p:GetFullName()..'|'..tostring(p:GetAddress())..'|'..tostring(p:GetWorld():GetAddress())..'|'..tostring(a:GetAddress())
    end
    local function value(a)
        local v=a.ChanceForApplyingParryOnBlock.CurrentValue
        assert(type(v)=='number' and v==v and v>=0 and v<=1,'Parry chance outside verified 0..1 scale')
        return v
    end
    local function record(text)
        local f=assert(io.open(ledger,'w'),'Cannot record parry restoration data')
        local ok,err=f:write(text or '');f:close();assert(ok,err)
    end
    local function status(s) menu.SetLabel(id,'status',s) end
    local function stop()
        enabled=false
        if timer then CancelDelayedAction(timer);timer=nil end
        menu.Set(id,'enabled',false)
        if owned then
            if valid(player) and valid(player:GetWorld()) and valid(attributes) and key(player,attributes)==identity then
                -- Preserve independently changed game/buff values rather than overwriting them.
                if value(attributes)==1 then
                    attributes.ChanceForApplyingParryOnBlock.CurrentValue=original
                    assert(value(attributes)==original,'Parry chance restore failed')
                end
            end
            record('');owned=false
        end
    end
    local function recover(p)
        local f=io.open(ledger,'r');if not f then return end
        local text=f:read('*a');f:close();if text=='' then return end
        local oldKey,oldValue=text:match('^(.-)\n([^\n]+)$')
        oldValue=tonumber(oldValue)
        assert(oldKey and oldValue and oldValue>=0 and oldValue<=1,'Invalid parry recovery record')
        local a=p.CharacterAttributeSet
        assert(valid(a) and valid(p:GetWorld()),'Recovery target unavailable')
        if key(p,a)==oldKey and value(a)==1 then
            a.ChanceForApplyingParryOnBlock.CurrentValue=oldValue
            assert(value(a)==oldValue,'Parry recovery failed')
        end
        record('')
    end
    local function tick()
        if not enabled then return end
        if not valid(player) or not valid(controller) or not valid(combat) or not valid(attributes) then stop();status('OFF: character unavailable');return end
        local pawn=controller.Pawn
        if not valid(pawn) or not valid(pawn:GetWorld()) or not valid(pawn.CharacterAttributeSet)
            or key(pawn,pawn.CharacterAttributeSet)~=identity or not combat:IsAlive() then
            stop();status('OFF: character changed or died');return
        end
        if value(attributes)~=1 then stop();status('OFF: game changed parry chance; not forcing it back') end
    end
    local function failure(err)
        local ok,restoreError=pcall(stop)
        status('OFF after error; see log')
        log('Parry assist: '..tostring(err))
        if not ok then log('Parry cleanup failed; reload backup and restart: '..tostring(restoreError)) end
    end
    local function toggle(on)
        generation=generation+1;local request=generation
        ExecuteInGameThread(function()
            if request~=generation then return end
            local ok,err=pcall(function()
                if not on then stop();status('OFF: mod-owned parry chance released');return end
                if enabled then return end
                local p=getPlayer(true);assert(valid(p) and valid(p:GetWorld()),'Load a save first')
                recover(p)
                local a,c,cc=p.CharacterAttributeSet,p.Controller,p.CombatComponent
                assert(valid(a) and valid(c) and valid(cc) and cc:IsAlive(),'Living player components required')
                assert(valid(c.Pawn) and c.Pawn:GetAddress()==p:GetAddress(),'Controlled player mismatch')
                local old=value(a)
                local base=a.ChanceForApplyingParryOnBlock.BaseValue
                player=p;attributes=a;controller=c;combat=cc;identity=key(p,a);original=old
                if old~=1 then
                    record(identity..'\n'..string.format('%.17g',original));owned=true
                    a.ChanceForApplyingParryOnBlock.CurrentValue=1
                    assert(value(a)==1,'Parry chance write did not stick')
                end
                enabled=true
                timer=LoopInGameThreadWithDelay(200,function() local passed,e=pcall(tick);if not passed then failure(e) end end)
                status('ON: hold right mouse to parry eligible blocked attacks.')
                log(string.format('Parry assist ON: current=%s -> 1, base=%s unchanged; no native hooks',tostring(old),tostring(base)))
            end)
            if not ok then failure(err) end
            menu.Set(id,'enabled',enabled)
        end)
    end
    M.Recover=function()
        if enabled then return end
        local p=getPlayer(true)
        if valid(p) then local ok,err=pcall(function() recover(p) end);if not ok then failure(err) end end
    end
    menu.Register({id=id,title='✦ Auto Parry',tab='♡ Player',items={
        {type='label',id='status',label='OFF. Enable to assist eligible blocks; disable to release the override.'},
        {type='checkbox',id='enabled',label='Auto parry while blocking',default=false,onChange=function(v) toggle(v==true) end},
        {type='label',label='Hold right mouse to block. WASD controls are unchanged. Not guaranteed for unblockable or wrong-direction attacks.'},
        {type='label',label='Turn OFF before saving, loading or reloading scripts. Save/reload persistence is not verified.'},
    }})
end
return M
