local cyberfox1337x = { function_signature = function(_module_name) end }
cyberfox1337x.function_signature("dawnwalker_eye_head_material_read_only_probe")

-- Discovery only: no hooks, writes, dynamic-instance creation, or automatic run.
-- These pins identify the inspected discovery build, not a promoted gameplay build.
local Probe = {}
local BUILD_ID = "25129649"
local EXECUTABLE_SHA256 = "7AD7D09645B0589DC0FF78B53AA1A7B18ECA79B1B7F888B403AB41D88AC7E853"
local PLAYER_CLASS = "/Script/Dawnwalker.DawnwalkerPlayerCharacter"
local MESH_CLASS = "/Script/Engine.SkeletalMeshComponent"
local INSTANCE_CLASS = "/Script/Engine.MaterialInstance"

local function require_condition(condition, message)
    if condition ~= true then error(message, 0) end
end

local function number(value, label)
    require_condition(type(value) == "number" and value == value and math.abs(value) < math.huge,
        label .. " is not finite")
    return value
end

local function text(value, label)
    require_condition(type(value) == "string" and #value > 0 and #value <= 1024, label .. " is invalid")
    return value
end

local function object_record(object, expected_class, label, allow_default)
    require_condition(object ~= nil and object:IsValid() == true, label .. " is unavailable")
    if expected_class then require_condition(object:IsA(expected_class) == true, label .. " class mismatch") end
    local name = text(object:GetFullName(), label .. " name")
    require_condition(allow_default == true or name:find("Default__", 1, true) == nil, label .. " is a class default")
    local address = number(object:GetAddress(), label .. " address")
    require_condition(address > 0, label .. " address is invalid")
    return { name = name, address = tostring(address) }
end

local function array_entries(array, maximum, label)
    require_condition(array ~= nil, label .. " is unavailable")
    local ok, count = pcall(function() return array:GetArrayNum() end)
    if not ok then ok, count = pcall(function() return #array end) end
    require_condition(ok, label .. " length is unavailable")
    number(count, label .. " count")
    require_condition(count % 1 == 0 and count >= 0 and count <= maximum, label .. " exceeds its bound")
    local entries = {}
    for index = 1, count do
        local entry = array[index]
        local unwrapped, raw = pcall(function() return entry:get() end)
        if unwrapped then entry = raw end
        require_condition(entry ~= nil, label .. " has a missing element")
        entries[index] = entry
    end
    return entries
end

local function parameter_record(parameter)
    local info = parameter.ParameterInfo
    local association = number(info.Association, "parameter association")
    local index = number(info.Index, "parameter index")
    require_condition(association % 1 == 0 and association >= 0 and association <= 2,
        "parameter association is unsupported")
    require_condition(index % 1 == 0 and index >= -1 and index <= 128, "parameter layer index is unsupported")
    return { name = text(info.Name:ToString(), "parameter name"), association = association, index = index }
end

local function parameter_key(record)
    return tostring(#record.name) .. ":" .. record.name .. ":" .. record.association .. ":" .. record.index
end

local function consume(budget, kind, count)
    if count > budget[kind] then
        budget.exhausted = kind
        error("eye capture global " .. kind .. " budget exhausted", 0)
    end
    budget[kind] = budget[kind] - count
end

local function local_parameters(material, observed, depth, budget)
    local result = { scalar = {}, vector = {}, texture = {} }
    local seen = {}
    local function entries(array, label)
        local values = array_entries(array, 128, label)
        consume(budget, "parameters", #values)
        return values
    end
    local function remember(kind, entry, record)
        local key = kind .. ":" .. parameter_key(record)
        require_condition(not seen[key], "duplicate parameter identity in a material layer")
        seen[key] = true
        observed[#observed + 1] = { kind = kind, record = record, info = entry.ParameterInfo, depth = depth }
    end
    for _, entry in ipairs(entries(material.ScalarParameterValues, "scalar parameters")) do
        local record = parameter_record(entry)
        record.value = number(entry.ParameterValue, "scalar value")
        result.scalar[#result.scalar + 1] = record
        remember("scalar", entry, record)
    end
    for _, entry in ipairs(entries(material.VectorParameterValues, "vector parameters")) do
        local record = parameter_record(entry)
        record.r = number(entry.ParameterValue.R, "red")
        record.g = number(entry.ParameterValue.G, "green")
        record.b = number(entry.ParameterValue.B, "blue")
        record.a = number(entry.ParameterValue.A, "alpha")
        result.vector[#result.vector + 1] = record
        remember("vector", entry, record)
    end
    for _, entry in ipairs(entries(material.TextureParameterValues, "texture parameters")) do
        local record = parameter_record(entry)
        local texture = entry.ParameterValue
        if texture ~= nil and texture:IsValid() == true then
            record.texture = object_record(texture, "/Script/Engine.Texture", "texture")
        else
            record.unset = true
        end
        result.texture[#result.texture + 1] = record
        remember("texture", entry, record)
    end
    return result
end

local function effective_parameters(material, observed, budget)
    local result, seen = {}, {}
    local dynamic = material:IsA("/Script/Engine.MaterialInstanceDynamic") == true
    local constant = material:IsA("/Script/Engine.MaterialInstanceConstant") == true
    for _, item in ipairs(observed) do
        local key = item.kind .. ":" .. parameter_key(item.record)
        if not seen[key] then
            seen[key] = true
            consume(budget, "getters", 1)
            local record = { kind = item.kind, name = item.record.name, association = item.record.association,
                index = item.record.index, nearest_override_depth = item.depth }
            local ok, value = pcall(function()
                -- Preserve the observed native FMaterialParameterInfo for dynamic getters.
                -- Constant getters cannot address layer/blend parameters without losing identity.
                require_condition(dynamic or (constant and record.association == 0 and record.index == -1),
                    "no reflected getter preserves this parameter identity on the current material")
                if item.kind == "scalar" then
                    local scalar
                    if dynamic then scalar = material:K2_GetScalarParameterValueByInfo(item.info)
                    else scalar = material:K2_GetScalarParameterValue(item.info.Name) end
                    return { value = number(scalar, "effective scalar") }
                elseif item.kind == "vector" then
                    local color
                    if dynamic then color = material:K2_GetVectorParameterValueByInfo(item.info)
                    else color = material:K2_GetVectorParameterValue(item.info.Name) end
                    return { r = number(color.R, "effective red"), g = number(color.G, "effective green"),
                        b = number(color.B, "effective blue"), a = number(color.A, "effective alpha") }
                end
                local texture
                if dynamic then texture = material:K2_GetTextureParameterValueByInfo(item.info)
                else texture = material:K2_GetTextureParameterValue(item.info.Name) end
                if texture == nil or texture:IsValid() ~= true then return { unset = true } end
                return { texture = object_record(texture, "/Script/Engine.Texture", "effective texture") }
            end)
            record.ok = ok
            record.observed_override = {}
            for field, override in pairs(item.record) do
                if field ~= "name" and field ~= "association" and field ~= "index" then record.observed_override[field] = override end
            end
            if ok then record.readback = value else record.reason = tostring(value) end
            result[#result + 1] = record
        end
    end
    return result
end

local function material_chain(material, budget)
    local chain, visited, observed = {}, {}, {}
    local leaf = material
    for depth = 1, 8 do
        consume(budget, "material_layers", 1)
        local record = object_record(material, "/Script/Engine.MaterialInterface", "material")
        require_condition(not visited[record.address], "material parent cycle")
        visited[record.address] = true
        record.dynamic = material:IsA("/Script/Engine.MaterialInstanceDynamic") == true
        record.depth = depth - 1
        chain[#chain + 1] = record
        if material:IsA(INSTANCE_CLASS) ~= true then
            record.base_material = true
            local effective = effective_parameters(leaf, observed, budget)
            -- Retain the exact chain and nearest override values, without repeating every inherited override.
            for _, layer in ipairs(chain) do layer.overrides = nil end
            return chain, effective
        end
        record.overrides = local_parameters(material, observed, depth - 1, budget)
        material = material.Parent
        require_condition(material ~= nil and material:IsValid() == true, "material parent is unavailable")
    end
    error("material parent chain exceeds eight levels", 0)
end

local function optional_object_record(object, expected_class, label)
    if object == nil or object:IsValid() ~= true then return { unset = true } end
    return object_record(object, expected_class, label)
end

local function head_components(player, deps)
    local mesh_class = deps.static_find_object(MESH_CLASS)
    object_record(mesh_class, "/Script/CoreUObject.Class", "skeletal mesh class")
    local head = object_record(player.HeadMesh, MESH_CLASS, "player head mesh")
    local components = array_entries(player:K2_GetComponentsByClass(mesh_class), 32, "player meshes")
    local matching, seen = {}, {}
    for _, component in ipairs(components) do
        local record = object_record(component, MESH_CLASS, "player mesh membership")
        require_condition(not seen[record.address], "duplicate player mesh")
        seen[record.address] = true
        if record.address == head.address and record.name == head.name then matching[#matching + 1] = component end
    end
    require_condition(#matching == 1, "HeadMesh must occur exactly once in the local player component list")
    return matching
end

local function materials(player, deps)
    local budget = { slots = 128, material_layers = 256, parameters = 2048, getters = 4096 }
    local components = head_components(player, deps)
    local records, seen_components, material_references = {}, {}, {}
    for _, component in ipairs(components) do
        local record = object_record(component, MESH_CLASS, "skeletal mesh")
        require_condition(not seen_components[record.address], "duplicate player mesh")
        seen_components[record.address] = true
        require_condition(object_record(component:GetOwner(), PLAYER_CLASS, "mesh owner").address == tostring(player:GetAddress()),
            "mesh belongs to another actor")
        local count = number(component:GetNumMaterials(), "material count")
        require_condition(count % 1 == 0 and count >= 0 and count <= 32, "material count exceeds its bound")
        local names = array_entries(component:GetMaterialSlotNames(), 32, "material slot names")
        require_condition(#names == count, "material slot name count differs from material count")
        record.asset = optional_object_record(component:GetSkeletalMeshAsset(), "/Script/Engine.SkeletalMesh", "mesh asset")
        record.materials = {}
        for index = 0, count - 1 do
            consume(budget, "slots", 1)
            local material = component:GetMaterial(index)
            local entry = { slot = index }
            if names[index + 1] then entry.slot_name = text(names[index + 1]:ToString(), "slot name") end
            local ok, chain, readbacks = pcall(function() return material_chain(material, budget) end)
            require_condition(not budget.exhausted, "eye capture global " .. tostring(budget.exhausted) .. " budget exhausted")
            entry.ok = ok
            if ok then
                entry.chain, entry.effective_parameters = chain, readbacks
                local address = chain[1].address
                material_references[address] = (material_references[address] or 0) + 1
            else entry.reason = tostring(chain) end
            record.materials[#record.materials + 1] = entry
        end
        records[#records + 1] = record
    end
    for _, record in ipairs(records) do
        for _, entry in ipairs(record.materials) do
            if entry.ok then entry.player_slot_references = material_references[entry.chain[1].address] end
        end
    end
    return records
end

local function same_object(actual, expected, expected_class, label)
    local current = optional_object_record(actual, expected_class, label)
    require_condition(current.address == expected.address and current.name == expected.name
        and current.unset == expected.unset, label .. " changed during eye material probe")
end

local function verify_material_topology(player, deps, records)
    local components = head_components(player, deps)
    require_condition(#components == #records, "player mesh count changed during eye material probe")
    local remaining = {}
    for _, record in ipairs(records) do remaining[record.address] = record end
    for _, component in ipairs(components) do
        local identity = object_record(component, MESH_CLASS, "mesh after probe")
        local record = remaining[identity.address]
        require_condition(record ~= nil and record.name == identity.name, "player meshes changed during eye material probe")
        remaining[identity.address] = nil
        same_object(component:GetOwner(), object_record(player, PLAYER_CLASS, "player"), PLAYER_CLASS, "mesh owner")
        same_object(component:GetSkeletalMeshAsset(), record.asset, "/Script/Engine.SkeletalMesh", "mesh asset")
        require_condition(component:GetNumMaterials() == #record.materials, "material count changed during eye material probe")
        local names = array_entries(component:GetMaterialSlotNames(), 32, "material slots after probe")
        require_condition(#names == #record.materials, "material slots changed during eye material probe")
        for _, entry in ipairs(record.materials) do
            require_condition(names[entry.slot + 1]:ToString() == entry.slot_name, "material slot name changed during eye material probe")
            if entry.ok then
                local material = component:GetMaterial(entry.slot)
                for _, layer in ipairs(entry.chain) do
                    same_object(material, layer, "/Script/Engine.MaterialInterface", "slot material or parent")
                    if not layer.base_material then material = material.Parent end
                end
            end
        end
    end
end

function Probe.run(deps)
    local ok, result = pcall(function()
        require_condition(type(deps) == "table" and type(deps.get_player) == "function"
            and type(deps.static_find_object) == "function", "eye material probe dependencies are incomplete")
        require_condition(deps.game_thread == true, "eye material probe requires the game thread")
        require_condition(type(deps.identity) == "table" and deps.identity.build_id == BUILD_ID
            and deps.identity.executable_sha256 == EXECUTABLE_SHA256, "eye discovery build attestation mismatch")
        local player = deps.get_player()
        local player_record = object_record(player, PLAYER_CLASS, "player")
        local world_record = object_record(player:GetWorld(), "/Script/Engine.World", "world")
        local form = number(player.Form, "player form")
        require_condition(form == 0 or form == 1, "player form is unsupported")
        local wolf_form = player:IsInWolfForm()
        require_condition(type(wolf_form) == "boolean", "wolf-form readback is unavailable")
        local snapshot = { ok = true, schema = 1, scope = "eye-head-material-discovery", mutation_authorized = false, gameplay_verified = false,
            player = player_record, world = world_record, form = form, form_name = form == 0 and "Human" or "Vampire",
            is_wolf_form = wolf_form,
            head_mesh = optional_object_record(player.HeadMesh, MESH_CLASS, "player head mesh"),
            limitation = "Observed scalar/vector/texture overrides and getter readbacks only; base defaults, eye identity, color semantics, and exclusive material ownership are not established." }
        snapshot.materials = materials(player, deps)
        local current_player = deps.get_player()
        object_record(current_player, PLAYER_CLASS, "player after probe")
        verify_material_topology(current_player, deps, snapshot.materials)
        current_player = deps.get_player()
        require_condition(object_record(current_player, PLAYER_CLASS, "player after probe").address == player_record.address
            and object_record(current_player:GetWorld(), "/Script/Engine.World", "world after probe").address == world_record.address
            and current_player.Form == form and current_player:IsInWolfForm() == wolf_form,
            "player, world, or form changed during eye material probe")
        same_object(current_player.HeadMesh, snapshot.head_mesh, MESH_CLASS, "player head mesh")
        if not snapshot.head_mesh.unset then
            snapshot.head_mesh.observed_in_player_meshes = false
            for _, mesh in ipairs(snapshot.materials) do
                if mesh.address == snapshot.head_mesh.address then snapshot.head_mesh.observed_in_player_meshes = true end
            end
        end
        return snapshot
    end)
    if ok then return result end
    return { ok = false, mutation_authorized = false, gameplay_verified = false, reason = tostring(result) }
end

function Probe.format_lines(result)
    local lines = {}
    local function visit(prefix, entry, depth)
        require_condition(depth <= 16 and #lines < 200000, "eye report exceeds its bound")
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
    visit("eye_head_materials", result, 0)
    return table.concat(lines, "\n")
end

return Probe
