local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("imported_UltimateResearch")
-- Exact Ultimate controls. No idle polling and no high-frequency UI hooks.
local M={}

local ultimates={
    {label='Witchcraft — Aether Cascade',id='Human_CascadingHexes'},
    {label='Witchcraft — Entwined Torment',id='Human_DoubleCast'},
    {label='Witchcraft — Runic Bulwark',id='Human_MagicShield'},
    {label='Swordmastery — Last Stand',id='Shared_SwordExpert'},
    {label='Swordmastery — Sword Sage',id='Shared_DeadlyReset'},
    {label='Swordmastery — Tactical Mastery',id='Shared_Tactician'},
    {label='Vampirism — Lethal Crescendo',id='Vampire_UnstoppableVrakhir'},
    {label='Vampirism — Renounce Death',id='Vampire_SecondChance'},
    {label='Vampirism — Sanguine Renewal',id='Vampire_SweetBlood'},
}

function M.Init(menu,getPlayer,log)
    assert(type(getPlayer)=='function','Ultimate controls require a player resolver')
    local panel='DWUltimateControls'
    local byLabel={}
    local options={}
    for _,entry in ipairs(ultimates) do byLabel[entry.label]=entry;options[#options+1]=entry.label end
    local directPending=false
    local function valid(o) return o and o:IsValid() end
    local function unwrap(v)
        for _=1,4 do
            local ok,k=pcall(function() return v:type() end)
            if not ok or (k~='RemoteUnrealParam' and k~='LocalUnrealParam') then return v end
            v=v:get()
        end
        error('Unsupported wrapper depth')
    end
    local function subsystem(name)
        local found=nil
        for _,o in ipairs(FindAllOf(name) or {}) do
            if valid(o) and not o:GetFullName():find('Default__',1,true) then
                assert(not found,'Multiple live '..name..' instances')
                found=o
            end
        end
        assert(found,name..' unavailable')
        return found
    end
    local function status(s) menu.SetLabel(panel,'status',s) end
    local function snapshot(dev)
        local s={points=dev:GetTraitPointAmount(),spent=dev:GetSpentTraitPointAmount(),
            bought=dev:GetBoughtTraitsCount(),levels={},traits={},count=0}
        local all=dev:GetAllTraits();assert(#all>0 and #all<=1000,'Unexpected trait count')
        local function add(_,wrapped)
            local t=unwrap(wrapped);assert(valid(t),'Invalid trait')
            local traitId=t.Skill_ID:ToString();assert(not s.levels[traitId],'Duplicate trait ID')
            s.levels[traitId]=dev:GetTraitLevel(t);s.traits[traitId]=t;s.count=s.count+1
        end
        if type(all)=='table' then for i=1,#all do add(i,all[i]) end else all:ForEach(add) end
        return s
    end
    local function requireSafePlayer()
        local p=getPlayer(true)
        assert(valid(p) and valid(p.CombatComponent) and p.CombatComponent:IsAlive(),'Load a living player save first')
        assert(not subsystem('CombatSubsystem'):GetIsInCombat(),'Leave combat first')
    end
    local function grantSelected()
        if directPending then status('A targeted Ultimate grant is already being verified.');return end
        ExecuteInGameThread(function()
            local ok,err=pcall(function()
                requireSafePlayer()
                local entry=byLabel[menu.Get(panel,'ultimate')];assert(entry,'Select an Ultimate first')
                local dev=subsystem('CharacterDevelopmentSubsystem')
                local before=snapshot(dev);local trait=before.traits[entry.id]
                assert(trait and trait.MaxTraitLevel==1,'Selected Ultimate asset is invalid on this build')
                assert(before.levels[entry.id]==0,entry.label..' is already unlocked')
                local devName,devAddress=dev:GetFullName(),dev:GetAddress()
                directPending=true -- never automatically retry a mutation
                log(string.format('ULTIMATE_DIRECT REQUEST id=%s label=%s bought=%s points=%s spent=%s',entry.id,entry.label,before.bought,before.points,before.spent))
                assert(dev:UnlockTrait(trait,1,false,false,true)==true,'UnlockTrait rejected the selected Ultimate')
                ExecuteWithDelay(1000,function() ExecuteInGameThread(function()
                    local checked,message=pcall(function()
                        local current=subsystem('CharacterDevelopmentSubsystem')
                        assert(current:GetFullName()==devName and current:GetAddress()==devAddress,'Player/world changed during verification')
                        local after=snapshot(current)
                        assert(after.count==before.count,'Trait list changed during verification')
                        assert(after.levels[entry.id]==1,'Selected Ultimate did not reach rank 1')
                        for traitId,level in pairs(before.levels) do
                            if traitId~=entry.id then assert(after.levels[traitId]==level,'Unexpected trait changed: '..traitId) end
                        end
                        assert(after.points==before.points and after.spent==before.spent,'Skill-point ledger changed unexpectedly')
                        assert(after.bought==before.bought+1,'Bought-trait count changed unexpectedly')
                        directPending=false
                        log(string.format('ULTIMATE_DIRECT VERIFIED id=%s bought=%s->%s points=%s spent=%s',entry.id,before.bought,after.bought,after.points,after.spent))
                        status(entry.label..' granted successfully. It cost no skill points and persists with the save.')
                    end)
                    if not checked then
                        log('ULTIMATE_DIRECT VERIFY ERROR '..tostring(message))
                        status('Targeted grant could not be verified. Do not save; reload an earlier save. See UE4SS.log.')
                    end
                end) end)
            end)
            if not ok then
                log('ULTIMATE_DIRECT ERROR '..tostring(err))
                status('Targeted grant failed. If mutation began, do not save; reload an earlier save. See UE4SS.log.')
            end
        end)
    end
    local function unlockAll()
        ExecuteInGameThread(function()
            local ok,err=pcall(function()
                requireSafePlayer()
                local dev=subsystem('CharacterDevelopmentSubsystem')
                local before=snapshot(dev)
                log(string.format('UNLOCK_ALL REQUEST bought=%s points=%s spent=%s args=true,true,true,false',before.bought,before.points,before.spent))
                dev:UnlockAllTraits(true,true,true,false)
                ExecuteWithDelay(1000,function() ExecuteInGameThread(function()
                    local checked,message=pcall(function()
                        local after=snapshot(subsystem('CharacterDevelopmentSubsystem'))
                        log(string.format('UNLOCK_ALL RESULT bought=%s->%s points=%s->%s spent=%s->%s',before.bought,after.bought,before.points,after.points,before.spent,after.spent))
                        status(string.format('Unlock Everything completed. Bought traits: %s -> %s.',before.bought,after.bought))
                    end)
                    if not checked then status('Bulk-unlock verification failed; reload an earlier save.');log('UNLOCK_ALL VERIFY ERROR '..tostring(message)) end
                end) end)
            end)
            if not ok then status('Unlock Everything failed; reload an earlier save.');log('UNLOCK_ALL ERROR '..tostring(err)) end
        end)
    end
    menu.Register({id=panel,title='☆ Ultimate Perks & Bulk Unlock',tab='✦ Progression',collapsible=true,collapsed=true,items={
        {type='label',id='status',label='Targeted Ultimate grants and Bulk Unlock are separate operations.'},
        {type='dropdown',id='ultimate',label='Ultimate to grant',options=options,default=options[1]},
        {type='button',id='grant',label='Grant selected Ultimate',variant='success',confirm={
            title='Grant selected Ultimate?',
            message='This directly grants only the selected Ultimate at rank 1. It bypasses normal prerequisites, exclusivity and skill-point cost. The mod verifies that no other trait or point ledger changed.',
            confirmLabel='Grant Ultimate',cancelLabel='Cancel'},onClick=grantSelected},
        {type='separator'},
        {type='button',id='unlockAll',label='Unlock Everything / Max All Traits',variant='danger',confirm={
            title='Unlock and max every trait and ability?',
            message='This affects the full trait database, not only Ultimates. It maxes ordinary, hidden, manual, quest and boss traits; recipe/manual-based skill access is marked as learned/read. It permanently changes the save and will trigger achievements.',
            confirmLabel='Unlock Everything',cancelLabel='Cancel',variant='danger'},onClick=unlockAll},
    }})
end

return M
