--[[
    HEIST CREW — AbilityHud
    ────────────────────────────────────────────────
    v1.0 (2026-09-25). Makes the crew roles FEEL different on your screen:

      • (v2.1) the old PERKS chip is gone — the perks are printed on the role
        card itself (CrewHud), one compact card instead of two.
      • LOOKOUT MARK (Q / gamepad L1 / touch "MARK" button) — fires UseAbility.
        A card in the bottomLeft slot, stacked right above the role card, with
        a 30s recharge ring. The server is authoritative; the ring is just the
        client's honest guess.
      • VISION — guards (tag "Guard") and cameras (tag "SecurityCamera") get a
        see-through-walls Highlight on THIS client only, when:
            your Role is Lookout  OR  your Gear includes Thermal
            OR the model's MarkedUntil is still in the future (a Lookout marked it)
      • MUSCLE TAKEDOWN — the server puts a "Takedown" ProximityPrompt on guards;
        it is hidden locally for everyone who isn't Muscle.

    PUBLIC API:
        AbilityHud:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local AbilityHud = {}
local localPlayer = Players.LocalPlayer

local MARK_ACTION = "HC_Mark"
local MARK_COOLDOWN = 30
local VISION_RATE = 0.25
local CARD_H = 60
local ABILITY_W = 190
local RING = 42
-- touch button spot inside Roblox's context-button frame (see LootHud for the throw button)
local TOUCH_POS = UDim2.new(0.5, 0, 0.02, 0)

local GUARD_COLOR = T.danger:Lerp(T.gold, 0.3)     -- red-orange
local CAMERA_COLOR = T.info                         -- cyan
local VISION_TAGS = {
    Guard = GUARD_COLOR,
    SecurityCamera = CAMERA_COLOR,
}

local ROLE = {}
for _, r in ipairs(Constants.ROLES) do ROLE[r.id] = r end

local GAMEPAD = {
    [Enum.UserInputType.Gamepad1] = true, [Enum.UserInputType.Gamepad2] = true,
    [Enum.UserInputType.Gamepad3] = true, [Enum.UserInputType.Gamepad4] = true,
}

-- ── helpers ────────────────────────────────────────────────────────────
local function tween(obj, t, props, style, dir)
    local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad,
        dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function frame(props)
    local f = Instance.new("Frame")
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    for k, v in pairs(props or {}) do f[k] = v end
    return f
end

local function round(obj)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0.5, 0)
    c.Parent = obj
    return c
end

local function hasGear(id)
    local g = localPlayer:GetAttribute("Gear")
    if type(g) ~= "string" then return false end
    for item in g:gmatch("[^,]+") do
        if item:match("^%s*(.-)%s*$") == id then return true end
    end
    return false
end

-- Restyle Roblox's grey touch button to the HUD's dark glass circle.
local function styleTouchButton(actionName, title, pos)
    pcall(function()
        ContextActionService:SetTitle(actionName, title)
        ContextActionService:SetPosition(actionName, pos)
    end)
    local btn = ContextActionService:GetButton(actionName)
    if not btn then return end
    pcall(function()
        btn.ImageTransparency = 1
        btn.BackgroundTransparency = 0.2
        btn.BackgroundColor3 = T.bg
        round(btn)
        UITheme.stroke(btn, T.line, 0.7, 1.5)
        local t = btn:FindFirstChild("ActionTitle")
        if t and t:IsA("TextLabel") then
            t.FontFace = UITheme.F.bold
            t.TextColor3 = T.text
            t.TextScaled = false
            t.TextSize = 13
        end
    end)
end

-- Radial progress ring built from frames only: two half-clips, each holding a full
-- disc whose UIGradient hides exactly half of it; rotating the gradient sweeps it.
local function makeRing(parent, size, thickness)
    local holder = frame({ Name = "Ring", Size = UDim2.fromOffset(size, size) })
    holder.Parent = parent

    local track = frame({ Name = "Track", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.line,
        BackgroundTransparency = 0.86, ZIndex = 1 })
    round(track)
    track.Parent = holder

    local halfSeq = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(0.501, 1),
        NumberSequenceKeypoint.new(1, 1),
    })
    local function half(xScale)
        local clip = frame({ Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(xScale, 0),
            ClipsDescendants = true, ZIndex = 2 })
        clip.Parent = holder
        local disc = frame({ Size = UDim2.fromOffset(size, size), Position = UDim2.fromOffset(-xScale * size, 0),
            BackgroundColor3 = T.text, BackgroundTransparency = 0 })
        round(disc)
        disc.Parent = clip
        local g = Instance.new("UIGradient")
        g.Transparency = halfSeq
        g.Parent = disc
        return clip, disc, g
    end
    local rClip, rDisc, rGrad = half(0.5)
    local lClip, lDisc, lGrad = half(0)

    local face = frame({ Name = "Face", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size - thickness * 2, size - thickness * 2), BackgroundColor3 = T.bgRaised,
        BackgroundTransparency = 0, ZIndex = 3 })
    round(face)
    face.Parent = holder
    local label = UITheme.label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.mono, TextSize = 15, Text = "Q", ZIndex = 4 })
    label.Parent = face

    local ring = { holder = holder, face = face, label = label }
    function ring.set(p)
        local a = math.clamp(p, 0, 1) * 360
        rClip.Visible = a > 0.5
        lClip.Visible = a > 180
        rGrad.Rotation = math.clamp(a, 0, 180)
        lGrad.Rotation = math.clamp(a, 180, 360)
    end
    function ring.color(c)
        rDisc.BackgroundColor3 = c
        lDisc.BackgroundColor3 = c
    end
    return ring
end

-- ── build ──────────────────────────────────────────────────────────────
function AbilityHud:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("AbilityHud")
    if existing then existing:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "AbilityHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = playerGui

    -- Lookout mark button (the whole card is tappable/clickable too) — bottomLeft slot, above the role card
    local ability = UITheme.card({ Name = "Mark", LayoutOrder = 5, Size = UDim2.fromOffset(ABILITY_W, CARD_H),
        radius = 16, Visible = false })
    ability.Parent = UITheme.slot("bottomLeft")
    local abilityScale = Instance.new("UIScale")
    abilityScale.Parent = ability
    local ring = makeRing(ability, RING, 3)
    ring.holder.Position = UDim2.fromOffset(11, (CARD_H - RING) / 2)
    local title = UITheme.label({ Position = UDim2.fromOffset(RING + 21, 9), Size = UDim2.new(1, -(RING + 29), 0, 22),
        FontFace = UITheme.F.display, TextSize = 19, Text = "MARK GUARDS" })
    title.Parent = ability
    local sub = UITheme.label({ Position = UDim2.fromOffset(RING + 21, 31), Size = UDim2.new(1, -(RING + 29), 0, 18),
        FontFace = UITheme.F.bold, TextSize = 14, Text = "READY" })
    sub.Parent = ability
    local hit = Instance.new("TextButton")
    hit.Name = "Hit"
    hit.Text = ""
    hit.AutoButtonColor = false
    hit.BackgroundTransparency = 1
    hit.Size = UDim2.fromScale(1, 1)
    hit.ZIndex = 5
    hit.Parent = ability
    hit.Activated:Connect(function() self:_useMark() end)
    hit.MouseEnter:Connect(function()
        if not self._cooling then tween(abilityScale, 0.12, { Scale = 1.03 }) end
    end)
    hit.MouseLeave:Connect(function() tween(abilityScale, 0.12, { Scale = 1 }) end)
    hit.MouseButton1Down:Connect(function() tween(abilityScale, 0.08, { Scale = 0.96 }) end)

    -- client-only highlights live under the tagged model itself, so nothing replicates
    self._screen = screen
    self._ability, self._abilityScale, self._ring, self._title, self._sub = ability, abilityScale, ring, title, sub
    self._highlights = {}
end

-- ── role → ability ─────────────────────────────────────────────────────
function AbilityHud:_renderRole()
    local roleId = localPlayer:GetAttribute("Role")
    local def = roleId and ROLE[roleId]
    local changed = roleId ~= self._role
    self._role = roleId

    -- Lookout ability
    local lookout = roleId == "Lookout"
    self:_setMarkBound(lookout)
    self._ability.Visible = lookout
    if lookout then
        local color = def and UITheme.rgb(def.color) or T.money
        self._markColor = color
        if not self._cooling then
            self._ring.color(color)
            self._ring.set(1)
            self._sub.Text = "READY"
            self._sub.TextColor3 = color
        end
        if changed then
            self._abilityScale.Scale = 0.9
            tween(self._abilityScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
        end
    end

    self:_applyTakedownAll()
end

-- ── Lookout mark ───────────────────────────────────────────────────────
function AbilityHud:_renderKeyHint(inputType)
    if GAMEPAD[inputType] then
        self._keyText = "L1"
    elseif inputType == Enum.UserInputType.Touch then
        self._keyText = ""           -- the on-screen MARK button is the hint
    else
        self._keyText = "Q"
    end
    if not self._cooling then self._ring.label.Text = self._keyText end
end

function AbilityHud:_setMarkBound(on)
    if on == self._markBound then return end
    self._markBound = on
    if on then
        ContextActionService:BindAction(MARK_ACTION, function(_, state)
            if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
            self:_useMark()
            return Enum.ContextActionResult.Sink
        end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
        styleTouchButton(MARK_ACTION, "MARK", TOUCH_POS)
    else
        ContextActionService:UnbindAction(MARK_ACTION)
    end
end

function AbilityHud:_useMark()
    if localPlayer:GetAttribute("Role") ~= "Lookout" then return end
    if self._cooling then
        -- nudge: still recharging (a quick shrink-bounce; the slot owns the position)
        tween(self._abilityScale, 0.05, { Scale = 0.94 }).Completed:Connect(function()
            tween(self._abilityScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
        end)
        return
    end
    local remote = self._abilityRemote
    if not remote then return end
    remote:FireServer()
    self:_startCooldown()
end

function AbilityHud:_startCooldown()
    self._cooling = true
    local color = self._markColor or T.money
    local started = os.clock()
    self._ring.color(T.muted)
    self._sub.TextColor3 = T.muted
    self._abilityScale.Scale = 0.94
    tween(self._abilityScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
    if self._cdConn then self._cdConn:Disconnect() end
    self._cdConn = RunService.RenderStepped:Connect(function()
        local elapsed = os.clock() - started
        local left = MARK_COOLDOWN - elapsed
        if left <= 0 then
            self._cdConn:Disconnect()
            self._cdConn = nil
            self._cooling = false
            self._ring.color(self._markColor or color)
            self._ring.set(1)
            self._ring.label.Text = self._keyText or "Q"
            self._sub.Text = "READY"
            self._sub.TextColor3 = self._markColor or color
            self._abilityScale.Scale = 1.08
            tween(self._abilityScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
            return
        end
        self._ring.set(elapsed / MARK_COOLDOWN)
        local secs = math.ceil(left)
        self._ring.label.Text = tostring(secs)
        self._sub.Text = string.format("RECHARGING %ds", secs)
    end)
end

-- ── vision highlights ──────────────────────────────────────────────────
function AbilityHud:_dropHighlight(inst)
    local h = self._highlights[inst]
    if h then
        self._highlights[inst] = nil
        if h.Parent then h:Destroy() end
    end
end

function AbilityHud:_visionTick()
    local now = workspace:GetServerTimeNow()
    local seesAll = localPlayer:GetAttribute("Role") == "Lookout" or hasGear("Thermal")
    local seen = {}
    for tag, color in pairs(VISION_TAGS) do
        for _, inst in ipairs(CollectionService:GetTagged(tag)) do
            if seen[inst] or not (inst:IsA("Model") or inst:IsA("BasePart")) or not inst:IsDescendantOf(workspace) then
                continue
            end
            seen[inst] = true
            local marked = (tonumber(inst:GetAttribute("MarkedUntil")) or 0) > now
            local show = seesAll or marked
            local h = self._highlights[inst]
            if show then
                if not h or not h.Parent then
                    h = Instance.new("Highlight")
                    h.Name = "HC_Vision"
                    h.Adornee = inst
                    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    h.FillColor = color
                    h.OutlineColor = color:Lerp(T.text, 0.25)
                    h.OutlineTransparency = 0
                    h.Parent = inst
                    self._highlights[inst] = h
                end
                -- a Lookout's mark reads a touch stronger than plain thermal/lookout sight
                h.FillTransparency = marked and 0.5 or 0.65
                h.Enabled = true
            elseif h then
                self:_dropHighlight(inst)
            end
        end
    end
    -- anything untagged / destroyed since last tick
    for inst in pairs(self._highlights) do
        if not seen[inst] then self:_dropHighlight(inst) end
    end
end

-- ── Muscle takedown prompts ────────────────────────────────────────────
-- serverWants[prompt] = the Enabled value the server last gave it
-- lastSet[prompt]     = what WE last wrote locally (so our own write isn't mistaken for the server's)
function AbilityHud:_applyTakedown(prompt)
    local want = self._serverWants[prompt]
    if want == nil then return end
    local enabled = want and localPlayer:GetAttribute("Role") == "Muscle"
    self._lastSet[prompt] = enabled
    if prompt.Enabled ~= enabled then prompt.Enabled = enabled end
end

function AbilityHud:_applyTakedownAll()
    if not self._serverWants then return end
    for prompt in pairs(self._serverWants) do self:_applyTakedown(prompt) end
end

function AbilityHud:_trackPrompt(prompt)
    if self._serverWants[prompt] ~= nil then return end
    self._serverWants[prompt] = prompt.Enabled
    prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
        if prompt.Enabled == self._lastSet[prompt] then return end   -- our own write
        self._serverWants[prompt] = prompt.Enabled                    -- the server changed it
        self:_applyTakedown(prompt)
    end)
    prompt.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            self._serverWants[prompt] = nil
            self._lastSet[prompt] = nil
        end
    end)
    self:_applyTakedown(prompt)
end

local function isTakedown(inst)
    return inst:IsA("ProximityPrompt") and inst.Name == "Takedown"
end

-- ── start ──────────────────────────────────────────────────────────────
function AbilityHud:start()
    self:_buildUi()
    self._serverWants = setmetatable({}, { __mode = "k" })
    self._lastSet = setmetatable({}, { __mode = "k" })

    self:_renderKeyHint(UserInputService:GetLastInputType())
    self:_renderRole()

    localPlayer:GetAttributeChangedSignal("Role"):Connect(function() self:_renderRole() end)
    UserInputService.LastInputTypeChanged:Connect(function(t)
        if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseWheel then return end
        self:_renderKeyHint(t)
    end)

    -- takedown prompts: existing + future
    for _, d in ipairs(workspace:GetDescendants()) do
        if isTakedown(d) then self:_trackPrompt(d) end
    end
    workspace.DescendantAdded:Connect(function(d)
        if isTakedown(d) then self:_trackPrompt(d) end
    end)

    -- vision: react instantly to tag changes, and re-check on a steady 0.25s beat
    for tag in pairs(VISION_TAGS) do
        CollectionService:GetInstanceAddedSignal(tag):Connect(function() self:_visionTick() end)
        CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst) self:_dropHighlight(inst) end)
    end
    localPlayer:GetAttributeChangedSignal("Gear"):Connect(function() self:_visionTick() end)
    task.spawn(function()
        while self._screen and self._screen.Parent do
            local ok, err = pcall(self._visionTick, self)
            if not ok then warn("[HEIST CREW] AbilityHud vision:", err) end
            task.wait(VISION_RATE)
        end
    end)

    task.spawn(function()
        self._abilityRemote = Remotes.getRemote(Remotes.NAMES.UseAbility, "RemoteEvent")
        if not self._abilityRemote then
            warn("[HEIST CREW] AbilityHud: UseAbility remote missing — MARK is disabled")
        end
    end)

    print("[HEIST CREW] AbilityHud mounted ✅")
end

return AbilityHud
