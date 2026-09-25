--[[
    HEIST CREW — GetawayVote  (v3.0 "THE SCORE", getaway agent)
    ────────────────────────────────────────────────
    "HOW DO WE ESCAPE?" — three BIG cards while the crew sits in the car:

        🚤 BOAT          always works
        🚁 HELICOPTER    +10% cash — 🔒 locked if anyone got caught this run
        🛣️ HIGHWAY       the car's power ×2

    Tap / click a card (or press 1 · 2 · 3, gamepad: DPad left/up/right) to
    vote; you can change your mind until the timer runs out. Dots under each
    card show how many crewmates picked it. Most votes wins, a tie → BOAT.
    (v3.0 polish) The crew's Driver ("Getaway pro") gets 2 dots — their vote counts x2.
    Then the winner gets stamped ("BOAT!") and the getaway movie starts.

    Driven by the "Getaway" remote (see server/GetawayService.lua):
        { phase = "vote", endsAt, duration, options, car, loud, voters }
        { phase = "tally", votes, voted, voters }
        { phase = "decided", route }   { phase = "scene" }   { phase = "cancel" }
    Sends { action = "vote", route }.

    PUBLIC API: GetawayVote:start()   (idempotent)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local GetawayVote = {}
local localPlayer = Players.LocalPlayer

local ROUTES = { "boat", "heli", "highway" }
local ICON = { boat = "🚤", heli = "🚁", highway = "🛣️" }
local NAME = { boat = "BOAT", heli = "HELICOPTER", highway = "HIGHWAY" }
local COLOR = { boat = T.info, heli = T.gold, highway = T.pink }
local KEYS = {
    [Enum.KeyCode.One] = "boat", [Enum.KeyCode.KeypadOne] = "boat", [Enum.KeyCode.DPadLeft] = "boat",
    [Enum.KeyCode.Two] = "heli", [Enum.KeyCode.KeypadTwo] = "heli", [Enum.KeyCode.DPadUp] = "heli",
    [Enum.KeyCode.Three] = "highway", [Enum.KeyCode.KeypadThree] = "highway", [Enum.KeyCode.DPadRight] = "highway",
}

local function pctText(p)
    local tenths = math.floor((tonumber(p) or 0) * 1000 + 0.5)   -- sneaky escapes pay half: 2.5%
    return tenths % 10 == 0 and string.format("+%d%%", tenths // 10) or string.format("+%.1f%%", tenths / 10)
end

function GetawayVote:_build()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("GetawayVote")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "GetawayVote"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 20
    screen.Enabled = false
    screen.Parent = pg

    local dim = Instance.new("Frame")
    dim.Name = "Dim"
    dim.Size = UDim2.fromScale(1, 1)
    dim.BackgroundColor3 = Color3.new(0, 0, 0)
    dim.BackgroundTransparency = 0.5
    dim.BorderSizePixel = 0
    dim.Parent = screen

    local root = Instance.new("Frame")
    root.Name = "Root"
    root.AnchorPoint = Vector2.new(0.5, 0.5)
    root.Position = UDim2.fromScale(0.5, 0.5)
    root.Size = UDim2.fromOffset(760, 470)
    root.BackgroundTransparency = 1
    root.Parent = screen
    local scale = Instance.new("UIScale")
    scale.Parent = root
    local function refit()
        local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
        scale.Scale = math.clamp(math.min(UITheme.scale(), (vp.X - 30) / 760, (vp.Y - 30) / 470), 0.4, 1.6)
    end
    refit()
    if Workspace.CurrentCamera then Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit) end

    local title = UITheme.label({ Name = "Title", Text = "HOW DO WE ESCAPE?", Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, 56), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextSize = 50, TextStrokeTransparency = 0.5 })
    title.Parent = root
    local sub = UITheme.label({ Name = "Sub", Text = "Tap a card! Most votes wins.", Position = UDim2.fromOffset(0, 56),
        Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
        TextSize = 20, TextColor3 = T.gold, TextScaled = true })
    do   -- (v3.0 polish) the Driver note makes this line longer: shrink, never spill
        local cap = Instance.new("UITextSizeConstraint")
        cap.MaxTextSize = 20
        cap.Parent = sub
    end
    sub.Parent = root

    -- timer bar
    local track = Instance.new("Frame")
    track.Name = "Timer"
    track.Position = UDim2.new(0.5, -200, 0, 88)
    track.Size = UDim2.fromOffset(400, 10)
    track.BackgroundColor3 = T.bgRaised
    track.BorderSizePixel = 0
    track.Parent = root
    UITheme.corner(track, 5)
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.fromScale(1, 1)
    fill.BackgroundColor3 = T.gold
    fill.BorderSizePixel = 0
    fill.Parent = track
    UITheme.corner(fill, 5)

    local cards = {}
    for i, r in ipairs(ROUTES) do
        local card = UITheme.card({ Name = "Card_" .. r, Position = UDim2.fromOffset((i - 1) * 256, 116),
            Size = UDim2.fromOffset(240, 300), radius = 22, accent = COLOR[r] })
        card.Parent = root
        local btn = Instance.new("TextButton")
        btn.Name = "Pick"
        btn.Text = ""
        btn.BackgroundTransparency = 1
        btn.Size = UDim2.fromScale(1, 1)
        btn.ZIndex = 5
        btn.Parent = card
        local icon = UITheme.label({ Name = "Icon", Text = ICON[r], Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 84),
            TextXAlignment = Enum.TextXAlignment.Center, TextSize = 72 })
        icon.Parent = card
        local name = UITheme.label({ Name = "Name", Text = NAME[r], Position = UDim2.fromOffset(0, 102), Size = UDim2.new(1, 0, 0, 34),
            TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 30, TextColor3 = COLOR[r] })
        name.Parent = card
        local line = UITheme.label({ Name = "Line", Text = "", Position = UDim2.fromOffset(12, 138), Size = UDim2.new(1, -24, 0, 42),
            TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, FontFace = UITheme.F.bold, TextSize = 17, TextColor3 = T.text })
        line.Parent = card
        local pill = Instance.new("Frame")
        pill.Name = "Pill"
        pill.AnchorPoint = Vector2.new(0.5, 0)
        pill.Position = UDim2.new(0.5, 0, 0, 188)
        pill.Size = UDim2.fromOffset(170, 38)
        pill.BackgroundColor3 = T.money
        pill.BackgroundTransparency = 0.15
        pill.BorderSizePixel = 0
        pill.Parent = card
        UITheme.corner(pill, 19)
        local pillText = UITheme.label({ Name = "Text", Text = "", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.display, TextSize = 20, TextColor3 = T.bgDeep })
        pillText.Parent = pill
        local dots = UITheme.label({ Name = "Dots", Text = "", Position = UDim2.fromOffset(0, 236), Size = UDim2.new(1, 0, 0, 26),
            TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 24, TextColor3 = COLOR[r] })
        dots.Parent = card
        local key = UITheme.caption(UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and "tap" or ("press " .. i),
            { Position = UDim2.fromOffset(0, 266), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
        key.Parent = card
        local lock = Instance.new("Frame")
        lock.Name = "Lock"
        lock.Size = UDim2.fromScale(1, 1)
        lock.BackgroundColor3 = Color3.new(0, 0, 0)
        lock.BackgroundTransparency = 0.35
        lock.BorderSizePixel = 0
        lock.ZIndex = 4
        lock.Visible = false
        lock.Parent = card
        UITheme.corner(lock, 22)
        local lockText = UITheme.label({ Name = "Text", Text = "🔒\nLocked", Size = UDim2.fromScale(1, 1),
            TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, FontFace = UITheme.F.display, TextSize = 26, ZIndex = 4 })
        lockText.Parent = lock
        local cs = Instance.new("UIScale")
        cs.Parent = card
        cards[r] = { card = card, btn = btn, line = line, pill = pill, pillText = pillText, dots = dots, lock = lock,
            lockText = lockText, scale = cs, stroke = card:FindFirstChild("Stroke") }
        btn.Activated:Connect(function() self:vote(r) end)
    end

    local stamp = UITheme.label({ Name = "Stamp", Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(700, 140), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextSize = 110, TextColor3 = T.gold, TextStrokeTransparency = 0.2, Rotation = -6, Visible = false, ZIndex = 10 })
    stamp.Parent = root
    self._u = { screen = screen, root = root, dim = dim, title = title, sub = sub, fill = fill, cards = cards, stamp = stamp }
end

function GetawayVote:vote(route)
    local st = self._state
    if not st or st.phase ~= "vote" then return end
    local opt = st.options and st.options[route]
    if not opt or opt.ok == false then return end
    st.mine = route
    self:_paint()
    local f = ReplicatedStorage:FindFirstChild("Remotes")
    local r = f and f:FindFirstChild("Getaway")
    if r then r:FireServer({ action = "vote", route = route }) end
end

function GetawayVote:_paint()
    local st = self._state
    local u = self._u
    if not st or not u then return end
    for _, r in ipairs(ROUTES) do
        local c = u.cards[r]
        local opt = (st.options or {})[r] or {}
        local locked = opt.ok == false
        c.lock.Visible = locked
        c.lockText.Text = "🔒\n" .. tostring(opt.why or "Locked")
        -- one simple line + one money pill per card
        local carPct = tonumber(opt.carPct) or 0
        if r == "boat" then
            c.line.Text = "Speedboat across the ocean. Always works!"
        elseif r == "heli" then
            c.line.Text = locked and "Only if NOBODY got caught" or "Fly away over the city!"
        else
            c.line.Text = "Floor it! Your car's power counts double"
        end
        local total = tonumber(opt.pct) or 0
        c.pillText.Text = total > 0 and (pctText(total) .. " CASH") or "SAFE BET"
        c.pill.BackgroundColor3 = total > 0 and T.money or T.faint
        local n = (st.votes or {})[r] or 0
        c.dots.Text = n > 0 and string.rep("● ", n) or ""
        local mine = st.mine == r
        c.scale.Scale = mine and 1.06 or 1
        if c.stroke then c.stroke.Thickness = mine and 5 or 2 end
        local _ = carPct
    end
    local voted, voters = st.voted or 0, st.voters or 1
    local driverNote = st.driver and ("  ·  🏎 " .. tostring(st.driver) .. "'s vote counts x2") or ""
    u.sub.Text = (st.mine and string.format("You picked %s!  (%d/%d voted)", NAME[st.mine], voted, voters)
        or string.format("Tap a card! Most votes wins.  (%d/%d voted)", voted, voters)) .. driverNote
end

function GetawayVote:_show(payload)
    local u = self._u
    self._state = {
        phase = "vote", endsAt = tonumber(payload.endsAt) or (Workspace:GetServerTimeNow() + 8),
        duration = tonumber(payload.duration) or 8, options = payload.options or {}, votes = {}, voted = 0,
        voters = tonumber(payload.voters) or 1, mine = nil,
        driver = type(payload.driver) == "string" and payload.driver or nil,   -- Driver role: vote x2
    }
    u.stamp.Visible = false
    u.title.Text = (payload.loud and "SIRENS! " or "") .. "HOW DO WE ESCAPE?"
    for _, r in ipairs(ROUTES) do u.cards[r].card.Visible = true end
    u.screen.Enabled = true
    u.root.Position = UDim2.fromScale(0.5, 0.56)
    TweenService:Create(u.root, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
    self:_paint()
end

function GetawayVote:_decided(route)
    local st = self._state
    local u = self._u
    if not u then return end
    if st then st.phase = "decided" end
    for _, r in ipairs(ROUTES) do
        u.cards[r].card.Visible = (r == route)
    end
    u.stamp.Text = (NAME[route] or "BOAT") .. "!"
    u.stamp.Visible = true
    u.stamp.TextTransparency = 0
    u.stamp.TextSize = 170
    TweenService:Create(u.stamp, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 110 }):Play()
    local token = {}
    self._hideToken = token
    task.delay(1.6, function()
        if self._hideToken == token then self:_hide() end
    end)
end

function GetawayVote:_hide()
    self._state = nil
    if self._u then self._u.screen.Enabled = false end
end

function GetawayVote:start()
    if self._started then return end
    self._started = true
    self:_build()
    task.spawn(function()
        local f = ReplicatedStorage:WaitForChild("Remotes", 30)
        local remote = f and f:WaitForChild("Getaway", 60)
        if not remote then warn("[GetawayVote] no Getaway remote") return end
        remote.OnClientEvent:Connect(function(msg)
            if type(msg) ~= "table" then return end
            local ok, err = pcall(function()
                if msg.phase == "vote" then
                    self._hideToken = nil
                    self:_show(msg)
                elseif msg.phase == "tally" and self._state then
                    self._state.votes = msg.votes or {}
                    self._state.voted = msg.voted or 0
                    self._state.voters = msg.voters or self._state.voters
                    self:_paint()
                elseif msg.phase == "decided" then
                    if not self._state then self._state = { phase = "decided", options = {} } end
                    self:_decided(msg.route)
                elseif msg.phase == "scene" or msg.phase == "cancel" then
                    self:_hide()
                end
            end)
            if not ok then warn("[GetawayVote]", err) end
        end)
    end)
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed or not self._state or self._state.phase ~= "vote" then return end
        local r = KEYS[input.KeyCode]
        if r then self:vote(r) end
    end)
    RunService.RenderStepped:Connect(function()
        local st = self._state
        if not st or st.phase ~= "vote" or not self._u then return end
        local left = math.max(0, st.endsAt - Workspace:GetServerTimeNow())
        self._u.fill.Size = UDim2.fromScale(math.clamp(left / math.max(0.1, st.duration), 0, 1), 1)
    end)
    print("[HEIST CREW] GetawayVote mounted ✅")
end

return GetawayVote
