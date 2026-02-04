--[[
    Persistent Settings
    Inherit settings from your main character to all alts
]]

-- Addon namespace
local addonName, PS = ...
_G.PersistentSettings = PS

-- Version
PS.VERSION = "0.1.0"

-- Default database structure
local DefaultDB = {
    mainCharacter = nil,        -- "Name-Realm" of the designated main
    settings = {},              -- Captured settings from main
    enabledSettings = {},       -- Which settings are enabled for inheritance
    addonSettings = {},        -- Captured addon SavedVariables: ["Addon Name"] = { ... }
    autoApply = false,          -- Auto-apply settings on new character login
    dbVersion = 1,
}

-- Addon settings: WoW addon folder name -> display key
local COMBAT_TIMER_ADDON = "combat timer"
local COMBAT_TIMER_KEY = "addon:Combat Timer"

-- Addon load check (retail uses C_AddOns; fallback for older clients)
local function IsAddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    return _G.IsAddOnLoaded and _G.IsAddOnLoaded(name) or false
end

-- Local references
local frame = CreateFrame("Frame")

-----------------------------------------------------------
-- Utility Functions
-----------------------------------------------------------

-- Get the current character's full name (Name-Realm)
function PS:GetCharacterID()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

-- Check if current character is the main
function PS:IsMainCharacter()
    if not PersistentSettingsDB or not PersistentSettingsDB.mainCharacter then
        return false
    end
    return PersistentSettingsDB.mainCharacter == self:GetCharacterID()
end

-- Check if this is a new character (first login with addon)
function PS:IsNewCharacter()
    local charID = self:GetCharacterID()
    PersistentSettingsDB.knownCharacters = PersistentSettingsDB.knownCharacters or {}
    return not PersistentSettingsDB.knownCharacters[charID]
end

-- Mark character as known
function PS:MarkCharacterKnown()
    local charID = self:GetCharacterID()
    PersistentSettingsDB.knownCharacters = PersistentSettingsDB.knownCharacters or {}
    PersistentSettingsDB.knownCharacters[charID] = true
end

-----------------------------------------------------------
-- Settings Management
-----------------------------------------------------------

-- Get CVar value (handles both boolean and numeric CVars)
function PS:GetCVarValue(cvarName)
    local value = C_CVar.GetCVar(cvarName)
    if value == nil then
        return nil
    end
    -- Convert "0"/"1" to boolean-like values for storage
    return value
end

-- Set CVar value
function PS:SetCVarValue(cvarName, value)
    if value == nil then return false end
    C_CVar.SetCVar(cvarName, value)
    return true
end

-- Get a setting definition by key
function PS:GetSettingDefinition(cvarName)
    if not PS.SettingDefinitions then return nil end
    
    for _, category in ipairs(PS.SettingDefinitions) do
        for _, setting in ipairs(category.settings) do
            if setting.key == cvarName then
                return setting
            end
        end
    end
    return nil
end

-----------------------------------------------------------
-- Addon Settings (e.g. Combat Timer - positions + font)
-----------------------------------------------------------

-- Deep copy table (for addon DB snapshots)
local function DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

-- Capture Combat Timer settings (only if addon is loaded)
function PS:CaptureCombatTimer()
    if not IsAddOnLoaded(COMBAT_TIMER_ADDON) then return 0 end
    if _G.CombatTimerDB == nil and _G.CombatTimerFontDB == nil then return 0 end

    PersistentSettingsDB.addonSettings = PersistentSettingsDB.addonSettings or {}
    local out = {}
    if _G.CombatTimerDB then
        out.db = DeepCopy(_G.CombatTimerDB)
    end
    if _G.CombatTimerFontDB then
        out.fontDB = DeepCopy(_G.CombatTimerFontDB)
    end
    if (out.db and next(out.db)) or (out.fontDB and next(out.fontDB)) then
        PersistentSettingsDB.addonSettings["Combat Timer"] = out
        return 1
    end
    return 0
end

-- Apply Combat Timer settings (only if addon is loaded; safe if not)
function PS:ApplyCombatTimer()
    local data = PersistentSettingsDB.addonSettings and PersistentSettingsDB.addonSettings["Combat Timer"]
    if not data then return 0 end

    if not IsAddOnLoaded(COMBAT_TIMER_ADDON) then return 0 end
    if _G.CombatTimerDB == nil then return 0 end

    if data.db then
        for k, v in pairs(data.db) do
            _G.CombatTimerDB[k] = DeepCopy(v)
        end
    end
    if data.fontDB then
        if _G.CombatTimerFontDB == nil then
            _G.CombatTimerFontDB = {}
        end
        for k, v in pairs(data.fontDB) do
            _G.CombatTimerFontDB[k] = v
        end
    end

    if type(_G.CombatTimer_RefreshLayout) == "function" then
        _G.CombatTimer_RefreshLayout()
    end
    return 1
end

-- Capture all enabled settings from main character
function PS:CaptureAllSettings()
    if not self:IsMainCharacter() then
        self:Print("Only the main character can capture settings.")
        return false
    end
    
    if not PS.SettingDefinitions then
        self:Print("No settings defined.")
        return false
    end
    
    local count = 0
    for _, category in ipairs(PS.SettingDefinitions) do
        for _, setting in ipairs(category.settings) do
            local value = self:GetCVarValue(setting.key)
            if value ~= nil then
                PersistentSettingsDB.settings[setting.key] = value
                count = count + 1
            else
                self:Print("Warning: Could not read CVar '" .. setting.key .. "'")
            end
        end
    end

    -- Addon settings (only if addon is loaded)
    PersistentSettingsDB.addonSettings = PersistentSettingsDB.addonSettings or {}
    if PersistentSettingsDB.enabledSettings[COMBAT_TIMER_KEY] then
        count = count + self:CaptureCombatTimer()
    end

    self:Print(string.format("Captured %d settings from main character.", count))
    return true
end

-- Apply all enabled settings to current character
function PS:ApplyAllSettings()
    if self:IsMainCharacter() then
        self:Print("Cannot apply settings to the main character.")
        return false
    end
    
    if not PersistentSettingsDB.mainCharacter then
        self:Print("No main character designated. Open settings with /ps")
        return false
    end

    local hasCVars = PersistentSettingsDB.settings and next(PersistentSettingsDB.settings)
    local hasAddonSettings = PersistentSettingsDB.addonSettings and next(PersistentSettingsDB.addonSettings)
    if not hasCVars and not hasAddonSettings then
        self:Print("No settings have been captured yet. Log into your main and use /ps capture")
        return false
    end

    local applied = 0
    local skipped = 0

    for _, category in ipairs(PS.SettingDefinitions) do
        for _, setting in ipairs(category.settings) do
            if PersistentSettingsDB.enabledSettings[setting.key] then
                local value = PersistentSettingsDB.settings and PersistentSettingsDB.settings[setting.key]
                if value ~= nil then
                    if self:SetCVarValue(setting.key, value) then
                        applied = applied + 1
                    end
                else
                    skipped = skipped + 1
                end
            end
        end
    end

    -- Addon settings (only apply if that addon is loaded)
    if PersistentSettingsDB.enabledSettings[COMBAT_TIMER_KEY] then
        applied = applied + self:ApplyCombatTimer()
    end

    self:Print(string.format("Applied %d settings from %s", applied, PersistentSettingsDB.mainCharacter))
    if skipped > 0 then
        self:Print(string.format("(%d settings skipped - not captured)", skipped))
    end
    return true
end


-----------------------------------------------------------
-- Main Character Management
-----------------------------------------------------------

-- Set current character as main
function PS:SetAsMain()
    local charID = self:GetCharacterID()
    PersistentSettingsDB.mainCharacter = charID
    self:Print(charID .. " is now set as the main character.")
    
    -- Capture settings when setting as main
    self:CaptureAllSettings()
    
    -- Update UI if open
    if PS.UpdateUI then
        PS:UpdateUI()
    end
end

-- Clear main character designation
function PS:ClearMain()
    PersistentSettingsDB.mainCharacter = nil
    self:Print("Main character designation cleared.")
    
    if PS.UpdateUI then
        PS:UpdateUI()
    end
end

-----------------------------------------------------------
-- Chat Output
-----------------------------------------------------------

function PS:Print(msg)
    print("|cff00ccff[Persistent Settings]|r " .. tostring(msg))
end

-----------------------------------------------------------
-- Initialization
-----------------------------------------------------------

local function InitializeDB()
    -- Create DB if it doesn't exist
    if not PersistentSettingsDB then
        PersistentSettingsDB = {}
    end
    
    -- Merge defaults
    for key, value in pairs(DefaultDB) do
        if PersistentSettingsDB[key] == nil then
            if type(value) == "table" then
                PersistentSettingsDB[key] = {}
            else
                PersistentSettingsDB[key] = value
            endg
        end
    end
end

local function OnAddonLoaded(self, event, loadedAddon)
    if loadedAddon == addonName then
        InitializeDB()
        PS:Print("v" .. PS.VERSION .. " loaded. Type /ps for options.")
    end
    -- When Combat Timer loads (e.g. LoadOnDemand), apply stored settings if enabled
    if loadedAddon == COMBAT_TIMER_ADDON and PersistentSettingsDB and PersistentSettingsDB.enabledSettings and PersistentSettingsDB.enabledSettings[COMBAT_TIMER_KEY] then
        PS:ApplyCombatTimer()
    end
end

local function OnPlayerLogin(self, event)
    -- Check if this is a new character
    if PS:IsNewCharacter() then
        if PersistentSettingsDB.mainCharacter and PersistentSettingsDB.autoApply then
            PS:Print("New character detected. Applying settings from " .. PersistentSettingsDB.mainCharacter)
            -- Delay slightly to ensure game is ready
            C_Timer.After(2, function()
                PS:ApplyAllSettings()
            end)
        elseif PersistentSettingsDB.mainCharacter then
            PS:Print("New character detected. Type /ps apply to inherit settings.")
        end
    end
    
    -- Mark character as known
    PS:MarkCharacterKnown()
    
    frame:UnregisterEvent("PLAYER_LOGIN")
end

-----------------------------------------------------------
-- Event Registration
-----------------------------------------------------------

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(self, event, ...)
    elseif event == "PLAYER_LOGIN" then
        OnPlayerLogin(self, event)
    end
end)

-----------------------------------------------------------
-- Slash Commands
-----------------------------------------------------------

SLASH_PERSISTENTSETTINGS1 = "/ps"
SLASH_PERSISTENTSETTINGS2 = "/persistentsettings"

SlashCmdList["PERSISTENTSETTINGS"] = function(msg)
    local cmd = msg:lower():trim()
    
    if cmd == "" or cmd == "options" or cmd == "config" then
        -- Open the UI
        if PS.ToggleUI then
            PS:ToggleUI()
        else
            PS:Print("UI not yet loaded.")
        end
    elseif cmd == "main" or cmd == "setmain" then
        PS:SetAsMain()
    elseif cmd == "apply" then
        PS:ApplyAllSettings()
    elseif cmd == "capture" then
        PS:CaptureAllSettings()
    elseif cmd == "status" then
        if PersistentSettingsDB.mainCharacter then
            PS:Print("Main character: " .. PersistentSettingsDB.mainCharacter)
            PS:Print("Current character: " .. PS:GetCharacterID())
            PS:Print("Is main: " .. (PS:IsMainCharacter() and "Yes" or "No"))
        else
            PS:Print("No main character set. Use /ps main to set current character as main.")
        end
    elseif cmd == "help" then
        PS:Print("Commands:")
        PS:Print("  /ps - Open settings window")
        PS:Print("  /ps main - Set current character as main")
        PS:Print("  /ps apply - Apply settings from main")
        PS:Print("  /ps capture - Capture settings (main only)")
        PS:Print("  /ps status - Show current status")
    else
        PS:Print("Unknown command. Type /ps help for available commands.")
    end
end
