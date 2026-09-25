--[[
    HEIST CREW — LootHud
    ────────────────────────────────────────────────
    v1.0 (2026-09-25). Two small pieces:

      (v2.1) both live in ONE row in the UITheme bottomCenter slot, so they
      can't overlap the drill card / heist-door panel / car dashboard.

      • CARRYING PILL while the "CarryingLoot" attribute is set:
            [bag] CARRYING  GOLD · $1,500    [ G  THROW ]
        The throw action is bound only while you carry something:
        G / gamepad Y / an on-screen THROW button on touch. It fires
        ThrowBag(camera look direction); the server does the rest.

      • KEYCARD CHIP (left of the carrying pill) while the "HasKeycard"
        attribute is true.

    PUBLIC API:
        LootHud:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local LootHud = {}
local localPlayer = Players.LocalPlayer

local ACTION = "HC_ThrowBag"
local THROW_COOLDOWN = 0.35
-- Touch button spot inside Roblox's context-button frame (bottom-right third of the
-- screen, around the jump button). Scale values; tweak here if it crowds the jump button.
local TOUCH_POS = UDim2.new(0.22, 0, 0.32, 0)

local GAMEPAD = {
    [Enum.UserInputType.Gamepad1] = true, [Enum.UserInputType.Gamepad2] = true,
    [Enum.UserInputType.Gamepad3] = true, [Enum.UserInputType.Gamepad4] = true,
}

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

local function hrow(parent, gap)
    local l = Instance.new("UIListLayout")
    l.FillDirection = Enum.FillDirection.Horizontal
    l.VerticalAlignment = Enum.VerticalAlignment.Center
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, gap or 8)
    l.Parent = parent
    return l
end

local function hpad(parent, l, r)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, l)
    p.PaddingRight = UDim.new(0, r or l)
    p.Parent = parent
    return p
end

-- Restyle Roblox's grey touch button so it matches the HUD (dark glass circle).
local function styleTouchButton(actionName, title, pos)
    pcall(function()
        ContextActionService:SetTitle(actionName, title)
        ContextActionService:SetPosition(actionName, pos)
    end)
    local btn = ContextActionService:GetButton(actionName)
    if not btn then return end
    pcall(function()
        btn.ImageTransparency = 1
        btn.BackgroundTransparency = 0.2
        btn.BackgroundColor3 = T.bg
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0.5, 0)
        c.Parent = btn
        UITheme.stroke(btn, T.line, 0.7, 1.5)
        local t = btn:FindFirstChild("ActionTitle")
        if t and t:IsA("TextLabel") then
            t.FontFace = UITheme.F.bold
            t.TextColor3 = T.text
            t.TextScaled = false
            t.TextSize = 13
        end
    end)
end

function LootHud:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("LootHud")
    if existing then existing:Destroy() end

    -- one centred row in the bottomCenter slot:  [KEYCARD]  [(bag) CARRYING GOLD · $1,500  (G) THROW]
    local rowFrame = frame({ Name = "LootRow", LayoutOrder = 20, Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY, Visible = false })
    rowFrame.Parent = UITheme.slot("bottomCenter")
    hrow(rowFrame, 10)

    -- ── carrying pill ──
    -- A transparent CanvasGroup wraps the pill (3px inset) so the whole thing
    -- fades as one piece without clipping the pill's outline.
    local group = Instance.new("CanvasGroup")
    group.Name = "Carrying"
    group.LayoutOrder = 2
    group.Size = UDim2.fromOffset(0, 58)
    group.AutomaticSize = Enum.AutomaticSize.X
    group.BackgroundTransparency = 1
    group.GroupTransparency = 1
    group.Visible = false
    group.Parent = rowFrame
    local gp = Instance.new("UIPadding")
    gp.PaddingLeft, gp.PaddingRight = UDim.new(0, 3), UDim.new(0, 3)
    gp.PaddingTop, gp.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
    gp.Parent = group
    local scale = Instance.new("UIScale")
    scale.Parent = group

    local pill = UITheme.card({ Name = "Pill", Size = UDim2.fromOffset(0, 52), AutomaticSize = Enum.AutomaticSize.X,
        radius = 26, noHighlight = true })
    pill.Parent = group
    hpad(pill, 7, 8)
    hrow(pill, 10)

    local bagBadge = UITheme.badge(UITheme.ICON.bag, T.gold, 40, { LayoutOrder = 1 })
    bagBadge.Parent = pill

    UITheme.caption("Carrying", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 52), TextSize = 13 }).Parent = pill
    local kind = UITheme.label({ Name = "Kind", LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 52), FontFace = UITheme.F.display, TextSize = 21, Text = "" })
    kind.Parent = pill
    UITheme.label({ LayoutOrder = 4, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 52),
        Text = "·", TextColor3 = T.faint, TextSize = 21 }).Parent = pill
    local value = UITheme.label({ Name = "Value", LayoutOrder = 5, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 52), FontFace = UITheme.F.display, TextSize = 21, TextColor3 = T.money, Text = "" })
    value.Parent = pill

    -- key hint chip:  [G] THROW
    local hint = frame({ Name = "Hint", LayoutOrder = 6, Size = UDim2.fromOffset(0, 36),
        AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.line, BackgroundTransparency = 0.9 })
    UITheme.corner(hint, 18)
    UITheme.stroke(hint, T.line, 0.85)
    hint.Parent = pill
    hpad(hint, 5, 13)
    hrow(hint, 8)
    local keycap = UITheme.label({ Name = "Key", LayoutOrder = 1, Size = UDim2.fromOffset(26, 26), Text = "G",
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.mono, TextSize = 15, TextColor3 = T.bgDeep,
        BackgroundColor3 = T.text, BackgroundTransparency = 0 })
    UITheme.corner(keycap, 13)
    keycap.Parent = hint
    UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36),
        Text = "THROW", FontFace = UITheme.F.display, TextSize = 14 }).Parent = hint

    -- ── keycard chip (left of the carrying pill) ──
    local key = UITheme.card({ Name = "Keycard", LayoutOrder = 1, Size = UDim2.fromOffset(0, 46),
        AutomaticSize = Enum.AutomaticSize.X, radius = 23, accent = T.info, noHighlight = true, Visible = false })
    key.Parent = rowFrame
    hpad(key, 6, 16)
    hrow(key, 8)
    local keyScale = Instance.new("UIScale")
    keyScale.Parent = key
    UITheme.badge(UITheme.ICON.key, T.info, 34, { LayoutOrder = 1 }).Parent = key
    UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 46),
        Text = "KEYCARD", FontFace = UITheme.F.display, TextSize = 17, TextColor3 = T.info }).Parent = key

    self._row = rowFrame
    self._group, self._scale = group, scale
    self._bagBadge, self._kind, self._value = bagBadge, kind, value
    self._hint, self._keycap = hint, keycap
    self._key, self._keyScale = key, keyScale
end

function LootHud:_syncRow()
    self._row.Visible = self._group.Visible or self._key.Visible
end

-- ── input hint (G / Y / hidden on touch) ──
function LootHud:_renderHint(inputType)
    if GAMEPAD[inputType] then
        self._hint.Visible = true
        self._keycap.Text = "Y"
    elseif inputType == Enum.UserInputType.Touch then
        self._hint.Visible = false          -- the on-screen THROW button is the hint
    else
        self._hint.Visible = true
        self._keycap.Text = "G"
    end
end

-- ── throw binding ──
function LootHud:_throw()
    if os.clock() - (self._lastThrow or 0) < THROW_COOLDOWN then return end
    self._lastThrow = os.clock()
    local remote = self._throwRemote
    local cam = workspace.CurrentCamera
    if remote and cam then
        remote:FireServer(cam.CFrame.LookVector)
    end
    self._scale.Scale = 0.92
    tween(self._scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

function LootHud:_setBound(on)
    if on == self._bound then return end
    self._bound = on
    if on then
        ContextActionService:BindAction(ACTION, function(_, state)
            if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
            self:_throw()
            return Enum.ContextActionResult.Sink
        end, true, Enum.KeyCode.G, Enum.KeyCode.ButtonY)
        styleTouchButton(ACTION, "THROW", TOUCH_POS)
    else
        ContextActionService:UnbindAction(ACTION)
    end
end

-- ── renders ──
function LootHud:_renderCarry()
    local kindId = localPlayer:GetAttribute("CarryingLoot")
    local carrying = type(kindId) == "string" and kindId ~= ""
    self:_setBound(carrying)

    local token = {}
    self._carryToken = token
    local g = self._group
    if carrying then
        local def = Constants.LOOT[kindId]
        local color = def and UITheme.rgb(def.color) or T.text
        self._kind.Text = string.upper(kindId)
        self._kind.TextColor3 = color
        UITheme.setBadge(self._bagBadge, UITheme.ICON.bag, color)
        self._value.Text = def and UITheme.money(def.value) or ""
        if not g.Visible or g.GroupTransparency > 0.5 then
            g.Visible = true
            g.GroupTransparency = 1
            self._scale.Scale = 0.85
        end
        self:_syncRow()
        tween(g, 0.25, { GroupTransparency = 0 })
        tween(self._scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
    elseif g.Visible then
        tween(self._scale, 0.25, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        local out = tween(g, 0.25, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        out.Completed:Connect(function()
            if self._carryToken == token then
                g.Visible = false
                self:_syncRow()
            end
        end)
    end
end

function LootHud:_renderKeycard()
    local has = localPlayer:GetAttribute("HasKeycard") == true
    if has == self._hasKey then return end
    self._hasKey = has
    if has then
        self._key.Visible = true
        self:_syncRow()
        self._keyScale.Scale = 0.6
        tween(self._keyScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
    else
        local out = tween(self._keyScale, 0.18, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        out.Completed:Connect(function()
            if not self._hasKey then
                self._key.Visible = false
                self:_syncRow()
            end
        end)
    end
end

function LootHud:start()
    self:_buildUi()
    self:_renderHint(UserInputService:GetLastInputType())
    self:_renderCarry()
    self:_renderKeycard()

    localPlayer:GetAttributeChangedSignal("CarryingLoot"):Connect(function() self:_renderCarry() end)
    localPlayer:GetAttributeChangedSignal("HasKeycard"):Connect(function() self:_renderKeycard() end)
    UserInputService.LastInputTypeChanged:Connect(function(t)
        if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseWheel then
            t = Enum.UserInputType.Keyboard
        end
        self:_renderHint(t)
    end)

    task.spawn(function()
        self._throwRemote = Remotes.getRemote(Remotes.NAMES.ThrowBag, "RemoteEvent")
        if not self._throwRemote then
            warn("[HEIST CREW] LootHud: ThrowBag remote missing — throwing is disabled")
        end
    end)

    print("[HEIST CREW] LootHud mounted ✅")
end

return LootHud
