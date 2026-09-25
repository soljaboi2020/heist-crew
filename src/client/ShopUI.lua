--[[
    HEIST CREW — ShopUI  ("THE SHOP")
    ────────────────────────────────────────────────
    v1.0 (2026-09-25), v2.1 UI overhaul. The shop modal. Opens when the local
    player triggers a ProximityPrompt named "OpenShop"; closes with the X, a
    click on the dimmed backdrop, Escape, or gamepad B.

        THE VAULT                                   CASH $12,450   (X)
        THE SHOP   every mask = a different power
        [GEAR] (MASKS) (BAGS) (CARS) (TRAILS) (CASH) (CODES) (VIP)
        ─────────────────────────────────────────────────────
        picture cards / code box / VIP card
        ─────────────────────────────────────────────────────
        inline feedback                               ESC  CLOSE

    v2.1 — REAL PICTURES (target: docs/mockups/shop-masks-v2.png). Every item
    card is: a big picture on a glow in the item's colour, the name, a
    coloured ABILITY pill + one line of what it does (masks), and a price /
    EQUIPPED button. Pictures:
        masks  → ImageLabel "rbxthumb://type=Asset&id=<assetId>&w=420&h=420"
        bags   → ViewportFrame: a little duffel bag built from parts, in the
                 skin's colour + material (+ reflectance)
        cars   → ViewportFrame: a simple car body in the paint colour
        trails → a gradient streak in the trail's colours (rainbow for VIP)
    v2.2 — GEAR THAT DOES STUFF: bag / car / trail cards show their power
    like masks do (a coloured pill + one line, from catalog item.power):
    green pill = more cash (bags), blue = speed (trails / fast cars), gold =
    bust slower (tough cars). Car cards preview the REAL car type — a clone of
    ReplicatedStorage.HC_CarPreviews[<id>] (VehicleService publishes one model
    per type), falling back to the simple drawn car. Bag cards draw the bag at
    its tier's size (item.scale) with a SIZE tag.
    CASH tab (Robux → cash packs): state.robuxPacks {id, name, cash, robux,
    available}; buying calls ShopAction("buyRobuxPack", {id}) and the SERVER
    opens the Roblox prompt. available == false → greyed "COMING SOON".

    Talks to the ShopAction RemoteFunction:
        InvokeServer(action, payload) -> { ok, msg, state }
        actions: getState · buyGear{id} · buyMask{id} · equipMask{id} · redeemCode{code}
                 · buyCosmetic{id} · equipCosmetic{id} · buyRobuxPack{id}
        state  = { cash, gear = {...}, masks = {owned ids}, mask, vip, vipPassId, codesRedeemed = {...},
                   maskList = {{id, name, price, owned, equipped, ability = {id, name, desc}}}, maskPower,
                   robuxPacks = {{id, name, cash, robux, available}},
                   cosmetics = { catalog = {items}, owned = {ids}, equipped = {bag, car, trail} } }
                   (v2.2 catalog items also carry power = {name, desc}, carType, scale, size …)
    Masks fall back to Constants.MASKS (assetId + ability) for anything the
    server's maskList doesn't carry. BAGS / CARS / TRAILS / CASH pages are
    built the first time the server sends their data.
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
local I = UITheme.ICON

local ShopUI = {}
local localPlayer = Players.LocalPlayer

local W, H = 840, 580             -- design size (scaled with the HUD, shrunk to fit small screens)
local CLOSE_ACTION = "HC_ShopClose"
local INVOKE_TIMEOUT = 10
local PIC_H = 118                 -- picture area on an item card

local TABS = {
    { id = "gear",  label = "GEAR",   sub = "tools that make the job easier" },
    { id = "masks", label = "MASKS",  sub = "every mask = a different power" },
    { id = "bag",   label = "BAGS",   sub = "bigger bag = more cash per bag" },      -- v2.0 cosmetics (page id = category)
    { id = "car",   label = "CARS",   sub = "the crew drives the best car anyone has on" },
    { id = "trail", label = "TRAILS", sub = "every trail makes you faster" },
    { id = "cash",  label = "CASH",   sub = "cash packs for Robux" },
    { id = "codes", label = "CODES",  sub = "got a promo code?" },
    { id = "vip",   label = "VIP",    sub = "the VIP pass" },
}
local TAB_SUB = {}
for _, t in ipairs(TABS) do TAB_SUB[t.id] = t.sub end

-- mask card colours (the mockup's order)
local MASK_COLORS = {
    Color3.fromRGB(236, 72, 153), Color3.fromRGB(56, 189, 248), Color3.fromRGB(139, 92, 246),
    Color3.fromRGB(249, 115, 22), Color3.fromRGB(244, 114, 182), Color3.fromRGB(52, 211, 153),
    Color3.fromRGB(167, 139, 250), Color3.fromRGB(251, 191, 36),
}
local GEAR_ICON = { Sneakers = "👟", Lockpick = "🔓", Duffel = "🎒", Jammer = "📡", Thermal = "🥽" }
local GEAR_COLOR = { Sneakers = T.info, Lockpick = T.gold, Duffel = T.money, Jammer = T.purple, Thermal = T.danger }

local MASK_DEF = {}
for i, m in ipairs(Constants.MASKS or {}) do
    MASK_DEF[m.id] = m
    MASK_DEF[m.id]._order = i
end

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
    for k, v in pairs(props or {}) do (f :: any)[k] = v end
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

local function c3(t, fallback)
    if typeof(t) == "Color3" then return t end
    if type(t) == "table" and tonumber(t[1]) and tonumber(t[2]) and tonumber(t[3]) then
        return Color3.fromRGB(t[1], t[2], t[3])
    end
    return fallback
end

local function material(name, fallback)
    local ok, m = pcall(function() return (Enum.Material :: any)[name] end)
    if ok and typeof(m) == "EnumItem" then return m end
    return fallback or Enum.Material.SmoothPlastic
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
    local holder = frame({ Name = "Check", LayoutOrder = order or 0, Size = UDim2.fromOffset(16, 16) })
    local short = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(3, 6),
        Position = UDim2.fromOffset(5, 10), Rotation = -45, BackgroundColor3 = color, BackgroundTransparency = 0 })
    UITheme.corner(short, 1)
    short.Parent = holder
    local long = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(3, 11),
        Position = UDim2.fromOffset(9.8, 7.8), Rotation = 39, BackgroundColor3 = color, BackgroundTransparency = 0 })
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
        tween(scale, 0.12, { Scale = 1.04 })
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

-- A chunky action button with a centred [check] LABEL row.
local function actionButton(parent, props)
    local btn = Instance.new("TextButton")
    btn.Name = "Action"
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.BackgroundColor3 = T.bgRaised
    btn.Selectable = true
    for k, v in pairs(props or {}) do (btn :: any)[k] = v end
    UITheme.corner(btn, 12)
    local stroke = UITheme.stroke(btn, T.line, 1, 1.5)
    local row = frame({ Size = UDim2.fromScale(1, 1) })
    row.Parent = btn
    list(row, true, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
    local check, bars = makeCheck(row, T.bgDeep, 1)
    local label = UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
        FontFace = UITheme.F.display, TextSize = 17, TextColor3 = T.text })
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
    if kind == "buy" then
        -- affordable price: slate button, white price, green rim (mockup)
        b.BackgroundColor3 = T.bgRaised:Lerp(T.line, 0.08)
        setBase(b, 0)
        ab.label.TextColor3 = T.text
        ab.stroke.Color = T.money
        ab.stroke.Transparency = 0.35
    elseif kind == "claim" then
        b.BackgroundColor3 = T.money
        setBase(b, 0)
        ab.label.TextColor3 = T.bgDeep
    elseif kind == "gold" then
        b.BackgroundColor3 = T.gold
        setBase(b, 0)
        ab.label.TextColor3 = T.bgDeep
    elseif kind == "poor" then
        b.BackgroundColor3 = T.bgRaised
        setBase(b, 0.35)
        ab.label.TextColor3 = T.faint
    elseif kind == "owned" or kind == "equipped" then
        b.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
        setBase(b, 0)
        ab.label.TextColor3 = T.bgDeep
        for _, bar in ipairs(ab.checkBars) do bar.BackgroundColor3 = T.bgDeep end
        b.Active = false
    elseif kind == "equip" then
        b.BackgroundColor3 = T.line
        setBase(b, 0.9)
        ab.label.TextColor3 = T.text
        ab.stroke.Color = T.line
        ab.stroke.Transparency = 0.5
    elseif kind == "busy" then
        b.BackgroundColor3 = T.line
        setBase(b, 0.92)
        ab.label.TextColor3 = T.muted
        b.Active = false
    end
end

-- ── pictures ───────────────────────────────────────────────────────────
-- The item card: colour-rimmed card, glow picture area on top, name, pill, desc, button.
-- Returns { card, pic, name, pill, pillLabel, desc, ab }
local function itemCard(parent, order, color)
    local c = frame({ Name = "Item", LayoutOrder = order, BackgroundColor3 = T.bg, BackgroundTransparency = 0.05 })
    UITheme.corner(c, 16)
    UITheme.stroke(c, color, 0.1, 2)
    c.ClipsDescendants = false
    c.Parent = parent

    -- picture area: colour glow fading down into the card
    local pic = frame({ Name = "Picture", Size = UDim2.new(1, 0, 0, PIC_H), BackgroundColor3 = color,
        BackgroundTransparency = 0, ClipsDescendants = true })
    UITheme.corner(pic, 16)
    pic.Parent = c
    local pg = Instance.new("UIGradient")
    pg.Rotation = 90
    pg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.55),
        NumberSequenceKeypoint.new(0.7, 0.8),
        NumberSequenceKeypoint.new(1, 1),
    })
    pg.Parent = pic
    -- a soft round glow behind the picture
    for i, sz in ipairs({ 0.95, 0.62 }) do
        local glow = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
            Size = UDim2.new(0, PIC_H * sz, 0, PIC_H * sz), BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.25),
            BackgroundTransparency = i == 1 and 0.86 or 0.78 })
        UITheme.corner(glow, PIC_H)
        glow.Parent = pic
    end

    local name = UITheme.label({ Name = "Name", Position = UDim2.fromOffset(8, PIC_H + 4), Size = UDim2.new(1, -16, 0, 24),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 19,
        TextTruncate = Enum.TextTruncate.AtEnd })
    name.Parent = c

    local pill = frame({ Name = "Pill", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, PIC_H + 30),
        Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = color,
        BackgroundTransparency = 0, Visible = false })
    UITheme.corner(pill, 11)
    UITheme.padding(pill, 12, 0)
    pill.Parent = c
    local pillLabel = UITheme.label({ Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X,
        FontFace = UITheme.F.display, TextSize = 12, TextColor3 = T.bgDeep, TextXAlignment = Enum.TextXAlignment.Center })
    pillLabel.Parent = pill

    local desc = UITheme.label({ Name = "Desc", Position = UDim2.fromOffset(10, PIC_H + 56), Size = UDim2.new(1, -20, 0, 34),
        TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
        FontFace = UITheme.F.medium, TextSize = 14, TextColor3 = T.muted, TextTruncate = Enum.TextTruncate.AtEnd })
    desc.Parent = c

    local ab = actionButton(c, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10),
        Size = UDim2.new(1, -24, 0, 38) })
    return { card = c, pic = pic, name = name, pill = pill, pillLabel = pillLabel, desc = desc, ab = ab }
end

-- no pill? move the description up into its place
local function setPill(ic, text, color)
    if text and text ~= "" then
        ic.pill.Visible = true
        ic.pillLabel.Text = string.upper(text)
        if color then ic.pill.BackgroundColor3 = color end
        ic.desc.Position = UDim2.fromOffset(10, PIC_H + 56)
    else
        ic.pill.Visible = false
        ic.desc.Position = UDim2.fromOffset(10, PIC_H + 32)
    end
end

-- a ViewportFrame inside the picture area, with its own camera looking at `model`
local function viewport(pic, model, camFrom, lookAt, fov)
    local vf = Instance.new("ViewportFrame")
    vf.Name = "View"
    vf.AnchorPoint = Vector2.new(0.5, 0.5)
    vf.Position = UDim2.fromScale(0.5, 0.52)
    vf.Size = UDim2.new(1, -8, 1, -8)
    vf.BackgroundTransparency = 1
    vf.Ambient = Color3.fromRGB(150, 150, 165)
    vf.LightColor = Color3.fromRGB(255, 250, 240)
    vf.LightDirection = Vector3.new(-0.6, -1, -0.4)
    vf.Parent = pic
    local cam = Instance.new("Camera")
    cam.FieldOfView = fov or 32
    cam.CFrame = CFrame.lookAt(camFrom, lookAt)
    cam.Parent = vf
    vf.CurrentCamera = cam
    model.Parent = vf
    return vf
end

local function part(props)
    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.CastShadow = false
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    for k, v in pairs(props) do (p :: any)[k] = v end
    return p
end

-- a duffel bag (≈ 3 x 1.6 x 1.6 studs) in the skin's look, scaled to its tier (v2.2)
local function bagModel(item)
    local m = nil
    local k = math.clamp(tonumber(item.scale) or 1, 0.5, 2)
    local col = c3(item.color, Color3.fromRGB(28, 30, 36))
    local mat = material(item.material, Enum.Material.Fabric)
    local refl = tonumber(item.reflectance) or 0
    m = Instance.new("Model")
    m.Name = "Bag"
    local body = part({ Name = "Body", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 1.6, 1.6),
        Color = col, Material = mat, Reflectance = refl, CFrame = CFrame.new(0, 0.8, 0) })
    body.Parent = m
    -- zip line + two straps + handles (dark trim)
    local trim = col:Lerp(Color3.new(0, 0, 0), 0.55)
    part({ Name = "Zip", Size = Vector3.new(2.7, 0.08, 0.14), Color = T.gold, Material = Enum.Material.Metal,
        CFrame = CFrame.new(0, 1.62, 0) }).Parent = m
    for _, x in ipairs({ -0.75, 0.75 }) do
        part({ Name = "Strap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.22, 1.7, 1.7), Color = trim,
            Material = Enum.Material.Fabric, CFrame = CFrame.new(x, 0.8, 0) }).Parent = m
        part({ Name = "Handle", Size = Vector3.new(0.18, 0.55, 0.18), Color = trim, Material = Enum.Material.Fabric,
            CFrame = CFrame.new(x, 1.85, 0) }).Parent = m
    end
    part({ Name = "HandleTop", Size = Vector3.new(1.68, 0.16, 0.18), Color = trim, Material = Enum.Material.Fabric,
        CFrame = CFrame.new(0, 2.1, 0) }).Parent = m
    -- end caps
    for _, x in ipairs({ -1.52, 1.52 }) do
        part({ Name = "Cap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 1.3, 1.3), Color = trim,
            Material = mat, CFrame = CFrame.new(x, 0.8, 0) }).Parent = m
    end
    if k ~= 1 then
        pcall(function() m:ScaleTo(k) end)   -- scales about the pivot (the model's centre)
        pcall(function() m:PivotTo(m:GetPivot() + Vector3.new(0, (k - 1) * 1.05, 0)) end)
    end
    return m
end

-- (v2.2) the REAL car type for the card: a clone of VehicleService's preview
-- model, framed by its bounding box. nil if the previews aren't there (yet).
local function realCarPreview(pic, item)
    local folder = ReplicatedStorage:FindFirstChild("HC_CarPreviews")
    local src = folder and folder:FindFirstChild(tostring(item.id))
    if not src then return nil end
    local m = src:Clone()
    local cf, size = m:GetBoundingBox()
    local target = cf.Position
    local fov = 38
    local radius = size.Magnitude / 2
    local dist = radius / math.tan(math.rad(fov / 2)) * 0.82
    local dir = Vector3.new(-0.62, 0.42, -0.66).Unit    -- front-left, a little above (front = -Z)
    return viewport(pic, m, target + dir * dist, target, fov)
end

-- a simple car (≈ 8 x 3 x 4) painted in the item's colour
local function carModel(item)
    local col = c3(item.color, Color3.fromRGB(242, 242, 238))
    local mat = material(item.material, Enum.Material.SmoothPlastic)
    local refl = tonumber(item.reflectance) or 0.1
    local m = Instance.new("Model")
    m.Name = "Car"
    part({ Name = "Body", Size = Vector3.new(8, 1.3, 3.8), Color = col, Material = mat, Reflectance = refl,
        CFrame = CFrame.new(0, 1.15, 0) }).Parent = m
    part({ Name = "Hood", Shape = Enum.PartType.Block, Size = Vector3.new(2.2, 0.35, 3.6), Color = col, Material = mat,
        Reflectance = refl, CFrame = CFrame.new(-2.8, 1.95, 0) }).Parent = m
    part({ Name = "Cabin", Size = Vector3.new(3.8, 1.1, 3.4), Color = col:Lerp(Color3.new(0, 0, 0), 0.15), Material = mat,
        Reflectance = refl, CFrame = CFrame.new(0.5, 2.3, 0) }).Parent = m
    part({ Name = "Glass", Size = Vector3.new(3.9, 0.8, 3.5), Color = Color3.fromRGB(40, 60, 80),
        Material = Enum.Material.Glass, Transparency = 0.15, CFrame = CFrame.new(0.5, 2.3, 0) }).Parent = m
    for _, x in ipairs({ -2.6, 2.6 }) do
        for _, z in ipairs({ -1.85, 1.85 }) do
            part({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 1.5, 1.5),
                Color = Color3.fromRGB(22, 22, 26), Material = Enum.Material.SmoothPlastic,
                CFrame = CFrame.new(x, 0.75, z) * CFrame.Angles(0, math.rad(90), 0) }).Parent = m
        end
    end
    for _, z in ipairs({ -1.3, 1.3 }) do
        part({ Name = "Light", Size = Vector3.new(0.12, 0.3, 0.7), Color = Color3.fromRGB(255, 244, 200),
            Material = Enum.Material.Neon, CFrame = CFrame.new(-4.02, 1.4, z) }).Parent = m
    end
    return m
end

-- trail preview: a fat gradient streak with a few sparkle dots
local function trailPicture(pic, item)
    if not item.color then
        UITheme.label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(140, 30), Text = "NO TRAIL", TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.display, TextSize = 20, TextColor3 = T.faint, Parent = pic })
        return
    end
    local col = c3(item.color, T.muted)
    local col2 = c3(item.color2, col)
    local seq
    if item.rainbow then
        seq = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
            ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 60)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 230, 120)),
            ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 180, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 90, 255)),
        })
    else
        seq = ColorSequence.new(col, col2)
    end
    for i, spec in ipairs({ { y = 0.4, h = 22, r = -8 }, { y = 0.62, h = 12, r = -8 } }) do
        local streak = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, spec.y),
            Size = UDim2.new(0.86, 0, 0, spec.h), Rotation = spec.r, BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0 })
        UITheme.corner(streak, spec.h)
        streak.Parent = pic
        local g = Instance.new("UIGradient")
        g.Color = seq
        g.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.35, i == 1 and 0.25 or 0.55),
            NumberSequenceKeypoint.new(1, 0),
        })
        g.Parent = streak
    end
    for k = 1, 5 do
        local d = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.18 + k * 0.13, 0.25 + (k % 2) * 0.5),
            Size = UDim2.fromOffset(5, 5), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.3 })
        UITheme.corner(d, 3)
        d.Parent = pic
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

    -- fit wrapper (scales the whole modal with the HUD, and down on small screens)
    local fit = frame({ Name = "Fit", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(W + 6, H + 6) })
    fit.Parent = screen
    local fitScale = Instance.new("UIScale")
    fitScale.Parent = fit

    -- fade group (3px inset so the panel's outline isn't clipped)
    local group = Instance.new("CanvasGroup")
    group.Name = "Group"
    group.Size = UDim2.fromScale(1, 1)
    group.BackgroundTransparency = 1
    group.GroupTransparency = 1
    group.Active = true
    group.Parent = fit
    local animScale = Instance.new("UIScale")
    animScale.Parent = group

    local panel = UITheme.card({ Name = "Panel", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6),
        transparency = 0.02, radius = 22, Active = true })
    panel.Parent = group

    -- header
    UITheme.caption("The Vault", { Position = UDim2.fromOffset(26, 16), Size = UDim2.fromOffset(200, 14),
        TextColor3 = T.gold }).Parent = panel
    local titleRow = frame({ Position = UDim2.fromOffset(24, 28), Size = UDim2.fromOffset(520, 40) })
    titleRow.Parent = panel
    list(titleRow, true, 12, nil, Enum.VerticalAlignment.Bottom)
    UITheme.label({ LayoutOrder = 1, Text = "THE SHOP", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40),
        FontFace = UITheme.F.display, TextSize = 36 }).Parent = titleRow
    local tabSub = UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32),
        FontFace = UITheme.F.medium, TextSize = 17, TextColor3 = T.muted, Text = "" })
    tabSub.Parent = titleRow

    local close = Instance.new("TextButton")
    close.Name = "Close"
    close.Text = ""
    close.AutoButtonColor = false
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -18, 0, 18)
    close.Size = UDim2.fromOffset(42, 42)
    close.BackgroundColor3 = T.line
    close.BackgroundTransparency = 0.9
    close.BorderSizePixel = 0
    close.Parent = panel
    close:SetAttribute("BaseT", 0.9)
    UITheme.corner(close, 21)
    UITheme.stroke(close, T.line, 0.8)
    for _, rot in ipairs({ 45, -45 }) do
        local bar = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(3, 17), Rotation = rot, BackgroundColor3 = T.text, BackgroundTransparency = 0 })
        UITheme.corner(bar, 1)
        bar.Parent = close
    end
    hook(close, true)
    close.Activated:Connect(function() self:close() end)

    local cashPill = frame({ Name = "Cash", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -72, 0, 18),
        Size = UDim2.fromOffset(0, 42), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.money,
        BackgroundTransparency = 0.88 })
    UITheme.corner(cashPill, 21)
    UITheme.stroke(cashPill, T.money, 0.45, 1.5)
    cashPill.Parent = panel
    local cpp = Instance.new("UIPadding")
    cpp.PaddingLeft, cpp.PaddingRight = UDim.new(0, 6), UDim.new(0, 16)
    cpp.Parent = cashPill
    list(cashPill, true, 8, nil, Enum.VerticalAlignment.Center)
    UITheme.badge(I.cash, T.money, 32, { LayoutOrder = 1 }).Parent = cashPill
    local cash = UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 42),
        FontFace = UITheme.F.display, TextSize = 22, TextColor3 = T.money, Text = "$0" })
    cash.Parent = cashPill

    -- tabs
    local tabRow = frame({ Name = "Tabs", Position = UDim2.fromOffset(24, 80), Size = UDim2.new(1, -48, 0, 38) })
    tabRow.Parent = panel
    list(tabRow, true, 7, nil, Enum.VerticalAlignment.Center)
    self._tabs = {}
    for i, t in ipairs(TABS) do
        local b = Instance.new("TextButton")
        b.Name = "Tab_" .. t.id
        b.LayoutOrder = i
        b.Text = ""
        b.AutoButtonColor = false
        b.BorderSizePixel = 0
        b.Size = UDim2.fromOffset(0, 38)
        b.AutomaticSize = Enum.AutomaticSize.X
        b.BackgroundColor3 = T.gold
        b.Parent = tabRow
        UITheme.corner(b, 19)
        local st = UITheme.stroke(b, T.line, 0.82, 1.5)
        local p = Instance.new("UIPadding")
        p.PaddingLeft, p.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
        p.Parent = b
        list(b, true, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
        if t.id == "vip" or t.id == "cash" then
            local dot = frame({ LayoutOrder = 0, Size = UDim2.fromOffset(7, 7), BackgroundColor3 = T.gold,
                BackgroundTransparency = 0 })
            UITheme.corner(dot, 4)
            dot.Parent = b
        end
        local l = UITheme.label({ LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38),
            Text = t.label, FontFace = UITheme.F.display, TextSize = 15 })
        l.Parent = b
        hook(b, true)
        b.Activated:Connect(function() self:_selectTab(t.id) end)
        self._tabs[t.id] = { btn = b, label = l, stroke = st }
    end

    frame({ Name = "Divider", Position = UDim2.fromOffset(24, 128), Size = UDim2.new(1, -48, 0, 1),
        BackgroundColor3 = T.line, BackgroundTransparency = 0.88 }).Parent = panel

    -- pages
    local pages = frame({ Name = "Pages", Position = UDim2.fromOffset(20, 138), Size = UDim2.new(1, -40, 1, -138 - 52) })
    pages.Parent = panel
    self._pages = {}
    for _, t in ipairs(TABS) do
        local sf = Instance.new("ScrollingFrame")
        sf.Name = "Page_" .. t.id
        sf.Size = UDim2.fromScale(1, 1)
        sf.BackgroundTransparency = 1
        sf.BorderSizePixel = 0
        sf.ScrollBarThickness = 6
        sf.ScrollBarImageColor3 = T.line
        sf.ScrollBarImageTransparency = 0.6
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
    frame({ Name = "FootLine", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -48),
        Size = UDim2.new(1, -48, 0, 1), BackgroundColor3 = T.line, BackgroundTransparency = 0.88 }).Parent = panel
    local feedback = UITheme.label({ Name = "Feedback", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -10),
        Size = UDim2.new(1, -190, 0, 34), FontFace = UITheme.F.bold, TextSize = 16, Text = "",
        TextTruncate = Enum.TextTruncate.AtEnd })
    feedback.Parent = panel
    local hint = UITheme.label({ Name = "Hint", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -10),
        Size = UDim2.fromOffset(150, 34), TextXAlignment = Enum.TextXAlignment.Right, RichText = true,
        FontFace = UITheme.F.bold, TextSize = 13, TextColor3 = T.muted, Text = "" })
    hint.Parent = panel

    self._screen, self._backdrop, self._fit, self._fitScale = screen, backdrop, fit, fitScale
    self._group, self._animScale, self._panel = group, animScale, panel
    self._cash, self._fbLabel, self._hint, self._close, self._tabSub = cash, feedback, hint, close, tabSub

    self:_buildGear()
    self:_buildMasks()
    self:_buildCodes()
    self:_buildVip()
    self:_buildPlaceholders()
end

local function grid(parent, cols, height)
    local g = Instance.new("UIGridLayout")
    g.CellPadding = UDim2.fromOffset(14, 14)
    g.CellSize = UDim2.new(1 / cols, -math.ceil(14 * (cols - 1) / cols), 0, height)
    g.SortOrder = Enum.SortOrder.LayoutOrder
    g.Parent = parent
    -- a small inner margin keeps the card outlines clear of the scroll clip
    local p = Instance.new("UIPadding")
    p.PaddingLeft, p.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
    p.PaddingTop, p.PaddingBottom = UDim.new(0, 4), UDim.new(0, 6)
    p.Parent = parent
    return g
end

-- ── GEAR page ──────────────────────────────────────────────────────────
function ShopUI:_buildGear()
    local page = self._pages.gear
    grid(page, 3, 250)
    self._gearCards = {}
    for i, g in ipairs(Constants.GEAR) do
        local color = GEAR_COLOR[g.id] or T.gold
        local ic = itemCard(page, i, color)
        local b = UITheme.badge(GEAR_ICON[g.id] or string.upper(g.name:sub(1, 1)), color, 76)
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Position = UDim2.fromScale(0.5, 0.52)
        b.BackgroundColor3 = T.bgDeep
        b.BackgroundTransparency = 0.3
        b.Parent = ic.pic
        ic.name.Text = string.upper(g.name)
        setPill(ic, nil)
        ic.desc.Text = g.blurb or ""
        ic.ab.btn.Activated:Connect(function() self:_onGear(g) end)
        self._gearCards[g.id] = { ab = ic.ab, def = g }
    end
end

-- ── MASKS page ─────────────────────────────────────────────────────────
function ShopUI:_buildMasks()
    local page = self._pages.masks
    grid(page, 4, 262)
    self._maskCards = {}
    for i, m in ipairs(Constants.MASKS) do
        local color = MASK_COLORS[((i - 1) % #MASK_COLORS) + 1]
        local ic = itemCard(page, i, color)
        local img = Instance.new("ImageLabel")
        img.Name = "Thumb"
        img.AnchorPoint = Vector2.new(0.5, 0.5)
        img.Position = UDim2.fromScale(0.5, 0.52)
        img.Size = UDim2.fromOffset(PIC_H - 8, PIC_H - 8)
        img.BackgroundTransparency = 1
        img.ScaleType = Enum.ScaleType.Fit
        img.Image = m.assetId and ("rbxthumb://type=Asset&id=" .. tostring(m.assetId) .. "&w=420&h=420") or ""
        img.Parent = ic.pic
        ic.name.Text = string.upper(m.name)
        self._maskCards[m.id] = { ab = ic.ab, def = m, ic = ic, color = color }
        self:_paintMaskInfo(m.id, nil)
        ic.ab.btn.Activated:Connect(function() self:_onMask(m) end)
    end
end

-- ability pill + description (server maskList row wins, then Constants.MASKS)
function ShopUI:_paintMaskInfo(id, row)
    local card = self._maskCards[id]
    if not card then return end
    local def = MASK_DEF[id] or card.def
    local ab = (row and type(row.ability) == "table" and row.ability) or (type(def.ability) == "table" and def.ability) or nil
    if ab and ab.name then
        setPill(card.ic, tostring(ab.name), card.color)
        card.ic.desc.Text = tostring(ab.desc or "")
    else
        setPill(card.ic, nil)
        card.ic.desc.Text = (def.price or 0) <= 0 and "Free for everyone" or ""
    end
end

-- ── CODES page ─────────────────────────────────────────────────────────
function ShopUI:_buildCodes()
    local page = self._pages.codes
    local col = frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
    col.Parent = page
    list(col, false, 12, Enum.HorizontalAlignment.Center)
    local top = Instance.new("UIPadding")
    top.PaddingTop = UDim.new(0, 30)
    top.Parent = col

    UITheme.badge("🎟", T.gold, 64, { LayoutOrder = 0 }).Parent = col
    UITheme.label({ LayoutOrder = 2, Size = UDim2.fromOffset(460, 34), Text = "Got a code?",
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 30 }).Parent = col
    UITheme.label({ LayoutOrder = 3, Size = UDim2.fromOffset(460, 20), Text = "Each code pays out once. Caps don't matter.",
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.medium, TextSize = 16, TextColor3 = T.muted }).Parent = col

    local row = frame({ LayoutOrder = 4, Size = UDim2.new(0, 480, 0, 52) })
    row.Parent = col
    local box = Instance.new("TextBox")
    box.Name = "Code"
    box.Size = UDim2.new(1, -150, 1, 0)
    box.BackgroundColor3 = T.bgRaised
    box.BackgroundTransparency = 0.1
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.Text = ""
    box.PlaceholderText = "ENTER CODE"
    box.PlaceholderColor3 = T.faint
    box.TextColor3 = T.text
    box.FontFace = UITheme.F.mono
    box.TextSize = 20
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Parent = row
    UITheme.corner(box, 14)
    local boxStroke = UITheme.stroke(box, T.line, 0.8, 1.5)
    UITheme.padding(box, 16, 0)
    box.Focused:Connect(function() tween(boxStroke, 0.15, { Color = T.info, Transparency = 0.2 }) end)
    box.FocusLost:Connect(function(enter)
        tween(boxStroke, 0.2, { Color = T.line, Transparency = 0.8 })
        if enter then self:_redeem() end
    end)
    box:GetPropertyChangedSignal("Text"):Connect(function()
        local up = string.upper(box.Text):gsub("%s", "")
        if #up > 24 then up = up:sub(1, 24) end
        if up ~= box.Text then box.Text = up end
    end)

    local ab = actionButton(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
        Size = UDim2.new(0, 138, 1, 0) })
    ab.btn.Activated:Connect(function() self:_redeem() end)

    local result = UITheme.label({ LayoutOrder = 5, Size = UDim2.fromOffset(480, 24), Text = "",
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextSize = 17 })
    result.Parent = col
    local redeemed = UITheme.label({ LayoutOrder = 6, Size = UDim2.fromOffset(480, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Text = "", TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, FontFace = UITheme.F.medium,
        TextSize = 14, TextColor3 = T.faint })
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
    wp.PaddingTop, wp.PaddingBottom = UDim.new(0, 14), UDim.new(0, 6)
    wp.Parent = wrap

    local card = frame({ Size = UDim2.fromOffset(500, 300), BackgroundColor3 = T.bgRaised, BackgroundTransparency = 0.2 })
    UITheme.corner(card, 20)
    UITheme.stroke(card, T.gold, 0.2, 2)
    card.Parent = wrap
    local glow = Instance.new("UIGradient")
    glow.Rotation = 90
    glow.Color = ColorSequence.new(T.gold:Lerp(T.bgRaised, 0.7), T.bgRaised)
    glow.Parent = card

    local crown = UITheme.badge("👑", T.gold, 64)
    crown.Position = UDim2.fromOffset(28, 24)
    crown.Parent = card
    UITheme.caption("VIP pass", { Position = UDim2.fromOffset(106, 30), Size = UDim2.new(1, -134, 0, 14),
        TextColor3 = T.gold }).Parent = card
    local title = UITheme.label({ Position = UDim2.fromOffset(106, 46), Size = UDim2.new(1, -134, 0, 38),
        FontFace = UITheme.F.display, TextSize = 32, Text = "Run it VIP" })
    title.Parent = card
    local perks = frame({ Position = UDim2.fromOffset(30, 104), Size = UDim2.new(1, -60, 0, 64) })
    perks.Parent = card
    list(perks, false, 8)
    for i, text in ipairs({ "+10% on every payout", "VIP-only bag, car paint + rainbow trail" }) do
        local r = frame({ LayoutOrder = i, Size = UDim2.new(1, 0, 0, 26) })
        r.Parent = perks
        local dot = frame({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(10, 10),
            BackgroundColor3 = T.gold, BackgroundTransparency = 0 })
        UITheme.corner(dot, 5)
        dot.Parent = r
        UITheme.label({ Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -22, 1, 0), Text = text,
            FontFace = UITheme.F.bold, TextSize = 18 }).Parent = r
    end
    local note = UITheme.label({ Position = UDim2.fromOffset(30, 176), Size = UDim2.new(1, -60, 0, 40), Text = "",
        FontFace = UITheme.F.medium, TextSize = 15, TextColor3 = T.muted, TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top })
    note.Parent = card
    local ab = actionButton(card, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 30, 1, -22),
        Size = UDim2.new(1, -60, 0, 46) })
    ab.btn.Activated:Connect(function() self:_onVip() end)

    self._vip = { title = title, note = note, ab = ab }
end

-- ── BAGS / CARS / TRAILS / CASH pages (built when the server's data arrives) ──
local COSMETIC_CATS = { bag = "Bags", car = "Cars", trail = "Trails" }

function ShopUI:_buildPlaceholders()
    self._cosCards = {}
    self._loading = {}
    for _, cat in ipairs({ "bag", "car", "trail", "cash" }) do
        local page = self._pages[cat]
        if page then
            self._loading[cat] = UITheme.label({ Name = "Loading", Size = UDim2.new(1, 0, 0, 80),
                Text = "Loading...", TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
                TextSize = 18, TextColor3 = T.muted, Parent = page })
        end
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
        if page and COSMETIC_CATS[cat] then
            if self._loading[cat] then self._loading[cat]:Destroy() end
            grid(page, 4, 262)   -- (v2.2) same height as the mask cards: room for the power pill
            for i, item in ipairs(items) do
                local color = c3(item.color, T.muted)
                -- very dark / very light paints still need a visible rim
                local rim = color
                local lum = color.R * 0.3 + color.G * 0.59 + color.B * 0.11
                if lum < 0.18 then rim = color:Lerp(T.line, 0.35) end
                local ic = itemCard(page, i, rim)
                if cat == "bag" then
                    -- (v2.2) same camera for every tier, so bigger bags LOOK bigger
                    pcall(function()
                        viewport(ic.pic, bagModel(item), Vector3.new(3.4, 3.4, 5.6), Vector3.new(0, 1.25, 0), 40)
                    end)
                    if item.size then
                        local sz = UITheme.label({ AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 8, 0, 8),
                            Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
                            Text = "SIZE " .. tostring(item.size), FontFace = UITheme.F.display, TextSize = 12,
                            TextColor3 = T.text, BackgroundColor3 = T.bgDeep, BackgroundTransparency = 0.25, ZIndex = 3 })
                        UITheme.corner(sz, 10)
                        UITheme.padding(sz, 8, 0)
                        sz.Parent = ic.card
                    end
                elseif cat == "car" then
                    local okReal, vf = pcall(realCarPreview, ic.pic, item)
                    if not (okReal and vf) then
                        pcall(function()
                            viewport(ic.pic, carModel(item), Vector3.new(-8.5, 4.6, 8.5), Vector3.new(0, 1.4, 0), 40)
                        end)
                        -- the real previews may replicate a moment later: swap them in when they do
                        task.spawn(function()
                            local folder = ReplicatedStorage:WaitForChild("HC_CarPreviews", 30)
                            local src = folder and folder:WaitForChild(tostring(item.id), 5)
                            if src and ic.pic.Parent then
                                local old = ic.pic:FindFirstChild("View")
                                local ok2, vf2 = pcall(realCarPreview, ic.pic, item)
                                if ok2 and vf2 and old then old:Destroy() end
                            end
                        end)
                    end
                else
                    trailPicture(ic.pic, item)
                end
                if item.vipOnly or item.rewardOnly then
                    local tag = UITheme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8),
                        Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
                        Text = item.vipOnly and "VIP" or "DAY 7", FontFace = UITheme.F.display, TextSize = 12,
                        TextColor3 = T.bgDeep, BackgroundColor3 = T.gold, BackgroundTransparency = 0, ZIndex = 3 })
                    UITheme.corner(tag, 10)
                    UITheme.padding(tag, 8, 0)
                    tag.Parent = ic.card
                end
                ic.name.Text = string.upper(item.name or item.id)
                -- (v2.2) the power: pill + one line, like the masks
                local pw = type(item.power) == "table" and item.power or nil
                if pw and pw.name then
                    local txt = string.upper(tostring(pw.name))
                    local pc = rim
                    if txt:find("CASH") then pc = T.money
                    elseif txt:find("BUST") then pc = T.gold
                    elseif txt:find("SPEED") then pc = T.info
                    elseif (color.R * 0.3 + color.G * 0.59 + color.B * 0.11) < 0.35 then pc = T.muted end
                    setPill(ic, txt, pc)
                    ic.desc.Text = tostring(pw.desc or item.blurb or "")
                else
                    setPill(ic, nil)
                    ic.desc.Text = item.blurb or ""
                end
                ic.ab.btn.Activated:Connect(function() self:_onCosmetic(item) end)
                self._cosCards[item.id] = { ab = ic.ab, def = item }
            end
        end
    end
end

-- CASH (Robux → cash packs)
local PACK_ICON = { "💵", "💰", "🤑", "🚚" }
function ShopUI:_buildCash(packs)
    self._cashBuilt = true
    local page = self._pages.cash
    if self._loading.cash then self._loading.cash:Destroy() end
    grid(page, 4, 236)
    self._packCards = {}
    for i, pk in ipairs(packs) do
        if type(pk) == "table" and pk.id ~= nil then
            local ic = itemCard(page, i, T.money)
            local b = UITheme.badge(PACK_ICON[math.min(i, #PACK_ICON)], T.money, 64 + math.min(i, 4) * 4)
            b.AnchorPoint = Vector2.new(0.5, 0.5)
            b.Position = UDim2.fromScale(0.5, 0.52)
            b.BackgroundColor3 = T.bgDeep
            b.BackgroundTransparency = 0.3
            b.Parent = ic.pic
            ic.name.Text = UITheme.money(tonumber(pk.cash) or 0)
            ic.name.TextColor3 = T.money
            ic.name.TextSize = 22
            setPill(ic, tostring(pk.name or "Cash pack"), T.money)
            ic.desc.Text = "Instant cash to spend in the shop"
            ic.ab.btn.Activated:Connect(function() self:_onPack(pk) end)
            self._packCards[tostring(pk.id)] = { ab = ic.ab, def = pk }
        end
    end
    if #packs == 0 then
        UITheme.label({ Size = UDim2.new(1, 0, 0, 80), Text = "Cash packs are coming soon!",
            TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextSize = 18,
            TextColor3 = T.muted, Parent = page })
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
            self:_feedback((res.msg and res.msg ~= "") and res.msg or (res.ok and fallback or "Couldn't do that."), res.ok == true)
            local card = self._cosCards[item.id]
            if res.ok and card then self:_popCard(card.ab.btn) end
        end
    end)
end

function ShopUI:_onPack(pk)
    if self._busy then return end
    if pk.available == false then
        self:_feedback("That cash pack is coming soon!", false)
        return
    end
    task.spawn(function()
        local res = self:_request("buyRobuxPack", { id = pk.id }, "pack:" .. tostring(pk.id))
        if res then
            if res.ok then
                self:_feedback("Check the Roblox prompt to finish buying!", true)
            else
                self:_feedback((res.msg and res.msg ~= "") and res.msg or "Couldn't open the purchase.", false)
            end
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
    local maskRows = {}
    if type(s.maskList) == "table" then
        for _, row in ipairs(s.maskList) do
            if type(row) == "table" and row.id then
                maskRows[row.id] = row
                if row.owned then masks[row.id] = true end
            end
        end
    end
    local mask = localPlayer:GetAttribute("Mask")
    if type(mask) ~= "string" or mask == "" then mask = s.mask end
    if mask then masks[mask] = true end
    -- v2.0 cosmetics: server state + the live BagSkin / CarType / Trail attributes
    local sc = type(s.cosmetics) == "table" and s.cosmetics or {}
    local cos = { owned = toSet(sc.owned), equipped = {} }
    local eq = type(sc.equipped) == "table" and sc.equipped or {}
    for cat, attr in pairs({ bag = "BagSkin", car = "CarType", trail = "Trail" }) do
        local a = localPlayer:GetAttribute(attr)
        cos.equipped[cat] = (type(a) == "string" and a ~= "") and a or eq[cat]
        if cos.equipped[cat] then cos.owned[cos.equipped[cat]] = true end
    end
    return {
        cos = cos,
        catalog = type(sc.catalog) == "table" and sc.catalog or nil,
        packs = type(s.robuxPacks) == "table" and s.robuxPacks or nil,
        cash = tonumber(cashAttr) or tonumber(s.cash) or 0,
        gear = gear,
        masks = masks,
        maskRows = maskRows,
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
        elseif busy then
            paint(card.ab, "busy", self._busyKey == "gear:" .. id and "BUYING..." or UITheme.money(g.price))
        elseif v.cash >= g.price then
            paint(card.ab, "buy", UITheme.money(g.price))
        else
            paint(card.ab, "poor", UITheme.money(g.price))
        end
    end

    for id, card in pairs(self._maskCards) do
        local m = card.def
        local row = v.maskRows[id]
        self:_paintMaskInfo(id, row)
        local price = (row and tonumber(row.price)) or m.price or 0
        local equipped = v.mask == id or (row and row.equipped == true and not localPlayer:GetAttribute("Mask"))
        if equipped then
            paint(card.ab, "equipped", "EQUIPPED")
        elseif busy then
            local mine = self._busyKey == "mask:" .. id
            paint(card.ab, "busy", mine and "..." or (v.masks[id] and "EQUIP" or (price <= 0 and "CLAIM" or UITheme.money(price))))
        elseif v.masks[id] then
            paint(card.ab, "equip", "EQUIP")
        elseif price <= 0 then
            paint(card.ab, "claim", "CLAIM")
        elseif v.cash >= price then
            paint(card.ab, "buy", UITheme.money(price))
        else
            paint(card.ab, "poor", UITheme.money(price))
        end
    end

    -- v2.0 cosmetics (pages are built the first time the catalog arrives)
    if not self._cosBuilt and v.catalog then
        self:_buildCosmetics(v.catalog)
    elseif not self._cosBuilt and v.loaded then
        for cat, l in pairs(self._loading or {}) do
            if cat ~= "cash" and l.Parent then l.Text = "Coming soon!" end
        end
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
            paint(card.ab, "buy", UITheme.money(price))
        else
            paint(card.ab, "poor", UITheme.money(price))
        end
    end

    -- CASH packs
    if not self._cashBuilt and v.packs then
        self:_buildCash(v.packs)
    elseif not self._cashBuilt and v.loaded and self._loading.cash and self._loading.cash.Parent then
        self._loading.cash.Text = "Cash packs are coming soon!"
    end
    for pid, card in pairs(self._packCards or {}) do
        local pk = card.def
        for _, fresh in ipairs(v.packs or {}) do
            if type(fresh) == "table" and tostring(fresh.id) == pid then pk = fresh end
        end
        if pk.available == false then
            paint(card.ab, "poor", "COMING SOON")
        elseif busy then
            paint(card.ab, "busy", self._busyKey == "pack:" .. pid and "..." or ("R$ " .. tostring(pk.robux or "?")))
        else
            paint(card.ab, "gold", "R$ " .. tostring(pk.robux or "?"))
        end
        card.def = pk
    end

    -- codes
    local code = self._code
    if busy then
        paint(code.ab, "busy", self._busyKey == "code" and "CHECKING..." or "REDEEM")
    else
        paint(code.ab, "claim", "REDEEM")
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
    fb.TextColor3 = good and T.money or T.gold
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
    local row = v.maskRows[m.id]
    local price = (row and tonumber(row.price)) or m.price or 0
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
            self:_feedback((res.msg and res.msg ~= "") and res.msg or (res.ok and fallback or "Couldn't do that."), res.ok == true)
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
        code.result.TextColor3 = T.gold
        return
    end
    task.spawn(function()
        local res = self:_request("redeemCode", { code = text }, "code")
        if not res then
            code.result.Text = "Couldn't reach the shop. Try again."
            code.result.TextColor3 = T.gold
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
    self._tabSub.Text = TAB_SUB[id] or ""
    for tid, t in pairs(self._tabs) do
        local on = tid == id
        local bgT = on and 0 or 1
        t.btn:SetAttribute("BaseT", bgT)
        if instant then
            t.btn.BackgroundTransparency = bgT
            t.label.TextColor3 = on and T.bgDeep or T.muted
        else
            tween(t.btn, 0.18, { BackgroundTransparency = bgT })
            tween(t.label, 0.18, { TextColor3 = on and T.bgDeep or T.muted })
        end
        t.stroke.Transparency = on and 1 or 0.82
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
    local fit = math.min((vp.X - 24) / (W + 6), (vp.Y - 24) / (H + 6))
    self._fitScale.Scale = math.clamp(math.min(UITheme.scale(), fit), 0.4, 1.6)
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
    self:_selectTab(self._tab or "masks", true)
    self:_render()
    self._screen.Enabled = true
    self._group.GroupTransparency = 1
    self._animScale.Scale = 0.94
    tween(self._backdrop, 0.25, { BackgroundTransparency = 0.4 })
    tween(self._group, 0.22, { GroupTransparency = 0 })
    tween(self._animScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

    ContextActionService:BindAction(CLOSE_ACTION, function(_, state)
        if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
        self:close()
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)

    if GAMEPAD[UserInputService:GetLastInputType()] then
        GuiService.SelectedObject = self._tabs[self._tab or "masks"].btn
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
    self:_selectTab("masks", true)
    self:_renderHint(UserInputService:GetLastInputType())

    ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if prompt.Name == "OpenShop" and player == localPlayer then self:open() end
    end)

    for _, attr in ipairs({ "Cash", "Gear", "Mask", "VIP", "BagSkin", "CarType", "Trail" }) do
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
