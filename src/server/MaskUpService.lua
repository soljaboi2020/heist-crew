--[[
    HEIST CREW — MaskUpService  (v3.2 "MASK UP", casing mode)
    ────────────────────────────────────────────────
    Idea #2 in docs/research/heist-games-ideas.md (PAYDAY-style casing), made
    kid-simple:

      1. The crew drops in at refs.sneakIn with NO masks on and NO mask power.
         That is CASING: walk around, look at the guards and cameras.
         A chip says "CASING — look around, then MASK UP!" and a big pink
         MASK UP button shows (key M, gamepad L2, or tap it).
      2. While casing, guards and cameras treat you like a customer / staff:
         their meters DON'T fill — except inside a restricted room (below),
         where they fill at the normal speed. Bumping into a guard in a
         public room does nothing (a customer bumped him).
      3. Casing ends for the WHOLE crew when:
           • anyone presses MASK UP,
           • CASING_TIME (60 s) runs out,
           • anyone does a crime: starts a crime prompt (bag loot, smash a
             case, pick up a dropped bag, take the keycard, cut the cameras,
             swipe / hack a keypad, place the drill, take down a guard), any
             JobService crime event (startRun hook), the alarm going off, or
             walking into a CRIME room (the vault / safe / laser room).
      4. MASK UP: every crew member gets a 1.5 s camera shot (zoom to the face,
         the mask snaps on with a "shhk" + bass hit + flash), then the masks
         go on (ShopService:wearMask → MaskService power ON) and the screen
         says MASKS ON — THE JOB IS ON. Guards get a short grace for the shot
         so nobody is spotted while their camera is busy.

    RESTRICTED vs CRIME rooms (per job, world x/z boxes):
      • refs.restricted (optional, builders may add it):
            { BasePart | { x0, z0, x1, z1, crime = bool?, y0 = n?, y1 = n? }, ... }
        a BasePart is its oriented box; crime = true → walking in = MASK UP.
      • otherwise derived from refs.plan.rooms (world coords):
            CRIME       rooms named VAULT / SAFE / LASERS, and the room that
                        holds plan.vault (the mart's office safe)
            RESTRICTED  CRIME rooms + rooms named SECURITY / MANAGER / OFFICE
            never       the room the crew dropped into (refs.sneakIn — staff)
        Everything else (shop floor, showroom, halls, gallery, kitchen, staff
        and break rooms) is public. Height band: sneakIn floor −6 .. +14 so the
        roof is not "inside the vault".

    [slice] v3.3: jobs with refs.arrival (the crew starts on the sidewalk) ALWAYS
    case — the tutorial exception below only applies to drop-in-inside jobs.
    TUTORIAL: runs where anyone in the crew is DOING the tutorial (player
    attribute `Tutorial` = "portal" on the tutorial job, or any in-run step;
    "offer" / "paused" don't count) SKIP casing — masks go on at the drop-in
    exactly like before, so the tutorial's steps don't change.

    ATTRIBUTES (Player, server writes):
      Casing (bool)          true while this player is an unmasked "customer"
      CasingEndsAt (number)  server time (Workspace:GetServerTimeNow) casing auto-ends
      InRestricted (bool)    standing in a restricted room while casing
    GuardService.stealthFactor / its touch check and SecurityService cameras
    read Casing + InRestricted ([HOOK: MaskUp] lines in those files).

    REMOTE "MaskUp" (RemoteEvent, created here via Remotes.getRemote):
      C→S  ("maskUp")                       the button / key
      S→C  { phase = "maskup", by = name?, reason = "button"|"time"|"crime"|"zone"|"alarm",
             text = "Malachi grabbed the loot!", snap = seconds, duration = seconds }
      S→C  { phase = "end" }                casing cancelled (run over)

    PUBLIC API (all safe to call before :init — it self-inits lazily):
      MaskUpService:init(deps?)   deps = { jobService?, shop?, guards?, notify? }
      MaskUpService:beginCasing(crewList, cfg, refs) -> bool   (JobService launch)
      MaskUpService:shouldDefer(player) -> bool     (JobService addToCrew: skip wearMask)
      MaskUpService:crime(player?, why?)            (JobService startRun / triggerAlarm)
      MaskUpService:maskUp(reason, player?, text?) -> bool
      MaskUpService:isCasing() -> bool              (casing or the mask-up shot playing)
      MaskUpService:zones() -> { {x0,z0,x1,z1,crime,name,y0,y1,part?} }  (tests / debug)
      MaskUpService.CASING_TIME / SNAP / DURATION / GUARD_GRACE
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MaskUpService = {}

MaskUpService.CASING_TIME = 60     -- seconds of casing before the masks go on by themselves
MaskUpService.SNAP = 0.85          -- seconds into the shot when the mask snaps on
MaskUpService.DURATION = 1.5       -- length of the mask-up camera shot
MaskUpService.GUARD_GRACE = 1.8    -- guards can't spot anyone during the shot
MaskUpService.TICK = 0.2           -- room check rate

local REMOTE_NAME = "MaskUp"

-- prompts that are a crime the moment you START them (ProximityPrompt.Name)
local CRIME_PROMPTS = {
    BagLoot = "grabbed the loot", SmashCase = "smashed a case", PickUpBag = "grabbed a bag",
    TakeKeycard = "took the keycard", Breaker = "cut the cameras", BreakerHacker = "cut the cameras",
    Swipe = "swiped the keycard", HackKeypad = "hacked the keypad", Drill = "started the drill",
    Takedown = "took down a guard",
}
-- JobService startRun `why` → words (unknown kinds still count as a crime)
local CRIME_WORDS = {
    take = "grabbed the loot", smash = "smashed a case", load = "loaded a bag", throw = "threw a bag",
    keycard = "took the keycard", cameras = "cut the cameras", door = "opened a locked door",
    drill = "started the drill", takedown = "took down a guard", alarm = "set off the alarm",
}
local NOT_CRIME = { launch = true, caught = true }

local CRIME_ROOMS = { VAULT = true, SAFE = true, LASERS = true }
local RESTRICTED_ROOMS = { SECURITY = true, MANAGER = true, OFFICE = true }

local D = {}            -- deps
local inited = false
local remote = nil
local state = {
    casing = false,     -- the crew is unmasked
    masking = false,    -- the mask-up shot is playing (masks go on at SNAP)
    token = nil,        -- bumped every casing / reset (cancels loops + delays)
    endsAt = 0,         -- os.clock() when casing auto-ends
    crew = {},          -- [player] = true: unmasked crew members to mask
    zones = {},
}

local function optional(name)
    local mod = script.Parent:FindFirstChild(name)
    if not mod then return nil end
    local ok, r = pcall(require, mod)
    return (ok and type(r) == "table") and r or nil
end

local function job() return D.jobService or optional("JobService") end
local function shop() return D.shop or optional("ShopService") end
local function guards() return D.guards or optional("GuardService") end

local function inRun(p)
    local J = job()
    if not (p and p.Parent) then return false end
    if not J or type(J.isInRun) ~= "function" then return true end
    local ok, r = pcall(J.isInRun, J, p)
    return ok and r == true
end

local function fire(p, payload)
    if remote and p and p.Parent then pcall(remote.FireClient, remote, p, payload) end
end

local function setCasingAttrs(p, on)
    if not p or not p.Parent then return end
    p:SetAttribute("Casing", on and true or nil)
    p:SetAttribute("CasingEndsAt", on and (Workspace:GetServerTimeNow() + math.max(0, state.endsAt - os.clock())) or nil)
    p:SetAttribute("InRestricted", nil)
end

-- ── rooms ────────────────────────────────────────────────────────────
local function roomHas(r, x, z)
    return x >= math.min(r[1], r[3]) and x <= math.max(r[1], r[3]) and z >= math.min(r[2], r[4]) and z <= math.max(r[2], r[4])
end

local function buildZones(refs)
    local zones = {}
    if type(refs) ~= "table" then return zones end
    local s = refs.sneakIn
    local floorY = (s and s.at and s.at.Y) or (refs.entryPoint and refs.entryPoint.Y) or 3
    local y0, y1 = floorY - 6, floorY + 14

    if type(refs.restricted) == "table" and #refs.restricted > 0 then
        for i, r in ipairs(refs.restricted) do
            if typeof(r) == "Instance" and r:IsA("BasePart") then
                table.insert(zones, { part = r, crime = r:GetAttribute("Crime") == true, name = r.Name })
            elseif type(r) == "table" and tonumber(r[1]) and tonumber(r[4]) then
                table.insert(zones, { x0 = math.min(r[1], r[3]), z0 = math.min(r[2], r[4]), x1 = math.max(r[1], r[3]),
                    z1 = math.max(r[2], r[4]), crime = r.crime == true, name = r.name or ("restricted" .. i),
                    y0 = r.y0 or y0, y1 = r.y1 or y1 })
            end
        end
        return zones
    end

    local plan = refs.plan
    if type(plan) ~= "table" or type(plan.rooms) ~= "table" then return zones end
    local vx, vz = plan.vault and plan.vault[1], plan.vault and plan.vault[2]
    for _, r in ipairs(plan.rooms) do
        local name = string.upper(tostring(r[5] or ""))
        if tonumber(r[1]) and tonumber(r[4]) then
            local dropRoom = s and s.at and roomHas(r, s.at.X, s.at.Z)
            local crime = CRIME_ROOMS[name] or (vx and vz and roomHas(r, vx, vz)) or false
            local restricted = crime or RESTRICTED_ROOMS[name] or false
            if restricted and not dropRoom then
                table.insert(zones, { x0 = math.min(r[1], r[3]), z0 = math.min(r[2], r[4]), x1 = math.max(r[1], r[3]),
                    z1 = math.max(r[2], r[4]), crime = crime and true or false, name = name, y0 = y0, y1 = y1 })
            end
        end
    end
    return zones
end

local function zoneAt(pos)
    local best = nil
    for _, z in ipairs(state.zones) do
        local inside
        if z.part then
            local okP, lp = pcall(function() return z.part.CFrame:PointToObjectSpace(pos) end)
            local h = z.part.Size / 2
            inside = okP and math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
        else
            inside = pos.X >= z.x0 and pos.X <= z.x1 and pos.Z >= z.z0 and pos.Z <= z.z1 and pos.Y >= z.y0 and pos.Y <= z.y1
        end
        if inside then
            if z.crime then return z end
            best = best or z
        end
    end
    return best
end

-- ── the mask-up moment ───────────────────────────────────────────────
local function crewList()
    local list = {}
    for p in pairs(state.crew) do
        if p.Parent and inRun(p) then table.insert(list, p) end
    end
    return list
end

function MaskUpService:maskUp(reason, player, text)
    if not state.casing or state.masking then return false end
    state.masking = true
    local token = state.token
    local list = crewList()
    local G = guards()
    if G then G.graceUntil = math.max(G.graceUntil or 0, os.clock() + MaskUpService.GUARD_GRACE) end
    local payload = {
        phase = "maskup", reason = reason or "button", by = player and player.DisplayName or nil,
        text = text, snap = MaskUpService.SNAP, duration = MaskUpService.DURATION,
    }
    for _, p in ipairs(list) do fire(p, payload) end
    task.delay(MaskUpService.SNAP, function()
        if state.token ~= token then return end
        state.casing = false
        local S = shop()
        for _, p in ipairs(crewList()) do
            setCasingAttrs(p, false)
            if S and type(S.wearMask) == "function" then
                local ok, err = pcall(S.wearMask, S, p)
                if not ok then warn("[MaskUpService] wearMask:", err) end
            end
        end
        for p in pairs(state.crew) do setCasingAttrs(p, false) end   -- (anyone who dropped out)
        state.crew = {}
    end)
    task.delay(MaskUpService.DURATION, function()
        if state.token ~= token then return end
        state.masking = false
    end)
    return true
end

function MaskUpService:crime(player, why)
    if not state.casing or state.masking then return end
    if why and NOT_CRIME[why] then return end
    local what = (why and CRIME_WORDS[why]) or "made a move"
    local text = player and (player.DisplayName .. " " .. what .. "!") or "Somebody made a move!"
    if why == "alarm" then text = "The alarm went off!" end
    self:maskUp(why == "alarm" and "alarm" or "crime", player, text)
end

-- ── casing ───────────────────────────────────────────────────────────
-- someone is actually DOING the tutorial in this run (not just offered it / paused)
local function tutorialCrew(list, cfg)
    local TS = optional("TutorialService")
    local tutJob = (TS and TS.JOB) or "mart"
    for _, p in ipairs(list or {}) do
        local t = p:GetAttribute("Tutorial")
        if t == "portal" then
            if cfg and cfg.id == tutJob then return true end
        elseif t ~= nil and t ~= "offer" and t ~= "paused" then
            return true
        end
    end
    return false
end

local function stopCasing(tellClients)
    local wasOn = state.casing or state.masking or next(state.crew) ~= nil
    state.token = {}
    state.casing, state.masking = false, false
    for p in pairs(state.crew) do
        setCasingAttrs(p, false)
        if tellClients and wasOn then fire(p, { phase = "end" }) end
    end
    state.crew = {}
    state.zones = {}
end

function MaskUpService:beginCasing(list, cfg, refs)
    self:init()
    stopCasing(false)
    -- [slice] v3.3 a job that starts OUTSIDE (refs.arrival — Sunny's Mart) always
    -- cases, even on a tutorial run: the rookie walks in the front door as a
    -- customer (masked, the register camera would catch them on the doormat).
    -- The tutorial's first step (the breaker) is a crime, so the masks still go
    -- on right where the tutorial expects them.
    local arrives = type(refs) == "table" and type(refs.arrival) == "table"
    if not list or #list == 0 or (tutorialCrew(list, cfg) and not arrives) then return false end
    local token = {}
    state.token = token
    state.casing = true
    state.masking = false
    state.endsAt = os.clock() + MaskUpService.CASING_TIME
    state.zones = buildZones(refs)
    for _, p in ipairs(list) do
        state.crew[p] = true
        setCasingAttrs(p, true)
    end
    task.spawn(function()
        while state.token == token and state.casing and not state.masking do
            if os.clock() >= state.endsAt then
                MaskUpService:maskUp("time", nil, "Time's up!")
                break
            end
            for p in pairs(state.crew) do
                local hrp = p.Parent and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local z = zoneAt(hrp.Position)
                    local was = p:GetAttribute("InRestricted") == true
                    if (z ~= nil) ~= was then p:SetAttribute("InRestricted", z ~= nil or nil) end
                    if z and z.crime and state.casing and not state.masking then
                        MaskUpService:maskUp("zone", p, p.DisplayName .. " walked into the " .. string.lower(z.name or "vault") .. "!")
                        break
                    end
                end
            end
            task.wait(MaskUpService.TICK)
        end
    end)
    return true
end

function MaskUpService:shouldDefer(player)
    if not (state.casing or state.masking) or not player then return false end
    if state.masking and not state.casing then return false end
    if not state.crew[player] then
        -- joined the run mid-casing: unmasked like everyone else
        state.crew[player] = true
        setCasingAttrs(player, true)
    end
    return true
end

function MaskUpService:isCasing()
    return state.casing or state.masking
end

function MaskUpService:zones()
    return state.zones
end

-- ── init ─────────────────────────────────────────────────────────────
function MaskUpService:init(deps)
    deps = deps or {}
    D.jobService = deps.jobService or D.jobService
    D.shop = deps.shop or D.shop
    D.guards = deps.guards or D.guards
    if inited then return end
    inited = true

    remote = Remotes.getRemote(REMOTE_NAME, "RemoteEvent")
    remote.OnServerEvent:Connect(function(player, action)
        if action ~= "maskUp" then return end
        if not state.casing or state.masking then return end
        if not state.crew[player] and not inRun(player) then return end
        MaskUpService:maskUp("button", player, player.DisplayName .. " said MASK UP!")
    end)

    local function onPrompt(prompt, player)
        if not state.casing or state.masking or not prompt or not player then return end
        local what = CRIME_PROMPTS[prompt.Name]
        if not what then return end
        MaskUpService:maskUp("crime", player, player.DisplayName .. " " .. what .. "!")
    end
    ProximityPromptService.PromptButtonHoldBegan:Connect(onPrompt)
    ProximityPromptService.PromptTriggered:Connect(onPrompt)

    local J = job()
    if J and type(J.subscribe) == "function" then
        J:subscribe("finished", function() stopCasing(true) end)
        J:subscribe("reset", function() stopCasing(true) end)
    end
    Players.PlayerRemoving:Connect(function(p) state.crew[p] = nil end)
    print("[MaskUpService] casing mode ready 🎭")
end

return MaskUpService
