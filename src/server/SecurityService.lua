--[[
    HEIST CREW — SecurityService
    ────────────────────────────────────────────────
    v1.0. Runs every security system of the ARMED job (JobRefs, V1_SPEC §4):

      CAMERAS   sweep side to side; a player in the cone with line of sight for
                CAMERA_DETECT_TIME trips the alarm (Signal Jammer gear doubles it).
                Cut them all at the BREAKER (hold 3s; Hacker 1s).
      KEYCARD   spawns at a random keycardSpot each run. Take it (HasKeycard).
                If the holder is caught or leaves, it respawns somewhere else.
      DOORS     keycard doors: "Swipe keycard" (needs HasKeycard) or, for the
                Hacker only, "Hack keypad" (hold 4s, no card needed).
      LASERS    rows blink on/off on a rhythm; touching a lit row trips the alarm.

    Role-specific prompts carry a "RoleOnly" attribute; the client hides them
    for everyone else (CrewHud prompt filter). The server re-checks the role
    anyway — the client only decides what's SHOWN.

    v2.0: cameras never see a player who is Hidden (HideService) or Jailed
    (JailService), and never see bot crewmates (they're not Players, and bot
    models are left out of the line-of-sight ray so they can't block it either).
    Jobs with no cameras / breaker / keycard / lasers (Sunny's Mart has no
    keycard or lasers) are fine: every system just has nothing to run.

    Callbacks (from JobService):
        onEvent(kind, player, data)  -- "keycard", "cameras", "door", "needKeycard"; data = { pos = Vector3 }
        onAlarm(reason, player)
    PUBLIC API:
        SecurityService:init(callbacks, ShopService)
        SecurityService:arm(jobRefs) / :disarm()
        SecurityService:reset()                  -- back to fully armed, new keycard spot
        SecurityService:dropKeycard(player)      -- holder got caught/left
        SecurityService:camerasCut() -> bool
        SecurityService:doorsOpen() -> bool      -- every keycard door open
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local SecurityService = {}
local S = Constants.SECURITY

local cb = { onEvent = function() end, onAlarm = function() end }
local Shop = nil

local refs = nil
local conns = {}
local prompts = {}
local state = {
    camerasCut = false,
    doorOpen = {},        -- [i] = true
    keycardPart = nil,
    seen = {},            -- [player] = { [camIndex] = seconds }
    camBase = {},         -- [camIndex] = CFrame
}

local RED = Color3.fromRGB(255, 45, 70)
local GREEN = Color3.fromRGB(60, 240, 140)
local CYAN = Color3.fromRGB(40, 230, 255)

local function track(c) table.insert(conns, c) return c end

-- v2.0 mask powers (masks agent): optional MaskService lookup, never a hard require
local maskSvc = nil
local function maskHas(player, abilityId)
    if maskSvc == nil then
        local mod = script.Parent:FindFirstChild("MaskService")
        local ok, r = false, nil
        if mod then ok, r = pcall(require, mod) end
        maskSvc = (ok and type(r) == "table" and type(r.has) == "function") and r or false
    end
    if not maskSvc then return false end
    local ok, yes = pcall(maskSvc.has, maskSvc, player, abilityId)
    return ok and yes == true
end

-- v2.0 masks: Cyber "HACK CHIP" finishes a hold prompt in 1/HACK_SPEED of the
-- time, server-side (the client's hold ring keeps going, but the action has
-- already happened). Every action wired through here must be idempotent.
local hackHolds = {}   -- [prompt] = { [player] = token }
local function hackChipFast(p, fn)
    local speed = (Constants.MASK_POWERS or {}).HACK_SPEED or 2
    hackHolds[p] = {}
    track(p.PromptButtonHoldBegan:Connect(function(player)
        if not maskHas(player, "hackchip") then return end
        local token = {}
        hackHolds[p][player] = token
        task.delay(p.HoldDuration / speed, function()
            local holds = hackHolds[p]
            if holds and holds[player] == token and p.Parent then
                holds[player] = nil
                fn(player)
            end
        end)
    end))
    track(p.PromptButtonHoldEnded:Connect(function(player)
        if hackHolds[p] then hackHolds[p][player] = nil end
    end))
end

local function prompt(parent, name, action, object, hold, extra)
    local p = Instance.new("ProximityPrompt")
    p.Name = name
    p.ActionText = action
    p.ObjectText = object or ""
    p.HoldDuration = hold or 0
    p.MaxActivationDistance = 8
    p.RequiresLineOfSight = true   -- (fix v1.1) nothing through walls (breaker from outside, keycard from the garden…)
    p.KeyboardKeyCode = Enum.KeyCode.E
    for k, v in pairs(extra or {}) do p:SetAttribute(k, v) end
    p.Parent = parent
    table.insert(prompts, p)
    return p
end

local function roleOf(player) return player:GetAttribute("Role") end

local function aliveRoot(player)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    if hum.SeatPart then return nil end        -- in the getaway car: not "in the building"
    if player:GetAttribute("Hidden") or player:GetAttribute("Jailed") then return nil end   -- v2.0
    return char:FindFirstChild("HumanoidRootPart"), char
end

-- ── cameras ──────────────────────────────────────────────────────────
local function setCameraLive(cam, live)
    if cam.light then cam.light.Enabled = live end
    if cam.led then
        cam.led.Material = live and Enum.Material.Neon or Enum.Material.SmoothPlastic
        cam.led.Color = live and RED or Color3.fromRGB(40, 40, 44)
    end
end

local function cutCameras(player)
    if state.camerasCut or not refs then return end
    state.camerasCut = true
    for _, cam in ipairs(refs.cameras or {}) do setCameraLive(cam, false) end
    cb.onEvent("cameras", player, { pos = refs.breaker and refs.breaker.Position })
end

local function publishCameraSuspicion()
    -- v1.1: the fullest camera meter on each player → "CameraSuspicion" (0..1)
    for _, player in ipairs(Players:GetPlayers()) do
        local best, from = 0, nil
        if refs and not state.camerasCut then
            for i, v in pairs(state.seen[player] or {}) do
                local frac = math.clamp(v / S.CAMERA_DETECT_TIME, 0, 1)
                if frac > best then
                    best = frac
                    local cam = refs.cameras[i]
                    from = cam and cam.head and cam.head.Position
                end
            end
        end
        local old = player:GetAttribute("CameraSuspicion") or 0
        if math.abs(best - old) > 0.02 or (best == 0 and old ~= 0) then
            player:SetAttribute("CameraSuspicion", best)
        end
        if from and best > 0 then player:SetAttribute("CameraFrom", from) end
    end
end

local camRayParams, camRayBuilt = nil, 0
local function tickCameras(dt)
    if not refs or state.camerasCut then return end
    local t = os.clock()
    -- (perf v1.1) rebuild the raycast filter once a second, not every frame
    if not camRayParams or t - camRayBuilt > 1 then
        camRayParams = RaycastParams.new()
        camRayParams.FilterType = Enum.RaycastFilterType.Exclude
        local exclude = {}
        for _, cam in ipairs(refs.cameras or {}) do table.insert(exclude, cam.model) end
        for _, g in ipairs(CollectionService:GetTagged("Guard")) do table.insert(exclude, g) end
        for _, b in ipairs(CollectionService:GetTagged("BotCrew")) do table.insert(exclude, b) end   -- v2.0
        camRayParams.FilterDescendantsInstances = exclude
        camRayBuilt = t
    end
    local rayParams = camRayParams

    local cosHalf = math.cos(math.rad(S.CAMERA_HALF_ANGLE))
    for i, cam in ipairs(refs.cameras or {}) do
        local base = state.camBase[i]
        if base and cam.head then
            local range = math.rad(cam.yawRange or 70) / 2
            local yaw = math.sin(t * 2 * math.pi / (cam.period or 7)) * range
            cam.head.CFrame = base * CFrame.Angles(0, yaw, 0)
        end
        local head = cam.head
        if head then
            local look = head.CFrame.LookVector
            for _, player in ipairs(Players:GetPlayers()) do
                local hrp, char = aliveRoot(player)
                local seen = state.seen[player] or {}
                state.seen[player] = seen
                local inView = false
                if hrp then
                    local to = hrp.Position - head.Position
                    local dist = to.Magnitude
                    if dist < S.CAMERA_RANGE and dist > 0.1 and look:Dot(to.Unit) > cosHalf then
                        local hit = workspace:Raycast(head.Position, to, rayParams)
                        inView = hit ~= nil and hit.Instance:IsDescendantOf(char)
                    end
                end
                if inView then
                    local rate = (Shop and Shop:hasGear(player, "Jammer")) and 0.5 or 1
                    -- v2.0 masks: Catrina "GHOST" → cameras take 2x longer (stacks with the Jammer)
                    if maskHas(player, "ghost") then rate = rate * ((Constants.MASK_POWERS or {}).GHOST_CAMERA or 0.5) end
                    seen[i] = (seen[i] or 0) + dt * rate
                    if cam.led then cam.led.Color = (math.floor(t * 8) % 2 == 0) and RED or Color3.fromRGB(255, 200, 60) end
                    if seen[i] >= S.CAMERA_DETECT_TIME then
                        seen[i] = 0
                        cb.onAlarm("camera", player)
                    end
                else
                    seen[i] = math.max(0, (seen[i] or 0) - dt * 0.5)
                end
            end
        end
    end
end

-- ── keycard ──────────────────────────────────────────────────────────
local function spawnKeycard()
    if state.keycardPart then state.keycardPart:Destroy() state.keycardPart = nil end
    if not refs or not refs.keycardSpots or #refs.keycardSpots == 0 then return end
    local spot = refs.keycardSpots[math.random(1, #refs.keycardSpots)]

    local card = Instance.new("Part")
    card.Name = "Keycard"
    card.Size = Vector3.new(0.9, 0.06, 0.6)
    card.CFrame = spot * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
    card.Anchored = true
    card.CanCollide = false
    card.Material = Enum.Material.SmoothPlastic
    card.Color = Color3.fromRGB(235, 240, 245)
    local stripe = Instance.new("Part")
    stripe.Name = "Stripe"
    stripe.Size = Vector3.new(0.9, 0.07, 0.14)
    stripe.CFrame = card.CFrame * CFrame.new(0, 0, -0.16)
    stripe.Anchored = true
    stripe.CanCollide = false
    stripe.Material = Enum.Material.Neon
    stripe.Color = CYAN
    stripe.Parent = card
    local glow = Instance.new("PointLight")
    glow.Color = CYAN
    glow.Brightness = 1.2
    glow.Range = 5
    glow.Parent = card
    card.Parent = refs.root

    local p = prompt(card, "TakeKeycard", "Take", "Keycard", 0.4)
    p.MaxActivationDistance = 7
    table.remove(prompts)   -- (fix v1.1) lives and dies with the card; don't grow the list forever
    p.Triggered:Connect(function(player)
        if player:GetAttribute("HasKeycard") then return end
        player:SetAttribute("HasKeycard", true)
        local pos = card.Position
        card:Destroy()
        state.keycardPart = nil
        cb.onEvent("keycard", player, { pos = pos })
    end)
    state.keycardPart = card
end

function SecurityService:dropKeycard(player)
    if player and player:GetAttribute("HasKeycard") then
        player:SetAttribute("HasKeycard", false)
        if not self:doorsOpen() then spawnKeycard() end
    end
end

-- ── doors ────────────────────────────────────────────────────────────
local function setStatus(door, open)
    if door.status then
        door.status.Material = Enum.Material.Neon
        door.status.Color = open and GREEN or RED
    end
end

local function openDoor(i, player)
    if state.doorOpen[i] or not refs then return end
    local door = refs.keycardDoors[i]
    state.doorOpen[i] = true
    door._closed = door._closed or door.door.CFrame
    TweenService:Create(door.door, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { CFrame = door._closed + (door.openOffset or Vector3.new(6, 0, 0)) }):Play()
    door.door.CanCollide = false
    setStatus(door, true)
    for _, p in ipairs(Players:GetPlayers()) do p:SetAttribute("HasKeycard", false) end
    if state.keycardPart then state.keycardPart:Destroy() state.keycardPart = nil end
    cb.onEvent("door", player, { pos = door.door.Position })
end

local function closeDoors()
    for i, door in ipairs(refs and refs.keycardDoors or {}) do
        if door._closed then door.door.CFrame = door._closed end
        door.door.CanCollide = true
        setStatus(door, false)
        state.doorOpen[i] = nil
    end
end

function SecurityService:doorsOpen()
    if not refs or not refs.keycardDoors then return true end
    for i = 1, #refs.keycardDoors do
        if not state.doorOpen[i] then return false end
    end
    return true
end

-- ── lasers ───────────────────────────────────────────────────────────
local laserAcc = 0
local pubAcc = 0
local function tickLasers(dt)
    if not refs or not refs.laserRows then return end
    laserAcc = laserAcc + dt
    if laserAcc < S.LASER_CHECK_RATE then return end
    laserAcc = 0
    local t = os.clock()
    local chars = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then table.insert(chars, p.Character) end
    end
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = chars
    for _, row in ipairs(refs.laserRows) do
        local cycle = (row.onTime or 1.4) + (row.offTime or 1.1)
        local on = ((t + (row.phase or 0)) % cycle) < (row.onTime or 1.4)
        if row._on ~= on then
            row._on = on
            for _, beam in ipairs(row.beams or {}) do beam.Transparency = on and 0 or 1 end
        end
        if on and #chars > 0 and row.zoneCFrame then
            local hits = workspace:GetPartBoundsInBox(row.zoneCFrame, row.zoneSize or Vector3.new(8, 5, 0.6), params)
            for _, part in ipairs(hits) do
                local model = part:FindFirstAncestorOfClass("Model")
                local player = model and Players:GetPlayerFromCharacter(model)
                if player and not player:GetAttribute("Jailed") then
                    cb.onAlarm("laser", player)
                    break
                end
            end
        end
    end
end

-- ── arm / disarm / reset ─────────────────────────────────────────────
function SecurityService:disarm()
    for _, c in ipairs(conns) do c:Disconnect() end
    conns = {}
    for _, p in ipairs(prompts) do if p.Parent then p:Destroy() end end
    prompts = {}
    hackHolds = {}   -- v2.0 masks: pending HACK CHIP holds die with their prompts
    if refs then
        closeDoors()
        for i, cam in ipairs(refs.cameras or {}) do
            if state.camBase[i] and cam.head then cam.head.CFrame = state.camBase[i] end
            setCameraLive(cam, false)
        end
        for _, row in ipairs(refs.laserRows or {}) do
            for _, beam in ipairs(row.beams or {}) do beam.Transparency = 1 end
            row._on = false
        end
    end
    if state.keycardPart then state.keycardPart:Destroy() state.keycardPart = nil end
    for _, p in ipairs(Players:GetPlayers()) do p:SetAttribute("HasKeycard", false) end
    refs = nil
end

function SecurityService:arm(jobRefs)
    self:disarm()
    refs = jobRefs
    state.camBase = {}
    for i, cam in ipairs(refs.cameras or {}) do
        if cam.head then state.camBase[i] = cam.head.CFrame end
        if cam.model then CollectionService:AddTag(cam.model, "SecurityCamera") end
    end
    for _, row in ipairs(refs.laserRows or {}) do
        for _, beam in ipairs(row.beams or {}) do CollectionService:AddTag(beam, "Laser") end
    end

    -- breaker: everyone 3s, Hacker 1s (two prompts, the client shows the right one)
    if refs.breaker then
        local slow = prompt(refs.breaker, "Breaker", "Cut the cameras", "Security panel", S.BREAKER_HOLD, { RoleHide = "Hacker" })
        local fast = prompt(refs.breaker, "BreakerHacker", "Cut the cameras", "Security panel", 1, { RoleOnly = "Hacker" })
        track(slow.Triggered:Connect(function(player) cutCameras(player) end))
        track(fast.Triggered:Connect(function(player)
            if roleOf(player) == "Hacker" then cutCameras(player) end
        end))
        -- v2.0 masks: HACK CHIP halves both breaker holds
        hackChipFast(slow, function(player) cutCameras(player) end)
        hackChipFast(fast, function(player)
            if roleOf(player) == "Hacker" then cutCameras(player) end
        end)
    end

    for i, door in ipairs(refs.keycardDoors or {}) do
        door._closed = door.door.CFrame
        local swipe = prompt(door.panel, "Swipe", "Swipe keycard", "Keypad", 0.3)
        track(swipe.Triggered:Connect(function(player)
            if state.doorOpen[i] then return end
            if player:GetAttribute("HasKeycard") then
                openDoor(i, player)
            else
                cb.onEvent("needKeycard", player)
            end
        end))
        local hack = prompt(door.panel, "HackKeypad", "Hack keypad", "Keypad", S.HACK_DOOR_HOLD, { RoleOnly = "Hacker" })
        -- (fix v1.1) same panel as "Swipe" — give it its own key and let both show,
        -- otherwise Roblox shows only one prompt per key and the Hacker never sees this
        hack.KeyboardKeyCode = Enum.KeyCode.H
        hack.GamepadKeyCode = Enum.KeyCode.ButtonY
        hack.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
        swipe.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
        track(hack.Triggered:Connect(function(player)
            if roleOf(player) == "Hacker" and not state.doorOpen[i] then openDoor(i, player) end
        end))
        -- v2.0 masks: HACK CHIP halves the keypad hack too
        hackChipFast(hack, function(player)
            if roleOf(player) == "Hacker" and not state.doorOpen[i] then openDoor(i, player) end
        end)
    end

    track(RunService.Heartbeat:Connect(function(dt)
        local ok, err = pcall(function()
            tickCameras(dt)
            tickLasers(dt)
            pubAcc = pubAcc + dt
            if pubAcc > 0.1 then
                pubAcc = 0
                publishCameraSuspicion()
            end
        end)
        if not ok then warn("[SecurityService] tick failed:", err) end
    end))
    track(Players.PlayerRemoving:Connect(function(p)
        state.seen[p] = nil
        if p:GetAttribute("HasKeycard") then self:dropKeycard(p) end
    end))

    self:reset()
end

function SecurityService:reset()
    if not refs then return end
    state.camerasCut = false
    state.seen = {}
    for i, cam in ipairs(refs.cameras or {}) do
        setCameraLive(cam, true)
        if state.camBase[i] and cam.head then cam.head.CFrame = state.camBase[i] end
    end
    closeDoors()
    for _, p in ipairs(Players:GetPlayers()) do p:SetAttribute("HasKeycard", false) end
    spawnKeycard()
end

function SecurityService:camerasCut() return state.camerasCut end

-- v2.0: what this job actually has (JobService skips steps a job doesn't have)
function SecurityService:hasCameras() return refs ~= nil and refs.cameras ~= nil and #refs.cameras > 0 end
function SecurityService:hasKeycardDoors() return refs ~= nil and refs.keycardDoors ~= nil and #refs.keycardDoors > 0 end

function SecurityService:init(callbacks, shopService)
    cb.onEvent = callbacks.onEvent or cb.onEvent
    cb.onAlarm = callbacks.onAlarm or cb.onAlarm
    Shop = shopService
end

return SecurityService
