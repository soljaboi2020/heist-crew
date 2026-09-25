--[[
    HEIST CREW — VehicleService
    ────────────────────────────────────────────────
    v1.0 "Neon Miami" (2026-09-25). The drivable getaway car.

    WHY KINEMATIC: a physics car (constraints, springs, torque) needs tuning
    inside a running engine, and nobody can playtest from where this was
    written. So the car is an ANCHORED model that the server moves itself
    every Heartbeat with PivotTo:
      • speed v (studs/s) from the driver's throttle, yaw from their steer
      • ground-follow: raycast down each frame, sit the car on whatever is there
      • obstacles: a box cast ahead of the bumper; hit something = stop
      • water / void / a step taller than MAX_STEP_UP = treated as a wall
    Seated characters are welded to the seats (SeatWeld), so they ride along.

    INPUT: the stock Roblox vehicle controller fills VehicleSeat.ThrottleFloat
    / SteerFloat from WASD / thumbstick. As a belt-and-braces fallback the
    CarHud also mirrors those values to the server on the "CarInput" remote;
    whichever arrived most recently from the CURRENT driver wins.

    PUBLIC API:
        VehicleService:init(callbacks)
            callbacks.onDropoff(car, occupants:{Player})   -- once per spawn/reset
            callbacks.onDriverChanged(car, player|nil)      -- optional
        VehicleService:spawnGetaway(cframe) -> car          -- replaces any existing car
        VehicleService:getCar() -> car|nil

        car.model, car.driverSeat, car.trunk, car.seats
        car:getOccupants() -> {Player}
        car:getSpeed() -> number (absolute, studs/s)
        car:setAlarmMode(on)      -- underglow + cabin light flash red/blue
        car:freeze(on)            -- ignore input, stop hard
        car:ejectAll()            -- unseat everyone, drop them beside the car
        car:reset(cframe)         -- eject, stop, unfreeze, re-arm drop-off, teleport
        car:destroy()
        car:applyPaint(player|nil) -- (v2.0) body paint = that player's car color, nil = default white

        VehicleService:refreshPaint()        -- (v2.0) repaint for whoever is driving right now

    v2.0 CAR COLORS: whenever the driver seat changes hands the body is painted
    with the DRIVER's equipped car color (CosmeticsService:carPaintFor); empty
    seat / no cosmetic = the classic Vice White. CosmeticsService is required
    lazily, so no extra wiring is needed.

    MODEL ATTRIBUTES (read by CarHud): Speed, BustMeter (PoliceService),
    NitroUntil, NitroReadyAt, NitroCooldown (server time / seconds).

    SHARED WITH PoliceService: VehicleService.Kinematic (ground / obstacle
    probes + the movement step) and VehicleService.Build (part helpers).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local VehicleService = {}

local W = Constants.WORLD
local DROPOFF = Vector3.new(W.DROPOFF.x, W.DROPOFF.y, W.DROPOFF.z)
local CAR_INPUT_REMOTE = "CarInput"   -- not in Remotes.NAMES (see report); created here

local TUNE = {
    ACCEL          = 28,
    REVERSE_ACCEL  = 20,
    BRAKE          = 60,
    DRAG           = 9,      -- coasting
    OVERSPEED_DRAG = 30,     -- bleeding off speed after nitro ends
    FROZEN_BRAKE   = 120,
    MAX_FORWARD    = 55,
    MAX_REVERSE    = 18,
    DRIVER_MULT    = 1.2,    -- Driver role
    NITRO_MAX      = 85,
    NITRO_ACCEL    = 70,
    NITRO_TIME     = 2.5,
    NITRO_COOLDOWN = 12,     -- measured from activation
    YAW_RATE       = 1.9,    -- rad/s at full lock
    YAW_FULL_SPEED = 14,     -- steering reaches full authority at this speed
    MAX_STEP_UP    = 1.2,    -- tallest ledge the car will climb in one frame
    BUMPER_Y       = 1.5,    -- centre height of the obstacle box cast
    BUMPER_H       = 1.1,    -- its height (covers y 0.95..2.05 above the ground)
    OBSTACLE_PAD   = 1.5,
    INPUT_STALE    = 0.5,    -- seconds a CarInput packet stays valid
}
VehicleService.TUNE = TUNE

local BOUNDS = { x0 = -150, x1 = 150, z0 = -150, z1 = 60 }
VehicleService.BOUNDS = BOUNDS

local CAR_HALF_LEN = 5.6
local CAR_WIDTH = 4.7

-- ──────────────────────────────────────────────
-- small utils
-- ──────────────────────────────────────────────
local function approach(value, target, step)
    if value < target then
        return math.min(target, value + step)
    end
    return math.max(target, value - step)
end

local function safeNumber(x, lo, hi)
    if type(x) ~= "number" or x ~= x then return 0 end
    return math.clamp(x, lo, hi)
end

local function fire(fn, ...)
    if type(fn) ~= "function" then return end
    local args = table.pack(...)
    task.spawn(function()
        local ok, err = pcall(fn, table.unpack(args, 1, args.n))
        if not ok then warn("[VehicleService] callback error:", err) end
    end)
end

-- yaw such that CFrame.Angles(0, yaw, 0).LookVector points along `dir`
local function yawFromLook(dir)
    return math.atan2(-dir.X, -dir.Z)
end

-- ──────────────────────────────────────────────
-- Kinematic helpers (shared with PoliceService)
-- ──────────────────────────────────────────────
local Kin = {}
VehicleService.Kinematic = Kin
Kin.yawFromLook = yawFromLook
Kin.approach = approach

-- Every player character + every Guard-tagged NPC (guards and cops).
-- Vehicles drive through these (the physics pushes them aside) rather than
-- stopping dead or climbing on top of them.
function Kin.bodies()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then table.insert(list, p.Character) end
    end
    for _, g in ipairs(CollectionService:GetTagged("Guard")) do
        table.insert(list, g)
    end
    return list
end

function Kin.vehicles()
    local list = {}
    for _, tag in ipairs({ "GetawayCar", "PoliceCruiser" }) do
        for _, m in ipairs(CollectionService:GetTagged(tag)) do
            table.insert(list, m)
        end
    end
    return list
end

-- Filters: ground probes ignore bodies + ALL vehicles (never drive up onto
-- another car); obstacle probes ignore bodies + this vehicle only.
function Kin.filters(ownModel)
    local bodies = Kin.bodies()
    local ground = table.clone(bodies)
    for _, v in ipairs(Kin.vehicles()) do table.insert(ground, v) end
    if ownModel then table.insert(ground, ownModel) end
    local obstacle = bodies
    if ownModel then table.insert(obstacle, ownModel) end
    return ground, obstacle
end

-- Ground height under (x, z), searching down from fromY.
-- Returns y, material  -- or nil, "water" | "void"
function Kin.groundAt(x, z, fromY, exclude)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclude or {}
    params.IgnoreWater = false
    params.RespectCanCollide = true
    local result = Workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -80, 0), params)
    if not result then return nil, "void" end
    if result.Material == Enum.Material.Water then return nil, "water" end
    return result.Position.Y, result.Material
end

-- Something solid within `dist` studs of the bumper (dirSign 1 = forward,
-- -1 = backward)? Returns the RaycastResult or nil.
function Kin.obstacle(cf, dirSign, halfLen, width, dist, exclude)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclude or {}
    params.IgnoreWater = true
    params.RespectCanCollide = true

    local dir = cf.LookVector * dirSign
    -- start just inside the bumper (our own model is excluded anyway)
    local origin = cf * CFrame.new(0, TUNE.BUMPER_Y, -dirSign * (halfLen - 0.4))
    local ok, result = pcall(function()
        return Workspace:Blockcast(origin, Vector3.new(width, TUNE.BUMPER_H, 0.4), dir * (dist + 0.4), params)
    end)
    if ok then return result end

    -- fallback: three rays across the bumper
    for _, ox in ipairs({ -width / 2 + 0.2, 0, width / 2 - 0.2 }) do
        local o = (origin * CFrame.new(ox, 0, 0)).Position
        local r = Workspace:Raycast(o, dir * (dist + 0.4), params)
        if r then return r end
    end
    return nil
end

-- Move a kinematic body one frame. body = { pos (ground contact point),
-- yaw, v, halfLen, width, model }. The caller has already updated v and yaw.
-- Returns true if the move was blocked (v is zeroed).
function Kin.advance(body, dt, groundExclude, obstacleExclude)
    local cf = CFrame.new(body.pos) * CFrame.Angles(0, body.yaw, 0)
    local blocked = false
    local newPos = body.pos

    if math.abs(body.v) > 0.05 then
        local dirSign = body.v > 0 and 1 or -1
        local step = math.abs(body.v) * dt
        if Kin.obstacle(cf, dirSign, body.halfLen, body.width, step + TUNE.OBSTACLE_PAD, obstacleExclude) then
            body.v = 0
            blocked = true
        else
            newPos = body.pos + cf.LookVector * body.v * dt
        end
    end

    -- world bounds
    local cx = math.clamp(newPos.X, BOUNDS.x0, BOUNDS.x1)
    local cz = math.clamp(newPos.Z, BOUNDS.z0, BOUNDS.z1)
    if cx ~= newPos.X or cz ~= newPos.Z then
        body.v = 0
        blocked = true
    end

    -- ground follow: centre, nose and tail must all be over solid, dry ground
    local look = cf.LookVector
    local fromY = body.pos.Y + 5
    local best = -math.huge
    local solid = true
    for _, off in ipairs({ 0, body.halfLen - 1, -(body.halfLen - 1) }) do
        local y = Kin.groundAt(cx + look.X * off, cz + look.Z * off, fromY, groundExclude)
        if y == nil then
            solid = false
            break
        end
        best = math.max(best, y)
    end

    if not solid or best - body.pos.Y > TUNE.MAX_STEP_UP then
        -- water, void, or a wall-sized ledge: refuse the move
        body.v = 0
        if newPos ~= body.pos then blocked = true end
        return blocked
    end

    body.pos = Vector3.new(cx, best, cz)
    return blocked
end

-- ──────────────────────────────────────────────
-- Build helpers (shared with PoliceService). All coordinates are LOCAL to
-- the vehicle: origin = ground contact under the centre, front = -Z, right = +X.
-- ──────────────────────────────────────────────
local Build = {}
VehicleService.Build = Build

function Build.part(props, parent, className)
    local p = Instance.new(className or "Part")
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Material = Enum.Material.SmoothPlastic
    for k, v in pairs(props) do p[k] = v end
    p.Parent = parent
    return p
end

function Build.box(parent, name, x0, y0, z0, x1, y1, z1, color, material, extra, className)
    local props = {
        Name = name,
        Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
        CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
        Color = color,
        Material = material,
    }
    for k, v in pairs(extra or {}) do props[k] = v end
    return Build.part(props, parent, className)
end

-- Wedge: low edge toward the FRONT (-Z) by default; flip=true puts it at the back.
function Build.wedge(parent, name, x0, y0, z0, x1, y1, z1, color, material, flip, extra)
    local props = {
        Name = name,
        Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
        CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
            * (flip and CFrame.Angles(0, math.pi, 0) or CFrame.new()),
        Color = color,
        Material = material,
    }
    for k, v in pairs(extra or {}) do props[k] = v end
    return Build.part(props, parent, "WedgePart")
end

-- Tyre + silver rim, axle along X
function Build.wheel(parent, x, z, radius, width)
    local tyre = Build.part({
        Name = "Wheel", Shape = Enum.PartType.Cylinder,
        Size = Vector3.new(width, radius * 2, radius * 2),
        CFrame = CFrame.new(x, radius, z),
        Color = Color3.fromRGB(24, 24, 26), Material = Enum.Material.Rubber,
        CanCollide = false, CanTouch = false,
    }, parent)
    Build.part({
        Name = "Rim", Shape = Enum.PartType.Cylinder,
        Size = Vector3.new(width + 0.06, radius * 1.2, radius * 1.2),
        CFrame = CFrame.new(x, radius, z),
        Color = Color3.fromRGB(200, 204, 212), Material = Enum.Material.Metal,
        Reflectance = 0.15, CanCollide = false, CanTouch = false, CanQuery = false,
    }, parent)
    return tyre
end

-- ──────────────────────────────────────────────
-- The getaway car: an '80s Miami wedge (Testarossa / Daytona Spyder).
-- Open-top on purpose: four seated R15 avatars are ~5 studs tall, so a
-- closed 3.4-stud cabin would have their heads poking through the roof.
-- The "black glass" is the raked windscreen + low side glass.
-- ──────────────────────────────────────────────
local WHITE     = Color3.fromRGB(242, 242, 238)
local PINK      = Color3.fromRGB(255, 70, 180)
local CYAN      = Color3.fromRGB(40, 230, 255)
local BLACK     = Color3.fromRGB(18, 18, 22)
local LEATHER   = Color3.fromRGB(34, 30, 32)
local TRIM      = Color3.fromRGB(58, 60, 66)
local RED_LIGHT = Color3.fromRGB(255, 40, 60)
local BLUE_LIGHT = Color3.fromRGB(60, 110, 255)

local PAINT = { Material = Enum.Material.SmoothPlastic, Reflectance = 0.12 }  -- glossy car paint
local GLASS = { Transparency = 0.25, Reflectance = 0.25 }
local DECOR = { CanCollide = false, CanTouch = false }

local function buildCarModel()
    local model = Instance.new("Model")
    model.Name = "GetawayCar"
    local B = Build

    local root = B.part({
        Name = "Root", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(),
        Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false,
    }, model)
    model.PrimaryPart = root

    -- body
    B.box(model, "LowerBody", -2.3, 0.75, -5.5, 2.3, 1.55, 5.5, WHITE, Enum.Material.SmoothPlastic, PAINT)
    B.wedge(model, "Hood", -2.3, 1.55, -5.5, 2.3, 2.25, -1.4, WHITE, Enum.Material.SmoothPlastic, false, PAINT)
    B.box(model, "CockpitWallL", -2.3, 1.55, -1.4, -1.9, 2.25, 3.2, WHITE, Enum.Material.SmoothPlastic, PAINT)
    B.box(model, "CockpitWallR", 1.9, 1.55, -1.4, 2.3, 2.25, 3.2, WHITE, Enum.Material.SmoothPlastic, PAINT)
    B.box(model, "Dash", -1.9, 1.55, -1.4, 1.9, 2.25, -0.95, LEATHER, Enum.Material.Fabric)
    B.box(model, "Bulkhead", -1.9, 1.55, 3.0, 1.9, 2.6, 3.2, LEATHER, Enum.Material.Fabric)
    B.box(model, "RearDeck", -2.3, 1.55, 3.2, 2.3, 2.45, 5.5, WHITE, Enum.Material.SmoothPlastic, PAINT)
    -- (v2.0) the body panels that take the driver's car color
    local paint = {}
    for _, name in ipairs({ "LowerBody", "Hood", "CockpitWallL", "CockpitWallR", "RearDeck" }) do
        local pt = model:FindFirstChild(name)
        if pt and pt:IsA("BasePart") then table.insert(paint, pt) end
    end
    -- engine-lid slats (the Testarossa grille)
    for i = 0, 3 do
        local z = 3.6 + i * 0.42
        B.box(model, "DeckSlat", -1.8, 2.45, z, 1.8, 2.5, z + 0.2, BLACK, Enum.Material.Metal, DECOR)
    end
    -- targa hoop (keeps the silhouette at ~3.4 tall)
    B.box(model, "HoopL", -1.95, 2.45, 3.05, -1.75, 3.25, 3.25, BLACK, Enum.Material.Metal)
    B.box(model, "HoopR", 1.75, 2.45, 3.05, 1.95, 3.25, 3.25, BLACK, Enum.Material.Metal)
    B.box(model, "HoopTop", -1.95, 3.2, 3.05, 1.95, 3.4, 3.25, BLACK, Enum.Material.Metal)

    -- black glass: raked windscreen + low side glass
    B.wedge(model, "Windscreen", -1.9, 2.25, -1.4, 1.9, 3.3, -0.75, BLACK, Enum.Material.Glass, false, GLASS)
    B.box(model, "SideGlassL", -2.3, 2.25, -0.75, -2.2, 2.85, 1.2, BLACK, Enum.Material.Glass, GLASS)
    B.box(model, "SideGlassR", 2.2, 2.25, -0.75, 2.3, 2.85, 1.2, BLACK, Enum.Material.Glass, GLASS)

    -- hot-pink side stripe + black side strakes
    for _, s in ipairs({ -1, 1 }) do
        local x0, x1 = s * 2.3, s * 2.36
        B.box(model, "Stripe", math.min(x0, x1), 1.22, -5.3, math.max(x0, x1), 1.42, 5.3, PINK,
            Enum.Material.SmoothPlastic, DECOR)
        for _, y in ipairs({ 1.72, 1.92, 2.12 }) do
            B.box(model, "Strake", math.min(x0, x1), y, 1.3, math.max(x0, x1), y + 0.09, 3.9, BLACK,
                Enum.Material.Metal, DECOR)
        end
    end

    -- bumpers
    B.box(model, "BumperF", -2.3, 0.55, -5.65, 2.3, 0.95, -5.45, TRIM, Enum.Material.Metal)
    B.box(model, "BumperR", -2.3, 0.55, 5.45, 2.3, 0.95, 5.65, TRIM, Enum.Material.Metal)

    -- pop-up headlights (raised) + beams
    local headlights = {}
    for _, s in ipairs({ -1, 1 }) do
        local xa, xb = s * 1.0, s * 2.0
        B.box(model, "PopUp", math.min(xa, xb), 1.75, -4.3, math.max(xa, xb), 2.15, -3.5, BLACK,
            Enum.Material.SmoothPlastic, PAINT)
        local la, lb = s * 1.1, s * 1.9
        local lens = B.box(model, "HeadlightLens", math.min(la, lb), 1.8, -4.34, math.max(la, lb), 2.1, -4.3,
            Color3.fromRGB(255, 248, 225), Enum.Material.Neon, DECOR)
        local beam = Instance.new("SpotLight")
        beam.Face = Enum.NormalId.Front
        beam.Angle = 55
        beam.Brightness = 3
        beam.Range = 40
        beam.Color = Color3.fromRGB(255, 244, 220)
        beam.Shadows = false
        beam.Parent = lens
        table.insert(headlights, beam)
        -- amber running light low on the nose
        local ra, rb = s * 1.7, s * 2.15
        B.box(model, "RunningLight", math.min(ra, rb), 0.98, -5.56, math.max(ra, rb), 1.14, -5.5,
            Color3.fromRGB(255, 170, 60), Enum.Material.Neon, DECOR)
    end

    -- rear: taillight strip, trunk panel, exhaust flames (nitro)
    B.box(model, "Taillights", -2.2, 1.24, 5.5, 2.2, 1.46, 5.56, RED_LIGHT, Enum.Material.Neon, DECOR)
    local trunk = B.box(model, "Trunk", -1.4, 0.95, 5.5, 1.4, 1.2, 5.6, BLACK, Enum.Material.Metal, DECOR)
    local exhausts = {}
    for _, s in ipairs({ -1, 1 }) do
        B.box(model, "Tailpipe", s * 1.0 - 0.18, 0.62, 5.5, s * 1.0 + 0.18, 0.86, 5.8, TRIM, Enum.Material.Metal, DECOR)
        local flame = B.box(model, "NitroFlame", s * 1.0 - 0.14, 0.66, 5.8, s * 1.0 + 0.14, 0.82, 6.5,
            Color3.fromRGB(80, 200, 255), Enum.Material.Neon, { CanCollide = false, CanTouch = false, CanQuery = false, Transparency = 1 })
        table.insert(exhausts, flame)
    end

    -- wheels
    for _, s in ipairs({ -1, 1 }) do
        B.wheel(model, s * 2.25, -3.6, 1.05, 0.8)
        B.wheel(model, s * 2.25, 3.5, 1.05, 0.8)
    end

    -- neon underglow: two thin strips + one light under the car
    local glow = {}
    for _, s in ipairs({ -1, 1 }) do
        local a, b = s * 2.0, s * 2.2
        table.insert(glow, B.box(model, "Underglow", math.min(a, b), 0.45, -4.4, math.max(a, b), 0.55, 4.4, CYAN,
            Enum.Material.Neon, { CanCollide = false, CanTouch = false, CanQuery = false }))
    end
    local glowEmitter = B.part({
        Name = "UnderglowEmitter", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(0, 0.35, 0),
        Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false,
    }, model)
    local underLight = Instance.new("PointLight")
    underLight.Color = CYAN
    underLight.Range = 12
    underLight.Brightness = 2.2
    underLight.Shadows = false
    underLight.Parent = glowEmitter

    local cabinEmitter = B.part({
        Name = "CabinLight", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(0, 2.2, 0.9),
        Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false,
    }, model)
    local cabinLight = Instance.new("PointLight")
    cabinLight.Color = CYAN
    cabinLight.Range = 7
    cabinLight.Brightness = 0.8
    cabinLight.Shadows = false
    cabinLight.Parent = cabinEmitter

    -- seats (front = -Z, so the default seat orientation already faces forward)
    local seatProps = { Color = LEATHER, Material = Enum.Material.Fabric, Size = Vector3.new(1.4, 0.4, 1.4) }
    local driverSeat = Instance.new("VehicleSeat")
    driverSeat.Name = "GetawayDriverSeat"
    driverSeat.HeadsUpDisplay = false
    driverSeat.MaxSpeed = 0
    driverSeat.Torque = 0
    for k, v in pairs(seatProps) do (driverSeat :: any)[k] = v end
    driverSeat.Anchored = true
    driverSeat.CFrame = CFrame.new(-0.9, 1.75, -0.2)
    driverSeat.Parent = model

    local seats = { driverSeat }
    local seatSpots = {
        { "PassengerSeat", 0.9, -0.2 },
        { "RearSeatL", -0.9, 2.1 },
        { "RearSeatR", 0.9, 2.1 },
    }
    for _, spot in ipairs(seatSpots) do
        local s = Instance.new("Seat")
        s.Name = spot[1]
        for k, v in pairs(seatProps) do (s :: any)[k] = v end
        s.Anchored = true
        s.CFrame = CFrame.new(spot[2], 1.75, spot[3])
        s.Parent = model
        table.insert(seats, s)
    end
    -- front seat backs (the rear pair lean on the bulkhead)
    for _, x in ipairs({ -0.9, 0.9 }) do
        B.box(model, "SeatBack", x - 0.7, 1.95, 0.5, x + 0.7, 2.95, 0.75, LEATHER, Enum.Material.Fabric)
    end

    return {
        model = model, root = root, driverSeat = driverSeat, seats = seats, trunk = trunk,
        glow = glow, underLight = underLight, cabinLight = cabinLight,
        headlights = headlights, exhausts = exhausts,
        paint = paint,
    }
end

-- ──────────────────────────────────────────────
-- Car object
-- ──────────────────────────────────────────────
local Car = {}
Car.__index = Car

local callbacks = {}
local currentCar = nil
local inputs = {}          -- [Player] = { throttle, steer, at }
local initialized = false

local function carCFrame(pos, yaw)
    return CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
end

function Car:_placeAt(cframe)
    local look = cframe.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 1e-3 then flat = Vector3.new(0, 0, -1) end
    self.yaw = yawFromLook(flat.Unit)
    local p = cframe.Position
    local groundExclude = Kin.filters(self.model)
    local y = Kin.groundAt(p.X, p.Z, p.Y + 6, groundExclude)
    self.pos = Vector3.new(p.X, y or p.Y, p.Z)
    self.v = 0
    self.model:PivotTo(carCFrame(self.pos, self.yaw))
end

function Car:getSpeed()
    return math.abs(self.v or 0)
end

function Car:getOccupants()
    local list = {}
    for _, seat in ipairs(self.seats) do
        local hum = seat.Occupant
        if hum and hum.Parent then
            local p = Players:GetPlayerFromCharacter(hum.Parent)
            if p then table.insert(list, p) end
        end
    end
    return list
end

function Car:getDriver()
    local hum = self.driverSeat and self.driverSeat.Occupant
    if hum and hum.Parent then
        return Players:GetPlayerFromCharacter(hum.Parent), hum
    end
    return nil, hum
end

function Car:_setGlowColor(color)
    for _, g in ipairs(self.glow) do g.Color = color end
    self.underLight.Color = color
    self.cabinLight.Color = color
end

-- (v2.0) car colors — CosmeticsService is optional and loaded on first use
local Cosmetics = nil
local function cosmetics()
    if Cosmetics ~= nil then return Cosmetics or nil end
    Cosmetics = false
    local mod = script.Parent:FindFirstChild("CosmeticsService")
    if mod then
        local ok, result = pcall(require, mod)
        if ok and type(result) == "table" then Cosmetics = result end
    end
    return Cosmetics or nil
end

function Car:applyPaint(player)
    local spec = nil
    local C = player and cosmetics()
    if C and C.carPaintFor then
        local ok, res = pcall(function() return C:carPaintFor(player) end)
        if ok and type(res) == "table" then spec = res end
    end
    local color = spec and spec.color or WHITE
    local mat = spec and spec.material or PAINT.Material
    local refl = spec and spec.reflectance or PAINT.Reflectance
    for _, pt in ipairs(self.paint or {}) do
        if pt.Parent then
            pt.Color = color
            pt.Material = mat
            pt.Reflectance = refl
        end
    end
    self.model:SetAttribute("Paint", spec and spec.id or "CarClassic")
end

function Car:setAlarmMode(on)
    self.alarm = on and true or false
    self._phase = nil
    if not self.alarm then
        self:_setGlowColor(CYAN)
        self.cabinLight.Brightness = 0.8
    else
        self.cabinLight.Brightness = 1.6
    end
    if self.model then self.model:SetAttribute("Alarm", self.alarm) end
end

function Car:freeze(on)
    self.frozen = on and true or false
    if self.frozen then
        self.v = 0
        if self.model then self.model:SetAttribute("NitroUntil", 0) end
    end
end

function Car:ejectAll()
    local pivot = self.model and self.model:GetPivot() or carCFrame(self.pos, self.yaw)
    for _, seat in ipairs(self.seats) do
        local hum = seat.Occupant
        for _, c in ipairs(seat:GetChildren()) do
            if c.Name == "SeatWeld" and c:IsA("JointInstance") then c:Destroy() end
        end
        if hum then
            pcall(function() hum.Sit = false end)
            local char = hum.Parent
            if char and char:IsA("Model") then
                -- drop them just outside their side of the car
                local localPos = pivot:PointToObjectSpace(seat.Position)
                local side = localPos.X >= 0 and 1 or -1
                local exit = pivot * CFrame.new(side * 4.6, 3.2, localPos.Z)
                pcall(function()
                    char:PivotTo(CFrame.new(exit.Position) * pivot.Rotation)
                end)
            end
        end
    end
end

function Car:reset(cframe)
    self:ejectAll()
    self.v = 0
    self.frozen = false
    self.dropoffFired = false
    self:setAlarmMode(false)
    self.model:SetAttribute("NitroUntil", 0)
    self.model:SetAttribute("NitroReadyAt", 0)
    self.model:SetAttribute("BustMeter", 0)
    self.model:SetAttribute("Speed", 0)
    if typeof(cframe) == "CFrame" then
        self:_placeAt(cframe)
    end
end

function Car:destroy()
    if self.destroyed then return end
    self.destroyed = true
    for _, c in ipairs(self.connections) do c:Disconnect() end
    self.connections = {}
    if self.model then self.model:Destroy() end
    if currentCar == self then currentCar = nil end
end

function Car:_readInput(driver)
    local rec = driver and inputs[driver]
    if rec and os.clock() - rec.at < TUNE.INPUT_STALE then
        return rec.throttle, rec.steer
    end
    local seat = self.driverSeat
    return safeNumber(seat.ThrottleFloat, -1, 1), safeNumber(seat.SteerFloat, -1, 1)
end

function Car:_step(dt)
    if self.destroyed or not self.model or not self.model.Parent then return end
    local model = self.model
    local now = Workspace:GetServerTimeNow()
    local driver, driverHum = self:getDriver()

    local throttle, steer = 0, 0
    if driverHum and not self.frozen then
        throttle, steer = self:_readInput(driver)
    end

    local maxF = TUNE.MAX_FORWARD
    if driver and driver:GetAttribute("Role") == "Driver" then
        maxF = maxF * TUNE.DRIVER_MULT
    end
    local accel = TUNE.ACCEL
    local nitroUntil = tonumber(model:GetAttribute("NitroUntil")) or 0
    local nitroOn = driverHum ~= nil and not self.frozen and now < nitroUntil
    if nitroOn and throttle >= 0 then
        maxF = TUNE.NITRO_MAX
        accel = TUNE.NITRO_ACCEL
        throttle = 1
    end

    -- speed
    local v = self.v
    if self.frozen then
        v = approach(v, 0, TUNE.FROZEN_BRAKE * dt)
    elseif throttle > 0.01 then
        if v < 0 then
            v = math.min(0, v + TUNE.BRAKE * throttle * dt)
        elseif v < maxF then
            v = math.min(maxF, v + accel * throttle * dt)
        end
    elseif throttle < -0.01 then
        if v > 0 then
            v = math.max(0, v + TUNE.BRAKE * throttle * dt)
        elseif v > -TUNE.MAX_REVERSE then
            v = math.max(-TUNE.MAX_REVERSE, v + TUNE.REVERSE_ACCEL * throttle * dt)
        end
    else
        v = approach(v, 0, TUNE.DRAG * dt)
    end
    if v > maxF then v = math.max(maxF, v - TUNE.OVERSPEED_DRAG * dt) end
    if v < -TUNE.MAX_REVERSE then v = -TUNE.MAX_REVERSE end
    self.v = v

    -- steering (reversing flips it, like a real car)
    local oldPos, oldYaw = self.pos, self.yaw
    local grip = math.clamp(math.abs(v) / TUNE.YAW_FULL_SPEED, 0, 1)
    local dirSign = v >= 0 and 1 or -1
    self.yaw = self.yaw - steer * TUNE.YAW_RATE * grip * dirSign * dt

    if math.abs(self.v) > 0.01 or self.yaw ~= oldYaw then
        local groundEx, obstacleEx = Kin.filters(model)
        Kin.advance(self, dt, groundEx, obstacleEx)
    end
    if self.pos ~= oldPos or self.yaw ~= oldYaw then
        model:PivotTo(carCFrame(self.pos, self.yaw))
    end

    -- HUD attribute (~10 Hz)
    self._attrClock = (self._attrClock or 0) + dt
    if self._attrClock >= 0.1 then
        self._attrClock = 0
        local shown = math.floor(math.abs(self.v) * 10 + 0.5) / 10
        if model:GetAttribute("Speed") ~= shown then model:SetAttribute("Speed", shown) end
    end

    -- nitro flames
    if nitroOn ~= self._flames then
        self._flames = nitroOn
        for _, f in ipairs(self.exhausts) do f.Transparency = nitroOn and 0 or 1 end
    end

    -- alarm flashing: red / blue at ~5 Hz
    if self.alarm then
        local phase = math.floor(os.clock() * 5) % 2
        if phase ~= self._phase then
            self._phase = phase
            self:_setGlowColor(phase == 0 and RED_LIGHT or BLUE_LIGHT)
        end
    end

    -- drop-off
    -- (fix v1.1: the latch now re-arms when the car leaves the zone, so a joyride to
    -- the marina before the heist can't disable the drop-off for the real run)
    local d = Vector3.new(self.pos.X - DROPOFF.X, 0, self.pos.Z - DROPOFF.Z).Magnitude
    if d <= W.DROPOFF_RADIUS then
        if not self.dropoffFired then
            local occ = self:getOccupants()
            if #occ > 0 then
                self.dropoffFired = true
                fire(callbacks.onDropoff, self, occ)
            end
        end
    else
        self.dropoffFired = false
    end
end

-- "Drive" / "Get in" prompts: touch-to-sit is unreliable on a car you have
-- to climb into, so every seat also gets a ProximityPrompt that seats you.
function Car:_wireSeat(seat, isDriver)
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "EnterPrompt"
    prompt.ActionText = isDriver and "Drive" or "Get in"
    prompt.ObjectText = "Getaway car"
    prompt.KeyboardKeyCode = Enum.KeyCode.F    -- E is left free for the trunk / loot prompts
    prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 9
    prompt.RequiresLineOfSight = false
    prompt.Parent = seat

    table.insert(self.connections, prompt.Triggered:Connect(function(player)
        if self.destroyed or seat.Occupant then return end
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 or hum.SeatPart then return end
        pcall(function() seat:Sit(hum) end)
    end))

    table.insert(self.connections, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
        prompt.Enabled = seat.Occupant == nil
        if isDriver then
            local driver = self:getDriver()
            self:applyPaint(driver)
            fire(callbacks.onDriverChanged, self, driver)
        end
    end))
end

local function newCar(cframe)
    local parts = buildCarModel()
    local self = setmetatable({
        model = parts.model,
        root = parts.root,
        driverSeat = parts.driverSeat,
        seats = parts.seats,
        trunk = parts.trunk,
        glow = parts.glow,
        underLight = parts.underLight,
        cabinLight = parts.cabinLight,
        headlights = parts.headlights,
        exhausts = parts.exhausts,
        paint = parts.paint,
        halfLen = CAR_HALF_LEN,
        width = CAR_WIDTH,
        pos = Vector3.zero,
        yaw = 0,
        v = 0,
        frozen = false,
        alarm = false,
        dropoffFired = false,
        destroyed = false,
        connections = {},
    }, Car)

    local model = self.model
    model:SetAttribute("Speed", 0)
    model:SetAttribute("BustMeter", 0)
    model:SetAttribute("NitroUntil", 0)
    model:SetAttribute("NitroReadyAt", 0)
    model:SetAttribute("NitroCooldown", TUNE.NITRO_COOLDOWN)
    model:SetAttribute("Alarm", false)
    CollectionService:AddTag(model, "GetawayCar")

    for i, seat in ipairs(self.seats) do
        self:_wireSeat(seat, i == 1)
    end

    -- place first (probes exclude this model anyway), then parent, so the car
    -- never flashes at the world origin for a frame
    self:_placeAt(typeof(cframe) == "CFrame" and cframe or CFrame.new(
        W.GETAWAY_POSITION.x, W.GETAWAY_POSITION.y, W.GETAWAY_POSITION.z))
    model.Parent = Workspace

    table.insert(self.connections, model.AncestryChanged:Connect(function()
        if not model:IsDescendantOf(game) then self:destroy() end
    end))
    return self
end

-- ──────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────
function VehicleService:init(cb)
    cb = cb or {}
    callbacks.onDropoff = cb.onDropoff
    callbacks.onDriverChanged = cb.onDriverChanged
    if initialized then return end
    initialized = true

    local nitroRemote = Remotes.getRemote(Remotes.NAMES.Nitro)
    nitroRemote.OnServerEvent:Connect(function(player)
        local car = currentCar
        if not car or car.destroyed or car.frozen then return end
        local driver = car:getDriver()
        if driver ~= player then return end
        if player:GetAttribute("Role") ~= "Driver" then return end
        local now = Workspace:GetServerTimeNow()
        if now < (tonumber(car.model:GetAttribute("NitroReadyAt")) or 0) then return end
        car.model:SetAttribute("NitroUntil", now + TUNE.NITRO_TIME)
        car.model:SetAttribute("NitroReadyAt", now + TUNE.NITRO_COOLDOWN)
    end)

    local inputRemote = Remotes.getRemote(CAR_INPUT_REMOTE)
    inputRemote.OnServerEvent:Connect(function(player, throttle, steer)
        local car = currentCar
        if not car or car:getDriver() ~= player then
            inputs[player] = nil
            return
        end
        inputs[player] = {
            throttle = safeNumber(throttle, -1, 1),
            steer = safeNumber(steer, -1, 1),
            at = os.clock(),
        }
    end)
    Players.PlayerRemoving:Connect(function(player) inputs[player] = nil end)

    RunService.Heartbeat:Connect(function(dt)
        local car = currentCar
        if car and not car.destroyed then
            car:_step(math.min(dt, 0.1))
        end
    end)
end

function VehicleService:spawnGetaway(cframe)
    if currentCar then currentCar:destroy() end
    currentCar = newCar(cframe)
    return currentCar
end

function VehicleService:refreshPaint()
    local car = self:getCar()
    if car then car:applyPaint((car:getDriver())) end
end

function VehicleService:getCar()
    if currentCar and currentCar.destroyed then currentCar = nil end
    return currentCar
end

return VehicleService
