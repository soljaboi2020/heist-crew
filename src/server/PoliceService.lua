--[[
    HEIST CREW — PoliceService
    ────────────────────────────────────────────────
    v1.0 "Neon Miami" (2026-09-25). Cruisers + cops.

      dispatch(stopPos, getCrewPlayers)
          Two black-and-white cruisers roll in from the street ends
          (Constants.WORLD.POLICE_SPAWNS), sirens on, lights flashing, drive
          along their lane and park either side of stopPos. When a cruiser
          parks, one cop gets out and hunts the nearest crew member on foot
          (PathfindingService, water is off-limits). Touching a cop = caught.

      chaseCar(car)
          The cruisers switch to pursuing the getaway car (spawning them first
          if needed). Top speed 52 — a hair under the car's 55, so a clean
          driver pulls away and nitro always escapes. A BustMeter (0..1) on the
          car model fills while a cruiser is within 10 studs AND the car is
          doing < 25; at 1 → onCarBusted(car), once.

      Cruisers are KINEMATIC like the getaway car (anchored, moved every
      Heartbeat) and use VehicleService.Kinematic for ground-follow and
      obstacle probes, so they don't drive through buildings or into the sea.
      A cruiser stuck for > 2s is teleported to a clear spot behind the car
      (or, before a chase, straight to its parking spot).

    TAGS: each cop model is tagged "Guard" (so Lookout / thermal / marks see
    them). Cruiser models are tagged "PoliceCruiser" — NOT "Guard".

    PUBLIC API:
        PoliceService:init(callbacks)
            callbacks.onPlayerCaught(player, copModel)
            callbacks.onCarBusted(car)
        PoliceService:dispatch(stopPos: Vector3, getCrewPlayers: () -> {Player})
        PoliceService:chaseCar(car)
        PoliceService:recall()
        PoliceService:isActive() -> boolean
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local VehicleService = require(script.Parent.VehicleService)
local NpcFactory = require(script.Parent.NpcFactory)

local Kin = VehicleService.Kinematic
local Build = VehicleService.Build
local BOUNDS = VehicleService.BOUNDS

local PoliceService = {}

local W = Constants.WORLD
local STREET_Z = W.STREET_Z

local TUNE = {
    ROUTE_SPEED   = 45,
    CHASE_SPEED   = 52,
    ACCEL         = 30,
    BRAKE         = 60,
    TURN_RATE     = 2.2,     -- rad/s at speed
    PARK_OFFSET_X = 7,
    PARK_OFFSET_Z = 2.5,
    STUCK_TIME    = 2,
    BUST_RANGE    = 10,      -- gap between the two car bodies, studs
    BUST_MAX_CAR_SPEED = 25,
    BUST_FILL     = 0.33,    -- per second
    BUST_DRAIN    = 0.25,
    TELEPORT_BACK = 45,
    COP_SPEED     = 17,
    COP_REPLAN    = 0.6,
    CATCH_COOLDOWN = 2,
}
PoliceService.TUNE = TUNE

local CRUISER_HALF_LEN = 5.9
local CRUISER_WIDTH = 4.8

local COP_SPEC = {
    name = "Cop",
    outfitId = 320998366,   -- official Roblox "Police Officer Nash"
    bodyColors = {
        head  = Color3.fromRGB(204, 142, 105),
        torso = Color3.fromRGB(27, 42, 53),
        arms  = Color3.fromRGB(27, 42, 53),
        legs  = Color3.fromRGB(17, 17, 17),
    },
}

local callbacks = {}
local cruisers = {}         -- list of cruiser tables
local cops = {}             -- list of cop tables
local folder = nil
local getCrew = function() return {} end
local chaseTarget = nil     -- the car object being chased
local bustFired = false
local generation = 0        -- bumped by recall(); async work from an old dispatch bails
local caughtUntil = {}      -- [Player] = os.clock() when they can be caught again
local initialized = false

-- ──────────────────────────────────────────────
-- utils
-- ──────────────────────────────────────────────
local function fire(fn, ...)
    if type(fn) ~= "function" then return end
    local args = table.pack(...)
    task.spawn(function()
        local ok, err = pcall(fn, table.unpack(args, 1, args.n))
        if not ok then warn("[PoliceService] callback error:", err) end
    end)
end

local function flat(v)
    return Vector3.new(v.X, 0, v.Z)
end

local function wrapAngle(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

local function crewList()
    local ok, list = pcall(getCrew)
    if ok and type(list) == "table" then return list end
    return {}
end

local function isCrew(player)
    for _, p in ipairs(crewList()) do
        if p == player then return true end
    end
    return false
end

local function carValid(car)
    return car ~= nil and not car.destroyed and car.model ~= nil and car.model.Parent ~= nil
end

-- Half-extent of an oriented box (vehicle footprint) along a flat unit direction
local function extentAlong(u, look, halfLen, halfWidth)
    local right = Vector3.new(-look.Z, 0, look.X)
    return math.abs(u:Dot(look)) * halfLen + math.abs(u:Dot(right)) * halfWidth
end

-- Gap between two vehicle footprints (approximate, good enough for "within 10 studs")
local function gapBetween(posA, lookA, halfLenA, widthA, posB, lookB, halfLenB, widthB)
    local d = flat(posB - posA)
    local dist = d.Magnitude
    if dist < 1e-3 then return 0 end
    local u = d / dist
    local ea = extentAlong(u, flat(lookA), halfLenA, widthA / 2)
    local eb = extentAlong(u, flat(lookB), halfLenB, widthB / 2)
    return math.max(0, dist - ea - eb)
end

local function ensureFolder()
    if folder and folder.Parent then return folder end
    folder = Instance.new("Folder")
    folder.Name = "Police"
    folder.Parent = Workspace
    return folder
end

-- ──────────────────────────────────────────────
-- Cruiser model (local coords: origin = ground under centre, front = -Z)
-- ──────────────────────────────────────────────
local BLACK  = Color3.fromRGB(16, 17, 20)
local WHITE  = Color3.fromRGB(240, 240, 236)
local TRIM   = Color3.fromRGB(52, 54, 60)
local RED    = Color3.fromRGB(255, 40, 50)
local BLUE   = Color3.fromRGB(40, 90, 255)
local RED_DIM  = Color3.fromRGB(70, 14, 18)
local BLUE_DIM = Color3.fromRGB(14, 22, 70)

local PAINT = { Reflectance = 0.1 }
local DECOR = { CanCollide = false, CanTouch = false }

local function doorText(part, face)
    local g = Instance.new("SurfaceGui")
    g.Face = face
    g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    g.PixelsPerStud = 50
    g.LightInfluence = 0.6
    g.Parent = part
    local l = UITheme.label({
        Text = "POLICE",
        Size = UDim2.fromScale(1, 1),
        FontFace = UITheme.F.display,
        TextScaled = true,
        TextColor3 = BLACK,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0.08, 0)
    pad.PaddingRight = UDim.new(0.08, 0)
    pad.PaddingTop = UDim.new(0.18, 0)
    pad.PaddingBottom = UDim.new(0.18, 0)
    pad.Parent = l
    l.Parent = g
end

local function buildCruiserModel(index)
    local model = Instance.new("Model")
    model.Name = "PoliceCruiser" .. index
    local B = Build

    local root = B.part({
        Name = "Root", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(),
        Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false,
    }, model)
    model.PrimaryPart = root

    -- body: black with white doors + white roof (the classic black-and-white)
    B.box(model, "Body", -2.35, 0.75, -5.6, 2.35, 1.95, 5.6, BLACK, Enum.Material.SmoothPlastic, PAINT)
    B.box(model, "Cabin", -2.1, 1.95, -1.8, 2.1, 3.3, 2.5, BLACK, Enum.Material.Glass, { Transparency = 0.15, Reflectance = 0.3 })
    B.box(model, "Roof", -2.15, 3.3, -1.5, 2.15, 3.45, 2.2, WHITE, Enum.Material.SmoothPlastic, PAINT)
    local doorL = B.box(model, "DoorL", -2.42, 0.95, -1.6, -2.35, 1.9, 2.4, WHITE, Enum.Material.SmoothPlastic, DECOR)
    local doorR = B.box(model, "DoorR", 2.35, 0.95, -1.6, 2.42, 1.9, 2.4, WHITE, Enum.Material.SmoothPlastic, DECOR)
    doorText(doorL, Enum.NormalId.Left)
    doorText(doorR, Enum.NormalId.Right)

    -- push bar, bumpers, lights
    B.box(model, "PushBar", -1.4, 0.8, -5.95, 1.4, 1.75, -5.6, TRIM, Enum.Material.Metal)
    B.box(model, "BumperR", -2.35, 0.6, 5.6, 2.35, 1.0, 5.8, TRIM, Enum.Material.Metal)
    for _, s in ipairs({ -1, 1 }) do
        local a, b = s * 1.5, s * 2.2
        B.box(model, "Headlight", math.min(a, b), 1.4, -5.66, math.max(a, b), 1.7, -5.6,
            Color3.fromRGB(255, 248, 225), Enum.Material.Neon, DECOR)
        B.box(model, "Taillight", math.min(a, b), 1.4, 5.6, math.max(a, b), 1.7, 5.66, RED, Enum.Material.Neon, DECOR)
    end

    -- light bar: two red segments on the left, two blue on the right
    B.box(model, "LightBarBase", -1.7, 3.45, -0.25, 1.7, 3.6, 0.45, TRIM, Enum.Material.Metal)
    local reds, blues = {}, {}
    for i = 0, 3 do
        local x0 = -1.6 + i * 0.8
        local isRed = i < 2
        local seg = B.box(model, isRed and "LightRed" or "LightBlue", x0 + 0.03, 3.6, -0.15, x0 + 0.77, 3.9, 0.35,
            isRed and RED or BLUE, Enum.Material.Neon, DECOR)
        table.insert(isRed and reds or blues, seg)
    end
    local redLight = Instance.new("PointLight")
    redLight.Color = RED
    redLight.Range = 18
    redLight.Brightness = 3
    redLight.Shadows = false
    redLight.Parent = reds[1]
    local blueLight = Instance.new("PointLight")
    blueLight.Color = BLUE
    blueLight.Range = 18
    blueLight.Brightness = 3
    blueLight.Shadows = false
    blueLight.Parent = blues[#blues]

    for _, s in ipairs({ -1, 1 }) do
        Build.wheel(model, s * 2.25, -3.6, 1.05, 0.8)
        Build.wheel(model, s * 2.25, 3.6, 1.05, 0.8)
    end

    local siren = Instance.new("Sound")
    siren.Name = "Siren"
    siren.SoundId = Constants.SOUNDS.ALARM
    siren.Looped = true
    siren.Volume = 0.4
    siren.PlaybackSpeed = 1.3
    siren.RollOffMode = Enum.RollOffMode.InverseTapered
    siren.RollOffMinDistance = 15
    siren.RollOffMaxDistance = 150
    siren.Parent = root

    CollectionService:AddTag(model, "PoliceCruiser")
    return {
        model = model, root = root, reds = reds, blues = blues,
        redLight = redLight, blueLight = blueLight, siren = siren,
    }
end

-- ──────────────────────────────────────────────
-- Cruiser placement + movement
-- ──────────────────────────────────────────────
local function cruiserCFrame(cr)
    return CFrame.new(cr.pos) * CFrame.Angles(0, cr.yaw, 0)
end

local function placeCruiser(cr, pos, yaw)
    local groundEx = Kin.filters(cr.model)
    local y = Kin.groundAt(pos.X, pos.Z, pos.Y + 8, groundEx)
    cr.pos = Vector3.new(pos.X, y or pos.Y, pos.Z)
    cr.yaw = yaw
    cr.stuckT = 0
    cr.model:PivotTo(cruiserCFrame(cr))
end

-- Is there room for a cruiser at pos (street level, dry, nothing solid)?
local function spotIsClear(pos, yaw, ownModel)
    if pos.X < BOUNDS.x0 + 4 or pos.X > BOUNDS.x1 - 4 or pos.Z < BOUNDS.z0 + 4 or pos.Z > BOUNDS.z1 - 4 then
        return nil
    end
    local groundEx = Kin.filters(ownModel)
    local y = Kin.groundAt(pos.X, pos.Z, 30, groundEx)
    if not y or math.abs(y) > 3 then return nil end   -- roof, pit, or water

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = groundEx
    params.RespectCanCollide = true
    local cf = CFrame.new(pos.X, y + 2.3, pos.Z) * CFrame.Angles(0, yaw, 0)
    local ok, hits = pcall(function()
        return Workspace:GetPartBoundsInBox(cf, Vector3.new(CRUISER_WIDTH + 0.6, 3, CRUISER_HALF_LEN * 2 + 1), params)
    end)
    if not ok then return nil end
    -- vehicles are in the exclude list for ground probes; re-check them here
    for _, v in ipairs(Kin.vehicles()) do
        if v ~= ownModel then
            local vp = v:GetPivot().Position
            if flat(vp - pos).Magnitude < 12 then return nil end
        end
    end
    for _, hit in ipairs(hits) do
        -- Terrain is a BasePart whose bounds cover the whole map; the ground
        -- probe above already vetted it, so only real parts count as blockers
        if not hit:IsA("Terrain") then return nil end
    end
    return Vector3.new(pos.X, y, pos.Z)
end

local spawnCop   -- forward declaration (defined in the Cops section below)

local function parkCruiser(cr)
    cr.mode = "parked"
    cr.v = 0
    if not cr.copSpawned then
        cr.copSpawned = true
        task.spawn(spawnCop, cr)
    end
end

-- Stuck before a chase: just put it where it was going.
local function snapToPark(cr)
    local base = cr.parkPos
    if not base then return end
    for _, dx in ipairs({ 0, -9, 9, -18, 18 }) do
        local p = spotIsClear(base + Vector3.new(dx, 0, 0), cr.parkYaw, cr.model)
        if p then
            placeCruiser(cr, p, cr.parkYaw)
            parkCruiser(cr)
            return
        end
    end
    -- nowhere clear: park where it stands rather than spin forever
    parkCruiser(cr)
end

-- Stuck (or hopelessly far) during a chase: reappear behind the car.
local function teleportBehind(cr, car)
    local cf = car.model:GetPivot()
    local fwd = flat(cf.LookVector)
    if fwd.Magnitude < 1e-3 then fwd = Vector3.new(1, 0, 0) end
    fwd = fwd.Unit
    local carPos = cf.Position
    local sx = fwd.X >= 0 and 1 or -1
    local candidates = {
        carPos - fwd * TUNE.TELEPORT_BACK,
        Vector3.new(math.clamp(carPos.X - sx * TUNE.TELEPORT_BACK, -140, 140), 0, STREET_Z - 4),
        Vector3.new(math.clamp(carPos.X - sx * TUNE.TELEPORT_BACK, -140, 140), 0, STREET_Z + 4),
        carPos - fwd * (TUNE.TELEPORT_BACK * 0.6),
    }
    for _, c in ipairs(candidates) do
        local toCar = flat(carPos - c)
        local yaw = toCar.Magnitude > 1e-3 and Kin.yawFromLook(toCar.Unit) or cr.yaw
        local p = spotIsClear(c, yaw, cr.model)
        if p then
            placeCruiser(cr, p, yaw)
            cr.v = math.min(25, TUNE.CHASE_SPEED)
            return true
        end
    end
    cr.stuckT = 0
    return false
end

-- Steer toward `target`, aiming for `targetSpeed`, then move one frame.
local function drive(cr, dt, target, targetSpeed, groundEx, obstacleEx)
    local to = flat(target - cr.pos)
    if to.Magnitude > 0.5 then
        local desired = Kin.yawFromLook(to.Unit)
        local err = wrapAngle(desired - cr.yaw)
        -- cars can't pivot on the spot, but a little low-speed authority keeps
        -- a cruiser from getting wedged forever
        local authority = math.clamp(math.abs(cr.v) / 10, 0.3, 1)
        local maxTurn = TUNE.TURN_RATE * authority * dt
        cr.yaw = cr.yaw + math.clamp(err, -maxTurn, maxTurn)
        -- slow down while pointing the wrong way
        targetSpeed = targetSpeed * math.clamp(math.cos(err), 0.25, 1)
    end
    local rate = targetSpeed > cr.v and TUNE.ACCEL or TUNE.BRAKE
    cr.v = Kin.approach(cr.v, targetSpeed, rate * dt)
    Kin.advance(cr, dt, groundEx, obstacleEx)
    cr.model:PivotTo(cruiserCFrame(cr))
end

local function stepRoute(cr, dt, groundEx, obstacleEx)
    local wp = cr.waypoints[cr.wpIndex]
    if not wp then
        parkCruiser(cr)
        return
    end
    local isLast = cr.wpIndex == #cr.waypoints
    local dist = flat(wp - cr.pos).Magnitude
    if dist < (isLast and 2 or 5) then
        if isLast then
            parkCruiser(cr)
            return
        end
        cr.wpIndex = cr.wpIndex + 1
        return
    end
    local speed = TUNE.ROUTE_SPEED
    if isLast then speed = math.min(speed, dist * 1.4 + 3) end
    drive(cr, dt, wp, speed, groundEx, obstacleEx)

    if speed > 5 and math.abs(cr.v) < 2 then
        cr.stuckT = cr.stuckT + dt
    else
        cr.stuckT = 0
    end
    if cr.stuckT > TUNE.STUCK_TIME then
        snapToPark(cr)
    end
end

local function stepChase(cr, dt, car, groundEx, obstacleEx)
    local cf = car.model:GetPivot()
    local carPos = cf.Position
    local carLook = cf.LookVector
    local carSpeed = car:getSpeed()
    local gap = gapBetween(cr.pos, cruiserCFrame(cr).LookVector, CRUISER_HALF_LEN, CRUISER_WIDTH,
        carPos, carLook, car.halfLen or 5.6, car.width or 4.7)

    -- aim a little ahead of the car so we cut it off instead of trailing it
    local lead = carPos + flat(carLook) * math.min(carSpeed * 0.4, 12)
    local speed = TUNE.CHASE_SPEED
    if gap < 12 then
        speed = math.clamp(carSpeed + (gap - 3) * 3, 0, TUNE.CHASE_SPEED)
    end
    drive(cr, dt, lead, speed, groundEx, obstacleEx)

    if gap > 15 and speed > 10 and math.abs(cr.v) < 3 then
        cr.stuckT = cr.stuckT + dt
    else
        cr.stuckT = 0
    end
    if (cr.stuckT > TUNE.STUCK_TIME or gap > 170) and os.clock() >= (cr.nextTeleport or 0) then
        cr.nextTeleport = os.clock() + 1   -- don't re-scan spots every frame if none are clear
        teleportBehind(cr, car)
    end
end

local function flashLights(cr)
    local phase = math.floor(os.clock() * 4 + cr.phaseOffset) % 2
    if phase == cr.lightPhase then return end
    cr.lightPhase = phase
    local redOn = phase == 0
    for _, p in ipairs(cr.reds) do p.Color = redOn and RED or RED_DIM end
    for _, p in ipairs(cr.blues) do p.Color = redOn and BLUE_DIM or BLUE end
    cr.redLight.Enabled = redOn
    cr.blueLight.Enabled = not redOn
end

local function newCruiser(index, spawnPos, yaw)
    local parts = buildCruiserModel(index)
    local cr = {
        index = index,
        model = parts.model,
        root = parts.root,
        reds = parts.reds,
        blues = parts.blues,
        redLight = parts.redLight,
        blueLight = parts.blueLight,
        siren = parts.siren,
        halfLen = CRUISER_HALF_LEN,
        width = CRUISER_WIDTH,
        pos = spawnPos,
        yaw = yaw,
        v = 0,
        mode = "idle",
        waypoints = {},
        wpIndex = 1,
        stuckT = 0,
        phaseOffset = (index - 1) * 0.5,
        lightPhase = -1,
        copSpawned = false,
    }
    placeCruiser(cr, spawnPos, yaw)
    cr.model.Parent = ensureFolder()
    pcall(function() cr.siren:Play() end)
    table.insert(cruisers, cr)
    return cr
end

local function spawnCruisers()
    local spawns = W.POLICE_SPAWNS or {}
    for i, sp in ipairs(spawns) do
        local pos = Vector3.new(sp.x, sp.y, sp.z)
        -- face along the street, toward the middle of the map
        local dir = sp.x < 0 and Vector3.new(1, 0, 0) or Vector3.new(-1, 0, 0)
        local cr = newCruiser(i, pos, Kin.yawFromLook(dir))
        cr.side = sp.x < 0 and -1 or 1
        cr.laneZ = sp.z
    end
end

-- ──────────────────────────────────────────────
-- Cops (on foot)
-- ──────────────────────────────────────────────
local function isWaterAt(pos)
    local groundEx = Kin.filters(nil)
    local y, reason = Kin.groundAt(pos.X, pos.Z, pos.Y + 6, groundEx)
    return y == nil and reason == "water"
end

local function nearestTarget(cop)
    local best, bestDist = nil, math.huge
    local from = cop.root.Position
    for _, p in ipairs(crewList()) do
        if typeof(p) == "Instance" and p:IsA("Player") then
            local char = p.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hum and hrp and hrp:IsA("BasePart") and hum.Health > 0 and hum.SeatPart == nil then
                local d = (hrp.Position - from).Magnitude
                if d < bestDist and not isWaterAt(hrp.Position) then
                    best, bestDist = hrp, d
                end
            end
        end
    end
    return best, bestDist
end

local function planPath(cop, targetPos)
    local path = PathfindingService:CreatePath({
        AgentRadius = 2, AgentHeight = 5, AgentCanJump = false,
        Costs = { Water = math.huge },
    })
    local ok = pcall(function() path:ComputeAsync(cop.root.Position, targetPos) end)
    if ok and path.Status == Enum.PathStatus.Success then
        local points = {}
        for i, wp in ipairs(path:GetWaypoints()) do
            if i > 1 then
                if isWaterAt(wp.Position) then break end   -- never step into the sea
                table.insert(points, wp.Position)
            end
        end
        if #points > 0 then return points end
    end
    return nil
end

local function runCopBrain(cop, gen)
    task.spawn(function()
        local lastPlan = -math.huge
        local lastIssue = 0
        while cop.alive and generation == gen and cop.model.Parent do
            local hum, root = cop.humanoid, cop.root
            if hum.Health <= 0 then break end

            if os.clock() - lastPlan >= TUNE.COP_REPLAN then
                lastPlan = os.clock()
                local target, dist = nearestTarget(cop)
                if target then
                    if dist < 12 then
                        cop.points = { target.Position }   -- close: just run at them
                    else
                        cop.points = planPath(cop, target.Position) or { target.Position }
                    end
                    cop.idx = 1
                    lastIssue = 0
                else
                    cop.points = nil
                    hum:MoveTo(root.Position)
                end
            end

            if isWaterAt(root.Position) and cop.home then
                cop.points = { cop.home }        -- somehow in the water: back to the car
                cop.idx = 1
            end

            local pts = cop.points
            if pts then
                local p = pts[cop.idx]
                while p and flat(p - root.Position).Magnitude < 2.5 do
                    cop.idx = cop.idx + 1
                    p = pts[cop.idx]
                    lastIssue = 0
                end
                if p and os.clock() - lastIssue > 1 then
                    hum:MoveTo(p)
                    lastIssue = os.clock()
                end
            end
            task.wait(0.1)
        end
    end)
end

function spawnCop(cr)
    local gen = generation
    local ok, model, humanoid, root = pcall(NpcFactory.build, table.clone(COP_SPEC))
    if not ok or not model or not humanoid or not root then
        warn("[PoliceService] could not build a cop:", ok and "nil model" or model)
        return
    end
    if generation ~= gen or not cr.model.Parent then
        model:Destroy()   -- recalled while the outfit was loading
        return
    end

    -- step out of the driver's door (left side)
    local cf = cr.model:GetPivot()
    local spot = (cf * CFrame.new(-(CRUISER_WIDTH / 2 + 2.2), 0, -1)).Position
    local y = Kin.groundAt(spot.X, spot.Z, spot.Y + 6, (Kin.filters(nil)))
    if y then spot = Vector3.new(spot.X, y, spot.Z) end
    model:PivotTo(CFrame.new(spot + Vector3.new(0, 3, 0)) * cf.Rotation)
    model.Parent = ensureFolder()
    CollectionService:AddTag(model, "Guard")
    pcall(function() root:SetNetworkOwner(nil) end)
    pcall(NpcFactory.animate, humanoid)
    humanoid.WalkSpeed = TUNE.COP_SPEED

    local cop = {
        model = model, humanoid = humanoid, root = root,
        alive = true, home = spot, points = nil, idx = 1, connections = {},
    }
    table.insert(cops, cop)

    local function onTouched(hit)
        if not cop.alive then return end
        local char = hit:FindFirstAncestorOfClass("Model")
        if not char or char == model then return end
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end
        local now = os.clock()
        if caughtUntil[player] and now < caughtUntil[player] then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 or hum.SeatPart ~= nil then return end
        if not isCrew(player) then return end
        caughtUntil[player] = now + TUNE.CATCH_COOLDOWN
        fire(callbacks.onPlayerCaught, player, model)
    end
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(cop.connections, part.Touched:Connect(onTouched))
        end
    end
    table.insert(cop.connections, humanoid.Died:Connect(function() cop.alive = false end))

    runCopBrain(cop, gen)
end

-- ──────────────────────────────────────────────
-- Heartbeat
-- ──────────────────────────────────────────────
local function updateBust(car, dt: number)
    if not carValid(car) then return end
    local cf = car.model:GetPivot()
    local near = false
    for _, cr in ipairs(cruisers) do
        local gap = gapBetween(cr.pos, cruiserCFrame(cr).LookVector, CRUISER_HALF_LEN, CRUISER_WIDTH,
            cf.Position, cf.LookVector, car.halfLen or 5.6, car.width or 4.7)
        if gap <= TUNE.BUST_RANGE then
            near = true
            break
        end
    end
    local meter = tonumber(car.model:GetAttribute("BustMeter")) or 0
    -- (fix v1.1: an EMPTY car can't be busted — the driver may be out loading bags)
    if near and car:getSpeed() < TUNE.BUST_MAX_CAR_SPEED and #car:getOccupants() > 0 then
        meter = meter + TUNE.BUST_FILL * dt
    else
        meter = meter - TUNE.BUST_DRAIN * dt
    end
    meter = math.clamp(meter, 0, 1)
    -- round so we don't replicate a new float every frame for nothing
    local shown = math.floor(meter * 200 + 0.5) / 200
    if car.model:GetAttribute("BustMeter") ~= shown then
        car.model:SetAttribute("BustMeter", shown)
    end
    if meter >= 1 and not bustFired then
        bustFired = true
        fire(callbacks.onCarBusted, car)
    end
end

local function step(dt)
    dt = math.min(dt, 0.1)
    if #cruisers == 0 then return end

    local car = chaseTarget
    if car and not carValid(car) then
        chaseTarget = nil
        car = nil
    end

    for i = #cruisers, 1, -1 do
        local cr = cruisers[i]
        if not cr.model.Parent then
            table.remove(cruisers, i)
        else
            flashLights(cr)
            local groundEx, obstacleEx = Kin.filters(cr.model)
            if cr.mode == "chase" and car then
                stepChase(cr, dt, car, groundEx, obstacleEx)
            elseif cr.mode == "route" then
                stepRoute(cr, dt, groundEx, obstacleEx)
            elseif math.abs(cr.v) > 0.05 then
                -- idle / parked / chase with no car: roll to a stop
                cr.v = Kin.approach(cr.v, 0, TUNE.BRAKE * dt)
                Kin.advance(cr, dt, groundEx, obstacleEx)
                cr.model:PivotTo(cruiserCFrame(cr))
            end
        end
    end

    if car then updateBust(car, dt) end
end

-- ──────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────
function PoliceService:init(cb)
    cb = cb or {}
    callbacks.onPlayerCaught = cb.onPlayerCaught
    callbacks.onCarBusted = cb.onCarBusted
    if initialized then return end
    initialized = true
    RunService.Heartbeat:Connect(step)
    Players.PlayerRemoving:Connect(function(p) caughtUntil[p] = nil end)
end

function PoliceService:dispatch(stopPos, getCrewPlayers)
    if type(getCrewPlayers) == "function" then getCrew = getCrewPlayers end
    if typeof(stopPos) ~= "Vector3" then
        stopPos = Vector3.new(W.GETAWAY_POSITION.x, 0, STREET_Z)
    end
    if #cruisers > 0 then return end   -- already rolling; crew getter updated above

    spawnCruisers()
    for _, cr in ipairs(cruisers) do
        local side = cr.side or (cr.pos.X < stopPos.X and -1 or 1)
        local laneZ = cr.laneZ or STREET_Z
        local park = Vector3.new(stopPos.X + side * TUNE.PARK_OFFSET_X, 0,
            stopPos.Z + (side < 0 and TUNE.PARK_OFFSET_Z or -TUNE.PARK_OFFSET_Z))
        local approachPt = Vector3.new(park.X + side * 12, 0, laneZ)
        cr.parkPos = park
        -- parked facing the way it drove in
        local inDir = flat(park - approachPt)
        cr.parkYaw = inDir.Magnitude > 1e-3 and Kin.yawFromLook(inDir.Unit) or cr.yaw
        cr.waypoints = { approachPt, park }
        cr.wpIndex = 1
        cr.mode = "route"
    end
end

function PoliceService:chaseCar(car)
    if not carValid(car) then return end
    if chaseTarget ~= car then
        bustFired = false
        car.model:SetAttribute("BustMeter", 0)
    end
    chaseTarget = car
    if #cruisers == 0 then spawnCruisers() end
    for _, cr in ipairs(cruisers) do
        cr.mode = "chase"
        cr.stuckT = 0
    end
end

function PoliceService:recall()
    generation = generation + 1
    for _, cr in ipairs(cruisers) do
        pcall(function() cr.siren:Stop() end)
        cr.model:Destroy()
    end
    cruisers = {}
    for _, cop in ipairs(cops) do
        cop.alive = false
        for _, c in ipairs(cop.connections) do c:Disconnect() end
        if cop.model then cop.model:Destroy() end
    end
    cops = {}
    if carValid(chaseTarget) then
        chaseTarget.model:SetAttribute("BustMeter", 0)
    end
    chaseTarget = nil
    bustFired = false
    caughtUntil = {}
    if folder then
        folder:Destroy()
        folder = nil
    end
end

function PoliceService:isActive()
    return #cruisers > 0 or #cops > 0
end

return PoliceService
