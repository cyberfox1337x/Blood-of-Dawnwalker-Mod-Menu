local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("fall_damage_observation_tests")
local M = assert(loadfile(assert(arg[1])))()
local function object(id) return {IsValid=function()return true end,GetAddress=function()return id end} end
local player, component, effect = object(1), object(2), object(3)
player.FallDamageComponent=component;player.GetWorld=function()return object(4)end
local callbacks, removed = {}, 0
local pilot=M.New({GetPlayer=function()return player end,StaticFindObject=function(path)
    return path:find("Default__",1,true) and effect or object(5)
end,RegisterHook=function(path,pre,post)callbacks[path]={pre,post};return 1,2 end,
UnregisterHook=function()removed=removed+1 end})
local function wrap(value)return{get=function()return value end}end
pilot.start()
local fall, magnitude=callbacks[M.FALL],callbacks[M.MAGNITUDE]
assert(magnitude[1](wrap(object(8)),wrap({Def=effect}))==nil)
assert(pilot.snapshot().exactSpecCalls==0)
assert(fall[1](wrap(component),wrap(player))==nil)
assert(magnitude[1](wrap(object(8)),wrap({Def=effect}))==nil)
magnitude[1](wrap(object(8)),wrap({Def=object(9)}))
fall[2]()
assert(pilot.snapshot().exactSpecCalls==1 and pilot.snapshot().scopedCalls==2 and pilot.snapshot().depth==0)
fall[1](wrap(object(99)),wrap(player));magnitude[1](wrap(object(8)),wrap({Def=effect}));fall[2]()
assert(pilot.snapshot().exactSpecCalls==1)
pilot.stop();assert(removed==2 and pilot.snapshot().mutationAuthorized==false)
print("PASS exact fall scope, other receiver/spec rejection, nil hook returns and paired cleanup")
