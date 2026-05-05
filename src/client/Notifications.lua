--[[
    HEIST CREW — Notifications (toast system)
    ────────────────────────────────────────────────
    Shows top-center sliding toast messages whenever the server fires
    the Notify remote.

    Server fires:  notifyRemote:FireClient(player, {text=..., color="green"|"red"|"gold"|"white", duration=3})

    PUBLIC API:
        Notifications:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Notifications = {}

local localPlayer = Players.LocalPlayer

local COLOR_MAP = {
    green = Color3.fromRGB(34, 197, 94),
    red   = Color3.fromRGB(239, 68, 68),
    gold  = Color3.fromRGB(234, 179, 8),
    white = Color3.fromRGB(255, 255, 255),
}

function Notifications:_buildContainer()
    local playerGui = localPlayer:WaitForChild("PlayerGui")

    local existing = playerGui:FindFirstChild("ToastNotifications")
    if existing then existing:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "ToastNotifications"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = playerGui

    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(0, 500, 1, 0)
    container.Position = UDim2.new(0.5, -250, 0, 100)
    container.BackgroundTransparency = 1
    container.Parent = screen

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 8)
    layout.Parent = container

    self._container = container
end

function Notifications:show(text, colorName, duration)
    if not self._container then return end
    duration = duration or 3
    local color = COLOR_MAP[colorName] or COLOR_MAP.white

    local toast = Instance.new("Frame")
    toast.Name = "Toast"
    toast.Size = UDim2.new(0, 0, 0, 50)
    toast.AutomaticSize = Enum.AutomaticSize.X
    toast.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
    toast.BackgroundTransparency = 0.1
    toast.BorderSizePixel = 0
    toast.LayoutOrder = -tick()  -- newest on top
    toast.Parent = self._container

    local corner = Instance.new("UICorner", toast)
    corner.CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke", toast)
    stroke.Color = color
    stroke.Thickness = 2

    local padding = Instance.new("UIPadding", toast)
    padding.PaddingLeft = UDim.new(0, 20)
    padding.PaddingRight = UDim.new(0, 20)

    local label = Instance.new("TextLabel", toast)
    label.Size = UDim2.new(0, 0, 1, 0)
    label.AutomaticSize = Enum.AutomaticSize.X
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color
    label.Font = Enum.Font.GothamBold
    label.TextSize = 22
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center

    -- Slide in from above
    toast.Position = UDim2.new(0.5, 0, -0.1, 0)
    toast.AnchorPoint = Vector2.new(0.5, 0)
    TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0, 0),
    }):Play()

    -- Auto-fade out
    task.delay(duration, function()
        if not toast.Parent then return end
        local fadeTween = TweenService:Create(toast, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 1,
        })
        fadeTween:Play()
        TweenService:Create(label, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
        TweenService:Create(stroke, TweenInfo.new(0.4), {Transparency = 1}):Play()
        fadeTween.Completed:Wait()
        toast:Destroy()
    end)
end

function Notifications:start()
    self:_buildContainer()

    local notifyRemote = Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent")
    notifyRemote.OnClientEvent:Connect(function(payload)
        self:show(payload.text or "", payload.color or "white", payload.duration or 3)
    end)
    print("[HEIST CREW] Notifications mounted ✅")
end

return Notifications
