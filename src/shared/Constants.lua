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
Constants.VERSION      = "1.1.0"
Constants.STUDIO_NAME  = "Malachi Builds"

-- ───── Dev switches ─────
Constants.DEV_TEST_PAD = false   -- the +$50 green test pad (dev only)

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
-- v1.0 "NEON MIAMI" (2026-09-25). Full map in docs/V1_SPEC.md.
--   +Z = south (safehouse / jewelry side)   -Z = north (villa / beach side)
--   Ground top = y 0. Building floors top = y 0.5 (FLOOR).
Constants.WORLD = {
    FLOOR                  = 0.5,

    -- Spawn — inside the safehouse, facing north toward the planning table
    SPAWN_POSITION         = {x = 0,  y = 0.6,  z = 27},

    -- The safehouse (warehouse / "Riverside Auto Body"). Garage in the NORTH wall.
    SAFEHOUSE_CENTER       = {x = 0,  y = 0,    z = 22},
    SAFEHOUSE_HALF_WIDTH   = 24,
    SAFEHOUSE_HALF_DEPTH   = 18,
    SAFEHOUSE_HEIGHT       = 16,
    GARAGE_WIDTH           = 18,
    GARAGE_HEIGHT          = 12,
    BOSS_NPC_POS           = {x = 8,  y = 0,    z = 19},

    -- Ocean Drive: the street (runs east-west)
    STREET_Z               = -14,
    STREET_HALF_WIDTH      = 8,
    STREET_LENGTH          = 300,     -- x -150..150

    -- Villa Rosa (job 1) — beachfront art-deco villa, north of the street
    MANSION_CENTER         = {x = 0,  y = 0,    z = -60},
    MANSION_HALF_WIDTH     = 30,
    MANSION_HALF_DEPTH     = 22,      -- z -82..-38, front door at z -38
    MANSION_WALL_HEIGHT    = 16,
    MANSION_DOOR_WIDTH     = 10,

    -- Diamond Dolls Jewelers (job 2) — storefront on the south side of the street
    JEWELRY_CENTER         = {x = -58, y = 0,   z = 11},
    JEWELRY_HALF_WIDTH     = 12,      -- x -70..-46
    JEWELRY_HALF_DEPTH     = 12,      -- z -1..23, shopfront faces north (z -1)

    -- Beach + ocean (Terrain)
    BEACH_Z0               = -88,     -- sand from here north...
    BEACH_Z1               = -108,    -- ...to here, then water
    OCEAN_SURFACE_Y        = -0.6,

    -- The marina drop-off: drive the loaded getaway car here to cash out
    DROPOFF                = {x = 106, y = 0,   z = -96},
    DROPOFF_RADIUS         = 14,

    -- Default getaway parking (jobs override this with their own spot)
    GETAWAY_POSITION       = {x = -40, y = 0,   z = -18},

    -- Police cruisers enter from the street ends
    POLICE_SPAWNS          = { {x = -145, y = 0, z = -10}, {x = 145, y = 0, z = -18} },

    -- Test pad (dev only — see DEV_TEST_PAD)
    TEST_PAD_POSITION      = {x = -38, y = 0.5, z = 4},
}

-- ───── Neon Miami palette (world art) ─────
Constants.MIAMI = {
    PASTELS = {
        {242, 160, 190}, -- flamingo pink
        {150, 225, 200}, -- mint
        {190, 170, 235}, -- lilac
        {250, 200, 160}, -- peach
        {150, 205, 240}, -- sky
        {245, 230, 150}, -- lemon
    },
    NEONS = {
        {255, 70, 180},  -- hot pink
        {40, 230, 255},  -- cyan
        {180, 90, 255},  -- purple
        {255, 140, 60},  -- sunset orange
    },
    STUCCO = {240, 232, 222},
}

-- ───── Crew roles (v0.7.0) ─────
-- Picked by standing on a pad in the safehouse. One player per role.
-- v1.0: roles have real perks (AbilityService). Malachi approved "do everything".
Constants.ROLES = {
    { id = "Hacker",  color = {56, 189, 248},  blurb = "Cameras, keypads, alarms",
      perks = "Hacks keycard doors without a card · cuts cameras 3x faster" },
    { id = "Muscle",  color = {248, 113, 113}, blurb = "Heavy loot, doors, crowds",
      perks = "Full speed with any bag · takes down guards from behind (E)" },
    { id = "Driver",  color = {251, 191, 36},  blurb = "Getaway car, cop chases",
      perks = "+20% car speed · nitro boost (Shift)" },
    { id = "Lookout", color = {74, 222, 128},  blurb = "Spots guards through walls",
      perks = "Sees guards + cameras through walls · Q marks them for the crew" },
}


-- ───── Jobs (v1.0) ─────
-- Each job has a builder (geometry → JobRefs, see docs/V1_SPEC.md) and is run
-- by JobService. Only the SELECTED job is armed; the other shows CLOSED.
Constants.JOBS = {
    {
        id = "villa", name = "VILLA ROSA", tagline = "Beachfront villa. Stealth pays.",
        difficulty = 2, unlockLevel = 1, guards = 3,
        alarmTimer = 90,           -- seconds to get the loaded car to the marina once the alarm trips
        stealthBonus = 0.25,       -- +25% of the take if the alarm never trips
        briefing = {
            "Villa Rosa. Beachfront. Owner's in Monaco — the vault isn't.",
            "Three guards with flashlights, three cameras. Cut the cameras at the breaker in the security room.",
            "The vault wing needs a keycard. It moves around — search the office, bedroom, kitchen and gallery.",
            "Lasers blink. Time it. Drill the vault, and if the drill jams, fix it.",
            "Bag everything, load the car, drive it to the marina. Quiet pays extra.",
        },
    },
    {
        id = "jewelry", name = "DIAMOND DOLLS", tagline = "Smash, grab, go. Silent alarm.",
        difficulty = 3, unlockLevel = 3, guards = 2,
        alarmTimer = 75,
        stealthBonus = 0.15,
        silentAlarmDelay = 45,     -- first smashed case starts a hidden clock; police roll after this
        briefing = {
            "Diamond Dolls. Eight glass cases, and every one of them is wired.",
            "The first case you smash trips a silent alarm. Cops are on their way — you just won't hear them.",
            "Grab what you can, then the back room: keycard door, one laser, a safe.",
            "Load the car and get to the marina before the block goes red.",
        },
    },
}

-- Loot kinds. value = cash added to the crew's take when the bag is secured.
-- speed = WalkSpeed while carrying (Muscle ignores it). Default WalkSpeed is 16.
Constants.LOOT = {
    Cash     = { value = 1000, speed = 13, color = {74, 222, 128} },
    Gold     = { value = 1500, speed = 10, color = {251, 191, 36} },
    Diamonds = { value = 2500, speed = 12, color = {125, 211, 252} },
    Jewels   = { value = 900,  speed = 14, color = {244, 114, 182} },
    Art      = { value = 2000, speed = 11, color = {196, 181, 253} },
}

-- Security tuning (SecurityService)
Constants.SECURITY = {
    CAMERA_RANGE        = 32,
    CAMERA_HALF_ANGLE   = 24,     -- degrees
    CAMERA_DETECT_TIME  = 0.7,    -- seconds in view before the alarm trips
    BREAKER_HOLD        = 3,      -- seconds to cut the cameras (Hacker: 1)
    HACK_DOOR_HOLD      = 4,      -- Hacker opens keycard doors without a card
    LASER_CHECK_RATE    = 0.08,
}

-- Detection: guards/cameras fill a meter before the alarm (v1.1) — seeing you
-- up close fills it fast, at the edge of their vision it fills slowly.
Constants.DETECTION = {
    GUARD_NEAR_TIME = 0.4,    -- seconds to spot you at point-blank
    GUARD_FAR_TIME  = 1.4,    -- seconds to spot you at the edge of vision
    DECAY           = 0.6,    -- meter drains this much per second once you're out of sight
}

-- Heist flow
Constants.LAUNCH_COUNTDOWN    = 5     -- seconds between "everyone ready" and the drop-in
Constants.HEIST_RUN_LIMIT     = 480   -- a quiet run can take this long before the owner calls it
Constants.JOB_RESET_COOLDOWN  = 15
Constants.BAG_THROW_SPEED     = 55

-- ───── Progression ─────
Constants.XP = {
    PER_HEIST   = 250,     -- finishing a run in the car
    PER_BAG     = 60,      -- each secured bag (whole crew gets it)
    STEALTH     = 150,
    LEVEL_BASE  = 400,     -- XP to go from level L to L+1 = LEVEL_BASE * L
}

-- ───── Shop: gear (passive perks, bought once, kept forever) ─────
Constants.GEAR = {
    { id = "Sneakers",  name = "Silent Sneakers", price = 1500, blurb = "+2 walk speed" },
    { id = "Lockpick",  name = "Pro Lockpick",    price = 2500, blurb = "Crack vaults 30% faster" },
    { id = "Duffel",    name = "Tactical Duffel", price = 4000, blurb = "Half the bag slowdown" },
    { id = "Jammer",    name = "Signal Jammer",   price = 6000, blurb = "Cameras take twice as long to spot you" },
    { id = "Thermal",   name = "Thermal Goggles", price = 9000, blurb = "See guards through walls" },
}

-- ───── Shop: masks (worn automatically when a job starts) ─────
-- All are Roblox-made catalog accessories (InsertService can load them).
Constants.MASKS = {
    { id = "Bandit",    assetId = 93050572,   name = "Bandit",          price = 0 },
    { id = "Goalie",    assetId = 22151737,   name = "Goalie",          price = 1500 },
    { id = "Owl",       assetId = 28944404,   name = "Night Owl",       price = 3000 },
    { id = "Kitsune",   assetId = 3210207381, name = "Kitsune",         price = 5000 },
    { id = "Pixel",     assetId = 1744163817, name = "8-Bit Skull",     price = 7500 },
    { id = "Catrina",   assetId = 2528067691, name = "Catrina",         price = 10000 },
    { id = "Mystery",   assetId = 125377979,  name = "Mystery",         price = 15000 },
    { id = "Cyber",     assetId = 7466060125, name = "Cyber",           price = 25000 },
}

-- ───── Codes (promo codes → cash, once per player) ─────
Constants.CODES = {
    HEISTCREW = 2500,
    NEONMIAMI = 5000,
    VILLAROSA = 1500,
}

-- ───── Daily reward: day N of a streak pays DAILY_BASE * N (caps at 7) ─────
Constants.DAILY_BASE = 500

-- ───── Monetization ─────
-- ⚠️ 0 = NOT CREATED YET. Malachi creates these in the Creator Dashboard
-- (Monetization → Passes), then pastes the id here. Code is inert until then.
Constants.GAMEPASSES = {
    VIP = 0,          -- +10% on every payout, gold name on the TV
}
Constants.VIP_MULTIPLIER = 1.10

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
