--[[
    HEIST CREW — GetawayService  (v3.0 "THE SCORE", getaway agent)
    ────────────────────────────────────────────────
    Nobody drives any more. When the crew is done (JobService decides: the
    driver — or anyone, if the driver seat is empty — presses GO! with at least
    one bag loaded; or everyone still in the run sits in the car AND the alarm
    is on or every bag is loaded) the escape plays as a MOVIE:

      1. VOTE (8 s) — every crew member gets three big cards:
            🚤 BOAT        always open
            🚁 HELICOPTER  only if nobody got caught (jailed / out) this run. +10% cash.
                           A guard sending you back to the door is NOT a catch.
            🛣️ HIGHWAY     the car's power on full display: car bonus ×2
         Majority wins; a tie (or nobody voting) → BOAT. Everyone voted → it
         ends early.
      2. THE SCENE — the server builds ONE payload (tracks, props, camera shots,
         captions) and fires it to every crew member; each client plays it
         locally (client/GetawayCinematic.lua) with copies of the car, the crew,
         the chase cars and the props. The real car never leaves its yard.
         WHY CLIENT-SIDE: a server-moved anchored car replicates at network rate
         and stutters; local copies run at the frame rate on every screen and
         can go anywhere (the highway is 900 studs outside the map) without
         dragging real characters through the world. Everybody still sees the
         same movie, because the server decides everything and sends it once.
      3. After the scene length the server calls ctx.onDone(info) and
         JobService pays out (the PayoutScreen lands over the final shot).

    BONUSES (applied by JobService to the bags' cash — see bonusFor):
        car type: Classic 0 · Muscle 5% · Street Racer 8% · Armored 8% ·
                  Monster 10% · Tank 12%  (VehicleService.GETAWAY_BONUS)
                  → full in a LOUD escape (the alarm went off), half in stealth,
                    ×2 on the Highway.
        Helicopter: +10%.
        DRIVER ROLE "Getaway pro" (v3.0 polish): if someone in the escaping crew
        has Role = "Driver", their vote counts ×2 and the whole crew gets +5%
        (DRIVER_BONUS) on the bags' cash — any route, loud or stealth.

    REMOTE "Getaway" (RemoteEvent, created here — not in Remotes.NAMES yet):
      server → client  { phase = "vote", endsAt, options = {boat=,heli=,highway=}, car = {...}, loud, voters }
                       { phase = "tally", votes = { boat = n, heli = n, highway = n }, voted, voters, mine? }
                       { phase = "decided", route }
                       { phase = "scene", scene = <see buildScene>, crew = {Player}, carModel = Model }
                       { phase = "cancel" }
      client → server  { action = "go" }                 (CarHud's GO! button → ctx callback onGo)
                       { action = "vote", route = "boat" | "heli" | "highway" }

    PUBLIC API:
        GetawayService:init(deps)   deps = { onGo = function(player) end, notify = fn? }
        GetawayService:start(ctx) -> boolean
            ctx = { crew = {Player}, car = car object (VehicleService), jobId,
                    startCFrame = CFrame (the car's yard spot), loud = bool,
                    heliAllowed = bool, onDone = function(info) end,
                    voteTime? = seconds, forceRoute? = route (tests) }
            info = { route, routeName, loud, carType, carId, carName, pct, carPct, heliPct,
                     driverPct, driverName?, duration }
        GetawayService:cancel()
        GetawayService:isBusy() -> boolean
        GetawayService:getPhase() -> "idle" | "vote" | "scene"
        GetawayService.bonusFor(route, loud, carType) -> { total, car, heli, base }
        GetawayService.buildScene(opts) -> scene        -- pure (tests)
            opts = { route, loud, carType, startCFrame, halfLen?, seed?, jobId? }
        GetawayService.voteWeight(player) -> 2 for a Driver, else 1
        GetawayService.driverOf(crew) -> Player? (first Role == "Driver")
        GetawayService.ROUTES / ROUTE_INFO / VOTE_TIME / HELI_BONUS / DRIVER_BONUS / DRIVER_VOTE_WEIGHT

    SCENE FORMAT (client/GetawayCinematic.lua plays it):
        { route, loud, carType, jobId, seed, duration, hold,
          tracks = { car = {keys}, boat? = {keys}, heli? = {keys}, cop1? , cop2? },
              key = { t, p = Vector3 (ground contact), y = yaw, x = pitch?, r = roll?, c = 1? (new segment: no blending across) }
              yaw: CFrame.Angles(0, y, 0).LookVector points where it drives.
          props = { { kind = "Shutter"|"Roadblock", cf = CFrame, t0, t1 } },
          events = { { t, kind = "smash"|"nitro"|"fade"|"hop"|"sirens"|"stamp"|"shake", ... } },
          shots = { { t0, t1, mode = "fixed"|"look"|"chase"|"lookback", ... } },
              lookback = { target, focus = Vector3, dist, side, y?, ahead, lookY } (see lookbackShot)
          captions = { { t, dur, text } }, radio = bool,
          boatCF?, heliSeats?, stunt? = { kind, t, s, cf } }
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local GetawayService = {}

GetawayService.VOTE_TIME = 8
GetawayService.HELI_BONUS = 0.10
GetawayService.DRIVER_BONUS = 0.05        -- Driver role "Getaway pro": +5% for the crew
GetawayService.DRIVER_VOTE_WEIGHT = 2     -- ...and the Driver's escape vote counts x2
GetawayService.ROUTES = { "boat", "heli", "highway" }
GetawayService.ROUTE_INFO = {
    boat = { name = "Boat", icon = "🚤", line = "Speedboat across the ocean" },
    heli = { name = "Helicopter", icon = "🚁", line = "Fly away over the city" },
    highway = { name = "Highway", icon = "🛣️", line = "Floor it out of town" },
}
local REMOTE_NAME = "Getaway"

-- optional siblings
local function sibling(name)
    local mod = script.Parent:FindFirstChild(name)
    if not mod then return nil end
    local ok, r = pcall(require, mod)
    return ok and type(r) == "table" and r or nil
end
local Vehicle = sibling("VehicleService")
local Props = sibling("GetawayProps")

local FALLBACK_BONUS = { classic = 0, muscle = 0.05, racer = 0.08, armored = 0.08, monster = 0.10, tank = 0.12 }
local function carBase(carType)
    if Vehicle and type(Vehicle.bonusFor) == "function" then
        local ok, v = pcall(Vehicle.bonusFor, carType)
        if ok and type(v) == "number" then return v end
    end
    return FALLBACK_BONUS[carType or "classic"] or 0
end

local function round6(x) return math.floor(x * 1e6 + 0.5) / 1e6 end

function GetawayService.bonusFor(route, loud, carType)
    local base = carBase(carType)
    local carPct = base * (loud and 1 or 0.5) * (route == "highway" and 2 or 1)
    local heliPct = route == "heli" and GetawayService.HELI_BONUS or 0
    return { total = round6(carPct + heliPct), car = round6(carPct), heli = round6(heliPct), base = base }
end

-- ══════════════════════════════════════════════════════════════════════
-- SCENE BUILDER (pure: numbers in, tables out)
-- ══════════════════════════════════════════════════════════════════════
local W = Constants.WORLD
local STREET_Z = W.STREET_Z or -14
local LANE_E = STREET_Z + 4      -- eastbound (+X) keeps to the south lane
local LANE_W = STREET_Z - 4      -- westbound
local MARINA_X = 108             -- the marina drive route (MiamiBuilder KEEP_CLEAR x 94..122)
local PIER_X = 103               -- pier deck x 100..106, top y 1.0, from z -114 north
local PIER_Y = 1.0
local KEY_DT = 0.1
local HOLD = 9                   -- seconds of motion after the scene ends (the payout sits over it)

local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function yawOf(dir)
    local f = flat(dir)
    if f.Magnitude < 1e-4 then return 0 end
    f = f.Unit
    return math.atan2(-f.X, -f.Z)
end
local function yawCF(p, yaw) return CFrame.new(p) * CFrame.Angles(0, yaw, 0) end
local function smooth(u) u = math.clamp(u, 0, 1) return u * u * (3 - 2 * u) end
local function r3(n) return math.floor(n * 1000 + 0.5) / 1000 end

-- polyline (Vector3s, y = ground height) → dense samples with rounded corners
local function smoothPath(points, radius)
    local pts = {}
    for _, p in ipairs(points) do
        if #pts == 0 or (p - pts[#pts]).Magnitude > 0.05 then table.insert(pts, p) end
    end
    local out = {}
    local function push(p)
        if #out == 0 or (p - out[#out]).Magnitude > 0.01 then table.insert(out, p) end
    end
    if #pts == 1 then push(pts[1]) end
    for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        local startP = a
        if i > 1 then
            local prev = pts[i - 1]
            local cut = math.min(radius, (a - prev).Magnitude / 2, (b - a).Magnitude / 2)
            startP = a + (b - a).Unit * cut
        end
        local endP = b
        local c = pts[i + 2]
        local cut2 = 0
        if c then
            cut2 = math.min(radius, (b - a).Magnitude / 2, (c - b).Magnitude / 2)
            endP = b - (b - a).Unit * cut2
        end
        local n = math.max(1, math.ceil((endP - startP).Magnitude / 2))
        for k = 0, n do push(startP:Lerp(endP, k / n)) end
        if c and cut2 > 0.01 then
            local q0, q2 = endP, b + (c - b).Unit * cut2
            for k = 1, 8 do
                local u = k / 8
                push(q0 * (1 - u) ^ 2 + b * 2 * (1 - u) * u + q2 * u * u)
            end
        end
    end
    local samples, s = {}, 0
    for i, p in ipairs(out) do
        if i > 1 then s = s + (p - out[i - 1]).Magnitude end
        samples[i] = { p = p, s = s }
    end
    return samples, s
end

-- position on the sample list at arc length s (clamped; extrapolates past the end)
local function posAt(samples, s)
    local n = #samples
    if n == 1 then return samples[1].p end
    if s <= 0 then
        local a, b = samples[1].p, samples[2].p
        local d = (b - a).Magnitude > 1e-4 and (b - a).Unit or Vector3.new(0, 0, -1)
        return a + d * s   -- (extrapolates backwards: chase cars start behind the path)
    end
    if s >= samples[n].s then
        local a, b = samples[n - 1].p, samples[n].p
        local d = (b - a).Magnitude > 1e-4 and (b - a).Unit or Vector3.new(0, 0, -1)
        return b + d * (s - samples[n].s)
    end
    local lo, hi = 1, n
    while hi - lo > 1 do
        local mid = (lo + hi) // 2
        if samples[mid].s <= s then lo = mid else hi = mid end
    end
    local a, b = samples[lo], samples[hi]
    local u = (s - a.s) / math.max(1e-6, b.s - a.s)
    return a.p:Lerp(b.p, u)
end
local function dirAt(samples, s)
    local d = posAt(samples, s + 0.8) - posAt(samples, s - 0.8)
    if flat(d).Magnitude < 1e-4 then d = posAt(samples, s + 2) - posAt(samples, s) end
    return d
end

-- speed profile → { {t, s} } recorded every KEY_DT from t0
-- opts: hold (sit still until this time), v0 (start speed), vmax, accel, stop (brake to 0 at L), extra (keep going past L for this long)
local function schedule(L, opts)
    local t = opts.t0 or 0
    local hold = opts.hold or t
    local v = opts.v0 or 0
    local vmax = opts.vmax
    local a = opts.accel or vmax
    local s = 0
    local list = {}
    local nextRec = t
    local dt = 0.02
    local stopAt = nil
    local limit = t + 120
    while t < limit do
        if t >= nextRec - 1e-9 then
            table.insert(list, { t = r3(t), s = s })
            nextRec = nextRec + KEY_DT
        end
        if stopAt and t >= stopAt then break end
        if t >= hold then
            if opts.stop then
                local brake = a * 1.3
                local need = v * v / (2 * brake)
                if L - s <= need + 0.05 then
                    v = math.max(0, v - brake * dt)
                else
                    v = math.min(vmax, v + a * dt)
                end
                if v <= 0.01 and s > L * 0.5 then
                    s = L
                    stopAt = t
                end
            else
                v = math.min(vmax, v + a * dt)
            end
            s = s + v * dt
            if opts.stop and s >= L then s = L stopAt = stopAt or t end
            if not opts.stop and s >= L and not stopAt then stopAt = t + (opts.extra or 0) end
        end
        t = t + dt
    end
    table.insert(list, { t = r3(t), s = s })
    return list, t
end

local function sAt(sched, t)
    if t <= sched[1].t then return sched[1].s end
    local n = #sched
    if t >= sched[n].t then return sched[n].s end
    for i = 1, n - 1 do
        local a, b = sched[i], sched[i + 1]
        if t >= a.t and t <= b.t then
            local u = (t - a.t) / math.max(1e-6, b.t - a.t)
            return a.s + (b.s - a.s) * u
        end
    end
    return sched[n].s
end
-- like sAt, but before the schedule starts it runs backwards at speed v0
local function sAtExt(sched, t, v0)
    if t < sched[1].t then return sched[1].s - (v0 or 0) * (sched[1].t - t) end
    return sAt(sched, t)
end
local function tAt(sched, s)
    for i = 1, #sched - 1 do
        local a, b = sched[i], sched[i + 1]
        if s >= a.s and s <= b.s and b.s > a.s then
            return a.t + (b.t - a.t) * (s - a.s) / (b.s - a.s)
        end
    end
    return sched[#sched].t
end

-- the car-type stunt as an offset along the path (u = (s - sStunt) / width)
local STUNTS = {
    classic = { style = "weave", amp = 6.2, width = 16, caption = "NEAR MISS!", fling = "none" },
    muscle  = { style = "weave", amp = 6.2, width = 16, caption = "NITRO!", fling = "none", nitro = true },
    racer   = { style = "weave", amp = 5.6, width = 12, caption = "TOO FAST FOR THE COPS!", fling = "none", nitro = true },
    armored = { style = "straight", caption = "BOUNCE! COPS CAN'T STOP US!", fling = "bounce" },
    monster = { style = "jump", height = 9, width = 13, caption = "MONSTER JUMP!", fling = "hop" },
    tank    = { style = "straight", caption = "TANK SMASH!", fling = "fly" },
}
GetawayService.STUNTS = STUNTS

local function stuntOffset(st, s, sSt, right)
    if not st or not sSt then return Vector3.zero end
    if st.style == "weave" then
        local u = (s - sSt) / st.width
        if math.abs(u) >= 1 then return Vector3.zero end
        return right * (st.amp * (1 + math.cos(math.pi * u)) / 2)
    elseif st.style == "jump" then
        local u = (s - sSt) / st.width
        if math.abs(u) >= 1 then return Vector3.zero end
        return Vector3.new(0, st.height * (1 - u * u), 0)
    end
    return Vector3.zero
end

-- keys for a vehicle driving a sample path on a schedule
local function driveKeys(samples, sched, stunt, sSt, firstSegment)
    local function at(s)
        local base = posAt(samples, s)
        local d = flat(dirAt(samples, s))
        d = d.Magnitude > 1e-4 and d.Unit or Vector3.new(0, 0, -1)
        local right = Vector3.new(-d.Z, 0, d.X)
        return base + stuntOffset(stunt, s, sSt, right)
    end
    local keys = {}
    for i, k in ipairs(sched) do
        local p = at(k.s)
        local ahead = at(k.s + 1.2) - at(k.s - 1.2)
        if flat(ahead).Magnitude < 1e-3 then ahead = dirAt(samples, k.s) end
        local h = flat(ahead).Magnitude
        local key = { t = k.t, p = p, y = yawOf(ahead) }
        if math.abs(ahead.Y) > 1e-3 and h > 1e-3 then key.x = r3(math.atan2(ahead.Y, h)) end
        if i == 1 and firstSegment == false then key.c = 1 end
        keys[i] = key
    end
    return keys
end

-- a chase car tailing the car's schedule: lag seconds behind, sideways offset,
-- never past sMax (it brakes at the roadblock), then spins out a little.
-- Its own path may start earlier than the car's (sShift: cop s = car s + sShift),
-- so on the street it comes in from behind instead of out of the yard.
local function copKeys(samples, sched, lag, side, sMax, tFrom, tTo, spinDir, segStart, sShift, v0)
    local keys = {}
    local sStopT = nil
    local t = tFrom
    local lastS = -math.huge
    while t <= tTo + 1e-6 do
        local s = sAtExt(sched, t - lag, v0) - 2 + (sShift or 0)
        local stopped = false
        if sMax and s >= sMax then s = sMax stopped = true end
        if s < lastS then s = lastS end
        lastS = s
        local d = flat(dirAt(samples, s))
        d = d.Magnitude > 1e-4 and d.Unit or Vector3.new(0, 0, -1)
        local right = Vector3.new(-d.Z, 0, d.X)
        local y = yawOf(d)
        if stopped then
            sStopT = sStopT or t
            y = y + spinDir * 0.9 * smooth((t - sStopT) / 0.6)
        end
        local key = { t = r3(t), p = posAt(samples, s) + right * side, y = y }
        if #keys == 0 and segStart then key.c = 1 end
        table.insert(keys, key)
        t = t + KEY_DT
    end
    return keys
end

local function lookShot(t0, t1, a, b, target, lookUp, fov)
    return { t0 = r3(t0), t1 = r3(t1), mode = "look", a = a, b = b, target = target, lookUp = lookUp or 1.5, fov = fov }
end
local function chaseShot(t0, t1, target, o1, o2, look, fov)
    return { t0 = r3(t0), t1 = r3(t1), mode = "chase", target = target, o1 = o1, o2 = o2 or o1, look = look or Vector3.new(0, 2, -10), fov = fov }
end
local function fixedShot(t0, t1, from, to, fov)
    return { t0 = r3(t0), t1 = r3(t1), mode = "fixed", from = from, to = to or from, fov = fov }
end
-- (playtest fix 2026-09-25) the final HELD shot: the camera rides along on the far
-- side of the target from `focus` (the city), looking back THROUGH the target at
-- it — the boat + its wake in the foreground, the lit skyline behind.
--   dist = studs behind the target (away from focus), side = sideways offset,
--   y = absolute camera height, ahead = how far past the target (toward focus)
--   the camera aims, lookY = the height it aims at
local function lookbackShot(t0, t1, target, focus, o)
    o = o or {}
    return { t0 = r3(t0), t1 = r3(t1), mode = "lookback", target = target, focus = focus,
        dist = o.dist or 24, side = o.side or 0, y = o.y, ahead = o.ahead or 70, lookY = o.lookY or 6, fov = o.fov or 62 }
end

-- how far the car goes before it's out of the yard gate (the first leg straight ahead)
local function streetPoint(startCF, laneZ)
    local p = startCF.Position
    return Vector3.new(p.X, 0, laneZ)
end

-- Find the yard gate straight ahead of the car (two walls close on both
-- sides) so the shutter prop sits IN the gate. Falls back to just ahead of
-- the bumper. Needs the world, so the scene builder takes it as an option.
function GetawayService.findGate(startCF, halfLen, exclude)
    local look = flat(startCF.LookVector)
    look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
    local right = Vector3.new(-look.Z, 0, look.X)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclude or {}
    local base = startCF.Position + Vector3.new(0, 4, 0)
    for d = math.floor(halfLen + 2), 44 do
        local p = base + look * d
        local r1 = Workspace:Raycast(p, right * 6, params)
        local r2 = Workspace:Raycast(p, -right * 6, params)
        if r1 and r2 then
            local w = (r1.Position - r2.Position).Magnitude
            if w > 5.6 and w < 11.5 then
                local mid = (r1.Position + r2.Position) / 2
                return CFrame.lookAt(Vector3.new(mid.X, startCF.Position.Y, mid.Z), Vector3.new(mid.X, startCF.Position.Y, mid.Z) + look), w, d
            end
        end
    end
    local p = startCF.Position + look * (halfLen + 1.6)
    return CFrame.lookAt(p, p + look), 8.4, halfLen + 1.6
end

--[[ opts = { route, loud, carType, startCFrame, halfLen?, seed?, jobId?, gateCF?, gateWidth?,
             boatCF?, highway? = GetawayProps.HIGHWAY } ]]
function GetawayService.buildScene(opts)
    local route = opts.route or "boat"
    local loud = opts.loud == true
    local carType = opts.carType or "classic"
    local startCF = opts.startCFrame or CFrame.new(0, 0, 0)
    local halfLen = opts.halfLen or 6
    local seed = opts.seed or 1
    local rng = Random.new(seed)
    local st = loud and STUNTS[carType] or nil
    local vmax = loud and 52 or 34
    local start = startCF.Position
    local startLook = flat(startCF.LookVector)
    startLook = startLook.Magnitude > 1e-3 and startLook.Unit or Vector3.new(0, 0, -1)
    local sy = start.Y

    local scene = {
        route = route, loud = loud, carType = carType, jobId = opts.jobId, seed = seed,
        tracks = {}, props = {}, events = {}, shots = {}, captions = {}, radio = not loud, hold = HOLD,
    }
    local function cap(t, text, dur) table.insert(scene.captions, { t = r3(t), dur = dur or 2, text = text }) end
    local function ev(e) e.t = r3(e.t) table.insert(scene.events, e) end

    -- which way along Ocean Drive
    local dirX
    if route == "boat" then
        dirX = (MARINA_X >= start.X) and 1 or -1
    elseif route == "highway" then
        dirX = 1
    else
        dirX = start.X > 0 and -1 or 1
    end
    local laneZ = dirX > 0 and LANE_E or LANE_W
    local exitPt = streetPoint(startCF, laneZ)

    -- ── leg 1 path ──
    local pts = { Vector3.new(start.X, sy, start.Z), Vector3.new(exitPt.X, 0, exitPt.Z) }
    local stuntPos, stuntDir = nil, nil
    if route == "boat" then
        table.insert(pts, Vector3.new(MARINA_X, 0, laneZ))
        table.insert(pts, Vector3.new(MARINA_X, 0, -100))
        table.insert(pts, Vector3.new(PIER_X, 0.2, -109.5))
        table.insert(pts, Vector3.new(PIER_X, PIER_Y, -114))
        table.insert(pts, Vector3.new(PIER_X, PIER_Y, -136))
        stuntPos = Vector3.new(MARINA_X, 0, -58)
    elseif route == "heli" then
        local stopX = math.clamp(start.X + dirX * 60, -118, 118)
        table.insert(pts, Vector3.new(stopX, 0, laneZ))
        stuntPos = Vector3.new(start.X + dirX * 30, 0, laneZ)
    else
        local endX = math.min(start.X + 78, 146)
        if endX - start.X < 8 then endX = start.X + 8 end
        table.insert(pts, Vector3.new(endX, 0, laneZ))
    end
    local samples, L = smoothPath(pts, 7)

    local exitS = (Vector3.new(exitPt.X, 0, exitPt.Z) - Vector3.new(start.X, 0, start.Z)).Magnitude
    local sSt = nil
    if st and stuntPos and route ~= "highway" then
        -- nearest sample to the stunt spot
        local best, bestD = nil, math.huge
        for _, smp in ipairs(samples) do
            local d = (flat(smp.p) - flat(stuntPos)).Magnitude
            if d < bestD then best, bestD = smp.s, d end
        end
        sSt = best
        if sSt and sSt < exitS + 14 then sSt = nil end   -- too close to the gate for a stunt
    end

    -- a slower car on short trips so the drive still reads (and the scene stays 12-18 s)
    local minDrive = ({ boat = 5.2, heli = 4.2, highway = 2.4 })[route]
    local v1 = math.min(vmax, math.max(18, L / minDrive + 6))
    local stop = route ~= "highway"
    local HOLD_START = 1.3
    local sched1, tEnd1 = schedule(L, { t0 = 0, hold = HOLD_START, vmax = v1, accel = v1 / 1.1, stop = stop, extra = 0 })
    local carKeys = driveKeys(samples, sched1, st, sSt, true)
    local tExit = tAt(sched1, math.min(exitS, L))
    local tSt = sSt and tAt(sched1, sSt) or nil

    -- the yard gate rolls up
    local gateCF, gateW = opts.gateCF, opts.gateWidth
    if not gateCF then
        local p = start + startLook * (halfLen + 1.6)
        gateCF, gateW = CFrame.lookAt(p, p + startLook), 8.4
    end
    table.insert(scene.props, { kind = "Shutter", cf = gateCF, t0 = 0, t1 = r3(math.max(tExit, 2.5) + 0.5), width = gateW or 8.4, open0 = 0.35, open1 = 1.3 })

    -- ROLL-OUT: high over the yard, looking down the car's nose
    local hi = CFrame.new(start) * CFrame.lookAt(Vector3.zero, startLook)
    local camA = (hi * CFrame.new(2.5, 15, 13)).Position
    local camB = (hi * CFrame.new(1.5, 13, 9)).Position
    local tRoll = math.max(2.4, math.min(tExit + 0.4, 4.2))
    table.insert(scene.shots, lookShot(0, tRoll, camA, camB, "car", 1.2, 60))
    cap(0.35, loud and "GO GO GO!" or "Nice and easy…", 1.6)
    if loud then ev({ t = 0.2, kind = "sirens", on = true }) end

    local shotT = tRoll
    local function chaseUntil(t1, o1, o2)
        if t1 - shotT > 0.3 then
            table.insert(scene.shots, chaseShot(shotT, t1, "car", o1 or Vector3.new(0, 6.5, 18), o2 or Vector3.new(2.5, 5, 15), Vector3.new(0, 2.2, -12), 68))
            shotT = t1
        end
    end

    -- STUNT (loud) or a slow city-lights dolly (stealth)
    local function addStunt(samplesX, schedX, sStX, tStX, segName)
        if not st or not sStX or not tStX then return end
        local p = posAt(samplesX, sStX)
        local d = flat(dirAt(samplesX, sStX))
        d = d.Magnitude > 1e-4 and d.Unit or Vector3.new(1, 0, 0)
        local right = Vector3.new(-d.Z, 0, d.X)
        local shift = st.style == "weave" and -5 or 0
        local base = Vector3.new(p.X, p.Y, p.Z) + right * shift
        local rbCF = CFrame.lookAt(base, base + d)
        table.insert(scene.props, { kind = "Roadblock", cf = rbCF, t0 = 0, t1 = r3((segName == "hw") and 999 or 999) })
        scene.stunt = { kind = carType, t = r3(tStX), s = sStX, cf = rbCF, style = st.style }
        ev({ t = tStX - 0.05, kind = "smash", style = st.fling, dir = d, seed = seed })
        if st.nitro then ev({ t = tStX - 0.7, kind = "nitro", dur = 1.6 }) end
        ev({ t = tStX, kind = "shake", power = (st.fling == "fly" or st.fling == "bounce") and 1 or 0.4 })
        cap(tStX - 0.5, st.caption, 1.9)
        -- side camera: off to the left of the roadblock, a little ahead of it
        local camP = p - right * 11 + d * 9 + Vector3.new(0, 4.5, 0)
        local camQ = p - right * 12 + d * 12 + Vector3.new(0, 5.5, 0)
        chaseUntil(tStX - 1.3)
        if tStX + 1.15 > shotT + 0.3 then
            table.insert(scene.shots, lookShot(shotT, tStX + 1.15, camP, camQ, "car", 1.6, 62))
            shotT = tStX + 1.15
        end
        local _ = schedX
    end
    local function addDolly(samplesX, schedX, tFromX, tToX)
        local tm = (tFromX + tToX) / 2
        if tToX - tFromX < 2.6 then return end
        local sm = sAt(schedX, tm)
        local p = posAt(samplesX, sm)
        local d = flat(dirAt(samplesX, sm))
        d = d.Magnitude > 1e-4 and d.Unit or Vector3.new(1, 0, 0)
        local right = Vector3.new(-d.Z, 0, d.X)
        chaseUntil(tm - 1.2)
        if tm + 1.4 <= shotT + 0.3 then return end
        table.insert(scene.shots, lookShot(shotT, tm + 1.4, p + right * 10 - d * 4 + Vector3.new(0, 3, 0),
            p + right * 10 + d * 8 + Vector3.new(0, 3.5, 0), "car", 1.4, 55))
        shotT = tm + 1.4
    end

    local tracks = scene.tracks
    tracks.car = carKeys
    -- the chase cars' road: 70 studs back along Ocean Drive, then the car's route from the gate on
    local function copPath()
        local cp = { Vector3.new(exitPt.X - dirX * 70, 0, laneZ) }
        for i = 2, #pts do table.insert(cp, pts[i]) end
        local cs = smoothPath(cp, 7)
        return cs, 70 - exitS
    end
    local copFrom = math.max(tExit - 0.2, 1.5)

    if route == "boat" or route == "heli" then
        if st and sSt then addStunt(samples, sched1, sSt, tSt, "street")
        elseif not loud then addDolly(samples, sched1, tRoll, tEnd1 - 2) end
        if loud then
            local copSamples, shift = copPath()
            local capS = (sSt and (sSt - 15) or (L - 16)) + shift
            tracks.cop1 = copKeys(copSamples, sched1, 0.95, -2.2, capS, copFrom, tEnd1 + HOLD, 1, false, shift)
            tracks.cop2 = copKeys(copSamples, sched1, 1.55, 2.4, capS - 13, copFrom, tEnd1 + HOLD, -1, false, shift)
        end
    end

    local tStop = tEnd1
    if route == "boat" then
        local boatCF = opts.boatCF or CFrame.new(109, -0.3, -141)
        scene.boatCF = boatCF
        local tHop, tLaunch = tStop + 0.35, tStop + 1.9
        ev({ t = tHop, kind = "hop", to = "boat", dur = 1.25 })
        cap(tStop - 1.4, "TO THE BOAT!", 1.8)
        -- boat keys: still, then blast north off the pier, carve a turn and cruise
        -- ALONG the coast (playtest fix 2026-09-25: it used to blast ~900 studs north,
        -- past the camera and off the end of the water — the held shot under the
        -- payout was flat empty ocean). Parallel to the beach the city stays ~160
        -- studs away (inside the fog start), so the final shot can look back at it.
        local bk = {}
        local bp = boatCF.Position
        local byaw = yawOf(boatCF.LookVector)
        table.insert(bk, { t = 0, p = bp, y = byaw })
        table.insert(bk, { t = r3(tLaunch), p = bp, y = byaw })
        local cruiseDir = (bp.X >= 0) and Vector3.new(-1, 0, 0) or Vector3.new(1, 0, 0)   -- toward the city centre
        local cruiseYaw = yawOf(cruiseDir)
        local dYaw = ((cruiseYaw - byaw + math.pi) % (2 * math.pi)) - math.pi
        local STRAIGHT, TURN_R = 22, 22                -- clear the pier end (z -150) before turning
        local turnLen = math.max(1, TURN_R * math.abs(dYaw))
        local V_BLAST, V_CRUISE = 58, 20
        local tBlastEnd = tLaunch + 2.4
        local tBoatEnd = tLaunch + 5.2 + HOLD + 6      -- (+6: the client's hold safety margin)
        local vB, sB, tt, yaw = 0, 0, tLaunch, byaw
        local p = bp
        local DT = 0.2
        while tt < tBoatEnd do
            tt = tt + DT
            if tt <= tBlastEnd then vB = math.min(V_BLAST, vB + 30 * DT)
            else vB = math.max(V_CRUISE, vB - 20 * DT) end
            local ds = vB * DT
            sB = sB + ds
            -- heading: straight out, then a constant-radius turn onto the cruise line
            local u = math.clamp((sB - STRAIGHT) / turnLen, 0, 1)
            yaw = byaw + dYaw * u
            p = p + CFrame.Angles(0, yaw, 0).LookVector * ds
            local turning = u > 0 and u < 1
            local bob = math.sin(tt * 5) * 0.12
            table.insert(bk, { t = r3(tt), p = Vector3.new(p.X, bp.Y + bob, p.Z), y = yaw,
                x = r3(math.min(0.14, vB / 500)), r = turning and r3(0.2 * (dYaw >= 0 and 1 or -1)) or 0 })
        end
        tracks.boat = bk
        ev({ t = tLaunch, kind = "wake", on = true })
        -- shots. (The chase along the pier keeps to the EAST side and above the
        -- lanterns — x 100.6, y 7..7.9 — which the old offset flew straight through:
        -- the one-frame glitch between shots.)
        chaseUntil(tStop - 1.9, Vector3.new(0, 8.5, 18), Vector3.new(3.5, 8.5, 16))
        table.insert(scene.shots, fixedShot(shotT, tLaunch + 0.4,
            CFrame.lookAt(Vector3.new(114, 6.5, -157), Vector3.new(104, 1.8, -133)),
            CFrame.lookAt(Vector3.new(115, 6, -155), Vector3.new(106, 1.4, -139)), 58))
        shotT = tLaunch + 0.4
        table.insert(scene.shots, chaseShot(shotT, tLaunch + 2.4, "boat", Vector3.new(-7, 4, 17), Vector3.new(-4, 5, 22), Vector3.new(0, 1.5, -10), 70))
        shotT = tLaunch + 2.4
        scene.duration = r3(tLaunch + 5.2)
        -- FINAL (held under the payout): out on the water beyond the boat, looking
        -- back at it — wake in the foreground, the lit Miami skyline behind
        table.insert(scene.shots, lookbackShot(shotT, scene.duration + HOLD, "boat", Vector3.new(0, 0, STREET_Z),
            { dist = 26, side = 7, y = 8.5, ahead = 80, lookY = 9, fov = 60 }))
        cap(tLaunch + 2.6, loud and "WE GOT AWAY!" or "CLEAN GETAWAY!", 2.4)
        if loud then ev({ t = tLaunch + 1.5, kind = "sirens", on = false }) end
    elseif route == "heli" then
        local stopP = posAt(samples, L)
        local d = flat(dirAt(samples, L))
        d = d.Magnitude > 1e-4 and d.Unit or Vector3.new(dirX, 0, 0)
        local landP = stopP + d * 17
        local hy = yawOf(d)
        local tLand, tLift = tStop + 0.1, tStop + 2.2
        local hk = {}
        local sky = landP - d * 40 + Vector3.new(0, 58, 36)
        table.insert(hk, { t = 0, p = sky, y = hy })
        table.insert(hk, { t = r3(math.max(0.5, tStop - 3.2)), p = sky, y = hy })
        table.insert(hk, { t = r3(tStop - 1.7), p = landP + Vector3.new(0, 16, 6) - d * 10, y = hy, x = 0.12 })
        table.insert(hk, { t = r3(tStop - 0.7), p = landP + Vector3.new(0, 3.5, 0), y = hy, x = 0.05 })
        table.insert(hk, { t = r3(tLand), p = landP, y = hy })
        table.insert(hk, { t = r3(tLift), p = landP, y = hy })
        -- (playtest fix 2026-09-25) it flies off ALONG Ocean Drive over the city
        -- (hotels ≤ 30 tall; it cruises at 70+), not out to sea: the held shot
        -- under the payout looks down past it at the city lights
        local cdx = (landP.X > 0) and -1 or 1
        local cruiseYaw = yawOf(Vector3.new(cdx, 0, 0))
        local cz = STREET_Z - 22
        local function turnYaw(u)
            local diff = ((cruiseYaw - hy + math.pi) % (2 * math.pi)) - math.pi
            return hy + diff * smooth(u)
        end
        table.insert(hk, { t = r3(tLift + 0.8), p = landP + Vector3.new(0, 7, 0), y = turnYaw(0.2), x = -0.05 })
        table.insert(hk, { t = r3(tLift + 1.7), p = landP + Vector3.new(cdx * 4, 22, -4), y = turnYaw(0.7), x = -0.16, r = 0.14 * cdx })
        table.insert(hk, { t = r3(tLift + 3.2), p = Vector3.new(landP.X + cdx * 36, 50, cz), y = cruiseYaw, x = -0.22, r = 0.05 })
        table.insert(hk, { t = r3(tLift + 5.2), p = Vector3.new(landP.X + cdx * 90, 70, cz), y = cruiseYaw, x = -0.18 })
        table.insert(hk, { t = r3(tLift + 5.2 + HOLD), p = Vector3.new(landP.X + cdx * (90 + 22 * HOLD), 78, cz), y = cruiseYaw, x = -0.15 })
        table.insert(hk, { t = r3(tLift + 5.2 + HOLD + 6), p = Vector3.new(landP.X + cdx * (90 + 22 * (HOLD + 6)), 82, cz), y = cruiseYaw, x = -0.15 })
        tracks.heli = hk
        ev({ t = tStop + 0.4, kind = "hop", to = "heli", dur = 1.3 })
        cap(tStop - 1.8, "CHOPPER'S HERE!", 1.9)
        chaseUntil(tStop - 2.4, Vector3.new(0, 6.5, 18), Vector3.new(-3, 5, 14))
        local camL = stopP - d * 13 - Vector3.new(-d.Z, 0, d.X) * 6 + Vector3.new(0, 2.6, 0)
        table.insert(scene.shots, lookShot(shotT, tLift + 0.2, camL, camL + d * 3 + Vector3.new(0, 0.6, 0), "heli", 3, 64))
        shotT = tLift + 0.2
        local camU = stopP - d * 22 + Vector3.new(0, 3, 0)
        table.insert(scene.shots, lookShot(shotT, tLift + 2.6, camU, camU + Vector3.new(0, 5, 0), "heli", 2.5, 66))
        shotT = tLift + 2.6
        scene.duration = r3(tLift + 5.0)
        -- FINAL (held): above and behind it, looking down past it at the city lights
        table.insert(scene.shots, chaseShot(shotT, scene.duration + HOLD, "heli", Vector3.new(-8, 12, 32), Vector3.new(-12, 16, 40), Vector3.new(0, -40, -70), 64))
        cap(tLift + 2.8, loud and "WE GOT AWAY!" or "CLEAN GETAWAY!", 2.4)
        if loud then ev({ t = tLift + 1, kind = "sirens", on = false }) end
    else
        -- HIGHWAY: leg 1 ends in a fade, leg 2 is the night highway far outside the map
        local H = opts.highway or (Props and Props.HIGHWAY) or { x0 = 900, x1 = 1800, z = 900, y = 0, laneOffset = 12 }
        local tFade = tEnd1
        if not loud then addDolly(samples, sched1, tRoll, tFade - 0.6) end
        if loud then
            local copSamples, shift = copPath()
            tracks.cop1 = copKeys(copSamples, sched1, 0.95, -2.2, nil, copFrom, tFade, 1, false, shift)
            tracks.cop2 = copKeys(copSamples, sched1, 1.55, 2.4, nil, copFrom, tFade, -1, false, shift)
        end
        chaseUntil(tFade)
        ev({ t = tFade, kind = "fade", dur = 0.7 })
        cap(tFade + 0.25, "HIT THE HIGHWAY!", 1.8)
        local hz = H.z + (H.laneOffset or 12)
        local x0 = H.x0 + 20
        local x1 = H.x1 - 30
        local pts2 = { Vector3.new(x0, H.y, hz), Vector3.new(x1, H.y, hz) }
        local samples2, L2 = smoothPath(pts2, 1)
        local drive2 = 8.7
        local v2 = math.min(loud and 90 or 64, L2 / (drive2 + HOLD) * 1.25)
        local sched2 = schedule(L2, { t0 = tFade, hold = tFade, v0 = v2 * 0.8, vmax = v2, accel = 20, stop = false, extra = 0 })
        local sSt2 = st and math.min(L2 * 0.35, v2 * 4.2) or nil
        local keys2 = driveKeys(samples2, sched2, st, sSt2, false)
        for _, k in ipairs(keys2) do table.insert(carKeys, k) end
        ev({ t = tFade + 0.3, kind = "nitro", dur = 1.4 })
        if loud then
            local tSt2 = tAt(sched2, sSt2)
            local c1 = copKeys(samples2, sched2, 0.9, -2.2, sSt2 - 15, tFade, tFade + drive2 + HOLD, 1, true, 0, v2 * 0.8)
            local c2 = copKeys(samples2, sched2, 1.45, 2.4, sSt2 - 28, tFade, tFade + drive2 + HOLD, -1, true, 0, v2 * 0.8)
            for _, k in ipairs(c1) do table.insert(tracks.cop1, k) end
            for _, k in ipairs(c2) do table.insert(tracks.cop2, k) end
            -- first shot on the highway: low by the barrier as the car blasts past
            table.insert(scene.shots, lookShot(tFade, tFade + 2.0, Vector3.new(x0 + 58, H.y + 2.4, hz + 8), Vector3.new(x0 + 60, H.y + 2.2, hz + 9), "car", 1.2, 62))
            shotT = tFade + 2.0
            addStunt(samples2, sched2, sSt2, tSt2, "hw")
        else
            table.insert(scene.shots, lookShot(tFade, tFade + 2.4, Vector3.new(x0 + 50, H.y + 2.4, hz + 8), Vector3.new(x0 + 52, H.y + 2.2, hz + 9), "car", 1.2, 62))
            shotT = tFade + 2.4
        end
        scene.duration = r3(tFade + drive2)
        chaseUntil(scene.duration - 2.6, Vector3.new(0, 5.5, 17), Vector3.new(-2, 4.5, 14))
        -- final: behind + above, the car shrinking into the glow
        local endS = sAt(sched2, scene.duration - 2.6)
        local ep = posAt(samples2, endS)
        local camF = ep + Vector3.new(-26, 8, -3)
        table.insert(scene.shots, fixedShot(shotT, scene.duration + HOLD,
            CFrame.lookAt(camF, Vector3.new(H.x1 + 110, H.y + 22, hz)),
            CFrame.lookAt(camF + Vector3.new(6, 2, 0), Vector3.new(H.x1 + 110, H.y + 26, hz)), 58))
        cap(scene.duration - 2.2, loud and "WE GOT AWAY!" or "CLEAN GETAWAY!", 2.4)
        if loud then ev({ t = scene.duration - 3, kind = "sirens", on = false }) end
        scene.highway = { x0 = H.x0, x1 = H.x1, z = H.z }
    end

    if scene.radio then
        cap(tRoll + 0.1, "📻 Miami Nights FM", 3.2)
    end
    ev({ t = scene.duration - 0.6, kind = "stamp", text = loud and "GOT AWAY!" or "CLEAN GETAWAY!" })
    -- keep the tail of every track moving a little into the hold
    local last = carKeys[#carKeys]
    if last.t < scene.duration + HOLD and route ~= "highway" then
        table.insert(carKeys, { t = r3(scene.duration + HOLD), p = last.p, y = last.y })
    end
    table.sort(scene.events, function(a, b) return a.t < b.t end)
    table.sort(scene.captions, function(a, b) return a.t < b.t end)
    local _ = rng
    return scene
end

-- ══════════════════════════════════════════════════════════════════════
-- RUNTIME: vote → scene → done
-- ══════════════════════════════════════════════════════════════════════
local remote = nil
local deps = {}
local current = nil          -- the running getaway (ctx + state)

local function now() return Workspace:GetServerTimeNow() end

local function fireCrew(ctx, payload)
    if not remote then return end
    for _, p in ipairs(ctx.crew) do
        if p.Parent then remote:FireClient(p, payload) end
    end
end

local function inCrew(ctx, player)
    for _, p in ipairs(ctx.crew) do if p == player then return true end end
    return false
end

local function carInfo(ctx)
    local car = ctx.car
    local m = car and car.model
    local carType = (car and car.carType) or (m and m:GetAttribute("CarType")) or "classic"
    return {
        carType = carType,
        carId = (car and car.carId) or (m and m:GetAttribute("CarId")) or "CarClassic",
        carName = (m and m:GetAttribute("CarName")) or "Classic",
        halfLen = (car and car.halfLen) or 6,
    }
end

function GetawayService.voteWeight(player)
    local ok, role = pcall(function() return player:GetAttribute("Role") end)
    return (ok and role == "Driver") and GetawayService.DRIVER_VOTE_WEIGHT or 1
end

function GetawayService.driverOf(crew)
    for _, p in ipairs(crew or {}) do
        if GetawayService.voteWeight(p) > 1 then return p end
    end
    return nil
end

local function tally(state)
    local counts = { boat = 0, heli = 0, highway = 0 }
    local voted = 0
    for player, route in pairs(state.votes) do
        counts[route] = (counts[route] or 0) + GetawayService.voteWeight(player)
        voted = voted + 1
    end
    return counts, voted
end

function GetawayService.decide(counts, heliAllowed)
    local best, bestN, tie = "boat", -1, false
    for _, r in ipairs(GetawayService.ROUTES) do
        local n = counts[r] or 0
        if r == "heli" and not heliAllowed then n = 0 end
        if n > bestN then best, bestN, tie = r, n, false
        elseif n == bestN then tie = true end
    end
    if bestN <= 0 or tie then return "boat" end
    return best
end

function GetawayService:isBusy()
    return current ~= nil
end

function GetawayService:getPhase()
    return current and current.phase or "idle"
end

function GetawayService:cancel()
    local c = current
    if not c then return end
    current = nil
    c.cancelled = true
    fireCrew(c.ctx, { phase = "cancel" })
end

function GetawayService:start(ctx)
    if current then return false end
    if type(ctx) ~= "table" or type(ctx.crew) ~= "table" or #ctx.crew == 0 then return false end
    local ci = carInfo(ctx)
    local state = { ctx = ctx, phase = "vote", votes = {}, cancelled = false, info = ci }
    current = state
    local voteTime = tonumber(ctx.voteTime) or GetawayService.VOTE_TIME
    local loud = ctx.loud == true
    local driver = GetawayService.driverOf(ctx.crew)
    local driverPct = driver and GetawayService.DRIVER_BONUS or 0
    state.driver, state.driverPct = driver, driverPct
    local options = {}
    for _, r in ipairs(GetawayService.ROUTES) do
        local b = GetawayService.bonusFor(r, loud, ci.carType)
        options[r] = {
            ok = (r ~= "heli") or ctx.heliAllowed == true,
            pct = round6(b.total + driverPct), carPct = b.car, heliPct = b.heli, driverPct = driverPct,
            name = GetawayService.ROUTE_INFO[r].name, icon = GetawayService.ROUTE_INFO[r].icon,
            line = GetawayService.ROUTE_INFO[r].line,
            why = (r == "heli" and ctx.heliAllowed ~= true) and "Locked — someone got caught" or nil,
        }
    end
    state.endsAt = now() + voteTime
    fireCrew(ctx, {
        phase = "vote", endsAt = state.endsAt, duration = voteTime, options = options, loud = loud,
        car = { type = ci.carType, name = ci.carName, base = carBase(ci.carType) }, voters = #ctx.crew,
        driver = driver and driver.DisplayName or nil,
    })

    task.spawn(function()
        -- 1. the vote
        if ctx.forceRoute then state.forced = ctx.forceRoute end
        while not state.cancelled and now() < state.endsAt do
            task.wait(0.1)
        end
        if state.cancelled or current ~= state then return end
        local counts = tally(state)
        local route = state.forced or GetawayService.decide(counts, ctx.heliAllowed == true)
        if route == "heli" and ctx.heliAllowed ~= true then route = "boat" end
        state.route = route
        state.phase = "decided"
        fireCrew(ctx, { phase = "decided", route = route, votes = counts })
        task.wait(1.1)
        if state.cancelled or current ~= state then return end

        -- 2. the scene
        local startCF = ctx.startCFrame
        if typeof(startCF) ~= "CFrame" then
            startCF = ctx.car and ctx.car.model and ctx.car.model:GetPivot() or CFrame.new()
        end
        local gateCF, gateW
        local okG, a, b = pcall(GetawayService.findGate, startCF, ci.halfLen, (function()
            local ex = {}
            if ctx.car and ctx.car.model then table.insert(ex, ctx.car.model) end
            for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ex, p.Character) end end
            return ex
        end)())
        if okG then gateCF, gateW = a, b end
        local okS, scene = pcall(GetawayService.buildScene, {
            route = route, loud = loud, carType = ci.carType, startCFrame = startCF, halfLen = ci.halfLen,
            seed = math.random(1, 1e6), jobId = ctx.jobId, gateCF = gateCF, gateWidth = gateW,
            boatCF = Props and Props.boatCFrame and Props.boatCFrame() or nil,
            highway = Props and Props.HIGHWAY or nil,
        })
        if not okS then
            warn("[GetawayService] buildScene failed:", scene)
            scene = { route = route, loud = loud, carType = ci.carType, duration = 2, hold = 4, tracks = {}, props = {},
                events = {}, shots = {}, captions = { { t = 0, dur = 2, text = "WE GOT AWAY!" } } }
        end
        state.phase = "scene"
        state.scene = scene
        local crew = {}
        for _, p in ipairs(ctx.crew) do if p.Parent then table.insert(crew, p) end end
        fireCrew(ctx, { phase = "scene", scene = scene, crew = crew, carModel = ctx.car and ctx.car.model or nil })
        local t0 = os.clock()
        while not state.cancelled and os.clock() - t0 < (scene.duration or 12) + 0.25 do
            task.wait(0.1)
        end
        if state.cancelled or current ~= state then return end
        current = nil

        -- 3. done → JobService pays
        local bonus = GetawayService.bonusFor(route, loud, ci.carType)
        local info = {
            route = route, routeName = GetawayService.ROUTE_INFO[route].name, icon = GetawayService.ROUTE_INFO[route].icon,
            loud = loud, carType = ci.carType, carId = ci.carId, carName = ci.carName,
            pct = round6(bonus.total + driverPct), carPct = bonus.car, heliPct = bonus.heli,
            driverPct = driverPct, driverName = driver and driver.DisplayName or nil,
            duration = scene.duration,
        }
        if type(ctx.onDone) == "function" then
            local ok, err = pcall(ctx.onDone, info)
            if not ok then warn("[GetawayService] onDone:", err) end
        end
    end)
    return true
end

function GetawayService:init(d)
    deps = d or {}
    if Props and type(Props.init) == "function" then
        local ok, err = pcall(Props.init, Props)
        if not ok then warn("[GetawayService] props:", err) end
    end
    if remote then return end
    remote = Remotes.getRemote(REMOTE_NAME, "RemoteEvent")
    remote.OnServerEvent:Connect(function(player, msg)
        if type(msg) ~= "table" then return end
        if msg.action == "go" then
            if type(deps.onGo) == "function" then
                local ok, err = pcall(deps.onGo, player)
                if not ok then warn("[GetawayService] onGo:", err) end
            end
        elseif msg.action == "vote" then
            local c = current
            if not c or c.phase ~= "vote" or not inCrew(c.ctx, player) then return end
            local route = msg.route
            if route ~= "boat" and route ~= "heli" and route ~= "highway" then return end
            if route == "heli" and c.ctx.heliAllowed ~= true then return end
            c.votes[player] = route
            local counts, voted = tally(c)
            local voters = 0
            for _, p in ipairs(c.ctx.crew) do if p.Parent then voters = voters + 1 end end
            fireCrew(c.ctx, { phase = "tally", votes = counts, voted = voted, voters = voters })
            if voted >= voters then
                c.endsAt = math.min(c.endsAt, now() + 0.8)   -- everyone voted: don't make them wait
            end
        end
    end)
    print("[GetawayService] movie getaways online 🎬 (boat · helicopter · highway)")
end

return GetawayService
