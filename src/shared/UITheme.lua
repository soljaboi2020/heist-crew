--[[
    HEIST CREW — UITheme
    ────────────────────────────────────────────────
    ONE look for every piece of UI, so the HUD stops being five different
    styles glued together. Added 2026-09-25 (Malachi: "make sure ui is nice
    not like crappy blocky").

    v2.1 "UI OVERHAUL" (2026-09-25): chunky cards, icon badges, a slot grid so
    panels never overlap, and one scale that follows the screen size.

    v3.2 "MIAMI HUD" (2026-09-25, from Malachi's Studio screenshots: "polished
    but the text is tiny, too many panels, everything is the same dark navy,
    the Boss icon is a purple cylinder"):

      • MIAMI PALETTE — cards are a deep night-purple with a coloured glow at
        the top (props.tint, default hot pink) fading to near-black, and a
        pink → teal GLOW EDGE (UIStroke gradient). Recolour a card's edge with
        card.Stroke.Color = X like before and it switches to a plain bevel in
        that colour; set it back to UITheme.GLOW (white) for the glow again.
      • BIGGER TYPE — body 19, title 24, caption 14 (design px; x1.2 at 1080p).
        Muted text is lighter so it stays readable on the dark cards.
      • REAL ICONS — a badge given an emoji that renders badly on Roblox gets a
        Roblox-hosted picture instead (UITheme.IMG, all verified on the Roblox
        thumbnail API). The Boss is his actual "Fedora and Shades" hat
        (asset 168167624, made by Roblox) instead of the 🎩 emoji, which drew
        as a purple cylinder. Any icon string that starts with "rbx"/"http" is
        drawn as an image too.
      • DRAWN SHAPES — UITheme.chevron() / UITheme.closeX() / UITheme.check()
        are built from Frames, because BuilderSans has no ▾ ▲ ✕ ✓ glyphs
        (they drew as empty boxes).
      • CHUNKY BUTTONS — UITheme.button(): bright fill, light-top gradient,
        thick darker outline, like the shop cards. Touch targets >= 44 px.
      • PHONES — the HUD ScreenGui stays inside the device safe area (notches);
        "rightEdge" (DAILY / MUSIC) now lives INSIDE the topRight stack, so it
        can never overlap THE JOB card again; on touch the "left" slot (Boss
        tips, tutorial) stacks under the role card at the top-left, away from
        the thumbstick.

    LAYOUT GRID — UITheme.slot(name): every HUD parents its panels into one of
    the screen slots (a UIListLayout each), so two things in the same slot
    stack instead of overlapping:

            ┌ topLeft (Roblox chat — we leave it alone) ┐
            │                 topCenter                 topRight │
            │                objective bar               cash    │
            │                toasts                      THE JOB │
            │ left                                   [DAILY][♪]  │ ← rightEdge (inside topRight)
            │ Boss tips                                          │
            │                                                    │
            │ bottomLeft          bottomCenter                   │
            │ MARK button       sneaking chips                   │
            │ role card         carry + keycard / drill /  MUSIC │
            │                   heist door / car dashboard       │
            └────────────────────────────────────────────────────┘

        On touch screens the bottom-left is the thumbstick, so bottomLeft
        moves to the top-left (under Roblox's buttons) and "left" stacks
        under it.
      • SCALE — every slot has a UIScale driven by the viewport
        (UITheme.scale()): design size is a 900-px-tall screen, so 1080p
        draws at 1.2x, 1440p at ~1.5x, and phones never go below 0.8x.
        Modal screens (shop, daily, payout) call UITheme.autoScale().

    Used by the client HUDs AND by the server for in-world screens (TV,
    blueprint, role signs) so the world and the HUD match. The slot / scale
    functions are client-only (they touch PlayerGui + the camera).

    API (all backward compatible with v2.1):
        C / F / T / L / ICON / IMG / GLOW
        corner stroke padding panel card badge setBadge label caption button
        rgb money isTouch scale autoScale hud slot
        (v3.2) chevron closeX check pill tint glowStroke iconIsImage
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UITheme = {}

-- ── Palette ────────────────────────────────────────────────────────────
-- Miami nights: deep purple cards, hot pink + teal accents. The "meaning"
-- colours (money green, gold, danger red) are unchanged so nothing reads
-- differently than before.
UITheme.C = {
    bg        = Color3.fromRGB(28, 19, 52),     -- card fill (under the glow)
    bgDeep    = Color3.fromRGB(12, 8, 26),      -- card fill (bottom of the gradient)
    bgRaised  = Color3.fromRGB(52, 38, 92),     -- rows / tiles / secondary buttons inside a card
    edge      = Color3.fromRGB(128, 104, 184),  -- lavender outline (when a card is not glowing)
    line      = Color3.fromRGB(255, 255, 255),
    text      = Color3.fromRGB(250, 248, 255),
    muted     = Color3.fromRGB(206, 196, 232),  -- (v3.2) lighter: small text stays readable
    faint     = Color3.fromRGB(140, 126, 176),
    money     = Color3.fromRGB(74, 222, 128),
    gold      = Color3.fromRGB(252, 196, 45),
    danger    = Color3.fromRGB(248, 96, 96),
    dangerDeep= Color3.fromRGB(185, 28, 28),
    info      = Color3.fromRGB(56, 189, 248),
    pink      = Color3.fromRGB(244, 114, 182),  -- Miami hot pink
    purple    = Color3.fromRGB(167, 139, 250),
    -- v3.2
    teal      = Color3.fromRGB(45, 212, 191),   -- Miami teal
    hot       = Color3.fromRGB(236, 72, 153),   -- deeper pink (gradients)
    sunset    = Color3.fromRGB(251, 146, 60),   -- orange
    violet    = Color3.fromRGB(139, 92, 246),
}
local C = UITheme.C

-- A card edge set to this colour shows the pink → teal glow gradient.
UITheme.GLOW = Color3.new(1, 1, 1)

-- ── Type ───────────────────────────────────────────────────────────────
local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
UITheme.F = {
    display = Font.new(FAMILY, Enum.FontWeight.Heavy),
    bold    = Font.new(FAMILY, Enum.FontWeight.Bold),
    medium  = Font.new(FAMILY, Enum.FontWeight.Medium),
    mono    = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
}

-- Text sizes (design px — multiplied by UITheme.scale() on screen; 1080p = x1.2)
UITheme.T = {
    hero    = 32,   -- cash, big numbers
    title   = 24,   -- objective text, card titles
    body    = 19,   -- checklist steps, tip text
    small   = 16,   -- secondary lines (never smaller than this for words)
    caption = 14,   -- UPPERCASE labels
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
    hidden = "🙈", check = "✅", star = "⭐", trophy = "🏆", camera = "📷", music = "🎵", muted = "🔇",
    -- roles
    Hacker = "💻", Muscle = "💪", Driver = "🏎️", Lookout = "👀",
}

-- ── Pictures (Roblox-hosted, verified 2026-09-25 on thumbnails.roblox.com) ──
-- rbxthumb works for any catalog asset; only Roblox-made items are used so
-- they can't be deleted/moderated out from under us.
UITheme.IMG = {
    -- "Fedora and Shades" (Roblox, asset 168167624) — the Boss's own hat (NpcFactory)
    boss = "rbxthumb://type=Asset&id=168167624&w=150&h=150",
}

-- emoji that draw badly in Roblox's emoji font → the picture to use instead
local EMOJI_IMG = {
    ["🎩"] = UITheme.IMG.boss,     -- drew as a purple cylinder in the tutorial offer
}

-- true when an icon string should be drawn as an image
function UITheme.iconIsImage(icon)
    if type(icon) ~= "string" then return false end
    if EMOJI_IMG[icon] then return true end
    return icon:sub(1, 3) == "rbx" or icon:sub(1, 4) == "http"
end

local function iconImage(icon)
    if type(icon) ~= "string" then return nil end
    if EMOJI_IMG[icon] then return EMOJI_IMG[icon] end
    if icon:sub(1, 3) == "rbx" or icon:sub(1, 4) == "http" then return icon end
    return nil
end

-- ── Layout grid (design px) ────────────────────────────────────────────
UITheme.L = {
    MARGIN = 14,         -- safe margin from every screen edge
    GAP = 8,             -- space between stacked panels in a slot
    TOUCH_TOP = 64,      -- touch: slots that move to the top-left start below Roblox's buttons
    OBJ_H = 62,          -- objective bar height
    OBJ_MAX_W = 620,     -- objective bar never wider than this (phones: cash + role card stay clear)
    CASH_W = 210,        -- cash card width (FeelFX pops sit left of it)
    CASH_H = 60,
    JOB_W = 280,         -- THE JOB card width
    TIP_W = 330,         -- Boss tip card width
    ROLE_W = 280,        -- role card width (expanded)
    TOUCH_MIN = 44,      -- smallest tappable thing (px at scale 1)
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

-- colour sequences used by cards + strokes
local GLOW_SEQ = ColorSequence.new({
    ColorSequenceKeypoint.new(0, C.pink),
    ColorSequenceKeypoint.new(0.5, C.purple),
    ColorSequenceKeypoint.new(1, C.teal),
})
local BEVEL_SEQ = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(110, 110, 125))

local function fillSeq(tint, strength)
    strength = strength or 0.34
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.bg:Lerp(tint, strength)),
        ColorSequenceKeypoint.new(0.45, C.bg),
        ColorSequenceKeypoint.new(1, C.bgDeep),
    })
end

-- A UIStroke that glows pink → teal while its Color is UITheme.GLOW (white),
-- and turns into a plain bevelled outline in any other colour you give it.
function UITheme.glowStroke(parent, color, transparency, thickness)
    local s = UITheme.stroke(parent, color or UITheme.GLOW, transparency or 0.1, thickness or 2)
    local g = Instance.new("UIGradient")
    g.Name = "Glow"
    g.Rotation = 20
    g.Parent = s
    local function sync()
        if s.Color == UITheme.GLOW then
            g.Color = GLOW_SEQ
        else
            g.Color = BEVEL_SEQ
        end
    end
    sync()
    pcall(function() s:GetPropertyChangedSignal("Color"):Connect(sync) end)
    return s
end

-- Smoked-glass panel (v0.7 look — still used by a few flat rows + the server's in-world screens)
function UITheme.panel(props)
    local f = Instance.new("Frame")
    f.BackgroundColor3 = UITheme.C.bg
    f.BackgroundTransparency = props and props.transparency or 0.18
    f.BorderSizePixel = 0
    for k, v in pairs(props or {}) do
        if k ~= "transparency" and k ~= "radius" and k ~= "noStroke" then (f :: any)[k] = v end
    end
    UITheme.corner(f, props and props.radius or 12)
    if not (props and props.noStroke) then UITheme.stroke(f) end
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 205, 215))
    g.Parent = f
    return f
end

-- CHUNKY CARD — the main surface of the HUD.
--   props: any Frame properties, plus
--     radius (16), transparency (0.06),
--     accent (Color3: the edge in this colour instead of the pink → teal glow),
--     tint   (Color3: the colour glowing at the top of the card; default hot pink),
--     noGlow (true: a quiet lavender edge instead of the glow)
--     (noHighlight is accepted for older callers)
-- Returns the frame; frame.Stroke is its outline, frame.Fill its UIGradient.
-- No extra child frames, so a card can hold its own UIListLayout safely.
-- (If a caller passes its own BackgroundColor3 the card keeps that colour
--  with the old light→dark shading instead of the Miami gradient.)
function UITheme.card(props)
    props = props or {}
    local f = Instance.new("Frame")
    local ownColor = props.BackgroundColor3 ~= nil
    f.BackgroundColor3 = ownColor and props.BackgroundColor3 or Color3.new(1, 1, 1)
    f.BackgroundTransparency = props.transparency or 0.06
    f.BorderSizePixel = 0
    for k, v in pairs(props) do
        if k ~= "transparency" and k ~= "radius" and k ~= "accent" and k ~= "noHighlight"
            and k ~= "tint" and k ~= "noGlow" and k ~= "BackgroundColor3" then
            (f :: any)[k] = v
        end
    end
    UITheme.corner(f, props.radius or 16)
    local g = Instance.new("UIGradient")
    g.Name = "Fill"
    g.Rotation = 90
    if ownColor then
        g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 155, 170))
    else
        g.Color = fillSeq(props.tint or props.accent or C.hot)
    end
    g.Parent = f
    local edge = props.accent or (props.noGlow and C.edge) or UITheme.GLOW
    local s = UITheme.glowStroke(f, edge, props.accent and 0.08 or (props.noGlow and 0.35 or 0.12), 2)
    s.Name = "Stroke"
    return f
end

-- recolour the glow at the top of a card (made by UITheme.card)
function UITheme.tint(card, color, strength)
    local g = card and card:FindFirstChild("Fill")
    if g and g:IsA("UIGradient") and color then g.Color = fillSeq(color, strength) end
end

-- A circle with an icon in it. color = the ring/fill colour.
-- icon = an emoji, or an image ("rbxthumb://…", "rbxassetid://…"); emoji
-- that render badly (🎩) are swapped for pictures automatically.
-- Returns the badge frame; badge.Icon is the TextLabel, badge.Img the ImageLabel.
function UITheme.badge(icon, color, size, props)
    size = size or 40
    color = color or UITheme.C.gold
    local b = Instance.new("Frame")
    b.Name = "Badge"
    b.Size = UDim2.fromOffset(size, size)
    b.BackgroundColor3 = color
    b.BackgroundTransparency = 0.6
    b.BorderSizePixel = 0
    for k, v in pairs(props or {}) do (b :: any)[k] = v end
    UITheme.corner(b, math.ceil(size / 2))
    local fill = Instance.new("UIGradient")
    fill.Name = "Shine"
    fill.Rotation = 90
    fill.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 120, 135))
    fill.Parent = b
    local s = UITheme.stroke(b, color, 0.05, math.max(2, math.floor(size / 14)))
    s.Name = "Ring"
    local l = Instance.new("TextLabel")
    l.Name = "Icon"
    l.BackgroundTransparency = 1
    l.Size = UDim2.fromScale(1, 1)
    l.Text = ""
    l.TextColor3 = Color3.new(1, 1, 1)
    l.FontFace = UITheme.F.bold
    l.TextSize = math.floor(size * 0.56)
    l.TextXAlignment = Enum.TextXAlignment.Center
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = b
    local img = Instance.new("ImageLabel")
    img.Name = "Img"
    img.BackgroundTransparency = 1
    img.AnchorPoint = Vector2.new(0.5, 0.5)
    img.Position = UDim2.fromScale(0.5, 0.52)
    img.Size = UDim2.fromScale(0.86, 0.86)
    img.ScaleType = Enum.ScaleType.Fit
    img.Image = ""
    img.Visible = false
    img.Parent = b
    UITheme.setBadge(b, icon or "")
    return b
end

function UITheme.setBadge(badge, icon, color)
    if not badge then return end
    if icon then
        local l = badge:FindFirstChild("Icon")
        local img = badge:FindFirstChild("Img")
        local pic = iconImage(icon)
        if pic and img then
            img.Image = pic
            img.Visible = true
            if l then l.Text = "" end
        else
            if img then img.Visible = false end
            if l then l.Text = icon end
        end
    end
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
    l.TextSize = 17
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
        FontFace = UITheme.F.display,
        TextSize = UITheme.T.caption,
    })
    for k, v in pairs(props or {}) do (l :: any)[k] = v end
    return l
end

-- CHUNKY BUTTON (PLAY AGAIN, CLAIM, LET'S GO). Returns the TextButton.
-- Bright fill with a light top, a thick darker outline and a heavy font —
-- the shop-card look. Dark fills (bgRaised) get white text automatically.
function UITheme.button(text, color, props)
    color = color or UITheme.C.money
    local b = Instance.new("TextButton")
    b.AutoButtonColor = true
    b.BackgroundColor3 = color
    b.BorderSizePixel = 0
    b.Text = text or ""
    local lum = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
    b.TextColor3 = lum > 0.45 and UITheme.C.bgDeep or UITheme.C.text
    b.FontFace = UITheme.F.display
    b.TextSize = 20
    for k, v in pairs(props or {}) do (b :: any)[k] = v end
    UITheme.corner(b, 14)
    local g = Instance.new("UIGradient")
    g.Name = "Shine"
    g.Rotation = 90
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(235, 235, 235)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(175, 175, 180)),
    })
    g.Parent = b
    local s = UITheme.stroke(b, color:Lerp(Color3.new(0, 0, 0), 0.5), 0, 3)
    s.Name = "Stroke"
    return b
end

-- A little rounded chip: coloured fill, dark bold text ("FOX SPEED", "LIVE")
function UITheme.pill(text, color, props)
    color = color or UITheme.C.gold
    local l = UITheme.label({ Text = text or "", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 14,
        TextColor3 = UITheme.C.bgDeep, BackgroundColor3 = color, BackgroundTransparency = 0 })
    for k, v in pairs(props or {}) do (l :: any)[k] = v end
    UITheme.corner(l, 12)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, 9)
    p.PaddingRight = UDim.new(0, 9)
    p.Parent = l
    return l
end

-- ── Drawn shapes (BuilderSans has no ▾ ▲ ✕ ✓ — they drew as empty boxes) ──
local function bar(parent, w, h, pos, rot, color)
    local f = Instance.new("Frame")
    f.Name = "Bar"
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Size = UDim2.fromOffset(w, h)
    f.Position = pos
    f.Rotation = rot
    f.BackgroundColor3 = color
    f.BorderSizePixel = 0
    UITheme.corner(f, math.ceil(math.min(w, h) / 2))
    f.Parent = parent
    return f
end

-- A "^" chevron that points UP (Rotation 180 = down, 90 = right, -90 = left).
-- Returns the holder Frame (square, `size` px). Rotate / move the holder.
function UITheme.chevron(size, color, thickness)
    size = size or 20
    thickness = thickness or math.max(3, math.floor(size / 6))
    color = color or UITheme.C.text
    local h = Instance.new("Frame")
    h.Name = "Chevron"
    h.BackgroundTransparency = 1
    h.Size = UDim2.fromOffset(size, size)
    local len = size * 0.62
    bar(h, thickness, len, UDim2.new(0.5, -size * 0.19, 0.5, 0), 45, color)
    bar(h, thickness, len, UDim2.new(0.5, size * 0.19, 0.5, 0), -45, color)
    return h
end

-- recolour / fade a chevron, cross or check made by these helpers
function UITheme.paintShape(shape, color, transparency)
    if not shape then return end
    for _, b in ipairs(shape:GetChildren()) do
        if b:IsA("Frame") then
            if color then b.BackgroundColor3 = color end
            if transparency then b.BackgroundTransparency = transparency end
        end
    end
end

-- An "X" (close buttons)
function UITheme.closeX(size, color, thickness)
    size = size or 16
    local h = Instance.new("Frame")
    h.Name = "Cross"
    h.BackgroundTransparency = 1
    h.Size = UDim2.fromOffset(size, size)
    for _, rot in ipairs({ 45, -45 }) do
        bar(h, thickness or 3, size, UDim2.fromScale(0.5, 0.5), rot, color or UITheme.C.text)
    end
    return h
end

-- A tick mark
function UITheme.check(size, color, thickness)
    size = size or 16
    local k = size / 14
    local h = Instance.new("Frame")
    h.Name = "Tick"
    h.BackgroundTransparency = 1
    h.Size = UDim2.fromOffset(size, size)
    bar(h, thickness or 2, 4.5 * k, UDim2.fromOffset(4.75 * k, 8.6 * k), -45, color or UITheme.C.bgDeep)
    bar(h, thickness or 2, 8 * k, UDim2.fromOffset(8.3 * k, 7.2 * k), 39, color or UITheme.C.bgDeep)
    return h
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
    if name == "left" then return UDim2.new(0, M, 0.5, 0) end
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
    -- (v3.2) phones: keep every slot clear of notches / rounded corners
    pcall(function() g.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
    hud = g
    slots = {}
    g.Parent = pg
    return g
end

-- a stack frame (AutomaticSize XY + a UIListLayout)
local function stack(name, horizontal, h, v)
    local f = Instance.new("Frame")
    f.Name = name
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    f.Size = UDim2.fromOffset(0, 0)
    f.AutomaticSize = Enum.AutomaticSize.XY
    local list = Instance.new("UIListLayout")
    list.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
    list.HorizontalAlignment = h
    list.VerticalAlignment = v
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, UITheme.L.GAP)
    list.Parent = f
    return f
end

function UITheme.slot(name)
    local g = UITheme.hud()
    local s = slots[name]
    if s and s.Parent then return s end

    -- (v3.2) rightEdge = a row INSIDE the topRight stack (under cash + THE JOB).
    -- It used to be its own slot that chased topRight's size, and lagged a frame
    -- behind — DAILY sat on top of THE JOB card in the screenshots.
    if name == "rightEdge" then
        local top = UITheme.slot("topRight")
        local f = stack("Slot_rightEdge", true, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
        f.LayoutOrder = 100
        slots[name] = f
        f.Parent = top
        return f
    end
    -- (v3.2) phones: Boss tips / tutorial stack under the role card, top-left,
    -- instead of the middle-left where the thumbstick is
    if name == "left" and isTouch() then
        local tl = UITheme.slot("bottomLeft")
        local f = stack("Slot_left", false, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
        f.LayoutOrder = 50
        slots[name] = f
        f.Parent = tl
        return f
    end

    local def = SLOT_DEF[name] or SLOT_DEF.topRight
    if name == "bottomLeft" and isTouch() then
        -- phones: this slot moves to the top-left (thumbstick), so it grows DOWN from there
        def = { anchor = Vector2.new(0, 0), h = Enum.HorizontalAlignment.Left, v = Enum.VerticalAlignment.Top }
    end
    local f = stack("Slot_" .. name, false, def.h, def.v)
    f.AnchorPoint = def.anchor
    f.Position = slotPosition(name)
    UITheme.autoScale(f)
    slots[name] = f
    f.Parent = g
    return f
end

return UITheme
