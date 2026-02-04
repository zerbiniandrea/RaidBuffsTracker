local addonName, BR = ...

-- Aliases for shared namespace (populated by Core.lua and Components.lua)
local Components = BR.Components
local SetupTooltip = BR.SetupTooltip
local CreateButton = BR.CreateButton

-- Global API table for external addon integration
BuffReminders = {}
local EXPORT_PREFIX = "!BR_"

-- Buff tables by category (excludes custom, which is stored in db.customBuffs)
local BUFF_TABLES = {
    ---@type RaidBuff[]
    raid = {
        { spellID = { 1459, 432778 }, key = "intellect", name = "Arcane Intellect", class = "MAGE" }, -- 432778 = NPC version
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
        { spellID = { 1126, 432661 }, key = "versatility", name = "Mark of the Wild", class = "DRUID" }, -- 432661 = NPC version
        { spellID = 21562, key = "stamina", name = "Power Word: Fortitude", class = "PRIEST" },
        { spellID = 462854, key = "skyfury", name = "Skyfury", class = "SHAMAN" },
    },
    ---@type PresenceBuff[]
    presence = {
        {
            spellID = { 381637, 5761 },
            key = "atrophicNumbingPoison",
            name = "Atrophic/Numbing Poison",
            class = "ROGUE",
            missingText = "NO\nPOISON",
        },
        { spellID = 465, key = "devotionAura", name = "Devotion Aura", class = "PALADIN", missingText = "NO\nAURA" },
        {
            spellID = 20707,
            key = "soulstone",
            name = "Soulstone",
            class = "WARLOCK",
            missingText = "NO\nSTONE",
            infoTooltip = "Ready Check Only|This buff is only shown during ready checks.",
            noGlow = true,
        },
    },
    ---@type TargetedBuff[]
    targeted = {
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
            excludeTalentSpellID = 200025, -- Hide when Beacon of Virtue is known
            iconOverride = 236247, -- Force original icon (talents replace the texture)
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
    },
    ---@type SelfBuff[]
    self = {
        -- Warlock Grimoire of Sacrifice
        {
            spellID = 108503,
            buffIdOverride = 196099,
            key = "grimoireOfSacrifice",
            name = "Grimoire of Sacrifice",
            class = "WARLOCK",
            missingText = "NO\nGRIM",
        },
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
        -- Rogue poisons: lethal (Instant, Wound, Deadly, Amplifying) and non-lethal (Numbing, Atrophic, Crippling)
        -- With Dragon-Tempered Blades (381801): need 2 lethal + 2 non-lethal
        -- Without talent: need 1 lethal + 1 non-lethal
        {
            spellID = 2823, -- Deadly Poison (for icon)
            key = "roguePoisons",
            name = "Rogue Poisons",
            class = "ROGUE",
            missingText = "NO\nSELF\nPOISON",
            customCheck = function()
                local lethalPoisons = { 315584, 8679, 2823, 381664 } -- Instant, Wound, Deadly, Amplifying
                local nonLethalPoisons = { 5761, 381637, 3408 } -- Numbing, Atrophic, Crippling

                local lethalCount = 0
                local nonLethalCount = 0

                for _, id in ipairs(lethalPoisons) do
                    local auraData
                    pcall(function()
                        auraData = C_UnitAuras.GetUnitAuraBySpellID("player", id)
                    end)
                    if auraData then
                        lethalCount = lethalCount + 1
                    end
                end

                for _, id in ipairs(nonLethalPoisons) do
                    local auraData
                    pcall(function()
                        auraData = C_UnitAuras.GetUnitAuraBySpellID("player", id)
                    end)
                    if auraData then
                        nonLethalCount = nonLethalCount + 1
                    end
                end

                -- Dragon-Tempered Blades (381801): can have 2 of each
                local hasDragonTemperedBlades = IsPlayerSpell(381801)
                local requiredLethal = hasDragonTemperedBlades and 2 or 1
                local requiredNonLethal = hasDragonTemperedBlades and 2 or 1

                return lethalCount < requiredLethal or nonLethalCount < requiredNonLethal
            end,
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
    },
    ---@type ConsumableBuff[]
    consumable = {
        -- Augment Rune (The War Within + Midnight)
        {
            spellID = {
                453250, -- Crystallized Augment Rune (TWW)
                1234969, -- Ethereal Augment Rune (TWW permanent)
                1242347, -- Soulgorged Augment Rune (TWW raid drop)
                1264426, -- Void-Touched Augment Rune (Midnight)
            },
            displaySpellIDs = { 453250, 1234969, 1242347 }, -- Show TWW rune icons in UI
            key = "rune",
            name = "Rune",
            missingText = "NO\nRUNE",
            groupId = "rune",
        },
        -- Flasks (The War Within + Midnight)
        {
            spellID = {
                -- The War Within
                432021, -- Flask of Alchemical Chaos
                431971, -- Flask of Tempered Aggression
                431972, -- Flask of Tempered Swiftness
                431973, -- Flask of Tempered Versatility
                431974, -- Flask of Tempered Mastery
                -- Midnight
                1235057, -- Flask of Thalassian Resistance (Versatility)
                1235108, -- Flask of the Magisters (Mastery)
                1235110, -- Flask of the Blood Knights (Haste)
                1235111, -- Flask of the Shattered Sun (Critical Strike)
            },
            displaySpellIDs = {
                -- Show only TWW flask icons in UI
                432021, -- Flask of Alchemical Chaos
                431971, -- Flask of Tempered Aggression
                431972, -- Flask of Tempered Swiftness
                431973, -- Flask of Tempered Versatility
                431974, -- Flask of Tempered Mastery
            },
            key = "flask",
            name = "Flask",
            missingText = "NO\nFLASK",
            groupId = "flask",
        },
        -- Food (all expansions - detected by icon ID)
        {
            buffIconID = 136000, -- All food buffs use this icon
            key = "food",
            name = "Food",
            missingText = "NO\nFOOD",
            groupId = "food",
            iconOverride = 136000,
        },
        -- Weapon Buffs (oils, stones - but not for classes with imbues)
        {
            checkWeaponEnchant = true, -- Check if any weapon enchant exists
            key = "weaponBuff",
            name = "Weapon",
            missingText = "NO\nWEAPON\nBUFF",
            groupId = "weaponBuff",
            iconOverride = { 609892, 3622195, 3622196 }, -- Oil, Whetstone, Weightstone/Razorstone
            excludeIfSpellKnown = {
                -- Shaman imbues
                382021, -- Earthliving Weapon
                318038, -- Flametongue Weapon
                33757, -- Windfury Weapon
                -- Paladin rites
                433583, -- Rite of Adjuration
                433568, -- Rite of Sanctification
            },
        },
        -- Healthstone (ready check only - checks inventory)
        {
            itemID = { 5512, 224464 }, -- Healthstone, Demonic Healthstone
            key = "healthstone",
            name = "Healthstone",
            missingText = "NO\nSTONE",
            groupId = "healthstone",
            iconOverride = 538745, -- Healthstone icon
            readyCheckOnly = true,
            infoTooltip = "Ready Check Only|This is only shown during ready checks.",
        },
    },
}

-- Local aliases for direct access
local RaidBuffs = BUFF_TABLES.raid
local PresenceBuffs = BUFF_TABLES.presence
local TargetedBuffs = BUFF_TABLES.targeted
local SelfBuffs = BUFF_TABLES.self
local Consumables = BUFF_TABLES.consumable

---@type table<string, BuffGroup>
local BuffGroups = {
    beacons = { displayName = "Beacons", missingText = "NO\nBEACONS" },
    shamanImbues = { displayName = "Shaman Imbues" },
    paladinRites = { displayName = "Paladin Rites" },
    shamanShields = { displayName = "Shaman Shields" },
    -- Consumable groups
    flask = { displayName = "Flask" },
    food = { displayName = "Food" },
    rune = { displayName = "Augment Rune" },
    weaponBuff = { displayName = "Weapon Buff" },
    healthstone = { displayName = "Healthstone!" },
}

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

-- UI Constants (needed by helper functions below)
local TEXCOORD_INSET = 0.08

-- ============================================================================
-- UI HELPER FUNCTIONS
-- ============================================================================

---Create a draggable panel with standard backdrop
---@param name string? Frame name (nil for anonymous)
---@param width number
---@param height number
---@param options? {bgColor?: table, borderColor?: table, strata?: string, level?: number, escClose?: boolean}
---@return table
local function CreatePanel(name, width, height, options)
    options = options or {}
    local bgColor = options.bgColor or { 0.1, 0.1, 0.1, 0.95 }
    local borderColor = options.borderColor or { 0.3, 0.3, 0.3, 1 }

    local panel = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetPoint("CENTER")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(unpack(bgColor))
    panel:SetBackdropBorderColor(unpack(borderColor))
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata(options.strata or "DIALOG")
    if options.level then
        panel:SetFrameLevel(options.level)
    end
    if options.escClose and name then
        tinsert(UISpecialFrames, name)
    end
    return panel
end

---Create a section header with yellow text
---@param parent table
---@param text string
---@param x number
---@param y number
---@return table header
---@return number newY
local function CreateSectionHeader(parent, text, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", x, y)
    header:SetText("|cffffcc00" .. text .. "|r")
    return header, y - 18
end

---Create a buff icon texture with standard formatting
---@param parent table
---@param size number
---@param textureID? number|string
---@return table
local function CreateBuffIcon(parent, size, textureID)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
    if textureID then
        icon:SetTexture(textureID)
    end
    return icon
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
local DEFAULT_BORDER_SIZE = 2
local DEFAULT_ICON_ZOOM = 8 -- percentage (0.08 as inset)
local MISSING_TEXT_SCALE = 0.6 -- scale for "NO X" warning text
local OPTIONS_BASE_SCALE = 1.2

-- Locals
local mainFrame
local buffFrames = {}
local updateTicker
local inReadyCheck = false
local readyCheckTimer = nil
local testMode = false
local testModeData = nil -- Stores seeded fake values for consistent test display
local playerClass = nil -- Cached player class, set once on init
local optionsPanel
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

---Get or create category settings entry in DB (reduces boilerplate in onChange handlers)
---@param category string
---@return table settings The category settings table
local function GetOrCreateCategorySettings(category)
    local db = BuffRemindersDB
    db.categorySettings = db.categorySettings or {}
    db.categorySettings[category] = db.categorySettings[category] or {}
    return db.categorySettings[category]
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
local UpdateDisplay, UpdateAnchor, ShowGlowDemo, ToggleTestMode, RefreshTestDisplay
local ShowCustomBuffModal
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

-- ============================================================================
-- OPTIONS PANEL (Two-Column Layout)
-- ============================================================================

local function CreateOptionsPanel()
    local PANEL_WIDTH = 540
    local COL_PADDING = 20
    local COL_WIDTH = (PANEL_WIDTH - COL_PADDING * 3) / 2 -- Two columns with padding
    local SECTION_SPACING = 12
    local ITEM_HEIGHT = 22

    local panel = CreatePanel("BuffRemindersOptions", PANEL_WIDTH, 400, { escClose = true })
    panel:Hide()

    -- Track all EditBoxes so we can clear focus when panel hides
    local panelEditBoxes = {} -- luacheck: ignore 431 (intentionally shadows module-level nil)
    Components.SetEditBoxesRef(panelEditBoxes)
    panel:SetScript("OnHide", function()
        for _, editBox in ipairs(panelEditBoxes) do
            editBox:ClearFocus()
        end
    end)

    -- Addon icon
    local addonIcon = CreateBuffIcon(panel, 28, "Interface\\AddOns\\BuffReminders\\icon.tga")
    addonIcon:SetPoint("TOPLEFT", 12, -8)

    -- Title (next to icon)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", addonIcon, "RIGHT", 8, 0)
    title:SetText("BuffReminders")

    -- Version (next to title, smaller font)
    local version = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 6, 0)
    local addonVersion = C_AddOns.GetAddOnMetadata("BuffReminders", "Version") or ""
    version:SetText(addonVersion)

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

    -- Close button (same style as scale buttons)
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("LEFT", scaleUp, "RIGHT", 8, 0)
    closeBtn:SetText("x")
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
    end)

    -- ========== TABS (flat style, sitting at top) ==========
    local tabButtons = {}
    local contentContainers = {}
    local TAB_HEIGHT = 22 -- Used for positioning separator and content

    local function SetActiveTab(tabName)
        for name, tab in pairs(tabButtons) do
            tab:SetActive(name == tabName)
        end
        for name, container in pairs(contentContainers) do
            if name == tabName then
                container:Show()
            else
                container:Hide()
            end
        end
    end

    tabButtons.buffs = Components.Tab(panel, { name = "buffs", label = "Buffs" })
    tabButtons.custom = Components.Tab(panel, { name = "custom", label = "Custom Buffs" })
    tabButtons.appearance = Components.Tab(panel, { name = "appearance", label = "Appearance" })
    tabButtons.settings = Components.Tab(panel, { name = "settings", label = "Settings" })
    tabButtons.profiles = Components.Tab(panel, { name = "profiles", label = "Import/Export" })

    -- Position tabs below title bar
    tabButtons.buffs:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_PADDING, -40)
    tabButtons.custom:SetPoint("LEFT", tabButtons.buffs, "RIGHT", 4, 0)
    tabButtons.appearance:SetPoint("LEFT", tabButtons.custom, "RIGHT", 4, 0)
    tabButtons.settings:SetPoint("LEFT", tabButtons.appearance, "RIGHT", 4, 0)
    tabButtons.profiles:SetPoint("LEFT", tabButtons.settings, "RIGHT", 4, 0)

    tabButtons.buffs:SetScript("OnClick", function()
        SetActiveTab("buffs")
    end)
    tabButtons.appearance:SetScript("OnClick", function()
        SetActiveTab("appearance")
    end)
    tabButtons.settings:SetScript("OnClick", function()
        SetActiveTab("settings")
    end)
    tabButtons.custom:SetScript("OnClick", function()
        SetActiveTab("custom")
    end)
    tabButtons.profiles:SetScript("OnClick", function()
        SetActiveTab("profiles")
    end)

    -- Separator line below tabs
    local tabSeparator = panel:CreateTexture(nil, "ARTWORK")
    tabSeparator:SetHeight(1)
    tabSeparator:SetPoint("TOPLEFT", COL_PADDING, -40 - TAB_HEIGHT)
    tabSeparator:SetPoint("TOPRIGHT", -COL_PADDING, -40 - TAB_HEIGHT)
    tabSeparator:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- ========== CONTENT CONTAINERS ==========
    local CONTENT_TOP = -40 - TAB_HEIGHT - 16 -- Below tabs and separator with padding

    local buffsContent = CreateFrame("Frame", nil, panel)
    buffsContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    buffsContent:SetSize(PANEL_WIDTH, 400) -- Height adjusted later
    contentContainers.buffs = buffsContent

    -- Appearance tab uses a scroll frame for expandable content
    local appearanceScrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    appearanceScrollFrame:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    appearanceScrollFrame:SetPoint("BOTTOMRIGHT", -24, 50) -- Leave room for scrollbar and bottom buttons
    appearanceScrollFrame:SetClipsChildren(true) -- Clip content that overflows
    appearanceScrollFrame:Hide()
    contentContainers.appearance = appearanceScrollFrame

    -- Position the scrollbar properly
    local scrollBar = appearanceScrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", appearanceScrollFrame, "TOPRIGHT", -16, -16)
        scrollBar:SetPoint("BOTTOMLEFT", appearanceScrollFrame, "BOTTOMRIGHT", -16, 16)
    end

    local appearanceContent = CreateFrame("Frame", nil, appearanceScrollFrame)
    appearanceContent:SetSize(PANEL_WIDTH - 24, 400) -- Width minus scrollbar
    appearanceScrollFrame:SetScrollChild(appearanceContent)
    panel.appearanceScrollFrame = appearanceScrollFrame

    -- Update callback for category visibility changes (used by Components.CategoryHeader)
    local function OnCategoryVisibilityChange()
        if testMode then
            RefreshTestDisplay()
        else
            UpdateDisplay()
        end
    end

    -- Settings tab content
    local settingsContent = CreateFrame("Frame", nil, panel)
    settingsContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    settingsContent:SetSize(PANEL_WIDTH, 400)
    settingsContent:Hide()
    contentContainers.settings = settingsContent

    local customContent = CreateFrame("Frame", nil, panel)
    customContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    customContent:SetSize(PANEL_WIDTH, 400)
    customContent:Hide()
    contentContainers.custom = customContent

    local profilesContent = CreateFrame("Frame", nil, panel)
    profilesContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    profilesContent:SetSize(PANEL_WIDTH, 400)
    profilesContent:Hide()
    contentContainers.profiles = profilesContent

    -- Import/Export UI
    local yOffset = -10

    -- Format change warning
    local formatWarning = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formatWarning:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    formatWarning:SetText("|cffff9900Note:|r Export string format changed in v2.6.1. Old strings are incompatible.")
    formatWarning:SetWidth(PANEL_WIDTH - COL_PADDING * 2)
    formatWarning:SetJustifyH("LEFT")
    yOffset = yOffset - 20

    -- Export section
    local exportHeader = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exportHeader:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    exportHeader:SetText("|cffffcc00Export Settings|r")
    yOffset = yOffset - 20

    local exportDesc = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    exportDesc:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    exportDesc:SetText("Copy the string below to share your settings with others.")
    exportDesc:SetWidth(PANEL_WIDTH - COL_PADDING * 2)
    exportDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 30

    -- Export text box (scrollable, read-only)
    local exportScrollFrame = CreateFrame("ScrollFrame", nil, profilesContent, "UIPanelScrollFrameTemplate")
    exportScrollFrame:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    exportScrollFrame:SetSize(PANEL_WIDTH - COL_PADDING * 2 - 24, 80)

    local exportEditBox = CreateFrame("EditBox", nil, exportScrollFrame)
    exportEditBox:SetMultiLine(true)
    exportEditBox:SetFontObject("GameFontHighlightSmall")
    exportEditBox:SetWidth(PANEL_WIDTH - COL_PADDING * 2 - 24)
    exportEditBox:SetAutoFocus(false)
    exportEditBox:SetTextInsets(6, 6, 6, 6)
    exportEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    exportEditBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        local height =
            math.max(80, select(2, self:GetFont()) * math.max(1, select(2, string.gsub(text, "\n", "\n")) + 1) + 10)
        self:SetHeight(height)
    end)
    exportEditBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText() -- Auto-select all text when clicked
    end)
    exportScrollFrame:SetScrollChild(exportEditBox)

    -- Add background to export box
    local exportBg = exportScrollFrame:CreateTexture(nil, "BACKGROUND")
    exportBg:SetAllPoints()
    exportBg:SetColorTexture(0, 0, 0, 0.5)

    -- Add border to export box for better visibility
    local exportBorder = CreateFrame("Frame", nil, exportScrollFrame, "BackdropTemplate")
    exportBorder:SetAllPoints(exportScrollFrame)
    exportBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    exportBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    -- Export button
    local exportButton = CreateButton(profilesContent, "Export", function()
        local exportString, err = BuffReminders:Export()
        if exportString then
            exportEditBox:SetText(exportString)
            exportEditBox:HighlightText()
            exportEditBox:SetFocus()
        else
            exportEditBox:SetText("Error: " .. (err or "Failed to export"))
        end
    end)
    exportButton:SetPoint("TOPLEFT", COL_PADDING, yOffset - 90)

    yOffset = yOffset - 120

    -- Separator
    local importExportSeparator = profilesContent:CreateTexture(nil, "ARTWORK")
    importExportSeparator:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    importExportSeparator:SetSize(PANEL_WIDTH - COL_PADDING * 2, 1)
    importExportSeparator:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    yOffset = yOffset - 15

    -- Import section
    local importHeader = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    importHeader:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    importHeader:SetText("|cffffcc00Import Settings|r")
    yOffset = yOffset - 20

    local importDesc = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importDesc:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    importDesc:SetText("Paste a settings string below and click Import. This will overwrite your current settings.")
    importDesc:SetWidth(PANEL_WIDTH - COL_PADDING * 2)
    importDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 30

    -- Import text box (scrollable, editable)
    local importScrollFrame = CreateFrame("ScrollFrame", nil, profilesContent, "UIPanelScrollFrameTemplate")
    importScrollFrame:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    importScrollFrame:SetSize(PANEL_WIDTH - COL_PADDING * 2 - 24, 80)

    local importEditBox = CreateFrame("EditBox", nil, importScrollFrame)
    importEditBox:SetMultiLine(true)
    importEditBox:SetFontObject("GameFontHighlightSmall")
    importEditBox:SetWidth(PANEL_WIDTH - COL_PADDING * 2 - 24)
    importEditBox:SetAutoFocus(false)
    importEditBox:SetTextInsets(6, 6, 6, 6) -- Add padding for better readability
    importEditBox:EnableMouse(true) -- Ensure mouse clicks work
    importEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    importEditBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        local height =
            math.max(80, select(2, self:GetFont()) * math.max(1, select(2, string.gsub(text, "\n", "\n")) + 1) + 10)
        self:SetHeight(height)
    end)
    importScrollFrame:SetScrollChild(importEditBox)

    -- Add background to import box
    local importBg = importScrollFrame:CreateTexture(nil, "BACKGROUND")
    importBg:SetAllPoints()
    importBg:SetColorTexture(0, 0, 0, 0.5)

    -- Add border to import box with focus feedback
    local importBorder = CreateFrame("Frame", nil, importScrollFrame, "BackdropTemplate")
    importBorder:SetAllPoints(importScrollFrame)
    importBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    importBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    -- Change border color when focused/unfocused
    importEditBox:SetScript("OnEditFocusGained", function(self)
        importBorder:SetBackdropBorderColor(1, 0.82, 0, 1) -- Gold when focused
        importBg:SetColorTexture(0.1, 0.1, 0.1, 0.8) -- Darker background
        self:SetCursorPosition(self:GetText():len())
    end)
    importEditBox:SetScript("OnEditFocusLost", function(self)
        importBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) -- Gray when unfocused
        importBg:SetColorTexture(0, 0, 0, 0.5) -- Lighter background
    end)

    yOffset = yOffset - 90

    -- Import button and status message
    local importStatus = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importStatus:SetWidth(PANEL_WIDTH - COL_PADDING * 2 - 120)
    importStatus:SetJustifyH("LEFT")
    importStatus:SetText("")

    local importButton = CreateButton(profilesContent, "Import", function()
        local importString = importEditBox:GetText()
        local success, err = BuffReminders:Import(importString)

        if success then
            importStatus:SetText("|cff00ff00Settings imported successfully!|r")
            StaticPopup_Show("BUFFREMINDERS_RELOAD_UI")
        else
            importStatus:SetText("|cffff0000Error: " .. (err or "Unknown error") .. "|r")
        end
    end)
    importButton:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    importStatus:SetPoint("LEFT", importButton, "RIGHT", 10, 0)

    panel.contentContainers = contentContainers

    -- Column anchors
    local leftColX = COL_PADDING
    local startY = 0 -- Relative to content container top

    panel.buffCheckboxes = {}

    -- ========== HELPER FUNCTIONS ==========

    -- Create buff checkbox (compact, for left column)
    -- spellIDs can be a single ID, a table of IDs (for multi-rank spells), or a table of tables (for grouped buffs with multiple icons)
    -- infoTooltip is optional: "Title|Description" format shows a "?" icon with tooltip
    -- iconOverride is optional: single texture ID or array of texture IDs to show instead of deriving icons from spellIDs
    local function CreateBuffCheckbox(x, y, spellIDs, key, displayName, infoTooltip, iconOverride)
        local cb = CreateFrame("CheckButton", nil, buffsContent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetChecked(BuffRemindersDB.enabledBuffs[key] ~= false)
        cb:SetScript("OnClick", function(self)
            BuffRemindersDB.enabledBuffs[key] = self:GetChecked()
            UpdateDisplay()
        end)

        -- Handle icons: either use iconOverride or derive from spellIDs
        local lastAnchor = cb
        if iconOverride then
            -- Icon override (single ID or array of IDs)
            local iconList = type(iconOverride) == "table" and iconOverride or { iconOverride }
            for _, textureID in ipairs(iconList) do
                local icon = CreateBuffIcon(buffsContent, 18, textureID)
                icon:SetPoint("LEFT", lastAnchor, lastAnchor == cb and "RIGHT" or "RIGHT", 2, 0)
                lastAnchor = icon
            end
        elseif spellIDs then
            -- Multiple icons for grouped buffs (dedupe by texture)
            local spellList = type(spellIDs) == "table" and spellIDs or { spellIDs }
            local seenTextures = {}
            for _, spellID in ipairs(spellList) do
                local texture = GetBuffTexture(spellID)
                if texture and not seenTextures[texture] then
                    seenTextures[texture] = true
                    local icon = CreateBuffIcon(buffsContent, 18, texture)
                    icon:SetPoint("LEFT", lastAnchor, lastAnchor == cb and "RIGHT" or "RIGHT", 2, 0)
                    lastAnchor = icon
                end
            end
        end

        local label = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        label:SetText(displayName)

        -- Add info tooltip icon if specified
        if infoTooltip then
            local infoIcon = buffsContent:CreateTexture(nil, "ARTWORK")
            infoIcon:SetSize(14, 14)
            infoIcon:SetPoint("LEFT", label, "RIGHT", 4, 0)
            infoIcon:SetAtlas("QuestNormal")
            -- Create invisible button for tooltip
            local infoBtn = CreateFrame("Button", nil, buffsContent)
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

    -- Create checkbox with label
    local function CreateCheckbox(parent, x, y, labelText, checked, onClick, tooltip)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetChecked(checked)
        cb:SetScript("OnClick", onClick)

        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(labelText)
        cb.label = label

        if tooltip then
            SetupTooltip(cb, labelText, tooltip)
        end

        return cb, y - ITEM_HEIGHT
    end

    -- Render checkboxes for any buff array
    -- Handles grouping automatically if groupId field is present
    local function RenderBuffCheckboxes(x, y, buffArray)
        -- Pass 1: Collect grouped data (flatten tables)
        local groupSpells = {}
        local groupDisplaySpells = {}
        local groupIconOverrides = {}
        for _, buff in ipairs(buffArray) do
            if buff.groupId then
                groupSpells[buff.groupId] = groupSpells[buff.groupId] or {}
                groupDisplaySpells[buff.groupId] = groupDisplaySpells[buff.groupId] or {}
                -- Flatten: buff.spellID can be a number or table of numbers
                if buff.spellID then
                    local spellList = type(buff.spellID) == "table" and buff.spellID or { buff.spellID }
                    for _, id in ipairs(spellList) do
                        table.insert(groupSpells[buff.groupId], id)
                    end
                end
                -- Flatten displaySpellIDs for UI icons
                if buff.displaySpellIDs then
                    local displayList = type(buff.displaySpellIDs) == "table" and buff.displaySpellIDs
                        or { buff.displaySpellIDs }
                    for _, id in ipairs(displayList) do
                        table.insert(groupDisplaySpells[buff.groupId], id)
                    end
                end
                -- Track iconOverride (use first one found for the group)
                if buff.iconOverride and not groupIconOverrides[buff.groupId] then
                    groupIconOverrides[buff.groupId] = buff.iconOverride
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
                    local iconOverride = groupIconOverrides[buff.groupId]
                    -- Use displaySpellIDs if available, otherwise fall back to all spellIDs
                    local displaySpells = groupDisplaySpells[buff.groupId]
                    local spells = (#displaySpells > 0) and displaySpells or groupSpells[buff.groupId]
                    -- If no spellIDs but has iconOverride, pass nil for spells
                    if #spells == 0 then
                        spells = nil
                    end
                    y = CreateBuffCheckbox(
                        x,
                        y,
                        spells,
                        buff.groupId,
                        groupInfo.displayName,
                        buff.infoTooltip,
                        iconOverride
                    )
                end
            else
                -- For non-grouped buffs, use displaySpellIDs if available
                local displaySpells = buff.displaySpellIDs or buff.spellID
                y = CreateBuffCheckbox(x, y, displaySpells, buff.key, buff.name, buff.infoTooltip, buff.iconOverride)
            end
        end

        return y
    end

    -- ========== BUFFS TAB: BUFF SELECTION (Two Columns) ==========
    local buffsLeftX = leftColX
    local buffsRightX = leftColX + COL_WIDTH + COL_PADDING
    local buffsLeftY = startY
    local buffsRightY = startY

    -- LEFT COLUMN: Group-wide buffs
    -- Raid Buffs header
    local raidHeader =
        Components.CategoryHeader(buffsContent, { text = "Raid Buffs", category = "raid" }, OnCategoryVisibilityChange)
    raidHeader:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    buffsLeftY = buffsLeftY - 18
    local raidNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    raidNote:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    raidNote:SetText("(for the whole group)")
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsLeftX, buffsLeftY, RaidBuffs)

    buffsLeftY = buffsLeftY - SECTION_SPACING

    -- Presence Buffs header
    local presenceHeader = Components.CategoryHeader(
        buffsContent,
        { text = "Presence Buffs", category = "presence" },
        OnCategoryVisibilityChange
    )
    presenceHeader:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    buffsLeftY = buffsLeftY - 18
    local presenceNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    presenceNote:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    presenceNote:SetText("(at least 1 person needs)")
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsLeftX, buffsLeftY, PresenceBuffs)

    buffsLeftY = buffsLeftY - SECTION_SPACING

    -- Consumables header
    local consumableHeader = Components.CategoryHeader(
        buffsContent,
        { text = "Consumables", category = "consumable" },
        OnCategoryVisibilityChange
    )
    consumableHeader:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    buffsLeftY = buffsLeftY - 18
    local consumablesNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    consumablesNote:SetPoint("TOPLEFT", buffsLeftX + 5, buffsLeftY)
    consumablesNote:SetText("(flasks, food, runes, and weapon oils)")
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsLeftX, buffsLeftY, Consumables)

    -- RIGHT COLUMN: Individual buffs
    -- Targeted Buffs header
    local targetedHeader = Components.CategoryHeader(
        buffsContent,
        { text = "Targeted Buffs", category = "targeted" },
        OnCategoryVisibilityChange
    )
    targetedHeader:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    buffsRightY = buffsRightY - 18
    local targetedNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    targetedNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    targetedNote:SetText("(buffs to maintain on someone else)")
    buffsRightY = buffsRightY - 14
    buffsRightY = RenderBuffCheckboxes(buffsRightX, buffsRightY, TargetedBuffs)

    buffsRightY = buffsRightY - SECTION_SPACING

    -- Self Buffs header
    local selfHeader =
        Components.CategoryHeader(buffsContent, { text = "Self Buffs", category = "self" }, OnCategoryVisibilityChange)
    selfHeader:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    buffsRightY = buffsRightY - 18
    local selfNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    selfNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    selfNote:SetText("(buffs strictly on yourself)")
    buffsRightY = buffsRightY - 14
    buffsRightY = RenderBuffCheckboxes(buffsRightX, buffsRightY, SelfBuffs)

    -- Set buffs content height (use the taller column)
    buffsContent:SetHeight(math.max(math.abs(buffsLeftY), math.abs(buffsRightY)) + 20)

    -- ========== FRAMES TAB: SINGLE COLUMN LAYOUT ==========
    local framesX = leftColX
    local framesY = startY

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
    panel.SetCheckboxEnabled = SetCheckboxEnabled

    -- ========== SECTION: MAIN FRAME ==========
    local mainFrameHeader
    mainFrameHeader, framesY = CreateSectionHeader(appearanceContent, "Main Frame", framesX, framesY)

    -- Reset button next to the header (will be wired up after sliders are created)
    local mainResetBtn = CreateButton(appearanceContent, "Reset", function() end, {
        title = "Reset Main Frame",
        desc = "Reset all main frame settings to defaults",
    })
    mainResetBtn:SetPoint("LEFT", mainFrameHeader, "RIGHT", 10, 0)

    -- Row 1: Icon Size
    local sizeHolder = Components.Slider(appearanceContent, {
        label = "Icon Size",
        min = 16,
        max = 128,
        value = GetCategorySettings("main").iconSize or 64,
        onChange = function(val)
            GetOrCreateCategorySettings("main").iconSize = val
            UpdateVisuals()
        end,
    })
    sizeHolder:SetPoint("TOPLEFT", framesX, framesY)
    panel.sizeSlider = sizeHolder.slider
    panel.sizeValue = sizeHolder.valueText
    framesY = framesY - 24

    -- Row 2: Spacing
    local spacingHolder = Components.Slider(appearanceContent, {
        label = "Spacing",
        min = 0,
        max = 50,
        value = math.floor((GetCategorySettings("main").spacing or 0.2) * 100),
        suffix = "%",
        onChange = function(val)
            GetOrCreateCategorySettings("main").spacing = val / 100
            if testMode then
                RefreshTestDisplay()
            else
                UpdateDisplay()
            end
        end,
    })
    spacingHolder:SetPoint("TOPLEFT", framesX, framesY)
    panel.spacingSlider = spacingHolder.slider
    panel.spacingValue = spacingHolder.valueText
    framesY = framesY - 24

    -- Row 3: Icon Zoom
    local zoomHolder = Components.Slider(appearanceContent, {
        label = "Icon Zoom",
        min = 0,
        max = 15,
        value = GetCategorySettings("main").iconZoom or DEFAULT_ICON_ZOOM,
        suffix = "%",
        onChange = function(val)
            GetOrCreateCategorySettings("main").iconZoom = val
            UpdateVisuals()
        end,
    })
    zoomHolder:SetPoint("TOPLEFT", framesX, framesY)
    panel.zoomSlider = zoomHolder.slider
    panel.zoomValue = zoomHolder.valueText
    framesY = framesY - 24

    -- Row 4: Border Size
    local borderHolder = Components.Slider(appearanceContent, {
        label = "Border Size",
        min = 0,
        max = 8,
        value = GetCategorySettings("main").borderSize or DEFAULT_BORDER_SIZE,
        suffix = "px",
        onChange = function(val)
            GetOrCreateCategorySettings("main").borderSize = val
            UpdateVisuals()
        end,
    })
    borderHolder:SetPoint("TOPLEFT", framesX, framesY)
    panel.borderSlider = borderHolder.slider
    panel.borderValue = borderHolder.valueText
    framesY = framesY - 24

    -- Row 5: Direction buttons
    local mainDirHolder = Components.DirectionButtons(appearanceContent, {
        selected = GetCategorySettings("main").growDirection or "CENTER",
        onChange = function(dir)
            GetOrCreateCategorySettings("main").growDirection = dir
            if testMode then
                RefreshTestDisplay()
            else
                UpdateDisplay()
            end
        end,
    })
    mainDirHolder:SetPoint("TOPLEFT", framesX, framesY)
    panel.growBtns = mainDirHolder.buttons

    -- Wire up the Reset button handler now that sliders exist
    mainResetBtn:SetScript("OnClick", function()
        local db = BuffRemindersDB
        db.categorySettings = db.categorySettings or {}
        db.categorySettings.main = {
            position = defaults.categorySettings.main.position,
            iconSize = defaults.categorySettings.main.iconSize,
            spacing = defaults.categorySettings.main.spacing,
            growDirection = defaults.categorySettings.main.growDirection,
            iconZoom = defaults.categorySettings.main.iconZoom,
            borderSize = defaults.categorySettings.main.borderSize,
        }
        -- Update sliders
        sizeHolder:SetValue(defaults.categorySettings.main.iconSize)
        spacingHolder:SetValue(defaults.categorySettings.main.spacing * 100)
        zoomHolder:SetValue(defaults.categorySettings.main.iconZoom)
        borderHolder:SetValue(defaults.categorySettings.main.borderSize)
        mainDirHolder:SetDirection(defaults.categorySettings.main.growDirection)
        -- Reset position (update both legacy and new locations)
        db.position = {
            point = defaults.categorySettings.main.position.point,
            x = defaults.categorySettings.main.position.x,
            y = defaults.categorySettings.main.position.y,
        }
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(
            defaults.categorySettings.main.position.point,
            UIParent,
            defaults.categorySettings.main.position.point,
            defaults.categorySettings.main.position.x,
            defaults.categorySettings.main.position.y
        )
        UpdateVisuals()
    end)

    framesY = framesY - 24 - SECTION_SPACING

    -- ========== SECTION: CATEGORIES ==========
    _, framesY = CreateSectionHeader(appearanceContent, "Categories", framesX, framesY)

    -- Capture this Y position for the UpdateCategoryLayout closure
    local categoriesStartY = framesY

    local CATEGORY_LABELS_FULL = {
        raid = "Raid Buffs",
        presence = "Presence Buffs",
        targeted = "Targeted Buffs",
        self = "Self Buffs",
        consumable = "Consumables",
        custom = "Custom Buffs",
    }

    -- Store category row data for refresh
    panel.categoryRows = {}

    -- Create expandable category row
    local function CreateCategoryRow(category, labelText, yPos)
        local rowData = {}
        rowData.category = category

        -- Main row frame
        local rowFrame = CreateFrame("Frame", nil, appearanceContent)
        rowFrame:SetSize(PANEL_WIDTH - COL_PADDING * 2, 22)
        rowFrame:SetPoint("TOPLEFT", framesX, yPos)
        rowData.rowFrame = rowFrame

        -- Category label
        local catLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        catLabel:SetPoint("LEFT", 0, 0)
        catLabel:SetWidth(100)
        catLabel:SetJustifyH("LEFT")
        catLabel:SetText(labelText)

        -- Split checkbox
        local splitCb = CreateFrame("CheckButton", nil, rowFrame, "UICheckButtonTemplate")
        splitCb:SetSize(20, 20)
        splitCb:SetPoint("LEFT", catLabel, "RIGHT", 10, 0)
        splitCb:SetChecked(IsCategorySplit(category))
        SetupTooltip(
            splitCb,
            "Split to Own Frame",
            "When enabled, this category's buffs will be displayed in a separate, independently movable frame with its own appearance settings.",
            "ANCHOR_TOP"
        )
        rowData.splitCheckbox = splitCb

        local splitLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        splitLabel:SetPoint("LEFT", splitCb, "RIGHT", 2, 0)
        splitLabel:SetText("Split")

        -- Expand/collapse arrow (only shows when split)
        local expandBtn = CreateFrame("Button", nil, rowFrame)
        expandBtn:SetSize(16, 16)
        expandBtn:SetPoint("LEFT", splitLabel, "RIGHT", 8, 0)
        expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
        expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
        expandBtn:Hide()
        rowData.expandBtn = expandBtn
        rowData.expanded = false

        -- Settings container (hidden by default)
        local settingsFrame = CreateFrame("Frame", nil, appearanceContent)
        settingsFrame:SetSize(PANEL_WIDTH - COL_PADDING * 2 - 20, 134)
        settingsFrame:SetPoint("TOPLEFT", framesX + 20, yPos - 22)
        settingsFrame:Hide()
        rowData.settingsFrame = settingsFrame

        -- Settings background (subtle indent)
        local settingsBg = settingsFrame:CreateTexture(nil, "BACKGROUND")
        settingsBg:SetAllPoints()
        settingsBg:SetColorTexture(0.15, 0.15, 0.15, 0.5)

        -- Settings content
        local setY = -4
        local setX = 4

        -- Icon Size slider
        local catSizeHolder = Components.Slider(settingsFrame, {
            label = "Icon Size",
            min = 16,
            max = 128,
            value = GetCategorySettings(category).iconSize or 64,
            onChange = function(val)
                GetOrCreateCategorySettings(category).iconSize = val
                UpdateVisuals()
            end,
        })
        catSizeHolder:SetPoint("TOPLEFT", setX, setY)
        rowData.sizeSlider = catSizeHolder.slider
        rowData.sizeHolder = catSizeHolder
        setY = setY - 24

        -- Spacing slider
        local catSpacingHolder = Components.Slider(settingsFrame, {
            label = "Spacing",
            min = 0,
            max = 50,
            value = math.floor((GetCategorySettings(category).spacing or 0.2) * 100),
            suffix = "%",
            onChange = function(val)
                GetOrCreateCategorySettings(category).spacing = val / 100
                if testMode then
                    RefreshTestDisplay()
                else
                    UpdateDisplay()
                end
            end,
        })
        catSpacingHolder:SetPoint("TOPLEFT", setX, setY)
        rowData.spacingSlider = catSpacingHolder.slider
        rowData.spacingHolder = catSpacingHolder
        setY = setY - 24

        -- Icon Zoom slider
        local catZoomHolder = Components.Slider(settingsFrame, {
            label = "Icon Zoom",
            min = 0,
            max = 15,
            value = GetCategorySettings(category).iconZoom or DEFAULT_ICON_ZOOM,
            suffix = "%",
            onChange = function(val)
                GetOrCreateCategorySettings(category).iconZoom = val
                UpdateVisuals()
            end,
        })
        catZoomHolder:SetPoint("TOPLEFT", setX, setY)
        rowData.zoomSlider = catZoomHolder.slider
        rowData.zoomHolder = catZoomHolder
        setY = setY - 24

        -- Border Size slider
        local catBorderHolder = Components.Slider(settingsFrame, {
            label = "Border Size",
            min = 0,
            max = 8,
            value = GetCategorySettings(category).borderSize or DEFAULT_BORDER_SIZE,
            suffix = "px",
            onChange = function(val)
                GetOrCreateCategorySettings(category).borderSize = val
                UpdateVisuals()
            end,
        })
        catBorderHolder:SetPoint("TOPLEFT", setX, setY)
        rowData.borderSlider = catBorderHolder.slider
        rowData.borderHolder = catBorderHolder
        setY = setY - 24

        -- Direction buttons
        local catDirHolder = Components.DirectionButtons(settingsFrame, {
            selected = GetCategorySettings(category).growDirection or "CENTER",
            onChange = function(dir)
                GetOrCreateCategorySettings(category).growDirection = dir
                if testMode then
                    RefreshTestDisplay()
                else
                    UpdateDisplay()
                end
            end,
        })
        catDirHolder:SetPoint("TOPLEFT", setX, setY)
        rowData.growBtns = catDirHolder.buttons
        rowData.dirHolder = catDirHolder

        -- Reset button on the top row (right-aligned)
        local catResetBtn = CreateButton(rowFrame, "Reset", function()
            local db = BuffRemindersDB
            db.categorySettings = db.categorySettings or {}
            local catDefaults = defaults.categorySettings[category]
            db.categorySettings[category] = {
                position = catDefaults.position,
                iconSize = catDefaults.iconSize,
                spacing = catDefaults.spacing,
                growDirection = catDefaults.growDirection,
                iconZoom = catDefaults.iconZoom,
                borderSize = catDefaults.borderSize,
            }
            -- Update sliders
            catSizeHolder:SetValue(catDefaults.iconSize)
            catSpacingHolder:SetValue(catDefaults.spacing * 100)
            catZoomHolder:SetValue(catDefaults.iconZoom)
            catBorderHolder:SetValue(catDefaults.borderSize)
            catDirHolder:SetDirection(catDefaults.growDirection)
            -- Reset position if frame exists
            if categoryFrames and categoryFrames[category] then
                local frame = categoryFrames[category]
                frame:ClearAllPoints()
                frame:SetPoint(
                    catDefaults.position.point,
                    UIParent,
                    catDefaults.position.point,
                    catDefaults.position.x,
                    catDefaults.position.y
                )
            end
            UpdateVisuals()
        end, {
            title = "Reset " .. labelText,
            desc = "Reset all " .. labelText:lower() .. " settings to defaults",
        })
        catResetBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -30, 0)
        rowData.resetBtn = catResetBtn

        -- Function to update row layout
        local function UpdateRowLayout()
            local isSplit = splitCb:GetChecked()
            if isSplit then
                expandBtn:Show()
                if rowData.expanded then
                    expandBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
                    settingsFrame:Show()
                else
                    expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
                    settingsFrame:Hide()
                end
            else
                expandBtn:Hide()
                settingsFrame:Hide()
                rowData.expanded = false
            end
        end
        rowData.UpdateLayout = UpdateRowLayout

        -- Split checkbox handler
        splitCb:SetScript("OnClick", function(self)
            local db = BuffRemindersDB
            db.splitCategories = db.splitCategories or {}
            db.splitCategories[category] = self:GetChecked()
            if self:GetChecked() then
                rowData.expanded = true
            end
            UpdateRowLayout()
            panel.UpdateCategoryLayout()
            ReparentBuffFrames()
            UpdateVisuals()
        end)

        -- Expand button handler
        expandBtn:SetScript("OnClick", function()
            rowData.expanded = not rowData.expanded
            UpdateRowLayout()
            panel.UpdateCategoryLayout()
        end)

        -- Function to refresh values
        rowData.RefreshValues = function()
            local catSettings = GetCategorySettings(category)
            splitCb:SetChecked(IsCategorySplit(category))
            catSizeHolder:SetValue(catSettings.iconSize or 64)
            catSpacingHolder:SetValue((catSettings.spacing or 0.2) * 100)
            catZoomHolder:SetValue(catSettings.iconZoom or DEFAULT_ICON_ZOOM)
            catBorderHolder:SetValue(catSettings.borderSize or DEFAULT_BORDER_SIZE)
            catDirHolder:SetDirection(catSettings.growDirection or "CENTER")
            UpdateRowLayout()
        end

        return rowData
    end

    -- Create category rows
    local categoryRowY = framesY
    for _, category in ipairs(CATEGORIES) do
        local rowData = CreateCategoryRow(category, CATEGORY_LABELS_FULL[category], categoryRowY)
        panel.categoryRows[category] = rowData
        categoryRowY = categoryRowY - 24
    end

    -- Function to recalculate layout when categories expand/collapse
    panel.UpdateCategoryLayout = function()
        local yPos = categoriesStartY
        for _, category in ipairs(CATEGORIES) do
            local rowData = panel.categoryRows[category]
            rowData.rowFrame:ClearAllPoints()
            rowData.rowFrame:SetPoint("TOPLEFT", framesX, yPos)
            yPos = yPos - 24
            if rowData.expanded and IsCategorySplit(category) then
                rowData.settingsFrame:ClearAllPoints()
                rowData.settingsFrame:SetPoint("TOPLEFT", framesX + 20, yPos)
                rowData.settingsFrame:Show()
                yPos = yPos - 134
            else
                rowData.settingsFrame:Hide()
            end
        end
        panel.categoriesEndY = yPos
        panel.UpdateAppearanceContentHeight()
    end

    -- Initial category end Y position
    panel.categoriesEndY = categoryRowY

    -- ========== SETTINGS TAB CONTENT ==========
    local settingsY = 0
    local settingsX = COL_PADDING

    -- ========== SECTION: DISPLAY ==========
    _, settingsY = CreateSectionHeader(settingsContent, "Display", settingsX, settingsY)

    local reminderCb
    reminderCb, settingsY = CreateCheckbox(
        settingsContent,
        settingsX,
        settingsY,
        'Show "BUFF!" reminder text',
        BuffRemindersDB.showBuffReminder ~= false,
        function(self)
            BuffRemindersDB.showBuffReminder = self:GetChecked()
            UpdateVisuals()
        end
    )
    panel.reminderCheckbox = reminderCb

    settingsY = settingsY - SECTION_SPACING

    -- ========== SECTION: BEHAVIOR ==========
    _, settingsY = CreateSectionHeader(settingsContent, "Behavior", settingsX, settingsY)

    local behaviorContainer = CreateFrame("Frame", nil, settingsContent)
    behaviorContainer:SetSize(PANEL_WIDTH - COL_PADDING * 2, 160)
    behaviorContainer:SetPoint("TOPLEFT", settingsX, settingsY)
    panel.behaviorContainer = behaviorContainer

    local behY = 0

    -- Informational note about buff tracking
    local trackingNote = behaviorContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    trackingNote:SetPoint("TOPLEFT", 0, behY)
    trackingNote:SetWidth(PANEL_WIDTH - COL_PADDING * 2 - 18)
    trackingNote:SetJustifyH("LEFT")
    trackingNote:SetText("Buff counts and buff providers are tracked only for alive, connected, and visible allies.")

    -- Add info icon for open world faction details
    local trackingInfoIcon = behaviorContainer:CreateTexture(nil, "ARTWORK")
    trackingInfoIcon:SetSize(14, 14)
    trackingInfoIcon:SetPoint("TOPLEFT", PANEL_WIDTH - COL_PADDING * 2 - 14, behY)
    trackingInfoIcon:SetAtlas("QuestNormal")
    local trackingInfoBtn = CreateFrame("Button", nil, behaviorContainer)
    trackingInfoBtn:SetSize(14, 14)
    trackingInfoBtn:SetPoint("CENTER", trackingInfoIcon, "CENTER", 0, 0)
    trackingInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open World vs Instances", 1, 0.82, 0)
        GameTooltip:AddLine(
            "In open world, opposing faction players are not counted as allies. In dungeons and raids, all group members are allied and counted normally.",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    trackingInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    behY = behY - 18

    local groupCb, instanceCb
    groupCb, behY = CreateCheckbox(
        behaviorContainer,
        0,
        behY,
        "Show only in group/raid",
        BuffRemindersDB.showOnlyInGroup ~= false,
        function(self)
            BuffRemindersDB.showOnlyInGroup = self:GetChecked()
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

    instanceCb, behY = CreateCheckbox(
        behaviorContainer,
        20,
        behY,
        "Only in instance",
        BuffRemindersDB.showOnlyInInstance,
        function(self)
            BuffRemindersDB.showOnlyInInstance = self:GetChecked()
            UpdateDisplay()
        end
    )
    SetCheckboxEnabled(instanceCb, BuffRemindersDB.showOnlyInGroup)
    panel.instanceCheckbox = instanceCb

    local readyCheckCb
    readyCheckCb, behY = CreateCheckbox(
        behaviorContainer,
        0,
        behY,
        "Show only on ready check",
        BuffRemindersDB.showOnlyOnReadyCheck,
        function(self)
            BuffRemindersDB.showOnlyOnReadyCheck = self:GetChecked()
            if panel.readyCheckHolder then
                panel.readyCheckHolder:SetEnabled(self:GetChecked())
            end
            UpdateDisplay()
        end
    )
    panel.readyCheckCheckbox = readyCheckCb

    local readyCheckHolder = Components.Slider(behaviorContainer, {
        label = "Duration",
        min = 10,
        max = 30,
        value = BuffRemindersDB.readyCheckDuration or 15,
        suffix = "s",
        onChange = function(val)
            BuffRemindersDB.readyCheckDuration = val
        end,
    })
    readyCheckHolder:SetPoint("TOPLEFT", 20, behY)
    readyCheckHolder:SetEnabled(BuffRemindersDB.showOnlyOnReadyCheck)
    panel.readyCheckSlider = readyCheckHolder.slider
    panel.readyCheckSliderValue = readyCheckHolder.valueText
    panel.readyCheckHolder = readyCheckHolder
    behY = behY - 24

    local playerClassCb
    playerClassCb, behY = CreateCheckbox(
        behaviorContainer,
        0,
        behY,
        "Show only my class buffs",
        BuffRemindersDB.showOnlyPlayerClassBuff,
        function(self)
            BuffRemindersDB.showOnlyPlayerClassBuff = self:GetChecked()
            UpdateDisplay()
        end,
        "Only show buffs that your class can provide (e.g., warriors will only see Battle Shout)"
    )
    panel.playerClassCheckbox = playerClassCb

    local playerMissingCb
    playerMissingCb, behY = CreateCheckbox(
        behaviorContainer,
        0,
        behY,
        "Show only buffs I'm missing",
        BuffRemindersDB.showOnlyPlayerMissing,
        function(self)
            BuffRemindersDB.showOnlyPlayerMissing = self:GetChecked()
            UpdateDisplay()
        end,
        "Only show buffs that you personally are missing, instead of showing group buff coverage (e.g., 17/20)"
    )
    panel.playerMissingCheckbox = playerMissingCb

    -- EXPERIMENTAL label for glow fallback
    local experimentalLabel = behaviorContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    experimentalLabel:SetPoint("TOPLEFT", 0, behY - 8)
    experimentalLabel:SetText("EXPERIMENTAL")
    experimentalLabel:SetTextColor(1, 0.5, 0) -- Orange color
    behY = behY - 18

    local glowFallbackCb
    glowFallbackCb, behY = CreateCheckbox(
        behaviorContainer,
        0,
        behY,
        "Show own raid buff during M+",
        BuffRemindersDB.useGlowFallback == true,
        function(self)
            BuffRemindersDB.useGlowFallback = self:GetChecked()
            UpdateFallbackDisplay()
        end,
        "Uses WoW's action bar glow to detect when someone needs your raid buff, in Mythic+ where normal tracking is disabled.\n\nRequires the spell to be on your action bars."
    )
    panel.glowFallbackCheckbox = glowFallbackCb

    local behaviorHeight = math.abs(behY) + 10
    behaviorContainer:SetHeight(behaviorHeight)
    settingsY = settingsY - behaviorHeight - SECTION_SPACING

    -- ========== SECTION: EXPIRATION WARNING ==========
    _, settingsY = CreateSectionHeader(settingsContent, "Expiration Warning", settingsX, settingsY)

    local expirationContainer = CreateFrame("Frame", nil, settingsContent)
    expirationContainer:SetSize(PANEL_WIDTH - COL_PADDING * 2, 100)
    expirationContainer:SetPoint("TOPLEFT", settingsX, settingsY)
    panel.expirationContainer = expirationContainer

    local expY = 0

    local glowCb
    glowCb, expY = CreateCheckbox(
        expirationContainer,
        0,
        expY,
        "Show glow when expiring",
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

    local thresholdHolder = Components.Slider(expirationContainer, {
        label = "Threshold",
        min = 1,
        max = 15,
        value = BuffRemindersDB.expirationThreshold or 5,
        suffix = " min",
        onChange = function(val)
            BuffRemindersDB.expirationThreshold = val
            if testMode then
                RefreshTestDisplay()
            else
                UpdateDisplay()
            end
        end,
    })
    thresholdHolder:SetPoint("TOPLEFT", 0, expY)
    panel.thresholdSlider = thresholdHolder.slider
    panel.thresholdValue = thresholdHolder.valueText
    panel.thresholdHolder = thresholdHolder
    expY = expY - 24

    -- Style dropdown - build options from GlowStyles
    local styleOptions = {}
    for i, style in ipairs(GlowStyles) do
        styleOptions[i] = { label = style.name, value = i }
    end

    local styleHolder = Components.Dropdown(expirationContainer, {
        label = "Style:",
        options = styleOptions,
        selected = BuffRemindersDB.glowStyle or 1,
        width = 100,
        onChange = function(val)
            BuffRemindersDB.glowStyle = val
            if testMode then
                RefreshTestDisplay()
            else
                UpdateDisplay()
            end
        end,
    }, "BuffRemindersStyleDropdown")
    styleHolder:SetPoint("TOPLEFT", 0, expY)
    panel.styleHolder = styleHolder

    local previewBtn = CreateButton(expirationContainer, "Preview", function()
        ShowGlowDemo()
    end)
    previewBtn:SetPoint("LEFT", styleHolder, "RIGHT", 5, 0)
    panel.previewBtn = previewBtn

    -- Helper to enable/disable glow-related controls
    local function SetGlowControlsEnabled(enabled)
        if panel.thresholdHolder then
            panel.thresholdHolder:SetEnabled(enabled)
        end
        if panel.styleHolder then
            panel.styleHolder:SetEnabled(enabled)
        end
        previewBtn:SetEnabled(enabled)
    end
    panel.SetGlowControlsEnabled = SetGlowControlsEnabled
    SetGlowControlsEnabled(BuffRemindersDB.showExpirationGlow)

    expY = expY - 28
    local expirationHeight = math.abs(expY) + 20
    expirationContainer:SetHeight(expirationHeight)

    -- Set settings content height
    settingsY = settingsY - expirationHeight
    local settingsHeight = math.abs(settingsY) + 20
    settingsContent:SetHeight(settingsHeight)

    -- Function to update layout when categories expand/collapse
    panel.UpdateAppearanceContentHeight = function()
        -- Update total content height based on categories
        local totalHeight = math.abs(panel.categoriesEndY) + 40
        appearanceContent:SetHeight(totalHeight)
    end

    -- Set initial appearance content height
    appearanceContent:SetHeight(math.abs(panel.categoriesEndY) + 40)

    -- Content height for bottom buttons positioning (use tallest tab)
    local contentHeight = math.max(buffsContent:GetHeight(), appearanceContent:GetHeight(), settingsHeight)

    -- ========== CUSTOM BUFFS CONTENT ==========
    panel.customBuffRows = {}

    -- Header with visibility toggles
    local customY = 0
    local customHeader = Components.CategoryHeader(
        customContent,
        { text = "Custom Buffs", category = "custom" },
        OnCategoryVisibilityChange
    )
    customHeader:SetPoint("TOPLEFT", COL_PADDING, customY)
    customY = customY - 18

    local customDesc = customContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    customDesc:SetPoint("TOPLEFT", COL_PADDING, customY)
    customDesc:SetWidth(PANEL_WIDTH - COL_PADDING * 2)
    customDesc:SetJustifyH("LEFT")
    customDesc:SetText("Track any buff by spell ID. Only checks if YOU have the buff (like Self Buffs).")

    -- Container for custom buff rows
    local customBuffsContainer = CreateFrame("Frame", nil, customContent)
    customBuffsContainer:SetPoint("TOPLEFT", COL_PADDING, customY - 14)
    customBuffsContainer:SetSize(PANEL_WIDTH - COL_PADDING * 2, 300)
    panel.customBuffsContainer = customBuffsContainer

    -- Function to render custom buff rows
    local function RenderCustomBuffRows()
        -- Clear existing rows
        for _, row in ipairs(panel.customBuffRows) do
            row:Hide()
            row:SetParent(nil)
        end
        panel.customBuffRows = {}

        local db = BuffRemindersDB
        local rowY = 0

        -- Sort custom buffs by key for consistent order
        local sortedKeys = {}
        if db.customBuffs then
            for key in pairs(db.customBuffs) do
                table.insert(sortedKeys, key)
            end
        end
        table.sort(sortedKeys)

        -- Show empty state message if no custom buffs
        if #sortedKeys == 0 then
            local emptyFrame = CreateFrame("Frame", nil, customBuffsContainer)
            emptyFrame:SetSize(300, 30)
            emptyFrame:SetPoint("TOPLEFT", 0, rowY)
            local emptyMsg = emptyFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            emptyMsg:SetPoint("TOPLEFT")
            emptyMsg:SetText("No custom buffs added yet.")
            table.insert(panel.customBuffRows, emptyFrame)
            rowY = rowY - 22
        end

        for _, key in ipairs(sortedKeys) do
            local customBuff = db.customBuffs[key]
            local row = CreateFrame("Frame", nil, customBuffsContainer)
            row:SetSize(PANEL_WIDTH - COL_PADDING * 2, ITEM_HEIGHT)
            row:SetPoint("TOPLEFT", 0, rowY)

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
            local icon = CreateBuffIcon(row, 18, GetBuffTexture(customBuff.spellID))
            icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)

            -- Name label
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            label:SetText(customBuff.name or ("Spell " .. customBuff.spellID))

            -- Class indicator (if set)
            if customBuff.class then
                local classLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                classLabel:SetPoint("LEFT", label, "RIGHT", 4, 0)
                classLabel:SetText("(" .. customBuff.class:sub(1, 3) .. ")")
            end

            -- Edit button
            local editBtn = CreateButton(row, "Edit", function()
                ShowCustomBuffModal(key, RenderCustomBuffRows)
            end)
            editBtn:SetPoint("RIGHT", row, "RIGHT", -50, 0)

            -- Delete button
            local deleteBtn = CreateButton(row, "Delete", function()
                StaticPopup_Show("BUFFREMINDERS_DELETE_CUSTOM", customBuff.name or key, nil, {
                    key = key,
                    refreshPanel = RenderCustomBuffRows,
                })
            end)
            deleteBtn:SetPoint("LEFT", editBtn, "RIGHT", 4, 0)

            table.insert(panel.customBuffRows, row)
            rowY = rowY - ITEM_HEIGHT
        end

        -- Add button
        local addBtn = CreateButton(customBuffsContainer, "+ Add Custom Buff", function()
            ShowCustomBuffModal(nil, RenderCustomBuffRows)
        end)
        addBtn:SetPoint("TOPLEFT", 0, rowY - 4)
        table.insert(panel.customBuffRows, addBtn)

        -- Update container height
        customBuffsContainer:SetHeight(math.abs(rowY) + 30)
    end

    panel.RenderCustomBuffRows = RenderCustomBuffRows
    RenderCustomBuffRows()

    -- Set custom content height
    customContent:SetHeight(contentHeight)

    -- ========== BOTTOM BUTTONS (on main panel) ==========
    local contentBottomY = CONTENT_TOP - contentHeight - 20

    -- Create a frame for the bottom section that sits above scroll content
    local bottomFrame = CreateFrame("Frame", nil, panel)
    bottomFrame:SetPoint("TOPLEFT", 0, contentBottomY + 5)
    bottomFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    bottomFrame:SetFrameLevel(panel:GetFrameLevel() + 10) -- Ensure it's above scroll content

    -- Background to mask any scroll content bleeding through
    local bottomBg = bottomFrame:CreateTexture(nil, "BACKGROUND")
    bottomBg:SetAllPoints()
    bottomBg:SetColorTexture(0.1, 0.1, 0.1, 0.95)

    -- Separator line
    local separator = bottomFrame:CreateTexture(nil, "ARTWORK")
    separator:SetSize(PANEL_WIDTH - 40, 1)
    separator:SetPoint("TOP", 0, -5)
    separator:SetColorTexture(0.5, 0.5, 0.5, 1)

    -- Button row (centered using holder frame)
    local btnHolder = CreateFrame("Frame", nil, bottomFrame)
    btnHolder:SetPoint("TOP", 0, -20)
    btnHolder:SetSize(1, 22)

    local lockBtn = CreateButton(btnHolder, BuffRemindersDB.locked and "Unlock" or "Lock", function(self)
        BuffRemindersDB.locked = not BuffRemindersDB.locked
        self:SetText(BuffRemindersDB.locked and "Unlock" or "Lock")
        DynamicResizeButton_Resize(self)
        if testMode then
            RefreshTestDisplay()
        else
            UpdateDisplay()
        end
    end, { title = "Lock/Unlock", desc = "Unlock to drag and reposition the buff frames." })
    lockBtn:SetPoint("RIGHT", btnHolder, "CENTER", -4, 0)
    panel.lockBtn = lockBtn

    local testBtn = CreateButton(btnHolder, "Test", function(self)
        local isOn = ToggleTestMode()
        self:SetText(isOn and "Stop Test" or "Test")
        DynamicResizeButton_Resize(self)
    end, {
        title = "Test icon's appearance",
        desc = "Shows ALL buffs regardless of what you selected in the buffs section.",
    })
    testBtn:SetPoint("LEFT", btnHolder, "CENTER", 4, 0)
    panel.testBtn = testBtn

    contentBottomY = contentBottomY - 30

    -- Set panel height
    local panelHeight = math.abs(contentBottomY) + 15
    panel:SetHeight(panelHeight)

    -- Set initial active tab
    SetActiveTab("buffs")

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
        RefreshBuffCheckboxes(TargetedBuffs)
        RefreshBuffCheckboxes(SelfBuffs)
        -- Refresh custom buffs section
        if optionsPanel.RenderCustomBuffRows then
            optionsPanel.RenderCustomBuffRows()
        end
        local mainSettings = GetCategorySettings("main")
        optionsPanel.sizeSlider:SetValue(mainSettings.iconSize or 64)
        optionsPanel.spacingSlider:SetValue((mainSettings.spacing or 0.2) * 100)
        optionsPanel.zoomSlider:SetValue(mainSettings.iconZoom or DEFAULT_ICON_ZOOM)
        optionsPanel.borderSlider:SetValue(mainSettings.borderSize or DEFAULT_BORDER_SIZE)
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
        if optionsPanel.styleHolder then
            optionsPanel.styleHolder:SetValue(db.glowStyle or 1)
        end
        if optionsPanel.SetGlowControlsEnabled then
            optionsPanel.SetGlowControlsEnabled(db.showExpirationGlow)
        end
        for _, btn in ipairs(optionsPanel.growBtns) do
            btn:SetEnabled(btn.direction ~= (mainSettings.growDirection or "CENTER"))
        end
        -- Refresh category rows (expandable split settings)
        if optionsPanel.categoryRows then
            for _, category in ipairs(CATEGORIES) do
                local rowData = optionsPanel.categoryRows[category]
                if rowData and rowData.RefreshValues then
                    rowData.RefreshValues()
                end
            end
            if optionsPanel.UpdateCategoryLayout then
                optionsPanel.UpdateCategoryLayout()
            end
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
    local numStyles = #GlowStyles

    local panel = CreatePanel("BuffRemindersGlowDemo", numStyles * (ICON_SIZE + SPACING) + SPACING, ICON_SIZE + 70, {
        bgColor = { 0.12, 0.08, 0.18, 0.98 },
        borderColor = { 0.6, 0.4, 0.8, 1 },
        strata = "TOOLTIP",
    })

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Glow Styles Preview")

    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

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
        border:SetPoint("TOPLEFT", -DEFAULT_BORDER_SIZE, DEFAULT_BORDER_SIZE)
        border:SetPoint("BOTTOMRIGHT", DEFAULT_BORDER_SIZE, -DEFAULT_BORDER_SIZE)
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

StaticPopupDialogs["BUFFREMINDERS_RELOAD_UI"] = {
    text = "Settings imported successfully!\nReload UI to apply changes?",
    button1 = "Reload",
    button2 = "Cancel",
    OnAccept = function()
        ReloadUI()
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

    local MODAL_WIDTH = 340
    local BASE_HEIGHT = 270
    local ROW_HEIGHT = 26
    local ADVANCED_HEIGHT = 85
    local CONTENT_LEFT = 20
    local ROWS_START_Y = -60 -- Below title and "Spell IDs:" label
    local editingBuff = existingKey and BuffRemindersDB.customBuffs[existingKey] or nil

    -- Convert existing spellID to array form for editing
    local existingSpellIDs = {}
    if editingBuff then
        if type(editingBuff.spellID) == "table" then
            for _, id in ipairs(editingBuff.spellID) do
                table.insert(existingSpellIDs, id)
            end
        else
            table.insert(existingSpellIDs, editingBuff.spellID)
        end
    end

    local modal = CreatePanel("BuffRemindersCustomBuffModal", MODAL_WIDTH, BASE_HEIGHT, {
        bgColor = { 0.1, 0.1, 0.1, 0.98 },
        borderColor = { 0.4, 0.4, 0.4, 1 },
        level = 200,
        escClose = true,
    })

    -- Forward declare for OnHide handler
    local spellRows, nameBox, missingBox

    -- Clear focus from EditBoxes when modal hides to prevent keyboard capture
    modal:SetScript("OnHide", function()
        if spellRows then
            for _, rowData in ipairs(spellRows) do
                if rowData.editBox then
                    rowData.editBox:ClearFocus()
                end
            end
        end
        if nameBox then
            nameBox:ClearFocus()
        end
        if missingBox then
            missingBox:ClearFocus()
        end
    end)

    -- Title and close button
    local title = modal:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(editingBuff and "Edit Custom Buff" or "Add Custom Buff")

    local closeBtn = CreateFrame("Button", nil, modal, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Spell IDs label
    local spellIdsLabel = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spellIdsLabel:SetPoint("TOPLEFT", CONTENT_LEFT, -40)
    spellIdsLabel:SetText("Spell IDs:")

    -- State
    spellRows = {}
    local advancedShown = false

    -- Forward declarations
    local addSpellBtn, advancedBtn, advancedText, advancedFrame
    local selectedClass

    -- Single layout function that positions everything
    local function UpdateLayout()
        local rowCount = #spellRows

        -- Position each row
        for i, rowData in ipairs(spellRows) do
            rowData.frame:ClearAllPoints()
            rowData.frame:SetPoint("TOPLEFT", modal, "TOPLEFT", CONTENT_LEFT, ROWS_START_Y - ((i - 1) * ROW_HEIGHT))
            -- Show/hide remove button
            if rowCount > 1 then
                rowData.removeBtn:Show()
            else
                rowData.removeBtn:Hide()
            end
        end

        -- Position add button below rows
        local addBtnY = ROWS_START_Y - (rowCount * ROW_HEIGHT) - 4
        addSpellBtn:ClearAllPoints()
        addSpellBtn:SetPoint("TOPLEFT", modal, "TOPLEFT", CONTENT_LEFT, addBtnY)

        -- Position advanced toggle below add button
        local advancedY = addBtnY - 26
        advancedBtn:ClearAllPoints()
        advancedBtn:SetPoint("TOPLEFT", modal, "TOPLEFT", CONTENT_LEFT, advancedY)

        -- Position advanced frame below toggle
        advancedFrame:ClearAllPoints()
        advancedFrame:SetPoint("TOPLEFT", modal, "TOPLEFT", CONTENT_LEFT, advancedY - 22)

        -- Update modal height
        local extraRows = math.max(0, rowCount - 1)
        local advancedExtra = advancedShown and ADVANCED_HEIGHT or 0
        modal:SetHeight(BASE_HEIGHT + (extraRows * ROW_HEIGHT) + advancedExtra)
    end

    -- Create a spell row
    local function CreateSpellRow(initialSpellID)
        local rowFrame = CreateFrame("Frame", nil, modal)
        rowFrame:SetSize(MODAL_WIDTH - 40, ROW_HEIGHT - 2)

        -- Edit box
        local editBox = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
        editBox:SetSize(70, 20)
        editBox:SetPoint("LEFT", 0, 0)
        editBox:SetAutoFocus(false)
        if initialSpellID then
            editBox:SetText(tostring(initialSpellID))
        end

        -- Lookup button
        local lookupBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        lookupBtn:SetSize(50, 20)
        lookupBtn:SetPoint("LEFT", editBox, "RIGHT", 5, 0)
        lookupBtn:SetText("Lookup")
        lookupBtn:SetNormalFontObject("GameFontHighlightSmall")
        lookupBtn:SetHighlightFontObject("GameFontHighlightSmall")

        -- Icon preview
        local icon = CreateBuffIcon(rowFrame, 18)
        icon:SetPoint("LEFT", lookupBtn, "RIGHT", 8, 0)
        icon:Hide()

        -- Spell name
        local nameText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        nameText:SetPoint("RIGHT", rowFrame, "RIGHT", -28, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        removeBtn:SetSize(20, 20)
        removeBtn:SetPoint("RIGHT", 0, 0)
        removeBtn:SetText("-")
        removeBtn:SetNormalFontObject("GameFontHighlightSmall")
        removeBtn:SetHighlightFontObject("GameFontHighlightSmall")
        removeBtn:Hide()

        local rowData = {
            frame = rowFrame,
            editBox = editBox,
            icon = icon,
            nameText = nameText,
            removeBtn = removeBtn,
            validated = false,
            spellID = nil,
            spellName = nil,
        }

        -- Lookup handler
        lookupBtn:SetScript("OnClick", function()
            local spellID = tonumber(editBox:GetText())
            if not spellID then
                icon:Hide()
                nameText:SetText("|cffff4d4dInvalid ID|r")
                rowData.validated, rowData.spellID, rowData.spellName = false, nil, nil
                return
            end

            local valid, name, iconID = ValidateSpellID(spellID)
            if valid then
                icon:SetTexture(iconID)
                icon:Show()
                nameText:SetText(name or "")
                rowData.validated, rowData.spellID, rowData.spellName = true, spellID, name
            else
                icon:Hide()
                nameText:SetText("|cffff4d4dNot found|r")
                rowData.validated, rowData.spellID, rowData.spellName = false, nil, nil
            end
        end)

        -- Remove handler
        removeBtn:SetScript("OnClick", function()
            for i, rd in ipairs(spellRows) do
                if rd == rowData then
                    rowData.frame:Hide()
                    table.remove(spellRows, i)
                    UpdateLayout()
                    break
                end
            end
        end)

        table.insert(spellRows, rowData)

        -- Auto-lookup if initial spell ID provided
        if initialSpellID then
            lookupBtn:GetScript("OnClick")()
        end

        return rowData
    end

    -- Add spell ID button
    addSpellBtn = CreateButton(modal, "+ Add Spell ID", function()
        CreateSpellRow(nil)
        UpdateLayout()
    end)

    -- Advanced options toggle button
    advancedBtn = CreateFrame("Button", nil, modal)
    advancedBtn:SetSize(200, 20)
    advancedText = advancedBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    advancedText:SetPoint("LEFT", 0, 0)
    advancedText:SetText("[+] Show Advanced Options")
    advancedText:SetTextColor(0.6, 0.8, 1)

    -- Advanced options frame
    advancedFrame = CreateFrame("Frame", nil, modal)
    advancedFrame:SetSize(MODAL_WIDTH - 40, ADVANCED_HEIGHT)
    advancedFrame:Hide()

    -- Advanced options content
    local advY = 0

    local nameHolder = Components.TextInput(advancedFrame, {
        label = "Display Name:",
        value = editingBuff and editingBuff.name or "",
        width = 150,
        labelWidth = 85,
    })
    nameHolder:SetPoint("TOPLEFT", 0, advY)
    nameBox = nameHolder.editBox -- Keep reference for save handler

    advY = advY - 25

    local missingHolder = Components.TextInput(advancedFrame, {
        label = "Missing Text:",
        value = editingBuff and editingBuff.missingText and editingBuff.missingText:gsub("\n", "\\n") or "",
        width = 80,
        labelWidth = 85,
    })
    missingHolder:SetPoint("TOPLEFT", 0, advY)
    missingBox = missingHolder.editBox -- Keep reference for save handler

    local missingHint = advancedFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    missingHint:SetPoint("LEFT", missingHolder, "RIGHT", 5, 0)
    missingHint:SetText("(use \\n for newline)")

    advY = advY - 25

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
    selectedClass = editingBuff and editingBuff.class or nil

    local classDropdown =
        CreateFrame("Frame", "BuffRemindersCustomClassDropdown", advancedFrame, "UIDropDownMenuTemplate")
    classDropdown:SetPoint("LEFT", classLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(classDropdown, 100)

    UIDropDownMenu_Initialize(classDropdown, function(_, level)
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
    end)
    UIDropDownMenu_SetSelectedValue(classDropdown, selectedClass)
    for _, cls in ipairs(classOptions) do
        if cls.value == selectedClass then
            UIDropDownMenu_SetText(classDropdown, cls.label)
            break
        end
    end

    -- Advanced toggle handler
    advancedBtn:SetScript("OnClick", function()
        advancedShown = not advancedShown
        if advancedShown then
            advancedText:SetText("[-] Hide Advanced Options")
            advancedFrame:Show()
        else
            advancedText:SetText("[+] Show Advanced Options")
            advancedFrame:Hide()
        end
        UpdateLayout()
    end)

    -- Error message
    local saveError = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    saveError:SetPoint("BOTTOMLEFT", 20, 42)
    saveError:SetWidth(MODAL_WIDTH - 120)
    saveError:SetJustifyH("LEFT")
    saveError:SetTextColor(1, 0.3, 0.3)

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, modal, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        modal:Hide()
    end)

    -- Save button
    local saveBtn = CreateFrame("Button", nil, modal, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, 22)
    saveBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        -- Collect validated spell IDs
        local validatedIDs = {}
        local firstName = nil
        for _, rowData in ipairs(spellRows) do
            if rowData.validated and rowData.spellID then
                table.insert(validatedIDs, rowData.spellID)
                if not firstName then
                    firstName = rowData.spellName
                end
            end
        end

        if #validatedIDs == 0 then
            saveError:SetText("Please validate at least one spell ID")
            return
        end
        saveError:SetText("")

        -- Store as single number if only one, array if multiple
        local spellIDValue = #validatedIDs == 1 and validatedIDs[1] or validatedIDs

        local key = existingKey or GenerateCustomBuffKey(spellIDValue)
        local displayName = nameBox:GetText()
        if displayName == "" then
            displayName = firstName or ("Spell " .. validatedIDs[1])
        end

        local missingTextValue = missingBox:GetText()
        if missingTextValue ~= "" then
            missingTextValue = missingTextValue:gsub("\\n", "\n")
        else
            missingTextValue = nil
        end

        local customBuff = {
            spellID = spellIDValue,
            key = key,
            name = displayName,
            missingText = missingTextValue,
            class = selectedClass,
        }

        BuffRemindersDB.customBuffs[key] = customBuff

        if not existingKey then
            CreateCustomBuffFrameRuntime(customBuff)
        else
            local frame = buffFrames[key]
            if frame then
                local texture = GetBuffTexture(spellIDValue)
                if texture then
                    frame.icon:SetTexture(texture)
                end
                frame.displayName = displayName
                frame.spellIDs = spellIDValue
            end
        end

        modal:Hide()
        if refreshPanelCallback then
            refreshPanelCallback()
        end
        UpdateDisplay()
    end)

    -- Initialize rows
    if #existingSpellIDs > 0 then
        for _, spellID in ipairs(existingSpellIDs) do
            CreateSpellRow(spellID)
        end
    else
        CreateSpellRow(nil)
    end

    -- Initial layout
    UpdateLayout()

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
            ToggleOptions()
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
