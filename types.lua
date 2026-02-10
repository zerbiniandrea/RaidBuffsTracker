---@meta
-- Type definitions for LuaLS (lua-language-server)
-- This file is NOT loaded by WoW - it's only used for type checking during development

-- WoW API types (stubs with commonly used methods)
---@class Frame
---@field Show fun(self: Frame)
---@field Hide fun(self: Frame)
---@field GetWidth fun(self: Frame): number
---@field GetHeight fun(self: Frame): number

---@class Button: Frame

---@class Texture
---@field SetAllPoints fun(self: Texture, target?: any)
---@field SetTexCoord fun(self: Texture, left: number, right: number, top: number, bottom: number)
---@field SetTexture fun(self: Texture, texture: number|string)
---@field SetAtlas fun(self: Texture, atlas: string)
---@field SetSize fun(self: Texture, width: number, height: number)
---@field Show fun(self: Texture)
---@field Hide fun(self: Texture)

---@class FontString
---@field SetFont fun(self: FontString, font: string, size: number, flags?: string)
---@field SetText fun(self: FontString, text: string)
---@field Show fun(self: FontString)
---@field Hide fun(self: FontString)

---@class AnimationGroup

---@alias SpellID number|number[]
---@alias ClassName "WARRIOR"|"PALADIN"|"HUNTER"|"ROGUE"|"PRIEST"|"DEATHKNIGHT"|"SHAMAN"|"MAGE"|"WARLOCK"|"MONK"|"DRUID"|"DEMONHUNTER"|"EVOKER"
---@alias RoleType "TANK"|"HEALER"|"DAMAGER"

---@class RaidBuff
---@field spellID SpellID
---@field castSpellID? number Spell ID used for click-to-cast when different from the buff aura IDs
---@field key string
---@field name string
---@field class ClassName
---@field levelRequired? number

---@class PresenceBuff
---@field spellID SpellID
---@field key string
---@field name string
---@field class ClassName
---@field levelRequired? number
---@field missingText string
---@field groupId? string
---@field excludeTalentSpellID? number
---@field iconOverride? number
---@field infoTooltip? string
---@field noGlow? boolean

---@class TargetedBuff
---@field spellID SpellID
---@field key string
---@field name string
---@field class ClassName
---@field missingText string
---@field groupId? string
---@field beneficiaryRole? RoleType
---@field excludeTalentSpellID? number
---@field iconOverride? number
---@field requireSpecId? number
---@field infoTooltip? string

---@class SelfBuff
---@field spellID SpellID -- TODO: make optional (entries with customCheck + iconOverride don't need it)
---@field key string
---@field name string
---@field class? ClassName
---@field missingText string
---@field groupId? string
---@field enchantID? number
---@field buffIdOverride? number
---@field requireSpecId? number        -- Only show if player's current spec matches (WoW spec ID)
---@field requiresTalentSpellID? number -- TODO: rename to requiresSpellID (also used for baseline spec abilities, not just talents)
---@field excludeTalentSpellID? number -- TODO: rename to excludeSpellID
---@field iconOverride? number
---@field iconByRole? table<RoleType, number>
---@field infoTooltip? string
---@field customCheck? fun(): boolean?

---@class ConsumableBuff
---@field spellID? SpellID
---@field key string
---@field name string
---@field missingText string
---@field groupId? string
---@field checkWeaponEnchant? boolean Check if any weapon enchant exists (oils, stones, imbues)
---@field excludeIfSpellKnown? number[] Don't show if player knows any of these spells
---@field buffIconID? number Check for any buff with this icon ID (e.g., 136000 for food)
---@field displaySpellIDs? SpellID Spell IDs to show icons for in UI (subset of spellID)
---@field iconOverride? number|number[] Icon texture ID(s) to use instead of spell icon
---@field itemID? number|number[] Check if player has this item in inventory
---@field readyCheckOnly? boolean Only show during ready checks
---@field infoTooltip? string Tooltip text shown on hover (pipe-separated: title|description)
---@field visibilityCondition? fun(): boolean Custom function that gates visibility (return false to hide)

---@class BuffGroup
---@field displayName string

---@class CustomBuff
---@field spellID SpellID
---@field key string
---@field name string
---@field missingText? string
---@field class? ClassName
---@field requireSpecId? number
---@field showWhenPresent? boolean  -- Show icon when buff IS on player (default: show when missing)
---@field invertGlow? boolean       -- TODO: rename to something clearer (e.g. showWhenNotGlowing) — "invertGlow" doesn't convey the actual behavior: fallback triggers when spell is NOT glowing (default: when glowing)

---@class BuffFrame: Button
---@field key string
---@field spellIDs SpellID
---@field displayName string
---@field buffDef table
---@field icon Texture
---@field border Texture
---@field count FontString
---@field buffText? FontString
---@field testText FontString
---@field isPlayerBuff? boolean
---@field buffCategory? CategoryName
---@field glowTexture? Texture
---@field glowAnim? AnimationGroup
---@field glowShowing? boolean
---@field currentGlowStyle? number
---@field clickOverlay? Button
---@field actionButtons? Button[]
---@field extraFrames? table[]
---@field isExtraFrame? boolean
---@field mainFrame? BuffFrame

---@alias CategoryName "raid"|"presence"|"targeted"|"self"|"pet"|"consumable"|"custom"

---@class CategoryPosition
---@field point string
---@field x number
---@field y number

---@class DefaultSettings
---@field iconSize number
---@field textSize? number
---@field iconAlpha number
---@field textAlpha number
---@field textColor number[]
---@field spacing number
---@field iconZoom number
---@field borderSize number
---@field growDirection string
---@field showExpirationGlow boolean
---@field expirationThreshold number
---@field glowStyle number
---@field fontFace? string
---@field showConsumablesWithoutItems? boolean
---@field consumableRebuffWarning? boolean
---@field consumableRebuffThreshold? number
---@field consumableRebuffColor? number[]
---@field consumableDisplayMode? "icon_only"|"sub_icons"|"expanded"

---@class CategorySetting
---@field position CategoryPosition
---@field iconSize? number
---@field textSize? number
---@field iconAlpha? number
---@field textAlpha? number
---@field textColor? number[]
---@field spacing? number
---@field growDirection? string
---@field iconZoom? number
---@field borderSize? number
---@field showBuffReminder? boolean
---@field showText? boolean
---@field useCustomAppearance? boolean
---@field split? boolean
---@field clickable? boolean
---@field clickableHighlight? boolean
---@field priority? number

--- All category settings must be defined here. When adding a new category:
--- 1. Add it to CategoryName alias above
--- 2. Add a field here with the same name
---@class AllCategorySettings
---@field main CategorySetting
---@field raid CategorySetting
---@field presence CategorySetting
---@field targeted CategorySetting
---@field self CategorySetting
---@field consumable CategorySetting
---@field custom CategorySetting

---@class CategoryFrame: Frame
---@field category CategoryName

---@alias SplitCategories table<CategoryName, boolean>

---@class DungeonDifficulty
---@field normal? boolean
---@field heroic? boolean
---@field mythic? boolean
---@field mythicPlus? boolean
---@field timewalking? boolean
---@field follower? boolean

---@class RaidDifficulty
---@field lfr? boolean
---@field normal? boolean
---@field heroic? boolean
---@field mythic? boolean

---@class ContentVisibility
---@field openWorld boolean
---@field dungeon boolean
---@field scenario boolean
---@field raid boolean
---@field dungeonDifficulty? DungeonDifficulty
---@field raidDifficulty? RaidDifficulty

---@alias CategoryVisibility table<CategoryName, ContentVisibility>

---@class BuffStateEntry
---@field key string                         -- "intellect", "devotionAura", etc.
---@field category CategoryName              -- "raid", "presence", "targeted", "self", "pet", "consumable", "custom"
---@field sortOrder number                   -- Position within category for display ordering
---@field visible boolean                    -- Should show?
---@field displayType "count"|"missing"|"expiring"
---@field countText string?                  -- "17/20" for raid buffs, "5m" for expiring consumables
---@field missingText string?                -- "NO\nAURA" for non-raid
---@field expiringTime number?               -- Seconds remaining if expiring
---@field shouldGlow boolean                 -- Expiration glow?
---@field iconByRole table<RoleType,number>? -- Role-based icon override
---@field rebuffWarning boolean?             -- Consumable rebuff pulsing border?
---@field isEating boolean?                 -- Food entry: player is currently eating

---@class BuffRemindersDB
---@field dbVersion? integer

-- ============================================================================
-- UI COMPONENT CONFIG TYPES (Components.lua)
-- ============================================================================

---@class ScrollableContainerConfig
---@field contentHeight? number Initial content height (default 600)
---@field scrollbarWidth? number Width reserved for scrollbar (default 24)

---@class VerticalLayoutConfig
---@field x? number Starting X position (default 0)
---@field y? number Starting Y position (default 0)

---@class CollapsibleSectionConfig
---@field title string Header text
---@field defaultCollapsed? boolean Start collapsed (default true)
---@field width? number Optional explicit width override
---@field scrollbarOffset? number Offset to subtract from parent width (used when width not specified)
---@field onToggle? fun(expanded: boolean) Optional callback when toggled

---@class ToggleConfig
---@field label string
---@field checked? boolean
---@field get? fun(): boolean
---@field enabled? fun(): boolean
---@field onChange fun(checked: boolean)
---@field tooltip? string|table
