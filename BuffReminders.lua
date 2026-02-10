local addonName, BR = ...

-- Shared constants (from Core.lua)
local DEFAULT_BORDER_SIZE = BR.DEFAULT_BORDER_SIZE
local DEFAULT_ICON_ZOOM = BR.DEFAULT_ICON_ZOOM

-- LibSharedMedia for font resolution
local LSM = LibStub("LibSharedMedia-3.0")

-- Masque integration (optional)
local Masque = LibStub("Masque", true)
local masqueGroup = Masque and Masque:Group("BuffReminders")

local function IsMasqueActive()
    return masqueGroup ~= nil and not masqueGroup.db.Disabled
end

-- Cached font path — resolved once on load and updated when the setting changes (via VisualsRefresh).
-- All SetFont calls read this local directly instead of calling LSM:Fetch() every time.
local fontPath = STANDARD_TEXT_FONT

---Resolve the font path from saved settings and update the cache
local function ResolveFontPath()
    local fontName = BuffRemindersDB and BuffRemindersDB.defaults and BuffRemindersDB.defaults.fontFace
    if fontName then
        local path = LSM:Fetch("font", fontName)
        if path then
            fontPath = path
            return
        end
    end
    fontPath = STANDARD_TEXT_FONT
end

-- Global API table for external addon integration
BuffReminders = {}
local EXPORT_PREFIX = "!BR_"

-- Buff tables from Buffs.lua (via BR namespace)
local BUFF_TABLES = BR.BUFF_TABLES

-- Local aliases for direct access
local RaidBuffs = BUFF_TABLES.raid
local PresenceBuffs = BUFF_TABLES.presence
local TargetedBuffs = BUFF_TABLES.targeted
local SelfBuffs = BUFF_TABLES.self
local PetBuffs = BUFF_TABLES.pet
local Consumables = BUFF_TABLES.consumable
local CustomBuffs = BUFF_TABLES.custom

-- Build icon override lookup table (for spells replaced by talents)
local IconOverrides = {} ---@type table<number, number>
for _, buffArray in ipairs({ PresenceBuffs, TargetedBuffs, SelfBuffs, PetBuffs }) do
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

---Rebuild BUFF_TABLES.custom from db.customBuffs (preserves table identity via wipe)
local function BuildCustomBuffArray()
    local db = BuffRemindersDB
    wipe(CustomBuffs)
    if not db or not db.customBuffs then
        return
    end
    local sortedKeys = {}
    for k in pairs(db.customBuffs) do
        sortedKeys[#sortedKeys + 1] = k
    end
    table.sort(sortedKeys)
    for _, k in ipairs(sortedKeys) do
        CustomBuffs[#CustomBuffs + 1] = db.customBuffs[k]
    end
end

-- Get helpers from State.lua
local GetBuffSettingKey = function(buff)
    return BR.StateHelpers.GetBuffSettingKey(buff)
end
local IsBuffEnabled = function(key)
    return BR.StateHelpers.IsBuffEnabled(key)
end

-- Default settings
-- Note: enabledBuffs defaults to all enabled - only set false to disable by default
local defaults = {
    locked = true,
    enabledBuffs = {
        delveFood = false,
        burningRush = false,
    },
    showOnlyInGroup = false,
    showOnlyPlayerClassBuff = false,
    showOnlyPlayerMissing = false,
    showOnlyOnReadyCheck = false,
    hidePetWhileMounted = true,
    petPassiveOnlyInCombat = false,
    readyCheckDuration = 15, -- seconds
    optionsPanelScale = 1.2, -- base scale (displayed as 100%)
    showLoginMessages = true,

    -- Global defaults (inherited by categories unless overridden)
    ---@type DefaultSettings
    defaults = {
        -- Appearance
        iconSize = 64,
        -- textSize: nil = auto (derived from iconSize * 0.32). Only set when user explicitly overrides.
        iconAlpha = 1,
        textAlpha = 1,
        textColor = { 1, 1, 1 },
        spacing = 0.2, -- multiplier of iconSize
        iconZoom = 8, -- percentage
        borderSize = 2,
        growDirection = "CENTER", -- "LEFT", "CENTER", "RIGHT", "UP", "DOWN"
        -- Behavior (glow is global-only)
        showExpirationGlow = true,
        expirationThreshold = 15, -- minutes
        glowStyle = 1, -- 1=Orange, 2=Gold, 3=Yellow, 4=White, 5=Red
        -- Consumable rebuff warning
        showConsumablesWithoutItems = false,
        consumableRebuffWarning = true,
        consumableRebuffThreshold = 10, -- minutes
        consumableRebuffColor = { 1, 0.5, 0 },
        consumableDisplayMode = "sub_icons",
        petDisplayMode = "expanded", -- "generic" or "expanded"
    },

    ---@type CategoryVisibility
    categoryVisibility = { -- Which content types each category shows in
        raid = { openWorld = true, dungeon = true, scenario = true, raid = true },
        presence = { openWorld = true, dungeon = true, scenario = true, raid = true },
        targeted = { openWorld = false, dungeon = true, scenario = true, raid = true },
        self = { openWorld = true, dungeon = true, scenario = true, raid = true },
        pet = { openWorld = true, dungeon = true, scenario = true, raid = true },
        consumable = {
            openWorld = false,
            dungeon = true,
            scenario = true,
            raid = true,
            dungeonDifficulty = {
                normal = false,
                heroic = false,
                mythic = true,
                mythicPlus = false,
                timewalking = false,
                follower = false,
            },
            raidDifficulty = {
                lfr = false,
                normal = true,
                heroic = true,
                mythic = true,
            },
        },
        custom = { openWorld = true, dungeon = true, scenario = true, raid = true },
    },

    ---@type AllCategorySettings
    categorySettings = { -- Per-category settings
        main = {
            position = { point = "CENTER", x = 0, y = 0 },
            -- main frame always uses defaults for appearance/behavior
        },
        raid = {
            position = { point = "CENTER", x = 0, y = 60 },
            useCustomAppearance = false,
            showBuffReminder = true,
            split = false,
            clickable = false,
            clickableHighlight = true,
            priority = 1,
        },
        presence = {
            position = { point = "CENTER", x = 0, y = 20 },
            useCustomAppearance = false,
            split = false,
            clickable = false,
            clickableHighlight = true,
            priority = 2,
        },
        targeted = {
            position = { point = "CENTER", x = 0, y = -20 },
            useCustomAppearance = false,
            split = false,
            clickable = false,
            clickableHighlight = true,
            priority = 3,
        },
        self = {
            position = { point = "CENTER", x = 0, y = -60 },
            useCustomAppearance = false,
            split = false,
            clickable = false,
            clickableHighlight = true,
            priority = 4,
        },
        pet = {
            position = { point = "CENTER", x = 0, y = -100 },
            useCustomAppearance = false,
            split = false,
            clickable = false,
            clickableHighlight = true,
            priority = 5,
        },
        consumable = {
            position = { point = "CENTER", x = 0, y = -140 },
            useCustomAppearance = false,
            split = false,
            clickable = false,
            clickableHighlight = true,
            priority = 6,
        },
        custom = {
            position = { point = "CENTER", x = 0, y = -180 },
            useCustomAppearance = false,
            split = false,
            clickable = false,
            clickableHighlight = true,
            priority = 7,
        },
    },
}

-- Constants
local MISSING_TEXT_SCALE = 0.6 -- scale for "NO X" warning text

-- Locals
local mainFrame
local buffFrames = {}
local updateTicker
local readyCheckTimer = nil
local testMode = false
local testModeData = nil -- Stores seeded fake values for consistent test display
local playerClass = nil -- Cached player class, set once on init
local playerRole = nil -- Cached player role, invalidated on spec change
local glowingSpells = {} -- Track which spell IDs are currently glowing (for action bar glow fallback)

-- Throttle for UNIT_AURA events (can fire rapidly during raid-wide buffs)
local AURA_THROTTLE = 0.2 -- seconds
local lastAuraUpdate = 0

-- Track combat state via events (InCombatLockdown() can lag behind PLAYER_REGEN_DISABLED)
local inCombat = false
local isResting = false

-- Category frame system
local categoryFrames = {}
local moverFrames = {} -- Per-category mover frames (shown when unlocked for drag positioning)
local CATEGORIES = { "raid", "presence", "targeted", "self", "pet", "consumable", "custom" }
local CATEGORY_LABELS = {
    raid = "Raid",
    presence = "Presence",
    targeted = "Targeted",
    self = "Self",
    pet = "Pet",
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
    -- Check new location first (categorySettings.{cat}.split)
    if db.categorySettings and db.categorySettings[category] then
        if db.categorySettings[category].split ~= nil then
            return db.categorySettings[category].split == true
        end
    end
    -- Fall back to legacy location (splitCategories.{cat})
    return db.splitCategories and db.splitCategories[category] == true
end

---Check if all categories are split (mainFrame would be empty)
---@return boolean
local function AreAllCategoriesSplit()
    for _, category in ipairs(CATEGORIES) do
        if not IsCategorySplit(category) then
            return false
        end
    end
    return true
end

---Get settings for a category with inheritance from defaults
---Uses BR.Config.GetCategorySetting for inherited values when applicable
---@param category string
---@return table A table with all effective settings for this category
local function GetCategorySettings(category)
    local db = BuffRemindersDB
    local catSettings = db.categorySettings and db.categorySettings[category]
    local globalDefaults = db.defaults or defaults.defaults

    -- For main frame, always use global defaults
    if category == "main" then
        return {
            position = catSettings and catSettings.position or { point = "CENTER", x = 0, y = 0 },
            iconSize = globalDefaults.iconSize or 64,
            textSize = globalDefaults.textSize, -- nil = auto (derived from iconSize)
            iconAlpha = globalDefaults.iconAlpha or 1,
            textAlpha = globalDefaults.textAlpha or 1,
            textColor = globalDefaults.textColor or { 1, 1, 1 },
            spacing = globalDefaults.spacing or 0.2,
            iconZoom = globalDefaults.iconZoom or 8,
            borderSize = globalDefaults.borderSize or 2,
            growDirection = globalDefaults.growDirection or "CENTER",
            showBuffReminder = false, -- main uses per-frame logic based on buff's actual category
            showExpirationGlow = globalDefaults.showExpirationGlow ~= false,
            expirationThreshold = globalDefaults.expirationThreshold or 15,
            glowStyle = globalDefaults.glowStyle or 1,
        }
    end

    -- For other categories, use inheritance
    local result = {}
    local defaultCatSettings = defaults.categorySettings[category] or {}

    -- Position is always category-specific
    result.position = catSettings and catSettings.position
        or defaultCatSettings.position
        or { point = "CENTER", x = 0, y = 0 }
    result.split = catSettings and catSettings.split or false

    -- Appearance: inherit from defaults unless useCustomAppearance is true
    local useCustomAppearance = catSettings and catSettings.useCustomAppearance
    if useCustomAppearance then
        -- Custom appearance: use category values, fall back to code defaults (NOT user's global defaults)
        -- This ensures custom-appearance categories are fully independent from Global Defaults changes.
        -- Values are snapshotted from current defaults when useCustomAppearance is first enabled.
        result.iconSize = (catSettings and catSettings.iconSize) or 64
        result.textSize = (catSettings and catSettings.textSize) -- nil = auto
        result.iconAlpha = (catSettings and catSettings.iconAlpha) or 1
        result.textAlpha = (catSettings and catSettings.textAlpha) or 1
        result.textColor = (catSettings and catSettings.textColor) or { 1, 1, 1 }
        result.spacing = (catSettings and catSettings.spacing) or 0.2
        result.iconZoom = (catSettings and catSettings.iconZoom) or 8
        result.borderSize = (catSettings and catSettings.borderSize) or 2
    else
        result.iconSize = globalDefaults.iconSize or 64
        result.textSize = globalDefaults.textSize -- nil = auto
        result.iconAlpha = globalDefaults.iconAlpha or 1
        result.textAlpha = globalDefaults.textAlpha or 1
        result.textColor = globalDefaults.textColor or { 1, 1, 1 }
        result.spacing = globalDefaults.spacing or 0.2
        result.iconZoom = globalDefaults.iconZoom or 8
        result.borderSize = globalDefaults.borderSize or 2
    end

    -- Direction: inherit from defaults unless split (split frames have their own direction)
    if result.split then
        result.growDirection = (catSettings and catSettings.growDirection) or globalDefaults.growDirection or "CENTER"
    else
        result.growDirection = globalDefaults.growDirection or "CENTER"
    end

    -- BUFF! text: direct per-category for raid only
    if category == "raid" then
        result.showBuffReminder = not catSettings or catSettings.showBuffReminder ~= false
    else
        result.showBuffReminder = false
    end

    -- Glow: always from global defaults
    result.showExpirationGlow = globalDefaults.showExpirationGlow ~= false
    result.expirationThreshold = globalDefaults.expirationThreshold or 15
    result.glowStyle = globalDefaults.glowStyle or 1

    return result
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

---Check if overlay text should be shown for a given category
---@param category? CategoryName
---@return boolean
local function ShouldShowText(category)
    if not category then
        return true
    end
    local cs = BuffRemindersDB.categorySettings and BuffRemindersDB.categorySettings[category]
    return not cs or cs.showText ~= false
end

-- Fallback text scale ratio (used when textSize is not set)
local TEXT_SCALE_RATIO = 0.32

---Calculate font size, preferring explicit textSize over iconSize-derived
---@param scale? number
---@param textSize? number
---@param iconSize? number
---@return number
local function GetFontSize(scale, textSize, iconSize)
    local baseSize = textSize or math.floor((iconSize or 64) * TEXT_SCALE_RATIO)
    return math.max(6, math.floor(baseSize * (scale or 1)))
end

---Get font size for a specific frame based on its effective category
---@param frame table
---@param scale? number
---@return number
local function GetFrameFontSize(frame, scale)
    local effectiveCat = GetEffectiveCategory(frame)
    local catSettings = GetCategorySettings(effectiveCat)
    return GetFontSize(scale, catSettings.textSize, catSettings.iconSize)
end

-- Use functions from State.lua
local FormatRemainingTime = BR.StateHelpers.FormatRemainingTime

---Get player's current role (cached, invalidated on spec change)
---@return RoleType?
local function GetPlayerRole()
    if playerRole then
        return playerRole
    end
    local spec = GetSpecialization()
    if spec then
        playerRole = GetSpecializationRole(spec)
        return playerRole
    end
    return nil
end

---Invalidate player role cache (call on PLAYER_SPECIALIZATION_CHANGED)
local function InvalidatePlayerRoleCache()
    playerRole = nil
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

-- Action bar button names to scan for glows
-- Reverse lookup: spellID → buff entry (for glow fallback detection across all categories)
local glowSpellToBuff = {}

--- Register a buff's spellID(s) in the glow fallback lookup table
local function RegisterGlowBuff(buff, catName)
    local ids = type(buff.spellID) == "table" and buff.spellID or { buff.spellID }
    for _, id in ipairs(ids) do
        if id and id ~= 0 then
            glowSpellToBuff[id] = { buff = buff, category = catName }
        end
    end
end

--- Unregister spellID(s) from the glow fallback lookup table
---@param spellID number|number[] Single spell ID or table of spell IDs
local function UnregisterGlowSpell(spellID)
    local ids = type(spellID) == "table" and spellID or { spellID }
    for _, id in ipairs(ids) do
        if id then
            glowSpellToBuff[id] = nil
        end
    end
end

for catName, category in pairs(BUFF_TABLES) do
    for _, buff in ipairs(category) do
        if not buff.enchantID and not buff.customCheck and not buff.readyCheckOnly then
            RegisterGlowBuff(buff, catName)
        end
    end
end

-- Seed glowingSpells with any already-active overlay glows (covers login/reload/zone change)
local IsSpellOverlayed = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
local function SeedGlowingSpells()
    if not IsSpellOverlayed then
        return
    end
    for spellID, entry in pairs(glowSpellToBuff) do
        if (not entry.buff.class or entry.buff.class == playerClass) and IsSpellOverlayed(spellID) then
            glowingSpells[spellID] = true
        end
    end
end

-- Forward declarations
local UpdateDisplay, UpdateAnchor, ToggleTestMode, RefreshTestDisplay
local UpdateFallbackDisplay, RenderPetEntries
local UpdateActionButtons

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
    local styleIndex = (db.defaults and db.defaults.glowStyle) or 1

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

-- Forward declaration for SetRebuffBorder (defined after glow styles)
local SetRebuffBorder

-- Hide a buff frame and clear its glow and rebuff border.
-- Overlays and action buttons are managed solely by SyncSecureButtons() based on
-- frame:IsShown(), so we don't touch them here — avoids hide/show flicker when
-- UpdateDisplay() hides all frames then re-shows visible ones each tick.
local function HideFrame(frame)
    frame:Hide()
    SetExpirationGlow(frame, false)
    SetRebuffBorder(frame, false)
end

---Show a frame with missing text styling
---@param frame BuffFrame
---@param missingText? string
---@return boolean true (for anyVisible chaining)
local function ShowMissingFrame(frame, missingText)
    if missingText then
        frame.count:SetFont(fontPath, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
        frame.count:SetText(missingText)
        frame.count:Show()
    else
        frame.count:Hide()
    end
    frame:Show()
    SetExpirationGlow(frame, false)
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

-- Create a category frame for grouped display mode
local function CreateCategoryFrame(category)
    local db = BuffRemindersDB
    local catSettings = db.categorySettings and db.categorySettings[category] or defaults.categorySettings[category]
    local pos = catSettings.position or defaults.categorySettings[category].position

    local frame = CreateFrame("Frame", "BuffReminders_Category_" .. category, UIParent)
    frame:SetSize(200, 50)
    frame:SetPoint("CENTER", UIParent, "CENTER", pos.x or 0, pos.y or 0)
    frame.category = category
    frame:EnableMouse(false)

    frame:Hide()
    return frame
end

-- Create icon and border textures on a buff frame (no positioning — call UpdateIconStyling after)
local function CreateIconTextures(frame, texture)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    frame.icon:SetDesaturated(false)
    frame.icon:SetVertexColor(1, 1, 1, 1)
    if texture then
        frame.icon:SetTexture(texture)
    end

    frame.border = frame:CreateTexture(nil, "BACKGROUND")
    frame.border:SetColorTexture(0, 0, 0, 1)
end

-- Apply icon zoom and border sizing (single source of truth for Masque vs native styling)
local function UpdateIconStyling(frame, catSettings)
    if IsMasqueActive() then
        -- Masque controls TexCoord; hide our border for a clean borderless look
        frame.border:Hide()
        return
    end
    -- Native styling: our zoom and border
    local zoom = (catSettings.iconZoom or DEFAULT_ICON_ZOOM) / 100
    frame.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    local borderSize = catSettings.borderSize or DEFAULT_BORDER_SIZE
    frame.border:ClearAllPoints()
    frame.border:SetPoint("TOPLEFT", -borderSize, borderSize)
    frame.border:SetPoint("BOTTOMRIGHT", borderSize, -borderSize)
    frame.border:Show()
end

-- Find the first spell ID the player can actually cast (returns nil if none)
---@param spellIDs SpellID
---@return number?
local function GetCastableSpellID(spellIDs)
    if spellIDs == nil then
        return nil
    end
    if type(spellIDs) ~= "table" then
        return IsPlayerSpell(spellIDs) and spellIDs or nil
    end
    for _, id in ipairs(spellIDs) do
        if IsPlayerSpell(id) then
            return id
        end
    end
    return nil
end

-- Pre-filter a buff's spell by talent/spec requirements, then find a castable spell ID.
-- Checks excludeTalentSpellID, requiresTalentSpellID, and requireSpecId before delegating
-- to GetCastableSpellID. Returns nil if the buff is filtered out or no spell is castable.
---@param buff table The buff definition table
---@return number?
local function GetActionSpellID(buff)
    if buff.excludeTalentSpellID and IsPlayerSpell(buff.excludeTalentSpellID) then
        return nil
    end
    if buff.requiresTalentSpellID and not IsPlayerSpell(buff.requiresTalentSpellID) then
        return nil
    end
    if buff.requireSpecId then
        local spec = GetSpecialization()
        if spec then
            local specId = GetSpecializationInfo(spec)
            if specId ~= buff.requireSpecId then
                return nil
            end
        end
    end
    return GetCastableSpellID(buff.castSpellID or buff.spellID)
end

-- Create a SecureActionButton overlay for click-to-cast on a buff frame.
-- Parented to UIParent with NO anchors to the buff frame hierarchy, avoiding any
-- layout dependency that would make the frame hierarchy protected/secure.
-- Position is synced manually by SyncSecureButtons() after each layout pass.
---@param frame table The parent buff frame
local function CreateClickOverlay(frame)
    local overlay = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    overlay:RegisterForClicks("AnyDown", "AnyUp")
    overlay:EnableMouse(false)
    overlay:Hide()
    -- Auto-hide in combat (secure state driver), auto-show after
    RegisterStateDriver(overlay, "visibility", "[combat] hide; show")
    -- When state driver re-shows after combat, hide if buff frame isn't visible
    overlay:SetScript("OnShow", function(self)
        if not frame:IsShown() then
            self:Hide()
        end
    end)
    -- Refresh display shortly after click so the consumed buff disappears quickly
    overlay:SetScript("PostClick", function()
        C_Timer.After(0.3, function()
            if not InCombatLockdown() then
                UpdateDisplay()
            end
        end)
    end)
    overlay.highlight = overlay:CreateTexture(nil, "HIGHLIGHT")
    overlay.highlight:SetAllPoints()
    overlay.highlight:SetTexCoord(BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET, BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET)
    overlay.highlight:SetColorTexture(1, 1, 1, 0.2)
    frame.clickOverlay = overlay
end

-- ============================================================================
-- CONSUMABLE ACTION BUTTONS
-- ============================================================================

local ACTION_ICON_SCALE = 0.45
local ACTION_ICON_MIN = 18
local ACTION_ICON_Y_OFFSET = -6

-- Quality pip atlas names for crafted consumables (rank 1/2/3)
local QUALITY_ATLAS = {
    [1] = "Professions-Icon-Quality-Tier1-Inv",
    [2] = "Professions-Icon-Quality-Tier2-Inv",
    [3] = "Professions-Icon-Quality-Tier3-Inv",
}

---Set or hide a quality pip overlay texture based on crafted quality.
---@param overlay Texture The overlay texture to update
---@param craftedQuality number? The crafted quality tier (1-3) or nil
---@param size number The parent icon size (pip is 50% of this)
local function SetQualityOverlay(overlay, craftedQuality, size)
    local atlas = craftedQuality and QUALITY_ATLAS[craftedQuality]
    if atlas then
        overlay:SetAtlas(atlas)
        overlay:SetSize(size * 0.5, size * 0.5)
        overlay:Show()
    else
        overlay:Hide()
    end
end

---Create a small SecureActionButton for the consumable item row.
---Parented to UIParent with NO anchors to buff frames (avoids taint).
---Position synced by SyncSecureButtons().
---@return table btn The created button
local function CreateActionButton()
    local btn = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    btn:RegisterForClicks("AnyDown", "AnyUp")
    btn:Hide()
    -- Start hidden — state driver activated by SyncSecureButtons() after positioning
    RegisterStateDriver(btn, "visibility", "hide")
    -- When state driver re-shows after combat, hide if buff frame isn't visible
    btn:SetScript("OnShow", function(self)
        local bf = self._br_buff_frame
        if not bf or not bf:IsShown() then
            self:Hide()
        end
    end)
    -- Refresh display shortly after click so the consumed buff disappears quickly
    btn:SetScript("PostClick", function()
        C_Timer.After(0.3, function()
            if not InCombatLockdown() then
                UpdateDisplay()
            end
        end)
    end)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET, BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET)

    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    btn.count:SetPoint("BOTTOMRIGHT", -1, 1)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetTexCoord(BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET, BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET)
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)

    btn.qualityOverlay = btn:CreateTexture(nil, "OVERLAY")
    btn.qualityOverlay:SetPoint("TOPLEFT", 1, -1)
    btn.qualityOverlay:Hide()

    return btn
end

-- Consumable item cache: only rescan bags when BAG_UPDATE_DELAYED fires
local consumableCache = {} -- key → items array (or nil)
local consumableCacheDirty = true

local function InvalidateConsumableCache()
    consumableCacheDirty = true
end

---Scan bags for all consumable categories and populate the cache.
local function RefreshConsumableCache()
    if not consumableCacheDirty then
        return
    end
    consumableCacheDirty = false

    if not C_Container or not C_Container.GetContainerNumSlots then
        wipe(consumableCache)
        return
    end

    local itemSets = BR.CONSUMABLE_ITEMS or {}
    -- Scan all bags once, bucket items by consumable category
    local buckets = {} -- category → { [itemID] = { count, icon } }
    local maxBags = NUM_BAG_SLOTS or 4
    for bag = 0, maxBags do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then
                for category, allowedSet in pairs(itemSets) do
                    if allowedSet[itemID] and not (buckets[category] and buckets[category][itemID]) then
                        if not buckets[category] then
                            buckets[category] = {}
                        end
                        local ok, count = pcall(C_Item.GetItemCount, itemID, false, true)
                        count = (ok and count) or 0
                        if count > 0 then
                            local info = C_Container.GetContainerItemInfo(bag, slot)
                            local icon = info and info.iconFileID or nil
                            local itemLink = info and info.hyperlink
                            local cq = nil
                            if itemLink then
                                -- Parse crafted quality tier from the embedded atlas in the item link
                                -- e.g. |A:Professions-ChatIcon-Quality-Tier2:17:15::1|a → tier 2
                                local tier = tostring(itemLink):match("Professions%-ChatIcon%-Quality%-Tier(%d)")
                                if tier then
                                    cq = tonumber(tier)
                                end
                            end
                            buckets[category][itemID] = {
                                itemID = itemID,
                                count = count,
                                icon = icon,
                                craftedQuality = cq,
                            }
                        end
                    end
                end
            end
        end
    end

    -- Convert buckets to sorted arrays
    wipe(consumableCache)
    for category, entries in pairs(buckets) do
        local items = {}
        for _, item in pairs(entries) do
            items[#items + 1] = item
        end
        table.sort(items, function(a, b)
            if a.count == b.count then
                return a.itemID < b.itemID
            end
            return a.count > b.count
        end)
        consumableCache[category] = items
    end
end

-- Map buff key → CONSUMABLE_ITEMS category key
local BUFF_KEY_TO_CATEGORY = {
    flask = "flask",
    food = "food",
    rune = "rune",
    weaponBuff = "weapon",
}

---Get cached consumable items for a buff definition.
---@param buff table The buff definition table
---@return table[]? items Array of { itemID, count, icon } sorted by count desc, or nil
local function GetConsumableActionItems(buff)
    if not buff then
        return nil
    end
    local category = BUFF_KEY_TO_CATEGORY[buff.key]
    if not category then
        return nil
    end
    RefreshConsumableCache()
    local items = consumableCache[category]
    return items and #items > 0 and items or nil
end

---Create/update the item icons for a consumable buff frame.
---Sets attributes, textures, and marks buttons visible. Positioning is handled
---separately by SyncSecureButtons() (no anchors to avoid taint).
---@param frame table The buff frame
---@param actionItems table[]? Array of { itemID, count, icon }
---@param clickable boolean? Whether buttons should accept mouse input
local function UpdateConsumableButtons(frame, actionItems, clickable)
    if not actionItems or #actionItems <= 1 then
        if frame.actionButtons then
            for _, btn in ipairs(frame.actionButtons) do
                btn._br_visible = false
                btn:Hide()
            end
        end
        return
    end

    if not frame.actionButtons then
        frame.actionButtons = {}
    end

    for i, item in ipairs(actionItems) do
        local btn = frame.actionButtons[i]
        if not btn then
            btn = CreateActionButton()
            btn._br_buff_frame = frame
            frame.actionButtons[i] = btn
        end

        btn.itemID = item.itemID
        btn.icon:SetTexture(item.icon or 134400)
        btn._br_craftedQuality = item.craftedQuality

        -- Dirty tracking: skip redundant SetAttribute calls
        if btn._br_action_item ~= item.itemID then
            if frame.key == "weaponBuff" then
                btn:SetAttribute("type", "macro")
                btn:SetAttribute("macrotext", "/use item:" .. tostring(item.itemID) .. "\n/use 16")
            else
                btn:SetAttribute("type", "item")
                btn:SetAttribute("item", "item:" .. tostring(item.itemID))
            end
            btn._br_action_item = item.itemID
        end

        btn:EnableMouse(clickable == true)
        btn._br_visible = true
        btn._br_count = item.count
        btn._br_needs_sync = true
    end

    -- Mark unused buttons hidden
    for i = #actionItems + 1, #frame.actionButtons do
        frame.actionButtons[i]._br_visible = false
        frame.actionButtons[i]:Hide()
    end
end

-- Sync all secure button positions/sizes/visibility with their buff frames.
-- Uses screen coordinates (no anchors) so secure frames never taint the buff hierarchy.
-- Safe to call at any time; skips if in combat lockdown.
local function SyncSecureButtons()
    if InCombatLockdown() then
        return
    end
    for _, frame in pairs(buffFrames) do
        -- Sync click overlay
        local overlay = frame.clickOverlay
        if overlay then
            local cs = frame.buffCategory
                and BuffRemindersDB.categorySettings
                and BuffRemindersDB.categorySettings[frame.buffCategory]
            local clickable = cs and cs.clickable == true
            if frame:IsShown() then
                if not clickable then
                    overlay:EnableMouse(false)
                    overlay:Hide()
                    overlay._br_left = nil
                else
                    local left, bottom, width, height = frame:GetRect()
                    if left then
                        -- Skip if position unchanged (avoids redundant ClearAllPoints/SetPoint)
                        if
                            overlay._br_left ~= left
                            or overlay._br_bottom ~= bottom
                            or overlay._br_width ~= width
                            or overlay._br_height ~= height
                        then
                            overlay:ClearAllPoints()
                            overlay:SetSize(width, height)
                            overlay:SetFrameStrata(frame:GetFrameStrata())
                            overlay:SetFrameLevel(frame:GetFrameLevel() + 5)
                            overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
                            overlay._br_left = left
                            overlay._br_bottom = bottom
                            overlay._br_width = width
                            overlay._br_height = height
                        end
                        overlay:EnableMouse(true)
                        if not overlay:IsShown() then
                            overlay:Show()
                        end
                    end
                end
            else
                overlay:Hide()
                overlay:EnableMouse(false)
                overlay._br_left = nil
            end
        end
        -- Sync action buttons (consumable item row)
        if frame.actionButtons then
            if frame:IsShown() then
                local left, bottom, width, _ = frame:GetRect()
                if left then
                    local effectiveCat = GetEffectiveCategory(frame)
                    local catSettings = GetCategorySettings(effectiveCat)
                    local size = math.max(ACTION_ICON_MIN, math.floor((catSettings.iconSize or 64) * ACTION_ICON_SCALE))
                    local btnSpacing = math.max(2, math.floor(size * 0.2))
                    -- Count visible buttons
                    local visibleCount = 0
                    for _, btn in ipairs(frame.actionButtons) do
                        if btn._br_visible then
                            visibleCount = visibleCount + 1
                        end
                    end
                    if visibleCount > 0 then
                        -- Wrap into rows based on main icon width
                        local maxPerRow = math.max(1, math.floor((width + btnSpacing) / (size + btnSpacing)))
                        local idx = 0
                        for _, btn in ipairs(frame.actionButtons) do
                            if btn._br_visible then
                                local col = idx % maxPerRow
                                local row = math.floor(idx / maxPerRow)
                                -- Recalculate row width for partial last row
                                local thisRowCount = math.min(maxPerRow, visibleCount - row * maxPerRow)
                                local thisRowWidth = thisRowCount * size + (thisRowCount - 1) * btnSpacing
                                local thisRowStartX = left + (width - thisRowWidth) / 2
                                local btnX = thisRowStartX + col * (size + btnSpacing)
                                local btnY = bottom + ACTION_ICON_Y_OFFSET - size - row * (size + btnSpacing)
                                local needsUpdate = btn._br_needs_sync
                                    or btn._br_x ~= btnX
                                    or btn._br_y ~= btnY
                                    or btn._br_size ~= size
                                if needsUpdate then
                                    -- Reposition
                                    btn:ClearAllPoints()
                                    btn:SetSize(size, size)
                                    btn:SetFrameStrata(frame:GetFrameStrata())
                                    btn:SetFrameLevel(frame:GetFrameLevel() + 4)
                                    btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", btnX, btnY)
                                    btn._br_x = btnX
                                    btn._br_y = btnY
                                    btn._br_size = size
                                    -- Update text/font (only when data or size changed)
                                    btn.count:SetText(
                                        btn._br_count and btn._br_count > 1 and tostring(btn._br_count) or ""
                                    )
                                    btn.count:SetFont(fontPath, math.max(10, math.floor(size * 0.45)), "OUTLINE")
                                    SetQualityOverlay(btn.qualityOverlay, btn._br_craftedQuality, size)
                                    btn._br_needs_sync = false
                                end
                                -- Activate combat state driver on first show (buttons start with "hide" driver)
                                if not btn._br_driver_active then
                                    RegisterStateDriver(btn, "visibility", "[combat] hide; show")
                                    btn._br_driver_active = true
                                end
                                if not btn:IsShown() then
                                    btn:Show()
                                end
                                idx = idx + 1
                            end
                        end
                    end
                    -- Hide buttons that are no longer visible
                    for _, btn in ipairs(frame.actionButtons) do
                        if not btn._br_visible and btn._br_driver_active then
                            RegisterStateDriver(btn, "visibility", "hide")
                            btn._br_driver_active = false
                            btn._br_x = nil
                        end
                    end
                end
            else
                for _, btn in ipairs(frame.actionButtons) do
                    if btn._br_driver_active then
                        RegisterStateDriver(btn, "visibility", "hide")
                        btn._br_driver_active = false
                        btn._br_x = nil
                    else
                        btn:Hide()
                    end
                end
            end
        end
        -- Sync extra frame click overlays (expanded consumable display mode)
        if frame.extraFrames then
            for _, extra in ipairs(frame.extraFrames) do
                local extraOverlay = extra.clickOverlay
                if extraOverlay then
                    if extra:IsShown() then
                        local extraCs = frame.buffCategory
                            and BuffRemindersDB.categorySettings
                            and BuffRemindersDB.categorySettings[frame.buffCategory]
                        local extraClickable = extraCs and extraCs.clickable == true
                        if not extraClickable then
                            extraOverlay:EnableMouse(false)
                            extraOverlay:Hide()
                            extraOverlay._br_left = nil
                        else
                            local eLeft, eBottom, eWidth, eHeight = extra:GetRect()
                            if eLeft then
                                if
                                    extraOverlay._br_left ~= eLeft
                                    or extraOverlay._br_bottom ~= eBottom
                                    or extraOverlay._br_width ~= eWidth
                                    or extraOverlay._br_height ~= eHeight
                                then
                                    extraOverlay:ClearAllPoints()
                                    extraOverlay:SetSize(eWidth, eHeight)
                                    extraOverlay:SetFrameStrata(extra:GetFrameStrata())
                                    extraOverlay:SetFrameLevel(extra:GetFrameLevel() + 5)
                                    extraOverlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", eLeft, eBottom)
                                    extraOverlay._br_left = eLeft
                                    extraOverlay._br_bottom = eBottom
                                    extraOverlay._br_width = eWidth
                                    extraOverlay._br_height = eHeight
                                end
                                extraOverlay:EnableMouse(true)
                                if not extraOverlay:IsShown() then
                                    extraOverlay:Show()
                                end
                            end
                        end
                    else
                        extraOverlay:Hide()
                        extraOverlay:EnableMouse(false)
                        extraOverlay._br_left = nil
                    end
                end
            end
        end
    end
end

-- Schedule secure button sync for the next frame (after layout has been calculated)
local syncPending = false
local function ScheduleSecureSync()
    if syncPending then
        return
    end
    syncPending = true
    C_Timer.After(0, function()
        syncPending = false
        SyncSecureButtons()
    end)
end

-- Create icon frame for a buff
local function CreateBuffFrame(buff, category)
    local frame = CreateFrame("Frame", "BuffReminders_" .. buff.key, mainFrame)
    frame.key = buff.key
    frame.spellIDs = buff.spellID
    frame.displayName = buff.name
    frame.buffCategory = category
    frame.buffDef = buff

    local db = BuffRemindersDB
    -- Use effective category settings (respects split categories)
    local effectiveCat = (category and IsCategorySplit(category)) and category or "main"
    local catSettings = GetCategorySettings(effectiveCat)
    local iconSize = catSettings.iconSize or 64
    frame:SetSize(iconSize, iconSize)

    -- Icon + border textures
    local iconOverride = buff.iconOverride
    if type(iconOverride) == "table" then
        iconOverride = iconOverride[1] -- Use first icon for buff frame
    end
    local texture = iconOverride or GetBuffTexture(buff.spellID, buff.iconByRole)
    CreateIconTextures(frame, texture)

    frame.qualityOverlay = frame:CreateTexture(nil, "OVERLAY")
    frame.qualityOverlay:SetPoint("TOPLEFT", 5, -4)
    frame.qualityOverlay:Hide()

    -- Register with Masque (Normal = false: we handle borders, Masque handles TexCoord)
    if masqueGroup then
        masqueGroup:AddButton(frame, {
            Icon = frame.icon,
            Normal = false,
        })
    end

    -- Apply initial zoom/border state (respects Masque)
    UpdateIconStyling(frame, catSettings)

    -- Count text (font size scales with icon size, updated in UpdateVisuals)
    local textColor = catSettings.textColor or { 1, 1, 1 }
    local textAlpha = catSettings.textAlpha or 1
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    frame.count:SetPoint("CENTER", 0, 0)
    frame.count:SetTextColor(textColor[1], textColor[2], textColor[3], textAlpha)
    frame.count:SetFont(fontPath, GetFontSize(1, catSettings.textSize, catSettings.iconSize), "OUTLINE")

    -- Stack count (bottom-right, WoW-standard item count style) for consumables
    frame.stackCount = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    frame.stackCount:SetPoint("BOTTOMRIGHT", -5, 4)
    frame.stackCount:Hide()

    -- Frame alpha
    frame:SetAlpha(catSettings.iconAlpha or 1)

    -- "BUFF!" text for the class that provides this buff (raid buffs only)
    frame.isPlayerBuff = (playerClass == buff.class)
    if frame.isPlayerBuff and category == "raid" then
        frame.buffText = frame:CreateFontString(nil, "OVERLAY")
        frame.buffText:SetPoint("TOP", frame, "BOTTOM", 0, -6)
        frame.buffText:SetFont(fontPath, GetFontSize(0.8, catSettings.textSize, catSettings.iconSize), "OUTLINE")
        frame.buffText:SetTextColor(textColor[1], textColor[2], textColor[3], textAlpha)
        frame.buffText:SetText("BUFF!")
        local raidCs = db.categorySettings and db.categorySettings.raid
        if raidCs and raidCs.showBuffReminder == false then
            frame.buffText:Hide()
        end
    end

    -- "TEST" text (shown above icon in test mode)
    frame.testText = frame:CreateFontString(nil, "OVERLAY")
    frame.testText:SetPoint("BOTTOM", frame, "TOP", 0, 25)
    frame.testText:SetFont(fontPath, GetFontSize(0.6, catSettings.textSize, catSettings.iconSize), "OUTLINE")
    frame.testText:SetTextColor(1, 0.8, 0, 1)
    frame.testText:SetText("TEST")
    frame.testText:Hide()

    -- Always click-through (dragging is handled by anchor handles)
    frame:EnableMouse(false)

    frame:Hide()
    return frame
end

-- Get or create an extra frame for expanded consumable display mode.
-- Extra frames are stored lazily in frame.extraFrames[index] and share the same
-- visual structure as the main buff frame (icon, border, stackCount, Masque).
---@param frame table The main consumable buff frame
---@param index number 1-based index for the extra frame
---@return table extra The extra frame (shown/hidden by caller)
local function GetOrCreateExtraFrame(frame, index)
    if not frame.extraFrames then
        frame.extraFrames = {}
    end
    local extra = frame.extraFrames[index]
    if extra then
        return extra
    end

    extra = CreateFrame("Frame", nil, frame:GetParent())
    extra.isExtraFrame = true
    extra.mainFrame = frame
    extra.buffCategory = frame.buffCategory
    extra.key = frame.key .. "_extra_" .. index

    local effectiveCat = GetEffectiveCategory(frame)
    local catSettings = GetCategorySettings(effectiveCat)
    local iconSize = catSettings.iconSize or 64
    extra:SetSize(iconSize, iconSize)

    CreateIconTextures(extra, nil)

    extra.qualityOverlay = extra:CreateTexture(nil, "OVERLAY")
    extra.qualityOverlay:SetPoint("TOPLEFT", 5, -4)
    extra.qualityOverlay:Hide()

    if masqueGroup then
        masqueGroup:AddButton(extra, {
            Icon = extra.icon,
            Normal = false,
        })
    end

    UpdateIconStyling(extra, catSettings)

    -- Stack count (bottom-right, same as main frame)
    extra.stackCount = extra:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    extra.stackCount:SetPoint("BOTTOMRIGHT", -5, 4)
    extra.stackCount:Hide()

    -- Count text (for consistency, though expanded frames mainly use stackCount)
    local textColor = catSettings.textColor or { 1, 1, 1 }
    local textAlpha = catSettings.textAlpha or 1
    extra.count = extra:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    extra.count:SetPoint("CENTER", 0, 0)
    extra.count:SetTextColor(textColor[1], textColor[2], textColor[3], textAlpha)
    extra.count:SetFont(fontPath, GetFontSize(1, catSettings.textSize, catSettings.iconSize), "OUTLINE")
    extra.count:Hide()

    extra:SetAlpha(catSettings.iconAlpha or 1)
    extra:EnableMouse(false)
    extra:Hide()

    frame.extraFrames[index] = extra
    return extra
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

-- Build a sorted category list by priority
local function GetSortedCategories()
    local db = BuffRemindersDB
    local sorted = {}
    for i, category in ipairs(CATEGORIES) do
        sorted[#sorted + 1] = { name = category, index = i }
    end
    table.sort(sorted, function(a, b)
        local aPri = db.categorySettings and db.categorySettings[a.name] and db.categorySettings[a.name].priority
            or defaults.categorySettings[a.name].priority
        local bPri = db.categorySettings and db.categorySettings[b.name] and db.categorySettings[b.name].priority
            or defaults.categorySettings[b.name].priority
        if aPri == bPri then
            return a.index < b.index
        end
        return aPri < bPri
    end)
    return sorted
end

-- Position and size the main container frame with the given buff frames
local function PositionMainContainer(mainFrameBuffs)
    local db = BuffRemindersDB

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
        local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
        local pos = (db.categorySettings and db.categorySettings.main and db.categorySettings.main.position)
            or db.position
            or { point = "CENTER", x = 0, y = 0 }
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(anchor, UIParent, "CENTER", pos.x or 0, pos.y or 0)

        PositionFramesInContainer(mainFrame, mainFrameBuffs, iconSize, spacing, direction)
        mainFrame:Show()
    else
        mainFrame:Hide()
    end
end

-- Position and size a split category frame with the given buff frames
local function PositionSplitCategory(category, frames)
    local catFrame = categoryFrames[category]
    if not catFrame then
        return
    end

    local catSettings = GetCategorySettings(category)
    local direction = catSettings.growDirection or "CENTER"
    local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
    local pos = catSettings.position or { point = "CENTER", x = 0, y = 0 }

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

        catFrame:ClearAllPoints()
        catFrame:SetPoint(anchor, UIParent, "CENTER", pos.x or 0, pos.y or 0)

        PositionFramesInContainer(catFrame, frames, iconSize, spacing, direction)
        catFrame:Show()
    else
        catFrame:Hide()
    end
end

-- Hide split category frames that have no visible buffs, and hide non-split category frames
local function PositionSplitCategories(visibleByCategory)
    for _, category in ipairs(CATEGORIES) do
        local catFrame = categoryFrames[category]
        if catFrame then
            if IsCategorySplit(category) then
                local entries = visibleByCategory[category]
                if not entries or #entries == 0 then
                    -- No visible buffs: still position (mover handles visibility)
                    PositionSplitCategory(category, {})
                end
            else
                -- Not split - hide category frame
                catFrame:Hide()
            end
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
            frame.count:SetFont(fontPath, GetFrameFontSize(frame), "OUTLINE")
            if (db.defaults and db.defaults.showExpirationGlow ~= false) and not glowShown then
                frame.count:SetText(FormatRemainingTime(testModeData.fakeRemaining))
                SetExpirationGlow(frame, true)
                glowShown = true
            else
                local fakeBuffed = testModeData.fakeTotal - testModeData.fakeMissing[i]
                frame.count:SetText(fakeBuffed .. "/" .. testModeData.fakeTotal)
            end
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(fontPath, GetFrameFontSize(frame, 0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL presence buffs
    for _, buff in ipairs(PresenceBuffs) do
        local frame = buffFrames[buff.key]
        if frame then
            frame.count:SetFont(fontPath, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
            frame.count:SetText(buff.missingText)
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(fontPath, GetFrameFontSize(frame, 0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL targeted buffs
    for _, buff in ipairs(TargetedBuffs) do
        local frame = buffFrames[buff.key]
        if frame then
            frame.count:SetText(buff.missingText)
            frame.count:SetFont(fontPath, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(fontPath, GetFrameFontSize(frame, 0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL self buffs
    for _, buff in ipairs(SelfBuffs) do
        local frame = buffFrames[buff.key]
        if frame then
            frame.count:SetText(buff.missingText)
            frame.count:SetFont(fontPath, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(fontPath, GetFrameFontSize(frame, 0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL pet buffs
    for _, buff in ipairs(PetBuffs) do
        local frame = buffFrames[buff.key]
        if frame then
            frame.count:SetText(buff.missingText)
            frame.count:SetFont(fontPath, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(fontPath, GetFrameFontSize(frame, 0.6), "OUTLINE")
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
            frame.count:SetFont(fontPath, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(fontPath, GetFrameFontSize(frame, 0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Show ALL custom buffs
    for _, buff in ipairs(CustomBuffs) do
        local frame = buffFrames[buff.key]
        if frame then
            if buff.missingText then
                frame.count:SetFont(fontPath, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
                frame.count:SetText(buff.missingText)
                frame.count:Show()
            else
                frame.count:Hide()
            end
            if frame.testText and testModeData.showLabels then
                frame.testText:SetFont(fontPath, GetFrameFontSize(frame, 0.6), "OUTLINE")
                frame.testText:Show()
            end
            frame:Show()
        end
    end

    -- Position using category-first helpers
    local sortedCategories = GetSortedCategories()
    local mainFrameBuffs = {}

    -- Collect shown frames by category for positioning
    local shownByCategory = {}
    for _, frame in pairs(buffFrames) do
        if frame:IsShown() and frame.buffCategory then
            local cat = frame.buffCategory
            if not shownByCategory[cat] then
                shownByCategory[cat] = {}
            end
            table.insert(shownByCategory[cat], frame)
        end
    end

    for _, catEntry in ipairs(sortedCategories) do
        local category = catEntry.name
        local frames = shownByCategory[category] or {}

        if #frames > 0 and IsCategorySplit(category) then
            PositionSplitCategory(category, frames)
        elseif not IsCategorySplit(category) then
            for _, frame in ipairs(frames) do
                table.insert(mainFrameBuffs, frame)
            end
        end
    end

    PositionMainContainer(mainFrameBuffs)
    PositionSplitCategories(shownByCategory)
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
            fakeRemaining = math.random(1, (db.defaults and db.defaults.expirationThreshold) or 15) * 60,
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
    mainFrame:Hide()
    for _, category in ipairs(CATEGORIES) do
        if categoryFrames[category] then
            categoryFrames[category]:Hide()
        end
    end
    -- Also hide individual buff frames (so they don't reappear when mainFrame is shown by fallback)
    for _, frame in pairs(buffFrames) do
        frame:Hide()
        if frame.extraFrames then
            for _, extra in ipairs(frame.extraFrames) do
                extra:Hide()
            end
        end
    end
end

-- Update the fallback display (shows tracked buffs via action bar glow during M+/PvP/combat)
-- Shows glow-based frames + pet frames, then collects ALL visible frames for unified positioning
UpdateFallbackDisplay = function()
    if not mainFrame then
        return
    end

    -- Show frames for any glowing spells (skip invertGlow buffs — handled in second pass)
    local seenKeys = {}
    local GetPlayerSpecId = BR.StateHelpers.GetPlayerSpecId
    for spellID, _ in pairs(glowingSpells) do
        local entry = glowSpellToBuff[spellID]
        if entry then
            local buff = entry.buff
            if not buff.invertGlow and (not buff.class or buff.class == playerClass) and not seenKeys[buff.key] then
                -- Skip targeted buffs when solo (they require a group target)
                local skipSolo = entry.category == "targeted" and GetNumGroupMembers() == 0
                -- Skip buffs requiring a specific spec
                local skipSpec = buff.requireSpecId and GetPlayerSpecId() ~= buff.requireSpecId
                if not skipSolo and not skipSpec then
                    seenKeys[buff.key] = true
                    local frame = buffFrames[buff.key]
                    if frame and IsBuffEnabled(buff.key) then
                        ShowMissingFrame(frame, buff.missingText)
                    end
                end
            end
        end
    end

    -- Second pass: show invertGlow buffs where NONE of their spells are glowing
    local invertedHasGlow = {}
    for spellID, _ in pairs(glowingSpells) do
        local entry = glowSpellToBuff[spellID]
        if entry and entry.buff.invertGlow then
            invertedHasGlow[entry.buff.key] = true
        end
    end
    for _, entry in pairs(glowSpellToBuff) do
        local buff = entry.buff
        if buff.invertGlow and not seenKeys[buff.key] and not invertedHasGlow[buff.key] then
            seenKeys[buff.key] = true
            if not buff.class or buff.class == playerClass then
                local skipSpec = buff.requireSpecId and GetPlayerSpecId() ~= buff.requireSpecId
                if not skipSpec then
                    local frame = buffFrames[buff.key]
                    if frame and IsBuffEnabled(buff.key) then
                        ShowMissingFrame(frame, buff.missingText)
                    end
                end
            end
        end
    end

    -- Pet frames are non-secure and customCheck works in all contexts
    BR.BuffState.Refresh()
    RenderPetEntries()

    -- Collect ALL visible frames (glow + pet + pet extra frames) for unified positioning
    local shownByCategory = {}
    local mainFrameBuffs = {}
    for _, frame in pairs(buffFrames) do
        if frame:IsShown() and frame.buffCategory then
            local category = frame.buffCategory
            if IsCategorySplit(category) then
                if not shownByCategory[category] then
                    shownByCategory[category] = {}
                end
                shownByCategory[category][#shownByCategory[category] + 1] = frame
            else
                mainFrameBuffs[#mainFrameBuffs + 1] = frame
            end
            -- Include expanded pet extra frames in the same list
            if frame.extraFrames then
                for _, extra in ipairs(frame.extraFrames) do
                    if extra:IsShown() then
                        if IsCategorySplit(category) then
                            shownByCategory[category][#shownByCategory[category] + 1] = extra
                        else
                            mainFrameBuffs[#mainFrameBuffs + 1] = extra
                        end
                    end
                end
            end
        end
    end

    if #mainFrameBuffs > 0 or next(shownByCategory) then
        for category, frames in pairs(shownByCategory) do
            PositionSplitCategory(category, frames)
        end
        if #mainFrameBuffs > 0 then
            PositionMainContainer(mainFrameBuffs)
        end
        UpdateAnchor()
    else
        HideAllDisplayFrames()
    end
end

-- Eating icon texture ID (from State.lua, matches the eating channel aura icon)
local EATING_ICON = BR.EATING_AURA_ICON

-- Show/hide rebuff warning pulsing border on a buff frame (4-edge border, does not obscure icon)
SetRebuffBorder = function(frame, show)
    if show then
        local color = (BuffRemindersDB and BuffRemindersDB.defaults and BuffRemindersDB.defaults.consumableRebuffColor)
            or { 1, 0.5, 0 }
        local cr, cg, cb = color[1] or 1, color[2] or 0.5, color[3] or 0
        if not frame.rebuffBorderFrame then
            local thickness = 2
            local holder = CreateFrame("Frame", nil, frame)
            holder:SetPoint("TOPLEFT", -thickness, thickness)
            holder:SetPoint("BOTTOMRIGHT", thickness, -thickness)
            holder:SetFrameLevel(frame:GetFrameLevel() + 5)
            -- Top
            local t = holder:CreateTexture(nil, "OVERLAY")
            t:SetPoint("TOPLEFT")
            t:SetPoint("TOPRIGHT")
            t:SetHeight(thickness)
            t:SetColorTexture(cr, cg, cb, 1)
            -- Bottom
            local b = holder:CreateTexture(nil, "OVERLAY")
            b:SetPoint("BOTTOMLEFT")
            b:SetPoint("BOTTOMRIGHT")
            b:SetHeight(thickness)
            b:SetColorTexture(cr, cg, cb, 1)
            -- Left
            local l = holder:CreateTexture(nil, "OVERLAY")
            l:SetPoint("TOPLEFT")
            l:SetPoint("BOTTOMLEFT")
            l:SetWidth(thickness)
            l:SetColorTexture(cr, cg, cb, 1)
            -- Right
            local r = holder:CreateTexture(nil, "OVERLAY")
            r:SetPoint("TOPRIGHT")
            r:SetPoint("BOTTOMRIGHT")
            r:SetWidth(thickness)
            r:SetColorTexture(cr, cg, cb, 1)

            local ag = holder:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0.3)
            fade:SetDuration(0.6)
            fade:SetSmoothing("IN_OUT")
            frame.rebuffBorderFrame = holder
            frame.rebuffBorderAnim = ag
            frame.rebuffBorderEdges = { t, b, l, r }
            frame.rebuffBorderColor = { cr, cg, cb }
        elseif
            frame.rebuffBorderColor[1] ~= cr
            or frame.rebuffBorderColor[2] ~= cg
            or frame.rebuffBorderColor[3] ~= cb
        then
            for _, edge in ipairs(frame.rebuffBorderEdges) do
                edge:SetColorTexture(cr, cg, cb, 1)
            end
            frame.rebuffBorderColor = { cr, cg, cb }
        end
        frame.rebuffBorderFrame:Show()
        if not frame.rebuffBorderAnim:IsPlaying() then
            frame.rebuffBorderAnim:Play()
        end
    else
        if frame.rebuffBorderFrame then
            frame.rebuffBorderAnim:Stop()
            frame.rebuffBorderFrame:Hide()
        end
    end
end

-- Resolve the correct icon for a consumable frame.
-- Uses the top item from the consumable cache (actual item in bags), falling back
-- to the buff definition's iconOverride or buffIconID.
local function ResolveConsumableIcon(frame)
    local items = GetConsumableActionItems(frame.buffDef)
    if items and items[1] and items[1].icon then
        frame.icon:SetTexture(items[1].icon)
        if frame.qualityOverlay then
            SetQualityOverlay(frame.qualityOverlay, items[1].craftedQuality, frame:GetWidth())
        end
    else
        local def = frame.buffDef
        local fallback = def and (def.iconOverride or def.buffIconID)
        if fallback then
            frame.icon:SetTexture(fallback)
        end
        if frame.qualityOverlay then
            frame.qualityOverlay:Hide()
        end
    end
end

-- Render a single visible entry into its frame using the appropriate display type.
-- Returns true if the frame was shown, false if it was skipped (e.g. consumable
-- with no bag items and showConsumablesWithoutItems off).
local function RenderVisibleEntry(frame, entry)
    -- Hide stack count and quality overlay by default; only the consumable-with-items path shows them
    frame.stackCount:Hide()
    if frame.qualityOverlay then
        frame.qualityOverlay:Hide()
    end

    -- Eating override: state provides isEating as a snapshot, so the display
    -- never reads a live flag that can change mid-cycle.
    if entry.isEating then
        frame.icon:SetTexture(EATING_ICON)
        frame._br_eating_icon = true
        frame.count:Hide()
        frame:Show()
        SetExpirationGlow(frame, false)
        SetRebuffBorder(frame, false)
        return true
    elseif frame._br_eating_icon then
        -- Transition from eating → not eating: restore the correct consumable icon
        frame._br_eating_icon = nil
        ResolveConsumableIcon(frame)
    end

    if entry.displayType == "count" then
        frame.count:SetFont(fontPath, GetFrameFontSize(frame), "OUTLINE")
        frame.count:SetText(entry.countText or "")
        frame.count:Show()
        frame:Show()
        SetExpirationGlow(frame, entry.shouldGlow)
        SetRebuffBorder(frame, false)
    elseif entry.displayType == "expiring" then
        frame.count:SetFont(fontPath, GetFrameFontSize(frame), "OUTLINE")
        frame.count:SetText(entry.countText or "")
        frame.count:Show()
        frame:Show()
        if entry.rebuffWarning then
            SetRebuffBorder(frame, true)
            SetExpirationGlow(frame, false)
        else
            SetRebuffBorder(frame, false)
            SetExpirationGlow(frame, true)
        end
    else -- "missing"
        -- Consumables with bag scan support: show actual item from bags
        if BUFF_KEY_TO_CATEGORY[frame.key] then
            local items = GetConsumableActionItems(frame.buffDef)
            if items then
                frame.icon:SetTexture(items[1].icon)
                if frame.qualityOverlay then
                    SetQualityOverlay(frame.qualityOverlay, items[1].craftedQuality, frame:GetWidth())
                end
                frame.count:Hide()
                frame.stackCount:SetText(items[1].count)
                frame.stackCount:Show()
                frame:Show()
                SetExpirationGlow(frame, false)
                SetRebuffBorder(frame, false)
            elseif (BuffRemindersDB.defaults or {}).showConsumablesWithoutItems then
                ShowMissingFrame(frame, entry.missingText)
                SetRebuffBorder(frame, false)
            else
                -- No items and setting is off: don't show the frame
                return false
            end
        else
            if entry.iconByRole then
                local texture = GetBuffTexture(frame.spellIDs, entry.iconByRole)
                if texture then
                    frame.icon:SetTexture(texture)
                end
            end
            ShowMissingFrame(frame, entry.missingText)
            SetRebuffBorder(frame, false)
        end
    end

    -- Per-category text visibility (uses buff's actual category, not effective/main)
    if not ShouldShowText(frame.buffCategory) then
        frame.count:Hide()
        frame.stackCount:Hide()
    end
    return true
end

---Apply consumable display mode (sub-icons or expanded extra frames) to a consumable frame.
---@param frame BuffFrame
---@param entry BuffStateEntry
---@param frameList table[] List to append extra frames to (for positioning)
---@param parentFrame Frame Parent for extra frames
local function ApplyConsumableDisplayMode(frame, entry, frameList, parentFrame)
    if entry.displayType ~= "missing" or entry.isEating then
        return
    end
    if not BUFF_KEY_TO_CATEGORY[frame.key] or not frame:IsShown() then
        return
    end

    local displayMode = (BuffRemindersDB.defaults or {}).consumableDisplayMode or "sub_icons"
    local items = GetConsumableActionItems(frame.buffDef)
    if displayMode == "sub_icons" then
        local cs = BuffRemindersDB.categorySettings and BuffRemindersDB.categorySettings.consumable
        local clickable = cs and cs.clickable == true
        UpdateConsumableButtons(frame, items, clickable)
    else
        -- Not sub_icons: hide any leftover sub-icon buttons
        UpdateConsumableButtons(frame, nil)
        if displayMode == "expanded" and items and #items > 1 then
            for i = 2, #items do
                local extra = GetOrCreateExtraFrame(frame, i - 1)
                extra:SetParent(parentFrame)
                extra:SetSize(frame:GetWidth(), frame:GetHeight())
                extra.icon:SetTexture(items[i].icon)
                if extra.qualityOverlay then
                    SetQualityOverlay(extra.qualityOverlay, items[i].craftedQuality, frame:GetWidth())
                end
                extra.stackCount:SetText(items[i].count)
                extra.stackCount:Show()
                extra.count:Hide()
                extra:Show()
                frameList[#frameList + 1] = extra
            end
        end
    end
end

-- Expand a pet entry's actions into the main frame + extra frames.
-- The first action overrides the main frame's icon; subsequent actions create extra frames.
-- Returns the extra frames appended to frameList (if provided).
---@param frame BuffFrame
---@param entry BuffStateEntry
---@param frameList? table[] List to append extra frames to (for positioning)
local function ExpandPetActions(frame, entry, frameList)
    if not entry.petActions or #entry.petActions == 0 or not frame:IsShown() then
        frame._br_pet_spell = nil
        return
    end

    -- Override main frame with first action
    local first = entry.petActions[1]
    frame.icon:SetTexture(first.icon)
    frame.count:Hide()
    frame._br_pet_spell = first.spellID

    -- Extra frames for remaining actions
    for i = 2, #entry.petActions do
        local action = entry.petActions[i]
        local extra = GetOrCreateExtraFrame(frame, i - 1)
        extra:SetParent(frame:GetParent())
        extra:SetSize(frame:GetWidth(), frame:GetHeight())
        extra.icon:SetTexture(action.icon)
        extra.count:Hide()
        extra.stackCount:Hide()
        extra._br_pet_spell = action.spellID
        extra:Show()
        if frameList then
            frameList[#frameList + 1] = extra
        end
    end
end

---Apply pet display mode to a frame: expand into extra frames or restore generic icon.
---@param frame BuffFrame
---@param entry BuffStateEntry
---@param frameList? table[] List to append extra frames to (for positioning)
local function ApplyPetDisplayMode(frame, entry, frameList)
    if not entry.petActions then
        return
    end
    local petMode = (BuffRemindersDB.defaults or {}).petDisplayMode or "expanded"
    if petMode == "expanded" then
        ExpandPetActions(frame, entry, frameList)
    else
        -- Generic mode: restore original icon, use preferred action for click-to-cast
        local texture = GetBuffTexture(frame.spellIDs)
        if texture then
            frame.icon:SetTexture(texture)
        end
        local gi = entry.petActions.genericIndex or 1
        frame._br_pet_spell = entry.petActions[gi] and entry.petActions[gi].spellID
        if frame.extraFrames then
            for _, extra in ipairs(frame.extraFrames) do
                extra:Hide()
            end
        end
    end
end

-- Render pet category entries (pet frames are non-secure and customCheck works in all contexts)
RenderPetEntries = function()
    local petEntries = BR.BuffState.visibleByCategory.pet
    if not petEntries or #petEntries == 0 then
        return
    end
    table.sort(petEntries, function(a, b)
        return a.sortOrder < b.sortOrder
    end)
    for _, entry in ipairs(petEntries) do
        local frame = buffFrames[entry.key]
        if frame then
            RenderVisibleEntry(frame, entry)
            ApplyPetDisplayMode(frame, entry)
        end
    end
end

-- Update the display
UpdateDisplay = function()
    if not mainFrame or testMode then
        return
    end

    -- Early exit: can't check buffs when dead, in combat, M+, instanced PvP, or player housing
    local _, instanceType = IsInInstance()
    local inMythicPlus = C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    local inHousing = C_Housing
        and (
            (C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot())
            or (C_Housing.IsOnNeighborhoodMap and C_Housing.IsOnNeighborhoodMap())
        )

    local isDead = UnitIsDeadOrGhost("player")
    -- Use both our event-tracked flag AND the API (event fires before API updates)
    local combatCheck = inCombat or InCombatLockdown()

    -- Absolute exit: nothing should show when dead or in housing
    if isDead or inHousing then
        HideAllDisplayFrames()
        return
    end

    -- Restricted contexts: hide secure frames, but glow + pet reminders can still show
    if inMythicPlus or instanceType == "pvp" or instanceType == "arena" then
        HideAllDisplayFrames()
        UpdateFallbackDisplay()
        ScheduleSecureSync()
        return
    end

    -- Combat: glow fallback + pet reminders (both handled by UpdateFallbackDisplay)
    if combatCheck then
        for _, frame in pairs(buffFrames) do
            HideFrame(frame)
        end
        UpdateFallbackDisplay()
        ScheduleSecureSync()
        return
    end

    local db = BuffRemindersDB

    -- Hide based on visibility settings
    if db.showOnlyOnReadyCheck and not BR.BuffState.GetReadyCheckState() then
        HideAllDisplayFrames()
        return
    end

    if db.showOnlyInGroup and GetNumGroupMembers() == 0 then
        HideAllDisplayFrames()
        return
    end

    if db.hideWhileResting and isResting then
        HideAllDisplayFrames()
        return
    end

    -- Refresh buff state
    BR.BuffState.Refresh()

    -- Hide all frames first
    for _, frame in pairs(buffFrames) do
        HideFrame(frame)
        if frame.extraFrames then
            for _, extra in ipairs(frame.extraFrames) do
                extra:Hide()
            end
        end
    end

    local visibleByCategory = BR.BuffState.visibleByCategory
    local anyVisible = false

    -- Build sorted category list by priority
    local sortedCategories = GetSortedCategories()

    -- Collect frames for main container (non-split) in priority order
    local mainFrameBuffs = {}

    for _, catEntry in ipairs(sortedCategories) do
        local category = catEntry.name
        local entries = visibleByCategory[category]

        if entries and #entries > 0 then
            table.sort(entries, function(a, b)
                return a.sortOrder < b.sortOrder
            end)
            anyVisible = true

            if IsCategorySplit(category) then
                -- Render + position this split category directly
                local frames = {}
                for _, entry in ipairs(entries) do
                    local frame = buffFrames[entry.key]
                    if frame then
                        local shown = RenderVisibleEntry(frame, entry)
                        if shown then
                            frames[#frames + 1] = frame
                        end
                        -- Category-specific post-processing
                        if category == "consumable" then
                            ApplyConsumableDisplayMode(frame, entry, frames, frame:GetParent())
                        elseif category == "pet" then
                            ApplyPetDisplayMode(frame, entry, frames)
                        end
                    end
                end
                PositionSplitCategory(category, frames)
            else
                -- Render, collect for main container
                for _, entry in ipairs(entries) do
                    local frame = buffFrames[entry.key]
                    if frame then
                        local shown = RenderVisibleEntry(frame, entry)
                        if shown then
                            mainFrameBuffs[#mainFrameBuffs + 1] = frame
                        end
                        -- Category-specific post-processing
                        if category == "consumable" then
                            ApplyConsumableDisplayMode(frame, entry, mainFrameBuffs, mainFrame)
                        elseif category == "pet" then
                            ApplyPetDisplayMode(frame, entry, mainFrameBuffs)
                        end
                    end
                end
            end
        end
    end

    -- Position main container
    PositionMainContainer(mainFrameBuffs)

    -- Handle split category frames with no visible buffs
    PositionSplitCategories(visibleByCategory)

    if not anyVisible then
        HideAllDisplayFrames()
    end
    UpdateAnchor()
    ScheduleSecureSync()

    -- Sync click overlays on expanded extra frames (they are created above but
    -- UpdateActionButtons is the only place that wires up their click overlays).
    if not InCombatLockdown() then
        local displayMode = (BuffRemindersDB.defaults or {}).consumableDisplayMode
        if displayMode == "expanded" then
            UpdateActionButtons("consumable")
        end
        UpdateActionButtons("pet")
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

-- Forward declaration for ReparentBuffFrames (defined after InitializeFrames)
local ReparentBuffFrames

-- Forward declaration for PositionMoverFrame
local PositionMoverFrame

---Round a number to the nearest integer
local function RoundCoord(x)
    return math.floor(x + 0.5)
end

---Get the saved position table for a category key
---@param catKey string "main" or a category name
---@return table position {point, x, y}
local function GetSavedPosition(catKey)
    local db = BuffRemindersDB
    if catKey == "main" then
        return (db.categorySettings and db.categorySettings.main and db.categorySettings.main.position)
            or db.position
            or { point = "CENTER", x = 0, y = 0 }
    end
    local catSettings = db.categorySettings and db.categorySettings[catKey]
    return (catSettings and catSettings.position)
        or (defaults.categorySettings[catKey] and defaults.categorySettings[catKey].position)
        or { point = "CENTER", x = 0, y = 0 }
end

---Save a position for a category key and reposition its frame
---@param catKey string "main" or a category name
---@param x number
---@param y number
local function SavePosition(catKey, x, y)
    local db = BuffRemindersDB
    if not db.categorySettings then
        db.categorySettings = {}
    end
    if not db.categorySettings[catKey] then
        db.categorySettings[catKey] = {}
    end
    db.categorySettings[catKey].position = { x = x, y = y }

    -- Reposition the icon container frame
    if catKey == "main" then
        if mainFrame then
            local mainSettings = GetCategorySettings("main")
            local direction = mainSettings.growDirection or "CENTER"
            local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint(anchor, UIParent, "CENTER", x, y)
        end
    else
        local catFrame = categoryFrames[catKey]
        if catFrame then
            local cs = GetCategorySettings(catKey)
            local direction = cs.growDirection or "CENTER"
            local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
            catFrame:ClearAllPoints()
            catFrame:SetPoint(anchor, UIParent, "CENTER", x, y)
        end
    end

    -- Keep the mover frame in sync
    PositionMoverFrame(catKey)
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

-- Dim/restore the icon container for a specific mover during drag
local EDIT_MODE_DIM_ALPHA = 0.3

local function GetContainerForCatKey(catKey)
    if catKey == "main" then
        return mainFrame
    end
    return categoryFrames[catKey]
end

local function DimContainer(catKey)
    local container = GetContainerForCatKey(catKey)
    if container then
        container:SetAlpha(EDIT_MODE_DIM_ALPHA)
    end
end

local function RestoreContainer(catKey)
    local container = GetContainerForCatKey(catKey)
    if container then
        container:SetAlpha(1)
    end
end

-- Finish a mover drag: read the direction-anchor edge, re-anchor, save
local function FinishMoverDrag(mover, catKey)
    mover:StopMovingOrSizing()
    local settings = GetCategorySettings(catKey)
    local direction = settings.growDirection or "CENTER"
    local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
    local px, py = UIParent:GetCenter()
    local x, y
    if anchor == "LEFT" then
        x = RoundCoord(mover:GetLeft() - px)
        y = RoundCoord(select(2, mover:GetCenter()) - py)
    elseif anchor == "RIGHT" then
        x = RoundCoord(mover:GetRight() - px)
        y = RoundCoord(select(2, mover:GetCenter()) - py)
    elseif anchor == "TOP" then
        x = RoundCoord((mover:GetCenter()) - px)
        y = RoundCoord(mover:GetTop() - py)
    elseif anchor == "BOTTOM" then
        x = RoundCoord((mover:GetCenter()) - px)
        y = RoundCoord(mover:GetBottom() - py)
    else -- CENTER
        local cx, cy = mover:GetCenter()
        x = RoundCoord(cx - px)
        y = RoundCoord(cy - py)
    end
    mover:ClearAllPoints()
    mover:SetPoint(anchor, UIParent, "CENTER", x, y)
    SavePosition(catKey, x, y)
    RestoreContainer(catKey)
end

-- Coordinate popup: shared popup for typing exact X/Y positions on mover frames
local coordPopup

local function CreateCoordinatePopup()
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(190, 110)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    popup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    popup:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 11, "OUTLINE")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Set Position")
    title:SetTextColor(1, 0.82, 0, 1)

    -- X row
    local xLabel = popup:CreateFontString(nil, "OVERLAY")
    xLabel:SetFont(fontPath, 11, "OUTLINE")
    xLabel:SetPoint("TOPLEFT", 10, -30)
    xLabel:SetText("X")
    xLabel:SetTextColor(1, 1, 1, 1)

    local xEdit = CreateFrame("EditBox", nil, popup)
    xEdit:SetSize(130, 20)
    xEdit:SetFont(fontPath, 11, "")
    xEdit:SetAutoFocus(false)
    local xContainer = BR.StyleEditBox(xEdit)
    xContainer:SetSize(130, 20)
    xContainer:SetPoint("LEFT", xLabel, "RIGHT", 8, 0)

    -- Y row
    local yLabel = popup:CreateFontString(nil, "OVERLAY")
    yLabel:SetFont(fontPath, 11, "OUTLINE")
    yLabel:SetPoint("TOPLEFT", 10, -56)
    yLabel:SetText("Y")
    yLabel:SetTextColor(1, 1, 1, 1)

    local yEdit = CreateFrame("EditBox", nil, popup)
    yEdit:SetSize(130, 20)
    yEdit:SetFont(fontPath, 11, "")
    yEdit:SetAutoFocus(false)
    local yContainer = BR.StyleEditBox(yEdit)
    yContainer:SetSize(130, 20)
    yContainer:SetPoint("LEFT", yLabel, "RIGHT", 8, 0)

    -- Apply button
    local applyBtn = BR.CreateButton(popup, "Apply", function()
        local xVal = tonumber(xEdit:GetText())
        local yVal = tonumber(yEdit:GetText())
        if not xVal or not yVal then
            return
        end
        local catKey = popup.catKey
        xVal = RoundCoord(xVal)
        yVal = RoundCoord(yVal)
        SavePosition(catKey, xVal, yVal)
        popup:Hide()
    end)
    applyBtn:SetPoint("BOTTOM", 0, 8)

    -- Tab from X to Y
    xEdit:SetScript("OnTabPressed", function()
        yEdit:SetFocus()
    end)

    -- Enter triggers Apply on either editbox
    xEdit:SetScript("OnEnterPressed", function()
        applyBtn:Click()
    end)
    yEdit:SetScript("OnEnterPressed", function()
        applyBtn:Click()
    end)
    yEdit:SetScript("OnTabPressed", function()
        xEdit:SetFocus()
    end)

    -- Escape to close
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    popup.xEdit = xEdit
    popup.yEdit = yEdit
    popup:Hide()
    return popup
end

local function ShowCoordinatePopup(catKey, mover)
    if not coordPopup then
        coordPopup = CreateCoordinatePopup()
    end
    coordPopup.catKey = catKey
    coordPopup.mover = mover
    coordPopup:ClearAllPoints()
    coordPopup:SetPoint("LEFT", mover, "RIGHT", 10, 0)

    local pos = GetSavedPosition(catKey)
    coordPopup.xEdit:SetText(tostring(pos.x or 0))
    coordPopup.yEdit:SetText(tostring(pos.y or 0))

    coordPopup:Show()
    coordPopup.xEdit:SetFocus()
end

-- Create a mover frame for positioning a category.
-- The mover is a 48×48 draggable frame parented to UIParent. Shown when unlocked.
local function CreateMoverFrame(catKey, displayName)
    local MOVER_SIZE = 48

    local mover = CreateFrame("Frame", nil, UIParent)
    mover:SetSize(MOVER_SIZE, MOVER_SIZE)
    mover:SetFrameStrata("HIGH")
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")

    -- Green background
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0.7, 0, 0.6)

    -- Label above the mover
    mover.label = mover:CreateFontString(nil, "OVERLAY")
    mover.label:SetPoint("BOTTOM", mover, "TOP", 0, 4)
    mover.label:SetFont(fontPath, 11, "OUTLINE")
    mover.label:SetTextColor(0.4, 1, 0.4, 1)
    mover.label:SetText(displayName or catKey)

    -- "Anchor" text below the green box (updated with growth direction in UpdateAnchor)
    mover.anchorText = mover:CreateFontString(nil, "OVERLAY")
    mover.anchorText:SetPoint("TOP", mover, "BOTTOM", 0, -4)
    mover.anchorText:SetFont(fontPath, 11, "OUTLINE")
    mover.anchorText:SetTextColor(0.4, 1, 0.4, 1)

    mover.catKey = catKey

    -- Position at saved location using direction-based anchor
    local pos = GetSavedPosition(catKey)
    local initSettings = GetCategorySettings(catKey)
    local initDirection = initSettings.growDirection or "CENTER"
    local initAnchor = DIRECTION_ANCHORS[initDirection] or "CENTER"
    mover:SetPoint(initAnchor, UIParent, "CENTER", pos.x or 0, pos.y or 0)

    -- Tooltip
    BR.SetupTooltip(mover, "Buff Anchor", "Drag to reposition\nRight-click to set exact coordinates")

    -- Drag scripts
    mover:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        if coordPopup then
            coordPopup:Hide()
        end
        DimContainer(catKey)
        self:StartMoving()
    end)
    mover:SetScript("OnDragStop", function(self)
        FinishMoverDrag(self, catKey)
    end)
    mover:SetScript("OnHide", function(self)
        if self:IsMovable() then
            FinishMoverDrag(self, catKey)
        end
    end)

    -- Right-click to open coordinate popup
    mover:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            ShowCoordinatePopup(catKey, self)
        end
    end)

    mover:Hide()
    return mover
end

-- Position a mover frame at its saved coordinates using direction-based anchor
PositionMoverFrame = function(catKey)
    local mover = moverFrames[catKey]
    if not mover then
        return
    end
    local pos = GetSavedPosition(catKey)
    local settings = GetCategorySettings(catKey)
    local direction = settings.growDirection or "CENTER"
    local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
    mover:ClearAllPoints()
    mover:SetPoint(anchor, UIParent, "CENTER", pos.x or 0, pos.y or 0)
end

-- Initialize main frame
local function InitializeFrames()
    mainFrame = CreateFrame("Frame", "BuffRemindersFrame", UIParent)
    mainFrame:SetSize(200, 50)

    local db = BuffRemindersDB
    local pos = (db.categorySettings and db.categorySettings.main and db.categorySettings.main.position)
        or db.position
        or { point = "CENTER", x = 0, y = 0 }
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", pos.x or 0, pos.y or 0)
    mainFrame:EnableMouse(false)

    -- Create category frames for grouped display mode
    for _, category in ipairs(CATEGORIES) do
        categoryFrames[category] = CreateCategoryFrame(category)
    end

    -- Create mover frames (shown when unlocked for drag positioning)
    moverFrames["main"] = CreateMoverFrame("main", GetMainFrameLabel())
    for _, category in ipairs(CATEGORIES) do
        moverFrames[category] = CreateMoverFrame(category, CATEGORY_LABELS[category])
    end

    -- Create buff frames for all categories (including custom, populated by BuildCustomBuffArray)
    for category, buffArray in pairs(BUFF_TABLES) do
        for _, buff in ipairs(buffArray) do
            buffFrames[buff.key] = CreateBuffFrame(buff, category)
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
    buffFrames[customBuff.key] = frame
    table.insert(CustomBuffs, customBuff)
    RegisterGlowBuff(customBuff, "custom")
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
        if frame.extraFrames then
            for _, extra in ipairs(frame.extraFrames) do
                extra:SetParent(frame:GetParent())
            end
        end
    end
end

---Remove a custom buff frame (called at runtime when deleting buffs)
---@param key string
local function RemoveCustomBuffFrame(key)
    local frame = buffFrames[key]
    if frame then
        UnregisterGlowSpell(frame.spellIDs)
        -- Clean up click overlay (unregister state driver before hiding)
        if frame.clickOverlay and not InCombatLockdown() then
            UnregisterStateDriver(frame.clickOverlay, "visibility")
            frame.clickOverlay:EnableMouse(false)
            frame.clickOverlay:Hide()
            frame.clickOverlay = nil
        end
        -- Clean up action buttons
        if frame.actionButtons and not InCombatLockdown() then
            for _, btn in ipairs(frame.actionButtons) do
                UnregisterStateDriver(btn, "visibility")
                btn:Hide()
            end
            frame.actionButtons = nil
        end
        frame:Hide()
        frame:SetParent(nil)
        buffFrames[key] = nil
    end
    -- Remove from BUFF_TABLES.custom array
    for i = #CustomBuffs, 1, -1 do
        if CustomBuffs[i].key == key then
            table.remove(CustomBuffs, i)
            break
        end
    end
end

-- Export custom buff management for Options.lua
BR.CustomBuffs = {
    CreateRuntime = CreateCustomBuffFrameRuntime,
    Remove = RemoveCustomBuffFrame,
    UpdateFrame = function(key, spellIDValue, displayName)
        local frame = buffFrames[key]
        if frame then
            -- Re-register glow lookup with new spellID
            UnregisterGlowSpell(frame.spellIDs)
            local texture = GetBuffTexture(spellIDValue)
            if texture then
                frame.icon:SetTexture(texture)
            end
            frame.displayName = displayName
            frame.spellIDs = spellIDValue
            -- Rebuild array (modal creates a new object for db.customBuffs[key], staling the old ref)
            BuildCustomBuffArray()
            local customBuff = BuffRemindersDB and BuffRemindersDB.customBuffs and BuffRemindersDB.customBuffs[key]
            if customBuff then
                RegisterGlowBuff(customBuff, "custom")
            end
        end
    end,
}

-- Update mover frame visibility and labels based on lock/split state.
-- IMPORTANT: Never reposition a mover that is already shown — doing so would cancel
-- an active StartMoving() drag via ClearAllPoints(). Only position on first show.
UpdateAnchor = function()
    if not mainFrame then
        return
    end

    local db = BuffRemindersDB
    local unlocked = not db.locked

    -- Main mover: show when unlocked AND not all categories split
    local allSplit = AreAllCategoriesSplit()
    local mainMover = moverFrames["main"]
    if mainMover then
        if unlocked and not allSplit then
            local mainSettings = GetCategorySettings("main")
            mainMover.label:SetText(GetMainFrameLabel())
            mainMover.anchorText:SetText("Anchor \194\183 Growth " .. (mainSettings.growDirection or "CENTER"))
            if not mainMover:IsShown() then
                PositionMoverFrame("main")
                mainMover:Show()
            end
        else
            mainMover:Hide()
        end
    end

    -- Category movers: show when unlocked AND that category is split
    for _, category in ipairs(CATEGORIES) do
        local mover = moverFrames[category]
        if mover then
            if unlocked and IsCategorySplit(category) then
                local catSettings = GetCategorySettings(category)
                mover.label:SetText(CATEGORY_LABELS[category])
                mover.anchorText:SetText("Anchor \194\183 Growth " .. (catSettings.growDirection or "CENTER"))
                if not mover:IsShown() then
                    PositionMoverFrame(category)
                    mover:Show()
                end
            else
                mover:Hide()
            end
        end
    end
end

-- Hide all mover frames
local function HideAllMovers()
    if coordPopup then
        coordPopup:Hide()
    end
    for _, mover in pairs(moverFrames) do
        if mover then
            mover:Hide()
        end
    end
end

-- Update icon sizes and text (called when settings change)
local function UpdateVisuals()
    for _, frame in pairs(buffFrames) do
        -- Use effective category settings (split category or "main")
        local effectiveCat = GetEffectiveCategory(frame)
        local catSettings = GetCategorySettings(effectiveCat)
        local size = catSettings.iconSize or 64
        frame:SetSize(size, size)
        frame.count:SetFont(fontPath, GetFrameFontSize(frame, 1), "OUTLINE")

        -- Text color and alpha
        local tc = catSettings.textColor or { 1, 1, 1 }
        local ta = catSettings.textAlpha or 1
        frame.count:SetTextColor(tc[1], tc[2], tc[3], ta)

        -- Frame alpha
        frame:SetAlpha(catSettings.iconAlpha or 1)

        if frame.buffText then
            frame.buffText:SetFont(fontPath, GetFrameFontSize(frame, 0.8), "OUTLINE")
            frame.buffText:SetTextColor(tc[1], tc[2], tc[3], ta)
            -- BUFF! text: use buff's actual category (raid only)
            local buffCat = frame.buffCategory
            local showReminder = false
            if buffCat == "raid" then
                local cs = BuffRemindersDB.categorySettings and BuffRemindersDB.categorySettings.raid
                showReminder = not cs or cs.showBuffReminder ~= false
            end
            frame.buffText:SetShown(showReminder)
        end
        UpdateIconStyling(frame, catSettings)

        -- Per-category text visibility
        if not ShouldShowText(frame.buffCategory) then
            frame.count:Hide()
        end

        -- Update extra frames (expanded consumable display mode)
        if frame.extraFrames then
            for _, extra in ipairs(frame.extraFrames) do
                extra:SetSize(size, size)
                UpdateIconStyling(extra, catSettings)
                extra:SetAlpha(catSettings.iconAlpha or 1)
            end
        end
    end
    if IsMasqueActive() then
        masqueGroup:ReSkin()
    end
    if testMode then
        RefreshTestDisplay()
    else
        UpdateDisplay()
    end
end

-- ============================================================================
-- CLICK-TO-CAST OVERLAY MANAGEMENT
-- ============================================================================

-- Update action buttons for all frames in a category based on the clickable setting.
-- Creates overlays lazily on first enable (WoW frames persist until /reload, so we
-- avoid creating them until the feature is actually used).
-- Must NOT be called during combat lockdown (secure frame operations are forbidden).
---@param category string
UpdateActionButtons = function(category)
    if InCombatLockdown() then
        return
    end

    local db = BuffRemindersDB
    local cs = db.categorySettings and db.categorySettings[category]
    local enabled = cs and cs.clickable == true
    local showHighlight = enabled and (cs.clickableHighlight ~= false)

    for _, frame in pairs(buffFrames) do
        if frame.buffCategory == category then
            if enabled then
                -- Lazily create overlay on first enable
                if not frame.clickOverlay then
                    CreateClickOverlay(frame)
                end
                if frame.clickOverlay.highlight then
                    frame.clickOverlay.highlight:SetShown(showHighlight)
                end
                if category == "consumable" then
                    local actionItems = GetConsumableActionItems(frame.buffDef)
                    -- Update main overlay (uses first/best item)
                    local mainBtn = frame.clickOverlay
                    if actionItems and #actionItems > 0 then
                        local item = actionItems[1]
                        mainBtn.itemID = item.itemID
                        if frame.key == "weaponBuff" then
                            mainBtn:SetAttribute("type", "macro")
                            mainBtn:SetAttribute("macrotext", "/use item:" .. item.itemID .. "\n/use 16")
                        else
                            mainBtn:SetAttribute("type", "item")
                            mainBtn:SetAttribute("item", "item:" .. item.itemID)
                        end
                        mainBtn:EnableMouse(true)
                    else
                        mainBtn.itemID = nil
                        mainBtn:EnableMouse(false)
                    end
                    -- Update clickability on existing sub-icon buttons
                    local displayMode = (db.defaults or {}).consumableDisplayMode or "sub_icons"
                    if displayMode == "sub_icons" and frame.actionButtons then
                        for _, btn in ipairs(frame.actionButtons) do
                            btn:EnableMouse(true)
                            if btn.highlight then
                                btn.highlight:SetShown(showHighlight)
                            end
                        end
                    end
                    -- Expanded mode: set up click overlays on extra frames
                    if displayMode == "expanded" and frame.extraFrames and actionItems then
                        for idx, extra in ipairs(frame.extraFrames) do
                            local itemIdx = idx + 1 -- extra[1] = items[2], etc.
                            if extra:IsShown() and actionItems[itemIdx] then
                                if not extra.clickOverlay then
                                    CreateClickOverlay(extra)
                                end
                                local eItem = actionItems[itemIdx]
                                extra.clickOverlay.itemID = eItem.itemID
                                if frame.key == "weaponBuff" then
                                    extra.clickOverlay:SetAttribute("type", "macro")
                                    extra.clickOverlay:SetAttribute(
                                        "macrotext",
                                        "/use item:" .. eItem.itemID .. "\n/use 16"
                                    )
                                else
                                    extra.clickOverlay:SetAttribute("type", "item")
                                    extra.clickOverlay:SetAttribute("item", "item:" .. eItem.itemID)
                                end
                                extra.clickOverlay:EnableMouse(true)
                                if extra.clickOverlay.highlight then
                                    extra.clickOverlay.highlight:SetShown(showHighlight)
                                end
                            elseif extra.clickOverlay then
                                extra.clickOverlay:EnableMouse(false)
                                extra.clickOverlay:Hide()
                                extra.clickOverlay._br_left = nil
                            end
                        end
                    elseif frame.extraFrames then
                        -- Not expanded: disable extra overlays
                        for _, extra in ipairs(frame.extraFrames) do
                            if extra.clickOverlay then
                                extra.clickOverlay:EnableMouse(false)
                                extra.clickOverlay:Hide()
                                extra.clickOverlay._br_left = nil
                            end
                        end
                    end
                else
                    -- Spells: pre-filter by talent/spec, then check castability
                    local overlay = frame.clickOverlay
                    overlay.itemID = nil
                    -- Pet actions: use per-frame spell from expanded pet icons
                    if frame._br_pet_spell then
                        overlay:SetAttribute("type", "spell")
                        overlay:SetAttribute("spell", frame._br_pet_spell)
                        overlay:EnableMouse(true)
                    else
                        local castableID = GetActionSpellID(frame.buffDef)
                        if castableID then
                            overlay:SetAttribute("type", "spell")
                            overlay:SetAttribute("spell", castableID)
                            overlay:SetAttribute("unit", category == "raid" and "player" or nil)
                            overlay:EnableMouse(true)
                        else
                            overlay:EnableMouse(false)
                        end
                    end
                    -- Pet extra frames: each has its own summon spell
                    if frame.extraFrames then
                        for _, extra in ipairs(frame.extraFrames) do
                            if extra:IsShown() and extra._br_pet_spell then
                                if not extra.clickOverlay then
                                    CreateClickOverlay(extra)
                                end
                                extra.clickOverlay:SetAttribute("type", "spell")
                                extra.clickOverlay:SetAttribute("spell", extra._br_pet_spell)
                                extra.clickOverlay:EnableMouse(true)
                                if extra.clickOverlay.highlight then
                                    extra.clickOverlay.highlight:SetShown(showHighlight)
                                end
                            elseif extra.clickOverlay then
                                extra.clickOverlay:EnableMouse(false)
                                extra.clickOverlay:Hide()
                                extra.clickOverlay._br_left = nil
                            end
                        end
                    end
                end
            elseif frame.clickOverlay then
                frame.clickOverlay:EnableMouse(false)
                frame.clickOverlay:Hide()
                frame.clickOverlay._br_left = nil
                -- Sub-icon buttons: disable mouse but keep visible if mode is sub_icons
                local displayMode = (db.defaults or {}).consumableDisplayMode or "sub_icons"
                if frame.actionButtons then
                    for _, btn in ipairs(frame.actionButtons) do
                        btn:EnableMouse(false)
                        if displayMode ~= "sub_icons" then
                            if btn._br_driver_active then
                                RegisterStateDriver(btn, "visibility", "hide")
                                btn._br_driver_active = false
                                btn._br_x = nil
                            else
                                btn:Hide()
                            end
                        end
                    end
                end
                -- Also disable extra frame overlays
                if frame.extraFrames then
                    for _, extra in ipairs(frame.extraFrames) do
                        if extra.clickOverlay then
                            extra.clickOverlay:EnableMouse(false)
                            extra.clickOverlay:Hide()
                            extra.clickOverlay._br_left = nil
                        end
                    end
                end
            end
        end
    end
    ScheduleSecureSync()
end

-- Refresh overlay spell attributes for all frames (e.g., after spec change).
-- Re-checks talent/spec pre-filters and IsPlayerSpell, updates EnableMouse + spell attribute.
-- Also refreshes consumable action buttons.
local function RefreshOverlaySpells()
    if InCombatLockdown() then
        return
    end

    local db = BuffRemindersDB
    for _, frame in pairs(buffFrames) do
        if frame.clickOverlay then
            local category = frame.buffCategory
            local cs = category and db.categorySettings and db.categorySettings[category]
            local enabled = cs and cs.clickable == true
            if enabled and category ~= "consumable" then
                local overlay = frame.clickOverlay
                local castableID = GetActionSpellID(frame.buffDef)
                if castableID then
                    overlay:SetAttribute("type", "spell")
                    overlay:SetAttribute("spell", castableID)
                    overlay:SetAttribute("unit", category == "raid" and "player" or nil)
                    overlay:EnableMouse(true)
                else
                    overlay:EnableMouse(false)
                end
            end
        end
    end
    -- Also refresh consumable and pet action buttons
    UpdateActionButtons("consumable")
    UpdateActionButtons("pet")
end

-- ============================================================================
-- CALLBACK REGISTRY SUBSCRIPTIONS
-- ============================================================================
-- Subscribe to config change events for automatic UI updates.
-- This decouples the options panel from the display system.

local CallbackRegistry = BR.CallbackRegistry

-- Visual changes (icon size, zoom, border, text visibility, font)
CallbackRegistry:RegisterCallback("VisualsRefresh", function()
    ResolveFontPath()
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

-- Display changes (enabled buffs, visibility settings, consumable display mode)
CallbackRegistry:RegisterCallback("DisplayRefresh", function()
    if testMode then
        RefreshTestDisplay()
    else
        UpdateDisplay()
    end
    -- Refresh consumable action button clickability/visibility after mode changes
    if not InCombatLockdown() then
        UpdateActionButtons("consumable")
    end
end)

-- Structural changes (split categories)
CallbackRegistry:RegisterCallback("FramesReparent", function()
    ReparentBuffFrames()
    UpdateVisuals()
end)

-- Masque skin change callback — restore our TexCoord when Masque is disabled
if masqueGroup then
    masqueGroup:RegisterCallback(function()
        UpdateVisuals()
        BR.Components.RefreshAll()
    end)
end

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

-- Export shared references for Options.lua
BR.LSM = LSM

-- Export helpers for Options.lua
BR.Helpers = {
    GetBuffSettingKey = GetBuffSettingKey,
    IsBuffEnabled = IsBuffEnabled,
    GetCategorySettings = GetCategorySettings,
    IsCategorySplit = IsCategorySplit,
    GetBuffTexture = GetBuffTexture,
    DeepCopy = DeepCopy,
    GetCurrentContentType = BR.StateHelpers.GetCurrentContentType,
    IsCategoryVisibleForContent = BR.StateHelpers.IsCategoryVisibleForContent,
    ValidateSpellID = ValidateSpellID,
    GenerateCustomBuffKey = GenerateCustomBuffKey,
}

-- Toggle lock state: when unlocked, show mover frames for dragging
local function ToggleLock()
    local db = BuffRemindersDB
    db.locked = not db.locked
    if db.locked then
        HideAllMovers()
    else
        UpdateAnchor()
    end
    return db.locked
end

-- Export display functions for Options.lua
BR.Display = {
    Update = UpdateDisplay,
    RefreshTest = RefreshTestDisplay,
    ToggleTestMode = ToggleTestMode,
    ToggleLock = ToggleLock,
    UpdateVisuals = UpdateVisuals,
    UpdateFallback = UpdateFallbackDisplay,
    UpdateActionButtons = UpdateActionButtons,
    IsTestMode = function()
        return testMode
    end,
    ResetMainFramePosition = function(x, y)
        SavePosition("main", x or 0, y or 0)
    end,
    ResetCategoryFramePosition = function(category, x, y)
        SavePosition(category, x or 0, y or 0)
    end,
}

-- Export Masque state for Options.lua
BR.Masque = {
    IsActive = function()
        return masqueGroup ~= nil and not masqueGroup.db.Disabled
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

    -- Only export fields that exist in defaults
    for key in pairs(defaults) do
        if BuffRemindersDB[key] ~= nil then
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

-- Import settings from a serialized string
local function ImportSettings(str)
    local data, err = DeserializeTable(str)
    if not data then
        return false, err
    end

    -- Deep merge imported data into BuffRemindersDB
    for k, v in pairs(data) do
        BuffRemindersDB[k] = DeepCopy(v)
    end

    -- Re-apply metatable on defaults (DeepCopy produces a plain table)
    if BuffRemindersDB.defaults then
        setmetatable(BuffRemindersDB.defaults, { __index = defaults.defaults })
    end

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
    elseif cmd == "lock" then
        BuffRemindersDB.locked = true
        HideAllMovers()
        BR.Components.RefreshAll()
        print("|cff00ccffBuffReminders:|r Frames locked.")
    elseif cmd == "unlock" then
        BuffRemindersDB.locked = false
        UpdateAnchor()
        BR.Components.RefreshAll()
        print("|cff00ccffBuffReminders:|r Frames unlocked.")
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
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("PET_BAR_UPDATE")
eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
eventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == addonName then
        _, playerClass = UnitClass("player")
        BR.BuffState.SetPlayerClass(playerClass)
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

        -- Notify users about recent changes (delayed, can be disabled)
        if BuffRemindersDB.showLoginMessages ~= false then
            C_Timer.After(3, function()
                print(
                    "|cff00ccffBuffReminders:|r Now supporting clickable icons for raid buffs and consumables! Enable it in |cffffcc00/br|r options."
                )
            end)
        end

        -- Deep copy default values for missing keys (skips 'defaults' sub-table, served by metatable)
        local function DeepCopyDefault(source, target)
            for k, v in pairs(source) do
                if k == "defaults" then
                    -- Skip: served by metatable __index
                    if target[k] == nil then
                        target[k] = {}
                    end
                elseif target[k] == nil then
                    if type(v) == "table" then
                        target[k] = {}
                        DeepCopyDefault(v, target[k])
                    else
                        target[k] = v
                    end
                elseif type(v) == "table" and type(target[k]) == "table" then
                    -- Recursively fill in missing nested keys
                    DeepCopyDefault(v, target[k])
                end
            end
        end

        local db = BuffRemindersDB

        -- ====================================================================
        -- Versioned migrations — each runs exactly once, tracked by dbVersion
        -- ====================================================================
        local DB_VERSION = 10

        local migrations = {
            -- [1] Consolidate all pre-versioning migrations (v2.8 → v3.x)
            [1] = function()
                -- Ensure db.defaults exists (DeepCopyDefault hasn't run yet)
                if not db.defaults then
                    db.defaults = {}
                end

                -- Migrate from old schema to new schema (v3.0 migration)
                local isOldSchema = db.iconSize ~= nil
                    or db.spacing ~= nil
                    or db.growDirection ~= nil
                    or db.showExpirationGlow ~= nil
                if isOldSchema then
                    -- Migrate global appearance settings to defaults
                    db.defaults.iconSize = db.iconSize or defaults.defaults.iconSize
                    db.defaults.spacing = db.spacing or defaults.defaults.spacing
                    db.defaults.growDirection = db.growDirection or defaults.defaults.growDirection
                    -- Migrate global behavior settings to defaults
                    db.defaults.showExpirationGlow = db.showExpirationGlow ~= false
                    db.defaults.expirationThreshold = db.expirationThreshold or defaults.defaults.expirationThreshold
                    db.defaults.glowStyle = db.glowStyle or defaults.defaults.glowStyle
                    -- Clean up old root-level keys
                    db.iconSize = nil
                    db.spacing = nil
                    db.growDirection = nil
                end

                -- Migrate splitCategories to categorySettings.{cat}.split
                if db.splitCategories then
                    for cat, isSplit in pairs(db.splitCategories) do
                        if not db.categorySettings then
                            db.categorySettings = {}
                        end
                        if not db.categorySettings[cat] then
                            db.categorySettings[cat] = {}
                        end
                        db.categorySettings[cat].split = isSplit
                    end
                    db.splitCategories = nil
                end

                -- Migrate old categorySettings with appearance values to use useCustomAppearance
                if isOldSchema and db.categorySettings then
                    for cat, catSettings in pairs(db.categorySettings) do
                        if cat ~= "main" and catSettings.iconSize then
                            catSettings.useCustomAppearance = catSettings.split == true
                        end
                    end
                end

                -- Migrate root-level showBuffReminder to raid category (v2.8.1 users)
                if db.showBuffReminder ~= nil then
                    if db.categorySettings and db.categorySettings.raid then
                        db.categorySettings.raid.showBuffReminder = db.showBuffReminder
                    end
                end

                -- Migrate: remove useCustomBehavior, per-category glow, consolidate showBuffReminder
                if db.categorySettings then
                    for cat, catSettings in pairs(db.categorySettings) do
                        if cat ~= "main" then
                            if cat == "raid" then
                                if catSettings.useCustomBehavior == false and catSettings.showBuffReminder == nil then
                                    catSettings.showBuffReminder = db.defaults and db.defaults.showBuffReminder ~= false
                                end
                            else
                                catSettings.showBuffReminder = nil
                            end
                            catSettings.useCustomBehavior = nil
                            catSettings.showExpirationGlow = nil
                            catSettings.expirationThreshold = nil
                            catSettings.glowStyle = nil
                        end
                    end
                end

                -- Migrate legacy root-level glow settings to defaults
                if db.showExpirationGlow ~= nil then
                    db.defaults.showExpirationGlow = db.showExpirationGlow
                    db.showExpirationGlow = nil
                end
                if db.expirationThreshold ~= nil then
                    db.defaults.expirationThreshold = db.expirationThreshold
                    db.expirationThreshold = nil
                end
                if db.glowStyle ~= nil then
                    db.defaults.glowStyle = db.glowStyle
                    db.glowStyle = nil
                end

                -- Remove showBuffReminder from defaults (now per-category raid-only)
                if db.defaults then
                    db.defaults.showBuffReminder = nil
                end
                db.showBuffReminder = nil

                -- Remove showOnlyInInstance (replaced by per-category W/S/D/R visibility toggles)
                db.showOnlyInInstance = nil

                -- Ensure categorySettings.main exists
                if not db.categorySettings then
                    db.categorySettings = {}
                end
                if not db.categorySettings.main then
                    db.categorySettings.main = {}
                end

                -- Migrate old position to categorySettings.main.position
                if db.position and not db.categorySettings.main.position then
                    db.categorySettings.main.position = {
                        point = db.position.point,
                        x = db.position.x,
                        y = db.position.y,
                    }
                end
            end,

            -- [2] Strip db.defaults keys matching code defaults (enable metatable inheritance)
            [2] = function()
                if db.defaults then
                    for key, value in pairs(db.defaults) do
                        if defaults.defaults[key] ~= nil and value == defaults.defaults[key] then
                            db.defaults[key] = nil
                        end
                    end
                end
            end,

            -- [3] Add pet category (new first-class category for pet summon reminders)
            [3] = function()
                -- Ensure categorySettings.pet exists with defaults
                if not db.categorySettings then
                    db.categorySettings = {}
                end
                if not db.categorySettings.pet then
                    db.categorySettings.pet = {}
                end
                -- Ensure categoryVisibility.pet exists
                if not db.categoryVisibility then
                    db.categoryVisibility = {}
                end
                if not db.categoryVisibility.pet then
                    db.categoryVisibility.pet = {
                        openWorld = true,
                        dungeon = true,
                        scenario = true,
                        raid = true,
                    }
                end
            end,

            -- [4] Remove useGlowFallback (glow fallback is now always enabled)
            [4] = function()
                db.useGlowFallback = nil
            end,

            -- [5] Remove vestigial db.position (now fully in categorySettings.main.position)
            [5] = function()
                if db.position then
                    if not db.categorySettings then
                        db.categorySettings = {}
                    end
                    if not db.categorySettings.main then
                        db.categorySettings.main = {}
                    end
                    if not db.categorySettings.main.position then
                        db.categorySettings.main.position = {
                            x = db.position.x or 0,
                            y = db.position.y or 0,
                        }
                    end
                    db.position = nil
                end
            end,

            -- [6] Add sensible difficulty defaults for consumables (mythic only, no LFR)
            [6] = function()
                if not db.categoryVisibility then
                    return
                end
                local vis = db.categoryVisibility.consumable
                if not vis then
                    return
                end
                -- Add dungeon difficulty defaults (mythic only) if not already set
                if not vis.dungeonDifficulty then
                    vis.dungeonDifficulty = {
                        normal = false,
                        heroic = false,
                        mythic = true,
                        mythicPlus = false,
                        timewalking = false,
                        follower = false,
                    }
                end
                -- Add raid difficulty defaults (no LFR) if not already set
                if not vis.raidDifficulty then
                    vis.raidDifficulty = {
                        lfr = false,
                        normal = true,
                        heroic = true,
                        mythic = true,
                    }
                end
            end,

            -- [7] Rename custom buff specId → requireSpecId (unify with built-in buff field names)
            [7] = function()
                if db.customBuffs then
                    for _, customBuff in pairs(db.customBuffs) do
                        if customBuff.specId ~= nil then
                            customBuff.requireSpecId = customBuff.specId
                            customBuff.specId = nil
                        end
                    end
                end
            end,

            -- [8] Seed pre-configured Burning Rush custom buff (disabled by default)
            [8] = function()
                if not db.customBuffs then
                    db.customBuffs = {}
                end
                local key = "burningRush"
                if not db.customBuffs[key] then
                    db.customBuffs[key] = {
                        spellID = 111400,
                        key = key,
                        name = "Burning Rush",
                        missingText = "",
                        class = "WARLOCK",
                        showWhenPresent = true,
                    }
                end
                if not db.enabledBuffs then
                    db.enabledBuffs = {}
                end
                if db.enabledBuffs[key] == nil then
                    db.enabledBuffs[key] = false
                end
            end,

            -- [9] Fix consumable dungeon difficulty default: mythic not M+
            [9] = function()
                local vis = db.categoryVisibility and db.categoryVisibility.consumable
                if not vis or not vis.dungeonDifficulty then
                    return
                end
                local dd = vis.dungeonDifficulty
                -- Only fix if the user still has the old wrong defaults (M+ on, mythic off)
                if dd.mythicPlus == true and dd.mythic == false then
                    dd.mythic = true
                    dd.mythicPlus = false
                end
            end,

            -- [10] Clean up consumableItems (no longer user-configured; bag scanning replaces manual config)
            [10] = function()
                db.consumableItems = nil
            end,
        }

        -- Run pending migrations
        local currentVersion = db.dbVersion or 0
        for version = currentVersion + 1, DB_VERSION do
            if migrations[version] then
                migrations[version]()
            end
        end
        db.dbVersion = DB_VERSION

        -- Deep copy defaults for non-defaults tables
        DeepCopyDefault(defaults, db)

        -- Migration: textSize was 12 in defaults but never used (font size was derived from
        -- iconSize * 0.32). Now nil means "auto-derive from iconSize". Clean up the old value
        -- so users get the auto behavior instead of a hardcoded 12.
        if db.defaults and db.defaults.textSize == 12 then
            db.defaults.textSize = nil
        end

        -- Initialize custom buffs storage and populate BUFF_TABLES.custom
        if not db.customBuffs then
            db.customBuffs = {}
        end
        BuildCustomBuffArray()

        -- Register custom buffs in glow fallback lookup (so they work in M+/combat)
        for _, customBuff in ipairs(CustomBuffs) do
            RegisterGlowBuff(customBuff, "custom")
        end

        -- Set up metatable so db.defaults inherits from code defaults
        if not db.defaults then
            db.defaults = {}
        end
        setmetatable(db.defaults, { __index = defaults.defaults })

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
        slashInfo:SetText("Slash commands: /br, /br lock, /br unlock, /br test")

        local category = Settings.RegisterCanvasLayoutCategory(settingsPanel, settingsPanel.name)
        Settings.RegisterAddOnCategory(category)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Invalidate caches on zone change (spec may have auto-switched on entry)
        BR.BuffState.InvalidateContentTypeCache()
        BR.BuffState.InvalidateSpellCache()
        BR.BuffState.InvalidateSpecCache()
        -- Sync flags with current state (in case of reload)
        inCombat = InCombatLockdown()
        isResting = IsResting()
        BR.StateHelpers.ScanEatingState()
        ResolveFontPath()
        InvalidateConsumableCache()
        if not mainFrame then
            InitializeFrames()
            -- Initialize action buttons for categories with clickable enabled
            for _, cat in ipairs(CATEGORIES) do
                local cs = BuffRemindersDB.categorySettings and BuffRemindersDB.categorySettings[cat]
                if cs and cs.clickable then
                    UpdateActionButtons(cat)
                end
            end
        end
        SeedGlowingSpells() -- Catch glows that were active before event registration
        if not inCombat then
            StartUpdates()
        end
        -- Delayed update to catch glow events that fire after reload
        C_Timer.After(0.5, function()
            UpdateDisplay()
        end)
    elseif event == "GROUP_ROSTER_UPDATE" then
        UpdateDisplay()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        BR.StateHelpers.ScanEatingState()
        RefreshOverlaySpells()
        StartUpdates()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        StopUpdates()
        UpdateDisplay()
    elseif event == "PLAYER_DEAD" then
        HideAllDisplayFrames()
    elseif event == "PLAYER_UNGHOST" then
        UpdateDisplay()
    elseif event == "UNIT_AURA" then
        -- Skip in combat (auras change frequently, and we can't check buffs or eat in combat)
        -- Throttle rapid events (e.g., raid-wide buff application)
        if not InCombatLockdown() and mainFrame and mainFrame:IsShown() then
            if arg1 == "player" then
                BR.StateHelpers.UpdateEatingState(arg2)
            end
            local now = GetTime()
            if now - lastAuraUpdate >= AURA_THROTTLE then
                lastAuraUpdate = now
                UpdateDisplay()
            end
            -- else: throttled, 1s ticker will catch it
        end
    elseif event == "UNIT_PET" then
        if arg1 == "player" then
            UpdateDisplay()
        end
    elseif event == "PET_BAR_UPDATE" then
        UpdateDisplay()
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        UpdateDisplay()
    elseif event == "PLAYER_DIFFICULTY_CHANGED" then
        BR.BuffState.InvalidateContentTypeCache()
        UpdateDisplay()
    elseif event == "PLAYER_UPDATE_RESTING" then
        isResting = IsResting()
        UpdateDisplay()
    elseif event == "READY_CHECK" then
        -- Cancel any existing timer
        if readyCheckTimer then
            readyCheckTimer:Cancel()
        end
        BR.BuffState.SetReadyCheckState(true)
        UpdateDisplay()
        -- Start timer to reset ready check state
        local duration = BuffRemindersDB.readyCheckDuration or 15
        readyCheckTimer = C_Timer.NewTimer(duration, function()
            BR.BuffState.SetReadyCheckState(false)
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
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 ~= "player" then
            return
        end
        -- Invalidate caches when player changes spec
        InvalidatePlayerRoleCache()
        BR.BuffState.InvalidateSpellCache()
        RefreshOverlaySpells()
        UpdateDisplay()
        -- Spells can become available shortly after spec swap; refresh once more
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                RefreshOverlaySpells()
            end
            UpdateDisplay()
        end)
    elseif event == "TRAIT_CONFIG_UPDATED" then
        -- Invalidate spell cache when talents change (within same spec)
        BR.BuffState.InvalidateSpellCache()
        RefreshOverlaySpells()
        UpdateDisplay()
    elseif event == "SPELLS_CHANGED" then
        -- Catch delayed spell availability after spec/talent changes (noisy event, keep cheap)
        BR.BuffState.InvalidateSpellCache()
    elseif event == "BAG_UPDATE_DELAYED" then
        InvalidateConsumableCache()
        UpdateDisplay()
        UpdateActionButtons("consumable")
    end
end)
