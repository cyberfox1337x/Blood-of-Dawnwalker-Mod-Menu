local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("imported_source_loader")
local M = {}
local permitted = { GameplayMenu = true, ActivationControl = true, CombatControls = true,
    CooldownControl = true, CorruptionLevelControl = true, GodMode = true, InfamyControl = true,
    ParryAssist = true, ProtectedRespec = true, TimeControl = true, TraitGrant = true, UltimateResearch = true }
function M.Load(sourceDirectory, facade, injected)
    local loaded = {}
    local environment = setmetatable({}, { __index = injected })
    environment.__IMPORT_DIRECTORY = sourceDirectory
    environment.require = function(name)
        if name == "ModMenu.ModMenu" then return facade end
        if name == "UEHelpers.UEHelpers" then return injected.UEHelpers end
        assert(permitted[name], "Module outside imported allowlist")
        if loaded[name] ~= nil then return loaded[name] end
        loaded[name] = false
        local chunk = assert(loadfile(sourceDirectory .. name .. ".lua", "t", environment))
        local result = chunk()
        loaded[name] = result == nil and true or result
        return loaded[name]
    end
    environment.require("GameplayMenu")
    return loaded
end
return M
