--[[
    HEIST CREW — PortalHud  (v2.0)
    ────────────────────────────────────────────────
    When YOU are standing in a heist door's glowing floor zone, a card in the
    UITheme bottomCenter slot (door icon in the heist's colour) says what's
    going on, in 7-year-old words:

        HEIST DOOR
        ● VILLA ROSA  ·  1 / 2 players  ·  Waiting for 1 more
        ● VILLA ROSA  ·  2 / 2 players  ·  Starting in 4
        ● OCEAN BANK  ·  LOCKED — reach level 5

    Data: the Portal remote (server → client, PortalService)
        { portals = { [jobId] = { count, needed, total, launchAt, locked, selected } } }
          count    players in that zone      needed  players it takes to start a countdown
          total    everyone in the server    launchAt  server time of the drop-in (0/nil = none)
          locked   false | true | level number
    v3.2: the card glows in the heist's colour, bigger words, no "…" glyphs.

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
    jewelry = Color3.fromRGB(45, 212, 191), bank = Color3.fromRGB(252, 196, 45),
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
    -- (v2.1) a chunky card in the UITheme bottomCenter slot
    local panel = UITheme.card({ Name = "Portal", LayoutOrder = 40, Size = UDim2.fromOffset(0, 82),
        AutomaticSize = Enum.AutomaticSize.X, radius = 22, Visible = false })
    panel.Parent = UITheme.slot("bottomCenter")
    local stroke = panel:FindFirstChild("Stroke")
    local minW = Instance.new("UISizeConstraint")
    minW.MinSize = Vector2.new(340, 82)
    minW.Parent = panel
    local scale = Instance.new("UIScale")
    scale.Parent = panel
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 24)
    pad.Parent = panel
    local outer = Instance.new("UIListLayout")
    outer.FillDirection = Enum.FillDirection.Horizontal
    outer.VerticalAlignment = Enum.VerticalAlignment.Center
    outer.SortOrder = Enum.SortOrder.LayoutOrder
    outer.Padding = UDim.new(0, 14)
    outer.Parent = panel
    local badge = UITheme.badge(UITheme.ICON.door, T.gold, 58, { LayoutOrder = 1 })
    badge.Parent = panel

    local col = Instance.new("Frame")
    col.LayoutOrder = 2
    col.BackgroundTransparency = 1
    col.Size = UDim2.fromOffset(0, 64)
    col.AutomaticSize = Enum.AutomaticSize.X
    col.Parent = panel
    local cl = Instance.new("UIListLayout")
    cl.SortOrder = Enum.SortOrder.LayoutOrder
    cl.VerticalAlignment = Enum.VerticalAlignment.Center
    cl.Parent = col
    UITheme.caption("Heist door", { LayoutOrder = 1, Size = UDim2.fromOffset(200, 18), TextSize = 15,
        TextColor3 = T.gold }).Parent = col

    local row = Instance.new("Frame")
    row.LayoutOrder = 2
    row.BackgroundTransparency = 1
    row.Size = UDim2.fromOffset(0, 36)
    row.AutomaticSize = Enum.AutomaticSize.X
    row.Parent = col
    local list = Instance.new("UIListLayout")
    list.FillDirection = Enum.FillDirection.Horizontal
    list.VerticalAlignment = Enum.VerticalAlignment.Center
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 10)
    list.Parent = row

    local function lbl(order, props)
        local l = UITheme.label(props)
        l.LayoutOrder = order
        l.AutomaticSize = Enum.AutomaticSize.X
        l.Size = UDim2.fromOffset(0, 36)
        l.Parent = row
        return l
    end
    local name = lbl(2, { FontFace = UITheme.F.display, TextSize = 28 })
    local sep1 = lbl(3, { Text = "·", TextColor3 = T.faint, TextSize = 28 })
    local count = lbl(4, { FontFace = UITheme.F.display, TextSize = 22 })
    local sep2 = lbl(5, { Text = "·", TextColor3 = T.faint, TextSize = 28 })
    local status = lbl(6, { FontFace = UITheme.F.display, TextSize = 24 })

    self._u = { panel = panel, stroke = stroke, badge = badge, scale = scale, name = name, sep1 = sep1, count = count,
        sep2 = sep2, status = status }
end

function PortalHud:_render(jobId)
    local u = self._u
    local d = self._state[jobId] or {}
    local col = JOB_COLOR[jobId] or T.gold
    UITheme.setBadge(u.badge, UITheme.ICON.door, col)
    u.name.Text = jobName(jobId)
    u.name.TextColor3 = col
    if u.stroke then
        u.stroke.Color = col
        u.stroke.Transparency = 0.1
    end
    if self._tinted ~= jobId then
        self._tinted = jobId
        UITheme.tint(u.panel, col, 0.4)
    end

    local n = math.max(0, math.floor(tonumber(d.count) or 0))
    local need = tonumber(d.needed)
    local now = workspace:GetServerTimeNow()
    local left = (tonumber(d.launchAt) or 0) > 0 and math.ceil(d.launchAt - now) or 0

    if d.locked then
        u.count.Visible, u.sep1.Visible = false, false
        -- (v2.0.1) true = a heist is running; a number = level lock
        local need = tonumber(d.starsNeeded) or 0   -- v3.2: star-locked doors
        u.status.Text = (need > 0) and string.format("🔒 Need ⭐ %d", need) or "Heist in progress!"
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
        u.status.Text = "Stay here!"
        u.status.TextColor3 = T.muted
    else
        u.status.Text = "Get ready!"
        u.status.TextColor3 = T.gold
    end
end

function PortalHud:_show(on)
    local u = self._u
    if on == self._shown then return end
    self._shown = on
    if on then
        u.panel.Visible = true
        u.scale.Scale = 0.85
        TweenService:Create(u.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
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
