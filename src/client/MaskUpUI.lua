--[[
    HEIST CREW — MaskUpUI  (v3.2 "MASK UP", casing mode — client)
    ────────────────────────────────────────────────
    The client half of MaskUpService (server). While the local player has
    the attribute Casing = true:
      • a small chip under the objective bar:
            🕵 CASING — look around, then MASK UP!   0:47
      • a big pink MASK UP button (bottom right, above the jump button on
        phones). Key: M · gamepad: ButtonL2 · or tap / click it.
        Pressing it fires the "MaskUp" remote ("maskUp"); the server masks
        the WHOLE crew.
    When the server sends { phase = "maskup" } every crew member gets the
    same 1.5 s shot:
        0.00  camera swings round to the face (Scriptable, FOV 70 → 48)
        snap  (0.85) "shhk" + bass hit + white flash + tiny shake — the
              server puts the mask on at the same moment
        1.50  camera back to normal, big title
              MASKS ON — THE JOB IS ON   (+ who / why, e.g. "Malachi grabbed the loot!")
    The camera part is skipped if another cut-scene owns the camera
    (GetawayPlaying) or there's no head to look at; the title still shows.
    { phase = "end" } (run over) hides everything.

    Sounds: built-in rbxasset://sounds only (snap.mp3, bass.wav, swoosh.wav),
    each wrapped in pcall so a failed load never errors.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local UITheme = require(ReplicatedStorage.Shared.UITheme)

local MaskUpUI = {}

local localPlayer = Players.LocalPlayer
local T = UITheme.C
local ACTION = "HC_MaskUp"
local KEYS = { Enum.KeyCode.M, Enum.KeyCode.ButtonL2 }
local SOUNDS = {
    swoosh = "rbxasset://sounds/swoosh.wav",
    snap = "rbxasset://sounds/snap.mp3",
    bass = "rbxasset://sounds/bass.wav",
}

local function playSound(id, volume)
    pcall(function()
        local s = Instance.new("Sound")
        s.SoundId = id
        s.Volume = volume or 0.7
        s.Parent = SoundService
        s:Play()
        task.delay(4, function() if s.Parent then s:Destroy() end end)
    end)
end

-- the remote is created by MaskUpService:init on the server — poll for it
-- (never Remotes.getRemote here: its 10 s wait could give up before a late init)
local function findRemote(self)
    if self._remote and self._remote.Parent then return self._remote end
    local folder = ReplicatedStorage:FindFirstChild("Remotes")
    local r = folder and folder:FindFirstChild("MaskUp")
    if r and r:IsA("RemoteEvent") then self._remote = r end
    return self._remote
end

-- ── build ────────────────────────────────────────────────────────────
function MaskUpUI:_build()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("HC_MaskUp")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "HC_MaskUp"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 6
    screen.Parent = pg

    -- casing chip (under the objective bar)
    local chip = UITheme.card({ Name = "CasingChip", Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = 15, Visible = false, accent = T.pink, radius = 20 })
    UITheme.padding(chip, 14, 0)
    local row = Instance.new("UIListLayout")
    row.FillDirection = Enum.FillDirection.Horizontal
    row.VerticalAlignment = Enum.VerticalAlignment.Center
    row.Padding = UDim.new(0, 10)
    row.SortOrder = Enum.SortOrder.LayoutOrder
    row.Parent = chip
    local badge = UITheme.badge("🕵", T.pink, 28, { LayoutOrder = 1 })
    badge.Parent = chip
    local chipText = UITheme.label({ Name = "Text", Text = "CASING — look around, then MASK UP!", AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 40), FontFace = UITheme.F.bold, TextSize = UITheme.T.body, LayoutOrder = 2 })
    chipText.Parent = chip
    local chipTime = UITheme.label({ Name = "Time", Text = "1:00", AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 40), FontFace = UITheme.F.mono, TextSize = UITheme.T.body, TextColor3 = T.pink, LayoutOrder = 3 })
    chipTime.Parent = chip
    local okSlot, slot = pcall(UITheme.slot, "topCenter")
    if okSlot and slot then
        chip.Parent = slot
    else
        chip.AnchorPoint = Vector2.new(0.5, 0)
        chip.Position = UDim2.new(0.5, 0, 0, 90)
        chip.Parent = screen
    end

    -- the big pink button
    local touch = UITheme.isTouch()
    local holder = Instance.new("Frame")
    holder.Name = "MaskUpHolder"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(230, 84)
    holder.AnchorPoint = Vector2.new(1, 1)
    holder.Position = touch and UDim2.new(1, -24, 1, -210) or UDim2.new(1, -28, 1, -120)
    holder.Visible = false
    holder.Parent = screen
    UITheme.autoScale(holder)
    local btn = UITheme.button("🎭  MASK UP", T.pink, { Name = "MaskUpButton", Size = UDim2.fromScale(1, 1), TextSize = 30 })
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextStrokeTransparency = 0.55
    btn.Parent = holder
    local hint = UITheme.label({ Name = "KeyHint", Text = touch and "" or "[M]", AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 4), Size = UDim2.fromOffset(40, 18), TextXAlignment = Enum.TextXAlignment.Right,
        FontFace = UITheme.F.bold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.2, ZIndex = 3 })
    hint.Parent = btn
    local pulse = Instance.new("UIScale")
    pulse.Parent = btn

    -- white flash + title
    local flash = Instance.new("Frame")
    flash.Name = "Flash"
    flash.Size = UDim2.fromScale(1, 1)
    flash.BackgroundColor3 = Color3.new(1, 1, 1)
    flash.BackgroundTransparency = 1
    flash.BorderSizePixel = 0
    flash.ZIndex = 10
    flash.Parent = screen
    local title = Instance.new("CanvasGroup")
    title.Name = "Title"
    title.AnchorPoint = Vector2.new(0.5, 0.5)
    title.Position = UDim2.fromScale(0.5, 0.38)
    title.Size = UDim2.fromOffset(860, 190)
    title.BackgroundTransparency = 1
    title.GroupTransparency = 1
    title.ZIndex = 11
    title.Parent = screen
    UITheme.autoScale(title)
    local tBig = UITheme.label({ Name = "Big", Text = "MASKS ON", Size = UDim2.new(1, 0, 0, 104), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 100, TextColor3 = T.pink, TextStrokeTransparency = 0.4,
        TextStrokeColor3 = Color3.new(), ZIndex = 12 })
    tBig.Parent = title
    local tSub = UITheme.label({ Name = "Sub", Text = "THE JOB IS ON", Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 34),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 30, TextColor3 = T.text,
        TextStrokeTransparency = 0.5, TextStrokeColor3 = Color3.new(), ZIndex = 12 })
    tSub.Parent = title
    local tWhy = UITheme.label({ Name = "Why", Text = "", Position = UDim2.fromOffset(0, 144), Size = UDim2.new(1, 0, 0, 26),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextSize = 20, TextColor3 = T.gold,
        TextStrokeTransparency = 0.6, TextStrokeColor3 = Color3.new(), ZIndex = 12 })
    tWhy.Parent = title

    self._ui = { screen = screen, chip = chip, chipTime = chipTime, holder = holder, btn = btn, pulse = pulse,
        flash = flash, title = title, tWhy = tWhy }
    btn.Activated:Connect(function() self:_press() end)
end

-- ── casing on / off ──────────────────────────────────────────────────
function MaskUpUI:_press()
    if self._pressed or localPlayer:GetAttribute("Casing") ~= true then return end
    local r = findRemote(self)
    if not r then return end
    self._pressed = true
    self._ui.btn.Text = "🎭  ..."
    pcall(function() r:FireServer("maskUp") end)
    task.delay(2, function()   -- server said no (run over?) → let them try again
        self._pressed = false
        if self._ui then self._ui.btn.Text = "🎭  MASK UP" end
    end)
end

function MaskUpUI:_setCasing(on)
    on = on and not self._masking
    local u = self._ui
    if self._casingOn == on then return end
    self._casingOn = on
    if on then
        -- wait for the drop-in title card to clear before popping the chip + button
        task.delay(2.6, function()
            if self._casingOn then u.chip.Visible = true u.holder.Visible = true end
        end)
    else
        u.chip.Visible = false
        u.holder.Visible = false
    end
    self._pressed = false
    u.btn.Text = "🎭  MASK UP"
    if on then
        ContextActionService:BindAction(ACTION, function(_, inputState)
            if inputState == Enum.UserInputState.Begin then self:_press() end
            return Enum.ContextActionResult.Sink
        end, false, table.unpack(KEYS))
        local token = {}
        self._loop = token
        task.spawn(function()
            local k = 0
            while self._loop == token do
                local endsAt = localPlayer:GetAttribute("CasingEndsAt")
                if type(endsAt) == "number" then
                    local left = math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow()))
                    u.chipTime.Text = string.format("%d:%02d", math.floor(left / 60), left % 60)
                end
                k += 1
                u.pulse.Scale = 1 + 0.05 * math.sin(k * 0.6)
                task.wait(0.1)
            end
        end)
    else
        self._loop = nil
        pcall(function() ContextActionService:UnbindAction(ACTION) end)
    end
end

-- ── the mask-up shot ─────────────────────────────────────────────────
function MaskUpUI:_title(why)
    local u = self._ui
    u.tWhy.Text = why or ""
    u.title.GroupTransparency = 1
    u.title.Size = UDim2.fromOffset(980, 216)
    TweenService:Create(u.title, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { GroupTransparency = 0, Size = UDim2.fromOffset(860, 190) }):Play()
    task.delay(2.4, function()
        TweenService:Create(u.title, TweenInfo.new(0.7), { GroupTransparency = 1 }):Play()
    end)
end

function MaskUpUI:_maskUp(payload)
    local u = self._ui
    self._masking = true
    self:_setCasing(false)
    local snap = tonumber(payload.snap) or 0.85
    local duration = tonumber(payload.duration) or 1.5
    local cam = Workspace.CurrentCamera
    local char = localPlayer.Character
    local head = char and char:FindFirstChild("Head")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local useCam = cam and head and head:IsA("BasePart") and localPlayer:GetAttribute("GetawayPlaying") ~= true
        and cam.CameraType ~= Enum.CameraType.Scriptable
    local fov0 = cam and cam.FieldOfView or 70
    local shot = nil
    if useCam then
        local ok = pcall(function()
            local hcf = head.CFrame
            local look = Vector3.new(hcf.LookVector.X, 0, hcf.LookVector.Z)
            look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
            local eye = head.Position + look * 3.4 + Vector3.new(0, 0.35, 0) + hcf.RightVector * 0.6
            shot = CFrame.lookAt(eye, head.Position + Vector3.new(0, 0.1, 0))
            cam.CameraType = Enum.CameraType.Scriptable
            TweenService:Create(cam, TweenInfo.new(snap * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { CFrame = shot, FieldOfView = 48 }):Play()
        end)
        if not ok then useCam = false end
    end
    playSound(SOUNDS.swoosh, 0.5)

    task.delay(snap, function()
        playSound(SOUNDS.snap, 0.9)
        playSound(SOUNDS.bass, 0.8)
        u.flash.BackgroundTransparency = 0.15
        TweenService:Create(u.flash, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
        if useCam and shot then
            -- tiny shake as the mask clicks on
            task.spawn(function()
                for i = 1, 5 do
                    if cam.CameraType ~= Enum.CameraType.Scriptable then break end
                    local a = (6 - i) * 0.05
                    cam.CFrame = shot * CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
                    task.wait(0.03)
                end
                if cam.CameraType == Enum.CameraType.Scriptable then cam.CFrame = shot end
            end)
        end
    end)

    task.delay(duration, function()
        if useCam and cam.CameraType == Enum.CameraType.Scriptable then
            pcall(function()
                cam.CameraType = Enum.CameraType.Custom
                if hum and hum.Parent then cam.CameraSubject = hum end
                cam.FieldOfView = fov0
            end)
        end
        self._masking = false
        self:_title(payload.text)
    end)
end

function MaskUpUI:_hideAll()
    self._masking = false
    self:_setCasing(false)
end

-- ── start ────────────────────────────────────────────────────────────
function MaskUpUI:start()
    if self._started then return end   -- (v3.2) safe to call twice (init.client + tests)
    self._started = true
    self:_build()
    local function sync() self:_setCasing(localPlayer:GetAttribute("Casing") == true) end
    localPlayer:GetAttributeChangedSignal("Casing"):Connect(sync)
    sync()
    task.spawn(function()
        local r
        while not r do
            r = findRemote(self)
            if not r then task.wait(1) end
        end
        r.OnClientEvent:Connect(function(payload)
            if type(payload) ~= "table" then return end
            if payload.phase == "maskup" then
                self:_maskUp(payload)
            elseif payload.phase == "end" then
                self:_hideAll()
            end
        end)
    end)
    print("[HEIST CREW] MaskUpUI mounted ✅")
end

return MaskUpUI
