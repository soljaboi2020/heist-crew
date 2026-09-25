--[[
    HEIST CREW — CarHud
    ────────────────────────────────────────────────
    v1.0 "Neon Miami" (2026-09-25). The dashboard you see while you're in
    the getaway car (driver or passenger). Hidden the rest of the time.

      • SPEED   big number, "Speed" model attribute (studs/s) x 1.3 → MPH
      • MARINA  small arrow + distance to the drop-off, relative to the camera
      • BUST    thin red meter, only while the car's "BustMeter" > 0
      • NITRO   Driver role in the driver seat only: "SHIFT  NITRO" chip with
                a cooldown fill (NitroUntil / NitroReadyAt vs server time).
                LeftShift / ButtonL3 / on-screen touch button → Nitro remote.
      • CAR     (v2.2) top-right: the car type + its power ("MONSTER TRUCK ·
                +20% SPEED"), from the model's CarName / CarPerk attributes.
                The nitro cooldown fill follows the model's NitroCooldown
                (Muscle Car: 7 s).

    Also mirrors the driver's throttle/steer to the server on the "CarInput"
    remote (VehicleService prefers it over the replicated VehicleSeat values
    when it is fresh — belt and braces, since nobody could playtest this).

    PUBLIC API:
        CarHud:start()
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local CarHud = {}
local localPlayer = Players.LocalPlayer

local NITRO_ACTION = "HeistCrewNitro"
local CAR_INPUT_REMOTE = "CarInput"
local MPH_PER_STUD = 1.3
local METERS_PER_STUD = 0.28
local DEFAULT_NITRO_COOLDOWN = 12
local W = Constants.WORLD
local DROPOFF = Vector3.new(W.DROPOFF.x, W.DROPOFF.y, W.DROPOFF.z)

-- Non-yielding remote lookup (Remotes.getRemote waits up to 10s on the client)
local function findRemote(name)
    local f = ReplicatedStorage:FindFirstChild("Remotes")
    local r = f and f:FindFirstChild(name)
    if r and r:IsA("RemoteEvent") then return r end
    return nil
end

local function num(x)
    local n = tonumber(x)
    if n == nil or n ~= n then return 0 end
    return n
end

-- The getaway car model a seat belongs to, or nil
local function carModelFor(seat)
    if not seat then return nil end
    local node = seat.Parent
    while node and node ~= Workspace do
        if node:IsA("Model") and (CollectionService:HasTag(node, "GetawayCar") or node.Name == "GetawayCar") then
            return node
        end
        node = node.Parent
    end
    if seat.Name == "GetawayDriverSeat" then
        return seat:FindFirstAncestorOfClass("Model")
    end
    return nil
end

-- ──────────────────────────────────────────────
-- UI
-- ──────────────────────────────────────────────
function CarHud:_buildUi()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("CarHud")
    if existing then existing:Destroy() end

    -- (v2.1) the dashboard is a card in the UITheme bottomCenter slot (hidden until you sit in the car)
    local panel = UITheme.card({
        Name = "CarPanel", LayoutOrder = 50, Size = UDim2.fromOffset(340, 122), radius = 18, Visible = false,
    })
    panel.Parent = UITheme.slot("bottomCenter")

    -- ── drop-off navigation row ──
    local boat = UITheme.badge(UITheme.ICON.marina, T.info, 30)
    boat.Position = UDim2.fromOffset(12, 8)
    boat.Parent = panel
    local arrow = UITheme.label({
        Name = "Arrow", Text = "▲", Position = UDim2.fromOffset(48, 10), Size = UDim2.fromOffset(26, 26),
        TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = T.info, TextSize = 20,
    })
    arrow.Parent = panel
    UITheme.caption("Marina", { Position = UDim2.fromOffset(80, 8), Size = UDim2.fromOffset(120, 14) }).Parent = panel
    local distLabel = UITheme.label({
        Name = "Distance", Text = "--", Position = UDim2.fromOffset(80, 21), Size = UDim2.fromOffset(140, 18),
        FontFace = UITheme.F.display, TextSize = 16, TextColor3 = T.text,
    })
    distLabel.Parent = panel

    -- ── (v2.2) car type + power ──
    local carName = UITheme.label({
        Name = "CarName", Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8),
        Size = UDim2.fromOffset(125, 16), TextXAlignment = Enum.TextXAlignment.Right,
        FontFace = UITheme.F.display, TextSize = 14, TextColor3 = T.gold,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    carName.Parent = panel
    local carPerk = UITheme.label({
        Name = "CarPerk", Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 25),
        Size = UDim2.fromOffset(125, 14), TextXAlignment = Enum.TextXAlignment.Right,
        FontFace = UITheme.F.bold, TextSize = 12, TextColor3 = T.muted,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    carPerk.Parent = panel

    -- ── speed ──
    local speed = UITheme.label({
        Name = "Speed", Text = "0", Position = UDim2.fromOffset(10, 40), Size = UDim2.fromOffset(112, 52),
        FontFace = UITheme.F.display, TextSize = 52, TextXAlignment = Enum.TextXAlignment.Right,
    })
    speed.Parent = panel
    UITheme.caption("mph", { Position = UDim2.fromOffset(128, 72), Size = UDim2.fromOffset(40, 14) }).Parent = panel

    -- ── nitro chip (Driver only) ──
    local chip = Instance.new("Frame")
    chip.Name = "NitroChip"
    chip.AnchorPoint = Vector2.new(1, 0)
    chip.Position = UDim2.new(1, -14, 0, 52)
    chip.Size = UDim2.fromOffset(130, 34)
    chip.BackgroundColor3 = T.bgRaised
    chip.BackgroundTransparency = 0.1
    chip.BorderSizePixel = 0
    chip.ClipsDescendants = true
    chip.Visible = false
    chip.Parent = panel
    UITheme.corner(chip, 8)
    local chipStroke = UITheme.stroke(chip, T.gold, 0.55)
    local chipFill = Instance.new("Frame")
    chipFill.Name = "Fill"
    chipFill.Size = UDim2.fromScale(1, 1)
    chipFill.BackgroundColor3 = T.gold
    chipFill.BackgroundTransparency = 0.72
    chipFill.BorderSizePixel = 0
    chipFill.Parent = chip
    UITheme.corner(chipFill, 8)
    local chipLabel = UITheme.label({
        Name = "Label", Text = "SHIFT  NITRO", Size = UDim2.fromScale(1, 1),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 15, TextColor3 = T.gold, ZIndex = 2,
    })
    chipLabel.Parent = chip

    -- ── bust meter ──
    local bustRow = Instance.new("Frame")
    bustRow.Name = "Bust"
    bustRow.BackgroundTransparency = 1
    bustRow.Position = UDim2.fromOffset(14, 98)
    bustRow.Size = UDim2.new(1, -28, 0, 16)
    bustRow.Visible = false
    bustRow.Parent = panel
    UITheme.caption("Bust", {
        Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(40, 14), TextColor3 = T.danger,
    }).Parent = bustRow
    local bustTrack = Instance.new("Frame")
    bustTrack.Name = "Track"
    bustTrack.Position = UDim2.new(0, 42, 0.5, -3)
    bustTrack.Size = UDim2.new(1, -42, 0, 6)
    bustTrack.BackgroundColor3 = T.faint
    bustTrack.BackgroundTransparency = 0.4
    bustTrack.BorderSizePixel = 0
    bustTrack.Parent = bustRow
    UITheme.corner(bustTrack, 3)
    local bustFill = Instance.new("Frame")
    bustFill.Name = "Fill"
    bustFill.Size = UDim2.fromScale(0, 1)
    bustFill.BackgroundColor3 = T.danger
    bustFill.BorderSizePixel = 0
    bustFill.Parent = bustTrack
    UITheme.corner(bustFill, 3)

    self.ui = {
        panel = panel, arrow = arrow, dist = distLabel, speed = speed,
        chip = chip, chipStroke = chipStroke, chipFill = chipFill, chipLabel = chipLabel,
        bustRow = bustRow, bustFill = bustFill,
        carName = carName, carPerk = carPerk,
    }
end

-- ──────────────────────────────────────────────
-- Nitro binding
-- ──────────────────────────────────────────────
function CarHud:_fireNitro()
    if os.clock() - (self._lastNitro or 0) < 0.3 then return end
    self._lastNitro = os.clock()
    local r = findRemote(Remotes.NAMES.Nitro)
    if r then r:FireServer() end
end

function CarHud:_refreshNitroBinding()
    local want = self.isDriverSeat == true and localPlayer:GetAttribute("Role") == "Driver"
    if want and not self.nitroBound then
        ContextActionService:BindActionAtPriority(NITRO_ACTION, function(_, state)
            if state == Enum.UserInputState.Begin then self:_fireNitro() end
            return Enum.ContextActionResult.Sink
        end, true, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
        pcall(function() ContextActionService:SetTitle(NITRO_ACTION, "NITRO") end)
        self.nitroBound = true
    elseif not want and self.nitroBound then
        ContextActionService:UnbindAction(NITRO_ACTION)
        self.nitroBound = false
    end
    if self.ui then
        self.ui.chip.Visible = want
        self.ui.chipLabel.Text = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
            and "NITRO" or "SHIFT  NITRO"
    end
end

-- ──────────────────────────────────────────────
-- Seat tracking
-- ──────────────────────────────────────────────
function CarHud:_onSeat(seat)
    local car = carModelFor(seat)
    if car then
        self.seat = seat
        self.car = car
        self.isDriverSeat = seat:IsA("VehicleSeat") and seat.Name == "GetawayDriverSeat"
        if self.ui then self.ui.panel.Visible = true end
    else
        self.seat = nil
        self.car = nil
        self.isDriverSeat = false
        if self.ui then self.ui.panel.Visible = false end
        self:_sendInput(0, 0, true)
    end
    self:_refreshNitroBinding()
end

function CarHud:_bindCharacter(character)
    if self._seatConn then
        self._seatConn:Disconnect()
        self._seatConn = nil
    end
    self:_onSeat(nil)
    if not character then return end
    task.spawn(function()
        local hum = character:WaitForChild("Humanoid", 10)
        if not hum or not hum:IsA("Humanoid") or localPlayer.Character ~= character then return end
        self._seatConn = hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
            self:_onSeat(hum.SeatPart)
        end)
        self:_onSeat(hum.SeatPart)
    end)
end

-- ──────────────────────────────────────────────
-- Driver input mirror (see header)
-- ──────────────────────────────────────────────
function CarHud:_sendInput(throttle, steer, force)
    local last = self._lastInput
    local now = os.clock()
    local changed = not last or last.t ~= throttle or last.s ~= steer
    if not force then
        if changed and last and now - last.at < 0.05 then return end
        if not changed and last and now - last.at < 0.2 then return end
    elseif last and last.t == 0 and last.s == 0 then
        return   -- already told the server we stopped
    end
    local r = findRemote(CAR_INPUT_REMOTE)
    if not r then return end
    r:FireServer(throttle, steer)
    self._lastInput = { t = throttle, s = steer, at = now }
end

local function keyAxis(pos, neg, pos2, neg2)
    local v = 0
    if UserInputService:IsKeyDown(pos) or UserInputService:IsKeyDown(pos2) then v = v + 1 end
    if UserInputService:IsKeyDown(neg) or UserInputService:IsKeyDown(neg2) then v = v - 1 end
    return v
end

function CarHud:_pollDriverInput()
    local seat = self.seat
    if not seat or not seat:IsA("VehicleSeat") then return end
    local throttle = num(seat.ThrottleFloat)
    local steer = num(seat.SteerFloat)
    -- if the stock vehicle controller isn't feeding the seat, read the keys ourselves
    if throttle == 0 and steer == 0 and not UserInputService:GetFocusedTextBox() then
        throttle = keyAxis(Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.Up, Enum.KeyCode.Down)
        steer = keyAxis(Enum.KeyCode.D, Enum.KeyCode.A, Enum.KeyCode.Right, Enum.KeyCode.Left)
    end
    self:_sendInput(math.clamp(throttle, -1, 1), math.clamp(steer, -1, 1), false)
end

-- ──────────────────────────────────────────────
-- Per-frame update
-- ──────────────────────────────────────────────
function CarHud:_update()
    local ui = self.ui
    if not ui then return end
    local car = self.car
    if not car or not car.Parent then
        if ui.panel.Visible then
            self.car = nil
            ui.panel.Visible = false
        end
        return
    end

    if self.isDriverSeat then self:_pollDriverInput() end

    -- speed
    local speed = math.abs(num(car:GetAttribute("Speed")))
    ui.speed.Text = tostring(math.floor(speed * MPH_PER_STUD + 0.5))

    -- drop-off arrow + distance (relative to where the camera looks)
    local ok, pivot = pcall(function() return car:GetPivot() end)
    local here = ok and pivot.Position or DROPOFF
    local toDrop = Vector3.new(DROPOFF.X - here.X, 0, DROPOFF.Z - here.Z)
    local dist = toDrop.Magnitude
    ui.dist.Text = string.format("%d m", math.floor(dist * METERS_PER_STUD + 0.5))
    local cam = Workspace.CurrentCamera
    if cam and dist > 0.5 then
        local look = cam.CFrame.LookVector
        local flatLook = Vector3.new(look.X, 0, look.Z)
        if flatLook.Magnitude > 1e-3 then
            flatLook = flatLook.Unit
            local right = Vector3.new(-flatLook.Z, 0, flatLook.X)
            local dir = toDrop.Unit
            ui.arrow.Rotation = math.deg(math.atan2(dir:Dot(right), dir:Dot(flatLook)))
        end
    end
    ui.arrow.TextColor3 = dist <= W.DROPOFF_RADIUS and T.money or T.info

    -- (v2.2) car type
    local cn = car:GetAttribute("CarName")
    local cp = car:GetAttribute("CarPerk")
    ui.carName.Text = type(cn) == "string" and string.upper(cn) or ""
    ui.carPerk.Text = type(cp) == "string" and cp or ""

    -- bust meter
    local bust = math.clamp(num(car:GetAttribute("BustMeter")), 0, 1)
    ui.bustRow.Visible = bust > 0.001
    ui.bustFill.Size = UDim2.fromScale(bust, 1)

    -- nitro chip
    if ui.chip.Visible then
        local now = Workspace:GetServerTimeNow()
        local untilT = num(car:GetAttribute("NitroUntil"))
        local readyAt = num(car:GetAttribute("NitroReadyAt"))
        local cooldown = num(car:GetAttribute("NitroCooldown"))
        if cooldown <= 0 then cooldown = DEFAULT_NITRO_COOLDOWN end
        if now < untilT then
            ui.chipFill.Size = UDim2.fromScale(1, 1)
            ui.chipFill.BackgroundColor3 = T.info
            ui.chipFill.BackgroundTransparency = 0.45
            ui.chipLabel.TextColor3 = T.text
            ui.chipStroke.Color = T.info
        elseif now < readyAt then
            local frac = math.clamp(1 - (readyAt - now) / cooldown, 0, 1)
            ui.chipFill.Size = UDim2.fromScale(frac, 1)
            ui.chipFill.BackgroundColor3 = T.muted
            ui.chipFill.BackgroundTransparency = 0.7
            ui.chipLabel.TextColor3 = T.muted
            ui.chipStroke.Color = T.faint
        else
            ui.chipFill.Size = UDim2.fromScale(1, 1)
            ui.chipFill.BackgroundColor3 = T.gold
            ui.chipFill.BackgroundTransparency = 0.72
            ui.chipLabel.TextColor3 = T.gold
            ui.chipStroke.Color = T.gold
        end
    end
end

-- ──────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────
function CarHud:start()
    if self._started then return end
    self._started = true
    self:_buildUi()

    localPlayer.CharacterAdded:Connect(function(character)
        self:_bindCharacter(character)
    end)
    localPlayer.CharacterRemoving:Connect(function()
        self:_onSeat(nil)
    end)
    localPlayer:GetAttributeChangedSignal("Role"):Connect(function()
        self:_refreshNitroBinding()
    end)
    if localPlayer.Character then
        self:_bindCharacter(localPlayer.Character)
    end

    RunService.RenderStepped:Connect(function()
        local ok, err = pcall(function() self:_update() end)
        if not ok and not self._warned then
            self._warned = true
            warn("[CarHud] update error:", err)
        end
    end)
end

return CarHud
