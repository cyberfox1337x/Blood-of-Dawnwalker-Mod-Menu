local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("world_speed_location_control")
local M = {}
local function valid(o) return o ~= nil and o:IsValid() end
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
function M.Init(menu, helpers)
    local id, owned, failed = "DWCoreWorld", nil, false
    local function context()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a controlled player first")
        local world, controller = player:GetWorld(), player.Controller
        assert(valid(world) and valid(controller) and valid(controller.Pawn)
            and controller.Pawn:GetAddress() == player:GetAddress(), "Player possession changed")
        local statics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        assert(valid(statics), "Gameplay statics unavailable")
        return { player = player, world = world, target = statics,
            playerAddress = player:GetAddress(), worldAddress = world:GetAddress(), targetAddress = statics:GetAddress() }
    end
    local function live(record)
        for _, key in ipairs({ "player", "world", "target" }) do
            assert(valid(record[key]) and record[key]:GetAddress() == record[key .. "Address"], "Owned speed identity expired")
        end
    end
    local function read(record)
        local speed = record.target:GetGlobalTimeDilation(record.world)
        assert(finite(speed) and speed > 0, "Invalid game speed readback")
        return speed
    end
    local function sync(speed, text)
        if speed then menu.Set(id, "speed", speed) end
        menu.Set(id, "owned", owned ~= nil)
        menu.SetLabel(id, "status", text)
    end
    local function restore()
        if not owned then return end
        live(owned)
        owned.target:SetGlobalTimeDilation(owned.world, owned.baseline)
        local actual = read(owned)
        assert(math.abs(actual - owned.baseline) <= .01, "Game speed restoration readback failed")
        owned = nil
        sync(actual, string.format("Game speed: %.2fx (original restored)", actual))
    end
    local function guarded(callback)
        ExecuteInGameThread(function()
            local ok, err = pcall(callback)
            if ok then return end
            failed = true
            local restored, restoreError = pcall(restore)
            sync(nil, restored and "Request failed; original speed restored." or "STOP: game speed cleanup remains unresolved. Restart and reload the save.")
            error(tostring(err) .. (restored and "" or "; " .. tostring(restoreError)))
        end)
    end
    local function setSpeed(value)
        guarded(function()
            assert(not failed, "Prior failure requires restarting and reloading the save")
            assert(finite(value) and value >= .1 and value <= 3, "Game speed must be between 0.1 and 3")
            local current = context()
            if owned then
                live(owned)
                assert(current.playerAddress == owned.playerAddress and current.worldAddress == owned.worldAddress
                    and current.targetAddress == owned.targetAddress, "Game speed belongs to another player or world")
            else
                current.baseline = read(current)
                owned = current
            end
            owned.target:SetGlobalTimeDilation(owned.world, value)
            local actual = read(owned)
            assert(math.abs(actual - value) <= .01, "Game speed setter readback failed")
            if math.abs(actual - owned.baseline) <= .01 then owned = nil end
            sync(actual, string.format("Game speed: %.2fx", actual))
        end)
    end
    local function refresh()
        local current = context()
        local speed = read(current)
        local location = current.player:K2_GetActorLocation()
        assert(location and finite(location.X) and finite(location.Y) and finite(location.Z), "Location readback is not finite")
        local after = context()
        assert(current.playerAddress == after.playerAddress and current.worldAddress == after.worldAddress, "Location identity changed")
        menu.SetLabel(id, "location", string.format("X: %.2f  Y: %.2f  Z: %.2f", location.X, location.Y, location.Z))
        sync(speed, string.format("Game speed: %.2fx", speed))
    end
    function M.ResetSession()
        assert(not owned, "Cannot discard unresolved game speed ownership")
        menu.SetLabel(id, "location", "Refresh to read the current location.")
    end
    -- Read once the session is up so the panel is live before its first click; the runner
    -- retries a failed read on later ticks, and the Read button stays for a manual re-read.
    function M.SessionReady() refresh() end
    menu.Register({ id = id, title = "World controls", tab = "World", items = {
        { type = "number", id = "speed", label = "Game Speed", min = .1, max = 3, step = .1, default = 1, onChange = setSpeed },
        -- StopControls deliberately visits this registered ownership flag even though
        -- the existing World UI presents a slider and Restore button instead.
        { type = "checkbox", id = "owned", label = "Speed override active", default = false,
          onChange = function(value) assert(value == false, "Use the Game Speed slider"); guarded(restore) end },
        { type = "button", id = "restore", label = "Restore game speed", onClick = function() guarded(restore) end },
        { type = "button", id = "refresh", label = "Refresh world readback", onClick = refresh },
        { type = "label", id = "status", label = "Refresh to read game speed." },
        { type = "label", id = "location", label = "Refresh to read the current location." },
    } })
    menu.OnOpen(refresh)
end
return M
