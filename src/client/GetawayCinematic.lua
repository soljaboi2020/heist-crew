--[[
    HEIST CREW — GetawayCinematic  (v3.0 "THE SCORE", getaway agent)
    ────────────────────────────────────────────────
    Plays the getaway MOVIE the server sends (server/GetawayService.lua builds
    it; everybody in the crew gets the same payload):

        { phase = "scene", scene = {...}, crew = {Player}, carModel = Model }

    Everything in the movie is a LOCAL COPY made for this one scene and thrown
    away after: the getaway car (cloned from the real one, so it's the crew's
    real car type), the crew sitting in it (clones of their avatars, in their
    real seats), the chase cruisers, the roadblock, the yard shutter, the
    speedboat / helicopter (templates in ReplicatedStorage.HC_GetawayProps).
    The real car + real characters (still parked in the yard) and the real
    marina boat are hidden locally with LocalTransparencyModifier meanwhile.

    TIMELINE (all a pure function of scene time t, so SKIP just jumps t):
      tracks   keyframes {t, p, y, x?, r?, c?} → Hermite (time-aware Catmull-Rom)
               for position, shortest-arc yaw, lerped pitch/roll; a key with c=1
               starts a new segment (the highway cut) — no blending across it
      props    Shutter rolls up (open0 → open1), Roadblock sits on the road
      events   smash (fly / bounce / hop / none) · nitro flames · fade to black ·
               hop (crew jump into the boat / helicopter) · sirens on/off ·
               shake · wake · stamp ("GOT AWAY!")
      shots    fixed (CFrame → CFrame) · look (camera a → b, looking at a track)
               · chase (behind a track, offsets o1 → o2) · lookback (rides on the
               far side of a track from a focus point, looking back through it at
               the focus — the held final shot: boat + wake, skyline behind).
               A new shot = a cut, and (playtest fix 2026-09-25) every cut after
               the first happens UNDER BLACK: the frame of the cut is fully black,
               then it fades in over CUT_DIP s — no glitch frame between shots.
               The camera is also never left inside a part: if the spot a shot
               asks for is inside something solid, it is pulled in toward the
               subject along the line of sight (unclip).
      captions bottom of the screen; "📻 …" goes in the radio chip instead

    Letterbox bars, other HUDs hidden (restored after), controls off, SKIP
    after 3 s (button, Space / Enter / gamepad B). When the scene ends the
    camera HOLDS the final shot (the boat / helicopter / car keeps going) while
    the PayoutScreen sits over it; closing the payout (or ~9 s with no payout)
    hands the camera back. The payout screen sets the local player attribute
    PayoutOpen = true/false (PayoutScreen.lua).

    Local attribute: GetawayPlaying = true while the movie runs.

    PUBLIC API:
        GetawayCinematic:start()            -- idempotent
        GetawayCinematic:play(msg)          -- (tests) play a scene payload
        GetawayCinematic:stop()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local GetawayCinematic = {}
local localPlayer = Players.LocalPlayer

local SKIP_AFTER = 3
local CUT_DIP = 0.18          -- black dip on every cut (seconds to fade back in)
local FAR = CFrame.new(0, -5000, 0)
local RED = Color3.fromRGB(255, 40, 60)
local BLUE = Color3.fromRGB(60, 110, 255)
local KEEP_GUIS = { GetawayCinematic = true, PayoutScreen = true, GetawayVote = true }

local function smooth(u) u = math.clamp(u, 0, 1) return u * u * (3 - 2 * u) end
local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end

-- ══════════════════════════════════════════════════════════════════════
-- track evaluation
-- ══════════════════════════════════════════════════════════════════════
local function findKey(keys, t)
    local n = #keys
    if n == 0 or t < keys[1].t then return nil end
    if t >= keys[n].t then return n end
    local lo, hi = 1, n
    while hi - lo > 1 do
        local mid = (lo + hi) // 2
        if keys[mid].t <= t then lo = mid else hi = mid end
    end
    -- several keys can share a time (a segment cut): take the last one ≤ t
    while lo < n and keys[lo + 1].t <= t do lo = lo + 1 end
    return lo
end

local function tangent(keys, i)
    local k = keys[i]
    local prev = (i > 1 and not k.c) and keys[i - 1] or nil
    local nxt = keys[i + 1]
    if nxt and nxt.c then nxt = nil end
    if prev and nxt and nxt.t > prev.t then return (nxt.p - prev.p) / (nxt.t - prev.t) end
    if nxt and nxt.t > k.t then return (nxt.p - k.p) / (nxt.t - k.t) end
    if prev and k.t > prev.t then return (k.p - prev.p) / (k.t - prev.t) end
    return Vector3.zero
end

-- → CFrame (nil before the track's first key)
local function evalTrack(keys, t)
    if type(keys) ~= "table" then return nil end
    local i = findKey(keys, t)
    if not i then return nil end
    local a = keys[i]
    local b = keys[i + 1]
    local p, y, x, r
    if not b or b.c or b.t <= a.t then
        p, y, x, r = a.p, a.y or 0, a.x or 0, a.r or 0
    else
        local h = b.t - a.t
        local u = math.clamp((t - a.t) / h, 0, 1)
        local u2, u3 = u * u, u * u * u
        local h00, h10, h01, h11 = 2 * u3 - 3 * u2 + 1, u3 - 2 * u2 + u, -2 * u3 + 3 * u2, u3 - u2
        p = a.p * h00 + tangent(keys, i) * (h10 * h) + b.p * h01 + tangent(keys, i + 1) * (h11 * h)
        y = (a.y or 0) + wrap((b.y or 0) - (a.y or 0)) * u
        x = (a.x or 0) + ((b.x or 0) - (a.x or 0)) * u
        r = (a.r or 0) + ((b.r or 0) - (a.r or 0)) * u
    end
    return CFrame.new(p) * CFrame.Angles(0, y, 0) * CFrame.Angles(x, 0, r)
end

-- yaw-only frame (steady cameras)
local function flatCF(cf)
    local look = cf.LookVector
    local f = Vector3.new(look.X, 0, look.Z)
    if f.Magnitude < 1e-3 then f = Vector3.new(0, 0, -1) end
    return CFrame.lookAt(cf.Position, cf.Position + f.Unit)
end

-- never leave the camera inside a part: if `cf` sits inside something visible,
-- pull it in toward `anchor` (the subject) to just in front of the first hit.
-- The scene's own copies (s.folder) and hidden real parts are ignored.
local function unclip(s, cf, anchor)
    if not anchor or not s.overlap then return cf end
    local pos = cf.Position
    local okO, hits = pcall(function() return Workspace:GetPartBoundsInRadius(pos, 0.6, s.overlap) end)
    if not okO or type(hits) ~= "table" then return cf end
    local inside = false
    for _, p in ipairs(hits) do
        if p.Transparency < 0.9 and p.LocalTransparencyModifier < 0.9 and not p:IsA("Terrain") then inside = true break end
    end
    if not inside then return cf end
    local dir = pos - anchor
    if dir.Magnitude < 1 then return cf end
    local okR, hit = pcall(function() return Workspace:Raycast(anchor, dir, s.rayParams) end)
    if not okR or not hit then return cf end   -- (bounding-box false alarm: leave it)
    local safe = hit.Position - dir.Unit * 0.8
    return CFrame.lookAt(safe, safe + cf.LookVector)
end

-- ══════════════════════════════════════════════════════════════════════
-- copies
-- ══════════════════════════════════════════════════════════════════════
local function ghost(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
            d.CanCollide = false
            d.CanQuery = false
            d.CanTouch = false
        elseif d:IsA("ProximityPrompt") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound")
            or d:IsA("Animator") or d:IsA("ForceField") or d:IsA("BillboardGui") then
            d:Destroy()
        elseif d:IsA("Seat") or d:IsA("VehicleSeat") then
            d.Disabled = true
        end
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("Seat") or d:IsA("VehicleSeat") then d.Disabled = true end
    end
    for _, tag in ipairs(CollectionService:GetTags(model)) do CollectionService:RemoveTag(model, tag) end
end

local function cloneOf(inst)
    if not inst then return nil end
    local was = inst.Archivable
    inst.Archivable = true
    local ok, c = pcall(function() return inst:Clone() end)
    inst.Archivable = was
    if ok and c then ghost(c) return c end
    return nil
end

local function template(name)
    local f = ReplicatedStorage:FindFirstChild("HC_GetawayProps")
    local t = f and f:FindFirstChild(name)
    return t and cloneOf(t) or nil
end

local function carFallback(carType)
    local f = ReplicatedStorage:FindFirstChild("HC_CarPreviews")
    if not f then return nil end
    local id = "Car" .. string.upper(string.sub(carType or "classic", 1, 1)) .. string.sub(carType or "classic", 2)
    local m = f:FindFirstChild(id) or f:FindFirstChild("CarClassic")
    return m and cloneOf(m) or nil
end

-- ══════════════════════════════════════════════════════════════════════
-- UI
-- ══════════════════════════════════════════════════════════════════════
function GetawayCinematic:_build()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("GetawayCinematic")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "GetawayCinematic"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 12       -- under the PayoutScreen (15): the payout lands over the final shot
    screen.Enabled = false
    screen.Parent = pg

    local bars = {}
    for i, anchor in ipairs({ 0, 1 }) do
        local b = Instance.new("Frame")
        b.Name = "Bar"
        b.BackgroundColor3 = Color3.new(0, 0, 0)
        b.BorderSizePixel = 0
        b.AnchorPoint = Vector2.new(0, anchor)
        b.Position = UDim2.fromScale(0, anchor)
        b.Size = UDim2.new(1, 0, 0, 0)
        b.Parent = screen
        bars[i] = b
    end
    local black = Instance.new("Frame")
    black.Name = "Black"
    black.Size = UDim2.fromScale(1, 1)
    black.BackgroundColor3 = Color3.new(0, 0, 0)
    black.BackgroundTransparency = 1
    black.BorderSizePixel = 0
    black.ZIndex = 5
    black.Parent = screen

    local caption = UITheme.label({ Name = "Caption", Text = "", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.88, -8),
        Size = UDim2.new(1, 0, 0, 60), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 52,
        TextColor3 = T.gold, TextStrokeTransparency = 0.3, TextStrokeColor3 = Color3.new(0, 0, 0), TextTransparency = 1, ZIndex = 6 })
    caption.Parent = screen
    UITheme.autoScale(caption)

    local radio = UITheme.card({ Name = "Radio", AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 24, 0.12, 12),
        Size = UDim2.fromOffset(280, 44), radius = 22, accent = T.pink, Visible = false })
    radio.Parent = screen
    local radioText = UITheme.label({ Name = "Text", Text = "", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 20, TextColor3 = T.pink })
    radioText.Parent = radio
    UITheme.autoScale(radio)

    local stamp = UITheme.label({ Name = "Stamp", Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
        Size = UDim2.new(1, 0, 0, 140), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 110,
        TextColor3 = T.money, TextStrokeTransparency = 0.2, Rotation = -5, Visible = false, ZIndex = 7 })
    stamp.Parent = screen
    UITheme.autoScale(stamp)

    local skip = UITheme.button("SKIP ▶▶", T.text, { Name = "Skip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -18),
        Size = UDim2.fromOffset(150, 46), TextSize = 20, Visible = false, ZIndex = 8 })
    skip.Parent = screen
    UITheme.autoScale(skip)
    skip.Activated:Connect(function() self:skip() end)

    self._u = { screen = screen, bars = bars, black = black, caption = caption, radio = radio, radioText = radioText,
        stamp = stamp, skip = skip }
end

-- ══════════════════════════════════════════════════════════════════════
-- play
-- ══════════════════════════════════════════════════════════════════════
function GetawayCinematic:skip()
    local s = self._s
    if not s or s.t < SKIP_AFTER or s.t >= s.duration - 0.5 then return end
    s.offset = s.offset + (s.duration - 0.4 - s.t)
    s.skipped = true
end

function GetawayCinematic:stop()
    local s = self._s
    if not s then return end
    self._s = nil
    if s.conn then s.conn:Disconnect() end
    if s.inputConn then s.inputConn:Disconnect() end
    for _, snd in ipairs(s.sounds or {}) do pcall(function() snd:Stop() snd:Destroy() end) end
    for _, p in ipairs(s.hiddenParts or {}) do
        if p.Parent then p.LocalTransparencyModifier = 0 end
    end
    if s.folder then s.folder:Destroy() end
    local cam = Workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        cam.FieldOfView = 70
        local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then cam.CameraSubject = hum end
        -- (v3.3) behind the character, facing the way it faces (CameraFeel)
        local mod = script.Parent:FindFirstChild("CameraFeel")
        if mod then pcall(function() require(mod).restoreBehind() end) end
    end
    if s.controls then pcall(function() s.controls:Enable() end) end
    for _, g in ipairs(s.hiddenGuis or {}) do
        if g.Parent then g.Enabled = true end
    end
    local u = self._u
    if u then
        for _, b in ipairs(u.bars) do b.Size = UDim2.new(1, 0, 0, 0) end
        u.black.BackgroundTransparency = 1
        u.caption.TextTransparency = 1
        u.stamp.Visible = false
        u.skip.Visible = false
        u.radio.Visible = false
        u.screen.Enabled = false
    end
    localPlayer:SetAttribute("GetawayPlaying", false)
end

function GetawayCinematic:play(msg)
    if self._s then self:stop() end
    local scene = msg and msg.scene
    if type(scene) ~= "table" then return end
    local u = self._u
    local cam = Workspace.CurrentCamera
    if not u or not cam then return end

    local folder = Instance.new("Folder")
    folder.Name = "GetawayScene"
    folder.Parent = Workspace
    local s = {
        scene = scene, folder = folder, t = 0, offset = 0, t0 = os.clock(),
        duration = tonumber(scene.duration) or 12, hold = tonumber(scene.hold) or 9,
        models = {}, props = {}, crew = {}, hiddenParts = {}, hiddenGuis = {}, sounds = {}, fired = {},
        payoutSeen = false, lastShot = nil,
    }
    self._s = s
    localPlayer:SetAttribute("GetawayPlaying", true)
    local tracks = scene.tracks or {}

    -- ── the car + crew ──
    local realCar = msg.carModel
    local car = (typeof(realCar) == "Instance" and realCar.Parent) and cloneOf(realCar) or carFallback(scene.carType)
    local realPivot = (typeof(realCar) == "Instance" and realCar.Parent) and realCar:GetPivot() or nil
    if car then
        car.Name = "SceneCar"
        car.Parent = folder
        s.models.car = car
        for _, d in ipairs(car:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == "NitroFlame" then d.Transparency = 1 end
        end
        if not car.PrimaryPart then car.PrimaryPart = car:FindFirstChild("Root") or car:FindFirstChildWhichIsA("BasePart") end
    end
    if realCar and typeof(realCar) == "Instance" then
        for _, d in ipairs(realCar:GetDescendants()) do
            if d:IsA("BasePart") then table.insert(s.hiddenParts, d) end
        end
    end
    local seatNames = { "GetawayDriverSeat", "PassengerSeat", "RearSeatL", "RearSeatR" }
    local usedSeat = {}
    local crewList = type(msg.crew) == "table" and msg.crew or {}
    for _, p in ipairs(crewList) do
        if #s.crew >= 4 then break end
        local char = typeof(p) == "Instance" and p:IsA("Player") and p.Character or nil
        if char and car then
            local clone = cloneOf(char)
            if clone then
                local hum = clone:FindFirstChildOfClass("Humanoid")
                if hum then
                    pcall(function()
                        hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                        hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
                    end)
                end
                clone.Name = "Crew_" .. p.Name
                clone.Parent = folder
                local offset
                local realHum = char:FindFirstChildOfClass("Humanoid")
                local seat = realHum and realHum.SeatPart
                if seat and realPivot and seat:IsDescendantOf(realCar) then
                    offset = realPivot:ToObjectSpace(char:GetPivot())
                    usedSeat[seat.Name] = true
                else
                    for _, nm in ipairs(seatNames) do
                        if not usedSeat[nm] then
                            local cs = car:FindFirstChild(nm, true)
                            if cs and cs:IsA("BasePart") then
                                usedSeat[nm] = true
                                offset = car:GetPivot():ToObjectSpace(cs.CFrame * CFrame.new(0, cs.Size.Y / 2 + 1.55, 0))
                                break
                            end
                        end
                    end
                end
                if offset then
                    table.insert(s.crew, { model = clone, offset = offset, index = #s.crew + 1 })
                else
                    clone:Destroy()
                end
                for _, d in ipairs(char:GetDescendants()) do
                    if d:IsA("BasePart") then table.insert(s.hiddenParts, d) end
                end
            end
        end
    end

    -- ── other vehicles ──
    for _, name in ipairs({ "cop1", "cop2" }) do
        if tracks[name] then
            local m = template("Cruiser")
            if m then m.Name = name m:PivotTo(FAR) m.Parent = folder s.models[name] = m end
        end
    end
    if tracks.boat then
        local m = template("Speedboat")
        if m then
            m:PivotTo(FAR)
            m.Parent = folder
            s.models.boat = m
            local root = m.PrimaryPart
            local wakeAt = root and root:FindFirstChild("Wake")
            if wakeAt then
                local pe = Instance.new("ParticleEmitter")
                pe.Name = "WakeFX"
                pe.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255))
                pe.Size = NumberSequence.new(1.2, 4)
                pe.Transparency = NumberSequence.new(0.25, 1)
                pe.Lifetime = NumberRange.new(0.8, 1.4)
                pe.Rate = 90
                pe.Speed = NumberRange.new(4, 9)
                pe.SpreadAngle = Vector2.new(35, 35)
                pe.Enabled = false
                pe.Parent = wakeAt
                s.wake = pe
            end
        end
        local f = ReplicatedStorage:FindFirstChild("HC_GetawayProps")
        local ov = f and f:FindFirstChild("RealBoat")
        local real = ov and ov:IsA("ObjectValue") and ov.Value
        if real then
            for _, d in ipairs(real:GetDescendants()) do
                if d:IsA("BasePart") then table.insert(s.hiddenParts, d) end
            end
        end
    end
    if tracks.heli then
        local m = template("Helicopter")
        if m then
            m:PivotTo(CFrame.new())
            local main, tail = m:FindFirstChild("MainRotor"), m:FindFirstChild("TailRotor")
            s.rotors = {
                main = main, mainLocal = main and main:GetPivot() or nil,
                tail = tail, tailLocal = tail and tail:GetPivot() or nil,
            }
            m:PivotTo(FAR)
            m.Parent = folder
            s.models.heli = m
        end
    end

    -- seat spots in the boat / helicopter (Attachment "Seat1".."Seat4" on the Root, root = origin)
    local function seatSpots(m)
        local list = {}
        local root = m and m.PrimaryPart
        for i = 1, 4 do
            local a = root and root:FindFirstChild("Seat" .. i)
            list[i] = a and a:IsA("Attachment") and (CFrame.new(a.Position) * CFrame.new(0, 1.55, 0)) or CFrame.new(0, 3, 0)
        end
        return list
    end
    s.boatSeats = seatSpots(s.models.boat)
    s.heliSeats = seatSpots(s.models.heli)

    -- ── props ──
    for _, pr in ipairs(scene.props or {}) do
        local m = template(pr.kind)
        if m then
            m:PivotTo(pr.cf)
            m.Parent = folder
            local entry = { def = pr, model = m, pieces = {} }
            if pr.kind == "Shutter" then
                local door = m:FindFirstChild("Door")
                if door then entry.door = door entry.doorLocal = pr.cf:ToObjectSpace(door:GetPivot()) end
            elseif pr.kind == "Roadblock" then
                local rng = Random.new(tonumber(scene.seed) or 7)
                for _, child in ipairs(m:GetChildren()) do
                    if child ~= m.PrimaryPart and (child:IsA("Model") or child:IsA("BasePart")) then
                        table.insert(entry.pieces, {
                            inst = child, base = child:GetPivot(),
                            v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.6, 1), rng:NextNumber(-1, 1)),
                            spin = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-3, 3), rng:NextNumber(-4, 4)),
                            heavy = child.Name == "Cruiser",
                        })
                    end
                end
                s.roadblock = entry
            end
            table.insert(s.props, entry)
        end
    end

    -- ── sound: sirens (loud) / the radio (stealth) ──
    local function sound(id, vol, speed, looped)
        local snd = Instance.new("Sound")
        snd.SoundId = id
        snd.Volume = vol
        snd.PlaybackSpeed = speed or 1
        snd.Looped = looped ~= false
        snd.Parent = SoundService
        table.insert(s.sounds, snd)
        return snd
    end
    if scene.loud then s.siren = sound(Constants.SOUNDS.ALARM, 0.3, 1.3, true) end
    if scene.radio then
        s.radioSnd = sound(Constants.SOUNDS.LOBBY_AMBIENT, 0.45, 1, true)
        pcall(function() s.radioSnd:Play() end)
    end

    -- (unclip) ignore the scene's own copies + the hidden real car / crew / boat
    pcall(function()
        local ignore = { folder }
        if typeof(realCar) == "Instance" then table.insert(ignore, realCar) end
        for _, p in ipairs(crewList) do
            if typeof(p) == "Instance" and p:IsA("Player") and p.Character then table.insert(ignore, p.Character) end
        end
        local f = ReplicatedStorage:FindFirstChild("HC_GetawayProps")
        local ov = f and f:FindFirstChild("RealBoat")
        if ov and ov:IsA("ObjectValue") and ov.Value then table.insert(ignore, ov.Value) end
        s.overlap = OverlapParams.new()
        s.overlap.FilterType = Enum.RaycastFilterType.Exclude
        s.overlap.FilterDescendantsInstances = ignore
        s.rayParams = RaycastParams.new()
        s.rayParams.FilterType = Enum.RaycastFilterType.Exclude
        s.rayParams.FilterDescendantsInstances = ignore
    end)

    -- ── hide the HUD, take the camera, stop the controls ──
    for _, g in ipairs(localPlayer.PlayerGui:GetChildren()) do
        if g:IsA("ScreenGui") and not KEEP_GUIS[g.Name] and g.Enabled then
            g.Enabled = false
            table.insert(s.hiddenGuis, g)
        end
    end
    pcall(function()
        local ps = localPlayer:FindFirstChild("PlayerScripts")
        local pm = ps and ps:FindFirstChild("PlayerModule")
        if pm then
            local controls = require(pm):GetControls()
            controls:Disable()
            s.controls = controls
        end
    end)
    cam.CameraType = Enum.CameraType.Scriptable
    u.screen.Enabled = true
    u.black.BackgroundTransparency = 0
    TweenService:Create(u.black, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
    for _, b in ipairs(u.bars) do
        TweenService:Create(b, TweenInfo.new(0.5), { Size = UDim2.new(1, 0, 0.1, 0) }):Play()
    end
    u.skip.Visible = false
    u.stamp.Visible = false
    s.inputConn = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        local k = input.KeyCode
        if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonB then self:skip() end
    end)

    local token = s
    s.conn = RunService.RenderStepped:Connect(function(dt)
        if self._s ~= token then return end
        local ok, err = pcall(function() self:_frame(s, dt) end)
        if not ok then
            warn("[GetawayCinematic] frame:", err)
            self:stop()
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════════
-- one frame
-- ══════════════════════════════════════════════════════════════════════
local function pieceCF(pc, style, te, t, dir, right)
    local tau = t - te
    if tau <= 0 or style == nil then return pc.base end
    local up = Vector3.new(0, 1, 0)
    local isCone = pc.inst.Name == "Cone"
    -- fly: everything (tank) · bounce: cruiser shoved, the rest flies (armored)
    -- hop: cruiser bounces, cones scatter (monster) · none: only the cones get clipped (near miss)
    local flies = style == "fly" or (style == "bounce" and not pc.heavy) or ((style == "hop" or style == "none") and isCone)
    if flies then
        local power = (style == "fly") and 1 or (style == "bounce" and 0.7 or 0.35)
        if style == "fly" and pc.heavy then power = 0.55 end
        local v = (dir * (30 + 12 * pc.v.Z) + right * (16 * pc.v.X) + up * (22 * pc.v.Y)) * power
        local tt = math.min(tau, 3)
        local g = 70
        local off = v * tt + up * (-0.5 * g * tt * tt)
        -- land on the road: never below where it started
        if off.Y < 0 then
            local tLand = (2 * v.Y) / g
            local flatT = math.min(tt, tLand)
            off = Vector3.new(v.X * flatT, 0, v.Z * flatT)
            tt = flatT
        end
        local spin = pc.spin * math.min(tau, 1.2) * power
        return CFrame.new(off) * pc.base * CFrame.Angles(spin.X, spin.Y, spin.Z)
    elseif style == "bounce" and pc.heavy then
        -- the cruiser gets shoved aside and spins
        local e = 1 - (1 - math.clamp(tau / 0.8, 0, 1)) ^ 3
        local off = right * (11 * e) + dir * (6 * e) + up * (math.sin(math.clamp(tau / 0.5, 0, 1) * math.pi) * 1.4)
        return CFrame.new(off) * pc.base * CFrame.Angles(0, 1.3 * e, 0)
    elseif style == "hop" and pc.heavy then
        -- a monster truck lands next to it: a little bounce
        local k = math.clamp(tau / 0.4, 0, 1)
        return CFrame.new(0, -math.sin(k * math.pi) * 0.5, 0) * pc.base
    end
    return pc.base
end

function GetawayCinematic:_frame(s, dt)
    local u = self._u
    local scene = s.scene
    local cam = Workspace.CurrentCamera
    local t = os.clock() - s.t0 + s.offset
    s.t = t
    local D = s.duration
    local tracks = scene.tracks or {}

    -- hide the real car / crew / boat (every frame: the engine may reset the modifier)
    for _, p in ipairs(s.hiddenParts) do
        if p.Parent then p.LocalTransparencyModifier = 1 end
    end

    -- vehicles
    local poses = {}
    for name, m in pairs(s.models) do
        local cf = evalTrack(tracks[name], t)
        if name == "boat" and not cf and scene.boatCF then cf = scene.boatCF end
        poses[name] = cf
        m:PivotTo(cf or FAR)
    end
    -- helicopter rotors
    if s.rotors and poses.heli then
        local r = s.rotors
        local ang = t * 26
        if r.main and r.mainLocal then r.main:PivotTo(poses.heli * r.mainLocal * CFrame.Angles(0, ang, 0)) end
        if r.tail and r.tailLocal then r.tail:PivotTo(poses.heli * r.tailLocal * CFrame.Angles(ang * 1.6, 0, 0)) end
    end
    -- cop lights + the car's alarm glow
    local phase = math.floor(t * 5) % 2
    if phase ~= s.lightPhase then
        s.lightPhase = phase
        for _, name in ipairs({ "cop1", "cop2" }) do
            local m = s.models[name]
            if m then
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("BasePart") then
                        if d.Name == "LightRed" then d.Color = phase == 0 and RED or Color3.fromRGB(70, 14, 18)
                        elseif d.Name == "LightBlue" then d.Color = phase == 1 and BLUE or Color3.fromRGB(14, 22, 70) end
                    end
                end
            end
        end
        if s.roadblock then
            for _, d in ipairs(s.roadblock.model:GetDescendants()) do
                if d:IsA("BasePart") then
                    if d.Name == "LightRed" then d.Color = phase == 0 and RED or Color3.fromRGB(70, 14, 18)
                    elseif d.Name == "LightBlue" then d.Color = phase == 1 and BLUE or Color3.fromRGB(14, 22, 70) end
                end
            end
        end
        if scene.loud and s.models.car then
            for _, d in ipairs(s.models.car:GetDescendants()) do
                if d:IsA("BasePart") and d.Name == "Underglow" then d.Color = phase == 0 and RED or BLUE end
            end
        end
    end

    -- events (fire-once bookkeeping + continuous state)
    local nitroOn, fadeA, shake, sirens, stampText = false, 0, 0, false, nil
    local hopEv, smashEv = nil, nil
    for i, e in ipairs(scene.events or {}) do
        local te = e.t or 0
        if e.kind == "nitro" then
            if t >= te and t < te + (e.dur or 1.2) then nitroOn = true end
        elseif e.kind == "fade" then
            local half = (e.dur or 0.7) / 2
            local d = math.abs(t - te)
            if d < half then fadeA = math.max(fadeA, 1 - d / half) end
        elseif e.kind == "shake" then
            if t >= te and t < te + 0.6 then shake = math.max(shake, (e.power or 1) * (1 - (t - te) / 0.6)) end
        elseif e.kind == "sirens" then
            if t >= te then sirens = e.on == true end
        elseif e.kind == "stamp" then
            if t >= te then stampText = e.text end
        elseif e.kind == "hop" then
            hopEv = e
        elseif e.kind == "smash" then
            smashEv = e
        elseif e.kind == "wake" then
            if s.wake then s.wake.Enabled = t >= te end
        end
        if t >= te and not s.fired[i] then s.fired[i] = true end
    end
    if s.models.car and nitroOn ~= s.nitro then
        s.nitro = nitroOn
        for _, d in ipairs(s.models.car:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == "NitroFlame" then d.Transparency = nitroOn and 0 or 1 end
        end
    end
    if s.siren then
        if sirens and not s.siren.IsPlaying then pcall(function() s.siren:Play() end)
        elseif not sirens and s.siren.IsPlaying then s.siren:Stop() end
    end

    -- props
    for _, pr in ipairs(s.props) do
        local def = pr.def
        local visible = t >= (def.t0 or 0) and t <= (def.t1 or math.huge)
        if not visible then
            pr.model:PivotTo(FAR)
        elseif def.kind == "Shutter" then
            pr.model:PivotTo(def.cf)
            if pr.door then
                local k = smooth((t - (def.open0 or 0.3)) / math.max(0.1, (def.open1 or 1.3) - (def.open0 or 0.3)))
                pr.door:PivotTo(def.cf * CFrame.new(0, 8.6 * k, 0) * pr.doorLocal)
            end
        elseif def.kind == "Roadblock" then
            pr.model:PivotTo(def.cf)
            local style = smashEv and t >= smashEv.t and smashEv.style or nil
            local dir = smashEv and typeof(smashEv.dir) == "Vector3" and smashEv.dir or def.cf.LookVector
            local right = Vector3.new(-dir.Z, 0, dir.X)
            for _, pc in ipairs(pr.pieces) do
                pc.inst:PivotTo(pieceCF(pc, style, smashEv and smashEv.t or 0, t, dir, right))
            end
        end
    end

    -- crew: in the car, hopping, or in the boat / helicopter
    for i, c in ipairs(s.crew) do
        local carCF = poses.car
        local cf = carCF and carCF * c.offset or nil
        if hopEv and poses[hopEv.to] then
            local seats = hopEv.to == "boat" and s.boatSeats or s.heliSeats
            local seatCF = seats[((i - 1) % 4) + 1]
            local h0 = hopEv.t + (i - 1) * 0.15
            local dur = hopEv.dur or 1.2
            if t >= h0 then
                local target = poses[hopEv.to] * seatCF
                local k = (t - h0) / dur
                if k >= 1 then
                    cf = target
                else
                    local fromCar = evalTrack(tracks.car, h0)
                    local from = fromCar and fromCar * c.offset or target
                    local e = smooth(k)
                    cf = from:Lerp(target, e) + Vector3.new(0, math.sin(k * math.pi) * 4, 0)
                end
            end
        end
        c.model:PivotTo(cf or FAR)
    end

    -- camera
    local shots = scene.shots or {}
    local shot, idx = nil, nil
    for k, sh in ipairs(shots) do
        if t >= sh.t0 and t < sh.t1 then shot, idx = sh, k end
    end
    if not shot and #shots > 0 then shot, idx = shots[#shots], #shots end
    local dipA = 0
    if shot then
        local cut = s.lastShot ~= idx
        -- every cut after the first lands on a black frame and fades in
        if cut and s.lastShot ~= nil then s.dipFrom = t end
        s.lastShot = idx
        if s.dipFrom then dipA = 1 - math.clamp((t - s.dipFrom) / CUT_DIP, 0, 1) end
        local anchor = nil
        local su = smooth((t - shot.t0) / math.max(0.1, shot.t1 - shot.t0))
        if shot.t1 - shot.t0 > 12 then su = math.clamp((t - shot.t0) / 12, 0, 1) end   -- long holds drift slowly
        local want
        if shot.mode == "fixed" then
            want = shot.from:Lerp(shot.to or shot.from, su)
        elseif shot.mode == "look" then
            local pos = shot.a:Lerp(shot.b or shot.a, su)
            local tgt = poses[shot.target] or s.lastTarget
            if tgt then
                s.lastTarget = tgt
                local at = tgt.Position + Vector3.new(0, shot.lookUp or 1.5, 0)
                anchor = at
                if (at - pos).Magnitude > 0.1 then want = CFrame.lookAt(pos, at) end
            end
        elseif shot.mode == "chase" then
            local tgt = evalTrack(tracks[shot.target], t - 0.15) or poses[shot.target]
            if tgt then
                local base = flatCF(tgt)
                local off = shot.o1:Lerp(shot.o2 or shot.o1, su)
                want = CFrame.lookAt((base * CFrame.new(off)).Position, (base * CFrame.new(shot.look or Vector3.new(0, 2, -10))).Position)
                if not cut and s.camCF then
                    want = s.camCF:Lerp(want, 1 - math.exp(-(dt or 0.016) * 9))
                end
                anchor = tgt.Position + Vector3.new(0, 2, 0)
            end
        elseif shot.mode == "lookback" then
            -- ride along on the far side of the target from the focus, looking back
            -- through it at the focus (boat + wake in front, the skyline behind)
            local tgt = poses[shot.target] or s.lastTarget
            local focus = typeof(shot.focus) == "Vector3" and shot.focus or Vector3.zero
            if tgt then
                s.lastTarget = tgt
                local tp = tgt.Position
                local toF = Vector3.new(focus.X - tp.X, 0, focus.Z - tp.Z)
                toF = toF.Magnitude > 1 and toF.Unit or Vector3.new(0, 0, 1)
                local side = Vector3.new(-toF.Z, 0, toF.X)
                local camY = tonumber(shot.y) or (tp.Y + 8)
                local camP = Vector3.new(tp.X, camY, tp.Z) - toF * (shot.dist or 24) + side * (shot.side or 0)
                local at = Vector3.new(tp.X, 0, tp.Z) + toF * (shot.ahead or 70) + Vector3.new(0, shot.lookY or 6, 0)
                want = CFrame.lookAt(camP, at)
                if not cut and s.camCF then
                    want = s.camCF:Lerp(want, 1 - math.exp(-(dt or 0.016) * 3))
                end
                anchor = tp + Vector3.new(0, 2, 0)
            end
        end
        if want then
            want = unclip(s, want, anchor)
            s.camCF = want
            local shaken = want
            if shake > 0 then
                shaken = want * CFrame.new((math.noise(t * 25, 1) * 0.8) * shake, (math.noise(t * 25, 2) * 0.8) * shake, 0)
            end
            cam.CFrame = shaken
        end
        if shot.fov and cam.FieldOfView ~= shot.fov then cam.FieldOfView = shot.fov end
    end

    -- captions + radio chip
    local capText, capA, radioText = nil, 1, nil
    for _, c in ipairs(scene.captions or {}) do
        if t >= c.t and t < c.t + (c.dur or 2) then
            if string.sub(c.text or "", 1, 4) == "📻" then
                radioText = c.text
            else
                capText = c.text
                local into, left = t - c.t, c.t + (c.dur or 2) - t
                capA = 1 - math.clamp(math.min(into, left) / 0.25, 0, 1)
            end
        end
    end
    if capText then
        u.caption.Text = capText
        u.caption.TextTransparency = capA
        u.caption.TextStrokeTransparency = 0.3 + 0.7 * capA
    else
        u.caption.TextTransparency = 1
        u.caption.TextStrokeTransparency = 1
    end
    u.radio.Visible = radioText ~= nil
    if radioText then u.radioText.Text = radioText end
    if stampText and not s.stampShown then
        s.stampShown = true
        u.stamp.Text = stampText
        u.stamp.Visible = true
        u.stamp.TextSize = 170
        TweenService:Create(u.stamp, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 110 }):Play()
        task.delay(2.2, function() if u.stamp then u.stamp.Visible = false end end)
    end
    local blackA = math.max(fadeA, dipA)
    u.black.BackgroundTransparency = (blackA > 0) and (1 - blackA) or (t < 0.45 and u.black.BackgroundTransparency or 1)
    u.skip.Visible = t >= SKIP_AFTER and t < D - 0.5

    -- the end: hold the final shot under the payout, then hand the camera back
    if t >= D then
        if s.radioSnd and s.radioSnd.Volume > 0.2 then s.radioSnd.Volume = 0.2 end
        local open = localPlayer:GetAttribute("PayoutOpen") == true
        if open then s.payoutSeen = true end
        if (s.payoutSeen and not open) or (not s.payoutSeen and t >= D + s.hold) or t >= D + s.hold + 6 then
            self:stop()
        end
    end
end

function GetawayCinematic:start()
    if self._started then return end
    self._started = true
    self:_build()
    task.spawn(function()
        local f = ReplicatedStorage:WaitForChild("Remotes", 30)
        local remote = f and f:WaitForChild("Getaway", 60)
        if not remote then warn("[GetawayCinematic] no Getaway remote") return end
        remote.OnClientEvent:Connect(function(msg)
            if type(msg) ~= "table" then return end
            if msg.phase == "scene" then
                task.spawn(function()
                    local ok, err = pcall(function() self:play(msg) end)
                    if not ok then
                        warn("[GetawayCinematic] play failed:", err)
                        self:stop()
                    end
                end)
            elseif msg.phase == "cancel" then
                self:stop()
            end
        end)
    end)
    -- never leave anyone stuck in a movie after respawning
    localPlayer.CharacterAdded:Connect(function()
        local s = self._s
        if s and s.t >= s.duration then self:stop() end
    end)
    print("[HEIST CREW] GetawayCinematic mounted ✅")
end

return GetawayCinematic
