--[[
    HEIST CREW — Client Bootstrap
    ────────────────────────────────────────────────
    Runs on each player's device. Mounts UI, listens for server events,
    handles input + camera + visual effects.

    Phase 1 wiring:
      ✅ CashHud  — green cash counter in the top-right corner
--]]

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local CashHud = require(script.CashHud)

print("══════════════════════════════════════════")
print(string.format("[HEIST CREW] Client online ✅ — playing as %s", localPlayer.Name))
print("══════════════════════════════════════════")

-- Mount the cash HUD (top-right green counter)
CashHud:start()
