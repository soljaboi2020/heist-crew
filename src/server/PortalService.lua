--[[
    HEIST CREW — PortalService  (v2.0 "BIGGER", V2_SPEC §6 + §7)
    ────────────────────────────────────────────────
    Portals replace "ready up" as the way to start a heist. Each heist has a
    glowing portal in the club (ClubBuilder: hub.portals[jobId].zone). The kid
    rule: "stand in a heist's portal to go."

      • standing in a portal = you picked that heist AND you're ready
        (JobService readyCount shows you as ready).
      • the portal with the most people picks the heist (JobService:selectJob).
        A tie keeps the heist that's already picked.
      • countdown for the picked heist's portal:
            everyone in the server is in it    → PORTAL.ALL_COUNTDOWN  (5 s)
            at least half of the server is     → PORTAL.HALF_COUNTDOWN (15 s)
        dropping below half cancels it. At zero, JobService launches with the
        players who are IN THE PORTAL right then (the rest stay in the club).
      • no portal does anything while a heist is launching / running / resetting
        (they all show locked).

    Zones: hub.portals[jobId].zone, plus any BasePart tagged "PortalZone" with a
    string attribute JobId (so a builder can add zones without new refs).

    Every change fires the Portal remote to all clients
        { portals = { [jobId] = { count, needed, total, launchAt, locked, selected } } }
    and calls hub.portals[jobId].setState(count, needed, launchIn, locked) (pcall).
        count    players standing in that portal
        needed   players needed to START a countdown (half the server, rounded up)
        total    players in the server (all of them = the fast 5 s countdown)
        launchIn seconds until launch (nil = no countdown)
        locked   true while a heist is busy, or the heist is still level-locked

    PUBLIC API:
        PortalService:init({ hub = world.hub, jobService = JobService, notify = fn(player, text, color, dur)? })
        PortalService:getOccupants(jobId) -> { Player }
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PortalService = {}

local P = Constants.PORTAL or { ALL_COUNTDOWN = 5, HALF_COUNTDOWN = 15 }
local TICK = 0.25

local hub = nil
local Job = nil
local notifyFn = nil
local portalRemote = Remotes.getRemote(Remotes.NAMES.Portal, "RemoteEvent")

local occupants = {}          -- [jobId] = { Player }
local switching = false
local countdownWait = nil     -- the seconds of the countdown WE started (5 or 15), nil = none
local lastPayload = nil
local lastSent = 0
local lastState = {}          -- [jobId] = "count|needed|launchIn|locked"

local function now() return Workspace:GetServerTimeNow() end

local function say(player, text, color, duration)
    if notifyFn and player and player.Parent then
        pcall(notifyFn, player, text, color or "white", duration or 3)
    end
end
local function sayAll(text, color, duration)
    for _, p in ipairs(Players:GetPlayers()) do say(p, text, color, duration) end
end

-- every zone we know about: { { jobId, part } }
local function zones()
    local list = {}
    local seen = {}
    if hub and type(hub.portals) == "table" then
        for jobId, portal in pairs(hub.portals) do
            local z = type(portal) == "table" and portal.zone
            if typeof(z) == "Instance" and z:IsA("BasePart") and z.Parent then
                table.insert(list, { jobId = jobId, part = z })
                seen[z] = true
            end
        end
    end
    for _, z in ipairs(CollectionService:GetTagged("PortalZone")) do
        local id = z:GetAttribute("JobId")
        if z:IsA("BasePart") and not seen[z] and type(id) == "string" then
            table.insert(list, { jobId = id, part = z })
        end
    end
    return list
end

local function inside(part, pos)
    local rel = part.CFrame:PointToObjectSpace(pos)
    local h = part.Size / 2
    -- a little headroom above a flat pad so a jumping player still counts
    return math.abs(rel.X) <= h.X and math.abs(rel.Z) <= h.Z and rel.Y >= -h.Y - 4 and rel.Y <= math.max(h.Y, 4) + 4
end

local function scan()
    local occ = {}
    local zl = zones()
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 and not player:GetAttribute("Jailed") then
            for _, z in ipairs(zl) do
                if inside(z.part, hrp.Position) then
                    occ[z.jobId] = occ[z.jobId] or {}
                    table.insert(occ[z.jobId], player)
                    break
                end
            end
        end
    end
    return occ, zl
end

function PortalService:getOccupants(jobId)
    local list = {}
    for _, p in ipairs(occupants[jobId] or {}) do
        if p.Parent then table.insert(list, p) end
    end
    return list
end

local function jobIds(zl)
    local ids, seen = {}, {}
    for _, cfg in ipairs(Constants.JOBS) do
        table.insert(ids, cfg.id)
        seen[cfg.id] = true
    end
    for _, z in ipairs(zl) do
        if not seen[z.jobId] then table.insert(ids, z.jobId) seen[z.jobId] = true end
    end
    return ids
end

local function publish(zl, total, phase)
    local launchAt, source = Job:getLaunch()
    local current = Job:getCurrentId()
    local needed = math.max(1, math.ceil(total / 2))
    local payload = { portals = {} }
    for _, id in ipairs(jobIds(zl)) do
        local count = #(occupants[id] or {})
        local locked = phase ~= "idle" or not Job:isUnlocked(id)
        local la = (id == current and source == "portal" and launchAt > 0) and launchAt or 0
        payload.portals[id] = {
            count = count, needed = needed, total = total, launchAt = la, locked = locked,
            selected = id == current,
        }
        local launchIn = la > 0 and math.max(0, math.ceil(la - now())) or nil
        local key = string.format("%d|%d|%s|%s", count, needed, tostring(launchIn), tostring(locked))
        if lastState[id] ~= key then
            lastState[id] = key
            local portal = hub and type(hub.portals) == "table" and hub.portals[id]
            if type(portal) == "table" and type(portal.setState) == "function" then
                local ok, err = pcall(portal.setState, count, needed, launchIn, locked)
                if not ok then warn("[PortalService] setState(" .. id .. "):", err) end
            end
        end
    end
    -- fire on change, plus every 2 s so late joiners catch up
    local sig = {}
    for id, s in pairs(payload.portals) do
        table.insert(sig, string.format("%s:%d:%d:%d:%s:%s", id, s.count, s.needed, s.launchAt, tostring(s.locked), tostring(s.selected)))
    end
    table.sort(sig)
    local key = table.concat(sig, ";")
    if key ~= lastPayload or os.clock() - lastSent > 2 then
        lastPayload = key
        lastSent = os.clock()
        portalRemote:FireAllClients(payload)
    end
end

local function tick()
    local occ, zl = scan()
    occupants = occ
    local total = #Players:GetPlayers()
    local phase = Job:getPhase()
    local current = Job:getCurrentId()

    -- who counts as "ready": standing in the picked heist's portal
    local readySet = {}
    if phase == "idle" and current then
        for _, p in ipairs(occ[current] or {}) do readySet[p] = true end
    end
    Job:setPortalReady(readySet)

    if phase ~= "idle" then
        countdownWait = nil
        publish(zl, total, phase)
        return
    end

    -- 1) the busiest portal picks the heist
    if not switching then
        local best, bestN = nil, 0
        for _, id in ipairs(jobIds(zl)) do
            local n = #(occ[id] or {})
            if n > bestN and Job:isUnlocked(id) then best, bestN = id, n end
        end
        local curN = current and #(occ[current] or {}) or 0
        if best and best ~= current and bestN > curN then
            switching = true
            countdownWait = nil
            task.spawn(function()
                local ok, result = pcall(Job.selectJob, Job, best)
                if ok and result then
                    local name = best
                    for _, cfg in ipairs(Constants.JOBS) do if cfg.id == best then name = cfg.name end end
                    sayAll("Next heist: " .. name, "gold", 3)
                elseif not ok then
                    warn("[PortalService] selectJob:", result)
                end
                switching = false
            end)
            publish(zl, total, phase)
            return
        end
    end
    if switching then
        publish(zl, total, phase)
        return
    end

    -- 2) countdown for the picked heist's portal
    local launchAt, source = Job:getLaunch()
    local n = current and #(occ[current] or {}) or 0
    local needed = math.max(1, math.ceil(total / 2))
    if current and n >= needed and total > 0 then
        local want = (n >= total) and (P.ALL_COUNTDOWN or 5) or (P.HALF_COUNTDOWN or 15)
        local ours = source == "portal" and launchAt > 0
        -- start one, or shorten ours when the last person steps in
        if (launchAt == 0) or (ours and countdownWait and want < countdownWait and launchAt - now() > want + 0.5) then
            local jobId = current
            local started = Job:startLaunchCountdown(want, function()
                return PortalService:getOccupants(jobId)
            end, "portal")
            if started then
                countdownWait = want
                if want <= (P.ALL_COUNTDOWN or 5) then
                    sayAll(string.format("Everyone's in! Going in %d…", want), "gold", 3)
                else
                    sayAll(string.format("Going in %d! Step in the portal to come along.", want), "gold", 3)
                end
            end
        end
    elseif source == "portal" and launchAt > 0 then
        countdownWait = nil
        Job:cancelLaunch("Stopped — not enough people in the portal")
    end

    publish(zl, total, phase)
end

function PortalService:init(deps)
    deps = deps or {}
    hub = deps.hub or {}
    Job = deps.jobService
    notifyFn = deps.notify
    if not Job then
        warn("[PortalService] no jobService — portals disabled")
        return
    end
    local n = 0
    for _ in pairs(type(hub.portals) == "table" and hub.portals or {}) do n = n + 1 end
    n = n + #CollectionService:GetTagged("PortalZone")
    if n == 0 then
        warn("[PortalService] the club has no portals yet — ready-up at the holo table still works")
    end
    Players.PlayerAdded:Connect(function() lastPayload = nil end)
    task.spawn(function()
        while true do
            local ok, err = pcall(tick)
            if not ok then warn("[PortalService] tick:", err) end
            task.wait(TICK)
        end
    end)
    print("[PortalService] Ready —", n, "portal zones")
end

return PortalService
