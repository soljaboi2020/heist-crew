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
        radius = 16,
    })
    card.Parent = UITheme.slot("topRight")
    local scale = Instance.new("UIScale")
    scale.Parent = card

    local badge = UITheme.badge(UITheme.ICON.cash, T.money, 38)
    badge.AnchorPoint = Vector2.new(0, 0.5)
    badge.Position = UDim2.new(0, 10, 0.5, 0)
    badge.Parent = card

    UITheme.caption("Cash", { Position = UDim2.fromOffset(58, 7), Size = UDim2.new(1, -66, 0, 14) }).Parent = card

    local amount = UITheme.label({
        Name = "Amount",
        RichText = true,
        Position = UDim2.fromOffset(58, 19),
        Size = UDim2.new(1, -66, 0, 34),
        FontFace = UITheme.F.display,
        TextSize = UITheme.T.hero - 2,
        TextColor3 = T.text,
    })
    amount.Parent = card

    -- "+$X" floats just left of the card (child of the card so it scales + follows it)
    local delta = UITheme.label({
        Name = "Delta",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(0, -10, 0.5, 0),
        Size = UDim2.fromOffset(170, 26),
        TextXAlignment = Enum.TextXAlignment.Right,
        FontFace = UITheme.F.display,
        TextSize = 24,
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

function CashHud:start()
    self:_buildUi()
    self:setCash(localPlayer:GetAttribute("Cash") or 0, false)
    localPlayer:GetAttributeChangedSignal("Cash"):Connect(function()
        self:setCash(localPlayer:GetAttribute("Cash") or 0, true)
    end)
    print("[HEIST CREW] CashHud mounted ✅")
end

return CashHud
