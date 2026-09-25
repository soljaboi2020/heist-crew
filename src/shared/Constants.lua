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
Constants.VERSION      = "0.7.0"
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
-- v0.4.0 co-op note: VAULT + ESCAPE + STEALTH are paid to EACH crew member who
-- reaches the getaway car, so a clean solo run still totals $3,000 exactly as it
-- did before. CRACKER_BONUS is the only per-person extra — it goes to whoever
-- actually held E on the vault, so there's a reason to volunteer for the risky job.
Constants.HEIST_PAYOUT_VAULT   = 1500   -- loot share, per escapee
Constants.HEIST_PAYOUT_ESCAPE  = 1000   -- escaping with the loot, per escapee
Constants.HEIST_PAYOUT_STEALTH_BONUS = 500  -- bonus if no guard ever spotted the crew
Constants.HEIST_PAYOUT_CRACKER_BONUS = 750  -- to the player who cracked the vault

-- ───── World layout (Vector3-friendly tables — convert with Vector3.new) ─────
-- v0.7.0 (2026-09-25): the open marble plaza is gone. Players spawn INSIDE the
-- crew safehouse (a warehouse south of the street), walk out through a roll-up
-- garage door, cross a real street, and hit the mansion on the far side.
--   +Z = south (safehouse side)     -Z = north (mansion side)
Constants.WORLD = {
    -- Spawn — inside the safehouse, facing north toward the planning table
    SPAWN_POSITION         = {x = 0,  y = 0.6,  z = 27},

    -- The safehouse (warehouse). Garage door is in the NORTH wall.
    SAFEHOUSE_CENTER       = {x = 0,  y = 0,    z = 22},
    SAFEHOUSE_HALF_WIDTH   = 24,
    SAFEHOUSE_HALF_DEPTH   = 18,
    SAFEHOUSE_HEIGHT       = 16,
    GARAGE_WIDTH           = 18,
    GARAGE_HEIGHT          = 12,

    -- Boss stands at the planning table
    BOSS_NPC_POS           = {x = 8,  y = 0,    z = 19},

    -- Street between the safehouse and the mansion (runs east-west)
    STREET_Z               = -14,
    STREET_HALF_WIDTH      = 8,

    -- Mansion
    MANSION_DOOR           = {x = 0,  y = 0,    z = -35},
    MANSION_CENTER         = {x = 0,  y = 0,    z = -55},
    MANSION_VAULT          = {x = 0,  y = 5,    z = -73},
    MANSION_HALF_WIDTH     = 22,
    MANSION_HALF_DEPTH     = 18,
    MANSION_WALL_HEIGHT    = 18,
    MANSION_DOOR_WIDTH     = 10,

    -- Getaway car (parked in the alley east of the safehouse)
    GETAWAY_POSITION       = {x = 38, y = 2.5,  z = 8},

    -- Test pad (still around for quick economy testing)
    TEST_PAD_POSITION      = {x = -38, y = 0.5, z = 4},
}

-- ───── Crew roles (v0.7.0) ─────
-- Picked by standing on a pad in the safehouse. One player per role.
-- ⚠️ Roles are COSMETIC for now (badge + roster). Abilities come later and get
-- approved first (Rule #12).
Constants.ROLES = {
    { id = "Hacker",  color = {56, 189, 248},  blurb = "Cameras, keypads, alarms" },
    { id = "Muscle",  color = {248, 113, 113}, blurb = "Heavy loot, doors, crowds" },
    { id = "Driver",  color = {251, 191, 36},  blurb = "Getaway car, cop chases" },
    { id = "Lookout", color = {74, 222, 128},  blurb = "Spots guards through walls" },
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
