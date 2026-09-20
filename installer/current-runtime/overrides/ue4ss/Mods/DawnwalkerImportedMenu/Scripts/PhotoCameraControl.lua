local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("photo_camera_control")

-- Enter and leave the game's photo camera.
--
-- This is the rare fully reversible pair: EnterPhotoCamera and ExitPhotoCamera both
-- exist, and IsInCameraMode reports the actual mode, so every action is proved by a
-- readback and the camera can always be put back.

local M = {}

local PHOTO_CAMERA_CLASS = "/Script/DogwoodSystem.PhotoCameraActor"

local function valid(object) return object ~= nil and object:IsValid() end

function M.Init(menu, helpers)
    local id, entered = "DWPhotoCamera", false
    local enterField = { type = "button", id = "enter", label = "Enter photo camera", enabled = false }
    local exitField = { type = "button", id = "exit", label = "Exit photo camera", enabled = false }

    local function setAvailable(available)
        enterField.enabled = available == true
        exitField.enabled = available == true
    end

    local function unavailableMessage(reason)
        if tostring(reason):find("Photo camera actor is not present", 1, true) then
            return "Unavailable in this level: photo camera actor is not present."
        end
        return "Unavailable: " .. tostring(reason)
    end

    local function resolve()
        local player = helpers.GetPlayer()
        assert(valid(player), "Load a save before using the photo camera.")
        local camera = FindFirstOf("PhotoCameraActor")
        assert(valid(camera) and not camera:GetFullName():find("Default__", 1, true),
            "Photo camera actor is not present in this level.")
        assert(camera:IsA(PHOTO_CAMERA_CLASS), "Resolved object is not the photo camera actor.")
        return { player = player:GetAddress(), camera = camera, address = camera:GetAddress() }
    end

    local function inCameraMode(camera)
        local mode = camera:IsInCameraMode()
        assert(type(mode) == "boolean", "Photo camera mode reading is unavailable.")
        return mode
    end

    local function sync(message, mode)
        menu.Set(id, "active", mode == true)
        menu.SetLabel(id, "status", message)
    end

    local function refresh(silent)
        local ok, record = pcall(resolve)
        if not ok then
            setAvailable(false)
            local message = unavailableMessage(record)
            if silent and message:find("Unavailable in this level", 1, true) then
                sync(message, false)
                return
            end
            if not silent then sync(message, false) end
            error(record, 0)
        end
        setAvailable(true)
        local mode = inCameraMode(record.camera)
        entered = entered and mode
        sync(mode and "Photo camera is active." or "Photo camera is off.", mode)
    end

    -- Move the camera into the requested mode and prove it with IsInCameraMode.
    local function switch(target, verb)
        local ok, record = pcall(resolve)
        if not ok then
            setAvailable(false)
            sync(unavailableMessage(record), false)
            error(record, 0)
        end
        setAvailable(true)
        local before = inCameraMode(record.camera)
        if before == target then
            sync(string.format("Photo camera is already %s.", target and "active" or "off"), before)
            return
        end
        if target then record.camera:EnterPhotoCamera() else record.camera:ExitPhotoCamera() end
        local after = inCameraMode(record.camera)
        if after ~= target then
            sync(string.format("The game refused to %s the photo camera; it is still %s.",
                verb, after and "active" or "off"), after)
            error("Photo camera readback did not match the request")
        end
        entered = target
        sync(string.format("Verified: photo camera %s.", target and "entered" or "exited"), after)
    end

    -- A new session must not believe it still owns a previous session's camera.
    function M.ResetSession()
        entered = false
    end

    -- Read once the session is up so the panel is live before its first click. A level that
    -- has no photo-camera actor is a supported unavailable state, not a console failure.
    -- Other early-session failures remain retryable, and the Read button stays available.
    function M.SessionReady() refresh(true) end

    menu.Register({ id = id, title = "Photo camera", tab = "Visuals", items = {
        { type = "label", id = "status", label = "Read the photo camera to see whether it is active." },
        { type = "button", id = "refresh", label = "Read photo camera state", onClick = refresh },
        enterField,
        exitField,
        { type = "checkbox", id = "active", label = "Photo camera active", value = false },
        { type = "label", label = "Fully reversible: the game provides both an enter and an exit, and each is confirmed by reading the camera mode back." },
    } })

    enterField.onClick = function() switch(true, "enter") end
    exitField.onClick = function() switch(false, "exit") end

    return M
end

return M
