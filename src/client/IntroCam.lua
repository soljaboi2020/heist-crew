--[[
    HEIST CREW — IntroCam  (v2.0)
    ────────────────────────────────────────────────
    First-join fly-over. The server fires the IntroCam remote with
    { points = { CFrame, ... } } (ClubBuilder refs.introPath: the street and the
    auto-shop sign → down the freight lift → the club → the heist doors → the
    spawn). We glide the camera through them in ~8 s with a "HEIST CREW" title
    card and "Press any key to skip", then ease back behind your character.

      • Plays ONCE per join (a second fire is ignored).
      • Smooth: Catmull-Rom through the positions, eased rotations.
      • A segment that goes from street level down into The Vault dips to
        black (the camera would otherwise fly through the shop floor).
      • The auto-shop garage door is hidden locally while we fly through it.
      • Other HUDs are hidden during the fly-over and restored after.
      • Local attributes on the player (client-side only, other HUDs read them):
          IntroPlaying = true while it runs · IntroCamDone = true after.
        (DailyRewardUI waits for IntroCamDone before its card may pop up.)

    PUBLIC API: IntroCam:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local IntroCam = {}
local localPlayer = Players.LocalPlayer

local TOTAL = 8          -- seconds for the whole fly-over
local BLEND = 1.2        -- of which: the last glide back behind your character
local GROUND_Y = -1.5    -- above this = the street, below = The Vault

local function smooth(u) return u * u * (3 - 2 * u) end

local function catmull(p0, p1, p2, p3, u)
    local u2, u3 = u * u, u * u * u
    return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (-p0 + 3 * p1 - 3 * p2 + p3) * u3)
end

function IntroCam:_build()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("IntroCam")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "IntroCam"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 40
    screen.Enabled = false
    screen.Parent = pg

    local bars = {}
    for i, anchor in ipairs({ 0, 1 }) do
        local b = Instance.new("Frame")
        b.BackgroundColor3 = Color3.new(0, 0, 0)
        b.BorderSizePixel = 0
        b.AnchorPoint = Vector2.new(0, anchor)
        b.Position = UDim2.fromScale(0, anchor)
        b.Size = UDim2.new(1, 0, 0.09, 0)
        b.Parent = screen
        bars[i] = b
    end

    local black = Instance.new("Frame")
    black.Name = "Black"
    black.Size = UDim2.fromScale(1, 1)
    black.BackgroundColor3 = Color3.new(0, 0, 0)
    black.BackgroundTransparency = 1
    black.BorderSizePixel = 0
    black.ZIndex = 5
    black.Parent = screen

    -- title: plain Frame + labels (not a CanvasGroup: fades are done per label)
    local title = UITheme.label({ Text = "HEIST CREW", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4),
        Size = UDim2.new(1, 0, 0, 100), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextSize = 96, TextTransparency = 1, TextStrokeTransparency = 1, TextStrokeColor3 = Color3.new(), ZIndex = 6 })
    title.Parent = screen
    UITheme.autoScale(title)     -- v2.1: title reads the same on 1080p, 1440p and phones
    local sub = UITheme.label({ Text = "WELCOME TO THE VAULT", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.4, 66 * UITheme.scale()),
        Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
        TextSize = 22, TextColor3 = T.gold, TextTransparency = 1, TextStrokeTransparency = 1, TextStrokeColor3 = Color3.new(), ZIndex = 6 })
    sub.Parent = screen
    UITheme.autoScale(sub)

    local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local skip = UITheme.label({ Text = touch and "Tap to skip" or "Press any key to skip", AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -24, 1, -16), Size = UDim2.fromOffset(260, 22), TextXAlignment = Enum.TextXAlignment.Right,
        FontFace = UITheme.F.bold, TextSize = 16, TextColor3 = T.muted, ZIndex = 6 })
    skip.Parent = screen
    UITheme.autoScale(skip)

    self._u = { screen = screen, bars = bars, black = black, title = title, sub = sub, skip = skip }
end

-- the garage door slats of the auto shop: hidden locally while the camera flies through
local function garageSlats()
    local list = {}
    local world = workspace:FindFirstChild("HeistWorld")
    local door = world and world:FindFirstChild("GarageDoor", true)
    if door then
        for _, d in ipairs(door:GetDescendants()) do
            if d:IsA("BasePart") then table.insert(list, { part = d, t = d.Transparency }) end
        end
    end
    return list
end

function IntroCam:play(points)
    local u = self._u
    local cam = workspace.CurrentCamera
    local pts = {}
    for _, p in ipairs(points or {}) do
        if typeof(p) == "CFrame" then table.insert(pts, p) end
    end
    if #pts < 2 or not cam then return end

    -- wait (briefly) for our character so we can land behind it
    local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:FindFirstChildOfClass("Humanoid")

    localPlayer:SetAttribute("IntroPlaying", true)
    -- CrewHud's own join title card would double up with ours
    local crew = localPlayer.PlayerGui:FindFirstChild("CrewHud")
    local tc = crew and crew:FindFirstChild("TitleCard")
    if tc then tc:Destroy() end
    -- hide the other HUDs for the fly-over (restored after — only the ones WE hid)
    local hidden = {}
    self._hidden = hidden
    for _, g in ipairs(localPlayer.PlayerGui:GetChildren()) do
        if g:IsA("ScreenGui") and g ~= u.screen and g.Enabled then
            g.Enabled = false
            table.insert(hidden, g)
        end
    end
    local slats = garageSlats()
    for _, s in ipairs(slats) do s.part.Transparency = 1 end

    local oldType = cam.CameraType
    cam.CameraType = Enum.CameraType.Scriptable
    u.screen.Enabled = true
    u.black.BackgroundTransparency = 0
    TweenService:Create(u.black, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()

    -- segment timing: proportional to sqrt(length), over TOTAL - BLEND
    local lens, sum = {}, 0
    for i = 1, #pts - 1 do
        lens[i] = math.sqrt((pts[i + 1].Position - pts[i].Position).Magnitude + 1)
        sum = sum + lens[i]
    end
    local fly = TOTAL - BLEND
    local starts, t = {}, 0
    for i = 1, #pts - 1 do
        starts[i] = t
        lens[i] = lens[i] / sum * fly
        t = t + lens[i]
    end

    local skipped = false
    local inputConn = UserInputService.InputBegan:Connect(function(input)
        local ty = input.UserInputType
        if ty == Enum.UserInputType.Keyboard or ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch
            or ty.Name:sub(1, 7) == "Gamepad" then
            skipped = true
        end
    end)

    local function titleAlpha(el)
        -- fade in 0.4..1.2 s, hold, fade out 5.8..6.8 s
        if el < 0.4 then return 1 end
        if el < 1.2 then return 1 - (el - 0.4) / 0.8 end
        if el < 5.8 then return 0 end
        if el < 6.8 then return (el - 5.8) / 1.0 end
        return 1
    end

    local blendFrom
    local t0 = os.clock()
    local done = false
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if done then return end
        local el = os.clock() - t0
        local ta = titleAlpha(el)
        u.title.TextTransparency = ta
        u.title.TextStrokeTransparency = 0.6 + 0.4 * ta
        u.sub.TextTransparency = ta
        u.sub.TextStrokeTransparency = 0.6 + 0.4 * ta

        if el < fly then
            local i = #pts - 1
            for k = 1, #pts - 1 do
                if el < starts[k] + lens[k] then i = k break end
            end
            local lu = math.clamp((el - starts[i]) / lens[i], 0, 1)
            local p0 = pts[math.max(1, i - 1)].Position
            local p1, p2 = pts[i].Position, pts[i + 1].Position
            local p3 = pts[math.min(#pts, i + 2)].Position
            local pos = catmull(p0, p1, p2, p3, lu)
            local rot = pts[i].Rotation:Lerp(pts[i + 1].Rotation, smooth(lu))
            cam.CFrame = CFrame.new(pos) * rot
            -- street → Vault (or back): dip to black through the floor
            local crossing = (p1.Y > GROUND_Y) ~= (p2.Y > GROUND_Y)
            if crossing then
                local d = math.abs(lu - 0.5)
                u.black.BackgroundTransparency = math.clamp((d - 0.18) / 0.2, 0, 1)
            elseif el > 0.6 then
                u.black.BackgroundTransparency = 1
            end
        else
            -- glide back to where the normal camera will sit (behind + above you)
            blendFrom = blendFrom or cam.CFrame
            local bu = smooth(math.clamp((el - fly) / BLEND, 0, 1))
            if root and root.Parent then
                local look = root.CFrame.LookVector
                local target = root.Position + Vector3.new(0, 1.5, 0)
                local camPos = target - Vector3.new(look.X, 0, look.Z).Unit * 11 + Vector3.new(0, 4.5, 0)
                cam.CFrame = blendFrom:Lerp(CFrame.lookAt(camPos, target), bu)
            end
            u.black.BackgroundTransparency = 1
            if bu >= 1 then done = true end
        end
        if skipped then done = true end
    end)

    while not done do task.wait() end
    conn:Disconnect()
    inputConn:Disconnect()

    if skipped then
        u.black.BackgroundTransparency = 0
    end
    cam.CameraType = (oldType == Enum.CameraType.Scriptable) and Enum.CameraType.Custom or oldType
    if hum and hum.Parent then cam.CameraSubject = hum end
    for _, s in ipairs(slats) do
        if s.part.Parent then s.part.Transparency = s.t end
    end
    for _, g in ipairs(hidden) do
        if g.Parent then g.Enabled = true end
    end
    u.title.TextTransparency = 1
    u.sub.TextTransparency = 1
    u.title.TextStrokeTransparency = 1
    u.sub.TextStrokeTransparency = 1
    u.skip.Visible = false
    for _, b in ipairs(u.bars) do
        TweenService:Create(b, TweenInfo.new(0.4), { Size = UDim2.new(1, 0, 0, 0) }):Play()
    end
    local out = TweenService:Create(u.black, TweenInfo.new(skipped and 0.5 or 0.2), { BackgroundTransparency = 1 })
    out:Play()
    out.Completed:Wait()
    u.screen.Enabled = false
end

function IntroCam:start()
    self:_build()
    local played = false
    task.spawn(function()
        local remote = Remotes.getRemote(Remotes.NAMES.IntroCam, "RemoteEvent")
        if not remote then return end
        remote.OnClientEvent:Connect(function(payload)
            if played then return end
            played = true
            task.spawn(function()
                local ok, err = pcall(function() self:play(payload and payload.points) end)
                if not ok then
                    warn("[HEIST CREW] IntroCam failed: " .. tostring(err))
                    -- never leave the player stuck on a scripted camera
                    local cam = workspace.CurrentCamera
                    if cam and cam.CameraType == Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Custom end
                    for _, g in ipairs(self._hidden or {}) do
                        if g.Parent then g.Enabled = true end
                    end
                    if self._u then self._u.screen.Enabled = false end
                end
                localPlayer:SetAttribute("IntroPlaying", false)
                localPlayer:SetAttribute("IntroCamDone", true)
            end)
        end)
    end)
    print("[HEIST CREW] IntroCam mounted ✅")
end

return IntroCam
