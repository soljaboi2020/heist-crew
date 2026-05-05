--[[
    HEIST CREW — Shared Constants
    ────────────────────────────────────────────────
    Lives in ReplicatedStorage so BOTH server and client can read these
    values. Single source of truth for game-wide settings.

    Usage from any script:
        local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)
        print(Constants.GAME_NAME)
--]]

local Constants = {}

-- ───── Game identity ─────
Constants.GAME_NAME    = "Heist Crew"
Constants.VERSION      = "0.0.1"
Constants.STUDIO_NAME  = "Malachi Builds"

-- ───── Crew settings ─────
Constants.MAX_CREW_SIZE = 4   -- 4-player coop heists

-- ───── Lobby settings ─────
Constants.LOBBY_MAX_PLAYERS = 12  -- max players in the hub at once
Constants.HEIST_MAX_DURATION = 600  -- 10 minutes (in seconds)

-- ───── Economy ─────
Constants.STARTING_CASH     = 100   -- new players spawn with $100
Constants.MIN_HEIST_PAYOUT  = 500
Constants.MAX_HEIST_PAYOUT  = 10000000  -- top-tier mansion late-game

-- ───── Stealth + AI ─────
Constants.GUARD_VISION_RANGE      = 30   -- studs (Roblox unit)
Constants.GUARD_VISION_FOV_DEGREES = 90  -- guard cone of vision
Constants.GUARD_ALERT_DURATION    = 8    -- seconds guard stays alert after losing sight

-- ───── Vault crack mini-game ─────
Constants.LOCKPICK_TICK_RATE = 0.05  -- 50ms — how fast the dial spins
Constants.LOCKPICK_TOLERANCE = 5     -- degrees — how close to the right angle counts

-- ───── Getaway ─────
Constants.GETAWAY_TIMER     = 60   -- seconds to reach the getaway car after the alarm
Constants.CASH_SPLIT_EQUAL  = true -- if false, raid leader gets bonus

return Constants
