--[[
    HEIST CREW — DailyRewardUI
    ────────────────────────────────────────────────
    v2.0 "BIGGER" (2026-09-25), v2.1 UI overhaul. The daily reward calendar.

        [gift] DAILY REWARD                                (X)
               Come back every day!
        [1] [2] [3] [4] [5] [6] [7]      ← today glows gold, claimed days get a check
        [        DAY 3 — $600 — CLAIM!        ]

    v2.1 (Malachi: "the daily popup appears the instant you spawn and covers
    everything"):
      • it only pops up by itself AFTER the IntroCam fly-over has finished
        (or 6 s after spawning when there's no fly-over), and never while a
        heist is running, you're standing in a heist door, or another big
        screen (shop / briefing / payout) is open.
      • a smaller, prettier card (540 wide instead of 640) that scales with
        the screen like the rest of the HUD.
      • the "DAILY" button is tucked into the UITheme rightEdge slot (right
        side, under the cash + THE JOB cards) and hides during a heist. A red
        dot shows when a reward is waiting.
      • save didn't load (normal in Studio without API access) → a small
        friendly note on the card ("Rewards are paused…"), not a red error,
        and the card doesn't pop up by itself.

    Talks to the DailyReward RemoteFunction ("status" | "claim") →
        { ok, day, amount, nextAt, msg, claimable, secondsLeft, streak, rewards, bonus,
          saveFailed? (optional — see NEEDS in the v2.1 report) }
    All the rules live on the server (DailyRewardService); this only shows them.

    PUBLIC API:
        DailyRewardUI:start()
        DailyRewardUI:open()
        DailyRewardUI:close()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C
local I = UITheme.ICON

local DailyRewardUI = {}
local localPlayer = Players.LocalPlayer

local W, H = 540, 300
local CLOSE_ACTION = "HC_DailyClose"
local DEFAULT_REWARDS = { 250, 400, 600, 800, 1000, 1500, 3000 }
local INTRO_FALLBACK = 6         -- seconds after spawn when there's no fly-over
local DEFAULT_SUB = "Every day in a row pays more. Day 7 = the big one!"
-- other big screens: the daily card never pops up on top of these
local BUSY_SCREENS = { "ShopUI", "PayoutScreen", "IntroCam" }

local function tween(obj, t, props, style, dir)
    local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad,
        dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function frame(props)
    local f = Instance.new("Frame")
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    for k, v in pairs(props or {}) do (f :: any)[k] = v end
    return f
end

local function fmtWait(secs)
    secs = math.max(0, math.floor(secs or 0))
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return string.format("%dh %dm", h, m) end
    if m > 0 then return string.format("%dm", m) end
    return "a moment"
end

-- ── remote ─────────────────────────────────────────────────────────────
-- The server may swap a RemoteEvent placeholder for the real RemoteFunction a
-- moment after we load, so keep looking until it's the right class.
function DailyRewardUI:_remote()
    if self._rf and self._rf.Parent then return self._rf end
    local folder = ReplicatedStorage:FindFirstChild("Remotes")
    local r = folder and folder:FindFirstChild(Remotes.NAMES.DailyReward or "DailyReward")
    if r and r:IsA("RemoteFunction") then
        self._rf = r
        return r
    end
    return nil
end

function DailyRewardUI:_waitRemote(timeout)
    local t0 = os.clock()
    while os.clock() - t0 < (timeout or 20) do
        local r = self:_remote()
        if r then return r end
        task.wait(0.5)
    end
    return nil
end

function DailyRewardUI:_invoke(action)
    local r = self:_remote()
    if not r then return nil end
    local done, ok, res = false, false, nil
    task.spawn(function()
        ok, res = pcall(function() return r:InvokeServer(action) end)
        done = true
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 10 do task.wait(0.05) end
    if not done or not ok or type(res) ~= "table" then return nil end
    return res
end

-- the save didn't load (Studio without API access, a DataStore hiccup): rewards are paused
local function savePaused(res)
    if type(res) ~= "table" then return false end
    if res.saveFailed == true or res.saveLoaded == false then return true end
    local m = string.lower(tostring(res.msg or ""))
    return res.ok == false and (m:find("save", 1, true) ~= nil) and (m:find("load", 1, true) ~= nil)
        and not m:find("loading your save", 1, true)
end

-- ── build ──────────────────────────────────────────────────────────────
function DailyRewardUI:_build()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("DailyRewardUI")
    if old then old:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "DailyRewardUI"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 18
    screen.Parent = pg

    -- ── the small reopen button (UITheme rightEdge slot) ──
    local open = Instance.new("TextButton")
    open.Name = "DailyButton"
    open.Text = ""
    open.AutoButtonColor = false
    open.LayoutOrder = 1
    open.Size = UDim2.fromOffset(118, 44)
    open.BackgroundColor3 = T.bg
    open.BackgroundTransparency = 0.08
    open.BorderSizePixel = 0
    open.Parent = UITheme.slot("rightEdge")
    UITheme.corner(open, 22)
    local og = Instance.new("UIGradient")
    og.Rotation = 90
    og.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 155, 170))
    og.Parent = open
    UITheme.stroke(open, T.gold, 0.2, 2)
    local gift = UITheme.badge(I.daily, T.gold, 34)
    gift.AnchorPoint = Vector2.new(0, 0.5)
    gift.Position = UDim2.new(0, 5, 0.5, 0)
    gift.Parent = open
    UITheme.label({ Text = "DAILY", Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -50, 1, 0),
        FontFace = UITheme.F.display, TextSize = 17, TextColor3 = T.gold, Parent = open })
    local dot = frame({ Name = "Ready", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6),
        Size = UDim2.fromOffset(14, 14), BackgroundColor3 = T.danger, BackgroundTransparency = 0, Visible = false })
    UITheme.corner(dot, 7)
    UITheme.stroke(dot, T.bgDeep, 0, 2)
    dot.Parent = open
    local openScale = Instance.new("UIScale")
    openScale.Parent = open
    open.MouseEnter:Connect(function() tween(openScale, 0.12, { Scale = 1.06 }) end)
    open.MouseLeave:Connect(function() tween(openScale, 0.15, { Scale = 1 }) end)
    open.Activated:Connect(function()
        if self._open then self:close() else self:open() end
    end)

    -- ── the card ──
    local backdrop = Instance.new("TextButton")
    backdrop.Name = "Backdrop"
    backdrop.Text = ""
    backdrop.AutoButtonColor = false
    backdrop.Modal = true
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
    backdrop.BackgroundTransparency = 1
    backdrop.BorderSizePixel = 0
    backdrop.Visible = false
    backdrop.Parent = screen
    backdrop.Activated:Connect(function() self:close() end)

    local group = Instance.new("CanvasGroup")
    group.Name = "Card"
    group.AnchorPoint = Vector2.new(0.5, 0.5)
    group.Position = UDim2.fromScale(0.5, 0.5)
    group.Size = UDim2.fromOffset(W + 6, H + 6)
    group.BackgroundTransparency = 1
    group.GroupTransparency = 1
    group.Visible = false
    group.Parent = screen
    local fitScale = Instance.new("UIScale")
    fitScale.Parent = group

    local panel = UITheme.card({ Name = "Panel", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6),
        transparency = 0.03, radius = 20, accent = T.gold, Active = true })
    panel.Parent = group

    local hero = UITheme.badge(I.daily, T.gold, 50)
    hero.Position = UDim2.fromOffset(20, 16)
    hero.Parent = panel
    UITheme.caption("Daily reward", { Position = UDim2.fromOffset(80, 18), Size = UDim2.fromOffset(300, 14),
        TextColor3 = T.gold }).Parent = panel
    UITheme.label({ Text = "Come back every day!", Position = UDim2.fromOffset(80, 32), Size = UDim2.fromOffset(380, 30),
        FontFace = UITheme.F.display, TextSize = 26 }).Parent = panel
    local sub = UITheme.label({ Text = DEFAULT_SUB,
        Position = UDim2.fromOffset(20, 72), Size = UDim2.new(1, -40, 0, 20), TextWrapped = true,
        FontFace = UITheme.F.medium, TextSize = 15, TextColor3 = T.muted })
    sub.Parent = panel

    local close = Instance.new("TextButton")
    close.Name = "Close"
    close.Text = ""
    close.AutoButtonColor = false
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -16, 0, 16)
    close.Size = UDim2.fromOffset(36, 36)
    close.BackgroundColor3 = T.line
    close.BackgroundTransparency = 0.9
    close.BorderSizePixel = 0
    close.Parent = panel
    UITheme.corner(close, 18)
    UITheme.stroke(close, T.line, 0.85)
    for _, rot in ipairs({ 45, -45 }) do
        local bar = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(3, 15), Rotation = rot, BackgroundColor3 = T.text, BackgroundTransparency = 0 })
        UITheme.corner(bar, 1)
        bar.Parent = close
    end
    close.Activated:Connect(function() self:close() end)

    -- the 7 day boxes
    local row = frame({ Name = "Days", Position = UDim2.fromOffset(20, 102), Size = UDim2.new(1, -40, 0, 104) })
    row.Parent = panel
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = row
    local boxW = math.floor((W - 40 - 6 * 6) / 7)
    self._boxes = {}
    for i = 1, 7 do
        local box = frame({ LayoutOrder = i, Size = UDim2.fromOffset(boxW, 104), BackgroundColor3 = T.bgRaised,
            BackgroundTransparency = 0.25 })
        UITheme.corner(box, 14)
        local stroke = UITheme.stroke(box, T.line, 0.88)
        box.Parent = row
        local dayL = UITheme.label({ Position = UDim2.fromOffset(0, 7), Size = UDim2.new(1, 0, 0, 14),
            Text = "DAY " .. i, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
            TextSize = 12, TextColor3 = T.muted })
        dayL.Parent = box
        local big = i == 7
        local b = UITheme.badge(big and I.daily or I.cash, big and T.gold or T.money, big and 40 or 34)
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Position = UDim2.new(0.5, 0, 0, 47)
        b.Parent = box
        local amt = UITheme.label({ Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 0, 18),
            Text = UITheme.money(DEFAULT_REWARDS[i]), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.display, TextSize = 15, TextColor3 = T.money })
        amt.Parent = box
        local extra = UITheme.label({ Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 0, 12),
            Text = big and "+ GOLD BAG" or "", TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.bold, TextSize = 10, TextColor3 = T.gold })
        extra.Parent = box
        -- claimed check
        local check = frame({ Name = "Check", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4),
            Size = UDim2.fromOffset(18, 18), BackgroundColor3 = T.money, BackgroundTransparency = 0, Visible = false })
        UITheme.corner(check, 9)
        check.Parent = box
        local short = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 5),
            Position = UDim2.fromOffset(6.6, 10.4), Rotation = -45, BackgroundColor3 = T.bgDeep, BackgroundTransparency = 0 })
        short.Parent = check
        local long = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 9),
            Position = UDim2.fromOffset(10.4, 8.6), Rotation = 39, BackgroundColor3 = T.bgDeep, BackgroundTransparency = 0 })
        long.Parent = check
        local scale = Instance.new("UIScale")
        scale.Parent = box
        self._boxes[i] = { box = box, stroke = stroke, day = dayL, amt = amt, check = check, scale = scale }
    end

    -- claim button
    local claim = Instance.new("TextButton")
    claim.Name = "Claim"
    claim.Text = ""
    claim.AutoButtonColor = false
    claim.AnchorPoint = Vector2.new(0.5, 1)
    claim.Position = UDim2.new(0.5, 0, 1, -18)
    claim.Size = UDim2.new(1, -40, 0, 54)
    claim.BackgroundColor3 = T.money
    claim.BorderSizePixel = 0
    claim.Parent = panel
    UITheme.corner(claim, 16)
    local cg = Instance.new("UIGradient")
    cg.Rotation = 90
    cg.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
    cg.Parent = claim
    local claimLabel = UITheme.label({ Size = UDim2.fromScale(1, 1), Text = "CLAIM!", TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 22, TextColor3 = T.bgDeep })
    claimLabel.Parent = claim
    local claimScale = Instance.new("UIScale")
    claimScale.Parent = claim
    claim.MouseEnter:Connect(function() if claim.Active then tween(claimScale, 0.12, { Scale = 1.03 }) end end)
    claim.MouseLeave:Connect(function() tween(claimScale, 0.15, { Scale = 1 }) end)
    claim.Activated:Connect(function() self:_claim() end)

    self._screen, self._backdrop, self._group, self._fitScale = screen, backdrop, group, fitScale
    self._openBtn, self._dot, self._sub = open, dot, sub
    self._claimBtn, self._claimLabel, self._claimScale = claim, claimLabel, claimScale
end

-- a small, friendly line under the title (never a red error — Malachi's call)
function DailyRewardUI:_note(text, color)
    self._sub.Text = text or DEFAULT_SUB
    self._sub.TextColor3 = color or T.muted
end

-- ── render ─────────────────────────────────────────────────────────────
function DailyRewardUI:_render()
    local st = self._status
    if not self._screen then return end
    local rewards = (st and type(st.rewards) == "table") and st.rewards or DEFAULT_REWARDS
    local streak = st and tonumber(st.streak) or 0
    local day = st and tonumber(st.day) or 1
    local claimable = st ~= nil and st.claimable == true

    for i, b in ipairs(self._boxes) do
        b.amt.Text = UITheme.money(tonumber(rewards[i]) or DEFAULT_REWARDS[i])
        -- claimed = every day up to your streak (when the next claim continues it)
        local claimed = i <= streak and (i < day or not claimable)
        local today = i == day
        b.check.Visible = claimed
        if today then
            b.box.BackgroundColor3 = T.gold
            b.box.BackgroundTransparency = claimable and 0.8 or 0.9
            b.stroke.Color = T.gold
            b.stroke.Transparency = claimable and 0.15 or 0.6
            b.stroke.Thickness = 2
            b.day.Text = claimable and "TODAY" or ("DAY " .. i)
            b.day.TextColor3 = T.gold
        else
            b.box.BackgroundColor3 = T.bgRaised
            b.box.BackgroundTransparency = claimed and 0.55 or 0.25
            b.stroke.Color = T.line
            b.stroke.Transparency = 0.88
            b.stroke.Thickness = 1
            b.day.Text = "DAY " .. i
            b.day.TextColor3 = T.muted
        end
    end

    local c = self._claimBtn
    if self._busy then
        c.Active = false
        c.BackgroundColor3 = T.line
        c.BackgroundTransparency = 0.9
        self._claimLabel.TextColor3 = T.muted
        self._claimLabel.Text = "..."
    elseif claimable then
        c.Active = true
        c.BackgroundColor3 = T.money
        c.BackgroundTransparency = 0
        self._claimLabel.TextColor3 = T.bg
        self._claimLabel.Text = string.format("DAY %d  —  %s  —  CLAIM!", day, UITheme.money(tonumber(rewards[day]) or 0))
    else
        c.Active = false
        c.BackgroundColor3 = T.line
        c.BackgroundTransparency = 0.92
        self._claimLabel.TextColor3 = T.muted
        if self._justClaimed then
            self._claimLabel.Text = "SEE YOU TOMORROW!"
        elseif savePaused(st) then
            self._claimLabel.Text = "REWARDS PAUSED THIS TIME"
        elseif st and not st.ok then
            self._claimLabel.Text = string.upper(st.msg ~= "" and st.msg or "LOADING...")
        else
            local left = self._nextLocal and (self._nextLocal - os.clock()) or 0
            self._claimLabel.Text = left > 0 and ("NEXT REWARD IN " .. string.upper(fmtWait(left))) or "CHECKING..."
        end
    end
    self._dot.Visible = claimable and not savePaused(st)
end

-- ── actions ────────────────────────────────────────────────────────────
function DailyRewardUI:_setStatus(res)
    self._status = res
    local left = tonumber(res and res.secondsLeft) or 0
    self._nextLocal = os.clock() + left
    self:_render()
end

function DailyRewardUI:refresh()
    local res = self:_invoke("status")
    if res then self:_setStatus(res) end
    return res
end

function DailyRewardUI:_claim()
    if self._busy then return end
    local st = self._status
    if not st or not st.claimable then return end
    self._busy = true
    self:_render()
    task.spawn(function()
        local res = self:_invoke("claim")
        self._busy = false
        if not res then
            self:_note("Hmm, the server didn't answer. Try again in a second!", T.muted)
            self:_render()
            return
        end
        if res.ok then
            self._justClaimed = true
            self:_note(res.msg or "Reward claimed!", T.money)
            local b = self._boxes[tonumber(res.day) or 1]
            if b then
                b.scale.Scale = 1.18
                tween(b.scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
            end
            self:_setStatus(res)
            task.delay(2.2, function()
                if self._open then self:close() end
            end)
        elseif savePaused(res) then
            -- Studio / DataStore hiccup: a friendly heads-up, not an error
            self:_note("Heads up: your save didn't load this time, so rewards are paused. Rejoin to claim!", T.gold)
            self:_setStatus(res)
        else
            self:_note(res.msg or "Not yet!", T.gold)
            self:_setStatus(res)
        end
    end)
end

-- ── open / close ───────────────────────────────────────────────────────
function DailyRewardUI:_layout()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    -- HUD scale, but never bigger than the screen
    local fit = math.min((vp.X - 24) / (W + 6), (vp.Y - 24) / (H + 6))
    self._fitScale.Scale = math.clamp(math.min(UITheme.scale(), fit), 0.45, 1.6)
end

function DailyRewardUI:open()
    if not self._screen or self._open then return end
    self._open = true
    local token = {}
    self._animToken = token
    self._justClaimed = false
    self:_note(savePaused(self._status)
        and "Heads up: your save didn't load this time, so rewards are paused. Rejoin to claim!" or DEFAULT_SUB,
        savePaused(self._status) and T.gold or T.muted)
    self:_layout()
    self:_render()
    self._backdrop.Visible = true
    self._group.Visible = true
    self._group.GroupTransparency = 1
    self._fitScale.Scale = self._fitScale.Scale * 0.94
    local target = self._fitScale.Scale / 0.94
    tween(self._backdrop, 0.25, { BackgroundTransparency = 0.45 })
    tween(self._group, 0.22, { GroupTransparency = 0 })
    tween(self._fitScale, 0.35, { Scale = target }, Enum.EasingStyle.Back)

    ContextActionService:BindAction(CLOSE_ACTION, function(_, state)
        if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
        self:close()
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)

    task.spawn(function()
        self:refresh()
    end)
end

function DailyRewardUI:close()
    if not self._open then return end
    self._open = false
    local token = {}
    self._animToken = token
    ContextActionService:UnbindAction(CLOSE_ACTION)
    tween(self._backdrop, 0.2, { BackgroundTransparency = 1 })
    local out = tween(self._group, 0.2, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    out.Completed:Connect(function()
        if self._animToken == token then
            self._group.Visible = false
            self._backdrop.Visible = false
        end
    end)
end

-- ── start ──────────────────────────────────────────────────────────────
-- is it a good moment to pop the card up by itself?
function DailyRewardUI:_quietMoment()
    if localPlayer:GetAttribute("IntroPlaying") then return false end
    if localPlayer:GetAttribute("InPortal") or localPlayer:GetAttribute("Jailed") then return false end
    if self._jobActive then return false end
    local pg = localPlayer:FindFirstChild("PlayerGui")
    if pg then
        for _, name in ipairs(BUSY_SCREENS) do
            local g = pg:FindFirstChild(name)
            if g and g:IsA("ScreenGui") and g.Enabled then return false end
        end
        local b = pg:FindFirstChild("BriefingUI")
        local sub = b and b:FindFirstChild("Subtitle")
        if sub and sub.Visible then return false end
    end
    local cam = workspace.CurrentCamera
    if cam and cam.CameraType == Enum.CameraType.Scriptable then return false end
    return true
end

function DailyRewardUI:start()
    self:_build()
    self:_render()
    local t0 = os.clock()

    -- the DAILY button hides while a heist is running (one less thing on screen)
    task.spawn(function()
        local info = Remotes.getRemote(Remotes.NAMES.JobInfo, "RemoteEvent")
        if not info then return end
        info.OnClientEvent:Connect(function(i)
            local active = type(i) == "table" and i.stage == "ACTIVE"
            self._jobActive = active
            self._openBtn.Visible = not active
            if active and self._open then self:close() end
        end)
    end)

    -- tick the "next reward in" countdown + notice when a new reward unlocks
    task.spawn(function()
        while self._screen and self._screen.Parent do
            task.wait(30)
            local st = self._status
            if st and not st.claimable and self._nextLocal and os.clock() >= self._nextLocal then
                self:refresh()
            elseif self._open then
                self:_render()
            end
        end
    end)

    task.spawn(function()
        if not self:_waitRemote(30) then
            warn("[HEIST CREW] DailyRewardUI: DailyReward RemoteFunction missing")
            return
        end
        -- give the save a moment to load
        for _ = 1, 10 do
            local res = self:refresh()
            if res and res.ok then break end
            task.wait(2)
        end
        -- v2.1: wait for the IntroCam fly-over to finish (or INTRO_FALLBACK s with no fly-over)
        while true do
            if localPlayer:GetAttribute("IntroCamDone") then break end
            if not localPlayer:GetAttribute("IntroPlaying") and os.clock() - t0 >= INTRO_FALLBACK then break end
            if os.clock() - t0 > 60 then break end
            task.wait(0.25)
        end
        task.wait(2.5)   -- let the Boss's welcome tip land first
        -- then wait for a quiet moment (not mid-heist, not in a door, no other big screen)
        local waited = 0
        while not self:_quietMoment() and waited < 120 do
            task.wait(1)
            waited = waited + 1
        end
        local st = self._status
        if st and st.ok and st.claimable and not savePaused(st) and self:_quietMoment() then
            self:open()
        end
    end)
    print("[HEIST CREW] DailyRewardUI mounted ✅")
end

return DailyRewardUI
