# Heist Crew v2.0 "BIGGER" — build spec

> Written 2026-09-25 when Malachi said *"I love all of that, do it all in one go, no stops, lock in."*
> This is the contract every agent builds against. **v1 rules still apply** (`docs/V1_SPEC.md` §0, §2–§5,
> and `docs/ART_DIRECTION.md`). Where this file and V1 disagree, this file wins.

## Why (Malachi's playtest, 2026-09-25)
Screen recording `_recordings/roblox.mp4`: busted 6 seconds in, cramped rooms, "isn't playable",
"needs to be bigger", "doesn't feel like a Roblox game", "when one guard sees you they all come running,
it's confusing". **The bar: a 7-year-old understands it, and it looks like a REAL place** — not "outside
some weird stuff". Every place you spawn or drop in must look like a believable, finished room.

## 0. House rules (all agents)
- Luau ModuleScripts. **CRLF** line endings: after writing a file run `sed -i 's/\r$//; s/$/\r/' <file>`.
- **Must parse:** `~/.claude/bin/luau-compile --null <file>` exits 0. Run `bash tools/check.sh` (from the
  project root) before you finish — it checks every file.
- **Only edit the files you own** (§9). Need something from another file? Put it in your final report under
  "NEEDS FROM OTHERS" with exact function names — the integrator (Claude) wires it.
- **Do NOT edit** `init.server.lua`, `init.client.lua`, `Constants.lua` (except the core agent),
  `Remotes.lua`. Remote names you may use are in §3 (already registered).
- **Do NOT git commit / push.** The integrator commits.
- New client modules: return a table with `:start()` (the bootstrap calls it in a pcall). New server
  services: expose `:init(deps)` and document it at the top of the file.
- Builders = geometry + refs only (no Scripts, no gameplay). Anchor static parts. Real Materials. Neon only on
  thin accents. Text on SurfaceGuis, never floating (one exception: short NPC speech bubbles).
- Kenney props: `KenneyLoader.placeMany({{kit=, name=, pos=, facing=}}, folder)`; names must exist in
  `shared/KenneyAssets.lua` (read it).
- Sounds: only use built-in `rbxasset://sounds/...` paths or well-known public Roblox sound ids; wrap
  anything id-based so a failed load never errors.

## 1. World map v2 (studs; +Z = south, −Z = north; ground y=0, floors y=0.5) — all in `Constants.WORLD`
**Roblox scale, not real scale** (the camera sits behind you): halls **10–12 wide**, doorways **≥ 7 wide,
10–11 tall**, ceilings **14–18**, rooms **≥ 20×20**.

| Thing | Where |
|---|---|
| Safehouse / auto shop (exists) | x −24..24, z 4..40 |
| The Vault club HQ (exists, underground) | x −44..44, z 0..64, floor y −27.5 |
| Ocean Drive | asphalt z −22..−6, x −150..150. Sidewalks to z −26.6 (N) and z −1.4 (S) |
| **Villa Rosa** (job) | **x −42..42, z −96..−38**. Front door x 0 at z −38. Garden z −38..−26.6. Back terrace z −102..−96 |
| **Diamond Dolls** (job) | **x −82..−46, z −1..35**, shopfront faces NORTH (z −1) |
| **Sunny's Mart** (NEW warm-up job) | **x 50..74, z 1..25**, front faces NORTH (z 1) |
| **Ocean Bank** (NEW big job) | **x 84..140, z 1..55**, front faces NORTH (z 1) |
| **Police station + jail** (NEW) | **x −104..−80, z −52..−28**, front faces SOUTH onto the street |
| Beach sand | **z −102..−122**; ocean north of z −118 |
| Marina drop-off | ring **(106, 0, −110)**, r 14; pier x 100..106 from z −114 north |
| Route to marina | **keep x 94..122, z −26..−104 clear** |
| North-side deco lots (front z −28, depth ≤ 22) | centres x **−62 (w 22), 62 (w 22)**, plus anything west of x −110 |
| South-side deco lots (front z 1) | centre x **−116 (w 24)**. Keep **x 28..48, z −2..20 clear** (car alley) |
| Getaway parking (per job) | villa (−40, 0, −18) · jewelry (−40, 0, −10) · mart (44, 0, −10) · bank (80, 0, −10), facing +X |

## 2. New attributes + tags
| Name | On | Set by | Meaning |
|---|---|---|---|
| `Crouching` (bool) | Player | FeelService (from `Crouch` remote) | sneaking: slower walk, guards take 2× longer |
| `Hidden` (bool) | Player | HideService | inside a hide spot: guards + cameras can't see you |
| `InShadow` (bool) | Player | FeelService (touching a ShadowZone) | guards take 1.6× longer |
| `Jailed` (bool) | Player | JailService | in a cell; a teammate can break you out |
| `IsBot` (bool) | bot Model | BotService | AI crewmate |
| Tag **`HideSpot`** | BasePart | job builders | a closet / big plant / laundry cart you can hide in. Attribute `Label` (e.g. "Closet") |
| Tag **`ShadowZone`** | BasePart (invisible, CanCollide/CanQuery/CanTouch=false) | job builders | dark area |
| Tag **`Vent`** | BasePart | job builders | the entry/exit panel of a crawl vent (both ends get one). Attribute `Pair` = name of the other end |

## 3. Remotes (already registered in `shared/Remotes.lua`)
`FeelFX` S→C `{kind="cash"|"loot"|"load"|"sound"|"big", amount, pos, sound, text}` ·
`Crouch` C→S `(on)` · `Hide` S→C `{hidden, spot}` · `Portal` S→C `{portals={[jobId]={count,needed,launchAt,locked}}}` ·
`IntroCam` S→C `{points={CFrame...}}` · `DailyReward` RemoteFunction `("status"|"claim")` →
`{ok, day, amount, nextAt, msg}` · `Jail` S→C `{jailed, freeAt}` · `Leaderboard` S→C `{rows={{name,cash,heists}}}`.

## 4. JobRefs v2 (what a job builder returns — v1 §4 fields plus:)
```lua
sneakIn   = { at = Vector3, face = Vector3, spread = Vector3 },  -- INSIDE the building, a real room, no guard/camera on it
entrances = { { kind = "front"|"side"|"roof", at = Vector3, label = "Front door" }, ... }  -- 3 ways in
hideSpots = { BasePart, ... },      -- also tagged HideSpot
shadowZones = { BasePart, ... },    -- also tagged ShadowZone
vents = { { a = BasePart, b = BasePart }, ... },  -- crawl vents: prompt at a teleports to b and back
```
- **3 ways in:** front (loud/obvious), side service door (sneaky — this is where `sneakIn` is), roof (ladder
  outside + roof hatch → drop inside; hard but secret).
- **Easy → hard going in:** outer rooms small loot + few guards; the vault core has the big loot + most security.
- **Loops not dead ends**; **cover** (desks, crates, couches) every ~10 studs; **shadow zones** in corners and
  unlit corridors; **2–4 hide spots** per heist; **1–2 vents**.
- Jobs without a keycard or lasers return `keycardDoors = {}`, `keycardSpots = {}`, `laserRows = {}`.
- Guard routes: straight `a`↔`b` lines, ≥ 2 studs clear of props, **never through the `sneakIn` room**.

## 5. Jobs (`Constants.JOBS` — core agent)
| id | name | builder | difficulty | guards | notes |
|---|---|---|---|---|---|
| `mart` | SUNNY'S MART | `MartBuilder` | 1 | 1 | **warm-up**: 1 guard, 1 camera, back-office safe, no keycard, no lasers. Teaches the game |
| `villa` | VILLA ROSA | `VillaBuilder` | 2 | 3 | stealth |
| `jewelry` | DIAMOND DOLLS | `JewelryBuilder` | 3 | 2 | loud, silent alarm |
| `bank` | OCEAN BANK | `BankBuilder` | 4 | 4 | the big one: lobby, teller line, offices, keycard, lasers, huge round vault |
All `unlockLevel = 1` for now (Malachi is testing everything). Briefings: 7-year-old words.

## 6. Game rules v2 (core agent)
- **Guard sees/grabs you → back to the sneakIn door** (v1.2.5 `kickBack`). Cameras/lasers → alarm + police.
- **Police grab you → jail** (police station cell), not "out". A teammate holds E at your cell door to free you
  (you respawn at the job's sneakIn). Solo/nobody frees you in 30 s → released to the club, out of this run.
- **Auto-role:** anyone launching with no role gets a free one.
- **Portals** replace "ready up" as the way to start: stand in a heist's portal in the club; countdown when
  everyone in the server is in the same portal (5 s) or half the server is (15 s). The holo table + Boss stay
  for the plan.
- **Bots:** when the crew is < 3 players, BotService spawns AI crewmates (1–2) at the drop-in. A bot follows
  its player; hold E on it ("Give bag") and it walks the bag to the getaway car and loads it. Guards ignore bots.

## 7. Club / lobby (lobby agent) — `ClubBuilder:build` returns, in addition to v1.2 refs:
```lua
spawnPads = { SpawnLocation, ... },     -- 4+, Neutral, Duration = 5 (built-in ForceField = spawn protection)
portals = { [jobId] = { zone = BasePart (trigger volume, CanCollide=false), setState = function(count, needed, launchIn, locked) end } },
leaderboardAnchor = CFrame,             -- a wall spot; progression agent's board is placed here (face -Z of CFrame = readable side)
introPath = { CFrame, ... },            -- 4–6 camera keyframes for the first-join fly-over
```

## 8. World (world agent) — `MiamiBuilder:build(folder)` RETURNS:
```lua
{ jail = { cells = { { inside = CFrame, door = BasePart } , ... (3+) }, release = CFrame } }
```
`AmbientService:start(folder)` (new server file) drives traffic cars + walking pedestrians (client-cheap:
server tweens on anchored models, low count: ≤ 6 cars, ≤ 10 people). Cars stay in their lanes and stop well
clear of the getaway spots; nobody walks into job interiors.

## 9. Who owns what (v2)
| Agent | Files (create or edit) |
|---|---|
| villa | `server/VillaBuilder.lua` |
| jewelry | `server/JewelryBuilder.lua`, `server/MartBuilder.lua` (new) |
| bank | `server/BankBuilder.lua` (new) |
| world | `server/MiamiBuilder.lua`, `server/AmbientService.lua` (new) |
| feel | `server/GuardService.lua`, `server/FeelService.lua` (new), `server/HideService.lua` (new), `client/FeelFX.lua` (new), `client/CrouchController.lua` (new), `client/DetectionHud.lua` |
| lobby | `server/ClubBuilder.lua`, `server/SafehouseBuilder.lua`, `client/ClubFX.lua`, `client/IntroCam.lua` (new), `client/PortalHud.lua` (new), `client/CrewHud.lua`, `client/TipHud.lua`, `client/BriefingUI.lua`, `client/WaypointHud.lua` |
| progression | `server/PlayerDataService.lua`, `server/ShopService.lua`, `client/ShopUI.lua`, `server/VehicleService.lua`, `server/DailyRewardService.lua` (new), `client/DailyRewardUI.lua` (new), `server/LeaderboardService.lua` (new), `server/CosmeticsService.lua` (new) |
| core | `shared/Constants.lua`, `server/JobService.lua`, `server/LootService.lua`, `server/SecurityService.lua`, `server/PoliceService.lua`, `server/CrewService.lua`, `server/HeistBuilder.lua`, `server/PortalService.lua` (new), `server/JailService.lua` (new), `server/BotService.lua` (new), `client/JobHud.lua`, `client/PayoutScreen.lua` |
| integrator (Claude) | `init.server.lua`, `init.client.lua`, `Remotes.lua`, docs, git |
