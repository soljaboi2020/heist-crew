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

local function walkTo(guard, target, gen)
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

    for _, point in ipairs(points) do
        local deadline = os.clock() + (flatDist(root.Position, point) / math.max(hum.WalkSpeed, 1)) + 3
        local lastIssue = 0
        while flatDist(root.Position, point) > 2 do
            if guard.gen ~= gen or not guards[guard.name] then return false end
            if os.clock() > deadline then return false end
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

local function runBrain(guard)
    task.spawn(function()
        while guards[guard.name] do
            local gen = guard.gen
            if guard.alarmActive then
                guard.humanoid.WalkSpeed = Constants.GUARD_CHASE_SPEED
                walkTo(guard, guard._chaseTarget or guard.waypointA, gen)
                -- Reached the last-known spot: stand and look around until orders change
                while guard.gen == gen and guards[guard.name] do task.wait(0.2) end
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
function GuardService:spawnPatrols(cb)
    callbacks.onPlayerSpotted = cb.onPlayerSpotted or function() end
    callbacks.onPlayerCaught = cb.onPlayerCaught or function() end

    local W = Constants.WORLD
    local center = Vector3.new(W.MANSION_CENTER.x, W.MANSION_CENTER.y, W.MANSION_CENTER.z)

    -- Two guards patrolling the mansion: one east-west, one diagonal
    local guardConfigs = {
        {
            name = "Guard_Patrol_A",
            spawn = center + Vector3.new(-15, 3, 0),
            waypointA = center + Vector3.new(-20, 3, -10),
            waypointB = center + Vector3.new(20, 3, -10),
        },
        {
            name = "Guard_Patrol_B",
            spawn = center + Vector3.new(15, 3, 8),
            waypointA = center + Vector3.new(20, 3, 8),
            waypointB = center + Vector3.new(-20, 3, 8),
        },
    }

    local guardFolder = Instance.new("Folder")
    guardFolder.Name = "Guards"
    guardFolder.Parent = Workspace

    local spawned = 0
    for _, cfg in ipairs(guardConfigs) do
        local model, humanoid, root, head = buildGuardModel(cfg.name, cfg.spawn)
        if model then
            model.Parent = guardFolder
            -- Server owns the physics so the guard can't be flung/lagged by a client
            pcall(function() root:SetNetworkOwner(nil) end)
            NpcFactory.animate(humanoid)
            local guard = spawnGuard(cfg.name, cfg.waypointA, cfg.waypointB, model, humanoid, root, head)
            guards[cfg.name] = guard
            runBrain(guard)
            spawned = spawned + 1
        else
            warn("[GuardService] could not build", cfg.name)
        end
    end

    -- Heartbeat: tick catch cooldowns + scan vision
    RunService.Heartbeat:Connect(function(dt)
        for _, guard in pairs(guards) do
            if guard.cooldown > 0 then
                guard.cooldown = math.max(0, guard.cooldown - dt)
            end
        end
        -- Vision scan less frequently (every ~0.1s)
        if RunService:IsServer() then
            self._scanAccumulator = (self._scanAccumulator or 0) + dt
            if self._scanAccumulator > 0.1 then
                self._scanAccumulator = 0
                for _, guard in pairs(guards) do
                    checkVision(guard)
                end
            end
        end
    end)

    print("[GuardService] Spawned", spawned, "guards")
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
    self:setAlarmActive(false)
end

return GuardService
