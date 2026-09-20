-- Native controls discovered in Steam build 25014996. No cheats auto-enable.
local M={}
function M.Init(menu,getPlayer,log,directory)
    local ID,WORLD='DWCombatControls','DWShrines'
    local path=directory..'combat-session.ini'
    local state={target='',god=false,stamina=false,cooldown=false,originalCooldown=true,backend='continuous'}
    local busy=false
    local tickHandle=nil
    local cachedPlayer,cachedCombat,cachedController=nil,nil,nil
    local cacheTicks=0
    local requestVersion=0
    local function stopTick()
        if tickHandle then CancelDelayedAction(tickHandle);tickHandle=nil end
        cachedPlayer=nil;cachedCombat=nil;cachedController=nil;cacheTicks=0
    end
    local function valid(o) return o and o:IsValid() end
    local function subsystem(name)
        -- Refuse ambiguous instances, rather than selecting a template or old world.
        local result=nil
        for _,o in ipairs(FindAllOf(name) or {}) do
            if valid(o) and not o:GetFullName():find('Default__',1,true) then
                if result then error('Multiple live '..name..' instances') end
                result=o
            end
        end
        if not result then error(name..' unavailable') end
        return result
    end
    local function persist()
        local f=assert(io.open(path,'w'),'Cannot record toggle ownership')
        for _,key in ipairs({'target','god','stamina','cooldown','originalCooldown','backend'}) do
            f:write(key..'='..tostring(state[key])..'\n')
        end
        f:close()
    end
    do
        local f=io.open(path,'r')
        if f then
            state.backend='legacy'
            for line in f:lines() do
                local k,v=line:match('^(%w+)=(.*)$')
                if k=='target' or k=='backend' then state[k]=v
                elseif k and type(state[k])=='boolean' then state[k]=v=='true' end
            end
            f:close()
        end
    end
    local needsRecovery=state.god or state.stamina or state.cooldown
    local function sync()
        for _,key in ipairs({'god','stamina','cooldown'}) do menu.Set(ID,key,state[key]) end
    end
    local function recover(p)
        if not needsRecovery then return end
        -- Restore only locks this mod recorded for this exact pawn. On a new
        -- game process / respawn, do not touch another character's state.
        if state.target==p:GetFullName() and state.backend=='legacy' then
            local c=p.CombatComponent
            if not valid(c) then error('Combat component unavailable for cleanup') end
            if state.god then c:UnlockHealth();state.god=false;persist() end
            if state.stamina then c:UnlockStamina();state.stamina=false;persist() end
            if state.cooldown then
                local s=subsystem('FocusAbilitiesSubsystem')
                if s:AreCooldownsEnabled_Debug()~=state.originalCooldown then s:ToggleDisablingAllCooldowns_Debug() end
                state.cooldown=false;persist()
            end
        end
        state.god=false;state.stamina=false;state.cooldown=false
        state.target=p:GetFullName();state.backend='continuous';persist();needsRecovery=false;sync()
        log('Combat controls: recovered prior mod-owned locks; toggles OFF')
    end
    local function enforce()
        if needsRecovery or not state.stamina then return end
        -- No UEHelpers.GetPlayer / FindAllOf / StaticFindObject in the timer.
        -- Resolve once at toggle-on; all recurring work uses those cached objects.
        if not valid(cachedPlayer) or not valid(cachedCombat) or not valid(cachedController) then
            state.god=false;state.stamina=false;state.cooldown=false
            stopTick();persist();sync()
            return
        end
        cacheTicks=cacheTicks+1
        if cacheTicks>=4 then
            cacheTicks=0
            -- Direct pointer-property read, not an object-array search. Check for
            -- possession/save transitions at 2.5 Hz instead of scanning every tick.
            local controlled=cachedController.Pawn
            if not valid(controlled) or controlled:GetFullName()~=state.target or not cachedCombat:IsAlive() then
                state.stamina=false;stopTick();persist();sync();return
            end
        end
        if cachedCombat:GetStaminaPercentage()<0.995 then cachedCombat:SetStaminaPercent(1.0) end
    end
    local function safeTick()
        local ok,err=pcall(enforce)
        if not ok then
            state.god=false;state.stamina=false;state.cooldown=false
            stopTick();pcall(persist);sync()
            menu.SetLabel(ID,'status','Stamina stopped after an error; see log')
            log('Cached stamina control error: '..tostring(err))
        end
    end
    M._tick=safeTick
    local function run(section,fn)
        if busy then sync();return end
        busy=true
        ExecuteInGameThread(function()
            local ok,err=pcall(function()
                local p=getPlayer(true)
                if not p then error('Load a save first') end
                recover(p)
                fn(p)
            end)
            busy=false
            if not ok then
                local friendly=tostring(err):gsub('^.-:%d+:%s*','')
                menu.SetLabel(section,'status','Unavailable: '..friendly)
                log('Combat controls error: '..tostring(err))
            end
            sync()
        end)
    end
    local function toggle(key,on)
        if key~='stamina' then
            state[key]=false;sync()
            menu.SetLabel(ID,'status','Health/cooldown automation paused for performance investigation')
            return
        end
        requestVersion=requestVersion+1
        local requestedVersion=requestVersion
        if not on then
            -- Stop before any queued lookup, so OFF takes effect immediately.
            state.stamina=false;stopTick();persist();sync()
            menu.SetLabel(ID,'status','Stamina OFF — no recurring combat-control timer')
            log('Cached stamina OFF: timer cancelled')
            return
        end
        run(ID,function(p)
            if requestedVersion~=requestVersion then return end
            if state.target~=p:GetFullName() then
                state.target=p:GetFullName();state.god=false;state.stamina=false;state.cooldown=false
            end
            if state[key]==on then return end
            local c=p.CombatComponent
            if not valid(c) or not c:IsAlive() then error('A living controlled character is required') end
            local controller=p.Controller
            if not valid(controller) then error('Player controller unavailable') end
            stopTick()
            cachedPlayer=p;cachedCombat=c;cachedController=controller
            c:SetStaminaPercent(1.0)
            state.backend='continuous';state.stamina=true
            tickHandle=LoopInGameThreadWithDelay(100,safeTick)
            persist()
            menu.SetLabel(ID,'status',on and 'Stamina refill: ON' or 'Stamina refill: OFF')
            log('Cached stamina ON: 100ms timer, no repeated player-controller searches')
        end)
    end
    menu.Register({id=ID,title='☆ Stamina',tab='♡ Player',items={
        {type='label',id='status',label='Stamina refill: OFF'},
        {type='checkbox',id='stamina',label='Rapid stamina refill',default=false,onChange=function(v) toggle('stamina',v==true) end},
        {type='label',label='Continuously refills stamina. Re-enable after respawning.'},
    }})
    menu.Register({id=WORLD,title='❀ Fast Travel Shrines',tab='✦ Progression',collapsible=true,collapsed=true,items={
        {type='label',id='status',label='Permanent unlock. Cheats will trigger achievements.'},
        {type='button',id='unlock',label='Unlock all shrine travel points',variant='warning',
            confirm={title='Unlock every shrine travel point?',message='This permanently changes your save and will trigger achievements. There is no menu undo. Proceed?',confirmLabel='Unlock shrines'},
            onClick=function()
                run(WORLD,function()
                    if subsystem('CombatSubsystem'):GetIsInCombat() then error('Leave combat before unlocking shrines') end
                    local journal=subsystem('OpenWorldJournalImpl')
                    local lib=StaticFindObject('/Script/DogwoodMap.Default__MappinSystemBlueprintLibrary')
                    if not valid(lib) then error('Map library unavailable') end
                    lib:DebugUnlockAllFastTravelDestinations(journal)
                    menu.SetLabel(WORLD,'status','Unlock request sent. Reopen the shrine map to verify.')
                    log('Shrine unlock requested by confirmed menu action; map verification required')
                end)
            end},
    }})
    local protectedRespec=nil
    local pendingConversion=0
    local previewRefund,previewSpent=0,0
    local previewMode='light'
    local function ensureProtectedRespec()
        if protectedRespec then return end
        protectedRespec=require('ProtectedRespec').New(function()
            local current=getPlayer(true)
            local dev=subsystem('CharacterDevelopmentSubsystem')
            local combat=subsystem('CombatSubsystem')
            assert(valid(current) and valid(current.Controller),'Player/world unavailable')
            local pawn=current.Controller.Pawn
            assert(valid(pawn) and pawn:GetFullName()==current:GetFullName(),'Controlled player mismatch')
            assert(valid(current.CombatComponent) and current.CombatComponent:IsAlive(),'Player is not alive')
            assert(not combat:GetIsInCombat(),'Leave combat before respec')
            return dev,current:GetFullName()..'|'..dev:GetFullName()
        end,function(ms,fn)
            ExecuteWithDelay(ms,function() ExecuteInGameThread(fn) end)
        end,log,function(message) menu.SetLabel('DWRespec','status',message) end)
    end
    local function armRespec(mode,statusPrefix,keepLabel)
        run('DWRespec',function()
            ensureProtectedRespec()
            local message,preview=protectedRespec.Arm(mode)
            pendingConversion=preview.conversion or 0
            previewRefund,previewSpent=preview.refund or 0,preview.spent or 0
            previewMode=mode
            menu.SetLabel('DWRespec','status',statusPrefix..message)
            menu.SetLabel('DWRespec','protected',keepLabel..':\n'..table.concat(preview.protectedNames,'\n')..'\nRemaining spent ledger: '..preview.remainingSpent)
        end)
    end
    menu.Register({id='DWRespec',title='✦ Skill Respec',tab='✦ Progression',collapsible=true,items={
        {type='label',label='Light keeps Ultimates and earned protected abilities. Medium also removes Ultimates. Full restores only Compel Soul, Astral Communion, Voracious Bite, Mercurial Fervour and Wolf Transform after the native reset.'},
        {type='label',label='All modes preserve trait unlock-access bookkeeping. Full may still leave game-native survivors such as Font of Life or Mandrake Ward if ResetAllTraits does not clear them.'},
        {type='label',label='Before starting: create a separate manual save, leave combat, and turn cheats OFF. Do not spend points, save, or reload scripts while respec runs.'},
        {type='label',label='Refund policy: current costs of removed ranks only. Protected ranks and unexplained historical spent points are not refunded.'},
        {type='label',id='status',label='Ready to preview. No skills change until you confirm.'},
        {type='label',id='protected',label='Protected abilities: generate a preview to see your list.'},
        {type='button',id='armLight',label='Preview Light Respec',onClick=function()
            armRespec('light','LIGHT RESPEC — ','KEEP')
        end},
        {type='button',id='armMedium',label='Preview Medium Respec',variant='warning',onClick=function()
            armRespec('medium','MEDIUM RESPEC — Ultimates will be removed. ','KEEP (Ultimates excluded)')
        end},
        {type='button',id='armFull',label='Preview Full Respec',variant='danger',onClick=function()
            armRespec('full','FULL RESPEC — only five essential abilities will be restored. ','KEEP (essential five only)')
        end},
        {type='button',id='confirm',label='Confirm respec (changes skills)',onClick=function()
            run('DWRespec',function()
                assert(protectedRespec,'Preview your refund first.')
                local function perform() protectedRespec.Confirm(pendingConversion>0) end
                if previewMode=='full' and pendingConversion==0 then
                    menu.Confirm({
                        title='Full Respec — keep only five essentials?',
                        message='This removes every resettable learned rank, including Ultimates, boss-blood, quest and manual-granted abilities. Only Compel Soul, Astral Communion, Voracious Bite, Mercurial Fervour and Wolf Transform will be restored. Font of Life, Mandrake Ward or other game-native survivors may remain if the game reset does not clear them. Continue?',
                        confirmLabel='Full respec',cancelLabel='Cancel',variant='danger',
                        onConfirm=function() run('DWRespec',perform) end,
                    })
                elseif previewMode=='medium' and pendingConversion==0 then
                    menu.Confirm({
                        title='Medium Respec including Ultimates?',
                        message='This removes ordinary purchased ranks and learned Ultimates. Essential, boss-blood, quest and manual-granted abilities remain protected. Continue?',
                        confirmLabel='Medium respec',cancelLabel='Cancel',variant='danger',
                        onConfirm=function() run('DWRespec',perform) end,
                    })
                elseif pendingConversion>0 then
                    local conversion=pendingConversion
                    local modeWarning=previewMode=='full'
                        and 'Full Respec will remove every resettable rank except the five named essentials.\n\n'
                        or (previewMode=='medium' and 'Medium Respec will also remove every learned Ultimate.\n\n' or '')
                    menu.Confirm({
                        title='Convert non-skill-point upgrades?',
                        message=string.format('%sThe removed ranks currently cost %d skill points, but this save records only %d spent skill points. The %d-point difference may represent upgrades obtained through legendary consumables or earned abilities included by this respec mode.\n\nContinuing will convert that difference into %d skill points. Consumed upgrade items will not be restored. This cannot be undone without reloading your backup save.',modeWarning,previewRefund or 0,previewSpent or 0,conversion,conversion),
                        confirmLabel='Convert and respec',cancelLabel='Cancel',variant='danger',
                        onConfirm=function() run('DWRespec',perform) end,
                    })
                else perform() end
            end)
        end},
        {type='button',id='cancel',label='Cancel preview',onClick=function()
            if not protectedRespec or protectedRespec.Cancel() then
                pendingConversion=0;previewRefund=0;previewSpent=0;previewMode='light'
                menu.SetLabel('DWRespec','status','Preview cancelled. No skills changed.')
                menu.SetLabel('DWRespec','protected','Protected abilities: generate a preview to see your list.')
            end
        end},
        {type='label',label='If verification fails: do NOT save or retry. Reload your pre-respec manual save. Preserve UE4SS.log for diagnosis.'},
        {type='label',label='Successful respecs may be repeated. An unverified mutation blocks retries until restart.'},
    }})
    -- Recovery only; never automatically enables a cheat or unlocks anything.
    ExecuteWithDelay(1000,function() run(ID,function() end) end)
    log('Combat controls v3 loaded: NO idle timer; cached stamina only; health/cooldown automation paused')
end
return M
