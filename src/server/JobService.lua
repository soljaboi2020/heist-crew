--[[
    HEIST CREW — JobService  (replaces HeistService, v1.0 · v2.0 "BIGGER")
    ────────────────────────────────────────────────
    Runs a heist from first move to payout, for whichever job is SELECTED
    (Sunny's Mart / Villa Rosa / Diamond Dolls / Ocean Bank — Constants.JOBS,
    geometry from the builders).

    THE FLOW
      IDLE ─(portal countdown / ready-up / any heist action)─► ACTIVE
        • launch: the crew drops in at the job's sneakIn door, masks on,
          anyone without a role gets a free one, bots fill a small crew
        • quiet run: no timer (a HEIST_RUN_LIMIT backstop only)
        • ALARM (camera / laser / silent alarm): alarm sound, guards hunt,
          police roll in, and the crew has job.alarmTimer seconds
        • DRILL the vault/safe: it runs on its own, it JAMS (fix it), door
          swings open → loot unlocks
        • carry bags to the getaway car → "Load bag" (or give it to a bot)
        • v3.0 THE GETAWAY (no driving): everyone still in the run sits in the
          car (with a bag loaded, or the alarm going), or the driver presses the
          big GO! button with ≥ 1 bag → GetawayService runs the 8 s escape vote
          (Boat / Helicopter / Highway) and the movie, then the run ends and the
          loaded bags pay out (+ car / helicopter / target bonuses)
      v2.0 rules (V2_SPEC §6), simple enough for a 7-year-old:
        • a GUARD sees / grabs you  → back to the sneakIn door (kickBack, v1.2.5)
        • a COP grabs you           → JAIL (JailService). A teammate holds E at
          your cell door to break you out (you respawn at sneakIn). Nobody frees
          you in 30 s → released to the club, out of this run. If nobody is left
          free to break anyone out, the run ends.
        • (v3.0: no car chase / bust — the chase is in the movie. The alarm
          timer still ends the run if the crew isn't in the car in time.)
      Jobs without keycard doors / lasers / smash cases (the mart) just skip
      those steps — every system copes with an empty list.

    PUBLIC API
        JobService:init(deps)
            deps = { jobs = { [id] = JobRefs }, security, loot, guards, vehicles, police,
                     economy, progress, shop, data,
                     crew?  (CrewService — auto-role; required lazily if absent),
                     feel?  (FeelService),  hide? (HideService) }
        JobService:selectJob(id) -> boolean           -- arm a job (no-op while a run is live)
        JobService:cycleJob(player)                   -- "pick heist" (R) at the holo table
        JobService:toggleReady(player, forceReady)    -- old ready-up path (still works)
        JobService:startLaunchCountdown(seconds, getPlayers?, source?) -> boolean
            getPlayers() -> {Player} is asked AT LAUNCH (nil = everyone). source = "portal" | "ready"
        JobService:cancelLaunch(reason?)
        JobService:getLaunch() -> launchAt (server time, 0 = none), source
        JobService:getPhase() -> "idle" | "launching" | "running" | "resetting"
        JobService:getCurrentId() -> jobId | nil
        JobService:isUnlocked(jobId) -> boolean
        JobService:getCurrent() -> cfg, refs
        JobService:getCar() -> car | nil
        JobService:isInRun(player) -> boolean          -- in the crew, not out / escaped / jailed
        JobService:subscribe(event, fn)
            "launched"  (players, cfg, refs)   after the drop-in
            "finished"  (result, cfg, refs)    the run ended (before the reset cooldown)
            "reset"     (cfg, refs)            the job is armed again
            "jobChanged"(cfg, refs)
        JobService:useJail(JailService)               -- JailService:init calls this
        JobService:noteBots(names)                    -- BotService: names of this run's bots (payout)
        JobService.hub, JobService.onJobChanged, JobService.onFinished   (set by init.server)

    v3.0 "THE SCORE" (getaway agent):
        deps.getaway? (GetawayService — required lazily from this folder if absent;
                       JobService calls its :init, so init.server needs no change)
        JobService:beginGetaway(why?, player?) -> boolean   (tests / integrator)
        JobService:triggerAlarm(reason?, player?) · JobService:catchPlayer(player, by?)   (tests)
        Car model attributes kept fresh during a run (CarHud reads them):
            CrewIn, CrewNeed (seated / still-in-the-run crew), GetawayPhase
            ("wait" | "vote" | "decided" | "scene" | ""), GetawayLoud, HeliOk
        Payout (HeistState COMPLETE payload) adds: route, getaway = { route,
            routeName, icon, loud, carName, carType, rows = {{label, amount, icon}} },
            target = { name, amount }?, bonusEach
        LOOT-CORE hooks (V3_SPEC §4, all optional / pcall'd):
            LootShuffle:prepare — the v3 LootService already shuffles inside
                arm()/reset(); JobService only calls prepare itself for an older
                LootService (no :valueOf), so the shuffle never runs twice.
            LootService:valueOf(bag) — fallback value for a loaded row with no value
                (counts().take already includes jackpot / fragile / bag tier).
            TargetService:bonusFor(run) → +cash per escapee (read BEFORE clearLoaded,
                which resets it) + TargetService:awardCrew(escapees) trophies,
                TargetService:targetFor(jobId).name → the payout row label.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local JobService = {}

local S = {}                 -- services
local jobs = {}              -- id -> { cfg, refs }
local currentId = nil
local run = nil              -- the active run (nil when idle)
local resettingUntil = 0
local launching = false      -- (v2.0) the cut-scene / drop-in is playing
local car = nil
local drillPrompt = nil
local vaultClosed = nil      -- { [part] = CFrame }
local drillModel = nil
local listeners = {}         -- event -> { fn }
local beginGetaway, checkGetaway, syncCarAttrs   -- v3.0 (forward declarations)
local legacyShuffle

local DRILL_TIME = 24
local JAM_POINTS = { 0.33, 0.7 }
local JAM_CHANCE = 0.7

local stateRemote    = Remotes.getRemote(Remotes.NAMES.HeistState, "RemoteEvent")
local progressRemote = Remotes.getRemote(Remotes.NAMES.VaultProgress, "RemoteEvent")
local alarmRemote    = Remotes.getRemote(Remotes.NAMES.AlarmTriggered, "RemoteEvent")
local notifyRemote   = Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent")
local infoRemote     = Remotes.getRemote(Remotes.NAMES.JobInfo, "RemoteEvent")
local launchRemote   = Remotes.getRemote(Remotes.NAMES.LaunchJob, "RemoteEvent")

-- v1.1 ready-up → countdown → drop-in (v2.0: portals use the same countdown)
local ready = {}          -- [player] = true
local launchAt = 0        -- server time the drop-in happens (0 = no countdown)
local launchToken = nil
local launchSource = nil  -- "ready" | "portal"

-- ── small helpers ────────────────────────────────────────────────────
local function notify(player, text, color, duration)
    if player and player.Parent then
        notifyRemote:FireClient(player, { text = text, color = color or "white", duration = duration or 3 })
    end
end
local function notifyAll(text, color, duration)
    for _, p in ipairs(Players:GetPlayers()) do notify(p, text, color, duration) end
end
local function broadcastState(state, payload)
    stateRemote:FireAllClients(state, payload or {})
end
local function now() return Workspace:GetServerTimeNow() end

local function emit(event, ...)
    local args = table.pack(...)
    for _, fn in ipairs(listeners[event] or {}) do
        task.spawn(function()
            local ok, err = pcall(fn, table.unpack(args, 1, args.n))
            if not ok then warn("[JobService] listener '" .. event .. "':", err) end
        end)
    end
end

-- optional sibling services (other agents' files may not exist yet)
local optionalCache = {}
local function optionalService(name)
    if optionalCache[name] ~= nil then return optionalCache[name] or nil end
    local mod = script.Parent:FindFirstChild(name)
    local ok, result = false, nil
    if mod then ok, result = pcall(require, mod) end
    optionalCache[name] = (ok and type(result) == "table") and result or false
    return optionalCache[name] or nil
end

-- FeelService (feel agent): juice. Returns true if it ran, so callers can fall
-- back to the old one-shot sounds when the service isn't there.
local function feel(method, ...)
    local F = S.feel or optionalService("FeelService")
    if not F or type(F[method]) ~= "function" then return false end
    local ok, err = pcall(F[method], F, ...)
    if not ok then warn("[JobService] Feel:" .. method, err) end
    return ok
end

local function lifetimeEarned(player, amount)
    local D = S.data
    if D and type(D.addLifetimeEarned) == "function" and amount and amount > 0 then
        local ok, err = pcall(D.addLifetimeEarned, D, player, amount)
        if not ok then warn("[JobService] addLifetimeEarned:", err) end
    end
end

local alarmSound = nil
local function playOneShot(id, volume)
    local s = Instance.new("Sound")
    s.SoundId = id
    s.Volume = volume or 0.6
    s.Parent = Workspace
    s:Play()
    s.Ended:Connect(function() s:Destroy() end)
    task.delay(10, function() if s.Parent then s:Destroy() end end)
end
local function alarmLoop(on)
    if alarmSound then alarmSound:Destroy() alarmSound = nil end
    if on then
        alarmSound = Instance.new("Sound")
        alarmSound.Name = "AlarmSound"
        alarmSound.SoundId = Constants.SOUNDS.ALARM
        alarmSound.Volume = 0.55
        alarmSound.Looped = true
        alarmSound.Parent = Workspace
        alarmSound:Play()
    end
end

local function job() return currentId and jobs[currentId] end

local function has(refs, key)
    local t = refs and refs[key]
    return type(t) == "table" and #t > 0
end

local function nounOf(j)
    if not j then return "Vault" end
    return j.cfg.vaultNoun or (j.cfg.id == "jewelry" and "Safe" or "Vault")
end

-- (fix v1.1) a seated character is welded to the (anchored) car seat — moving
-- its root would drag the seat or snap back. Break the seat weld first.
local function unseat(player)
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart then
        local seat = hum.SeatPart
        local w = seat:FindFirstChild("SeatWeld")
        if w then w:Destroy() end
        hum.Sit = false
        task.wait()
    end
end

local function sendToSafehouse(player)
    unseat(player)
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local sp = Constants.WORLD.SPAWN_POSITION
    if hrp then hrp.CFrame = CFrame.new(sp.x + math.random(-4, 4), sp.y + 3, sp.z + math.random(-2, 2)) end
end

-- put a player at the job's sneaky door (kick-back, jail break-out)
local function sendToSneakIn(player)
    local j = job()
    local s = j and j.refs.sneakIn
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    unseat(player)
    if s then
        local pos = s.at + s.spread * math.random(-2, 2)
        hrp.CFrame = CFrame.lookAt(pos, Vector3.new(s.face.X, pos.Y, s.face.Z))
    elseif j and j.refs.entryPoint then
        hrp.CFrame = CFrame.new(j.refs.entryPoint + Vector3.new(0, 3, 0))
    end
end

local function rootPos(player)
    local hrp = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position
end

local function activeCrew()
    local list = {}
    if not run then return list end
    for p, e in pairs(run.crew) do
        if p.Parent and not e.out and not e.escaped and not e.jailed then table.insert(list, p) end
    end
    return list
end

local function addToCrew(player)
    if run and player and not run.crew[player] then
        run.crew[player] = { out = false, escaped = false, jailed = false }
        if S.shop then S.shop:wearMask(player) end
    end
end

-- ── JobInfo (drives the JOB card + objective pill) ───────────────────
local function drillLabel(noun)
    local d = run and run.drill
    if run and run.vaultOpen then return "The " .. string.lower(noun) .. " is open!" end
    if not d then return "Drill the " .. string.lower(noun) end
    if d.jammed then return "Drill stuck — fix it! (hold E)" end
    return string.format("Drilling… %d%%", math.floor(d.progress * 100))
end

local function keycardHeld()
    for _, p in ipairs(Players:GetPlayers()) do if p:GetAttribute("HasKeycard") then return true end end
    return false
end

-- v1.1: waypoints — where the NEXT thing to do is (the client draws markers)
local function buildTargets(j, c)
    local t = {}
    local function add(pos, label, kind) if pos then table.insert(t, { pos = pos, label = label, kind = kind }) end end
    local refs = j.refs
    if not run then
        local b = Constants.WORLD.BOSS_NPC_POS
        add(Vector3.new(b.x, b.y + 6.5, b.z), "BRIEFING", "boss")
        -- v2.0: the portal for the selected heist is where you start; ready-up is the fallback
        local portal = JobService.hub and type(JobService.hub.portals) == "table" and JobService.hub.portals[j.cfg.id]
        if portal and typeof(portal.zone) == "Instance" and portal.zone:IsA("BasePart") then
            add(portal.zone.Position + Vector3.new(0, 4, 0), "START HERE", "ready")
        else
            local tb = Constants.WORLD.HUB_TABLE
            add(Vector3.new(tb.x, tb.y + 5, tb.z), "READY UP", "ready")
        end
        return t
    end
    local carPos = car and car.model and car.model.Parent and car.model:GetPivot().Position
    -- v2.0: a teammate in a cell → point the crew at the cell door
    if S.jail and type(S.jail.getOccupiedDoors) == "function" then
        local ok, doors = pcall(S.jail.getOccupiedDoors, S.jail)
        if ok and type(doors) == "table" then
            for i, door in ipairs(doors) do
                if i <= 2 then add(door.pos + Vector3.new(0, 3, 0), "BREAK OUT", "jail") end
            end
        end
    end
    if run.getaway then return t end   -- v3.0: the movie is playing
    if run.alarm then
        add(carPos and carPos + Vector3.new(0, 4, 0), "GET IN THE CAR", "car")
        return t
    end
    if refs.breaker and has(refs, "cameras") and not S.security:camerasCut() then
        add(refs.breaker.Position, "BREAKER", "optional")
    end
    local rem = S.loot:remaining()
    local n = 0
    for _, r in ipairs(rem) do
        if r.isCase and n < 3 then add(r.pos, "SMASH", "loot") n = n + 1 end
    end
    -- loot you can grab right now (mart registers, the open jewelry pieces, an open vault)
    n = 0
    for _, r in ipairs(rem) do
        if not r.isCase and not r.locked and n < 2 then add(r.pos, "LOOT", "loot") n = n + 1 end
    end
    if has(refs, "keycardDoors") and not S.security:doorsOpen() then
        local door = refs.keycardDoors[1]
        if keycardHeld() and door and door.panel then
            add(door.panel.Position, "KEYPAD", "door")
        else
            for _, spot in ipairs(refs.keycardSpots or {}) do add(spot.Position + Vector3.new(0, 1.5, 0), "SEARCH", "search") end
        end
    elseif not run.vaultOpen and refs.vault and refs.vault.door then
        local label = "DRILL"
        if run.drill then label = run.drill.jammed and "FIX DRILL" or "DRILLING" end
        add(refs.vault.door.Position, label, "vault")
    end
    add(carPos and carPos + Vector3.new(0, 4, 0), c.loaded > 0 and "GETAWAY CAR" or "CAR", "car")
    return t
end

local portalReady = {}    -- [player] = true  (PortalService: standing in the selected job's portal)

-- onlyReadyUp: count just the old ready-up (the holo-table countdown must not
-- start because people are standing in a portal — PortalService owns that one)
local function readyCounts(onlyReadyUp)
    local n, total, names = 0, 0, {}
    for _, p in ipairs(Players:GetPlayers()) do
        total = total + 1
        if ready[p] or (portalReady[p] and not onlyReadyUp) then
            n = n + 1
            table.insert(names, p.DisplayName)
        end
    end
    return n, total, names
end

local function buildInfo()
    local j = job()
    if not j then return { stage = "IDLE", steps = {} } end
    local refs = j.refs
    local c = S.loot:counts()
    local steps = {}
    local function add(id, label, done, optional) table.insert(steps, { id = id, label = label, done = done, optional = optional }) end

    if has(refs, "cameras") and refs.breaker then
        add("cameras", S.security:camerasCut() and "Cameras are off" or "Turn off the cameras", S.security:camerasCut(), true)
    end
    if (c.cases or 0) > 0 then
        add("cases", string.format("Smash the glass cases  %d/%d", c.casesTaken, c.cases), c.casesTaken >= c.cases)
    end
    if (c.open or 0) > 0 then
        add("open", string.format("Grab the loot  %d/%d", c.openTaken or 0, c.open), (c.openTaken or 0) >= c.open)
    end
    local noun = nounOf(j)
    if has(refs, "keycardDoors") then
        local doorsOpen = S.security:doorsOpen()
        -- (fix v1.1) ticked only while someone actually HOLDS the card (or the door is open);
        -- if the holder gets caught the card respawns and the step comes back
        add("keycard", "Find the keycard", doorsOpen or keycardHeld(), false)
        add("door", j.cfg.doorLabel or "Open the locked door", doorsOpen)
    end
    if refs.vault then
        add("vault", drillLabel(noun), run ~= nil and run.vaultOpen == true)
        if (c.vault or 0) > 0 then
            add("loot", string.format("Bag the %s money  %d/%d", string.lower(noun), c.vaultTaken or 0, c.vault),
                (c.vaultTaken or 0) >= c.vault)
        end
    end
    if run and run.getaway then
        add("car", "Getaway! Enjoy the ride", true)
    else
        add("car", string.format("Put bags in the car (%d)  ·  then everyone hop in!", c.loaded), false)
    end

    local jailedNames = {}
    if run then
        for p, e in pairs(run.crew) do
            if e.jailed and p.Parent then table.insert(jailedNames, p.DisplayName) end
        end
    end
    local rc, pc, rn = readyCounts()
    return {
        jobId = j.cfg.id, jobName = j.cfg.name, stage = run and "ACTIVE" or "IDLE",
        steps = steps, take = c.take, bagsSecured = c.loaded, bagsTotal = c.total,
        alarm = run ~= nil and run.alarm == true, alarmEndsAt = run and run.alarmEndsAt or 0,
        silentAlarm = run ~= nil and run.silent == true and not run.alarm,
        targets = buildTargets(j, c),
        startedAt = run and run.startedAtServer or 0,
        readyCount = rc, playerCount = pc, readyNames = rn, launchAt = launchAt,
        jailed = jailedNames, bots = run and run.botNames or {},
        difficulty = j.cfg.difficulty,
        getaway = run and run.getaway and run.getaway.phase or nil,   -- v3.0
    }
end

local infoQueued = false
local function pushInfo()
    if infoQueued then return end
    infoQueued = true
    task.defer(function()
        infoQueued = false
        local ok, info = pcall(buildInfo)
        if ok then infoRemote:FireAllClients(info) else warn("[JobService] info:", info) end
    end)
end

-- ── vault ────────────────────────────────────────────────────────────
local function vaultParts(refs)
    local v = refs.vault
    if not v then return {} end
    local list = v.parts or v.extras or { v.door }
    local seen, out = {}, {}
    for _, p in ipairs(list) do if not seen[p] then seen[p] = true table.insert(out, p) end end
    if v.door and not seen[v.door] then table.insert(out, v.door) end
    return out
end

local function closeVault()
    if vaultClosed then
        for part, cf in pairs(vaultClosed) do part.CFrame = cf end
    end
end

local function openVault(player)
    local j = job()
    if not run or run.vaultOpen or not j or not j.refs.vault then return end
    run.vaultOpen = true
    local v = j.refs.vault
    local hinge = v.hinge or v.door.CFrame
    local swing = hinge * CFrame.Angles(0, v.openAngle or math.rad(-100), 0)
    for _, part in ipairs(vaultParts(j.refs)) do
        local rel = hinge:ToObjectSpace(vaultClosed[part] or part.CFrame)
        TweenService:Create(part, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
            { CFrame = swing * rel }):Play()
    end
    if drillModel then drillModel:Destroy() drillModel = nil end
    if drillPrompt then drillPrompt.Enabled = false end
    S.loot:setVaultOpen(true)
    local noun = nounOf(j)
    if not feel("big", string.upper(noun) .. " OPEN!", { sound = "vault_open", shake = true }) then
        playOneShot(Constants.SOUNDS.VAULT_CRACK, 0.9)
    end
    progressRemote:FireAllClients(1)
    task.delay(1.2, function() progressRemote:FireAllClients(0) end)
    -- (fix v1.1) the drill bonus is paid at a SUCCESSFUL finish, not here — it was
    -- farmable by drilling and bailing
    run.driller = player
    notifyAll("It's open! Grab the money and take it to the car", "green", 4)
    pushInfo()
end

local function makeDrill(door)
    if drillModel then drillModel:Destroy() end
    local m = Instance.new("Model")
    m.Name = "Drill"
    local cf = door.CFrame
    -- sit it in front of the door face that points toward the corridor (door LookVector
    -- may be either face — use whichever faces the drill owner; fine as a visual)
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(1.4, 1.4, 2.4)
    body.Material = Enum.Material.Metal
    body.Color = Color3.fromRGB(230, 170, 30)
    body.Anchored = true
    body.CanCollide = false
    body.CFrame = cf * CFrame.new(0, 0, -1.6)
    body.Parent = m
    local bit = Instance.new("Part")
    bit.Name = "Bit"
    bit.Shape = Enum.PartType.Cylinder
    bit.Size = Vector3.new(1.2, 0.35, 0.35)
    bit.Material = Enum.Material.Metal
    bit.Color = Color3.fromRGB(120, 125, 135)
    bit.Anchored = true
    bit.CanCollide = false
    bit.CFrame = cf * CFrame.new(0, 0, -0.5) * CFrame.Angles(0, math.rad(90), 0)
    bit.Parent = m
    local sparks = Instance.new("ParticleEmitter")
    sparks.Name = "Sparks"
    sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 40))
    sparks.LightEmission = 1
    sparks.Size = NumberSequence.new(0.12, 0)
    sparks.Lifetime = NumberRange.new(0.2, 0.5)
    sparks.Rate = 60
    sparks.Speed = NumberRange.new(8, 16)
    sparks.SpreadAngle = Vector2.new(60, 60)
    sparks.Acceleration = Vector3.new(0, -40, 0)
    sparks.Parent = bit
    local glow = Instance.new("PointLight")
    glow.Color = Color3.fromRGB(255, 180, 90)
    glow.Brightness = 1.5
    glow.Range = 8
    glow.Parent = bit
    m.Parent = job() and job().refs.root or Workspace
    drillModel = m
    return m
end

local function setDrillPrompt(text, hold, enabled)
    if not drillPrompt then return end
    drillPrompt.ActionText = text
    drillPrompt.HoldDuration = hold
    drillPrompt.Enabled = enabled
end

local startRun, triggerAlarm   -- forward declarations

local function startDrill(player)
    local j = job()
    if not j or not j.refs.vault then return end
    if not S.security:doorsOpen() then
        notify(player, "Open the locked door with the keycard first", "white", 2)
        return
    end
    if not run then startRun(player, "drill") end
    if not run then return end
    addToCrew(player)
    if run.vaultOpen then return end
    local d = run.drill
    if d and d.jammed then
        d.jammed = false
        setDrillPrompt("Fix drill", 1.5, false)
        local sp = drillModel and drillModel:FindFirstChild("Sparks", true)
        if sp then sp.Enabled = true end
        notifyAll(player.DisplayName .. " fixed the drill", "gold", 2)
        pushInfo()
        return
    end
    if d then return end   -- already running

    local rate = 1 / (j.cfg.drillTime or DRILL_TIME)
    if S.shop:hasGear(player, "Lockpick") then rate = rate * 1.3 end
    d = { progress = 0, jammed = false, owner = player, jams = {} }
    for _, point in ipairs(JAM_POINTS) do
        if math.random() < JAM_CHANCE then table.insert(d.jams, point) end
    end
    run.drill = d
    makeDrill(j.refs.vault.door)
    setDrillPrompt("Fix drill", 1.5, false)
    notifyAll(player.DisplayName .. " started the drill — wait for it!", "gold", 3)
    local thisRun = run
    task.spawn(function()
        while run == thisRun and not run.vaultOpen do
            if not d.jammed then
                d.progress = math.min(1, d.progress + rate * 0.25)
                progressRemote:FireAllClients(d.progress)
                if d.jams[1] and d.progress >= d.jams[1] then
                    table.remove(d.jams, 1)
                    d.jammed = true
                    setDrillPrompt("Fix drill", 1.5, true)
                    local sp = drillModel and drillModel:FindFirstChild("Sparks", true)
                    if sp then sp.Enabled = false end
                    notifyAll("The drill got stuck — someone fix it! (hold E)", "red", 3)
                    pushInfo()
                end
                if d.progress >= 1 then
                    openVault(d.owner)
                    break
                end
                if math.floor(d.progress * 100) % 5 == 0 then pushInfo() end
            end
            task.wait(0.25)
        end
    end)
    pushInfo()
end

-- ── the run ──────────────────────────────────────────────────────────
local finish   -- forward

-- crewList (v2.0): launch passes the players who actually dropped in; any
-- other start (walking in and grabbing something) takes everyone, as before.
startRun = function(player, why, crewList)
    if run then return run end
    if os.clock() < resettingUntil then
        if player then notify(player, "The job is resetting — give it a few seconds", "white", 2) end
        return nil
    end
    local j = job()
    if not j then return nil end
    run = {
        jobId = j.cfg.id, startedAt = os.clock(), startedAtServer = now(), crew = {}, alarm = false, alarmEndsAt = 0,
        silent = false, vaultOpen = false, keycardFound = false, drill = nil, botNames = {},
        caught = false, getaway = nil,   -- v3.0: caught locks the helicopter; getaway = the escape is on
    }
    for _, p in ipairs(crewList or Players:GetPlayers()) do addToCrew(p) end
    if player then addToCrew(player) end
    ready = {}
    launchAt = 0
    launchToken = nil
    launchSource = nil
    if why ~= "launch" then
        notifyAll(string.format("The %s job is ON — masks up!", j.cfg.name), "gold", 4)
    end
    broadcastState("ACTIVE", { jobId = j.cfg.id })
    local thisRun = run
    task.spawn(function()
        while run == thisRun do
            pushInfo()
            pcall(checkGetaway)   -- v3.0: everyone in the car → go
            pcall(syncCarAttrs)
            task.wait(1)
        end
    end)
    task.delay(Constants.HEIST_RUN_LIMIT, function()
        if run == thisRun and not run.getaway then
            notifyAll("That took too long — the Boss called it off", "red", 4)
            finish("timeout")
        end
    end)
    pushInfo()
    return run
end

triggerAlarm = function(reason, player)
    if os.clock() < resettingUntil then return end
    local j = job()
    if not j then return end
    if not run then startRun(player, "alarm") end
    if not run or run.alarm or run.getaway then return end
    addToCrew(player)
    run.alarm = true
    run.alarmEndsAt = now() + j.cfg.alarmTimer
    local who = player and player.DisplayName or "Someone"
    local msg = ({
        camera = "A camera saw " .. who .. " — ALARM! Get to the car!",
        laser  = who .. " touched a laser — ALARM! Get to the car!",
        guard  = "A guard saw " .. who .. " — ALARM!",
        silent = "The silent alarm worked — the police are here!",
    })[reason] or "ALARM!"
    notifyAll(msg, "red", 5)
    alarmLoop(true)
    feel("sound", "alarm_small")
    alarmRemote:FireAllClients(true)
    S.guards:setAlarmActive(true, player and rootPos(player))
    S.police:dispatch(j.refs.policeStop, activeCrew)
    if car then
        car:setAlarmMode(true)   -- (v3.0: no car chase — the chase is in the getaway movie)
    end
    broadcastState("ESCAPING", { escapeSeconds = j.cfg.alarmTimer })
    local thisRun = run
    task.delay(j.cfg.alarmTimer, function()
        if run == thisRun and not run.getaway then
            notifyAll("Out of time — the police closed the roads", "red", 4)
            finish("time")
        end
    end)
    pushInfo()
end

-- (v1.2.5) Malachi: "one guard sees you and they all come running, it's confusing".
-- New rule, simple enough for a 7-year-old: a GUARD catching or spotting you just
-- sends you back to the sneaky door (you drop your bag + keycard). No alarm, the
-- other guards keep patrolling, and you're still in the run. Only COPS jail you.
local kickedAt = {}
local function kickBack(player, guard, grabbed)
    if os.clock() < resettingUntil then sendToSafehouse(player) return end
    if player:GetAttribute("Jailed") then return end
    if run and run.getaway then return end   -- v3.0: the crew is already escaping
    if (kickedAt[player] or 0) > os.clock() - 2 then return end   -- one kick at a time
    kickedAt[player] = os.clock()
    if not run then startRun(player, "caught") end
    if not run then return end
    addToCrew(player)
    local e = run.crew[player]
    if e and (e.out or e.escaped or e.jailed) then return end
    -- v2.0 masks: Goalie "TOUGH GUY" — the first guard catch each run, you break
    -- free: keep your bag + keycard, stay where you are, the guard gets stunned.
    local MS = optionalService("MaskService")
    if MS and type(MS.useToughGuy) == "function" then
        local okT, saved = pcall(MS.useToughGuy, MS, player)
        if okT and saved then
            if guard then S.guards:stun(guard, 3) end
            player:SetAttribute("GuardSuspicion", 0)
            notifyAll(player.DisplayName .. " broke free from a guard!", "gold", 2)
            pushInfo()
            return
        end
    end
    if grabbed then run.caught = true end   -- v3.0: a guard GRAB locks the helicopter (being spotted doesn't)
    S.loot:drop(player)
    S.security:dropKeycard(player)
    if guard then S.guards:stun(guard, 3) end   -- he doesn't grab you again on the way out
    sendToSneakIn(player)
    player:SetAttribute("GuardSuspicion", 0)
    feel("sound", "fail", nil, player)
    notify(player, "A guard saw you! You're back at the door. Sneak back in!", "red", 4)
    notifyAll(player.DisplayName .. " got sent back to the door", "white", 2)
    pushInfo()
end

-- ── jail (v2.0) ──────────────────────────────────────────────────────
local function jailFreed(player, rescuer)
    if not run or not run.crew[player] then
        sendToSafehouse(player)
        return
    end
    local e = run.crew[player]
    e.jailed = false
    sendToSneakIn(player)
    feel("sound", "door", rootPos(player))
    notifyAll(string.format("%s broke %s out of jail!", rescuer and rescuer.DisplayName or "Someone", player.DisplayName), "green", 3)
    notify(player, "You're free! Sneak back in and help your crew!", "green", 4)
    pushInfo()
end

local function jailTimeout(player)
    if run and run.crew[player] then
        local e = run.crew[player]
        e.jailed = false
        e.out = true
        if S.shop then S.shop:removeMask(player) end
    end
    notify(player, "Nobody broke you out. You're out of this heist — back to the club.", "red", 5)
    sendToSafehouse(player)
    if run and #activeCrew() == 0 then finish("caught") end
    pushInfo()
end

local function catchPlayer(player, by)
    if os.clock() < resettingUntil then
        sendToSafehouse(player)
        return
    end
    if not run then
        -- walked into a guard with no run going: that's being seen
        triggerAlarm("guard", player)
    end
    if not run then return end
    if run.getaway then return end   -- v3.0: already escaping (the movie is playing)
    addToCrew(player)
    local e = run.crew[player]
    if e.out or e.escaped or e.jailed then return end
    run.caught = true   -- v3.0: nobody gets the helicopter this run
    S.loot:drop(player)
    S.security:dropKeycard(player)
    feel("sound", "fail", nil, player)

    -- v2.0: jail instead of "out" (if the police station exists)
    local jail = S.jail
    if jail and type(jail.jail) == "function" then
        local ok, jailed = pcall(jail.jail, jail, player, {
            onFreed = jailFreed,
            onTimeout = jailTimeout,
        })
        if ok and jailed then
            e.jailed = true
            notifyAll(string.format("The police caught %s! Go to the police station and break them out!", player.DisplayName), "red", 4)
            notify(player, "You're in jail! A teammate can break you out.", "red", 5)
            if #activeCrew() == 0 then
                notifyAll("Nobody is left to help — the heist is over", "red", 4)
                finish("caught")
            end
            pushInfo()
            return
        elseif not ok then
            warn("[JobService] jail failed:", jailed)
        end
    end

    e.out = true
    S.shop:removeMask(player)
    notifyAll(string.format("%s got caught%s", player.DisplayName, by == "cop" and " by the police" or ""), "red", 3)
    notify(player, "Caught — no money this time. Back to the club.", "red", 4)
    sendToSafehouse(player)
    if #activeCrew() == 0 then finish("caught") end
    pushInfo()
end

-- v3.0 LOOT-CORE §4: LootShuffle:prepare at arm / reset. The v3 LootService
-- (has :valueOf) already does it inside arm()/reset(), so only an older
-- LootService gets it from here — a second prepare would re-roll the shuffle.
legacyShuffle = function(refs)
    if S.loot and type(S.loot.valueOf) == "function" then return nil end
    local LS = optionalService("LootShuffle")
    if not LS or type(LS.prepare) ~= "function" then return nil end
    local ok, active = pcall(LS.prepare, LS, refs)
    if not ok then warn("[JobService] LootShuffle:prepare:", active) return nil end
    if type(active) == "table" and refs then refs.activeLoot = active end
    return nil   -- (arm/reset's 2nd arg is opts in the v3 LootService; nothing to pass)
end

-- ── v3.0 THE GETAWAY ─────────────────────────────────────────────────
local function Getaway()
    return S.getaway or optionalService("GetawayService")
end

local function seatedInCar(player)
    local hum = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    return seat ~= nil and car ~= nil and car.model ~= nil and seat:IsDescendantOf(car.model)
end

-- seated / still-in-the-run crew, bags in the car
local function getawayStatus()
    local active = activeCrew()
    local inCar = 0
    for _, p in ipairs(active) do if seatedInCar(p) then inCar = inCar + 1 end end
    local okC, c = pcall(function() return S.loot:counts() end)
    return inCar, #active, (okC and c and c.loaded) or 0
end

syncCarAttrs = function()
    local m = car and car.model
    if not m or not m.Parent then return end
    if run then
        local inCar, need = getawayStatus()
        local phase = "wait"
        if run.getaway then
            local G = Getaway()
            phase = (G and type(G.getPhase) == "function" and G:getPhase()) or run.getaway.phase or "scene"
            if phase == "idle" then phase = "scene" end
        end
        m:SetAttribute("CrewIn", inCar)
        m:SetAttribute("CrewNeed", need)
        m:SetAttribute("GetawayPhase", phase)
        m:SetAttribute("GetawayLoud", run.alarm == true)
        m:SetAttribute("HeliOk", not run.caught)
    else
        m:SetAttribute("CrewIn", 0)
        m:SetAttribute("CrewNeed", 0)
        m:SetAttribute("GetawayPhase", "")
        m:SetAttribute("GetawayLoud", false)
        m:SetAttribute("HeliOk", true)
    end
end

beginGetaway = function(why, player)
    local G = Getaway()
    local j = job()
    if not run or run.getaway or not car or not car.model or not G or not j then return false end
    local crew = activeCrew()
    if #crew == 0 then return false end
    local thisRun = run
    run.getaway = { phase = "vote", crew = crew, anchored = {}, why = why }
    run.allInSince = nil
    car:freeze(true)
    if type(car.lockSeats) == "function" then car:lockSeats(true) end
    -- everyone still free comes along: into a free seat, or held still where they are
    for _, p in ipairs(crew) do
        if not seatedInCar(p) then
            local char = p.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local seated = false
            if hum and hum.Health > 0 and not hum.SeatPart then
                for _, seat in ipairs(car.seats or {}) do
                    if not seat.Occupant then
                        -- (Seat:Sit welds them in; SeatPart may only update a frame later)
                        if pcall(function() seat:Sit(hum) end) then seated = true break end
                    end
                end
            end
            if not seated and hrp and not hrp.Anchored then
                hrp.Anchored = true
                table.insert(run.getaway.anchored, hrp)
            end
        end
    end
    local startCF = j.refs.getawayCFrame
    if typeof(startCF) ~= "CFrame" then startCF = car.model:GetPivot() end
    local ok, started = pcall(function()
        return G:start({
            crew = crew, car = car, jobId = j.cfg.id, startCFrame = startCF,
            loud = run.alarm == true, heliAllowed = not run.caught,
            forceRoute = JobService._forceRoute,   -- (tests)
            onDone = function(info)
                if run ~= thisRun then return end
                for _, p in ipairs(crew) do
                    local e = run.crew[p]
                    if e and p.Parent and not e.out and not e.jailed then e.escaped = true end
                end
                run.getawayInfo = info
                finish("getaway")
            end,
        })
    end)
    if not ok or not started then
        if not ok then warn("[JobService] getaway start:", started) end
        run.getaway = nil
        car:freeze(false)
        if type(car.lockSeats) == "function" then car:lockSeats(false) end
        return false
    end
    feel("sound", "success")
    notifyAll(why == "go" and player and (player.DisplayName .. " hit GO! Pick how we escape!") or "Everyone's in! Pick how we escape!", "gold", 3)
    pcall(syncCarAttrs)
    pushInfo()
    return true
end

checkGetaway = function()
    if not run or run.getaway or not car or launching then return end
    local inCar, need, bags = getawayStatus()
    if need > 0 and inCar >= need and (bags >= 1 or run.alarm) then
        if not run.allInSince then
            run.allInSince = os.clock()
            task.delay(1.05, function() pcall(checkGetaway) end)
            return
        end
        if os.clock() - run.allInSince >= 1 then beginGetaway("allin") end
    else
        run.allInSince = nil
    end
end

-- the big GO! button (GetawayService forwards the remote here)
local function onGo(player)
    if not run or not player then return end
    if run.getaway then return end
    local e = run.crew[player]
    if not e or e.out or e.escaped or e.jailed then
        notify(player, "You're not in this heist", "white", 2)
        return
    end
    if not seatedInCar(player) then
        notify(player, "Get in the car first!", "white", 2)
        return
    end
    local driverHum = car and car.driverSeat and car.driverSeat.Occupant
    if driverHum and driverHum.Parent ~= player.Character then
        notify(player, "The driver presses GO!", "white", 2)
        return
    end
    local _, _, bags = getawayStatus()
    if bags < 1 then
        notify(player, "Put at least one bag in the car first!", "white", 3)
        return
    end
    beginGetaway("go", player)
end

function JobService:beginGetaway(why, player)
    return beginGetaway(why or "go", player)
end

-- (v3.0 test / integrator hooks: force an alarm or a police catch)
function JobService:triggerAlarm(reason, player)
    triggerAlarm(reason or "camera", player)
end
function JobService:catchPlayer(player, by)
    catchPlayer(player, by or "cop")
end

finish = function(result)
    if not run then return end
    local r = run
    local j = job()
    run = nil
    -- v3.0: a getaway still voting / playing when the run ends another way stops
    if r.getaway then
        local G = Getaway()
        if G and type(G.isBusy) == "function" and G:isBusy() then pcall(G.cancel, G) end
        for _, hrp in ipairs(r.getaway.anchored or {}) do
            if hrp.Parent then hrp.Anchored = false end
        end
    end
    -- (fix v1.1) block new runs until the reset has ACTUALLY happened (it used to be
    -- skippable if someone tripped a sensor on the exact frame the cooldown ended)
    resettingUntil = math.huge

    alarmLoop(false)
    alarmRemote:FireAllClients(false)
    progressRemote:FireAllClients(0)

    -- v2.0: anyone still in a cell goes home (JailService clears the cells)
    local jailedAtEnd = 0
    for p, e in pairs(r.crew) do
        if e.jailed then
            jailedAtEnd = jailedAtEnd + 1
            e.jailed = false
            if S.jail and type(S.jail.release) == "function" then pcall(S.jail.release, S.jail, p) end
            if p.Parent then
                notify(p, "The heist is over — you're out of jail. Back to the club.", "white", 4)
                sendToSafehouse(p)
            end
        end
    end
    if S.jail and type(S.jail.releaseAll) == "function" then pcall(S.jail.releaseAll, S.jail) end
    if S.hide and type(S.hide.unhideAll) == "function" then pcall(S.hide.unhideAll, S.hide) end

    local c = S.loot:counts()
    local won = result == "getaway" or result == "dropoff"
    local bags = won and S.loot:getLoaded() or {}
    -- v3.0 LOOT-CORE: a loaded row with no value asks LootService:valueOf
    if won and type(S.loot.valueOf) == "function" then
        for _, b in ipairs(bags) do
            if type(b.value) ~= "number" then
                local okV, v = pcall(S.loot.valueOf, S.loot, b)
                b.value = (okV and type(v) == "number") and math.floor(v + 0.5) or 0
            end
        end
    end
    local elapsed = os.clock() - r.startedAt
    local escapees = {}
    for p, e in pairs(r.crew) do
        if e.escaped and p.Parent then table.insert(escapees, p) end
    end
    local total = 0
    for p in pairs(r.crew) do if p.Parent then total = total + 1 end end

    local take = won and c.take or 0
    local stealth = not r.alarm
    local each = 0
    local stealthAmt = 0
    if #escapees > 0 and take > 0 then
        stealthAmt = stealth and math.floor(take * (j.cfg.stealthBonus or 0) + 0.5) or 0
        each = take + stealthAmt
    end
    -- v3.0 getaway bonuses (per escapee, on the bags' cash): car type + helicopter + Driver
    local gi = r.getawayInfo
    local getawayRows, bonusEach = {}, 0
    -- "+5%" / "+2.5%" (a half bonus in a sneaky escape isn't always a whole number)
    local function pctStr(f)
        local tenths = math.floor(f * 1000 + 0.5)
        return tenths % 10 == 0 and string.format("+%d%%", tenths // 10) or string.format("+%.1f%%", tenths / 10)
    end
    if gi and #escapees > 0 and take > 0 then
        local carPct, heliPct = tonumber(gi.carPct) or 0, tonumber(gi.heliPct) or 0
        if carPct > 0 then
            local amt = math.floor(take * carPct + 0.5)
            local how = gi.route == "highway" and "  (highway x2)" or ""
            if not gi.loud then how = how .. "  (sneaky: half)" end
            table.insert(getawayRows, { label = string.format("%s power %s%s", tostring(gi.carName or "Car"),
                pctStr(carPct), how), amount = amt, icon = "🚗" })
            bonusEach = bonusEach + amt
        end
        if heliPct > 0 then
            local amt = math.floor(take * heliPct + 0.5)
            table.insert(getawayRows, { label = string.format("Helicopter escape %s", pctStr(heliPct)), amount = amt, icon = "🚁" })
            bonusEach = bonusEach + amt
        end
        -- v3.0 polish: Driver role "Getaway pro" → +5% for the whole crew
        local driverPct = tonumber(gi.driverPct) or 0
        if driverPct > 0 then
            local amt = math.floor(take * driverPct + 0.5)
            table.insert(getawayRows, { label = string.format("Getaway pro %s %s", gi.driverName and ("(" .. tostring(gi.driverName) .. ")") or "(Driver)",
                pctStr(driverPct)), amount = amt, icon = "🏎" })
            bonusEach = bonusEach + amt
        end
    end
    -- v3.0 LOOT-CORE: the Boss's target (+$5,000 each), read before clearLoaded resets it
    local targetRow = nil
    if won and #escapees > 0 then
        local TS = optionalService("TargetService")
        if TS and type(TS.bonusFor) == "function" then
            r.bags, r.escapees, r.result = bags, escapees, result
            local okB, v = pcall(TS.bonusFor, TS, r)
            local amt = okB and ((type(v) == "number" and v) or (type(v) == "table" and (tonumber(v.amount) or tonumber(v.bonus)))) or 0
            if amt and amt > 0 then
                local name = "Boss's target"
                if type(TS.targetFor) == "function" then
                    local okT, t = pcall(TS.targetFor, TS, r.jobId)
                    if okT and type(t) == "table" and t.name then name = tostring(t.name) end
                end
                targetRow = { name = name, amount = math.floor(amt + 0.5) }
                bonusEach = bonusEach + targetRow.amount
                if type(TS.awardCrew) == "function" then pcall(TS.awardCrew, TS, escapees) end
            end
        end
    end
    each = each + bonusEach
    local success_pre = #escapees > 0 and take > 0
    local xpEach = Constants.XP.PER_HEIST + Constants.XP.PER_BAG * #bags + (stealth and Constants.XP.STEALTH or 0)
    local escapeeIds = {}
    for _, p in ipairs(escapees) do table.insert(escapeeIds, p.UserId) end
    if success_pre and r.driller and r.driller.Parent and r.crew[r.driller] and r.crew[r.driller].escaped then
        S.economy:addCash(r.driller, Constants.HEIST_PAYOUT_CRACKER_BONUS, "Drilled the vault", { payout = true })
        lifetimeEarned(r.driller, Constants.HEIST_PAYOUT_CRACKER_BONUS)
        notify(r.driller, string.format("+%s drill bonus", UITheme.money(Constants.HEIST_PAYOUT_CRACKER_BONUS)), "gold", 4)
    end
    local carPos = car and car.model and car.model.Parent and car.model:GetPivot().Position
    local feltCash = false
    for _, p in ipairs(escapees) do
        if each > 0 then
            S.economy:addCash(p, each, "Heist payout " .. r.jobId, { payout = true })
            lifetimeEarned(p, each)
            if feel("cash", p, each, carPos) then feltCash = true end
            feel("big", "+" .. UITheme.money(each), { player = p, color = "money", sound = "success" })
        end
        local d = S.data:getData(p)
        if d then
            d.heistsCompleted = (d.heistsCompleted or 0) + 1
            d.bagsSecured = (d.bagsSecured or 0) + #bags
        end
        S.progress:addXP(p, xpEach, "heist")
        if each > 0 then
            notify(p, string.format("You got %s%s", UITheme.money(each), stealthAmt > 0 and "  (+sneaky bonus)" or ""), "green", 6)
            -- v2.0 masks: Bandit "LUCKY" → +10% of the bags' cash, on top, for you
            local MS = optionalService("MaskService")
            if MS and type(MS.has) == "function" and take > 0 then
                local okL, lucky = pcall(MS.has, MS, p, "lucky")
                if okL and lucky then
                    local extra = math.floor(take * ((Constants.MASK_POWERS or {}).LUCKY_BONUS or 0.1) + 0.5)
                    if extra > 0 then
                        S.economy:addCash(p, extra, "LUCKY mask", { payout = true })
                        lifetimeEarned(p, extra)
                        notify(p, string.format("LUCKY mask: +%s extra!", UITheme.money(extra)), "gold", 5)
                    end
                end
            end
        else
            notify(p, "You got away — but the car was empty", "gold", 5)
        end
    end

    local success = #escapees > 0
    if success then
        playOneShot(Constants.SOUNDS.HEIST_WIN, 0.8)
        if not feltCash then playOneShot(Constants.SOUNDS.CASH_CHA_CHING, 0.7) end
    else
        if not feel("sound", "fail") then playOneShot(Constants.SOUNDS.HEIST_FAIL, 0.7) end
    end
    local grade = "F"
    if success then
        if take == 0 then grade = "C"
        elseif stealth and elapsed < 240 then grade = "S"
        elseif stealth then grade = "A"
        else grade = "B" end
    end
    -- v2.0: bot crew lines for the payout screen
    local botCrew, botIndex = {}, {}
    for _, name in ipairs(r.botNames or {}) do
        botIndex[name] = { name = name, bags = 0, value = 0 }
        table.insert(botCrew, botIndex[name])
    end
    for _, b in ipairs(bags) do
        if b.bot then
            local row = botIndex[b.bot]
            if not row then
                row = { name = b.bot, bags = 0, value = 0 }
                botIndex[b.bot] = row
                table.insert(botCrew, row)
            end
            row.bags = row.bags + 1
            row.value = row.value + (b.value or 0)
        end
    end
    broadcastState(success and "COMPLETE" or "FAILED", {
        escaped = #escapees, crewSize = total, take = take, each = each, result = result,
        bags = bags, stealth = stealth, stealthBonus = stealthAmt, grade = grade,
        xp = xpEach, time = math.floor(elapsed), escapees = escapeeIds, jobName = j.cfg.name,
        jobId = j.cfg.id, botCrew = botCrew, jailed = jailedAtEnd,
        -- v3.0
        route = gi and gi.route or nil, bonusEach = bonusEach, target = targetRow,
        getaway = gi and { route = gi.route, routeName = gi.routeName, icon = gi.icon, loud = gi.loud,
            carName = gi.carName, carType = gi.carType, rows = getawayRows } or nil,
    })

    for p in pairs(r.crew) do
        if p.Parent then
            S.shop:removeMask(p)
            S.loot:drop(p)
        end
    end
    S.police:recall()
    S.guards:reset()
    if car then
        car:freeze(true)
        task.delay(3, function()
            if not car then return end
            car:ejectAll()
            for p in pairs(r.crew) do
                if p.Parent and r.crew[p].escaped then sendToSafehouse(p) end
            end
            car:reset(j.refs.getawayCFrame)
            car:setAlarmMode(false)
            car:freeze(false)
            S.loot:attachTrunk(car.trunk)
            if car.model then car.model:SetAttribute("Bags", 0) end
        end)
    end
    S.loot:clearLoaded()
    pcall(syncCarAttrs)
    pushInfo()
    emit("finished", result, j.cfg, j.refs)

    if JobService.onFinished then task.spawn(JobService.onFinished) end
    task.delay(Constants.JOB_RESET_COOLDOWN, function()
        S.security:reset()
        S.loot:reset(legacyShuffle(j.refs))
        closeVault()
        if drillModel then drillModel:Destroy() drillModel = nil end
        setDrillPrompt("Place drill", 0.8, true)
        -- fresh guards at their posts
        S.guards:spawnPatrols(nil, j.refs.guardRoutes)
        broadcastState("IDLE", {})
        resettingUntil = 0
        notifyAll(string.format("%s is ready again — pick your next heist!", j.cfg.name), "gold", 3)
        emit("reset", j.cfg, j.refs)
        pushInfo()
    end)
end

-- ── ready-up / portal → countdown → drop-in (v1.1, v2.0) ──────────────
local function allReady()
    local n, total = readyCounts(true)
    return total > 0 and n == total
end

-- (v1.1) one AFK player can't hold the crew hostage: if at least half are
-- ready, a longer countdown starts; if everyone is, the short one.
local MAJORITY_COUNTDOWN = (Constants.PORTAL and Constants.PORTAL.HALF_COUNTDOWN) or 15
local function enoughReady()
    local n, total = readyCounts(true)
    return total > 0 and n >= math.max(1, math.ceil(total / 2))
end

local function dropPoints(j)
    -- (v1.2.3) Malachi: "I should spawn in the heist, not outside". Each job has a
    -- sneaky side door (sneakIn); the crew lands there in two rows.
    local s = j.refs.sneakIn
    if s then
        local out = Vector3.new(s.at.X - s.face.X, 0, s.at.Z - s.face.Z)
        out = out.Magnitude > 1e-3 and out.Unit or Vector3.new(0, 0, 1)   -- away from the door
        local pts = {}
        for i = 1, 8 do
            local row = (i - 1) % 4
            local col = math.floor((i - 1) / 4)
            table.insert(pts, s.at + s.spread * ((row - 1.5) * 2) + out * (col * 2.5))
        end
        return pts, s.face
    end
    -- fallback: line the crew up on the sidewalk next to the getaway car
    local cf = j.refs.getawayCFrame or CFrame.new(-40, 0, -18)
    local p = cf.Position
    local W = Constants.WORLD
    local walkZ = (p.Z < W.STREET_Z) and (W.STREET_Z - W.STREET_HALF_WIDTH - 2.6) or (W.STREET_Z + W.STREET_HALF_WIDTH + 2.6)
    local pts = {}
    for i = 1, 8 do
        table.insert(pts, Vector3.new(p.X - 6 + i * 3, 3.5, walkZ))
    end
    return pts
end

local function launch(players)
    local j = job()
    if not j or run or launching then return end
    launching = true
    launchAt = 0
    launchToken = nil
    launchSource = nil

    local crewList = {}
    for _, p in ipairs(players or Players:GetPlayers()) do
        if p.Parent then table.insert(crewList, p) end
    end
    if #crewList == 0 then
        launching = false
        pushInfo()
        return
    end

    -- v2.0 auto-role: nobody drops in without a job to do
    local crew = S.crew or optionalService("CrewService")
    if crew and type(crew.autoAssign) == "function" then
        local ok, err = pcall(crew.autoAssign, crew, crewList)
        if not ok then warn("[JobService] autoAssign:", err) end
    end

    -- v2.2 (gear agent): the getaway car becomes the crew's best car type
    -- (VehicleService:chooseForCrew → CosmeticsService:pickCrewCar); locked until the car resets
    if S.vehicles and type(S.vehicles.chooseForCrew) == "function" then
        local okC, carId = pcall(S.vehicles.chooseForCrew, S.vehicles, crewList)
        local real = okC and S.vehicles:getCar()
        if not okC then warn("[JobService] chooseForCrew:", carId)
        elseif real and real.model then
            if real.trunk then S.loot:attachTrunk(real.trunk) end   -- same Trunk part; re-arm to be safe
            local cname, perk = real.model:GetAttribute("CarName"), real.model:GetAttribute("CarPerk")
            if cname and carId ~= "CarClassic" then
                for _, p in ipairs(crewList) do
                    notify(p, string.format("Getaway car: %s%s", tostring(cname),
                        (perk and perk ~= "") and ("  (" .. tostring(perk) .. ")") or ""), "gold", 4)
                end
            end
        end
    end

    local ok, err = pcall(function()
        -- v1.2 cut-scene: a copy of the getaway car rolls up the ramp in The Vault's
        -- garage bay while every client's camera watches, then fade → drop-in.
        local bay = JobService.hub and JobService.hub.bay
        local real = S.vehicles.getCar and S.vehicles:getCar()
        if bay and real and real.model then
            local okc, copy = pcall(function() return real.model:Clone() end)
            if okc and copy then
                for _, d in ipairs(copy:GetDescendants()) do
                    if d:IsA("ProximityPrompt") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then d:Destroy()
                    elseif d:IsA("Seat") or d:IsA("VehicleSeat") then d.Disabled = true
                    elseif d:IsA("BasePart") then d.Anchored = true d.CanCollide = false end
                end
                for _, tag in ipairs(game:GetService("CollectionService"):GetTags(copy)) do
                    game:GetService("CollectionService"):RemoveTag(copy, tag)
                end
                copy.Name = "RolloutCar"
                -- keep the car's pivot height above ground (it's parked at road level y≈0)
                local lift = Vector3.new(0, real.model:GetPivot().Position.Y - ((j.refs.getawayCFrame or CFrame.new()).Position.Y), 0)
                copy:PivotTo(bay.start + lift)
                copy.Parent = Workspace
                for _, p in ipairs(crewList) do
                    launchRemote:FireClient(p, { phase = "rollout", camFrom = bay.camFrom, camTo = bay.camTo })
                end
                local path = { bay.start + lift, bay.rampFoot + lift, bay.rampTop + lift }
                local t0 = os.clock()
                local dur = 2.6
                while os.clock() - t0 < dur do
                    local a = (os.clock() - t0) / dur
                    local cf = (a < 0.35) and path[1]:Lerp(path[2], a / 0.35) or path[2]:Lerp(path[3], (a - 0.35) / 0.65)
                    copy:PivotTo(cf)
                    task.wait()
                end
                task.delay(3, function() copy:Destroy() end)
            end
        end

        for _, p in ipairs(crewList) do
            launchRemote:FireClient(p, { phase = "fade", jobName = j.cfg.name, tagline = j.cfg.tagline })
        end
        task.wait(1.1)
        local pts, faceAt = dropPoints(j)
        for i, p in ipairs(crewList) do
            local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            unseat(p)
            local pos = pts[(i - 1) % #pts + 1]
            if hrp then
                local faceTarget = faceAt or j.refs.entryPoint or (pos + Vector3.new(0, 0, -1))
                hrp.CFrame = CFrame.lookAt(pos, Vector3.new(faceTarget.X, pos.Y, faceTarget.Z))
            end
        end
    end)
    if not ok then warn("[JobService] launch cut-scene:", err) end

    S.guards.graceUntil = os.clock() + (Constants.DETECTION.DROP_IN_GRACE or 0)
    startRun(nil, "launch", crewList)
    launching = false
    for _, p in ipairs(crewList) do
        launchRemote:FireClient(p, { phase = "title", jobName = j.cfg.name, tagline = j.cfg.tagline })
    end
    if run then emit("launched", crewList, j.cfg, j.refs) end
end

local function countdownTo(seconds, source, getPlayers)
    local token = {}
    launchToken = token
    launchAt = now() + seconds
    launchSource = source
    task.delay(seconds, function()
        if launchToken ~= token then return end
        if source == "ready" and not enoughReady() then return end
        local list = nil
        if getPlayers then
            local okp, result = pcall(getPlayers)
            list = (okp and type(result) == "table") and result or nil
            if not list or #list == 0 then
                JobService:cancelLaunch()
                return
            end
        end
        launch(list)
    end)
end

local function checkLaunch()
    if run or launching or os.clock() < resettingUntil then return end
    if launchSource == "portal" then pushInfo() return end   -- PortalService owns this countdown
    if enoughReady() then
        local wait = allReady() and Constants.LAUNCH_COUNTDOWN or MAJORITY_COUNTDOWN
        local target = now() + wait
        -- start a countdown, or shorten a running one when the last person readies
        if launchAt == 0 or target < launchAt - 0.5 then
            countdownTo(wait, "ready", nil)
            notifyAll(allReady() and string.format("Everyone's ready — going in %d!", wait)
                or string.format("Going in %d — get ready to come along!", wait), "gold", 3)
        end
    elseif launchAt ~= 0 then
        launchAt = 0
        launchToken = nil
        launchSource = nil
        notifyAll("Stopped — someone isn't ready", "white", 2)
    end
    pushInfo()
end

function JobService:toggleReady(player, forceReady)
    if run or launching then
        notify(player, "The heist is already going", "white", 2)
        return
    end
    if os.clock() < resettingUntil then
        notify(player, "The job is resetting — give it a few seconds", "white", 2)
        return
    end
    if forceReady then
        if ready[player] then return end
        ready[player] = true
    else
        ready[player] = (not ready[player]) or nil
    end
    local n, total = readyCounts()
    if ready[player] then
        notifyAll(string.format("%s is ready  (%d/%d)", player.DisplayName, n, total), "gold", 2)
    else
        notifyAll(string.format("%s isn't ready  (%d/%d)", player.DisplayName, n, total), "white", 2)
    end
    checkLaunch()
end

-- v2.0 public countdown API (PortalService)
function JobService:startLaunchCountdown(seconds, getPlayers, source)
    if run or launching or os.clock() < resettingUntil or not job() then return false end
    seconds = math.max(0, tonumber(seconds) or Constants.LAUNCH_COUNTDOWN)
    countdownTo(seconds, source or "portal", getPlayers)
    pushInfo()
    return true
end

function JobService:cancelLaunch(reason)
    if launchAt == 0 and not launchToken then return end
    launchAt = 0
    launchToken = nil
    launchSource = nil
    if reason then notifyAll(reason, "white", 2) end
    pushInfo()
end

function JobService:getLaunch()
    return launchAt, launchSource
end

function JobService:setPortalReady(set)
    set = type(set) == "table" and set or {}
    local changed = false
    for p in pairs(set) do if not portalReady[p] then changed = true break end end
    if not changed then
        for p in pairs(portalReady) do if not set[p] then changed = true break end end
    end
    portalReady = set
    if changed then pushInfo() end
end

function JobService:getPhase()
    if run then return "running" end
    if launching then return "launching" end
    if os.clock() < resettingUntil then return "resetting" end
    return "idle"
end

function JobService:getCurrentId()
    return currentId
end

function JobService:getCar()
    return car
end

function JobService:isInRun(player)
    local e = run and player and run.crew[player]
    return e ~= nil and not e.out and not e.escaped and not e.jailed
end

-- JailService: may this player break someone out right now?
function JobService:canBreakOut(player)
    if not run or not player or not player.Parent or player:GetAttribute("Jailed") then return false end
    local e = run.crew[player]
    if not e then
        addToCrew(player)   -- a friend who came to help joins the crew
        return true
    end
    return not e.out and not e.escaped and not e.jailed
end

function JobService:subscribe(event, fn)
    if type(fn) ~= "function" then return end
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function JobService:useJail(jailService)
    S.jail = jailService
end

function JobService:noteBots(names)
    if run and type(names) == "table" then
        run.botNames = table.clone(names)
        pushInfo()
    end
end

-- ── selecting / arming a job ─────────────────────────────────────────
local function unlocked(cfg)
    if (cfg.unlockLevel or 1) <= 1 then return true end
    for _, p in ipairs(Players:GetPlayers()) do
        if S.progress:getLevel(p) >= cfg.unlockLevel then return true end
    end
    return false
end

function JobService:isUnlocked(id)
    local j = jobs[id]
    return j ~= nil and unlocked(j.cfg)
end

function JobService:selectJob(id)
    if run or launching then return false end
    local target = jobs[id]
    if not target then return false end
    if launchAt ~= 0 then self:cancelLaunch() end
    local old = job()
    if old then
        S.security:disarm()
        S.loot:disarm()
        S.guards:despawnAll()
        S.police:recall()
        closeVault()
    end
    currentId = id
    ReplicatedStorage:SetAttribute("ActiveJob", id)
    for jid, jj in pairs(jobs) do
        if jj.refs.openSign then pcall(jj.refs.openSign, jid == id) end
    end

    local refs = target.refs
    vaultClosed = {}
    for _, part in ipairs(vaultParts(refs)) do vaultClosed[part] = part.CFrame end
    if drillPrompt then drillPrompt:Destroy() drillPrompt = nil end
    if refs.vault and refs.vault.door then
        local p = Instance.new("ProximityPrompt")
        p.Name = "Drill"
        p.ActionText = "Place drill"
        p.ObjectText = nounOf(target)
        p.HoldDuration = 0.8
        p.MaxActivationDistance = 7
        p.RequiresLineOfSight = true   -- (fix v1.1) no drilling through walls
        -- (v2.0 fix) the dial / hub / spokes sit right in front of the lock plate's
        -- centre, so a prompt ON the plate failed its own line-of-sight check and
        -- never showed. Hang it just in front of the door face (same side the
        -- drill model goes — the door's LookVector).
        local att = refs.vault.door:FindFirstChild("DrillPoint") or Instance.new("Attachment")
        att.Name = "DrillPoint"
        -- (v2.1) a builder can move it (vault.drillOffset, door space): the mart safe
        -- sits in a tight office behind a desk, so its prompt hangs at head height
        att.Position = typeof(refs.vault.drillOffset) == "Vector3" and refs.vault.drillOffset or Vector3.new(0, 0, -1.5)
        att.Parent = refs.vault.door
        p.Parent = att
        p.Triggered:Connect(function(player) startDrill(player) end)
        drillPrompt = p
    end

    S.security:arm(refs)
    S.loot:arm(refs, legacyShuffle(refs))
    S.guards:spawnPatrols(nil, refs.guardRoutes or {})
    car = S.vehicles:spawnGetaway(refs.getawayCFrame)
    if car then S.loot:attachTrunk(car.trunk) end
    if self.onJobChanged then pcall(self.onJobChanged, target.cfg, refs) end
    emit("jobChanged", target.cfg, refs)
    pushInfo()
    print("[JobService] Armed job:", id)
    return true
end

function JobService:cycleJob(player)
    if run or launching or os.clock() < resettingUntil then
        notify(player, "Finish (or lose) the heist you're on first", "white", 2)
        return
    end
    local ids = {}
    for _, cfg in ipairs(Constants.JOBS) do if jobs[cfg.id] then table.insert(ids, cfg.id) end end
    local idx = table.find(ids, currentId) or 0
    for step = 1, #ids do
        local cand = ids[(idx + step - 1) % #ids + 1]
        local cfg = jobs[cand].cfg
        if cand ~= currentId then
            if unlocked(cfg) then
                self:selectJob(cand)
                notifyAll(string.format("Next heist: %s — %s", cfg.name, cfg.tagline), "gold", 4)
                return
            else
                notify(player, string.format("%s unlocks at level %d", cfg.name, cfg.unlockLevel), "white", 3)
            end
        end
    end
end

-- ── init ─────────────────────────────────────────────────────────────
function JobService:init(deps)
    S.security, S.loot, S.guards = deps.security, deps.loot, deps.guards
    S.vehicles, S.police = deps.vehicles, deps.police
    S.economy, S.progress, S.shop, S.data = deps.economy, deps.progress, deps.shop, deps.data
    S.crew, S.feel, S.hide = deps.crew, deps.feel, deps.hide
    if deps.jail then S.jail = deps.jail end

    for _, cfg in ipairs(Constants.JOBS) do
        local refs = deps.jobs and deps.jobs[cfg.id]
        if refs then jobs[cfg.id] = { cfg = cfg, refs = refs } end
    end

    S.security:init({
        onEvent = function(kind, player, data)
            if os.clock() < resettingUntil then return end
            data = data or {}
            if kind == "needKeycard" then
                notify(player, "It's locked! Find the keycard first (or bring a Hacker)", "white", 3)
                return
            end
            startRun(player, kind)
            addToCrew(player)
            if not run then return end
            if kind == "keycard" then
                run.keycardFound = true
                feel("sound", "pickup", data.pos, player)
                notifyAll(player.DisplayName .. " found the keycard!", "gold", 3)
            elseif kind == "cameras" then
                if not feel("big", "CAMERAS OFF", { color = "info" }) then
                    feel("sound", "tick", data.pos)
                end
                notifyAll(player.DisplayName .. " turned off the cameras!", "gold", 3)
            elseif kind == "door" then
                feel("sound", "door", data.pos)
                notifyAll("The door is open!" .. (has(job().refs, "laserRows") and " Watch out for the lasers." or ""), "gold", 3)
            end
            pushInfo()
        end,
        onAlarm = function(reason, player) triggerAlarm(reason, player) end,
    }, S.shop)

    S.loot:init({
        onEvent = function(kind, player, data)
            data = data or {}
            if kind == "full" then
                notify(player, "Your hands are full! Put your bag in the car, give it to a bot, or throw it (G)", "white", 2)
                return
            elseif kind == "emptyHanded" then
                notify(player, "Bring a bag to put in the car", "white", 2)
                return
            end
            if os.clock() < resettingUntil then return end
            startRun(player, kind)
            addToCrew(player)
            if not run then return end
            if kind == "take" or kind == "smash" then
                feel("loot", player, data.kind, data.pos)
            end
            if kind == "smash" then
                local cfg = job().cfg
                if cfg.silentAlarmDelay and not run.silent and not run.alarm then
                    run.silent = true
                    notifyAll("Uh oh… a secret alarm went off somewhere!", "gold", 3)
                    local thisRun = run
                    task.delay(cfg.silentAlarmDelay, function()
                        if run == thisRun and not run.alarm then triggerAlarm("silent", nil) end
                    end)
                end
            elseif kind == "load" then
                local value = data.value or (S.loot.info and S.loot.info(data.kind).value) or 0
                feel("load", value, data.pos)
                -- v2.2 bag tiers: say where the extra came from ("Duffel Bag +$150")
                local extra = ""
                if (tonumber(data.bonus) or 0) > 0 then
                    extra = string.format("  (%s +%s)", tostring(data.tierName or "bag"), UITheme.money(data.bonus))
                end
                if data.bot then
                    notifyAll(string.format("%s (bot) put %s in the car  +%s%s", data.bot, tostring(data.name or data.kind), UITheme.money(value), extra), "green", 3)
                elseif player then
                    notifyAll(string.format("%s put %s in the car  +%s%s", player.DisplayName, tostring(data.name or data.kind), UITheme.money(value), extra), "green", 3)
                end
            end
            pushInfo()
        end,
    }, S.shop)

    S.guards:spawnPatrols({
        onPlayerSpotted = function(player, guard) kickBack(player, guard) end,
        onPlayerCaught = function(player, guard)
            -- during the loud escape a guard grab still counts as caught (→ jail)
            if run and run.alarm then catchPlayer(player, "guard") else kickBack(player, guard, true) end
        end,
        onTakedown = function(player)
            startRun(player, "takedown")
            addToCrew(player)
            notifyAll(player.DisplayName .. " knocked out a guard!", "gold", 3)
        end,
        onTakedownFailed = function(player)
            notify(player, "He saw you coming! Sneak up from behind next time.", "red", 2)
            kickBack(player)
        end,
    }, {})

    S.vehicles:init({
        onDropoff = function(theCar, occupants)
            if not run then
                for _, p in ipairs(occupants) do notify(p, "Nice drive! Bring some loot next time.", "white", 3) end
                return
            end
            local any = false
            for _, p in ipairs(occupants) do
                addToCrew(p)
                local e = run.crew[p]
                if e and not e.out and not e.jailed then
                    e.escaped = true
                    any = true
                end
            end
            if any then finish("dropoff") end
        end,
        onDriverChanged = function() end,   -- (v3.0: nobody drives; no chase)
        onOccupantsChanged = function()
            task.defer(function()
                pcall(syncCarAttrs)
                pcall(checkGetaway)
            end)
        end,
    })

    S.police:init({
        onPlayerCaught = function(player) catchPlayer(player, "cop") end,
        onCarBusted = function(theCar)
            if not run then return end
            notifyAll("BUSTED — the police blocked the car!", "red", 5)
            theCar:freeze(true)
            for _, p in ipairs(theCar:getOccupants()) do
                local e = run.crew[p]
                if e then e.out = true end
            end
            theCar:ejectAll()
            S.loot:clearLoaded()
            finish("busted")
        end,
    })

    -- v3.0 the movie getaway (vote + cut-scene); GO! presses come back through onGo
    S.getaway = deps.getaway or optionalService("GetawayService")
    if S.getaway and type(S.getaway.init) == "function" then
        local okG, errG = pcall(S.getaway.init, S.getaway, { onGo = onGo, notify = notify })
        if not okG then warn("[JobService] GetawayService:init:", errG) end
    end

    Remotes.getRemote(Remotes.NAMES.ReadyUp, "RemoteEvent").OnServerEvent:Connect(function(player, force)
        JobService:toggleReady(player, force == true)
    end)

    Players.PlayerAdded:Connect(function(p)
        if launchAt ~= 0 then checkLaunch() end   -- a new player isn't ready yet
        task.delay(2, function()
            if p.Parent then
                local ok, info = pcall(buildInfo)
                if ok then infoRemote:FireClient(p, info) end
                if run and run.alarm then alarmRemote:FireClient(p, true) end   -- (fix v1.1)
            end
        end)
    end)
    Players.PlayerRemoving:Connect(function(p)
        ready[p] = nil
        portalReady[p] = nil
        kickedAt[p] = nil
        task.defer(checkLaunch)
        if run and run.crew[p] then
            run.crew[p] = nil
            if next(run.crew) == nil or #activeCrew() == 0 then
                finish("abandoned")
            end
        end
    end)

    -- arm the first job that actually built (easy → hard order in Constants.JOBS)
    for _, cfg in ipairs(Constants.JOBS) do
        if jobs[cfg.id] then
            self:selectJob(cfg.id)
            break
        end
    end
    print("[JobService] Ready")
end

function JobService:getCurrent()
    local j = job()
    return j and j.cfg, j and j.refs
end

return JobService
