--[[
    HEIST CREW — Notifications (toasts)
    ────────────────────────────────────────────────
    v0.7.0, v2.1 UI overhaul. Toasts stack in the topCenter slot, directly
    under the objective bar (so they can never cover it): a chunky rounded
    card, a coloured accent + dot for meaning (green = money, red = danger,
    gold = heads-up), big white text. Max 3 at once; the oldest goes first.
    They fade + pop in and fade out as one piece (CanvasGroup).

    Server fires:  Notify:FireClient(player, {text=..., color="green"|"red"|"gold"|"white", duration=3})

    PUBLIC API:
        Notifications:start()
        Notifications:show(text, colorName, duration)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local Notifications = {}
local localPlayer = Players.LocalPlayer

local ACCENT = {
    green = T.money,
    red   = T.danger,
    gold  = T.gold,
    white = T.info,
}

local MAX_TOASTS = 3

function Notifications:_buildContainer()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("ToastNotifications")
    if existing then existing:Destroy() end

    local container = Instance.new("Frame")
    container.Name = "Toasts"
    container.LayoutOrder = 2
    container.BackgroundTransparency = 1
    container.Size = UDim2.fromOffset(0, 0)
    container.AutomaticSize = Enum.AutomaticSize.XY
    container.Parent = UITheme.slot("topCenter")

    local layout = Instance.new("UIListLayout")
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = container

    self._container = container
    self._n = 0
end

function Notifications:show(text, colorName, duration)
    if not self._container then return end
    duration = duration or 3
    local accent = ACCENT[colorName] or ACCENT.white
    self._n = self._n + 1

    -- keep the stack short: drop the oldest
    local toasts = {}
    for _, c in ipairs(self._container:GetChildren()) do
        if c:IsA("CanvasGroup") then table.insert(toasts, c) end
    end
    table.sort(toasts, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
    while #toasts >= MAX_TOASTS do
        table.remove(toasts, 1):Destroy()
    end

    local toast = Instance.new("CanvasGroup")
    toast.Name = "Toast"
    toast.LayoutOrder = self._n
    toast.AutomaticSize = Enum.AutomaticSize.X
    toast.Size = UDim2.fromOffset(0, 50)
    toast.BackgroundColor3 = Color3.new(1, 1, 1)      -- (v3.2) the gradient below carries the colour
    toast.BackgroundTransparency = 0.04
    toast.GroupTransparency = 1
    toast.Parent = self._container
    UITheme.corner(toast, 16)
    -- v3.2: a glow of the toast's colour on the left, fading into night purple
    local g = Instance.new("UIGradient")
    g.Rotation = 0
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, T.bg:Lerp(accent, 0.45)),
        ColorSequenceKeypoint.new(0.35, T.bg),
        ColorSequenceKeypoint.new(1, T.bgDeep),
    })
    g.Parent = toast

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 6, 1, -16)
    bar.Position = UDim2.fromOffset(10, 8)
    bar.BackgroundColor3 = accent
    bar.BorderSizePixel = 0
    bar.Parent = toast
    UITheme.corner(bar, 3)

    local label = UITheme.label({
        Text = text,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.new(0, 0, 1, 0),
        Position = UDim2.fromOffset(26, 0),
        FontFace = UITheme.F.display,
        TextSize = 21,
        TextColor3 = T.text,
    })
    label.Parent = toast
    local pad = Instance.new("UIPadding")
    pad.PaddingRight = UDim.new(0, 44)   -- room for the 24px left inset + breathing space
    pad.Parent = toast

    local scale = Instance.new("UIScale")
    scale.Scale = 0.9
    scale.Parent = toast
    TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { GroupTransparency = 0 }):Play()
    TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Scale = 1 }):Play()

    task.delay(duration, function()
        if not toast.Parent then return end
        local out = TweenService:Create(toast, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { GroupTransparency = 1 })
        out:Play()
        out.Completed:Wait()
        toast:Destroy()
    end)
end

function Notifications:start()
    self:_buildContainer()
    local notifyRemote = Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent")
    if notifyRemote then
        notifyRemote.OnClientEvent:Connect(function(payload)
            payload = type(payload) == "table" and payload or {}
            self:show(payload.text or "", payload.color or "white", payload.duration or 3)
        end)
    end
    print("[HEIST CREW] Notifications mounted ✅")
end

return Notifications
