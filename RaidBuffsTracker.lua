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
-- {spellID(s), settingKey, displayName, classProvider, beneficiaryRole (optional)}
-- beneficiaryRole can be "HEALER", "TANK", "DAMAGER" to limit who can receive the buff
local ProviderCountBuffs = {
    {369459, "sourceOfMagic", "Source of Magic", "EVOKER", "HEALER"},
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
    iconSize = 64,
    spacing = 0.2,      -- multiplier of iconSize (reset ratios default)
    textScale = 0.32,   -- multiplier of iconSize (reset ratios default)
    showBuffReminder = true,
    showOnlyInGroup = false,
    hideBuffsWithoutProvider = false,
    showOnlyPlayerClassBuff = false,
    filterByClassBenefit = false,
    growDirection = "CENTER", -- "LEFT", "CENTER", "RIGHT"
    showExpirationGlow = true,
    expirationThreshold = 15, -- minutes
    optionsPanelScale = 1.2,  -- base scale (displayed as 100%)
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
-- Returns: hasBuff, remainingTime (nil if no expiration or buff not found)
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
            local remaining = nil
            if auraData.expirationTime and auraData.expirationTime > 0 then
                remaining = auraData.expirationTime - GetTime()
            end
            return true, remaining
        end
    end

    return false, nil
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
    local minRemaining = nil
    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers()
    local db = RaidBuffsTrackerDB
    local beneficiaries = db.filterByClassBenefit and buffKey and BuffBeneficiaries[buffKey] or nil

    if groupSize == 0 then
        -- Solo: check if player benefits
        local _, playerClass = UnitClass("player")
        if beneficiaries and not beneficiaries[playerClass] then
            return 0, 0, nil -- player doesn't benefit, skip
        end
        total = 1
        local hasBuff, remaining = UnitHasBuff("player", spellIDs)
        if not hasBuff then
            missing = 1
        elseif remaining then
            minRemaining = remaining
        end
        return missing, total, minRemaining
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
                local hasBuff, remaining = UnitHasBuff(unit, spellIDs)
                if not hasBuff then
                    missing = missing + 1
                elseif remaining then
                    if not minRemaining or remaining < minRemaining then
                        minRemaining = remaining
                    end
                end
            end
        end
    end

    return missing, total, minRemaining
end

-- Count group members with a presence buff (returns count, minRemaining)
local function CountPresenceBuff(spellIDs)
    local found = 0
    local minRemaining = nil
    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers()

    if groupSize == 0 then
        local hasBuff, remaining = UnitHasBuff("player", spellIDs)
        if hasBuff then
            found = 1
            minRemaining = remaining
        end
        return found, minRemaining
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
            local hasBuff, remaining = UnitHasBuff(unit, spellIDs)
            if hasBuff then
                found = found + 1
                if remaining then
                    if not minRemaining or remaining < minRemaining then
                        minRemaining = remaining
                    end
                end
            end
        end
    end

    return found, minRemaining
end

-- Count buffs vs providers (returns buffCount, targetCount, minRemaining)
-- beneficiaryRole is optional: if provided, targetCount = min(providers, beneficiaries)
-- Also handles self-cast restriction: if only 1 provider who is the only beneficiary, target = 0
local function CountProviderBuff(spellIDs, providerClass, beneficiaryRole)
    local buffCount = 0
    local providerCount = 0
    local beneficiaryCount = 0
    local providerBeneficiaryCount = 0  -- providers who are also beneficiaries
    local minRemaining = nil
    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers()

    if groupSize == 0 then
        local _, playerClass = UnitClass("player")
        local isProvider = (playerClass == providerClass)
        local isBeneficiary = false
        if isProvider then
            providerCount = 1
        end
        if beneficiaryRole then
            local role = UnitGroupRolesAssigned("player")
            if role == beneficiaryRole then
                beneficiaryCount = 1
                isBeneficiary = true
            end
        end
        if isProvider and isBeneficiary then
            providerBeneficiaryCount = 1
        end
        local hasBuff, remaining = UnitHasBuff("player", spellIDs)
        if hasBuff then
            buffCount = 1
            minRemaining = remaining
        end
        local targetCount = beneficiaryRole and math.min(providerCount, beneficiaryCount) or providerCount
        -- Self-cast restriction: if only 1 provider who is the only beneficiary, can't cast on self
        if beneficiaryRole and providerCount == 1 and beneficiaryCount == 1 and providerBeneficiaryCount == 1 then
            targetCount = 0
        end
        return buffCount, targetCount, minRemaining
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
            local isProvider = (unitClass == providerClass)
            local isBeneficiary = false
            if isProvider then
                providerCount = providerCount + 1
            end
            if beneficiaryRole then
                local role = UnitGroupRolesAssigned(unit)
                if role == beneficiaryRole then
                    beneficiaryCount = beneficiaryCount + 1
                    isBeneficiary = true
                end
            end
            if isProvider and isBeneficiary then
                providerBeneficiaryCount = providerBeneficiaryCount + 1
            end
            local hasBuff, remaining = UnitHasBuff(unit, spellIDs)
            if hasBuff then
                buffCount = buffCount + 1
                if remaining then
                    if not minRemaining or remaining < minRemaining then
                        minRemaining = remaining
                    end
                end
            end
        end
    end

    local targetCount = beneficiaryRole and math.min(providerCount, beneficiaryCount) or providerCount
    -- Self-cast restriction: if only 1 provider who is the only beneficiary, can't cast on self
    if beneficiaryRole and providerCount == 1 and beneficiaryCount == 1 and providerBeneficiaryCount == 1 then
        targetCount = 0
    end
    return buffCount, targetCount, minRemaining
end

-- Forward declarations
local UpdateDisplay, PositionBuffFrames, UpdateAnchor

-- Show/hide expiration glow on a buff frame
local function SetExpirationGlow(frame, show)
    if show then
        if not frame.glowShowing then
            ActionButton_ShowOverlayGlow(frame)
            frame.glowShowing = true
        end
    else
        if frame.glowShowing then
            ActionButton_HideOverlayGlow(frame)
            frame.glowShowing = false
        end
    end
end

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
            local missing, total, minRemaining = CountMissingBuff(spellIDs, key)
            local expiringSoon = db.showExpirationGlow and minRemaining and minRemaining < (db.expirationThreshold * 60)
            if missing > 0 then
                local buffed = total - missing
                frame.count:SetText(buffed .. "/" .. total)
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, expiringSoon)
            elseif expiringSoon then
                -- Everyone has buff but expiring soon - show with glow
                frame.count:SetText(total .. "/" .. total)
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, true)
            else
                frame:Hide()
                SetExpirationGlow(frame, false)
            end
        elseif frame then
            frame:Hide()
            SetExpirationGlow(frame, false)
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
            local count, minRemaining = CountPresenceBuff(spellIDs)
            local expiringSoon = db.showExpirationGlow and minRemaining and minRemaining < (db.expirationThreshold * 60)
            if count == 0 then
                -- Nobody has it - show as missing
                frame.count:SetText("")
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, false)
            elseif expiringSoon then
                -- Has buff but expiring soon - show with glow
                frame.count:SetText("")
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, true)
            else
                -- At least 1 person has it and not expiring - all good
                frame:Hide()
                SetExpirationGlow(frame, false)
            end
        elseif frame then
            frame:Hide()
            SetExpirationGlow(frame, false)
        end
    end

    -- Process provider-count buffs (number of buffs should match number of providers)
    for _, buffData in ipairs(ProviderCountBuffs) do
        local spellIDs, key, _, classProvider, beneficiaryRole = unpack(buffData)
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
            local buffCount, targetCount, minRemaining = CountProviderBuff(spellIDs, classProvider, beneficiaryRole)
            local expiringSoon = db.showExpirationGlow and minRemaining and minRemaining < (db.expirationThreshold * 60)
            if targetCount > 0 and buffCount < targetCount then
                -- Not all targets have the buff
                frame.count:SetText(buffCount .. "/" .. targetCount)
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, expiringSoon)
            elseif targetCount > 0 and expiringSoon then
                -- All applied but expiring soon - show with glow
                frame.count:SetText(buffCount .. "/" .. targetCount)
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, true)
            else
                -- All targets have the buff or no valid targets
                frame:Hide()
                SetExpirationGlow(frame, false)
            end
        elseif frame then
            frame:Hide()
            SetExpirationGlow(frame, false)
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
-- OPTIONS PANEL (Two-Column Layout)
-- ============================================================================

local function CreateOptionsPanel()
    local PANEL_WIDTH = 540
    local LEFT_COL_WIDTH = 220
    local RIGHT_COL_WIDTH = 280
    local COL_PADDING = 20
    local SECTION_SPACING = 12
    local ITEM_HEIGHT = 22

    local panel = CreateFrame("Frame", "RaidBuffsTrackerOptions", UIParent, "BackdropTemplate")
    panel:SetWidth(PANEL_WIDTH)
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

    -- Addon icon
    local addonIcon = panel:CreateTexture(nil, "ARTWORK")
    addonIcon:SetSize(28, 28)
    addonIcon:SetPoint("TOPLEFT", 12, -8)
    addonIcon:SetTexture("Interface\\AddOns\\RaidBuffsTracker\\icon.tga")
    addonIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Title (next to icon)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", addonIcon, "RIGHT", 8, 0)
    title:SetText("|cff00ff00RaidBuffsTracker|r")

    -- Scale controls (top right area) - using buttons to avoid slider scaling issues
    -- Base scale is 1.2 (displayed as 100%), range is 80%-150%
    local BASE_SCALE = 1.2
    local MIN_PCT, MAX_PCT = 80, 150
    local scaleDown, scaleUp

    local scaleValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValue:SetPoint("TOPRIGHT", -70, -14)
    local currentScale = RaidBuffsTrackerDB.optionsPanelScale or BASE_SCALE
    local currentPct = math.floor(currentScale / BASE_SCALE * 100 + 0.5)
    scaleValue:SetText(currentPct .. "%")

    local function UpdateScale(delta)
        -- Use integer math to avoid floating point issues
        local oldPct = math.floor((RaidBuffsTrackerDB.optionsPanelScale or BASE_SCALE) / BASE_SCALE * 100 + 0.5)
        local newPct = math.max(MIN_PCT, math.min(MAX_PCT, oldPct + delta))
        local newScale = newPct / 100 * BASE_SCALE
        RaidBuffsTrackerDB.optionsPanelScale = newScale
        panel:SetScale(newScale)
        scaleValue:SetText(newPct .. "%")
        -- Disable buttons at limits
        scaleDown:SetEnabled(newPct > MIN_PCT)
        scaleUp:SetEnabled(newPct < MAX_PCT)
    end

    scaleDown = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scaleDown:SetSize(18, 18)
    scaleDown:SetPoint("RIGHT", scaleValue, "LEFT", -4, 0)
    scaleDown:SetText("-")
    scaleDown:SetScript("OnClick", function() UpdateScale(-10) end)
    scaleDown:SetEnabled(currentPct > MIN_PCT)

    scaleUp = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scaleUp:SetSize(18, 18)
    scaleUp:SetPoint("LEFT", scaleValue, "RIGHT", 4, 0)
    scaleUp:SetText("+")
    scaleUp:SetScript("OnClick", function() UpdateScale(10) end)
    scaleUp:SetEnabled(currentPct < MAX_PCT)

    -- Apply saved scale
    if RaidBuffsTrackerDB.optionsPanelScale then
        panel:SetScale(RaidBuffsTrackerDB.optionsPanelScale)
    end

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)

    -- Column anchors
    local leftColX = COL_PADDING
    local rightColX = LEFT_COL_WIDTH + COL_PADDING * 2
    local startY = -44

    panel.buffCheckboxes = {}

    -- ========== HELPER FUNCTIONS ==========

    -- Create section header
    local function CreateSectionHeader(parent, text, x, y)
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", x, y)
        header:SetText("|cffffcc00" .. text .. "|r")
        return header, y - 18
    end

    -- Create buff checkbox (compact, for left column)
    local function CreateBuffCheckbox(x, y, spellIDs, key, displayName)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetChecked(RaidBuffsTrackerDB.enabledBuffs[key])
        cb:SetScript("OnClick", function(self)
            RaidBuffsTrackerDB.enabledBuffs[key] = self:GetChecked()
            UpdateDisplay()
        end)

        local icon = panel:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local texture = GetBuffTexture(spellIDs)
        if texture then
            icon:SetTexture(texture)
        end

        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        label:SetText(displayName)

        panel.buffCheckboxes[key] = cb
        return y - ITEM_HEIGHT
    end

    -- Create checkbox with label (for right column)
    local function CreateCheckbox(x, y, labelText, checked, onClick)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetChecked(checked)
        cb:SetScript("OnClick", onClick)

        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(labelText)

        return cb, y - ITEM_HEIGHT
    end

    -- Create compact slider with clickable numeric input
    local function CreateSlider(x, y, labelText, minVal, maxVal, step, initVal, suffix, onChange)
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", x, y)
        label:SetWidth(70)
        label:SetJustifyH("LEFT")
        label:SetText(labelText)

        local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
        slider:SetPoint("LEFT", label, "RIGHT", 5, 0)
        slider:SetSize(100, 14)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        slider:SetValue(initVal)
        slider.Low:SetText("")
        slider.High:SetText("")
        slider.Text:SetText("")

        -- Clickable value display
        local valueBtn = CreateFrame("Button", nil, panel)
        valueBtn:SetPoint("LEFT", slider, "RIGHT", 6, 0)
        valueBtn:SetSize(40, 16)

        local value = valueBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetAllPoints()
        value:SetJustifyH("LEFT")
        value:SetText(initVal .. (suffix or ""))

        -- Edit box (hidden by default)
        local editBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        editBox:SetSize(35, 16)
        editBox:SetPoint("LEFT", slider, "RIGHT", 6, 0)
        editBox:SetAutoFocus(false)
        editBox:SetNumeric(true)
        editBox:Hide()

        editBox:SetScript("OnEnterPressed", function(self)
            local num = tonumber(self:GetText())
            if num then
                num = math.max(minVal, math.min(maxVal, num))
                slider:SetValue(num)
            end
            self:Hide()
            valueBtn:Show()
        end)

        editBox:SetScript("OnEscapePressed", function(self)
            self:Hide()
            valueBtn:Show()
        end)

        editBox:SetScript("OnEditFocusLost", function(self)
            self:Hide()
            valueBtn:Show()
        end)

        valueBtn:SetScript("OnClick", function()
            valueBtn:Hide()
            editBox:SetText(tostring(math.floor(slider:GetValue())))
            editBox:Show()
            editBox:SetFocus()
            editBox:HighlightText()
        end)
        valueBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Click to type a value")
            GameTooltip:Show()
        end)
        valueBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        slider:SetScript("OnValueChanged", function(self, val)
            val = math.floor(val)
            value:SetText(val .. (suffix or ""))
            onChange(val)
        end)

        return slider, value, y - 24
    end

    -- ========== LEFT COLUMN: BUFF SELECTION ==========
    local leftY = startY

    -- Tracked Buffs header
    _, leftY = CreateSectionHeader(panel, "Tracked Buffs", leftColX, leftY)

    -- Coverage buffs
    for _, buffData in ipairs(RaidBuffs) do
        local spellIDs, key, displayName = unpack(buffData)
        leftY = CreateBuffCheckbox(leftColX, leftY, spellIDs, key, displayName)
    end

    leftY = leftY - SECTION_SPACING

    -- Presence Buffs header
    _, leftY = CreateSectionHeader(panel, "Presence Buffs", leftColX, leftY)
    local presenceNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    presenceNote:SetPoint("TOPLEFT", leftColX, leftY)
    presenceNote:SetText("(need at least 1)")
    leftY = leftY - 14

    for _, buffData in ipairs(PresenceBuffs) do
        local spellIDs, key, displayName = unpack(buffData)
        leftY = CreateBuffCheckbox(leftColX, leftY, spellIDs, key, displayName)
    end

    leftY = leftY - SECTION_SPACING

    -- Provider Buffs header
    _, leftY = CreateSectionHeader(panel, "Provider Buffs", leftColX, leftY)
    local providerNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    providerNote:SetPoint("TOPLEFT", leftColX, leftY)
    providerNote:SetText("(1 per provider)")
    leftY = leftY - 14

    for _, buffData in ipairs(ProviderCountBuffs) do
        local spellIDs, key, displayName = unpack(buffData)
        leftY = CreateBuffCheckbox(leftColX, leftY, spellIDs, key, displayName)
    end

    -- ========== RIGHT COLUMN: SETTINGS ==========
    local rightY = startY

    -- Appearance header
    _, rightY = CreateSectionHeader(panel, "Appearance", rightColX, rightY)

    local sizeSlider, sizeValue
    sizeSlider, sizeValue, rightY = CreateSlider(rightColX, rightY, "Icon Size", 16, 128, 1, RaidBuffsTrackerDB.iconSize, "", function(val)
        RaidBuffsTrackerDB.iconSize = val
        UpdateVisuals()
    end)
    panel.sizeSlider = sizeSlider
    panel.sizeValue = sizeValue

    local spacingSlider, spacingValue
    spacingSlider, spacingValue, rightY = CreateSlider(rightColX, rightY, "Spacing", 0, 50, 1, math.floor((RaidBuffsTrackerDB.spacing or 0.2) * 100), "%", function(val)
        RaidBuffsTrackerDB.spacing = val / 100
        if testMode then
            PositionBuffFrames()
        else
            UpdateDisplay()
        end
    end)
    panel.spacingSlider = spacingSlider
    panel.spacingValue = spacingValue

    local textSlider, textValue
    textSlider, textValue, rightY = CreateSlider(rightColX, rightY, "Text Size", 20, 60, 1, math.floor((RaidBuffsTrackerDB.textScale or 0.32) * 100), "%", function(val)
        RaidBuffsTrackerDB.textScale = val / 100
        UpdateVisuals()
        if testMode then
            PositionBuffFrames()
        end
    end)
    panel.textSlider = textSlider
    panel.textValue = textValue

    rightY = rightY - 4

    -- Grow direction
    local growLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    growLabel:SetPoint("TOPLEFT", rightColX, rightY)
    growLabel:SetText("Grow:")

    local growBtns = {}
    local directions = {"LEFT", "CENTER", "RIGHT"}
    local dirLabels = {"Left", "Center", "Right"}
    local growBtnWidth = 70

    for i, dir in ipairs(directions) do
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(growBtnWidth, 18)
        btn:SetPoint("LEFT", growLabel, "RIGHT", 5 + (i-1) * (growBtnWidth + 3), 0)
        btn:SetText(dirLabels[i])
        btn:SetNormalFontObject("GameFontHighlightSmall")
        btn:SetHighlightFontObject("GameFontHighlightSmall")
        btn:SetDisabledFontObject("GameFontDisableSmall")
        btn.direction = dir
        btn:SetScript("OnClick", function()
            RaidBuffsTrackerDB.growDirection = dir
            for _, b in ipairs(growBtns) do
                b:SetEnabled(b.direction ~= dir)
            end
            UpdateDisplay()
        end)
        btn:SetEnabled(RaidBuffsTrackerDB.growDirection ~= dir)
        growBtns[i] = btn
    end
    panel.growBtns = growBtns

    rightY = rightY - 26

    -- Separator
    local sep1 = panel:CreateTexture(nil, "ARTWORK")
    sep1:SetSize(RIGHT_COL_WIDTH - 20, 1)
    sep1:SetPoint("TOPLEFT", rightColX, rightY)
    sep1:SetColorTexture(0.4, 0.4, 0.4, 1)
    rightY = rightY - SECTION_SPACING

    -- Behavior header
    _, rightY = CreateSectionHeader(panel, "Behavior", rightColX, rightY)

    local lockCb
    lockCb, rightY = CreateCheckbox(rightColX, rightY, "Lock Position", RaidBuffsTrackerDB.locked, function(self)
        RaidBuffsTrackerDB.locked = self:GetChecked()
        UpdateAnchor()
    end)
    panel.lockCheckbox = lockCb

    local reminderCb
    reminderCb, rightY = CreateCheckbox(rightColX, rightY, "Show \"BUFF!\" reminder", RaidBuffsTrackerDB.showBuffReminder ~= false, function(self)
        RaidBuffsTrackerDB.showBuffReminder = self:GetChecked()
        UpdateVisuals()
    end)
    panel.reminderCheckbox = reminderCb

    local groupCb
    groupCb, rightY = CreateCheckbox(rightColX, rightY, "Show only in group/raid", RaidBuffsTrackerDB.showOnlyInGroup ~= false, function(self)
        RaidBuffsTrackerDB.showOnlyInGroup = self:GetChecked()
        UpdateDisplay()
    end)
    panel.groupCheckbox = groupCb

    local providerCb
    providerCb, rightY = CreateCheckbox(rightColX, rightY, "Hide buffs for missing classes", RaidBuffsTrackerDB.hideBuffsWithoutProvider, function(self)
        RaidBuffsTrackerDB.hideBuffsWithoutProvider = self:GetChecked()
        UpdateDisplay()
    end)
    panel.providerCheckbox = providerCb

    local playerClassCb
    playerClassCb, rightY = CreateCheckbox(rightColX, rightY, "Show only my class buff", RaidBuffsTrackerDB.showOnlyPlayerClassBuff, function(self)
        RaidBuffsTrackerDB.showOnlyPlayerClassBuff = self:GetChecked()
        UpdateDisplay()
    end)
    panel.playerClassCheckbox = playerClassCb

    local classBenefitCb
    classBenefitCb, rightY = CreateCheckbox(rightColX, rightY, "Only count benefiting classes |cffff8000(BETA)|r", RaidBuffsTrackerDB.filterByClassBenefit, function(self)
        RaidBuffsTrackerDB.filterByClassBenefit = self:GetChecked()
        UpdateDisplay()
    end)
    panel.classBenefitCheckbox = classBenefitCb

    -- Separator
    local sep2 = panel:CreateTexture(nil, "ARTWORK")
    sep2:SetSize(RIGHT_COL_WIDTH - 20, 1)
    sep2:SetPoint("TOPLEFT", rightColX, rightY - 4)
    sep2:SetColorTexture(0.4, 0.4, 0.4, 1)
    rightY = rightY - SECTION_SPACING - 4

    -- Expiration Warning header
    _, rightY = CreateSectionHeader(panel, "Expiration Warning", rightColX, rightY)

    local glowCb
    glowCb, rightY = CreateCheckbox(rightColX, rightY, "Show glow when expiring", RaidBuffsTrackerDB.showExpirationGlow, function(self)
        RaidBuffsTrackerDB.showExpirationGlow = self:GetChecked()
        UpdateDisplay()
    end)
    panel.glowCheckbox = glowCb

    local thresholdSlider, thresholdValue
    thresholdSlider, thresholdValue, rightY = CreateSlider(rightColX, rightY, "Threshold", 1, 15, 1, RaidBuffsTrackerDB.expirationThreshold or 5, " min", function(val)
        RaidBuffsTrackerDB.expirationThreshold = val
        UpdateDisplay()
    end)
    panel.thresholdSlider = thresholdSlider
    panel.thresholdValue = thresholdValue

    -- ========== BOTTOM BUTTONS (spanning both columns) ==========
    local bottomY = math.min(leftY, rightY) - 20

    -- Separator line
    local separator = panel:CreateTexture(nil, "ARTWORK")
    separator:SetSize(PANEL_WIDTH - 40, 1)
    separator:SetPoint("TOP", 0, bottomY)
    separator:SetColorTexture(0.5, 0.5, 0.5, 1)
    bottomY = bottomY - 15

    -- Button row
    local btnWidth = 100
    local btnSpacing = 10
    local totalBtnWidth = btnWidth * 3 + btnSpacing * 2

    local resetPosBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetPosBtn:SetSize(btnWidth, 22)
    resetPosBtn:SetPoint("TOP", -totalBtnWidth/2 + btnWidth/2, bottomY)
    resetPosBtn:SetText("Reset Pos")
    resetPosBtn:SetScript("OnClick", function()
        RaidBuffsTrackerDB.position = {point = "CENTER", x = 0, y = 0}
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end)
    resetPosBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset Position")
        GameTooltip:AddLine("Moves the buff tracker back to the center of the screen.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetPosBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local resetRatiosBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetRatiosBtn:SetSize(btnWidth, 22)
    resetRatiosBtn:SetPoint("LEFT", resetPosBtn, "RIGHT", btnSpacing, 0)
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
        GameTooltip:AddLine("Resets spacing and text size to recommended ratios.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetRatiosBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(btnWidth, 22)
    testBtn:SetPoint("LEFT", resetRatiosBtn, "RIGHT", btnSpacing, 0)
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

    bottomY = bottomY - 30

    -- Set panel height
    panel:SetHeight(math.abs(bottomY) + 15)

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
        if optionsPanel.glowCheckbox then
            optionsPanel.glowCheckbox:SetChecked(db.showExpirationGlow)
        end
        if optionsPanel.thresholdSlider then
            optionsPanel.thresholdSlider:SetValue(db.expirationThreshold or 5)
            optionsPanel.thresholdValue:SetText((db.expirationThreshold or 5) .. " min")
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

        -- Register with WoW's Interface Options
        local settingsPanel = CreateFrame("Frame")
        settingsPanel.name = "RaidBuffsTracker"

        local title = settingsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("|cff00ff00RaidBuffsTracker|r")

        local desc = settingsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        desc:SetText("Track missing raid buffs at a glance.")

        local openBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
        openBtn:SetSize(150, 24)
        openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
        openBtn:SetText("Open Options")
        openBtn:SetScript("OnClick", function()
            ToggleOptions()
            -- Close the WoW settings panel
            if SettingsPanel then
                SettingsPanel:Hide()
            end
        end)

        local slashInfo = settingsPanel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        slashInfo:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -12)
        slashInfo:SetText("Slash commands: /rbt or /raidbuffstracker")

        local category = Settings.RegisterCanvasLayoutCategory(settingsPanel, settingsPanel.name)
        Settings.RegisterAddOnCategory(category)

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
