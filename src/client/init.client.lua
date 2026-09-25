--[[
    HEIST CREW — Client Bootstrap
    ────────────────────────────────────────────────
    Runs on each player's device. Mounts UI, listens for server events,
    handles input + camera + visual effects.

    Phase 2 wiring:
      ✅ CashHud        — green cash counter in the top-right corner
      ✅ Notifications  — top-center sliding toast messages
      ✅ HeistHud       — alarm vignette + vault crack bar + result card
      ✅ CrewHud        — role card + objective pill + title card (v0.7.0)
    All UI shares one look: Shared.UITheme.
--]]

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local CashHud       = require(script.CashHud)
local Notifications = require(script.Notifications)
local HeistHud      = require(script.HeistHud)
local CrewHud       = require(script.CrewHud)

print("══════════════════════════════════════════")
print(string.format("[HEIST CREW] Client online ✅ — playing as %s", localPlayer.Name))
print("══════════════════════════════════════════")

-- Mount the cash HUD (top-right green counter)
CashHud:start()

-- Mount the toast notifications system (top-center sliding messages)
Notifications:start()

-- Mount the heist HUD (vault progress + alarm border + state banner)
HeistHud:start()

-- Role card + objective pill + title card (v0.7.0)
CrewHud:start()
