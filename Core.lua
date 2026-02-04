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

---Create a styled button using standard Blizzard dynamic resize template
---@param parent Frame
---@param text string
---@param onClick function
---@param tooltip? {title: string, desc?: string} Optional tooltip configuration
---@return table
function BR.CreateButton(parent, text, onClick, tooltip)
    local btn = CreateFrame("Button", nil, parent, "UIPanelDynamicResizeButtonTemplate")
    btn:SetText(text)
    DynamicResizeButton_Resize(btn)
    btn:SetScript("OnClick", onClick)
    if tooltip then
        BR.SetupTooltip(btn, tooltip.title, tooltip.desc, "ANCHOR_TOP")
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
})
BR.CallbackRegistry = CallbackRegistry

-- ============================================================================
-- CONFIG SYSTEM (Event-Driven Settings)
-- ============================================================================
-- Centralized settings management with automatic callback triggering.
-- UI components call Config.Set() and interested systems subscribe to changes.
--
-- TODO: Add validation like Platynator:
-- 1. Centralized settings registry with defaults and refresh types
-- 2. IsValidOption() to catch typos at runtime
-- 3. Debug mode that warns on unknown config paths

BR.Config = {}

-- Refresh types: which callback to fire for each setting
-- Settings not listed here just fire "SettingChanged"
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
---@param path string Dot-separated path like "main.iconSize" or "enabledBuffs.intellect"
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

    -- Fire type-specific refresh callback if applicable
    -- Check each segment for a refresh type (e.g., "main.iconSize" matches "iconSize")
    for _, segment in ipairs(segments) do
        local refreshType = RefreshType[segment]
        if refreshType then
            CallbackRegistry:TriggerEvent(refreshType, path)
            break
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

                -- Collect refresh types
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

    -- Fire each unique refresh type once
    for refreshType in pairs(refreshTypes) do
        CallbackRegistry:TriggerEvent(refreshType)
    end
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
