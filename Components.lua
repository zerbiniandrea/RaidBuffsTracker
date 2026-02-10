local _, BR = ...

-- ============================================================================
-- UI COMPONENT FACTORY
-- ============================================================================
-- Reusable UI components for the options panel (Platynator-style factory pattern).
-- These reduce code duplication and provide consistent styling.

local Components = BR.Components
local RefreshableComponents = BR.RefreshableComponents

-- ============================================================================
-- TOOLTIP UTILITIES
-- ============================================================================

---Show a tooltip on a widget (title in gold, optional description in white)
---@param owner table Frame that owns the tooltip
---@param title string Tooltip title
---@param desc? string Optional description line
---@param anchor? string Anchor point (default "ANCHOR_RIGHT")
local function ShowTooltip(owner, title, desc, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if desc then
        GameTooltip:AddLine(desc, 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

---Setup tooltip on a widget using SetScript (replaces existing OnEnter/OnLeave)
local function SetupTooltip(widget, tooltipTitle, tooltipDesc, anchor)
    widget:SetScript("OnEnter", function(self)
        ShowTooltip(self, tooltipTitle, tooltipDesc, anchor)
    end)
    widget:SetScript("OnLeave", HideTooltip)
end

---Setup tooltip on a widget using HookScript (chains with existing OnEnter/OnLeave)
local function HookTooltip(widget, tooltipTitle, tooltipDesc, anchor)
    widget:HookScript("OnEnter", function(self)
        ShowTooltip(self, tooltipTitle, tooltipDesc, anchor)
    end)
    widget:HookScript("OnLeave", HideTooltip)
end

BR.ShowTooltip = ShowTooltip
BR.HideTooltip = HideTooltip
BR.SetupTooltip = SetupTooltip
BR.HookTooltip = HookTooltip

-- ============================================================================
-- BUTTON
-- ============================================================================

-- Modern button color constants
local ButtonColors = {
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
    local colors = ButtonColors

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
            ShowTooltip(btn, tooltip.title, tooltip.desc, "ANCHOR_TOP")
        end
    end)

    btn:SetScript("OnLeave", function()
        isHovered = false
        isPressed = false
        UpdateVisual()
        if tooltip then
            HideTooltip()
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

---@class ComponentConfig
---@class SliderConfig : ComponentConfig
---@field label string Display label for the slider
---@field min number Minimum value
---@field max number Maximum value
---@field step? number Step increment (default 1)
---@field value? number Initial value (deprecated: prefer get)
---@field get? fun(): number Getter for initial value and refresh (preferred over value)
---@field enabled? fun(): boolean Getter for enabled state, evaluated on Refresh()
---@field suffix? string Value suffix (e.g., "px", "%")
---@field onChange fun(val: number) Callback when value changes
---@field tooltip? string|{title: string, desc?: string} Tooltip shown on hover (string or {title, desc} table)
---@field labelWidth? number Width of label (default 70)
---@field sliderWidth? number Width of slider (default 100)

---@class DirectionButtonsConfig : ComponentConfig
---@field label? string Optional label (default "Direction:")
---@field selected? string Initial direction (deprecated: prefer get)
---@field get? fun(): string Getter for initial value and refresh (preferred over selected)
---@field enabled? fun(): boolean Getter for enabled state, evaluated on Refresh()
---@field onChange fun(dir: string) Callback when direction changes
---@field width? number Dropdown width (default 90)

---@class CategoryHeaderConfig : ComponentConfig
---@field text string Header text
---@field category CategoryName Category for visibility toggles

-- Panel EditBoxes tracking (populated by CreateOptionsPanel, used by Components)
local panelEditBoxes = nil ---@type table[]?

-- Modern slider color constants
local SliderColors = {
    track = { 0.2, 0.2, 0.2, 1 },
    trackFill = { 0.6, 0.5, 0.1, 1 }, -- Subtle gold fill
    trackDisabled = { 0.15, 0.15, 0.15, 1 },
    thumb = { 0.4, 0.4, 0.4, 1 },
    thumbHover = { 1, 0.82, 0, 1 }, -- Golden on hover
    thumbDisabled = { 0.25, 0.25, 0.25, 1 },
    text = { 1, 1, 1, 1 },
    textDisabled = { 0.5, 0.5, 0.5, 1 },
}

-- TextInput color constants (shared with StyleEditBox and TextArea)
local TextInputColors = {
    bg = { 0.08, 0.08, 0.08, 0.9 },
    bgFocused = { 0.1, 0.1, 0.1, 0.95 },
    border = { 0.3, 0.3, 0.3, 1 },
    borderFocused = { 1, 0.82, 0, 1 },
}

---Style any EditBox with dark flat UI (dark bg, gray border, gold focus highlight).
---Wraps the EditBox in a BackdropTemplate container. Caller should set size/position on the returned container.
---@param editBox table The EditBox to style
---@return table container The backdrop container frame
local function StyleEditBox(editBox)
    local colors = TextInputColors
    local parent = editBox:GetParent()

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    container:SetBackdropColor(unpack(colors.bg))
    container:SetBackdropBorderColor(unpack(colors.border))

    editBox:SetParent(container)
    editBox:ClearAllPoints()
    editBox:SetPoint("TOPLEFT", 4, -2)
    editBox:SetPoint("BOTTOMRIGHT", -4, 2)
    editBox:SetTextColor(1, 1, 1, 1)

    editBox:HookScript("OnEditFocusGained", function()
        container:SetBackdropColor(unpack(colors.bgFocused))
        container:SetBackdropBorderColor(unpack(colors.borderFocused))
    end)

    editBox:HookScript("OnEditFocusLost", function()
        container:SetBackdropColor(unpack(colors.bg))
        container:SetBackdropBorderColor(unpack(colors.border))
    end)

    editBox:HookScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    return container
end

BR.StyleEditBox = StyleEditBox

---Create a modern flat-style slider with thin track and small thumb
---@param parent table Parent frame
---@param config SliderConfig Configuration table
---@return table holder Frame containing slider with .slider, .valueText, .SetValue(v), .GetValue()
function Components.Slider(parent, config)
    local colors = SliderColors
    local labelWidth = config.labelWidth or (config.label and 70 or 0)
    local sliderWidth = config.sliderWidth or 100
    local step = config.step or 1
    local suffix = config.suffix or ""
    local TRACK_HEIGHT = 4
    local THUMB_WIDTH = 8
    local THUMB_HEIGHT = 14

    -- Container frame
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(labelWidth + sliderWidth + 60, 20)

    -- Label
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(labelWidth)
    label:SetJustifyH("LEFT")
    if config.label then
        label:SetText(config.label)
    end
    holder.label = label

    -- Slider track container
    local sliderFrame = CreateFrame("Frame", nil, holder)
    sliderFrame:SetPoint("LEFT", label, "RIGHT", 5, 0)
    sliderFrame:SetSize(sliderWidth, 16)
    holder.slider = sliderFrame

    -- Track background
    local trackBg = sliderFrame:CreateTexture(nil, "BACKGROUND")
    trackBg:SetHeight(TRACK_HEIGHT)
    trackBg:SetPoint("LEFT", 0, 0)
    trackBg:SetPoint("RIGHT", 0, 0)
    trackBg:SetColorTexture(unpack(colors.track))
    sliderFrame.trackBg = trackBg

    -- Track fill (shows value progress)
    local trackFill = sliderFrame:CreateTexture(nil, "ARTWORK")
    trackFill:SetHeight(TRACK_HEIGHT)
    trackFill:SetPoint("LEFT", trackBg, "LEFT", 0, 0)
    trackFill:SetColorTexture(unpack(colors.trackFill))
    sliderFrame.trackFill = trackFill

    -- Thumb
    local thumb = CreateFrame("Button", nil, sliderFrame)
    thumb:SetSize(THUMB_WIDTH, THUMB_HEIGHT)
    thumb:SetPoint("CENTER", trackBg, "LEFT", 0, 0)

    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(unpack(colors.thumb))
    thumb.tex = thumbTex

    -- State
    local currentValue = config.get and config.get() or config.value or config.min
    local isEnabled = true
    local isDragging = false
    local isThumbHovered = false

    -- Clickable value display button (declared early for event handlers)
    local valueBtn = CreateFrame("Button", nil, holder)
    valueBtn:SetPoint("LEFT", sliderFrame, "RIGHT", 6, 0)
    valueBtn:SetSize(40, 16)

    local valueText = valueBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetAllPoints()
    valueText:SetJustifyH("LEFT")
    valueText:SetText(math.floor(currentValue) .. suffix)
    holder.valueText = valueText

    local function ValueToPosition(val)
        local range = config.max - config.min
        if range == 0 then
            return 0
        end
        local pct = (val - config.min) / range
        return pct * (sliderWidth - THUMB_WIDTH)
    end

    local function PositionToValue(pos)
        local pct = pos / (sliderWidth - THUMB_WIDTH)
        pct = math.max(0, math.min(1, pct))
        local val = config.min + pct * (config.max - config.min)
        -- Round to step
        val = math.floor((val - config.min) / step + 0.5) * step + config.min
        return math.max(config.min, math.min(config.max, val))
    end

    local function UpdateThumbPosition()
        local pos = ValueToPosition(currentValue)
        thumb:SetPoint("CENTER", trackBg, "LEFT", pos + THUMB_WIDTH / 2, 0)
        trackFill:SetWidth(math.max(1, pos + THUMB_WIDTH / 2))
    end

    local function UpdateVisual()
        if not isEnabled then
            thumbTex:SetColorTexture(unpack(colors.thumbDisabled))
            trackBg:SetColorTexture(unpack(colors.trackDisabled))
            trackFill:SetColorTexture(0.3, 0.25, 0.05, 1) -- Dimmed fill
        elseif isThumbHovered or isDragging then
            thumbTex:SetColorTexture(unpack(colors.thumbHover))
            trackBg:SetColorTexture(unpack(colors.track))
            trackFill:SetColorTexture(unpack(colors.trackFill))
        else
            thumbTex:SetColorTexture(unpack(colors.thumb))
            trackBg:SetColorTexture(unpack(colors.track))
            trackFill:SetColorTexture(unpack(colors.trackFill))
        end
        UpdateThumbPosition()
    end

    thumb:SetScript("OnEnter", function()
        isThumbHovered = true
        UpdateVisual()
    end)

    thumb:SetScript("OnLeave", function()
        isThumbHovered = false
        UpdateVisual()
    end)

    thumb:SetScript("OnMouseDown", function()
        if isEnabled then
            isDragging = true
            UpdateVisual()
        end
    end)

    thumb:SetScript("OnMouseUp", function()
        isDragging = false
        UpdateVisual()
    end)

    -- Dragging logic
    sliderFrame:SetScript("OnUpdate", function()
        if isDragging and isEnabled then
            local mouseX = GetCursorPosition()
            local scale = sliderFrame:GetEffectiveScale()
            local frameLeft = sliderFrame:GetLeft() * scale
            local localX = (mouseX - frameLeft) / scale - THUMB_WIDTH / 2
            local newVal = PositionToValue(localX)
            if newVal ~= currentValue then
                currentValue = newVal
                valueText:SetText(math.floor(currentValue) .. suffix)
                UpdateThumbPosition()
                config.onChange(math.floor(currentValue))
            end
        end
    end)

    -- Click on track to jump
    sliderFrame:EnableMouse(true)
    sliderFrame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and isEnabled then
            local mouseX = GetCursorPosition()
            local scale = sliderFrame:GetEffectiveScale()
            local frameLeft = sliderFrame:GetLeft() * scale
            local localX = (mouseX - frameLeft) / scale - THUMB_WIDTH / 2
            local newVal = PositionToValue(localX)
            currentValue = newVal
            valueText:SetText(math.floor(currentValue) .. suffix)
            UpdateVisual()
            config.onChange(math.floor(currentValue))
            isDragging = true
        end
    end)

    sliderFrame:SetScript("OnMouseUp", function()
        isDragging = false
        UpdateVisual()
    end)

    -- Edit box (hidden by default)
    local editBox = CreateFrame("EditBox", nil, holder)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    local editContainer = StyleEditBox(editBox)
    editContainer:SetSize(35, 16)
    editContainer:SetPoint("LEFT", sliderFrame, "RIGHT", 6, 0)
    editContainer:Hide()

    editBox:SetScript("OnEnterPressed", function(self)
        local num = tonumber(self:GetText())
        if num then
            num = math.max(config.min, math.min(config.max, num))
            currentValue = num
            valueText:SetText(math.floor(currentValue) .. suffix)
            UpdateVisual()
            config.onChange(math.floor(currentValue))
        end
        editContainer:Hide()
        valueBtn:Show()
    end)

    editBox:SetScript("OnEscapePressed", function()
        editContainer:Hide()
        valueBtn:Show()
    end)

    editBox:SetScript("OnEditFocusLost", function()
        editContainer:Hide()
        valueBtn:Show()
    end)

    -- Track editbox for focus cleanup on panel hide
    if panelEditBoxes then
        table.insert(panelEditBoxes, editBox)
    end

    valueBtn:SetScript("OnClick", function()
        valueBtn:Hide()
        editBox:SetText(tostring(math.floor(currentValue)))
        editContainer:Show()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    SetupTooltip(valueBtn, "Adjust value", "Click to type or use mouse wheel", "ANCHOR_TOP")

    -- Mouse wheel support
    holder:EnableMouseWheel(true)
    holder:SetScript("OnMouseWheel", function(_, delta)
        if isEnabled then
            local newVal = currentValue + (delta * step)
            newVal = math.max(config.min, math.min(config.max, newVal))
            currentValue = newVal
            valueText:SetText(math.floor(currentValue) .. suffix)
            UpdateVisual()
            config.onChange(math.floor(currentValue))
        end
    end)

    -- Hover tooltip (on all interactive children, chained with existing scripts)
    local wheelHint = "Use mouse wheel to adjust"
    if config.tooltip then
        local title, desc
        if type(config.tooltip) == "table" then
            title = config.tooltip.title
            desc = config.tooltip.desc
        else
            title = config.tooltip --[[@as string]]
        end
        local fullDesc = desc and (desc .. "\n\n" .. wheelHint) or wheelHint
        holder:EnableMouse(true)
        local function showTip()
            ShowTooltip(holder, title, fullDesc, "ANCHOR_TOP")
        end
        local function hideTip()
            HideTooltip()
        end
        holder:HookScript("OnEnter", showTip)
        holder:HookScript("OnLeave", hideTip)
        thumb:HookScript("OnEnter", showTip)
        thumb:HookScript("OnLeave", hideTip)
        sliderFrame:HookScript("OnEnter", showTip)
        sliderFrame:HookScript("OnLeave", hideTip)
        valueBtn:HookScript("OnEnter", showTip)
        valueBtn:HookScript("OnLeave", hideTip)
    else
        local function showHint()
            ShowTooltip(holder, wheelHint, nil, "ANCHOR_TOP")
        end
        thumb:HookScript("OnEnter", showHint)
        thumb:HookScript("OnLeave", HideTooltip)
        sliderFrame:SetScript("OnEnter", showHint)
        sliderFrame:SetScript("OnLeave", HideTooltip)
    end

    -- Initial visual
    UpdateVisual()

    -- Public methods
    function holder:SetValue(val)
        currentValue = val
        valueText:SetText(math.floor(currentValue) .. suffix)
        UpdateVisual()
    end

    function holder:GetValue()
        return currentValue
    end

    function holder:SetEnabled(enabled)
        isEnabled = enabled
        local color = enabled and 1 or 0.5
        label:SetTextColor(color, color, color)
        valueText:SetTextColor(color, color, color)
        UpdateVisual()
    end

    -- For compatibility with old code checking slider:IsEnabled()
    function sliderFrame:IsEnabled()
        return isEnabled
    end

    -- Refresh method for OnShow pattern (re-reads value and enabled state from DB)
    function holder:Refresh()
        if config.get then
            currentValue = config.get()
            valueText:SetText(math.floor(currentValue) .. suffix)
            UpdateVisual()
        end
        if config.enabled then
            holder:SetEnabled(config.enabled())
        end
    end

    -- Auto-register if refreshable
    if config.get or config.enabled then
        table.insert(RefreshableComponents, holder)
    end

    return holder
end

-- Modern checkbox color constants
local CheckboxColors = {
    bg = { 0.12, 0.12, 0.12, 1 },
    bgHover = { 0.16, 0.16, 0.16, 1 },
    bgChecked = { 0.15, 0.13, 0.08, 1 }, -- Subtle warm tint when checked
    border = { 0.3, 0.3, 0.3, 1 },
    borderHover = { 0.45, 0.45, 0.45, 1 },
    borderChecked = { 0.6, 0.5, 0.2, 1 }, -- Subtle golden border when checked
    borderDisabled = { 0.2, 0.2, 0.2, 1 },
    checkmark = { 0.9, 0.75, 0.2, 1 }, -- Softer golden checkmark
    checkmarkDisabled = { 0.5, 0.42, 0.1, 1 },
    text = { 1, 1, 1, 1 },
    textDisabled = { 0.5, 0.5, 0.5, 1 },
}

---Create the core checkbox button frame (reusable by Checkbox component)
---@param parent table Parent frame
---@param initialChecked boolean Initial checked state
---@param onChange fun(checked: boolean) Callback when state changes
---@return table cb Checkbox button with .SetChecked(v), .GetChecked(), .SetHovered(v), .SetEnabled(v)
local function CreateCheckboxCore(parent, initialChecked, onChange)
    local colors = CheckboxColors
    local CHECKBOX_SIZE = 16 -- Match icon size for alignment

    local cb = CreateFrame("Button", nil, parent, "BackdropTemplate")
    cb:SetSize(CHECKBOX_SIZE, CHECKBOX_SIZE)
    cb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    cb:SetBackdropColor(unpack(colors.bg))
    cb:SetBackdropBorderColor(unpack(colors.border))

    -- Checkmark texture (sized to fit within checkbox)
    local checkmark = cb:CreateTexture(nil, "ARTWORK")
    checkmark:SetPoint("CENTER", 0, 0)
    checkmark:SetSize(CHECKBOX_SIZE + 4, CHECKBOX_SIZE + 4) -- Slightly larger for visual punch
    checkmark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkmark:SetVertexColor(unpack(colors.checkmark))
    checkmark:Hide()
    cb.checkmark = checkmark

    -- State
    local isChecked = initialChecked or false
    local isEnabled = true
    local isHovered = false

    local function UpdateVisual()
        if isChecked then
            checkmark:Show()
        else
            checkmark:Hide()
        end

        if not isEnabled then
            cb:SetBackdropBorderColor(unpack(colors.borderDisabled))
            cb:SetBackdropColor(0.08, 0.08, 0.08, 1)
            checkmark:SetVertexColor(unpack(colors.checkmarkDisabled))
        elseif isChecked and isHovered then
            cb:SetBackdropBorderColor(unpack(colors.borderHover))
            cb:SetBackdropColor(unpack(colors.bgHover))
            checkmark:SetVertexColor(unpack(colors.checkmark))
        elseif isChecked then
            cb:SetBackdropBorderColor(unpack(colors.borderChecked))
            cb:SetBackdropColor(unpack(colors.bgChecked))
            checkmark:SetVertexColor(unpack(colors.checkmark))
        elseif isHovered then
            cb:SetBackdropBorderColor(unpack(colors.borderHover))
            cb:SetBackdropColor(unpack(colors.bgHover))
        else
            cb:SetBackdropBorderColor(unpack(colors.border))
            cb:SetBackdropColor(unpack(colors.bg))
        end
    end

    cb:SetScript("OnEnter", function()
        isHovered = true
        UpdateVisual()
    end)

    cb:SetScript("OnLeave", function()
        isHovered = false
        UpdateVisual()
    end)

    cb:SetScript("OnClick", function()
        if isEnabled then
            isChecked = not isChecked
            UpdateVisual()
            if onChange then
                onChange(isChecked)
            end
        end
    end)

    -- Public methods
    function cb:SetChecked(checked)
        isChecked = checked
        UpdateVisual()
    end

    function cb:GetChecked()
        return isChecked
    end

    function cb:SetHovered(hovered)
        isHovered = hovered
        UpdateVisual()
    end

    function cb:SetEnabled(enabled)
        isEnabled = enabled
        UpdateVisual()
    end

    function cb:IsEnabled()
        return isEnabled
    end

    UpdateVisual()
    return cb
end

---@class CheckboxConfig : ComponentConfig
---@field label string Display label
---@field checked? boolean Initial checked state (deprecated: prefer get)
---@field get? fun(): boolean Getter for initial value and refresh (preferred over checked)
---@field enabled? fun(): boolean Getter for enabled state, evaluated on Refresh()
---@field tooltip? string|{title: string, desc: string} Tooltip shown on hover (string or {title, desc} table)
---@field onChange fun(checked: boolean) Callback when checked state changes
---@field icons? number[] Optional texture ID(s) to show between checkbox and label
---@field infoTooltip? string Optional info icon tooltip (format: "title|description")
---@field warningTooltip? string Optional warning icon tooltip (format: "title|description")
---@field onRightClick? fun() Optional right-click callback (wired on all interactive children)

---Create a modern flat-style checkbox with label and optional icons/tooltip
---@param parent table Parent frame
---@param config CheckboxConfig Configuration table
---@return table holder Frame containing checkbox with .checkbox, .SetChecked(v), .GetChecked()
function Components.Checkbox(parent, config)
    local colors = CheckboxColors
    local initialChecked = config.get and config.get() or config.checked or false

    -- Container frame
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(200, 20)

    -- Create checkbox using shared core
    local cb = CreateCheckboxCore(holder, initialChecked, config.onChange)
    cb:SetPoint("LEFT", 0, 0)
    holder.checkbox = cb

    -- Build icon chain (optional)
    local lastAnchor = cb
    local ICON_SIZE = 16 -- Match checkbox size
    local ICON_SPACING = 4 -- Consistent spacing
    if config.icons then
        local CreateBuffIcon = BR.CreateBuffIcon
        for _, textureID in ipairs(config.icons) do
            local icon = CreateBuffIcon(holder, ICON_SIZE, textureID)
            icon:SetPoint("LEFT", lastAnchor, "RIGHT", ICON_SPACING, 0)
            lastAnchor = icon
        end
    end

    -- Label
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", lastAnchor, "RIGHT", ICON_SPACING + 1, 0) -- Slightly more space before text
    label:SetText(config.label)
    holder.label = label
    cb.label = label

    -- Hover tooltip (on all interactive children, chained with hover visuals)
    if config.tooltip then
        local title, desc
        if type(config.tooltip) == "table" then
            title = config.tooltip.title
            desc = config.tooltip.desc
        else
            title = config.tooltip --[[@as string]]
        end
        holder:EnableMouse(true)
        local function showTip()
            ShowTooltip(holder, title, desc, "ANCHOR_TOP")
        end
        local function hideTip()
            HideTooltip()
        end
        holder:HookScript("OnEnter", showTip)
        holder:HookScript("OnLeave", hideTip)
        cb:HookScript("OnEnter", showTip)
        cb:HookScript("OnLeave", hideTip)
    end

    -- Info / warning tooltip icon (optional, shown after label)
    local tooltipText = config.infoTooltip or config.warningTooltip
    if tooltipText then
        local infoIcon = holder:CreateTexture(nil, "ARTWORK")
        infoIcon:SetSize(14, 14)
        infoIcon:SetPoint("LEFT", label, "RIGHT", 4, 0)
        if config.warningTooltip then
            infoIcon:SetAtlas("services-icon-warning")
        else
            infoIcon:SetAtlas("QuestNormal")
        end

        local infoBtn = CreateFrame("Button", nil, holder)
        infoBtn:SetSize(14, 14)
        infoBtn:SetPoint("CENTER", infoIcon, "CENTER", 0, 0)

        local infoTitle, infoDesc = tooltipText:match("^([^|]+)|(.+)$")
        if not infoTitle then
            infoTitle = tooltipText
        end
        SetupTooltip(infoBtn, infoTitle, infoDesc)
    end

    -- Right-click callback (wired on all interactive children)
    if config.onRightClick then
        local function handleRightClick(_, button)
            if button == "RightButton" then
                config.onRightClick()
            end
        end
        holder:EnableMouse(true)
        holder:SetScript("OnMouseUp", handleRightClick)
        cb:HookScript("OnMouseUp", handleRightClick)
    end

    -- Public methods
    function holder:SetChecked(checked)
        cb:SetChecked(checked)
    end

    function holder:GetChecked()
        return cb:GetChecked()
    end

    function holder:SetEnabled(enabled)
        cb:SetEnabled(enabled)
        if enabled then
            label:SetTextColor(unpack(colors.text))
        else
            label:SetTextColor(unpack(colors.textDisabled))
        end
    end

    -- Refresh method for OnShow pattern
    function holder:Refresh()
        if config.get then
            cb:SetChecked(config.get())
        end
        if config.enabled then
            holder:SetEnabled(config.enabled())
        end
    end

    -- Auto-register if refreshable
    if config.get or config.enabled then
        table.insert(RefreshableComponents, holder)
    end

    return holder
end

-- Toggle (pill/switch) component colors
local ToggleColors = {
    trackOff = { 0.12, 0.12, 0.12, 1 },
    trackOn = { 0.15, 0.13, 0.08, 1 },
    borderOff = { 0.3, 0.3, 0.3, 1 },
    borderOn = { 0.6, 0.5, 0.2, 1 },
    borderHover = { 0.45, 0.45, 0.45, 1 },
    borderDisabled = { 0.2, 0.2, 0.2, 1 },
    thumbOff = { 0.4, 0.4, 0.4, 1 },
    thumbOn = { 0.9, 0.75, 0.2, 1 },
    thumbHover = { 1, 0.82, 0, 1 },
    thumbDisabled = { 0.25, 0.25, 0.25, 1 },
    text = { 1, 1, 1, 1 },
    textDisabled = { 0.5, 0.5, 0.5, 1 },
}

---@param parent Frame
---@param config ToggleConfig
---@return Frame
function Components.Toggle(parent, config)
    local colors = ToggleColors
    local checked = config.checked or false

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(200, 20)

    -- Track (the pill background)
    local track = CreateFrame("Button", nil, holder, "BackdropTemplate")
    track:SetSize(32, 16)
    track:SetPoint("LEFT", 0, 0)
    track:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8x8",
        edgeFile = "Interface\\BUTTONS\\WHITE8x8",
        edgeSize = 1,
    })

    -- Thumb (the sliding circle)
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(12, 12)
    thumb:SetColorTexture(1, 1, 1, 1)

    -- Label
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", track, "RIGHT", 6, 0)
    label:SetText(config.label)
    holder.label = label

    local enabled = true

    local function UpdateVisual()
        if not enabled then
            track:SetBackdropColor(unpack(colors.trackOff))
            track:SetBackdropBorderColor(unpack(colors.borderDisabled))
            thumb:SetVertexColor(unpack(colors.thumbDisabled))
            label:SetTextColor(unpack(colors.textDisabled))
        elseif checked then
            track:SetBackdropColor(unpack(colors.trackOn))
            track:SetBackdropBorderColor(unpack(colors.borderOn))
            thumb:SetVertexColor(unpack(colors.thumbOn))
            label:SetTextColor(unpack(colors.text))
        else
            track:SetBackdropColor(unpack(colors.trackOff))
            track:SetBackdropBorderColor(unpack(colors.borderOff))
            thumb:SetVertexColor(unpack(colors.thumbOff))
            label:SetTextColor(unpack(colors.text))
        end

        thumb:ClearAllPoints()
        if checked then
            thumb:SetPoint("LEFT", track, "LEFT", 18, 0) -- on position
        else
            thumb:SetPoint("LEFT", track, "LEFT", 2, 0) -- off position
        end
    end

    track:SetScript("OnClick", function()
        if not enabled then
            return
        end
        checked = not checked
        UpdateVisual()
        if config.onChange then
            config.onChange(checked)
        end
    end)

    track:SetScript("OnEnter", function()
        if not enabled then
            return
        end
        if checked then
            thumb:SetVertexColor(unpack(colors.thumbHover))
        else
            track:SetBackdropBorderColor(unpack(colors.borderHover))
        end
    end)

    track:SetScript("OnLeave", function()
        if not enabled then
            return
        end
        UpdateVisual()
    end)

    -- Tooltip support (same pattern as Checkbox)
    if config.tooltip then
        local title, desc
        if type(config.tooltip) == "table" then
            title = config.tooltip.title
            desc = config.tooltip.desc
        else
            title = config.tooltip --[[@as string]]
        end
        holder:EnableMouse(true)
        local function showTip()
            ShowTooltip(holder, title, desc, "ANCHOR_TOP")
        end
        local function hideTip()
            HideTooltip()
        end
        holder:HookScript("OnEnter", showTip)
        holder:HookScript("OnLeave", hideTip)
        track:HookScript("OnEnter", showTip)
        track:HookScript("OnLeave", hideTip)
    end

    -- Public methods
    function holder:SetChecked(value)
        checked = value and true or false
        UpdateVisual()
    end

    function holder:GetChecked()
        return checked
    end

    function holder:SetEnabled(value)
        enabled = value and true or false
        track:EnableMouse(enabled)
        UpdateVisual()
    end

    function holder:Refresh()
        if config.get then
            checked = config.get() and true or false
        end
        if config.enabled then
            holder:SetEnabled(config.enabled())
        end
        UpdateVisual()
    end

    -- Auto-register if refreshable
    if config.get or config.enabled then
        table.insert(RefreshableComponents, holder)
    end

    UpdateVisual()

    return holder
end

-- Modern dropdown styling colors
local DropdownColors = {
    bg = { 0.15, 0.15, 0.15, 1 },
    bgHover = { 0.2, 0.2, 0.2, 1 },
    bgDisabled = { 0.1, 0.1, 0.1, 1 },
    border = { 0.3, 0.3, 0.3, 1 },
    borderHover = { 0.5, 0.5, 0.5, 1 },
    borderDisabled = { 0.2, 0.2, 0.2, 1 },
    arrow = { 0.7, 0.7, 0.7, 1 },
    arrowHover = { 1, 0.82, 0, 1 },
    arrowDisabled = { 0.4, 0.4, 0.4, 1 },
    text = { 1, 1, 1, 1 },
    textDisabled = { 0.5, 0.5, 0.5, 1 },
    -- Menu colors
    menuBg = { 0.12, 0.12, 0.12, 0.98 },
    menuBorder = { 0.3, 0.3, 0.3, 1 },
    itemBgHover = { 0.25, 0.22, 0.1, 1 },
    itemText = { 1, 1, 1, 1 },
    itemTextHover = { 1, 0.82, 0, 1 },
    checkmark = { 0.9, 0.75, 0.2, 1 },
}

---Create the core dropdown (button + menu) - reusable by Dropdown and DirectionButtons
---@param parent table Parent frame
---@param width number Dropdown width
---@param options table[] Array of {label, value} options
---@param initialValue any Initial selected value
---@param onChange fun(value: any, label: string) Callback when selection changes
---@param maxItems? number Max visible items before scrolling (nil = no limit)
---@param itemInit? fun(item: table, label: FontString, opt: table) Optional per-item setup callback
---@return table dropdown Core dropdown with .button, .menu, .SetValue(), .GetValue(), .SetEnabled()
local function CreateDropdownCore(parent, width, options, initialValue, onChange, maxItems, itemInit)
    local colors = DropdownColors
    local BUTTON_HEIGHT = 22
    local ITEM_HEIGHT = 22
    local MENU_PADDING_V = 4

    -- Find initial label
    local currentValue = initialValue
    local currentLabel = ""
    for _, opt in ipairs(options) do
        if opt.value == currentValue then
            currentLabel = opt.label
            break
        end
    end

    -- State
    local isEnabled = true
    local isOpen = false
    local isHovered = false

    -- ==================== BUTTON ====================
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, BUTTON_HEIGHT)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    local buttonText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    buttonText:SetPoint("LEFT", 8, 0)
    buttonText:SetPoint("RIGHT", -20, 0)
    buttonText:SetJustifyH("LEFT")
    buttonText:SetText(currentLabel)

    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetRotation(math.rad(-90)) -- points down

    -- ==================== MENU ====================
    -- Parent to UIParent for proper strata handling
    local useScroll = maxItems and #options > maxItems
    local visibleCount = useScroll and maxItems or #options
    local menuHeight = visibleCount * ITEM_HEIGHT + MENU_PADDING_V * 2
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetSize(width, menuHeight)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(unpack(colors.menuBg))
    menu:SetBackdropBorderColor(unpack(colors.menuBorder))
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:Hide()

    -- Scroll frame (only created when needed)
    local scrollFrame, scrollChild
    if useScroll then
        scrollFrame = CreateFrame("ScrollFrame", nil, menu)
        scrollFrame:SetPoint("TOPLEFT", 1, -MENU_PADDING_V)
        scrollFrame:SetPoint("BOTTOMRIGHT", -1, MENU_PADDING_V)

        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetSize(width - 2, #options * ITEM_HEIGHT)
        scrollFrame:SetScrollChild(scrollChild)

        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(_, delta)
            local current = scrollFrame:GetVerticalScroll()
            local maxScroll = #options * ITEM_HEIGHT - visibleCount * ITEM_HEIGHT
            local newScroll = math.max(0, math.min(maxScroll, current - delta * ITEM_HEIGHT * 3))
            scrollFrame:SetVerticalScroll(newScroll)
        end)
    end

    -- Position menu below button (updated when shown)
    local function PositionMenu()
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    end

    -- ==================== VISUAL STATE ====================
    local function UpdateButtonVisual()
        if not isEnabled then
            button:SetBackdropColor(unpack(colors.bgDisabled))
            button:SetBackdropBorderColor(unpack(colors.borderDisabled))
            buttonText:SetTextColor(unpack(colors.textDisabled))
            arrow:SetVertexColor(unpack(colors.arrowDisabled))
        elseif isHovered or isOpen then
            button:SetBackdropColor(unpack(colors.bgHover))
            button:SetBackdropBorderColor(unpack(colors.borderHover))
            buttonText:SetTextColor(unpack(colors.text))
            arrow:SetVertexColor(unpack(colors.arrowHover))
        else
            button:SetBackdropColor(unpack(colors.bg))
            button:SetBackdropBorderColor(unpack(colors.border))
            buttonText:SetTextColor(unpack(colors.text))
            arrow:SetVertexColor(unpack(colors.arrow))
        end
    end

    -- Track if mouse was down last frame (for click-outside detection)
    local wasMouseDown = false

    local function CloseMenu()
        isOpen = false
        menu:Hide()
        wasMouseDown = false
        UpdateButtonVisual()
    end

    local function OpenMenu()
        isOpen = true
        PositionMenu()
        menu:Show()
        if scrollFrame then
            scrollFrame:SetVerticalScroll(0)
        end
        wasMouseDown = IsMouseButtonDown("LeftButton") -- Prevent immediate close from the opening click
        UpdateButtonVisual()
    end

    -- OnUpdate to detect clicks outside menu (only runs while menu is visible)
    menu:SetScript("OnUpdate", function()
        local isMouseDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")

        -- Detect click (mouse just pressed)
        if isMouseDown and not wasMouseDown then
            -- Check if click is outside menu and button
            if not menu:IsMouseOver() and not button:IsMouseOver() then
                CloseMenu()
            end
        end

        wasMouseDown = isMouseDown
    end)

    -- ==================== MENU ITEMS ====================
    local itemParent = scrollChild or menu
    local items = {}
    for i, opt in ipairs(options) do
        local item = CreateFrame("Button", nil, itemParent)
        item:SetSize(width - 2, ITEM_HEIGHT)
        item:SetPoint("TOPLEFT", 0, -(useScroll and 0 or MENU_PADDING_V) - (i - 1) * ITEM_HEIGHT)

        local itemBg = item:CreateTexture(nil, "BACKGROUND")
        itemBg:SetAllPoints()
        itemBg:SetColorTexture(0, 0, 0, 0)

        local check = item:CreateTexture(nil, "ARTWORK")
        check:SetSize(14, 14)
        check:SetPoint("LEFT", 6, 0)
        check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        check:SetVertexColor(unpack(colors.checkmark))
        check:SetShown(opt.value == currentValue)

        local label = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 24, 0)
        label:SetPoint("RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        label:SetText(opt.label)
        label:SetTextColor(unpack(colors.itemText))

        -- Item hover visual
        local function UpdateItemVisual(hovered)
            if hovered then
                itemBg:SetColorTexture(unpack(colors.itemBgHover))
                label:SetTextColor(unpack(colors.itemTextHover))
            else
                itemBg:SetColorTexture(0, 0, 0, 0)
                label:SetTextColor(unpack(colors.itemText))
            end
        end

        item:SetScript("OnEnter", function()
            UpdateItemVisual(true)
            if opt.desc then
                ShowTooltip(item, opt.label, opt.desc, "ANCHOR_RIGHT")
            end
        end)
        item:SetScript("OnLeave", function()
            UpdateItemVisual(false)
            if opt.desc then
                HideTooltip()
            end
        end)
        item:SetScript("OnClick", function()
            currentValue = opt.value
            currentLabel = opt.label
            buttonText:SetText(currentLabel)
            -- Update checkmarks
            for _, it in ipairs(items) do
                it.check:SetShown(it.value == currentValue)
            end
            CloseMenu()
            onChange(currentValue, currentLabel)
        end)

        -- Forward mouse wheel to scroll frame when scrollable
        if scrollFrame then
            item:EnableMouseWheel(true)
            item:SetScript("OnMouseWheel", function(_, delta)
                local current = scrollFrame:GetVerticalScroll()
                local maxScroll = #options * ITEM_HEIGHT - visibleCount * ITEM_HEIGHT
                local newScroll = math.max(0, math.min(maxScroll, current - delta * ITEM_HEIGHT * 3))
                scrollFrame:SetVerticalScroll(newScroll)
            end)
        end

        -- Custom per-item setup (e.g., font preview)
        if itemInit then
            itemInit(item, label, opt)
        end

        item.value = opt.value
        item.check = check
        items[i] = item
    end

    -- ==================== BUTTON EVENTS ====================
    button:SetScript("OnEnter", function()
        isHovered = true
        UpdateButtonVisual()
    end)
    button:SetScript("OnLeave", function()
        isHovered = false
        UpdateButtonVisual()
    end)
    button:SetScript("OnClick", function()
        if isEnabled then
            if isOpen then
                CloseMenu()
            else
                OpenMenu()
            end
        end
    end)

    -- Initialize visual
    UpdateButtonVisual()

    -- ==================== PUBLIC API ====================
    local dropdown = { button = button, menu = menu }

    function dropdown:SetValue(value)
        currentValue = value
        for _, opt in ipairs(options) do
            if opt.value == value then
                currentLabel = opt.label
                break
            end
        end
        buttonText:SetText(currentLabel)
        for _, item in ipairs(items) do
            item.check:SetShown(item.value == currentValue)
        end
    end

    function dropdown:GetValue()
        return currentValue
    end

    function dropdown:SetEnabled(enabled)
        isEnabled = enabled
        button:EnableMouse(enabled)
        if not enabled and isOpen then
            CloseMenu()
        end
        UpdateButtonVisual()
    end

    function dropdown:IsEnabled()
        return isEnabled
    end

    return dropdown
end

---Create direction buttons (LEFT, CENTER, RIGHT, UP, DOWN)
---@param parent table Parent frame
---@param config DirectionButtonsConfig Configuration table
---@return table holder Frame containing direction dropdown with .SetDirection(dir)
function Components.DirectionButtons(parent, config)
    local directions = { "LEFT", "CENTER", "RIGHT", "UP", "DOWN" }
    local dirLabels = { LEFT = "Left", CENTER = "Center", RIGHT = "Right", UP = "Up", DOWN = "Down" }
    local width = config.width or 90

    -- Build options array
    local options = {}
    for _, dir in ipairs(directions) do
        table.insert(options, { label = dirLabels[dir], value = dir })
    end

    -- Container frame
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(70 + width + 10, 26)

    -- Label
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(config.label or "Direction:")
    holder.label = label

    -- Initial value
    local initialValue = config.get and config.get() or config.selected

    -- Create dropdown core
    local dropdown = CreateDropdownCore(holder, width, options, initialValue, function(value)
        config.onChange(value)
    end)
    dropdown.button:SetPoint("LEFT", label, "RIGHT", 5, 0)
    holder.dropdown = dropdown

    -- Public method to update selection (backwards compatible)
    function holder:SetDirection(dir)
        dropdown:SetValue(dir)
    end

    -- SetEnabled method for toggling interactivity
    function holder:SetEnabled(enabled)
        dropdown:SetEnabled(enabled)
        local color = enabled and 1 or 0.5
        label:SetTextColor(color, color, color)
    end

    -- Refresh method for OnShow pattern
    function holder:Refresh()
        if config.get then
            dropdown:SetValue(config.get())
        end
        if config.enabled then
            holder:SetEnabled(config.enabled())
        end
    end

    -- Auto-register if refreshable
    if config.get or config.enabled then
        table.insert(RefreshableComponents, holder)
    end

    -- Backwards compatibility: empty buttons table (no longer used)
    holder.buttons = {}

    return holder
end

local CONTENT_TOGGLE_DEFS = {
    { key = "openWorld", label = "W", tooltip = "Open World" },
    { key = "scenario", label = "S", tooltip = "Scenarios (Delves, Torghast, etc.)" },
    { key = "dungeon", label = "D", tooltip = "Dungeons (including M+)" },
    { key = "raid", label = "R", tooltip = "Raids" },
}

local DUNGEON_DIFF_DEFS = {
    { key = "normal", label = "N", tooltip = "Normal Dungeons" },
    { key = "heroic", label = "H", tooltip = "Heroic Dungeons" },
    { key = "mythic", label = "M", tooltip = "Mythic Dungeons" },
    { key = "mythicPlus", label = "M+", tooltip = "Mythic+ Keystones" },
    { key = "timewalking", label = "TW", tooltip = "Timewalking Dungeons" },
    { key = "follower", label = "F", tooltip = "Follower Dungeons" },
}

local RAID_DIFF_DEFS = {
    { key = "lfr", label = "LFR", tooltip = "Looking for Raid" },
    { key = "normal", label = "N", tooltip = "Normal Raids" },
    { key = "heroic", label = "H", tooltip = "Heroic Raids" },
    { key = "mythic", label = "M", tooltip = "Mythic Raids" },
}

local SEGMENT_H = 16
local DIVIDER_W = 1
local DEFAULT_SEGMENT_W = 22

---Compute bar width for a given number of segments and segment width
---@param numSegments number
---@param segW number
---@return number
local function ComputeBarWidth(numSegments, segW)
    return numSegments * segW + (numSegments - 1) * DIVIDER_W + 2
end

local BAR_H = SEGMENT_H + 2

---Create a generic segmented toggle bar
---@param parent table Parent frame
---@param barConfig table { toggleDefs, segmentWidth, getState, setState, onChange }
---@return table container The bar container frame
---@return table toggleButtons Array of segment button frames
local function CreateSegmentedBar(parent, barConfig)
    local toggleDefs = barConfig.toggleDefs
    local segW = barConfig.segmentWidth or DEFAULT_SEGMENT_W
    local barW = ComputeBarWidth(#toggleDefs, segW)

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(barW, BAR_H)
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    container:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    container:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local barDisabled = false
    local toggleButtons = {}
    for i, toggle in ipairs(toggleDefs) do
        local btn = CreateFrame("Button", nil, container)
        btn:SetSize(segW, SEGMENT_H)
        local xOff = 1 + (i - 1) * (segW + DIVIDER_W)
        btn:SetPoint("TOPLEFT", container, "TOPLEFT", xOff, -1)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()

        local btnLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btnLabel:SetPoint("CENTER", 0, -1)
        btnLabel:SetText(toggle.label)

        local function UpdateToggleVisual()
            if barDisabled then
                bg:SetColorTexture(0, 0, 0, 0)
                btnLabel:SetTextColor(0.25, 0.25, 0.25, 1)
                return
            end
            -- Tri-state visual: getVisualState returns "on"/"partial"/"off"
            local visualState
            if barConfig.getVisualState then
                visualState = barConfig.getVisualState(toggle.key)
            else
                visualState = barConfig.getState(toggle.key) and "on" or "off"
            end
            if visualState == "on" then
                bg:SetColorTexture(0.18, 0.15, 0.08, 1)
                btnLabel:SetTextColor(0.9, 0.75, 0.2, 1)
            elseif visualState == "partial" then
                bg:SetColorTexture(0.12, 0.08, 0.02, 1)
                btnLabel:SetTextColor(0.7, 0.5, 0.1, 1)
            else
                bg:SetColorTexture(0, 0, 0, 0)
                btnLabel:SetTextColor(0.4, 0.4, 0.4, 1)
            end
        end
        btn.UpdateVisual = UpdateToggleVisual
        UpdateToggleVisual()

        btn:SetScript("OnClick", function()
            if barDisabled then
                return
            end
            barConfig.setState(toggle.key)
            UpdateToggleVisual()
            if barConfig.onChange then
                barConfig.onChange()
            end
        end)

        SetupTooltip(btn, toggle.tooltip, "Click to toggle visibility in " .. toggle.tooltip:lower(), "ANCHOR_TOP")

        if i < #toggleDefs then
            local divider = container:CreateTexture(nil, "ARTWORK")
            divider:SetSize(DIVIDER_W, SEGMENT_H)
            divider:SetPoint("LEFT", btn, "RIGHT", 0, 0)
            divider:SetColorTexture(0.3, 0.3, 0.3, 0.8)
        end

        toggleButtons[i] = btn
    end

    ---Set whether the entire bar is disabled (non-interactive, all gray)
    ---@param disabled boolean
    function container:SetBarDisabled(disabled)
        barDisabled = disabled
        for _, btn in ipairs(toggleButtons) do
            btn.UpdateVisual()
        end
    end

    return container, toggleButtons
end

---Build barConfig for the content-type (W/S/D/R) bar
---@param category CategoryName
---@param onChange fun()
---@return table barConfig
local function MakeContentBarConfig(category, onChange)
    return {
        toggleDefs = CONTENT_TOGGLE_DEFS,
        segmentWidth = DEFAULT_SEGMENT_W,
        getState = function(key)
            local db = BuffRemindersDB
            local visibility = db.categoryVisibility and db.categoryVisibility[category]
            return not visibility or visibility[key] ~= false
        end,
        setState = function(key)
            local db = BuffRemindersDB
            if not db.categoryVisibility then
                db.categoryVisibility = {}
            end
            if not db.categoryVisibility[category] then
                db.categoryVisibility[category] = { openWorld = true, scenario = true, dungeon = true, raid = true }
            end
            db.categoryVisibility[category][key] = not db.categoryVisibility[category][key]
        end,
        onChange = onChange,
    }
end

---Create category header with content visibility toggles [W][S][D][R]
---@param parent table Parent frame
---@param config CategoryHeaderConfig Configuration table
---@param updateCallback fun() Function to call when visibility changes (UpdateDisplay or RefreshTestDisplay)
---@return table header FontString for the header
function Components.CategoryHeader(parent, config, updateCallback)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetText("|cffffcc00" .. config.text .. "|r")

    local bar = CreateSegmentedBar(parent, MakeContentBarConfig(config.category, updateCallback))
    bar:SetPoint("LEFT", header, "RIGHT", 8, 0)

    return header
end

---@class VisibilityTogglesConfig : ComponentConfig
---@field category CategoryName Category for visibility toggles
---@field onChange fun() Callback when visibility changes

---Create standalone content + difficulty visibility toggles (D/R expand to the right)
---@param parent table Parent frame
---@param config VisibilityTogglesConfig Configuration table
---@return table holder Frame containing segmented toggle bar with D/R difficulty expansion
function Components.VisibilityToggles(parent, config)
    local category = config.category
    local DIFF_SEGMENT_W = 26

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(200, BAR_H)

    -- All toggle buttons across all bars (content + difficulty bars) for Refresh
    local allToggleButtons = {}

    -- Helper: get/set difficulty sub-table
    local function getDiffTable(dbKey)
        local db = BuffRemindersDB
        local vis = db.categoryVisibility and db.categoryVisibility[category]
        return vis and vis[dbKey]
    end

    local function ensureDiffTable(dbKey)
        local db = BuffRemindersDB
        if not db.categoryVisibility then
            db.categoryVisibility = {}
        end
        if not db.categoryVisibility[category] then
            db.categoryVisibility[category] = { openWorld = true, scenario = true, dungeon = true, raid = true }
        end
        if not db.categoryVisibility[category][dbKey] then
            db.categoryVisibility[category][dbKey] = {}
        end
        return db.categoryVisibility[category][dbKey]
    end

    local function isContentEnabled(contentKey)
        local db = BuffRemindersDB
        local vis = db.categoryVisibility and db.categoryVisibility[category]
        return not vis or vis[contentKey] ~= false
    end

    -- Compute tri-state visual for D/R buttons: "on" (all diffs enabled), "partial" (some), "off" (content disabled)
    local function getDiffVisualState(contentKey, diffDbKey, diffDefs)
        if not isContentEnabled(contentKey) then
            return "off"
        end
        local diffTable = getDiffTable(diffDbKey)
        if not diffTable then
            return "on" -- nil = all enabled
        end
        local anyOn, anyOff = false, false
        for _, def in ipairs(diffDefs) do
            if diffTable[def.key] == false then
                anyOff = true
            else
                anyOn = true
            end
        end
        if anyOn and anyOff then
            return "partial"
        elseif anyOn then
            return "on"
        else
            return "off"
        end
    end

    -- Forward-declare refreshAll so diff bar onChange can call it
    local refreshAll

    -- Content label (LEFT anchor centers vertically in holder)
    local contentLabel = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    contentLabel:SetPoint("LEFT", 0, 0)
    contentLabel:SetText("Show in:")

    -- Content bar with custom getVisualState for D/R
    local contentBarConfig = MakeContentBarConfig(category, config.onChange)
    contentBarConfig.getVisualState = function(key)
        if key == "dungeon" then
            return getDiffVisualState("dungeon", "dungeonDifficulty", DUNGEON_DIFF_DEFS)
        elseif key == "raid" then
            return getDiffVisualState("raid", "raidDifficulty", RAID_DIFF_DEFS)
        else
            return isContentEnabled(key) and "on" or "off"
        end
    end
    local contentBar, contentButtons = CreateSegmentedBar(holder, contentBarConfig)
    contentBar:SetPoint("LEFT", contentLabel, "RIGHT", 6, 0)

    for _, btn in ipairs(contentButtons) do
        allToggleButtons[#allToggleButtons + 1] = btn
    end

    -- Difficulty bar state
    local diffBars = {} -- keyed by contentKey ("dungeon", "raid")
    local activeDiffKey = nil -- which difficulty bar is currently shown

    local diffMappings = {
        { contentKey = "dungeon", diffDbKey = "dungeonDifficulty", diffDefs = DUNGEON_DIFF_DEFS, btnIndex = 3 },
        { contentKey = "raid", diffDbKey = "raidDifficulty", diffDefs = RAID_DIFF_DEFS, btnIndex = 4 },
    }

    -- Arrow indicator between content bar and difficulty bar (hidden when no diff bar is open)
    local expandArrow = CreateFrame("Frame", nil, holder)
    expandArrow:SetSize(10, BAR_H)
    expandArrow:SetPoint("LEFT", contentBar, "RIGHT", 2, 0)
    local arrowTex = expandArrow:CreateTexture(nil, "OVERLAY")
    arrowTex:SetSize(8, 8)
    arrowTex:SetPoint("CENTER", 0, 0)
    arrowTex:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrowTex:SetVertexColor(0.5, 0.5, 0.5, 1)
    expandArrow:Hide()

    -- Pre-create difficulty bars
    for _, mapping in ipairs(diffMappings) do
        -- Difficulty bar: parented to holder so it's clipped by scroll frame
        local bar, buttons = CreateSegmentedBar(holder, {
            toggleDefs = mapping.diffDefs,
            segmentWidth = DIFF_SEGMENT_W,
            getState = function(key)
                local diffTable = getDiffTable(mapping.diffDbKey)
                return not diffTable or diffTable[key] ~= false
            end,
            setState = function(key)
                local t = ensureDiffTable(mapping.diffDbKey)
                local wasEnabled = t[key] ~= false
                t[key] = not wasEnabled

                -- Auto-manage content type toggle
                local db = BuffRemindersDB
                local vis = db.categoryVisibility and db.categoryVisibility[category]
                if wasEnabled then
                    -- Turned off: check if ALL are now off -> disable content type
                    local anyStillOn = false
                    for _, def in ipairs(mapping.diffDefs) do
                        if t[def.key] ~= false then
                            anyStillOn = true
                            break
                        end
                    end
                    if not anyStillOn and vis then
                        vis[mapping.contentKey] = false
                    end
                else
                    -- Turned on from off: if content type was disabled, re-enable it
                    -- and set only the clicked difficulty to true (others stay off)
                    if vis and vis[mapping.contentKey] == false then
                        vis[mapping.contentKey] = true
                        for _, def in ipairs(mapping.diffDefs) do
                            t[def.key] = def.key == key
                        end
                    end
                end
            end,
            onChange = function()
                -- Auto-manage may change multiple states; refresh everything
                refreshAll()
                config.onChange()
            end,
        })
        bar:SetPoint("LEFT", expandArrow, "RIGHT", 2, 0)
        bar:Hide()

        for _, btn in ipairs(buttons) do
            allToggleButtons[#allToggleButtons + 1] = btn
        end

        diffBars[mapping.contentKey] = bar
    end

    local function closeDiffBar()
        if activeDiffKey then
            diffBars[activeDiffKey]:Hide()
            activeDiffKey = nil
            expandArrow:Hide()
        end
    end

    local function showDiffBar(contentKey)
        if activeDiffKey == contentKey then
            -- Toggle off: clicking same button again hides it
            closeDiffBar()
            return
        end
        -- Hide previous bar if any
        if activeDiffKey then
            diffBars[activeDiffKey]:Hide()
        end
        diffBars[contentKey]:Show()
        expandArrow:Show()
        activeDiffKey = contentKey
    end

    -- Override D and R button click to toggle difficulty bar to the right
    for _, mapping in ipairs(diffMappings) do
        local btn = contentButtons[mapping.btnIndex]
        btn:SetScript("OnClick", function()
            showDiffBar(mapping.contentKey)
        end)
        local toggle = CONTENT_TOGGLE_DEFS[mapping.btnIndex]
        SetupTooltip(
            btn,
            toggle.tooltip,
            "Click to filter by " .. toggle.tooltip:lower() .. " difficulty",
            "ANCHOR_TOP"
        )
    end

    -- refreshAll: update all button visuals (used by onChange and Refresh)
    refreshAll = function()
        for _, btn in ipairs(allToggleButtons) do
            btn.UpdateVisual()
        end
    end

    holder.toggleButtons = contentButtons

    -- Close difficulty bar when holder is hidden (e.g. options panel closes)
    holder:SetScript("OnHide", closeDiffBar)

    -- Refresh method: update all buttons (content bar + both difficulty bars)
    function holder:Refresh()
        refreshAll()
    end

    table.insert(RefreshableComponents, holder)

    return holder
end

---@class DropdownOption
---@field label string Display text
---@field value any Value to pass to callback
---@field desc? string Optional description shown as tooltip on hover

---@class DropdownConfig : ComponentConfig
---@field label string Label text
---@field options DropdownOption[] Available options
---@field selected? any Initial selected value (deprecated: prefer get)
---@field get? fun(): any Getter for initial value and refresh (preferred over selected)
---@field enabled? fun(): boolean Getter for enabled state, evaluated on Refresh()
---@field tooltip? string|{title: string, desc?: string} Tooltip on hover
---@field width? number Dropdown width (default 100)
---@field maxItems? number Max visible items before scrolling (nil = no limit)
---@field itemInit? fun(item: table, label: FontString, opt: table) Optional per-item setup callback
---@field onChange fun(value: any) Callback when selection changes

---Create a dropdown with label
---@param parent table Parent frame
---@param config DropdownConfig Configuration table
---@param _ string? Unused (was uniqueName for UIDropDownMenu, kept for API compatibility)
---@return table holder Frame containing dropdown with .SetValue(v), .GetValue(), .SetEnabled(bool)
function Components.Dropdown(parent, config, _)
    local width = config.width or 100

    -- Container frame
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(70 + width + 10, 26)

    -- Label
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(config.label)
    holder.label = label

    -- Initial value
    local initialValue = config.get and config.get() or config.selected

    -- Create dropdown core
    local dropdown = CreateDropdownCore(holder, width, config.options, initialValue, function(value)
        config.onChange(value)
    end, config.maxItems, config.itemInit)
    dropdown.button:SetPoint("LEFT", label, "RIGHT", 5, 0)
    holder.dropdown = dropdown

    -- Public methods (delegate to core)
    function holder:SetValue(value)
        dropdown:SetValue(value)
    end

    function holder:GetValue()
        return dropdown:GetValue()
    end

    function holder:SetEnabled(enabled)
        dropdown:SetEnabled(enabled)
        local color = enabled and 1 or 0.5
        label:SetTextColor(color, color, color)
    end

    -- Hover tooltip (attached to label only, not the entire holder)
    if config.tooltip then
        local tipTitle, tipDesc
        if type(config.tooltip) == "table" then
            tipTitle = config.tooltip.title
            tipDesc = config.tooltip.desc
        else
            tipTitle = config.tooltip --[[@as string]]
        end
        label:EnableMouse(true)
        local function showTip()
            ShowTooltip(label, tipTitle, tipDesc, "ANCHOR_TOP")
        end
        label:SetScript("OnEnter", showTip)
        label:SetScript("OnLeave", HideTooltip)
    end

    -- Refresh method for OnShow pattern
    function holder:Refresh()
        if config.get then
            dropdown:SetValue(config.get())
        end
        if config.enabled then
            holder:SetEnabled(config.enabled())
        end
    end

    -- Auto-register if refreshable
    if config.get or config.enabled then
        table.insert(RefreshableComponents, holder)
    end

    return holder
end

---@class TabConfig : ComponentConfig
---@field name string Internal tab name
---@field label string Display label
---@field width? number Tab width (default 90)
---@field height? number Tab height (default 22)

---Create a flat-style tab button
---@param parent table Parent frame
---@param config TabConfig Configuration table
---@return table tab Tab button with .SetActive(bool), .isActive
function Components.Tab(parent, config)
    local width = config.width or 90
    local height = config.height or 22

    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(width, height)
    tab.tabName = config.name

    -- Background (highlighted when active)
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 0)
    bg:SetColorTexture(0.2, 0.2, 0.2, 0)
    tab.bg = bg

    -- Bottom line (shows when active)
    local bottomLine = tab:CreateTexture(nil, "BORDER")
    bottomLine:SetHeight(2)
    bottomLine:SetPoint("BOTTOMLEFT", 1, 0)
    bottomLine:SetPoint("BOTTOMRIGHT", -1, 0)
    bottomLine:SetColorTexture(0.6, 0.6, 0.6, 0)
    tab.bottomLine = bottomLine

    -- Text
    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", 0, 0)
    text:SetText(config.label)
    tab.text = text

    -- Hover effect
    tab:SetScript("OnEnter", function(self)
        if not self.isActive then
            self.bg:SetColorTexture(0.25, 0.25, 0.25, 0.5)
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if not self.isActive then
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 0)
        end
    end)

    -- Public method to set active state
    function tab:SetActive(active)
        self.isActive = active
        if active then
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
            self.bottomLine:SetColorTexture(0.8, 0.6, 0, 1)
            self.text:SetFontObject("GameFontHighlightSmall")
        else
            self.bg:SetColorTexture(0.2, 0.2, 0.2, 0)
            self.bottomLine:SetColorTexture(0.6, 0.6, 0.6, 0)
            self.text:SetFontObject("GameFontNormalSmall")
        end
    end

    return tab
end

---@class TextInputConfig : ComponentConfig
---@field label string Display label
---@field value? string Initial value (deprecated: prefer get)
---@field get? fun(): string Getter for initial value and refresh (preferred over value)
---@field enabled? fun(): boolean Predicate for enabled state (refreshed on RefreshAll)
---@field width? number Input width (default 150)
---@field labelWidth? number Label width (default 80)
---@field numeric? boolean Numeric only input
---@field onChange? fun(text: string) Callback when text changes (on enter/focus lost)

---Create a labeled text input
---@param parent table Parent frame
---@param config TextInputConfig Configuration table
---@return table holder Frame with .editBox, .SetValue(v), .GetValue()
function Components.TextInput(parent, config)
    local width = config.width or 150
    local labelWidth = config.labelWidth or 80

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(labelWidth + width + 5, 20)

    -- Label
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(labelWidth)
    label:SetJustifyH("LEFT")
    label:SetText(config.label)
    holder.label = label

    -- Edit box
    local editBox = CreateFrame("EditBox", nil, holder)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetAutoFocus(false)
    local inputContainer = StyleEditBox(editBox)
    inputContainer:SetSize(width, 18)
    inputContainer:SetPoint("LEFT", label, "RIGHT", 5, 0)
    if config.numeric then
        editBox:SetNumeric(true)
    end
    local initialText = config.get and config.get() or config.value
    if initialText then
        editBox:SetText(initialText)
    end
    holder.editBox = editBox

    -- Track editbox for focus cleanup
    if panelEditBoxes then
        table.insert(panelEditBoxes, editBox)
    end

    -- Callbacks
    if config.onChange then
        editBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            config.onChange(self:GetText())
        end)
        editBox:SetScript("OnEditFocusLost", function(self)
            config.onChange(self:GetText())
        end)
    else
        editBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
    end

    -- Public methods
    function holder:SetValue(text)
        editBox:SetText(text or "")
    end

    function holder:GetValue()
        return editBox:GetText()
    end

    function holder:SetEnabled(enabled)
        editBox:SetEnabled(enabled)
        local color = enabled and 1 or 0.5
        label:SetTextColor(color, color, color)
        local borderAlpha = enabled and 1 or 0.4
        inputContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, borderAlpha)
    end

    -- Refresh method for OnShow pattern
    function holder:Refresh()
        if config.get then
            editBox:SetText(config.get() or "")
        end
        if config.enabled then
            holder:SetEnabled(config.enabled())
        end
    end

    -- Auto-register if refreshable
    if config.get or config.enabled then
        table.insert(RefreshableComponents, holder)
    end

    return holder
end

-- ============================================================================
-- NUMERIC STEPPER
-- ============================================================================

---Create a compact numeric stepper with [-] value [+] buttons
---@param parent table Parent frame
---@param config table Configuration: label, min, max, step?, labelWidth?, get?, enabled?, onChange?
---@return table holder Frame with .SetValue(n), .GetValue(), .SetEnabled(bool), .Refresh()
function Components.NumericStepper(parent, config)
    local labelWidth = config.labelWidth or 70
    local step = config.step or 1
    local BTN_SIZE = 16
    local VALUE_WIDTH = 26

    -- Container frame
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(labelWidth + BTN_SIZE * 2 + VALUE_WIDTH + 16, 20)

    -- Label
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(labelWidth)
    label:SetJustifyH("LEFT")
    label:SetText(config.label)
    holder.label = label

    -- State
    local currentValue = config.min or 0
    if config.get then
        currentValue = config.get()
    end
    local isEnabled = true

    -- Clickable value display button
    local valueBtn = CreateFrame("Button", nil, holder)
    valueBtn:SetSize(VALUE_WIDTH, BTN_SIZE)

    local valueText = valueBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetAllPoints()
    valueText:SetJustifyH("CENTER")

    -- Forward declarations (buttons needed by UpdateButtonStates, defined below)
    local UpdateButtonStates

    local function UpdateValueText()
        valueText:SetText(tostring(currentValue))
        if UpdateButtonStates then
            UpdateButtonStates()
        end
    end

    local function ClampAndSet(val)
        val = math.max(config.min or 0, math.min(config.max or 100, val))
        val = math.floor(val / step + 0.5) * step
        if val ~= currentValue then
            currentValue = val
            UpdateValueText()
            if config.onChange then
                config.onChange(currentValue)
            end
        else
            UpdateButtonStates()
        end
    end

    -- Minus button
    local minusBtn = CreateFrame("Button", nil, holder, "BackdropTemplate")
    minusBtn:SetSize(BTN_SIZE, BTN_SIZE)
    minusBtn:SetPoint("LEFT", label, "RIGHT", 4, 0)
    minusBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    minusBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    minusBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local minusLabel = minusBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    minusLabel:SetPoint("CENTER", 0, 0)
    minusLabel:SetText("-")

    -- Value positioned between buttons
    valueBtn:SetPoint("LEFT", minusBtn, "RIGHT", 2, 0)

    -- Plus button
    local plusBtn = CreateFrame("Button", nil, holder, "BackdropTemplate")
    plusBtn:SetSize(BTN_SIZE, BTN_SIZE)
    plusBtn:SetPoint("LEFT", valueBtn, "RIGHT", 2, 0)
    plusBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    plusBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    plusBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local plusLabel = plusBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    plusLabel:SetPoint("CENTER", 0, 0)
    plusLabel:SetText("+")

    -- Update button appearance based on whether value is at min/max
    UpdateButtonStates = function()
        if not isEnabled then
            return
        end
        local atMin = currentValue <= (config.min or 0)
        local atMax = currentValue >= (config.max or 100)
        if atMin then
            minusBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            minusBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
            minusLabel:SetTextColor(0.35, 0.35, 0.35)
        else
            minusBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
            minusBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            minusLabel:SetTextColor(1, 1, 1)
        end
        if atMax then
            plusBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            plusBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
            plusLabel:SetTextColor(0.35, 0.35, 0.35)
        else
            plusBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
            plusBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            plusLabel:SetTextColor(1, 1, 1)
        end
    end

    -- Edit box (hidden by default, shown on value click)
    local editBox = CreateFrame("EditBox", nil, holder)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    local editContainer = StyleEditBox(editBox)
    editContainer:SetSize(VALUE_WIDTH + 4, BTN_SIZE)
    editContainer:SetPoint("LEFT", minusBtn, "RIGHT", 0, 0)
    editContainer:Hide()

    editBox:SetScript("OnEnterPressed", function(self)
        local num = tonumber(self:GetText())
        if num then
            ClampAndSet(num)
        end
        editContainer:Hide()
        valueBtn:Show()
    end)

    editBox:SetScript("OnEscapePressed", function()
        editContainer:Hide()
        valueBtn:Show()
    end)

    editBox:SetScript("OnEditFocusLost", function()
        editContainer:Hide()
        valueBtn:Show()
    end)

    -- Track editbox for focus cleanup on panel hide
    if panelEditBoxes then
        table.insert(panelEditBoxes, editBox)
    end

    valueBtn:SetScript("OnClick", function()
        if not isEnabled then
            return
        end
        valueBtn:Hide()
        editBox:SetText(tostring(math.floor(currentValue)))
        editContainer:Show()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    SetupTooltip(valueBtn, "Adjust value", "Click to type or use mouse wheel", "ANCHOR_TOP")

    -- Hover effects (skip if button is at its limit)
    local function IsBtnAtLimit(btn)
        if btn == minusBtn then
            return currentValue <= (config.min or 0)
        end
        return currentValue >= (config.max or 100)
    end

    for _, btn in ipairs({ minusBtn, plusBtn }) do
        btn:SetScript("OnEnter", function(self)
            if isEnabled and not IsBtnAtLimit(self) then
                self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
                self:SetBackdropColor(0.25, 0.25, 0.25, 1)
            end
        end)
        btn:SetScript("OnLeave", function()
            UpdateButtonStates()
        end)
    end

    minusBtn:SetScript("OnClick", function()
        if isEnabled then
            ClampAndSet(currentValue - step)
        end
    end)
    plusBtn:SetScript("OnClick", function()
        if isEnabled then
            ClampAndSet(currentValue + step)
        end
    end)

    -- Mouse wheel on entire holder
    holder:EnableMouseWheel(true)
    holder:SetScript("OnMouseWheel", function(_, delta)
        if isEnabled then
            ClampAndSet(currentValue + delta * step)
        end
    end)

    UpdateValueText()

    -- Public methods
    function holder:SetValue(val)
        currentValue = math.max(config.min or 0, math.min(config.max or 100, val))
        UpdateValueText()
    end

    function holder:GetValue()
        return currentValue
    end

    function holder:SetEnabled(enabled)
        isEnabled = enabled
        local color = enabled and 1 or 0.5
        label:SetTextColor(color, color, color)
        valueText:SetTextColor(color, color, color)
        if enabled then
            UpdateButtonStates()
        else
            -- Close edit box if open when disabling
            editContainer:Hide()
            valueBtn:Show()
            minusBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            minusBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
            plusBtn:SetBackdropColor(0.15, 0.15, 0.15, 1)
            plusBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
            minusLabel:SetTextColor(0.5, 0.5, 0.5)
            plusLabel:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    -- Refresh method for OnShow pattern
    function holder:Refresh()
        if config.get then
            currentValue = config.get()
            UpdateValueText()
        end
        if config.enabled then
            holder:SetEnabled(config.enabled())
        end
    end

    -- Auto-register if refreshable
    if config.get or config.enabled then
        table.insert(RefreshableComponents, holder)
    end

    return holder
end

-- ============================================================================
-- COLOR SWATCH
-- ============================================================================

---@class ColorSwatchConfig : ComponentConfig
---@field label string Display label
---@field get? fun(): number, number, number, number? Getter returning r, g, b [, a]
---@field enabled? fun(): boolean Getter for enabled state
---@field onChange fun(r: number, g: number, b: number, a?: number) Callback when color changes
---@field hasOpacity? boolean Show opacity/alpha slider (default false)
---@field labelWidth? number Width of label (default 70)

---Create a small color swatch that opens WoW's ColorPickerFrame on click
---@param parent table Parent frame
---@param config ColorSwatchConfig Configuration table
---@return table holder Frame containing color swatch with .SetColor(r,g,b,a?), .GetColor(), .SetEnabled(bool)
function Components.ColorSwatch(parent, config)
    local labelWidth = config.labelWidth or (config.label and 70 or 0)
    local SWATCH_SIZE = 16

    -- Container frame
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(labelWidth + SWATCH_SIZE + 50, 20)

    -- Label
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(labelWidth)
    label:SetJustifyH("LEFT")
    if config.label then
        label:SetText(config.label)
    end
    holder.label = label

    -- Swatch button
    local swatchBtn = CreateFrame("Button", nil, holder, "BackdropTemplate")
    swatchBtn:SetSize(SWATCH_SIZE, SWATCH_SIZE)
    swatchBtn:SetPoint("LEFT", label, "RIGHT", 5, 0)
    swatchBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    swatchBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- State
    local currentR, currentG, currentB, currentA = 1, 1, 1, 1
    if config.get then
        local r, g, b, a = config.get()
        currentR, currentG, currentB = r, g, b
        currentA = a or 1
    end
    local isEnabled = true

    -- Alpha value text (shown when hasOpacity is true)
    local alphaText
    if config.hasOpacity then
        alphaText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        alphaText:SetPoint("LEFT", swatchBtn, "RIGHT", 4, 0)
        alphaText:SetText(math.floor(currentA * 100) .. "%")
    end

    local function UpdateSwatchColor()
        swatchBtn:SetBackdropColor(currentR, currentG, currentB, 1)
        if alphaText then
            alphaText:SetText(math.floor(currentA * 100) .. "%")
        end
    end
    UpdateSwatchColor()

    -- Hover effect
    swatchBtn:SetScript("OnEnter", function()
        if isEnabled then
            swatchBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end
    end)
    swatchBtn:SetScript("OnLeave", function()
        if isEnabled then
            swatchBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        end
    end)

    -- Click opens color picker
    swatchBtn:SetScript("OnClick", function()
        if not isEnabled then
            return
        end
        local prevR, prevG, prevB, prevA = currentR, currentG, currentB, currentA
        local info = {
            r = currentR,
            g = currentG,
            b = currentB,
            hasOpacity = config.hasOpacity or false,
            opacity = config.hasOpacity and currentA or nil,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                currentR, currentG, currentB = r, g, b
                if config.hasOpacity then
                    currentA = ColorPickerFrame:GetColorAlpha()
                end
                UpdateSwatchColor()
                config.onChange(currentR, currentG, currentB, config.hasOpacity and currentA or nil)
            end,
            cancelFunc = function()
                currentR, currentG, currentB, currentA = prevR, prevG, prevB, prevA
                UpdateSwatchColor()
                config.onChange(prevR, prevG, prevB, config.hasOpacity and prevA or nil)
            end,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    -- Public methods
    function holder:SetColor(r, g, b, a)
        currentR, currentG, currentB = r, g, b
        if a then
            currentA = a
        end
        UpdateSwatchColor()
    end

    function holder:GetColor()
        return currentR, currentG, currentB, currentA
    end

    function holder:SetEnabled(enabled)
        isEnabled = enabled
        local color = enabled and 1 or 0.5
        label:SetTextColor(color, color, color)
        if alphaText then
            alphaText:SetTextColor(color, color, color)
        end
        if not enabled then
            swatchBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
            swatchBtn:SetAlpha(0.35)
        else
            swatchBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            swatchBtn:SetAlpha(1)
        end
    end

    -- Refresh method for OnShow pattern
    function holder:Refresh()
        if config.get then
            local r, g, b, a = config.get()
            currentR, currentG, currentB = r, g, b
            currentA = a or 1
            UpdateSwatchColor()
        end
        if config.enabled then
            holder:SetEnabled(config.enabled())
        end
    end

    -- Auto-register if refreshable
    if config.get or config.enabled then
        table.insert(RefreshableComponents, holder)
    end

    return holder
end

-- Modern scrollbar colors (defined early for use by TextArea and ScrollableContainer)
local ScrollbarColors = {
    track = { 0.12, 0.12, 0.12, 1 },
    thumb = { 0.3, 0.3, 0.3, 1 },
    thumbHover = { 0.45, 0.45, 0.45, 1 },
    thumbPressed = { 1, 0.82, 0, 0.8 },
    border = { 0.2, 0.2, 0.2, 1 },
}

-- Helper to apply modern styling to scrollbar (used by TextArea and ScrollableContainer)
local function ApplyModernScrollbarStyle(scrollBar)
    if not scrollBar then
        return
    end
    local colors = ScrollbarColors

    -- Hide default textures
    local trackBg = scrollBar.trackBg or scrollBar.Track
    if trackBg then
        trackBg:SetAlpha(0)
    end

    -- Try to find and hide the track textures
    for _, region in pairs({ scrollBar:GetRegions() }) do
        if region:GetObjectType() == "Texture" then
            local name = region:GetName() or ""
            if name:find("Track") or name:find("Border") or name:find("BG") then
                region:SetAlpha(0)
            end
        end
    end

    -- Create modern track background
    local track = CreateFrame("Frame", nil, scrollBar, "BackdropTemplate")
    track:SetPoint("TOPLEFT", 4, 0)
    track:SetPoint("BOTTOMRIGHT", -4, 0)
    track:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    track:SetBackdropColor(unpack(colors.track))
    track:SetBackdropBorderColor(unpack(colors.border))
    track:SetFrameLevel(scrollBar:GetFrameLevel())

    -- Style the thumb
    local thumb = scrollBar.ThumbTexture or scrollBar.thumbTexture
    if thumb then
        thumb:SetColorTexture(unpack(colors.thumb))
        thumb:SetSize(8, 40)

        -- Try to set up hover/press effects
        local thumbParent = thumb:GetParent()
        if thumbParent and thumbParent.SetScript then
            thumbParent:HookScript("OnEnter", function()
                thumb:SetColorTexture(unpack(colors.thumbHover))
            end)
            thumbParent:HookScript("OnLeave", function()
                thumb:SetColorTexture(unpack(colors.thumb))
            end)
        end
    end

    -- Hide scroll up/down buttons
    local scrollUp = scrollBar.ScrollUpButton or scrollBar.scrollUp or _G[scrollBar:GetName() .. "ScrollUpButton"]
    local scrollDown = scrollBar.ScrollDownButton
        or scrollBar.scrollDown
        or _G[scrollBar:GetName() .. "ScrollDownButton"]
    if scrollUp then
        scrollUp:SetAlpha(0)
        scrollUp:SetSize(1, 1)
        scrollUp:EnableMouse(false)
    end
    if scrollDown then
        scrollDown:SetAlpha(0)
        scrollDown:SetSize(1, 1)
        scrollDown:EnableMouse(false)
    end
end

-- TextArea color constants
local TextAreaColors = {
    bg = { 0.08, 0.08, 0.08, 0.9 },
    bgFocused = { 0.1, 0.1, 0.1, 0.95 },
    border = { 0.3, 0.3, 0.3, 1 },
    borderFocused = { 1, 0.82, 0, 1 },
    text = { 1, 1, 1, 1 },
}

---@class TextAreaConfig : ComponentConfig
---@field width number Width of the text area
---@field height number Height of the text area
---@field readOnly? boolean If true, text cannot be edited (default false)
---@field onTextChanged? fun(text: string) Callback when text changes
---@field onFocusGained? fun() Callback when focus gained
---@field onFocusLost? fun() Callback when focus lost

---Create a multiline text area (no scrollbar, mouse wheel scrolls)
---@param parent table Parent frame
---@param config TextAreaConfig Configuration table
---@return table holder Frame with .editBox, .SetText(v), .GetText(), .HighlightText(), .SetFocus()
function Components.TextArea(parent, config)
    local colors = TextAreaColors

    -- Container frame with backdrop
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(config.width, config.height)
    holder:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    holder:SetBackdropColor(unpack(colors.bg))
    holder:SetBackdropBorderColor(unpack(colors.border))

    -- Scroll frame (basic, no scrollbar)
    local scrollFrame = CreateFrame("ScrollFrame", nil, holder)
    scrollFrame:SetPoint("TOPLEFT", 1, -1)
    scrollFrame:SetPoint("BOTTOMRIGHT", -1, 1)
    scrollFrame:SetClipsChildren(true)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, self:GetScrollChild():GetHeight() - self:GetHeight())
        local newScroll = math.max(0, math.min(maxScroll, current - delta * 20))
        self:SetVerticalScroll(newScroll)
    end)

    -- Edit box
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetSize(config.width - 4, config.height)
    editBox:SetAutoFocus(false)
    editBox:SetTextInsets(6, 6, 6, 6)
    editBox:EnableMouse(true)
    editBox:SetTextColor(unpack(colors.text))

    if config.readOnly then
        editBox:SetScript("OnChar", function() end)
        editBox:SetScript("OnKeyDown", function() end)
    end

    scrollFrame:SetScrollChild(editBox)
    holder.editBox = editBox
    holder.scrollFrame = scrollFrame

    -- Focus visual state
    local function UpdateFocusVisual(focused)
        if focused then
            holder:SetBackdropColor(unpack(colors.bgFocused))
            holder:SetBackdropBorderColor(unpack(colors.borderFocused))
        else
            holder:SetBackdropColor(unpack(colors.bg))
            holder:SetBackdropBorderColor(unpack(colors.border))
        end
    end

    editBox:SetScript("OnEditFocusGained", function(self)
        UpdateFocusVisual(true)
        if config.onFocusGained then
            config.onFocusGained()
        end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        UpdateFocusVisual(false)
        if config.onFocusLost then
            config.onFocusLost()
        end
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Auto-resize content height based on text
    editBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        local _, fontHeight = self:GetFont()
        local lineCount = select(2, string.gsub(text, "\n", "\n")) + 1
        local contentHeight = math.max(config.height - 4, fontHeight * lineCount + 12)
        self:SetHeight(contentHeight)

        if config.onTextChanged then
            config.onTextChanged(text)
        end
    end)

    -- Track editbox for focus cleanup
    if panelEditBoxes then
        table.insert(panelEditBoxes, editBox)
    end

    -- Public methods
    function holder:SetText(text)
        editBox:SetText(text or "")
    end

    function holder:GetText()
        return editBox:GetText()
    end

    function holder:HighlightText()
        editBox:HighlightText()
    end

    function holder:SetFocus()
        editBox:SetFocus()
    end

    function holder:ClearFocus()
        editBox:ClearFocus()
    end

    return holder
end

---Initialize panelEditBoxes reference (called from CreateOptionsPanel)
---@param editBoxes table[] The editboxes array from the options panel
function Components.SetEditBoxesRef(editBoxes)
    panelEditBoxes = editBoxes
end

---Refresh all registered components (call on panel OnShow)
function Components.RefreshAll()
    for _, component in ipairs(RefreshableComponents) do
        if component.Refresh then
            component:Refresh()
        end
    end
end

---Clear refreshable components registry (call before recreating panel)
function Components.ClearRegistry()
    for i = #RefreshableComponents, 1, -1 do
        RefreshableComponents[i] = nil
    end
end

---Create a scrollable content container with auto-calculated width
---@param parent Frame Parent frame
---@param config ScrollableContainerConfig Configuration table
---@return table scrollFrame Scroll frame with :GetContentFrame(), :SetContentHeight(h), :GetContentWidth()
---@return table content Content frame
function Components.ScrollableContainer(parent, config)
    local contentHeight = config.contentHeight or 600
    local scrollbarWidth = config.scrollbarWidth or 24

    -- Holder frame (the scroll frame itself)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetClipsChildren(true)

    -- Position scrollbar
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", -18, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", -18, 16)

        -- Apply modern styling
        ApplyModernScrollbarStyle(scrollBar)
    end

    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    local parentWidth = parent.GetWidth and parent:GetWidth() or 540
    local contentWidth = parentWidth - scrollbarWidth
    content:SetSize(contentWidth, contentHeight)
    scrollFrame:SetScrollChild(content)

    -- Public methods
    function scrollFrame:GetContentFrame()
        return content
    end

    function scrollFrame:GetContentWidth()
        return contentWidth
    end

    function scrollFrame:GetContentHeight()
        return contentHeight
    end

    function scrollFrame:SetContentHeight(height)
        contentHeight = height
        content:SetHeight(height)
    end

    return scrollFrame, content
end

---Create a vertical layout helper for positioning elements
---@param parent table Parent frame
---@param config VerticalLayoutConfig Configuration table
---@return table layout Layout helper with :Add(component, spacing), :AddText(fontString, height), :Space(amount), :GetY()
function Components.VerticalLayout(parent, config)
    local x = config.x or 0
    local y = config.y or 0
    local currentY = y

    local layout = {}

    ---Add a component at the current Y position and advance
    ---@param component table Component frame to position
    ---@param height? number Height to advance (uses component height if not specified)
    ---@param spacing? number Extra spacing after component (default 0)
    function layout:Add(component, height, spacing)
        component:SetPoint("TOPLEFT", parent, "TOPLEFT", x, currentY)
        local advanceHeight = height or (component.GetHeight and component:GetHeight()) or 20
        currentY = currentY - advanceHeight - (spacing or 0)
    end

    ---Add a font string at the current Y position and advance
    ---@param fontString table FontString to position
    ---@param height number Height to advance
    ---@param spacing? number Extra spacing after text (default 0)
    function layout:AddText(fontString, height, spacing)
        fontString:SetPoint("TOPLEFT", parent, "TOPLEFT", x, currentY)
        currentY = currentY - height - (spacing or 0)
    end

    ---Add vertical space
    ---@param amount number Space to add
    function layout:Space(amount)
        currentY = currentY - amount
    end

    ---Get current Y position
    ---@return number
    function layout:GetY()
        return currentY
    end

    ---Set X position for subsequent items
    ---@param newX number New X position
    function layout:SetX(newX)
        x = newX
    end

    ---Get current X position
    ---@return number
    function layout:GetX()
        return x
    end

    ---Add multiple components on the same row, advancing Y by the tallest
    ---@param items table[] Array of {component, xOffset} pairs
    ---@param spacing? number Extra spacing after row (default 0)
    function layout:AddRow(items, spacing)
        local maxH = 0
        for _, item in ipairs(items) do
            local comp, xOff = item[1], item[2]
            comp:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, currentY)
            local h = (comp.GetHeight and comp:GetHeight()) or 20
            if h > maxH then
                maxH = h
            end
        end
        currentY = currentY - maxH - (spacing or 0)
    end

    return layout
end

---Create an accordion-style collapsible section
---@param parent table Parent frame
---@param config CollapsibleSectionConfig Configuration table
---@return table holder Frame with :SetCollapsed(bool), :IsCollapsed(), :GetContentFrame(), :GetContentHeight(), :SetContentHeight(h)
function Components.CollapsibleSection(parent, config)
    local HEADER_HEIGHT = 24
    local CONTENT_PADDING = 10
    local BORDER_COLOR = { 0.25, 0.25, 0.25, 1 }
    local CONTENT_BG_COLOR = { 0.08, 0.08, 0.08, 0.95 }

    -- Container frame with backdrop for border
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")

    -- Calculate width: explicit > parent-based with scrollbar offset > parent > default
    local sectionWidth = config.width
    if not sectionWidth then
        local parentWidth = parent.GetWidth and parent:GetWidth() or 480
        local scrollbarOffset = config.scrollbarOffset or 0
        sectionWidth = parentWidth - scrollbarOffset
    end
    holder:SetSize(sectionWidth, HEADER_HEIGHT)
    holder:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    holder:SetBackdropColor(0, 0, 0, 0) -- Transparent bg (header/content have their own)
    holder:SetBackdropBorderColor(unpack(BORDER_COLOR))

    -- Header button (clickable)
    local header = CreateFrame("Button", nil, holder)
    header:SetSize(holder:GetWidth() - 2, HEADER_HEIGHT - 1) -- Account for border
    header:SetPoint("TOPLEFT", 1, -1)

    -- Header background
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0.18, 0.18, 0.18, 1)

    -- Collapse indicator (chevron style)
    local indicator = header:CreateTexture(nil, "OVERLAY")
    indicator:SetSize(12, 12)
    indicator:SetPoint("LEFT", 10, 0)
    indicator:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    indicator:SetVertexColor(0.6, 0.6, 0.6)

    -- Title
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", indicator, "RIGHT", 8, 0)
    title:SetText(config.title)

    -- Content container (has background)
    local contentBg = CreateFrame("Frame", nil, holder)
    contentBg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    contentBg:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    contentBg:SetHeight(100)
    contentBg:Hide()

    -- Content background texture
    local contentBgTex = contentBg:CreateTexture(nil, "BACKGROUND")
    contentBgTex:SetAllPoints()
    contentBgTex:SetColorTexture(unpack(CONTENT_BG_COLOR))

    -- Separator line between header and content
    local separator = contentBg:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", 0, 0)
    separator:SetPoint("TOPRIGHT", 0, 0)
    separator:SetColorTexture(0.25, 0.25, 0.25, 1)

    -- Content frame (where children go, with padding)
    local content = CreateFrame("Frame", nil, contentBg)
    content:SetPoint("TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)
    content:SetPoint("TOPRIGHT", -CONTENT_PADDING, -CONTENT_PADDING)
    content:SetHeight(100) -- Default height, will be set by caller

    -- State
    local isCollapsed = config.defaultCollapsed ~= false -- Default to collapsed
    local contentHeight = 100

    -- Update visual state
    local function UpdateVisual()
        if isCollapsed then
            indicator:SetRotation(0) -- points right (native orientation)
            contentBg:Hide()
            holder:SetHeight(HEADER_HEIGHT)
        else
            indicator:SetRotation(math.rad(-90)) -- points down
            contentBg:Show()
            holder:SetHeight(HEADER_HEIGHT + contentHeight + CONTENT_PADDING * 2)
        end

        if config.onToggle then
            config.onToggle(not isCollapsed)
        end
    end

    -- Hover effect
    header:SetScript("OnEnter", function()
        headerBg:SetColorTexture(0.22, 0.22, 0.22, 1)
        indicator:SetVertexColor(0.8, 0.8, 0.8)
    end)
    header:SetScript("OnLeave", function()
        headerBg:SetColorTexture(0.18, 0.18, 0.18, 1)
        indicator:SetVertexColor(0.6, 0.6, 0.6)
    end)

    -- Click to toggle
    header:SetScript("OnClick", function()
        isCollapsed = not isCollapsed
        UpdateVisual()
    end)

    -- Public methods
    function holder:SetCollapsed(collapsed)
        isCollapsed = collapsed
        UpdateVisual()
    end

    function holder:IsCollapsed()
        return isCollapsed
    end

    function holder:GetContentFrame()
        return content
    end

    function holder:GetContentHeight()
        return contentHeight
    end

    function holder:SetContentHeight(height)
        contentHeight = height
        content:SetHeight(height)
        contentBg:SetHeight(height + CONTENT_PADDING * 2)
        if not isCollapsed then
            holder:SetHeight(HEADER_HEIGHT + contentHeight + CONTENT_PADDING * 2)
        end
    end

    function holder:SetTitle(newTitle)
        title:SetText(newTitle)
    end

    -- Refresh method (re-apply collapsed state)
    function holder:Refresh()
        UpdateVisual()
    end

    -- Initialize
    UpdateVisual()

    return holder
end

-- ============================================================================
-- BANNER
-- ============================================================================

---Create a warning banner with left accent bar and muted background
---@param parent table Parent frame
---@param config {text: string, icon?: string, color?: string, visible?: function, height?: number}
---@return table holder Banner frame with :Refresh(), :SetText()
function Components.Banner(parent, config)
    local BANNER_HEIGHT = config.height or 26

    -- Color presets: "red" (warning) or "orange" (info)
    local colors = {
        red = { bg = { 0.18, 0.06, 0.06, 0.6 }, accent = { 0.7, 0.12, 0.1, 0.8 }, text = { 0.85, 0.7, 0.65 } },
        orange = { bg = { 0.18, 0.12, 0.04, 0.6 }, accent = { 0.7, 0.45, 0.1, 0.8 }, text = { 0.9, 0.78, 0.6 } },
    }
    local c = colors[config.color] or colors.red

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(BANNER_HEIGHT)

    -- Subtle translucent background
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(c.bg))

    -- Thin accent line at the bottom
    local accent = holder:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetPoint("BOTTOMRIGHT")
    accent:SetHeight(1.5)
    accent:SetColorTexture(unpack(c.accent))

    -- Icon (supports atlas names or texture file paths)
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 10, 0)
    local iconPath = config.icon or "services-icon-warning"
    if iconPath:find("\\") or iconPath:find("/") then
        icon:SetTexture(iconPath)
    else
        icon:SetAtlas(iconPath)
    end

    -- Text
    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    text:SetPoint("RIGHT", -8, 0)
    text:SetJustifyH("LEFT")
    text:SetText(config.text or "")
    text:SetTextColor(unpack(c.text))

    function holder:SetText(newText)
        text:SetText(newText)
    end

    function holder:Refresh()
        if config.visible then
            holder:SetShown(config.visible())
        end
    end

    if config.visible then
        table.insert(RefreshableComponents, holder)
    end

    return holder
end
