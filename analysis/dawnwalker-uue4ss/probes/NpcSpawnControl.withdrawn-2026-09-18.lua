local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("npc_spawn_control")

-- NPC spawning through the game's own population factory.
--
-- The only reflected spawn entry point is
--   USpawnPopulationActorAsyncAction::RunAsyncAction(WorldContext,
--       TSoftClassPtr<UCommunityNPCDefinitionBase> NPCDefinitionClass,
--       TSoftClassPtr<UAIDefinition> AIDefinitionClass, FVector Location, float Rotation)
-- (pinned dump Dawnwalker.hpp). Both definition arguments are soft class pointers, which
-- cannot be constructed from Lua. They are therefore *borrowed*: every loaded
-- URebelFormationGroupDefinition (the game's own combat-encounter recipes) carries
-- `Pawns[i].NPCDefinitionClass` / `Pawns[i].AIDefinitionClass` as exactly these types, and
-- every loaded UCommunityNPCDefinitionBase class carries `AIDefinition` on its CDO. The
-- native values are read from those properties and handed straight back to the factory,
-- so the game only ever spawns pairs it ships itself - nothing is reconstructed.
--
-- Spawns are owned: the pawns that appear after a request are the ones that were not there
-- before it, each is recorded, and "Remove spawned NPCs" destroys exactly those actors and
-- confirms each one is gone. A new session (save load, death) drops the record: the pawns
-- went with the old world.

local M = {}

local ACTION_CLASS = "/Script/Dawnwalker.SpawnPopulationActorAsyncAction"
local ACTION_CDO = "/Script/Dawnwalker.Default__SpawnPopulationActorAsyncAction"
local GROUP_DEFINITION_CLASS = "/Script/RebelFormation.RebelFormationGroupDefinition"
local NPC_DEFINITION_CLASS = "/Script/Population.CommunityNPCDefinitionBase"
local PAWN_CLASS = "/Script/Engine.Pawn"
local SPAWN_DISTANCE = 350
local SPAWN_TIMEOUT_TICKS, SPAWN_TICK_MS = 40, 500
local MAX_COUNT = 5

local function valid(object) return object ~= nil and object:IsValid() end

-- The soft pointer's asset path, as text, for labels only. Every accessor the runtime has
-- offered across versions is tried; an unreadable pointer is still usable for spawning.
local function softPathText(pointer)
    if pointer == nil then return nil end
    for _, read in ipairs({
        function() return pointer:GetAssetPathName():ToString() end,
        function() return pointer:GetAssetPathName() end,
        function() return pointer.AssetPathName:ToString() end,
        function() return pointer:ToString() end,
    }) do
        local ok, text = pcall(read)
        if ok and type(text) == "string" and #text > 0 and text ~= "None" then return text end
    end
    return nil
end

local function shortName(path)
    if not path then return "unnamed" end
    local base = path:match("([^./]+)$") or path
    return base:gsub("_C$", "")
end

function M.Init(menu, helpers, deps)
    deps = deps or {}
    local id = "DWNpcSpawn"
    local catalog, selected, owned = {}, nil, {}
    local pending = nil

    local function publish(message) menu.SetLabel(id, "status", message) end

    local function player()
        local pawn = helpers.GetPlayer()
        assert(valid(pawn), "Load a save before spawning NPCs.")
        return pawn
    end

    -- Every NPC/AI definition pair the game ships in its formation recipes, plus every loaded
    -- NPC definition class paired with the AI definition its own CDO names. Read-only.
    local function scan()
        catalog = {}
        local seen = {}
        local groups = FindAllOf("RebelFormationGroupDefinition") or {}
        for _, group in ipairs(groups) do
            if valid(group) and group:IsA(GROUP_DEFINITION_CLASS) and not group:GetFullName():find("Default__", 1, true) then
                local ok, count = pcall(function() return group.Pawns:GetArrayNum() end)
                for index = 1, (ok and count or 0) do
                    local entryOk, entry = pcall(function() return group.Pawns[index] end)
                    if entryOk and entry then
                        local npc, ai = entry.NPCDefinitionClass, entry.AIDefinitionClass
                        local npcPath, aiPath = softPathText(npc), softPathText(ai)
                        if npcPath and aiPath then
                            local key = npcPath .. "|" .. aiPath
                            if not seen[key] then
                                seen[key] = true
                                catalog[#catalog + 1] = { key = key, npc = npc, ai = ai, npcPath = npcPath, aiPath = aiPath,
                                    label = string.format("%s  [%s]", shortName(npcPath), shortName(aiPath)), source = group:GetFullName() }
                            end
                        end
                    end
                end
            end
        end
        table.sort(catalog, function(a, b) return a.label:lower() < b.label:lower() end)
        local options = {}
        for _, entry in ipairs(catalog) do options[#options + 1] = { label = entry.label, value = entry.key } end
        local still = nil
        for _, entry in ipairs(catalog) do if entry.key == selected then still = selected end end
        selected = still
        menu.SetOptions(id, "npc", #options > 0 and options or { { label = "No NPC recipes are loaded in this area", value = false } }, still or false)
        return #catalog, #groups
    end

    local function entryFor(key)
        for _, entry in ipairs(catalog) do if entry.key == key then return entry end end
        return nil
    end

    -- Set of every pawn currently in the world, by address, so new arrivals can be told apart.
    local function pawnSet()
        local set = {}
        for _, pawn in ipairs(FindAllOf("Pawn") or {}) do
            if valid(pawn) then set[pawn:GetAddress()] = true end
        end
        return set
    end

    local function describeOwned()
        local alive = 0
        for _, record in ipairs(owned) do if valid(record.pawn) then alive = alive + 1 end end
        menu.Set(id, "owned", alive > 0)
        return alive
    end

    local function spawnLocation(pawn, offsetIndex)
        local location = pawn:K2_GetActorLocation()
        local rotation = pawn:K2_GetActorRotation()
        local yaw = math.rad(rotation.Yaw)
        -- In front of the player, fanned sideways for repeated spawns, facing the player.
        local side = (offsetIndex - 1) * 120 - ((MAX_COUNT - 1) * 60)
        local forward = { x = math.cos(yaw), y = math.sin(yaw) }
        local right = { x = -math.sin(yaw), y = math.cos(yaw) }
        return {
            X = location.X + forward.x * SPAWN_DISTANCE + right.x * side,
            Y = location.Y + forward.y * SPAWN_DISTANCE + right.y * side,
            Z = location.Z,
        }, (rotation.Yaw + 180) % 360
    end

    local function finishPending(message)
        if pending and pending.loop then pcall(CancelDelayedAction, pending.loop) end
        pending = nil
        publish(message)
        describeOwned()
    end

    local function spawn(count)
        assert(not pending, "A spawn is still in progress; wait for it to finish.")
        local entry = assert(entryFor(selected), "Choose an NPC to spawn first.")
        assert(type(count) == "number" and count % 1 == 0 and count >= 1 and count <= MAX_COUNT, "Choose a count from 1 to " .. MAX_COUNT .. ".")
        local pawn = player()
        local factory = StaticFindObject(ACTION_CDO)
        assert(valid(factory) and factory:IsA(ACTION_CLASS), "The game's NPC spawn factory is unavailable.")
        local before = pawnSet()
        local actions = {}
        for index = 1, count do
            local location, yaw = spawnLocation(pawn, index)
            local action = factory:RunAsyncAction(pawn, entry.npc, entry.ai, location, yaw)
            assert(valid(action) and action:IsA(ACTION_CLASS), "The spawn factory returned no action.")
            -- A Blueprint async node activates its action after wiring the delegates; nothing
            -- wires them here, so the action is activated directly and the world is watched.
            action:Activate()
            actions[#actions + 1] = action
        end
        pending = { before = before, actions = actions, expected = count, ticks = 0, entry = entry }
        publish(string.format("Spawning %d x %s...", count, shortName(entry.npcPath)))
        -- The sandbox loop runs until its handle is cancelled (a callback's return value is
        -- not consulted), so every exit path goes through finishPending.
        pending.loop = LoopInGameThreadWithDelay(SPAWN_TICK_MS, function()
            if not pending then return end
            pending.ticks = pending.ticks + 1
            local found = 0
            for _, candidate in ipairs(FindAllOf("Pawn") or {}) do
                if valid(candidate) and not pending.before[candidate:GetAddress()] and candidate:IsA(PAWN_CLASS) then
                    local known = false
                    for _, record in ipairs(owned) do if record.pawn:GetAddress() == candidate:GetAddress() then known = true end end
                    if not known then
                        owned[#owned + 1] = { pawn = candidate, entry = pending.entry, address = candidate:GetAddress() }
                        pending.before[candidate:GetAddress()] = true
                    end
                    found = found + 1
                end
            end
            pending.arrived = (pending.arrived or 0) + found
            if pending.arrived >= pending.expected then
                finishPending(string.format("Spawned %d x %s. %d spawned NPC(s) alive; use Remove spawned NPCs to clear them.",
                    pending.expected, shortName(pending.entry.npcPath), describeOwned()))
                return
            end
            if pending.ticks >= SPAWN_TIMEOUT_TICKS then
                local spawnerAlive = 0
                for _, action in ipairs(pending.actions) do if valid(action) and valid(action.Spawner) then spawnerAlive = spawnerAlive + 1 end end
                finishPending(string.format("Spawn request for %s produced %d of %d pawns within %d s (%d spawner(s) created). The game may have refused this NPC here.",
                    shortName(pending.entry.npcPath), pending.arrived, pending.expected, SPAWN_TIMEOUT_TICKS * SPAWN_TICK_MS / 1000, spawnerAlive))
            end
        end)
    end

    local function despawn()
        assert(not pending, "A spawn is still in progress; wait for it to finish.")
        local removed, refused, remaining = 0, 0, {}
        for _, record in ipairs(owned) do
            if valid(record.pawn) then
                local ok = pcall(function() record.pawn:K2_DestroyActor() end)
                if ok and not valid(record.pawn) then removed = removed + 1
                else refused = refused + 1; remaining[#remaining + 1] = record end
            else
                removed = removed + 1
            end
        end
        owned = remaining
        describeOwned()
        assert(refused == 0, string.format("%d spawned NPC(s) could not be removed; %d removed.", refused, removed))
        publish(string.format("Removed %d spawned NPC(s).", removed))
    end

    local function queue(callback, ...)
        local arguments = { ... }
        ExecuteInGameThread(function()
            local ok, failure = pcall(callback, table.unpack(arguments))
            if not ok then publish("NPC spawn: " .. tostring(failure)); describeOwned(); error(failure, 0) end
        end)
    end

    menu.Register({ id = id, title = "Spawn NPC", tab = "NPC", items = {
        { type = "label", id = "status", label = "Scanning for the NPC recipes loaded in this area..." },
        { type = "dropdown", id = "npc", label = "NPC", options = {}, onChange = function(value) selected = value end },
        { type = "number", id = "count", label = "How many", default = 1, min = 1, max = MAX_COUNT, integer = true },
        { type = "button", id = "spawn", label = "Spawn in front of you", confirm = {
            title = "Spawn this NPC?",
            message = "Uses the game's own population factory with an NPC/AI pair the game ships in this area. Hostile recipes will attack you at once. Spawned NPCs are tracked and can be removed below; they are not part of any quest.",
            confirmLabel = "Spawn", cancelLabel = "Cancel" },
            onClick = function() queue(function() spawn(menu.Get(id, "count") or 1) end) end },
        { type = "button", id = "despawn", label = "Remove spawned NPCs", onClick = function() queue(despawn) end },
        { type = "button", id = "rescan", label = "Rescan NPC recipes", onClick = function() queue(function()
            local entries, groups = scan()
            publish(string.format("%d NPC recipe(s) from %d formation definition(s) loaded in this area.", entries, groups))
        end) end },
        { type = "checkbox", id = "owned", label = "Spawned NPCs alive", default = false, enabled = false },
        { type = "label", label = "Only NPC/AI definition pairs the game itself loads for this area are offered, read straight from its formation recipes, so the list changes with the region. Spawned NPCs behave like the game's own encounters: hostile ones fight, civilians idle. Remove destroys exactly the NPCs spawned here and confirms each one is gone; nothing else in the world is touched." },
    } })

    -- Scan once the session is up so the list is live before the first click. An empty
    -- scan is a valid answer (no recipes loaded here), so it never blocks the runner.
    function M.SessionReady()
        local entries, groups = scan()
        publish(entries > 0
            and string.format("%d NPC recipe(s) from %d formation definition(s) loaded in this area.", entries, groups)
            or "No NPC recipes are loaded in this area yet; they appear once the game has loaded an encounter nearby. Rescan later.")
    end

    function M.ResetSession()
        if pending and pending.loop then pcall(CancelDelayedAction, pending.loop) end
        pending = nil
        owned = {}
        catalog, selected = {}, nil
        menu.Set(id, "owned", false)
        menu.SetOptions(id, "npc", {}, false)
        publish("Scanning for the NPC recipes loaded in this area...")
    end

    return M
end

return M
