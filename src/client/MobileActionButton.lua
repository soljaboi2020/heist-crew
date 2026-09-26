--[[
    HEIST CREW — MobileActionButton  (v2.2, ideas #10 "one context button")
    ────────────────────────────────────────────────
    Phones only (TouchEnabled and NOT KeyboardEnabled). One BIG round button
    in the thumb zone, bottom-right just above Roblox's jump button, that
    mirrors whatever ProximityPrompt Roblox is showing you right now:

      • tracks ProximityPromptService.PromptShown / PromptHidden (the prompts
        Roblox itself decided to show — so role filters, line of sight,
        Enabled = false etc. are all respected for free). Several shown →
        the nearest one wins.
      • label = the prompt's ActionText ("Bag it", "Hide", "Crawl through"…),
        icon by type: ✋ grab · 💎 smash · 💻 hack · 🙈 hide · 🕳 crawl ·
        🔧 drill · 📦 load · 🚗 get in · 💪 takedown · 🔓 break out · 👉 anything else
      • press = prompt:InputHoldBegin(), let go = prompt:InputHoldEnd(), and a
        ring fills over the prompt's HoldDuration (instant prompts just flash).
      • hides itself when no prompt is showing.

    PC / console never build it, so the default prompt UI there is untouched.
    On phones Roblox's own prompt stays tappable too — this is just bigger.

    PUBLIC API:
        MobileActionButton:start()
        (tests) MobileActionButton._forceTouch = true  (build on a PC mock)
                MobileActionButton:current() -> ProximityPrompt?
                MobileActionButton:press() / :release()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local MobileActionButton = {}
local localPlayer = Players.LocalPlayer

local SIZE_BIG = 108          -- real screen px (not UIScale'd: a thumb is a thumb)
local SIZE_SMALL = 96         -- small phones — still ≥ 96
local RING_W = 7

-- first match wins (lower-cased ActionText / prompt Name)
local ICONS = {
    { "smash", "💎" }, { "takedown", "💪" }, { "break out", "🔓" }, { "drill", "🔧" },
    { "hack", "💻" }, { "keypad", "🔢" }, { "swipe", "🔑" }, { "keycard", "🔑" }, { "cut", "✂" },
    { "get out", "🚪" }, { "hide", "🙈" }, { "crawl", "🕳" }, { "vent", "🕳" }, { "hatch", "🕳" },
    { "load", "📦" }, { "give bag", "📦" }, { "get in", "🚗" }, { "drive", "🚗" },
    { "bag", "✋" }, { "pick up", "✋" }, { "lift", "✋" }, { "grab", "✋" }, { "open", "✋" },
    { "shop", "🛒" }, { "ready", "✅" }, { "plan", "🎩" }, { "vault", "🏦" },
}

local function tween(obj, t, props, style)
    local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function iconFor(prompt)
    local s = string.lower((prompt.ActionText or "") .. " " .. prompt.Name)
    for _, pair in ipairs(ICONS) do
        if s:find(pair[1], 1, true) then return pair[2] end
    end
    return "👉"
end
MobileActionButton._iconFor = iconFor

local function promptPos(p)
    local par = p.Parent
    if not par then return nil end
    if par:IsA("Attachment") then return par.WorldPosition end
    if par:IsA("BasePart") then return par.Position end
    if par:IsA("Model") then
        local ok, cf = pcall(function() return par:GetPivot() end)
        return ok and cf.Position or nil
    end
    return nil
end

local function usable(p)
    return p and p.Parent and p.Enabled and p:IsDescendantOf(workspace)
end

-- ── build ──────────────────────────────────────────────────────────────
function MobileActionButton:_build()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("MobileActionButton")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "MobileActionButton"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 4
    screen.Parent = pg
    self._screen = screen

    local btn = Instance.new("TextButton")
    btn.Name = "ActionButton"
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.AnchorPoint = Vector2.new(0.5, 1)
    btn.BackgroundColor3 = T.bg
    btn.BackgroundTransparency = 0.08
    btn.BorderSizePixel = 0
    btn.Visible = false
    btn.Parent = screen
    UITheme.corner(btn, 999)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 155, 170))
    g.Parent = btn
    self._stroke = UITheme.stroke(btn, T.gold, 0.1, 3)
    self._pop = Instance.new("UIScale")
    self._pop.Parent = btn

    -- hold ring: a coloured disc behind the face, revealed by two rotating half-gradients
    local ring = Instance.new("Frame")
    ring.Name = "Ring"
    ring.BackgroundTransparency = 1
    ring.Size = UDim2.fromScale(1, 1)
    ring.Parent = btn
    local halfSeq = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(0.501, 1), NumberSequenceKeypoint.new(1, 1),
    })
    local halves = {}
    for i, x in ipairs({ 0.5, 0 }) do
        local clip = Instance.new("Frame")
        clip.BackgroundTransparency = 1
        clip.ClipsDescendants = true
        clip.Size = UDim2.fromScale(0.5, 1)
        clip.Position = UDim2.fromScale(x, 0)
        clip.Visible = false
        clip.Parent = ring
        local disc = Instance.new("Frame")
        disc.BorderSizePixel = 0
        disc.BackgroundColor3 = T.money
        disc.Size = UDim2.fromScale(2, 1)
        disc.Position = UDim2.fromScale(-x * 2, 0)
        disc.Parent = clip
        UITheme.corner(disc, 999)
        local grad = Instance.new("UIGradient")
        grad.Transparency = halfSeq
        grad.Parent = disc
        halves[i] = { clip = clip, grad = grad }
    end
    self._halves = halves

    local face = Instance.new("Frame")
    face.Name = "Face"
    face.AnchorPoint = Vector2.new(0.5, 0.5)
    face.Position = UDim2.fromScale(0.5, 0.5)
    face.Size = UDim2.new(1, -RING_W * 2, 1, -RING_W * 2)
    face.BackgroundColor3 = T.bgDeep
    face.BackgroundTransparency = 0.05
    face.BorderSizePixel = 0
    face.Parent = btn
    UITheme.corner(face, 999)

    self._icon = UITheme.label({ Name = "Icon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.1, 0),
        Size = UDim2.fromScale(1, 0.5), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 40, Text = "✋" })
    self._icon.Parent = face
    self._label = UITheme.label({ Name = "Action", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.6, 0),
        Size = UDim2.new(1, -10, 0.26, 0), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true,
        FontFace = UITheme.F.display, TextColor3 = T.text, Text = "" })
    local lim = Instance.new("UITextSizeConstraint")
    lim.MaxTextSize = 16
    lim.MinTextSize = 9
    lim.Parent = self._label
    self._label.Parent = face

    btn.InputBegan:Connect(function(input)
        local ut = input.UserInputType
        if ut == Enum.UserInputType.Touch or ut == Enum.UserInputType.MouseButton1 then self:press() end
    end)
    btn.InputEnded:Connect(function(input)
        local ut = input.UserInputType
        if ut == Enum.UserInputType.Touch or ut == Enum.UserInputType.MouseButton1 then self:release() end
    end)
    self._btn = btn
    self:_layout()
    local cam = workspace.CurrentCamera
    if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() self:_layout() end) end
end

-- sit just above Roblox's jump button (TouchGui: 70 px on small screens, 120 px otherwise)
function MobileActionButton:_layout()
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local small = math.min(vp.X, vp.Y) <= 500
    local jump = small and 70 or 120
    local jumpRight = small and 95 or 170                -- jump button's left edge, from the right
    local jumpTop = small and 90 or jump * 1.75          -- jump button's top, from the bottom
    local size = small and SIZE_SMALL or SIZE_BIG
    local cx = jumpRight - jump / 2                      -- centred over the jump button
    cx = math.max(cx, size / 2 + 8)                      -- never off the right edge
    self._btn.Size = UDim2.fromOffset(size, size)
    self._btn.Position = UDim2.new(1, -cx, 1, -(jumpTop + 14))
end

function MobileActionButton:_setRing(p)
    local a = math.clamp(p, 0, 1) * 360
    local r, l = self._halves[1], self._halves[2]
    r.clip.Visible = a > 0.5
    l.clip.Visible = a > 180
    r.grad.Rotation = math.clamp(a, 0, 180)
    l.grad.Rotation = math.clamp(a, 180, 360)
end

-- ── tracking ───────────────────────────────────────────────────────────
function MobileActionButton:current()
    return self._current
end

function MobileActionButton:_pickCurrent()
    local char = localPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local best, bd = nil, math.huge
    for i = #self._shown, 1, -1 do
        local p = self._shown[i]
        if not usable(p) then
            table.remove(self._shown, i)
        else
            local pos = promptPos(p)
            local d = (root and pos) and (pos - root.Position).Magnitude or (#self._shown - i)
            if d < bd then best, bd = p, d end
        end
    end
    if best ~= self._current then
        if self._holding and self._current then self:release() end
        self._current = best
        self:_show(best)
    elseif best then
        -- ActionText changes live ("Lift together (1/2)")
        local t = string.upper(best.ActionText ~= "" and best.ActionText or "Use")
        if self._label.Text ~= t then
            self._label.Text = t
            self._icon.Text = iconFor(best)
        end
    end
end

function MobileActionButton:_show(p)
    local btn = self._btn
    if not p then
        btn.Visible = false
        self:_setRing(0)
        return
    end
    self._label.Text = string.upper(p.ActionText ~= "" and p.ActionText or "Use")
    self._icon.Text = iconFor(p)
    self:_setRing(0)
    if not btn.Visible then
        btn.Visible = true
        self._pop.Scale = 0.6
        tween(self._pop, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
    end
end

-- ── press / release ────────────────────────────────────────────────────
function MobileActionButton:press()
    local p = self._current
    if not usable(p) or self._holding then return false end
    self._holding = p
    self._holdStart = os.clock()
    self._holdDur = math.max(0, tonumber(p.HoldDuration) or 0)
    self._stroke.Color = T.money
    tween(self._pop, 0.08, { Scale = 0.92 })
    local ok, err = pcall(function() p:InputHoldBegin() end)
    if not ok then warn("[MobileActionButton] InputHoldBegin:", err) end
    return ok
end

function MobileActionButton:release()
    local p = self._holding
    if not p then return false end
    self._holding = nil
    self._stroke.Color = T.gold
    tween(self._pop, 0.12, { Scale = 1 })
    self:_setRing(0)
    local ok = pcall(function() p:InputHoldEnd() end)
    return ok
end

-- ── start ──────────────────────────────────────────────────────────────
function MobileActionButton:start()
    local touch = self._forceTouch == true or UITheme.isTouch()
    if not touch then
        print("[HEIST CREW] MobileActionButton: not a touch-only device — skipped")
        return
    end
    if self._started then return end   -- (v3.2) safe to call twice; guard AFTER the touch check
    self._started = true
    self._shown = {}
    self:_build()

    ProximityPromptService.PromptShown:Connect(function(prompt)
        for _, p in ipairs(self._shown) do if p == prompt then return end end
        table.insert(self._shown, prompt)
        self:_pickCurrent()
    end)
    ProximityPromptService.PromptHidden:Connect(function(prompt)
        for i, p in ipairs(self._shown) do
            if p == prompt then table.remove(self._shown, i) break end
        end
        self:_pickCurrent()
    end)
    ProximityPromptService.PromptTriggered:Connect(function(prompt)
        if prompt == self._current then
            self._stroke.Color = T.money
            self:_setRing(1)
            task.delay(0.2, function()
                if not self._holding then
                    self:_setRing(0)
                    self._stroke.Color = T.gold
                end
            end)
        end
    end)

    local acc = 0
    RunService.Heartbeat:Connect(function(dt)
        acc += dt
        if acc >= 0.1 then
            acc = 0
            if #self._shown > 0 or self._current then self:_pickCurrent() end
        end
        if self._holding and self._holdDur > 0 then
            self:_setRing((os.clock() - self._holdStart) / self._holdDur)
        end
    end)
    print("[HEIST CREW] MobileActionButton mounted ✅")
end

return MobileActionButton
