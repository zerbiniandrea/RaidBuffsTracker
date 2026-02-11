local _, BR = ...

-- ============================================================================
-- BUFF STATE MODULE
-- ============================================================================
-- Pure data layer: computes "what buffs are missing" without any UI concerns.
-- Display layer subscribes to BuffStateChanged events to render.

-- Buff tables from Buffs.lua (via BR namespace)
local BUFF_TABLES = BR.BUFF_TABLES
local BuffBeneficiaries = BR.BuffBeneficiaries

-- Local aliases
local RaidBuffs = BUFF_TABLES.raid
local PresenceBuffs = BUFF_TABLES.presence
local TargetedBuffs = BUFF_TABLES.targeted
local SelfBuffs = BUFF_TABLES.self
local PetBuffs = BUFF_TABLES.pet
local Consumables = BUFF_TABLES.consumable
local CustomBuffs = BUFF_TABLES.custom

-- ============================================================================
-- MODULE STATE
-- ============================================================================

---@class BuffState
---@field entries table<string, BuffStateEntry>
---@field lastUpdate number
local BuffState = {
    entries = {},
    lastUpdate = 0,
}

-- Cache player class (set once on init via SetPlayerClass)
local playerClass = nil

-- Ready check state (set via SetReadyCheckState)
local inReadyCheck = false

-- ============================================================================
-- CACHED VALUES (invalidated by specific events)
-- ============================================================================

-- Content type cache (invalidated on PLAYER_ENTERING_WORLD)
local cachedContentType = nil

-- Difficulty cache (invalidated alongside content type)
local cachedDifficultyKey = nil

local DUNGEON_DIFFICULTY_KEYS = {
    [1] = "normal", -- Normal
    [2] = "heroic", -- Heroic
    [23] = "mythic", -- Mythic
    [8] = "mythicPlus", -- Mythic Keystone
    [24] = "timewalking", -- Timewalking
    [205] = "follower", -- Follower Dungeon
}

local RAID_DIFFICULTY_KEYS = {
    [17] = "lfr", -- Looking for Raid
    [14] = "normal", -- Normal
    [15] = "heroic", -- Heroic
    [16] = "mythic", -- Mythic
}

-- Talent/spell knowledge cache (invalidated on PLAYER_SPECIALIZATION_CHANGED)
local cachedSpellKnowledge = {}

-- Spec ID cache (invalidated on PLAYER_SPECIALIZATION_CHANGED)
local cachedSpecId = nil

-- Off-hand weapon cache (invalidated on equipment/spec change)
local cachedHasOffHandWeapon = nil

-- Weapon enchant info for current refresh cycle (set once per BuffState.Refresh())
local currentWeaponEnchants = {
    hasMainHand = false,
    mainHandID = nil,
    hasOffHand = false,
    offHandID = nil,
}

-- Valid group members for current refresh cycle (set once per BuffState.Refresh())
-- Each entry: { unit = "raid1", class = "WARRIOR", isPlayer = true }
---@type {unit: string, class: string, isPlayer: boolean}[]
local currentValidUnits = {}

-- Max level per class for current refresh cycle (players only, for caster availability checks)
---@type table<ClassName, number>
local classMaxLevels = {}

---Get the player's current spec ID (cached)
---@return number?
local function GetPlayerSpecId()
    if cachedSpecId then
        return cachedSpecId
    end
    local specIndex = GetSpecialization()
    if specIndex then
        cachedSpecId = GetSpecializationInfo(specIndex)
    end
    return cachedSpecId
end

---Check if player knows a spell (cached version of IsPlayerSpell)
---@param spellID number
---@return boolean
local function IsPlayerSpellCached(spellID)
    if cachedSpellKnowledge[spellID] ~= nil then
        return cachedSpellKnowledge[spellID]
    end
    local knows = IsPlayerSpell(spellID)
    cachedSpellKnowledge[spellID] = knows
    return knows
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

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

---Build the list of valid units for the current refresh cycle
---Called once at the start of BuffState.Refresh()
local function BuildValidUnitCache()
    currentValidUnits = {}
    classMaxLevels = {}

    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers()

    if groupSize == 0 then
        -- Solo player
        local _, class = UnitClass("player")
        table.insert(currentValidUnits, {
            unit = "player",
            class = class,
            isPlayer = true,
        })
        classMaxLevels[class] = UnitLevel("player")
        return
    end

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
            local _, class = UnitClass(unit)
            local isPlayer = UnitIsPlayer(unit)
            table.insert(currentValidUnits, {
                unit = unit,
                class = class,
                isPlayer = isPlayer,
            })
            -- Track max level per class (players only, for buff caster checks)
            if isPlayer and class then
                local level = UnitLevel(unit)
                if not classMaxLevels[class] or level > classMaxLevels[class] then
                    classMaxLevels[class] = level
                end
            end
        end
    end
end

---Check if any group member of the given class meets the level requirement
---Uses classMaxLevels cache built at start of refresh cycle
---@param requiredClass ClassName
---@param levelRequired? number
---@return boolean
local function HasCasterForBuff(requiredClass, levelRequired)
    local maxLevel = classMaxLevels[requiredClass]
    if not maxLevel then
        return false
    end
    return not levelRequired or maxLevel >= levelRequired
end

---Get classes present in the group (players only, excludes NPCs)
---Uses currentValidUnits cache built at start of refresh cycle
---@return table<ClassName, boolean>
local function GetGroupClasses()
    local classes = {}
    for _, data in ipairs(currentValidUnits) do
        -- Only count actual players as potential buffers (NPCs won't cast buffs like Skyfury)
        if data.isPlayer and data.class then
            classes[data.class] = true
        end
    end
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

---Get the effective setting key for a buff (groupId if present, otherwise individual key)
---@param buff RaidBuff|PresenceBuff|TargetedBuff|SelfBuff
---@return string
local function GetBuffSettingKey(buff)
    return buff.groupId or buff.key
end

---Check if a buff is enabled (defaults to true if not explicitly set to false)
---@param key string
---@return boolean
local function IsBuffEnabled(key)
    local db = BuffRemindersDB
    return db.enabledBuffs[key] ~= false
end

---Get the current content type based on instance/zone (cached)
---@return "openWorld"|"dungeon"|"scenario"|"raid"
local function GetCurrentContentType()
    if cachedContentType then
        return cachedContentType
    end

    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        cachedContentType = "openWorld"
    elseif instanceType == "raid" then
        cachedContentType = "raid"
    elseif instanceType == "scenario" then
        cachedContentType = "scenario"
    else
        cachedContentType = "dungeon"
    end

    return cachedContentType
end

---Get the current difficulty key (cached)
---Only caches valid keys; returns nil (retried next call) if the API returns
---an unmapped difficultyID (e.g. 0 during a loading transition).
---@return string? difficultyKey or nil if not in a dungeon/raid or unknown difficulty
local function GetCurrentDifficultyKey()
    if cachedDifficultyKey ~= nil then
        return cachedDifficultyKey
    end
    local difficultyID = select(3, GetInstanceInfo())
    local contentType = GetCurrentContentType()
    if contentType == "dungeon" then
        local key = DUNGEON_DIFFICULTY_KEYS[difficultyID]
        if key then
            cachedDifficultyKey = key
        end
        return key
    elseif contentType == "raid" then
        local key = RAID_DIFFICULTY_KEYS[difficultyID]
        if key then
            cachedDifficultyKey = key
        end
        return key
    end
    return nil
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
    if visibility[contentType] == false then
        return false
    end
    -- Check difficulty sub-filter
    local diffKey = GetCurrentDifficultyKey()
    if diffKey then
        if contentType == "dungeon" and visibility.dungeonDifficulty then
            return visibility.dungeonDifficulty[diffKey] ~= false
        elseif contentType == "raid" and visibility.raidDifficulty then
            return visibility.raidDifficulty[diffKey] ~= false
        end
    end
    return true
end

---Determine visibility and scan scope for a buff based on tracking mode.
---Raid buffs go on everyone, so "scan group" means showing coverage numbers.
---Presence buffs live on the caster, so "scan group" means finding if anyone has the aura.
---@param trackingMode string
---@param buffClass ClassName
---@param category "raid"|"presence"
---@param hasCaster boolean
---@param castOnOthers? boolean Buff exists on the target, not the caster (e.g., Soulstone)
---@return { show: boolean, playerOnly: boolean }
local function GetTrackingScope(trackingMode, buffClass, category, hasCaster, castOnOthers)
    if not hasCaster then
        return { show = false, playerOnly = false }
    end
    if trackingMode == "my_buffs" and buffClass ~= playerClass then
        return { show = false, playerOnly = false }
    end

    if trackingMode == "personal" then
        -- Presence buffs from other classes exist only on the caster, not on you.
        -- castOnOthers buffs (Soulstone) are someone else's responsibility in personal mode.
        if category == "presence" and (buffClass ~= playerClass or castOnOthers) then
            return { show = false, playerOnly = false }
        end
        return { show = true, playerOnly = true }
    elseif trackingMode == "smart" then
        local isMyClass = buffClass == playerClass
        -- Raid: scan group if I'm the caster (show coverage), just check me otherwise
        -- Presence: just check me if I'm the caster, scan group to find other casters
        --   castOnOthers: always scan group (the buff is on the target, not on me)
        if category == "raid" then
            return { show = true, playerOnly = not isMyClass }
        else
            return { show = true, playerOnly = isMyClass and not castOnOthers }
        end
    elseif trackingMode == "my_buffs" then
        -- Raid: scan group to show coverage numbers
        -- Presence: just check if my own aura is active
        --   castOnOthers: scan group (the buff is on someone else)
        return { show = true, playerOnly = category == "presence" and not castOnOthers }
    else
        -- "all" mode: always scan the full group
        return { show = true, playerOnly = false }
    end
end

-- ============================================================================
-- BUFF CHECK FUNCTIONS
-- ============================================================================

---Count group members missing a buff
---Uses currentValidUnits cache built at start of refresh cycle
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

    if playerOnly or #currentValidUnits <= 1 then
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

    for _, data in ipairs(currentValidUnits) do
        -- Check if unit's class benefits from this buff
        if not beneficiaries or beneficiaries[data.class] then
            total = total + 1
            local hasBuff, remaining = UnitHasBuff(data.unit, spellIDs)
            if not hasBuff then
                missing = missing + 1
            elseif remaining then
                if not minRemaining or remaining < minRemaining then
                    minRemaining = remaining
                end
            end
        end
    end

    return missing, total, minRemaining
end

---Check if anyone in the group has a presence buff active
---Uses currentValidUnits cache built at start of refresh cycle
---@param spellIDs SpellID
---@param playerOnly? boolean Only check the player, not the group
---@return boolean hasBuff
---@return number? minRemaining
local function HasPresenceBuff(spellIDs, playerOnly)
    if playerOnly or #currentValidUnits <= 1 then
        local hasBuff, remaining = UnitHasBuff("player", spellIDs)
        return hasBuff, remaining
    end

    local minRemaining = nil
    local found = false

    for _, data in ipairs(currentValidUnits) do
        local hasBuff, remaining = UnitHasBuff(data.unit, spellIDs)
        if hasBuff then
            found = true
            if remaining then
                if not minRemaining or remaining < minRemaining then
                    minRemaining = remaining
                end
            else
                return true, nil -- no expiration, no need to keep scanning
            end
        end
    end

    return found, minRemaining
end

---Check if player's buff is active on anyone in the group
---Uses currentValidUnits cache built at start of refresh cycle
---@param spellID number
---@param role? RoleType Only check units with this role
---@return boolean
local function IsPlayerBuffActive(spellID, role)
    for _, data in ipairs(currentValidUnits) do
        if not role or UnitGroupRolesAssigned(data.unit) == role then
            local hasBuff, _, sourceUnit = UnitHasBuff(data.unit, spellID)
            if hasBuff and sourceUnit and UnitIsUnit(sourceUnit, "player") then
                return true
            end
        end
    end
    return false
end

---Check if player should cast their targeted buff (returns true if a beneficiary needs it)
---@param spellIDs SpellID
---@param requiredClass ClassName
---@param beneficiaryRole? RoleType
---@return boolean? Returns nil if player can't provide this buff
local function ShouldShowTargetedBuff(spellIDs, requiredClass, beneficiaryRole, requireSpecId)
    if playerClass ~= requiredClass then
        return nil
    end
    if requireSpecId and GetPlayerSpecId() ~= requireSpecId then
        return nil
    end

    local spellID = (type(spellIDs) == "table" and spellIDs[1] or spellIDs) --[[@as number]]
    if not IsPlayerSpellCached(spellID) then
        return nil
    end

    -- Targeted buffs require a group (you cast them on others)
    if GetNumGroupMembers() == 0 then
        return nil
    end

    return not IsPlayerBuffActive(spellID, beneficiaryRole)
end

-- Categories where the "player knows this spell" check should be skipped.
-- Custom buffs track buffs the user *receives*, not necessarily casts.
local SKIP_SPELL_KNOWN_CATEGORIES = { custom = true }

---Check if player should cast their self buff or weapon imbue (returns true if missing)
---@param spellID SpellID
---@param requiredClass ClassName
---@param enchantID? number For weapon imbues, checks if this enchant is on either weapon
---@param requiresTalent? number Only show if player HAS this talent
---@param excludeTalent? number Hide if player HAS this talent
---@param buffIdOverride? number Separate buff ID to check (if different from spellID)
---@param customCheck? fun(): boolean? Custom check function for complex buff logic
---@param requireSpecId? number Only show if player's current spec matches (WoW spec ID)
---@param skipSpellKnownCheck? boolean Skip the "player knows spell" check (for custom buffs)
---@param requiresBuffWithEnchant? boolean When true, require both enchant AND buff (for Paladin Rites)
---@return boolean? Returns nil if player can't/shouldn't use this buff
local function ShouldShowSelfBuff(
    spellID,
    requiredClass,
    enchantID,
    requiresTalent,
    excludeTalent,
    buffIdOverride,
    customCheck,
    requireSpecId,
    skipSpellKnownCheck,
    requiresBuffWithEnchant
)
    if requiredClass and playerClass ~= requiredClass then
        return nil
    end
    if requireSpecId and GetPlayerSpecId() ~= requireSpecId then
        return nil
    end

    -- Talent checks (before spell availability check for talent-gated buffs)
    if requiresTalent and not IsPlayerSpellCached(requiresTalent) then
        return nil
    end
    if excludeTalent and IsPlayerSpellCached(excludeTalent) then
        return nil
    end

    -- Custom check function takes precedence over standard checks
    if customCheck then
        return customCheck()
    end

    -- For buffs with multiple spellIDs (like shields), check if player knows ANY of them
    -- Skip for custom buffs (they track received buffs, not cast buffs)
    if not skipSpellKnownCheck then
        ---@type number[]
        local spellIDs
        if type(spellID) == "table" then
            spellIDs = spellID
        else
            spellIDs = { spellID }
        end
        local knowsAnySpell = false
        for _, id in ipairs(spellIDs) do
            if IsPlayerSpellCached(id) then
                knowsAnySpell = true
                break
            end
        end
        if not knowsAnySpell then
            return nil
        end
    end

    -- Weapon imbue: check if this specific enchant is on either weapon
    if enchantID then
        local hasEnchant = currentWeaponEnchants.mainHandID == enchantID or currentWeaponEnchants.offHandID == enchantID

        -- For Paladin Rites: require BOTH enchant AND buff (Blizzard bug workaround)
        if requiresBuffWithEnchant then
            local hasBuff, _ = UnitHasBuff("player", buffIdOverride or spellID)
            return not (hasEnchant and hasBuff)
        end

        -- Standard enchant-only check
        return not hasEnchant
    end

    -- Regular buff check - use buffIdOverride if provided, otherwise use spellID
    local hasBuff, _ = UnitHasBuff("player", buffIdOverride or spellID)
    return not hasBuff
end

-- Icon ID for the eating channel aura (consistent across all food types)
-- Shared via BR namespace: also used by BuffReminders.lua for the display icon
BR.EATING_AURA_ICON = 133950
local EATING_AURA_ICON = BR.EATING_AURA_ICON

-- Event-driven eating state: tracked via UNIT_AURA payload, no per-render scanning.
local eatingAuraInstanceID = nil

---Check if the player is currently eating (reads cached flag, O(1))
---@return boolean
local function IsPlayerEating()
    return eatingAuraInstanceID ~= nil
end

---Full aura scan to seed eating state (call once on init / reload)
local function ScanEatingState()
    eatingAuraInstanceID = nil
    local i = 1
    local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
    while auraData do
        local ok, match = pcall(function()
            return auraData.icon == EATING_AURA_ICON
        end)
        if ok and match then
            eatingAuraInstanceID = auraData.auraInstanceID
            return
        end
        i = i + 1
        auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
    end
end

---Update eating state from UNIT_AURA payload (called on every player UNIT_AURA)
---@param updateInfo table? The updateInfo payload from UNIT_AURA
local function UpdateEatingState(updateInfo)
    if not updateInfo then
        return
    end
    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            local ok, match = pcall(function()
                return aura.icon == EATING_AURA_ICON
            end)
            if ok and match then
                eatingAuraInstanceID = aura.auraInstanceID
                break
            end
        end
    end
    if updateInfo.removedAuraInstanceIDs and eatingAuraInstanceID then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
            if id == eatingAuraInstanceID then
                eatingAuraInstanceID = nil
                break
            end
        end
    end
end

---Check if player is missing a consumable buff, weapon enchant, or inventory item (returns true if missing)
---@param spellIDs? SpellID
---@param buffIconID? number
---@param checkWeaponEnchant? boolean
---@param itemID? number|number[]
---@return boolean shouldShow
---@return number? remainingTime seconds remaining if buff is present and has a duration
local function ShouldShowConsumableBuff(spellIDs, buffIconID, checkWeaponEnchant, checkWeaponEnchantOH, itemID)
    -- Check buff auras by spell ID
    if spellIDs then
        local spellList = type(spellIDs) == "table" and spellIDs or { spellIDs }
        for _, id in ipairs(spellList) do
            local hasBuff, remaining = UnitHasBuff("player", id)
            if hasBuff then
                return false, remaining -- Has at least one of the consumable buffs
            end
        end
    end

    -- Check buff auras by icon ID (e.g., food buffs all use icon 136000)
    if buffIconID then
        local i = 1
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        while auraData do
            local success, iconMatches = pcall(function()
                return auraData.icon == buffIconID
            end)
            if success and iconMatches then
                local remaining = nil
                if auraData.expirationTime and auraData.expirationTime > 0 then
                    remaining = auraData.expirationTime - GetTime()
                end
                return false, remaining -- Has a buff with this icon
            end
            i = i + 1
            auraData = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        end
    end

    -- Check if any weapon enchant exists (oils, stones, shaman imbues, etc.)
    if checkWeaponEnchant then
        if currentWeaponEnchants.hasMainHand then
            -- GetWeaponEnchantInfo returns: hasMainHand, mainExpiration, mainCharges, mainEnchantID, ...
            local _, mainExpiration = GetWeaponEnchantInfo()
            local remaining = mainExpiration and (mainExpiration / 1000) or nil
            return false, remaining -- Has a weapon enchant
        end
    end

    -- Check if off-hand weapon enchant exists
    if checkWeaponEnchantOH then
        if currentWeaponEnchants.hasOffHand then
            local _, _, _, _, _, offExpiration = GetWeaponEnchantInfo()
            local remaining = offExpiration and (offExpiration / 1000) or nil
            return false, remaining
        end
    end

    -- Check inventory for item
    if itemID then
        local itemList = type(itemID) == "table" and itemID or { itemID }
        for _, id in ipairs(itemList) do
            local ok, count = pcall(C_Item.GetItemCount, id, false, true)
            if ok and count and count > 0 then
                return false, nil -- Has the item in inventory
            end
        end
    end

    -- If we have nothing to check, return false
    if not spellIDs and not buffIconID and not checkWeaponEnchant and not checkWeaponEnchantOH and not itemID then
        return false, nil
    end

    return true, nil -- Missing all consumable buffs/enchants/items
end

---Check if buff passes common pre-conditions
---@param buff table Any buff type with optional pre-check fields
---@param presentClasses? table<ClassName, boolean>
---@param db table Database settings
---@return boolean passes
local function PassesPreChecks(buff, presentClasses, db)
    -- Custom visibility condition
    if buff.visibilityCondition and not buff.visibilityCondition() then
        return false
    end

    -- Ready check only
    if buff.readyCheckOnly and not inReadyCheck then
        return false
    end

    -- Class filtering
    if buff.class then
        local trackingMode = db.buffTrackingMode
        if trackingMode == "my_buffs" and buff.class ~= playerClass then
            return false
        end
        if presentClasses and not presentClasses[buff.class] then
            return false
        end
    end

    -- Talent exclusion
    if buff.excludeTalentSpellID and IsPlayerSpellCached(buff.excludeTalentSpellID) then
        return false
    end

    -- Spell knowledge exclusion
    if buff.excludeIfSpellKnown then
        for _, spellID in ipairs(buff.excludeIfSpellKnown) do
            if IsPlayerSpellCached(spellID) then
                return false
            end
        end
    end

    return true
end

-- ============================================================================
-- BUFF STATE API
-- ============================================================================

---Get a single entry by key
---@param key string
---@return BuffStateEntry?
function BuffState.GetEntry(key)
    return BuffState.entries[key]
end

---Pre-built per-category lists of visible entries (populated by Refresh)
---@type table<CategoryName, BuffStateEntry[]>
BuffState.visibleByCategory = {}

---Create or update an entry
---@param key string
---@param category CategoryName
---@param sortOrder? number Position within category for display ordering
---@return BuffStateEntry
local function GetOrCreateEntry(key, category, sortOrder)
    if not BuffState.entries[key] then
        ---@type BuffStateEntry
        BuffState.entries[key] = {
            key = key,
            category = category,
            sortOrder = sortOrder or 0,
            visible = false,
            displayType = "missing",
            shouldGlow = false,
        }
    end
    return BuffState.entries[key]
end

---Recompute all buff states
function BuffState.Refresh()
    local db = BuffRemindersDB
    if not db then
        return
    end

    -- Invalidate off-hand weapon cache each refresh cycle (cheap lazy re-check)
    cachedHasOffHandWeapon = nil

    -- Reset all entries to not visible
    for _, entry in pairs(BuffState.entries) do
        entry.visible = false
        entry.shouldGlow = false
        entry.countText = nil
        entry.missingText = nil
        entry.expiringTime = nil
        entry.rebuffWarning = nil -- legacy field, still cleared for safety
        entry.isEating = nil
        entry.petActions = nil
    end

    -- Build valid unit cache once per refresh cycle
    BuildValidUnitCache()

    -- Fetch weapon enchant info once per refresh cycle
    local hasMain, _, _, mainID, hasOff, _, _, offID = GetWeaponEnchantInfo()
    currentWeaponEnchants.hasMainHand = hasMain or false
    currentWeaponEnchants.mainHandID = mainID
    currentWeaponEnchants.hasOffHand = hasOff or false
    currentWeaponEnchants.offHandID = offID

    local trackingMode = db.buffTrackingMode
    -- TODO: make glow truly global — currently only raid/presence buffs track time remaining,
    -- so targeted/self/consumable/custom buffs never glow. Add expiration tracking to all categories.
    local glowDefaults = db.defaults or {}
    local expirationThreshold = (glowDefaults.expirationThreshold or 15) * 60
    local showExpirationGlow = glowDefaults.showExpirationGlow ~= false

    -- Process raid buffs (coverage - need everyone to have them)
    local raidVisible = IsCategoryVisibleForContent("raid")
    for i, buff in ipairs(RaidBuffs) do
        local entry = GetOrCreateEntry(buff.key, "raid", i)
        local scope =
            GetTrackingScope(trackingMode, buff.class, "raid", HasCasterForBuff(buff.class, buff.levelRequired))

        if IsBuffEnabled(buff.key) and raidVisible and scope.show then
            local missing, total, minRemaining = CountMissingBuff(buff.spellID, buff.key, scope.playerOnly)
            local expiringSoon = showExpirationGlow and minRemaining and minRemaining < expirationThreshold

            if missing > 0 then
                entry.visible = true
                entry.displayType = "count"
                local buffed = total - missing
                entry.countText = scope.playerOnly and "" or (buffed .. "/" .. total)
                entry.shouldGlow = expiringSoon or false
                if expiringSoon and minRemaining then
                    entry.expiringTime = minRemaining
                end
            elseif expiringSoon and minRemaining then
                entry.visible = true
                entry.displayType = "expiring"
                entry.expiringTime = minRemaining
                entry.countText = FormatRemainingTime(minRemaining)
                entry.shouldGlow = true
            end
        end
    end

    -- Process presence buffs (need at least 1 person to have them)
    local presenceVisible = IsCategoryVisibleForContent("presence")
    for i, buff in ipairs(PresenceBuffs) do
        local entry = GetOrCreateEntry(buff.key, "presence", i)
        local scope = GetTrackingScope(
            trackingMode,
            buff.class,
            "presence",
            HasCasterForBuff(buff.class, buff.levelRequired),
            buff.castOnOthers
        )
        local showBuff = presenceVisible and (not buff.readyCheckOnly or inReadyCheck) and scope.show

        if IsBuffEnabled(buff.key) and showBuff then
            local hasBuff, minRemaining = HasPresenceBuff(buff.spellID, scope.playerOnly)
            local expiringSoon = showExpirationGlow
                and not buff.noGlow
                and minRemaining
                and minRemaining < expirationThreshold

            if not hasBuff then
                entry.visible = true
                entry.displayType = "missing"
                entry.missingText = buff.missingText
            elseif expiringSoon and minRemaining then
                entry.visible = true
                entry.displayType = "expiring"
                entry.expiringTime = minRemaining
                entry.countText = FormatRemainingTime(minRemaining)
                entry.shouldGlow = true
            end
        end
    end

    -- Process targeted buffs (player's own buff responsibility)
    local targetedVisible = IsCategoryVisibleForContent("targeted")
    for i, buff in ipairs(TargetedBuffs) do
        local entry = GetOrCreateEntry(buff.key, "targeted", i)
        local settingKey = GetBuffSettingKey(buff)

        if IsBuffEnabled(settingKey) and targetedVisible and PassesPreChecks(buff, nil, db) then
            local shouldShow =
                ShouldShowTargetedBuff(buff.spellID, buff.class, buff.beneficiaryRole, buff.requireSpecId)
            if shouldShow then
                entry.visible = true
                entry.displayType = "missing"
                entry.missingText = buff.missingText
            end
        end
    end

    -- Process self buffs (player's own buff on themselves, including weapon imbues)
    local selfVisible = IsCategoryVisibleForContent("self")
    for i, buff in ipairs(SelfBuffs) do
        local entry = GetOrCreateEntry(buff.key, "self", i)
        local settingKey = buff.groupId or buff.key

        if IsBuffEnabled(settingKey) and selfVisible then
            local shouldShow = ShouldShowSelfBuff(
                buff.spellID,
                buff.class,
                buff.enchantID,
                buff.requiresTalentSpellID,
                buff.excludeTalentSpellID,
                buff.buffIdOverride,
                buff.customCheck,
                buff.requireSpecId,
                nil, -- skipSpellKnownCheck
                buff.requiresBuffWithEnchant
            )
            if shouldShow then
                entry.visible = true
                entry.displayType = "missing"
                entry.missingText = buff.missingText
                entry.iconByRole = buff.iconByRole
            end
        end
    end

    -- Process pet buffs (pet summon reminders)
    local petVisible = IsCategoryVisibleForContent("pet")
    if BuffRemindersDB.hidePetWhileMounted ~= false and IsMounted() then
        petVisible = false
    end
    local petPassiveHidden = BuffRemindersDB.petPassiveOnlyInCombat and not UnitAffectingCombat("player")
    for i, buff in ipairs(PetBuffs) do
        local entry = GetOrCreateEntry(buff.key, "pet", i)
        local settingKey = buff.groupId or buff.key

        if IsBuffEnabled(settingKey) and petVisible and not (buff.key == "petPassive" and petPassiveHidden) then
            local shouldShow = ShouldShowSelfBuff(
                buff.spellID,
                buff.class,
                buff.enchantID,
                buff.requiresTalentSpellID,
                buff.excludeTalentSpellID,
                buff.buffIdOverride,
                buff.customCheck,
                buff.requireSpecId,
                nil, -- skipSpellKnownCheck
                buff.requiresBuffWithEnchant
            )
            if shouldShow then
                entry.visible = true
                entry.displayType = "missing"
                entry.missingText = buff.missingText
                entry.iconByRole = buff.iconByRole
                -- Expanded pet actions (individual summon spell icons)
                if buff.groupId == "pets" and BR.PetHelpers then
                    local actions = BR.PetHelpers.GetPetActions(playerClass)
                    if actions and #actions > 0 then
                        entry.petActions = actions
                    end
                end
            end
        end
    end

    -- Process consumable buffs
    local consumableVisible = IsCategoryVisibleForContent("consumable")
    local consumableGlowEnabled = BR.Config.GetCategorySetting("consumable", "showExpirationGlow") ~= false
    local consumableGlowThreshold = (BR.Config.GetCategorySetting("consumable", "expirationThreshold") or 15) * 60
    for i, buff in ipairs(Consumables) do
        local entry = GetOrCreateEntry(buff.key, "consumable", i)
        local settingKey = buff.groupId or buff.key

        local hasCaster = not buff.class or HasCasterForBuff(buff.class, buff.levelRequired)
        if IsBuffEnabled(settingKey) and consumableVisible and hasCaster and PassesPreChecks(buff, nil, db) then
            local shouldShow, remainingTime = ShouldShowConsumableBuff(
                buff.spellID,
                buff.buffIconID,
                buff.checkWeaponEnchant,
                buff.checkWeaponEnchantOH,
                buff.itemID
            )
            if shouldShow then
                entry.visible = true
                entry.displayType = "missing"
                entry.missingText = buff.missingText
            elseif consumableGlowEnabled and remainingTime and remainingTime < consumableGlowThreshold then
                -- Consumable is present but expiring soon
                entry.visible = true
                entry.displayType = "expiring"
                entry.expiringTime = remainingTime
                entry.countText = FormatRemainingTime(remainingTime)
                entry.shouldGlow = true
            end
            -- Eating state for food entries (display uses this for icon override)
            if entry.visible and buff.key == "food" then
                entry.isEating = IsPlayerEating()
            end
        end
    end

    -- Process custom buffs (user-defined, flows through ShouldShowSelfBuff like self/pet)
    local customVisible = IsCategoryVisibleForContent("custom")
    local skipSpellKnown = SKIP_SPELL_KNOWN_CATEGORIES["custom"]
    for i, buff in ipairs(CustomBuffs) do
        local entry = GetOrCreateEntry(buff.key, "custom", i)
        local settingKey = buff.groupId or buff.key

        local shouldProcess = IsBuffEnabled(settingKey) and customVisible

        -- If requireSpellKnown is true, check if player knows at least one spell
        if shouldProcess and buff.requireSpellKnown then
            local spellIDs = type(buff.spellID) == "table" and buff.spellID or { buff.spellID }
            local knowsAnySpell = false
            for _, spellID in ipairs(spellIDs) do
                if IsPlayerSpellCached(spellID) then
                    knowsAnySpell = true
                    break
                end
            end
            if not knowsAnySpell then
                shouldProcess = false
            end
        end

        if shouldProcess then
            local shouldShow = ShouldShowSelfBuff(
                buff.spellID,
                buff.class,
                buff.enchantID,
                buff.requiresTalentSpellID,
                buff.excludeTalentSpellID,
                buff.buffIdOverride,
                buff.customCheck,
                buff.requireSpecId,
                skipSpellKnown,
                buff.requiresBuffWithEnchant
            )
            local wantPresent = buff.showWhenPresent
            local show = (wantPresent and shouldShow == false) or (not wantPresent and shouldShow)
            if show then
                entry.visible = true
                entry.displayType = "missing"
                entry.missingText = buff.missingText
            end
        end
    end

    -- Build visibleByCategory in one pass from entries
    BuffState.visibleByCategory = {}
    for _, entry in pairs(BuffState.entries) do
        if entry.visible then
            local cat = entry.category
            if not BuffState.visibleByCategory[cat] then
                BuffState.visibleByCategory[cat] = {}
            end
            table.insert(BuffState.visibleByCategory[cat], entry)
        end
    end

    BuffState.lastUpdate = GetTime()

    -- Fire event so display can update
    BR.CallbackRegistry:TriggerEvent("BuffStateChanged")
end

---Set the player class (called once on init)
---@param class ClassName
function BuffState.SetPlayerClass(class)
    playerClass = class
end

---Set the ready check state
---@param state boolean
function BuffState.SetReadyCheckState(state)
    inReadyCheck = state
end

---Get the ready check state
---@return boolean
function BuffState.GetReadyCheckState()
    return inReadyCheck
end

-- ============================================================================
-- CACHE INVALIDATION
-- ============================================================================

---Invalidate content type cache (call on PLAYER_ENTERING_WORLD)
function BuffState.InvalidateContentTypeCache()
    cachedContentType = nil
    cachedDifficultyKey = nil
end

---Invalidate spec ID cache (call on PLAYER_ENTERING_WORLD, PLAYER_SPECIALIZATION_CHANGED)
function BuffState.InvalidateSpecCache()
    cachedSpecId = nil
end

---Invalidate spell knowledge cache (call on PLAYER_SPECIALIZATION_CHANGED)
function BuffState.InvalidateSpellCache()
    cachedSpellKnowledge = {}
    cachedSpecId = nil
end

---Check if off-hand slot has a weapon (cached)
---@return boolean
function BuffState.HasOffHandWeapon()
    if cachedHasOffHandWeapon == nil then
        local offhandItemID = GetInventoryItemID("player", 17) -- INVSLOT_OFFHAND
        if not offhandItemID then
            cachedHasOffHandWeapon = false
        else
            local _, _, _, _, _, itemClassID = GetItemInfoInstant(offhandItemID)
            cachedHasOffHandWeapon = itemClassID == 2 -- Enum.ItemClass.Weapon
        end
    end
    return cachedHasOffHandWeapon
end

---Invalidate off-hand weapon cache (call on PLAYER_EQUIPMENT_CHANGED, PLAYER_SPECIALIZATION_CHANGED)
function BuffState.InvalidateOffHandCache()
    cachedHasOffHandWeapon = nil
end

-- Export utility functions that display layer still needs
BR.StateHelpers = {
    GetPlayerSpecId = GetPlayerSpecId,
    UnitHasBuff = UnitHasBuff,
    GetGroupClasses = GetGroupClasses,
    IterateGroupMembers = IterateGroupMembers,
    IsValidGroupMember = IsValidGroupMember,
    FormatRemainingTime = FormatRemainingTime,
    IsPlayerEating = IsPlayerEating,
    UpdateEatingState = UpdateEatingState,
    ScanEatingState = ScanEatingState,
    GetCurrentContentType = GetCurrentContentType,
    IsCategoryVisibleForContent = IsCategoryVisibleForContent,
    GetBuffSettingKey = GetBuffSettingKey,
    IsBuffEnabled = IsBuffEnabled,
}

-- Export the module
BR.BuffState = BuffState
