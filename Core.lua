local _, BR = ...

-- ============================================================================
-- SHARED NAMESPACE
-- ============================================================================
-- This file establishes the BR namespace used by all addon files.
-- It loads first (per TOC order) so other files can access BR.* functions.

-- Component factory table (populated by Components.lua)
BR.Components = {}

-- Registry of refreshable components (for OnShow refresh pattern)
-- Components with a get() function register here automatically
BR.RefreshableComponents = {}

-- ============================================================================
-- SHARED UI UTILITIES
-- ============================================================================

---Setup tooltip on hover for a widget
---@param widget table
---@param tooltipTitle string
---@param tooltipDesc? string
---@param anchor? string
function BR.SetupTooltip(widget, tooltipTitle, tooltipDesc, anchor)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltipTitle)
        if tooltipDesc then
            GameTooltip:AddLine(tooltipDesc, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Modern button color constants
BR.ButtonColors = {
    bg = { 0.15, 0.15, 0.15, 1 },
    bgHover = { 0.22, 0.22, 0.22, 1 },
    bgPressed = { 0.12, 0.12, 0.12, 1 },
    border = { 0.3, 0.3, 0.3, 1 },
    borderHover = { 0.5, 0.5, 0.5, 1 },
    borderPressed = { 1, 0.82, 0, 1 },
    borderDisabled = { 0.25, 0.25, 0.25, 1 },
    text = { 1, 1, 1, 1 },
    textDisabled = { 0.5, 0.5, 0.5, 1 },
}

---Create a modern flat-style button with dark background and thin border
---@param parent Frame
---@param text string
---@param onClick function
---@param tooltip? {title: string, desc?: string} Optional tooltip configuration
---@return table
function BR.CreateButton(parent, text, onClick, tooltip)
    local colors = BR.ButtonColors

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(unpack(colors.bg))
    btn:SetBackdropBorderColor(unpack(colors.border))

    -- Text
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText(text)
    btn.text = btnText

    -- Auto-size based on text with padding
    local textWidth = btnText:GetStringWidth()
    btn:SetSize(math.max(textWidth + 16, 60), 22)

    -- Visual state tracking
    local isEnabled = true
    local isPressed = false
    local isHovered = false

    local function UpdateVisual()
        if not isEnabled then
            btn:SetBackdropColor(unpack(colors.bg))
            btn:SetBackdropBorderColor(unpack(colors.borderDisabled))
            btnText:SetTextColor(unpack(colors.textDisabled))
        elseif isPressed then
            btn:SetBackdropColor(unpack(colors.bgPressed))
            btn:SetBackdropBorderColor(unpack(colors.borderPressed))
            btnText:SetTextColor(unpack(colors.text))
        elseif isHovered then
            btn:SetBackdropColor(unpack(colors.bgHover))
            btn:SetBackdropBorderColor(unpack(colors.borderHover))
            btnText:SetTextColor(unpack(colors.text))
        else
            btn:SetBackdropColor(unpack(colors.bg))
            btn:SetBackdropBorderColor(unpack(colors.border))
            btnText:SetTextColor(unpack(colors.text))
        end
    end

    btn:SetScript("OnEnter", function()
        isHovered = true
        UpdateVisual()
        if tooltip then
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip.title)
            if tooltip.desc then
                GameTooltip:AddLine(tooltip.desc, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function()
        isHovered = false
        isPressed = false
        UpdateVisual()
        if tooltip then
            GameTooltip:Hide()
        end
    end)

    btn:SetScript("OnMouseDown", function()
        if isEnabled then
            isPressed = true
            UpdateVisual()
        end
    end)

    btn:SetScript("OnMouseUp", function()
        isPressed = false
        UpdateVisual()
    end)

    btn:SetScript("OnClick", function()
        if isEnabled and onClick then
            onClick(btn)
        end
    end)

    -- Public methods
    function btn:SetText(newText)
        btnText:SetText(newText)
        local newWidth = btnText:GetStringWidth()
        self:SetSize(math.max(newWidth + 16, 60), 22)
    end

    function btn:GetText()
        return btnText:GetText()
    end

    function btn:SetEnabled(enabled)
        isEnabled = enabled
        if enabled then
            self:Enable()
        else
            self:Disable()
        end
        UpdateVisual()
    end

    return btn
end

-- ============================================================================
-- SHARED CONSTANTS
-- ============================================================================

BR.TEXCOORD_INSET = 0.08
BR.DEFAULT_BORDER_SIZE = 2
BR.DEFAULT_ICON_ZOOM = 8 -- percentage (0.08 as inset)
BR.OPTIONS_BASE_SCALE = 1.2

-- ============================================================================
-- CALLBACK REGISTRY (Event System)
-- ============================================================================
-- Pub/sub system for decoupled communication between modules.
-- Based on Blizzard's CallbackRegistryMixin pattern.

local CallbackRegistry = CreateFromMixins(CallbackRegistryMixin)
CallbackRegistry:OnLoad()
CallbackRegistry:GenerateCallbackEvents({
    "SettingChanged", -- Fired when any setting changes: (settingName, newValue, oldValue)
    "DisplayRefresh", -- Fired when display needs full refresh
    "VisualsRefresh", -- Fired when visual properties (size, zoom, border) change
    "LayoutRefresh", -- Fired when layout needs recalculation (spacing, direction)
    "FramesReparent", -- Fired when frames need reparenting (split category change)
    "BuffStateChanged", -- Fired when buff state entries are recomputed
})
BR.CallbackRegistry = CallbackRegistry

-- ============================================================================
-- CONFIG SYSTEM (Event-Driven Settings)
-- ============================================================================
-- Centralized settings management with automatic callback triggering.
-- UI components call Config.Set() and interested systems subscribe to changes.
--
-- Validation: Paths are validated against registered settings. Invalid paths
-- print a warning in debug mode to catch typos early.

BR.Config = {}

-- Debug mode: set to true to print warnings for invalid config paths
BR.Config.DebugMode = false

-- ============================================================================
-- SETTINGS REGISTRY (Single Source of Truth)
-- ============================================================================
-- All valid settings defined here with their refresh types.
-- This catches typos and documents the config structure.

-- Root-level settings (path = key directly)
local RootSettings = {
    splitCategories = "FramesReparent",
    showBuffReminder = "VisualsRefresh",
    frameLocked = nil, -- No refresh needed
    hideInCombat = nil,
    showOnlyInGroup = nil,
    position = nil, -- Table with x, y
}

-- Per-category settings (path = categorySettings.{category}.{key})
local CategorySettingKeys = {
    -- Appearance (visual properties)
    iconSize = "VisualsRefresh",
    iconZoom = "VisualsRefresh",
    borderSize = "VisualsRefresh",
    textSize = "VisualsRefresh",
    spacing = "LayoutRefresh",
    growDirection = "LayoutRefresh",
    -- Behavior
    showBuffReminder = "VisualsRefresh",
    showExpirationGlow = "VisualsRefresh",
    expirationThreshold = "VisualsRefresh",
    glowStyle = "VisualsRefresh",
    -- Toggles
    useCustomAppearance = nil, -- No refresh, just toggle state
    useCustomBehavior = nil, -- No refresh, just toggle state
    split = "FramesReparent",
}

-- Defaults settings (path = defaults.{key})
local DefaultSettingKeys = {
    -- Appearance
    iconSize = "VisualsRefresh",
    iconZoom = "VisualsRefresh",
    borderSize = "VisualsRefresh",
    textSize = "VisualsRefresh",
    spacing = "LayoutRefresh",
    growDirection = "LayoutRefresh",
    -- Behavior
    showBuffReminder = "VisualsRefresh",
    showExpirationGlow = "VisualsRefresh",
    expirationThreshold = "VisualsRefresh",
    glowStyle = "VisualsRefresh",
}

-- Valid category names
local ValidCategories = {
    main = true,
    raid = true,
    presence = true,
    targeted = true,
    self = true,
    consumable = true,
    custom = true,
}

-- Dynamic tables (path = {root}.{anyKey})
-- These allow any second-level key (buff names, visibility contexts, etc.)
local DynamicRoots = {
    enabledBuffs = "DisplayRefresh",
    categoryVisibility = "DisplayRefresh",
    splitCategories = "FramesReparent",
}

---Check if a config path is valid
---@param segments string[] Path segments
---@return boolean isValid
---@return string? refreshType
local function ValidatePath(segments)
    if #segments == 0 then
        return false, nil
    end

    local root = segments[1]

    -- Check root-level settings (explicit key check since some have nil refresh type)
    local isRootSetting = root == "showBuffReminder"
        or root == "frameLocked"
        or root == "hideInCombat"
        or root == "showOnlyInGroup"
        or root == "position"
    if isRootSetting then
        if #segments == 1 then
            return true, RootSettings[root]
        end
        -- position.x, position.y are valid
        if root == "position" and #segments == 2 then
            return true, nil
        end
        return false, nil
    end

    -- Check defaults.{setting}
    if root == "defaults" then
        if #segments == 1 then
            return true, nil -- Just "defaults" is valid
        end
        if #segments == 2 then
            local setting = segments[2]
            if DefaultSettingKeys[setting] ~= nil then
                return true, DefaultSettingKeys[setting]
            end
            -- position is also valid under defaults
            if setting == "position" then
                return true, nil
            end
            return false, nil
        end
        return false, nil
    end

    -- Check categorySettings.{category}.{setting}
    if root == "categorySettings" then
        if #segments < 2 then
            return true, nil -- Just "categorySettings" is valid (for iteration)
        end
        local category = segments[2]
        if not ValidCategories[category] then
            return false, nil
        end
        if #segments == 2 then
            return true, nil -- Just "categorySettings.main" is valid
        end
        if #segments == 3 then
            local setting = segments[3]
            -- Check if it's a known category setting key (including those with nil refresh)
            local knownKeys = {
                "position",
                "iconSize",
                "iconZoom",
                "borderSize",
                "textSize",
                "spacing",
                "growDirection",
                "showBuffReminder",
                "showExpirationGlow",
                "expirationThreshold",
                "glowStyle",
                "useCustomAppearance",
                "useCustomBehavior",
                "split",
            }
            for _, key in ipairs(knownKeys) do
                if setting == key then
                    return true, CategorySettingKeys[setting]
                end
            end
            return false, nil
        end
        return false, nil
    end

    -- Check dynamic roots (enabledBuffs.*, categoryVisibility.*, splitCategories.*)
    if DynamicRoots[root] then
        -- Any subpath is valid for dynamic roots
        return true, DynamicRoots[root]
    end

    return false, nil
end

---Check if a config path is valid and get its refresh type
---@param path string Dot-separated path
---@return boolean isValid
---@return string? refreshType
function BR.Config.IsValidPath(path)
    local segments = {}
    for segment in path:gmatch("[^.]+") do
        table.insert(segments, segment)
    end
    return ValidatePath(segments)
end

-- Legacy RefreshType lookup (for backward compatibility with segment-based lookup)
local RefreshType = {
    -- Visual properties
    ["iconSize"] = "VisualsRefresh",
    ["iconZoom"] = "VisualsRefresh",
    ["borderSize"] = "VisualsRefresh",
    ["showBuffReminder"] = "VisualsRefresh",
    -- Layout properties
    ["spacing"] = "LayoutRefresh",
    ["growDirection"] = "LayoutRefresh",
    -- Structural changes
    ["splitCategories"] = "FramesReparent",
    -- Display changes (enabledBuffs, visibility)
    ["enabledBuffs"] = "DisplayRefresh",
    ["categoryVisibility"] = "DisplayRefresh",
}

---Set a config value and trigger appropriate callbacks
---@param path string Dot-separated path like "categorySettings.main.iconSize" or "enabledBuffs.intellect"
---@param value any The new value
function BR.Config.Set(path, value)
    local db = BuffRemindersDB
    if not db then
        return
    end

    -- Parse path into segments
    local segments = {}
    for segment in path:gmatch("[^.]+") do
        table.insert(segments, segment)
    end

    if #segments == 0 then
        return
    end

    -- Validate path (debug mode only warns, doesn't block)
    local isValid, validatedRefreshType = ValidatePath(segments)
    if not isValid and BR.Config.DebugMode then
        print("|cffff6600BuffReminders:|r Invalid config path: " .. path)
    end

    -- Navigate to parent and get old value
    local parent = db
    for i = 1, #segments - 1 do
        local key = segments[i]
        if parent[key] == nil then
            parent[key] = {}
        end
        parent = parent[key]
    end

    local finalKey = segments[#segments]
    local oldValue = parent[finalKey]

    -- Don't trigger if value hasn't changed
    if oldValue == value then
        return
    end

    -- Set the new value
    parent[finalKey] = value

    -- Fire SettingChanged callback
    CallbackRegistry:TriggerEvent("SettingChanged", path, value, oldValue)

    -- Use validated refresh type if available, otherwise fall back to segment lookup
    if validatedRefreshType then
        CallbackRegistry:TriggerEvent(validatedRefreshType, path)
    else
        -- Legacy: check each segment for a refresh type
        for _, segment in ipairs(segments) do
            local refreshType = RefreshType[segment]
            if refreshType then
                CallbackRegistry:TriggerEvent(refreshType, path)
                break
            end
        end
    end
end

---Get a config value
---@param path string Dot-separated path like "main.iconSize"
---@param default? any Default value if not found
---@return any
function BR.Config.Get(path, default)
    local db = BuffRemindersDB
    if not db then
        return default
    end

    local current = db
    for segment in path:gmatch("[^.]+") do
        if type(current) ~= "table" then
            return default
        end
        current = current[segment]
        if current == nil then
            return default
        end
    end

    return current
end

---Set multiple config values at once (batched, single refresh)
---@param changes table<string, any> Map of path -> value
function BR.Config.SetMulti(changes)
    local db = BuffRemindersDB
    if not db then
        return
    end

    local refreshTypes = {}

    for path, value in pairs(changes) do
        -- Parse and set each value
        local segments = {}
        for segment in path:gmatch("[^.]+") do
            table.insert(segments, segment)
        end

        if #segments > 0 then
            -- Validate path (debug mode only warns, doesn't block)
            local isValid, validatedRefreshType = ValidatePath(segments)
            if not isValid and BR.Config.DebugMode then
                print("|cffff6600BuffReminders:|r Invalid config path: " .. path)
            end

            local parent = db
            for i = 1, #segments - 1 do
                local key = segments[i]
                if parent[key] == nil then
                    parent[key] = {}
                end
                parent = parent[key]
            end

            local finalKey = segments[#segments]
            local oldValue = parent[finalKey]

            if oldValue ~= value then
                parent[finalKey] = value
                CallbackRegistry:TriggerEvent("SettingChanged", path, value, oldValue)

                -- Collect refresh types (prefer validated, fall back to segment lookup)
                if validatedRefreshType then
                    refreshTypes[validatedRefreshType] = true
                else
                    for _, segment in ipairs(segments) do
                        local refreshType = RefreshType[segment]
                        if refreshType then
                            refreshTypes[refreshType] = true
                            break
                        end
                    end
                end
            end
        end
    end

    -- Fire each unique refresh type once
    for refreshType in pairs(refreshTypes) do
        CallbackRegistry:TriggerEvent(refreshType)
    end
end

-- ============================================================================
-- CATEGORY SETTING INHERITANCE
-- ============================================================================
-- Categories can inherit appearance and behavior settings from defaults,
-- or use their own custom values when useCustomAppearance/useCustomBehavior is true.

-- Keys that are appearance-related (inherit from defaults when useCustomAppearance is false)
local AppearanceKeys = {
    iconSize = true,
    textSize = true,
    spacing = true,
    iconZoom = true,
    borderSize = true,
}

-- Keys that are behavior-related (inherit from defaults when useCustomBehavior is false)
local BehaviorKeys = {
    showBuffReminder = true,
    showExpirationGlow = true,
    expirationThreshold = true,
    glowStyle = true,
}

---Get a category setting with inheritance from defaults
---@param category string Category name (raid, presence, etc.)
---@param key string Setting key (iconSize, showBuffReminder, etc.)
---@return any value The effective value for this setting
function BR.Config.GetCategorySetting(category, key)
    local db = BuffRemindersDB
    if not db then
        return nil
    end

    local catSettings = db.categorySettings and db.categorySettings[category]
    if not catSettings then
        -- No category settings, fall back to defaults
        return db.defaults and db.defaults[key]
    end

    -- Check if this key uses inheritance
    if AppearanceKeys[key] then
        -- Appearance: use custom value only if useCustomAppearance is true
        if not catSettings.useCustomAppearance then
            return db.defaults and db.defaults[key]
        end
    elseif BehaviorKeys[key] then
        -- Behavior: use custom value only if useCustomBehavior is true
        if not catSettings.useCustomBehavior then
            return db.defaults and db.defaults[key]
        end
    end

    -- Use category-specific value if set, otherwise fall back to defaults
    local value = catSettings[key]
    if value ~= nil then
        return value
    end
    return db.defaults and db.defaults[key]
end

---Check if a category has custom appearance enabled
---@param category string
---@return boolean
function BR.Config.HasCustomAppearance(category)
    local db = BuffRemindersDB
    if not db or not db.categorySettings or not db.categorySettings[category] then
        return false
    end
    return db.categorySettings[category].useCustomAppearance == true
end

---Check if a category has custom behavior enabled
---@param category string
---@return boolean
function BR.Config.HasCustomBehavior(category)
    local db = BuffRemindersDB
    if not db or not db.categorySettings or not db.categorySettings[category] then
        return false
    end
    return db.categorySettings[category].useCustomBehavior == true
end

-- ============================================================================
-- SHARED UI FACTORIES
-- ============================================================================

---Create a draggable panel with standard backdrop
---@param name string? Frame name (nil for anonymous)
---@param width number
---@param height number
---@param options? {bgColor?: table, borderColor?: table, strata?: string, level?: number, escClose?: boolean}
---@return table
function BR.CreatePanel(name, width, height, options)
    options = options or {}
    local bgColor = options.bgColor or { 0.1, 0.1, 0.1, 0.95 }
    local borderColor = options.borderColor or { 0.3, 0.3, 0.3, 1 }

    local panel = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetPoint("CENTER")
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    panel:SetBackdropColor(unpack(bgColor))
    panel:SetBackdropBorderColor(unpack(borderColor))
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata(options.strata or "DIALOG")
    if options.level then
        panel:SetFrameLevel(options.level)
    end
    if options.escClose and name then
        tinsert(UISpecialFrames, name)
    end
    return panel
end

---Create a section header with yellow text
---@param parent table
---@param text string
---@param x number
---@param y number
---@return table header
---@return number newY
function BR.CreateSectionHeader(parent, text, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", x, y)
    header:SetText("|cffffcc00" .. text .. "|r")
    return header, y - 18
end

---Create a buff icon texture with standard formatting
---@param parent table
---@param size number
---@param textureID? number|string
---@return table
function BR.CreateBuffIcon(parent, size, textureID)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexCoord(BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET, BR.TEXCOORD_INSET, 1 - BR.TEXCOORD_INSET)
    if textureID then
        icon:SetTexture(textureID)
    end
    return icon
end
