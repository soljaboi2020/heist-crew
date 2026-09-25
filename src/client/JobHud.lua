--[[
    HEIST CREW — JobHud
    ────────────────────────────────────────────────
    v1.0 (2026-09-25). "THE JOB" card, top-right, directly under the cash card:

        THE JOB                        LIVE
        VILLA ROSA
        (o) Cut the cameras   optional
        (v) ~~Find the keycard~~
        ( ) Crack the vault
        ─────────────────────────────────
        TAKE                          BAGS
        $4,500                       3 / 6
        [ ALARM 0:42 ]  [ SILENT ALARM ]
        ─────────────────────────────────
        LVL 4                 320 / 1,600 XP
        ▬▬▬▬▬▬▬───────────────────────────

    Collapses to "Next heist: VILLA ROSA" + the level line while the job is
    IDLE. Everything animates: steps pop when they complete, the take rolls
    up, the XP bar slides, and a LEVEL UP flash plays when Level goes up.

    v2.0: works for every job in Constants.JOBS (mart / villa / jewelry / bank —
    the server only sends the steps a job has). A red JAIL box shows while
    you're in a cell ("In jail — a teammate can break you out  0:24"), and your
    crew sees "Bob is in jail — go break them out!". Bot crewmates are listed
    under the job name.

    Listens to:
        JobInfo remote (spec §5, + v2 fields jailed = {names}, bots = {names})
        Jail remote { jailed, freeAt }  ·  player attribute Jailed
        player attributes Level / XP / XPNext
        ReplicatedStorage attribute ActiveJob (fallback before the first JobInfo)

    PUBLIC API:
        JobHud:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local JobHud = {}
local localPlayer = Players.LocalPlayer

local WIDTH = 240
local TOP = 88            -- cash card is y 14..76; its "+$X" delta drifts to ~y 96 and fades
local CIRCLE = 16

local JOB_NAME = {}
for _, j in ipairs(Constants.JOBS or {}) do JOB_NAME[j.id] = j.name end

-- ── small helpers ──────────────────────────────────────────────────────
local function tween(obj, t, props, style, dir)
    local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad,
        dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function hex(c)
    return "#" .. c:ToHex()
end

local function esc(s)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
    return s
end

local function commas(n)
    return UITheme.money(n):sub(2)
end

local function frame(props)
    local f = Instance.new("Frame")
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    for k, v in pairs(props or {}) do f[k] = v end
    return f
end

local function hairline(order)
    return frame({ Name = "Divider", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = T.line, BackgroundTransparency = 0.9 })
end

-- A small rounded chip with a dot + text. Returns chip, dot, label, (timer label).
local function makeChip(color, text, withTimer, order)
    local chip = frame({ Name = "Chip", LayoutOrder = order, Size = UDim2.fromOffset(0, 26),
        AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = color, BackgroundTransparency = 0.82,
        Visible = false })
    UITheme.corner(chip, 13)
    UITheme.stroke(chip, color, 0.45)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 9)
    pad.PaddingRight = UDim.new(0, 11)
    pad.Parent = chip
    local row = Instance.new("UIListLayout")
    row.FillDirection = Enum.FillDirection.Horizontal
    row.VerticalAlignment = Enum.VerticalAlignment.Center
    row.SortOrder = Enum.SortOrder.LayoutOrder
    row.Padding = UDim.new(0, 6)
    row.Parent = chip
    local dot = frame({ LayoutOrder = 1, Size = UDim2.fromOffset(7, 7), BackgroundColor3 = color,
        BackgroundTransparency = 0 })
    UITheme.corner(dot, 4)
    dot.Parent = chip
    local label = UITheme.label({ LayoutOrder = 2, Text = text, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 26), FontFace = UITheme.F.bold, TextSize = 12, TextColor3 = color })
    label.Parent = chip
    local timer
    if withTimer then
        timer = UITheme.label({ LayoutOrder = 3, Text = "0:00", AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.fromOffset(0, 26), FontFace = UITheme.F.mono, TextSize = 13, TextColor3 = T.text })
        timer.Parent = chip
    end
    return chip, dot, label, timer
end

-- Step marker: ring (open) / 8 dashes (optional) / green disc + drawn check (done)
local function makeCircle(parent)
    local holder = frame({ Name = "Circle", Size = UDim2.fromOffset(CIRCLE, CIRCLE), Position = UDim2.fromOffset(0, 2) })
    holder.Parent = parent
    local scale = Instance.new("UIScale")
    scale.Parent = holder

    local disc = frame({ Name = "Disc", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.money })
    UITheme.corner(disc, CIRCLE)
    disc.Parent = holder
    local ring = UITheme.stroke(disc, T.muted, 0.25, 1.5)

    -- dashed ring for optional steps: 8 short dots around the edge
    local dashes = frame({ Name = "Dashes", Size = UDim2.fromScale(1, 1), Visible = false })
    dashes.Parent = holder
    local r = CIRCLE / 2 - 1
    for i = 0, 7 do
        local a = i * math.pi / 4
        local d = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(3, 3),
            Position = UDim2.fromOffset(CIRCLE / 2 + math.cos(a) * r, CIRCLE / 2 + math.sin(a) * r),
            BackgroundColor3 = T.muted, BackgroundTransparency = 0.35 })
        UITheme.corner(d, 2)
        d.Parent = dashes
    end

    -- the check mark: two thin rotated bars (no font glyph needed)
    local check = frame({ Name = "Check", Size = UDim2.fromScale(1, 1), Visible = false })
    check.Parent = holder
    local k = CIRCLE / 14
    local short = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 4.5 * k),
        Position = UDim2.fromOffset(4.75 * k, 8.6 * k), Rotation = -45, BackgroundColor3 = T.bg,
        BackgroundTransparency = 0 })
    UITheme.corner(short, 1)
    short.Parent = check
    local long = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 8 * k),
        Position = UDim2.fromOffset(8.3 * k, 7.2 * k), Rotation = 39, BackgroundColor3 = T.bg,
        BackgroundTransparency = 0 })
    UITheme.corner(long, 1)
    long.Parent = check

    return { holder = holder, scale = scale, disc = disc, ring = ring, dashes = dashes, check = check }
end

local function paintCircle(c, done, optional)
    if done then
        c.disc.BackgroundTransparency = 0
        c.ring.Transparency = 1
        c.dashes.Visible = false
        c.check.Visible = true
    elseif optional then
        c.disc.BackgroundTransparency = 1
        c.ring.Transparency = 1
        c.dashes.Visible = true
        c.check.Visible = false
    else
        c.disc.BackgroundTransparency = 1
        c.ring.Transparency = 0.25
        c.dashes.Visible = false
        c.check.Visible = false
    end
end

local function stepText(step)
    local label = esc(step.label or step.id or "?")
    if step.done then
        return "<s>" .. label .. "</s>"
    elseif step.optional then
        return string.format('%s  <font size="12" color="%s">optional</font>', label, hex(T.faint))
    end
    return label
end

local function stepColor(step)
    if step.done then return T.muted end
    if step.optional then return T.muted end
    return T.text
end

-- ── build ──────────────────────────────────────────────────────────────
function JobHud:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("JobHud")
    if existing then existing:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "JobHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = playerGui

    local card = UITheme.panel({
        Name = "JobCard",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -16, 0, TOP),
        Size = UDim2.fromOffset(WIDTH, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        radius = 14,
    })
    card.Parent = screen
    local cardScale = Instance.new("UIScale")
    cardScale.Parent = card
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 16)
    pad.PaddingRight = UDim.new(0, 16)
    pad.PaddingTop = UDim.new(0, 12)
    pad.PaddingBottom = UDim.new(0, 14)
    pad.Parent = card
    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 8)
    list.Parent = card

    -- 1. header: THE JOB ··· [READY]
    local header = frame({ Name = "Header", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 18) })
    header.Parent = card
    UITheme.caption("The job", { Size = UDim2.new(1, -70, 1, 0), TextSize = 12 }).Parent = header
    local stage = UITheme.label({ Name = "Stage", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Text = "READY",
        FontFace = UITheme.F.bold, TextSize = 12, TextColor3 = T.muted,
        BackgroundColor3 = T.muted, BackgroundTransparency = 0.88 })
    UITheme.corner(stage, 9)
    local sp = Instance.new("UIPadding")
    sp.PaddingLeft = UDim.new(0, 8)
    sp.PaddingRight = UDim.new(0, 8)
    sp.Parent = stage
    stage.Parent = header

    -- 2. job name
    local name = UITheme.label({ Name = "JobName", LayoutOrder = 2, RichText = true, Size = UDim2.new(1, 0, 0, 24),
        FontFace = UITheme.F.display, TextSize = 20, TextTruncate = Enum.TextTruncate.AtEnd, Text = "" })
    name.Parent = card

    -- 3. steps
    -- 3. v2.0 notes: jail box / crew-in-jail line / bot crew line
    local notes = frame({ Name = "Notes", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, Visible = false })
    notes.Parent = card
    local nl = Instance.new("UIListLayout")
    nl.SortOrder = Enum.SortOrder.LayoutOrder
    nl.Padding = UDim.new(0, 4)
    nl.Parent = notes
    local jailBox = frame({ Name = "JailBox", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.danger, BackgroundTransparency = 0.8, Visible = false })
    UITheme.corner(jailBox, 10)
    UITheme.stroke(jailBox, T.danger, 0.4)
    local jp = Instance.new("UIPadding")
    jp.PaddingLeft = UDim.new(0, 10)
    jp.PaddingRight = UDim.new(0, 10)
    jp.PaddingTop = UDim.new(0, 6)
    jp.PaddingBottom = UDim.new(0, 6)
    jp.Parent = jailBox
    jailBox.Parent = notes
    local jailTitle = UITheme.label({ Name = "Title", Size = UDim2.new(1, -44, 0, 20), Text = "IN JAIL",
        FontFace = UITheme.F.display, TextSize = 16, TextColor3 = T.danger })
    jailTitle.Parent = jailBox
    local jailTimer = UITheme.label({ Name = "Timer", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(44, 20), TextXAlignment = Enum.TextXAlignment.Right, Text = "0:30",
        FontFace = UITheme.F.mono, TextSize = 15, TextColor3 = T.text })
    jailTimer.Parent = jailBox
    local jailHint = UITheme.label({ Name = "Hint", Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 16),
        AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, Text = "A teammate can break you out!",
        FontFace = UITheme.F.medium, TextSize = 13, TextColor3 = T.text })
    jailHint.Parent = jailBox
    local crewJail = UITheme.label({ Name = "CrewJail", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 16),
        AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = true, Visible = false,
        FontFace = UITheme.F.bold, TextSize = 13, TextColor3 = T.danger, Text = "" })
    crewJail.Parent = notes
    local botLine = UITheme.label({ Name = "Bots", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 16),
        AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = true, Visible = false,
        FontFace = UITheme.F.medium, TextSize = 12, TextColor3 = T.muted, Text = "" })
    botLine.Parent = notes

    -- 4. steps
    local steps = frame({ Name = "Steps", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y })
    steps.Parent = card
    local sl = Instance.new("UIListLayout")
    sl.SortOrder = Enum.SortOrder.LayoutOrder
    sl.Padding = UDim.new(0, 6)
    sl.Parent = steps

    local takeDivider = hairline(5)
    takeDivider.Parent = card

    -- 6. take + bags
    local takeRow = frame({ Name = "Take", LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 42) })
    takeRow.Parent = card
    UITheme.caption("Money", { Size = UDim2.new(0.6, 0, 0, 14), TextSize = 12 }).Parent = takeRow
    local take = UITheme.label({ Name = "Amount", Position = UDim2.fromOffset(0, 14), Size = UDim2.new(0.65, 0, 0, 28),
        FontFace = UITheme.F.display, TextSize = 24, TextColor3 = T.money, Text = "$0" })
    take.Parent = takeRow
    UITheme.caption("Bags", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0.35, 0, 0, 14), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right }).Parent = takeRow
    local bags = UITheme.label({ Name = "Bags", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 14),
        Size = UDim2.new(0.35, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Right, RichText = true,
        FontFace = UITheme.F.mono, TextSize = 18, Text = "0 / 0" })
    bags.Parent = takeRow

    -- 7. alarm chips
    local chips = frame({ Name = "Chips", LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 26), Visible = false })
    chips.Parent = card
    local cl = Instance.new("UIListLayout")
    cl.FillDirection = Enum.FillDirection.Horizontal
    cl.VerticalAlignment = Enum.VerticalAlignment.Center
    cl.SortOrder = Enum.SortOrder.LayoutOrder
    cl.Padding = UDim.new(0, 6)
    cl.Parent = chips
    local alarmChip, alarmDot, _, alarmTimer = makeChip(T.danger, "ALARM", true, 1)
    alarmChip.Parent = chips
    local silentChip, silentDot = makeChip(T.gold, "SECRET ALARM", false, 2)
    silentChip.Parent = chips

    local levelDivider = hairline(8)
    levelDivider.Parent = card

    -- 9. level + XP bar
    local levelRow = frame({ Name = "Level", LayoutOrder = 9, Size = UDim2.new(1, 0, 0, 28) })
    levelRow.Parent = card
    local lvl = UITheme.label({ Name = "Lvl", RichText = true, Size = UDim2.new(0.5, 0, 0, 18),
        FontFace = UITheme.F.display, TextSize = 16, Text = "" })
    lvl.Parent = levelRow
    local lvlScale = Instance.new("UIScale")
    lvlScale.Parent = lvl
    local xp = UITheme.label({ Name = "XP", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0.6, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right,
        FontFace = UITheme.F.medium, TextSize = 12, TextColor3 = T.muted, Text = "" })
    xp.Parent = levelRow
    local flash = UITheme.label({ Name = "LevelUp", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0.6, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right,
        FontFace = UITheme.F.display, TextSize = 14, TextColor3 = T.gold, Text = "LEVEL UP", TextTransparency = 1 })
    flash.Parent = levelRow
    local track = frame({ Name = "Track", Position = UDim2.fromOffset(0, 23), Size = UDim2.new(1, 0, 0, 4),
        BackgroundColor3 = T.line, BackgroundTransparency = 0.88 })
    UITheme.corner(track, 2)
    track.Parent = levelRow
    local fill = frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.info, BackgroundTransparency = 0 })
    UITheme.corner(fill, 2)
    fill.Parent = track
    local fg = Instance.new("UIGradient")
    fg.Color = ColorSequence.new(T.info, T.info:Lerp(T.text, 0.35))
    fg.Parent = fill

    self._screen, self._card, self._cardScale = screen, card, cardScale
    self._cardStroke = card:FindFirstChildOfClass("UIStroke")
    self._stage, self._name, self._steps = stage, name, steps
    self._takeDivider, self._takeRow, self._take, self._bags = takeDivider, takeRow, take, bags
    self._chips = chips
    self._alarmChip, self._alarmDot, self._alarmTimer = alarmChip, alarmDot, alarmTimer
    self._silentChip, self._silentDot = silentChip, silentDot
    self._lvl, self._lvlScale, self._xp, self._flash, self._fill = lvl, lvlScale, xp, flash, fill
    self._rows = {}
    self._rowOrder = {}
    self._notes, self._jailBox, self._jailTimer, self._jailHint = notes, jailBox, jailTimer, jailHint
    self._crewJail, self._botLine = crewJail, botLine

    self._takeValue = Instance.new("NumberValue")
    self._takeValue.Changed:Connect(function(v)
        take.Text = UITheme.money(v)
    end)
end

-- ── steps ──────────────────────────────────────────────────────────────
function JobHud:_buildRows(steps)
    for _, r in pairs(self._rows) do r.row:Destroy() end
    self._rows, self._rowOrder = {}, {}
    for i, step in ipairs(steps) do
        local key = tostring(step.id or i)
        local row = frame({ Name = "Step_" .. key, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 20),
            AutomaticSize = Enum.AutomaticSize.Y })
        row.Parent = self._steps
        local c = makeCircle(row)
        local label = UITheme.label({ RichText = true, Position = UDim2.fromOffset(CIRCLE + 9, 0),
            Size = UDim2.new(1, -(CIRCLE + 9), 0, 20), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
            FontFace = UITheme.F.medium, TextSize = 14 })
        label.Parent = row
        paintCircle(c, step.done, step.optional)
        label.Text = stepText(step)
        label.TextColor3 = stepColor(step)
        self._rows[key] = { row = row, circle = c, label = label, done = step.done and true or false }
        table.insert(self._rowOrder, key)
    end
end

function JobHud:_renderSteps(steps)
    steps = type(steps) == "table" and steps or {}
    local same = #steps == #self._rowOrder
    if same then
        for i, step in ipairs(steps) do
            if tostring(step.id or i) ~= self._rowOrder[i] then
                same = false
                break
            end
        end
    end
    if not same then
        self:_buildRows(steps)
        return
    end
    for i, step in ipairs(steps) do
        local r = self._rows[tostring(step.id or i)]
        local done = step.done and true or false
        r.label.Text = stepText(step)
        paintCircle(r.circle, done, step.optional)
        if done and not r.done then
            -- quick pop: the disc springs in, the label flashes green then settles to muted
            r.circle.scale.Scale = 0.35
            tween(r.circle.scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
            r.label.TextColor3 = T.money
            task.delay(0.35, function()
                if r.label.Parent then tween(r.label, 0.6, { TextColor3 = stepColor(step) }) end
            end)
        else
            r.label.TextColor3 = stepColor(step)
        end
        r.done = done
    end
end

-- ── alarm chips ────────────────────────────────────────────────────────
function JobHud:_setAlarm(on, endsAt)
    self._alarmEndsAt = tonumber(endsAt) or 0
    if on == self._alarmOn then return end
    self._alarmOn = on
    if self._alarmConn then
        self._alarmConn:Disconnect()
        self._alarmConn = nil
    end
    self._alarmChip.Visible = on
    if not on then return end
    local chipScale = self._alarmChip:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
    chipScale.Parent = self._alarmChip
    chipScale.Scale = 0.7
    tween(chipScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
    local last = -1
    self._alarmConn = RunService.Heartbeat:Connect(function()
        local left = math.max(0, (self._alarmEndsAt or 0) - workspace:GetServerTimeNow())
        local secs = math.ceil(left)
        if secs ~= last then
            last = secs
            self._alarmTimer.Text = string.format("%d:%02d", math.floor(secs / 60), secs % 60)
        end
        -- the dot blinks, faster in the last 10 seconds
        local rate = secs <= 10 and 6 or 2.5
        self._alarmDot.BackgroundTransparency = (math.floor(os.clock() * rate) % 2 == 0) and 0 or 0.7
    end)
end

function JobHud:_setSilent(on)
    if on == self._silentOn then return end
    self._silentOn = on
    if self._silentTweens then
        for _, tw in ipairs(self._silentTweens) do tw:Cancel() end
        self._silentTweens = nil
    end
    self._silentChip.Visible = on
    if not on then return end
    -- a slow amber "breathe" — no countdown, the crew doesn't know when police roll
    self._silentChip.BackgroundTransparency = 0.88
    self._silentDot.BackgroundTransparency = 0
    local info = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    local a = TweenService:Create(self._silentChip, info, { BackgroundTransparency = 0.62 })
    local b = TweenService:Create(self._silentDot, info, { BackgroundTransparency = 0.75 })
    a:Play()
    b:Play()
    self._silentTweens = { a, b }
end

-- ── job info ───────────────────────────────────────────────────────────
function JobHud:_jobName(info)
    if info and info.jobName then return tostring(info.jobName) end
    local id = (info and info.jobId) or ReplicatedStorage:GetAttribute("ActiveJob")
    if id and JOB_NAME[id] then return JOB_NAME[id] end
    return id and string.upper(tostring(id)) or nil
end

function JobHud:_render(info)
    info = info or {}
    local active = info.stage == "ACTIVE"
    local wasActive = self._active
    self._active = active

    local jobName = self:_jobName(info)
    if active then
        self._name.TextSize = 20
        self._name.FontFace = UITheme.F.display
        self._name.Text = esc(jobName or "THE JOB")
        self._stage.Text = "LIVE"
        self._stage.TextColor3 = T.gold
        self._stage.BackgroundColor3 = T.gold
    else
        self._name.TextSize = 16
        self._name.FontFace = UITheme.F.bold
        if jobName then
            self._name.Text = string.format('<font color="%s">Next heist:</font> %s',
                hex(T.muted), esc(jobName))
        else
            self._name.Text = string.format('<font color="%s">Pick a heist</font>', hex(T.muted))
        end
        self._stage.Text = "READY"
        self._stage.TextColor3 = T.muted
        self._stage.BackgroundColor3 = T.muted
    end

    self._steps.Visible = active
    self._takeDivider.Visible = active
    self._takeRow.Visible = active

    if active then
        self:_renderSteps(info.steps)
        local takeN = tonumber(info.take) or 0
        if takeN ~= self._takeTarget then
            local up = self._takeTarget ~= nil and takeN > self._takeTarget
            self._takeTarget = takeN
            if up then
                tween(self._takeValue, 0.7, { Value = takeN }, Enum.EasingStyle.Quart)
            else
                self._takeValue.Value = takeN
                self._take.Text = UITheme.money(takeN)
            end
        end
        local secured = tonumber(info.bagsSecured) or 0
        local total = tonumber(info.bagsTotal) or 0
        self._bags.Text = string.format('%d <font color="%s">/ %d</font>', secured, hex(T.muted), total)
        if self._lastSecured and secured > self._lastSecured then
            self._bags.TextColor3 = T.money
            tween(self._bags, 0.8, { TextColor3 = T.text })
        end
        self._lastSecured = secured
        self:_setAlarm(info.alarm and true or false, info.alarmEndsAt)
        self:_setSilent((info.silentAlarm and not info.alarm) and true or false)
    else
        self._takeTarget = nil
        self._lastSecured = nil
        self:_setAlarm(false, 0)
        self:_setSilent(false)
    end
    self._chips.Visible = active and (self._alarmOn or self._silentOn) or false
    self:_renderNotes(info, active)

    -- stroke goes red while the alarm is live
    if self._cardStroke and not self._levelFlashing then
        self._cardStroke.Color = self._alarmOn and T.danger or T.line
        self._cardStroke.Transparency = self._alarmOn and 0.45 or 0.88
    end

    if wasActive ~= nil and wasActive ~= active then
        self._cardScale.Scale = 0.96
        tween(self._cardScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
    end
end

-- ── v2.0 jail + crew notes ─────────────────────────────────────────────
local function nameList(list)
    local out = {}
    for _, n in ipairs(type(list) == "table" and list or {}) do table.insert(out, esc(n)) end
    return out
end

function JobHud:_renderNotes(info, active)
    info = info or {}
    local jailedMe = self._jailed == true
    -- my own jail box
    self._jailBox.Visible = jailedMe
    -- teammates in jail (not me)
    local others = {}
    for _, n in ipairs(nameList(info.jailed)) do
        if n ~= esc(localPlayer.DisplayName) then table.insert(others, n) end
    end
    if active and #others > 0 then
        local who = table.concat(others, ", ")
        self._crewJail.Text = string.format("%s %s in jail — go break them out!", who,
            #others == 1 and "is" or "are")
        self._crewJail.Visible = not jailedMe
    else
        self._crewJail.Visible = false
    end
    -- bot crewmates
    local bots = nameList(info.bots)
    if active and #bots > 0 then
        self._botLine.Text = string.format('<font color="%s">Bot crew:</font> %s  <font color="%s">(E = give bag)</font>',
            hex(T.muted), table.concat(bots, ", "), hex(T.faint))
        self._botLine.Visible = true
    else
        self._botLine.Visible = false
    end
    self._notes.Visible = self._jailBox.Visible or self._crewJail.Visible or self._botLine.Visible
end

function JobHud:_setJailed(on, freeAt)
    on = on == true
    if freeAt then self._jailFreeAt = tonumber(freeAt) or 0 end
    if on == self._jailed then
        self:_renderNotes(self._info, self._active)
        return
    end
    self._jailed = on
    if self._jailConn then
        self._jailConn:Disconnect()
        self._jailConn = nil
    end
    if on then
        local last = -1
        self._jailConn = RunService.Heartbeat:Connect(function()
            local left = math.max(0, (self._jailFreeAt or 0) - workspace:GetServerTimeNow())
            local secs = math.ceil(left)
            if secs ~= last then
                last = secs
                self._jailTimer.Text = string.format("%d:%02d", math.floor(secs / 60), secs % 60)
                self._jailHint.Text = secs > 0 and "A teammate can break you out!"
                    or "Nobody came… going back to the club."
            end
        end)
        if self._cardScale then
            self._cardScale.Scale = 1.04
            tween(self._cardScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
        end
    end
    self:_renderNotes(self._info, self._active)
end

-- ── level / XP ─────────────────────────────────────────────────────────
function JobHud:_renderLevel(animate)
    local level = math.max(1, math.floor(tonumber(localPlayer:GetAttribute("Level")) or 1))
    local xp = math.max(0, tonumber(localPlayer:GetAttribute("XP")) or 0)
    local nextXp = tonumber(localPlayer:GetAttribute("XPNext")) or ((Constants.XP and Constants.XP.LEVEL_BASE or 400) * level)
    if nextXp <= 0 then nextXp = 1 end
    local ratio = math.clamp(xp / nextXp, 0, 1)

    self._lvl.Text = string.format('<font color="%s">LVL</font> %d', hex(T.muted), level)
    self._xp.Text = string.format("%s / %s XP", commas(xp), commas(nextXp))

    local prev = self._lastLevel
    self._lastLevel = level
    if animate and prev and level > prev then
        self:_levelUp(ratio)
    elseif animate then
        tween(self._fill, 0.5, { Size = UDim2.fromScale(ratio, 1) }, Enum.EasingStyle.Quart)
    else
        self._fill.Size = UDim2.fromScale(ratio, 1)
    end
end

function JobHud:_levelUp(ratio)
    local token = {}
    self._levelToken = token
    self._levelFlashing = true
    -- bar runs to full, then refills to the new level's progress
    local full = tween(self._fill, 0.25, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    full.Completed:Connect(function()
        if self._levelToken ~= token then return end
        self._fill.Size = UDim2.fromScale(0, 1)
        tween(self._fill, 0.5, { Size = UDim2.fromScale(ratio, 1) }, Enum.EasingStyle.Quart)
    end)
    -- "LEVEL UP" replaces the XP text for a moment; the level number pops gold
    self._xp.TextTransparency = 1
    self._flash.TextTransparency = 0
    self._lvl.TextColor3 = T.gold
    self._lvlScale.Scale = 1.3
    tween(self._lvlScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
    if self._cardStroke then
        self._cardStroke.Color = T.gold
        self._cardStroke.Transparency = 0.2
    end
    self._cardScale.Scale = 1.04
    tween(self._cardScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
    task.delay(1.8, function()
        if self._levelToken ~= token then return end
        tween(self._flash, 0.4, { TextTransparency = 1 })
        tween(self._xp, 0.4, { TextTransparency = 0 })
        tween(self._lvl, 0.6, { TextColor3 = T.text })
        self._levelFlashing = false
        if self._cardStroke then
            tween(self._cardStroke, 0.8, {
                Color = self._alarmOn and T.danger or T.line,
                Transparency = self._alarmOn and 0.45 or 0.88,
            })
        end
    end)
end

function JobHud:_queueLevel()
    if self._levelQueued then return end
    self._levelQueued = true
    -- Level / XP / XPNext usually change together; render once after they all land
    task.delay(0.05, function()
        self._levelQueued = false
        self:_renderLevel(true)
    end)
end

-- ── start ──────────────────────────────────────────────────────────────
function JobHud:start()
    self:_buildUi()
    self:_render(nil)
    self:_renderLevel(false)

    for _, attr in ipairs({ "Level", "XP", "XPNext" }) do
        localPlayer:GetAttributeChangedSignal(attr):Connect(function() self:_queueLevel() end)
    end
    ReplicatedStorage:GetAttributeChangedSignal("ActiveJob"):Connect(function()
        -- only a fallback: once JobInfo is flowing it names the job itself
        if not self._info or self._info.stage ~= "ACTIVE" then self:_render(self._info) end
    end)

    -- v2.0 jail state: the remote carries freeAt, the attribute is the truth
    localPlayer:GetAttributeChangedSignal("Jailed"):Connect(function()
        self:_setJailed(localPlayer:GetAttribute("Jailed") == true, nil)
    end)
    task.spawn(function()
        local jr = Remotes.getRemote(Remotes.NAMES.Jail, "RemoteEvent")
        if not jr then return end
        jr.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            self:_setJailed(data.jailed == true, data.freeAt)
        end)
    end)
    if localPlayer:GetAttribute("Jailed") then self:_setJailed(true, nil) end

    task.spawn(function()
        local remote = Remotes.getRemote(Remotes.NAMES.JobInfo, "RemoteEvent")
        if not remote then
            warn("[HEIST CREW] JobHud: JobInfo remote missing — card stays in idle mode")
            return
        end
        remote.OnClientEvent:Connect(function(info)
            if type(info) ~= "table" then return end
            self._info = info
            self:_render(info)
        end)
    end)

    print("[HEIST CREW] JobHud mounted ✅")
end

return JobHud
