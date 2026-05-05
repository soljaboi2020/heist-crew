--[[
    HEIST CREW — CashHud (client UI)
    ────────────────────────────────────────────────
    The green cash counter pinned to the top-right of the player's screen.

    Mounts a ScreenGui at startup, listens for the `CashUpdated` remote
    event from the server, and pops a brief animation when the number
    increases (white flash + scale bounce).

    PUBLIC API:
        CashHud:start()  — call once on client startup
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CashHud = {}

local localPlayer = Players.LocalPlayer
local currentCash = 0

-- Format an integer with comma separators ("1234567" → "$1,234,567")
local function format(amount)
    local s = tostring(math.floor(amount))
    while true do
        local k
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return "$" .. s
end

function CashHud:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")

    -- Remove any old HUD (if Rojo hot-reloaded the script)
    local existing = playerGui:FindFirstChild("CashHud")
    if existing then existing:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "CashHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "Container"
    frame.Size = UDim2.new(0, 220, 0, 70)
    frame.Position = UDim2.new(1, -240, 0, 24)
    frame.AnchorPoint = Vector2.new(0, 0)
    frame.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Parent = screen

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(34, 197, 94)
    stroke.Thickness = 2
    stroke.Transparency = 0.25
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = frame

    -- Cash icon (just a styled $ sign)
    local icon = Instance.new("TextLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 36, 1, 0)
    icon.Position = UDim2.new(0, 12, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Text = "💰"
    icon.TextColor3 = Color3.fromRGB(34, 197, 94)
    icon.Font = Enum.Font.GothamBlack
    icon.TextScaled = true
    icon.TextXAlignment = Enum.TextXAlignment.Left
    icon.Parent = frame

    local label = Instance.new("TextLabel")
    label.Name = "CashLabel"
    label.Size = UDim2.new(1, -60, 1, 0)
    label.Position = UDim2.new(0, 52, 0, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(34, 197, 94)
    label.Font = Enum.Font.GothamBlack
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Right
    label.Text = "$0"
    label.Parent = frame

    local sizeConstraint = Instance.new("UITextSizeConstraint")
    sizeConstraint.MaxTextSize = 36
    sizeConstraint.MinTextSize = 12
    sizeConstraint.Parent = label

    self._screen = screen
    self._frame = frame
    self._label = label
    self._stroke = stroke
end

function CashHud:setCash(newAmount, animate)
    local oldAmount = currentCash
    currentCash = newAmount
    if not self._label then return end

    self._label.Text = format(newAmount)

    if animate and newAmount > oldAmount then
        -- Pop animation: scale bounce + white flash + glow stroke
        local label = self._label
        local frame = self._frame
        local stroke = self._stroke

        local originalSize = UDim2.new(0, 220, 0, 70)
        frame.Size = UDim2.new(0, 240, 0, 78)
        TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = originalSize,
        }):Play()

        local origLabelColor = Color3.fromRGB(34, 197, 94)
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            TextColor3 = origLabelColor,
        }):Play()

        stroke.Transparency = 0
        TweenService:Create(stroke, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Transparency = 0.25,
        }):Play()
    end
end

function CashHud:start()
    self:_buildUi()

    local cashRemote = Remotes.getRemote("CashUpdated", "RemoteEvent")
    if not cashRemote then
        warn("[CashHud] CashUpdated remote not found — server may not be ready")
        return
    end

    cashRemote.OnClientEvent:Connect(function(newAmount)
        self:setCash(newAmount, true)
    end)

    print("[HEIST CREW] CashHud mounted ✅")
end

return CashHud
