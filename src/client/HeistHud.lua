--[[
    HEIST CREW — HeistHud
    ────────────────────────────────────────────────
    v0.7.0 redesign (UITheme). Three things:

      1. ALARM — a red glow that breathes in from the screen edges (a soft
         vignette, not the old four solid red bars).
      2. VAULT CRACK — bottom-centre card: "CRACKING VAULT" + live percent,
         thin gold bar that fills smoothly.
      3. RESULT — centre card when a run ends: HEIST COMPLETE / BUSTED and how
         many of the crew got out. Pops in, holds, fades.

    The escape countdown moved to the objective pill (CrewHud) — one place
    for "what do I do now", instead of a second banner on top of it.

    Listens to: VaultProgress, AlarmTriggered, HeistState remotes.

    PUBLIC API:
        HeistHud:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local HeistHud = {}
local localPlayer = Players.LocalPlayer

local function edgeGlow(parent, rotation, size, position, anchor)
    local f = Instance.new("Frame")
    f.BackgroundColor3 = T.dangerDeep
    f.BorderSizePixel = 0
    f.Size = size
    f.Position = position
    f.AnchorPoint = anchor
    f.Parent = parent
    local g = Instance.new("UIGradient")
    g.Rotation = rotation
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(0.5, 0.75),
        NumberSequenceKeypoint.new(1, 1),
    })
    g.Parent = f
end

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

    -- 1. alarm vignette
    local vignette = Instance.new("CanvasGroup")
    vignette.Name = "AlarmVignette"
    vignette.Size = UDim2.fromScale(1, 1)
    vignette.BackgroundTransparency = 1
    vignette.GroupTransparency = 1
    vignette.Visible = false
    vignette.Parent = screen
    edgeGlow(vignette, 90, UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0), Vector2.new(0, 0))     -- top
    edgeGlow(vignette, -90, UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 1), Vector2.new(0, 1))    -- bottom
    edgeGlow(vignette, 0, UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0))      -- left
    edgeGlow(vignette, 180, UDim2.fromScale(0.16, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0))    -- right

    -- 2. vault crack card
    local crack = UITheme.panel({
        Name = "VaultCrack",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -96),
        Size = UDim2.fromOffset(380, 64),
        Visible = false,
        radius = 14,
    })
    crack.Parent = screen
    UITheme.caption("Drill", { Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -36, 0, 14),
        TextColor3 = T.gold }).Parent = crack
    local pct = UITheme.label({ Text = "0%", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 8),
        Size = UDim2.fromOffset(80, 22), TextXAlignment = Enum.TextXAlignment.Right, FontFace = UITheme.F.mono, TextSize = 18 })
    pct.Parent = crack
    local track = Instance.new("Frame")
    track.Position = UDim2.new(0, 18, 0, 40)
    track.Size = UDim2.new(1, -36, 0, 8)
    track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    track.BackgroundTransparency = 0.88
    track.BorderSizePixel = 0
    track.Parent = crack
    UITheme.corner(track, 4)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = T.gold
    fill.BorderSizePixel = 0
    fill.Parent = track
    UITheme.corner(fill, 4)
    local fg = Instance.new("UIGradient")
    fg.Color = ColorSequence.new(Color3.fromRGB(245, 158, 11), Color3.fromRGB(253, 224, 71))
    fg.Parent = fill

    -- 3. result card
    local result = Instance.new("CanvasGroup")
    result.Name = "Result"
    result.AnchorPoint = Vector2.new(0.5, 0.5)
    result.Position = UDim2.fromScale(0.5, 0.42)
    result.Size = UDim2.fromOffset(460, 170)
    result.BackgroundColor3 = T.bg
    result.BackgroundTransparency = 0.1
    result.GroupTransparency = 1
    result.Visible = false
    result.Parent = screen
    UITheme.corner(result, 18)
    UITheme.stroke(result)
    local rScale = Instance.new("UIScale")
    rScale.Parent = result
    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(1, 0, 0, 4)
    accent.BorderSizePixel = 0
    accent.Parent = result
    local rCaption = UITheme.caption("", { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Center })
    rCaption.Parent = result
    local rTitle = UITheme.label({ Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 56),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 50 })
    rTitle.Parent = result
    local rSub = UITheme.label({ Position = UDim2.fromOffset(0, 108), Size = UDim2.new(1, 0, 0, 24),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.medium, TextSize = 19, TextColor3 = T.muted })
    rSub.Parent = result

    self._vignette = vignette
    self._crack, self._fill, self._pct = crack, fill, pct
    self._result, self._rScale, self._rAccent, self._rTitle, self._rSub = result, rScale, accent, rTitle, rSub
    self._rCaption = rCaption
end

function HeistHud:setAlarm(active)
    if self._pulse then self._pulse:Disconnect() self._pulse = nil end
    local v = self._vignette
    if not active then
        TweenService:Create(v, TweenInfo.new(0.6), { GroupTransparency = 1 }):Play()
        task.delay(0.6, function() if v.GroupTransparency > 0.95 then v.Visible = false end end)
        return
    end
    v.Visible = true
    local t0 = os.clock()
    self._pulse = RunService.RenderStepped:Connect(function()
        local wave = (math.sin((os.clock() - t0) * 4.2) + 1) / 2   -- slow breathe, ~0.7 Hz
        v.GroupTransparency = 0.15 + wave * 0.45
    end)
end

function HeistHud:setVaultProgress(progress)
    local card = self._crack
    if progress <= 0 then
        card.Visible = false
        self._fill.Size = UDim2.fromScale(0, 1)
        return
    end
    card.Visible = true
    TweenService:Create(self._fill, TweenInfo.new(0.2, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1) }):Play()
    self._pct.Text = string.format("%d%%", math.floor(progress * 100 + 0.5))
    if progress >= 1 then
        self._pct.Text = "OPEN"
        self._pct.TextColor3 = T.money
        task.delay(0.9, function()
            card.Visible = false
            self._pct.TextColor3 = T.text
        end)
    end
end

function HeistHud:showResult(win, payload)
    local r = self._result
    self._rTitle.Text = win and "HEIST COMPLETE" or "BUSTED"
    self._rTitle.TextColor3 = win and T.money or T.danger
    self._rAccent.BackgroundColor3 = win and T.money or T.danger
    local total = payload.crewSize or 0
    local escaped = payload.escaped
    local n = type(escaped) == "table" and #escaped or tonumber(escaped) or 0
    local each = tonumber(payload.each) or 0
    if win and each > 0 then
        self._rSub.Text = string.format("%d of %d made it out  ·  %s each", n, math.max(total, n), UITheme.money(each))
    elseif win then
        self._rSub.Text = "Clean getaway — but the car was empty"
    else
        local why = ({ busted = "The cops boxed in the car.", time = "Out of time.", caught = "Everyone got caught.",
            timeout = "The Boss called it off.", abandoned = "The crew bailed." })[payload.result or ""]
        self._rSub.Text = why or "Nobody made it to the marina."
    end
    local jobName = game:GetService("ReplicatedStorage"):GetAttribute("ActiveJob")
    self._rCaption.Text = jobName == "jewelry" and "DIAMOND DOLLS" or "VILLA ROSA"

    r.Visible = true
    r.GroupTransparency = 1
    self._rScale.Scale = 0.86
    TweenService:Create(r, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
    TweenService:Create(self._rScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
    local token = {}
    self._resultToken = token
    task.delay(4, function()
        if self._resultToken ~= token then return end
        local out = TweenService:Create(r, TweenInfo.new(0.5), { GroupTransparency = 1 })
        out:Play()
        out.Completed:Wait()
        if self._resultToken == token then r.Visible = false end
    end)
end

function HeistHud:setHeistState(stateName, payload)
    if stateName == "COMPLETE" then
        self:showResult(true, payload)
    elseif stateName == "FAILED" then
        self:showResult(false, payload)
    end
end

function HeistHud:start()
    self:_buildUi()

    Remotes.getRemote(Remotes.NAMES.VaultProgress, "RemoteEvent").OnClientEvent:Connect(function(progress)
        self:setVaultProgress(progress)
    end)
    Remotes.getRemote(Remotes.NAMES.AlarmTriggered, "RemoteEvent").OnClientEvent:Connect(function(active)
        self:setAlarm(active)
    end)
    Remotes.getRemote(Remotes.NAMES.HeistState, "RemoteEvent").OnClientEvent:Connect(function(stateName, payload)
        self:setHeistState(stateName, payload or {})
    end)

    print("[HEIST CREW] HeistHud mounted ✅")
end

return HeistHud
