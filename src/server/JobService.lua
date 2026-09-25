--[[
    HEIST CREW — JobService  (replaces HeistService, v1.0)
    ────────────────────────────────────────────────
    Runs a heist from first move to payout, for whichever job is SELECTED
    (Villa Rosa / Diamond Dolls — Constants.JOBS, geometry from the builders).

    THE FLOW
      IDLE ─(any heist action: keycard, cameras, loot, drill, getting seen)─► ACTIVE
        • everyone in the server is the crew; masks go on
        • quiet run: no timer (a HEIST_RUN_LIMIT backstop only)
        • ALARM (camera / laser / guard / silent alarm): alarm sound, guards
          hunt, police roll in, and the crew has job.alarmTimer seconds
        • DRILL the vault: place it, it runs on its own, it JAMS (fix it),
          vault door swings open → loot unlocks
        • carry bags to the getaway car → "Load bag"
        • DRIVE the car to the marina drop-off → run ends, loaded bags pay out
      Everyone in the car at the drop-off gets the FULL take (+ stealth bonus if
      the alarm never tripped). Caught = out, no payout. Car busted = all out.
      Then a short cooldown, and the job resets.

    Services are passed in via init() so this file only orchestrates.
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
local car = nil
local drillPrompt = nil
local vaultClosed = nil      -- { [part] = CFrame }
local drillModel = nil

local DRILL_TIME = 24
local JAM_POINTS = { 0.33, 0.7 }
local JAM_CHANCE = 0.7

local stateRemote    = Remotes.getRemote(Remotes.NAMES.HeistState, "RemoteEvent")
local progressRemote = Remotes.getRemote(Remotes.NAMES.VaultProgress, "RemoteEvent")
local alarmRemote    = Remotes.getRemote(Remotes.NAMES.AlarmTriggered, "RemoteEvent")
local notifyRemote   = Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent")
local infoRemote     = Remotes.getRemote(Remotes.NAMES.JobInfo, "RemoteEvent")
local launchRemote   = Remotes.getRemote(Remotes.NAMES.LaunchJob, "RemoteEvent")

-- v1.1 ready-up → countdown → drop-in
local ready = {}          -- [player] = true
local launchAt = 0        -- server time the drop-in happens (0 = no countdown)
local launchToken = nil

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

local function rootPos(player)
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position
end

local function activeCrew()
    local list = {}
    if not run then return list end
    for p, e in pairs(run.crew) do
        if p.Parent and not e.out and not e.escaped then table.insert(list, p) end
    end
    return list
end

local function addToCrew(player)
    if run and player and not run.crew[player] then
        run.crew[player] = { out = false, escaped = false }
        if S.shop then S.shop:wearMask(player) end
    end
end

-- ── JobInfo (drives the JOB card + objective pill) ───────────────────
local function drillLabel(noun)
    local d = run and run.drill
    if run and run.vaultOpen then return noun .. " open" end
    if not d then return "Drill the " .. string.lower(noun) end
    if d.jammed then return "Drill jammed — fix it!" end
    return string.format("Drilling… %d%%", math.floor(d.progress * 100))
end

-- v1.1: waypoints — where the NEXT thing to do is (the client draws markers)
local function buildTargets(j, c)
    local t = {}
    local function add(pos, label, kind) if pos then table.insert(t, { pos = pos, label = label, kind = kind }) end end
    local refs = j.refs
    if not run then
        local b = Constants.WORLD.BOSS_NPC_POS
        local tb = Constants.WORLD.HUB_TABLE
        add(Vector3.new(b.x, b.y + 6.5, b.z), "BRIEFING", "boss")
        add(Vector3.new(tb.x, tb.y + 5, tb.z), "READY UP", "ready")
        return t
    end
    local carPos = car and car.model and car.model.Parent and car.model:GetPivot().Position
    local d = Constants.WORLD.DROPOFF
    local marina = Vector3.new(d.x, 3, d.z)
    if run.alarm then
        add(carPos and carPos + Vector3.new(0, 4, 0), "CAR", "car")
        add(marina, "MARINA", "marina")
        return t
    end
    if refs.breaker and not S.security:camerasCut() then add(refs.breaker.Position, "BREAKER", "optional") end
    local rem = S.loot:remaining()
    if j.cfg.id == "jewelry" then
        local n = 0
        for _, r in ipairs(rem) do
            if r.isCase and n < 3 then add(r.pos, "SMASH", "loot") n = n + 1 end
        end
    end
    if not S.security:doorsOpen() then
        local held = false
        for _, p in ipairs(Players:GetPlayers()) do if p:GetAttribute("HasKeycard") then held = true end end
        local door = refs.keycardDoors and refs.keycardDoors[1]
        if held and door then
            add(door.panel.Position, "KEYPAD", "door")
        else
            for _, spot in ipairs(refs.keycardSpots or {}) do add(spot.Position + Vector3.new(0, 1.5, 0), "SEARCH", "search") end
        end
    elseif not run.vaultOpen and refs.vault then
        local label = "DRILL"
        if run.drill then label = run.drill.jammed and "FIX DRILL" or "DRILLING" end
        add(refs.vault.door.Position, label, "vault")
    else
        local n = 0
        for _, r in ipairs(rem) do
            if not r.isCase and not r.locked and n < 2 then add(r.pos, "LOOT", "loot") n = n + 1 end
        end
    end
    add(carPos and carPos + Vector3.new(0, 4, 0), "CAR", "car")
    if c.loaded > 0 then add(marina, "MARINA", "marina") end
    return t
end

local function readyCounts()
    local n, total, names = 0, 0, {}
    for _, p in ipairs(Players:GetPlayers()) do
        total = total + 1
        if ready[p] then
            n = n + 1
            table.insert(names, p.DisplayName)
        end
    end
    return n, total, names
end

local function buildInfo()
    local j = job()
    if not j then return { stage = "IDLE", steps = {} } end
    local c = S.loot:counts()
    local steps = {}
    local function add(id, label, done, optional) table.insert(steps, { id = id, label = label, done = done, optional = optional }) end

    add("cameras", S.security:camerasCut() and "Cameras cut" or "Cut the cameras", S.security:camerasCut(), true)
    if j.cfg.id == "jewelry" then
        add("cases", string.format("Smash the cases  %d/%d", c.casesTaken, c.cases), c.cases > 0 and c.casesTaken >= c.cases)
    end
    local doorsOpen = S.security:doorsOpen()
    -- (fix v1.1) ticked only while someone actually HOLDS the card (or the door is open);
    -- if the holder gets caught the card respawns and the step comes back
    local held = false
    for _, p in ipairs(Players:GetPlayers()) do if p:GetAttribute("HasKeycard") then held = true end end
    add("keycard", "Find the keycard", doorsOpen or held, false)
    add("door", j.cfg.id == "jewelry" and "Open the back room door" or "Open the locked vault door", doorsOpen)
    local noun = j.cfg.id == "jewelry" and "Safe" or "Vault"
    add("vault", drillLabel(noun), run ~= nil and run.vaultOpen == true)
    local vaultBags = c.total - c.cases
    local vaultTaken = c.taken - c.casesTaken
    add("loot", string.format("Bag the %s  %d/%d", string.lower(noun), vaultTaken, vaultBags), vaultBags > 0 and vaultTaken >= vaultBags)
    add("car", string.format("Load the car (%d)  ·  drive to the marina", c.loaded), false)

    return {
        jobId = j.cfg.id, jobName = j.cfg.name, stage = run and "ACTIVE" or "IDLE",
        steps = steps, take = c.take, bagsSecured = c.loaded, bagsTotal = c.total,
        alarm = run ~= nil and run.alarm == true, alarmEndsAt = run and run.alarmEndsAt or 0,
        silentAlarm = run ~= nil and run.silent == true and not run.alarm,
        targets = buildTargets(j, c),
        startedAt = run and run.startedAtServer or 0,
        readyCount = (select(1, readyCounts())), playerCount = (select(2, readyCounts())),
        readyNames = (select(3, readyCounts())), launchAt = launchAt,
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
    playOneShot(Constants.SOUNDS.VAULT_CRACK, 0.9)
    progressRemote:FireAllClients(1)
    task.delay(1.2, function() progressRemote:FireAllClients(0) end)
    -- (fix v1.1) the drill bonus is paid at a SUCCESSFUL finish, not here — it was
    -- farmable by drilling and bailing
    run.driller = player
    notifyAll("It's open — bag the loot and get it to the car", "green", 4)
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
        notify(player, "Get through the keycard door first", "white", 2)
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

    local rate = 1 / DRILL_TIME
    if S.shop:hasGear(player, "Lockpick") then rate = rate * 1.3 end
    d = { progress = 0, jammed = false, owner = player, jams = {} }
    for _, point in ipairs(JAM_POINTS) do
        if math.random() < JAM_CHANCE then table.insert(d.jams, point) end
    end
    run.drill = d
    makeDrill(j.refs.vault.door)
    setDrillPrompt("Fix drill", 1.5, false)
    notifyAll(player.DisplayName .. " set up the drill — hold the room", "gold", 3)
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
                    notifyAll("The drill jammed — someone fix it!", "red", 3)
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

startRun = function(player, why)
    if run then return run end
    if os.clock() < resettingUntil then
        if player then notify(player, "The job is resetting — give it a few seconds", "white", 2) end
        return nil
    end
    local j = job()
    if not j then return nil end
    run = {
        jobId = j.cfg.id, startedAt = os.clock(), startedAtServer = now(), crew = {}, alarm = false, alarmEndsAt = 0,
        silent = false, vaultOpen = false, keycardFound = false, drill = nil,
    }
    for _, p in ipairs(Players:GetPlayers()) do addToCrew(p) end
    ready = {}
    launchAt = 0
    launchToken = nil
    if why ~= "launch" then
        notifyAll(string.format("The %s job is ON — masks up", j.cfg.name), "gold", 4)
    end
    broadcastState("ACTIVE", { jobId = j.cfg.id })
    local thisRun = run
    task.spawn(function()
        while run == thisRun do
            pushInfo()
            task.wait(1)
        end
    end)
    task.delay(Constants.HEIST_RUN_LIMIT, function()
        if run == thisRun then
            notifyAll("Took too long — the Boss called it off", "red", 4)
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
    if not run or run.alarm then return end
    addToCrew(player)
    run.alarm = true
    run.alarmEndsAt = now() + j.cfg.alarmTimer
    local who = player and player.DisplayName or "Someone"
    local msg = ({
        camera = who .. " got caught on camera — ALARM!",
        laser  = who .. " tripped a laser — ALARM!",
        guard  = "A guard spotted " .. who .. " — ALARM!",
        silent = "Silent alarm — the cops are here!",
    })[reason] or "ALARM!"
    notifyAll(msg, "red", 5)
    alarmLoop(true)
    alarmRemote:FireAllClients(true)
    S.guards:setAlarmActive(true, player and rootPos(player))
    S.police:dispatch(j.refs.policeStop, activeCrew)
    if car then
        car:setAlarmMode(true)
        if #car:getOccupants() > 0 then S.police:chaseCar(car) end
    end
    broadcastState("ESCAPING", { escapeSeconds = j.cfg.alarmTimer })
    local thisRun = run
    task.delay(j.cfg.alarmTimer, function()
        if run == thisRun then
            notifyAll("Out of time — the cops locked the block down", "red", 4)
            finish("time")
        end
    end)
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
    addToCrew(player)
    local e = run.crew[player]
    if e.out or e.escaped then return end
    e.out = true
    S.loot:drop(player)
    S.security:dropKeycard(player)
    S.shop:removeMask(player)
    notifyAll(string.format("%s got taken down%s", player.DisplayName, by == "cop" and " by the cops" or ""), "red", 3)
    notify(player, "Caught — no payout this run. Back to the safehouse.", "red", 4)
    sendToSafehouse(player)
    if #activeCrew() == 0 then finish("caught") end
    pushInfo()
end

finish = function(result)
    if not run then return end
    local r = run
    local j = job()
    run = nil
    -- (fix v1.1) block new runs until the reset has ACTUALLY happened (it used to be
    -- skippable if someone tripped a sensor on the exact frame the cooldown ended)
    resettingUntil = math.huge

    alarmLoop(false)
    alarmRemote:FireAllClients(false)
    progressRemote:FireAllClients(0)

    local c = S.loot:counts()
    local bags = (result == "dropoff") and S.loot:getLoaded() or {}
    local elapsed = os.clock() - r.startedAt
    local escapees = {}
    for p, e in pairs(r.crew) do
        if e.escaped and p.Parent then table.insert(escapees, p) end
    end
    local total = 0
    for p in pairs(r.crew) do if p.Parent then total = total + 1 end end

    local take = (result == "dropoff") and c.take or 0
    local stealth = not r.alarm
    local each = 0
    if #escapees > 0 and take > 0 then
        each = math.floor(take * (1 + (stealth and j.cfg.stealthBonus or 0)) + 0.5)
    end
    local success_pre = #escapees > 0 and take > 0
    local xpEach = Constants.XP.PER_HEIST + Constants.XP.PER_BAG * #bags + (stealth and Constants.XP.STEALTH or 0)
    local escapeeIds = {}
    for _, p in ipairs(escapees) do table.insert(escapeeIds, p.UserId) end
    if success_pre and r.driller and r.driller.Parent and r.crew[r.driller] and r.crew[r.driller].escaped then
        S.economy:addCash(r.driller, Constants.HEIST_PAYOUT_CRACKER_BONUS, "Drilled the vault", { payout = true })
        notify(r.driller, string.format("+%s drill bonus", UITheme.money(Constants.HEIST_PAYOUT_CRACKER_BONUS)), "gold", 4)
    end
    for _, p in ipairs(escapees) do
        if each > 0 then
            S.economy:addCash(p, each, "Heist payout " .. r.jobId, { payout = true })
        end
        local d = S.data:getData(p)
        if d then
            d.heistsCompleted = (d.heistsCompleted or 0) + 1
            d.bagsSecured = (d.bagsSecured or 0) + #bags
        end
        S.progress:addXP(p, xpEach, "heist")
        if each > 0 then
            notify(p, string.format("You got %s%s", UITheme.money(each), stealth and "  (+stealth bonus)" or ""), "green", 6)
        else
            notify(p, "Clean escape — but the car was empty", "gold", 5)
        end
    end

    local success = #escapees > 0
    if success then
        playOneShot(Constants.SOUNDS.HEIST_WIN, 0.8)
        playOneShot(Constants.SOUNDS.CASH_CHA_CHING, 0.7)
    else
        playOneShot(Constants.SOUNDS.HEIST_FAIL, 0.7)
    end
    local grade = "F"
    if success then
        if take == 0 then grade = "C"
        elseif stealth and elapsed < 240 then grade = "S"
        elseif stealth then grade = "A"
        else grade = "B" end
    end
    broadcastState(success and "COMPLETE" or "FAILED", {
        escaped = #escapees, crewSize = total, take = take, each = each, result = result,
        bags = bags, stealth = stealth, stealthBonus = math.max(0, each - take), grade = grade,
        xp = xpEach, time = math.floor(elapsed), escapees = escapeeIds, jobName = j.cfg.name,
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
    pushInfo()

    if JobService.onFinished then task.spawn(JobService.onFinished) end
    task.delay(Constants.JOB_RESET_COOLDOWN, function()
        S.security:reset()
        S.loot:reset()
        closeVault()
        if drillModel then drillModel:Destroy() drillModel = nil end
        setDrillPrompt("Place drill", 0.8, true)
        -- fresh guards at their posts
        S.guards:spawnPatrols(nil, j.refs.guardRoutes)
        broadcastState("IDLE", {})
        resettingUntil = 0
        notifyAll(string.format("%s has reset — ready for the next job", j.cfg.name), "gold", 3)
        pushInfo()
    end)
end

-- ── ready-up → countdown → drop-in (v1.1) ─────────────────────────────
local function allReady()
    local n, total = readyCounts()
    return total > 0 and n == total
end

-- (v1.1) one AFK player can't hold the crew hostage: if at least half are
-- ready, a longer countdown starts; if everyone is, the short one.
local MAJORITY_COUNTDOWN = 15
local function enoughReady()
    local n, total = readyCounts()
    return total > 0 and n >= math.max(1, math.ceil(total / 2))
end

local function dropPoints(j)
    -- line the crew up on the sidewalk next to the getaway car
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

local function launch()
    local j = job()
    if not j or run then return end
    launchAt = 0
    launchToken = nil

    -- v1.2 cut-scene: a copy of the getaway car rolls up the ramp in The Vault's
    -- garage bay while every client's camera watches, then fade → drop-in.
    local bay = JobService.hub and JobService.hub.bay
    local real = S.vehicles.getCar and S.vehicles:getCar()
    if bay and real and real.model then
        local ok, copy = pcall(function() return real.model:Clone() end)
        if ok and copy then
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
            local lift = Vector3.new(0, real.model:GetPivot().Position.Y - ((job().refs.getawayCFrame or CFrame.new()).Position.Y), 0)
            copy:PivotTo(bay.start + lift)
            copy.Parent = Workspace
            launchRemote:FireAllClients({ phase = "rollout", camFrom = bay.camFrom, camTo = bay.camTo })
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

    launchRemote:FireAllClients({ phase = "fade", jobName = j.cfg.name, tagline = j.cfg.tagline })
    task.wait(1.1)
    local pts = dropPoints(j)
    for i, p in ipairs(Players:GetPlayers()) do
        local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        unseat(p)
        local pos = pts[(i - 1) % #pts + 1]
        if hrp then
            local faceTarget = j.refs.entryPoint or (pos + Vector3.new(0, 0, -1))
            hrp.CFrame = CFrame.lookAt(pos, Vector3.new(faceTarget.X, pos.Y, faceTarget.Z))
        end
    end
    startRun(nil, "launch")
    launchRemote:FireAllClients({ phase = "title", jobName = j.cfg.name, tagline = j.cfg.tagline })
end

local function checkLaunch()
    if run or os.clock() < resettingUntil then return end
    if enoughReady() then
        local wait = allReady() and Constants.LAUNCH_COUNTDOWN or MAJORITY_COUNTDOWN
        local target = now() + wait
        -- start a countdown, or shorten a running one when the last person readies
        if launchAt == 0 or target < launchAt - 0.5 then
            launchAt = target
            local token = {}
            launchToken = token
            notifyAll(allReady() and string.format("Everyone's ready — rolling out in %d", wait)
                or string.format("Rolling out in %d — ready up to come along", wait), "gold", 3)
            task.delay(wait, function()
                if launchToken == token and enoughReady() then launch() end
            end)
        end
    elseif launchAt ~= 0 then
        launchAt = 0
        launchToken = nil
        notifyAll("Launch cancelled — someone isn't ready", "white", 2)
    end
    pushInfo()
end

function JobService:toggleReady(player, forceReady)
    if run then
        notify(player, "The job's already running", "white", 2)
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

-- ── selecting / arming a job ─────────────────────────────────────────
local function unlocked(cfg)
    for _, p in ipairs(Players:GetPlayers()) do
        if S.progress:getLevel(p) >= cfg.unlockLevel then return true end
    end
    return cfg.unlockLevel <= 1
end

function JobService:selectJob(id)
    if run then return false end
    local target = jobs[id]
    if not target then return false end
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
        p.ObjectText = target.cfg.id == "jewelry" and "Safe" or "Vault"
        p.HoldDuration = 0.8
        p.MaxActivationDistance = 7
        p.RequiresLineOfSight = true   -- (fix v1.1) no drilling through walls
        p.Parent = refs.vault.door
        p.Triggered:Connect(function(player) startDrill(player) end)
        drillPrompt = p
    end

    S.security:arm(refs)
    S.loot:arm(refs)
    S.guards:spawnPatrols(nil, refs.guardRoutes)
    car = S.vehicles:spawnGetaway(refs.getawayCFrame)
    if car then S.loot:attachTrunk(car.trunk) end
    if self.onJobChanged then pcall(self.onJobChanged, target.cfg, refs) end
    pushInfo()
    print("[JobService] Armed job:", id)
    return true
end

function JobService:cycleJob(player)
    if run or os.clock() < resettingUntil then
        notify(player, "Finish (or lose) the current job first", "white", 2)
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
                notifyAll(string.format("Next job: %s — %s", cfg.name, cfg.tagline), "gold", 4)
                return
            else
                notify(player, string.format("%s unlocks at level %d", cfg.name, cfg.unlockLevel), "white", 3)
            end
        end
    end
end

-- ── init ─────────────────────────────────────────────────────────────
-- deps = { jobs = { villa = refs, jewelry = refs }, security, loot, guards, vehicles,
--          police, economy, progress, shop, data }
function JobService:init(deps)
    S.security, S.loot, S.guards = deps.security, deps.loot, deps.guards
    S.vehicles, S.police = deps.vehicles, deps.police
    S.economy, S.progress, S.shop, S.data = deps.economy, deps.progress, deps.shop, deps.data

    for _, cfg in ipairs(Constants.JOBS) do
        local refs = deps.jobs[cfg.id]
        if refs then jobs[cfg.id] = { cfg = cfg, refs = refs } end
    end

    S.security:init({
        onEvent = function(kind, player)
            if os.clock() < resettingUntil then return end
            if kind == "needKeycard" then
                notify(player, "Locked — find the keycard, or bring a Hacker", "white", 3)
                return
            end
            startRun(player, kind)
            addToCrew(player)
            if not run then return end
            if kind == "keycard" then
                run.keycardFound = true
                notifyAll(player.DisplayName .. " found the keycard", "gold", 3)
            elseif kind == "cameras" then
                notifyAll(player.DisplayName .. " cut the cameras", "gold", 3)
            elseif kind == "door" then
                notifyAll("The door's open — watch the lasers", "gold", 3)
            end
            pushInfo()
        end,
        onAlarm = function(reason, player) triggerAlarm(reason, player) end,
    }, S.shop)

    S.loot:init({
        onEvent = function(kind, player, data)
            if kind == "full" then
                notify(player, "Hands full — load your bag or throw it (G)", "white", 2)
                return
            elseif kind == "emptyHanded" then
                notify(player, "Bring a bag to load it", "white", 2)
                return
            end
            if os.clock() < resettingUntil then return end
            startRun(player, kind)
            addToCrew(player)
            if not run then return end
            if kind == "smash" then
                local cfg = job().cfg
                if cfg.silentAlarmDelay and not run.silent and not run.alarm then
                    run.silent = true
                    notifyAll("A silent alarm went off somewhere…", "gold", 3)
                    local thisRun = run
                    task.delay(cfg.silentAlarmDelay, function()
                        if run == thisRun and not run.alarm then triggerAlarm("silent", nil) end
                    end)
                end
            elseif kind == "load" then
                local info = Constants.LOOT[data.kind] or {}
                notifyAll(string.format("%s loaded %s  +%s", player.DisplayName, data.kind, UITheme.money(info.value or 0)), "green", 3)
            end
            pushInfo()
        end,
    }, S.shop)

    S.guards:spawnPatrols({
        onPlayerSpotted = function(player) triggerAlarm("guard", player) end,
        onPlayerCaught = function(player) catchPlayer(player, "guard") end,
        onTakedown = function(player)
            startRun(player, "takedown")
            addToCrew(player)
            notifyAll(player.DisplayName .. " knocked out a guard", "gold", 3)
        end,
        onTakedownFailed = function(player)
            notify(player, "He saw you coming — get behind him", "red", 2)
            triggerAlarm("guard", player)
        end,
    }, {})

    S.vehicles:init({
        onDropoff = function(theCar, occupants)
            if not run then
                for _, p in ipairs(occupants) do notify(p, "Nice drive. Bring some loot next time.", "white", 3) end
                return
            end
            local any = false
            for _, p in ipairs(occupants) do
                addToCrew(p)
                local e = run.crew[p]
                if e and not e.out then
                    e.escaped = true
                    any = true
                end
            end
            if any then finish("dropoff") end
        end,
        onDriverChanged = function(theCar, driver)
            if run and run.alarm and driver then S.police:chaseCar(theCar) end
        end,
    })

    S.police:init({
        onPlayerCaught = function(player) catchPlayer(player, "cop") end,
        onCarBusted = function(theCar)
            if not run then return end
            notifyAll("BUSTED — the cops boxed in the car", "red", 5)
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
        task.defer(checkLaunch)
        if run and run.crew[p] then
            run.crew[p] = nil
            if next(run.crew) == nil or #activeCrew() == 0 then
                finish("abandoned")
            end
        end
    end)

    local first = Constants.JOBS[1] and Constants.JOBS[1].id
    if first and jobs[first] then self:selectJob(first) end
    print("[JobService] Ready")
end

function JobService:getCurrent()
    local j = job()
    return j and j.cfg, j and j.refs
end

return JobService
