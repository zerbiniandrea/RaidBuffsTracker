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
