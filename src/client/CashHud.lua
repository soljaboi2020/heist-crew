--[[
    HEIST CREW — CashHud (client UI)
    ────────────────────────────────────────────────
    v0.7.0 redesign (UITheme). Top-right smoked-glass card:

        CASH
        $12,450          ← rolls up to the new number instead of jumping
                +$3,000  ← little green delta that drifts down and fades

    Reads the "Cash" player attribute the server sets (EconomyService), so it
    shows the right number the instant it loads. The old version waited for a
    remote event and sat at "$0" if it missed the first one.

    PUBLIC API:
        CashHud:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

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

    local screen = Instance.new("ScreenGui")
    screen.Name = "CashHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = playerGui

    local card = UITheme.panel({
        Name = "Card",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -16, 0, 14),
        Size = UDim2.fromOffset(200, 62),
        radius = 14,
    })
    card.Parent = screen
    local scale = Instance.new("UIScale")
    scale.Parent = card

    UITheme.caption("Cash", { Position = UDim2.fromOffset(16, 9), Size = UDim2.new(1, -32, 0, 14) }).Parent = card

    local amount = UITheme.label({
        Name = "Amount",
        RichText = true,
        Position = UDim2.fromOffset(16, 22),
        Size = UDim2.new(1, -32, 0, 32),
        FontFace = UITheme.F.display,
        TextSize = 28,
        TextColor3 = T.text,
    })
    amount.Parent = card

    local delta = UITheme.label({
        Name = "Delta",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -18, 0, 80),
        Size = UDim2.fromOffset(160, 22),
        TextXAlignment = Enum.TextXAlignment.Right,
        FontFace = UITheme.F.display,
        TextSize = 20,
        TextColor3 = T.money,
        TextTransparency = 1,
        TextStrokeTransparency = 1,
        TextStrokeColor3 = Color3.new(0, 0, 0),
    })
    delta.Parent = screen

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
        self._scale.Scale = 1.06
        TweenService:Create(self._scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }):Play()
        -- "+$X" drifts down and fades
        local d = self._delta
        d.Text = "+" .. UITheme.money(newAmount - old)
        d.Position = UDim2.new(1, -18, 0, 80)
        d.TextTransparency = 0
        d.TextStrokeTransparency = 0.6
        TweenService:Create(d, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.new(1, -18, 0, 96),
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
