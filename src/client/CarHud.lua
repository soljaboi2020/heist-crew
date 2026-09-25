--[[
    HEIST CREW — CarHud
    ────────────────────────────────────────────────
    v3.0 "THE SCORE" (getaway agent, 2026-09-25): NOBODY DRIVES ANY MORE.
    The card you see while you sit in the getaway car is now the escape
    button, kid-simple:

      • CAR      the car type + what it pays ("TANK · +12% cash getaway"),
                 from the model's CarName / CarPerk attributes
      • BAGS     💰 how many bags are in the car ("Bags" model attribute)
      • CREW     👥 how many of the crew are sitting in the car
                 ("CrewIn" / "CrewNeed", kept fresh by JobService)
      • GO!      a big green button. Everyone in the car = it goes by itself;
                 or the driver (anyone, if the driver seat is empty) presses
                 GO! once at least one bag is loaded. Enter / gamepad X / tap.
                 Fires the "Getaway" remote { action = "go" }.
      • VOTE     while the crew picks the escape the button turns into a
                 status line ("Pick how we escape!" / "Here we go!").
                 ("GetawayPhase" model attribute: wait | vote | decided | scene)

    Also starts GetawayVote + GetawayCinematic (sibling modules) if the client
    bootstrap hasn't — both :start() calls are idempotent, so adding them to
    init.client's ORDER later is harmless.

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

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local CarHud = {}
local localPlayer = Players.LocalPlayer

local GO_ACTION = "HeistCrewGetawayGo"
local REMOTE = "Getaway"

-- Non-yielding remote lookup
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

    local panel = UITheme.card({
        Name = "CarPanel", LayoutOrder = 50, Size = UDim2.fromOffset(400, 150), radius = 20, Visible = false,
    })
    panel.Parent = UITheme.slot("bottomCenter")

    -- car name + what it pays
    local carBadge = UITheme.badge(UITheme.ICON.car, T.gold, 34)
    carBadge.Position = UDim2.fromOffset(14, 12)
    carBadge.Parent = panel
    local carName = UITheme.label({
        Name = "CarName", Text = "", Position = UDim2.fromOffset(56, 10), Size = UDim2.fromOffset(200, 20),
        FontFace = UITheme.F.display, TextSize = 18, TextColor3 = T.gold, TextTruncate = Enum.TextTruncate.AtEnd,
    })
    carName.Parent = panel
    local carPerk = UITheme.label({
        Name = "CarPerk", Text = "", Position = UDim2.fromOffset(56, 30), Size = UDim2.fromOffset(200, 16),
        FontFace = UITheme.F.bold, TextSize = 13, TextColor3 = T.muted, TextTruncate = Enum.TextTruncate.AtEnd,
    })
    carPerk.Parent = panel

    -- bags + crew counters (big, readable)
    local bags = UITheme.label({
        Name = "Bags", Text = "💰 0 bags", Position = UDim2.fromOffset(16, 58), Size = UDim2.fromOffset(230, 34),
        FontFace = UITheme.F.display, TextSize = 28, TextColor3 = T.money,
    })
    bags.Parent = panel
    local crew = UITheme.label({
        Name = "Crew", Text = "👥 0/0 in the car", Position = UDim2.fromOffset(16, 92), Size = UDim2.fromOffset(230, 22),
        FontFace = UITheme.F.bold, TextSize = 18, TextColor3 = T.text,
    })
    crew.Parent = panel
    local hint = UITheme.label({
        Name = "Hint", Text = "", Position = UDim2.fromOffset(16, 118), Size = UDim2.new(1, -32, 0, 20),
        FontFace = UITheme.F.medium, TextSize = 14, TextColor3 = T.muted, TextTruncate = Enum.TextTruncate.AtEnd,
    })
    hint.Parent = panel

    -- the GO! button
    local go = UITheme.button("GO!", T.money, {
        Name = "GoButton", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14),
        Size = UDim2.fromOffset(130, 96), TextSize = 44,
    })
    go.Parent = panel
    local goSub = UITheme.label({
        Name = "GoSub", Text = "", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6),
        Size = UDim2.new(1, -8, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
        TextSize = 12, TextColor3 = T.bgDeep, ZIndex = 3,
    })
    goSub.Parent = go
    go.Activated:Connect(function() self:_pressGo() end)

    -- during the vote / movie the button becomes a status line
    local status = UITheme.label({
        Name = "Status", Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14),
        Size = UDim2.fromOffset(150, 96), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
        FontFace = UITheme.F.display, TextSize = 20, TextColor3 = T.gold, Visible = false,
    })
    status.Parent = panel

    self.ui = {
        panel = panel, carName = carName, carPerk = carPerk, bags = bags, crew = crew, hint = hint,
        go = go, goSub = goSub, status = status,
    }
end

-- ──────────────────────────────────────────────
-- GO!
-- ──────────────────────────────────────────────
function CarHud:_canGo()
    local car = self.car
    if not car then return false, "" end
    local phase = car:GetAttribute("GetawayPhase")
    if phase == "vote" or phase == "decided" or phase == "scene" then return false, "" end
    if phase ~= "wait" then return false, "No heist going" end
    if num(car:GetAttribute("Bags")) < 1 then return false, "Load a bag first" end
    local driverSeat = car:FindFirstChild("GetawayDriverSeat", true)
    local driverHum = driverSeat and (driverSeat:IsA("Seat") or driverSeat:IsA("VehicleSeat")) and driverSeat.Occupant or nil
    if driverHum and driverHum.Parent ~= localPlayer.Character then return false, "Driver's call" end
    return true, "Let's go!"
end

function CarHud:_pressGo()
    if os.clock() - (self._lastGo or 0) < 0.6 then return end
    self._lastGo = os.clock()
    local ok = self:_canGo()
    if not ok then return end
    local r = findRemote(REMOTE)
    if r then r:FireServer({ action = "go" }) end
end

function CarHud:_bindGo(on)
    if on and not self.goBound then
        ContextActionService:BindActionAtPriority(GO_ACTION, function(_, state)
            if state == Enum.UserInputState.Begin then self:_pressGo() end
            return Enum.ContextActionResult.Pass
        end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.ButtonX)
        self.goBound = true
    elseif not on and self.goBound then
        ContextActionService:UnbindAction(GO_ACTION)
        self.goBound = false
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
        if self.ui then self.ui.panel.Visible = true end
    else
        self.seat = nil
        self.car = nil
        if self.ui then self.ui.panel.Visible = false end
    end
    self:_bindGo(self.car ~= nil)
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
            self:_bindGo(false)
        end
        return
    end

    local cn = car:GetAttribute("CarName")
    local cp = car:GetAttribute("CarPerk")
    ui.carName.Text = type(cn) == "string" and string.upper(cn) or "GETAWAY CAR"
    ui.carPerk.Text = type(cp) == "string" and cp or ""

    local n = math.floor(num(car:GetAttribute("Bags")))
    ui.bags.Text = string.format("💰 %d bag%s", n, n == 1 and "" or "s")
    ui.bags.TextColor3 = n > 0 and T.money or T.muted
    local crewIn, need = math.floor(num(car:GetAttribute("CrewIn"))), math.floor(num(car:GetAttribute("CrewNeed")))
    ui.crew.Text = need > 0 and string.format("👥 %d/%d in the car", crewIn, need) or "👥 In the car"

    local phase = car:GetAttribute("GetawayPhase")
    local busy = phase == "vote" or phase == "decided" or phase == "scene"
    ui.go.Visible = not busy
    ui.status.Visible = busy
    if busy then
        ui.status.Text = (phase == "vote") and "Pick how we escape!" or "Here we go!"
        ui.hint.Text = "Hold on tight…"
        return
    end
    local ok, why = self:_canGo()
    ui.go.BackgroundColor3 = ok and T.money or T.faint
    ui.go.AutoButtonColor = ok
    ui.goSub.Text = why or ""
    if phase ~= "wait" then
        ui.hint.Text = "Start a heist to use the getaway car"
    elseif n < 1 then
        ui.hint.Text = "Bring loot! Put a bag in the trunk (E)"
    elseif need > 0 and crewIn >= need then
        ui.hint.Text = "Everyone's in! Here we go…"
    else
        ui.hint.Text = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
            and "Everyone in the car = we go! Or tap GO!" or "Everyone in the car = we go! Or press GO! (Enter)"
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

    -- v3.0: the vote cards + the getaway movie (idempotent starts)
    for _, name in ipairs({ "GetawayVote", "GetawayCinematic" }) do
        local mod = script.Parent:FindFirstChild(name)
        if mod then
            task.spawn(function()
                local ok, err = pcall(function() require(mod):start() end)
                if not ok then warn("[CarHud] " .. name .. " failed: " .. tostring(err)) end
            end)
        end
    end
    print("[HEIST CREW] CarHud mounted ✅")
end

return CarHud
