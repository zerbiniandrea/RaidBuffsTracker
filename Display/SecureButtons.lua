local _, BR = ...

-- ============================================================================
-- SECURE BUTTONS & CLICK-TO-CAST OVERLAYS
-- Consumable action buttons (sub-icons, expanded), click-to-cast spell overlays,
-- and all secure frame positioning logic. Separated from the display layer to
-- keep combat-lockdown-sensitive code isolated.
-- ============================================================================

local GetCategorySettings = BR.Helpers.GetCategorySettings
local IsCategorySplit = BR.Helpers.IsCategorySplit

-- ============================================================================
-- SPELL HELPERS
-- ============================================================================

---Given one or more spell IDs, return the first that the player knows.
---@param spellIDs number|number[]|nil
---@return number?
local function GetCastableSpellID(spellIDs)
    if spellIDs == nil then
        return nil
    end
    if type(spellIDs) ~= "table" then
        return IsPlayerSpell(spellIDs) and spellIDs or nil
    end
    for _, id in ipairs(spellIDs) do
        if IsPlayerSpell(id) then
            return id
        end
    end
    return nil
end

-- Pre-filter a buff's spell by talent/spec requirements, then find a castable spell ID.
-- Checks excludeTalentSpellID, requiresTalentSpellID, and requireSpecId before delegating
-- to GetCastableSpellID. Returns nil if the buff is filtered out or no spell is castable.
---@param buff table The buff definition table
---@return number?
local function GetActionSpellID(buff)
    if buff.excludeTalentSpellID and IsPlayerSpell(buff.excludeTalentSpellID) then
        return nil
    end
    if buff.requiresTalentSpellID and not IsPlayerSpell(buff.requiresTalentSpellID) then
        return nil
    end
    if buff.requireSpecId then
        local spec = GetSpecialization()
        if spec then
            local specId = GetSpecializationInfo(spec)
            if specId ~= buff.requireSpecId then
                return nil
            end
        end
    end
    return GetCastableSpellID(buff.castSpellID or buff.spellID)
end

-- ============================================================================
-- CLICK-TO-CAST OVERLAY
-- ============================================================================

-- Create a SecureActionButton overlay for click-to-cast on a buff frame.
-- Parented to UIParent with NO anchors to the buff frame hierarchy, avoiding any
-- layout dependency that would make the frame hierarchy protected/secure.
-- Position is synced manually by SyncSecureButtons() after each layout pass.
---@param frame table The parent buff frame
local function CreateClickOverlay(frame)
    local overlay = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    overlay:RegisterForClicks("AnyDown", "AnyUp")
    overlay:EnableMouse(false)
    overlay:Hide()
    -- Auto-hide in combat (secure state driver), auto-show after
    RegisterStateDriver(overlay, "visibility", "[combat] hide; show")
    -- When state driver re-shows after combat, hide if buff frame isn't visible
    -- Uses IsVisible() (not IsShown()) to check entire parent chain — the frame's own
    -- shown state can be true while its parent container is hidden.
    overlay:SetScript("OnShow", function(self)
        if not frame:IsVisible() then
            self:Hide()
        end
    end)
    -- Refresh display shortly after click so the consumed buff disappears quickly
    overlay:SetScript("PostClick", function()
        C_Timer.After(0.3, function()
            if not InCombatLockdown() then
                BR.Display.Update()
            end
        end)
    end)
    overlay.highlight = overlay:CreateTexture(nil, "HIGHLIGHT")
    overlay.highlight:SetAllPoints()
    overlay.highlight:SetTexCoord(BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET, BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET)
    overlay.highlight:SetColorTexture(1, 1, 1, 0.2)
    frame.clickOverlay = overlay
end

-- ============================================================================
-- CONSUMABLE ACTION BUTTONS
-- ============================================================================

local ACTION_ICON_SCALE = 0.45
local ACTION_ICON_MIN = 18
local ACTION_ICON_OFFSET = -6

-- Quality text and colors for crafted consumables (rank 1/2/3)
local QUALITY_INFO = {
    [1] = { text = "R1", r = 0.73, g = 0.46, b = 0.26 }, -- Bronze
    [2] = { text = "R2", r = 0.75, g = 0.75, b = 0.75 }, -- Silver
    [3] = { text = "R3", r = 1.00, g = 0.82, b = 0.00 }, -- Gold
}

---Set or hide a quality pip overlay text based on crafted quality.
---@param overlay FontString The overlay text to update
---@param craftedQuality number? The crafted quality tier (1-3) or nil
---@param size number The parent icon size (used for font sizing)
local function SetQualityOverlay(overlay, craftedQuality, size)
    local info = craftedQuality and QUALITY_INFO[craftedQuality]
    if info then
        -- Scale font with icon size (minimum 8px font)
        local fontPath = BR.Display.GetFontPath()
        local fontSize = math.max(8, size * 0.25)
        overlay:SetFont(fontPath, fontSize, "OUTLINE")
        overlay:SetText(info.text)
        overlay:SetTextColor(info.r, info.g, info.b, 1)
        -- Position in top-left corner, kept inside icon boundaries
        overlay:ClearAllPoints()
        overlay:SetPoint("TOPLEFT", overlay:GetParent(), "TOPLEFT", 2, -2)
        overlay:Show()
    else
        overlay:Hide()
    end
end

---Create a small SecureActionButton for the consumable item row.
---Parented to UIParent with NO anchors to buff frames (avoids taint).
---Position synced by SyncSecureButtons().
---@return table btn The created button
local function CreateActionButton()
    local btn = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    btn:RegisterForClicks("AnyDown", "AnyUp")
    btn:Hide()
    -- Start hidden — state driver activated by SyncSecureButtons() after positioning
    RegisterStateDriver(btn, "visibility", "hide")
    -- When state driver re-shows after combat, hide if buff frame isn't visible
    -- Uses IsVisible() to check entire parent chain (see CreateClickOverlay comment)
    btn:SetScript("OnShow", function(self)
        local bf = self._br_buff_frame
        if not bf or not bf:IsVisible() then
            self:Hide()
        end
    end)
    -- Refresh display shortly after click so the consumed buff disappears quickly
    btn:SetScript("PostClick", function()
        C_Timer.After(0.3, function()
            if not InCombatLockdown() then
                BR.Display.Update()
            end
        end)
    end)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET, BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET)

    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    btn.count:SetPoint("BOTTOMRIGHT", -1, 1)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetTexCoord(BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET, BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET)
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)

    btn.qualityOverlay = btn:CreateFontString(nil, "OVERLAY")
    btn.qualityOverlay:Hide()

    return btn
end

-- Consumable item cache: only rescan bags when BAG_UPDATE_DELAYED fires
local consumableCache = {} -- key → items array (or nil)
local consumableCacheDirty = true

local function InvalidateConsumableCache()
    consumableCacheDirty = true
end

---Scan bags for all consumable categories and populate the cache.
local function RefreshConsumableCache()
    if not consumableCacheDirty then
        return
    end
    consumableCacheDirty = false

    if not C_Container or not C_Container.GetContainerNumSlots then
        wipe(consumableCache)
        return
    end

    local itemSets = BR.CONSUMABLE_ITEMS or {}
    -- Scan all bags once, bucket items by consumable category
    local buckets = {} -- category → { [itemID] = { count, icon } }
    local maxBags = NUM_BAG_SLOTS or 4
    for bag = 0, maxBags do
        local slots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, slots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then
                for category, allowedSet in pairs(itemSets) do
                    if allowedSet[itemID] and not (buckets[category] and buckets[category][itemID]) then
                        if not buckets[category] then
                            buckets[category] = {}
                        end
                        local ok, count = pcall(C_Item.GetItemCount, itemID, false, true)
                        count = (ok and count) or 0
                        if count > 0 then
                            local info = C_Container.GetContainerItemInfo(bag, slot)
                            local icon = info and info.iconFileID or nil
                            local itemLink = info and info.hyperlink
                            local cq = nil
                            if itemLink then
                                -- Parse crafted quality tier from the embedded atlas in the item link
                                -- e.g. |A:Professions-ChatIcon-Quality-Tier2:17:15::1|a → tier 2
                                local tier = tostring(itemLink):match("Professions%-ChatIcon%-Quality%-Tier(%d)")
                                if tier then
                                    cq = tonumber(tier)
                                end
                            end
                            buckets[category][itemID] = {
                                itemID = itemID,
                                count = count,
                                icon = icon,
                                craftedQuality = cq,
                            }
                        end
                    end
                end
            end
        end
    end

    -- Convert buckets to sorted arrays
    wipe(consumableCache)
    for category, entries in pairs(buckets) do
        local items = {}
        for _, item in pairs(entries) do
            items[#items + 1] = item
        end
        local allowedSet = itemSets[category]
        table.sort(items, function(a, b)
            -- If items have numeric priority values, sort by priority first (lower = better)
            local aPri = allowedSet and allowedSet[a.itemID]
            local bPri = allowedSet and allowedSet[b.itemID]
            if type(aPri) == "number" and type(bPri) == "number" and aPri ~= bPri then
                return aPri < bPri
            end
            if a.count == b.count then
                return a.itemID < b.itemID
            end
            return a.count > b.count
        end)
        consumableCache[category] = items
    end
end

-- Map buff key → CONSUMABLE_ITEMS category key
local BUFF_KEY_TO_CATEGORY = {
    flask = "flask",
    food = "food",
    rune = "rune",
    weaponBuff = "weapon",
    weaponBuffOH = "weapon",
}

---Get cached consumable items for a buff definition.
---@param buff table The buff definition table
---@return table[]? items Array of { itemID, count, icon } sorted by count desc, or nil
local function GetConsumableActionItems(buff)
    if not buff then
        return nil
    end
    local category = BUFF_KEY_TO_CATEGORY[buff.key]
    if not category then
        return nil
    end
    RefreshConsumableCache()
    local items = consumableCache[category]
    return items and #items > 0 and items or nil
end

---Create/update the item icons for a consumable buff frame.
---Sets attributes, textures, and marks buttons visible. Positioning is handled
---separately by SyncSecureButtons() (no anchors to avoid taint).
---@param frame table The buff frame
---@param actionItems table[]? Array of { itemID, count, icon }
---@param clickable boolean? Whether buttons should accept mouse input
local function UpdateConsumableButtons(frame, actionItems, clickable)
    if not actionItems or #actionItems <= 1 then
        if frame.actionButtons then
            for _, btn in ipairs(frame.actionButtons) do
                btn._br_visible = false
                btn:Hide()
            end
        end
        return
    end

    if not frame.actionButtons then
        frame.actionButtons = {}
    end

    for i, item in ipairs(actionItems) do
        local btn = frame.actionButtons[i]
        if not btn then
            btn = CreateActionButton()
            btn._br_buff_frame = frame
            frame.actionButtons[i] = btn
        end

        btn.itemID = item.itemID
        btn.icon:SetTexture(item.icon or 134400)
        btn._br_craftedQuality = item.craftedQuality

        -- Dirty tracking: skip redundant SetAttribute calls
        if btn._br_action_item ~= item.itemID then
            if frame.key == "weaponBuff" or frame.key == "weaponBuffOH" then
                local slot = frame.key == "weaponBuffOH" and 17 or 16
                btn:SetAttribute("type", "macro")
                btn:SetAttribute("macrotext", "/use item:" .. tostring(item.itemID) .. "\n/use " .. slot)
            else
                btn:SetAttribute("type", "item")
                btn:SetAttribute("item", "item:" .. tostring(item.itemID))
            end
            btn._br_action_item = item.itemID
        end

        btn:EnableMouse(clickable == true)
        btn._br_visible = true
        btn._br_count = item.count
        btn._br_needs_sync = true
    end

    -- Mark unused buttons hidden
    for i = #actionItems + 1, #frame.actionButtons do
        frame.actionButtons[i]._br_visible = false
        frame.actionButtons[i]:Hide()
    end
end

-- ============================================================================
-- SECURE FRAME SYNC
-- ============================================================================

---Get the effective category for a buff frame (split or "main")
local function GetEffectiveCategory(frame)
    if frame.buffCategory and IsCategorySplit(frame.buffCategory) then
        return frame.buffCategory
    end
    return "main"
end

-- Sync all secure button positions/sizes/visibility with their buff frames.
-- Uses screen coordinates (no anchors) so secure frames never taint the buff hierarchy.
-- Safe to call at any time; skips if in combat lockdown.
local function HideAllSecureFrames()
    for _, frame in pairs(BR.Display.frames) do
        if frame.clickOverlay then
            frame.clickOverlay:EnableMouse(false)
            frame.clickOverlay:Hide()
            frame.clickOverlay._br_left = nil
        end
        if frame.actionButtons then
            for _, btn in ipairs(frame.actionButtons) do
                if btn._br_driver_active then
                    RegisterStateDriver(btn, "visibility", "hide")
                    btn._br_driver_active = false
                    btn._br_x = nil
                else
                    btn:Hide()
                end
            end
        end
        if frame.extraFrames then
            for _, extra in ipairs(frame.extraFrames) do
                if extra.clickOverlay then
                    extra.clickOverlay:EnableMouse(false)
                    extra.clickOverlay:Hide()
                    extra.clickOverlay._br_left = nil
                end
            end
        end
    end
end

local function SyncSecureButtons()
    if InCombatLockdown() then
        return
    end
    -- Hide all clickable overlays during test mode to prevent desync
    if BR.Display.IsTestMode() then
        HideAllSecureFrames()
        return
    end
    local fontPath = BR.Display.GetFontPath()
    for _, frame in pairs(BR.Display.frames) do
        -- Sync click overlay
        local overlay = frame.clickOverlay
        if overlay then
            local cs = frame.buffCategory
                and BuffRemindersDB.categorySettings
                and BuffRemindersDB.categorySettings[frame.buffCategory]
            local clickable = cs and cs.clickable == true
            if frame:IsVisible() then
                if not clickable then
                    overlay:EnableMouse(false)
                    overlay:Hide()
                    overlay._br_left = nil
                else
                    local left, bottom, width, height = frame:GetRect()
                    if left then
                        -- Skip if position unchanged (avoids redundant ClearAllPoints/SetPoint)
                        if
                            overlay._br_left ~= left
                            or overlay._br_bottom ~= bottom
                            or overlay._br_width ~= width
                            or overlay._br_height ~= height
                        then
                            overlay:ClearAllPoints()
                            overlay:SetSize(width, height)
                            overlay:SetFrameStrata(frame:GetFrameStrata())
                            overlay:SetFrameLevel(frame:GetFrameLevel() + 5)
                            overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
                            overlay._br_left = left
                            overlay._br_bottom = bottom
                            overlay._br_width = width
                            overlay._br_height = height
                        end
                        overlay:EnableMouse(true)
                        if not overlay:IsShown() then
                            overlay:Show()
                        end
                    end
                end
            else
                overlay:Hide()
                overlay:EnableMouse(false)
                overlay._br_left = nil
            end
        end
        -- Sync action buttons (consumable item row)
        if frame.actionButtons then
            if frame:IsVisible() then
                local left, bottom, width, height = frame:GetRect()
                if left then
                    local effectiveCat = GetEffectiveCategory(frame)
                    local catSettings = GetCategorySettings(effectiveCat)
                    local consumableSettings = GetCategorySettings("consumable")
                    local size = math.max(ACTION_ICON_MIN, math.floor((catSettings.iconSize or 64) * ACTION_ICON_SCALE))
                    local btnSpacing = math.max(2, math.floor(size * 0.2))
                    local subIconSide = consumableSettings.subIconSide or "BOTTOM"
                    -- Count visible buttons
                    local visibleCount = 0
                    for _, btn in ipairs(frame.actionButtons) do
                        if btn._br_visible then
                            visibleCount = visibleCount + 1
                        end
                    end
                    if visibleCount > 0 then
                        local idx = 0
                        for _, btn in ipairs(frame.actionButtons) do
                            if btn._br_visible then
                                local btnX, btnY
                                local isSideways = subIconSide == "LEFT" or subIconSide == "RIGHT"
                                if isSideways then
                                    local maxPerCol =
                                        math.max(1, math.floor((height + btnSpacing) / (size + btnSpacing)))
                                    local row = idx % maxPerCol
                                    local col = math.floor(idx / maxPerCol)
                                    local thisColCount = math.min(maxPerCol, visibleCount - col * maxPerCol)
                                    local thisColHeight = thisColCount * size + (thisColCount - 1) * btnSpacing
                                    local thisColStartY = bottom + (height - thisColHeight) / 2
                                    if subIconSide == "LEFT" then
                                        btnX = left + ACTION_ICON_OFFSET - size - col * (size + btnSpacing)
                                    else
                                        btnX = left + width - ACTION_ICON_OFFSET + col * (size + btnSpacing)
                                    end
                                    btnY = thisColStartY + row * (size + btnSpacing)
                                else
                                    local maxPerRow =
                                        math.max(1, math.floor((width + btnSpacing) / (size + btnSpacing)))
                                    local col = idx % maxPerRow
                                    local row = math.floor(idx / maxPerRow)
                                    local thisRowCount = math.min(maxPerRow, visibleCount - row * maxPerRow)
                                    local thisRowWidth = thisRowCount * size + (thisRowCount - 1) * btnSpacing
                                    local thisRowStartX = left + (width - thisRowWidth) / 2
                                    btnX = thisRowStartX + col * (size + btnSpacing)
                                    if subIconSide == "TOP" then
                                        btnY = bottom + height - ACTION_ICON_OFFSET + row * (size + btnSpacing)
                                    else
                                        btnY = bottom + ACTION_ICON_OFFSET - size - row * (size + btnSpacing)
                                    end
                                end
                                local needsUpdate = btn._br_needs_sync
                                    or btn._br_x ~= btnX
                                    or btn._br_y ~= btnY
                                    or btn._br_size ~= size
                                if needsUpdate then
                                    -- Reposition
                                    btn:ClearAllPoints()
                                    btn:SetSize(size, size)
                                    btn:SetFrameStrata(frame:GetFrameStrata())
                                    btn:SetFrameLevel(frame:GetFrameLevel() + 4)
                                    btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", btnX, btnY)
                                    btn._br_x = btnX
                                    btn._br_y = btnY
                                    btn._br_size = size
                                    -- Update text/font (only when data or size changed)
                                    btn.count:SetText(
                                        btn._br_count and btn._br_count > 1 and tostring(btn._br_count) or ""
                                    )
                                    btn.count:SetFont(fontPath, math.max(10, math.floor(size * 0.45)), "OUTLINE")
                                    SetQualityOverlay(btn.qualityOverlay, btn._br_craftedQuality, size)
                                    btn._br_needs_sync = false
                                end
                                -- Activate combat state driver on first show (buttons start with "hide" driver)
                                if not btn._br_driver_active then
                                    RegisterStateDriver(btn, "visibility", "[combat] hide; show")
                                    btn._br_driver_active = true
                                end
                                if not btn:IsShown() then
                                    btn:Show()
                                end
                                idx = idx + 1
                            end
                        end
                    end
                    -- Hide buttons that are no longer visible
                    for _, btn in ipairs(frame.actionButtons) do
                        if not btn._br_visible and btn._br_driver_active then
                            RegisterStateDriver(btn, "visibility", "hide")
                            btn._br_driver_active = false
                            btn._br_x = nil
                        end
                    end
                end
            else
                for _, btn in ipairs(frame.actionButtons) do
                    if btn._br_driver_active then
                        RegisterStateDriver(btn, "visibility", "hide")
                        btn._br_driver_active = false
                        btn._br_x = nil
                    else
                        btn:Hide()
                    end
                end
            end
        end
        -- Sync extra frame click overlays (expanded consumable display mode)
        if frame.extraFrames then
            for _, extra in ipairs(frame.extraFrames) do
                local extraOverlay = extra.clickOverlay
                if extraOverlay then
                    if extra:IsVisible() then
                        local extraCs = frame.buffCategory
                            and BuffRemindersDB.categorySettings
                            and BuffRemindersDB.categorySettings[frame.buffCategory]
                        local extraClickable = extraCs and extraCs.clickable == true
                        if not extraClickable then
                            extraOverlay:EnableMouse(false)
                            extraOverlay:Hide()
                            extraOverlay._br_left = nil
                        else
                            local eLeft, eBottom, eWidth, eHeight = extra:GetRect()
                            if eLeft then
                                if
                                    extraOverlay._br_left ~= eLeft
                                    or extraOverlay._br_bottom ~= eBottom
                                    or extraOverlay._br_width ~= eWidth
                                    or extraOverlay._br_height ~= eHeight
                                then
                                    extraOverlay:ClearAllPoints()
                                    extraOverlay:SetSize(eWidth, eHeight)
                                    extraOverlay:SetFrameStrata(extra:GetFrameStrata())
                                    extraOverlay:SetFrameLevel(extra:GetFrameLevel() + 5)
                                    extraOverlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", eLeft, eBottom)
                                    extraOverlay._br_left = eLeft
                                    extraOverlay._br_bottom = eBottom
                                    extraOverlay._br_width = eWidth
                                    extraOverlay._br_height = eHeight
                                end
                                extraOverlay:EnableMouse(true)
                                if not extraOverlay:IsShown() then
                                    extraOverlay:Show()
                                end
                            end
                        end
                    else
                        extraOverlay:Hide()
                        extraOverlay:EnableMouse(false)
                        extraOverlay._br_left = nil
                    end
                end
            end
        end
    end
end

-- Schedule secure button sync for the next frame (after layout has been calculated)
local syncPending = false
local function ScheduleSecureSync()
    if syncPending then
        return
    end
    syncPending = true
    C_Timer.After(0, function()
        syncPending = false
        SyncSecureButtons()
    end)
end

-- ============================================================================
-- UPDATE ACTION BUTTONS (CLICK-TO-CAST WIRING)
-- ============================================================================

---Wire up click-to-cast overlays for all buff frames in a category.
---For consumables, also sets up consumable action items and expanded mode.
---For spells, checks talent/spec requirements and castability.
---@param category string
local function UpdateActionButtons(category)
    if InCombatLockdown() or BR.Display.IsTestMode() then
        return
    end

    local db = BuffRemindersDB
    local cs = db.categorySettings and db.categorySettings[category]
    local enabled = cs and cs.clickable == true
    local showHighlight = enabled and (cs.clickableHighlight ~= false)

    for _, frame in pairs(BR.Display.frames) do
        if frame.buffCategory == category then
            if enabled then
                -- Lazily create overlay on first enable
                if not frame.clickOverlay then
                    CreateClickOverlay(frame)
                end
                if frame.clickOverlay.highlight then
                    frame.clickOverlay.highlight:SetShown(showHighlight)
                end
                if category == "consumable" then
                    local actionItems = GetConsumableActionItems(frame.buffDef)
                    -- Update main overlay (uses first/best item)
                    local mainBtn = frame.clickOverlay
                    if actionItems and #actionItems > 0 then
                        local item = actionItems[1]
                        mainBtn.itemID = item.itemID
                        if frame.key == "weaponBuff" or frame.key == "weaponBuffOH" then
                            local slot = frame.key == "weaponBuffOH" and 17 or 16
                            mainBtn:SetAttribute("type", "macro")
                            mainBtn:SetAttribute("macrotext", "/use item:" .. item.itemID .. "\n/use " .. slot)
                        else
                            mainBtn:SetAttribute("type", "item")
                            mainBtn:SetAttribute("item", "item:" .. item.itemID)
                        end
                        mainBtn:EnableMouse(true)
                    else
                        mainBtn.itemID = nil
                        mainBtn:EnableMouse(false)
                    end
                    -- Update clickability on existing sub-icon buttons
                    local displayMode = (db.defaults or {}).consumableDisplayMode or "sub_icons"
                    if displayMode == "sub_icons" and frame.actionButtons then
                        for _, btn in ipairs(frame.actionButtons) do
                            btn:EnableMouse(true)
                            if btn.highlight then
                                btn.highlight:SetShown(showHighlight)
                            end
                        end
                    end
                    -- Expanded mode: set up click overlays on extra frames
                    if displayMode == "expanded" and frame.extraFrames and actionItems then
                        for idx, extra in ipairs(frame.extraFrames) do
                            local itemIdx = idx + 1 -- extra[1] = items[2], etc.
                            if extra:IsShown() and actionItems[itemIdx] then
                                if not extra.clickOverlay then
                                    CreateClickOverlay(extra)
                                end
                                local eItem = actionItems[itemIdx]
                                extra.clickOverlay.itemID = eItem.itemID
                                if frame.key == "weaponBuff" or frame.key == "weaponBuffOH" then
                                    local slot = frame.key == "weaponBuffOH" and 17 or 16
                                    extra.clickOverlay:SetAttribute("type", "macro")
                                    extra.clickOverlay:SetAttribute(
                                        "macrotext",
                                        "/use item:" .. eItem.itemID .. "\n/use " .. slot
                                    )
                                else
                                    extra.clickOverlay:SetAttribute("type", "item")
                                    extra.clickOverlay:SetAttribute("item", "item:" .. eItem.itemID)
                                end
                                extra.clickOverlay:EnableMouse(true)
                                if extra.clickOverlay.highlight then
                                    extra.clickOverlay.highlight:SetShown(showHighlight)
                                end
                            elseif extra.clickOverlay then
                                extra.clickOverlay:EnableMouse(false)
                                extra.clickOverlay:Hide()
                                extra.clickOverlay._br_left = nil
                            end
                        end
                    elseif frame.extraFrames then
                        -- Not expanded: disable extra overlays
                        for _, extra in ipairs(frame.extraFrames) do
                            if extra.clickOverlay then
                                extra.clickOverlay:EnableMouse(false)
                                extra.clickOverlay:Hide()
                                extra.clickOverlay._br_left = nil
                            end
                        end
                    end
                else
                    -- Spells: pre-filter by talent/spec, then check castability
                    local overlay = frame.clickOverlay
                    overlay.itemID = nil
                    -- Pet actions: use per-frame spell from expanded pet icons
                    if frame._br_pet_spell then
                        overlay:SetAttribute("type", "spell")
                        overlay:SetAttribute("spell", frame._br_pet_spell)
                        overlay:EnableMouse(true)
                    else
                        local castableID = GetActionSpellID(frame.buffDef)
                        if castableID then
                            overlay:SetAttribute("type", "spell")
                            overlay:SetAttribute("spell", castableID)
                            overlay:SetAttribute("unit", category == "raid" and "player" or nil)
                            overlay:EnableMouse(true)
                        else
                            overlay:EnableMouse(false)
                        end
                    end
                    -- Pet extra frames: each has its own summon spell
                    if frame.extraFrames then
                        for _, extra in ipairs(frame.extraFrames) do
                            if extra:IsShown() and extra._br_pet_spell then
                                if not extra.clickOverlay then
                                    CreateClickOverlay(extra)
                                end
                                extra.clickOverlay:SetAttribute("type", "spell")
                                extra.clickOverlay:SetAttribute("spell", extra._br_pet_spell)
                                extra.clickOverlay:EnableMouse(true)
                                if extra.clickOverlay.highlight then
                                    extra.clickOverlay.highlight:SetShown(showHighlight)
                                end
                            elseif extra.clickOverlay then
                                extra.clickOverlay:EnableMouse(false)
                                extra.clickOverlay:Hide()
                                extra.clickOverlay._br_left = nil
                            end
                        end
                    end
                end
            elseif frame.clickOverlay then
                frame.clickOverlay:EnableMouse(false)
                frame.clickOverlay:Hide()
                frame.clickOverlay._br_left = nil
                -- Sub-icon buttons: disable mouse but keep visible if mode is sub_icons
                local displayMode = (db.defaults or {}).consumableDisplayMode or "sub_icons"
                if frame.actionButtons then
                    for _, btn in ipairs(frame.actionButtons) do
                        btn:EnableMouse(false)
                        if displayMode ~= "sub_icons" then
                            if btn._br_driver_active then
                                RegisterStateDriver(btn, "visibility", "hide")
                                btn._br_driver_active = false
                                btn._br_x = nil
                            else
                                btn:Hide()
                            end
                        end
                    end
                end
                -- Also disable extra frame overlays
                if frame.extraFrames then
                    for _, extra in ipairs(frame.extraFrames) do
                        if extra.clickOverlay then
                            extra.clickOverlay:EnableMouse(false)
                            extra.clickOverlay:Hide()
                            extra.clickOverlay._br_left = nil
                        end
                    end
                end
            end
        end
    end
    ScheduleSecureSync()
end

-- Refresh overlay spell attributes for all frames (e.g., after spec change).
-- Re-checks talent/spec pre-filters and IsPlayerSpell, updates EnableMouse + spell attribute.
-- Also refreshes consumable action buttons.
local function RefreshOverlaySpells()
    if InCombatLockdown() or BR.Display.IsTestMode() then
        return
    end

    local db = BuffRemindersDB
    for _, frame in pairs(BR.Display.frames) do
        if frame.clickOverlay then
            local category = frame.buffCategory
            local cs = category and db.categorySettings and db.categorySettings[category]
            local enabled = cs and cs.clickable == true
            if enabled and category ~= "consumable" then
                local overlay = frame.clickOverlay
                local castableID = GetActionSpellID(frame.buffDef)
                if castableID then
                    overlay:SetAttribute("type", "spell")
                    overlay:SetAttribute("spell", castableID)
                    overlay:SetAttribute("unit", category == "raid" and "player" or nil)
                    overlay:EnableMouse(true)
                else
                    overlay:EnableMouse(false)
                end
            end
        end
    end
    -- Also refresh consumable and pet action buttons
    UpdateActionButtons("consumable")
    UpdateActionButtons("pet")
end

-- Export module
BR.SecureButtons = {
    UpdateActionButtons = UpdateActionButtons,
    RefreshOverlaySpells = RefreshOverlaySpells,
    GetConsumableActionItems = GetConsumableActionItems,
    UpdateConsumableButtons = UpdateConsumableButtons,
    InvalidateConsumableCache = InvalidateConsumableCache,
    HideAllSecureFrames = HideAllSecureFrames,
    ScheduleSecureSync = ScheduleSecureSync,
    SetQualityOverlay = SetQualityOverlay,
}
