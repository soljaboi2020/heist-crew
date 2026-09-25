--[[
    HEIST CREW — PortalHud  (v2.0)
    ────────────────────────────────────────────────
    When YOU are standing in a heist door's glowing floor zone, a panel at the
    bottom-centre says what's going on, in 7-year-old words:

        HEIST DOOR
        ● VILLA ROSA  ·  1 / 2 players  ·  Waiting for 1 more
        ● VILLA ROSA  ·  2 / 2 players  ·  Starting in 4
        ● OCEAN BANK  ·  LOCKED — reach level 5

    Data: the Portal remote (server → client, PortalService)
        { portals = { [jobId] = { count, needed, total, launchAt, locked, selected } } }
          count    players in that zone      needed  players it takes to start a countdown
          total    everyone in the server    launchAt  server time of the drop-in (0/nil = none)
          locked   false | true | level number
    Zones: BaseParts tagged "PortalZone" with attribute JobId (ClubBuilder).

    Sets a LOCAL attribute on the player: InPortal = jobId (or nil) — TipHud,
    CrewHud and WaypointHud read it.

    PUBLIC API: PortalHud:start()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local PortalHud = {}
local localPlayer = Players.LocalPlayer

local FALLBACK_NAME = { mart = "SUNNY'S MART", villa = "VILLA ROSA", jewelry = "DIAMOND DOLLS", bank = "OCEAN BANK" }
local JOB_COLOR = {
    mart = Color3.fromRGB(74, 222, 128), villa = Color3.fromRGB(255, 70, 180),
    jewelry = Color3.fromRGB(40, 230, 255), bank = Color3.fromRGB(251, 191, 36),
}

local function jobName(id)
    for _, j in ipairs(Constants.JOBS or {}) do
        if j.id == id then return j.name end
    end
    return FALLBACK_NAME[id] or string.upper(tostring(id))
end

local function jobLevel(id)
    for _, j in ipairs(Constants.JOBS or {}) do
        if j.id == id then return j.unlockLevel end
    end
    return nil
end

local function inside(zone, pos)
    local rel = zone.CFrame:PointToObjectSpace(pos)
    local h = zone.Size / 2
    return math.abs(rel.X) <= h.X and math.abs(rel.Z) <= h.Z and rel.Y >= -h.Y - 1 and rel.Y <= h.Y + 3
end

function PortalHud:_build()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("PortalHud")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "PortalHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 4
    screen.Parent = pg

    local panel = UITheme.panel({ Name = "Portal", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -118),
        Size = UDim2.fromOffset(0, 66), AutomaticSize = Enum.AutomaticSize.X, radius = 18, transparency = 0.1, Visible = false })
    panel.Parent = screen
    local stroke = panel:FindFirstChildOfClass("UIStroke")
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 20)
    pad.PaddingRight = UDim.new(0, 22)
    pad.Parent = panel
    UITheme.caption("Heist door", { Position = UDim2.fromOffset(0, 9), Size = UDim2.fromOffset(200, 14), TextColor3 = T.gold }).Parent = panel

    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Position = UDim2.fromOffset(0, 24)
    row.Size = UDim2.fromOffset(0, 34)
    row.AutomaticSize = Enum.AutomaticSize.X
    row.Parent = panel
    local list = Instance.new("UIListLayout")
    list.FillDirection = Enum.FillDirection.Horizontal
    list.VerticalAlignment = Enum.VerticalAlignment.Center
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 10)
    list.Parent = row

    local dot = Instance.new("Frame")
    dot.LayoutOrder = 1
    dot.Size = UDim2.fromOffset(12, 12)
    dot.BorderSizePixel = 0
    dot.Parent = row
    UITheme.corner(dot, 6)
    local function lbl(order, props)
        local l = UITheme.label(props)
        l.LayoutOrder = order
        l.AutomaticSize = Enum.AutomaticSize.X
        l.Size = UDim2.fromOffset(0, 34)
        l.Parent = row
        return l
    end
    local name = lbl(2, { FontFace = UITheme.F.display, TextSize = 22 })
    local sep1 = lbl(3, { Text = "·", TextColor3 = T.faint, TextSize = 22 })
    local count = lbl(4, { FontFace = UITheme.F.bold, TextSize = 19 })
    local sep2 = lbl(5, { Text = "·", TextColor3 = T.faint, TextSize = 22 })
    local status = lbl(6, { FontFace = UITheme.F.display, TextSize = 21 })

    self._u = { panel = panel, stroke = stroke, dot = dot, name = name, sep1 = sep1, count = count, sep2 = sep2, status = status }
end

function PortalHud:_render(jobId)
    local u = self._u
    local d = self._state[jobId] or {}
    local col = JOB_COLOR[jobId] or T.gold
    u.dot.BackgroundColor3 = col
    u.name.Text = jobName(jobId)
    u.name.TextColor3 = col
    u.stroke.Color = col
    u.stroke.Transparency = 0.5

    local n = math.max(0, math.floor(tonumber(d.count) or 0))
    local need = tonumber(d.needed)
    local now = workspace:GetServerTimeNow()
    local left = (tonumber(d.launchAt) or 0) > 0 and math.ceil(d.launchAt - now) or 0

    if d.locked then
        local lvl = (type(d.locked) == "number") and d.locked or jobLevel(jobId) or 2
        u.count.Visible, u.sep1.Visible = false, false
        u.status.Text = string.format("LOCKED — reach level %d", lvl)
        u.status.TextColor3 = T.danger
        return
    end
    u.count.Visible, u.sep1.Visible = true, true
    if need and need > 0 then
        u.count.Text = string.format("%d / %d player%s", n, need, need == 1 and "" or "s")
    else
        u.count.Text = string.format("%d player%s here", n, n == 1 and "" or "s")
    end
    if left > 0 then
        u.status.Text = string.format("Starting in %d", left)
        u.status.TextColor3 = T.money
    elseif need and n < need then
        local more = need - n
        u.status.Text = string.format("Waiting for %d more", more)
        u.status.TextColor3 = T.muted
    elseif self._state[jobId] == nil then
        u.status.Text = "Stay here…"
        u.status.TextColor3 = T.muted
    else
        u.status.Text = "Get ready…"
        u.status.TextColor3 = T.gold
    end
end

function PortalHud:_show(on)
    local u = self._u
    if on == self._shown then return end
    self._shown = on
    if on then
        u.panel.Visible = true
        u.panel.Position = UDim2.new(0.5, 0, 1, -104)
        TweenService:Create(u.panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 1, -118) }):Play()
    else
        u.panel.Visible = false
    end
end

function PortalHud:start()
    self._state = {}
    self._shown = false
    self:_build()

    local zones = {}
    local function addZone(z)
        if z:IsA("BasePart") then zones[z] = true end
    end
    for _, z in ipairs(CollectionService:GetTagged("PortalZone")) do addZone(z) end
    CollectionService:GetInstanceAddedSignal("PortalZone"):Connect(addZone)
    CollectionService:GetInstanceRemovedSignal("PortalZone"):Connect(function(z) zones[z] = nil end)

    task.spawn(function()
        local remote = Remotes.getRemote(Remotes.NAMES.Portal, "RemoteEvent")
        if remote then
            remote.OnClientEvent:Connect(function(payload)
                if type(payload) == "table" and type(payload.portals) == "table" then
                    self._state = payload.portals
                end
            end)
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.1)
            local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
            local here
            if root then
                for z in pairs(zones) do
                    if z.Parent and inside(z, root.Position) then
                        here = z:GetAttribute("JobId")
                        break
                    end
                end
            end
            if localPlayer:GetAttribute("InPortal") ~= here then localPlayer:SetAttribute("InPortal", here) end
            if here then
                self:_render(here)
                self:_show(true)
            else
                self:_show(false)
            end
        end
    end)
    print("[HEIST CREW] PortalHud mounted ✅")
end

return PortalHud
