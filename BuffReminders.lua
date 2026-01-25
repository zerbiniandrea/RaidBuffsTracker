local addonName, _ = ...

---@type RaidBuff[]
local RaidBuffs = {
    { spellID = 1459, key = "intellect", name = "Arcane Intellect", class = "MAGE" },
    { spellID = 6673, key = "attackPower", name = "Battle Shout", class = "WARRIOR" },
    {
        spellID = {
            381732,
            381741,
            381746,
            381748,
            381749,
            381750,
            381751,
            381752,
            381753,
            381754,
            381756,
            381757,
            381758,
        },
        key = "bronze",
        name = "Blessing of the Bronze",
        class = "EVOKER",
    },
    { spellID = 1126, key = "versatility", name = "Mark of the Wild", class = "DRUID" },
    { spellID = 21562, key = "stamina", name = "Power Word: Fortitude", class = "PRIEST" },
    { spellID = 462854, key = "skyfury", name = "Skyfury", class = "SHAMAN" },
}

---@type PresenceBuff[]
local PresenceBuffs = {
    { spellID = 381637, key = "atrophicPoison", name = "Atrophic Poison", class = "ROGUE", missingText = "NO\nPOISON" },
    { spellID = 465, key = "devotionAura", name = "Devotion Aura", class = "PALADIN", missingText = "NO\nAURA" },
    {
        spellID = 20707,
        key = "soulstone",
        name = "Soulstone",
        class = "WARLOCK",
        missingText = "NO\nSTONE",
        infoTooltip = "Ready Check Only|This buff is only shown during ready checks.",
    },
}

---@type PersonalBuff[]
local PersonalBuffs = {
    -- Beacons (alphabetical: Faith, Light)
    {
        spellID = 156910,
        key = "beaconOfFaith",
        name = "Beacon of Faith",
        class = "PALADIN",
        missingText = "NO\nFAITH",
        groupId = "beacons",
    },
    {
        spellID = 53563,
        key = "beaconOfLight",
        name = "Beacon of Light",
        class = "PALADIN",
        missingText = "NO\nLIGHT",
        groupId = "beacons",
    },
    {
        spellID = 974,
        key = "earthShieldOthers",
        name = "Earth Shield",
        class = "SHAMAN",
        missingText = "NO\nES",
        infoTooltip = "May Show Extra Icon|Until you cast this, you might see both this and the Water/Lightning Shield reminder. I can't tell if you want Earth Shield on yourself, or Earth Shield on an ally + Water/Lightning Shield on yourself.",
    },
    {
        spellID = 369459,
        key = "sourceOfMagic",
        name = "Source of Magic",
        class = "EVOKER",
        beneficiaryRole = "HEALER",
        missingText = "NO\nSOURCE",
    },
    {
        spellID = 474750,
        key = "symbioticRelationship",
        name = "Symbiotic Relationship",
        class = "DRUID",
        missingText = "NO\nLINK",
    },
}

---@type SelfBuff[]
local SelfBuffs = {
    -- Paladin weapon rites (alphabetical: Adjuration, Sanctification)
    {
        spellID = 433583,
        key = "riteOfAdjuration",
        name = "Rite of Adjuration",
        class = "PALADIN",
        missingText = "NO\nRITE",
        enchantID = 7144,
        groupId = "paladinRites",
    },
    {
        spellID = 433568,
        key = "riteOfSanctification",
        name = "Rite of Sanctification",
        class = "PALADIN",
        missingText = "NO\nRITE",
        enchantID = 7143,
        groupId = "paladinRites",
    },
    -- Shadowform will drop during Void Form, but that only happens in combat. We're happy enough just checking Shadowform before going into combat.
    { spellID = 232698, key = "shadowform", name = "Shadowform", class = "PRIEST", missingText = "NO\nFORM" },
    -- Shaman weapon imbues (alphabetical: Earthliving, Flametongue, Windfury)
    {
        spellID = 382021,
        key = "earthlivingWeapon",
        name = "Earthliving Weapon",
        class = "SHAMAN",
        missingText = "NO\nEL",
        enchantID = 6498,
        groupId = "shamanImbues",
    },
    {
        spellID = 318038,
        key = "flametongueWeapon",
        name = "Flametongue Weapon",
        class = "SHAMAN",
        missingText = "NO\nFT",
        enchantID = 5400,
        groupId = "shamanImbues",
    },
    {
        spellID = 33757,
        key = "windfuryWeapon",
        name = "Windfury Weapon",
        class = "SHAMAN",
        missingText = "NO\nWF",
        enchantID = 5401,
        groupId = "shamanImbues",
    },
    -- Shaman shields (alphabetical: Earth, Lightning, Water)
    -- With Elemental Orbit: need Earth Shield (passive self-buff)
    {
        spellID = 974, -- Earth Shield spell (for icon and spell check)
        buffIdOverride = 383648, -- The passive buff to check for
        key = "earthShieldSelfEO",
        name = "Earth Shield (Self)",
        class = "SHAMAN",
        missingText = "NO\nSELF ES",
        requiresTalentSpellID = 383010,
        groupId = "shamanShields",
    },
    -- With Elemental Orbit: need Lightning Shield or Water Shield
    {
        spellID = { 192106, 52127 },
        key = "waterLightningShieldEO",
        name = "Water/Lightning Shield",
        class = "SHAMAN",
        missingText = "NO\nSHIELD",
        requiresTalentSpellID = 383010,
        groupId = "shamanShields",
        iconByRole = { HEALER = 52127, DAMAGER = 192106, TANK = 192106 },
    },
    -- Without Elemental Orbit: need either Earth Shield, Lightning Shield, or Water Shield on self
    {
        spellID = { 974, 192106, 52127 },
        key = "shamanShieldBasic",
        name = "Shield (No Talent)",
        class = "SHAMAN",
        missingText = "NO\nSHIELD",
        excludeTalentSpellID = 383010,
        groupId = "shamanShields",
        iconByRole = { HEALER = 52127, DAMAGER = 192106, TANK = 192106 },
    },
}

---@type table<string, BuffGroup>
local BuffGroups = {
    beacons = { displayName = "Beacons", missingText = "NO\nBEACONS" },
    shamanImbues = { displayName = "Shaman Imbues" },
    paladinRites = { displayName = "Paladin Rites" },
    shamanShields = { displayName = "Shaman Shields" },
}

---Get the effective setting key for a buff (groupId if present, otherwise individual key)
---@param buff RaidBuff|PresenceBuff|PersonalBuff|SelfBuff
---@return string
local function GetBuffSettingKey(buff)
    return buff.groupId or buff.key
end

---Generate a unique key for a custom buff
---@param spellID number
---@return string
local function GenerateCustomBuffKey(spellID)
    return "custom_" .. spellID .. "_" .. time()
end

---Validate a spell ID exists via GetSpellInfo
---@param spellID number
---@return boolean valid
---@return string? name
---@return number? iconID
local function ValidateSpellID(spellID)
    local name, _, iconID
    pcall(function()
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            name = info.name
            iconID = info.iconID
        end
    end)
    return name ~= nil, name, iconID
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
-- Note: enabledBuffs defaults to all enabled - only set false to disable by default
local defaults = {
    position = { point = "CENTER", x = 0, y = 0 },
    locked = true,
    enabledBuffs = {},
    iconSize = 64,
    spacing = 0.2, -- multiplier of iconSize (reset ratios default)
    textScale = 0.34, -- multiplier of iconSize (reset ratios default)
    showBuffReminder = true,
    showOnlyInGroup = false,
    showOnlyInInstance = false,
    showOnlyPlayerClassBuff = false,
    showOnlyOnReadyCheck = false,
    readyCheckDuration = 15, -- seconds
    growDirection = "CENTER", -- "LEFT", "CENTER", "RIGHT"
    showExpirationGlow = true,
    expirationThreshold = 15, -- minutes
    glowStyle = 1, -- 1=Orange, 2=Gold, 3=Yellow, 4=White, 5=Red
    optionsPanelScale = 1.2, -- base scale (displayed as 100%)
}

-- Constants
local TEXCOORD_INSET = 0.08
local BORDER_PADDING = 2
local MISSING_TEXT_SCALE = 0.6 -- scale for "NO X" warning text
local OPTIONS_BASE_SCALE = 1.2

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

---Check if a buff is enabled (defaults to true if not explicitly set to false)
---@param key string
---@return boolean
local function IsBuffEnabled(key)
    local db = BuffRemindersDB
    return db.enabledBuffs[key] ~= false
end

---Check if a unit is a valid group member for buff tracking
---Excludes: non-existent, dead/ghost, disconnected, hostile (cross-faction in open world)
---@param unit string
---@return boolean
local function IsValidGroupMember(unit)
    return UnitExists(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) and UnitCanAssist("player", unit)
end

---Iterate over valid group members, calling callback(unit) for each
---Handles raid vs party unit naming automatically
---@param callback fun(unit: string)
local function IterateGroupMembers(callback)
    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers()

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
            callback(unit)
        end
    end
end

---Calculate font size based on settings, with optional scale multiplier
---@param scale? number
---@return number
local function GetFontSize(scale)
    local db = BuffRemindersDB
    local baseSize = db.iconSize * (db.textScale or defaults.textScale)
    return math.floor(baseSize * (scale or 1))
end

---Format remaining time in seconds to a short string (e.g., "5m" or "30s")
---@param seconds number
---@return string
local function FormatRemainingTime(seconds)
    local mins = math.floor(seconds / 60)
    if mins > 0 then
        return mins .. "m"
    else
        return math.floor(seconds) .. "s"
    end
end

---Get classes present in the group
---@return table<ClassName, boolean>
local function GetGroupClasses()
    local classes = {}

    if GetNumGroupMembers() == 0 then
        if playerClass then
            classes[playerClass] = true
        end
        return classes
    end

    IterateGroupMembers(function(unit)
        local _, class = UnitClass(unit)
        if class then
            classes[class] = true
        end
    end)
    return classes
end

---Check if unit has a specific buff (handles single spellID or table of spellIDs)
---@param unit string
---@param spellIDs SpellID
---@return boolean hasBuff
---@return number? remainingTime
---@return string? sourceUnit
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

---Get player's current role
---@return RoleType?
local function GetPlayerRole()
    local spec = GetSpecialization()
    if spec then
        return GetSpecializationRole(spec)
    end
    return nil
end

---Get spell texture (handles table of spellIDs and role-based icons)
---@param spellIDs SpellID
---@param iconByRole? table<RoleType, number>
---@return number? textureID
local function GetBuffTexture(spellIDs, iconByRole)
    local id
    -- Check for role-based icon override
    if iconByRole then
        local role = GetPlayerRole()
        if role and iconByRole[role] then
            id = iconByRole[role]
        end
    end
    -- Fall back to spellIDs
    if not id then
        id = type(spellIDs) == "table" and spellIDs[1] or spellIDs
    end
    local texture
    pcall(function()
        texture = C_Spell.GetSpellTexture(id)
    end)
    return texture
end

---Count group members missing a buff
---@param spellIDs SpellID
---@param buffKey? string Used for class benefit filtering
---@return number missing
---@return number total
---@return number? minRemaining
local function CountMissingBuff(spellIDs, buffKey)
    local missing = 0
    local total = 0
    local minRemaining = nil
    local beneficiaries = BuffBeneficiaries[buffKey]

    if GetNumGroupMembers() == 0 then
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

    IterateGroupMembers(function(unit)
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
    end)

    return missing, total, minRemaining
end

---Count group members with a presence buff
---@param spellIDs SpellID
---@return number count
---@return number? minRemaining
local function CountPresenceBuff(spellIDs)
    local found = 0
    local minRemaining = nil

    if GetNumGroupMembers() == 0 then
        local hasBuff, remaining = UnitHasBuff("player", spellIDs)
        if hasBuff then
            found = 1
            minRemaining = remaining
        end
        return found, minRemaining
    end

    IterateGroupMembers(function(unit)
        local hasBuff, remaining = UnitHasBuff(unit, spellIDs)
        if hasBuff then
            found = found + 1
            if remaining then
                if not minRemaining or remaining < minRemaining then
                    minRemaining = remaining
                end
            end
        end
    end)

    return found, minRemaining
end

---Check if player's buff is active on anyone in the group
---@param spellID number
---@param role? RoleType Only check units with this role
---@return boolean
local function IsPlayerBuffActive(spellID, role)
    local found = false

    IterateGroupMembers(function(unit)
        if found then
            return
        end
        if not role or UnitGroupRolesAssigned(unit) == role then
            local hasBuff, _, sourceUnit = UnitHasBuff(unit, spellID)
            if hasBuff and sourceUnit and UnitIsUnit(sourceUnit, "player") then
                found = true
            end
        end
    end)

    return found
end

---Check if player should cast their personal buff (returns true if a beneficiary needs it)
---@param spellIDs SpellID
---@param requiredClass ClassName
---@param beneficiaryRole? RoleType
---@return boolean? Returns nil if player can't provide this buff
local function ShouldShowPersonalBuff(spellIDs, requiredClass, beneficiaryRole)
    if playerClass ~= requiredClass then
        return nil
    end

    local spellID = (type(spellIDs) == "table" and spellIDs[1] or spellIDs) --[[@as number]]
    if not IsPlayerSpell(spellID) then
        return nil
    end

    -- Personal buffs require a group (you cast them on others)
    if GetNumGroupMembers() == 0 then
        return nil
    end

    return not IsPlayerBuffActive(spellID, beneficiaryRole)
end

---Check if player should cast their self buff or weapon imbue (returns true if missing)
---@param spellID SpellID
---@param requiredClass ClassName
---@param enchantID? number For weapon imbues, checks if this enchant is on either weapon
---@param requiresTalent? number Only show if player HAS this talent
---@param excludeTalent? number Hide if player HAS this talent
---@param buffIdOverride? number Separate buff ID to check (if different from spellID)
---@return boolean? Returns nil if player can't/shouldn't use this buff
local function ShouldShowSelfBuff(spellID, requiredClass, enchantID, requiresTalent, excludeTalent, buffIdOverride)
    if playerClass ~= requiredClass then
        return nil
    end

    -- Talent checks (before spell availability check for talent-gated buffs)
    if requiresTalent and not IsPlayerSpell(requiresTalent) then
        return nil
    end
    if excludeTalent and IsPlayerSpell(excludeTalent) then
        return nil
    end

    -- For buffs with multiple spellIDs (like shields), check if player knows ANY of them
    local spellIDs = type(spellID) == "table" and spellID or { spellID }
    local knowsAnySpell = false
    for _, id in ipairs(spellIDs) do
        if IsPlayerSpell(id) then
            knowsAnySpell = true
            break
        end
    end
    if not knowsAnySpell then
        return nil
    end

    -- Weapon imbue: check if this specific enchant is on either weapon
    if enchantID then
        local _, _, _, mainHandEnchantID, _, _, _, offHandEnchantID = GetWeaponEnchantInfo()
        return mainHandEnchantID ~= enchantID and offHandEnchantID ~= enchantID
    end

    -- Regular buff check - use buffIdOverride if provided, otherwise use spellID
    local hasBuff, _ = UnitHasBuff("player", buffIdOverride or spellID)
    return not hasBuff
end

-- Forward declarations
local UpdateDisplay, PositionBuffFrames, UpdateAnchor, ShowGlowDemo, ToggleTestMode, RefreshTestDisplay
local ShowCustomBuffModal

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

-- Hide a buff frame and clear its glow
local function HideFrame(frame)
    frame:Hide()
    SetExpirationGlow(frame, false)
end

-- Create icon frame for a buff
local function CreateBuffFrame(buff, _)
    local frame = CreateFrame("Frame", "BuffReminders_" .. buff.key, mainFrame)
    frame.key = buff.key
    frame.spellIDs = buff.spellID
    frame.displayName = buff.name

    local db = BuffRemindersDB
    frame:SetSize(db.iconSize, db.iconSize)

    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
    frame.icon:SetDesaturated(false)
    frame.icon:SetVertexColor(1, 1, 1, 1)
    local texture = GetBuffTexture(buff.spellID, buff.iconByRole)
    if texture then
        frame.icon:SetTexture(texture)
    end

    -- Border (background behind icon)
    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetPoint("TOPLEFT", -BORDER_PADDING, BORDER_PADDING)
    frame.border:SetPoint("BOTTOMRIGHT", BORDER_PADDING, -BORDER_PADDING)
    frame.border:SetColorTexture(0, 0, 0, 1)

    -- Count text (font size scales with icon size)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    frame.count:SetPoint("CENTER", 0, 0)
    frame.count:SetTextColor(1, 1, 1, 1)
    frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(), "OUTLINE")

    -- "BUFF!" text for the class that provides this buff
    frame.isPlayerBuff = (playerClass == buff.class)
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
    for _, buff in ipairs(RaidBuffs) do
        local frame = buffFrames[buff.key]
        if frame and frame:IsShown() then
            table.insert(visibleFrames, frame)
        end
    end
    for _, buff in ipairs(PresenceBuffs) do
        local frame = buffFrames[buff.key]
        if frame and frame:IsShown() then
            table.insert(visibleFrames, frame)
        end
    end
    for _, buff in ipairs(PersonalBuffs) do
        local frame = buffFrames[buff.key]
        if frame and frame:IsShown() then
            table.insert(visibleFrames, frame)
        end
    end
    for _, buff in ipairs(SelfBuffs) do
        local frame = buffFrames[buff.key]
        if frame and frame:IsShown() then
            table.insert(visibleFrames, frame)
        end
    end
    -- Custom buffs (sorted by key for consistent order)
    local customBuffs = db.customBuffs or {}
    local sortedCustomKeys = {}
    for key in pairs(customBuffs) do
        table.insert(sortedCustomKeys, key)
    end
    table.sort(sortedCustomKeys)
    for _, key in ipairs(sortedCustomKeys) do
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
        HideFrame(frame)
        if frame.testText then
            frame.testText:Hide()
        end
    end

    local glowShown = false

    -- Show ALL raid buffs (ignore enabledBuffs)
    for i, buff in ipairs(RaidBuffs) do
        local frame = buffFrames[buff.key]
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
    for _, buff in ipairs(PresenceBuffs) do
        local frame = buffFrames[buff.key]
        if frame then
            frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
            frame.count:SetText(buff.missingText or "")
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(STANDARD_TEXT_FONT, GetFontSize(0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL personal buffs (one per group)
    local seenGroups = {}
    for _, buff in ipairs(PersonalBuffs) do
        local frame = buffFrames[buff.key]
        if frame then
            if buff.groupId and seenGroups[buff.groupId] then
                frame:Hide()
            else
                if buff.groupId then
                    seenGroups[buff.groupId] = true
                    local groupInfo = BuffGroups[buff.groupId]
                    frame.count:SetText(groupInfo and groupInfo.missingText or "")
                else
                    frame.count:SetText(buff.missingText or "")
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
    for _, buff in ipairs(SelfBuffs) do
        local frame = buffFrames[buff.key]
        if frame then
            frame.count:SetText(buff.missingText or "")
            frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(STANDARD_TEXT_FONT, GetFontSize(0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL custom buffs (self buffs)
    if db.customBuffs then
        for _, customBuff in pairs(db.customBuffs) do
            local frame = buffFrames[customBuff.key]
            if frame then
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
                frame.count:SetText(customBuff.missingText or "NO\nBUFF")
                if frame.testText and testModeData.showLabels then
                    frame.testText:SetFont(STANDARD_TEXT_FONT, GetFontSize(0.6), "OUTLINE")
                    frame.testText:Show()
                end
                frame:Show()
            end
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
    for _, buff in ipairs(RaidBuffs) do
        local frame = buffFrames[buff.key]
        local showBuff = (not db.showOnlyPlayerClassBuff or buff.class == playerClass)
            and (not presentClasses or presentClasses[buff.class])

        if frame and IsBuffEnabled(buff.key) and showBuff then
            local missing, total, minRemaining = CountMissingBuff(buff.spellID, buff.key)
            local expiringSoon = db.showExpirationGlow and minRemaining and minRemaining < (db.expirationThreshold * 60)
            if missing > 0 then
                local buffed = total - missing
                frame.count:SetText(buffed .. "/" .. total)
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, expiringSoon)
            elseif expiringSoon then
                -- Everyone has buff but expiring soon - show remaining time with glow
                ---@cast minRemaining number
                frame.count:SetText(FormatRemainingTime(minRemaining))
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, true)
            else
                HideFrame(frame)
            end
        elseif frame then
            HideFrame(frame)
        end
    end

    -- Process presence buffs (need at least 1 person to have them)
    for _, buff in ipairs(PresenceBuffs) do
        local frame = buffFrames[buff.key]
        local readyCheckOnly = buff.infoTooltip and buff.infoTooltip:match("^Ready Check Only")
        local showBuff = (not readyCheckOnly or inReadyCheck)
            and (not db.showOnlyPlayerClassBuff or buff.class == playerClass)
            and (not presentClasses or presentClasses[buff.class])

        if frame and IsBuffEnabled(buff.key) and showBuff then
            local count, minRemaining = CountPresenceBuff(buff.spellID)
            local expiringSoon = db.showExpirationGlow and minRemaining and minRemaining < (db.expirationThreshold * 60)
            if count == 0 then
                -- Nobody has it - show as missing
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
                frame.count:SetText(buff.missingText or "")
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, false)
            elseif expiringSoon then
                -- Has buff but expiring soon - show remaining time with glow
                ---@cast minRemaining number
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(), "OUTLINE")
                frame.count:SetText(FormatRemainingTime(minRemaining))
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, true)
            else
                -- At least 1 person has it and not expiring - all good
                HideFrame(frame)
            end
        elseif frame then
            HideFrame(frame)
        end
    end

    -- Process personal buffs (player's own buff responsibility)
    local visibleGroups = {} -- Track visible buffs by groupId for merging
    for _, buff in ipairs(PersonalBuffs) do
        local frame = buffFrames[buff.key]
        local settingKey = GetBuffSettingKey(buff)

        if frame and IsBuffEnabled(settingKey) then
            local shouldShow = ShouldShowPersonalBuff(buff.spellID, buff.class, buff.beneficiaryRole)
            if shouldShow then
                frame.icon:SetAllPoints()
                frame.icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
                frame.count:SetText(buff.missingText or "")
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, false)
                -- Track for group merging
                if buff.groupId then
                    visibleGroups[buff.groupId] = visibleGroups[buff.groupId] or {}
                    table.insert(visibleGroups[buff.groupId], { frame = frame, spellID = buff.spellID })
                end
            else
                HideFrame(frame)
            end
        elseif frame then
            HideFrame(frame)
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

    -- Process self buffs (player's own buff on themselves, including weapon imbues)
    for _, buff in ipairs(SelfBuffs) do
        local frame = buffFrames[buff.key]
        local settingKey = buff.groupId or buff.key

        if frame and IsBuffEnabled(settingKey) then
            local shouldShow = ShouldShowSelfBuff(
                buff.spellID,
                buff.class,
                buff.enchantID,
                buff.requiresTalentSpellID,
                buff.excludeTalentSpellID,
                buff.buffIdOverride
            )
            if shouldShow then
                frame.icon:SetAllPoints()
                frame.icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
                -- Update icon based on current role (for role-dependent buffs like shields)
                if buff.iconByRole then
                    local texture = GetBuffTexture(buff.spellID, buff.iconByRole)
                    if texture then
                        frame.icon:SetTexture(texture)
                    end
                end
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
                frame.count:SetText(buff.missingText or "")
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, false)
            else
                HideFrame(frame)
            end
        elseif frame then
            HideFrame(frame)
        end
    end

    -- Process custom buffs (self buffs only - show if player doesn't have the buff)
    if db.customBuffs then
        for _, customBuff in pairs(db.customBuffs) do
            local frame = buffFrames[customBuff.key]
            -- Check class filter (nil means any class)
            local classMatch = not customBuff.class or customBuff.class == playerClass
            if frame and IsBuffEnabled(customBuff.key) and classMatch then
                local hasBuff = UnitHasBuff("player", customBuff.spellID)
                if not hasBuff then
                    frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(MISSING_TEXT_SCALE), "OUTLINE")
                    frame.count:SetText(customBuff.missingText or "NO\nBUFF")
                    frame:Show()
                    anyVisible = true
                    SetExpirationGlow(frame, false)
                else
                    HideFrame(frame)
                end
            elseif frame then
                HideFrame(frame)
            end
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

    for i, buff in ipairs(RaidBuffs) do
        buffFrames[buff.key] = CreateBuffFrame(buff, i)
    end

    for i, buff in ipairs(PresenceBuffs) do
        buffFrames[buff.key] = CreateBuffFrame(buff, #RaidBuffs + i)
        buffFrames[buff.key].isPresenceBuff = true
    end

    for i, buff in ipairs(PersonalBuffs) do
        buffFrames[buff.key] = CreateBuffFrame(buff, #RaidBuffs + #PresenceBuffs + i)
        buffFrames[buff.key].isPersonalBuff = true
    end

    for i, buff in ipairs(SelfBuffs) do
        buffFrames[buff.key] = CreateBuffFrame(buff, #RaidBuffs + #PresenceBuffs + #PersonalBuffs + i)
        buffFrames[buff.key].isSelfBuff = true
    end

    -- Create frames for custom buffs (always self buffs)
    if db.customBuffs then
        for _, customBuff in pairs(db.customBuffs) do
            local frame = CreateBuffFrame(customBuff, 0)
            frame.isCustomBuff = true
            buffFrames[customBuff.key] = frame
        end
    end

    mainFrame:Hide()
end

---Create a frame for a newly added custom buff (called at runtime when adding buffs)
---@param customBuff CustomBuff
local function CreateCustomBuffFrameRuntime(customBuff)
    if not mainFrame then
        return
    end
    local frame = CreateBuffFrame(customBuff, 0)
    frame.isCustomBuff = true
    buffFrames[customBuff.key] = frame
end

---Remove a custom buff frame (called at runtime when deleting buffs)
---@param key string
local function RemoveCustomBuffFrame(key)
    local frame = buffFrames[key]
    if frame then
        frame:Hide()
        frame:SetParent(nil)
        buffFrames[key] = nil
    end
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
    tinsert(UISpecialFrames, "BuffRemindersOptions")

    -- Addon icon
    local addonIcon = panel:CreateTexture(nil, "ARTWORK")
    addonIcon:SetSize(28, 28)
    addonIcon:SetPoint("TOPLEFT", 12, -8)
    addonIcon:SetTexture("Interface\\AddOns\\BuffReminders\\icon.tga")
    addonIcon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)

    -- Title (next to icon)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", addonIcon, "RIGHT", 8, 0)
    title:SetText("BuffReminders")

    -- Scale controls (top right area) - using buttons to avoid slider scaling issues
    -- Base scale is OPTIONS_BASE_SCALE (displayed as 100%), range is 80%-150%
    local BASE_SCALE = OPTIONS_BASE_SCALE
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

    -- Setup tooltip for a widget
    local function SetupTooltip(widget, tooltipTitle, tooltipDesc, anchor)
        widget:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipTitle)
            if tooltipDesc then
                GameTooltip:AddLine(tooltipDesc, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        widget:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Create buff checkbox (compact, for left column)
    -- spellIDs can be a single ID, a table of IDs (for multi-rank spells), or a table of tables (for grouped buffs with multiple icons)
    -- infoTooltip is optional: "Title|Description" format shows a "?" icon with tooltip
    local function CreateBuffCheckbox(x, y, spellIDs, key, displayName, infoTooltip)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetChecked(BuffRemindersDB.enabledBuffs[key])
        cb:SetScript("OnClick", function(self)
            BuffRemindersDB.enabledBuffs[key] = self:GetChecked()
            UpdateDisplay()
        end)

        -- Handle multiple icons for grouped buffs (dedupe by texture)
        local lastAnchor = cb
        local spellList = type(spellIDs) == "table" and spellIDs or { spellIDs }
        local seenTextures = {}
        for _, spellID in ipairs(spellList) do
            local texture = GetBuffTexture(spellID)
            if texture and not seenTextures[texture] then
                seenTextures[texture] = true
                local icon = panel:CreateTexture(nil, "ARTWORK")
                icon:SetSize(18, 18)
                icon:SetPoint("LEFT", lastAnchor, lastAnchor == cb and "RIGHT" or "RIGHT", 2, 0)
                icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
                icon:SetTexture(texture)
                lastAnchor = icon
            end
        end

        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        label:SetText(displayName)

        -- Add info tooltip icon if specified
        if infoTooltip then
            local infoIcon = panel:CreateTexture(nil, "ARTWORK")
            infoIcon:SetSize(14, 14)
            infoIcon:SetPoint("LEFT", label, "RIGHT", 4, 0)
            infoIcon:SetAtlas("QuestNormal")
            -- Create invisible button for tooltip
            local infoBtn = CreateFrame("Button", nil, panel)
            infoBtn:SetSize(14, 14)
            infoBtn:SetPoint("CENTER", infoIcon, "CENTER", 0, 0)
            -- Parse "Title|Description" format
            local tooltipTitle, tooltipDesc = infoTooltip:match("^([^|]+)|(.+)$")
            if not tooltipTitle then
                tooltipTitle, tooltipDesc = infoTooltip, nil
            end
            infoBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tooltipTitle, 1, 0.82, 0)
                if tooltipDesc then
                    GameTooltip:AddLine(tooltipDesc, 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            infoBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end

        panel.buffCheckboxes[key] = cb
        return y - ITEM_HEIGHT
    end

    -- Create checkbox with label (for right column)
    local function CreateCheckbox(x, y, labelText, checked, onClick, tooltip)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetChecked(checked)
        cb:SetScript("OnClick", onClick)

        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(labelText)
        cb.label = label

        if tooltip then
            SetupTooltip(cb, labelText, tooltip)
        end

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
        SetupTooltip(valueBtn, "Click to type a value", nil, "ANCHOR_TOP")

        slider:SetScript("OnValueChanged", function(self, val)
            val = math.floor(val)
            value:SetText(val .. (suffix or ""))
            onChange(val)
        end)

        slider.label = label
        return slider, value, y - 24
    end

    -- Render checkboxes for any buff array
    -- Handles grouping automatically if groupId field is present
    local function RenderBuffCheckboxes(x, y, buffArray)
        -- Pass 1: Collect grouped spell IDs (flatten tables)
        local groupSpells = {}
        for _, buff in ipairs(buffArray) do
            if buff.groupId then
                groupSpells[buff.groupId] = groupSpells[buff.groupId] or {}
                -- Flatten: buff.spellID can be a number or table of numbers
                local spellList = type(buff.spellID) == "table" and buff.spellID or { buff.spellID }
                for _, id in ipairs(spellList) do
                    table.insert(groupSpells[buff.groupId], id)
                end
            end
        end

        -- Pass 2: Render with group deduplication
        local seenGroups = {}
        for _, buff in ipairs(buffArray) do
            if buff.groupId then
                if not seenGroups[buff.groupId] then
                    seenGroups[buff.groupId] = true
                    local groupInfo = BuffGroups[buff.groupId]
                    y = CreateBuffCheckbox(
                        x,
                        y,
                        groupSpells[buff.groupId],
                        buff.groupId,
                        groupInfo.displayName,
                        buff.infoTooltip
                    )
                end
            else
                y = CreateBuffCheckbox(x, y, buff.spellID, buff.key, buff.name, buff.infoTooltip)
            end
        end

        return y
    end

    -- ========== LEFT COLUMN: BUFF SELECTION ==========
    local leftY = startY

    -- Raid Buffs header
    _, leftY = CreateSectionHeader(panel, "Raid Buffs", leftColX, leftY)
    local raidNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    raidNote:SetPoint("TOPLEFT", leftColX, leftY)
    raidNote:SetText("(for the whole group)")
    leftY = leftY - 14
    leftY = RenderBuffCheckboxes(leftColX, leftY, RaidBuffs)

    leftY = leftY - SECTION_SPACING

    -- Presence Buffs header
    _, leftY = CreateSectionHeader(panel, "Presence Buffs", leftColX, leftY)
    local presenceNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    presenceNote:SetPoint("TOPLEFT", leftColX, leftY)
    presenceNote:SetText("(at least 1 person needs)")
    leftY = leftY - 14
    leftY = RenderBuffCheckboxes(leftColX, leftY, PresenceBuffs)

    leftY = leftY - SECTION_SPACING

    -- Personal Buffs header
    _, leftY = CreateSectionHeader(panel, "Personal Buffs", leftColX, leftY)
    local personalNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    personalNote:SetPoint("TOPLEFT", leftColX, leftY)
    personalNote:SetText("(buffs you cast on others)")
    leftY = leftY - 14
    leftY = RenderBuffCheckboxes(leftColX, leftY, PersonalBuffs)

    leftY = leftY - SECTION_SPACING

    -- Self Buffs header
    _, leftY = CreateSectionHeader(panel, "Self Buffs", leftColX, leftY)
    local selfNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    selfNote:SetPoint("TOPLEFT", leftColX, leftY)
    selfNote:SetText("(buffs on yourself)")
    leftY = leftY - 14
    leftY = RenderBuffCheckboxes(leftColX, leftY, SelfBuffs)

    leftY = leftY - SECTION_SPACING

    -- Custom Buffs header
    _, leftY = CreateSectionHeader(panel, "Custom Buffs", leftColX, leftY)
    local customNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    customNote:SetPoint("TOPLEFT", leftColX, leftY)
    customNote:SetText("(user-defined buffs)")
    leftY = leftY - 14

    -- Container for custom buff rows (for dynamic refresh)
    local customBuffsContainer = CreateFrame("Frame", nil, panel)
    customBuffsContainer:SetPoint("TOPLEFT", leftColX, leftY)
    customBuffsContainer:SetSize(LEFT_COL_WIDTH, 200)
    panel.customBuffsContainer = customBuffsContainer
    panel.customBuffRows = {}

    -- Function to render custom buff rows
    local function RenderCustomBuffRows()
        -- Clear existing rows
        for _, row in ipairs(panel.customBuffRows) do
            row:Hide()
            row:SetParent(nil)
        end
        panel.customBuffRows = {}

        local db = BuffRemindersDB
        local customY = 0

        -- Sort custom buffs by key for consistent order
        local sortedKeys = {}
        if db.customBuffs then
            for key in pairs(db.customBuffs) do
                table.insert(sortedKeys, key)
            end
        end
        table.sort(sortedKeys)

        for _, key in ipairs(sortedKeys) do
            local customBuff = db.customBuffs[key]
            local row = CreateFrame("Frame", nil, customBuffsContainer)
            row:SetSize(LEFT_COL_WIDTH, 20)
            row:SetPoint("TOPLEFT", 0, customY)

            -- Checkbox
            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetSize(20, 20)
            cb:SetPoint("LEFT", 0, 0)
            cb:SetChecked(IsBuffEnabled(key))
            cb:SetScript("OnClick", function(self)
                BuffRemindersDB.enabledBuffs[key] = self:GetChecked()
                UpdateDisplay()
            end)
            panel.buffCheckboxes[key] = cb

            -- Icon
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
            local texture = GetBuffTexture(customBuff.spellID)
            if texture then
                icon:SetTexture(texture)
            end

            -- Name label
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            label:SetWidth(100)
            label:SetJustifyH("LEFT")
            label:SetText(customBuff.name or ("Spell " .. customBuff.spellID))

            -- Edit button
            local editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            editBtn:SetSize(18, 18)
            editBtn:SetPoint("LEFT", label, "RIGHT", 2, 0)
            editBtn:SetNormalFontObject("GameFontHighlightSmall")
            editBtn:SetText("E")
            editBtn:SetScript("OnClick", function()
                ShowCustomBuffModal(key, RenderCustomBuffRows)
            end)
            SetupTooltip(editBtn, "Edit", "Edit this custom buff", "ANCHOR_TOP")

            -- Delete button
            local deleteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            deleteBtn:SetSize(18, 18)
            deleteBtn:SetPoint("LEFT", editBtn, "RIGHT", 2, 0)
            deleteBtn:SetNormalFontObject("GameFontHighlightSmall")
            deleteBtn:SetText("X")
            deleteBtn:SetScript("OnClick", function()
                StaticPopup_Show("BUFFREMINDERS_DELETE_CUSTOM", customBuff.name or key, nil, {
                    key = key,
                    refreshPanel = RenderCustomBuffRows,
                })
            end)
            SetupTooltip(deleteBtn, "Delete", "Delete this custom buff", "ANCHOR_TOP")

            table.insert(panel.customBuffRows, row)
            customY = customY - ITEM_HEIGHT
        end

        -- Add button
        local addBtn = CreateFrame("Button", nil, customBuffsContainer, "UIPanelButtonTemplate")
        addBtn:SetSize(130, 20)
        addBtn:SetPoint("TOPLEFT", 0, customY - 4)
        addBtn:SetText("+ Add Custom Buff")
        addBtn:SetNormalFontObject("GameFontHighlightSmall")
        addBtn:SetScript("OnClick", function()
            ShowCustomBuffModal(nil, RenderCustomBuffRows)
        end)
        table.insert(panel.customBuffRows, addBtn)

        -- Update container height and leftY
        customBuffsContainer:SetHeight(math.abs(customY) + 30)

        return customY - 30
    end

    panel.RenderCustomBuffRows = RenderCustomBuffRows
    local customHeight = RenderCustomBuffRows()
    leftY = leftY + customHeight

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
        end,
        "Only show buffs that your class can provide (e.g., warriors will only see Battle Shout)"
    )
    panel.playerClassCheckbox = playerClassCb

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
    SetupTooltip(
        resetPosBtn,
        "Reset Position",
        "Moves the buff tracker back to the center of the screen.",
        "ANCHOR_TOP"
    )

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
    SetupTooltip(resetRatiosBtn, "Reset Ratios", "Resets spacing and text size to recommended ratios.", "ANCHOR_TOP")

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

        -- Helper to refresh checkboxes for a buff array (handles grouping)
        local function RefreshBuffCheckboxes(buffArray)
            local seenGroups = {}
            for _, buff in ipairs(buffArray) do
                local settingKey = GetBuffSettingKey(buff)
                if buff.groupId then
                    if not seenGroups[buff.groupId] then
                        seenGroups[buff.groupId] = true
                        if optionsPanel.buffCheckboxes[settingKey] then
                            optionsPanel.buffCheckboxes[settingKey]:SetChecked(IsBuffEnabled(settingKey))
                        end
                    end
                else
                    if optionsPanel.buffCheckboxes[settingKey] then
                        optionsPanel.buffCheckboxes[settingKey]:SetChecked(IsBuffEnabled(settingKey))
                    end
                end
            end
        end

        RefreshBuffCheckboxes(RaidBuffs)
        RefreshBuffCheckboxes(PresenceBuffs)
        RefreshBuffCheckboxes(PersonalBuffs)
        RefreshBuffCheckboxes(SelfBuffs)
        -- Refresh custom buffs section
        if optionsPanel.RenderCustomBuffRows then
            optionsPanel.RenderCustomBuffRows()
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
        icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
        icon:SetTexture(GetBuffTexture(1459)) -- Arcane Intellect icon

        local border = iconFrame:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", -BORDER_PADDING, BORDER_PADDING)
        border:SetPoint("BOTTOMRIGHT", BORDER_PADDING, -BORDER_PADDING)
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

-- Delete confirmation dialog for custom buffs
StaticPopupDialogs["BUFFREMINDERS_DELETE_CUSTOM"] = {
    text = 'Delete custom buff "%s"?',
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.key then
            BuffRemindersDB.customBuffs[data.key] = nil
            BuffRemindersDB.enabledBuffs[data.key] = nil
            RemoveCustomBuffFrame(data.key)
            if data.refreshPanel then
                data.refreshPanel()
            end
            UpdateDisplay()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Custom buff add/edit modal dialog
local customBuffModal
ShowCustomBuffModal = function(existingKey, refreshPanelCallback)
    if customBuffModal then
        customBuffModal:Hide()
    end

    local MODAL_WIDTH = 320
    local MODAL_HEIGHT = 270
    local editingBuff = existingKey and BuffRemindersDB.customBuffs[existingKey] or nil

    local modal = CreateFrame("Frame", "BuffRemindersCustomBuffModal", UIParent, "BackdropTemplate")
    modal:SetSize(MODAL_WIDTH, MODAL_HEIGHT)
    modal:SetPoint("CENTER")
    modal:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    modal:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
    modal:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    modal:SetMovable(true)
    modal:EnableMouse(true)
    modal:RegisterForDrag("LeftButton")
    modal:SetScript("OnDragStart", modal.StartMoving)
    modal:SetScript("OnDragStop", modal.StopMovingOrSizing)
    modal:SetFrameStrata("DIALOG")
    modal:SetFrameLevel(200)
    tinsert(UISpecialFrames, "BuffRemindersCustomBuffModal")

    local title = modal:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(editingBuff and "Edit Custom Buff" or "Add Custom Buff")

    local closeBtn = CreateFrame("Button", nil, modal, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    local y = -40

    -- Spell ID input
    local spellIdLabel = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spellIdLabel:SetPoint("TOPLEFT", 20, y)
    spellIdLabel:SetText("Spell ID:")

    local spellIdBox = CreateFrame("EditBox", nil, modal, "InputBoxTemplate")
    spellIdBox:SetSize(100, 20)
    spellIdBox:SetPoint("LEFT", spellIdLabel, "RIGHT", 10, 0)
    spellIdBox:SetAutoFocus(false)
    spellIdBox:SetNumeric(true)
    if editingBuff then
        spellIdBox:SetText(tostring(editingBuff.spellID))
    end

    local lookupBtn = CreateFrame("Button", nil, modal, "UIPanelButtonTemplate")
    lookupBtn:SetSize(60, 20)
    lookupBtn:SetPoint("LEFT", spellIdBox, "RIGHT", 5, 0)
    lookupBtn:SetText("Lookup")

    y = y - 30

    -- Preview area
    local previewBg = modal:CreateTexture(nil, "BACKGROUND")
    previewBg:SetSize(MODAL_WIDTH - 40, 50)
    previewBg:SetPoint("TOPLEFT", 20, y)
    previewBg:SetColorTexture(0.05, 0.05, 0.05, 1)

    local previewIcon = modal:CreateTexture(nil, "ARTWORK")
    previewIcon:SetSize(40, 40)
    previewIcon:SetPoint("TOPLEFT", 25, y - 5)
    previewIcon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
    previewIcon:Hide()

    local previewName = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewName:SetPoint("TOPLEFT", previewIcon, "TOPRIGHT", 10, -2)
    previewName:SetText("")

    local previewDesc = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewDesc:SetPoint("TOPLEFT", previewName, "BOTTOMLEFT", 0, -2)
    previewDesc:SetWidth(MODAL_WIDTH - 100)
    previewDesc:SetHeight(24) -- Limit to ~2 lines
    previewDesc:SetJustifyH("LEFT")
    previewDesc:SetJustifyV("TOP")
    previewDesc:SetText("")
    previewDesc:SetTextColor(0.8, 0.8, 0.8)
    previewDesc:SetWordWrap(true)
    previewDesc:SetNonSpaceWrap(false)

    local previewError = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewError:SetPoint("CENTER", previewBg, "CENTER", 0, 0)
    previewError:SetText("Enter a spell ID and click Lookup")
    previewError:SetTextColor(0.6, 0.6, 0.6)

    -- State for validated spell
    local validatedSpellID = editingBuff and editingBuff.spellID or nil
    local validatedSpellName = editingBuff and editingBuff.name or nil

    if editingBuff then
        local valid, name, iconID = ValidateSpellID(editingBuff.spellID)
        if valid then
            previewIcon:SetTexture(iconID)
            previewIcon:Show()
            previewName:SetText(name or "")
            previewError:Hide()
            validatedSpellName = name
            -- Get spell description
            pcall(function()
                local desc = C_Spell.GetSpellDescription(editingBuff.spellID)
                if desc then
                    previewDesc:SetText(desc)
                end
            end)
        end
    end

    lookupBtn:SetScript("OnClick", function()
        local spellID = tonumber(spellIdBox:GetText())
        if not spellID then
            previewIcon:Hide()
            previewName:SetText("")
            previewDesc:SetText("")
            previewError:SetText("Invalid spell ID")
            previewError:SetTextColor(1, 0.3, 0.3)
            previewError:Show()
            validatedSpellID = nil
            validatedSpellName = nil
            return
        end

        local valid, name, iconID = ValidateSpellID(spellID)
        if valid then
            previewIcon:SetTexture(iconID)
            previewIcon:Show()
            previewName:SetText(name or "")
            previewError:Hide()
            validatedSpellID = spellID
            validatedSpellName = name
            -- Get spell description
            pcall(function()
                local desc = C_Spell.GetSpellDescription(spellID)
                if desc then
                    previewDesc:SetText(desc)
                end
            end)
        else
            previewIcon:Hide()
            previewName:SetText("")
            previewDesc:SetText("")
            previewError:SetText("Spell not found")
            previewError:SetTextColor(1, 0.3, 0.3)
            previewError:Show()
            validatedSpellID = nil
            validatedSpellName = nil
        end
    end)

    y = y - 60

    -- Advanced options toggle
    local advancedShown = false
    local advancedFrame = CreateFrame("Frame", nil, modal)
    advancedFrame:SetPoint("TOPLEFT", 20, y - 25)
    advancedFrame:SetSize(MODAL_WIDTH - 40, 85)
    advancedFrame:Hide()

    local advancedBtn = CreateFrame("Button", nil, modal)
    advancedBtn:SetPoint("TOPLEFT", 20, y)
    advancedBtn:SetSize(200, 20)
    local advancedText = advancedBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    advancedText:SetPoint("LEFT", 0, 0)
    advancedText:SetText("[+] Show Advanced Options")
    advancedText:SetTextColor(0.6, 0.8, 1)

    -- Advanced options
    local advY = 0

    -- Display Name
    local nameLabel = advancedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", 0, advY)
    nameLabel:SetText("Display Name:")

    local nameBox = CreateFrame("EditBox", nil, advancedFrame, "InputBoxTemplate")
    nameBox:SetSize(150, 18)
    nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 5, 0)
    nameBox:SetAutoFocus(false)
    if editingBuff and editingBuff.name then
        nameBox:SetText(editingBuff.name)
    end

    advY = advY - 25

    -- Missing Text
    local missingLabel = advancedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    missingLabel:SetPoint("TOPLEFT", 0, advY)
    missingLabel:SetText("Missing Text:")

    local missingBox = CreateFrame("EditBox", nil, advancedFrame, "InputBoxTemplate")
    missingBox:SetSize(80, 18)
    missingBox:SetPoint("LEFT", missingLabel, "RIGHT", 5, 0)
    missingBox:SetAutoFocus(false)
    if editingBuff and editingBuff.missingText then
        missingBox:SetText(editingBuff.missingText:gsub("\n", "\\n"))
    end

    local missingHint = advancedFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    missingHint:SetPoint("LEFT", missingBox, "RIGHT", 5, 0)
    missingHint:SetText("(use \\n for newline)")

    advY = advY - 25

    -- Class Filter
    local classLabel = advancedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    classLabel:SetPoint("TOPLEFT", 0, advY)
    classLabel:SetText("Only for class:")

    local classOptions = {
        { value = nil, label = "Any" },
        { value = "WARRIOR", label = "Warrior" },
        { value = "PALADIN", label = "Paladin" },
        { value = "HUNTER", label = "Hunter" },
        { value = "ROGUE", label = "Rogue" },
        { value = "PRIEST", label = "Priest" },
        { value = "DEATHKNIGHT", label = "Death Knight" },
        { value = "SHAMAN", label = "Shaman" },
        { value = "MAGE", label = "Mage" },
        { value = "WARLOCK", label = "Warlock" },
        { value = "MONK", label = "Monk" },
        { value = "DRUID", label = "Druid" },
        { value = "DEMONHUNTER", label = "Demon Hunter" },
        { value = "EVOKER", label = "Evoker" },
    }
    local selectedClass = editingBuff and editingBuff.class or nil

    local classDropdown =
        CreateFrame("Frame", "BuffRemindersCustomClassDropdown", advancedFrame, "UIDropDownMenuTemplate")
    classDropdown:SetPoint("LEFT", classLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(classDropdown, 100)

    local function ClassDropdown_Initialize(self, level)
        for _, cls in ipairs(classOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = cls.label
            info.value = cls.value
            info.checked = selectedClass == cls.value
            info.func = function()
                selectedClass = cls.value
                UIDropDownMenu_SetSelectedValue(classDropdown, cls.value)
                UIDropDownMenu_SetText(classDropdown, cls.label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(classDropdown, ClassDropdown_Initialize)
    UIDropDownMenu_SetSelectedValue(classDropdown, selectedClass)
    for _, cls in ipairs(classOptions) do
        if cls.value == selectedClass then
            UIDropDownMenu_SetText(classDropdown, cls.label)
            break
        end
    end

    advancedBtn:SetScript("OnClick", function()
        advancedShown = not advancedShown
        if advancedShown then
            advancedText:SetText("[-] Hide Advanced Options")
            advancedFrame:Show()
            modal:SetHeight(MODAL_HEIGHT + 85)
        else
            advancedText:SetText("[+] Show Advanced Options")
            advancedFrame:Hide()
            modal:SetHeight(MODAL_HEIGHT)
        end
    end)

    -- Buttons at bottom
    local cancelBtn = CreateFrame("Button", nil, modal, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        modal:Hide()
    end)

    local saveBtn = CreateFrame("Button", nil, modal, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, 22)
    saveBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        if not validatedSpellID then
            previewError:SetText("Please validate a spell ID first")
            previewError:SetTextColor(1, 0.3, 0.3)
            previewError:Show()
            return
        end

        local key = existingKey or GenerateCustomBuffKey(validatedSpellID)
        local displayName = nameBox:GetText()
        if displayName == "" then
            displayName = validatedSpellName or ("Spell " .. validatedSpellID)
        end

        local missingText = missingBox:GetText()
        if missingText ~= "" then
            missingText = missingText:gsub("\\n", "\n")
        else
            missingText = nil
        end

        local customBuff = {
            spellID = validatedSpellID,
            key = key,
            name = displayName,
            missingText = missingText,
            class = selectedClass,
        }

        BuffRemindersDB.customBuffs[key] = customBuff

        -- Create frame if new
        if not existingKey then
            CreateCustomBuffFrameRuntime(customBuff)
        else
            -- Update existing frame's icon
            local frame = buffFrames[key]
            if frame then
                local texture = GetBuffTexture(validatedSpellID)
                if texture then
                    frame.icon:SetTexture(texture)
                end
                frame.displayName = displayName
            end
        end

        modal:Hide()
        if refreshPanelCallback then
            refreshPanelCallback()
        end
        UpdateDisplay()
    end)

    customBuffModal = modal
    modal:Show()
end

-- Slash command handler
local function SlashHandler(msg)
    local cmd = msg:match("^(%S*)") or ""
    cmd = cmd:lower()

    if cmd == "test" then
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

        -- Notify users about the rename (shows once)
        if not BuffRemindersDB.renameNotificationShown then
            BuffRemindersDB.renameNotificationShown = true
            print("|cff00ccffBuffReminders:|r This addon was renamed from |cffffcc00RaidBuffsTracker|r.")
            print(
                "|cff00ccffBuffReminders:|r Your previous settings could not be migrated. Use |cffffcc00/br|r to reconfigure."
            )
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

        -- Initialize custom buffs storage
        if not BuffRemindersDB.customBuffs then
            BuffRemindersDB.customBuffs = {}
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
        desc:SetText("Track missing buffs at a glance.")

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
