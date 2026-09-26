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

      v3.0 "THE SCORE" (LOOT-CORE, docs/V3_SPEC.md §2):
      • the pill shows the loot's real NAME + VALUE (LootService attributes
        CarryName / CarryValue — jackpot, cracks and bag tier included) and
        flag chips: HEAVY · FRAGILE 75% · JACKPOT · TARGET. Helping lift a
        heavy one (CarryHelping) shows "HELPING  GOLDEN FLAMINGO · with Sam".
      • TARGET CHIP (left end of the row) during a heist:
            [🎯] TARGET  Golden Flamingo · +$5,000      → turns green "SECURED" once loaded
        (ReplicatedStorage attributes TargetName / TargetBonus / TargetSecured,
        shown while JobInfo.stage == "ACTIVE").
      • JACKPOT BANNER on the drop-in (LaunchJob phase "title"):
            "JACKPOT: the WINE CELLAR x1.5!"   (ReplicatedStorage LootJackpot / LootJackpotMult)
      • SPINNERS: parts tagged "Spin" (attribute Spin = degrees/second, e.g. the
        Pink Diamond's turntable) turn locally, around their own up axis, while
        within 160 studs of the camera. Welded children turn with them.

    PUBLIC API:
        LootHud:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local LootHud = {}
local localPlayer = Players.LocalPlayer

local ACTION = "HC_ThrowBag"
-- (v3.2) the Boss target moved onto THE JOB card header (JobHud) — one less
-- panel on screen. Flip this back on to bring the bottom chip back.
local SHOW_TARGET_CHIP = false
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
            t.TextSize = 16
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
        radius = 26, noHighlight = true, tint = T.pink })
    pill.Parent = group
    hpad(pill, 7, 8)
    hrow(pill, 10)

    local bagBadge = UITheme.badge(UITheme.ICON.bag, T.gold, 40, { LayoutOrder = 1 })
    bagBadge.Parent = pill

    local caption = UITheme.caption("Carrying", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 52), TextSize = 15, TextColor3 = T.pink })
    caption.Parent = pill
    self._caption = caption
    local kind = UITheme.label({ Name = "Kind", LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 52), FontFace = UITheme.F.display, TextSize = 23, Text = "" })
    kind.Parent = pill
    UITheme.label({ LayoutOrder = 4, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 52),
        Text = "·", TextColor3 = T.faint, TextSize = 21 }).Parent = pill
    local value = UITheme.label({ Name = "Value", LayoutOrder = 5, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 52), FontFace = UITheme.F.display, TextSize = 23, TextColor3 = T.money, Text = "" })
    value.Parent = pill

    -- v3: flag chips (HEAVY / FRAGILE 75% / JACKPOT / TARGET)
    local flags = frame({ Name = "Flags", LayoutOrder = 6, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X })
    flags.Parent = pill
    hrow(flags, 6)
    local function flagChip(order, text, color)
        local chip = frame({ LayoutOrder = order, Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = color, BackgroundTransparency = 0.15, Visible = false })
        UITheme.corner(chip, 14)
        hpad(chip, 9, 9)
        local l = UITheme.label({ Name = "Text", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28),
            Text = text, FontFace = UITheme.F.display, TextSize = 15, TextColor3 = T.bgDeep })
        l.Parent = chip
        chip.Parent = flags
        return chip
    end
    self._flagHeavy = flagChip(1, "HEAVY", T.danger)
    self._flagFragile = flagChip(2, "FRAGILE", T.pink)
    self._flagJackpot = flagChip(3, "JACKPOT", T.gold)
    self._flagTarget = flagChip(4, "TARGET", T.teal)
    self._flags = flags

    -- key hint chip:  [G] THROW
    local hint = frame({ Name = "Hint", LayoutOrder = 7, Size = UDim2.fromOffset(0, 36),
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
        Text = "THROW", FontFace = UITheme.F.display, TextSize = 17 }).Parent = hint

    -- ── v3 target chip (left end of the row) ──
    local target = UITheme.card({ Name = "Target", LayoutOrder = 0, Size = UDim2.fromOffset(0, 46),
        AutomaticSize = Enum.AutomaticSize.X, radius = 23, accent = T.gold, noHighlight = true, Visible = false })
    target.Parent = rowFrame
    hpad(target, 6, 16)
    hrow(target, 8)
    local targetBadge = UITheme.badge(UITheme.ICON.target, T.gold, 34, { LayoutOrder = 1 })
    targetBadge.Parent = target
    local targetCap = UITheme.caption("Target", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 46), TextSize = 12 })
    targetCap.Parent = target
    local targetName = UITheme.label({ LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 46),
        Text = "", FontFace = UITheme.F.display, TextSize = 17, TextColor3 = T.gold })
    targetName.Parent = target
    local targetBonus = UITheme.label({ LayoutOrder = 4, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 46),
        Text = "", FontFace = UITheme.F.display, TextSize = 17, TextColor3 = T.money })
    targetBonus.Parent = target
    self._target, self._targetBadge, self._targetCap = target, targetBadge, targetCap
    self._targetName, self._targetBonus = targetName, targetBonus

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
        Text = "KEYCARD", FontFace = UITheme.F.display, TextSize = 19, TextColor3 = T.info }).Parent = key

    self._row = rowFrame
    self._group, self._scale = group, scale
    self._bagBadge, self._kind, self._value = bagBadge, kind, value
    self._hint, self._keycap = hint, keycap
    self._key, self._keyScale = key, keyScale
end

function LootHud:_syncRow()
    self._row.Visible = self._group.Visible or self._key.Visible or self._target.Visible
end

-- ── input hint (G / Y / hidden on touch) ──
function LootHud:_renderHint(inputType)
    self._lastInput = inputType
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
    local helping = localPlayer:GetAttribute("CarryHelping")
    local carrying = type(kindId) == "string" and kindId ~= ""
    self:_setBound(carrying)
    if not carrying and type(helping) == "string" and helping ~= "" then
        -- v3: lifting the other side of someone's heavy loot
        self:_renderHelping(helping)
        return
    end
    self._caption.Text = "CARRYING"

    local token = {}
    self._carryToken = token
    local g = self._group
    if carrying then
        local def = Constants.LOOT[kindId]
        local color = def and UITheme.rgb(def.color) or T.text
        local name = localPlayer:GetAttribute("CarryName") or (def and def.name) or kindId
        self._kind.Text = string.upper(tostring(name))
        self._kind.TextColor3 = color
        UITheme.setBadge(self._bagBadge, UITheme.ICON.bag, color)
        local v = tonumber(localPlayer:GetAttribute("CarryValue")) or (def and def.value)
        self._value.Text = v and UITheme.money(v) or ""
        self:_renderFlags()
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

-- v3: HEAVY / FRAGILE nn% / JACKPOT / TARGET chips + the throw hint only when you can throw it
function LootHud:_renderFlags()
    local heavy = localPlayer:GetAttribute("CarryHeavy") == true
    local fragile = localPlayer:GetAttribute("CarryFragile") == true
    local integ = tonumber(localPlayer:GetAttribute("CarryIntegrity")) or 1
    self._flagHeavy.Visible = heavy
    local partner = localPlayer:GetAttribute("CarryPartner")
    self._flagHeavy:FindFirstChild("Text").Text = (heavy and type(partner) == "string" and partner ~= "") and ("HEAVY · with " .. partner) or "HEAVY"
    self._flagFragile.Visible = fragile
    self._flagFragile:FindFirstChild("Text").Text = integ < 0.999 and string.format("CRACKED %d%%", math.floor(integ * 100 + 0.5))
        or "FRAGILE · walk slow (C)"
    self._flagJackpot.Visible = localPlayer:GetAttribute("CarryJackpot") == true
    self._flagTarget.Visible = localPlayer:GetAttribute("CarryTarget") == true
    local canThrow = not heavy or localPlayer:GetAttribute("Role") == "Muscle"
    if not canThrow then self._hint.Visible = false else self:_renderHint(self._lastInput or UserInputService:GetLastInputType()) end
end

function LootHud:_renderHelping(itemName)
    local token = {}
    self._carryToken = token
    local g = self._group
    self._caption.Text = "HELPING"
    self._kind.Text = string.upper(itemName)
    self._kind.TextColor3 = T.gold
    UITheme.setBadge(self._bagBadge, "💪", T.gold)
    local partner = localPlayer:GetAttribute("CarryPartner")
    self._value.Text = (type(partner) == "string" and partner ~= "") and ("with " .. partner) or ""
    self._flagHeavy.Visible = true
    self._flagHeavy:FindFirstChild("Text").Text = "HEAVY · stay close!"
    self._flagFragile.Visible, self._flagJackpot.Visible, self._flagTarget.Visible = false, false, false
    self._hint.Visible = false
    if not g.Visible or g.GroupTransparency > 0.5 then
        g.Visible = true
        g.GroupTransparency = 1
        self._scale.Scale = 0.85
    end
    self:_syncRow()
    tween(g, 0.25, { GroupTransparency = 0 })
    tween(self._scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- v3: the Boss's target, while a heist is running
function LootHud:_renderTarget()
    local name = ReplicatedStorage:GetAttribute("TargetName")
    local show = SHOW_TARGET_CHIP and self._stage == "ACTIVE" and type(name) == "string" and name ~= ""
    local wasVisible = self._target.Visible
    self._target.Visible = show
    if show then
        local secured = ReplicatedStorage:GetAttribute("TargetSecured") == true
        local bonus = tonumber(ReplicatedStorage:GetAttribute("TargetBonus")) or 5000
        self._targetCap.Text = secured and "SECURED" or "TARGET"
        self._targetName.Text = name
        self._targetName.TextColor3 = secured and T.money or T.gold
        self._targetBonus.Text = "+" .. UITheme.money(bonus)
        UITheme.setBadge(self._targetBadge, secured and UITheme.ICON.check or UITheme.ICON.target, secured and T.money or T.gold)
        if self._target:FindFirstChild("Stroke") then self._target.Stroke.Color = secured and T.money or T.gold end
    end
    if show ~= wasVisible then self:_syncRow() end
end

-- v3: "JACKPOT: the WINE CELLAR x1.5!" right after the drop-in title
function LootHud:_jackpotBanner()
    local room = ReplicatedStorage:GetAttribute("LootJackpot")
    if type(room) ~= "string" or room == "" then return end
    local mult = tonumber(ReplicatedStorage:GetAttribute("LootJackpotMult")) or 1.5
    local text = string.format("JACKPOT: the %s x%s!", room, (mult % 1 == 0) and tostring(math.floor(mult)) or tostring(mult))
    local FeelFX = script.Parent:FindFirstChild("FeelFX")
    local ok = false
    if FeelFX then
        ok = pcall(function() require(FeelFX):banner(text, "gold", false) end)
    end
    if not ok then warn("[HEIST CREW] LootHud: no FeelFX banner for the jackpot") end
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

-- v3: client-side turntables (tag "Spin", attribute Spin = deg/s)
local SPIN_RANGE = 160
function LootHud:_spinStep(dt, camPos)
    for _, p in ipairs(CollectionService:GetTagged("Spin")) do
        if p:IsA("BasePart") and p:IsDescendantOf(workspace) then
            local rate = tonumber(p:GetAttribute("Spin")) or 0
            if rate ~= 0 and (p.Position - camPos).Magnitude <= SPIN_RANGE then
                p.CFrame = p.CFrame * CFrame.Angles(0, math.rad(rate * dt), 0)
            end
        end
    end
end

function LootHud:_startSpinners()
    RunService.RenderStepped:Connect(function(dt)
        local cam = workspace.CurrentCamera
        if cam then self:_spinStep(dt, cam.CFrame.Position) end
    end)
end

function LootHud:start()
    self:_buildUi()
    pcall(function() self:_startSpinners() end)
    self:_renderHint(UserInputService:GetLastInputType())
    self:_renderCarry()
    self:_renderKeycard()

    localPlayer:GetAttributeChangedSignal("CarryingLoot"):Connect(function() self:_renderCarry() end)
    -- v3: live value / cracks / lifting partner
    for _, a in ipairs({ "CarryValue", "CarryIntegrity", "CarryPartner", "CarryName" }) do
        localPlayer:GetAttributeChangedSignal(a):Connect(function()
            if localPlayer:GetAttribute("CarryingLoot") then
                local v = tonumber(localPlayer:GetAttribute("CarryValue"))
                if v then self._value.Text = UITheme.money(v) end
                local n = localPlayer:GetAttribute("CarryName")
                if type(n) == "string" then self._kind.Text = string.upper(n) end
                self:_renderFlags()
            end
        end)
    end
    localPlayer:GetAttributeChangedSignal("CarryHelping"):Connect(function() self:_renderCarry() end)
    for _, a in ipairs({ "TargetName", "TargetSecured", "TargetBonus" }) do
        ReplicatedStorage:GetAttributeChangedSignal(a):Connect(function() self:_renderTarget() end)
    end
    localPlayer:GetAttributeChangedSignal("HasKeycard"):Connect(function() self:_renderKeycard() end)
    UserInputService.LastInputTypeChanged:Connect(function(t)
        if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseWheel then
            t = Enum.UserInputType.Keyboard
        end
        self:_renderHint(t)
    end)

    -- v3: heist stage (target chip) + drop-in (jackpot banner)
    task.spawn(function()
        local info = Remotes.getRemote(Remotes.NAMES.JobInfo, "RemoteEvent")
        if info then
            info.OnClientEvent:Connect(function(payload)
                if type(payload) ~= "table" then return end
                if payload.stage ~= self._stage then
                    self._stage = payload.stage
                    self:_renderTarget()
                end
            end)
        end
    end)
    task.spawn(function()
        local launch = Remotes.getRemote(Remotes.NAMES.LaunchJob, "RemoteEvent")
        if launch then
            launch.OnClientEvent:Connect(function(payload)
                if type(payload) == "table" and payload.phase == "title" then
                    -- (v3.3) queued on FeelFX's big-banner lock: BriefingUI's drop-in title holds it
                    -- ~2.5 s, so the jackpot shows right after it (never on top of it), then tips
                    task.delay(0.15, function() self:_jackpotBanner() end)
                end
            end)
        end
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
