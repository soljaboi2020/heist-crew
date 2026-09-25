--[[
    HEIST CREW — Server Bootstrap (v1.0 "Neon Miami")
    ────────────────────────────────────────────────
    Builds the world, starts every service, and wires them together.
    No game logic lives here — see docs/V1_SPEC.md for who owns what.

      HeistBuilder      world: lighting, safehouse, Miami, Villa Rosa, Diamond Dolls
      PlayerDataService DataStore-backed saves (cash, level, gear, masks, streak…)
      EconomyService    cash in / cash out (+ VIP multiplier on payouts)
      ProgressService   XP + levels
      ShopService       gear, masks, codes, VIP pass, daily reward
      CrewService       crew-role pads + the safehouse TV
      AbilityService    Lookout's mark
      SecurityService   cameras, breaker, keycard, doors, lasers
      LootService       bags: carry, throw, load into the car
      GuardService      patrol guards (+ Muscle takedowns)
      VehicleService    the drivable getaway car
      PoliceService     cruisers + cops once the alarm trips
      JobService        runs the heist start to finish
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

print("══════════════════════════════════════════")
print("[HEIST CREW] Server online ✅")
print(string.format("[HEIST CREW] Version %s — Neon Miami", Constants.VERSION))
print("══════════════════════════════════════════")

-- Create every remote up front so clients never wait on one that's made late
for name in pairs(Remotes.NAMES) do
    Remotes.getRemote(name, (name == "ShopAction" or name == "DailyReward") and "RemoteFunction" or "RemoteEvent")
end

local notifyRemote = Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent")
local function notify(player, text, color, duration)
    if player and player.Parent and text and text ~= "" then
        notifyRemote:FireClient(player, { text = text, color = color or "white", duration = duration or 3 })
    end
end

-- A module that fails to load gets a harmless stand-in, so one broken file
-- can't take the whole game down.
local function optional(name, stub)
    local mod = script:FindFirstChild(name)
    if mod then
        local ok, result = pcall(require, mod)
        if ok then return result end
        warn("[HEIST CREW] " .. name .. " failed to load: " .. tostring(result))
    else
        warn("[HEIST CREW] " .. name .. " missing — using a stand-in")
    end
    return stub
end

local PlayerDataService = require(script.PlayerDataService)
local EconomyService    = require(script.EconomyService)
local ProgressService   = require(script.ProgressService)
local ShopService       = require(script.ShopService)
local CrewService       = require(script.CrewService)
local AbilityService    = require(script.AbilityService)
local SecurityService   = require(script.SecurityService)
local LootService       = require(script.LootService)
local GuardService      = require(script.GuardService)
local JobService        = require(script.JobService)
local HeistBuilder      = require(script.HeistBuilder)
local SafehouseBuilder  = require(script.SafehouseBuilder)
local ClubBuilder       = require(script.ClubBuilder)
local TestPad           = require(script.TestPad)

local VehicleService = optional("VehicleService", {
    init = function() end, spawnGetaway = function() return nil end, getCar = function() return nil end,
})
local PoliceService = optional("PoliceService", {
    init = function() end, dispatch = function() end, chaseCar = function() end,
    recall = function() end, isActive = function() return false end,
})

-- ── players: connect FIRST, then catch anyone who joined while we built ──
local function onPlayerAdded(player)
    print(string.format("[HEIST CREW] %s joined the crew 💼", player.Name))
    PlayerDataService:loadPlayer(player)
    EconomyService:fireCashUpdate(player)
    ProgressService:sync(player)
    ShopService:onPlayerJoined(player)

    -- (fix v1.1) the first character may already exist by now
    if player.Character and ShopService:hasGear(player, "Sneakers") then
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 18 end
    end
    player.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        EconomyService:fireCashUpdate(player)
        -- Silent Sneakers gear: +2 walk speed (LootService handles it while carrying)
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and ShopService:hasGear(player, "Sneakers") then hum.WalkSpeed = 18 end
    end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
    print(string.format("[HEIST CREW] %s left the crew", player.Name))
    PlayerDataService:savePlayer(player)
end)

-- ── services that don't need the world ──────────────────────────────
ProgressService:init(PlayerDataService, notify)
ShopService:init(PlayerDataService, EconomyService, notify)
AbilityService:init(notify)

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end

-- ── build the world (this yields: NPC outfits + Kenney models load) ─────
local world = HeistBuilder:build()

-- (fix v1.2.1) Roblox loads your character while the world is still building,
-- before the spawn pad has moved down into The Vault -- so the FIRST spawn landed
-- you out on the street by the auto shop. Anyone already in the game gets moved
-- down to the club spawn now that it exists. (Respawns already use the new pad.)
do
    local sp = Constants.WORLD.SPAWN_POSITION
    local spawnAt = Vector3.new(sp.x, sp.y + 3.5, sp.z)
    local faceTo  = Vector3.new(Constants.WORLD.HUB_TABLE.x, sp.y + 3.5, Constants.WORLD.HUB_TABLE.z)
    local pads = (world.hub and world.hub.spawnPads) or {}   -- v2.0: the club entrance lobby
    for i, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if char and char.PrimaryPart then
            local pad = pads[(i - 1) % math.max(#pads, 1) + 1]
            if pad then
                char:PivotTo(pad.CFrame + Vector3.new(0, 3.5, 0))
            else
                char:PivotTo(CFrame.lookAt(spawnAt, faceTo))
            end
            print("[HEIST CREW] moved early joiner into The Vault:", player.Name)
        end
    end
end

-- v1.2: the crew pads, TV and blueprint live in The Vault (the club HQ)
local hub = world.hub or {}
CrewService:init(hub, PlayerDataService)

JobService.hub = hub
JobService.onJobChanged = function(cfg, jobRefs)
    SafehouseBuilder:showJob(hub, cfg, jobRefs)
end
ClubBuilder.onNextJob = function(player) JobService:cycleJob(player) end
ClubBuilder.onReadyUp = function(player) JobService:toggleReady(player) end

-- Freight lift between The Vault and the auto shop (client fades, we teleport)
local launchRemote = Remotes.getRemote(Remotes.NAMES.LaunchJob, "RemoteEvent")
local travelling = {}
local function travel(player, dir)
    if travelling[player] then return end
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    travelling[player] = true
    launchRemote:FireClient(player, { phase = "travel", dir = dir })
    task.delay(0.45, function()
        local W = Constants.WORLD
        if hrp.Parent then
            if dir == "down" then
                local e = W.HUB_ELEVATOR
                hrp.CFrame = CFrame.lookAt(Vector3.new(e.x, W.HUB_FLOOR + 3, e.z - 2), Vector3.new(e.x, W.HUB_FLOOR + 3, e.z - 20))
            else
                local e = W.SAFEHOUSE_ELEVATOR
                hrp.CFrame = CFrame.lookAt(Vector3.new(e.x, e.y + 3, e.z), Vector3.new(e.x, e.y + 3, e.z - 20))
            end
        end
        travelling[player] = nil
    end)
end
ClubBuilder.onElevator = travel
SafehouseBuilder.onElevator = travel

-- Trophy room: shows the best heist count of anyone in the server
local function refreshTrophies()
    if not hub.setTrophies then return end
    local best = 0
    for _, p in ipairs(Players:GetPlayers()) do
        local d = PlayerDataService:getData(p)
        if d and (d.heistsCompleted or 0) > best then best = d.heistsCompleted end
    end
    pcall(hub.setTrophies, best)
end
JobService.onFinished = refreshTrophies
Players.PlayerAdded:Connect(function() task.delay(3, refreshTrophies) end)
Players.PlayerRemoving:Connect(function() task.defer(refreshTrophies) end)
task.delay(3, refreshTrophies)

-- ── v2.0 services (each optional: one broken file can't stop the server) ──
local FeelService = optional("FeelService", nil)
local HideService = optional("HideService", nil)
local JailService = optional("JailService", nil)
local BotService = optional("BotService", nil)
local PortalService = optional("PortalService", nil)
local DailyRewardService = optional("DailyRewardService", nil)
local LeaderboardService = optional("LeaderboardService", nil)
local CosmeticsService = optional("CosmeticsService", nil)
local AmbientService = optional("AmbientService", nil)
local VentService = optional("VentService", nil)
local function safe(label, fn)
    local ok, err = pcall(fn)
    if not ok then warn("[HEIST CREW] " .. label .. " failed: " .. tostring(err)) end
end
if FeelService then safe("FeelService", function() FeelService:init() end) end
if VentService then safe("VentService", function() VentService:init({ feel = FeelService }) end) end
if HideService then safe("HideService", function() HideService:init({ feel = FeelService }) end) end
if CosmeticsService then safe("CosmeticsService", function() CosmeticsService:init(PlayerDataService, EconomyService, notify) end) end
if DailyRewardService then safe("DailyRewardService", function() DailyRewardService:init(PlayerDataService, EconomyService, notify, CosmeticsService) end) end
if LeaderboardService then
    safe("LeaderboardService", function()
        LeaderboardService:init(PlayerDataService)
        if hub.leaderboardAnchor then
            LeaderboardService:placeBoard(hub.leaderboardAnchor, world.heistFolder or workspace)
        end
    end)
end
if AmbientService then
    safe("AmbientService", function()
        local f = Instance.new("Folder")
        f.Name = "Ambient"
        f.Parent = world.heistFolder or workspace
        AmbientService:start(f)
    end)
end

JobService:init({
    crew = CrewService,
    feel = FeelService,
    hide = HideService,
    jobs = world.jobs,
    security = SecurityService,
    loot = LootService,
    guards = GuardService,
    vehicles = VehicleService,
    police = PoliceService,
    economy = EconomyService,
    progress = ProgressService,
    shop = ShopService,
    data = PlayerDataService,
})

if JailService then safe("JailService", function() JailService:init({ jail = world.jail, notify = notify, jobService = JobService }) end) end
if BotService then safe("BotService", function() BotService:init({ jobService = JobService, loot = LootService }) end) end
if PortalService then safe("PortalService", function() PortalService:init({ hub = hub, jobService = JobService, notify = notify }) end) end

-- First-join fly-over (client IntroCam plays it once per join)
do
    local introRemote = Remotes.getRemote(Remotes.NAMES.IntroCam, "RemoteEvent")
    local function sendIntro(player)
        if hub.introPath and #hub.introPath > 0 then
            task.delay(2, function()
                if player.Parent then introRemote:FireClient(player, { points = hub.introPath }) end
            end)
        end
    end
    Players.PlayerAdded:Connect(sendIntro)
    for _, p in ipairs(Players:GetPlayers()) do sendIntro(p) end
end

if Constants.DEV_TEST_PAD then TestPad:spawn() end

game:BindToClose(function()
    print("[HEIST CREW] Server shutting down — saving all players...")
    for _, player in ipairs(Players:GetPlayers()) do
        PlayerDataService:savePlayer(player)
    end
end)

print("[HEIST CREW] All systems go 🚀")
