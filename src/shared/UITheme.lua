--[[
    HEIST CREW — UITheme
    ────────────────────────────────────────────────
    ONE look for every piece of UI, so the HUD stops being five different
    styles glued together. Added 2026-09-25 (Malachi: "make sure ui is nice
    not like crappy blocky").

    v2.1 "UI OVERHAUL" (2026-09-25, from Malachi's playtest video at
    2560x1372: "very simple / bad" — tiny text, panels on top of each other,
    too many waypoint chips, every box the same thin dark rectangle):

      • CHUNKY CARDS  — UITheme.card(): rounded 16, navy→deep-navy gradient,
        a 2px dark outline + a 1px light top highlight, so a panel reads as a
        solid object (Roblox-game style), not a hairline sketch.
      • ICON BADGES   — UITheme.badge(icon, color, size): a coloured circle
        with a big emoji icon in it. Icons live ONLY in badges; text stays
        clean words (UITheme.ICON has the whole set in one place).
      • LAYOUT GRID   — UITheme.slot(name): every HUD parents its panels into
        one of seven screen slots (a UIListLayout each), so nothing can ever
        overlap — two things in the same slot stack instead:

            ┌ topLeft (Roblox chat — we leave it alone) ┐
            │                 topCenter                 topRight │
            │                objective bar               cash    │
            │                toasts                      THE JOB │
            │ left                                       DAILY   │
            │ Boss tips                                 (rightEdge)
            │                                                    │
            │ bottomLeft          bottomCenter                   │
            │ MARK button       sneaking chips                   │
            │ role card         carry + keycard / drill /        │
            │                   heist door / car dashboard       │
            └────────────────────────────────────────────────────┘

        On touch screens the bottom-left is the thumbstick, so bottomLeft
        moves to the top-left (under Roblox's buttons) and tips go below it.
      • SCALE         — every slot has a UIScale driven by the viewport
        (UITheme.scale()): design size is a 900-px-tall screen, so 1080p
        draws at 1.2x, 1440p at ~1.5x, and phones never go below 0.8x.
        Modal screens (shop, daily, payout) call UITheme.autoScale().

    Used by the client HUDs AND by the server for in-world screens (TV,
    blueprint, role signs) so the world and the HUD match. The slot / scale
    functions are client-only (they touch PlayerGui + the camera).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UITheme = {}

-- ── Palette ────────────────────────────────────────────────────────────
UITheme.C = {
    bg        = Color3.fromRGB(14, 17, 28),     -- card fill (top of the gradient)
    bgDeep    = Color3.fromRGB(8, 10, 18),      -- card fill (bottom of the gradient)
    bgRaised  = Color3.fromRGB(30, 36, 54),     -- rows / tiles inside a card
    edge      = Color3.fromRGB(78, 88, 118),    -- card outline (slate; its gradient darkens the bottom)
    line      = Color3.fromRGB(255, 255, 255),
    text      = Color3.fromRGB(245, 247, 252),
    muted     = Color3.fromRGB(160, 172, 196),
    faint     = Color3.fromRGB(88, 100, 124),
    money     = Color3.fromRGB(74, 222, 128),
    gold      = Color3.fromRGB(252, 196, 45),
    danger    = Color3.fromRGB(248, 96, 96),
    dangerDeep= Color3.fromRGB(185, 28, 28),
    info      = Color3.fromRGB(56, 189, 248),
    pink      = Color3.fromRGB(244, 114, 182),
    purple    = Color3.fromRGB(167, 139, 250),
}

-- ── Type ───────────────────────────────────────────────────────────────
local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
UITheme.F = {
    display = Font.new(FAMILY, Enum.FontWeight.Heavy),
    bold    = Font.new(FAMILY, Enum.FontWeight.Bold),
    medium  = Font.new(FAMILY, Enum.FontWeight.Medium),
    mono    = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
}

-- Text sizes (design px — multiplied by UITheme.scale() on screen)
UITheme.T = {
    hero    = 30,   -- cash, big numbers
    title   = 22,   -- objective text, card titles
    body    = 17,   -- checklist steps, tip text
    small   = 14,   -- secondary lines
    caption = 12,   -- UPPERCASE labels
}

-- ── Icons (emoji, only ever drawn inside a badge) ──────────────────────
UITheme.ICON = {
    -- objectives / waypoints
    boss = "🎩", ready = "🚪", portal = "🚪", door = "🚪", keypad = "🔢", search = "🔍",
    key = "🔑", vault = "🔒", drill = "🔧", loot = "💰", smash = "💎", car = "🚗",
    marina = "⛵", jail = "🚔", breaker = "⚡", optional = "⭐", target = "🎯",
    role = "🎭", wait = "⏳", home = "🏠", alarm = "🚨", eye = "👀",
    -- HUD
    cash = "💵", bag = "💰", daily = "🎁", level = "⭐", tip = "🎩", sneak = "🤫",
    hidden = "🙈", check = "✅", star = "⭐", trophy = "🏆", camera = "📷",
    -- roles
    Hacker = "💻", Muscle = "💪", Driver = "🏎", Lookout = "👀",
}

-- ── Layout grid (design px) ────────────────────────────────────────────
UITheme.L = {
    MARGIN = 14,         -- safe margin from every screen edge
    GAP = 8,             -- space between stacked panels in a slot
    TOUCH_TOP = 64,      -- touch: slots that move to the top-left start below Roblox's buttons
    OBJ_H = 62,          -- objective bar height
    CASH_W = 200,        -- cash card width (FeelFX pops sit left of it)
    CASH_H = 58,
    JOB_W = 262,         -- THE JOB card width
    TIP_W = 300,         -- Boss tip card width
    ROLE_W = 280,        -- role card width
    DESIGN_H = 900,      -- design screen height (scale 1)
}

-- ── Helpers ────────────────────────────────────────────────────────────
function UITheme.corner(parent, px)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, px or 10)
    c.Parent = parent
    return c
end

-- Hairline / outline border
function UITheme.stroke(parent, color, transparency, thickness)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = color or UITheme.C.line
    s.Transparency = transparency or 0.88
    s.Thickness = thickness or 1
    s.Parent = parent
    return s
end

function UITheme.padding(parent, x, y)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, x or 12)
    p.PaddingRight = UDim.new(0, x or 12)
    p.PaddingTop = UDim.new(0, y or x or 12)
    p.PaddingBottom = UDim.new(0, y or x or 12)
    p.Parent = parent
    return p
end

-- Smoked-glass panel (v0.7 look — still used by a few flat rows)
function UITheme.panel(props)
    local f = Instance.new("Frame")
    f.BackgroundColor3 = UITheme.C.bg
    f.BackgroundTransparency = props and props.transparency or 0.18
    f.BorderSizePixel = 0
    for k, v in pairs(props or {}) do
        if k ~= "transparency" and k ~= "radius" and k ~= "noStroke" then f[k] = v end
    end
    UITheme.corner(f, props and props.radius or 12)
    if not (props and props.noStroke) then UITheme.stroke(f) end
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 205, 215))
    g.Parent = f
    return f
end

-- v2.1 CHUNKY CARD — the main surface of the HUD.
--   props: any Frame properties, plus
--     radius (16), transparency (0.08), accent (Color3: coloured outline instead of the slate edge)
--     (noHighlight is accepted for older callers; the bevel is now on the outline itself)
-- Returns the frame; frame.Stroke is its 2px outline. The outline carries a
-- top-light / bottom-dark gradient (the "bevel" that makes it look solid) —
-- recolour it with Stroke.Color and the bevel follows. No extra child frames,
-- so a card can hold its own UIListLayout safely.
function UITheme.card(props)
    props = props or {}
    local f = Instance.new("Frame")
    f.BackgroundColor3 = UITheme.C.bg
    f.BackgroundTransparency = props.transparency or 0.08
    f.BorderSizePixel = 0
    for k, v in pairs(props) do
        if k ~= "transparency" and k ~= "radius" and k ~= "accent" and k ~= "noHighlight" then
            (f :: any)[k] = v
        end
    end
    UITheme.corner(f, props.radius or 16)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 155, 170))
    g.Parent = f
    local s = UITheme.stroke(f, props.accent or UITheme.C.edge, props.accent and 0.15 or 0.2, 2)
    s.Name = "Stroke"
    local sg = Instance.new("UIGradient")
    sg.Rotation = 90
    sg.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(95, 95, 105))
    sg.Parent = s
    return f
end

-- A circle with an emoji icon in it. color = the ring/fill colour.
-- Returns the badge frame; badge.Icon is the TextLabel.
function UITheme.badge(icon, color, size, props)
    size = size or 40
    color = color or UITheme.C.gold
    local b = Instance.new("Frame")
    b.Name = "Badge"
    b.Size = UDim2.fromOffset(size, size)
    b.BackgroundColor3 = color
    b.BackgroundTransparency = 0.72
    b.BorderSizePixel = 0
    for k, v in pairs(props or {}) do (b :: any)[k] = v end
    UITheme.corner(b, math.ceil(size / 2))
    local s = UITheme.stroke(b, color, 0.05, math.max(2, math.floor(size / 16)))
    s.Name = "Ring"
    local l = Instance.new("TextLabel")
    l.Name = "Icon"
    l.BackgroundTransparency = 1
    l.Size = UDim2.fromScale(1, 1)
    l.Text = icon or ""
    l.TextColor3 = Color3.new(1, 1, 1)
    l.FontFace = UITheme.F.bold
    l.TextSize = math.floor(size * 0.56)
    l.TextXAlignment = Enum.TextXAlignment.Center
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = b
    return b
end

function UITheme.setBadge(badge, icon, color)
    if not badge then return end
    local l = badge:FindFirstChild("Icon")
    if l and icon then l.Text = icon end
    if color then
        badge.BackgroundColor3 = color
        local s = badge:FindFirstChild("Ring")
        if s then s.Color = color end
    end
end

function UITheme.label(props)
    local l = Instance.new("TextLabel")
    l.Text = ""   -- (fix v1.1.1) Roblox's default is the word "Label" — it showed on screen
    l.BackgroundTransparency = 1
    l.TextColor3 = UITheme.C.text
    l.FontFace = UITheme.F.bold
    l.TextSize = 16
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    for k, v in pairs(props or {}) do (l :: any)[k] = v end
    return l
end

-- Small uppercase caption ("CASH", "YOUR ROLE", "OBJECTIVE")
function UITheme.caption(text, props)
    local l = UITheme.label({
        Text = string.upper(text),
        TextColor3 = UITheme.C.muted,
        FontFace = UITheme.F.bold,
        TextSize = UITheme.T.caption,
    })
    for k, v in pairs(props or {}) do (l :: any)[k] = v end
    return l
end

-- Big rounded button (PLAY AGAIN, CLAIM, GOT IT). Returns the TextButton.
function UITheme.button(text, color, props)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = true
    b.BackgroundColor3 = color or UITheme.C.money
    b.BorderSizePixel = 0
    b.Text = text or ""
    b.TextColor3 = UITheme.C.bgDeep
    b.FontFace = UITheme.F.display
    b.TextSize = 20
    for k, v in pairs(props or {}) do (b :: any)[k] = v end
    UITheme.corner(b, 14)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
    g.Parent = b
    UITheme.stroke(b, UITheme.C.edge, 0.45, 2)
    return b
end

function UITheme.rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

-- "1234567" -> "$1,234,567"
function UITheme.money(n)
    local s = tostring(math.floor(n or 0))
    while true do
        local k
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return "$" .. s
end

-- ── Scale (client) ─────────────────────────────────────────────────────
local function isTouch()
    local UIS = game:GetService("UserInputService")
    return UIS.TouchEnabled and not UIS.KeyboardEnabled
end
UITheme.isTouch = isTouch

local function computeScale(vp)
    if not vp or vp.Y < 10 then return 1 end
    local s = vp.Y / UITheme.L.DESIGN_H
    s = math.min(s, vp.X / 1000)                     -- keep >= 1000 design px of width
    local floor = isTouch() and 0.8 or 0.7
    return math.clamp(s, floor, 1.6)
end

local scaleValue = 1
local scaleWatchers = {}     -- { {ui = UIScale, mult = number} }
local scaleHooked = false

local function applyScales()
    for i = #scaleWatchers, 1, -1 do
        local w = scaleWatchers[i]
        if w.ui.Parent then
            w.ui.Scale = scaleValue * w.mult
        else
            table.remove(scaleWatchers, i)
        end
    end
end

local function hookScale()
    if scaleHooked or not RunService:IsClient() then return end
    scaleHooked = true
    local conn
    local function bind()
        if conn then conn:Disconnect() conn = nil end
        local cam = workspace.CurrentCamera
        if not cam then return end
        local function upd()
            local s = computeScale(cam.ViewportSize)
            if math.abs(s - scaleValue) > 0.001 then
                scaleValue = s
                applyScales()
            end
        end
        conn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(upd)
        scaleValue = computeScale(cam.ViewportSize)
        applyScales()
    end
    bind()
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bind)
end

-- current HUD scale (1 = 900-px-tall screen)
function UITheme.scale()
    hookScale()
    return scaleValue
end

-- Give a GuiObject a UIScale that follows the screen size (x mult).
function UITheme.autoScale(guiObject, mult)
    hookScale()
    local ui = Instance.new("UIScale")
    ui.Name = "AutoScale"
    ui.Scale = scaleValue * (mult or 1)
    ui.Parent = guiObject
    table.insert(scaleWatchers, { ui = ui, mult = mult or 1 })
    return ui
end

-- ── Slots (client) ─────────────────────────────────────────────────────
-- One shared ScreenGui ("HC_HUD") with a frame per screen slot. Every HUD
-- parents its panels into a slot; the slot's UIListLayout stacks them in
-- LayoutOrder, so they can never overlap. Hidden panels (Visible = false)
-- take no space.
local hud = nil
local slots = {}

-- vertical: true = stack top→bottom; h = horizontal alignment; v = vertical alignment
local SLOT_DEF = {
    topCenter    = { anchor = Vector2.new(0.5, 0), h = Enum.HorizontalAlignment.Center, v = Enum.VerticalAlignment.Top },
    topRight     = { anchor = Vector2.new(1, 0),   h = Enum.HorizontalAlignment.Right,  v = Enum.VerticalAlignment.Top },
    left         = { anchor = Vector2.new(0, 0.5), h = Enum.HorizontalAlignment.Left,   v = Enum.VerticalAlignment.Center },
    bottomLeft   = { anchor = Vector2.new(0, 1),   h = Enum.HorizontalAlignment.Left,   v = Enum.VerticalAlignment.Bottom },
    bottomCenter = { anchor = Vector2.new(0.5, 1), h = Enum.HorizontalAlignment.Center, v = Enum.VerticalAlignment.Bottom },
    rightEdge    = { anchor = Vector2.new(1, 0),   h = Enum.HorizontalAlignment.Right,  v = Enum.VerticalAlignment.Top },
    center       = { anchor = Vector2.new(0.5, 0.5), h = Enum.HorizontalAlignment.Center, v = Enum.VerticalAlignment.Center },
}

local function slotPosition(name)
    local M = UITheme.L.MARGIN
    local touch = isTouch()
    if name == "topCenter" then return UDim2.new(0.5, 0, 0, M) end
    if name == "topRight" then return UDim2.new(1, -M, 0, M) end
    if name == "left" then
        -- touch: the role card sits top-left, tips go a little lower
        return touch and UDim2.new(0, M, 0.58, 0) or UDim2.new(0, M, 0.5, 0)
    end
    if name == "bottomLeft" then
        if touch then return UDim2.new(0, M, 0, UITheme.L.TOUCH_TOP) end   -- thumbstick lives bottom-left
        return UDim2.new(0, M, 1, -M)
    end
    if name == "bottomCenter" then return UDim2.new(0.5, 0, 1, -M - (touch and 6 or 0)) end
    if name == "center" then return UDim2.fromScale(0.5, 0.5) end
    return UDim2.new(1, -M, 0, M)
end

-- the shared HUD ScreenGui (created on first use)
function UITheme.hud()
    if hud and hud.Parent then return hud end
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    if hud and hud.Parent then return hud end      -- another thread made it while we waited
    local old = pg:FindFirstChild("HC_HUD")
    if old then old:Destroy() end
    local g = Instance.new("ScreenGui")
    g.Name = "HC_HUD"
    g.ResetOnSpawn = false
    g.IgnoreGuiInset = true
    g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    g.DisplayOrder = 2
    hud = g
    slots = {}
    g.Parent = pg
    return g
end

function UITheme.slot(name)
    local g = UITheme.hud()
    local s = slots[name]
    if s and s.Parent then return s end
    local def = SLOT_DEF[name] or SLOT_DEF.topRight
    if name == "bottomLeft" and isTouch() then
        -- phones: this slot moves to the top-left (thumbstick), so it grows DOWN from there
        def = { anchor = Vector2.new(0, 0), h = Enum.HorizontalAlignment.Left, v = Enum.VerticalAlignment.Top }
    end
    local f = Instance.new("Frame")
    f.Name = "Slot_" .. name
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    f.AnchorPoint = def.anchor
    f.Position = slotPosition(name)
    f.Size = UDim2.fromOffset(0, 0)
    f.AutomaticSize = Enum.AutomaticSize.XY
    local list = Instance.new("UIListLayout")
    list.FillDirection = Enum.FillDirection.Vertical
    list.HorizontalAlignment = def.h
    list.VerticalAlignment = def.v
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, UITheme.L.GAP)
    list.Parent = f
    UITheme.autoScale(f)
    slots[name] = f
    f.Parent = g
    -- rightEdge sits directly under the topRight stack (cash + THE JOB), never on it
    if name == "rightEdge" then
        local top = UITheme.slot("topRight")
        -- (positions are real screen pixels; AbsoluteSize already includes the UIScale)
        local function follow()
            local bottom = top.AbsolutePosition.Y + top.AbsoluteSize.Y
            f.Position = UDim2.new(1, -UITheme.L.MARGIN, 0, math.floor(bottom + UITheme.L.GAP * scaleValue))
        end
        top:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)
        top:GetPropertyChangedSignal("AbsolutePosition"):Connect(follow)
        follow()
    end
    return f
end

return UITheme
