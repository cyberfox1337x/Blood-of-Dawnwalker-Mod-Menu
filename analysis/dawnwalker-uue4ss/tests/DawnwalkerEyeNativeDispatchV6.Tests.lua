local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_native_dispatch_tests")
local calls = {}
local function observed(name)
    return function(deps) calls[#calls + 1] = { name = name, deps = deps }; return { ok = true } end
end
package.loaded.DawnwalkerEyeNativePilot = { run = observed("pilot") }
package.loaded.DawnwalkerEyePreviewReadOnlyProbe = { run = observed("preview") }
package.loaded.DawnwalkerEyeFrameExportProbe = { run = observed("export"), run_camera_roundtrip = observed("camera") }
package.loaded.DawnwalkerEyeVariantReadOnlyProbe = { run = observed("variants") }
package.loaded.DawnwalkerPrivateEyePreviewProbe = { run = observed("private-preview") }
package.loaded.DawnwalkerEyePreviewGeometry = { observe_landmarks = function() return {} end }
package.loaded.DawnwalkerHumanIrisRoundtripProbe = { run = observed("human-iris") }
package.loaded.DawnwalkerInventoryEyeCaptureProbe = { run = function(deps, phase, sample)
    calls[#calls + 1] = { name = "inventory-capture", deps = deps, phase = phase, sample = sample }
    return { ok = true, phase = phase, nonce = deps.nonce, boot_id = deps.boot_id }
end }
local Dispatch = dofile(assert(arg[1], "Pass dispatcher path"))
assert(#calls == 0, "Import must perform no native work")
local count = 0
local function test(name, run) calls = {}; run(); count = count + 1; print("PASS " .. name) end
local function deps(operation) return { operation = operation, boot_id = "1000-123", nonce = string.rep("a", 32) } end
test("observe dispatches only getters and current native preview observation", function()
    local result = Dispatch.run(deps("observe"))
    assert(result.ok and #calls == 2 and calls[1].name == "pilot" and calls[2].name == "preview")
    assert(not result.gameplay_verified and result.production_capabilities == "none")
end)
test("material operations cannot invoke camera or export code", function()
    for _, operation in ipairs({ "private-instance-roundtrip", "color-roundtrip" }) do
        calls = {}
        assert(Dispatch.run(deps(operation)).ok and #calls == 1 and calls[1].name == "pilot")
        assert(calls[1].deps.operation == operation and calls[1].deps.capture_frames == nil)
    end
end)
test("export receives native observation dependency without changing camera", function()
    assert(Dispatch.run(deps("export")).ok and #calls == 1 and calls[1].name == "export")
    assert(type(calls[1].deps.preview_probe) == "function" and calls[1].deps.capture_frames == nil)
end)
test("camera operation explicitly requests all three artifact phases", function()
    assert(Dispatch.run(deps("camera-roundtrip")).ok and #calls == 1 and calls[1].name == "camera")
    assert(calls[1].deps.capture_frames == true and type(calls[1].deps.preview_probe) == "function")
end)
test("unknown operations do not enter a native module", function()
    assert(not Dispatch.run(deps("arbitrary-command")).ok and #calls == 0)
end)
test("variant observation invokes only its read-only module", function()
    local result = Dispatch.run(deps("variant-observe"))
    assert(result.ok and result.schema == 5 and #calls == 1 and calls[1].name == "variants")
    assert(calls[1].deps.observe_head_landmarks == package.loaded.DawnwalkerEyePreviewGeometry.observe_landmarks)
end)
test("private preview pins actual observed Head pivot without enabling player controls", function()
    local input = deps("private-preview-roundtrip")
    input.pivot_bone_name = "untrusted arbitrary request"
    local result = Dispatch.run(input)
    assert(result.ok and #calls == 1 and calls[1].name == "private-preview" and calls[1].deps.pivot_bone_name == "Head")
    assert(result.production_capabilities == "none" and not result.gameplay_verified)
end)

test("human iris uses only the owned inventory phase adapter and native scalar pilot", function()
    local input = deps("human-iris-pair-roundtrip")
    local result = Dispatch.run(input)
    assert(result.ok and result.schema == 5 and #calls == 1 and calls[1].name == "human-iris")
    assert(input.preview_probe == package.loaded.DawnwalkerEyePreviewReadOnlyProbe.run)
    assert(type(input.capture_callback) == "function" and input.pivot_bone_name == nil)
    local sample = { phase = "changed", nonce = input.nonce, boot_id = input.boot_id }
    local receipt = input.capture_callback("changed", sample)
    assert(receipt.ok and #calls == 2 and calls[2].name == "inventory-capture")
    assert(calls[2].deps == input and calls[2].phase == "changed" and calls[2].sample == sample)
    assert(not result.gameplay_verified and result.production_capabilities == "none")
end)
test("report encoding and incremental byte bound reject injected or oversized data", function()
    local report = Dispatch.format_lines({ value = "Name\nInjected%", ok = true })
    assert(report:find("Name%0AInjected%25", 1, true))
    assert(not pcall(Dispatch.format_lines, { value = string.rep("x", 1048576) }))
end)
print("Eye native dispatcher: " .. count .. " tests passed")
