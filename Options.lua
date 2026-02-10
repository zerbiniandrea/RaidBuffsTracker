local _, BR = ...

-- ============================================================================
-- OPTIONS PANEL
-- ============================================================================
-- Simplified 3-tab layout: Buffs, Appearance, Settings

-- Aliases from BR namespace
local Components = BR.Components
local CreateButton = BR.CreateButton
local CreatePanel = BR.CreatePanel
local CreateSectionHeader = BR.CreateSectionHeader
local CreateBuffIcon = BR.CreateBuffIcon
local StyleEditBox = BR.StyleEditBox

-- Shared constants
local TEXCOORD_INSET = BR.TEXCOORD_INSET
local DEFAULT_BORDER_SIZE = BR.DEFAULT_BORDER_SIZE
local DEFAULT_ICON_ZOOM = BR.DEFAULT_ICON_ZOOM
local OPTIONS_BASE_SCALE = BR.OPTIONS_BASE_SCALE

-- Buff tables
local BUFF_TABLES = BR.BUFF_TABLES
local BuffGroups = BR.BuffGroups

-- Local aliases for buff arrays
local RaidBuffs = BUFF_TABLES.raid
local PresenceBuffs = BUFF_TABLES.presence
local TargetedBuffs = BUFF_TABLES.targeted
local SelfBuffs = BUFF_TABLES.self
local PetBuffs = BUFF_TABLES.pet
local Consumables = BUFF_TABLES.consumable

-- Glow module
local Glow = BR.Glow
local GlowTypes = Glow.Types

-- Export references from BuffReminders.lua
local defaults = BR.defaults
local LSM = BR.LSM

-- Helper function aliases
local GetCategorySettings = BR.Helpers.GetCategorySettings
local IsCategorySplit = BR.Helpers.IsCategorySplit
local GetBuffTexture = BR.Helpers.GetBuffTexture
local ValidateSpellID = BR.Helpers.ValidateSpellID
local GenerateCustomBuffKey = BR.Helpers.GenerateCustomBuffKey

-- Display function aliases
local UpdateDisplay = BR.Display.Update
local RefreshTestDisplay = BR.Display.RefreshTest
local ToggleTestMode = BR.Display.ToggleTestMode
local UpdateVisuals = BR.Display.UpdateVisuals
local ResetCategoryFramePosition = BR.Display.ResetCategoryFramePosition
local ReparentBuffFrames = BR.CallbackRegistry.TriggerEvent
        and function()
            BR.CallbackRegistry:TriggerEvent("FramesReparent")
        end
    or function() end

-- Masque state
local IsMasqueActive = BR.Masque and BR.Masque.IsActive or function()
    return false
end

-- Custom buff management
local CreateCustomBuffFrameRuntime = BR.CustomBuffs.CreateRuntime
local RemoveCustomBuffFrame = BR.CustomBuffs.Remove
local UpdateCustomBuffFrame = BR.CustomBuffs.UpdateFrame

-- Module-level variables
local optionsPanel = nil
local glowDemoPanel = nil
local customBuffModal = nil

-- Forward declarations
local ShowGlowDemo, ShowCustomBuffModal

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PANEL_WIDTH = 540
local COL_PADDING = 20
local SECTION_SPACING = 12
local ITEM_HEIGHT = 22
local SCROLLBAR_WIDTH = 24

-- Vertical layout spacing constants
local COMPONENT_GAP = 4 -- Standard gap between components
local SECTION_GAP = 8 -- Gap before/after section boundaries
local DROPDOWN_EXTRA = 8 -- Extra clearance after dropdowns (menu overlay space)

local CATEGORY_ORDER = { "raid", "presence", "targeted", "self", "pet", "consumable", "custom" }
local CATEGORY_LABELS = {
    raid = "Raid Buffs",
    presence = "Presence Buffs",
    targeted = "Targeted Buffs",
    self = "Self Buffs",
    pet = "Pet Reminders",
    consumable = "Consumables",
    custom = "Custom Buffs",
}

-- Layout-aware section header (uses VerticalLayout instead of manual Y tracking)
local function LayoutSectionHeader(layout, parent, text)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetText("|cffffcc00" .. text .. "|r")
    layout:AddText(header, 14, COMPONENT_GAP)
    return header
end

-- ============================================================================
-- OPTIONS PANEL
-- ============================================================================

local function CreateOptionsPanel()
    local panel = CreatePanel("BuffRemindersOptions", PANEL_WIDTH, 597, { escClose = true })
    panel:Hide()

    -- Forward declarations for banner system
    local UpdateBannerLayout
    local housingBanner, masqueBanner

    -- Track all EditBoxes so we can clear focus when panel hides
    local panelEditBoxes = {}
    Components.SetEditBoxesRef(panelEditBoxes)
    panel:SetScript("OnHide", function()
        for _, editBox in ipairs(panelEditBoxes) do
            editBox:ClearFocus()
        end
    end)

    -- Refresh all component values from DB when panel opens (OnShow pattern)
    panel:SetScript("OnShow", function()
        Components.RefreshAll()
        UpdateBannerLayout()
    end)

    -- Title (inline with tab row)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", COL_PADDING, -10)
    title:SetText("|cffffffffBuff|r|cffffcc00Reminders|r")

    -- Version (next to title, smaller font)
    local version = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 6, 0)
    local addonVersion = C_AddOns.GetAddOnMetadata("BuffReminders", "Version") or ""
    version:SetText(addonVersion)

    -- Discord link (next to version)
    local discordSep = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    discordSep:SetPoint("LEFT", version, "RIGHT", 6, 0)
    discordSep:SetText("|cff555555·|r")

    local discordLink = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    discordLink:SetPoint("LEFT", discordSep, "RIGHT", 6, 0)
    discordLink:SetText("|cff7289daJoin Discord|r")

    local discordHit = CreateFrame("Button", nil, panel)
    discordHit:SetAllPoints(discordLink)
    discordHit:SetScript("OnClick", function()
        StaticPopup_Show("BUFFREMINDERS_DISCORD_URL")
    end)
    discordHit:SetScript("OnEnter", function()
        discordLink:SetText("|cff99aaffJoin Discord|r")
        BR.ShowTooltip(
            discordHit,
            "Click for invite link",
            "Got feedback, feature requests, or bug reports?\nJoin the Discord!",
            "ANCHOR_BOTTOM"
        )
    end)
    discordHit:SetScript("OnLeave", function()
        discordLink:SetText("|cff7289daJoin Discord|r")
        BR.HideTooltip()
    end)

    -- Scale controls (top right area) - text link style: < 100% >
    local BASE_SCALE = OPTIONS_BASE_SCALE
    local MIN_PCT, MAX_PCT = 80, 150

    local currentScale = BuffRemindersDB.optionsPanelScale or BASE_SCALE
    local currentPct = math.floor(currentScale / BASE_SCALE * 100 + 0.5)

    -- Close button
    local closeBtn = CreateButton(panel, "x", function()
        panel:Hide()
    end)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local scaleHolder = CreateFrame("Frame", nil, panel)
    scaleHolder:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    scaleHolder:SetSize(60, 16)

    local scaleDown = scaleHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleDown:SetPoint("LEFT", 0, 0)
    scaleDown:SetText("<")

    local scaleValue = scaleHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValue:SetPoint("LEFT", scaleDown, "RIGHT", 4, 0)
    scaleValue:SetText(currentPct .. "%")

    local scaleUp = scaleHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleUp:SetPoint("LEFT", scaleValue, "RIGHT", 4, 0)
    scaleUp:SetText(">")

    local function UpdateScaleText()
        local pct = math.floor((BuffRemindersDB.optionsPanelScale or BASE_SCALE) / BASE_SCALE * 100 + 0.5)
        scaleValue:SetText(pct .. "%")
        scaleDown:SetTextColor(pct > MIN_PCT and 1 or 0.4, pct > MIN_PCT and 1 or 0.4, pct > MIN_PCT and 1 or 0.4)
        scaleUp:SetTextColor(pct < MAX_PCT and 1 or 0.4, pct < MAX_PCT and 1 or 0.4, pct < MAX_PCT and 1 or 0.4)
    end

    local function UpdateScale(delta)
        local oldPct = math.floor((BuffRemindersDB.optionsPanelScale or BASE_SCALE) / BASE_SCALE * 100 + 0.5)
        local newPct = math.max(MIN_PCT, math.min(MAX_PCT, oldPct + delta))
        local newScale = newPct / 100 * BASE_SCALE
        BuffRemindersDB.optionsPanelScale = newScale
        panel:SetScale(newScale)
        UpdateScaleText()
    end

    -- Clickable regions for < and >
    local downBtn = CreateFrame("Button", nil, scaleHolder)
    downBtn:SetAllPoints(scaleDown)
    downBtn:SetScript("OnClick", function()
        UpdateScale(-10)
    end)
    downBtn:SetScript("OnEnter", function()
        if currentPct > MIN_PCT then
            scaleDown:SetTextColor(1, 0.82, 0)
        end
    end)
    downBtn:SetScript("OnLeave", function()
        UpdateScaleText()
    end)

    local upBtn = CreateFrame("Button", nil, scaleHolder)
    upBtn:SetAllPoints(scaleUp)
    upBtn:SetScript("OnClick", function()
        UpdateScale(10)
    end)
    upBtn:SetScript("OnEnter", function()
        local pct = math.floor((BuffRemindersDB.optionsPanelScale or BASE_SCALE) / BASE_SCALE * 100 + 0.5)
        if pct < MAX_PCT then
            scaleUp:SetTextColor(1, 0.82, 0)
        end
    end)
    upBtn:SetScript("OnLeave", function()
        UpdateScaleText()
    end)

    UpdateScaleText()

    if BuffRemindersDB.optionsPanelScale then
        panel:SetScale(BuffRemindersDB.optionsPanelScale)
    end

    -- ========== TABS ==========
    local tabButtons = {}
    local contentContainers = {}
    local TAB_HEIGHT = 22
    local activeTabName = "buffs"

    local function SetActiveTab(tabName)
        activeTabName = tabName
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
        if masqueBanner then
            masqueBanner:Refresh()
            UpdateBannerLayout()
        end
    end

    -- Create 4 tabs: Buffs, Display, Settings, Import/Export
    tabButtons.buffs = Components.Tab(panel, { name = "buffs", label = "Buffs", width = 50 })
    tabButtons.appearance = Components.Tab(panel, { name = "appearance", label = "Display", width = 60 })
    tabButtons.settings = Components.Tab(panel, { name = "settings", label = "Settings", width = 65 })
    tabButtons.profiles = Components.Tab(panel, { name = "profiles", label = "Import/Export", width = 95 })

    -- Position tabs below title
    tabButtons.buffs:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_PADDING, -30)
    tabButtons.appearance:SetPoint("LEFT", tabButtons.buffs, "RIGHT", 2, 0)
    tabButtons.settings:SetPoint("LEFT", tabButtons.appearance, "RIGHT", 2, 0)
    tabButtons.profiles:SetPoint("LEFT", tabButtons.settings, "RIGHT", 2, 0)

    for name, tab in pairs(tabButtons) do
        tab:SetScript("OnClick", function()
            SetActiveTab(name)
        end)
    end

    -- Separator line below tabs
    local tabSeparator = panel:CreateTexture(nil, "ARTWORK")
    tabSeparator:SetHeight(1)
    tabSeparator:SetPoint("TOPLEFT", COL_PADDING, -30 - TAB_HEIGHT)
    tabSeparator:SetPoint("TOPRIGHT", -COL_PADDING, -30 - TAB_HEIGHT)
    tabSeparator:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- ========== CONTENT CONTAINERS ==========
    local CONTENT_TOP = -30 - TAB_HEIGHT - 10

    -- Helper to create a scrollable content container using Components
    local function CreateScrollableContent(name)
        local scrollFrame, content = Components.ScrollableContainer(panel, {
            contentHeight = 600,
            scrollbarWidth = SCROLLBAR_WIDTH,
        })
        scrollFrame:SetPoint("TOPLEFT", 0, CONTENT_TOP)
        scrollFrame:SetPoint("BOTTOMRIGHT", 0, 46)
        scrollFrame:Hide()

        contentContainers[name] = scrollFrame
        return content, scrollFrame
    end

    -- ========== BANNERS ==========
    local BANNER_HEIGHT = 28
    local BANNER_TOP_GAP = 6
    local BANNER_BETWEEN_GAP = 4
    local BANNER_BOTTOM_GAP = 0

    housingBanner = Components.Banner(panel, {
        text = "Buff tracking is disabled in housing zones",
        visible = function()
            return C_Housing
                and (
                    (C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot())
                    or (C_Housing.IsOnNeighborhoodMap and C_Housing.IsOnNeighborhoodMap())
                )
        end,
    })

    masqueBanner = Components.Banner(panel, {
        text = "Zoom and Border settings are managed by Masque",
        icon = "QuestNormal",
        color = "orange",
        visible = function()
            return IsMasqueActive() and activeTabName == "appearance"
        end,
    })

    UpdateBannerLayout = function()
        local bannerY = -30 - TAB_HEIGHT - BANNER_TOP_GAP
        local bannerOffset = 0

        if housingBanner:IsShown() then
            housingBanner:ClearAllPoints()
            housingBanner:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_PADDING, bannerY)
            housingBanner:SetPoint("RIGHT", panel, "RIGHT", -COL_PADDING, 0)
            bannerY = bannerY - BANNER_HEIGHT - BANNER_BETWEEN_GAP
            bannerOffset = bannerOffset + BANNER_HEIGHT + BANNER_BETWEEN_GAP
        end

        if masqueBanner:IsShown() then
            masqueBanner:ClearAllPoints()
            masqueBanner:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_PADDING, bannerY)
            masqueBanner:SetPoint("RIGHT", panel, "RIGHT", -COL_PADDING, 0)
            bannerOffset = bannerOffset + BANNER_HEIGHT + BANNER_BOTTOM_GAP
        elseif bannerOffset > 0 then
            -- Replace the between-gap with a bottom-gap after the last visible banner
            bannerOffset = bannerOffset - BANNER_BETWEEN_GAP + BANNER_BOTTOM_GAP
        end

        local newTop = CONTENT_TOP - bannerOffset
        for _, container in pairs(contentContainers) do
            container:ClearAllPoints()
            container:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, newTop)
            if container.GetContentFrame then
                container:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 46)
            end
        end
    end

    -- Store buff checkboxes for refresh
    panel.buffCheckboxes = {}

    -- ========== HELPER FUNCTIONS ==========

    -- Resolve icons from iconOverride or spellIDs
    local function ResolveBuffIcons(iconOverride, spellIDs)
        if iconOverride then
            -- Use override textures directly
            if type(iconOverride) == "table" then
                return iconOverride
            else
                return { iconOverride }
            end
        elseif spellIDs then
            -- Look up textures from spell IDs (deduplicated)
            local icons = {}
            local seenTextures = {}
            local spellList = type(spellIDs) == "table" and spellIDs or { spellIDs }
            for _, spellID in ipairs(spellList) do
                local texture = GetBuffTexture(spellID)
                if texture and not seenTextures[texture] then
                    seenTextures[texture] = true
                    table.insert(icons, texture)
                end
            end
            return #icons > 0 and icons or nil
        end
        return nil
    end

    -- Create buff checkbox using Components.Checkbox
    local function CreateBuffCheckbox(parent, x, y, spellIDs, key, displayName, infoTooltip, iconOverride)
        local holder = Components.Checkbox(parent, {
            label = displayName,
            icons = ResolveBuffIcons(iconOverride, spellIDs),
            infoTooltip = infoTooltip,
            get = function()
                return BuffRemindersDB.enabledBuffs[key] ~= false
            end,
            onChange = function(checked)
                BuffRemindersDB.enabledBuffs[key] = checked
                if BR.Display.IsTestMode() then
                    RefreshTestDisplay()
                else
                    UpdateDisplay()
                end
            end,
        })
        holder:SetPoint("TOPLEFT", x, y)
        panel.buffCheckboxes[key] = holder
        return y - ITEM_HEIGHT
    end

    -- ========== BUFFS TAB (Two-Column Layout) ==========
    local buffsContent, _ = CreateScrollableContent("buffs")

    -- Render checkboxes for a buff array (single column within each side)
    local function RenderBuffCheckboxes(parent, x, y, buffArray)
        local groupSpells = {}
        local groupDisplaySpells = {}
        local groupIconOverrides = {}

        for _, buff in ipairs(buffArray) do
            if buff.groupId then
                groupSpells[buff.groupId] = groupSpells[buff.groupId] or {}
                groupDisplaySpells[buff.groupId] = groupDisplaySpells[buff.groupId] or {}
                if buff.spellID then
                    local spellList = type(buff.spellID) == "table" and buff.spellID or { buff.spellID }
                    for _, id in ipairs(spellList) do
                        table.insert(groupSpells[buff.groupId], id)
                    end
                end
                if buff.displaySpellIDs then
                    local displayList = type(buff.displaySpellIDs) == "table" and buff.displaySpellIDs
                        or { buff.displaySpellIDs }
                    for _, id in ipairs(displayList) do
                        table.insert(groupDisplaySpells[buff.groupId], id)
                    end
                end
                -- Resolve display icon(s) per entry: override > displaySpellIDs > primary spellID
                if not groupIconOverrides[buff.groupId] then
                    groupIconOverrides[buff.groupId] = {}
                end
                if buff.iconOverride then
                    local overrides = type(buff.iconOverride) == "table" and buff.iconOverride or { buff.iconOverride }
                    for _, icon in ipairs(overrides) do
                        table.insert(groupIconOverrides[buff.groupId], icon)
                    end
                elseif buff.displaySpellIDs then
                    local displayList = type(buff.displaySpellIDs) == "table" and buff.displaySpellIDs
                        or { buff.displaySpellIDs }
                    for _, id in ipairs(displayList) do
                        local texture = GetBuffTexture(id)
                        if texture then
                            table.insert(groupIconOverrides[buff.groupId], texture)
                        end
                    end
                elseif buff.spellID then
                    local primarySpell = type(buff.spellID) == "table" and buff.spellID[1] or buff.spellID
                    if primarySpell and primarySpell > 0 then
                        local texture = GetBuffTexture(primarySpell)
                        if texture then
                            table.insert(groupIconOverrides[buff.groupId], texture)
                        end
                    end
                end
            end
        end

        local seenGroups = {}
        for _, buff in ipairs(buffArray) do
            if buff.groupId then
                if not seenGroups[buff.groupId] then
                    seenGroups[buff.groupId] = true
                    local groupInfo = BuffGroups[buff.groupId]
                    local iconOverride = groupIconOverrides[buff.groupId]
                    if iconOverride and #iconOverride == 0 then
                        iconOverride = nil
                    end
                    local displaySpells = groupDisplaySpells[buff.groupId]
                    local spells = (#displaySpells > 0) and displaySpells or groupSpells[buff.groupId]
                    if #spells == 0 then
                        spells = nil
                    end
                    y = CreateBuffCheckbox(
                        parent,
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
                local displaySpells = buff.displaySpellIDs or buff.spellID
                y = CreateBuffCheckbox(
                    parent,
                    x,
                    y,
                    displaySpells,
                    buff.key,
                    buff.name,
                    buff.infoTooltip,
                    buff.iconOverride
                )
            end
        end

        return y
    end

    -- Column layout constants
    local COL_WIDTH = (PANEL_WIDTH - COL_PADDING * 3) / 2
    local buffsLeftX = COL_PADDING
    local buffsRightX = COL_PADDING + COL_WIDTH + COL_PADDING
    local buffsLeftY = -6
    local buffsRightY = -6

    -- LEFT COLUMN: Group-wide buffs
    -- Raid Buffs
    _, buffsLeftY = CreateSectionHeader(buffsContent, "Raid Buffs", buffsLeftX, buffsLeftY)
    local raidNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    raidNote:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    raidNote:SetText("(for the whole group)")
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsContent, buffsLeftX, buffsLeftY, RaidBuffs)
    buffsLeftY = buffsLeftY - SECTION_SPACING

    -- Targeted Buffs
    _, buffsLeftY = CreateSectionHeader(buffsContent, "Targeted Buffs", buffsLeftX, buffsLeftY)
    local targetedNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    targetedNote:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    targetedNote:SetText("(buffs on someone else)")
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsContent, buffsLeftX, buffsLeftY, TargetedBuffs)
    buffsLeftY = buffsLeftY - SECTION_SPACING

    -- Consumables
    _, buffsLeftY = CreateSectionHeader(buffsContent, "Consumables", buffsLeftX, buffsLeftY)
    local consumablesNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    consumablesNote:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    consumablesNote:SetText("(flasks, food, runes, oils)")
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsContent, buffsLeftX, buffsLeftY, Consumables)

    -- RIGHT COLUMN: Individual buffs
    -- Presence Buffs
    _, buffsRightY = CreateSectionHeader(buffsContent, "Presence Buffs", buffsRightX, buffsRightY)
    local presenceNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    presenceNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    presenceNote:SetText("(at least 1 person needs)")
    buffsRightY = buffsRightY - 14
    buffsRightY = RenderBuffCheckboxes(buffsContent, buffsRightX, buffsRightY, PresenceBuffs)
    buffsRightY = buffsRightY - SECTION_SPACING

    -- Self Buffs
    _, buffsRightY = CreateSectionHeader(buffsContent, "Self Buffs", buffsRightX, buffsRightY)
    local selfNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    selfNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    selfNote:SetText("(buffs strictly on yourself)")
    buffsRightY = buffsRightY - 14
    buffsRightY = RenderBuffCheckboxes(buffsContent, buffsRightX, buffsRightY, SelfBuffs)
    buffsRightY = buffsRightY - SECTION_SPACING

    -- Pet Reminders
    _, buffsRightY = CreateSectionHeader(buffsContent, "Pet Reminders", buffsRightX, buffsRightY)
    local petNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    petNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    petNote:SetText("(pet summon reminders)")
    buffsRightY = buffsRightY - 14
    buffsRightY = RenderBuffCheckboxes(buffsContent, buffsRightX, buffsRightY, PetBuffs)
    buffsRightY = buffsRightY - SECTION_SPACING

    -- Custom Buffs (right column)
    _, buffsRightY = CreateSectionHeader(buffsContent, "Custom Buffs", buffsRightX, buffsRightY)
    panel.customBuffRows = {}

    local customNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    customNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    customNote:SetText("(track any buff/glow by spell ID)")
    buffsRightY = buffsRightY - 14

    local customSectionStartY = buffsRightY
    local customBuffsContainer = CreateFrame("Frame", nil, buffsContent)
    customBuffsContainer:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    customBuffsContainer:SetSize(COL_WIDTH, 200)

    local ADD_BTN_GAP = 4
    local ADD_BTN_HEIGHT = 22
    local CUSTOM_CONTAINER_PAD = ADD_BTN_GAP + ADD_BTN_HEIGHT + 2

    local function RenderCustomBuffRows()
        for _, row in ipairs(panel.customBuffRows) do
            row:Hide()
            row:SetParent(nil)
        end
        panel.customBuffRows = {}

        local db = BuffRemindersDB
        local rowY = 0

        local sortedKeys = {}
        if db.customBuffs then
            for key in pairs(db.customBuffs) do
                table.insert(sortedKeys, key)
            end
        end
        table.sort(sortedKeys)

        for _, key in ipairs(sortedKeys) do
            local customBuff = db.customBuffs[key]

            -- Use Components.Checkbox for consistent styling
            local holder = Components.Checkbox(customBuffsContainer, {
                label = customBuff.name or ("Spell " .. tostring(customBuff.spellID)),
                icons = ResolveBuffIcons(nil, customBuff.spellID),
                get = function()
                    return BuffRemindersDB.enabledBuffs[key] ~= false
                end,
                onChange = function(checked)
                    BuffRemindersDB.enabledBuffs[key] = checked
                    if BR.Display.IsTestMode() then
                        RefreshTestDisplay()
                    else
                        UpdateDisplay()
                    end
                end,
                onRightClick = function()
                    ShowCustomBuffModal(key, RenderCustomBuffRows)
                end,
                tooltip = { title = "Custom Buff", desc = "Right-click to edit or delete" },
            })
            holder:SetPoint("TOPLEFT", 0, rowY)
            panel.buffCheckboxes[key] = holder

            table.insert(panel.customBuffRows, holder)
            rowY = rowY - ITEM_HEIGHT
        end

        local addBtn = CreateButton(customBuffsContainer, "+ Add Custom Buff", function()
            ShowCustomBuffModal(nil, RenderCustomBuffRows)
        end)
        addBtn:SetPoint("TOPLEFT", 0, rowY - ADD_BTN_GAP)
        table.insert(panel.customBuffRows, addBtn)

        customBuffsContainer:SetHeight(math.abs(rowY) + CUSTOM_CONTAINER_PAD)

        -- Recalculate content height when custom buffs change
        local effectiveRightY = customSectionStartY + rowY - CUSTOM_CONTAINER_PAD
        buffsContent:SetHeight(math.max(math.abs(buffsLeftY), math.abs(effectiveRightY)) + 4)

        return rowY
    end

    panel.RenderCustomBuffRows = RenderCustomBuffRows
    RenderCustomBuffRows()

    -- ========== APPEARANCE TAB ==========
    local appearanceContent, _ = CreateScrollableContent("appearance")
    local appX = COL_PADDING
    local appLayout = Components.VerticalLayout(appearanceContent, { x = appX, y = -10 })

    -- Global Defaults section
    LayoutSectionHeader(appLayout, appearanceContent, "Global Defaults")

    local defNote = appearanceContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    appLayout:AddText(defNote, 12, COMPONENT_GAP)
    defNote:SetText("(All categories inherit these unless overridden)")

    -- Fixed column layout: all sliders use default labelWidth (70)
    local DEF_COL2 = 260 -- labelWidth(70) + sliderWidth(100) + value(60) + gap(30)

    local defSizeHolder = Components.Slider(appearanceContent, {
        label = "Icon Size",
        min = 16,
        max = 128,
        get = function()
            return BuffRemindersDB.defaults and BuffRemindersDB.defaults.iconSize or 64
        end,
        onChange = function(val)
            BR.Config.Set("defaults.iconSize", val)
        end,
    })

    local defZoomHolder = Components.Slider(appearanceContent, {
        label = "Icon Zoom",
        min = 0,
        max = 15,
        get = function()
            return BuffRemindersDB.defaults and BuffRemindersDB.defaults.iconZoom or DEFAULT_ICON_ZOOM
        end,
        enabled = function()
            return not IsMasqueActive()
        end,
        suffix = "%",
        onChange = function(val)
            BR.Config.Set("defaults.iconZoom", val)
        end,
    })
    appLayout:AddRow({ { defSizeHolder, appX }, { defZoomHolder, appX + DEF_COL2 } }, COMPONENT_GAP)

    local defBorderHolder = Components.Slider(appearanceContent, {
        label = "Border",
        min = 0,
        max = 8,
        get = function()
            return BuffRemindersDB.defaults and BuffRemindersDB.defaults.borderSize or DEFAULT_BORDER_SIZE
        end,
        enabled = function()
            return not IsMasqueActive()
        end,
        suffix = "px",
        onChange = function(val)
            BR.Config.Set("defaults.borderSize", val)
        end,
    })

    local defAlphaHolder = Components.Slider(appearanceContent, {
        label = "Alpha",
        min = 10,
        max = 100,
        get = function()
            return math.floor((BuffRemindersDB.defaults and BuffRemindersDB.defaults.iconAlpha or 1) * 100)
        end,
        suffix = "%",
        onChange = function(val)
            BR.Config.Set("defaults.iconAlpha", val / 100)
        end,
    })
    appLayout:AddRow({ { defBorderHolder, appX }, { defAlphaHolder, appX + DEF_COL2 } }, COMPONENT_GAP)

    local defSpacingHolder = Components.Slider(appearanceContent, {
        label = "Spacing",
        min = 0,
        max = 50,
        get = function()
            return math.floor((BuffRemindersDB.defaults and BuffRemindersDB.defaults.spacing or 0.2) * 100)
        end,
        suffix = "%",
        onChange = function(val)
            BR.Config.Set("defaults.spacing", val / 100)
        end,
    })

    local defTextSizeHolder = Components.NumericStepper(appearanceContent, {
        label = "Text",
        min = 6,
        max = 32,
        get = function()
            local db = BuffRemindersDB.defaults
            if db and db.textSize then
                return db.textSize
            end
            -- Auto: derive from icon size (matches rendering behavior)
            local iconSize = db and db.iconSize or 64
            return math.floor(iconSize * 0.32)
        end,
        onChange = function(val)
            BR.Config.Set("defaults.textSize", val)
        end,
    })

    local defTextColorHolder = Components.ColorSwatch(appearanceContent, {
        hasOpacity = true,
        get = function()
            local tc = BuffRemindersDB.defaults and BuffRemindersDB.defaults.textColor or { 1, 1, 1 }
            local ta = BuffRemindersDB.defaults and BuffRemindersDB.defaults.textAlpha or 1
            return tc[1], tc[2], tc[3], ta
        end,
        onChange = function(r, g, b, a)
            BR.Config.SetMulti({
                ["defaults.textColor"] = { r, g, b },
                ["defaults.textAlpha"] = a or 1,
            })
        end,
    })
    appLayout:AddRow({ { defSpacingHolder, appX }, { defTextSizeHolder, appX + DEF_COL2 } }, COMPONENT_GAP)
    defTextColorHolder:SetPoint("LEFT", defTextSizeHolder, "RIGHT", 12, 0) -- aligns alpha % with slider values

    -- Font dropdown (global setting, uses LibSharedMedia)
    local function BuildFontOptions()
        local fontList = LSM:List("font")
        local opts = { { label = "Default", value = nil } }
        for _, name in ipairs(fontList) do
            table.insert(opts, { label = name, value = name })
        end
        return opts
    end

    local defFontHolder = Components.Dropdown(appearanceContent, {
        label = "Font:",
        options = BuildFontOptions(),
        width = 200,
        maxItems = 15,
        itemInit = function(_, itemLabel, opt)
            if opt.value then
                local path = LSM:Fetch("font", opt.value)
                if path then
                    itemLabel:SetFont(path, 12, "")
                end
            end
        end,
        get = function()
            return BuffRemindersDB.defaults and BuffRemindersDB.defaults.fontFace or nil
        end,
        onChange = function(val)
            BR.Config.Set("defaults.fontFace", val)
        end,
    })
    appLayout:Add(defFontHolder, nil, COMPONENT_GAP)

    local defDirHolder = Components.DirectionButtons(appearanceContent, {
        get = function()
            return BuffRemindersDB.defaults and BuffRemindersDB.defaults.growDirection or "CENTER"
        end,
        onChange = function(dir)
            BR.Config.Set("defaults.growDirection", dir)
        end,
    })
    appLayout:Add(defDirHolder, nil, COMPONENT_GAP + DROPDOWN_EXTRA)

    -- Expiration Glow section
    LayoutSectionHeader(appLayout, appearanceContent, "Expiration Glow")
    appLayout:Space(COMPONENT_GAP)

    local previewBtn = CreateButton(appearanceContent, "Preview", function()
        ShowGlowDemo()
    end)
    appLayout:Add(previewBtn, nil, SECTION_GAP)

    local defGlowHolder = Components.Checkbox(appearanceContent, {
        label = "Glow",
        get = function()
            return BuffRemindersDB.defaults and BuffRemindersDB.defaults.showExpirationGlow ~= false
        end,
        onChange = function(checked)
            BR.Config.Set("defaults.showExpirationGlow", checked)
            Components.RefreshAll()
        end,
    })

    local function isExpirationGlowEnabled()
        return BuffRemindersDB.defaults and BuffRemindersDB.defaults.showExpirationGlow ~= false
    end

    local defThresholdHolder = Components.Slider(appearanceContent, {
        min = 1,
        max = 45,
        step = 5,
        get = function()
            return BuffRemindersDB.defaults and BuffRemindersDB.defaults.expirationThreshold or 15
        end,
        enabled = isExpirationGlowEnabled,
        suffix = " min",
        onChange = function(val)
            BR.Config.Set("defaults.expirationThreshold", val)
        end,
    })
    defThresholdHolder:SetPoint("LEFT", defGlowHolder.checkbox, "RIGHT", 40, 0)

    local typeOptions = {}
    for i, gt in ipairs(GlowTypes) do
        typeOptions[i] = { label = gt.name, value = i }
    end

    local defTypeHolder = Components.Dropdown(appearanceContent, {
        label = "Type:",
        labelWidth = 34,
        options = typeOptions,
        get = function()
            return BuffRemindersDB.defaults and BuffRemindersDB.defaults.glowType or 1
        end,
        enabled = isExpirationGlowEnabled,
        width = 95,
        onChange = function(val)
            BR.Config.Set("defaults.glowType", val)
        end,
    }, "BuffRemindersDefGlowTypeDropdown")
    defTypeHolder:SetPoint("LEFT", defThresholdHolder, "RIGHT", 8, 0)

    local defGlowColorHolder = Components.ColorSwatch(appearanceContent, {
        hasOpacity = true,
        get = function()
            local c = BR.Config.Get("defaults.glowColor", Glow.DEFAULT_COLOR)
            return c[1], c[2], c[3], c[4] or 1
        end,
        enabled = isExpirationGlowEnabled,
        onChange = function(r, g, b, a)
            BR.Config.Set("defaults.glowColor", { r, g, b, a or 1 })
        end,
    })
    defGlowColorHolder:SetPoint("LEFT", defTypeHolder, "RIGHT", 6, 0)

    appLayout:Add(defGlowHolder, nil, COMPONENT_GAP + DROPDOWN_EXTRA)

    -- Per-Category Customization section
    LayoutSectionHeader(appLayout, appearanceContent, "Per-Category Customization")
    appLayout:Space(COMPONENT_GAP)

    -- Create collapsible sections that chain-anchor to each other
    local categorySections = {}
    local previousSection = nil

    local function UpdateAppearanceContentHeight()
        -- Calculate total height: fixed header area + all collapsible sections
        local totalHeight = math.abs(appLayout:GetY())
        for _, sec in ipairs(categorySections) do
            totalHeight = totalHeight + sec:GetHeight() + 4
        end
        appearanceContent:SetHeight(totalHeight)
    end

    local SECTION_SCROLLBAR_OFFSET = COL_PADDING
    for _, category in ipairs(CATEGORY_ORDER) do
        local section = Components.CollapsibleSection(appearanceContent, {
            title = CATEGORY_LABELS[category],
            defaultCollapsed = true,
            scrollbarOffset = SECTION_SCROLLBAR_OFFSET,
            onToggle = function()
                -- Defer layout update to next frame
                C_Timer.After(0, UpdateAppearanceContentHeight)
            end,
        })

        if previousSection then
            section:SetPoint("TOPLEFT", previousSection, "BOTTOMLEFT", 0, -4)
        else
            section:SetPoint("TOPLEFT", appX, appLayout:GetY())
        end

        local catContent = section:GetContentFrame()
        local catLayout = Components.VerticalLayout(catContent, { x = 0, y = 0 })

        local db = BuffRemindersDB

        -- Visibility callback for W/S/D/R toggles
        local function OnCategoryVisibilityChange()
            if BR.Display.IsTestMode() then
                RefreshTestDisplay()
            else
                UpdateDisplay()
            end
        end

        -- W/S/D/R content visibility toggles
        local visToggles = Components.VisibilityToggles(catContent, {
            category = category,
            onChange = OnCategoryVisibilityChange,
        })
        catLayout:Add(visToggles, nil, SECTION_GAP)

        -- Icons sub-header (all categories except custom)
        if category ~= "custom" then
            local iconsHeader = catContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            iconsHeader:SetText("|cffffcc00Icons|r")
            catLayout:AddText(iconsHeader, 12, COMPONENT_GAP)
        end

        -- Show text on icons (not for custom — custom buffs have per-buff missing text)
        if category ~= "custom" then
            local showTextHolder = Components.Checkbox(catContent, {
                label = "Show text on icons",
                get = function()
                    local cs = db.categorySettings and db.categorySettings[category]
                    return not cs or cs.showText ~= false
                end,
                tooltip = {
                    title = "Show text on icons",
                    desc = "Display count or missing text overlays on buff icons for this category",
                },
                onChange = function(checked)
                    BR.Config.Set("categorySettings." .. category .. ".showText", checked)
                end,
            })
            catLayout:Add(showTextHolder, nil, COMPONENT_GAP)
        end

        -- "BUFF!" text (raid only, grouped under Icons)
        if category == "raid" then
            local reminderHolder = Components.Checkbox(catContent, {
                label = 'Show "BUFF!" reminder text',
                get = function()
                    local cs = db.categorySettings and db.categorySettings.raid
                    return not cs or cs.showBuffReminder ~= false
                end,
                onChange = function(checked)
                    BR.Config.Set("categorySettings.raid.showBuffReminder", checked)
                end,
            })
            catLayout:Add(reminderHolder, nil, COMPONENT_GAP)
        end

        -- Click to cast checkbox (raid and consumable only)
        if category == "raid" or category == "consumable" or category == "pet" then
            local clickableHolder = Components.Checkbox(catContent, {
                label = "Click to cast",
                get = function()
                    local cs = db.categorySettings and db.categorySettings[category]
                    return cs and cs.clickable == true
                end,
                tooltip = {
                    title = "Click to cast",
                    desc = "Make buff icons clickable to cast the corresponding spell (out of combat only). "
                        .. "Only works for spells your character can cast.",
                },
                warningTooltip = "Help improve this feature!|This feature interacts with many different spells "
                    .. "and class configurations that can't all be tested by one person.\n\n"
                    .. "If you encounter any Lua errors (e.g. when clicking a buff icon, "
                    .. "when entering combat for a raid encounter, or with only certain "
                    .. "categories set to clickable), please report them on Discord, "
                    .. "CurseForge, or GitHub with:\n\n"
                    .. "- Your class and spec\n"
                    .. "- Which buff icon you clicked (if applicable)\n"
                    .. "- Which categories have click to cast enabled\n"
                    .. "- What you were doing when the error occurred\n"
                    .. "- The full error message\n\n"
                    .. "Your reports help make this feature more reliable for everyone!",
                onChange = function(checked)
                    if not db.categorySettings then
                        db.categorySettings = {}
                    end
                    if not db.categorySettings[category] then
                        db.categorySettings[category] = {}
                    end
                    db.categorySettings[category].clickable = checked
                    BR.Display.UpdateActionButtons(category)
                    Components.RefreshAll()
                end,
            })
            catLayout:Add(clickableHolder, nil, 2)

            catLayout:SetX(20)
            local highlightHolder = Components.Checkbox(catContent, {
                label = "Hover highlight",
                get = function()
                    local hcs = db.categorySettings and db.categorySettings[category]
                    return hcs and hcs.clickableHighlight ~= false
                end,
                enabled = function()
                    local hcs = db.categorySettings and db.categorySettings[category]
                    return hcs and hcs.clickable == true
                end,
                tooltip = {
                    title = "Hover highlight",
                    desc = "Show a subtle highlight when hovering over clickable buff icons.",
                },
                onChange = function(checked)
                    if not db.categorySettings then
                        db.categorySettings = {}
                    end
                    if not db.categorySettings[category] then
                        db.categorySettings[category] = {}
                    end
                    db.categorySettings[category].clickableHighlight = checked
                    BR.Display.UpdateActionButtons(category)
                end,
            })
            catLayout:Add(highlightHolder, nil, COMPONENT_GAP)
            catLayout:SetX(0)
        end

        -- Behavior sub-header (pet only)
        if category == "pet" then
            catLayout:Space(SECTION_GAP)
            local behaviorHeader = catContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            behaviorHeader:SetText("|cffffcc00Behavior|r")
            catLayout:AddText(behaviorHeader, 12, COMPONENT_GAP)

            local hideMountHolder = Components.Checkbox(catContent, {
                label = "Hide while mounted",
                get = function()
                    return BuffRemindersDB.hidePetWhileMounted ~= false
                end,
                onChange = function(checked)
                    BuffRemindersDB.hidePetWhileMounted = checked
                    UpdateDisplay()
                end,
            })
            catLayout:Add(hideMountHolder, nil, COMPONENT_GAP)

            local passiveCombatHolder = Components.Checkbox(catContent, {
                label = "Pet passive only in combat",
                get = function()
                    return BuffRemindersDB.petPassiveOnlyInCombat == true
                end,
                tooltip = {
                    title = "Pet passive only in combat",
                    desc = "Only show the passive pet reminder while in combat. When disabled, the reminder is always shown.",
                },
                onChange = function(checked)
                    BuffRemindersDB.petPassiveOnlyInCombat = checked
                    UpdateDisplay()
                end,
            })
            catLayout:Add(passiveCombatHolder, nil, COMPONENT_GAP)

            local updatePetDisplayModePreview -- forward declaration for preview update
            local petDisplayModeHolder = Components.Dropdown(catContent, {
                label = "Pet display",
                width = 120,
                get = function()
                    return BR.Config.Get("defaults.petDisplayMode", "generic")
                end,
                options = {
                    { value = "generic", label = "Generic icon" },
                    { value = "expanded", label = "Summon spells" },
                },
                tooltip = {
                    title = "Pet display mode",
                    desc = "Generic icon: show a single 'NO PET' icon. Summon spells: show individual pet summon spell icons (e.g., each stable pet for hunters).",
                },
                onChange = function(val)
                    BR.Config.Set("defaults.petDisplayMode", val)
                    if updatePetDisplayModePreview then
                        updatePetDisplayModePreview(val)
                    end
                end,
            })
            catLayout:Add(petDisplayModeHolder, nil, COMPONENT_GAP + DROPDOWN_EXTRA)

            -- Pet display mode preview (anchored to the right of the dropdown)
            local PP_ICON = 24
            local PP_BORDER = 2
            local PP_GAP = 3
            local PP_STEP = PP_ICON + PP_GAP + PP_BORDER * 2

            local TEX_PET_GENERIC = 136082 -- Summon Demon flyout icon
            local TEX_PETS = { 136218, 136221, 136217 } -- Imp, Voidwalker, Felhunter

            local petPreviewHolder = CreateFrame("Frame", nil, catContent)
            petPreviewHolder:SetSize(260, PP_ICON + PP_BORDER * 2 + 14)
            petPreviewHolder:SetPoint("TOPLEFT", petDisplayModeHolder, "TOPRIGHT", 12, 0)

            local petPreviewContainer = CreateFrame("Frame", nil, petPreviewHolder)
            petPreviewContainer:SetPoint("TOPLEFT", 0, 0)
            petPreviewContainer:SetSize(260, PP_ICON + PP_BORDER * 2)
            petPreviewContainer:SetAlpha(0.7)

            local petPreviewDesc = petPreviewHolder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            petPreviewDesc:SetPoint("TOPLEFT", petPreviewContainer, "BOTTOMLEFT", 0, -3)
            petPreviewDesc:SetJustifyH("LEFT")

            local function CreatePetPreviewIcon(parent, texture, size)
                local f = CreateFrame("Frame", nil, parent)
                f:SetSize(size, size)
                f.icon = f:CreateTexture(nil, "ARTWORK")
                f.icon:SetAllPoints()
                f.icon:SetTexture(texture)
                local z = TEXCOORD_INSET
                f.icon:SetTexCoord(z, 1 - z, z, 1 - z)
                f.border = f:CreateTexture(nil, "BACKGROUND")
                f.border:SetColorTexture(0, 0, 0, 1)
                f.border:SetPoint("TOPLEFT", -PP_BORDER, PP_BORDER)
                f.border:SetPoint("BOTTOMRIGHT", PP_BORDER, -PP_BORDER)
                return f
            end

            local allPetPreviewFrames = {}

            -- Generic: single icon
            local genericFrame = CreatePetPreviewIcon(petPreviewContainer, TEX_PET_GENERIC, PP_ICON)
            genericFrame:SetPoint("TOPLEFT", petPreviewContainer, "TOPLEFT", 0, 0)
            genericFrame:Hide()
            allPetPreviewFrames[#allPetPreviewFrames + 1] = genericFrame

            -- Expanded: individual summon spell icons
            local expandedPetFrames = {}
            for i = 1, 3 do
                local f = CreatePetPreviewIcon(petPreviewContainer, TEX_PETS[i], PP_ICON)
                f:SetPoint("TOPLEFT", petPreviewContainer, "TOPLEFT", (i - 1) * PP_STEP, 0)
                f:Hide()
                expandedPetFrames[i] = f
                allPetPreviewFrames[#allPetPreviewFrames + 1] = f
            end

            local PET_MODE_FRAMES = {
                generic = { genericFrame },
                expanded = expandedPetFrames,
            }
            local PET_MODE_DESC = {
                generic = "A single generic 'NO PET' icon",
                expanded = "Each pet summon spell as its own icon",
            }

            updatePetDisplayModePreview = function(mode)
                for _, f in ipairs(allPetPreviewFrames) do
                    f:Hide()
                end
                local shown = PET_MODE_FRAMES[mode]
                if shown then
                    for _, f in ipairs(shown) do
                        f:Show()
                    end
                end
                petPreviewDesc:SetText(PET_MODE_DESC[mode] or "")
            end

            -- Initial state
            updatePetDisplayModePreview(BR.Config.Get("defaults.petDisplayMode", "generic"))

            -- Register for refresh so reopening the panel re-reads the value
            function petPreviewHolder:Refresh()
                updatePetDisplayModePreview(BR.Config.Get("defaults.petDisplayMode", "generic"))
            end
            table.insert(BR.RefreshableComponents, petPreviewHolder)
        end

        -- Item display mode (consumable only, grouped with icon options)
        if category == "consumable" then
            local updateDisplayModePreview -- forward declaration for preview update
            local displayModeHolder = Components.Dropdown(catContent, {
                label = "Item display",
                get = function()
                    return BR.Config.Get("defaults.consumableDisplayMode", "sub_icons")
                end,
                options = {
                    { value = "icon_only", label = "Icon only" },
                    { value = "sub_icons", label = "Sub-icons" },
                    { value = "expanded", label = "Expanded" },
                },
                tooltip = {
                    title = "Consumable item display",
                    desc = "Icon only: show the top item icon only. Sub-icons: show small clickable icons below the main icon. Expanded: show each item variant as a full-sized icon in the row.",
                },
                onChange = function(val)
                    BR.Config.Set("defaults.consumableDisplayMode", val)
                    if updateDisplayModePreview then
                        updateDisplayModePreview(val)
                    end
                end,
            })
            catLayout:Add(displayModeHolder, nil, COMPONENT_GAP + DROPDOWN_EXTRA)

            -- Display mode preview (anchored to the right of the dropdown)
            local P_ICON = 24
            local P_SUB = 12
            local P_BORDER = 2
            local P_GAP = 3
            local P_STEP = P_ICON + P_GAP + P_BORDER * 2
            local P_SUB_STEP = P_SUB + P_BORDER * 2 -- sub-icons touch borders
            -- Distinct textures for flask/food/oil and their variants
            local TEX_FLASK = { 134877, 134863, 134852 } -- main + 2 other variants
            local TEX_FOOD = { 134062, 133984 } -- main + 1 other variant
            local TEX_OIL = 609892

            local previewHolder = CreateFrame("Frame", nil, catContent)
            previewHolder:SetSize(260, P_ICON + P_SUB + P_GAP + P_BORDER * 2 + 14)
            previewHolder:SetPoint("TOPLEFT", displayModeHolder, "TOPRIGHT", 12, 0)

            local previewContainer = CreateFrame("Frame", nil, previewHolder)
            previewContainer:SetPoint("TOPLEFT", 0, 0)
            previewContainer:SetSize(260, P_ICON + P_SUB + P_GAP + P_BORDER * 2)
            previewContainer:SetAlpha(0.7)

            local previewDesc = previewHolder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            previewDesc:SetPoint("TOPLEFT", previewContainer, "BOTTOMLEFT", 0, -3)
            previewDesc:SetJustifyH("LEFT")

            local function CreatePreviewIcon(parent, texture, size)
                local f = CreateFrame("Frame", nil, parent)
                f:SetSize(size, size)
                f.icon = f:CreateTexture(nil, "ARTWORK")
                f.icon:SetAllPoints()
                f.icon:SetTexture(texture)
                local z = TEXCOORD_INSET
                f.icon:SetTexCoord(z, 1 - z, z, 1 - z)
                f.border = f:CreateTexture(nil, "BACKGROUND")
                f.border:SetColorTexture(0, 0, 0, 1)
                f.border:SetPoint("TOPLEFT", -P_BORDER, P_BORDER)
                f.border:SetPoint("BOTTOMRIGHT", P_BORDER, -P_BORDER)
                return f
            end

            local allPreviewFrames = {}

            -- Icon-only: [Flask] [Food] [Oil]
            local iconOnlyFrames = {}
            local iconOnlyTextures = { TEX_FLASK[1], TEX_FOOD[1], TEX_OIL }
            for i = 1, 3 do
                local f = CreatePreviewIcon(previewContainer, iconOnlyTextures[i], P_ICON)
                f:SetPoint("TOPLEFT", previewContainer, "TOPLEFT", (i - 1) * P_STEP, 0)
                f:Hide()
                iconOnlyFrames[i] = f
                allPreviewFrames[#allPreviewFrames + 1] = f
            end

            -- Sub-icons: [Flask] [Food] [Oil] with variant sub-icons below
            local subIconsFrames = { mains = {}, subs = {} }
            local subVariants = { TEX_FLASK, TEX_FOOD, {} } -- oil has no variants
            for i, variants in ipairs(subVariants) do
                local mainTex = (#variants > 0) and variants[1] or TEX_OIL
                local main = CreatePreviewIcon(previewContainer, mainTex, P_ICON)
                main:SetPoint("TOPLEFT", previewContainer, "TOPLEFT", (i - 1) * P_STEP, 0)
                main:Hide()
                subIconsFrames.mains[i] = main
                allPreviewFrames[#allPreviewFrames + 1] = main
                if #variants > 1 then
                    local subCount = #variants - 1
                    local subRowWidth = (subCount - 1) * P_SUB_STEP + P_SUB
                    local subOffsetX = (P_ICON - subRowWidth) / 2
                    for j = 2, #variants do
                        local sub = CreatePreviewIcon(previewContainer, variants[j], P_SUB)
                        sub:SetPoint("TOPLEFT", main, "BOTTOMLEFT", subOffsetX + (j - 2) * P_SUB_STEP, -P_GAP)
                        sub:Hide()
                        subIconsFrames.subs[#subIconsFrames.subs + 1] = sub
                        allPreviewFrames[#allPreviewFrames + 1] = sub
                    end
                end
            end

            -- Expanded: [F1][F2][F3][Fd1][Fd2][Oil] — each variant at full size
            local expandedFrames = {}
            local expandedTextures = {
                TEX_FLASK[1],
                TEX_FLASK[2],
                TEX_FLASK[3],
                TEX_FOOD[1],
                TEX_FOOD[2],
                TEX_OIL,
            }
            for i = 1, 6 do
                local f = CreatePreviewIcon(previewContainer, expandedTextures[i], P_ICON)
                f:SetPoint("TOPLEFT", previewContainer, "TOPLEFT", (i - 1) * P_STEP, 0)
                f:Hide()
                expandedFrames[i] = f
                allPreviewFrames[#allPreviewFrames + 1] = f
            end

            -- Combine sub-icons mains + subs into one flat list
            local subIconsAll = {}
            for _, f in ipairs(subIconsFrames.mains) do
                subIconsAll[#subIconsAll + 1] = f
            end
            for _, f in ipairs(subIconsFrames.subs) do
                subIconsAll[#subIconsAll + 1] = f
            end

            local MODE_FRAMES = {
                icon_only = iconOnlyFrames,
                sub_icons = subIconsAll,
                expanded = expandedFrames,
            }
            local MODE_DESC = {
                icon_only = "Shows the item with the highest count",
                sub_icons = "Small clickable item variants below each icon",
                expanded = "Each item variant as a full-sized icon",
            }

            updateDisplayModePreview = function(mode)
                for _, f in ipairs(allPreviewFrames) do
                    f:Hide()
                end
                local shown = MODE_FRAMES[mode]
                if shown then
                    for _, f in ipairs(shown) do
                        f:Show()
                    end
                end
                previewDesc:SetText(MODE_DESC[mode] or "")
            end

            -- Initial state
            updateDisplayModePreview(BR.Config.Get("defaults.consumableDisplayMode", "sub_icons"))

            -- Register for refresh so reopening the panel re-reads the value
            function previewHolder:Refresh()
                updateDisplayModePreview(BR.Config.Get("defaults.consumableDisplayMode", "sub_icons"))
            end
            table.insert(BR.RefreshableComponents, previewHolder)

            -- Sub-header for behavior options
            catLayout:Space(SECTION_GAP)
            local behaviorHeader = catContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            behaviorHeader:SetText("|cffffcc00Behavior|r")
            catLayout:AddText(behaviorHeader, 12, COMPONENT_GAP)

            local showWithoutItemsHolder = Components.Checkbox(catContent, {
                label = "Show when not in bags",
                get = function()
                    return BR.Config.Get("defaults.showConsumablesWithoutItems", false) == true
                end,
                tooltip = {
                    title = "Show consumables without items",
                    desc = "When enabled, consumable reminders are shown even if you don't have the item in your bags. When disabled, only consumables you actually carry are shown.",
                },
                onChange = function(checked)
                    BR.Config.Set("defaults.showConsumablesWithoutItems", checked)
                end,
            })
            catLayout:Add(showWithoutItemsHolder, nil, COMPONENT_GAP)
        end

        -- Layout sub-header
        catLayout:Space(SECTION_GAP)
        local layoutHeader = catContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        layoutHeader:SetText("|cffffcc00Layout|r")
        catLayout:AddText(layoutHeader, 12, COMPONENT_GAP)

        -- Priority slider (only relevant when not split)
        local priorityHolder = Components.Slider(catContent, {
            label = "Priority",
            min = 1,
            max = 7,
            step = 1,
            get = function()
                local cs = db.categorySettings and db.categorySettings[category]
                return cs and cs.priority or defaults.categorySettings[category].priority
            end,
            enabled = function()
                return not IsCategorySplit(category)
            end,
            tooltip = {
                title = "Display Priority",
                desc = "Controls the order of this category in the combined frame. Lower values are displayed first.",
            },
            onChange = function(val)
                BR.Config.Set("categorySettings." .. category .. ".priority", val)
            end,
        })
        catLayout:Add(priorityHolder, nil, COMPONENT_GAP)

        -- Split frame checkbox
        local splitHolder = Components.Checkbox(catContent, {
            label = "Split into separate frame",
            get = function()
                return IsCategorySplit(category)
            end,
            tooltip = {
                title = "Split into separate frame",
                desc = "Display this category's buffs in a separate, independently movable frame",
            },
            onChange = function(checked)
                if not db.categorySettings then
                    db.categorySettings = {}
                end
                if not db.categorySettings[category] then
                    db.categorySettings[category] = {}
                end
                db.categorySettings[category].split = checked
                ReparentBuffFrames()
                UpdateVisuals()
            end,
        })
        catLayout:Add(splitHolder, nil, COMPONENT_GAP)

        -- Reset position button (only relevant when split)
        local resetBtn = CreateButton(catContent, "Reset Position", function()
            local catDefaults = defaults.categorySettings[category]
            if catDefaults and catDefaults.position then
                ResetCategoryFramePosition(category, catDefaults.position.x, catDefaults.position.y)
            end
        end)
        resetBtn:SetPoint("LEFT", splitHolder, "RIGHT", 10, 0)
        resetBtn:SetEnabled(IsCategorySplit(category))

        local origSplitClick = splitHolder.checkbox:GetScript("OnClick")
        splitHolder.checkbox:SetScript("OnClick", function(self)
            if origSplitClick then
                origSplitClick(self)
            end
            resetBtn:SetEnabled(IsCategorySplit(category))
            Components.RefreshAll()
        end)

        -- Shared enabled predicates for this category
        local function isCategorySplitEnabled()
            return IsCategorySplit(category)
        end

        local function isCustomAppearanceEnabled()
            return IsCategorySplit(category)
                and db.categorySettings
                and db.categorySettings[category]
                and db.categorySettings[category].useCustomAppearance == true
        end

        -- Use custom appearance checkbox
        catLayout:SetX(0)
        local useCustomAppHolder = Components.Checkbox(catContent, {
            label = "Use custom appearance",
            get = function()
                return db.categorySettings
                    and db.categorySettings[category]
                    and db.categorySettings[category].useCustomAppearance == true
            end,
            enabled = isCategorySplitEnabled,
            tooltip = {
                title = "Use custom appearance",
                desc = "When disabled, this category inherits appearance settings from Global Defaults",
            },
            infoTooltip = "Custom appearance requires splitting|This category must be split into a separate frame to customize its appearance independently. Check 'Split into separate frame' above to enable this option.",
            onChange = function(checked)
                if not db.categorySettings then
                    db.categorySettings = {}
                end
                if not db.categorySettings[category] then
                    db.categorySettings[category] = {}
                end
                -- When enabling custom appearance, snapshot current effective values
                -- so the category starts independent from future Global Defaults changes
                if checked then
                    local effective = GetCategorySettings(category)
                    local cs = db.categorySettings[category]
                    local appearanceKeys = {
                        "iconSize",
                        "spacing",
                        "iconZoom",
                        "borderSize",
                        "iconAlpha",
                        "textAlpha",
                        "growDirection",
                    }
                    if category == "consumable" then
                        appearanceKeys[#appearanceKeys + 1] = "glowType"
                        appearanceKeys[#appearanceKeys + 1] = "showExpirationGlow"
                        appearanceKeys[#appearanceKeys + 1] = "expirationThreshold"
                    end
                    for _, key in ipairs(appearanceKeys) do
                        if cs[key] == nil and effective[key] ~= nil then
                            cs[key] = effective[key]
                        end
                    end
                    -- textSize: only snapshot if explicitly set (nil = auto-derive from iconSize)
                    if cs.textSize == nil and effective.textSize ~= nil then
                        cs.textSize = effective.textSize
                    end
                    -- textColor: deep copy (table value)
                    if cs.textColor == nil and effective.textColor then
                        local tc = effective.textColor
                        cs.textColor = { tc[1], tc[2], tc[3] }
                    end
                    -- glowColor: deep copy (table value, consumable only)
                    if category == "consumable" then
                        if cs.glowColor == nil and effective.glowColor then
                            local gc = effective.glowColor
                            cs.glowColor = { gc[1], gc[2], gc[3], gc[4] or 1 }
                        end
                    end
                end
                db.categorySettings[category].useCustomAppearance = checked
                UpdateVisuals()
                Components.RefreshAll()
            end,
        })
        catLayout:Add(useCustomAppHolder, nil, COMPONENT_GAP)

        -- Direction buttons (part of custom appearance)
        catLayout:SetX(10)
        local dirHolder = Components.DirectionButtons(catContent, {
            get = function()
                local catSettings = db.categorySettings and db.categorySettings[category]
                local val = catSettings and catSettings.growDirection
                if val ~= nil then
                    return val
                end
                return db.defaults and db.defaults.growDirection or "CENTER"
            end,
            enabled = isCustomAppearanceEnabled,
            onChange = function(dir)
                BR.Config.Set("categorySettings." .. category .. ".growDirection", dir)
            end,
        })
        catLayout:Add(dirHolder, nil, COMPONENT_GAP + DROPDOWN_EXTRA)

        -- Appearance controls (3-row grid with fixed columns)
        catLayout:SetX(10)
        local appFrame = CreateFrame("Frame", nil, catContent)
        appFrame:SetSize(380, 50)
        catLayout:SetX(10)
        catLayout:Add(appFrame, 0)

        -- Read the category's own saved value, falling back to defaults only if no value was saved.
        -- This avoids showing inherited defaults when useCustomAppearance is off, so toggling
        -- custom appearance off/on preserves the user's previously configured values.
        local function getCatOwnValue(key, default)
            local catSettings = db.categorySettings and db.categorySettings[category]
            local val = catSettings and catSettings[key]
            if val ~= nil then
                return val
            end
            return db.defaults and db.defaults[key] or default
        end

        local CAT_LW = 50 -- Shared label width for aligned columns
        local CAT_COL2 = CAT_LW + 100 + 60 + 10 -- labelWidth + slider + value + gap = 220

        local sizeHolder = Components.Slider(appFrame, {
            label = "Size",
            min = 16,
            max = 128,
            labelWidth = CAT_LW,
            get = function()
                return getCatOwnValue("iconSize", 64)
            end,
            enabled = isCustomAppearanceEnabled,
            onChange = function(val)
                BR.Config.Set("categorySettings." .. category .. ".iconSize", val)
            end,
        })
        sizeHolder:SetPoint("TOPLEFT", 0, 0)

        local zoomHolder = Components.Slider(appFrame, {
            label = "Zoom",
            min = 0,
            max = 15,
            labelWidth = CAT_LW,
            get = function()
                return getCatOwnValue("iconZoom", DEFAULT_ICON_ZOOM)
            end,
            enabled = function()
                return isCustomAppearanceEnabled() and not IsMasqueActive()
            end,
            suffix = "%",
            onChange = function(val)
                BR.Config.Set("categorySettings." .. category .. ".iconZoom", val)
            end,
        })
        zoomHolder:SetPoint("TOPLEFT", CAT_COL2, 0)

        local borderHolder = Components.Slider(appFrame, {
            label = "Border",
            min = 0,
            max = 8,
            labelWidth = CAT_LW,
            get = function()
                return getCatOwnValue("borderSize", DEFAULT_BORDER_SIZE)
            end,
            enabled = function()
                return isCustomAppearanceEnabled() and not IsMasqueActive()
            end,
            suffix = "px",
            onChange = function(val)
                BR.Config.Set("categorySettings." .. category .. ".borderSize", val)
            end,
        })
        borderHolder:SetPoint("TOPLEFT", 0, -24)

        local catAlphaHolder = Components.Slider(appFrame, {
            label = "Alpha",
            min = 10,
            max = 100,
            labelWidth = CAT_LW,
            get = function()
                return math.floor((getCatOwnValue("iconAlpha", 1)) * 100)
            end,
            enabled = isCustomAppearanceEnabled,
            suffix = "%",
            onChange = function(val)
                BR.Config.Set("categorySettings." .. category .. ".iconAlpha", val / 100)
            end,
        })
        catAlphaHolder:SetPoint("TOPLEFT", CAT_COL2, -24)

        local spacingHolder = Components.Slider(appFrame, {
            label = "Spacing",
            min = 0,
            max = 50,
            labelWidth = CAT_LW,
            get = function()
                return math.floor((getCatOwnValue("spacing", 0.2)) * 100)
            end,
            enabled = isCustomAppearanceEnabled,
            suffix = "%",
            onChange = function(val)
                BR.Config.Set("categorySettings." .. category .. ".spacing", val / 100)
            end,
        })
        spacingHolder:SetPoint("TOPLEFT", 0, -48)

        local catTextSizeHolder = Components.NumericStepper(appFrame, {
            label = "Text",
            labelWidth = CAT_LW,
            min = 6,
            max = 32,
            get = function()
                local textSize = getCatOwnValue("textSize", nil)
                if textSize then
                    return textSize
                end
                -- Auto: derive from icon size
                local iconSize = getCatOwnValue("iconSize", 64)
                return math.floor(iconSize * 0.32)
            end,
            enabled = isCustomAppearanceEnabled,
            onChange = function(val)
                BR.Config.Set("categorySettings." .. category .. ".textSize", val)
            end,
        })
        catTextSizeHolder:SetPoint("TOPLEFT", CAT_COL2, -48)

        local catTextColorHolder = Components.ColorSwatch(appFrame, {
            hasOpacity = true,
            get = function()
                local tc = getCatOwnValue("textColor", { 1, 1, 1 })
                local ta = getCatOwnValue("textAlpha", 1)
                return tc[1], tc[2], tc[3], ta
            end,
            enabled = isCustomAppearanceEnabled,
            onChange = function(r, g, b, a)
                BR.Config.SetMulti({
                    ["categorySettings." .. category .. ".textColor"] = { r, g, b },
                    ["categorySettings." .. category .. ".textAlpha"] = a or 1,
                })
            end,
        })
        catTextColorHolder:SetPoint("LEFT", catTextSizeHolder, "RIGHT", 12, 0) -- aligns alpha % with slider values

        local gridHeight = 72 -- 3 rows default
        if category == "consumable" then
            -- Row 4: Glow enable + threshold + type + color (consumable only)
            local function isGlowEnabled()
                return isCustomAppearanceEnabled() and getCatOwnValue("showExpirationGlow", true) ~= false
            end

            local catGlowCheckHolder = Components.Checkbox(appFrame, {
                label = "Glow",
                get = function()
                    return getCatOwnValue("showExpirationGlow", true) ~= false
                end,
                enabled = isCustomAppearanceEnabled,
                onChange = function(checked)
                    BR.Config.Set("categorySettings." .. category .. ".showExpirationGlow", checked)
                    Components.RefreshAll()
                end,
            })
            catGlowCheckHolder:SetPoint("TOPLEFT", 0, -72)

            local catGlowThresholdHolder = Components.Slider(appFrame, {
                min = 1,
                max = 45,
                step = 5,
                suffix = " min",
                get = function()
                    return getCatOwnValue("expirationThreshold", 15)
                end,
                enabled = isGlowEnabled,
                onChange = function(val)
                    BR.Config.Set("categorySettings." .. category .. ".expirationThreshold", val)
                end,
            })
            catGlowThresholdHolder:SetPoint("LEFT", catGlowCheckHolder.checkbox, "RIGHT", 40, 0)

            local catGlowTypeOptions = {}
            for gi, gt in ipairs(GlowTypes) do
                catGlowTypeOptions[gi] = { label = gt.name, value = gi }
            end

            local catGlowTypeHolder = Components.Dropdown(appFrame, {
                label = "Type:",
                labelWidth = 34,
                options = catGlowTypeOptions,
                get = function()
                    return getCatOwnValue("glowType", 1)
                end,
                enabled = isGlowEnabled,
                width = 95,
                onChange = function(val)
                    BR.Config.Set("categorySettings." .. category .. ".glowType", val)
                end,
            }, "BuffReminders_" .. category .. "_GlowTypeDropdown")
            catGlowTypeHolder:SetPoint("TOPLEFT", CAT_COL2, -72)

            local catGlowColorHolder = Components.ColorSwatch(appFrame, {
                hasOpacity = true,
                get = function()
                    local c = getCatOwnValue("glowColor", Glow.DEFAULT_COLOR)
                    return c[1], c[2], c[3], c[4] or 1
                end,
                enabled = isGlowEnabled,
                onChange = function(r, g, b, a)
                    BR.Config.Set("categorySettings." .. category .. ".glowColor", { r, g, b, a or 1 })
                end,
            })
            catGlowColorHolder:SetPoint("TOPLEFT", catTextColorHolder, "TOPLEFT", 0, -24)

            gridHeight = 96 -- 4 rows with glow
        end

        -- Advance past the appFrame grid and finalize section height
        catLayout:Space(gridHeight)
        catLayout:SetX(0)

        section:SetContentHeight(math.abs(catLayout:GetY()) + 10)
        table.insert(categorySections, section)
        previousSection = section
    end

    UpdateAppearanceContentHeight()

    -- ========== SETTINGS TAB ==========
    -- Simple frame (not scrollable) - content fits without scrolling
    local settingsContent = CreateFrame("Frame", nil, panel)
    settingsContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    settingsContent:SetSize(PANEL_WIDTH, 300)
    settingsContent:Hide()
    contentContainers.settings = settingsContent

    local setX = COL_PADDING
    local setLayout = Components.VerticalLayout(settingsContent, { x = setX, y = -10 })

    -- General Settings section
    LayoutSectionHeader(setLayout, settingsContent, "Display Behavior")

    local groupHolder = Components.Checkbox(settingsContent, {
        label = "Show only in group/raid",
        get = function()
            return BuffRemindersDB.showOnlyInGroup ~= false
        end,
        onChange = function(checked)
            BuffRemindersDB.showOnlyInGroup = checked
            UpdateDisplay()
        end,
    })
    setLayout:Add(groupHolder, nil, COMPONENT_GAP)

    local restingHolder = Components.Checkbox(settingsContent, {
        label = "Hide while resting",
        get = function()
            return BuffRemindersDB.hideWhileResting == true
        end,
        tooltip = { title = "Hide while resting", desc = "Hide buff reminders while in inns or capital cities" },
        onChange = function(checked)
            BuffRemindersDB.hideWhileResting = checked
            UpdateDisplay()
        end,
    })
    setLayout:Add(restingHolder, nil, COMPONENT_GAP)

    local readyCheckHolder = Components.Checkbox(settingsContent, {
        label = "Show only on ready check",
        get = function()
            return BuffRemindersDB.showOnlyOnReadyCheck == true
        end,
        onChange = function(checked)
            BuffRemindersDB.showOnlyOnReadyCheck = checked
            UpdateDisplay()
            Components.RefreshAll()
        end,
    })
    setLayout:Add(readyCheckHolder, nil, COMPONENT_GAP)

    local readyDurationHolder = Components.Slider(settingsContent, {
        label = "Duration",
        min = 10,
        max = 30,
        get = function()
            return BuffRemindersDB.readyCheckDuration or 15
        end,
        enabled = function()
            return BuffRemindersDB.showOnlyOnReadyCheck == true
        end,
        suffix = "s",
        labelWidth = 55,
        sliderWidth = 70,
        onChange = function(val)
            BuffRemindersDB.readyCheckDuration = val
        end,
    })
    setLayout:SetX(setX + 20)
    setLayout:Add(readyDurationHolder, nil, COMPONENT_GAP)
    setLayout:SetX(setX)

    local trackingModeHolder = Components.Dropdown(settingsContent, {
        label = "Buff tracking",
        width = 200,
        options = {
            {
                value = "all",
                label = "All buffs, all players",
                desc = "Show all raid and presence buffs for every class, tracking full group coverage.",
            },
            {
                value = "my_buffs",
                label = "Only my buffs, all players",
                desc = "Only show buffs your class can provide. Still tracks full group coverage.",
            },
            {
                value = "personal",
                label = "Only buffs I need",
                desc = "Show all buff types, but only check whether you personally have them. No group counts.",
            },
            {
                value = "smart",
                label = "Smart",
                desc = "Buffs your class provides track full group coverage. Other class buffs only check you personally.",
            },
        },
        get = function()
            return BR.Config.Get("buffTrackingMode", "all")
        end,
        tooltip = {
            title = "Buff tracking mode",
            desc = "Controls which raid and presence buffs are shown, and whether they track the full group or only you.",
        },
        onChange = function(val)
            BR.Config.Set("buffTrackingMode", val)
            UpdateDisplay()
        end,
    })
    setLayout:Add(trackingModeHolder, nil, COMPONENT_GAP)

    local loginMsgHolder = Components.Checkbox(settingsContent, {
        label = "Show login messages",
        get = function()
            return BuffRemindersDB.showLoginMessages ~= false
        end,
        onChange = function(checked)
            BuffRemindersDB.showLoginMessages = checked
        end,
    })
    setLayout:Add(loginMsgHolder)

    -- ========== IMPORT/EXPORT TAB ==========
    -- Use simple frame (not scrollable) to avoid nested scroll frame issues with edit boxes
    local profilesContent = CreateFrame("Frame", nil, panel)
    profilesContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    profilesContent:SetSize(PANEL_WIDTH, 500)
    profilesContent:Hide()
    contentContainers.profiles = profilesContent

    local profX = COL_PADDING
    local profLayout = Components.VerticalLayout(profilesContent, { x = profX, y = -10 })

    local formatWarning = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formatWarning:SetText("|cffff9900Note:|r Export string format changed in v2.6.1. Old strings are incompatible.")
    formatWarning:SetWidth(PANEL_WIDTH - COL_PADDING * 2)
    formatWarning:SetJustifyH("LEFT")
    profLayout:AddText(formatWarning, 12, SECTION_GAP)

    -- Export section
    LayoutSectionHeader(profLayout, profilesContent, "Export Settings")

    local exportDesc = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    exportDesc:SetText("Copy the string below to share your settings with others.")
    profLayout:AddText(exportDesc, 12, COMPONENT_GAP)

    local exportTextArea = Components.TextArea(profilesContent, {
        width = PANEL_WIDTH - COL_PADDING * 2 - SCROLLBAR_WIDTH,
        height = 80,
    })
    profLayout:Add(exportTextArea, 80, COMPONENT_GAP)

    local exportButton = CreateButton(profilesContent, "Export", function()
        local exportString, err = BuffReminders:Export()
        if exportString then
            exportTextArea:SetText(exportString)
            exportTextArea:HighlightText()
            exportTextArea:SetFocus()
        else
            exportTextArea:SetText("Error: " .. (err or "Failed to export"))
        end
    end)
    profLayout:Add(exportButton, 22, SECTION_GAP)

    -- Import section
    LayoutSectionHeader(profLayout, profilesContent, "Import Settings")

    local importDesc = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    importDesc:SetText("Paste a settings string below. This will overwrite your current settings.")
    profLayout:AddText(importDesc, 12, COMPONENT_GAP)

    local importTextArea = Components.TextArea(profilesContent, {
        width = PANEL_WIDTH - COL_PADDING * 2 - SCROLLBAR_WIDTH,
        height = 80,
    })
    profLayout:Add(importTextArea, 80, COMPONENT_GAP)

    local importStatus = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importStatus:SetWidth(PANEL_WIDTH - COL_PADDING * 2 - 120)
    importStatus:SetJustifyH("LEFT")
    importStatus:SetText("")

    local importButton = CreateButton(profilesContent, "Import", function()
        local importString = importTextArea:GetText()
        local success, err = BuffReminders:Import(importString)
        if success then
            importStatus:SetText("|cff00ff00Settings imported successfully!|r")
            StaticPopup_Show("BUFFREMINDERS_RELOAD_UI")
        else
            importStatus:SetText("|cffff0000Error: " .. (err or "Unknown error") .. "|r")
        end
    end)
    profLayout:Add(importButton, 22)
    importStatus:SetPoint("LEFT", importButton, "RIGHT", 10, 0)

    profilesContent:SetHeight(math.abs(profLayout:GetY()) + 50)

    -- ========== BOTTOM BUTTONS ==========
    local bottomFrame = CreateFrame("Frame", nil, panel)
    bottomFrame:SetPoint("BOTTOMLEFT", 0, 0)
    bottomFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    bottomFrame:SetHeight(45)
    bottomFrame:SetFrameLevel(panel:GetFrameLevel() + 10)

    local separator = bottomFrame:CreateTexture(nil, "ARTWORK")
    separator:SetSize(PANEL_WIDTH - 40, 1)
    separator:SetPoint("TOP", 0, -5)
    separator:SetColorTexture(0.3, 0.3, 0.3, 1)

    local btnHolder = CreateFrame("Frame", nil, bottomFrame)
    btnHolder:SetPoint("TOP", separator, "BOTTOM", 0, -8)
    btnHolder:SetSize(1, 22)

    local BTN_WIDTH = 80

    local lockBtn = CreateButton(btnHolder, "Unlock", function()
        BR.Display.ToggleLock()
        Components.RefreshAll()
    end, { title = "Lock / Unlock", desc = "Unlock to show anchor handles for repositioning buff frames." })
    lockBtn:SetSize(BTN_WIDTH, 22)
    lockBtn:SetPoint("RIGHT", btnHolder, "CENTER", -4, 0)

    function lockBtn:Refresh()
        self.text:SetText(BuffRemindersDB.locked and "Unlock" or "Lock")
    end
    lockBtn:Refresh()
    table.insert(BR.RefreshableComponents, lockBtn)

    local testBtn = CreateButton(btnHolder, "Stop Test", function(self)
        local isOn = ToggleTestMode()
        self.text:SetText(isOn and "Stop Test" or "Test")
    end, {
        title = "Test icon's appearance",
        desc = "Shows ALL buffs regardless of what you selected in the buffs section.",
    })
    testBtn:SetText("Test")
    testBtn:SetSize(BTN_WIDTH, 22)
    testBtn:SetPoint("LEFT", btnHolder, "CENTER", 4, 0)
    panel.testBtn = testBtn

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
        -- Refresh custom buffs
        if optionsPanel.RenderCustomBuffRows then
            optionsPanel.RenderCustomBuffRows()
        end
        -- Update button texts
        if BR.Display.IsTestMode() then
            optionsPanel.testBtn.text:SetText("Stop Test")
        else
            optionsPanel.testBtn.text:SetText("Test")
        end
        optionsPanel:Show()
    end
end

-- Glow demo panel
ShowGlowDemo = function()
    -- Clean up old panel (recreate to reflect current color)
    if glowDemoPanel then
        glowDemoPanel:Hide()
        glowDemoPanel = nil
    end

    local ICON_SIZE = 64
    local SPACING = 20
    local numTypes = #GlowTypes

    local demoPanel = CreatePanel("BuffRemindersGlowDemo", numTypes * (ICON_SIZE + SPACING) + SPACING, ICON_SIZE + 70, {
        strata = "TOOLTIP",
    })

    local demoTitle = demoPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    demoTitle:SetPoint("TOP", 0, -8)
    demoTitle:SetText("|cffffcc00Glow Types Preview|r")

    local demoCloseBtn = CreateButton(demoPanel, "x", function()
        demoPanel:Hide()
    end)
    demoCloseBtn:SetSize(22, 22)
    demoCloseBtn:SetPoint("TOPRIGHT", -5, -5)

    local color = BR.Config.Get("defaults.glowColor", Glow.DEFAULT_COLOR)
    local demoFrames = {}

    for i, gt in ipairs(GlowTypes) do
        local iconFrame = CreateFrame("Frame", nil, demoPanel)
        iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
        iconFrame:SetPoint("TOPLEFT", SPACING + (i - 1) * (ICON_SIZE + SPACING), -30)

        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
        icon:SetTexture(GetBuffTexture(1459))

        local border = iconFrame:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", -DEFAULT_BORDER_SIZE, DEFAULT_BORDER_SIZE)
        border:SetPoint("BOTTOMRIGHT", DEFAULT_BORDER_SIZE, -DEFAULT_BORDER_SIZE)
        border:SetColorTexture(0, 0, 0, 1)

        Glow.Start(iconFrame, i, color, "BR_demo_" .. i)
        demoFrames[i] = iconFrame

        local typeLabel = demoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        typeLabel:SetPoint("TOP", iconFrame, "BOTTOM", 0, -4)
        typeLabel:SetText(gt.name)
        typeLabel:SetWidth(ICON_SIZE + 10)
    end

    -- Clean up glows when panel hides
    demoPanel:SetScript("OnHide", function()
        for i in ipairs(GlowTypes) do
            if demoFrames[i] then
                Glow.StopAll(demoFrames[i], "BR_demo_" .. i)
            end
        end
    end)

    glowDemoPanel = demoPanel
end

-- Delete confirmation dialog for custom buffs
StaticPopupDialogs["BUFFREMINDERS_DELETE_CUSTOM"] = {
    text = 'Delete custom buff "%s"?',
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(_, data)
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

StaticPopupDialogs["BUFFREMINDERS_DISCORD_URL"] = {
    text = "Join the BuffReminders Discord!\nCopy the URL below (Ctrl+C):",
    button1 = "Close",
    hasEditBox = true,
    editBoxWidth = 250,
    OnShow = function(self)
        self.EditBox:SetText("https://discord.gg/qezQ2hXJJ7")
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Custom buff add/edit modal dialog
ShowCustomBuffModal = function(existingKey, refreshPanelCallback)
    if customBuffModal then
        customBuffModal:Hide()
    end

    local MODAL_WIDTH = 340
    local BASE_HEIGHT = 409
    local ROW_HEIGHT = 26
    local CONTENT_LEFT = 20
    local ROWS_START_Y = -60
    local editingBuff = existingKey and BuffRemindersDB.customBuffs[existingKey] or nil

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

    local spellRows, nameBox, missingBox

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

    local modalTitle = modal:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    modalTitle:SetPoint("TOP", 0, -12)
    modalTitle:SetText(editingBuff and "Edit Custom Buff" or "Add Custom Buff")

    local modalCloseBtn = CreateButton(modal, "x", function()
        modal:Hide()
    end)
    modalCloseBtn:SetSize(22, 22)
    modalCloseBtn:SetPoint("TOPRIGHT", -5, -5)

    local spellIdsLabel = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spellIdsLabel:SetPoint("TOPLEFT", CONTENT_LEFT, -40)
    spellIdsLabel:SetText("Spell IDs:")

    spellRows = {}

    local addSpellBtn, sectionsFrame
    local showWhenActiveToggle, invertGlowToggle
    local classDropdownHolder
    local specDropdownHolder

    local function UpdateLayout()
        local rowCount = #spellRows

        for i, rowData in ipairs(spellRows) do
            rowData.frame:ClearAllPoints()
            rowData.frame:SetPoint("TOPLEFT", modal, "TOPLEFT", CONTENT_LEFT, ROWS_START_Y - ((i - 1) * ROW_HEIGHT))
            if rowCount > 1 then
                rowData.removeBtn:Show()
            else
                rowData.removeBtn:Hide()
            end
        end

        local addBtnY = ROWS_START_Y - (rowCount * ROW_HEIGHT) - 4
        addSpellBtn:ClearAllPoints()
        addSpellBtn:SetPoint("TOPLEFT", modal, "TOPLEFT", CONTENT_LEFT, addBtnY)

        sectionsFrame:ClearAllPoints()
        sectionsFrame:SetPoint("TOPLEFT", modal, "TOPLEFT", CONTENT_LEFT, addBtnY - 28)

        local extraRows = math.max(0, rowCount - 1)
        modal:SetHeight(BASE_HEIGHT + (extraRows * ROW_HEIGHT))
    end

    local function CreateSpellRow(initialSpellID)
        local rowFrame = CreateFrame("Frame", nil, modal)
        rowFrame:SetSize(MODAL_WIDTH - 40, ROW_HEIGHT - 2)

        local editBox = CreateFrame("EditBox", nil, rowFrame)
        editBox:SetFontObject("GameFontHighlightSmall")
        editBox:SetAutoFocus(false)
        local editContainer = StyleEditBox(editBox)
        editContainer:SetSize(70, 20)
        editContainer:SetPoint("LEFT", 0, 0)
        if initialSpellID then
            editBox:SetText(tostring(initialSpellID))
        end

        local doLookup -- forward declare for onClick
        local lookupBtn = CreateButton(rowFrame, "Lookup", function()
            doLookup()
        end)
        lookupBtn:SetSize(55, 20)
        lookupBtn:SetPoint("LEFT", editContainer, "RIGHT", 5, 0)

        local icon = CreateBuffIcon(rowFrame, 18)
        icon:SetPoint("LEFT", lookupBtn, "RIGHT", 8, 0)
        icon:Hide()

        local nameText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        nameText:SetPoint("RIGHT", rowFrame, "RIGHT", -28, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)

        local removeBtn = CreateButton(rowFrame, "-", nil)
        removeBtn:SetSize(22, 20)
        removeBtn:SetPoint("RIGHT", 0, 0)
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

        doLookup = function()
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
        end

        table.insert(spellRows, rowData)

        if initialSpellID then
            doLookup()
        end

        return rowData
    end

    addSpellBtn = CreateButton(modal, "+ Add Spell ID", function()
        CreateSpellRow(nil)
        UpdateLayout()
    end)

    -- Sections frame (always visible, below add-spell button)
    sectionsFrame = CreateFrame("Frame", nil, modal)
    sectionsFrame:SetSize(MODAL_WIDTH - 40, 240)

    local function CreateSeparator(parent, yOff)
        local line = parent:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", 0, yOff)
        line:SetPoint("RIGHT", 0, 0)
        line:SetColorTexture(0.25, 0.25, 0.25, 0.8)
    end

    -- Display section
    CreateSeparator(sectionsFrame, 0)
    local displayLabel = sectionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    displayLabel:SetPoint("TOPLEFT", 0, -9)
    displayLabel:SetText("Display")

    local nameHolder = Components.TextInput(sectionsFrame, {
        label = "Display Name:",
        value = editingBuff and editingBuff.name or "",
        width = 150,
        labelWidth = 85,
    })
    nameHolder:SetPoint("TOPLEFT", 0, -25)
    nameBox = nameHolder.editBox

    local missingHolder = Components.TextInput(sectionsFrame, {
        label = "Missing Text:",
        value = editingBuff and editingBuff.missingText and editingBuff.missingText:gsub("\n", "\\n") or "",
        width = 80,
        labelWidth = 85,
    })
    missingHolder:SetPoint("TOPLEFT", 0, -49)
    missingBox = missingHolder.editBox

    local missingHint = sectionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    missingHint:SetPoint("LEFT", missingHolder, "RIGHT", 5, 0)
    missingHint:SetText("(use \\n for newline)")

    -- Behavior section
    CreateSeparator(sectionsFrame, -73)
    local behaviorLabel = sectionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    behaviorLabel:SetPoint("TOPLEFT", 0, -82)
    behaviorLabel:SetText("Behavior")

    showWhenActiveToggle = Components.Toggle(sectionsFrame, {
        label = editingBuff and editingBuff.showWhenPresent and "Show when active" or "Show when missing",
        checked = editingBuff and editingBuff.showWhenPresent or false,
        onChange = function(isChecked)
            if isChecked then
                showWhenActiveToggle.label:SetText("Show when active")
                missingHolder.label:SetText("Active Text:")
            else
                showWhenActiveToggle.label:SetText("Show when missing")
                missingHolder.label:SetText("Missing Text:")
            end
        end,
    })
    showWhenActiveToggle:SetPoint("TOPLEFT", 0, -98)
    if editingBuff and editingBuff.showWhenPresent then
        missingHolder.label:SetText("Active Text:")
    end

    invertGlowToggle = Components.Toggle(sectionsFrame, {
        label = editingBuff and editingBuff.invertGlow and "Detect when not glowing" or "Detect when glowing",
        checked = not (editingBuff and editingBuff.invertGlow or false),
        onChange = function(isChecked)
            if isChecked then
                invertGlowToggle.label:SetText("Detect when glowing")
            else
                invertGlowToggle.label:SetText("Detect when not glowing")
            end
        end,
    })
    invertGlowToggle:SetPoint("TOPLEFT", 0, -120)

    -- Filtering section
    CreateSeparator(sectionsFrame, -144)
    local filteringLabel = sectionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filteringLabel:SetPoint("TOPLEFT", 0, -153)
    filteringLabel:SetText("Filtering")

    local classOptions = {
        { value = nil, label = "Any" },
        { value = "DEATHKNIGHT", label = "Death Knight" },
        { value = "DEMONHUNTER", label = "Demon Hunter" },
        { value = "DRUID", label = "Druid" },
        { value = "EVOKER", label = "Evoker" },
        { value = "HUNTER", label = "Hunter" },
        { value = "MAGE", label = "Mage" },
        { value = "MONK", label = "Monk" },
        { value = "PALADIN", label = "Paladin" },
        { value = "PRIEST", label = "Priest" },
        { value = "ROGUE", label = "Rogue" },
        { value = "SHAMAN", label = "Shaman" },
        { value = "WARLOCK", label = "Warlock" },
        { value = "WARRIOR", label = "Warrior" },
    }

    local function CreateSpecDropdown(classToken, selectedSpecId)
        if specDropdownHolder then
            specDropdownHolder:Hide()
            specDropdownHolder = nil
        end
        if not classToken then
            return
        end
        local specOptions = BR.CLASS_SPEC_OPTIONS[classToken]
        if not specOptions then
            return
        end
        specDropdownHolder = Components.Dropdown(sectionsFrame, {
            label = "Only for spec:",
            options = specOptions,
            selected = selectedSpecId,
            width = 130,
            onChange = function() end,
        })
        specDropdownHolder:SetPoint("TOPLEFT", 0, -197)
    end

    classDropdownHolder = Components.Dropdown(sectionsFrame, {
        label = "Only for class:",
        options = classOptions,
        selected = editingBuff and editingBuff.class or nil,
        width = 130,
        maxItems = 10,
        onChange = function(value)
            CreateSpecDropdown(value, nil)
        end,
    }, "BuffRemindersCustomClassDropdown")
    classDropdownHolder:SetPoint("TOPLEFT", 0, -169)

    -- Initialize spec dropdown for editing existing buff
    if editingBuff and editingBuff.class then
        CreateSpecDropdown(editingBuff.class, editingBuff.requireSpecId)
    end

    local saveError = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    saveError:SetPoint("BOTTOMLEFT", 20, 42)
    saveError:SetWidth(MODAL_WIDTH - 120)
    saveError:SetJustifyH("LEFT")
    saveError:SetTextColor(1, 0.3, 0.3)

    local cancelBtn = CreateButton(modal, "Cancel", function()
        modal:Hide()
    end)
    cancelBtn:SetPoint("BOTTOMRIGHT", -20, 15)

    -- Delete button (only when editing existing buff)
    if existingKey and editingBuff then
        local buffName = editingBuff.name or existingKey
        local deleteBtn = CreateButton(modal, "Delete", function()
            modal:Hide()
            StaticPopup_Show("BUFFREMINDERS_DELETE_CUSTOM", buffName, nil, {
                key = existingKey,
                refreshPanel = refreshPanelCallback,
            })
        end)
        deleteBtn:SetPoint("BOTTOMLEFT", 20, 15)
    end

    local saveBtn = CreateButton(modal, "Save", function()
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

        local spellIDValue = #validatedIDs == 1 and validatedIDs[1] or validatedIDs
        local key = existingKey or GenerateCustomBuffKey(spellIDValue)
        local displayName = nameBox:GetText()
        if displayName == "" then
            displayName = firstName or ("Spell " .. validatedIDs[1])
        end

        local missingTextValue = strtrim(missingBox:GetText())
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
            class = classDropdownHolder:GetValue(),
            requireSpecId = specDropdownHolder and specDropdownHolder:GetValue() or nil,
            showWhenPresent = showWhenActiveToggle:GetChecked() or nil,
            invertGlow = (not invertGlowToggle:GetChecked()) or nil,
        }

        BuffRemindersDB.customBuffs[key] = customBuff

        if not existingKey then
            CreateCustomBuffFrameRuntime(customBuff)
        else
            UpdateCustomBuffFrame(key, spellIDValue, displayName)
        end

        modal:Hide()
        if refreshPanelCallback then
            refreshPanelCallback()
        end
        UpdateDisplay()
    end)
    saveBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)

    if #existingSpellIDs > 0 then
        for _, spellID in ipairs(existingSpellIDs) do
            CreateSpellRow(spellID)
        end
    else
        CreateSpellRow(nil)
    end

    UpdateLayout()

    customBuffModal = modal
    modal:Show()
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

BR.Options = {
    Toggle = ToggleOptions,
}
