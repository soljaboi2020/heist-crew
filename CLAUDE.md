# CLAUDE.md — Heist Crew (Roblox Game)

> **Purpose:** Per-project context document. Read this at the start of every Heist Crew session so future Claude knows exactly where we are.

---

## 📛 Project Name & Goal

**Heist Crew** — a 4-player coop PvE Roblox game where crews execute heists on AI-guarded mansions, banks, and casinos. Inspired by Money Heist / Payday 2 / GTA V Heists, but **Roblox-native** with the viral hooks that actually move players (cash that goes up, gear unlocks, gamepasses, codes, FOMO heist events).

**Why we picked it:**
- The "Steal a [X]" genre on Roblox is saturated — Malachi's instinct to differentiate was correct.
- Heists give us a *narrative* hook (plan → infiltrate → crack → escape) competitors don't have.
- Coop multiplayer = friend-pull-in factor (one person joins, brings 3 friends).
- Monetizable in 6+ ways without feeling pay-to-win (cosmetics, crew slots, gear catalog, VIP, dev products for getaway boosts, etc.).
- Name "Heist Crew" verified **available** on Roblox (Malachi checked 2026-05-05).

## 📅 Date Created
- **2026-05-05** — Project scaffolded. Smoke-test phase ("Hello world" Rojo → Studio sync).

## 👤 Malachi's Roblox account
- **Username:** `Soljaboi1919` (confirmed 2026-05-05 via Studio Output: `[HEIST CREW] Soljaboi1919 joined the crew 💼`)

## 🗂️ Folder Structure

```
heist-crew/
├── CLAUDE.md                    ← this file (project context)
├── README.md                    ← public-facing setup + run guide
├── .gitignore                   ← excludes *.rbxl, sourcemap.json, OS junk
├── default.project.json         ← Rojo config (filesystem ↔ Studio mapping)
└── src/
    ├── server/
    │   └── init.server.lua      ← server bootstrap (runs on Roblox server)
    ├── client/
    │   └── init.client.lua      ← client bootstrap (runs on each player's device)
    └── shared/
        └── Constants.lua        ← single-source-of-truth game settings
```

**Rojo mapping (from `default.project.json`):**
| Filesystem path | Roblox service |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |

## 🛠️ Tech Stack

- **Language:** Luau (Roblox's Lua dialect)
- **Engine:** Roblox Studio
- **Sync tool:** [Rojo](https://rojo.space/) **v7.7.0** (CLI + Studio plugin — both upgraded 2026-09-22;
  the May install was 7.6.1 on a different machine)
- **Version control:** Git + GitHub (`soljaboi2020/heist-crew`)
- **⚠️ WORKFLOW CHANGED 2026-09-22 — Studio now runs on the SAME machine as the repo.**
  Malachi moved Studio onto the `D:\Projects` machine ("easier to send screenshots"), so there is
  **no git pull step any more**: Claude writes a file, Rojo sees it instantly, Studio hot-reloads.
  The old laptop→GitHub→gaming-PC route still works but is no longer the path being used.

## ▶️ How to run / preview

### On the **gaming PC** (where Roblox Studio runs):

**One-time setup:**
```powershell
# 1. Install Rojo CLI (skip if already installed — verify with `rojo --version`)
winget install Rojo.Rojo

# 2. Install Rojo plugin in Studio (skip if already installed)
#    https://create.roblox.com/store/asset/13916111004/Rojo
#    Or in Studio: Toolbox → Marketplace → Plugins → search "Rojo" → Get

# 3. Clone the repo
cd D:\Projects\source\personal
git clone https://github.com/soljaboi2020/heist-crew.git
cd heist-crew
```

**Daily workflow:**
```powershell
# 1. Pull latest from GitHub (whenever Claude has pushed new code from the laptop)
cd D:\Projects\source\personal\heist-crew
git pull   # only needed if Studio is on a DIFFERENT machine

# 2. Start Rojo server
rojo serve
# (leave this PowerShell window open — it watches files and feeds Studio)

# 3. Open Roblox Studio → File → New Place
# 4. Plugins tab → Rojo → Connect (uses default port 34872)
# 5. Hit Play (F5) — should see in the Output window:
#       [HEIST CREW] Server online ✅
#       [HEIST CREW] Version 0.0.1 — Hello world phase
#       [HEIST CREW] <YourUsername> joined the crew 💼
#       [HEIST CREW] Client online ✅ — playing as <YourUsername>
```

**To stop:** `Ctrl+C` in the Rojo PowerShell window, then close Studio.

### On the **laptop** (where Claude edits):

Claude edits files in `/src/source/personal/heist-crew/` (which is **`D:\Projects\source\personal\heist-crew\`** on Windows — ⚠️ `/src` = `D:\Projects`, **not** bare `D:\`). After each meaningful change, Claude auto-commits + pushes to GitHub per Rule #6. Malachi just runs `git pull` on the gaming PC to receive the changes.

## ✏️ How to edit / customize

| Want to change... | Edit this file |
|---|---|
| Game name, version, max crew size, payout limits | `src/shared/Constants.lua` |
| Server-side game logic (heists, AI, economy) | `src/server/init.server.lua` (currently a stub — services will be added as separate ModuleScripts) |
| Client-side UI, input, camera, effects | `src/client/init.client.lua` |
| What folders sync to which Studio services | `default.project.json` |
| Files git ignores | `.gitignore` |

**Convention:** any new server systems go in `src/server/<ServiceName>.lua` as ModuleScripts. Same for client (`src/client/<UIName>.lua`) and shared (`src/shared/<ModuleName>.lua`). The bootstrap files (`init.server.lua` / `init.client.lua`) just `require()` and start the modules.

## 🎯 Active Tasks / TODO

### Phase 0 — Smoke test ✅ DONE 2026-05-05
- [x] Scaffold project structure
- [x] Write Rojo config
- [x] Write server + client + shared bootstrap files
- [x] Initialize git + push to GitHub
- [x] Malachi clones on gaming PC + runs `rojo serve`
- [x] Malachi connects Studio's Rojo plugin → hits Play → confirms "[HEIST CREW] Server online ✅" in Output

### Phase 1 — Core framework ✅ DONE 2026-05-05
- [x] `PlayerDataService.lua` — DataStore wrapper for cash, level, owned gear, completed heists
- [x] `Remotes.lua` — central RemoteEvent / RemoteFunction registry
- [x] First spawn-and-greet flow (player joins → spawns in lobby with $100 starting cash visible on HUD)

### Phase 2 — First playable heist ✅ SHIPPED 2026-05-05 (we are here 🟢 — pending in-Studio verification)
- [x] Procedural mansion (60×40 stud building, walls + roof + door + signs)
- [x] Vault (gold DiamondPlate cube with ProximityPrompt, hold E for 8 sec)
- [x] Two patrolling AI guards (block-character build, vision cones, raycast LOS)
- [x] Getaway car (activates green/Neon when alarm fires, Touched = win)
- [x] State machine: IDLE → CRACKING → ESCAPING → COMPLETE/FAILED
- [x] Alarm system (red flashing border + screen-wide pulse)
- [x] Toast notifications (top-center sliding messages, color-coded)
- [x] Heist HUD (vault progress bar + state banner + countdown)
- [x] Stealth bonus payout (+$500 if escape without being spotted)

### Phase 3 — Multi-heist + economy
- [ ] 5 heist locations: small mansion, big mansion, bank, casino, museum
- [ ] Tool catalog: lockpick, EMP, silenced pistol, drill, thermal scope
- [ ] Shop UI for spending cash on tools
- [ ] Crew lobby — match with friends, ready-up, vote on heist
- [x] ~~Multiplayer crew system (multiple players sharing one heist instance)~~ ✅ **DONE 2026-09-22 (v0.4.0)**
- [ ] Lockpicking mini-game (the dial-tolerance system from Constants) — currently replaced with hold-E-on-vault, will revisit

### Phase 4 — Monetization
- [ ] Gamepass: VIP Crew (cosmetic vault, +10% payout)
- [ ] Gamepass: Extra Crew Slot (5-player crews)
- [ ] Dev products: Getaway Boost, Skip Lockpick, Extra Loot Roll
- [ ] Daily login rewards + login streak

### Phase 5 — Polish + launch
- [ ] Sound FX + ambient audio + music stings on alarm trigger
- [ ] Cinematic camera on heist start ("the briefing")
- [ ] Notification system + toasts
- [ ] Codes system (Twitter / TikTok promo codes)
- [ ] Soft launch to friends — iterate on feedback
- [ ] Public launch + `@heistcrewroblox` TikTok push

## ✅ Completed
- [x] **2026-05-05** — Picked the game concept (Heist Crew, after rejecting "Steal a Drip" for being in a saturated genre)
- [x] **2026-05-05** — Verified name available on Roblox
- [x] **2026-05-05** — Set up cross-machine workflow (laptop → GitHub → gaming PC) using Malachi's existing GitHub Desktop install
- [x] **2026-05-05** — Installed Rojo CLI v7.6.1 + Rojo Studio plugin on gaming PC
- [x] **2026-05-05** — Project scaffolded: Rojo config + 3 bootstrap scripts + Constants module + .gitignore

## 📌 Decisions & Notes

### Game design choices
- **4-player crews** (not 5 or 6) — small enough that everyone has a role, big enough to feel like a heist movie.
- **PvE not PvP** — coop = friend recruitment. PvP = matchmaking nightmare for a solo dev.
- **Stealth-first** — guards use vision cones (90° FOV, 30 stud range, 8 sec alert duration). Player can choose to go loud, but stealth bonuses payout +50%.
- **Cash > XP** — Malachi confirmed players come back for "numbers go up." Cash is the main progression loop; cosmetics are the prestige loop.
- **Procedural rooms** — heists must feel different every run, otherwise it's a one-and-done game. Hand-placed environments for hub/lobby only.

### Code conventions
- **Use `init.server.lua` / `init.client.lua` as bootstraps**, not as the actual logic dump. Real systems go in ModuleScripts.
- **Constants in `Shared`** so client UI can show the same "$10M MAX PAYOUT" the server enforces.
- **Print statements use `[HEIST CREW]` prefix** so they're greppable in the Studio Output window.
- **Always `require(game:GetService("X"))`** — never trust `script.Parent.Parent.Parent` indirection (breaks when files move).

### Workflow notes
- **Laptop = code, gaming PC = run.** Bridge is GitHub. Same flow as `malachi-builds` and `shine-pro-exterior`.
- **Auto-deploy enabled** (Rule #6) — Claude pushes to `main` directly via `/src/.git-credentials`. Malachi just pulls.
- **`.rbxl` / `.rbxlx` files are git-ignored** — the source of truth is the Lua + JSON files. The Studio place file is rebuilt on each session via Rojo.

### Things to NOT do
- ❌ Don't hand-edit code inside Studio — Studio is for **previewing**, not for editing. Claude edits files on disk; Rojo syncs them in.
- ❌ Don't commit `*.rbxl` files — bloats the repo and can't be merged.
- ❌ Don't put game logic in `init.server.lua` — keep that file as a 30-line bootstrap.

## 📅 Change Log
- **2026-05-05** — Project created. Rojo config + bootstrap scripts + Constants module written. Smoke test phase started. Initial commit pushed to GitHub.
- **2026-05-05** — **🎉 PHASE 0 SMOKE TEST PASSED.** Malachi cloned the repo on his gaming PC via GitHub Desktop, ran `rojo serve` from VS Code's integrated terminal, connected the Rojo plugin in Studio, and hit Play. All 3 print statements (Server online / Player joined / Client online) appeared in the Output window. Confirmed Roblox username: `Soljaboi1919`. Full pipeline (laptop → GitHub → gaming PC → Rojo → Studio) verified working. Phase 1 (core framework) starts next.
- **2026-05-05** — **🎉 PHASE 1 SHIPPED + VERIFIED.** Pushed commit `c78c39f`: 5 new modules (Remotes, PlayerDataService, EconomyService, TestPad, CashHud) + bumped version to 0.1.0. Malachi pulled via GitHub Desktop, Rojo hot-reloaded, hit Play in Studio. Verified: green cash HUD appears top-right showing $100, glowing green pad spawned at (20, 0, 0), stepping on pad triggered 3 successful touches (100→150→200→250), HUD bounce animation fired on each, EconomyService server-side prints confirmed. Full gameplay loop (touch → server → DataStore → remote → HUD animation) verified end-to-end. Ready for Phase 2 (first heist room).
- **2026-05-05** — **🎉 PHASE 2 MEGA-PUSH — FULL PLAYABLE HEIST.** Bumped version to 0.2.0. Per Malachi's request "add everything to make playable," shipped one giant push containing:
  - **`HeistBuilder.lua`** — procedural mansion (60×40 floor, 4 walls split around 12-stud doorway, translucent roof, "🏛 MANSION HEIST" sign), gold DiamondPlate vault with PointLight, dark metal getaway car (body + roof + 4 wheels), decorative green Neon spawn ring, mansion centered at (0, 0, -160), vault at (0, 5, -185), getaway at (0, 2, -70).
  - **`GuardService.lua`** — 2 patrolling guards (block-character: body + head + hat + SpotLight vision cone). 90° FOV cone check via dot-product, line-of-sight via raycast, 35-stud vision range. PATROL state walks waypoint A↔B; CHASE state activates on alarm and beelines to last-known player position. Touched event = caught.
  - **`HeistService.lua`** — state machine (IDLE / CRACKING / ESCAPING / COMPLETE / FAILED). Vault uses ProximityPrompt with `HoldDuration=8`, `KeyCode=E`. On full hold: pays $1500, fires alarm to all clients, activates getaway car (green Neon glow), starts 90s escape timer. Getaway car Touched = $1000 escape + $500 stealth bonus if not spotted. Caught/spotted while CRACKING/ESCAPING = fail + teleport back to spawn. After 30s cooldown, vault re-arms.
  - **`Notifications.lua`** (client) — top-center sliding toast system. Color map (green/red/gold/white) feeds UIStroke + label color. Tweens in from above, auto-fades after duration.
  - **`HeistHud.lua`** (client) — three UI elements: (1) full-screen alarm border with 4 red bars + "🚨 ALARM TRIGGERED" text pulsing via sine wave, (2) vault progress bar bottom-center with gold fill + "🔧 CRACKING... X%" label, (3) state banner top-center with live ESCAPE countdown.
  - **`Constants.lua`** updated with Guard AI / Vault / Heist Payout / World coordinate / Color sections.
  - **`Remotes.lua`** added: `HeistState`, `VaultProgress`, `AlarmTriggered`, `Notify`.
  - **`init.server.lua`** wires it all together: `HeistBuilder:build()` → `GuardService:spawnPatrols(callbacks)` → `HeistService:init(refs, GuardService, EconomyService)` → `TestPad:spawn()`.
  - **`init.client.lua`** mounts `Notifications` + `HeistHud` alongside `CashHud`.
  - **Pending verification** — Malachi needs to pull, hit F5, walk to mansion (~150 studs north), sneak past guards (yellow vision cones), hold E on vault, escape to getaway car within 90s. Stealth run = $3,000 total payout.
- **2026-05-05** — **🎨 v0.3.0 — POLISHED LOBBY + ATMOSPHERE.** Malachi flagged that the mansion was too far + the world looked empty (just a ring on a baseplate). Massive HeistBuilder rewrite to make the game LOOK like a popular Roblox game:
  - **Lighting overhaul** — cinematic dusk skybox (ClockTime 19.5, 3000 stars), Atmosphere haze, Bloom effect, ColorCorrection (warm tint), fog from 200→800 studs.
  - **Ambient music** — looping Sound at Workspace level w/ rbxassetid free track.
  - **Lobby plaza** at spawn — 28-stud-radius circular marble plaza, gold neon ring border, center pedestal w/ floating "💰 HEIST CREW" sign + subtitle "Crack the vault. Escape the guards. Get paid.", 4 lamp posts (with PointLights) at compass points, glowing green SpawnLocation pad.
  - **Tutorial billboard** — wooden board angled toward spawn w/ SurfaceGui showing "📋 HOW TO HEIST" + 5-step instructions.
  - **Boss NPC** — block-character in navy suit + gold tie + black fedora, speech bubble: "Crack that vault, kid. Don't get caught."
  - **Decorative trees** — 9 trees scattered around plaza edge (wood trunks + green grass-material leaf balls).
  - **Path** — 8-wide stone walkway from lobby to mansion entrance with gold neon edge strips + 2 lamp posts at midpoint.
  - **Mansion repositioned** — moved from z=-160 → z=-55 (much closer), shrunk from 60×40 → 44×36 (more focused). Added: 4 corner cylinder pillars w/ gold neon caps, marble floor, red carpet runner from entrance to vault, slate roof w/ gold trim, 4 interior PointLights, 3 wall paintings.
  - **Vault upgraded** — added 3 colored gem balls (ruby/emerald/sapphire) stacked on top.
  - **Getaway car restyled** — added roof cabin, glass windshield, 4 cylinder wheels, 2 Neon headlights w/ PointLights.
  - **Sound effects** — vault crack click on success, looping alarm wail when alarm fires, triumphant sting + cha-ching on heist complete, fail buzzer on caught.
  - **Tuning** — vault crack time reduced 8s→6s (snappier), getaway timer 90s→60s, vault cooldown 30s→20s.
  - **Constants reorg** — added `LOBBY_CENTER`, `LOBBY_RADIUS`, `TUTORIAL_BOARD_POS`, `BOSS_NPC_POS`, `PATH_START/END`, `SOUNDS` table, expanded `COLORS` with marble/carpet/grass/path tints.

## 📅 Change Log (continued)
- **2026-09-01** — **🎨 VISUAL DIRECTION FOR v1.0** (commits `b584bd0`, `364800e`) — *this was never
  logged here at the time and the doc read as if nothing happened after May.* Produced
  `docs/mockups/vision-board.png` + `icon-512.png`: the game icon (masked character, "4-PLAYER
  CO-OP" banner, orange sunburst — deliberately Roblox-native rather than the first attempt's
  generic-app look), the in-heist HUD (alarm timer, cash counter, cracking bar, objective strip),
  a **crew-select screen with four roles — Hacker / Muscle / Driver / Lookout** — and a payout
  breakdown screen. ⚠️ **These are design targets, not implemented.** The roles in particular do
  not exist in code.
- **2026-09-22** — **🤝 v0.4.0 — CO-OP REWRITE (the game now matches its own icon).**
  Found that `HeistService` tracked a single `session.activePlayer`: only the vault-cracker was
  paid, and `if player ~= session.activePlayer then return end` on the getaway car meant nobody
  else could even finish. Three friends in a server would have watched one person play. Rewritten
  to a shared crew run:
  - `session.crew` maps each Player → `{escaped, out}`. Everyone on the server joins the crew the
    moment the vault pops.
  - **Any** player can crack the vault; a second player touching it is told who's already on it.
  - **Every** crew member escapes individually at the car and is paid individually.
  - **Getting caught is now personal, not team-wide** — one player going down no longer fails the
    run for the whole crew. They're teleported to the lobby with no payout; everyone else runs on.
  - **Being spotted no longer instantly fails the heist.** It costs the crew its stealth bonus and
    pulls the guards in early. (It used to be an instant team wipe, which in co-op would be
    miserable.)
  - Cracker going down mid-crack resets the crack but leaves the vault armed for a teammate.
  - Run resolves when all crew have escaped or been taken out, or the 60s timer expires
    (stragglers get "left behind"). `PlayerRemoving` drops leavers so a quitter can't stall it.
  - Vault progress now broadcasts to the **whole crew**, not just the cracker.
  - New `HEIST_PAYOUT_CRACKER_BONUS = 750`. Per-escapee payout unchanged at $2,500, or $3,000
    clean — so a **solo run pays exactly what it did before** and co-op adds upside.
  - Client contract deliberately untouched (`stateName` + `payload.escapeSeconds`), so
    `HeistHud.lua` needed no changes.
  - Both changed files verified to parse with a real Lua parser before handing over. Compound
    `+=` assignments were rewritten as plain assignment purely so an off-the-shelf parser could
    check them — Luau supports `+=` fine.
  - ⏸️ **PENDING IN-STUDIO VERIFICATION** — solo path and a 2-player crew test.

- **2026-09-24** — **👮 v0.6.0 — REAL NPCs + FUTURE LIGHTING** (Malachi: *"it looks like shit and
  blocky"* → pitched 5 fixes, he said go; did #1 + #2 first).
  - New **`src/server/NpcFactory.lua`** — builds real R15 avatars via
    `Players:CreateHumanoidModelFromDescription`, plays Roblox's stock R15 idle/walk/run anims
    (507766666 / 507777826 / 507767714) on the server Animator. Fallback chain: catalog look →
    plain R15 in body colours → nil. Hides name tags/health bars (art rule #3).
  - **Guards** = official Roblox outfit **320998366 "Police Officer Nash"** (bundle 349, Rthro).
    Movement rewritten from anchored-brick tweens to `Humanoid:MoveTo` + **PathfindingService**
    (old guards slid *through walls* when chasing). Order changes bump `guard.gen` to cancel the
    current walk. Touching **any** guard part = caught. Vision logic unchanged (now reads
    `guard.root`); SpotLight has `Shadows = true`. `guard.body` kept as an alias.
  - **Boss** = R15 avatar, shirt 6554200369 + pants 6555797786 (TIX "Grey Suit w/ Black Vest",
    third-party — if it's ever deleted the fallback kicks in) + hat 168167624 "Fedora and Shades".
    Speech bubble now `MaxDistance 40`, not AlwaysOnTop.
  - **`default.project.json` sets `Lighting.Technology = "Future"`** (not settable from script).
    Ambient 50,55,75 → 22,24,34 so the mansion interior goes dark; interior lamps dimmer + shadows.
  - Neon → Metal on pillar caps, the 49×41 roof-trim slab, and the spawn pad.
  - All 3 changed .lua files pass `luau-compile` (official Luau release binary, in /tmp — not kept).
  - ⏸️ **PENDING IN-STUDIO CHECK** — guards spawn + walk, boss stands idle, interior is dark.
  - **Next up (approved list):** #3 mansion rebuild (windows, framed door, rooms) · #4 Kenney
    models — needs a Roblox **Open Cloud API key** from Malachi so Claude can bulk-upload the FBX
    files (unverified until tried) · #5 screen HUD replacing the floating "MANSION HEIST" sign.

- **2026-09-24 (pm)** — **v0.6.1 — fixes from Malachi's first v0.6.0 screenshot.** Boss avatar
  confirmed rendering. Fixed: ① the 3 `AlwaysOnTop` BillboardGuis ("MANSION HEIST", "VAULT",
  "GETAWAY") covering the screen from anywhere → new `signText()` prints them on a part face via
  SurfaceGui (arch header, vault front, both car doors; car uses a proxy table so `HeistService`'s
  `.Text`/`.TextColor3` writes still work unchanged) ② **plaza trim ring BUG** — segments sized
  `(segLength, 0.22, 1.1)` but after the Y-rotation local X is radial, so they rendered as orange
  spokes; now `(1.1, 0.22, segLength)`, colour toned to aged brass ③ lamp bulbs were 1.5-stud
  flat-yellow neon blobs → 0.9-stud warm-white bulb under a dark metal shade (path lamps too)
  ④ TestPad sign no longer AlwaysOnTop.

- **2026-09-24 → 25** — **🔑 KENNEY PIPELINE LIVE (Open Cloud).** Malachi made a Roblox Open Cloud
  key (`assets` API, read+write) → vaulted at `~/.claude/roblox-opencloud-key` (listed in
  `~/.claude/CREDENTIALS.md`). His user id **2501618318** (display name "Karen").
  - **`tools/upload_kenney.py`** uploads the Kenney `.fbx` files straight from the zips via
    `POST apis.roblox.com/assets/v1/assets` (assetType `Model`), polls the operation, writes the
    ledger **`tools/kenney_assets.json`** after EVERY upload, and generates
    **`src/shared/KenneyAssets.lua`**. Preview by default, `--go` to upload, never re-uploads.
    Furniture (140) + factory (143) kits uploaded; dungeon kit skipped (medieval). **Moderation
    approved every one instantly.**
  - Factory texture atlas also uploaded: Image **94958674308524** (Decal 76890606501727) —
    `KenneyLoader` applies it if a factory mesh arrives with no `TextureID`.
  - **Verified in Studio:** `InsertService:LoadAsset(108470551669951)` loaded `HC_furniture_desk`.
  - Also: `tools/fix_kenney_sizes.lua` — command-bar snippet to shrink hand-inserted Kenney meshes.
- **2026-09-25** — **🏚 v0.7.0 — THE SAFEHOUSE + NEW UI** (Malachi picked lobby option A and said
  *"make sure ui is nice not like crappy blocky"*). Roadmap agreed in chat: ① Safehouse ② Mansion
  2.0 (loot bags, cameras/keycards, rebuilt interior) ③ roles + masks ④ shop/progression + Jewelry
  Store ⑤ driving getaway + police ⑥ monetization + soft launch. **Show-before-build (Rule #12)
  applies to ② onward.**
  - **World re-laid out** (`Constants.WORLD`): plaza/pedestal/plaza lamps/tutorial board DELETED.
    Spawn is inside the safehouse at (0, 0.6, 27) facing north; street runs east-west at z −14;
    getaway car moved to (38, 2.5, 8) off the new sidewalk. `sendToLobby` now uses SPAWN_POSITION
    (was a hardcoded `(0,10,0)`).
  - **`SafehouseBuilder.lua`** — brick warehouse x −24..24 / z 4..40: auto roll-up garage door
    (slats stack into the header — they'd have gone through the roof in the first draft),
    planning table + live SurfaceGui **blueprint** of the mansion job, 4 **crew pads** + wall signs,
    **gear wall** (shadow-board teaser for the shop) + workbench, **lounge + TV** (next job, top-5
    earners, crew roster), hanging industrial lamps w/ shadows, skylights, trusses, "RIVERSIDE AUTO
    BODY" front sign. Plus the **street**: asphalt, dashed line, kerbs, sidewalks, zebra crossing,
    14 streetlights, mansion garden path + hedges.
  - **`KenneyLoader.lua`** — LoadAsset (cached) → ScaleTo real size (diagonal match, robust to axis
    swaps; furniture ×1.25 because avatars are chunky) → anchor → sit on the floor → recolour.
    ⚠️ **`FRONT_YAW` is an unverified guess** (`math.pi`): if furniture faces the wall, flip it to 0.
  - **`CrewService.lua`** — pads assign roles (one per role, swap by stepping on another, freed on
    leave), `Role` player attribute, pad glow + sign status, TV refresh every 2s. **Roles are
    cosmetic** — abilities not built.
  - **`EconomyService`** mirrors cash to a `Cash` player attribute + standard `leaderstats` → fixes
    the HUD sitting at **$0** when it missed the first `CashUpdated` event (seen in screenshots).
  - **New UI (`Shared/UITheme.lua`)** — one look for all HUD + in-world screens: smoked-glass
    panels, hairline strokes, BuilderSans type, colour only for meaning. Rewrote **CashHud**
    (rolling number, "+$X" delta), **Notifications** (CanvasGroup toasts, accent bar, max 4),
    **HeistHud** (red edge-glow alarm vignette, slim vault bar, HEIST COMPLETE / BUSTED result card),
    new **CrewHud** (role card, objective pill w/ escape countdown, "HEIST CREW" title card on join).
  - Every .lua in the repo passes `luau-compile` + `luau-analyze` (no unknown globals).
  - ⏸️ **PENDING IN-STUDIO CHECK** — props loading + orientation, door, pads, TV, UI layout.

- **2026-09-25** — **v0.7.1 — fixes from the first safehouse screenshots.** Safehouse, blueprint,
  boss, TV, pads, streetlights all confirmed rendering; **factory crates came in textured** (atlas
  fallback not needed). Fixed: ① **REAL BUG — cash $0 / no TV number**: the world build now yields
  (NPC outfits + Kenney loads), so in Studio the player joined BEFORE `PlayerAdded` was connected
  and their data never loaded. `init.server.lua` now also runs the join handler for players already
  in the server. (Also explains the $0 in older screenshots.) ② role card moved bottom-left — Roblox's
  chat window sits top-left ③ pad labels enlarged (Top-face text runs along world Z) + wall-sign
  status shortened to "OPEN"/name with TextScaled ④ boss bubble restyled to UITheme ⑤ **test pad OFF**
  (`Constants.DEV_TEST_PAD = false`) ⑥ `tools/clean_workspace.lua` — command-bar snippet that moves
  hand-inserted Workspace junk (the giant desk/corridor blocking the sky) to `ServerStorage._OldInserts`.
  ⏳ **Malachi: "the brick building gives basic, I want this game out of this world"** → art-direction
  options pitched (Rule #12), awaiting his pick before any exterior rebuild.

- **2026-09-25** — **🌴 v1.0.0 "NEON MIAMI" — EVERYTHING AT ONCE.** Malachi picked art direction A
  (Neon Miami Nights) and said *"knock everything out in one — every upgrade — we'll go through it
  when it's done."* The whole roadmap was built in one pass. **Contract: `docs/V1_SPEC.md`** (world
  map, attributes, remotes, JobRefs, file ownership) — read it first.
  - **Built in parallel by 5 subagents** (each owned its own files): `MiamiBuilder` (world art),
    `VillaBuilder` (job 1 map), `JewelryBuilder` (job 2 map), `VehicleService`+`PoliceService`+
    `CarHud`, and the UI set `JobHud`/`LootHud`/`AbilityHud`/`ShopUI`. Claude wrote the core +
    integration.
  - **Core (Claude):** `JobService` replaces `HeistService` (deleted) — run lifecycle IDLE→ACTIVE,
    alarm + timer, **drill** (place → runs → random jams to fix → vault swings open), silent alarm
    (jewelry), catch/bust/drop-off, payouts (each escapee gets the FULL take, + stealth bonus if no
    alarm), XP, reset. `SecurityService` (sweeping cameras w/ LOS + detect time, breaker, random
    keycard, keycard doors + Hacker hack, rhythmic laser rows via GetPartBoundsInBox). `LootService`
    (duffel bags on your back, slowdown, G to throw, pick up, load into the car trunk).
    `ShopService` (gear, Roblox-made catalog masks worn during jobs, codes, VIP pass, daily streak)
    over the `ShopAction` RemoteFunction. `ProgressService` (XP/levels). `AbilityService` (Lookout
    mark). `GuardService` now route-driven, live-chases the nearest player, Muscle takedowns (stun).
    Saves migrated to the v1.0 shape in `PlayerDataService`. `HeistBuilder` is now a coordinator that
    pcall-wraps every builder; `init.server`/`init.client` load optional modules defensively.
  - **Getaway = drive the loaded car to the marina** (`WORLD.DROPOFF` (106,0,-96)). Only players IN
    the car at the drop-off are paid. Car busted by cruisers → everyone in it is out.
  - **Monetization is inert until Malachi acts:** `Constants.GAMEPASSES.VIP = 0` — create the pass in
    the Creator Dashboard and paste the id. Codes live in `Constants.CODES`.
  - **Integration notes from the subagents (all handled):** vault/safe `door` is a flat lock plate
    (a cylinder can't face the corridor) — the disc is in `vault.parts`; the car is open-top with
    F-key seat prompts; a `CarInput` remote carries driver input (VehicleSeat input on an anchored
    seat is unverified); two parked cars removed from police lanes; smashed case glass now shatters
    (LootService); client `Remotes.getRemote` no longer creates a shadow folder.
  - **Unverified guesses to check first in Studio:** `KenneyLoader.FRONT_YAW` (props facing the
    wall?), WedgePart orientation on the cars (`VehicleService` `Build.wedge`), whether PivotTo
    carries seated players, touch-button positions (`TOUCH_POS` in LootHud/AbilityHud).
  - ⏸️ **NOTHING HERE HAS BEEN PLAYTESTED.** Everything compiles + analyzes clean; that's all.

- **2026-09-25** — **🎬 v1.1.0 — "MAKE IT FEEL LIKE A HEIST" + FULL BUG SWEEP.** Malachi: v1.0 *"looks
  great, everything works"* but *"not much of a heist… kind of confusing."* Built:
  - **Briefing + drop-in** (`BriefingUI`): E on the Boss → letterboxed camera sweep over blueprint/TV/
    garage with typed-out lines (`Constants.JOBS[].briefing`) → READY UP. Ready also at the planning
    table (E; change job moved to R). All ready → 5s, or ≥half ready → 15s → fade → crew teleported to
    the sidewalk by the car → masks on → title card. Implicit start (first heist action) still works.
  - **Waypoints** (`WaypointHud`) from `JobInfo.targets` (server computes the next goal: BRIEFING/READY,
    BREAKER, SEARCH (keycard rooms), KEYPAD, DRILL/FIX DRILL, LOOT, SMASH, CAR, MARINA). Carrying a bag
    → only CAR/MARINA. Off-screen → edge arrow.
  - **Detection meters** (`DetectionHud`): guards (`GuardService`, 0.4s point-blank → 1.4s at range,
    drains out of sight) and cameras publish `GuardSuspicion`/`CameraSuspicion` + source position →
    "SPOTTING…" meter + direction arrow. Guards no longer alarm instantly.
  - **Payout screen** (`PayoutScreen`): bags count in with cha-chings, stealth bonus, YOUR CUT rolls
    up, grade stamp **S/A/B/C/F**, +XP, time, PLAY AGAIN; failures show why + a tip. Old result card
    retired.
  - **Rookie tips** (`TipHud`, attribute `Rookie` until first finished heist) + objective pill now
    "Step 1/2/3 of 3" in the lobby and "Stealth · m:ss" during a run.
  - **Bug sweep** (independent reviewer, 30 findings, 0 crashes) — fixed: drop-off latch could die for
    the run · empty parked car could be busted · reset race could skip the job reset · bags lost on
    death / after 180s · prompts through walls (LOS on everywhere, drill needs the door open) ·
    jewelry open-room loot locked (`inVault=false`) · **failed DataStore read no longer saves defaults
    over real data** · Hacker's keypad prompt hidden by Swipe (own key H + AlwaysShow) · seated players
    teleported while welded (`unseat`) · keycard step stayed ticked · briefing camera tween leak ·
    READY button toggled you off · off-screen arrows mirrored · Roblox player list over the HUD ·
    phones (role card, payout scale) · bag strap welded at origin · loose bags blocking the car ·
    guards chasing into the safehouse · pad toast spam · drill bonus farmable · mask race ·
    late joiners missing the alarm · laser tip never showing · guard loop surviving respawn · camera
    perf · street lamp shadows · first-spawn Sneakers · one AFK player blocking launch.
  - **Known, not fixed:** driving may look choppy on other clients (server PivotTo of an anchored car).
    If it does, next step = unanchored chassis + AlignPosition owned by the driver.

- **2026-09-25** — **v1.1.1** fixes from screenshots: CanvasGroup fades didn't hide on Malachi's PC
  ("SPOTTING…" + drop-in title stuck on screen) → `init.client` drives `Visible` from
  `GroupTransparency` for every CanvasGroup; `UITheme.label` default Text "" (the word "Label"
  showed); extra SpawnLocations in the place are disabled (players spawned outside); max 2 SEARCH
  markers.
- **2026-09-25** — **🪩 v1.2.0 "THE VAULT"** — Malachi wanted *"a huge inside center where the heist
  spawns you"*; picked option A. New **`ClubBuilder.lua`**: underground neon club HQ under the auto
  shop, x -44..44 / z 0..64 / floor y -27.5 (`WORLD.HUB_*`). DJ stage + LED wall ("THE VAULT") +
  moving truss spots, glass dance floor, bar + VIP mezzanine (stairs by the stage), **holo planning
  table** (blueprint + READY UP (E) / change job (R)) with the job screen hanging above it, crew
  pads + signs (east), **mask wall** (real catalog masks on display heads; shop counter prompt
  `OpenShop`), **trophy room** (`Constants.TROPHIES`, unlocks by the best `heistsCompleted` in the
  server), **garage bay + ramp** (launch cut-scene: a copy of the getaway car rolls up it while
  every camera watches), freight elevator ↔ auto shop (fade + teleport; prompts `ElevatorUp`/
  `ElevatorDown`). **Spawn moved into the club** (0,-27.4,54); Boss at the holo table.
  The auto shop (SafehouseBuilder) is now just the street-level cover business + lift; its old
  pads/table/gear wall/TV functions are kept but not called. Client **`ClubFX`** animates tiles,
  lights, spots and the EQ locally (only while you're in the club). Extras (training course,
  leaderboard wall, arcade) deferred by Malachi — "later when I feel happy".

- **2026-09-25** — **v1.2.1** first spawn put you on the street outside the auto shop: the
  character loads while `HeistBuilder:build()` is still yielding, before the spawn pad moves into
  The Vault. `init.server` now pivots every already-loaded character to `SPAWN_POSITION` (facing
  the holo table) right after the build. Respawns were already fine.

- **2026-09-25** — **v1.2.2** from Studio playtest: holo-table prompt flicker (Boss briefing + Ready up both
  on E, a few studs apart → Roblox flip-flopped) → Boss is now **F**, Ready (E) / Pick heist (R) sit on their
  own attachments on the spawn side of the table. Role pad text was upside down → rotated 180. All Boss
  briefing lines, tips and step text rewritten **so a 7-year-old gets it** (Malachi's bar — keep it that way).
- **2026-09-25** — **v1.2.3 SNEAKY ENTRANCES** (Malachi picked option C over door-step / grace-period):
  launch now drops the crew at a **STAFF ONLY side door** via `refs.sneakIn {at, face, spread}` →
  `JobService.dropPoints` (sidewalk-by-the-car is the fallback). **Villa:** east wall z -57..-53 →
  security room right beside the breaker (no camera there; Guard B's x=20 route is >40° off). East fake
  window at z -57 skipped. **Jewelry:** east alley z 18.3..21.7 → back office (no guard/camera; closet +
  breaker next door; keycard door still gates the safe). Office bookcase moved off the doorway.
- **2026-09-25** — **v1.2.4** from Malachi's first screen recording (`_recordings/roblox.mp4`, gitignored):
  he was **BUSTED at 0:06** — Guard B walked through the security-room doorway right after the drop-in
  and filled the meter in <1s. Fixes: detection 0.4/1.4s → **1.2/3.0s**, **8s drop-in grace**
  (`GuardService.graceUntil`), villa Guard B now patrols the **gallery only**, drop-in moved **INSIDE**
  (villa security room / jewelry back office). His verdict on the build: *"isn't playable… needs to be
  bigger… doesn't give Roblox game"* → pitched a direction (see chat 2026-09-25), awaiting his pick.
- **2026-09-25** — **v1.2.5 KICK-BACK RULE** (Malachi: *"too hard… one guard sees you and they all
  come running, it's confusing"*). A guard spotting/grabbing you in stealth → `kickBack()`: drop bag +
  keycard, teleport to `sneakIn`, guard stunned 3s, **no alarm**, still in the run. Alarm now only from
  cameras / lasers / the jewelry silent alarm; during the loud escape a guard grab is still "caught".
  Kid rule on screen: *guard sees you → back to the door; camera sees you → alarm + police.*
  Still open from the pitch: bigger rooms · more feedback/juice · auto-role · jail/respawn instead of out.

- **2026-09-25** — **🏗️ v2.0 "BIGGER"** — Malachi: *"I love all of that, do it all in one go, no stops, lock in"*
  (after the playtest: too hard, cramped, "doesn't feel like a Roblox game", spawns "outside weird stuff").
  Contract = **`docs/V2_SPEC.md`** (world map v2, attributes/tags, remotes, JobRefs v2, game rules, file ownership).
  Built by 8 parallel agents + an integration tester (mock Roblox runtime in /tmp). What's in it:
  - **4 heists:** `mart` SUNNY'S MART (NEW warm-up, 1 guard, no keycard) · `villa` (rebuilt x -42..42 z -96..-38,
    12 rooms, loops) · `jewelry` (rebuilt x -82..-46 z -1..35) · `bank` OCEAN BANK (NEW, x 84..140 z 1..55, raised
    floor **y 2.0**, round vault). Each has **3 ways in** (front / STAFF ONLY side door / roof ladder+hatch), drop-in
    INSIDE a finished staff room (`refs.sneakIn`), HideSpots, ShadowZones, crawl Vents (`VentService`, reads `Exit`).
  - **Rules:** guard → back to the door (kickBack) · camera/laser → alarm · **police → JAIL** (MiamiBuilder police
    station, 3 cells; teammate holds E to break you out; 30 s) · auto-role at launch · **BotService** AI crewmates
    (<3 players; "Give bag" E → bot loads the car).
  - **Lobby:** real club entrance south of The Vault (6 spawn pads w/ ForceField, bouncer NPC, coat check, signs);
    **4 heist doors** (PortalService: all in → 5 s, half → 15 s) replace ready-up; first-join **IntroCam** fly-over.
  - **Feel:** FeelService/FeelFX money pops + banners + sounds · **crouch (C)** 2× slower detection · shadows 1.6× ·
    hide (E) · guards say "Huh?" at 40% before "HEY!".
  - **Come back:** 7-day DailyReward calendar · 19 cosmetics (bag skins / car colors / trails) · leaderboard wall.
  - **City:** police station, direction signs to every heist, crosswalks, bus stop, alleys, rooftops,
    AmbientService traffic (6 cars) + 10 pedestrians. Beach moved to z -100..-120, marina ring (106,-110).
  - **`tools/check.sh`** = luau-compile syntax check of every file (binary in `~/.claude/bin/`, persists).
  ⚠️ NOT yet played in Studio — first playtest will surface prop orientation (Kenney FRONT_YAW), ladder
  climbability, pathfinding, balance (villa take ~$18.4k).

- **2026-09-25** — **v2.0.1 → v2.1 "LOOKS REAL"** (Malachi's 2nd video: door opened too early, could walk out onto
  ugly green lawn, graphics + UI "very simple / bad"). v2.0.1: portal doors open only at launchIn <= 1.2, "Heist in
  progress" text, bots side-by-side, Give-bag prompt only when carrying. v2.1 (7 agents + tester, 251/251 mock checks):
  - Every heist **walled in** with a SERVICE YARD; the **getaway car parks in the yard** and drives out a gate:
    villa (45.6,0,-72) · jewelry (-42.4,0,13) · mart (78.25,0,10) · bank (135.9,0.25,15), all facing the gate.
  - MiamiBuilder: lawn → dark paved `Ground` + `_cityGround` plazas/parks/lots, `KEEP_CLEAR` rects, Future-tuned
    lighting. KenneyLoader recolours untextured props by name (opts.color/material/recolor, setStyle/styleFor).
    ClubBuilder: steel elevator heist doors. NpcFactory.OUTFITS / outfit() / outfitFor().
  - **UI overhaul:** UITheme slots (topCenter/topRight/rightEdge/left/bottomLeft/bottomCenter) + scale(); one
    objective bar; ≤3 waypoints; tips queue; ShopUI with **real mask pictures (rbxthumb)** + 3D bag/car previews +
    **CASH tab**. Mockup: `docs/mockups/shop-masks-v2.png`.
  - **Mask powers** (MaskService; `Constants.MASKS[i].ability`, `MASK_POWERS`): lucky · toughguy · nightvision ·
    foxspeed · powerthrow · ghost · surprise · hackchip.
  - **Robux cash packs LIVE on Roblox** (RobuxService ProcessReceipt, idempotent): universe **10127256584**,
    products 3714635306 / 3714635777 / 3714635779 / 3714635781 ($5K/25 · $30K/99 · $100K/249 · $500K/799 R$),
    icons in `docs/icons/`. Created + iconed via **Open Cloud** (`~/.claude/roblox-opencloud-key`, scope
    developer-product:read+write; PATCH with multipart `imageFile` sets the icon — no asset scope needed).
  - Malachi must set in Studio: Lighting.Technology = Future; Game Settings → Security → Studio API access ON.

## 📑 Reference docs
- **`docs/ART_DIRECTION.md`** 🆕 2026-09-22 — **read this before building anything visual.**
  The five rules that came out of the "doesn't look like a real Roblox game" screenshot
  (neon is an accent never a surface · light comes from lights not floors · text on surfaces
  or the screen, never floating · every part gets a real Material · bright lobby vs dark
  mansion), Malachi's four reference games and what to take from each, the Track A (code) /
  Track B (art) split, and the `.rbxmx` room-kit spec with attachment naming.
- `docs/mockups/` — v1.0 vision board + game icon (2026-09-01). Design targets, not built.

When sections of this file balloon past ~40 lines, split them into `docs/`:
- `docs/HEIST_DESIGN.md` — detailed level design / loot tables / guard behaviors
- `docs/MONETIZATION.md` — gamepass + dev product price math
- `docs/SOUND_DESIGN.md` — music stings, ambient layers, alarm SFX
- `docs/LAUNCH_PLAYBOOK.md` — TikTok + Discord + soft-launch sequencing
