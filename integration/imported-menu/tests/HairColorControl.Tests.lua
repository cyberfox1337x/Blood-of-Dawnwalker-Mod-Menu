local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("hair_color_control_tests")
-- usage: lua HairColorControl.Tests.lua <path to Scripts/HairColorControl.lua>
local modulePath = assert(arg[1], "Pass the HairColorControl.lua path")

local nextAddress = 100
local function uobject(fullName, classes, fields)
    nextAddress = nextAddress + 1
    local object = { fullName = fullName, classes = classes, address = nextAddress, validity = true }
    for key, value in pairs(fields or {}) do object[key] = value end
    function object:IsValid() return self.validity end
    function object:IsA(class) return self.classes[class] == true end
    function object:GetAddress() return self.address end
    function object:GetFullName() return self.fullName end
    return object
end
local MIC, MID, MATERIAL, BASE = "/Script/Engine.MaterialInstanceConstant", "/Script/Engine.MaterialInstanceDynamic", "/Script/Engine.MaterialInterface", "/Script/Engine.Material"
local function materialObject(fullName, classes, parent)
    local material = uobject(fullName, classes, { Parent = parent, scalars = {}, vectors = {} })
    function material:K2_GetScalarParameterValue(name) local key = name:ToString(); return self.scalars[key] or (self.Parent and self.Parent:K2_GetScalarParameterValue(name)) or 0 end
    function material:K2_GetVectorParameterValue(name) local key = name:ToString(); return self.vectors[key] or (self.Parent and self.Parent:K2_GetVectorParameterValue(name)) or { R = 0, G = 0, B = 0, A = 1 } end
    function material:SetScalarParameterValue(name, value) self.scalars[name:ToString()] = value end
    function material:SetVectorParameterValue(name, value) self.vectors[name:ToString()] = { R = value.R, G = value.G, B = value.B, A = value.A } end
    return material
end
local hairBase = materialObject("Material /Game/_Dawnwalker/Shaders/Characters/Hair/M_Hair_v02.M_Hair_v02", { [BASE] = true, [MATERIAL] = true })
local facialBase = materialObject("Material /Game/_Dawnwalker/Shaders/Characters/Hair/M_Hair_v01.M_Hair_v01", { [BASE] = true, [MATERIAL] = true })
local function instance(name, base)
    local material = materialObject("MaterialInstanceConstant /Game/x/" .. name .. "." .. name, { [MIC] = true, [MATERIAL] = true }, base)
    material.scalars["BC Melanin"] = 0.8
    return material
end
local function component(materials)
    local comp = uobject("SkeletalMeshComponent hair", { ["/Script/Engine.SkeletalMeshComponent"] = true }, { slots = materials, created = {} })
    function comp:GetNumMaterials() return #self.slots end
    function comp:GetMaterial(slot) return self.slots[slot + 1] end
    function comp:SetMaterial(slot, material) self.slots[slot + 1] = material end
    function comp:CreateDynamicMaterialInstance(slot, parent, name)
        local mid = materialObject("MaterialInstanceDynamic " .. name:ToString(), { [MID] = true, [MATERIAL] = true }, parent)
        self.slots[slot + 1] = mid; self.created[#self.created + 1] = mid
        return mid
    end
    return comp
end
local hairMic, beardMic, browMic = instance("MI_HMFACE_Coen_Haircuts_A_S0_v2", hairBase), instance("MI_HMA_Coen_FacialHair", facialBase), instance("MI_Brows", hairBase)
local player = uobject("DawnwalkerPlayerCharacter P", { ["/Script/Dawnwalker.DawnwalkerPlayerCharacter"] = true }, {
    HairMesh = component({ hairMic }), BeardMeshComponent = component({ beardMic }), EyebrowMeshComponent = component({ browMic }) })

local queue, values, section = {}, {}, nil
local menu = {
    Register = function(definition) section = definition end,
    Set = function(_, id, value) values[id] = value end,
    SetLabel = function(_, id, value) values[id] = value end,
}
local skeletalClass = uobject("Class /Script/Engine.MeshComponent", {})
function player:K2_GetComponentsByClass(class)
    assert(class == skeletalClass)
    return { self.HairMesh, self.BeardMeshComponent, self.EyebrowMeshComponent, self.dynamicHair }
end
local environment = setmetatable({
    StaticFindObject = function(path) return path == "/Script/Engine.MeshComponent" and skeletalClass or nil end,
    FName = function(text) return { ToString = function() return text end } end,
    ExecuteInGameThread = function(callback) queue[#queue + 1] = callback end,
}, { __index = _G })
local module = assert(loadfile(modulePath, "t", environment))()
module.Init(menu, { GetPlayer = function() return player end })
local function request(id, value)
    for _, item in ipairs(section.items) do if item.id == id then return (item.onChange or item.onClick)(value) end end
    error("unknown control " .. tostring(id))
end
local function flush() assert(#queue == 1, "expected exactly one queued callback, got " .. #queue); local callback = table.remove(queue, 1); return pcall(callback) end

-- Observation reads every hair component and names its shader family.
request("observe"); assert(flush())
assert(values.observation:find("hair slot0: MI_HMFACE_Coen_Haircuts_A_S0_v2 [haircut]", 1, true), values.observation)
assert(values.observation:find("beard slot0: MI_HMA_Coen_FacialHair [facial]", 1, true) and values.observation:find("eyebrows slot0: MI_Brows [haircut]", 1, true), values.observation)
assert(values.observation:find("BC Melanin=0.800", 1, true), "observation must report the shared material's current values")
print("PASS observation reports hair, beard and eyebrow materials with their shader families")

-- A hair colour binds private instances and writes the natural mapping to haircut
-- materials only; the shared materials stay untouched.
request("color", "#8A3B1E"); assert(flush())
assert(values.color == "#8a3b1e" and values.owned == true, tostring(values.status))
assert(values.status:find("Applied in game: hair #8A3B1E as natural melanin 0.74, redness 0.75, grey 0.00", 1, true), values.status)
assert(#player.HairMesh.created == 1 and player.HairMesh:GetMaterial(0) == player.HairMesh.created[1], "hair slot must wear the private instance")
local hairMid = player.HairMesh.created[1]
assert(math.abs(hairMid.scalars["BC Melanin"] - 0.74) < 0.01 and math.abs(hairMid.scalars["BC Redness"] - 0.75) < 0.01 and hairMid.scalars["BC Gray Hair Amount"] == 0, "natural mapping written to the haircut")
assert(hairMid.vectors["BC DyeColor(white means off)"] == nil, "the dead dye parameter is not written")
local beardMid = player.BeardMeshComponent.created[1]
assert(beardMid.vectors.RootColor == nil, "a hair colour leaves the eyebrows alone")
assert(hairMic.scalars["BC Melanin"] == 0.8 and next(hairMic.vectors) == nil, "shared material must be untouched")
print("PASS hair colour maps to the natural melanin model on private haircut instances only")

-- Eyebrows take any RGB directly, on the facial-hair family only.
request("brows", "#00FF00"); assert(flush())
assert(values.brows == "#00ff00" and values.browStatus:find("Eyebrows in game: #00FF00", 1, true), tostring(values.browStatus))
assert(beardMid.vectors.RootColor.G == 1 and beardMid.vectors.TipColor.G == 1 and beardMid.scalars["BC Melanin"] == nil, "eyebrows take root/tip colour only")
assert(hairMid.vectors.RootColor == nil, "an eyebrow colour leaves the haircut alone")
print("PASS eyebrow colour writes root/tip colour on facial-hair instances only")

-- White takes the grey-hair path and re-applies onto the same instances.
request("color", "#FFFFFF"); assert(flush())
assert(#player.HairMesh.created == 1, "re-apply must reuse the private instance")
assert(hairMid.scalars["BC Gray Hair Amount"] == 1 and hairMid.scalars["BC Melanin"] < 0.1 and values.status:find("grey 1.00", 1, true), values.status)
print("PASS white maps to the grey-hair path and re-applies onto the same instances")

-- Tuning writes reviewed names only, per component, and reports what it wrote.
request("tune", "BC Melanin=0.3; RootColor=#00ff00"); assert(flush())
assert(hairMid.scalars["BC Melanin"] == 0.3 and beardMid.vectors.RootColor.G == 1, values.tuning)
assert(values.tuning:find("hair: BC Melanin=0.30", 1, true) or values.tuning:find("BC Melanin=0.30", 1, true), values.tuning)
assert(not pcall(request, "tune", "Nonsense=1"), "unreviewed names are refused before anything is queued")
print("PASS tuning is limited to reviewed names and reports per component")

-- Restore rebinds the originals; a foreign material on a slot is refused, never overwritten.
request("restore"); assert(flush())
assert(player.HairMesh:GetMaterial(0) == hairMic and player.BeardMeshComponent:GetMaterial(0) == beardMic and values.owned == false and values.color == "" and values.brows == "")
request("color", "#123456"); assert(flush())
local foreign = materialObject("MaterialInstanceConstant /Game/x/Foreign.Foreign", { [MIC] = true, [MATERIAL] = true }, hairBase)
player.HairMesh:SetMaterial(0, foreign)
request("restore"); local ok = flush()
assert(not ok and values.status:find("Refusing restoration over a foreign material", 1, true), values.status)
assert(player.HairMesh:GetMaterial(0) == foreign, "a foreign material must never be replaced")
print("PASS restore rebinds originals and refuses to overwrite a foreign material")

-- Session reset drops the retained pawn state and clears the published colour.
module.ResetSession()
assert(values.color == "" and values.owned == false and not module.IsActive())
print("PASS session reset clears the hair state")

-- Hair meshes attached dynamically (named fields empty) are found by enumerating the
-- player's skeletal mesh components and recognising the shader family.
do
    local dynamic = component({ instance("MI_DynamicHair", hairBase) })
    dynamic.fullName = "SkeletalMeshComponent DynHair"; function dynamic:GetFName() return { ToString = function() return "DynHair" end } end
    player.HairMesh, player.BeardMeshComponent, player.EyebrowMeshComponent = nil, nil, nil
    player.dynamicHair = dynamic
    for _, comp in ipairs({ dynamic }) do function comp:GetFName() return { ToString = function() return "DynHair" end } end end
    request("observe"); assert(flush())
    assert(values.observation:find("DynHair slot0: MI_DynamicHair [haircut]", 1, true), values.observation)
    request("color", "#00ffff"); assert(flush())
    assert(#dynamic.created == 1 and dynamic.created[1].scalars["BC Melanin"] ~= nil, values.status)
    request("restore"); assert(flush())
    assert(dynamic:GetMaterial(0) == dynamic.slots[1] and dynamic.slots[1] ~= dynamic.created[1])
    print("PASS dynamically attached hair meshes are discovered by shader family")
end
