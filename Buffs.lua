local _, BR = ...

-- ============================================================================
-- BUFF DATA TABLES
-- ============================================================================
-- This file contains all buff definition tables.
-- Loaded after Core.lua so BR namespace is available.

---@type table<string, RaidBuff[]|PresenceBuff[]|TargetedBuff[]|SelfBuff[]|ConsumableBuff[]>
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

---@type table<string, BuffGroup>
BR.BuffGroups = {
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
