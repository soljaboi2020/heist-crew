--[[
    HEIST CREW — Server Bootstrap
    ────────────────────────────────────────────────
    Entry point for the server. Loads services, wires up player events,
    spawns the test pad. Real game systems get added as ModuleScripts
    in this same folder and required from here.

    Phase 1 wiring:
      ✅ PlayerDataService  (cache + DataStore)
      ✅ EconomyService     (cash add + replicate to client)
      ✅ TestPad            (first earning loop — proves the pipeline)

    Coming in Phase 2+:
      - HeistService        (spawns heist rooms, runs the timer)
      - GuardService        (AI guards with patrol + alert states)
      - StealthService      (line-of-sight detection)
      - VaultService        (lockpicking mini-game)
      - GetawayService      (escape vehicle + cash split)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local PlayerDataService = require(script.PlayerDataService)
local EconomyService = require(script.EconomyService)
local TestPad = require(script.TestPad)

print("══════════════════════════════════════════")
print("[HEIST CREW] Server online ✅")
print(string.format("[HEIST CREW] Version %s — The Cash Loop", Constants.VERSION))
print("══════════════════════════════════════════")

-- Spawn the green earning pad
TestPad:spawn()

-- Player join flow
Players.PlayerAdded:Connect(function(player)
    print(string.format("[HEIST CREW] %s joined the crew 💼", player.Name))

    -- Load (or create) their saved data
    PlayerDataService:loadPlayer(player)

    -- Sync their cash to the client once their character spawns
    -- (CharacterAdded fires after the client's PlayerScripts are running,
    -- which means the HUD's listener is already mounted)
    local function syncCash()
        task.wait(0.5)  -- tiny safety buffer
        EconomyService:fireCashUpdate(player)
    end

    player.CharacterAdded:Connect(syncCash)

    -- Edge case: if character already exists when we connect (rare), sync now
    if player.Character then
        task.spawn(syncCash)
    end
end)

-- Player leave flow — save their progress
Players.PlayerRemoving:Connect(function(player)
    print(string.format("[HEIST CREW] %s left the crew", player.Name))
    PlayerDataService:savePlayer(player)
end)

-- Server shutdown — save EVERYONE
game:BindToClose(function()
    print("[HEIST CREW] Server shutting down — saving all players...")
    for _, player in ipairs(Players:GetPlayers()) do
        PlayerDataService:savePlayer(player)
    end
end)
