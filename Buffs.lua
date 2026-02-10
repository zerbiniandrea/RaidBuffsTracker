local _, BR = ...

-- ============================================================================
-- BUFF DATA TABLES
-- ============================================================================
-- This file contains all buff definition tables.
-- Loaded after Core.lua so BR namespace is available.

---Check if the player's pet is on passive stance
---@return boolean? true if pet exists and is on passive, nil otherwise
local function IsPetOnPassive()
    if not UnitExists("pet") then
        return nil
    end
    for i = 1, NUM_PET_ACTION_SLOTS do
        local name, _, _, isActive = GetPetActionInfo(i)
        if name == "PET_MODE_PASSIVE" and isActive then
            return true
        end
    end
    return nil
end

---@type table<string, RaidBuff[]|PresenceBuff[]|TargetedBuff[]|SelfBuff[]|ConsumableBuff[]|CustomBuff[]>
BR.BUFF_TABLES = {
    ---@type RaidBuff[]
    raid = {
        { spellID = { 1459, 432778 }, key = "intellect", name = "Arcane Intellect", class = "MAGE", levelRequired = 8 }, -- 432778 = NPC version
        { spellID = 6673, key = "attackPower", name = "Battle Shout", class = "WARRIOR", levelRequired = 10 },
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
            castSpellID = 364342,
            key = "bronze",
            name = "Blessing of the Bronze",
            class = "EVOKER",
            levelRequired = 30,
        },
        {
            spellID = { 1126, 432661 },
            key = "versatility",
            name = "Mark of the Wild",
            class = "DRUID",
            levelRequired = 10,
        }, -- 432661 = NPC version
        { spellID = 21562, key = "stamina", name = "Power Word: Fortitude", class = "PRIEST", levelRequired = 10 },
        { spellID = 462854, key = "skyfury", name = "Skyfury", class = "SHAMAN", levelRequired = 16 },
    },
    ---@type PresenceBuff[]
    presence = {
        {
            spellID = { 381637, 5761 },
            key = "atrophicNumbingPoison",
            name = "Atrophic/Numbing Poison",
            class = "ROGUE",
            levelRequired = 80,
            missingText = "NO\nPOISON",
        },
        {
            spellID = 465,
            key = "devotionAura",
            name = "Devotion Aura",
            class = "PALADIN",
            levelRequired = 10,
            missingText = "NO\nAURA",
        },
        {
            spellID = 20707,
            key = "soulstone",
            name = "Soulstone",
            class = "WARLOCK",
            levelRequired = 13,
            missingText = "NO\nSTONE",
            readyCheckOnly = true,
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
            requireSpecId = 65, -- Holy only
        },
        {
            spellID = 53563,
            key = "beaconOfLight",
            name = "Beacon of Light",
            class = "PALADIN",
            missingText = "NO\nLIGHT",
            groupId = "beacons",
            requireSpecId = 65, -- Holy only
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
            spellID = 360827,
            key = "blisteringScales",
            name = "Blistering Scales",
            class = "EVOKER",
            beneficiaryRole = "TANK",
            missingText = "NO\nSCALES",
            requireSpecId = 1473, -- Augmentation
            requiresTalentSpellID = 360827,
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
        -- Mage Arcane Familiar
        {
            spellID = 205022,
            buffIdOverride = 210126,
            key = "arcaneFamiliar",
            name = "Arcane Familiar",
            class = "MAGE",
            missingText = "NO\nFAMILIAR",
        },
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

                -- Count known and active poisons in each category
                local knownLethal, knownNonLethal = 0, 0
                local activeLethal, activeNonLethal = 0, 0

                for _, id in ipairs(lethalPoisons) do
                    if IsPlayerSpell(id) then
                        knownLethal = knownLethal + 1
                    end
                    local auraData
                    pcall(function()
                        auraData = C_UnitAuras.GetUnitAuraBySpellID("player", id)
                    end)
                    if auraData then
                        activeLethal = activeLethal + 1
                    end
                end

                for _, id in ipairs(nonLethalPoisons) do
                    if IsPlayerSpell(id) then
                        knownNonLethal = knownNonLethal + 1
                    end
                    local auraData
                    pcall(function()
                        auraData = C_UnitAuras.GetUnitAuraBySpellID("player", id)
                    end)
                    if auraData then
                        activeNonLethal = activeNonLethal + 1
                    end
                end

                -- Don't show if the player hasn't learned any poisons yet (e.g. low-level rogue)
                if knownLethal == 0 and knownNonLethal == 0 then
                    return nil
                end

                -- Dragon-Tempered Blades (381801): can have 2 of each
                local hasDragonTemperedBlades = IsPlayerSpell(381801)

                -- Only require as many as the player actually knows
                local requiredLethal = math.min(knownLethal, hasDragonTemperedBlades and 2 or 1)
                local requiredNonLethal = math.min(knownNonLethal, hasDragonTemperedBlades and 2 or 1)

                return activeLethal < requiredLethal or activeNonLethal < requiredNonLethal
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
            displaySpellIDs = 974, -- Earth Shield icon for group checkbox
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
            displaySpellIDs = 192106, -- Lightning Shield icon for group checkbox
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
            displaySpellIDs = 52127, -- Water Shield icon for group checkbox
            iconByRole = { HEALER = 52127, DAMAGER = 192106, TANK = 192106 },
        },
    },
    ---@type SelfBuff[]
    pet = {
        -- Pet reminders (alphabetical: Frost Mage, Hunter, Passive, Unholy DK, Warlock)
        {
            spellID = 31687, -- Summon Water Elemental (for icon)
            key = "frostMagePet",
            name = "Water Elemental",
            class = "MAGE",
            missingText = "NO\nPET",
            requireSpecId = 64, -- Frost
            requiresTalentSpellID = 31687,
            groupId = "pets",
            customCheck = function()
                return not UnitExists("pet")
            end,
        },
        {
            spellID = 883, -- Call Pet 1 (unused: customCheck bypasses spell check, iconOverride bypasses icon)
            key = "hunterPet",
            name = "Hunter Pet",
            class = "HUNTER",
            missingText = "NO\nPET",
            iconOverride = 132161,
            groupId = "pets",
            customCheck = function()
                -- MM Hunters don't use pets unless they have Unbreakable Bond
                if BR.StateHelpers.GetPlayerSpecId() == 254 and not IsPlayerSpell(1223323) then
                    return nil
                end
                return not UnitExists("pet")
            end,
        },
        {
            spellID = 0, -- No spell needed (customCheck + iconOverride)
            key = "petPassive",
            name = "Pet Passive",
            -- No class: applies to any class with a pet
            missingText = "PASSIVE\nPET",
            iconOverride = 132311,
            customCheck = IsPetOnPassive,
        },
        {
            spellID = 46584, -- Raise Dead (for icon)
            key = "unholyPet",
            name = "Unholy Ghoul",
            class = "DEATHKNIGHT",
            missingText = "NO\nPET",
            requireSpecId = 252, -- Unholy
            groupId = "pets",
            customCheck = function()
                return not UnitExists("pet")
            end,
        },
        {
            spellID = 688, -- Summon Imp (unused: customCheck bypasses spell check, iconOverride bypasses icon)
            key = "warlockPet",
            name = "Warlock Demon",
            class = "WARLOCK",
            missingText = "NO\nPET",
            iconOverride = 136082, -- Summon Demon flyout icon
            excludeTalentSpellID = 108503, -- Grimoire of Sacrifice: pet intentionally sacrificed
            groupId = "pets",
            customCheck = function()
                return not UnitExists("pet")
            end,
        },
    },
    ---@type CustomBuff[]
    custom = {},
    ---@type ConsumableBuff[]
    consumable = {
        -- Augment Rune (The War Within + Midnight)
        {
            spellID = {
                1234969, -- Ethereal Augment Rune (TWW permanent) - highest priority
                1242347, -- Soulgorged Augment Rune (TWW raid drop) - persists through death
                453250, -- Crystallized Augment Rune (TWW) - single use
                393438, -- Draconic Augment Rune (Dragonflight) - legacy
                1264426, -- Void-Touched Augment Rune (Midnight)
            },
            displaySpellIDs = { 1234969, 1242347, 453250, 393438 }, -- Show rune icons in priority order
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
        -- Delve Food (only when inside a delve with Brann or Valeera)
        {
            buffIconID = 133954,
            key = "delveFood",
            name = "Delve Food",
            missingText = "NO\nFOOD",
            groupId = "delveFood",
            iconOverride = 133954,
            infoTooltip = "Delves Only|Only shown inside delves when Brann or Valeera are in your party.",
            visibilityCondition = function()
                local inInstance, instanceType = IsInInstance()
                if not inInstance or instanceType ~= "scenario" then
                    return false
                end
                for i = 1, GetNumGroupMembers() do
                    local guid = UnitGUID("party" .. i)
                    if guid then
                        local npcID = select(6, strsplit("-", guid))
                        npcID = tonumber(npcID)
                        if npcID == 210759 or npcID == 248567 then
                            return true
                        end
                    end
                end
                return false
            end,
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
            class = "WARLOCK",
            missingText = "NO\nSTONE",
            groupId = "healthstone",
            iconOverride = 538745, -- Healthstone icon
            readyCheckOnly = true,
            infoTooltip = "Ready Check Only|This is only shown during ready checks.",
        },
    },
}

---@type table<string, BuffGroup>
BR.BuffGroups = {
    beacons = { displayName = "Beacons" },
    shamanImbues = { displayName = "Shaman Imbues" },
    paladinRites = { displayName = "Paladin Rites" },
    pets = { displayName = "Pets" },
    shamanShields = { displayName = "Shaman Shields" },
    -- Consumable groups
    flask = { displayName = "Flask" },
    food = { displayName = "Food" },
    delveFood = { displayName = "Delve Food" },
    rune = { displayName = "Augment Rune" },
    weaponBuff = { displayName = "Weapon Buff" },
    healthstone = { displayName = "Healthstone!" },
}

-- Classes that benefit from each buff (BETA: class-level only, not spec-aware)
-- nil = everyone benefits, otherwise only listed classes are counted
BR.BuffBeneficiaries = {
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
