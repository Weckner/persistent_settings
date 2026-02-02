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
    autoApply = false,          -- Auto-apply settings on new character login
    dbVersion = 1,
}

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
    
    if not PersistentSettingsDB.settings then
        self:Print("No settings have been captured yet. Log into your main and use /ps capture")
        return false
    end
    
    local applied = 0
    local skipped = 0
    
    for _, category in ipairs(PS.SettingDefinitions) do
        for _, setting in ipairs(category.settings) do
            -- Only apply if this setting is enabled for inheritance
            if PersistentSettingsDB.enabledSettings[setting.key] then
                local value = PersistentSettingsDB.settings[setting.key]
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
            end
        end
    end
end

local function OnAddonLoaded(self, event, loadedAddon)
    if loadedAddon ~= addonName then return end
    
    InitializeDB()
    PS:Print("v" .. PS.VERSION .. " loaded. Type /ps for options.")
    
    frame:UnregisterEvent("ADDON_LOADED")
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
