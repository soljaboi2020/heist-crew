--[[
    HEIST CREW — BriefingShots  (v2.2, 2026-09-25)
    ────────────────────────────────────────────────
    "When talking to the Boss the story is good, but the camera should show
    the actual heist."  This works out a camera fly-through of every REAL
    target building from the job refs and publishes it for BriefingUI.

    Server only. No gameplay, no Scripts, nothing in the world is changed:
    it only reads the job refs, raycasts, and writes a few Folders into
    ReplicatedStorage.

    PUBLIC API
        BriefingShots:publish(world)      -- call ONCE, right after HeistBuilder:build()
            world.jobs = { [jobId] = JobRefs }  (HeistBuilder's return value)
            Returns { [jobId] = { shot, ... } }. Never errors (each job is pcall'd).
        BriefingShots:compute(refs) -> { shot, ... }   -- one job, no publishing

    SHOT
        { from = CFrame, to = CFrame,      -- the camera tweens from -> to
          duration = number,               -- seconds (a hint; the client paces by line)
          label = "THE STAFF DOOR",        -- caption chip text
          tag = "wide"|"front"|"side"|"roof"|"breaker"|"keycard"|"lasers"|"vault"|"car" }
        Order: wide, front, side, roof, breaker, keycard, lasers, vault, car
        (a tag is left out when the job has no such thing — the mart has no
        keycard and no lasers).

    PUBLISHED FORMAT (what the client reads — attributes, no ModuleScript)
        ReplicatedStorage
          └ BriefingShots            Folder   attr Version = 1
              └ <jobId>              Folder   attr Count = n
                  └ "01" .. "0n"     Folder   attrs  From (CFrame) · To (CFrame)
                                                     Duration (number) · Label (string)
                                                     Tag (string) · Order (number)
        Children are named with two digits so sorting by Name == sorting by Order.

    CAMERA SAFETY (why a shot never starts inside a wall)
        Every camera position is found from a point we KNOW is open air (the
        spot outside the door, the middle of the laser corridor, just in front
        of the vault door) by raycasting from that point toward where we'd like
        the camera. If anything solid is in the way the camera is pulled in to
        1.5 studs in front of the first hit. Several directions are tried and
        the best clear one wins, so interior shots end up inside the room and
        exterior shots outside. Parts that are see-through (Transparency >= 0.9)
        or non-collidable and half see-through are ignored, as are the target's
        own parts right at the start of the ray. Finally the spot is checked
        with GetPartBoundsInRadius and nudged toward the anchor if it overlaps.
        The "to" CFrame sits on the same cleared ray (a dolly-in), or is
        cleared separately when it drifts sideways.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local BriefingShots = {}

local UP = Vector3.new(0, 1, 0)
local PULL = 1.5          -- studs in front of the first hit
local SHOT_TIME = 4.5

-- ──────────────────────────────────────────────
-- helpers
-- ──────────────────────────────────────────────
local function isV3(v) return typeof(v) == "Vector3" end
local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end
local function finiteV3(v) return isV3(v) and finite(v.X) and finite(v.Y) and finite(v.Z) end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function unitOr(v, fallback)
    if v.Magnitude < 1e-4 then return fallback end
    return v.Unit
end

local function partOf(x)
    if typeof(x) ~= "Instance" then return nil end
    if x:IsA("BasePart") then return x end
    if x:IsA("Model") then return x.PrimaryPart or x:FindFirstChildWhichIsA("BasePart", true) end
    return nil
end

-- parts a camera may pass through
local function seeThrough(p)
    if not p:IsA("BasePart") then return true end
    if p.Transparency >= 0.9 then return true end
    if not p.CanCollide and p.Transparency >= 0.5 then return true end
    return false
end

-- instances every ray of the CURRENT job ignores (characters + that job's laser beams)
local jobIgnore = {}

local function baseExclude(extra)
    local list = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then table.insert(list, plr.Character) end
    end
    for _, x in ipairs(jobIgnore) do table.insert(list, x) end
    for _, x in ipairs(extra or {}) do table.insert(list, x) end
    return list
end

-- first SOLID hit from origin along dir (length = dir.Magnitude).
-- o.skip: hits closer than this to the origin are skipped (the target's own bits)
-- o.ignore: extra instances to ignore (the target itself)
local function solidHit(origin, dir, o)
    o = o or {}
    local exclude = baseExclude(o.ignore)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    for _ = 1, 16 do
        params.FilterDescendantsInstances = exclude
        local r = Workspace:Raycast(origin, dir, params)
        if not r then return nil end
        local inst = r.Instance
        if inst == Workspace.Terrain then return r end
        if seeThrough(inst) or (r.Position - origin).Magnitude < (o.skip or 0) then
            table.insert(exclude, inst)
        else
            return r
        end
    end
    return nil
end

-- is a camera sitting at pos inside something solid?
local function buried(pos)
    local ok, parts = pcall(function() return Workspace:GetPartBoundsInRadius(pos, 0.6) end)
    if not ok or type(parts) ~= "table" then return false end
    for _, p in ipairs(parts) do
        if not seeThrough(p) and p.CanCollide then
            -- bounds overlap is coarse: confirm the point is really inside the box
            local l = p.CFrame:PointToObjectSpace(pos)
            local h = p.Size / 2 + Vector3.new(0.4, 0.4, 0.4)
            if math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z then return true end
        end
    end
    return false
end

-- from the open-air anchor, go toward `want`; returns the cleared position + how far we got
local function clearTo(anchor, want, o)
    local d = want - anchor
    local len = d.Magnitude
    if len < 0.1 then return anchor, 0 end
    local hit = solidHit(anchor, d, o)
    local pos = want
    if hit then
        local back = math.max(0, (hit.Position - anchor).Magnitude - PULL)
        pos = anchor + d.Unit * back
    end
    -- never park inside a part: step back toward the anchor until free
    local tries = 0
    while buried(pos) and tries < 12 do
        local rem = (pos - anchor).Magnitude
        if rem < 1 then break end
        pos = anchor + (pos - anchor).Unit * math.max(0, rem - 1.5)
        tries += 1
    end
    return pos, (pos - anchor).Magnitude
end

-- can a camera at pos actually SEE `look`? (a hit within o.lookR of it counts as seeing it)
local function canSee(pos, look, o)
    local d = look - pos
    if d.Magnitude < 0.5 then return true end
    local hit = solidHit(pos, d, { ignore = o and o.ignore })
    if not hit then return true end
    return (hit.Position - look).Magnitude <= ((o and o.lookR) or 1.5)
end

-- try several directions from the anchor; pick the one that gets closest to `dist`.
-- o = { prefer = unit Vector3 (bonus), skip, ignore, look (must be visible), lookR, minReach }
local function bestSpot(anchor, dirs, dist, o)
    o = o or {}
    local best, bestScore, bestReach
    for i, dvec in ipairs(dirs) do
        if dvec.Magnitude > 1e-3 then
            local u = dvec.Unit
            local pos, reach = clearTo(anchor, anchor + u * dist, o)
            local score = math.min(reach, dist) / dist
            if o.prefer then score += 0.25 * u:Dot(o.prefer) end
            score -= 0.5 * math.max(0, u.Y - 0.6)          -- no bird's-eye unless nothing else works
            if o.look and not canSee(pos, o.look, o) then score -= 0.8 end
            score -= i * 0.001      -- stable: earlier directions win ties
            if reach >= (o.minReach or 3) and (not bestScore or score > bestScore) then
                best, bestScore, bestReach = pos, score, reach
            end
        end
    end
    return best, bestReach or 0
end

-- 16 compass directions, tilted up by `lift` (y component before normalising)
local function ring(lift)
    local out = {}
    for k = 0, 15 do
        local a = k * math.pi / 8
        table.insert(out, Vector3.new(math.cos(a), lift, math.sin(a)))
    end
    return out
end

-- floor height under a point (for low angles)
local function floorBelow(p, o)
    local hit = solidHit(p + UP * 0.5, Vector3.new(0, -30, 0), o)
    return hit and hit.Position.Y or (p.Y - 4)
end

local function shot(tag, label, fromPos, toPos, lookFrom, lookTo)
    lookTo = lookTo or lookFrom
    -- lookAt breaks if the camera looks straight down/up: nudge the target
    local function safeLook(p, t)
        local d = t - p
        if d.Magnitude < 0.5 then t = p + Vector3.new(0, 0, -1) d = t - p end
        if math.abs(d.Unit.Y) > 0.985 then t += Vector3.new(0.5, 0, 0.5) end
        return CFrame.lookAt(p, t)
    end
    return { tag = tag, label = label, duration = SHOT_TIME, look = lookFrom,
        from = safeLook(fromPos, lookFrom), to = safeLook(toPos, lookTo) }
end

-- ──────────────────────────────────────────────
-- building box (plan.bounds + the tallest part of the job over it)
-- ──────────────────────────────────────────────
local function buildingBox(refs)
    local b = refs.plan and refs.plan.bounds
    local x0, z0, x1, z1
    if type(b) == "table" and #b >= 4 then
        x0, z0, x1, z1 = math.min(b[1], b[3]), math.min(b[2], b[4]), math.max(b[1], b[3]), math.max(b[2], b[4])
    end
    local top = 0
    local root = refs.root
    local mnX, mnZ, mxX, mxZ = math.huge, math.huge, -math.huge, -math.huge
    if typeof(root) == "Instance" then
        for _, p in ipairs(root:GetDescendants()) do
            if p:IsA("BasePart") and p.Transparency < 0.9 then
                local c = p.Position
                local inside = (not x0) or (c.X >= x0 and c.X <= x1 and c.Z >= z0 and c.Z <= z1)
                if inside then
                    if p.Size.Y < 60 then top = math.max(top, c.Y + p.Size.Y / 2) end
                    mnX, mxX = math.min(mnX, c.X), math.max(mxX, c.X)
                    mnZ, mxZ = math.min(mnZ, c.Z), math.max(mxZ, c.Z)
                end
            end
        end
    end
    if not x0 then
        if mnX == math.huge then return nil end
        x0, z0, x1, z1 = mnX, mnZ, mxX, mxZ
    end
    top = math.clamp(top, 12, 60)
    return { x0 = x0, z0 = z0, x1 = x1, z1 = z1, top = top,
        center = Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2),
        halfX = (x1 - x0) / 2, halfZ = (z1 - z0) / 2 }
end

-- which face of the box is a point outside of → outward axis
local function outwardAxis(box, p)
    local dx = p.X - box.center.X
    local dz = p.Z - box.center.Z
    local ox = math.abs(dx) - box.halfX
    local oz = math.abs(dz) - box.halfZ
    if ox > oz then return Vector3.new(dx >= 0 and 1 or -1, 0, 0) end
    return Vector3.new(0, 0, dz >= 0 and 1 or -1)
end

local function entrance(refs, kind)
    for _, e in ipairs(type(refs.entrances) == "table" and refs.entrances or {}) do
        if e.kind == kind and finiteV3(e.at) then return e end
    end
    return nil
end

-- ──────────────────────────────────────────────
-- the shots
-- ──────────────────────────────────────────────
local function wideShot(refs, box, frontDir)
    local c = box.center
    local look = c + UP * (box.top * 0.45)
    local front = entrance(refs, "front")
    local anchor = (front and front.at or (c + frontDir * (math.max(box.halfX, box.halfZ) + 4))) + UP * 3
    local right = frontDir:Cross(UP)
    local depth = math.abs(frontDir.X) > 0.5 and box.halfX or box.halfZ
    local back = depth + 34
    local want = c + frontDir * back + UP * (box.top + 26)
    local from = clearTo(anchor, want - right * 22)
    local to = clearTo(anchor, want + right * 22 - frontDir * 6)
    return shot("wide", "THE TARGET", from, to, look, look)
end

local function frontShot(refs, box, frontDir)
    local e = entrance(refs, "front")
    if not e then return nil end
    local door = e.at + UP * 2.5
    local anchor = e.at + UP * 3
    local right = frontDir:Cross(UP)
    local want = anchor + frontDir * 22 + UP * 6 + right * 7
    local from = clearTo(anchor, want)
    local to = anchor + (from - anchor) * 0.6
    return shot("front", "THE FRONT DOOR", from, to, door - frontDir * 2, door - frontDir * 3)
end

local function sideShot(refs, box)
    local e = entrance(refs, "side")
    if not e then return nil end
    local out = outwardAxis(box, e.at)
    local anchor = e.at + UP * 3
    local door = e.at - out * 3 + UP * 2.5
    local right = out:Cross(UP)
    local dirs = {
        out + right * 0.45 + UP * 0.35, out - right * 0.45 + UP * 0.35,
        out + UP * 0.4, right + UP * 0.3, -right + UP * 0.3,
    }
    local pos = bestSpot(anchor, dirs, 15, { prefer = out, skip = 0.5, look = door, lookR = 4 })
    if not pos then pos = clearTo(anchor, anchor + out * 3 + UP * 2) end
    local to = anchor + (pos - anchor) * 0.65
    local label = string.upper(e.label or "SIDE DOOR"):gsub("%s*%b()", "")
    return shot("side", "THE " .. label, pos, to, door, door)
end

local function roofShot(refs, box)
    local e = entrance(refs, "roof")
    if not e then return nil end
    local out = outwardAxis(box, e.at)
    local anchor = e.at + UP * 3
    local right = out:Cross(UP)
    local lookFrom = e.at + UP * (box.top * 0.45)
    local lookTo = e.at - out * 6 + UP * (box.top + 1)
    local dirs = {
        out + UP * 0.55 + right * 0.35, out + UP * 0.55 - right * 0.35, out + UP * 0.45,
        out + UP * 0.8, right + UP * 0.6, -right + UP * 0.6, UP + out * 0.3,
    }
    local dist = 16 + box.top * 0.5
    local pos = bestSpot(anchor, dirs, dist, { prefer = out, skip = 0.5, look = lookFrom, lookR = 4 })
    if not pos then pos = clearTo(anchor, anchor + out * 3 + UP * 3) end
    -- crane up: the second position is the first one lifted, cleared on its own
    local to = clearTo(pos, pos + UP * 8)
    return shot("roof", "THE ROOF HATCH", pos, to, lookFrom, lookTo)
end

-- the ignore list for "this part and the model it belongs to" (not the whole job folder)
local function ownParts(part, extra)
    local list = { part }
    -- (careful: Workspace IS a Model — never ignore it, or every ray passes through the world)
    local m = part.Parent
    if m and m:IsA("Model") and not m:IsA("WorldRoot") and #m:GetChildren() <= 40 then table.insert(list, m) end
    for _, x in ipairs(extra or {}) do if typeof(x) == "Instance" then table.insert(list, x) end end
    return list
end

-- a thing inside the building (breaker / keycard door): look at it from inside the room
local function interiorShot(tag, label, part, box, dist, lift)
    part = partOf(part)
    if not part then return nil end
    local target = part.Position
    local toCenter = unitOr(flat(box.center - target), Vector3.new(0, 0, 1))
    local ign = ownParts(part)
    local pos = bestSpot(target, ring(lift), dist,
        { prefer = toCenter, ignore = ign, look = target, lookR = 1.2, minReach = 4 })
    if not pos then return nil end
    local to = target + (pos - target) * 0.7
    return shot(tag, label, pos, to, target, target)
end

local function lasersShot(refs, box)
    local row = type(refs.laserRows) == "table" and refs.laserRows[1]
    if not row then return nil end
    local zc = typeof(row.zoneCFrame) == "CFrame" and row.zoneCFrame
    if not zc then
        local b = partOf(row.beams and row.beams[1])
        if not b then return nil end
        zc = b.CFrame
    end
    local size = isV3(row.zoneSize) and row.zoneSize or Vector3.new(10, 8, 10)
    -- the long horizontal axis of the corridor = look down it, through the beams
    local ax = size.X >= size.Z and zc.RightVector or zc.LookVector
    ax = unitOr(flat(ax), Vector3.new(1, 0, 0))
    local half = math.max(size.X, size.Z) / 2
    local centre = zc.Position
    local anchor = Vector3.new(centre.X, math.max(centre.Y, floorBelow(centre) + 3), centre.Z)
    local dirs = { ax + UP * 0.15, -ax + UP * 0.15 }
    for _, d in ipairs(ring(0.25)) do table.insert(dirs, d) end
    local pos = bestSpot(anchor, dirs, half + 7, { look = anchor, lookR = 1, minReach = 4 })
    if not pos then return nil end
    local to = anchor + (pos - anchor) * 0.75
    return shot("lasers", "THE LASERS", pos, to, anchor, anchor)
end

local function vaultShot(refs, box, noun)
    local v = refs.vault
    local door = partOf(v and v.door)
    if not door then return nil end
    local target = door.Position
    local ign = ownParts(door, type(v.parts) == "table" and v.parts or nil)
    -- the open side of the door: a flat ring search, a few studs out
    local toCenter = unitOr(flat(box.center - target), Vector3.new(0, 0, 1))
    local faceSpot = bestSpot(target, ring(0), 6, { prefer = toCenter, ignore = ign, minReach = 2.5 })
    if not faceSpot then return nil end
    local face = unitOr(flat(faceSpot - target), toCenter)
    local anchor = target + face * math.min(2.5, (faceSpot - target).Magnitude)
    local right = face:Cross(UP)
    -- dramatic low angle: camera just above the floor, looking UP at the door
    local floorY = floorBelow(anchor, { ignore = ign })
    local look = target + UP * 1
    local o = { ignore = ign, look = look, lookR = 3, minReach = 4 }
    local lowDrop = math.min(0, floorY + 1.3 - anchor.Y)
    local dirs = {}
    for _, side in ipairs({ -0.55, 0.55, 0, -1, 1 }) do
        for _, far in ipairs({ 11, 8 }) do
            table.insert(dirs, face * far + right * (side * far) + UP * lowDrop)
        end
    end
    local from = bestSpot(anchor, dirs, 11, o)
    if not from then from = clearTo(anchor, anchor + face * 6 + UP * lowDrop, o) end
    -- push in + rise a little
    local rel = from - anchor
    local to = clearTo(anchor, anchor + Vector3.new(rel.X * 0.72, rel.Y + 0.8, rel.Z * 0.72) - right * 1.5, o)
    return shot("vault", "THE " .. string.upper(noun or "VAULT"), from, to, look, look + UP * 0.6)
end

local function carShot(refs)
    local cf = typeof(refs.getawayCFrame) == "CFrame" and refs.getawayCFrame
    if not cf then return nil end
    local car = cf.Position
    local fwd = unitOr(flat(cf.LookVector), Vector3.new(0, 0, -1))
    local right = fwd:Cross(UP)
    local anchor = car + UP * 4
    local look = car + UP * 2
    local dirs = {
        fwd + right * 0.8 + UP * 0.45, fwd - right * 0.8 + UP * 0.45, fwd + UP * 0.5,
        right + UP * 0.45, -right + UP * 0.45, -fwd + right * 0.6 + UP * 0.5, -fwd - right * 0.6 + UP * 0.5,
        fwd + UP * 1.2, UP + fwd * 0.2,
    }
    local pos = bestSpot(anchor, dirs, 15, { prefer = fwd, skip = 5, look = look, lookR = 5, minReach = 5 })
        or clearTo(anchor, anchor + UP * 8, { skip = 5 })
    local to = anchor + (pos - anchor) * 0.72 + UP * 0.5
    return shot("car", "THE GETAWAY CAR", pos, to, look, look + fwd * 4)
end


local function jobCfg(id)
    local ok, Constants = pcall(function() return require(ReplicatedStorage.Shared.Constants) end)
    if not ok then return nil end
    for _, j in ipairs(Constants.JOBS or {}) do if j.id == id then return j end end
    return nil
end

local function goodShot(s)
    if not s then return false end
    for _, cf in ipairs({ s.from, s.to }) do
        if typeof(cf) ~= "CFrame" then return false end
        for _, x in ipairs({ cf:GetComponents() }) do if not finite(x) then return false end end
    end
    return true
end

function BriefingShots:compute(refs)
    if type(refs) ~= "table" then return {} end
    local box = buildingBox(refs)
    if not box then return {} end
    local front = entrance(refs, "front")
    local frontDir = front and outwardAxis(box, front.at) or Vector3.new(0, 0, -1)
    local cfg = jobCfg(refs.id)
    local noun = cfg and cfg.vaultNoun or "Vault"
    local kd = type(refs.keycardDoors) == "table" and refs.keycardDoors[1]
    -- laser beams are not walls (a ray would stop on them and pull the camera in)
    jobIgnore = {}
    for _, row in ipairs(type(refs.laserRows) == "table" and refs.laserRows or {}) do
        for _, b in ipairs(type(row.beams) == "table" and row.beams or {}) do
            if typeof(b) == "Instance" then table.insert(jobIgnore, b) end
        end
    end

    local out = {}
    local makers = {
        function() return wideShot(refs, box, frontDir) end,
        function() return frontShot(refs, box, frontDir) end,
        function() return sideShot(refs, box) end,
        function() return roofShot(refs, box) end,
        function() return interiorShot("breaker", "THE BREAKER BOX", refs.breaker, box, 11, 0.3) end,
        function() return kd and interiorShot("keycard", "THE KEYCARD DOOR", kd.door, box, 13, 0.25) end,
        function() return lasersShot(refs, box) end,
        function() return vaultShot(refs, box, noun) end,
        function() return carShot(refs) end,
    }
    for _, make in ipairs(makers) do
        local ok, s = pcall(make)
        if ok and goodShot(s) then
            table.insert(out, s)
        elseif not ok then
            warn("[BriefingShots] " .. tostring(refs.id) .. " shot failed: " .. tostring(s))
        end
    end
    jobIgnore = {}
    return out
end

function BriefingShots:publish(world)
    local all = {}
    local jobs = type(world) == "table" and world.jobs or nil
    local folder = ReplicatedStorage:FindFirstChild("BriefingShots")
    if folder then folder:Destroy() end
    folder = Instance.new("Folder")
    folder.Name = "BriefingShots"
    folder:SetAttribute("Version", 1)
    if type(jobs) ~= "table" then
        folder.Parent = ReplicatedStorage
        return all
    end
    for id, refs in pairs(jobs) do
        local ok, shots = pcall(function() return self:compute(refs) end)
        if not ok then
            warn("[BriefingShots] " .. tostring(id) .. " failed: " .. tostring(shots))
        elseif #shots > 0 then
            all[id] = shots
            local jf = Instance.new("Folder")
            jf.Name = tostring(id)
            jf:SetAttribute("Count", #shots)
            for i, s in ipairs(shots) do
                local sf = Instance.new("Folder")
                sf.Name = string.format("%02d", i)
                sf:SetAttribute("Order", i)
                sf:SetAttribute("From", s.from)
                sf:SetAttribute("To", s.to)
                sf:SetAttribute("Duration", s.duration)
                sf:SetAttribute("Label", s.label)
                sf:SetAttribute("Tag", s.tag)
                sf.Parent = jf
            end
            jf.Parent = folder
        end
    end
    folder.Parent = ReplicatedStorage
    local n = 0
    for _ in pairs(all) do n += 1 end
    print("[BriefingShots] published camera fly-throughs for " .. n .. " jobs 🎬")
    return all
end

return BriefingShots
