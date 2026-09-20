-- Searchable targeted trait grant. Mutations are explicit and verified; no polling.
local M={}

function M.Init(menu,getPlayer,log)
    assert(type(getPlayer)=='function','Trait grant requires a player resolver')
    local PANEL='DWTraitGrant'
    local selectedId=false
    local mutationPending=false

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
    local function status(s) menu.SetLabel(PANEL,'status',s) end
    local function requireSafePlayer()
        local p=getPlayer(true)
        assert(valid(p) and valid(p.CombatComponent) and p.CombatComponent:IsAlive(),'Load a living player save first')
        assert(not subsystem('CombatSubsystem'):GetIsInCombat(),'Leave combat first')
    end
    local function snapshot(dev)
        local s={points=dev:GetTraitPointAmount(),spent=dev:GetSpentTraitPointAmount(),levels={},traits={},names={},max={},count=0}
        local all=dev:GetAllTraits();assert(#all>0 and #all<=1000,'Unexpected trait count')
        local function add(_,wrapped)
            local trait=unwrap(wrapped);assert(valid(trait),'Invalid trait')
            local id=trait.Skill_ID:ToString();assert(not s.traits[id],'Duplicate trait ID: '..id)
            local ok,name=pcall(function() return trait.LocalizedName:ToString() end)
            if not ok or not name or name=='' or name:find('MISSING',1,true) then name=id end
            s.traits[id]=trait;s.names[id]=name
            s.levels[id]=tonumber(dev:GetTraitLevel(trait)) or 0
            s.max[id]=tonumber(trait.MaxTraitLevel) or 0
            assert(s.max[id]>=1 and s.max[id]<=32,'Invalid maximum rank: '..id)
            s.count=s.count+1
        end
        if type(all)=='table' then for i=1,#all do add(i,all[i]) end else all:ForEach(add) end
        return s
    end
    local function refreshList()
        local ok,err=pcall(function()
            local p=getPlayer(true);assert(valid(p),'Load a save first')
            local snap=snapshot(subsystem('CharacterDevelopmentSubsystem'))
            local options={}
            for id,_ in pairs(snap.traits) do
                options[#options+1]={
                    label=string.format('%s — rank %d/%d  [%s]',snap.names[id],snap.levels[id],snap.max[id],id),
                    value=id,
                }
            end
            table.sort(options,function(a,b) return a.label:lower()<b.label:lower() end)
            local keep=selectedId and snap.traits[selectedId] and selectedId or false
            if not keep then selectedId=false end
            menu.SetOptions(PANEL,'perk',options,keep)
            status(string.format('%d loaded perks indexed. Select one and choose its target rank.',snap.count))
            log(string.format('TRAIT_GRANT indexed=%d',snap.count))
        end)
        if not ok then status('Perk list unavailable: load a save, then press Refresh perk list.');log('TRAIT_GRANT SCAN ERROR '..tostring(err)) end
    end
    local function requestRefresh() ExecuteInGameThread(refreshList) end
    local function grantSelected()
        if mutationPending then status('A perk grant is already being verified.');return end
        ExecuteInGameThread(function()
            local mutationStarted=false
            local ok,err=pcall(function()
                requireSafePlayer()
                assert(selectedId,'Select a perk first')
                local dev=subsystem('CharacterDevelopmentSubsystem')
                local before=snapshot(dev)
                local trait=before.traits[selectedId];assert(trait,'Selected perk is no longer available; refresh the list')
                local target=math.floor(tonumber(menu.Get(PANEL,'rank')) or 1)
                target=math.max(1,math.min(target,before.max[selectedId]))
                assert(before.levels[selectedId]<target,string.format('%s is already rank %d/%d',before.names[selectedId],before.levels[selectedId],before.max[selectedId]))
                local devName,devAddress=dev:GetFullName(),dev:GetAddress()
                mutationPending=true;mutationStarted=true
                log(string.format('TRAIT_GRANT REQUEST id=%s name=%s rank=%d->%d max=%d points=%s spent=%s',selectedId,before.names[selectedId],before.levels[selectedId],target,before.max[selectedId],before.points,before.spent))
                assert(dev:UnlockTrait(trait,target,false,false,true)==true,'UnlockTrait rejected the selected perk')
                ExecuteWithDelay(1000,function() ExecuteInGameThread(function()
                    local checked,message=pcall(function()
                        local current=subsystem('CharacterDevelopmentSubsystem')
                        assert(current:GetFullName()==devName and current:GetAddress()==devAddress,'Player/world changed during verification')
                        local after=snapshot(current);assert(after.count==before.count,'Trait list changed during verification')
                        assert(after.levels[selectedId]==target,'Selected perk did not reach the requested rank')
                        for id,level in pairs(before.levels) do
                            if id~=selectedId then assert(after.levels[id]==level,'Unexpected perk changed: '..id) end
                        end
                        assert(after.points==before.points and after.spent==before.spent,'Skill-point ledger changed unexpectedly')
                        mutationPending=false
                        log(string.format('TRAIT_GRANT VERIFIED id=%s rank=%d->%d points=%s spent=%s',selectedId,before.levels[selectedId],target,after.points,after.spent))
                        status(string.format('%s granted at rank %d/%d. No skill points were spent.',before.names[selectedId],target,before.max[selectedId]))
                        refreshList()
                    end)
                    if not checked then
                        log('TRAIT_GRANT VERIFY ERROR '..tostring(message))
                        status('Perk grant could not be verified. Do not save or retry; reload an earlier save. See UE4SS.log.')
                    end
                end) end)
            end)
            if not ok then
                if not mutationStarted then mutationPending=false end
                log('TRAIT_GRANT ERROR '..tostring(err))
                status(mutationStarted and 'Perk grant failed after mutation began. Do not save; reload an earlier save. See UE4SS.log.' or tostring(err))
            end
        end)
    end

    menu.Register({id=PANEL,title='♡ Grant Specific Perk',tab='✦ Progression',collapsible=true,collapsed=true,items={
        {type='label',id='status',label='Load a save to index the perk database.'},
        {type='dropdown',id='perk',label='Perk',searchable=true,placeholder='Search every loaded perk...',maxVisible=200,
            options={{label='Perks scan after loading a save',value=false}},onChange=function(v) selectedId=v end},
        {type='number',id='rank',label='Target rank',default=1,min=1,max=32,integer=true},
        {type='button',id='grant',label='Grant selected perk',variant='success',confirm={
            title='Grant this perk directly?',
            message='Sets only the selected perk to the requested rank, capped at its real maximum. This bypasses prerequisites, exclusivity, manuals, quests and skill-point cost, and may trigger achievements or progression events.',
            confirmLabel='Grant perk',cancelLabel='Cancel'},onClick=grantSelected},
        {type='button',id='refresh',label='Refresh perk list',onClick=requestRefresh},
    }})
    menu.OnOpen(requestRefresh)
end

return M
