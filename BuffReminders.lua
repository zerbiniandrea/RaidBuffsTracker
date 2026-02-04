local addonName, BR = ...

-- Shared constants (from Core.lua)
local TEXCOORD_INSET = BR.TEXCOORD_INSET
local DEFAULT_BORDER_SIZE = BR.DEFAULT_BORDER_SIZE
local DEFAULT_ICON_ZOOM = BR.DEFAULT_ICON_ZOOM

-- Global API table for external addon integration
BuffReminders = {}
local EXPORT_PREFIX = "!BR_"

-- Buff tables from Buffs.lua (via BR namespace)
local BUFF_TABLES = BR.BUFF_TABLES
local BuffGroups = BR.BuffGroups

-- Local aliases for direct access
local RaidBuffs = BUFF_TABLES.raid
local PresenceBuffs = BUFF_TABLES.presence
local TargetedBuffs = BUFF_TABLES.targeted
local SelfBuffs = BUFF_TABLES.self
local Consumables = BUFF_TABLES.consumable

-- Build icon override lookup table (for spells replaced by talents)
local IconOverrides = {} ---@type table<number, number>
for _, buffArray in ipairs({ PresenceBuffs, TargetedBuffs, SelfBuffs }) do
    for _, buff in ipairs(buffArray) do
        if buff.iconOverride then
            local spellList = (type(buff.spellID) == "table" and buff.spellID or { buff.spellID }) --[[@as number[] ]]
            for _, id in ipairs(spellList) do
                IconOverrides[id] = buff.iconOverride
            end
        end
    end
end

-- ============================================================================
-- BUFF HELPER FUNCTIONS
-- ============================================================================

---Get the effective setting key for a buff (groupId if present, otherwise individual key)
---@param buff RaidBuff|PresenceBuff|TargetedBuff|SelfBuff
---@return string
local function GetBuffSettingKey(buff)
    return buff.groupId or buff.key
end

---Generate a unique key for a custom buff
---@param spellID SpellID
---@return string
local function GenerateCustomBuffKey(spellID)
    local id = type(spellID) == "table" and spellID[1] or spellID
    return "custom_" .. id .. "_" .. time()
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

-- BuffBeneficiaries from Buffs.lua (classes that benefit from each buff)
local BuffBeneficiaries = BR.BuffBeneficiaries

-- Default settings
-- Note: enabledBuffs defaults to all enabled - only set false to disable by default
local defaults = {
    position = { point = "CENTER", x = 0, y = 0 },
    locked = true,
    enabledBuffs = {},
    iconSize = 64,
    spacing = 0.2, -- multiplier of iconSize (reset ratios default)
    showBuffReminder = true,
    showOnlyInGroup = false,
    showOnlyInInstance = false,
    showOnlyPlayerClassBuff = false,
    showOnlyPlayerMissing = false,
    showOnlyOnReadyCheck = false,
    readyCheckDuration = 15, -- seconds
    growDirection = "CENTER", -- "LEFT", "CENTER", "RIGHT", "UP", "DOWN"
    showExpirationGlow = true,
    expirationThreshold = 15, -- minutes
    glowStyle = 1, -- 1=Orange, 2=Gold, 3=Yellow, 4=White, 5=Red
    useGlowFallback = false, -- EXPERIMENTAL: Show own raid buff via action bar glow during M+
    optionsPanelScale = 1.2, -- base scale (displayed as 100%)
    splitCategories = { -- Which categories are split into their own frame (false = in main frame)
        raid = false,
        presence = false,
        targeted = false,
        self = false,
        consumable = false,
        custom = false,
    }, ---@type SplitCategories
    ---@type CategoryVisibility
    categoryVisibility = { -- Which content types each category shows in
        raid = { openWorld = true, dungeon = true, scenario = true, raid = true },
        presence = { openWorld = true, dungeon = true, scenario = true, raid = true },
        targeted = { openWorld = false, dungeon = true, scenario = true, raid = true },
        self = { openWorld = true, dungeon = true, scenario = true, raid = true },
        consumable = { openWorld = false, dungeon = true, scenario = true, raid = true },
        custom = { openWorld = true, dungeon = true, scenario = true, raid = true },
    },
    ---@type AllCategorySettings
    categorySettings = { -- Per-category settings (main = non-split buffs, others = when split)
        main = {
            position = { point = "CENTER", x = 0, y = 0 },
            iconSize = 64,
            spacing = 0.2,
            growDirection = "CENTER",
            iconZoom = 8,
            borderSize = 2,
        },
        raid = {
            position = { point = "CENTER", x = 0, y = 60 },
            iconSize = 64,
            spacing = 0.2,
            growDirection = "CENTER",
            iconZoom = 8,
            borderSize = 2,
        },
        presence = {
            position = { point = "CENTER", x = 0, y = 20 },
            iconSize = 64,
            spacing = 0.2,
            growDirection = "CENTER",
            iconZoom = 8,
            borderSize = 2,
        },
        targeted = {
            position = { point = "CENTER", x = 0, y = -20 },
            iconSize = 64,
            spacing = 0.2,
            growDirection = "CENTER",
            iconZoom = 8,
            borderSize = 2,
        },
        self = {
            position = { point = "CENTER", x = 0, y = -60 },
            iconSize = 64,
            spacing = 0.2,
            growDirection = "CENTER",
            iconZoom = 8,
            borderSize = 2,
        },
        consumable = {
            position = { point = "CENTER", x = 0, y = -100 },
            iconSize = 64,
            spacing = 0.2,
            growDirection = "CENTER",
            iconZoom = 8,
            borderSize = 2,
        },
        custom = {
            position = { point = "CENTER", x = 0, y = -140 },
            iconSize = 64,
            spacing = 0.2,
            growDirection = "CENTER",
            iconZoom = 8,
            borderSize = 2,
        },
    },
}

-- Constants
local MISSING_TEXT_SCALE = 0.6 -- scale for "NO X" warning text

-- Locals
local mainFrame
local buffFrames = {}
local updateTicker
local inReadyCheck = false
local readyCheckTimer = nil
local testMode = false
local testModeData = nil -- Stores seeded fake values for consistent test display
local playerClass = nil -- Cached player class, set once on init
local glowingSpells = {} -- Track which spell IDs are currently glowing (for action bar glow fallback)

-- Category frame system
local categoryFrames = {}
local CATEGORIES = { "raid", "presence", "targeted", "self", "consumable", "custom" }
local CATEGORY_LABELS = {
    raid = "Raid",
    presence = "Presence",
    targeted = "Targeted",
    self = "Self",
    consumable = "Consumable",
    custom = "Custom",
}

-- Export for Options.lua
BR.defaults = defaults
BR.CATEGORIES = CATEGORIES

---Check if a category is split into its own frame
---@param category string
---@return boolean
local function IsCategorySplit(category)
    local db = BuffRemindersDB
    return db.splitCategories and db.splitCategories[category] == true
end

---Check if all categories are split (mainFrame would be empty)
---@return boolean
local function AreAllCategoriesSplit()
    local db = BuffRemindersDB
    if not db.splitCategories then
        return false
    end
    for _, category in ipairs(CATEGORIES) do
        if not db.splitCategories[category] then
            return false
        end
    end
    return true
end

---Get settings for a category (including "main" for non-split buffs)
---@param category string
---@return table
local function GetCategorySettings(category)
    local db = BuffRemindersDB
    if db.categorySettings and db.categorySettings[category] then
        return db.categorySettings[category]
    end
    return defaults.categorySettings[category] or defaults.categorySettings.main
end

---Get the effective category for a frame (its own category if split, otherwise "main")
---@param frame table
---@return string
local function GetEffectiveCategory(frame)
    if frame.buffCategory and IsCategorySplit(frame.buffCategory) then
        return frame.buffCategory
    end
    return "main"
end

---Check if a buff is enabled (defaults to true if not explicitly set to false)
---@param key string
---@return boolean
local function IsBuffEnabled(key)
    local db = BuffRemindersDB
    return db.enabledBuffs[key] ~= false
end

---Get the current content type based on instance/zone
---@return "openWorld"|"dungeon"|"scenario"|"raid"
local function GetCurrentContentType()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        return "openWorld"
    end
    if instanceType == "raid" then
        return "raid"
    end
    if instanceType == "scenario" then
        return "scenario"
    end
    -- Treat party/dungeon and any unknown instanced content as dungeon
    -- PvP/arena are already filtered out in UpdateDisplay before this is called
    return "dungeon"
end

---Check if a category should be visible for the current content type
---@param category CategoryName
---@return boolean
local function IsCategoryVisibleForContent(category)
    local db = BuffRemindersDB
    if not db.categoryVisibility then
        return true
    end
    local visibility = db.categoryVisibility[category]
    if not visibility then
        return true
    end
    local contentType = GetCurrentContentType()
    return visibility[contentType] ~= false
end

---Check if a unit is a valid group member for buff tracking
---Excludes: non-existent, dead/ghost, disconnected, hostile (cross-faction in open world)
---@param unit string
---@return boolean
local function IsValidGroupMember(unit)
    return UnitExists(unit)
        and not UnitIsDeadOrGhost(unit)
        and UnitIsConnected(unit)
        and UnitCanAssist("player", unit)
        and UnitIsVisible(unit)
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

-- Fixed text scale ratio (font size = iconSize * TEXT_SCALE_RATIO)
local TEXT_SCALE_RATIO = 0.32

---Calculate font size based on icon size, with optional scale multiplier
---@param scale? number
---@param iconSizeOverride? number
---@return number
local function GetFontSize(scale, iconSizeOverride)
    local mainSettings = GetCategorySettings("main")
    local iconSize = iconSizeOverride or mainSettings.iconSize or 64
    local baseSize = iconSize * TEXT_SCALE_RATIO
    return math.floor(baseSize * (scale or 1))
end

---Get font size for a specific frame based on its effective category
---@param frame table
---@param scale? number
---@return number
local function GetFrameFontSize(frame, scale)
    local effectiveCat = GetEffectiveCategory(frame)
    local catSettings = GetCategorySettings(effectiveCat)
    local iconSize = catSettings.iconSize or 64
    return GetFontSize(scale, iconSize)
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

---Get classes present in the group (players only, excludes NPCs)
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
        -- Only count actual players as potential buffers (NPCs won't cast buffs like Skyfury)
        if UnitIsPlayer(unit) then
            local _, class = UnitClass(unit)
            if class then
                classes[class] = true
            end
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
    -- Check for icon override (for spells replaced by talents)
    if IconOverrides[id] then
        return IconOverrides[id]
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
---@param playerOnly? boolean Only check the player, not the group
---@return number missing
---@return number total
---@return number? minRemaining
local function CountMissingBuff(spellIDs, buffKey, playerOnly)
    local missing = 0
    local total = 0
    local minRemaining = nil
    local beneficiaries = BuffBeneficiaries[buffKey]

    if playerOnly or GetNumGroupMembers() == 0 then
        -- Solo/player-only: check if player benefits
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
---@param playerOnly? boolean Only check the player, not the group
---@return number count
---@return number? minRemaining
local function CountPresenceBuff(spellIDs, playerOnly)
    local found = 0
    local minRemaining = nil

    if playerOnly or GetNumGroupMembers() == 0 then
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

---Check if player should cast their targeted buff (returns true if a beneficiary needs it)
---@param spellIDs SpellID
---@param requiredClass ClassName
---@param beneficiaryRole? RoleType
---@return boolean? Returns nil if player can't provide this buff
local function ShouldShowTargetedBuff(spellIDs, requiredClass, beneficiaryRole)
    if playerClass ~= requiredClass then
        return nil
    end

    local spellID = (type(spellIDs) == "table" and spellIDs[1] or spellIDs) --[[@as number]]
    if not IsPlayerSpell(spellID) then
        return nil
    end

    -- Targeted buffs require a group (you cast them on others)
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
---@param customCheck? fun(): boolean? Custom check function for complex buff logic
---@return boolean? Returns nil if player can't/shouldn't use this buff
local function ShouldShowSelfBuff(
    spellID,
    requiredClass,
    enchantID,
    requiresTalent,
    excludeTalent,
    buffIdOverride,
    customCheck
)
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

    -- Custom check function takes precedence over standard checks
    if customCheck then
        return customCheck()
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

---Check if player is missing a consumable buff, weapon enchant, or inventory item (returns true if missing)
---@param spellIDs? SpellID
---@param buffIconID? number
---@param checkWeaponEnchant? boolean
---@param itemID? number|number[]
---@return boolean
local function ShouldShowConsumableBuff(spellIDs, buffIconID, checkWeaponEnchant, itemID)
    -- Check buff auras by spell ID
    if spellIDs then
        local spellList = type(spellIDs) == "table" and spellIDs or { spellIDs }
        for _, id in ipairs(spellList) do
            local hasBuff, _ = UnitHasBuff("player", id)
            if hasBuff then
                return false -- Has at least one of the consumable buffs
            end
        end
    end

    -- Check buff auras by icon ID (e.g., food buffs all use icon 136000)
    if buffIconID then
        for i = 1, 40 do
            local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not auraData then
                break
            end
            local success, iconMatches = pcall(function()
                return auraData.icon == buffIconID
            end)
            if success and iconMatches then
                return false -- Has a buff with this icon
            end
        end
    end

    -- Check if any weapon enchant exists (oils, stones, shaman imbues, etc.)
    if checkWeaponEnchant then
        local hasMainHandEnchant = GetWeaponEnchantInfo()
        if hasMainHandEnchant then
            return false -- Has a weapon enchant
        end
    end

    -- Check inventory for item
    if itemID then
        local itemList = type(itemID) == "table" and itemID or { itemID }
        for _, id in ipairs(itemList) do
            local ok, count = pcall(C_Item.GetItemCount, id, false, true)
            if ok and count and count > 0 then
                return false -- Has the item in inventory
            end
        end
    end

    -- If we have nothing to check, return false
    if not spellIDs and not buffIconID and not checkWeaponEnchant and not itemID then
        return false
    end

    return true -- Missing all consumable buffs/enchants/items
end

-- Action bar button names to scan for glows
local ACTION_BAR_BUTTONS = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton",
    "MultiBar5Button",
    "MultiBar6Button",
    "MultiBar7Button",
}

---Check if a specific action button has an active glow overlay
---@param button table
---@return boolean
local function ButtonHasGlow(button)
    -- Check for SpellActivationAlert (Blizzard's glow frame)
    if button.SpellActivationAlert and button.SpellActivationAlert:IsShown() then
        return true
    end
    -- Check for overlay (older method)
    if button.overlay and button.overlay:IsShown() then
        return true
    end
    return false
end

---Check if any of the given spell IDs are currently glowing on the action bar
---@param spellIDs SpellID
---@return boolean
local function IsSpellGlowing(spellIDs)
    local ids = type(spellIDs) == "table" and spellIDs or { spellIDs }
    for _, id in ipairs(ids) do
        -- Check cached event data first (populated by glow events)
        if glowingSpells[id] then
            return true
        end
    end

    -- On reload, events don't fire for already-active glows
    -- Scan action bar buttons directly to check for active overlays
    for _, barName in ipairs(ACTION_BAR_BUTTONS) do
        for i = 1, 12 do
            local button = _G[barName .. i]
            if button and ButtonHasGlow(button) then
                -- Check if this button has one of our spell IDs
                local actionType, actionId = GetActionInfo(button.action or 0)
                if actionType == "spell" then
                    for _, id in ipairs(ids) do
                        if actionId == id then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

-- Cache for player's raid buff (computed once, never changes)
local playerRaidBuff = nil
local playerRaidBuffComputed = false

---Find the player's own raid buff (the one their class provides)
---@return RaidBuff|nil
local function GetPlayerRaidBuff()
    if playerRaidBuffComputed then
        return playerRaidBuff
    end
    for _, buff in ipairs(RaidBuffs) do
        if buff.class == playerClass then
            playerRaidBuff = buff
            break
        end
    end
    playerRaidBuffComputed = true
    return playerRaidBuff
end

-- Forward declarations
local UpdateDisplay, UpdateAnchor, ToggleTestMode, RefreshTestDisplay
local UpdateFallbackDisplay

-- Track if any frame is currently being dragged (to prevent repositioning during drag)
local isDraggingFrame = false

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

-- Export for Options.lua (ShowGlowDemo)
BR.GlowStyles = GlowStyles

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

---Show a frame with missing text styling
---@param frame BuffFrame
---@param missingText? string
---@return boolean true (for anyVisible chaining)
local function ShowMissingFrame(frame, missingText)
    frame.icon:SetAllPoints()
    frame.icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
    frame.count:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
    frame.count:SetText(missingText or "")
    frame:Show()
    SetExpirationGlow(frame, false)
    return true
end

---Check if buff passes common pre-conditions
---@param buff table Any buff type with optional pre-check fields
---@param presentClasses? table<ClassName, boolean>
---@param db table Database settings
---@return boolean passes
local function PassesPreChecks(buff, presentClasses, db)
    -- Ready check only
    local readyCheckOnly = buff.readyCheckOnly or (buff.infoTooltip and buff.infoTooltip:match("^Ready Check Only"))
    if readyCheckOnly and not inReadyCheck then
        return false
    end

    -- Class filtering
    if buff.class then
        if db.showOnlyPlayerClassBuff and buff.class ~= playerClass then
            return false
        end
        if presentClasses and not presentClasses[buff.class] then
            return false
        end
    end

    -- Talent exclusion
    if buff.excludeTalentSpellID and IsPlayerSpell(buff.excludeTalentSpellID) then
        return false
    end

    -- Spell knowledge exclusion
    if buff.excludeIfSpellKnown then
        for _, spellID in ipairs(buff.excludeIfSpellKnown) do
            if IsPlayerSpell(spellID) then
                return false
            end
        end
    end

    return true
end

-- Anchor point for each growth direction (anchor is the fixed point, icons grow away from it)
local DIRECTION_ANCHORS = {
    LEFT = "RIGHT", -- grow left: anchor on right, icons expand leftward
    RIGHT = "LEFT", -- grow right: anchor on left, icons expand rightward
    UP = "BOTTOM",
    DOWN = "TOP",
    CENTER = "CENTER",
}

-- Get anchor position offset from frame center based on anchor type and frame size
local function GetAnchorOffset(anchor, width, height)
    if anchor == "LEFT" then
        return -width / 2, 0
    elseif anchor == "RIGHT" then
        return width / 2, 0
    elseif anchor == "TOP" then
        return 0, height / 2
    elseif anchor == "BOTTOM" then
        return 0, -height / 2
    end
    return 0, 0 -- CENTER
end

-- Create a category frame for grouped display mode
local function CreateCategoryFrame(category)
    local db = BuffRemindersDB
    local catSettings = db.categorySettings and db.categorySettings[category] or defaults.categorySettings[category]
    local pos = catSettings.position

    local frame = CreateFrame("Frame", "BuffReminders_Category_" .. category, UIParent)
    frame:SetSize(200, 50)
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    frame.category = category

    -- Edit mode padding (how much larger the background is than the icons)
    local EDIT_PADDING = 8

    -- Border for edit mode (outermost, creates the green border)
    frame.editBorder = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    frame.editBorder:SetPoint("TOPLEFT", -EDIT_PADDING - 2, EDIT_PADDING + 2)
    frame.editBorder:SetPoint("BOTTOMRIGHT", EDIT_PADDING + 2, -EDIT_PADDING - 2)
    frame.editBorder:SetColorTexture(0, 0.7, 0, 0.9)
    frame.editBorder:Hide()

    -- Background (shown when unlocked, like WoW edit mode)
    frame.editBg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.editBg:SetPoint("TOPLEFT", -EDIT_PADDING, EDIT_PADDING)
    frame.editBg:SetPoint("BOTTOMRIGHT", EDIT_PADDING, -EDIT_PADDING)
    frame.editBg:SetColorTexture(0.05, 0.2, 0.05, 0.7)
    frame.editBg:Hide()

    -- Label text at top
    frame.editLabel = frame:CreateFontString(nil, "OVERLAY")
    frame.editLabel:SetPoint("BOTTOM", frame, "TOP", 0, EDIT_PADDING + 6)
    frame.editLabel:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    frame.editLabel:SetTextColor(0.4, 1, 0.4, 1)
    frame.editLabel:SetText(CATEGORY_LABELS[category] or category)
    frame.editLabel:Hide()

    -- Expand hit rectangle to match the green border visual
    -- Negative values expand the clickable area outward
    frame:SetHitRectInsets(-(EDIT_PADDING + 2), -(EDIT_PADDING + 2), -(EDIT_PADDING + 2), -(EDIT_PADDING + 2))

    -- Make frame draggable
    frame:SetMovable(true)
    frame:EnableMouse(not db.locked)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(self)
        if not BuffRemindersDB.locked then
            isDraggingFrame = true
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        isDraggingFrame = false
        -- Save anchor position (based on growth direction) relative to UIParent CENTER
        local dragCatSettings = GetCategorySettings(category)
        local direction = dragCatSettings.growDirection or "CENTER"
        local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
        local cx, cy = self:GetCenter()
        local px, py = UIParent:GetCenter()
        local w, h = self:GetSize()
        local offsetX, offsetY = GetAnchorOffset(anchor, w, h)
        local x, y = (cx - px) + offsetX, (cy - py) + offsetY
        if not BuffRemindersDB.categorySettings then
            BuffRemindersDB.categorySettings = {}
        end
        if not BuffRemindersDB.categorySettings[category] then
            BuffRemindersDB.categorySettings[category] = {}
        end
        BuffRemindersDB.categorySettings[category].position = { point = "CENTER", x = x, y = y }
    end)

    frame:Hide()
    return frame
end

-- Create icon frame for a buff
local function CreateBuffFrame(buff, category)
    local frame = CreateFrame("Frame", "BuffReminders_" .. buff.key, mainFrame)
    frame.key = buff.key
    frame.spellIDs = buff.spellID
    frame.displayName = buff.name
    frame.buffCategory = category

    local db = BuffRemindersDB
    -- Use effective category settings (respects split categories)
    local effectiveCat = (category and IsCategorySplit(category)) and category or "main"
    local catSettings = GetCategorySettings(effectiveCat)
    local iconSize = catSettings.iconSize or 64
    frame:SetSize(iconSize, iconSize)

    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    local zoom = (catSettings.iconZoom or DEFAULT_ICON_ZOOM) / 100
    frame.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    frame.icon:SetDesaturated(false)
    frame.icon:SetVertexColor(1, 1, 1, 1)
    local iconOverride = buff.iconOverride
    if type(iconOverride) == "table" then
        iconOverride = iconOverride[1] -- Use first icon for buff frame
    end
    local texture = iconOverride or GetBuffTexture(buff.spellID, buff.iconByRole)
    if texture then
        frame.icon:SetTexture(texture)
    end

    -- Border (background behind icon)
    local borderSize = catSettings.borderSize or DEFAULT_BORDER_SIZE
    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetPoint("TOPLEFT", -borderSize, borderSize)
    frame.border:SetPoint("BOTTOMRIGHT", borderSize, -borderSize)
    frame.border:SetColorTexture(0, 0, 0, 1)

    -- Count text (font size scales with icon size, updated in UpdateVisuals)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    frame.count:SetPoint("CENTER", 0, 0)
    frame.count:SetTextColor(1, 1, 1, 1)
    frame.count:SetFont(STANDARD_TEXT_FONT, GetFontSize(1), "OUTLINE")

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
    frame.testText:SetPoint("BOTTOM", frame, "TOP", 0, 25)
    frame.testText:SetFont(STANDARD_TEXT_FONT, GetFontSize(0.6), "OUTLINE")
    frame.testText:SetTextColor(1, 0.8, 0, 1)
    frame.testText:SetText("TEST")
    frame.testText:Hide()

    -- Dragging (handles both single-frame and category-frame modes)
    frame:EnableMouse(not BuffRemindersDB.locked)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not BuffRemindersDB.locked then
            isDraggingFrame = true
            local parent = self:GetParent()
            if parent then
                parent:StartMoving()
            end
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        local parent = self:GetParent()
        if not parent then
            isDraggingFrame = false
            return
        end
        parent:StopMovingOrSizing()
        isDraggingFrame = false
        -- Save anchor position (based on growth direction) relative to UIParent CENTER
        local settings = BuffRemindersDB
        local catKey = parent.category or "main"
        local dragCatSettings = GetCategorySettings(catKey)
        local direction = dragCatSettings.growDirection or "CENTER"
        local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
        local cx, cy = parent:GetCenter()
        local px, py = UIParent:GetCenter()
        local w, h = parent:GetSize()
        local offsetX, offsetY = GetAnchorOffset(anchor, w, h)
        local x, y = (cx - px) + offsetX, (cy - py) + offsetY
        if parent.category then
            -- Save to category-specific position (this is a split category frame)
            if not settings.categorySettings then
                settings.categorySettings = {}
            end
            if not settings.categorySettings[parent.category] then
                settings.categorySettings[parent.category] = {}
            end
            settings.categorySettings[parent.category].position = { point = "CENTER", x = x, y = y }
        else
            -- Save to main frame position (both legacy and new locations)
            settings.position = { point = "CENTER", x = x, y = y }
            if settings.categorySettings and settings.categorySettings.main then
                settings.categorySettings.main.position = { point = "CENTER", x = x, y = y }
            end
        end
    end)

    frame:Hide()
    return frame
end

-- Helper to position frames within a container using specified settings
local function PositionFramesInContainer(container, frames, iconSize, spacing, direction)
    local count = #frames
    if count == 0 then
        return
    end

    for i, frame in ipairs(frames) do
        frame:ClearAllPoints()
        if direction == "LEFT" then
            -- Grow left: first icon at right edge, subsequent icons to the left
            frame:SetPoint("RIGHT", container, "RIGHT", -((i - 1) * (iconSize + spacing)), 0)
        elseif direction == "RIGHT" then
            -- Grow right: first icon at left edge, subsequent icons to the right
            frame:SetPoint("LEFT", container, "LEFT", (i - 1) * (iconSize + spacing), 0)
        elseif direction == "UP" then
            frame:SetPoint("BOTTOM", container, "BOTTOM", 0, (i - 1) * (iconSize + spacing))
        elseif direction == "DOWN" then
            frame:SetPoint("TOP", container, "TOP", 0, -((i - 1) * (iconSize + spacing)))
        else -- CENTER (horizontal)
            local totalWidth = count * iconSize + (count - 1) * spacing
            local startX = -totalWidth / 2 + iconSize / 2
            frame:SetPoint("CENTER", container, "CENTER", startX + (i - 1) * (iconSize + spacing), 0)
        end
    end
end

-- Position buff frames with split category support
-- Handles mixed mode: some categories in mainFrame, some split into their own frames
local function PositionBuffFramesWithSplits()
    -- Skip repositioning if any frame is currently being dragged
    if isDraggingFrame then
        return
    end

    local db = BuffRemindersDB

    -- Collect visible frames by category
    local framesByCategory = {
        raid = {},
        presence = {},
        targeted = {},
        self = {},
        consumable = {},
        custom = {},
    }

    for category, buffArray in pairs(BUFF_TABLES) do
        for _, buff in ipairs(buffArray) do
            local frame = buffFrames[buff.key]
            if frame and frame:IsShown() then
                table.insert(framesByCategory[category], frame)
            end
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
            table.insert(framesByCategory.custom, frame)
        end
    end

    -- Collect frames for mainFrame (non-split categories) in definition order
    local mainFrameBuffs = {}
    for _, category in ipairs(CATEGORIES) do
        if not IsCategorySplit(category) then
            for _, frame in ipairs(framesByCategory[category]) do
                table.insert(mainFrameBuffs, frame)
            end
        end
    end

    -- Position and size mainFrame
    if #mainFrameBuffs > 0 then
        local mainSettings = GetCategorySettings("main")
        local iconSize = mainSettings.iconSize or 64
        local spacing = math.floor(iconSize * (mainSettings.spacing or 0.2))
        local direction = mainSettings.growDirection or "CENTER"

        -- Resize individual buff frames to main icon size
        for _, frame in ipairs(mainFrameBuffs) do
            frame:SetSize(iconSize, iconSize)
        end

        -- Size mainFrame to fit contents
        local isVertical = direction == "UP" or direction == "DOWN"
        local totalSize = #mainFrameBuffs * iconSize + (#mainFrameBuffs - 1) * spacing
        if isVertical then
            mainFrame:SetSize(iconSize, math.max(totalSize, iconSize))
        else
            mainFrame:SetSize(math.max(totalSize, iconSize), iconSize)
        end

        -- Re-anchor based on growth direction so first icon stays at anchor position
        -- pos is already the anchor position relative to UIParent CENTER
        local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
        local pos = db.position
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(anchor, UIParent, "CENTER", pos.x or 0, pos.y or 0)

        PositionFramesInContainer(mainFrame, mainFrameBuffs, iconSize, spacing, direction)
        mainFrame:Show()
    elseif not db.locked then
        -- Keep mainFrame visible when unlocked for positioning
        local mainSettings = GetCategorySettings("main")
        local iconSize = mainSettings.iconSize or 64
        local direction = mainSettings.growDirection or "CENTER"
        local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
        local pos = db.position
        mainFrame:SetSize(iconSize, iconSize)
        -- pos is already the anchor position relative to UIParent CENTER
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(anchor, UIParent, "CENTER", pos.x or 0, pos.y or 0)
        mainFrame:Show()
    else
        mainFrame:Hide()
    end

    -- Position frames within each split category
    for _, category in ipairs(CATEGORIES) do
        local catFrame = categoryFrames[category]
        local frames = framesByCategory[category]
        local isSplit = IsCategorySplit(category)

        if catFrame and isSplit then
            local catSettings = GetCategorySettings(category)
            local direction = catSettings.growDirection or "CENTER"
            local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
            local pos = catSettings.position

            if #frames > 0 then
                local iconSize = catSettings.iconSize or 64
                local spacing = math.floor(iconSize * (catSettings.spacing or 0.2))

                -- Resize individual buff frames to category's icon size
                for _, frame in ipairs(frames) do
                    frame:SetSize(iconSize, iconSize)
                end

                -- Size category frame to fit contents
                local isVertical = direction == "UP" or direction == "DOWN"
                local totalSize = #frames * iconSize + (#frames - 1) * spacing
                if isVertical then
                    catFrame:SetSize(iconSize, math.max(totalSize, iconSize))
                else
                    catFrame:SetSize(math.max(totalSize, iconSize), iconSize)
                end

                -- Re-anchor based on growth direction so first icon stays at anchor position
                -- pos is already the anchor position relative to UIParent CENTER
                catFrame:ClearAllPoints()
                catFrame:SetPoint(anchor, UIParent, "CENTER", pos.x or 0, pos.y or 0)

                PositionFramesInContainer(catFrame, frames, iconSize, spacing, direction)
                catFrame:Show()
            elseif not db.locked then
                -- Keep split frame visible when unlocked for positioning
                local iconSize = catSettings.iconSize or 64
                catFrame:SetSize(iconSize, iconSize)
                -- pos is already the anchor position relative to UIParent CENTER
                catFrame:ClearAllPoints()
                catFrame:SetPoint(anchor, UIParent, "CENTER", pos.x or 0, pos.y or 0)
                catFrame:Show()
            else
                catFrame:Hide()
            end
        elseif catFrame then
            -- Not split - hide category frame
            catFrame:Hide()
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
            frame.count:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame), "OUTLINE")
            if db.showExpirationGlow and not glowShown then
                frame.count:SetText(FormatRemainingTime(testModeData.fakeRemaining))
                SetExpirationGlow(frame, true)
                glowShown = true
            else
                local fakeBuffed = testModeData.fakeTotal - testModeData.fakeMissing[i]
                frame.count:SetText(fakeBuffed .. "/" .. testModeData.fakeTotal)
            end
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, 0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL presence buffs
    for _, buff in ipairs(PresenceBuffs) do
        local frame = buffFrames[buff.key]
        if frame then
            frame.count:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
            frame.count:SetText(buff.missingText or "")
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, 0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL targeted buffs (one per group)
    local seenGroups = {}
    for _, buff in ipairs(TargetedBuffs) do
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
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
                if frame.testText and testModeData.showLabels then
                    frame.testText:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, 0.6), "OUTLINE")
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
            frame.count:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, 0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL consumable buffs
    for _, buff in ipairs(Consumables) do
        local frame = buffFrames[buff.key]
        if frame then
            frame.count:SetText(buff.missingText)
            frame.count:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, 0.6), "OUTLINE")
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
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
                frame.count:SetText(customBuff.missingText or "NO\nBUFF")
                if frame.testText and testModeData.showLabels then
                    frame.testText:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, 0.6), "OUTLINE")
                    frame.testText:Show()
                end
                frame:Show()
            end
        end
    end

    -- Position and show appropriate frame(s)
    PositionBuffFramesWithSplits()
    UpdateAnchor()
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

-- Helper to hide all display frames (mainFrame, category frames, and all buff frames)
local function HideAllDisplayFrames()
    -- Skip hiding if any frame is being dragged
    if isDraggingFrame then
        return
    end
    mainFrame:Hide()
    for _, category in ipairs(CATEGORIES) do
        if categoryFrames[category] then
            categoryFrames[category]:Hide()
        end
    end
    -- Also hide individual buff frames (so they don't reappear when mainFrame is shown by fallback)
    for _, frame in pairs(buffFrames) do
        frame:Hide()
    end
end

-- Update the fallback display (shows player's own raid buff via glow during M+/PvP)
-- Assumes caller has already determined we're in restricted mode and called HideAllDisplayFrames()
UpdateFallbackDisplay = function()
    if not mainFrame or not BuffRemindersDB.useGlowFallback then
        return
    end

    local playerBuff = GetPlayerRaidBuff()
    if not playerBuff then
        return
    end

    local frame = buffFrames[playerBuff.key]
    if not frame or not IsBuffEnabled(playerBuff.key) then
        return
    end

    if IsSpellGlowing(playerBuff.spellID) then
        ShowMissingFrame(frame, "NO\nBUFF!")
        PositionBuffFramesWithSplits()
        UpdateAnchor() -- Ensure edit mode visuals are updated
    end
    -- No else branch - HideAllDisplayFrames was already called by caller
end

-- Update the display
UpdateDisplay = function()
    if testMode then
        return
    end

    -- Early exit: can't check buffs when dead, in combat, M+, or instanced PvP
    local _, instanceType = IsInInstance()
    local inMythicPlus = C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    if
        UnitIsDeadOrGhost("player")
        or InCombatLockdown()
        or inMythicPlus
        or instanceType == "pvp"
        or instanceType == "arena"
    then
        HideAllDisplayFrames()
        -- Fallback only when alive (dead players can't cast)
        if not UnitIsDeadOrGhost("player") then
            UpdateFallbackDisplay()
        end
        return
    end

    local db = BuffRemindersDB

    -- Hide based on visibility settings
    if db.showOnlyOnReadyCheck and not inReadyCheck then
        HideAllDisplayFrames()
        return
    end

    if db.showOnlyInGroup then
        if db.showOnlyInInstance then
            if not IsInInstance() then
                HideAllDisplayFrames()
                return
            end
        elseif GetNumGroupMembers() == 0 then
            HideAllDisplayFrames()
            return
        end
    end

    local presentClasses = GetGroupClasses()

    local anyVisible = false

    -- Process coverage buffs (need everyone to have them)
    local playerOnly = db.showOnlyPlayerMissing
    local raidVisible = IsCategoryVisibleForContent("raid")
    for _, buff in ipairs(RaidBuffs) do
        local frame = buffFrames[buff.key]
        local showBuff = raidVisible
            and (not db.showOnlyPlayerClassBuff or buff.class == playerClass)
            and (not presentClasses or presentClasses[buff.class])

        if frame and IsBuffEnabled(buff.key) and showBuff then
            local missing, total, minRemaining = CountMissingBuff(buff.spellID, buff.key, playerOnly)
            local expiringSoon = db.showExpirationGlow and minRemaining and minRemaining < (db.expirationThreshold * 60)
            if missing > 0 then
                local buffed = total - missing
                -- In player-only mode, just show the icon; in group mode, show "X/Y"
                frame.count:SetText(playerOnly and "" or (buffed .. "/" .. total))
                frame:Show()
                anyVisible = true
                SetExpirationGlow(frame, expiringSoon)
            elseif expiringSoon then
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
    local presenceVisible = IsCategoryVisibleForContent("presence")
    for _, buff in ipairs(PresenceBuffs) do
        local frame = buffFrames[buff.key]
        local readyCheckOnly = buff.infoTooltip and buff.infoTooltip:match("^Ready Check Only")
        local showBuff = presenceVisible
            and (not readyCheckOnly or inReadyCheck)
            and (not db.showOnlyPlayerClassBuff or buff.class == playerClass)
            and (not presentClasses or presentClasses[buff.class])

        if frame and IsBuffEnabled(buff.key) and showBuff then
            local count, minRemaining = CountPresenceBuff(buff.spellID, playerOnly)
            local expiringSoon = db.showExpirationGlow
                and not buff.noGlow
                and minRemaining
                and minRemaining < (db.expirationThreshold * 60)
            if count == 0 then
                anyVisible = ShowMissingFrame(frame, buff.missingText) or anyVisible
            elseif expiringSoon then
                ---@cast minRemaining number
                frame.count:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame), "OUTLINE")
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

    -- Process targeted buffs (player's own buff responsibility)
    local targetedVisible = IsCategoryVisibleForContent("targeted")
    local visibleGroups = {} -- Track visible buffs by groupId for merging
    for _, buff in ipairs(TargetedBuffs) do
        local frame = buffFrames[buff.key]
        local settingKey = GetBuffSettingKey(buff)

        if frame and IsBuffEnabled(settingKey) and targetedVisible and PassesPreChecks(buff, nil, db) then
            local shouldShow = ShouldShowTargetedBuff(buff.spellID, buff.class, buff.beneficiaryRole)
            if shouldShow then
                anyVisible = ShowMissingFrame(frame, buff.missingText) or anyVisible
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
    local selfVisible = IsCategoryVisibleForContent("self")
    for _, buff in ipairs(SelfBuffs) do
        local frame = buffFrames[buff.key]
        local settingKey = buff.groupId or buff.key

        if frame and IsBuffEnabled(settingKey) and selfVisible then
            local shouldShow = ShouldShowSelfBuff(
                buff.spellID,
                buff.class,
                buff.enchantID,
                buff.requiresTalentSpellID,
                buff.excludeTalentSpellID,
                buff.buffIdOverride,
                buff.customCheck
            )
            if shouldShow then
                -- Update icon based on current role (for role-dependent buffs like shields)
                if buff.iconByRole then
                    local texture = GetBuffTexture(buff.spellID, buff.iconByRole)
                    if texture then
                        frame.icon:SetTexture(texture)
                    end
                end
                anyVisible = ShowMissingFrame(frame, buff.missingText) or anyVisible
            else
                HideFrame(frame)
            end
        elseif frame then
            HideFrame(frame)
        end
    end

    -- Process consumable buffs (food, flasks, runes, healthstones)
    local consumableVisible = IsCategoryVisibleForContent("consumable")
    for _, buff in ipairs(Consumables) do
        local frame = buffFrames[buff.key]
        local settingKey = buff.groupId or buff.key

        if frame and IsBuffEnabled(settingKey) and consumableVisible and PassesPreChecks(buff, nil, db) then
            local shouldShow =
                ShouldShowConsumableBuff(buff.spellID, buff.buffIconID, buff.checkWeaponEnchant, buff.itemID)
            if shouldShow then
                anyVisible = ShowMissingFrame(frame, buff.missingText) or anyVisible
            else
                HideFrame(frame)
            end
        elseif frame then
            HideFrame(frame)
        end
    end

    -- Process custom buffs (self buffs only - show if player doesn't have the buff)
    local customVisible = IsCategoryVisibleForContent("custom")
    if db.customBuffs then
        for _, customBuff in pairs(db.customBuffs) do
            local frame = buffFrames[customBuff.key]
            -- Check class filter (nil means any class)
            local classMatch = not customBuff.class or customBuff.class == playerClass
            if frame and IsBuffEnabled(customBuff.key) and customVisible and classMatch then
                local hasBuff = UnitHasBuff("player", customBuff.spellID)
                if not hasBuff then
                    anyVisible = ShowMissingFrame(frame, customBuff.missingText or "NO\nBUFF") or anyVisible
                else
                    HideFrame(frame)
                end
            elseif frame then
                HideFrame(frame)
            end
        end
    end

    if anyVisible or not db.locked then
        -- Use split-aware positioning (handles both main and split categories)
        PositionBuffFramesWithSplits()
        UpdateAnchor()
    else
        -- Hide everything when locked and no buffs visible
        HideAllDisplayFrames()
        UpdateAnchor() -- Ensure edit mode visuals are cleared
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
            isDraggingFrame = true
            self:StartMoving()
        end
    end)

    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        isDraggingFrame = false
        -- Save anchor position (based on growth direction) relative to UIParent CENTER
        local mainSettings = GetCategorySettings("main")
        local direction = mainSettings.growDirection or "CENTER"
        local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
        local cx, cy = self:GetCenter()
        local px, py = UIParent:GetCenter()
        local w, h = self:GetSize()
        local offsetX, offsetY = GetAnchorOffset(anchor, w, h)
        local x, y = (cx - px) + offsetX, (cy - py) + offsetY
        BuffRemindersDB.position = { point = "CENTER", x = x, y = y }
        if BuffRemindersDB.categorySettings and BuffRemindersDB.categorySettings.main then
            BuffRemindersDB.categorySettings.main.position = { point = "CENTER", x = x, y = y }
        end
    end)
end

-- Forward declaration for ReparentBuffFrames (defined after InitializeFrames)
local ReparentBuffFrames

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

    -- Edit mode padding (how much larger the background is than the icons)
    local EDIT_PADDING = 8

    -- Border for edit mode (outermost, creates the green border)
    mainFrame.editBorder = mainFrame:CreateTexture(nil, "BACKGROUND", nil, -2)
    mainFrame.editBorder:SetPoint("TOPLEFT", -EDIT_PADDING - 2, EDIT_PADDING + 2)
    mainFrame.editBorder:SetPoint("BOTTOMRIGHT", EDIT_PADDING + 2, -EDIT_PADDING - 2)
    mainFrame.editBorder:SetColorTexture(0, 0.7, 0, 0.9)
    mainFrame.editBorder:Hide()

    -- Edit mode background (shown when unlocked, like WoW edit mode)
    mainFrame.editBg = mainFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
    mainFrame.editBg:SetPoint("TOPLEFT", -EDIT_PADDING, EDIT_PADDING)
    mainFrame.editBg:SetPoint("BOTTOMRIGHT", EDIT_PADDING, -EDIT_PADDING)
    mainFrame.editBg:SetColorTexture(0.05, 0.2, 0.05, 0.7)
    mainFrame.editBg:Hide()

    -- Label text at top
    mainFrame.editLabel = mainFrame:CreateFontString(nil, "OVERLAY")
    mainFrame.editLabel:SetPoint("BOTTOM", mainFrame, "TOP", 0, EDIT_PADDING + 6)
    mainFrame.editLabel:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    mainFrame.editLabel:SetTextColor(0.4, 1, 0.4, 1)
    mainFrame.editLabel:SetText("Main")
    mainFrame.editLabel:Hide()

    -- Expand hit rectangle to match the green border visual
    -- Negative values expand the clickable area outward
    mainFrame:SetHitRectInsets(-(EDIT_PADDING + 2), -(EDIT_PADDING + 2), -(EDIT_PADDING + 2), -(EDIT_PADDING + 2))

    -- Legacy anchor frame (keeping for compatibility, but edit visuals are better)
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

    -- Create category frames for grouped display mode
    for _, category in ipairs(CATEGORIES) do
        categoryFrames[category] = CreateCategoryFrame(category)
    end

    -- Create buff frames for all categories
    for category, buffArray in pairs(BUFF_TABLES) do
        for _, buff in ipairs(buffArray) do
            buffFrames[buff.key] = CreateBuffFrame(buff, category)
        end
    end

    -- Create frames for custom buffs (always self buffs)
    if db.customBuffs then
        for _, customBuff in pairs(db.customBuffs) do
            buffFrames[customBuff.key] = CreateBuffFrame(customBuff, "custom")
        end
    end

    -- Reparent frames based on split category settings
    ReparentBuffFrames()

    mainFrame:Hide()
end

---Create a frame for a newly added custom buff (called at runtime when adding buffs)
---@param customBuff CustomBuff
local function CreateCustomBuffFrameRuntime(customBuff)
    if not mainFrame then
        return
    end
    local frame = CreateBuffFrame(customBuff, "custom")
    frame.isCustomBuff = true
    buffFrames[customBuff.key] = frame
end

-- Reparent all buff frames to appropriate parent based on split status
ReparentBuffFrames = function()
    for _, frame in pairs(buffFrames) do
        local category = frame.buffCategory
        if category and IsCategorySplit(category) and categoryFrames[category] then
            -- This category is split - parent to its own frame
            frame:SetParent(categoryFrames[category])
            frame:ClearAllPoints() -- Clear stale anchors after reparenting
        else
            -- This category is in main frame
            frame:SetParent(mainFrame)
            frame:ClearAllPoints() -- Clear stale anchors after reparenting
        end
    end
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

-- Export custom buff management for Options.lua
BR.CustomBuffs = {
    CreateRuntime = CreateCustomBuffFrameRuntime,
    Remove = RemoveCustomBuffFrame,
    UpdateFrame = function(key, spellIDValue, displayName)
        local frame = buffFrames[key]
        if frame then
            local texture = GetBuffTexture(spellIDValue)
            if texture then
                frame.icon:SetTexture(texture)
            end
            frame.displayName = displayName
            frame.spellIDs = spellIDValue
        end
    end,
}

-- Helper to show/hide edit mode visuals for a frame
local function SetEditModeVisuals(frame, show, label)
    if not frame then
        return
    end
    if show then
        if frame.editBorder then
            frame.editBorder:Show()
        end
        if frame.editBg then
            frame.editBg:Show()
        end
        if frame.editLabel then
            if label then
                frame.editLabel:SetText(label)
            end
            frame.editLabel:Show()
        end
    else
        if frame.editBorder then
            frame.editBorder:Hide()
        end
        if frame.editBg then
            frame.editBg:Hide()
        end
        if frame.editLabel then
            frame.editLabel:Hide()
        end
    end
end

-- Build a label showing which categories are in mainFrame
local function GetMainFrameLabel()
    local parts = {}
    for _, category in ipairs(CATEGORIES) do
        if not IsCategorySplit(category) then
            table.insert(parts, CATEGORY_LABELS[category])
        end
    end
    if #parts == 0 then
        return "Main (empty)"
    elseif #parts == #CATEGORIES then
        return "Main (all)"
    else
        return table.concat(parts, " + ")
    end
end

-- Update anchor position and visibility
UpdateAnchor = function()
    if not mainFrame then
        return
    end
    local db = BuffRemindersDB
    local unlocked = not db.locked

    -- Hide legacy anchor frames (we use edit mode visuals now)
    if mainFrame.anchorFrame then
        mainFrame.anchorFrame:Hide()
    end

    -- Update mainFrame edit mode visuals (frame visibility is handled by PositionBuffFramesWithSplits)
    local allSplit = AreAllCategoriesSplit()
    if unlocked and not allSplit and mainFrame:IsShown() then
        SetEditModeVisuals(mainFrame, true, GetMainFrameLabel())
    else
        SetEditModeVisuals(mainFrame, false)
    end

    -- Update edit mode visuals for split category frames (frame visibility is handled by PositionBuffFramesWithSplits)
    for _, category in ipairs(CATEGORIES) do
        local catFrame = categoryFrames[category]
        if catFrame then
            local isSplit = IsCategorySplit(category)

            if isSplit and unlocked and catFrame:IsShown() then
                SetEditModeVisuals(catFrame, true, CATEGORY_LABELS[category])
            else
                SetEditModeVisuals(catFrame, false)
            end
        end
    end

    -- Update mouse enabled state (click-through when locked)
    mainFrame:EnableMouse(unlocked)
    for _, category in ipairs(CATEGORIES) do
        local catFrame = categoryFrames[category]
        if catFrame then
            catFrame:EnableMouse(unlocked and IsCategorySplit(category))
        end
    end
    for _, frame in pairs(buffFrames) do
        -- Only enable mouse on buff frames if they're in mainFrame (not in a split category)
        local category = frame.buffCategory
        local inSplitCategory = category and IsCategorySplit(category)
        frame:EnableMouse(unlocked and not inSplitCategory)
    end
end

-- Update icon sizes and text (called when settings change)
local function UpdateVisuals()
    local db = BuffRemindersDB
    for _, frame in pairs(buffFrames) do
        -- Use effective category settings (split category or "main")
        local effectiveCat = GetEffectiveCategory(frame)
        local catSettings = GetCategorySettings(effectiveCat)
        local size = catSettings.iconSize or 64
        frame:SetSize(size, size)
        frame.count:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, 1), "OUTLINE")
        if frame.buffText then
            frame.buffText:SetFont(STANDARD_TEXT_FONT, GetFrameFontSize(frame, 0.8), "OUTLINE")
            if db.showBuffReminder then
                frame.buffText:Show()
            else
                frame.buffText:Hide()
            end
        end
        -- Update icon zoom (texcoord)
        local zoom = (catSettings.iconZoom or DEFAULT_ICON_ZOOM) / 100
        frame.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        -- Update border size
        local borderSize = catSettings.borderSize or DEFAULT_BORDER_SIZE
        frame.border:ClearAllPoints()
        frame.border:SetPoint("TOPLEFT", -borderSize, borderSize)
        frame.border:SetPoint("BOTTOMRIGHT", borderSize, -borderSize)
    end
    if testMode then
        RefreshTestDisplay()
    else
        UpdateDisplay()
    end
end

-- ============================================================================
-- CALLBACK REGISTRY SUBSCRIPTIONS
-- ============================================================================
-- Subscribe to config change events for automatic UI updates.
-- This decouples the options panel from the display system.

local CallbackRegistry = BR.CallbackRegistry

-- Visual changes (icon size, zoom, border, text visibility)
CallbackRegistry:RegisterCallback("VisualsRefresh", function()
    UpdateVisuals()
end)

-- Layout changes (spacing, grow direction)
CallbackRegistry:RegisterCallback("LayoutRefresh", function()
    if testMode then
        RefreshTestDisplay()
    else
        UpdateDisplay()
    end
end)

-- Display changes (enabled buffs, visibility settings)
CallbackRegistry:RegisterCallback("DisplayRefresh", function()
    if testMode then
        RefreshTestDisplay()
    else
        UpdateDisplay()
    end
end)

-- Structural changes (split categories)
CallbackRegistry:RegisterCallback("FramesReparent", function()
    ReparentBuffFrames()
    UpdateVisuals()
end)

-- ============================================================================
-- IMPORT/EXPORT FUNCTIONS
-- ============================================================================

-- Deep copy a table
local function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Export helpers for Options.lua
BR.Helpers = {
    GetBuffSettingKey = GetBuffSettingKey,
    IsBuffEnabled = IsBuffEnabled,
    GetCategorySettings = GetCategorySettings,
    IsCategorySplit = IsCategorySplit,
    GetBuffTexture = GetBuffTexture,
    DeepCopy = DeepCopy,
    GetCurrentContentType = GetCurrentContentType,
    IsCategoryVisibleForContent = IsCategoryVisibleForContent,
    ValidateSpellID = ValidateSpellID,
    GenerateCustomBuffKey = GenerateCustomBuffKey,
}

-- Export display functions for Options.lua
BR.Display = {
    Update = UpdateDisplay,
    RefreshTest = RefreshTestDisplay,
    ToggleTestMode = ToggleTestMode,
    UpdateVisuals = UpdateVisuals,
    UpdateFallback = UpdateFallbackDisplay,
    IsTestMode = function()
        return testMode
    end,
    ResetMainFramePosition = function(point, x, y)
        if mainFrame then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint(point, UIParent, point, x, y)
        end
    end,
    ResetCategoryFramePosition = function(category, point, x, y)
        local frame = categoryFrames[category]
        if frame then
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, point, x, y)
        end
    end,
}

-- Serialize a Lua table to a base64-encoded CBOR string
local function SerializeTable(tbl)
    local success, cbor = pcall(C_EncodingUtil.SerializeCBOR, tbl)
    if not success then
        return nil
    end
    return C_EncodingUtil.EncodeBase64(cbor)
end

-- Deserialize a base64-encoded CBOR string back to a Lua table
local function DeserializeTable(str)
    if not str or str:trim() == "" then
        return nil, "Empty input"
    end

    local success, decoded = pcall(C_EncodingUtil.DecodeBase64, str)
    if not success or not decoded then
        return nil, "Invalid format: not valid base64"
    end

    local ok, data = pcall(C_EncodingUtil.DeserializeCBOR, decoded)
    if not ok or type(data) ~= "table" then
        return nil, "Invalid data: failed to deserialize"
    end

    return data
end

-- Export current settings to a serialized string (only includes valid settings from defaults + customBuffs)
local function ExportSettings()
    local export = {}

    -- Only export fields that exist in defaults (excluding locked)
    for key in pairs(defaults) do
        if key ~= "locked" and BuffRemindersDB[key] ~= nil then
            export[key] = DeepCopy(BuffRemindersDB[key])
        end
    end

    -- Also include custom buffs
    if BuffRemindersDB.customBuffs then
        export.customBuffs = DeepCopy(BuffRemindersDB.customBuffs)
    end

    local result = SerializeTable(export)
    if not result then
        return nil, "Failed to serialize settings"
    end
    return result
end

-- Import settings from a serialized string (preserves locked state)
local function ImportSettings(str)
    local data, err = DeserializeTable(str)
    if not data then
        return false, err
    end

    -- Preserve current locked state
    local currentLocked = BuffRemindersDB.locked

    -- Deep merge imported data into BuffRemindersDB
    for k, v in pairs(data) do
        BuffRemindersDB[k] = DeepCopy(v)
    end

    -- Restore locked state
    BuffRemindersDB.locked = currentLocked

    return true
end

-- ============================================================================
-- PUBLIC API (for external addon integration)
-- ============================================================================

--- Export settings to a prefixed string that can be imported by other addons
--- @param profileKey string|nil Optional profile name (ignored - BuffReminders uses single profile)
--- @return string|nil Encoded settings string with !BR_ prefix, or nil on error
--- @return string|nil Error message if export failed
function BuffReminders:Export(profileKey)
    local exportString, err = ExportSettings()
    if not exportString then
        return nil, err
    end
    return EXPORT_PREFIX .. exportString
end

--- Import settings from a prefixed string
--- @param importString string The encoded settings string (must start with !BR_)
--- @param profileKey string|nil Optional profile name (ignored - BuffReminders uses single profile)
--- @return boolean success Whether the import succeeded
--- @return string|nil error Error message if import failed
function BuffReminders:Import(importString, profileKey)
    if not importString or type(importString) ~= "string" then
        return false, "Invalid import string"
    end

    -- Validate prefix
    if importString:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return false, "Invalid import string (missing prefix)"
    end

    -- Strip prefix and import
    local dataString = importString:sub(#EXPORT_PREFIX + 1)
    return ImportSettings(dataString)
end

-- Slash command handler
local function SlashHandler(msg)
    local cmd = msg:match("^(%S*)") or ""
    cmd = cmd:lower()

    if cmd == "test" then
        ToggleTestMode(false) -- no labels, for previews
    else
        BR.Options.Toggle()
    end
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_UNGHOST")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("READY_CHECK")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

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

        -- Migrate old global settings to categorySettings.main
        local db = BuffRemindersDB
        if not db.categorySettings then
            db.categorySettings = {}
        end
        if not db.categorySettings.main then
            db.categorySettings.main = {}
        end
        -- Copy old settings if categorySettings.main doesn't have them
        if db.iconSize and not db.categorySettings.main.iconSize then
            db.categorySettings.main.iconSize = db.iconSize
        end
        if db.spacing and not db.categorySettings.main.spacing then
            db.categorySettings.main.spacing = db.spacing
        end
        if db.growDirection and not db.categorySettings.main.growDirection then
            db.categorySettings.main.growDirection = db.growDirection
        end
        if db.position and not db.categorySettings.main.position then
            db.categorySettings.main.position = {
                point = db.position.point,
                x = db.position.x,
                y = db.position.y,
            }
        end

        -- Initialize categoryVisibility with defaults for each category
        if not db.categoryVisibility then
            db.categoryVisibility = {}
        end
        for _, category in ipairs(CATEGORIES) do
            if not db.categoryVisibility[category] then
                local defaultVis = defaults.categoryVisibility[category]
                db.categoryVisibility[category] = {
                    openWorld = defaultVis and defaultVis.openWorld ~= false,
                    dungeon = defaultVis and defaultVis.dungeon ~= false,
                    scenario = defaultVis and defaultVis.scenario ~= false,
                    raid = defaultVis and defaultVis.raid ~= false,
                }
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
        desc:SetText("Track missing buffs at a glance.")

        local openBtn = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
        openBtn:SetSize(150, 24)
        openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
        openBtn:SetText("Open Options")
        openBtn:SetScript("OnClick", function()
            BR.Options.Toggle()
            -- Close the WoW settings panel properly (HideUIPanel handles keyboard focus cleanup)
            if SettingsPanel then
                HideUIPanel(SettingsPanel)
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
        if not InCombatLockdown() then
            StartUpdates()
        end
        -- Delayed update to catch glow events that fire after reload
        C_Timer.After(0.5, function()
            UpdateDisplay()
        end)
    elseif event == "GROUP_ROSTER_UPDATE" then
        UpdateDisplay()
    elseif event == "PLAYER_REGEN_ENABLED" then
        StartUpdates()
    elseif event == "PLAYER_REGEN_DISABLED" then
        StopUpdates()
        UpdateDisplay()
    elseif event == "PLAYER_DEAD" then
        HideAllDisplayFrames()
    elseif event == "PLAYER_UNGHOST" then
        UpdateDisplay()
    elseif event == "UNIT_AURA" then
        -- Skip in combat (auras change frequently, but we can't check buffs anyway)
        if not InCombatLockdown() and mainFrame and mainFrame:IsShown() then
            UpdateDisplay()
        end
    elseif event == "READY_CHECK" then
        -- Cancel any existing timer
        if readyCheckTimer then
            readyCheckTimer:Cancel()
        end
        inReadyCheck = true
        UpdateDisplay()
        -- Start timer to reset ready check state
        local duration = BuffRemindersDB.readyCheckDuration or 15
        readyCheckTimer = C_Timer.NewTimer(duration, function()
            inReadyCheck = false
            readyCheckTimer = nil
            UpdateDisplay()
        end)
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        local spellID = arg1
        glowingSpells[spellID] = true
        UpdateDisplay()
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local spellID = arg1
        glowingSpells[spellID] = nil
        UpdateDisplay()
    end
end)
