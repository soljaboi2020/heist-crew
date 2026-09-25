--[[
    HEIST CREW — TutorialService  (v3.1 "FIRST HEIST")
    ────────────────────────────────────────────────
    The first-time walkthrough at SUNNY'S MART. Bar: a 7-year-old gets it.

      New player (save field tutorialDone = false) lands in the club →
        big card: "First heist? Let the Boss show you!"  [LET'S GO] [I know how]
          I know how → tutorialDone = true, never asked again (no reward).
          LET'S GO   → the steps below, one at a time:

        portal   walk into the SUNNY'S MART door  (the mart gets auto-picked)
        breaker  find the breaker, hold E → camera off      (skipped if no camera)
        cash     grab the cash at the register (E, then tap fast!)
        trunk    take the bag to the car, E at the trunk
        ticket   OPTIONAL: the Golden Ticket, +$5,000  (can "Skip this")
        go       get in the car (F) and press GO!
        escape   pick how you get away (the movie plays)
        → payout: "You're a real crew member now!" + $1,000 (once, ever) + tutorialDone

      Every step advances from REAL game state, never a timer:
        JobService "launched" / "finished" events · SecurityService:camerasCut() ·
        LootService:isCarrying / counts().loaded / counts().targetSecured ·
        GetawayService:getPhase() (or the car's GetawayPhase attribute).
      Drop the bag (guard sent you back, you threw it) → back to "cash".
      Die / fail / get sent home → paused → "Try again" (back to the portal step).
      Leave the game → nothing saved as done, so the card comes back next time.

    FORGIVING RUN ("assist"): only when the launched crew is ALL tutorial players
    (a solo rookie, or a group of rookies). Then each gets TutorialStealthMult = 2:
    guards (GuardService.stealthFactor) and cameras (SecurityService) take 2x
    longer to notice them. Anyone else in the crew → no gameplay change, the
    rookie just sees the step cards.

    PLAYER ATTRIBUTES (server-set, the client TutorialHud reads them):
        Tutorial            string|nil  "offer" | "portal" | "breaker" | "cash" | "trunk" |
                                        "ticket" | "ticketCar" | "go" | "escape" | "paused"
                                        (nil = no tutorial; TipHud stays quiet while set)
        TutorialTarget      Vector3|nil where the arrow points
        TutorialPause       string|nil  why it paused: "failed" | "died" | "otherJob"
        TutorialWait        bool        portal step, but a heist is busy — wait for it
        TutorialAssist      bool        this run is the forgiving one
        TutorialStealthMult number|nil  2 during an assisted run (Guard/Security hooks)
        TutorialReward      number      set once on completion (the banner shows it)

    REMOTE "Tutorial" (RemoteEvent, created here), client → server:
        { action = "start" }        LET'S GO (from the offer) / TRY AGAIN (from paused)
        { action = "skip" }         I know how / Stop tutorial → tutorialDone, no reward
        { action = "skipTicket" }   skip the optional Golden Ticket step

    PUBLIC API:
        TutorialService:init(deps)
            deps = { data = PlayerDataService, jobService = JobService, loot = LootService,
                     security = SecurityService, economy = EconomyService, hub = world.hub,
                     portal = PortalService?, getaway = GetawayService?, notify = fn? }
        TutorialService:getStep(player) -> step | nil
        TutorialService:start(player) / :skip(player) / :skipTicket(player)   (tests / remote)
        TutorialService.REWARD = 1000
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local TutorialService = {}
TutorialService.REWARD = 1000
TutorialService.STEALTH_MULT = 2
TutorialService.JOB = "mart"

local TICK = 0.25
local IN_RUN = { breaker = true, cash = true, trunk = true, ticket = true, ticketCar = true, go = true, escape = true }

local D = {}          -- deps
local st = {}         -- [player] = { step, assist, inRun, heists, loaded, lastSelect }
local remote = nil

local function say(player, text, color, dur)
    if D.notify and player.Parent then pcall(D.notify, player, text, color or "gold", dur or 3) end
end

local function rootOf(player)
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function heistsOf(player)
    local d = D.data and D.data:getData(player)
    return d and (tonumber(d.heistsCompleted) or 0) or 0
end

local function clearAssist(player)
    player:SetAttribute("TutorialAssist", false)
    player:SetAttribute("TutorialStealthMult", nil)
end

local function setStep(player, step, target)
    local s = st[player]
    if s then s.step = step end
    player:SetAttribute("Tutorial", step)
    player:SetAttribute("TutorialTarget", target)
    if step ~= "paused" then player:SetAttribute("TutorialPause", nil) end
    if step ~= "portal" then player:SetAttribute("TutorialWait", false) end
end

local function stop(player)
    st[player] = nil
    if player.Parent then
        setStep(player, nil, nil)
        player:SetAttribute("TutorialPause", nil)
        player:SetAttribute("TutorialWait", false)
        clearAssist(player)
    end
end

local function pause(player, why)
    local s = st[player]
    if not s then return end
    s.inRun = false
    s.assist = false
    clearAssist(player)
    setStep(player, "paused", nil)
    player:SetAttribute("TutorialPause", why or "failed")
end

-- ── targets ──────────────────────────────────────────────────────────
local function martRefs()
    local J = D.jobService
    if not J then return nil end
    local cfg, refs = J:getCurrent()
    if cfg and cfg.id == TutorialService.JOB then return refs end
    return nil
end

local function portalPos()
    local hub = D.hub
    local p = hub and type(hub.portals) == "table" and hub.portals[TutorialService.JOB]
    local z = type(p) == "table" and p.zone
    if typeof(z) == "Instance" and z:IsA("BasePart") then return z.Position end
    for _, part in ipairs(game:GetService("CollectionService"):GetTagged("PortalZone")) do
        if part:IsA("BasePart") and part:GetAttribute("JobId") == TutorialService.JOB then return part.Position end
    end
    return nil
end

local function carParts()
    local car = D.jobService and D.jobService:getCar()
    if not car then return nil, nil end
    return car.trunk, car.driverSeat
end

-- nearest open pile: registers first, never the target or a heavy one
local function registerPos(player)
    if not D.loot or type(D.loot.remaining) ~= "function" then return nil end
    local root = rootOf(player)
    local from = root and root.Position or Vector3.zero
    local best, bestD, bestReg = nil, math.huge, false
    for _, r in ipairs(D.loot:remaining()) do
        if not r.locked and not r.target and not r.heavy and not r.isCase and typeof(r.pos) == "Vector3" then
            local reg = r.kind == "Register"
            local d = (r.pos - from).Magnitude
            if (reg and not bestReg) or (reg == bestReg and d < bestD) then
                best, bestD, bestReg = r.pos, d, reg
            end
        end
    end
    return best
end

local function ticketPos()
    if not D.loot or type(D.loot.remaining) ~= "function" then return nil end
    for _, r in ipairs(D.loot:remaining()) do
        if r.target and not r.locked and typeof(r.pos) == "Vector3" then return r.pos end
    end
    return nil
end

local function counts()
    local ok, c = pcall(function() return D.loot:counts() end)
    return ok and type(c) == "table" and c or { loaded = 0 }
end

local function carrying(player)
    local ok, yes = pcall(function() return D.loot:isCarrying(player) end)
    return ok and yes == true
end

local function getawayStarted()
    local G = D.getaway
    if G and type(G.getPhase) == "function" then
        local ok, ph = pcall(G.getPhase, G)
        if ok and ph and ph ~= "idle" then return true end
    end
    local car = D.jobService and D.jobService:getCar()
    local ph = car and car.model and car.model:GetAttribute("GetawayPhase")
    return type(ph) == "string" and ph ~= "" and ph ~= "wait"
end

-- ── the steps ────────────────────────────────────────────────────────
local afterLoad   -- forward

local function enterRunStep(player)
    -- first step inside the mart: the breaker (if there's a camera to cut)
    local refs = martRefs()
    local hasCams = refs and refs.breaker and type(refs.cameras) == "table" and #refs.cameras > 0
    if hasCams and not D.security:camerasCut() then
        setStep(player, "breaker", refs.breaker.Position)
    else
        setStep(player, "cash", registerPos(player))
    end
end

afterLoad = function(player)
    local c = counts()
    if not c.targetSecured and ticketPos() then
        setStep(player, "ticket", ticketPos())
    else
        local _, seat = carParts()
        setStep(player, "go", seat and seat.Position)
    end
end

-- the rookie is back in the club: aim at the mart door; pick the mart if nobody minds
local function portalTick(player, s)
    local J = D.jobService
    local phase = J:getPhase()
    player:SetAttribute("TutorialWait", phase ~= "idle")
    player:SetAttribute("TutorialTarget", portalPos())
    if phase ~= "idle" or J:getCurrentId() == TutorialService.JOB then return end
    local launchAt = J:getLaunch()
    if (launchAt or 0) > 0 or os.clock() - (s.lastSelect or 0) < 3 then return end
    -- only switch the heist when no one is standing in a door (don't hijack a crew's pick)
    local busy = false
    if D.portal and type(D.portal.getOccupants) == "function" then
        for _, cfg in ipairs(Constants.JOBS) do
            local ok, occ = pcall(D.portal.getOccupants, D.portal, cfg.id)
            if ok and type(occ) == "table" and #occ > 0 then busy = true break end
        end
    else
        for _, p in ipairs(Players:GetPlayers()) do
            if not st[p] then busy = true break end
        end
    end
    if busy then return end
    s.lastSelect = os.clock()
    local ok, err = pcall(J.selectJob, J, TutorialService.JOB)
    if not ok then warn("[TutorialService] selectJob:", err) end
end

local function tickPlayer(player, s)
    local step = s.step
    if step == "offer" or step == "paused" or step == nil then return end
    if step == "portal" then portalTick(player, s) return end
    if not s.inRun then return end

    local J = D.jobService
    if not J:isInRun(player) then
        -- jailed: keep the step, the card says "wait for a friend"; out / home = handled by events
        return
    end
    local trunk, seat = carParts()
    if step == "breaker" then
        if D.security:camerasCut() then
            setStep(player, "cash", registerPos(player))
        end
    elseif step == "cash" then
        if carrying(player) then
            s.loaded = counts().loaded
            setStep(player, "trunk", trunk and trunk.Position)
        else
            player:SetAttribute("TutorialTarget", registerPos(player))
        end
    elseif step == "trunk" then
        local c = counts()
        if c.loaded > (s.loaded or 0) and not carrying(player) then
            afterLoad(player)
        elseif not carrying(player) then
            -- dropped it (guard sent you back / threw it): grab one again
            setStep(player, "cash", registerPos(player))
        else
            player:SetAttribute("TutorialTarget", trunk and trunk.Position)
        end
    elseif step == "ticket" then
        local c = counts()
        if c.targetSecured then
            setStep(player, "go", seat and seat.Position)
        elseif carrying(player) then
            s.loaded = c.loaded
            setStep(player, "ticketCar", trunk and trunk.Position)
        else
            local tp = ticketPos()
            if tp then
                player:SetAttribute("TutorialTarget", tp)
            else
                setStep(player, "go", seat and seat.Position)   -- somebody else took it
            end
        end
    elseif step == "ticketCar" then
        local c = counts()
        if c.targetSecured or (c.loaded > (s.loaded or 0) and not carrying(player)) then
            setStep(player, "go", seat and seat.Position)
        elseif not carrying(player) then
            setStep(player, "ticket", ticketPos())
        else
            player:SetAttribute("TutorialTarget", trunk and trunk.Position)
        end
    elseif step == "go" then
        if getawayStarted() then
            setStep(player, "escape", nil)
        elseif carrying(player) then
            -- picked up another bag on the way: load it first
            s.loaded = counts().loaded
            setStep(player, "trunk", trunk and trunk.Position)
        else
            player:SetAttribute("TutorialTarget", seat and seat.Position)
        end
    end
end

-- ── lifecycle ────────────────────────────────────────────────────────
local function complete(player)
    local s = st[player]
    if not s then return end
    local first = D.data and D.data:markTutorialDone(player)
    stop(player)
    if first then
        if D.economy then
            pcall(D.economy.addCash, D.economy, player, TutorialService.REWARD, "Tutorial complete")
        end
        player:SetAttribute("TutorialReward", TutorialService.REWARD)
        print("[TutorialService] " .. player.Name .. " finished the tutorial (+$" .. TutorialService.REWARD .. ")")
    end
end

function TutorialService:getStep(player)
    local s = st[player]
    return s and s.step or nil
end

function TutorialService:offer(player)
    if not player.Parent or st[player] then return end
    if not D.data or D.data:isTutorialDone(player) then return end
    -- no Sunny's Mart in this server (its builder failed) → no tutorial to give
    if not D.jobService:isUnlocked(TutorialService.JOB) then
        warn("[TutorialService] Sunny's Mart isn't built — no tutorial this session")
        return
    end
    st[player] = { step = "offer" }
    setStep(player, "offer", nil)
end

function TutorialService:start(player)
    local s = st[player]
    if not s or (s.step ~= "offer" and s.step ~= "paused") then return false end
    s.inRun, s.assist = false, false
    clearAssist(player)
    setStep(player, "portal", portalPos())
    portalTick(player, s)
    return true
end

function TutorialService:skip(player)
    if not st[player] then return false end
    if D.data then D.data:markTutorialDone(player) end
    stop(player)
    say(player, "No problem — the Boss trusts you. Go get 'em!", "gold", 3)
    return true
end

function TutorialService:skipTicket(player)
    local s = st[player]
    if not s or (s.step ~= "ticket" and s.step ~= "ticketCar") then return false end
    local _, seat = carParts()
    setStep(player, "go", seat and seat.Position)
    return true
end

local function onLaunched(players, cfg)
    local list = {}
    for _, p in ipairs(players or {}) do list[p] = true end
    -- the forgiving run: every player who dropped in is on the tutorial
    local allRookies = true
    for p in pairs(list) do
        local s = st[p]
        if not s or s.step ~= "portal" then allRookies = false end
    end
    for p in pairs(list) do
        local s = st[p]
        if s and s.step == "portal" then
            if cfg and cfg.id == TutorialService.JOB then
                s.inRun = true
                s.heists = heistsOf(p)
                s.loaded = 0
                s.assist = allRookies
                p:SetAttribute("TutorialAssist", allRookies)
                p:SetAttribute("TutorialStealthMult", allRookies and TutorialService.STEALTH_MULT or nil)
                enterRunStep(p)
            else
                -- they walked into a different heist: that's fine, the tutorial waits
                pause(p, "otherJob")
            end
        end
    end
end

local function onFinished()
    for p, s in pairs(st) do
        if s.inRun and IN_RUN[s.step] then
            if p.Parent and heistsOf(p) > (s.heists or 0) then
                complete(p)
            elseif p.Parent then
                pause(p, "failed")
            end
        end
    end
end

local function watchCharacter(player, char)
    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end
    hum.Died:Connect(function()
        local s = st[player]
        if s and s.inRun and IN_RUN[s.step] then pause(player, "died") end
    end)
end

local function onPlayer(player)
    player.CharacterAdded:Connect(function(c) watchCharacter(player, c) end)
    if player.Character then task.spawn(watchCharacter, player, player.Character) end
    -- wait for the save (PlayerDataService loads on join; it may retry)
    task.spawn(function()
        local t0 = os.clock()
        while player.Parent and D.data and not D.data:getData(player) and os.clock() - t0 < 30 do task.wait(0.5) end
        if not player.Parent then return end
        if D.data and D.data.loadFailed and D.data:loadFailed(player) then return end
        TutorialService:offer(player)
    end)
end

function TutorialService:init(deps)
    D = deps or {}
    if not D.jobService or not D.loot or not D.security or not D.data then
        warn("[TutorialService] missing deps — tutorial off")
        return
    end
    remote = Remotes.getRemote("Tutorial", "RemoteEvent")
    remote.OnServerEvent:Connect(function(player, msg)
        local action = type(msg) == "table" and msg.action or msg
        if action == "start" then TutorialService:start(player)
        elseif action == "skip" then TutorialService:skip(player)
        elseif action == "skipTicket" then TutorialService:skipTicket(player)
        end
    end)
    D.jobService:subscribe("launched", onLaunched)
    D.jobService:subscribe("finished", onFinished)

    Players.PlayerAdded:Connect(onPlayer)
    Players.PlayerRemoving:Connect(function(p) st[p] = nil end)
    for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end

    task.spawn(function()
        while true do
            for p, s in pairs(st) do
                if p.Parent then
                    local ok, err = pcall(tickPlayer, p, s)
                    if not ok then warn("[TutorialService] tick:", err) end
                else
                    st[p] = nil
                end
            end
            task.wait(TICK)
        end
    end)
    print("[TutorialService] Ready")
end

return TutorialService
