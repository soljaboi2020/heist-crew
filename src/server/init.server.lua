--[[
    HEIST CREW — Server Bootstrap
    ────────────────────────────────────────────────
    Entry point for the server. Builds the world, spawns guards, wires up
    the heist state machine, and handles player join/leave + DataStore.

    Phase 2 wiring:
      ✅ HeistBuilder      (procedural mansion + vault + getaway car)
      ✅ GuardService      (patrolling + vision + chase)
      ✅ HeistService      (vault crack → alarm → escape → payout state machine)
      ✅ EconomyService    (cash add + replicate)
      ✅ PlayerDataService (DataStore-backed cache)
      ✅ TestPad           (kept around as a quick cash test)

    Coming next:
      - Multiplayer crew system (multiple players in one heist)
      - Multiple heist locations (bank, casino, museum)
      - Tool catalog (lockpick, EMP, silenced pistol)
      - Shop + cosmetics + gamepasses
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerDataService = require(script.PlayerDataService)
local EconomyService    = require(script.EconomyService)
local TestPad           = require(script.TestPad)
local HeistBuilder      = require(script.HeistBuilder)
local GuardService      = require(script.GuardService)
local HeistService      = require(script.HeistService)

print("══════════════════════════════════════════")
print("[HEIST CREW] Server online ✅")
print(string.format("[HEIST CREW] Version %s — The Heist", Constants.VERSION))
print("══════════════════════════════════════════")

-- 1. Build the world (mansion, vault, getaway car, spawn ring)
local refs = HeistBuilder:build()

-- 2. Spawn guards with callbacks pointing to the heist service
GuardService:spawnPatrols({
    onPlayerSpotted = function(player, guard)
        HeistService:onPlayerSpotted(player, guard)
    end,
    onPlayerCaught = function(player, guard)
        HeistService:onPlayerCaught(player, guard)
    end,
})

-- 3. Initialize the heist state machine (it'll wire up the vault prompt + getaway touch)
HeistService:init(refs, GuardService, EconomyService)

-- 4. Spawn the test cash pad (still useful for quick economy testing)
TestPad:spawn()

-- 5. Player join/leave flow (unchanged from Phase 1)
Players.PlayerAdded:Connect(function(player)
    print(string.format("[HEIST CREW] %s joined the crew 💼", player.Name))
    PlayerDataService:loadPlayer(player)

    local function syncCash()
        task.wait(0.5)
        EconomyService:fireCashUpdate(player)
    end

    player.CharacterAdded:Connect(syncCash)
    if player.Character then task.spawn(syncCash) end
end)

Players.PlayerRemoving:Connect(function(player)
    print(string.format("[HEIST CREW] %s left the crew", player.Name))
    PlayerDataService:savePlayer(player)
end)

game:BindToClose(function()
    print("[HEIST CREW] Server shutting down — saving all players...")
    for _, player in ipairs(Players:GetPlayers()) do
        PlayerDataService:savePlayer(player)
    end
end)
