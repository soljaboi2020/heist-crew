# Heist Crew v1.0 "Neon Miami" — build spec

> Written 2026-09-25 when Malachi said *"knock everything out in one."* This is the contract
> every module is built against. If code and this doc disagree, fix one of them — don't let
> them drift.

## 0. House rules (every file)

- **Luau, ModuleScripts**, one system per file. Server in `src/server/`, client in
  `src/client/`, shared in `src/shared/`. Bootstraps (`init.server.lua`, `init.client.lua`)
  only `require` + start.
- **CRLF line endings.** After writing a file run `sed -i 's/\r$//; s/$/\r/' <file>` (idempotent).
- **Must compile:** `/tmp/luau/luau-compile --null <file>` must print "Compiled". Also run
  `/tmp/luau/luau-analyze <file>` and fix anything that isn't a Roblox global it doesn't know.
- **Art rules** (`docs/ART_DIRECTION.md`): Neon only on small accents (bulbs, thin tubes, signs,
  LEDs, lasers) — never a floor/wall/big slab. No floating `BillboardGui` text (one exception:
  a short NPC speech bubble). Every part gets a real `Material` — never leave `Plastic`.
  Text goes on surfaces (`SurfaceGui`) or the screen HUD.
- **Use `Shared.UITheme`** for any GUI (HUD or SurfaceGui): `UITheme.C` palette, `UITheme.F`
  fonts (BuilderSans), `panel/label/caption/stroke/corner/money`.
- **Kenney props** via `server/KenneyLoader.lua`:
  `KenneyLoader.placeMany({{kit="furniture"|"factory", name=..., pos=Vector3 (bottom-centre), facing=Vector3}}, parentFolder)`.
  Names must exist in `shared/KenneyAssets.lua`. It is async and never errors.
- Builders build **geometry only** and return refs. **All gameplay logic lives in services.**
  No `Script`s inside builders.
- Anchor everything static. `CanCollide=false` on decoration players shouldn't snag on.
- Don't edit files you don't own (list per module below). If you need a change elsewhere,
  write it in your final report.

## 1. World map (studs; +Z = south, −Z = north; ground top y=0, floors top y=0.5)

| Thing | Where |
|---|---|
| Safehouse (exists) | x −24..24, z 4..40, walls 1 thick centred on edges, wall top y 16.5, roof slab y 16.5..17.5. Garage opening north face x −9..9, y 0.5..12.5. **Outer faces:** x ±24.5, z 3.5 (north), z 40.5 (south). |
| Ocean Drive (street, exists) | asphalt z −22..−6, x −120..120 today (Miami builder may extend to ±150). Kerbs + sidewalks to z −26.6 (north) and z −1.4 (south). Zebra crossing at x −5..5. Streetlights every 28 at x ≠ 0, z −25.8 / −2.2. |
| Safehouse driveway (exists) | x −10..10, z −1.4..3.5 |
| **Villa Rosa** (job 1) | x −30..30, z −82..−38, front door centred x 0 at z −38. Front garden z −38..−26.6. Back terrace z −88..−82. |
| **Diamond Dolls Jewelers** (job 2) | x −70..−46, z −1..23. Shopfront faces NORTH (z −1) onto the street. |
| Beach (Terrain sand) | z −88..−108 (all x). Ocean (Terrain water) north of z −104, surface y ≈ −0.6. |
| **Marina drop-off** | ring centred (106, 0, −96), radius 14, on the sand; pier x 100..106 running north from z −100 to −130 with a speedboat. |
| Route to the marina | along the street east to x ≈ 106, then north across open ground x 94..120 to the sand. **Keep x 94..122, z −26..−96 clear of buildings and trees.** |
| Deco building lots (north side, front face z −28, depth ≤ 22) | centres x −50 (w 22), −80 (w 24), 50 (w 22), 78 (w 24). |
| Deco building lots (south side, front face z 1, depth ≤ 22) | centres x −92 (w 24) [jewelry is −58], 62 (w 20), 88 (w 20). **Keep x 28..48, z −2..20 clear** (old car alley). |
| Police entry | cruisers spawn at (−145, 0, −10) and (145, 0, −18) |

## 2. Player / world state (attributes — replicate automatically)

| Attribute | On | Set by | Meaning |
|---|---|---|---|
| `Cash` (int) | Player | EconomyService | balance |
| `Role` (string?) | Player | CrewService | Hacker / Muscle / Driver / Lookout |
| `Level`, `XP`, `XPNext` (int) | Player | ProgressService | progression |
| `Gear` (string) | Player | ShopService | comma list of owned gear ids |
| `Mask` (string) | Player | ShopService | equipped mask id |
| `VIP` (bool) | Player | ShopService | owns the VIP pass |
| `CarryingLoot` (string?) | Player | LootService | loot kind being carried, nil if none |
| `HasKeycard` (bool) | Player | SecurityService | holding the keycard |
| `ActiveJob` (string) | ReplicatedStorage | JobService | selected job id |
| `BustMeter` (0..1) | getaway car Model | PoliceService | police proximity meter |
| `MarkedUntil` (number, `workspace:GetServerTimeNow()`) | guard/cop Model | AbilityService | Lookout mark |

CollectionService tags: **`Guard`** (every guard + cop model), **`SecurityCamera`** (camera models),
**`GetawayCar`** (the car model).

## 3. Remotes (`shared/Remotes.lua` NAMES)

Server → client: `CashUpdated`, `HeistState(state, payload)` (states `IDLE`, `ACTIVE`,
`ESCAPING` {escapeSeconds}, `COMPLETE`/`FAILED` {escaped, crewSize, take, each}),
`VaultProgress(0..1)`, `AlarmTriggered(bool)`, `Notify({text,color,duration})`,
**`JobInfo(info)`** — see §5.

Client → server: **`ThrowBag(dir: Vector3)`**, **`UseAbility()`** (Lookout mark),
**`Nitro()`** (Driver), **`ShopAction`** RemoteFunction `(action, payload) -> {ok, msg, state}`
with actions `getState`, `buyGear{id}`, `buyMask{id}`, `equipMask{id}`, `redeemCode{code}`, `buyVIP`.

## 4. JobRefs — what a job builder returns

```lua
{
  id = "villa",
  root = Folder,
  entryPoint = Vector3,              -- just outside the front door
  policeStop = Vector3,              -- where cruisers park on the street for this job
  getawayCFrame = CFrame,            -- where the getaway car parks (on the road, facing along it)
  openSign = function(open: boolean) end,   -- flip OPEN/CLOSED signage when (de)selected

  vault = {                          -- optional (jewelry calls it the safe)
    door = BasePart,                 -- the round door; ProximityPrompt goes here
    hinge = CFrame,                  -- pivot CFrame the door rotates around (Y axis)
    openAngle = math.rad(-100),
  },
  keycardDoors = { { door = BasePart, openOffset = Vector3, panel = BasePart, status = BasePart } },
  keycardSpots = { CFrame, ... },    -- surface points where the keycard can spawn
  breaker = BasePart | nil,          -- security panel; prompt goes here
  cameras = { { model = Model, head = BasePart, light = SpotLight, led = BasePart,
                yawRange = 70, period = 7 } },   -- head.CFrame LookVector = centre of sweep
  laserRows = { { beams = { BasePart }, zoneCFrame = CFrame, zoneSize = Vector3,
                  onTime = 1.4, offTime = 1.1, phase = 0 } },
  lootSpots = { { kind = "Cash"|"Gold"|"Diamonds"|"Art"|"Jewels", cframe = CFrame, visual = Instance } },
  smashCases = { { glass = BasePart, visual = Instance, cframe = CFrame, kind = "Jewels" } },
  guardRoutes = { { name = "Guard_A", spawn = Vector3, a = Vector3, b = Vector3 } },
  plan = {                           -- drawn on the safehouse blueprint (world coords)
    bounds = {x0, z0, x1, z1},
    rooms = { {x0, z0, x1, z1, "OFFICE"}, ... },
    vault = {x, z}, entry = {x, z},
  },
}
```

`visual` for loot/cases is hidden (Transparency=1 / Parent=nil) by LootService when taken and
restored on reset — builders just make it look good.

## 5. JobInfo payload (server → client, on every change)

```lua
{ jobId, jobName, stage = "IDLE"|"ACTIVE",
  steps = { {id="cameras", label="Cut the cameras", done=false, optional=true}, ... },
  take = 0, bagsSecured = 0, bagsTotal = 6,
  alarm = false, alarmEndsAt = 0 (server time), silentAlarm = false }
```

## 6. Who owns what

| Owner | Files |
|---|---|
| Claude (core) | Constants, Remotes, UITheme, PlayerDataService, EconomyService, JobService, SecurityService, LootService, AbilityService, ShopService, ProgressService, CrewService, GuardService, NpcFactory, HeistBuilder, SafehouseBuilder, init.server, init.client, CrewHud, HeistHud, CashHud, Notifications |
| Agent · world | `server/MiamiBuilder.lua` |
| Agent · villa | `server/VillaBuilder.lua` |
| Agent · jewelry | `server/JewelryBuilder.lua` |
| Agent · vehicles | `server/VehicleService.lua`, `server/PoliceService.lua`, `client/CarHud.lua` |
| Agent · UI | `client/ShopUI.lua`, `client/JobHud.lua`, `client/LootHud.lua`, `client/AbilityHud.lua` |
