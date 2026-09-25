--[[
    HEIST CREW — CrouchController  (v2.0 "BIGGER", feel agent)
    ────────────────────────────────────────────────
    Sneaking, client side.

      • C / LeftCtrl / gamepad ButtonB / on-screen CROUCH button (touch)
        toggles crouch → fires the Crouch remote. The SERVER (FeelService)
        owns the "Crouching" attribute + the slower walk; we only react to it.
      • While crouching: the camera drops (Humanoid.CameraOffset y −1.2) and a
        small "SNEAKING" chip shows bottom-centre.
      • While the "Hidden" attribute is true (HideService): a "HIDDEN" chip.
      • Hide-spot prompts someone else is already in are hidden for you (the
        server marks them with an "Occupant" attribute = that player's UserId).

    PUBLIC API:
        CrouchController:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local CrouchController = {}
local localPlayer = Players.LocalPlayer

local ACTION = "HC_Crouch"
local CAMERA_DROP = Vector3.new(0, -1.2, 0)
local CHIP_Y = -226              -- above LootHud's carrying pill (y −170, 50 tall)
local TOUCH_POS = UDim2.new(0.05, 0, 0.62, 0)

local function tween(obj, t, props)
    local tw = TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function makeChip(parent, name, text, color, order)
    local chip = UITheme.panel({ Name = name, LayoutOrder = order, Size = UDim2.fromOffset(0, 30),
        AutomaticSize = Enum.AutomaticSize.X, radius = 15, Visible = false })
    local s = chip:FindFirstChildOfClass("UIStroke")
    if s then
        s.Color = color
        s.Transparency = 0.45
    end
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 11), UDim.new(0, 13)
    pad.Parent = chip
    local row = Instance.new("UIListLayout")
    row.FillDirection = Enum.FillDirection.Horizontal
    row.VerticalAlignment = Enum.VerticalAlignment.Center
    row.SortOrder = Enum.SortOrder.LayoutOrder
    row.Padding = UDim.new(0, 8)
    row.Parent = chip
    local dot = Instance.new("Frame")
    dot.LayoutOrder = 1
    dot.Size = UDim2.fromOffset(8, 8)
    dot.BackgroundColor3 = color
    dot.BorderSizePixel = 0
    UITheme.corner(dot, 4)
    dot.Parent = chip
    UITheme.label({ LayoutOrder = 2, Text = text, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30),
        FontFace = UITheme.F.bold, TextSize = 13, TextColor3 = T.text }).Parent = chip
    local scale = Instance.new("UIScale")
    scale.Parent = chip
    chip.Parent = parent
    return chip, scale
end

local function showChip(chip, scale, on)
    if on and not chip.Visible then
        chip.Visible = true
        scale.Scale = 0.7
        tween(scale, 0.18, { Scale = 1 })
    elseif not on then
        chip.Visible = false
    end
end

local function styleTouchButton(title)
    pcall(function()
        ContextActionService:SetTitle(ACTION, title)
        ContextActionService:SetPosition(ACTION, TOUCH_POS)
    end)
    local btn = ContextActionService:GetButton(ACTION)
    if not btn or btn:GetAttribute("HCStyled") then return end
    pcall(function()
        btn:SetAttribute("HCStyled", true)
        btn.ImageTransparency = 1
        btn.BackgroundTransparency = 0.2
        btn.BackgroundColor3 = T.bg
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0.5, 0)
        c.Parent = btn
        UITheme.stroke(btn, T.line, 0.7, 1.5)
        local t = btn:FindFirstChild("ActionTitle")
        if t and t:IsA("TextLabel") then
            t.FontFace = UITheme.F.bold
            t.TextColor3 = T.text
            t.TextScaled = false
            t.TextSize = 12
        end
    end)
end

-- Hide-spot prompts: hide the ones someone else is in
local function watchHidePrompt(prompt)
    if not prompt:IsA("ProximityPrompt") or prompt.Name ~= "HidePrompt" then return end
    local function sync()
        local occ = prompt:GetAttribute("Occupant")
        prompt.Enabled = (occ == nil) or (occ == localPlayer.UserId)
    end
    sync()
    prompt:GetAttributeChangedSignal("Occupant"):Connect(sync)
end

local function watchHideSpot(part)
    for _, c in ipairs(part:GetChildren()) do watchHidePrompt(c) end
    part.ChildAdded:Connect(watchHidePrompt)
end

function CrouchController:start()
    local remote = Remotes.getRemote(Remotes.NAMES.Crouch)
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("CrouchHud")
    if old then old:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "CrouchHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.Parent = pg

    local row = Instance.new("Frame")
    row.Name = "Chips"
    row.BackgroundTransparency = 1
    row.AnchorPoint = Vector2.new(0.5, 1)
    row.Position = UDim2.new(0.5, 0, 1, CHIP_Y)
    row.Size = UDim2.fromOffset(300, 30)
    row.Parent = screen
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 8)
    layout.Parent = row

    local sneakChip, sneakScale = makeChip(row, "Sneaking", "SNEAKING", T.info, 1)
    local hiddenChip, hiddenScale = makeChip(row, "Hidden", "HIDDEN", T.money, 2)

    -- ── camera + chips follow the server's attributes ──
    local camTween = nil
    local function applyCamera()
        local char = localPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        local want = localPlayer:GetAttribute("Crouching") and CAMERA_DROP or Vector3.zero
        if camTween then camTween:Cancel() end
        camTween = tween(hum, 0.22, { CameraOffset = want })
    end
    local function refresh()
        local crouching = localPlayer:GetAttribute("Crouching") == true
        local hidden = localPlayer:GetAttribute("Hidden") == true
        showChip(sneakChip, sneakScale, crouching and not hidden)
        showChip(hiddenChip, hiddenScale, hidden)
        if UserInputService.TouchEnabled then styleTouchButton(crouching and "STAND" or "CROUCH") end
        applyCamera()
    end
    localPlayer:GetAttributeChangedSignal("Crouching"):Connect(refresh)
    localPlayer:GetAttributeChangedSignal("Hidden"):Connect(refresh)
    localPlayer.CharacterAdded:Connect(function(char)
        char:WaitForChild("Humanoid", 10)
        refresh()
    end)

    -- ── input ──
    local lastPress = 0
    ContextActionService:BindAction(ACTION, function(_, state)
        if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
        if os.clock() - lastPress < 0.2 then return Enum.ContextActionResult.Sink end
        lastPress = os.clock()
        local char = localPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 or hum.SeatPart then return Enum.ContextActionResult.Pass end
        if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
        if remote then remote:FireServer(not (localPlayer:GetAttribute("Crouching") == true)) end
        return Enum.ContextActionResult.Sink
    end, true, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
    if UserInputService.TouchEnabled then styleTouchButton("CROUCH") end

    -- ── hide-spot prompt filter ──
    for _, part in ipairs(CollectionService:GetTagged("HideSpot")) do watchHideSpot(part) end
    CollectionService:GetInstanceAddedSignal("HideSpot"):Connect(watchHideSpot)

    refresh()
    print("[HEIST CREW] CrouchController mounted ✅")
end

return CrouchController
