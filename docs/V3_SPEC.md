# Heist Crew v3.0 "THE SCORE" — getaway cinematics + creative loot

> 2026-09-25. Malachi: *"do everything you just named except the hybrid thing, in one go."*
> V2_SPEC house rules still apply (§0: CRLF, `bash tools/check.sh`, only your files, no commits).
> Mock runtime for testing: `/tmp/hcmock` (see its `drv_*.luau` + `bundle.py`).

## 1. The getaway (GETAWAY agent)
- **No driving.** When the crew is done (everyone still in the run is seated in the getaway car, or
  the driver presses **"GO!"** once at least one bag is loaded), the escape plays as a **cut-scene**.
- **Choose your escape** (vote UI while seated, 8 s, majority, ties → Boat):
  - 🚤 **Boat** — always available.
  - 🚁 **Helicopter** — only if **nobody got caught/jailed** this run. **+10% cash.**
  - 🛣️ **Highway** — the car's power on full display. +car bonus ×2.
- **Stealth vs loud:** no alarm → calm cruise (radio, city lights). Alarm → sirens, police chase,
  near-misses, alley cut, roadblock.
- **Car type flavour + a real reward** (cars can't change speed any more, so they pay out):
  Classic +0% · Muscle +5% · Street Racer +8% (leaves cops in the dust) · Armored +8% (cops bounce off)
  · Monster +10% (jumps a police car) · Tank +12% (smashes the roadblock). Applies in loud escapes;
  half of it in stealth escapes.
- Payout screen appears over the final shot (boat speeding away / heli over the ocean / car into the
  highway sunset-at-night).
- The cut-scene is shared: every crew member sees it; the server decides the route + outcome and
  sends one payload; clients play it locally. Skippable per player after 3 s.

## 2. Loot (LOOT-CORE agent + builder agents)
### 2.1 lootSpots v3 (builders return this; v1 fields still valid)
```lua
{ kind = "Painting", cframe = CFrame, visual = Instance,
  interact = nil|"cut"|"dial"|"stuff"|"unscrew"|"drill",  -- mini-game before it bags (nil = hold E like today)
  heavy = false,        -- needs 2 players to carry (Muscle can solo)
  fragile = false,      -- loses value if the carrier sprints/gets grabbed/falls
  hidden = false,       -- secret stash: only spawns on ~1-in-20 runs, visual hidden otherwise
  pool = "a",           -- shuffle group: each run only SOME spots in a pool are active (see §2.3)
  target = nil|"GoldFlamingo"|...,  -- the Boss's named target item for this heist (exactly one per job)
  inVault = true|false }
```
### 2.2 Themed loot kinds (Constants.LOOT — LOOT-CORE owns; builders only reference ids)
| Heist | Kinds |
|---|---|
| Villa | `Painting` (cut) · `GoldRecord` · `GoldFlamingo` (TARGET, heavy) · `Wine` (fragile) · `JewelryBox` (dial, bedroom safe) · vault: `Cash`, `GoldBars` (heavy), `Diamonds` |
| Diamond Dolls | `Necklace` (on display busts, unscrew glass) · `Watch` · `PinkDiamond` (TARGET, own laser cage + spinning pedestal) · `Jewels` (smash cases) · safe: `Diamonds` |
| Sunny's Mart | `Register` (stuff) · `ScratchTickets` · `ATMCash` (drill the ATM) · `SafeCash` (dial, manager's safe) · `Lottery` · TARGET `GoldenTicket` |
| Ocean Bank | `GoldBars` (heavy) · `MoneyCart` (heavy, wheeled) · `DepositBox` ×20 (random contents: cash / jewels / rare collectible / 🦆 rubber duck joke) · `Bonds` · TARGET `CrownJewel` |
| Any (hidden stash) | `SecretStash` behind a painting / under a rug / in a fish tank — ~1 in 20 runs |
### 2.3 Shuffle + jackpot
- Each run, LootService activates a random subset of each `pool` (≈60%) and picks **one "jackpot"
  room** (a pool) where every spot is active and values ×1.5. The Boss's briefing names the target.
### 2.4 Mini-games (client `LootMinigames.lua`, server validates duration/progress)
`cut` trace the frame edge with the mouse/finger · `dial` turn a dial to 3 clicks · `stuff` tap/click
fast to fill a bar · `unscrew` hold + rotate 4 screws · `drill` place drill + wait (reuse vault drill).
All kid-simple, ≤ 6 s, big visuals, with a skip-safe fallback (hold E 3 s) for accessibility.
### 2.5 Rules
- **Heavy:** two players stand at it → both "Carry together" (tethered, both slowed), or Muscle solo.
- **Fragile:** value drops 25% per bump (sprint > 2 s, grabbed, fall > 6 studs); FeelFX "CRACK!".
- **Target:** secured → **+$5,000 bonus** + a trophy on the club trophy wall (per player, saved).
- **Bag fills visually** (the carried bag bulges by value tier; cash bundles stick out).
- **Display:** cash on shrink-wrapped pallets, gold in neat stacks, deposit-box wall with numbered
  doors, money carts on casters — builders make visuals look real (art rules).

## 3. Ownership
| Agent | Files |
|---|---|
| getaway | `server/GetawayService.lua` (new), `server/GetawayProps.lua` (new: helicopter, boat rig, roadblock, chase cars, highway set), `client/GetawayCinematic.lua` (new), `client/GetawayVote.lua` (new), `server/VehicleService.lua`, `server/PoliceService.lua`, `server/JobService.lua` (escape/finish flow + payout bonuses — also wire the LOOT-CORE hooks listed in §4), `client/CarHud.lua`, `client/PayoutScreen.lua` |
| loot-core | `shared/Constants.lua` (LOOT + new LOOT_V3 sections), `server/LootService.lua`, `server/LootShuffle.lua` (new), `server/TargetService.lua` (new), `client/LootMinigames.lua` (new), `client/LootHud.lua`, `server/ClubBuilder.lua` (trophy wall additions only) |
| villa-loot | `server/VillaBuilder.lua` |
| jewelry-mart-loot | `server/JewelryBuilder.lua`, `server/MartBuilder.lua` |
| bank-loot | `server/BankBuilder.lua` |

## 4. Cross-agent hooks (LOOT-CORE exposes, GETAWAY wires into JobService)
- `TargetService:onSecured(player, kind)` / `TargetService:targetFor(jobId)` / `TargetService:bonusFor(run)`
- `LootShuffle:prepare(refs)` at job arm/reset → returns the active spots; JobService/LootService use it.
- `LootService` exposes `valueOf(bag)` (after fragile/jackpot/bag-tier multipliers).
- Briefing: `TargetService:targetFor(jobId)` → `{kind, name, line}`; BriefingUI isn't owned by anyone
  this round — the integrator adds the Boss line.
