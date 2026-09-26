--[[
    HEIST CREW — WaypointHud  (v1.1, v2.1 declutter)
    ────────────────────────────────────────────────
    On-screen markers for "where do I go next". The server puts the next goals
    in JobInfo.targets ({pos, label, kind}).

    v2.1 (Malachi's playtest: "way too many chips at once — SEARCH 13m, LOOT,
    CAR, BREAKER, MARINA…"). The rule now:

      • ONE main marker — the CURRENT objective (the same step the big
        objective bar names). Big icon badge + a pill "LOOT · 12m", a soft
        pulse ring, and it sticks to the screen edge with an arrow when it's
        behind you.
      • at most 2 small extras — other targets within ~25 studs of you (a
        teammate in jail always counts as one). They fade out as they get
        further away and simply hide when off-screen.
      • never more than 3 on screen. No text chips — icons.

    Which target is "current":
        lobby      → the Boss (until you heard the plan) → then the heist door
        carrying   → the car
        alarm      → the car  (v3.0: no marina drive — the getaway is a movie;
                     the old "marina" kind is still understood but never sent)
        running    → first unfinished step of the job:
                     cases/open/loot → LOOT/SMASH · keycard → SEARCH (or KEYPAD
                     once someone has it) · door → KEYPAD · vault → DRILL · car → CAR
        fallback   → the nearest non-optional target

    v3.2: the Boss marker shows his real hat picture (UITheme badge image),
    the edge arrow is drawn (UITheme.chevron — "▲" drew as a box), bigger
    pill text, Miami colours (heist doors teal, car pink).

    kinds → colour:  boss gold · ready/portal green (the heist doors) ·
                     search/door/vault cyan · loot green · car pink ·
                     marina cyan · jail red · optional dimmed

    v2.0 lobby: the heist DOORS start a run. If the server's "ready" target
    isn't there, we add our own "HEIST DOORS" marker at the middle of the door
    row (PortalZone tags). Standing in a door (local attribute InPortal) hides
    it; once you've heard the plan (HeardPlan) the Boss marker is dropped.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C
local I = UITheme.ICON

local WaypointHud = {}
local localPlayer = Players.LocalPlayer

local COLORS = {
    boss = T.gold, ready = T.teal, portal = T.teal, jail = T.danger,
    search = T.info, door = T.info, vault = T.info, marina = T.info,
    loot = T.money, car = T.pink, optional = T.muted,
}
local MAX = 3
local NEAR = 25          -- studs: extras only inside this radius
local FADE_FROM = 17     -- extras start fading here
local EDGE = 70          -- px (design) from the screen edge for the off-screen arrow
local MAIN_SIZE = 54
local EXTRA_SIZE = 38

-- current step id → target kinds that satisfy it (in preference order)
local STEP_KINDS = {
    cases = { "loot" }, open = { "loot" }, loot = { "loot" },
    keycard = { "search", "door" }, door = { "door", "search" },
    vault = { "vault" }, car = { "car", "marina" }, cameras = { "optional" },
}

local function iconFor(t)
    local k, lab = t.kind, string.upper(tostring(t.label or ""))
    if k == "loot" then return lab == "SMASH" and I.smash or I.loot end
    if k == "vault" then return I.drill end
    if k == "door" then return I.keypad end
    if k == "optional" then return lab == "BREAKER" and I.breaker or I.optional end
    return I[k] or I.target
end

local function makeMarker(parent)
    local m = Instance.new("Frame")
    m.Name = "Marker"
    m.AnchorPoint = Vector2.new(0.5, 0)      -- top-centre = top of the badge (UIScale grows from here)
    m.Size = UDim2.fromOffset(160, MAIN_SIZE + 36)
    m.BackgroundTransparency = 1
    m.Visible = false
    m.Parent = parent
    local scale = UITheme.autoScale(m)

    local pulse = Instance.new("Frame")
    pulse.Name = "Pulse"
    pulse.AnchorPoint = Vector2.new(0.5, 0.5)
    pulse.Position = UDim2.new(0.5, 0, 0, MAIN_SIZE / 2)
    pulse.Size = UDim2.fromOffset(MAIN_SIZE, MAIN_SIZE)
    pulse.BackgroundTransparency = 1
    pulse.Parent = m
    UITheme.corner(pulse, MAIN_SIZE)
    local pulseStroke = UITheme.stroke(pulse, T.gold, 0.3, 3)

    local badge = UITheme.badge(I.target, T.gold, MAIN_SIZE)
    badge.AnchorPoint = Vector2.new(0.5, 0)
    badge.Position = UDim2.new(0.5, 0, 0, 0)
    badge.BackgroundColor3 = T.bgDeep
    badge.BackgroundTransparency = 0.15
    badge.Parent = m

    -- little pointer under the badge
    local tip = Instance.new("Frame")
    tip.Name = "Tip"
    tip.AnchorPoint = Vector2.new(0.5, 0.5)
    tip.Position = UDim2.new(0.5, 0, 0, MAIN_SIZE + 1)
    tip.Size = UDim2.fromOffset(10, 10)
    tip.Rotation = 45
    tip.BorderSizePixel = 0
    tip.Parent = m

    local pill = UITheme.label({ Name = "Pill", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, MAIN_SIZE + 8),
        Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 18, TextColor3 = T.text, RichText = true,
        BackgroundColor3 = T.bgDeep, BackgroundTransparency = 0.2 })
    UITheme.corner(pill, 14)
    UITheme.padding(pill, 10, 0)
    local pillStroke = UITheme.stroke(pill, T.gold, 0.4, 1.5)
    pill.Parent = m

    local arrow = UITheme.chevron(30, T.gold, 6)
    arrow.Name = "Arrow"
    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    arrow.Visible = false
    arrow.Parent = parent
    UITheme.autoScale(arrow)

    return { frame = m, scale = scale, badge = badge, icon = badge:FindFirstChild("Icon"), img = badge:FindFirstChild("Img"),
        ring = badge:FindFirstChild("Ring"),
        tip = tip, pill = pill, pillStroke = pillStroke, pulse = pulse, pulseStroke = pulseStroke, arrow = arrow }
end

local function setAlpha(m, a, main)
    local t = 1 - a
    m.badge.BackgroundTransparency = 0.15 + 0.85 * t
    if m.ring then m.ring.Transparency = 0.05 + 0.95 * t end
    if m.icon then m.icon.TextTransparency = t end
    if m.img then m.img.ImageTransparency = t end
    m.tip.BackgroundTransparency = main and t or 1
    m.pill.TextTransparency = t
    m.pill.BackgroundTransparency = 0.2 + 0.8 * t
    m.pillStroke.Transparency = 0.4 + 0.6 * t
end

-- middle of the heist-door row, a bit above head height (nil if no doors)
local function doorRow()
    local sum, n = Vector3.zero, 0
    for _, z in ipairs(CollectionService:GetTagged("PortalZone")) do
        if z:IsA("BasePart") then
            sum = sum + z.Position
            n = n + 1
        end
    end
    if n == 0 then return nil end
    return sum / n + Vector3.new(0, 5, 0)
end

local function currentStepId(info)
    for _, step in ipairs((info and info.steps) or {}) do
        if not step.done and not step.optional then return step.id end
    end
    return nil
end

-- nearest target of one of `kinds` (in preference order)
local function pick(list, kinds, here)
    for _, k in ipairs(kinds) do
        local best, bd = nil, math.huge
        for _, t in ipairs(list) do
            if t.kind == k then
                local d = (t.pos - here).Magnitude
                if d < bd then best, bd = t, d end
            end
        end
        if best then return best end
    end
    return nil
end

-- → main target (or nil), extras list
function WaypointHud:_choose(here, seated)
    local info = self._info or {}
    local raw = {}
    for _, t in ipairs(info.targets or {}) do
        if typeof(t.pos) == "Vector3" then table.insert(raw, t) end
    end
    if localPlayer:GetAttribute("Jailed") then return nil, {} end

    local lobby = false
    for _, t in ipairs(raw) do if t.kind == "boss" then lobby = true end end

    local main
    if lobby then
        local inPortal = localPlayer:GetAttribute("InPortal") ~= nil
        local heard = localPlayer:GetAttribute("HeardPlan") == true
        if inPortal then return nil, {} end
        if heard then
            main = pick(raw, { "ready", "portal" }, here)
            if not main then
                local row = doorRow()
                if row then main = { pos = row, label = "HEIST DOORS", kind = "portal" } end
            end
        else
            main = pick(raw, { "boss" }, here)
        end
        return main, {}      -- the lobby never needs extras
    end

    local carrying = localPlayer:GetAttribute("CarryingLoot")
    carrying = type(carrying) == "string" and carrying ~= ""
    if seated then
        main = pick(raw, { "marina" }, here)
    elseif info.alarm or carrying then
        main = pick(raw, { "car", "marina" }, here)
    else
        local kinds = STEP_KINDS[currentStepId(info) or ""]
        if kinds then main = pick(raw, kinds, here) end
        if not main then
            local best, bd = nil, math.huge
            for _, t in ipairs(raw) do
                if t.kind ~= "optional" and t.kind ~= "jail" then
                    local d = (t.pos - here).Magnitude
                    if d < bd then best, bd = t, d end
                end
            end
            main = best
        end
    end

    local extras = {}
    -- a teammate in a cell always gets a (small) marker
    local jail = pick(raw, { "jail" }, here)
    if jail and jail ~= main then table.insert(extras, jail) end
    local near = {}
    for _, t in ipairs(raw) do
        if t ~= main and t ~= jail and not (seated and t.kind == "car")
            and not (carrying and t.kind ~= "car" and t.kind ~= "marina") then
            local d = (t.pos - here).Magnitude
            if d <= NEAR then table.insert(near, { t = t, d = d }) end
        end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    for _, n in ipairs(near) do
        if #extras >= MAX - 1 then break end
        table.insert(extras, n.t)
    end
    return main, extras
end

function WaypointHud:start()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("WaypointHud")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "WaypointHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = -1          -- under every other HUD
    screen.Parent = pg

    local markers = {}
    for i = 1, MAX do markers[i] = makeMarker(screen) end
    self._info = {}

    task.spawn(function()
        local remote = Remotes.getRemote(Remotes.NAMES.JobInfo, "RemoteEvent")
        if remote then
            remote.OnClientEvent:Connect(function(info)
                self._info = type(info) == "table" and info or {}
            end)
        end
    end)

    local function hideAll()
        for _, m in ipairs(markers) do
            m.frame.Visible = false
            m.arrow.Visible = false
        end
    end

    RunService.RenderStepped:Connect(function()
        local cam = workspace.CurrentCamera
        local char = localPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not cam or not root then hideAll() return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local seated = hum and hum.SeatPart ~= nil
        local here = root.Position

        local main, extras = self:_choose(here, seated)
        local list = {}
        if main then table.insert(list, { t = main, main = true }) end
        for _, e in ipairs(extras) do
            if #list >= MAX then break end
            table.insert(list, { t = e, main = false })
        end

        local vp = cam.ViewportSize
        local sc = UITheme.scale()
        local now = os.clock()
        for i, m in ipairs(markers) do
            local entry = list[i]
            if not entry then
                m.frame.Visible = false
                m.arrow.Visible = false
                continue
            end
            local t, isMain = entry.t, entry.main
            local col = COLORS[t.kind] or T.text
            local d = (t.pos - here).Magnitude
            local alpha
            if isMain then
                alpha = math.clamp((d - 4) / 4, 0, 1)          -- fade out when you're right on top of it
            else
                alpha = 1 - math.clamp((d - FADE_FROM) / (NEAR - FADE_FROM), 0, 1)
                if t.kind == "jail" then alpha = 1 end
                alpha = alpha * 0.9
            end
            if alpha <= 0.02 then
                m.frame.Visible = false
                m.arrow.Visible = false
                continue
            end

            -- look
            local size = isMain and MAIN_SIZE or EXTRA_SIZE
            m.badge.Size = UDim2.fromOffset(size, size)
            m.badge:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, size)
            local ic = iconFor(t)
            if m.lastIcon ~= ic then
                m.lastIcon = ic
                UITheme.setBadge(m.badge, ic)
            end
            if m.icon then m.icon.TextSize = math.floor(size * 0.56) end
            if m.ring then m.ring.Color = col end
            m.tip.BackgroundColor3 = col
            m.tip.Position = UDim2.new(0.5, 0, 0, size + 1)
            m.pill.Visible = isMain
            m.pill.Position = UDim2.new(0.5, 0, 0, size + 8)
            m.pillStroke.Color = col
            local meters = math.floor(d * 0.28 + 0.5)
            m.pill.Text = string.format('%s  <font color="#%s">%dm</font>', string.upper(tostring(t.label or "")),
                T.muted:ToHex(), meters)
            m.pulse.Visible = isMain
            if isMain then
                local ph = (now * 0.9) % 1
                m.pulse.Size = UDim2.fromOffset(size * (1 + ph * 0.7), size * (1 + ph * 0.7))
                m.pulseStroke.Color = col
                m.pulseStroke.Transparency = 0.3 + 0.7 * ph
            end
            setAlpha(m, alpha, isMain)

            local sp, onScreen = cam:WorldToViewportPoint(t.pos)
            if onScreen and sp.Z > 0 then
                m.frame.Visible = true
                m.frame.Position = UDim2.fromOffset(sp.X, sp.Y - (size + 1) * sc)   -- pointer tip sits on the spot
                m.arrow.Visible = false
            elseif isMain then
                -- clamp to the screen edge, pointing toward the target
                local centre = vp / 2
                local rel = cam.CFrame:PointToObjectSpace(t.pos)
                local dir = Vector2.new(rel.X, -rel.Y)
                if dir.Magnitude < 1e-3 then dir = Vector2.new(0, 1) end
                dir = dir.Unit
                local edge = EDGE * sc
                local sx = (centre.X - edge) / math.max(math.abs(dir.X), 1e-3)
                local sy = (centre.Y - edge) / math.max(math.abs(dir.Y), 1e-3)
                local pos = centre + dir * math.min(sx, sy)
                m.frame.Visible = true
                m.frame.Position = UDim2.fromOffset(pos.X, pos.Y - size * 0.5 * sc)
                m.tip.BackgroundTransparency = 1
                m.arrow.Visible = true
                m.arrow.Position = UDim2.fromOffset(pos.X + dir.X * (size * 0.5 + 22) * sc, pos.Y + dir.Y * (size * 0.5 + 22) * sc)
                m.arrow.Rotation = math.deg(math.atan2(dir.X, -dir.Y))
                UITheme.paintShape(m.arrow, col)
            else
                m.frame.Visible = false
                m.arrow.Visible = false
            end
        end
    end)
    print("[HEIST CREW] WaypointHud mounted ✅")
end

return WaypointHud
