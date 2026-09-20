local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_preview_read_only_probe")

-- Existing-object discovery only. This module does not create, render, or change a preview.
local Probe = {}
local BUILD_ID = "25129649"
local EXECUTABLE_SHA256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
local PLAYER_CLASS = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local DOLL_CLASS = "/Script/DogwoodInventory.InventoryRenderDoll"
local MESH_CLASS = "/Script/Engine.SkeletalMeshComponent"
local CAPTURE_CLASS = "/Script/Engine.SceneCaptureComponent2D"
local TARGET_CLASS = "/Script/Engine.TextureRenderTarget2D"
local MESH_FIELDS = { "LeaderMeshComponent", "HeadMeshComponent", "HairMeshComponent", "EyebrowMeshComponent",
    "BeardMeshComponent", "TorsoMeshComponent", "HandMeshComponent", "LegMeshComponent", "FeetMeshComponent" }
local LIGHT_FIELDS = { "Key Light Spot", "Fill Light Spot", "Rim Light Spot", "Fill Weapon Light Spot" }

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function finite_number(value, label)
    require_condition(type(value) == "number" and value == value and math.abs(value) < math.huge,
        label .. " is not finite")
    return value
end

local function bounded_integer(value, minimum, maximum, label)
    finite_number(value, label)
    require_condition(value % 1 == 0 and value >= minimum and value <= maximum, label .. " exceeds its bound")
    return value
end

local function text(value, label)
    require_condition(type(value) == "string" and #value > 0 and #value <= 1024, label .. " is invalid")
    return value
end

local function object_record(object, expected_class, label)
    require_condition(object ~= nil and object:IsValid() == true, label .. " is unavailable")
    if expected_class then require_condition(object:IsA(expected_class) == true, label .. " class mismatch") end
    local name = text(object:GetFullName(), label .. " name")
    require_condition(name:find("Default__", 1, true) == nil, label .. " is a class default")
    local address = finite_number(object:GetAddress(), label .. " address")
    require_condition(address > 0, label .. " address is invalid")
    return { name = name, address = tostring(address) }
end

local function optional_object(object, expected_class, label)
    if object == nil or object:IsValid() ~= true then return { unset = true } end
    return object_record(object, expected_class, label)
end

local function same_object(object, previous, expected_class, label)
    local current = optional_object(object, expected_class, label)
    require_condition(current.unset == previous.unset and current.address == previous.address
        and current.name == previous.name, label .. " changed during preview probe")
end

local function observe(reader)
    local ok, result = pcall(reader)
    if ok then return { ok = true, value = result } end
    return { ok = false, reason = tostring(result) }
end

local function array_entries(array, maximum, label)
    require_condition(array ~= nil, label .. " is unavailable")
    local ok, count = pcall(function() return array:GetArrayNum() end)
    -- FindAllOf returns a Lua list; reflected arrays use GetArrayNum.
    if not ok then ok, count = pcall(function() return #array end) end
    require_condition(ok, label .. " length is unavailable")
    bounded_integer(count, 0, maximum, label .. " count")
    local entries = {}
    for index = 1, count do
        local entry = array[index]
        -- Reflected array elements can be RemoteUnrealParam wrappers.
        local unwrapped, raw = pcall(function() return entry:get() end)
        if unwrapped then entry = raw end
        require_condition(entry ~= nil, label .. " has a missing element")
        entries[index] = entry
    end
    return entries
end

local function vector(value, label)
    return { x = finite_number(value.X, label .. " X"), y = finite_number(value.Y, label .. " Y"),
        z = finite_number(value.Z, label .. " Z") }
end

local function rotation(value, label)
    return { pitch = finite_number(value.Pitch, label .. " pitch"), yaw = finite_number(value.Yaw, label .. " yaw"),
        roll = finite_number(value.Roll, label .. " roll") }
end

local function boolean(value, label)
    require_condition(type(value) == "boolean", label .. " is not a boolean")
    return value
end

local function record_fields(object, fields, validator)
    local result = {}
    for _, field in ipairs(fields) do
        result[field] = observe(function() return validator(object[field], field) end)
    end
    return result
end

local function object_list(array, label, expected_class)
    local result = {}
    for _, object in ipairs(array_entries(array, 64, label)) do
        result[#result + 1] = observe(function()
            -- Weak-object properties may expose Get rather than an object directly.
            local direct_ok, record = pcall(object_record, object, expected_class, label)
            if direct_ok then return record end
            local dereferenced_ok, dereferenced = pcall(function() return object:Get() end)
            require_condition(dereferenced_ok, label .. " object cannot be read: " .. tostring(record))
            return object_record(dereferenced, expected_class, label)
        end)
    end
    return result
end

local function mesh_record(mesh, doll, field)
    local record = optional_object(mesh, MESH_CLASS, field)
    if record.unset then return record end
    same_object(mesh:GetOwner(), object_record(doll, DOLL_CLASS, "doll"), DOLL_CLASS, field .. " owner")
    record.asset = optional_object(mesh:GetSkeletalMeshAsset(), "/Script/Engine.SkeletalMesh", field .. " asset")
    local count = bounded_integer(mesh:GetNumMaterials(), 0, 32, field .. " material count")
    local names = array_entries(mesh:GetMaterialSlotNames(), 32, field .. " slot names")
    require_condition(#names == count, field .. " material names/count disagree")
    record.materials = {}
    for index = 0, count - 1 do
        local material = mesh:GetMaterial(index)
        local binding = optional_object(material, "/Script/Engine.MaterialInterface", field .. " material")
        binding.slot = index
        binding.slot_name = text(names[index + 1]:ToString(), field .. " slot name")
        if not binding.unset then
            binding.dynamic = material:IsA("/Script/Engine.MaterialInstanceDynamic") == true
        end
        record.materials[#record.materials + 1] = binding
    end
    return record
end

local function target_record(target)
    local record = object_record(target, TARGET_CLASS, "render target")
    record.width = bounded_integer(target.SizeX, 1, 8192, "render width")
    record.height = bounded_integer(target.SizeY, 1, 8192, "render height")
    record.format = bounded_integer(target.RenderTargetFormat, 0, 255, "render target format")
    record.override_format = bounded_integer(target.OverrideFormat, 0, 255, "override format")
    record.gamma = finite_number(target.TargetGamma, "render target gamma")
    record.flags = record_fields(target, { "SRGB", "bForceLinearGamma", "bHDR", "bGPUSharedFlag" }, boolean)
    return record
end

local function capture_record(capture, doll)
    local record = object_record(capture, CAPTURE_CLASS, "scene capture")
    same_object(capture:GetOwner(), object_record(doll, DOLL_CLASS, "doll"), DOLL_CLASS, "scene capture owner")
    record.target = target_record(capture.TextureTarget)
    record.location = observe(function() return vector(capture:K2_GetComponentLocation(), "capture location") end)
    record.rotation = observe(function() return rotation(capture:K2_GetComponentRotation(), "capture rotation") end)
    record.fields = record_fields(capture, { "ProjectionType", "FOVAngle", "OrthoWidth", "PrimitiveRenderMode",
        "CaptureSource", "PostProcessBlendWeight", "CustomNearClippingPlane" }, finite_number)
    record.flags = record_fields(capture, { "bCaptureEveryFrame", "bCaptureOnMovement", "bMainViewCamera",
        "bMainViewFamily", "bMainViewResolution", "bRenderInMainRenderer", "bSuppressWorldPostProcessing",
        "bOverride_CustomNearClippingPlane" }, boolean)
    record.lists = {}
    for _, field in ipairs({ "ShowOnlyActors", "HiddenActors", "ShowOnlyComponents", "HiddenComponents" }) do
        record.lists[field] = observe(function() return object_list(capture[field], field, nil) end)
    end
    return record
end

local function doll_record(doll, player, world_record)
    local record = object_record(doll, DOLL_CLASS, "doll")
    require_condition(record.address ~= object_record(player, PLAYER_CLASS, "player").address, "doll aliases the player")
    same_object(doll:GetWorld(), world_record, "/Script/Engine.World", "doll world")
    record.inventory = object_record(doll.TargetInventory, "/Script/DogwoodInventory.InventoryComponent", "doll inventory")
    same_object(doll.TargetInventory:GetOwner(), object_record(player, PLAYER_CLASS, "player"), PLAYER_CLASS, "inventory owner")
    record.appearance = optional_object(doll.AppearanceToApply, "/Script/DogwoodInventory.AppearanceBase", "doll appearance")
    record.location = observe(function() return vector(doll:K2_GetActorLocation(), "doll location") end)
    record.rotation = observe(function() return rotation(doll:K2_GetActorRotation(), "doll rotation") end)
    record.capture = capture_record(doll.SceneCapture, doll)
    record.meshes = {}
    for _, field in ipairs(MESH_FIELDS) do record.meshes[field] = mesh_record(doll[field], doll, field) end
    require_condition(not record.meshes.HeadMeshComponent.unset and not record.meshes.HeadMeshComponent.asset.unset,
        "doll head mesh or asset is unavailable")
    record.lights = {}
    for _, field in ipairs(LIGHT_FIELDS) do
        record.lights[field] = observe(function()
            local light = doll[field]
            local light_record = optional_object(light, "/Script/Engine.LightComponentBase", field)
            if light_record.unset then return light_record end
            same_object(light:GetOwner(), object_record(doll, DOLL_CLASS, "doll"), DOLL_CLASS, field .. " owner")
            light_record.intensity = finite_number(light.Intensity, field .. " intensity")
            local color = light:GetLightColor()
            light_record.color = { r = finite_number(color.R, "light red"), g = finite_number(color.G, "light green"),
                b = finite_number(color.B, "light blue"), a = finite_number(color.A, "light alpha") }
            return light_record
        end)
    end
    return record
end

local function verify_doll(doll, record, player, world_record)
    same_object(doll, record, DOLL_CLASS, "doll")
    same_object(doll:GetWorld(), world_record, "/Script/Engine.World", "doll world")
    same_object(doll.TargetInventory, record.inventory, "/Script/DogwoodInventory.InventoryComponent", "doll inventory")
    same_object(doll.TargetInventory:GetOwner(), object_record(player, PLAYER_CLASS, "player"), PLAYER_CLASS, "inventory owner")
    same_object(doll.AppearanceToApply, record.appearance, "/Script/DogwoodInventory.AppearanceBase", "doll appearance")
    same_object(doll.SceneCapture, record.capture, CAPTURE_CLASS, "scene capture")
    same_object(doll.SceneCapture:GetOwner(), record, DOLL_CLASS, "scene capture owner")
    local target = doll.SceneCapture.TextureTarget
    same_object(target, record.capture.target, TARGET_CLASS, "render target")
    require_condition(target.SizeX == record.capture.target.width and target.SizeY == record.capture.target.height
        and target.RenderTargetFormat == record.capture.target.format and target.OverrideFormat == record.capture.target.override_format,
        "render target dimensions or format changed during preview probe")
    for _, field in ipairs(MESH_FIELDS) do
        local mesh, previous = doll[field], record.meshes[field]
        same_object(mesh, previous, MESH_CLASS, field)
        if not previous.unset then
            same_object(mesh:GetOwner(), record, DOLL_CLASS, field .. " owner")
            same_object(mesh:GetSkeletalMeshAsset(), previous.asset, "/Script/Engine.SkeletalMesh", field .. " asset")
            require_condition(mesh:GetNumMaterials() == #previous.materials, field .. " material count changed")
            local names = array_entries(mesh:GetMaterialSlotNames(), 32, field .. " slot names after probe")
            require_condition(#names == #previous.materials, field .. " slot count changed")
            for _, material in ipairs(previous.materials) do
                same_object(mesh:GetMaterial(material.slot), material, "/Script/Engine.MaterialInterface", field .. " material")
                require_condition(names[material.slot + 1]:ToString() == material.slot_name, field .. " slot name changed")
            end
        end
    end
end

function Probe.run(deps)
    local ok, result = pcall(function()
        require_condition(type(deps) == "table" and type(deps.get_player) == "function"
            and type(deps.find_all_of) == "function", "preview probe dependencies are incomplete")
        require_condition(deps.game_thread == true, "preview probe requires the game thread")
        require_condition(type(deps.identity) == "table" and deps.identity.build_id == BUILD_ID
            and deps.identity.executable_sha256 == EXECUTABLE_SHA256, "preview discovery build attestation mismatch")
        local player = deps.get_player()
        local player_record = object_record(player, PLAYER_CLASS, "player")
        local world_record = object_record(player:GetWorld(), "/Script/Engine.World", "world")
        local form = bounded_integer(player.Form, 0, 1, "player form")
        local wolf = boolean(player:IsInWolfForm(), "wolf form")
        local snapshot = { ok = true, mutation_authorized = false, gameplay_verified = false, preview_verified = false,
            player = player_record, world = world_record, form = form, is_wolf_form = wolf, dolls = {}, observed_doll_count = 0,
            player_location = observe(function() return vector(player:K2_GetActorLocation(), "player location") end),
            player_rotation = observe(function() return rotation(player:K2_GetActorRotation(), "player rotation") end),
            limitation = "Existing native doll metadata only; isolated rotation, neutral lighting, live frame transport and corresponding eye settings are not verified." }
        local candidates = array_entries(deps.find_all_of("InventoryRenderDoll") or {}, 8, "existing dolls")
        local seen, successful = {}, {}
        for _, doll in ipairs(candidates) do
            local name = text(doll:GetFullName(), "candidate name")
            if not name:find("Default__", 1, true) then
                local identity = object_record(doll, DOLL_CLASS, "doll candidate")
                require_condition(not seen[identity.address], "duplicate doll candidate")
                seen[identity.address] = true
                local candidate = observe(function() return doll_record(doll, player, world_record) end)
                snapshot.dolls[#snapshot.dolls + 1] = candidate
                if candidate.ok then
                    snapshot.observed_doll_count = snapshot.observed_doll_count + 1
                    successful[#successful + 1] = { object = doll, record = candidate.value }
                end
            end
        end
        for _, candidate in ipairs(successful) do verify_doll(candidate.object, candidate.record, player, world_record) end
        local current = deps.get_player()
        same_object(current, player_record, PLAYER_CLASS, "player")
        same_object(current:GetWorld(), world_record, "/Script/Engine.World", "player world")
        require_condition(current.Form == form and current:IsInWolfForm() == wolf, "player form changed during preview probe")
        return snapshot
    end)
    if ok then return result end
    return { ok = false, mutation_authorized = false, gameplay_verified = false, preview_verified = false, reason = tostring(result) }
end

function Probe.format_lines(result)
    local lines = {}
    local function visit(prefix, entry, depth)
        require_condition(depth <= 18 and #lines < 20000, "preview report exceeds its bound")
        if type(entry) == "table" then
            local keys = {}
            for key in pairs(entry) do keys[#keys + 1] = key end
            table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
            for _, key in ipairs(keys) do visit(prefix .. "." .. tostring(key), entry[key], depth + 1) end
        else
            local encoded = tostring(entry):gsub("[%%\r\n]", function(character)
                return string.format("%%%02X", string.byte(character))
            end)
            lines[#lines + 1] = prefix .. "=" .. encoded
        end
    end
    visit("eye_preview", result, 0)
    return table.concat(lines, "\n")
end

return Probe
