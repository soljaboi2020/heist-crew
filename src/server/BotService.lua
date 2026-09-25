--[[
    HEIST CREW — BotService  (v2.0 "BIGGER", V2_SPEC §6)
    ────────────────────────────────────────────────
    AI crewmates for small crews. The kid rule: "playing alone? You get robot
    friends. Give them your bag (E) and they take it to the car for you."

      • when a heist LAUNCHES with fewer than BOTS.CREW_TARGET (3) real players,
        1–2 bots drop in at the job's sneakIn (2 bots solo, 1 bot with two
        players). Each bot belongs to a player and follows them with
        PathfindingService, about FOLLOW_DIST (6) studs behind. Further than
        CATCH_UP_DIST (60), or stuck for 2 s → it teleports behind its player.
      • "Give bag" (E) on a bot: your bag moves onto the bot
        (LootService:transferToBot), it walks to the getaway car trunk and loads
        it (LootService:botLoad — counts EXACTLY like a player load), then comes
        back to its player. Stuck on the way → it teleports next to the car.
      • guards, cameras, lasers and cops only look at Players, so they ignore
        bots (bot models are tagged "BotCrew" and SecurityService also leaves
        them out of its camera rays). Bots walk through players (collision
        groups HCBots / HCPlayers) so they never block a doorway.
      • bots despawn when the run ends or the job changes.

    Model: NpcFactory R15, attribute IsBot = true, BotName, OwnerUserId;
    tag "BotCrew"; a bright purple crew outfit + the Bandit mask so nobody
    mistakes them for a guard. No floating name tags (art rule).

    PUBLIC API:
        BotService:init({ jobService = JobService, loot = LootService })
        BotService:spawnFor(players: {Player}, refs: JobRefs) -> { botModel }
        BotService:despawnAll()
        BotService:getBots() -> { { model, name, owner } }
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local NpcFactory = require(script.Parent.NpcFactory)

local BotService = {}

local B = Constants.BOTS or { CREW_TARGET = 3, MAX = 2, FOLLOW_DIST = 6, CATCH_UP_DIST = 60, NAMES = { "Rex", "Pip" } }
local STUCK_TIME = 2
local DELIVER_STUCK = 3
local LOAD_RANGE = 7
local REPLAN = 1

local Job, Loot = nil, nil
local bots = {}               -- list of bot tables
local folder = nil
local generation = 0
local notifyRemote = Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent")

local BOT_GROUP, PLAYER_GROUP = "HCBots", "HCPlayers"
local groupsReady = false

local function notify(player, text, color, duration)
    if player and player.Parent then
        notifyRemote:FireClient(player, { text = text, color = color or "white", duration = duration or 3 })
    end
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- ── collision groups: bots never shove / block players ───────────────
local function setupGroups()
    local ok, err = pcall(function()
        pcall(function() PhysicsService:RegisterCollisionGroup(BOT_GROUP) end)
        pcall(function() PhysicsService:RegisterCollisionGroup(PLAYER_GROUP) end)
        PhysicsService:CollisionGroupSetCollidable(BOT_GROUP, PLAYER_GROUP, false)
        PhysicsService:CollisionGroupSetCollidable(BOT_GROUP, BOT_GROUP, false)
    end)
    groupsReady = ok
    if not ok then warn("[BotService] collision groups:", err) end
end

local function setGroup(model, group)
    if not groupsReady then return end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then d.CollisionGroup = group end
    end
end

local function hookPlayerGroup(player)
    local function onChar(char)
        if not groupsReady then return end
        setGroup(char, PLAYER_GROUP)
        char.DescendantAdded:Connect(function(d)
            if d:IsA("BasePart") and d.CollisionGroup == "Default" then d.CollisionGroup = PLAYER_GROUP end
        end)
    end
    player.CharacterAdded:Connect(onChar)
    if player.Character then onChar(player.Character) end
end

-- ── building a bot ───────────────────────────────────────────────────
local BOT_SPEC = {
    -- no outfit id: a plain R15 in bright crew colours (can't collide with a
    -- deleted catalog item) + the free Bandit mask everyone owns
    hats = { (Constants.MASKS and Constants.MASKS[1] and Constants.MASKS[1].assetId) or 93050572 },
    bodyColors = {
        head  = Color3.fromRGB(205, 160, 120),
        torso = Color3.fromRGB(150, 70, 230),    -- crew purple
        arms  = Color3.fromRGB(150, 70, 230),
        legs  = Color3.fromRGB(40, 40, 60),
    },
}

local function ensureFolder()
    if folder and folder.Parent then return folder end
    folder = Instance.new("Folder")
    folder.Name = "BotCrew"
    folder.Parent = Workspace
    return folder
end

local function rootOf(player)
    local char = player and player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then return hrp, hum end
    return nil
end

local function place(bot, pos, faceTo)
    local cf = faceTo and CFrame.lookAt(pos, Vector3.new(faceTo.X, pos.Y, faceTo.Z)) or CFrame.new(pos)
    bot.root.AssemblyLinearVelocity = Vector3.zero
    bot.model:PivotTo(cf)
    bot.points, bot.idx = nil, 1
    bot.lastMoveAt, bot.lastPos = os.clock(), pos
    bot.humanoid:MoveTo(pos)
end

local function behind(player, dist)
    local hrp = rootOf(player)
    if not hrp then return nil end
    local look = flat(hrp.CFrame.LookVector)
    look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
    return hrp.Position - look * dist, hrp.Position
end

local function teleportBehind(bot)
    local pos, ownerPos = behind(bot.owner, 4)
    if pos then place(bot, pos, ownerPos) end
end

local function trunkPart()
    local car = Job and Job.getCar and Job:getCar()
    local t = car and car.trunk
    if t and t.Parent then return t end
    return nil
end

-- walk along a path to `goal`; replans every REPLAN seconds or when the goal moves
local function walk(bot, goal)
    local t = os.clock()
    if not bot.points or t - (bot.planAt or 0) > REPLAN or (bot.goal and (bot.goal - goal).Magnitude > 4) then
        bot.planAt = t
        bot.goal = goal
        local path = PathfindingService:CreatePath({ AgentRadius = 1.6, AgentHeight = 5, AgentCanJump = true })
        local ok = pcall(function() path:ComputeAsync(bot.root.Position, goal) end)
        if ok and path.Status == Enum.PathStatus.Success then
            bot.points = {}
            for i, wp in ipairs(path:GetWaypoints()) do
                if i > 1 then table.insert(bot.points, wp) end
            end
            bot.pathOk = true
        else
            bot.points = { { Position = goal, Action = Enum.PathWaypointAction.Walk } }
            bot.pathOk = false
        end
        bot.idx = 1
        bot.issuedAt = 0
    end
    local wp = bot.points[bot.idx]
    while wp and flat(wp.Position - bot.root.Position).Magnitude < 2.5 do
        bot.idx = bot.idx + 1
        wp = bot.points[bot.idx]
        bot.issuedAt = 0
    end
    if wp and t - (bot.issuedAt or 0) > 0.8 then
        bot.humanoid:MoveTo(wp.Position)
        if wp.Action == Enum.PathWaypointAction.Jump then bot.humanoid.Jump = true end
        bot.issuedAt = t
    end
end

local function stop(bot)
    if bot.points then
        bot.points, bot.idx = nil, 1
        bot.humanoid:MoveTo(bot.root.Position)
    end
end

-- stuck = trying to move but hasn't gone anywhere for `limit` seconds
local function stuckFor(bot, limit)
    local pos = bot.root.Position
    if not bot.lastPos or (pos - bot.lastPos).Magnitude > 1 then
        bot.lastPos = pos
        bot.lastMoveAt = os.clock()
        return false
    end
    return os.clock() - (bot.lastMoveAt or os.clock()) > limit
end

local function setPrompt(bot)
    if bot.prompt then
        -- (v2.0.1) only show "Give bag" when the owner actually has a bag (it was clutter)
        bot.prompt.Enabled = bot.state == "follow" and bot.owner ~= nil and bot.owner:GetAttribute("CarryingLoot") ~= nil
    end
end

local function reassign(bot)
    for _, other in ipairs(bots) do
        if other ~= bot and other.owner and other.owner.Parent then
            bot.owner = other.owner
            bot.model:SetAttribute("OwnerUserId", other.owner.UserId)
            return true
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if Job and Job.isInRun and Job:isInRun(p) then
            bot.owner = p
            bot.model:SetAttribute("OwnerUserId", p.UserId)
            return true
        end
    end
    return false
end

local function removeBot(bot)
    bot.alive = false
    if Loot and Loot.dropBot then pcall(Loot.dropBot, Loot, bot.model) end
    if bot.model then bot.model:Destroy() end
    local i = table.find(bots, bot)
    if i then table.remove(bots, i) end
end

local function brain(bot, gen)
    task.spawn(function()
        while bot.alive and generation == gen and bot.model.Parent do
            local ok, err = pcall(function()
                if bot.humanoid.Health <= 0 then
                    bot.humanoid.Health = bot.humanoid.MaxHealth
                end
                if not (bot.owner and bot.owner.Parent) then
                    if not reassign(bot) then
                        removeBot(bot)
                        return
                    end
                end

                if bot.state == "deliver" then
                    local trunk = trunkPart()
                    local carrying = Loot and Loot:botCarrying(bot.model)
                    if not carrying then
                        bot.state = "follow"
                        setPrompt(bot)
                        return
                    end
                    if not trunk then
                        -- no car to load: hang on to the bag and keep following
                        bot.state = "follow"
                        setPrompt(bot)
                        return
                    end
                    local d = flat(trunk.Position - bot.root.Position).Magnitude
                    if d <= LOAD_RANGE then
                        stop(bot)
                        local loaded = Loot:botLoad(bot.model, trunk)
                        bot.state = "follow"
                        setPrompt(bot)
                        if loaded then
                            notify(bot.owner, string.format("%s put your bag in the car!", bot.name), "green", 3)
                        end
                        return
                    end
                    -- stand behind the car, not in the middle of it
                    local carCF = trunk.CFrame
                    local goal = trunk.Position + flat(carCF.LookVector) * 3
                    walk(bot, goal)
                    bot.humanoid.WalkSpeed = 20
                    if stuckFor(bot, DELIVER_STUCK) or os.clock() - (bot.deliverStart or 0) > 40 then
                        -- can't find a way (locked door, fence): hop to the car
                        local side = flat(carCF.LookVector)
                        side = side.Magnitude > 1e-3 and side.Unit or Vector3.new(0, 0, 1)
                        place(bot, trunk.Position + side * 5 + Vector3.new(0, 3, 0), trunk.Position)
                        bot.deliverStart = os.clock()
                    end
                    return
                end

                -- follow
                local hrp, hum = rootOf(bot.owner)
                if not hrp or hum.SeatPart or bot.owner:GetAttribute("Jailed") then
                    stop(bot)
                    return
                end
                local d = flat(hrp.Position - bot.root.Position).Magnitude
                if d > (B.CATCH_UP_DIST or 60) or math.abs(hrp.Position.Y - bot.root.Position.Y) > 25 then
                    teleportBehind(bot)
                    return
                end
                if d > (B.FOLLOW_DIST or 6) + 2 then
                    local goal = behind(bot.owner, B.FOLLOW_DIST or 6)
                    -- (v2.0.1) side-by-side, not stacked on each other
                    if goal and bot.side then
                        local hrp = rootOf(bot.owner)
                        if hrp then goal = goal + hrp.CFrame.RightVector * bot.side end
                    end
                    bot.humanoid.WalkSpeed = d > 20 and 22 or 16
                    if goal then walk(bot, goal) end
                    if stuckFor(bot, STUCK_TIME) then teleportBehind(bot) end
                else
                    stop(bot)
                    bot.lastPos = bot.root.Position
                    bot.lastMoveAt = os.clock()
                end
            end)
            if not ok then warn("[BotService] brain:", err) end
            task.wait(0.2)
        end
    end)
end

local function giveBag(bot, player)
    if not bot.alive or bot.state ~= "follow" then return end
    if not (Loot and Loot:isCarrying(player)) then
        notify(player, "Grab some loot first, then give the bag to " .. bot.name, "white", 3)
        return
    end
    if not trunkPart() then
        notify(player, "There's no car to put it in", "white", 2)
        return
    end
    local kind = Loot:transferToBot(player, bot.model)
    if not kind then return end
    bot.state = "deliver"
    bot.deliverStart = os.clock()
    bot.points = nil
    bot.lastPos, bot.lastMoveAt = bot.root.Position, os.clock()
    setPrompt(bot)
    notify(player, string.format("%s is taking your %s to the car!", bot.name, kind), "gold", 3)
end

local function makeBot(owner, name, pos, faceTo, gen)
    local spec = table.clone(BOT_SPEC)
    spec.name = "Bot_" .. name
    local ok, model, humanoid, root = pcall(NpcFactory.build, spec)
    if not ok or not model or not humanoid or not root then
        warn("[BotService] could not build bot", name, ok and "" or model)
        return nil
    end
    if generation ~= gen then model:Destroy() return nil end
    model:SetAttribute("IsBot", true)
    model:SetAttribute("BotName", name)
    model:SetAttribute("OwnerUserId", owner.UserId)
    CollectionService:AddTag(model, "BotCrew")
    model.Parent = ensureFolder()
    setGroup(model, BOT_GROUP)
    pcall(function() root:SetNetworkOwner(nil) end)
    pcall(NpcFactory.animate, humanoid)
    humanoid.WalkSpeed = 16

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "GiveBag"
    prompt.ActionText = "Give bag"
    prompt.ObjectText = name .. " (crew bot)"
    prompt.HoldDuration = 0.3
    prompt.MaxActivationDistance = 8
    prompt.RequiresLineOfSight = false
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.Parent = root

    local bot = {
        model = model, humanoid = humanoid, root = root, owner = owner, name = name,
        state = "follow", prompt = prompt, alive = true,
    }
    prompt.Triggered:Connect(function(player) giveBag(bot, player) end)
    bot.side = (#bots % 2 == 0) and -3 or 3
    owner:GetAttributeChangedSignal("CarryingLoot"):Connect(function() setPrompt(bot) end)
    setPrompt(bot)
    place(bot, pos, faceTo)
    table.insert(bots, bot)
    brain(bot, gen)
    return bot
end

-- nothing solid (walls, props) where a bot would stand; players / bots don't count
local function clearSpot(pos)
    local ok, hits = pcall(function()
        return Workspace:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(2, 4, 2))
    end)
    if not ok then return true end
    for _, p in ipairs(hits) do
        local model = p:FindFirstAncestorOfClass("Model")
        local isChar = model and model:FindFirstChildOfClass("Humanoid") ~= nil
        if p.CanCollide and not isChar then return false end
    end
    return true
end

function BotService:spawnFor(players, refs)
    self:despawnAll()
    local real = {}
    for _, p in ipairs(players or {}) do if p.Parent then table.insert(real, p) end end
    local want = math.clamp((B.CREW_TARGET or 3) - #real, 0, B.MAX or 2)
    if want <= 0 or #real == 0 then return {} end
    local s = refs and refs.sneakIn
    local base, face, spread
    if s then
        base, face, spread = s.at, s.face, s.spread
    else
        local hrp = rootOf(real[1])
        if not hrp then return {} end
        base, face, spread = hrp.Position, hrp.Position + hrp.CFrame.LookVector * 10, Vector3.new(1, 0, 0)
    end
    local gen = generation
    local names = {}
    local pool = table.clone(B.NAMES or { "Rex", "Pip" })
    local made = {}
    for i = 1, want do
        local owner = real[(i - 1) % #real + 1]
        local name = table.remove(pool, math.random(1, math.max(1, #pool))) or ("Bot" .. i)
        -- stand them just behind the crew's drop-in rows
        local away = flat(base - face)
        away = away.Magnitude > 1e-3 and away.Unit or Vector3.new(0, 0, 1)
        local pos = base + spread * ((i - 1.5) * 3) + away * 5 + Vector3.new(0, 1, 0)
        if not clearSpot(pos) then
            -- (v2.0 fix) no room behind the crew (the jewelry back office puts that
            -- spot inside the wall): stand in front of them instead
            local alt = base + spread * ((i - 1.5) * 3) - away * 3 + Vector3.new(0, 1, 0)
            if clearSpot(alt) then pos = alt end
        end
        local bot = makeBot(owner, name, pos, face, gen)
        if bot then
            table.insert(names, name)
            table.insert(made, bot.model)
            notify(owner, string.format("%s the crew bot is with you! Hold E on %s to give them your bag.", name, name), "gold", 5)
        end
    end
    if #names > 0 and Job and Job.noteBots then Job:noteBots(names) end
    return made
end

function BotService:despawnAll()
    generation = generation + 1
    local list = table.clone(bots)
    for _, bot in ipairs(list) do removeBot(bot) end
    bots = {}
    if folder then folder:Destroy() folder = nil end
end

function BotService:getBots()
    local out = {}
    for _, b in ipairs(bots) do table.insert(out, { model = b.model, name = b.name, owner = b.owner }) end
    return out
end

function BotService:init(deps)
    deps = deps or {}
    Job = deps.jobService
    Loot = deps.loot
    setupGroups()
    Players.PlayerAdded:Connect(hookPlayerGroup)
    for _, p in ipairs(Players:GetPlayers()) do hookPlayerGroup(p) end
    if Job and Job.subscribe then
        Job:subscribe("launched", function(players, _cfg, refs) BotService:spawnFor(players, refs) end)
        Job:subscribe("finished", function() BotService:despawnAll() end)
        Job:subscribe("jobChanged", function() BotService:despawnAll() end)
    else
        warn("[BotService] JobService has no subscribe() — bots disabled")
    end
    print("[BotService] Ready")
end

return BotService
