--[[
    HEIST CREW — Server Bootstrap
    ────────────────────────────────────────────────
    This is the entry point that runs on the Roblox server when the game starts.
    Right now it just confirms the connection is alive — proof that Rojo is
    syncing your local files into Studio correctly.

    Once the smoke test passes, we'll wire up:
      - PlayerDataService   (saves/loads player progress)
      - HeistService        (spawns heist rooms, runs the timer)
      - GuardService        (AI guards with patrol + alert states)
      - StealthService      (line-of-sight detection)
      - VaultService        (lockpicking mini-game)
      - GetawayService      (escape vehicle + cash split)
      - EconomyService      (cash, gear shop, gamepass perks)

    File structure mirrors `src/server/` in your repo. Anything you drop in
    here automatically becomes a server script in `ServerScriptService.Server`.
--]]

print("══════════════════════════════════════════")
print("[HEIST CREW] Server online ✅")
print("[HEIST CREW] Version 0.0.1 — Hello world phase")
print("══════════════════════════════════════════")

local Players = game:GetService("Players")

-- Greet every player who joins (smoke test for player events)
Players.PlayerAdded:Connect(function(player)
    print(string.format("[HEIST CREW] %s joined the crew 💼", player.Name))
end)

Players.PlayerRemoving:Connect(function(player)
    print(string.format("[HEIST CREW] %s left the crew", player.Name))
end)
