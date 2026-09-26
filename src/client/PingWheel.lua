--[[
    HEIST CREW — PingWheel  (v2.2 "TALK WITHOUT TALKING")
    ────────────────────────────────────────────────
    Ideas #8: ping / spot + a quick-chat wheel, so a crew can talk with chat
    OFF. The server (PingService) decides what you pinged; this file draws it.

      📍 PING      tap T · middle mouse · gamepad D-pad UP · the 📍 in the
                   middle of the wheel (phones)
                   → aims where your mouse is (screen centre when the mouse is
                     locked / on a gamepad / on a phone) and sends it.
                   Every teammate sees a marker THROUGH WALLS for 6 s (9 s for a
                   Lookout's guard/camera pings), then it fades:
                     👮 GUARD red · 📷 CAMERA orange · 💰 LOOT gold ·
                     🚪 DOOR / 🔑 KEYCARD blue · 🕳 VENT / HATCH purple · 📍 LOOK white
                   with the distance and who pinged it (in their role colour),
                   a ping sound, and a small arrow on the screen edge when it's
                   behind you. A pinged guard also gets a red Highlight for 3 s.
                   Max 3 markers per player — a 4th replaces their oldest.

      💬 QUICK CHAT  HOLD T · hold gamepad D-pad DOWN · the 💬 button (phones)
                   → a 6-slice wheel: 👋 Over here! · ✋ Wait! · 🏃 Go go go! ·
                     👮 Guard! · 🆘 Need help! · 👍 Good job!
                   Point at a slice (mouse / right stick / 1-6 keys, or tap it)
                   and let go. The line pops up in a speech bubble over your head
                   and as a toast for the crew. Works with chat disabled — only
                   the slice NUMBER is sent, never text.

    Remotes: "Ping" + "QuickChat" (made by PingService on the server).

    PUBLIC API:
        PingWheel:start()
        PingWheel:ping() -> sent:boolean            (aim + send)
        PingWheel:openWheel(mode)  mode = "hold" | "pad" | "touch"
        PingWheel:closeWheel()
        PingWheel:pick(index)                       (send quick-chat line 1..6)
        PingWheel.LINES = {{text, icon, color}, ...}
        (tests) PingWheel:_onPing(payload) · PingWheel:_onChat(payload) · PingWheel:activeCount(userId?)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local PingWheel = {}
local localPlayer = Players.LocalPlayer

PingWheel.LINES = {
    { text = "Over here!", icon = "👋", color = "white" },
    { text = "Wait!",      icon = "✋", color = "gold" },
    { text = "Go go go!",  icon = "🏃", color = "green" },
    { text = "Guard!",     icon = "👮", color = "red" },
    { text = "Need help!", icon = "🆘", color = "gold" },
    { text = "Good job!",  icon = "👍", color = "green" },
}

local KIND = {
    guard  = { icon = "👮", color = T.danger },
    camera = { icon = "📷", color = Color3.fromRGB(251, 146, 60) },
    loot   = { icon = "💰", color = T.gold },
    door   = { icon = "🚪", color = T.info },
    vent   = { icon = "🕳", color = T.purple },
    look   = { icon = "📍", color = T.text },
}
local LABEL_ICON = { KEYCARD = "🔑", VAULT = "🔒", HATCH = "🕳" }

local PING_KEY = Enum.KeyCode.T
local HOLD_TIME = 0.2              -- hold T this long → wheel instead of ping
local LOCAL_COOLDOWN = 0.7         -- matches the server; saves pointless sends
local MAX_PER_PLAYER = 3
local FADE = 1                     -- last second of a marker's life fades out
local GUARD_GLOW = 3               -- seconds a pinged guard stays highlighted
local BUBBLE_TIME = 3
local WHEEL_R = 118                -- design px, slice centres from the wheel centre
local SLICE = 88
local EDGE = 64
local SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"

local ROLE_COLOR = {}
for _, r in ipairs(Constants.ROLES or {}) do ROLE_COLOR[r.id] = UITheme.rgb(r.color) end
local PALETTE = { T.info, T.pink, T.money, T.gold, T.purple, T.danger }

local function tween(obj, t, props, style)
    local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function playerColor(p)
    local role = p and p:GetAttribute("Role")
    if role and ROLE_COLOR[role] then return ROLE_COLOR[role] end
    local id = p and p.UserId or 0
    return PALETTE[(math.abs(id) % #PALETTE) + 1]
end

local function isTouch()
    return PingWheel._forceTouch == true or UITheme.isTouch()
end

local function getawayVoteOpen()
    for _, car in ipairs(CollectionService:GetTagged("GetawayCar")) do
        if car:GetAttribute("GetawayPhase") == "vote" then return true end
    end
    return false
end

-- ── ping markers ───────────────────────────────────────────────────────
local function adorneeFor(target)
    if typeof(target) ~= "Instance" or not target.Parent then return nil end
    if target:IsA("Model") then
        return target:FindFirstChild("Head") or target.PrimaryPart
            or target:FindFirstChild("HumanoidRootPart") or target:FindFirstChildWhichIsA("BasePart", true)
    end
    if target:IsA("BasePart") then return target end
    return nil
end

function PingWheel:_anchorAt(pos)
    local folder = workspace:FindFirstChild("HC_Pings")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "HC_Pings"
        folder.Parent = workspace
    end
    local a = Instance.new("Part")
    a.Name = "PingAnchor"
    a.Size = Vector3.new(0.2, 0.2, 0.2)
    a.Transparency = 1
    a.Anchored = true
    a.CanCollide = false
    a.CanQuery = false
    a.CanTouch = false
    a.CastShadow = false
    a.CFrame = CFrame.new(pos)
    a.Parent = folder
    return a
end

function PingWheel:_buildMarker(rec)
    local style = KIND[rec.kind] or KIND.look
    local icon = LABEL_ICON[rec.label] or style.icon
    local col = style.color

    local bb = Instance.new("BillboardGui")
    bb.Name = "HC_Ping_" .. rec.id
    bb.Size = UDim2.fromOffset(170, 104)
    bb.AlwaysOnTop = true              -- short-lived pings may show through walls (V2 §0 exception)
    bb.LightInfluence = 0
    bb.ResetOnSpawn = false
    bb.MaxDistance = 1000
    bb.Adornee = rec.adornee
    bb.StudsOffsetWorldSpace = Vector3.new(0, rec.follow and 2.6 or 1.6, 0)

    local cg = Instance.new("CanvasGroup")
    cg.Name = "Body"
    cg.BackgroundTransparency = 1
    cg.Size = UDim2.fromScale(1, 1)
    cg.Parent = bb
    local scale = Instance.new("UIScale")
    scale.Scale = 0.4
    scale.Parent = cg

    local name = UITheme.label({ Name = "Who", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.fromOffset(170, 18), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14,
        FontFace = UITheme.F.bold, TextColor3 = rec.byColor, Text = rec.byName,
        TextStrokeTransparency = 0.35, TextStrokeColor3 = Color3.new() })
    name.Parent = cg

    local badge = UITheme.badge(icon, col, 44, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20) })
    badge.BackgroundColor3 = T.bgDeep
    badge.BackgroundTransparency = 0.15
    badge.Parent = cg

    local pill = UITheme.label({ Name = "Pill", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70),
        Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 15, RichText = true,
        BackgroundColor3 = T.bgDeep, BackgroundTransparency = 0.2, Text = rec.label })
    UITheme.corner(pill, 13)
    UITheme.padding(pill, 10, 0)
    UITheme.stroke(pill, col, 0.3, 1.5)
    pill.Parent = cg

    bb.Parent = localPlayer:WaitForChild("PlayerGui")
    tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)

    -- off-screen arrow (screen edge), WaypointHud style
    local edge = Instance.new("Frame")
    edge.Name = "Edge_" .. rec.id
    edge.AnchorPoint = Vector2.new(0.5, 0.5)
    edge.Size = UDim2.fromOffset(34, 34)
    edge.BackgroundTransparency = 1
    edge.Visible = false
    edge.Parent = self._screen
    UITheme.autoScale(edge)
    local eb = UITheme.badge(icon, col, 34)
    eb.BackgroundColor3 = T.bgDeep
    eb.BackgroundTransparency = 0.15
    eb.Parent = edge
    local arrow = UITheme.label({ Name = "Arrow", Text = "▲", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(24, 24),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 20, TextColor3 = col,
        TextStrokeTransparency = 0.4, TextStrokeColor3 = Color3.new() })
    arrow.Parent = edge

    rec.bb, rec.cg, rec.pill, rec.edge, rec.arrow = bb, cg, pill, edge, arrow
end

function PingWheel:_removePing(rec)
    if rec.dead then return end
    rec.dead = true
    for i, r in ipairs(self._pings) do
        if r == rec then table.remove(self._pings, i) break end
    end
    local mine = self._byPlayer[rec.byId]
    if mine then
        for i, r in ipairs(mine) do
            if r == rec then table.remove(mine, i) break end
        end
    end
    for _, x in ipairs({ rec.bb, rec.edge, rec.anchor, rec.highlight }) do
        if x and x.Parent then x:Destroy() end
    end
end

function PingWheel:_highlightGuard(model)
    if not (typeof(model) == "Instance" and model:IsA("Model") and model.Parent) then return nil end
    local old = model:FindFirstChild("HC_Ping")
    if old then old:Destroy() end
    local h = Instance.new("Highlight")
    h.Name = "HC_Ping"
    h.Adornee = model
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.FillColor = T.danger
    h.FillTransparency = 0.45
    h.OutlineColor = T.danger:Lerp(T.text, 0.3)
    h.OutlineTransparency = 0
    h.Parent = model
    task.delay(GUARD_GLOW - 0.6, function()
        if h.Parent then tween(h, 0.6, { FillTransparency = 1, OutlineTransparency = 1 }) end
    end)
    task.delay(GUARD_GLOW, function()
        if h.Parent then h:Destroy() end
    end)
    return h
end

function PingWheel:_sound(kind)
    local s = self._snd
    if not s then return end
    pcall(function()
        s.PlaybackSpeed = kind == "guard" and 1.3 or kind == "loot" and 1.12 or 1
        s.TimePosition = 0
        s:Play()
    end)
end

function PingWheel:_onPing(payload)
    if type(payload) ~= "table" or typeof(payload.pos) ~= "Vector3" then return end
    local by = payload.by
    local byId = (typeof(by) == "Instance" and by:IsA("Player")) and by.UserId or 0
    local target = payload.target
    local kind = KIND[payload.kind] and payload.kind or "look"

    -- same player pinged the same guard/thing again → just refresh it
    local mine = self._byPlayer[byId] or {}
    self._byPlayer[byId] = mine
    for _, r in ipairs(mine) do
        if target ~= nil and r.target == target then self:_removePing(r) break end
    end
    while #mine >= MAX_PER_PLAYER do self:_removePing(mine[1]) end

    local follow = (kind == "guard" or kind == "camera") and adorneeFor(target) or nil
    local rec = {
        id = payload.id or 0, byId = byId, kind = kind, label = tostring(payload.label or "LOOK"),
        pos = payload.pos, target = target, follow = follow, born = os.clock(),
        life = math.clamp(tonumber(payload.life) or 6, 1, 15),
        byName = (typeof(by) == "Instance" and by:IsA("Player")) and by.DisplayName or "Crew",
        byColor = playerColor(typeof(by) == "Instance" and by:IsA("Player") and by or nil),
    }
    if follow then
        rec.adornee = follow
    else
        rec.anchor = self:_anchorAt(payload.pos)
        rec.adornee = rec.anchor
    end
    self:_buildMarker(rec)
    if kind == "guard" then rec.highlight = self:_highlightGuard(target) end
    table.insert(mine, rec)
    table.insert(self._pings, rec)
    self:_sound(kind)
end

function PingWheel:activeCount(userId)
    if userId then return #(self._byPlayer[userId] or {}) end
    return #self._pings
end

function PingWheel:_tick()
    local cam = workspace.CurrentCamera
    local char = localPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local now = os.clock()
    local sc = UITheme.scale()
    for i = #self._pings, 1, -1 do
        local rec = self._pings[i]
        local age = now - rec.born
        if age >= rec.life or (rec.follow and not rec.follow.Parent and not rec.anchor) then
            self:_removePing(rec)
            continue
        end
        local pos = (rec.follow and rec.follow.Parent) and rec.follow.Position or rec.pos
        local alpha = math.clamp((rec.life - age) / FADE, 0, 1)
        if rec.cg then rec.cg.GroupTransparency = 1 - alpha end
        if rec.pill and root then
            local meters = math.floor((pos - root.Position).Magnitude * 0.28 + 0.5)
            rec.pill.Text = string.format('%s  <font color="#%s">%dm</font>', rec.label, T.muted:ToHex(), meters)
        end
        -- edge arrow when off-screen
        if cam and rec.edge then
            local sp, onScreen = cam:WorldToViewportPoint(pos)
            if onScreen and sp.Z > 0 then
                rec.edge.Visible = false
            else
                local vp = cam.ViewportSize
                local centre = vp / 2
                local rel = cam.CFrame:PointToObjectSpace(pos)
                local dir = Vector2.new(rel.X, -rel.Y)
                if dir.Magnitude < 1e-3 then dir = Vector2.new(0, 1) end
                dir = dir.Unit
                local e = EDGE * sc
                local sx = (centre.X - e) / math.max(math.abs(dir.X), 1e-3)
                local sy = (centre.Y - e) / math.max(math.abs(dir.Y), 1e-3)
                local p = centre + dir * math.min(sx, sy)
                rec.edge.Visible = alpha > 0.05
                rec.edge.Position = UDim2.fromOffset(p.X, p.Y)
                rec.arrow.Position = UDim2.new(0.5, dir.X * 30, 0.5, dir.Y * 30)
                rec.arrow.Rotation = math.deg(math.atan2(dir.X, -dir.Y))
                rec.arrow.TextTransparency = 1 - alpha
            end
        end
    end
end

-- ── sending a ping ─────────────────────────────────────────────────────
function PingWheel:_aimRay(centre)
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local vp = cam.ViewportSize
    if centre or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter or isTouch() then
        return cam:ViewportPointToRay(vp.X / 2, vp.Y / 2)
    end
    local m = UserInputService:GetMouseLocation()
    return cam:ViewportPointToRay(m.X, m.Y)
end

function PingWheel:ping(centre)
    if not self._pingRemote then return false end
    local now = os.clock()
    if now - (self._lastPing or -99) < LOCAL_COOLDOWN then return false end
    local ray = self:_aimRay(centre)
    if not ray then return false end
    self._lastPing = now
    self._pingRemote:FireServer(ray.Origin, ray.Direction.Unit)
    return true
end

-- ── quick chat ─────────────────────────────────────────────────────────
function PingWheel:pick(index)
    local line = PingWheel.LINES[index]
    if not line or not self._chatRemote then return false end
    local now = os.clock()
    if now - (self._lastChat or -99) < 1.5 then return false end
    self._lastChat = now
    self._chatRemote:FireServer(index)
    return true
end

function PingWheel:_bubble(player, line)
    local char = player.Character
    local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
    if not head then return end
    local pg = localPlayer:FindFirstChild("PlayerGui")
    if not pg then return end
    local key = "HC_ChatBubble_" .. player.UserId
    local old = pg:FindFirstChild(key)
    if old then old:Destroy() end

    local bb = Instance.new("BillboardGui")
    bb.Name = key
    bb.Adornee = head
    bb.Size = UDim2.fromOffset(230, 56)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
    bb.AlwaysOnTop = false            -- a normal speech bubble (NPC-style exception)
    bb.LightInfluence = 0
    bb.MaxDistance = 140
    bb.ResetOnSpawn = false

    local cg = Instance.new("CanvasGroup")
    cg.BackgroundTransparency = 1
    cg.Size = UDim2.fromScale(1, 1)
    cg.Parent = bb
    local card = Instance.new("Frame")
    card.Name = "Bubble"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.45)
    card.Size = UDim2.fromOffset(0, 42)
    card.AutomaticSize = Enum.AutomaticSize.X
    card.BackgroundColor3 = Color3.fromRGB(250, 250, 252)
    card.BorderSizePixel = 0
    card.Parent = cg
    UITheme.corner(card, 21)
    UITheme.stroke(card, playerColor(player), 0.1, 3)
    UITheme.padding(card, 14, 0)
    local row = Instance.new("UIListLayout")
    row.FillDirection = Enum.FillDirection.Horizontal
    row.VerticalAlignment = Enum.VerticalAlignment.Center
    row.SortOrder = Enum.SortOrder.LayoutOrder
    row.Padding = UDim.new(0, 6)
    row.Parent = card
    UITheme.label({ LayoutOrder = 1, Text = line.icon, Size = UDim2.fromOffset(28, 42), TextSize = 24,
        TextXAlignment = Enum.TextXAlignment.Center }).Parent = card
    UITheme.label({ Name = "Text", LayoutOrder = 2, Text = line.text, Size = UDim2.fromOffset(0, 42),
        AutomaticSize = Enum.AutomaticSize.X, TextSize = 20, FontFace = UITheme.F.display,
        TextColor3 = T.bgDeep }).Parent = card
    local scale = Instance.new("UIScale")
    scale.Scale = 0.5
    scale.Parent = cg
    bb.Parent = pg
    tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
    task.delay(BUBBLE_TIME - 0.4, function()
        if bb.Parent then tween(cg, 0.4, { GroupTransparency = 1 }) end
    end)
    task.delay(BUBBLE_TIME, function()
        if bb.Parent then bb:Destroy() end
    end)
    return bb
end

function PingWheel:_onChat(payload)
    if type(payload) ~= "table" then return end
    local line = PingWheel.LINES[payload.index]
    local by = payload.by
    if not line or not (typeof(by) == "Instance" and by:IsA("Player")) then return end
    self:_bubble(by, line)
    if by ~= localPlayer then
        pcall(function()
            local n = script.Parent:FindFirstChild("Notifications")
            if n then require(n):show(by.DisplayName .. ": " .. line.icon .. " " .. line.text, line.color, 2.5) end
        end)
    end
    self:_sound("chat")
end

-- ── the wheel ──────────────────────────────────────────────────────────
function PingWheel:_buildWheel()
    local screen = self._screen
    local shade = Instance.new("TextButton")        -- tap outside = close (phones)
    shade.Name = "WheelShade"
    shade.Text = ""
    shade.AutoButtonColor = false
    shade.BackgroundColor3 = Color3.new()
    shade.BackgroundTransparency = 0.65
    shade.Size = UDim2.fromScale(1, 1)
    shade.Visible = false
    shade.ZIndex = 5
    shade.Parent = screen
    shade.Activated:Connect(function() self:closeWheel() end)

    local wheel = Instance.new("Frame")
    wheel.Name = "Wheel"
    wheel.AnchorPoint = Vector2.new(0.5, 0.5)
    wheel.Position = UDim2.fromScale(0.5, 0.5)
    wheel.Size = UDim2.fromOffset(WHEEL_R * 2 + SLICE, WHEEL_R * 2 + SLICE)
    wheel.BackgroundTransparency = 1
    wheel.Visible = false
    wheel.ZIndex = 6
    wheel.Parent = screen
    self._wheelScale = UITheme.autoScale(wheel)

    local slices = {}
    for i, line in ipairs(PingWheel.LINES) do
        local ang = math.rad((i - 1) * 60)
        local b = Instance.new("TextButton")
        b.Name = "Slice" .. i
        b.Text = ""
        b.AutoButtonColor = false
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Position = UDim2.new(0.5, math.sin(ang) * WHEEL_R, 0.5, -math.cos(ang) * WHEEL_R)
        b.Size = UDim2.fromOffset(SLICE, SLICE)
        b.BackgroundColor3 = T.bg
        b.BackgroundTransparency = 0.1
        b.BorderSizePixel = 0
        b.ZIndex = 7
        b.Parent = wheel
        UITheme.corner(b, SLICE / 2)
        local st = UITheme.stroke(b, T.edge, 0.15, 3)
        UITheme.label({ Text = line.icon, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
            Size = UDim2.fromOffset(SLICE, 36), TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 }).Parent = b
        UITheme.label({ Text = line.text, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 50),
            Size = UDim2.fromOffset(SLICE + 20, 22), TextSize = 14, FontFace = UITheme.F.display,
            TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 }).Parent = b
        UITheme.label({ Text = tostring(i), Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(14, 14),
            TextSize = 11, FontFace = UITheme.F.mono, TextColor3 = T.faint, ZIndex = 8,
            Visible = not isTouch() }).Parent = b
        b.Activated:Connect(function()
            self:pick(i)
            self:closeWheel()
        end)
        slices[i] = { button = b, stroke = st }
    end

    local centre = Instance.new("TextButton")
    centre.Name = "Centre"
    centre.Text = ""
    centre.AutoButtonColor = true
    centre.AnchorPoint = Vector2.new(0.5, 0.5)
    centre.Position = UDim2.fromScale(0.5, 0.5)
    centre.Size = UDim2.fromOffset(84, 84)
    centre.BackgroundColor3 = T.bgDeep
    centre.BackgroundTransparency = 0.05
    centre.BorderSizePixel = 0
    centre.ZIndex = 7
    centre.Parent = wheel
    UITheme.corner(centre, 42)
    UITheme.stroke(centre, T.gold, 0.1, 3)
    UITheme.label({ Text = "📍", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
        Size = UDim2.fromOffset(84, 34), TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 }).Parent = centre
    self._centreText = UITheme.label({ Text = "PING", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46),
        Size = UDim2.fromOffset(84, 20), TextSize = 13, FontFace = UITheme.F.display, TextColor3 = T.gold,
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 })
    self._centreText.Parent = centre
    centre.Activated:Connect(function()
        self:closeWheel()
        self:ping(true)               -- phones / clicks: ping what's in the middle of the screen
    end)

    self._shade, self._wheel, self._slices = shade, wheel, slices
end

function PingWheel:_select(i)
    if self._sel == i then return end
    self._sel = i
    for k, s in ipairs(self._slices or {}) do
        local on = k == i
        s.stroke.Color = on and T.gold or T.edge
        s.button.BackgroundColor3 = on and T.bgRaised or T.bg
        s.button.Size = on and UDim2.fromOffset(SLICE + 10, SLICE + 10) or UDim2.fromOffset(SLICE, SLICE)
    end
end

-- direction (screen px, y down) → slice index, or nil inside the dead zone
local function sliceFor(v, dead)
    if v.Magnitude < dead then return nil end
    local a = math.deg(math.atan2(v.X, -v.Y)) % 360
    return math.floor(((a + 30) % 360) / 60) + 1
end
PingWheel._sliceFor = sliceFor

function PingWheel:openWheel(mode)
    if not self._wheel then return end
    self._mode = mode or "touch"
    self._cursor = Vector2.zero
    self._stick = Vector2.zero
    self._mouseStart = UserInputService:GetMouseLocation()
    self:_select(nil)
    self._centreText.Text = (self._mode == "hold") and "let go" or "PING"
    self._shade.Visible = (self._mode == "touch")
    self._wheel.Visible = true
    self._open = true
    self._wheelScale.Scale = UITheme.scale() * 0.7
    tween(self._wheelScale, 0.16, { Scale = UITheme.scale() }, Enum.EasingStyle.Back)
end

function PingWheel:closeWheel()
    self._open = false
    self._mode = nil
    if self._wheel then self._wheel.Visible = false end
    if self._shade then self._shade.Visible = false end
    self:_select(nil)
end

-- let go of T / D-pad down: send the highlighted line (nothing highlighted = cancel)
function PingWheel:_commit()
    local i = self._sel
    self:closeWheel()
    if i then self:pick(i) end
end

function PingWheel:_bindInput()
    local function blocked()
        if UserInputService:GetFocusedTextBox() then return true end
        return false
    end

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed or blocked() then return end
        local kc, ut = input.KeyCode, input.UserInputType
        if self._open and self._mode ~= "touch" then
            local n = ({ [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
                [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6 })[kc]
            if n then
                self:closeWheel()
                self:pick(n)
                return
            end
        end
        if kc == PING_KEY then
            local stamp = os.clock()
            self._tDown = stamp
            task.delay(HOLD_TIME, function()
                if self._tDown == stamp and not self._open then self:openWheel("hold") end
            end)
        elseif ut == Enum.UserInputType.MouseButton3 then
            self:ping()
        elseif kc == Enum.KeyCode.DPadUp then
            if not getawayVoteOpen() then self:ping(true) end
        elseif kc == Enum.KeyCode.DPadDown then
            if not getawayVoteOpen() then self:openWheel("pad") end
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        local kc = input.KeyCode
        if kc == PING_KEY and self._tDown then
            self._tDown = nil
            if self._open and self._mode == "hold" then
                self:_commit()
            elseif not self._open then
                self:ping()
            end
        elseif kc == Enum.KeyCode.DPadDown and self._open and self._mode == "pad" then
            self:_commit()
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not self._open then return end
        local ut, kc = input.UserInputType, input.KeyCode
        if ut == Enum.UserInputType.MouseMovement and self._mode == "hold" then
            if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
                local d = input.Delta
                self._cursor = self._cursor + Vector2.new(d.X, d.Y)
                if self._cursor.Magnitude > 120 then self._cursor = self._cursor.Unit * 120 end
            else
                local w = self._wheel
                local c = w.AbsolutePosition + w.AbsoluteSize / 2
                local m = UserInputService:GetMouseLocation()
                self._cursor = m - c
            end
            self:_select(sliceFor(self._cursor, 30 * UITheme.scale()) or self._sel)
        elseif kc == Enum.KeyCode.Thumbstick2 or kc == Enum.KeyCode.Thumbstick1 then
            local p = input.Position
            local v = Vector2.new(p.X, -p.Y)
            if v.Magnitude > 0.5 then self:_select(sliceFor(v, 0.5)) end
        end
    end)
end

-- phones: a 💬 button (the wheel's 📍 centre is the phone's ping)
function PingWheel:_buildTouchButton()
    local b = Instance.new("TextButton")
    b.Name = "ChatWheelButton"
    b.Text = ""
    b.LayoutOrder = 60
    b.Size = UDim2.fromOffset(60, 60)
    b.BackgroundColor3 = T.bg
    b.BackgroundTransparency = 0.1
    b.BorderSizePixel = 0
    UITheme.corner(b, 30)
    UITheme.stroke(b, T.info, 0.15, 2)
    UITheme.label({ Text = "💬", Size = UDim2.fromScale(1, 1), TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center }).Parent = b
    b.Parent = UITheme.slot("rightEdge")
    b.Activated:Connect(function()
        if self._open then self:closeWheel() else self:openWheel("touch") end
    end)
    self._touchButton = b
    return b
end

-- ── start ──────────────────────────────────────────────────────────────
function PingWheel:start()
    if self._started then return end   -- (v3.2) safe to call twice (init.client + tests)
    self._started = true
    self._pings = {}
    self._byPlayer = {}
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("PingWheel")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "PingWheel"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 6
    screen.Parent = pg
    self._screen = screen

    local s = Instance.new("Sound")
    s.Name = "HC_PingSound"
    s.Volume = 0.55
    pcall(function() s.SoundId = SOUND_ID end)
    s.Parent = SoundService
    self._snd = s

    self:_buildWheel()
    if isTouch() then self:_buildTouchButton() end
    self:_bindInput()

    task.spawn(function()
        self._pingRemote = Remotes.getRemote((Remotes.NAMES and Remotes.NAMES.Ping) or "Ping", "RemoteEvent")
        self._chatRemote = Remotes.getRemote((Remotes.NAMES and Remotes.NAMES.QuickChat) or "QuickChat", "RemoteEvent")
        if self._pingRemote then
            self._pingRemote.OnClientEvent:Connect(function(p)
                local ok, err = pcall(function() self:_onPing(p) end)
                if not ok then warn("[PingWheel] ping:", err) end
            end)
        end
        if self._chatRemote then
            self._chatRemote.OnClientEvent:Connect(function(p)
                local ok, err = pcall(function() self:_onChat(p) end)
                if not ok then warn("[PingWheel] chat:", err) end
            end)
        end
    end)

    RunService.RenderStepped:Connect(function()
        if #self._pings > 0 then self:_tick() end
    end)
    print("[HEIST CREW] PingWheel mounted ✅ (T ping · hold T chat)")
end

return PingWheel
