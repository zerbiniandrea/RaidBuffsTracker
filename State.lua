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

-- Talent/spell knowledge cache (invalidated on PLAYER_SPECIALIZATION_CHANGED)
local cachedSpellKnowledge = {}

-- Spec ID cache (invalidated on PLAYER_SPECIALIZATION_CHANGED)
local cachedSpecId = nil

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

---Count group members with a presence buff
---Uses currentValidUnits cache built at start of refresh cycle
---@param spellIDs SpellID
---@param playerOnly? boolean Only check the player, not the group
---@return number count
---@return number? minRemaining
local function CountPresenceBuff(spellIDs, playerOnly)
    local found = 0
    local minRemaining = nil

    if playerOnly or #currentValidUnits <= 1 then
        local hasBuff, remaining = UnitHasBuff("player", spellIDs)
        if hasBuff then
            found = 1
            minRemaining = remaining
        end
        return found, minRemaining
    end

    for _, data in ipairs(currentValidUnits) do
        local hasBuff, remaining = UnitHasBuff(data.unit, spellIDs)
        if hasBuff then
            found = found + 1
            if remaining then
                if not minRemaining or remaining < minRemaining then
                    minRemaining = remaining
                end
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

---Check if player should cast their self buff or weapon imbue (returns true if missing)
---@param spellID SpellID
---@param requiredClass ClassName
---@param enchantID? number For weapon imbues, checks if this enchant is on either weapon
---@param requiresTalent? number Only show if player HAS this talent
---@param excludeTalent? number Hide if player HAS this talent
---@param buffIdOverride? number Separate buff ID to check (if different from spellID)
---@param customCheck? fun(): boolean? Custom check function for complex buff logic
---@param requireSpecId? number Only show if player's current spec matches (WoW spec ID)
---@return boolean? Returns nil if player can't/shouldn't use this buff
local function ShouldShowSelfBuff(
    spellID,
    requiredClass,
    enchantID,
    requiresTalent,
    excludeTalent,
    buffIdOverride,
    customCheck,
    requireSpecId
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

    -- Weapon imbue: check if this specific enchant is on either weapon
    if enchantID then
        return currentWeaponEnchants.mainHandID ~= enchantID and currentWeaponEnchants.offHandID ~= enchantID
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
        if currentWeaponEnchants.hasMainHand then
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

    -- Reset all entries to not visible
    for _, entry in pairs(BuffState.entries) do
        entry.visible = false
        entry.shouldGlow = false
        entry.countText = nil
        entry.missingText = nil
        entry.expiringTime = nil
    end

    -- Build valid unit cache once per refresh cycle
    BuildValidUnitCache()

    -- Fetch weapon enchant info once per refresh cycle
    local hasMain, _, _, mainID, hasOff, _, _, offID = GetWeaponEnchantInfo()
    currentWeaponEnchants.hasMainHand = hasMain or false
    currentWeaponEnchants.mainHandID = mainID
    currentWeaponEnchants.hasOffHand = hasOff or false
    currentWeaponEnchants.offHandID = offID

    local playerOnly = db.showOnlyPlayerMissing
    -- TODO: make glow truly global — currently only raid/presence buffs track time remaining,
    -- so targeted/self/consumable/custom buffs never glow. Add expiration tracking to all categories.
    local glowDefaults = db.defaults or {}
    local expirationThreshold = (glowDefaults.expirationThreshold or 15) * 60
    local showExpirationGlow = glowDefaults.showExpirationGlow ~= false

    -- Process raid buffs (coverage - need everyone to have them)
    local raidVisible = IsCategoryVisibleForContent("raid")
    for i, buff in ipairs(RaidBuffs) do
        local entry = GetOrCreateEntry(buff.key, "raid", i)
        local hasCaster = HasCasterForBuff(buff.class, buff.levelRequired)
        local showBuff = raidVisible and (not db.showOnlyPlayerClassBuff or buff.class == playerClass) and hasCaster

        if IsBuffEnabled(buff.key) and showBuff then
            local missing, total, minRemaining = CountMissingBuff(buff.spellID, buff.key, playerOnly)
            local expiringSoon = showExpirationGlow and minRemaining and minRemaining < expirationThreshold

            if missing > 0 then
                entry.visible = true
                entry.displayType = "count"
                local buffed = total - missing
                entry.countText = playerOnly and "" or (buffed .. "/" .. total)
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
        local readyCheckOnly = buff.infoTooltip and buff.infoTooltip:match("^Ready Check Only")
        local hasCaster = HasCasterForBuff(buff.class, buff.levelRequired)
        local showBuff = presenceVisible
            and (not readyCheckOnly or inReadyCheck)
            and (not db.showOnlyPlayerClassBuff or buff.class == playerClass)
            and hasCaster

        if IsBuffEnabled(buff.key) and showBuff then
            local count, minRemaining = CountPresenceBuff(buff.spellID, playerOnly)
            local expiringSoon = showExpirationGlow
                and not buff.noGlow
                and minRemaining
                and minRemaining < expirationThreshold

            if count == 0 then
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
                buff.requireSpecId
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
    for i, buff in ipairs(PetBuffs) do
        local entry = GetOrCreateEntry(buff.key, "pet", i)
        local settingKey = buff.groupId or buff.key

        if IsBuffEnabled(settingKey) and petVisible then
            local shouldShow = ShouldShowSelfBuff(
                buff.spellID,
                buff.class,
                buff.enchantID,
                buff.requiresTalentSpellID,
                buff.excludeTalentSpellID,
                buff.buffIdOverride,
                buff.customCheck,
                buff.requireSpecId
            )
            if shouldShow then
                entry.visible = true
                entry.displayType = "missing"
                entry.missingText = buff.missingText
                entry.iconByRole = buff.iconByRole
            end
        end
    end

    -- Process consumable buffs
    local consumableVisible = IsCategoryVisibleForContent("consumable")
    for i, buff in ipairs(Consumables) do
        local entry = GetOrCreateEntry(buff.key, "consumable", i)
        local settingKey = buff.groupId or buff.key

        local hasCaster = not buff.class or HasCasterForBuff(buff.class, buff.levelRequired)
        if IsBuffEnabled(settingKey) and consumableVisible and hasCaster and PassesPreChecks(buff, nil, db) then
            local shouldShow =
                ShouldShowConsumableBuff(buff.spellID, buff.buffIconID, buff.checkWeaponEnchant, buff.itemID)
            if shouldShow then
                entry.visible = true
                entry.displayType = "missing"
                entry.missingText = buff.missingText
            end
        end
    end

    -- Process custom buffs
    local customVisible = IsCategoryVisibleForContent("custom")
    if db.customBuffs then
        -- Sort keys for stable ordering (pairs() has no guaranteed order)
        local sortedKeys = {}
        for k in pairs(db.customBuffs) do
            sortedKeys[#sortedKeys + 1] = k
        end
        table.sort(sortedKeys)

        for i, k in ipairs(sortedKeys) do
            local customBuff = db.customBuffs[k]
            local entry = GetOrCreateEntry(customBuff.key, "custom", i)
            local classMatch = not customBuff.class or customBuff.class == playerClass
            local specMatch = not customBuff.specId or customBuff.specId == GetPlayerSpecId()

            if IsBuffEnabled(customBuff.key) and customVisible and classMatch and specMatch then
                local hasBuff = UnitHasBuff("player", customBuff.spellID)
                if not hasBuff then
                    entry.visible = true
                    entry.displayType = "missing"
                    entry.missingText = customBuff.missingText
                end
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

-- Export utility functions that display layer still needs
BR.StateHelpers = {
    GetPlayerSpecId = GetPlayerSpecId,
    UnitHasBuff = UnitHasBuff,
    GetGroupClasses = GetGroupClasses,
    IterateGroupMembers = IterateGroupMembers,
    IsValidGroupMember = IsValidGroupMember,
    FormatRemainingTime = FormatRemainingTime,
    GetCurrentContentType = GetCurrentContentType,
    IsCategoryVisibleForContent = IsCategoryVisibleForContent,
    GetBuffSettingKey = GetBuffSettingKey,
    IsBuffEnabled = IsBuffEnabled,
}

-- Export the module
BR.BuffState = BuffState
