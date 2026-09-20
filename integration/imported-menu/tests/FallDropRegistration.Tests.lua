local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("fall_drop_registration_tests")
local file=assert(io.open(assert(arg[1]),"rb"));local source=file:read("*a");file:close()
-- Limit this registration test to its owned block, independent of other adapters.
local start=assert(source:find("local fallDropLoaded, fallDropFailure",1,true))
local ending=assert(source:find('if not fallDropLoaded then menu.Fail("Fall drop initialization failed: " .. tostring(fallDropFailure)) end',start,true))
local block=source:sub(start,ending-1)
local registered,dependencies,started
local module={New=function(deps)dependencies=deps;return{start=function(height)started=height end,cancel=function()end,
    snapshot=function()return{recoveryPending=false}end,owned=function()return false end}end}
local environment={pcall=pcall,assert=assert,ipairs=ipairs,tostring=tostring,scriptDirectory="",adapterModules={},
    loadfile=function()return function()return module end end,StaticFindObject=function()return{}end,
    helpers={GetPlayer=function()return nil end},Facade={Encode=function()return "{}"end},
    injected={ExecuteInGameThread=function(callback)callback()end,ExecuteWithDelay=function()end,CancelDelayedAction=function()end},
    menu={Register=function(section)registered=section end,Set=function()end,SetLabel=function()end}}
assert(load(block,"fall-drop-registration","t",environment))()
assert(registered.id=="DWFallDropTest" and not started and dependencies.allOff()==false)
registered.items[1].onClick();assert(started==200)
registered.items[2].onClick();assert(started==400)
assert(not pcall(registered.items[3].onChange,true))
assert(#environment.adapterModules==1)
print("PASS fall drop registration, no startup mutation, exact 200-unit dispatch and enable rejection")
