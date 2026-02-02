--[[
    Persistent Settings - UI Module
    Settings window for managing inherited settings
]]

local addonName, PS = ...

-- UI State
local mainFrame = nil
local settingsCheckboxes = {}

-- UI Constants
local FRAME_WIDTH = 400
local FRAME_HEIGHT = 500
local PADDING = 16
local ROW_HEIGHT = 24

-----------------------------------------------------------
-- UI Helper Functions
-----------------------------------------------------------

local function CreateCheckbox(parent, name, label, tooltip, onClick)
    local checkbox = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
    checkbox.Text:SetText(label)
    checkbox.tooltipText = tooltip
    
    if onClick then
        checkbox:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            onClick(self, checked)
        end)
    end
    
    return checkbox
end

local function CreateButton(parent, name, text, width, height, onClick)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 120, height or 24)
    button:SetText(text)
    
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    
    return button
end

local function CreateSectionHeader(parent, text)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetText(text)
    return header
end

local function CreateLabel(parent, text, template)
    local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    label:SetText(text)
    return label
end

-----------------------------------------------------------
-- Main Frame Creation
-----------------------------------------------------------

local function CreateMainFrame()
    -- Main frame
    local frame = CreateFrame("Frame", "PersistentSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()
    
    -- Title
    frame.TitleText:SetText("Persistent Settings")
    
    -- Make it closable with Escape
    tinsert(UISpecialFrames, "PersistentSettingsFrame")
    
    -- Content area - anchor directly to main frame with offsets for title bar and border
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 4, -30)  -- Account for title bar
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING - 4, PADDING + 4)
    frame.content = content
    
    -- Current character info
    local charLabel = CreateLabel(content, "Current Character:", "GameFontNormalSmall")
    charLabel:SetPoint("TOPLEFT", 0, 0)
    
    local charName = CreateLabel(content, "", "GameFontHighlight")
    charName:SetPoint("LEFT", charLabel, "RIGHT", 8, 0)
    frame.charName = charName
    
    -- Main character section
    local mainSection = CreateSectionHeader(content, "Main Character")
    mainSection:SetPoint("TOPLEFT", charLabel, "BOTTOMLEFT", 0, -20)
    
    local mainLabel = CreateLabel(content, "Designated Main:", "GameFontNormalSmall")
    mainLabel:SetPoint("TOPLEFT", mainSection, "BOTTOMLEFT", 0, -8)
    
    local mainName = CreateLabel(content, "None", "GameFontHighlight")
    mainName:SetPoint("LEFT", mainLabel, "RIGHT", 8, 0)
    frame.mainName = mainName
    
    -- Is main indicator
    local isMainLabel = CreateLabel(content, "", "GameFontGreen")
    isMainLabel:SetPoint("LEFT", mainName, "RIGHT", 16, 0)
    frame.isMainLabel = isMainLabel
    
    -- Set as Main button
    local setMainBtn = CreateButton(content, nil, "Set Current as Main", 160, 28, function()
        PS:SetAsMain()
    end)
    setMainBtn:SetPoint("TOPLEFT", mainLabel, "BOTTOMLEFT", 0, -12)
    frame.setMainBtn = setMainBtn
    
    -- Clear Main button
    local clearMainBtn = CreateButton(content, nil, "Clear Main", 100, 28, function()
        PS:ClearMain()
    end)
    clearMainBtn:SetPoint("LEFT", setMainBtn, "RIGHT", 8, 0)
    frame.clearMainBtn = clearMainBtn
    
    -- Settings section
    local settingsSection = CreateSectionHeader(content, "Settings to Inherit")
    settingsSection:SetPoint("TOPLEFT", setMainBtn, "BOTTOMLEFT", 0, -24)
    
    local settingsNote = CreateLabel(content, "Select which settings new characters should inherit:", "GameFontNormalSmall")
    settingsNote:SetPoint("TOPLEFT", settingsSection, "BOTTOMLEFT", 0, -8)
    settingsNote:SetTextColor(0.7, 0.7, 0.7)
    
    -- Scroll frame for settings list
    local scrollFrame = CreateFrame("ScrollFrame", "PersistentSettingsScrollFrame", content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", settingsNote, "BOTTOMLEFT", 0, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -24, 60)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(FRAME_WIDTH - PADDING * 2 - 40, 400) -- Will be resized dynamically
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild
    
    -- Bottom buttons - row 1
    local applyBtn = CreateButton(content, nil, "Apply from Main", 140, 26, function()
        PS:ApplyAllSettings()
    end)
    applyBtn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    frame.applyBtn = applyBtn
    
    local captureBtn = CreateButton(content, nil, "Capture Settings", 140, 26, function()
        PS:CaptureAllSettings()
    end)
    captureBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
    frame.captureBtn = captureBtn
    
    -- Auto-apply checkbox
    local autoApplyCheck = CreateCheckbox(content, nil, "Auto-apply to new characters", 
        "Automatically apply settings when logging into a new character",
        function(self, checked)
            PersistentSettingsDB.autoApply = checked
        end)
    autoApplyCheck:SetPoint("BOTTOMLEFT", applyBtn, "TOPLEFT", -4, 6)
    frame.autoApplyCheck = autoApplyCheck
    
    return frame
end

-----------------------------------------------------------
-- Settings List Population
-----------------------------------------------------------

-- Setting definitions
-- Format: { key = "cvarName", name = "Display Name", tooltip = "Description" }
PS.SettingDefinitions = {
    {
        category = "Controls",
        settings = {
            { key = "deselectOnClick", name = "Sticky Target", tooltip = "Keep target selected when clicking empty space (inverse of deselect)", invert = true },
            { key = "autoDismountFlying", name = "Auto Dismount in Flight", tooltip = "Automatically dismount when casting spells while flying" },
            { key = "autoClearAFK", name = "Auto Cancel Away Mode", tooltip = "Automatically clear AFK status when you move or act" },
            { key = "interactOnLeftClick", name = "Interact on Left Click", tooltip = "Left-click to interact with NPCs and objects" },
            { key = "lootUnderMouse", name = "Open Loot Window at Mouse", tooltip = "Position loot window at cursor location" },
            { key = "autoLootDefault", name = "Auto Loot", tooltip = "Automatically loot all items" },
            { key = "combinedBags", name = "Combine Bags", tooltip = "Show all bags as one combined bag" },
            { key = "softTargetInteract", name = "Enable Interact Key", tooltip = "Enable the interact key functionality" },
            { key = "softTargettingInteractKeySound", name = "Interact Key Sound Cue", tooltip = "Play sound when interact key target is available" },
            { key = "ClipCursor", name = "Lock Cursor to Window", tooltip = "Keep mouse cursor within game window" },
            { key = "mouseInvertPitch", name = "Invert Mouse", tooltip = "Invert vertical mouse movement" },
            { key = "cameraWaterCollision", name = "Water Collision", tooltip = "Camera collides with water surface" },
        }
    },
    {
        category = "Interface",
        settings = {
            { key = "showInGameNavigation", name = "In Game Navigation", tooltip = "Show navigation arrows for quest objectives" },
            { key = "showTutorials", name = "Tutorials", tooltip = "Show in-game tutorials and tips" },
            { key = "chatBubbles", name = "Chat Bubbles", tooltip = "Show chat bubbles above characters" },
            { key = "chatBubblesParty", name = "Party Chat Bubbles", tooltip = "Show chat bubbles for party members" },
            { key = "ReplaceOtherPlayerPortraits", name = "Replace Player Frame Portraits", tooltip = "Use class icons instead of character portraits for party frames" },
            { key = "ReplaceMyPlayerPortrait", name = "Replace My Frame Portrait", tooltip = "Use class icon instead of character portrait for your frame" },
            -- { key = "???", name = "Show Warband Completed Quests", tooltip = "Show quests completed by other Warband characters" }, -- CVar not found
        }
    },
}

-- Store UI elements for cleanup
local settingsUIElements = {}

local function PopulateSettingsList()
    if not mainFrame or not mainFrame.scrollChild then return end
    
    local scrollChild = mainFrame.scrollChild
    
    -- Clear existing UI elements
    for _, element in pairs(settingsCheckboxes) do
        element:Hide()
        element:SetParent(nil)
    end
    wipe(settingsCheckboxes)
    
    for _, element in pairs(settingsUIElements) do
        if element.Hide then element:Hide() end
    end
    wipe(settingsUIElements)
    
    local yOffset = 0
    
    -- Check if we have any settings
    local hasSettings = false
    for _, category in ipairs(PS.SettingDefinitions) do
        if #category.settings > 0 then
            hasSettings = true
            break
        end
    end
    
    if not hasSettings then
        local placeholder = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        placeholder:SetPoint("TOPLEFT", 0, 0)
        placeholder:SetText("Settings will be added here.\nCheck back after configuration!")
        placeholder:SetJustifyH("LEFT")
        table.insert(settingsUIElements, placeholder)
        return
    end
    
    -- Create checkboxes for each setting
    for _, category in ipairs(PS.SettingDefinitions) do
        if #category.settings > 0 then
            -- Category header
            local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header:SetPoint("TOPLEFT", 0, yOffset)
            header:SetText(category.category)
            header:SetTextColor(1, 0.82, 0)
            table.insert(settingsUIElements, header)
            yOffset = yOffset - ROW_HEIGHT
            
            -- Settings in category
            for _, setting in ipairs(category.settings) do
                -- Checkbox for enabling inheritance
                local checkbox = CreateCheckbox(scrollChild, nil, setting.name, setting.tooltip,
                    function(self, checked)
                        PersistentSettingsDB.enabledSettings[setting.key] = checked
                    end)
                checkbox:SetPoint("TOPLEFT", 8, yOffset)
                
                -- Set initial state - default to enabled
                if PersistentSettingsDB and PersistentSettingsDB.enabledSettings then
                    -- Default new settings to enabled
                    if PersistentSettingsDB.enabledSettings[setting.key] == nil then
                        PersistentSettingsDB.enabledSettings[setting.key] = true
                    end
                    checkbox:SetChecked(PersistentSettingsDB.enabledSettings[setting.key])
                end
                
                settingsCheckboxes[setting.key] = checkbox
                yOffset = yOffset - ROW_HEIGHT
            end
            
            yOffset = yOffset - 8 -- Extra spacing between categories
        end
    end
    
    -- Resize scroll child to fit content
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

-----------------------------------------------------------
-- UI Update Function
-----------------------------------------------------------

function PS:UpdateUI()
    if not mainFrame then return end
    
    -- Update character name
    mainFrame.charName:SetText(self:GetCharacterID())
    
    -- Update main character display
    if PersistentSettingsDB and PersistentSettingsDB.mainCharacter then
        mainFrame.mainName:SetText(PersistentSettingsDB.mainCharacter)
        
        if self:IsMainCharacter() then
            mainFrame.isMainLabel:SetText("(This character)")
            mainFrame.isMainLabel:SetTextColor(0, 1, 0)
            mainFrame.applyBtn:Disable()
            mainFrame.captureBtn:Enable()
        else
            mainFrame.isMainLabel:SetText("")
            mainFrame.applyBtn:Enable()
            mainFrame.captureBtn:Disable()
        end
    else
        mainFrame.mainName:SetText("None set")
        mainFrame.mainName:SetTextColor(0.5, 0.5, 0.5)
        mainFrame.isMainLabel:SetText("")
        mainFrame.applyBtn:Disable()
        mainFrame.captureBtn:Disable()
    end
    
    -- Update auto-apply checkbox
    if PersistentSettingsDB then
        mainFrame.autoApplyCheck:SetChecked(PersistentSettingsDB.autoApply or false)
    end
    
    -- Populate settings list
    PopulateSettingsList()
end

-----------------------------------------------------------
-- Toggle UI Visibility
-----------------------------------------------------------

function PS:ToggleUI()
    if not mainFrame then
        mainFrame = CreateMainFrame()
    end
    
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:UpdateUI()
        mainFrame:Show()
    end
end

function PS:ShowUI()
    if not mainFrame then
        mainFrame = CreateMainFrame()
    end
    self:UpdateUI()
    mainFrame:Show()
end

function PS:HideUI()
    if mainFrame then
        mainFrame:Hide()
    end
end
