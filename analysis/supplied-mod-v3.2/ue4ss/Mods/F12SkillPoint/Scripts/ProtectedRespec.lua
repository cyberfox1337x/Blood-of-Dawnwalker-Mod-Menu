-- Protected preservation with a current-cost refund for removed ranks only.
-- Historical/unexplained spent points are retained, never guessed into refunds.
-- No generic unlock-all, save writes, or idle polling.
local M={}
-- These five abilities come from Vrakhir blood or their dedicated quests rather
-- than an ordinary skill-point purchase. Keep the explicit IDs as a second
-- line of protection in case a game patch changes UnlockWithQuest metadata.
local protectedExplicitAbilities={
    CombatFocus_Explosion=true,               -- Blood Surge
    CombatFocus_Mesmerize=true,               -- Mesmerise
    CombatFocus_Passive_VrakhirShield=true,   -- Scarlet Shield
    CombatFocus_Scream=true,                  -- Piercing Shriek
    CombatFocus_ShadowStorm=true,             -- Shadowstorm
}
local ultimateAbilities={
    Human_CascadingHexes=true,                 -- Aether Cascade
    Human_DoubleCast=true,                     -- Entwined Torment
    Human_MagicShield=true,                    -- Runic Bulwark
    Shared_DeadlyReset=true,                   -- Sword Sage
    Shared_SwordExpert=true,                   -- Last Stand
    Shared_Tactician=true,                     -- Tactical Mastery
    Vampire_SecondChance=true,                 -- Renounce Death
    Vampire_SweetBlood=true,                   -- Sanguine Renewal
    Vampire_UnstoppableVrakhir=true,           -- Lethal Crescendo
}
-- These mappings are confirmed by aligning the sorted live KEEP list with the
-- trait audit. CombatFocus_ArcaneBoost is Mercurial Fervour (not Run Hex).
local minimalEssentialIds={
    CombatFocus_Necrospeak='compel',       -- Compel Soul
    CombatFocus_AoHActivator='astral',     -- Astral Communion
    CombatFocus_ShadowstepBite='bite',     -- Voracious Bite
    CombatFocus_ArcaneBoost='fervour',     -- Mercurial Fervour
    CombatFocus_WolfBoost='wolf',          -- Wolf Transform / Shapeshift
}
local minimalEssentialNames={
    -- Fail-safe fallbacks if a later build changes one of the confirmed IDs.
    compelsoul='compel',astralcommunion='astral',voraciousbite='bite',
    mercurialfervour='fervour',mercurialfervor='fervour',
    wolftransform='wolf',wolftransformation='wolf',shapeshift='wolf',
}
local minimalGroups={'compel','astral','bite','fervour','wolf'}
local function normalizedName(v) return tostring(v or ''):lower():gsub('[^%w]','') end
local function normalizeMode(mode)
    -- Preserve compatibility with the previous boolean API and its tests.
    if mode==nil or mode==false or mode=='light' then return 'light' end
    if mode==true or mode=='medium' then return 'medium' end
    assert(mode=='full','Unknown respec mode')
    return mode
end
local function unwrap(v)
    for _=1,4 do
        local ok,k=pcall(function() return v:type() end)
        if not ok or (k~='RemoteUnrealParam' and k~='LocalUnrealParam') then return v end
        v=v:get()
    end
    error('Unsupported wrapper depth')
end
local function integer(v,label)
    assert(type(v)=='number' and v>=0 and v%1==0,label..' invalid')
    return v
end
local function removedRankCost(r)
    if r.protected or r.level==0 then return 0 end
    local levels=r.trait.Levels
    assert(#levels>=r.level and #levels<=32,'Invalid rank cost list: '..r.id)
    local costs={}
    local function add(index,value)
        assert(type(index)=='number' and index>=1 and index%1==0,'Unexpected rank indexing')
        assert(costs[index]==nil,'Duplicate rank cost')
        costs[index]=integer(unwrap(unwrap(value).SkillPointsCost),'rank cost')
    end
    if type(levels)=='table' then for i=1,#levels do add(i,levels[i]) end else levels:ForEach(add) end
    local sum=0
    for i=1,r.level do assert(costs[i]~=nil,'Missing rank cost');sum=sum+costs[i] end
    return sum
end
local function plan(s)
    local refund=0
    for _,id in ipairs(s.order) do refund=refund+removedRankCost(s.rows[id]) end
    local conversion=math.max(0,refund-s.spent)
    local ledgerRefund=refund-conversion
    return {refund=refund,conversion=conversion,ledgerRefund=ledgerRefund,
        points=s.points+refund,basePoints=s.points+ledgerRefund,spent=s.spent-ledgerRefund}
end
local function snapshot(dev,mode)
    mode=normalizeMode(mode)
    local s={points=integer(dev:GetTraitPointAmount(),'points'),spent=integer(dev:GetSpentTraitPointAmount(),'spent'),
        rows={},order={},mode=mode}
    local all=dev:GetAllTraits()
    assert(#all>0 and #all<=1000,'Unexpected trait count')
    local minimalFound={}
    local function add(_,value)
        local t=unwrap(value)
        assert(t:IsValid(),'Invalid trait')
        local id=t.Skill_ID:ToString()
        assert(not s.rows[id],'Duplicate trait ID')
        local r={id=id,trait=t,level=integer(dev:GetTraitLevel(t),'rank'),
            history=integer(dev:GetOnceBoughtTraitLevel(t),'history'),
            unblocked=integer(dev:GetTraitUnblockedLevel(t.Skill_ID),'unlock'),
            fixed=t.AlwaysEquippedWithoutSlotCost,quest=t.UnlockWithQuest}
        assert(type(r.fixed)=='boolean' and type(r.quest)=='boolean','Missing protection flags')
        local nameOK,name=pcall(function() return t.LocalizedName:ToString() end)
        r.name=(nameOK and name and name~='' and not name:find('MISSING',1,true)) and name or id
        r.ultimate=ultimateAbilities[id]==true
        local minimalGroup=minimalEssentialIds[id] or minimalEssentialNames[normalizedName(r.name)]
        if minimalGroup then
            assert(not minimalFound[minimalGroup] or minimalFound[minimalGroup]==id,
                'Full Respec safety check found duplicate essential mapping: '..minimalGroup)
            minimalFound[minimalGroup]=id
        end
        if mode=='full' then
            r.protected=minimalGroup~=nil
        else
            r.protected=r.fixed or r.quest or protectedExplicitAbilities[id]==true
                or (r.ultimate and mode=='light')
        end
        s.rows[id]=r;s.order[#s.order+1]=id
    end
    if type(all)=='table' then for i=1,#all do add(i,all[i]) end else all:ForEach(add) end
    if mode=='full' then
        for _,group in ipairs(minimalGroups) do
            assert(minimalFound[group],
                'Full Respec safety check could not resolve essential ability group: '..group)
        end
    end
    table.sort(s.order)
    local parts={mode,tostring(s.points),tostring(s.spent)}
    for _,id in ipairs(s.order) do
        local r=s.rows[id]
        parts[#parts+1]=table.concat({id,r.name,r.level,r.history,r.unblocked,tostring(r.fixed),tostring(r.quest),tostring(r.ultimate),tostring(r.protected)},'|')
    end
    s.fingerprint=table.concat(parts,'\n')
    return s
end
function M.New(resolve,schedule,log,status)
    local armed,running,tainted=nil,false,false
    local api={}
    function api.Cancel()
        if running or tainted then return false end
        armed=nil
        return true
    end
    local function report(s,tag)
        log('PROTECTED_RESPEC '..tag..'\n'..s.fingerprint)
    end
    function api.Arm(mode)
        assert(not running,'A respec is already running.')
        assert(not tainted,'A previous respec mutation could not be verified. Restart and reload the clean save before retrying.')
        armed=nil
        local dev,identity=resolve()
        mode=normalizeMode(mode)
        local before=snapshot(dev,mode)
        local n=0
        local protectedNames={}
        for _,id in ipairs(before.order) do
            local r=before.rows[id]
            -- Never use purchase history to silently grant a previously removed ability.
            assert(not (r.protected and r.history>0 and r.level==0),
                'Previously earned protected ability missing: '..id..'. Reload an earlier save first.')
            if r.protected and r.level>0 then
                n=n+1
                protectedNames[#protectedNames+1]=string.format('%s (rank %d)',r.name,r.level)
            end
        end
        report(before,'ARM')
        local accounting=plan(before)
        armed={before=before,identity=identity,expires=os.time()+90,accounting=accounting,mode=mode}
        log(string.format('PROTECTED_RESPEC PLAN refund=%d ledgerRefund=%d conversion=%d targetPoints=%d remainingSpent=%d policy=current-cost-removed-ranks',accounting.refund,accounting.ledgerRefund,accounting.conversion,accounting.points,accounting.spent))
        return string.format('Refund: %d points | Available: %d -> %d%s. Confirm within 90 seconds.',accounting.refund,before.points,accounting.points,
                accounting.conversion>0 and string.format(' | Consumable conversion: %d',accounting.conversion) or ''),
            {protectedNames=protectedNames,remainingSpent=accounting.spent,conversion=accounting.conversion,
                refund=accounting.refund,spent=before.spent,mode=mode,
                includeUltimates=mode~='light'}
    end
    function api.Confirm(allowConversion)
        local a=armed;armed=nil
        assert(a and not running,'Generate a fresh refund preview before confirming.')
        assert(not tainted,'A previous respec mutation could not be verified. Restart and reload the clean save before retrying.')
        assert(os.time()<=a.expires,'Preview expired. Generate a new preview.')
        local dev,identity=resolve()
        assert(identity==a.identity,'Player/world changed')
        local before=snapshot(dev,a.mode)
        assert(before.fingerprint==a.before.fingerprint,'Your skill points or ranks changed. Generate a new preview.')
        local accounting=plan(before)
        assert(accounting.refund==a.accounting.refund,'Rank costs changed. Generate a new preview.')
        assert(accounting.conversion==0 or allowConversion==true,'Non-ledger upgrade conversion was not authorized.')
        local removable=false
        for _,id in ipairs(before.order) do if before.rows[id].level>0 and not before.rows[id].protected then removable=true end end
        assert(removable,'No ordinary purchased ranks to reset')
        running=true
        report(before,'BEFORE')
        local ticks,last,stable,phase=0,nil,0,'waiting'
        local ended=false
        local function fail(err)
            ended=true
            running=false;tainted=true
            log('PROTECTED_RESPEC FAILED: '..tostring(err))
            status('Respec could not be verified. Do NOT save or retry. Reload your pre-respec manual save. Details: UE4SS.log.')
        end
        local function check()
            if ended then return end
            local ok,err=pcall(function()
                ticks=ticks+1
                local currentDev,currentIdentity=resolve()
                assert(currentIdentity==a.identity,'Player/world changed during respec')
                local now=snapshot(currentDev,a.mode)
                assert(#now.order==#before.order,'Trait list changed')
                for _,id in ipairs(before.order) do assert(now.rows[id],'Trait disappeared: '..id) end
                if now.fingerprint==last then stable=stable+1 else stable=0 end
                last=now.fingerprint
                if phase=='waiting' then
                    local removed=false
                    for _,id in ipairs(before.order) do
                        if now.rows[id].level<before.rows[id].level then removed=true end
                    end
                    -- Wait for an actual delayed reset and a second stable sample.
                    if removed and stable>=1 then
                        report(now,'RESET_OBSERVED')
                        for _,id in ipairs(before.order) do
                            local old,new=before.rows[id],now.rows[id]
                            if new.unblocked<old.unblocked then
                                currentDev:UnblockTraitToLevel(new.trait.Skill_ID,old.unblocked,false,false)
                                log('PROTECTED_RESPEC RESTORE_UNLOCK '..id..' '..old.unblocked)
                            end
                            if old.protected and old.level>0 and new.level<old.level then
                                -- Restore only previously owned ranks. No parent or bought-event replay.
                                assert(currentDev:UnlockTrait(new.trait,old.level,false,false,false)==true,
                                    'Restore rejected: '..id)
                                log('PROTECTED_RESPEC RESTORE_RANK '..id..' '..old.level)
                            end
                        end
                        phase='verifying';stable=0;last=nil
                        status('Restoring earned abilities/unlocks; verifying. Do not spend points or save.')
                    end
                elseif stable>=3 then
                    for _,id in ipairs(before.order) do
                        local old,new=before.rows[id],now.rows[id]
                        assert(new.unblocked==old.unblocked,'Unlock limit mismatch: '..id)
                        if old.protected then assert(new.level==old.level,'Protected rank mismatch: '..id)
                        else assert(new.level==0,'Ordinary rank remains/was repurchased: '..id) end
                    end
                    if phase=='verifying' then
                        report(now,'PRESERVATION_VERIFIED')
                        -- Native reset refunds its entire historical ledger. Keep only the
                        -- refund for removed ranks, returning the excess to spent accounting.
                        assert(now.points+now.spent==before.points+before.spent,'Point budget changed during respec')
                        local excess=now.points-accounting.basePoints
                        assert(excess>=0,'Native refund below planned refund; no extra points will be invented')
                        assert(now.spent+excess==accounting.spent,'Unexpected spent ledger')
                        phase='accounting';stable=0;last=nil -- Set before the call: never retry it.
                        log(string.format('PROTECTED_RESPEC ACCOUNTING excess=%d conversion=%d targetPoints=%d targetSpent=%d',excess,accounting.conversion,accounting.points,accounting.spent))
                        if excess>0 then currentDev:SpendTraitPoints(excess) end
                        if accounting.conversion>0 then currentDev:ReceiveTraitPoints(accounting.conversion) end
                        status('Protection passed; verifying corrected refund. Do not spend points or save.')
                    else
                        assert(now.points==accounting.points and now.spent==accounting.spent,'Refund accounting verification failed')
                        report(now,'VERIFIED')
                        ended=true
                        running=false
                        status(string.format('Respec verified: +%d points (%d -> %d). Protected ranks and unlocks kept. Keep your backup; save into a NEW slot.',accounting.refund,before.points,now.points))
                        return
                    end
                end
                assert(ticks<30,'Timed out waiting for reset/preservation; no automatic retry')
                schedule(500,check)
            end)
            if not ok then fail(err) end
        end
        local ok,err=pcall(function()
            dev:ResetAllTraits()
            status('Reset requested. Waiting for delayed changes; do not spend points, save, or reload scripts.')
            schedule(500,check)
        end)
        if not ok then fail(err) end
    end
    return api
end
return M
