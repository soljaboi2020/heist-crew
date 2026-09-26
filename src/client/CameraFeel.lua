--[[
    HEIST CREW — CameraFeel  (v3.3 "FEELS LIKE ROBLOX")
    ────────────────────────────────────────────────
    One place that owns how the normal third-person camera feels.

      • comfortable zoom: min 6 · starts at 11 · max 24 studs (the old
        0.5..128 defaults let you end up inside your own head or way up in
        the sky in a small room).
      • CameraFeel.restoreBehind() — after EVERY scripted camera (IntroCam,
        the Boss briefing, the MASK UP shot, the getaway movie, the drop-in)
        the camera goes back to Custom, BEHIND the character, looking the way
        the character faces, slightly down. Before this the camera kept the
        last scripted angle — after MASK UP it ended up facing the player (and
        often a wall).
      • teleports: when the server moves you far in one step (drop-in, kicked
        back to the door, jail, a vent, back to the club) the camera also snaps
        behind you instead of swinging through walls to catch up.
      • NO Invisicam: ProximityPrompt line-of-sight is checked from the camera,
        so a see-through camera behind a wall hides every prompt (v3.0.1).

    Started by FeelFX:start() (so it runs without touching init.client) and
    safe to :start() twice.

    PUBLIC API
        CameraFeel:start()
        CameraFeel.restoreBehind(opts?)   -- opts.force (default true): also takes the camera
                                          -- back from Scriptable. opts.pitch (deg, default 14)
        CameraFeel.MIN_ZOOM / DEFAULT_ZOOM / MAX_ZOOM
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraFeel = {}
local localPlayer = Players.LocalPlayer

CameraFeel.MIN_ZOOM = 6
CameraFeel.DEFAULT_ZOOM = 11
CameraFeel.MAX_ZOOM = 24
local FOV = 70
local TELEPORT_JUMP = 18      -- studs in one frame = a teleport, not walking / falling
local STEP_NAME = "HC_CameraBehind"

local function charParts()
    local char = localPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

-- anything else holding the camera right now? (then leave it alone)
local function cutsceneRunning()
    return localPlayer:GetAttribute("GetawayPlaying") == true or localPlayer:GetAttribute("IntroPlaying") == true
end

local function behindCFrame(cam, root, pitchDeg)
    local look = root.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 1e-3 then flat = Vector3.new(0, 0, -1) end
    flat = flat.Unit
    local pitch = math.rad(pitchDeg or 14)
    local dir = (flat * math.cos(pitch) - Vector3.new(0, math.sin(pitch), 0)).Unit
    local focus = root.Position + Vector3.new(0, 1.5, 0)
    local dist = CameraFeel.DEFAULT_ZOOM
    pcall(function()
        local d = (cam.CFrame.Position - cam.Focus.Position).Magnitude
        if d > 0.5 and d < CameraFeel.MAX_ZOOM + 2 then dist = math.clamp(d, CameraFeel.MIN_ZOOM, CameraFeel.MAX_ZOOM) end
    end)
    return CFrame.lookAt(focus - dir * dist, focus)
end

local token = nil
function CameraFeel.restoreBehind(opts)
    opts = type(opts) == "table" and opts or {}
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local _, root, hum = charParts()
    local force = opts.force ~= false
    if cam.CameraType == Enum.CameraType.Scriptable then
        if not force then return end
        cam.CameraType = Enum.CameraType.Custom
    end
    if hum and hum.Parent then cam.CameraSubject = hum end
    if math.abs(cam.FieldOfView - FOV) > 0.5 then cam.FieldOfView = FOV end
    if not root then return end
    -- The default camera reads its rotation from camera.CFrame every frame, so
    -- we set it just before the camera script runs, for a few frames (a
    -- CameraType change can reset it once).
    local my = {}
    token = my
    local frames = 0
    local function apply()
        if token ~= my then return false end
        if cam.CameraType ~= Enum.CameraType.Custom then return false end
        local _, r = charParts()
        if not r then return false end
        cam.CFrame = behindCFrame(cam, r, opts.pitch)
        return true
    end
    apply()
    pcall(function() RunService:UnbindFromRenderStep(STEP_NAME) end)
    local ok = pcall(function()
        RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value - 1, function()
            frames += 1
            if not apply() or frames >= 3 then
                pcall(function() RunService:UnbindFromRenderStep(STEP_NAME) end)
            end
        end)
    end)
    if not ok then
        task.spawn(function()
            for _ = 1, 3 do
                RunService.RenderStepped:Wait()
                if not apply() then break end
            end
        end)
    end
end

-- start at a comfortable zoom: pin max to the default for a moment (the
-- camera clamps into range), then open the range back up
local function applyZoomRange(first)
    pcall(function()
        localPlayer.CameraMinZoomDistance = CameraFeel.MIN_ZOOM
        if first then
            localPlayer.CameraMaxZoomDistance = CameraFeel.DEFAULT_ZOOM
            task.delay(0.25, function()
                localPlayer.CameraMaxZoomDistance = CameraFeel.MAX_ZOOM
            end)
        else
            localPlayer.CameraMaxZoomDistance = CameraFeel.MAX_ZOOM
        end
    end)
end

function CameraFeel:start()
    if self._started then return end
    self._started = true
    applyZoomRange(true)

    -- teleport watch: a big jump in one frame → camera behind you
    local lastPos = nil
    local lastRoot = nil
    local snapCooldown = 0
    RunService.Heartbeat:Connect(function()
        local _, root = charParts()
        if not root then lastPos, lastRoot = nil, nil return end
        local pos = root.Position
        if root ~= lastRoot then
            lastRoot, lastPos = root, pos
            return
        end
        local jump = (pos - lastPos).Magnitude
        lastPos = pos
        if jump > TELEPORT_JUMP and os.clock() > snapCooldown then
            snapCooldown = os.clock() + 0.5
            local cam = Workspace.CurrentCamera
            if cam and cam.CameraType == Enum.CameraType.Custom and not cutsceneRunning()
                and localPlayer:GetAttribute("Hidden") ~= true then
                CameraFeel.restoreBehind({ force = false })
            end
        end
    end)
    localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            local cam = Workspace.CurrentCamera
            if cam and cam.CameraType == Enum.CameraType.Custom and not cutsceneRunning() then
                CameraFeel.restoreBehind({ force = false })
            end
        end)
    end)
    print("[HEIST CREW] CameraFeel mounted ✅ (zoom " .. CameraFeel.MIN_ZOOM .. "–" .. CameraFeel.MAX_ZOOM .. ")")
end

return CameraFeel
