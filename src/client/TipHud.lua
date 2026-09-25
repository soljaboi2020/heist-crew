--[[
    HEIST CREW — TipHud  (v1.1)
    ────────────────────────────────────────────────
    First-run coaching from the Boss. Only while the player is a "Rookie"
    (server attribute: hasn't finished a heist yet). Each tip shows ONCE per
    session, at the moment it's useful, in a card on the left side of the
    screen (clear of every other HUD). Dismiss with the ✕ or it fades after
    a while.

    Triggers: joining · first run starting · first time being spotted ·
    first bag · near the car with a bag · first alarm · first time driving ·
    reaching the vault · lasers ahead.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local TipHud = {}
local localPlayer = Players.LocalPlayer

local TIPS = {
    welcome = { "Welcome to The Vault!", "1. Stand on a colored circle to pick your role.  2. Talk to the Boss (press F).  3. Press E at the glowing table when you're ready." },
    start   = { "You're in!", "Follow the markers. Stay out of flashlights and red camera beams, or you'll get caught." },
    spotted = { "Someone sees you!", "Hide! Get out of their sight and the meter goes back down." },
    bag     = { "Heavy bag!", "Bags make you slow. Take it to the car and press E at the trunk. Or press G to throw it to a friend." },
    trunk   = { "Load it up", "Hold E at the back of the car to put the bag in. Bags in the car = money at the end." },
    alarm   = { "The alarm is on!", "Forget the rest! Jump in the car and drive to the marina before time runs out." },
    drive   = { "You're driving", "Use WASD to drive. Follow the marker to the marina. Drivers: press Shift to go super fast." },
    vault   = { "The vault", "Put the drill on the vault and stay close. If it gets stuck, hold E to fix it." },
    lasers  = { "Lasers!", "The red beams blink on and off. Walk through when they're off." },
}

function TipHud:_build()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("TipHud")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "TipHud"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 6
    screen.Parent = pg

    local card = Instance.new("CanvasGroup")
    card.AnchorPoint = Vector2.new(0, 0.5)
    card.Position = UDim2.new(0, 16, 0.5, 0)
    card.Size = UDim2.fromOffset(300, 118)
    card.BackgroundColor3 = T.bg
    card.BackgroundTransparency = 0.12
    card.GroupTransparency = 1
    card.Visible = false
    card.Parent = screen
    UITheme.corner(card, 14)
    UITheme.stroke(card, T.gold, 0.6, 1)
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 4, 1, -24)
    bar.Position = UDim2.fromOffset(12, 12)
    bar.BackgroundColor3 = T.gold
    bar.BorderSizePixel = 0
    bar.Parent = card
    UITheme.caption("The Boss says", { Position = UDim2.fromOffset(26, 12), Size = UDim2.new(1, -60, 0, 14),
        TextColor3 = T.gold }).Parent = card
    local head = UITheme.label({ Position = UDim2.fromOffset(26, 28), Size = UDim2.new(1, -44, 0, 22),
        FontFace = UITheme.F.display, TextSize = 19 })
    head.Parent = card
    local body = UITheme.label({ Position = UDim2.fromOffset(26, 52), Size = UDim2.new(1, -40, 0, 56), TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top, FontFace = UITheme.F.medium, TextSize = 14, TextColor3 = T.muted })
    body.Parent = card
    local close = Instance.new("TextButton")
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -8, 0, 6)
    close.Size = UDim2.fromOffset(26, 26)
    close.BackgroundTransparency = 1
    close.Text = "✕"
    close.TextColor3 = T.muted
    close.FontFace = UITheme.F.bold
    close.TextSize = 15
    close.Parent = card
    close.Activated:Connect(function() self:_hide() end)
    self._u = { card = card, head = head, body = body }
end

function TipHud:_hide()
    local c = self._u.card
    local out = TweenService:Create(c, TweenInfo.new(0.3), { GroupTransparency = 1 })
    out:Play()
    out.Completed:Connect(function() if c.GroupTransparency > 0.95 then c.Visible = false end end)
end

function TipHud:show(key)
    if self._seen[key] then return end
    if not localPlayer:GetAttribute("Rookie") then return end
    local tip = TIPS[key]
    if not tip then return end
    self._seen[key] = true
    local u = self._u
    u.head.Text = tip[1]
    u.body.Text = tip[2]
    u.card.Visible = true
    u.card.GroupTransparency = 1
    u.card.Position = UDim2.new(0, -20, 0.5, 0)
    TweenService:Create(u.card, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { GroupTransparency = 0, Position = UDim2.new(0, 16, 0.5, 0) }):Play()
    local token = {}
    self._token = token
    task.delay(12, function() if self._token == token then self:_hide() end end)
end

function TipHud:start()
    self._seen = {}
    self:_build()

    task.delay(6, function() self:show("welcome") end)

    task.spawn(function()
        local info = Remotes.getRemote(Remotes.NAMES.JobInfo, "RemoteEvent")
        if info then
            info.OnClientEvent:Connect(function(i)
                i = i or {}
                if i.stage == "ACTIVE" then self:show("start") end
                if i.alarm then self:show("alarm") end
                for _, t in ipairs(i.targets or {}) do
                    local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if root and typeof(t.pos) == "Vector3" and (t.pos - root.Position).Magnitude < 18 then
                        if t.kind == "vault" then self:show("vault") end
                        if t.kind == "car" and localPlayer:GetAttribute("CarryingLoot") then self:show("trunk") end
                    end
                end
            end)
        end
    end)

    local function onSusp()
        local v = math.max(localPlayer:GetAttribute("GuardSuspicion") or 0, localPlayer:GetAttribute("CameraSuspicion") or 0)
        if v > 0.25 then self:show("spotted") end
    end
    localPlayer:GetAttributeChangedSignal("GuardSuspicion"):Connect(onSusp)
    localPlayer:GetAttributeChangedSignal("CameraSuspicion"):Connect(onSusp)
    localPlayer:GetAttributeChangedSignal("CarryingLoot"):Connect(function()
        if localPlayer:GetAttribute("CarryingLoot") then self:show("bag") end
    end)

    -- driving + lasers: cheap polling
    task.spawn(function()
        while true do
            task.wait(0.5)
            local char = localPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then self:show("drive") end
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root and not self._seen.lasers then
                -- (fix v1.1) beams are CanQuery=false, so find them by the "Laser" tag
                for _, p in ipairs(game:GetService("CollectionService"):GetTagged("Laser")) do
                    if p:IsA("BasePart") and p.Transparency < 0.5 and (p.Position - root.Position).Magnitude < 14 then
                        self:show("lasers")
                        break
                    end
                end
            end
        end
    end)
    print("[HEIST CREW] TipHud mounted ✅")
end

return TipHud
