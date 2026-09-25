--[[
    HEIST CREW — GuardService
    ────────────────────────────────────────────────
    Spawns + animates patrolling guards. Each guard:
      1. Walks between two waypoints on a loop (PATROL state)
      2. Scans for players in a 90° forward cone using raycasts
      3. If a player is spotted: alarm fires + all guards CHASE
      4. If a guard touches a player: heist FAILS

    2026-09-24: guards are now REAL R15 avatars (official Roblox police
    outfit) that walk with animations and use pathfinding — built by
    NpcFactory. They used to be an anchored brick + cube head on a tween.

    PUBLIC API:
        GuardService:spawnPatrols(callbacks)
            callbacks.onPlayerSpotted(player)
            callbacks.onPlayerCaught(player)
        GuardService:setAlarmActive(active:boolean)  -- triggers chase mode
        GuardService:reset()  -- send everyone back to patrol
--]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local NpcFactory = require(script.Parent.NpcFactory)

local GuardService = {}

local guards = {}             -- list of guard tables
local alarmActive = false
local callbacks = {
    onPlayerSpotted = function() end,
    onPlayerCaught = function() end,
}

-- ──────────────────────────────────────────────
-- Build a single guard (a real R15 avatar — see NpcFactory)
-- ──────────────────────────────────────────────
local GUARD_SPEC = {
    outfitId = 320998366,   -- official Roblox "Police Officer Nash" (bundle 349)
    bodyColors = {          -- used only if the outfit ever fails to load
        head  = Color3.fromRGB(204, 142, 105),
        torso = Color3.fromRGB(27, 42, 53),
        arms  = Color3.fromRGB(27, 42, 53),
        legs  = Color3.fromRGB(17, 17, 17),
    },
}

local function buildGuardModel(name, position)
    local spec = table.clone(GUARD_SPEC)
    spec.name = name
    local model, humanoid, root = NpcFactory.build(spec)
    if not model then return nil end

    -- Vision cone: a SpotLight on the head. In the dark mansion (Future
    -- lighting) this throws a visible pool on the floor — that IS the stealth game.
    local head = model:FindFirstChild("Head") or root
    local vision = Instance.new("SpotLight")
    vision.Brightness = 5
    vision.Range = Constants.GUARD_VISION_RANGE
    vision.Angle = Constants.GUARD_VISION_FOV_DEGREES
    vision.Color = Color3.fromRGB(255, 220, 100)
    vision.Face = Enum.NormalId.Front
    vision.Shadows = true
    vision.Parent = head

    model:PivotTo(CFrame.new(position + Vector3.new(0, 2, 0)))
    return model, humanoid, root, head
end

-- ──────────────────────────────────────────────
-- Spawn a single guard with a patrol path
-- ──────────────────────────────────────────────
local function spawnGuard(name, waypointA, waypointB, model, humanoid, root, head)
    local guard = {
        name = name,
        model = model,
        humanoid = humanoid,
        body = root,        -- kept for anything that still reads guard.body
        root = root,
        head = head,
        waypointA = waypointA,
        waypointB = waypointB,
        nextWaypoint = waypointB,
        alarmActive = false,
        cooldown = 0,
        gen = 0,            -- bumped whenever orders change, cancels the current walk
    }

    -- Touching ANY part of the guard (arms, legs, hat) = caught
    local function onTouched(hit)
        local character = hit:FindFirstAncestorOfClass("Model")
        if not character or character == model then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if guard.cooldown > 0 then return end
        if guard.stunnedUntil and os.clock() < guard.stunnedUntil then return end
        guard.cooldown = 2  -- prevent multi-fire
        callbacks.onPlayerCaught(player, guard)
    end
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then part.Touched:Connect(onTouched) end
    end

    return guard
end

-- ──────────────────────────────────────────────
-- Movement: walk (pathfinding, so guards go AROUND walls instead of through
-- them like the old tweened bricks did). Returns when arrived, when orders
-- change (guard.gen bumped), or after a timeout.
-- ──────────────────────────────────────────────
local function flatDist(a, b)
    return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function walkTo(guard, target, gen, budget)
    local hum, root = guard.humanoid, guard.root
    local points = { target }

    local path = PathfindingService:CreatePath({
        AgentRadius = 2, AgentHeight = 6, AgentCanJump = false,
    })
    local ok = pcall(function() path:ComputeAsync(root.Position, target) end)
    if ok and path.Status == Enum.PathStatus.Success then
        points = {}
        for _, wp in ipairs(path:GetWaypoints()) do table.insert(points, wp.Position) end
    end

    local hardStop = budget and (os.clock() + budget) or math.huge
    for _, point in ipairs(points) do
        if os.clock() > hardStop then return false end
        local deadline = os.clock() + (flatDist(root.Position, point) / math.max(hum.WalkSpeed, 1)) + 3
        local lastIssue = 0
        while flatDist(root.Position, point) > 2 do
            if guard.gen ~= gen or not guards[guard.name] then return false end
            if os.clock() > deadline or os.clock() > hardStop then return false end
            if guard.stunnedUntil and os.clock() < guard.stunnedUntil then return false end
            -- Humanoid:MoveTo silently gives up after 8s, so keep re-issuing it
            if os.clock() - lastIssue > 2 then
                hum:MoveTo(point)
                lastIssue = os.clock()
            end
            task.wait(0.1)
        end
    end
    return true
end

local function nearestPlayer(from, maxDist)
    local best, bestD = nil, maxDist or math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        local char = p.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hum and hrp and hum.Health > 0 and not hum.SeatPart then
            local d = (hrp.Position - from).Magnitude
            if d < bestD then best, bestD = hrp.Position, d end
        end
    end
    return best
end

local function runBrain(guard)
    task.spawn(function()
        while guards[guard.name] do
            local gen = guard.gen
            if guard.stunnedUntil and os.clock() < guard.stunnedUntil then
                task.wait(0.2)
            elseif guard.alarmActive then
                -- v1.0: chase the NEAREST player live (re-plan every ~1s) instead of
                -- walking to one stale "last known position" and standing there.
                guard.humanoid.WalkSpeed = Constants.GUARD_CHASE_SPEED
                local target = nearestPlayer(guard.root.Position, 90) or guard._chaseTarget
                if target then
                    walkTo(guard, target, gen, 1)
                else
                    task.wait(0.3)
                end
            else
                guard.humanoid.WalkSpeed = Constants.GUARD_PATROL_SPEED
                local target = guard.nextWaypoint
                if walkTo(guard, target, gen) then
                    guard.nextWaypoint = (target == guard.waypointA) and guard.waypointB or guard.waypointA
                    -- Pause at the end of each leg, like a real patrol
                    local t = os.clock() + 1.5
                    while os.clock() < t and guard.gen == gen do task.wait(0.1) end
                end
            end
        end
    end)
end

-- ──────────────────────────────────────────────
-- Vision check: cast a ray forward, see if a player is in cone
-- ──────────────────────────────────────────────
local function checkVision(guard)
    if guard.alarmActive then return end  -- already chasing, no need to "spot"
    if guard.stunnedUntil and os.clock() < guard.stunnedUntil then return end

    local headPos = guard.head.Position
    local lookVector = guard.root.CFrame.LookVector

    local closestPlayer = nil
    local closestDist = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        local toPlayer = (hrp.Position - headPos)
        local dist = toPlayer.Magnitude
        if dist > Constants.GUARD_VISION_RANGE then continue end

        -- Cone check: dot(lookVector, normalize(toPlayer)) > cos(FOV/2)
        local normalized = toPlayer.Unit
        local cosAngle = lookVector:Dot(normalized)
        local cosFovHalf = math.cos(math.rad(Constants.GUARD_VISION_FOV_DEGREES / 2))
        if cosAngle < cosFovHalf then continue end

        -- Line of sight: raycast from head to player, ignore guard model
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {guard.model}
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local result = Workspace:Raycast(headPos, toPlayer, rayParams)
        if result and result.Instance:IsDescendantOf(char) then
            -- Saw the player!
            if dist < closestDist then
                closestDist = dist
                closestPlayer = player
            end
        end
    end

    if closestPlayer then
        callbacks.onPlayerSpotted(closestPlayer, guard)
    end
end

-- ──────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────
local guardFolder = nil
local heartbeat = nil

-- Muscle takedown: knocks a guard out for a while if you get him from behind.
local TAKEDOWN_TIME = 10
local function addTakedown(guard)
    local p = Instance.new("ProximityPrompt")
    p.Name = "Takedown"
    p.ActionText = "Takedown"
    p.ObjectText = "Guard"
    p.HoldDuration = 0.6
    p.MaxActivationDistance = 6
    p.RequiresLineOfSight = false
    p:SetAttribute("RoleOnly", "Muscle")
    p.Parent = guard.root
    p.Triggered:Connect(function(player)
        if player:GetAttribute("Role") ~= "Muscle" then return end
        if guard.stunnedUntil and os.clock() < guard.stunnedUntil then return end
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local toPlayer = (hrp.Position - guard.root.Position)
        toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
        local look = guard.root.CFrame.LookVector
        if toPlayer.Magnitude > 0.1 and Vector3.new(look.X, 0, look.Z).Unit:Dot(toPlayer.Unit) > -0.2 and not guard.alarmActive then
            callbacks.onTakedownFailed(player, guard)   -- he saw you coming
            return
        end
        GuardService:stun(guard, TAKEDOWN_TIME)
        callbacks.onTakedown(player, guard)
    end)
end

function GuardService:stun(guard, seconds)
    guard.stunnedUntil = os.clock() + seconds
    guard.gen = guard.gen + 1
    guard.humanoid:MoveTo(guard.root.Position)
    guard.humanoid.PlatformStand = true
    local light = guard.head and guard.head:FindFirstChildOfClass("SpotLight")
    if light then light.Enabled = false end
    task.delay(seconds, function()
        if not guard.model.Parent then return end
        guard.humanoid.PlatformStand = false
        if light then light.Enabled = true end
        -- stand back up where he fell
        guard.root.CFrame = CFrame.new(guard.root.Position + Vector3.new(0, 2, 0))
    end)
end

-- routes: { { name, spawn = Vector3, a = Vector3, b = Vector3 } }
function GuardService:spawnPatrols(cb, routes)
    cb = cb or {}
    callbacks.onPlayerSpotted = cb.onPlayerSpotted or callbacks.onPlayerSpotted
    callbacks.onPlayerCaught = cb.onPlayerCaught or callbacks.onPlayerCaught
    callbacks.onTakedown = cb.onTakedown or callbacks.onTakedown or function() end
    callbacks.onTakedownFailed = cb.onTakedownFailed or callbacks.onTakedownFailed or function() end

    self:despawnAll()
    guardFolder = Instance.new("Folder")
    guardFolder.Name = "Guards"
    guardFolder.Parent = Workspace

    local spawned = 0
    for i, cfg in ipairs(routes or {}) do
        local name = cfg.name or ("Guard_" .. i)
        local model, humanoid, root, head = buildGuardModel(name, cfg.spawn or cfg.a)
        if model then
            model.Parent = guardFolder
            CollectionService:AddTag(model, "Guard")
            -- Server owns the physics so the guard can't be flung/lagged by a client
            pcall(function() root:SetNetworkOwner(nil) end)
            NpcFactory.animate(humanoid)
            local guard = spawnGuard(name, cfg.a, cfg.b, model, humanoid, root, head)
            guards[name] = guard
            addTakedown(guard)
            runBrain(guard)
            spawned = spawned + 1
        else
            warn("[GuardService] could not build", name)
        end
    end

    if not heartbeat then
        heartbeat = RunService.Heartbeat:Connect(function(dt)
            for _, guard in pairs(guards) do
                if guard.cooldown > 0 then
                    guard.cooldown = math.max(0, guard.cooldown - dt)
                end
            end
            self._scanAccumulator = (self._scanAccumulator or 0) + dt
            if self._scanAccumulator > 0.1 then
                self._scanAccumulator = 0
                for _, guard in pairs(guards) do
                    local ok, err = pcall(checkVision, guard)
                    if not ok then warn("[GuardService] vision:", err) end
                end
            end
        end)
    end

    print("[GuardService] Spawned", spawned, "guards")
end

function GuardService:despawnAll()
    for name, guard in pairs(guards) do
        guards[name] = nil
        if guard.model then guard.model:Destroy() end
    end
    if guardFolder then guardFolder:Destroy() guardFolder = nil end
end

function GuardService:getGuards()
    return guards
end

function GuardService:setAlarmActive(active, chaseTarget)
    alarmActive = active
    for _, guard in pairs(guards) do
        guard.alarmActive = active
        guard._chaseTarget = chaseTarget
        guard.gen = guard.gen + 1   -- interrupts whatever walk is in progress
    end
    print(string.format("[GuardService] Alarm %s", active and "ACTIVE 🚨" or "cleared ✅"))
end

function GuardService:reset()
    for _, guard in pairs(guards) do
        guard.stunnedUntil = nil
        guard.humanoid.PlatformStand = false
        local light = guard.head and guard.head:FindFirstChildOfClass("SpotLight")
        if light then light.Enabled = true end
    end
    self:setAlarmActive(false)
end

return GuardService
