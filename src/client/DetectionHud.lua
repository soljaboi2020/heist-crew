--[[
    HEIST CREW — DetectionHud  (v1.1)
    ────────────────────────────────────────────────
    "You're being spotted" — so the alarm is never a surprise.
    Guards (GuardSuspicion / SuspicionFrom) and cameras (CameraSuspicion /
    CameraFrom) fill a meter on YOU before the alarm trips. This shows the
    fuller of the two as:
      • a slim meter just above the crosshair with "SPOTTING…" → "SPOTTED!",
        amber → red as it fills
      • an arrow around the centre of the screen pointing at who's watching
    Break line of sight and it drains away.

    v2.0 (feel agent): under the meter, tiny labels say WHY you're safer right
    now — "sneaking" (Crouching: guards 2x slower), "in the dark" (InShadow:
    1.6x slower), "hidden" (Hidden: guards + cameras can't see you at all).

    v3.2: bigger words, a chunkier meter, and the direction arrow is DRAWN
    (UITheme.chevron) — the "▲" glyph drew as an empty box in BuilderSans.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local DetectionHud = {}
local localPlayer = Players.LocalPlayer

local AMBER = Color3.fromRGB(251, 191, 36)

function DetectionHud:start()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("DetectionHud")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "DetectionHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 4
    screen.Parent = pg

    local card = Instance.new("CanvasGroup")
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.62)   -- (v1.1) below the crosshair, clear of the toast stack
    card.Size = UDim2.fromOffset(300, 78)
    card.BackgroundTransparency = 1
    card.GroupTransparency = 1
    card.Parent = screen
    UITheme.autoScale(card)     -- v2.1: readable on 1440p and phones
    local eye = UITheme.label({ Text = "SPOTTING...", Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 25, TextStrokeTransparency = 0.3, TextStrokeColor3 = Color3.new() })
    eye.Parent = card
    local track = Instance.new("Frame")
    track.Position = UDim2.fromOffset(20, 33)
    track.Size = UDim2.new(1, -40, 0, 12)
    track.BackgroundColor3 = Color3.new(0, 0, 0)
    track.BackgroundTransparency = 0.4
    track.BorderSizePixel = 0
    track.Parent = card
    UITheme.corner(track, 6)
    UITheme.stroke(track, Color3.new(0, 0, 0), 0.4, 1.5)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0, 1)
    fill.BorderSizePixel = 0
    fill.Parent = track
    UITheme.corner(fill, 6)

    -- (v2.0) why you're safer: "sneaking · in the dark" / "hidden"
    local why = UITheme.label({ Name = "Why", Position = UDim2.fromOffset(0, 51), Size = UDim2.new(1, 0, 0, 22),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 18,
        TextColor3 = T.teal, TextStrokeTransparency = 0.6, TextStrokeColor3 = Color3.new(), Text = "" })
    why.Parent = card

    local arrow = UITheme.chevron(34, T.danger, 7)
    arrow.Name = "Arrow"
    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    arrow.Visible = false
    arrow.Parent = screen
    UITheme.autoScale(arrow)

    local shown = 0
    RunService.RenderStepped:Connect(function(dt)
        local g = localPlayer:GetAttribute("GuardSuspicion") or 0
        local c = localPlayer:GetAttribute("CameraSuspicion") or 0
        local v, from = g, localPlayer:GetAttribute("SuspicionFrom")
        if c > g then v, from = c, localPlayer:GetAttribute("CameraFrom") end
        shown = shown + (v - shown) * math.min(1, dt * 12)

        local active = shown > 0.03
        card.GroupTransparency = active and 0 or math.min(1, card.GroupTransparency + dt * 3)
        local col = AMBER:Lerp(T.danger, math.clamp(shown, 0, 1))
        fill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
        fill.BackgroundColor3 = col
        eye.TextColor3 = col
        eye.Text = shown > 0.85 and "SPOTTED!" or (c > g and "CAMERA SEES YOU" or "SPOTTING...")
        if active then
            local reasons = {}
            if localPlayer:GetAttribute("Hidden") then
                table.insert(reasons, "hidden")
            else
                if localPlayer:GetAttribute("Crouching") then table.insert(reasons, "sneaking") end
                if localPlayer:GetAttribute("InShadow") then table.insert(reasons, "in the dark") end
            end
            why.Text = table.concat(reasons, "  ·  ")
        end

        local cam = workspace.CurrentCamera
        if active and cam and typeof(from) == "Vector3" then
            local rel = cam.CFrame:PointToObjectSpace(from)
            local dir = Vector2.new(rel.X, -rel.Y)
            if dir.Magnitude > 1e-3 then
                dir = dir.Unit
                local centre = cam.ViewportSize / 2
                local r = math.min(centre.X, centre.Y) * 0.42
                arrow.Visible = true
                arrow.Position = UDim2.fromOffset(centre.X + dir.X * r, centre.Y + dir.Y * r)
                arrow.Rotation = math.deg(math.atan2(dir.X, -dir.Y))
                UITheme.paintShape(arrow, col, 1 - math.clamp(shown * 1.5, 0.3, 1))
            else
                arrow.Visible = false
            end
        else
            arrow.Visible = false
        end
    end)
    print("[HEIST CREW] DetectionHud mounted ✅")
end

return DetectionHud
