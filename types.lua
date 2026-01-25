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
---@field infoTooltip? string

---@class PersonalBuff
---@field spellID SpellID
---@field key string
---@field name string
---@field class ClassName
---@field missingText string
---@field groupId? string
---@field beneficiaryRole? RoleType
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
---@field iconByRole? table<RoleType, number>
---@field infoTooltip? string

---@class BuffGroup
---@field displayName string
---@field missingText? string

---@class CustomBuff
---@field spellID number
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
---@field isPresenceBuff? boolean
---@field isPersonalBuff? boolean
---@field isSelfBuff? boolean
---@field isCustomBuff? boolean
---@field glowTexture? Texture
---@field glowAnim? AnimationGroup
---@field glowShowing? boolean
---@field currentGlowStyle? number
