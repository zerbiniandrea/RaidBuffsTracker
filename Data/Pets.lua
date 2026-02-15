local _, BR = ...

-- ============================================================================
-- PET HELPERS MODULE
-- ============================================================================
-- Builds per-class lists of pet summon actions for expanded pet icons.
-- Each action has a spellID, icon, label, and sortOrder for display.

-- ============================================================================
-- TYPE DEFINITIONS
-- ============================================================================

---@class PetAction
---@field key string
---@field spellID number
---@field spellName string             -- Localized spell name for SecureActionButton casting
---@field icon number
---@field label string
---@field sortOrder number

---@class PetActionList : PetAction[]
---@field genericIndex? number  -- Preferred index for generic (collapsed) display mode

-- Hunter Call Pet spell IDs (Call Pet 1 through Call Pet 5)
local CALL_PET_SPELLS = { 883, 83242, 83243, 83244, 83245 }

-- Revive Pet spell ID
local REVIVE_PET = 982

-- Warlock Summon Demon flyout ID
local SUMMON_DEMON_FLYOUT = 10

---Build hunter pet actions from stable info
---@return PetAction[]?
local function BuildHunterActions()
    -- MM Hunters don't use pets unless they have Unbreakable Bond
    if BR.StateHelpers.GetPlayerSpecId() == 254 and not IsPlayerSpell(1223323) then
        return nil
    end

    local canUseExotic = IsPlayerSpell(53270) -- Exotic Beasts (BM passive)
    local actions = {}
    local order = 0

    for slotIndex, spellID in ipairs(CALL_PET_SPELLS) do
        if IsPlayerSpell(spellID) then
            local info = C_StableInfo.GetStablePetInfo(slotIndex)
            if info and info.name and info.icon and (not info.isExotic or canUseExotic) then
                order = order + 1
                actions[#actions + 1] = {
                    key = "pet_action_" .. spellID,
                    spellID = spellID,
                    spellName = C_Spell.GetSpellName(spellID),
                    icon = info.icon,
                    label = info.name,
                    sortOrder = order,
                }
            end
        end
    end

    -- Add Revive Pet at the end if the player knows it and has callable pets
    if #actions > 0 and IsPlayerSpell(REVIVE_PET) then
        order = order + 1
        local icon = C_Spell.GetSpellTexture(REVIVE_PET)
        if icon then
            actions[#actions + 1] = {
                key = "pet_action_" .. REVIVE_PET,
                spellID = REVIVE_PET,
                spellName = C_Spell.GetSpellName(REVIVE_PET),
                icon = icon,
                label = "Revive Pet",
                sortOrder = order,
            }
        end
    end

    return #actions > 0 and actions or nil
end

---Build warlock pet actions from the Summon Demon flyout
---@return PetAction[]?
local function BuildWarlockActions()
    local ok, _, _, numSlots, isKnown = pcall(GetFlyoutInfo, SUMMON_DEMON_FLYOUT)
    if not ok or not isKnown or not numSlots then
        return nil
    end

    local actions = {}
    local order = 0

    for i = 1, numSlots do
        local slotOk, spellID, _, slotIsKnown = pcall(GetFlyoutSlotInfo, SUMMON_DEMON_FLYOUT, i)
        if slotOk and spellID and slotIsKnown then
            local info = C_Spell.GetSpellInfo(spellID)
            if info then
                order = order + 1
                actions[#actions + 1] = {
                    key = "pet_action_" .. spellID,
                    spellID = spellID,
                    spellName = info.name,
                    icon = info.iconID,
                    label = info.name,
                    sortOrder = order,
                }
            end
        end
    end

    if #actions == 0 then
        return nil
    end

    -- Demonology: default to last action (Felguard) in generic mode
    if BR.StateHelpers.GetPlayerSpecId() == 266 then
        actions.genericIndex = #actions
    end

    return actions
end

---Build a single-action list for a given spell
---@param spellID number
---@return PetAction[]?
local function BuildSingleAction(spellID)
    if not IsPlayerSpell(spellID) then
        return nil
    end
    local info = C_Spell.GetSpellInfo(spellID)
    if not info then
        return nil
    end
    return {
        {
            key = "pet_action_" .. spellID,
            spellID = spellID,
            spellName = info.name,
            icon = info.iconID,
            label = info.name,
            sortOrder = 1,
        },
    }
end

-- Cached pet actions (rebuilt on spec/talent/stable changes, not every refresh)
local cachedActions = nil
local cacheValid = false

---Build and cache the list of pet summon actions for the given class.
---Returns cached result on subsequent calls until invalidated.
---@param class ClassName
---@return PetActionList?
local function GetPetActions(class)
    if cacheValid then
        return cachedActions
    end

    if class == "HUNTER" then
        cachedActions = BuildHunterActions()
    elseif class == "WARLOCK" then
        cachedActions = BuildWarlockActions()
    elseif class == "DEATHKNIGHT" then
        cachedActions = BuildSingleAction(46584) -- Raise Dead
    elseif class == "MAGE" then
        cachedActions = BuildSingleAction(31687) -- Summon Water Elemental
    else
        cachedActions = nil
    end

    cacheValid = true
    return cachedActions
end

---Invalidate cached pet actions (call on spec/talent/stable changes).
local function InvalidatePetActions()
    cacheValid = false
    cachedActions = nil
end

-- Export
BR.PetHelpers = {
    GetPetActions = GetPetActions,
    InvalidatePetActions = InvalidatePetActions,
}
