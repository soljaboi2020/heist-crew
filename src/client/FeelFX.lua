--[[
    HEIST CREW — FeelFX  (v2.0 "BIGGER", feel agent)
    ────────────────────────────────────────────────
    The client half of server/FeelService.lua — the "juice":

      cash   "+$250" pops up at the world spot (or under the cash card if
             there's no spot), counts up with little ticks, rises + fades.
      loot   "+ GOLD" pop in the loot's colour where it was grabbed.
      load   "+$1,500 LOADED" pop at the car trunk.
      big    big centre-screen banner ("VAULT OPEN!", "+$4,500") that punches
             in, holds, and fades. shake=true adds a light screen shake.
      sound  a named one-shot (3D at pos, else 2D). vault_open also shakes.

    World pops are a BillboardGui on a local-only anchor part that lives
    < 1.5 s (the allowed transient-effect exception to "no floating text").
    Every sound is played inside pcall — a bad id is silent, never an error.
    All UI uses Shared.UITheme.

    PUBLIC API:
        FeelFX:start()
        FeelFX:banner(text, color?, shake?)   -- local-only banner (for other HUDs)
        FeelFX:shake(strength?, seconds?)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local FeelFX = {}
local localPlayer = Players.LocalPlayer

local screen = nil
local bannerHolder = nil
local screenPopY = 0            -- stacks screen pops so two don't overlap
local TICK_ID = "rbxasset://sounds/clickfast.wav"

local COLORS = { gold = T.gold, money = T.money, danger = T.danger, info = T.info, text = T.text }

local function tween(obj, t, props, style, dir)
    local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad,
        dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function colorOf(c, fallback)
    if typeof(c) == "Color3" then return c end
    if type(c) == "string" and COLORS[c] then return COLORS[c] end
    if type(c) == "table" and #c == 3 then
        local ok, col = pcall(UITheme.rgb, c)
        if ok then return col end
    end
    return fallback or T.text
end

-- ── sounds ───────────────────────────────────────────────────────────
local function playSound(id, volume, pitch, pos)
    if type(id) ~= "string" or id == "" then return end
    pcall(function()
        local s = Instance.new("Sound")
        s.SoundId = id
        s.Volume = volume or 0.6
        s.PlaybackSpeed = pitch or 1
        local holder = nil
        if typeof(pos) == "Vector3" then
            holder = Instance.new("Part")
            holder.Name = "FeelSound"
            holder.Anchored = true
            holder.CanCollide = false
            holder.CanQuery = false
            holder.CanTouch = false
            holder.Transparency = 1
            holder.Size = Vector3.new(0.2, 0.2, 0.2)
            holder.CFrame = CFrame.new(pos)
            holder.Parent = workspace.CurrentCamera   -- local-only
            s.RollOffMaxDistance = 120
            s.RollOffMinDistance = 12
            s.Parent = holder
        else
            s.Parent = SoundService
        end
        s:Play()
        local target = holder or s
        s.Ended:Connect(function() if target.Parent then target:Destroy() end end)
        Debris:AddItem(target, 8)
    end)
end

-- ── shake-lite ───────────────────────────────────────────────────────
local shakeUntil, shakeStart, shakeStrength = 0, 0, 0
local shakeBound = false

function FeelFX:shake(strength, seconds)
    strength = strength or 0.35
    seconds = seconds or 0.5
    local now = os.clock()
    shakeStart = now
    shakeUntil = now + seconds
    shakeStrength = strength
    if shakeBound then return end
    shakeBound = true
    RunService:BindToRenderStep("HC_FeelShake", Enum.RenderPriority.Camera.Value + 1, function()
        local t = os.clock()
        if t >= shakeUntil then
            shakeBound = false
            RunService:UnbindFromRenderStep("HC_FeelShake")
            return
        end
        local cam = workspace.CurrentCamera
        if not cam then return end
        local k = 1 - (t - shakeStart) / math.max(shakeUntil - shakeStart, 0.01)
        local a = math.rad(shakeStrength) * k
        cam.CFrame = cam.CFrame * CFrame.Angles(
            math.noise(t * 22, 0.3) * a,
            math.noise(t * 22, 7.1) * a,
            math.noise(t * 22, 13.7) * a * 0.5)
    end)
end

-- ── pops ─────────────────────────────────────────────────────────────
local function popLabel(text, color, size)
    return UITheme.label({
        Text = text, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = size or 30, TextColor3 = color,
        TextStrokeTransparency = 0.35, TextStrokeColor3 = T.bg,
    })
end

-- count "+$0" → "+$250" over ~0.35 s with a few ticks
local function countUp(label, amount, prefix, suffix, withTicks)
    task.spawn(function()
        local steps = math.clamp(math.floor(math.abs(amount) / 50), 1, 6)
        for i = 1, steps do
            if not label.Parent then return end
            local v = math.floor(amount * i / steps)
            label.Text = prefix .. UITheme.money(math.abs(v)) .. (suffix or "")
            if withTicks and i < steps then playSound(TICK_ID, 0.25, 1.2 + i * 0.08) end
            task.wait(0.06)
        end
    end)
end

local function worldPop(pos, text, color, opts)
    opts = opts or {}
    local anchor = Instance.new("Part")
    anchor.Name = "FeelPop"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.2, 0.2, 0.2)
    anchor.CFrame = CFrame.new(pos + Vector3.new(math.random(-8, 8) / 10, 2.5, math.random(-8, 8) / 10))
    anchor.Parent = workspace.CurrentCamera

    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(220, 48)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.MaxDistance = 140
    bb.Adornee = anchor
    bb.StudsOffset = Vector3.new(0, 0, 0)
    bb.Parent = anchor
    local label = popLabel(text, color, opts.size or 30)
    label.Parent = bb
    local scale = Instance.new("UIScale")
    scale.Scale = 0.4
    scale.Parent = label

    tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
    tween(bb, 1.25, { StudsOffset = Vector3.new(0, 3.2, 0) }, Enum.EasingStyle.Quad)
    task.delay(0.7, function()
        if label.Parent then tween(label, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 }) end
    end)
    Debris:AddItem(anchor, 1.3)
    return label
end

local function screenPop(text, color)
    if not screen then return nil end
    screenPopY = (screenPopY + 1) % 3
    -- (v2.1) just LEFT of the cash card (topRight slot), so it never lands on THE JOB card
    local sc = UITheme.scale()
    local L = UITheme.L
    local holder = Instance.new("Frame")
    holder.BackgroundTransparency = 1
    holder.AnchorPoint = Vector2.new(1, 0)
    holder.Position = UDim2.new(1, -(L.MARGIN + (L.CASH_W + 14) * sc), 0, L.MARGIN + (8 + screenPopY * 30) * sc)
    holder.Size = UDim2.fromOffset(200, 36)
    holder.Parent = screen
    UITheme.autoScale(holder)
    local label = popLabel(text, color, 26)
    label.TextXAlignment = Enum.TextXAlignment.Right
    label.Parent = holder
    tween(holder, 1.2, { Position = holder.Position - UDim2.fromOffset(0, 26) })
    task.delay(0.7, function()
        if label.Parent then tween(label, 0.45, { TextTransparency = 1, TextStrokeTransparency = 1 }) end
    end)
    Debris:AddItem(holder, 1.3)
    return label
end

local function pop(pos, text, color, opts)
    if typeof(pos) == "Vector3" then
        local ok, label = pcall(worldPop, pos, text, color, opts)
        if ok then return label end
    end
    return screenPop(text, color)
end

-- ── big banner ───────────────────────────────────────────────────────
function FeelFX:banner(text, color, shake)
    if not bannerHolder then return end
    for _, c in ipairs(bannerHolder:GetChildren()) do c:Destroy() end
    local col = colorOf(color, T.gold)

    local group = Instance.new("CanvasGroup")
    group.AnchorPoint = Vector2.new(0.5, 0.5)
    group.Position = UDim2.fromScale(0.5, 0.5)
    group.Size = UDim2.fromOffset(640, 110)
    group.BackgroundTransparency = 1
    group.GroupTransparency = 0
    group.Parent = bannerHolder
    local scale = Instance.new("UIScale")
    scale.Scale = 1.5
    scale.Parent = group

    -- thin gold hairlines above and below the words
    for _, y in ipairs({ 14, 96 }) do
        local line = Instance.new("Frame")
        line.AnchorPoint = Vector2.new(0.5, 0)
        line.Position = UDim2.new(0.5, 0, 0, y)
        line.Size = UDim2.fromOffset(0, 2)
        line.BorderSizePixel = 0
        line.BackgroundColor3 = col
        line.BackgroundTransparency = 0.25
        line.Parent = group
        tween(line, 0.4, { Size = UDim2.fromOffset(360, 2) }, Enum.EasingStyle.Quint)
    end
    local label = UITheme.label({
        Text = string.upper(tostring(text or "")), Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 76),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 64,
        TextColor3 = col, TextStrokeTransparency = 0.3, TextStrokeColor3 = T.bg, TextScaled = false,
    })
    label.Parent = group

    tween(scale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
    if shake then self:shake(0.45, 0.55) end
    task.delay(1.8, function()
        if group.Parent then
            tween(group, 0.45, { GroupTransparency = 1 })
            tween(scale, 0.45, { Scale = 0.92 })
            Debris:AddItem(group, 0.5)
        end
    end)
end

-- ── remote ───────────────────────────────────────────────────────────
local function handle(payload)
    if type(payload) ~= "table" then return end
    local kind = payload.kind
    local pos = typeof(payload.pos) == "Vector3" and payload.pos or nil
    local amount = tonumber(payload.amount) or 0

    if kind == "cash" then
        local neg = amount < 0
        local label = pop(pos, (neg and "-" or "+") .. UITheme.money(0), neg and T.danger or T.money, { size = 32 })
        if label then countUp(label, amount, neg and "-" or "+", nil, true) end
        task.delay(0.36, function() playSound(payload.id, payload.volume, payload.pitch, nil) end)
    elseif kind == "loot" then
        pop(pos, "+ " .. string.upper(tostring(payload.text or "LOOT")), colorOf(payload.color, T.gold), { size = 28 })
        playSound(payload.id, payload.volume, payload.pitch, pos)
    elseif kind == "load" then
        local label = pop(pos, amount > 0 and ("+" .. UITheme.money(0) .. " LOADED") or "BAG LOADED", T.gold, { size = 28 })
        if label and amount > 0 then countUp(label, amount, "+", " LOADED", false) end
        playSound(payload.id, payload.volume, payload.pitch, pos)
    elseif kind == "big" then
        FeelFX:banner(payload.text, payload.color, payload.shake)
        if payload.id then playSound(payload.id, payload.volume, payload.pitch, nil) end
    elseif kind == "sound" then
        playSound(payload.id, payload.volume, payload.pitch, pos)
        if payload.shake then FeelFX:shake(0.4, 0.5) end
    end
end

function FeelFX:start()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("FeelFX")
    if old then old:Destroy() end
    screen = Instance.new("ScreenGui")
    screen.Name = "FeelFX"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 7
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = pg

    bannerHolder = Instance.new("Frame")
    bannerHolder.Name = "Banner"
    bannerHolder.BackgroundTransparency = 1
    bannerHolder.AnchorPoint = Vector2.new(0.5, 0.5)
    bannerHolder.Position = UDim2.fromScale(0.5, 0.3)
    bannerHolder.Size = UDim2.fromOffset(640, 110)
    bannerHolder.Parent = screen
    UITheme.autoScale(bannerHolder)   -- v2.1: scales with the screen like the rest of the HUD

    local remote = Remotes.getRemote(Remotes.NAMES.FeelFX)
    if remote then
        remote.OnClientEvent:Connect(function(payload)
            local ok, err = pcall(handle, payload)
            if not ok then warn("[FeelFX]", err) end
        end)
    else
        warn("[FeelFX] FeelFX remote missing")
    end
    print("[HEIST CREW] FeelFX mounted ✅")
end

return FeelFX
