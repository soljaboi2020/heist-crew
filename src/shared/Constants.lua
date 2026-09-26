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
Constants.VERSION      = "2.0.0"
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

    -- v1.2 "THE VAULT": the underground club HQ under the auto shop. You spawn
    -- here. x -44..44, z 0..64, floor top y -27.5, ceiling y -3.5 (the lawn is y -2..0).
    HUB_FLOOR              = -27.5,
    HUB_CENTER             = {x = 0,  y = -27.5, z = 32},
    HUB_HALF_WIDTH         = 44,
    HUB_HALF_DEPTH         = 32,
    HUB_HEIGHT             = 24,
    HUB_TABLE              = {x = 0,  y = -27.5, z = 38},   -- holo planning table (centre)
    HUB_ELEVATOR           = {x = 12, y = -27.5, z = 60},   -- freight lift up to the auto shop
    SAFEHOUSE_ELEVATOR     = {x = 0,  y = 0.5,   z = 22},   -- freight lift down (in the auto shop)

    -- Spawn — inside The Vault, south end, facing north toward the holo table + DJ stage
    SPAWN_POSITION         = {x = 0,  y = -27.4, z = 54},

    -- The safehouse (warehouse / "Riverside Auto Body"). Garage in the NORTH wall.
    SAFEHOUSE_CENTER       = {x = 0,  y = 0,    z = 22},
    SAFEHOUSE_HALF_WIDTH   = 24,
    SAFEHOUSE_HALF_DEPTH   = 18,
    SAFEHOUSE_HEIGHT       = 16,
    GARAGE_WIDTH           = 18,
    GARAGE_HEIGHT          = 12,
    BOSS_NPC_POS           = {x = 7,  y = -28,  z = 41},   -- at the holo table (y = floor - 0.5)

    -- Ocean Drive: the street (runs east-west)
    STREET_Z               = -14,
    STREET_HALF_WIDTH      = 8,
    STREET_LENGTH          = 300,     -- x -150..150

    -- Villa Rosa (job 1) — beachfront art-deco villa, north of the street
    -- v2.0 "BIGGER": the villa grew to x -42..42, z -96..-38 (docs/V2_SPEC.md §1)
    MANSION_CENTER         = {x = 0,  y = 0,    z = -67},
    MANSION_HALF_WIDTH     = 42,
    MANSION_HALF_DEPTH     = 29,      -- z -96..-38, front door at z -38
    MANSION_WALL_HEIGHT    = 16,
    MANSION_DOOR_WIDTH     = 10,

    -- Diamond Dolls Jewelers (job 2) — storefront on the south side of the street
    JEWELRY_CENTER         = {x = -64, y = 0,   z = 17},
    JEWELRY_HALF_WIDTH     = 18,      -- x -82..-46 (v2.0: was 24 wide)
    JEWELRY_HALF_DEPTH     = 18,      -- z -1..35, shopfront faces north (z -1)

    -- v2.0 new jobs + buildings (docs/V2_SPEC.md §1)
    MART_CENTER            = {x = 62, y = 0,   z = 13},   -- Sunny's Mart (warm-up): front line z 1 (= z - HALF_DEPTH), x 50..74; v3.3 the building runs back to z 33.5 (x 48..74) + yard x 74..83.7
    MART_HALF_WIDTH        = 12,
    MART_HALF_DEPTH        = 12,
    BANK_CENTER            = {x = 112, y = 0,  z = 28},   -- Ocean Bank x 84..140, z 1..55, front faces north
    BANK_HALF_WIDTH        = 28,
    BANK_HALF_DEPTH        = 27,
    POLICE_STATION_CENTER  = {x = -92, y = 0,  z = -40},  -- north side, x -104..-80, z -52..-28, front faces south
    POLICE_STATION_HALF_WIDTH = 12,
    POLICE_STATION_HALF_DEPTH = 12,

    -- Beach + ocean (Terrain)
    BEACH_Z0               = -102,    -- sand from here north... (v2.0: was -88)
    BEACH_Z1               = -122,    -- ...to here, then water (v2.0: was -108)
    OCEAN_SURFACE_Y        = -0.6,

    -- The old marina drop-off (v3.0: nobody drives there any more — the getaway is a
    -- cut-scene; MiamiBuilder keeps the pier + boat here as decor for the Boat escape)
    DROPOFF                = {x = 106, y = 0,   z = -110},   -- v2.0: was z -96 (beach moved north)
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
    { id = "Driver",  color = {251, 191, 36},  blurb = "Getaway pro: picks the escape",
      perks = "Getaway pro: your escape vote counts x2 · +5% getaway cash for the crew" },
    { id = "Lookout", color = {74, 222, 128},  blurb = "Spots guards through walls",
      perks = "Sees guards + cameras through walls · Q marks them for the crew" },
}


-- ───── Jobs (v1.0, v2.0 "BIGGER") ─────
-- Each job has a builder (geometry → JobRefs, see docs/V1_SPEC.md §4 + V2_SPEC.md §4)
-- and is run by JobService. Only the SELECTED job is armed; the others show CLOSED.
-- Order here = order in the club (portals, "pick heist" cycling): easy → hard.
--   vaultNoun  what the drill goes on ("Vault" / "Safe") — HUD + prompts
--   doorLabel  the keycard-door step, if the job has keycard doors
--   drillTime  seconds the drill needs (no jams counted)
-- (v2.0) Every briefing is written so a 7-year-old gets it. Keep it that way.
Constants.JOBS = {
    {
        id = "mart", name = "SUNNY'S MART", tagline = "A little corner store. Your first job!",
        difficulty = 1, unlockLevel = 1, guards = 1,
        alarmTimer = 90,
        stealthBonus = 0.25,
        vaultNoun = "Safe", drillTime = 12,
        warmup = true,
        -- (v3.3 SLICE) one goal at a time: camera → safe → cash in the car → GO!
        -- Boss lines are matched to briefing shots by keyword (BriefingUI):
        -- camera/breaker → breaker · safe/drill → the safe · car → the car.
        briefing = {
            "This is Sunny's Mart. A little corner store. Your first job!",
            "You start outside on the sidewalk. No masks yet, so walk in like a normal shopper.",
            "Job 1: the breaker box is in the stock room at the back. Turn it off and the camera goes dark!",
            "There is 1 guard. He walks by the registers. Once your mask is on, stay out of his light!",
            "Job 2: put the drill on the safe in the office. If it gets stuck, hold E to fix it.",
            "Job 3: bag the cash and put it in the car out back. Then hop in and press GO!",
            "Extra cash if you want it: the registers, the lotto tickets and the ATM. But the guard is watching!",
        },
        -- (v3.3 SLICE) the goal words on the objective bar (JobService SLICE_WORDS keys)
        goals = {
            cameras = "Turn off the camera (breaker in the back)",
            safe = "Crack the safe in the office",
            loot = "Bag the safe cash + load the car  %d/%d",
            car = "Hop in the car + press GO!",
        },
    },
    {
        id = "villa", name = "VILLA ROSA", tagline = "Beachfront villa. Stealth pays.",
        difficulty = 2, unlockLevel = 1, guards = 3,
        alarmTimer = 90,           -- seconds to load the car and escape (GO!) once the alarm trips
        stealthBonus = 0.25,       -- +25% of the take if the alarm never trips
        vaultNoun = "Vault", doorLabel = "Open the locked vault door", drillTime = 24,
        briefing = {
            -- (v3.4) the same numbered steps the objective bar shows (one goal at a time).
            -- BriefingUI picks each line's camera shot by its first keyword (camera/breaker,
            -- keycard/locked, laser, vault/drill/safe, car, door/sneak), so word them on purpose.
            "This job is Villa Rosa. A rich guy's beach house. He's on vacation, and his vault is full of money!",
            "You sneak in the staff door. Look around first, then press M to MASK UP!",
            "Step 1: find the breaker in the security room. It turns the cameras off, so they can't see you!",
            "Step 2: find the keycard. It hides in a different room every time, so follow the gold markers!",
            "Step 3: swipe it to open the locked door.",
            "Red lasers blink on and off. Walk through when they turn off!",
            "Step 4: put the drill on the vault. If it gets stuck, hold E to fix it.",
            "Step 5: put the money bags in the car, hop in and press GO!",
            "Watch out for guards! If one sees you, you go back to the door. Press C to crouch and sneak.",
        },
    },
    {
        id = "jewelry", name = "DIAMOND DOLLS", tagline = "Smash, grab, go. Silent alarm.",
        difficulty = 3, unlockLevel = 1, guards = 2,
        alarmTimer = 75,
        stealthBonus = 0.15,
        silentAlarmDelay = 45,     -- first smashed case starts a hidden clock; police roll after this
        vaultNoun = "Safe", doorLabel = "Open the back room door", drillTime = 20,
        briefing = {
            -- (v3.4) the same numbered steps the objective bar shows (one goal at a time).
            -- BriefingUI picks each line's camera shot by its first keyword (camera/breaker,
            -- keycard/locked, laser, vault/drill/safe, car, door/sneak), so word them on purpose.
            "This job is Diamond Dolls. It's a jewelry store full of shiny stuff!",
            "Walk in the front like a shopper. Look around, then press M to MASK UP!",
            "Step 1: the breaker is in the back closet. Turn the cameras off!",
            "Step 2: find the keycard. Follow the gold markers!",
            "Step 3: swipe it to open the locked back room.",
            "Red lasers blink on and off. Walk through when they turn off!",
            "Step 4: drill the safe. If it gets stuck, hold E to fix it.",
            "Step 5: put the money bags in the car, hop in and press GO!",
            "Bonus: the glass cases are full of jewels. But smashing one secretly calls the police, so do it last!",
        },
    },
    {
        id = "bank", name = "OCEAN BANK", tagline = "The big one. The biggest vault in Miami.",
        difficulty = 4, unlockLevel = 1, guards = 4,
        alarmTimer = 120,
        stealthBonus = 0.3,
        vaultNoun = "Vault", doorLabel = "Open the vault hallway door", drillTime = 30,
        briefing = {
            -- (v3.4) the same numbered steps the objective bar shows (one goal at a time).
            -- BriefingUI picks each line's camera shot by its first keyword (camera/breaker,
            -- keycard/locked, laser, vault/drill/safe, car, door/sneak), so word them on purpose.
            "This is Ocean Bank. The biggest vault in Miami, full of gold and money!",
            "Walk in the front like a customer. Look around, then press M to MASK UP!",
            "Step 1: find the breaker in the security room. It turns the cameras off!",
            "Step 2: find the keycard. Follow the gold markers!",
            "Step 3: swipe it to open the locked vault hallway.",
            "Red lasers blink on and off. Walk through when they turn off!",
            "Step 4: put the drill on the big round vault. If it gets stuck, hold E to fix it.",
            "Step 5: put the money bags in the car, hop in and press GO!",
            "If the police catch you, you go to jail. A friend can break you out!",
        },
    },
}

-- (v2.0) Jail: a cop grabbing you puts you in a cell at the police station.
Constants.JAIL = {
    TIME          = 30,    -- seconds before you're released to the club (out of this run)
    BREAKOUT_HOLD = 2,     -- seconds a teammate holds E at your cell door
}

-- (v2.0) Portals in the club: stand in one to pick that heist and get ready.
Constants.PORTAL = {
    ALL_COUNTDOWN  = 5,    -- everyone in the server is in the same portal
    HALF_COUNTDOWN = 15,   -- at least half of the server is
}

-- (v2.0) Bot crewmates when the crew is small.
Constants.BOTS = {
    CREW_TARGET   = 3,     -- bots fill the crew up to this many (real players + bots)
    MAX           = 2,
    FOLLOW_DIST   = 6,     -- studs behind their player
    CATCH_UP_DIST = 60,    -- further than this = teleport to their player
    NAMES         = { "Rex", "Pip", "Nova", "Taco" },
}

-- Loot kinds. value = cash added to the crew's take when the bag is secured.
-- speed = WalkSpeed while carrying (Muscle ignores it). Default WalkSpeed is 16.
-- v3.0 "THE SCORE" (LOOT-CORE, docs/V3_SPEC.md §2.2): every kind also has
--   name      what the HUD / prompts / pops call it (kid words)
--   heavy     needs TWO people to carry ("Lift together"), or the Muscle alone
--   fragile   loses value when bumped (running > 2 s, grabbed, thrown, falling)
--   interact  default mini-game before it bags ("cut"|"dial"|"stuff"|"unscrew"|"drill").
--             A builder's lootSpot.interact wins; lootSpot.interact = false = plain hold E.
--   deposit   contents are rolled when you open it (Constants.LOOT_V3.DEPOSIT_BOX)
--   heavy/fragile on the lootSpot win over the kind's flag too.
Constants.LOOT = {
    Cash     = { value = 1000, speed = 13, color = {74, 222, 128},  name = "Cash" },
    Gold     = { value = 1500, speed = 10, color = {251, 191, 36},  name = "Gold" },
    Diamonds = { value = 2500, speed = 12, color = {125, 211, 252}, name = "Diamonds" },
    Jewels   = { value = 900,  speed = 14, color = {244, 114, 182}, name = "Jewels" },
    Art      = { value = 2000, speed = 11, color = {196, 181, 253}, name = "Painting" },
    -- v2.0 new jobs
    Register = { value = 400,  speed = 15, color = {134, 239, 172}, name = "Register Cash", interact = "stuff" },  -- mart cash register
    Lottery  = { value = 300,  speed = 15, color = {253, 186, 116}, name = "Lottery Tickets" },                  -- mart scratch tickets
    Bonds    = { value = 3000, speed = 12, color = {165, 243, 252}, name = "Bonds" },                            -- bank bearer bonds
    GoldBars = { value = 4000, speed = 9,  color = {250, 204, 21},  name = "Gold Bars", heavy = true },          -- bank vault gold

    -- ── v3.0 themed loot ──
    -- Villa Rosa
    Painting     = { value = 3000, speed = 12, color = {196, 181, 253}, name = "Painting", interact = "cut" },
    GoldRecord   = { value = 1800, speed = 14, color = {250, 204, 21},  name = "Gold Record" },
    GoldFlamingo = { value = 7500, speed = 9,  color = {255, 150, 200}, name = "Golden Flamingo", heavy = true },   -- TARGET
    Wine         = { value = 1600, speed = 14, color = {170, 40, 80},   name = "Fancy Wine", fragile = true },
    JewelryBox   = { value = 2200, speed = 14, color = {244, 114, 182}, name = "Jewelry Box", interact = "dial" },
    -- Diamond Dolls
    Necklace     = { value = 1800, speed = 15, color = {226, 232, 240}, name = "Necklace", interact = "unscrew" },
    Watch        = { value = 1200, speed = 15, color = {253, 224, 71},  name = "Gold Watch" },
    PinkDiamond  = { value = 9000, speed = 13, color = {255, 120, 200}, name = "Pink Diamond" },                  -- TARGET
    -- Sunny's Mart
    ScratchTickets = { value = 250,  speed = 15, color = {253, 186, 116}, name = "Scratch Tickets" },
    ATMCash      = { value = 1500, speed = 14, color = {74, 222, 128},  name = "ATM Cash", interact = "drill" },
    SafeCash     = { value = 1200, speed = 14, color = {74, 222, 128},  name = "Safe Cash", interact = "dial" },
    GoldenTicket = { value = 3000, speed = 15, color = {252, 211, 77},  name = "Golden Ticket" },                 -- TARGET
    -- Ocean Bank
    MoneyCart    = { value = 6000, speed = 9,  color = {74, 222, 128},  name = "Money Cart", heavy = true },
    DepositBox   = { value = 1200, speed = 14, color = {203, 213, 225}, name = "Deposit Box", deposit = true },   -- value = a rough guess; real value rolled
    CrownJewel   = { value = 12000, speed = 12, color = {192, 132, 252}, name = "Crown Jewel" },                  -- TARGET
    -- any job: the ~1-in-20 secret stash
    SecretStash  = { value = 4000, speed = 13, color = {45, 212, 191},  name = "Secret Stash" },
}
-- Anything a builder names that isn't listed above still pays this (never $0).
Constants.LOOT_DEFAULT = { value = 500, speed = 13, color = {226, 232, 240}, name = "Loot" }

-- ───── v3.0 "THE SCORE" loot rules (LOOT-CORE: LootService / LootShuffle / TargetService) ─────
-- Words are for a 7-year-old. Keep them that way.
Constants.LOOT_V3 = {
    -- §2.3 shuffle: each run only SOME spots in a pool are out; one pool is the JACKPOT room
    SHUFFLE_ACTIVE  = 0.6,     -- fraction of each pool that is out on a run (at least 1)
    JACKPOT_MULT    = 1.5,     -- every spot in the jackpot room is out and worth x1.5
    HIDDEN_CHANCE   = 1 / 20,  -- a hidden = true spot (secret stash) shows up on ~1 run in 20

    -- §2.5 target (the Boss's named item) — paid to the crew on top of the take
    TARGET_BONUS    = 5000,

    -- §2.5 heavy loot
    HEAVY_SPEED     = 9,       -- both carriers walk this fast (the Muscle alone walks full speed)
    HEAVY_LIFT_WAIT = 10,      -- seconds the first lifter waits for a buddy
    HEAVY_LIFT_NEAR = 12,      -- the buddy must be this close to join / a bot this close helps
    HEAVY_TETHER    = 16,      -- carriers further apart than this for...
    HEAVY_TETHER_TIME = 1.5,   -- ...this long drop it

    -- §2.5 fragile loot
    FRAGILE_LOSS    = 0.25,    -- value lost per bump (of the full value)
    FRAGILE_FLOOR   = 0.25,    -- never worth less than this much of its value (kid-friendly)
    FRAGILE_RUN_SPEED = 10,    -- faster than this counts as running (crouch-walk = 8 = safe)
    FRAGILE_RUN_TIME  = 2,     -- running this long = a bump
    FRAGILE_RECRACK   = 3,     -- after a bump, this long of running before the next one
    FRAGILE_FALL    = 6,       -- falling further than this (studs) = a bump

    -- §2.4 mini-games. `min` = the server's fastest believable finish (too fast = rejected).
    --   prompt = the ProximityPrompt action, title/hint = the mini-game card
    MINIGAMES = {
        cut     = { min = 1.8, prompt = "Cut it out", title = "CUT IT OUT!",   hint = "Trace the frame all the way round" },
        dial    = { min = 1.2, prompt = "Crack it",   title = "CRACK THE DIAL!", hint = "Turn the dial until it CLICKS (3 times)" },
        stuff   = { min = 1.4, prompt = "Grab it",    title = "STUFF THE BAG!", hint = "Tap tap tap as fast as you can!" },
        unscrew = { min = 1.2, prompt = "Unscrew it", title = "UNSCREW THE GLASS!", hint = "Hold each screw and spin it" },
        drill   = { min = 2.2, prompt = "Drill it",   title = "DRILL IT!",     hint = "Wait for the drill. If it jams, TAP it!" },
    },
    MINIGAME_HOLD    = 3,      -- accessibility fallback: hold E / X / the HOLD button this long
    MINIGAME_TIMEOUT = 30,     -- a mini-game left open longer than this is cancelled
    MINIGAME_REACH   = 14,     -- studs from the loot you must still be when you finish

    -- §2.2 Ocean Bank deposit boxes: what's inside (weights add to 100)
    DEPOSIT_BOX = {
        { id = "cash",   weight = 50, name = "Cash",   value = 1200 },
        { id = "jewels", weight = 30, name = "Jewels", value = 2000 },
        { id = "rare",   weight = 15, value = 4500,
          names = { "Old Gold Coin", "Signed Baseball", "Treasure Map", "Tiny Gold Car", "Dino Egg" } },
        { id = "duck",   weight = 5,  name = "Rubber Duck", value = 1,
          line = "QUACK! It's just a rubber duck... worth $1!" },
    },

    -- §2.5 / §4 the Boss's target per job (exactly one per heist)
    TARGETS = {
        mart    = { kind = "GoldenTicket", name = "Golden Ticket",
                    line = "Somewhere in the store is a GOLDEN TICKET. Find it and bring it to me for $5,000 extra!" },
        villa   = { kind = "GoldFlamingo", name = "Golden Flamingo",
                    line = "Bring me the GOLDEN FLAMINGO! It's heavy, so lift it with a buddy (or be the Muscle). $5,000 extra!" },
        jewelry = { kind = "PinkDiamond", name = "Pink Diamond",
                    line = "Bring me the PINK DIAMOND! It spins on its own stand behind lasers. $5,000 extra!" },
        bank    = { kind = "CrownJewel", name = "Crown Jewel",
                    line = "The CROWN JEWEL is locked in the vault. Bring it to me for $5,000 extra!" },
    },
}

-- Security tuning (SecurityService)
Constants.SECURITY = {
    CAMERA_RANGE        = 32,
    CAMERA_HALF_ANGLE   = 24,     -- degrees
    CAMERA_DETECT_TIME  = 1.6,   -- v2.0: was 0.7 (too harsh for a kid game; the jewelry vent exit was in view)    -- seconds in view before the alarm trips
    BREAKER_HOLD        = 3,      -- seconds to cut the cameras (Hacker: 1)
    HACK_DOOR_HOLD      = 4,      -- Hacker opens keycard doors without a card
    LASER_CHECK_RATE    = 0.08,
}

-- Detection: guards/cameras fill a meter before the alarm (v1.1) — seeing you
-- up close fills it fast, at the edge of their vision it fills slowly.
Constants.DETECTION = {
    -- (v1.2.4) was 0.4 / 1.4 -- Malachi got busted 6s into his first run. Now you
    -- get a real moment to duck out of sight.
    GUARD_NEAR_TIME = 1.2,    -- seconds to spot you at point-blank
    GUARD_FAR_TIME  = 3.0,    -- seconds to spot you at the edge of vision
    DROP_IN_GRACE   = 8,      -- seconds after the drop-in when guards can't spot anyone
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
-- (v2.0 masks agent) Every mask has a POWER while you wear it in a heist
-- (MaskService). `ability.id` is what MaskService:has(player, id) checks and what
-- the player attribute `MaskPower` holds (the HUD shows `name` + `desc`).
-- Words are for a 7-year-old. Keep them that way.
Constants.MASKS = {
    { id = "Bandit",    assetId = 93050572,   name = "Bandit",          price = 0,
      ability = { id = "lucky",       name = "LUCKY",       desc = "+10% cash from every bag" } },
    { id = "Goalie",    assetId = 22151737,   name = "Goalie",          price = 1500,
      ability = { id = "toughguy",    name = "TOUGH GUY",   desc = "The first time a guard catches you, you break free!" } },
    { id = "Owl",       assetId = 28944404,   name = "Night Owl",       price = 3000,
      ability = { id = "nightvision", name = "NIGHT VISION", desc = "Dark spots hide you even better" } },
    -- (v3.0.1) was Roblox "Kitsune Mask" 3210207381 — a SIDE-worn mask, sat on the side of the head.
    -- Now the Roblox "Steampunk Fox Mask" (covers the face). Same id so owners keep it.
    { id = "Kitsune",   assetId = 2830768205, name = "Steam Fox",         price = 5000,
      ability = { id = "foxspeed",    name = "FOX SPEED",   desc = "You run 20% faster" } },
    { id = "Pixel",     assetId = 1744163817, name = "8-Bit Skull",     price = 7500,
      ability = { id = "powerthrow",  name = "POWER THROW", desc = "Throw bags twice as far" } },
    { id = "Catrina",   assetId = 2528067691, name = "Catrina",         price = 10000,
      ability = { id = "ghost",       name = "GHOST",       desc = "Cameras take 2x longer to see you" } },
    { id = "Mystery",   assetId = 125377979,  name = "Mystery",         price = 15000,
      ability = { id = "surprise",    name = "SURPRISE!",   desc = "A random power every heist!" } },
    { id = "Cyber",     assetId = 7466060125, name = "Cyber",           price = 25000,
      ability = { id = "hackchip",    name = "HACK CHIP",   desc = "Cut cameras and hack keypads 2x faster" } },
}

-- Tuning for the mask powers (MaskService + the small hooks in Guard/Security/Loot/JobService)
Constants.MASK_POWERS = {
    LUCKY_BONUS      = 0.10,   -- lucky: +10% of the crew's take, paid to you on top
    NIGHT_SHADOW     = 2.0,    -- nightvision: shadow zones slow guards 2x (normal 1.6x)
    FOX_SPEED        = 1.20,   -- foxspeed: WalkSpeed x1.2 (attribute SpeedMult)
    THROW_MULT       = 2.0,    -- powerthrow: bag flies twice as far
    GHOST_CAMERA     = 0.5,    -- ghost: camera meter fills at half speed (2x longer)
    HACK_SPEED       = 2.0,    -- hackchip: breaker + keypad holds finish in half the time
}

-- ───── Robux → cash packs (Developer Products, RobuxService) ─────
-- ⚠️ productId 0 = NOT CREATED YET (the pack is hidden / can't be bought).
-- How to create them: see the header of src/server/RobuxService.lua.
-- Developer Products created 2026-09-25 on universe 10127256584 (Open Cloud, key in ~/.claude/roblox-opencloud-key)
Constants.ROBUX_PACKS = {
    { id = "small",  name = "Pocket Cash",  cash = 5000,   robux = 25,  productId = 3714635306 },
    { id = "medium", name = "Bag of Cash",  cash = 30000,  robux = 99,  productId = 3714635777 },
    { id = "large",  name = "Cash Stack",   cash = 100000, robux = 249, productId = 3714635779 },
    { id = "huge",   name = "Money Truck",  cash = 500000, robux = 799, productId = 3714635781 },
}

-- ───── Trophy room (v1.2): unlocks by the best heistsCompleted in the server ─────
Constants.TROPHIES = {
    { at = 1,  name = "FIRST SCORE",   blurb = "A single gold bar" },
    { at = 2,  name = "BANKROLL",      blurb = "Stacks of cash" },
    { at = 3,  name = "ICE",           blurb = "The Villa Rosa diamond" },
    { at = 5,  name = "THE MASTERPIECE", blurb = "A painting nobody reported stolen" },
    { at = 10, name = "LEGEND",        blurb = "The golden bear" },
}

-- ───── Codes (promo codes → cash, once per player) ─────
Constants.CODES = {
    HEISTCREW = 2500,
    NEONMIAMI = 5000,
    VILLAROSA = 1500,
}


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

-- ───── (v3.2) HEIST STARS: 3 per heist (JobService finish → PlayerDataService) ─────
-- ⭐ no alarm (stealth) · ⭐ every bag of the job in the trunk · ⭐ fast (the getaway
-- started before PAR seconds). Only a WIN with cash in the car earns stars.
-- Best stars per job are saved (bestStars / totalStars); total stars open the doors.
Constants.STARS = {
    PAR = { mart = 150, villa = 300, jewelry = 240, bank = 420 },   -- seconds (drop-in → GO!)
    PAR_DEFAULT = 300,
    -- total stars (best per job, summed) needed to open a heist door. Old saves that
    -- already finished a heist keep everything open (unlockAll, PlayerDataService migrate).
    UNLOCK = { mart = 0, villa = 1, jewelry = 3, bank = 6 },
}

-- ───── (v3.2) HOT STREAK: consecutive good heists → bigger take ─────
-- A win with cash in the car → +1 level (cap MAX). The bonus is paid on the NEXT
-- heist: PER_LEVEL x the level you came in with, on the bags' cash (take).
-- Fail / busted / timeout / caught / leaving mid-run → -1 level (never straight to 0).
-- An empty-car win changes nothing.
Constants.STREAK = {
    MAX = 5,
    PER_LEVEL = 0.10,
}

-- ───── Sound IDs (Roblox marketplace assets — known free) ─────
Constants.SOUNDS = {
    LOBBY_AMBIENT = "rbxassetid://1846431634",  -- (v3.0.1) APM "Miami Nights A" (old id was not audio)  -- chill background loop
    ALARM         = "rbxassetid://138081509",   -- police siren / klaxon
    CASH_CHA_CHING = "rbxassetid://131886985",  -- cash register
    VAULT_CRACK   = "rbxassetid://3744371091",  -- mechanical click
    HEIST_WIN     = "rbxasset://sounds/victory.wav",  -- (v3.0.1) built-in  -- triumphant sting
    HEIST_FAIL    = "rbxassetid://116298781032555",  -- (v3.0.1) sad trombone (verified loads)  -- fail buzzer
}

return Constants
