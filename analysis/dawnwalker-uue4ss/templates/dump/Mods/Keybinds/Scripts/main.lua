local cyberfox1337x = {}
cyberfox1337x["function"] = function(module_name)
    return module_name
end
cyberfox1337x["function"]("dawnwalker_read_only_dump_keybinds")

-- Only reflection/metadata dumpers are exposed. Asset and actor dumpers stay unbound.
local safe_dump_keybinds = {
    ObjectDumper = { Key = Key.J, ModifierKeys = { ModifierKey.CONTROL } },
    CXXHeaderGenerator = { Key = Key.H, ModifierKeys = { ModifierKey.CONTROL } },
    UHTCompatibleHeaderGenerator = { Key = Key.NUM_NINE, ModifierKeys = { ModifierKey.CONTROL } },
    DumpUSMAP = { Key = Key.NUM_SIX, ModifierKeys = { ModifierKey.CONTROL } },
    DumpJMAP = { Key = Key.NUM_FIVE, ModifierKeys = { ModifierKey.CONTROL } },
}

-- Key-down auto-repeat can otherwise start the same multi-minute dumper twice.
-- Discovery operations are intentionally one-shot per game process.
local started_dumps = {}

local function register_safe_dump(name, callback)
    local binding = safe_dump_keybinds[name]
    if binding and not IsKeyBindRegistered(binding.Key, binding.ModifierKeys) then
        RegisterKeyBindAsync(binding.Key, binding.ModifierKeys, function()
            if started_dumps[name] then
                return
            end
            started_dumps[name] = true
            callback()
        end)
    end
end

register_safe_dump("ObjectDumper", function() DumpAllObjects() end)
register_safe_dump("CXXHeaderGenerator", function() GenerateSDK() end)
register_safe_dump("UHTCompatibleHeaderGenerator", function() GenerateUHTCompatibleHeaders() end)
register_safe_dump("DumpUSMAP", function() DumpUSMAP() end)
register_safe_dump("DumpJMAP", function() DumpJMAP() end)
