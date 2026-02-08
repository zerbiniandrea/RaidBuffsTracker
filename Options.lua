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

-- Glow styles (for ShowGlowDemo)
local GlowStyles = BR.GlowStyles

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
        scrollFrame:SetPoint("BOTTOMRIGHT", 0, 50)
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
                container:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 50)
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
                UpdateDisplay()
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
    customNote:SetText("(track any buff by spell ID)")
    buffsRightY = buffsRightY - 14

    local customBuffsContainer = CreateFrame("Frame", nil, buffsContent)
    customBuffsContainer:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    customBuffsContainer:SetSize(COL_WIDTH, 200)

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
                    UpdateDisplay()
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
        addBtn:SetPoint("TOPLEFT", 0, rowY - 4)
        table.insert(panel.customBuffRows, addBtn)

        customBuffsContainer:SetHeight(math.abs(rowY) + 30)

        return rowY
    end

    panel.RenderCustomBuffRows = RenderCustomBuffRows
    local customEndY = RenderCustomBuffRows()
    buffsRightY = buffsRightY + customEndY - 20

    -- Set buffs content height (use the taller column)
    buffsContent:SetHeight(math.max(math.abs(buffsLeftY), math.abs(buffsRightY)) + 10)

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
        label = "",
        labelWidth = 0,
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

    local resetMainPosBtn = CreateButton(appearanceContent, "Reset Main Frame Position", function()
        local mainDefaults = defaults.categorySettings.main
        if mainDefaults and mainDefaults.position then
            BR.Display.ResetMainFramePosition(mainDefaults.position.x, mainDefaults.position.y)
        end
    end, { title = "Reset Position", desc = "Reset the main buff frame to center of screen." })
    appLayout:Add(resetMainPosBtn, 22, SECTION_GAP)

    -- Expiration Glow section
    LayoutSectionHeader(appLayout, appearanceContent, "Expiration Glow")

    local defGlowHolder = Components.Checkbox(appearanceContent, {
        label = "Show expiration glow",
        get = function()
            return BuffRemindersDB.defaults and BuffRemindersDB.defaults.showExpirationGlow ~= false
        end,
        onChange = function(checked)
            BR.Config.Set("defaults.showExpirationGlow", checked)
            Components.RefreshAll()
        end,
    })
    appLayout:Add(defGlowHolder, nil, COMPONENT_GAP)

    local function isExpirationGlowEnabled()
        return BuffRemindersDB.defaults and BuffRemindersDB.defaults.showExpirationGlow ~= false
    end

    local defThresholdHolder = Components.Slider(appearanceContent, {
        label = "Threshold",
        min = 1,
        max = 15,
        get = function()
            return BuffRemindersDB.defaults and BuffRemindersDB.defaults.expirationThreshold or 15
        end,
        enabled = isExpirationGlowEnabled,
        suffix = " min",
        onChange = function(val)
            BR.Config.Set("defaults.expirationThreshold", val)
        end,
    })
    appLayout:SetX(appX + 20)
    appLayout:Add(defThresholdHolder, nil, COMPONENT_GAP)

    -- Style dropdown (on its own line)
    local styleOptions = {}
    for i, style in ipairs(GlowStyles) do
        styleOptions[i] = { label = style.name, value = i }
    end

    local defStyleHolder = Components.Dropdown(appearanceContent, {
        label = "Style:",
        options = styleOptions,
        get = function()
            return BuffRemindersDB.defaults and BuffRemindersDB.defaults.glowStyle or 1
        end,
        enabled = isExpirationGlowEnabled,
        width = 100,
        onChange = function(val)
            BR.Config.Set("defaults.glowStyle", val)
        end,
    }, "BuffRemindersDefStyleDropdown")
    appLayout:Add(defStyleHolder, nil, COMPONENT_GAP + DROPDOWN_EXTRA)
    appLayout:SetX(appX)

    local previewBtn = CreateButton(appearanceContent, "Preview", function()
        ShowGlowDemo()
    end)
    previewBtn:SetPoint("LEFT", defStyleHolder, "RIGHT", 10, 0)

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

        -- Hide while mounted (pet only)
        if category == "pet" then
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
        end

        -- "BUFF!" text (raid only)
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
        catLayout:SetX(10)
        catLayout:Add(priorityHolder, nil, COMPONENT_GAP)

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

        -- Direction and Reset button on same line
        local dirHolder = Components.DirectionButtons(catContent, {
            get = function()
                local catSettings = db.categorySettings and db.categorySettings[category]
                local val = catSettings and catSettings.growDirection
                if val ~= nil then
                    return val
                end
                return db.defaults and db.defaults.growDirection or "CENTER"
            end,
            enabled = isCategorySplitEnabled,
            onChange = function(dir)
                BR.Config.Set("categorySettings." .. category .. ".growDirection", dir)
            end,
        })
        catLayout:Add(dirHolder, nil, COMPONENT_GAP + DROPDOWN_EXTRA)

        local resetBtn = CreateButton(catContent, "Reset Pos", function()
            local catDefaults = defaults.categorySettings[category]
            if catDefaults and catDefaults.position then
                ResetCategoryFramePosition(category, catDefaults.position.x, catDefaults.position.y)
            end
        end)
        resetBtn:SetPoint("LEFT", dirHolder, "RIGHT", 10, 0)
        resetBtn:SetEnabled(IsCategorySplit(category))

        local origSplitClick = splitHolder.checkbox:GetScript("OnClick")
        splitHolder.checkbox:SetScript("OnClick", function(self)
            if origSplitClick then
                origSplitClick(self)
            end
            resetBtn:SetEnabled(IsCategorySplit(category))
            Components.RefreshAll()
        end)

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
                    }
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
                end
                db.categorySettings[category].useCustomAppearance = checked
                UpdateVisuals()
                Components.RefreshAll()
            end,
        })
        catLayout:Add(useCustomAppHolder, nil, COMPONENT_GAP)

        -- Appearance controls (3-row grid with fixed columns)
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
            label = "",
            labelWidth = 0,
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

        -- Advance past the 3-row appFrame grid (72px) and finalize section height
        catLayout:Space(72)
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

    local playerClassHolder = Components.Checkbox(settingsContent, {
        label = "Show only my class buffs",
        get = function()
            return BuffRemindersDB.showOnlyPlayerClassBuff == true
        end,
        tooltip = { title = "Show only my class buffs", desc = "Only show buffs that your class can provide" },
        onChange = function(checked)
            BuffRemindersDB.showOnlyPlayerClassBuff = checked
            UpdateDisplay()
        end,
    })
    setLayout:Add(playerClassHolder, nil, COMPONENT_GAP)

    local playerMissingHolder = Components.Checkbox(settingsContent, {
        label = "Show only buffs I'm missing",
        get = function()
            return BuffRemindersDB.showOnlyPlayerMissing == true
        end,
        tooltip = { title = "Show only buffs I'm missing", desc = "Only show buffs you personally are missing" },
        onChange = function(checked)
            BuffRemindersDB.showOnlyPlayerMissing = checked
            UpdateDisplay()
        end,
    })
    setLayout:Add(playerMissingHolder, nil, COMPONENT_GAP)

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
    if glowDemoPanel then
        glowDemoPanel:SetShown(not glowDemoPanel:IsShown())
        return
    end

    local ICON_SIZE = 64
    local SPACING = 20
    local numStyles = #GlowStyles

    local demoPanel =
        CreatePanel("BuffRemindersGlowDemo", numStyles * (ICON_SIZE + SPACING) + SPACING, ICON_SIZE + 70, {
            strata = "TOOLTIP",
        })

    local demoTitle = demoPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    demoTitle:SetPoint("TOP", 0, -8)
    demoTitle:SetText("|cffffcc00Glow Styles Preview|r")

    local demoCloseBtn = CreateButton(demoPanel, "x", function()
        demoPanel:Hide()
    end)
    demoCloseBtn:SetSize(22, 22)
    demoCloseBtn:SetPoint("TOPRIGHT", -5, -5)

    for i, style in ipairs(GlowStyles) do
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

        style.setup(iconFrame)
        if iconFrame.glowAnim then
            iconFrame.glowAnim:Play()
        end

        local styleLabel = demoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        styleLabel:SetPoint("TOP", iconFrame, "BOTTOM", 0, -4)
        styleLabel:SetText(style.name)
        styleLabel:SetWidth(ICON_SIZE + 10)
    end

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

        local missingTextValue = missingBox:GetText()
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
