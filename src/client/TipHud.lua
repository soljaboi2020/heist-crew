--[[
    HEIST CREW — TipHud  (v1.1, v2.1 UI overhaul)
    ────────────────────────────────────────────────
    First-run coaching from the Boss. Only while the player is a "Rookie"
    (server attribute: hasn't finished a heist yet). Each tip shows ONCE per
    session, at the moment it's useful.

    v2.1 (Malachi: the tip card was hard to read + sat on top of other cards):
      • lives in the UITheme "left" slot — nothing else goes there, so it can't
        overlap anything
      • tips are SHORT (one line of heading, one short sentence)
      • ONE at a time: a new tip waits in a queue until the current one is
        gone; urgent ones (alarm / spotted / jail) jump the queue
      • auto-dismiss after 7 s (or the ✕)

    Triggers: joining (after the IntroCam fly-over, if it plays) · first time
    standing in a heist door · first run starting · first time being spotted ·
    first bag · near the car with a bag · first alarm · first time in the car ·
    reaching the vault · lasers ahead · first time in jail.

    v3.2 "MIAMI HUD": night-purple card with a gold glow, the Boss's real hat
    as the icon (UITheme swaps the 🎩 emoji for his Fedora picture), bigger
    words, even shorter tips, a drawn X you can actually tap (44 px).

    v3.1: quiet while the player attribute `Tutorial` is set (TutorialService /
    TutorialHud run the first-time walkthrough and own the coaching then).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C
local I = UITheme.ICON

local TipHud = {}
local localPlayer = Players.LocalPlayer

local SHOW_TIME = 7
local GAP_TIME = 0.8
local URGENT = { alarm = true, spotted = true, jail = true }

local TIPS = {
    welcome = { "Welcome to The Vault!", "The bar at the top says what to do.", I.boss },
    portal  = { "Heist door", "Stay here. Your crew can join you!", I.door },
    jail    = { "Busted!", "A friend can get you out. Hang on!", I.jail },
    start   = { "You're in!", "Stay out of flashlights and red beams.", I.eye },
    spotted = { "They see you!", "Hide! Full meter = back to the door.", I.eye },
    bag     = { "Got a bag!", "Take it to the car.", I.bag },
    trunk   = { "Load it up", "Hold E at the back of the car.", I.car },
    alarm   = { "Alarm!", "Load the car and hit GO! Fast!", I.alarm },
    drive   = { "In the car!", "Hit GO! Then vote how to escape.", I.car },
    vault   = { "The vault", "Put the drill on it. Stuck? Hold E.", I.drill },
    lasers  = { "Lasers!", "Walk through when they blink off.", I.alarm },
}

function TipHud:_build()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("TipHud")
    if old then old:Destroy() end

    local card = Instance.new("CanvasGroup")
    card.Name = "BossTip"
    card.LayoutOrder = 1
    card.Size = UDim2.fromOffset(UITheme.L.TIP_W, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = Color3.new(1, 1, 1)     -- (v3.2) the gradient carries the colour
    card.BackgroundTransparency = 0.04
    card.GroupTransparency = 1
    card.Visible = false
    card.Parent = UITheme.slot("left")
    UITheme.corner(card, 18)
    local stroke = UITheme.stroke(card, T.gold, 0.15, 2.5)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, T.bg:Lerp(T.gold, 0.28)),
        ColorSequenceKeypoint.new(0.45, T.bg),
        ColorSequenceKeypoint.new(1, T.bgDeep),
    })
    g.Parent = card
    UITheme.padding(card, 12, 12)
    local scale = Instance.new("UIScale")
    scale.Parent = card

    local badge = UITheme.badge(I.boss, T.gold, 54)
    badge.Parent = card
    local col = Instance.new("Frame")
    col.BackgroundTransparency = 1
    col.Position = UDim2.fromOffset(64, 0)
    col.Size = UDim2.new(1, -64, 0, 0)
    col.AutomaticSize = Enum.AutomaticSize.Y
    col.Parent = card
    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 2)
    list.Parent = col
    UITheme.caption("The Boss says", { LayoutOrder = 1, Size = UDim2.new(1, -34, 0, 16), TextColor3 = T.gold }).Parent = col
    local head = UITheme.label({ LayoutOrder = 2, Size = UDim2.new(1, -34, 0, 28), FontFace = UITheme.F.display,
        TextSize = 24, TextScaled = true })
    do local c = Instance.new("UITextSizeConstraint") c.MaxTextSize = 24 c.MinTextSize = 14 c.Parent = head end
    head.Parent = col
    local body = UITheme.label({ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = UITheme.F.bold,
        TextSize = UITheme.T.body, TextColor3 = T.text })
    body.Parent = col

    local close = Instance.new("TextButton")
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, 10, 0, -10)      -- inside the card padding (a CanvasGroup clips)
    close.Size = UDim2.fromOffset(44, 44)             -- (v3.2) a real touch target
    close.BackgroundTransparency = 1
    close.Text = ""
    close.ZIndex = 3
    close.Parent = card
    local x = UITheme.closeX(14, T.muted, 3)          -- drawn: BuilderSans has no ✕ glyph
    x.AnchorPoint = Vector2.new(0.5, 0.5)
    x.Position = UDim2.fromScale(0.5, 0.5)
    x.Parent = close
    close.Activated:Connect(function() self:_hide() end)
    self._u = { card = card, head = head, body = body, badge = badge, scale = scale, stroke = stroke }
end

function TipHud:_hide()
    local u = self._u
    if not self._showing then return end
    self._showing = nil
    self._token = {}
    local c = u.card
    local out = TweenService:Create(c, TweenInfo.new(0.3), { GroupTransparency = 1 })
    out:Play()
    out.Completed:Connect(function()
        if not self._showing then c.Visible = false end
    end)
    task.delay(GAP_TIME, function() self:_next() end)
end

function TipHud:_next()
    if self._showing then return end
    local key = table.remove(self._queue, 1)
    if key then self:_display(key) end
end

function TipHud:_display(key)
    local tip = TIPS[key]
    if not tip then return end
    local u = self._u
    self._showing = key
    u.head.Text = tip[1]
    u.body.Text = tip[2]
    UITheme.setBadge(u.badge, tip[3] or I.boss, URGENT[key] and T.danger or T.gold)
    u.stroke.Color = URGENT[key] and T.danger or T.gold
    u.card.Visible = true
    u.card.GroupTransparency = 1
    u.scale.Scale = 0.9
    TweenService:Create(u.card, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { GroupTransparency = 0 }):Play()
    TweenService:Create(u.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
    local token = {}
    self._token = token
    task.delay(SHOW_TIME, function() if self._token == token then self:_hide() end end)
end

function TipHud:show(key)
    if self._seen[key] then return end
    if not localPlayer:GetAttribute("Rookie") then return end
    -- (tutorial hook, v3.1) the first-time tutorial (TutorialHud) owns the coaching while
    -- it runs: no tips, and the tip isn't marked seen, so it can still show afterwards
    if localPlayer:GetAttribute("Tutorial") then return end
    if not TIPS[key] then return end
    self._seen[key] = true
    if not self._showing then
        self:_display(key)
    elseif URGENT[key] and not URGENT[self._showing] then
        -- urgent: swap straight in
        table.insert(self._queue, 1, key)
        self:_hide()
    else
        table.insert(self._queue, key)
        while #self._queue > 3 do table.remove(self._queue, 1) end
    end
end

function TipHud:start()
    self._seen = {}
    self._queue = {}
    self:_build()
    -- (tutorial hook, v3.1) the tutorial starting clears any tip on screen + the queue
    localPlayer:GetAttributeChangedSignal("Tutorial"):Connect(function()
        if localPlayer:GetAttribute("Tutorial") then
            self._queue = {}
            if self._showing then self:_hide() end
        end
    end)

    -- v2.0: wait for the first-join fly-over (IntroCam) to finish first
    task.delay(6, function()
        local t0 = os.clock()
        while localPlayer:GetAttribute("IntroPlaying") and os.clock() - t0 < 20 do task.wait(0.25) end
        if localPlayer:GetAttribute("IntroCamDone") then task.wait(1) end
        self:show("welcome")
    end)
    localPlayer:GetAttributeChangedSignal("InPortal"):Connect(function()
        if localPlayer:GetAttribute("InPortal") then self:show("portal") end
    end)
    localPlayer:GetAttributeChangedSignal("Jailed"):Connect(function()
        if localPlayer:GetAttribute("Jailed") then self:show("jail") end
    end)

    task.spawn(function()
        local info = Remotes.getRemote(Remotes.NAMES.JobInfo, "RemoteEvent")
        if info then
            info.OnClientEvent:Connect(function(i)
                i = i or {}
                if i.stage == "ACTIVE" then self:show("start") end
                if i.alarm then self:show("alarm") end
                for _, t in ipairs(i.targets or {}) do
                    local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if root and typeof(t.pos) == "Vector3" and (t.pos - root.Position).Magnitude < 18 then
                        if t.kind == "vault" then self:show("vault") end
                        if t.kind == "car" and localPlayer:GetAttribute("CarryingLoot") then self:show("trunk") end
                    end
                end
            end)
        end
    end)

    local function onSusp()
        local v = math.max(localPlayer:GetAttribute("GuardSuspicion") or 0, localPlayer:GetAttribute("CameraSuspicion") or 0)
        if v > 0.25 then self:show("spotted") end
    end
    localPlayer:GetAttributeChangedSignal("GuardSuspicion"):Connect(onSusp)
    localPlayer:GetAttributeChangedSignal("CameraSuspicion"):Connect(onSusp)
    localPlayer:GetAttributeChangedSignal("CarryingLoot"):Connect(function()
        if localPlayer:GetAttribute("CarryingLoot") then self:show("bag") end
    end)

    -- driving + lasers: cheap polling
    task.spawn(function()
        while true do
            task.wait(0.5)
            local char = localPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            -- (v3.0) nobody drives: any seat in the getaway car (model with CarId)
            local seat = hum and hum.SeatPart
            local carModel = seat and seat:FindFirstAncestorWhichIsA("Model")
            while carModel and carModel:GetAttribute("CarId") == nil do
                carModel = carModel:FindFirstAncestorWhichIsA("Model")
            end
            if carModel then self:show("drive") end
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root and not self._seen.lasers then
                -- (fix v1.1) beams are CanQuery=false, so find them by the "Laser" tag
                for _, p in ipairs(game:GetService("CollectionService"):GetTagged("Laser")) do
                    if p:IsA("BasePart") and p.Transparency < 0.5 and (p.Position - root.Position).Magnitude < 14 then
                        self:show("lasers")
                        break
                    end
                end
            end
        end
    end)
    print("[HEIST CREW] TipHud mounted ✅")
end

return TipHud
