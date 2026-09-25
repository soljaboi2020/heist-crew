--[[
    HEIST CREW — BriefingUI  (v1.1)
    ────────────────────────────────────────────────
    1. THE BRIEFING — press E on the Boss. The camera leaves your character
       and slowly glides over three shots (the blueprint, the TV, the garage
       door) while the Boss's lines for the selected job type out in a
       subtitle bar (Constants.JOBS[..].briefing). Skip with the button,
       Space or gamepad B. At the end: a big READY UP button.
    2. THE DROP-IN — when the server fires LaunchJob:
         phase "fade"  → screen fades to black (server teleports the crew)
         phase "title" → fades back in on a title card:
                          VILLA ROSA / MASKS ON. THE JOB IS ON.
    Cinematic bars (letterbox) during both, so it reads as a cut-scene.

    PUBLIC API: BriefingUI:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ContextActionService = game:GetService("ContextActionService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local BriefingUI = {}
local localPlayer = Players.LocalPlayer

-- v1.2: shots inside The Vault (club HQ): holo table, job screen, DJ stage, garage bay
local HF = Constants.WORLD.HUB_FLOOR
local TB = Constants.WORLD.HUB_TABLE
local SHOTS = {
    { from = Vector3.new(TB.x - 8, HF + 11, TB.z + 7), to = Vector3.new(TB.x, HF + 3.4, TB.z), drift = Vector3.new(8, 0, 0) },
    { from = Vector3.new(TB.x + 6, HF + 10, TB.z + 4), to = Vector3.new(TB.x, HF + 13, TB.z - 9), drift = Vector3.new(-6, 0, 0) },
    { from = Vector3.new(0, HF + 6, 30), to = Vector3.new(0, HF + 9, 2), drift = Vector3.new(0, 2, -5) },
    { from = Vector3.new(-2, HF + 7, 42), to = Vector3.new(-17, HF + 3, 52), drift = Vector3.new(-3, 0, 2) },
}
local LINE_TIME = 4.2

local function jobCfg()
    local id = ReplicatedStorage:GetAttribute("ActiveJob")
    for _, j in ipairs(Constants.JOBS) do if j.id == id then return j end end
    return Constants.JOBS[1]
end

function BriefingUI:_build()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("BriefingUI")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "BriefingUI"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 20
    screen.Parent = pg

    -- letterbox bars
    local bars = {}
    for i, anchor in ipairs({ 0, 1 }) do
        local b = Instance.new("Frame")
        b.BackgroundColor3 = Color3.new(0, 0, 0)
        b.BorderSizePixel = 0
        b.AnchorPoint = Vector2.new(0, anchor)
        b.Position = UDim2.fromScale(0, anchor)
        b.Size = UDim2.new(1, 0, 0, 0)
        b.ZIndex = 5
        b.Parent = screen
        bars[i] = b
    end

    -- subtitle
    local sub = UITheme.panel({ Name = "Subtitle", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110),
        Size = UDim2.fromOffset(760, 96), Visible = false, radius = 16, transparency = 0.1 })
    sub.ZIndex = 6
    sub.Parent = screen
    UITheme.caption("The Boss", { Position = UDim2.fromOffset(22, 12), Size = UDim2.new(1, -44, 0, 14),
        TextColor3 = T.gold, ZIndex = 7 }).Parent = sub
    local line = UITheme.label({ Position = UDim2.fromOffset(22, 30), Size = UDim2.new(1, -44, 0, 56),
        TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = UITheme.F.bold, TextSize = 21, ZIndex = 7 })
    line.Parent = sub
    local cons = Instance.new("UISizeConstraint")
    cons.MaxSize = Vector2.new(760, 96)
    cons.Parent = sub

    local skip = Instance.new("TextButton")
    skip.Name = "Skip"
    skip.AnchorPoint = Vector2.new(1, 1)
    skip.Position = UDim2.new(1, -20, 1, -120)   -- (v1.1) bottom-right, clear of the JOB card
    skip.Size = UDim2.fromOffset(110, 36)
    skip.BackgroundColor3 = T.bg
    skip.BackgroundTransparency = 0.2
    skip.Text = "SKIP  ›"
    skip.TextColor3 = T.text
    skip.FontFace = UITheme.F.bold
    skip.TextSize = 15
    skip.AutoButtonColor = true
    skip.Visible = false
    skip.ZIndex = 8
    skip.Parent = screen
    UITheme.corner(skip, 18)
    UITheme.stroke(skip)

    -- READY UP card after the briefing
    local readyCard = UITheme.panel({ Name = "Ready", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110),
        Size = UDim2.fromOffset(460, 150), Visible = false, radius = 18, transparency = 0.08 })
    readyCard.ZIndex = 6
    readyCard.Parent = screen
    local rTitle = UITheme.label({ Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 30),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 26, ZIndex = 7 })
    rTitle.Parent = readyCard
    UITheme.label({ Text = "When the whole crew is ready, you roll out together.", Position = UDim2.fromOffset(0, 48),
        Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.medium,
        TextSize = 15, TextColor3 = T.muted, ZIndex = 7 }).Parent = readyCard
    local readyBtn = Instance.new("TextButton")
    readyBtn.AnchorPoint = Vector2.new(0.5, 1)
    readyBtn.Position = UDim2.new(0.5, 0, 1, -18)
    readyBtn.Size = UDim2.fromOffset(220, 48)
    readyBtn.BackgroundColor3 = T.money
    readyBtn.Text = "READY UP"
    readyBtn.TextColor3 = T.bg
    readyBtn.FontFace = UITheme.F.display
    readyBtn.TextSize = 22
    readyBtn.ZIndex = 8
    readyBtn.Parent = readyCard
    UITheme.corner(readyBtn, 24)
    local later = Instance.new("TextButton")
    later.AnchorPoint = Vector2.new(1, 0)
    later.Position = UDim2.new(1, -12, 0, 10)
    later.Size = UDim2.fromOffset(28, 28)
    later.BackgroundTransparency = 1
    later.Text = "✕"
    later.TextColor3 = T.muted
    later.FontFace = UITheme.F.bold
    later.TextSize = 18
    later.ZIndex = 8
    later.Parent = readyCard

    -- black fade + title card for the drop-in
    local black = Instance.new("Frame")
    black.Name = "Fade"
    black.Size = UDim2.fromScale(1, 1)
    black.BackgroundColor3 = Color3.new(0, 0, 0)
    black.BackgroundTransparency = 1
    black.BorderSizePixel = 0
    black.ZIndex = 20
    black.Parent = screen
    local title = Instance.new("CanvasGroup")
    title.AnchorPoint = Vector2.new(0.5, 0.5)
    title.Position = UDim2.fromScale(0.5, 0.42)
    title.Size = UDim2.fromOffset(800, 170)
    title.BackgroundTransparency = 1
    title.GroupTransparency = 1
    title.ZIndex = 21
    title.Parent = screen
    local tName = UITheme.label({ Size = UDim2.new(1, 0, 0, 100), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 96, TextStrokeTransparency = 0.6, TextStrokeColor3 = Color3.new(), ZIndex = 22 })
    tName.Parent = title
    local tSub = UITheme.label({ Text = "MASKS ON.  THE JOB IS ON.", Position = UDim2.fromOffset(0, 104),
        Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
        TextSize = 22, TextColor3 = T.gold, TextStrokeTransparency = 0.6, TextStrokeColor3 = Color3.new(), ZIndex = 22 })
    tSub.Parent = title

    self._ui = { screen = screen, bars = bars, sub = sub, line = line, skip = skip, readyCard = readyCard,
        rTitle = rTitle, readyBtn = readyBtn, later = later, black = black, title = title, tName = tName, tSub = tSub }
end

function BriefingUI:_letterbox(on)
    for _, b in ipairs(self._ui.bars) do
        TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = UDim2.new(1, 0, on and 0.1 or 0, 0) }):Play()
    end
end

function BriefingUI:_showReady()
    local u = self._ui
    local cfg = jobCfg()
    u.rTitle.Text = "READY FOR " .. cfg.name .. "?"
    u.readyCard.Visible = true
end

function BriefingUI:play()
    if self._playing then return end
    self._playing = true
    local u = self._ui
    local cam = workspace.CurrentCamera
    local cfg = jobCfg()
    local lines = cfg.briefing or { cfg.tagline }
    local skipped = false
    local function doSkip() skipped = true end

    u.readyCard.Visible = false
    self:_letterbox(true)
    u.sub.Visible = true
    u.skip.Visible = true
    local skipConn = u.skip.Activated:Connect(doSkip)
    ContextActionService:BindAction("HC_SkipBriefing", function(_, state)
        if state == Enum.UserInputState.Begin then doSkip() end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonB)

    local oldType = cam.CameraType
    cam.CameraType = Enum.CameraType.Scriptable
    for i, text in ipairs(lines) do
        if skipped then break end
        local shot = SHOTS[(i - 1) % #SHOTS + 1]
        cam.CFrame = CFrame.lookAt(shot.from, shot.to)
        if self._camTween then self._camTween:Cancel() end
        self._camTween = TweenService:Create(cam, TweenInfo.new(LINE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            { CFrame = CFrame.lookAt(shot.from + shot.drift, shot.to) })
        self._camTween:Play()
        -- typewriter
        u.line.Text = text
        u.line.MaxVisibleGraphemes = 0
        local n = utf8.len(text) or #text
        local t0 = os.clock()
        while not skipped and os.clock() - t0 < LINE_TIME do
            u.line.MaxVisibleGraphemes = math.min(n, math.floor((os.clock() - t0) * 55))
            task.wait()
        end
        u.line.MaxVisibleGraphemes = -1
    end

    ContextActionService:UnbindAction("HC_SkipBriefing")
    skipConn:Disconnect()
    -- (fix v1.1) stop the last shot's tween or it keeps dragging the camera
    if self._camTween then self._camTween:Cancel() self._camTween = nil end
    cam.CameraType = (oldType == Enum.CameraType.Scriptable) and Enum.CameraType.Custom or oldType
    local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then cam.CameraSubject = hum end
    u.sub.Visible = false
    u.skip.Visible = false
    self:_letterbox(false)
    self._playing = false
    self._briefed = true
    self:_showReady()
end

function BriefingUI:_restoreCamera()
    local cam = workspace.CurrentCamera
    if cam.CameraType == Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Custom end
    local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then cam.CameraSubject = hum end
end

function BriefingUI:_dropIn(payload)
    local u = self._ui
    u.readyCard.Visible = false
    if payload.phase == "travel" then
        -- freight lift: a quick dip to black while the server moves you
        u.black.BackgroundTransparency = 1
        TweenService:Create(u.black, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
        task.delay(0.8, function()
            TweenService:Create(u.black, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
        end)
        return
    end
    if payload.phase == "rollout" then
        -- v1.2: watch the getaway car roll up the ramp in the garage bay
        if self._playing then return end
        self:_letterbox(true)
        local cam = workspace.CurrentCamera
        if typeof(payload.camFrom) == "Vector3" and typeof(payload.camTo) == "Vector3" then
            cam.CameraType = Enum.CameraType.Scriptable
            cam.CFrame = CFrame.lookAt(payload.camFrom, payload.camTo)
            TweenService:Create(cam, TweenInfo.new(2.6, Enum.EasingStyle.Sine),
                { CFrame = CFrame.lookAt(payload.camFrom + Vector3.new(-4, 3, 6), payload.camTo + Vector3.new(0, 6, 8)) }):Play()
        end
        return
    end
    if payload.phase == "fade" then
        self:_letterbox(true)
        TweenService:Create(u.black, TweenInfo.new(0.9), { BackgroundTransparency = 0 }):Play()
    elseif payload.phase == "title" then
        self:_restoreCamera()
        u.tName.Text = payload.jobName or ""
        u.black.BackgroundTransparency = 0
        u.title.GroupTransparency = 1
        TweenService:Create(u.title, TweenInfo.new(0.6), { GroupTransparency = 0 }):Play()
        task.delay(1.4, function()
            TweenService:Create(u.black, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
        end)
        task.delay(3.6, function()
            TweenService:Create(u.title, TweenInfo.new(0.8), { GroupTransparency = 1 }):Play()
            self:_letterbox(false)
        end)
    end
end

function BriefingUI:start()
    self:_build()
    local u = self._ui
    local readyRemote = Remotes.getRemote(Remotes.NAMES.ReadyUp, "RemoteEvent")

    u.readyBtn.Activated:Connect(function()
        if readyRemote then readyRemote:FireServer(true) end   -- SET ready (never toggles off)
        u.readyCard.Visible = false
    end)
    u.later.Activated:Connect(function() u.readyCard.Visible = false end)

    ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if player ~= localPlayer then return end
        if prompt.Name == "Briefing" then
            task.spawn(function() self:play() end)
        end
    end)

    local launch = Remotes.getRemote(Remotes.NAMES.LaunchJob, "RemoteEvent")
    if launch then
        launch.OnClientEvent:Connect(function(payload)
            self:_dropIn(payload or {})
        end)
    end
    print("[HEIST CREW] BriefingUI mounted ✅")
end

return BriefingUI
