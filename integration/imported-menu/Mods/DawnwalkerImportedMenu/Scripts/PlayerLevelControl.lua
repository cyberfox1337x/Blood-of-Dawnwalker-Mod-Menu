local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("player_level_control")
local M = {}
local function valid(object) return object ~= nil and object:IsValid() end
local function integer(value) return type(value) == "number" and value == value and value % 1 == 0 end
function M.Init(menu, helpers)
    local id, observed, generation = "DWCoreLevel", nil, 0
    local path = "/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem"
    local function context()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a player before reading the level.")
        local world, controller = player:GetWorld(), player.Controller
        assert(valid(world) and valid(controller) and valid(controller.Pawn)
            and controller.Pawn:GetAddress() == player:GetAddress(), "Player possession changed; read the level again.")
        local library = StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary")
        local class = StaticFindObject(path)
        assert(valid(library) and valid(class), "Character development reflection is unavailable.")
        local subsystem = library:GetGameInstanceSubsystem(player, class)
        assert(valid(subsystem) and subsystem:IsA(path), "Character development subsystem is unavailable.")
        return { player = player:GetAddress(), world = world:GetAddress(), controller = controller:GetAddress(),
            subsystem = subsystem, address = subsystem:GetAddress() }
    end
    local function same(a, b)
        return a.player == b.player and a.world == b.world and a.controller == b.controller and a.address == b.address
    end
    local function read()
        local record = context()
        local settings = StaticFindObject("/Script/DogwoodCharacterDevelopment.Default__DogwoodCharacterDevelopmentSettings")
        assert(valid(settings) and settings:IsA("/Script/DogwoodCharacterDevelopment.DogwoodCharacterDevelopmentSettings"),
            "Live level settings are unavailable; the level range cannot be verified.")
        local cap = settings.LevelCap
        -- LevelCap is a reflected int8. This bounds enumeration without inventing a game cap.
        assert(integer(cap) and cap >= 1 and cap <= 127, "The live level cap is invalid.")
        local current = record.subsystem:GetCurrentLevel()
        assert(integer(current) and current >= 0 and current <= cap, "Current level is outside the live level range.")
        local requirements, hasRequirement = {}, false
        record.settingsAddress = settings:GetAddress()
        for level = 1, cap do
            local requirement = record.subsystem:GetCurrentLevelXPRequirement(level)
            assert(integer(requirement) and requirement >= 0 and requirement < math.huge,
                "The live experience table could not be verified at level " .. level .. ".")
            requirements[level] = requirement
            if requirement > 0 then hasRequirement = true end
        end
        assert(current == cap or hasRequirement, "The live experience requirements are empty; the level range cannot be verified.")
        assert(same(record, context()), "Player changed while reading the level.")
        record.current, record.cap, record.requirements = current, cap, requirements
        return record
    end
    local function sync(record, message)
        observed = record
        local options = {}
        if record then
            menu.Set(id, "current", record.current)
            menu.Set(id, "cap", record.cap)
            for level = record.current + 1, record.cap do options[#options + 1] = { label = tostring(level), value = level } end
        else
            menu.Set(id, "current", nil); menu.Set(id, "cap", nil)
        end
        menu.SetOptions(id, "target", options, false)
        menu.SetLabel(id, "status", message)
    end
    local function refresh(silent)
        if not silent then sync(nil, "Reading current level and live experience requirements...") end
        local ok, record = pcall(read)
        if not ok then if not silent then sync(nil, "Unavailable: " .. tostring(record)) end; error(record, 0) end
        sync(record, "Current level " .. record.current .. "; verified game cap " .. record.cap .. ". Raising the level grants trait points and cannot be undone here.")
    end
    local function apply()
        local target = menu.Get(id, "target")
        assert(observed and integer(target) and target > observed.current and target <= observed.cap,
            "Read the live level and choose a higher target first.")
        local baseline, token = observed, generation
        menu.Confirm({ title = "Raise player level?", message = "Raise level from " .. baseline.current .. " to " .. target
            .. " and grant the game's trait points. This progression change cannot be reversed here. Keep a save backup.", confirmLabel = "Apply level " .. target,
            onConfirm = function()
                assert(token == generation, "Player session changed; read the level again.")
                local before = read()
                -- The identity must be the one the targets were built for, and the level the
                -- player saw must still be the live level; each mismatch is named so a refusal
                -- says what moved.
                assert(same(baseline, before), "Player session changed; read the level again.")
                assert(before.settingsAddress == baseline.settingsAddress, "The level settings object was replaced; read the level again.")
                assert(before.current == baseline.current, string.format(
                    "Player level changed from %d to %d since it was read; read the level again.", baseline.current, before.current))
                assert(before.cap == baseline.cap, string.format(
                    "Level cap changed from %d to %d since it was read; read the level again.", baseline.cap, before.cap))
                for level = 1, before.cap do assert(before.requirements[level] == baseline.requirements[level], "Experience requirements changed.") end
                observed = nil
                menu.SetOptions(id, "target", {}, false)
                local ok, result = pcall(function()
                    before.subsystem:ForceLevelUpTo(target, true)
                    local after = read()
                    assert(same(before, after) and after.current == target, "Exact level readback failed; progression may have changed. Reload your backup before saving.")
                    return after
                end)
                if not ok then sync(nil, "STOP: " .. tostring(result)); error(result) end
                sync(result, "Player level " .. result.current .. " verified by the game.")
            end })
    end
    function M.ResetSession() generation = generation + 1; sync(nil, "Read the current level to discover valid targets.") end
    -- Read once the session is up so the panel is live before its first click; the runner
    -- retries a failed read on later ticks, and the Read button stays for a manual re-read.
    function M.SessionReady() refresh(true) end
    menu.Register({ id = id, title = "Player level", tab = "Player", items = {
        { id = "current", type = "label", label = "Current level" },
        { id = "cap", type = "label", label = "Verified level cap" },
        { id = "target", type = "dropdown", label = "Target player level", options = {} },
        { id = "refresh", type = "button", label = "Read player level", onClick = refresh },
        { id = "apply", type = "button", label = "Apply player level", onClick = apply },
        { id = "status", type = "label", label = "Read the current level to discover valid targets." },
    } })
end
return M
