local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_native_operation_dispatch")
local Pilot = require("DawnwalkerEyeNativePilot")
local Preview = require("DawnwalkerEyePreviewReadOnlyProbe")
local Export = require("DawnwalkerEyeFrameExportProbe")
local Variants = require("DawnwalkerEyeVariantReadOnlyProbe")
local PrivatePreview = require("DawnwalkerPrivateEyePreviewProbe")
local Geometry = require("DawnwalkerEyePreviewGeometry")
local HumanIris = require("DawnwalkerHumanIrisRoundtripProbe")
local InventoryCapture = require("DawnwalkerInventoryEyeCaptureProbe")
local Operations = {}

function Operations.run(deps)
    local result
    if deps.operation == "observe" then
        result = { native = Pilot.run(deps), preview = Preview.run(deps) }
        result.ok = result.native.ok and result.preview.ok
    elseif deps.operation == "private-instance-roundtrip" or deps.operation == "color-roundtrip" then
        result = Pilot.run(deps)
    elseif deps.operation == "export" then
        deps.preview_probe = Preview.run
        result = Export.run(deps)
    elseif deps.operation == "camera-roundtrip" then
        deps.preview_probe, deps.capture_frames = Preview.run, true
        result = Export.run_camera_roundtrip(deps)
    elseif deps.operation == "variant-observe" then
        deps.observe_head_landmarks = Geometry.observe_landmarks
        result = Variants.run(deps)
    elseif deps.operation == "private-preview-roundtrip" then
        deps.pivot_bone_name = "Head"
        result = PrivatePreview.run(deps)
    elseif deps.operation == "human-iris-pair-roundtrip" then
        deps.preview_probe = Preview.run
        deps.capture_callback = function(phase, sample) return InventoryCapture.run(deps, phase, sample) end
        result = HumanIris.run(deps)
    else
        result = { ok = false, reason = "Unsupported explicitly requested eye operation" }
    end
    result.schema, result.operation, result.boot_id, result.nonce = 7, deps.operation, deps.boot_id, deps.nonce
    result.gameplay_verified, result.production_capabilities = false, "none"
    return result
end

function Operations.format_lines(result)
    local lines, bytes = {}, 0
    local function visit(prefix, value, depth)
        assert(depth <= 20 and #lines < 20000, "Eye operation report exceeds bounds")
        if type(value) == "table" then
            local keys = {}
            for key in pairs(value) do keys[#keys + 1] = key end
            table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
            for _, key in ipairs(keys) do visit(prefix .. "." .. tostring(key), value[key], depth + 1) end
        else
            local encoded = tostring(value):gsub("[%%\r\n]", function(character) return string.format("%%%02X", string.byte(character)) end)
            local line = prefix .. "=" .. encoded
            bytes = bytes + #line + 1
            assert(bytes <= 1048576, "Eye operation report exceeds one MiB")
            lines[#lines + 1] = line
        end
    end
    visit("eye_pilot", result, 0)
    return table.concat(lines, "\n")
end

return Operations
