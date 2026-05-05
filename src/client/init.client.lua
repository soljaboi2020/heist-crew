--[[
    HEIST CREW — Client Bootstrap
    ────────────────────────────────────────────────
    Runs on each player's device. Mounts UI, listens for server events,
    handles input + camera + visual effects.

    Phase 2 wiring:
      ✅ CashHud        — green cash counter in the top-right corner
      ✅ Notifications  — top-center sliding toast messages
      ✅ HeistHud       — vault crack progress bar + alarm border + state banner
--]]

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local CashHud       = require(script.CashHud)
local Notifications = require(script.Notifications)
local HeistHud      = require(script.HeistHud)

print("══════════════════════════════════════════")
print(string.format("[HEIST CREW] Client online ✅ — playing as %s", localPlayer.Name))
print("══════════════════════════════════════════")

-- Mount the cash HUD (top-right green counter)
CashHud:start()

-- Mount the toast notifications system (top-center sliding messages)
Notifications:start()

-- Mount the heist HUD (vault progress + alarm border + state banner)
HeistHud:start()
