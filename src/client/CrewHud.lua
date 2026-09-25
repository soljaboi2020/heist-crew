--[[
    HEIST CREW — CrewHud
    ────────────────────────────────────────────────
    v0.7.0 (2026-09-25). The "what am I, what do I do" layer:

      • ROLE CARD (top-left, under Roblox's buttons) — your crew role with its
        colour, or a nudge to go pick one. Reads the "Role" player attribute.
      • OBJECTIVE PILL (top-centre) — always tells you the next step:
            no role          → Step on a crew pad to pick your role
            idle             → Cross the street and crack the mansion vault
            cracking         → Hold E on the vault — stay out of the flashlights
            escaping         → Get to the getaway car   0:42   (turns red)
            after a run      → Head back to the safehouse
      • TITLE CARD — "HEIST CREW" fades in and out once when you join.

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

local CrewHud = {}
local localPlayer = Players.LocalPlayer

local ROLE_COLOR = {}
local ROLE_BLURB = {}
for _, r in ipairs(Constants.ROLES) do
    ROLE_COLOR[r.id] = UITheme.rgb(r.color)
    ROLE_BLURB[r.id] = r.blurb
end

function CrewHud:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("CrewHud")
    if existing then existing:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "CrewHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = playerGui

    -- ── role card ──
    local role = UITheme.panel({ Name = "RoleCard", Position = UDim2.fromOffset(16, 72), Size = UDim2.fromOffset(230, 62), radius = 14 })
    role.Parent = screen
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 4, 1, -20)
    bar.Position = UDim2.fromOffset(12, 10)
    bar.BorderSizePixel = 0
    bar.Parent = role
    UITheme.corner(bar, 2)
    UITheme.caption("Your role", { Position = UDim2.fromOffset(26, 9), Size = UDim2.new(1, -40, 0, 14) }).Parent = role
    local roleName = UITheme.label({ Position = UDim2.fromOffset(26, 22), Size = UDim2.new(1, -40, 0, 22),
        FontFace = UITheme.F.display, TextSize = 21 })
    roleName.Parent = role
    local roleBlurb = UITheme.label({ Position = UDim2.fromOffset(26, 42), Size = UDim2.new(1, -40, 0, 14),
        FontFace = UITheme.F.medium, TextSize = 12, TextColor3 = T.muted })
    roleBlurb.Parent = role

    -- ── objective pill ──
    local obj = UITheme.panel({ Name = "Objective", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
        Size = UDim2.fromOffset(0, 44), AutomaticSize = Enum.AutomaticSize.X, radius = 22 })
    obj.Parent = screen
    local objPad = Instance.new("UIPadding")
    objPad.PaddingLeft = UDim.new(0, 18)
    objPad.PaddingRight = UDim.new(0, 20)
    objPad.Parent = obj
    local row = Instance.new("UIListLayout")
    row.FillDirection = Enum.FillDirection.Horizontal
    row.VerticalAlignment = Enum.VerticalAlignment.Center
    row.SortOrder = Enum.SortOrder.LayoutOrder
    row.Padding = UDim.new(0, 10)
    row.Parent = obj
    local dot = Instance.new("Frame")
    dot.LayoutOrder = 1
    dot.Size = UDim2.fromOffset(8, 8)
    dot.BackgroundColor3 = T.gold
    dot.BorderSizePixel = 0
    dot.Parent = obj
    UITheme.corner(dot, 4)
    local cap = UITheme.caption("Objective", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 44), TextColor3 = T.gold })
    cap.Parent = obj
    local objText = UITheme.label({ LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 44),
        FontFace = UITheme.F.bold, TextSize = 17 })
    objText.Parent = obj
    local timer = UITheme.label({ LayoutOrder = 4, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 44),
        FontFace = UITheme.F.mono, TextSize = 18, TextColor3 = T.danger, Visible = false })
    timer.Parent = obj
    local objStroke = obj:FindFirstChildOfClass("UIStroke")

    self._role = { bar = bar, name = roleName, blurb = roleBlurb }
    self._obj = { frame = obj, dot = dot, cap = cap, text = objText, timer = timer, stroke = objStroke }
    self._screen = screen
end

function CrewHud:_renderRole()
    local r = localPlayer:GetAttribute("Role")
    local ui = self._role
    if r and ROLE_COLOR[r] then
        ui.bar.BackgroundColor3 = ROLE_COLOR[r]
        ui.name.Text = string.upper(r)
        ui.name.TextColor3 = ROLE_COLOR[r]
        ui.blurb.Text = ROLE_BLURB[r]
    else
        ui.bar.BackgroundColor3 = T.faint
        ui.name.Text = "No role yet"
        ui.name.TextColor3 = T.text
        ui.blurb.Text = "Crew pads are on the west wall"
    end
end

function CrewHud:_setObjective(caption, text, danger)
    local o = self._obj
    local col = danger and T.danger or T.gold
    o.cap.Text = string.upper(caption)
    o.cap.TextColor3 = col
    o.dot.BackgroundColor3 = col
    o.stroke.Color = danger and T.danger or T.line
    o.stroke.Transparency = danger and 0.4 or 0.88
    if o.text.Text ~= text then
        o.text.Text = text
        o.text.TextTransparency = 1
        TweenService:Create(o.text, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
    end
end

function CrewHud:_refresh()
    if self._escapeUntil then return end   -- the countdown owns the pill while escaping
    self._obj.timer.Visible = false
    if self._phase == "cracking" then
        self:_setObjective("Objective", "Hold E on the vault — stay out of the flashlights")
    elseif self._phase == "after" then
        self:_setObjective("Objective", "Head back to the safehouse")
    elseif not localPlayer:GetAttribute("Role") then
        self:_setObjective("Objective", "Step on a crew pad to pick your role")
    else
        self:_setObjective("Objective", "Cross the street and crack the mansion vault")
    end
end

function CrewHud:_startEscape(seconds)
    local untilT = os.clock() + (seconds or Constants.GETAWAY_TIMER)
    self._escapeUntil = untilT
    self:_setObjective("Escape", "Get to the getaway car", true)
    local o = self._obj
    o.timer.Visible = true
    task.spawn(function()
        while self._escapeUntil == untilT do
            local left = math.max(0, math.ceil(untilT - os.clock()))
            o.timer.Text = string.format("%d:%02d", math.floor(left / 60), left % 60)
            -- the dot blinks in the last 10 seconds
            o.dot.BackgroundTransparency = (left <= 10 and math.floor(os.clock() * 4) % 2 == 0) and 0.8 or 0
            if left <= 0 then break end
            task.wait(0.1)
        end
        o.dot.BackgroundTransparency = 0
    end)
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
    UITheme.label({ Text = "HEIST CREW", Size = UDim2.new(1, 0, 0, 96), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 92, TextStrokeTransparency = 0.7, TextStrokeColor3 = Color3.new() }).Parent = card
    UITheme.label({ Text = "PICK A ROLE  ·  PLAN THE JOB  ·  GET PAID", Position = UDim2.fromOffset(0, 100),
        Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
        TextSize = 18, TextColor3 = T.gold, TextStrokeTransparency = 0.7, TextStrokeColor3 = Color3.new() }).Parent = card
    task.delay(1, function()
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
    self._phase = "idle"
    self:_refresh()
    self:_titleCard()

    localPlayer:GetAttributeChangedSignal("Role"):Connect(function()
        self:_renderRole()
        self:_refresh()
    end)

    Remotes.getRemote(Remotes.NAMES.VaultProgress, "RemoteEvent").OnClientEvent:Connect(function(p)
        if self._escapeUntil then return end
        local was = self._phase
        self._phase = (p > 0 and p < 1) and "cracking" or (self._phase == "cracking" and "idle" or self._phase)
        if was ~= self._phase then self:_refresh() end
    end)

    Remotes.getRemote(Remotes.NAMES.HeistState, "RemoteEvent").OnClientEvent:Connect(function(state, payload)
        payload = payload or {}
        if state == "ESCAPING" then
            self._phase = "escaping"
            self:_startEscape(payload.escapeSeconds)
        elseif state == "COMPLETE" or state == "FAILED" then
            self._escapeUntil = nil
            self._phase = "after"
            self:_refresh()
        elseif state == "IDLE" then
            self._escapeUntil = nil
            self._phase = "idle"
            self:_refresh()
        end
    end)

    print("[HEIST CREW] CrewHud mounted ✅")
end

return CrewHud
