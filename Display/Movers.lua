local _, BR = ...

-- ============================================================================
-- MOVER FRAME SYSTEM
-- Draggable positioning frames shown when the addon is "unlocked."
-- Each category (and the main combined frame) gets its own mover.
-- ============================================================================

local CATEGORIES = BR.CATEGORIES
local CATEGORY_LABELS = BR.CATEGORY_LABELS
local DIRECTION_ANCHORS = BR.DIRECTION_ANCHORS

local GetCategorySettings = BR.Helpers.GetCategorySettings
local IsCategorySplit = BR.Helpers.IsCategorySplit

local moverFrames = {} -- Per-category mover frames (shown when unlocked for drag positioning)
local lastDirection = {} -- Tracks previous growDirection per catKey for position conversion
local coordPopup -- Shared coordinate popup

-- Offset from anchor edge to frame center, in units of iconSize
local ANCHOR_TO_CENTER = {
    LEFT = { x = 0.5, y = 0 },
    RIGHT = { x = -0.5, y = 0 },
    TOP = { x = 0, y = -0.5 },
    BOTTOM = { x = 0, y = 0.5 },
    CENTER = { x = 0, y = 0 },
}

local EDIT_MODE_DIM_ALPHA = 0.3

---Round a number to the nearest integer
local function RoundCoord(x)
    return math.floor(x + 0.5)
end

-- Convert saved position from one anchor to another so the frame stays in place
local function ConvertPosition(oldAnchor, newAnchor, x, y, size)
    local o, n = ANCHOR_TO_CENTER[oldAnchor], ANCHOR_TO_CENTER[newAnchor]
    return RoundCoord(x + (o.x - n.x) * size), RoundCoord(y + (o.y - n.y) * size)
end

---Get the saved position table for a category key
---@param catKey string "main" or a category name
---@return table position {point, x, y}
local function GetSavedPosition(catKey)
    local db = BuffRemindersDB
    local defaults = BR.Display.defaults
    if catKey == "main" then
        return (db.categorySettings and db.categorySettings.main and db.categorySettings.main.position)
            or db.position
            or { point = "CENTER", x = 0, y = 0 }
    end
    local catSettings = db.categorySettings and db.categorySettings[catKey]
    return (catSettings and catSettings.position)
        or (defaults.categorySettings[catKey] and defaults.categorySettings[catKey].position)
        or { point = "CENTER", x = 0, y = 0 }
end

-- Forward declaration
local PositionMoverFrame

---Save a position for a category key and reposition its frame
---@param catKey string "main" or a category name
---@param x number
---@param y number
local function SavePosition(catKey, x, y)
    local db = BuffRemindersDB
    if not db.categorySettings then
        db.categorySettings = {}
    end
    if not db.categorySettings[catKey] then
        db.categorySettings[catKey] = {}
    end
    db.categorySettings[catKey].position = { x = x, y = y }

    -- Reposition the icon container frame
    local container = catKey == "main" and BR.Display.mainFrame or BR.Display.categoryFrames[catKey]
    if container then
        local settings = GetCategorySettings(catKey)
        local direction = settings.growDirection or "CENTER"
        local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
        container:ClearAllPoints()
        container:SetPoint(anchor, UIParent, "CENTER", x, y)
    end

    -- Keep the mover frame in sync
    PositionMoverFrame(catKey)
end

-- Build a label showing which categories are in mainFrame
local function GetMainFrameLabel()
    local parts = {}
    for _, category in ipairs(CATEGORIES) do
        if not IsCategorySplit(category) then
            table.insert(parts, CATEGORY_LABELS[category])
        end
    end
    if #parts == 0 then
        return "Main (empty)"
    elseif #parts == #CATEGORIES then
        return "Main (all)"
    else
        return table.concat(parts, " + ")
    end
end

-- Dim/restore the icon container for a specific mover during drag
local function GetContainerForCatKey(catKey)
    if catKey == "main" then
        return BR.Display.mainFrame
    end
    return BR.Display.categoryFrames[catKey]
end

local function DimContainer(catKey)
    local container = GetContainerForCatKey(catKey)
    if container then
        container:SetAlpha(EDIT_MODE_DIM_ALPHA)
    end
end

local function RestoreContainer(catKey)
    local container = GetContainerForCatKey(catKey)
    if container then
        container:SetAlpha(1)
    end
end

-- Finish a mover drag: read the direction-anchor edge, re-anchor, save
local function FinishMoverDrag(mover, catKey)
    mover.isDragging = false
    mover:StopMovingOrSizing()
    local settings = GetCategorySettings(catKey)
    local direction = settings.growDirection or "CENTER"
    local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
    local px, py = UIParent:GetCenter()
    local x, y
    if anchor == "LEFT" then
        x = RoundCoord(mover:GetLeft() - px)
        y = RoundCoord(select(2, mover:GetCenter()) - py)
    elseif anchor == "RIGHT" then
        x = RoundCoord(mover:GetRight() - px)
        y = RoundCoord(select(2, mover:GetCenter()) - py)
    elseif anchor == "TOP" then
        x = RoundCoord(select(1, mover:GetCenter()) - px)
        y = RoundCoord(mover:GetTop() - py)
    elseif anchor == "BOTTOM" then
        x = RoundCoord(select(1, mover:GetCenter()) - px)
        y = RoundCoord(mover:GetBottom() - py)
    else -- CENTER
        local cx, cy = mover:GetCenter()
        x = RoundCoord(cx - px)
        y = RoundCoord(cy - py)
    end
    mover:ClearAllPoints()
    mover:SetPoint(anchor, UIParent, "CENTER", x, y)
    SavePosition(catKey, x, y)
    RestoreContainer(catKey)
end

-- Coordinate popup: shared popup for typing exact X/Y positions on mover frames
local function CreateCoordinatePopup()
    local fontPath = BR.Display.GetFontPath()
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(190, 110)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    popup:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    popup:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 11, "OUTLINE")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Set Position")
    title:SetTextColor(1, 0.82, 0, 1)

    -- X row
    local xLabel = popup:CreateFontString(nil, "OVERLAY")
    xLabel:SetFont(fontPath, 11, "OUTLINE")
    xLabel:SetPoint("TOPLEFT", 10, -30)
    xLabel:SetText("X")
    xLabel:SetTextColor(1, 1, 1, 1)

    local xEdit = CreateFrame("EditBox", nil, popup)
    xEdit:SetSize(130, 20)
    xEdit:SetFont(fontPath, 11, "")
    xEdit:SetAutoFocus(false)
    local xContainer = BR.StyleEditBox(xEdit)
    xContainer:SetSize(130, 20)
    xContainer:SetPoint("LEFT", xLabel, "RIGHT", 8, 0)

    -- Y row
    local yLabel = popup:CreateFontString(nil, "OVERLAY")
    yLabel:SetFont(fontPath, 11, "OUTLINE")
    yLabel:SetPoint("TOPLEFT", 10, -56)
    yLabel:SetText("Y")
    yLabel:SetTextColor(1, 1, 1, 1)

    local yEdit = CreateFrame("EditBox", nil, popup)
    yEdit:SetSize(130, 20)
    yEdit:SetFont(fontPath, 11, "")
    yEdit:SetAutoFocus(false)
    local yContainer = BR.StyleEditBox(yEdit)
    yContainer:SetSize(130, 20)
    yContainer:SetPoint("LEFT", yLabel, "RIGHT", 8, 0)

    -- Apply button
    local applyBtn = BR.CreateButton(popup, "Apply", function()
        local xVal = tonumber(xEdit:GetText())
        local yVal = tonumber(yEdit:GetText())
        if not xVal or not yVal then
            return
        end
        local catKey = popup.catKey
        xVal = RoundCoord(xVal)
        yVal = RoundCoord(yVal)
        SavePosition(catKey, xVal, yVal)
        popup:Hide()
    end)
    applyBtn:SetPoint("BOTTOM", 0, 8)

    -- Tab from X to Y
    xEdit:SetScript("OnTabPressed", function()
        yEdit:SetFocus()
    end)

    -- Enter triggers Apply on either editbox
    xEdit:SetScript("OnEnterPressed", function()
        applyBtn:Click()
    end)
    yEdit:SetScript("OnEnterPressed", function()
        applyBtn:Click()
    end)
    yEdit:SetScript("OnTabPressed", function()
        xEdit:SetFocus()
    end)

    -- Escape to close
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    popup.xEdit = xEdit
    popup.yEdit = yEdit
    popup:Hide()
    return popup
end

local function ShowCoordinatePopup(catKey, mover)
    if not coordPopup then
        coordPopup = CreateCoordinatePopup()
    end
    coordPopup.catKey = catKey
    coordPopup.mover = mover
    coordPopup:ClearAllPoints()
    coordPopup:SetPoint("LEFT", mover, "RIGHT", 10, 0)

    local pos = GetSavedPosition(catKey)
    coordPopup.xEdit:SetText(tostring(pos.x or 0))
    coordPopup.yEdit:SetText(tostring(pos.y or 0))

    coordPopup:Show()
    coordPopup.xEdit:SetFocus()
end

-- Create a mover frame for positioning a category.
-- The mover matches the category's iconSize for accurate positioning. Shown when unlocked.
local function CreateMoverFrame(catKey, displayName)
    local fontPath = BR.Display.GetFontPath()
    local catSettings = GetCategorySettings(catKey)
    local iconSize = catSettings.iconSize or 64

    local mover = CreateFrame("Frame", nil, UIParent)
    mover:SetSize(iconSize, iconSize)
    mover:SetFrameStrata("HIGH")
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")

    -- Green background
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0.7, 0, 0.6)

    -- Label above the mover
    mover.label = mover:CreateFontString(nil, "OVERLAY")
    mover.label:SetPoint("BOTTOM", mover, "TOP", 0, 4)
    mover.label:SetFont(fontPath, 11, "OUTLINE")
    mover.label:SetTextColor(0.4, 1, 0.4, 1)
    mover.label:SetText(displayName or catKey)

    -- "Anchor" text below the green box (updated with growth direction in UpdateAnchor)
    mover.anchorText = mover:CreateFontString(nil, "OVERLAY")
    mover.anchorText:SetPoint("TOP", mover, "BOTTOM", 0, -4)
    mover.anchorText:SetFont(fontPath, 11, "OUTLINE")
    mover.anchorText:SetTextColor(0.4, 1, 0.4, 1)

    mover.catKey = catKey

    function mover:UpdateSize()
        local settings = GetCategorySettings(catKey)
        local size = settings.iconSize or 64
        self:SetSize(size, size)
    end

    -- Position at saved location using direction-based anchor
    local pos = GetSavedPosition(catKey)
    local initSettings = GetCategorySettings(catKey)
    local initDirection = initSettings.growDirection or "CENTER"
    local initAnchor = DIRECTION_ANCHORS[initDirection] or "CENTER"
    mover:SetPoint(initAnchor, UIParent, "CENTER", pos.x or 0, pos.y or 0)

    -- Tooltip
    BR.SetupTooltip(mover, "Buff Anchor", "Drag to reposition\nRight-click to set exact coordinates")

    -- Drag scripts
    mover:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        if coordPopup then
            coordPopup:Hide()
        end
        DimContainer(catKey)
        self.isDragging = true
        self:StartMoving()
    end)
    mover:SetScript("OnDragStop", function(self)
        FinishMoverDrag(self, catKey)
    end)
    mover:SetScript("OnHide", function(self)
        if self.isDragging then
            FinishMoverDrag(self, catKey)
        end
    end)

    -- Right-click to open coordinate popup
    mover:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            ShowCoordinatePopup(catKey, self)
        end
    end)

    mover:Hide()
    return mover
end

-- Position a mover frame at its saved coordinates using direction-based anchor
PositionMoverFrame = function(catKey)
    local mover = moverFrames[catKey]
    if not mover or mover.isDragging then
        return
    end
    local pos = GetSavedPosition(catKey)
    local settings = GetCategorySettings(catKey)
    local direction = settings.growDirection or "CENTER"
    local anchor = DIRECTION_ANCHORS[direction] or "CENTER"
    mover:ClearAllPoints()
    mover:SetPoint(anchor, UIParent, "CENTER", pos.x or 0, pos.y or 0)
end

-- Initialize mover frames for all categories (called from InitializeFrames)
local function InitializeMovers()
    moverFrames["main"] = CreateMoverFrame("main", GetMainFrameLabel())
    lastDirection["main"] = (GetCategorySettings("main").growDirection or "CENTER")
    for _, category in ipairs(CATEGORIES) do
        moverFrames[category] = CreateMoverFrame(category, CATEGORY_LABELS[category])
        lastDirection[category] = (GetCategorySettings(category).growDirection or "CENTER")
    end
end

-- Check if all categories are split into separate frames
local function AreAllCategoriesSplit()
    for _, category in ipairs(CATEGORIES) do
        if not IsCategorySplit(category) then
            return false
        end
    end
    return true
end

-- Update mover frame visibility and labels based on lock/split state.
-- IMPORTANT: Never reposition a mover that is already shown — doing so would cancel
-- an active StartMoving() drag via ClearAllPoints(). Only position on first show.
local function UpdateAnchor()
    if not BR.Display.mainFrame then
        return
    end

    local db = BuffRemindersDB
    local unlocked = not db.locked

    -- Main mover: show when unlocked AND not all categories split
    local allSplit = AreAllCategoriesSplit()
    local mainMover = moverFrames["main"]
    if mainMover then
        if unlocked and not allSplit then
            local mainSettings = GetCategorySettings("main")
            mainMover.label:SetText(GetMainFrameLabel())
            mainMover.anchorText:SetText("Anchor \194\183 Growth " .. (mainSettings.growDirection or "CENTER"))
            PositionMoverFrame("main")
            mainMover:Show()
        else
            mainMover:Hide()
        end
    end

    -- Category movers: show when unlocked AND that category is split
    for _, category in ipairs(CATEGORIES) do
        local mover = moverFrames[category]
        if mover then
            if unlocked and IsCategorySplit(category) then
                local catSettings = GetCategorySettings(category)
                mover.label:SetText(CATEGORY_LABELS[category])
                mover.anchorText:SetText("Anchor \194\183 Growth " .. (catSettings.growDirection or "CENTER"))
                PositionMoverFrame(category)
                mover:Show()
            else
                mover:Hide()
            end
        end
    end
end

-- Hide all mover frames
local function HideAllMovers()
    if coordPopup then
        coordPopup:Hide()
    end
    for _, mover in pairs(moverFrames) do
        if mover then
            mover:Hide()
        end
    end
end

-- Convert saved positions when growth direction changes (called from LayoutRefresh callback)
local function ConvertDirectionPositions()
    local allCatKeys = { "main" }
    for _, cat in ipairs(CATEGORIES) do
        allCatKeys[#allCatKeys + 1] = cat
    end
    for _, catKey in ipairs(allCatKeys) do
        local settings = GetCategorySettings(catKey)
        local dir = settings.growDirection or "CENTER"
        local oldDir = lastDirection[catKey]
        if oldDir and oldDir ~= dir then
            local oldAnchor = DIRECTION_ANCHORS[oldDir] or "CENTER"
            local newAnchor = DIRECTION_ANCHORS[dir] or "CENTER"
            local pos = GetSavedPosition(catKey)
            local size = settings.iconSize or 64
            local nx, ny = ConvertPosition(oldAnchor, newAnchor, pos.x or 0, pos.y or 0, size)
            SavePosition(catKey, nx, ny)
        end
        lastDirection[catKey] = dir
    end
end

-- Export module
BR.Movers = {
    Initialize = InitializeMovers,
    UpdateAnchor = UpdateAnchor,
    HideAll = HideAllMovers,
    SavePosition = SavePosition,
    GetMoverFrames = function()
        return moverFrames
    end,
    ConvertDirectionPositions = ConvertDirectionPositions,
}
