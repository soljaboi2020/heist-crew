--[[
    HEIST CREW — CrewHud
    ────────────────────────────────────────────────
    v0.7.0 (2026-09-25), v2.1 UI overhaul, v3.2 "MIAMI HUD". The "what am I,
    what do I do" layer:

      • OBJECTIVE BAR (UITheme slot topCenter) — ONE big bar that always says
        the next thing to do, in as few words as a 7-year-old needs:
            [icon]  STEP 2 OF 3  ▰▰▱
                    Talk to the Boss (F)
        The icon matches the step (Boss hat, door, key, car…), the little
        segments show how far along you are. Lobby:
            Step 1 of 3  Stand on a circle to pick a role
            Step 2 of 3  Talk to the Boss (F)
            Step 3 of 3  Walk into a heist door
            in a door    Wait here. Starting soon!
            countdown    Heist starting in 4!
        then during a run:
            active       → the first unfinished step of the job (JobInfo), "STEALTH · 1:32"
            alarm        → Load the car and hit GO!   0:42   (bar turns red)
            jail         → In jail! Wait for a friend
            after a run  → Back to The Vault. Pick a heist!
        Reads local attributes HeardPlan (BriefingUI) and InPortal (PortalHud).
        (The Boss TARGET lives on THE JOB card header now — JobHud.)

      • ROLE CARD (slot bottomLeft — on phones it moves top-left). v3.2:
        COMPACT by default — a big role badge in the role colour, the ROLE NAME
        and a tiny mask-power chip:
            [💻]  HACKER   [FOX SPEED]  ˅
        Tap it (or hover with the mouse) and it opens to show the perks, one
        per line, plus what your mask does. It also opens by itself for 5 s
        when your role changes, so you learn what you got.

      • TITLE CARD — "HEIST CREW" fades in and out once when you join
        (skipped when the IntroCam fly-over plays — it has its own).
        Lives at PlayerGui.CrewHud.TitleCard (IntroCam destroys it by name).
      • PROMPT FILTER — role-only prompts (RoleOnly / RoleHide) and, v2.0,
        prompts with HideIfJailed are hidden while YOU are Jailed.

    PUBLIC API:
        CrewHud:start()
        CrewHud:setRoleOpen(bool)      -- open / close the role details
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C
local I = UITheme.ICON
local L = UITheme.L

local CrewHud = {}
local localPlayer = Players.LocalPlayer

local ROLE = {}
for _, r in ipairs(Constants.ROLES) do ROLE[r.id] = r end

-- step id (JobInfo.steps) → icon
local STEP_ICON = {
    cameras = I.breaker, cases = I.smash, open = I.loot, keycard = I.key, door = I.door,
    vault = I.drill, loot = I.loot, car = I.car,
}

local MAX_SEGMENTS = 8
local DETAIL_W = L.ROLE_W - 28        -- width of the opened role details
local AUTO_OPEN = 5                   -- seconds the details show by themselves on a new role

local function capFirst(s)
    s = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return (s:gsub("^%l", string.upper))
end

-- "a · b · c" → { "A", "B", "C" }
local function perkLines(def)
    local out = {}
    for piece in (def.perks or ""):gmatch("[^·]+") do
        local s = capFirst(piece)
        if s ~= "" then table.insert(out, s) end
    end
    return out
end

local function frame(props)
    local f = Instance.new("Frame")
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    for k, v in pairs(props or {}) do (f :: any)[k] = v end
    return f
end

local function hlist(parent, gap, vAlign)
    local l = Instance.new("UIListLayout")
    l.FillDirection = Enum.FillDirection.Horizontal
    l.VerticalAlignment = vAlign or Enum.VerticalAlignment.Center
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, gap or 8)
    l.Parent = parent
    return l
end

local function vlist(parent, gap)
    local l = Instance.new("UIListLayout")
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, gap or 4)
    l.Parent = parent
    return l
end

function CrewHud:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("CrewHud")
    if existing then existing:Destroy() end
    local touch = UITheme.isTouch()

    -- own ScreenGui only for the join title card (IntroCam looks for CrewHud.TitleCard)
    local screen = Instance.new("ScreenGui")
    screen.Name = "CrewHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 8
    screen.Parent = playerGui
    self._screen = screen

    -- ── objective bar (topCenter) ──
    local obj = UITheme.card({ Name = "Objective", LayoutOrder = 1, Size = UDim2.fromOffset(0, L.OBJ_H),
        AutomaticSize = Enum.AutomaticSize.X, radius = 20, tint = T.hot })
    local objSize = Instance.new("UISizeConstraint")
    objSize.MinSize = Vector2.new(340, L.OBJ_H)
    objSize.MaxSize = Vector2.new(L.OBJ_MAX_W, L.OBJ_H)
    objSize.Parent = obj
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 9)
    pad.PaddingRight = UDim.new(0, 22)
    pad.Parent = obj
    hlist(obj, 12)
    obj.Parent = UITheme.slot("topCenter")
    local objScale = Instance.new("UIScale")
    objScale.Parent = obj

    local badge = UITheme.badge(I.target, T.gold, 46, { LayoutOrder = 1 })
    badge.Parent = obj

    local col = frame({ LayoutOrder = 2, Size = UDim2.fromOffset(0, 52), AutomaticSize = Enum.AutomaticSize.X })
    col.Parent = obj
    local colList = vlist(col, 1)
    colList.VerticalAlignment = Enum.VerticalAlignment.Center

    local top = frame({ LayoutOrder = 1, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X })
    top.Parent = col
    hlist(top, 10)
    local cap = UITheme.caption("Objective", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 18), TextSize = UITheme.T.caption, TextColor3 = T.gold })
    cap.Parent = top
    local segs = frame({ LayoutOrder = 2, Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X })
    segs.Parent = top
    hlist(segs, 4)
    local segList = {}
    for i = 1, MAX_SEGMENTS do
        local s = frame({ LayoutOrder = i, Size = UDim2.fromOffset(20, 7), BackgroundColor3 = T.line,
            BackgroundTransparency = 0.8, Visible = false })
        UITheme.corner(s, 4)
        s.Parent = segs
        segList[i] = s
    end

    local objText = UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30),
        FontFace = UITheme.F.display, TextSize = touch and 22 or UITheme.T.title, TextColor3 = T.text })
    objText.Parent = col

    local timer = UITheme.label({ LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 42),
        FontFace = UITheme.F.mono, TextSize = 30, TextColor3 = T.danger, Visible = false,
        BackgroundColor3 = T.danger, BackgroundTransparency = 0.8 })
    UITheme.corner(timer, 12)
    UITheme.padding(timer, 10, 0)
    timer.Parent = obj

    -- ── role card (bottomLeft) — compact, opens on tap / hover ──
    local role = UITheme.card({ Name = "RoleCard", LayoutOrder = 10, Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY, radius = 18, tint = T.purple })
    UITheme.padding(role, 8, 8)
    vlist(role, 8)
    role.Parent = UITheme.slot("bottomLeft")
    local roleScale = Instance.new("UIScale")
    roleScale.Parent = role

    -- the always-visible row is a button (tap = open / close the details)
    local head = Instance.new("TextButton")
    head.Name = "Toggle"
    head.LayoutOrder = 1
    head.Text = ""
    head.AutoButtonColor = false
    head.BackgroundTransparency = 1
    head.BorderSizePixel = 0
    head.Size = UDim2.fromOffset(0, 54)
    head.AutomaticSize = Enum.AutomaticSize.X
    head.Parent = role
    local headPad = Instance.new("UIPadding")
    headPad.PaddingRight = UDim.new(0, 6)
    headPad.Parent = head
    hlist(head, 10)

    local roleBadge = UITheme.badge(I.role, T.faint, 54, { LayoutOrder = 1 })
    roleBadge.Parent = head
    local nameCol = frame({ LayoutOrder = 2, Size = UDim2.fromOffset(0, 54), AutomaticSize = Enum.AutomaticSize.X })
    nameCol.Parent = head
    local ncl = vlist(nameCol, 2)
    ncl.VerticalAlignment = Enum.VerticalAlignment.Center
    local roleName = UITheme.label({ LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28),
        FontFace = UITheme.F.display, TextSize = 26 })
    roleName.Parent = nameCol
    -- tiny mask-power chip (player attributes MaskPowerName / MaskPowerDesc)
    local maskChip = UITheme.pill("", T.gold, { LayoutOrder = 2, Size = UDim2.fromOffset(0, 22), TextSize = 13,
        Visible = false })
    maskChip.Parent = nameCol
    local chevron = UITheme.chevron(16, T.muted, 3)
    chevron.LayoutOrder = 3
    chevron.Rotation = 180
    chevron.Parent = head

    -- details (hidden until tapped / hovered)
    local details = frame({ Name = "Details", LayoutOrder = 2, Size = UDim2.fromOffset(DETAIL_W, 0),
        AutomaticSize = Enum.AutomaticSize.Y, Visible = false })
    details.Parent = role
    vlist(details, 6)
    local detailPad = Instance.new("UIPadding")
    detailPad.PaddingLeft = UDim.new(0, 4)
    detailPad.PaddingBottom = UDim.new(0, 2)
    detailPad.Parent = details

    -- hover (mouse) opens it while the pointer is on it; a tap pins it open
    head.Activated:Connect(function()
        self._rolePinned = not self._roleOpen
        self:setRoleOpen(not self._roleOpen, self._rolePinned and 8 or nil)
    end)
    role.MouseEnter:Connect(function()
        if not UITheme.isTouch() then
            self._hover = true
            self:setRoleOpen(true)
        end
    end)
    role.MouseLeave:Connect(function()
        self._hover = false
        if not self._rolePinned and not self._autoOpen then self:setRoleOpen(false) end
    end)

    self._role = { card = role, badge = roleBadge, name = roleName, mask = maskChip, scale = roleScale,
        details = details, chevron = chevron, head = head }
    self._obj = { frame = obj, badge = badge, cap = cap, text = objText, timer = timer, segs = segList,
        stroke = obj:FindFirstChild("Stroke"), scale = objScale }
end

-- one line in the role details: a coloured dot + wrapped text
function CrewHud:_detailLine(order, text, color, rich)
    local row = frame({ LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
    local dot = frame({ Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(0, 7), BackgroundColor3 = color,
        BackgroundTransparency = 0 })
    UITheme.corner(dot, 4)
    dot.Parent = row
    local l = UITheme.label({ Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -16, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, RichText = rich == true,
        TextYAlignment = Enum.TextYAlignment.Top, FontFace = UITheme.F.bold, TextSize = 17,
        TextColor3 = T.text, Text = text })
    l.Parent = row
    row.Parent = self._role.details
    return row
end

-- open / close the role details. `secs` = close again by itself after this long.
function CrewHud:setRoleOpen(open, secs)
    local ui = self._role
    if not ui then return end
    open = open == true
    self._roleOpen = open
    if not open then self._rolePinned = false end
    local rows = 0
    for _, c in ipairs(ui.details:GetChildren()) do
        if c:IsA("Frame") then rows = rows + 1 end
    end
    ui.details.Visible = open and rows > 0
    ui.chevron.Rotation = open and 0 or 180
    local token = {}
    self._roleToken = token
    if open and secs then
        task.delay(secs, function()
            if self._roleToken == token and not self._hover then
                self._autoOpen = false
                self:setRoleOpen(false)
            end
        end)
    end
end

function CrewHud:_renderDetails()
    local ui = self._role
    for _, c in ipairs(ui.details:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    local r = localPlayer:GetAttribute("Role")
    local def = r and ROLE[r]
    local col = def and UITheme.rgb(def.color) or T.muted
    local n = 0
    if def then
        for _, line in ipairs(perkLines(def)) do
            n = n + 1
            self:_detailLine(n, line, col)
        end
    else
        n = n + 1
        self:_detailLine(n, "Stand on a colored circle to pick one", T.muted)
        n = n + 1
        self:_detailLine(n, "Or skip it. You get one free!", T.muted)
    end
    local mName = localPlayer:GetAttribute("MaskPowerName")
    local mDesc = localPlayer:GetAttribute("MaskPowerDesc")
    if type(mName) == "string" and mName ~= "" then
        local function esc(x)
            return (tostring(x):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
        end
        local d = (type(mDesc) == "string" and mDesc ~= "") and (": " .. esc(mDesc)) or ""
        n = n + 1
        self:_detailLine(n, ('<font color="#%s">MASK %s</font>%s'):format(T.gold:ToHex(), esc(string.upper(mName)), d),
            T.gold, true)
    end
    if self._roleOpen then ui.details.Visible = n > 0 end
end

function CrewHud:_renderRole()
    local r = localPlayer:GetAttribute("Role")
    local ui = self._role
    local def = r and ROLE[r]
    local changed = r ~= self._lastRole
    self._lastRole = r
    local s = ui.card:FindFirstChild("Stroke")
    if def then
        local col = UITheme.rgb(def.color)
        UITheme.setBadge(ui.badge, I[r] or I.role, col)
        ui.name.Text = string.upper(r)
        ui.name.TextColor3 = col
        UITheme.tint(ui.card, col, 0.42)
        if s then
            s.Color = col
            s.Transparency = 0.15
        end
    else
        UITheme.setBadge(ui.badge, I.role, T.faint)
        ui.name.Text = "NO ROLE YET"
        ui.name.TextColor3 = T.text
        UITheme.tint(ui.card, T.purple)
        if s then
            s.Color = UITheme.GLOW
            s.Transparency = 0.3
        end
    end
    self:_renderDetails()
    if changed then
        ui.scale.Scale = 0.92
        TweenService:Create(ui.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
        -- a new role: show what it does for a few seconds
        if def and self._started then
            self._autoOpen = true
            self:setRoleOpen(true, AUTO_OPEN)
        end
    end
end

function CrewHud:_renderMask()
    local name = localPlayer:GetAttribute("MaskPowerName")
    local chip = self._role.mask
    if type(name) == "string" and name ~= "" then
        chip.Text = string.upper(name)
        chip.Visible = true
    else
        chip.Visible = false
    end
    self:_renderDetails()
end

-- caption, text, icon, danger?, progress {done, total} (nil = hide segments)
function CrewHud:_setObjective(caption, text, icon, danger, progress)
    local o = self._obj
    local col = danger and T.danger or T.gold
    o.cap.Text = string.upper(caption)
    o.cap.TextColor3 = col
    UITheme.setBadge(o.badge, icon or I.target, col)
    if o.stroke then
        o.stroke.Color = danger and T.danger or UITheme.GLOW
        o.stroke.Transparency = danger and 0.05 or 0.12
    end
    if danger ~= self._objDanger then
        self._objDanger = danger
        UITheme.tint(o.frame, danger and T.danger or T.hot)
    end
    for i, s in ipairs(o.segs) do
        local total = progress and math.min(progress.total, MAX_SEGMENTS) or 0
        s.Visible = i <= total
        if i <= total then
            local done = i <= progress.done
            local current = i == progress.done + 1
            s.BackgroundColor3 = done and T.teal or (current and col or T.line)
            s.BackgroundTransparency = done and 0 or (current and 0.1 or 0.75)
        end
    end
    if o.text.Text ~= text then
        o.text.Text = text
        o.text.TextTransparency = 1
        TweenService:Create(o.text, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
        -- a little "new objective" pop
        o.scale.Scale = 1.06
        TweenService:Create(o.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
    end
end

-- v1.0: the bar is driven by the JobInfo remote (see V1_SPEC §5): it always
-- names the first unfinished step of the job, or the escape countdown.
function CrewHud:_refresh()
    local info = self._info or {}
    local o = self._obj
    if localPlayer:GetAttribute("Jailed") then
        -- v2.0: caught by the police — a teammate can break you out
        self._escapeUntil = nil
        o.timer.Visible = false
        self:_setObjective("Busted", "In jail! Wait for a friend", I.jail, true)
        return
    end
    if info.alarm and (info.alarmEndsAt or 0) > 0 then
        self:_startEscape(info.alarmEndsAt)
        return
    end
    self._escapeUntil = nil
    o.timer.Visible = false
    if self._phase == "after" then
        self:_setObjective("Nice work", "Back to The Vault. Pick a heist!", I.home)
        return
    end
    if info.stage == "ACTIVE" then
        -- caption shows the mode + heist clock ("STEALTH · 2:31")
        local elapsed = math.max(0, math.floor(workspace:GetServerTimeNow() - (info.startedAt or workspace:GetServerTimeNow())))
        local mode = info.silentAlarm and "Hurry! Secret alarm!"
            or string.format("Stealth · %d:%02d", math.floor(elapsed / 60), elapsed % 60)
        local total, done, current = 0, 0, nil
        for _, step in ipairs(info.steps or {}) do
            if not step.optional then
                total = total + 1
                if step.done then
                    done = done + 1
                elseif not current then
                    current = step
                end
            end
        end
        -- (v3.3) a tutorial is up: the bar says exactly what the tutorial card says
        local tl = localPlayer:GetAttribute("Tutorial") and localPlayer:GetAttribute("TutorialLine")
        if type(tl) == "string" and tl ~= "" then
            self:_setObjective(mode, tl, (current and STEP_ICON[current.id]) or I.target, info.silentAlarm == true,
                { done = done, total = total })
        elseif current then
            self:_setObjective(mode, current.label, STEP_ICON[current.id] or I.target, info.silentAlarm == true,
                { done = done, total = total })
        else
            self:_setObjective(mode, "Get in the car and hit GO!", I.car, false, { done = done, total = total })
        end
    elseif (info.launchAt or 0) > 0 then
        local left = math.max(0, math.ceil(info.launchAt - workspace:GetServerTimeNow()))
        self:_setObjective("Rolling out", string.format("Heist starting in %d!", left), I.wait, false, { done = 3, total = 3 })
    elseif localPlayer:GetAttribute("Tutorial") then
        -- v3.1: the tutorial's own step card is the guide — no competing lobby steps
        self:_setObjective("Tutorial", "Follow the gold arrow!", I.wait, false, nil)
    elseif localPlayer:GetAttribute("InPortal") then
        self:_setObjective("Step 3 of 3", "Wait here. Starting soon!", I.wait, false, { done = 2, total = 3 })
    elseif localPlayer:GetAttribute("HeardPlan") then
        self:_setObjective("Step 3 of 3", "Walk into a heist door", I.door, false, { done = 2, total = 3 })
    elseif not localPlayer:GetAttribute("Role") then
        self:_setObjective("Step 1 of 3", "Stand on a circle to pick a role", I.role, false, { done = 0, total = 3 })
    else
        self:_setObjective("Step 2 of 3", UITheme.isTouch() and "Talk to the Boss" or "Talk to the Boss (F)", I.boss, false,
            { done = 1, total = 3 })
    end
end

function CrewHud:_startEscape(endsAt)
    if self._escapeUntil == endsAt then return end
    self._escapeUntil = endsAt
    self:_setObjective("Escape!", "Load the car and hit GO!", I.alarm, true)
    local o = self._obj
    o.timer.Visible = true
    task.spawn(function()
        while self._escapeUntil == endsAt do
            local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
            o.timer.Text = string.format("%d:%02d", math.floor(left / 60), left % 60)
            local blink = left <= 10 and math.floor(os.clock() * 4) % 2 == 0
            o.badge.BackgroundTransparency = blink and 0.15 or 0.6
            if left <= 0 then break end
            task.wait(0.1)
        end
        o.badge.BackgroundTransparency = 0.6
    end)
end

-- Role-only prompts (Hacker: fast breaker / hack keypad, Muscle: takedown).
-- The server re-checks the role; this only decides what each player SEES.
function CrewHud:_filterPrompt(p)
    if not p:IsA("ProximityPrompt") then return end
    -- (v3.3) the keycard-door keypad is ONE prompt on E: its words + hold follow
    -- what YOU can do with it (the server re-checks card / role / hold on trigger)
    local hack = p:GetAttribute("KeypadHack")
    if type(hack) == "number" then
        if not localPlayer:GetAttribute("HasKeycard") and localPlayer:GetAttribute("Role") == "Hacker" then
            p.ActionText, p.HoldDuration = "Hack it (Hacker)", hack
        else
            p.ActionText, p.HoldDuration = "Swipe keycard", 0.3
        end
        p.ObjectText = "Keypad"
    end
    local only, hide = p:GetAttribute("RoleOnly"), p:GetAttribute("RoleHide")
    local jailHide = p:GetAttribute("HideIfJailed") == true
    if not only and not hide and not jailHide then return end
    local role = localPlayer:GetAttribute("Role")
    local show = true
    if only then show = (role == only) end
    if hide and role == hide then show = false end
    -- v2.0: you can't break YOURSELF out of jail — only a teammate can
    if jailHide and localPlayer:GetAttribute("Jailed") then show = false end
    p.Enabled = show
end

function CrewHud:_filterAll()
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then self:_filterPrompt(d) end
    end
end

function CrewHud:_titleCard()
    local card = Instance.new("CanvasGroup")
    card.Name = "TitleCard"
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.4)
    card.Size = UDim2.fromOffset(700, 160)
    card.BackgroundTransparency = 1
    card.GroupTransparency = 1
    card.Parent = self._screen
    UITheme.autoScale(card)
    local title = UITheme.label({ Text = "HEIST CREW", Size = UDim2.new(1, 0, 0, 100), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 96, TextStrokeTransparency = 0.4, TextStrokeColor3 = T.bgDeep })
    title.Parent = card
    -- Miami sunset across the letters
    local tg = Instance.new("UIGradient")
    tg.Rotation = 0
    tg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, T.pink),
        ColorSequenceKeypoint.new(0.5, T.gold),
        ColorSequenceKeypoint.new(1, T.teal),
    })
    tg.Parent = title
    UITheme.label({ Text = "PICK A ROLE  ·  HEAR THE PLAN  ·  WALK IN A DOOR", Position = UDim2.fromOffset(0, 106),
        Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextSize = 22, TextColor3 = T.text, TextStrokeTransparency = 0.4, TextStrokeColor3 = T.bgDeep }).Parent = card
    task.delay(1.5, function()
        -- v2.0: the IntroCam fly-over has its own title card (and destroys this one)
        if localPlayer:GetAttribute("IntroPlaying") or localPlayer:GetAttribute("IntroCamDone") or not card.Parent then
            if card.Parent then card:Destroy() end
            return
        end
        -- (v3.3) a big centre title: take FeelFX's banner lock so no banner / tip lands on it
        local fxMod = script.Parent:FindFirstChild("FeelFX")
        if fxMod then pcall(function() require(fxMod):holdBig(3.9) end) end
        TweenService:Create(card, TweenInfo.new(0.5), { GroupTransparency = 0 }):Play()
        task.wait(2.6)
        local out = TweenService:Create(card, TweenInfo.new(0.7), { GroupTransparency = 1 })
        out:Play()
        out.Completed:Wait()
        card:Destroy()
    end)
end

function CrewHud:start()
    self:_buildUi()
    self:_renderRole()
    self:_renderMask()
    self._started = true
    for _, attr in ipairs({ "MaskPowerName", "MaskPowerDesc" }) do
        localPlayer:GetAttributeChangedSignal(attr):Connect(function() self:_renderMask() end)
    end
    self._phase = "idle"
    self:_refresh()
    self:_titleCard()

    localPlayer:GetAttributeChangedSignal("Role"):Connect(function()
        self:_renderRole()
        self:_refresh()
        self:_filterAll()
    end)
    self:_filterAll()
    -- v2.0: lobby steps follow the Boss briefing / standing in a heist door / jail
    for _, attr in ipairs({ "HeardPlan", "InPortal" }) do
        localPlayer:GetAttributeChangedSignal(attr):Connect(function() self:_refresh() end)
    end
    localPlayer:GetAttributeChangedSignal("Jailed"):Connect(function()
        self:_refresh()
        self:_filterAll()
    end)
    -- (v3.3) picking up / losing the keycard switches the keypad's words
    localPlayer:GetAttributeChangedSignal("HasKeycard"):Connect(function() self:_filterAll() end)
    -- (v3.3) the tutorial card's line (TutorialHud, local attribute) drives the bar while it's up
    for _, attr in ipairs({ "TutorialLine", "Tutorial" }) do
        localPlayer:GetAttributeChangedSignal(attr):Connect(function() self:_refresh() end)
    end
    -- keep the heist clock / launch countdown ticking between JobInfo pushes
    task.spawn(function()
        while true do
            task.wait(1)
            local i = self._info or {}
            if (i.stage == "ACTIVE" and not i.alarm) or (i.launchAt or 0) > 0 then self:_refresh() end
        end
    end)
    workspace.DescendantAdded:Connect(function(d)
        if d:IsA("ProximityPrompt") then task.defer(function() self:_filterPrompt(d) end) end
    end)

    local infoRemote = Remotes.getRemote(Remotes.NAMES.JobInfo, "RemoteEvent")
    if infoRemote then
        infoRemote.OnClientEvent:Connect(function(info)
            self._info = info or {}
            if self._info.stage == "ACTIVE" then self._phase = "idle" end
            self:_refresh()
        end)
    end

    local stateRemote = Remotes.getRemote(Remotes.NAMES.HeistState, "RemoteEvent")
    if stateRemote then
        stateRemote.OnClientEvent:Connect(function(state)
            if state == "COMPLETE" or state == "FAILED" then
                self._phase = "after"
                self._escapeUntil = nil
                self:_refresh()
            elseif state == "IDLE" then
                self._phase = "idle"
                self:_refresh()
            end
        end)
    end

    print("[HEIST CREW] CrewHud mounted ✅")
end

return CrewHud
