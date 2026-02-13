local _, BR = ...

-- ============================================================================
-- GLOW MODULE
-- ============================================================================
-- Shared glow primitives for expiration warnings and consumable rebuff borders.
-- Uses LibCustomGlow for Pixel/AutoCast effects and a custom pulsing border.

local LCG = LibStub("LibCustomGlow-1.0")

BR.Glow = {}

-- Default glow color (orange) — used as fallback throughout the addon
BR.Glow.DEFAULT_COLOR = { 0.95, 0.57, 0.07, 1 }

-- ============================================================================
-- PULSING BORDER (shared primitive)
-- ============================================================================
-- Creates a 4-edge colored border with a bounce alpha animation.
-- Multiple independent borders per frame are supported via the `key` parameter,
-- which namespaces the state stored on the frame.

---@param frame table
---@param key string Unique key to namespace this border's state on the frame
---@param color number[] {r, g, b [, a]}
---@param thickness? number Border thickness in pixels (default 2)
function BR.Glow.PulsingBorderStart(frame, key, color, thickness)
    local cr, cg, cb, ca = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    local stateKey = "_pulsingBorder_" .. key
    local state = frame[stateKey]
    thickness = thickness or 2

    if not state then
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetPoint("TOPLEFT", -thickness, thickness)
        holder:SetPoint("BOTTOMRIGHT", thickness, -thickness)
        holder:SetFrameLevel(frame:GetFrameLevel() + 5)
        local t = holder:CreateTexture(nil, "OVERLAY")
        t:SetPoint("TOPLEFT")
        t:SetPoint("TOPRIGHT")
        t:SetHeight(thickness)
        t:SetColorTexture(cr, cg, cb, ca)
        local b = holder:CreateTexture(nil, "OVERLAY")
        b:SetPoint("BOTTOMLEFT")
        b:SetPoint("BOTTOMRIGHT")
        b:SetHeight(thickness)
        b:SetColorTexture(cr, cg, cb, ca)
        local l = holder:CreateTexture(nil, "OVERLAY")
        l:SetPoint("TOPLEFT")
        l:SetPoint("BOTTOMLEFT")
        l:SetWidth(thickness)
        l:SetColorTexture(cr, cg, cb, ca)
        local r = holder:CreateTexture(nil, "OVERLAY")
        r:SetPoint("TOPRIGHT")
        r:SetPoint("BOTTOMRIGHT")
        r:SetWidth(thickness)
        r:SetColorTexture(cr, cg, cb, ca)
        local ag = holder:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.3)
        fade:SetDuration(0.6)
        fade:SetSmoothing("IN_OUT")
        state =
            { holder = holder, anim = ag, edges = { t, b, l, r }, color = { cr, cg, cb, ca }, thickness = thickness }
        frame[stateKey] = state
    else
        local prev = state.color
        if prev[1] ~= cr or prev[2] ~= cg or prev[3] ~= cb or prev[4] ~= ca then
            for _, edge in ipairs(state.edges) do
                edge:SetColorTexture(cr, cg, cb, ca)
            end
            state.color = { cr, cg, cb, ca }
        end
        if state.thickness ~= thickness then
            state.holder:SetPoint("TOPLEFT", -thickness, thickness)
            state.holder:SetPoint("BOTTOMRIGHT", thickness, -thickness)
            state.edges[1]:SetHeight(thickness) -- top
            state.edges[2]:SetHeight(thickness) -- bottom
            state.edges[3]:SetWidth(thickness) -- left
            state.edges[4]:SetWidth(thickness) -- right
            state.thickness = thickness
        end
    end
    state.holder:Show()
    if not state.anim:IsPlaying() then
        state.anim:Play()
    end
end

---@param frame table
---@param key string Must match the key used in PulsingBorderStart
function BR.Glow.PulsingBorderStop(frame, key)
    local state = frame["_pulsingBorder_" .. key]
    if state then
        state.anim:Stop()
        state.holder:Hide()
    end
end

-- ============================================================================
-- GLOW TYPES (Pixel, AutoCast, Border)
-- ============================================================================

BR.Glow.Types = {
    { name = "Pixel" },
    { name = "AutoCast" },
    { name = "Border" },
}

---Start a glow by type index
---@param frame table
---@param typeIndex number 1=Pixel, 2=AutoCast, 3=Border
---@param color number[] {r, g, b, a}
---@param key string Unique key for this glow instance
---@param size? number Glow thickness/scale (default 2)
function BR.Glow.Start(frame, typeIndex, color, key, size)
    size = size or 2
    if typeIndex == 1 then
        LCG.PixelGlow_Start(frame, color, nil, nil, nil, size, nil, nil, nil, key)
    elseif typeIndex == 2 then
        LCG.AutoCastGlow_Start(frame, color, nil, nil, size / 2, nil, nil, key)
    elseif typeIndex == 3 then
        BR.Glow.PulsingBorderStart(frame, key, color, size)
    end
end

---Stop a specific glow type on a frame
---@param frame table
---@param typeIndex number 1=Pixel, 2=AutoCast, 3=Border
---@param key string Must match the key used in Start
function BR.Glow.Stop(frame, typeIndex, key)
    if typeIndex == 1 then
        LCG.PixelGlow_Stop(frame, key)
    elseif typeIndex == 2 then
        LCG.AutoCastGlow_Stop(frame, key)
    elseif typeIndex == 3 then
        BR.Glow.PulsingBorderStop(frame, key)
    end
end

---Stop all glow types on a frame for a given key (use when the active type is unknown)
---@param frame table
---@param key string Must match the key used in Start
function BR.Glow.StopAll(frame, key)
    LCG.PixelGlow_Stop(frame, key)
    LCG.AutoCastGlow_Stop(frame, key)
    BR.Glow.PulsingBorderStop(frame, key)
end

-- ============================================================================
-- HIGH-LEVEL GLOW FUNCTIONS
-- ============================================================================

local EXPIRATION_KEY = "BR_expiration"

-- Per-frame glow state key (avoids polluting frame namespace with multiple keys)
local GLOW_STATE_KEY = "_brGlowState"

---Compare two color tables {r, g, b, a} for equality
---@param a number[]|nil
---@param b number[]|nil
---@return boolean
local function ColorsEqual(a, b)
    if a == b then
        return true
    end
    if not a or not b then
        return false
    end
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

---Show/hide expiration glow on a buff frame (reads type + color from DB or cached settings)
---@param frame table
---@param show boolean
---@param category? string Category name for per-category glow settings (nil = use global defaults)
---@param cachedSettings? {typeIndex: number, color: number[], size: number} Pre-fetched glow settings to avoid DB reads
function BR.Glow.SetExpiration(frame, show, category, cachedSettings)
    local state = frame[GLOW_STATE_KEY]

    if show then
        local typeIndex, color, size
        if cachedSettings then
            typeIndex = cachedSettings.typeIndex
            color = cachedSettings.color
            size = cachedSettings.size
        elseif category then
            typeIndex = BR.Config.GetCategorySetting(category, "glowType") or 1
            color = BR.Config.GetCategorySetting(category, "glowColor") or BR.Glow.DEFAULT_COLOR
            size = BR.Config.GetCategorySetting(category, "glowSize") or 2
        else
            local db = BuffRemindersDB
            typeIndex = (db.defaults and db.defaults.glowType) or 1
            color = (db.defaults and db.defaults.glowColor) or BR.Glow.DEFAULT_COLOR
            size = (db.defaults and db.defaults.glowSize) or 2
        end

        -- Already glowing with the same type, size, and color — don't restart (preserves animation state)
        if
            state
            and state.showing
            and state.typeIndex == typeIndex
            and state.size == size
            and ColorsEqual(state.color, color)
        then
            return
        end

        -- Stop previous glow if type, size, or color changed
        if state and state.showing then
            BR.Glow.Stop(frame, state.typeIndex, EXPIRATION_KEY)
        end

        BR.Glow.Start(frame, typeIndex, color, EXPIRATION_KEY, size)
        frame[GLOW_STATE_KEY] = { showing = true, typeIndex = typeIndex, size = size, color = color }
    else
        if state and state.showing then
            BR.Glow.Stop(frame, state.typeIndex, EXPIRATION_KEY)
            state.showing = false
        end
    end
end
