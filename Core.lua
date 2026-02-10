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
    frameLocked = nil, -- No refresh needed
    hideInCombat = nil,
    showOnlyInGroup = nil,
    position = nil, -- Table with x, y
    buffTrackingMode = nil, -- No auto-refresh, manually calls UpdateDisplay
}

-- Per-category settings (path = categorySettings.{category}.{key})
local CategorySettingKeys = {
    -- Appearance (visual properties)
    iconSize = "VisualsRefresh",
    iconZoom = "VisualsRefresh",
    borderSize = "VisualsRefresh",
    textSize = "VisualsRefresh",
    iconAlpha = "VisualsRefresh",
    textAlpha = "VisualsRefresh",
    textColor = "VisualsRefresh",
    spacing = "LayoutRefresh",
    growDirection = "LayoutRefresh",
    -- Layout
    priority = "LayoutRefresh",
    -- Behavior
    showBuffReminder = "VisualsRefresh",
    showText = "VisualsRefresh",
    -- Toggles
    useCustomAppearance = nil, -- No refresh, just toggle state
    split = "FramesReparent",
    clickable = nil, -- No auto-refresh, handled manually via UpdateClickOverlays
    clickableHighlight = nil, -- No auto-refresh, handled manually via UpdateClickOverlays
}

-- Defaults settings (path = defaults.{key})
local DefaultSettingKeys = {
    -- Appearance
    iconSize = "VisualsRefresh",
    iconZoom = "VisualsRefresh",
    borderSize = "VisualsRefresh",
    textSize = "VisualsRefresh",
    iconAlpha = "VisualsRefresh",
    textAlpha = "VisualsRefresh",
    textColor = "VisualsRefresh",
    spacing = "LayoutRefresh",
    growDirection = "LayoutRefresh",
    -- Behavior (glow is global-only, lives under defaults)
    showExpirationGlow = "VisualsRefresh",
    expirationThreshold = "VisualsRefresh",
    glowStyle = "VisualsRefresh",
    -- Consumable rebuff warning
    showConsumablesWithoutItems = "DisplayRefresh",
    consumableRebuffWarning = "DisplayRefresh",
    consumableRebuffThreshold = "DisplayRefresh",
    consumableRebuffColor = "VisualsRefresh",
    -- Consumable display mode
    consumableDisplayMode = "DisplayRefresh",
    -- Pet display mode
    petDisplayMode = "DisplayRefresh",
    -- Font (global-only, lives under defaults)
    fontFace = "VisualsRefresh",
}

-- Valid category names
local ValidCategories = {
    main = true,
    raid = true,
    presence = true,
    targeted = true,
    self = true,
    pet = true,
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
    local isRootSetting = root == "frameLocked"
        or root == "hideInCombat"
        or root == "showOnlyInGroup"
        or root == "position"
        or root == "buffTrackingMode"
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
                "iconAlpha",
                "textAlpha",
                "textColor",
                "spacing",
                "growDirection",
                "showBuffReminder",
                "showText",
                "useCustomAppearance",
                "split",
                "clickable",
                "clickableHighlight",
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
    iconAlpha = true,
    textAlpha = true,
    textColor = true,
    spacing = true,
    iconZoom = true,
    borderSize = true,
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
        if not catSettings.useCustomAppearance then
            -- No custom appearance: always inherit from defaults
            return db.defaults and db.defaults[key]
        end
        -- Custom appearance: use category value only (independent from defaults)
        return catSettings[key]
    end

    -- Non-appearance keys: use category value if set, otherwise fall back to defaults
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

-- ============================================================================
-- CLASS SPEC OPTIONS (for custom buff spec filtering)
-- ============================================================================
-- Built once at load time. Keyed by class token, each value is a dropdown
-- options table with { value, label } entries.

local CLASS_IDS = {
    WARRIOR = 1,
    PALADIN = 2,
    HUNTER = 3,
    ROGUE = 4,
    PRIEST = 5,
    DEATHKNIGHT = 6,
    SHAMAN = 7,
    MAGE = 8,
    WARLOCK = 9,
    MONK = 10,
    DRUID = 11,
    DEMONHUNTER = 12,
    EVOKER = 13,
}

BR.CLASS_SPEC_OPTIONS = {}
for token, classID in pairs(CLASS_IDS) do
    local specs = {}
    for i = 1, 4 do
        local specID, name = GetSpecializationInfoForClassID(classID, i)
        if specID then
            table.insert(specs, { value = specID, label = name })
        end
    end
    table.sort(specs, function(a, b)
        return a.label < b.label
    end)
    local opts = { { value = nil, label = "Any" } }
    for _, spec in ipairs(specs) do
        table.insert(opts, spec)
    end
    BR.CLASS_SPEC_OPTIONS[token] = opts
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
