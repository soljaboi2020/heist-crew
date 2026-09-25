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
        car:setType(carId) -> changed   -- (v2.2) rebuild as another car type IN PLACE (same
                                        --  car object, same Trunk part); ejects everyone first
        car.carId, car.carType, car.speedMult, car.bustMult, car.nitroCooldown, car.halfLen, car.width

        VehicleService:spawnGetaway(cframe, carId?) -- carId default = best car in the server
        VehicleService:chooseForCrew(players) -> carId   -- (v2.2) JobService, at the drop-in
        VehicleService:refreshType()          -- (v2.2) club only: re-pick from the server
        VehicleService:isCrewLocked() -> bool
        VehicleService.CAR_TYPES             -- { "classic", "muscle", "racer", "armored", "monster", "tank" }
        callbacks.onTypeChanged(car, carId)   -- optional

    v2.2 CAR TYPES (gear agent — replaces the v2.0 car paints). CosmeticsService
    owns the list + stats (carStats / pickCrewCar); this file builds a distinct
    model per type (BODIES below) on one shared kit: same 4-seat layout, trunk,
    lights, flames, underglow. Stats: speedMult scales top speed, acceleration
    and nitro; nitroCooldown per type (Muscle 7 s); bustMult is read by
    PoliceService. WHICH CAR: the priciest car anyone in the crew has equipped
    (CosmeticsService:pickCrewCar). In the club the car previews the best car in
    the server and follows equips live; chooseForCrew locks it for the run,
    Car:reset (after the run) unlocks it. Previews of every type are published
    to ReplicatedStorage.HC_CarPreviews (for ShopUI's ViewportFrames).
    Model attributes: CarId, CarType, CarName, CarPerk, SpeedMult, BustMult.

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
-- v2.2 CAR TYPES. Every type is built from parts in LOCAL coords (origin =
-- ground under the centre, front = -Z, right = +X) and shares one "kit":
-- the same 4-seat layout (driver front-left, passenger front-right, two in
-- the back at z 2.1 — only the seat HEIGHT changes per type), trunk at the
-- tail (the "Load bag" prompt lives on it), headlights, taillights, nitro
-- flames, underglow + cabin light (the alarm flashes them).
-- Every type is ≤ 5.5 studs wide INCLUDING wheels (yard gates are ~7.4) and
-- ≤ 7.2 tall (gate headers start at ~10.6).
--   classic  '80s Miami wedge (Testarossa)        5.36 wide · 11.5 long · 3.4 tall
--   muscle   '70s muscle coupe, hood scoop         5.41 · 12.6 · 3.2
--   racer    low wedge supercar + big wing         5.41 · 12.0 · 2.95
--   armored  armored van: bull bar, plates, box    5.46 · 13.2 · 5.9
--   monster  lifted pickup on 4-stud wheels        5.46 · 13.3 · 7.15
--   tank     treads, hull, cartoon turret          5.44 · 13.0 · 7.1
-- Open-top on purpose (every type): four seated R15 avatars are ~5 studs
-- tall, so a closed cabin would have their heads through the roof.
-- ──────────────────────────────────────────────
local WHITE     = Color3.fromRGB(242, 242, 238)
local PINK      = Color3.fromRGB(255, 70, 180)
local CYAN      = Color3.fromRGB(40, 230, 255)
local BLACK     = Color3.fromRGB(18, 18, 22)
local LEATHER   = Color3.fromRGB(34, 30, 32)
local TRIM      = Color3.fromRGB(58, 60, 66)
local CHROME    = Color3.fromRGB(200, 204, 212)
local RED_LIGHT = Color3.fromRGB(255, 40, 60)
local BLUE_LIGHT = Color3.fromRGB(60, 110, 255)
local AMBER     = Color3.fromRGB(255, 170, 60)
local LAMP      = Color3.fromRGB(255, 248, 225)

local SM = Enum.Material.SmoothPlastic
local PAINT = { Material = SM, Reflectance = 0.12 }  -- glossy car paint
local GLASS = { Transparency = 0.25, Reflectance = 0.25 }
local DECOR = { CanCollide = false, CanTouch = false }
local GHOST = { CanCollide = false, CanTouch = false, CanQuery = false }

local function mirrorX(a, b) return math.min(a, b), math.max(a, b) end

-- a headlight lens on the nose (front face at z) + returns it for the kit
local function lens(model, name, xa, xb, y0, y1, z, color)
    local x0, x1 = mirrorX(xa, xb)
    return Build.box(model, name or "HeadlightLens", x0, y0, z - 0.04, x1, y1, z, color or LAMP, Enum.Material.Neon, DECOR)
end

-- ── the shared kit ──────────────────────────────
-- spec = { seatY, lenses = {Part}, tail = {x0,y0,z0,x1,y1,z1}, trunk = {…},
--          exhausts = { {x, y, z} }, glow = { y, xIn, xOut, z0, z1 },
--          cabin = Vector3, rearBack = bool (add rear seat backs) }
local function kit(model, spec)
    local B = Build
    local seatY = spec.seatY
    local headlights = {}
    for _, l in ipairs(spec.lenses or {}) do
        local beam = Instance.new("SpotLight")
        beam.Face = Enum.NormalId.Front
        beam.Angle = 55
        beam.Brightness = 3
        beam.Range = 40
        beam.Color = Color3.fromRGB(255, 244, 220)
        beam.Shadows = false
        beam.Parent = l
        table.insert(headlights, beam)
    end
    local t = spec.tail
    B.box(model, "Taillights", t[1], t[2], t[3], t[4], t[5], t[6], RED_LIGHT, Enum.Material.Neon, DECOR)
    local k = spec.trunk
    local trunk = B.box(model, "Trunk", k[1], k[2], k[3], k[4], k[5], k[6], BLACK, Enum.Material.Metal, DECOR)
    local exhausts = {}
    for _, e in ipairs(spec.exhausts) do
        local x, y, z = e[1], e[2], e[3]
        B.box(model, "Tailpipe", x - 0.18, y - 0.12, z, x + 0.18, y + 0.12, z + 0.3, TRIM, Enum.Material.Metal, DECOR)
        local flame = B.box(model, "NitroFlame", x - 0.14, y - 0.08, z + 0.3, x + 0.14, y + 0.08, z + 1.0,
            Color3.fromRGB(80, 200, 255), Enum.Material.Neon, { CanCollide = false, CanTouch = false, CanQuery = false, Transparency = 1 })
        table.insert(exhausts, flame)
    end
    local g = spec.glow
    local glow = {}
    for _, s in ipairs({ -1, 1 }) do
        local a, b = mirrorX(s * g[2], s * g[3])
        table.insert(glow, B.box(model, "Underglow", a, g[1], g[4], b, g[1] + 0.1, g[5], CYAN, Enum.Material.Neon, GHOST))
    end
    local glowEmitter = B.part({
        Name = "UnderglowEmitter", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(0, g[1] - 0.1, 0),
        Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false,
    }, model)
    local underLight = Instance.new("PointLight")
    underLight.Color = CYAN
    underLight.Range = 12
    underLight.Brightness = 2.2
    underLight.Shadows = false
    underLight.Parent = glowEmitter

    local cabinEmitter = B.part({
        Name = "CabinLight", Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(spec.cabin or Vector3.new(0, seatY + 0.45, 0.9)),
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
    for key, v in pairs(seatProps) do (driverSeat :: any)[key] = v end
    driverSeat.Anchored = true
    driverSeat.CFrame = CFrame.new(-0.9, seatY, -0.2)
    driverSeat.Parent = model
    local seats = { driverSeat }
    for _, spot in ipairs({ { "PassengerSeat", 0.9, -0.2 }, { "RearSeatL", -0.9, 2.1 }, { "RearSeatR", 0.9, 2.1 } }) do
        local s = Instance.new("Seat")
        s.Name = spot[1]
        for key, v in pairs(seatProps) do (s :: any)[key] = v end
        s.Anchored = true
        s.CFrame = CFrame.new(spot[2], seatY, spot[3])
        s.Parent = model
        table.insert(seats, s)
    end
    for _, x in ipairs({ -0.9, 0.9 }) do
        B.box(model, "SeatBack", x - 0.7, seatY + 0.2, 0.5, x + 0.7, seatY + 1.2, 0.75, LEATHER, Enum.Material.Fabric)
        if spec.rearBack then
            B.box(model, "SeatBack", x - 0.7, seatY + 0.2, 2.8, x + 0.7, seatY + 1.1, 3.05, LEATHER, Enum.Material.Fabric)
        end
    end
    return {
        driverSeat = driverSeat, seats = seats, trunk = trunk, glow = glow, underLight = underLight,
        cabinLight = cabinLight, headlights = headlights, exhausts = exhausts,
    }
end

-- ── the bodies ──────────────────────────────────
local BODIES = {}

-- CLASSIC: an '80s Miami wedge (Testarossa / Daytona Spyder)
BODIES.classic = function(model, P)
    local B = Build
    B.box(model, "LowerBody", -2.3, 0.75, -5.5, 2.3, 1.55, 5.5, P, SM, PAINT)
    B.wedge(model, "Hood", -2.3, 1.55, -5.5, 2.3, 2.25, -1.4, P, SM, false, PAINT)
    B.box(model, "CockpitWallL", -2.3, 1.55, -1.4, -1.9, 2.25, 3.2, P, SM, PAINT)
    B.box(model, "CockpitWallR", 1.9, 1.55, -1.4, 2.3, 2.25, 3.2, P, SM, PAINT)
    B.box(model, "Dash", -1.9, 1.55, -1.4, 1.9, 2.25, -0.95, LEATHER, Enum.Material.Fabric)
    B.box(model, "Bulkhead", -1.9, 1.55, 3.0, 1.9, 2.6, 3.2, LEATHER, Enum.Material.Fabric)
    B.box(model, "RearDeck", -2.3, 1.55, 3.2, 2.3, 2.45, 5.5, P, SM, PAINT)
    for i = 0, 3 do   -- engine-lid slats (the Testarossa grille)
        local z = 3.6 + i * 0.42
        B.box(model, "DeckSlat", -1.8, 2.45, z, 1.8, 2.5, z + 0.2, BLACK, Enum.Material.Metal, DECOR)
    end
    B.box(model, "HoopL", -1.95, 2.45, 3.05, -1.75, 3.25, 3.25, BLACK, Enum.Material.Metal)
    B.box(model, "HoopR", 1.75, 2.45, 3.05, 1.95, 3.25, 3.25, BLACK, Enum.Material.Metal)
    B.box(model, "HoopTop", -1.95, 3.2, 3.05, 1.95, 3.4, 3.25, BLACK, Enum.Material.Metal)
    B.wedge(model, "Windscreen", -1.9, 2.25, -1.4, 1.9, 3.3, -0.75, BLACK, Enum.Material.Glass, false, GLASS)
    B.box(model, "SideGlassL", -2.3, 2.25, -0.75, -2.2, 2.85, 1.2, BLACK, Enum.Material.Glass, GLASS)
    B.box(model, "SideGlassR", 2.2, 2.25, -0.75, 2.3, 2.85, 1.2, BLACK, Enum.Material.Glass, GLASS)
    for _, s in ipairs({ -1, 1 }) do
        local x0, x1 = mirrorX(s * 2.3, s * 2.36)
        B.box(model, "Stripe", x0, 1.22, -5.3, x1, 1.42, 5.3, PINK, SM, DECOR)
        for _, y in ipairs({ 1.72, 1.92, 2.12 }) do
            B.box(model, "Strake", x0, y, 1.3, x1, y + 0.09, 3.9, BLACK, Enum.Material.Metal, DECOR)
        end
    end
    B.box(model, "BumperF", -2.3, 0.55, -5.65, 2.3, 0.95, -5.45, TRIM, Enum.Material.Metal)
    B.box(model, "BumperR", -2.3, 0.55, 5.45, 2.3, 0.95, 5.65, TRIM, Enum.Material.Metal)
    local lenses = {}
    for _, s in ipairs({ -1, 1 }) do
        local xa, xb = mirrorX(s * 1.0, s * 2.0)
        B.box(model, "PopUp", xa, 1.75, -4.3, xb, 2.15, -3.5, BLACK, SM, PAINT)
        table.insert(lenses, lens(model, nil, s * 1.1, s * 1.9, 1.8, 2.1, -4.3))
        local ra, rb = mirrorX(s * 1.7, s * 2.15)
        B.box(model, "RunningLight", ra, 0.98, -5.56, rb, 1.14, -5.5, AMBER, Enum.Material.Neon, DECOR)
    end
    for _, s in ipairs({ -1, 1 }) do
        B.wheel(model, s * 2.25, -3.6, 1.05, 0.8)
        B.wheel(model, s * 2.25, 3.5, 1.05, 0.8)
    end
    return { halfLen = 5.6, width = 4.7, seatY = 1.75, lenses = lenses,
        tail = { -2.2, 1.24, 5.5, 2.2, 1.46, 5.56 }, trunk = { -1.4, 0.95, 5.5, 1.4, 1.2, 5.6 },
        exhausts = { { -1.0, 0.74, 5.5 }, { 1.0, 0.74, 5.5 } }, glow = { 0.45, 2.0, 2.2, -4.4, 4.4 },
        cabin = Vector3.new(0, 2.2, 0.9), rearBack = false }
end

-- MUSCLE CAR: long hood + scoop, rally stripes, ducktail, fat rear tyres
BODIES.muscle = function(model, P)
    local B = Build
    B.box(model, "LowerBody", -2.3, 0.7, -6.0, 2.3, 1.75, 5.8, P, SM, PAINT)
    B.box(model, "Hood", -2.3, 1.75, -6.0, 2.3, 2.15, -1.4, P, SM, PAINT)
    B.box(model, "HoodScoop", -0.75, 2.15, -4.4, 0.75, 2.5, -2.2, BLACK, Enum.Material.Metal)
    B.box(model, "ScoopMouth", -0.6, 2.2, -4.45, 0.6, 2.42, -4.4, TRIM, Enum.Material.Metal, DECOR)
    B.box(model, "CockpitWallL", -2.3, 1.75, -1.4, -1.9, 2.35, 3.4, P, SM, PAINT)
    B.box(model, "CockpitWallR", 1.9, 1.75, -1.4, 2.3, 2.35, 3.4, P, SM, PAINT)
    B.box(model, "Dash", -1.9, 1.75, -1.4, 1.9, 2.3, -0.95, LEATHER, Enum.Material.Fabric)
    B.box(model, "Bulkhead", -1.9, 1.75, 3.0, 1.9, 2.75, 3.4, LEATHER, Enum.Material.Fabric)
    B.box(model, "RearDeck", -2.3, 1.75, 3.4, 2.3, 2.25, 5.8, P, SM, PAINT)
    B.wedge(model, "Ducktail", -2.2, 2.25, 5.1, 2.2, 2.6, 5.8, P, SM, false, PAINT)
    B.wedge(model, "Windscreen", -1.9, 2.15, -1.4, 1.9, 3.2, -0.8, BLACK, Enum.Material.Glass, false, GLASS)
    -- black rally stripes over hood + deck
    for _, s in ipairs({ -1, 1 }) do
        local a, b = mirrorX(s * 0.35, s * 0.8)
        B.box(model, "RallyStripe", a, 2.15, -6.0, b, 2.18, -1.4, BLACK, SM, DECOR)
        B.box(model, "RallyStripe", a, 2.25, 3.4, b, 2.28, 5.1, BLACK, SM, DECOR)
    end
    B.box(model, "Grille", -1.7, 1.05, -6.05, 1.7, 1.65, -6.0, BLACK, Enum.Material.Metal, DECOR)
    B.box(model, "BumperF", -2.4, 0.55, -6.25, 2.4, 1.0, -6.0, CHROME, Enum.Material.Metal, { Reflectance = 0.2 })
    B.box(model, "BumperR", -2.4, 0.55, 5.8, 2.4, 1.0, 6.05, CHROME, Enum.Material.Metal, { Reflectance = 0.2 })
    local lenses = {}
    for _, s in ipairs({ -1, 1 }) do
        table.insert(lenses, lens(model, nil, s * 1.85, s * 2.2, 1.2, 1.55, -6.0))
        -- side pipes along the sills
        local a, b = mirrorX(s * 2.3, s * 2.45)
        B.box(model, "SidePipe", a, 0.62, -0.5, b, 0.84, 3.0, CHROME, Enum.Material.Metal, { CanCollide = false, CanTouch = false, Reflectance = 0.2 })
    end
    for _, s in ipairs({ -1, 1 }) do
        B.wheel(model, s * 2.2, -3.9, 1.05, 0.8)
        B.wheel(model, s * 2.2, 3.8, 1.2, 0.95)   -- fat rears
    end
    return { halfLen = 6.1, width = 4.8, seatY = 1.95, lenses = lenses,
        tail = { -2.2, 1.3, 5.8, 2.2, 1.6, 5.86 }, trunk = { -1.1, 1.1, 5.8, 1.1, 1.3, 5.9 },
        exhausts = { { -1.3, 0.7, 6.05 }, { 1.3, 0.7, 6.05 } }, glow = { 0.45, 2.0, 2.2, -4.6, 4.6 },
        cabin = Vector3.new(0, 2.4, 0.9), rearBack = false }
end

-- STREET RACER: a low, wide Lambo-style wedge with side intakes and a big wing
BODIES.racer = function(model, P)
    local B = Build
    local CARBON = Color3.fromRGB(26, 26, 30)
    B.box(model, "LowerBody", -2.45, 0.45, -5.6, 2.45, 1.15, 5.8, P, SM, PAINT)
    B.wedge(model, "Nose", -2.45, 1.15, -5.6, 2.45, 1.6, -1.6, P, SM, false, PAINT)
    B.box(model, "Splitter", -2.5, 0.3, -5.9, 2.5, 0.45, -5.3, CARBON, SM)
    B.box(model, "CockpitWallL", -2.45, 1.15, -1.6, -2.0, 1.75, 2.8, P, SM, PAINT)
    B.box(model, "CockpitWallR", 2.0, 1.15, -1.6, 2.45, 1.75, 2.8, P, SM, PAINT)
    B.box(model, "Dash", -2.0, 1.15, -1.6, 2.0, 1.6, -1.2, LEATHER, Enum.Material.Fabric)
    B.wedge(model, "Windscreen", -1.9, 1.6, -1.6, 1.9, 2.6, -0.6, BLACK, Enum.Material.Glass, false, GLASS)
    B.box(model, "Bulkhead", -2.0, 1.15, 2.8, 2.0, 2.3, 3.0, LEATHER, Enum.Material.Fabric)
    B.box(model, "EngineCover", -2.45, 1.15, 3.0, 2.45, 1.95, 5.8, P, SM, PAINT)
    for i = 0, 4 do   -- engine vents
        local z = 3.3 + i * 0.45
        B.box(model, "Vent", -1.5, 1.95, z, 1.5, 2.0, z + 0.2, CARBON, Enum.Material.Metal, DECOR)
    end
    -- side intakes (the Lambo look)
    for _, s in ipairs({ -1, 1 }) do
        local a, b = mirrorX(s * 2.45, s * 2.5)
        B.wedge(model, "Intake", a, 1.2, 0.6, b, 1.85, 2.8, CARBON, SM, false, DECOR)
        local sa, sb = mirrorX(s * 2.45, s * 2.5)
        B.box(model, "SideStripe", sa, 0.75, -5.2, sb, 0.85, 5.4, BLACK, SM, DECOR)
    end
    -- big rear wing on two struts
    for _, x in ipairs({ -1.3, 1.3 }) do
        B.box(model, "WingStrut", x - 0.1, 1.95, 4.9, x + 0.1, 2.65, 5.15, CARBON, SM, DECOR)
    end
    B.box(model, "Wing", -2.4, 2.65, 4.6, 2.4, 2.8, 5.7, CARBON, SM, DECOR)
    for _, s in ipairs({ -1, 1 }) do
        local a, b = mirrorX(s * 2.3, s * 2.4)
        B.box(model, "WingPlate", a, 2.45, 4.55, b, 2.95, 5.75, CARBON, SM, DECOR)
    end
    B.box(model, "Diffuser", -2.2, 0.3, 5.6, 2.2, 0.75, 5.95, CARBON, SM)
    local lenses = {}
    for _, s in ipairs({ -1, 1 }) do
        table.insert(lenses, lens(model, nil, s * 1.2, s * 2.3, 0.95, 1.1, -5.6))
    end
    for _, s in ipairs({ -1, 1 }) do
        B.wheel(model, s * 2.2, -3.7, 0.95, 0.9)
        B.wheel(model, s * 2.2, 3.6, 1.0, 0.95)
    end
    return { halfLen = 5.9, width = 4.9, seatY = 1.35, lenses = lenses,
        tail = { -2.3, 1.3, 5.8, 2.3, 1.45, 5.86 }, trunk = { -1.2, 0.85, 5.8, 1.2, 1.1, 5.9 },
        exhausts = { { -0.5, 0.95, 5.8 }, { 0.5, 0.95, 5.8 } }, glow = { 0.3, 2.0, 2.2, -4.6, 4.6 },
        cabin = Vector3.new(0, 1.8, 0.9), rearBack = false }
end

-- ARMORED TRUCK: bull bar, steel plates, slit windscreen, armoured cargo box
BODIES.armored = function(model, P)
    local B = Build
    local PLATE = P:Lerp(Color3.new(0, 0, 0), 0.25)
    local YEL = Color3.fromRGB(245, 196, 40)
    B.box(model, "LowerBody", -2.4, 0.9, -6.2, 2.4, 2.2, 6.2, P, Enum.Material.Metal)
    B.box(model, "EngineBox", -2.4, 2.2, -6.2, 2.4, 3.0, -2.4, P, Enum.Material.Metal)
    B.box(model, "ArmorFront", -2.4, 3.0, -2.45, 2.4, 4.4, -2.1, PLATE, Enum.Material.DiamondPlate)
    for _, s in ipairs({ -1, 1 }) do   -- vision slits
        local a, b = mirrorX(s * 0.4, s * 2.0)
        B.box(model, "Slit", a, 3.55, -2.5, b, 3.95, -2.44, BLACK, Enum.Material.Glass, GLASS)
    end
    for _, s in ipairs({ -1, 1 }) do
        local a, b = mirrorX(s * 2.4, s * 2.55)
        B.box(model, "SidePlate", a, 1.2, -2.4, b, 3.3, 3.2, PLATE, Enum.Material.DiamondPlate)
        for _, z in ipairs({ -1.8, -0.2, 1.4, 2.8 }) do   -- bolts
            local ba, bb = mirrorX(s * 2.55, s * 2.6)
            B.box(model, "Bolt", ba, 3.0, z, bb, 3.15, z + 0.15, CHROME, Enum.Material.Metal, GHOST)
        end
        local ya, yb = mirrorX(s * 2.4, s * 2.46)
        B.box(model, "HazardStripe", ya, 1.3, 3.2, yb, 1.55, 6.1, YEL, SM, DECOR)
    end
    B.box(model, "Dash", -2.0, 2.2, -2.1, 2.0, 2.9, -1.3, LEATHER, Enum.Material.Fabric)
    -- the armoured cargo box behind the back seats
    B.box(model, "CargoBox", -2.55, 2.2, 3.2, 2.55, 5.4, 6.2, P, Enum.Material.Metal)
    B.box(model, "CargoRoofRim", -2.55, 5.4, 3.2, 2.55, 5.55, 6.2, PLATE, Enum.Material.DiamondPlate)
    B.box(model, "RearDoorSeam", -0.04, 2.3, 6.2, 0.04, 5.3, 6.24, BLACK, SM, GHOST)
    B.box(model, "Beacon", -0.3, 5.55, 4.4, 0.3, 5.9, 5.0, AMBER, Enum.Material.Neon, DECOR)
    -- bull bar
    B.box(model, "BullBar", -2.2, 0.7, -6.45, 2.2, 1.0, -6.2, BLACK, Enum.Material.Metal)
    B.box(model, "BullBarTop", -2.2, 2.3, -6.45, 2.2, 2.55, -6.2, BLACK, Enum.Material.Metal)
    for _, x in ipairs({ -1.9, -0.6, 0.6, 1.9 }) do
        B.box(model, "BullBarPost", x - 0.12, 1.0, -6.45, x + 0.12, 2.3, -6.25, BLACK, Enum.Material.Metal)
    end
    B.box(model, "BumperR", -2.4, 0.7, 6.2, 2.4, 1.2, 6.4, BLACK, Enum.Material.Metal)
    local lenses = {}
    for _, s in ipairs({ -1, 1 }) do
        table.insert(lenses, lens(model, nil, s * 1.3, s * 2.1, 1.6, 2.1, -6.2))
    end
    for _, s in ipairs({ -1, 1 }) do
        B.wheel(model, s * 2.2, -4.2, 1.25, 1.0)
        B.wheel(model, s * 2.2, 4.2, 1.25, 1.0)
    end
    return { halfLen = 6.4, width = 4.9, seatY = 2.4, lenses = lenses,
        tail = { -2.3, 2.4, 6.2, -1.6, 2.8, 6.26 }, tail2 = { 1.6, 2.4, 6.2, 2.3, 2.8, 6.26 },
        trunk = { -1.2, 1.5, 6.2, 1.2, 2.0, 6.3 },
        exhausts = { { -1.6, 0.95, 6.4 } }, glow = { 0.5, 1.9, 2.1, -4.8, 4.8 },
        cabin = Vector3.new(0, 2.9, 0.9), rearBack = true }
end

-- MONSTER TRUCK: a pickup on a lift kit with 4-stud wheels
BODIES.monster = function(model, P)
    local B = Build
    local FLAME = Color3.fromRGB(255, 150, 30)
    local SPRING = Color3.fromRGB(250, 210, 40)
    B.box(model, "Chassis", -1.6, 2.6, -5.6, 1.6, 3.2, 5.6, BLACK, Enum.Material.Metal)
    for _, z in ipairs({ -3.9, 3.9 }) do
        B.box(model, "Axle", -2.1, 1.85, z - 0.2, 2.1, 2.15, z + 0.2, TRIM, Enum.Material.Metal, DECOR)
        for _, x in ipairs({ -1.3, 1.3 }) do
            B.box(model, "Spring", x - 0.22, 2.1, z - 0.22, x + 0.22, 3.2, z + 0.22, SPRING, Enum.Material.Metal, DECOR)
        end
    end
    B.box(model, "LowerBody", -1.9, 3.2, -6.2, 1.9, 4.2, 6.2, P, SM, PAINT)
    B.box(model, "Hood", -1.9, 4.2, -6.2, 1.9, 4.7, -1.6, P, SM, PAINT)
    B.wedge(model, "Windscreen", -1.8, 4.7, -1.6, 1.8, 5.7, -1.0, BLACK, Enum.Material.Glass, false, GLASS)
    B.box(model, "Dash", -1.7, 4.2, -1.6, 1.7, 4.8, -1.2, LEATHER, Enum.Material.Fabric)
    for _, s in ipairs({ -1, 1 }) do
        local a, b = mirrorX(s * 1.7, s * 1.9)
        B.box(model, "DoorWall", a, 4.2, -1.6, b, 4.95, 1.2, P, SM, PAINT)
        B.box(model, "BedWall", a, 4.2, 1.2, b, 5.0, 6.2, P, SM, PAINT)
        -- flames down the sides
        local fa, fb = mirrorX(s * 1.9, s * 1.93)
        for i = 0, 3 do
            local z = -5.6 + i * 1.2
            B.wedge(model, "Flame", fa, 3.35, z, fb, 4.05, z + 1.4, i % 2 == 0 and FLAME or Color3.fromRGB(255, 220, 60), SM, true, GHOST)
        end
        -- exhaust stacks behind the cab
        local ea, eb = mirrorX(s * 1.75, s * 2.05)
        B.box(model, "Stack", ea, 4.3, 0.9, eb, 6.4, 1.2, CHROME, Enum.Material.Metal, { CanCollide = false, CanTouch = false, Reflectance = 0.2 })
    end
    B.box(model, "Tailgate", -1.9, 4.2, 6.0, 1.9, 5.0, 6.2, P, SM, PAINT)
    -- roll bar with a light bar
    for _, x in ipairs({ -1.75, 1.75 }) do
        B.box(model, "RollBarPost", x - 0.12, 4.2, 0.9, x + 0.12, 6.9, 1.12, BLACK, Enum.Material.Metal)
    end
    B.box(model, "RollBarTop", -1.87, 6.7, 0.9, 1.87, 6.9, 1.12, BLACK, Enum.Material.Metal)
    for i = 0, 3 do
        local x = -1.2 + i * 0.8
        B.box(model, "RoofLamp", x - 0.25, 6.9, 0.88, x + 0.25, 7.15, 1.08, AMBER, Enum.Material.Neon, GHOST)
    end
    B.box(model, "BumperF", -2.0, 2.6, -6.5, 2.0, 3.4, -6.2, BLACK, Enum.Material.Metal)
    B.box(model, "BumperR", -2.0, 2.6, 6.2, 2.0, 3.3, 6.45, BLACK, Enum.Material.Metal)
    local lenses = {}
    for _, s in ipairs({ -1, 1 }) do
        table.insert(lenses, lens(model, nil, s * 0.9, s * 1.7, 3.7, 4.05, -6.2))
    end
    for _, s in ipairs({ -1, 1 }) do
        B.wheel(model, s * 2.15, -3.9, 2.0, 1.1)
        B.wheel(model, s * 2.15, 3.9, 2.0, 1.1)
    end
    return { halfLen = 6.4, width = 5.0, seatY = 4.4, lenses = lenses,
        tail = { -1.85, 4.3, 6.2, -1.3, 4.7, 6.26 }, tail2 = { 1.3, 4.3, 6.2, 1.85, 4.7, 6.26 },
        trunk = { -1.1, 4.3, 6.2, 1.1, 4.8, 6.3 },
        exhausts = { { -1.0, 2.95, 6.45 }, { 1.0, 2.95, 6.45 } }, glow = { 2.45, 1.4, 1.6, -5.2, 5.2 },
        cabin = Vector3.new(0, 4.9, 0.9), rearBack = true }
end

-- TANK: treads, sloped glacis, open crew hull, a big cartoon turret at the back
BODIES.tank = function(model, P)
    local B = Build
    local DARK = P:Lerp(Color3.new(0, 0, 0), 0.3)
    local TREAD = Color3.fromRGB(38, 38, 40)
    for _, s in ipairs({ -1, 1 }) do
        local a, b = mirrorX(s * 1.9, s * 2.7)
        B.box(model, "Tread", a, 0.1, -5.4, b, 1.8, 5.4, TREAD, Enum.Material.DiamondPlate)
        for _, z in ipairs({ -5.4, 5.4 }) do
            B.part({ Name = "Sprocket", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 1.7, 1.7),
                CFrame = CFrame.new(s * 2.3, 0.95, z), Color = TREAD, Material = Enum.Material.Metal,
                CanCollide = false, CanTouch = false }, model)
        end
        for i = 0, 4 do   -- road-wheel hubs on the outside
            local z = -3.6 + i * 1.8
            B.part({ Name = "RoadWheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 1.1, 1.1),
                CFrame = CFrame.new(s * 2.69, 0.9, z), Color = DARK, Material = Enum.Material.Metal,
                CanCollide = false, CanTouch = false, CanQuery = false }, model)
        end
        local fa, fb = mirrorX(s * 1.9, s * 2.72)
        B.box(model, "Fender", fa, 1.8, -5.8, fb, 2.0, 5.8, P, Enum.Material.Metal)
        local wa, wb = mirrorX(s * 1.6, s * 1.9)
        B.box(model, "HullWall", wa, 2.2, -3.2, wb, 3.0, 3.0, P, Enum.Material.Metal)
    end
    B.box(model, "Hull", -1.9, 0.6, -5.9, 1.9, 2.2, 6.0, P, Enum.Material.Metal)
    B.wedge(model, "Glacis", -1.9, 2.2, -5.9, 1.9, 3.0, -3.2, P, Enum.Material.Metal, false)
    B.box(model, "Dash", -1.6, 2.2, -3.2, 1.6, 2.9, -2.6, LEATHER, Enum.Material.Fabric)
    -- turret (raised so the barrel clears the crew's heads)
    B.box(model, "TurretRing", -1.7, 2.2, 3.0, 1.7, 3.2, 6.0, DARK, Enum.Material.Metal)
    B.box(model, "TurretNeck", -1.2, 3.2, 3.4, 1.2, 5.2, 5.6, DARK, Enum.Material.Metal)
    B.box(model, "Turret", -1.8, 5.2, 3.1, 1.8, 6.9, 6.0, P, Enum.Material.Metal)
    B.wedge(model, "TurretFace", -1.8, 5.2, 2.5, 1.8, 6.9, 3.1, P, Enum.Material.Metal, false)
    B.box(model, "Hatch", -0.6, 6.9, 4.1, 0.6, 7.1, 5.3, DARK, Enum.Material.Metal)
    B.box(model, "Mantlet", -0.5, 5.9, 2.3, 0.5, 6.7, 2.6, DARK, Enum.Material.Metal)
    B.part({ Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8.8, 0.55, 0.55),
        CFrame = CFrame.new(0, 6.3, -2.1) * CFrame.Angles(0, math.rad(90), 0), Color = DARK,
        Material = Enum.Material.Metal, CanCollide = false, CanTouch = false }, model)
    B.part({ Name = "Muzzle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 0.8, 0.8),
        CFrame = CFrame.new(0, 6.3, -6.35) * CFrame.Angles(0, math.rad(90), 0), Color = TREAD,
        Material = Enum.Material.Metal, CanCollide = false, CanTouch = false }, model)
    -- a white star on each side of the turret
    for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
        local turret = model:FindFirstChild("Turret")
        if turret then
            local g = Instance.new("SurfaceGui")
            g.Face = face
            g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
            g.PixelsPerStud = 40
            g.LightInfluence = 0.6
            g.Parent = turret
            local l = Instance.new("TextLabel")
            l.BackgroundTransparency = 1
            l.Size = UDim2.fromScale(1, 1)
            l.Text = "★"
            l.TextScaled = true
            l.TextColor3 = Color3.fromRGB(240, 240, 232)
            l.Parent = g
        end
    end
    local lenses = {}
    for _, s in ipairs({ -1, 1 }) do
        table.insert(lenses, lens(model, nil, s * 1.1, s * 1.6, 1.5, 1.85, -5.9))
    end
    return { halfLen = 6.3, width = 5.4, seatY = 2.4, lenses = lenses,
        tail = { -1.8, 1.7, 6.0, -1.3, 1.95, 6.06 }, tail2 = { 1.3, 1.7, 6.0, 1.8, 1.95, 6.06 },
        trunk = { -1.1, 1.1, 6.0, 1.1, 1.5, 6.1 },
        exhausts = { { -1.4, 2.0, 6.0 }, { 1.4, 2.0, 6.0 } }, glow = { 0.35, 1.5, 1.7, -5.0, 5.0 },
        cabin = Vector3.new(0, 2.9, 0.9), rearBack = true }
end

VehicleService.CAR_TYPES = { "classic", "muscle", "racer", "armored", "monster", "tank" }

-- (v2.2) stats + colour per car id, from CosmeticsService (loaded lazily, optional)
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

local DEFAULT_STATS = { id = "CarClassic", name = "Classic", carType = "classic", speedMult = 1, bustMult = 1,
    nitroCooldown = TUNE.NITRO_COOLDOWN, perk = "", color = WHITE }

local function statsFor(carId)
    local C = cosmetics()
    if C and type(C.carStats) == "function" then
        local ok, st = pcall(C.carStats, C, carId)
        if ok and type(st) == "table" and BODIES[st.carType] then return st end
    end
    return DEFAULT_STATS
end

-- build one car model (no wiring) for a car id. Returns the parts table.
local function buildCarModel(carId)
    local stats = statsFor(carId)
    local model = Instance.new("Model")
    model.Name = "GetawayCar"
    local root = Build.part({
        Name = "Root", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(),
        Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false,
    }, model)
    model.PrimaryPart = root
    local spec = BODIES[stats.carType](model, stats.color or WHITE)
    if spec.tail2 then   -- split taillights (trucks / tank): a second strip
        local t = spec.tail2
        Build.box(model, "Taillights", t[1], t[2], t[3], t[4], t[5], t[6], RED_LIGHT, Enum.Material.Neon, DECOR)
    end
    local k = kit(model, spec)
    model:SetAttribute("CarId", stats.id)
    model:SetAttribute("CarType", stats.carType)
    model:SetAttribute("CarName", stats.name)
    model:SetAttribute("CarPerk", stats.perk)
    return {
        model = model, root = root, driverSeat = k.driverSeat, seats = k.seats, trunk = k.trunk,
        glow = k.glow, underLight = k.underLight, cabinLight = k.cabinLight,
        headlights = k.headlights, exhausts = k.exhausts,
        halfLen = spec.halfLen, width = spec.width, stats = stats,
    }
end
VehicleService._buildCarModel = buildCarModel   -- (tests / previews)

-- ──────────────────────────────────────────────
-- Car object
-- ──────────────────────────────────────────────
local Car = {}
Car.__index = Car

local callbacks = {}
local currentCar = nil
local crewLocked = false   -- (v2.2) chooseForCrew picked this run's car; no lobby swaps until reset
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

-- (v2.0 car colours were retired in v2.2 — colour is part of each car type.
-- Kept as a no-op so an old caller can't error.)
function Car:applyPaint(_player) end

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
    -- (v2.2) the run is over: the club car goes back to "best car in the server"
    if currentCar == self and crewLocked then
        crewLocked = false
        task.defer(function() VehicleService:refreshType() end)
    end
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
    for _, c in ipairs(self.seatConns or {}) do c:Disconnect() end
    self.seatConns = {}
    if self.ancestryConn then self.ancestryConn:Disconnect() self.ancestryConn = nil end
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

    -- (v2.2) car type: speedMult scales top speed, acceleration and nitro
    local sm = self.speedMult or 1
    local maxF = TUNE.MAX_FORWARD * sm
    if driver and driver:GetAttribute("Role") == "Driver" then
        maxF = maxF * TUNE.DRIVER_MULT
    end
    local accel = TUNE.ACCEL * sm
    local nitroUntil = tonumber(model:GetAttribute("NitroUntil")) or 0
    local nitroOn = driverHum ~= nil and not self.frozen and now < nitroUntil
    if nitroOn and throttle >= 0 then
        maxF = math.max(maxF, TUNE.NITRO_MAX * sm)
        accel = TUNE.NITRO_ACCEL * sm
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

    table.insert(self.seatConns, prompt.Triggered:Connect(function(player)
        if self.destroyed or seat.Occupant then return end
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 or hum.SeatPart then return end
        pcall(function() seat:Sit(hum) end)
    end))

    table.insert(self.seatConns, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
        prompt.Enabled = seat.Occupant == nil
        if isDriver then
            local driver = self:getDriver()
            fire(callbacks.onDriverChanged, self, driver)
        end
    end))
end

-- copy a freshly built parts table onto the car object
function Car:_adopt(parts)
    self.model = parts.model
    self.root = parts.root
    self.driverSeat = parts.driverSeat
    self.seats = parts.seats
    self.glow = parts.glow
    self.underLight = parts.underLight
    self.cabinLight = parts.cabinLight
    self.headlights = parts.headlights
    self.exhausts = parts.exhausts
    self.halfLen = parts.halfLen or CAR_HALF_LEN
    self.width = parts.width or CAR_WIDTH
    local st = parts.stats or {}
    self.carId = st.id or "CarClassic"
    self.carType = st.carType or "classic"
    self.speedMult = tonumber(st.speedMult) or 1
    self.bustMult = tonumber(st.bustMult) or 1        -- PoliceService scales the bust fill by this
    self.nitroCooldown = tonumber(st.nitroCooldown) or TUNE.NITRO_COOLDOWN
    self._flames = nil
    self._phase = nil
    parts.model:SetAttribute("NitroCooldown", self.nitroCooldown)
    parts.model:SetAttribute("SpeedMult", self.speedMult)
    parts.model:SetAttribute("BustMult", self.bustMult)
    CollectionService:AddTag(parts.model, "GetawayCar")
    self.seatConns = {}
    for i, seat in ipairs(self.seats) do
        self:_wireSeat(seat, i == 1)
    end
    if self.ancestryConn then self.ancestryConn:Disconnect() end
    local model = parts.model
    self.ancestryConn = model.AncestryChanged:Connect(function()
        if self.model == model and not model:IsDescendantOf(game) then self:destroy() end
    end)
end

-- (v2.2) swap this car to another type IN PLACE: same car object (JobService /
-- PoliceService / BotService keep their reference), same TRUNK part (so
-- LootService's "Load bag" prompt and its closures keep working), new body.
-- Everyone is ejected first. Returns true if it changed.
function Car:setType(carId)
    if self.destroyed then return false end
    local stats = statsFor(carId)
    if stats.id == self.carId then return false end
    self:ejectAll()
    local old = self.model
    local oldTrunk = self.trunk
    local parts = buildCarModel(stats.id)
    -- keep the old trunk instance: move it onto the new body's trunk spot
    if oldTrunk and oldTrunk.Parent and parts.trunk then
        oldTrunk.Size = parts.trunk.Size
        oldTrunk.CFrame = parts.trunk.CFrame
        oldTrunk.Parent = parts.model
        parts.trunk:Destroy()
        parts.trunk = oldTrunk
    end
    self.trunk = parts.trunk
    -- carry the live attributes over (Bags, Alarm, nitro timers, bust meter…)
    for _, key in ipairs({ "Speed", "BustMeter", "NitroUntil", "NitroReadyAt", "Alarm", "Bags" }) do
        local v = old and old:GetAttribute(key)
        if v ~= nil then parts.model:SetAttribute(key, v) end
    end
    for _, c in ipairs(self.seatConns or {}) do c:Disconnect() end
    self.seatConns = {}
    if self.ancestryConn then self.ancestryConn:Disconnect() self.ancestryConn = nil end
    self:_adopt(parts)
    parts.model:PivotTo(carCFrame(self.pos, self.yaw))
    parts.model.Parent = (old and old.Parent) or Workspace
    if old then old:Destroy() end
    self:setAlarmMode(self.alarm)
    fire(callbacks.onTypeChanged, self, self.carId)
    return true
end

local function newCar(cframe, carId)
    local parts = buildCarModel(carId)
    local self = setmetatable({
        trunk = parts.trunk,
        pos = Vector3.zero,
        yaw = 0,
        v = 0,
        frozen = false,
        alarm = false,
        dropoffFired = false,
        destroyed = false,
        connections = {},
        seatConns = {},
    }, Car)
    local model = parts.model
    model:SetAttribute("Speed", 0)
    model:SetAttribute("BustMeter", 0)
    model:SetAttribute("NitroUntil", 0)
    model:SetAttribute("NitroReadyAt", 0)
    model:SetAttribute("Alarm", false)
    self:_adopt(parts)

    -- place first (probes exclude this model anyway), then parent, so the car
    -- never flashes at the world origin for a frame
    self:_placeAt(typeof(cframe) == "CFrame" and cframe or CFrame.new(
        W.GETAWAY_POSITION.x, W.GETAWAY_POSITION.y, W.GETAWAY_POSITION.z))
    model.Parent = Workspace
    return self
end

-- (v2.2) the crew's best car id for a list of players (CosmeticsService rule)
local function pickFor(players)
    local C = cosmetics()
    if C and type(C.pickCrewCar) == "function" then
        local ok, id = pcall(C.pickCrewCar, C, players)
        if ok and type(id) == "string" then return id end
    end
    return "CarClassic"
end

-- (v2.2) one preview model per car type in ReplicatedStorage.HC_CarPreviews
-- (ShopUI clones them into its ViewportFrames, so the shop shows the REAL car)
local function publishPreviews()
    local folder = ReplicatedStorage:FindFirstChild("HC_CarPreviews")
    if folder then folder:Destroy() end
    folder = Instance.new("Folder")
    folder.Name = "HC_CarPreviews"
    local C = cosmetics()
    for _, item in ipairs((C and C.ITEMS) or {}) do
        if item.category == "car" and item.carType and BODIES[item.carType] then
            local ok, parts = pcall(buildCarModel, item.id)
            if ok and parts then
                local m = parts.model
                m.Name = item.id
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("Light") then d:Destroy()
                    elseif d:IsA("BasePart") then d.CanCollide = false d.CanTouch = false d.CanQuery = false end
                end
                m.Parent = folder
            end
        end
    end
    folder.Parent = ReplicatedStorage
end

-- ──────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────
function VehicleService:init(cb)
    cb = cb or {}
    callbacks.onDropoff = cb.onDropoff
    callbacks.onDriverChanged = cb.onDriverChanged
    callbacks.onTypeChanged = cb.onTypeChanged or callbacks.onTypeChanged
    if initialized then return end
    initialized = true
    local okP, errP = pcall(publishPreviews)
    if not okP then warn("[VehicleService] car previews:", errP) end

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
        car.model:SetAttribute("NitroReadyAt", now + (car.nitroCooldown or TUNE.NITRO_COOLDOWN))
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

-- carId optional: default = the best car anyone in the server has equipped
function VehicleService:spawnGetaway(cframe, carId)
    if currentCar then currentCar:destroy() end
    crewLocked = false
    currentCar = newCar(cframe, carId or pickFor(Players:GetPlayers()))
    return currentCar
end

-- (v2.2) JobService calls this at the drop-in with the crew: the car becomes
-- the crew's best car and stays that type until it resets after the run.
function VehicleService:chooseForCrew(players)
    local car = self:getCar()
    local id = pickFor(players or Players:GetPlayers())
    if car then
        car:setType(id)
        crewLocked = true
    end
    return id
end

-- (v2.2) in the club: re-pick from everyone in the server (someone equipped a
-- new car / joined / left). Never swaps mid-run, never with people inside.
function VehicleService:refreshType()
    local car = self:getCar()
    if not car or crewLocked or car.frozen or #car:getOccupants() > 0 then return false end
    return car:setType(pickFor(Players:GetPlayers()))
end

function VehicleService:refreshPaint()   -- (v2.0 name, kept for old callers)
    return self:refreshType()
end

function VehicleService:isCrewLocked()
    return crewLocked
end

function VehicleService:getCar()
    if currentCar and currentCar.destroyed then currentCar = nil end
    return currentCar
end

return VehicleService
