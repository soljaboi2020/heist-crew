--[[
    HEIST CREW — TutorialHud  (v3.1 "FIRST HEIST")
    ────────────────────────────────────────────────
    The screen half of TutorialService (server). Everything here follows the
    player attributes the server sets — the client decides NOTHING about
    progress, it only draws:

      • OFFER CARD (centre, modal) — "First heist? Let the Boss show you!"
            [LET'S GO]  [I know how]      (shows after the IntroCam fly-over)
      • STEP CARD (UITheme slot "left" — the Boss-tip slot; TipHud is quiet
        while the Tutorial attribute is set, so they never fight):
            [big icon]  STEP 3 OF 6 · THE BOSS SAYS
                        Grab the cash! Press E at the register
                        [ E ] [ TAP FAST! ]
                        "Then tap fast to stuff the bag!"
            + "Skip this" on the optional Golden Ticket step
            + [TRY AGAIN] [Stop] when it paused (failed / died / other heist)
            + a small "Skip tutorial" link (tap twice — no accidental skips)
      • WORLD ARROW — a glowing gold Beam from your feet to the target
        (Attachment on your HumanoidRootPart → Attachment on a local marker
        part) with a pulse running along it, plus a spinning gold chevron
        bobbing over the target. All local: only YOU see your arrow.
      • DONE BANNER — "You're a real crew member now!" + the reward + confetti,
        after the payout screen closes (TutorialReward attribute).

    Attributes read (see TutorialService): Tutorial, TutorialTarget,
    TutorialPause, TutorialWait, TutorialReward, + Jailed, IntroPlaying,
    IntroCamDone, GetawayPlaying.
    Remote "Tutorial" (client → server): { action = "start" | "skip" | "skipTicket" }

    PUBLIC API:
        TutorialHud:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local TutorialHud = {}
local localPlayer = Players.LocalPlayer

local TOTAL = 6
local STEPS = {
    portal    = { n = 1, icon = "🚪", text = "Walk into the SUNNY'S MART door", chips = { "WALK IN" },
                  boss = "Let's start easy. A little corner shop!" },
    breaker   = { n = 2, icon = "⚡", text = "Find the breaker. Hold E to turn off the camera", chips = { "HOLD E" },
                  boss = "Cameras first. No camera, no problem!" },
    cash      = { n = 3, icon = "💰", text = "Grab the cash! Press E at the register", chips = { "E", "TAP FAST!" },
                  boss = "Then tap fast to stuff the bag!" },
    trunk     = { n = 4, icon = "🚗", text = "Take the bag to the car. Press E at the trunk", chips = { "E" },
                  boss = "The car is parked out back." },
    ticket    = { n = 5, icon = "🎫", text = "Bonus! Grab the Golden Ticket for +$5,000", chips = { "HOLD E" },
                  boss = "It's hiding in the office. Want it?", skipStep = true },
    ticketCar = { n = 5, icon = "🎫", text = "Put the Golden Ticket in the trunk", chips = { "E" },
                  boss = "That's +$5,000 when you get away!", skipStep = true },
    go        = { n = 6, icon = "🏁", text = "Get in the car and press GO!", chips = { "F", "GO!" },
                  boss = "F to hop in. Then hit the big GO! button." },
    escape    = { n = 6, icon = "🚤", text = "Pick how you get away!", chips = { "CLICK" },
                  boss = "Any way works. You did it!" },
}
local PAUSED = {
    failed   = { icon = "😅", text = "Oops! That didn't work.", boss = "No worries. Every crew messes up. Try again!" },
    died     = { icon = "🩹", text = "Ouch! Let's try that again.", boss = "Shake it off, rookie." },
    otherJob = { icon = "🏪", text = "That's a different heist!", boss = "Have fun! Sunny's Mart will wait for you." },
}

local remote = nil
local function send(action)
    task.spawn(function()
        local t0 = os.clock()
        while not remote and os.clock() - t0 < 30 do task.wait(0.2) end
        if remote then remote:FireServer({ action = action }) end
    end)
end

local function attr(name) return localPlayer:GetAttribute(name) end

-- ── offer card ───────────────────────────────────────────────────────
function TutorialHud:_buildOffer(pg)
    local old = pg:FindFirstChild("TutorialOffer")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "TutorialOffer"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 19          -- over the daily-reward card (18), under the Boss briefing (20)
    screen.Enabled = false
    screen.Parent = pg

    local back = Instance.new("Frame")
    back.Name = "Backdrop"
    back.Size = UDim2.fromScale(1, 1)
    back.BackgroundColor3 = Color3.new(0, 0, 0)
    back.BackgroundTransparency = 0.45
    back.BorderSizePixel = 0
    back.Parent = screen

    local card = UITheme.card({ Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(480, 0), AutomaticSize = Enum.AutomaticSize.Y, accent = T.gold })
    card.Parent = screen
    UITheme.autoScale(card)
    UITheme.padding(card, 24, 22)
    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.Padding = UDim.new(0, 10)
    list.Parent = card

    UITheme.badge("🎩", T.gold, 84, { LayoutOrder = 1 }).Parent = card
    UITheme.label({ LayoutOrder = 2, Text = "FIRST HEIST?", Size = UDim2.new(1, 0, 0, 44), FontFace = UITheme.F.display,
        TextSize = 40, TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Center }).Parent = card
    UITheme.label({ LayoutOrder = 3, Text = "Let the Boss show you!", Size = UDim2.new(1, 0, 0, 28),
        FontFace = UITheme.F.bold, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center }).Parent = card

    local row = Instance.new("Frame")
    row.LayoutOrder = 4
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, 0, 0, 64)
    row.Parent = card
    local rl = Instance.new("UIListLayout")
    rl.FillDirection = Enum.FillDirection.Horizontal
    rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
    rl.VerticalAlignment = Enum.VerticalAlignment.Center
    rl.Padding = UDim.new(0, 14)
    rl.Parent = row
    local go = UITheme.button("LET'S GO!", T.money, { Name = "LetsGo", Size = UDim2.fromOffset(220, 60), TextSize = 28, LayoutOrder = 1 })
    go.Parent = row
    local know = UITheme.button("I know how", T.bgRaised, { Name = "IKnowHow", Size = UDim2.fromOffset(170, 52), TextSize = 20,
        TextColor3 = T.text, LayoutOrder = 2 })
    know.Parent = row

    go.Activated:Connect(function()
        screen.Enabled = false
        send("start")
    end)
    know.Activated:Connect(function()
        screen.Enabled = false
        send("skip")
    end)
    self._offer = screen
end

-- ── step card ────────────────────────────────────────────────────────
function TutorialHud:_chip(text, parent, order)
    local chip = Instance.new("TextLabel")
    chip.LayoutOrder = order
    chip.AutomaticSize = Enum.AutomaticSize.X
    chip.Size = UDim2.fromOffset(34, 30)
    chip.BackgroundColor3 = T.gold
    chip.BorderSizePixel = 0
    chip.Text = text
    chip.TextColor3 = T.bgDeep
    chip.FontFace = UITheme.F.display
    chip.TextSize = 18
    UITheme.corner(chip, 8)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = chip
    UITheme.stroke(chip, Color3.fromRGB(120, 80, 0), 0.2, 2)
    chip.Parent = parent
    return chip
end

function TutorialHud:_buildCard()
    local card = UITheme.card({ Name = "TutorialStep", LayoutOrder = 0, Size = UDim2.fromOffset(360, 0),
        AutomaticSize = Enum.AutomaticSize.Y, accent = T.gold, Visible = false })
    card.Parent = UITheme.slot("left")
    UITheme.padding(card, 14, 14)
    local scale = Instance.new("UIScale")
    scale.Parent = card

    local badge = UITheme.badge("🚪", T.gold, 60)
    badge.Parent = card
    local col = Instance.new("Frame")
    col.BackgroundTransparency = 1
    col.Position = UDim2.fromOffset(72, 0)
    col.Size = UDim2.new(1, -72, 0, 0)
    col.AutomaticSize = Enum.AutomaticSize.Y
    col.Parent = card
    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 6)
    list.Parent = col

    local cap = UITheme.caption("Step 1 of 6 · The Boss says", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 14), TextColor3 = T.gold })
    cap.Parent = col
    local main = UITheme.label({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true, FontFace = UITheme.F.display, TextSize = 22, TextYAlignment = Enum.TextYAlignment.Top })
    main.Parent = col
    local chips = Instance.new("Frame")
    chips.LayoutOrder = 3
    chips.BackgroundTransparency = 1
    chips.Size = UDim2.new(1, 0, 0, 30)
    chips.Parent = col
    local cl = Instance.new("UIListLayout")
    cl.FillDirection = Enum.FillDirection.Horizontal
    cl.SortOrder = Enum.SortOrder.LayoutOrder
    cl.Padding = UDim.new(0, 6)
    cl.Parent = chips
    local boss = UITheme.label({ LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true, FontFace = UITheme.F.medium, TextSize = UITheme.T.body, TextColor3 = T.muted,
        TextYAlignment = Enum.TextYAlignment.Top })
    boss.Parent = col

    local btns = Instance.new("Frame")
    btns.LayoutOrder = 5
    btns.BackgroundTransparency = 1
    btns.Size = UDim2.new(1, 0, 0, 44)
    btns.Visible = false
    btns.Parent = col
    local bl = Instance.new("UIListLayout")
    bl.FillDirection = Enum.FillDirection.Horizontal
    bl.SortOrder = Enum.SortOrder.LayoutOrder
    bl.Padding = UDim.new(0, 8)
    bl.Parent = btns
    local retry = UITheme.button("TRY AGAIN", T.money, { Name = "TryAgain", Size = UDim2.fromOffset(140, 42), TextSize = 20, LayoutOrder = 1 })
    retry.Parent = btns
    local stopB = UITheme.button("Stop", T.bgRaised, { Name = "StopTutorial", Size = UDim2.fromOffset(80, 42), TextSize = 18,
        TextColor3 = T.text, LayoutOrder = 2 })
    stopB.Parent = btns
    local skipStep = UITheme.button("Skip this", T.bgRaised, { Name = "SkipStep", Size = UDim2.fromOffset(120, 42), TextSize = 18,
        TextColor3 = T.text, LayoutOrder = 3 })
    skipStep.Parent = btns

    local skipAll = Instance.new("TextButton")
    skipAll.Name = "SkipTutorial"
    skipAll.LayoutOrder = 6
    skipAll.BackgroundTransparency = 1
    skipAll.Size = UDim2.new(1, 0, 0, 18)
    skipAll.Text = "Skip tutorial"
    skipAll.TextXAlignment = Enum.TextXAlignment.Right
    skipAll.TextColor3 = T.faint
    skipAll.FontFace = UITheme.F.bold
    skipAll.TextSize = 13
    skipAll.Parent = col

    retry.Activated:Connect(function() send("start") end)
    stopB.Activated:Connect(function() send("skip") end)
    skipStep.Activated:Connect(function() send("skipTicket") end)
    -- tap twice: a kid mashing buttons shouldn't lose the tutorial by accident
    local armedAt = 0
    skipAll.Activated:Connect(function()
        if os.clock() - armedAt < 4 then
            send("skip")
            armedAt = 0
            skipAll.Text = "Skip tutorial"
        else
            armedAt = os.clock()
            skipAll.Text = "Really skip? Tap again"
            skipAll.TextColor3 = T.danger
            task.delay(4, function()
                if os.clock() - armedAt >= 3.9 then
                    skipAll.Text = "Skip tutorial"
                    skipAll.TextColor3 = T.faint
                end
            end)
        end
    end)

    self._card = { card = card, scale = scale, badge = badge, cap = cap, main = main, chips = chips, boss = boss,
        btns = btns, retry = retry, stop = stopB, skipStep = skipStep, skipAll = skipAll }
end

function TutorialHud:_render()
    local u = self._card
    if not u then return end
    local step = attr("Tutorial")
    local def = STEPS[step]
    local busy = attr("GetawayPlaying") or attr("IntroPlaying")
    if (not def and step ~= "paused") or busy then
        u.card.Visible = false
        self._shown = nil
        return
    end
    local icon, text, boss, chips, n = nil, nil, nil, {}, nil
    local showRetry, showSkipStep = false, false
    if step == "paused" then
        local p = PAUSED[attr("TutorialPause") or "failed"] or PAUSED.failed
        icon, text, boss = p.icon, p.text, p.boss
        showRetry = true
    elseif attr("Jailed") then
        icon, text, boss, n = "🚔", "You're in jail! Wait for a friend.", "Hang tight. It won't be long.", def.n
    elseif step == "portal" and attr("TutorialWait") then
        icon, text, chips, n = "⏳", "Wait for the heist to finish. Then walk into SUNNY'S MART!", { "WAIT" }, def.n
        boss = "Somebody's out on a job right now."
    else
        icon, text, boss, chips, n = def.icon, def.text, def.boss, def.chips, def.n
        showSkipStep = def.skipStep == true
    end
    u.cap.Text = n and string.upper(string.format("Step %d of %d · The Boss says", n, TOTAL)) or "THE BOSS SAYS"
    UITheme.setBadge(u.badge, icon, step == "paused" and T.danger or T.gold)
    u.main.Text = text
    u.boss.Text = "\"" .. boss .. "\""
    for _, c in ipairs(u.chips:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    for i, c in ipairs(chips) do self:_chip(c, u.chips, i) end
    u.chips.Visible = #chips > 0
    u.btns.Visible = showRetry or showSkipStep
    u.retry.Visible = showRetry
    u.stop.Visible = showRetry
    u.skipStep.Visible = showSkipStep
    u.skipAll.Visible = not showRetry
    local key = tostring(step) .. "|" .. text
    if not u.card.Visible or self._shown ~= key then
        -- pop in when the step changes (the "new thing to do" moment)
        u.card.Visible = true
        u.scale.Scale = 0.85
        TweenService:Create(u.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
    end
    self._shown = key
end

-- ── world arrow ──────────────────────────────────────────────────────
function TutorialHud:_buildArrow()
    local old = workspace:FindFirstChild("TutorialMarker")
    if old then old:Destroy() end
    local marker = Instance.new("Part")
    marker.Name = "TutorialMarker"
    marker.Anchored = true
    marker.CanCollide = false
    marker.CanQuery = false
    marker.CanTouch = false
    marker.CastShadow = false
    marker.Transparency = 1
    marker.Size = Vector3.new(0.2, 0.2, 0.2)
    marker.Parent = workspace
    local a1 = Instance.new("Attachment")
    a1.Name = "TutorialTo"
    a1.Parent = marker

    -- a spinning gold chevron (two thin neon bars in a V) bobbing over the target
    local chevron = Instance.new("Model")
    chevron.Name = "Chevron"
    for i, side in ipairs({ -1, 1 }) do
        local bar = Instance.new("Part")
        bar.Name = "Bar" .. i
        bar.Anchored = true
        bar.CanCollide = false
        bar.CanQuery = false
        bar.CanTouch = false
        bar.CastShadow = false
        bar.Material = Enum.Material.Neon
        bar.Color = T.gold
        bar.Size = Vector3.new(0.45, 2.2, 0.45)
        bar:SetAttribute("Side", side)
        bar.Parent = chevron
    end
    chevron.Parent = marker

    local beam = Instance.new("Beam")
    beam.Name = "TutorialBeam"
    beam.Attachment1 = a1
    beam.FaceCamera = true
    beam.Width0 = 1
    beam.Width1 = 0.6
    beam.Segments = 24
    beam.LightEmission = 1
    beam.LightInfluence = 0
    beam.Brightness = 2
    beam.Color = ColorSequence.new(T.gold, T.money)
    beam.Enabled = false
    beam.Parent = marker
    self._arrow = { marker = marker, a1 = a1, beam = beam, chevron = chevron }
end

function TutorialHud:_attachRoot()
    local a = self._arrow
    if not a then return end
    local char = localPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then a.beam.Attachment0 = nil return end
    local a0 = root:FindFirstChild("TutorialFrom")
    if not a0 then
        a0 = Instance.new("Attachment")
        a0.Name = "TutorialFrom"
        a0.Position = Vector3.new(0, -2.2, 0)   -- near your feet, so the line runs along the floor
        a0.Parent = root
    end
    a.beam.Attachment0 = a0
end

local function pulse(t)
    -- a bright band running from you to the goal
    local keys = {}
    for i = 0, 9 do
        local x = i / 9
        local w = 0.5 + 0.5 * math.sin((x * 3 - t * 1.6) * math.pi * 2)
        local edge = (x < 0.05 or x > 0.95) and 0.5 or 0
        table.insert(keys, NumberSequenceKeypoint.new(x, math.clamp(0.72 - 0.6 * w + edge, 0, 1)))
    end
    return NumberSequence.new(keys)
end

function TutorialHud:_stepArrow(t)
    local a = self._arrow
    if not a then return end
    local target = attr("TutorialTarget")
    local active = typeof(target) == "Vector3" and STEPS[attr("Tutorial")] ~= nil
        and not attr("GetawayPlaying") and not attr("Jailed")
    if not active then
        a.beam.Enabled = false
        for _, b in ipairs(a.chevron:GetChildren()) do b.Transparency = 1 end
        return
    end
    a.marker.CFrame = CFrame.new(target)
    if not a.beam.Attachment0 or not a.beam.Attachment0.Parent then self:_attachRoot() end
    local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    local dist = root and (root.Position - target).Magnitude or 0
    a.beam.Enabled = root ~= nil and dist > 5
    a.beam.Transparency = pulse(t)
    -- chevron: spin + bob, 4.5 studs above the goal
    local top = target + Vector3.new(0, 4.5 + math.sin(t * 3) * 0.5, 0)
    local spin = CFrame.new(top) * CFrame.Angles(0, t * 2, 0)
    for _, b in ipairs(a.chevron:GetChildren()) do
        local side = b:GetAttribute("Side") or 1
        b.Transparency = 0
        b.CFrame = spin * CFrame.new(side * 0.72, 0, 0) * CFrame.Angles(0, 0, side * math.rad(40))
    end
end

-- ── done banner + confetti ───────────────────────────────────────────
function TutorialHud:_celebrate(amount)
    local pg = localPlayer:WaitForChild("PlayerGui")
    -- let the payout screen have its moment first
    local t0 = os.clock()
    while os.clock() - t0 < 25 do
        local ps = pg:FindFirstChild("PayoutScreen")
        if not (ps and ps:IsA("ScreenGui") and ps.Enabled) and not attr("GetawayPlaying") then break end
        task.wait(0.25)
    end
    local old = pg:FindFirstChild("TutorialDone")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "TutorialDone"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 16
    screen.Parent = pg

    local card = Instance.new("CanvasGroup")
    card.Name = "Banner"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.32)
    card.Size = UDim2.fromOffset(620, 190)
    card.BackgroundColor3 = T.bg
    card.BackgroundTransparency = 0.05
    card.GroupTransparency = 1
    card.Parent = screen
    UITheme.corner(card, 22)
    UITheme.stroke(card, T.gold, 0.1, 3)
    local sc = UITheme.autoScale(card)
    UITheme.badge("🎩", T.gold, 76, { Position = UDim2.fromOffset(26, 57) }).Parent = card
    UITheme.label({ Text = "YOU'RE A REAL CREW MEMBER NOW!", Position = UDim2.fromOffset(118, 34), Size = UDim2.new(1, -136, 0, 70),
        TextWrapped = true, FontFace = UITheme.F.display, TextSize = 32, TextColor3 = T.gold }).Parent = card
    UITheme.label({ Text = string.format("+%s from the Boss", UITheme.money(amount)), Position = UDim2.fromOffset(118, 110),
        Size = UDim2.new(1, -136, 0, 34), FontFace = UITheme.F.display, TextSize = 28, TextColor3 = T.money }).Parent = card
    UITheme.label({ Text = "Pick any heist door next. Good luck, crew!", Position = UDim2.fromOffset(118, 146),
        Size = UDim2.new(1, -136, 0, 22), FontFace = UITheme.F.medium, TextSize = 17, TextColor3 = T.muted }).Parent = card
    local base = sc.Scale
    sc.Scale = base * 0.6
    TweenService:Create(card, TweenInfo.new(0.35), { GroupTransparency = 0 }):Play()
    TweenService:Create(sc, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Scale = base }):Play()

    -- confetti: little coloured squares raining down
    local colors = { T.gold, T.money, T.pink, T.info, T.purple, Color3.new(1, 1, 1) }
    local rng = Random.new()
    for i = 1, 70 do
        local f = Instance.new("Frame")
        f.Name = "Confetti"
        f.BorderSizePixel = 0
        f.BackgroundColor3 = colors[(i % #colors) + 1]
        f.Size = UDim2.fromOffset(rng:NextInteger(8, 16), rng:NextInteger(10, 20))
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.Position = UDim2.new(rng:NextNumber(0.05, 0.95), 0, -0.05, -rng:NextInteger(0, 200))
        f.Rotation = rng:NextInteger(0, 360)
        f.Parent = screen
        local dur = rng:NextNumber(2.4, 4.2)
        TweenService:Create(f, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(f.Position.X.Scale + rng:NextNumber(-0.12, 0.12), 0, 1.08, 0),
            Rotation = f.Rotation + rng:NextInteger(-540, 540),
        }):Play()
    end
    task.delay(6.5, function()
        if not screen.Parent then return end
        local out = TweenService:Create(card, TweenInfo.new(0.6), { GroupTransparency = 1 })
        out:Play()
        out.Completed:Wait()
        screen:Destroy()
    end)
end

-- ── start ────────────────────────────────────────────────────────────
function TutorialHud:_offerTick()
    local want = attr("Tutorial") == "offer"
    if not want then
        if self._offer then self._offer.Enabled = false end
        return
    end
    -- wait for the first-join fly-over to finish (or ~8 s with no fly-over)
    if attr("IntroPlaying") then return end
    if not attr("IntroCamDone") and os.clock() - self._t0 < 8 then return end
    if self._offer and not self._offer.Enabled then self._offer.Enabled = true end
end

function TutorialHud:start()
    if self._started then return end   -- (v3.1) safe to call twice (init.client + tests)
    self._started = true
    self._t0 = os.clock()
    local pg = localPlayer:WaitForChild("PlayerGui")
    self:_buildOffer(pg)
    self:_buildCard()
    self:_buildArrow()

    task.spawn(function()
        local folder = ReplicatedStorage:WaitForChild("Remotes")
        remote = folder:WaitForChild("Tutorial")
    end)

    for _, name in ipairs({ "Tutorial", "TutorialPause", "TutorialWait", "Jailed", "GetawayPlaying", "IntroPlaying" }) do
        localPlayer:GetAttributeChangedSignal(name):Connect(function()
            self:_render()
            self:_offerTick()
        end)
    end
    localPlayer:GetAttributeChangedSignal("TutorialReward"):Connect(function()
        local amt = attr("TutorialReward")
        if type(amt) == "number" and amt > 0 and not self._celebrated then
            self._celebrated = true
            task.spawn(function() self:_celebrate(amt) end)
        end
    end)
    localPlayer.CharacterAdded:Connect(function(char)
        char:WaitForChild("HumanoidRootPart", 10)
        self:_attachRoot()
    end)
    self:_attachRoot()
    self:_render()

    -- the offer waits for the intro; the arrow animates every frame (only while a step has a target)
    task.spawn(function()
        while self._offer and self._offer.Parent do
            self:_offerTick()
            task.wait(0.25)
        end
    end)
    RunService.RenderStepped:Connect(function()
        local ok, err = pcall(self._stepArrow, self, os.clock())
        if not ok and not self._warned then
            self._warned = true
            warn("[HEIST CREW] TutorialHud arrow:", err)
        end
    end)
    print("[HEIST CREW] TutorialHud mounted ✅")
end

return TutorialHud
