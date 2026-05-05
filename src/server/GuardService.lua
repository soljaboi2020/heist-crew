--[[
    HEIST CREW — GuardService
    ────────────────────────────────────────────────
    Spawns + animates patrolling guards. Each guard:
      1. Tweens between two waypoints on a loop (PATROL state)
      2. Scans for players in a 90° forward cone using raycasts
      3. If a player is spotted: alarm fires + all guards CHASE
      4. If a guard touches a player: heist FAILS

    Guards are NOT real Roblox Humanoids — they're just animated parts.
    This keeps the AI simple and lets us reskin them later (or swap to
    real R15 humanoids when we want to).

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
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local GuardService = {}

local guards = {}             -- list of guard tables
local alarmActive = false
local callbacks = {
    onPlayerSpotted = function() end,
    onPlayerCaught = function() end,
}

-- ──────────────────────────────────────────────
-- Build a single guard model (block-character)
-- ──────────────────────────────────────────────
local function buildGuardModel(name, position)
    local model = Instance.new("Model")
    model.Name = name

    -- Body (the Touched listener attaches here)
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(2.5, 5, 1.5)
    body.Position = position
    body.Anchored = true
    body.TopSurface = Enum.SurfaceType.Smooth
    body.BottomSurface = Enum.SurfaceType.Smooth
    body.Material = Enum.Material.Plastic
    body.Color = Color3.fromRGB(15, 15, 15)
    body.Parent = model

    -- Head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(1.6, 1.6, 1.6)
    head.Anchored = true
    head.CanCollide = false
    head.Material = Enum.Material.Plastic
    head.Color = Color3.fromRGB(220, 180, 140)
    head.Parent = model

    -- Hat (formal — like a security guard cap)
    local hat = Instance.new("Part")
    hat.Name = "Hat"
    hat.Size = Vector3.new(2, 0.7, 2)
    hat.Anchored = true
    hat.CanCollide = false
    hat.Material = Enum.Material.SmoothPlastic
    hat.Color = Color3.fromRGB(15, 15, 15)
    hat.Parent = model

    -- Vision cone (a SpotLight on the head, plus a translucent yellow cone)
    local vision = Instance.new("SpotLight")
    vision.Brightness = 4
    vision.Range = Constants.GUARD_VISION_RANGE
    vision.Angle = Constants.GUARD_VISION_FOV_DEGREES
    vision.Color = Color3.fromRGB(255, 220, 100)
    vision.Face = Enum.NormalId.Front
    vision.Parent = head

    model.PrimaryPart = body
    return model, body, head, hat
end

-- Position the head + hat relative to the body
local function syncGuardParts(guard)
    local bp = guard.body.Position
    guard.head.Position = bp + Vector3.new(0, 3.3, 0)
    guard.hat.Position  = bp + Vector3.new(0, 4.3, 0)
    -- Match orientation (face the same direction the body is facing)
    guard.head.CFrame = CFrame.new(guard.head.Position) * (guard.body.CFrame - guard.body.Position)
    guard.hat.CFrame  = CFrame.new(guard.hat.Position)  * (guard.body.CFrame - guard.body.Position)
end

-- ──────────────────────────────────────────────
-- Spawn a single guard with a patrol path
-- ──────────────────────────────────────────────
local function spawnGuard(name, waypointA, waypointB, body, head, hat, model)
    local guard = {
        name = name,
        model = model,
        body = body,
        head = head,
        hat = hat,
        waypointA = waypointA,
        waypointB = waypointB,
        currentTween = nil,
        alerted = false,
        alarmActive = false,
        cooldown = 0,
    }

    -- Touched listener: if a player walks into the guard, FAIL
    body.Touched:Connect(function(hit)
        local character = hit:FindFirstAncestorOfClass("Model")
        if not character then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        if guard.cooldown > 0 then return end
        guard.cooldown = 2  -- prevent multi-fire
        callbacks.onPlayerCaught(player, guard)
    end)

    return guard
end

-- ──────────────────────────────────────────────
-- Animate a guard's patrol movement
-- ──────────────────────────────────────────────
local function startPatrol(guard)
    if guard.currentTween then guard.currentTween:Cancel() end

    -- Distance / speed → time
    local from = guard.body.Position
    local to = guard.alarmActive and (guard._chaseTarget or guard.waypointA) or guard.waypointB
    if not guard.alarmActive then
        -- Toggle waypoints back and forth
        if (guard.body.Position - guard.waypointA).Magnitude < 3 then
            to = guard.waypointB
        else
            to = guard.waypointA
        end
    end

    local distance = (from - to).Magnitude
    local speed = guard.alarmActive and Constants.GUARD_CHASE_SPEED or Constants.GUARD_PATROL_SPEED
    local duration = math.max(0.5, distance / speed)

    -- Compute facing direction
    local lookCFrame = CFrame.new(from, to)

    local tween = TweenService:Create(guard.body, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
        CFrame = CFrame.new(to) * (lookCFrame - lookCFrame.Position),
    })
    guard.currentTween = tween
    tween:Play()

    tween.Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed and guards[guard.name] then
            -- Tiny pause then start the next leg
            task.wait(0.5)
            startPatrol(guard)
        end
    end)
end

-- ──────────────────────────────────────────────
-- Vision check: cast a ray forward, see if a player is in cone
-- ──────────────────────────────────────────────
local function checkVision(guard)
    if guard.alarmActive then return end  -- already chasing, no need to "spot"

    local headPos = guard.head.Position
    local lookVector = guard.body.CFrame.LookVector

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

    for _, cfg in ipairs(guardConfigs) do
        local model, body, head, hat = buildGuardModel(cfg.name, cfg.spawn)
        model.Parent = guardFolder
        local guard = spawnGuard(cfg.name, cfg.waypointA, cfg.waypointB, body, head, hat, model)
        guards[cfg.name] = guard
        startPatrol(guard)
    end

    -- Heartbeat: scan vision + sync head/hat positions every frame
    RunService.Heartbeat:Connect(function(dt)
        for _, guard in pairs(guards) do
            syncGuardParts(guard)
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

    print("[GuardService] Spawned", #guardConfigs, "guards")
end

function GuardService:setAlarmActive(active, chaseTarget)
    alarmActive = active
    for _, guard in pairs(guards) do
        guard.alarmActive = active
        guard._chaseTarget = chaseTarget
        if guard.currentTween then guard.currentTween:Cancel() end
        startPatrol(guard)
    end
    print(string.format("[GuardService] Alarm %s", active and "ACTIVE 🚨" or "cleared ✅"))
end

function GuardService:reset()
    self:setAlarmActive(false)
end

return GuardService
