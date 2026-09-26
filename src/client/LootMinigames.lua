--[[
    HEIST CREW — LootMinigames  (v3.0 "THE SCORE", LOOT-CORE · docs/V3_SPEC.md §2.4)
    ────────────────────────────────────────────────
    Some loot needs a quick mini-game before it goes in the bag. The SERVER
    starts one (RemoteEvent "LootMinigame", made by LootService), this module
    draws it, and tells the server when you finished. The server checks the
    time (too fast = rejected) and bags it.

      cut      ✂  trace the frame edge all the way round (mouse / finger drag;
                  gamepad: push the stick to cut along the line)
      dial     🔒  turn the dial to the GREEN dot until it CLICKS, 3 times
                  (drag round / stick angle / A-D or arrow keys)
      stuff    💰  tap / click / A / Space as fast as you can to fill the bag
      unscrew  🔩  hold each of the 4 screws (spinning your finger/mouse round
                  it makes it faster). Gamepad/keys: hold A / Space
      drill    🔧  tap to place the drill, wait… JAMMED? tap tap tap!
    Every one is ≤ ~4 s for a kid, ≤ 6 s worst case.

    ACCESSIBILITY: hold E (keyboard) / X (gamepad) / the HOLD button for 3 s
    to finish any of them. Cancel: the ✕ button, Backspace, or B.

    Messages: see the LootService header (op = start / stop / result / done / cancel).

    PUBLIC API:
        LootMinigames:start()
        LootMinigames:isOpen() -> bool
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local LootMinigames = {}
local localPlayer = Players.LocalPlayer

local REMOTE_NAME = "LootMinigame"
local CARD_W, CARD_H = 480, 430
local AREA_W, AREA_H = 400, 240

local SOUNDS = {
    click   = { id = "rbxasset://sounds/clickfast.wav", volume = 0.7, pitch = 1.25 },
    tick    = { id = "rbxasset://sounds/clickfast.wav", volume = 0.4, pitch = 1.8 },
    tap     = { id = "rbxasset://sounds/button.wav", volume = 0.45, pitch = 1.3 },
    good    = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7, pitch = 1.2 },
    bad     = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, pitch = 0.55 },
    snap    = { id = "rbxasset://sounds/snap.mp3", volume = 0.7, pitch = 1.1 },
    swoosh  = { id = "rbxasset://sounds/clickfast.wav", volume = 0.5, pitch = 1.1 },
    jam     = { id = "rbxasset://sounds/bass.wav", volume = 0.7, pitch = 1.6 },
}

local GAMEPAD = {
    [Enum.UserInputType.Gamepad1] = true, [Enum.UserInputType.Gamepad2] = true,
    [Enum.UserInputType.Gamepad3] = true, [Enum.UserInputType.Gamepad4] = true,
}

local function play(name)
    local s = SOUNDS[name]
    if not s then return end
    pcall(function()
        local snd = Instance.new("Sound")
        snd.SoundId = s.id
        snd.Volume = s.volume or 0.6
        snd.PlaybackSpeed = s.pitch or 1
        snd.Parent = SoundService
        snd:Play()
        task.delay(2, function() if snd.Parent then snd:Destroy() end end)
    end)
end

local function tween(obj, t, props, style, dir)
    local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function frame(props, parent)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.BackgroundTransparency = 1
    for k, v in pairs(props or {}) do (f :: any)[k] = v end
    f.Parent = parent
    return f
end

local function round(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or UDim.new(0.5, 0)
    c.Parent = obj
    return c
end

local function label(props, parent)
    local l = UITheme.label(props)
    l.Parent = parent
    return l
end

local function inset()
    local ok, a = pcall(function() return GuiService:GetGuiInset() end)
    return ok and a or Vector2.zero
end

-- angle helpers (degrees)
local function angDiff(a: number, b: number): number
    local d = (a - b) % 360
    if d > 180 then d = d - 360 end
    return d
end

-- ════════════════════════════════════════════════════════════════════
-- THE GAMES — each: build(area, api) -> game; game:update(dt, api) -> progress 0..1
--   api: pointer() -> Vector2 (area-local px) | nil,  down (bool), taps (count this frame),
--        stick (Vector2), keyTurn (-1..1), gamepad (bool), scale (px per design px), sound(name)
-- ════════════════════════════════════════════════════════════════════
local GAMES = {}

-- ✂ CUT: trace the frame edge. Progress = how far round the rectangle you've cut.
GAMES.cut = {}
function GAMES.cut.build(area, api)
    local g = { progress = 0 }
    local cw, ch = 300, 180
    local canvas = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(cw, ch), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(58, 76, 140) }, area)
    -- a happy little painting
    frame({ Position = UDim2.fromScale(0, 0.62), Size = UDim2.fromScale(1, 0.38), BackgroundTransparency = 0,
        BackgroundColor3 = Color3.fromRGB(60, 150, 90) }, canvas)
    local sun = frame({ Position = UDim2.fromScale(0.66, 0.14), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 0,
        BackgroundColor3 = Color3.fromRGB(255, 200, 70) }, canvas)
    round(sun)
    local hill = frame({ Position = UDim2.fromScale(0.08, 0.42), Size = UDim2.fromOffset(120, 90), BackgroundTransparency = 0,
        BackgroundColor3 = Color3.fromRGB(40, 120, 80) }, canvas)
    round(hill)
    -- gold frame (behind the dashes)
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 8
    stroke.Color = Color3.fromRGB(212, 170, 80)
    stroke.Parent = canvas
    -- dashed cut line + the gold "cut" fill on each edge
    local edges = {
        { pos = function(f) return UDim2.fromOffset(0, -2), UDim2.fromOffset(cw * f, 4) end },                 -- top →
        { pos = function(f) return UDim2.fromOffset(cw - 2, 0), UDim2.fromOffset(4, ch * f) end },             -- right ↓
        { pos = function(f) return UDim2.fromOffset(cw * (1 - f), ch - 2), UDim2.fromOffset(cw * f, 4) end },  -- bottom ←
        { pos = function(f) return UDim2.fromOffset(-2, ch * (1 - f)), UDim2.fromOffset(4, ch * f) end },      -- left ↑
    }
    for i, e in ipairs(edges) do
        local horiz = (i % 2 == 1)
        local len = horiz and cw or ch
        for k = 0, math.floor(len / 14) - 1 do
            local d = frame({ BackgroundTransparency = 0.35, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 }, canvas)
            if i == 1 then d.Position = UDim2.fromOffset(k * 14, -1) d.Size = UDim2.fromOffset(8, 2)
            elseif i == 2 then d.Position = UDim2.fromOffset(cw - 1, k * 14) d.Size = UDim2.fromOffset(2, 8)
            elseif i == 3 then d.Position = UDim2.fromOffset(k * 14, ch - 1) d.Size = UDim2.fromOffset(8, 2)
            else d.Position = UDim2.fromOffset(-1, k * 14) d.Size = UDim2.fromOffset(2, 8) end
        end
        e.fill = frame({ BackgroundTransparency = 0, BackgroundColor3 = T.gold, ZIndex = 4, Size = UDim2.fromOffset(0, 0) }, canvas)
    end
    local startDot = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(22, 22),
        BackgroundTransparency = 0, BackgroundColor3 = T.money, ZIndex = 5 }, canvas)
    round(startDot)
    local knife = label({ Text = "✂️", TextSize = 34, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(40, 40),
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, canvas)
    g.canvas, g.edges, g.knife, g.cw, g.ch = canvas, edges, knife, cw, ch
    g.P = 2 * (cw + ch)
    g.lastTick = 0
    return g
end
-- point on the rectangle at distance s (clockwise from top-left)
local function rectPoint(g, s)
    local cw, ch = g.cw, g.ch
    s = math.clamp(s, 0, g.P)
    if s <= cw then return Vector2.new(s, 0) end
    s = s - cw
    if s <= ch then return Vector2.new(cw, s) end
    s = s - ch
    if s <= cw then return Vector2.new(cw - s, ch) end
    s = s - cw
    return Vector2.new(0, ch - s)
end
-- nearest distance-along-the-path for a point (design px)
local function rectParam(g, p)
    local cw, ch = g.cw, g.ch
    local best, bestD = 0, math.huge
    local segs = {
        { 0, Vector2.new(0, 0), Vector2.new(cw, 0) },
        { cw, Vector2.new(cw, 0), Vector2.new(cw, ch) },
        { cw + ch, Vector2.new(cw, ch), Vector2.new(0, ch) },
        { 2 * cw + ch, Vector2.new(0, ch), Vector2.new(0, 0) },
    }
    for _, sg in ipairs(segs) do
        local a, b = sg[2], sg[3]
        local ab = b - a
        local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
        local q = a + ab * t
        local d = (p - q).Magnitude
        if d < bestD then best, bestD = sg[1] + ab.Magnitude * t, d end
    end
    return best, bestD
end
function GAMES.cut.update(g, dt, api)
    g.now = (g.now or 0) + dt
    local P = g.P
    local cap = 0.52 * P * dt            -- can't cut faster than ~1.9 s a lap (the knife catches up)
    local s = g.progress * P
    local moved = false
    local ptr = api.pointer(g.canvas)
    if api.gamepad and api.stick.Magnitude > 0.4 then
        s = s + math.min(cap, 0.4 * P * dt)
        moved = true
    elseif ptr and api.down then
        local sc = api.scale
        local p = ptr / sc
        local t, d = rectParam(g, p)
        -- how far AHEAD of the knife (clockwise) the finger is; the knife catches
        -- up at its own speed, so a fast finger is fine (it wraps past the start too)
        local ahead = (t - s) % P
        if d <= 40 and ahead > 0 and ahead <= P * 0.5 then
            s = s + math.min(ahead, cap)
            moved = true
        end
    end
    g.progress = math.clamp(s / P, 0, 1)
    -- draw
    local cw, ch = g.cw, g.ch
    local fills = {
        math.clamp(s / cw, 0, 1), math.clamp((s - cw) / ch, 0, 1),
        math.clamp((s - cw - ch) / cw, 0, 1), math.clamp((s - 2 * cw - ch) / ch, 0, 1),
    }
    for i, e in ipairs(g.edges) do
        local pos, size = e.pos(fills[i])
        e.fill.Position, e.fill.Size = pos, size
    end
    local kp = rectPoint(g, s)
    g.knife.Position = UDim2.fromOffset(kp.X, kp.Y)
    if moved and g.now - g.lastTick > 0.12 then
        g.lastTick = g.now
        api.sound("tick")
    end
    return g.progress
end

-- 🔒 DIAL: turn to the green dot, hold it there → CLICK. Three clicks.
GAMES.dial = {}
function GAMES.dial.build(area, api)
    local g = { angle = 0, clicks = 0, hold = 0, need = 3 }
    local size = 190
    local dial = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(60, 64, 78) }, area)
    round(dial)
    local ring = Instance.new("UIStroke")
    ring.Thickness = 8
    ring.Color = Color3.fromRGB(150, 156, 176)
    ring.Parent = dial
    -- tick marks round the edge
    for k = 0, 23 do
        local holder = frame({ Size = UDim2.fromScale(1, 1), Rotation = k * 15 }, dial)
        frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(3, k % 2 == 0 and 14 or 8),
            BackgroundTransparency = 0.3, BackgroundColor3 = Color3.new(1, 1, 1) }, holder)
    end
    -- the green target dot (moves after each click)
    g.targetHolder = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size + 44, size + 44) }, area)
    local dot = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 0, BackgroundColor3 = T.money }, g.targetHolder)
    round(dot)
    g.dot = dot
    -- the knob that turns (pointer notch at the top)
    g.knob = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size - 40, size - 40),
        BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(34, 36, 46) }, dial)
    round(g.knob)
    frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(10, 40),
        BackgroundTransparency = 0, BackgroundColor3 = T.gold }, g.knob)
    g.count = label({ Text = "0 / 3", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(100, 40), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextSize = 26, ZIndex = 3 }, g.knob)
    g.dial, g.ring, g.size = dial, ring, size
    -- targets: at least 120° apart and away from the start
    local rng = Random.new(api.seed or os.clock())
    local a = 0
    g.targets = {}
    for i = 1, g.need do
        a = a + (rng:NextInteger(0, 1) == 0 and 1 or -1) * rng:NextInteger(125, 200)
        g.targets[i] = a % 360
    end
    g.targetHolder.Rotation = g.targets[1]
    return g
end
function GAMES.dial.update(g, dt, api)
    local maxTurn = 540 * dt
    local want = nil
    if api.gamepad and api.stick.Magnitude > 0.5 then
        want = math.deg(math.atan2(api.stick.X, api.stick.Y))
    end
    local ptr = api.pointer(g.dial)
    if not want and ptr and api.down then
        local c = g.dial.AbsoluteSize / 2
        local v = ptr - c
        if v.Magnitude > 8 then
            local pa = math.deg(math.atan2(v.X, -v.Y))
            if g.lastPtr then
                g.angle = g.angle + math.clamp(angDiff(pa, g.lastPtr), -maxTurn, maxTurn)
            end
            g.lastPtr = pa
        end
    else
        g.lastPtr = nil
    end
    if want then g.angle = g.angle + math.clamp(angDiff(want, g.angle), -maxTurn, maxTurn) end
    if api.keyTurn ~= 0 then g.angle = g.angle + api.keyTurn * 260 * dt end
    g.knob.Rotation = g.angle
    if g.clicks >= g.need then return 1 end
    local diff = math.abs(angDiff(g.angle, g.targets[g.clicks + 1]))
    -- warmer = greener ring
    local warm = math.clamp(1 - diff / 120, 0, 1)
    g.ring.Color = Color3.fromRGB(150, 156, 176):Lerp(T.money, warm)
    if diff <= 11 then
        g.hold = g.hold + dt
        if g.hold >= 0.35 then
            g.hold = 0
            g.clicks = g.clicks + 1
            api.sound("click")
            g.count.Text = string.format("%d / %d", g.clicks, g.need)
            g.dial.Size = UDim2.fromOffset(g.size + 14, g.size + 14)
            tween(g.dial, 0.2, { Size = UDim2.fromOffset(g.size, g.size) }, Enum.EasingStyle.Back)
            if g.clicks < g.need then g.targetHolder.Rotation = g.targets[g.clicks + 1] else g.dot.Visible = false end
        end
    else
        g.hold = 0
    end
    return g.clicks / g.need
end

-- 💰 STUFF: tap fast to fill the bag (it slowly empties if you stop)
GAMES.stuff = {}
function GAMES.stuff.build(area, api)
    local g = { fill = 0, last = -1 }
    g.bag = label({ Text = "💰", TextSize = 110, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
        Size = UDim2.fromOffset(160, 140), TextXAlignment = Enum.TextXAlignment.Center }, area)
    g.scaleObj = Instance.new("UIScale")
    g.scaleObj.Parent = g.bag
    g.tap = label({ Text = "TAP!", FontFace = UITheme.F.display, TextSize = 30, TextColor3 = T.money,
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -44), Size = UDim2.fromOffset(200, 36),
        TextXAlignment = Enum.TextXAlignment.Center }, area)
    g.area = area
    return g
end
function GAMES.stuff.update(g, dt, api)
    g.now = (g.now or 0) + dt
    for _ = 1, api.taps do
        if g.now - g.last >= 0.1 then
            g.last = g.now
            g.fill = math.min(1, g.fill + 0.07)
            api.sound("tap")
            g.scaleObj.Scale = 1.18
            tween(g.scaleObj, 0.15, { Scale = 1 })
            -- a bill flies into the bag
            local bill = label({ Text = "💵", TextSize = 30, AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(math.random(10, 90) / 100, 0.95), Size = UDim2.fromOffset(36, 36),
                TextXAlignment = Enum.TextXAlignment.Center }, g.area)
            tween(bill, 0.3, { Position = UDim2.fromScale(0.5, 0.42), TextTransparency = 0.6 })
            task.delay(0.32, function() bill:Destroy() end)
        end
    end
    if g.fill < 1 then g.fill = math.max(0, g.fill - 0.1 * dt) end
    g.tap.TextTransparency = 0.4 + 0.4 * math.sin(g.now * 10)
    return g.fill
end

-- 🔩 UNSCREW: 4 screws. Hold one (spin round it = faster). Then the glass lifts off.
GAMES.unscrew = {}
function GAMES.unscrew.build(area, api)
    local g = { screws = {}, active = nil, lifted = false }
    local glass = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 190),
        BackgroundTransparency = 0.45, BackgroundColor3 = Color3.fromRGB(170, 220, 255) }, area)
    round(glass, UDim.new(0, 10))
    local st = Instance.new("UIStroke")
    st.Thickness = 3
    st.Color = Color3.fromRGB(230, 245, 255)
    st.Parent = glass
    label({ Text = "💎", TextSize = 70, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(100, 90), TextXAlignment = Enum.TextXAlignment.Center }, glass)
    for i, pos in ipairs({ Vector2.new(0.08, 0.12), Vector2.new(0.92, 0.12), Vector2.new(0.92, 0.88), Vector2.new(0.08, 0.88) }) do
        local s = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(pos.X, pos.Y), Size = UDim2.fromOffset(46, 46),
            BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(190, 196, 210), ZIndex = 3 }, glass)
        round(s)
        local ring = Instance.new("UIStroke")
        ring.Thickness = 4
        ring.Color = T.gold
        ring.Transparency = 1
        ring.Parent = s
        local slot = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 6),
            BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(70, 74, 88), ZIndex = 4 }, s)
        g.screws[i] = { frame = s, slot = slot, ring = ring, p = 0, done = false }
    end
    g.glass = glass
    return g
end
function GAMES.unscrew.update(g, dt, api)
    g.now = (g.now or 0) + dt
    local left = 0
    for _, s in ipairs(g.screws) do if not s.done then left = left + 1 end end
    if left == 0 then
        if not g.lifted then
            g.lifted = true
            g.liftAt = g.now
            api.sound("swoosh")
            tween(g.glass, 0.25, { Position = UDim2.fromScale(0.5, -0.2), BackgroundTransparency = 1 })
        end
        return (g.now - g.liftAt >= 0.25) and 1 or 0.99
    end
    local ptr = api.pointer(g.glass)
    local target = nil
    if ptr and api.down and not api.gamepad then
        for _, s in ipairs(g.screws) do
            if not s.done then
                local c = s.frame.AbsolutePosition - g.glass.AbsolutePosition + s.frame.AbsoluteSize / 2
                if (ptr - c).Magnitude <= 40 * api.scale then target = s break end
            end
        end
    elseif api.down then
        for _, s in ipairs(g.screws) do if not s.done then target = s break end end
    end
    -- highlight the next screw for gamepad / keys
    for _, s in ipairs(g.screws) do s.ring.Transparency = (s == target) and 0 or (s.done and 1 or 0.7) end
    if target then
        local speed = 1 / 0.5
        -- spinning round the screw (or the stick) makes it faster
        local spin = 0
        if api.gamepad then
            spin = api.stick.Magnitude > 0.5 and 1 or 0
        elseif ptr then
            local c = target.frame.AbsolutePosition - g.glass.AbsolutePosition + target.frame.AbsoluteSize / 2
            local v = ptr - c
            if v.Magnitude > 4 then
                local a = math.deg(math.atan2(v.X, -v.Y))
                if g.lastA and g.lastTarget == target then
                    spin = math.clamp(math.abs(angDiff(a, g.lastA)) / (dt * 180), 0, 1)
                end
                g.lastA = a
            end
        end
        g.lastTarget = target
        target.p = math.min(1, target.p + dt * speed * (1 + 0.8 * spin))
        target.slot.Rotation = target.p * 720
        if target.p >= 1 then
            target.done = true
            api.sound("snap")
            tween(target.frame, 0.2, { BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 10) })
            target.slot.Visible = false
        end
    else
        g.lastA = nil
    end
    local sum = 0
    for _, s in ipairs(g.screws) do sum = sum + s.p end
    return math.min(0.98, sum / #g.screws)
end

-- 🔧 DRILL: tap to put the drill on. It runs… JAMMED → tap tap tap → runs → done.
GAMES.drill = {}
function GAMES.drill.build(area, api)
    local g = { phase = "place", p = 0, jamAt = 0.4 + math.random() * 0.25, jammed = false, fixes = 0, last = -1 }
    g.box = frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(170, 130),
        BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(80, 86, 100) }, area)
    round(g.box, UDim.new(0, 14))
    label({ Text = "🔒", TextSize = 60, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(80, 70), TextXAlignment = Enum.TextXAlignment.Center }, g.box)
    g.drill = label({ Text = "🔧", TextSize = 64, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.82, 0.12),
        Size = UDim2.fromOffset(80, 70), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, area)
    g.msg = label({ Text = "TAP to put the drill on!", FontFace = UITheme.F.display, TextSize = 24, TextColor3 = T.gold,
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(360, 34),
        TextXAlignment = Enum.TextXAlignment.Center }, area)
    g.area = area
    return g
end
function GAMES.drill.update(g, dt, api)
    g.now = (g.now or 0) + dt
    if g.phase == "place" then
        if api.taps > 0 then
            g.phase = "run"
            api.sound("snap")
            tween(g.drill, 0.2, { Position = UDim2.fromScale(0.5, 0.45) })
            g.msg.Text = "Drilling..."
            g.msg.TextColor3 = T.text
        end
        return 0
    end
    if g.jammed then
        for _ = 1, api.taps do
            if g.now - g.last >= 0.08 then
                g.last = g.now
                g.fixes = g.fixes + 1
                api.sound("tap")
                g.drill.Rotation = (g.fixes % 2 == 0) and 12 or -12
            end
        end
        g.box.Position = UDim2.new(0.5, math.sin(g.now * 60) * 3, 0.45, 0)
        if g.fixes >= 4 then
            g.jammed = false
            g.drill.Rotation = 0
            g.box.Position = UDim2.fromScale(0.5, 0.45)
            g.msg.Text = "Fixed! Drilling..."
            g.msg.TextColor3 = T.money
            api.sound("good")
        end
        return g.p
    end
    g.p = math.min(1, g.p + dt / 2.6)
    g.drill.Rotation = math.sin(g.now * 50) * 6
    if not g.jamDone and g.p >= g.jamAt then
        g.jamDone = true
        g.jammed = true
        g.fixes = 0
        g.msg.Text = "JAMMED! TAP TAP TAP!"
        g.msg.TextColor3 = T.danger
        api.sound("jam")
    end
    return g.p
end

-- ════════════════════════════════════════════════════════════════════
-- the card + input plumbing
-- ════════════════════════════════════════════════════════════════════
function LootMinigames:_buildGui()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("LootMinigames")
    if old then old:Destroy() end
    local gui = Instance.new("ScreenGui")
    gui.Name = "LootMinigames"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Enabled = false
    gui.Parent = pg
    self._gui = gui
end

function LootMinigames:isOpen()
    return self._open ~= nil
end

function LootMinigames:_send(msg)
    if self._remote then pcall(function() self._remote:FireServer(msg) end) end
end

function LootMinigames:_close(delaySec)
    local o = self._open
    if not o then return end
    self._open = nil
    for _, c in ipairs(o.conns) do c:Disconnect() end
    pcall(function() ProximityPromptService.Enabled = true end)
    local card = o.card
    task.delay(delaySec or 0, function()
        if not card.Parent then return end
        tween(o.cardScale, 0.18, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        task.delay(0.18, function()
            card:Destroy()
            if not self._open and self._gui then self._gui.Enabled = false end
        end)
    end)
end

-- the result line on the card (green / red), then close
function LootMinigames:_flash(o, text, good)
    if not o or not o.card.Parent then return end
    o.status.Text = text
    o.status.TextColor3 = good and T.money or T.danger
    o.status.Visible = true
end

function LootMinigames:_finish(mode)
    local o = self._open
    if not o or o.finished then return end
    o.finished = true
    self:_flash(o, "NICE!", true)
    play("good")
    self:_send({ op = "done", token = o.token, mode = mode, ok = true })
    -- the server answers with a result; if it never does, close anyway
    local token = o.token
    task.delay(3, function()
        if self._open and self._open.token == token then self:_close(0) end
    end)
end

function LootMinigames:_cancel()
    local o = self._open
    if not o then return end
    self:_send({ op = "cancel", token = o.token })
    self:_close(0)
end

function LootMinigames:_openGame(msg)
    if self._open then self:_close(0) end
    local def = GAMES[msg.game]
    if not def then
        -- unknown game: the hold fallback still works
        def = GAMES.stuff
    end
    local gui = self._gui
    gui.Enabled = true

    local card = UITheme.card({ Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
        Size = UDim2.fromOffset(CARD_W, CARD_H), accent = T.gold, radius = 22, Active = true })
    card.Parent = gui
    UITheme.autoScale(card)
    local cardScale = Instance.new("UIScale")
    cardScale.Scale = 0.8
    cardScale.Parent = card
    tween(cardScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
    -- frees the mouse in first person / shift-lock while the card is up
    local modal = Instance.new("TextButton")
    modal.Name = "Modal"
    modal.Modal = true
    modal.BackgroundTransparency = 1
    modal.Text = ""
    modal.Size = UDim2.fromScale(1, 1)
    modal.AutoButtonColor = false
    modal.Parent = card

    label({ Text = tostring(msg.title or "GET IT!"), FontFace = UITheme.F.display, TextSize = 32, TextColor3 = T.gold,
        Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Center }, card)
    label({ Text = string.format("%s  ·  %s", tostring(msg.name or "Loot"), UITheme.money(tonumber(msg.value) or 0)),
        FontFace = UITheme.F.bold, TextSize = 16, TextColor3 = T.muted,
        Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center }, card)
    label({ Text = tostring(msg.hint or ""), FontFace = UITheme.F.medium, TextSize = 17, TextColor3 = T.text,
        Position = UDim2.fromOffset(20, 72), Size = UDim2.new(1, -40, 0, 22), TextXAlignment = Enum.TextXAlignment.Center,
        TextWrapped = true }, card)

    local area = frame({ Name = "Area", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 100),
        Size = UDim2.fromOffset(AREA_W, AREA_H), BackgroundTransparency = 0, BackgroundColor3 = T.bgRaised, Active = true,
        ClipsDescendants = true }, card)
    round(area, UDim.new(0, 16))

    -- progress bar
    local barBg = frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 100 + AREA_H + 12),
        Size = UDim2.fromOffset(AREA_W, 14), BackgroundTransparency = 0, BackgroundColor3 = T.bgDeep }, card)
    round(barBg)
    local bar = frame({ Size = UDim2.fromScale(0, 1), BackgroundTransparency = 0, BackgroundColor3 = T.money }, barBg)
    round(bar)

    -- footer: HOLD fallback button + hint
    local holdBtn = UITheme.button("HOLD 3s", T.info, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 40, 1, -14),
        Size = UDim2.fromOffset(130, 34), TextSize = 16 })
    holdBtn.Parent = card
    local holdFill = frame({ Size = UDim2.fromScale(0, 1), BackgroundTransparency = 0.55, BackgroundColor3 = Color3.new(1, 1, 1),
        ZIndex = 2 }, holdBtn)
    round(holdFill, UDim.new(0, 14))
    local holdHint = label({ Text = "or hold E", FontFace = UITheme.F.bold, TextSize = 14, TextColor3 = T.muted,
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 180, 1, -20), Size = UDim2.fromOffset(160, 22) }, card)
    local closeBtn = UITheme.button("✕", T.danger, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12),
        Size = UDim2.fromOffset(36, 36), TextSize = 18 })
    closeBtn.Parent = card
    local status = label({ Text = "", FontFace = UITheme.F.display, TextSize = 40, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0, 100 + AREA_H / 2), Size = UDim2.fromOffset(AREA_W, 60),
        TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2, TextStrokeColor3 = T.bgDeep, ZIndex = 20,
        Visible = false }, card)

    local o = {
        token = msg.token, game = msg.game, card = card, cardScale = cardScale, area = area, bar = bar, status = status,
        holdFill = holdFill, holdT = 0, holdNeed = tonumber(msg.hold) or 3, conns = {}, finished = false,
        t0 = os.clock(), timeout = tonumber(msg.timeout) or 30,
        input = { down = false, taps = 0, touchPos = nil, stick = Vector2.zero, keyTurn = 0, holdKey = false, holdBtn = false,
            gamepad = GAMEPAD[UserInputService:GetLastInputType()] == true },
    }
    self._open = o
    pcall(function() ProximityPromptService.Enabled = false end)

    local inp = o.input
    local function lastIsGamepad(t) if GAMEPAD[t] then inp.gamepad = true elseif t ~= Enum.UserInputType.Focus then
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Keyboard
            or t == Enum.UserInputType.MouseMovement then inp.gamepad = false end end end
    local keysDown = {}
    local function keyTurn()
        local k = 0
        if keysDown[Enum.KeyCode.D] or keysDown[Enum.KeyCode.Right] then k = k + 1 end
        if keysDown[Enum.KeyCode.A] or keysDown[Enum.KeyCode.Left] then k = k - 1 end
        inp.keyTurn = k
    end
    table.insert(o.conns, UserInputService.InputBegan:Connect(function(io)
        lastIsGamepad(io.UserInputType)
        local t, k = io.UserInputType, io.KeyCode
        if t == Enum.UserInputType.MouseButton1 then
            inp.down = true
            inp.taps = inp.taps + 1
        elseif t == Enum.UserInputType.Touch then
            inp.down = true
            inp.taps = inp.taps + 1
            inp.touchPos = Vector2.new(io.Position.X, io.Position.Y) + inset()
        elseif k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.Space or k == Enum.KeyCode.ButtonR2 then
            inp.down = true
            inp.taps = inp.taps + 1
        elseif k == Enum.KeyCode.E or k == Enum.KeyCode.ButtonX then
            inp.holdKey = true
        elseif k == Enum.KeyCode.Backspace or k == Enum.KeyCode.ButtonB then
            self:_cancel()
        else
            keysDown[k] = true
            keyTurn()
        end
    end))
    table.insert(o.conns, UserInputService.InputEnded:Connect(function(io)
        local t, k = io.UserInputType, io.KeyCode
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
            or k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.Space or k == Enum.KeyCode.ButtonR2 then
            inp.down = false
            if t == Enum.UserInputType.Touch then inp.touchPos = nil end
        elseif k == Enum.KeyCode.E or k == Enum.KeyCode.ButtonX then
            inp.holdKey = false
        else
            keysDown[k] = nil
            keyTurn()
        end
    end))
    table.insert(o.conns, UserInputService.InputChanged:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.Touch then
            inp.touchPos = Vector2.new(io.Position.X, io.Position.Y) + inset()
        elseif io.KeyCode == Enum.KeyCode.Thumbstick1 or io.KeyCode == Enum.KeyCode.Thumbstick2 then
            inp.gamepad = true
            local v = Vector2.new(io.Position.X, io.Position.Y)
            inp.stick = v.Magnitude > 0.2 and v or Vector2.zero
        elseif io.UserInputType == Enum.UserInputType.MouseMovement then
            inp.gamepad = false
        end
    end))
    table.insert(o.conns, holdBtn.MouseButton1Down:Connect(function() inp.holdBtn = true end))
    table.insert(o.conns, holdBtn.MouseButton1Up:Connect(function() inp.holdBtn = false end))
    table.insert(o.conns, holdBtn.MouseLeave:Connect(function() inp.holdBtn = false end))
    table.insert(o.conns, closeBtn.Activated:Connect(function() self:_cancel() end))
    holdHint.Text = inp.gamepad and "or hold X" or (UITheme.isTouch() and "" or "or hold E")

    local api = {
        seed = tonumber(msg.token),
        scale = 1,
        sound = play,
    }
    function api.pointer(rel)
        local abs
        if inp.touchPos then abs = inp.touchPos
        elseif not inp.gamepad then abs = UserInputService:GetMouseLocation() end
        if not abs then return nil end
        return abs - (rel or area).AbsolutePosition
    end
    local ok, g = pcall(def.build, area, api)
    if not ok then
        warn("[LootMinigames] build:", g)
        g = nil
    end

    table.insert(o.conns, RunService.RenderStepped:Connect(function(dt)
        if self._open ~= o or o.finished then return end
        -- design px → screen px (the card's UIScales)
        api.scale = math.max(0.1, area.AbsoluteSize.X / AREA_W)
        api.down, api.taps, api.stick, api.keyTurn, api.gamepad = inp.down, inp.taps, inp.stick, inp.keyTurn, inp.gamepad
        inp.taps = 0
        local progress = 0
        if g then
            local okU, p = pcall(def.update, g, dt, api)
            if okU then progress = tonumber(p) or 0 else warn("[LootMinigames] update:", p) g = nil end
        end
        bar.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
        -- the accessibility hold
        if inp.holdKey or inp.holdBtn then
            o.holdT = o.holdT + dt
        else
            o.holdT = math.max(0, o.holdT - dt * 2)
        end
        holdFill.Size = UDim2.fromScale(math.clamp(o.holdT / o.holdNeed, 0, 1), 1)
        if o.holdT >= o.holdNeed then
            self:_finish("hold")
        elseif progress >= 1 then
            self:_finish("game")
        elseif os.clock() - o.t0 > o.timeout then
            self:_cancel()
        end
    end))
end

function LootMinigames:_onMessage(msg)
    if type(msg) ~= "table" then return end
    if msg.op == "start" then
        self:_openGame(msg)
    elseif msg.op == "stop" then
        local o = self._open
        if o and (msg.token == nil or msg.token == o.token) then
            o.finished = true
            local why = { caught = "CAUGHT!", timeout = "TOO SLOW!", reset = "", died = "OUCH!", switch = "" }
            local text = why[msg.reason] or ""
            if text ~= "" then
                self:_flash(o, text, false)
                play("bad")
                self:_close(0.8)
            else
                self:_close(0)
            end
        end
    elseif msg.op == "result" then
        local o = self._open
        if o and msg.token == o.token then
            if msg.ok then
                self:_close(0.35)
            else
                self:_flash(o, tostring(msg.msg or "Try again!"), false)
                play("bad")
                self:_close(1.2)
            end
        end
    end
end

function LootMinigames:start()
    self:_buildGui()
    task.spawn(function()
        local remote = nil
        for _ = 1, 12 do
            remote = Remotes.getRemote(REMOTE_NAME, "RemoteEvent")
            if remote then break end
        end
        if not remote then
            warn("[HEIST CREW] LootMinigames: LootMinigame remote missing — mini-games disabled")
            return
        end
        self._remote = remote
        remote.OnClientEvent:Connect(function(msg)
            local ok, err = pcall(self._onMessage, self, msg)
            if not ok then warn("[LootMinigames]", err) end
        end)
    end)
    -- a respawn mid-game: let the server know it's off
    localPlayer.CharacterAdded:Connect(function()
        if self._open then self:_cancel() end
    end)
    print("[HEIST CREW] LootMinigames mounted ✅")
end

-- (tests) drive a game headless: returns the GAMES table
LootMinigames._GAMES = GAMES

return LootMinigames
