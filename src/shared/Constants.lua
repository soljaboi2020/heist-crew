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
Constants.VERSION      = "0.2.0"
Constants.STUDIO_NAME  = "Malachi Builds"

-- ───── Crew settings ─────
Constants.MAX_CREW_SIZE = 4

-- ───── Lobby settings ─────
Constants.LOBBY_MAX_PLAYERS  = 12
Constants.HEIST_MAX_DURATION = 600

-- ───── Economy ─────
Constants.STARTING_CASH     = 100
Constants.MIN_HEIST_PAYOUT  = 500
Constants.MAX_HEIST_PAYOUT  = 10000000

-- ───── Stealth + AI ─────
Constants.GUARD_VISION_RANGE      = 35
Constants.GUARD_VISION_FOV_DEGREES = 90
Constants.GUARD_ALERT_DURATION    = 8
Constants.GUARD_PATROL_SPEED      = 8
Constants.GUARD_CHASE_SPEED       = 16

-- ───── Vault crack mini-game ─────
Constants.VAULT_CRACK_TIME      = 8     -- seconds to hold E to crack the vault
Constants.VAULT_RESET_COOLDOWN  = 30    -- seconds before vault is crackable again

-- ───── Getaway ─────
Constants.GETAWAY_TIMER     = 90
Constants.CASH_SPLIT_EQUAL  = true

-- ───── Heist payouts ─────
Constants.HEIST_PAYOUT_VAULT   = 1500   -- cracking the vault
Constants.HEIST_PAYOUT_ESCAPE  = 1000   -- escaping with the loot
Constants.HEIST_PAYOUT_STEALTH_BONUS = 500  -- bonus if no guard ever spotted you

-- ───── World layout (Vector3-friendly tables — convert with Vector3.new) ─────
Constants.WORLD = {
    SPAWN_POSITION       = {x = 0, y = 5, z = 0},
    TEST_PAD_POSITION    = {x = 25, y = 0.5, z = 5},
    GETAWAY_POSITION     = {x = 0, y = 2, z = -70},
    MANSION_DOOR         = {x = 0, y = 0, z = -120},
    MANSION_CENTER       = {x = 0, y = 0, z = -160},
    MANSION_VAULT        = {x = 0, y = 5, z = -185},
    MANSION_HALF_WIDTH   = 30,
    MANSION_HALF_DEPTH   = 25,
    MANSION_WALL_HEIGHT  = 18,
    MANSION_DOOR_WIDTH   = 12,
}

-- ───── Theme colors (RGB tables — convert with Color3.fromRGB) ─────
Constants.COLORS = {
    BG_DARK     = {15, 23, 42},     -- Slate 900
    GREEN_PRIMARY = {34, 197, 94},  -- Emerald 500
    GREEN_DIM   = {22, 101, 52},    -- Emerald 800
    RED_ALERT   = {239, 68, 68},    -- Red 500
    GOLD        = {234, 179, 8},    -- Yellow 500
    GRAY        = {75, 85, 99},     -- Gray 600
    WHITE       = {255, 255, 255},
}

return Constants
