local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature('timeless_court_control')
local M = {}
-- Exact journal package scope from the reference's unencrypted directory index.
-- No reference container is loaded, installed or included in the runtime.
local TARGETS = {
    ["/Game/_Dawnwalker/Quest/q102_st_mihai/Journal/q102_journal_asylum.q102_journal_asylum"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX106_Recruiters_Tavern/ox106_journal.ox106_journal"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX115_DigSite_Summoning/poi_ox115_digsites_summoning.poi_ox115_digsites_summoning"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX110_Transports_Prisoner/Journal/ox110_journal.ox110_journal"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX102_Camp_Pain/ox102_journal.ox102_journal"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX111_Tranports_New_Life/Journal/ox111_journal.ox111_journal"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX107_Recruiters_Woman/ox107_journal.ox107_journal"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX101_Camp_Empathy/ox101_journal.ox101_journal"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX103_Camp_Training/ox103_journal.ox103_journal"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX116_DigSite_Boss/poi_ox116_digsites_boss.poi_ox116_digsites_boss"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX117_Transports_Artifact/poi_ox117_transport_artifact.poi_ox117_transport_artifact"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX118_Transports_Thieves/poi_ox118_transport_thieves.poi_ox118_transport_thieves"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX114_DigSite_Generic/poi_ox114_digsites_generic.poi_ox114_digsites_generic"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Xanthe_POIs/OX105_Recruiters_Poor/ox105_journal.ox105_journal"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA109/Journal/Journal_OA109.Journal_OA109"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA111/Journal/Journal_OA111.Journal_OA111"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA110/Journal/Journal_OA110.Journal_OA110"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA104/Journal/Journal_OA104.Journal_OA104"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA101/Journal/Journal_OA101.Journal_OA101"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA102/Journal/Journal_OA102.Journal_OA102"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA112/Journal/Journal_OA112.Journal_OA112"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA113/Journal/Journal_OA113.Journal_OA113"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA103/Journal/Journal_OA103.Journal_OA103"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA105/Journal/Journal_OA105.Journal_OA105"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA106/Journal/Journal_OA106.Journal_OA106"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA107/Journal/Journal_OA107.Journal_OA107"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/AmbrusPOI/OA108/Journal/Journal_OA108.Journal_OA108"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Bakir_POIs/02_Distilleries/OB106_Hidden_Distillery/Journal/ob106_hidden_distillery.ob106_hidden_distillery"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Bakir_POIs/02_Distilleries/OB104_Extremist_Distillery/Journal/ob104_extremist_distillery.ob104_extremist_distillery"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Bakir_POIs/02_Distilleries/OB105_City_Distillery/Journal/ob105_city_distillery.ob105_city_distillery"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Bakir_POIs/05_Kobold_Transports/OB112_Kobold_Transport/Journal/ob112_kobold_transport.ob112_kobold_transport"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Bakir_POIs/01_Rebel_Hunters/OB101_Uriash/Journal/ob101_hunters1.ob101_hunters1"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Bakir_POIs/01_Rebel_Hunters/OB102_DeadWitness/Journal/ob102_main.ob102_main"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Bakir_POIs/01_Rebel_Hunters/OB103_Survivors/Journal/ob103_rebel_hunters.ob103_rebel_hunters"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Bakir_POIs/03_Cages/OB108_Vasil_Cage/Journal/ob108_standard_cage.ob108_standard_cage"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Bakir_POIs/03_Cages/OB107_Torturer_Cage/Journal/ob107_torturer_cage.ob107_torturer_cage"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Bakir_POIs/03_Cages/OB109_Game_Cage/Journal/ob109_game_cage.ob109_game_cage"] = true,
    ["/Game/_Dawnwalker/Quest/_Open_World/POIs/Act_1/Bakir_POIs/04_Uriash_Transports/OB110_Corrupt_Transport/Journal/ob110_uriash_transport.ob110_uriash_transport"] = true,
    ["/Game/_Dawnwalker/Quest/q105_rebels/Journal/q105_miller_rescue_journal.q105_miller_rescue_journal"] = true,
    ["/Game/_Dawnwalker/Quest/_Side_Quests/sq716_uriash_girl/Journal/sq716_matriarch.sq716_matriarch"] = true,
}
local function valid(object) return object ~= nil and object:IsValid() end
local function address(object) assert(valid(object),'Object unavailable');return tostring(object:GetAddress()) end
local function same(a,b) return valid(a) and valid(b) and address(a)==address(b) end
local function unwrap(value)
    if value and type(value.get)=='function' then return value:get() end
    return value
end
local function count(collection,limit)
    local length=#collection
    assert(type(length)=='number' and length>=0 and length%1==0 and length<=limit,'Unexpected journal size')
    return length
end
local function guid(objective)
    local id=objective.ID
    local fields={id.A,id.B,id.C,id.D}
    for _,value in ipairs(fields) do assert(type(value)=='number' and value%1==0,'Objective identity unavailable') end
    assert(#fields==4,'Objective identity incomplete')
    return table.concat(fields,':')
end
local function fields(objective)
    local cost,push=objective.CompletedObjectiveTimeProgression,objective.bPushTimeToSpecificHour
    assert(type(cost)=='number' and cost%1==0 and cost>=0 and cost<=8 and type(push)=='boolean','Objective time fields unavailable')
    return cost,push
end
local function assetPath(asset)
    local full=asset:GetFullName()
    return full:match('^[^ ]+ (.+)$')
end
function M.New(helpers)
    local records,enabled,owner={},false,nil
    local function context()
        local player=helpers.GetPlayer()
        assert(valid(player) and player:IsA('/Script/Dawnwalker.DawnwalkerPlayerCharacter'),'Load a supported player first')
        assert(valid(player.Controller) and same(player.Controller.Pawn,player),'Player possession unavailable')
        local world=player:GetWorld()
        local state=helpers.GetGameStateBase()
        assert(valid(world) and valid(state) and state:IsA('/Script/Dawnwalker.DawnwalkerGameStateBase') and same(state:GetWorld(),world),'Quest world unavailable')
        local journal=state.QuestJournal
        assert(valid(journal) and journal:IsA('/Script/Quest.Journal'),'Quest journal unavailable')
        return {player=address(player),world=address(world),journal=address(journal),object=journal}
    end
    local function locate(record)
        assert(valid(record.quest) and same(record.quest.QuestAssetPtr,record.asset),'Quest ownership changed')
        local match
        for i=1,count(record.quest.Objectives,128) do
            local objective=unwrap(record.quest.Objectives[i])
            if guid(objective)==record.id then assert(not match,'Duplicate objective identity');match=objective end
        end
        assert(match,'Owned objective no longer exists')
        return match
    end
    local function restore()
        local remaining={}
        for _,record in ipairs(records) do
            if valid(record.quest) then
                local ok=pcall(function()
                    local objective=locate(record)
                    local cost,push=fields(objective)
                    -- A third-party value must not be overwritten. Retain the record
                    -- for explicit recovery rather than claiming a successful OFF.
                    assert((cost==0 or cost==record.cost) and (push==false or push==record.push),'Objective changed outside this control')
                    objective.CompletedObjectiveTimeProgression=record.cost
                    objective.bPushTimeToSpecificHour=record.push
                    local restoredCost,restoredPush=fields(objective)
                    assert(restoredCost==record.cost and restoredPush==record.push,'Objective restore readback failed')
                end)
                if not ok then remaining[#remaining+1]=record end
            end
        end
        records=remaining
        if #records>0 then error('Court time restoration is incomplete; original records retained',0) end
        enabled,owner=false,nil
    end
    local function collect(ctx)
        local opened={};ctx.object:GetOpenedQuests(opened)
        local candidates,seen={},{}
        for index=1,count(opened,512) do
            local quest=unwrap(opened[index])
            assert(valid(quest) and quest:IsA('/Script/Quest.Quest'),'Unexpected journal quest')
            local asset=quest.QuestAssetPtr
            if valid(asset) and TARGETS[assetPath(asset)] then
                assert(asset:IsA('/Script/Quest.Quest') and not same(quest,asset),'Refusing shared quest asset')
                for i=1,count(quest.Objectives,128) do
                    local objective=unwrap(quest.Objectives[i])
                    local id=guid(objective);local key=address(quest)..':'..id
                    assert(not seen[key],'Duplicate journal objective');seen[key]=true
                    local cost,push=fields(objective)
                    candidates[#candidates+1]={quest=quest,asset=asset,id=id,key=key,cost=cost,push=push}
                    assert(#candidates<=4096,'Too many court objectives')
                end
            end
        end
        return candidates
    end
    local function apply()
        local ctx=context()
        if owner then assert(owner.player==ctx.player and owner.world==ctx.world and owner.journal==ctx.journal,'Player session changed') end
        local candidates=collect(ctx)
        assert(#candidates>0,'No supported court activity is open in this save')
        local existing={}
        for _,record in ipairs(records) do
            local cost,push=fields(locate(record))
            assert(cost==0 and push==false,'Owned court objective changed; restore first')
            existing[record.key]=true
        end
        local ok,failure=pcall(function()
            for _,candidate in ipairs(candidates) do
                if not existing[candidate.key] then
                    records[#records+1]=candidate
                    local objective=locate(candidate)
                    objective.CompletedObjectiveTimeProgression=0
                    objective.bPushTimeToSpecificHour=false
                    local cost,push=fields(objective)
                    assert(cost==0 and push==false,'Court time change readback failed')
                end
            end
        end)
        if not ok then
            local restored=pcall(restore)
            error(tostring(failure)..(restored and '; originals restored' or '; restoration required'),0)
        end
        enabled,owner=true,ctx
    end
    return {
        SetEnabled=function(value) assert(type(value)=='boolean','Expected a toggle value');if value then apply() else restore() end end,
        IsActive=function()return enabled or #records>0 end,
        RefreshSession=function()
            if not enabled then return end
            local ctx=context()
            if owner.player~=ctx.player or owner.world~=ctx.world or owner.journal~=ctx.journal then restore();return end
            apply()
        end,
        ResetSession=restore,
    }
end
function M.Init(menu,helpers)
    local id='DWTimelessCourt'
    local control=M.New(helpers)
    local function set(value)
        local ok,failure=pcall(control.SetEnabled,value)
        -- Assertions include Lua source locations; neither the status label nor
        -- the command response should expose those implementation details.
        local reason=tostring(failure)
        while reason:match('^.-:%d+:%s*') do
            reason=reason:gsub('^.-:%d+:%s*','',1)
        end
        menu.Set(id,'enabled',control.IsActive())
        menu.SetLabel(id,'status',ok and (value and 'Court activity time costs disabled for supported open activities.' or 'Original court activity time costs restored.') or reason)
        if not ok then error(reason,0) end
    end
    function M.ResetSession() control.ResetSession();menu.Set(id,'enabled',false) end
    function M.RefreshSession()
        if not control.IsActive() then return end
        control.RefreshSession()
        if not control.IsActive() then menu.Set(id,'enabled',false) end
    end
    menu.Register({id=id,title='Court Activities',tab='World',items={
        {id='enabled',type='checkbox',label='Timeless Court Activities - No Time Cost',default=false,onChange=set},
        {id='status',type='label',label='Off. Original court activity time costs are preserved.'},
        {type='label',label='Applies to supported open court activities. Turning off restores their original costs, not time already spent.'},
    }})
    return M
end
return M
