--[[
    HEIST CREW — ShopUI  ("GEAR WALL")
    ────────────────────────────────────────────────
    v1.0 (2026-09-25). The shop modal. Opens when the local player triggers a
    ProximityPrompt named "OpenShop"; closes with the X, a click on the dimmed
    backdrop, Escape, or gamepad B.

        SAFEHOUSE                               CASH $12,450   (X)
        GEAR WALL
        [GEAR] (MASKS) (BAGS) (CARS) (TRAILS) (CODES) (VIP)
        ─────────────────────────────────────────────────────
        card grid / code box / VIP card
        ─────────────────────────────────────────────────────
        inline feedback                               ESC  CLOSE

    Talks to the ShopAction RemoteFunction:
        InvokeServer(action, payload) -> { ok, msg, state }
        actions: getState · buyGear{id} · buyMask{id} · equipMask{id} · redeemCode{code}
                 · buyCosmetic{id} · equipCosmetic{id}                                 (v2.0)
        state  = { cash, gear = {...}, masks = {owned ids}, mask, vip, vipPassId, codesRedeemed = {...},
                   cosmetics = { catalog = {items}, owned = {ids}, equipped = {bag, car, trail} } }
    v2.0: BAGS / CARS / TRAILS tabs are built from state.cosmetics.catalog the
    first time the server sends it (the item list lives in CosmeticsService).
    VIP is bought with MarketplaceService:PromptGamePassPurchase (client-side);
    state is re-fetched after PromptGamePassPurchaseFinished.

    PUBLIC API:
        ShopUI:start()
        ShopUI:open()
        ShopUI:close()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local ShopUI = {}
local localPlayer = Players.LocalPlayer

local W, H = 720, 460             -- design size; shrinks to fit small screens
local MIN_W, MIN_H = 560, 300     -- below this the whole modal scales down instead
local CLOSE_ACTION = "HC_ShopClose"
local INVOKE_TIMEOUT = 10

local TABS = {
    { id = "gear",  label = "GEAR" },
    { id = "masks", label = "MASKS" },
    { id = "bag",   label = "BAGS" },     -- v2.0 cosmetics (page id = cosmetic category)
    { id = "car",   label = "CARS" },
    { id = "trail", label = "TRAILS" },
    { id = "codes", label = "CODES" },
    { id = "vip",   label = "VIP" },
}

-- mask swatches come from the game's own Neon-Miami palette
local SWATCHES = {}
for _, c in ipairs(Constants.MIAMI.NEONS) do table.insert(SWATCHES, UITheme.rgb(c)) end
for _, c in ipairs(Constants.MIAMI.PASTELS) do table.insert(SWATCHES, UITheme.rgb(c)) end

local GAMEPAD = {
    [Enum.UserInputType.Gamepad1] = true, [Enum.UserInputType.Gamepad2] = true,
    [Enum.UserInputType.Gamepad3] = true, [Enum.UserInputType.Gamepad4] = true,
}

-- ── helpers ────────────────────────────────────────────────────────────
local function tween(obj, t, props, style, dir)
    local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad,
        dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function frame(props)
    local f = Instance.new("Frame")
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    for k, v in pairs(props or {}) do f[k] = v end
    return f
end

local function list(parent, horizontal, gap, hAlign, vAlign)
    local l = Instance.new("UIListLayout")
    l.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, gap or 8)
    if hAlign then l.HorizontalAlignment = hAlign end
    if vAlign then l.VerticalAlignment = vAlign end
    l.Parent = parent
    return l
end

-- accepts either an array of ids or a {id = true} map
local function toSet(t)
    local s = {}
    if type(t) ~= "table" then return s end
    for k, v in pairs(t) do
        if type(k) == "number" and type(v) == "string" then
            s[v] = true
        elseif type(k) == "string" and v then
            s[k] = true
        end
    end
    return s
end

local function toList(t)
    local out = {}
    for id in pairs(toSet(t)) do table.insert(out, id) end
    table.sort(out)
    return out
end

-- drawn check mark (two rotated bars) — crisp at any size, no font glyph needed
local function makeCheck(parent, color, order)
    local holder = frame({ Name = "Check", LayoutOrder = order or 0, Size = UDim2.fromOffset(14, 14) })
    local short = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 5),
        Position = UDim2.fromOffset(4.6, 8.8), Rotation = -45, BackgroundColor3 = color, BackgroundTransparency = 0 })
    UITheme.corner(short, 1)
    short.Parent = holder
    local long = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 9.5),
        Position = UDim2.fromOffset(8.6, 6.9), Rotation = 39, BackgroundColor3 = color, BackgroundTransparency = 0 })
    UITheme.corner(long, 1)
    long.Parent = holder
    holder.Parent = parent
    return holder, { short, long }
end

-- Hover / press feedback for any TextButton: scale + background lift.
-- The resting transparency is stored in the "BaseT" attribute so state changes can move it.
local function hook(btn, liftable)
    local scale = Instance.new("UIScale")
    scale.Parent = btn
    local function base() return btn:GetAttribute("BaseT") or btn.BackgroundTransparency end
    local function enter()
        if not btn.Active then return end
        tween(scale, 0.12, { Scale = 1.03 })
        if liftable then
            tween(btn, 0.12, { BackgroundTransparency = math.max(0, base() - 0.08) })
        end
    end
    local function leave()
        tween(scale, 0.15, { Scale = 1 })
        tween(btn, 0.15, { BackgroundTransparency = base() })
    end
    btn.MouseEnter:Connect(enter)
    btn.MouseLeave:Connect(leave)
    btn.SelectionGained:Connect(enter)
    btn.SelectionLost:Connect(leave)
    btn.MouseButton1Down:Connect(function()
        if btn.Active then tween(scale, 0.08, { Scale = 0.95 }) end
    end)
    btn.MouseButton1Up:Connect(function()
        tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
    end)
    return scale
end

local function setBase(btn, t)
    btn:SetAttribute("BaseT", t)
    btn.BackgroundTransparency = t
end

-- A pill-shaped action button with a centred [check] LABEL row.
local function actionButton(parent, props)
    local btn = Instance.new("TextButton")
    btn.Name = "Action"
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.BackgroundColor3 = T.money
    btn.Selectable = true
    for k, v in pairs(props or {}) do btn[k] = v end
    UITheme.corner(btn, 10)
    local stroke = UITheme.stroke(btn, T.line, 1)
    local row = frame({ Size = UDim2.fromScale(1, 1) })
    row.Parent = btn
    list(row, true, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
    local check, bars = makeCheck(row, T.money, 1)
    local label = UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
        FontFace = UITheme.F.display, TextSize = 14, TextColor3 = T.bg })
    label.Parent = row
    btn.Parent = parent
    hook(btn, true)
    return { btn = btn, label = label, check = check, checkBars = bars, stroke = stroke }
end

-- Paint an action button. kind: "buy" | "claim" | "poor" | "owned" | "equip" | "equipped" | "busy" | "gold"
local function paint(ab, kind, text)
    local b = ab.btn
    local showCheck = kind == "owned" or kind == "equipped"
    ab.check.Visible = showCheck
    ab.label.Text = text
    ab.stroke.Transparency = 1
    b.Active = true
    b.AutoButtonColor = false
    if kind == "buy" or kind == "claim" then
        b.BackgroundColor3 = T.money
        setBase(b, 0)
        ab.label.TextColor3 = T.bg
    elseif kind == "gold" then
        b.BackgroundColor3 = T.gold
        setBase(b, 0)
        ab.label.TextColor3 = T.bg
    elseif kind == "poor" then
        b.BackgroundColor3 = T.line
        setBase(b, 0.95)
        ab.label.TextColor3 = T.faint
        ab.stroke.Transparency = 0.92
    elseif kind == "owned" or kind == "equipped" then
        b.BackgroundColor3 = T.money
        setBase(b, 0.88)
        ab.label.TextColor3 = T.money
        for _, bar in ipairs(ab.checkBars) do bar.BackgroundColor3 = T.money end
        b.Active = false
    elseif kind == "equip" then
        b.BackgroundColor3 = T.line
        setBase(b, 0.9)
        ab.label.TextColor3 = T.text
        ab.stroke.Transparency = 0.8
    elseif kind == "busy" then
        b.BackgroundColor3 = T.line
        setBase(b, 0.92)
        ab.label.TextColor3 = T.muted
        b.Active = false
    end
end

-- ── build ──────────────────────────────────────────────────────────────
function ShopUI:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("ShopUI")
    if existing then existing:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "ShopUI"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 20
    screen.Enabled = false
    screen.Parent = playerGui

    -- dimmed backdrop: click to close; Modal frees the mouse in first person / shift-lock
    local backdrop = Instance.new("TextButton")
    backdrop.Name = "Backdrop"
    backdrop.Text = ""
    backdrop.AutoButtonColor = false
    backdrop.Modal = true
    backdrop.Selectable = false
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
    backdrop.BackgroundTransparency = 1
    backdrop.BorderSizePixel = 0
    backdrop.Parent = screen
    backdrop.Activated:Connect(function() self:close() end)

    -- fit wrapper (scales the whole modal on very small screens)
    local fit = frame({ Name = "Fit", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(W + 4, H + 4) })
    fit.Parent = screen
    local fitScale = Instance.new("UIScale")
    fitScale.Parent = fit

    -- fade group (2px inset so the panel's hairline stroke isn't clipped)
    local group = Instance.new("CanvasGroup")
    group.Name = "Group"
    group.Size = UDim2.fromScale(1, 1)
    group.BackgroundTransparency = 1
    group.GroupTransparency = 1
    group.Active = true
    group.Parent = fit
    local animScale = Instance.new("UIScale")
    animScale.Parent = group

    local panel = UITheme.panel({ Name = "Panel", Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4),
        transparency = 0.06, radius = 18, Active = true })
    panel.Parent = group

    -- header
    UITheme.caption("Safehouse", { Position = UDim2.fromOffset(24, 16), Size = UDim2.fromOffset(200, 14), TextSize = 12,
        TextColor3 = T.gold }).Parent = panel
    UITheme.label({ Text = "GEAR WALL", Position = UDim2.fromOffset(24, 30), Size = UDim2.fromOffset(300, 30),
        FontFace = UITheme.F.display, TextSize = 28 }).Parent = panel

    local close = Instance.new("TextButton")
    close.Name = "Close"
    close.Text = ""
    close.AutoButtonColor = false
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -18, 0, 18)
    close.Size = UDim2.fromOffset(38, 38)
    close.BackgroundColor3 = T.line
    close.BackgroundTransparency = 0.93
    close.BorderSizePixel = 0
    close.Parent = panel
    close:SetAttribute("BaseT", 0.93)
    UITheme.corner(close, 19)
    UITheme.stroke(close, T.line, 0.88)
    for _, rot in ipairs({ 45, -45 }) do
        local bar = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(2, 15), Rotation = rot, BackgroundColor3 = T.text, BackgroundTransparency = 0 })
        UITheme.corner(bar, 1)
        bar.Parent = close
    end
    hook(close, true)
    close.Activated:Connect(function() self:close() end)

    local cashPill = frame({ Name = "Cash", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -68, 0, 18),
        Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.money,
        BackgroundTransparency = 0.9 })
    UITheme.corner(cashPill, 19)
    UITheme.stroke(cashPill, T.money, 0.7)
    cashPill.Parent = panel
    local cpp = Instance.new("UIPadding")
    cpp.PaddingLeft, cpp.PaddingRight = UDim.new(0, 14), UDim.new(0, 16)
    cpp.Parent = cashPill
    list(cashPill, true, 8, nil, Enum.VerticalAlignment.Center)
    UITheme.caption("Cash", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38),
        TextSize = 12 }).Parent = cashPill
    local cash = UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38),
        FontFace = UITheme.F.display, TextSize = 19, TextColor3 = T.money, Text = "$0" })
    cash.Parent = cashPill

    -- tabs
    local tabRow = frame({ Name = "Tabs", Position = UDim2.fromOffset(24, 72), Size = UDim2.new(1, -48, 0, 34) })
    tabRow.Parent = panel
    list(tabRow, true, 8, nil, Enum.VerticalAlignment.Center)
    self._tabs = {}
    for i, t in ipairs(TABS) do
        local b = Instance.new("TextButton")
        b.Name = "Tab_" .. t.id
        b.LayoutOrder = i
        b.Text = ""
        b.AutoButtonColor = false
        b.BorderSizePixel = 0
        b.Size = UDim2.fromOffset(0, 34)
        b.AutomaticSize = Enum.AutomaticSize.X
        b.BackgroundColor3 = T.text
        b.Parent = tabRow
        UITheme.corner(b, 17)
        local st = UITheme.stroke(b, T.line, 0.86)
        local p = Instance.new("UIPadding")
        p.PaddingLeft, p.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)   -- (v2.0) 7 tabs now
        p.Parent = b
        list(b, true, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
        if t.id == "vip" then
            local dot = frame({ LayoutOrder = 0, Size = UDim2.fromOffset(6, 6), BackgroundColor3 = T.gold,
                BackgroundTransparency = 0 })
            UITheme.corner(dot, 3)
            dot.Parent = b
        end
        local l = UITheme.label({ LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34),
            Text = t.label, FontFace = UITheme.F.bold, TextSize = 13 })
        l.Parent = b
        hook(b, true)
        b.Activated:Connect(function() self:_selectTab(t.id) end)
        self._tabs[t.id] = { btn = b, label = l, stroke = st }
    end

    frame({ Name = "Divider", Position = UDim2.fromOffset(24, 116), Size = UDim2.new(1, -48, 0, 1),
        BackgroundColor3 = T.line, BackgroundTransparency = 0.9 }).Parent = panel

    -- pages
    local pages = frame({ Name = "Pages", Position = UDim2.fromOffset(24, 126), Size = UDim2.new(1, -48, 1, -126 - 50) })
    pages.Parent = panel
    self._pages = {}
    for _, t in ipairs(TABS) do
        local sf = Instance.new("ScrollingFrame")
        sf.Name = "Page_" .. t.id
        sf.Size = UDim2.fromScale(1, 1)
        sf.BackgroundTransparency = 1
        sf.BorderSizePixel = 0
        sf.ScrollBarThickness = 4
        sf.ScrollBarImageColor3 = T.line
        sf.ScrollBarImageTransparency = 0.7
        sf.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
        sf.CanvasSize = UDim2.new()
        sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
        sf.ScrollingDirection = Enum.ScrollingDirection.Y
        sf.Selectable = false
        sf.Visible = false
        sf.Parent = pages
        self._pages[t.id] = sf
    end

    -- footer
    frame({ Name = "FootLine", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -46),
        Size = UDim2.new(1, -48, 0, 1), BackgroundColor3 = T.line, BackgroundTransparency = 0.9 }).Parent = panel
    local feedback = UITheme.label({ Name = "Feedback", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -10),
        Size = UDim2.new(1, -170, 0, 30), FontFace = UITheme.F.bold, TextSize = 14, Text = "",
        TextTruncate = Enum.TextTruncate.AtEnd })
    feedback.Parent = panel
    local hint = UITheme.label({ Name = "Hint", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -10),
        Size = UDim2.fromOffset(140, 30), TextXAlignment = Enum.TextXAlignment.Right, RichText = true,
        FontFace = UITheme.F.bold, TextSize = 12, TextColor3 = T.muted, Text = "" })
    hint.Parent = panel

    self._screen, self._backdrop, self._fit, self._fitScale = screen, backdrop, fit, fitScale
    self._group, self._animScale, self._panel = group, animScale, panel
    self._cash, self._fbLabel, self._hint, self._close = cash, feedback, hint, close

    self:_buildGear()
    self:_buildMasks()
    self:_buildCodes()
    self:_buildVip()
    self:_buildCosmeticPlaceholders()
end

-- ── GEAR page ──────────────────────────────────────────────────────────
local function cardFrame(parent, order)
    local c = frame({ LayoutOrder = order, BackgroundColor3 = T.bgRaised, BackgroundTransparency = 0.35 })
    UITheme.corner(c, 14)
    UITheme.stroke(c, T.line, 0.9)
    UITheme.padding(c, 14, 14)
    c.Parent = parent
    return c
end

local function grid(parent, cols, height)
    local g = Instance.new("UIGridLayout")
    g.CellPadding = UDim2.fromOffset(12, 12)
    g.CellSize = UDim2.new(1 / cols, -math.ceil(12 * (cols - 1) / cols), 0, height)
    g.SortOrder = Enum.SortOrder.LayoutOrder
    g.Parent = parent
    -- a 2px inner margin keeps the card strokes clear of the scroll clip
    local p = Instance.new("UIPadding")
    p.PaddingLeft, p.PaddingRight = UDim.new(0, 2), UDim.new(0, 2)
    p.PaddingTop, p.PaddingBottom = UDim.new(0, 2), UDim.new(0, 2)
    p.Parent = parent
    return g
end

function ShopUI:_buildGear()
    local page = self._pages.gear
    grid(page, 3, 144)
    self._gearCards = {}
    for i, g in ipairs(Constants.GEAR) do
        local c = cardFrame(page, i)
        local tile = UITheme.label({ Size = UDim2.fromOffset(34, 34), Text = string.upper(g.name:sub(1, 1)),
            TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 16,
            TextColor3 = T.muted, BackgroundColor3 = T.line, BackgroundTransparency = 0.92 })
        UITheme.corner(tile, 9)
        tile.Parent = c
        UITheme.label({ Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -44, 0, 18), Text = g.name,
            FontFace = UITheme.F.bold, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd }).Parent = c
        UITheme.label({ Position = UDim2.fromOffset(44, 18), Size = UDim2.new(1, -44, 0, 16),
            Text = UITheme.money(g.price), FontFace = UITheme.F.medium, TextSize = 12, TextColor3 = T.muted }).Parent = c
        UITheme.label({ Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 34), Text = g.blurb or "",
            FontFace = UITheme.F.medium, TextSize = 13, TextColor3 = T.muted, TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd }).Parent = c
        local ab = actionButton(c, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 34) })
        ab.btn.Activated:Connect(function() self:_onGear(g) end)
        self._gearCards[g.id] = { ab = ab, tile = tile, def = g }
    end
end

-- ── MASKS page ─────────────────────────────────────────────────────────
function ShopUI:_buildMasks()
    local page = self._pages.masks
    grid(page, 4, 144)
    self._maskCards = {}
    for i, m in ipairs(Constants.MASKS) do
        local color = SWATCHES[((i - 1) % #SWATCHES) + 1]
        local c = cardFrame(page, i)
        c:FindFirstChildOfClass("UIPadding"):Destroy()
        UITheme.padding(c, 10, 10)

        -- glyph block: a stylised mask (rounded face + two eye slits) on a tinted plate
        local plate = frame({ Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = color, BackgroundTransparency = 0.86 })
        UITheme.corner(plate, 10)
        plate.Parent = c
        local face = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(46, 30), BackgroundColor3 = color, BackgroundTransparency = 0 })
        UITheme.corner(face, 15)
        face.Parent = plate
        local shade = Instance.new("UIGradient")
        shade.Rotation = 90
        shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 200))
        shade.Parent = face
        for _, x in ipairs({ 0.3, 0.7 }) do
            local eye = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.45),
                Size = UDim2.fromOffset(11, 6), BackgroundColor3 = T.bg, BackgroundTransparency = 0 })
            UITheme.corner(eye, 3)
            eye.Parent = face
        end

        UITheme.label({ Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 20), Text = string.upper(m.name),
            TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 15,
            TextTruncate = Enum.TextTruncate.AtEnd }).Parent = c
        UITheme.label({ Position = UDim2.fromOffset(0, 75), Size = UDim2.new(1, 0, 0, 14),
            Text = (m.price or 0) <= 0 and "FREE" or UITheme.money(m.price), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.medium, TextSize = 12, TextColor3 = T.muted }).Parent = c
        local ab = actionButton(c, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 30) })
        ab.btn.Activated:Connect(function() self:_onMask(m) end)
        self._maskCards[m.id] = { ab = ab, def = m }
    end
end

-- ── CODES page ─────────────────────────────────────────────────────────
function ShopUI:_buildCodes()
    local page = self._pages.codes
    local col = frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
    col.Parent = page
    list(col, false, 10, Enum.HorizontalAlignment.Center)
    local top = Instance.new("UIPadding")
    top.PaddingTop = UDim.new(0, 18)
    top.Parent = col

    UITheme.caption("Promo codes", { LayoutOrder = 1, Size = UDim2.fromOffset(420, 14), TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center }).Parent = col
    UITheme.label({ LayoutOrder = 2, Size = UDim2.fromOffset(420, 30), Text = "Got a code?",
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 26 }).Parent = col
    UITheme.label({ LayoutOrder = 3, Size = UDim2.fromOffset(420, 18), Text = "Each code pays out once. Caps don't matter.",
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.medium, TextSize = 14, TextColor3 = T.muted }).Parent = col

    local row = frame({ LayoutOrder = 4, Size = UDim2.new(0, 440, 0, 48) })
    row.Parent = col
    local box = Instance.new("TextBox")
    box.Name = "Code"
    box.Size = UDim2.new(1, -140, 1, 0)
    box.BackgroundColor3 = T.line
    box.BackgroundTransparency = 0.94
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.Text = ""
    box.PlaceholderText = "ENTER CODE"
    box.PlaceholderColor3 = T.faint
    box.TextColor3 = T.text
    box.FontFace = UITheme.F.mono
    box.TextSize = 18
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Parent = row
    UITheme.corner(box, 12)
    local boxStroke = UITheme.stroke(box, T.line, 0.86)
    UITheme.padding(box, 16, 0)
    box.Focused:Connect(function() tween(boxStroke, 0.15, { Color = T.info, Transparency = 0.35 }) end)
    box.FocusLost:Connect(function(enter)
        tween(boxStroke, 0.2, { Color = T.line, Transparency = 0.86 })
        if enter then self:_redeem() end
    end)
    box:GetPropertyChangedSignal("Text"):Connect(function()
        local up = string.upper(box.Text):gsub("%s", "")
        if #up > 24 then up = up:sub(1, 24) end
        if up ~= box.Text then box.Text = up end
    end)

    local ab = actionButton(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
        Size = UDim2.new(0, 128, 1, 0) })
    ab.btn.Activated:Connect(function() self:_redeem() end)

    local result = UITheme.label({ LayoutOrder = 5, Size = UDim2.fromOffset(440, 22), Text = "",
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextSize = 15 })
    result.Parent = col
    local redeemed = UITheme.label({ LayoutOrder = 6, Size = UDim2.fromOffset(440, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Text = "", TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, FontFace = UITheme.F.medium,
        TextSize = 12, TextColor3 = T.faint })
    redeemed.Parent = col

    self._code = { box = box, ab = ab, result = result, redeemed = redeemed }
end

-- ── VIP page ───────────────────────────────────────────────────────────
function ShopUI:_buildVip()
    local page = self._pages.vip
    local wrap = frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
    wrap.Parent = page
    list(wrap, false, 0, Enum.HorizontalAlignment.Center)
    local wp = Instance.new("UIPadding")
    wp.PaddingTop, wp.PaddingBottom = UDim.new(0, 10), UDim.new(0, 4)
    wp.Parent = wrap

    local card = frame({ Size = UDim2.fromOffset(460, 252), BackgroundColor3 = T.bgRaised, BackgroundTransparency = 0.3 })
    UITheme.corner(card, 16)
    UITheme.stroke(card, T.gold, 0.6)
    card.Parent = wrap
    local glow = Instance.new("UIGradient")
    glow.Rotation = 90
    glow.Color = ColorSequence.new(T.gold:Lerp(T.bgRaised, 0.82), T.bgRaised)
    glow.Parent = card
    local accent = frame({ Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -48, 0, 3), BackgroundColor3 = T.gold,
        BackgroundTransparency = 0 })
    UITheme.corner(accent, 2)
    accent.Parent = card

    UITheme.caption("VIP pass", { Position = UDim2.fromOffset(28, 22), Size = UDim2.new(1, -56, 0, 14), TextSize = 12,
        TextColor3 = T.gold }).Parent = card
    local title = UITheme.label({ Position = UDim2.fromOffset(28, 38), Size = UDim2.new(1, -56, 0, 34),
        FontFace = UITheme.F.display, TextSize = 30, Text = "Run it VIP" })
    title.Parent = card
    local perks = frame({ Position = UDim2.fromOffset(28, 84), Size = UDim2.new(1, -56, 0, 60) })
    perks.Parent = card
    list(perks, false, 8)
    for i, text in ipairs({ "+10% on every payout", "Gold name on the safehouse TV" }) do
        local r = frame({ LayoutOrder = i, Size = UDim2.new(1, 0, 0, 22) })
        r.Parent = perks
        local dot = frame({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(8, 8),
            BackgroundColor3 = T.gold, BackgroundTransparency = 0 })
        UITheme.corner(dot, 4)
        dot.Parent = r
        UITheme.label({ Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -20, 1, 0), Text = text,
            FontFace = UITheme.F.bold, TextSize = 16 }).Parent = r
    end
    local note = UITheme.label({ Position = UDim2.fromOffset(28, 150), Size = UDim2.new(1, -56, 0, 36), Text = "",
        FontFace = UITheme.F.medium, TextSize = 13, TextColor3 = T.muted, TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top })
    note.Parent = card
    local ab = actionButton(card, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 28, 1, -22),
        Size = UDim2.new(1, -56, 0, 40) })
    ab.btn.Activated:Connect(function() self:_onVip() end)

    self._vip = { title = title, note = note, ab = ab }
end

-- ── BAGS / CARS / TRAILS pages (v2.0 cosmetics) ────────────────────────
local COSMETIC_CATS = { bag = "Bag skins", car = "Car colors", trail = "Trails" }

local function c3(t, fallback)
    if type(t) == "table" and tonumber(t[1]) and tonumber(t[2]) and tonumber(t[3]) then
        return Color3.fromRGB(t[1], t[2], t[3])
    end
    return fallback
end

function ShopUI:_buildCosmeticPlaceholders()
    self._cosCards = {}
    self._cosLoading = {}
    for cat in pairs(COSMETIC_CATS) do
        local page = self._pages[cat]
        if page then
            self._cosLoading[cat] = UITheme.label({ Name = "Loading", Size = UDim2.new(1, 0, 0, 60),
                Text = "Loading...", TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
                TextSize = 16, TextColor3 = T.muted, Parent = page })
        end
    end
end

-- little picture on each card: a bag, a car, or a streak
local function cosmeticGlyph(plate, item)
    local col = c3(item.color, T.muted)
    if item.category == "bag" then
        local sack = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55),
            Size = UDim2.fromOffset(46, 28), BackgroundColor3 = col, BackgroundTransparency = 0 })
        UITheme.corner(sack, 9)
        UITheme.stroke(sack, T.line, 0.75)
        sack.Parent = plate
        local strap = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, 4, 0, 5), BackgroundColor3 = T.gold, BackgroundTransparency = 0.1 })
        UITheme.corner(strap, 2)
        strap.Parent = sack
        local handle = frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 2),
            Size = UDim2.fromOffset(18, 7), BackgroundTransparency = 1 })
        UITheme.stroke(handle, col, 0, 2)
        UITheme.corner(handle, 4)
        handle.Parent = sack
    elseif item.category == "car" then
        local body = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 3),
            Size = UDim2.fromOffset(66, 16), BackgroundColor3 = col, BackgroundTransparency = 0 })
        UITheme.corner(body, 6)
        body.Parent = plate
        local cabin = frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.45, 0, 0, 2),
            Size = UDim2.fromOffset(30, 10), BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.35), BackgroundTransparency = 0 })
        UITheme.corner(cabin, 5)
        cabin.Parent = body
        for _, x in ipairs({ 0.22, 0.78 }) do
            local wheel = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 1),
                Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(20, 20, 24), BackgroundTransparency = 0 })
            UITheme.corner(wheel, 6)
            UITheme.stroke(wheel, T.line, 0.7)
            wheel.Parent = body
        end
    else
        if not item.color then
            UITheme.label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(100, 20), Text = "NONE", TextXAlignment = Enum.TextXAlignment.Center,
                FontFace = UITheme.F.display, TextSize = 14, TextColor3 = T.faint, Parent = plate })
            return
        end
        local streak = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, -24, 0, 12), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0 })
        UITheme.corner(streak, 6)
        streak.Parent = plate
        local g = Instance.new("UIGradient")
        if item.rainbow then
            g.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
                ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 60)),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 230, 120)),
                ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 180, 255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 90, 255)),
            })
        else
            g.Color = ColorSequence.new(col, c3(item.color2, col))
        end
        g.Transparency = NumberSequence.new(0.9, 0)
        g.Parent = streak
    end
end

function ShopUI:_buildCosmetics(catalog)
    self._cosBuilt = true
    local byCat = { bag = {}, car = {}, trail = {} }
    for _, item in ipairs(catalog) do
        if type(item) == "table" and byCat[item.category] and type(item.id) == "string" then
            table.insert(byCat[item.category], item)
        end
    end
    for cat, items in pairs(byCat) do
        local page = self._pages[cat]
        if page then
            if self._cosLoading[cat] then self._cosLoading[cat]:Destroy() end
            grid(page, 3, 150)
            for i, item in ipairs(items) do
                local color = c3(item.color, T.muted)
                local c = cardFrame(page, i)
                c:FindFirstChildOfClass("UIPadding"):Destroy()
                UITheme.padding(c, 10, 10)
                local plate = frame({ Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = color, BackgroundTransparency = 0.86 })
                UITheme.corner(plate, 10)
                plate.Parent = c
                cosmeticGlyph(plate, item)
                if item.vipOnly or item.rewardOnly then
                    local tag = UITheme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 5),
                        Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X,
                        Text = item.vipOnly and "VIP" or "DAY 7", FontFace = UITheme.F.display, TextSize = 11,
                        TextColor3 = T.bg, BackgroundColor3 = T.gold, BackgroundTransparency = 0 })
                    UITheme.corner(tag, 8)
                    UITheme.padding(tag, 7, 0)
                    tag.Parent = plate
                end
                UITheme.label({ Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 20),
                    Text = string.upper(item.name or item.id), TextXAlignment = Enum.TextXAlignment.Center,
                    FontFace = UITheme.F.display, TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd }).Parent = c
                local sub = UITheme.label({ Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 14),
                    Text = item.blurb or "", TextXAlignment = Enum.TextXAlignment.Center,
                    FontFace = UITheme.F.medium, TextSize = 12, TextColor3 = T.muted, TextTruncate = Enum.TextTruncate.AtEnd })
                sub.Parent = c
                local ab = actionButton(c, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
                    Size = UDim2.new(1, 0, 0, 30) })
                ab.btn.Activated:Connect(function() self:_onCosmetic(item) end)
                self._cosCards[item.id] = { ab = ab, def = item }
            end
        end
    end
end

function ShopUI:_onCosmetic(item)
    if self._busy then return end
    local v = self:_view()
    local cos = v.cos
    if cos.equipped[item.category] == item.id then return end
    local action
    if cos.owned[item.id] then
        if item.vipOnly and not v.vip then
            self:_feedback("That one is for VIP players.", false)
            return
        end
        action = "equipCosmetic"
    else
        if item.rewardOnly then
            self:_feedback("Claim 7 daily rewards in a row to get " .. (item.name or "this") .. "!", false)
            return
        end
        if item.vipOnly and not v.vip then
            self:_feedback("That one is for VIP players. Check the VIP tab!", false)
            return
        end
        local price = tonumber(item.price) or 0
        if v.cash < price then
            self:_feedback(string.format("You need %s more for %s.", UITheme.money(price - v.cash), item.name or "that"), false)
            return
        end
        action = "buyCosmetic"
    end
    task.spawn(function()
        local res = self:_request(action, { id = item.id }, "cos:" .. item.id)
        if res then
            local fallback = action == "equipCosmetic" and ((item.name or "") .. " equipped") or ("Got " .. (item.name or "it"))
            self:_feedback(res.msg ~= "" and res.msg or (res.ok and fallback or "Couldn't do that."), res.ok == true)
            local card = self._cosCards[item.id]
            if res.ok and card then self:_popCard(card.ab.btn) end
        end
    end)
end

-- ── state + rendering ──────────────────────────────────────────────────
function ShopUI:_view()
    -- server state when we have it, live attributes on top (they're authoritative + instant)
    local s = self._state or {}
    local cashAttr = localPlayer:GetAttribute("Cash")
    local gear = toSet(s.gear)
    local attrGear = localPlayer:GetAttribute("Gear")
    if type(attrGear) == "string" then
        for id in attrGear:gmatch("[^,]+") do gear[id:match("^%s*(.-)%s*$")] = true end
    end
    local masks = toSet(s.masks)
    local mask = localPlayer:GetAttribute("Mask")
    if type(mask) ~= "string" or mask == "" then mask = s.mask end
    if mask then masks[mask] = true end
    -- v2.0 cosmetics: server state + the live BagSkin / CarColor / Trail attributes
    local sc = type(s.cosmetics) == "table" and s.cosmetics or {}
    local cos = { owned = toSet(sc.owned), equipped = {} }
    local eq = type(sc.equipped) == "table" and sc.equipped or {}
    for cat, attr in pairs({ bag = "BagSkin", car = "CarColor", trail = "Trail" }) do
        local a = localPlayer:GetAttribute(attr)
        cos.equipped[cat] = (type(a) == "string" and a ~= "") and a or eq[cat]
        if cos.equipped[cat] then cos.owned[cos.equipped[cat]] = true end
    end
    return {
        cos = cos,
        catalog = type(sc.catalog) == "table" and sc.catalog or nil,
        cash = tonumber(cashAttr) or tonumber(s.cash) or 0,
        gear = gear,
        masks = masks,
        mask = mask,
        vip = s.vip == true or localPlayer:GetAttribute("VIP") == true,
        vipPassId = tonumber(s.vipPassId) or tonumber(Constants.GAMEPASSES and Constants.GAMEPASSES.VIP) or 0,
        codes = toList(s.codesRedeemed),
        loaded = self._state ~= nil,
    }
end

function ShopUI:_render()
    if not self._screen then return end
    local v = self:_view()
    self._cash.Text = UITheme.money(v.cash)
    -- the silent state refresh on open doesn't lock the buttons visually
    local busy = self._busy and self._busyKey ~= "state"

    for id, card in pairs(self._gearCards) do
        local g = card.def
        if v.gear[id] then
            paint(card.ab, "owned", "OWNED")
            card.tile.TextColor3 = T.money
            card.tile.BackgroundColor3 = T.money
            card.tile.BackgroundTransparency = 0.86
        else
            card.tile.TextColor3 = T.muted
            card.tile.BackgroundColor3 = T.line
            card.tile.BackgroundTransparency = 0.92
            if busy then
                paint(card.ab, "busy", self._busyKey == "gear:" .. id and "BUYING..." or "BUY " .. UITheme.money(g.price))
            elseif v.cash >= g.price then
                paint(card.ab, "buy", "BUY " .. UITheme.money(g.price))
            else
                paint(card.ab, "poor", "BUY " .. UITheme.money(g.price))
            end
        end
    end

    for id, card in pairs(self._maskCards) do
        local m = card.def
        local price = m.price or 0
        if v.mask == id then
            paint(card.ab, "equipped", "EQUIPPED")
        elseif busy then
            local mine = self._busyKey == "mask:" .. id
            paint(card.ab, "busy", mine and "..." or (v.masks[id] and "EQUIP" or (price <= 0 and "CLAIM" or UITheme.money(price))))
        elseif v.masks[id] then
            paint(card.ab, "equip", "EQUIP")
        elseif price <= 0 then
            paint(card.ab, "claim", "CLAIM")
        elseif v.cash >= price then
            paint(card.ab, "buy", "BUY " .. UITheme.money(price))
        else
            paint(card.ab, "poor", UITheme.money(price))
        end
    end

    -- v2.0 cosmetics (pages are built the first time the catalog arrives)
    if not self._cosBuilt and v.catalog then
        self:_buildCosmetics(v.catalog)
    elseif not self._cosBuilt and v.loaded then
        for _, l in pairs(self._cosLoading or {}) do l.Text = "Coming soon!" end
    end
    for id, card in pairs(self._cosCards or {}) do
        local item = card.def
        local price = tonumber(item.price) or 0
        if v.cos.equipped[item.category] == id then
            paint(card.ab, "equipped", "EQUIPPED")
        elseif busy then
            paint(card.ab, "busy", self._busyKey == "cos:" .. id and "..." or (v.cos.owned[id] and "EQUIP" or UITheme.money(price)))
        elseif v.cos.owned[id] then
            if item.vipOnly and not v.vip then
                paint(card.ab, "poor", "VIP ONLY")
            else
                paint(card.ab, "equip", "EQUIP")
            end
        elseif item.rewardOnly then
            paint(card.ab, "poor", "DAILY REWARD")
        elseif item.vipOnly and not v.vip then
            paint(card.ab, "poor", "VIP ONLY")
        elseif price <= 0 then
            paint(card.ab, "claim", "CLAIM")
        elseif v.cash >= price then
            paint(card.ab, "buy", "BUY " .. UITheme.money(price))
        else
            paint(card.ab, "poor", UITheme.money(price))
        end
    end

    -- codes
    local code = self._code
    if busy then
        paint(code.ab, "busy", self._busyKey == "code" and "CHECKING..." or "REDEEM")
    else
        paint(code.ab, "buy", "REDEEM")
    end
    code.redeemed.Text = #v.codes > 0 and ("Already redeemed: " .. table.concat(v.codes, " · ")) or ""

    -- VIP
    local vip = self._vip
    if v.vip then
        vip.title.Text = "You're VIP"
        vip.note.Text = "Thanks for backing the crew. Your bonus applies to every payout automatically."
        vip.ab.btn.Visible = true
        paint(vip.ab, "owned", "OWNED")
    elseif v.vipPassId == 0 then
        vip.title.Text = "VIP coming soon"
        vip.note.Text = "The pass isn't on sale yet. It'll show up here the moment it is."
        vip.ab.btn.Visible = false
    else
        vip.title.Text = "Run it VIP"
        vip.note.Text = "One-time Roblox pass. Kept forever, on every server."
        vip.ab.btn.Visible = true
        local label = self._vipPrice and ("GET VIP  ·  R$ " .. tostring(self._vipPrice)) or "GET VIP"
        if self._vipPrompting then
            paint(vip.ab, "busy", "CHECK THE ROBLOX PROMPT")
        else
            paint(vip.ab, "gold", label)
        end
        self:_fetchVipPrice(v.vipPassId)
    end
end

function ShopUI:_fetchVipPrice(passId)
    if self._vipPriceFor == passId then return end
    self._vipPriceFor = passId
    task.spawn(function()
        local ok, info = pcall(function()
            return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
        end)
        if ok and type(info) == "table" and tonumber(info.PriceInRobux) then
            self._vipPrice = info.PriceInRobux
            if self._open then self:_render() end
        end
    end)
end

function ShopUI:_feedback(text, good)
    local fb = self._fbLabel
    local token = {}
    self._fbToken = token
    fb.Text = text or ""
    fb.TextColor3 = good and T.money or T.danger
    fb.TextTransparency = 1
    tween(fb, 0.2, { TextTransparency = 0 })
    task.delay(4, function()
        if self._fbToken == token then tween(fb, 0.5, { TextTransparency = 1 }) end
    end)
end

-- One ShopAction round-trip. Buttons lock while it's in flight; never hangs forever.
function ShopUI:_request(action, payload, busyKey)
    if self._busy then return nil end
    local remote = self._remote
    if not remote then
        local folder = ReplicatedStorage:FindFirstChild("Remotes")
        local r = folder and folder:FindFirstChild(Remotes.NAMES.ShopAction)
        if r and r:IsA("RemoteFunction") then
            remote = r
            self._remote = r
        end
    end
    if not remote then
        self:_feedback("The shop is offline right now. Try again in a moment.", false)
        return nil
    end

    self._busy, self._busyKey = true, busyKey
    if busyKey ~= "state" then self:_render() end

    local done, ok, res, timedOut = false, false, nil, false
    task.spawn(function()
        ok, res = pcall(function() return remote:InvokeServer(action, payload) end)
        done = true
        -- a late answer still carries fresh state
        if timedOut and ok and type(res) == "table" and type(res.state) == "table" then
            self._state = res.state
            self:_render()
        end
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < INVOKE_TIMEOUT do task.wait(0.05) end
    timedOut = not done

    self._busy, self._busyKey = false, nil
    if timedOut then
        self:_feedback("The shop didn't answer. Try again.", false)
        self:_render()
        return nil
    end
    if not ok or type(res) ~= "table" then
        self:_feedback("Couldn't reach the shop. Try again.", false)
        self:_render()
        return nil
    end
    if type(res.state) == "table" then self._state = res.state end
    self:_render()
    return res
end

-- ── actions ────────────────────────────────────────────────────────────
function ShopUI:_onGear(g)
    if self._busy then return end
    local v = self:_view()
    if v.gear[g.id] then return end
    if v.cash < g.price then
        self:_feedback(string.format("You need %s more for %s.", UITheme.money(g.price - v.cash), g.name), false)
        return
    end
    task.spawn(function()
        local res = self:_request("buyGear", { id = g.id }, "gear:" .. g.id)
        if res then
            self:_feedback(res.msg or (res.ok and ("Bought " .. g.name) or "Couldn't buy that."), res.ok == true)
            if res.ok then self:_popCard(self._gearCards[g.id].ab.btn) end
        end
    end)
end

function ShopUI:_onMask(m)
    if self._busy then return end
    local v = self:_view()
    if v.mask == m.id then return end
    local price = m.price or 0
    local action
    if v.masks[m.id] then
        action = "equipMask"
    else
        if v.cash < price then
            self:_feedback(string.format("You need %s more for %s.", UITheme.money(price - v.cash), m.name), false)
            return
        end
        action = "buyMask"
    end
    task.spawn(function()
        local res = self:_request(action, { id = m.id }, "mask:" .. m.id)
        if res then
            local fallback = action == "equipMask" and (m.name .. " equipped") or ("Got " .. m.name)
            self:_feedback(res.msg or (res.ok and fallback or "Couldn't do that."), res.ok == true)
            if res.ok then self:_popCard(self._maskCards[m.id].ab.btn) end
        end
    end)
end

function ShopUI:_redeem()
    if self._busy then return end
    local code = self._code
    local text = (code.box.Text or ""):gsub("%s", ""):upper()
    if text == "" then
        code.result.Text = "Type a code first."
        code.result.TextColor3 = T.danger
        return
    end
    task.spawn(function()
        local res = self:_request("redeemCode", { code = text }, "code")
        if not res then
            code.result.Text = "Couldn't reach the shop. Try again."
            code.result.TextColor3 = T.danger
            return
        end
        code.result.Text = res.msg or (res.ok and "Code redeemed!" or "That code didn't work.")
        code.result.TextColor3 = res.ok and T.money or T.danger
        code.result.TextTransparency = 1
        tween(code.result, 0.2, { TextTransparency = 0 })
        if res.ok then code.box.Text = "" end
    end)
end

function ShopUI:_onVip()
    local v = self:_view()
    if v.vip or v.vipPassId == 0 or self._vipPrompting then return end
    self._vipPrompting = true
    self:_render()
    local ok = pcall(function()
        MarketplaceService:PromptGamePassPurchase(localPlayer, v.vipPassId)
    end)
    if not ok then
        self._vipPrompting = false
        self:_feedback("Couldn't open the Roblox purchase prompt.", false)
        self:_render()
    end
end

function ShopUI:_popCard(btn)
    local s = btn:FindFirstChildOfClass("UIScale")
    if not s then return end
    s.Scale = 1.1
    tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- ── tabs ───────────────────────────────────────────────────────────────
function ShopUI:_selectTab(id, instant)
    self._tab = id
    for tid, t in pairs(self._tabs) do
        local on = tid == id
        local bgT = on and 0 or 1
        t.btn:SetAttribute("BaseT", bgT)
        if instant then
            t.btn.BackgroundTransparency = bgT
            t.label.TextColor3 = on and T.bg or T.muted
        else
            tween(t.btn, 0.18, { BackgroundTransparency = bgT })
            tween(t.label, 0.18, { TextColor3 = on and T.bg or T.muted })
        end
        t.stroke.Transparency = on and 1 or 0.86
    end
    for pid, page in pairs(self._pages) do
        local was = page.Visible
        page.Visible = pid == id
        if page.Visible and not was and not instant then
            page.CanvasPosition = Vector2.zero
        end
    end
end

-- ── layout (fit to screen) ─────────────────────────────────────────────
function ShopUI:_layout()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    local availW, availH = vp.X - 24, vp.Y - 24
    local fit = math.clamp(math.min(availW / MIN_W, availH / MIN_H), 0.55, 1)
    local w = math.clamp(availW / fit, MIN_W, W)
    local h = math.clamp(availH / fit, MIN_H, H)
    self._fit.Size = UDim2.fromOffset(math.floor(w) + 4, math.floor(h) + 4)
    self._fitScale.Scale = fit
end

function ShopUI:_renderHint(inputType)
    if GAMEPAD[inputType] then
        self._hint.Text = string.format('<font color="#%s">B</font>  CLOSE', T.text:ToHex())
    elseif inputType == Enum.UserInputType.Touch then
        self._hint.Text = ""
    else
        self._hint.Text = string.format('<font color="#%s">ESC</font>  CLOSE', T.text:ToHex())
    end
end

-- ── open / close ───────────────────────────────────────────────────────
function ShopUI:open()
    if not self._screen or self._open then return end
    self._open = true
    local token = {}
    self._animToken = token

    self:_layout()
    self:_selectTab(self._tab or "gear", true)
    self:_render()
    self._screen.Enabled = true
    self._group.GroupTransparency = 1
    self._animScale.Scale = 0.94
    tween(self._backdrop, 0.25, { BackgroundTransparency = 0.45 })
    tween(self._group, 0.22, { GroupTransparency = 0 })
    tween(self._animScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

    ContextActionService:BindAction(CLOSE_ACTION, function(_, state)
        if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
        self:close()
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)

    if GAMEPAD[UserInputService:GetLastInputType()] then
        GuiService.SelectedObject = self._tabs[self._tab or "gear"].btn
    end

    task.spawn(function()
        -- wait for any in-flight request to finish, then pull fresh state
        local t0 = os.clock()
        while self._busy and os.clock() - t0 < INVOKE_TIMEOUT do task.wait(0.1) end
        if self._open and self._animToken == token then
            local res = self:_request("getState", {}, "state")
            if res and res.ok == false and res.msg then self:_feedback(res.msg, false) end
        end
    end)
end

function ShopUI:close()
    if not self._open then return end
    self._open = false
    local token = {}
    self._animToken = token
    ContextActionService:UnbindAction(CLOSE_ACTION)
    local sel = GuiService.SelectedObject
    if sel and sel:IsDescendantOf(self._screen) then GuiService.SelectedObject = nil end
    self._code.box:ReleaseFocus()

    tween(self._backdrop, 0.2, { BackgroundTransparency = 1 })
    tween(self._animScale, 0.2, { Scale = 0.96 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local out = tween(self._group, 0.2, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    out.Completed:Connect(function()
        if self._animToken == token then self._screen.Enabled = false end
    end)
end

-- ── start ──────────────────────────────────────────────────────────────
function ShopUI:start()
    self:_buildUi()
    self:_selectTab("gear", true)
    self:_renderHint(UserInputService:GetLastInputType())

    ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if prompt.Name == "OpenShop" and player == localPlayer then self:open() end
    end)

    for _, attr in ipairs({ "Cash", "Gear", "Mask", "VIP", "BagSkin", "CarColor", "Trail" }) do
        localPlayer:GetAttributeChangedSignal(attr):Connect(function()
            if self._open then self:_render() end
        end)
    end

    UserInputService.LastInputTypeChanged:Connect(function(t)
        if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseWheel then return end
        self:_renderHint(t)
    end)

    local function watchViewport()
        local cam = workspace.CurrentCamera
        if cam then
            cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                if self._open then self:_layout() end
            end)
        end
    end
    watchViewport()
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
        if player ~= localPlayer then return end
        local v = self:_view()
        if passId ~= v.vipPassId then return end
        self._vipPrompting = false
        if purchased then
            self:_feedback("VIP unlocked. Welcome to the club.", true)
        end
        self:_render()
        if purchased then
            -- give the server a beat to see the pass, then refresh
            task.delay(1.5, function()
                if not self._busy then self:_request("getState", {}, "state") end
            end)
        end
    end)

    task.spawn(function()
        local r = Remotes.getRemote(Remotes.NAMES.ShopAction, "RemoteFunction")
        if r and r:IsA("RemoteFunction") then
            self._remote = r
        else
            warn("[HEIST CREW] ShopUI: ShopAction RemoteFunction missing — the shop will show as offline")
        end
    end)

    print("[HEIST CREW] ShopUI mounted ✅")
end

return ShopUI
