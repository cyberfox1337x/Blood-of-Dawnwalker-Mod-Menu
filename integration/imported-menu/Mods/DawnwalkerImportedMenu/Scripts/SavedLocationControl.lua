local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("saved_location_control")
local M = {}
local function valid(o) return o ~= nil and o:IsValid() end
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
function M.Init(menu, helpers)
    local id, locations, pending, failed = "DWCoreTeleport", {}, nil, false
    local generation, sequence = 0, 0
    local namespace = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
    local function context()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a player first")
        local world, controller = player:GetWorld(), player.Controller
        assert(valid(world) and valid(controller) and valid(controller.Pawn)
            and controller.Pawn:GetAddress() == player:GetAddress(), "Player possession changed")
        return { player = player, world = world, controller = controller,
            playerAddress = player:GetAddress(), worldAddress = world:GetAddress(), controllerAddress = controller:GetAddress() }
    end
    local function live(record)
        for _, key in ipairs({ "player", "world", "controller" }) do
            assert(valid(record[key]) and record[key]:GetAddress() == record[key .. "Address"], "Saved location identity expired")
        end
    end
    local function transform(player)
        local p, r = player:K2_GetActorLocation(), player:K2_GetActorRotation()
        assert(p and r and finite(p.X) and finite(p.Y) and finite(p.Z)
            and finite(r.pitch) and finite(r.Yaw) and finite(r.Roll), "Invalid player transform")
        return { X = p.X, Y = p.Y, Z = p.Z }, { pitch = r.pitch, Yaw = r.Yaw, Roll = r.Roll }
    end
    local function matches(a, b)
        return a.playerAddress == b.playerAddress and a.worldAddress == b.worldAddress and a.controllerAddress == b.controllerAddress
    end
    local function distance(a, b) return (a.X-b.X)^2 + (a.Y-b.Y)^2 + (a.Z-b.Z)^2 end
    local function restore()
        if not pending then return end
        live(pending)
        assert(matches(pending, context()), "Cannot restore teleport across a changed player session")
        assert(pending.player:K2_TeleportTo(pending.location, pending.rotation) == true, "Teleport restoration refused")
        local current = transform(pending.player)
        assert(distance(current, pending.location) <= 100, "Teleport restoration readback failed")
        pending = nil; menu.Set(id, "cleanup", false)
    end
    local function save()
        local name = tostring(menu.Get(id, "name") or ""):match("^%s*(.-)%s*$")
        assert(#name > 0 and #name <= 64 and not name:find("[%z\1-\31\127;=]"), "Use a name of 1 to 64 characters without control characters, semicolons or equals signs")
        local record = context()
        record.location, record.rotation = transform(record.player)
        assert(matches(record, context()), "Player changed while saving position")
        local count = 0
        for _, existing in pairs(locations) do
            count = count + 1
            assert(existing.name:lower() ~= name:lower(), "That name is already saved. Choose a different name to keep both positions.")
        end
        assert(count < 32, "This session already has 32 saved locations")
        sequence = sequence + 1
        local locationId = "location-" .. namespace .. "-" .. generation .. "-" .. sequence
        record.name = name
        locations[locationId] = record
        local options = {}
        for key, saved in pairs(locations) do options[#options + 1] = { label = saved.name, value = key } end
        table.sort(options, function(a,b) return a.label:lower() < b.label:lower() end)
        menu.SetOptions(id, "destination", options, locationId)
        menu.SetLabel(id, "status", "Saved current position: " .. name)
    end
    local function teleport()
        assert(not failed and not pending, "Prior teleport failure requires cleanup and restarting")
        local destination = locations[menu.Get(id, "destination")]
        assert(destination, "Choose a location saved during this session")
        local current = context(); live(destination)
        assert(matches(destination, current), "Saved location belongs to another player or world")
        current.location, current.rotation = transform(current.player)
        pending = current; menu.Set(id, "cleanup", true)
        local ok, err = pcall(function()
            assert(current.player:K2_TeleportTo(destination.location, destination.rotation) == true, "Teleport refused")
            assert(matches(current, context()), "Player changed during teleport")
            local arrived = transform(current.player)
            assert(distance(arrived, destination.location) <= 100, "Teleport arrival readback failed")
        end)
        if not ok then
            failed = true
            local restored, restoreError = pcall(restore)
            menu.SetLabel(id, "status", restored and "Teleport failed; original position restored." or "STOP: teleport restoration unresolved. Reload the save.")
            error(tostring(err) .. (restored and "" or "; " .. tostring(restoreError)))
        end
        pending = nil; menu.Set(id, "cleanup", false)
        menu.SetLabel(id, "status", "Teleported to " .. destination.name .. "; destination verified.")
    end
    function M.ResetSession()
        assert(not pending, "Cannot discard unresolved teleport restoration")
        locations = {}; menu.SetOptions(id, "destination", {}, false); menu.Set(id, "name", "")
        generation = generation + 1
        menu.SetLabel(id, "status", "Save the current position to create a destination.")
    end
    menu.Register({ id = id, title = "Saved locations", tab = "Teleport", items = {
        { type = "input", id = "name", label = "Saved location name", default = "" },
        { type = "button", id = "save", label = "Save Location", onClick = save },
        { type = "dropdown", id = "destination", label = "Saved location", options = {} },
        { type = "button", id = "teleport", label = "Teleport", onClick = teleport },
        { type = "checkbox", id = "cleanup", label = "Teleport recovery pending", default = false,
          onChange = function(value) assert(value == false, "Recovery can only be released"); restore() end },
        { type = "label", id = "status", label = "Save the current position to create a destination." },
    } })
end
return M
