local addonName, _ = ...

-- Buff definitions: {spellID(s), settingKey, displayName, classProvider}
local RaidBuffs = {
    { 1459, "intellect", "Arcane Intellect", "MAGE" },
    { 6673, "attackPower", "Battle Shout", "WARRIOR" },
    {
        { 381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758 },
        "bronze",
        "Blessing of the Bronze",
        "EVOKER",
    },
    { 1126, "versatility", "Mark of the Wild", "DRUID" },
    { 21562, "stamina", "Power Word: Fortitude", "PRIEST" },
    { 462854, "skyfury", "Skyfury", "SHAMAN" },
}

-- Presence-based buffs: only need at least 1 person to have it active
-- {spellID(s), settingKey, displayName, classProvider, missingText, readyCheckOnly}
local PresenceBuffs = {
    { 381637, "atrophicPoison", "Atrophic Poison", "ROGUE", "NO\nPOISON", false },
    { 465, "devotionAura", "Devotion Aura", "PALADIN", "NO\nAURA", false },
    { 20707, "soulstone", "Soulstone", "WARLOCK", "NO\nSTONE", true },
}

-- Personal buffs: only tracks if the player should cast their buff on others
-- {spellID, settingKey, displayName, requiredClass, beneficiaryRole, missingText, groupId}
-- Only shows if player is the required class, has the spell talented, and a beneficiary needs it
-- groupId is optional - buffs with same groupId share a single setting and show one icon
local PersonalBuffs = {
    { 156910, "beaconOfFaith", "Beacon of Faith", "PALADIN", nil, "NO\nFAITH", "beacons" },
    { 53563, "beaconOfLight", "Beacon of Light", "PALADIN", nil, "NO\nLIGHT", "beacons" },
    { 369459, "sourceOfMagic", "Source of Magic", "EVOKER", "HEALER", "NO\nSOURCE", nil },
    { 474750, "symbioticRelationship", "Symbiotic Relationship", "DRUID", nil, "NO\nLINK", nil },
}

-- Self buffs: buffs the player casts on themselves
-- {spellID, settingKey, displayName, requiredClass, missingText}
-- Only shows if player is the required class and has the spell (spec is inferred from spell knowledge)
local SelfBuffs = {
    -- Shadowform will drop during Void Form, but that only happens in combat. We're happy enough just checking Shadowform before going into combat.
    { 232698, "shadowform", "Shadowform", "PRIEST", "NO\nFORM" },
}

-- Display names and text for grouped buffs
local BuffGroups = {
    beacons = { displayName = "Beacons", missingText = "NO\nBEACONS" },
}

-- Get the effective setting key for a buff (groupId if present, otherwise individual key)
local function GetBuffSettingKey(buffData)
    local _, key, _, _, _, _, groupId = unpack(buffData)
    return groupId or key
end

-- Classes that benefit from each buff (BETA: class-level only, not spec-aware)
-- nil = everyone benefits, otherwise only listed classes are counted
local BuffBeneficiaries = {
    intellect = {
        MAGE = true,
        WARLOCK = true,
        PRIEST = true,
        DRUID = true,
        SHAMAN = true,
        MONK = true,
        EVOKER = true,
        PALADIN = true,
        DEMONHUNTER = true,
    },
    attackPower = {
        WARRIOR = true,
        ROGUE = true,
        HUNTER = true,
        DEATHKNIGHT = true,
        PALADIN = true,
        MONK = true,
        DRUID = true,
        DEMONHUNTER = true,
        SHAMAN = true,
    },
    -- stamina, versatility, skyfury, bronze = everyone benefits (nil)
}

-- Default settings
local defaults = {
    position = { point = "CENTER", x = 0, y = 0 },
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
        beacons = true,
        shadowform = true,
    },
    iconSize = 64,
    spacing = 0.2, -- multiplier of iconSize (reset ratios default)
    textScale = 0.34, -- multiplier of iconSize (reset ratios default)
    showBuffReminder = true,
    showOnlyInGroup = false,
    showOnlyInInstance = false,
    showOnlyPlayerClassBuff = false,
    filterByClassBenefit = false,
    showOnlyOnReadyCheck = false,
    readyCheckDuration = 15, -- seconds
    growDirection = "CENTER", -- "LEFT", "CENTER", "RIGHT"
    showExpirationGlow = true,
    expirationThreshold = 15, -- minutes
    glowStyle = 1, -- 1=Orange, 2=Gold, 3=Yellow, 4=White, 5=Red
    optionsPanelScale = 1.2, -- base scale (displayed as 100%)
}

-- Locals
local mainFrame
local buffFrames = {}
local updateTicker
local inReadyCheck = false
local readyCheckTimer = nil
local inCombat = false
local testMode = false
local testModeData = nil -- Stores seeded fake values for consistent test display
local playerClass = nil -- Cached player class, set once on init
local optionsPanel
local MISSING_TEXT_SCALE = 0.6 -- scale for "NO X" warning text

-- Check if a unit is a valid group member for buff tracking
-- Excludes: non-existent, dead/ghost, disconnected, hostile (cross-faction in open world)
local function IsValidGroupMember(unit)
    return UnitExists(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) and UnitCanAssist("player", unit)
end

-- Calculate font size based on settings, with optional scale multiplier
local function GetFontSize(scale)
    local db = BuffRemindersDB
    local baseSize = db.iconSize * (db.textScale or defaults.textScale)
    return math.floor(baseSize * (scale or 1))
end

-- Format remaining time in seconds to a short string (e.g., "5m" or "30s")
local function FormatRemainingTime(seconds)
    local mins = math.floor(seconds / 60)
    if mins > 0 then
        return mins .. "m"
    else
        return math.floor(seconds) .. "s"
    end
end

-- Get classes present in the group
local function GetGroupClasses()
    local classes = {}
    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers()

    if groupSize == 0 then
        if playerClass then
            classes[playerClass] = true
        end
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

        if IsValidGroupMember(unit) then
            local _, class = UnitClass(unit)
            if class then
                classes[class] = true
            end
        end
    end
    return classes
end

-- Check if unit has a specific buff (handles single spellID or table of spellIDs)
-- Returns: hasBuff, remainingTime, sourceUnit
local function UnitHasBuff(unit, spellIDs)
    if type(spellIDs) ~= "table" then
        spellIDs = { spellIDs }
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
            return true, remaining, auraData.sourceUnit
        end
    end

    return false, nil, nil
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
    local db = BuffRemindersDB
    local beneficiaries = db.filterByClassBenefit and buffKey and BuffBeneficiaries[buffKey] or nil

    if groupSize == 0 then
        -- Solo: check if player benefits
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

        if IsValidGroupMember(unit) then
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

        if IsValidGroupMember(unit) then
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

-- Check if player's buff is active on anyone in the group
-- Returns true if the buff (from player) exists on someone, false otherwise
-- If role is specified, only checks units with that role
local function IsPlayerBuffActive(spellID, role, groupSize)
    local inRaid = IsInRaid()

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

        if IsValidGroupMember(unit) then
            if not role or UnitGroupRolesAssigned(unit) == role then
                local hasBuff, _, sourceUnit = UnitHasBuff(unit, spellID)
                if hasBuff and sourceUnit and UnitIsUnit(sourceUnit, "player") then
                    return true
                end
            end
        end
    end

    return false
end

-- Check if player should cast their personal buff (returns true if a beneficiary needs it)
-- Returns nil if player can't provide this buff
local function ShouldShowPersonalBuff(spellIDs, requiredClass, beneficiaryRole)
    if playerClass ~= requiredClass then
        return nil
    end

    local spellID = type(spellIDs) == "table" and spellIDs[1] or spellIDs
    if not IsPlayerSpell(spellID) then
        return nil
    end

    -- Personal buffs require a group (you cast them on others)
    local groupSize = GetNumGroupMembers()
    if groupSize == 0 then
        return nil
    end

    return not IsPlayerBuffActive(spellID, beneficiaryRole, groupSize)
end

-- Check if player should cast their self buff (returns true if missing)
-- Returns nil if player can't/shouldn't use this buff
local function ShouldShowSelfBuff(spellID, requiredClass)
    if playerClass ~= requiredClass then
        return nil
    end

    if not IsPlayerSpell(spellID) then
        return nil
    end

    local hasBuff, _ = UnitHasBuff("player", spellID)
    return not hasBuff
end

-- Forward declarations
local UpdateDisplay, PositionBuffFrames, UpdateAnchor, ShowGlowDemo, ToggleTestMode, RefreshTestDisplay

-- Glow style definitions
local GlowStyles = {
    {
        name = "Orange",
        setup = function(frame)
            local glow = frame:CreateTexture(nil, "OVERLAY")
            glow:SetPoint("TOPLEFT", -4, 4)
            glow:SetPoint("BOTTOMRIGHT", 4, -4)
            glow:SetAtlas("bags-glow-orange")
            glow:SetAlpha(0.8)
            frame.glowTexture = glow
            local ag = glow:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(0.8)
            fade:SetToAlpha(0.3)
            fade:SetDuration(0.5)
            frame.glowAnim = ag
        end,
    },
    {
        name = "Gold",
        setup = function(frame)
            local glow = frame:CreateTexture(nil, "OVERLAY")
            glow:SetPoint("TOPLEFT", -3, 3)
            glow:SetPoint("BOTTOMRIGHT", 3, -3)
            glow:SetAtlas("loottoast-itemborder-gold")
            frame.glowTexture = glow
            local ag = glow:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0.4)
            fade:SetDuration(0.6)
            frame.glowAnim = ag
        end,
    },
    {
        name = "Yellow",
        setup = function(frame)
            local glow = frame:CreateTexture(nil, "OVERLAY")
            glow:SetPoint("TOPLEFT", -6, 6)
            glow:SetPoint("BOTTOMRIGHT", 6, -6)
            glow:SetAtlas("bags-glow-white")
            glow:SetVertexColor(1, 0.8, 0)
            frame.glowTexture = glow
            local ag = glow:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(0.9)
            fade:SetToAlpha(0.2)
            fade:SetDuration(0.5)
            frame.glowAnim = ag
        end,
    },
    {
        name = "White",
        setup = function(frame)
            local glow = frame:CreateTexture(nil, "OVERLAY")
            glow:SetPoint("TOPLEFT", -6, 6)
            glow:SetPoint("BOTTOMRIGHT", 6, -6)
            glow:SetAtlas("bags-glow-white")
            frame.glowTexture = glow
            local ag = glow:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(0.9)
            fade:SetToAlpha(0.2)
            fade:SetDuration(0.5)
            frame.glowAnim = ag
        end,
    },
    {
        name = "Red",
        setup = function(frame)
            local glow = frame:CreateTexture(nil, "OVERLAY")
            glow:SetPoint("TOPLEFT", -5, 5)
            glow:SetPoint("BOTTOMRIGHT", 5, -5)
            glow:SetAtlas("bags-glow-white")
            glow:SetVertexColor(1, 0.2, 0.2)
            frame.glowTexture = glow
            local ag = glow:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0.1)
            fade:SetDuration(0.3)
            frame.glowAnim = ag
        end,
    },
}

-- Show/hide expiration glow on a buff frame
local function SetExpirationGlow(frame, show)
    local db = BuffRemindersDB
    local styleIndex = db.glowStyle or 1

    if show then
        if not frame.glowShowing or frame.currentGlowStyle ~= styleIndex then
            -- Clean up old glow if style changed
            if frame.glowAnim then
                frame.glowAnim:Stop()
            end
            if frame.glowTexture then
                frame.glowTexture:Hide()
                frame.glowTexture:SetParent(nil)
                frame.glowTexture = nil
            end
            frame.glowAnim = nil

            -- Setup new glow style
            local style = GlowStyles[styleIndex]
            if style then
                style.setup(frame)
                frame.currentGlowStyle = styleIndex
                if frame.glowTexture then
                    frame.glowTexture:Show()
                end
                if frame.glowAnim then
                    frame.glowAnim:Play()
                end
            end
            frame.glowShowing = true
        end
    else
        if frame.glowShowing then
            if frame.glowAnim then
                frame.glowAnim:Stop()
            end
            if frame.glowTexture then
                frame.glowTexture:Hide()
            end
            frame.glowShowing = false
        end
    end
end

-- Create icon frame for a buff
local function CreateBuffFrame(buffData, _)
    local spellIDs, key, displayName, classProvider = unpack(buffData)

    local frame = CreateFrame("Frame", "BuffReminders_" .. key, mainFrame)
    frame.key = key
    frame.spellIDs = spellIDs
    frame.displayName = displayName

    local db = BuffRemindersDB
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
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    frame.count:SetPoint("CENTER", 0, 0)
    frame.count:SetTextColor(1, 1, 1, 1)
    frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(), "OUTLINE")

    -- "BUFF!" text for the class that provides this buff
    frame.isPlayerBuff = (playerClass == classProvider)
    if frame.isPlayerBuff then
        frame.buffText = frame:CreateFontString(nil, "OVERLAY")
        frame.buffText:SetPoint("TOP", frame, "BOTTOM", 0, -6)
        frame.buffText:SetFont(STANDARD_TEXT_FONT, GetFontSize(0.8), "OUTLINE")
        frame.buffText:SetTextColor(1, 1, 1, 1)
        frame.buffText:SetText("BUFF!")
        if not db.showBuffReminder then
            frame.buffText:Hide()
        end
    end

    -- "TEST" text (shown above icon in test mode)
    frame.testText = frame:CreateFontString(nil, "OVERLAY")
    frame.testText:SetPoint("BOTTOM", frame, "TOP", 0, 8)
    frame.testText:SetFont(STANDARD_TEXT_FONT, GetFontSize(0.6), "OUTLINE")
    frame.testText:SetTextColor(1, 0.8, 0, 1)
    frame.testText:SetText("TEST")
    frame.testText:Hide()

    -- Dragging
    frame:EnableMouse(not BuffRemindersDB.locked)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        if not BuffRemindersDB.locked then
            mainFrame:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
        local point, _, _, x, y = mainFrame:GetPoint()
        BuffRemindersDB.position = { point = point, x = x, y = y }
    end)

    frame:Hide()
    return frame
end

-- Position all visible buff frames (in definition order)
PositionBuffFrames = function()
    local db = BuffRemindersDB
    local iconSize = db.iconSize or 32
    local spacing = math.floor(iconSize * (db.spacing or 0.2))
    local direction = db.growDirection or "CENTER"

    -- Collect visible frames in definition order
    local visibleFrames = {}
    for _, buffData in ipairs(RaidBuffs) do
        local key = buffData[2]
        local frame = buffFrames[key]
        if frame and frame:IsShown() then
            table.insert(visibleFrames, frame)
        end
    end
    for _, buffData in ipairs(PresenceBuffs) do
        local key = buffData[2]
        local frame = buffFrames[key]
        if frame and frame:IsShown() then
            table.insert(visibleFrames, frame)
        end
    end
    for _, buffData in ipairs(PersonalBuffs) do
        local key = buffData[2]
        local frame = buffFrames[key]
        if frame and frame:IsShown() then
            table.insert(visibleFrames, frame)
        end
    end
    for _, buffData in ipairs(SelfBuffs) do
        local key = buffData[2]
        local frame = buffFrames[key]
        if frame and frame:IsShown() then
            table.insert(visibleFrames, frame)
        end
    end

    local count = #visibleFrames
    if count == 0 then
        return
    end

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

-- Refresh the test mode display (used when settings change while in test mode)
-- Uses seeded values from testModeData for consistent display
RefreshTestDisplay = function()
    if not testModeData then
        return
    end

    local db = BuffRemindersDB

    -- Hide all frames, clear glows, and hide test labels first
    for _, frame in pairs(buffFrames) do
        frame:Hide()
        SetExpirationGlow(frame, false)
        if frame.testText then
            frame.testText:Hide()
        end
    end

    local glowShown = false

    -- Show ALL raid buffs (ignore enabledBuffs)
    for i, buffData in ipairs(RaidBuffs) do
        local _, key = unpack(buffData)
        local frame = buffFrames[key]
        if frame then
            frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(), "OUTLINE")
            if db.showExpirationGlow and not glowShown then
                frame.count:SetText(FormatRemainingTime(testModeData.fakeRemaining))
                SetExpirationGlow(frame, true)
                glowShown = true
            else
                local fakeBuffed = testModeData.fakeTotal - testModeData.fakeMissing[i]
                frame.count:SetText(fakeBuffed .. "/" .. testModeData.fakeTotal)
            end
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(STANDARD_TEXT_FONT, GetFontSize(0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL presence buffs
    for _, buffData in ipairs(PresenceBuffs) do
        local _, key, _, _, missingText = unpack(buffData)
        local frame = buffFrames[key]
        if frame then
            frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
            frame.count:SetText(missingText or "")
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(STANDARD_TEXT_FONT, GetFontSize(0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL personal buffs (one per group)
    local seenGroups = {}
    for _, buffData in ipairs(PersonalBuffs) do
        local _, key, _, _, _, missingText, groupId = unpack(buffData)
        local frame = buffFrames[key]
        if frame then
            if groupId and seenGroups[groupId] then
                frame:Hide()
            else
                if groupId then
                    seenGroups[groupId] = true
                    local groupInfo = BuffGroups[groupId]
                    frame.count:SetText(groupInfo and groupInfo.missingText or "")
                else
                    frame.count:SetText(missingText or "")
                end
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
                if frame.testText and testModeData.showLabels then
                    frame.testText:SetFont(STANDARD_TEXT_FONT, GetFontSize(0.6), "OUTLINE")
                    frame.testText:Show()
                end
                frame:Show()
            end
        end
    end

    -- Show ALL self buffs
    for _, buffData in ipairs(SelfBuffs) do
        local _, key, _, _, missingText = unpack(buffData)
        local frame = buffFrames[key]
        if frame then
            frame.count:SetText(missingText or "")
            frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(STANDARD_TEXT_FONT, GetFontSize(0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    mainFrame:Show()
    PositionBuffFrames()
end

-- Toggle test mode - returns true if test mode is now ON, false if OFF
-- showLabels: if true (default), show "TEST" labels above icons
ToggleTestMode = function(showLabels)
    if showLabels == nil then
        showLabels = true
    end
    if testMode then
        testMode = false
        testModeData = nil
        -- Clear all glows and hide test labels
        for _, frame in pairs(buffFrames) do
            SetExpirationGlow(frame, false)
            if frame.testText then
                frame.testText:Hide()
            end
        end
        UpdateDisplay()
        return false
    else
        testMode = true
        -- Seed fake values for consistent display during test mode
        local db = BuffRemindersDB
        testModeData = {
            fakeTotal = math.random(10, 20),
            fakeRemaining = math.random(1, db.expirationThreshold or 15) * 60,
            fakeMissing = {},
            showLabels = showLabels,
        }
        for i = 1, #RaidBuffs do
            testModeData.fakeMissing[i] = math.random(1, 5)
        end
        RefreshTestDisplay()
        return true
    end
end

-- Update the display
UpdateDisplay = function()
    if testMode then
        return
    end

    if inCombat then
        mainFrame:Hide()
        return
    end

    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        mainFrame:Hide()
        return
    end

    local db = BuffRemindersDB

    -- Hide based on visibility settings
    if db.showOnlyOnReadyCheck and not inReadyCheck then
        mainFrame:Hide()
        return
    end

    if db.showOnlyInGroup then
        if db.showOnlyInInstance then
            if not IsInInstance() then
                mainFrame:Hide()
                return
            end
        elseif GetNumGroupMembers() == 0 then
            mainFrame:Hide()
            return
        end
    end

    local presentClasses = GetGroupClasses()

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
                -- Everyone has buff but expiring soon - show remaining time with glow
                frame.count:SetText(FormatRemainingTime(minRemaining))
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
        local spellIDs, key, _, classProvider, missingText, readyCheckOnly = unpack(buffData)
        local frame = buffFrames[key]

        local showBuff = true
        -- Filter: ready check only buffs
        if readyCheckOnly and not inReadyCheck then
            showBuff = false
        end
        -- Filter: only show player's class buff
        if showBuff and db.showOnlyPlayerClassBuff and classProvider ~= playerClass then
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
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
                frame.count:SetText(missingText or "")
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, false)
            elseif expiringSoon then
                -- Has buff but expiring soon - show remaining time with glow
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(), "OUTLINE")
                frame.count:SetText(FormatRemainingTime(minRemaining))
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

    -- Process personal buffs (player's own buff responsibility)
    local visibleGroups = {} -- Track visible buffs by groupId for merging
    for _, buffData in ipairs(PersonalBuffs) do
        local spellIDs, key, _, requiredClass, beneficiaryRole, missingText, groupId = unpack(buffData)
        local frame = buffFrames[key]
        local settingKey = GetBuffSettingKey(buffData)

        if frame and db.enabledBuffs[settingKey] then
            local shouldShow = ShouldShowPersonalBuff(spellIDs, requiredClass, beneficiaryRole)
            if shouldShow then
                frame.icon:SetAllPoints()
                frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
                frame.count:SetText(missingText or "")
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, false)
                -- Track for group merging
                if groupId then
                    visibleGroups[groupId] = visibleGroups[groupId] or {}
                    table.insert(visibleGroups[groupId], { frame = frame, spellID = spellIDs })
                end
            else
                frame:Hide()
                SetExpirationGlow(frame, false)
            end
        elseif frame then
            frame:Hide()
            SetExpirationGlow(frame, false)
        end
    end

    -- Merge grouped buffs that are both visible (show first icon with group text)
    for groupId, group in pairs(visibleGroups) do
        if #group >= 2 then
            local primary = group[1]
            local groupInfo = BuffGroups[groupId]
            primary.frame.count:SetText(groupInfo and groupInfo.missingText or "")
            -- Hide other frames in the group
            for i = 2, #group do
                group[i].frame:Hide()
            end
        end
    end

    -- Process self buffs (player's own buff on themselves)
    for _, buffData in ipairs(SelfBuffs) do
        local spellID, key, _, requiredClass, missingText = unpack(buffData)
        local frame = buffFrames[key]

        if frame and db.enabledBuffs[key] then
            local shouldShow = ShouldShowSelfBuff(spellID, requiredClass)
            if shouldShow then
                frame.icon:SetAllPoints()
                frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
                frame.count:SetText(missingText or "")
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, false)
            else
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
    mainFrame:EnableMouse(not BuffRemindersDB.locked)
    mainFrame:RegisterForDrag("LeftButton")

    mainFrame:SetScript("OnDragStart", function(self)
        if not BuffRemindersDB.locked then
            self:StartMoving()
        end
    end)

    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        BuffRemindersDB.position = { point = point, x = x, y = y }
    end)
end

-- Initialize main frame
local function InitializeFrames()
    mainFrame = CreateFrame("Frame", "BuffRemindersFrame", UIParent)
    mainFrame:SetSize(200, 50)

    local db = BuffRemindersDB
    mainFrame:SetPoint(
        db.position.point or "CENTER",
        UIParent,
        db.position.point or "CENTER",
        db.position.x or 0,
        db.position.y or 0
    )

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

    for i, buffData in ipairs(PersonalBuffs) do
        local key = buffData[2]
        buffFrames[key] = CreateBuffFrame(buffData, #RaidBuffs + #PresenceBuffs + i)
        buffFrames[key].isPersonalBuff = true
    end

    for i, buffData in ipairs(SelfBuffs) do
        local key = buffData[2]
        buffFrames[key] = CreateBuffFrame(buffData, #RaidBuffs + #PresenceBuffs + #PersonalBuffs + i)
        buffFrames[key].isSelfBuff = true
    end

    mainFrame:Hide()
end

-- Update anchor position and visibility
UpdateAnchor = function()
    if not mainFrame or not mainFrame.anchorFrame then
        return
    end
    local db = BuffRemindersDB
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

    -- Update mouse enabled state (click-through when locked)
    mainFrame:EnableMouse(not db.locked)
    for _, frame in pairs(buffFrames) do
        frame:EnableMouse(not db.locked)
    end
end

-- Update icon sizes and text (called when settings change)
local function UpdateVisuals()
    local db = BuffRemindersDB
    local size = db.iconSize
    for _, frame in pairs(buffFrames) do
        frame:SetSize(size, size)
        frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(), "OUTLINE")
        if frame.buffText then
            frame.buffText:SetFont(STANDARD_TEXT_FONT, GetFontSize(0.8), "OUTLINE")
            if db.showBuffReminder then
                frame.buffText:Show()
            else
                frame.buffText:Hide()
            end
        end
    end
    if testMode then
        RefreshTestDisplay()
    else
        UpdateDisplay()
    end
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

    local panel = CreateFrame("Frame", "BuffRemindersOptions", UIParent, "BackdropTemplate")
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
    addonIcon:SetTexture("Interface\\AddOns\\BuffReminders\\icon.tga")
    addonIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Title (next to icon)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", addonIcon, "RIGHT", 8, 0)
    title:SetText("BuffReminders")

    -- Scale controls (top right area) - using buttons to avoid slider scaling issues
    -- Base scale is 1.2 (displayed as 100%), range is 80%-150%
    local BASE_SCALE = 1.2
    local MIN_PCT, MAX_PCT = 80, 150
    local scaleDown, scaleUp

    local scaleValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValue:SetPoint("TOPRIGHT", -70, -14)
    local currentScale = BuffRemindersDB.optionsPanelScale or BASE_SCALE
    local currentPct = math.floor(currentScale / BASE_SCALE * 100 + 0.5)
    scaleValue:SetText(currentPct .. "%")

    local function UpdateScale(delta)
        -- Use integer math to avoid floating point issues
        local oldPct = math.floor((BuffRemindersDB.optionsPanelScale or BASE_SCALE) / BASE_SCALE * 100 + 0.5)
        local newPct = math.max(MIN_PCT, math.min(MAX_PCT, oldPct + delta))
        local newScale = newPct / 100 * BASE_SCALE
        BuffRemindersDB.optionsPanelScale = newScale
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
    scaleDown:SetScript("OnClick", function()
        UpdateScale(-10)
    end)
    scaleDown:SetEnabled(currentPct > MIN_PCT)

    scaleUp = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scaleUp:SetSize(18, 18)
    scaleUp:SetPoint("LEFT", scaleValue, "RIGHT", 4, 0)
    scaleUp:SetText("+")
    scaleUp:SetScript("OnClick", function()
        UpdateScale(10)
    end)
    scaleUp:SetEnabled(currentPct < MAX_PCT)

    -- Apply saved scale
    if BuffRemindersDB.optionsPanelScale then
        panel:SetScale(BuffRemindersDB.optionsPanelScale)
    end

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
    end)

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
        cb:SetChecked(BuffRemindersDB.enabledBuffs[key])
        cb:SetScript("OnClick", function(self)
            BuffRemindersDB.enabledBuffs[key] = self:GetChecked()
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
        cb.label = label

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
        valueBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        slider:SetScript("OnValueChanged", function(self, val)
            val = math.floor(val)
            value:SetText(val .. (suffix or ""))
            onChange(val)
        end)

        slider.label = label
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
        local spellIDs, key, displayName, _, _, readyCheckOnly = unpack(buffData)
        leftY = CreateBuffCheckbox(leftColX, leftY, spellIDs, key, displayName)
        -- Add info indicator for ready-check-only buffs
        if readyCheckOnly then
            local infoIcon = panel:CreateTexture(nil, "ARTWORK")
            infoIcon:SetSize(14, 14)
            infoIcon:SetPoint("TOPLEFT", leftColX + 105, leftY + ITEM_HEIGHT - 3)
            infoIcon:SetAtlas("QuestNormal")
            -- Create invisible button for tooltip
            local infoBtn = CreateFrame("Button", nil, panel)
            infoBtn:SetSize(14, 14)
            infoBtn:SetPoint("CENTER", infoIcon, "CENTER", 0, 0)
            infoBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Ready Check Only", 1, 0.82, 0)
                GameTooltip:AddLine("This buff is only shown during ready checks.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            infoBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
    end

    leftY = leftY - SECTION_SPACING

    -- Personal Buffs header
    _, leftY = CreateSectionHeader(panel, "Personal Buffs", leftColX, leftY)
    local personalNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    personalNote:SetPoint("TOPLEFT", leftColX, leftY)
    personalNote:SetText("(your buff only)")
    leftY = leftY - 14

    local seenGroups = {}
    for _, buffData in ipairs(PersonalBuffs) do
        local spellIDs, key, displayName, _, _, _, groupId = unpack(buffData)
        if groupId then
            if not seenGroups[groupId] then
                seenGroups[groupId] = true
                local groupInfo = BuffGroups[groupId]
                leftY = CreateBuffCheckbox(leftColX, leftY, spellIDs, groupId, groupInfo.displayName)
            end
        else
            leftY = CreateBuffCheckbox(leftColX, leftY, spellIDs, key, displayName)
        end
    end

    leftY = leftY - SECTION_SPACING

    -- Self Buffs header
    _, leftY = CreateSectionHeader(panel, "Self Buffs", leftColX, leftY)
    local selfNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    selfNote:SetPoint("TOPLEFT", leftColX, leftY)
    selfNote:SetText("(buffs on yourself)")
    leftY = leftY - 14

    for _, buffData in ipairs(SelfBuffs) do
        local spellID, key, displayName = unpack(buffData)
        leftY = CreateBuffCheckbox(leftColX, leftY, spellID, key, displayName)
    end

    -- ========== RIGHT COLUMN: SETTINGS ==========
    local rightY = startY

    -- Appearance header
    _, rightY = CreateSectionHeader(panel, "Appearance", rightColX, rightY)

    local sizeSlider, sizeValue
    sizeSlider, sizeValue, rightY = CreateSlider(
        rightColX,
        rightY,
        "Icon Size",
        16,
        128,
        1,
        BuffRemindersDB.iconSize,
        "",
        function(val)
            BuffRemindersDB.iconSize = val
            UpdateVisuals()
        end
    )
    panel.sizeSlider = sizeSlider
    panel.sizeValue = sizeValue

    local spacingSlider, spacingValue
    spacingSlider, spacingValue, rightY = CreateSlider(
        rightColX,
        rightY,
        "Spacing",
        0,
        50,
        1,
        math.floor((BuffRemindersDB.spacing or 0.2) * 100),
        "%",
        function(val)
            BuffRemindersDB.spacing = val / 100
            if testMode then
                PositionBuffFrames()
            else
                UpdateDisplay()
            end
        end
    )
    panel.spacingSlider = spacingSlider
    panel.spacingValue = spacingValue

    local textSlider, textValue
    textSlider, textValue, rightY = CreateSlider(
        rightColX,
        rightY,
        "Text Size",
        20,
        60,
        1,
        math.floor((BuffRemindersDB.textScale or 0.34) * 100),
        "%",
        function(val)
            BuffRemindersDB.textScale = val / 100
            UpdateVisuals()
        end
    )
    panel.textSlider = textSlider
    panel.textValue = textValue

    rightY = rightY - 4

    -- Lock button and grow direction
    local lockBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    lockBtn:SetSize(52, 18)
    lockBtn:SetPoint("TOPLEFT", rightColX, rightY)
    lockBtn:SetNormalFontObject("GameFontHighlightSmall")
    lockBtn:SetHighlightFontObject("GameFontHighlightSmall")
    lockBtn:SetText(BuffRemindersDB.locked and "Unlock" or "Lock")
    lockBtn:SetScript("OnClick", function(self)
        BuffRemindersDB.locked = not BuffRemindersDB.locked
        self:SetText(BuffRemindersDB.locked and "Unlock" or "Lock")
        UpdateAnchor()
    end)
    panel.lockBtn = lockBtn

    local growLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    growLabel:SetPoint("LEFT", lockBtn, "RIGHT", 10, 0)
    growLabel:SetText("Grow:")

    local growBtns = {}
    local directions = { "LEFT", "CENTER", "RIGHT" }
    local dirLabels = { "Left", "Center", "Right" }
    local growBtnWidth = 52

    for i, dir in ipairs(directions) do
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(growBtnWidth, 18)
        btn:SetPoint("LEFT", growLabel, "RIGHT", 5 + (i - 1) * (growBtnWidth + 3), 0)
        btn:SetText(dirLabels[i])
        btn:SetNormalFontObject("GameFontHighlightSmall")
        btn:SetHighlightFontObject("GameFontHighlightSmall")
        btn:SetDisabledFontObject("GameFontDisableSmall")
        btn.direction = dir
        btn:SetScript("OnClick", function()
            BuffRemindersDB.growDirection = dir
            for _, b in ipairs(growBtns) do
                b:SetEnabled(b.direction ~= dir)
            end
            UpdateDisplay()
        end)
        btn:SetEnabled(BuffRemindersDB.growDirection ~= dir)
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

    local reminderCb
    reminderCb, rightY = CreateCheckbox(
        rightColX,
        rightY,
        'Show "BUFF!" reminder',
        BuffRemindersDB.showBuffReminder ~= false,
        function(self)
            BuffRemindersDB.showBuffReminder = self:GetChecked()
            UpdateVisuals()
        end
    )
    panel.reminderCheckbox = reminderCb

    -- Helper to enable/disable checkbox with label greying
    local function SetCheckboxEnabled(cb, enabled)
        cb:SetEnabled(enabled)
        if cb.label then
            if enabled then
                cb.label:SetTextColor(1, 1, 1)
            else
                cb.label:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end

    local groupCb, instanceCb
    groupCb, rightY = CreateCheckbox(
        rightColX,
        rightY,
        "Show only in group/raid",
        BuffRemindersDB.showOnlyInGroup ~= false,
        function(self)
            BuffRemindersDB.showOnlyInGroup = self:GetChecked()
            -- Update sub-checkbox enabled state
            if instanceCb then
                SetCheckboxEnabled(instanceCb, self:GetChecked())
                if not self:GetChecked() then
                    instanceCb:SetChecked(false)
                    BuffRemindersDB.showOnlyInInstance = false
                end
            end
            UpdateDisplay()
        end
    )
    panel.groupCheckbox = groupCb

    -- Sub-checkbox: Only in instance (indented under group checkbox)
    instanceCb, rightY = CreateCheckbox(
        rightColX + 20,
        rightY,
        "Only in instance",
        BuffRemindersDB.showOnlyInInstance,
        function(self)
            BuffRemindersDB.showOnlyInInstance = self:GetChecked()
            UpdateDisplay()
        end
    )
    SetCheckboxEnabled(instanceCb, BuffRemindersDB.showOnlyInGroup)
    panel.instanceCheckbox = instanceCb
    panel.SetCheckboxEnabled = SetCheckboxEnabled

    local readyCheckCb, readyCheckSlider, readyCheckSliderValue
    readyCheckCb, rightY = CreateCheckbox(
        rightColX,
        rightY,
        "Show only on ready check",
        BuffRemindersDB.showOnlyOnReadyCheck,
        function(self)
            BuffRemindersDB.showOnlyOnReadyCheck = self:GetChecked()
            -- Enable/disable the duration slider
            if readyCheckSlider then
                local enabled = self:GetChecked()
                local color = enabled and 1 or 0.5
                readyCheckSlider:SetEnabled(enabled)
                readyCheckSlider.label:SetTextColor(color, color, color)
                readyCheckSliderValue:SetTextColor(color, color, color)
            end
            UpdateDisplay()
        end
    )
    panel.readyCheckCheckbox = readyCheckCb

    -- Duration slider
    readyCheckSlider, readyCheckSliderValue, rightY = CreateSlider(
        rightColX,
        rightY,
        "Duration",
        10,
        30,
        1,
        BuffRemindersDB.readyCheckDuration or 15,
        "s",
        function(val)
            BuffRemindersDB.readyCheckDuration = val
        end
    )
    local rcEnabled = BuffRemindersDB.showOnlyOnReadyCheck
    local rcColor = rcEnabled and 1 or 0.5
    readyCheckSlider:SetEnabled(rcEnabled)
    readyCheckSlider.label:SetTextColor(rcColor, rcColor, rcColor)
    readyCheckSliderValue:SetTextColor(rcColor, rcColor, rcColor)
    panel.readyCheckSlider = readyCheckSlider
    panel.readyCheckSliderValue = readyCheckSliderValue

    local playerClassCb
    playerClassCb, rightY = CreateCheckbox(
        rightColX,
        rightY,
        "Show only my class buffs",
        BuffRemindersDB.showOnlyPlayerClassBuff,
        function(self)
            BuffRemindersDB.showOnlyPlayerClassBuff = self:GetChecked()
            UpdateDisplay()
        end
    )
    panel.playerClassCheckbox = playerClassCb

    local classBenefitCb
    classBenefitCb, rightY = CreateCheckbox(
        rightColX,
        rightY,
        "Only count benefiting classes |cffff8000(BETA)|r",
        BuffRemindersDB.filterByClassBenefit,
        function(self)
            BuffRemindersDB.filterByClassBenefit = self:GetChecked()
            UpdateDisplay()
        end
    )
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
    glowCb, rightY = CreateCheckbox(
        rightColX,
        rightY,
        "Show glow when expiring in:",
        BuffRemindersDB.showExpirationGlow,
        function(self)
            BuffRemindersDB.showExpirationGlow = self:GetChecked()
            if panel.SetGlowControlsEnabled then
                panel.SetGlowControlsEnabled(self:GetChecked())
            end
            if testMode then
                RefreshTestDisplay()
            else
                UpdateDisplay()
            end
        end
    )
    glowCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Expiration Warning")
        GameTooltip:AddLine("Shows a glow effect on buff icons when they are close to expiring.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            "The icon will be shown even when all players have the buff, as long as it's within the threshold.",
            0.8,
            0.8,
            0.8,
            true
        )
        GameTooltip:Show()
    end)
    glowCb:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    panel.glowCheckbox = glowCb

    local thresholdSlider, thresholdValue
    thresholdSlider, thresholdValue, rightY = CreateSlider(
        rightColX,
        rightY,
        "Threshold",
        1,
        15,
        1,
        BuffRemindersDB.expirationThreshold or 5,
        " min",
        function(val)
            BuffRemindersDB.expirationThreshold = val
            if testMode then
                RefreshTestDisplay()
            else
                UpdateDisplay()
            end
        end
    )
    panel.thresholdSlider = thresholdSlider
    panel.thresholdValue = thresholdValue

    -- Glow style dropdown
    local styleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.styleLabel = styleLabel
    styleLabel:SetPoint("TOPLEFT", rightColX, rightY)
    styleLabel:SetText("Style:")

    local styleDropdown = CreateFrame("Frame", "BuffRemindersStyleDropdown", panel, "UIDropDownMenuTemplate")
    styleDropdown:SetPoint("LEFT", styleLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(styleDropdown, 100)

    local function StyleDropdown_Initialize(self, level)
        for i, style in ipairs(GlowStyles) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = style.name
            info.value = i
            info.checked = (BuffRemindersDB.glowStyle or 1) == i
            info.func = function()
                BuffRemindersDB.glowStyle = i
                UIDropDownMenu_SetSelectedValue(styleDropdown, i)
                UIDropDownMenu_SetText(styleDropdown, style.name)
                if testMode then
                    RefreshTestDisplay()
                else
                    UpdateDisplay()
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(styleDropdown, StyleDropdown_Initialize)
    UIDropDownMenu_SetSelectedValue(styleDropdown, BuffRemindersDB.glowStyle or 1)
    UIDropDownMenu_SetText(styleDropdown, GlowStyles[BuffRemindersDB.glowStyle or 1].name)
    panel.styleDropdown = styleDropdown

    -- Preview button
    local previewBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    previewBtn:SetSize(80, 18)
    previewBtn:SetPoint("LEFT", styleDropdown, "RIGHT", 0, 2)
    previewBtn:SetText("Preview")
    previewBtn:SetScript("OnClick", function()
        ShowGlowDemo()
    end)
    panel.previewBtn = previewBtn

    -- Helper to enable/disable glow-related controls
    local function SetGlowControlsEnabled(enabled)
        local color = enabled and 1 or 0.5
        thresholdSlider:SetEnabled(enabled)
        thresholdSlider.label:SetTextColor(color, color, color)
        thresholdValue:SetTextColor(color, color, color)
        styleLabel:SetTextColor(color, color, color)
        UIDropDownMenu_EnableDropDown(styleDropdown)
        if not enabled then
            UIDropDownMenu_DisableDropDown(styleDropdown)
        end
        previewBtn:SetEnabled(enabled)
    end
    panel.SetGlowControlsEnabled = SetGlowControlsEnabled

    -- Set initial state
    SetGlowControlsEnabled(BuffRemindersDB.showExpirationGlow)

    rightY = rightY - 28

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
    resetPosBtn:SetPoint("TOP", -totalBtnWidth / 2 + btnWidth / 2, bottomY)
    resetPosBtn:SetText("Reset Pos")
    resetPosBtn:SetScript("OnClick", function()
        BuffRemindersDB.position = { point = "CENTER", x = 0, y = 0 }
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end)
    resetPosBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset Position")
        GameTooltip:AddLine("Moves the buff tracker back to the center of the screen.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetPosBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local resetRatiosBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetRatiosBtn:SetSize(btnWidth, 22)
    resetRatiosBtn:SetPoint("LEFT", resetPosBtn, "RIGHT", btnSpacing, 0)
    resetRatiosBtn:SetText("Reset Ratios")
    resetRatiosBtn:SetScript("OnClick", function()
        BuffRemindersDB.spacing = 0.2
        BuffRemindersDB.textScale = 0.34
        panel.spacingSlider:SetValue(20)
        panel.textSlider:SetValue(34)
        panel.spacingValue:SetText("20%")
        panel.textValue:SetText("34%")
        UpdateVisuals()
    end)
    resetRatiosBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset Ratios")
        GameTooltip:AddLine("Resets spacing and text size to recommended ratios.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    resetRatiosBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(btnWidth, 22)
    testBtn:SetPoint("LEFT", resetRatiosBtn, "RIGHT", btnSpacing, 0)
    testBtn:SetText("Test")
    panel.testBtn = testBtn
    testBtn:SetScript("OnClick", function()
        local isOn = ToggleTestMode()
        testBtn:SetText(isOn and "Stop Test" or "Test")
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
        local db = BuffRemindersDB
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
        local seenSyncGroups = {}
        for _, buffData in ipairs(PersonalBuffs) do
            local _, _, _, _, _, _, groupId = unpack(buffData)
            local settingKey = GetBuffSettingKey(buffData)
            if groupId then
                if not seenSyncGroups[groupId] then
                    seenSyncGroups[groupId] = true
                    if optionsPanel.buffCheckboxes[settingKey] then
                        optionsPanel.buffCheckboxes[settingKey]:SetChecked(db.enabledBuffs[settingKey])
                    end
                end
            else
                if optionsPanel.buffCheckboxes[settingKey] then
                    optionsPanel.buffCheckboxes[settingKey]:SetChecked(db.enabledBuffs[settingKey])
                end
            end
        end
        for _, buffData in ipairs(SelfBuffs) do
            local key = buffData[2]
            if optionsPanel.buffCheckboxes[key] then
                optionsPanel.buffCheckboxes[key]:SetChecked(db.enabledBuffs[key])
            end
        end
        optionsPanel.sizeSlider:SetValue(db.iconSize)
        optionsPanel.spacingSlider:SetValue((db.spacing or 0.2) * 100)
        optionsPanel.textSlider:SetValue((db.textScale or 0.34) * 100)
        optionsPanel.lockBtn:SetText(db.locked and "Unlock" or "Lock")
        optionsPanel.reminderCheckbox:SetChecked(db.showBuffReminder ~= false)
        optionsPanel.groupCheckbox:SetChecked(db.showOnlyInGroup ~= false)
        if optionsPanel.instanceCheckbox then
            optionsPanel.instanceCheckbox:SetChecked(db.showOnlyInInstance)
            optionsPanel.SetCheckboxEnabled(optionsPanel.instanceCheckbox, db.showOnlyInGroup)
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
        if optionsPanel.styleDropdown then
            UIDropDownMenu_SetSelectedValue(optionsPanel.styleDropdown, db.glowStyle or 1)
            UIDropDownMenu_SetText(optionsPanel.styleDropdown, GlowStyles[db.glowStyle or 1].name)
        end
        if optionsPanel.SetGlowControlsEnabled then
            optionsPanel.SetGlowControlsEnabled(db.showExpirationGlow)
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

-- Glow demo panel
local glowDemoPanel
ShowGlowDemo = function()
    if glowDemoPanel then
        glowDemoPanel:SetShown(not glowDemoPanel:IsShown())
        return
    end

    local ICON_SIZE = 64
    local SPACING = 20

    local panel = CreateFrame("Frame", "BuffRemindersGlowDemo", UIParent, "BackdropTemplate")
    local numStyles = #GlowStyles
    panel:SetSize(numStyles * (ICON_SIZE + SPACING) + SPACING, ICON_SIZE + 70)
    panel:SetPoint("CENTER")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(0.12, 0.08, 0.18, 0.98)
    panel:SetBackdropBorderColor(0.6, 0.4, 0.8, 1)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata("TOOLTIP")

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Glow Styles Preview")

    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Create demo icons using GlowStyles
    for i, style in ipairs(GlowStyles) do
        local iconFrame = CreateFrame("Frame", nil, panel)
        iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
        iconFrame:SetPoint("TOPLEFT", SPACING + (i - 1) * (ICON_SIZE + SPACING), -30)

        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(GetBuffTexture(1459)) -- Arcane Intellect icon

        local border = iconFrame:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", 2, -2)
        border:SetColorTexture(0, 0, 0, 1)

        -- Setup and play glow animation
        style.setup(iconFrame)
        if iconFrame.glowAnim then
            iconFrame.glowAnim:Play()
        end

        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOP", iconFrame, "BOTTOM", 0, -4)
        label:SetText(i .. ". " .. style.name)
        label:SetWidth(ICON_SIZE + 10)
    end

    glowDemoPanel = panel
end

-- Slash command handler
local function SlashHandler(msg)
    local cmd = msg:match("^(%S*)") or ""
    cmd = cmd:lower()

    if cmd == "glowdemo" then
        ShowGlowDemo()
    elseif cmd == "test" then
        ToggleTestMode(false) -- no labels, for previews
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
eventFrame:RegisterEvent("READY_CHECK")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        _, playerClass = UnitClass("player")
        if not BuffRemindersDB then
            BuffRemindersDB = {}
        end
        for k, v in pairs(defaults) do
            if BuffRemindersDB[k] == nil then
                if type(v) == "table" then
                    BuffRemindersDB[k] = {}
                    for k2, v2 in pairs(v) do
                        BuffRemindersDB[k][k2] = v2
                    end
                else
                    BuffRemindersDB[k] = v
                end
            end
        end
        for _, buffData in ipairs(RaidBuffs) do
            local key = buffData[2]
            if BuffRemindersDB.enabledBuffs[key] == nil then
                BuffRemindersDB.enabledBuffs[key] = true
            end
        end
        for _, buffData in ipairs(PresenceBuffs) do
            local key = buffData[2]
            if BuffRemindersDB.enabledBuffs[key] == nil then
                BuffRemindersDB.enabledBuffs[key] = true
            end
        end
        local seenInitGroups = {}
        for _, buffData in ipairs(PersonalBuffs) do
            local settingKey = GetBuffSettingKey(buffData)
            if not seenInitGroups[settingKey] then
                seenInitGroups[settingKey] = true
                if BuffRemindersDB.enabledBuffs[settingKey] == nil then
                    BuffRemindersDB.enabledBuffs[settingKey] = true
                end
            end
        end
        for _, buffData in ipairs(SelfBuffs) do
            local key = buffData[2]
            if BuffRemindersDB.enabledBuffs[key] == nil then
                BuffRemindersDB.enabledBuffs[key] = true
            end
        end

        SLASH_BUFFREMINDERS1 = "/br"
        SLASH_BUFFREMINDERS2 = "/buffreminders"
        SlashCmdList["BUFFREMINDERS"] = SlashHandler

        -- Register with WoW's Interface Options
        local settingsPanel = CreateFrame("Frame")
        settingsPanel.name = "BuffReminders"

        local title = settingsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("BuffReminders")

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
        slashInfo:SetText("Slash commands: /br or /buffreminders")

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
    elseif event == "READY_CHECK" then
        -- Cancel any existing timer
        if readyCheckTimer then
            readyCheckTimer:Cancel()
        end
        inReadyCheck = true
        if not inCombat then
            UpdateDisplay()
        end
        -- Start timer to reset ready check state
        local duration = BuffRemindersDB.readyCheckDuration or 15
        readyCheckTimer = C_Timer.NewTimer(duration, function()
            inReadyCheck = false
            readyCheckTimer = nil
            UpdateDisplay()
        end)
    end
end)
