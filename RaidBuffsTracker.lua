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

-- Presence-based buffs: only need at least 1 person to have it active
-- {spellID(s), settingKey, displayName, classProvider}
local PresenceBuffs = {
    {465, "devotionAura", "Devotion Aura", "PALADIN"},
    {381637, "atrophicPoison", "Atrophic Poison", "ROGUE"},
}

-- Provider-count buffs: number of buffs should match number of providers
-- {spellID(s), settingKey, displayName, classProvider}
local ProviderCountBuffs = {
    {369459, "sourceOfMagic", "Source of Magic", "EVOKER"},
}

-- Classes that benefit from each buff (BETA: class-level only, not spec-aware)
-- nil = everyone benefits, otherwise only listed classes are counted
local BuffBeneficiaries = {
    intellect = {
        MAGE=true, WARLOCK=true, PRIEST=true, DRUID=true,
        SHAMAN=true, MONK=true, EVOKER=true, PALADIN=true, DEMONHUNTER=true
    },
    attackPower = {
        WARRIOR=true, ROGUE=true, HUNTER=true, DEATHKNIGHT=true,
        PALADIN=true, MONK=true, DRUID=true, DEMONHUNTER=true, SHAMAN=true
    },
    -- stamina, versatility, skyfury, bronze = everyone benefits (nil)
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
        devotionAura = true,
        atrophicPoison = true,
        sourceOfMagic = true,
    },
    iconSize = 32,
    spacing = 0.2,      -- multiplier of iconSize
    textScale = 0.32,   -- multiplier of iconSize
    showBuffReminder = true,
    showOnlyInGroup = true,
    hideBuffsWithoutProvider = false,
    showOnlyPlayerClassBuff = false,
    filterByClassBenefit = false,
    growDirection = "CENTER", -- "LEFT", "CENTER", "RIGHT"
}

-- Locals
local mainFrame
local buffFrames = {}
local updateTicker
local inCombat = false
local testMode = false
local optionsPanel

-- Get classes present in the group
local function GetGroupClasses()
    local classes = {}
    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers()

    if groupSize == 0 then
        local _, class = UnitClass("player")
        if class then classes[class] = true end
        return classes
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

        if UnitExists(unit) and UnitIsConnected(unit) then
            local _, class = UnitClass(unit)
            if class then classes[class] = true end
        end
    end
    return classes
end

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
-- buffKey is optional, used for class benefit filtering
local function CountMissingBuff(spellIDs, buffKey)
    local missing = 0
    local total = 0
    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers()
    local db = RaidBuffsTrackerDB
    local beneficiaries = db.filterByClassBenefit and buffKey and BuffBeneficiaries[buffKey] or nil

    if groupSize == 0 then
        -- Solo: check if player benefits
        local _, playerClass = UnitClass("player")
        if beneficiaries and not beneficiaries[playerClass] then
            return 0, 0 -- player doesn't benefit, skip
        end
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
            -- Check if unit's class benefits from this buff
            local _, unitClass = UnitClass(unit)
            if not beneficiaries or beneficiaries[unitClass] then
                total = total + 1
                if not UnitHasBuff(unit, spellIDs) then
                    missing = missing + 1
                end
            end
        end
    end

    return missing, total
end

-- Count group members with a presence buff (returns count of players with buff)
local function CountPresenceBuff(spellIDs)
    local found = 0
    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers()

    if groupSize == 0 then
        if UnitHasBuff("player", spellIDs) then
            found = 1
        end
        return found
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
            if UnitHasBuff(unit, spellIDs) then
                found = found + 1
            end
        end
    end

    return found
end

-- Count buffs vs providers (returns buffCount, providerCount)
local function CountProviderBuff(spellIDs, providerClass)
    local buffCount = 0
    local providerCount = 0
    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers()

    if groupSize == 0 then
        local _, playerClass = UnitClass("player")
        if playerClass == providerClass then
            providerCount = 1
        end
        if UnitHasBuff("player", spellIDs) then
            buffCount = 1
        end
        return buffCount, providerCount
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
            local _, unitClass = UnitClass(unit)
            if unitClass == providerClass then
                providerCount = providerCount + 1
            end
            if UnitHasBuff(unit, spellIDs) then
                buffCount = buffCount + 1
            end
        end
    end

    return buffCount, providerCount
end

-- Forward declarations
local UpdateDisplay, PositionBuffFrames, UpdateAnchor

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
    local direction = db.growDirection or "CENTER"

    local visibleFrames = {}
    for _, frame in pairs(buffFrames) do
        if frame:IsShown() then
            table.insert(visibleFrames, frame)
        end
    end

    local count = #visibleFrames
    if count == 0 then return end

    for i, frame in ipairs(visibleFrames) do
        frame:ClearAllPoints()
        if direction == "LEFT" then
            -- Grow right from left anchor
            frame:SetPoint("LEFT", mainFrame, "LEFT", (i - 1) * (iconSize + spacing), 0)
        elseif direction == "RIGHT" then
            -- Grow left from right anchor
            frame:SetPoint("RIGHT", mainFrame, "RIGHT", -((i - 1) * (iconSize + spacing)), 0)
        else -- CENTER
            local totalWidth = count * iconSize + (count - 1) * spacing
            local startX = -totalWidth / 2 + iconSize / 2
            frame:SetPoint("CENTER", mainFrame, "CENTER", startX + (i - 1) * (iconSize + spacing), 0)
        end
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

    -- Hide if not in group and setting is enabled
    if db.showOnlyInGroup and GetNumGroupMembers() == 0 then
        mainFrame:Hide()
        return
    end

    local presentClasses = nil
    if db.hideBuffsWithoutProvider then
        presentClasses = GetGroupClasses()
    end

    local _, playerClass = UnitClass("player")

    local anyVisible = false

    -- Process coverage buffs (need everyone to have them)
    for _, buffData in ipairs(RaidBuffs) do
        local spellIDs, key, _, classProvider = unpack(buffData)
        local frame = buffFrames[key]

        local showBuff = true
        -- Filter: only show player's class buff
        if db.showOnlyPlayerClassBuff and classProvider ~= playerClass then
            showBuff = false
        end
        -- Filter: hide buffs without provider in group
        if showBuff and presentClasses and not presentClasses[classProvider] then
            showBuff = false
        end

        if frame and db.enabledBuffs[key] and showBuff then
            local missing, total = CountMissingBuff(spellIDs, key)
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

    -- Process presence buffs (need at least 1 person to have them)
    for _, buffData in ipairs(PresenceBuffs) do
        local spellIDs, key, _, classProvider = unpack(buffData)
        local frame = buffFrames[key]

        local showBuff = true
        -- Filter: only show player's class buff
        if db.showOnlyPlayerClassBuff and classProvider ~= playerClass then
            showBuff = false
        end
        -- Filter: hide buffs without provider in group
        if showBuff and presentClasses and not presentClasses[classProvider] then
            showBuff = false
        end

        if frame and db.enabledBuffs[key] and showBuff then
            local count = CountPresenceBuff(spellIDs)
            if count == 0 then
                -- Nobody has it - show as missing
                frame.count:SetText("")
                frame:Show()
                anyVisible = true
            else
                -- At least 1 person has it - all good
                frame:Hide()
            end
        elseif frame then
            frame:Hide()
        end
    end

    -- Process provider-count buffs (number of buffs should match number of providers)
    for _, buffData in ipairs(ProviderCountBuffs) do
        local spellIDs, key, _, classProvider = unpack(buffData)
        local frame = buffFrames[key]

        local showBuff = true
        -- Filter: only show player's class buff
        if db.showOnlyPlayerClassBuff and classProvider ~= playerClass then
            showBuff = false
        end
        -- Filter: hide buffs without provider in group
        if showBuff and presentClasses and not presentClasses[classProvider] then
            showBuff = false
        end

        if frame and db.enabledBuffs[key] and showBuff then
            local buffCount, providerCount = CountProviderBuff(spellIDs, classProvider)
            if buffCount < providerCount then
                -- Not all providers have applied their buff
                frame.count:SetText(buffCount .. "/" .. providerCount)
                frame:Show()
                anyVisible = true
            else
                -- All providers have applied their buff
                frame:Hide()
            end
        elseif frame then
            frame:Hide()
        end
    end

    if anyVisible then
        mainFrame:Show()
        PositionBuffFrames()
        UpdateAnchor()
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

    -- Anchor indicator (shown when unlocked) - use separate frame to draw on top
    mainFrame.anchorFrame = CreateFrame("Frame", nil, mainFrame)
    mainFrame.anchorFrame:SetSize(65, 26)
    mainFrame.anchorFrame:SetFrameLevel(mainFrame:GetFrameLevel() + 100)
    mainFrame.anchor = mainFrame.anchorFrame:CreateTexture(nil, "BACKGROUND")
    mainFrame.anchor:SetAllPoints()
    mainFrame.anchor:SetColorTexture(0, 0.8, 0, 0.9)
    mainFrame.anchorText = mainFrame.anchorFrame:CreateFontString(nil, "OVERLAY")
    mainFrame.anchorText:SetPoint("CENTER", 0, 0)
    mainFrame.anchorText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    mainFrame.anchorText:SetTextColor(1, 1, 1, 1)
    mainFrame.anchorText:SetText("ANCHOR")
    mainFrame.anchorFrame:Hide()

    for i, buffData in ipairs(RaidBuffs) do
        local key = buffData[2]
        buffFrames[key] = CreateBuffFrame(buffData, i)
    end

    for i, buffData in ipairs(PresenceBuffs) do
        local key = buffData[2]
        buffFrames[key] = CreateBuffFrame(buffData, #RaidBuffs + i)
        buffFrames[key].isPresenceBuff = true
    end

    for i, buffData in ipairs(ProviderCountBuffs) do
        local key = buffData[2]
        buffFrames[key] = CreateBuffFrame(buffData, #RaidBuffs + #PresenceBuffs + i)
        buffFrames[key].isProviderCountBuff = true
    end

    mainFrame:Hide()
end

-- Update anchor position and visibility
UpdateAnchor = function()
    if not mainFrame or not mainFrame.anchorFrame then return end
    local db = RaidBuffsTrackerDB
    local direction = db.growDirection or "CENTER"

    mainFrame.anchorFrame:ClearAllPoints()
    if direction == "LEFT" then
        mainFrame.anchorFrame:SetPoint("LEFT", mainFrame, "LEFT", 0, 0)
    elseif direction == "RIGHT" then
        mainFrame.anchorFrame:SetPoint("RIGHT", mainFrame, "RIGHT", 0, 0)
    else -- CENTER
        mainFrame.anchorFrame:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
    end

    if not db.locked and mainFrame:IsShown() then
        mainFrame.anchorFrame:Show()
    else
        mainFrame.anchorFrame:Hide()
    end
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
    buffLabel:SetPoint("TOP", 0, yOffset)
    buffLabel:SetText("Tracked Buffs:")
    yOffset = yOffset - 22

    panel.buffCheckboxes = {}
    local buffStartX = 30  -- Fixed left margin for alignment

    -- Helper to create buff checkbox row
    local function CreateBuffCheckbox(spellIDs, key, displayName, classProvider, suffix)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", buffStartX, yOffset)
        cb:SetChecked(RaidBuffsTrackerDB.enabledBuffs[key])
        cb:SetScript("OnClick", function(self)
            RaidBuffsTrackerDB.enabledBuffs[key] = self:GetChecked()
            UpdateDisplay()
        end)

        local icon = panel:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local texture = GetBuffTexture(spellIDs)
        if texture then
            icon:SetTexture(texture)
        end

        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        label:SetText(displayName .. " |cff888888(" .. classProvider .. ")|r" .. (suffix or ""))

        panel.buffCheckboxes[key] = cb
        yOffset = yOffset - 24
    end

    -- Coverage buffs
    for _, buffData in ipairs(RaidBuffs) do
        local spellIDs, key, displayName, classProvider = unpack(buffData)
        CreateBuffCheckbox(spellIDs, key, displayName, classProvider)
    end

    yOffset = yOffset - 10

    -- Presence buffs section
    local presenceLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    presenceLabel:SetPoint("TOP", 0, yOffset)
    presenceLabel:SetText("Presence Buffs |cff888888(need at least 1)|r:")
    yOffset = yOffset - 22

    for _, buffData in ipairs(PresenceBuffs) do
        local spellIDs, key, displayName, classProvider = unpack(buffData)
        CreateBuffCheckbox(spellIDs, key, displayName, classProvider)
    end

    yOffset = yOffset - 10

    -- Provider-count buffs section
    local providerCountLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    providerCountLabel:SetPoint("TOP", 0, yOffset)
    providerCountLabel:SetText("Provider Buffs |cff888888(1 per provider)|r:")
    yOffset = yOffset - 22

    for _, buffData in ipairs(ProviderCountBuffs) do
        local spellIDs, key, displayName, classProvider = unpack(buffData)
        CreateBuffCheckbox(spellIDs, key, displayName, classProvider)
    end

    yOffset = yOffset - 20

    -- Helper for inline sliders: Label [slider] value
    local function CreateInlineSlider(yPos, labelText, minVal, maxVal, step, initVal, valueSuffix, onChange)
        local labelWidth = 65
        local sliderWidth = 140
        local valueWidth = 40

        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", 25, yPos)
        label:SetWidth(labelWidth)
        label:SetJustifyH("RIGHT")
        label:SetText(labelText)

        local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
        slider:SetPoint("LEFT", label, "RIGHT", 10, 0)
        slider:SetSize(sliderWidth, 17)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        slider:SetValue(initVal)
        slider.Low:SetText("")
        slider.High:SetText("")
        slider.Text:SetText("")

        local value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetPoint("LEFT", slider, "RIGHT", 10, 0)
        value:SetWidth(valueWidth)
        value:SetJustifyH("LEFT")
        value:SetText(initVal .. (valueSuffix or ""))

        slider:SetScript("OnValueChanged", function(self, val)
            val = math.floor(val)
            value:SetText(val .. (valueSuffix or ""))
            onChange(val)
        end)

        return slider, value
    end

    -- Icon Size slider
    local sizeSlider, sizeValue = CreateInlineSlider(yOffset, "Icon Size:", 16, 128, 2, RaidBuffsTrackerDB.iconSize, "", function(val)
        RaidBuffsTrackerDB.iconSize = val
        UpdateVisuals()
    end)
    panel.sizeSlider = sizeSlider
    panel.sizeValue = sizeValue

    yOffset = yOffset - 28

    -- Spacing slider
    local spacingSlider, spacingValue = CreateInlineSlider(yOffset, "Spacing:", 0, 50, 5, math.floor((RaidBuffsTrackerDB.spacing or 0.2) * 100), "%", function(val)
        RaidBuffsTrackerDB.spacing = val / 100
        UpdateDisplay()
    end)
    panel.spacingSlider = spacingSlider
    panel.spacingValue = spacingValue

    yOffset = yOffset - 28

    -- Text Size slider
    local textSlider, textValue = CreateInlineSlider(yOffset, "Text Size:", 20, 60, 2, math.floor((RaidBuffsTrackerDB.textScale or 0.32) * 100), "%", function(val)
        RaidBuffsTrackerDB.textScale = val / 100
        UpdateVisuals()
    end)
    panel.textSlider = textSlider
    panel.textValue = textValue

    yOffset = yOffset - 30

    -- Helper to create centered checkbox with label
    local function CreateCenteredCheckbox(labelText, yPos, checked, onClick)
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(280, 24)
        row:SetPoint("TOP", 0, yPos)

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetChecked(checked)
        cb:SetScript("OnClick", onClick)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        label:SetText(labelText)

        -- Center the checkbox + label within the row
        local totalWidth = 24 + 2 + label:GetStringWidth()
        cb:SetPoint("LEFT", row, "CENTER", -totalWidth / 2, 0)

        return cb
    end

    -- Lock checkbox
    local lockCb = CreateCenteredCheckbox("Lock Position", yOffset, RaidBuffsTrackerDB.locked, function(self)
        RaidBuffsTrackerDB.locked = self:GetChecked()
        UpdateAnchor()
    end)
    panel.lockCheckbox = lockCb

    yOffset = yOffset - 30

    -- Show Buff Reminder checkbox
    local reminderCb = CreateCenteredCheckbox("Show \"BUFF!\" reminder", yOffset, RaidBuffsTrackerDB.showBuffReminder ~= false, function(self)
        RaidBuffsTrackerDB.showBuffReminder = self:GetChecked()
        UpdateVisuals()
    end)
    panel.reminderCheckbox = reminderCb

    yOffset = yOffset - 30

    -- Show only in group checkbox
    local groupCb = CreateCenteredCheckbox("Show only in group/raid", yOffset, RaidBuffsTrackerDB.showOnlyInGroup ~= false, function(self)
        RaidBuffsTrackerDB.showOnlyInGroup = self:GetChecked()
        UpdateDisplay()
    end)
    panel.groupCheckbox = groupCb

    yOffset = yOffset - 30

    -- Hide if provider missing checkbox
    local providerCb = CreateCenteredCheckbox("Hide buffs for missing classes", yOffset, RaidBuffsTrackerDB.hideBuffsWithoutProvider, function(self)
        RaidBuffsTrackerDB.hideBuffsWithoutProvider = self:GetChecked()
        UpdateDisplay()
    end)
    panel.providerCheckbox = providerCb

    yOffset = yOffset - 30

    -- Show only player class buff checkbox
    local playerClassCb = CreateCenteredCheckbox("Show only my class buff", yOffset, RaidBuffsTrackerDB.showOnlyPlayerClassBuff, function(self)
        RaidBuffsTrackerDB.showOnlyPlayerClassBuff = self:GetChecked()
        UpdateDisplay()
    end)
    panel.playerClassCheckbox = playerClassCb

    yOffset = yOffset - 30

    -- Filter by class benefit checkbox (BETA)
    local classBenefitCb = CreateCenteredCheckbox("Only count benefiting classes |cffff8000(BETA)|r", yOffset, RaidBuffsTrackerDB.filterByClassBenefit, function(self)
        RaidBuffsTrackerDB.filterByClassBenefit = self:GetChecked()
        UpdateDisplay()
    end)
    panel.classBenefitCheckbox = classBenefitCb

    yOffset = yOffset - 35

    -- Grow direction label
    local growLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    growLabel:SetPoint("TOP", 0, yOffset)
    growLabel:SetText("Grow Direction:")

    yOffset = yOffset - 25

    -- Grow direction buttons
    local growBtnWidth = 80
    local growBtnSpacing = 10
    local totalGrowWidth = (growBtnWidth * 3) + (growBtnSpacing * 2)

    local growBtns = {}
    local directions = {"LEFT", "CENTER", "RIGHT"}
    local dirLabels = {"Left", "Center", "Right"}

    for i, dir in ipairs(directions) do
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(growBtnWidth, 22)
        btn:SetPoint("TOP", -totalGrowWidth/2 + growBtnWidth/2 + (i-1) * (growBtnWidth + growBtnSpacing), yOffset)
        btn:SetText(dirLabels[i])
        btn.direction = dir
        btn:SetScript("OnClick", function()
            RaidBuffsTrackerDB.growDirection = dir
            for _, b in ipairs(growBtns) do
                if b.direction == dir then
                    b:SetEnabled(false)
                else
                    b:SetEnabled(true)
                end
            end
            UpdateDisplay()
        end)
        if RaidBuffsTrackerDB.growDirection == dir then
            btn:SetEnabled(false)
        end
        growBtns[i] = btn
    end
    panel.growBtns = growBtns

    yOffset = yOffset - 35  -- 22px button height + 13px padding

    -- Separator line
    local separator = panel:CreateTexture(nil, "ARTWORK")
    separator:SetSize(260, 1)
    separator:SetPoint("TOP", 0, yOffset)
    separator:SetColorTexture(0.5, 0.5, 0.5, 1)

    yOffset = yOffset - 15

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
        panel.spacingSlider:SetValue(20)
        panel.textSlider:SetValue(32)
        panel.spacingValue:SetText("20%")
        panel.textValue:SetText("32%")
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
            for _, buffData in ipairs(PresenceBuffs) do
                local _, key = unpack(buffData)
                local frame = buffFrames[key]
                if frame and db.enabledBuffs[key] then
                    frame.count:SetText("")
                    frame:Show()
                end
            end
            for _, buffData in ipairs(ProviderCountBuffs) do
                local _, key = unpack(buffData)
                local frame = buffFrames[key]
                if frame and db.enabledBuffs[key] then
                    local fakeProviders = math.random(1, 3)
                    local fakeBuffed = math.random(0, fakeProviders - 1)
                    frame.count:SetText(fakeBuffed .. "/" .. fakeProviders)
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
        for _, buffData in ipairs(PresenceBuffs) do
            local key = buffData[2]
            if optionsPanel.buffCheckboxes[key] then
                optionsPanel.buffCheckboxes[key]:SetChecked(db.enabledBuffs[key])
            end
        end
        for _, buffData in ipairs(ProviderCountBuffs) do
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
        optionsPanel.groupCheckbox:SetChecked(db.showOnlyInGroup ~= false)
        if optionsPanel.providerCheckbox then
            optionsPanel.providerCheckbox:SetChecked(db.hideBuffsWithoutProvider)
        end
        if optionsPanel.playerClassCheckbox then
            optionsPanel.playerClassCheckbox:SetChecked(db.showOnlyPlayerClassBuff)
        end
        if optionsPanel.classBenefitCheckbox then
            optionsPanel.classBenefitCheckbox:SetChecked(db.filterByClassBenefit)
        end
        for _, btn in ipairs(optionsPanel.growBtns) do
            btn:SetEnabled(btn.direction ~= db.growDirection)
        end
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
            for _, buffData in ipairs(PresenceBuffs) do
                local _, key = unpack(buffData)
                local frame = buffFrames[key]
                if frame and db.enabledBuffs[key] then
                    frame.count:SetText("")
                    frame:Show()
                end
            end
            for _, buffData in ipairs(ProviderCountBuffs) do
                local _, key = unpack(buffData)
                local frame = buffFrames[key]
                if frame and db.enabledBuffs[key] then
                    local fakeProviders = math.random(1, 3)
                    local fakeBuffed = math.random(0, fakeProviders - 1)
                    frame.count:SetText(fakeBuffed .. "/" .. fakeProviders)
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
        for _, buffData in ipairs(PresenceBuffs) do
            local key = buffData[2]
            if RaidBuffsTrackerDB.enabledBuffs[key] == nil then
                RaidBuffsTrackerDB.enabledBuffs[key] = true
            end
        end
        for _, buffData in ipairs(ProviderCountBuffs) do
            local key = buffData[2]
            if RaidBuffsTrackerDB.enabledBuffs[key] == nil then
                RaidBuffsTrackerDB.enabledBuffs[key] = true
            end
        end

        SLASH_RAIDBUFFSTRACKER1 = "/rbt"
        SLASH_RAIDBUFFSTRACKER2 = "/raidbuffstracker"
        SlashCmdList["RAIDBUFFSTRACKER"] = SlashHandler

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
