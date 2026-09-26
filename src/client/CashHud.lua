--[[
    HEIST CREW — CashHud (client UI)
    ────────────────────────────────────────────────
    v0.7.0, v2.1 UI overhaul. First card in the topRight slot (THE JOB card
    stacks under it):

        [$]  CASH
             $12,450          ← rolls up to the new number instead of jumping
    +$3,000                    ← green delta just left of the card, drifts + fades

    Reads the "Cash" player attribute the server sets (EconomyService), so it
    shows the right number the instant it loads.

    v3.2 "MIAMI HUD": teal-glow card, bigger number, and a little flame chip
    ("x3") while the player's hot streak (attribute Streak, PlayerDataService)
    is 1 or more.

    PUBLIC API:
        CashHud:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C
local L = UITheme.L

local CashHud = {}
local localPlayer = Players.LocalPlayer

local function render(label, amount)
    local s = UITheme.money(amount):sub(2)   -- drop the "$", colour it separately
    label.Text = string.format('<font color="#4ADE80">$</font>%s', s)
end

function CashHud:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("CashHud")
    if existing then existing:Destroy() end

    local card = UITheme.card({
        Name = "CashCard",
        LayoutOrder = 1,
        Size = UDim2.fromOffset(L.CASH_W, L.CASH_H),
        radius = 18,
        tint = T.teal,
    })
    card.Parent = UITheme.slot("topRight")
    local scale = Instance.new("UIScale")
    scale.Parent = card

    local badge = UITheme.badge(UITheme.ICON.cash, T.money, 42)
    badge.AnchorPoint = Vector2.new(0, 0.5)
    badge.Position = UDim2.new(0, 9, 0.5, 0)
    badge.Parent = card

    UITheme.caption("Cash", { Position = UDim2.fromOffset(60, 6), Size = UDim2.new(1, -68, 0, 16) }).Parent = card

    -- hot-streak flame chip (top-right corner of the card)
    local streak = UITheme.pill("🔥 x0", T.sunset, { Name = "Streak", AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 5), Size = UDim2.fromOffset(0, 20), TextSize = 13, Visible = false })
    streak.Parent = card
    self._streak = streak

    local amount = UITheme.label({
        Name = "Amount",
        RichText = true,
        Position = UDim2.fromOffset(60, 20),
        Size = UDim2.new(1, -68, 0, 36),
        FontFace = UITheme.F.display,
        TextSize = UITheme.T.hero - 2,
        TextScaled = true,
        TextColor3 = T.text,
    })
    do local c = Instance.new("UITextSizeConstraint") c.MaxTextSize = UITheme.T.hero - 2 c.MinTextSize = 14 c.Parent = amount end
    amount.Parent = card

    -- "+$X" floats just left of the card (child of the card so it scales + follows it)
    local delta = UITheme.label({
        Name = "Delta",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(0, -10, 0.5, 0),
        Size = UDim2.fromOffset(170, 26),
        TextXAlignment = Enum.TextXAlignment.Right,
        FontFace = UITheme.F.display,
        TextSize = 26,
        TextColor3 = T.money,
        TextTransparency = 1,
        TextStrokeTransparency = 1,
        TextStrokeColor3 = Color3.new(0, 0, 0),
    })
    delta.Parent = card

    self._amount, self._delta, self._scale = amount, delta, scale
    self._shown = Instance.new("NumberValue")
    self._shown.Changed:Connect(function(v) render(amount, v) end)
end

function CashHud:setCash(newAmount, animate)
    local old = self._target or 0
    self._target = newAmount
    if not animate or newAmount == old then
        self._shown.Value = newAmount
        render(self._amount, newAmount)
        return
    end

    -- roll the number
    TweenService:Create(self._shown, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        { Value = newAmount }):Play()

    if newAmount > old then
        -- little pop on the card
        self._scale.Scale = 1.08
        TweenService:Create(self._scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }):Play()
        -- "+$X" drifts down and fades
        local d = self._delta
        d.Text = "+" .. UITheme.money(newAmount - old)
        d.Position = UDim2.new(0, -10, 0.5, 0)
        d.TextTransparency = 0
        d.TextStrokeTransparency = 0.5
        TweenService:Create(d, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.new(0, -10, 0.5, 18),
            TextTransparency = 1,
            TextStrokeTransparency = 1,
        }):Play()
    end
end

function CashHud:_renderStreak()
    local n = tonumber(localPlayer:GetAttribute("Streak")) or 0
    self._streak.Visible = n >= 1
    self._streak.Text = string.format("🔥 x%d", n)
end

function CashHud:start()
    self:_buildUi()
    self:_renderStreak()
    localPlayer:GetAttributeChangedSignal("Streak"):Connect(function() self:_renderStreak() end)
    self:setCash(localPlayer:GetAttribute("Cash") or 0, false)
    localPlayer:GetAttributeChangedSignal("Cash"):Connect(function()
        self:setCash(localPlayer:GetAttribute("Cash") or 0, true)
    end)
    print("[HEIST CREW] CashHud mounted ✅")
end

return CashHud
