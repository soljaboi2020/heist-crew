--[[
    HEIST CREW — TestPad
    ────────────────────────────────────────────────
    Spawns a glowing green pad next to the spawn point. Stepping on it
    pays you +$50 (with a 1-second per-player cooldown so you can't farm
    it by standing still). This is the "first earning loop" — proves the
    full pipeline works end-to-end:

        player touches pad
            ↓
        EconomyService:addCash()
            ↓
        PlayerDataService updates cache
            ↓
        CashUpdated remote fires to client
            ↓
        Client HUD animates the new amount

    Will be deleted in Phase 2 once we have actual heist rooms.

    PUBLIC API:
        TestPad:spawn()  — call once on server startup
--]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local EconomyService = require(script.Parent.EconomyService)

local TestPad = {}

local PAD_PAYOUT = 50
local PAD_COOLDOWN = 1.0
local PAD_POSITION = Vector3.new(20, 0.5, 0)

local cooldowns = {}  -- [userId] = lastTouchTime

function TestPad:spawn()
    -- The glowing pad
    local pad = Instance.new("Part")
    pad.Name = "TestPayoutPad"
    pad.Size = Vector3.new(8, 1, 8)
    pad.Position = PAD_POSITION
    pad.Anchored = true
    pad.Material = Enum.Material.Neon
    pad.Color = Color3.fromRGB(34, 197, 94)
    pad.TopSurface = Enum.SurfaceType.Smooth
    pad.BottomSurface = Enum.SurfaceType.Smooth
    pad.Parent = Workspace

    -- Floating sign above the pad
    local sign = Instance.new("Part")
    sign.Name = "TestPayoutSign"
    sign.Size = Vector3.new(7, 2.5, 0.2)
    sign.Position = PAD_POSITION + Vector3.new(0, 4.5, 0)
    sign.Anchored = true
    sign.CanCollide = false
    sign.Material = Enum.Material.SmoothPlastic
    sign.Color = Color3.fromRGB(15, 23, 42)
    sign.Parent = Workspace

    local gui = Instance.new("SurfaceGui")
    gui.Face = Enum.NormalId.Front
    gui.LightInfluence = 0
    gui.AlwaysOnTop = true
    gui.PixelsPerStud = 50
    gui.Parent = sign

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "STEP HERE\n+$50"
    label.TextColor3 = Color3.fromRGB(34, 197, 94)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBlack
    label.Parent = gui

    -- A subtle point light for ambiance
    local light = Instance.new("PointLight")
    light.Brightness = 2
    light.Range = 14
    light.Color = Color3.fromRGB(34, 197, 94)
    light.Parent = pad

    -- Touch handler
    pad.Touched:Connect(function(hit)
        local character = hit:FindFirstAncestorOfClass("Model")
        if not character then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end

        local now = os.clock()
        local last = cooldowns[player.UserId] or 0
        if now - last < PAD_COOLDOWN then return end
        cooldowns[player.UserId] = now

        EconomyService:addCash(player, PAD_PAYOUT, "TestPad touch")

        -- Visual feedback: flash white briefly
        local originalColor = pad.Color
        pad.Color = Color3.fromRGB(255, 255, 255)
        task.delay(0.15, function()
            pad.Color = originalColor
        end)
    end)

    print(string.format("[TestPad] Spawned at (%.0f, %.0f, %.0f) — pays $%d, %ds cooldown",
        PAD_POSITION.X, PAD_POSITION.Y, PAD_POSITION.Z, PAD_PAYOUT, PAD_COOLDOWN))
end

return TestPad
