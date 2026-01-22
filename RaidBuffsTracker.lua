local addonName, ns = ...

-- Buff definitions: {spellID(s), settingKey, displayName, classProvider}
local RaidBuffs = {
    {1459, "intellect", "Arcane Intellect", "MAGE"},
    {21562, "stamina", "Power Word: Fortitude", "PRIEST"},
    {6673, "attackPower", "Battle Shout", "WARRIOR"},
    {1126, "versatility", "Mark of the Wild", "DRUID"},
    {462854, "skyfury", "Skyfury", "SHAMAN"},
    {{381748, 364342}, "bronze", "Blessing of the Bronze", "EVOKER"},
}

-- Default settings
local defaults = {
    position = {point = "CENTER", x = 0, y = 0},
    locked = false,
    enabledBuffs = {
        intellect = true,
        stamina = true,
        attackPower = true,
        versatility = true,
        skyfury = true,
        bronze = true,
    },
    iconSize = 32,
    spacing = 0.2,      -- multiplier of iconSize
    textScale = 0.32,   -- multiplier of iconSize
    showBuffReminder = true,
}

-- Locals
local mainFrame
local buffFrames = {}
local updateTicker
local inCombat = false
local testMode = false
local optionsPanel

-- Check if unit has a specific buff (handles single spellID or table of spellIDs)
local function UnitHasBuff(unit, spellIDs)
    if type(spellIDs) ~= "table" then
        spellIDs = {spellIDs}
    end

    for _, id in ipairs(spellIDs) do
        local auraData
        pcall(function()
            auraData = C_UnitAuras.GetUnitAuraBySpellID(unit, id)
        end)
        if auraData then
            return true
        end
    end

    return false
end

-- Get spell texture (handles table of spellIDs)
local function GetBuffTexture(spellIDs)
    local id = type(spellIDs) == "table" and spellIDs[1] or spellIDs
    local texture
    pcall(function()
        texture = C_Spell.GetSpellTexture(id)
    end)
    return texture
end

-- Count group members missing a buff (returns missing, total)
local function CountMissingBuff(spellIDs)
    local missing = 0
    local total = 0
    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers()

    if groupSize == 0 then
        total = 1
        if not UnitHasBuff("player", spellIDs) then
            missing = 1
        end
        return missing, total
    end

    for i = 1, groupSize do
        local unit
        if inRaid then
            unit = "raid" .. i
        else
            if i == 1 then
                unit = "player"
            else
                unit = "party" .. (i - 1)
            end
        end

        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) then
            total = total + 1
            if not UnitHasBuff(unit, spellIDs) then
                missing = missing + 1
            end
        end
    end

    return missing, total
end

-- Forward declarations
local UpdateDisplay, PositionBuffFrames

-- Create icon frame for a buff
local function CreateBuffFrame(buffData, index)
    local spellIDs, key, displayName, classProvider = unpack(buffData)

    local frame = CreateFrame("Frame", "RaidBuffsTracker_" .. key, mainFrame)
    frame.key = key
    frame.spellIDs = spellIDs
    frame.displayName = displayName

    local db = RaidBuffsTrackerDB
    frame:SetSize(db.iconSize, db.iconSize)

    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon:SetDesaturated(false)
    frame.icon:SetVertexColor(1, 1, 1, 1)
    local texture = GetBuffTexture(spellIDs)
    if texture then
        frame.icon:SetTexture(texture)
    end

    -- Border (background behind icon)
    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetPoint("TOPLEFT", -2, 2)
    frame.border:SetPoint("BOTTOMRIGHT", 2, -2)
    frame.border:SetColorTexture(0, 0, 0, 1)

    -- Count text (font size scales with icon size)
    local fontSize = math.floor(db.iconSize * (db.textScale or 0.32))
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    frame.count:SetPoint("CENTER", 0, 0)
    frame.count:SetTextColor(1, 1, 1, 1)
    frame.count:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")

    -- "BUFF!" text for the class that provides this buff
    local _, playerClass = UnitClass("player")
    frame.isPlayerBuff = (playerClass == classProvider)
    if frame.isPlayerBuff then
        frame.buffText = frame:CreateFontString(nil, "OVERLAY")
        frame.buffText:SetPoint("TOP", frame, "BOTTOM", 0, -6)
        frame.buffText:SetFont(STANDARD_TEXT_FONT, math.floor(fontSize * 0.8), "OUTLINE")
        frame.buffText:SetTextColor(1, 1, 1, 1)
        frame.buffText:SetText("BUFF!")
        if not db.showBuffReminder then
            frame.buffText:Hide()
        end
    end

    -- Dragging
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        if not RaidBuffsTrackerDB.locked then
            mainFrame:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
        local point, _, _, x, y = mainFrame:GetPoint()
        RaidBuffsTrackerDB.position = {point = point, x = x, y = y}
    end)

    frame:Hide()
    return frame
end

-- Position all visible buff frames
PositionBuffFrames = function()
    local db = RaidBuffsTrackerDB
    local iconSize = db.iconSize or 32
    local spacing = math.floor(iconSize * (db.spacing or 0.2))

    local visibleFrames = {}
    for _, frame in pairs(buffFrames) do
        if frame:IsShown() then
            table.insert(visibleFrames, frame)
        end
    end

    local count = #visibleFrames
    if count == 0 then return end

    local totalWidth = count * iconSize + (count - 1) * spacing
    local startX = -totalWidth / 2 + iconSize / 2

    for i, frame in ipairs(visibleFrames) do
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", mainFrame, "CENTER", startX + (i - 1) * (iconSize + spacing), 0)
    end
end

-- Update the display
UpdateDisplay = function()
    if testMode then return end

    if inCombat then
        mainFrame:Hide()
        return
    end

    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        mainFrame:Hide()
        return
    end

    local db = RaidBuffsTrackerDB
    local anyVisible = false

    for _, buffData in ipairs(RaidBuffs) do
        local spellIDs, key = unpack(buffData)
        local frame = buffFrames[key]

        if frame and db.enabledBuffs[key] then
            local missing, total = CountMissingBuff(spellIDs)
            if missing > 0 then
                local buffed = total - missing
                frame.count:SetText(buffed .. "/" .. total)
                frame:Show()
                anyVisible = true
            else
                frame:Hide()
            end
        elseif frame then
            frame:Hide()
        end
    end

    if anyVisible then
        mainFrame:Show()
        PositionBuffFrames()
    else
        mainFrame:Hide()
    end
end

-- Start update ticker
local function StartUpdates()
    if updateTicker then
        updateTicker:Cancel()
    end
    updateTicker = C_Timer.NewTicker(1, UpdateDisplay)
    UpdateDisplay()
end

-- Stop update ticker
local function StopUpdates()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
end

-- Make frame draggable
local function SetupDragging()
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")

    mainFrame:SetScript("OnDragStart", function(self)
        if not RaidBuffsTrackerDB.locked then
            self:StartMoving()
        end
    end)

    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        RaidBuffsTrackerDB.position = {point = point, x = x, y = y}
    end)
end

-- Initialize main frame
local function InitializeFrames()
    mainFrame = CreateFrame("Frame", "RaidBuffsTrackerFrame", UIParent)
    mainFrame:SetSize(200, 50)

    local db = RaidBuffsTrackerDB
    mainFrame:SetPoint(db.position.point or "CENTER", UIParent, db.position.point or "CENTER", db.position.x or 0, db.position.y or 0)

    SetupDragging()

    for i, buffData in ipairs(RaidBuffs) do
        local key = buffData[2]
        buffFrames[key] = CreateBuffFrame(buffData, i)
    end

    mainFrame:Hide()
end

-- Update icon sizes and text (called when settings change)
local function UpdateVisuals()
    local db = RaidBuffsTrackerDB
    local size = db.iconSize
    local fontSize = math.floor(size * (db.textScale or 0.32))
    for _, frame in pairs(buffFrames) do
        frame:SetSize(size, size)
        frame.count:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        if frame.buffText then
            frame.buffText:SetFont(STANDARD_TEXT_FONT, math.floor(fontSize * 0.8), "OUTLINE")
            if db.showBuffReminder then
                frame.buffText:Show()
            else
                frame.buffText:Hide()
            end
        end
    end
    UpdateDisplay()
end

-- ============================================================================
-- OPTIONS PANEL
-- ============================================================================

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame", "RaidBuffsTrackerOptions", UIParent, "BackdropTemplate")
    panel:SetWidth(320)
    panel:SetPoint("CENTER")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    panel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata("DIALOG")
    panel:Hide()

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cff00ff00RaidBuffsTracker|r Options")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    local yOffset = -40

    -- Buff checkboxes section
    local buffLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buffLabel:SetPoint("TOPLEFT", 15, yOffset)
    buffLabel:SetText("Tracked Buffs:")
    yOffset = yOffset - 20

    panel.buffCheckboxes = {}
    for _, buffData in ipairs(RaidBuffs) do
        local spellIDs, key, displayName, classProvider = unpack(buffData)

        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(290, 24)
        row:SetPoint("TOPLEFT", 15, yOffset)

        -- Icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 0, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local texture = GetBuffTexture(spellIDs)
        if texture then
            icon:SetTexture(texture)
        end

        -- Checkbox
        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        cb:SetChecked(RaidBuffsTrackerDB.enabledBuffs[key])
        cb:SetScript("OnClick", function(self)
            RaidBuffsTrackerDB.enabledBuffs[key] = self:GetChecked()
            UpdateDisplay()
        end)

        -- Label
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        label:SetText(displayName .. " |cff888888(" .. classProvider .. ")|r")

        panel.buffCheckboxes[key] = cb
        yOffset = yOffset - 26
    end

    yOffset = yOffset - 15

    -- Icon Size slider
    local sizeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("TOP", 0, yOffset)
    sizeLabel:SetText("Icon Size:")

    local sizeValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeValue:SetPoint("LEFT", sizeLabel, "RIGHT", 5, 0)
    sizeValue:SetText(RaidBuffsTrackerDB.iconSize)

    yOffset = yOffset - 25

    local sizeSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOP", 0, yOffset)
    sizeSlider:SetSize(200, 17)
    sizeSlider:SetMinMaxValues(16, 64)
    sizeSlider:SetValueStep(2)
    sizeSlider:SetObeyStepOnDrag(true)
    sizeSlider:SetValue(RaidBuffsTrackerDB.iconSize)
    sizeSlider.Low:SetText("16")
    sizeSlider.High:SetText("64")
    sizeSlider.Text:SetText("")
    sizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        RaidBuffsTrackerDB.iconSize = value
        sizeValue:SetText(value)
        UpdateVisuals()
    end)
    panel.sizeSlider = sizeSlider

    yOffset = yOffset - 40

    -- Spacing slider
    local spacingLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spacingLabel:SetPoint("TOP", 0, yOffset)
    spacingLabel:SetText("Spacing:")

    local spacingValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spacingValue:SetPoint("LEFT", spacingLabel, "RIGHT", 5, 0)
    spacingValue:SetText(string.format("%.0f%%", (RaidBuffsTrackerDB.spacing or 0.2) * 100))

    yOffset = yOffset - 25

    local spacingSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    spacingSlider:SetPoint("TOP", 0, yOffset)
    spacingSlider:SetSize(200, 17)
    spacingSlider:SetMinMaxValues(0, 50)
    spacingSlider:SetValueStep(5)
    spacingSlider:SetObeyStepOnDrag(true)
    spacingSlider:SetValue((RaidBuffsTrackerDB.spacing or 0.2) * 100)
    spacingSlider.Low:SetText("0%")
    spacingSlider.High:SetText("50%")
    spacingSlider.Text:SetText("")
    spacingSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        RaidBuffsTrackerDB.spacing = value / 100
        spacingValue:SetText(value .. "%")
        UpdateDisplay()
    end)
    panel.spacingSlider = spacingSlider

    yOffset = yOffset - 40

    -- Text Size slider
    local textLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textLabel:SetPoint("TOP", 0, yOffset)
    textLabel:SetText("Text Size:")

    local textValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    textValue:SetPoint("LEFT", textLabel, "RIGHT", 5, 0)
    textValue:SetText(string.format("%.0f%%", (RaidBuffsTrackerDB.textScale or 0.32) * 100))

    yOffset = yOffset - 25

    local textSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    textSlider:SetPoint("TOP", 0, yOffset)
    textSlider:SetSize(200, 17)
    textSlider:SetMinMaxValues(20, 60)
    textSlider:SetValueStep(2)
    textSlider:SetObeyStepOnDrag(true)
    textSlider:SetValue((RaidBuffsTrackerDB.textScale or 0.32) * 100)
    textSlider.Low:SetText("20%")
    textSlider.High:SetText("60%")
    textSlider.Text:SetText("")
    textSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        RaidBuffsTrackerDB.textScale = value / 100
        textValue:SetText(value .. "%")
        UpdateVisuals()
    end)
    panel.textSlider = textSlider

    yOffset = yOffset - 40

    -- Lock checkbox (centered)
    local lockCb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    lockCb:SetSize(24, 24)
    lockCb:SetPoint("TOP", -40, yOffset)
    lockCb:SetChecked(RaidBuffsTrackerDB.locked)
    lockCb:SetScript("OnClick", function(self)
        RaidBuffsTrackerDB.locked = self:GetChecked()
    end)
    panel.lockCheckbox = lockCb

    local lockLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lockLabel:SetPoint("LEFT", lockCb, "RIGHT", 2, 0)
    lockLabel:SetText("Lock Position")

    yOffset = yOffset - 30

    -- Show Buff Reminder checkbox
    local reminderCb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    reminderCb:SetSize(24, 24)
    reminderCb:SetPoint("TOP", -55, yOffset)
    reminderCb:SetChecked(RaidBuffsTrackerDB.showBuffReminder ~= false)
    reminderCb:SetScript("OnClick", function(self)
        RaidBuffsTrackerDB.showBuffReminder = self:GetChecked()
        UpdateVisuals()
    end)
    panel.reminderCheckbox = reminderCb

    local reminderLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    reminderLabel:SetPoint("LEFT", reminderCb, "RIGHT", 2, 0)
    reminderLabel:SetText("Show \"BUFF!\" reminder")

    yOffset = yOffset - 45

    -- Buttons row 1 (centered)
    local btnWidth = 135

    -- Reset Position button
    local resetPosBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetPosBtn:SetSize(btnWidth, 24)
    resetPosBtn:SetPoint("TOP", -72, yOffset)
    resetPosBtn:SetText("Reset Position")
    resetPosBtn:SetScript("OnClick", function()
        RaidBuffsTrackerDB.position = {point = "CENTER", x = 0, y = 0}
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end)

    -- Reset Ratios button
    local resetRatiosBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetRatiosBtn:SetSize(btnWidth, 24)
    resetRatiosBtn:SetPoint("LEFT", resetPosBtn, "RIGHT", 10, 0)
    resetRatiosBtn:SetText("Reset Ratios")
    resetRatiosBtn:SetScript("OnClick", function()
        RaidBuffsTrackerDB.spacing = 0.2
        RaidBuffsTrackerDB.textScale = 0.32
        spacingSlider:SetValue(20)
        textSlider:SetValue(32)
        spacingValue:SetText("20%")
        textValue:SetText("32%")
        UpdateVisuals()
    end)
    resetRatiosBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset Ratios")
        GameTooltip:AddLine("Resets spacing and text size to recommended ratios based on icon size for a consistent look.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetRatiosBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    yOffset = yOffset - 30

    -- Buttons row 2 (centered)
    -- Test Mode button
    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(btnWidth, 24)
    testBtn:SetPoint("TOP", 0, yOffset)
    testBtn:SetText("Test")
    panel.testBtn = testBtn
    testBtn:SetScript("OnClick", function()
        if testMode then
            testMode = false
            testBtn:SetText("Test")
            UpdateDisplay()
        else
            testMode = true
            testBtn:SetText("Stop Test")
            local db = RaidBuffsTrackerDB
            local fakeTotal = math.random(10, 20)
            for _, buffData in ipairs(RaidBuffs) do
                local _, key = unpack(buffData)
                local frame = buffFrames[key]
                if frame and db.enabledBuffs[key] then
                    local fakeBuffed = fakeTotal - math.random(1, 5)
                    frame.count:SetText(fakeBuffed .. "/" .. fakeTotal)
                    frame:Show()
                end
            end
            mainFrame:Show()
            PositionBuffFrames()
        end
    end)

    -- Set panel height dynamically based on content
    local panelHeight = math.abs(yOffset) + 40  -- add bottom padding
    panel:SetHeight(panelHeight)

    return panel
end

-- Toggle options panel
local function ToggleOptions()
    if not optionsPanel then
        optionsPanel = CreateOptionsPanel()
    end

    if optionsPanel:IsShown() then
        optionsPanel:Hide()
    else
        -- Refresh values
        local db = RaidBuffsTrackerDB
        for _, buffData in ipairs(RaidBuffs) do
            local key = buffData[2]
            if optionsPanel.buffCheckboxes[key] then
                optionsPanel.buffCheckboxes[key]:SetChecked(db.enabledBuffs[key])
            end
        end
        optionsPanel.sizeSlider:SetValue(db.iconSize)
        optionsPanel.spacingSlider:SetValue((db.spacing or 0.2) * 100)
        optionsPanel.textSlider:SetValue((db.textScale or 0.32) * 100)
        optionsPanel.lockCheckbox:SetChecked(db.locked)
        optionsPanel.reminderCheckbox:SetChecked(db.showBuffReminder ~= false)
        if testMode then
            optionsPanel.testBtn:SetText("Stop Test")
        else
            optionsPanel.testBtn:SetText("Test")
        end
        optionsPanel:Show()
    end
end

-- Slash command handler
local function SlashHandler(msg)
    local cmd = msg:match("^(%S*)") or ""
    cmd = cmd:lower()

    if cmd == "test" then
        -- Quick test toggle from command line
        if testMode then
            testMode = false
            print("|cff00ff00RaidBuffsTracker|r - Test mode OFF")
            UpdateDisplay()
        else
            testMode = true
            print("|cff00ff00RaidBuffsTracker|r - Test mode ON")
            local db = RaidBuffsTrackerDB
            local fakeTotal = math.random(10, 20)
            for _, buffData in ipairs(RaidBuffs) do
                local _, key = unpack(buffData)
                local frame = buffFrames[key]
                if frame and db.enabledBuffs[key] then
                    local fakeBuffed = fakeTotal - math.random(1, 5)
                    frame.count:SetText(fakeBuffed .. "/" .. fakeTotal)
                    frame:Show()
                end
            end
            mainFrame:Show()
            PositionBuffFrames()
        end
    else
        ToggleOptions()
    end
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if not RaidBuffsTrackerDB then
            RaidBuffsTrackerDB = {}
        end
        for k, v in pairs(defaults) do
            if RaidBuffsTrackerDB[k] == nil then
                if type(v) == "table" then
                    RaidBuffsTrackerDB[k] = {}
                    for k2, v2 in pairs(v) do
                        RaidBuffsTrackerDB[k][k2] = v2
                    end
                else
                    RaidBuffsTrackerDB[k] = v
                end
            end
        end
        for _, buffData in ipairs(RaidBuffs) do
            local key = buffData[2]
            if RaidBuffsTrackerDB.enabledBuffs[key] == nil then
                RaidBuffsTrackerDB.enabledBuffs[key] = true
            end
        end

        SLASH_RAIDBUFFSTRACKER1 = "/rbt"
        SLASH_RAIDBUFFSTRACKER2 = "/raidbuffstracker"
        SlashCmdList["RAIDBUFFSTRACKER"] = SlashHandler

        print("|cff00ff00RaidBuffsTracker|r loaded. Type /rbt for options.")

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not mainFrame then
            InitializeFrames()
        end
        inCombat = InCombatLockdown()
        if not inCombat then
            StartUpdates()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        if not inCombat then
            UpdateDisplay()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        StartUpdates()

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        StopUpdates()
        mainFrame:Hide()

    elseif event == "UNIT_AURA" then
        if not inCombat and mainFrame and mainFrame:IsShown() then
            UpdateDisplay()
        end
    end
end)
