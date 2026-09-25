--[[
    HEIST CREW — CrewHud
    ────────────────────────────────────────────────
    v0.7.0 (2026-09-25), v2.1 UI overhaul. The "what am I, what do I do" layer:

      • OBJECTIVE BAR (UITheme slot topCenter) — ONE big bar that always says
        the next thing to do:
            [icon]  STEP 2 OF 3  ▰▰▱
                    Talk to the Boss (press F) to hear the plan
        The icon matches the step (Boss hat, door, key, car…), the little
        segments show how far along you are. v2.0 lobby, in 7-year-old words:
            Step 1 of 3  Stand on a colored circle to pick a role (you can skip this)
            Step 2 of 3  Talk to the Boss (press F) to hear the plan
            Step 3 of 3  Walk into a heist door to start
            in a door    Wait here — the heist starts soon
            countdown    Heist starting in 4!
        then during a run:
            active       → the first unfinished step of the job (JobInfo), "STEALTH · 1:32"
            alarm        → Get the car to the marina   0:42   (bar turns red)
            jail         → You're in jail — wait for a friend
            after a run  → Back to The Vault — pick your next heist
        Reads local attributes HeardPlan (BriefingUI) and InPortal (PortalHud).
      • ROLE CARD (slot bottomLeft — on phones it moves top-left) — role icon
        badge in the role colour + role name + its perks + your mask's power
        (attributes MaskPowerName / MaskPowerDesc), all in one compact card
        (v2.1: the separate perks card from AbilityHud is merged in here).
      • TITLE CARD — "HEIST CREW" fades in and out once when you join
        (skipped when the IntroCam fly-over plays — it has its own).
        Lives at PlayerGui.CrewHud.TitleCard (IntroCam destroys it by name).
      • PROMPT FILTER — role-only prompts (RoleOnly / RoleHide) and, v2.0,
        prompts with HideIfJailed are hidden while YOU are Jailed.

    PUBLIC API:
        CrewHud:start()
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

local function capFirst(s)
    s = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return (s:gsub("^%l", string.upper))
end

local function perksText(def)
    local parts = {}
    for piece in (def.perks or ""):gmatch("[^·]+") do
        local s = capFirst(piece)
        if s ~= "" then table.insert(parts, s) end
    end
    return table.concat(parts, "  ·  ")
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

function CrewHud:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("CrewHud")
    if existing then existing:Destroy() end

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
        AutomaticSize = Enum.AutomaticSize.X, radius = 18 })
    local objMin = Instance.new("UISizeConstraint")
    objMin.MinSize = Vector2.new(360, L.OBJ_H)
    objMin.Parent = obj
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 22)
    pad.Parent = obj
    hlist(obj, 12)
    obj.Parent = UITheme.slot("topCenter")
    local objScale = Instance.new("UIScale")
    objScale.Parent = obj

    local badge = UITheme.badge(I.target, T.gold, 44, { LayoutOrder = 1 })
    badge.Parent = obj

    local col = frame({ LayoutOrder = 2, Size = UDim2.fromOffset(0, 48), AutomaticSize = Enum.AutomaticSize.X })
    col.Parent = obj
    local colList = Instance.new("UIListLayout")
    colList.SortOrder = Enum.SortOrder.LayoutOrder
    colList.VerticalAlignment = Enum.VerticalAlignment.Center
    colList.Padding = UDim.new(0, 1)
    colList.Parent = col

    local top = frame({ LayoutOrder = 1, Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X })
    top.Parent = col
    hlist(top, 10)
    local cap = UITheme.caption("Objective", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 16), TextSize = 13, TextColor3 = T.gold })
    cap.Parent = top
    local segs = frame({ LayoutOrder = 2, Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X })
    segs.Parent = top
    hlist(segs, 4)
    local segList = {}
    for i = 1, MAX_SEGMENTS do
        local s = frame({ LayoutOrder = i, Size = UDim2.fromOffset(18, 6), BackgroundColor3 = T.line,
            BackgroundTransparency = 0.8, Visible = false })
        UITheme.corner(s, 3)
        s.Parent = segs
        segList[i] = s
    end

    local objText = UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28),
        FontFace = UITheme.F.display, TextSize = UITheme.T.title, TextColor3 = T.text })
    objText.Parent = col

    local timer = UITheme.label({ LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40),
        FontFace = UITheme.F.mono, TextSize = 28, TextColor3 = T.danger, Visible = false,
        BackgroundColor3 = T.danger, BackgroundTransparency = 0.82 })
    UITheme.corner(timer, 10)
    UITheme.padding(timer, 10, 0)
    timer.Parent = obj

    -- ── role card (bottomLeft) ──
    local role = UITheme.card({ Name = "RoleCard", LayoutOrder = 10, Size = UDim2.fromOffset(L.ROLE_W, 0),
        AutomaticSize = Enum.AutomaticSize.Y, radius = 16 })
    UITheme.padding(role, 10, 10)
    role.Parent = UITheme.slot("bottomLeft")
    local roleScale = Instance.new("UIScale")
    roleScale.Parent = role
    local roleBadge = UITheme.badge(I.role, T.faint, 46)
    roleBadge.Position = UDim2.fromOffset(0, 0)
    roleBadge.Parent = role
    local text = frame({ Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -56, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y })
    text.Parent = role
    local tl = Instance.new("UIListLayout")
    tl.SortOrder = Enum.SortOrder.LayoutOrder
    tl.Padding = UDim.new(0, 1)
    tl.Parent = text
    local roleCap = UITheme.caption("Your role", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 14) })
    roleCap.Parent = text
    local roleName = UITheme.label({ LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 24),
        FontFace = UITheme.F.display, TextSize = 21 })
    roleName.Parent = text
    local rolePerks = UITheme.label({ LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = UITheme.F.medium,
        TextSize = UITheme.T.small, TextColor3 = T.muted })
    rolePerks.Parent = text
    -- v2.1: the active mask power (player attributes MaskPowerName / MaskPowerDesc)
    local maskLine = UITheme.label({ LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true, RichText = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = UITheme.F.bold,
        TextSize = UITheme.T.small, TextColor3 = T.gold, Visible = false })
    maskLine.Parent = text

    self._role = { card = role, badge = roleBadge, name = roleName, perks = rolePerks, scale = roleScale, mask = maskLine }
    self._obj = { frame = obj, badge = badge, cap = cap, text = objText, timer = timer, segs = segList,
        stroke = obj:FindFirstChild("Stroke"), scale = objScale }
end

function CrewHud:_renderRole()
    local r = localPlayer:GetAttribute("Role")
    local ui = self._role
    local def = r and ROLE[r]
    local changed = r ~= self._lastRole
    self._lastRole = r
    if def then
        local col = UITheme.rgb(def.color)
        UITheme.setBadge(ui.badge, I[r] or I.role, col)
        ui.name.Text = string.upper(r)
        ui.name.TextColor3 = col
        ui.perks.Text = perksText(def)
        local s = ui.card:FindFirstChild("Stroke")
        if s then
            s.Color = col
            s.Transparency = 0.45
        end
    else
        UITheme.setBadge(ui.badge, I.role, T.faint)
        ui.name.Text = "NO ROLE YET"
        ui.name.TextColor3 = T.text
        ui.perks.Text = "Stand on a colored circle — or skip it, you get one free"
        local s = ui.card:FindFirstChild("Stroke")
        if s then
            s.Color = T.edge
            s.Transparency = 0.2
        end
    end
    if changed then
        ui.scale.Scale = 0.92
        TweenService:Create(ui.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
    end
end

function CrewHud:_renderMask()
    local name = localPlayer:GetAttribute("MaskPowerName")
    local desc = localPlayer:GetAttribute("MaskPowerDesc")
    local line = self._role.mask
    if type(name) == "string" and name ~= "" then
        local function esc(x)
            return (tostring(x):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
        end
        local d = (type(desc) == "string" and desc ~= "") and ('  <font color="#%s">%s</font>'):format(T.muted:ToHex(), esc(desc)) or ""
        line.Text = "MASK: " .. esc(string.upper(name)) .. d
        line.Visible = true
    else
        line.Visible = false
    end
end

-- caption, text, icon, danger?, progress {done, total} (nil = hide segments)
function CrewHud:_setObjective(caption, text, icon, danger, progress)
    local o = self._obj
    local col = danger and T.danger or T.gold
    o.cap.Text = string.upper(caption)
    o.cap.TextColor3 = col
    UITheme.setBadge(o.badge, icon or I.target, col)
    if o.stroke then
        o.stroke.Color = danger and T.danger or T.edge
        o.stroke.Transparency = danger and 0.1 or 0.2
    end
    for i, s in ipairs(o.segs) do
        local total = progress and math.min(progress.total, MAX_SEGMENTS) or 0
        s.Visible = i <= total
        if i <= total then
            local done = i <= progress.done
            local current = i == progress.done + 1
            s.BackgroundColor3 = done and T.money or (current and col or T.line)
            s.BackgroundTransparency = done and 0 or (current and 0.1 or 0.78)
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
        self:_setObjective("Busted", "You're in jail — wait for a friend to break you out", I.jail, true)
        return
    end
    if info.alarm and (info.alarmEndsAt or 0) > 0 then
        self:_startEscape(info.alarmEndsAt)
        return
    end
    self._escapeUntil = nil
    o.timer.Visible = false
    if self._phase == "after" then
        self:_setObjective("Nice work", "Back to The Vault — pick your next heist", I.home)
        return
    end
    if info.stage == "ACTIVE" then
        -- caption shows the mode + heist clock ("STEALTH · 2:31")
        local elapsed = math.max(0, math.floor(workspace:GetServerTimeNow() - (info.startedAt or workspace:GetServerTimeNow())))
        local mode = info.silentAlarm and "Hurry — secret alarm!"
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
        if current then
            self:_setObjective(mode, current.label, STEP_ICON[current.id] or I.target, info.silentAlarm == true,
                { done = done, total = total })
        else
            self:_setObjective(mode, "Load the car and drive to the marina", I.car, false, { done = done, total = total })
        end
    elseif (info.launchAt or 0) > 0 then
        local left = math.max(0, math.ceil(info.launchAt - workspace:GetServerTimeNow()))
        self:_setObjective("Rolling out", string.format("Heist starting in %d!", left), I.wait, false, { done = 3, total = 3 })
    elseif localPlayer:GetAttribute("InPortal") then
        self:_setObjective("Step 3 of 3", "Wait here — the heist starts soon", I.wait, false, { done = 2, total = 3 })
    elseif localPlayer:GetAttribute("HeardPlan") then
        self:_setObjective("Step 3 of 3", "Walk into a heist door to start", I.door, false, { done = 2, total = 3 })
    elseif not localPlayer:GetAttribute("Role") then
        self:_setObjective("Step 1 of 3", "Stand on a colored circle to pick a role (you can skip this)", I.role, false,
            { done = 0, total = 3 })
    else
        self:_setObjective("Step 2 of 3", "Talk to the Boss (press F) to hear the plan", I.boss, false, { done = 1, total = 3 })
    end
end

function CrewHud:_startEscape(endsAt)
    if self._escapeUntil == endsAt then return end
    self._escapeUntil = endsAt
    self:_setObjective("Escape!", "Get the car to the marina", I.alarm, true)
    local o = self._obj
    o.timer.Visible = true
    task.spawn(function()
        while self._escapeUntil == endsAt do
            local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
            o.timer.Text = string.format("%d:%02d", math.floor(left / 60), left % 60)
            local blink = left <= 10 and math.floor(os.clock() * 4) % 2 == 0
            o.badge.BackgroundTransparency = blink and 0.2 or 0.72
            if left <= 0 then break end
            task.wait(0.1)
        end
        o.badge.BackgroundTransparency = 0.72
    end)
end

-- Role-only prompts (Hacker: fast breaker / hack keypad, Muscle: takedown).
-- The server re-checks the role; this only decides what each player SEES.
function CrewHud:_filterPrompt(p)
    if not p:IsA("ProximityPrompt") then return end
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
    card.Size = UDim2.fromOffset(640, 150)
    card.BackgroundTransparency = 1
    card.GroupTransparency = 1
    card.Parent = self._screen
    UITheme.autoScale(card)
    UITheme.label({ Text = "HEIST CREW", Size = UDim2.new(1, 0, 0, 96), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 92, TextStrokeTransparency = 0.5, TextStrokeColor3 = Color3.new() }).Parent = card
    UITheme.label({ Text = "PICK A ROLE  ·  HEAR THE PLAN  ·  WALK IN A HEIST DOOR", Position = UDim2.fromOffset(0, 100),
        Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
        TextSize = 18, TextColor3 = T.gold, TextStrokeTransparency = 0.5, TextStrokeColor3 = Color3.new() }).Parent = card
    task.delay(1.5, function()
        -- v2.0: the IntroCam fly-over has its own title card (and destroys this one)
        if localPlayer:GetAttribute("IntroPlaying") or localPlayer:GetAttribute("IntroCamDone") or not card.Parent then
            if card.Parent then card:Destroy() end
            return
        end
        TweenService:Create(card, TweenInfo.new(0.8), { GroupTransparency = 0 }):Play()
        task.wait(3.2)
        local out = TweenService:Create(card, TweenInfo.new(1), { GroupTransparency = 1 })
        out:Play()
        out.Completed:Wait()
        card:Destroy()
    end)
end

function CrewHud:start()
    self:_buildUi()
    self:_renderRole()
    self:_renderMask()
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
