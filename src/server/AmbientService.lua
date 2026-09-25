--[[
    HEIST CREW — AmbientService
    ────────────────────────────────────────────────
    v2.0 "BIGGER" (2026-09-25). Makes Ocean Drive feel lived-in:
      • TRAFFIC — up to 6 low-poly 80s cars (MiamiBuilder.buildCar) cruising the
        two lanes of Ocean Drive: eastbound z -10, westbound z -18, x -150..150.
        At the street end a car fades out and re-enters at the other end.
      • PEDESTRIANS — up to 10 R15 NPCs (NpcFactory) strolling back and forth
        along the sidewalks, idling at the ends of their beat. They never leave
        the sidewalk, so they can never walk into a job interior.

    RULES (docs/V2_SPEC.md §8):
      • Traffic yields. A player ahead in the lane (≤ ~10 studs from the bumper)
        → the car brakes and waits. Waits more than 4 s → it "skips": fades out,
        re-appears past them (or back at the street end), fades in.
      • The getaway car (tag "GetawayCar") or a police cruiser (tag
        "PoliceCruiser") ahead in the lane → the car skips past it straight away,
        so traffic never queues up behind — or stops on — a parked getaway.
      • A traffic car never STOPS on a getaway parking spot
        ((-40,-18) (-40,-10) (44,-10) (80,-10)): if it would have to brake there,
        it skips instead. It stays in its lane the whole time.
      • Pedestrians pause if a player is right in front of them.

    CHEAP BY DESIGN:
      • Cars: every part welded to ONE anchored invisible Root; the service only
        sets Root.CFrame (6 CFrame writes per frame, total). Parts are
        CanQuery=false + CanTouch=false, so VehicleService/PoliceService
        probes, guard LOS rays and touch-to-catch all ignore them. They still
        collide with players (anchored = immovable, and they stop for you).
      • Pedestrians: anchored HumanoidRootPart moved by CFrame (no physics, no
        pathfinding) with the stock R15 walk/idle playing. Parts CanCollide /
        CanQuery / CanTouch off — they are scenery, never in the way.
      • Obstacle scan (players + tagged vehicles) runs 10×/s, not every frame.

    PUBLIC API:
        AmbientService:start(folder?)   build + run traffic and pedestrians.
                                        folder = where the "Ambient" folder goes
                                        (default workspace). Safe to call twice.
        AmbientService:init(deps)       same, deps.folder optional (house style).
        AmbientService:stop()           disconnect + destroy everything.
        AmbientService:setEnabled(on)   pause/resume (cars + people freeze in place).
        AmbientService.CONFIG           tunables (counts, lanes, speeds).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local MiamiBuilder = require(script.Parent.MiamiBuilder)
local NpcFactory = require(script.Parent.NpcFactory)

local AmbientService = {}

local CONFIG = {
    CARS = 6,
    PEDS = 10,
    X_END = 150,             -- street runs x -150..150
    ROAD_Y = 0.2,            -- asphalt top
    LANES = {
        { z = -10, dir = 1,  spots = { -40, 44, 80 } },   -- eastbound (south lane)
        { z = -18, dir = -1, spots = { -40 } },           -- westbound (north lane)
    },
    CRUISE_MIN = 13, CRUISE_MAX = 19,   -- studs/s
    ACCEL = 9, BRAKE = 30,
    CAR_HALF = 5.2,          -- half a car length (bumper to centre)
    FOLLOW_GAP = 15,         -- centre-to-centre distance kept behind another traffic car
    YIELD_GAP = 10,          -- bumper-to-body gap to a player before stopping
    SLOW_RANGE = 26,         -- start easing off this far (centre distance) before a stop
    VEHICLE_SKIP = 34,       -- a getaway/cruiser this close ahead in the lane → skip it
    SPOT_CLEAR = 8,          -- "on a getaway spot" = within this many studs of its x
    PLAYER_WAIT = 4,         -- seconds to wait for a player before skipping past
    LANE_HALF = 4.2,         -- |dz| that counts as "in my lane"
    FADE = 0.35,

    SIDEWALKS = {
        -- walking lines (MiamiBuilder.SIDEWALK) + beats that stay on the pavement.
        -- North skips the marina drive route (x 94..122).
        { side = "north", x0 = -146, x1 = -60 }, { side = "north", x0 = -70, x1 = 10 },
        { side = "north", x0 = 0, x1 = 90 },     { side = "north", x0 = 126, x1 = 148 },
        { side = "south", x0 = -146, x1 = -60 }, { side = "south", x0 = -70, x1 = 20 },
        { side = "south", x0 = 10, x1 = 90 },    { side = "south", x0 = 90, x1 = 146 },
    },
    PED_SPEED_MIN = 4.2, PED_SPEED_MAX = 6.2,
    PED_PASS = 1.4,          -- sidestep toward the kerb when two walkers meet
}
AmbientService.CONFIG = CONFIG

local PAINTS = {
    { Color3.fromRGB(242, 160, 190), Color3.new(1, 1, 1) },
    { Color3.fromRGB(150, 225, 200), Color3.fromRGB(240, 90, 150) },
    { Color3.fromRGB(250, 225, 140), Color3.fromRGB(60, 190, 210), taxi = true },
    { Color3.fromRGB(236, 236, 240), Color3.fromRGB(240, 90, 150) },
    { Color3.fromRGB(190, 170, 235), Color3.new(1, 1, 1) },
    { Color3.fromRGB(70, 74, 90), Color3.fromRGB(250, 170, 90) },
}

local SKIN = {
    Color3.fromRGB(255, 220, 180), Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 140, 100),
    Color3.fromRGB(150, 100, 70), Color3.fromRGB(100, 68, 48),
}
local CLOTHES = {
    Color3.fromRGB(242, 160, 190), Color3.fromRGB(150, 225, 200), Color3.fromRGB(250, 200, 160),
    Color3.fromRGB(190, 170, 235), Color3.fromRGB(245, 240, 230), Color3.fromRGB(80, 170, 220),
    Color3.fromRGB(240, 110, 90), Color3.fromRGB(60, 64, 80),
}
local PANTS = {
    Color3.fromRGB(60, 80, 130), Color3.fromRGB(235, 232, 220), Color3.fromRGB(40, 42, 50),
    Color3.fromRGB(190, 170, 130),
}

local rng = Random.new(1986)
local state = nil      -- { folder, cars, peds, conn, enabled, obstacles, scanAt }

-- ──────────────────────────────────────────────
-- helpers
-- ──────────────────────────────────────────────
local function laneCF(x, lane)
    local p = Vector3.new(x, CONFIG.ROAD_Y, lane.z)
    return CFrame.lookAt(p, p + Vector3.new(lane.dir, 0, 0))
end

local function onSpot(car)
    for _, sx in ipairs(car.lane.spots) do
        if math.abs(car.x - sx) < CONFIG.SPOT_CLEAR then return true end
    end
    return false
end

-- players + tagged vehicles, refreshed 10×/s
local function scanObstacles(s)
    local players, vehicles = {}, {}
    for _, p in ipairs(Players:GetPlayers()) do
        local ch = p.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then table.insert(players, hrp.Position) end
    end
    for _, tag in ipairs({ "GetawayCar", "PoliceCruiser" }) do
        for _, m in ipairs(CollectionService:GetTagged(tag)) do
            if m:IsA("Model") and m:IsDescendantOf(Workspace) then
                local ok, cf = pcall(m.GetPivot, m)
                if ok then table.insert(vehicles, cf.Position) end
            end
        end
    end
    s.obstacles = { players = players, vehicles = vehicles }
end

local function setAlpha(car, a)          -- a = 0 visible … 1 gone
    for _, rec in ipairs(car.parts) do
        rec[1].Transparency = rec[2] + (1 - rec[2]) * a
    end
    for _, l in ipairs(car.lights) do l.Enabled = a < 0.5 end
    for _, g in ipairs(car.guis) do g.Enabled = a < 0.5 end
end

-- is the lane clear around x (for re-entering)?
local function laneClear(s, lane, x, self)
    for _, o in ipairs(s.cars) do
        if o ~= self and o.lane == lane and not o.hidden and math.abs(o.x - x) < CONFIG.FOLLOW_GAP then
            return false
        end
    end
    for _, pos in ipairs(s.obstacles.vehicles) do
        if math.abs(pos.Z - lane.z) < CONFIG.LANE_HALF + 2 and math.abs(pos.X - x) < 14 then return false end
    end
    for _, pos in ipairs(s.obstacles.players) do
        if math.abs(pos.Z - lane.z) < CONFIG.LANE_HALF and math.abs(pos.X - x) < 10 then return false end
    end
    for _, sx in ipairs(lane.spots) do
        if math.abs(x - sx) < CONFIG.SPOT_CLEAR then return false end
    end
    return true
end

-- Fade out → reposition to targetX (or the lane start) → fade in.
local function skip(s, car, targetX)
    if car.busy then return end
    car.busy = true
    task.spawn(function()
        local steps = 5
        for i = 1, steps do
            if state ~= s then return end
            setAlpha(car, i / steps)
            task.wait(CONFIG.FADE / steps)
        end
        car.hidden = true
        local lane = car.lane
        local x = targetX
        if not x or x * lane.dir > CONFIG.X_END - 6 or not laneClear(s, lane, x, car) then
            x = -lane.dir * CONFIG.X_END
            -- wait (hidden) until the entry point is free
            while state == s and not laneClear(s, lane, x, car) do task.wait(0.5) end
            if state ~= s then return end
        end
        car.x = x
        car.speed = car.cruise * 0.6
        car.wait = 0
        car.root.CFrame = laneCF(car.x, lane)
        car.hidden = false
        for i = steps - 1, 0, -1 do
            if state ~= s then return end
            setAlpha(car, i / steps)
            task.wait(CONFIG.FADE / steps)
        end
        car.busy = false
    end)
end

-- ──────────────────────────────────────────────
-- 🚗 traffic
-- ──────────────────────────────────────────────
local function spawnCar(s, index)
    local lane = CONFIG.LANES[(index % #CONFIG.LANES) + 1]
    local paint = PAINTS[((index - 1) % #PAINTS) + 1]
    -- spread along the lane, clear of the getaway spots
    local x
    for _ = 1, 20 do
        x = rng:NextNumber(-CONFIG.X_END + 10, CONFIG.X_END - 10)
        if laneClear(s, lane, x, nil) then break end
    end
    local model, root = MiamiBuilder.buildCar(s.folder, laneCF(x, lane), {
        paint = paint[1], stripe = paint[2], taxi = paint.taxi, lights = true, weld = true, noQuery = true,
        name = "TrafficCar" .. index,
    })
    if not root then
        model:Destroy()
        return
    end
    CollectionService:AddTag(model, "TrafficCar")
    local car = {
        model = model, root = root, lane = lane, x = x,
        cruise = rng:NextNumber(CONFIG.CRUISE_MIN, CONFIG.CRUISE_MAX),
        speed = 0, wait = 0, busy = false, hidden = false,
        parts = {}, lights = {}, guis = {},
    }
    car.speed = car.cruise
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") and d ~= root then
            table.insert(car.parts, { d, d.Transparency })
        elseif d:IsA("Light") then
            table.insert(car.lights, d)
        elseif d:IsA("SurfaceGui") then
            table.insert(car.guis, d)
        end
    end
    table.insert(s.cars, car)
end

local function stepCar(s, car, dt)
    if car.busy then return end
    local lane, dir = car.lane, car.lane.dir
    local target = car.cruise
    local stopFor = nil        -- "player" | "traffic"
    local nearest, nearestX = math.huge, nil

    -- another traffic car ahead in my lane → follow it
    for _, o in ipairs(s.cars) do
        if o ~= car and o.lane == lane and not o.hidden then
            local d = (o.x - car.x) * dir
            if d > 0 and d < nearest then nearest, nearestX, stopFor = d, o.x, "traffic" end
        end
    end
    local stopDist = CONFIG.FOLLOW_GAP

    -- getaway car / cruiser ahead in my lane → skip past it now
    for _, pos in ipairs(s.obstacles.vehicles) do
        if math.abs(pos.Z - lane.z) < CONFIG.LANE_HALF + 1 then
            local d = (pos.X - car.x) * dir
            if d > -4 and d < CONFIG.VEHICLE_SKIP then
                skip(s, car, pos.X + dir * 16)
                return
            end
        end
    end

    -- a player standing/walking in my lane ahead
    for _, pos in ipairs(s.obstacles.players) do
        if math.abs(pos.Z - lane.z) < CONFIG.LANE_HALF and pos.Y < 12 then
            local d = (pos.X - car.x) * dir
            if d > -2 and d < nearest then
                nearest, nearestX, stopFor = d, pos.X, "player"
                stopDist = CONFIG.CAR_HALF + 1 + CONFIG.YIELD_GAP
            end
        end
    end
    if stopFor == "traffic" then stopDist = CONFIG.FOLLOW_GAP end

    if nearest < stopDist + (CONFIG.SLOW_RANGE - CONFIG.FOLLOW_GAP) then
        local t = math.clamp((nearest - stopDist) / (CONFIG.SLOW_RANGE - CONFIG.FOLLOW_GAP), 0, 1)
        target = car.cruise * t
    end

    if target < 0.5 then
        -- about to stand still: never on a getaway spot, never forever for a player
        if onSpot(car) then
            skip(s, car, (nearestX or car.x) + dir * 14)
            return
        end
        if stopFor == "player" then
            car.wait += dt
            if car.wait > CONFIG.PLAYER_WAIT then
                skip(s, car, (nearestX or car.x) + dir * 14)
                return
            end
        end
    else
        car.wait = 0
    end

    if car.speed < target then
        car.speed = math.min(target, car.speed + CONFIG.ACCEL * dt)
    else
        car.speed = math.max(target, car.speed - CONFIG.BRAKE * dt)
    end
    car.x += dir * car.speed * dt

    if car.x * dir > CONFIG.X_END then
        skip(s, car, nil)          -- end of the street → re-enter at the start
        return
    end
    car.root.CFrame = laneCF(car.x, lane)
end

-- ──────────────────────────────────────────────
-- 🚶 pedestrians
-- ──────────────────────────────────────────────
local function sidewalkZ(side)
    local S = MiamiBuilder.SIDEWALK or { northZ = -23.0, southZ = -4.8 }
    return (side == "north") and S.northZ or S.southZ
end

local function spawnPed(s, index)
    local beat = CONFIG.SIDEWALKS[((index - 1) % #CONFIG.SIDEWALKS) + 1]
    local shirt = CLOTHES[rng:NextInteger(1, #CLOTHES)]
    local spec = {
        name = "Pedestrian" .. index,
        bodyColors = {
            head = SKIN[rng:NextInteger(1, #SKIN)],
            torso = shirt,
            arms = shirt,
            legs = PANTS[rng:NextInteger(1, #PANTS)],
        },
    }
    spec.bodyColors.arms = (rng:NextNumber() < 0.5) and spec.bodyColors.head or shirt   -- short vs long sleeves
    if index % 4 == 0 then
        -- a businessman in the Boss's suit (same verified catalog ids as the Boss)
        spec.shirt, spec.pants, spec.hats = 6554200369, 6555797786, nil
    end
    local model, humanoid, root = NpcFactory.build(spec)
    if not model or state ~= s then
        if model then model:Destroy() end
        return
    end
    root.Anchored = true
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false
            d.CanQuery = false
            d.CanTouch = false
        end
    end
    humanoid.WalkSpeed = 0
    local baseZ = sidewalkZ(beat.side)
    local standY = 0.5 + humanoid.HipHeight + root.Size.Y / 2
    local ped = {
        model = model, root = root, beat = beat, baseZ = baseZ, y = standY,
        x = rng:NextNumber(beat.x0, beat.x1), dir = (rng:NextNumber() < 0.5) and 1 or -1,
        speed = rng:NextNumber(CONFIG.PED_SPEED_MIN, CONFIG.PED_SPEED_MAX),
        z = baseZ, pauseUntil = 0, anim = nil, animAt = 0,
        -- the kerb side: +z on the north sidewalk, -z on the south one
        kerb = (beat.side == "north") and 1 or -1,
    }
    model:PivotTo(CFrame.lookAt(Vector3.new(ped.x, standY, baseZ), Vector3.new(ped.x + ped.dir, standY, baseZ)))
    CollectionService:AddTag(model, "Pedestrian")
    model.Parent = s.folder
    ped.ctrl = NpcFactory.animate(humanoid)
    table.insert(s.peds, ped)
end

local function setPedAnim(ped, key, now)
    -- re-assert every ~1 s: the Humanoid.Running hook in NpcFactory may flip an
    -- anchored NPC back to idle
    if ped.anim ~= key or now - ped.animAt > 1 then
        ped.anim, ped.animAt = key, now
        if ped.ctrl then
            ped.ctrl.play(key, (key == "walk") and (ped.speed / 10) or 1)
        end
    end
end

local function stepPed(s, ped, dt, now)
    if now < ped.pauseUntil then
        setPedAnim(ped, "idle", now)
        return
    end
    -- a player right in front → wait a moment
    for _, pos in ipairs(s.obstacles.players) do
        local d = (pos.X - ped.x) * ped.dir
        if d > 0 and d < 4 and math.abs(pos.Z - ped.z) < 2.5 and pos.Y < 10 then
            ped.pauseUntil = now + 0.6
            setPedAnim(ped, "idle", now)
            return
        end
    end
    -- two walkers meeting head-on: the east-walker steps toward the kerb
    local wantZ = ped.baseZ
    if ped.dir > 0 then
        for _, o in ipairs(s.peds) do
            if o ~= ped and o.dir ~= ped.dir and o.beat.side == ped.beat.side then
                local d = (o.x - ped.x) * ped.dir
                if d > -2 and d < 7 then
                    wantZ = ped.baseZ + ped.kerb * CONFIG.PED_PASS
                    break
                end
            end
        end
    end
    ped.z += math.clamp(wantZ - ped.z, -2.5 * dt, 2.5 * dt)

    ped.x += ped.dir * ped.speed * dt
    local b = ped.beat
    if ped.x > b.x1 or ped.x < b.x0 then
        ped.x = math.clamp(ped.x, b.x0, b.x1)
        ped.dir = -ped.dir
        ped.pauseUntil = now + rng:NextNumber(1, 3.5)
    end
    setPedAnim(ped, "walk", now)
    local p = Vector3.new(ped.x, ped.y, ped.z)
    ped.root.CFrame = CFrame.lookAt(p, p + Vector3.new(ped.dir, 0, 0))
end

-- ──────────────────────────────────────────────
-- 🚀 lifecycle
-- ──────────────────────────────────────────────
function AmbientService:start(parentFolder)
    if state then return end
    local f = Instance.new("Folder")
    f.Name = "Ambient"
    f.Parent = parentFolder or Workspace
    local s = { folder = f, cars = {}, peds = {}, enabled = true, scanAt = 0,
        obstacles = { players = {}, vehicles = {} } }
    state = s
    scanObstacles(s)

    for i = 1, CONFIG.CARS do
        local ok, err = pcall(spawnCar, s, i)
        if not ok then warn("[AmbientService] traffic car " .. i .. " failed: " .. tostring(err)) end
    end

    -- NPC builds yield (catalog lookups) — stagger them off the main thread
    task.spawn(function()
        for i = 1, CONFIG.PEDS do
            if state ~= s then return end
            local ok, err = pcall(spawnPed, s, i)
            if not ok then warn("[AmbientService] pedestrian " .. i .. " failed: " .. tostring(err)) end
            task.wait(0.2)
        end
    end)

    s.conn = RunService.Heartbeat:Connect(function(dt)
        if not s.enabled then return end
        dt = math.min(dt, 0.1)
        local now = os.clock()
        if now >= s.scanAt then
            s.scanAt = now + 0.1
            scanObstacles(s)
        end
        for _, car in ipairs(s.cars) do
            local ok, err = pcall(stepCar, s, car, dt)
            if not ok then
                warn("[AmbientService] car step error: " .. tostring(err))
                car.busy = true      -- park the broken one instead of spamming
            end
        end
        for _, ped in ipairs(s.peds) do
            if ped.root.Parent then
                local ok = pcall(stepPed, s, ped, dt, now)
                if not ok then ped.pauseUntil = math.huge end
            end
        end
    end)
    print(string.format("[AmbientService] Ocean Drive is alive — %d cars, %d people on the way 🚗🚶", #s.cars, CONFIG.PEDS))
end

function AmbientService:init(deps)
    self:start(deps and deps.folder or nil)
end

function AmbientService:setEnabled(on)
    if state then state.enabled = (on ~= false) end
end

function AmbientService:stop()
    local s = state
    if not s then return end
    state = nil
    if s.conn then s.conn:Disconnect() end
    s.folder:Destroy()
end

return AmbientService
