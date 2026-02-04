local _, BR = ...

-- ============================================================================
-- OPTIONS PANEL
-- ============================================================================
-- Extracted from BuffReminders.lua for modularity.
-- This file loads AFTER BuffReminders.lua so BR.* exports are available.

-- Aliases from BR namespace
local Components = BR.Components
local SetupTooltip = BR.SetupTooltip
local CreateButton = BR.CreateButton
local CreatePanel = BR.CreatePanel
local CreateSectionHeader = BR.CreateSectionHeader
local CreateBuffIcon = BR.CreateBuffIcon

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
local Consumables = BUFF_TABLES.consumable

-- Glow styles (for ShowGlowDemo)
local GlowStyles = BR.GlowStyles

-- Export references from BuffReminders.lua
local defaults = BR.defaults
local CATEGORIES = BR.CATEGORIES

-- Helper function aliases
local GetBuffSettingKey = BR.Helpers.GetBuffSettingKey
local IsBuffEnabled = BR.Helpers.IsBuffEnabled
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
local ResetMainFramePosition = BR.Display.ResetMainFramePosition
local ResetCategoryFramePosition = BR.Display.ResetCategoryFramePosition
local ReparentBuffFrames = BR.CallbackRegistry.TriggerEvent
        and function()
            BR.CallbackRegistry:TriggerEvent("FramesReparent")
        end
    or function() end
local UpdateFallbackDisplay = BR.Display.UpdateFallback or function() end

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
-- OPTIONS PANEL (Two-Column Layout)
-- ============================================================================

local function CreateOptionsPanel()
    local PANEL_WIDTH = 540
    local COL_PADDING = 20
    local COL_WIDTH = (PANEL_WIDTH - COL_PADDING * 3) / 2 -- Two columns with padding
    local SECTION_SPACING = 12
    local ITEM_HEIGHT = 22

    local panel = CreatePanel("BuffRemindersOptions", PANEL_WIDTH, 400, { escClose = true })
    panel:Hide()

    -- Track all EditBoxes so we can clear focus when panel hides
    local panelEditBoxes = {} -- luacheck: ignore 431 (intentionally shadows module-level nil)
    Components.SetEditBoxesRef(panelEditBoxes)
    panel:SetScript("OnHide", function()
        for _, editBox in ipairs(panelEditBoxes) do
            editBox:ClearFocus()
        end
    end)

    -- Refresh all component values from DB when panel opens (OnShow pattern)
    panel:SetScript("OnShow", function()
        Components.RefreshAll()
    end)

    -- Addon icon
    local addonIcon = CreateBuffIcon(panel, 28, "Interface\\AddOns\\BuffReminders\\icon.tga")
    addonIcon:SetPoint("TOPLEFT", 12, -8)

    -- Title (next to icon)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", addonIcon, "RIGHT", 8, 0)
    title:SetText("BuffReminders")

    -- Version (next to title, smaller font)
    local version = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 6, 0)
    local addonVersion = C_AddOns.GetAddOnMetadata("BuffReminders", "Version") or ""
    version:SetText(addonVersion)

    -- Scale controls (top right area) - using buttons to avoid slider scaling issues
    -- Base scale is OPTIONS_BASE_SCALE (displayed as 100%), range is 80%-150%
    local BASE_SCALE = OPTIONS_BASE_SCALE
    local MIN_PCT, MAX_PCT = 80, 150
    local scaleDown, scaleUp

    local scaleValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleValue:SetPoint("TOPRIGHT", -70, -14)
    local currentScale = BuffRemindersDB.optionsPanelScale or BASE_SCALE
    local currentPct = math.floor(currentScale / BASE_SCALE * 100 + 0.5)
    scaleValue:SetText(currentPct .. "%")

    local function UpdateScale(delta)
        -- Use integer math to avoid floating point issues
        local oldPct = math.floor((BuffRemindersDB.optionsPanelScale or BASE_SCALE) / BASE_SCALE * 100 + 0.5)
        local newPct = math.max(MIN_PCT, math.min(MAX_PCT, oldPct + delta))
        local newScale = newPct / 100 * BASE_SCALE
        BuffRemindersDB.optionsPanelScale = newScale
        panel:SetScale(newScale)
        scaleValue:SetText(newPct .. "%")
        -- Disable buttons at limits
        scaleDown:SetEnabled(newPct > MIN_PCT)
        scaleUp:SetEnabled(newPct < MAX_PCT)
    end

    scaleDown = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scaleDown:SetSize(18, 18)
    scaleDown:SetPoint("RIGHT", scaleValue, "LEFT", -4, 0)
    scaleDown:SetText("-")
    scaleDown:SetScript("OnClick", function()
        UpdateScale(-10)
    end)
    scaleDown:SetEnabled(currentPct > MIN_PCT)

    scaleUp = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scaleUp:SetSize(18, 18)
    scaleUp:SetPoint("LEFT", scaleValue, "RIGHT", 4, 0)
    scaleUp:SetText("+")
    scaleUp:SetScript("OnClick", function()
        UpdateScale(10)
    end)
    scaleUp:SetEnabled(currentPct < MAX_PCT)

    -- Apply saved scale
    if BuffRemindersDB.optionsPanelScale then
        panel:SetScale(BuffRemindersDB.optionsPanelScale)
    end

    -- Close button (same style as scale buttons)
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("LEFT", scaleUp, "RIGHT", 8, 0)
    closeBtn:SetText("x")
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
    end)

    -- ========== TABS (flat style, sitting at top) ==========
    local tabButtons = {}
    local contentContainers = {}
    local TAB_HEIGHT = 22 -- Used for positioning separator and content

    local function SetActiveTab(tabName)
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
    end

    tabButtons.buffs = Components.Tab(panel, { name = "buffs", label = "Buffs" })
    tabButtons.custom = Components.Tab(panel, { name = "custom", label = "Custom Buffs" })
    tabButtons.appearance = Components.Tab(panel, { name = "appearance", label = "Appearance" })
    tabButtons.settings = Components.Tab(panel, { name = "settings", label = "Settings" })
    tabButtons.profiles = Components.Tab(panel, { name = "profiles", label = "Import/Export" })

    -- Position tabs below title bar
    tabButtons.buffs:SetPoint("TOPLEFT", panel, "TOPLEFT", COL_PADDING, -40)
    tabButtons.custom:SetPoint("LEFT", tabButtons.buffs, "RIGHT", 4, 0)
    tabButtons.appearance:SetPoint("LEFT", tabButtons.custom, "RIGHT", 4, 0)
    tabButtons.settings:SetPoint("LEFT", tabButtons.appearance, "RIGHT", 4, 0)
    tabButtons.profiles:SetPoint("LEFT", tabButtons.settings, "RIGHT", 4, 0)

    tabButtons.buffs:SetScript("OnClick", function()
        SetActiveTab("buffs")
    end)
    tabButtons.appearance:SetScript("OnClick", function()
        SetActiveTab("appearance")
    end)
    tabButtons.settings:SetScript("OnClick", function()
        SetActiveTab("settings")
    end)
    tabButtons.custom:SetScript("OnClick", function()
        SetActiveTab("custom")
    end)
    tabButtons.profiles:SetScript("OnClick", function()
        SetActiveTab("profiles")
    end)

    -- Separator line below tabs
    local tabSeparator = panel:CreateTexture(nil, "ARTWORK")
    tabSeparator:SetHeight(1)
    tabSeparator:SetPoint("TOPLEFT", COL_PADDING, -40 - TAB_HEIGHT)
    tabSeparator:SetPoint("TOPRIGHT", -COL_PADDING, -40 - TAB_HEIGHT)
    tabSeparator:SetColorTexture(0.3, 0.3, 0.3, 1)

    -- ========== CONTENT CONTAINERS ==========
    local CONTENT_TOP = -40 - TAB_HEIGHT - 16 -- Below tabs and separator with padding

    local buffsContent = CreateFrame("Frame", nil, panel)
    buffsContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    buffsContent:SetSize(PANEL_WIDTH, 400) -- Height adjusted later
    contentContainers.buffs = buffsContent

    -- Appearance tab uses a scroll frame for expandable content
    local appearanceScrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    appearanceScrollFrame:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    appearanceScrollFrame:SetPoint("BOTTOMRIGHT", -24, 50) -- Leave room for scrollbar and bottom buttons
    appearanceScrollFrame:SetClipsChildren(true) -- Clip content that overflows
    appearanceScrollFrame:Hide()
    contentContainers.appearance = appearanceScrollFrame

    -- Position the scrollbar properly
    local scrollBar = appearanceScrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", appearanceScrollFrame, "TOPRIGHT", -16, -16)
        scrollBar:SetPoint("BOTTOMLEFT", appearanceScrollFrame, "BOTTOMRIGHT", -16, 16)
    end

    local appearanceContent = CreateFrame("Frame", nil, appearanceScrollFrame)
    appearanceContent:SetSize(PANEL_WIDTH - 24, 400) -- Width minus scrollbar
    appearanceScrollFrame:SetScrollChild(appearanceContent)
    panel.appearanceScrollFrame = appearanceScrollFrame

    -- Update callback for category visibility changes (used by Components.CategoryHeader)
    local function OnCategoryVisibilityChange()
        if BR.Display.IsTestMode() then
            RefreshTestDisplay()
        else
            UpdateDisplay()
        end
    end

    -- Settings tab content
    local settingsContent = CreateFrame("Frame", nil, panel)
    settingsContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    settingsContent:SetSize(PANEL_WIDTH, 400)
    settingsContent:Hide()
    contentContainers.settings = settingsContent

    local customContent = CreateFrame("Frame", nil, panel)
    customContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    customContent:SetSize(PANEL_WIDTH, 400)
    customContent:Hide()
    contentContainers.custom = customContent

    local profilesContent = CreateFrame("Frame", nil, panel)
    profilesContent:SetPoint("TOPLEFT", 0, CONTENT_TOP)
    profilesContent:SetSize(PANEL_WIDTH, 400)
    profilesContent:Hide()
    contentContainers.profiles = profilesContent

    -- Import/Export UI
    local yOffset = -10

    -- Format change warning
    local formatWarning = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    formatWarning:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    formatWarning:SetText("|cffff9900Note:|r Export string format changed in v2.6.1. Old strings are incompatible.")
    formatWarning:SetWidth(PANEL_WIDTH - COL_PADDING * 2)
    formatWarning:SetJustifyH("LEFT")
    yOffset = yOffset - 20

    -- Export section
    local exportHeader = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exportHeader:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    exportHeader:SetText("|cffffcc00Export Settings|r")
    yOffset = yOffset - 20

    local exportDesc = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    exportDesc:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    exportDesc:SetText("Copy the string below to share your settings with others.")
    exportDesc:SetWidth(PANEL_WIDTH - COL_PADDING * 2)
    exportDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 30

    -- Export text box (scrollable, read-only)
    local exportScrollFrame = CreateFrame("ScrollFrame", nil, profilesContent, "UIPanelScrollFrameTemplate")
    exportScrollFrame:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    exportScrollFrame:SetSize(PANEL_WIDTH - COL_PADDING * 2 - 24, 80)

    local exportEditBox = CreateFrame("EditBox", nil, exportScrollFrame)
    exportEditBox:SetMultiLine(true)
    exportEditBox:SetFontObject("GameFontHighlightSmall")
    exportEditBox:SetWidth(PANEL_WIDTH - COL_PADDING * 2 - 24)
    exportEditBox:SetAutoFocus(false)
    exportEditBox:SetTextInsets(6, 6, 6, 6)
    exportEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    exportEditBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        local height =
            math.max(80, select(2, self:GetFont()) * math.max(1, select(2, string.gsub(text, "\n", "\n")) + 1) + 10)
        self:SetHeight(height)
    end)
    exportEditBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText() -- Auto-select all text when clicked
    end)
    exportScrollFrame:SetScrollChild(exportEditBox)

    -- Add background to export box
    local exportBg = exportScrollFrame:CreateTexture(nil, "BACKGROUND")
    exportBg:SetAllPoints()
    exportBg:SetColorTexture(0, 0, 0, 0.5)

    -- Add border to export box for better visibility
    local exportBorder = CreateFrame("Frame", nil, exportScrollFrame, "BackdropTemplate")
    exportBorder:SetAllPoints(exportScrollFrame)
    exportBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    exportBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    -- Export button
    local exportButton = CreateButton(profilesContent, "Export", function()
        local exportString, err = BuffReminders:Export()
        if exportString then
            exportEditBox:SetText(exportString)
            exportEditBox:HighlightText()
            exportEditBox:SetFocus()
        else
            exportEditBox:SetText("Error: " .. (err or "Failed to export"))
        end
    end)
    exportButton:SetPoint("TOPLEFT", COL_PADDING, yOffset - 90)

    yOffset = yOffset - 120

    -- Separator
    local importExportSeparator = profilesContent:CreateTexture(nil, "ARTWORK")
    importExportSeparator:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    importExportSeparator:SetSize(PANEL_WIDTH - COL_PADDING * 2, 1)
    importExportSeparator:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    yOffset = yOffset - 15

    -- Import section
    local importHeader = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    importHeader:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    importHeader:SetText("|cffffcc00Import Settings|r")
    yOffset = yOffset - 20

    local importDesc = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importDesc:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    importDesc:SetText("Paste a settings string below and click Import. This will overwrite your current settings.")
    importDesc:SetWidth(PANEL_WIDTH - COL_PADDING * 2)
    importDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 30

    -- Import text box (scrollable, editable)
    local importScrollFrame = CreateFrame("ScrollFrame", nil, profilesContent, "UIPanelScrollFrameTemplate")
    importScrollFrame:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    importScrollFrame:SetSize(PANEL_WIDTH - COL_PADDING * 2 - 24, 80)

    local importEditBox = CreateFrame("EditBox", nil, importScrollFrame)
    importEditBox:SetMultiLine(true)
    importEditBox:SetFontObject("GameFontHighlightSmall")
    importEditBox:SetWidth(PANEL_WIDTH - COL_PADDING * 2 - 24)
    importEditBox:SetAutoFocus(false)
    importEditBox:SetTextInsets(6, 6, 6, 6) -- Add padding for better readability
    importEditBox:EnableMouse(true) -- Ensure mouse clicks work
    importEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    importEditBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        local height =
            math.max(80, select(2, self:GetFont()) * math.max(1, select(2, string.gsub(text, "\n", "\n")) + 1) + 10)
        self:SetHeight(height)
    end)
    importScrollFrame:SetScrollChild(importEditBox)

    -- Add background to import box
    local importBg = importScrollFrame:CreateTexture(nil, "BACKGROUND")
    importBg:SetAllPoints()
    importBg:SetColorTexture(0, 0, 0, 0.5)

    -- Add border to import box with focus feedback
    local importBorder = CreateFrame("Frame", nil, importScrollFrame, "BackdropTemplate")
    importBorder:SetAllPoints(importScrollFrame)
    importBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    importBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    -- Change border color when focused/unfocused
    importEditBox:SetScript("OnEditFocusGained", function(self)
        importBorder:SetBackdropBorderColor(1, 0.82, 0, 1) -- Gold when focused
        importBg:SetColorTexture(0.1, 0.1, 0.1, 0.8) -- Darker background
        self:SetCursorPosition(self:GetText():len())
    end)
    importEditBox:SetScript("OnEditFocusLost", function(self)
        importBorder:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) -- Gray when unfocused
        importBg:SetColorTexture(0, 0, 0, 0.5) -- Lighter background
    end)

    yOffset = yOffset - 90

    -- Import button and status message
    local importStatus = profilesContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    importStatus:SetWidth(PANEL_WIDTH - COL_PADDING * 2 - 120)
    importStatus:SetJustifyH("LEFT")
    importStatus:SetText("")

    local importButton = CreateButton(profilesContent, "Import", function()
        local importString = importEditBox:GetText()
        local success, err = BuffReminders:Import(importString)

        if success then
            importStatus:SetText("|cff00ff00Settings imported successfully!|r")
            StaticPopup_Show("BUFFREMINDERS_RELOAD_UI")
        else
            importStatus:SetText("|cffff0000Error: " .. (err or "Unknown error") .. "|r")
        end
    end)
    importButton:SetPoint("TOPLEFT", COL_PADDING, yOffset)
    importStatus:SetPoint("LEFT", importButton, "RIGHT", 10, 0)

    panel.contentContainers = contentContainers

    -- Column anchors
    local leftColX = COL_PADDING
    local startY = 0 -- Relative to content container top

    panel.buffCheckboxes = {}

    -- ========== HELPER FUNCTIONS ==========

    -- Create buff checkbox (compact, for left column)
    -- spellIDs can be a single ID, a table of IDs (for multi-rank spells), or a table of tables (for grouped buffs with multiple icons)
    -- infoTooltip is optional: "Title|Description" format shows a "?" icon with tooltip
    -- iconOverride is optional: single texture ID or array of texture IDs to show instead of deriving icons from spellIDs
    local function CreateBuffCheckbox(x, y, spellIDs, key, displayName, infoTooltip, iconOverride)
        local cb = CreateFrame("CheckButton", nil, buffsContent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetChecked(BuffRemindersDB.enabledBuffs[key] ~= false)
        cb:SetScript("OnClick", function(self)
            BuffRemindersDB.enabledBuffs[key] = self:GetChecked()
            UpdateDisplay()
        end)

        -- Handle icons: either use iconOverride or derive from spellIDs
        local lastAnchor = cb
        if iconOverride then
            -- Icon override (single ID or array of IDs)
            local iconList = type(iconOverride) == "table" and iconOverride or { iconOverride }
            for _, textureID in ipairs(iconList) do
                local icon = CreateBuffIcon(buffsContent, 18, textureID)
                icon:SetPoint("LEFT", lastAnchor, lastAnchor == cb and "RIGHT" or "RIGHT", 2, 0)
                lastAnchor = icon
            end
        elseif spellIDs then
            -- Multiple icons for grouped buffs (dedupe by texture)
            local spellList = type(spellIDs) == "table" and spellIDs or { spellIDs }
            local seenTextures = {}
            for _, spellID in ipairs(spellList) do
                local texture = GetBuffTexture(spellID)
                if texture and not seenTextures[texture] then
                    seenTextures[texture] = true
                    local icon = CreateBuffIcon(buffsContent, 18, texture)
                    icon:SetPoint("LEFT", lastAnchor, lastAnchor == cb and "RIGHT" or "RIGHT", 2, 0)
                    lastAnchor = icon
                end
            end
        end

        local label = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        label:SetText(displayName)

        -- Add info tooltip icon if specified
        if infoTooltip then
            local infoIcon = buffsContent:CreateTexture(nil, "ARTWORK")
            infoIcon:SetSize(14, 14)
            infoIcon:SetPoint("LEFT", label, "RIGHT", 4, 0)
            infoIcon:SetAtlas("QuestNormal")
            -- Create invisible button for tooltip
            local infoBtn = CreateFrame("Button", nil, buffsContent)
            infoBtn:SetSize(14, 14)
            infoBtn:SetPoint("CENTER", infoIcon, "CENTER", 0, 0)
            -- Parse "Title|Description" format
            local tooltipTitle, tooltipDesc = infoTooltip:match("^([^|]+)|(.+)$")
            if not tooltipTitle then
                tooltipTitle, tooltipDesc = infoTooltip, nil
            end
            infoBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tooltipTitle, 1, 0.82, 0)
                if tooltipDesc then
                    GameTooltip:AddLine(tooltipDesc, 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            infoBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end

        panel.buffCheckboxes[key] = cb
        return y - ITEM_HEIGHT
    end

    -- Create checkbox with label
    local function CreateCheckbox(parent, x, y, labelText, checked, onClick, tooltip)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", x, y)
        cb:SetChecked(checked)
        cb:SetScript("OnClick", onClick)

        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(labelText)
        cb.label = label

        if tooltip then
            SetupTooltip(cb, labelText, tooltip)
        end

        return cb, y - ITEM_HEIGHT
    end

    -- Render checkboxes for any buff array
    -- Handles grouping automatically if groupId field is present
    local function RenderBuffCheckboxes(x, y, buffArray)
        -- Pass 1: Collect grouped data (flatten tables)
        local groupSpells = {}
        local groupDisplaySpells = {}
        local groupIconOverrides = {}
        for _, buff in ipairs(buffArray) do
            if buff.groupId then
                groupSpells[buff.groupId] = groupSpells[buff.groupId] or {}
                groupDisplaySpells[buff.groupId] = groupDisplaySpells[buff.groupId] or {}
                -- Flatten: buff.spellID can be a number or table of numbers
                if buff.spellID then
                    local spellList = type(buff.spellID) == "table" and buff.spellID or { buff.spellID }
                    for _, id in ipairs(spellList) do
                        table.insert(groupSpells[buff.groupId], id)
                    end
                end
                -- Flatten displaySpellIDs for UI icons
                if buff.displaySpellIDs then
                    local displayList = type(buff.displaySpellIDs) == "table" and buff.displaySpellIDs
                        or { buff.displaySpellIDs }
                    for _, id in ipairs(displayList) do
                        table.insert(groupDisplaySpells[buff.groupId], id)
                    end
                end
                -- Track iconOverride (use first one found for the group)
                if buff.iconOverride and not groupIconOverrides[buff.groupId] then
                    groupIconOverrides[buff.groupId] = buff.iconOverride
                end
            end
        end

        -- Pass 2: Render with group deduplication
        local seenGroups = {}
        for _, buff in ipairs(buffArray) do
            if buff.groupId then
                if not seenGroups[buff.groupId] then
                    seenGroups[buff.groupId] = true
                    local groupInfo = BuffGroups[buff.groupId]
                    local iconOverride = groupIconOverrides[buff.groupId]
                    -- Use displaySpellIDs if available, otherwise fall back to all spellIDs
                    local displaySpells = groupDisplaySpells[buff.groupId]
                    local spells = (#displaySpells > 0) and displaySpells or groupSpells[buff.groupId]
                    -- If no spellIDs but has iconOverride, pass nil for spells
                    if #spells == 0 then
                        spells = nil
                    end
                    y = CreateBuffCheckbox(
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
                -- For non-grouped buffs, use displaySpellIDs if available
                local displaySpells = buff.displaySpellIDs or buff.spellID
                y = CreateBuffCheckbox(x, y, displaySpells, buff.key, buff.name, buff.infoTooltip, buff.iconOverride)
            end
        end

        return y
    end

    -- ========== BUFFS TAB: BUFF SELECTION (Two Columns) ==========
    local buffsLeftX = leftColX
    local buffsRightX = leftColX + COL_WIDTH + COL_PADDING
    local buffsLeftY = startY
    local buffsRightY = startY

    -- LEFT COLUMN: Group-wide buffs
    -- Raid Buffs header
    local raidHeader =
        Components.CategoryHeader(buffsContent, { text = "Raid Buffs", category = "raid" }, OnCategoryVisibilityChange)
    raidHeader:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    buffsLeftY = buffsLeftY - 18
    local raidNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    raidNote:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    raidNote:SetText("(for the whole group)")
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsLeftX, buffsLeftY, RaidBuffs)

    buffsLeftY = buffsLeftY - SECTION_SPACING

    -- Presence Buffs header
    local presenceHeader = Components.CategoryHeader(
        buffsContent,
        { text = "Presence Buffs", category = "presence" },
        OnCategoryVisibilityChange
    )
    presenceHeader:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    buffsLeftY = buffsLeftY - 18
    local presenceNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    presenceNote:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    presenceNote:SetText("(at least 1 person needs)")
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsLeftX, buffsLeftY, PresenceBuffs)

    buffsLeftY = buffsLeftY - SECTION_SPACING

    -- Consumables header
    local consumableHeader = Components.CategoryHeader(
        buffsContent,
        { text = "Consumables", category = "consumable" },
        OnCategoryVisibilityChange
    )
    consumableHeader:SetPoint("TOPLEFT", buffsLeftX, buffsLeftY)
    buffsLeftY = buffsLeftY - 18
    local consumablesNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    consumablesNote:SetPoint("TOPLEFT", buffsLeftX + 5, buffsLeftY)
    consumablesNote:SetText("(flasks, food, runes, and weapon oils)")
    buffsLeftY = buffsLeftY - 14
    buffsLeftY = RenderBuffCheckboxes(buffsLeftX, buffsLeftY, Consumables)

    -- RIGHT COLUMN: Individual buffs
    -- Targeted Buffs header
    local targetedHeader = Components.CategoryHeader(
        buffsContent,
        { text = "Targeted Buffs", category = "targeted" },
        OnCategoryVisibilityChange
    )
    targetedHeader:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    buffsRightY = buffsRightY - 18
    local targetedNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    targetedNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    targetedNote:SetText("(buffs to maintain on someone else)")
    buffsRightY = buffsRightY - 14
    buffsRightY = RenderBuffCheckboxes(buffsRightX, buffsRightY, TargetedBuffs)

    buffsRightY = buffsRightY - SECTION_SPACING

    -- Self Buffs header
    local selfHeader =
        Components.CategoryHeader(buffsContent, { text = "Self Buffs", category = "self" }, OnCategoryVisibilityChange)
    selfHeader:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    buffsRightY = buffsRightY - 18
    local selfNote = buffsContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    selfNote:SetPoint("TOPLEFT", buffsRightX, buffsRightY)
    selfNote:SetText("(buffs strictly on yourself)")
    buffsRightY = buffsRightY - 14
    buffsRightY = RenderBuffCheckboxes(buffsRightX, buffsRightY, SelfBuffs)

    -- Set buffs content height (use the taller column)
    buffsContent:SetHeight(math.max(math.abs(buffsLeftY), math.abs(buffsRightY)) + 20)

    -- ========== FRAMES TAB: SINGLE COLUMN LAYOUT ==========
    local framesX = leftColX
    local framesY = startY

    -- Helper to enable/disable checkbox with label greying
    local function SetCheckboxEnabled(cb, enabled)
        cb:SetEnabled(enabled)
        if cb.label then
            if enabled then
                cb.label:SetTextColor(1, 1, 1)
            else
                cb.label:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end
    panel.SetCheckboxEnabled = SetCheckboxEnabled

    -- ========== SECTION: MAIN FRAME ==========
    local mainFrameHeader
    mainFrameHeader, framesY = CreateSectionHeader(appearanceContent, "Main Frame", framesX, framesY)

    -- Reset button next to the header (will be wired up after sliders are created)
    local mainResetBtn = CreateButton(appearanceContent, "Reset", function() end, {
        title = "Reset Main Frame",
        desc = "Reset all main frame settings to defaults",
    })
    mainResetBtn:SetPoint("LEFT", mainFrameHeader, "RIGHT", 10, 0)

    -- Row 1: Icon Size
    local sizeHolder = Components.Slider(appearanceContent, {
        label = "Icon Size",
        min = 16,
        max = 128,
        get = function()
            return GetCategorySettings("main").iconSize or 64
        end,
        onChange = function(val)
            BR.Config.Set("categorySettings.main.iconSize", val)
        end,
    })
    sizeHolder:SetPoint("TOPLEFT", framesX, framesY)
    panel.sizeSlider = sizeHolder.slider
    panel.sizeValue = sizeHolder.valueText
    framesY = framesY - 24

    -- Row 2: Spacing
    local spacingHolder = Components.Slider(appearanceContent, {
        label = "Spacing",
        min = 0,
        max = 50,
        get = function()
            return math.floor((GetCategorySettings("main").spacing or 0.2) * 100)
        end,
        suffix = "%",
        onChange = function(val)
            BR.Config.Set("categorySettings.main.spacing", val / 100)
        end,
    })
    spacingHolder:SetPoint("TOPLEFT", framesX, framesY)
    panel.spacingSlider = spacingHolder.slider
    panel.spacingValue = spacingHolder.valueText
    framesY = framesY - 24

    -- Row 3: Icon Zoom
    local zoomHolder = Components.Slider(appearanceContent, {
        label = "Icon Zoom",
        min = 0,
        max = 15,
        get = function()
            return GetCategorySettings("main").iconZoom or DEFAULT_ICON_ZOOM
        end,
        suffix = "%",
        onChange = function(val)
            BR.Config.Set("categorySettings.main.iconZoom", val)
        end,
    })
    zoomHolder:SetPoint("TOPLEFT", framesX, framesY)
    panel.zoomSlider = zoomHolder.slider
    panel.zoomValue = zoomHolder.valueText
    framesY = framesY - 24

    -- Row 4: Border Size
    local borderHolder = Components.Slider(appearanceContent, {
        label = "Border Size",
        min = 0,
        max = 8,
        get = function()
            return GetCategorySettings("main").borderSize or DEFAULT_BORDER_SIZE
        end,
        suffix = "px",
        onChange = function(val)
            BR.Config.Set("categorySettings.main.borderSize", val)
        end,
    })
    borderHolder:SetPoint("TOPLEFT", framesX, framesY)
    panel.borderSlider = borderHolder.slider
    panel.borderValue = borderHolder.valueText
    framesY = framesY - 24

    -- Row 5: Direction buttons
    local mainDirHolder = Components.DirectionButtons(appearanceContent, {
        get = function()
            return GetCategorySettings("main").growDirection or "CENTER"
        end,
        onChange = function(dir)
            BR.Config.Set("categorySettings.main.growDirection", dir)
        end,
    })
    mainDirHolder:SetPoint("TOPLEFT", framesX, framesY)
    panel.growBtns = mainDirHolder.buttons

    -- Wire up the Reset button handler now that sliders exist
    mainResetBtn:SetScript("OnClick", function()
        local db = BuffRemindersDB
        db.categorySettings = db.categorySettings or {}
        db.categorySettings.main = {
            position = defaults.categorySettings.main.position,
            iconSize = defaults.categorySettings.main.iconSize,
            spacing = defaults.categorySettings.main.spacing,
            growDirection = defaults.categorySettings.main.growDirection,
            iconZoom = defaults.categorySettings.main.iconZoom,
            borderSize = defaults.categorySettings.main.borderSize,
        }
        -- Update sliders
        sizeHolder:SetValue(defaults.categorySettings.main.iconSize)
        spacingHolder:SetValue(defaults.categorySettings.main.spacing * 100)
        zoomHolder:SetValue(defaults.categorySettings.main.iconZoom)
        borderHolder:SetValue(defaults.categorySettings.main.borderSize)
        mainDirHolder:SetDirection(defaults.categorySettings.main.growDirection)
        -- Reset position (update both legacy and new locations)
        db.position = {
            point = defaults.categorySettings.main.position.point,
            x = defaults.categorySettings.main.position.x,
            y = defaults.categorySettings.main.position.y,
        }
        ResetMainFramePosition(
            defaults.categorySettings.main.position.point,
            defaults.categorySettings.main.position.x,
            defaults.categorySettings.main.position.y
        )
        UpdateVisuals()
    end)

    framesY = framesY - 24 - SECTION_SPACING

    -- ========== SECTION: CATEGORIES ==========
    _, framesY = CreateSectionHeader(appearanceContent, "Categories", framesX, framesY)

    -- Capture this Y position for the UpdateCategoryLayout closure
    local categoriesStartY = framesY

    local CATEGORY_LABELS_FULL = {
        raid = "Raid Buffs",
        presence = "Presence Buffs",
        targeted = "Targeted Buffs",
        self = "Self Buffs",
        consumable = "Consumables",
        custom = "Custom Buffs",
    }

    -- Store category row data for refresh
    panel.categoryRows = {}

    -- Create expandable category row
    local function CreateCategoryRow(category, labelText, yPos)
        local rowData = {}
        rowData.category = category

        -- Main row frame
        local rowFrame = CreateFrame("Frame", nil, appearanceContent)
        rowFrame:SetSize(PANEL_WIDTH - COL_PADDING * 2, 22)
        rowFrame:SetPoint("TOPLEFT", framesX, yPos)
        rowData.rowFrame = rowFrame

        -- Category label
        local catLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        catLabel:SetPoint("LEFT", 0, 0)
        catLabel:SetWidth(100)
        catLabel:SetJustifyH("LEFT")
        catLabel:SetText(labelText)

        -- Split checkbox
        local splitCb = CreateFrame("CheckButton", nil, rowFrame, "UICheckButtonTemplate")
        splitCb:SetSize(20, 20)
        splitCb:SetPoint("LEFT", catLabel, "RIGHT", 10, 0)
        splitCb:SetChecked(IsCategorySplit(category))
        SetupTooltip(
            splitCb,
            "Split to Own Frame",
            "When enabled, this category's buffs will be displayed in a separate, independently movable frame with its own appearance settings.",
            "ANCHOR_TOP"
        )
        rowData.splitCheckbox = splitCb

        local splitLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        splitLabel:SetPoint("LEFT", splitCb, "RIGHT", 2, 0)
        splitLabel:SetText("Split")

        -- Expand/collapse arrow (only shows when split)
        local expandBtn = CreateFrame("Button", nil, rowFrame)
        expandBtn:SetSize(16, 16)
        expandBtn:SetPoint("LEFT", splitLabel, "RIGHT", 8, 0)
        expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
        expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
        expandBtn:Hide()
        rowData.expandBtn = expandBtn
        rowData.expanded = false

        -- Settings container (hidden by default)
        local settingsFrame = CreateFrame("Frame", nil, appearanceContent)
        settingsFrame:SetSize(PANEL_WIDTH - COL_PADDING * 2 - 20, 134)
        settingsFrame:SetPoint("TOPLEFT", framesX + 20, yPos - 22)
        settingsFrame:Hide()
        rowData.settingsFrame = settingsFrame

        -- Settings background (subtle indent)
        local settingsBg = settingsFrame:CreateTexture(nil, "BACKGROUND")
        settingsBg:SetAllPoints()
        settingsBg:SetColorTexture(0.15, 0.15, 0.15, 0.5)

        -- Settings content
        local setY = -4
        local setX = 4

        -- Icon Size slider
        local cat = category -- Capture for closures
        local catSizeHolder = Components.Slider(settingsFrame, {
            label = "Icon Size",
            min = 16,
            max = 128,
            get = function()
                return GetCategorySettings(cat).iconSize or 64
            end,
            onChange = function(val)
                BR.Config.Set("categorySettings." .. cat .. ".iconSize", val)
            end,
        })
        catSizeHolder:SetPoint("TOPLEFT", setX, setY)
        rowData.sizeSlider = catSizeHolder.slider
        rowData.sizeHolder = catSizeHolder
        setY = setY - 24

        -- Spacing slider
        local catSpacingHolder = Components.Slider(settingsFrame, {
            label = "Spacing",
            min = 0,
            max = 50,
            get = function()
                return math.floor((GetCategorySettings(cat).spacing or 0.2) * 100)
            end,
            suffix = "%",
            onChange = function(val)
                BR.Config.Set("categorySettings." .. cat .. ".spacing", val / 100)
            end,
        })
        catSpacingHolder:SetPoint("TOPLEFT", setX, setY)
        rowData.spacingSlider = catSpacingHolder.slider
        rowData.spacingHolder = catSpacingHolder
        setY = setY - 24

        -- Icon Zoom slider
        local catZoomHolder = Components.Slider(settingsFrame, {
            label = "Icon Zoom",
            min = 0,
            max = 15,
            get = function()
                return GetCategorySettings(cat).iconZoom or DEFAULT_ICON_ZOOM
            end,
            suffix = "%",
            onChange = function(val)
                BR.Config.Set("categorySettings." .. cat .. ".iconZoom", val)
            end,
        })
        catZoomHolder:SetPoint("TOPLEFT", setX, setY)
        rowData.zoomSlider = catZoomHolder.slider
        rowData.zoomHolder = catZoomHolder
        setY = setY - 24

        -- Border Size slider
        local catBorderHolder = Components.Slider(settingsFrame, {
            label = "Border Size",
            min = 0,
            max = 8,
            get = function()
                return GetCategorySettings(cat).borderSize or DEFAULT_BORDER_SIZE
            end,
            suffix = "px",
            onChange = function(val)
                BR.Config.Set("categorySettings." .. cat .. ".borderSize", val)
            end,
        })
        catBorderHolder:SetPoint("TOPLEFT", setX, setY)
        rowData.borderSlider = catBorderHolder.slider
        rowData.borderHolder = catBorderHolder
        setY = setY - 24

        -- Direction buttons
        local catDirHolder = Components.DirectionButtons(settingsFrame, {
            get = function()
                return GetCategorySettings(cat).growDirection or "CENTER"
            end,
            onChange = function(dir)
                BR.Config.Set("categorySettings." .. cat .. ".growDirection", dir)
            end,
        })
        catDirHolder:SetPoint("TOPLEFT", setX, setY)
        rowData.growBtns = catDirHolder.buttons
        rowData.dirHolder = catDirHolder

        -- Reset button on the top row (right-aligned)
        local catResetBtn = CreateButton(rowFrame, "Reset", function()
            local db = BuffRemindersDB
            db.categorySettings = db.categorySettings or {}
            local catDefaults = defaults.categorySettings[category]
            db.categorySettings[category] = {
                position = catDefaults.position,
                iconSize = catDefaults.iconSize,
                spacing = catDefaults.spacing,
                growDirection = catDefaults.growDirection,
                iconZoom = catDefaults.iconZoom,
                borderSize = catDefaults.borderSize,
            }
            -- Update sliders
            catSizeHolder:SetValue(catDefaults.iconSize)
            catSpacingHolder:SetValue(catDefaults.spacing * 100)
            catZoomHolder:SetValue(catDefaults.iconZoom)
            catBorderHolder:SetValue(catDefaults.borderSize)
            catDirHolder:SetDirection(catDefaults.growDirection)
            -- Reset position if frame exists
            ResetCategoryFramePosition(
                category,
                catDefaults.position.point,
                catDefaults.position.x,
                catDefaults.position.y
            )
            UpdateVisuals()
        end, {
            title = "Reset " .. labelText,
            desc = "Reset all " .. labelText:lower() .. " settings to defaults",
        })
        catResetBtn:SetPoint("RIGHT", rowFrame, "RIGHT", -30, 0)
        rowData.resetBtn = catResetBtn

        -- Function to update row layout
        local function UpdateRowLayout()
            local isSplit = splitCb:GetChecked()
            if isSplit then
                expandBtn:Show()
                if rowData.expanded then
                    expandBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
                    settingsFrame:Show()
                else
                    expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
                    settingsFrame:Hide()
                end
            else
                expandBtn:Hide()
                settingsFrame:Hide()
                rowData.expanded = false
            end
        end
        rowData.UpdateLayout = UpdateRowLayout

        -- Split checkbox handler
        splitCb:SetScript("OnClick", function(self)
            local db = BuffRemindersDB
            db.splitCategories = db.splitCategories or {}
            db.splitCategories[category] = self:GetChecked()
            if self:GetChecked() then
                rowData.expanded = true
            end
            UpdateRowLayout()
            panel.UpdateCategoryLayout()
            ReparentBuffFrames()
            UpdateVisuals()
        end)

        -- Expand button handler
        expandBtn:SetScript("OnClick", function()
            rowData.expanded = not rowData.expanded
            UpdateRowLayout()
            panel.UpdateCategoryLayout()
        end)

        -- Function to refresh values
        rowData.RefreshValues = function()
            local catSettings = GetCategorySettings(category)
            splitCb:SetChecked(IsCategorySplit(category))
            catSizeHolder:SetValue(catSettings.iconSize or 64)
            catSpacingHolder:SetValue((catSettings.spacing or 0.2) * 100)
            catZoomHolder:SetValue(catSettings.iconZoom or DEFAULT_ICON_ZOOM)
            catBorderHolder:SetValue(catSettings.borderSize or DEFAULT_BORDER_SIZE)
            catDirHolder:SetDirection(catSettings.growDirection or "CENTER")
            UpdateRowLayout()
        end

        return rowData
    end

    -- Create category rows
    local categoryRowY = framesY
    for _, category in ipairs(CATEGORIES) do
        local rowData = CreateCategoryRow(category, CATEGORY_LABELS_FULL[category], categoryRowY)
        panel.categoryRows[category] = rowData
        categoryRowY = categoryRowY - 24
    end

    -- Function to recalculate layout when categories expand/collapse
    panel.UpdateCategoryLayout = function()
        local yPos = categoriesStartY
        for _, category in ipairs(CATEGORIES) do
            local rowData = panel.categoryRows[category]
            rowData.rowFrame:ClearAllPoints()
            rowData.rowFrame:SetPoint("TOPLEFT", framesX, yPos)
            yPos = yPos - 24
            if rowData.expanded and IsCategorySplit(category) then
                rowData.settingsFrame:ClearAllPoints()
                rowData.settingsFrame:SetPoint("TOPLEFT", framesX + 20, yPos)
                rowData.settingsFrame:Show()
                yPos = yPos - 134
            else
                rowData.settingsFrame:Hide()
            end
        end
        panel.categoriesEndY = yPos
        panel.UpdateAppearanceContentHeight()
    end

    -- Initial category end Y position
    panel.categoriesEndY = categoryRowY

    -- ========== SETTINGS TAB CONTENT ==========
    local settingsY = 0
    local settingsX = COL_PADDING

    -- ========== SECTION: DISPLAY ==========
    _, settingsY = CreateSectionHeader(settingsContent, "Display", settingsX, settingsY)

    local reminderCb
    reminderCb, settingsY = CreateCheckbox(
        settingsContent,
        settingsX,
        settingsY,
        'Show "BUFF!" reminder text',
        BuffRemindersDB.showBuffReminder ~= false,
        function(self)
            BuffRemindersDB.showBuffReminder = self:GetChecked()
            UpdateVisuals()
        end
    )
    panel.reminderCheckbox = reminderCb

    settingsY = settingsY - SECTION_SPACING

    -- ========== SECTION: BEHAVIOR ==========
    _, settingsY = CreateSectionHeader(settingsContent, "Behavior", settingsX, settingsY)

    local behaviorContainer = CreateFrame("Frame", nil, settingsContent)
    behaviorContainer:SetSize(PANEL_WIDTH - COL_PADDING * 2, 160)
    behaviorContainer:SetPoint("TOPLEFT", settingsX, settingsY)
    panel.behaviorContainer = behaviorContainer

    local behY = 0

    -- Informational note about buff tracking
    local trackingNote = behaviorContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    trackingNote:SetPoint("TOPLEFT", 0, behY)
    trackingNote:SetWidth(PANEL_WIDTH - COL_PADDING * 2 - 18)
    trackingNote:SetJustifyH("LEFT")
    trackingNote:SetText("Buff counts and buff providers are tracked only for alive, connected, and visible allies.")

    -- Add info icon for open world faction details
    local trackingInfoIcon = behaviorContainer:CreateTexture(nil, "ARTWORK")
    trackingInfoIcon:SetSize(14, 14)
    trackingInfoIcon:SetPoint("TOPLEFT", PANEL_WIDTH - COL_PADDING * 2 - 14, behY)
    trackingInfoIcon:SetAtlas("QuestNormal")
    local trackingInfoBtn = CreateFrame("Button", nil, behaviorContainer)
    trackingInfoBtn:SetSize(14, 14)
    trackingInfoBtn:SetPoint("CENTER", trackingInfoIcon, "CENTER", 0, 0)
    trackingInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open World vs Instances", 1, 0.82, 0)
        GameTooltip:AddLine(
            "In open world, opposing faction players are not counted as allies. In dungeons and raids, all group members are allied and counted normally.",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    trackingInfoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    behY = behY - 18

    local groupCb, instanceCb
    groupCb, behY = CreateCheckbox(
        behaviorContainer,
        0,
        behY,
        "Show only in group/raid",
        BuffRemindersDB.showOnlyInGroup ~= false,
        function(self)
            BuffRemindersDB.showOnlyInGroup = self:GetChecked()
            if instanceCb then
                SetCheckboxEnabled(instanceCb, self:GetChecked())
                if not self:GetChecked() then
                    instanceCb:SetChecked(false)
                    BuffRemindersDB.showOnlyInInstance = false
                end
            end
            UpdateDisplay()
        end
    )
    panel.groupCheckbox = groupCb

    instanceCb, behY = CreateCheckbox(
        behaviorContainer,
        20,
        behY,
        "Only in instance",
        BuffRemindersDB.showOnlyInInstance,
        function(self)
            BuffRemindersDB.showOnlyInInstance = self:GetChecked()
            UpdateDisplay()
        end
    )
    SetCheckboxEnabled(instanceCb, BuffRemindersDB.showOnlyInGroup)
    panel.instanceCheckbox = instanceCb

    local readyCheckCb
    readyCheckCb, behY = CreateCheckbox(
        behaviorContainer,
        0,
        behY,
        "Show only on ready check",
        BuffRemindersDB.showOnlyOnReadyCheck,
        function(self)
            BuffRemindersDB.showOnlyOnReadyCheck = self:GetChecked()
            if panel.readyCheckHolder then
                panel.readyCheckHolder:SetEnabled(self:GetChecked())
            end
            UpdateDisplay()
        end
    )
    panel.readyCheckCheckbox = readyCheckCb

    local readyCheckHolder = Components.Slider(behaviorContainer, {
        label = "Duration",
        min = 10,
        max = 30,
        get = function()
            return BuffRemindersDB.readyCheckDuration or 15
        end,
        suffix = "s",
        onChange = function(val)
            BuffRemindersDB.readyCheckDuration = val
        end,
    })
    readyCheckHolder:SetPoint("TOPLEFT", 20, behY)
    readyCheckHolder:SetEnabled(BuffRemindersDB.showOnlyOnReadyCheck)
    panel.readyCheckSlider = readyCheckHolder.slider
    panel.readyCheckSliderValue = readyCheckHolder.valueText
    panel.readyCheckHolder = readyCheckHolder
    behY = behY - 24

    local playerClassCb
    playerClassCb, behY = CreateCheckbox(
        behaviorContainer,
        0,
        behY,
        "Show only my class buffs",
        BuffRemindersDB.showOnlyPlayerClassBuff,
        function(self)
            BuffRemindersDB.showOnlyPlayerClassBuff = self:GetChecked()
            UpdateDisplay()
        end,
        "Only show buffs that your class can provide (e.g., warriors will only see Battle Shout)"
    )
    panel.playerClassCheckbox = playerClassCb

    local playerMissingCb
    playerMissingCb, behY = CreateCheckbox(
        behaviorContainer,
        0,
        behY,
        "Show only buffs I'm missing",
        BuffRemindersDB.showOnlyPlayerMissing,
        function(self)
            BuffRemindersDB.showOnlyPlayerMissing = self:GetChecked()
            UpdateDisplay()
        end,
        "Only show buffs that you personally are missing, instead of showing group buff coverage (e.g., 17/20)"
    )
    panel.playerMissingCheckbox = playerMissingCb

    -- EXPERIMENTAL label for glow fallback
    local experimentalLabel = behaviorContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    experimentalLabel:SetPoint("TOPLEFT", 0, behY - 8)
    experimentalLabel:SetText("EXPERIMENTAL")
    experimentalLabel:SetTextColor(1, 0.5, 0) -- Orange color
    behY = behY - 18

    local glowFallbackCb
    glowFallbackCb, behY = CreateCheckbox(
        behaviorContainer,
        0,
        behY,
        "Show own raid buff during M+",
        BuffRemindersDB.useGlowFallback == true,
        function(self)
            BuffRemindersDB.useGlowFallback = self:GetChecked()
            UpdateFallbackDisplay()
        end,
        "Uses WoW's action bar glow to detect when someone needs your raid buff, in Mythic+ where normal tracking is disabled.\n\nRequires the spell to be on your action bars."
    )
    panel.glowFallbackCheckbox = glowFallbackCb

    local behaviorHeight = math.abs(behY) + 10
    behaviorContainer:SetHeight(behaviorHeight)
    settingsY = settingsY - behaviorHeight - SECTION_SPACING

    -- ========== SECTION: EXPIRATION WARNING ==========
    _, settingsY = CreateSectionHeader(settingsContent, "Expiration Warning", settingsX, settingsY)

    local expirationContainer = CreateFrame("Frame", nil, settingsContent)
    expirationContainer:SetSize(PANEL_WIDTH - COL_PADDING * 2, 100)
    expirationContainer:SetPoint("TOPLEFT", settingsX, settingsY)
    panel.expirationContainer = expirationContainer

    local expY = 0

    local glowCb
    glowCb, expY = CreateCheckbox(
        expirationContainer,
        0,
        expY,
        "Show glow when expiring",
        BuffRemindersDB.showExpirationGlow,
        function(self)
            BuffRemindersDB.showExpirationGlow = self:GetChecked()
            if panel.SetGlowControlsEnabled then
                panel.SetGlowControlsEnabled(self:GetChecked())
            end
            if BR.Display.IsTestMode() then
                RefreshTestDisplay()
            else
                UpdateDisplay()
            end
        end
    )
    glowCb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Expiration Warning")
        GameTooltip:AddLine("Shows a glow effect on buff icons when they are close to expiring.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            "The icon will be shown even when all players have the buff, as long as it's within the threshold.",
            0.8,
            0.8,
            0.8,
            true
        )
        GameTooltip:Show()
    end)
    glowCb:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    panel.glowCheckbox = glowCb

    local thresholdHolder = Components.Slider(expirationContainer, {
        label = "Threshold",
        min = 1,
        max = 15,
        get = function()
            return BuffRemindersDB.expirationThreshold or 5
        end,
        suffix = " min",
        onChange = function(val)
            BuffRemindersDB.expirationThreshold = val
            if BR.Display.IsTestMode() then
                RefreshTestDisplay()
            else
                UpdateDisplay()
            end
        end,
    })
    thresholdHolder:SetPoint("TOPLEFT", 0, expY)
    panel.thresholdSlider = thresholdHolder.slider
    panel.thresholdValue = thresholdHolder.valueText
    panel.thresholdHolder = thresholdHolder
    expY = expY - 24

    -- Style dropdown - build options from GlowStyles
    local styleOptions = {}
    for i, style in ipairs(GlowStyles) do
        styleOptions[i] = { label = style.name, value = i }
    end

    local styleHolder = Components.Dropdown(expirationContainer, {
        label = "Style:",
        options = styleOptions,
        get = function()
            return BuffRemindersDB.glowStyle or 1
        end,
        width = 100,
        onChange = function(val)
            BuffRemindersDB.glowStyle = val
            if BR.Display.IsTestMode() then
                RefreshTestDisplay()
            else
                UpdateDisplay()
            end
        end,
    }, "BuffRemindersStyleDropdown")
    styleHolder:SetPoint("TOPLEFT", 0, expY)
    panel.styleHolder = styleHolder

    local previewBtn = CreateButton(expirationContainer, "Preview", function()
        ShowGlowDemo()
    end)
    previewBtn:SetPoint("LEFT", styleHolder, "RIGHT", 5, 0)
    panel.previewBtn = previewBtn

    -- Helper to enable/disable glow-related controls
    local function SetGlowControlsEnabled(enabled)
        if panel.thresholdHolder then
            panel.thresholdHolder:SetEnabled(enabled)
        end
        if panel.styleHolder then
            panel.styleHolder:SetEnabled(enabled)
        end
        previewBtn:SetEnabled(enabled)
    end
    panel.SetGlowControlsEnabled = SetGlowControlsEnabled
    SetGlowControlsEnabled(BuffRemindersDB.showExpirationGlow)

    expY = expY - 28
    local expirationHeight = math.abs(expY) + 20
    expirationContainer:SetHeight(expirationHeight)

    -- Set settings content height
    settingsY = settingsY - expirationHeight
    local settingsHeight = math.abs(settingsY) + 20
    settingsContent:SetHeight(settingsHeight)

    -- Function to update layout when categories expand/collapse
    panel.UpdateAppearanceContentHeight = function()
        -- Update total content height based on categories
        local totalHeight = math.abs(panel.categoriesEndY) + 40
        appearanceContent:SetHeight(totalHeight)
    end

    -- Set initial appearance content height
    appearanceContent:SetHeight(math.abs(panel.categoriesEndY) + 40)

    -- Content height for bottom buttons positioning (use tallest tab)
    local contentHeight = math.max(buffsContent:GetHeight(), appearanceContent:GetHeight(), settingsHeight)

    -- ========== CUSTOM BUFFS CONTENT ==========
    panel.customBuffRows = {}

    -- Header with visibility toggles
    local customY = 0
    local customHeader = Components.CategoryHeader(
        customContent,
        { text = "Custom Buffs", category = "custom" },
        OnCategoryVisibilityChange
    )
    customHeader:SetPoint("TOPLEFT", COL_PADDING, customY)
    customY = customY - 18

    local customDesc = customContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    customDesc:SetPoint("TOPLEFT", COL_PADDING, customY)
    customDesc:SetWidth(PANEL_WIDTH - COL_PADDING * 2)
    customDesc:SetJustifyH("LEFT")
    customDesc:SetText("Track any buff by spell ID. Only checks if YOU have the buff (like Self Buffs).")

    -- Container for custom buff rows
    local customBuffsContainer = CreateFrame("Frame", nil, customContent)
    customBuffsContainer:SetPoint("TOPLEFT", COL_PADDING, customY - 14)
    customBuffsContainer:SetSize(PANEL_WIDTH - COL_PADDING * 2, 300)
    panel.customBuffsContainer = customBuffsContainer

    -- Function to render custom buff rows
    local function RenderCustomBuffRows()
        -- Clear existing rows
        for _, row in ipairs(panel.customBuffRows) do
            row:Hide()
            row:SetParent(nil)
        end
        panel.customBuffRows = {}

        local db = BuffRemindersDB
        local rowY = 0

        -- Sort custom buffs by key for consistent order
        local sortedKeys = {}
        if db.customBuffs then
            for key in pairs(db.customBuffs) do
                table.insert(sortedKeys, key)
            end
        end
        table.sort(sortedKeys)

        -- Show empty state message if no custom buffs
        if #sortedKeys == 0 then
            local emptyFrame = CreateFrame("Frame", nil, customBuffsContainer)
            emptyFrame:SetSize(300, 30)
            emptyFrame:SetPoint("TOPLEFT", 0, rowY)
            local emptyMsg = emptyFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            emptyMsg:SetPoint("TOPLEFT")
            emptyMsg:SetText("No custom buffs added yet.")
            table.insert(panel.customBuffRows, emptyFrame)
            rowY = rowY - 22
        end

        for _, key in ipairs(sortedKeys) do
            local customBuff = db.customBuffs[key]
            local row = CreateFrame("Frame", nil, customBuffsContainer)
            row:SetSize(PANEL_WIDTH - COL_PADDING * 2, ITEM_HEIGHT)
            row:SetPoint("TOPLEFT", 0, rowY)

            -- Checkbox
            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetSize(20, 20)
            cb:SetPoint("LEFT", 0, 0)
            cb:SetChecked(IsBuffEnabled(key))
            cb:SetScript("OnClick", function(self)
                BuffRemindersDB.enabledBuffs[key] = self:GetChecked()
                UpdateDisplay()
            end)
            panel.buffCheckboxes[key] = cb

            -- Icon
            local icon = CreateBuffIcon(row, 18, GetBuffTexture(customBuff.spellID))
            icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)

            -- Name label
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            label:SetText(customBuff.name or ("Spell " .. customBuff.spellID))

            -- Class indicator (if set)
            if customBuff.class then
                local classLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                classLabel:SetPoint("LEFT", label, "RIGHT", 4, 0)
                classLabel:SetText("(" .. customBuff.class:sub(1, 3) .. ")")
            end

            -- Edit button
            local editBtn = CreateButton(row, "Edit", function()
                ShowCustomBuffModal(key, RenderCustomBuffRows)
            end)
            editBtn:SetPoint("RIGHT", row, "RIGHT", -50, 0)

            -- Delete button
            local deleteBtn = CreateButton(row, "Delete", function()
                StaticPopup_Show("BUFFREMINDERS_DELETE_CUSTOM", customBuff.name or key, nil, {
                    key = key,
                    refreshPanel = RenderCustomBuffRows,
                })
            end)
            deleteBtn:SetPoint("LEFT", editBtn, "RIGHT", 4, 0)

            table.insert(panel.customBuffRows, row)
            rowY = rowY - ITEM_HEIGHT
        end

        -- Add button
        local addBtn = CreateButton(customBuffsContainer, "+ Add", function()
            ShowCustomBuffModal(nil, RenderCustomBuffRows)
        end)
        addBtn:SetPoint("TOPLEFT", 0, rowY - 4)
        table.insert(panel.customBuffRows, addBtn)

        -- Update container height
        customBuffsContainer:SetHeight(math.abs(rowY) + 30)
    end

    panel.RenderCustomBuffRows = RenderCustomBuffRows
    RenderCustomBuffRows()

    -- Set custom content height
    customContent:SetHeight(contentHeight)

    -- ========== BOTTOM BUTTONS (on main panel) ==========
    local contentBottomY = CONTENT_TOP - contentHeight - 20

    -- Create a frame for the bottom section that sits above scroll content
    local bottomFrame = CreateFrame("Frame", nil, panel)
    bottomFrame:SetPoint("TOPLEFT", 0, contentBottomY + 5)
    bottomFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    bottomFrame:SetFrameLevel(panel:GetFrameLevel() + 10) -- Ensure it's above scroll content

    -- Background to mask any scroll content bleeding through
    local bottomBg = bottomFrame:CreateTexture(nil, "BACKGROUND")
    bottomBg:SetAllPoints()
    bottomBg:SetColorTexture(0.1, 0.1, 0.1, 0.95)

    -- Separator line
    local separator = bottomFrame:CreateTexture(nil, "ARTWORK")
    separator:SetSize(PANEL_WIDTH - 40, 1)
    separator:SetPoint("TOP", 0, -5)
    separator:SetColorTexture(0.5, 0.5, 0.5, 1)

    -- Button row (centered using holder frame)
    local btnHolder = CreateFrame("Frame", nil, bottomFrame)
    btnHolder:SetPoint("TOP", 0, -20)
    btnHolder:SetSize(1, 22)

    -- Size buttons for longest text to prevent resizing on click
    local lockBtn = CreateButton(btnHolder, "Unlock", function(self)
        BuffRemindersDB.locked = not BuffRemindersDB.locked
        self:SetText(BuffRemindersDB.locked and "Unlock" or "Lock")
        if BR.Display.IsTestMode() then
            RefreshTestDisplay()
        else
            UpdateDisplay()
        end
    end, { title = "Lock/Unlock", desc = "Unlock to drag and reposition the buff frames." })
    lockBtn:SetText(BuffRemindersDB.locked and "Unlock" or "Lock")
    lockBtn:SetPoint("RIGHT", btnHolder, "CENTER", -4, 0)
    panel.lockBtn = lockBtn

    local testBtn = CreateButton(btnHolder, "Stop Test", function(self)
        local isOn = ToggleTestMode()
        self:SetText(isOn and "Stop Test" or "Test")
    end, {
        title = "Test icon's appearance",
        desc = "Shows ALL buffs regardless of what you selected in the buffs section.",
    })
    testBtn:SetText("Test")
    testBtn:SetPoint("LEFT", btnHolder, "CENTER", 4, 0)
    panel.testBtn = testBtn

    contentBottomY = contentBottomY - 30

    -- Set panel height
    local panelHeight = math.abs(contentBottomY) + 15
    panel:SetHeight(panelHeight)

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
        -- Refresh values
        local db = BuffRemindersDB

        -- Helper to refresh checkboxes for a buff array (handles grouping)
        local function RefreshBuffCheckboxes(buffArray)
            local seenGroups = {}
            for _, buff in ipairs(buffArray) do
                local settingKey = GetBuffSettingKey(buff)
                if buff.groupId then
                    if not seenGroups[buff.groupId] then
                        seenGroups[buff.groupId] = true
                        if optionsPanel.buffCheckboxes[settingKey] then
                            optionsPanel.buffCheckboxes[settingKey]:SetChecked(IsBuffEnabled(settingKey))
                        end
                    end
                else
                    if optionsPanel.buffCheckboxes[settingKey] then
                        optionsPanel.buffCheckboxes[settingKey]:SetChecked(IsBuffEnabled(settingKey))
                    end
                end
            end
        end

        RefreshBuffCheckboxes(RaidBuffs)
        RefreshBuffCheckboxes(PresenceBuffs)
        RefreshBuffCheckboxes(TargetedBuffs)
        RefreshBuffCheckboxes(SelfBuffs)
        -- Refresh custom buffs section
        if optionsPanel.RenderCustomBuffRows then
            optionsPanel.RenderCustomBuffRows()
        end
        local mainSettings = GetCategorySettings("main")
        optionsPanel.sizeSlider:SetValue(mainSettings.iconSize or 64)
        optionsPanel.spacingSlider:SetValue((mainSettings.spacing or 0.2) * 100)
        optionsPanel.zoomSlider:SetValue(mainSettings.iconZoom or DEFAULT_ICON_ZOOM)
        optionsPanel.borderSlider:SetValue(mainSettings.borderSize or DEFAULT_BORDER_SIZE)
        optionsPanel.lockBtn:SetText(db.locked and "Unlock" or "Lock")
        optionsPanel.reminderCheckbox:SetChecked(db.showBuffReminder ~= false)
        optionsPanel.groupCheckbox:SetChecked(db.showOnlyInGroup ~= false)
        if optionsPanel.instanceCheckbox then
            optionsPanel.instanceCheckbox:SetChecked(db.showOnlyInInstance)
            optionsPanel.SetCheckboxEnabled(optionsPanel.instanceCheckbox, db.showOnlyInGroup)
        end
        if optionsPanel.playerClassCheckbox then
            optionsPanel.playerClassCheckbox:SetChecked(db.showOnlyPlayerClassBuff)
        end
        if optionsPanel.glowCheckbox then
            optionsPanel.glowCheckbox:SetChecked(db.showExpirationGlow)
        end
        if optionsPanel.thresholdSlider then
            optionsPanel.thresholdSlider:SetValue(db.expirationThreshold or 5)
            optionsPanel.thresholdValue:SetText((db.expirationThreshold or 5) .. " min")
        end
        if optionsPanel.styleHolder then
            optionsPanel.styleHolder:SetValue(db.glowStyle or 1)
        end
        if optionsPanel.SetGlowControlsEnabled then
            optionsPanel.SetGlowControlsEnabled(db.showExpirationGlow)
        end
        for _, btn in ipairs(optionsPanel.growBtns) do
            btn:SetEnabled(btn.direction ~= (mainSettings.growDirection or "CENTER"))
        end
        -- Refresh category rows (expandable split settings)
        if optionsPanel.categoryRows then
            for _, category in ipairs(CATEGORIES) do
                local rowData = optionsPanel.categoryRows[category]
                if rowData and rowData.RefreshValues then
                    rowData.RefreshValues()
                end
            end
            if optionsPanel.UpdateCategoryLayout then
                optionsPanel.UpdateCategoryLayout()
            end
        end
        if BR.Display.IsTestMode() then
            optionsPanel.testBtn:SetText("Stop Test")
        else
            optionsPanel.testBtn:SetText("Test")
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

    local panel = CreatePanel("BuffRemindersGlowDemo", numStyles * (ICON_SIZE + SPACING) + SPACING, ICON_SIZE + 70, {
        bgColor = { 0.12, 0.08, 0.18, 0.98 },
        borderColor = { 0.6, 0.4, 0.8, 1 },
        strata = "TOOLTIP",
    })

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Glow Styles Preview")

    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Create demo icons using GlowStyles
    for i, style in ipairs(GlowStyles) do
        local iconFrame = CreateFrame("Frame", nil, panel)
        iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
        iconFrame:SetPoint("TOPLEFT", SPACING + (i - 1) * (ICON_SIZE + SPACING), -30)

        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(TEXCOORD_INSET, 1 - TEXCOORD_INSET, TEXCOORD_INSET, 1 - TEXCOORD_INSET)
        icon:SetTexture(GetBuffTexture(1459)) -- Arcane Intellect icon

        local border = iconFrame:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", -DEFAULT_BORDER_SIZE, DEFAULT_BORDER_SIZE)
        border:SetPoint("BOTTOMRIGHT", DEFAULT_BORDER_SIZE, -DEFAULT_BORDER_SIZE)
        border:SetColorTexture(0, 0, 0, 1)

        -- Setup and play glow animation
        style.setup(iconFrame)
        if iconFrame.glowAnim then
            iconFrame.glowAnim:Play()
        end

        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOP", iconFrame, "BOTTOM", 0, -4)
        label:SetText(i .. ". " .. style.name)
        label:SetWidth(ICON_SIZE + 10)
    end

    glowDemoPanel = panel
end

-- Delete confirmation dialog for custom buffs
StaticPopupDialogs["BUFFREMINDERS_DELETE_CUSTOM"] = {
    text = 'Delete custom buff "%s"?',
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
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

-- Custom buff add/edit modal dialog
ShowCustomBuffModal = function(existingKey, refreshPanelCallback)
    if customBuffModal then
        customBuffModal:Hide()
    end

    local MODAL_WIDTH = 340
    local BASE_HEIGHT = 270
    local ROW_HEIGHT = 26
    local ADVANCED_HEIGHT = 85
    local CONTENT_LEFT = 20
    local ROWS_START_Y = -60 -- Below title and "Spell IDs:" label
    local editingBuff = existingKey and BuffRemindersDB.customBuffs[existingKey] or nil

    -- Convert existing spellID to array form for editing
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

    -- Forward declare for OnHide handler
    local spellRows, nameBox, missingBox

    -- Clear focus from EditBoxes when modal hides to prevent keyboard capture
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

    -- Title and close button
    local title = modal:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(editingBuff and "Edit Custom Buff" or "Add Custom Buff")

    local closeBtn = CreateFrame("Button", nil, modal, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Spell IDs label
    local spellIdsLabel = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spellIdsLabel:SetPoint("TOPLEFT", CONTENT_LEFT, -40)
    spellIdsLabel:SetText("Spell IDs:")

    -- State
    spellRows = {}
    local advancedShown = false

    -- Forward declarations
    local addSpellBtn, advancedBtn, advancedText, advancedFrame
    local selectedClass

    -- Single layout function that positions everything
    local function UpdateLayout()
        local rowCount = #spellRows

        -- Position each row
        for i, rowData in ipairs(spellRows) do
            rowData.frame:ClearAllPoints()
            rowData.frame:SetPoint("TOPLEFT", modal, "TOPLEFT", CONTENT_LEFT, ROWS_START_Y - ((i - 1) * ROW_HEIGHT))
            -- Show/hide remove button
            if rowCount > 1 then
                rowData.removeBtn:Show()
            else
                rowData.removeBtn:Hide()
            end
        end

        -- Position add button below rows
        local addBtnY = ROWS_START_Y - (rowCount * ROW_HEIGHT) - 4
        addSpellBtn:ClearAllPoints()
        addSpellBtn:SetPoint("TOPLEFT", modal, "TOPLEFT", CONTENT_LEFT, addBtnY)

        -- Position advanced toggle below add button
        local advancedY = addBtnY - 26
        advancedBtn:ClearAllPoints()
        advancedBtn:SetPoint("TOPLEFT", modal, "TOPLEFT", CONTENT_LEFT, advancedY)

        -- Position advanced frame below toggle
        advancedFrame:ClearAllPoints()
        advancedFrame:SetPoint("TOPLEFT", modal, "TOPLEFT", CONTENT_LEFT, advancedY - 22)

        -- Update modal height
        local extraRows = math.max(0, rowCount - 1)
        local advancedExtra = advancedShown and ADVANCED_HEIGHT or 0
        modal:SetHeight(BASE_HEIGHT + (extraRows * ROW_HEIGHT) + advancedExtra)
    end

    -- Create a spell row
    local function CreateSpellRow(initialSpellID)
        local rowFrame = CreateFrame("Frame", nil, modal)
        rowFrame:SetSize(MODAL_WIDTH - 40, ROW_HEIGHT - 2)

        -- Edit box
        local editBox = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
        editBox:SetSize(70, 20)
        editBox:SetPoint("LEFT", 0, 0)
        editBox:SetAutoFocus(false)
        if initialSpellID then
            editBox:SetText(tostring(initialSpellID))
        end

        -- Lookup button
        local lookupBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        lookupBtn:SetSize(50, 20)
        lookupBtn:SetPoint("LEFT", editBox, "RIGHT", 5, 0)
        lookupBtn:SetText("Lookup")
        lookupBtn:SetNormalFontObject("GameFontHighlightSmall")
        lookupBtn:SetHighlightFontObject("GameFontHighlightSmall")

        -- Icon preview
        local icon = CreateBuffIcon(rowFrame, 18)
        icon:SetPoint("LEFT", lookupBtn, "RIGHT", 8, 0)
        icon:Hide()

        -- Spell name
        local nameText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        nameText:SetPoint("RIGHT", rowFrame, "RIGHT", -28, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
        removeBtn:SetSize(20, 20)
        removeBtn:SetPoint("RIGHT", 0, 0)
        removeBtn:SetText("-")
        removeBtn:SetNormalFontObject("GameFontHighlightSmall")
        removeBtn:SetHighlightFontObject("GameFontHighlightSmall")
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

        -- Lookup handler
        lookupBtn:SetScript("OnClick", function()
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
        end)

        -- Remove handler
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

        table.insert(spellRows, rowData)

        -- Auto-lookup if initial spell ID provided
        if initialSpellID then
            lookupBtn:GetScript("OnClick")()
        end

        return rowData
    end

    -- Add spell ID button
    addSpellBtn = CreateButton(modal, "+ Add Spell ID", function()
        CreateSpellRow(nil)
        UpdateLayout()
    end)

    -- Advanced options toggle button
    advancedBtn = CreateFrame("Button", nil, modal)
    advancedBtn:SetSize(200, 20)
    advancedText = advancedBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    advancedText:SetPoint("LEFT", 0, 0)
    advancedText:SetText("[+] Show Advanced Options")
    advancedText:SetTextColor(0.6, 0.8, 1)

    -- Advanced options frame
    advancedFrame = CreateFrame("Frame", nil, modal)
    advancedFrame:SetSize(MODAL_WIDTH - 40, ADVANCED_HEIGHT)
    advancedFrame:Hide()

    -- Advanced options content
    local advY = 0

    local nameHolder = Components.TextInput(advancedFrame, {
        label = "Display Name:",
        value = editingBuff and editingBuff.name or "",
        width = 150,
        labelWidth = 85,
    })
    nameHolder:SetPoint("TOPLEFT", 0, advY)
    nameBox = nameHolder.editBox -- Keep reference for save handler

    advY = advY - 25

    local missingHolder = Components.TextInput(advancedFrame, {
        label = "Missing Text:",
        value = editingBuff and editingBuff.missingText and editingBuff.missingText:gsub("\n", "\\n") or "",
        width = 80,
        labelWidth = 85,
    })
    missingHolder:SetPoint("TOPLEFT", 0, advY)
    missingBox = missingHolder.editBox -- Keep reference for save handler

    local missingHint = advancedFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    missingHint:SetPoint("LEFT", missingHolder, "RIGHT", 5, 0)
    missingHint:SetText("(use \\n for newline)")

    advY = advY - 25

    local classLabel = advancedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    classLabel:SetPoint("TOPLEFT", 0, advY)
    classLabel:SetText("Only for class:")

    local classOptions = {
        { value = nil, label = "Any" },
        { value = "WARRIOR", label = "Warrior" },
        { value = "PALADIN", label = "Paladin" },
        { value = "HUNTER", label = "Hunter" },
        { value = "ROGUE", label = "Rogue" },
        { value = "PRIEST", label = "Priest" },
        { value = "DEATHKNIGHT", label = "Death Knight" },
        { value = "SHAMAN", label = "Shaman" },
        { value = "MAGE", label = "Mage" },
        { value = "WARLOCK", label = "Warlock" },
        { value = "MONK", label = "Monk" },
        { value = "DRUID", label = "Druid" },
        { value = "DEMONHUNTER", label = "Demon Hunter" },
        { value = "EVOKER", label = "Evoker" },
    }
    selectedClass = editingBuff and editingBuff.class or nil

    local classDropdown =
        CreateFrame("Frame", "BuffRemindersCustomClassDropdown", advancedFrame, "UIDropDownMenuTemplate")
    classDropdown:SetPoint("LEFT", classLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(classDropdown, 100)

    UIDropDownMenu_Initialize(classDropdown, function(_, level)
        for _, cls in ipairs(classOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = cls.label
            info.value = cls.value
            info.checked = selectedClass == cls.value
            info.func = function()
                selectedClass = cls.value
                UIDropDownMenu_SetSelectedValue(classDropdown, cls.value)
                UIDropDownMenu_SetText(classDropdown, cls.label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(classDropdown, selectedClass)
    for _, cls in ipairs(classOptions) do
        if cls.value == selectedClass then
            UIDropDownMenu_SetText(classDropdown, cls.label)
            break
        end
    end

    -- Advanced toggle handler
    advancedBtn:SetScript("OnClick", function()
        advancedShown = not advancedShown
        if advancedShown then
            advancedText:SetText("[-] Hide Advanced Options")
            advancedFrame:Show()
        else
            advancedText:SetText("[+] Show Advanced Options")
            advancedFrame:Hide()
        end
        UpdateLayout()
    end)

    -- Error message
    local saveError = modal:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    saveError:SetPoint("BOTTOMLEFT", 20, 42)
    saveError:SetWidth(MODAL_WIDTH - 120)
    saveError:SetJustifyH("LEFT")
    saveError:SetTextColor(1, 0.3, 0.3)

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, modal, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        modal:Hide()
    end)

    -- Save button
    local saveBtn = CreateFrame("Button", nil, modal, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, 22)
    saveBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        -- Collect validated spell IDs
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

        -- Store as single number if only one, array if multiple
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
            class = selectedClass,
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

    -- Initialize rows
    if #existingSpellIDs > 0 then
        for _, spellID in ipairs(existingSpellIDs) do
            CreateSpellRow(spellID)
        end
    else
        CreateSpellRow(nil)
    end

    -- Initial layout
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
