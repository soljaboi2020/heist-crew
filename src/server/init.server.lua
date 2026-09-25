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
    Remotes.getRemote(name, name == "ShopAction" and "RemoteFunction" or "RemoteEvent")
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

CrewService:init(world.safehouse, PlayerDataService)

JobService.onJobChanged = function(cfg, jobRefs)
    SafehouseBuilder:showJob(world.safehouse, cfg, jobRefs)
end
SafehouseBuilder.onNextJob = function(player)
    JobService:cycleJob(player)
end

JobService:init({
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

if Constants.DEV_TEST_PAD then TestPad:spawn() end

game:BindToClose(function()
    print("[HEIST CREW] Server shutting down — saving all players...")
    for _, player in ipairs(Players:GetPlayers()) do
        PlayerDataService:savePlayer(player)
    end
end)

print("[HEIST CREW] All systems go 🚀")
