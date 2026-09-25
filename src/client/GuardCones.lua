--[[
    HEIST CREW — GuardCones  (v3.1)
    ────────────────────────────────────────────────
    The #1 fairness feature: every guard and every live security camera paints
    a soft see-through wedge on the FLOOR showing exactly where it can see you.
    If you're outside the patch, you're safe. Simple as that — a 7-year-old
    can read it.

      GUARDS (tag "Guard")
        • wedge = the real vision: Constants.GUARD_VISION_RANGE +
          GUARD_VISION_FOV_DEGREES, pointing where the guard's body faces
          (the same numbers GuardService:checkVision uses).
        • hugs the floor he stands on (ray straight down), and each edge ray
          is shortened where a wall blocks it — the cone never "sees" through walls.
        • colour = that guard's meter on ME (model attribute Sus_<UserId>,
          published by GuardService [HOOK: GuardCones]):
              calm        → teal
              "Huh?" 40%  → yellow (and it pulses)
              spotted     → red
          Chasing (alarm on) → red. Stunned (Muscle takedown) → no cone.
      CAMERAS (tag "SecurityCamera", part "Head")
        • the real 3D camera cone (SECURITY.CAMERA_RANGE / CAMERA_HALF_ANGLE)
          cut at body height and drawn on the floor — it follows the sweep.
        • red-ish; brighter + pulsing while that camera is filling on ME.
        • gone while the cameras are cut (model attribute Live = false,
          SecurityService [HOOK: GuardCones]; falls back to the SpotLight).

    Only shown during a heist (HeistState ACTIVE / ESCAPING), or when you're
    standing right by a guard / camera (walked into a job before the run
    started, or joined mid-run). Hidden in the getaway movie. Distance-culled.
    Police officers are tagged "Guard" too but get NO cone (no vision meter).

    Cheap: each triangle is two thin WedgeParts (CanCollide / CanQuery /
    CanTouch / CastShadow all off) in one client-only folder, moved with
    workspace:BulkMoveTo every frame. Floor + wall rays run ~12x a second.

    Tuning knobs are the UPPER_CASE locals below.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local GuardCones = {}
local localPlayer = Players.LocalPlayer

-- ── tuning ─────────────────────────────────────────────────────────────
local GUARD_SEGMENTS = 10          -- fan slices per guard cone
local CAM_SEGMENTS = 14            -- outline points per camera footprint
local FILL_ALPHA = 0.74             -- calm fill transparency (spec ~0.75, a touch softer)
local FILL_ALPHA_HOT = 0.55         -- fill transparency at full suspicion
local RIM_ALPHA = 0.5              -- the brighter arc at the far edge
local RIM_WIDTH = 0.18
local LIFT = 0.07                  -- studs above the floor (no z-fighting)
local THICK = 0.04                 -- slab thickness
local MATERIAL = Enum.Material.Neon   -- self-lit so it reads in the dark rooms; high transparency keeps it subtle
local BODY_H = 3                   -- detection is measured at the torso (HumanoidRootPart) height above the floor
local RAY_HZ = 12                  -- floor/wall ray refreshes per second per guard
local CULL = 150                   -- hide cones further than this from the camera
local NEAR_SHOW = Constants.GUARD_VISION_RANGE + 18   -- out-of-heist: show a guard only this close

local C_CALM  = Color3.fromRGB(64, 224, 208)    -- teal
local C_HUH   = Color3.fromRGB(252, 206, 60)    -- "Huh?" yellow
local C_SPOT  = Color3.fromRGB(248, 70, 70)     -- spotted / chasing
local C_CAM   = Color3.fromRGB(255, 92, 92)     -- camera red-ish
local C_CAM_HOT = Color3.fromRGB(255, 40, 40)

local NOTICE_AT = 0.4

-- ── state ──────────────────────────────────────────────────────────────
local folder = nil
local heistOn = false
local cones = {}        -- [Model] = cone
GuardCones._cones = cones   -- (read-only peek for tests)

local function newPart(class, parent)
    local p = Instance.new(class)
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.CastShadow = false
    p.Massless = true
    p.Locked = true
    p.Material = MATERIAL
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Size = Vector3.new(THICK, 0.1, 0.1)
    p.Transparency = 1
    p.Parent = parent
    return p
end

-- A triangle from two wedges (the classic Roblox 3D-triangle trick).
-- Writes the two CFrames into cfOut and sets sizes only when they change.
local function triangle(a, b, c, w1, w2, cfOut, idx)
    local ab, ac, bc = b - a, c - a, c - b
    local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
    if abd > acd and abd > bcd then
        c, a = a, c
    elseif acd > bcd and acd > abd then
        a, b = b, a
    end
    ab, ac, bc = b - a, c - a, c - b
    local n = ac:Cross(ab)
    if n.Magnitude < 1e-4 or bc.Magnitude < 1e-4 then
        -- degenerate (a ray shortened to ~0): park both pieces out of sight
        cfOut[idx] = CFrame.new(0, -500, 0)
        cfOut[idx + 1] = CFrame.new(0, -500, 0)
        return
    end
    local right = n.Unit
    local up = bc:Cross(right).Unit
    local back = bc.Unit
    local height = math.abs(ab:Dot(up))
    local s1 = Vector3.new(THICK, math.max(height, 0.01), math.max(math.abs(ab:Dot(back)), 0.01))
    local s2 = Vector3.new(THICK, math.max(height, 0.01), math.max(math.abs(ac:Dot(back)), 0.01))
    if (w1.Size - s1).Magnitude > 0.03 then w1.Size = s1 end
    if (w2.Size - s2).Magnitude > 0.03 then w2.Size = s2 end
    cfOut[idx] = CFrame.fromMatrix((a + b) / 2, right, up, back)
    cfOut[idx + 1] = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

local function makeCone(kind, model, nTris, nRim)
    local f = Instance.new("Folder")
    f.Name = kind .. "_" .. model.Name
    local cone = {
        kind = kind, model = model, folder = f, wedges = {}, rims = {}, parts = {}, cfs = {},
        dist = {}, floorY = nil, nextRay = 0, shown = false, color = nil, alpha = nil,
    }
    for i = 1, nTris * 2 do
        local w = newPart("WedgePart", f)
        w.Name = "Fill"
        cone.wedges[i] = w
        table.insert(cone.parts, w)
    end
    for i = 1, nRim do
        local r = newPart("Part", f)
        r.Name = "Rim"
        cone.rims[i] = r
        table.insert(cone.parts, r)
    end
    return cone
end

local function setLook(cone, color, alpha, rimAlpha)
    if cone.color == color and cone.alpha == alpha then return end
    cone.color, cone.alpha = color, alpha
    for _, w in ipairs(cone.wedges) do
        w.Color = color
        w.Transparency = alpha
    end
    for _, r in ipairs(cone.rims) do
        r.Color = color
        r.Transparency = rimAlpha
    end
end

local function show(cone, on)
    if cone.shown == on then return end
    cone.shown = on
    cone.folder.Parent = on and folder or nil
end

-- ── raycasts ───────────────────────────────────────────────────────────
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local rayBuiltAt = -1
local function params()
    local t = os.clock()
    if t - rayBuiltAt > 1 then
        rayBuiltAt = t
        local ex = { folder }
        for _, g in ipairs(CollectionService:GetTagged("Guard")) do table.insert(ex, g) end
        for _, b in ipairs(CollectionService:GetTagged("BotCrew")) do table.insert(ex, b) end
        for _, cam in ipairs(CollectionService:GetTagged("SecurityCamera")) do table.insert(ex, cam) end
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character then table.insert(ex, p.Character) end
        end
        rayParams.FilterDescendantsInstances = ex
    end
    return rayParams
end

-- floor directly under a point (only fairly flat surfaces count)
local function floorUnder(pos, depth)
    local hit = Workspace:Raycast(pos, Vector3.new(0, -(depth or 30), 0), params())
    if hit and hit.Normal.Y > 0.6 then return hit.Position.Y end
    return nil
end

-- ── guards ─────────────────────────────────────────────────────────────
local G_RANGE = Constants.GUARD_VISION_RANGE
local G_HALF = math.rad(Constants.GUARD_VISION_FOV_DEGREES / 2)

local function guardSus(model)
    local v = model:GetAttribute("Sus_" .. localPlayer.UserId)
    if type(v) == "number" then return v end
    return 0
end

local function guardColor(sus, chasing, t)
    if chasing or sus >= 0.95 then return C_SPOT, FILL_ALPHA_HOT end
    if sus < NOTICE_AT then
        local k = math.clamp(sus / NOTICE_AT, 0, 1)
        return C_CALM:Lerp(C_HUH, k), FILL_ALPHA - (FILL_ALPHA - FILL_ALPHA_HOT) * k * 0.5
    end
    local k = math.clamp((sus - NOTICE_AT) / (1 - NOTICE_AT), 0, 1)
    local pulse = 0.5 + 0.5 * math.sin(t * 10)
    local col = C_HUH:Lerp(C_SPOT, k)
    return col, FILL_ALPHA_HOT + 0.08 * pulse * (1 - k)
end

local function updateGuard(cone, now, camPos, myRoot)
    local model = cone.model
    -- police officers are tagged "Guard" too (Lookout marks etc.) but have no
    -- vision meter — only GuardService guards (folder "Guards", or the hook's
    -- Chasing attribute) get a cone
    if not ((model.Parent and model.Parent.Name == "Guards") or model:GetAttribute("Chasing") ~= nil) then
        show(cone, false)
        return
    end
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    local head = model:FindFirstChild("Head") or root
    if not root or not head then show(cone, false) return end

    local stunned = model:GetAttribute("Stunned") == true
    if not stunned then
        local light = head:FindFirstChildOfClass("SpotLight")
        if light and not light.Enabled then stunned = true end   -- (fallback: stun disables his flashlight)
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if stunned or (hum and hum.Health <= 0) then show(cone, false) return end

    local rp = root.Position
    if (rp - camPos).Magnitude > CULL then show(cone, false) return end
    if not heistOn then
        if not myRoot or (myRoot.Position - rp).Magnitude > NEAR_SHOW then show(cone, false) return end
    end

    local look = root.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 1e-3 then show(cone, false) return end
    flat = flat.Unit

    -- rays (throttled): floor under him + one wall ray per fan edge
    if now >= cone.nextRay or not cone.floorY then
        cone.nextRay = now + 1 / RAY_HZ
        local fy = floorUnder(rp + Vector3.new(0, 1, 0), 12)
        if fy then cone.floorY = fy elseif not cone.floorY then cone.floorY = rp.Y - 3 end
        local bodyY = cone.floorY + BODY_H
        local eye = head.Position
        local dy = eye.Y - bodyY
        local reach = math.sqrt(math.max(G_RANGE * G_RANGE - dy * dy, 1))
        cone.reach = reach
        for i = 0, GUARD_SEGMENTS do
            local a = -G_HALF + (2 * G_HALF) * (i / GUARD_SEGMENTS)
            local dir = (CFrame.fromAxisAngle(Vector3.yAxis, a) * flat)
            local target = Vector3.new(rp.X, bodyY, rp.Z) + dir * reach
            local hit = Workspace:Raycast(eye, target - eye, params())
            local d = reach
            if hit then
                local hp = hit.Position
                d = math.clamp(Vector3.new(hp.X - rp.X, 0, hp.Z - rp.Z).Magnitude, 0.3, reach)
            end
            cone.dist[i] = d
        end
    end

    -- pose (every frame, follows him smoothly)
    local y = cone.floorY + LIFT
    local apex = Vector3.new(rp.X, y, rp.Z)
    local pts = {}
    for i = 0, GUARD_SEGMENTS do
        local a = -G_HALF + (2 * G_HALF) * (i / GUARD_SEGMENTS)
        local dir = (CFrame.fromAxisAngle(Vector3.yAxis, a) * flat)
        pts[i] = apex + dir * (cone.dist[i] or cone.reach or G_RANGE)
    end
    local cfs = cone.cfs
    for i = 1, GUARD_SEGMENTS do
        triangle(apex, pts[i - 1], pts[i], cone.wedges[i * 2 - 1], cone.wedges[i * 2], cfs, i * 2 - 1)
    end
    local n = GUARD_SEGMENTS * 2
    for i = 1, GUARD_SEGMENTS do
        local p0, p1 = pts[i - 1], pts[i]
        local len = (p1 - p0).Magnitude
        local r = cone.rims[i]
        local sz = Vector3.new(RIM_WIDTH, THICK * 1.5, math.max(len, 0.05))
        if (r.Size - sz).Magnitude > 0.03 then r.Size = sz end
        cfs[n + i] = (len > 1e-3) and CFrame.lookAt((p0 + p1) / 2 + Vector3.new(0, 0.01, 0), p1 + Vector3.new(0, 0.01, 0))
            or CFrame.new(0, -500, 0)
    end

    local col, alpha = guardColor(guardSus(model), model:GetAttribute("Chasing") == true, now)
    setLook(cone, col, alpha, math.max(0.2, alpha - 0.3))
    show(cone, true)
    return true
end

-- ── cameras ────────────────────────────────────────────────────────────
local S = Constants.SECURITY or {}
local C_RANGE = S.CAMERA_RANGE or 32
local C_HALF = math.rad(S.CAMERA_HALF_ANGLE or 24)

local function camLive(model, head)
    local live = model:GetAttribute("Live")
    if live == false then return false end
    local light = head:FindFirstChildOfClass("SpotLight")
    if light and not light.Enabled then return false end
    return live == true or light ~= nil
end

local function updateCamera(cone, now, camPos, myRoot)
    local model = cone.model
    local head = model:FindFirstChild("Head")
    if not head or not camLive(model, head) then show(cone, false) return end
    local hp = head.Position
    if (hp - camPos).Magnitude > CULL then show(cone, false) return end
    if not heistOn then
        if not myRoot or (myRoot.Position - hp).Magnitude > C_RANGE + 12 then show(cone, false) return end
    end

    local cf = head.CFrame
    local L = cf.LookVector
    -- floor under where it looks (throttled)
    if now >= cone.nextRay or not cone.floorY then
        cone.nextRay = now + 1
        local flatL = Vector3.new(L.X, 0, L.Z)
        local probe = hp + (flatL.Magnitude > 1e-3 and flatL.Unit * 3 or Vector3.zero)
        cone.floorY = floorUnder(probe, 40) or cone.floorY or (hp.Y - 12)
    end
    local bodyY = cone.floorY + BODY_H
    local y = cone.floorY + LIFT

    -- the boundary of the 3D cone, cut at body height, capped at the range
    local U, R = cf.UpVector, cf.RightVector
    local pts, cx, cz = {}, 0, 0
    local cosH, sinH = math.cos(C_HALF), math.sin(C_HALF)
    for i = 1, CAM_SEGMENTS do
        local phi = (i - 1) / CAM_SEGMENTS * math.pi * 2
        local d = L * cosH + (U * math.cos(phi) + R * math.sin(phi)) * sinH
        local t = C_RANGE
        if d.Y < -1e-3 then t = math.min(C_RANGE, (bodyY - hp.Y) / d.Y) end
        if t < 0 then t = C_RANGE end
        local p = hp + d * t
        pts[i] = Vector3.new(p.X, y, p.Z)
        cx, cz = cx + p.X, cz + p.Z
    end
    local centre = Vector3.new(cx / CAM_SEGMENTS, y, cz / CAM_SEGMENTS)

    local cfs = cone.cfs
    for i = 1, CAM_SEGMENTS do
        local a, b = pts[i], pts[i % CAM_SEGMENTS + 1]
        triangle(centre, a, b, cone.wedges[i * 2 - 1], cone.wedges[i * 2], cfs, i * 2 - 1)
    end
    local n = CAM_SEGMENTS * 2
    for i = 1, CAM_SEGMENTS do
        local p0, p1 = pts[i], pts[i % CAM_SEGMENTS + 1]
        local len = (p1 - p0).Magnitude
        local r = cone.rims[i]
        local sz = Vector3.new(RIM_WIDTH, THICK * 1.5, math.max(len, 0.05))
        if (r.Size - sz).Magnitude > 0.03 then r.Size = sz end
        cfs[n + i] = (len > 1e-3) and CFrame.lookAt((p0 + p1) / 2 + Vector3.new(0, 0.01, 0), p1 + Vector3.new(0, 0.01, 0))
            or CFrame.new(0, -500, 0)
    end

    -- hot while THIS camera is filling on me
    local hot = 0
    local cs = localPlayer:GetAttribute("CameraSuspicion") or 0
    local from = localPlayer:GetAttribute("CameraFrom")
    if cs > 0.02 and typeof(from) == "Vector3" and (from - hp).Magnitude < 2 then hot = cs end
    local pulse = 0.5 + 0.5 * math.sin(now * 10)
    local col = C_CAM:Lerp(C_CAM_HOT, hot)
    local alpha = FILL_ALPHA - (FILL_ALPHA - FILL_ALPHA_HOT) * hot - (hot > 0 and 0.06 * pulse or 0)
    setLook(cone, col, alpha, math.max(0.2, alpha - 0.3))
    show(cone, true)
    return true
end

-- ── registry ───────────────────────────────────────────────────────────
local function addGuard(model)
    if cones[model] or not model:IsA("Model") then return end
    cones[model] = makeCone("Guard", model, GUARD_SEGMENTS, GUARD_SEGMENTS)
end
local function addCamera(model)
    if cones[model] or not model:IsA("Model") then return end
    cones[model] = makeCone("Camera", model, CAM_SEGMENTS, CAM_SEGMENTS)
end
local function remove(model)
    local c = cones[model]
    if c then
        cones[model] = nil
        c.folder:Destroy()
    end
end

function GuardCones:setEnabled(on)   -- (for other modules / testing)
    heistOn = on == true
end

function GuardCones:start()
    if self._started then return end
    self._started = true

    local old = Workspace:FindFirstChild("HC_VisionCones")
    if old then old:Destroy() end
    folder = Instance.new("Folder")
    folder.Name = "HC_VisionCones"
    folder.Parent = Workspace

    for _, m in ipairs(CollectionService:GetTagged("Guard")) do addGuard(m) end
    for _, m in ipairs(CollectionService:GetTagged("SecurityCamera")) do addCamera(m) end
    CollectionService:GetInstanceAddedSignal("Guard"):Connect(addGuard)
    CollectionService:GetInstanceRemovedSignal("Guard"):Connect(remove)
    CollectionService:GetInstanceAddedSignal("SecurityCamera"):Connect(addCamera)
    CollectionService:GetInstanceRemovedSignal("SecurityCamera"):Connect(remove)

    -- heist on/off
    task.spawn(function()
        local ok, err = pcall(function()
            Remotes.getRemote(Remotes.NAMES.HeistState, "RemoteEvent").OnClientEvent:Connect(function(state)
                heistOn = (state == "ACTIVE" or state == "ESCAPING")
            end)
            Remotes.getRemote(Remotes.NAMES.AlarmTriggered, "RemoteEvent").OnClientEvent:Connect(function(active)
                if active then heistOn = true end   -- (joined mid-run: the server re-sends the alarm)
            end)
        end)
        if not ok then warn("[GuardCones] remotes:", err) end
    end)

    local parts, cfs = {}, {}
    RunService.RenderStepped:Connect(function()
        local ok, err = pcall(function()
            local now = os.clock()
            local cam = Workspace.CurrentCamera
            local camPos = cam and cam.CFrame.Position or Vector3.zero
            local char = localPlayer.Character
            local myRoot = char and char:FindFirstChild("HumanoidRootPart")
            local movie = localPlayer:GetAttribute("GetawayPlaying") == true
            table.clear(parts)
            table.clear(cfs)
            for model, cone in pairs(cones) do
                if not model.Parent then
                    remove(model)
                elseif movie then
                    show(cone, false)
                else
                    local drew
                    if cone.kind == "Guard" then
                        drew = updateGuard(cone, now, camPos, myRoot)
                    else
                        drew = updateCamera(cone, now, camPos, myRoot)
                    end
                    if drew then
                        for i, p in ipairs(cone.parts) do
                            local c = cone.cfs[i]
                            if c then
                                table.insert(parts, p)
                                table.insert(cfs, c)
                            end
                        end
                    end
                end
            end
            if #parts > 0 then
                Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
            end
        end)
        if not ok and not self._warned then
            self._warned = true
            warn("[GuardCones] update failed:", err)
        end
    end)
    print("[HEIST CREW] GuardCones mounted ✅")
end

return GuardCones
