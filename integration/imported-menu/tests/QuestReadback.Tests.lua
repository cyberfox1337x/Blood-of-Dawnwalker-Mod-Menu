local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("quest_readback_tests")
local path = assert(arg[1])
local function fixture(quests, tracked_index)
    local serial = 0
    local function object(class)
        serial = serial + 1
        return { address = serial, valid = true, IsValid = function(o) return o.valid end,
            GetAddress = function(o) return o.address end, IsA = function(_, name) return name == class end }
    end
    local player, world, controller = object("Player"), object("World"), object("Controller")
    player.Controller, controller.Pawn = controller, player
    player.GetWorld = function() return world end
    local journal, state = object("/Script/Quest.Journal"), object("/Script/Dawnwalker.DawnwalkerGameStateBase")
    state.QuestJournal, state.GetWorld = journal, function() return world end
    journal.GetTrackedQuest = function() return quests[tracked_index or 1] end
    journal.GetOpenedQuests = function(_, output) for i, q in ipairs(quests) do output[i] = q end end
    local values, items = {}, {}
    local menu = { Register = function(section) for _, item in ipairs(section.items) do items[item.id] = item end end,
        SetLabel = function(_, key, value) values[key] = value end }
    local module = assert(loadfile(path))()
    module.Init(menu, { GetPlayer = function() return player end, GetGameStateBase = function() return state end })
    return { refresh = items.refresh.onClick, values = values, module = module, journal = journal,
        player = player, world = world, state = state, object = object }
end
local function text(value) return { ToString = function() return value end } end
local quest_address = 899
local function quest(name, objectives)
    quest_address = quest_address + 1
    local address = quest_address
    return { IsValid = function() return true end, IsA = function(_, value) return value == "/Script/Quest.Quest" end,
        GetAddress = function() return address end, Title = text(name), State = 1, Objectives = objectives or {} }
end
local count = 0
local function test(name, fn) local ok, err = pcall(fn); assert(ok, name .. ": " .. tostring(err)); count = count + 1; print("PASS " .. name) end
test("valid empty journal differs from unavailable", function()
    local f = fixture({}); f.refresh()
    assert(f.values.snapshot == "schema=1;open_total=0;returned=0;truncated=0")
end)
test("tracked quest and objective encoding retains separators safely", function()
    local f = fixture({quest("A;B,é", {{Text=text("Find=one"), State=1, CurrentCount=1, MaxCount=2,bIsOptional=true}})})
    f.refresh(); assert(f.values.snapshot:find("A%3BB%2C%C3%A9",1,true))
    assert(f.values.snapshot:find("q=0,active,1,",1,true)); assert(f.values.snapshot:find("Find%3Done",1,true))
end)
test("quest and objective counts are bounded", function()
    local quests = {}
    for i=1,9 do
        local objectives={}
        for j=1,5 do objectives[j]={Text=text("Step"),State=1,CurrentCount=0,MaxCount=1,bIsOptional=false} end
        quests[i]=quest("Quest "..i,objectives)
    end
    local f=fixture(quests); f.refresh()
    assert(f.values.snapshot:find("open_total=9;returned=6;truncated=1",1,true))
    local _, objectiveCount=f.values.snapshot:gsub(";o=",""); assert(objectiveCount==18)
    assert(#f.values.snapshot<=8192)
end)
test("tracked quest after the quest limit is returned first without duplicates", function()
    local quests = {}
    for index = 1, 9 do quests[index] = quest("Quest " .. index) end
    local f = fixture(quests, 9)
    f.refresh()

    assert(f.values.snapshot:find("schema=1;open_total=9;returned=6;truncated=1", 1, true))
    assert(f.values.snapshot:find(";q=0,active,1,Quest 9,0,0", 1, true))
    assert(f.values.snapshot:find(";q=1,active,0,Quest 1,0,0", 1, true))
    assert(f.values.snapshot:find(";q=5,active,0,Quest 5,0,0", 1, true))
    assert(not f.values.snapshot:find("Quest 6", 1, true))
    assert(not f.values.snapshot:find("Quest 7", 1, true))
    assert(not f.values.snapshot:find("Quest 8", 1, true))
    local _, tracked_count = f.values.snapshot:gsub(",1,Quest 9,", "")
    assert(tracked_count == 1)
    local _, quest_count = f.values.snapshot:gsub(";q=", "")
    assert(quest_count == 6)
    assert(#f.values.snapshot <= 8192)
end)
test("duplicate quest addresses are emitted once", function()
    local repeated = quest("Repeated")
    local quests = {quest("One"), repeated, quest("Two"), quest("Three"), quest("Four"), repeated}
    local f = fixture(quests, 6)
    f.refresh()

    assert(f.values.snapshot:find("schema=1;open_total=6;returned=5;truncated=1", 1, true))
    assert(f.values.snapshot:find(";q=0,active,1,Repeated,0,0", 1, true))
    local _, repeated_count = f.values.snapshot:gsub("Repeated", "")
    assert(repeated_count == 1)
end)
test("first active required objective after the objective limit is returned first", function()
    local objectives = {
        {Text=text("Completed first"),State=2,CurrentCount=1,MaxCount=1,bIsOptional=false},
        {Text=text("Optional active"),State=1,CurrentCount=0,MaxCount=1,bIsOptional=true},
        {Text=text("Completed third"),State=2,CurrentCount=1,MaxCount=1,bIsOptional=false},
        {Text=text("Optional later"),State=1,CurrentCount=0,MaxCount=1,bIsOptional=true},
        {Text=text("Current required"),State=1,CurrentCount=0,MaxCount=2,bIsOptional=false},
    }
    local f = fixture({quest("Objective priority", objectives)})
    f.refresh()

    assert(f.values.snapshot:find(";q=0,active,1,Objective priority,5,1", 1, true))
    assert(f.values.snapshot:find(";o=0,active,Current required,0.000000,2,0", 1, true))
    assert(f.values.snapshot:find(";o=0,success,Completed first,1.000000,1,0", 1, true))
    assert(f.values.snapshot:find(";o=0,active,Optional active,0.000000,1,1", 1, true))
    assert(not f.values.snapshot:find("Completed third", 1, true))
    assert(not f.values.snapshot:find("Optional later", 1, true))
    local first_objective = f.values.snapshot:match(";o=0,([^;]+)")
    assert(first_objective == "active,Current required,0.000000,2,0")
    local _, current_count = f.values.snapshot:gsub("Current required", "")
    assert(current_count == 1)
    local _, objective_count = f.values.snapshot:gsub(";o=", "")
    assert(objective_count == 3)
    assert(#f.values.snapshot <= 8192)
end)
test("wrong game state world clears previous readback", function()
    local f=fixture({}); f.refresh(); f.state.GetWorld=function() return f.object("OtherWorld") end
    assert(not pcall(f.refresh)); assert(f.values.snapshot=="")
end)
test("player change during capture discards snapshot", function()
    local f=fixture({}); f.journal.GetOpenedQuests=function() f.player.address=100 end
    assert(not pcall(f.refresh)); assert(f.values.snapshot=="")
end)
test("journal change during capture discards snapshot", function()
    local f=fixture({})
    f.journal.GetOpenedQuests=function() f.state.QuestJournal=f.object("/Script/Quest.Journal") end
    assert(not pcall(f.refresh)); assert(f.values.snapshot=="")
end)
test("malformed objective and UTF8 rejected", function()
    for _, q in ipairs({quest("Bad\255"),quest("Bad count",{{Text=text("Step"),State=1,CurrentCount=math.huge,MaxCount=1,bIsOptional=false}})}) do
        local f=fixture({q}); assert(not pcall(f.refresh)); assert(f.values.snapshot=="")
    end
end)
test("session reset removes all old journal data", function()
    local f=fixture({quest("Old")}); f.refresh(); f.module.ResetSession(); assert(f.values.snapshot=="")
end)
print(string.format("%d QuestReadback tests passed",count))
