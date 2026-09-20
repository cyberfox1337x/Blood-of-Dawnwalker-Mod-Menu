local cyberfox1337x={signature=function(name)return name end}
cyberfox1337x.signature('timeless_court_tests')
local module=dofile(arg[1])
local function object(address,class)
 return {IsValid=function()return true end,GetAddress=function()return address end,IsA=function(_,name)return name==class end}
end
local function fixture()
 local world=object(1);local player=object(2,'/Script/Dawnwalker.DawnwalkerPlayerCharacter');player.GetWorld=function()return world end;player.Controller=object(3);player.Controller.Pawn=player
 local asset=object(4,'/Script/Quest.Quest');asset.GetFullName=function()return 'Quest /Game/_Dawnwalker/Quest/q102_st_mihai/Journal/q102_journal_asylum.q102_journal_asylum' end
 local quest=object(5,'/Script/Quest.Quest');quest.QuestAssetPtr=asset
 local objective={ID={A=1,B=2,C=3,D=4},CompletedObjectiveTimeProgression=3,bPushTimeToSpecificHour=true,TimeProgressionTargetHour=12};quest.Objectives={objective}
 local opened={quest};local journal=object(6,'/Script/Quest.Journal');journal.GetOpenedQuests=function(_,out)for i,q in ipairs(opened)do out[i]=q end end
 local state=object(7,'/Script/Dawnwalker.DawnwalkerGameStateBase');state.GetWorld=function()return world end;state.QuestJournal=journal
 local helpers={GetPlayer=function()return player end,GetGameStateBase=function()return state end}
 return module.New(helpers),objective,quest,asset,opened,player,helpers
end
local tests={}
local function registeredControl(helpers)
 local captured={}
 module.Init({Register=function(section)captured.section=section end,Set=function(_,_,value)captured.enabled=value end,SetLabel=function(_,_,label)captured.status=label end},helpers)
 return captured
end
tests['menu refusal displays and returns clean reason without source paths']=function()
 local _,objective,_,_,opened,_,helpers=fixture();opened[1]=nil
 local captured=registeredControl(helpers)
 local ok,failure=pcall(captured.section.items[1].onChange,true)
 local expected='No supported court activity is open in this save'
 assert(not ok and failure==expected,tostring(failure))
 assert(captured.status==expected,captured.status)
 assert(captured.enabled==false and objective.CompletedObjectiveTimeProgression==3)
end
tests['menu strips nested source positions while retaining failure reason']=function()
 local _,_,_,_,_,_,helpers=fixture()
 helpers.GetPlayer=function()error('C:\\game\\Scripts\\Helper.lua:42: Player unavailable',0)end
 local captured=registeredControl(helpers)
 local ok,failure=pcall(captured.section.items[1].onChange,true)
 assert(not ok and failure=='Player unavailable',tostring(failure))
 assert(captured.status=='Player unavailable' and captured.enabled==false)
end
tests['apply exact scoped fields and restore originals']=function()
 local c,o=fixture();c.SetEnabled(true);assert(o.CompletedObjectiveTimeProgression==0 and o.bPushTimeToSpecificHour==false);assert(o.TimeProgressionTargetHour==12);c.SetEnabled(false);assert(o.CompletedObjectiveTimeProgression==3 and o.bPushTimeToSpecificHour==true)
end
tests['unknown assets and shared quest assets are refused']=function()
 local c,o,q,a=fixture();a.GetFullName=function()return 'Quest /Game/Other.Other' end;assert(not pcall(c.SetEnabled,true));assert(o.CompletedObjectiveTimeProgression==3)
 c,o,q,a=fixture();q.GetAddress=a.GetAddress;assert(not pcall(c.SetEnabled,true));assert(o.CompletedObjectiveTimeProgression==3)
end
tests['foreign changes are preserved and recovery remains available']=function()
 local c,o=fixture();c.SetEnabled(true);o.CompletedObjectiveTimeProgression=4;assert(not pcall(c.SetEnabled,false));assert(o.CompletedObjectiveTimeProgression==4);assert(c.IsActive());o.CompletedObjectiveTimeProgression=0;c.SetEnabled(false);assert(o.CompletedObjectiveTimeProgression==3)
end
tests['objective reorder restores by GUID']=function()
 local c,o,q=fixture();c.SetEnabled(true);q.Objectives={{ID={A=9,B=9,C=9,D=9},CompletedObjectiveTimeProgression=2,bPushTimeToSpecificHour=false},o};c.SetEnabled(false);assert(o.CompletedObjectiveTimeProgression==3);assert(q.Objectives[1].CompletedObjectiveTimeProgression==2)
end
tests['malformed objective preflight leaves earlier targets unchanged']=function()
 local c,o,q=fixture();q.Objectives[2]={ID={A=2,B=2,C=2,D=2},CompletedObjectiveTimeProgression='bad',bPushTimeToSpecificHour=true};assert(not pcall(c.SetEnabled,true));assert(o.CompletedObjectiveTimeProgression==3)
end
tests['session cleanup restores and inactive refresh does nothing']=function()
 local c,o=fixture();c.RefreshSession();assert(o.CompletedObjectiveTimeProgression==3);c.SetEnabled(true);c.ResetSession();assert(o.CompletedObjectiveTimeProgression==3 and not c.IsActive())
end
tests['late opened scoped objectives join active override']=function()
 local c,o,q,a,opened=fixture();c.SetEnabled(true);local later=object(8,'/Script/Quest.Quest');later.QuestAssetPtr=a;local nextObjective={ID={A=8,B=2,C=3,D=4},CompletedObjectiveTimeProgression=5,bPushTimeToSpecificHour=false};later.Objectives={nextObjective};opened[2]=later;c.RefreshSession();assert(nextObjective.CompletedObjectiveTimeProgression==0);c.SetEnabled(false);assert(nextObjective.CompletedObjectiveTimeProgression==5)
end
tests['failed write readback rolls back all changed objectives']=function()
 local c,o,q=fixture()
 local values={ID={A=7,B=7,C=7,D=7},CompletedObjectiveTimeProgression=4,bPushTimeToSpecificHour=true}
 q.Objectives[2]=setmetatable({},{__index=values,__newindex=function(_,key,value)if key~='CompletedObjectiveTimeProgression' or value~=0 then values[key]=value end end})
 assert(not pcall(c.SetEnabled,true));assert(o.CompletedObjectiveTimeProgression==3 and o.bPushTimeToSpecificHour==true)
 assert(values.CompletedObjectiveTimeProgression==4 and values.bPushTimeToSpecificHour==true);assert(not c.IsActive())
end
tests['possession failure performs no write']=function()
 local c,o,q,a,opened,p=fixture();p.Controller.Pawn=nil;assert(not pcall(c.SetEnabled,true));assert(o.CompletedObjectiveTimeProgression==3)
end
local count=0;for name,test in pairs(tests)do test();count=count+1;print('PASS '..name)end;print(count..' Timeless Court tests passed')
