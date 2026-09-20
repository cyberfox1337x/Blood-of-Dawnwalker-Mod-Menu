local cyberfox1337x = { signature = function(name) return name end }
cyberfox1337x.signature("imported_GameplayMenu")
-- Dawnwalker Mod Menu for The Blood of Dawnwalker
-- v3.2 release; gameplay baseline v3 / UE 5.5.4
-- Originally validated on Steam 25129649 (CL257186). The game has since updated to
-- Steam 25191761 (CL258042); controls resolve by reflected name, so they survive a
-- patch, but each one's gameplay acceptance is re-verified separately.

local ModMenu = require("ModMenu.ModMenu")
local UEHelpers = require("UEHelpers.UEHelpers")

local PLAYER, SKILLS, XP, MUTATION = "DWPlayer", "DWSkills", "DWXP", "DWMutation"
local CURRENCY, MATERIALS, MANUALS, KEYS, ITEMS = "DWCurrency", "DWMaterials", "DWManuals", "DWKeys", "DWItems"

local sourcePath = __IMPORT_DIRECTORY .. "main.lua"
local configPath = sourcePath:gsub("[Mm][Aa][Ii][Nn]%.lua$", "settings.ini")
local config = {
    skillAmount=1, mutationAmount=1, mutationLevel=1, coinAmount=100, materialQuantity=1,
    itemQuantity=1, itemLevel=1, itemCategory="All",
}
local itemCache, materialOptions, manualOptions, keyOptions = {}, {}, {}, {}
local itemsScanned, selectedMaterial, selectedManual, selectedKey, selectedItem, keyLocked = false, false, false, false, false, false
local bulkGiveActive, bulkGiveIssued, bulkGiveInterrupted = false, false, false

local function log(s) print(string.format("[DawnwalkerModMenu] %s\n", s)) end
local function valid(o) return o and o:IsValid() end
local function clamp(v, low, high)
    return math.max(low, math.min(high, math.floor(tonumber(v) or low)))
end

local function loadConfig()
    local f = io.open(configPath, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k and config[k] ~= nil then
            config[k] = type(config[k]) == "number" and (tonumber(v) or config[k]) or v
        end
    end
    f:close()
end

local function saveConfig()
    local f = io.open(configPath, "w")
    if not f then log("Could not save settings") return end
    local keys = {"skillAmount","mutationAmount","mutationLevel","coinAmount","materialQuantity","itemQuantity",
        "itemLevel","itemCategory"}
    for _, k in ipairs(keys) do f:write(string.format("%s=%s\n", k, tostring(config[k]))) end
    f:close()
end
loadConfig()

local function player(quiet)
    local o = UEHelpers.GetPlayer()
    local cls = StaticFindObject("/Script/Dawnwalker.DawnwalkerPlayerCharacter")
    if not valid(o) or (valid(cls) and not o:IsA(cls)) then
        if not quiet then log("No controlled Dawnwalker character; load a save first") end
        return nil
    end
    local world=o:GetWorld()
    if not valid(world) then if not quiet then log("Player has no active world") end return nil end
    return o
end
local function charDev(quiet)
    local o = FindFirstOf("CharacterDevelopmentSubsystem")
    if not valid(o) then if not quiet then log("Load a save first") end return nil end
    return o
end
local function inventory(quiet)
    local p = player(true)
    if p and valid(p.InventoryComponent) then return p.InventoryComponent end
    local s = FindFirstOf("InventorySubsystem")
    local o = valid(s) and s:GetPlayerInventoryComponent() or nil
    if not valid(o) then if not quiet then log("Player inventory unavailable") end return nil end
    return o
end
local function beginHotkey()
    if keyLocked then return false end
    keyLocked = true
    ExecuteWithDelay(200, function() keyLocked = false end)
    return true
end

local function refreshPlayer()
    ExecuteInGameThread(function()
        local p = player(true)
        if not p or not valid(p.CombatComponent) then
            ModMenu.SetLabel(PLAYER, "status", "Load a save to view player status")
            ModMenu.Set(PLAYER,"health",{percent=0,text="—"})
            ModMenu.Set(PLAYER,"staminaMeter",{percent=0,text="—"})
            ModMenu.Set(PLAYER,"activationMeter",{percent=0,text="—"})
            ModMenu.SetLabel(PLAYER,"level","✿  Level    —")
            return
        end
        local c = p.CombatComponent
        local hp,sp=c:GetHealthPercentage(),c:GetStaminaPercentage()
        ModMenu.SetLabel(PLAYER,"status","Live player status")
        ModMenu.Set(PLAYER,"health",{percent=hp,text=string.format("%.0f%%",hp*100)})
        ModMenu.Set(PLAYER,"staminaMeter",{percent=sp,text=string.format("%.0f%%",sp*100)})
        local a=p.CharacterAttributeSet
        if valid(a) then
            local current=tonumber(a.ChargedActionSlots.CurrentValue) or 0
            local maximum=tonumber(a.UnlockedActionSlots.CurrentValue) or 0
            ModMenu.Set(PLAYER,"activationMeter",{percent=maximum>0 and current/maximum or 0,
                text=string.format("%.0f / %.0f",current,maximum)})
        end
        local dev=charDev(true)
        local ok,level=pcall(function() return dev and dev:GetCurrentLevel() end)
        ModMenu.SetLabel(PLAYER,"level",ok and level and string.format("✿  Level    %d",math.floor(tonumber(level) or 0))
            or "✿  Level    —")
    end)
end

local function restore(kind)
    ExecuteInGameThread(function()
        local p = player(false)
        if not p or not valid(p.CombatComponent) then return end
        local c = p.CombatComponent
        if kind == "health" then c:SetHealthPercent(1.0)
        elseif kind == "stamina" then c:SetStaminaPercent(1.0)
        elseif kind == "focus" then
            ModMenu.SetLabel(PLAYER, "status", "Activation-charge refill is disabled for crash safety")
            log("Activation-charge refill blocked for crash safety")
            return
        elseif kind == "wounds" and valid(p.WoundContainerComponent) then p.WoundContainerComponent:HealAllWounds() end
        log("Restored " .. kind)
        refreshPlayer()
    end)
end

local function refreshSkills()
    ExecuteInGameThread(function()
        local s = charDev(true)
        ModMenu.SetLabel(SKILLS, "status", s and string.format("Available skill points: %d", s:GetTraitPointAmount())
            or "Available skill points: load a save first")
    end)
end
local function changeSkills(delta, hotkey)
    if hotkey and not beginHotkey() then return end
    ExecuteInGameThread(function()
        local s = charDev(false); if not s then return end
        local before, n = s:GetTraitPointAmount(), math.abs(math.floor(delta))
        if delta > 0 then s:ReceiveTraitPoints(n)
        elseif delta < 0 then n=math.min(n,before); if n>0 then s:SpendTraitPoints(n) end end
        local after=s:GetTraitPointAmount()
        ModMenu.SetLabel(SKILLS,"status",string.format("Available skill points: %d",after))
        log(string.format("Skill points: %d -> %d",before,after))
    end)
end
local function clearSkills()
    ExecuteInGameThread(function()
        local s=charDev(false); if not s then return end
        local n=s:GetTraitPointAmount(); if n>0 then s:SpendTraitPoints(n) end; refreshSkills()
    end)
end

local xpValues = { ["Very small"]=1, Small=2, Medium=3, Large=4, ["Very large"]=5 }
local function awardXP()
    local name=ModMenu.Get(XP,"reward") or "Small"
    ExecuteInGameThread(function()
        local s=charDev(false); if not s then return end
        local amount=s:AddQuestXP(xpValues[name] or 2)
        ModMenu.SetLabel(XP,"status",string.format("Last award: %s (%s XP)",name,tostring(amount)))
        log(string.format("Awarded %s XP (%s)",name,tostring(amount)))
    end)
end
local function refreshMutation()
    ExecuteInGameThread(function()
        local s=charDev(true)
        ModMenu.SetLabel(MUTATION,"status",s and string.format("Corruption level: %d    Raw charge value: %.2f",
            s:GetCurrentMutationLevel(),s:GetCurrentMutationCharges()) or "Corruption: load a save first")
    end)
end
local corruptionControl
local function changeMutation(delta)
    -- Record the pre-change Corruption once per session so the panel's reset covers
    -- raw-charge changes too, not just the exact-level setter.
    if corruptionControl and corruptionControl.NoteBaseline then
        local noted, failure = pcall(corruptionControl.NoteBaseline)
        if not noted then log("Corruption baseline capture failed: " .. tostring(failure)) end
    end
    ExecuteInGameThread(function()
        local s=charDev(false); if not s then return end
        local beforeLevel,beforeCharges=s:GetCurrentMutationLevel(),s:GetCurrentMutationCharges()
        local n=math.abs(math.floor(delta))
        if delta<0 then n=-math.min(n,math.floor(s:GetCurrentMutationCharges())) end
        if n~=0 then s:AddMutationCharges(n) end
        local afterLevel,afterCharges=s:GetCurrentMutationLevel(),s:GetCurrentMutationCharges()
        local result=string.format("Level %d -> %d; raw charges %.2f -> %.2f",beforeLevel,afterLevel,beforeCharges,afterCharges)
        ModMenu.SetLabel(MUTATION,"lastChange",result)
        refreshMutation(); log("Corruption: "..result..string.format(" (requested change %+d)",n))
    end)
end

local function refreshCurrency()
    ExecuteInGameThread(function()
        local i=inventory(true)
        ModMenu.SetLabel(CURRENCY,"status",i and string.format("Coins: %d",i:GetCurrencyQuantity(0)) or "Coins: load a save first")
    end)
end
local function changeCoins(delta)
    ExecuteInGameThread(function()
        local i=inventory(false); if not i then return end
        local before=i:GetCurrencyQuantity(0); local n=math.abs(math.floor(delta))
        if delta<0 then n=-math.min(n,before) end
        if n~=0 then i:AddCurrency(0,n) end
        local after=i:GetCurrencyQuantity(0)
        ModMenu.SetLabel(CURRENCY,"status",string.format("Coins: %d",after))
        log(string.format("Coins: %d -> %d",before,after))
    end)
end

local categoryFor = {
    ItemWeaponDataAsset="Weapons", ItemClothingDataAsset="Clothing",
    ItemConsumableDataAsset="Consumables", ItemIngredientDataAsset="Materials",
    ItemRecipeDataAsset="Recipes", ItemJunkDataAsset="Junk",
}
local function humanize(name)
    return (name:gsub("^ITM_",""):gsub("_"," "):gsub("(%l)(%u)","%1 %2"))
end
local function looksLikeKey(className,internal,display,path)
    local classLower=className:lower()
    local internalLower=internal:lower()
    local displayLower=display:lower()
    local pathLower=(path or ""):lower()
    return classLower:find("key",1,true)~=nil
        or displayLower:find("%f[%a]key%f[%A]")~=nil
        or internalLower:find("_key",1,true)~=nil
        or internalLower:find("key_",1,true)~=nil
        or pathLower:find("/keys/",1,true)~=nil
end
local function itemOptions(category)
    local out={}
    for _,v in ipairs(itemCache) do
        if category=="All" or v.category==category then table.insert(out,{label=v.label,value=v.path}) end
    end
    if #out==0 then out={{label="No matching loaded items",value=false}} end
    return out
end
local function scanItems()
    if itemsScanned then return end
    itemsScanned=true; itemCache={}; materialOptions={}; manualOptions={}; keyOptions={}
    local base=StaticFindObject("/Script/DogwoodInventory.ItemBaseDataAsset")
    if not valid(base) then log("Item data class unavailable") return end
    ForEachUObject(function(o)
        if not o:IsA(base) or o:IsAnyClass() then return end
        local className=o:GetClass():GetFName():ToString()
        local category=categoryFor[className]
        local isManual=className=="ItemCharDevDataAsset"
        local internal=o:GetFName():ToString(); local display=nil
        local ok,result=pcall(function() return o:GetItemName():ToString() end)
        display=(ok and result and result~="" and not result:find("<MISSING",1,true)) and result or humanize(internal)
        local path=o:GetFullName():match("^%S+%s+(.+)$")
        local isKey=looksLikeKey(className,internal,display,path)
        if not category and not isManual and not isKey then return end -- Protect other quest/readable items.
        if path then
            if isKey then
                table.insert(keyOptions,{label=string.format("%s  [%s]",display,className),value=path})
            elseif isManual then
                table.insert(manualOptions,{label=display,value=path})
            else
                table.insert(itemCache,{label=string.format("%s  [%s]",display,category),path=path,category=category})
                if category=="Materials" then table.insert(materialOptions,{label=display,value=path}) end
            end
        end
    end)
    table.sort(itemCache,function(a,b) return a.label:lower()<b.label:lower() end)
    table.sort(materialOptions,function(a,b) return a.label:lower()<b.label:lower() end)
    table.sort(manualOptions,function(a,b) return a.label:lower()<b.label:lower() end)
    table.sort(keyOptions,function(a,b) return a.label:lower()<b.label:lower() end)
    local manualCount,keyCount=#manualOptions,#keyOptions
    if #materialOptions==0 then materialOptions={{label="No loaded materials",value=false}} end
    if #manualOptions==0 then manualOptions={{label="No loaded skill manuals",value=false}} end
    if #keyOptions==0 then keyOptions={{label="No loaded key items",value=false}} end
    ModMenu.SetOptions(MATERIALS,"material",materialOptions,false)
    ModMenu.SetOptions(MANUALS,"manual",manualOptions,false)
    ModMenu.SetOptions(KEYS,"key",keyOptions,false)
    ModMenu.SetOptions(ITEMS,"item",itemOptions(config.itemCategory),false)
    ModMenu.SetLabel(MANUALS,"scanStatus",string.format("%d skill manuals indexed.",manualCount))
    ModMenu.SetLabel(KEYS,"scanStatus",string.format("%d probable key items indexed.",keyCount))
    ModMenu.SetLabel(ITEMS,"scanStatus",string.format("%d standard items indexed. Quest and ordinary readable items are protected.",#itemCache))
    log(string.format("Indexed %d standard items, %d skill manuals and %d probable keys",#itemCache,manualCount,keyCount))
end
local inventoryInspected = false
local function inspectVisibleItems()
    local p=player(true)
    if not p then return end
    local function describe(asset)
        if not valid(asset) then return end
        log("VISIBLE_ITEM "..asset:GetFullName().." name="..asset:GetItemName():ToString().." fake="..tostring(asset:GetItemProperty(32)))
    end
    describe(StaticFindObject("/Game/_Dawnwalker/Inventory/Items/ITM_Ingredient_Bases11.ITM_Ingredient_Bases11"))
    for _,entry in ipairs(FindAllOf("InventoryUIListItem") or {}) do
        if valid(entry) and not entry:GetFullName():find("Default__",1,true) then
            local ok,err=pcall(function() describe(entry:GetItemAsset(p)) end)
            if not ok then log("VISIBLE_ITEM error="..tostring(err)) end
        end
    end
    log("VISIBLE_ITEM END")
end
local function inspectInventoryAPI()
    if inventoryInspected then return end
    inventoryInspected = true
    local classPaths = {
        "/Script/DogwoodInventory.InventoryBlueprintFunctionLibrary",
        "/Script/DogwoodInventory.InventorySubsystem",
        "/Script/DogwoodInventory.InventoryComponent",
    }
    for _,path in ipairs(classPaths) do
        local cls=StaticFindObject(path)
        if valid(cls) then
            log("ITEM_API CLASS "..path)
            cls:ForEachFunction(function(fn)
                log("ITEM_API FUNC "..fn:GetFName():ToString())
                fn:ForEachProperty(function(prop)
                    log("ITEM_API PARAM "..prop:GetClass():GetFName():ToString().." "..prop:GetFName():ToString())
                end)
            end)
        end
    end
    local enumClass=StaticFindObject("/Script/CoreUObject.Enum")
    if valid(enumClass) then
        ForEachUObject(function(obj)
            if obj:IsA(enumClass) and obj:GetFullName():find("/Script/DogwoodInventory.",1,true) then
                log("ITEM_API ENUM "..obj:GetFullName())
                obj:ForEachName(function(name,value)
                    log("ITEM_API VALUE "..name:ToString().."="..tostring(value))
                end)
            end
        end)
    end
    log("ITEM_API END")
end
-- Consume the native return struct inside its hook lifetime. Normal Lua return
-- conversion drops non-reflected ItemHandle fields, yielding an empty handle.
local pendingHandle=nil
local handleHookReady=false
local hookOK,hookError=pcall(function()
    RegisterHook("/Script/DogwoodInventory.InventoryBlueprintFunctionLibrary:GetItemHandle",function() end,
        function(context,returned,worldArg,assetArg,levelArg)
            local request=pendingHandle
            if not request then return end
            pendingHandle=nil
            local ok,err=pcall(function()
                local h=returned:get()
                if type(h)~="userdata" then error("Native ItemHandle userdata unavailable") end
                request.callback(h)
            end)
            request.done=ok
            request.error=err
        end)
    handleHookReady=true
end)
if not hookOK then log("Native item bridge unavailable: "..tostring(hookError)) end
local function withHandle(p,asset,level,callback)
    if not handleHookReady or pendingHandle then return false,"Item bridge unavailable or busy" end
    local request={callback=callback,done=false}
    pendingHandle=request
    local ok,err=pcall(function()
        StaticFindObject("/Script/DogwoodInventory.Default__InventoryBlueprintFunctionLibrary"):GetItemHandle(p,asset,level)
    end)
    pendingHandle=nil
    if not ok then return false,tostring(err) end
    return request.done,request.error or "Native return hook did not run"
end
local function give(path,quantity,level,section,onDone)
    if not path then
        ModMenu.SetLabel(section,"actionStatus","Choose an item first")
        if onDone then onDone(false) end
        return
    end
    ExecuteInGameThread(function()
        local completed=false
        local p,i=player(false),inventory(false)
        local lib=StaticFindObject("/Script/DogwoodInventory.Default__InventoryBlueprintFunctionLibrary")
        local asset=StaticFindObject(path)
        if not p or not i or not valid(lib) or not valid(asset) then
            ModMenu.SetLabel(section,"actionStatus","Could not resolve the selected item")
            if onDone then onDone(false) end
            return
        end
        local effectiveLevel=asset:HasItemLevel() and level or 0
        local bridged,bridgeError=withHandle(p,asset,effectiveLevel,function(handle)
        if lib:EqualEqual_ItemHandleItemHandle(handle,lib:MakeInvalidItemHandle()) then
            ModMenu.SetLabel(section,"actionStatus","Blocked: game returned an invalid item handle")
            log("Give blocked: invalid item handle for "..path)
            return
        end
        local before=i:GetItemQuantity(handle,false)
        log(string.format("Give target: player=%s inventory=%s before=%d",p:GetFullName(),i:GetFullName(),before))
        if bulkGiveActive then bulkGiveIssued=true end
        local result=i:TryAddItem(handle,quantity,false)
        local after=i:GetItemQuantity(handle,false)
        local gained=after-before
        local name=asset:GetItemName():ToString()
        if name=="" or name:find("<MISSING",1,true) then name=humanize(asset:GetFName():ToString()) end
        if gained>0 then
            ModMenu.SetLabel(section,"actionStatus",string.format("Verified +%d %s (owned %d -> %d)",gained,name,before,after))
        else
            local reasons={[0]="No result",[1]="Success reported, but inventory unchanged",[2]="Failure",
                [3]="Item not found",[4]="Not enough items",[5]="Not enough space",[12]="Quantity limit reached"}
            ModMenu.SetLabel(section,"actionStatus",reasons[result] or ("Inventory result "..tostring(result)))
        end
        log(string.format("Give verified: %d x %s, level %d, result %s, owned %d -> %d",quantity,path,effectiveLevel,tostring(result),before,after))
        end)
        if not bridged then
            ModMenu.SetLabel(section,"actionStatus","Item bridge failed; see log")
            log("Item bridge error: "..tostring(bridgeError))
        else
            completed=true
        end
        if onDone then onDone(completed) end
    end)
end

-- EInventoryResult (/Script/DogwoodInventory.EInventoryResult), CL257186 capture.
-- Used to explain a refused equip instead of reporting a bare numeric code.
local INVENTORY_RESULT_REASONS = {
    [0]="No result reported",[1]="Success reported",[2]="Failure",[3]="Item not found",
    [4]="Not enough items",[5]="Not enough space",[6]="Not enough currency",
    [7]="Not enough ingredients",[8]="Item not craftable",[9]="No free equipment slot",
    [10]="Item was unequipped",[11]="Item not usable",[12]="Quantity limit reached",
    [13]="Not all items sold",[14]="Equipment changes are locked right now",
    [15]="Equipment cannot change during combat",[16]="Item not upgradeable",
}

-- Count the equipment slots the game itself considers valid for an item.
-- Returns nil when the array cannot be read, so an unreadable roster degrades to
-- "let the native call decide" rather than silently blocking a legitimate item.
local function validEquipmentSlotCount(inventoryComponent,handle)
    local ok,count=pcall(function()
        local slots=inventoryComponent:GetValidEquipmentSlotsForItem(handle)
        if slots==nil then return nil end
        if type(slots)=="table" then return #slots end
        return slots:GetArrayNum()
    end)
    if not ok then
        log("Equip slot roster unavailable, continuing on native result: "..tostring(count))
        return nil
    end
    return count
end

-- Add one of the selected item and equip it in the same native call.
-- Verified against the live inventory: quantity must rise and IsItemEquipped must
-- become true. Equipping is an ordinary player action, so no ownership is held.
local function giveAndEquip(path,level,section)
    if not path then
        ModMenu.SetLabel(section,"actionStatus","Choose an item first")
        return
    end
    ExecuteInGameThread(function()
        local p,i=player(false),inventory(false)
        local lib=StaticFindObject("/Script/DogwoodInventory.Default__InventoryBlueprintFunctionLibrary")
        local asset=StaticFindObject(path)
        if not p or not i or not valid(lib) or not valid(asset) then
            ModMenu.SetLabel(section,"actionStatus","Could not resolve the selected item")
            return
        end
        -- The game refuses equipment changes in combat (EInventoryResult 15).
        -- Refuse before mutating anything so the inventory is never left half-changed.
        local combat=FindFirstOf("CombatSubsystem")
        if valid(combat) and not combat:GetFullName():find("Default__",1,true) and combat:GetIsInCombat() then
            ModMenu.SetLabel(section,"actionStatus","Leave combat before adding and equipping an item")
            return
        end
        local effectiveLevel=asset:HasItemLevel() and level or 0
        local bridged,bridgeError=withHandle(p,asset,effectiveLevel,function(handle)
            if lib:EqualEqual_ItemHandleItemHandle(handle,lib:MakeInvalidItemHandle()) then
                ModMenu.SetLabel(section,"actionStatus","Blocked: game returned an invalid item handle")
                log("Add and equip blocked: invalid item handle for "..path)
                return
            end
            local slotCount=validEquipmentSlotCount(i,handle)
            if slotCount==0 then
                ModMenu.SetLabel(section,"actionStatus","This item has no equipment slot; use Give selected item instead")
                log("Add and equip blocked: no valid equipment slot for "..path)
                return
            end
            local loadout=i:GetActiveLoadoutIndex()
            local before=i:GetItemQuantity(handle,false)
            local equippedBefore=i:IsItemEquipped(handle,loadout)
            log(string.format("Add and equip target: player=%s inventory=%s loadout=%s before=%d equipped=%s",
                p:GetFullName(),i:GetFullName(),tostring(loadout),before,tostring(equippedBefore)))
            local result=i:TryAddAndEquipItem(handle,false)
            local after=i:GetItemQuantity(handle,false)
            local equippedAfter=i:IsItemEquipped(handle,loadout)
            local name=asset:GetItemName():ToString()
            if name=="" or name:find("<MISSING",1,true) then name=humanize(asset:GetFName():ToString()) end
            if equippedAfter and not equippedBefore then
                ModMenu.SetLabel(section,"actionStatus",string.format("Verified: %s equipped (owned %d -> %d)",name,before,after))
            elseif after>before then
                ModMenu.SetLabel(section,"actionStatus",string.format("Added %s (owned %d -> %d) but it did not equip: %s",
                    name,before,after,INVENTORY_RESULT_REASONS[result] or ("result "..tostring(result))))
            elseif equippedAfter and equippedBefore then
                ModMenu.SetLabel(section,"actionStatus",string.format("%s was already equipped; inventory unchanged",name))
            else
                ModMenu.SetLabel(section,"actionStatus",INVENTORY_RESULT_REASONS[result] or ("Inventory result "..tostring(result)))
            end
            log(string.format("Add and equip verified: %s, level %d, result %s, owned %d -> %d, equipped %s -> %s",
                path,effectiveLevel,tostring(result),before,after,tostring(equippedBefore),tostring(equippedAfter)))
        end)
        if not bridged then
            ModMenu.SetLabel(section,"actionStatus","Item bridge failed; see log")
            log("Add and equip bridge error: "..tostring(bridgeError))
        end
    end)
end

-- /Script/DogwoodSystem.EQuickslot, CL257186 capture. Max shares Bottom's value, so
-- only these four are real slots.
local QUICKSLOTS = {
    {label="Left",value=0},{label="Top",value=1},{label="Right",value=2},{label="Bottom",value=3},
}
local selectedQuickslot = 0

local function quickslotSubsystem(quiet)
    local o = FindFirstOf("InventoryQuickslotSubsystem")
    if not valid(o) or o:GetFullName():find("Default__",1,true) then
        if not quiet then log("Quickslot subsystem unavailable") end
        return nil
    end
    return o
end

-- Report what the game currently holds in a quickslot. The handle itself cannot be
-- kept beyond the native call, so only its emptiness is reported, never a stored copy.
local function readQuickslot(section)
    ExecuteInGameThread(function()
        local ok,err=pcall(function()
            local subsystem=quickslotSubsystem(false)
            assert(subsystem,"Load a save first")
            local lib=StaticFindObject("/Script/DogwoodInventory.Default__InventoryBlueprintFunctionLibrary")
            assert(valid(lib),"Inventory library unavailable")
            local current=subsystem:GetItemInSlot(selectedQuickslot)
            local empty=lib:EqualEqual_ItemHandleItemHandle(current,lib:MakeInvalidItemHandle())
            local name=QUICKSLOTS[selectedQuickslot+1] and QUICKSLOTS[selectedQuickslot+1].label or tostring(selectedQuickslot)
            ModMenu.SetLabel(section,"slotStatus",
                empty and string.format("%s quickslot is empty.",name)
                    or string.format("%s quickslot currently holds an item.",name))
        end)
        if not ok then
            ModMenu.SetLabel(section,"slotStatus","Unavailable: "..tostring(err))
            log("Quickslot read failed: "..tostring(err))
        end
    end)
end

-- Assign the item selected in the Items panel to a quickslot, then prove it by
-- reading the slot back and comparing handles.
local function assignQuickslot(path,level,section)
    if not path then
        ModMenu.SetLabel(section,"slotStatus","Choose an item in the Items panel first")
        return
    end
    ExecuteInGameThread(function()
        local p=player(false)
        local subsystem=quickslotSubsystem(false)
        local lib=StaticFindObject("/Script/DogwoodInventory.Default__InventoryBlueprintFunctionLibrary")
        local asset=StaticFindObject(path)
        local inventoryComponent=inventory(false)
        if not p or not subsystem or not valid(lib) or not valid(asset) or not inventoryComponent then
            ModMenu.SetLabel(section,"slotStatus","Could not resolve the quickslot target")
            return
        end
        local slot=selectedQuickslot
        local slotName=QUICKSLOTS[slot+1] and QUICKSLOTS[slot+1].label or tostring(slot)
        local effectiveLevel=asset:HasItemLevel() and level or 0
        local bridged,bridgeError=withHandle(p,asset,effectiveLevel,function(handle)
            if lib:EqualEqual_ItemHandleItemHandle(handle,lib:MakeInvalidItemHandle()) then
                ModMenu.SetLabel(section,"slotStatus","Blocked: game returned an invalid item handle")
                return
            end
            -- A quickslot holds something you own, so refuse rather than binding a
            -- slot to an item the player does not have. bMatchAssetOnly must be true:
            -- a handle minted by GetItemHandle carries a fresh instance identity, so
            -- an exact-handle match reports 0 even for an item already in the bag.
            local owned=inventoryComponent:GetItemQuantity(handle,true)
            if not (type(owned)=="number" and owned>0) then
                ModMenu.SetLabel(section,"slotStatus","You do not own that item. Give it first, then assign it.")
                log("Quickslot assign blocked: not owned, "..path)
                return
            end
            local name=asset:GetItemName():ToString()
            if name=="" or name:find("<MISSING",1,true) then name=humanize(asset:GetFName():ToString()) end
            -- The game's own gate. It knows which item kinds a quickslot accepts and
            -- what the active preset allows, so ask it rather than guessing here.
            local allowed=subsystem:CanSetItemInQuickslot(handle,0)
            if allowed==false then
                ModMenu.SetLabel(section,"slotStatus",
                    string.format("The game will not accept %s in a quickslot.",name))
                log("Quickslot assign refused by CanSetItemInQuickslot: "..path)
                return
            end
            -- PresetId 0 is the default preset; no other preset is established.
            subsystem:SetItemInSlot(slot,handle,0)
            -- Verify by asking the game which slot now holds this item. Result is a
            -- plain EQuickslot enum out parameter, which crosses the Lua bridge
            -- safely; an FItemHandle return does not survive the conversion intact.
            local lookup={}
            local placed=subsystem:GetItemQuickslot(handle,lookup,0)
            -- The enum arrives as its numeric value; tonumber also covers a runtime
            -- that hands the byte back as a string.
            local reported=tonumber(lookup.Result)
            local matched=placed==true and reported==slot
            if matched then
                ModMenu.SetLabel(section,"slotStatus",string.format("Verified: %s assigned to the %s quickslot.",name,slotName))
            else
                ModMenu.SetLabel(section,"slotStatus",string.format("The game did not put %s in the %s quickslot.",name,slotName))
            end
            log(string.format("Quickslot assign: slot=%s item=%s owned=%s placed=%s reported=%s matched=%s",
                slotName,path,tostring(owned),tostring(placed),tostring(reported),tostring(matched)))
        end)
        if not bridged then
            ModMenu.SetLabel(section,"slotStatus","Item bridge failed; see log")
            log("Quickslot bridge error: "..tostring(bridgeError))
        end
    end)
end

local function giveAllEquipment()
    if bulkGiveInterrupted then
        ModMenu.SetLabel(ITEMS,"actionStatus","STOP: bulk equipment was interrupted after an item request. Reload the protected save and restart.")
        return
    end
    if bulkGiveActive then
        ModMenu.SetLabel(ITEMS,"actionStatus","Give All Equipment is already running")
        return
    end
    if not itemsScanned then scanItems() end
    local requestedLevel=clamp(ModMenu.Get(ITEMS,"level"),1,255)
    local queue={}
    for _,v in ipairs(itemCache) do
        if v.category=="Weapons" or v.category=="Clothing" then
            table.insert(queue,{path=v.path,label=v.label,category=v.category})
        end
    end
    if #queue==0 then
        ModMenu.SetLabel(ITEMS,"actionStatus","No Weapons or Clothing are currently indexed")
        return
    end
    local index,total=1,#queue
    bulkGiveActive=true;bulkGiveIssued=false
    log(string.format("Give All Equipment started: %d Weapons/Clothing items; level %d",total,requestedLevel))
    ModMenu.SetLabel(ITEMS,"actionStatus",string.format("Giving Weapons + Clothing: 0 / %d",total))
    local step
    step=function()
        if index>total then
            bulkGiveActive=false
            ModMenu.SetLabel(ITEMS,"actionStatus",string.format("Give All Equipment finished: attempted %d items",total))
            log(string.format("Give All Equipment finished: attempted %d items",total))
            return
        end
        local current=index
        local entry=queue[current]
        -- Log before crossing the native bridge so a crash identifies the exact
        -- asset being attempted rather than only the previously completed one.
        log(string.format("Give All Equipment attempt %d / %d [%s]: %s",current,total,entry.category,entry.path))
        give(entry.path,1,requestedLevel,ITEMS,function()
            if current==1 or current%10==0 or current==total then
                ModMenu.SetLabel(ITEMS,"actionStatus",string.format("Giving Weapons + Clothing: %d / %d",current,total))
            end
            index=current+1
            -- The 20 ms gap starts only after the current native inventory
            -- mutation has completed, preventing an unbounded game-thread queue.
            ExecuteWithDelay(20,step)
        end)
    end
    step()
end

ModMenu.Init({})
require("InfamyControl").Register(ModMenu)
require("TimeControl").Register(ModMenu)
require("UltimateResearch").Init(ModMenu,player,log)
require("TraitGrant").Init(ModMenu,player,log)

ModMenu.Register({id=PLAYER,title="♡ Player Status",tab="♡ Player",collapsible=true,items={
    {type="label",id="status",label="Load a save to view player status"},
    {type="meter",id="health",label="♡  Health",default={percent=0,text="—"},color={R=0.807,G=0.376,B=0.533,A=1}},
    {type="meter",id="staminaMeter",label="ϟ  Stamina",default={percent=0,text="—"},color={R=0.392,G=0.672,B=0.456,A=1}},
    {type="meter",id="activationMeter",label="❀  Activation Charge",default={percent=0,text="—"},color={R=0.552,G=0.386,B=0.823,A=1}},
    {type="label",id="level",label="✿  Level    —"},
    {type="button",id="stamina",label="Refill stamina now",variant="success",onClick=function() restore("stamina") end},
    {type="button",id="refresh",label="Refresh status",onClick=refreshPlayer},
}})

ModMenu.Register({id=SKILLS,title="✦ Skill Points",tab="✦ Progression",items={
    {type="label",id="status",label="Available skill points: load a save first"},
    {type="number",id="amount",label="Skill point amount",default=config.skillAmount,min=1,max=999,integer=true,onChange=function(v) config.skillAmount=clamp(v,1,999);saveConfig() end},
    {type="row",items={{type="button",id="add",label="Add",variant="success",onClick=function() changeSkills(clamp(ModMenu.Get(SKILLS,"amount"),1,999),false) end},
        {type="button",id="remove",label="Remove",variant="warning",onClick=function() changeSkills(-clamp(ModMenu.Get(SKILLS,"amount"),1,999),false) end}}},
    {type="button",id="clear",label="Clear available points",variant="danger",confirm={title="Clear available skill points?",message="Already unlocked skills are not removed.",confirmLabel="Clear points"},onClick=clearSkills},
}})
ModMenu.Register({id=XP,title="☆ Experience (XP)",tab="✦ Progression",collapsible=true,collapsed=true,items={
    {type="label",id="status",label="Add an XP reward using the game's reward sizes."},
    {type="dropdown",id="reward",label="Reward size",options={"Very small","Small","Medium","Large","Very large"},default="Small"},
    {type="button",id="award",label="Add XP",variant="success",onClick=awardXP},
}})
corruptionControl = require('CorruptionLevelControl')
corruptionControl.Init(ModMenu,player,charDev,log,{
    defaultLevel=config.mutationLevel,
    defaultAmount=config.mutationAmount,
    onLevelChanged=function(v) config.mutationLevel=clamp(v,1,15);saveConfig() end,
    onAmountChanged=function(v) config.mutationAmount=clamp(v,1,999);saveConfig() end,
    changeRaw=changeMutation,
    refresh=refreshMutation,
})

ModMenu.Register({id=CURRENCY,title="✦ Coins",tab="❀ Inventory",collapsible=true,items={
    {type="label",id="status",label="Coins: load a save first"},
    {type="number",id="amount",label="Coin amount",default=config.coinAmount,min=1,max=999999,integer=true,onChange=function(v) config.coinAmount=clamp(v,1,999999);saveConfig() end},
    {type="row",items={{type="button",id="add",label="Add coins",variant="success",onClick=function() changeCoins(clamp(ModMenu.Get(CURRENCY,"amount"),1,999999)) end},
        {type="button",id="remove",label="Remove coins",variant="warning",onClick=function() changeCoins(-clamp(ModMenu.Get(CURRENCY,"amount"),1,999999)) end}}},
}})
ModMenu.Register({id=MATERIALS,title="❀ Crafting Materials",tab="❀ Inventory",collapsible=true,items={
    {type="dropdown",id="material",label="Material",searchable=true,placeholder="Search materials...",maxVisible=150,options={{label="Items scan when menu opens",value=false}},onChange=function(v) selectedMaterial=v end},
    {type="number",id="quantity",label="Quantity",default=config.materialQuantity,min=1,max=99,integer=true,onChange=function(v) config.materialQuantity=clamp(v,1,99);saveConfig() end},
    {type="button",id="give",label="Add material",variant="success",onClick=function() give(selectedMaterial,clamp(ModMenu.Get(MATERIALS,"quantity"),1,99),1,MATERIALS) end},
    {type="label",id="actionStatus",label="Choose a material, then add it"},
}})
ModMenu.Register({id=MANUALS,title="♡ Skill Manuals",tab="❀ Inventory",collapsible=true,collapsed=true,items={
    {type="label",id="scanStatus",label="Skill manuals: Not indexed yet. Use Refresh game lists & status, or load a save first."},
    {type="label",label="Adds the physical manual only. Read or use it normally through the game."},
    {type="dropdown",id="manual",label="Manual",searchable=true,placeholder="Search skill manuals...",maxVisible=200,options={{label="Manuals scan when menu opens",value=false}},onChange=function(v) selectedManual=v end},
    {type="button",id="give",label="Give selected manual",variant="success",onClick=function() give(selectedManual,1,1,MANUALS) end},
    {type="label",id="actionStatus",label="Choose a manual, then give it"},
}})
ModMenu.Register({id=KEYS,title="! Keys & Key Items — Unsafe",tab="❀ Inventory",collapsible=true,collapsed=true,items={
    {type="label",id="scanStatus",label="Key items: Not indexed yet. Use Refresh game lists & status, or load a save first."},
    {type="label",label="Quest state is not advanced. Wrong or duplicate keys can disrupt progression or remain permanently."},
    {type="dropdown",id="key",label="Key item",searchable=true,placeholder="Search key items...",maxVisible=200,options={{label="Keys scan when menu opens",value=false}},onChange=function(v) selectedKey=v end},
    {type="button",id="give",label="Give selected key",variant="danger",confirm={title="Give this key item?",message="This adds the physical key only. It does not complete the quest or acquisition event that normally awards it. The key may duplicate, remain permanently, bypass progression, or cause a quest mismatch.",confirmLabel="Give key",cancelLabel="Cancel"},onClick=function() give(selectedKey,1,1,KEYS) end},
    {type="label",id="actionStatus",label="Choose a key item, then give it"},
}})
ModMenu.Register({id=ITEMS,title="☆ Items and Equipment",tab="❀ Inventory",collapsible=true,collapsed=true,items={
    {type="label",id="scanStatus",label="Items: Not indexed yet. Use Refresh game lists & status, or load a save first."},
    {type="dropdown",id="category",label="Category",options={"All","Weapons","Clothing","Consumables","Materials","Recipes","Junk"},default=config.itemCategory,onChange=function(v) config.itemCategory=v;selectedItem=false;saveConfig();if itemsScanned then ModMenu.SetOptions(ITEMS,"item",itemOptions(v),false) end end},
    {type="dropdown",id="item",label="Item",searchable=true,placeholder="Search safe items...",maxVisible=200,options={{label="Items scan when menu opens",value=false}},onChange=function(v) selectedItem=v end},
    {type="row",items={{type="number",id="quantity",label="Quantity",default=config.itemQuantity,min=1,max=99,integer=true,onChange=function(v) config.itemQuantity=clamp(v,1,99);saveConfig() end},
        {type="number",id="level",label="Item level",default=config.itemLevel,min=1,max=255,integer=true,onChange=function(v) config.itemLevel=clamp(v,1,255);saveConfig() end}}},
    {type="button",id="give",label="Give selected item",variant="success",onClick=function() give(selectedItem,clamp(ModMenu.Get(ITEMS,"quantity"),1,99),clamp(ModMenu.Get(ITEMS,"level"),1,255),ITEMS) end},
    {type="button",id="giveEquip",label="Give and equip selected item",variant="success",onClick=function() giveAndEquip(selectedItem,clamp(ModMenu.Get(ITEMS,"level"),1,255),ITEMS) end},
    {type="label",label="Give and equip adds one copy and wears it immediately. Weapons and clothing only; leave combat first. Whatever occupied the slot returns to your inventory."},
    {type="button",id="giveAll",label="Give all Weapons + Clothing (one each)",variant="danger",confirm={
        title="Give all Weapons and Clothing?",
        message="Adds one of every indexed Weapon and Clothing item. Every item that supports levels uses the selected Item Level. Consumables, materials, recipes and junk are excluded because bulk-adding some database entries can crash the game. This can still add hundreds of items, permanently clutter the inventory, or hit item limits. Each item waits for the previous one to finish, then pauses 20 ms. Do not save, load, close the game, or run another inventory action until it finishes.",
        confirmLabel="Give equipment",cancelLabel="Cancel",variant="danger"},onClick=giveAllEquipment},
    {type="label",id="actionStatus",label="Quest/readable items are excluded; manuals and keys have separate panels above"},
}})
ModMenu.Register({id="DWQuickslots",title="☆ Quickslots",tab="❀ Inventory",items={
    {type="label",label="Assigns the item currently selected in Items and Equipment above to one of the four quickslots."},
    {type="dropdown",id="slot",label="Quickslot",options=QUICKSLOTS,default=0,onChange=function(v) selectedQuickslot=clamp(v,0,3) end},
    {type="button",id="read",label="Read selected quickslot",onClick=function() readQuickslot("DWQuickslots") end},
    {type="button",id="assign",label="Assign selected item to quickslot",variant="success",onClick=function()
        assignQuickslot(selectedItem,clamp(ModMenu.Get(ITEMS,"level"),1,255),"DWQuickslots") end},
    {type="label",id="slotStatus",label="Choose a slot, then read or assign."},
    {type="label",label="You must already own the item. Quickslots can be reassigned normally in game, so this needs no restore."},
}})
ModMenu.Register({id='DWMenuWarnings',title='! Warnings & Limitations',tab='! Warnings',items={
    {type='label',label='CHEATS WILL TRIGGER ACHIEVEMENTS. Saved changes remain after removing the mod.'},
    {type='label',label='Light Respec keeps Ultimates and broad earned protections. Medium removes Ultimates too. Full restores only Compel Soul, Astral Communion, Voracious Bite, Mercurial Fervour and Wolf Transform after the native reset.'},
    {type='label',label='Font of Life and Mandrake Ward may survive even Full Respec because the game-native ResetAllTraits operation does not clear them. Legendary-consumable or earned-rank differences may become skill points; consumed items are not restored.'},
    {type='label',label='Grant Specific Perk searches the complete loaded trait database and directly sets one chosen perk to a requested valid rank. It bypasses prerequisites, exclusivity, manuals, quests and skill-point cost.'},
    {type='label',label='Bulk Unlock maxes ordinary, hidden, manual, quest and boss traits and marks recipe/manual-based skill access as learned/read. It may be used repeatedly.'},
    {type='label',label='Give Manual adds the physical skill manual only. Duplicate or out-of-order manuals may not provide another unlock.'},
    {type='label',label='Give All Equipment is limited to Weapons and Clothing. Bulk recipes, consumables, materials and junk are excluded after a native crash was traced to Recipe4. Levelled equipment uses the selected Item Level. Wait for completion before saving or loading.'},
    {type='label',label='Give Key adds only the physical key, not its quest event. Keys can duplicate, remain permanently, bypass progression or mismatch quest state.'},
    {type='label',label='After Set Corruption Level, trigger one native corruption update so gameplay effects refresh: press +1 raw charge (optionally -1 afterward), or drink blood. Lowering the level does not undo quests, dialogue, unlocks, achievements or other events already triggered.'},
    {type='label',label='Unlock All Shrines permanently changes map progression. Lowering Infamy does not undo world or quest events.'},
    {type='label',label='Time can move forward across days. Rewind only adjusts slots within the current day/phase: you cannot go back to a previous day, and quest events are not reversed.'},
    {type='label',label='Leave combat and turn cheats OFF for progression operations. Never reload scripts while respec or verification is running.'},
    {type='label',label='If verification fails, do not save or retry; reload an earlier save and restart the game.'},
    {type='label',label='These controls run through the desktop menu and a headless native adapter. No in-game menu overlay is loaded.'},
    {type='label',label='The supplied menu author reports validation on build 25129649 with HookLoadMap disabled. The game has since updated to build 25191761 (CL258042). Controls resolve by name so they survive a patch, but gameplay acceptance is being re-verified per control.'},
    {type='label',label='Eye colour is identity-gated to the previous build and will refuse until its material work is reviewed against the new executable.'},
    {type='label',label='Health / god mode is unavailable. See the README for installation, compatibility and recovery details.'},
}})

local CombatControls=require('CombatControls')
CombatControls.Init(ModMenu,player,log,sourcePath:gsub('[Mm][Aa][Ii][Nn]%.lua$',''))
local ActivationControl=require('ActivationControl')
ActivationControl.Init(ModMenu,player,log,sourcePath:gsub('[Mm][Aa][Ii][Nn]%.lua$',''))
local GodMode=require('GodMode')
-- Keep recovery of previously owned damage flags, but hide the nonworking cheat.
GodMode.Init(ModMenu,player,log,sourcePath:gsub('[Mm][Aa][Ii][Nn]%.lua$',''),true)
local CooldownControl=require('CooldownControl')
CooldownControl.Init(ModMenu,player,log)
local ParryAssist=require('ParryAssist')
ParryAssist.Init(ModMenu,player,log,sourcePath:gsub('[Mm][Aa][Ii][Nn]%.lua$',''))

ModMenu.OnOpen(function()
    refreshPlayer();refreshSkills();refreshMutation();refreshCurrency();scanItems()
    ExecuteInGameThread(ActivationControl.Recover)
    ExecuteInGameThread(GodMode.Recover)
    ExecuteInGameThread(ParryAssist.Recover)
end)

saveConfig()
log("Headless source registered; native callbacks await explicit commands")
-- The in-game menu refreshed player status, skills, Corruption, coins and the item
-- catalog when it opened; the desktop menu never opens it, so with a save loaded those
-- cards stayed on "load a save first" until each Refresh was pressed. Run that same
-- refresh once per session as soon as the player exists. The readiness probe is silent:
-- a not-yet-ready session must error (so the runtime retries) without touching labels.
local function sessionReady()
    local p=player(true)
    if not p or not valid(p.CombatComponent) then error("Player not ready for the session refresh",0) end
    -- The same read refreshPlayer opens with: a pawn whose combat component cannot
    -- answer it yet is not ready, and must not be asked (that would publish a failure).
    local ready,hp=pcall(function() return p.CombatComponent:GetHealthPercentage() end)
    if not ready or type(hp)~="number" then error("Player combat component not ready for the session refresh",0) end
    refreshPlayer();refreshSkills();refreshMutation();refreshCurrency();scanItems()
end

return { SessionReady=sessionReady, ResetSession=function()
    if bulkGiveActive and bulkGiveIssued then bulkGiveInterrupted=true end
    bulkGiveActive=false;bulkGiveIssued=false;pendingHandle=nil;keyLocked=false
    itemsScanned=false;itemCache={};materialOptions={};manualOptions={};keyOptions={}
    selectedMaterial=false;selectedManual=false;selectedKey=false;selectedItem=false
    for _,pair in ipairs({{MATERIALS,"material"},{MANUALS,"manual"},{KEYS,"key"},{ITEMS,"item"}}) do
        ModMenu.SetOptions(pair[1],pair[2],{{label="Refresh items for the current player",value=false}},false)
    end
    if bulkGiveInterrupted then ModMenu.SetLabel(ITEMS,"actionStatus","STOP: interrupted bulk equipment request. Reload the protected save and restart.") end
end }
