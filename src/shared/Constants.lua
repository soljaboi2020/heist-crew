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
Constants.VERSION      = "0.3.0"
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
Constants.GUARD_VISION_RANGE      = 30
Constants.GUARD_VISION_FOV_DEGREES = 80
Constants.GUARD_ALERT_DURATION    = 8
Constants.GUARD_PATROL_SPEED      = 8
Constants.GUARD_CHASE_SPEED       = 18

-- ───── Vault crack mini-game ─────
Constants.VAULT_CRACK_TIME      = 6     -- seconds to hold E to crack the vault (was 8 — feels snappier)
Constants.VAULT_RESET_COOLDOWN  = 20    -- seconds before vault is crackable again (was 30)

-- ───── Getaway ─────
Constants.GETAWAY_TIMER     = 60
Constants.CASH_SPLIT_EQUAL  = true

-- ───── Heist payouts ─────
Constants.HEIST_PAYOUT_VAULT   = 1500   -- cracking the vault
Constants.HEIST_PAYOUT_ESCAPE  = 1000   -- escaping with the loot
Constants.HEIST_PAYOUT_STEALTH_BONUS = 500  -- bonus if no guard ever spotted you

-- ───── World layout (Vector3-friendly tables — convert with Vector3.new) ─────
-- v0.3.0: completely re-laid-out. Mansion is now CLOSE to spawn (~30 studs),
-- lobby is a proper plaza with NPC + tutorial board + lamp posts, path
-- guides players directly to the mansion entrance.
Constants.WORLD = {
    -- Spawn / lobby plaza
    SPAWN_POSITION         = {x = 0,  y = 5,    z = 0},
    LOBBY_CENTER           = {x = 0,  y = 0,    z = 0},
    LOBBY_RADIUS           = 28,

    -- Tutorial board + boss NPC (just south of spawn, between spawn and mansion)
    TUTORIAL_BOARD_POS     = {x = -14, y = 0,   z = -8},
    BOSS_NPC_POS           = {x = 12, y = 0,    z = -8},

    -- Path from lobby → mansion (straight south corridor)
    PATH_START             = {x = 0,  y = 0,    z = -15},
    PATH_END               = {x = 0,  y = 0,    z = -35},

    -- Mansion (closer, fancier, smaller footprint)
    MANSION_DOOR           = {x = 0,  y = 0,    z = -35},
    MANSION_CENTER         = {x = 0,  y = 0,    z = -55},
    MANSION_VAULT          = {x = 0,  y = 5,    z = -73},
    MANSION_HALF_WIDTH     = 22,
    MANSION_HALF_DEPTH     = 18,
    MANSION_WALL_HEIGHT    = 18,
    MANSION_DOOR_WIDTH     = 10,

    -- Getaway car (east of plaza so escape is sideways, not back through guards)
    GETAWAY_POSITION       = {x = 38, y = 2,    z = 4},

    -- Test pad (still around for quick economy testing)
    TEST_PAD_POSITION      = {x = -38, y = 0.5, z = 4},
}

-- ───── Theme colors (RGB tables — convert with Color3.fromRGB) ─────
Constants.COLORS = {
    BG_DARK       = {15, 23, 42},     -- Slate 900
    GREEN_PRIMARY = {34, 197, 94},    -- Emerald 500
    GREEN_DIM     = {22, 101, 52},    -- Emerald 800
    RED_ALERT     = {239, 68, 68},    -- Red 500
    GOLD          = {234, 179, 8},    -- Yellow 500
    GOLD_DEEP     = {180, 130, 8},    -- Darker gold for accents
    GRAY          = {75, 85, 99},     -- Gray 600
    WHITE         = {255, 255, 255},
    MARBLE_WHITE  = {235, 230, 220},  -- Mansion walls
    MARBLE_DARK   = {60, 55, 50},     -- Mansion accents / roof
    CARPET_RED    = {127, 29, 29},    -- Mansion interior carpet
    GRASS_GREEN   = {52, 116, 50},    -- Outdoor terrain tint
    PATH_STONE    = {180, 175, 165},  -- Walkway color
}

-- ───── Sound IDs (Roblox marketplace assets — known free) ─────
Constants.SOUNDS = {
    LOBBY_AMBIENT = "rbxassetid://9046657187",  -- chill background loop
    ALARM         = "rbxassetid://138081509",   -- police siren / klaxon
    CASH_CHA_CHING = "rbxassetid://131886985",  -- cash register
    VAULT_CRACK   = "rbxassetid://3744371091",  -- mechanical click
    HEIST_WIN     = "rbxassetid://9118819406",  -- triumphant sting
    HEIST_FAIL    = "rbxassetid://5466067944",  -- fail buzzer
}

return Constants
