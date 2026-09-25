--[[
    HEIST CREW — WaypointHud  (v1.1)
    ────────────────────────────────────────────────
    On-screen markers for "where do I go next" — the fix for "it's confusing".
    The server puts the next goals in JobInfo.targets ({pos, label, kind});
    this draws each as a small pill with a diamond + label + distance.
    Off-screen targets stick to the screen edge with an arrow pointing at them.

    Personal filter: if YOU are carrying a bag, only CAR (and MARINA) show —
    that's the only thing you need right then.

    kinds → colour:  boss/ready gold · search/door/vault cyan · loot green ·
                     car pink · marina cyan · optional dimmed
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local WaypointHud = {}
local localPlayer = Players.LocalPlayer

local COLORS = {
    boss = T.gold, ready = T.gold,
    search = T.info, door = T.info, vault = T.info, marina = T.info,
    loot = T.money, car = Color3.fromRGB(244, 114, 182), optional = T.muted,
}
local MAX = 8
local EDGE = 60

local function makeMarker(parent)
    local m = Instance.new("Frame")
    m.AnchorPoint = Vector2.new(0.5, 1)
    m.Size = UDim2.fromOffset(0, 26)
    m.AutomaticSize = Enum.AutomaticSize.X
    m.BackgroundColor3 = T.bg
    m.BackgroundTransparency = 0.25
    m.BorderSizePixel = 0
    m.Visible = false
    m.Parent = parent
    UITheme.corner(m, 13)
    local stroke = UITheme.stroke(m, T.line, 0.7, 1)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = m
    local row = Instance.new("UIListLayout")
    row.FillDirection = Enum.FillDirection.Horizontal
    row.VerticalAlignment = Enum.VerticalAlignment.Center
    row.Padding = UDim.new(0, 6)
    row.SortOrder = Enum.SortOrder.LayoutOrder
    row.Parent = m
    local dia = Instance.new("Frame")
    dia.LayoutOrder = 1
    dia.Size = UDim2.fromOffset(9, 9)
    dia.Rotation = 45
    dia.BorderSizePixel = 0
    dia.Parent = m
    local label = UITheme.label({ LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26),
        FontFace = UITheme.F.bold, TextSize = 13 })
    label.Parent = m
    local dist = UITheme.label({ LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26),
        FontFace = UITheme.F.mono, TextSize = 12, TextColor3 = T.muted })
    dist.Parent = m
    local arrow = UITheme.label({ Text = "▲", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(20, 20),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextSize = 18, Visible = false })
    arrow.Parent = parent
    return { frame = m, dia = dia, label = label, dist = dist, stroke = stroke, arrow = arrow }
end

function WaypointHud:start()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("WaypointHud")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "WaypointHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = -1          -- under every other HUD
    screen.Parent = pg

    local markers = {}
    for i = 1, MAX do markers[i] = makeMarker(screen) end
    local targets = {}

    task.spawn(function()
        local remote = Remotes.getRemote(Remotes.NAMES.JobInfo, "RemoteEvent")
        if remote then
            remote.OnClientEvent:Connect(function(info)
                targets = (info and info.targets) or {}
            end)
        end
    end)

    RunService.RenderStepped:Connect(function()
        local cam = workspace.CurrentCamera
        local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not cam or not root then
            for _, m in ipairs(markers) do m.frame.Visible = false m.arrow.Visible = false end
            return
        end
        local vp = cam.ViewportSize
        local list = targets
        if localPlayer:GetAttribute("CarryingLoot") then
            list = {}
            for _, t in ipairs(targets) do
                if t.kind == "car" or t.kind == "marina" then table.insert(list, t) end
            end
        end
        -- the car HUD shows its own drop-off arrow; hide the car marker while seated
        local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
        local seated = hum and hum.SeatPart ~= nil

        for i, m in ipairs(markers) do
            local t = list[i]
            if not t or typeof(t.pos) ~= "Vector3" or (seated and t.kind == "car") then
                m.frame.Visible = false
                m.arrow.Visible = false
            else
                local col = COLORS[t.kind] or T.text
                local d = (t.pos - root.Position).Magnitude
                m.dia.BackgroundColor3 = col
                m.label.Text = t.label or ""
                m.label.TextColor3 = (t.kind == "optional") and T.muted or T.text
                m.dist.Text = string.format("%dm", math.floor(d * 0.28 + 0.5))
                m.stroke.Color = col
                m.frame.BackgroundTransparency = (t.kind == "optional") and 0.5 or 0.25
                -- fade out when you're basically on top of it
                m.frame.Visible = d > 6

                local sp, onScreen = cam:WorldToViewportPoint(t.pos)
                if onScreen and sp.Z > 0 then
                    m.frame.Position = UDim2.fromOffset(sp.X, sp.Y)
                    m.arrow.Visible = false
                else
                    -- clamp to the screen edge, pointing toward the target
                    local centre = vp / 2
                    local rel = cam.CFrame:PointToObjectSpace(t.pos)
                    local dir = Vector2.new(rel.X, -rel.Y)
                    -- (fix v1.1) no flip: rel is already in camera space, flipping mirrored
                    -- things behind you onto the wrong side of the screen
                    if dir.Magnitude < 1e-3 then dir = Vector2.new(0, 1) end
                    dir = dir.Unit
                    local sx = (centre.X - EDGE) / math.max(math.abs(dir.X), 1e-3)
                    local sy = (centre.Y - EDGE) / math.max(math.abs(dir.Y), 1e-3)
                    local pos = centre + dir * math.min(sx, sy)
                    m.frame.Position = UDim2.fromOffset(pos.X, pos.Y - 14)
                    m.arrow.Visible = m.frame.Visible
                    m.arrow.Position = UDim2.fromOffset(pos.X + dir.X * 26, pos.Y + dir.Y * 26)
                    m.arrow.Rotation = math.deg(math.atan2(dir.X, -dir.Y))
                    m.arrow.TextColor3 = col
                end
            end
        end
    end)
    print("[HEIST CREW] WaypointHud mounted ✅")
end

return WaypointHud
