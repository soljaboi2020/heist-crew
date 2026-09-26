--[[
    HEIST CREW — JobHud
    ────────────────────────────────────────────────
    v1.0 (2026-09-25), v2.1 UI overhaul, v3.2 "MIAMI HUD". "THE JOB" card,
    second card in the topRight slot (right under the cash card).

    v3.2: STARTS FOLDED on every screen — just the header, the Boss target
    and the money (Malachi: "too many panels on screen at once"). The big
    objective bar up top already says the next step.

        FOLDED                              OPEN (tap the header / press J)
        [🎯] THE JOB · 2 OF 5     LIVE ˅    … same, plus:
             VILLA ROSA                     (o) Find the keycard
        [🎯] Golden Flamingo  +$5,000       ( ) Open the locked door
        MONEY  $4,500         BAGS 3 / 6    ( ) Crack the vault   +2 more
        [ ALARM 0:42 ]                      Bot crew: Taco, Rex
                                            LVL 4  ▬▬▬▬───  320 / 1,600 XP

    The card glows in the heist's own colour (mart green, villa pink,
    jewelry cyan, bank gold). The Boss TARGET line used to be its own chip
    at the bottom of the screen (LootHud) — it lives here now.

    Idle (no run): a small LEVEL card — "LEVEL 4" + the XP bar. (The heist
    doors pick the job now, so there's no "next heist" name any more.)

    v2.0: works for every job in Constants.JOBS. A red JAIL box shows while
    you're in a cell ("In jail — a teammate can break you out  0:24"), your
    crew sees "Bob is in jail — go break them out!", and bot crewmates are
    listed under the steps.

    Listens to:
        JobInfo remote (spec §5, + v2 fields jailed = {names}, bots = {names})
        Jail remote { jailed, freeAt }  ·  player attribute Jailed
        player attributes Level / XP / XPNext
        ReplicatedStorage attributes ActiveJob (fallback), TargetName /
        TargetBonus / TargetSecured (TargetService)

    PUBLIC API:
        JobHud:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C
local I = UITheme.ICON
local L = UITheme.L

local JobHud = {}
local localPlayer = Players.LocalPlayer

local WIDTH = L.JOB_W
local CIRCLE = 20
local SHOW_STEPS = 3          -- only the next 3 unfinished steps are listed
local DONE_FLASH = 0.9        -- a finished step stays (green) this long before it leaves
local TOGGLE_ACTION = "HC_JobToggle"

local JOB_NAME = {}
for _, j in ipairs(Constants.JOBS or {}) do JOB_NAME[j.id] = j.name end

-- each heist glows in its own colour (same as its door in The Vault)
local JOB_COLOR = {
    mart = Color3.fromRGB(74, 222, 128), villa = Color3.fromRGB(244, 114, 182),
    jewelry = Color3.fromRGB(45, 212, 191), bank = Color3.fromRGB(252, 196, 45),
}

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
    for k, v in pairs(props or {}) do (f :: any)[k] = v end
    return f
end

local function hairline(order)
    return frame({ Name = "Divider", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = T.line, BackgroundTransparency = 0.88 })
end

-- A rounded chip with a dot + text. Returns chip, dot, label, (timer label).
local function makeChip(color, text, withTimer, order)
    local chip = frame({ Name = "Chip", LayoutOrder = order, Size = UDim2.fromOffset(0, 34),
        AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = color, BackgroundTransparency = 0.8,
        Visible = false })
    UITheme.corner(chip, 17)
    UITheme.stroke(chip, color, 0.2, 2)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 12)
    pad.Parent = chip
    local row = Instance.new("UIListLayout")
    row.FillDirection = Enum.FillDirection.Horizontal
    row.VerticalAlignment = Enum.VerticalAlignment.Center
    row.SortOrder = Enum.SortOrder.LayoutOrder
    row.Padding = UDim.new(0, 6)
    row.Parent = chip
    local dot = frame({ LayoutOrder = 1, Size = UDim2.fromOffset(10, 10), BackgroundColor3 = color,
        BackgroundTransparency = 0 })
    UITheme.corner(dot, 5)
    dot.Parent = chip
    local label = UITheme.label({ LayoutOrder = 2, Text = text, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 32), FontFace = UITheme.F.display, TextSize = 17, TextColor3 = color })
    label.Parent = chip
    local timer
    if withTimer then
        timer = UITheme.label({ LayoutOrder = 3, Text = "0:00", AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2.fromOffset(0, 32), FontFace = UITheme.F.mono, TextSize = 18, TextColor3 = T.text })
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
    local ring = UITheme.stroke(disc, T.muted, 0.25, 2)

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
        Position = UDim2.fromOffset(4.75 * k, 8.6 * k), Rotation = -45, BackgroundColor3 = T.bgDeep,
        BackgroundTransparency = 0 })
    UITheme.corner(short, 1)
    short.Parent = check
    local long = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 8 * k),
        Position = UDim2.fromOffset(8.3 * k, 7.2 * k), Rotation = 39, BackgroundColor3 = T.bgDeep,
        BackgroundTransparency = 0 })
    UITheme.corner(long, 1)
    long.Parent = check

    return { holder = holder, scale = scale, disc = disc, ring = ring, dashes = dashes, check = check }
end

local function paintCircle(c, done, optional, current)
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
        c.ring.Transparency = current and 0 or 0.3
        c.ring.Color = current and T.gold or T.muted
        c.dashes.Visible = false
        c.check.Visible = false
    end
end

local function stepText(step)
    local label = esc(step.label or step.id or "?")
    if step.done then
        return "<s>" .. label .. "</s>"
    elseif step.optional then
        return string.format('%s  <font size="15" color="%s">(bonus)</font>', label, hex(T.gold))
    end
    return label
end

-- ── build ──────────────────────────────────────────────────────────────
function JobHud:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("JobHud")
    if existing then existing:Destroy() end

    local card = UITheme.card({
        Name = "JobCard",
        LayoutOrder = 2,
        Size = UDim2.fromOffset(WIDTH, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        radius = 18,
        tint = T.purple,
    })
    card.Parent = UITheme.slot("topRight")
    local cardScale = Instance.new("UIScale")
    cardScale.Parent = card
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 14)
    pad.PaddingRight = UDim.new(0, 12)
    pad.PaddingTop = UDim.new(0, 10)
    pad.PaddingBottom = UDim.new(0, 12)
    pad.Parent = card
    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 8)
    list.Parent = card

    -- 1. header: [badge] THE JOB · x OF y ··· [LIVE] [chevron]   (the whole header toggles)
    local header = frame({ Name = "Header", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 46) })
    header.Parent = card
    local badge = UITheme.badge(I.target, T.gold, 42)
    badge.AnchorPoint = Vector2.new(0, 0.5)
    badge.Position = UDim2.new(0, 0, 0.5, 0)
    badge.Parent = header
    local cap = UITheme.caption("The job", { Position = UDim2.fromOffset(52, 1), Size = UDim2.new(1, -118, 0, 16) })
    cap.Parent = header
    local name = UITheme.label({ Name = "JobName", RichText = true, Position = UDim2.fromOffset(52, 17),
        Size = UDim2.new(1, -118, 0, 28), FontFace = UITheme.F.display, TextSize = 23,
        TextScaled = true, Text = "" })   -- (v3.1.1) shrink to fit instead of "DIAMOND…"
    do local c = Instance.new("UITextSizeConstraint") c.MaxTextSize = 23 c.MinTextSize = 13 c.Parent = name end
    name.Parent = header
    local stage = UITheme.pill("READY", T.muted, { Name = "Stage", AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -30, 0.5, 0), Size = UDim2.fromOffset(0, 24), TextSize = 14 })
    stage.Parent = header
    local chevron = UITheme.chevron(18, T.muted, 3)
    chevron.Name = "Chevron"
    chevron.AnchorPoint = Vector2.new(1, 0.5)
    chevron.Position = UDim2.new(1, -2, 0.5, 0)
    chevron.Rotation = 180
    chevron.Parent = header
    local hit = Instance.new("TextButton")
    hit.Name = "Toggle"
    hit.Text = ""
    hit.BackgroundTransparency = 1
    hit.Size = UDim2.new(1, 0, 1, 8)          -- a little taller than the header: easy to tap
    hit.Position = UDim2.fromOffset(0, -4)
    hit.ZIndex = 5
    hit.Parent = header
    hit.Activated:Connect(function() self:_toggle() end)

    -- 2. the Boss target (was LootHud's chip at the bottom of the screen)
    local target = frame({ Name = "Target", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.gold,
        BackgroundTransparency = 0.84, Visible = false })
    UITheme.corner(target, 16)
    local targetStroke = UITheme.stroke(target, T.gold, 0.35, 1.5)
    target.Parent = card
    local targetBadge = UITheme.badge(I.target, T.gold, 26)
    targetBadge.AnchorPoint = Vector2.new(0, 0.5)
    targetBadge.Position = UDim2.new(0, 3, 0.5, 0)
    targetBadge.Parent = target
    local targetName = UITheme.label({ Name = "TargetName", Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -118, 1, 0),
        FontFace = UITheme.F.display, TextSize = 17, TextColor3 = T.gold, TextScaled = true, Text = "" })
    do local c = Instance.new("UITextSizeConstraint") c.MaxTextSize = 17 c.MinTextSize = 11 c.Parent = targetName end
    targetName.Parent = target
    local targetBonus = UITheme.label({ Name = "TargetBonus", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0),
        Size = UDim2.new(0, 80, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = UITheme.F.display,
        TextSize = 17, TextColor3 = T.money, Text = "" })
    targetBonus.Parent = target

    -- 3. v2.0 notes: jail box / crew-in-jail line / bot crew line
    local notes = frame({ Name = "Notes", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, Visible = false })
    notes.Parent = card
    local nl = Instance.new("UIListLayout")
    nl.SortOrder = Enum.SortOrder.LayoutOrder
    nl.Padding = UDim.new(0, 4)
    nl.Parent = notes
    local jailBox = frame({ Name = "JailBox", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.danger, BackgroundTransparency = 0.78, Visible = false })
    UITheme.corner(jailBox, 12)
    UITheme.stroke(jailBox, T.danger, 0.2, 2)
    local jp = Instance.new("UIPadding")
    jp.PaddingLeft = UDim.new(0, 10)
    jp.PaddingRight = UDim.new(0, 10)
    jp.PaddingTop = UDim.new(0, 6)
    jp.PaddingBottom = UDim.new(0, 8)
    jp.Parent = jailBox
    jailBox.Parent = notes
    local jailTitle = UITheme.label({ Name = "Title", Size = UDim2.new(1, -56, 0, 24), Text = "IN JAIL",
        FontFace = UITheme.F.display, TextSize = 21, TextColor3 = T.danger })
    jailTitle.Parent = jailBox
    local jailTimer = UITheme.label({ Name = "Timer", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(56, 24), TextXAlignment = Enum.TextXAlignment.Right, Text = "0:30",
        FontFace = UITheme.F.mono, TextSize = 20, TextColor3 = T.text })
    jailTimer.Parent = jailBox
    local jailHint = UITheme.label({ Name = "Hint", Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 20),
        AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, Text = "A friend can get you out!",
        FontFace = UITheme.F.bold, TextSize = 17, TextColor3 = T.text })
    jailHint.Parent = jailBox
    local crewJail = UITheme.label({ Name = "CrewJail", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 20),
        AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = true, Visible = false,
        FontFace = UITheme.F.display, TextSize = 17, TextColor3 = T.danger, Text = "" })
    crewJail.Parent = notes
    local botLine = UITheme.label({ Name = "Bots", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 18),
        AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = true, Visible = false,
        FontFace = UITheme.F.bold, TextSize = 16, TextColor3 = T.muted, Text = "" })
    botLine.Parent = card

    -- 4. steps (the next 3) + "+N more"  — only when the card is open
    local steps = frame({ Name = "Steps", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y })
    steps.Parent = card
    local sl = Instance.new("UIListLayout")
    sl.SortOrder = Enum.SortOrder.LayoutOrder
    sl.Padding = UDim.new(0, 8)
    sl.Parent = steps
    local more = UITheme.label({ Name = "More", LayoutOrder = 999, Size = UDim2.new(1, 0, 0, 18),
        FontFace = UITheme.F.bold, TextSize = 15, TextColor3 = T.muted, Visible = false })
    local morePad = Instance.new("UIPadding")
    morePad.PaddingLeft = UDim.new(0, CIRCLE + 10)
    morePad.Parent = more
    more.Parent = steps

    local takeDivider = hairline(6)
    takeDivider.Parent = card

    -- 7. take + bags
    local takeRow = frame({ Name = "Take", LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 50) })
    takeRow.Parent = card
    UITheme.caption("Money", { Size = UDim2.new(0.6, 0, 0, 16) }).Parent = takeRow
    local take = UITheme.label({ Name = "Amount", Position = UDim2.fromOffset(0, 16), Size = UDim2.new(0.65, 0, 0, 34),
        FontFace = UITheme.F.display, TextSize = 30, TextColor3 = T.money, Text = "$0" })
    take.Parent = takeRow
    UITheme.caption("Bags", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0.35, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Right }).Parent = takeRow
    local bags = UITheme.label({ Name = "Bags", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 16),
        Size = UDim2.new(0.35, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Right, RichText = true,
        FontFace = UITheme.F.display, TextSize = 26, Text = "0 / 0" })
    bags.Parent = takeRow

    -- 8. alarm chips (shown even when folded — they matter)
    local chips = frame({ Name = "Chips", LayoutOrder = 8, Size = UDim2.new(1, 0, 0, 34), Visible = false })
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

    local levelDivider = hairline(9)
    levelDivider.Parent = card

    -- 10. level + XP bar
    local levelRow = frame({ Name = "Level", LayoutOrder = 10, Size = UDim2.new(1, 0, 0, 34) })
    levelRow.Parent = card
    local lvl = UITheme.label({ Name = "Lvl", RichText = true, Size = UDim2.new(0.5, 0, 0, 22),
        FontFace = UITheme.F.display, TextSize = 20, Text = "" })
    lvl.Parent = levelRow
    local lvlScale = Instance.new("UIScale")
    lvlScale.Parent = lvl
    local xp = UITheme.label({ Name = "XP", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0.6, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Right,
        FontFace = UITheme.F.bold, TextSize = 16, TextColor3 = T.muted, Text = "" })
    xp.Parent = levelRow
    local flash = UITheme.label({ Name = "LevelUp", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0.6, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Right,
        FontFace = UITheme.F.display, TextSize = 19, TextColor3 = T.gold, Text = "LEVEL UP!", TextTransparency = 1 })
    flash.Parent = levelRow
    local track = frame({ Name = "Track", Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 8),
        BackgroundColor3 = T.line, BackgroundTransparency = 0.84 })
    UITheme.corner(track, 4)
    track.Parent = levelRow
    local fill = frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0 })
    UITheme.corner(fill, 4)
    fill.Parent = track
    local fg = Instance.new("UIGradient")
    fg.Color = ColorSequence.new(T.pink, T.teal)
    fg.Parent = fill

    self._card, self._cardScale = card, cardScale
    self._cardStroke = card:FindFirstChild("Stroke")
    self._badge, self._cap, self._chevron, self._toggleBtn = badge, cap, chevron, hit
    self._stage, self._name, self._steps, self._more = stage, name, steps, more
    self._targetRow, self._targetBadge, self._targetName, self._targetBonus, self._targetStroke =
        target, targetBadge, targetName, targetBonus, targetStroke
    self._takeDivider, self._takeRow, self._take, self._bags = takeDivider, takeRow, take, bags
    self._levelDivider, self._levelRow = levelDivider, levelRow
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

-- ── collapse ───────────────────────────────────────────────────────────
function JobHud:_toggle()
    self._collapsed = not self._collapsed
    self._cardScale.Scale = 0.97
    tween(self._cardScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
    self:_render(self._info)
end

-- ── steps ──────────────────────────────────────────────────────────────
function JobHud:_buildRows(steps)
    for _, r in pairs(self._rows) do r.row:Destroy() end
    self._rows, self._rowOrder = {}, {}
    self._flashUntil = {}
    for i, step in ipairs(steps) do
        local key = tostring(step.id or i)
        local row = frame({ Name = "Step_" .. key, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 24),
            AutomaticSize = Enum.AutomaticSize.Y, Visible = false })
        row.Parent = self._steps
        local c = makeCircle(row)
        local label = UITheme.label({ RichText = true, Position = UDim2.fromOffset(CIRCLE + 10, 0),
            Size = UDim2.new(1, -(CIRCLE + 10), 0, 22), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
            FontFace = UITheme.F.medium, TextSize = UITheme.T.body })
        label.Parent = row
        self._rows[key] = { row = row, circle = c, label = label, done = step.done and true or false }
        table.insert(self._rowOrder, key)
    end
end

-- show only: the next SHOW_STEPS unfinished steps (+ any step that JUST finished, briefly)
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
    local fresh = not same
    if fresh then self:_buildRows(steps) end

    local now = os.clock()
    local shown, remaining, firstOpen = 0, 0, nil
    for i, step in ipairs(steps) do
        local key = tostring(step.id or i)
        local r = self._rows[key]
        local done = step.done and true or false
        if done and not r.done and not fresh then
            -- just finished: pop the disc, flash the label green, then drop out of the list
            self._flashUntil[key] = now + DONE_FLASH
            r.circle.scale.Scale = 0.35
            tween(r.circle.scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
            task.delay(DONE_FLASH + 0.05, function()
                if self._rows[key] == r then self:_renderSteps(self._info and self._info.steps) end
            end)
        end
        r.done = done
        local flashing = done and (self._flashUntil[key] or 0) > now
        local visible = false
        if flashing then
            visible = true
        elseif not done then
            remaining = remaining + 1
            if shown < SHOW_STEPS then
                shown = shown + 1
                visible = true
            end
        end
        local current = false
        if visible and not done and not step.optional and not firstOpen then
            firstOpen = key
            current = true
        end
        r.row.Visible = visible
        r.label.Text = stepText(step)
        paintCircle(r.circle, done, step.optional, current)
        if flashing then
            r.label.TextColor3 = T.money
            r.label.FontFace = UITheme.F.bold
        elseif current then
            r.label.TextColor3 = T.text
            r.label.FontFace = UITheme.F.bold
        else
            r.label.TextColor3 = T.muted
            r.label.FontFace = UITheme.F.medium
        end
    end
    local extra = remaining - shown
    self._more.Visible = extra > 0
    self._more.Text = string.format("+%d more", extra)

    -- header caption: progress
    local total, doneN = 0, 0
    for _, step in ipairs(steps) do
        if not step.optional then
            total = total + 1
            if step.done then doneN = doneN + 1 end
        end
    end
    self._cap.Text = total > 0 and string.format("THE JOB  ·  %d OF %d", doneN, total) or "THE JOB"
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
    self._silentChip.BackgroundTransparency = 0.85
    self._silentDot.BackgroundTransparency = 0
    local info = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    local a = TweenService:Create(self._silentChip, info, { BackgroundTransparency = 0.6 })
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
    local collapsed = self._collapsed == true

    local jobName = self:_jobName(info)
    if active then
        local jid = info.jobId or ReplicatedStorage:GetAttribute("ActiveJob")
        local jcol = JOB_COLOR[jid] or T.gold
        self._name.Text = esc(jobName or "THE JOB")
        self._name.TextColor3 = T.text
        self._stage.Text = "LIVE"
        self._stage.BackgroundColor3 = jcol
        self._stage.Visible = true
        UITheme.setBadge(self._badge, I.target, jcol)
        UITheme.tint(self._card, jcol, 0.4)
    else
        -- idle: a small LEVEL card (the heist doors pick the job now)
        self._cap.Text = "YOUR LEVEL"
        self._name.Text = string.format("LEVEL %d", self._lastLevel or 1)
        self._name.TextColor3 = T.text
        self._stage.Visible = false
        UITheme.setBadge(self._badge, I.level, T.gold)
        UITheme.tint(self._card, T.purple)
    end
    self._chevron.Visible = active
    self._toggleBtn.Visible = active
    self._chevron.Rotation = collapsed and 180 or 0

    self._steps.Visible = active and not collapsed
    self._takeDivider.Visible = active
    self._takeRow.Visible = active
    self._levelDivider.Visible = active and not collapsed
    self._levelRow.Visible = not collapsed or not active
    self._lvl.Visible = active
    self:_renderTarget(active)

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

    -- outline goes red while the alarm is live
    if self._cardStroke and not self._levelFlashing then
        self._cardStroke.Color = self._alarmOn and T.danger or UITheme.GLOW
        self._cardStroke.Transparency = self._alarmOn and 0.05 or 0.12
    end

    if wasActive ~= nil and wasActive ~= active then
        self._cardScale.Scale = 0.96
        tween(self._cardScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
    end
end

-- ── v3.2 Boss target (ReplicatedStorage TargetName / TargetBonus / TargetSecured) ──
function JobHud:_renderTarget(active)
    if active == nil then active = self._active end
    local name = ReplicatedStorage:GetAttribute("TargetName")
    local show = active == true and type(name) == "string" and name ~= ""
    self._targetRow.Visible = show
    if not show then return end
    local secured = ReplicatedStorage:GetAttribute("TargetSecured") == true
    local bonus = tonumber(ReplicatedStorage:GetAttribute("TargetBonus")) or 5000
    local col = secured and T.money or T.gold
    self._targetName.Text = secured and (name .. "  SECURED!") or name
    self._targetName.TextColor3 = col
    self._targetBonus.Text = "+" .. UITheme.money(bonus)
    self._targetRow.BackgroundColor3 = col
    self._targetStroke.Color = col
    UITheme.setBadge(self._targetBadge, secured and I.check or I.target, col)
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
        self._crewJail.Text = string.format("%s %s in jail. Go get them out!", who,
            #others == 1 and "is" or "are")
        self._crewJail.Visible = not jailedMe
    else
        self._crewJail.Visible = false
    end
    -- bot crewmates (hidden when folded)
    local bots = nameList(info.bots)
    if active and #bots > 0 and not self._collapsed then
        self._botLine.Text = string.format('<font color="%s">Bot crew:</font> %s  <font color="%s">(E = give bag)</font>',
            hex(T.teal), table.concat(bots, ", "), hex(T.muted))
        self._botLine.Visible = true
    else
        self._botLine.Visible = false
    end
    self._notes.Visible = self._jailBox.Visible or self._crewJail.Visible
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
                self._jailHint.Text = secs > 0 and "A friend can get you out!"
                    or "Nobody came. Back to the club!"
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
    if not self._active then self._name.Text = string.format("LEVEL %d", level) end
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
        self._cardStroke.Transparency = 0.1
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
                Color = self._alarmOn and T.danger or UITheme.GLOW,
                Transparency = self._alarmOn and 0.05 or 0.12,
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
    self._collapsed = true     -- v3.2: folded everywhere; the objective bar already says the next step
    self:_buildUi()
    self:_render(nil)
    self:_renderLevel(false)

    ContextActionService:BindAction(TOGGLE_ACTION, function(_, state)
        if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
        self:_toggle()
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.J)

    for _, attr in ipairs({ "Level", "XP", "XPNext" }) do
        localPlayer:GetAttributeChangedSignal(attr):Connect(function() self:_queueLevel() end)
    end
    for _, a in ipairs({ "TargetName", "TargetSecured", "TargetBonus" }) do
        ReplicatedStorage:GetAttributeChangedSignal(a):Connect(function() self:_renderTarget() end)
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
