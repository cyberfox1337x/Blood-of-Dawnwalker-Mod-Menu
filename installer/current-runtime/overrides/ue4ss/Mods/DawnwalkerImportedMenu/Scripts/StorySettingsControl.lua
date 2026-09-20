local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("supplied_story_settings_control")
local M = {}
local function valid(object) return object ~= nil and object:IsValid() end
local function integer(value) return type(value)=="number" and value>=0 and value<math.huge and value%1==0 end
local function unwrap(value)
    for _=1,4 do
        local ok, kind=pcall(function() return value:type() end)
        if not ok or (kind~="RemoteUnrealParam" and kind~="LocalUnrealParam") then return value end
        value=value:get()
    end
    error("Unsupported trait value wrapper")
end
function M.Init(menu, helpers)
    local id, records, dayRecord, failed="DWStorySettings",{},nil,false
    local function context()
        local player=helpers.GetPlayer()
        assert(valid(player),"Load a controlled player first.")
        local world,controller=player:GetWorld(),player.Controller
        assert(valid(world) and valid(controller) and valid(controller.Pawn)
            and controller.Pawn:GetAddress()==player:GetAddress(),"Player possession changed.")
        return {player=player:GetAddress(),world=world:GetAddress(),controller=controller:GetAddress()}
    end
    local function same(a,b) return a.player==b.player and a.world==b.world and a.controller==b.controller end
    local function levels(asset)
        local array=asset.Levels
        assert(#array>=1 and #array<=32,"Trait rank count is invalid.")
        local result={}
        local function add(index,value)
            assert(integer(index) and index>=1 and index<=#array and result[index]==nil,"Unexpected trait rank indexing.")
            value=unwrap(value)
            assert(integer(unwrap(value.TimeCost)),"Trait time cost is invalid.")
            result[index]=value
        end
        if type(array)=="table" then for index=1,#array do add(index,array[index]) end else array:ForEach(add) end
        for index=1,#array do assert(result[index],"Trait rank is missing.") end
        return result
    end
    local function scan()
        local session=context()
        local all=FindAllOf("TraitAsset")
        assert(type(all)=="table" and #all>0 and #all<=4096,"No bounded loaded trait collection is available.")
        local plan,assets,ranks,nonzero={},0,0,0
        for _,asset in ipairs(all) do
            if valid(asset) and not asset:GetFullName():find("Default__",1,true) then
                assert(asset:IsA("/Script/DogwoodCharacterDevelopment.TraitAsset"),"Unexpected trait class.")
                local rows=levels(asset); assets=assets+1
                for index,row in ipairs(rows) do
                    ranks=ranks+1
                    local cost=unwrap(row.TimeCost)
                    if cost>0 then
                        nonzero=nonzero+1
                        plan[#plan+1]={asset=asset,address=asset:GetAddress(),name=asset:GetFullName(),index=index,count=#rows,cost=cost,target=row}
                    end
                end
            end
        end
        assert(assets>0 and same(session,context()),"Player changed or no concrete traits were found.")
        return plan,assets,ranks,nonzero,session
    end
    local function row(record, cache)
        assert(valid(record.asset) and record.asset:GetAddress()==record.address and record.asset:GetFullName()==record.name,"Owned trait identity expired.")
        local rows=cache and cache[record.address]
        if not rows then rows=levels(record.asset);if cache then cache[record.address]=rows end end
        assert(#rows==record.count,"Owned trait ranks changed.")
        return rows[record.index]
    end
    local function restoreTraits()
        local unresolved,restored,skipped,cache={},0,0,{}
        for _,record in ipairs(records) do
            local ok=pcall(function()
                local target=row(record,cache);local current=unwrap(target.TimeCost)
                if current==0 then
                    target.TimeCost=record.cost
                    assert(unwrap(target.TimeCost)==record.cost,"Trait restoration readback failed.")
                    restored=restored+1
                elseif current~=record.cost then skipped=skipped+1 end
            end)
            if not ok then unresolved[#unresolved+1]=record end
        end
        records=unresolved;menu.Set(id,"traits",#records>0)
        assert(#records==0,"STOP: trait cost restoration unresolved; reload your save before continuing.")
        menu.SetLabel(id,"traitStatus",string.format("Restored %d trait rank costs; left %d externally changed costs untouched.",restored,skipped))
    end
    local function setTraits(enabled)
        if not enabled then restoreTraits();return end
        if #records>0 then menu.Set(id,"traits",true);return end
        menu.Set(id,"traits",false)
        assert(not failed,"A previous failure requires restarting after cleanup.")
        local plan,assets,ranks,count,session=scan()
        records=plan;menu.Set(id,"traits",true)
        local ok,err=pcall(function()
            for _,record in ipairs(records) do
                local target=record.target
                assert(unwrap(target.TimeCost)==record.cost,"Trait cost changed before apply.")
                target.TimeCost=0
                assert(unwrap(target.TimeCost)==0,"Trait cost zero readback failed.")
            end
            assert(same(session,context()),"Player changed during trait cost update.")
            local cache={}
            for _,record in ipairs(records) do assert(unwrap(row(record,cache).TimeCost)==0,"Fresh trait cost readback failed.") end
        end)
        for _,record in ipairs(records) do record.target=nil end
        if not ok then
            failed=true
            local restored,restoreError=pcall(restoreTraits)
            menu.SetLabel(id,"traitStatus",restored and "Trait update failed; original costs restored." or tostring(restoreError))
            error(tostring(err)..(restored and "" or "; "..tostring(restoreError)))
        end
        menu.SetLabel(id,"traitStatus",string.format("Verified zero time cost for %d changed ranks across %d loaded traits (%d ranks inspected). Newly loaded traits require OFF then ON.",count,assets,ranks))
    end
    local function settings()
        local object=StaticFindObject("/Script/Quest.Default__QuestSettings")
        assert(valid(object) and object:IsA("/Script/Quest.QuestSettings"),"Quest settings reflection is unavailable.")
        assert(integer(object.DaysToPass) and object.DaysToPass>0,"Configured story days are invalid.")
        local system=FindFirstOf("TimeSystemImpl")
        assert(valid(system) and not system:GetFullName():find("Default__",1,true),"The active story time system is unavailable.")
        local current,goal=system:GetCurrentDay(),system:GetMainGoalDay()
        assert(integer(current) and integer(goal),"Active story deadline readback is invalid.")
        return object,system,current,goal
    end
    local function restoreDays()
        if not dayRecord then menu.Set(id,"dayOwned",false);menu.Set(id,"daysEnabled",false);return end
        local record=dayRecord
        assert(valid(record.object) and record.object:GetAddress()==record.address,"Owned quest settings identity expired.")
        if record.object.DaysToPass==91 then record.object.DaysToPass=record.original end
        assert(record.object.DaysToPass==record.original,"Story day settings restoration was not verified.")
        assert(valid(record.system) and record.system:GetAddress()==record.systemAddress and record.system:GetMainGoalDay()==record.goal,"Active story deadline restoration was not verified.")
        dayRecord=nil;menu.Set(id,"dayOwned",false);menu.Set(id,"daysEnabled",false)
    end
    local function setDays(enabled)
        if not enabled then
            restoreDays()
            menu.SetLabel(id,"dayStatus","Original story configuration and active deadline restored and verified.")
            return
        end
        menu.Set(id,"daysEnabled",false)
        if dayRecord then
            assert(dayRecord.object.DaysToPass==91 and dayRecord.system:GetMainGoalDay()==91,"Owned story deadline changed; restore first.")
            menu.Set(id,"daysEnabled",true);return
        end
        local session=context()
        local object,system,_,before=settings()
        dayRecord={object=object,address=object:GetAddress(),original=object.DaysToPass,system=system,systemAddress=system:GetAddress(),goal=before}
        menu.Set(id,"dayOwned",true)
        local ok,result=pcall(function()
            object.DaysToPass=91
            assert(object.DaysToPass==91 and same(session,context()),"Story setting write or player identity verification failed.")
            assert(system:GetMainGoalDay()==91,"The active deadline did not become91. Persistent configuration and restart may be required.")
        end)
        if not ok then
            local restored,restoreError=pcall(restoreDays)
            menu.SetLabel(id,"dayStatus",restored and "Story day change failed; original settings and deadline restored." or "STOP: story deadline recovery remains unresolved.")
            error(tostring(result)..(restored and "" or "; "..tostring(restoreError)))
        end
        menu.Set(id,"daysEnabled",true)
        menu.SetLabel(id,"dayStatus","90-day story setting active: DaysToPass91 and active deadline91 verified. OFF restores the captured original deadline; this live override ends with the runtime session.")
    end
    local function refresh()
        local object,_,current,goal=settings()
        menu.SetLabel(id,"dayStatus",string.format("Configured DaysToPass=%d; active day=%d, deadline=%d. Supplied 90-day configuration uses 91.",object.DaysToPass,current,goal))
        local _,assets,ranks,count=scan()
        menu.SetLabel(id,"traitStatus",string.format("Loaded traits=%d; ranks=%d; nonzero time costs=%d. Refresh is read-only.",assets,ranks,count))
    end
    function M.ResetSession()
        assert(#records==0 and not dayRecord,"Cannot discard unresolved story settings ownership.")
        failed=false;menu.Set(id,"traits",false);menu.Set(id,"dayOwned",false);menu.Set(id,"daysEnabled",false)
        menu.SetLabel(id,"dayStatus","Read current settings before changing story time.")
        menu.SetLabel(id,"traitStatus","Only loaded trait rank costs are covered; no background scans run.")
    end
    menu.Register({id=id,title="Story settings from supplied mods",tab="World",items={
        {id="refresh",type="button",label="Read story and trait costs",onClick=refresh},
        {id="daysEnabled",type="checkbox",label="90-day story deadline (live)",default=false,onChange=setDays},
        {id="dayOwned",type="checkbox",label="Story setting recovery pending",default=false,onChange=function(value) assert(value==false,"Recovery can only be released.");restoreDays() end},
        {id="dayStatus",type="label",label="Read current settings before changing story time."},
        {id="traits",type="checkbox",label="No time cost for loaded traits",default=false,onChange=setTraits},
        {id="traitStatus",type="label",label="Only loaded trait rank costs are covered; no background scans run."},
    }})
end
return M
