-- Dawnwalker Mod Menu for The Blood of Dawnwalker
-- v3.2 release; gameplay baseline v3 / Steam 25129649 / UE 5.5.4

local ModMenu = require("ModMenu.ModMenu")
local UEHelpers = require("UEHelpers.UEHelpers")

local PLAYER, SKILLS, XP, MUTATION = "DWPlayer", "DWSkills", "DWXP", "DWMutation"
local CURRENCY, MATERIALS, MANUALS, KEYS, ITEMS = "DWCurrency", "DWMaterials", "DWManuals", "DWKeys", "DWItems"

local sourcePath = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
local configPath = sourcePath:gsub("[Mm][Aa][Ii][Nn]%.lua$", "settings.ini")
local config = {
    skillAmount=1, mutationAmount=1, mutationLevel=1, coinAmount=100, materialQuantity=1,
    itemQuantity=1, itemLevel=1, itemCategory="All",
}
local itemCache, materialOptions, manualOptions, keyOptions = {}, {}, {}, {}
local itemsScanned, selectedMaterial, selectedManual, selectedKey, selectedItem, keyLocked = false, false, false, false, false, false

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
local function changeMutation(delta)
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

local bulkGiveActive=false
local function giveAllEquipment()
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
    bulkGiveActive=true
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

ModMenu.Init({title="✦ Dawnwalker Mod Menu ♡",instanceId="DawnwalkerModMenu",key=Key.F6,keyHint="F6",
    dock="center",widthFrac=0.56,topFrac=0.055,bottomFrac=0.20,rightFrac=0.012,
    theme="dark",tabs={"♡ Player","✦ Progression","❀ Inventory","☆ World","! Warnings"},
    kawaiiCards=true,
    -- Converted from the browser preview's sRGB palette into UMG linear color.
    cardBg={R=0.008,G=0.007,B=0.011,A=0.985},
    cardColors={
        {R=0.660,G=0.262,B=0.423,A=0.96},
        {R=0.552,G=0.386,B=0.823,A=0.96},
        {R=0.392,G=0.672,B=0.456,A=0.96},
        {R=0.799,G=0.509,B=0.168,A=0.96},
    },
    colors={
        panelBg={R=0.005,G=0.004,B=0.007,A=0.985},
        panelBorder={R=0.871,G=0.680,B=0.738,A=0.96},
        textPrimary={R=0.896,G=0.799,B=0.784,A=1.0},
        textMuted={R=0.474,G=0.397,B=0.429,A=1.0},
        textAccent={R=0.807,G=0.376,B=0.533,A=1.0},
        textStatus={R=0.799,G=0.509,B=0.168,A=1.0},
        buttonBg={R=0.015,G=0.011,B=0.018,A=0.98},
        buttonText={R=0.896,G=0.799,B=0.784,A=1.0},
        buttonBgPrimary={R=0.078,G=0.033,B=0.127,A=1.0},
        buttonTextPrimary={R=1.0,G=0.880,B=1.0,A=1.0},
        buttonBgSecondary={R=0.074,G=0.047,B=0.095,A=1.0},
        buttonTextSecondary={R=0.855,G=0.723,B=0.855,A=1.0},
        buttonBgSuccess={R=0.107,G=0.296,B=0.171,A=1.0},
        buttonTextSuccess={R=0.896,G=1.0,B=0.871,A=1.0},
        buttonBgDanger={R=0.342,G=0.033,B=0.074,A=1.0},
        buttonTextDanger={R=1.0,G=0.831,B=0.871,A=1.0},
        buttonBgWarning={R=0.638,G=0.296,B=0.074,A=1.0},
        buttonTextWarning={R=0.015,G=0.007,B=0.010,A=1.0},
        buttonBgInfo={R=0.178,G=0.117,B=0.420,A=1.0},
        buttonTextInfo={R=0.896,G=0.880,B=1.0,A=1.0},
        buttonBgActive={R=0.807,G=0.376,B=0.533,A=1.0},
        buttonTextActive={R=0.015,G=0.007,B=0.010,A=1.0},
        buttonBgDisabled={R=0.018,G=0.012,B=0.024,A=1.0},
        buttonTextDisabled={R=0.195,G=0.133,B=0.195,A=1.0},
        sectionHeaderBg={R=0.015,G=0.011,B=0.018,A=0.99},
        sectionMark={R=0.807,G=0.376,B=0.533,A=1.0},
        fieldBg={R=0.011,G=0.009,B=0.013,A=1.0},
        fieldText={R=0.896,G=0.799,B=0.784,A=1.0},
        fieldHint={R=0.296,G=0.205,B=0.319,A=1.0},
        dropdownHeaderBg={R=0.025,G=0.014,B=0.032,A=1.0},
        dropdownHeaderText={R=0.896,G=0.799,B=0.784,A=1.0},
        dropdownOptionBg={R=0.010,G=0.007,B=0.014,A=1.0},
        dropdownOptionText={R=0.896,G=0.799,B=0.784,A=1.0},
        dropdownMore={R=0.552,G=0.296,B=0.552,A=1.0},
        overlayDim={R=0.002,G=0.001,B=0.003,A=0.62},
        confirmCardBg={R=0.014,G=0.008,B=0.018,A=0.99},
        confirmDivider={R=0.386,G=0.145,B=0.337,A=1.0},
    },
    ignoreLook=true,cursorMode="engine",fontScale=1.42})

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
require('CorruptionLevelControl').Init(ModMenu,player,charDev,log,{
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
    {type="label",id="scanStatus",label="Scanning loaded skill manuals..."},
    {type="label",label="Adds the physical manual only. Read or use it normally through the game."},
    {type="dropdown",id="manual",label="Manual",searchable=true,placeholder="Search skill manuals...",maxVisible=200,options={{label="Manuals scan when menu opens",value=false}},onChange=function(v) selectedManual=v end},
    {type="button",id="give",label="Give selected manual",variant="success",onClick=function() give(selectedManual,1,1,MANUALS) end},
    {type="label",id="actionStatus",label="Choose a manual, then give it"},
}})
ModMenu.Register({id=KEYS,title="! Keys & Key Items — Unsafe",tab="❀ Inventory",collapsible=true,collapsed=true,items={
    {type="label",id="scanStatus",label="Scanning loaded key items..."},
    {type="label",label="Quest state is not advanced. Wrong or duplicate keys can disrupt progression or remain permanently."},
    {type="dropdown",id="key",label="Key item",searchable=true,placeholder="Search key items...",maxVisible=200,options={{label="Keys scan when menu opens",value=false}},onChange=function(v) selectedKey=v end},
    {type="button",id="give",label="Give selected key",variant="danger",confirm={title="Give this key item?",message="This adds the physical key only. It does not complete the quest or acquisition event that normally awards it. The key may duplicate, remain permanently, bypass progression, or cause a quest mismatch.",confirmLabel="Give key",cancelLabel="Cancel"},onClick=function() give(selectedKey,1,1,KEYS) end},
    {type="label",id="actionStatus",label="Choose a key item, then give it"},
}})
ModMenu.Register({id=ITEMS,title="☆ Items and Equipment",tab="❀ Inventory",collapsible=true,collapsed=true,items={
    {type="label",id="scanStatus",label="Scanning safe item assets..."},
    {type="dropdown",id="category",label="Category",options={"All","Weapons","Clothing","Consumables","Materials","Recipes","Junk"},default=config.itemCategory,onChange=function(v) config.itemCategory=v;selectedItem=false;saveConfig();if itemsScanned then ModMenu.SetOptions(ITEMS,"item",itemOptions(v),false) end end},
    {type="dropdown",id="item",label="Item",searchable=true,placeholder="Search safe items...",maxVisible=200,options={{label="Items scan when menu opens",value=false}},onChange=function(v) selectedItem=v end},
    {type="row",items={{type="number",id="quantity",label="Quantity",default=config.itemQuantity,min=1,max=99,integer=true,onChange=function(v) config.itemQuantity=clamp(v,1,99);saveConfig() end},
        {type="number",id="level",label="Item level",default=config.itemLevel,min=1,max=255,integer=true,onChange=function(v) config.itemLevel=clamp(v,1,255);saveConfig() end}}},
    {type="button",id="give",label="Give selected item",variant="success",onClick=function() give(selectedItem,clamp(ModMenu.Get(ITEMS,"quantity"),1,99),clamp(ModMenu.Get(ITEMS,"level"),1,255),ITEMS) end},
    {type="button",id="giveAll",label="Give all Weapons + Clothing (one each)",variant="danger",confirm={
        title="Give all Weapons and Clothing?",
        message="Adds one of every indexed Weapon and Clothing item. Every item that supports levels uses the selected Item Level. Consumables, materials, recipes and junk are excluded because bulk-adding some database entries can crash the game. This can still add hundreds of items, permanently clutter the inventory, or hit item limits. Each item waits for the previous one to finish, then pauses 20 ms. Do not save, load, close the game, or run another inventory action until it finishes.",
        confirmLabel="Give equipment",cancelLabel="Cancel",variant="danger"},onClick=giveAllEquipment},
    {type="label",id="actionStatus",label="Quest/readable items are excluded; manuals and keys have separate panels above"},
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
    {type='label',label='The menu uses the engine cursor to avoid custom 16 ms cursor polling. UE4SS overlay rendering can still reduce FPS while open.'},
    {type='label',label='Validated on game build 25129649 with HookLoadMap disabled. Game or UE4SS updates may require a compatibility update.'},
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

local fixed={{key=Key.F12,name="F12",fn=function() changeSkills(1,true) end},{key=Key.F11,name="F11",fn=function() changeSkills(-1,true) end}}
for _,b in ipairs(fixed) do if not IsKeyBindRegistered(b.key) then RegisterKeyBind(b.key,b.fn) else log(b.name.." already registered") end end
saveConfig()
log("Ready: F6 menu; player, progression, inventory and world controls enabled")
