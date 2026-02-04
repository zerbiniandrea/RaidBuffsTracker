local _, BR = ...

-- ============================================================================
-- UI COMPONENT FACTORY
-- ============================================================================
-- Reusable UI components for the options panel (Platynator-style factory pattern).
-- These reduce code duplication and provide consistent styling.

local Components = BR.Components
local SetupTooltip = BR.SetupTooltip
local RefreshableComponents = BR.RefreshableComponents

---@class ComponentConfig
---@class SliderConfig : ComponentConfig
---@field label string Display label for the slider
---@field min number Minimum value
---@field max number Maximum value
---@field step? number Step increment (default 1)
---@field value? number Initial value (deprecated: prefer get)
---@field get? fun(): number Getter for initial value and refresh (preferred over value)
---@field suffix? string Value suffix (e.g., "px", "%")
---@field onChange fun(val: number) Callback when value changes
---@field labelWidth? number Width of label (default 70)
---@field sliderWidth? number Width of slider (default 100)

---@class CheckboxConfig : ComponentConfig
---@field label string Display label
---@field checked? boolean Initial checked state (deprecated: prefer get)
---@field get? fun(): boolean Getter for initial value and refresh (preferred over checked)
---@field tooltip? string Tooltip description
---@field onChange fun(checked: boolean) Callback when checked state changes

---@class DirectionButtonsConfig : ComponentConfig
---@field label? string Optional label (default "Direction:")
---@field selected? string Initial direction (deprecated: prefer get)
---@field get? fun(): string Getter for initial value and refresh (preferred over selected)
---@field onChange fun(dir: string) Callback when direction changes
---@field width? number Dropdown width (default 90)

---@class CategoryHeaderConfig : ComponentConfig
---@field text string Header text
---@field category CategoryName Category for visibility toggles

-- Panel EditBoxes tracking (populated by CreateOptionsPanel, used by Components)
local panelEditBoxes = nil ---@type table[]?

-- Counter for unique dropdown names
local directionDropdownCounter = 0

---Create a compact slider with clickable numeric input and editbox
---@param parent table Parent frame
---@param config SliderConfig Configuration table
---@return table holder Frame containing slider with .slider, .valueText, .SetValue(v), .GetValue()
function Components.Slider(parent, config)
    local labelWidth = config.labelWidth or 70
    local sliderWidth = config.sliderWidth or 100
    local step = config.step or 1
    local suffix = config.suffix or ""

    -- Container frame
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(labelWidth + sliderWidth + 60, 20)

    -- Label
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(labelWidth)
    label:SetJustifyH("LEFT")
    label:SetText(config.label)
    holder.label = label

    -- Slider
    local slider = CreateFrame("Slider", nil, holder, "OptionsSliderTemplate")
    slider:SetPoint("LEFT", label, "RIGHT", 5, 0)
    slider:SetSize(sliderWidth, 14)
    slider:SetMinMaxValues(config.min, config.max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local initialValue = config.get and config.get() or config.value
    slider:SetValue(initialValue)
    slider.Low:SetText("")
    slider.High:SetText("")
    slider.Text:SetText("")
    holder.slider = slider

    -- Clickable value display button
    local valueBtn = CreateFrame("Button", nil, holder)
    valueBtn:SetPoint("LEFT", slider, "RIGHT", 6, 0)
    valueBtn:SetSize(40, 16)

    local valueText = valueBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetAllPoints()
    valueText:SetJustifyH("LEFT")
    valueText:SetText(initialValue .. suffix)
    holder.valueText = valueText

    -- Edit box (hidden by default)
    local editBox = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    editBox:SetSize(35, 16)
    editBox:SetPoint("LEFT", slider, "RIGHT", 6, 0)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:Hide()

    editBox:SetScript("OnEnterPressed", function(self)
        local num = tonumber(self:GetText())
        if num then
            num = math.max(config.min, math.min(config.max, num))
            slider:SetValue(num)
        end
        self:Hide()
        valueBtn:Show()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:Hide()
        valueBtn:Show()
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        self:Hide()
        valueBtn:Show()
    end)

    -- Track editbox for focus cleanup on panel hide
    if panelEditBoxes then
        table.insert(panelEditBoxes, editBox)
    end

    valueBtn:SetScript("OnClick", function()
        valueBtn:Hide()
        editBox:SetText(tostring(math.floor(slider:GetValue())))
        editBox:Show()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    SetupTooltip(valueBtn, "Click to type a value", nil, "ANCHOR_TOP")

    slider:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val)
        valueText:SetText(val .. suffix)
        config.onChange(val)
    end)

    -- Mouse wheel support (Platynator pattern)
    holder:EnableMouseWheel(true)
    holder:SetScript("OnMouseWheel", function(_, delta)
        if slider:IsEnabled() then
            local newVal = slider:GetValue() + (delta * step)
            newVal = math.max(config.min, math.min(config.max, newVal))
            slider:SetValue(newVal)
        end
    end)

    -- Public methods
    function holder:SetValue(val)
        slider:SetValue(val)
    end

    function holder:GetValue()
        return slider:GetValue()
    end

    function holder:SetEnabled(enabled)
        local color = enabled and 1 or 0.5
        slider:SetEnabled(enabled)
        label:SetTextColor(color, color, color)
        valueText:SetTextColor(color, color, color)
    end

    -- Refresh method for OnShow pattern (re-reads value from DB)
    function holder:Refresh()
        if config.get then
            slider:SetValue(config.get())
        end
    end

    -- Auto-register if refreshable
    if config.get then
        table.insert(RefreshableComponents, holder)
    end

    return holder
end

---Create a checkbox with label and optional tooltip
---@param parent table Parent frame
---@param config CheckboxConfig Configuration table
---@return table holder Frame containing checkbox with .checkbox, .SetChecked(v), .GetChecked()
function Components.Checkbox(parent, config)
    -- Container frame
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(200, 20)

    local cb = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", 0, 0)
    local initialChecked = config.get and config.get() or config.checked
    cb:SetChecked(initialChecked)
    cb:SetScript("OnClick", function(self)
        config.onChange(self:GetChecked())
    end)
    holder.checkbox = cb

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(config.label)
    holder.label = label
    cb.label = label -- For SetCheckboxEnabled compatibility

    if config.tooltip then
        SetupTooltip(cb, config.label, config.tooltip)
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
            label:SetTextColor(1, 1, 1)
        else
            label:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    -- Refresh method for OnShow pattern
    function holder:Refresh()
        if config.get then
            cb:SetChecked(config.get())
        end
    end

    -- Auto-register if refreshable
    if config.get then
        table.insert(RefreshableComponents, holder)
    end

    return holder
end

---Create direction buttons (LEFT, CENTER, RIGHT, UP, DOWN)
---@param parent table Parent frame
---@param config DirectionButtonsConfig Configuration table
---@return table holder Frame containing direction dropdown with .SetDirection(dir)
function Components.DirectionButtons(parent, config)
    local directions = { "LEFT", "CENTER", "RIGHT", "UP", "DOWN" }
    local dirLabels = { LEFT = "Left", CENTER = "Center", RIGHT = "Right", UP = "Up", DOWN = "Down" }
    local width = config.width or 90

    -- Generate unique name for dropdown
    directionDropdownCounter = directionDropdownCounter + 1
    local dropdownName = "BuffRemindersDirectionDropdown" .. directionDropdownCounter

    -- Container frame
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(70 + width + 20, 26)

    -- Label
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(config.label or "Direction:")
    holder.label = label

    -- Dropdown
    local dropdown = CreateFrame("Frame", dropdownName, holder, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", label, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(dropdown, width)
    holder.dropdown = dropdown

    -- Store current value (use get() if available for initial value)
    local currentValue = config.get and config.get() or config.selected

    -- Initialize dropdown
    local function InitializeDropdown(_, level)
        for _, dir in ipairs(directions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = dirLabels[dir] or dir
            info.value = dir
            info.checked = currentValue == dir
            info.func = function()
                currentValue = dir
                UIDropDownMenu_SetSelectedValue(dropdown, dir)
                UIDropDownMenu_SetText(dropdown, dirLabels[dir] or dir)
                config.onChange(dir)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(dropdown, InitializeDropdown)
    UIDropDownMenu_SetSelectedValue(dropdown, currentValue)
    UIDropDownMenu_SetText(dropdown, dirLabels[currentValue] or currentValue)

    -- Public method to update selection (backwards compatible)
    function holder:SetDirection(dir)
        currentValue = dir
        UIDropDownMenu_SetSelectedValue(dropdown, dir)
        UIDropDownMenu_SetText(dropdown, dirLabels[dir] or dir)
    end

    -- Refresh method for OnShow pattern
    function holder:Refresh()
        if config.get then
            local dir = config.get()
            currentValue = dir
            UIDropDownMenu_SetSelectedValue(dropdown, dir)
            UIDropDownMenu_SetText(dropdown, dirLabels[dir] or dir)
        end
    end

    -- Auto-register if refreshable
    if config.get then
        table.insert(RefreshableComponents, holder)
    end

    -- Backwards compatibility: empty buttons table (no longer used)
    holder.buttons = {}

    return holder
end

---Create category header with content visibility toggles [W][S][D][R]
---@param parent table Parent frame
---@param config CategoryHeaderConfig Configuration table
---@param updateCallback fun() Function to call when visibility changes (UpdateDisplay or RefreshTestDisplay)
---@return table header FontString for the header
function Components.CategoryHeader(parent, config, updateCallback)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetText("|cffffcc00" .. config.text .. "|r")

    local toggles = {
        { key = "openWorld", label = "W", tooltip = "Open World" },
        { key = "scenario", label = "S", tooltip = "Scenarios (Delves, Torghast, etc.)" },
        { key = "dungeon", label = "D", tooltip = "Dungeons (including M+)" },
        { key = "raid", label = "R", tooltip = "Raids" },
    }

    local lastToggle
    for i, toggle in ipairs(toggles) do
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(18, 14)
        if i == 1 then
            btn:SetPoint("LEFT", header, "RIGHT", 8, 0)
        else
            btn:SetPoint("LEFT", lastToggle, "RIGHT", 2, 0)
        end

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg.key = toggle.key

        local btnLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btnLabel:SetPoint("CENTER", 0, 0)
        btnLabel:SetText(toggle.label)

        local function UpdateToggleVisual()
            local db = BuffRemindersDB
            local visibility = db.categoryVisibility and db.categoryVisibility[config.category]
            local enabled = not visibility or visibility[toggle.key] ~= false
            if enabled then
                bg:SetColorTexture(0.2, 0.6, 0.2, 0.8) -- Green
                btnLabel:SetTextColor(1, 1, 1)
            else
                bg:SetColorTexture(0.4, 0.2, 0.2, 0.8) -- Dim red
                btnLabel:SetTextColor(0.6, 0.6, 0.6)
            end
        end
        btn.UpdateVisual = UpdateToggleVisual
        UpdateToggleVisual()

        btn:SetScript("OnClick", function()
            local db = BuffRemindersDB
            if not db.categoryVisibility then
                db.categoryVisibility = {}
            end
            if not db.categoryVisibility[config.category] then
                db.categoryVisibility[config.category] =
                    { openWorld = true, scenario = true, dungeon = true, raid = true }
            end
            db.categoryVisibility[config.category][toggle.key] = not db.categoryVisibility[config.category][toggle.key]
            UpdateToggleVisual()
            updateCallback()
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(toggle.tooltip, 1, 1, 1)
            GameTooltip:AddLine("Click to toggle visibility in " .. toggle.tooltip:lower(), 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        lastToggle = btn
    end

    return header
end

---@class DropdownOption
---@field label string Display text
---@field value any Value to pass to callback

---@class DropdownConfig : ComponentConfig
---@field label string Label text
---@field options DropdownOption[] Available options
---@field selected? any Initial selected value (deprecated: prefer get)
---@field get? fun(): any Getter for initial value and refresh (preferred over selected)
---@field width? number Dropdown width (default 100)
---@field onChange fun(value: any) Callback when selection changes

---Create a dropdown with label (Platynator-style wrapper around UIDropDownMenu)
---@param parent table Parent frame
---@param config DropdownConfig Configuration table
---@param uniqueName string Unique global name for the dropdown frame
---@return table holder Frame containing dropdown with .SetValue(v), .GetValue(), .SetEnabled(bool)
function Components.Dropdown(parent, config, uniqueName)
    local width = config.width or 100

    -- Container frame
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(70 + width + 20, 26)

    -- Label
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(config.label)
    holder.label = label

    -- Dropdown
    local dropdown = CreateFrame("Frame", uniqueName, holder, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", label, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(dropdown, width)
    holder.dropdown = dropdown

    -- Store current value (use get() if available for initial value)
    local currentValue = config.get and config.get() or config.selected

    -- Initialize dropdown
    local function InitializeDropdown(_, level)
        for _, opt in ipairs(config.options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.checked = currentValue == opt.value
            info.func = function()
                currentValue = opt.value
                UIDropDownMenu_SetSelectedValue(dropdown, opt.value)
                UIDropDownMenu_SetText(dropdown, opt.label)
                config.onChange(opt.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(dropdown, InitializeDropdown)
    UIDropDownMenu_SetSelectedValue(dropdown, config.selected)

    -- Set initial text
    for _, opt in ipairs(config.options) do
        if opt.value == config.selected then
            UIDropDownMenu_SetText(dropdown, opt.label)
            break
        end
    end

    -- Public methods
    function holder:SetValue(value)
        currentValue = value
        UIDropDownMenu_SetSelectedValue(dropdown, value)
        for _, opt in ipairs(config.options) do
            if opt.value == value then
                UIDropDownMenu_SetText(dropdown, opt.label)
                break
            end
        end
    end

    function holder:GetValue()
        return currentValue
    end

    function holder:SetEnabled(enabled)
        local color = enabled and 1 or 0.5
        label:SetTextColor(color, color, color)
        if enabled then
            UIDropDownMenu_EnableDropDown(dropdown)
        else
            UIDropDownMenu_DisableDropDown(dropdown)
        end
    end

    -- Refresh method for OnShow pattern
    function holder:Refresh()
        if config.get then
            local value = config.get()
            currentValue = value
            UIDropDownMenu_SetSelectedValue(dropdown, value)
            for _, opt in ipairs(config.options) do
                if opt.value == value then
                    UIDropDownMenu_SetText(dropdown, opt.label)
                    break
                end
            end
        end
    end

    -- Auto-register if refreshable
    if config.get then
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
    local editBox = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    editBox:SetSize(width, 18)
    editBox:SetPoint("LEFT", label, "RIGHT", 5, 0)
    editBox:SetAutoFocus(false)
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
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

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
    end

    -- Refresh method for OnShow pattern
    function holder:Refresh()
        if config.get then
            editBox:SetText(config.get() or "")
        end
    end

    -- Auto-register if refreshable
    if config.get then
        table.insert(RefreshableComponents, holder)
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
