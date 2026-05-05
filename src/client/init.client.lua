--[[
    HEIST CREW — Client Bootstrap
    ────────────────────────────────────────────────
    This runs on each player's device (their phone/PC/console).
    Handles UI, input, camera, and visual effects.

    Right now it just confirms the client is alive.
--]]

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

print("══════════════════════════════════════════")
print(string.format("[HEIST CREW] Client online ✅ — playing as %s", localPlayer.Name))
print("══════════════════════════════════════════")
