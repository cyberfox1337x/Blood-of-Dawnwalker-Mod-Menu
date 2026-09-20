local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("speed_descriptor_readback")
local M = {}
local names = { MaxSpeedModifier = true, WalkSpeed = true, RunSpeed = true, SprintSpeed = true }
local candidates = {
    { "/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_SpedBoost_Lvl3", "GE_WolfBoost_SpedBoost_Lvl3_C" },
    { "/Game/_Dawnwalker/Combat/Focus/Vampire/WolfBoost/GE_WolfBoost_SpedBoost_Lvl4", "GE_WolfBoost_SpedBoost_Lvl4_C" },
    { "/Game/_Dawnwalker/Player/GE_PlayerAttributes", "GE_PlayerAttributes_C" },
}
local function valid(object) return object ~= nil and object:IsValid() end
local function text(value)
    if type(value) ~= "string" then value = value:ToString() end
    assert(type(value) == "string" and #value <= 512, "Invalid descriptor text")
    return value:gsub("[\r\n;]", " ")
end
local function modifiers(container)
    local values = {}
    local function add(element)
        assert(#values < 16, "Modifier inspection limit exceeded")
        local ok, unwrapped = pcall(function() return element:get() end)
        values[#values + 1] = ok and unwrapped or element
        assert(values[#values] ~= nil, "Missing modifier")
    end
    local available, foreach = pcall(function() return container.ForEach end)
    if available and type(foreach) == "function" then
        container:ForEach(function(_, element) add(element); return false end)
    else
        assert(type(#container) == "number" and #container <= 16, "Invalid modifier container")
        for index = 1, #container do add(container[index]) end
    end
    return values
end

-- One explicit scan; FindObjects bounds returned objects before Lua inspection.
-- Nil required/banned flags avoid relying on contradictory old flag docs; CDO
-- identity is checked against each exact class below. No effect is loaded/applied.
function M.Read(deps)
    assert(type(deps.findObjects) == "function" and type(deps.findObject) == "function", "Bounded object discovery unavailable")
    local owner = deps.findObject("/Script/DogwoodStats.PlayerMovementAttributeSet")
    assert(valid(owner), "Movement attribute class unavailable")
    local ownerAddress = owner:GetAddress()
    local objects, candidateMissing, candidateInvalid = {}, 0, 0
    for _, candidate in ipairs(candidates) do
        local ok, object = pcall(function()
            local class = deps.findObject(candidate[1] .. "." .. candidate[2])
            local cdo = deps.findObject(candidate[1] .. ".Default__" .. candidate[2])
            if not valid(class) or not valid(cdo) then return nil end
            assert(class:GetCDO():GetAddress() == cdo:GetAddress()
                and cdo:GetClass():GetAddress() == class:GetAddress(), "Candidate class/CDO mismatch")
            return cdo
        end)
        if not ok then candidateInvalid = candidateInvalid + 1
        elseif object then objects[#objects + 1] = object
        else candidateMissing = candidateMissing + 1 end
    end
    local fallback = #objects == 0
    if fallback then objects = deps.findObjects(512, "GameplayEffect", nil, nil, nil, false) end
    assert(type(objects) == "table" and #objects <= 512, "Unexpected bounded search result")
    local rows, skipped, matches, scanned = {}, 0, 0, 0
    for index = 1, #objects do
        scanned = scanned + 1
        local object = objects[index]
        local ok, findings = pcall(function()
            if not valid(object) or not object:IsA("/Script/GameplayAbilities.GameplayEffect") then return {} end
            local class, outer = object:GetClass(), object:GetOuter()
            assert(valid(class) and valid(outer), "Effect identity unavailable")
            local address, outerAddress = object:GetAddress(), outer:GetAddress()
            if class:GetCDO():GetAddress() ~= address then return {} end
            local entries, result = modifiers(object.Modifiers), {}
            for _, entry in ipairs(entries) do
                local descriptor = entry.Attribute
                local name = text(descriptor.AttributeName)
                if names[name] and valid(descriptor.AttributeOwner)
                    and descriptor.AttributeOwner:GetAddress() == ownerAddress then
                    local descriptorAddress = descriptor:GetStructAddress()
                    assert(type(descriptorAddress) == "number" and descriptorAddress > 0, "Invalid descriptor identity")
                    result[#result + 1] = "attribute=" .. name .. ";effect=" .. text(object:GetFullName())
                        .. ";class=" .. text(class:GetFullName()) .. ";modifiers=" .. #entries
                        .. ";descriptor=" .. tostring(descriptorAddress)
                end
            end
            assert(valid(object) and object:GetAddress() == address and object:GetOuter():GetAddress() == outerAddress
                and class:GetCDO():GetAddress() == address, "Effect changed during scan")
            return result
        end)
        if not ok then skipped = skipped + 1
        else
            for _, line in ipairs(findings) do
                matches = matches + 1
                if #rows < 64 then rows[#rows + 1] = line end
            end
        end
    end
    assert(valid(owner) and owner:GetAddress() == ownerAddress, "Attribute owner changed during scan")
    table.insert(rows, 1, "read_only=true;scanned=" .. scanned .. ";matches=" .. matches .. ";skipped=" .. skipped
        .. ";candidate_missing=" .. candidateMissing .. ";candidate_invalid=" .. candidateInvalid .. ";fallback=" .. tostring(fallback)
        .. ";search_capped=" .. tostring(fallback and #objects == 512) .. ";output_capped=" .. tostring(matches > 64))
    return table.concat(rows, "\n")
end
function M.Init(menu)
    menu.Register({ id = "DWSpeedReadback", title = "Speed descriptor diagnostics", tab = "Player", items = {
        { type = "button", id = "refresh", label = "Read loaded speed descriptors", onClick = function()
            ExecuteInGameThread(function()
                menu.SetLabel("DWSpeedReadback", "status", M.Read({findObjects=FindObjects,findObject=StaticFindObject}))
            end)
        end },
        { type = "label", id = "status", label = "Read-only speed descriptor discovery has not run." },
    } })
end
return M
