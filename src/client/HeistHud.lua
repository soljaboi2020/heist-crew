--[[
    HEIST CREW — HeistHud (vault progress + alarm border)
    ────────────────────────────────────────────────
    Two UI elements:
      1. Vault progress bar (bottom-center) — fills as you hold E on the vault
      2. Alarm border (full-screen red flashing border) — when alarm is active

    Listens to:
      - VaultProgress remote: 0..1 fills the bar; 0 hides it
      - AlarmTriggered remote: true → red border flashes; false → hides
      - HeistState remote: top banner shows current state

    PUBLIC API:
        HeistHud:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HeistHud = {}

local localPlayer = Players.LocalPlayer

function HeistHud:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")

    local existing = playerGui:FindFirstChild("HeistHud")
    if existing then existing:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "HeistHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = playerGui

    -- ── Alarm border (full-screen red overlay, hidden by default) ──
    local alarmBorder = Instance.new("Frame")
    alarmBorder.Name = "AlarmBorder"
    alarmBorder.Size = UDim2.new(1, 0, 1, 0)
    alarmBorder.BackgroundTransparency = 1
    alarmBorder.BorderSizePixel = 0
    alarmBorder.Visible = false
    alarmBorder.ZIndex = 1
    alarmBorder.Parent = screen

    -- 4 colored bars (top, bottom, left, right) for the border effect
    local function makeBar(side)
        local bar = Instance.new("Frame")
        bar.Name = side
        bar.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
        bar.BorderSizePixel = 0
        bar.BackgroundTransparency = 0.3
        bar.Parent = alarmBorder
        return bar
    end
    local topBar = makeBar("Top")
    topBar.Size = UDim2.new(1, 0, 0, 12)
    topBar.Position = UDim2.new(0, 0, 0, 0)
    local bottomBar = makeBar("Bottom")
    bottomBar.Size = UDim2.new(1, 0, 0, 12)
    bottomBar.Position = UDim2.new(0, 0, 1, -12)
    local leftBar = makeBar("Left")
    leftBar.Size = UDim2.new(0, 12, 1, 0)
    leftBar.Position = UDim2.new(0, 0, 0, 0)
    local rightBar = makeBar("Right")
    rightBar.Size = UDim2.new(0, 12, 1, 0)
    rightBar.Position = UDim2.new(1, -12, 0, 0)

    -- Center "ALARM" text
    local alarmText = Instance.new("TextLabel")
    alarmText.Name = "AlarmText"
    alarmText.Size = UDim2.new(0, 600, 0, 80)
    alarmText.Position = UDim2.new(0.5, -300, 0, 60)
    alarmText.BackgroundTransparency = 1
    alarmText.Text = "🚨 ALARM TRIGGERED — RUN TO THE GETAWAY 🚨"
    alarmText.TextColor3 = Color3.fromRGB(239, 68, 68)
    alarmText.Font = Enum.Font.GothamBlack
    alarmText.TextScaled = true
    alarmText.TextStrokeTransparency = 0
    alarmText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    alarmText.Parent = alarmBorder

    -- ── Vault progress bar (bottom-center, hidden by default) ──
    local progressFrame = Instance.new("Frame")
    progressFrame.Name = "VaultProgress"
    progressFrame.Size = UDim2.new(0, 360, 0, 36)
    progressFrame.Position = UDim2.new(0.5, -180, 1, -120)
    progressFrame.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
    progressFrame.BackgroundTransparency = 0.15
    progressFrame.BorderSizePixel = 0
    progressFrame.Visible = false
    progressFrame.ZIndex = 2
    progressFrame.Parent = screen

    Instance.new("UICorner", progressFrame).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", progressFrame)
    stroke.Color = Color3.fromRGB(234, 179, 8)
    stroke.Thickness = 2

    local progressFill = Instance.new("Frame")
    progressFill.Name = "Fill"
    progressFill.Size = UDim2.new(0, 0, 1, -6)
    progressFill.Position = UDim2.new(0, 3, 0, 3)
    progressFill.BackgroundColor3 = Color3.fromRGB(234, 179, 8)
    progressFill.BorderSizePixel = 0
    progressFill.Parent = progressFrame
    Instance.new("UICorner", progressFill).CornerRadius = UDim.new(0, 6)

    local progressLabel = Instance.new("TextLabel")
    progressLabel.Size = UDim2.new(1, 0, 1, 0)
    progressLabel.BackgroundTransparency = 1
    progressLabel.Text = "🔧 CRACKING VAULT..."
    progressLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    progressLabel.Font = Enum.Font.GothamBlack
    progressLabel.TextSize = 18
    progressLabel.ZIndex = 3
    progressLabel.Parent = progressFrame

    -- ── Heist state banner (top-center, only shows during ESCAPING/COMPLETE/FAILED) ──
    local stateBanner = Instance.new("Frame")
    stateBanner.Name = "StateBanner"
    stateBanner.Size = UDim2.new(0, 480, 0, 56)
    stateBanner.Position = UDim2.new(0.5, -240, 0, 28)
    stateBanner.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
    stateBanner.BackgroundTransparency = 0.1
    stateBanner.BorderSizePixel = 0
    stateBanner.Visible = false
    stateBanner.ZIndex = 4
    stateBanner.Parent = screen

    Instance.new("UICorner", stateBanner).CornerRadius = UDim.new(0, 12)
    local bannerStroke = Instance.new("UIStroke", stateBanner)
    bannerStroke.Color = Color3.fromRGB(239, 68, 68)
    bannerStroke.Thickness = 2

    local stateLabel = Instance.new("TextLabel")
    stateLabel.Size = UDim2.new(1, -16, 1, 0)
    stateLabel.Position = UDim2.new(0, 8, 0, 0)
    stateLabel.BackgroundTransparency = 1
    stateLabel.Text = ""
    stateLabel.TextColor3 = Color3.fromRGB(239, 68, 68)
    stateLabel.Font = Enum.Font.GothamBlack
    stateLabel.TextSize = 22
    stateLabel.Parent = stateBanner

    self._screen = screen
    self._alarmBorder = alarmBorder
    self._alarmText = alarmText
    self._progressFrame = progressFrame
    self._progressFill = progressFill
    self._progressLabel = progressLabel
    self._stateBanner = stateBanner
    self._stateLabel = stateLabel
    self._bannerStroke = bannerStroke
end

-- Pulse the alarm border (red on/off cycle)
function HeistHud:_startAlarmPulse()
    if self._alarmHeartbeat then self._alarmHeartbeat:Disconnect() end
    local startTime = os.clock()
    self._alarmHeartbeat = RunService.Heartbeat:Connect(function()
        if not self._alarmBorder.Visible then return end
        local elapsed = os.clock() - startTime
        local pulse = (math.sin(elapsed * 6) + 1) / 2  -- 0..1 sine wave at ~1Hz
        local trans = 0.2 + pulse * 0.5
        for _, child in ipairs(self._alarmBorder:GetChildren()) do
            if child:IsA("Frame") then
                child.BackgroundTransparency = trans
            end
        end
    end)
end

function HeistHud:setAlarm(active)
    self._alarmBorder.Visible = active
    if active then
        self:_startAlarmPulse()
    else
        if self._alarmHeartbeat then
            self._alarmHeartbeat:Disconnect()
            self._alarmHeartbeat = nil
        end
    end
end

function HeistHud:setVaultProgress(progress)
    if progress <= 0 then
        self._progressFrame.Visible = false
        self._progressFill.Size = UDim2.new(0, 0, 1, -6)
        return
    end
    self._progressFrame.Visible = true
    local targetWidth = math.floor(354 * progress)
    self._progressFill.Size = UDim2.new(0, targetWidth, 1, -6)
    if progress >= 1 then
        self._progressLabel.Text = "✅ VAULT CRACKED!"
        task.delay(0.8, function()
            if self._progressFrame then self._progressFrame.Visible = false end
        end)
    else
        self._progressLabel.Text = string.format("🔧 CRACKING... %d%%", math.floor(progress * 100))
    end
end

function HeistHud:setHeistState(stateName, payload)
    if stateName == "ESCAPING" then
        self._stateBanner.Visible = true
        self._stateLabel.Text = string.format("🏃 ESCAPE: %ds left!", payload.escapeSeconds or 0)
        self._bannerStroke.Color = Color3.fromRGB(239, 68, 68)
        self._stateLabel.TextColor3 = Color3.fromRGB(239, 68, 68)

        -- Live countdown
        if self._stateCountdown then task.cancel(self._stateCountdown) end
        self._stateCountdown = task.spawn(function()
            local startTime = os.clock()
            local total = payload.escapeSeconds or 60
            while self._stateBanner.Visible do
                local remaining = math.max(0, total - (os.clock() - startTime))
                self._stateLabel.Text = string.format("🏃 ESCAPE: %ds left!", math.ceil(remaining))
                if remaining <= 0 then break end
                task.wait(0.5)
            end
        end)
    elseif stateName == "COMPLETE" then
        self._stateBanner.Visible = true
        self._stateLabel.Text = "🎉 HEIST COMPLETE!"
        self._bannerStroke.Color = Color3.fromRGB(34, 197, 94)
        self._stateLabel.TextColor3 = Color3.fromRGB(34, 197, 94)
        task.delay(4, function()
            if self._stateBanner then self._stateBanner.Visible = false end
        end)
    elseif stateName == "FAILED" then
        self._stateBanner.Visible = true
        self._stateLabel.Text = "❌ HEIST FAILED"
        self._bannerStroke.Color = Color3.fromRGB(239, 68, 68)
        self._stateLabel.TextColor3 = Color3.fromRGB(239, 68, 68)
        task.delay(3, function()
            if self._stateBanner then self._stateBanner.Visible = false end
        end)
    elseif stateName == "IDLE" then
        self._stateBanner.Visible = false
    end
end

function HeistHud:start()
    self:_buildUi()

    local progressRemote = Remotes.getRemote(Remotes.NAMES.VaultProgress, "RemoteEvent")
    progressRemote.OnClientEvent:Connect(function(progress)
        self:setVaultProgress(progress)
    end)

    local alarmRemote = Remotes.getRemote(Remotes.NAMES.AlarmTriggered, "RemoteEvent")
    alarmRemote.OnClientEvent:Connect(function(active)
        self:setAlarm(active)
    end)

    local stateRemote = Remotes.getRemote(Remotes.NAMES.HeistState, "RemoteEvent")
    stateRemote.OnClientEvent:Connect(function(stateName, payload)
        self:setHeistState(stateName, payload or {})
    end)

    print("[HEIST CREW] HeistHud mounted ✅")
end

return HeistHud
