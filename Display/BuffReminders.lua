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

-- Buff tables from Buffs.lua (via BR namespace)
local BUFF_TABLES = BR.BUFF_TABLES

-- Local aliases for direct access
local RaidBuffs = BUFF_TABLES.raid
local PresenceBuffs = BUFF_TABLES.presence
local TargetedBuffs = BUFF_TABLES.targeted
local SelfBuffs = BUFF_TABLES.self
local PetBuffs = BUFF_TABLES.pet
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
    buffTrackingMode = "all",
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
        -- Behavior (glow settings)
        showExpirationGlow = true,
        glowWhenMissing = true,
        expirationThreshold = 15, -- minutes
        glowType = 1, -- 1=Pixel, 2=AutoCast, 3=Border, 4=Proc
        glowColor = BR.Glow.DEFAULT_COLOR,
        useCustomGlowColor = false,
        glowSize = 2,
        showConsumablesWithoutItems = false,
        consumableDisplayMode = "sub_icons",
        petDisplayMode = "generic", -- "generic" or "expanded"
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
            subIconSide = "BOTTOM",
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
local eventFrame -- forward declaration; created later in file, referenced by StartUpdates

---@class TestModeData
---@field fakeTotal number Total group size for fake counts
---@field fakeRemaining number Fake time remaining for expiration glow test
---@field fakeMissing table<number, number> Fake missing counts per raid buff index
---@field showLabels boolean Whether to show "TEST" labels on icons

---@type TestModeData?
local testModeData = nil -- Stores seeded fake values for consistent test display
local playerClass = nil -- Cached player class, set once on init
local playerRole = nil -- Cached player role, invalidated on spec change
local glowingSpells = {} -- Track which spell IDs are currently glowing (for action bar glow fallback)

-- Dirty flag system: events set dirty=true, OnUpdate checks flag with throttle
local dirty = false
local lastUpdateTime = 0
local MIN_UPDATE_INTERVAL = 0.5 -- seconds between actual updates

local function SetDirty()
    dirty = true
end

-- Track combat state via events (InCombatLockdown() can lag behind PLAYER_REGEN_DISABLED)
local inCombat = false
local isResting = false

-- Category frame system
local categoryFrames = {}
local CATEGORIES = { "raid", "presence", "targeted", "self", "pet", "consumable", "custom" }

-- Track previously visible frame keys for selective hiding (Phase 3 optimization)
local previouslyVisibleKeys = {} ---@type table<string, boolean>

-- Layout signature tracking for skip-redundant-positioning (Phase 4 optimization)
-- Signatures are concatenated visible frame keys; if unchanged, skip repositioning
local lastMainSignature = ""
local lastSplitSignatures = {} ---@type table<string, string>
local CATEGORY_LABELS = {
    raid = "Raid",
    presence = "Presence",
    targeted = "Targeted",
    self = "Self",
    pet = "Pet",
    consumable = "Consumable",
    custom = "Custom",
}

-- Export for Options.lua and split modules
BR.defaults = defaults
BR.CATEGORIES = CATEGORIES
BR.CATEGORY_LABELS = CATEGORY_LABELS

-- Early init of BR.Display for split modules (populated further below and in InitializeFrames)
BR.Display = BR.Display or {}
BR.Display.defaults = defaults
BR.Display.GetFontPath = function()
    return fontPath
end

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
    result.subIconSide = (catSettings and catSettings.subIconSide) or defaultCatSettings.subIconSide

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
        result.growDirection = (catSettings and catSettings.growDirection) or "CENTER"
        result.glowType = (catSettings and catSettings.glowType) or 1
        result.glowColor = (catSettings and catSettings.glowColor) or BR.Glow.DEFAULT_COLOR
        result.glowSize = (catSettings and catSettings.glowSize) or 2
        result.showExpirationGlow = catSettings and catSettings.showExpirationGlow
        result.expirationThreshold = (catSettings and catSettings.expirationThreshold)
    else
        result.iconSize = globalDefaults.iconSize or 64
        result.textSize = globalDefaults.textSize -- nil = auto
        result.iconAlpha = globalDefaults.iconAlpha or 1
        result.textAlpha = globalDefaults.textAlpha or 1
        result.textColor = globalDefaults.textColor or { 1, 1, 1 }
        result.spacing = globalDefaults.spacing or 0.2
        result.iconZoom = globalDefaults.iconZoom or 8
        result.borderSize = globalDefaults.borderSize or 2
        result.growDirection = globalDefaults.growDirection or "CENTER"
        result.glowType = globalDefaults.glowType or 1
        result.glowColor = globalDefaults.glowColor or BR.Glow.DEFAULT_COLOR
        result.glowSize = globalDefaults.glowSize or 2
        result.showExpirationGlow = globalDefaults.showExpirationGlow
        result.expirationThreshold = globalDefaults.expirationThreshold
    end

    -- BUFF! text: direct per-category for raid only
    if category == "raid" then
        result.showBuffReminder = not catSettings or catSettings.showBuffReminder ~= false
    else
        result.showBuffReminder = false
    end

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
        -- Skip if: has enchantID, customCheck, readyCheckOnly, or glowMode disabled (custom buffs only)
        if not buff.enchantID and not buff.customCheck and not buff.readyCheckOnly and buff.glowMode ~= "disabled" then
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
local UpdateDisplay, ToggleTestMode
local UpdateFallbackDisplay, RenderPetEntries

-- Local alias for glow module
local SetExpirationGlow = BR.Glow.SetExpiration

-- Per-render-cycle cache for glow settings (avoids repeated BR.Config.GetCategorySetting calls)
local glowSettingsCache = {} ---@type table<string, {typeIndex: number, color: number[], size: number}>

---Get cached glow settings for a category (populated once per render cycle)
---@param category string
---@return {typeIndex: number, color: number[], size: number}
local function GetCachedGlowSettings(category)
    local cached = glowSettingsCache[category]
    if cached then
        return cached
    end
    cached = {
        typeIndex = BR.Config.GetCategorySetting(category, "glowType") or 1,
        color = BR.Config.GetCategorySetting(category, "glowColor") or BR.Glow.DEFAULT_COLOR,
        useCustomColor = BR.Config.GetCategorySetting(category, "useCustomGlowColor") or false,
        size = BR.Config.GetCategorySetting(category, "glowSize") or 2,
    }
    glowSettingsCache[category] = cached
    return cached
end

-- Hide a buff frame without destroying its glow.
-- The glow overlay is a child of the frame, so frame:Hide() visually hides it and
-- pauses its OnUpdate (WoW doesn't fire OnUpdate on hidden frames). When the frame
-- is re-shown, the glow animation resumes seamlessly from where it left off.
-- SetExpirationGlow handles cleanup when a re-shown frame no longer needs a glow.
local function HideFrame(frame)
    frame:Hide()
end

---Show a frame with missing text styling
---@param frame BuffFrame
---@param missingText? string
---@param shouldGlow? boolean
---@param category? CategoryName
---@param cachedGlow? {typeIndex: number, color: number[], size: number}
---@return boolean true (for anyVisible chaining)
local function ShowMissingFrame(frame, missingText, shouldGlow, category, cachedGlow)
    -- Hide stackCount/qualityOverlay — ShowMissingFrame can be called from fallback paths
    -- (UpdateFallbackDisplay) that don't go through RenderVisibleEntry's cleanup.
    frame.stackCount:Hide()
    if frame.qualityOverlay then
        frame.qualityOverlay:Hide()
    end
    if missingText then
        frame.count:SetFont(fontPath, GetFrameFontSize(frame, MISSING_TEXT_SCALE), "OUTLINE")
        frame.count:SetText(missingText)
        frame.count:Show()
    else
        frame.count:Hide()
    end
    frame:Show()
    SetExpirationGlow(frame, shouldGlow or false, category, cachedGlow)
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
BR.DIRECTION_ANCHORS = DIRECTION_ANCHORS

-- Create a category frame for grouped display mode
local function CreateCategoryFrame(category)
    local db = BuffRemindersDB
    local catSettings = db.categorySettings and db.categorySettings[category] or defaults.categorySettings[category]
    local pos = catSettings.position or defaults.categorySettings[category].position
    local direction = catSettings.growDirection or defaults.defaults.growDirection or "CENTER"
    local anchor = DIRECTION_ANCHORS[direction] or "CENTER"

    local frame = CreateFrame("Frame", "BuffReminders_Category_" .. category, UIParent)
    frame:SetSize(200, 50)
    frame:SetPoint(anchor, UIParent, "CENTER", pos.x or 0, pos.y or 0)
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
        -- Masque controls styling; hide our native border (Masque manages its own textures via ReSkin)
        frame.border:Hide()
        return
    end
    -- When Masque is loaded but disabled, hide textures it created (Backdrop, Shadow, Gloss, etc.)
    -- that linger with a default Blizzard look. Skip the loop entirely if Masque was never loaded.
    if masqueGroup then
        for _, region in next, { frame:GetRegions() } do
            if region:IsObjectType("Texture") and region ~= frame.icon and region ~= frame.border then
                region:Hide()
            end
        end
    end
    -- Restore native state (Masque changes icon anchors, border texture/draw layer/alpha when skinning)
    frame.icon:ClearAllPoints()
    frame.icon:SetAllPoints()
    frame.border:SetDrawLayer("BACKGROUND")
    frame.border:SetAlpha(1)
    frame.border:SetColorTexture(0, 0, 0, 1)
    local zoom = (catSettings.iconZoom or DEFAULT_ICON_ZOOM) / 100
    frame.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    local borderSize = catSettings.borderSize or DEFAULT_BORDER_SIZE
    frame.border:ClearAllPoints()
    frame.border:SetPoint("TOPLEFT", -borderSize, borderSize)
    frame.border:SetPoint("BOTTOMRIGHT", borderSize, -borderSize)
    frame.border:Show()
end

-- Map buff key → consumable category (used by display to detect consumable buffs with bag items)
local BUFF_KEY_TO_CATEGORY = {
    flask = "flask",
    food = "food",
    rune = "rune",
    weaponBuff = "weapon",
    weaponBuffOH = "weapon",
}

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

    frame.qualityOverlay = frame:CreateFontString(nil, "OVERLAY")
    frame.qualityOverlay:Hide()

    -- Register with Masque — provide Normal texture so skins like Caith can style it
    if masqueGroup then
        masqueGroup:AddButton(frame, {
            Icon = frame.icon,
            Normal = frame.border,
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
        local raidBts = db.categorySettings and db.categorySettings.raid and db.categorySettings.raid.buffTextSize
        frame.buffText:SetFont(
            fontPath,
            raidBts or GetFontSize(0.8, catSettings.textSize, catSettings.iconSize),
            "OUTLINE"
        )
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

    extra.qualityOverlay = extra:CreateFontString(nil, "OVERLAY")
    extra.qualityOverlay:Hide()

    if masqueGroup then
        masqueGroup:AddButton(extra, {
            Icon = extra.icon,
            Normal = extra.border,
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

-- Build a sorted category list by priority (cached, invalidated on config change)
local cachedSortedCategories = nil

local function InvalidateSortedCategories()
    cachedSortedCategories = nil
end

local function GetSortedCategories()
    if cachedSortedCategories then
        return cachedSortedCategories
    end
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
    cachedSortedCategories = sorted
    return sorted
end

---Build a signature string from a list of frames (by buffKey)
---@param frames table[]
---@return string
local function BuildLayoutSignature(frames)
    if #frames == 0 then
        return ""
    end
    -- Use table.concat for efficiency; keys are short strings
    local keys = {}
    for i, frame in ipairs(frames) do
        keys[i] = (frame.buffDef and frame.buffDef.key) or ""
    end
    return table.concat(keys, ",")
end

-- Position and size the main container frame with the given buff frames
local function PositionMainContainer(mainFrameBuffs)
    local db = BuffRemindersDB

    if #mainFrameBuffs > 0 then
        -- Skip repositioning if the same frames are visible in the same order
        local sig = BuildLayoutSignature(mainFrameBuffs)
        if sig == lastMainSignature then
            return
        end
        lastMainSignature = sig

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
        lastMainSignature = ""
        mainFrame:Hide()
    end
end

-- Position and size a split category frame with the given buff frames
local function PositionSplitCategory(category, frames)
    local catFrame = categoryFrames[category]
    if not catFrame then
        return
    end

    if #frames > 0 then
        -- Skip repositioning if the same frames are visible in the same order
        local sig = BuildLayoutSignature(frames)
        if sig == (lastSplitSignatures[category] or "") then
            return
        end
        lastSplitSignatures[category] = sig

        local catSettings = GetCategorySettings(category)
        local direction = catSettings.growDirection or "CENTER"
        local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
        local pos = catSettings.position or { point = "CENTER", x = 0, y = 0 }
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
        lastSplitSignatures[category] = ""
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

--- Generate fake state entries for test mode, populating BR.BuffState.entries
--- and BR.BuffState.visibleByCategory so UpdateDisplay can render via the normal pipeline.
local function GenerateTestEntries()
    assert(testModeData, "GenerateTestEntries called with nil testModeData")

    -- Reset all entries (same pattern as State.lua:Refresh)
    for _, entry in pairs(BR.BuffState.entries) do
        entry.visible = false
        entry.shouldGlow = false
        entry.countText = nil
        entry.missingText = nil
        entry.expiringTime = nil
        entry.isEating = nil
        entry.petActions = nil
        entry.iconByRole = nil
    end

    local raidIndex = 1

    for _, category in ipairs(CATEGORIES) do
        -- Per-category glow settings (same pattern as State.lua:GetCategoryGlow)
        local glowEnabled = BR.Config.GetCategorySetting(category, "showExpirationGlow") ~= false
        local glowWhenMissing = glowEnabled and BR.Config.GetCategorySetting(category, "glowWhenMissing") ~= false
        local expiringShown = false

        local buffTable = BUFF_TABLES[category]
        for i, buff in ipairs(buffTable) do
            local settingKey = buff.groupId or buff.key
            if IsBuffEnabled(settingKey) then
                -- Get or create entry (mirrors State.lua pattern)
                local entry = BR.BuffState.entries[buff.key]
                if not entry then
                    entry = {
                        key = buff.key,
                        category = category,
                        sortOrder = i,
                        visible = false,
                        displayType = "missing",
                        shouldGlow = false,
                    }
                    BR.BuffState.entries[buff.key] = entry
                end
                entry.category = category
                entry.sortOrder = i
                entry.visible = true

                local noGlow = buff.noGlow

                if category == "raid" then
                    if glowEnabled and not expiringShown then
                        entry.displayType = "expiring"
                        entry.countText = FormatRemainingTime(testModeData.fakeRemaining)
                        entry.shouldGlow = true
                        expiringShown = true
                    else
                        entry.displayType = "count"
                        local fakeBuffed = testModeData.fakeTotal - testModeData.fakeMissing[raidIndex]
                        entry.countText = fakeBuffed .. "/" .. testModeData.fakeTotal
                        entry.shouldGlow = glowWhenMissing
                    end
                    raidIndex = raidIndex + 1
                elseif category == "pet" then
                    entry.displayType = "missing"
                    entry.missingText = buff.missingText
                    entry.iconByRole = buff.iconByRole
                    entry.shouldGlow = glowWhenMissing
                    if buff.groupId == "pets" and BR.PetHelpers then
                        local actions = BR.PetHelpers.GetPetActions(playerClass)
                        if actions and #actions > 0 then
                            entry.petActions = actions
                        end
                    end
                else
                    -- consumable, presence, targeted, self, custom
                    entry.displayType = "missing"
                    entry.missingText = buff.missingText
                    entry.iconByRole = buff.iconByRole
                    entry.shouldGlow = glowWhenMissing and not noGlow

                    -- Show first buff as expiring to preview expiration glow
                    if glowEnabled and not noGlow and not expiringShown then
                        entry.displayType = "expiring"
                        entry.countText = FormatRemainingTime(testModeData.fakeRemaining)
                        entry.shouldGlow = true
                        expiringShown = true
                    end
                end
            end
        end
    end

    -- Build visibleByCategory (same pattern as State.lua)
    for _, list in pairs(BR.BuffState.visibleByCategory) do
        wipe(list)
    end
    for _, entry in pairs(BR.BuffState.entries) do
        if entry.visible then
            local cat = entry.category
            if not BR.BuffState.visibleByCategory[cat] then
                BR.BuffState.visibleByCategory[cat] = {}
            end
            table.insert(BR.BuffState.visibleByCategory[cat], entry)
        end
    end

    -- Mark sorted status
    for _, list in pairs(BR.BuffState.visibleByCategory) do
        local sorted = true
        for j = 2, #list do
            if list[j].sortOrder < list[j - 1].sortOrder then
                sorted = false
                break
            end
        end
        list._sorted = sorted
    end
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
        -- Clear all glows, hide test labels, and hide ALL frames (including extra frames)
        -- so UpdateDisplay starts from a clean slate. Without this, frames shown during
        -- test mode but not tracked in previouslyVisibleKeys would linger as orphans.
        for _, frame in pairs(buffFrames) do
            SetExpirationGlow(frame, false)
            if frame.testText then
                frame.testText:Hide()
            end
            frame:Hide()
            if frame.extraFrames then
                for _, extra in ipairs(frame.extraFrames) do
                    extra:Hide()
                end
            end
        end
        wipe(previouslyVisibleKeys)
        -- Reset layout signatures so positioning runs fresh
        lastMainSignature = ""
        wipe(lastSplitSignatures)
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
        BR.SecureButtons.HideAllSecureFrames()
        lastMainSignature = ""
        wipe(lastSplitSignatures)
        UpdateDisplay()
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
    wipe(previouslyVisibleKeys)
    -- Reset layout signatures so next PositionMainContainer/PositionSplitCategory always
    -- runs fresh. Without this, if the signature matches a previous value, positioning
    -- returns early without calling mainFrame:Show(), leaving frames invisible.
    lastMainSignature = ""
    wipe(lastSplitSignatures)
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

    -- Show frames for any glowing spells (skip whenNotGlowing buffs — handled in second pass)
    local seenKeys = {}
    local GetPlayerSpecId = BR.StateHelpers.GetPlayerSpecId
    for spellID, _ in pairs(glowingSpells) do
        local entry = glowSpellToBuff[spellID]
        if entry then
            local buff = entry.buff
            local mode = buff.glowMode or "whenGlowing"
            if mode == "whenGlowing" and (not buff.class or buff.class == playerClass) and not seenKeys[buff.key] then
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

    -- Second pass: show whenNotGlowing buffs where NONE of their spells are glowing
    local invertedHasGlow = {}
    for spellID, _ in pairs(glowingSpells) do
        local entry = glowSpellToBuff[spellID]
        if entry and (entry.buff.glowMode == "whenNotGlowing") then
            invertedHasGlow[entry.buff.key] = true
        end
    end
    for _, entry in pairs(glowSpellToBuff) do
        local buff = entry.buff
        if buff.glowMode == "whenNotGlowing" and not seenKeys[buff.key] and not invertedHasGlow[buff.key] then
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
        BR.Movers.UpdateAnchor()
    else
        HideAllDisplayFrames()
    end
end

-- Eating icon texture ID (from State.lua, matches the eating channel aura icon)
local EATING_ICON = BR.EATING_AURA_ICON

-- Resolve a consumable frame's icon from bag items.
-- Returns "items" if bag items found (sets icon, quality overlay, stack count),
-- "missing" if no items but showConsumablesWithoutItems is on,
-- or false if no items and setting is off.
---@param frame BuffFrame
---@return string|false result "items", "missing", or false
local function ResolveConsumableFrame(frame)
    local items = frame._cachedItems
    if items == nil then
        items = BR.SecureButtons.GetConsumableActionItems(frame.buffDef) or false
        frame._cachedItems = items
    end
    if items and items[1] then
        frame.icon:SetTexture(items[1].icon)
        if frame.qualityOverlay then
            BR.SecureButtons.SetQualityOverlay(frame.qualityOverlay, items[1].craftedQuality, frame:GetWidth())
        end
        frame.count:Hide()
        frame.stackCount:SetText(items[1].count)
        frame.stackCount:Show()
        return "items"
    end
    -- No items: fall back icon to buff definition
    local def = frame.buffDef
    local fallback = def and (def.iconOverride or def.buffIconID)
    if fallback then
        frame.icon:SetTexture(fallback)
    end
    if frame.qualityOverlay then
        frame.qualityOverlay:Hide()
    end
    if (BuffRemindersDB.defaults or {}).showConsumablesWithoutItems then
        return "missing"
    end
    return false
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
        return true
    elseif frame._br_eating_icon then
        -- Transition from eating → not eating: restore the correct consumable icon
        frame._br_eating_icon = nil
        ResolveConsumableFrame(frame)
    end

    -- Get cached glow settings for this entry's category (avoids repeated DB reads)
    local cachedGlow = entry.category and GetCachedGlowSettings(entry.category) or nil

    if entry.displayType == "count" then
        frame.count:SetFont(fontPath, GetFrameFontSize(frame), "OUTLINE")
        frame.count:SetText(entry.countText or "")
        frame.count:Show()
        frame:Show()
        SetExpirationGlow(frame, entry.shouldGlow, entry.category, cachedGlow)
    elseif entry.displayType == "expiring" then
        frame.count:SetFont(fontPath, GetFrameFontSize(frame), "OUTLINE")
        frame.count:SetText(entry.countText or "")
        frame.count:Show()
        frame:Show()
        SetExpirationGlow(frame, true, entry.category, cachedGlow)
    else -- "missing"
        -- Consumables with bag scan support: show actual item from bags
        if BUFF_KEY_TO_CATEGORY[frame.key] then
            local result = ResolveConsumableFrame(frame)
            if result == "items" then
                frame:Show()
                SetExpirationGlow(frame, entry.shouldGlow, entry.category, cachedGlow)
            elseif result == "missing" then
                ShowMissingFrame(frame, entry.missingText, entry.shouldGlow, entry.category, cachedGlow)
            else
                if testMode then
                    ShowMissingFrame(frame, entry.missingText, entry.shouldGlow, entry.category, cachedGlow)
                else
                    return false
                end
            end
        else
            if entry.iconByRole then
                local texture = GetBuffTexture(frame.spellIDs, entry.iconByRole)
                if texture then
                    frame.icon:SetTexture(texture)
                end
            end
            ShowMissingFrame(frame, entry.missingText, entry.shouldGlow, entry.category, cachedGlow)
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
    local items = frame._cachedItems
    if items == nil then
        items = BR.SecureButtons.GetConsumableActionItems(frame.buffDef) or false
        frame._cachedItems = items
    end
    if displayMode == "sub_icons" then
        local cs = BuffRemindersDB.categorySettings and BuffRemindersDB.categorySettings.consumable
        local clickable = cs and cs.clickable == true
        BR.SecureButtons.UpdateConsumableButtons(frame, items, clickable)
    else
        -- Not sub_icons: hide any leftover sub-icon buttons
        BR.SecureButtons.UpdateConsumableButtons(frame, nil)
        if displayMode == "expanded" and items and #items > 1 then
            for i = 2, #items do
                local extra = GetOrCreateExtraFrame(frame, i - 1)
                extra:SetParent(parentFrame)
                extra:SetSize(frame:GetWidth(), frame:GetHeight())
                extra.icon:SetTexture(items[i].icon)
                if extra.qualityOverlay then
                    BR.SecureButtons.SetQualityOverlay(extra.qualityOverlay, items[i].craftedQuality, frame:GetWidth())
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
    frame._br_pet_spell = first.spellName

    -- Extra frames for remaining actions
    for i = 2, #entry.petActions do
        local action = entry.petActions[i]
        local extra = GetOrCreateExtraFrame(frame, i - 1)
        extra:SetParent(frame:GetParent())
        extra:SetSize(frame:GetWidth(), frame:GetHeight())
        extra.icon:SetTexture(action.icon)
        extra.count:Hide()
        extra.stackCount:Hide()
        extra._br_pet_spell = action.spellName
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
    local petMode = (BuffRemindersDB.defaults or {}).petDisplayMode or "generic"
    if petMode == "expanded" then
        ExpandPetActions(frame, entry, frameList)
    else
        -- Generic mode: restore original icon, use preferred action for click-to-cast
        local texture = GetBuffTexture(frame.spellIDs)
        if texture then
            frame.icon:SetTexture(texture)
        end
        local gi = entry.petActions.genericIndex or 1
        frame._br_pet_spell = entry.petActions[gi] and entry.petActions[gi].spellName
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
    if not petEntries._sorted then
        table.sort(petEntries, function(a, b)
            return a.sortOrder < b.sortOrder
        end)
    end
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
    if not mainFrame then
        return
    end

    -- Clear per-cycle caches (before early exits — fallback paths also use these)
    wipe(glowSettingsCache)
    for key in pairs(BUFF_KEY_TO_CATEGORY) do
        local frame = buffFrames[key]
        if frame then
            frame._cachedItems = nil
        end
    end

    if testMode then
        -- Test mode: generate fake state entries through the normal pipeline
        GenerateTestEntries()
    else
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
            BR.SecureButtons.ScheduleSecureSync()
            return
        end

        -- Combat: glow fallback + pet reminders (both handled by UpdateFallbackDisplay)
        if combatCheck then
            for _, frame in pairs(buffFrames) do
                HideFrame(frame)
            end
            UpdateFallbackDisplay()
            BR.SecureButtons.ScheduleSecureSync()
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
    end

    local visibleByCategory = BR.BuffState.visibleByCategory
    local anyVisible = false

    -- Track which keys are visible this cycle (for selective hiding)
    local currentlyVisibleKeys = {} ---@type table<string, boolean>

    -- Build sorted category list by priority
    local sortedCategories = GetSortedCategories()

    -- Collect frames for main container (non-split) in priority order
    local mainFrameBuffs = {}

    for _, catEntry in ipairs(sortedCategories) do
        local category = catEntry.name
        local entries = visibleByCategory[category]

        if entries and #entries > 0 then
            if not entries._sorted then
                table.sort(entries, function(a, b)
                    return a.sortOrder < b.sortOrder
                end)
            end
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
                            currentlyVisibleKeys[entry.key] = true
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
                            currentlyVisibleKeys[entry.key] = true
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

    -- Selectively hide frames that were visible last cycle but aren't now
    for key in pairs(previouslyVisibleKeys) do
        if not currentlyVisibleKeys[key] then
            local frame = buffFrames[key]
            if frame then
                HideFrame(frame)
                frame._cachedItems = nil
                if frame.extraFrames then
                    for _, extra in ipairs(frame.extraFrames) do
                        extra:Hide()
                    end
                end
            end
        end
    end
    -- Update tracking set
    wipe(previouslyVisibleKeys)
    for key in pairs(currentlyVisibleKeys) do
        previouslyVisibleKeys[key] = true
    end

    -- Position main container
    PositionMainContainer(mainFrameBuffs)

    -- Handle split category frames with no visible buffs
    PositionSplitCategories(visibleByCategory)

    if not anyVisible then
        HideAllDisplayFrames()
    end
    BR.Movers.UpdateAnchor()

    -- Show TEST labels in test mode (after positioning so font size is correct)
    if testMode and testModeData and testModeData.showLabels then
        for _, frame in pairs(buffFrames) do
            if frame:IsShown() and frame.testText then
                frame.testText:SetFont(fontPath, GetFrameFontSize(frame, 0.6), "OUTLINE")
                frame.testText:Show()
            end
        end
    end

    -- Skip secure frame sync in test mode (secure frames are hidden)
    if not testMode then
        BR.SecureButtons.ScheduleSecureSync()

        -- Sync click overlays on expanded extra frames (they are created above but
        -- UpdateActionButtons is the only place that wires up their click overlays).
        if not InCombatLockdown() then
            local displayMode = (BuffRemindersDB.defaults or {}).consumableDisplayMode
            if displayMode == "expanded" then
                BR.SecureButtons.UpdateActionButtons("consumable")
            end
            BR.SecureButtons.UpdateActionButtons("pet")
        end
    end
end

-- Start update ticker
local function StartUpdates()
    if updateTicker then
        updateTicker:Cancel()
    end
    -- Slow fallback ticker for expiration text staleness (e.g. "14m" → "13m")
    updateTicker = C_Timer.NewTicker(3, SetDirty)
    -- OnUpdate checks dirty flag with throttle
    eventFrame:SetScript("OnUpdate", function()
        if not dirty then
            return
        end
        local now = GetTime()
        if now - lastUpdateTime < MIN_UPDATE_INTERVAL then
            return
        end
        dirty = false
        lastUpdateTime = now
        UpdateDisplay()
    end)
    -- Immediate first update
    dirty = false
    lastUpdateTime = GetTime()
    UpdateDisplay()
end

-- Stop update ticker
local function StopUpdates()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
    eventFrame:SetScript("OnUpdate", nil)
    dirty = false
end

-- Forward declaration for ReparentBuffFrames (defined after InitializeFrames)
local ReparentBuffFrames

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

    -- Export frame references for split modules (Movers, SecureButtons)
    BR.Display.mainFrame = mainFrame
    BR.Display.categoryFrames = categoryFrames
    BR.Display.frames = buffFrames

    -- Create mover frames (shown when unlocked for drag positioning)
    BR.Movers.Initialize()

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
    -- Only register for glow tracking if glowMode is not disabled
    if customBuff.glowMode ~= "disabled" then
        RegisterGlowBuff(customBuff, "custom")
    end
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
            -- Re-register glow lookup with new spellID (unregister old, then conditionally re-register)
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
            if customBuff and customBuff.glowMode ~= "disabled" then
                RegisterGlowBuff(customBuff, "custom")
            end
        end
    end,
}

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
            local raidBts = BuffRemindersDB.categorySettings
                and BuffRemindersDB.categorySettings.raid
                and BuffRemindersDB.categorySettings.raid.buffTextSize
            frame.buffText:SetFont(fontPath, raidBts or GetFrameFontSize(frame, 0.8), "OUTLINE")
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
    UpdateDisplay()
end

-- ============================================================================
-- CALLBACK REGISTRY SUBSCRIPTIONS
-- ============================================================================
-- Subscribe to config change events for automatic UI updates.
-- This decouples the options panel from the display system.

local CallbackRegistry = BR.CallbackRegistry

---Reset layout signatures so next UpdateDisplay forces repositioning
local function ResetLayoutSignatures()
    lastMainSignature = ""
    wipe(lastSplitSignatures)
end

-- Visual changes (icon size, zoom, border, text visibility, font)
CallbackRegistry:RegisterCallback("VisualsRefresh", function()
    ResolveFontPath()
    ResetLayoutSignatures()
    UpdateVisuals()
    for _, mover in pairs(BR.Movers.GetMoverFrames()) do
        mover:UpdateSize()
    end
end)

-- Layout changes (spacing, grow direction)
CallbackRegistry:RegisterCallback("LayoutRefresh", function()
    -- If growth direction changed, convert saved positions so frames stay in place
    BR.Movers.ConvertDirectionPositions()
    ResetLayoutSignatures()
    InvalidateSortedCategories()

    UpdateDisplay()
end)

-- Display changes (enabled buffs, visibility settings, consumable display mode)
CallbackRegistry:RegisterCallback("DisplayRefresh", function()
    ResetLayoutSignatures()
    InvalidateSortedCategories()
    UpdateDisplay()
    -- Refresh consumable action button clickability/visibility after mode changes
    if not InCombatLockdown() then
        BR.SecureButtons.UpdateActionButtons("consumable")
    end
end)

-- Structural changes (split categories)
CallbackRegistry:RegisterCallback("FramesReparent", function()
    ResetLayoutSignatures()
    InvalidateSortedCategories()
    ReparentBuffFrames()
    UpdateVisuals()
end)

-- Masque skin change callback — restore native styling when Masque is disabled.
-- Deferred because Masque modifies button regions after firing the callback.
if masqueGroup then
    masqueGroup:RegisterCallback(function()
        C_Timer.After(0, function()
            UpdateVisuals()
            BR.Components.RefreshAll()
        end)
    end)
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
    DeepCopy = function(...)
        return BR.ImportExport.DeepCopy(...)
    end,
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
        BR.Movers.HideAll()
    else
        BR.Movers.UpdateAnchor()
    end
    return db.locked
end

-- Export display functions for Options.lua
BR.Display.Update = UpdateDisplay
BR.Display.ToggleTestMode = ToggleTestMode
BR.Display.ToggleLock = ToggleLock
BR.Display.UpdateVisuals = UpdateVisuals
BR.Display.UpdateActionButtons = function(category)
    return BR.SecureButtons.UpdateActionButtons(category)
end
BR.Display.IsTestMode = function()
    return testMode
end
BR.Display.ResetCategoryFramePosition = function(category, x, y)
    BR.Movers.SavePosition(category, x or 0, y or 0)
end

-- Export Masque state for Options.lua
BR.Masque = {
    IsActive = function()
        return masqueGroup ~= nil and not masqueGroup.db.Disabled
    end,
}

-- Slash command handler
local function SlashHandler(msg)
    local cmd = msg:match("^(%S*)") or ""
    cmd = cmd:lower()

    if cmd == "test" then
        ToggleTestMode(false) -- no labels, for previews
    elseif cmd == "lock" then
        BuffRemindersDB.locked = true
        BR.Movers.HideAll()
        BR.Components.RefreshAll()
        print("|cff00ccffBuffReminders:|r Frames locked.")
    elseif cmd == "unlock" then
        BuffRemindersDB.locked = false
        BR.Movers.UpdateAnchor()
        BR.Components.RefreshAll()
        print("|cff00ccffBuffReminders:|r Frames unlocked.")
    else
        BR.Options.Toggle()
    end
end

-- Event handler
eventFrame = CreateFrame("Frame")
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
eventFrame:RegisterEvent("PET_STABLE_UPDATE")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
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
        local DB_VERSION = 16

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
                    db.defaults.glowStyle = db.glowStyle or 1
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

            -- [11] Migrate showOnlyPlayerClassBuff/showOnlyPlayerMissing to buffTrackingMode
            [11] = function()
                local classBuff = db.showOnlyPlayerClassBuff
                local playerMissing = db.showOnlyPlayerMissing
                if classBuff then
                    db.buffTrackingMode = "my_buffs"
                elseif playerMissing then
                    db.buffTrackingMode = "personal"
                else
                    db.buffTrackingMode = "all"
                end
                -- Clean up old keys
                db.showOnlyPlayerClassBuff = nil
                db.showOnlyPlayerMissing = nil
            end,
            -- [12] Migrate glowStyle (1-5 color variants) to glowType + glowColor (LibCustomGlow)
            [12] = function()
                if not db.defaults then
                    return
                end
                local oldStyle = db.defaults.glowStyle
                if oldStyle ~= nil then
                    -- All old styles were atlas-based pulsing → map to Pixel glow with the color
                    local colorMap = {
                        [1] = { 0.95, 0.57, 0.07, 1 }, -- Orange
                        [2] = { 1, 0.82, 0, 1 }, -- Gold
                        [3] = { 1, 0.8, 0, 1 }, -- Yellow
                        [4] = { 0.9, 0.9, 0.9, 1 }, -- White
                        [5] = { 1, 0.2, 0.2, 1 }, -- Red
                    }
                    db.defaults.glowType = 1 -- Pixel (closest to old atlas pulsing)
                    db.defaults.glowColor = colorMap[oldStyle] or { 0.95, 0.57, 0.07, 1 }
                    db.defaults.glowStyle = nil
                end
            end,
            -- [13] Unify consumable rebuff warning into per-category expiration glow
            [13] = function()
                if not db.defaults then
                    return
                end
                local defs = db.defaults
                local globalThreshold = defs.expirationThreshold or 15

                -- Migrate consumableRebuffWarning = false → per-category override
                if defs.consumableRebuffWarning == false then
                    if not db.categorySettings then
                        db.categorySettings = {}
                    end
                    if not db.categorySettings.consumable then
                        db.categorySettings.consumable = {}
                    end
                    db.categorySettings.consumable.useCustomAppearance = true
                    db.categorySettings.consumable.showExpirationGlow = false
                end

                -- Migrate consumableRebuffThreshold if different from global
                if defs.consumableRebuffThreshold ~= nil and defs.consumableRebuffThreshold ~= globalThreshold then
                    if not db.categorySettings then
                        db.categorySettings = {}
                    end
                    if not db.categorySettings.consumable then
                        db.categorySettings.consumable = {}
                    end
                    db.categorySettings.consumable.useCustomAppearance = true
                    db.categorySettings.consumable.expirationThreshold = defs.consumableRebuffThreshold
                end

                -- Clean up old keys
                defs.consumableRebuffWarning = nil
                defs.consumableRebuffThreshold = nil
                defs.consumableRebuffColor = nil
            end,
            -- [14] Tie growDirection to useCustomAppearance (was previously tied to split)
            [14] = function()
                if not db.categorySettings then
                    return
                end
                local gd = db.defaults or {}
                for _, catSettings in pairs(db.categorySettings) do
                    -- Users who had split + custom direction but no custom appearance
                    -- would lose their direction setting without this migration
                    if
                        catSettings.split
                        and catSettings.growDirection ~= nil
                        and not catSettings.useCustomAppearance
                    then
                        catSettings.useCustomAppearance = true
                        -- Snapshot current global defaults so the category is fully independent
                        if catSettings.iconSize == nil then
                            catSettings.iconSize = gd.iconSize or 64
                        end
                        if catSettings.spacing == nil then
                            catSettings.spacing = gd.spacing or 0.2
                        end
                        if catSettings.iconZoom == nil then
                            catSettings.iconZoom = gd.iconZoom or 8
                        end
                        if catSettings.borderSize == nil then
                            catSettings.borderSize = gd.borderSize or 2
                        end
                        if catSettings.iconAlpha == nil then
                            catSettings.iconAlpha = gd.iconAlpha or 1
                        end
                        if catSettings.textAlpha == nil then
                            catSettings.textAlpha = gd.textAlpha or 1
                        end
                        if catSettings.textColor == nil and gd.textColor then
                            local tc = gd.textColor
                            catSettings.textColor = { tc[1], tc[2], tc[3] }
                        end
                    end
                end
            end,
            -- [15] Migrate invertGlow boolean to glowMode enum
            [15] = function()
                if not db.customBuffs then
                    return
                end
                for _, buff in pairs(db.customBuffs) do
                    if buff.invertGlow then
                        buff.glowMode = "whenNotGlowing"
                    end
                    buff.invertGlow = nil
                end
            end,
            -- [16] Migrate glow color: old orange default → new yellow default,
            -- and auto-enable useCustomGlowColor for users who had a custom color
            [16] = function()
                local oldOrange = { 0.95, 0.57, 0.07, 1 }
                local newDefault = BR.Glow.DEFAULT_COLOR
                local function isOldOrange(c)
                    return c and c[1] == oldOrange[1] and c[2] == oldOrange[2] and c[3] == oldOrange[3]
                end
                if db.defaults and db.defaults.glowColor then
                    if isOldOrange(db.defaults.glowColor) then
                        db.defaults.glowColor = { newDefault[1], newDefault[2], newDefault[3], newDefault[4] }
                    else
                        db.defaults.useCustomGlowColor = true
                    end
                end
                if db.categorySettings then
                    for _, catSettings in pairs(db.categorySettings) do
                        if catSettings.glowColor then
                            if isOldOrange(catSettings.glowColor) then
                                catSettings.glowColor = { newDefault[1], newDefault[2], newDefault[3], newDefault[4] }
                            else
                                catSettings.useCustomGlowColor = true
                            end
                        end
                    end
                end
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

        -- One-time self buffs click-to-cast notice
        if not db.selfClickNoticeShown then
            db.selfClickNoticeShown = true
            C_Timer.After(5, function()
                if BuffRemindersDB.showLoginMessages ~= false then
                    print(
                        "|cff00ccffBuffReminders:|r Self buffs now support clickable icons! Enable it in |cffffcc00/br|r under the Self category."
                    )
                end
            end)
        end

        -- Clean up old one-time notice flags
        db.glowUpdateNoticeShown = nil

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
            if customBuff.glowMode ~= "disabled" then
                RegisterGlowBuff(customBuff, "custom")
            end
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
        if not mainFrame then
            InitializeFrames()
            -- Initialize action buttons for categories with clickable enabled
            for _, cat in ipairs(CATEGORIES) do
                local cs = BuffRemindersDB.categorySettings and BuffRemindersDB.categorySettings[cat]
                if cs and cs.clickable then
                    BR.SecureButtons.UpdateActionButtons(cat)
                end
            end
        end
        BR.SecureButtons.InvalidateConsumableCache()
        SeedGlowingSpells() -- Catch glows that were active before event registration
        if not inCombat then
            StartUpdates()
        end
        -- Delayed update to catch glow events that fire after reload
        C_Timer.After(0.5, SetDirty)
        -- Refresh custom buff icons after spell data is fully loaded (talent-modified icons)
        C_Timer.After(1.5, function()
            for key, def in pairs(BuffRemindersDB.customBuffs or {}) do
                local frame = buffFrames[key]
                if frame and def.spellID then
                    local texture = GetBuffTexture(def.spellID)
                    if texture then
                        frame.icon:SetTexture(texture)
                    end
                end
            end
        end)
    elseif event == "GROUP_ROSTER_UPDATE" then
        SetDirty()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        BR.StateHelpers.ScanEatingState()
        BR.SecureButtons.RefreshOverlaySpells()
        StartUpdates()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        StopUpdates()
        UpdateDisplay() -- last update before combat lockdown
    elseif event == "PLAYER_DEAD" then
        HideAllDisplayFrames()
    elseif event == "PLAYER_UNGHOST" then
        SetDirty()
    elseif event == "UNIT_AURA" then
        -- Skip in combat (auras change frequently, and we can't check buffs or eat in combat)
        if not InCombatLockdown() and mainFrame and mainFrame:IsShown() then
            if arg1 == "player" then
                BR.StateHelpers.UpdateEatingState(arg2)
            end
            dirty = true -- OnUpdate will pick this up with throttle
        end
    elseif event == "UNIT_PET" then
        if arg1 == "player" then
            SetDirty()
        end
    elseif event == "PET_BAR_UPDATE" then
        SetDirty()
    elseif event == "PET_STABLE_UPDATE" then
        BR.PetHelpers.InvalidatePetActions()
        SetDirty()
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        SetDirty()
    elseif event == "PLAYER_DIFFICULTY_CHANGED" then
        BR.BuffState.InvalidateContentTypeCache()
        SetDirty()
    elseif event == "PLAYER_UPDATE_RESTING" then
        isResting = IsResting()
        SetDirty()
    elseif event == "READY_CHECK" then
        -- Cancel any existing timer
        if readyCheckTimer then
            readyCheckTimer:Cancel()
        end
        BR.BuffState.SetReadyCheckState(true)
        UpdateDisplay() -- user-facing, must be instant
        -- Start timer to reset ready check state
        local duration = BuffRemindersDB.readyCheckDuration or 15
        readyCheckTimer = C_Timer.NewTimer(duration, function()
            BR.BuffState.SetReadyCheckState(false)
            readyCheckTimer = nil
            UpdateDisplay() -- must be instant
        end)
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        local spellID = arg1
        glowingSpells[spellID] = true
        SetDirty()
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local spellID = arg1
        glowingSpells[spellID] = nil
        SetDirty()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 ~= "player" then
            return
        end
        -- Invalidate caches when player changes spec
        InvalidatePlayerRoleCache()
        BR.BuffState.InvalidateSpellCache()
        BR.PetHelpers.InvalidatePetActions()
        BR.SecureButtons.RefreshOverlaySpells()
        UpdateDisplay() -- cache invalidation + immediate feedback
        -- Spells can become available shortly after spec swap; refresh once more
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                BR.SecureButtons.RefreshOverlaySpells()
            end
            SetDirty()
        end)
    elseif event == "TRAIT_CONFIG_UPDATED" then
        -- Invalidate spell cache when talents change (within same spec)
        BR.BuffState.InvalidateSpellCache()
        BR.PetHelpers.InvalidatePetActions()
        BR.SecureButtons.RefreshOverlaySpells()
        SetDirty()
    elseif event == "SPELLS_CHANGED" then
        -- Catch delayed spell availability after spec/talent changes (noisy event, keep cheap)
        BR.BuffState.InvalidateSpellCache()
        BR.PetHelpers.InvalidatePetActions()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        SetDirty()
    elseif event == "BAG_UPDATE_DELAYED" then
        BR.SecureButtons.InvalidateConsumableCache()
        SetDirty()
        BR.SecureButtons.UpdateActionButtons("consumable")
    end
end)
