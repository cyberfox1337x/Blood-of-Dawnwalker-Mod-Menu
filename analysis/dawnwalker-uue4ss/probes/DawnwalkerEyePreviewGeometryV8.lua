local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_preview_geometry_v8")

local Geometry = {}
local PHASES = { "front", "yaw-min", "yaw-max", "eyes-closeup", "head-zoom-min", "head-zoom-max",
    "eyes-zoom-min", "eyes-zoom-max", "restored-front" }

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function finite(value, label)
    require_condition(type(value) == "number" and value == value and math.abs(value) < math.huge, label .. " is not finite")
    return value
end

local function vector(value)
    return { X = finite(value.X, "X"), Y = finite(value.Y, "Y"), Z = finite(value.Z, "Z") }
end

local function distance(left, right)
    return math.sqrt((left.X - right.X)^2 + (left.Y - right.Y)^2 + (left.Z - right.Z)^2)
end

local function eye_partner(name)
    local prefix = name:match("^(.-)_l_eye$")
    if prefix then return prefix .. "_r_eye" end
    prefix = name:match("^(.-)eye_l$")
    if prefix then return prefix .. "eye_r" end
    return nil
end

-- Exact terminal eye pairs outrank the many forehead/eyelid bones in this native rig.
function Geometry.observe_landmarks(head)
    local count = head:GetNumBones()
    require_condition(type(count) == "number" and count % 1 == 0 and count >= 1 and count <= 2048,
        "Head skeleton exceeds the observation bound")
    local names, candidates, pairs_found = {}, {}, {}
    for index = 0, count - 1 do
        local bone = head:GetBoneName(index)
        local name = bone:ToString()
        require_condition(type(name) == "string" and #name >= 1 and #name <= 128, "Invalid native bone name")
        local lower = name:lower()
        require_condition(names[lower] == nil, "Native skeleton has ambiguous case-insensitive bone names")
        local entry = { index = index, name = name, native = bone }
        names[lower] = entry
        local rank = (eye_partner(lower) or lower:match("_r_eye$") or lower:match("eye_r$")) and 1
            or lower == "head" and 2 or lower:find("eye", 1, true) and 3
            or lower:find("neck", 1, true) and 4 or lower:find("head", 1, true) and 5 or nil
        if rank then entry.rank = rank; candidates[#candidates + 1] = entry end
    end
    for lower, entry in pairs(names) do
        local partner = eye_partner(lower)
        if partner and names[partner] then pairs_found[#pairs_found + 1] = { left = entry, right = names[partner] } end
    end
    table.sort(candidates, function(left, right)
        if left.rank == right.rank then return left.index < right.index end
        return left.rank < right.rank
    end)
    local result = { bone_count = count, matches = {}, omitted_matches = math.max(0, #candidates - 24), eye_pair_count = #pairs_found }
    for index = 1, math.min(24, #candidates) do
        local entry = candidates[index]
        require_condition(head:DoesSocketExist(entry.native) == true, "Observed landmark is not a current socket")
        result.matches[index] = { index = entry.index, name = entry.name, location = vector(head:GetSocketLocation(entry.native)) }
    end
    if #pairs_found == 1 then
        local pair = pairs_found[1]
        require_condition(head:DoesSocketExist(pair.left.native) == true and head:DoesSocketExist(pair.right.native) == true,
            "Eye endpoints are not current sockets")
        result.eye_pair = { left = { name = pair.left.name, index = pair.left.index, location = vector(head:GetSocketLocation(pair.left.native)) },
            right = { name = pair.right.name, index = pair.right.index, location = vector(head:GetSocketLocation(pair.right.native)) } }
    end
    return result
end

function Geometry.phase_names()
    local result = {}
    for index, phase in ipairs(PHASES) do result[index] = phase end
    return result
end

local function framing(pivot, half_extent, field_of_view, center, radius)
    local near_clip = 1
    -- The enclosing sphere remains in front of the near plane throughout the full orbit.
    local clearance = radius + distance(pivot, center) + near_clip + math.max(1, radius * 0.05)
    local default_distance = math.max(clearance * 1.15, half_extent / math.tan(math.rad(field_of_view / 2)))
    require_condition(default_distance <= 5000, "Native head bounds require an unsupported camera distance")
    return { pivot = pivot, field_of_view = field_of_view, near_clip = near_clip, safe_distance = clearance,
        default_distance = default_distance, minimum_distance = math.max(clearance, default_distance * 0.78),
        maximum_distance = default_distance * 1.35 }
end

function Geometry.build_views(input)
    local center, head, left, right, forward = vector(input.head_center), vector(input.head_pivot),
        vector(input.eye_left), vector(input.eye_right), vector(input.forward)
    local radius = finite(input.head_radius, "native head radius")
    require_condition(radius >= 2 and radius <= 200, "Native head radius is outside supported framing bounds")
    require_condition(distance(head, center) <= radius * 2.5, "Head socket and native mesh bounds disagree")
    local eye_distance = distance(left, right)
    require_condition(eye_distance >= 0.5 and eye_distance <= 25 and distance(left, center) <= radius * 2.5
        and distance(right, center) <= radius * 2.5, "Native eye pair is outside supported head bounds")
    local forward_length = math.sqrt(forward.X^2 + forward.Y^2)
    require_condition(forward_length >= 0.5 and forward_length <= 1.5 and math.abs(forward.Z) <= 0.5, "Player facing is not a usable horizontal preview basis")
    forward.X, forward.Y = forward.X / forward_length, forward.Y / forward_length
    local eyes_pivot = { X = (left.X + right.X) / 2, Y = (left.Y + right.Y) / 2, Z = (left.Z + right.Z) / 2 }
    -- V7's 1.65-radius half-span framed almost the entire torso. The measured
    -- eye spacing centers this crop below the eyes while full head bounds still
    -- determine near-plane clearance for every orbit and zoom endpoint.
    local head_pivot = { X = center.X, Y = center.Y, Z = eyes_pivot.Z - eye_distance * 1.2 }
    local shoulder_half_span = math.max(radius * 1.05, eye_distance * 4.5)
    local profiles = {
        ["head-and-shoulders"] = framing(head_pivot, shoulder_half_span, 30, center, radius),
        ["eyes-close-up"] = framing(eyes_pivot, eye_distance * 1.1, 20, center, radius),
    }
    local function view(phase, profile_name, yaw, zoom)
        local profile = profiles[profile_name]
        local camera_distance = zoom == "minimum" and profile.maximum_distance
            or zoom == "maximum" and profile.minimum_distance or profile.default_distance
        local angle = math.rad(yaw)
        local direction = { X = forward.X * math.cos(angle) - forward.Y * math.sin(angle),
            Y = forward.X * math.sin(angle) + forward.Y * math.cos(angle) }
        local pivot = profile.pivot
        return { phase = phase, framing = profile_name, yaw_degrees = yaw, zoom = zoom, pivot = vector(pivot),
            distance = camera_distance, field_of_view = profile.field_of_view, near_clip = profile.near_clip,
            location = { X = pivot.X + direction.X * camera_distance, Y = pivot.Y + direction.Y * camera_distance, Z = pivot.Z } }
    end
    local views = {
        view(PHASES[1], "head-and-shoulders", 0, "default"), view(PHASES[2], "head-and-shoulders", -69, "default"),
        view(PHASES[3], "head-and-shoulders", 69, "default"), view(PHASES[4], "eyes-close-up", 0, "default"),
        view(PHASES[5], "head-and-shoulders", 0, "minimum"), view(PHASES[6], "head-and-shoulders", 0, "maximum"),
        view(PHASES[7], "eyes-close-up", 0, "minimum"), view(PHASES[8], "eyes-close-up", 0, "maximum"),
        view(PHASES[9], "head-and-shoulders", 0, "default"),
    }
    return { profiles = profiles, views = views, head_center = center, head_radius = radius, eye_distance = eye_distance }
end

return Geometry
