--[[
    HEIST CREW — PingService  (v2.2 "TALK WITHOUT TALKING")
    ────────────────────────────────────────────────
    Ideas #8 (ping / spot + quick-chat wheel). Many kids have voice + text
    chat off, so a 4-player crew needs a way to point and shout that works
    with chat disabled. The client (PingWheel) sends WHERE you aimed; this
    service does all the deciding:

      📍 PING   (C→S "Ping"  (origin:Vector3, dir:Vector3))
         • rate limit: 1 per 0.7 s per player (extra presses are dropped)
         • the server re-casts the ray itself (from the camera origin the
           client gave, clamped to your head if it's silly-far away), up to
           150 studs from YOUR CHARACTER — past that, nothing happens
         • what you hit decides the marker (first match wins):
               guard  → "GUARD"        (red)     also a crew Highlight on him
               camera → "CAMERA"       (orange)
               loot   → "LOOT"         (gold)
               door / keycard door / vault door → "DOOR" / "KEYCARD" (blue)
               vent / roof hatch → "VENT" / "HATCH"
               anything else → "LOOK"  (a plain pin)
           A little aim-help: a guard / camera the ray passes close to (and
           that isn't behind what you hit) counts as hit — kids don't aim.
         • broadcast (S→C "Ping") to your crew:
             { id, by = Player, kind, label, pos = Vector3, target = Instance?,
               life = seconds, t = server time }
           Lookouts' guard + camera pings last longer (9 s instead of 6).

      💬 QUICK CHAT  (C→S "QuickChat" (index 1..6))
         • rate limit: 1 per 1.5 s per player
         • broadcast (S→C "QuickChat") to your crew: { by = Player, index, t }
           (the words live in the client — PingWheel.LINES — so the server
           only ever relays a number: nothing typed ever crosses the wire)

    "Your crew" = while a job is running, the players in the run (jailed
    teammates included) talk to each other and lobby players talk to the
    lobby. With no job running, everyone is one crew.

    Remotes (created here with Remotes.getRemote — add to Remotes.NAMES):
        Ping       RemoteEvent  C→S (origin, dir)   ·  S→C (payload)
        QuickChat  RemoteEvent  C→S (index)         ·  S→C (payload)

    PUBLIC API:
        PingService:init(deps)     deps = { jobService? }   (all optional)
        PingService:classify(hitInstance, hitPos, origin?, dir?) -> kind, label, target, pos   (tests)
        PingService:ping(player, origin, dir) -> payload | nil, reason    (the remote handler; tests)
        PingService:say(player, index) -> payload | nil, reason
        PingService.PING_COOLDOWN, .CHAT_COOLDOWN, .MAX_DIST, .LIFE, .LOOKOUT_LIFE, .NUM_LINES
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PingService = {}

PingService.PING_COOLDOWN = 0.7
PingService.CHAT_COOLDOWN = 1.5
PingService.MAX_DIST = 150          -- studs from the pinger's character
PingService.MAX_ORIGIN = 80         -- camera further than this from you → cast from your head instead
PingService.LIFE = 6
PingService.LOOKOUT_LIFE = 9        -- ideas #8: "camera pings last longer" for the Lookout
PingService.NUM_LINES = 6
PingService.NEAR = 4.5              -- studs: "you pinged the floor right next to the loot" still counts

local deps = {}
local lastPing = {}                 -- [Player] = os.clock()
local lastChat = {}
local nextId = 0
local lootPrompts = {}              -- [ProximityPrompt] = true  (loot anchors are CanQuery=false, so rays miss them)
local pingRemote, chatRemote

-- ── helpers ────────────────────────────────────────────────────────────
local function finiteV3(v)
    if typeof(v) ~= "Vector3" then return false end
    for _, n in ipairs({ v.X, v.Y, v.Z }) do
        if n ~= n or n == math.huge or n == -math.huge then return false end
    end
    return true
end

local function rootOf(player)
    local char = player and player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not hum or hum.Health <= 0 then return nil end
    return root, char
end

local function modelPos(inst)
    if inst:IsA("Model") then
        local pp = inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChildWhichIsA("BasePart", true)
        if pp then return pp.Position end
        local ok, cf = pcall(function() return inst:GetPivot() end)
        return ok and cf.Position or nil
    elseif inst:IsA("BasePart") then
        return inst.Position
    end
    return nil
end

local function promptPos(p)
    local par = p.Parent
    if not par then return nil end
    if par:IsA("Attachment") then return par.WorldPosition end
    if par:IsA("BasePart") then return par.Position end
    if par:IsA("Model") then return modelPos(par) end
    return nil
end

local function isLootPrompt(p)
    return p.Name == "BagLoot" or p.Name == "SmashCase"
end

local function watchPrompt(inst)
    if inst:IsA("ProximityPrompt") and isLootPrompt(inst) then
        lootPrompts[inst] = true
        inst.AncestryChanged:Connect(function()
            if not inst:IsDescendantOf(workspace) then lootPrompts[inst] = nil end
        end)
    end
end

local function tagged(inst, tag)
    local ok, r = pcall(function() return CollectionService:HasTag(inst, tag) end)
    return ok and r
end

-- "Is this instance one of the things a ping names?"  → kind, label, target
local function kindOf(inst)
    if tagged(inst, "Guard") then return "guard", "GUARD", inst end
    if tagged(inst, "SecurityCamera") then return "camera", "CAMERA", inst end
    if tagged(inst, "Vent") then return "vent", "VENT", inst end
    if inst:GetAttribute("LootKind") ~= nil or inst:GetAttribute("LootName") ~= nil
        or tagged(inst, "TargetTrophy") then
        return "loot", "LOOT", inst
    end
    local n = inst.Name
    if n == "LootPrompt" then return "loot", "LOOT", inst end
    if n:find("KeycardDoor") then return "door", "KEYCARD", inst end
    if n:find("Hatch") then return "vent", "HATCH", inst end
    if n:find("Vent") then return "vent", "VENT", inst end
    if n:find("VaultDoor") or n == "Vault" then return "door", "VAULT", inst end
    if n:find("Door") then return "door", "DOOR", inst end
    return nil
end

local RANK = { guard = 1, camera = 2, loot = 3, door = 4, vent = 5 }

-- ── classify ───────────────────────────────────────────────────────────
-- hit = the BasePart the ray hit (or nil), pos = the hit point.
-- origin/dir (optional) turn on the aim-help for guards + cameras.
function PingService:classify(hit, pos, origin, dir)
    local best, bestRank = nil, math.huge
    local function offer(kind, label, target, at)
        if kind and (RANK[kind] or 99) < bestRank then
            best = { kind = kind, label = label, target = target, pos = at }
            bestRank = RANK[kind] or 99
        end
    end

    -- 1) the thing you hit, or anything it's part of (a guard's arm → the guard)
    local a = hit
    while a and a ~= workspace and a.Parent do
        local k, l, t = kindOf(a)
        if k then
            offer(k, l, t, (k == "guard" or k == "camera") and modelPos(t) or pos)
            break
        end
        a = a.Parent
    end

    -- 2) aim-help: guards / cameras the ray passes close to, not behind the hit
    if origin and dir and dir.Magnitude > 0 then
        local u = dir.Unit
        local hitAlong = (pos - origin):Dot(u)
        for tag, kind in pairs({ Guard = "guard", SecurityCamera = "camera" }) do
            for _, inst in ipairs(CollectionService:GetTagged(tag)) do
                if inst:IsDescendantOf(workspace) and (RANK[kind] < bestRank) then
                    local p = modelPos(inst)
                    if p then
                        local along = (p - origin):Dot(u)
                        if along > 0 and along <= hitAlong + 3 then
                            local off = ((p - origin) - u * along).Magnitude
                            if off <= 2.5 + along * 0.02 then
                                offer(kind, kind == "guard" and "GUARD" or "CAMERA", inst, p)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3) near the hit point: loot anchors (rays can't hit them), vents, guards
    if bestRank > RANK.loot then
        local bestD = PingService.NEAR
        for p in pairs(lootPrompts) do
            if p.Parent and p.Enabled then
                local pp = promptPos(p)
                if pp then
                    local d = (pp - pos).Magnitude
                    if d <= bestD then
                        bestD = d
                        offer("loot", "LOOT", p.Parent, pp)
                    end
                end
            end
        end
        -- dropped / thrown loot bags (attribute Kind + Value)
        for _, d in ipairs(workspace:GetChildren()) do
            if d:GetAttribute("LootName") ~= nil then
                local dp = modelPos(d)
                if dp and (dp - pos).Magnitude <= PingService.NEAR then offer("loot", "LOOT", d, dp) end
            end
        end
    end
    if bestRank > RANK.vent then
        for _, v in ipairs(CollectionService:GetTagged("Vent")) do
            if v:IsA("BasePart") and (v.Position - pos).Magnitude <= PingService.NEAR then
                offer("vent", "VENT", v, v.Position)
            end
        end
    end

    if best then return best.kind, best.label, best.target, best.pos or pos end
    return "look", "LOOK", nil, pos
end

-- ── crew ───────────────────────────────────────────────────────────────
local function inRun(p)
    local js = deps.jobService
    if not js then return false end
    local ok, r = pcall(function() return js:isInRun(p) end)
    return (ok and r) or p:GetAttribute("Jailed") == true
end

local function audience(sender)
    local js = deps.jobService
    local running = false
    if js then
        local ok, ph = pcall(function() return js:getPhase() end)
        running = ok and ph == "running"
    end
    local list = {}
    local mine = running and inRun(sender)
    for _, p in ipairs(Players:GetPlayers()) do
        if not running or inRun(p) == mine then table.insert(list, p) end
    end
    return list
end
PingService._audience = audience

local function send(remote, sender, payload)
    if not remote then return end
    for _, p in ipairs(audience(sender)) do
        remote:FireClient(p, payload)
    end
end

-- ── ping ───────────────────────────────────────────────────────────────
function PingService:ping(player, origin, dir)
    if not (player and player:IsA("Player")) then return nil, "who" end
    if not finiteV3(origin) or not finiteV3(dir) or dir.Magnitude < 1e-3 then return nil, "bad args" end
    local now = os.clock()
    if lastPing[player] and now - lastPing[player] < PingService.PING_COOLDOWN then return nil, "cooldown" end
    local root, char = rootOf(player)
    if not root then return nil, "no character" end
    local head = char:FindFirstChild("Head")
    local headPos = head and head.Position or (root.Position + Vector3.new(0, 1.5, 0))
    if (origin - root.Position).Magnitude > PingService.MAX_ORIGIN then origin = headPos end
    lastPing[player] = now

    local u = dir.Unit
    local len = PingService.MAX_DIST + (origin - root.Position).Magnitude
    local exclude = { char }
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = exclude
    local hit, pos
    for _ = 1, 5 do
        local r = workspace:Raycast(origin, u * len, params)
        if not r then break end
        local inst = r.Instance
        -- see-through blockers (invisible walls, glass-ish triggers) don't catch pings
        if inst and inst:IsA("BasePart") and inst.Transparency >= 0.95 and not kindOf(inst)
            and not (inst.Parent and (tagged(inst.Parent, "Guard") or tagged(inst.Parent, "SecurityCamera"))) then
            table.insert(exclude, inst)
            params.FilterDescendantsInstances = exclude
        else
            hit, pos = inst, r.Position
            break
        end
    end
    if not pos then return nil, "nothing there" end
    if (pos - root.Position).Magnitude > PingService.MAX_DIST then return nil, "too far" end

    local kind, label, target, at = self:classify(hit, pos, origin, u)
    at = at or pos
    if (at - root.Position).Magnitude > PingService.MAX_DIST + 6 then at, target, kind, label = pos, nil, "look", "LOOK" end
    local life = PingService.LIFE
    if player:GetAttribute("Role") == "Lookout" and (kind == "guard" or kind == "camera") then
        life = PingService.LOOKOUT_LIFE
    end
    nextId += 1
    local payload = {
        id = nextId, by = player, kind = kind, label = label, pos = at,
        target = target, life = life, t = workspace:GetServerTimeNow(),
    }
    send(pingRemote, player, payload)
    return payload
end

-- ── quick chat ─────────────────────────────────────────────────────────
function PingService:say(player, index)
    if not (player and player:IsA("Player")) then return nil, "who" end
    if type(index) ~= "number" or index ~= index or index % 1 ~= 0
        or index < 1 or index > PingService.NUM_LINES then
        return nil, "bad index"
    end
    local now = os.clock()
    if lastChat[player] and now - lastChat[player] < PingService.CHAT_COOLDOWN then return nil, "cooldown" end
    if not rootOf(player) then return nil, "no character" end
    lastChat[player] = now
    local payload = { by = player, index = index, t = workspace:GetServerTimeNow() }
    send(chatRemote, player, payload)
    return payload
end

-- ── init ───────────────────────────────────────────────────────────────
function PingService:init(d)
    deps = d or {}
    pingRemote = Remotes.getRemote((Remotes.NAMES and Remotes.NAMES.Ping) or "Ping", "RemoteEvent")
    chatRemote = Remotes.getRemote((Remotes.NAMES and Remotes.NAMES.QuickChat) or "QuickChat", "RemoteEvent")

    for _, x in ipairs(workspace:GetDescendants()) do watchPrompt(x) end
    workspace.DescendantAdded:Connect(watchPrompt)

    pingRemote.OnServerEvent:Connect(function(player, origin, dir)
        local ok, err = pcall(function() self:ping(player, origin, dir) end)
        if not ok then warn("[PingService] ping:", err) end
    end)
    chatRemote.OnServerEvent:Connect(function(player, index)
        local ok, err = pcall(function() self:say(player, index) end)
        if not ok then warn("[PingService] chat:", err) end
    end)
    Players.PlayerRemoving:Connect(function(p)
        lastPing[p] = nil
        lastChat[p] = nil
    end)
    print("[HEIST CREW] PingService ready ✅ (ping + quick chat)")
end

return PingService
