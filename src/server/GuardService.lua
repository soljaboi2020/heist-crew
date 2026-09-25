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

    v2.0 (feel agent) — sneaking (docs/V2_SPEC.md §2):
      • player attribute Hidden   → guards can't see you, won't chase/path to
                                    you, and can't catch you by touch
      • player attribute Crouching → a guard's meter fills 2x slower
      • player attribute InShadow  → 1.6x slower (stacks with crouch: 3.2x)
      • Jailed players are ignored too.
      • A guard whose meter on you passes NOTICE_AT stops walking, turns to look
        at you and says "Huh?"; when he fully spots you he shouts "HEY!"
        (short NPC speech bubble — the allowed floating-text exception).
    GuardService.stealthFactor(player) -> (hidden:boolean, fillMultiplier:number)
--]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local NpcFactory = require(script.Parent.NpcFactory)
local Debris = game:GetService("Debris")

local GuardService = {}

local guards = {}             -- list of guard tables
local alarmActive = false
local callbacks = {
    onPlayerSpotted = function() end,
    onPlayerCaught = function() end,
}

-- ── v2.0 sneaking ──────────────────────────────────────────────
local CROUCH_MULT = 2      -- fill time x2 while crouching
local SHADOW_MULT = 1.6    -- fill time x1.6 in a ShadowZone (stacks)
local NOTICE_AT   = 0.4    -- meter level where a guard stops and turns to look
local HIDDEN_KEEP_OUT = 6  -- guards never walk to a point this close to a hidden player

-- Returns (cannotBeSeen, fillTimeMultiplier)
function GuardService.stealthFactor(player)
    if player:GetAttribute("Hidden") or player:GetAttribute("Jailed") then return true, math.huge end
    local m = 1
    if player:GetAttribute("Crouching") then m = m * CROUCH_MULT end
    if player:GetAttribute("InShadow") then m = m * SHADOW_MULT end
    return false, m
end

local function isHidden(player)
    return player:GetAttribute("Hidden") == true or player:GetAttribute("Jailed") == true
end

-- true if `pos` is right on top of a hidden player (don't walk into his closet)
local function nearHidden(pos)
    if typeof(pos) ~= "Vector3" then return false end
    for _, p in ipairs(Players:GetPlayers()) do
        if isHidden(p) then
            local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - pos).Magnitude < HIDDEN_KEEP_OUT then return true end
        end
    end
    return false
end

-- Short speech bubble over a guard's head ("Huh?" / "HEY!"), gone in ~1.5 s
local function say(guard, text, color)
    local head = guard.head
    if not head or not head.Parent then return end
    local old = head:FindFirstChild("SpeechBubble")
    if old then old:Destroy() end
    local bb = Instance.new("BillboardGui")
    bb.Name = "SpeechBubble"
    bb.Size = UDim2.fromOffset(84, 34)
    bb.StudsOffset = Vector3.new(0, 2.4, 0)
    bb.AlwaysOnTop = false
    bb.MaxDistance = 80
    bb.LightInfluence = 0
    local panel = UITheme.panel({ Size = UDim2.fromScale(1, 1), radius = 17, transparency = 0.1 })
    panel.Parent = bb
    local l = UITheme.label({ Text = text, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 20, TextColor3 = color or UITheme.C.text })
    l.Parent = panel
    bb.Parent = head
    Debris:AddItem(bb, 1.5)
end

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
        local hum = character:FindFirstChildOfClass("Humanoid")
        if hum and hum.SeatPart then return end   -- (fix v1.1) in the car = the police's job
        if isHidden(player) then return end        -- (v2.0) hidden in a closet / jailed
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
            -- (v2.0) he noticed someone: stand still and look (checkVision turns him)
            if guard.lookUntil and os.clock() < guard.lookUntil and not guard.alarmActive then
                hum:MoveTo(root.Position)
                lastIssue = 0
                deadline = deadline + 0.1
                task.wait(0.1)
                continue
            end
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
        -- (fix v1.1) never chase into the safehouse — it's home base
        local sh = Constants.WORLD.SAFEHOUSE_CENTER
        local inSafehouse = hrp and math.abs(hrp.Position.X - sh.x) < Constants.WORLD.SAFEHOUSE_HALF_WIDTH + 1
            and math.abs(hrp.Position.Z - sh.z) < Constants.WORLD.SAFEHOUSE_HALF_DEPTH + 1
        if hum and hrp and hum.Health > 0 and not hum.SeatPart and not inSafehouse and not isHidden(p) then
            local d = (hrp.Position - from).Magnitude
            if d < bestD then best, bestD = hrp.Position, d end
        end
    end
    return best
end

local function runBrain(guard)
    task.spawn(function()
        while guards[guard.name] == guard do   -- (fix v1.1) a respawned guard with the same name ends the old loop
            local gen = guard.gen
            if guard.stunnedUntil and os.clock() < guard.stunnedUntil then
                task.wait(0.2)
            elseif guard.alarmActive then
                -- v1.0: chase the NEAREST player live (re-plan every ~1s) instead of
                -- walking to one stale "last known position" and standing there.
                guard.humanoid.WalkSpeed = Constants.GUARD_CHASE_SPEED
                local target = nearestPlayer(guard.root.Position, 90) or guard._chaseTarget
                if target and nearHidden(target) then target = nil end   -- (v2.0) never into a hiding spot
                if target then
                    walkTo(guard, target, gen, 1)
                    task.wait(0.1)   -- (v2.0 fix) already standing on the target: walkTo returns at once — don't spin
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
-- v1.1: seeing a player fills that guard's meter for them instead of an
-- instant alarm. Up close it fills in GUARD_NEAR_TIME, at the edge of vision in
-- GUARD_FAR_TIME. Out of sight it drains. Full meter = spotted (alarm).
-- The highest meter on each player is mirrored to the player attributes
-- "GuardSuspicion" (0..1) and "SuspicionFrom" (Vector3) for the HUD.
local D = Constants.DETECTION
local frameMax = {}   -- [player] = { value, from }  rebuilt every scan

local function checkVision(guard, dt)
    guard.sus = guard.sus or {}
    local stunned = (guard.stunnedUntil and os.clock() < guard.stunnedUntil)
        or os.clock() < (GuardService.graceUntil or 0)   -- (v1.2.4) drop-in grace
    local headPos = guard.head.Position
    local lookVector = guard.root.CFrame.LookVector
    local cosFovHalf = math.cos(math.rad(Constants.GUARD_VISION_FOV_DEGREES / 2))
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { guard.model }
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local watchPos, watchV = nil, 0
    for _, player in ipairs(Players:GetPlayers()) do
        local seen = false
        local dist = math.huge
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local cantSee, mult = GuardService.stealthFactor(player)
        if hrp and hum and hum.Health > 0 and not hum.SeatPart and not stunned and not guard.alarmActive and not cantSee then
            local toPlayer = hrp.Position - headPos
            dist = toPlayer.Magnitude
            if dist <= Constants.GUARD_VISION_RANGE and dist > 0.1 and lookVector:Dot(toPlayer.Unit) >= cosFovHalf then
                local result = Workspace:Raycast(headPos, toPlayer, rayParams)
                seen = result ~= nil and result.Instance:IsDescendantOf(char)
            end
        end
        local v = guard.sus[player] or 0
        if seen then
            local t = math.clamp(dist / Constants.GUARD_VISION_RANGE, 0, 1)
            local fillTime = (D.GUARD_NEAR_TIME + (D.GUARD_FAR_TIME - D.GUARD_NEAR_TIME) * t) * mult
            v = v + dt / fillTime
        else
            v = v - dt * D.DECAY
        end
        v = math.clamp(v, 0, 1)
        local before = guard.sus[player] or 0
        guard.sus[player] = v
        if seen and v >= NOTICE_AT then
            if v > watchV then watchPos, watchV = hrp.Position, v end
            if before < NOTICE_AT then say(guard, "Huh?", UITheme.C.gold) end
        end
        if v >= 1 then
            guard.sus[player] = 0
            say(guard, "HEY!", UITheme.C.danger)
            callbacks.onPlayerSpotted(player, guard)
        end
        local cur = frameMax[player]
        if v > 0 and (not cur or v > cur.value) then
            frameMax[player] = { value = v, from = headPos }
        end
    end

    -- (v2.0) he noticed someone: stop and turn toward them (the brain's walk
    -- pauses while lookUntil is in the future)
    if watchPos and not guard.alarmActive and not stunned then
        guard.lookUntil = os.clock() + 0.8
        local rp = guard.root.Position
        local flat = Vector3.new(watchPos.X, rp.Y, watchPos.Z)
        if (flat - rp).Magnitude > 0.5 then
            guard.root.CFrame = guard.root.CFrame:Lerp(CFrame.lookAt(rp, flat), 0.35)
        end
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
                local step = self._scanAccumulator
                self._scanAccumulator = 0
                frameMax = {}
                for _, guard in pairs(guards) do
                    local ok, err = pcall(checkVision, guard, step)
                    if not ok then warn("[GuardService] vision:", err) end
                end
                for _, p in ipairs(Players:GetPlayers()) do
                    local m = frameMax[p]
                    local v = m and m.value or 0
                    local old = p:GetAttribute("GuardSuspicion") or 0
                    if math.abs(v - old) > 0.02 or (v == 0 and old ~= 0) then
                        p:SetAttribute("GuardSuspicion", v)
                    end
                    if m then p:SetAttribute("SuspicionFrom", m.from) end
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
        guard.lookUntil = nil
        guard.sus = {}
        guard.humanoid.PlatformStand = false
        local light = guard.head and guard.head:FindFirstChildOfClass("SpotLight")
        if light then light.Enabled = true end
    end
    self:setAlarmActive(false)
end

return GuardService
