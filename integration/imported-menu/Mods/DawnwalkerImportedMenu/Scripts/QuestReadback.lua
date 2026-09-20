local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("quest_journal_readback_adapter")
local M = {}
local MAX_QUESTS, MAX_OBJECTIVES_PER_QUEST = 6, 3
local MAX_QUEST_TEXT_ENCODED_BYTES, MAX_QUEST_READBACK_BYTES = 240, 8192
local function is_finite_number(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
local function is_valid(o) return o ~= nil and o:IsValid() end
local function sanitize(v) return tostring(v):sub(1, 512) end
local function get_object_address(o)
    if not is_valid(o) then return nil end
    local address = o:GetAddress()
    return is_finite_number(address) and address > 0 and address or nil
end
local function object_matches_address(o, address) return address ~= nil and get_object_address(o) == address end
local function optional_object_address(o)
    local ok, address = pcall(get_object_address, o)
    return ok and address or nil
end
local function normalize_quest_text(value, fallback)
    local text = tostring(value or "")
    text = text:gsub("[%z\1-\31\127]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    if text == "" then return fallback end
    return text
end

local function encode_quest_character(character)
    local encoded = {}
    for index = 1, #character do
        local byte = character:byte(index)
        local safe = (byte >= 48 and byte <= 57)
            or (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or byte == 32 or byte == 39 or byte == 40 or byte == 41
            or byte == 45 or byte == 46 or byte == 95
        table.insert(encoded, safe and string.char(byte) or string.format("%%%02X", byte))
    end
    return table.concat(encoded)
end

local function percent_encode_quest_text(text)
    local pieces = {}
    local encoded_length = 0
    local truncated = false
    local encode_ok, encode_error = pcall(function()
        for _, codepoint in utf8.codes(text) do
            local piece = encode_quest_character(utf8.char(codepoint))
            if encoded_length + #piece > MAX_QUEST_TEXT_ENCODED_BYTES then
                truncated = true
                break
            end
            table.insert(pieces, piece)
            encoded_length = encoded_length + #piece
        end
    end)
    if not encode_ok then return nil, "Quest text was not valid UTF-8: " .. sanitize(encode_error) end

    if truncated then
        while #pieces > 0 and encoded_length + 3 > MAX_QUEST_TEXT_ENCODED_BYTES do
            local removed = table.remove(pieces)
            encoded_length = encoded_length - #removed
        end
        table.insert(pieces, "...")
    end
    return table.concat(pieces), nil
end

local function read_encoded_ftext(ftext, fallback)
    if ftext == nil then return nil, "Quest text was unavailable." end
    local read_ok, text = pcall(function() return ftext:ToString() end)
    if not read_ok or type(text) ~= "string" then return nil, "Quest text readback failed." end
    return percent_encode_quest_text(normalize_quest_text(text, fallback))
end

local function unwrap_remote_value(value)
    if value == nil then return nil end
    local unwrap_ok, unwrapped = pcall(function() return value:get() end)
    if unwrap_ok then return unwrapped end
    return value
end

local function normalized_quest_state(value)
    local numeric = tonumber(value)
    if numeric == 1 then return "active" end
    if numeric == 2 then return "success" end
    if numeric == 3 then return "failure" end

    local named = tostring(value or ""):lower()
    if named:find("active", 1, true) then return "active" end
    if named:find("success", 1, true) then return "success" end
    if named:find("failure", 1, true) then return "failure" end
    return "unknown"
end


function M.Init(menu, helpers)
local id = "DWQuestReadback"
local function get_live_player_context()
    local player = helpers.GetPlayer()
    if not is_valid(player) then return nil, nil, "Load a controlled player first" end
    local world, controller = player:GetWorld(), player.Controller
    local address = get_object_address(player)
    if not address or not is_valid(world) or not is_valid(controller)
        or not object_matches_address(controller.Pawn, address) then
        return nil, nil, "Player possession or world unavailable"
    end
    return player, { player_address = address, world_address = get_object_address(world) }
end
local function get_quest_journal(identity)
    local UEHelpers = helpers
    if type(UEHelpers.GetGameStateBase) ~= "function" then
        return nil, "The game-state helper is unavailable."
    end

    local state_ok, game_state = pcall(UEHelpers.GetGameStateBase)
    if not state_ok or not is_valid(game_state) then return nil, "The Dawnwalker game state is unavailable." end
    local class_ok, is_dawnwalker_state = pcall(function()
        return game_state:IsA("/Script/Dawnwalker.DawnwalkerGameStateBase")
    end)
    if not class_ok or not is_dawnwalker_state then return nil, "The resolved game state has the wrong class." end

    local world_ok, state_world = pcall(function() return game_state:GetWorld() end)
    if not world_ok or not object_matches_address(state_world, identity.world_address) then
        return nil, "The quest journal belongs to a different world identity."
    end

    local journal_ok, journal = pcall(function() return game_state.QuestJournal end)
    if not journal_ok or not is_valid(journal) then return nil, "The QuestJournal is not loaded." end
    local journal_class_ok, is_journal = pcall(function() return journal:IsA("/Script/Quest.Journal") end)
    if not journal_class_ok or not is_journal then return nil, "The QuestJournal has the wrong class." end
    return journal, nil
end

local function read_quest_objectives(quest)
    local objectives_ok, objectives = pcall(function() return quest.Objectives end)
    if not objectives_ok or objectives == nil then return nil, nil, "Quest Objectives were unavailable." end
    local count_ok, objective_count = pcall(function() return #objectives end)
    if not count_ok or not is_finite_number(objective_count) or objective_count < 0 or objective_count % 1 ~= 0 then
        return nil, nil, "Quest objective count was invalid."
    end

    local candidates = {}
    local iterate_ok, iterate_error = pcall(function()
        for index = 1, objective_count do
            local remote_objective = objectives[index]
            local objective = unwrap_remote_value(remote_objective)
            if objective == nil then error("Quest objective was unavailable.") end

            local fields_ok, text_value, state_value, current_count, max_count, optional = pcall(function()
                return objective.Text, objective.State, objective.CurrentCount, objective.MaxCount, objective.bIsOptional
            end)
            if not fields_ok then error("Quest objective fields were unavailable: " .. sanitize(text_value)) end
            if not is_finite_number(current_count) or current_count < 0 or current_count > 1000000000 then
                error("Quest objective current count was invalid.")
            end
            if not is_finite_number(max_count) or max_count < 0 or max_count > 1000000000 or max_count % 1 ~= 0 then
                error("Quest objective maximum count was invalid.")
            end
            if type(optional) ~= "boolean" then error("Quest objective optional state was invalid.") end

            local encoded_text, text_error = read_encoded_ftext(text_value, "Untitled objective")
            if not encoded_text then error(text_error) end
            local address = optional_object_address(objective)
            table.insert(candidates, {
                text = encoded_text,
                state = normalized_quest_state(state_value),
                current_count = current_count,
                max_count = math.floor(max_count),
                optional = optional,
                selection_key = address and ("address:" .. tostring(address)) or ("index:" .. tostring(index)),
            })
        end
    end)
    if not iterate_ok then return nil, nil, sanitize(iterate_error) end
    if #candidates ~= objective_count then return nil, nil, "Quest objective iteration returned an incomplete snapshot." end

    local records, selected = {}, {}
    local function select(record)
        if record == nil or selected[record.selection_key] or #records >= MAX_OBJECTIVES_PER_QUEST then return end
        selected[record.selection_key] = true
        table.insert(records, record)
    end
    for _, candidate in ipairs(candidates) do
        if candidate.state == "active" and not candidate.optional then
            select(candidate)
            break
        end
    end
    for _, candidate in ipairs(candidates) do select(candidate) end
    return objective_count, records, nil
end

local function read_quest_record(quest, tracked_address)
    if not is_valid(quest) then return nil, "An opened quest was no longer valid." end
    local class_ok, is_quest = pcall(function() return quest:IsA("/Script/Quest.Quest") end)
    if not class_ok or not is_quest then return nil, "An opened quest had the wrong class." end

    local fields_ok, title_value, state_value = pcall(function() return quest.Title, quest.State end)
    if not fields_ok then return nil, "Quest fields were unavailable: " .. sanitize(title_value) end
    local encoded_title, title_error = read_encoded_ftext(title_value, "Untitled quest")
    if not encoded_title then return nil, title_error end
    local objective_count, objectives, objective_error = read_quest_objectives(quest)
    if not objectives then return nil, objective_error end

    return {
        title = encoded_title,
        state = normalized_quest_state(state_value),
        tracked = tracked_address ~= nil and get_object_address(quest) == tracked_address,
        objective_count = objective_count,
        objectives = objectives,
    }, nil
end

local function handle_quest_journal()
    local _, identity, player_error = get_live_player_context()
    if not identity then return false, "rejected", player_error, "" end
    local journal, journal_error = get_quest_journal(identity)
    if not journal then return false, "rejected", journal_error, "" end

    local tracked_ok, tracked_quest = pcall(function() return journal:GetTrackedQuest() end)
    if not tracked_ok then return false, "rejected", "Tracked quest readback failed.", "" end
    local tracked_address = get_object_address(tracked_quest)

    local opened_out = {}
    local opened_ok, opened_error = pcall(function() journal:GetOpenedQuests(opened_out) end)
    if not opened_ok then
        return false, "rejected", "GetOpenedQuests readback failed: " .. sanitize(opened_error), ""
    end
    local opened_quests = opened_out
    local count_ok, open_quest_count = pcall(function() return #opened_quests end)
    if not count_ok or not is_finite_number(open_quest_count) or open_quest_count < 0 or open_quest_count % 1 ~= 0 then
        return false, "rejected", "Opened quest count was invalid.", ""
    end

    local candidates, quests, selected = {}, {}, {}
    local iterate_ok, iterate_error = pcall(function()
        for index = 1, open_quest_count do
            local remote_quest = opened_quests[index]
            local quest = unwrap_remote_value(remote_quest)
            if not is_valid(quest) then error("An opened quest was no longer valid.") end
            local address = get_object_address(quest)
            table.insert(candidates, {
                quest = quest,
                tracked = tracked_address ~= nil and address == tracked_address,
                selection_key = address and ("address:" .. tostring(address)) or ("index:" .. tostring(index)),
            })
        end

        local function select(candidate)
            if candidate == nil or selected[candidate.selection_key] or #quests >= MAX_QUESTS then return end
            local quest, quest_error = read_quest_record(candidate.quest, tracked_address)
            if not quest then error(quest_error) end
            selected[candidate.selection_key] = true
            table.insert(quests, quest)
        end
        for _, candidate in ipairs(candidates) do
            if candidate.tracked then
                select(candidate)
                break
            end
        end
        for _, candidate in ipairs(candidates) do select(candidate) end
    end)
    if not iterate_ok then return false, "rejected", "Quest Journal snapshot failed: " .. sanitize(iterate_error), "" end
    local unique_candidate_count, unique_candidate_keys = 0, {}
    for _, candidate in ipairs(candidates) do
        if not unique_candidate_keys[candidate.selection_key] then
            unique_candidate_keys[candidate.selection_key] = true
            unique_candidate_count = unique_candidate_count + 1
        end
    end
    local expected_quest_count = math.min(unique_candidate_count, MAX_QUESTS)
    if #quests ~= expected_quest_count then
        return false, "rejected", "Quest Journal iteration returned an incomplete snapshot.", ""
    end

    local records = {
        "schema=1",
        "open_total=" .. tostring(open_quest_count),
        "returned=" .. tostring(#quests),
        "truncated=" .. (open_quest_count > #quests and "1" or "0"),
    }
    for quest_index, quest in ipairs(quests) do
        local zero_based_index = quest_index - 1
        table.insert(records, table.concat({
            "q=" .. tostring(zero_based_index),
            quest.state,
            quest.tracked and "1" or "0",
            quest.title,
            tostring(quest.objective_count),
            quest.objective_count > #quest.objectives and "1" or "0",
        }, ","))
        for _, objective in ipairs(quest.objectives) do
            table.insert(records, table.concat({
                "o=" .. tostring(zero_based_index),
                objective.state,
                objective.text,
                string.format("%.6f", objective.current_count),
                tostring(objective.max_count),
                objective.optional and "1" or "0",
            }, ","))
        end
    end

    local readback = table.concat(records, ";")
    if #readback > MAX_QUEST_READBACK_BYTES then
        return false, "rejected", "Quest Journal exceeded its bounded readback size.", ""
    end
    local _, after = get_live_player_context()
    if not after or after.player_address ~= identity.player_address or after.world_address ~= identity.world_address then
        return false, "rejected", "Player/world changed during journal capture", ""
    end
    local afterJournal = get_quest_journal(after)
    if not object_matches_address(afterJournal, get_object_address(journal)) then
        return false, "rejected", "Journal changed during capture", ""
    end
    return true, "applied", string.format("Read %d open quest(s); returned %d bounded record(s).", open_quest_count, #quests), readback
end


local function refresh()
    menu.SetLabel(id, "snapshot", "")
    local ok, accepted, _, message, readback = pcall(handle_quest_journal)
    if not ok or not accepted then
        menu.SetLabel(id, "status", "Quest readback unavailable. Refresh after loading a save.")
        error(ok and message or accepted)
    end
    menu.SetLabel(id, "snapshot", readback)
    menu.SetLabel(id, "status", message)
end
function M.ResetSession()
    menu.SetLabel(id, "snapshot", "")
    menu.SetLabel(id, "status", "Refresh to read the current Quest Journal.")
end
-- Read the journal as the session comes up rather than leaving the panel on "Refresh to
-- read" with a save already loaded. Publishes only on success; a failure propagates so
-- the runtime retries, and the standing label stays accurate in the meantime.
function M.SessionReady()
    local ok, accepted, _, message, readback = pcall(handle_quest_journal)
    if not ok then error(accepted, 0) end
    if not accepted then error(message, 0) end
    menu.SetLabel(id, "snapshot", readback)
    menu.SetLabel(id, "status", message)
end
menu.Register({ id = id, title = "Quest Journal", tab = "Quests", items = {
    { type = "button", id = "refresh", label = "Refresh Quest Journal", onClick = refresh },
    { type = "label", id = "status", label = "Refresh to read the current Quest Journal." },
    { type = "label", id = "snapshot", label = "" },
} })
end
return M
