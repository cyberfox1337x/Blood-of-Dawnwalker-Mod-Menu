local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_preview_geometry_tests")
local Geometry = assert(dofile(assert(arg[1], "Pass the geometry module path")))
local count = 0
local function test(name, action) action(); count = count + 1; print("PASS " .. name) end
local function input()
    return { head_center = { X = 10, Y = 20, Z = 190 }, head_pivot = { X = 10, Y = 20, Z = 190 }, head_radius = 20,
        eye_left = { X = 18, Y = 17, Z = 197 }, eye_right = { X = 18, Y = 23, Z = 197 }, forward = { X = 1, Y = 0, Z = 0 } }
end
local function head_fixture(bones)
    return { GetNumBones = function() return #bones end,
        GetBoneName = function(_, index) return { ToString = function() return bones[index + 1] end } end,
        DoesSocketExist = function() return true end, GetSocketLocation = function() return { X = 0, Y = 0, Z = 1 } end }
end

test("head and eye framing use actual bounds with separate zoom endpoints and exact restoration", function()
    local geometry = Geometry.build_views(input())
    assert(#geometry.views == 9 and geometry.eye_distance == 6 and geometry.head_radius == 20)
    assert(geometry.views[2].yaw_degrees == -69 and geometry.views[3].yaw_degrees == 69)
    assert(geometry.views[2].location.Y < 20 and geometry.views[3].location.Y > 20)
    assert(geometry.views[4].pivot.X == 18 and geometry.views[4].pivot.Z == 197)
    assert(geometry.views[5].distance > geometry.views[1].distance and geometry.views[6].distance < geometry.views[1].distance)
    assert(geometry.views[7].distance > geometry.views[4].distance and geometry.views[8].distance < geometry.views[4].distance)
    for key, value in pairs(geometry.views[1].location) do assert(geometry.views[9].location[key] == value) end
    for _, view in ipairs(geometry.views) do
        local center = geometry.head_center
        local distance = math.sqrt((view.location.X - center.X)^2 + (view.location.Y - center.Y)^2 + (view.location.Z - center.Z)^2)
        assert(distance - geometry.head_radius > view.near_clip)
    end
end)

test("derived horizontal orbit follows current native facing", function()
    local original = input()
    original.forward = { X = 0, Y = 1, Z = 0 }
    local geometry = Geometry.build_views(original)
    assert(geometry.views[1].location.Y > 20 and geometry.views[1].location.X == 10)
    assert(geometry.views[2].location.X > 10 and geometry.views[3].location.X < 10)
end)

test("invalid radius, landmarks, facing and nonfinite input reject derived views", function()
    for _, scenario in ipairs({ "radius", "eyes", "landmark", "facing", "nonfinite" }) do
        local value = input()
        if scenario == "radius" then value.head_radius = 0
        elseif scenario == "eyes" then value.eye_left = value.eye_right
        elseif scenario == "landmark" then value.head_pivot.Z = 10000
        elseif scenario == "facing" then value.forward.X = 0
        else value.head_center.Z = math.huge end
        assert(not pcall(Geometry.build_views, value), scenario)
    end
end)

test("actual terminal eye pair is retained ahead of the first24 forehead matches", function()
    local bones = { "root", "Head", "neck_01" }
    for index = 1, 40 do bones[#bones + 1] = "FACIAL_C_ForeheadSkin" .. index end
    bones[#bones + 1], bones[#bones + 2] = "FACIAL_L_Eye", "FACIAL_R_Eye"
    local result = Geometry.observe_landmarks(head_fixture(bones))
    assert(#result.matches == 24 and result.omitted_matches == 20 and result.eye_pair_count == 1)
    assert(result.matches[1].name == "FACIAL_L_Eye" and result.matches[2].name == "FACIAL_R_Eye")
    assert(result.matches[3].name == "Head" and result.eye_pair.left.name == "FACIAL_L_Eye")
end)

test("ambiguous endpoint pairs are observed but do not select a usable eye pivot", function()
    local result = Geometry.observe_landmarks(head_fixture({ "Head", "FACIAL_L_Eye", "FACIAL_R_Eye", "eye_l", "eye_r" }))
    assert(result.eye_pair_count == 2 and result.eye_pair == nil)
    assert(Geometry.observe_landmarks(head_fixture({ "Head", "eyelid_l", "eyelid_r" })).eye_pair_count == 0)
end)

test("unknown socket, duplicate names and unbounded rigs fail closed", function()
    local invalid_socket = head_fixture({ "Head" })
    invalid_socket.DoesSocketExist = function() return false end
    assert(not pcall(Geometry.observe_landmarks, invalid_socket))
    assert(not pcall(Geometry.observe_landmarks, head_fixture({ "Head", "head" })))
    assert(not pcall(Geometry.observe_landmarks, { GetNumBones = function() return 2049 end }))
end)

print("PASS " .. count .. " eye preview geometry test groups")
