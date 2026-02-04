---@meta
-- Type definitions for LuaLS (lua-language-server)
-- This file is NOT loaded by WoW - it's only used for type checking during development

-- WoW API types (stubs)
---@class Frame
---@class Texture
---@class FontString
---@class AnimationGroup

---@alias SpellID number|number[]
---@alias ClassName "WARRIOR"|"PALADIN"|"HUNTER"|"ROGUE"|"PRIEST"|"DEATHKNIGHT"|"SHAMAN"|"MAGE"|"WARLOCK"|"MONK"|"DRUID"|"DEMONHUNTER"|"EVOKER"
---@alias RoleType "TANK"|"HEALER"|"DAMAGER"

---@class RaidBuff
---@field spellID SpellID
---@field key string
---@field name string
---@field class ClassName

---@class PresenceBuff
---@field spellID SpellID
---@field key string
---@field name string
---@field class ClassName
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
---@field infoTooltip? string

---@class SelfBuff
---@field spellID SpellID
---@field key string
---@field name string
---@field class ClassName
---@field missingText string
---@field groupId? string
---@field enchantID? number
---@field buffIdOverride? number
---@field requiresTalentSpellID? number
---@field excludeTalentSpellID? number
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

---@class BuffGroup
---@field displayName string
---@field missingText? string

---@class CustomBuff
---@field spellID SpellID
---@field key string
---@field name string
---@field missingText? string
---@field class? ClassName

---@class BuffFrame: Frame
---@field key string
---@field spellIDs SpellID
---@field displayName string
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

---@alias CategoryName "raid"|"presence"|"targeted"|"self"|"consumable"|"custom"

---@class CategoryPosition
---@field point string
---@field x number
---@field y number

---@class CategorySetting
---@field position CategoryPosition
---@field iconSize number
---@field spacing number
---@field growDirection string
---@field iconZoom number
---@field borderSize number

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
---@field editBg? Texture
---@field editBorder? Texture
---@field editLabel? FontString

---@alias SplitCategories table<CategoryName, boolean>
