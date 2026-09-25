--[[
    HEIST CREW — LootHud
    ────────────────────────────────────────────────
    v1.0 (2026-09-25). Two small pieces:

      • CARRYING PILL (bottom-centre, above the vault-crack card) while the
        "CarryingLoot" attribute is set:
            [bag] CARRYING  GOLD · $1,500    [ G  THROW ]
        The throw action is bound only while you carry something:
        G / gamepad Y / an on-screen THROW button on touch. It fires
        ThrowBag(camera look direction); the server does the rest.

      • KEYCARD CHIP (bottom-left, just above the role card) while the
        "HasKeycard" attribute is true.

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
local PILL_Y = -170             -- vault card occupies y -160..-96 above the bottom edge
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

    local screen = Instance.new("ScreenGui")
    screen.Name = "LootHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = playerGui

    -- ── carrying pill ──
    -- A transparent CanvasGroup wraps the glass pill (2px inset) so the whole thing
    -- fades as one piece without clipping the pill's hairline stroke.
    local group = Instance.new("CanvasGroup")
    group.Name = "Carrying"
    group.AnchorPoint = Vector2.new(0.5, 1)
    group.Position = UDim2.new(0.5, 0, 1, PILL_Y)
    group.Size = UDim2.fromOffset(0, 50)
    group.AutomaticSize = Enum.AutomaticSize.X
    group.BackgroundTransparency = 1
    group.GroupTransparency = 1
    group.Visible = false
    group.Parent = screen
    local gp = Instance.new("UIPadding")
    gp.PaddingLeft, gp.PaddingRight = UDim.new(0, 3), UDim.new(0, 3)
    gp.PaddingTop, gp.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
    gp.Parent = group
    local scale = Instance.new("UIScale")
    scale.Parent = group

    local pill = UITheme.panel({ Name = "Pill", Size = UDim2.fromOffset(0, 44), AutomaticSize = Enum.AutomaticSize.X,
        radius = 22 })
    pill.Parent = group
    hpad(pill, 16, 7)
    hrow(pill, 10)

    -- bag glyph: rounded body + hollow handle, tinted with the loot colour
    local bag = frame({ Name = "Bag", LayoutOrder = 1, Size = UDim2.fromOffset(18, 18) })
    bag.Parent = pill
    local body = frame({ Position = UDim2.fromOffset(1, 6), Size = UDim2.fromOffset(16, 12), BackgroundTransparency = 0,
        BackgroundColor3 = T.gold })
    UITheme.corner(body, 4)
    body.Parent = bag
    local handle = frame({ Position = UDim2.fromOffset(5, 1), Size = UDim2.fromOffset(8, 8) })
    UITheme.corner(handle, 4)
    local handleStroke = UITheme.stroke(handle, T.gold, 0, 2)
    handle.Parent = bag

    UITheme.caption("Carrying", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 44), TextSize = 12 }).Parent = pill
    local kind = UITheme.label({ Name = "Kind", LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 44), FontFace = UITheme.F.display, TextSize = 17, Text = "" })
    kind.Parent = pill
    UITheme.label({ LayoutOrder = 4, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 44),
        Text = "·", TextColor3 = T.faint, TextSize = 17 }).Parent = pill
    local value = UITheme.label({ Name = "Value", LayoutOrder = 5, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 44), FontFace = UITheme.F.display, TextSize = 17, TextColor3 = T.money, Text = "" })
    value.Parent = pill

    -- key hint chip:  [G] THROW
    local hint = frame({ Name = "Hint", LayoutOrder = 6, Size = UDim2.fromOffset(0, 30),
        AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.line, BackgroundTransparency = 0.93 })
    UITheme.corner(hint, 15)
    UITheme.stroke(hint, T.line, 0.9)
    hint.Parent = pill
    hpad(hint, 4, 12)
    hrow(hint, 8)
    local keycap = UITheme.label({ Name = "Key", LayoutOrder = 1, Size = UDim2.fromOffset(22, 22), Text = "G",
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.mono, TextSize = 13, TextColor3 = T.bg,
        BackgroundColor3 = T.text, BackgroundTransparency = 0 })
    UITheme.corner(keycap, 11)
    keycap.Parent = hint
    UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30),
        Text = "THROW", FontFace = UITheme.F.bold, TextSize = 12 }).Parent = hint

    -- ── keycard chip (just above the 62px role card: 16 margin + 62 + 8 gap) ──
    local key = UITheme.panel({ Name = "Keycard", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -86),
        Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, radius = 16, Visible = false })
    key.Parent = screen
    local keyStroke = key:FindFirstChildOfClass("UIStroke")
    if keyStroke then
        keyStroke.Color = T.info
        keyStroke.Transparency = 0.45
    end
    hpad(key, 10, 13)
    hrow(key, 8)
    local keyScale = Instance.new("UIScale")
    keyScale.Parent = key
    local card = frame({ LayoutOrder = 1, Size = UDim2.fromOffset(18, 13), BackgroundColor3 = T.info, BackgroundTransparency = 0 })
    UITheme.corner(card, 3)
    card.Parent = key
    frame({ Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = T.bg,
        BackgroundTransparency = 0.35 }).Parent = card
    frame({ Position = UDim2.fromOffset(3, 8), Size = UDim2.fromOffset(6, 2), BackgroundColor3 = T.bg,
        BackgroundTransparency = 0.5 }).Parent = card
    UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32),
        Text = "KEYCARD", FontFace = UITheme.F.bold, TextSize = 13, TextColor3 = T.info }).Parent = key

    self._group, self._scale = group, scale
    self._body, self._handleStroke, self._kind, self._value = body, handleStroke, kind, value
    self._hint, self._keycap = hint, keycap
    self._key, self._keyScale = key, keyScale
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
        self._body.BackgroundColor3 = color
        self._handleStroke.Color = color
        self._value.Text = def and UITheme.money(def.value) or ""
        if not g.Visible or g.GroupTransparency > 0.5 then
            g.Visible = true
            g.GroupTransparency = 1
            g.Position = UDim2.new(0.5, 0, 1, PILL_Y + 12)
            self._scale.Scale = 0.9
        end
        tween(g, 0.25, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 1, PILL_Y) })
        tween(self._scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
    elseif g.Visible then
        local out = tween(g, 0.25, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 1, PILL_Y + 10) },
            Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        out.Completed:Connect(function()
            if self._carryToken == token then g.Visible = false end
        end)
    end
end

function LootHud:_renderKeycard()
    local has = localPlayer:GetAttribute("HasKeycard") == true
    if has == self._hasKey then return end
    self._hasKey = has
    if has then
        self._key.Visible = true
        self._keyScale.Scale = 0.6
        tween(self._keyScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
    else
        local out = tween(self._keyScale, 0.18, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        out.Completed:Connect(function()
            if not self._hasKey then self._key.Visible = false end
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
