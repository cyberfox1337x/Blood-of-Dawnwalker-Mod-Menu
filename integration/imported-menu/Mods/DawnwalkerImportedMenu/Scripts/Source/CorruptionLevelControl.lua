local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("imported_CorruptionLevelControl")
-- Direct corruption-level control through the game's saved Vampire attributes.
local M={}

function M.Init(menu,getPlayer,getDevelopment,log,options)
    options=options or {}
    local ID='DWMutation'
    local tainted=false
    -- The Corruption values as they were the first time this session changed them, so a
    -- user who experiments can put the save back. Cleared on a session change so one
    -- save's values are never written into another.
    local original=nil
    local function valid(o) return o and o:IsValid() end
    local function finite(v) return type(v)=='number' and v==v and math.abs(v)<1000000 end
    local function status(message) menu.SetLabel(ID,'lastChange',message) end
    local function readAttribute(attribute,label)
        assert(attribute~=nil,label..' unavailable')
        local base,current=attribute.BaseValue,attribute.CurrentValue
        assert(finite(base) and finite(current),label..' contains invalid values')
        return base,current
    end
    local function controlledPlayer()
        local p=getPlayer(true)
        assert(valid(p) and valid(p:GetWorld()),'Load a save first')
        assert(valid(p.CombatComponent) and p.CombatComponent:IsAlive(),'Player must be alive')
        local controller=p.Controller
        assert(valid(controller) and valid(controller.Pawn)
            and controller.Pawn:GetAddress()==p:GetAddress(),'Controlled player mismatch')
        local combat=FindFirstOf('CombatSubsystem')
        assert(not valid(combat) or not combat:GetIsInCombat(),'Leave combat before setting Corruption level')
        return p
    end
    -- Record the pre-change values once per session. Reads only.
    local function captureOriginal(attributes)
        if original~=nil then return end
        local levelBase,levelCurrent=readAttribute(attributes.MutationLevel,'MutationLevel')
        local chargeBase,chargeCurrent=readAttribute(attributes.MutationCharged,'MutationCharged')
        original={levelBase=levelBase,levelCurrent=levelCurrent,
            chargeBase=chargeBase,chargeCurrent=chargeCurrent}
        menu.Set(ID,'owned',false)
        log(string.format('CORRUPTION_BASELINE level=%s charge=%.4f',tostring(levelCurrent),chargeCurrent))
    end

    -- Called before the raw-charge buttons mutate, so those are covered by the reset too.
    function M.NoteBaseline()
        if original~=nil then return end
        local ok,err=pcall(function()
            local p=getPlayer(true)
            if not (valid(p) and valid(p.VampireAttributeSet)) then return end
            captureOriginal(p.VampireAttributeSet)
        end)
        if not ok then log('CORRUPTION_BASELINE unavailable: '..tostring(err)) end
    end

    function M.ResetSession()
        original=nil
    end

    -- Put Corruption back to the values recorded at the first change this session.
    local function restoreOriginal()
        if tainted then
            status('Unavailable after a failed verification; reload your pre-change save and restart the game')
            return
        end
        if original==nil then
            status('No original Corruption recorded yet this session, so there is nothing to reset')
            return
        end
        ExecuteInGameThread(function()
            local ok,err=pcall(function()
                local p=controlledPlayer()
                local attributes=p.VampireAttributeSet
                assert(valid(attributes),'Vampire corruption attributes unavailable')
                local target=original
                local beforeLevel=readAttribute(attributes.MutationLevel,'MutationLevel')
                local identity=p:GetFullName()..'|'..tostring(p:GetAddress())..'|'..tostring(attributes:GetAddress())
                local wrote,writeError=pcall(function()
                    -- Zero the charge first for the same reason the setter does: a
                    -- leftover charge must not push the restored level straight back up.
                    attributes.MutationCharged.BaseValue=0
                    attributes.MutationCharged.CurrentValue=0
                    attributes.MutationLevel.BaseValue=target.levelBase
                    attributes.MutationLevel.CurrentValue=target.levelCurrent
                    attributes.MutationCharged.BaseValue=target.chargeBase
                    attributes.MutationCharged.CurrentValue=target.chargeCurrent
                    local dev=getDevelopment(true)
                    assert(valid(dev),'Character development subsystem unavailable')
                    assert(dev:GetCurrentMutationLevel()==target.levelCurrent,
                        'Game rejected the restored Corruption level')
                end)
                if not wrote then error(writeError) end
                log(string.format('CORRUPTION_RESET REQUEST level=%s->%s charge->%.4f',
                    tostring(beforeLevel),tostring(target.levelCurrent),target.chargeCurrent))
                status(string.format('Verifying restored Corruption level %s...',tostring(target.levelCurrent)))
                ExecuteWithDelay(500,function()
                    ExecuteInGameThread(function()
                        local verified,verifyError=pcall(function()
                            local current=getPlayer(true)
                            assert(valid(current) and valid(current.VampireAttributeSet),'Player changed during verification')
                            local currentIdentity=current:GetFullName()..'|'..tostring(current:GetAddress())..'|'
                                ..tostring(current.VampireAttributeSet:GetAddress())
                            assert(currentIdentity==identity,'Player changed during verification')
                            local dev=getDevelopment(true)
                            assert(valid(dev),'Character development subsystem unavailable')
                            assert(dev:GetCurrentMutationLevel()==target.levelCurrent,
                                'Restored Corruption level did not hold')
                        end)
                        if not verified then
                            tainted=true
                            status('Reset verification failed - do not save or retry; reload the pre-change save and restart')
                            log('CORRUPTION_RESET VERIFY_FAILED '..tostring(verifyError))
                            return
                        end
                        menu.Set(ID,'owned',false)
                        status(string.format('Verified: Corruption restored to level %s, charge %.2f',
                            tostring(target.levelCurrent),target.chargeCurrent))
                        log(string.format('CORRUPTION_RESET VERIFIED level=%s',tostring(target.levelCurrent)))
                        if options.refresh then options.refresh() end
                    end)
                end)
            end)
            if not ok then
                local clean=tostring(err):gsub('^.-:[0-9]+:%s*','')
                status('Could not reset Corruption: '..clean)
                log('CORRUPTION_RESET ERROR '..tostring(err))
            end
        end)
    end

    local function applyLevel()
        if tainted then
            status('Unavailable after a failed verification; reload your pre-change save and restart the game')
            return
        end
        ExecuteInGameThread(function()
            local ok,err=pcall(function()
                local target=math.max(1,math.min(15,math.floor(tonumber(menu.Get(ID,'level')) or 1)))
                local p=controlledPlayer()
                local attributes=p.VampireAttributeSet
                assert(valid(attributes),'Vampire corruption attributes unavailable')
                captureOriginal(attributes)
                local levelBase,levelCurrent=readAttribute(attributes.MutationLevel,'MutationLevel')
                local chargeBase,chargeCurrent=readAttribute(attributes.MutationCharged,'MutationCharged')
                assert(levelCurrent>=0 and levelCurrent<=15 and levelBase>=0 and levelBase<=15,
                    'Existing Corruption level is outside the verified 0–15 range')
                local identity=p:GetFullName()..'|'..tostring(p:GetAddress())..'|'..tostring(attributes:GetAddress())

                local function restore()
                    attributes.MutationLevel.BaseValue=levelBase
                    attributes.MutationLevel.CurrentValue=levelCurrent
                    attributes.MutationCharged.BaseValue=chargeBase
                    attributes.MutationCharged.CurrentValue=chargeCurrent
                end
                local wrote,writeError=pcall(function()
                    -- Zero charge first so a lower target cannot inherit enough progress
                    -- to immediately cross back into the next corruption level.
                    attributes.MutationCharged.BaseValue=0
                    attributes.MutationCharged.CurrentValue=0
                    attributes.MutationLevel.BaseValue=target
                    attributes.MutationLevel.CurrentValue=target
                    local dev=getDevelopment(true)
                    assert(valid(dev),'Character development subsystem unavailable')
                    assert(dev:GetCurrentMutationLevel()==target,'Game rejected the requested Corruption level')
                    assert(math.abs(dev:GetCurrentMutationCharges())<0.01,'Game rejected the fresh-level charge reset')
                end)
                if not wrote then
                    local restored,restoreError=pcall(restore)
                    if not restored then tainted=true;error(tostring(writeError)..'; rollback failed: '..tostring(restoreError)) end
                    error(writeError)
                end

                status(string.format('Verifying Corruption level %d…',target))
                log(string.format('CORRUPTION_LEVEL REQUEST level=%s->%d charge=%.4f->0 baseLevel=%s baseCharge=%s',
                    tostring(levelCurrent),target,chargeCurrent,tostring(levelBase),tostring(chargeBase)))
                ExecuteWithDelay(500,function()
                    ExecuteInGameThread(function()
                        local verified,verifyError=pcall(function()
                            local current=getPlayer(true)
                            assert(valid(current) and valid(current.VampireAttributeSet),'Player changed during verification')
                            local currentIdentity=current:GetFullName()..'|'..tostring(current:GetAddress())..'|'
                                ..tostring(current.VampireAttributeSet:GetAddress())
                            assert(currentIdentity==identity,'Player changed during verification')
                            local dev=getDevelopment(true)
                            assert(valid(dev),'Character development subsystem unavailable')
                            assert(dev:GetCurrentMutationLevel()==target,'Corruption level did not remain at the target')
                            assert(math.abs(dev:GetCurrentMutationCharges())<0.01,'Corruption charge did not remain at zero')
                        end)
                        if not verified then
                            tainted=true
                            status('Verification failed—do not save or retry; reload the pre-change save and restart')
                            log('CORRUPTION_LEVEL VERIFY_FAILED '..tostring(verifyError))
                            return
                        end
                        menu.Set(ID,'owned',original~=nil and original.levelCurrent~=target)
                        status(string.format('Level set to %d. Now press +1 raw charge (optionally -1 after), or drink blood, to refresh its effects',target))
                        log(string.format('CORRUPTION_LEVEL VERIFIED level=%d charge=0',target))
                        if options.onLevelChanged then options.onLevelChanged(target) end
                    end)
                end)
            end)
            if not ok then
                local clean=tostring(err):gsub('^.-:[0-9]+:%s*','')
                status('Could not set level: '..clean)
                log('CORRUPTION_LEVEL ERROR '..tostring(err))
            end
        end)
    end

    menu.Register({id=ID,title='☆ Corruption',tab='✦ Progression',collapsible=true,collapsed=true,items={
        {type='label',id='status',label='Corruption: load a save first'},
        {type='number',id='level',label='Corruption level',default=options.defaultLevel or 1,min=1,max=15,integer=true,
            onChange=function(v) if options.onLevelChanged then options.onLevelChanged(math.max(1,math.min(15,math.floor(tonumber(v) or 1)))) end end},
        {type='button',id='setLevel',label='Set exact Corruption level',variant='warning',confirm={
            title='Set Corruption level?',
            message='Sets the attained Corruption level directly and resets progress inside that level to zero. Afterward, press +1 raw charge (optionally -1 after), or drink blood, so the game refreshes the level effects. Lowering it does not reverse quests, dialogue, unlocks, achievements or other events already triggered by a higher level.',
            confirmLabel='Set level',cancelLabel='Cancel'},onClick=applyLevel},
        {type='label',label='IMPORTANT: after setting a level, press +1 raw charge (optionally -1 afterward), or drink blood, to refresh its gameplay effects.'},
        {type='label',label='Raw charge controls adjust progress within the current level. Start with 1.'},
        {type='number',id='amount',label='Corruption amount (raw units)',default=options.defaultAmount or 1,min=1,max=999,integer=true,
            onChange=function(v) if options.onAmountChanged then options.onAmountChanged(math.max(1,math.min(999,math.floor(tonumber(v) or 1)))) end end},
        {type='row',items={
            {type='button',id='add',label='Increase corruption',variant='warning',onClick=function()
                if options.changeRaw then options.changeRaw(math.max(1,math.min(999,math.floor(tonumber(menu.Get(ID,'amount')) or 1)))) end
            end},
            {type='button',id='remove',label='Reduce corruption charges',variant='secondary',onClick=function()
                if options.changeRaw then options.changeRaw(-math.max(1,math.min(999,math.floor(tonumber(menu.Get(ID,'amount')) or 1)))) end
            end},
        }},
        {type='row',items={
            {type='button',id='addOne',label='+1 raw charge',onClick=function() if options.changeRaw then options.changeRaw(1) end end},
            {type='button',id='removeOne',label='-1 raw charge',onClick=function() if options.changeRaw then options.changeRaw(-1) end end},
        }},
        {type='label',id='lastChange',label='No corruption changes made this session'},
        {type='button',id='resetOriginal',label="Reset Corruption to this session's original",variant='secondary',confirm={
            title='Reset Corruption?',
            message='Puts the Corruption level and raw charge back to the values recorded before your first change this session. It restores the numbers only: quests, dialogue, unlocks and achievements already triggered by a higher level are not reversed.',
            confirmLabel='Reset Corruption',cancelLabel='Cancel'},onClick=restoreOriginal},
        {type='checkbox',id='owned',label="Corruption differs from this session's original",value=false},
        {type='button',id='refresh',label='Refresh corruption status',onClick=options.refresh},
    }})
end

return M
