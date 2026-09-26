--[[
    HEIST CREW — BriefingUI  (v1.1)
    ────────────────────────────────────────────────
    1. THE BRIEFING — press F on the Boss. The camera leaves your character
       and slowly glides over three shots (the blueprint, the TV, the garage
       door) while the Boss's lines for the selected job type out in a
       subtitle bar (Constants.JOBS[..].briefing). Skip with the button,
       Space or gamepad B. At the end (v2.0): a card that says what to do
       next — "Walk into the VILLA ROSA door to start" — with a GOT IT button.
       (The old READY UP button is gone: the heist DOORS in the lobby start a
       run now. The ReadyUp remote isn't fired from here any more.)
       Sets the LOCAL player attribute HeardPlan = true (CrewHud's step 3,
       WaypointHud dims the Boss marker).
    2. THE DROP-IN — when the server fires LaunchJob:
         phase "fade"  → screen fades to black (server teleports the crew)
         phase "title" → fades back in on a title card:
                          VILLA ROSA / MASKS ON. THE JOB IS ON.
    Cinematic bars (letterbox) during both, so it reads as a cut-scene.

    v2.2 THE REAL TARGET: if the server published camera shots for the job
    (ReplicatedStorage.BriefingShots.<jobId>, see server/BriefingShots.lua),
    the briefing flies over the ACTUAL building instead of the club: line 1 =
    the wide establishing shot, then every line picks the shot it talks about
    (camera/breaker → breaker, keycard/locked → keycard, laser → lasers,
    vault/drill/safe → vault, car/escape/boats → car, door/sneak → side door,
    anything else → the next shot not shown yet). Each shot cuts in with a
    quick dip and glides from→to (Quad InOut). A caption chip names the shot
    ("VILLA ROSA · THE STAFF DOOR"); the other HUD ScreenGuis are hidden for
    the fly-through and put back after. No shots → the old club camera.

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
    -- v2.0: the heist doors in the lobby (east wall, x 44, z 74..110)
    { from = Vector3.new(22, HF + 8, 80), to = Vector3.new(44, HF + 6, 94), drift = Vector3.new(0, 0, 8) },
}
local LINE_TIME = 4.2

local function jobCfg()
    local id = ReplicatedStorage:GetAttribute("ActiveJob")
    for _, j in ipairs(Constants.JOBS) do if j.id == id then return j end end
    return Constants.JOBS[1]
end

-- v2.2: the real-building shots published by the server (nil if none)
local function loadShots(jobId)
    local root = ReplicatedStorage:FindFirstChild("BriefingShots")
    local jf = root and jobId and root:FindFirstChild(jobId)
    if not jf then return nil end
    local list = {}
    for _, sf in ipairs(jf:GetChildren()) do
        local from, to = sf:GetAttribute("From"), sf:GetAttribute("To")
        if typeof(from) == "CFrame" and typeof(to) == "CFrame" then
            table.insert(list, {
                order = tonumber(sf:GetAttribute("Order")) or tonumber(sf.Name) or 99,
                from = from, to = to,
                label = tostring(sf:GetAttribute("Label") or ""),
                tag = tostring(sf:GetAttribute("Tag") or ""),
            })
        end
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    return #list > 0 and list or nil
end

-- which shot a Boss line is about (first rule that matches wins)
local LINE_RULES = {
    { tag = "breaker", words = { "camera", "cameras", "breaker" } },
    { tag = "keycard", words = { "keycard", "locked" } },
    { tag = "lasers",  words = { "laser", "lasers" } },
    { tag = "vault",   words = { "vault", "drill", "safe" } },
    { tag = "car",     words = { "car", "cars", "escape", "boat", "boats" } },
    { tag = "side",    words = { "door", "sneak" } },
}
local function lineTag(text)
    local low = string.lower(text or "")
    for _, rule in ipairs(LINE_RULES) do
        for _, w in ipairs(rule.words) do
            if string.find(low, "%f[%a]" .. w .. "%f[%A]") then return rule.tag end
        end
    end
    return nil
end

-- one shot per line: { shot, reversed }. Line 1 is always the wide shot.
local function planShots(lines, shots)
    local byTag, used, plan = {}, {}, {}
    for _, sh in ipairs(shots) do if not byTag[sh.tag] then byTag[sh.tag] = sh end end
    local function nextUnused()
        for _, sh in ipairs(shots) do if not used[sh] then return sh end end
        return nil
    end
    for i, text in ipairs(lines) do
        local sh
        if i == 1 then sh = byTag.wide or byTag.front or shots[1] end
        if not sh then
            local tag = lineTag(text)
            sh = tag and byTag[tag] or nil
        end
        sh = sh or nextUnused() or shots[(i - 1) % #shots + 1]
        -- a shot we've already shown plays backwards (to → from) for variety
        plan[i] = { shot = sh, reversed = used[sh] == true }
        used[sh] = true
    end
    return plan
end
BriefingUI._lineTag = lineTag         -- (exposed for tests)
BriefingUI._planShots = planShots
BriefingUI._loadShots = loadShots

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
    -- (v2.1) chunky card + the Boss's hat badge, scaled with the HUD
    local sub = UITheme.card({ Name = "Subtitle", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90),
        Size = UDim2.fromOffset(760, 104), Visible = false, radius = 18, transparency = 0.06, accent = T.gold })
    sub.ZIndex = 6
    sub.Parent = screen
    UITheme.autoScale(sub)
    local hat = UITheme.badge(UITheme.ICON.boss, T.gold, 56)
    hat.Position = UDim2.fromOffset(16, 22)
    hat.ZIndex = 7
    hat.Parent = sub
    UITheme.caption("The Boss", { Position = UDim2.fromOffset(86, 12), Size = UDim2.new(1, -106, 0, 16),
        TextSize = 13, TextColor3 = T.gold, ZIndex = 7 }).Parent = sub
    local line = UITheme.label({ Position = UDim2.fromOffset(86, 30), Size = UDim2.new(1, -106, 0, 64),
        TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = UITheme.F.bold, TextSize = 22, ZIndex = 7 })
    line.Parent = sub
    local cons = Instance.new("UISizeConstraint")
    cons.MaxSize = Vector2.new(760, 104)
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
    UITheme.stroke(skip, T.line, 0.6, 1.5)
    UITheme.autoScale(skip)

    -- v2.2: caption chip for the real-building shots ("VILLA ROSA · THE STAFF DOOR")
    local chip = Instance.new("Frame")
    chip.Name = "ShotCaption"
    chip.AnchorPoint = Vector2.new(0.5, 0)
    chip.Position = UDim2.new(0.5, 0, 0.1, 14)
    chip.Size = UDim2.fromOffset(360, 34)
    chip.AutomaticSize = Enum.AutomaticSize.X
    chip.BackgroundColor3 = T.bg
    chip.BackgroundTransparency = 0.15
    chip.Visible = false
    chip.ZIndex = 6
    chip.Parent = screen
    UITheme.corner(chip, 17)
    UITheme.stroke(chip, T.gold, 0.35, 1.5)
    UITheme.autoScale(chip)
    local chipPad = Instance.new("UIPadding")
    chipPad.PaddingLeft = UDim.new(0, 16)
    chipPad.PaddingRight = UDim.new(0, 18)
    chipPad.Parent = chip
    local chipDot = Instance.new("Frame")
    chipDot.Name = "Rec"
    chipDot.AnchorPoint = Vector2.new(0, 0.5)
    chipDot.Position = UDim2.new(0, 0, 0.5, 0)
    chipDot.Size = UDim2.fromOffset(10, 10)
    chipDot.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
    chipDot.BorderSizePixel = 0
    chipDot.ZIndex = 7
    chipDot.Parent = chip
    UITheme.corner(chipDot, 5)
    local chipText = UITheme.label({ Position = UDim2.fromOffset(18, 0), Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X, FontFace = UITheme.F.bold, TextSize = 16, TextColor3 = T.gold, ZIndex = 7 })
    chipText.Parent = chip
    -- a quick dip to black between shots (under the bars + subtitle)
    local cut = Instance.new("Frame")
    cut.Name = "Cut"
    cut.Size = UDim2.fromScale(1, 1)
    cut.BackgroundColor3 = Color3.new(0, 0, 0)
    cut.BackgroundTransparency = 1
    cut.BorderSizePixel = 0
    cut.ZIndex = 4
    cut.Parent = screen

    -- READY UP card after the briefing
    local readyCard = UITheme.card({ Name = "Ready", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90),
        Size = UDim2.fromOffset(500, 170), Visible = false, radius = 20, transparency = 0.04, accent = T.money })
    readyCard.ZIndex = 6
    readyCard.Parent = screen
    UITheme.autoScale(readyCard)
    local rTitle = UITheme.label({ Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 30),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 27, ZIndex = 7 })
    rTitle.Parent = readyCard
    local rBody = UITheme.label({ Position = UDim2.fromOffset(20, 48), Size = UDim2.new(1, -40, 0, 36),
        TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, FontFace = UITheme.F.medium,
        TextSize = 17, TextColor3 = T.text, ZIndex = 7 })
    rBody.Parent = readyCard
    local readyBtn = Instance.new("TextButton")
    readyBtn.AnchorPoint = Vector2.new(0.5, 1)
    readyBtn.Position = UDim2.new(0.5, 0, 1, -18)
    readyBtn.Size = UDim2.fromOffset(220, 48)
    readyBtn.BackgroundColor3 = T.money
    readyBtn.Text = "GOT IT"
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
    UITheme.autoScale(title)
    local tName = UITheme.label({ Size = UDim2.new(1, 0, 0, 100), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 96, TextStrokeTransparency = 0.6, TextStrokeColor3 = Color3.new(), ZIndex = 22 })
    tName.Parent = title
    local tSub = UITheme.label({ Text = "MASKS ON.  THE JOB IS ON.", Position = UDim2.fromOffset(0, 104),
        Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
        TextSize = 22, TextColor3 = T.gold, TextStrokeTransparency = 0.6, TextStrokeColor3 = Color3.new(), ZIndex = 22 })
    tSub.Parent = title

    self._ui = { screen = screen, bars = bars, sub = sub, line = line, skip = skip, readyCard = readyCard,
        rTitle = rTitle, rBody = rBody, readyBtn = readyBtn, later = later, black = black, title = title, tName = tName, tSub = tSub,
        chip = chip, chipText = chipText, chipDot = chipDot, cut = cut }
end

function BriefingUI:_letterbox(on, amount)
    for _, b in ipairs(self._ui.bars) do
        TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = UDim2.new(1, 0, on and (amount or 0.1) or 0, 0) }):Play()
    end
end

function BriefingUI:_showReady()
    local u = self._ui
    local cfg = jobCfg()
    u.rTitle.Text = "NEXT: WALK INTO A HEIST DOOR"
    u.rBody.Text = "Go to the Heist Hall and walk into the " .. cfg.name .. " door (or any door). Friends can hop in too!"
    u.readyCard.Visible = true
end

function BriefingUI:_showChip(text)
    local u = self._ui
    u.chipText.Text = text
    u.chip.Visible = true
    u.chip.BackgroundTransparency = 1
    u.chipText.TextTransparency = 1
    TweenService:Create(u.chip, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.15 }):Play()
    TweenService:Create(u.chipText, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { TextTransparency = 0 }):Play()
end

-- v2.2: hide the other HUD ScreenGuis for the fly-through; returns the list to put back
function BriefingUI:_hideHud()
    local hidden = {}
    local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return hidden end
    for _, g in ipairs(pg:GetChildren()) do
        if g:IsA("ScreenGui") and g ~= self._ui.screen and g.Enabled then
            g.Enabled = false
            table.insert(hidden, g)
        end
    end
    return hidden
end

function BriefingUI:play()
    if self._playing then return end
    self._playing = true
    -- v2.2: never fight the first-join fly-over (IntroCam) for the camera
    local waitT = os.clock()
    while localPlayer:GetAttribute("IntroPlaying") == true and os.clock() - waitT < 12 do task.wait(0.1) end
    local u = self._ui
    local cam = workspace.CurrentCamera
    local cfg = jobCfg()
    local lines = cfg.briefing or { cfg.tagline }
    -- v3.0: the Boss names this heist's TARGET item as his last line
    do
        local okC, C = pcall(require, game:GetService("ReplicatedStorage").Shared.Constants)
        local t = okC and C.LOOT_V3 and C.LOOT_V3.TARGETS and cfg.id and C.LOOT_V3.TARGETS[cfg.id]
        if t and t.line then
            local copy = table.clone(lines)
            table.insert(copy, t.line)
            lines = copy
        end
    end
    local skipped = false
    local function doSkip() skipped = true end

    -- v2.2: the real building, if the server published shots for this job
    local shots = loadShots(cfg.id)
    local plan = shots and planShots(lines, shots) or nil

    u.readyCard.Visible = false
    self:_letterbox(true, plan and 0.08 or 0.1)
    u.sub.Visible = true
    u.skip.Visible = true
    local skipConn = u.skip.Activated:Connect(doSkip)
    ContextActionService:BindAction("HC_SkipBriefing", function(_, state)
        if state == Enum.UserInputState.Begin then doSkip() end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonB)

    local oldType = cam.CameraType
    local oldFov = cam.FieldOfView
    local hiddenHud = plan and self:_hideHud() or {}
    cam.CameraType = Enum.CameraType.Scriptable
    for i, text in ipairs(lines) do
        if skipped then break end
        if self._camTween then self._camTween:Cancel() self._camTween = nil end
        if plan then
            local step = plan[i]
            local sh = step.shot
            local a, b = sh.from, sh.to
            if step.reversed then a, b = b, a end
            -- quick dip to black, cut, fade back in
            local prev = plan[i - 1]
            if i == 1 or (prev and prev.shot ~= sh) then
                if i > 1 then
                    u.cut.BackgroundTransparency = 1
                    TweenService:Create(u.cut, TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
                    local t0 = os.clock()
                    while not skipped and os.clock() - t0 < 0.13 do task.wait() end
                else
                    u.cut.BackgroundTransparency = 0
                end
                cam.FieldOfView = 55
                cam.CFrame = a
                TweenService:Create(u.cut, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
                self:_showChip(string.upper(cfg.name or "") .. "  ·  " .. sh.label)
            else
                cam.CFrame = a
            end
            self._camTween = TweenService:Create(cam, TweenInfo.new(LINE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
                { CFrame = b })
            self._camTween:Play()
        else
            local shot = SHOTS[(i - 1) % #SHOTS + 1]
            cam.CFrame = CFrame.lookAt(shot.from, shot.to)
            self._camTween = TweenService:Create(cam, TweenInfo.new(LINE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { CFrame = CFrame.lookAt(shot.from + shot.drift, shot.to) })
            self._camTween:Play()
        end
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
    cam.FieldOfView = oldFov
    cam.CameraType = (oldType == Enum.CameraType.Scriptable) and Enum.CameraType.Custom or oldType
    local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then cam.CameraSubject = hum end
    for _, g in ipairs(hiddenHud) do
        if g.Parent and not g.Enabled then g.Enabled = true end
    end
    u.cut.BackgroundTransparency = 1
    u.chip.Visible = false
    u.sub.Visible = false
    u.skip.Visible = false
    self:_letterbox(false)
    self._playing = false
    self._briefed = true
    localPlayer:SetAttribute("HeardPlan", true)
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
        -- [HOOK: MaskUp] v3.2 casing: "Look around. Mask up when you're ready." (MaskUpUI shows MASKS ON later)
        u.tSub.Text = payload.subtitle or "MASKS ON.  THE JOB IS ON."
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
    -- v2.0: no more READY UP here — the heist doors start the run. GOT IT just closes the card.
    u.readyBtn.Activated:Connect(function()
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
